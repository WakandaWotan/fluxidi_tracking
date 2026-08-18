// CHIRON-COMPLIANCE-KV-COST-P0
//
// Read-count, behavioural-equivalence and isolation contract for the pass-scoped
// hydration/leg-map preload.
//
// Proven production defect: one reconcile pass processed 44 considered events for
// a single tenant/company, and every one of them re-read the identical scoped
// hydration triple (3 BOOKING_KV gets) and rebuilt the identical booking
// leg-type map from the identical `contextEntries` (~172 BOOKING_KV gets). That
// is `considered x (3 + distinct_legless_bookings)` ~= 7,700 BOOKING_KV reads per
// tick, 12 ticks/hour, ~92,400 reads/hour, for values that cannot change inside
// the pass.
//
// The seam computes both exactly once per scope pass. These tests assert the
// resulting read count is `3 + distinct_legless_bookings` and, critically, that
// it stays CONSTANT as the considered-event count grows.
//
// This phase does NOT address the separate COMPLIANCE_KV per-tick event scan
// (~1,380 gets/tick); that cost is asserted here only so it stays visible.
//
// Hermetic: in-memory KV, outbound fetch trapped, no Chiron/Billit/Mollie call.
//
//   node --test workers/compliance/chiron_compliance_kv_cost_p0.test.mjs

import { test, before, after, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";
import {
  armChironDueMarker,
  CHIRON_RECONCILE_DUE_DONE_KEY,
} from "./chiron_reconcile_due_index.js";

const {
  _chironAutoReconcileScopeBestEffort,
  _chironCronReconcileAllScopesBestEffort,
  _chironAutoSubmitOneEvent,
  _chironBuildOfficialDraftForSingleEvent,
  _chironBuildScopePreload,
  _chironPreloadForScope,
  _chironLoadScopedHydrationCache,
  _chironLoadBookingLegTypeMap,
  _chironShouldRunReconcileFromStatusPoll,
  CHIRON_AUTO_RECONCILE_MAX_PROCESS,
  safeSegment,
} = __testInternals;

async function seedDueNowAndMigrationDone(h, nowMs = Date.now()) {
  for (const key of [...h.complianceStore.keys()]) {
    if (!key.startsWith("compliance_event_v1/")) continue;
    await armChironDueMarker(h.env.COMPLIANCE_KV, key, nowMs);
  }
  await h.env.COMPLIANCE_KV.put(CHIRON_RECONCILE_DUE_DONE_KEY, JSON.stringify({ v: 1 }), {
    metadata: { v: 1, done: true },
  });
}

const ACC_URL = "https://mow-acc.api.vlaanderen.be/chiron/taxirit";
const TENANT_A = "T_kvcost_a";
const COMPANY_A = "C_kvcost_a";
const TENANT_B = "T_kvcost_b";
const COMPANY_B = "C_kvcost_b";

let originalFetch;
let outbound = [];

before(() => {
  originalFetch = global.fetch;
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url || String(input);
    outbound.push(href);
    throw new Error(`hermetic test: blocked outbound fetch to ${href}`);
  };
});

after(() => {
  global.fetch = originalFetch;
});

beforeEach(() => {
  outbound = [];
});

/* ===================== fixtures ===================== */

// The reconciler only considers events inside CHIRON_AUTO_RECONCILE_MAX_WINDOW_MS
// (14 days) and after `testflow_started_at`, so fixture timestamps must be
// relative to now rather than hard-coded dates.
const NOW_MS = Date.now();
const EVENT_BASE_MS = NOW_MS - 3 * 60 * 60 * 1000;
const TESTFLOW_STARTED_AT = new Date(NOW_MS - 7 * 24 * 60 * 60 * 1000).toISOString();

