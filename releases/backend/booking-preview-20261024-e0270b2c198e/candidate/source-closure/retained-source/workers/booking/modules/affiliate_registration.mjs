import { affiliatePerson, affiliateProgramMetadata } from './affiliate_http.mjs';
import { affiliateOperation } from './affiliate_ledger.mjs';
import { corsHeaders } from './http_response.js';

const reply = (body, status = 200) => Response.json(body, { status, headers: { ...corsHeaders(), 'cache-control': 'private, no-store' } });
const error = (code, status = 503) => reply({ ok: false, error: code, recoverable: status === 503 }, status);
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
const sha256 = async value => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)))].map(x => x.toString(16).padStart(2, '0')).join('');

// Optional referral registrations are tied to one real personal identity and
// immutable request. A completed replay issues a fresh short-lived company
// session; no company bearer is stored in the financial ledger or retry outbox.
export async function registerCompanyWithAffiliate({ request, body, env, loadCustomerSession,
  loadGlobalIdentity, allocateScope, validateRegistration, register, mintReplaySession }) {
  if (!body?.referral_code) return register(body, env);
  const programme = affiliateProgramMetadata(env);
  if (!programme.program_enabled) return error('affiliate_program_not_enabled');
  if (!env.AFFILIATE_LEDGER) return error('affiliate_not_configured');
  if (!programme.may_apply) return error('affiliate_terms_not_configured');
  let person;
  try { person = await affiliatePerson(request, env, loadCustomerSession, loadGlobalIdentity); }
  catch (_) { return error('affiliate_identity_lookup_unavailable'); }
  if (!person) return error('affiliate_personal_login_required', 401);
  if (!/^[A-Za-z0-9_-]{16,80}$/.test(body.affiliate_registration_request_id || '')) return error('affiliate_registration_id_required', 400);
  const companyName = body.company_name ?? body.companyName;
  if (typeof companyName !== 'string' || !companyName.trim()) return error('missing_company_name', 400);
  const validation = await validateRegistration?.(body, env);
  if (validation) return validation;
  const requestHash = await sha256(JSON.stringify(canonical(body)));
  const candidate = await allocateScope(env, companyName);
  if (!candidate) return error('affiliate_registration_scope_unavailable');
  const prepared = await affiliateOperation(env, 'registration_prepare', {
    request_id: body.affiliate_registration_request_id, payload_hash: requestHash,
    referral_code: body.referral_code, scope: candidate,
  }, { actor_id: person.customer_id });
  if (!prepared.ok) return error(prepared.error, prepared._http_status || prepared.status || 503);
  const scope = { tenant_id: prepared.scope[0], company_id: prepared.scope[1], hasScope: true };
  const outboxKey = `affiliate:registration:outbox:${await sha256(prepared.registration_id)}:v1`;
  let result = prepared.result;
  if (!result && prepared.state === 'writing') {
    result = await env.BOOKING_KV.get(outboxKey, { type: 'json' });
    // Never rerun signup writes after a lost completion. Exact durable scope
    // and pending referral survive; incomplete side effects need explicit
    // recovery rather than silently creating a second company.
    if (!result) return error('affiliate_registration_completion_pending');
  }
  if (result) {
    const completed = await affiliateOperation(env, 'registration_complete', { registration_id: prepared.registration_id, result }, { actor_id: person.customer_id });
    if (!completed.ok) return error(completed.error, completed._http_status || completed.status || 503);
    let credentials;
    try { credentials = await mintReplaySession(env, scope, result); }
    catch (_) { return error('affiliate_registration_session_unavailable'); }
    if (!credentials) return error('affiliate_registration_session_unavailable');
    return reply({ ...result, ...credentials, affiliate_referral_state: 'held_owner_review', registration_idempotent: true });
  }
  const begun = await affiliateOperation(env, 'registration_begin', { registration_id: prepared.registration_id }, { actor_id: person.customer_id });
  if (!begun.ok) return error(begun.error, begun._http_status || begun.status || 503);
  let response;
  try { response = await register(body, env, { scope }); }
  catch (_) { return error('affiliate_registration_completion_pending'); }
  if (response.status !== 200) return response;
  const wire = await response.json();
  const { company_session_token, companySessionToken, ...safe } = wire;
  result = { ...safe, affiliate_referral_state: 'held_owner_review' };
  // Completion outbox precedes its ledger ACK and contains no credentials.
  // An ACK outage replays this exact result instead of signup mutations.
  try { await env.BOOKING_KV.put(outboxKey, JSON.stringify(result)); }
  catch (_) { return error('affiliate_registration_completion_pending'); }
  const completed = await affiliateOperation(env, 'registration_complete', { registration_id: prepared.registration_id, result }, { actor_id: person.customer_id });
  if (!completed.ok) return error(completed.error, completed._http_status || completed.status || 503);
  return reply({ ...result, company_session_token, companySessionToken });
}
