// ASAP intent is a short-lived server search, not permission to move a missed
// scheduled appointment. Arrival may still be up to the existing public 4h.
export const ASAP_SEARCH_MS = 10 * 60_000;
export const ASAP_ARRIVAL_HORIZON_MS = 4 * 3_600_000;
export const ASAP_CONFIRMATION_MARGIN_MS = 30_000;

export function pickupMode(payload) {
  const explicit = String(payload?.pickup_mode || '').trim().toLowerCase();
  if (explicit) return ['asap', 'scheduled'].includes(explicit) ? explicit : null;
  return payload?.when_now === true || payload?.when_now === 'true' ? 'asap' : 'scheduled';
}

export function serverPickupIntent(payload, nowMs = Date.now()) {
  const mode = pickupMode(payload);
  return mode === 'asap' ? { pickup_mode: mode,
    asap_requested_at: new Date(nowMs).toISOString(),
    asap_search_expires_at: new Date(nowMs + ASAP_SEARCH_MS).toISOString() }
    : { pickup_mode: mode };
}

export function asapSearchState(record, nowMs = Date.now()) {
  if (record?.pickup_mode !== 'asap') return { asap: false };
  const requestedMs = Date.parse(record.asap_requested_at || '');
  const expiresMs = Date.parse(record.asap_search_expires_at || '');
  const valid = Number.isFinite(requestedMs) && requestedMs <= nowMs
    && expiresMs === requestedMs + ASAP_SEARCH_MS;
  return { asap: true, valid, expired: !valid || nowMs >= expiresMs, requestedMs, expiresMs };
}

export function freshAsapOrigin(value, departureMs) {
  return value?.origin_source === 'company_live'
    || value?.origin_source === 'tracking_ping' && Number(value.origin_age_seconds) <= 180
    || Number.isFinite(departureMs) && value?.origin_source === 'previous_reservation_dropoff';
}

// Quote, offer and receipt use this same bounded arrival search. An existing
// held window is kept only if the current full evaluator still proves it.
export async function resolveAsapArrival({ evaluate, nowMs = Date.now(), departureMs,
  keepPickupMs, horizonMs = nowMs + ASAP_ARRIVAL_HORIZON_MS }) {
  const allowed = value => value?.would_allow_booking === true || value?.allowed === true;
  const usable = value => freshAsapOrigin(value, departureMs);
  if (Number.isFinite(keepPickupMs) && keepPickupMs > nowMs && keepPickupMs <= horizonMs) {
    const existing = await evaluate(keepPickupMs);
    if (allowed(existing) && usable(existing)) return { ...existing, pickup_ms: keepPickupMs };
  }
  let at = Math.max(nowMs, Number.isFinite(departureMs) ? departureMs : nowMs) + ASAP_CONFIRMATION_MARGIN_MS;
  let result = { allowed: false, would_allow_booking: false, reason: 'asap_arrival_unavailable' };
  // A full recheck can expose a later prior reservation. Bound route work;
  // no successful result is accepted solely from its suggested timestamp.
  for (let attempt = 0; attempt < 3 && at <= horizonMs; attempt++) {
    result = await evaluate(at);
    if (!usable(result)) return { ...result, allowed: false, would_allow_booking: false,
      reason: result?.reason || 'asap_live_origin_unavailable', pickup_ms: null };
    if (allowed(result)) return { ...result, pickup_ms: at };
    const earliest = result?.earliest_available_at_ms;
    if (!Number.isFinite(earliest) || earliest + ASAP_CONFIRMATION_MARGIN_MS <= at) break;
    at = earliest + ASAP_CONFIRMATION_MARGIN_MS;
  }
  return { ...result, allowed: false, would_allow_booking: false, pickup_ms: null,
    ...(at > horizonMs ? { reason: 'asap_arrival_horizon_exceeded' } : {}) };
}

