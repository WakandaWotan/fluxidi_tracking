// P0C — projection-first GET /bookings. Hermetic counting KV only.
//
// Run:
//   node --test workers/booking/booking_list_projection_p0c.test.mjs
//   node --test workers/booking/modules/booking_list_projection.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, {
  rebuildCompanyBookingsListProjectionForScope,
} from "./fluxidi_booking_worker.js";
import {
  companyBookingsListIndexKey,
  upsertCompanyBookingsListIndexBestEffort,
  removeCompanyBookingsListIndexBestEffort,
} from "./modules/booking_indexes.js";
import {
  ACTIONABLE_GRACE_MS,
  companyListProjectionMarkerKey,
  encodeListCursor,
  seedProjectedCompanyPages,
  seedProjectedDriverPages,
  tryListCompanyBookingsProjected,
  tryListDriverBookingsProjected,
  upsertBookingListProjectionsBestEffort,
} from "./modules/booking_list_projection.js";
import { wrapKvBudget } from "./modules/kv_op_budget.js";

const ADMIN = "p0c-admin-token";
const TENANT = "T1";
const COMPANY = "C1";
const OTHER = "C2";
const SCOPE = { tenant_id: TENANT, company_id: COMPANY, hasScope: true };
const OTHER_SCOPE = { tenant_id: TENANT, company_id: OTHER, hasScope: true };

function countingKV(seed = {}) {
  const store = new Map();
  const meta = new Map();
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [], listed: [] };
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
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

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

async function seedCompanySession({ tokenValue, tenantId, companyId }) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `company_admin:session:${hash}:v1`,
    record: {
      role: "company_admin",
      tenant_id: tenantId,
      company_id: companyId,
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

async function seedDriverSession({ tokenValue, tenantId, companyId, driverId }) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `public_driver:session:${hash}:v1`,
    record: {
      role: "driver",
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

function envWith(kv, extra = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    ...extra,
  };
}

function listRow(id, extras = {}) {
  const created = extras.created_at || extras.createdAt || `2026-08-01T00:00:00.000Z`;
  return {
    booking_id: id,
    created_at: created,
    createdAt: created,
    pickup_iso: extras.pickup_iso || new Date(Date.now() + 3600_000).toISOString(),
    from: extras.from || "A",
    to: extras.to || "B",
    status: extras.status || "CONFIRMED",
    customer_name: extras.customer_name || "Pat",
    assigned_driver_id: extras.assigned_driver_id || null,
    assigned_vehicle_id: extras.assigned_vehicle_id || null,
    ...extras,
  };
}

function bookingRec({
  id,
  tenant = TENANT,
  company = COMPANY,
  status = "CONFIRMED",
  pickupIso = new Date(Date.now() + 3600_000).toISOString(),
  createdAt = "2026-08-01T00:00:00.000Z",
  updatedAt = "2026-08-01T00:00:00.000Z",
  driverId = null,
  vehicleId = null,
  extra = {},
}) {
  return {
    booking_id: id,
    bookingId: id,
    tenant_id: tenant,
    company_id: company,
    status,
    created_at: createdAt,
    updated_at: updatedAt,
    pickup_iso: pickupIso,
    assigned_driver_id: driverId,
    assigned_vehicle_id: vehicleId,
    booking: {
      from: "A",
      to: "B",
      pickup_iso: pickupIso,
      pickupStartIso: pickupIso,
      created_at: createdAt,
      customer_name: "Pat",
    },
    ...extra,
  };
}

function indexFor(scope, bookingIds) {
  return {
    version: 1,
    updated_at: new Date().toISOString(),
    items: bookingIds.map((booking_id) => ({
      booking_id,
      sort_ts: Date.now(),
    })),
  };
}

function assertNoBookingHydration(kv) {
  assert.equal(
    kv.counts.listed.some((prefix) => prefix === "booking:" || String(prefix).startsWith("booking:")),
    false,
    "GET must never list prefix booking:",
  );
  assert.equal(
    kv.counts.got.some((key) => String(key).startsWith("booking:")),
    false,
    "GET must never hydrate booking records",
  );
}

async function companyGet(env, { limit = 50, includeHistory = false, cursor = "", companyId = COMPANY } = {}) {
  const params = new URLSearchParams({
    tenant_id: TENANT,
    company_id: companyId,
    limit: String(limit),
  });
  if (includeHistory) params.set("include_history", "1");
  if (cursor) params.set("cursor", cursor);
  return worker.fetch(
    new Request(`https://example.test/bookings?${params}`, {
      method: "GET",
      headers: { "x-admin-token": ADMIN },
    }),
    env,
    {},
  );
}

async function driverGet(env, token, { limit = 50, includeHistory = false, cursor = "" } = {}) {
  const params = new URLSearchParams({ limit: String(limit) });
  if (includeHistory) params.set("include_history", "1");
  if (cursor) params.set("cursor", cursor);
  return worker.fetch(
    new Request(`https://example.test/driver/bookings?${params}`, {
      method: "GET",
      headers: { Authorization: `Bearer ${token}` },
    }),
    env,
    {},
  );
}

test("legacy path: 0 / 3 / 83 bookings hydrate the company index (before counts)", async () => {
  for (const n of [0, 3, 83]) {
    const seed = {};
    const ids = [];
    for (let i = 0; i < n; i += 1) {
      const id = `2026-08-${String(100 + i).padStart(3, "0")}`;
      ids.push(id);
      seed[`booking:${id}`] = bookingRec({
        id,
        createdAt: `2026-08-01T00:${String(i).padStart(2, "0")}:00.000Z`,
      });
    }
    seed[companyBookingsListIndexKey(SCOPE)] = indexFor(SCOPE, ids);
    const kv = countingKV(seed);
    const res = await companyGet(envWith(kv), { limit: 50, includeHistory: true });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.items.length, Math.min(50, n));
    // Marker probe (1) + company index (1) + one get per indexed booking.
    assert.equal(kv.counts.get, 2 + n, `legacy reads at n=${n}`);
    assert.equal(kv.counts.list, 0);
    assert.equal("total_count" in body, false);
  }
});

