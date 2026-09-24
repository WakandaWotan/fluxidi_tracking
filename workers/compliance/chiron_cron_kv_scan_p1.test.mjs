// CHIRON-CRON-KV-SCAN-P1
//
// Due-index + write-reduction contract. Hermetic in-memory KV. Outbound
// fetch is trapped — no live Chiron, booking or payment calls.
//
//   node --test workers/compliance/chiron_cron_kv_scan_p1.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";
import worker from "./fluxidi_compliance_worker.js";
import {
  CHIRON_RECONCILE_DUE_DONE_KEY,
  CHIRON_RECONCILE_DUE_MIGRATION_KEY,
  CHIRON_RECONCILE_DUE_PREFIX,
  CHIRON_RECONCILE_RECOVER_PREFIX,
  CHIRON_RECONCILE_WAKEUP_PREFIX,
  CHIRON_WAITING_RECHECK_MS,
  CHIRON_RETRYABLE_RECHECK_MS,
  CHIRON_DUE_RECOVER_STATE_VERSION,
  buildChironScopeRecoverKey,
  CHIRON_DUE_RECOVER_BATCH,
  CHIRON_DUE_RECOVER_CATCHUP_WINDOW_MS,
  CHIRON_DUE_RECOVER_WINDOW_MS,
  armChironDueMarker,
  buildChironRecentDateIndexPrefixes,
  isChironFullScopeEventListPrefix,
  markChironDueMigrationComplete,
} from "./chiron_reconcile_due_index.js";

const {
  _chironCronReconcileAllScopesBestEffort,
  _chironAutoReconcileScopeBestEffort,
  _chironWriteExportStatus,
  _chironExportStatusFunctionallyEqual,
  _chironTestflowCountersChanged,
  _chironReArmPairedArrivalAfterDeparture,
  _chironMarkScopeDueMigrationComplete,
  _chironScopeDueMigrationKey,
  _chironResolveDueCandidate,
  _chironConfirmDueMarkerAfterPersist,
  CHIRON_SCOPE_DUE_MIGRATION_BATCH,
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

function recentDateKey(event, atMs) {
  const d = new Date(atMs);
  const y = String(d.getUTCFullYear()).padStart(4, "0");
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  const ms = String(atMs).padStart(13, "0");
  return [
    "compliance_event_v1",
    "tenant",
    safeSegment(event.tenant_id, ""),
    "company",
    safeSegment(event.company_id, ""),
    y,
    m,
    day,
    `${ms}_${safeSegment(event.event_id, "evt")}`,
  ].join("/");
}

function canonicalKeyFor(event) {
  return [
    "compliance_event_canonical_v1",
    "tenant",
    safeSegment(event.tenant_id, ""),
    "company",
    safeSegment(event.company_id, ""),
    "eid",
    safeSegment(event.event_id, "evt"),
  ].join("/");
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
      async get(key, opts = {}) {
        counts.valueReads += 1;
        valueReadKeys.push(key);
        const row = compliance.get(key);
        if (!row) return null;
        if (opts.type === "json") {
          try {
            return JSON.parse(row.value);
          } catch (_) {
            return null;
          }
        }
        return row.value;
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

async function finishMigration(h, tenantId, companyId) {
  await _chironMarkScopeDueMigrationComplete(h.env, tenantId, companyId, NOW_MS);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
}

async function appendViaEventsApi(h, event) {
  h.env.COMPLIANCE_ADMIN_TOKEN = "p1-admin";
  const res = await worker.fetch(
    new Request("https://compliance.internal/compliance/events/append", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: "Bearer p1-admin",
      },
      body: JSON.stringify(event),
    }),
    h.env,
    { waitUntil() {} },
  );
  return res.json();
}

async function seedHistory(h, tenantId, companyId, n) {
  for (let i = 0; i < n; i += 1) {
    const event = rideEvent("ride_stop", tenantId, companyId, `old_${i}`, i);
    const key = eventKeyFor(tenantId, companyId, i, `old_${i}`);
    await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  }
}

function withPinnedNow(nowMs, fn) {
  const previous = Date.now;
  Date.now = () => nowMs;
  const restore = () => {
    Date.now = previous;
  };
  try {
    const result = fn();
    if (result && typeof result.then === "function") {
      return Promise.resolve(result).finally(restore);
    }
    restore();
    return result;
  } catch (error) {
    restore();
    throw error;
  }
}

function hasDueMarkerFor(h, eventKey) {
  return [...h.compliance.keys()].some(
    (k) =>
      k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) &&
      k !== CHIRON_RECONCILE_DUE_DONE_KEY &&
      (h.compliance.get(k)?.metadata?.ek || "") === eventKey,
  );
}

