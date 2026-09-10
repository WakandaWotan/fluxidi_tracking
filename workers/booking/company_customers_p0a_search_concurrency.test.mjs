// P0A follow-up checks: search beyond the first GET, concurrent writes.
//
// Run:
//   node --test workers/booking/company_customers_p0a_search_concurrency.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  createCompanyCustomer,
  updateCompanyCustomer,
  CUSTOMER_GET_MAX_READS,
  CUSTOMER_LIST_PAGE_SIZE,
  CUSTOMER_SEARCH_PAGE_READS,
} from "./modules/company_customers.mjs";

const ADMIN = "p0a-admin-token";
const TENANT_A = "TA";
const COMPANY_A = "CA";
const SCOPE_A = { tenant_id: TENANT_A, company_id: COMPANY_A, hasScope: true };

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
      await Promise.resolve();
      counts.get += 1;
      counts.got.push(key);
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || (opts && opts.type === "json");
      if (asJson) {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch {
          return null;
        }
      }
      return raw;
    },
    async put(key, val, opts) {
      await Promise.resolve();
      counts.put += 1;
      store.set(key, val);
      if (opts?.metadata) meta.set(key, opts.metadata);
    },
    async delete(key) {
      await Promise.resolve();
      counts.delete += 1;
      store.delete(key);
      meta.delete(key);
    },
    async list() {
      counts.list += 1;
      return { keys: [], list_complete: true };
    },
  };
}

function envWith(kv, extra = {}) {
  return { ADMIN_TOKEN: ADMIN, BOOKING_KV: kv, ...extra };
}

async function searchGet(env, { q, cursor = "", limit = 50 } = {}) {
  const url = new URL("https://example.test/company/customers");
  url.searchParams.set("tenant_id", TENANT_A);
  url.searchParams.set("company_id", COMPANY_A);
  url.searchParams.set("q", q);
  url.searchParams.set("limit", String(limit));
  if (cursor) url.searchParams.set("cursor", cursor);
  const beforeGets = env.BOOKING_KV.counts.get;
  const beforeLists = env.BOOKING_KV.counts.list;
  const res = await worker.fetch(
    new Request(url, { headers: { "x-admin-token": ADMIN } }),
    env,
    {},
  );
  const got = env.BOOKING_KV.counts.get - beforeGets;
  const listed = env.BOOKING_KV.counts.list - beforeLists;
  assert.ok(got <= CUSTOMER_GET_MAX_READS, `search GET used ${got} reads`);
  assert.equal(listed, 0);
  const body = await res.json();
  return { res, body };
}

test("search keeps a follow-up cursor when the match is past the first GET page budget", async () => {
  const kv = countingKV();
  const env = envWith(kv, { CUSTOMER_NOW_MS: 1_700_000_000_000 });
  const needed =
    CUSTOMER_LIST_PAGE_SIZE * CUSTOMER_SEARCH_PAGE_READS + 1;
  let needleId = "";
  env.CUSTOMER_NOW_MS = 1_700_000_000_000;
  const needle = await createCompanyCustomer(env, {
    scope: SCOPE_A,
    body: { display_name: "Needle Only", email: "unique-needle@ex.test" },
  });
  assert.equal(needle.ok, true);
  needleId = needle.body.customer.customer_id;
  for (let i = 0; i < needed; i += 1) {
    env.CUSTOMER_NOW_MS = 1_700_000_000_000 + (i + 1) * 1000;
    const result = await createCompanyCustomer(env, {
      scope: SCOPE_A,
      body: { display_name: `Filler ${i}`, email: `filler${i}@ex.test` },
    });
    assert.equal(result.ok, true);
  }

  const first = await searchGet(env, { q: "unique-needle" });
  assert.equal(first.res.status, 200);
  assert.equal(first.body.ok, true);
  assert.equal(
    first.body.items.some((row) => row.customer_id === needleId),
    false,
    "first bounded search GET must not already include the oldest needle",
  );
  assert.equal(first.body.has_more, true, "empty first page must not look final");
  assert.ok(String(first.body.next_cursor || "").trim(), "follow-up cursor required");

  let cursor = first.body.next_cursor;
  let found = false;
  const seen = new Set();
  for (let hop = 0; hop < 12; hop += 1) {
    const page = await searchGet(env, { q: "unique-needle", cursor });
    assert.equal(page.res.status, 200);
    for (const item of page.body.items) {
      assert.equal(seen.has(item.customer_id), false);
      seen.add(item.customer_id);
      if (item.customer_id === needleId) found = true;
    }
    if (found) break;
    assert.equal(page.body.has_more, true, "must not end while unread pages remain");
    cursor = page.body.next_cursor;
  }
  assert.equal(found, true);
});

test("concurrent same-revision patches are not atomic on Workers KV", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createCompanyCustomer(env, {
    scope: SCOPE_A,
    body: { display_name: "Rev Race", email: "rev-race@ex.test" },
  });
  const id = created.body.customer.customer_id;
  const [left, right] = await Promise.all([
    updateCompanyCustomer(env, {
      scope: SCOPE_A,
      customerId: id,
      body: { revision: 1, display_name: "Left Win", email: "rev-race@ex.test" },
    }),
    updateCompanyCustomer(env, {
      scope: SCOPE_A,
      customerId: id,
      body: { revision: 1, display_name: "Right Win", email: "rev-race@ex.test" },
    }),
  ]);
  const statuses = [left.status, right.status].sort();
  const bothApplied = left.ok && right.ok;
  if (bothApplied) {
    assert.equal(left.body.customer.revision, 2);
    assert.equal(right.body.customer.revision, 2);
    const stored = JSON.parse(
      kv.store.get(`tenant:${TENANT_A}:company:${COMPANY_A}:customer:v1:${id}`),
    );
    assert.equal(stored.revision, 2);
    assert.ok(
      stored.display_name === "Left Win" || stored.display_name === "Right Win",
    );
  } else {
    assert.deepEqual(statuses, [200, 409]);
  }
});

test("concurrent creates with one idempotency key are not atomic on Workers KV", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const [left, right] = await Promise.all([
    createCompanyCustomer(env, {
      scope: SCOPE_A,
      idempotencyKey: "same-create",
      body: { display_name: "Idem Left", email: "idem-left@ex.test" },
    }),
    createCompanyCustomer(env, {
      scope: SCOPE_A,
      idempotencyKey: "same-create",
      body: { display_name: "Idem Right", email: "idem-right@ex.test" },
    }),
  ]);
  const leftConflict = left.error === "idempotency_payload_conflict";
  const rightConflict = right.error === "idempotency_payload_conflict";
  assert.ok(left.ok || leftConflict, "left must apply or lose the KV race");
  assert.ok(right.ok || rightConflict, "right must apply or lose the KV race");
  assert.ok(left.ok || right.ok, "at least one create must persist");
  if (left.ok && right.ok) {
    const ids = new Set([
      left.body.customer.customer_id,
      right.body.customer.customer_id,
    ]);
    if (ids.size === 1) {
      assert.ok(left.body.idempotent || right.body.idempotent);
    } else {
      assert.equal(ids.size, 2);
    }
  }
});