test("projected path: 0 / 3 / 83 bookings stay inside the hard GET budget", async () => {
  for (const n of [0, 3, 83]) {
    const rows = [];
    for (let i = 0; i < n; i += 1) {
      rows.push(
        listRow(`2026-08-${String(200 + i).padStart(3, "0")}`, {
          created_at: `2026-08-01T00:${String(i % 60).padStart(2, "0")}:00.000Z`,
        }),
      );
    }
    const seed = seedProjectedCompanyPages(SCOPE, rows, { includeHistory: true });
    const kv = countingKV(seed);
    const res = await companyGet(envWith(kv), { limit: 50, includeHistory: true });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.items.length, Math.min(50, n));
    assert.ok(body.count === body.items.length);
    assert.equal(body.total_count, n);
    assert.equal("next_cursor" in body, true);
    assert.equal("has_more" in body, true);
    assert.ok(kv.counts.get <= 5, `reads=${kv.counts.get} n=${n}`);
    assert.ok(kv.counts.list <= 2);
    assert.equal(kv.counts.put, 0);
    assert.equal(kv.counts.delete, 0);
    assertNoBookingHydration(kv);
  }
});

test("10k and 100k: fixed budget and no unrelated booking record fetch", async () => {
  for (const n of [10_000, 100_000]) {
    const visible = [];
    for (let i = 0; i < 200; i += 1) {
      visible.push(
        listRow(`2026-08-${String(300 + i).padStart(3, "0")}`, {
          created_at: `2026-08-02T00:00:${String(i).padStart(2, "0")}.000Z`,
        }),
      );
    }
    const seed = seedProjectedCompanyPages(SCOPE, visible, { includeHistory: true });
    for (let i = 0; i < n; i += 1) {
      seed[`booking:unrelated-${i}`] = { booking_id: `unrelated-${i}`, tenant_id: TENANT, company_id: COMPANY };
    }
    const kv = countingKV(seed);
    const res = await companyGet(envWith(kv), { limit: 50, includeHistory: true });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.items.length, 50);
    assert.equal(body.has_more, true);
    assert.ok(kv.counts.get <= 5, `reads=${kv.counts.get} n=${n}`);
    assert.equal(kv.counts.put, 0);
    assertNoBookingHydration(kv);
    assert.equal(
      kv.counts.got.some((key) => String(key).startsWith("booking:unrelated-")),
      false,
    );
  }
});

test("company first and next pages plus old-client limit 50/200 compatibility", async () => {
  const rows = [];
  for (let i = 0; i < 83; i += 1) {
    rows.push(
      listRow(`2026-08-${String(400 + i).padStart(3, "0")}`, {
        created_at: `2026-08-03T00:${String(i).padStart(2, "0")}:00.000Z`,
        customer_name: "Pat",
        customer_phone: "0032",
      }),
    );
  }
  const kv = countingKV(seedProjectedCompanyPages(SCOPE, rows, { includeHistory: true }));
  const env = envWith(kv);
  const first = await companyGet(env, { limit: 50, includeHistory: true });
  const firstBody = await first.json();
  assert.equal(firstBody.ok, true);
  assert.equal(firstBody.items.length, 50);
  assert.equal(firstBody.count, 50);
  assert.equal(firstBody.total_count, 83);
  assert.ok(firstBody.items[0].booking_id);
  assert.ok(firstBody.items[0].from);
  assert.ok(firstBody.items[0].to);
  assert.ok(firstBody.next_cursor);
  const next = await companyGet(env, {
    limit: 50,
    includeHistory: true,
    cursor: firstBody.next_cursor,
  });
  const nextBody = await next.json();
  assert.equal(nextBody.items.length, 33);
  assert.equal(nextBody.count, 33);
  assert.equal(nextBody.total_count, 83);
  const ids = new Set([
    ...firstBody.items.map((r) => r.booking_id),
    ...nextBody.items.map((r) => r.booking_id),
  ]);
  assert.equal(ids.size, 83);
  const wide = await companyGet(env, { limit: 200, includeHistory: true });
  const wideBody = await wide.json();
  assert.equal(wideBody.items.length, 83);
  assert.equal(wideBody.has_more, false);
});