async function putUnmarkedRecent(h, bookingId, seq, atMs) {
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, bookingId, seq, {
    created_at_utc: new Date(atMs).toISOString(),
    timestamps: {
      event_at_utc: new Date(atMs).toISOString(),
      started_at_utc: new Date(atMs).toISOString(),
    },
  });
  const key = recentDateKey(event, atMs);
  await h.env.COMPLIANCE_KV.put(canonicalKeyFor(event), JSON.stringify(event));
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  return { event, key };
}

async function putArmedRecent(h, bookingId, seq, atMs) {
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, bookingId, seq, {
    created_at_utc: new Date(atMs).toISOString(),
    timestamps: {
      event_at_utc: new Date(atMs).toISOString(),
      started_at_utc: new Date(atMs).toISOString(),
    },
  });
  const key = recentDateKey(event, atMs);
  await h.env.COMPLIANCE_KV.put(canonicalKeyFor(event), JSON.stringify(event));
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  await armChironDueMarker(h.env.COMPLIANCE_KV, key, 0);
  return { event, key };
}

test("1. idle after migration: 1 due list, 0 event reads, 0 writes, 0 provider", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, 40);
  await finishMigration(h, TENANT_A, COMPANY_A);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.ok, true);
  assert.equal(summary.due_selected, 0);
  assert.equal(h.eventReads().length, 0);
  assert.equal(h.dueLists(), 1);
  assert.equal(
    h.writeKeys.every((k) => k.startsWith(CHIRON_RECONCILE_RECOVER_PREFIX)),
    true,
    "idle may persist the recover watermark only",
  );
  assert.equal(h.counts.deletes, 0);
  assert.equal(h.listPrefixes.some(isChironFullScopeEventListPrefix), false);
  assert.deepEqual(providerCalls, []);
});

test("2. new ride is selected without rereading finished history", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, 40);
  await finishMigration(h, TENANT_A, COMPANY_A);
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
  const { computeChironReconcileDueAtMs, CHIRON_RETRYABLE_RECHECK_MS } = await import("./chiron_reconcile_due_index.js");
  assert.ok(
    computeChironReconcileDueAtMs(retryable, NOW_MS) > NOW_MS,
    "fresh retryable is parked past the next cron tick",
  );
  assert.equal(
    computeChironReconcileDueAtMs(
      {
        ...retryable,
        last_attempt_at: new Date(NOW_MS - CHIRON_RETRYABLE_RECHECK_MS - 1).toISOString(),
      },
      NOW_MS,
    ),
    0,
  );
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
  await finishMigration(h, TENANT_A, COMPANY_A);
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
  await finishMigration(h, TENANT_A, COMPANY_A);
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
  await finishMigration(h, TENANT_A, COMPANY_A);
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
  await finishMigration(hNew, TENANT_A, COMPANY_A);
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

test("14. a company enabled after !done is scanned; global done does not hide it", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);
  await seedConnection(h, TENANT_B, COMPANY_B);
  const late = rideEvent("ride_start", TENANT_B, COMPANY_B, "street_late", 93);
  const lateKey = eventKeyFor(TENANT_B, COMPANY_B, 93, "late");
  await h.env.COMPLIANCE_KV.put(lateKey, JSON.stringify(late));
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.ok(h.eventReads().includes(lateKey));
  assert.equal(summary.ok, true);
  assert.equal(
    h.eventReads().some((k) => k.includes("old_")),
    false,
  );
});

