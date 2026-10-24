// Local candidate for an isolated staging availability read. This module is
// intentionally not wired into the Worker or the public availability ingress.
import {readBoundedJson} from './bounded_json_storage.mjs';
import {_companyDriverIndexKey} from './driver_ops.js';
import {createPerDriverState} from '../../tracking/modules/per_driver_state.mjs';

const INDEX_SCOPE_KEY = 'driver-index-scope-v1';
const INDEX_PENDING_KEY = 'driver-index-pending-v1';
const INDEX_KEY = 'drivers-index-v1';
const PRESENCE_KEY = 'company-presence-v1';
const PRESENCE_TTL_MS = 24 * 60 * 60 * 1000;

const refusal = error => ({ok:false,status:503,error});
const sameScope = (a,b) => a?.tenant_id === b?.tenant_id && a?.company_id === b?.company_id;
const record = value => value && typeof value === 'object' && !Array.isArray(value);
const canonical = value => JSON.stringify(value, (_, child) =>
  record(child) ? Object.fromEntries(Object.keys(child).sort().map(key => [key, child[key]])) : child);

export async function readStagingFrozenDriverStateV1({env,storage,scope,nowMs=Date.now()} = {}) {
  if (env?.STAGING_TRIAL_MODE !== '1' || env?.STAGING_TRIAL_ENVIRONMENT !== 'staging') {
    return refusal('staging_trial_configuration_required');
  }
  if (!scope?.tenant_id || !scope?.company_id || typeof storage?.get !== 'function'
    || typeof env?.BOOKING_KV?.get !== 'function' || !Number.isSafeInteger(nowMs)) {
    return refusal('staging_frozen_state_configuration_required');
  }
  try {
    const bound = await storage.get(INDEX_SCOPE_KEY);
    if (!bound || !sameScope(bound,scope)) return refusal('staging_frozen_scope_unavailable');
    if (await readBoundedJson(storage,INDEX_PENDING_KEY)
      || await storage.get(`${INDEX_KEY}:chunk-intent`)) {
      return refusal('staging_frozen_index_recovery_pending');
    }
    const durable = await readBoundedJson(storage,INDEX_KEY);
    const published = await env.BOOKING_KV.get(_companyDriverIndexKey(scope),{type:'json'});
    const generation = Number(durable?.driver_index_generation);
    if (!record(durable) || !record(durable.drivers) || !record(published)
      || !record(published.drivers) || !Number.isSafeInteger(generation) || generation < 1
      || generation !== Number(published.driver_index_generation)
      || canonical(durable) !== canonical(published)) {
      return refusal('staging_frozen_index_unavailable');
    }

    const presenceMarker = await storage.get(PRESENCE_KEY);
    const updatedMs = Date.parse(presenceMarker?.updated_at || '');
    if (presenceMarker?.format !== 'per-driver-v2'
      || !Number.isSafeInteger(presenceMarker?.revision) || presenceMarker.revision < 1
      || !Number.isFinite(updatedMs) || updatedMs > nowMs
      || nowMs - updatedMs >= PRESENCE_TTL_MS
      || await storage.get(`${PRESENCE_KEY}:adoption-v2`)) {
      return refusal('staging_frozen_presence_unavailable');
    }
    const drivers = await createPerDriverState(storage,PRESENCE_KEY,'presence-driver:v2:', {
      extract: value => value.drivers || {},
    }).loadReadOnly();
    if (!record(drivers) || Object.values(drivers).some(row => !record(row)
      || row.tenant_id && row.tenant_id !== scope.tenant_id
      || row.company_id && row.company_id !== scope.company_id)) {
      return refusal('staging_frozen_presence_unavailable');
    }
    return {ok:true,index:durable,presence:{drivers,updated_at:presenceMarker.updated_at,
      presence_revision:presenceMarker.revision}};
  } catch (_) {
    return refusal('staging_frozen_state_unavailable');
  }
}