function eventIso(seq, offsetSeconds = 0) {
  return new Date(EVENT_BASE_MS + seq * 60_000 + offsetSeconds * 1000).toISOString();
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
    testflow_started_at: TESTFLOW_STARTED_AT,
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
  return {
    event_type: kind,
    event_id: `${kind}:${tenantId}:${companyId}:${bookingId}`,
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: bookingId,
    trip_id: `trip_${bookingId}`,
    ride_type: "direct",
    created_at_utc: eventIso(seq, isStop ? 30 : 0),
    timestamps: {
      event_at_utc: eventIso(seq, isStop ? 30 : 0),
      started_at_utc: eventIso(seq, 0),
      ...(isStop ? { stopped_at_utc: eventIso(seq, 30) } : {}),
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
  return `compliance_event_v1/tenant/${t}/company/${c}/2026/08/03/${1000 + seq}_${label}`;
}

/**
 * Counting KV pair. COMPLIANCE_KV holds the connection doc plus events;
 * BOOKING_KV records every value read so the contract can be asserted per key.
 */
function makeHarness({ scopes, bookingsPerScope, eventsPerBooking }) {
  const complianceStore = new Map();
  const complianceMeta = new Map();
  const bookingReads = [];
  const complianceReads = [];
  let complianceLists = 0;

  for (const { tenantId, companyId } of scopes) {
    complianceStore.set(
      `tenant:${tenantId}:company:${companyId}:chiron_connection:v1`,
      JSON.stringify(completeFive()),
    );
    let seq = 0;
    for (let b = 0; b < bookingsPerScope; b += 1) {
      const bookingId = `street_${tenantId}_${String(b).padStart(3, "0")}`;
      const kinds = eventsPerBooking === 1 ? ["ride_stop"] : ["ride_start", "ride_stop"];
      for (const kind of kinds) {
        seq += 1;
        complianceStore.set(
          eventKeyFor(tenantId, companyId, seq, `${kind}_${b}`),
          JSON.stringify(rideEvent(kind, tenantId, companyId, bookingId, seq)),
        );
      }
    }
  }

  const env = {
    CHIRON_EXPORT_MODE: "test",
    CHIRON_EXPORT_BASE_URL: ACC_URL,
    COMPLIANCE_KV: {
      async get(key) {
        complianceReads.push(key);
        return complianceStore.get(key) ?? null;
      },
      async put(key, value, opts = {}) {
        complianceStore.set(key, value);
        if (opts && opts.metadata) complianceMeta.set(key, opts.metadata);
        else complianceMeta.delete(key);
      },
      async delete(key) {
        complianceStore.delete(key);
        complianceMeta.delete(key);
      },
      async list({ prefix = "", limit = 1000, cursor } = {}) {
        complianceLists += 1;
        const all = [...complianceStore.keys()].filter((k) => k.startsWith(prefix)).sort();
        const start = cursor ? Number(Buffer.from(String(cursor), "base64").toString("utf8")) || 0 : 0;
        const slice = all.slice(start, start + limit);
        const next = start + slice.length;
        const complete = next >= all.length;
        return {
          keys: slice.map((name) => ({ name, metadata: complianceMeta.get(name) || null })),
          list_complete: complete,
          cursor: complete ? undefined : Buffer.from(String(next), "utf8").toString("base64"),
        };
      },
    },
    BOOKING_KV: {
      async get(key) {
        bookingReads.push(key);
        return null; // no booking record => leg type stays on the base fallback
      },
    },
  };

  const hydrationKeysFor = (tenantId, companyId) => [
    `tenant:${tenantId}:company:${companyId}:business_profile:v1`,
    `tenant:${tenantId}:company:${companyId}:fleet:vehicles:v1`,
    `tenant:${tenantId}:company:${companyId}:drivers:index:v1`,
  ];

  return {
    env,
    bookingReads,
    complianceReads,
    complianceStore,
    complianceListCount: () => complianceLists,
    hydrationKeysFor,
    bookingKeyReads: () => bookingReads.filter((k) => k.startsWith("booking:")),
    hydrationReads: () => bookingReads.filter((k) => !k.startsWith("booking:")),
    countOf: (key) => bookingReads.filter((k) => k === key).length,
    reset: () => {
      bookingReads.length = 0;
      complianceReads.length = 0;
      complianceLists = 0;
    },
  };
}

const SCOPE_A = { tenantId: TENANT_A, companyId: COMPANY_A };
const SCOPE_B = { tenantId: TENANT_B, companyId: COMPANY_B };

/* ===================== read-count contract ===================== */

test("1. BOOKING_KV reads per scope pass equal exactly 3 hydration reads plus one per distinct legless booking", async () => {
  const bookings = 8;
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 1 });

  const outcome = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "test",
  });
  assert.equal(outcome.ok, true);
  assert.ok(outcome.considered > 0, "fixture must produce candidates");

  assert.equal(h.hydrationReads().length, 3, "exactly three hydration reads");
  assert.equal(h.bookingKeyReads().length, bookings, "exactly one read per distinct booking");
  assert.equal(h.bookingReads.length, 3 + bookings, "total BOOKING_KV reads == 3 + B");

  // Each hydration key read exactly once, not once per event.
  for (const key of h.hydrationKeysFor(TENANT_A, COMPANY_A)) {
    assert.equal(h.countOf(key), 1, `hydration key read exactly once: ${key}`);
  }
  // Each booking read exactly once, not once per event.
  const distinct = new Set(h.bookingKeyReads());
  assert.equal(distinct.size, bookings);
  for (const key of distinct) {
    assert.equal(h.countOf(key), 1, `booking key read exactly once: ${key}`);
  }
  assert.deepEqual(outbound, [], "no provider call");
});