test("15. event persist without marker is recovered by confirm; get error does not retire", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_gap", 94);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 94, "gap");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  const { _chironConfirmDueMarkerAfterPersist } = __testInternals;
  const marker = await _chironConfirmDueMarkerAfterPersist(h.env, event, key);
  assert.ok(marker);
  h.resetCounts();
  const first = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(first.due_selected, 1);
  assert.deepEqual(h.eventReads(), [key]);

  const empty = createCountingEnv();
  const markerKey = await armChironDueMarker(empty.env.COMPLIANCE_KV, key, 0);
  empty.env.COMPLIANCE_KV.get = async () => {
    throw new Error("kv_temporarily_unavailable");
  };
  const resolved = await _chironResolveDueCandidate(
    empty.env,
    { eventKey: key, markerKey },
    NOW_MS,
    null,
  );
  assert.equal(resolved.kind, "read_error");
  assert.equal(empty.counts.deletes, 0);
});

test("16. waiting stay idle until due-at; departure success rearms arrival for the next tick", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);
  const start = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_wait2", 1);
  const stop = rideEvent("ride_stop", TENANT_A, COMPANY_A, "street_wait2", 2);
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, 1, "wait2_start");
  const stopKey = eventKeyFor(TENANT_A, COMPANY_A, 2, "wait2_stop");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(stopKey, JSON.stringify(stop));
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  await h.env.COMPLIANCE_KV.put(
    buildChironExportStatusKey(t, c, `candidate_v1:${stop.event_id}`),
    JSON.stringify({
      sync_state: "waiting_for_departure",
      last_attempt_at: new Date(NOW_MS).toISOString(),
      official_status: "aankomst",
    }),
  );
  await h.env.COMPLIANCE_KV.put(
    buildChironExportStatusKey(t, c, `candidate_v1:${start.event_id}`),
    JSON.stringify({
      sync_state: "failed",
      failure_kind: "definitive",
      outbound_fingerprint_definitive_attempts: 6,
      last_attempt_at: new Date(NOW_MS - 60_000).toISOString(),
      official_status: "vertrek",
    }),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, stopKey, NOW_MS + CHIRON_WAITING_RECHECK_MS);
  h.resetCounts();
  const idle = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 60_000,
  });
  assert.equal(idle.due_selected, 0);
  assert.equal(h.eventReads().length, 0);

  await _chironWriteExportStatus(
    h.env,
    buildChironExportStatusKey(t, c, `candidate_v1:${start.event_id}`),
    {
      sync_state: "synced",
      official_status: "vertrek",
      last_attempt_at: new Date(NOW_MS + 90_000).toISOString(),
    },
    { event: start, eventKey: startKey, nowMs: NOW_MS + 90_000 },
  );
  const armed = await _chironReArmPairedArrivalAfterDeparture(h.env, start, [
    { key: startKey, event: start },
    { key: stopKey, event: stop },
  ]);
  assert.ok(armed >= 1);
  h.resetCounts();
  const after = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 90_000,
  });
  assert.equal(after.due_selected, 1);
  assert.deepEqual(h.eventReads(), [stopKey]);
});

test("17. scoped migration paginates, survives an interrupt, and sets !done only at the end", async () => {
  const n = CHIRON_SCOPE_DUE_MIGRATION_BATCH + 40;
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedConnection(h, TENANT_B, COMPANY_B);
  await seedHistory(h, TENANT_A, COMPANY_A, n);
  await seedHistory(h, TENANT_B, COMPANY_B, 30);
  h.resetCounts();
  const first = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  const firstSnap = h.snapshot();
  assert.equal(first.migration_done, false);
  assert.ok(firstSnap.eventReads <= CHIRON_SCOPE_DUE_MIGRATION_BATCH * 2 + 5);
  assert.ok(firstSnap.eventReads < n + 30);
  assert.ok(!h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY));

  let ticks = 1;
  let last = first;
  while (!last.migration_done && ticks < 20) {
    last = await _chironCronReconcileAllScopesBestEffort(h.env, {
      source: "cron",
      nowMs: NOW_MS + ticks * 60_000,
    });
    ticks += 1;
  }
  assert.equal(last.migration_done, true);
  assert.ok(h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY));
  assert.ok(ticks >= 2, "1552-class prefixes need more than one page");
});

