// HTTP-KV-AMPLIFIERS-P0 — projection-first dashboard GET + mutation deltas.
// Hermetic in-memory counting KV only. No live Cloudflare or production IDs.

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, {
  upsertDashboardBookingsKpiProjectionBestEffort,
  removeDashboardBookingsKpiProjectionBestEffort,
  _applyDashboardBookingsKpiContributionDelta,
  computeDashboardBookingKpiContribution,
  _loadScopedActiveDemandWithRepair,
  dashboardBookingsKpiAggregateKey,
} from "./fluxidi_booking_worker.js";

const ADMIN = "http-kv-admin-token";
const TENANT = "T1";
const COMPANY = "C1";
const MONTH = "2026-07";
const AGG_KEY = `tenant:${TENANT}:company:${COMPANY}:dashboard:bookings_kpis:v1`;
const DEMAND_KEY = `tenant:${TENANT}:company:${COMPANY}:booking:demand:index:v1`;
const REPAIR_MARKER_KEY = `tenant:${TENANT}:company:${COMPANY}:booking:demand:repair_marker:v1`;
const FINANCE_KEY = `tenant:${TENANT}:company:${COMPANY}:dashboard:booking_finance:month:${MONTH}:v1`;

function countingKV(seed = {}) {
  const store = new Map();
  const meta = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [], listed: [] };
  return {
    store,
    meta,
    counts,
    async get(key, opts) {
      counts.get += 1;
      counts.got.push(key);
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || (opts && opts.type === "json");
      if (asJson) {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val, opts) {
      counts.put += 1;
      store.set(key, val);
      if (opts?.metadata) meta.set(key, opts.metadata);
    },
    async delete(key) {
      counts.delete += 1;
      store.delete(key);
      meta.delete(key);
    },
    async list({ prefix = "", limit = 1000, cursor } = {}) {
      counts.list += 1;
      counts.listed.push(prefix);
      const names = [...store.keys()].filter((k) => k.startsWith(prefix)).sort();
      const start = cursor ? Number(cursor) || 0 : 0;
      const page = names.slice(start, start + limit);
      const next = start + page.length;
      return {
        keys: page.map((name) => ({ name, metadata: meta.get(name) || null })),
        list_complete: next >= names.length,
        cursor: next >= names.length ? undefined : String(next),
      };
    },
  };
}

function cleanProjection(open = 7) {
  const now = "2026-07-24T18:00:00.000Z";
  return {
    version: 1,
    source: "projection",
    projection_complete: true,
    projection_health: "ok",
    updated_at: now,
    evaluated_at: now,
    counters: {
      considered_open: open,
      excluded_terminal: 2,
      excluded_payment_failed: 0,
      excluded_stale_payment_pending: 0,
      excluded_hidden: 0,
      excluded_missing_pickup_time: 0,
      excluded_stale_past_pickup: 0,
      excluded_non_canonical_provisional_record: 0,
      excluded_reference_only_provisional_record: 0,
      excluded_duplicate_identity: 0,
      excluded_terminal_identity: 0,
      excluded_out_of_scope: 0,
      excluded_invalid_record: 0,
    },
  };
}

function makeEnv(bookingKv, trackingKv = countingKV()) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: bookingKv,
    FLUXIDI_TRACKING: trackingKv,
  };
}

function kpisReq() {
  return new Request(
    `https://booking.internal/admin/dashboard/bookings-kpis?tenant_id=${TENANT}&company_id=${COMPANY}&month=${MONTH}`,
    { method: "GET", headers: { "x-admin-token": ADMIN } },
  );
}

function assertNoBookingHistoryScan(bookingKv) {
  assert.equal(
    bookingKv.counts.listed.some((prefix) => prefix === "booking:" || prefix.startsWith("booking:")),
    false,
    "GET must never list prefix booking:",
  );
  assert.equal(
    bookingKv.counts.got.some((key) => String(key).startsWith("booking:")),
    false,
    "GET must never get-every-booking",
  );
}

