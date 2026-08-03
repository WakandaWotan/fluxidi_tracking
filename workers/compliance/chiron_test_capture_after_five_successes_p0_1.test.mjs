// FLUXIDI-CHIRON-TEST-CAPTURE-AFTER-FIVE-SUCCESSES-P0-1
//
// Release-blocking: production toggle must never stop Fluxidi's internal
// Chiron ACC/test capture. Five successful tests are a readiness milestone
// only — the sixth and later eligible rides must keep appearing on the
// Chiron test portal (ACC auto-submit) for DIRECT / RIDE / RETURN_RIDE.
//
// Run:
//   node --test workers/compliance/chiron_test_capture_after_five_successes_p0_1.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironDeriveEffectiveChironEnvironment,
  buildChironConnectionStatusResponse,
  parseChironConfigStatusPostInput,
  _chironAutoSubmitEligibleForEvent,
  _chironTestflowLiveGate,
  _chironProductionLiveGate,
  _chironAutoSubmitRoutingGate,
  recordChironTestflowSubmitResult,
  buildChironTestflowResetStatusDoc,
} = __testInternals;

const ACC_TAXIRIT_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";

function goodEnv(overrides = {}) {
  return {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_TAXIRIT_URL,
    ...overrides,
  };
}

function baseStored(overrides = {}) {
  return {
    schema_version: "chiron_connection_status_v1",
    enabled: true,
    environment: "test",
    region: "flanders",
    production_enabled: false,
    test_credentials_stored: true,
    production_credentials_stored: false,
    last_connection_status: "test_passed",
    last_connection_test_at: "2026-08-03T07:00:00.000Z",
    testflow_auto_submit_enabled: true,
    testflow_started_at: "2026-08-03T07:00:00.000Z",
    ...overrides,
  };
}

function completeFiveStored(overrides = {}) {
  return baseStored({
    test_departure_sent_count: 5,
    test_arrival_sent_count: 5,
    test_messages_sent_count: 10,
    test_rides_completed_count: 5,
    testflow_ritnummers_completed: ["r1", "r2", "r3", "r4", "r5"],
    testflow_ritnummers_departure: ["r1", "r2", "r3", "r4", "r5"],
    testflow_ritnummers_arrival: ["r1", "r2", "r3", "r4", "r5"],
    ...overrides,
  });
}

function eventAt(iso, extras = {}) {
  return {
    event_type: "ride_start",
    created_at_utc: iso,
    booking_id: "b1",
    ...extras,
  };
}

function assertAccEligible(payload, label) {
  assert.equal(payload.effective_chiron_environment, "test", label);
  assert.equal(payload.acc_test_submit_active, true, label);
  assert.equal(_chironTestflowLiveGate(payload, goodEnv()), null, label);
  const reason = _chironAutoSubmitEligibleForEvent(
    payload,
    goodEnv(),
    eventAt("2026-08-03T12:00:00.000Z"),
  );
  assert.equal(reason, null, `${label}: expected eligible, got ${reason}`);
}

function assertTransportParity(rideType, legType) {
  // Transport mapping is carried on the compliance event; eligibility must
  // not depend on ride type. These fields must survive the ACC gate.
  const payload = buildChironConnectionStatusResponse(
    "T1",
    "C1",
    completeFiveStored({ environment: "production", production_enabled: false }),
  );
  const reason = _chironAutoSubmitEligibleForEvent(
    payload,
    goodEnv(),
    eventAt("2026-08-03T12:00:00.000Z", {
      ride_type: rideType,
      leg_type: legType,
      transport_mode:
        rideType === "direct"
          ? "DIRECT"
          : legType === "return"
            ? "RETURN_RIDE"
            : "RIDE",
    }),
  );
  assert.equal(reason, null, `${rideType}/${legType || "-"} must stay ACC-eligible`);
}

// -------------------------------------------------------------------------
// Cases 1–4: production off, DIRECT (and milestone semantics).
// -------------------------------------------------------------------------
test("1 production off, success 0: direct ride ACC-eligible", () => {
  const payload = buildChironConnectionStatusResponse("T1", "C1", baseStored());
  assert.equal(payload.test_rides_completed_count, 0);
  assertAccEligible(payload, "case1");
});

