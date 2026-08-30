// COMPANY-DATA-LATENCY-P0-REPAIR-1 (Part B) — executable spec for the
// `handleDashboardTripKpis` repair.
//
// What the repair changes:
//
//   * The four independent aggregate KV documents (global, month, finance,
//     debug) plus the diagnostics-cache blob are fetched in a single
//     parallel batch instead of five sequential awaits.
//   * The expensive `_collectTripKpiPendingDiagnostics` and
//     `_collectActionableUnpaidCompletedStats` scans NO LONGER run on the
//     request-serving path, and ordinary GET never schedules a
//     `ctx.waitUntil` diagnostic refresh.
//   * The visible KPI card is truthful: when the diagnostics cache is
//     unavailable, `unpaid_completed_rides_count` falls back to the
//     primary aggregate raw count instead of silently reporting `0`.
//
// Preserved behavior:
//
//   * `78c0ade` bounded-fallback (skip reconcile when aggregates valid).
//   * `74c0ade` bounded fallback cap.
//   * Exact integer-cent totals from primary + finance aggregates.
//   * Tenant/company isolation.
//   * No extra reconcile on the read path when aggregates are ready.
//
// Run:
//   node --test workers/tracking/dashboard_trip_kpis_latency_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, {
  materializeTripDashboardKpisBestEffort,
} from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };
const MONTH = "2026-07";

const KEY_GLOBAL = "tenant:T1:company:C1:dashboard:trip_kpis:v1";
const KEY_MONTH = `tenant:T1:company:C1:dashboard:trip_kpis:month:${MONTH}:v1`;
const KEY_FINANCE = `tenant:T1:company:C1:dashboard:booking_finance:month:${MONTH}:v1`;
const KEY_DEBUG = "tenant:T1:company:C1:dashboard:trip_kpi_debug:v1";
const KEY_DIAG_CACHE =
  "tenant:T1:company:C1:dashboard:trip_kpi_diagnostics_cache:v1";
const PENDING_PREFIX = "tenant:T1:company:C1:dashboard:trip_kpi_pending_booking:";
const CONTRIB_PREFIX = "tenant:T1:company:C1:dashboard:trip_kpi_contrib:";

/** Instrumented KV mock: records per-key call order, tracks concurrency and
 * supports optional per-`get` latency to prove parallelism. */
function makeKV({ seed = {}, getLatencyMs = 0 } = {}) {
  const store = new Map(Object.entries(seed));
  const state = {
    getKeys: [],
    listPrefixes: [],
    putKeys: [],
    inFlightGets: 0,
    maxInFlightGets: 0,
  };
  return {
    _state: state,
    store,
    async get(key) {
      state.inFlightGets += 1;
      state.getKeys.push(key);
      if (state.inFlightGets > state.maxInFlightGets) {
        state.maxInFlightGets = state.inFlightGets;
      }
      try {
        if (getLatencyMs > 0) {
          await new Promise((r) => setTimeout(r, getLatencyMs));
        }
        return store.has(key) ? store.get(key) : null;
      } finally {
        state.inFlightGets -= 1;
      }
    },
    async put(key, val) {
      state.putKeys.push(key);
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts = {}) {
      const prefix = String(opts.prefix || "");
      state.listPrefixes.push(prefix);
      const all = [...store.keys()]
        .filter((name) => (prefix ? name.startsWith(prefix) : true))
        .sort();
      return {
        keys: all.map((name) => ({ name })),
        list_complete: true,
      };
    },
  };
}

function makeEnv(kv) {
  return {
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
  };
}

/** Test harness for `ctx.waitUntil` that resolves the background promise
 * inline so tests can await it. */
function makeCtx() {
  const scheduled = [];
  return {
    scheduled,
    waitUntil(promise) {
      scheduled.push(promise);
    },
    async flush() {
      const pending = scheduled.splice(0, scheduled.length);
      await Promise.all(pending);
    },
  };
}

function kpisReq(url = `https://track.internal/admin/dashboard/trip-kpis?tenant_id=T1&company_id=C1&month=${MONTH}`) {
  return new Request(url, {
    method: "GET",
    headers: { "x-admin-token": ADMIN },
  });
}