function openBooking(bookingId, extras = {}) {
  return {
    booking_id: bookingId,
    tenant_id: TENANT,
    company_id: COMPANY,
    status: "CONFIRMED",
    payment_status: "unpaid",
    pickup_at: new Date(Date.now() + 2 * 60 * 60 * 1000).toISOString(),
    updated_at: extras.updated_at || new Date().toISOString(),
    ...extras,
  };
}

const SCOPE = { tenant_id: TENANT, company_id: COMPANY, hasScope: true };

test("clean bookings KPI projection: exact contract, <=5 reads, 0 lists, 0 writes", async () => {
  const bookingKv = countingKV({
    [AGG_KEY]: cleanProjection(7),
  });
  const trackingKv = countingKV({
    [FINANCE_KEY]: {
      monthly_paid_bookings_income_cents: 12000,
      monthly_paid_bookings_count: 3,
      updated_at: "2026-07-24T18:00:00.000Z",
    },
  });
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv, trackingKv));
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.open_bookings_count, 7);
  assert.equal(body.considered_open, 7);
  assert.equal(body.excluded_terminal, 2);
  assert.equal(body.month, MONTH);
  assert.equal(body.monthly_income_cents, 12000);
  assert.equal(body.source, "projection");
  assert.equal(body.projection_health, "ok");
  assert.equal(body.counts_are_authoritative, true);
  assert.ok(Array.isArray(body.excluded_terminal_statuses));
  assert.ok(body.scan_stats && typeof body.scan_stats === "object");
  assert.ok(bookingKv.counts.get <= 5, `reads=${bookingKv.counts.get}`);
  assert.equal(bookingKv.counts.list, 0);
  assert.equal(bookingKv.counts.put, 0);
  assert.equal(bookingKv.counts.delete, 0);
  assertNoBookingHistoryScan(bookingKv);
});

test("dirty projection: last valid values + degraded metadata, no booking: list", async () => {
  const dirty = {
    ...cleanProjection(4),
    projection_complete: false,
    projection_health: "dirty",
    projection_dirty_reason: "contribution_upsert_failed",
  };
  const bookingKv = countingKV({ [AGG_KEY]: dirty });
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv));
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal(body.open_bookings_count, 4);
  assert.equal(body.degraded, true);
  assert.equal(body.projection_health, "dirty");
  assert.equal(body.counts_are_authoritative, false);
  assert.equal(bookingKv.counts.list, 0);
  assert.equal(bookingKv.counts.put, 0);
  assertNoBookingHistoryScan(bookingKv);
});

test("missing projection: non-fabricated pending response, bounded, Flutter-usable", async () => {
  const bookingKv = countingKV({});
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv));
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, false);
  assert.equal(body.data_pending, true);
  assert.equal(body.projection_health, "missing");
  assert.equal(body.error, "dashboard_bookings_kpi_index_unavailable");
  assert.notEqual(body.projection_health, "ok");
  assert.equal(bookingKv.counts.list, 0);
  assert.ok(bookingKv.counts.get <= 5);
  assertNoBookingHistoryScan(bookingKv);
});

test("10k historical booking keys: GET op count stays constant and never reads them", async () => {
  const seed = { [AGG_KEY]: cleanProjection(9) };
  for (let i = 0; i < 10_000; i += 1) {
    seed[`booking:hist-${i}`] = { booking_id: `hist-${i}`, tenant_id: TENANT, company_id: COMPANY };
  }
  const bookingKv = countingKV(seed);
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv));
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.open_bookings_count, 9);
  const firstReads = bookingKv.counts.get;
  const firstLists = bookingKv.counts.list;
  assert.ok(firstReads <= 5);
  assert.equal(firstLists, 0);
  assertNoBookingHistoryScan(bookingKv);
});

test("100k historical booking keys: GET op count stays constant and never reads them", async () => {
  const seed = { [AGG_KEY]: cleanProjection(11) };
  for (let i = 0; i < 100_000; i += 1) {
    seed[`booking:hist-${i}`] = { id: i };
  }
  const bookingKv = countingKV(seed);
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv));
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.open_bookings_count, 11);
  assert.ok(bookingKv.counts.get <= 5);
  assert.equal(bookingKv.counts.list, 0);
  assertNoBookingHistoryScan(bookingKv);
});