test("active-only vs include-history filter combinations", async () => {
  const now = Date.now();
  const rows = [
    listRow("2026-08-501", { status: "CONFIRMED", pickup_iso: new Date(now + 3600_000).toISOString() }),
    listRow("2026-08-502", { status: "COMPLETED", pickup_iso: new Date(now - 3600_000).toISOString() }),
    listRow("2026-08-503", { status: "CANCELLED", pickup_iso: new Date(now + 7200_000).toISOString() }),
    listRow("2026-08-504", {
      status: "CONFIRMED",
      pickup_iso: new Date(now - ACTIONABLE_GRACE_MS - 60_000).toISOString(),
    }),
  ];
  const kv = countingKV(seedProjectedCompanyPages(SCOPE, rows, { includeHistory: true }));
  const env = envWith(kv);
  const history = await (await companyGet(env, { includeHistory: true })).json();
  const active = await (await companyGet(env, { includeHistory: false })).json();
  const historyIds = history.items.map((r) => r.booking_id);
  const activeIds = active.items.map((r) => r.booking_id);
  assert.ok(historyIds.includes("2026-08-501"));
  assert.ok(historyIds.includes("2026-08-502"));
  assert.ok(historyIds.includes("2026-08-503"));
  assert.equal(history.total_count, 4);
  assert.deepEqual(activeIds, ["2026-08-501"]);
  assert.equal(active.total_count, 1);
});

test("company/tenant isolation: foreign company rows never appear", async () => {
  const own = seedProjectedCompanyPages(
    SCOPE,
    [listRow("2026-08-601", { created_at: "2026-08-04T00:00:01.000Z" })],
    { includeHistory: true },
  );
  const foreign = seedProjectedCompanyPages(
    OTHER_SCOPE,
    [listRow("2026-08-602", { created_at: "2026-08-04T00:00:02.000Z" })],
    { includeHistory: true },
  );
  const kv = countingKV({ ...own, ...foreign });
  const body = await (await companyGet(envWith(kv), { includeHistory: true })).json();
  const ids = body.items.map((r) => r.booking_id);
  assert.deepEqual(ids, ["2026-08-601"]);
  assert.equal(ids.includes("2026-08-602"), false);
});

test("driver first and next pages use driver projection, not company hydrate", async () => {
  const rows = [];
  for (let i = 0; i < 3; i += 1) {
    rows.push(
      listRow(`2026-08-${String(700 + i).padStart(3, "0")}`, {
        assigned_driver_id: "drv-1",
        pickup_iso: new Date(Date.now() + (i + 1) * 3600_000).toISOString(),
        created_at: `2026-08-05T00:00:0${i}.000Z`,
      }),
    );
  }
  const seed = seedProjectedDriverPages(SCOPE, "drv-1", rows, { includeHistory: false });
  const session = await seedDriverSession({
    tokenValue: "drv-tok",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: "drv-1",
  });
  seed[session.key] = session.record;
  const kv = countingKV(seed);
  const first = await (await driverGet(envWith(kv), "drv-tok", { limit: 2 })).json();
  assert.equal(first.ok, true);
  assert.equal(first.items.length, 2);
  assert.equal(first.has_more, true);
  const next = await (
    await driverGet(envWith(kv), "drv-tok", { limit: 2, cursor: first.next_cursor })
  ).json();
  assert.ok(next.items.length >= 1);
  assertNoBookingHydration(kv);
});

test("create/update/cancel/complete/reassign/delete maintain projections after activation", async () => {
  const seed = seedProjectedCompanyPages(SCOPE, [], { includeHistory: true });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const created = bookingRec({
    id: "2026-08-801",
    createdAt: "2026-08-06T00:00:01.000Z",
    updatedAt: "2026-08-06T00:00:01.000Z",
    driverId: "drv-a",
  });
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-801", created, SCOPE);
  let body = await (await companyGet(env, { includeHistory: true })).json();
  assert.ok(body.items.some((r) => r.booking_id === "2026-08-801"));

  const updated = {
    ...created,
    updated_at: "2026-08-06T00:00:02.000Z",
    booking: { ...created.booking, from: "Ghent", to: "Bruges" },
  };
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-801", updated, SCOPE);
  body = await (await companyGet(env, { includeHistory: true })).json();
  assert.equal(body.items.find((r) => r.booking_id === "2026-08-801")?.from, "Ghent");

  const cancelled = { ...updated, status: "CANCELLED", updated_at: "2026-08-06T00:00:03.000Z" };
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-801", cancelled, SCOPE);
  const active = await (await companyGet(env, { includeHistory: false })).json();
  assert.equal(active.items.some((r) => r.booking_id === "2026-08-801"), false);
  const history = await (await companyGet(env, { includeHistory: true })).json();
  assert.ok(history.items.some((r) => r.booking_id === "2026-08-801"));

  const completed = { ...cancelled, status: "COMPLETED", updated_at: "2026-08-06T00:00:04.000Z" };
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-801", completed, SCOPE);
  const reassigned = {
    ...completed,
    status: "CONFIRMED",
    assigned_driver_id: "drv-b",
    updated_at: "2026-08-06T00:00:05.000Z",
  };
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-801", reassigned, SCOPE);
  await removeCompanyBookingsListIndexBestEffort(env, "2026-08-801", reassigned);
  body = await (await companyGet(env, { includeHistory: true })).json();
  assert.equal(body.items.some((r) => r.booking_id === "2026-08-801"), false);
});