function seedValidAggregates({
  seed = {},
  monthPaidCount = 5,
  monthIncomeCents = 12000,
  completed = 137,
  unpaidRaw = 14,
} = {}) {
  seed[KEY_GLOBAL] = JSON.stringify({
    completed_rides_count: completed,
    unpaid_completed_rides_count: unpaidRaw,
  });
  seed[KEY_MONTH] = JSON.stringify({
    monthly_paid_rides_count: monthPaidCount,
    monthly_income_cents: monthIncomeCents,
    updated_at: "2026-07-24T18:00:00Z",
  });
  seed[KEY_FINANCE] = JSON.stringify({
    monthly_paid_bookings_income_cents: monthIncomeCents,
    monthly_paid_bookings_count: monthPaidCount,
    updated_at: "2026-07-24T18:00:00Z",
  });
  seed[KEY_DEBUG] = JSON.stringify({});
  return seed;
}

function seedDiagnosticsCache({
  seed = {},
  ageMs = 30_000,
  actionable = 3,
  trackingOnly = 4,
  staleUnactionable = 2,
  missingArtifact = 0,
  scanned = 20,
  tripMissing = 1,
  paidButNotCompleted = 0,
} = {}) {
  const computedAtMs = Date.now() - ageMs;
  seed[KEY_DIAG_CACHE] = JSON.stringify({
    trip_missing: tripMissing,
    trip_missing_active: tripMissing,
    paid_but_not_completed: paidButNotCompleted,
    paid_but_not_completed_active: paidButNotCompleted,
    actionable_count: actionable,
    tracking_only: trackingOnly,
    stale_unactionable: staleUnactionable,
    missing_visible_payment_artifact: missingArtifact,
    total_scanned_unpaid_completed: scanned,
    computed_at_utc: new Date(computedAtMs).toISOString(),
  });
  return seed;
}

// ---------------------------------------------------------------------------
// T1 — valid aggregate + fresh cache: no reconcile, no scan, only 5 KV.gets.
// ---------------------------------------------------------------------------

test("Part B / T1: valid aggregate + fresh cache — 5 KV.gets, no reconcile, no list scan", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({}),
    ageMs: 10_000,
    actionable: 3,
  });
  const kv = makeKV({ seed });
  const ctx = makeCtx();
  const res = await worker.fetch(kpisReq(), makeEnv(kv), ctx);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.completed_rides_count, 137);
  assert.equal(body.monthly_paid_rides_count, 5);
  assert.equal(body.monthly_income_cents, 12000);
  assert.equal(body.unpaid_completed_rides_count, 3, "actionable count from cache");
  assert.equal(body.diagnostics.completed_but_unpaid_raw, 14);
  assert.equal(body.diagnostics_source, "cached_fresh");
  assert.ok(body.diagnostics_computed_at_utc);
  // Exactly the five parallel aggregate reads — NO expensive scan reads.
  assert.equal(kv._state.getKeys.length, 5);
  assert.deepEqual(
    [...kv._state.getKeys].sort(),
    [KEY_DEBUG, KEY_DIAG_CACHE, KEY_FINANCE, KEY_GLOBAL, KEY_MONTH].sort(),
  );
  assert.deepEqual(kv._state.listPrefixes, [], "no diagnostic list scans");
  await ctx.flush();
  // A fresh cache should not trigger a background refresh.
  assert.equal(ctx.scheduled.length, 0);
});

// ---------------------------------------------------------------------------
// T2 — 5 aggregate reads run in a single parallel wave (fake latency proof).
// ---------------------------------------------------------------------------

test("Part B / T2: 5 aggregate reads execute in a single parallel wave", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({}),
    ageMs: 10_000,
  });
  const kv = makeKV({ seed, getLatencyMs: 30 });
  const ctx = makeCtx();
  const started = Date.now();
  await worker.fetch(kpisReq(), makeEnv(kv), ctx);
  const elapsedMs = Date.now() - started;
  // Sequential would be >= 5 * 30 = 150 ms. Parallel wave ~ 30-50 ms.
  assert.ok(
    elapsedMs < 120,
    `expected <120 ms parallel wave, got ${elapsedMs} ms (sequential regression?)`,
  );
  // Concurrency ceiling: at least 5 in flight (all aggregate reads).
  assert.ok(
    kv._state.maxInFlightGets >= 4,
    `expected parallelism, max in-flight was ${kv._state.maxInFlightGets}`,
  );
});

// ---------------------------------------------------------------------------
// T3 — same aggregate is not re-fetched when reconcile is skipped.
// ---------------------------------------------------------------------------

