// Called only inside the existing company DriverIndexCoordinatorDO queue.
// KV is a one-time migration input, never a competing heartbeat writer.
import { companyDriverPresenceKey, mergePresenceHeartbeat } from './company_dispatch.mjs';
import { createPerDriverState } from '../../tracking/modules/per_driver_state.mjs';
import { emitTenantCostMetric } from './tenant_cost_metrics.mjs';

const PRESENCE_STORAGE_KEY = 'company-presence-v1';
const LEGACY_TTL_MS = 24 * 60 * 60 * 1000;
const stores = new WeakMap();
const pruneTimes = new WeakMap();

export async function presenceOperation(env, storage, scope, mutation) {
  let store = stores.get(storage);
  if (!store) {
   if (await storage.get(PRESENCE_STORAGE_KEY) == null) {
    const legacy = await env.BOOKING_KV.get(companyDriverPresenceKey(scope), { type: 'json' });
    if (legacy != null && (typeof legacy !== 'object' || Array.isArray(legacy)
      || legacy.drivers != null && (typeof legacy.drivers !== 'object' || Array.isArray(legacy.drivers)))) {
      throw Error('presence_legacy_invalid');
    }
    const record = legacy || { drivers: {} };
    // Durable adoption also handles empty maps, so stale KV cannot re-seed later.
    await storage.put(PRESENCE_STORAGE_KEY, record);
   }
   store = createPerDriverState(storage, PRESENCE_STORAGE_KEY, 'presence-driver:v2:', {
    extract: value => value.drivers || {}, wrap: (drivers, metadata) => ({ drivers, updated_at: metadata.updated_at }),
    onWrite: env.TENANT_COST_METRICS_ENABLED === '1' ? async (row, writes, bytes) => {
      await emitTenantCostMetric(env, scope, 'storage_writes', writes);
      await emitTenantCostMetric(env, scope, 'storage_bytes', bytes);
    } : undefined,
   });
   await store.load(); stores.set(storage, store);
  }
  let record = { drivers: await store.load(), updated_at: store.metadata.updated_at };
  const nowMs = mutation?.now_ms ?? Date.now();
  const updatedMs = Date.parse(record.updated_at || '');
  if (Number.isFinite(updatedMs) && nowMs - updatedMs >= LEGACY_TTL_MS) {
    // Expire the durable rows too. Otherwise a new heartbeat would resurrect
    // the expired company map when its small updated_at marker moves forward.
    await store.clear({ updated_at: new Date(nowMs).toISOString() });
    record = { drivers: {}, updated_at: new Date(nowMs).toISOString() };
  }
  if(mutation?.metadata_only===true)return {ok:true,revision:store.revision,updated_at:store.metadata.updated_at||''};
  if (!mutation || Array.isArray(mutation.driver_ids)) {
    if (env.ENTERPRISE_DRIVER_STATE_RETENTION_ENABLED === '1' && !mutation?.driver_ids
      && nowMs - (pruneTimes.get(storage) || 0) >= 3600000) {
      const pruned = await store.prune(row => {
        const seen = Date.parse(row?.last_seen_at || '');
        return Number.isFinite(seen) && nowMs - seen >= LEGACY_TTL_MS;
      });
      record.drivers = pruned.rows;
      if (pruned.removed < 127) pruneTimes.set(storage, nowMs);
    }
    if (mutation?.driver_ids) record = { ...record, drivers: Object.fromEntries(mutation.driver_ids
      .filter(id => typeof id === 'string' && record.drivers[id]).map(id => [id, record.drivers[id]])) };
    return { ok: true, record: { ...record, presence_revision: store.revision } };
  }
  if (typeof mutation.driver_id !== 'string' || !mutation.driver_id.trim()
    || !Number.isFinite(nowMs) || !Number.isFinite(new Date(nowMs).getTime())) throw Error('presence_heartbeat_invalid');
  const merged = mergePresenceHeartbeat({ drivers: { [mutation.driver_id]: record.drivers[mutation.driver_id] } }, mutation.driver_id, nowMs);
  if (merged.changed) {
    await store.write(mutation.driver_id, merged.record.drivers[mutation.driver_id], { updated_at: merged.record.updated_at });
    const previous = Date.parse(record.drivers[mutation.driver_id]?.last_seen_at || '');
    if (Number.isFinite(previous) && nowMs > previous && nowMs - previous <= 180000)
      await emitTenantCostMetric(env, scope, 'online_driver_seconds', (nowMs - previous) / 1000);
  }
  const current = merged.changed ? merged.record : record;
  return { ok: true, wrote: merged.changed, last_seen_at: current.drivers?.[mutation.driver_id]?.last_seen_at || '' };
}