test("18. rollback to old writer then remigrate finds the unmarked event", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, 5);
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.equal(h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY), true);

  const orphan = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_old_writer", 200);
  const orphanKey = eventKeyFor(TENANT_A, COMPANY_A, 200, "old_writer");
  await h.env.COMPLIANCE_KV.put(orphanKey, JSON.stringify(orphan));

  h.compliance.delete(CHIRON_RECONCILE_DUE_DONE_KEY);
  h.compliance.delete(CHIRON_RECONCILE_DUE_MIGRATION_KEY);
  h.compliance.delete(_chironScopeDueMigrationKey(TENANT_A, COMPANY_A));

  const eventKeysBefore = [...h.compliance.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/"),
  ).length;
  h.resetCounts();
  const again = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 120_000,
  });
  const eventKeysAfter = [...h.compliance.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/"),
  ).length;
  assert.equal(eventKeysAfter, eventKeysBefore);
  assert.ok(h.eventReads().includes(orphanKey));
  assert.ok(again.due_selected >= 0);
});

test("19. gated due markers are deferred, not deleted", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A, { enabled: false });
  await finishMigration(h, TENANT_A, COMPANY_A);
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_gate", 19);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 19, "gate");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  await armChironDueMarker(h.env.COMPLIANCE_KV, key, 0);
  const before = [...h.compliance.keys()].filter((k) =>
    k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
  );
  assert.ok(before.length >= 1);
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  const after = [...h.compliance.keys()].filter((k) =>
    k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
  );
  assert.ok(after.length >= 1, "gated scope must keep a due marker");
});

test("13. after !done, append arms new rides; a later-enabled company is not hidden", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, 8);
  await finishMigration(h, TENANT_A, COMPANY_A);

  const start = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_append", 200);
  const stop = rideEvent("ride_stop", TENANT_A, COMPANY_A, "street_append", 201);
  const appendedStart = await appendViaEventsApi(h, start);
  const appendedStop = await appendViaEventsApi(h, stop);
  assert.equal(appendedStart.ok, true);
  assert.equal(appendedStop.ok, true);
  const markersAfterAppend = [...h.compliance.keys()].filter(
    (k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
  );
  assert.ok(markersAfterAppend.length >= 2, "append write paths arm due markers");

  const dup = await appendViaEventsApi(h, start);
  assert.equal(dup.ok, true);
  assert.equal(dup.deduplicated, true);

  const tenantC = "T_scan_p1_late";
  const companyC = "C_scan_p1_late";
  const late = rideEvent("ride_start", tenantC, companyC, "street_late", 202);
  const lateKey = eventKeyFor(tenantC, companyC, 202, "late");
  await h.env.COMPLIANCE_KV.put(lateKey, JSON.stringify(late));
  await seedConnection(h, tenantC, companyC);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.ok(h.eventReads().includes(lateKey), "later-enabled company is scanned once");
  assert.ok(summary.migration_done === false || h.eventReads().includes(lateKey));
});

test("14. persist-without-marker is recovered; an invisible marker is not treated as handled", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);
  const event2 = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_invisible", 211);
  const key2 = eventKeyFor(TENANT_A, COMPANY_A, 211, "invisible");
  await h.env.COMPLIANCE_KV.put(key2, JSON.stringify(event2));
  await armChironDueMarker(h.env.COMPLIANCE_KV, key2, NOW_MS + 60_000);
  const beforeKeys = new Set(h.compliance.keys());
  h.resetCounts();
  const idle = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(idle.due_selected, 0);
  assert.ok(h.compliance.has(key2), "authoritative event is never deleted");
  assert.equal(h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY), true);
  for (const name of beforeKeys) {
    if (name.startsWith("compliance_event_v1/")) {
      assert.ok(h.compliance.has(name));
    }
  }
});

test("15. a temporary event-get error does not retire the due marker", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_readerr", 212);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 212, "readerr");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  const markerKey = await armChironDueMarker(h.env.COMPLIANCE_KV, key, 0);
  const origGet = h.env.COMPLIANCE_KV.get.bind(h.env.COMPLIANCE_KV);
  h.env.COMPLIANCE_KV.get = async (name, opts) => {
    if (name === key) throw new Error("kv_temporarily_unavailable");
    return origGet(name, opts);
  };
  const resolved = await _chironResolveDueCandidate(
    h.env,
    { eventKey: key, markerKey },
    NOW_MS,
    null,
  );
  assert.equal(resolved.kind, "read_error");
  assert.ok(h.compliance.has(markerKey), "marker stays until the event is readable");
});