test("2. the BOOKING_KV read count stays constant as the considered-event count grows", async () => {
  const bookings = 8;

  const one = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 1 });
  const outcomeOne = await _chironAutoReconcileScopeBestEffort(one.env, TENANT_A, COMPANY_A, {
    source: "test",
  });

  const two = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 2 });
  const outcomeTwo = await _chironAutoReconcileScopeBestEffort(two.env, TENANT_A, COMPANY_A, {
    source: "test",
  });

  // Twice the candidates over the same booking set.
  assert.ok(
    outcomeTwo.considered > outcomeOne.considered,
    `considered must grow: ${outcomeOne.considered} -> ${outcomeTwo.considered}`,
  );
  assert.equal(outcomeTwo.scanned, outcomeOne.scanned * 2);

  // Yet BOOKING_KV cost is identical and equals 3 + B in both.
  assert.equal(one.bookingReads.length, 3 + bookings);
  assert.equal(two.bookingReads.length, 3 + bookings);
  assert.equal(
    two.bookingReads.length,
    one.bookingReads.length,
    "BOOKING_KV reads must not scale with considered-event count",
  );

  // Pre-fix behaviour would have been considered x (3 + B); prove we are far below.
  const preFix = outcomeTwo.considered * (3 + bookings);
  assert.ok(
    two.bookingReads.length * 4 < preFix,
    `post-fix ${two.bookingReads.length} must be far below pre-fix ${preFix}`,
  );
});

test("3. two scopes in one cron tick each build their own independent preload", async () => {
  const bookings = 4;
  const h = makeHarness({
    scopes: [SCOPE_A, SCOPE_B],
    bookingsPerScope: bookings,
    eventsPerBooking: 1,
  });
  await seedDueNowAndMigrationDone(h);

  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron" });
  assert.equal(summary.ok, true);
  assert.equal(summary.scopes, 2, "both due scopes processed");

  // Each scope reads its OWN hydration triple exactly once. No sharing, no
  // double-reading.
  for (const { tenantId, companyId } of [SCOPE_A, SCOPE_B]) {
    for (const key of h.hydrationKeysFor(tenantId, companyId)) {
      assert.equal(h.countOf(key), 1, `each scope loads its own hydration once: ${key}`);
    }
  }
  assert.equal(h.hydrationReads().length, 6, "3 hydration reads per scope, 2 scopes");

  // Scope A never reads scope B's bookings and vice versa.
  const readsA = h.bookingKeyReads().filter((k) => k.includes(TENANT_A));
  const readsB = h.bookingKeyReads().filter((k) => k.includes(TENANT_B));
  assert.equal(readsA.length, bookings);
  assert.equal(readsB.length, bookings);
  assert.equal(readsA.length + readsB.length, h.bookingKeyReads().length);
});

