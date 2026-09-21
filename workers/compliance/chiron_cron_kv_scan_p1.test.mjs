// CHIRON-CRON-KV-SCAN-P1
//
// Due-index + write-reduction contract. Hermetic in-memory KV. Outbound
// fetch is trapped — no live Chiron, booking or payment calls.
//
//   node --test workers/compliance/chiron_cron_kv_scan_p1.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  CHIRON_RECONCILE_DUE_PREFIX,
  CHIRON_WAITING_RECHECK_MS,
  armChironDueMarker,
  markChironDueMigrationComplete,
} from "./chiron_reconcile_due_index.js";

const {
  _chironCronReconcileAllScopesBestEffort,
  _chironAutoReconcileScopeBestEffort,
  _chironWriteExportStatus,
  _chironExportStatusFunctionallyEqual,
  _chironTestflowCountersChanged,
  _chironReArmPairedArrivalAfterDeparture,
  recordChironTestflowSubmitResult,
  buildChironExportStatusKey,
  CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  safeSegment,
} = __testInternals;

const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const TENANT_A = "T_scan_p1_a";
const COMPANY_A = "C_scan_p1_a";
const TENANT_B = "T_scan_p1_b";
const COMPANY_B = "C_scan_p1_b";
const NOW_MS = Date.parse("2026-09-21T12:00:00.000Z");

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
    ...overrides,
  };
}

function rideEvent(kind, tenantId, companyId, bookingId, seq, overrides = {}) {
  const isStop = kind === "ride_stop";
  const created = new Date(NOW_MS - 3 * 60 * 60 * 1000 + seq * 60_000).toISOString();
  return {
    event_type: kind,
    event_id: `${kind}:${tenantId}:${companyId}:${bookingId}`,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: bookingId,
    trip_id: `trip_${bookingId}`,
    ride_type: "direct",
    created_at_utc: created,
    timestamps: {
      event_at_utc: created,
      started_at_utc: created,
      ...(isStop ? { stopped_at_utc: created } : {}),
    },
    driver: { driver_id: "drv_1" },
    vehicle: { vehicle_id: "vh_1", license_plate: "TXABC123" },
    locations: {
      pickup: { lat: 50.7720114, lng: 3.6695565, label: "origin" },
      dropoff: { lat: 50.850504, lng: 3.482422, label: "dest" },
    },
    fare: { currency: "EUR", distance_km: 12.5, total_amount: 20 },
    ...overrides,
  };
}

function eventKeyFor(tenantId, companyId, seq, label) {
  return `compliance_event_v1/tenant/${safeSegment(tenantId, "")}/company/${safeSegment(
    companyId,
    "",
  )}/2026/09/21/${String(1_780_000_000_000 + seq).padStart(13, "0")}_${label}`;
}

function createCountingEnv() {
  const compliance = new Map();
  const counts = { lists: 0, valueReads: 0, writes: 0, deletes: 0, bookingReads: 0 };
  const valueReadKeys = [];
  const writeKeys = [];
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
        writeKeys.push(key);
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
    writeKeys,
    listPrefixes,
    eventReads: () => valueReadKeys.filter((k) => k.startsWith("compliance_event_v1/")),
    dueLists: () => listPrefixes.filter((p) => p === CHIRON_RECONCILE_DUE_PREFIX).length,
    snapshot: () => ({
      lists: counts.lists,
      reads: counts.valueReads,
      writes: counts.writes,
      deletes: counts.deletes,
      bookingReads: counts.bookingReads,
      eventReads: valueReadKeys.filter((k) => k.startsWith("compliance_event_v1/")).length,
      dueLists: listPrefixes.filter((p) => p === CHIRON_RECONCILE_DUE_PREFIX).length,
      provider: providerCalls.length,
    }),
    resetCounts() {
      counts.lists = 0;
      counts.valueReads = 0;
      counts.writes = 0;
      counts.deletes = 0;
      counts.bookingReads = 0;
      valueReadKeys.length = 0;
      writeKeys.length = 0;
      listPrefixes.length = 0;
      providerCalls.length = 0;
    },
  };
}

async function seedConnection(h, tenantId, companyId, overrides = {}) {
  await h.env.COMPLIANCE_KV.put(
    `tenant:${tenantId}:company:${companyId}:chiron_connection:v1`,
    JSON.stringify(connectionDoc(overrides)),
  );
}

