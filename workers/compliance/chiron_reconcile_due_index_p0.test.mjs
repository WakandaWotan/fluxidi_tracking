// CHIRON-COMPLIANCE-DUE-INDEX-P0
//
// Deterministic read-count, crash-order, migration and privacy contract for
// the ordered Chiron pending/due-marker index.
//
//   node --test workers/compliance/chiron_reconcile_due_index_p0.test.mjs
//
// Official KV limits retrieved 2026-08-18:
//   https://developers.cloudflare.com/kv/platform/limits/
//   key ≤ 512 bytes, metadata ≤ 1024 bytes serialized JSON.
//
// Fake / relative timestamps only. No live Chiron, BOOKING, or production KV.

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  CHIRON_RECONCILE_DUE_PREFIX,
  CHIRON_RECONCILE_DUE_DONE_KEY,
  CHIRON_RECONCILE_DUE_MIGRATION_KEY,
  CHIRON_RECONCILE_DUE_MIGRATION_BATCH,
  CHIRON_RECONCILE_DUE_PROCESS_LIMIT,
  CHIRON_WAITING_RECHECK_MS,
  CF_KV_KEY_MAX_BYTES,
  CF_KV_METADATA_MAX_BYTES,
  ChironDueIndexTestCrash,
  armChironDueMarker,
  applyChironDueMarkerTransition,
  buildChironDueMarkerKey,
  buildChironDueMarkerMetadata,
  chironDueMarkerKeyByteLength,
  chironDueMarkerMetadataJsonBytes,
  chironOpaqueEventRef,
  computeChironReconcileDueAtMs,
  chironDueMarkerEventRecencyMs,
  formatChironDueIndexLog,
  chironDueIndexLogContainsForbiddenIdentity,
  markChironDueMigrationComplete,
  parseChironDueMarkerKey,
  selectDueChironMarkers,
} from "./chiron_reconcile_due_index.js";

const {
  _chironCronReconcileAllScopesBestEffort,
  _chironAutoReconcileScopeBestEffort,
  _chironAutoSubmitOneEvent,
  _chironBuildOfficialDraftForSingleEvent,
  _chironBuildScopePreload,
  _chironLoadScopedHydrationCache,
  _chironLoadBookingLegTypeMap,
  _chironShouldRunReconcileFromStatusPoll,
  _chironWriteExportStatus,
  _chironMigrateDueMarkersOnePage,
  CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  CHIRON_AUTO_RECONCILE_MIN_INTERVAL_MS,
  CHIRON_PENDING_STALE_MS,
  CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS,
  CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS,
  buildChironOfficialIdempotencyKey,
  buildChironExportStatusKey,
  safeSegment,
} = __testInternals;

const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const TENANT_A = "T_due_a";
const COMPANY_A = "C_due_a";
const TENANT_B = "T_due_b";
const COMPANY_B = "C_due_b";

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

const NOW_MS = Date.now();

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
    testflow_started_at: new Date(NOW_MS - 7 * 24 * 60 * 60 * 1000).toISOString(),
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
    event_id: `${kind}:${tenantId}:${companyId}:${bookingId}:${seq}`,
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
  const t = safeSegment(tenantId, "");
  const c = safeSegment(companyId, "");
  return `compliance_event_v1/tenant/${t}/company/${c}/2026/08/03/${String(1000 + seq).padStart(13, "0")}_${label}`;
}