test("three concurrent bookings-kpis GETs: no rebuild, bounded constant cost", async () => {
  const bookingKv = countingKV({ [AGG_KEY]: cleanProjection(5) });
  const env = makeEnv(bookingKv);
  const results = await Promise.all([
    worker.fetch(kpisReq(), env),
    worker.fetch(kpisReq(), env),
    worker.fetch(kpisReq(), env),
  ]);
  for (const res of results) {
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.open_bookings_count, 5);
    assert.equal(body.source, "projection");
  }
  assert.equal(bookingKv.counts.list, 0);
  assert.equal(bookingKv.counts.put, 0);
  assert.equal(bookingKv.counts.delete, 0);
  assert.ok(bookingKv.counts.get <= 15);
  assertNoBookingHistoryScan(bookingKv);
});

test("fleet-demand index five minutes stale: no namespace scan, index is used", async () => {
  const staleAt = new Date(Date.now() - 6 * 60 * 1000).toISOString();
  const bookingKv = countingKV({
    [DEMAND_KEY]: {
      tenant_id: TENANT,
      company_id: COMPANY,
      updated_at: staleAt,
      index_updated_at: staleAt,
      items: [
        {
          booking_id: "B-open",
          pickup_ms: Date.now() + 3_600_000,
          service_min: 45,
          dropoff_at_ms: Date.now() + 3_600_000 + 45 * 60_000,
          lifecycle: "confirmed",
          tier: "comfort",
          pax: 2,
          bags: 1,
        },
      ],
    },
  });
  const loaded = await _loadScopedActiveDemandWithRepair(
    { BOOKING_KV: bookingKv },
    SCOPE,
    { staleAfterMs: 5 * 60 * 1000 },
  );
  assert.equal(loaded.ok, true);
  assert.equal(loaded.demand_index_rebuilt, false);
  assert.equal(loaded.items.length, 1);
  assert.equal(bookingKv.counts.list, 0);
  assert.equal(
    bookingKv.counts.got.some((key) => String(key).startsWith("booking:")),
    false,
  );
});

test("missing/corrupt fleet-demand index: no false availability, no full scan, marker only", async () => {
  const bookingKv = countingKV({
    [DEMAND_KEY]: { items: "corrupt", updated_at: new Date().toISOString() },
  });
  const loaded = await _loadScopedActiveDemandWithRepair(
    { BOOKING_KV: bookingKv },
    SCOPE,
  );
  assert.equal(loaded.ok, false);
  assert.equal(loaded.demand_index_rebuilt, false);
  assert.equal(Array.isArray(loaded.items) && loaded.items.length === 0, true);
  assert.equal(bookingKv.counts.list, 0);
  assert.ok(bookingKv.store.has(REPAIR_MARKER_KEY));
  assert.ok(bookingKv.counts.put <= 1);
  assert.equal(
    bookingKv.counts.got.some((key) => String(key).startsWith("booking:")),
    false,
  );
});

test("booking create/update/cancel/complete deltas are idempotent", async () => {
  const bookingKv = countingKV({});
  const env = { BOOKING_KV: bookingKv };
  const created = openBooking("B-delta");
  const first = await upsertDashboardBookingsKpiProjectionBestEffort(env, "B-delta", created, SCOPE);
  assert.equal(first.ok, true);
  const agg1 = JSON.parse(bookingKv.store.get(AGG_KEY));
  assert.equal(agg1.counters.considered_open, 1);
  assert.equal(agg1.projection_health, "ok");
  assert.notEqual(agg1.projection_health, "dirty");
  const retry = await upsertDashboardBookingsKpiProjectionBestEffort(env, "B-delta", created, SCOPE);
  assert.equal(retry.unchanged, true);
  const aggRetry = JSON.parse(bookingKv.store.get(AGG_KEY));
  assert.equal(aggRetry.counters.considered_open, 1);
  const cancelled = openBooking("B-delta", { status: "CANCELLED" });
  await upsertDashboardBookingsKpiProjectionBestEffort(env, "B-delta", cancelled, SCOPE);
  const aggCancel = JSON.parse(bookingKv.store.get(AGG_KEY));
  assert.equal(aggCancel.counters.considered_open, 0);
  await upsertDashboardBookingsKpiProjectionBestEffort(env, "B-delta", cancelled, SCOPE);
  assert.equal(JSON.parse(bookingKv.store.get(AGG_KEY)).counters.considered_open, 0);
  const completed = openBooking("B-next", { status: "CONFIRMED" });
  await upsertDashboardBookingsKpiProjectionBestEffort(env, "B-next", completed, SCOPE);
  assert.equal(JSON.parse(bookingKv.store.get(AGG_KEY)).counters.considered_open, 1);
  await upsertDashboardBookingsKpiProjectionBestEffort(
    env,
    "B-next",
    openBooking("B-next", { status: "COMPLETED" }),
    SCOPE,
  );
  assert.equal(JSON.parse(bookingKv.store.get(AGG_KEY)).counters.considered_open, 0);
  await removeDashboardBookingsKpiProjectionBestEffort(env, "B-next", SCOPE);
  await removeDashboardBookingsKpiProjectionBestEffort(env, "B-next", SCOPE);
  assert.equal(JSON.parse(bookingKv.store.get(AGG_KEY)).counters.considered_open, 0);
  assert.equal(JSON.parse(bookingKv.store.get(AGG_KEY)).projection_health, "ok");
});

