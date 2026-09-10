// P0C — compact booking-list pages stay HTTP/KV-budget readable.
//
// Run:
//   node --test workers/booking/booking_list_projection_compact_p0c.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker, {
  rebuildCompanyBookingsListProjectionForScope,
} from "./fluxidi_booking_worker.js";
import {
  companyBookingsListIndexKey,
  upsertCompanyBookingsListIndexBestEffort,
} from "./modules/booking_indexes.js";
import {
  LIST_PROJ_GET_MAX_LISTS,
  LIST_PROJ_GET_MAX_READS,
  companyListProjectionMarkerKey,
  companyListProjectionPageKey,
  companyListProjectionPendingMarkerKey,
  companyListProjectionRebuildKey,
  isCompanyListProjectionActivated,
  readCompanyListProjectionMarker,
  seedProjectedCompanyPages,
  tryListCompanyBookingsProjected,
  upsertBookingListProjectionsBestEffort,
} from "./modules/booking_list_projection.js";
import { KvBudgetExceededError, wrapKvBudget } from "./modules/kv_op_budget.js";

const ADMIN = "p0c-admin-token";
const TENANT = "T1";
const COMPANY = "C1";
const SCOPE = { tenant_id: TENANT, company_id: COMPANY, hasScope: true };

function countingKV(seed = {}) {
  const store = new Map();
  const meta = new Map();
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [] };
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

function envWith(kv) {
  return { ADMIN_TOKEN: ADMIN, BOOKING_KV: kv };
}

function bookingRec({
  id,
  createdAt = "2026-07-01T00:00:00.000Z",
  updatedAt = "2026-07-01T00:00:00.000Z",
  pickupIso = "2026-07-01T08:00:00.000Z",
  from = "A",
}) {
  return {
    booking_id: id,
    bookingId: id,
    tenant_id: TENANT,
    company_id: COMPANY,
    status: "CONFIRMED",
    created_at: createdAt,
    updated_at: updatedAt,
    pickup_iso: pickupIso,
    assigned_driver_id: null,
    assigned_vehicle_id: null,
    booking: {
      from,
      to: "B",
      pickup_iso: pickupIso,
      pickupStartIso: pickupIso,
      created_at: createdAt,
      customer_name: "Pat",
    },
  };
}

function parseJson(raw) {
  if (raw == null) return null;
  try {
    return typeof raw === "string" ? JSON.parse(raw) : raw;
  } catch (_) {
    return null;
  }
}

function seedBookings(count, { prefix = "filler-", liveId = null } = {}) {
  const seed = {};
  const ids = [];
  for (let i = 0; i < count; i += 1) {
    const id = `${prefix}${String(i).padStart(3, "0")}`;
    ids.push(id);
    seed[`booking:${id}`] = bookingRec({
      id,
      createdAt: "2026-07-01T00:00:00.000Z",
      updatedAt: "2026-07-01T00:00:00.000Z",
      pickupIso: "2026-07-01T08:00:00.000Z",
    });
  }
  if (liveId) {
    ids.push(liveId);
    seed[`booking:${liveId}`] = bookingRec({
      id: liveId,
      createdAt: "2026-09-01T00:00:01.000Z",
      updatedAt: "2026-09-01T00:00:01.000Z",
      pickupIso: "2026-09-01T08:00:00.000Z",
    });
  }
  seed[companyBookingsListIndexKey(SCOPE)] = {
    version: 1,
    updated_at: "2026-07-01T00:00:00.000Z",
    items: ids.slice(0, 1).map((booking_id) => ({ booking_id, sort_ts: 1 })),
  };
  return { seed, ids };
}

async function rebuildUntilComplete(env, { maxSteps = 12 } = {}) {
  let cursor;
  let last;
  for (let i = 0; i < maxSteps; i += 1) {
    last = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, {
      dryRun: false,
      cursor,
    });
    if (last.complete === true) return last;
    cursor = last.cursor;
  }
  assert.fail("rebuild did not complete");
}

function allViewStoredSizes(kv, generation) {
  const marker = parseJson(kv.store.get(companyListProjectionMarkerKey(SCOPE)));
  const pages = marker?.views?.all?.pages || [];
  return pages.map((desc) => {
    const key = companyListProjectionPageKey(SCOPE, generation, "all", desc.id);
    const page = parseJson(kv.store.get(key));
    assert.ok(page && Array.isArray(page.rows), `missing packed page ${desc.id}`);
    return page.rows.length;
  });
}