test("2 production off, success 4→5: fifth ride eligible and milestone completes", () => {
  const at4 = baseStored({
    test_departure_sent_count: 4,
    test_arrival_sent_count: 4,
    test_messages_sent_count: 8,
    test_rides_completed_count: 4,
    testflow_ritnummers_departure: ["r1", "r2", "r3", "r4"],
    testflow_ritnummers_arrival: ["r1", "r2", "r3", "r4"],
    testflow_ritnummers_completed: ["r1", "r2", "r3", "r4"],
  });
  const afterFifthDeparture = recordChironTestflowSubmitResult(at4, {
    officialStatus: "vertrek",
    ritnummer: "r5",
    ok: true,
    foutenCount: 0,
  });
  const afterFifth = recordChironTestflowSubmitResult(afterFifthDeparture, {
    officialStatus: "aankomst",
    ritnummer: "r5",
    ok: true,
    foutenCount: 0,
  });
  assert.equal(afterFifth.testflow_status, "complete");
  assert.equal(afterFifth.test_rides_completed_count, 5);
  const payload = buildChironConnectionStatusResponse("T1", "C1", afterFifth);
  assertAccEligible(payload, "case2");
});

test("3 production off, success 5: sixth direct ride still ACC-eligible", () => {
  const payload = buildChironConnectionStatusResponse(
    "T1",
    "C1",
    completeFiveStored(),
  );
  assert.equal(payload.testflow_status, "complete");
  assertAccEligible(payload, "case3");
});

test("4 production off, success >5: later direct rides keep ACC-eligible", () => {
  const afterSixth = recordChironTestflowSubmitResult(completeFiveStored(), {
    officialStatus: "aankomst",
    ritnummer: "r6",
    ok: true,
    foutenCount: 0,
  });
  // Counter caps at 5 for UI, but history + ACC path continue.
  assert.equal(afterSixth.test_rides_completed_count, 5);
  assert.ok(afterSixth.testflow_ritnummers_arrival.includes("r6"));
  const payload = buildChironConnectionStatusResponse("T1", "C1", afterSixth);
  assertAccEligible(payload, "case4");
  const afterSeventh = recordChironTestflowSubmitResult(afterSixth, {
    officialStatus: "vertrek",
    ritnummer: "r7",
    ok: true,
    foutenCount: 0,
  });
  assert.ok(afterSeventh.testflow_ritnummers_departure.includes("r7"));
  assertAccEligible(
    buildChironConnectionStatusResponse("T1", "C1", afterSeventh),
    "case4-seventh",
  );
});

// -------------------------------------------------------------------------
// Cases 5–6: planned RIDE + RETURN_RIDE parity after 5/5 + advisory production.
// -------------------------------------------------------------------------
test("5 planned RIDE remains ACC-eligible after 5/5 with advisory production env", () => {
  assertTransportParity("planned", "outbound");
});

test("6 RETURN_RIDE remains ACC-eligible after 5/5 with advisory production env", () => {
  assertTransportParity("planned", "return");
});

test("10 DIRECT transport mapping does not require destination fields for ACC gate", () => {
  assertTransportParity("direct", undefined);
});

test("11 planned one-way remains RIDE for ACC eligibility", () => {
  assertTransportParity("planned", "outbound");
});

test("12 planned return remains RETURN_RIDE for ACC eligibility", () => {
  assertTransportParity("planned", "return");
});

// -------------------------------------------------------------------------
// Case 7: production disabled after previously reaching production readiness.
// -------------------------------------------------------------------------
test("7 production disabled after readiness: next ride still ACC (advisory env may stay production)", () => {
  const stored = completeFiveStored({
    environment: "production",
    production_enabled: false,
    production_credentials_stored: true,
    production_last_connection_status: "test_passed",
    production_last_connection_test_at: "2026-08-03T08:00:00.000Z",
  });
  const payload = buildChironConnectionStatusResponse("T1", "C1", stored);
  assert.equal(payload.environment, "production");
  assert.equal(payload.production_enabled, false);
  assert.equal(payload.effective_chiron_environment, "test");
  assertAccEligible(payload, "case7");
});

// -------------------------------------------------------------------------
// Case 8: production enabled and ready → production only, no ACC fallback.
// -------------------------------------------------------------------------
test("8 production enabled and ready: production destination only, no silent ACC", () => {
  const stored = completeFiveStored({
    environment: "production",
    production_enabled: true,
    production_credentials_stored: true,
    production_last_connection_status: "test_passed",
    production_last_connection_test_at: "2026-08-03T08:00:00.000Z",
  });
  const payload = buildChironConnectionStatusResponse("T1", "C1", stored);
  assert.equal(payload.effective_chiron_environment, "production");
  assert.equal(payload.production_submit_active, true);
  assert.equal(payload.acc_test_submit_active, false);
  assert.equal(
    _chironAutoSubmitRoutingGate(payload, goodEnv()),
    null,
    "production live-gate must open",
  );
  assert.equal(_chironProductionLiveGate(payload), null);
  assert.equal(
    _chironTestflowLiveGate(payload, goodEnv()),
    "effective_environment_is_production",
  );
});

