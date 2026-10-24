// Dedicated financial authority. Nothing here scans KV, changes subscriptions,
// sends money, or trusts a public caller's identity/payment amounts.
import { AFFILIATE_ADMIN_READS, affiliateAdminRead } from './affiliate_admin_reads.mjs';
import {stagingTrialDoMarkedV1,stagingTrialDoRefusalV1} from './staging_trial_do_fence_v1.mjs';

export const AFFILIATE_LEDGER_NAME = 'affiliate:platform:v1';
export const AFFILIATE_RATE_BPS = 500;
const text = (value, max = 160) => typeof value === 'string' ? value.trim().slice(0, max) : '';
const integer = value => Number.isSafeInteger(value) && value >= 0;
const json = value => JSON.stringify(value);
const decode = value => value ? JSON.parse(value) : null;
const fail = (error, status = 409) => Object.assign(new Error(error), { code: error, status });
const require = (ok, error, status = 409) => { if (!ok) throw fail(error, status); };
const scopeKey = scope => {
  const tenant = text(scope?.tenant_id, 80), company = text(scope?.company_id, 80);
  require(tenant && company && tenant !== 'global' && company !== 'global', 'affiliate_company_scope_required', 400);
  return json([tenant, company]);
};
const limitOf = value => Math.min(50, Math.max(1, Number.isInteger(value) ? value : 20));
const receiptKey = row => json(['mollie', text(row.payment_id, 128)]);
const targetOf = cents => Number((BigInt(cents) * 500n + 5000n) / 10000n);
const month = iso => /^\d{4}-\d{2}-\d{2}T/.test(iso || '') ? iso.slice(0, 7) : '';
const instant = iso => typeof iso === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?(?:Z|[+-]\d{2}:\d{2})$/.test(iso) ? Date.parse(iso) : NaN;
const validMonth = value => /^\d{4}-(0[1-9]|1[0-2])$/.test(value);
const validCurrency = value => /^[A-Z]{3}$/.test(value || '');

// These optional identifiers are supplied evidence, not inferred or validated
// company/tax ownership. Preserve exact strings and reject rather than truncate.
export function affiliateApplicationIdentifiers(body) {
  const identifiers = {};
  for (const field of ['company_registration_number', 'vat_number']) {
    if (!Object.hasOwn(body, field)) continue;
    const value = body[field];
    require(typeof value === 'string' && value.length <= 64 && !/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(value),
      'affiliate_application_identifier_invalid', 400);
    identifiers[field] = value;
  }
  return identifiers;
}