test("duplicate retry is idempotent; stale mutation does not overwrite newer summary", async () => {
  const seed = seedProjectedCompanyPages(SCOPE, [], { includeHistory: true });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const rec = bookingRec({
    id: "2026-08-811",
    updatedAt: "2026-08-07T00:00:02.000Z",
    extra: { booking: { from: "Newer", to: "B", pickup_iso: new Date(Date.now() + 3600_000).toISOString() } },
  });
  await upsertBookingListProjectionsBestEffort(env, "2026-08-811", rec, SCOPE);
  await upsertBookingListProjectionsBestEffort(env, "2026-08-811", rec, SCOPE);
  const stale = bookingRec({
    id: "2026-08-811",
    updatedAt: "2026-08-07T00:00:01.000Z",
    extra: { booking: { from: "Older", to: "B", pickup_iso: new Date(Date.now() + 3600_000).toISOString() } },
  });
  await upsertBookingListProjectionsBestEffort(env, "2026-08-811", stale, SCOPE);
  const body = await (await companyGet(env, { includeHistory: true })).json();
  const row = body.items.find((r) => r.booking_id === "2026-08-811");
  assert.ok(row);
  assert.equal(row.from, "Newer");
});

test("concurrent mutations settle without corrupting the authoritative booking", async () => {
  const seed = seedProjectedCompanyPages(SCOPE, [], { includeHistory: true });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const a = bookingRec({
    id: "2026-08-821",
    updatedAt: "2026-08-08T00:00:01.000Z",
    extra: { booking: { from: "One", to: "B", pickup_iso: new Date(Date.now() + 3600_000).toISOString() } },
  });
  const b = bookingRec({
    id: "2026-08-821",
    updatedAt: "2026-08-08T00:00:03.000Z",
    extra: { booking: { from: "Two", to: "B", pickup_iso: new Date(Date.now() + 3600_000).toISOString() } },
  });
  kv.store.set("booking:2026-08-821", JSON.stringify(b));
  await Promise.all([
    upsertBookingListProjectionsBestEffort(env, "2026-08-821", a, SCOPE),
    upsertBookingListProjectionsBestEffort(env, "2026-08-821", b, SCOPE),
  ]);
  const stored = JSON.parse(kv.store.get("booking:2026-08-821"));
  assert.equal(stored.booking.from, "Two");
  const body = await (await companyGet(env, { includeHistory: true })).json();
  const row = body.items.find((r) => r.booking_id === "2026-08-821");
  assert.ok(row);
  assert.equal(row.from, "Two");
});

test("incomplete rebuild keeps the old-client hydrate path", async () => {
  const seed = {};
  for (let i = 0; i < 250; i += 1) {
    const id = `2026-08-${String(900 + i).padStart(3, "0")}`;
    seed[`booking:${id}`] = bookingRec({
      id,
      createdAt: `2026-07-01T00:00:00.000Z`,
    });
  }
  seed[companyBookingsListIndexKey(SCOPE)] = indexFor(SCOPE, ["2026-08-900"]);
  const kv = countingKV(seed);
  const env = envWith(kv);
  const first = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, { dryRun: false });
  assert.equal(first.ok, true);
  assert.equal(first.complete, false);
  const before = kv.counts.get;
  const res = await companyGet(env, { includeHistory: true, limit: 50 });
  const body = await res.json();
  assert.equal(body.ok, true);
  assert.ok(kv.counts.get > before, "legacy hydrate still runs before complete marker");
  assert.ok(body.items.some((r) => r.booking_id === "2026-08-900"));
});

test("complete rebuild handoff switches GET to projected reads", async () => {
  const seed = {};
  const ids = [];
  for (let i = 0; i < 3; i += 1) {
    const id = `2026-08-${String(930 + i).padStart(3, "0")}`;
    ids.push(id);
    seed[`booking:${id}`] = bookingRec({
      id,
      createdAt: `2026-08-09T00:00:0${i}.000Z`,
    });
  }
  seed[companyBookingsListIndexKey(SCOPE)] = indexFor(SCOPE, ids);
  const kv = countingKV(seed);
  const env = envWith(kv);
  const rebuilt = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, { dryRun: false });
  assert.equal(rebuilt.ok, true);
  assert.equal(rebuilt.complete, true);
  kv.counts.get = 0;
  kv.counts.got = [];
  kv.counts.listed = [];
  kv.counts.list = 0;
  kv.counts.put = 0;
  const body = await (await companyGet(env, { includeHistory: true })).json();
  assert.equal(body.ok, true);
  assert.equal(body.items.length, 3);
  assert.ok(kv.counts.get <= 5);
  assertNoBookingHydration(kv);
});