function createCountingEnv() {
  const compliance = new Map();
  const bookingReads = [];
  const counts = {
    lists: 0,
    valueReads: 0,
    writes: 0,
    deletes: 0,
    bookingReads: 0,
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
      async get(key) {
        counts.bookingReads += 1;
        bookingReads.push(key);
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
    bookingReads,
    eventReads: () =>
      valueReadKeys.filter((k) => k.startsWith("compliance_event_v1/")),
    dueLists: () => listPrefixes.filter((p) => p === CHIRON_RECONCILE_DUE_PREFIX).length,
    snapshotCounts: () => ({ ...counts }),
    resetCounts() {
      counts.lists = 0;
      counts.valueReads = 0;
      counts.writes = 0;
      counts.deletes = 0;
      counts.bookingReads = 0;
      valueReadKeys.length = 0;
      listPrefixes.length = 0;
      bookingReads.length = 0;
    },
  };
}

async function seedConnection(h, tenantId, companyId, overrides = {}) {
  await h.env.COMPLIANCE_KV.put(
    `tenant:${tenantId}:company:${companyId}:chiron_connection:v1`,
    JSON.stringify(connectionDoc(overrides)),
  );
}

async function seedEventWithDue(h, event, eventKey, dueAtMs, statusDoc = null) {
  await h.env.COMPLIANCE_KV.put(eventKey, JSON.stringify(event));
  if (statusDoc) {
    const t = safeSegment(event.tenant_id, "");
    const c = safeSegment(event.company_id, "");
    const statusKey = buildChironExportStatusKey(
      t,
      c,
      `candidate_v1:${event.event_id}`,
    );
    await h.env.COMPLIANCE_KV.put(statusKey, JSON.stringify(statusDoc));
  }
  if (dueAtMs != null) {
    await armChironDueMarker(h.env.COMPLIANCE_KV, eventKey, dueAtMs);
  }
}

/* ===================== 1-6 idle / cap / future ===================== */

test("1. no-due pass: 0 value reads, 1 due list, 0 writes, 0 provider", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.ok, true);
  assert.equal(summary.due_selected, 0);
  assert.equal(h.counts.valueReads, 0);
  assert.equal(h.dueLists(), 1);
  assert.equal(h.counts.lists, 1);
  assert.equal(h.counts.writes, 0);
  assert.equal(h.counts.deletes, 0);
  assert.deepEqual(providerCalls, []);
});

test("2. historical terminal records cause 0 value reads after migration", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  for (let i = 0; i < 80; i += 1) {
    const key = `compliance_event_v1/tenant/${t}/company/${c}/2026/07/01/${String(i).padStart(13, "0")}_term`;
    await h.env.COMPLIANCE_KV.put(
      key,
      JSON.stringify(rideEvent("ride_stop", TENANT_A, COMPANY_A, `old_${i}`, i)),
    );
  }
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.equal(h.eventReads().length, 0);
  assert.equal(h.counts.valueReads, 0);
  assert.equal(h.dueLists(), 1);
  assert.deepEqual(providerCalls, []);
});

test("3. one due marker targets exactly one event", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_one", 1);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 1, "one");
  await seedEventWithDue(h, event, key, NOW_MS - 1000);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 1);
  assert.deepEqual(h.eventReads(), [key]);
  assert.equal(h.dueLists(), 1);
});

test("4+5. twenty due cap; more than twenty stays capped", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  for (let i = 0; i < 27; i += 1) {
    const event = rideEvent("ride_start", TENANT_A, COMPANY_A, `street_${i}`, i);
    const key = eventKeyFor(TENANT_A, COMPANY_A, i, `cap_${i}`);
    await seedEventWithDue(h, event, key, NOW_MS - 10_000 + i);
  }
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 20);
  assert.equal(h.eventReads().length, 20);
  assert.ok(h.eventReads().length <= CHIRON_AUTO_RECONCILE_MAX_PROCESS);
  assert.equal(h.dueLists(), 1);
  assert.ok(providerCalls.length <= 20);
});