async function companyGet(env, { limit = 50, cursor = "" } = {}) {
  const params = new URLSearchParams({
    tenant_id: TENANT,
    company_id: COMPANY,
    limit: String(limit),
    include_history: "1",
  });
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

async function walkHttp(env, expectedIds) {
  const collected = [];
  let cursor = "";
  const pages = [];
  for (let i = 0; i < 20; i += 1) {
    const res = await companyGet(env, { cursor });
    const body = await res.json();
    pages.push({ status: res.status, ok: body.ok, error: body.error || null, count: body.items?.length });
    assert.equal(res.status, 200, `HTTP ${res.status} at page ${i}: ${body.error}`);
    assert.equal(body.ok, true);
    assert.equal(body.total_count, expectedIds.length);
    assert.ok((body.items || []).length <= 50);
    if (body.has_more === true) {
      assert.ok(String(body.next_cursor || "").trim());
    } else {
      assert.equal(body.next_cursor, null);
    }
    collected.push(...(body.items || []).map((row) => row.booking_id));
    if (body.has_more !== true) break;
    cursor = body.next_cursor;
  }
  const unique = new Set(collected);
  const missing = expectedIds.filter((id) => !unique.has(id));
  const duplicates = collected.filter((id, idx) => collected.indexOf(id) !== idx);
  return { collected, unique, missing, duplicates, pages };
}

async function walkProjectedWithinBudget(env, expectedIds) {
  const collected = [];
  let cursor = "";
  for (let i = 0; i < 20; i += 1) {
    const wrapped = wrapKvBudget(env.BOOKING_KV, {
      maxReads: LIST_PROJ_GET_MAX_READS,
      maxLists: LIST_PROJ_GET_MAX_LISTS,
      maxWrites: 0,
      maxDeletes: 0,
    });
    const listed = await tryListCompanyBookingsProjected(
      { ...env, BOOKING_KV: wrapped },
      { limit: 50, includeHistory: true, cursor, tenantScope: SCOPE },
    );
    assert.equal(listed.ok, true);
    assert.ok(wrapped.counts.read <= LIST_PROJ_GET_MAX_READS, `reads=${wrapped.counts.read}`);
    collected.push(...(listed.items || []).map((row) => row.booking_id));
    if (listed.has_more !== true) break;
    cursor = listed.next_cursor;
  }
  const unique = new Set(collected);
  return {
    collected,
    unique,
    missing: expectedIds.filter((id) => !unique.has(id)),
    duplicates: collected.filter((id, idx) => collected.indexOf(id) !== idx),
  };
}

test("rebuild 251 packs into 200+51 and HTTP cursor walk stays complete", async () => {
  const { seed, ids } = seedBookings(250, { liveId: "2026-08-940" });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const rebuilt = await rebuildUntilComplete(env);
  assert.equal(rebuilt.ok, true);
  assert.equal(rebuilt.complete, true);
  assert.deepEqual(allViewStoredSizes(kv, rebuilt.generation), [200, 51]);
  const http = await walkHttp(env, ids);
  assert.equal(http.collected.length, 251);
  assert.equal(http.unique.size, 251);
  assert.deepEqual(http.duplicates, []);
  assert.deepEqual(http.missing, []);
  const budget = await walkProjectedWithinBudget(env, ids);
  assert.equal(budget.unique.size, 251);
  assert.deepEqual(budget.duplicates, []);
  assert.deepEqual(budget.missing, []);
});

test("rebuild 401 packs into 200+200+1", async () => {
  const { seed, ids } = seedBookings(401);
  const kv = countingKV(seed);
  const env = envWith(kv);
  const rebuilt = await rebuildUntilComplete(env);
  assert.equal(rebuilt.ok, true);
  assert.deepEqual(allViewStoredSizes(kv, rebuilt.generation), [200, 200, 1]);
  const http = await walkHttp(env, ids);
  assert.equal(http.unique.size, 401);
  assert.deepEqual(http.missing, []);
});

test("newer inserts into a full first page fill the next page", async () => {
  const { seed } = seedBookings(200);
  const kv = countingKV(seed);
  const env = envWith(kv);
  const first = await rebuildUntilComplete(env);
  assert.deepEqual(allViewStoredSizes(kv, first.generation), [200]);
  for (let i = 0; i < 51; i += 1) {
    const id = `newer-${String(i).padStart(3, "0")}`;
    const rec = bookingRec({
      id,
      createdAt: "2026-09-02T00:00:00.000Z",
      updatedAt: `2026-09-02T00:${String(i).padStart(2, "0")}:00.000Z`,
      pickupIso: "2026-09-02T08:00:00.000Z",
    });
    kv.store.set(`booking:${id}`, JSON.stringify(rec));
    await upsertBookingListProjectionsBestEffort(env, id, rec, SCOPE);
  }
  assert.deepEqual(allViewStoredSizes(kv, first.generation), [200, 51]);
});

test("mutation during open rebuild remains visible after compact handoff", async () => {
  const { seed, ids } = seedBookings(250, { liveId: "2026-08-940" });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const first = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, { dryRun: false });
  assert.equal(first.complete, false);
  const live = parseJson(kv.store.get("booking:2026-08-940"));
  const mutated = {
    ...live,
    updated_at: "2026-09-01T00:00:09.000Z",
    booking: { ...live.booking, from: "DuringRebuild" },
  };
  kv.store.set("booking:2026-08-940", JSON.stringify(mutated));
  await upsertCompanyBookingsListIndexBestEffort(env, "2026-08-940", mutated, SCOPE);
  const rebuilt = await rebuildUntilComplete(env);
  assert.equal(rebuilt.ok, true);
  assert.deepEqual(allViewStoredSizes(kv, rebuilt.generation), [200, 51]);
  const http = await walkHttp(env, ids);
  assert.ok(http.collected.includes("2026-08-940"));
  const res = await companyGet(env);
  const body = await res.json();
  const row = body.items.find((item) => item.booking_id === "2026-08-940");
  assert.ok(row);
  assert.equal(row.from, "DuringRebuild");
});