async function seedHistory(h, tenantId, companyId, n) {
  for (let i = 0; i < n; i += 1) {
    const event = rideEvent("ride_stop", tenantId, companyId, `old_${i}`, i);
    const key = eventKeyFor(tenantId, companyId, i, `old_${i}`);
    await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  }
}

test("1. idle after migration: 1 due list, 0 event reads, 0 writes, 0 provider", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, 40);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.ok, true);
  assert.equal(summary.due_selected, 0);
  assert.equal(h.eventReads().length, 0);
  assert.equal(h.dueLists(), 1);
  assert.equal(h.counts.writes, 0);
  assert.equal(h.counts.deletes, 0);
  assert.deepEqual(providerCalls, []);
});

test("2. new ride is selected without rereading finished history", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, 40);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_new", 90);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 90, "new");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  await armChironDueMarker(h.env.COMPLIANCE_KV, key, 0);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 1);
  assert.deepEqual(h.eventReads(), [key]);
  assert.equal(h.eventReads().some((k) => k.includes("old_")), false);
});

test("3. retryable failure stays due; definitive cooldown is future", async () => {
  const retryable = {
    sync_state: "retryable_failed",
    failure_kind: "retryable",
    last_attempt_at: new Date(NOW_MS - 60_000).toISOString(),
  };
  const definitive = {
    sync_state: "failed",
    failure_kind: "definitive",
    last_attempt_at: new Date(NOW_MS - 1_000).toISOString(),
    outbound_fingerprint_definitive_attempts: 1,
  };
  const { computeChironReconcileDueAtMs } = await import("./chiron_reconcile_due_index.js");
  assert.equal(computeChironReconcileDueAtMs(retryable, NOW_MS), 0);
  const dueDef = computeChironReconcileDueAtMs(definitive, NOW_MS, {
    definitiveCooldownMs: 10 * 60 * 1000,
    definitiveMaxAttempts: 6,
  });
  assert.ok(dueDef > NOW_MS);
});

test("4. waiting arrival is future until recheck; departure success rearms it", async () => {
  const h = createCountingEnv();
  const start = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_wait", 1);
  const stop = rideEvent("ride_stop", TENANT_A, COMPANY_A, "street_wait", 2);
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, 1, "wait_start");
  const stopKey = eventKeyFor(TENANT_A, COMPANY_A, 2, "wait_stop");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(stopKey, JSON.stringify(stop));
  const { computeChironReconcileDueAtMs } = await import("./chiron_reconcile_due_index.js");
  const waitingDue = computeChironReconcileDueAtMs(
    {
      sync_state: "waiting_for_departure",
      last_attempt_at: new Date(NOW_MS).toISOString(),
    },
    NOW_MS,
  );
  assert.equal(waitingDue, NOW_MS + CHIRON_WAITING_RECHECK_MS);
  const armed = await _chironReArmPairedArrivalAfterDeparture(h.env, start, [
    { key: startKey, event: start },
    { key: stopKey, event: stop },
  ]);
  assert.ok(armed >= 1);
  const markers = [...h.compliance.keys()].filter((k) =>
    k.startsWith(CHIRON_RECONCILE_DUE_PREFIX),
  );
  assert.ok(markers.some((k) => k.includes(":0000000000000000:")));
});

test("5. restart after !done does not full-scan and does not lose a due marker", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_restart", 5);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 5, "restart");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  await armChironDueMarker(h.env.COMPLIANCE_KV, key, 0);
  h.resetCounts();
  const first = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  const mid = h.snapshot();
  const second = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(first.due_selected, 1);
  assert.ok(second.due_selected <= 1);
  assert.equal(mid.eventReads, 1);
  assert.equal(
    h.listPrefixes.includes("compliance_event_v1/"),
    false,
    "restart never lists the historical event prefix",
  );
});

test("6. overlapping duplicate markers collapse to one event read", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_dup", 6);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 6, "dup");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  await armChironDueMarker(h.env.COMPLIANCE_KV, key, 0);
  await armChironDueMarker(h.env.COMPLIANCE_KV, key, NOW_MS - 1000);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 1);
  assert.equal(h.eventReads().length, 1);
  assert.ok(h.counts.deletes >= 1);
});

