import { verifyBookingCutoverRequest } from './booking_cutover_maintenance.mjs';
import { bookingWritersPaused } from './booking_writer_pause.mjs';
// A separate namespace resolves globally unique booking IDs without KV hints.
// One object per booking ID: a claim never waits for another company's queue.
export const CANONICAL_BOOKING_DIRECTORY_BINDING = 'CANONICAL_BOOKING_DIRECTORY';
const scopeOf = value => ({ tenant_id: String(value?.tenant_id || '').trim(), company_id: String(value?.company_id || '').trim() });
const validScope = scope => Boolean(scope.tenant_id && scope.company_id && scope.tenant_id.length <= 80 && scope.company_id.length <= 80);
const sameScope = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const validId = id => typeof id === 'string' && id.length > 0 && id.length <= 160 && !/\s/.test(id);
const failed = (error, status = 503) => ({ ok: false, error, status });

export class CanonicalBookingDirectoryDO {
  constructor(state, env) { this.state = state; this.env = env; }
  async fetch(request) {
    this.gate ||= Promise.resolve();
    const run = this.gate.then(async () => {
      const stagingMarked = this.env?.STAGING_TRIAL_MODE === '1'
        || this.env?.STAGING_TRIAL_ENVIRONMENT === 'staging'
        || String(this.env?.ENVIRONMENT ?? '').trim().toLowerCase() === 'staging';
      if (stagingMarked) {
        if (this.env?.STAGING_TRIAL_MODE !== '1'
          || this.env?.STAGING_TRIAL_ENVIRONMENT !== 'staging') {
          return failed('staging_trial_configuration_required');
        }
        let trialBody;
        try { trialBody = await request.clone().json(); }
        catch (_) { return failed('canonical_directory_request_invalid', 400); }
        if (trialBody?.operation !== 'read') {
          return failed('staging_canonical_directory_operation_closed', 403);
        }
      }
      if (this.env.BOOKING_RECORD_AUTHORITY_ENABLED !== '1') return failed('canonical_authority_disabled');
      const maintenance = await verifyBookingCutoverRequest(this.env, request, 'directory');
      let body;
      try { body = await request.json(); } catch (_) { return failed('canonical_directory_request_invalid', 400); }
      if (bookingWritersPaused(this.env) && body.operation !== 'read' && !maintenance) return failed('booking_writers_paused');
      if (!validId(body.bookingId)) return failed('canonical_booking_id_invalid', 400);
      const current = await this.state.storage.get('booking-route');
      if (current && (current.bookingId !== body.bookingId || !validScope(current.scope))) {
        return failed('canonical_directory_identity_conflict', 409);
      }
      if (body.operation === 'read') return { ok: true, scope: current?.scope || null };
      if (body.operation !== 'claim') return failed('canonical_directory_operation_invalid', 400);
      const scope = scopeOf(body.scope);
      if (!validScope(scope)) return failed('canonical_booking_scope_invalid', 400);
      if (current && !sameScope(current.scope, scope)) return failed('canonical_booking_scope_conflict', 403);
      if (!current) await this.state.storage.put('booking-route', { schema: 1, bookingId: body.bookingId, scope });
      // Never unclaim from a missing KV record, timeout, delete or failed writer.
      return { ok: true, scope, idempotent: Boolean(current) };
    }).catch(() => failed('canonical_directory_storage_failed'));
    this.gate = run.then(() => undefined, () => undefined);
    const result = await run;
    return Response.json(result, { status: result.status || 200 });
  }
}

async function callDirectory(env, body) {
  const binding = env[CANONICAL_BOOKING_DIRECTORY_BINDING];
  let result;
  if (!binding?.idFromName || !binding?.get) result = failed('canonical_directory_unavailable');
  else try {
    const response = await binding.get(binding.idFromName(body.bookingId)).fetch(new Request('https://directory/booking', {
      method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body) }));
    result = await response.json();
    if (!response.ok && result.ok === true) result = failed('canonical_directory_response_invalid');
  } catch (_) { result = failed('canonical_directory_unavailable'); }
  if (result?.ok !== true) {
    const error = new Error(result?.error || 'canonical_directory_unavailable');
    error.code = result?.error; error.status = result?.status || 503; throw error;
  }
  if ((result.scope && !validScope(result.scope))
    || (body.operation === 'claim' && !sameScope(result.scope, scopeOf(body.scope)))) {
    const error = new Error('canonical_directory_response_invalid'); error.code = error.message; error.status = 503; throw error;
  }
  return result.scope;
}
export const resolveCanonicalBookingScope = (env, bookingId) => callDirectory(env, { operation: 'read', bookingId });
export const claimCanonicalBookingScope = (env, bookingId, scope) => callDirectory(env, { operation: 'claim', bookingId, scope });

/** Test binding; state survives replacing the object instance. */
export function createMemoryCanonicalBookingDirectoryBinding(env) {
  const instances = new Map();
  return { idFromName: name => String(name), get(name) {
    if (!instances.has(name)) {
      const values = new Map(); const state = { storage: {
        get: async key => structuredClone(values.get(key)),
        put: async (key, value) => values.set(key, structuredClone(value)), _store: values } };
      instances.set(name, new CanonicalBookingDirectoryDO(state, env));
    }
    return instances.get(name);
  }, _instances: instances };
}