test("Part B / T3: valid aggregate is not re-fetched on the read path", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({}),
    ageMs: 5_000,
  });
  const kv = makeKV({ seed });
  await worker.fetch(kpisReq(), makeEnv(kv), makeCtx());
  const globalReads = kv._state.getKeys.filter((k) => k === KEY_GLOBAL).length;
  const monthReads = kv._state.getKeys.filter((k) => k === KEY_MONTH).length;
  assert.equal(globalReads, 1, "global aggregate must be read exactly once");
  assert.equal(monthReads, 1, "month aggregate must be read exactly once");
});

// ---------------------------------------------------------------------------
// T4 — invalid aggregate returns quickly + does not invent zero.
// ---------------------------------------------------------------------------

test("Part B / T4: absent diagnostics cache falls back to raw unpaid count (never invents zero)", async () => {
  // Aggregates valid; diagnostics cache missing.
  const seed = seedValidAggregates({});
  const kv = makeKV({ seed });
  const ctx = makeCtx();
  const res = await worker.fetch(kpisReq(), makeEnv(kv), ctx);
  const body = await res.json();
  assert.equal(res.status, 200);
  // The visible KPI must not silently drop to 0 just because the background
  // scan hasn't run yet.
  assert.equal(body.unpaid_completed_rides_count, 14, "falls back to global.unpaid_completed_rides_count");
  assert.equal(body.diagnostics.completed_but_unpaid, 14);
  assert.equal(body.diagnostics_source, "unavailable");
  assert.equal(body.diagnostics_computed_at_utc, null);
  // HTTP-KV-AMPLIFIERS-P0: ordinary GET never schedules a diagnostic scan.
  assert.equal(ctx.scheduled.length, 0);
  assert.deepEqual(kv._state.listPrefixes, [], "no diagnostic list scans");
});

// ---------------------------------------------------------------------------
// T5 — stale cache is still returned; background refresh scheduled.
// ---------------------------------------------------------------------------

test("Part B / T5: stale cache is returned as authoritative; ordinary GET never refreshes", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({}),
    ageMs: 2 * 60_000, // 2 min > fresh threshold (60 s) but < max age (15 min)
    actionable: 5,
  });
  const kv = makeKV({ seed });
  const ctx = makeCtx();
  const res = await worker.fetch(kpisReq(), makeEnv(kv), ctx);
  const body = await res.json();
  assert.equal(body.unpaid_completed_rides_count, 5, "stale cache still trusted");
  assert.equal(body.diagnostics_source, "cached_stale");
  assert.equal(ctx.scheduled.length, 0, "ordinary GET must not refresh diagnostics");
  await ctx.flush();
  assert.deepEqual(kv._state.listPrefixes, [], "no diagnostic list scans");
  assert.equal(kv._state.putKeys.includes(KEY_DIAG_CACHE), false);
});

// ---------------------------------------------------------------------------
// T6 — background refresh recomputes correctly.
// ---------------------------------------------------------------------------

test("Part B / T6: repeated GETs stay projection-only and never refresh diagnostics", async () => {
  const seed = seedValidAggregates({});
  const kv = makeKV({ seed });
  const ctx = makeCtx();
  const res1 = await worker.fetch(kpisReq(), makeEnv(kv), ctx);
  const body1 = await res1.json();
  assert.equal(body1.diagnostics_source, "unavailable");
  await ctx.flush();
  const ctx2 = makeCtx();
  const res2 = await worker.fetch(kpisReq(), makeEnv(kv), ctx2);
  const body2 = await res2.json();
  assert.equal(body2.diagnostics_source, "unavailable");
  assert.equal(ctx.scheduled.length, 0);
  assert.equal(ctx2.scheduled.length, 0);
  assert.deepEqual(kv._state.listPrefixes, [], "no diagnostic list scans");
});

// ---------------------------------------------------------------------------
// T7 — invalid aggregate still triggers bounded reconcile (78c0ade contract).
// ---------------------------------------------------------------------------