test("16. waiting arrival stays future until due; departure success rearms it", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);
  const start = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_pair", 220);
  const stop = rideEvent("ride_stop", TENANT_A, COMPANY_A, "street_pair", 221);
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, 220, "pair_start");
  const stopKey = eventKeyFor(TENANT_A, COMPANY_A, 221, "pair_stop");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(stopKey, JSON.stringify(stop));
  await _chironWriteExportStatus(
    h.env,
    "status-wait",
    {
      sync_state: "waiting_for_departure",
      last_attempt_at: new Date(NOW_MS).toISOString(),
      official_status: "aankomst",
    },
    { event: stop, eventKey: stopKey, previousStatus: null, nowMs: NOW_MS },
  );
  h.resetCounts();
  const beforeDue = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 60_000,
  });
  assert.equal(beforeDue.due_selected, 0, "waiting due-at is last_attempt + 5 min");

  await _chironWriteExportStatus(
    h.env,
    "status-dep",
    {
      sync_state: "synced",
      official_status: "vertrek",
      last_attempt_at: new Date(NOW_MS).toISOString(),
    },
    { event: start, eventKey: startKey, previousStatus: null, nowMs: NOW_MS },
  );
  const armed = await _chironReArmPairedArrivalAfterDeparture(h.env, start, [
    { key: startKey, event: start },
    { key: stopKey, event: stop },
  ]);
  assert.ok(armed >= 1);
  h.resetCounts();
  const afterDep = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(afterDep.due_selected, 1);
  assert.deepEqual(h.eventReads(), [stopKey]);
});

test("17. scoped migration paginates, resumes after interrupt, and delays !done", async () => {
  const page = CHIRON_SCOPE_DUE_MIGRATION_BATCH;
  const nA = page + 50;
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedConnection(h, TENANT_B, COMPANY_B);
  await seedHistory(h, TENANT_A, COMPANY_A, nA);
  await seedHistory(h, TENANT_B, COMPANY_B, 40);
  h.resetCounts();
  const first = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(first.migration_done, false);
  assert.ok(first.migration_examined <= page * 2);
  assert.ok(first.migration_examined >= 40);
  const midKeys = [...h.compliance.keys()];
  assert.equal(midKeys.includes(CHIRON_RECONCILE_DUE_DONE_KEY), false);

  let done = false;
  let ticks = 1;
  while (!done && ticks < 12) {
    const next = await _chironCronReconcileAllScopesBestEffort(h.env, {
      source: "cron",
      nowMs: NOW_MS + ticks * 60_000,
    });
    done = next.migration_done === true;
    ticks += 1;
  }
  assert.equal(done, true);
  assert.ok(ticks >= 2, "one tick is not enough for A plus B above the page size");
  const eventsAfter = [...h.compliance.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/"),
  );
  assert.equal(eventsAfter.length, nA + 40);
});

test("18. rollback 85f70b04-style write then remigration finds the event", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedHistory(h, TENANT_A, COMPANY_A, 6);
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.equal(h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY), true);

  const oldEvent = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_old_writer", 300);
  const oldKey = eventKeyFor(TENANT_A, COMPANY_A, 300, "old_writer");
  await h.env.COMPLIANCE_KV.put(oldKey, JSON.stringify(oldEvent));

  h.compliance.delete(CHIRON_RECONCILE_DUE_DONE_KEY);
  h.compliance.delete(CHIRON_RECONCILE_DUE_MIGRATION_KEY);
  h.compliance.delete(_chironScopeDueMigrationKey(TENANT_A, COMPANY_A));
  const eventsBefore = [...h.compliance.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/"),
  ).length;

  const remig = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 120_000,
  });
  const eventsAfter = [...h.compliance.keys()].filter((k) =>
    k.startsWith("compliance_event_v1/"),
  ).length;
  assert.equal(eventsAfter, eventsBefore);
  assert.ok(
    remig.due_selected >= 1 ||
      [...h.compliance.keys()].some(
        (k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
      ),
    "remigration rearms the old-writer event without deleting compliance events",
  );
  assert.ok(h.eventReads().includes(oldKey));
});