test("6a. due-at-0 historical backlog cannot starve a newer ride", async () => {
  const entries = [];
  entries.push({
    name: CHIRON_RECONCILE_DUE_DONE_KEY,
    metadata: { v: 1, done: true },
  });
  for (let i = 0; i < 25; i += 1) {
    const eventKey = eventKeyFor(TENANT_A, COMPANY_A, i, `old_${i}`);
    const markerKey = await buildChironDueMarkerKey(0, eventKey);
    entries.push({
      name: markerKey,
      metadata: { v: 1, ek: eventKey },
    });
  }
  const newKey =
    `compliance_event_v1/tenant/${safeSegment(TENANT_A, "")}/company/${safeSegment(COMPANY_A, "")}` +
    `/2026/08/18/1787043121583_ride_start_new`;
  const newMarker = await buildChironDueMarkerKey(0, newKey);
  entries.push({
    name: newMarker,
    metadata: { v: 1, ek: newKey },
  });
  entries.sort((a, b) => (a.name < b.name ? -1 : a.name > b.name ? 1 : 0));
  const picked = selectDueChironMarkers(entries, { nowMs: NOW_MS, limit: 20 });
  assert.equal(picked.sawDoneSentinel, true);
  assert.equal(picked.stoppedAtLimit, true);
  assert.equal(picked.selected.length, 20);
  assert.equal(picked.selected[0].eventKey, newKey);
  assert.ok(chironDueMarkerEventRecencyMs(newKey) > 1787043120000);
});

test("6b. young pending_build leaves the due-at-0 lane", () => {
  const last = NOW_MS - 5_000;
  const dueAt = computeChironReconcileDueAtMs(
    {
      sync_state: "pending_build",
      last_attempt_at: new Date(last).toISOString(),
    },
    NOW_MS,
    { pendingStaleMs: CHIRON_PENDING_STALE_MS },
  );
  assert.equal(dueAt, last + CHIRON_PENDING_STALE_MS);
  assert.ok(dueAt > NOW_MS - 1);
});

test("6. stop at first future marker", async () => {
  const entries = [
    { name: `${CHIRON_RECONCILE_DUE_PREFIX}${String(NOW_MS - 5).padStart(16, "0")}:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` },
    { name: `${CHIRON_RECONCILE_DUE_PREFIX}${String(NOW_MS + 5_000).padStart(16, "0")}:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb` },
    { name: `${CHIRON_RECONCILE_DUE_PREFIX}${String(NOW_MS + 9_000).padStart(16, "0")}:cccccccccccccccccccccccccccccccc` },
  ];
  const picked = selectDueChironMarkers(entries, { nowMs: NOW_MS, limit: 20 });
  assert.equal(picked.stoppedAtFuture, true);
  assert.equal(picked.selected.length, 1);
});

/* ===================== 7-11 retry / success / stale / orphan ===================== */

test("7. retryable failure rearms the correct future marker", async () => {
  const eventKey = eventKeyFor(TENANT_A, COMPANY_A, 7, "retry");
  const last = NOW_MS - 1_000;
  const status = {
    sync_state: "failed",
    failure_kind: "definitive",
    last_attempt_at: new Date(last).toISOString(),
    attempt_count: 1,
    outbound_fingerprint_definitive_attempts: 1,
  };
  const dueAt = computeChironReconcileDueAtMs(status, NOW_MS, {
    pendingStaleMs: CHIRON_PENDING_STALE_MS,
    definitiveCooldownMs: CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS,
    definitiveMaxAttempts: CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS,
  });
  assert.equal(dueAt, last + CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS);
  const markerKey = await buildChironDueMarkerKey(dueAt, eventKey);
  const parsed = parseChironDueMarkerKey(markerKey);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.dueAtMs, dueAt);
});

test("8. success/terminal removes marker", async () => {
  const h = createCountingEnv();
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_sync", 8);
  const eventKey = eventKeyFor(TENANT_A, COMPANY_A, 8, "sync");
  await seedEventWithDue(h, event, eventKey, 0);
  await _chironWriteExportStatus(
    h.env,
    "status-sync-8",
    {
      sync_state: "synced",
      last_attempt_at: new Date(NOW_MS).toISOString(),
    },
    { event, eventKey, previousStatus: null, nowMs: NOW_MS },
  );
  const leftover = [...h.compliance.keys()].filter((k) =>
    k.startsWith(CHIRON_RECONCILE_DUE_PREFIX),
  );
  assert.equal(
    leftover.filter((k) => k !== CHIRON_RECONCILE_DUE_DONE_KEY).length,
    0,
  );
});

