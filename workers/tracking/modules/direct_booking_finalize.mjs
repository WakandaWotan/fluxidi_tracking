// STREET-RIDE-DURABLE-COMPLETION-2 — durable street/direct booking finalization.
//
// Pure, dependency-free helpers that decide how a street/direct tracking trip
// drives the linked booking's completion. They are deliberately free of any
// Cloudflare/KV/env dependency so the finalize + reconcile + repair decision
// logic can be unit-tested with `node --test`.
//
// Invariants encoded here:
//   * one street ride owns exactly one durable booking_id + one authoritative
//     final fare (read from the persisted tracking trip, never re-computed);
//   * booking finalization is monotonic: once `completed`, it never regresses
//     to `pending`;
//   * the final fare is derived EXCLUSIVELY from the persisted trip totals
//     (already rounded once at stop by `directTripTotals`), so reconcile/repair
//     never introduce a second fare calculation or a second rounding.
//
// Run: node --test workers/tracking/modules/direct_booking_finalize.test.mjs

export const DIRECT_BOOKING_FINALIZE_STATE = Object.freeze({
  COMPLETED: "completed",
  PENDING: "pending",
});

// Coarse, PII-free reasons shared by the reconcile endpoint and the batch
// repair report so both surfaces classify a trip identically.
export const DIRECT_RECONCILE_REASON = Object.freeze({
  REPAIRABLE: "repairable",
  ALREADY_COMPLETED: "already_completed",
  MISSING_TRIP: "skipped_missing_trip",
  NOT_STREET_DIRECT: "skipped_not_street_direct",
  MISSING_BOOKING_ID: "skipped_missing_trip", // no durable booking ⇒ nothing to link
  NON_TERMINAL: "skipped_non_terminal",
  MISSING_FARE: "skipped_missing_fare",
});

function _str(v, max = 200) {
  if (v === null || v === undefined) return "";
  const s = String(v).trim();
  return max > 0 ? s.slice(0, max) : s;
}

function _numOrNull(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** True when the trip represents a street / direct ride. */
export function isStreetDirectTrip(trip) {
  if (!trip || typeof trip !== "object") return false;
  const kind = _str(trip.kind).toLowerCase();
  const source = _str(trip.source).toLowerCase();
  return kind === "direct" || source === "street_ride";
}

/** True once the tracking trip has reached a terminal (stopped) state. */
export function tripIsTerminal(trip) {
  if (!trip || typeof trip !== "object") return false;
  const status = _str(trip.status).toLowerCase();
  if (status === "stopped" || status === "completed" || status === "done") {
    return true;
  }
  return _str(trip.stopped_at).length > 0;
}

/** Durable booking id owned by this trip (never a client-provided fallback). */
export function directBookingIdFromTrip(trip) {
  if (!trip || typeof trip !== "object") return "";
  return _str(trip.booking_id ?? trip.bookingId, 160);
}

/**
 * Authoritative final fare (in integer cents) read ONLY from the persisted
 * trip totals. Returns null when no non-negative fare is present. This is the
 * single fare source for reconcile/repair — no re-computation, no re-rounding.
 */
export function authoritativeTripFareCents(trip) {
  if (!trip || typeof trip !== "object") return null;
  for (const raw of [trip.price_incl_vat, trip.total_eur]) {
    const n = _numOrNull(raw);
    if (n !== null && n >= 0) return Math.round(n * 100);
  }
  return null;
}

export function tripHasAuthoritativeFare(trip) {
  return authoritativeTripFareCents(trip) !== null;
}

/**
 * Classify a trip for reconcile / repair. Returns `{ ok, reason }` where reason
 * is one of the coarse DIRECT_RECONCILE_REASON tokens.
 */
export function tripReconcileEligibility(trip) {
  if (!trip || typeof trip !== "object") {
    return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_TRIP };
  }
  if (!isStreetDirectTrip(trip)) {
    return { ok: false, reason: DIRECT_RECONCILE_REASON.NOT_STREET_DIRECT };
  }
  if (!directBookingIdFromTrip(trip)) {
    return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_BOOKING_ID };
  }
  if (!tripIsTerminal(trip)) {
    return { ok: false, reason: DIRECT_RECONCILE_REASON.NON_TERMINAL };
  }
  if (!tripHasAuthoritativeFare(trip)) {
    return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_FARE };
  }
  return { ok: true, reason: DIRECT_RECONCILE_REASON.REPAIRABLE };
}