test("20. recent date prefixes exclude finished same-day history", () => {
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  const prefixes = buildChironRecentDateIndexPrefixes({
    tenantSeg: t,
    companySeg: c,
    fromMs: NOW_MS - 30 * 60 * 1000,
    toMs: NOW_MS,
    digits: 6,
  });
  assert.ok(prefixes.length >= 1);
  assert.ok(prefixes.every((p) => p.includes("/2026/09/21/")));
  assert.ok(prefixes.every((p) => !p.includes("/178000")));
  assert.ok(prefixes.some((p) => p.includes("/178999")));
});

test("21. fault injection: stored event, failed marker, no retry; later cron finds it", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedConnection(h, TENANT_B, COMPANY_B);
  await seedHistory(h, TENANT_A, COMPANY_A, 16);
  await finishMigration(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_B, COMPANY_B);

  const crashAt = NOW_MS - 90_000;
  const crashEvent = rideEvent(
    "ride_start",
    TENANT_A,
    COMPANY_A,
    "street_crash_gap",
    400,
    {
      created_at_utc: new Date(crashAt).toISOString(),
      timestamps: {
        event_at_utc: new Date(crashAt).toISOString(),
        started_at_utc: new Date(crashAt).toISOString(),
      },
    },
  );
  const crashKey = recentDateKey(crashEvent, crashAt);
  await h.env.COMPLIANCE_KV.put(canonicalKeyFor(crashEvent), JSON.stringify(crashEvent));
  await h.env.COMPLIANCE_KV.put(crashKey, JSON.stringify(crashEvent));

  const inflightAt = NOW_MS - 8 * 60_000;
  const inflightEvent = rideEvent(
    "ride_start",
    TENANT_A,
    COMPANY_A,
    "street_cutover_inflight",
    401,
    {
      created_at_utc: new Date(inflightAt).toISOString(),
      timestamps: {
        event_at_utc: new Date(inflightAt).toISOString(),
        started_at_utc: new Date(inflightAt).toISOString(),
      },
    },
  );
  const inflightKey = recentDateKey(inflightEvent, inflightAt);
  await h.env.COMPLIANCE_KV.put(inflightKey, JSON.stringify(inflightEvent));

  const otherAt = NOW_MS - 60_000;
  const otherEvent = rideEvent(
    "ride_start",
    TENANT_B,
    COMPANY_B,
    "street_other_gap",
    402,
    {
      created_at_utc: new Date(otherAt).toISOString(),
      timestamps: {
        event_at_utc: new Date(otherAt).toISOString(),
        started_at_utc: new Date(otherAt).toISOString(),
      },
    },
  );
  const otherKey = recentDateKey(otherEvent, otherAt);
  await h.env.COMPLIANCE_KV.put(otherKey, JSON.stringify(otherEvent));

  const guardEvent = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_dup_guard", 403);
  const guardKey = eventKeyFor(TENANT_A, COMPANY_A, 403, "dup_guard");
  await h.env.COMPLIANCE_KV.put(guardKey, JSON.stringify(guardEvent));
  await h.env.COMPLIANCE_KV.put(
    buildChironExportStatusKey(
      safeSegment(TENANT_A, ""),
      safeSegment(COMPANY_A, ""),
      `candidate_v1:${guardEvent.event_id}`,
    ),
    JSON.stringify({
      sync_state: "synced",
      official_status: "vertrek",
      last_attempt_at: new Date(NOW_MS - 30_000).toISOString(),
    }),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, guardKey, 0);

  const markersBefore = [...h.compliance.keys()].filter(
    (k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
  );
  assert.equal(
    markersBefore.some((k) => (h.compliance.get(k)?.metadata?.ek || "") === crashKey),
    false,
    "crash persist left no due marker",
  );
  assert.equal(
    [...h.compliance.keys()].some((k) => k.startsWith(CHIRON_RECONCILE_WAKEUP_PREFIX)),
    false,
    "no producer wakeup and no append retry",
  );

  h.resetCounts();
  const found = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.ok(found.recovered_unmarked >= 2, "later cron armed the markerless events");
  assert.ok(found.due_selected >= 2, "same cycle processes recovered due-at-0 work");
  assert.ok(h.eventReads().includes(crashKey));
  assert.ok(h.eventReads().includes(inflightKey));
  assert.equal(h.eventReads().includes(otherKey), false, "company B stays isolated this tick");
  assert.equal(
    h.eventReads().some((k) => /_\d{13}_old_\d+$/.test(k)),
    false,
    "finished history is not rescanned",
  );
  assert.ok(h.compliance.has(crashKey));
  assert.ok(h.compliance.has(inflightKey));
  assert.equal(h.listPrefixes.some(isChironFullScopeEventListPrefix), false);

  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  for (const event of [crashEvent, inflightEvent]) {
    await h.env.COMPLIANCE_KV.put(
      buildChironExportStatusKey(t, c, `candidate_v1:${event.event_id}`),
      JSON.stringify({
        sync_state: "synced",
        official_status: "vertrek",
        last_attempt_at: new Date(NOW_MS).toISOString(),
      }),
    );
  }
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 1_000,
  });
  assert.deepEqual(
    providerCalls,
    [],
    "duplicate guard does not submit an already-synced recovered event",
  );
});

