// Street-ride pairing + persistent export status so candidates never vanish.
//
// Run: node --test workers/compliance/chiron_street_pair_persist_status_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  _chironCanonicalTripIdFromEntries,
  _chironDepartureCanonicalDecision,
  _chironOfficialDraftReadyForSubmit,
  _chironPersistCandidateExportStatus,
  _chironAutoSubmitOneEvent,
  _chironAutoReconcileScopeBestEffort,
  _chironEvaluateSubmitDuplicateGuard,
  buildChironExportStatusKey,
  safeSegment,
} = __testInternals;

const TENANT = "T1";
const COMPANY = "C1";
const BOOKING = "street_shared_ritnummer";
const CANONICAL_TRIP = "trip_canonical";
const EXTRA_TRIP = "trip_extra";

function makeKV({ seed = {} } = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return JSON.parse(raw);
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, typeof val === "string" ? val : JSON.stringify(val));
    },
    async list({ prefix = "" } = {}) {
      const names = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
      return { keys: names.map((name) => ({ name })), list_complete: true };
    },
  };
}

function startEvent(tripId, eventId) {
  return {
    event_id: eventId,
    event_type: "ride_start",
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: BOOKING,
    trip_id: tripId,
    created_at_utc: "2026-08-15T10:42:59.000Z",
    timestamps: { event_at_utc: "2026-08-15T10:42:57.000Z" },
  };
}

function stopEvent() {
  return {
    event_id: `ride_stop:${TENANT}:${COMPANY}:${CANONICAL_TRIP}`,
    event_type: "ride_stop",
    tenant_id: TENANT,
    company_id: COMPANY,
    booking_id: BOOKING,
    trip_id: CANONICAL_TRIP,
    created_at_utc: "2026-08-15T11:04:40.000Z",
    timestamps: { event_at_utc: "2026-08-15T11:04:37.000Z" },
  };
}

test("canonical trip is the ride_stop trip_id for a shared street booking", () => {
  const entries = [
    { event: startEvent(EXTRA_TRIP, "extra") },
    { event: startEvent(CANONICAL_TRIP, "canon") },
    { event: stopEvent() },
  ];
  assert.equal(_chironCanonicalTripIdFromEntries(entries, BOOKING), CANONICAL_TRIP);
  assert.equal(
    _chironDepartureCanonicalDecision(startEvent(CANONICAL_TRIP, "canon"), entries).allow,
    true,
  );
  const extra = _chironDepartureCanonicalDecision(startEvent(EXTRA_TRIP, "extra"), entries);
  assert.equal(extra.allow, false);
  assert.equal(extra.reason, "extra_start_not_canonical_trip");
});

test("ACC placeholder_driver_pass is a soft warning, production stays blocked", () => {
  const draft = {
    category: "ride_payload",
    status: "vertrek",
    idempotency_key: "k",
    payload: { ritnummer: BOOKING },
    validation: {
      status: "blocker",
      exportable: false,
      missing: [],
      errors: ["placeholder_driver_pass"],
      blockers: [],
      sequence_safe: true,
    },
  };
  const acc = _chironOfficialDraftReadyForSubmit({
    officialDraft: draft,
    expectedOfficialStatus: "vertrek",
    effectiveEnvironment: "test",
  });
  assert.equal(acc.acceptable, true);
  const prod = _chironOfficialDraftReadyForSubmit({
    officialDraft: draft,
    expectedOfficialStatus: "vertrek",
    effectiveEnvironment: "production",
  });
  assert.equal(prod.acceptable, false);
  assert.equal(prod.reason, "placeholder_driver_pass");
});

test("payload-build skip persists a blocked reason and never uses the official vertrek key for an extra start", async () => {
  const kv = makeKV();
  const env = { COMPLIANCE_KV: kv };
  const extra = startEvent(EXTRA_TRIP, "0c319dcc-extra");
  const entries = [
    { event: extra },
    { event: startEvent(CANONICAL_TRIP, "f0f7ef47-canon") },
    { event: stopEvent() },
  ];
  const outcome = await _chironAutoSubmitOneEvent(env, extra, "extra-key", {
    source: "test",
    preloadedContextEntries: entries,
  });
  assert.equal(outcome.reason, "extra_start_not_canonical_trip");
  assert.equal(outcome.sync_state, "blocked");
  const officialKey = buildChironExportStatusKey(
    safeSegment(TENANT, ""),
    safeSegment(COMPANY, ""),
    `chiron_official_v1:${TENANT}:${COMPANY}:0772.931.038:${BOOKING}:vertrek`,
  );
  assert.equal(await kv.get(officialKey), null);
  const candidateKey = buildChironExportStatusKey(
    safeSegment(TENANT, ""),
    safeSegment(COMPANY, ""),
    "candidate_v1:0c319dcc-extra",
  );
  const stored = JSON.parse(await kv.get(candidateKey));
  assert.equal(stored.sync_state, "blocked");
  assert.equal(stored.reason_code, "extra_start_not_canonical_trip");
  assert.equal(stored.trip_id, EXTRA_TRIP);
});