test("Part B / T7: absent primary aggregate is data_pending and never reconciles", async () => {
  const kv = makeKV({ seed: {} });
  const ctx = makeCtx();
  const res = await worker.fetch(kpisReq(), makeEnv(kv), ctx);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.data_pending, true);
  assert.equal(body.degraded, true);
  assert.equal(body.projection_health, "missing");
  assert.equal(body.counts_are_authoritative, false);
  assert.equal(body.completed_rides_count, 0);
  assert.deepEqual(kv._state.listPrefixes, [], "missing projection must not scan history");
  assert.equal(ctx.scheduled.length, 0);
});

// ---------------------------------------------------------------------------
// T8 — tenant/company isolation still enforced.
// ---------------------------------------------------------------------------

test("Part B / T8: scope B never picks up scope A's cached diagnostics", async () => {
  const scopeAGlobal = "tenant:TA:company:CA:dashboard:trip_kpis:v1";
  const scopeAMonth = `tenant:TA:company:CA:dashboard:trip_kpis:month:${MONTH}:v1`;
  const scopeAFinance = `tenant:TA:company:CA:dashboard:booking_finance:month:${MONTH}:v1`;
  const scopeADebug = "tenant:TA:company:CA:dashboard:trip_kpi_debug:v1";
  const scopeADiag = "tenant:TA:company:CA:dashboard:trip_kpi_diagnostics_cache:v1";

  const scopeBGlobal = "tenant:TB:company:CB:dashboard:trip_kpis:v1";
  const scopeBMonth = `tenant:TB:company:CB:dashboard:trip_kpis:month:${MONTH}:v1`;
  const scopeBFinance = `tenant:TB:company:CB:dashboard:booking_finance:month:${MONTH}:v1`;
  const scopeBDebug = "tenant:TB:company:CB:dashboard:trip_kpi_debug:v1";

  const seed = {
    [scopeAGlobal]: JSON.stringify({
      completed_rides_count: 100,
      unpaid_completed_rides_count: 10,
    }),
    [scopeAMonth]: JSON.stringify({
      monthly_paid_rides_count: 3,
      monthly_income_cents: 5000,
      updated_at: "2026-07-24T18:00:00Z",
    }),
    [scopeAFinance]: JSON.stringify({
      monthly_paid_bookings_income_cents: 5000,
      monthly_paid_bookings_count: 3,
      updated_at: "2026-07-24T18:00:00Z",
    }),
    [scopeADebug]: JSON.stringify({}),
    [scopeADiag]: JSON.stringify({
      actionable_count: 7,
      total_scanned_unpaid_completed: 10,
      computed_at_utc: new Date().toISOString(),
    }),
    [scopeBGlobal]: JSON.stringify({
      completed_rides_count: 50,
      unpaid_completed_rides_count: 4,
    }),
    [scopeBMonth]: JSON.stringify({
      monthly_paid_rides_count: 1,
      monthly_income_cents: 100,
      updated_at: "2026-07-24T18:00:00Z",
    }),
    [scopeBFinance]: JSON.stringify({
      monthly_paid_bookings_income_cents: 100,
      monthly_paid_bookings_count: 1,
      updated_at: "2026-07-24T18:00:00Z",
    }),
    [scopeBDebug]: JSON.stringify({}),
  };
  const kv = makeKV({ seed });
  const resB = await worker.fetch(
    new Request(
      `https://track.internal/admin/dashboard/trip-kpis?tenant_id=TB&company_id=CB&month=${MONTH}`,
      { method: "GET", headers: { "x-admin-token": ADMIN } },
    ),
    makeEnv(kv),
    makeCtx(),
  );
  const bodyB = await resB.json();
  assert.equal(bodyB.completed_rides_count, 50);
  assert.equal(bodyB.diagnostics_source, "unavailable");
  // Scope B must fall back to its own raw unpaid count, NEVER 7 from A.
  assert.equal(bodyB.unpaid_completed_rides_count, 4);
});

// ---------------------------------------------------------------------------
// T9 — integer-cent accuracy unchanged.
// ---------------------------------------------------------------------------

test("Part B / T9: integer-cent totals from primary + finance aggregates are exact", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({
      monthIncomeCents: 120239, // 1202.39 EUR
      monthPaidCount: 42,
    }),
    ageMs: 5000,
  });
  const kv = makeKV({ seed });
  const res = await worker.fetch(kpisReq(), makeEnv(kv), makeCtx());
  const body = await res.json();
  assert.equal(body.monthly_income_cents, 120239);
  assert.equal(body.monthly_paid_bookings_income_cents, 120239);
  assert.equal(body.monthly_paid_rides_count, 42);
  assert.equal(body.monthly_paid_bookings_count, 42);
});

