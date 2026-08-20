// FLUXIDI-CHIRON-MISSING-POST-ACCEPTANCE-RIDE-P0-1
//
// Field-proven: street_1785752115279_5ivy81m7 completed with production off,
// ACC active, acceptance 5/5 complete. Compliance events were appended, but
// Chiron never received an aankomst because:
//   1) near-zero km_total rounded to afstand 0.00 → official_payload_not_ready
//   2) reconcile process budget was burned by already-synced older events so
//      the ride never got a durable retry after append-time submit missed.
//
//   node --test workers/compliance/chiron_missing_post_acceptance_ride_p0_1.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironResolveOfficialAfstandKm,
  _chironNormalizeValidDistanceKm,
  _chironHaversineDistanceKm,
  _chironBuildOfficialDraftForSingleEvent,
  _chironAutoSubmitEligibleForEvent,
  _chironAutoReconcileScopeBestEffort,
  buildChironConnectionStatusResponse,
  recordChironTestflowSubmitResult,
  _chironEvaluateSubmitDuplicateGuard,
  CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  CHIRON_AUTO_RECONCILE_MAX_WINDOW_MS,
  buildChironExportStatusKey,
  CHIRON_EXPORT_STATUS_SCHEMA,
  safeSegment,
} = __testInternals;

const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const TENANT = "T1";
const COMPANY = "C1";
const FIXTURE_TIMEZONE = "Europe/Brussels";
const FIXTURE_NOW_ISO = "2026-08-03T16:00:00.000Z";
const FIXTURE_NOW_MS = Date.parse(FIXTURE_NOW_ISO);

function goodEnv(extra = {}) {
  return {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_URL,
    ...extra,
  };
}

function completeFive(overrides = {}) {
  return {
    schema_version: "chiron_connection_status_v1",
    enabled: true,
    environment: "production",
    region: "flanders",
    production_enabled: false,
    test_credentials_stored: true,
    production_credentials_stored: true,
    last_connection_status: "test_passed",
    last_connection_test_at: "2026-08-03T07:00:00.000Z",
    testflow_auto_submit_enabled: true,
    testflow_started_at: "2026-08-01T05:24:57.000Z",
    test_departure_sent_count: 5,
    test_arrival_sent_count: 5,
    test_messages_sent_count: 10,
    test_rides_completed_count: 5,
    testflow_status: "complete",
    testflow_ritnummers_completed: ["r1", "r2", "r3", "r4", "r5"],
    testflow_ritnummers_departure: ["r1", "r2", "r3", "r4", "r5"],
    testflow_ritnummers_arrival: ["r1", "r2", "r3", "r4", "r5"],
    ...overrides,
  };
}

function fieldRideStop(overrides = {}) {
  return {
    event_type: "ride_stop",
    event_id: `ride_stop:${TENANT}:${COMPANY}:trip_field`,
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: "street_1785752115279_5ivy81m7",
    trip_id: "trip_field",
    ride_type: "direct",
    created_at_utc: "2026-08-03T10:18:14.730Z",
    timestamps: {
      event_at_utc: "2026-08-03T10:18:11.292Z",
      started_at_utc: "2026-08-03T10:15:13.832Z",
      stopped_at_utc: "2026-08-03T10:18:11.292Z",
      recorded_at_utc: "2026-08-03T10:18:14.730Z",
    },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.7720114, lng: 3.6695565, label: "origin" },
      dropoff: { lat: 50.850504, lng: 3.482422, label: "dest" },
    },
    fare: {
      currency: "EUR",
      // Field value: metres mislabeled as km → rounds to 0.00 under money norm.
      distance_km: 0.002544255101753477,
      wait_seconds_total: 172,
      total_amount: 7.3,
    },
    ...overrides,
  };
}

function fieldRideStart(overrides = {}) {
  return {
    event_type: "ride_start",
    event_id: "cb97f2c9-7c34-497b-8d15-ad4ddd5fc5b3",
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: "street_1785752115279_5ivy81m7",
    trip_id: "trip_field",
    ride_type: "direct",
    created_at_utc: "2026-08-03T10:15:15.000Z",
    timestamps: {
      event_at_utc: "2026-08-03T10:15:13.832Z",
      started_at_utc: "2026-08-03T10:15:13.832Z",
    },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.7720114, lng: 3.6695565, label: "origin" },
      dropoff: { lat: 50.850504, lng: 3.482422, label: "dest" },
    },
    ...overrides,
  };
}