test("blocked persist writes a safe reason without official vertrek collision", async () => {
  const kv = makeKV();
  const extra = startEvent(EXTRA_TRIP, "boom-extra");
  const persisted = await _chironPersistCandidateExportStatus(
    { COMPLIANCE_KV: kv },
    {
      tenantId: TENANT,
      companyId: COMPANY,
      event: extra,
      messageType: "departure",
      syncState: "blocked",
      reasonCode: "internal_exception",
      source: "test",
    },
  );
  assert.equal(persisted.ok, true);
  const stored = JSON.parse(await kv.get(persisted.status_key));
  assert.equal(stored.sync_state, "blocked");
  assert.equal(stored.reason_code, "internal_exception");
  assert.equal(stored.official_idempotency_key, null);
});

test("duplicate guard still blocks a second official submit", () => {
  const guard = _chironEvaluateSubmitDuplicateGuard({
    sync_state: "synced",
    attempt_count: 1,
  });
  assert.equal(guard.decision, "already_synced");
});

test("arrival still waits when departure is not confirmed", async () => {
  const kv = makeKV({
    [`tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`]: JSON.stringify({
      schema_version: "chiron_connection_status_v1",
      enabled: true,
      environment: "test",
      production_enabled: false,
      official_submit_enabled: false,
      test_credentials_stored: true,
      last_connection_status: "test_passed",
      testflow_auto_submit_enabled: true,
      testflow_started_at: "2026-08-01T00:00:00.000Z",
    }),
  });
  const env = {
    COMPLIANCE_KV: kv,
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: "https://mow-acc.api.vlaanderen.be/chiron/taxirit",
  };
  const stop = stopEvent();
  const outcome = await _chironAutoSubmitOneEvent(env, stop, "stop-key", {
    source: "test",
    preloadedContextEntries: [
      { event: startEvent(CANONICAL_TRIP, "canon") },
      { event: stop },
    ],
  });
  assert.ok(
    outcome.reason === "official_payload_not_ready" ||
      outcome.reason === "waiting_for_departure" ||
      outcome.sync_state === "blocked" ||
      outcome.skipped === true,
  );
  assert.notEqual(outcome.reason, "already_synced");
});

test("reconcile continues after a blocked extra start", async () => {
  const statusKey = `tenant:${TENANT}:company:${COMPANY}:chiron_connection:v1`;
  const kv = makeKV({
    [statusKey]: JSON.stringify({
      schema_version: "chiron_connection_status_v1",
      enabled: true,
      environment: "test",
      production_enabled: false,
      official_submit_enabled: false,
      test_credentials_stored: true,
      last_connection_status: "test_passed",
      testflow_auto_submit_enabled: true,
      testflow_started_at: "2026-08-01T00:00:00.000Z",
    }),
  });
  const extra = startEvent(EXTRA_TRIP, "extra-rec");
  const canon = startEvent(CANONICAL_TRIP, "canon-rec");
  const stop = stopEvent();
  const prefix = `compliance_event_v1/tenant/${TENANT}/company/${COMPANY}/2026/08/15/`;
  await kv.put(`${prefix}1_extra`, JSON.stringify(extra));
  await kv.put(`${prefix}2_canon`, JSON.stringify(canon));
  await kv.put(`${prefix}3_stop`, JSON.stringify(stop));
  const env = {
    COMPLIANCE_KV: kv,
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: "https://mow-acc.api.vlaanderen.be/chiron/taxirit",
  };
  const outcome = await _chironAutoReconcileScopeBestEffort(env, TENANT, COMPANY, {
    source: "test",
  });
  assert.notEqual(outcome.stopped_on_definitive_failure, true);
});
