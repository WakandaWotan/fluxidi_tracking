import { affiliateOperation, affiliateApplicationIdentifiers, AFFILIATE_RATE_BPS } from './affiliate_ledger.mjs';
import { corsHeaders } from './http_response.js';

const text = (value, max = 160) => typeof value === 'string' ? value.trim().slice(0, max) : '';
const reply = (body, status = 200) => Response.json(body, { status, headers: { ...corsHeaders(), 'cache-control': 'private, no-store' } });
const error = (code, status) => reply({ ok: false, error: code }, status);
const enabled = env => env?.AFFILIATE_PROGRAM_ENABLED === '1';
const terms = env => ({ terms_version: text(env?.AFFILIATE_TERMS_VERSION, 80) || null,
  terms_text: text(env?.AFFILIATE_TERMS_TEXT, 12000) || null });
const routes = {
  'GET /affiliate/me': 'overview', 'GET /affiliate/payouts': 'payouts', 'GET /affiliate/referrals': 'referrals',
  'GET /affiliate/entries': 'entries', 'GET /affiliate/bank-account': 'bank_details',
  'POST /affiliate/application': 'application', 'POST /affiliate/bank-account': 'bank_account',
  'POST /affiliate/application/identifiers': 'application_identifiers',
  'POST /affiliate/referrals/claim': 'claim_referral',
};
const adminRoutes = {
  'GET dashboard': 'cc_summary', 'GET directory': 'cc_directory',
  'GET detail': 'cc_detail', 'GET batch-detail': 'cc_batch',
  'GET command-center': 'cc_snapshot',
  'GET applications': 'applications', 'POST applications/review': 'review_application',
  'GET overview': 'admin_overview', 'GET audit': 'audit', 'GET batches': 'batches',
  'GET registrations': 'registrations', 'POST registrations/complete': 'registration_review_complete',
  'GET bank-accounts/detail': 'admin_bank_details', 'POST bank-accounts/verify': 'verify_bank', 'POST owners/review': 'owner_proof',
  'GET receipts/review': 'review_receipts', 'POST receipts/basis': 'review_basis',
  'POST receipts/recover': 'recover_receipt',
  'POST receipts/retry': 'retry_receipt', 'POST batches': 'create_batch',
  'POST batches/export': 'export_batch', 'POST batches/reconcile': 'reconcile_batch',
  'POST batches/cancel': 'cancel_batch',
};

export function affiliateProgramMetadata(env) {
  const legal = terms(env);
  return { program_enabled: enabled(env), ...legal, may_apply: enabled(env) && !!legal.terms_version && !!legal.terms_text,
    commission_rate_bps: AFFILIATE_RATE_BPS, revenue_basis: 'verified_paid_ex_vat_subscriptions_and_addons',
    bank_format_validated: false, automatic_bank_transfers: false };
}

// Company-admin roles and client supplied customer IDs never identify a person.
export async function affiliatePerson(request, env, loadCustomerSession, loadGlobalIdentity) {
  const session = await loadCustomerSession(request, env);
  if (!session || session.purpose !== 'customer_session' || session.tenant_id !== 'global' || session.company_id !== 'global' || !text(session.customer_id)) return null;
  const identity = await loadGlobalIdentity(env, session.customer_id);
  if (identity?.purpose !== 'customer_global_identity' || identity.customer_id !== session.customer_id) return null;
  return session;
}

async function readBody(request) {
  const raw = await request.text();
  if (raw.length > 32768) throw Object.assign(new Error('affiliate_request_too_large'), { status: 413 });
  const body = JSON.parse(raw || '{}');
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error('invalid_body');
  return body;
}