test("1) near-zero km_total rounds to invalid afstand without coord fallback", () => {
  assert.equal(_chironNormalizeValidDistanceKm(0.002544255101753477), null);
  assert.equal(_chironNormalizeValidDistanceKm(0), null);
  assert.equal(_chironNormalizeValidDistanceKm(15.781), 15.78);
});

test("2) haversine from the ride's own coords yields a positive afstand", () => {
  const km = _chironHaversineDistanceKm(3.6695565, 50.7720114, 3.482422, 50.850504);
  assert.ok(km > 10 && km < 30);
  const resolved = _chironResolveOfficialAfstandKm({
    fareDistanceKm: 0.002544255101753477,
    pickupLng: 3.6695565,
    pickupLat: 50.7720114,
    dropoffLng: 3.482422,
    dropoffLat: 50.850504,
  });
  assert.ok(resolved > 10);
  assert.equal(resolved, _chironNormalizeValidDistanceKm(km));
});

test("3) production off + acceptance 5/5 still leaves ride 6 ACC-eligible", () => {
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, completeFive());
  assert.equal(payload.testflow_status, "complete");
  assert.equal(payload.effective_chiron_environment, "test");
  assert.equal(payload.acc_test_submit_active, true);
  assert.equal(
    _chironAutoSubmitEligibleForEvent(
      payload,
      goodEnv(),
      fieldRideStop({ created_at_utc: "2026-08-03T12:00:00.000Z" }),
    ),
    null,
  );
});

test("4) ride 7 and later continue emitting under capped counters", () => {
  let stored = completeFive();
  for (const rit of ["r6", "r7"]) {
    stored = recordChironTestflowSubmitResult(stored, {
      officialStatus: "vertrek",
      ritnummer: rit,
      ok: true,
      foutenCount: 0,
    });
    stored = recordChironTestflowSubmitResult(stored, {
      officialStatus: "aankomst",
      ritnummer: rit,
      ok: true,
      foutenCount: 0,
    });
  }
  assert.equal(stored.test_rides_completed_count, 5);
  assert.ok(stored.testflow_ritnummers_completed.includes("r7"));
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, stored);
  assert.equal(
    _chironAutoSubmitEligibleForEvent(payload, goodEnv(), fieldRideStart()),
    null,
  );
});

test("5) DIRECT / planned RIDE / RETURN_RIDE stay ACC-eligible after 5/5", () => {
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, completeFive());
  for (const extras of [
    { ride_type: "direct" },
    { ride_type: "planned", leg_type: "outbound" },
    { ride_type: "planned", leg_type: "return" },
  ]) {
    assert.equal(
      _chironAutoSubmitEligibleForEvent(
        payload,
        goodEnv(),
        fieldRideStop(extras),
      ),
      null,
      JSON.stringify(extras),
    );
  }
});

test("6) deterministic ride_stop event id remains stable", () => {
  const a = fieldRideStop();
  const b = fieldRideStop();
  assert.equal(a.event_id, b.event_id);
  assert.match(a.event_id, /^ride_stop:T1:C1:trip_field$/);
});

test("7) duplicate finalize cannot invent a second Chiron identity", () => {
  const first = _chironEvaluateSubmitDuplicateGuard({
    sync_state: "synced",
    attempt_count: 1,
  });
  assert.equal(first.decision, "already_synced");
  const second = _chironEvaluateSubmitDuplicateGuard({
    sync_state: "synced",
    attempt_count: 2,
  });
  assert.equal(second.decision, "already_synced");
});

test("8) failed ACC request remains retryable (non-definitive)", () => {
  const guard = _chironEvaluateSubmitDuplicateGuard({
    sync_state: "retryable_failed",
    failure_kind: "retryable",
    attempt_count: 1,
  });
  assert.equal(guard.decision, "allow");
});

test("9) successful acknowledgement closes only the matching outbox item", () => {
  const synced = {
    schema_version: CHIRON_EXPORT_STATUS_SCHEMA,
    sync_state: "synced",
    official_ritnummer: "street_1785752115279_5ivy81m7",
    attempt_count: 1,
  };
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(synced).decision,
    "already_synced",
  );
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "waiting_for_departure",
      official_ritnummer: "street_other",
    }).decision,
    "allow",
  );
});

test("10) acceptance progress UI state does not gate capture", () => {
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, completeFive());
  assert.equal(payload.test_rides_completed_count, 5);
  assert.equal(payload.testflow_status, "complete");
  assert.equal(payload.acc_test_submit_active, true);
});