test("mutation after compact remains visible", async () => {
  const { seed, ids } = seedBookings(250, { liveId: "2026-08-940" });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const rebuilt = await rebuildUntilComplete(env);
  const rec = parseJson(kv.store.get("booking:filler-000"));
  const mutated = {
    ...rec,
    updated_at: "2026-09-03T00:00:00.000Z",
    booking: { ...rec.booking, from: "AfterCompact" },
  };
  kv.store.set("booking:filler-000", JSON.stringify(mutated));
  await upsertCompanyBookingsListIndexBestEffort(env, "filler-000", mutated, SCOPE);
  assert.deepEqual(allViewStoredSizes(kv, rebuilt.generation), [200, 51]);
  const http = await walkHttp(env, ids);
  assert.equal(http.unique.size, 251);
  const hit = http.pages;
  assert.ok(hit.every((page) => page.status === 200));
  let found = null;
  let cursor = "";
  for (let i = 0; i < 8; i += 1) {
    const body = await (await companyGet(env, { cursor })).json();
    found = (body.items || []).find((item) => item.booking_id === "filler-000") || found;
    if (found || body.has_more !== true) break;
    cursor = body.next_cursor;
  }
  assert.ok(found);
  assert.equal(found.from, "AfterCompact");
});

test("second rebuild stays compact", async () => {
  const { seed, ids } = seedBookings(250, { liveId: "2026-08-940" });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const first = await rebuildUntilComplete(env);
  const second = await rebuildUntilComplete(env);
  assert.equal(second.generation, first.generation + 1);
  assert.deepEqual(allViewStoredSizes(kv, second.generation), [200, 51]);
  const http = await walkHttp(env, ids);
  assert.equal(http.unique.size, 251);
});

test("old live generation stays readable until pending promote", async () => {
  const three = seedBookings(3, { prefix: "seed-" });
  const kv = countingKV(three.seed);
  const env = envWith(kv);
  const live = await rebuildUntilComplete(env);
  assert.equal(live.generation, 1);
  assert.deepEqual(allViewStoredSizes(kv, 1), [3]);
  const extra = seedBookings(248, { prefix: "more-" });
  for (const [key, value] of Object.entries(extra.seed)) {
    if (key.startsWith("booking:")) kv.store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  const pending = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, { dryRun: false });
  assert.equal(pending.complete, false);
  assert.equal(pending.generation, 2);
  const liveRead = await readCompanyListProjectionMarker(env, SCOPE);
  assert.equal(isCompanyListProjectionActivated(liveRead.marker), true);
  assert.equal(liveRead.marker.generation, 1);
  const first = await (await companyGet(env)).json();
  assert.equal(first.ok, true);
  assert.equal(first.items.length, 3);
  assert.equal(first.total_count, 3);
  assert.ok(kv.store.get(companyListProjectionPendingMarkerKey(SCOPE)));
  const finished = await rebuildUntilComplete(env);
  assert.equal(finished.generation, 2);
  assert.deepEqual(allViewStoredSizes(kv, 2), [200, 51]);
  const after = await (await companyGet(env)).json();
  assert.equal(after.total_count, 251);
});