test("GET never lists booking: even when the projection is missing and history exists", async () => {
  const seed = {};
  for (let i = 0; i < 250; i += 1) {
    seed[`booking:open-${i}`] = openBooking(`open-${i}`);
  }
  const bookingKv = countingKV(seed);
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv));
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.data_pending, true);
  assertNoBookingHistoryScan(bookingKv);
});

test("legacy dirty snapshot keeps last counters and never double-counts", async () => {
  const bookingKv = countingKV({
    [AGG_KEY]: {
      ...cleanProjection(4),
      projection_complete: false,
      projection_health: "dirty",
      projection_dirty_reason: "contribution_upsert",
    },
  });
  const env = { BOOKING_KV: bookingKv };
  const rec = openBooking("B-legacy");
  const out = await upsertDashboardBookingsKpiProjectionBestEffort(env, "B-legacy", rec, SCOPE);
  assert.equal(out.ok, true);
  const agg = JSON.parse(bookingKv.store.get(AGG_KEY));
  assert.equal(agg.counters.considered_open, 4);
  assert.equal(agg.projection_health, "dirty");
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv));
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.equal(body.open_bookings_count, 4);
  assert.equal(body.degraded, true);
  assertNoBookingHistoryScan(bookingKv);
});

test("exported aggregate key stays company-scoped", () => {
  assert.equal(dashboardBookingsKpiAggregateKey(SCOPE), AGG_KEY);
});

function concurrentReadKV(seed, { staleGets = 2, key = AGG_KEY } = {}) {
  const kv = countingKV(seed);
  const snapshot = seed[key]
    ? typeof seed[key] === "string"
      ? seed[key]
      : JSON.stringify(seed[key])
    : null;
  let staleLeft = staleGets;
  const origGet = kv.get.bind(kv);
  kv.get = async (k, opts) => {
    if (k === key && staleLeft > 0) {
      staleLeft -= 1;
      if (snapshot == null) return null;
      const asJson = opts === "json" || (opts && opts.type === "json");
      return asJson ? JSON.parse(snapshot) : snapshot;
    }
    return origGet(k, opts);
  };
  return kv;
}

function lostPutKV(seed, { lostPuts = 3, targetKey = AGG_KEY } = {}) {
  const kv = countingKV(seed);
  const origPut = kv.put.bind(kv);
  kv.remainingLostPuts = lostPuts;
  kv.put = async (key, val, opts) => {
    if (key === targetKey && kv.remainingLostPuts > 0) {
      kv.remainingLostPuts -= 1;
      kv.counts.put += 1;
      return;
    }
    return origPut(key, val, opts);
  };
  return kv;
}

function financeSeed() {
  return {
    monthly_paid_bookings_income_cents: 12000,
    monthly_paid_bookings_count: 3,
    updated_at: "2026-07-24T18:00:00.000Z",
  };
}

