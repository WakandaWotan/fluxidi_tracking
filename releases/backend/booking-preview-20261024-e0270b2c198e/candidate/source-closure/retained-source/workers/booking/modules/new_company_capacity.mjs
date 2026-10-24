import { companyTrackingObjectName } from '../../tracking/modules/company_tracking_room.mjs';
import { companyBookingsListIndexKey } from './booking_indexes.js';

const fail = (error, status = 409) => ({ ok: false, error, status });
const same = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const uuid = value => typeof value === 'string' && /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(value);
const validScope = scope => ['tenant_id', 'company_id'].every(key => typeof scope?.[key] === 'string'
  && /^[A-Za-z0-9._-]{1,80}$/.test(scope[key]));

// Private registration action, invoked BEFORE publishing a profile/code/session.
// Existing companies use reviewed inventory migration; never this empty bootstrap.
export async function initializeNewCompanyCapacity(state, env, { scope, registrationId }) {
  if (env.BOOKING_RECORD_AUTHORITY_ENABLED !== '1') return fail('canonical_authority_required', 503);
  if (!validScope(scope) || !uuid(registrationId)) return fail('new_company_capacity_identity_invalid', 400);
  if (!env.COMPANY_TRACKING?.idFromName || !env.COMPANY_TRACKING?.get || !state.storage.list) return fail('new_company_capacity_unavailable', 503);
  const key = 'new-company-capacity-registration';
  let intent = await state.storage.get(key);
  if (intent && (!same(intent, scope) || intent.registration_id !== registrationId)) return fail('new_company_capacity_identity_conflict');
  if (intent?.state === 'ready') return { ok: true, already_initialized: true };
  if (!intent) {
    const pin = await state.storage.get('canonical-booking-scope');
    if (pin && !same(pin, scope)) return fail('canonical_booking_scope_conflict', 403);
    for (const prefix of ['canonical-booking:', 'initial-booking-', 'canonical-booking-recovery:']) {
      if ((await state.storage.list({ prefix, limit: 1 })).size) return fail('new_company_capacity_existing_history');
    }
    const profile = await env.BOOKING_KV.get(`tenant:${scope.tenant_id}:company:${scope.company_id}:business_profile:v1`, { type: 'json' });
    const index = await env.BOOKING_KV.get(companyBookingsListIndexKey(scope), { type: 'json' });
    if (profile || index) return fail('new_company_capacity_existing_history');
    intent = { schema: 1, ...scope, registration_id: registrationId, state: 'prepared' };
    // Durable registration intent precedes the cross-object baseline call.
    await state.storage.put('canonical-booking-scope', { tenant_id: scope.tenant_id, company_id: scope.company_id });
    await state.storage.put(key, intent);
  }
  const room = env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(companyTrackingObjectName(scope.tenant_id, scope.company_id)));
  const response = await room.fetch(new Request('https://room/capacity-baseline', { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...scope, inventory_verified: true,
      bookings: [], inventory_digest: `new-company:${registrationId}`, new_company_registration: registrationId }) }));
  const result = await response.json();
  if (!response.ok || result.ok !== true || result.committed !== true) return fail(result.error || 'new_company_capacity_unavailable', response.ok ? 503 : response.status);
  await state.storage.put(key, { ...intent, state: 'ready' });
  return { ok: true, already_initialized: result.already_initialized === true };
}