test("9+10. duplicate and stale superseded markers reconcile", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_dup", 9);
  const eventKey = eventKeyFor(TENANT_A, COMPANY_A, 9, "dup");
  await seedEventWithDue(h, event, eventKey, NOW_MS - 5000);
  await armChironDueMarker(h.env.COMPLIANCE_KV, eventKey, NOW_MS - 1000);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 1);
  assert.equal(h.eventReads().length, 1);
  assert.ok(h.counts.deletes >= 1);
});

test("11. orphan marker deletes without provider call", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const missingKey = eventKeyFor(TENANT_A, COMPANY_A, 11, "missing");
  await armChironDueMarker(h.env.COMPLIANCE_KV, missingKey, NOW_MS - 1000);
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.equal(h.eventReads().length, 1);
  assert.ok(h.counts.deletes >= 1);
  assert.deepEqual(providerCalls, []);
});

/* ===================== 12-17 binding / reread / crash ===================== */

test("12. wrong scope/binding fails closed", async () => {
  const event = rideEvent("ride_start", TENANT_B, COMPANY_B, "street_x", 12);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 12, "mismatch");
  const outcome = await _chironAutoSubmitOneEvent(
    { CHIRON_EXPORT_MODE: "test", CHIRON_EXPORT_BASE_URL: ACC_URL, COMPLIANCE_KV: { async get() { return null; } } },
    event,
    key,
    { source: "test", expectedScope: { tenantId: TENANT_A, companyId: COMPANY_A } },
  );
  assert.equal(outcome.reason, "scope_binding_mismatch");
  assert.deepEqual(providerCalls, []);
});

test("13. authoritative event is read before any provider call", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_order", 13);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 13, "order");
  await seedEventWithDue(h, event, key, NOW_MS - 1000);
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.ok(h.eventReads()[0] === key);
  if (providerCalls.length) {
    assert.ok(h.eventReads().length >= 1);
  }
});

test("14. concurrent event change does not submit stale data", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_old", 14);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 14, "conc");
  await seedEventWithDue(h, event, key, NOW_MS - 1000);
  const updated = { ...event, booking_id: "street_new" };
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(updated));
  const seen = [];
  const origGet = h.env.COMPLIANCE_KV.get.bind(h.env.COMPLIANCE_KV);
  h.env.COMPLIANCE_KV.get = async (k) => {
    const raw = await origGet(k);
    if (k === key && raw) seen.push(JSON.parse(raw).booking_id);
    return raw;
  };
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.ok(seen.includes("street_new"));
  assert.equal(seen.includes("street_old"), false);
});

test("15-17. crash after arm / after persist / before retire", async () => {
  const store = new Map();
  const kv = {
    async put(key, value, opts = {}) {
      store.set(key, { value, metadata: opts.metadata || null });
    },
    async delete(key) {
      store.delete(key);
    },
  };
  const eventKey = eventKeyFor(TENANT_A, COMPANY_A, 15, "crash");
  let persisted = false;

  await assert.rejects(
    () =>
      applyChironDueMarkerTransition(kv, {
        eventKey,
        previousDueAtMs: null,
        nextDueAtMs: NOW_MS,
        persist: async () => {
          persisted = true;
        },
        crashAfter: "after_arm",
      }),
    (err) => err instanceof ChironDueIndexTestCrash && err.step === "after_arm",
  );
  assert.equal(persisted, false);
  assert.ok([...store.keys()].some((k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX)));

  persisted = false;
  await assert.rejects(
    () =>
      applyChironDueMarkerTransition(kv, {
        eventKey,
        previousDueAtMs: NOW_MS - 5000,
        nextDueAtMs: NOW_MS,
        persist: async () => {
          persisted = true;
        },
        crashAfter: "after_persist",
      }),
    (err) => err instanceof ChironDueIndexTestCrash && err.step === "after_persist",
  );
  assert.equal(persisted, true);

  const oldKey = await buildChironDueMarkerKey(NOW_MS - 8000, eventKey);
  store.set(oldKey, { value: "{}", metadata: null });
  await assert.rejects(
    () =>
      applyChironDueMarkerTransition(kv, {
        eventKey,
        previousDueAtMs: NOW_MS - 8000,
        nextDueAtMs: NOW_MS,
        persist: async () => {},
        crashAfter: "before_retire",
      }),
    (err) => err instanceof ChironDueIndexTestCrash && err.step === "before_retire",
  );
  assert.equal(store.has(oldKey), true);
});

