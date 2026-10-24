import {compactCanonicalFinancialEvidence,hydrateCanonicalFinancialEvidence} from './financial_quote_lifecycle.mjs';
import {persistCanonicalWithInvoiceIndex} from './company_invoice_source_index.mjs';
// The company coordinator owns canonical booking versions. Workers KV is a
// projection: its successful readback cannot establish the latest revision.
// Enable only after all Worker entry points and migration have been verified.
import { callCompanyCustomerImportCoordinator } from './company_customer_import_coordinator.mjs';
import { resolveCanonicalBookingScope, claimCanonicalBookingScope } from './canonical_booking_directory.mjs';
import { hasOpenDispatchAmendment } from './dispatch_booking_open.mjs';
import { buildCompanyIndexMembershipMap, legacyScopeEvidenceDigest, legacyOwnershipAgreesWithScope,
  inspectLegacyOwnership, applyProvenLegacyOwnership, unresolvedLegacyScopeTransition } from './legacy_scope_evidence.mjs';

const rawBookingKv = Symbol('rawBookingKv');
const authorityScope = Symbol('authorityScope');
const dispatchHandoff = Symbol('dispatchHandoff');
const VERSION = '_canonical_version';
const MAX_RECORD_BYTES = 120 * 1024;
const MAX_PAGE_RECORD_BYTES = 8 * 1024 * 1024;
const RECOVERY_PREFIX = 'canonical-booking-recovery:';
const RECOVERY_DELAY_MS = 60_000;
const failed = (error, status = 503) => ({ ok: false, error, status });
const scopeOf = value => ({ tenant_id: String(value?.tenant_id || value?.tenantId || value?.booking?.tenant_id || '').trim(),
  company_id: String(value?.company_id || value?.companyId || value?.booking?.company_id || '').trim() });