test("mutation during rebuild is visible after complete handoff", async () => {
  const seed = {};
  for (let i = 0; i < 250; i += 1) {
    const id = `filler-${String(i).padStart(3, "0")}`;
    seed[`booking:${id}`] = bookingRec({
      id,
      createdAt: "2026-07-01T00:00:00.000Z",
    });
  }
  const live = bookingRec({
    id: "2026-08-940",
    createdAt: "2026-09-01T00:00:01.000Z",
    updatedAt: "2026-09-01T00:00:01.000Z",
  });
  seed["booking:2026-08-940"] = live;
  seed[companyBookingsListIndexKey(SCOPE)] = indexFor(SCOPE, ["2026-08-940"]);
  const kv = countingKV(seed);
  const env = envWith(kv);
  const first = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, { dryRun: false });
  assert.equal(first.complete, false);
  const mutated = {
    ...live,
    updated_at: "2026-09-01T00:00:09.000Z",
    booking: { ...live.booking, from: "DuringRebuild" },
  };
  kv.store.set("booking:2026-08-940", JSON.stringify(mutated));
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-940", mutated, SCOPE);
  let cursor = first.cursor;
  let complete = false;
  for (let i = 0; i < 8 && !complete; i += 1) {
    const step = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, {
      dryRun: false,
      cursor,
    });
    complete = step.complete === true;
    cursor = step.cursor;
  }
  assert.equal(complete, true);
  const body = await (await companyGet(env, { includeHistory: true })).json();
  const row = body.items.find((r) => r.booking_id === "2026-08-940");
  assert.ok(row);
  assert.equal(row.from, "DuringRebuild");
});

test("corrupt projection fails safely and does not hydrate booking records", async () => {
  const seed = seedProjectedCompanyPages(
    SCOPE,
    [listRow("2026-08-950")],
    { includeHistory: true },
  );
  const marker = seed[companyListProjectionMarkerKey(SCOPE)];
  const pageKey = Object.keys(seed).find((key) => key.includes(":v:all:p:"));
  delete seed[pageKey];
  seed[companyListProjectionMarkerKey(SCOPE)] = marker;
  for (let i = 0; i < 20; i += 1) {
    seed[`booking:hidden-${i}`] = bookingRec({ id: `hidden-${i}` });
  }
  const kv = countingKV(seed);
  const res = await companyGet(envWith(kv), { includeHistory: true });
  assert.equal(res.status, 503);
  const body = await res.json();
  assert.equal(body.ok, false);
  assert.equal(body.error, "bookings_list_projection_unavailable");
  assertNoBookingHydration(kv);
});

test("old-client response compatibility keeps items/count and existing row fields", async () => {
  const seed = seedProjectedCompanyPages(
    SCOPE,
    [
      listRow("2026-08-960", {
        customer_name: "Pat",
        customer_phone: "0032",
        payment_status: "paid",
      }),
    ],
    { includeHistory: true },
  );
  const body = await (await companyGet(envWith(countingKV(seed)), { limit: 50, includeHistory: true })).json();
  assert.equal(body.ok, true);
  assert.ok(Array.isArray(body.items));
  assert.equal(typeof body.count, "number");
  const row = body.items[0];
  assert.equal(row.booking_id, "2026-08-960");
  assert.equal(row.from, "A");
  assert.equal(row.to, "B");
  assert.equal(row.status, "CONFIRMED");
  assert.equal(row.customer_name, "Pat");
  assert.equal(row.payment_status, "paid");
});

test("hard KV budget wrapper rejects a projected GET that would write", async () => {
  const seed = seedProjectedCompanyPages(SCOPE, [listRow("2026-08-970")], { includeHistory: true });
  const inner = countingKV(seed);
  const wrapped = wrapKvBudget(inner, { maxReads: 5, maxLists: 2, maxWrites: 0, maxDeletes: 0 });
  const listed = await tryListCompanyBookingsProjected(
    { BOOKING_KV: wrapped },
    { limit: 50, includeHistory: true, tenantScope: SCOPE },
  );
  assert.equal(listed.ok, true);
  assert.equal(inner.counts.put, 0);
  await assert.rejects(
    () => wrapped.put("x", "{}"),
    /kv_budget_write/,
  );
});

test("admin rebuild supports dryRun and compare without activating GET", async () => {
  const seed = {
    "booking:2026-08-980": bookingRec({ id: "2026-08-980" }),
  };
  const kv = countingKV(seed);
  const env = envWith(kv);
  const dry = await worker.fetch(
    new Request(
      `https://example.test/admin/bookings-list-projection/rebuild?tenant_id=${TENANT}&company_id=${COMPANY}`,
      {
        method: "POST",
        headers: { "x-admin-token": ADMIN, "content-type": "application/json" },
        body: JSON.stringify({ dryRun: true }),
      },
    ),
    env,
    {},
  );
  assert.equal(dry.status, 200);
  const dryBody = await dry.json();
  assert.equal(dryBody.ok, true);
  assert.equal(dryBody.dry_run, true);
  assert.equal(kv.store.has(companyListProjectionMarkerKey(SCOPE)), false);
  const compare = await worker.fetch(
    new Request(
      `https://example.test/admin/bookings-list-projection/rebuild?tenant_id=${TENANT}&company_id=${COMPANY}`,
      {
        method: "POST",
        headers: { "x-admin-token": ADMIN, "content-type": "application/json" },
        body: JSON.stringify({ compare: true }),
      },
    ),
    env,
    {},
  );
  const compareBody = await compare.json();
  assert.equal(compareBody.ok, true);
  assert.equal(compareBody.compare, true);
});