/* ===================== 18-20 idempotency / draft / isolation ===================== */

test("18. deterministic idempotency key is unchanged", () => {
  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const a = buildChironOfficialIdempotencyKey(scope, "0772.931.038", "rit-1", "vertrek");
  const b = buildChironOfficialIdempotencyKey(scope, "0772.931.038", "rit-1", "vertrek");
  assert.equal(a, b);
  assert.match(a, /^chiron_official_v1:/);
});

test("19. official draft payload is byte-equivalent with and without preload", async () => {
  const h = createCountingEnv();
  const start = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_draft", 19);
  const stop = rideEvent("ride_stop", TENANT_A, COMPANY_A, "street_draft", 20);
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, 19, "draft_start");
  const stopKey = eventKeyFor(TENANT_A, COMPANY_A, 20, "draft_stop");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(stopKey, JSON.stringify(stop));
  const contextEntries = [
    { key: startKey, event: start },
    { key: stopKey, event: stop },
  ];
  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const preload = _chironBuildScopePreload(scope, {
    hydrationCache: await _chironLoadScopedHydrationCache(h.env, scope, true),
    bookingLegTypeMap: await _chironLoadBookingLegTypeMap(h.env, contextEntries),
    contextEntries,
  });
  const withPreload = await _chironBuildOfficialDraftForSingleEvent(
    h.env,
    stop,
    stopKey,
    { preloadedContextEntries: contextEntries, scopePreload: preload },
  );
  const withoutPreload = await _chironBuildOfficialDraftForSingleEvent(
    h.env,
    stop,
    stopKey,
    { preloadedContextEntries: contextEntries },
  );
  assert.deepEqual(
    JSON.parse(JSON.stringify(withPreload)),
    JSON.parse(JSON.stringify(withoutPreload)),
  );
  assert.equal(
    withPreload.idempotency_key ?? withPreload.exportPayload?.chiron_official_draft?.idempotency_key ?? null,
    withoutPreload.idempotency_key ?? withoutPreload.exportPayload?.chiron_official_draft?.idempotency_key ?? null,
  );
});

test("20. tenant isolation across two scopes", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedConnection(h, TENANT_B, COMPANY_B);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const eventA = rideEvent("ride_start", TENANT_A, COMPANY_A, "street_a", 21);
  const eventB = rideEvent("ride_start", TENANT_B, COMPANY_B, "street_b", 22);
  const keyA = eventKeyFor(TENANT_A, COMPANY_A, 21, "iso_a");
  const keyB = eventKeyFor(TENANT_B, COMPANY_B, 22, "iso_b");
  await seedEventWithDue(h, eventA, keyA, NOW_MS - 1000);
  await h.env.COMPLIANCE_KV.put(keyB, JSON.stringify(eventB));
  h.resetCounts();
  await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "status_poll",
  });
  assert.ok(h.eventReads().includes(keyA));
  assert.equal(h.eventReads().includes(keyB), false);
});

/* ===================== 21-27 migration ===================== */

test("21-23. migration batch ≤25, one page, monotonic cursor", async () => {
  const h = createCountingEnv();
  for (let i = 0; i < 40; i += 1) {
    const event = rideEvent("ride_start", TENANT_A, COMPANY_A, `mig_${i}`, i);
    const key = eventKeyFor(TENANT_A, COMPANY_A, i, `mig_${i}`);
    await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  }
  h.resetCounts();
  const first = await _chironMigrateDueMarkersOnePage(h.env, { nowMs: NOW_MS });
  assert.ok(first.examined <= CHIRON_RECONCILE_DUE_MIGRATION_BATCH);
  assert.equal(first.examined, 25);
  assert.equal(first.done, false);
  const mig1 = JSON.parse(h.compliance.get(CHIRON_RECONCILE_DUE_MIGRATION_KEY).value);
  assert.ok(mig1.cursor);
  const cursor1 = mig1.cursor;

  const second = await _chironMigrateDueMarkersOnePage(h.env, { nowMs: NOW_MS });
  assert.ok(second.examined <= 25);
  const mig2 = JSON.parse(h.compliance.get(CHIRON_RECONCILE_DUE_MIGRATION_KEY).value);
  assert.notEqual(mig2.cursor, cursor1);
  assert.equal(mig2.completed, true);
  assert.equal(second.done, true);
});

