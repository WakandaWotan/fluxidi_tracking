// COMPANY-DATA-LATENCY-P0-REPAIR-1 (Part D) — executable spec for the
// bounded-parallel repair of `handleTripsHistory`.
//
// What the repair changes:
//
//   * Per-trip KV reads (scoped + legacy fallback) run with concurrency 16
//     instead of a single sequential `for` loop.
//   * Legacy scope-migration writes and the trips-index compaction are
//     deferred to `ctx.waitUntil` when available so the response never
//     blocks on best-effort housekeeping writes.
//
// Preserved behavior:
//
//   * Canonical order (the tripIds array order is preserved into the
//     downstream dedupe/limit pipeline).
//   * Tenant/company/driver scope enforcement (records not matching are
//     dropped exactly as before).
//   * Malformed / missing records handled safely (dropped, not fatal).
//   * Dedupe (street-history operational shadow collapse) and pagination
//     unchanged.
//
// Run:
//   node --test workers/tracking/trips_history_bounded_parallel.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_tracking_api_worker_V2_1_with_route_index.js";

const ADMIN = "test-admin-token";
const SCOPE = { tenant_id: "T1", company_id: "C1" };
const DRIVER = "D1";

const KEY_TRIPS_DRIVER_INDEX = `tenant:T1:company:C1:trips_index:driver:${DRIVER}`;
const scopedTripKey = (tripId) => `tenant:T1:company:C1:trip:${tripId}`;
const legacyTripKey = (tripId) => `trip:${tripId}`;

function makeKV({ seed = {}, getLatencyMs = 0 } = {}) {
  const store = new Map(Object.entries(seed));
  const state = {
    getKeys: [],
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
    async list() {
      return { keys: [], list_complete: true };
    },
  };
}

function makeEnv(kv) {
  return {
    ADMIN_TOKEN: ADMIN,
    FLUXIDI_TRACKING: kv,
  };
}

function makeCtx() {
  const scheduled = [];
  return {
    scheduled,
    waitUntil(p) {
      scheduled.push(p);
    },
    async flush() {
      const pending = scheduled.splice(0, scheduled.length);
      await Promise.all(pending);
    },
  };
}

function makeTrip({
  tripId,
  status = "stopped",
  archived = false,
  tenant_id = "T1",
  company_id = "C1",
  driver_id = DRIVER,
  extra = {},
} = {}) {
  return {
    trip_id: tripId,
    tenant_id,
    company_id,
    tenantId: tenant_id,
    companyId: company_id,
    driver_id,
    owner_driver_id: driver_id,
    owner_tenant_id: tenant_id,
    owner_company_id: company_id,
    status,
    archived,
    kind: "direct",
    source: "street_ride",
    stopped_at: "2026-07-23T10:00:00.000Z",
    total_eur: 3.2,
    price_incl_vat: 3.2,
    price_ex_vat: 2.64,
    price_vat: 0.56,
    vat_rate: 0.21,
    currency: "EUR",
    ...extra,
  };
}

function seedTripsIndexed({ count, prefix = "trip_", driverId = DRIVER, malformedIndices = [] } = {}) {
  const seed = {};
  const tripIds = [];
  for (let i = 0; i < count; i += 1) {
    const tripId = `${prefix}${i.toString().padStart(4, "0")}`;
    tripIds.push(tripId);
    if (malformedIndices.includes(i)) {
      // "malformed": write garbage at the scoped key so JSON.parse fails.
      seed[scopedTripKey(tripId)] = "{ not json ";
    } else {
      seed[scopedTripKey(tripId)] = JSON.stringify(makeTrip({ tripId, driver_id: driverId }));
    }
  }
  seed[KEY_TRIPS_DRIVER_INDEX] = JSON.stringify(tripIds);
  return { seed, tripIds };
}

function historyReq({ driverId = DRIVER, limit = 100 } = {}) {
  const url = new URL("https://track.internal/trips/history");
  url.searchParams.set("tenant_id", "T1");
  url.searchParams.set("company_id", "C1");
  url.searchParams.set("driver_id", driverId);
  url.searchParams.set("limit", String(limit));
  return new Request(url.toString(), {
    method: "GET",
    headers: { "x-admin-token": ADMIN },
  });
}