test("driver projected list does not hydrate the company booking index", async () => {
  const rows = [
    listRow("2026-08-990", {
      assigned_driver_id: "drv-iso",
      pickup_iso: new Date(Date.now() + 3600_000).toISOString(),
    }),
  ];
  const seed = seedProjectedDriverPages(SCOPE, "drv-iso", rows, { includeHistory: false });
  seed[companyBookingsListIndexKey(SCOPE)] = indexFor(SCOPE, ["should-not-load"]);
  seed["booking:should-not-load"] = bookingRec({ id: "should-not-load" });
  const session = await seedDriverSession({
    tokenValue: "drv-iso-tok",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: "drv-iso",
  });
  seed[session.key] = session.record;
  const kv = countingKV(seed);
  const body = await (await driverGet(envWith(kv), "drv-iso-tok")).json();
  assert.equal(body.ok, true);
  assert.equal(body.items[0].booking_id, "2026-08-990");
  assert.equal(kv.counts.got.includes("booking:should-not-load"), false);
});

test("tryListDriverBookingsProjected first/next pages stay bounded", async () => {
  const rows = [];
  for (let i = 0; i < 3; i += 1) {
    rows.push(
      listRow(`2026-08-${String(991 + i).padStart(3, "0")}`, {
        assigned_driver_id: "drv-page",
        pickup_iso: new Date(Date.now() + (i + 1) * 1800_000).toISOString(),
      }),
    );
  }
  const seed = seedProjectedDriverPages(SCOPE, "drv-page", rows, { includeHistory: true });
  const kv = countingKV(seed);
  kv.counts.get = 0;
  kv.counts.got = [];
  const first = await tryListDriverBookingsProjected(
    { BOOKING_KV: kv },
    {
      limit: 2,
      includeHistory: true,
      tenantScope: SCOPE,
      driverId: "drv-page",
      includeDispatch: false,
    },
  );
  assert.equal(first.ok, true);
  assert.equal(first.items.length, 2);
  assert.ok(kv.counts.get <= 5, `first reads=${kv.counts.get}`);
  kv.counts.get = 0;
  kv.counts.got = [];
  const next = await tryListDriverBookingsProjected(
    { BOOKING_KV: kv },
    {
      limit: 2,
      includeHistory: true,
      cursor: first.next_cursor,
      tenantScope: SCOPE,
      driverId: "drv-page",
      includeDispatch: false,
    },
  );
  assert.ok(next.items.length >= 1);
  assert.ok(kv.counts.get <= 5, `next reads=${kv.counts.get}`);
});

function rowDedupeKey(row) {
  return `${row.booking_id || row.id || ""}::${row.leg_id || row.legId || ""}`;
}

function assertPickupSoonest(rows) {
  for (let i = 1; i < rows.length; i += 1) {
    const prev = Date.parse(rows[i - 1].pickup_iso);
    const cur = Date.parse(rows[i].pickup_iso);
    if (prev !== cur) {
      assert.ok(prev <= cur, `order broke at ${rows[i - 1].booking_id} -> ${rows[i].booking_id}`);
      continue;
    }
    const idCmp = String(rows[i - 1].booking_id).localeCompare(String(rows[i].booking_id));
    assert.ok(idCmp <= 0);
  }
}

async function walkDriverProjectedPages(env, token, { limit = 25 } = {}) {
  const collected = [];
  const seen = new Set();
  let cursor = "";
  for (let page = 0; page < 80; page += 1) {
    env.BOOKING_KV.counts.get = 0;
    env.BOOKING_KV.counts.list = 0;
    env.BOOKING_KV.counts.put = 0;
    env.BOOKING_KV.counts.delete = 0;
    env.BOOKING_KV.counts.got = [];
    env.BOOKING_KV.counts.listed = [];
    const res = await driverGet(env, token, { limit, cursor });
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.count, body.items.length);
    const sessionReads = env.BOOKING_KV.counts.got.filter((key) =>
      String(key).includes(":session:"),
    ).length;
    const projectionReads = env.BOOKING_KV.counts.get - sessionReads;
    assert.ok(
      projectionReads <= 5,
      `projection reads=${projectionReads} total=${env.BOOKING_KV.counts.get} page=${page}`,
    );
    assert.ok(env.BOOKING_KV.counts.list <= 2);
    assert.equal(env.BOOKING_KV.counts.put, 0);
    assert.equal(env.BOOKING_KV.counts.delete, 0);
    assertNoBookingHydration(env.BOOKING_KV);
    if (body.has_more === true) {
      assert.ok(String(body.next_cursor || "").trim(), "has_more requires a cursor");
    } else {
      assert.equal(body.next_cursor, null);
    }
    for (const item of body.items) {
      const key = rowDedupeKey(item);
      assert.equal(seen.has(key), false, `duplicate ${key}`);
      seen.add(key);
      collected.push(item);
    }
    if (body.has_more !== true) return collected;
    cursor = body.next_cursor;
  }
  assert.fail("driver pagination did not terminate");
}

async function rebuildUntilComplete(env) {
  let cursor;
  let last;
  for (let i = 0; i < 20; i += 1) {
    last = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, {
      dryRun: false,
      cursor,
    });
    assert.equal(last.ok, true);
    if (last.complete === true) return last;
    cursor = last.cursor;
  }
  assert.fail("company rebuild did not complete");
}