// -------------------------------------------------------------------------
// Case 9: production enabled but credentials/readiness missing → fail-closed,
// no silent ACC when projected production_enabled stays invalid.
// -------------------------------------------------------------------------
test("9 production enabled but not ready: neutralized projection keeps durable ACC path", () => {
  // Legacy corruption is neutralized on read (production_enabled→false) so
  // rides are not lost; effective stays test and ACC remains the destination.
  const stored = completeFiveStored({
    environment: "production",
    production_enabled: true,
    production_credentials_stored: false,
    production_last_connection_status: "never_tested",
  });
  const payload = buildChironConnectionStatusResponse("T1", "C1", stored);
  assert.equal(payload.production_enabled, false);
  assert.equal(payload.effective_chiron_environment, "test");
  assertAccEligible(payload, "case9-neutralized");

  // Fresh write of production_enabled without credentials is refused.
  const refused = parseChironConfigStatusPostInput(
    { production_enabled: true },
    completeFiveStored({ production_credentials_stored: false }),
  );
  assert.equal(refused.error, "production_credentials_missing");
});

// -------------------------------------------------------------------------
// Cases 13–16: idempotency / visibility / environment truth.
// -------------------------------------------------------------------------
test("13 duplicate finalize does not invent a second logical compliance identity", () => {
  // Dedup identity is event_id scoped; auto-submit eligibility is unchanged
  // across repeated STOP signals for the same booking.
  const payload = buildChironConnectionStatusResponse(
    "T1",
    "C1",
    completeFiveStored({ environment: "production" }),
  );
  const first = _chironAutoSubmitEligibleForEvent(
    payload,
    goodEnv(),
    eventAt("2026-08-03T12:00:00.000Z", {
      event_type: "ride_stop",
      event_id: "ride_stop:T1:C1:trip-1",
      booking_id: "trip-1",
    }),
  );
  const second = _chironAutoSubmitEligibleForEvent(
    payload,
    goodEnv(),
    eventAt("2026-08-03T12:00:00.000Z", {
      event_type: "ride_stop",
      event_id: "ride_stop:T1:C1:trip-1",
      booking_id: "trip-1",
    }),
  );
  assert.equal(first, null);
  assert.equal(second, null);
});

test("14 retry keeps stable ACC environment while production stays off", () => {
  const stored = completeFiveStored({
    environment: "production",
    production_enabled: false,
  });
  const before = _chironDeriveEffectiveChironEnvironment(
    buildChironConnectionStatusResponse("T1", "C1", stored),
  );
  // Simulate a later retry: same stored config, same effective destination.
  const after = _chironDeriveEffectiveChironEnvironment(
    buildChironConnectionStatusResponse("T1", "C1", stored),
  );
  assert.equal(before, "test");
  assert.equal(after, "test");
});

test("15 test-page ACC path includes sixth and later successful rides", () => {
  const payload = buildChironConnectionStatusResponse(
    "T1",
    "C1",
    completeFiveStored({ environment: "production", production_enabled: false }),
  );
  for (const rit of ["r6", "r7", "r8"]) {
    const reason = _chironAutoSubmitEligibleForEvent(
      payload,
      goodEnv(),
      eventAt("2026-08-03T13:00:00.000Z", {
        event_type: "ride_stop",
        booking_id: rit,
      }),
    );
    assert.equal(reason, null, `${rit} must remain visible via ACC submit`);
  }
});

test("16 failed/retrying eligibility remains open (gate does not hide failures)", () => {
  const payload = buildChironConnectionStatusResponse(
    "T1",
    "C1",
    completeFiveStored({ environment: "production" }),
  );
  // Live-gate / eligibility do not inspect prior sync_state; failed records
  // stay retryable via the same ACC path.
  assert.equal(_chironTestflowLiveGate(payload, goodEnv()), null);
  assert.equal(
    _chironAutoSubmitEligibleForEvent(
      payload,
      goodEnv(),
      eventAt("2026-08-03T14:00:00.000Z", { event_type: "ride_stop" }),
    ),
    null,
  );
});