/** True when the trip's booking is already durably finalized. */
export function bookingAlreadyFinalized(trip) {
  return (
    _str(trip?.booking_finalize_state).toLowerCase() ===
    DIRECT_BOOKING_FINALIZE_STATE.COMPLETED
  );
}

/**
 * Build the `/track/booking/finalize-direct` payload from the persisted trip.
 * Fare fields come from the trip only. Mirrors the existing STOP payload shape
 * so the booking worker's idempotent finalize path is reused unchanged.
 */
export function buildFinalizePayloadFromTrip(trip, scope) {
  return {
    tenant_id: _str(scope?.tenant_id, 80),
    company_id: _str(scope?.company_id, 80),
    booking_id: directBookingIdFromTrip(trip),
    trip_id: _str(trip?.trip_id, 160) || null,
    stopped_at: _str(trip?.stopped_at, 80) || null,
    total_eur: _numOrNull(trip?.price_incl_vat ?? trip?.total_eur),
    price_ex_vat: _numOrNull(trip?.price_ex_vat),
    price_vat: _numOrNull(trip?.price_vat),
    // Mirror existing STOP behaviour: the trip stores vat_rate as a fraction and
    // is forwarded to the booking worker under vat_rate_percent unchanged.
    vat_rate_percent: _numOrNull(trip?.vat_rate),
    currency:
      _str(trip?.currency ?? trip?.pricing_snapshot?.currency, 8) || "EUR",
    source: "street_ride_stop",
  };
}

/** Map a booking-worker finalize response to a finalize state. */
export function deriveFinalizeStateFromResult(res) {
  return res && res.ok === true
    ? DIRECT_BOOKING_FINALIZE_STATE.COMPLETED
    : DIRECT_BOOKING_FINALIZE_STATE.PENDING;
}

/** Coarse, PII-free error code from a finalize response (null on success). */
export function finalizeErrorCodeFromResult(res) {
  if (res && res.ok === true) return null;
  return _str(res?.error, 120) || "unknown";
}

/**
 * Apply a finalize attempt to the trip record IN PLACE (monotonic).
 *
 * Persists: booking_finalize_state, booking_finalize_attempted_at,
 * booking_finalize_attempt_count, booking_finalize_last_error_code.
 * Once the state is `completed` it never regresses to `pending`.
 */
export function applyBookingFinalizeAttempt(
  trip,
  { state, errorCode = null, nowIso, attemptDelta = 1 } = {},
) {
  if (!trip || typeof trip !== "object") return trip;
  const completed = DIRECT_BOOKING_FINALIZE_STATE.COMPLETED;
  const wasCompleted = bookingAlreadyFinalized(trip);
  const nextState = wasCompleted ? completed : state;
  trip.booking_finalize_state = nextState;
  trip.booking_finalize_attempted_at = _str(nowIso, 80) || trip.booking_finalize_attempted_at || null;
  const prevCount = Number(trip.booking_finalize_attempt_count);
  trip.booking_finalize_attempt_count =
    (Number.isFinite(prevCount) ? prevCount : 0) + (Number(attemptDelta) || 0);
  trip.booking_finalize_last_error_code =
    nextState === completed ? null : errorCode || null;
  return trip;
}

/**
 * Bounded, PII-free response fields returned by /trip/stop and
 * /trip/reconcile-direct-booking. Never leaks totals, coordinates or raw
 * downstream bodies.
 */
export function safeBookingFinalizeResponseFields(trip) {
  const completed = bookingAlreadyFinalized(trip);
  return {
    booking_id: directBookingIdFromTrip(trip) || null,
    booking_finalize_state: completed
      ? DIRECT_BOOKING_FINALIZE_STATE.COMPLETED
      : DIRECT_BOOKING_FINALIZE_STATE.PENDING,
    booking_finalized: completed,
  };
}