export class AffiliateLedgerDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sql = state.storage.sql;
    if (stagingTrialDoMarkedV1(env)) return;
    for (const statement of [
      `CREATE TABLE IF NOT EXISTS affiliates (id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL, revision INTEGER NOT NULL, terms_version TEXT NOT NULL,
        profile TEXT NOT NULL, bank TEXT, bank_revision INTEGER NOT NULL DEFAULT 0,
        bank_verified INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)`,
      `CREATE INDEX IF NOT EXISTS affiliates_status ON affiliates(status,id)`,
      `CREATE TABLE IF NOT EXISTS capabilities (person_id TEXT PRIMARY KEY, role TEXT NOT NULL, updated_at TEXT NOT NULL)`,
      `CREATE TABLE IF NOT EXISTS owner_proofs (scope TEXT PRIMARY KEY, person_id TEXT NOT NULL,
        proof TEXT NOT NULL, recorded_at TEXT NOT NULL)`,
      `CREATE TABLE IF NOT EXISTS attributions (scope TEXT PRIMARY KEY, affiliate_id TEXT NOT NULL,
        state TEXT NOT NULL, revision INTEGER NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)`,
      `CREATE INDEX IF NOT EXISTS attributions_affiliate ON attributions(affiliate_id,scope)`,
      `CREATE TABLE IF NOT EXISTS referral_claims (id TEXT PRIMARY KEY, scope TEXT NOT NULL,
        claimant_id TEXT NOT NULL, affiliate_id TEXT NOT NULL, state TEXT NOT NULL,
        created_at TEXT NOT NULL, UNIQUE(scope,claimant_id))`,
      `CREATE INDEX IF NOT EXISTS referral_claims_affiliate ON referral_claims(affiliate_id,id)`,
      `CREATE TABLE IF NOT EXISTS registrations (id TEXT PRIMARY KEY, person_id TEXT NOT NULL,
        payload_hash TEXT NOT NULL, scope TEXT NOT NULL UNIQUE, affiliate_id TEXT NOT NULL,
        state TEXT NOT NULL, revision INTEGER NOT NULL DEFAULT 1, result TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)`,
      `CREATE INDEX IF NOT EXISTS registrations_state ON registrations(state,id)`,
      `CREATE TABLE IF NOT EXISTS receipts (id TEXT PRIMARY KEY, scope TEXT NOT NULL, payment_id TEXT NOT NULL UNIQUE,
        receipt TEXT NOT NULL, basis TEXT, state TEXT NOT NULL, reason TEXT NOT NULL,
        target INTEGER NOT NULL DEFAULT 0, affiliate_id TEXT, revision INTEGER NOT NULL,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL)`,
      `CREATE INDEX IF NOT EXISTS receipts_review ON receipts(state,id)`,
      `CREATE INDEX IF NOT EXISTS receipts_affiliate ON receipts(affiliate_id,state,id)`,
      `CREATE INDEX IF NOT EXISTS receipts_scope_review ON receipts(scope,state,id)`,
      `CREATE INDEX IF NOT EXISTS receipts_scope_id ON receipts(scope,id)`,
      `CREATE TABLE IF NOT EXISTS entries (id INTEGER PRIMARY KEY AUTOINCREMENT, affiliate_id TEXT NOT NULL,
        currency TEXT NOT NULL, cents INTEGER NOT NULL, receipt_id TEXT, receipt_revision INTEGER,
        kind TEXT NOT NULL, period TEXT NOT NULL, created_at TEXT NOT NULL,
        UNIQUE(receipt_id,receipt_revision))`,
      `CREATE INDEX IF NOT EXISTS entries_balance ON entries(affiliate_id,currency,period,id)`,
      `CREATE TABLE IF NOT EXISTS batches (id TEXT PRIMARY KEY, period TEXT NOT NULL, currency TEXT NOT NULL,
        manifest_hash TEXT NOT NULL, manifest TEXT NOT NULL, created_at TEXT NOT NULL)`,
      `CREATE TABLE IF NOT EXISTS payouts (id TEXT PRIMARY KEY, batch_id TEXT NOT NULL,
        affiliate_id TEXT NOT NULL, period TEXT NOT NULL, currency TEXT NOT NULL, cents INTEGER NOT NULL,
        state TEXT NOT NULL, bank_revision INTEGER NOT NULL, bank TEXT NOT NULL,
        execution_reference TEXT, updated_at TEXT NOT NULL)`,
      `CREATE INDEX IF NOT EXISTS payouts_affiliate ON payouts(affiliate_id,id)`,
      `CREATE INDEX IF NOT EXISTS payouts_period ON payouts(affiliate_id,period,currency)`,
      `CREATE TABLE IF NOT EXISTS executions (reference TEXT PRIMARY KEY, payout_id TEXT NOT NULL,
        result TEXT NOT NULL, evidence TEXT NOT NULL, recorded_at TEXT NOT NULL)`,
      `CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY AUTOINCREMENT, actor TEXT NOT NULL,
        action TEXT NOT NULL, subject TEXT NOT NULL, detail TEXT NOT NULL, recorded_at TEXT NOT NULL)`,
    ]) this.sql.exec(statement);
  }

  rows(statement, ...params) { return [...this.sql.exec(statement, ...params)]; }
  one(statement, ...params) { return this.rows(statement, ...params)[0] || null; }
  audit(actor, action, subject, detail, now) {
    this.sql.exec('INSERT INTO audit(actor,action,subject,detail,recorded_at) VALUES (?,?,?,?,?)',
      actor, action, subject, json(detail), now);
  }
  person(id) {
    const row = this.one('SELECT * FROM affiliates WHERE id=?', text(id));
    require(row, 'affiliate_not_enrolled', 404);
    return row;
  }
  expected(row, revision) { require(Number.isInteger(revision) && row.revision === revision, 'affiliate_revision_conflict'); }

  async fetch(request) {
    const stagingRefusal=stagingTrialDoRefusalV1(this.env);
    if(stagingRefusal)return stagingRefusal;
    if (request.method !== 'POST') return Response.json({ ok: false, error: 'method_not_allowed' }, { status: 405 });
    let input;
    try {
      const raw = await request.text();
      require(raw.length <= 65536, 'affiliate_request_too_large', 413);
      input = JSON.parse(raw);
      require(input && typeof input === 'object' && !Array.isArray(input), 'invalid_body', 400);
    } catch (error) { return Response.json({ ok: false, error: error.code || 'invalid_body' }, { status: error.status || 400 }); }
    try {
      // No await inside the SQL transaction: dedup, target/delta, summary and
      // payout reservations commit together or roll back together.
      const result = this.state.storage.transactionSync(() => this.operation(input));
      return Response.json({ ok: true, ...result });
    } catch (error) {
      return Response.json({ ok: false, error: error.code || 'affiliate_storage_unavailable' }, { status: error.status || 503 });
    }
  }

  operation(input) {
    const now = new Date().toISOString();
    const action = text(input.action, 64), actor = text(input.actor_id);
    const body = input.body || {};
    require(actor || ['receipt', 'capability'].includes(action), 'affiliate_actor_required', 401);
    if (action === 'capability') return { role: this.one('SELECT role FROM capabilities WHERE person_id=?', text(body.person_id))?.role || null };
    if (action === 'set_capability') {
      require(input.server_admin === true, 'affiliate_admin_required', 403);
      require(text(body.person_id) && ['ceo', 'none'].includes(body.role), 'invalid_capability', 400);
      this.sql.exec('INSERT INTO capabilities(person_id,role,updated_at) VALUES (?,?,?) ON CONFLICT(person_id) DO UPDATE SET role=excluded.role,updated_at=excluded.updated_at', body.person_id, body.role, now);
      this.audit(actor, action, body.person_id, { role: body.role }, now);
      return { role: body.role };
    }
    if (action === 'application') {
      require(text(body.terms_version, 80) && body.accepted === true, 'affiliate_terms_required', 400);
      require(text(body.display_name, 160), 'affiliate_name_required', 400);
      const identifiers = affiliateApplicationIdentifiers(body);
      require(body.applicant_type === 'business' || Object.keys(identifiers).length === 0, 'affiliate_business_identifiers_only', 400);
      const profile = { display_name: text(body.display_name), legal_name: text(body.legal_name),
        country: text(body.country, 2).toUpperCase(), address: text(body.address, 320),
        applicant_type: ['person', 'business'].includes(body.applicant_type) ? body.applicant_type : 'person',
        accepted_at: now, ...identifiers };
      const existing = this.one('SELECT * FROM affiliates WHERE id=?', actor);
      if (existing) {
        require(existing.terms_version === body.terms_version, 'affiliate_terms_update_requires_review');
        return this.overview(actor);
      }
      const code = 'FLA-' + crypto.randomUUID().replaceAll('-', '').slice(0, 16).toUpperCase();
      this.sql.exec('INSERT INTO affiliates(id,code,status,revision,terms_version,profile,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',
        actor, code, 'pending', 1, body.terms_version, json(profile), now, now);
      this.audit(actor, action, actor, { terms_version: body.terms_version }, now);
      return this.overview(actor);
    }
    if (action === 'application_identifiers') {
      const affiliate = this.person(actor);
      // Owner and current revision must match even when values are unchanged.
      this.expected(affiliate, body.expected_revision);
      const profile = decode(affiliate.profile);
      require(affiliate.status === 'pending' && profile && typeof profile === 'object' && !Array.isArray(profile) &&
        profile.applicant_type === 'business', 'affiliate_pending_business_required');
      const identifiers = affiliateApplicationIdentifiers(body), fields = Object.keys(identifiers);
      require(fields.length > 0, 'affiliate_application_identifiers_required', 400);
      if (fields.every(field => profile[field] === identifiers[field])) return { ...this.overview(actor), idempotent: true };
      const revision = affiliate.revision + 1;
      this.sql.exec('UPDATE affiliates SET profile=?,revision=?,updated_at=? WHERE id=?',
        json({ ...profile, ...identifiers }), revision, now, actor);
      this.audit(actor, action, actor, { fields, revision }, now);
      return { ...this.overview(actor), idempotent: false };
    }
    if (action === 'overview') return this.overview(actor);
    if (action === 'bank_details') return this.bankDetails(actor);
    if (action === 'registration_prepare') {
      require(text(body.request_id, 80) && /^[A-Za-z0-9_-]{16,80}$/.test(body.request_id) &&
        /^[a-f0-9]{64}$/.test(body.payload_hash || ''), 'affiliate_registration_id_required', 400);
      const id = json([actor, body.request_id]), old = this.one('SELECT * FROM registrations WHERE id=?', id);
      if (old) {
        require(old.payload_hash === body.payload_hash, 'affiliate_registration_identity_locked');
        return { registration_id: id, state: old.state, scope: decode(old.scope), result: decode(old.result), idempotent: true };
      }
      const affiliate = this.one('SELECT * FROM affiliates WHERE code=? AND status=?', text(body.referral_code, 40).toUpperCase(), 'active');
      require(affiliate, 'affiliate_referral_unavailable', 404);
      require(affiliate.id !== actor, 'affiliate_self_referral', 403);
      const scope = scopeKey(body.scope), claimId = json([scope, actor]);
      this.sql.exec('INSERT INTO registrations(id,person_id,payload_hash,scope,affiliate_id,state,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?)',
        id, actor, body.payload_hash, scope, affiliate.id, 'prepared', now, now);
      this.sql.exec('INSERT INTO referral_claims(id,scope,claimant_id,affiliate_id,state,created_at) VALUES (?,?,?,?,?,?)',
        claimId, scope, actor, affiliate.id, 'held_owner_review', now);
      this.audit(actor, action, id, { state: 'held_owner_review', scope: decode(scope) }, now);
      return { registration_id: id, state: 'prepared', scope: decode(scope), idempotent: false };
    }
    if (action === 'registration_begin' || action === 'registration_complete') {
      const row = this.one('SELECT * FROM registrations WHERE id=? AND person_id=?', text(body.registration_id, 500), actor);
      require(row, 'affiliate_registration_not_found', 404);
      if (action === 'registration_begin') {
        require(row.state === 'prepared', 'affiliate_registration_in_progress');
        this.sql.exec('UPDATE registrations SET state=?,revision=revision+1,updated_at=? WHERE id=?', 'writing', now, row.id);
        return { state: 'writing' };
      }
      require(body.result && body.result.tenant_id === decode(row.scope)[0] && body.result.company_id === decode(row.scope)[1] &&
        !body.result.company_session_token && !body.result.companySessionToken, 'affiliate_registration_result_invalid', 400);
      if (row.state === 'completed') { require(row.result === json(body.result), 'affiliate_registration_identity_locked'); return { idempotent: true }; }
      require(row.state === 'writing', 'affiliate_registration_not_started');
      this.sql.exec('UPDATE registrations SET state=?,result=?,revision=revision+1,updated_at=? WHERE id=?', 'completed', json(body.result), now, row.id);
      this.audit(actor, action, row.id, { state: 'completed' }, now);
      return { state: 'completed' };
    }
    if (action === 'payouts') return this.page('payouts', actor, body);
    if (action === 'entries') {
      this.person(actor); const limit = limitOf(body.limit), cursor = Number(body.cursor || 0);
      require(Number.isSafeInteger(cursor) && cursor >= 0, 'affiliate_cursor_invalid', 400);
      const rows = this.rows('SELECT id,currency,cents,kind,period,created_at FROM entries WHERE affiliate_id=? AND id>? ORDER BY id LIMIT ?', actor, cursor, limit + 1);
      return { items: rows.slice(0, limit), next_cursor: rows.length > limit ? String(rows[limit - 1].id) : null };
    }
    if (action === 'referrals') return this.page('referrals', actor, body);
    if (action === 'bank_account') {
      const affiliate = this.person(actor);
      this.expected(affiliate, body.expected_revision);
      require(body.encrypted_bank && text(body.encrypted_bank.ciphertext, 4000) && text(body.encrypted_bank.key_id, 80), 'encrypted_bank_required', 400);
      const revision = affiliate.revision + 1;
      this.sql.exec('UPDATE affiliates SET bank=?,bank_revision=bank_revision+1,bank_verified=0,revision=?,updated_at=? WHERE id=?',
        json(body.encrypted_bank), revision, now, actor);
      this.audit(actor, action, actor, { bank_revision: affiliate.bank_revision + 1 }, now);
      return this.overview(actor);
    }
    if (action === 'claim_referral') {
      const key = scopeKey(body), code = text(body.referral_code, 40).toUpperCase();
      const affiliate = this.one('SELECT * FROM affiliates WHERE code=? AND status=?', code, 'active');
      require(affiliate, 'affiliate_referral_unavailable', 404);
      require(affiliate.id !== actor, 'affiliate_self_referral', 403);
      const proof = this.one('SELECT * FROM owner_proofs WHERE scope=?', key);
      const verifiedOwner = proof?.person_id === actor;
      require(!proof || proof.person_id !== affiliate.id, 'affiliate_self_referral', 403);
      const old = this.one('SELECT * FROM attributions WHERE scope=?', key);
      if (old) {
        require(verifiedOwner, 'affiliate_company_owner_required', 403);
        require(old.affiliate_id === affiliate.id, 'affiliate_attribution_locked');
        return { state: old.state, revision: old.revision };
      }
      const state = verifiedOwner ? 'active' : 'held_owner_review';
      if (!verifiedOwner) {
        const claimId = json([key, actor]);
        const claim = this.one('SELECT * FROM referral_claims WHERE id=?', claimId);
        if (claim) require(claim.affiliate_id === affiliate.id, 'affiliate_claim_choice_requires_review');
        else {
          this.sql.exec('INSERT INTO referral_claims(id,scope,claimant_id,affiliate_id,state,created_at) VALUES (?,?,?,?,?,?)',
            claimId, key, actor, affiliate.id, state, now);
          this.audit(actor, action, claimId, { state, affiliate_id: affiliate.id }, now);
        }
        // An unproved caller cannot occupy another company's authoritative
        // attribution or prevent its actual owner from selecting a referral.
        return { state, revision: 0 };
      }
      this.sql.exec('INSERT INTO attributions(scope,affiliate_id,state,revision,created_at,updated_at) VALUES (?,?,?,?,?,?)', key, affiliate.id, state, 1, now, now);
      this.audit(actor, action, key, { state, affiliate_id: affiliate.id }, now);
      // Bounded SQL outbox recovery; no KV list or recurring global sweep.
      for (const receipt of this.rows('SELECT id FROM receipts WHERE scope=? AND state=? ORDER BY id LIMIT 50', key, 'held_review')) this.process(receipt.id, now);
      return { state, revision: 1 };
    }
    if (action === 'receipt') return this.receive(body, now);

    require(input.admin === true, 'affiliate_admin_required', 403);
    // Re-check the personal capability inside the same transaction as the
    // financial mutation; revocation during HTTP awaits must win.
    require(input.server_admin === true || this.one('SELECT role FROM capabilities WHERE person_id=?', actor)?.role === 'ceo', 'affiliate_ceo_required', 403);
    if (AFFILIATE_ADMIN_READS.has(action)) return affiliateAdminRead(this, action, body);
    if (action === 'recovery_receipt') return this.receive(body, now);
    if (action === 'registrations') {
      const limit = limitOf(body.limit);
      const rows = this.rows('SELECT id,person_id,payload_hash,scope,affiliate_id,state,revision,created_at,updated_at FROM registrations WHERE state=? AND id>? ORDER BY id LIMIT ?', 'writing', text(body.cursor, 500), limit + 1);
      return { items: rows.slice(0, limit).map(({ id, scope, ...row }) => ({ registration_id: id, ...row, scope: { tenant_id: decode(scope)[0], company_id: decode(scope)[1] } })), next_cursor: rows.length > limit ? rows[limit - 1].id : null };
    }
    if (action === 'registration_review_get' || action === 'registration_review_complete') {
      const row = this.one('SELECT * FROM registrations WHERE id=?', text(body.registration_id, 500));
      require(row, 'affiliate_registration_not_found', 404); this.expected(row, body.expected_revision);
      require(row.state === 'writing' && row.payload_hash === body.payload_hash, 'affiliate_registration_review_conflict');
      if (action === 'registration_review_get') return { registration_id: row.id, person_id: row.person_id, payload_hash: row.payload_hash,
        scope: { tenant_id: decode(row.scope)[0], company_id: decode(row.scope)[1] }, revision: row.revision, state: row.state };
      require(text(body.review_reference) && body.result?.tenant_id === decode(row.scope)[0] && body.result?.company_id === decode(row.scope)[1] &&
        !body.result.company_session_token && !body.result.companySessionToken, 'affiliate_registration_review_proof_required', 400);
      this.sql.exec('UPDATE registrations SET state=?,result=?,revision=revision+1,updated_at=? WHERE id=?', 'completed', json(body.result), now, row.id);
      this.audit(actor, action, row.id, { review_reference: text(body.review_reference), payload_hash: row.payload_hash,
        person_id: row.person_id, scope: decode(row.scope) }, now);
      return { registration_id: row.id, state: 'completed', revision: row.revision + 1 };
    }
    if (action === 'admin_bank_details') {
      const result = this.bankDetails(text(body.affiliate_id));
      this.audit(actor, action, result.affiliate_id, { bank_revision: result.bank_revision }, now);
      return result;
    }
    if (action === 'admin_overview') return this.overview(text(body.affiliate_id));
    if (action === 'audit') {
      const limit = limitOf(body.limit), cursor = Number(body.cursor || 0);
      require(Number.isSafeInteger(cursor) && cursor >= 0, 'affiliate_cursor_invalid', 400);
      const rows = this.rows('SELECT id,actor,action,subject,detail,recorded_at FROM audit WHERE id>? ORDER BY id LIMIT ?', cursor, limit + 1);
      return { items: rows.slice(0, limit).map(row => ({ ...row, detail: decode(row.detail) })), next_cursor: rows.length > limit ? String(rows[limit - 1].id) : null };
    }
    if (action === 'batches') {
      const limit = limitOf(body.limit);
      const rows = this.rows('SELECT id,period,currency,manifest_hash,created_at FROM batches WHERE id>? ORDER BY id LIMIT ?', text(body.cursor), limit + 1);
      return { items: rows.slice(0, limit), next_cursor: rows.length > limit ? rows[limit - 1].id : null };
    }
    if (action === 'applications') {
      const rows = this.rows('SELECT id,status,revision,profile,bank_revision,bank_verified,created_at,updated_at FROM affiliates WHERE id>? ORDER BY id LIMIT ?', text(body.cursor), limitOf(body.limit) + 1);
      const limit = limitOf(body.limit), hasMore = rows.length > limit;
      return { items: rows.slice(0, limit).map(row => ({ ...row, profile: decode(row.profile) })), next_cursor: hasMore ? rows[limit - 1].id : null };
    }
    if (action === 'review_application') {
      const person = this.person(body.affiliate_id); this.expected(person, body.expected_revision);
      require(['active', 'rejected', 'suspended'].includes(body.status) && text(body.review_reference), 'affiliate_review_required', 400);
      this.sql.exec('UPDATE affiliates SET status=?,revision=revision+1,updated_at=? WHERE id=?', body.status, now, person.id);
      this.audit(actor, action, person.id, { status: body.status, review_reference: text(body.review_reference) }, now);
      return { status: body.status, revision: person.revision + 1 };
    }
    if (action === 'verify_bank') {
      const person = this.person(body.affiliate_id); this.expected(person, body.expected_revision);
      require(person.bank && body.bank_revision === person.bank_revision && text(body.verification_reference), 'affiliate_bank_review_required');
      this.sql.exec('UPDATE affiliates SET bank_verified=1,revision=revision+1,updated_at=? WHERE id=?', now, person.id);
      this.audit(actor, action, person.id, { bank_revision: person.bank_revision, verification_reference: text(body.verification_reference) }, now);
      return { bank_verified: true, revision: person.revision + 1 };
    }
    if (action === 'owner_proof') {
      const key = scopeKey(body);
      require(text(body.person_id) && text(body.proof_reference) && ['verified_registration', 'reviewed_owner_evidence'].includes(body.proof_source), 'affiliate_owner_proof_required', 400);
      const old = this.one('SELECT * FROM owner_proofs WHERE scope=?', key);
      if (old) { require(old.person_id === body.person_id, 'affiliate_owner_proof_locked'); return { idempotent: true }; }
      const attribution = this.one('SELECT * FROM attributions WHERE scope=?', key);
      require(!attribution || attribution.affiliate_id !== body.person_id, 'affiliate_self_referral', 403);
      this.sql.exec('INSERT INTO owner_proofs(scope,person_id,proof,recorded_at) VALUES (?,?,?,?)', key, body.person_id,
        json({ source: body.proof_source, reference: text(body.proof_reference), actor }), now);
      this.audit(actor, action, key, { person_id: body.person_id, source: body.proof_source, proof_reference: text(body.proof_reference) }, now);
      return { state: 'verified' };
    }
    if (action === 'review_receipts') {
      const limit = limitOf(body.limit);
      const rows = this.rows('SELECT id,receipt,state,reason,revision,affiliate_id,target FROM receipts WHERE state=? AND id>? ORDER BY id LIMIT ?', 'held_review', text(body.cursor), limit + 1);
      return { items: rows.slice(0, limit).map(row => ({ ...row, receipt: decode(row.receipt) })), next_cursor: rows.length > limit ? rows[limit - 1].id : null };
    }
    if (action === 'review_basis') {
      const id = receiptKey(body), row = this.one('SELECT * FROM receipts WHERE id=?', id);
      require(row, 'affiliate_receipt_not_found', 404); this.expected(row, body.expected_revision);
      const receipt = decode(row.receipt), basis = body.basis;
      require(receipt.mode === 'live' && receipt.verified === true && receipt.payment_status === 'paid' &&
        (receipt.charged_back_gross_cents || 0) === 0, 'affiliate_payment_not_eligible');
      require(basis && basis.source === 'reviewed_invoice' && text(basis.reference) && basis.currency === receipt.currency,
        'affiliate_net_basis_proof_required', 400);
      require(integer(basis.ex_vat_cents) && integer(basis.vat_cents) && basis.ex_vat_cents + basis.vat_cents === receipt.gross_cents,
        'affiliate_basis_amount_conflict');
      require(integer(basis.refunded_ex_vat_cents) && integer(basis.refunded_vat_cents) &&
        basis.refunded_ex_vat_cents + basis.refunded_vat_cents === receipt.refunded_gross_cents &&
        basis.refunded_ex_vat_cents <= basis.ex_vat_cents && basis.refunded_vat_cents <= basis.vat_cents,
        'affiliate_refund_basis_conflict');
      require(receipt.refunded_gross_cents === 0 || (body.correction_policy_approved === true && text(basis.credit_reference)),
        'affiliate_correction_policy_review_required');
      const previous = decode(row.basis);
      require(!previous || (previous.ex_vat_cents === basis.ex_vat_cents && previous.vat_cents === basis.vat_cents && previous.reference === basis.reference),
        'affiliate_original_basis_locked');
      const trusted = { source: 'reviewed_invoice', reference: text(basis.reference), currency: basis.currency,
        ex_vat_cents: basis.ex_vat_cents, vat_cents: basis.vat_cents,
        refunded_ex_vat_cents: basis.refunded_ex_vat_cents, refunded_vat_cents: basis.refunded_vat_cents,
        credit_reference: text(basis.credit_reference), reviewed_by: actor, reviewed_at: now };
      this.sql.exec('UPDATE receipts SET basis=?,revision=revision+1,updated_at=? WHERE id=?', json(trusted), now, id);
      this.audit(actor, action, id, { reference: trusted.reference, credit_reference: trusted.credit_reference }, now);
      return this.process(id, now);
    }
    if (action === 'retry_receipt') {
      const id = receiptKey(body); require(this.one('SELECT id FROM receipts WHERE id=?', id), 'affiliate_receipt_not_found', 404);
      return this.process(id, now);
    }
    if (action === 'create_batch') return this.createBatch(body, actor, now);
    if (action === 'export_batch' || action === 'preview_export') {
      const batch = this.one('SELECT * FROM batches WHERE id=?', text(body.batch_id));
      require(batch && batch.manifest_hash === body.manifest_hash, 'affiliate_batch_proof_conflict');
      const payouts = this.rows('SELECT * FROM payouts WHERE batch_id=? ORDER BY id', batch.id);
      for (const payout of payouts) {
        require(['approved', 'exported', 'failed'].includes(payout.state), 'affiliate_batch_not_exportable');
        require(!this.one('SELECT id FROM receipts WHERE affiliate_id=? AND state=? LIMIT 1', payout.affiliate_id, 'held_review'), 'affiliate_payout_has_unresolved_receipt');
        const affiliate = this.person(payout.affiliate_id);
        require(affiliate.status === 'active', 'affiliate_payout_approval_required');
        require(affiliate.bank_verified === 1 && affiliate.bank_revision === payout.bank_revision, 'affiliate_bank_changed_since_batch');
        const balance = this.one('SELECT COALESCE(SUM(cents),0) AS cents FROM entries WHERE affiliate_id=? AND currency=?', payout.affiliate_id, payout.currency).cents;
        const reserved = this.one("SELECT COALESCE(SUM(cents),0) AS cents FROM payouts WHERE affiliate_id=? AND currency=? AND state IN ('approved','exported','failed')", payout.affiliate_id, payout.currency).cents;
        require(Number.isSafeInteger(balance) && Number.isSafeInteger(reserved) && balance >= reserved, 'affiliate_payout_balance_changed_since_batch');
      }
      if (action === 'export_batch') {
        this.sql.exec("UPDATE payouts SET state=?,updated_at=? WHERE batch_id=? AND state IN ('approved','failed')", 'exported', now, batch.id);
        this.audit(actor, action, batch.id, { manifest_hash: batch.manifest_hash }, now);
      }
      return { batch_id: batch.id, manifest_hash: batch.manifest_hash, format: 'review_manifest_v1',
        bank_format_validated: false, items: payouts.map(p => ({ payout_id: p.id, affiliate_id: p.affiliate_id,
          cents: p.cents, currency: p.currency, bank_revision: p.bank_revision, encrypted_bank: decode(p.bank) })) };
    }
    if (action === 'cancel_batch') {
      const batch = this.one('SELECT * FROM batches WHERE id=?', text(body.batch_id));
      require(batch && batch.manifest_hash === body.manifest_hash, 'affiliate_batch_proof_conflict');
      require(text(body.review_reference), 'affiliate_cancellation_review_required', 400);
      const payouts = this.rows('SELECT * FROM payouts WHERE batch_id=? ORDER BY id', batch.id);
      require(payouts.length > 0 && payouts.every(payout => ['approved', 'failed', 'cancelled'].includes(payout.state)), 'affiliate_exported_batch_cancellation_requires_bank_proof');
      for (const payout of payouts) if (payout.state === 'failed') {
        const execution = this.one('SELECT * FROM executions WHERE reference=? AND payout_id=?', payout.execution_reference, payout.id);
        require(execution?.result === 'failed', 'affiliate_failed_execution_proof_required');
      }
      const idempotent = payouts.every(payout => payout.state === 'cancelled');
      if (idempotent) {
        const prior = this.one('SELECT detail FROM audit WHERE action=? AND subject=? ORDER BY id LIMIT 1', action, batch.id);
        require(decode(prior?.detail)?.review_reference === text(body.review_reference), 'affiliate_cancellation_identity_locked');
      }
      if (!idempotent) {
        this.sql.exec("UPDATE payouts SET state=?,updated_at=? WHERE batch_id=? AND state IN ('approved','failed')", 'cancelled', now, batch.id);
        this.audit(actor, action, batch.id, { manifest_hash: batch.manifest_hash, review_reference: text(body.review_reference) }, now);
      }
      // Only reservations are released. No cash/commission entry changes and
      // no bank instruction is sent or silently withdrawn.
      return { batch_id: batch.id, state: 'cancelled', idempotent };
    }
    if (action === 'reconcile_batch') return this.reconcile(body, actor, now);
    throw fail('affiliate_action_not_found', 404);
  }

  bankDetails(id) {
    const person = this.person(id);
    return { affiliate_id: person.id, revision: person.revision,
      bank_revision: person.bank_revision, bank_verified: person.bank_verified === 1,
      encrypted_bank: decode(person.bank) };
  }

  overview(id) {
    const person = this.one('SELECT * FROM affiliates WHERE id=?', id);
    if (!person) return { status: 'not_enrolled', affiliate_id: id, revision: 0, balances: [], bank_verified: false };
    const balances = this.rows('SELECT currency,SUM(cents) AS balance_cents FROM entries WHERE affiliate_id=? GROUP BY currency ORDER BY currency', id);
    for (const balance of balances) {
      const reserved = this.one("SELECT COALESCE(SUM(cents),0) AS cents FROM payouts WHERE affiliate_id=? AND currency=? AND state IN ('approved','exported','failed')", id, balance.currency).cents;
      const paid = this.one("SELECT COALESCE(SUM(cents),0) AS cents FROM payouts WHERE affiliate_id=? AND currency=? AND state='paid'", id, balance.currency).cents;
      balance.reserved_cents = reserved; balance.available_cents = Math.max(0, balance.balance_cents - reserved); balance.paid_cents = paid;
    }
    return { affiliate_id: id, status: person.status, revision: person.revision,
      referral_code: person.status === 'active' ? person.code : null, profile: decode(person.profile),
      terms_version: person.terms_version, bank_revision: person.bank_revision, bank_verified: person.bank_verified === 1,
      balances, referred_companies: this.one('SELECT COUNT(*) AS count FROM attributions WHERE affiliate_id=?', id).count,
      held_receipts: this.one('SELECT COUNT(*) AS count FROM receipts WHERE affiliate_id=? AND state=?', id, 'held_review').count,
      updated_at: person.updated_at };
  }

  page(type, id, body) {
    this.person(id); const limit = limitOf(body.limit), cursor = text(body.cursor, 500);
    const rows = type === 'payouts'
      ? this.rows('SELECT id,period,currency,cents,state,updated_at FROM payouts WHERE affiliate_id=? AND id>? ORDER BY id LIMIT ?', id, cursor, limit + 1)
      : this.rows(`SELECT scope AS id,state,revision,created_at FROM attributions WHERE affiliate_id=? AND scope>?
          UNION ALL SELECT id,state,0 AS revision,created_at FROM referral_claims WHERE affiliate_id=? AND id>?
          AND NOT EXISTS(SELECT 1 FROM attributions WHERE attributions.scope=referral_claims.scope)
          ORDER BY id LIMIT ?`, id, cursor, id, cursor, limit + 1);
    const items = rows.slice(0, limit).map(row => type === 'payouts' ? row : {
      referral_id: row.id, state: row.state, revision: row.revision, created_at: row.created_at });
    // No customer names, contacts, payment amounts or full tenant records.
    return { items, next_cursor: rows.length > limit ? rows[limit - 1].id : null };
  }

  receive(receipt, now) {
    require(receipt.verified === true && receipt.provider === 'mollie' && text(receipt.payment_id, 128), 'affiliate_verified_receipt_required', 400);
    require(['subscription_initial', 'subscription_recurring', 'subscription_addon'].includes(receipt.kind), 'affiliate_payment_kind_refused', 400);
    receipt = { ...receipt, charged_back_gross_cents: receipt.charged_back_gross_cents ?? 0 };
    require(validCurrency(receipt.currency) && integer(receipt.gross_cents) && integer(receipt.refunded_gross_cents) &&
      integer(receipt.charged_back_gross_cents) && receipt.refunded_gross_cents <= receipt.gross_cents &&
      receipt.charged_back_gross_cents <= receipt.gross_cents, 'affiliate_receipt_amount_invalid', 400);
    const scope = scopeKey(receipt), id = receiptKey(receipt), forward = receipt.forward_basis;
    const policyVersion = text(this.env.AFFILIATE_CHECKOUT_BASIS_POLICY_VERSION, 80);
    const provedForward = policyVersion && forward?.version === 'checkout_net_vat_v1' && forward.derivation_version === policyVersion &&
      text(forward.review_reference) && text(forward.reference) && receipt.scope_verified === true && receipt.mode === 'live' &&
      forward.tenant_id === receipt.tenant_id && forward.company_id === receipt.company_id && forward.kind === receipt.kind &&
      forward.currency === receipt.currency && forward.gross_cents === receipt.gross_cents && integer(forward.ex_vat_cents) && integer(forward.vat_cents) &&
      forward.ex_vat_cents + forward.vat_cents === receipt.gross_cents &&
      (receipt.kind === 'subscription_recurring' ? text(receipt.provider_subscription_id).startsWith('sub_') && forward.provider_subscription_id === receipt.provider_subscription_id
        : !!text(receipt.activation_id) && forward.activation_id === receipt.activation_id);
    const forwardBasis = provedForward ? { source: 'reviewed_checkout_net_vat_v1', reference: text(forward.reference), currency: receipt.currency,
      ex_vat_cents: forward.ex_vat_cents, vat_cents: forward.vat_cents, refunded_ex_vat_cents: 0, refunded_vat_cents: 0,
      derivation_version: policyVersion, review_reference: text(forward.review_reference), reviewed_by: 'checkout_snapshot', reviewed_at: now } : null;
    const { forward_basis: ignoredForward, ...safeReceipt } = receipt;
    receipt = safeReceipt;
    const old = this.one('SELECT * FROM receipts WHERE id=?', id);
    if (old) {
      const previous = decode(old.receipt);
      const previousPaidTime = instant(previous.paid_at), incomingPaidTime = instant(receipt.paid_at);
      if (Number.isFinite(previousPaidTime)) {
        require(!Number.isFinite(incomingPaidTime) || incomingPaidTime === previousPaidTime, 'affiliate_paid_time_locked');
        // Provider reversal snapshots can omit the original paid timestamp;
        // retain its immutable evidence instead of borrowing current time.
        receipt.paid_at = previous.paid_at;
      }
      require((old.scope === scope || previous.scope_verified !== true) && previous.currency === receipt.currency && previous.gross_cents === receipt.gross_cents &&
        previous.kind === receipt.kind && previous.mode === receipt.mode, 'affiliate_payment_identity_locked');
      require(receipt.refunded_gross_cents >= previous.refunded_gross_cents, 'affiliate_stale_payment_snapshot');
      require(receipt.charged_back_gross_cents >= (previous.charged_back_gross_cents || 0), 'affiliate_stale_payment_snapshot');
      if (previous.payment_status === 'paid' && receipt.payment_status !== 'paid') {
        // Provider reversals are reviewable evidence, never an automatic
        // financial-policy decision or entitlement mutation.
        require(['charged_back', 'refunded'].includes(receipt.payment_status), 'affiliate_stale_payment_snapshot');
      }
      const changed = previous.payment_status !== receipt.payment_status || previous.refunded_gross_cents !== receipt.refunded_gross_cents ||
        (previous.charged_back_gross_cents || 0) !== receipt.charged_back_gross_cents || previous.scope_verified !== receipt.scope_verified ||
        previous.paid_at !== receipt.paid_at;
      if (changed) {
        require(previous.scope_verified !== true || receipt.scope_verified === true, 'affiliate_scope_proof_locked');
        this.sql.exec('UPDATE receipts SET receipt=?,scope=?,revision=revision+1,updated_at=? WHERE id=?', json(receipt), scope, now, id);
      }
    } else {
      this.sql.exec('INSERT INTO receipts(id,scope,payment_id,receipt,state,reason,revision,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?)',
        id, scope, receipt.payment_id, json(receipt), 'held_review', 'unprocessed', 1, now, now);
    }
    // Automatically recover an earlier held capture once this exact immutable
    // future checkout proof becomes available. Refunds still require their own
    // verified amount/credit policy and never reuse a guessed net ratio.
    if (forwardBasis && !this.one('SELECT basis FROM receipts WHERE id=?', id)?.basis) {
      this.sql.exec('UPDATE receipts SET basis=?,updated_at=? WHERE id=?', json(forwardBasis), now, id);
    }
    return this.process(id, now);
  }

  process(id, now) {
    const row = this.one('SELECT * FROM receipts WHERE id=?', id), receipt = decode(row.receipt), basis = decode(row.basis);
    const attribution = this.one('SELECT * FROM attributions WHERE scope=?', row.scope);
    const affiliate = attribution ? this.one('SELECT * FROM affiliates WHERE id=?', attribution.affiliate_id) : null;
    const proof = this.one('SELECT * FROM owner_proofs WHERE scope=?', row.scope);
    let reason = '';
    if (receipt.mode === 'test') reason = 'test_payment_excluded';
    else if (receipt.mode !== 'live') reason = 'payment_mode_review';
    else if ((receipt.charged_back_gross_cents || 0) > 0 || receipt.payment_status === 'charged_back') reason = 'provider_chargeback_requires_review';
    else if (receipt.payment_status !== 'paid') reason = row.target > 0 ? 'provider_reversal_requires_review' : 'payment_not_paid';
    else if (receipt.scope_verified !== true) reason = 'payment_scope_review';
    else if (!attribution || attribution.state !== 'active' || !proof) reason = 'attribution_owner_review';
    else if (!Number.isFinite(instant(receipt.paid_at)) || instant(receipt.paid_at) > Date.parse(now)) reason = 'payment_time_review';
    else if (Date.parse(receipt.paid_at) < Date.parse(attribution.created_at)) reason = 'attribution_effective_date_review';
    else if (proof.person_id === attribution.affiliate_id) reason = 'self_referral';
    else if (affiliate?.status !== 'active') reason = 'affiliate_approval_required';
    else if (!basis) reason = 'net_vat_basis_review';
    else if (basis.refunded_ex_vat_cents + basis.refunded_vat_cents !== receipt.refunded_gross_cents) reason = 'refund_basis_review';
    if (reason) {
      const state = ['test_payment_excluded', 'payment_not_paid'].includes(reason) && row.target === 0 ? 'excluded' : 'held_review';
      this.sql.exec('UPDATE receipts SET state=?,reason=?,affiliate_id=?,updated_at=? WHERE id=?', state, reason,
        attribution?.affiliate_id || null, now, id);
      return { receipt_id: id, state, reason, target_commission_cents: row.target, revision: row.revision };
    }
    const target = targetOf(basis.ex_vat_cents - basis.refunded_ex_vat_cents), delta = target - row.target;
    if (delta !== 0) this.sql.exec('INSERT INTO entries(affiliate_id,currency,cents,receipt_id,receipt_revision,kind,period,created_at) VALUES (?,?,?,?,?,?,?,?)',
      attribution.affiliate_id, receipt.currency, delta, id, row.revision, delta > 0 ? 'commission' : 'correction', month(receipt.paid_at) || month(now), now);
    require(Number.isSafeInteger(this.one('SELECT COALESCE(SUM(cents),0) AS cents FROM entries WHERE affiliate_id=? AND currency=?', attribution.affiliate_id, receipt.currency).cents), 'affiliate_balance_overflow');
    this.sql.exec('UPDATE receipts SET state=?,reason=?,target=?,affiliate_id=?,updated_at=? WHERE id=?',
      'accrued', '', target, attribution.affiliate_id, now, id);
    return { receipt_id: id, state: 'accrued', target_commission_cents: target, delta_cents: delta, revision: row.revision };
  }

  createBatch(body, actor, now) {
    const id = text(body.batch_id), period = text(body.period, 7), currency = text(body.currency, 3);
    const ids = [...new Set(Array.isArray(body.affiliate_ids) ? body.affiliate_ids.map(x => text(x)).filter(Boolean) : [])].sort();
    require(id && validMonth(period) && validCurrency(currency) && ids.length > 0 && ids.length <= 100, 'affiliate_batch_input_required', 400);
    const manifest = { period, currency, affiliate_ids: ids }, manifestText = json(manifest);
    const old = this.one('SELECT * FROM batches WHERE id=?', id);
    if (old) { require(decode(old.manifest).request === manifestText, 'affiliate_batch_identity_locked'); return { batch_id: id, manifest_hash: old.manifest_hash, items: decode(old.manifest).items, idempotent: true }; }
    const items = [];
    for (const affiliateId of ids) {
      const affiliate = this.person(affiliateId);
      require(affiliate.status === 'active' && affiliate.bank_verified === 1 && affiliate.bank, 'affiliate_payout_approval_required');
      require(!this.one('SELECT id FROM receipts WHERE affiliate_id=? AND state=? LIMIT 1', affiliateId, 'held_review'), 'affiliate_payout_has_unresolved_receipt');
      const balance = this.one('SELECT COALESCE(SUM(cents),0) AS cents FROM entries WHERE affiliate_id=? AND currency=? AND period<=?', affiliateId, currency, period).cents;
      const reserved = this.one("SELECT COALESCE(SUM(cents),0) AS cents FROM payouts WHERE affiliate_id=? AND currency=? AND state IN ('approved','exported','failed')", affiliateId, currency).cents;
      const cents = balance - reserved;
      require(Number.isSafeInteger(cents) && cents > 0, 'affiliate_no_payable_balance');
      const payoutId = `${id}:${affiliateId}`;
      this.sql.exec('INSERT INTO payouts(id,batch_id,affiliate_id,period,currency,cents,state,bank_revision,bank,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',
        payoutId, id, affiliateId, period, currency, cents, 'approved', affiliate.bank_revision, affiliate.bank, now);
      items.push({ payout_id: payoutId, affiliate_id: affiliateId, cents, currency, bank_revision: affiliate.bank_revision });
    }
    // This is a server-generated opaque immutable manifest proof, not a caller
    // supplied hash. It binds the stored exact payout amounts/account revisions.
    const proof = crypto.randomUUID();
    this.sql.exec('INSERT INTO batches(id,period,currency,manifest_hash,manifest,created_at) VALUES (?,?,?,?,?,?)', id, period, currency, proof, json({ request: manifestText, items }), now);
    this.audit(actor, 'create_batch', id, { manifest_hash: proof, items }, now);
    return { batch_id: id, manifest_hash: proof, items, idempotent: false };
  }

  reconcile(body, actor, now) {
    const batch = this.one('SELECT * FROM batches WHERE id=?', text(body.batch_id));
    require(batch && batch.manifest_hash === body.manifest_hash, 'affiliate_batch_proof_conflict');
    require(Array.isArray(body.executions) && body.executions.length > 0 && body.executions.length <= 100, 'affiliate_execution_evidence_required', 400);
    const results = [];
    for (const item of body.executions) {
      const payout = this.one('SELECT * FROM payouts WHERE id=? AND batch_id=?', text(item.payout_id), batch.id);
      require(payout && payout.cents === item.amount_cents && payout.currency === item.currency, 'affiliate_execution_amount_conflict');
      require(text(item.bank_execution_reference) && text(item.evidence_reference) && ['paid', 'failed'].includes(item.status) &&
        Number.isFinite(instant(item.executed_at)) && instant(item.executed_at) <= Date.parse(now), 'affiliate_execution_evidence_required', 400);
      const reference = text(item.bank_execution_reference), old = this.one('SELECT * FROM executions WHERE reference=?', reference);
      const evidence = { amount_cents: item.amount_cents, currency: item.currency, evidence_reference: text(item.evidence_reference), executed_at: item.executed_at };
      if (old) {
        require(old.payout_id === payout.id && old.result === item.status && old.evidence === json(evidence), 'affiliate_execution_identity_locked');
        results.push({ payout_id: payout.id, state: payout.state, idempotent: true }); continue;
      }
      require(payout.state !== 'paid', 'affiliate_payout_already_paid');
      require(['exported', 'failed'].includes(payout.state), 'affiliate_payout_not_exported');
      this.sql.exec('INSERT INTO executions(reference,payout_id,result,evidence,recorded_at) VALUES (?,?,?,?,?)', reference, payout.id, item.status, json(evidence), now);
      if (item.status === 'paid') this.sql.exec('INSERT INTO entries(affiliate_id,currency,cents,kind,period,created_at) VALUES (?,?,?,?,?,?)',
        payout.affiliate_id, payout.currency, -payout.cents, 'bank_payout', batch.period, now);
      this.sql.exec('UPDATE payouts SET state=?,execution_reference=?,updated_at=? WHERE id=?', item.status, reference, now, payout.id);
      this.audit(actor, 'reconcile_payout', payout.id, { reference, state: item.status, evidence_reference: evidence.evidence_reference }, now);
      results.push({ payout_id: payout.id, state: item.status, idempotent: false });
    }
    return { batch_id: batch.id, items: results };
  }
}

export async function affiliateOperation(env, action, body = {}, actor = {}) {
  if (!env?.AFFILIATE_LEDGER) return { ok: false, error: 'affiliate_not_configured', status: 503 };
  try {
    const binding = env.AFFILIATE_LEDGER, stub = binding.get(binding.idFromName(AFFILIATE_LEDGER_NAME));
    const response = await stub.fetch(new Request('https://affiliate.internal/operation', { method: 'POST',
      headers: { 'content-type': 'application/json' }, body: json({ action, body, ...actor }) }));
    const result = await response.json(); return { ...result, _http_status: response.status };
  } catch (_) { return { ok: false, error: 'affiliate_storage_unavailable', status: 503 }; }
}