test("4. no preload survives beyond the scheduled scope pass", async () => {
  const bookings = 5;
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 1 });

  await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, { source: "test" });
  const firstPass = h.bookingReads.length;
  assert.equal(firstPass, 3 + bookings);

  h.reset();
  await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, { source: "test" });
  assert.equal(
    h.bookingReads.length,
    3 + bookings,
    "a second pass re-reads everything: nothing is memoized across passes",
  );
});

test("5. the separate COMPLIANCE_KV per-tick event scan is unchanged by this phase", async () => {
  const bookings = 6;
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 2 });

  const outcome = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "test",
  });
  // Every scanned event is still value-read from COMPLIANCE_KV. This phase does
  // not fix that; the assertion exists so the remaining cost stays visible.
  assert.equal(outcome.scanned, bookings * 2);
  const scannedEventReads = h.complianceReads.filter((k) =>
    k.startsWith("compliance_event_v1/"),
  );
  assert.ok(
    scannedEventReads.length >= outcome.scanned,
    "COMPLIANCE_KV still reads every scanned event value",
  );
  assert.ok(h.complianceListCount() >= 1, "COMPLIANCE_KV listing still occurs");
});

/* ===================== behavioural equivalence ===================== */

test("6. official-draft payload and Chiron idempotency key are identical with and without the preload", async () => {
  const bookings = 3;
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 2 });

  // Rebuild the same context batch the reconciler would pass down.
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  const prefix = `compliance_event_v1/tenant/${t}/company/${c}/`;
  const contextEntries = [...h.complianceStore.keys()]
    .filter((k) => k.startsWith(prefix))
    .sort()
    .map((key) => ({ key, event: JSON.parse(h.complianceStore.get(key)) }));
  assert.ok(contextEntries.length >= 2);

  const target = contextEntries[contextEntries.length - 1];
  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };

  const [hydrationCache, bookingLegTypeMap] = await Promise.all([
    _chironLoadScopedHydrationCache(h.env, scope, true),
    _chironLoadBookingLegTypeMap(h.env, contextEntries),
  ]);
  const preload = _chironBuildScopePreload(scope, {
    hydrationCache,
    bookingLegTypeMap,
    contextEntries,
  });
  assert.ok(preload, "preload envelope must build");

  const withPreload = await _chironBuildOfficialDraftForSingleEvent(
    h.env,
    target.event,
    target.key,
    { preloadedContextEntries: contextEntries, scopePreload: preload },
  );
  const withoutPreload = await _chironBuildOfficialDraftForSingleEvent(
    h.env,
    target.event,
    target.key,
    { preloadedContextEntries: contextEntries },
  );

  assert.deepEqual(
    JSON.parse(JSON.stringify(withPreload)),
    JSON.parse(JSON.stringify(withoutPreload)),
    "official draft must be byte-equivalent with and without the preload",
  );
  assert.equal(withPreload.error, withoutPreload.error);
  assert.equal(
    withPreload.idempotency_key ?? null,
    withoutPreload.idempotency_key ?? null,
    "Chiron idempotency key unchanged",
  );
});

test("7. auto-submit outcome classification is identical with and without the preload", async () => {
  const bookings = 3;
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 2 });
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  const prefix = `compliance_event_v1/tenant/${t}/company/${c}/`;
  const contextEntries = [...h.complianceStore.keys()]
    .filter((k) => k.startsWith(prefix))
    .sort()
    .map((key) => ({ key, event: JSON.parse(h.complianceStore.get(key)) }));
  const target = contextEntries[0];
  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const preload = _chironBuildScopePreload(scope, {
    hydrationCache: await _chironLoadScopedHydrationCache(h.env, scope, true),
    bookingLegTypeMap: await _chironLoadBookingLegTypeMap(h.env, contextEntries),
    contextEntries,
  });

  const a = await _chironAutoSubmitOneEvent(h.env, target.event, target.key, {
    source: "test",
    preloadedContextEntries: contextEntries,
    scopePreload: preload,
  });
  const b = await _chironAutoSubmitOneEvent(h.env, target.event, target.key, {
    source: "test",
    preloadedContextEntries: contextEntries,
  });

  assert.equal(a.ok, b.ok);
  assert.equal(a.skipped, b.skipped);
  assert.equal(a.reason, b.reason);
  assert.equal(a.sync_state ?? null, b.sync_state ?? null);
  assert.equal(a.message_type ?? null, b.message_type ?? null);
  assert.deepEqual(outbound, [], "neither path contacted a provider");
});