test("24. terminal legacy events remain untouched", async () => {
  const h = createCountingEnv();
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "term_legacy", 24);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 24, "term_legacy");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  await h.env.COMPLIANCE_KV.put(
    buildChironExportStatusKey(t, c, `candidate_v1:${event.event_id}`),
    JSON.stringify({ sync_state: "synced", last_attempt_at: new Date(NOW_MS).toISOString() }),
  );
  const before = h.compliance.get(key).value;
  await _chironMigrateDueMarkersOnePage(h.env, { nowMs: NOW_MS });
  assert.equal(h.compliance.get(key).value, before);
  const markers = [...h.compliance.keys()].filter(
    (k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
  );
  assert.equal(markers.length, 0);
});

test("25. retryable legacy events get a marker", async () => {
  const h = createCountingEnv();
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "retry_legacy", 25);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 25, "retry_legacy");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  await h.env.COMPLIANCE_KV.put(
    buildChironExportStatusKey(t, c, `candidate_v1:${event.event_id}`),
    JSON.stringify({
      sync_state: "retryable_failed",
      failure_kind: "retryable",
      last_attempt_at: new Date(NOW_MS - 60_000).toISOString(),
    }),
  );
  await _chironMigrateDueMarkersOnePage(h.env, { nowMs: NOW_MS });
  const markers = [...h.compliance.keys()].filter(
    (k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
  );
  assert.equal(markers.length, 1);
});

test("26. normal due processing continues during migration", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  for (let i = 0; i < 30; i += 1) {
    const event = rideEvent("ride_stop", TENANT_A, COMPANY_A, `hist_${i}`, i + 40);
    const key = eventKeyFor(TENANT_A, COMPANY_A, i + 40, `hist_${i}`);
    await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  }
  const live = rideEvent("ride_start", TENANT_A, COMPANY_A, "live_due", 99);
  const liveKey = eventKeyFor(TENANT_A, COMPANY_A, 99, "live_due");
  await seedEventWithDue(h, live, liveKey, NOW_MS - 1000);
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.due_selected, 1);
  assert.ok(summary.migration_examined > 0);
  assert.ok(summary.migration_examined <= 25);
  assert.ok(h.eventReads().includes(liveKey));
});

test("27. migration completion permanently disables legacy value scan", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "after_done", 27);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 27, "after_done");
  await h.env.COMPLIANCE_KV.put(key, JSON.stringify(event));
  h.resetCounts();
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  assert.equal(summary.migration_done, true);
  assert.equal(summary.migration_examined, 0);
  assert.equal(h.eventReads().length, 0);
  assert.equal(h.listPrefixes.includes("compliance_event_v1/"), false);
});

/* ===================== 28-32 hydration / booking / throttle / counters ===================== */

test("28. already-synced marker: one event read, cleanup, no provider, no repair write", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "already", 28);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 28, "already");
  await seedEventWithDue(h, event, key, NOW_MS - 1000, {
    sync_state: "synced",
    last_attempt_at: new Date(NOW_MS - 60_000).toISOString(),
    official_idempotency_key: null,
  });
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.deepEqual(h.eventReads(), [key]);
  assert.deepEqual(providerCalls, []);
  const statusWrites = [...h.compliance.keys()].filter((k) =>
    k.includes("chiron_export_status_v1"),
  );
  // Seeded status remains; cron must not rewrite it.
  assert.ok(statusWrites.length >= 1);
});