test("projected company limit=25 exposes exact total_count=83", async () => {
  const rows = [];
  for (let i = 0; i < 83; i += 1) {
    rows.push(
      listRow(`2026-08-${String(1100 + i).padStart(4, "0")}`, {
        created_at: `2026-08-10T00:${String(i).padStart(2, "0")}:00.000Z`,
      }),
    );
  }
  const kv = countingKV(seedProjectedCompanyPages(SCOPE, rows, { includeHistory: true }));
  const env = envWith(kv);
  const first = await (await companyGet(env, { limit: 25, includeHistory: true })).json();
  assert.equal(first.count, 25);
  assert.equal(first.items.length, 25);
  assert.equal(first.total_count, 83);
  assert.equal(first.has_more, true);
  assert.ok(String(first.next_cursor || "").trim());
  const next = await (
    await companyGet(env, { limit: 25, includeHistory: true, cursor: first.next_cursor })
  ).json();
  assert.equal(next.total_count, 83);
  assert.equal(next.count, 25);
  assert.equal(next.has_more, true);
});

test("hide and status transition update exact company totals", async () => {
  const seed = seedProjectedCompanyPages(SCOPE, [], { includeHistory: true });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const now = Date.now();
  const rec = bookingRec({
    id: "2026-08-1201",
    createdAt: "2026-08-11T00:00:01.000Z",
    updatedAt: "2026-08-11T00:00:01.000Z",
    pickupIso: new Date(now + 3600_000).toISOString(),
  });
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-1201", rec, SCOPE);
  const history = await (await companyGet(env, { includeHistory: true })).json();
  const active = await (await companyGet(env, { includeHistory: false })).json();
  assert.equal(history.total_count, 1);
  assert.equal(active.total_count, 1);
  const cancelled = {
    ...rec,
    status: "CANCELLED",
    updated_at: "2026-08-11T00:00:02.000Z",
  };
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-1201", cancelled, SCOPE);
  const afterCancelHistory = await (await companyGet(env, { includeHistory: true })).json();
  const afterCancelActive = await (await companyGet(env, { includeHistory: false })).json();
  assert.equal(afterCancelHistory.total_count, 1);
  assert.equal(afterCancelActive.total_count, 0);
  const hidden = {
    ...cancelled,
    company_bookings_hidden: true,
    hidden_from_company_bookings: true,
    updated_at: "2026-08-11T00:00:03.000Z",
  };
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-1201", hidden, SCOPE);
  const afterHide = await (await companyGet(env, { includeHistory: true })).json();
  assert.equal(afterHide.total_count, 0);
  assert.equal(afterHide.items.length, 0);
});

test("driver merge cursor walks assigned+dispatch without duplicates or skips", async () => {
  const now = Date.now();
  const assigned = [];
  const dispatch = [];
  const expected = [];
  for (let i = 0; i < 210; i += 1) {
    const assignedId = `2026-08-A${String(i).padStart(3, "0")}`;
    const assignedRow = listRow(assignedId, {
      assigned_driver_id: "drv-merge",
      pickup_iso: new Date(now + (i * 2 + 1) * 1000).toISOString(),
    });
    assigned.push(assignedRow);
    expected.push(assignedRow);
  }
  for (let i = 0; i < 210; i += 1) {
    const dispatchId = i < 8 ? `2026-08-A${String(i).padStart(3, "0")}` : `2026-08-D${String(i).padStart(3, "0")}`;
    const dispatchRow = listRow(dispatchId, {
      pickup_iso: new Date(now + (i * 2 + 2) * 1000).toISOString(),
    });
    dispatch.push(dispatchRow);
    if (i >= 8) expected.push(dispatchRow);
  }
  expected.sort((a, b) => {
    const pa = Date.parse(a.pickup_iso);
    const pb = Date.parse(b.pickup_iso);
    if (pa !== pb) return pa - pb;
    return String(a.booking_id).localeCompare(String(b.booking_id));
  });
  const seed = seedProjectedDriverPages(SCOPE, "drv-merge", assigned, {
    includeHistory: false,
    dispatchRows: dispatch,
  });
  const session = await seedDriverSession({
    tokenValue: "drv-merge-tok",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: "drv-merge",
  });
  seed[session.key] = session.record;
  for (let i = 0; i < 40; i += 1) {
    seed[`booking:unrelated-merge-${i}`] = bookingRec({ id: `unrelated-merge-${i}` });
  }
  const kv = countingKV(seed);
  const env = envWith(kv);
  const collected = await walkDriverProjectedPages(env, "drv-merge-tok", { limit: 25 });
  assert.equal(collected.length, expected.length);
  assert.deepEqual(
    collected.map((row) => row.booking_id),
    expected.map((row) => row.booking_id),
  );
  assertPickupSoonest(collected);
  const wide = await driverGet(env, "drv-merge-tok", { limit: 50 });
  const wideBody = await wide.json();
  assert.equal(wideBody.ok, true);
  assert.equal(wideBody.count, wideBody.items.length);
  assert.equal(wideBody.items.length, 50);
  assert.equal(wideBody.has_more, true);
  assert.ok(wideBody.next_cursor);
});