test("8. reconcile and cron counters keep their documented shape and bounds", async () => {
  const bookings = 4;
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 2 });

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
    assert.equal(typeof outcome[field], "number", `${field} must remain a number`);
    assert.ok(outcome[field] >= 0, `${field} must stay non-negative`);
  }
  assert.equal(outcome.scanned, bookings * 2);
  assert.ok(
    outcome.considered <= outcome.scanned,
    "considered can never exceed scanned",
  );
  assert.ok(
    outcome.processed <= CHIRON_AUTO_RECONCILE_MAX_PROCESS,
    "per-pass process budget is still enforced",
  );
  assert.equal(outcome.submitted, 0, "no submit is possible without credentials");

  // The cron summary field is `skipped_throttled`; the log line renders it as
  // `throttled=`. Both names are asserted so a rename cannot pass silently.
  const summary = await _chironCronReconcileAllScopesBestEffort(h.env, { source: "cron" });
  for (const field of ["scopes", "ran", "skipped_throttled", "failed"]) {
    assert.equal(typeof summary[field], "number", `${field} must remain a number`);
  }
  assert.equal(summary.skipped_throttled, 0, "cron due-index path does not throttle");
});

test("9. the throttle marker still suppresses a second reconcile in the same window", async () => {
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 3, eventsPerBooking: 1 });

  const first = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "status_poll",
  });
  assert.equal(first.ok, true);
  const connRaw = h.complianceStore.get(
    `tenant:${TENANT_A}:company:${COMPANY_A}:chiron_connection:v1`,
  );
  const connDoc = JSON.parse(connRaw);
  assert.equal(
    _chironShouldRunReconcileFromStatusPoll(connDoc),
    false,
    "status-poll throttle still suppresses a second pass in the 15s window",
  );
});

/* ===================== failure and isolation ===================== */

test("10. a preload built for scope A is refused for scope B", async () => {
  const scopeA = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const scopeB = { tenant_id: TENANT_B, company_id: COMPANY_B };
  const preload = _chironBuildScopePreload(scopeA, {
    hydrationCache: { businessProfile: { legal_name: "A" } },
    bookingLegTypeMap: new Map([["b1", "outbound"]]),
    contextEntries: [],
  });

  assert.ok(_chironPreloadForScope(preload, scopeA), "own scope accepted");
  assert.equal(_chironPreloadForScope(preload, scopeB), null, "other scope refused");
  assert.equal(
    _chironPreloadForScope(preload, { tenant_id: TENANT_A, company_id: COMPANY_B }),
    null,
    "same tenant but different company refused",
  );
  assert.equal(
    _chironPreloadForScope(preload, { tenant_id: "", company_id: "" }),
    null,
    "empty scope refused",
  );
  assert.equal(_chironPreloadForScope(null, scopeA), null);
});

test("11. a foreign-scope event inside a batch loads its own hydration instead of reusing the preload", async () => {
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 2, eventsPerBooking: 1 });
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  const prefix = `compliance_event_v1/tenant/${t}/company/${c}/`;
  const contextEntries = [...h.complianceStore.keys()]
    .filter((k) => k.startsWith(prefix))
    .sort()
    .map((key) => ({ key, event: JSON.parse(h.complianceStore.get(key)) }));

  const scopeA = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const preload = _chironBuildScopePreload(scopeA, {
    hydrationCache: await _chironLoadScopedHydrationCache(h.env, scopeA, true),
    bookingLegTypeMap: await _chironLoadBookingLegTypeMap(h.env, contextEntries),
    contextEntries,
  });

  h.reset();
  const foreignEvent = rideEvent("ride_stop", TENANT_B, COMPANY_B, "street_foreign", 1);
  await _chironBuildOfficialDraftForSingleEvent(
    h.env,
    foreignEvent,
    "compliance_event_v1/tenant/x/company/y/2026/08/03/1_foreign",
    { preloadedContextEntries: contextEntries, scopePreload: preload },
  );

  // Scope B's own hydration keys must be read; scope A's must NOT be re-read.
  for (const key of h.hydrationKeysFor(TENANT_B, COMPANY_B)) {
    assert.equal(h.countOf(key), 1, `foreign scope loads its own key: ${key}`);
  }
  for (const key of h.hydrationKeysFor(TENANT_A, COMPANY_A)) {
    assert.equal(h.countOf(key), 0, `scope A hydration must not be reused: ${key}`);
  }
});

