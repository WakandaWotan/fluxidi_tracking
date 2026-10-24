import {readCompanyDriverSubset} from './driver_index_mutation.mjs';
// A cohort contains calls submitted BEFORE its authoritative read starts.
// Remove it before awaiting authority: late callers must get a NEW snapshot.
// There is no settled cache, timer, mutable-state reuse or capacity authority.
const owners = new WeakMap();
export function batchedDriverRead(owner, scope, driverId, read, { maxIds = 128 } = {}) {
  if (!owner || typeof owner !== 'object' || !scope?.tenant_id || !scope.company_id ||
      typeof driverId !== 'string' || !driverId || driverId.length > 96 ||
      !Number.isInteger(maxIds) || maxIds < 1 || maxIds > 500)
    return Promise.reject(Error('driver_read_batch_invalid'));
  let pending = owners.get(owner); if (!pending) { pending = new Map(); owners.set(owner, pending); }
  const key = JSON.stringify([scope.tenant_id, scope.company_id]);
  let cohort = pending.get(key);
  // The first caller owns the read contract. Distinct adapters cannot be merged.
  if (cohort && (cohort.read !== read || cohort.requests.length >= 256 ||
      !cohort.ids.has(driverId) && cohort.ids.size >= maxIds)) cohort = null;
  if (!cohort && pending.size >= 32) return Promise.resolve()
    .then(() => read(scope, [driverId])).then(record => ({
      driver: structuredClone(record.drivers?.[driverId] ?? null),
      generation: record.driver_index_generation || 0, cohortSize: 1,
    }));
  if (!cohort) {
    cohort = { read, ids: new Set(), requests: [] };
    // A full previous cohort is already scheduled; replacing discovery does not
    // discard its subscribers. Its drain only removes its OWN discovery entry.
    pending.set(key, cohort);
    const current = cohort;
    queueMicrotask(async () => {
      if (pending.get(key) === current) pending.delete(key);
      try {
        const record = await current.read(scope, [...current.ids]);
        for (const request of current.requests) request.resolve({
          driver: structuredClone(record.drivers?.[request.driverId] ?? null),
          generation: record.driver_index_generation || 0,
          cohortSize: current.requests.length,
        });
      } catch (error) { for (const request of current.requests) request.reject(error); }
    });
  }
  cohort.ids.add(driverId);
  return new Promise((resolve, reject) => cohort.requests.push({ driverId, resolve, reject }));
}

const adapters = new WeakMap();
export function readDriverEligibilityBatched(env, scope, driverId) {
  const owner = env?.DRIVER_INDEX_COORDINATOR;
  if (!owner || typeof owner !== 'object') return readCompanyDriverSubset(env,scope,{driver_ids:[driverId]})
    .then(record=>({driver:record.drivers?.[driverId]??null,generation:record.driver_index_generation||0}));
  let read = adapters.get(owner);
  if (!read) {
    read = (scoped, ids) => readCompanyDriverSubset(env, scoped, {driver_ids:ids});
    adapters.set(owner, read);
  }
  return batchedDriverRead(owner,scope,driverId,read);
}