// ---------------------------------------------------------------------------
// T1 — 200 trips read with bounded parallelism (fake-latency proof).
// ---------------------------------------------------------------------------

test("Part D / T1: 200 indexed trips read in bounded parallel, not sequentially", async () => {
  const { seed } = seedTripsIndexed({ count: 200 });
  const kv = makeKV({ seed, getLatencyMs: 20 });
  const ctx = makeCtx();
  const started = Date.now();
  const res = await worker.fetch(historyReq({ limit: 100 }), makeEnv(kv), ctx);
  const elapsedMs = Date.now() - started;
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.count, 100, "returned exactly `limit` trips");
  // 200 sequential reads at 20 ms = 4000 ms. Parallel = ~200 / 16 * 20 = 250 ms.
  // The `_resolveStreetHistoryTrackingLinks` step adds a small overhead but
  // stays well under the sequential ceiling.
  assert.ok(
    elapsedMs < 2000,
    `expected < 2000 ms parallel, got ${elapsedMs} ms — sequential regression?`,
  );
});

// ---------------------------------------------------------------------------
// T2 — concurrency ceiling respected (no more than 16 in-flight reads).
// ---------------------------------------------------------------------------

test("Part D / T2: per-trip read concurrency ceiling is respected", async () => {
  const { seed } = seedTripsIndexed({ count: 200 });
  const kv = makeKV({ seed, getLatencyMs: 5 });
  await worker.fetch(historyReq({ limit: 100 }), makeEnv(kv), makeCtx());
  // Guard rail: never explode subrequest budget. Some extra concurrency is
  // added by the parallel booking-KV lookups in
  // `_resolveStreetHistoryTrackingLinks`, but bulk in-flight should stay
  // within a small factor of the pool.
  assert.ok(
    kv._state.maxInFlightGets <= 40,
    `max in-flight too high: ${kv._state.maxInFlightGets}`,
  );
  // Prove that we actually parallelized (>4 in flight at some point).
  assert.ok(
    kv._state.maxInFlightGets >= 8,
    `reads did not parallelize (max in-flight ${kv._state.maxInFlightGets})`,
  );
});

// ---------------------------------------------------------------------------
// T3 — canonical order (tripIds order) preserved into the response.
// ---------------------------------------------------------------------------

test("Part D / T3: canonical order matches the input trips-index order (before dedupe/slice)", async () => {
  const { seed, tripIds } = seedTripsIndexed({ count: 12 });
  const kv = makeKV({ seed });
  const res = await worker.fetch(historyReq({ limit: 12 }), makeEnv(kv), makeCtx());
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.count, 12);
  const returnedIds = body.trips.map((t) => t.trip_id);
  // The dedupe step preserves the input order; direct trips with no
  // operational shadow don't get reordered.
  assert.deepEqual(returnedIds, tripIds);
});

// ---------------------------------------------------------------------------
// T4 — malformed / missing records are skipped safely.
// ---------------------------------------------------------------------------

test("Part D / T4: malformed / missing per-trip records are skipped (never fatal)", async () => {
  const { seed } = seedTripsIndexed({ count: 10, malformedIndices: [1, 4, 7] });
  const kv = makeKV({ seed });
  const res = await worker.fetch(historyReq({ limit: 100 }), makeEnv(kv), makeCtx());
  const body = await res.json();
  assert.equal(res.status, 200);
  // 10 in the index, 3 malformed → 7 kept.
  assert.equal(body.count, 7);
});

// ---------------------------------------------------------------------------
// T5 — cross-scope leak protection: another tenant's trip records never leak.
// ---------------------------------------------------------------------------

test("Part D / T5: tenant/driver scope enforcement — records from another tenant are dropped", async () => {
  const seed = {};
  const tripIds = [];
  for (let i = 0; i < 5; i += 1) {
    const id = `own-${i}`;
    tripIds.push(id);
    seed[scopedTripKey(id)] = JSON.stringify(makeTrip({ tripId: id }));
  }
  // Sneak an alien-tenant record at a legitimate scoped key (simulating a
  // corrupted / cross-tenant write): the handler must reject via
  // `recordMatchesTenantCompanyScope`.
  const alienId = "alien-1";
  tripIds.push(alienId);
  seed[scopedTripKey(alienId)] = JSON.stringify(
    makeTrip({ tripId: alienId, tenant_id: "OTHER", company_id: "OTHER" }),
  );
  seed[KEY_TRIPS_DRIVER_INDEX] = JSON.stringify(tripIds);

  const kv = makeKV({ seed });
  const res = await worker.fetch(historyReq({ limit: 100 }), makeEnv(kv), makeCtx());
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.count, 5, "alien-scope record dropped");
  for (const t of body.trips) {
    assert.notEqual(t.trip_id, alienId);
  }
});

