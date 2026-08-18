// CHIRON-TERMINAL-CLEANUP-P0
//
// Candidate-to-official reconciliation: after a proven Chiron success the
// candidate must resolve the official document with keyed gets, retire its
// due marker, and never consume another cron slot or provider call.
//
//   node --test workers/compliance/chiron_terminal_cleanup_p0.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  CHIRON_RECONCILE_DUE_PREFIX,
  CHIRON_RECONCILE_DUE_DONE_KEY,
  ChironDueIndexTestCrash,
  armChironDueMarker,
  buildChironDueMarkerKey,
  computeChironReconcileDueAtMs,
  markChironDueMigrationComplete,
  selectDueChironMarkers,
} from "./chiron_reconcile_due_index.js";

const {
  _chironCronReconcileAllScopesBestEffort,
  _chironWriteExportStatus,
  _chironReadBestExportStatusForEvent,
  _chironDeriveOfficialIdempotencyKeyFromEvent,
  _chironPutOfficialCandidatePointer,
  _chironCandidateExportStatusKey,
  buildChironOfficialEventRefKey,
  buildChironExportStatusKey,
  buildChironOfficialIdempotencyKey,
  buildChironConnectionStatusResponse,
  CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  safeSegment,
} = __testInternals;

const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const TENANT_A = "fluxidi_fluxidi_ddmh9g";
const COMPANY_A = "fluxidi_fluxidi_ddmh9g";
const TENANT_B = "tenant_isolated_b";
const COMPANY_B = "company_isolated_b";
const BOOKING = "street_1787043120900_3l031n2b";
const TRIP = "trip_30b3ce1a-a592-46aa-8135-99aeb76a0c99";
const KBO = "0772.931.038";
const NOW_MS = Date.parse("2026-08-18T13:10:00.000Z");

