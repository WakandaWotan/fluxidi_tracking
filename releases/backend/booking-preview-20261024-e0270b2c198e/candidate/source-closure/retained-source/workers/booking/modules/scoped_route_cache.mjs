// Isolate-local cache of route data only. Eligibility must never be stored here.
export function createBoundedRouteCache({ ttlMs = 30_000, maxEntries = 512, maxInflight = 128,
  now = () => Date.now(), cacheable = value => value && Number.isFinite(value.duration_seconds) && value.duration_seconds >= 0 } = {}) {
  const cache = new Map(), inflight = new Map();
  const evictExpired = () => { const at = now(); for (const [key, row] of cache) if (row.expires <= at) cache.delete(key); };
  return {
    cache, inflight,
    async resolve(key, fetcher, inflightKey = key) {
      evictExpired();
      const hit = cache.get(key);
      if (hit) { cache.delete(key); cache.set(key,hit); return { value: hit.value, cache: 'hit' }; }
      if (inflight.has(inflightKey)) return { value: await inflight.get(inflightKey), cache: 'joined' };
      const bounded = inflight.size < maxInflight;
      const pending = Promise.resolve().then(fetcher).then(value => {
        if (cacheable(value)) {
          evictExpired();
          cache.delete(key);
          while (cache.size >= maxEntries && cache.size) cache.delete(cache.keys().next().value);
          if (maxEntries > 0) cache.set(key,{ value, expires: now()+ttlMs });
        }
        return value;
      }).finally(() => { if (bounded && inflight.get(inflightKey) === pending) inflight.delete(inflightKey); });
      if (bounded) inflight.set(inflightKey,pending);
      return { value: await pending, cache: bounded ? 'miss' : 'bypass' };
    },
  };
}

const plannerCaches = new WeakMap();
export function plannerRouteCache(env) {
  if (!plannerCaches.has(env)) plannerCaches.set(env,createBoundedRouteCache());
  return plannerCaches.get(env);
}

export function plannerRouteKey({ tenantId, companyId, origin, destination, departAt, target = 'pickup' }) {
  if (!tenantId || !companyId) throw Error('route_cache_scope_required');
  const bucket = point => [Number(point.latitude).toFixed(4),Number(point.longitude).toFixed(4)];
  const departure = departAt ? Date.parse(departAt) : null;
  return JSON.stringify([tenantId,companyId,'mapbox/driving-traffic','overview=false',target,
    bucket(origin),[destination.latitude,destination.longitude],
    Number.isFinite(departure) ? [Math.floor(departure/30_000),new Date(departure).toISOString()] : null]);
}
