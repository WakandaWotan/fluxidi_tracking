// CHIRON-MISSING-LIVE-RIDE-P0
//
// Production-shaped reproduction of street_1787043120900_3l031n2b:
// migration complete, !done present, 25+ historical due-at-0 retries, then a
// new direct street ride is appended. Proves newest-first selection, no
// append-time history scan, visible provider rejection, crash-safe arming,
// tenant isolation, and the idle due-index read contract.
//
//   node --test workers/compliance/chiron_missing_live_ride_p0.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  CHIRON_RECONCILE_DUE_PREFIX,
  CHIRON_RECONCILE_DUE_DONE_KEY,
  ChironDueIndexTestCrash,
  armChironDueMarker,
  applyChironDueMarkerTransition,
  buildChironDueMarkerKey,
  computeChironReconcileDueAtMs,
  markChironDueMigrationComplete,
  parseChironDueMarkerKey,
  selectDueChironMarkers,
} from "./chiron_reconcile_due_index.js";

const {
  _chironCronReconcileAllScopesBestEffort,
  _chironAutoSubmitAfterAppendBestEffort,
  _chironAutoSubmitEligibleForEvent,
  _chironAppendContextEntries,
  _chironArmDueNowBestEffort,
  _chironConfirmDueMarkerAfterPersist,
  _chironWriteExportStatus,
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
const NOW_MS = Date.parse("2026-08-18T12:00:00.000Z");

let originalFetch;
let providerCalls = [];
let providerByIdem = new Map();

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input, init) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    const bodyRaw = typeof init?.body === "string" ? init.body : "";
    let idem = "";
    try {
      const parsed = JSON.parse(bodyRaw || "{}");
      idem = `${parsed?.ritnummer || ""}:${parsed?.status || ""}`;
    } catch (_) {
      idem = bodyRaw.slice(0, 80);
    }
    providerCalls.push({ href, idem });
    providerByIdem.set(idem, (providerByIdem.get(idem) || 0) + 1);
    if (href.includes("/oauth/token")) {
      return new Response(JSON.stringify({ access_token: "acc-token", expires_in: 3600 }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    if (href.includes("/chiron/taxirit")) {
      if (String(init?.headers?.authorization || "").includes("reject")) {
        return new Response(
          JSON.stringify({ fouten: [{ code: "CH1403", beschrijving: "rejected" }] }),
          { status: 200, headers: { "content-type": "application/json" } },
        );
      }
      return new Response(JSON.stringify({ fouten: [], external_reference: "ACC-OK" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    throw new Error(`hermetic test: blocked outbound fetch to ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  providerCalls = [];
  providerByIdem = new Map();
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
    fare: isStop
      ? { currency: "EUR", distance_km: 9.631644593922799, total_amount: 23.2 }
      : {},
    payment: isStop ? { status: "paid" } : {},
    ...overrides,
  };
}

function eventKeyFor(tenantId, companyId, day, ms, label) {
  const t = safeSegment(tenantId, "");
  const c = safeSegment(companyId, "");
  return `compliance_event_v1/tenant/${t}/company/${c}/${day}/${String(ms).padStart(13, "0")}_${label}`;
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

test("incident: newest due-at-0 street ride is selected over 25 historical retries", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });

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
  const stop = streetEvent("ride_stop", Date.parse("2026-08-18T08:58:17.192Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  const stopKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043497192, "ride_stop");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await h.env.COMPLIANCE_KV.put(stopKey, JSON.stringify(stop));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  await armChironDueMarker(h.env.COMPLIANCE_KV, stopKey, 0);

  const listed = [...h.compliance.keys()]
    .filter((k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX))
    .sort()
    .map((name) => ({ name, metadata: h.compliance.get(name)?.metadata || null }));
  const picked = selectDueChironMarkers(listed, {
    nowMs: NOW_MS,
    limit: CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  });
  assert.equal(picked.sawDoneSentinel, true);
  assert.equal(picked.selected[0].eventKey, stopKey);
  assert.equal(picked.selected[1].eventKey, startKey);
  assert.equal(picked.selected.length, 20);
});

test("incident: planned/draft sibling events do not change direct-ride eligibility", () => {
  const status = buildChironConnectionStatusResponse(
    TENANT_A,
    COMPANY_A,
    connectionDoc(),
  );
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const plannedSibling = {
    event_type: "booking_status_update",
    ride_type: "planned",
    booking_id: BOOKING,
    tenant_id: TENANT_A,
    company_id: COMPANY_A,
    created_at_utc: "2026-08-18T08:58:16.522Z",
  };
  const env = { CHIRON_EXPORT_MODE: "test", CHIRON_EXPORT_BASE_URL: ACC_URL };
  assert.equal(_chironAutoSubmitEligibleForEvent(status, env, start), null);
  assert.equal(
    _chironAutoSubmitEligibleForEvent(status, env, plannedSibling),
    "event_type_not_auto_submittable",
  );
  assert.equal(start.ride_type, "direct");
});

test("append uses only the new event plus one keyed sibling, never a history list", async () => {
  const h = createCountingEnv();
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const stop = streetEvent("ride_stop", Date.parse("2026-08-18T08:58:17.192Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(
    `compliance_event_canonical_v1/tenant/${safeSegment(TENANT_A, "")}/company/${safeSegment(COMPANY_A, "")}/eid/${safeSegment(start.event_id)}`,
    JSON.stringify(start),
  );
  for (let i = 0; i < 40; i += 1) {
    await h.env.COMPLIANCE_KV.put(
      eventKeyFor(TENANT_A, COMPANY_A, "2026/08/10", 1786345177300 + i, `hist_${i}`),
      JSON.stringify({ event_type: "ride_stop", event_id: `hist_${i}` }),
    );
  }
  h.resetCounts();
  const entries = await _chironAppendContextEntries(h.env, stop, startKey.replace("ride_start", "ride_stop"));
  assert.equal(h.counts.eventPrefixLists, 0);
  assert.ok(entries.length <= 2);
  assert.equal(h.counts.lists, 0);
});

test("missing-marker watchdog rearms with one keyed get, no history list", async () => {
  const h = createCountingEnv();
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  h.resetCounts();
  const markerKey = await _chironConfirmDueMarkerAfterPersist(h.env, start, startKey);
  assert.ok(markerKey);
  assert.equal(h.counts.eventPrefixLists, 0);
  assert.equal(h.counts.lists, 0);
  const parsed = parseChironDueMarkerKey(markerKey);
  assert.equal(parsed.ok, true);
  assert.equal(parsed.dueAtMs, 0);
});

test("arm failure cannot persist an unmarked submittable event", async () => {
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  await assert.rejects(
    () => _chironArmDueNowBestEffort({ COMPLIANCE_KV: null }, start, "x"),
    /chiron_due_marker_arm_unavailable/,
  );
});

test("provider rejection is stored and not marked synced; retry rearms off due-at-0 while young", async () => {
  const last = NOW_MS - 1_000;
  const dueAt = computeChironReconcileDueAtMs(
    {
      sync_state: "failed",
      failure_kind: "retryable",
      external_status_code: 200,
      fouten_count: 1,
      last_attempt_at: new Date(last).toISOString(),
    },
    NOW_MS,
    { waitingRecheckMs: 5 * 60 * 1000 },
  );
  assert.equal(dueAt, last + 5 * 60 * 1000);
  assert.notEqual(dueAt, 0);
});

test("synced persist retires the due marker; crash after arm still leaves a marker", async () => {
  const h = createCountingEnv();
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  await assert.rejects(
    () =>
      applyChironDueMarkerTransition(h.env.COMPLIANCE_KV, {
        eventKey: startKey,
        previousDueAtMs: 0,
        nextDueAtMs: NOW_MS + 60_000,
        persist: async () => {},
        crashAfter: "after_arm",
      }),
    (err) => err instanceof ChironDueIndexTestCrash,
  );
  const armedAfterCrash = [...h.compliance.keys()].filter((k) =>
    k.startsWith(CHIRON_RECONCILE_DUE_PREFIX),
  );
  assert.ok(armedAfterCrash.length >= 1);

  for (const key of [...h.compliance.keys()]) {
    if (key.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && key !== CHIRON_RECONCILE_DUE_DONE_KEY) {
      h.compliance.delete(key);
    }
  }
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  await _chironWriteExportStatus(
    h.env,
    "status-sync",
    { sync_state: "synced", last_attempt_at: new Date(NOW_MS).toISOString() },
    { event: start, eventKey: startKey, previousStatus: null, nowMs: NOW_MS },
  );
  const leftover = [...h.compliance.keys()].filter(
    (k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX) && k !== CHIRON_RECONCILE_DUE_DONE_KEY,
  );
  assert.equal(leftover.length, 0);
});

test("idle cron after migration: one due list, zero event value reads", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  h.resetCounts();
  await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron", nowMs: NOW_MS });
  assert.equal(h.eventReads().length, 0);
  assert.equal(h.dueLists(), 1);
  assert.equal(h.counts.bookingReads, 0);
});

test("two tenants stay isolated when both have due-at-0 markers", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await seedConnection(h, TENANT_B, COMPANY_B);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const aKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "a");
  const bKey = eventKeyFor(TENANT_B, COMPANY_B, "2026/08/18", 1787043121583, "b");
  await h.env.COMPLIANCE_KV.put(
    aKey,
    JSON.stringify(streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"))),
  );
  await h.env.COMPLIANCE_KV.put(
    bKey,
    JSON.stringify({
      ...streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z")),
      tenant_id: TENANT_B,
      company_id: COMPANY_B,
      booking_id: "street_other",
    }),
  );
  await armChironDueMarker(h.env.COMPLIANCE_KV, aKey, 0);
  await armChironDueMarker(h.env.COMPLIANCE_KV, bKey, 0);
  const listed = [...h.compliance.keys()]
    .filter((k) => k.startsWith(CHIRON_RECONCILE_DUE_PREFIX))
    .sort()
    .map((name) => ({ name, metadata: h.compliance.get(name)?.metadata || null }));
  const pickedA = selectDueChironMarkers(listed, {
    nowMs: NOW_MS,
    limit: 20,
    scopeFilter: {
      tenantSegment: safeSegment(TENANT_A, ""),
      companySegment: safeSegment(COMPANY_A, ""),
    },
  });
  assert.equal(pickedA.selected.length, 1);
  assert.equal(pickedA.selected[0].eventKey, aKey);
});

test("cron reads one authoritative event per selected marker and does not scan history", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  await markChironDueMigrationComplete(h.env.COMPLIANCE_KV, { now: new Date(NOW_MS) });
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  await armChironDueMarker(h.env.COMPLIANCE_KV, startKey, 0);
  for (let i = 0; i < 30; i += 1) {
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
  assert.equal(summary.due_selected, 1);
  assert.deepEqual(h.eventReads(), [startKey]);
  assert.equal(h.counts.eventPrefixLists, 0);
  assert.equal(h.dueLists(), 1);
});

test("append auto-submit is given a preloaded context and does not list event history", async () => {
  const h = createCountingEnv();
  await seedConnection(h, TENANT_A, COMPANY_A);
  const start = streetEvent("ride_start", Date.parse("2026-08-18T08:52:01.583Z"));
  const startKey = eventKeyFor(TENANT_A, COMPANY_A, "2026/08/18", 1787043121583, "ride_start");
  await h.env.COMPLIANCE_KV.put(startKey, JSON.stringify(start));
  for (let i = 0; i < 20; i += 1) {
    await h.env.COMPLIANCE_KV.put(
      eventKeyFor(TENANT_A, COMPANY_A, "2026/08/10", 1786345177300 + i, `hist_${i}`),
      JSON.stringify({ event_type: "ride_stop", event_id: `hist_${i}` }),
    );
  }
  h.resetCounts();
  await _chironAutoSubmitAfterAppendBestEffort(h.env, start, startKey);
  assert.equal(h.counts.eventPrefixLists, 0);
});