test("12. a preload failure degrades to the original per-event load without publishing partial state", async () => {
  const bookings = 3;
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: bookings, eventsPerBooking: 1 });

  // Make BOOKING_KV hostile: any property access throws, so building the preload
  // raises synchronously inside the pass.
  let accesses = 0;
  h.env.BOOKING_KV = new Proxy(
    {},
    {
      get() {
        accesses += 1;
        throw new Error("hostile binding");
      },
    },
  );

  const outcome = await _chironAutoReconcileScopeBestEffort(h.env, TENANT_A, COMPANY_A, {
    source: "test",
  });
  assert.equal(outcome.ok, true, "reconcile still completes best-effort");
  assert.ok(accesses > 0, "the hostile binding was exercised");
  assert.equal(outcome.submitted, 0);
  assert.deepEqual(outbound, [], "no provider call on the failure path");
});

test("13. the preload envelope is frozen and shares one stable map across events", async () => {
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 3, eventsPerBooking: 1 });
  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const map = new Map([["b1", "outbound"]]);
  const preload = _chironBuildScopePreload(scope, {
    hydrationCache: { businessProfile: null },
    bookingLegTypeMap: map,
    contextEntries: [],
  });

  assert.ok(Object.isFrozen(preload), "envelope must be frozen");
  assert.throws(
    () => {
      "use strict";
      preload.tenant_id = TENANT_B;
    },
    TypeError,
    "scope identity cannot be reassigned",
  );
  assert.equal(_chironPreloadForScope(preload, scope).bookingLegTypeMap, map, "stable map identity");

  // A non-Map or missing scope is rejected rather than silently accepted.
  assert.equal(
    _chironBuildScopePreload(scope, { bookingLegTypeMap: { not: "a map" } }).bookingLegTypeMap,
    null,
  );
  assert.equal(_chironBuildScopePreload({ tenant_id: "", company_id: "" }, {}), null);
});

test("14. the leg-type map is only reused for the exact entry batch it was built from", async () => {
  const h = makeHarness({ scopes: [SCOPE_A], bookingsPerScope: 2, eventsPerBooking: 1 });
  const t = safeSegment(TENANT_A, "");
  const c = safeSegment(COMPANY_A, "");
  const prefix = `compliance_event_v1/tenant/${t}/company/${c}/`;
  const contextEntries = [...h.complianceStore.keys()]
    .filter((k) => k.startsWith(prefix))
    .sort()
    .map((key) => ({ key, event: JSON.parse(h.complianceStore.get(key)) }));

  const scope = { tenant_id: TENANT_A, company_id: COMPANY_A };
  const preload = _chironBuildScopePreload(scope, {
    hydrationCache: await _chironLoadScopedHydrationCache(h.env, scope, true),
    bookingLegTypeMap: await _chironLoadBookingLegTypeMap(h.env, contextEntries),
    contextEntries,
  });

  // A target event that is NOT part of the preloaded batch forces the consumer to
  // append it, which breaks array identity and must trigger a rebuild rather
  // than silently reusing a map that never saw this booking.
  h.reset();
  const outsider = rideEvent("ride_stop", TENANT_A, COMPANY_A, "street_outsider", 99);
  await _chironBuildOfficialDraftForSingleEvent(
    h.env,
    outsider,
    "compliance_event_v1/tenant/zz/company/zz/2026/08/03/99_outsider",
    { preloadedContextEntries: contextEntries, scopePreload: preload },
  );
  assert.ok(
    h.bookingKeyReads().length > 0,
    "map rebuilt for a batch that differs from the preloaded array",
  );
});