const sameScope = (a, b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const validScope = scope => Boolean(scope?.tenant_id && scope?.company_id
  && scope.tenant_id.length <= 80 && scope.company_id.length <= 80);
function bookingIdOfKey(key) {
  if (typeof key !== 'string' || !key.startsWith('booking:')) return '';
  const id = key.slice(8);
  if (!id || id.length > 160 || /\s/.test(id)) throw exception(failed('canonical_booking_id_invalid', 400));
  return id;
}
const storageKey = id => `canonical-booking:${id}`;
const withoutVersion = record => { const copy = { ...record }; delete copy[VERSION]; return copy; };
function exception(result) {
  const error = new Error(result.error || 'canonical_booking_unavailable');
  error.code = result.error; error.status = result.status || 503; return error;
}
function dispatchIntent(record, id) {
  if (['COMPLETED', 'CANCELLED', 'CANCELED', 'NO_SHOW', 'REJECTED', 'EXPIRED']
    .includes(String(record.status || record.lifecycle_status || '').toUpperCase())
    || !hasOpenDispatchAmendment(record) && (record.assigned_driver_id || record.assignedDriverId || record.assigned_vehicle_id || record.assignedVehicleId
      || record.booking?.assigned_driver_id || record.booking?.assigned_vehicle_id)) return null;
  const offer = record.dispatch_offer;
  if (offer?.state === 'prepared' && offer.offer_id && Number.isSafeInteger(offer.version)) {
    return { type: 'offer', id: offer.offer_id, version: offer.version };
  }
  const search = record.dispatch_search;
  return search?.state === 'pending' && Number.isSafeInteger(search.version)
    ? { type: 'search', id: `search:${id}:${search.version}`, version: search.version } : null;
}
const sameIntent = (a, b) => Boolean(a && b && a.type === b.type && a.id === b.id && a.version === b.version);
async function envelope(env, scope, record, version, options, previous, id) {
  if(record?._canonical_financial_evidence_ref)throw exception(failed('booking_evidence_reference_unresolved',409));
  const intent = dispatchIntent(record, id), handedOff = sameIntent(intent, previous?.dispatch_handoff);
  const next = { schema: 1, ...scope, version, record: { ...record, [VERSION]: version },
    projection_pending: true, dispatch_retry: handedOff ? null : intent,
    ...(handedOff ? { dispatch_handoff: previous.dispatch_handoff } : {}),
    ...(options ? { projection_options: options } : {}) };
  if (new TextEncoder().encode(JSON.stringify(next)).byteLength > MAX_RECORD_BYTES) {
    next.record=await compactCanonicalFinancialEvidence(env,next.record,id);
  }
  if (new TextEncoder().encode(JSON.stringify(next)).byteLength > MAX_RECORD_BYTES) {
    throw exception(failed('canonical_booking_too_large', 413));
  }
  return next;
}

async function armRecovery(state) {
  if (!state.storage.setAlarm || !state.storage.list || !state.storage.delete) {
    throw exception(failed('canonical_booking_recovery_unavailable'));
  }
  const next = Date.now() + RECOVERY_DELAY_MS;
  const alarm = state.storage.getAlarm ? await state.storage.getAlarm() : null;
  if (alarm == null || alarm > next) await state.storage.setAlarm(next);
}
async function persistPending(state, id, value) {
  // Arm and index BEFORE the record write. A crash can leave a harmless job
  // pointing to the old generation, but cannot leave a new generation unqueued.
  await armRecovery(state);
  await state.storage.put(`${RECOVERY_PREFIX}${id}`, { schema: 1, bookingId: id, ...scopeOf(value) });
  await persistCanonicalWithInvoiceIndex(state.storage,id,value,()=>state.storage.put(storageKey(id),value));
}
async function finishRecovery(state, id, value) {
  if (!value?.projection_pending && !value?.dispatch_retry) await state.storage.delete(`${RECOVERY_PREFIX}${id}`);
}

export function canonicalBookingAuthorityEnabled(env) {
  return env?.BOOKING_RECORD_AUTHORITY_ENABLED === '1';
}

// Bootstrap scans may encounter other companies' keys. Establish ownership
// before reading through a company-pinned authority, without adopting a
// foreign record or treating its opaque scoped miss as a missing own booking.
export async function readCompanyBookingInventoryRecord(env, scope, bookingId) {
  const enabled = canonicalBookingAuthorityEnabled(env), key = `booking:${bookingId}`;
  const kv = env[rawBookingKv] || env.BOOKING_KV;
  let owner = enabled ? await resolveCanonicalBookingScope(env, bookingId) : null;
  let hint;
  if (!owner) {
    hint = await kv.get(key, { type: 'json' });
    if (!hint) return { record: null, foreign: false };
    owner = scopeOf(hint);
    if (!validScope(owner)) throw exception(failed('capacity_inventory_scope_unresolved', 409));
  }
  if (!sameScope(owner, scope)) return { record: null, foreign: true };
  return { record: enabled ? await env.BOOKING_KV.get(key, { type: 'json' }) : hint, foreign: false };
}

// Admin census must not adopt a raw record or repair a projection as a side effect.
export async function readLegacyBookingScopeMigrationRecord(env, bookingId) {
  const kv = env[rawBookingKv] || env.BOOKING_KV;
  const scope = canonicalBookingAuthorityEnabled(env) ? await resolveCanonicalBookingScope(env, bookingId) : null;
  if (scope) {
    const result = await callCompanyCustomerImportCoordinator(env, { action: 'canonical_booking',
      scope, bookingId, operation: 'inspect' });
    if (!result?.ok) throw exception(result || failed('canonical_booking_unavailable'));
    if (result.record) return { record: result.record, canonical: true, scope };
  }
  return { record: await kv.get(`booking:${bookingId}`, { type: 'json' }), canonical: false, scope };
}

export async function adoptProvenLegacyBookingScope(env, body) {
  const result = await callCompanyCustomerImportCoordinator(env, { ...body, action: 'canonical_booking',
    operation: 'adopt_legacy_scope' });
  if (!result?.ok) throw exception(result || failed('legacy_scope_adoption_failed'));
  return result;
}

// Called only within the serialized company DO. No in-memory record cache is
// used: reads after a restart and after storage failure use durable evidence.
export async function canonicalBookingOperation(state, env, body) {
  if (!canonicalBookingAuthorityEnabled(env)) return failed('canonical_authority_disabled');
  const scope = scopeOf(body.scope), id = String(body.bookingId || '').trim();
  if (!validScope(scope) || !id || !bookingIdOfKey(`booking:${id}`) || id.length > 160) {
    return failed('canonical_booking_scope_invalid', 400);
  }
  const pin = await state.storage.get('canonical-booking-scope');
  if (pin && !sameScope(pin, scope)) return failed('canonical_booking_scope_conflict', 403);
  const operation = String(body.operation || 'read');
  const kv = env[rawBookingKv] || env.BOOKING_KV, key = `booking:${id}`;
  let current = await state.storage.get(storageKey(id));
  if (current && (!sameScope(current, scope) || !sameScope(scopeOf(current.record), scope))) {
    return failed('canonical_booking_scope_conflict', 403);
  }
  // Inspection is genuinely read-only: no pin, directory claim, adoption,
  // alarm, KV write or pending-projection cleanup.
  if (operation === 'inspect') return { ok: true, record: current ? await hydrateCanonicalFinancialEvidence(env,current.record,id) : null };
  if (operation === 'adopt_legacy_scope' && !['1', 'true', 'yes', 'on'].includes(String(env.LEGACY_SCOPE_MIGRATION_ENABLED || '0').trim().toLowerCase())) return failed('legacy_scope_migration_disabled', 403);
  if (!pin) await state.storage.put('canonical-booking-scope', scope);
  if (current) await claimCanonicalBookingScope(env, id, scope);
  if (operation === 'adopt_legacy_scope' && !current) {
    const inventory = await buildCompanyIndexMembershipMap({ ...env, BOOKING_KV: kv }, { maxIndexes: body.maxIndexes || 200 });
    const legacy = await kv.get(key, { type: 'json' });
    if (!legacy || await legacyScopeEvidenceDigest(legacy) !== body.recordDigest
      || inventory.inventory_digest !== body.inventoryDigest) return failed('legacy_scope_review_conflict', 409);
    const owners = inventory.membership.get(id) || [];
    const uniqueOwners = [...new Map(owners.map(owner => [JSON.stringify([owner.tenant_id, owner.company_id]), owner])).values()];
    if (uniqueOwners.length !== 1 || !sameScope(uniqueOwners[0], scope) || !legacyOwnershipAgreesWithScope(legacy, scope)
      || legacy.legacy_scope_quarantine || ['ambiguous', 'legacy_scope_ambiguous'].includes(legacy.legacy_scope_status)) {
      return failed('legacy_scope_ownership_unresolved', 409);
    }
    if (unresolvedLegacyScopeTransition(legacy, id)) {
      return failed('legacy_scope_transition_unresolved', 409);
    }
    const next = await envelope(env, scope, applyProvenLegacyOwnership(legacy, scope, body.recordDigest), 1, undefined, undefined, id);
    await claimCanonicalBookingScope(env, id, scope);
    await persistPending(state, id, next);
    current = next;
  }
  if (!current && operation !== 'adopt_legacy_scope') {
    // Positive legacy evidence is needed for adoption. A miss is never a
    // release, a tombstone, or permission to overwrite another generation.
    const legacy = await kv.get(key, { type: 'json' });
    if (legacy) {
      const raw = inspectLegacyOwnership(legacy);
      if (raw.invalid || raw.conflicting || !sameScope(scopeOf(legacy), scope)) return body.operation === 'write'
        ? failed('canonical_booking_scope_conflict', 403) : { ok: true, record: null };
      current = await envelope(env, scope, legacy, 1, undefined, undefined, id);
      await claimCanonicalBookingScope(env, id, scope);
      await persistPending(state, id, current);
    }
  }
  async function project(value) {
    if (!value.projection_pending) return;
    await kv.put(key, JSON.stringify(await hydrateCanonicalFinancialEvidence(env,value.record,id)), value.projection_options);
    const clean = { ...value, projection_pending: false };
    await state.storage.put(storageKey(id), clean);
    current = clean;
    await finishRecovery(state, id, clean);
  }
  if (operation === 'read' || operation === 'adopt_legacy_scope') {
    if (current) await project(current);
    return { ok: true, record: current ? await hydrateCanonicalFinancialEvidence(env,current.record,id) : null };
  }
  if (operation === 'dispatch_handoff') {
    if (!current) return failed('canonical_booking_unavailable', 409);
    if (!sameIntent(current.dispatch_retry, body.intent) && !sameIntent(current.dispatch_handoff, body.intent)) {
      return failed('canonical_dispatch_intent_conflict', 409);
    }
    await project(current);
    const handedOff = { ...current, dispatch_retry: null, dispatch_handoff: body.intent };
    await state.storage.put(storageKey(id), handedOff);
    current = handedOff;
    await finishRecovery(state, id, handedOff);
    return { ok: true, handed_off: true };
  }
  if (operation !== 'write') return failed('canonical_booking_operation_invalid', 400);
  const record = body.record;
  const raw = inspectLegacyOwnership(record);
  if (!record || typeof record !== 'object' || Array.isArray(record) || raw.invalid || raw.conflicting || !sameScope(scopeOf(record), scope)) {
    return failed('canonical_booking_scope_conflict', 403);
  }
  if (!Number.isSafeInteger(body.expectedVersion) || body.expectedVersion < 0) {
    return failed('canonical_booking_version_invalid', 400);
  }
  if (body.expectedVersion !== (current?.version || 0)) {
    // A response can be lost after the durable write. An exact replay may
    // repair that projection; a stale different payload must never win.
    const replayRecord=current?.record?._canonical_financial_evidence_ref
      ? await compactCanonicalFinancialEvidence(env,record,id) : record;
    if (current && JSON.stringify(withoutVersion(replayRecord)) === JSON.stringify(withoutVersion(current.record))) {
      await project(current);
      return { ok: true, record: await hydrateCanonicalFinancialEvidence(env,current.record,id), idempotent: true };
    }
    return failed('canonical_booking_revision_conflict', 409);
  }
  // Store the canonical result before its KV projection. If either later
  // write fails, the pending result survives and an exact retry repairs it.
  const next = await envelope(env, scope, record, (current?.version || 0) + 1, body.options, current, id);
  await claimCanonicalBookingScope(env, id, scope);
  await persistPending(state, id, next);
  await project(next);
  return { ok: true, record: await hydrateCanonicalFinancialEvidence(env,current.record,id) };
}

export async function completeCanonicalDispatchHandoff(env, scope, bookingId, intent) {
  if (!canonicalBookingAuthorityEnabled(env)) return;
  const result = env[dispatchHandoff]
    ? await env[dispatchHandoff](scope, bookingId, intent)
    : await callCompanyCustomerImportCoordinator(env, { action: 'canonical_booking', scope,
      bookingId, operation: 'dispatch_handoff', intent });
  if (!result?.ok) throw exception(result || failed('canonical_dispatch_handoff_failed'));
}

// Run inside the same company gate as fetch. Work is indexed durably, bounded
// and rotated so one failing booking cannot starve another company's own jobs.
export async function recoverCanonicalBookings(state, env, retryDispatch) {
  const scope = await state.storage.get('canonical-booking-scope');
  if (!scope || !state.storage.list) return;
  const cursor = await state.storage.get('canonical-booking-recovery-cursor');
  let jobs = await state.storage.list({ prefix: RECOVERY_PREFIX, limit: 8, ...(cursor ? { startAfter: cursor } : {}) });
  if (!jobs.size && cursor) jobs = await state.storage.list({ prefix: RECOVERY_PREFIX, limit: 8 });
  if (!jobs.size) { if (state.storage.deleteAlarm) await state.storage.deleteAlarm(); return; }
  // A failed attempt survives both the alarm platform retry limit and restart.
  await state.storage.setAlarm(Date.now() + RECOVERY_DELAY_MS);
  if (!canonicalBookingAuthorityEnabled(env)) return;
  const scoped = withCanonicalBookingAuthority(env, { state, scope });
  for (const [key, job] of jobs) {
    await state.storage.put('canonical-booking-recovery-cursor', key);
    try {
      if (!sameScope(job, scope)) continue;
      const value = await state.storage.get(storageKey(job.bookingId));
      if (!value) { await state.storage.delete(key); continue; }
      await canonicalBookingOperation(state, env, { scope, bookingId: job.bookingId, operation: 'read' });
      if (value.dispatch_retry && env.DISPATCH_DEVICE_ACK_ENABLED === '1') {
        await retryDispatch(scoped, scope, job.bookingId);
      } else if (!value.dispatch_retry) {
        // Also repairs a failed index deletion after a clean checkpoint.
        await state.storage.delete(key);
      }
    } catch (_) { /* Retain the exact job; never infer release from failure. */ }
  }
  const remaining = await state.storage.list({ prefix: RECOVERY_PREFIX, limit: 1 });
  if (!remaining.size && state.storage.deleteAlarm) await state.storage.deleteAlarm();
}

function asKvValue(record, options) {
  const type = typeof options === 'string' ? options : options?.type;
  if (record == null) return null;
  if (type === 'json') return structuredClone(record);
  const text = JSON.stringify(record);
  if (type === 'arrayBuffer') return new TextEncoder().encode(text).buffer;
  if (type === 'stream') return new Response(text).body;
  return text;
}

// The same facade protects direct HTTP/cron writes and all imported modules.
// Inside the company queue it calls storage directly, avoiding a DO self-call.
export function withCanonicalBookingAuthority(env, { state, scope } = {}) {
  if (!canonicalBookingAuthorityEnabled(env)) return env;
  if (state) {
    scope = scopeOf(scope);
    if (!validScope(scope)) throw exception(failed('canonical_booking_scope_invalid', 400));
  }
  if (env[rawBookingKv] && (!state || sameScope(env[authorityScope], scope))) return env;
  const kv = env[rawBookingKv] || env.BOOKING_KV;
  if (!kv) throw exception(failed('canonical_booking_kv_unavailable'));
  const localWrites = new Map(), hints = new Map();
  async function call(owner, body) {
    const result = state && sameScope(owner, scope)
      ? await canonicalBookingOperation(state, { ...env, BOOKING_KV: kv, [rawBookingKv]: kv }, { ...body, scope: owner })
      : await callCompanyCustomerImportCoordinator({ ...env, BOOKING_KV: kv }, {
        action: 'canonical_booking', ...body, scope: owner });
    if (!result?.ok) throw exception(result || failed('canonical_booking_unavailable'));
    return result;
  }
  async function read(key, options) {
    const id = bookingIdOfKey(key);
    if (!id) return kv.get(key, options);
    let owner = state && validScope(scope) ? scope : hints.get(key);
    if (!owner) {
      owner = await resolveCanonicalBookingScope(env, id);
      if (!owner) {
        // Only an unadopted legacy booking needs a positive KV scope hint.
        const hint = await kv.get(key, { type: 'json' });
        if (!hint) return null;
        owner = scopeOf(hint);
      }
      if (!validScope(owner)) throw exception(failed('canonical_booking_scope_invalid', 409));
    }
    hints.set(key, owner);
    const result = await call(owner, { operation: 'read', bookingId: id });
    return asKvValue(result.record, options);
  }
  const wrapped = new Proxy(kv, { get(target, property) {
    if (property === 'get') return read;
    if (property === 'getWithMetadata') return async (key, options) => {
      if (!bookingIdOfKey(key)) return target.getWithMetadata(key, options);
      // Canonical booking writes carry no authoritative KV metadata.
      return { value: await read(key, options), metadata: null, cacheStatus: null };
    };
    if (property === 'put') return async (key, value, options) => {
      const id = bookingIdOfKey(key);
      if (!id) return target.put(key, value, options);
      let record;
      try { record = JSON.parse(value); } catch (_) { throw exception(failed('canonical_booking_json_required', 400)); }
      const owner = scopeOf(record);
      if (!validScope(owner) || (state && !sameScope(owner, scope))) {
        throw exception(failed('canonical_booking_scope_conflict', 403));
      }
      const originalVersion = record[VERSION] ?? 0;
      if (!Number.isSafeInteger(originalVersion) || originalVersion < 0) {
        throw exception(failed('canonical_booking_version_invalid', 400));
      }
      // Existing handlers sometimes write the same local object more than
      // once. Advance only versions successfully written by THIS invocation;
      // a concurrent writer's version still causes a CAS conflict.
      const own = localWrites.get(key);
      const expectedVersion = own?.originalVersion === originalVersion ? own.version : originalVersion;
      const result = await call(owner, { operation: 'write', bookingId: id, record, expectedVersion, options });
      localWrites.set(key, { originalVersion, version: result.record[VERSION] });
      hints.set(key, owner);
    };
    if (property === 'delete') return async key => {
      if (bookingIdOfKey(key)) throw exception(failed('canonical_booking_delete_requires_archive', 409));
      return target.delete(key);
    };
    const value = Reflect.get(target, property);
    return typeof value === 'function' ? value.bind(target) : value;
  } });
  return { ...env, BOOKING_KV: wrapped, [rawBookingKv]: kv, [authorityScope]: scope,
    [dispatchHandoff]: (owner, bookingId, intent) => call(owner, { operation: 'dispatch_handoff', bookingId, intent }) };
}

// A bounded read-only snapshot of already canonical company records. Canonical
// writers persist only after the immutable per-booking directory claim succeeds.
// Missing legacy rows deliberately fall back to normal adoption at the caller.
export async function readCanonicalCompanyPage(state,env,body){
 if(!canonicalBookingAuthorityEnabled(env))return failed('canonical_authority_disabled');
 const scope=scopeOf(body.scope),ids=body.bookingIds;
 if(!validScope(scope)||!Array.isArray(ids)||ids.length>50||ids.some(id=>!bookingIdOfKey('booking:'+id)))return failed('canonical_booking_page_invalid',400);
 const pin=await state.storage.get('canonical-booking-scope');
 if(!pin)return {ok:true,records:{}}; // Preserve normal legacy adoption.
 if(!sameScope(pin,scope))return failed('canonical_booking_scope_conflict',403);
 const records={};let pageBytes=0;
 for(const id of [...new Set(ids)]){const value=await state.storage.get(storageKey(id));if(!value)continue;
  if(!sameScope(value,scope)||!sameScope(scopeOf(value.record),scope)||value.schema!==1||!Number.isSafeInteger(value.version)||value.version<1||value.record[VERSION]!==value.version)return failed('canonical_booking_scope_conflict',403);
  const record=await hydrateCanonicalFinancialEvidence(env,value.record,id);
  const size=new TextEncoder().encode(JSON.stringify(record)).byteLength;
  // The existing caller reads omitted IDs individually through the same
  // authority. Do not retain fifty expanded tariff snapshots in one response.
  if(pageBytes+size>MAX_PAGE_RECORD_BYTES)break;
  records[id]=record;pageBytes+=size;
 }
 return {ok:true,records};
}
export async function readCanonicalCompanyPageFromWorker(env,scope,bookingIds){
 if(!canonicalBookingAuthorityEnabled(env)||!env?.COMPANY_CUSTOMER_IMPORT_COORDINATOR)return null;
 const result=await callCompanyCustomerImportCoordinator(env,{action:'canonical_booking_page',scope,bookingIds});
 if(!result?.ok)throw exception(result||failed('canonical_booking_unavailable'));
 return result.records;
}