function normalizeIban(value) {
  const iban = text(value, 80).replace(/\s/g, '').toUpperCase();
  if (!/^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$/.test(iban)) return null;
  const shifted = iban.slice(4) + iban.slice(0, 4);
  let remainder = 0;
  for (const character of shifted) {
    const digits = /^[0-9]$/.test(character) ? character : String(character.charCodeAt(0) - 55);
    for (const digit of digits) remainder = (remainder * 10 + Number(digit)) % 97;
  }
  return remainder === 1 ? iban : null;
}
const bankHolder = value => typeof value === 'string' && value.trim() && value.trim().length <= 160 && !/[\x00-\x1f\x7f-\x9f\u2028\u2029]/.test(value) ? value.trim() : null;
const bytesToBase64 = bytes => btoa(String.fromCharCode(...bytes));
const base64ToBytes = value => Uint8Array.from(atob(value), c => c.charCodeAt(0));
async function bankKey(env) {
  const value = text(env?.AFFILIATE_BANK_ENCRYPTION_KEY, 200);
  if (!/^[A-Za-z0-9+/]{43}=$/.test(value)) throw new Error('affiliate_bank_storage_not_configured');
  const bytes = base64ToBytes(value);
  if (bytes.length !== 32) throw new Error('affiliate_bank_storage_not_configured');
  return crypto.subtle.importKey('raw', bytes, 'AES-GCM', false, ['encrypt', 'decrypt']);
}
async function encryptBank(env, personId, bank) {
  const key = await bankKey(env), iv = crypto.getRandomValues(new Uint8Array(12));
  const additionalData = new TextEncoder().encode(`affiliate-bank-v1:${personId}`);
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv, additionalData }, key,
    new TextEncoder().encode(JSON.stringify(bank)));
  return { key_id: 'affiliate-bank-v1', iv: bytesToBase64(iv), ciphertext: bytesToBase64(new Uint8Array(encrypted)) };
}
async function decryptBank(env, personId, bank) {
  if (bank?.key_id !== 'affiliate-bank-v1') throw new Error('affiliate_bank_key_unavailable');
  const plaintext = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: base64ToBytes(bank.iv),
    additionalData: new TextEncoder().encode(`affiliate-bank-v1:${personId}`) }, await bankKey(env), base64ToBytes(bank.ciphertext));
  return JSON.parse(new TextDecoder().decode(plaintext));
}