test("22. markerless event is found despite >20 newer keys and fresh work each tick", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);

  const oldAt = NOW_MS - 12 * 60_000;
  const { key: oldKey } = await putUnmarkedRecent(h, "street_recover_old", 500, oldAt);
  const newerKeys = [];
  for (let i = 1; i <= CHIRON_DUE_RECOVER_BATCH + 5; i += 1) {
    const at = oldAt + i * 20_000;
    const row = await putUnmarkedRecent(h, `street_recover_newer_${i}`, 500 + i, at);
    newerKeys.push(row.key);
  }
  assert.ok(newerKeys.length > CHIRON_DUE_RECOVER_BATCH);
  assert.equal(hasDueMarkerFor(h, oldKey), false);
  assert.equal(
    [...h.compliance.keys()].some((k) => k.startsWith(CHIRON_RECONCILE_WAKEUP_PREFIX)),
    false,
  );

  let foundAtTick = -1;
  const recoverCosts = [];
  for (let tick = 0; tick < 6; tick += 1) {
    const tickNow = NOW_MS + tick * 60_000;
    const live = await putArmedRecent(
      h,
      `street_recover_live_${tick}`,
      800 + tick,
      tickNow,
    );
    h.resetCounts();
    const summary = await withPinnedNow(tickNow, () =>
      _chironCronReconcileAllScopesBestEffort(h.env, {
        source: "cron",
        nowMs: tickNow,
      }),
    );
    recoverCosts.push({
      tick,
      ...h.snapshot(),
      recovered_unmarked: summary.recovered_unmarked,
      recover_examined: summary.recover_examined,
      due_selected: summary.due_selected,
    });
    assert.ok(
      summary.due_selected >= 1,
      "armed new work still runs while recovery is catching up",
    );
    assert.ok(
      hasDueMarkerFor(h, live.key) || h.eventReads().includes(live.key),
      "normal new work is not blocked by unmarked recovery",
    );
    if (hasDueMarkerFor(h, oldKey) || h.eventReads().includes(oldKey)) {
      foundAtTick = tick;
      break;
    }
  }

  assert.ok(foundAtTick >= 0, "older markerless event is found without remigration");
  assert.equal(h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY), true);
  assert.equal(
    [...h.compliance.keys()].some((k) => k.startsWith(CHIRON_RECONCILE_WAKEUP_PREFIX)),
    false,
    "recovery did not depend on wakeup or producer retry",
  );
  assert.equal(h.listPrefixes.some(isChironFullScopeEventListPrefix), false);
  assert.ok(
    recoverCosts.every((row) => row.recover_examined <= CHIRON_DUE_RECOVER_BATCH),
    "recovery stays bounded per tick",
  );
});