test("incomplete rebuild does not promote a live generation", async () => {
  const { seed } = seedBookings(250, { liveId: "2026-08-940" });
  const kv = countingKV(seed);
  const env = envWith(kv);
  const first = await rebuildCompanyBookingsListProjectionForScope(env, SCOPE, { dryRun: false });
  assert.equal(first.complete, false);
  const liveRead = await readCompanyListProjectionMarker(env, SCOPE);
  assert.equal(isCompanyListProjectionActivated(liveRead.marker), false);
  const progress = parseJson(kv.store.get(companyListProjectionRebuildKey(SCOPE)));
  assert.equal(progress?.complete, false);
  const res = await companyGet(env);
  const body = await res.json();
  assert.equal(res.status, 200);
  assert.equal(body.ok, true);
  assert.equal("total_count" in body, false);
});

test("missing projection page stays a projection error, not a budget error", async () => {
  const seed = seedProjectedCompanyPages(
    SCOPE,
    [
      {
        booking_id: "2026-08-950",
        created_at: "2026-08-01T00:00:00.000Z",
        pickup_iso: "2026-08-31T12:00:00.000Z",
        from: "A",
        to: "B",
        status: "CONFIRMED",
      },
    ],
    { includeHistory: true },
  );
  const pageKey = Object.keys(seed).find((key) => key.includes(":v:all:p:"));
  delete seed[pageKey];
  const kv = countingKV(seed);
  const res = await companyGet(envWith(kv));
  const body = await res.json();
  assert.equal(res.status, 503);
  assert.equal(body.error, "bookings_list_projection_unavailable");
  assert.notEqual(body.error, "bookings_list_projection_budget_exceeded");
});

test("read-budget overrun is not labeled missing_page", async () => {
  const rows = [];
  for (let i = 0; i < 8; i += 1) {
    rows.push({
      booking_id: `frag-${String(i).padStart(3, "0")}`,
      created_at: `2026-08-01T00:00:0${i}.000Z`,
      pickup_iso: "2026-08-31T12:00:00.000Z",
      from: "A",
      to: "B",
      status: "CONFIRMED",
    });
  }
  const packed = seedProjectedCompanyPages(SCOPE, rows, { includeHistory: true });
  const marker = parseJson(
    typeof packed[companyListProjectionMarkerKey(SCOPE)] === "string"
      ? packed[companyListProjectionMarkerKey(SCOPE)]
      : JSON.stringify(packed[companyListProjectionMarkerKey(SCOPE)]),
  );
  const seed = {};
  const view = { pages: [], row_count: rows.length, next_page_id: rows.length + 1 };
  rows.forEach((row, idx) => {
    const pageId = String(idx + 1);
    view.pages.push({
      id: pageId,
      n: 1,
      hi: { sort_ms: Date.parse(row.created_at), pickup_ms: Date.parse(row.pickup_iso), booking_id: row.booking_id, leg_id: "" },
      lo: { sort_ms: Date.parse(row.created_at), pickup_ms: Date.parse(row.pickup_iso), booking_id: row.booking_id, leg_id: "" },
    });
    seed[companyListProjectionPageKey(SCOPE, 1, "all", pageId)] = {
      version: 1,
      generation: 1,
      view: "all",
      page_id: pageId,
      rows: [row],
    };
  });
  marker.views.all = view;
  seed[companyListProjectionMarkerKey(SCOPE)] = marker;
  const kv = countingKV(seed);
  const env = envWith(kv);
  const res = await companyGet(env);
  const body = await res.json();
  assert.equal(res.status, 503);
  assert.equal(body.error, "bookings_list_projection_budget_exceeded");
  const wrapped = wrapKvBudget(kv, {
    maxReads: LIST_PROJ_GET_MAX_READS,
    maxLists: 2,
    maxWrites: 0,
    maxDeletes: 0,
  });
  await assert.rejects(
    () =>
      tryListCompanyBookingsProjected(
        { BOOKING_KV: wrapped },
        { limit: 50, includeHistory: true, tenantScope: SCOPE },
      ),
    (err) => err instanceof KvBudgetExceededError,
  );
});
