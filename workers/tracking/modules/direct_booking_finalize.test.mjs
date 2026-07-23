// STREET-RIDE-DURABLE-COMPLETION-2 — deterministic tests for the pure
// street/direct booking finalization decision logic.
//
// Run: node --test workers/tracking/modules/direct_booking_finalize.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  DIRECT_BOOKING_FINALIZE_STATE,
  DIRECT_RECONCILE_REASON,
  isStreetDirectTrip,
  tripIsTerminal,
  directBookingIdFromTrip,
  authoritativeTripFareCents,
  tripHasAuthoritativeFare,
  tripReconcileEligibility,
  bookingAlreadyFinalized,
  buildFinalizePayloadFromTrip,
  deriveFinalizeStateFromResult,
  finalizeErrorCodeFromResult,
  applyBookingFinalizeAttempt,
  safeBookingFinalizeResponseFields,
} from "./direct_booking_finalize.mjs";

const scope = { tenant_id: "T1", company_id: "C1" };

const stoppedDirectTrip = (over = {}) => ({
  trip_id: "trip_abc",
  kind: "direct",
  source: "street_ride",
  status: "stopped",
  stopped_at: "2026-07-23T10:00:00.000Z",
  booking_id: "street_1752863820000_ab12cd34",
  total_eur: 3.2,
  price_incl_vat: 3.2,
  price_ex_vat: 2.64,
  price_vat: 0.56,
  vat_rate: 0.21,
  currency: "EUR",
  pricing_snapshot: { currency: "EUR" },
  ...over,
});

test("isStreetDirectTrip recognises direct kind and street_ride source", () => {
  assert.equal(isStreetDirectTrip({ kind: "direct" }), true);
  assert.equal(isStreetDirectTrip({ source: "street_ride" }), true);
  assert.equal(isStreetDirectTrip({ kind: "planned" }), false);
  assert.equal(isStreetDirectTrip(null), false);
});

test("tripIsTerminal is true for stopped/completed or a stopped_at stamp", () => {
  assert.equal(tripIsTerminal({ status: "stopped" }), true);
  assert.equal(tripIsTerminal({ status: "completed" }), true);
  assert.equal(tripIsTerminal({ status: "active", stopped_at: "x" }), true);
  assert.equal(tripIsTerminal({ status: "active" }), false);
});

test("authoritative fare reads trip totals only (cents)", () => {
  assert.equal(authoritativeTripFareCents(stoppedDirectTrip()), 320);
  assert.equal(
    authoritativeTripFareCents(stoppedDirectTrip({ price_incl_vat: null, total_eur: 3.3 })),
    330,
  );
  assert.equal(
    authoritativeTripFareCents(stoppedDirectTrip({ price_incl_vat: null, total_eur: null })),
    null,
  );
  assert.equal(tripHasAuthoritativeFare(stoppedDirectTrip()), true);
});

test("eligibility: repairable when terminal street/direct with booking + fare", () => {
  assert.deepEqual(tripReconcileEligibility(stoppedDirectTrip()), {
    ok: true,
    reason: DIRECT_RECONCILE_REASON.REPAIRABLE,
  });
});

test("eligibility: rejects non-terminal, missing booking, missing fare, non-street", () => {
  assert.equal(
    tripReconcileEligibility(stoppedDirectTrip({ status: "active", stopped_at: "" })).reason,
    DIRECT_RECONCILE_REASON.NON_TERMINAL,
  );
  assert.equal(
    tripReconcileEligibility(stoppedDirectTrip({ booking_id: "", bookingId: "" })).reason,
    DIRECT_RECONCILE_REASON.MISSING_BOOKING_ID,
  );
  assert.equal(
    tripReconcileEligibility(stoppedDirectTrip({ price_incl_vat: null, total_eur: null })).reason,
    DIRECT_RECONCILE_REASON.MISSING_FARE,
  );
  assert.equal(
    tripReconcileEligibility(stoppedDirectTrip({ kind: "planned", source: "planned" })).reason,
    DIRECT_RECONCILE_REASON.NOT_STREET_DIRECT,
  );
  assert.equal(
    tripReconcileEligibility(null).reason,
    DIRECT_RECONCILE_REASON.MISSING_TRIP,
  );
});