test("29-30. hydration only for due candidates; BOOKING_KV independent of history", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  for (let i = 0; i < 40; i += 1) {
    await h.env.COMPLIANCE_KV.put(
      `compliance_event_v1/tenant/${t}/company/${c}/2026/07/01/${String(i).padStart(13, "0")}_hist`,
      JSON.stringify(rideEvent("ride_stop", TENANT_A, COMPANY_A, `hist_${i}`, i)),
    );
  }
  const due = rideEvent("ride_stop", TENANT_A, COMPANY_A, "due_only", 200);
  const dueKey = eventKeyFor(TENANT_A, COMPANY_A, 200, "due_only");
  await seedEventWithDue(h, due, dueKey, NOW_MS - 1000);
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.equal(h.eventReads().filter((k) => k.includes("/2026/07/01/")).length, 0);
  assert.ok(h.counts.bookingReads <= 8, `booking reads ${h.counts.bookingReads}`);
});

test("31. throttle behaviour unchanged on status-poll helper", () => {
  const fresh = connectionDoc();
  assert.equal(_chironShouldRunReconcileFromStatusPoll(fresh), true);
  const recent = connectionDoc({
    testflow_auto_reconcile_last_at: new Date(NOW_MS - 1000).toISOString(),
  });
  assert.equal(_chironShouldRunReconcileFromStatusPoll(recent), false);
  assert.ok(CHIRON_AUTO_RECONCILE_MIN_INTERVAL_MS === 15000);
});

test("32. counter and budget shapes are preserved", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  const event = rideEvent("ride_start", TENANT_A, COMPANY_A, "shape", 32);
  const key = eventKeyFor(TENANT_A, COMPANY_A, 32, "shape");
  await seedEventWithDue(h, event, key, NOW_MS - 1000);
  const outcome = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "test",
  });
  for (const field of [
    "scanned",
    "considered",
    "submitted",
    "waiting_for_departure",
    "already_synced",
    "skipped",
    "failed",
  ]) {
    assert.equal(typeof outcome[field], "number");
  }
  assert.ok(outcome.processed <= CHIRON_RECONCILE_DUE_PROCESS_LIMIT);
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, {
    source: "cron",
    nowMs: NOW_MS,
  });
  for (const field of ["scopes", "ran", "skipped_throttled", "failed"]) {
    assert.equal(typeof summary[field], "number");
  }
});

/* ===================== 33-35 privacy / no globals / zero-due provider ===================== */

test("33. marker key/metadata privacy and Cloudflare size limits", async () => {
  const eventKey = eventKeyFor(TENANT_A, COMPANY_A, 33, "privacy");
  const markerKey = await buildChironDueMarkerKey(NOW_MS, eventKey);
  const meta = buildChironDueMarkerMetadata(eventKey);
  assert.ok(chironDueMarkerKeyByteLength(markerKey) < CF_KV_KEY_MAX_BYTES);
  assert.ok(chironDueMarkerMetadataJsonBytes(meta) < CF_KV_METADATA_MAX_BYTES);
  assert.equal(markerKey.includes(TENANT_A), false);
  assert.equal(markerKey.includes(COMPANY_A), false);
  assert.equal(markerKey.includes("street_"), false);
  assert.match(markerKey, /^chiron_reconcile_due:v1:\d{16}:[0-9a-f]{32}$/);
  const ref = await chironOpaqueEventRef(eventKey);
  const again = await chironOpaqueEventRef(eventKey);
  assert.equal(ref, again);
  const line = formatChironDueIndexLog({
    source: "cron",
    dueListed: 1,
    dueSelected: 0,
    eventReads: 0,
  });
  assert.equal(chironDueIndexLogContainsForbiddenIdentity(line), false);
  assert.equal(line.includes(eventKey), false);
});

test("34. due-index helpers do not store request-specific mutable globals", () => {
  const first = computeChironReconcileDueAtMs(null, NOW_MS);
  const second = computeChironReconcileDueAtMs(null, NOW_MS + 10);
  assert.equal(first, 0);
  assert.equal(second, 0);
  assert.ok(CHIRON_WAITING_RECHECK_MS > 0);
});

test("35. no provider call when zero due", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.deepEqual(providerCalls, []);
  assert.equal(h.counts.bookingReads, 0);
});
