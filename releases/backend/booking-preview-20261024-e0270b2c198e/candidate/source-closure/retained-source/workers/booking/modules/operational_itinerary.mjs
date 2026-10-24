// Explicit remaining itinerary. Never infer completed stops from GPS proximity.
export const MAX_REMAINING_STOPS = 8;
export function normalizeRemainingItinerary(value) {
  const declared = value?.remaining_route_complete;
  const raw = value?.remaining_stops;
  if (declared == null && raw == null) return { ok: true, declared: false, stops: [] };
  if (declared !== true || !Array.isArray(raw) || raw.length > MAX_REMAINING_STOPS)
    return { ok: false, error: 'operational_itinerary_invalid' };
  const stops = [];
  let waiting = 0;
  for (const stop of raw) {
    const wait = stop?.wait_seconds ?? 0;
    if (!stop || typeof stop.lat !== 'number' || !Number.isFinite(stop.lat) || Math.abs(stop.lat) > 90
      || typeof stop.lng !== 'number' || !Number.isFinite(stop.lng) || Math.abs(stop.lng) > 180
      || typeof stop.address !== 'string' || !stop.address.trim() || stop.address.length > 400
      || !Number.isSafeInteger(wait) || wait < 0 || wait > 43200)
      return { ok: false, error: 'operational_itinerary_invalid' };
    waiting += wait;
    if (waiting > 86400) return { ok: false, error: 'operational_itinerary_invalid' };
    const notBefore = stop.not_before_iso;
    if (notBefore != null && (typeof notBefore !== 'string' || !Number.isFinite(Date.parse(notBefore))))
      return { ok: false, error: 'operational_itinerary_invalid' };
    stops.push({ lat: stop.lat, lng: stop.lng, address: stop.address.trim(), wait_seconds: wait,
      ...(notBefore == null ? {} : { not_before_iso: new Date(notBefore).toISOString() }) });
  }
  return { ok: true, declared: true, stops };
}

export function operationalRideBlocking(value) {
  const status = String(value?.status || value?.lifecycle_status || '').toUpperCase();
  const phase = String(value?.customer_tracking_phase || '').toLowerCase();
  if (['completed', 'cancelled', 'canceled', 'ended'].includes(phase)
    || ['STOP', 'STOPPED', 'COMPLETED', 'DONE', 'FINISHED', 'CANCELLED', 'CANCELED', 'NO_SHOW', 'REJECTED'].includes(status)) return false;
  return phase === 'in_progress' || status === 'IN_PROGRESS';
}

export function activeItineraryLeg(record) {
  const active = (record?.operational_legs || []).filter(operationalRideBlocking);
  return active.length === 1 ? active[0] : null;
}

export function nextOperationalPoint(route) {
  const itinerary = normalizeRemainingItinerary(route);
  return itinerary.ok && itinerary.declared && itinerary.stops.length ? itinerary.stops[0] : route?.destination;
}