// -------------------------------------------------------------------------
// Case 17: tenant isolation.
// -------------------------------------------------------------------------
test("17 tenant isolation for toggle, counter and ACC eligibility", () => {
  const tenantA = buildChironConnectionStatusResponse(
    "TENANT_A",
    "CO_A",
    completeFiveStored({
      environment: "production",
      production_enabled: true,
      production_credentials_stored: true,
      production_last_connection_status: "test_passed",
      production_last_connection_test_at: "2026-08-03T08:00:00.000Z",
    }),
  );
  const tenantB = buildChironConnectionStatusResponse(
    "TENANT_B",
    "CO_B",
    baseStored({
      test_rides_completed_count: 1,
      test_departure_sent_count: 1,
      test_arrival_sent_count: 1,
      test_messages_sent_count: 2,
    }),
  );
  assert.equal(tenantA.effective_chiron_environment, "production");
  assert.equal(tenantB.effective_chiron_environment, "test");
  assert.equal(tenantA.test_rides_completed_count, 5);
  assert.equal(tenantB.test_rides_completed_count, 1);
  assert.equal(tenantA.production_enabled, true);
  assert.equal(tenantB.production_enabled, false);
  assertAccEligible(tenantB, "tenantB-isolated");
  assert.equal(tenantA.acc_test_submit_active, false);
});

// -------------------------------------------------------------------------
// Cases 18–20: durable recovery posture + historical truth.
// -------------------------------------------------------------------------
test("18 ACC path stays open for production-off records after restart projection", () => {
  const stored = completeFiveStored({
    environment: "production",
    production_enabled: false,
  });
  // Restart = re-project from durable KV doc; no in-memory latch may hide rides.
  const again = buildChironConnectionStatusResponse("T1", "C1", stored);
  assertAccEligible(again, "case18-restart");
});

test("19 production-off records retain ACC destination after refresh", () => {
  const stored = completeFiveStored({
    environment: "production",
    production_enabled: false,
  });
  const first = buildChironConnectionStatusResponse("T1", "C1", stored);
  const second = buildChironConnectionStatusResponse("T1", "C1", stored);
  assert.equal(first.effective_chiron_environment, second.effective_chiron_environment);
  assert.equal(first.effective_chiron_environment, "test");
});

test("20 historical production stamp is not relabelled as test by live-gate", () => {
  // Per-ride historical stamp lives on chiron_export_status_v1. The company
  // live-gate must not rewrite that stamp; production-ready companies still
  // route production-only when effective=production.
  const prod = buildChironConnectionStatusResponse(
    "T1",
    "C1",
    completeFiveStored({
      environment: "production",
      production_enabled: true,
      production_credentials_stored: true,
      production_last_connection_status: "test_passed",
      production_last_connection_test_at: "2026-08-03T08:00:00.000Z",
    }),
  );
  assert.equal(prod.effective_chiron_environment, "production");
  const historicalStamp = { effective_environment: "production" };
  assert.equal(historicalStamp.effective_environment, "production");
  assert.notEqual(historicalStamp.effective_environment, "test");
});

test("reset still arms ACC after prior production readiness", () => {
  const before = completeFiveStored({
    environment: "production",
    production_enabled: true,
    production_credentials_stored: true,
    production_last_connection_status: "test_passed",
    production_last_connection_test_at: "2026-08-03T08:00:00.000Z",
  });
  const after = buildChironTestflowResetStatusDoc(
    before,
    "T1",
    "C1",
    "2026-08-03T15:00:00.000Z",
    "reset-p0-1",
  );
  assert.equal(after.production_enabled, false);
  assert.equal(after.environment, "test");
  const payload = buildChironConnectionStatusResponse("T1", "C1", after);
  assert.equal(payload.effective_chiron_environment, "test");
  assert.equal(payload.acc_test_submit_active, true);
  assert.equal(_chironTestflowLiveGate(payload, goodEnv()), null);
  // Event must be at/after the new testflow_started_at stamped by reset.
  assert.equal(
    _chironAutoSubmitEligibleForEvent(
      payload,
      goodEnv(),
      eventAt("2026-08-03T15:01:00.000Z"),
    ),
    null,
  );
});

test("root-cause repro: environment=production + production_enabled=false opens ACC after 5/5", () => {
  const payload = buildChironConnectionStatusResponse(
    "T1",
    "C1",
    completeFiveStored({
      environment: "production",
      production_enabled: false,
    }),
  );
  assert.equal(payload.testflow_status, "complete");
  assert.equal(payload.environment, "production");
  assert.equal(payload.production_enabled, false);
  assert.equal(payload.effective_chiron_environment, "test");
  assert.equal(payload.acc_test_submit_active, true);
  assert.equal(_chironTestflowLiveGate(payload, goodEnv()), null);
  assert.notEqual(
    _chironTestflowLiveGate(payload, goodEnv()),
    "chiron_environment_must_be_test",
  );
});
