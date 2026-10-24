// Provider-independent lower bound for the existing ASAP search. Geography
// changes order only: an unrestricted snapped Mapbox route has no documented
// speed/snap-distance bound. Missing proof therefore contributes ZERO road time.
export function asapArrivalLowerBound({ nowMs, departureMs, keepPickupMs, marginMs = 30000 }) {
  const initial = Math.max(nowMs, Number.isFinite(departureMs) ? departureMs : nowMs) + marginMs;
  return Number.isFinite(keepPickupMs) && keepPickupMs > nowMs ? Math.min(initial, keepPickupMs) : initial;
}
export function cannotBeat(lowerBound, order, incumbent) {
  return Boolean(incumbent && Number.isFinite(lowerBound)
    && (lowerBound > incumbent.pickup_ms || lowerBound === incumbent.pickup_ms && order > incumbent.order));
}
// evaluate must retain the existing authoritative eligibility/road evaluator.
// A bound is conservative evidence, never permission to assign a resource.
export async function boundedCandidateSearch(candidates, { lowerBound, evaluate }) {
  const proposals = []; let incumbent = null, pruned = 0, evaluated = 0, last = null;
  for (const candidate of candidates) {
    const bound = lowerBound(candidate);
    if (cannotBeat(bound, candidate.order, incumbent)) { pruned++; continue; }
    const resolved = await evaluate(candidate); evaluated++; last = resolved;
    if (resolved?.allowed && Number.isFinite(resolved.pickup_ms)) {
      const proposal = { ...candidate, resolved };
      proposals.push(proposal);
      if (!incumbent || resolved.pickup_ms < incumbent.pickup_ms
        || resolved.pickup_ms === incumbent.pickup_ms && candidate.order < incumbent.order) {
        incumbent = { pickup_ms: resolved.pickup_ms, order: candidate.order };
      }
    }
  }
  return { proposals, pruned, evaluated, last };
}

// Owned by one advisory preparation only. No persistent/cross-booking TTL,
// no nearby-coordinate approximation, and no credential/PII key material.
export function createExactPreparationRoutes({ maxEntries = 1024 } = {}) {
  if (!Number.isSafeInteger(maxEntries) || maxEntries < 1 || maxEntries > 4096) throw Error('route_memo_limit_invalid');
  const entries = new Map();
  return {
    get size() { return entries.size; },
    async resolve(key, run) {
      if (entries.has(key)) return { value: structuredClone(await entries.get(key)), hit: true };
      if (entries.size >= maxEntries) return { value: await run(), hit: false };
      const pending = Promise.resolve().then(run); entries.set(key, pending);
      try { const value=await pending;if(value?.ok===false&&entries.get(key)===pending)entries.delete(key);return { value: structuredClone(value), hit: false }; }
      catch (error) { if (entries.get(key) === pending) entries.delete(key); throw error; }
    },
  };
}