test("7. two companies stay isolated", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedConnection(h, TENANT_B, COMPANY_B);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const eventA = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_a", 7);
  const eventB = rideEvent("ride_start", TENANT_B, COMPANY_B, "street_b", 8);
  const keyA = eventKeyFor(TENANT_A, COMPANY_A, 7, "iso_a");
  const keyB = eventKeyFor(TENANT_B, COMPANY_B, 8, "iso_b");
  await h.env.COMPLIANCE_KV.put(keyA, JSON.stringify(eventA));
  await h.env.COMPLIANCE_KV.put(keyB, JSON.stringify(eventB));
  await armChironDueMarker(h.env.COMPLIANCE_KV, keyA, 0);
  h.resetCounts();
  await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "status_poll",
    nowMs: NOW_MS,
  });
  assert.ok(h.eventReads().includes(keyA));
  assert.equal(h.eventReads().includes(keyB), false);
});

test("8. unchanged already-synced status and counters are not rewritten", async () => {
  const before = connectionDoc();
  const after = recordChironTestflowSubmitResult(before, {
    officialStatus: "vertrek",
    ritnummer: "already-tracked",
    ok: true,
    foutenCount: 0,
    sanitizedError: null,
  });
  const again = recordChironTestflowSubmitResult(after, {
    officialStatus: "vertrek",
    ritnummer: after.testflow_ritnummers_departure?.[0] || "x",
    ok: true,
    foutenCount: 0,
    sanitizedError: null,
  });
  assert.equal(_chironTestflowCountersChanged(after, again), false);
  assert.equal(
    _chironExportStatusFunctionallyEqual(
      { sync_state: "synced", official_status: "vertrek" },
      { sync_state: "synced", official_status: "vertrek", last_attempt_at: "x" },
    ),
    true,
  );
});

test("9. gated / disabled connection is not an event scan", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A, {
    enabled: false,
    testflow_auto_submit_enabled: true,
  });
  await seedHistory(h, TENANT_A, COMPANY_A, 20);
  h.resetCounts();
  const outcome = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(outcome.gated, true);
  assert.equal(outcome.ok, false);
  assert.equal(h.eventReads().length, 0);
  assert.equal(h.listPrefixes.includes("compliance_event_v1/"), false);
});

test("10. one-shot migration cost is temporary; later ticks stay cheap", async () => {
  const history = 35;
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, history);
  h.resetCounts();
  const first = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  const migration = h.snapshot();
  h.resetCounts();
  const second = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 60_000,
  });
  const lasting = h.snapshot();
  assert.equal(first.ok, true);
  assert.ok(migration.eventReads >= history, "first pass may read history once");
  assert.equal(second.migration_done, true);
  assert.ok(
    lasting.eventReads < history,
    `lasting event reads ${lasting.eventReads} must be below history ${history}`,
  );
  assert.ok(lasting.reads < migration.reads);
  assert.equal(lasting.provider, 0);
  assert.ok(CHIRON_AUTO_RECONCILE_MAX_PROCESS === 20);
});

test("11. disabled cron still costs zero KV", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  h.env.CHIRON_CRON_ENABLED = "0";
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron" });
  assert.equal(summary.disabled, true);
  assert.equal(h.counts.lists, 0);
  assert.equal(h.counts.valueReads, 0);
  assert.equal(h.counts.writes, 0);
});

test("12. old full-scan vs new idle comparison (counted, not estimated)", async () => {
  const history = 80;
  const hOld = createCountingEnv();
  await seedConnection(hOld, TENANT_A, COMPANY_A);
  await seedHistory(hOld, TENANT_A, COMPANY_A, history);
  hOld.resetCounts();
  await _chironAutoReconcileScopeBestEffort(hOld.env, TENANT_A, COMPANY_A, {
    source: "old_scan",
    nowMs: NOW_MS,
  });
  const oldPass = hOld.snapshot();

  const hNew = createCountingEnv();
  await seedConnection(hNew, TENANT_A, COMPANY_A);
  await seedHistory(hNew, TENANT_A, COMPANY_A, history);
  await markChironDueMigrationComplete(hNew.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  hNew.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(hNew.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  const newIdle = hNew.snapshot();

  assert.ok(oldPass.eventReads >= history);
  assert.equal(newIdle.eventReads, 0);
  assert.equal(newIdle.dueLists, 1);
  assert.ok(newIdle.reads < oldPass.reads / 10);
});