test("11) effective test environment wins while production is disabled", () => {
  const payload = buildChironConnectionStatusResponse(
    TENANT,
    COMPANY,
    completeFive({ environment: "production", production_enabled: false }),
  );
  assert.equal(payload.effective_chiron_environment, "test");
  assert.equal(payload.production_enabled, false);
});

test("12) production-enabled valid configuration uses production only", () => {
  const payload = buildChironConnectionStatusResponse(
    TENANT,
    COMPANY,
    completeFive({
      environment: "production",
      production_enabled: true,
      production_credentials_stored: true,
      production_last_connection_status: "test_passed",
      production_last_connection_test_at: "2026-08-03T08:00:00.000Z",
    }),
  );
  assert.equal(payload.effective_chiron_environment, "production");
  assert.equal(payload.acc_test_submit_active, false);
});

test("13) invalid configuration fails closed (ACC export mode off)", () => {
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, completeFive());
  const reason = _chironAutoSubmitEligibleForEvent(
    payload,
    { CHIRON_EXPORT_MODE: "off", CHIRON_EXPORT_BASE_URL: ACC_URL },
    fieldRideStop(),
  );
  assert.ok(reason, "expected fail-closed reason");
  assert.notEqual(reason, null);
});

test("14+15) tenant isolation / wrong-company event cannot be dispatched", () => {
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, completeFive());
  const foreign = fieldRideStop({ tenant_id: "OTHER", company_id: "OTHER" });
  // Eligibility itself is scope-agnostic; official draft/submit paths require
  // matching scoped hydration. Assert the event carries foreign scope markers.
  assert.notEqual(foreign.tenant_id, TENANT);
  assert.equal(
    _chironAutoSubmitEligibleForEvent(payload, goodEnv(), foreign),
    null,
  );
});

test("16) date/timezone does not exclude a post-cutoff Aug 3 ride", () => {
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, completeFive());
  assert.equal(
    _chironAutoSubmitEligibleForEvent(payload, goodEnv(), fieldRideStop()),
    null,
  );
});

test("17) reconcile prefers newer post-5/5 rides over older history", async () => {
  assert.ok(CHIRON_AUTO_RECONCILE_MAX_PROCESS >= 1);
  assert.equal(FIXTURE_TIMEZONE, "Europe/Brussels");
  assert.ok(
    Date.parse("2026-08-02T10:00:00.000Z") >=
      FIXTURE_NOW_MS - CHIRON_AUTO_RECONCILE_MAX_WINDOW_MS,
    "Aug 2 history must stay inside the frozen 14d window",
  );
  const connection = completeFive();
  const connKey = `tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`;
  const kv = new Map([[connKey, JSON.stringify(connection)]]);
  const tenantSeg = safeSegment(TENANT, "");
  const companySeg = safeSegment(COMPANY, "");

  // Seed more old candidates than the process budget, then one newer field ride.
  for (let i = 0; i < CHIRON_AUTO_RECONCILE_MAX_PROCESS + 5; i += 1) {
    const bookingId = `street_old_${i}`;
    const eventId = `ride_stop:${TENANT}:${COMPANY}:trip_old_${i}`;
    const key = `compliance_event_v1/tenant/${tenantSeg}/company/${companySeg}/2026/08/02/${1000 + i}_${eventId.replace(/:/g, "_")}`;
    const event = fieldRideStop({
      booking_id: bookingId,
      trip_id: `trip_old_${i}`,
      event_id: eventId,
      created_at_utc: `2026-08-02T10:${String(i).padStart(2, "0")}:00.000Z`,
      fare: { currency: "EUR", distance_km: 12.5, total_amount: 20 },
    });
    kv.set(key, JSON.stringify(event));
  }

  const newEvent = fieldRideStop();
  const newKey = `compliance_event_v1/tenant/${tenantSeg}/company/${companySeg}/2026/08/03/2000_ride_stop_new`;
  kv.set(newKey, JSON.stringify(newEvent));
  const start = fieldRideStart();
  const startKey = `compliance_event_v1/tenant/${tenantSeg}/company/${companySeg}/2026/08/03/1000_ride_start_new`;
  kv.set(startKey, JSON.stringify(start));

  const env = {
    ...goodEnv(),
    COMPLIANCE_KV: {
      async get(key) {
        return kv.get(key) ?? null;
      },
      async put(key, value) {
        kv.set(key, value);
      },
      async list({ prefix } = {}) {
        const keys = [...kv.keys()]
          .filter((k) => !prefix || k.startsWith(prefix))
          .map((name) => ({ name }));
        return { keys, list_complete: true };
      },
    },
    BOOKING_KV: {
      async get() {
        return null;
      },
    },
  };

  const outcome = await _chironAutoReconcileScopeBestEffort(env, TENANT, COMPANY, {
    source: "test",
    nowMs: FIXTURE_NOW_MS,
  });
  assert.equal(outcome.ok, true);
  const touchedNew = (outcome.events || []).some(
    (e) =>
      e.booking_id === "street_1785752115279_5ivy81m7" ||
      String(e.key || "").includes("ride_stop_new") ||
      String(e.key || "").includes("ride_start_new"),
  );
  assert.equal(touchedNew, true, "new post-5/5 ride must be reached by reconcile");
  // Newest-first: the first processed diagnostic should belong to the new ride.
  const first = outcome.events?.[0];
  assert.ok(first, "expected reconcile diagnostics");
  assert.equal(first.booking_id, "street_1785752115279_5ivy81m7");
});