let originalFetch;
let providerCalls = [];

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    providerCalls.push(href);
    throw new Error(`hermetic test: blocked outbound fetch to ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  providerCalls = [];
});

function connectionDoc(overrides = {}) {
  return {
    schema_version: "chiron_connection_status_v1",
    enabled: true,
    environment: "production",
    region: "flanders",
    production_enabled: false,
    test_credentials_stored: true,
    production_credentials_stored: true,
    last_connection_status: "test_passed",
    testflow_auto_submit_enabled: true,
    testflow_started_at: "2026-08-01T05:24:57.669Z",
    test_departure_sent_count: 5,
    test_arrival_sent_count: 5,
    test_messages_sent_count: 10,
    test_rides_completed_count: 5,
    testflow_status: "complete",
    official_submission_performed_at: null,
    ...overrides,
  };
}

function streetEvent(kind, seqMs, overrides = {}) {
  const isStop = kind === "ride_stop";
  const created = new Date(seqMs).toISOString();
  return {
    event_type: kind,
    event_id: `${kind}:${TENANT_A}:${COMPANY_A}:${TRIP}`,
    tenant_id: TENANT_A,
    company_id: COMPANY_A,
    booking_id: BOOKING,
    trip_id: TRIP,
    ride_type: "direct",
    enterprise_number: "0772931038",
    lifecycle_status: isStop ? "stopped" : "started",
    created_at_utc: created,
    timestamps: {
      event_at_utc: created,
      started_at_utc: "2026-08-18T08:52:00.480Z",
      ...(isStop ? { stopped_at_utc: "2026-08-18T08:58:15.037Z" } : {}),
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

function eventKeyFor(tenantId, companyId, day, ms, label) {
  const t = safeSegment(tenantId, "");
  const c = safeSegment(companyId, "");
  return `compliance_event_v1/tenant/${t}/company/${c}/${day}/${String(ms).padStart(13, "0")}_${label}`;
}

function officialIdem(event, status) {
  return buildChironOfficialIdempotencyKey(
    { tenant_id: event.tenant_id, company_id: event.company_id },
    KBO,
    event.booking_id,
    status,
  );
}

function officialStatusKey(event, status) {
  return buildChironExportStatusKey(
    safeSegment(event.tenant_id, ""),
    safeSegment(event.company_id, ""),
    officialIdem(event, status),
  );
}

function candidateKey(event) {
  return _chironCandidateExportStatusKey(event.tenant_id, event.company_id, event, null);
}

function dueMarkerNames(h) {
  return [...h.compliance.keys()]
    .filter((k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY)
    .sort();
}

function createCountingEnv() {
  const compliance = new Map();
  const counts = {
    lists: 0,
    valueReads: 0,
    writes: 0,
    deletes: 0,
    bookingReads: 0,
    eventPrefixLists: 0,
  };
  const valueReadKeys = [];
  const listPrefixes = [];

  const env = {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_URL,
    COMPLIANCE_KV: {
      async get(key) {
        counts.valueReads += 1;
        valueReadKeys.push(key);
        const row = compliance.get(key);
        return row ? row.value : null;
      },
      async put(key, value, opts = {}) {
        counts.writes += 1;
        compliance.set(key, {
          value: typeof value === "string" ? value : JSON.stringify(value),
          metadata: opts.metadata || null,
        });
      },
      async delete(key) {
        counts.deletes += 1;
        compliance.delete(key);
      },
      async list({ prefix = "", limit = 1000, cursor } = {}) {
        counts.lists += 1;
        listPrefixes.push(prefix);
        if (prefix.startsWith("compliance_event_v1/")) counts.eventPrefixLists += 1;
        const all = [...compliance.keys()].filter((k) => k.startsWith(prefix)).sort();
        const start = cursor
          ? Number(Buffer.from(String(cursor), "base64").toString("utf8")) || 0
          : 0;
        const slice = all.slice(start, start + limit);
        const next = start + slice.length;
        const complete = next >= all.length;
        return {
          keys: slice.map((name) => ({
            name,
            metadata: compliance.get(name)?.metadata || null,
          })),
          list_complete: complete,
          cursor: complete
            ? undefined
            : Buffer.from(String(next), "utf8").toString("base64"),
        };
      },
    },
    BOOKING_KV: {
      async get() {
        counts.bookingReads += 1;
        return null;
      },
    },
  };

  return {
    env,
    compliance,
    counts,
    valueReadKeys,
    listPrefixes,
    eventReads: () => valueReadKeys.filter((k) => k.startsWith("compliance_event_v1/")),
    dueLists: () => listPrefixes.filter((p) => p === CHIRON_RECONCILE_DUE_PREFIX).length,
    resetCounts() {
      counts.lists = 0;
      counts.valueReads = 0;
      counts.writes = 0;
      counts.deletes = 0;
      counts.bookingReads = 0;
      counts.eventPrefixLists = 0;
      valueReadKeys.length = 0;
      listPrefixes.length = 0;
    },
  };
}

async function seedConnection(h, tenantId, companyId) {
  await h.env.COMPLIANCE_KV.put(
    `tenant:${tenantId}:company:${companyId}:chiron_connection:v1`,
    JSON.stringify(connectionDoc()),
  );
}

function officialSyncedDoc(event, status, lastAttemptIso) {
  return {
    schema_version: "chiron_export_status_v1",
    tenant_id: event.tenant_id,
    company_id: event.company_id,
    event_id: event.event_id,
    official_idempotency_key: officialIdem(event, status),
    official_ritnummer: event.booking_id,
    official_status: status,
    sync_state: "synced",
    external_status_code: 201,
    fouten_count: 0,
    last_attempt_at: lastAttemptIso,
    attempt_count: 1,
    auto_submit: true,
    auto_submit_source: "cron",
  };
}

function parseDoc(h, key) {
  const raw = h.compliance.get(key)?.value;
  return raw ? JSON.parse(raw) : null;
}

async function seedReadyScope(h) {
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
}

test("1. fresh departure success records the official reference and retires its marker", async () => {
  const h = createCountingEnv();
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  assert.equal(dueMarkerNames(h).length, 1);

  await _chironWriteExportStatus(
    h.env,
    officialStatusKey(start, "vertrek"),
    officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z"),
    { event: start, eventKey: startKey, previousStatus: null, nowMs: NOW_MS },
  );

  const candidate = parseDoc(h, candidateKey(start));
  assert.equal(candidate.official_idempotency_key, officialIdem(start, "vertrek"));
  assert.equal(candidate.sync_state, "synced");
  const ref = parseDoc(h, buildChironOfficialEventRefKey(TENANT_A, COMPANY_A, start.event_id));
  assert.equal(ref.k, officialIdem(start, "vertrek"));
  assert.equal(dueMarkerNames(h).length, 0);
});

test("2. fresh arrival success records the official reference and retires its marker", async () => {
  const h = createCountingEnv();
  const stop = streetEvent("ride_stop", Date.parse("2026-08-18T08:58:17.192Z"));
  const stopKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043497192, "ride_stop");
  await h.env.COMPLIANCE_KV.put(stopKey, JSON.stringify(stop));
  await armChironDueMarker(h.env.COMPLIANCE_KV, stopKey, 0);

  await _chironWriteExportStatus(
    h.env,
    officialStatusKey(stop, "aankomst"),
    officialSyncedDoc(stop, "aankomst", "2026-08-18T12:56:00.554Z"),
    { event: stop, eventKey: stopKey, previousStatus: null, nowMs: NOW_MS },
  );

  const candidate = parseDoc(h, candidateKey(stop));
  assert.equal(candidate.official_idempotency_key, officialIdem(stop, "aankomst"));
  assert.equal(candidate.sync_state, "synced");
  assert.equal(dueMarkerNames(h).length, 0);
});

test("3. candidate resolves official synced state through a targeted get", async () => {
  const h = createCountingEnv();
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  await h.env.COMPLIANCE_KV.put(
    officialStatusKey(start, "vertrek"),
    JSON.stringify(officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z")),
  );
  await h.env.COMPLIANCE_KV.put(
    candidateKey(start),
    JSON.stringify({
      sync_state: "pending_build",
      reason_code: "payload_build",
      official_idempotency_key: null,
      last_attempt_at: "2026-08-18T12:55:57.804Z",
      attempt_count: 0,
    }),
  );
  h.resetCounts();
  const best = await _chironReadBestExportStatusForEvent(h.env, start);
  assert.equal(best.sync_state, "synced");
  assert.equal(best.official_idempotency_key, officialIdem(start, "vertrek"));
  assert.equal(h.counts.lists, 0);
  assert.ok(h.counts.valueReads >= 1 && h.counts.valueReads <= 3);
  assert.equal(h.counts.bookingReads, 0);
});

test("4. synced candidate is not rearmed", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await _chironWriteExportStatus(
    h.env,
    officialStatusKey(start, "vertrek"),
    officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z"),
    { event: start, eventKey: startKey, previousStatus: null, nowMs: NOW_MS },
  );
  const lastAttempt = parseDoc(h, candidateKey(start)).last_attempt_at;
  h.resetCounts();
  const first = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(first.due_selected, 0);
  assert.equal(dueMarkerNames(h).length, 0);
  h.resetCounts();
  const second = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 5 * 60 * 1000,
  });
  assert.equal(second.due_selected, 0);
  assert.equal(dueMarkerNames(h).length, 0);
  assert.equal(parseDoc(h, candidateKey(start)).last_attempt_at, lastAttempt);
  assert.equal(providerCalls.length, 0);
  assert.equal(h.counts.bookingReads, 0);
});

test("5. stale due-at-0 marker is deleted without hydration or provider call", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(
    officialStatusKey(start, "vertrek"),
    JSON.stringify(officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z")),
  );
  await h.env.COMPLIANCE_KV.put(
    candidateKey(start),
    JSON.stringify({
      tenant_id: TENANT_A,
      company_id: COMPANY_A,
      event_id: start.event_id,
      sync_state: "pending_build",
      official_idempotency_key: null,
      last_attempt_at: "2026-08-18T12:55:57.804Z",
      attempt_count: 0,
    }),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 0);
  assert.equal(dueMarkerNames(h).length, 0);
  assert.equal(h.counts.bookingReads, 0);
  assert.equal(h.counts.eventPrefixLists, 0);
  assert.equal(providerCalls.length, 0);
  assert.ok(h.eventReads().length <= 1);
});

test("6. future retry has one authoritative future marker and no immediate marker", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  const last = NOW_MS - 30_000;
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(
    officialStatusKey(start, "vertrek"),
    JSON.stringify({
      ...officialSyncedDoc(start, "vertrek", new Date(last).toISOString()),
      sync_state: "failed",
      failure_kind: "retryable",
      external_status_code: 200,
      fouten_count: 1,
      attempt_count: 1,
    }),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  const markers = dueMarkerNames(h);
  assert.equal(markers.length, 1);
  const dueAt = computeChironReconcileDueAtMs(
    parseDoc(h, officialStatusKey(start, "vertrek")),
    NOW_MS,
    { waitingRecheckMs: 5 * 60 * 1000 },
  );
  assert.ok(dueAt > NOW_MS);
  const expected = await buildChironDueMarkerKey(dueAt, startKey);
  assert.equal(markers[0], expected);
  const dueZero = await buildChironDueMarkerKey(0, startKey);
  assert.equal(h.compliance.has(dueZero), false);
});

test("7. duplicate markers cannot create duplicate Chiron submissions", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(
    officialStatusKey(start, "vertrek"),
    JSON.stringify(officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z")),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, NOW_MS - 1);
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 0);
  assert.equal(providerCalls.length, 0);
  assert.equal(dueMarkerNames(h).length, 0);
});

test("8. crash after official persistence but before marker delete self-heals next tick", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  await assert.rejects(
    () =>
      _chironWriteExportStatus(
        h.env,
        officialStatusKey(start, "vertrek"),
        officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z"),
        {
          event: start,
          eventKey: startKey,
          previousStatus: null,
          nowMs: NOW_MS,
          crashAfter: "after_persist",
        },
      ),
    (err) => err instanceof ChironDueIndexTestCrash,
  );
  assert.ok(parseDoc(h, officialStatusKey(start, "vertrek")));
  assert.equal(parseDoc(h, candidateKey(start)).official_idempotency_key, officialIdem(start, "vertrek"));
  assert.ok(dueMarkerNames(h).length >= 1);

  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 0);
  assert.equal(dueMarkerNames(h).length, 0);
  assert.equal(providerCalls.length, 0);
  assert.equal(h.counts.bookingReads, 0);
});

test("9. crash before official persistence leaves recoverable marked work", async () => {
  const h = createCountingEnv();
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  const pendingOfficial = {
    ...officialSyncedDoc(start, "vertrek", new Date(NOW_MS).toISOString()),
    sync_state: "pending",
    external_status_code: null,
    fouten_count: null,
    attempt_count: 1,
  };
  await assert.rejects(
    () =>
      _chironWriteExportStatus(
        h.env,
        officialStatusKey(start, "vertrek"),
        pendingOfficial,
        {
          event: start,
          eventKey: startKey,
          previousStatus: {
            sync_state: "pending_build",
            last_attempt_at: new Date(NOW_MS - 120000).toISOString(),
          },
          nowMs: NOW_MS,
          crashAfter: "after_arm",
        },
      ),
    (err) => err instanceof ChironDueIndexTestCrash,
  );
  assert.equal(parseDoc(h, officialStatusKey(start, "vertrek")), null);
  assert.ok(dueMarkerNames(h).length >= 1);
});

test("10. legacy candidate without pointer self-heals through a deterministic targeted lookup", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(
    officialStatusKey(start, "vertrek"),
    JSON.stringify(officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z")),
  );
  await h.env.COMPLIANCE_KV.put(
    candidateKey(start),
    JSON.stringify({
      tenant_id: TENANT_A,
      company_id: COMPANY_A,
      event_id: start.event_id,
      sync_state: "pending_build",
      official_idempotency_key: null,
      last_attempt_at: "2026-08-18T13:05:50.658Z",
      attempt_count: 0,
    }),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  assert.equal(_chironDeriveOfficialIdempotencyKeyFromEvent(start), officialIdem(start, "vertrek"));
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  const candidate = parseDoc(h, candidateKey(start));
  assert.equal(candidate.official_idempotency_key, officialIdem(start, "vertrek"));
  assert.equal(candidate.sync_state, "synced");
  assert.equal(candidate.last_attempt_at, "2026-08-18T13:05:50.658Z");
  assert.equal(dueMarkerNames(h).length, 0);
  assert.equal(providerCalls.length, 0);
});

test("11. missing official document preserves legitimate retry behaviour", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  const before = await buildChironDueMarkerKey(0, startKey);
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 1);
  assert.ok(h.compliance.has(before) || dueMarkerNames(h).length >= 1);
  const official = parseDoc(h, officialStatusKey(start, "vertrek"));
  assert.notEqual(official?.sync_state, "synced");
});

test("12. tenant/company mismatch refuses reuse", async () => {
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const foreign = officialSyncedDoc(start, "vertrek", "2026-08-18T12:55:59.365Z");
  foreign.tenant_id = TENANT_B;
  foreign.company_id = COMPANY_B;
  const linked = await _chironPutOfficialCandidatePointer(
    {
      COMPLIANCE_KV: {
        async get() { return null; },
        async put() { throw new Error("must_not_write_cross_tenant"); },
      },
    },
    start,
    officialIdem(start, "vertrek"),
    foreign,
  );
  assert.equal(linked, null);

  const h = createCountingEnv();
  await h.env.COMPLIANCE_KV.put(officialStatusKey(start, "vertrek"), JSON.stringify(foreign));
  const best = await _chironReadBestExportStatusForEvent(h.env, start);
  assert.equal(best?.sync_state === "synced", false);
});

test("13. two scopes cannot share candidate or official state", async () => {
  const startA = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startB = {
    ...startA,
    tenant_id: TENANT_B,
    company_id: COMPANY_B,
    event_id: `ride_start:${TENANT_B}:${COMPANY_B}:${TRIP}`,
  };
  assert.notEqual(candidateKey(startA), candidateKey(startB));
  assert.notEqual(officialStatusKey(startA, "vertrek"), officialStatusKey(startB, "vertrek"));
  assert.notEqual(
    buildChironOfficialEventRefKey(TENANT_A, COMPANY_A, startA.event_id),
    buildChironOfficialEventRefKey(TENANT_B, COMPANY_B, startB.event_id),
  );
});

test("14. departure remains ordered before arrival for one booking", async () => {
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  const stopKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043497192, "ride_stop");
  const listed = [
    { name: await buildChironDueMarkerKey(0, stopKey), metadata: { v: 1, ek: stopKey } },
    { name: await buildChironDueMarkerKey(0, startKey), metadata: { v: 1, ek: startKey } },
  ];
  const picked = selectDueChironMarkers(listed, { nowMs: NOW_MS, limit: 20 });
  const rows = picked.selected.map((row) => ({
    eventKey: row.eventKey,
    messageType: row.eventKey.includes("ride_stop") ? "arrival" : "departure",
    bookingId: BOOKING,
    eventAtMs: row.eventKey.includes("ride_stop") ? 1787043497192 : 1787043121583,
  }));
  rows.sort((a, b) => {
    if (a.bookingId && a.bookingId === b.bookingId) {
      if (a.messageType !== b.messageType) {
        return a.messageType === "departure" ? -1 : 1;
      }
      return a.eventAtMs - b.eventAtMs;
    }
    return b.eventAtMs - a.eventAtMs;
  });
  assert.equal(rows[0].messageType, "departure");
  assert.equal(rows[1].messageType, "arrival");
});

test("15. idle cron after migration: one due list, zero event value reads", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.equal(h.eventReads().length, 0);
  assert.equal(h.dueLists(), 1);
  assert.equal(h.counts.bookingReads, 0);
  assert.equal(h.counts.valueReads, 0);
  assert.equal(h.counts.writes, 0);
  assert.equal(providerCalls.length, 0);
});

test("16. considered-event growth does not reintroduce full-history reads", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  for (let i = 0; i < 40; i += 1) {
    await h.env.COMPLIANCE_KV.put(
      eventKeyFor(TENANT_A, COMPANY_A, "2026/08/10", 1786345177300 + i, `hist_${i}`),
      JSON.stringify({ event_type: "ride_stop", event_id: `hist_${i}` }),
    );
  }
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.ok(summary.due_selected <= CHIRON_AUTO_RECONCILE_MAX_PROCESS);
  assert.deepEqual(h.eventReads(), [startKey]);
  assert.equal(h.counts.eventPrefixLists, 0);
});

test("17. newest-first starvation regression remains green", async () => {
  const h = createCountingEnv();
  await seedReadyScope(h);
  for (let i = 0; i < 25; i += 1) {
    const old = {
      event_type: "ride_start",
      event_id: `old_${i}`,
      tenant_id: TENANT_A,
      company_id: COMPANY_A,
      booking_id: `street_old_${i}`,
      trip_id: `trip_old_${i}`,
      ride_type: "direct",
      created_at_utc: `2026-08-10T06:59:${String(i).padStart(2, "0")}.000Z`,
    };
    const key = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/10", 1786345177300 + i, `old_${i}`);
    await h.env.COMPLIANCE_KV.put(key, JSON.stringify(old));
    await armChironDueMarker(h.env.COMPLIANCE_KV, key, 0);
  }
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  const listed = [...h.compliance.keys()]
    .filter((k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX))
    .sort()
    .map((name) => ({ name, metadata: h.compliance.get(name)?.metadata || null }));
  const picked = selectDueChironMarkers(listed, {
    nowMs: NOW_MS,
    limit: CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  });
  assert.equal(picked.selected[0].eventKey, startKey);
});
