// GPS polling stays independent of Directions. Only public route data lives
// here; access, lifecycle and assignment are revalidated by the live handler.
const EARTH_METERS = 6_371_000;
const radians = value => value * Math.PI / 180;
function point(value) {
  if (value?.latitude == null || value?.longitude == null) return null;
  const latitude = Number(value?.latitude), longitude = Number(value?.longitude);
  return Number.isFinite(latitude) && Number.isFinite(longitude) && Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180
    ? { latitude, longitude } : null;
}
function distance(a, b) {
  const lat = radians(b.latitude - a.latitude), lon = radians(b.longitude - a.longitude);
  const h = Math.sin(lat / 2) ** 2 + Math.cos(radians(a.latitude)) * Math.cos(radians(b.latitude)) * Math.sin(lon / 2) ** 2;
  return 2 * EARTH_METERS * Math.asin(Math.min(1, Math.sqrt(h)));
}
function routeDistance(origin, route) {
  const coordinates = Array.isArray(route?.coordinates) ? route.coordinates : null;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return Infinity;
  const factor = Math.cos(radians(origin.latitude)), scale = EARTH_METERS * Math.PI / 180;
  const xy = row => [(row.longitude - origin.longitude) * scale * factor, (row.latitude - origin.latitude) * scale];
  let best = Infinity;
  for (let i = 1; i < coordinates.length; i++) {
    const a = xy(coordinates[i - 1]), b = xy(coordinates[i]), dx = b[0] - a[0], dy = b[1] - a[1];
    const t = Math.max(0, Math.min(1, -(a[0] * dx + a[1] * dy) / (dx * dx + dy * dy || 1)));
    best = Math.min(best, Math.hypot(a[0] + t * dx, a[1] + t * dy));
  }
  return best;
}

export function createAdaptiveEtaCache(fetcher, now = () => Date.now(),
  { maxEntries = 128, maxInflight = 32, maxBytes = 4 * 1024 * 1024 } = {}) {
  const entries = new Map(), inflight = new Map();
  let storedBytes = 0;
  const remove = key => { const entry = entries.get(key); if (entry) storedBytes -= entry.bytes; entries.delete(key); };
  const limits = { entries: Math.max(1, maxEntries), inflight: Math.max(1, maxInflight), bytes: Math.max(1, maxBytes) };
  function publicValue(entry, origin, cache) {
    const age = Math.max(0, (now() - entry.at) / 1000);
    return { ...entry.value, cache, estimated: age > 0 || cache === 'hit', age_seconds: age,
      refreshed_at: new Date(entry.at).toISOString(), position_basis: origin, provider_origin: entry.origin,
      // No time/distance extrapolation: traffic is not uniform along a route.
      source: 'mapbox/driving-traffic',
      estimate_source: age > 0 || cache === 'hit' ? 'cached_provider_route' : 'provider',
      provider_source: 'mapbox/driving-traffic', route_age_seconds: age,
      valid_until: new Date(entry.at + entry.refreshMs).toISOString() };
  }
  return {
    diagnostics: () => ({ entries: entries.size, inflight: inflight.size, bytes: storedBytes }),
    async resolve({ origin: rawOrigin, destination: rawDestination, target, context = {}, observability }) {
      const origin = point(rawOrigin), destination = point(rawDestination);
      if (!origin || !destination) return null;
      if (!context.tenant_id || !context.company_id || !context.booking_id) throw Error('customer_eta_scope_required');
      const key = JSON.stringify([context.tenant_id, context.company_id, context.booking_id,
        context.operational_leg || 'primary', context.session_id || '', context.assignment_version || '',
        context.lifecycle_seq || '', target, 'mapbox/driving-traffic', 'overview=simplified;geometries=geojson',
        destination.latitude, destination.longitude]);
      const at = now();
      // GPS publication and customer polling have different cadences. Derive
      // movement from captured sample time, never from viewer request spacing.
      const capturedAt = Date.parse(rawOrigin?.captured_at || rawOrigin?.position_captured_at || '');
      const sampleAt = Number.isFinite(capturedAt) ? capturedAt : at;
      for (const [oldKey, entry] of entries) if (at - entry.at >= 120_000) remove(oldKey);
      const entry = entries.get(key);
      let speed = entry?.speed ?? null, motionChanged = false;
      if (entry && sampleAt > entry.observedAt) {
        const elapsed = (sampleAt - entry.observedAt) / 1000;
        const moved = distance(entry.observedOrigin, origin);
        speed = moved / elapsed;
        // A stop/start or unexpected progress (for example a cleared queue)
        // invalidates the traffic estimate immediately at the next GPS poll.
        motionChanged = entry.speed !== null
          ? (entry.speed > 1 && speed < .5) || (entry.speed < .5 && speed > 2) || Math.abs(speed - entry.speed) > 5
          : speed > Math.max(5, (entry.value.distance_meters / Math.max(1, entry.value.duration_seconds)) * 2);
        entry.observedAt = sampleAt; entry.observedOrigin = origin; entry.speed = speed;
      }
      const refreshMs = speed === null || speed < .5 ? 60_000 : speed < 4 ? 50_000 : 40_000;
      if (entry && at >= entry.at && at - entry.at < refreshMs && !motionChanged
        && distance(entry.origin, origin) < 1200 && routeDistance(origin, entry.value.route) <= 50) {
        entry.refreshMs = refreshMs;
        entries.delete(key); entries.set(key, entry);
        return publicValue(entry, origin, 'hit');
      }
      // Once invalidated, a failed refresh must not resurrect the old traffic
      // estimate on the next poll (the observed speed may already have changed).
      if (entry) remove(key);
      // Coalesce only identical origin/context work. A newer GPS sample is
      // never joined to an older origin's provider request.
      const flightKey = JSON.stringify([key, origin.latitude, origin.longitude]);
      if (inflight.has(flightKey)) return publicValue(await inflight.get(flightKey), origin, 'joined');
      const task = (async () => {
        const value = await fetcher({ origin, destination, target, observability });
        if (!value || !Number.isFinite(value.duration_seconds) || value.duration_seconds < 0) throw Error('customer_eta_invalid');
        const saved = { at: now(), requestedAt: at, origin, observedOrigin: origin, observedAt: sampleAt, speed, refreshMs,
          value: { target, duration_seconds: value.duration_seconds, distance_meters: value.distance_meters ?? null, route: value.route ?? null } };
        saved.bytes = new TextEncoder().encode(JSON.stringify(saved)).byteLength;
        // A concurrent older provider response must not overwrite fresher GPS.
        if (saved.bytes <= limits.bytes && (!entries.has(key)
          || entries.get(key).observedAt <= sampleAt && entries.get(key).requestedAt <= at)) {
          remove(key);
          while (entries.size >= limits.entries || storedBytes + saved.bytes > limits.bytes) remove(entries.keys().next().value);
          entries.set(key, saved); storedBytes += saved.bytes;
        }
        return saved;
      })();
      if (inflight.size < limits.inflight) inflight.set(flightKey, task);
      try { return publicValue(await task, origin, 'miss'); }
      finally { if (inflight.get(flightKey) === task) inflight.delete(flightKey); }
    },
  };
}