export async function handleAffiliateRequest({ request, url, env, loadCustomerSession, loadGlobalIdentity, loadCompanyRecord, recoverPayment, completeRegistration, requireAdmin }) {
  const publicPath = url.pathname.startsWith('/affiliate/');
  const adminPath = url.pathname.startsWith('/admin/affiliate/');
  if (!publicPath && !adminPath) return null;
  const historicalCommandCenterRead=request.method==='GET'&&['/affiliate/admin/command-center','/affiliate/admin/batches','/affiliate/admin/batch-detail'].includes(url.pathname);
  if (!enabled(env)&&!historicalCommandCenterRead) return error('affiliate_program_not_enabled', 503);
  if (!env?.AFFILIATE_LEDGER) return error('affiliate_not_configured', 503);
  const personalAdmin = url.pathname.startsWith('/affiliate/admin/');
  let person = null, serverAdmin = false;
  try {
    if (adminPath) { requireAdmin(request, url, env); serverAdmin = true; }
    else {
      person = await affiliatePerson(request, env, loadCustomerSession, loadGlobalIdentity);
      if (!person) return error('affiliate_personal_login_required', 401);
    }
    if (personalAdmin) {
      const capability = await affiliateOperation(env, 'capability', { person_id: person.customer_id });
      if (!capability.ok) return error(capability.error, capability._http_status || capability.status || 503);
      if (capability.role !== 'ceo') return error('affiliate_ceo_required', 403);
    }
  } catch (_) { return error('unauthorized', 401); }
  let body;
  try {
    body = request.method === 'GET' ? { cursor: url.searchParams.get('cursor') || '', affiliate_id: url.searchParams.get('affiliate_id') || '',
      limit: Number(url.searchParams.get('limit') || 20),
      period: url.searchParams.get('period') || '', currency: url.searchParams.get('currency') || '',
      status: url.searchParams.get('status') || '', q: url.searchParams.get('q') || '',
      batch_id: url.searchParams.get('batch_id') || '',
      entries_cursor: url.searchParams.get('entries_cursor') || '',
      referrals_cursor: url.searchParams.get('referrals_cursor') || '',
      receipts_cursor: url.searchParams.get('receipts_cursor') || '',
      payouts_cursor: url.searchParams.get('payouts_cursor') || '' } : await readBody(request);
  } catch (failure) { return error(failure.message === 'affiliate_request_too_large' ? failure.message : 'invalid_body', failure.status || 400); }
  const actor = { actor_id: person?.customer_id || 'server_admin', admin: adminPath || personalAdmin, server_admin: serverAdmin };
  const suffix = adminPath ? url.pathname.slice('/admin/affiliate/'.length) : personalAdmin ? url.pathname.slice('/affiliate/admin/'.length) : null;
  let action = suffix === null ? routes[`${request.method} ${url.pathname}`] : adminRoutes[`${request.method} ${suffix}`];
  if (serverAdmin && suffix === 'capabilities' && request.method === 'POST') {
    const identity = await loadGlobalIdentity(env, text(body.person_id));
    if (identity?.purpose !== 'customer_global_identity' || identity.customer_id !== body.person_id) return error('affiliate_verified_person_required', 400);
    action = 'set_capability';
  }
  if (!action) return error('affiliate_route_not_found', 404);
  if (action === 'registration_review_complete') {
    if (!text(body.review_reference)) return error('affiliate_registration_review_proof_required', 400);
    const record = await affiliateOperation(env, 'registration_review_get', body, actor);
    if (!record.ok) return error(record.error, record._http_status || record.status || 503);
    try {
      const result = await completeRegistration?.(env, record);
      if (!result) return error('affiliate_registration_completion_unproved', 409);
      body = { ...body, result };
    } catch (_) { return error('affiliate_registration_lookup_unavailable', 503); }
  }
  if (action === 'owner_proof' || action === 'claim_referral' || action === 'recover_receipt') {
    const tenant = text(body.tenant_id, 80), company = text(body.company_id, 80);
    if (!tenant || !company || tenant === 'global' || company === 'global' ||
      body.tenant_id !== tenant || body.company_id !== company || !/^[A-Za-z0-9._-]+$/.test(tenant) || !/^[A-Za-z0-9._-]+$/.test(company)) {
      return error('affiliate_company_scope_required', 400);
    }
    try {
      if (!loadCompanyRecord || !await loadCompanyRecord(env, { tenant_id: tenant, company_id: company })) return error('affiliate_company_not_found', 404);
    } catch (_) { return error('affiliate_company_lookup_unavailable', 503); }
  }
  if (action === 'recover_receipt') {
    if (!/^tr_[A-Za-z0-9_]{4,120}$/.test(body.payment_id || '')) return error('affiliate_payment_id_required', 400);
    const current = await affiliateOperation(env, 'capability', { person_id: person?.customer_id || 'server_admin' });
    if (!current.ok) return error(current.error, current._http_status || current.status || 503);
    if (!serverAdmin && current.role !== 'ceo') return error('affiliate_ceo_required', 403);
    try {
      // This actor is derived above from authentication, never from the body.
      // Carry it through provider awaits for a transactional capability check.
      const result = await recoverPayment?.(env, { payment_id: body.payment_id, tenant_id: body.tenant_id, company_id: body.company_id }, actor);
      if (!result?.ok) return error(result?.error || 'affiliate_recovery_unavailable', result?._http_status || result?.status || 503);
      delete result._http_status;
      return reply(result);
    } catch (_) { return error('affiliate_recovery_unavailable', 503); }
  }
  if (action === 'application') {
    const legal = terms(env);
    if (!legal.terms_version || !legal.terms_text) return error('affiliate_terms_not_configured', 503);
    if (body.terms_version !== legal.terms_version || body.accepted !== true) return error('affiliate_terms_required', 400);
    let identifiers;
    try { identifiers = affiliateApplicationIdentifiers(body); }
    catch (failure) { return error(failure.code || 'affiliate_application_identifier_invalid', failure.status || 400); }
    if (body.applicant_type !== 'business' && Object.keys(identifiers).length) return error('affiliate_business_identifiers_only', 400);
    // Pick actual form fields. Auth/revision/role/balance/bank fields are never
    // accepted through application, even if an old or malicious client sends them.
    body = { terms_version: legal.terms_version, accepted: true, display_name: text(body.display_name),
      legal_name: text(body.legal_name), address: text(body.address, 320), country: text(body.country, 2), applicant_type: body.applicant_type,
      ...identifiers };
  }
  if (action === 'application_identifiers') {
    // No identity, status, profile, bank, terms or financial fields cross this
    // boundary. The exact authenticated owner/revision is checked in SQLite.
    let identifiers;
    try { identifiers = affiliateApplicationIdentifiers(body); }
    catch (failure) { return error(failure.code || 'affiliate_application_identifier_invalid', failure.status || 400); }
    body = { expected_revision: body.expected_revision, ...identifiers };
  }
  if (action === 'owner_proof') {
    const identity = await loadGlobalIdentity(env, text(body.person_id));
    if (identity?.purpose !== 'customer_global_identity' || identity.customer_id !== body.person_id) return error('affiliate_verified_person_required', 400);
    // Registration proof is created only by the internal registration hook;
    // a human CEO review remains accurately labelled reviewed evidence.
    body = { ...body, proof_source: 'reviewed_owner_evidence' };
  }
  if (action === 'bank_account') {
    const iban = normalizeIban(body.iban), accountHolder = bankHolder(body.account_holder);
    if (!iban || !accountHolder) return error('affiliate_bank_details_invalid', 400);
    try { body = { expected_revision: body.expected_revision,
      encrypted_bank: await encryptBank(env, person.customer_id, { iban, account_holder: accountHolder }) }; }
    catch (_) { return error('affiliate_bank_storage_not_configured', 503); }
  }
  let decodedExport;
  if (action === 'export_batch') {
    const preview = await affiliateOperation(env, 'preview_export', body, actor);
    if (!preview.ok) return error(preview.error, preview._http_status || preview.status || 503);
    try {
      decodedExport = await Promise.all(preview.items.map(async ({ encrypted_bank, ...item }) => ({ ...item,
        bank_account: await decryptBank(env, item.affiliate_id, encrypted_bank) })));
    } catch (_) { return error('affiliate_bank_key_unavailable', 503); }
  }
  // The export transaction rechecks capability/bank/balance after decryption.
  // A lost key must not leave an unavailable manifest falsely marked exported.
  const result = await affiliateOperation(env, action, body, actor);
  if (!result.ok) return error(result.error, result._http_status || result.status || 503);
  delete result._http_status;
  if(personalAdmin&&['cc_snapshot','cc_batch','batches'].includes(action)){
    const current=await affiliatePerson(request,env,loadCustomerSession,loadGlobalIdentity);
    const capability=await affiliateOperation(env,'capability',{person_id:person?.customer_id});
    if(current?.customer_id!==person?.customer_id||!capability.ok||capability.role!=='ceo')return error('affiliate_authorization_changed',403);
    return reply({...result,capture_enabled:enabled(env)});
  }
  // Private own-account bank view; ciphertext never crosses the public HTTP boundary.
  // The ledger selects by authenticated actor, ignoring supplied affiliate IDs.
  const ownOverview = ['overview', 'application', 'application_identifiers', 'bank_account'].includes(action);
  if (action === 'bank_details' || action === 'admin_bank_details' || (ownOverview && result.bank_revision > 0)) {
    const details = ownOverview ? await affiliateOperation(env, 'bank_details', {}, actor) : result;
    if (!details.ok) return error(details.error, details._http_status || details.status || 503);
    if (ownOverview && (details.revision !== result.revision || details.bank_revision !== result.bank_revision)) return error('affiliate_revision_conflict', 409);
    let bank = null;
    try {
      if (details.encrypted_bank) {
        const decoded = await decryptBank(env, details.affiliate_id, details.encrypted_bank);
        const iban = normalizeIban(decoded.iban), holder = bankHolder(decoded.account_holder);
        if (!iban || !holder) throw Error('invalid_bank_record');
        bank = { iban, account_holder: holder };
      }
    } catch (_) { return error('affiliate_bank_key_unavailable', 503); }
    if (!serverAdmin) {
      if (action === 'admin_bank_details') {
        const capability = await affiliateOperation(env, 'capability', { person_id: person.customer_id });
        if (!capability.ok || capability.role !== 'ceo') return error('affiliate_authorization_changed', 403);
      }
      const current = await affiliatePerson(request, env, loadCustomerSession, loadGlobalIdentity);
      if (current?.customer_id !== person?.customer_id) return error('affiliate_authorization_changed', 403);
    }
    result.bank_account = bank;
    delete result.encrypted_bank;
  }
  if (action === 'overview' || action === 'application' || action === 'application_identifiers' || action === 'bank_account') {
    const capability = await affiliateOperation(env, 'capability', { person_id: person.customer_id });
    const current = await affiliatePerson(request, env, loadCustomerSession, loadGlobalIdentity);
    if (current?.customer_id !== person?.customer_id) return error('affiliate_authorization_changed', 403);
    return reply({ ...result, ...affiliateProgramMetadata(env), can_administer: capability.ok && capability.role === 'ceo' });
  }
  if (action === 'export_batch') {
    result.items = decodedExport;
  }
  return reply(result);
}