test("23. markerless event survives an interrupt longer than the recover window", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);

  const storedAt = NOW_MS - 12 * 60_000;
  const { key: oldKey } = await putUnmarkedRecent(h, "street_recover_gap", 900, storedAt);
  assert.equal(hasDueMarkerFor(h, oldKey), false);
  assert.equal(
    [...h.compliance.keys()].some((k) => k.startsWith(CHIRON_RECONCILE_WAKEUP_PREFIX)),
    false,
  );
  assert.equal(h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY), true);
  const migKey = _chironScopeDueMigrationKey(TENANT_A, COMPANY_A);
  assert.equal(h.compliance.has(migKey), true);

  const interruptMs =
    CHIRON_DUE_RECOVER_CATCHUP_WINDOW_MS + CHIRON_DUE_RECOVER_WINDOW_MS + 60_000;
  const resumeMs = NOW_MS + interruptMs;
  assert.ok(interruptMs > CHIRON_DUE_RECOVER_CATCHUP_WINDOW_MS);
  assert.ok(interruptMs > CHIRON_DUE_RECOVER_WINDOW_MS);
  assert.ok(resumeMs - storedAt > CHIRON_DUE_RECOVER_CATCHUP_WINDOW_MS);

  let found = false;
  let recovered = 0;
  for (let tick = 0; tick < 8; tick += 1) {
    const tickNow = resumeMs + tick * 60_000;
    h.resetCounts();
    const summary = await withPinnedNow(tickNow, () =>
      _chironCronReconcileAllScopesBestEffort(h.env, {
        source: "cron",
        nowMs: tickNow,
      }),
    );
    recovered += Number(summary.recovered_unmarked) || 0;
    if (hasDueMarkerFor(h, oldKey) || h.eventReads().includes(oldKey)) {
      found = true;
      break;
    }
  }

  assert.equal(found, true, "event is found after the window-long interrupt");
  assert.ok(recovered >= 1);
  assert.equal(h.compliance.has(CHIRON_RECONCILE_DUE_DONE_KEY), true);
  assert.equal(h.compliance.has(migKey), true);
  assert.equal(h.compliance.has(CHIRON_RECONCILE_DUE_MIGRATION_KEY), true);
  assert.equal(h.listPrefixes.some(isChironFullScopeEventListPrefix), false);
});

test("24. idle after caught-up recover parks retryable leftovers and stops event reads", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await finishMigration(h, TENANT_A, COMPANY_A);
  const recoverKey = buildChironScopeRecoverKey(
    safeSegment(TENANT_A, ""),
    safeSegment(COMPANY_A, ""),
  );
  await h.env.COMPLIANCE_KV.put(
    recoverKey,
    JSON.stringify({
      version: CHIRON_DUE_RECOVER_STATE_VERSION,
      from_ms: NOW_MS,
      last_key: null,
      prefix: null,
      cursor: null,
    }),
  );
  const retryable = rideEvent("ride_start", TENANT_A, COMPANY_A, "idle_retry", 900);
  const retryKey = eventKeyFor(TENANT_A, COMPANY_A, 900, "idle_retry");
  await h.env.COMPLIANCE_KV.put(retryKey, JSON.stringify(retryable));
  await h.env.COMPLIANCE_KV.put(
    buildChironExportStatusKey(
      safeSegment(TENANT_A, ""),
      safeSegment(COMPANY_A, ""),
      `candidate_v1:${retryable.event_id}`,
    ),
    JSON.stringify({
      sync_state: "retryable_failed",
      failure_kind: "retryable",
      last_attempt_at: new Date(NOW_MS - 60_000).toISOString(),
    }),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, retryKey, 0);

  h.resetCounts();
  const first = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(first.due_selected, 0, "fresh retryable is re-armed to the future");
  assert.equal(first.recover_examined, 0);
  assert.ok(h.eventReads().includes(retryKey));

  h.resetCounts();
  const second = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS + 60_000,
  });
  assert.equal(second.due_selected, 0);
  assert.equal(second.recover_examined, 0);
  assert.equal(h.eventReads().length, 0, "idle tick must not re-read parked events");
  assert.ok(second.reads === undefined || h.counts.valueReads < 20);
  assert.equal(h.listPrefixes.some(isChironFullScopeEventListPrefix), false);
});