test("driver merge corrupt and cross-scope cursors fail closed", async () => {
  const now = Date.now();
  const assigned = [
    listRow("2026-08-1301", {
      assigned_driver_id: "drv-safe",
      pickup_iso: new Date(now + 3600_000).toISOString(),
    }),
  ];
  const dispatch = [
    listRow("2026-08-1302", { pickup_iso: new Date(now + 7200_000).toISOString() }),
  ];
  const seed = seedProjectedDriverPages(SCOPE, "drv-safe", assigned, {
    includeHistory: false,
    dispatchRows: dispatch,
  });
  const session = await seedDriverSession({
    tokenValue: "drv-safe-tok",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: "drv-safe",
  });
  seed[session.key] = session.record;
  seed["booking:hidden-safe"] = bookingRec({ id: "hidden-safe" });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const corrupt = await driverGet(env, "drv-safe-tok", { cursor: "not-a-cursor" });
  assert.equal(corrupt.status, 503);
  assert.equal((await corrupt.json()).ok, false);
  assertNoBookingHydration(kv);
  const foreign = encodeListCursor({
    v: 1,
    kind: "driver_merge",
    g: 1,
    t: TENANT,
    c: OTHER,
    actor_kind: "driver",
    actor_id: "drv-safe",
    assigned: { done: true },
    dispatch: { done: true },
  });
  kv.counts.got = [];
  const cross = await driverGet(env, "drv-safe-tok", { cursor: foreign });
  assert.equal(cross.status, 503);
  assert.equal(
    kv.counts.got.some((key) => String(key).startsWith("booking:")),
    false,
  );
  const stale = encodeListCursor({
    v: 1,
    kind: "driver_merge",
    g: 99,
    t: TENANT,
    c: COMPANY,
    actor_kind: "driver",
    actor_id: "drv-safe",
    assigned: { page_id: "1" },
    dispatch: { page_id: "1" },
  });
  const staleRes = await driverGet(env, "drv-safe-tok", { cursor: stale });
  assert.equal(staleRes.status, 503);
});

test("rebuild then GET /driver/bookings serves assigned and dispatch without hydrate", async () => {
  const now = Date.now();
  const assigned = bookingRec({
    id: "2026-08-1401",
    driverId: "drv-rb",
    pickupIso: new Date(now + 3600_000).toISOString(),
    extra: { payment_mode: "cash" },
  });
  const dispatch = bookingRec({
    id: "2026-08-1402",
    pickupIso: new Date(now + 7200_000).toISOString(),
    extra: { payment_mode: "cash" },
  });
  const hidden = bookingRec({
    id: "2026-08-1403",
    pickupIso: new Date(now + 5400_000).toISOString(),
    extra: { payment_mode: "cash", company_bookings_hidden: true },
  });
  const inactive = bookingRec({
    id: "2026-08-1404",
    status: "COMPLETED",
    pickupIso: new Date(now + 1800_000).toISOString(),
    driverId: "drv-rb",
    extra: { payment_mode: "cash" },
  });
  const seed = {
    "booking:2026-08-1401": assigned,
    "booking:2026-08-1402": dispatch,
    "booking:2026-08-1403": hidden,
    "booking:2026-08-1404": inactive,
  };
  const session = await seedDriverSession({
    tokenValue: "drv-rb-tok",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: "drv-rb",
  });
  seed[session.key] = session.record;
  const kv = countingKV(seed);
  const env = envWith(kv);
  const rebuilt = await rebuildUntilComplete(env);
  assert.equal(rebuilt.complete, true);
  kv.counts.get = 0;
  kv.counts.list = 0;
  kv.counts.put = 0;
  kv.counts.delete = 0;
  kv.counts.got = [];
  kv.counts.listed = [];
  const body = await (await driverGet(env, "drv-rb-tok", { limit: 25 })).json();
  const ids = body.items.map((row) => row.booking_id);
  assert.ok(ids.includes("2026-08-1401"));
  assert.ok(ids.includes("2026-08-1402"));
  assert.equal(ids.includes("2026-08-1403"), false);
  assert.equal(ids.includes("2026-08-1404"), false);
  assert.ok(kv.counts.get <= 5);
  assert.ok(kv.counts.list <= 2);
  assert.equal(kv.counts.put, 0);
  assert.equal(kv.counts.delete, 0);
  assertNoBookingHydration(kv);
});

test("rebuild dispatch is visible to a driver with no assignment marker", async () => {
  const now = Date.now();
  const dispatch = bookingRec({
    id: "2026-08-1411",
    pickupIso: new Date(now + 3600_000).toISOString(),
    extra: { payment_mode: "cash" },
  });
  const seed = { "booking:2026-08-1411": dispatch };
  const session = await seedDriverSession({
    tokenValue: "drv-empty-tok",
    tenantId: TENANT,
    companyId: COMPANY,
    driverId: "drv-empty",
  });
  seed[session.key] = session.record;
  const kv = countingKV(seed);
  const env = envWith(kv);
  const rebuilt = await rebuildUntilComplete(env);
  assert.equal(rebuilt.complete, true);
  kv.counts.get = 0;
  kv.counts.got = [];
  kv.counts.listed = [];
  const body = await (await driverGet(env, "drv-empty-tok", { limit: 25 })).json();
  assert.equal(body.ok, true);
  assert.equal(body.items.some((row) => row.booking_id === "2026-08-1411"), true);
  assertNoBookingHydration(kv);
  assert.ok(kv.counts.get <= 5);
});