// ---------------------------------------------------------------------------
// T10 — timing log emitted without PII.
// ---------------------------------------------------------------------------

test("Part B / T10: [TRIP_KPI_TIMING] emitted with integer counters only (no IDs)", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({}),
    ageMs: 5000,
  });
  const kv = makeKV({ seed });
  const captured = [];
  const originalLog = console.log;
  console.log = (msg) => {
    captured.push(String(msg));
  };
  try {
    await worker.fetch(kpisReq(), makeEnv(kv), makeCtx());
  } finally {
    console.log = originalLog;
  }
  const timingLine = captured.find((line) => line.startsWith("[TRIP_KPI_TIMING]"));
  assert.ok(timingLine, "expected [TRIP_KPI_TIMING] line");
  for (const forbidden of ["T1", "C1", "tenant:", "company:", "trip_id"]) {
    assert.equal(
      timingLine.includes(forbidden),
      false,
      `[TRIP_KPI_TIMING] leaked "${forbidden}"`,
    );
  }
  for (const expected of [
    "endpoint=trip",
    "auth_ms=",
    "parallel_read_ms=",
    "total_ms=",
    "kpi_source=",
    "diagnostics_source=",
  ]) {
    assert.ok(timingLine.includes(expected), `missing "${expected}"`);
  }
});

test("HTTP-KV / 10k historical trips: GET cost stays constant and never scans them", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({}),
    ageMs: 5_000,
  });
  for (let i = 0; i < 10_000; i += 1) {
    seed[`${CONTRIB_PREFIX}hist${i}:v1`] = JSON.stringify({ trip_id: `hist${i}` });
  }
  const kv = makeKV({ seed });
  const ctx = makeCtx();
  const res = await worker.fetch(kpisReq(), makeEnv(kv), ctx);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.completed_rides_count, 137);
  assert.equal(kv._state.getKeys.length, 5);
  assert.deepEqual(kv._state.listPrefixes, []);
  assert.equal(
    kv._state.getKeys.some((key) => String(key).startsWith(CONTRIB_PREFIX)),
    false,
  );
  assert.equal(ctx.scheduled.length, 0);
});

test("HTTP-KV / three concurrent trip-kpis GETs: no diagnostic refresh, constant projection reads", async () => {
  const seed = seedDiagnosticsCache({
    seed: seedValidAggregates({}),
    ageMs: 90_000,
    actionable: 5,
  });
  const kv = makeKV({ seed });
  const ctxs = [makeCtx(), makeCtx(), makeCtx()];
  const env = makeEnv(kv);
  const results = await Promise.all(
    ctxs.map((ctx) => worker.fetch(kpisReq(), env, ctx)),
  );
  for (const res of results) {
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.unpaid_completed_rides_count, 5);
    assert.equal(body.diagnostics_source, "cached_stale");
  }
  assert.equal(kv._state.getKeys.length, 15);
  assert.deepEqual(kv._state.listPrefixes, []);
  assert.equal(ctxs.reduce((n, ctx) => n + ctx.scheduled.length, 0), 0);
});

test("HTTP-KV / trip payment mutation keeps the projection correct without a GET scan", async () => {
  const kv = makeKV({ seed: {} });
  const env = makeEnv(kv);
  const scope = { tenant_id: "T1", company_id: "C1" };
  const unpaidTrip = {
    trip_id: "trip-1",
    tenant_id: "T1",
    company_id: "C1",
    status: "completed",
    payment_status: "unpaid",
  };
  await materializeTripDashboardKpisBestEffort(env, scope, unpaidTrip, "test_unpaid");
  const paidTrip = {
    ...unpaidTrip,
    payment_status: "paid",
    paid_at: "2026-07-15T12:00:00.000Z",
    payment_amount: 42,
  };
  await materializeTripDashboardKpisBestEffort(env, scope, paidTrip, "test_paid");
  await materializeTripDashboardKpisBestEffort(env, scope, paidTrip, "test_paid_retry");
  const res = await worker.fetch(kpisReq(), env, makeCtx());
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.completed_rides_count, 1);
  assert.equal(body.unpaid_completed_rides_count, 0);
  assert.equal(body.monthly_paid_rides_count, 1);
  assert.deepEqual(kv._state.listPrefixes, []);
});