test("finalize payload derives fare exclusively from the trip", () => {
  const trip = stoppedDirectTrip();
  const payload = buildFinalizePayloadFromTrip(trip, scope);
  assert.equal(payload.booking_id, trip.booking_id);
  assert.equal(payload.trip_id, trip.trip_id);
  assert.equal(payload.total_eur, 3.2);
  assert.equal(payload.price_ex_vat, 2.64);
  assert.equal(payload.price_vat, 0.56);
  assert.equal(payload.vat_rate_percent, 0.21);
  assert.equal(payload.currency, "EUR");
  assert.equal(payload.source, "street_ride_stop");
  assert.equal(payload.tenant_id, "T1");
  assert.equal(payload.company_id, "C1");
});

test("finalize payload ignores any client-provided fare on the trip envelope", () => {
  const trip = stoppedDirectTrip();
  // A rogue client field must never influence the derived fare.
  trip.client_total_eur = 999.99;
  const payload = buildFinalizePayloadFromTrip(trip, scope);
  assert.equal(payload.total_eur, 3.2);
});

test("deriveFinalizeStateFromResult maps ok→completed else pending", () => {
  assert.equal(
    deriveFinalizeStateFromResult({ ok: true }),
    DIRECT_BOOKING_FINALIZE_STATE.COMPLETED,
  );
  assert.equal(
    deriveFinalizeStateFromResult({ ok: false, error: "http_500" }),
    DIRECT_BOOKING_FINALIZE_STATE.PENDING,
  );
  assert.equal(
    deriveFinalizeStateFromResult(null),
    DIRECT_BOOKING_FINALIZE_STATE.PENDING,
  );
});

test("finalizeErrorCodeFromResult is null on success, coarse code otherwise", () => {
  assert.equal(finalizeErrorCodeFromResult({ ok: true }), null);
  assert.equal(finalizeErrorCodeFromResult({ ok: false, error: "booking_not_found" }), "booking_not_found");
  assert.equal(finalizeErrorCodeFromResult(null), "unknown");
});

test("applyBookingFinalizeAttempt records pending on failure with attempt count", () => {
  const trip = stoppedDirectTrip();
  applyBookingFinalizeAttempt(trip, {
    state: DIRECT_BOOKING_FINALIZE_STATE.PENDING,
    errorCode: "http_500",
    nowIso: "2026-07-23T10:00:01.000Z",
  });
  assert.equal(trip.booking_finalize_state, "pending");
  assert.equal(trip.booking_finalize_attempt_count, 1);
  assert.equal(trip.booking_finalize_last_error_code, "http_500");
  assert.equal(trip.booking_finalize_attempted_at, "2026-07-23T10:00:01.000Z");
});

test("applyBookingFinalizeAttempt is monotonic: completed never regresses", () => {
  const trip = stoppedDirectTrip();
  applyBookingFinalizeAttempt(trip, {
    state: DIRECT_BOOKING_FINALIZE_STATE.COMPLETED,
    nowIso: "2026-07-23T10:00:01.000Z",
  });
  assert.equal(trip.booking_finalize_state, "completed");
  assert.equal(trip.booking_finalize_last_error_code, null);
  // A later failed attempt must NOT downgrade a completed booking.
  applyBookingFinalizeAttempt(trip, {
    state: DIRECT_BOOKING_FINALIZE_STATE.PENDING,
    errorCode: "http_500",
    nowIso: "2026-07-23T10:00:05.000Z",
  });
  assert.equal(trip.booking_finalize_state, "completed");
  assert.equal(trip.booking_finalize_last_error_code, null);
  assert.equal(trip.booking_finalize_attempt_count, 2);
});

test("bookingAlreadyFinalized reflects the completed state", () => {
  assert.equal(bookingAlreadyFinalized(stoppedDirectTrip()), false);
  assert.equal(
    bookingAlreadyFinalized(stoppedDirectTrip({ booking_finalize_state: "completed" })),
    true,
  );
});

test("safeBookingFinalizeResponseFields is bounded and PII-free", () => {
  const trip = stoppedDirectTrip({ booking_finalize_state: "completed" });
  const out = safeBookingFinalizeResponseFields(trip);
  assert.deepEqual(Object.keys(out).sort(), [
    "booking_finalize_state",
    "booking_finalized",
    "booking_id",
  ]);
  assert.equal(out.booking_finalized, true);
  assert.equal(out.booking_finalize_state, "completed");
  assert.equal(out.booking_id, trip.booking_id);
  // No fare / coordinates leak.
  assert.equal("total_eur" in out, false);
});