// ---------------------------------------------------------------------------
// T6 — legacy scope-migration deferred to ctx.waitUntil.
// ---------------------------------------------------------------------------

test("Part D / T6: legacy scope-migration writes are scheduled via ctx.waitUntil (not blocking)", async () => {
  // Trip lives only under the legacy key AND matches the requested scope.
  const tripId = "legacy_trip_1";
  const seed = {
    [KEY_TRIPS_DRIVER_INDEX]: JSON.stringify([tripId]),
    [legacyTripKey(tripId)]: JSON.stringify(makeTrip({ tripId })),
  };
  const kv = makeKV({ seed });
  const ctx = makeCtx();
  const res = await worker.fetch(historyReq({ limit: 10 }), makeEnv(kv), ctx);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.count, 1);
  // The migration was scheduled through waitUntil — proving the response
  // no longer awaits the write inline like the pre-repair sequential loop
  // did. (JS microtasks may execute the write synchronously after `await`,
  // so we assert on scheduling and eventual persistence, not on the
  // absence of the put at inspection time.)
  assert.ok(ctx.scheduled.length >= 1, "migration should be scheduled via waitUntil");
  await ctx.flush();
  // After background flush the scoped key has been persisted.
  assert.ok(kv._state.putKeys.includes(scopedTripKey(tripId)));
});

// ---------------------------------------------------------------------------
// T7 — deferred index compaction respects size cap (driver = 200).
// ---------------------------------------------------------------------------

test("Part D / T7: cleaned trips-index compaction persists at driver cap after ctx.waitUntil flush", async () => {
  // 300 entries in the index but only 250 exist as records — the handler
  // must persist the compacted index (up to driver cap 200) via waitUntil.
  const seed = {};
  const tripIds = [];
  for (let i = 0; i < 300; i += 1) {
    const id = `trip_${i}`;
    tripIds.push(id);
    if (i < 250) {
      seed[scopedTripKey(id)] = JSON.stringify(makeTrip({ tripId: id }));
    }
  }
  seed[KEY_TRIPS_DRIVER_INDEX] = JSON.stringify(tripIds);
  const kv = makeKV({ seed });
  const ctx = makeCtx();
  await worker.fetch(historyReq({ limit: 200 }), makeEnv(kv), ctx);
  assert.ok(
    ctx.scheduled.length >= 1,
    "compaction should be scheduled via waitUntil",
  );
  await ctx.flush();
  assert.ok(kv._state.putKeys.includes(KEY_TRIPS_DRIVER_INDEX));
  const compacted = JSON.parse(kv.store.get(KEY_TRIPS_DRIVER_INDEX));
  assert.ok(Array.isArray(compacted));
  assert.ok(
    compacted.length <= 200,
    `compacted driver index must respect driver cap (200), got ${compacted.length}`,
  );
});

// ---------------------------------------------------------------------------
// T8 — no ctx: fallback to sequential inline writes (backward-compat).
// ---------------------------------------------------------------------------

test("Part D / T8: without ctx.waitUntil, legacy migration + index compaction still execute inline", async () => {
  const tripId = "legacy_backcompat_1";
  const seed = {
    [KEY_TRIPS_DRIVER_INDEX]: JSON.stringify([tripId]),
    [legacyTripKey(tripId)]: JSON.stringify(makeTrip({ tripId })),
  };
  const kv = makeKV({ seed });
  const res = await worker.fetch(historyReq({ limit: 10 }), makeEnv(kv));
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.count, 1);
  // Without ctx we run the writes inline, so the persistence has already
  // happened by the time the request resolves.
  assert.ok(kv._state.putKeys.includes(scopedTripKey(tripId)));
});