function assertNoIncorrectAuthoritative(body, expectedOpen, incomeCents = 12000) {
  assert.equal(body.monthly_income_cents, incomeCents);
  if (body.counts_are_authoritative === true) {
    assert.equal(body.ok, true);
    assert.equal(body.projection_health, "ok");
    assert.equal(body.degraded, undefined);
    assert.equal(body.open_bookings_count, expectedOpen);
    return "authoritative";
  }
  assert.equal(body.counts_are_authoritative, false);
  assert.notEqual(body.projection_health, "ok");
  return "degraded";
}

test("plain same-snapshot LWW of two deltas loses a booking count", () => {
  const a = computeDashboardBookingKpiContribution("B-lww-a", openBooking("B-lww-a"), SCOPE);
  const b = computeDashboardBookingKpiContribution("B-lww-b", openBooking("B-lww-b"), SCOPE);
  const fromA = _applyDashboardBookingsKpiContributionDelta(null, null, a).aggregate;
  const fromB = _applyDashboardBookingsKpiContributionDelta(null, null, b).aggregate;
  assert.equal(fromA.counters.considered_open, 1);
  assert.equal(fromB.counters.considered_open, 1);
  const merged = _applyDashboardBookingsKpiContributionDelta(fromA, null, b).aggregate;
  assert.equal(merged.counters.considered_open, 2);
});

test("two concurrent creates for the same company keep a correct or degraded projection", async () => {
  const bookingKv = concurrentReadKV({}, { staleGets: 4 });
  const trackingKv = countingKV({ [FINANCE_KEY]: financeSeed() });
  const env = { BOOKING_KV: bookingKv };
  const [first, second] = await Promise.all([
    upsertDashboardBookingsKpiProjectionBestEffort(env, "B-c1", openBooking("B-c1"), SCOPE),
    upsertDashboardBookingsKpiProjectionBestEffort(env, "B-c2", openBooking("B-c2"), SCOPE),
  ]);
  assert.equal(first.ok, true);
  assert.equal(second.ok, true);
  const agg = JSON.parse(bookingKv.store.get(AGG_KEY));
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv, trackingKv));
  const body = await res.json();
  const mode = assertNoIncorrectAuthoritative(body, 2);
  if (mode === "authoritative") {
    assert.equal(agg.counters.considered_open, 2);
    assert.equal(agg.projection_health, "ok");
  } else {
    assert.equal(body.degraded, true);
    assert.notEqual(agg.projection_health, "ok");
  }
  assertNoBookingHistoryScan(bookingKv);
});

test("create plus cancel/update concurrently leaves a correct or degraded projection", async () => {
  const bookingKv = countingKV({});
  const trackingKv = countingKV({ [FINANCE_KEY]: financeSeed() });
  const env = { BOOKING_KV: bookingKv };
  await upsertDashboardBookingsKpiProjectionBestEffort(
    env,
    "B-keep",
    openBooking("B-keep", { updated_at: "2026-07-24T18:00:00.000Z" }),
    SCOPE,
  );
  const racing = concurrentReadKV(Object.fromEntries(bookingKv.store.entries()), {
    staleGets: 4,
  });
  const racingEnv = { BOOKING_KV: racing };
  const createdAt = "2026-07-24T18:02:00.000Z";
  const cancelledAt = "2026-07-24T18:03:00.000Z";
  await Promise.all([
    upsertDashboardBookingsKpiProjectionBestEffort(
      racingEnv,
      "B-new",
      openBooking("B-new", { updated_at: createdAt }),
      SCOPE,
    ),
    upsertDashboardBookingsKpiProjectionBestEffort(
      racingEnv,
      "B-keep",
      openBooking("B-keep", { status: "CANCELLED", updated_at: cancelledAt }),
      SCOPE,
    ),
  ]);
  const res = await worker.fetch(kpisReq(), makeEnv(racing, trackingKv));
  const body = await res.json();
  const mode = assertNoIncorrectAuthoritative(body, 1);
  if (mode === "authoritative") {
    assert.equal(JSON.parse(racing.store.get(AGG_KEY)).counters.considered_open, 1);
  } else {
    assert.equal(body.degraded, true);
  }
  assertNoBookingHistoryScan(racing);
});