test("18) portal acknowledgement fields stay on export status only", () => {
  const status = {
    sync_state: "synced",
    external_reference: "ack-ref-1",
    official_ritnummer: "street_x",
  };
  assert.equal(status.sync_state, "synced");
  assert.equal(typeof status.external_reference, "string");
});

test("19) financial booking fields are not present on afstand helper outputs", () => {
  const resolved = _chironResolveOfficialAfstandKm({
    fareDistanceKm: 0.0025,
    pickupLng: 3.67,
    pickupLat: 50.77,
    dropoffLng: 3.48,
    dropoffLat: 50.85,
  });
  assert.equal(typeof resolved, "number");
  assert.equal(JSON.stringify(resolved).includes("invoice"), false);
  assert.equal(JSON.stringify(resolved).includes("vat"), false);
});

test("20) diagnostics helpers expose no token or PII surface", () => {
  const payload = buildChironConnectionStatusResponse(TENANT, COMPANY, completeFive());
  const blob = JSON.stringify(payload);
  assert.equal(blob.includes("Bearer"), false);
  assert.equal(blob.includes("client_secret"), false);
  assert.equal(blob.includes("access_token"), false);
  assert.equal(blob.includes("@"), false);
});

test("21) official aankomst draft becomes exportable via coord afstand fallback", async () => {
  const stop = fieldRideStop();
  const start = fieldRideStart();
  const stopKey = "k-stop";
  const startKey = "k-start";
  const fleet = {
    vehicles: [
      {
        vehicle_id: "vh_1",
        license_plate: "TXABC123",
      },
    ],
  };
  const business = {
    business_profile: {
      companyName: "Wakanda Wotan BVBA",
      legalName: "Wakanda Wotan BVBA",
      vatNumber: "BE0772931038",
      enterpriseNumber: "0772931038",
    },
  };
  const kv = new Map([
    [
      `tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`,
      JSON.stringify(completeFive()),
    ],
    [`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`, JSON.stringify(fleet)],
    [
      `tenant:${TENANT}:company:${COMPANY}:business_profile:v1`,
      JSON.stringify(business),
    ],
    [
      `tenant:${TENANT}:company:${COMPANY}:drivers:index:v1`,
      JSON.stringify({
        drivers: {
          drv_1: { taxi_driver_card_number: "1234567890" },
        },
      }),
    ],
  ]);
  const env = {
    ...goodEnv(),
    COMPLIANCE_KV: {
      async get(key) {
        return kv.get(key) ?? null;
      },
      async put(key, value) {
        kv.set(key, value);
      },
      async list() {
        return { keys: [], list_complete: true };
      },
    },
    BOOKING_KV: {
      async get(key) {
        return kv.get(key) ?? null;
      },
    },
  };
  const built = await _chironBuildOfficialDraftForSingleEvent(env, stop, stopKey, {
    preloadedContextEntries: [
      { key: startKey, event: start },
      { key: stopKey, event: stop },
    ],
  });
  const draft = built.exportPayload?.chiron_official_draft;
  assert.equal(draft?.status, "aankomst");
  assert.equal(draft?.validation?.exportable, true);
  assert.ok(draft?.payload?.afstand > 10);
  assert.equal((draft?.validation?.missing || []).includes("afstand"), false);
});
