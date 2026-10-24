// Share only a currently pending, read-only snapshot operation. No TTL cache,
// capacity result, route evidence or settled value survives a flight.
// Namespace identity and the exact ordered query are part of the key.
const owners = new WeakMap();
export async function sharedAdvisoryRead(owner, key, load, {maxPending = 32} = {}) {
  if (!owner || !['object','function'].includes(typeof owner)) return {value:await load(),shared:false};
  if (!Number.isSafeInteger(maxPending) || maxPending < 1 || maxPending > 128 || typeof key !== 'string') throw Error('advisory_flight_options_invalid');
  let pending = owners.get(owner);
  if (!pending) { pending = new Map(); owners.set(owner,pending); }
  const existing = pending.get(key);
  if (existing) return {value:structuredClone(await existing),shared:true};
  if (pending.size >= maxPending) return {value:await load(),shared:false};
  const task = Promise.resolve().then(load); pending.set(key,task);
  try { return {value:structuredClone(await task),shared:false}; }
  finally { if (pending.get(key) === task) pending.delete(key); }
}