test("duplicate retry of one transition while another booking changes stays correct or degraded", async () => {
  const bookingKv = countingKV({});
  const trackingKv = countingKV({ [FINANCE_KEY]: financeSeed() });
  const env = { BOOKING_KV: bookingKv };
  const firstRec = openBooking("B-dup", { updated_at: "2026-07-24T18:00:00.000Z" });
  await upsertDashboardBookingsKpiProjectionBestEffort(env, "B-dup", firstRec, SCOPE);
  const racing = concurrentReadKV(Object.fromEntries(bookingKv.store.entries()), {
    staleGets: 4,
  });
  const racingEnv = { BOOKING_KV: racing };
  const [retry, other] = await Promise.all([
    upsertDashboardBookingsKpiProjectionBestEffort(racingEnv, "B-dup", firstRec, SCOPE),
    upsertDashboardBookingsKpiProjectionBestEffort(
      racingEnv,
      "B-other",
      openBooking("B-other", { updated_at: "2026-07-24T18:02:00.000Z" }),
      SCOPE,
    ),
  ]);
  assert.equal(retry.ok, true);
  assert.equal(other.ok, true);
  const res = await worker.fetch(kpisReq(), makeEnv(racing, trackingKv));
  const body = await res.json();
  const mode = assertNoIncorrectAuthoritative(body, 2);
  if (mode === "authoritative") {
    assert.equal(JSON.parse(racing.store.get(AGG_KEY)).counters.considered_open, 2);
  } else {
    assert.equal(body.degraded, true);
  }
  assertNoBookingHistoryScan(racing);
});

test("out-of-order cancel then stale create does not reopen the booking", async () => {
  const bookingKv = countingKV({});
  const trackingKv = countingKV({ [FINANCE_KEY]: financeSeed() });
  const env = { BOOKING_KV: bookingKv };
  await upsertDashboardBookingsKpiProjectionBestEffort(
    env,
    "B-ooo",
    openBooking("B-ooo", { updated_at: "2026-07-24T18:00:00.000Z" }),
    SCOPE,
  );
  await upsertDashboardBookingsKpiProjectionBestEffort(
    env,
    "B-ooo",
    openBooking("B-ooo", { status: "CANCELLED", updated_at: "2026-07-24T18:05:00.000Z" }),
    SCOPE,
  );
  await upsertDashboardBookingsKpiProjectionBestEffort(
    env,
    "B-ooo",
    openBooking("B-ooo", { updated_at: "2026-07-24T18:01:00.000Z" }),
    SCOPE,
  );
  const agg = JSON.parse(bookingKv.store.get(AGG_KEY));
  assert.equal(agg.counters.considered_open, 0);
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv, trackingKv));
  const body = await res.json();
  const mode = assertNoIncorrectAuthoritative(body, 0);
  if (mode === "authoritative") {
    assert.equal(body.open_bookings_count, 0);
  }
  assertNoBookingHistoryScan(bookingKv);
});

test("unresolved KV race marks dirty and never returns an authoritative KPI", async () => {
  const bookingKv = lostPutKV({}, { lostPuts: 3 });
  const trackingKv = countingKV({ [FINANCE_KEY]: financeSeed() });
  const env = { BOOKING_KV: bookingKv };
  const out = await upsertDashboardBookingsKpiProjectionBestEffort(
    env,
    "B-race",
    openBooking("B-race"),
    SCOPE,
  );
  assert.equal(out.ok, true);
  assert.equal(out.conflict, true);
  assert.equal(out.aggregate_dirty, true);
  const raw = bookingKv.store.get(AGG_KEY);
  if (raw) {
    const agg = JSON.parse(raw);
    assert.equal(agg.projection_health, "dirty");
    assert.equal(agg.projection_dirty_reason, "concurrent_rmw_unresolved");
  }
  const res = await worker.fetch(kpisReq(), makeEnv(bookingKv, trackingKv));
  const body = await res.json();
  assert.equal(body.counts_are_authoritative, false);
  assert.notEqual(body.projection_health, "ok");
  if (body.ok === true) {
    assert.equal(body.degraded, true);
    assert.equal(body.monthly_income_cents, 12000);
  } else {
    assert.equal(body.data_pending, true);
  }
  assertNoBookingHistoryScan(bookingKv);
});