// Persist the new canonical window before retiring an offer. Claims are never
// edited in place: the coordinator then uses its existing refresh protocol.
export function applyAsapPickup(record, pickupMs) {
  if (!Number.isFinite(pickupMs)) return false;
  const iso = new Date(pickupMs).toISOString();
  const current = record.pickup_iso || record.booking?.pickup_iso || record.booking?.pickupStartIso;
  if (current === iso) return false;
  for (const source of [record, record.booking, record.payload, record.quote]) {
    if (!source || typeof source !== 'object') continue;
    source.pickup_iso = iso;
    for (const key of ['pickupIso', 'pickupStartIso', 'start_at', 'startAt']) {
      if (key in source) source[key] = iso;
    }
  }
  const collections = new Set([record.operational_legs, record.operationalLegs,
    record.booking?.operational_legs, record.booking?.operationalLegs]);
  for (const legs of collections) for (const leg of Array.isArray(legs) ? legs : []) {
    if (leg.leg_type !== 'outbound') continue;
    leg.pickup_iso = iso;
    if ('pickupIso' in leg) leg.pickupIso = iso;
  }
  // A server-computed waiting return follows the newly sealed ASAP pickup.
  // Its validated journey has no separately chosen return appointment.
  // Keep explicit returns and every financial/quote snapshot untouched.
  const choice = record.p12_reliable_choice, journey = choice?.journey;
  if (choice?.schema === 'fluxidi-reliable-choice-v1'
    && journey?.schema === 'fluxidi-reliable-journey-v1'
    && journey.mode === 'continuous_wait' && journey.returnAt == null
    && typeof journey.graphVersion === 'string' && journey.graphVersion.trim().length > 0
    && journey.graphVersion === choice.graph_version
    && Number.isFinite(journey.outboundMinutes) && journey.outboundMinutes > 0
    && Number.isFinite(journey.waitMinutes) && journey.waitMinutes > 0) {
    const financialMinutes = Number(record.booking?.duration_route_min);
    const minutes = Math.max(journey.outboundMinutes,
      Number.isFinite(financialMinutes) && financialMinutes >= 0 ? financialMinutes : 0);
    const returnMs = pickupMs + (minutes + journey.waitMinutes) * 60000;
    if (!Number.isFinite(returnMs) || Math.abs(returnMs) > 8640000000000000) throw Error('reliable_return_time_invalid');
    const returnIso = new Date(returnMs).toISOString();
    for (const source of [record, record.booking, record.payload]) {
      if (!source || typeof source !== 'object') continue;
      source.return_pickup_iso = returnIso;
      if ('returnPickupIso' in source) source.returnPickupIso = returnIso;
    }
  }
  delete record.dispatch_timing_attention;
  record.asap_resolved_at = new Date().toISOString();
  return true;
}

export function acceptedPickupResponse(record) {
  if (record?.pickup_mode !== 'asap') return {};
  const outbound = (record.operational_legs || record.operationalLegs || record.booking?.operational_legs || [])
    .find(leg => String(leg.leg_type || leg.legType).toLowerCase() === 'outbound');
  const sources = outbound ? [outbound] : [record, record.booking].filter(Boolean);
  const assigned = sources.some(source => (source.assigned_driver_id || source.assignedDriverId)
    && (source.assigned_vehicle_id || source.assignedVehicleId));
  const iso = outbound?.pickup_iso || outbound?.pickupIso || record.pickup_iso || record.booking?.pickupStartIso || null;
  const pickupMs = Date.parse(iso || ''), search = asapSearchState(record), offer = record.dispatch_offer;
  // A previous proposal is not current acceptance. A hard canonical assignment
  // retains its appointment even after discovery expiry; an unconfirmed window
  // needs the current bound offer and a still-future pickup inside that search.
  const proposed = record.asap_resolved_at && search.valid && !search.expired && pickupMs > Date.now()
    && ['prepared', 'offered'].includes(offer?.state) && record.revision === offer.record_revision;
  return { pickup_mode: 'asap', pickup_iso: Number.isFinite(pickupMs) && (assigned || proposed) ? iso : null };
}
