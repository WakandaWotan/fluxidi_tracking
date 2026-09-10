// COMPANY-CUSTOMER-OPS-P0B — concurrent import + expired resume.
//
// Run:
//   node --test workers/booking/company_customers_p0b_import_concurrency.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  CUSTOMER_GET_MAX_READS,
  CUSTOMER_IMPORT_TTL_SECONDS,
} from "./modules/company_customers.mjs";
import { createMemoryCompanyCustomerImportCoordinatorBinding } from "./modules/company_customer_import_coordinator.mjs";

const ADMIN = "p0b-conc-admin";
const TENANT_A = "TA";
const COMPANY_A = "CA";
const TENANT_B = "TB";
const COMPANY_B = "CB";

function countingKV(seed = {}) {
  const store = new Map();
  const counts = { get: 0, list: 0, put: 0, delete: 0 };
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    counts,
    async get(key, opts) {
      counts.get += 1;
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
    async put(key, val) {
      counts.put += 1;
      store.set(key, val);
    },
    async delete(key) {
      counts.delete += 1;
      store.delete(key);
    },
    async list() {
      counts.list += 1;
      return { keys: [], list_complete: true };
    },
  };
}

function envWith(kv, extra = {}) {
  const env = { ADMIN_TOKEN: ADMIN, BOOKING_KV: kv, ...extra };
  if (!env.COMPANY_CUSTOMER_IMPORT_COORDINATOR) {
    env.COMPANY_CUSTOMER_IMPORT_COORDINATOR =
      createMemoryCompanyCustomerImportCoordinatorBinding(env);
  }
  return env;
}

function newImportId(n) {
  return `imp_${String(n).padStart(32, "0")}`;
}

function customerRow(i, extras = {}) {
  return {
    row_key: extras.row_key || `r${i}`,
    decision: extras.decision || "create",
    customer: {
      display_name: extras.display_name || `Import ${String(i).padStart(3, "0")}`,
      email: extras.email || `imp${i}@p0b.test`,
      phone: extras.phone,
      country_calling_code: extras.country_calling_code,
    },
  };
}

async function adminRequest(env, path, { method = "GET", body, tenant = TENANT_A, company = COMPANY_A } = {}) {
  const url = new URL(`https://example.test${path}`);
  if (method === "GET") {
    url.searchParams.set("tenant_id", tenant);
    url.searchParams.set("company_id", company);
  }
  return worker.fetch(
    new Request(url, {
      method,
      headers: {
        "x-admin-token": ADMIN,
        "Content-Type": "application/json",
      },
      body: method === "GET"
        ? undefined
        : JSON.stringify({ tenant_id: tenant, company_id: company, ...(body || {}) }),
    }),
    env,
    {},
  );
}

async function importBatch(env, importId, rows, extras = {}) {
  const res = await adminRequest(env, `/company/customers/import/${importId}/batches`, {
    method: "POST",
    body: { rows },
    ...extras,
  });
  return { res, json: await res.json() };
}

async function walkList(env, { tenant = TENANT_A, company = COMPANY_A } = {}) {
  const seen = [];
  let cursor = "";
  for (let pages = 0; pages < 40; pages += 1) {
    const url = new URL("https://example.test/company/customers");
    url.searchParams.set("tenant_id", tenant);
    url.searchParams.set("company_id", company);
    url.searchParams.set("status", "active");
    url.searchParams.set("limit", "50");
    if (cursor) url.searchParams.set("cursor", cursor);
    const res = await worker.fetch(
      new Request(url, { method: "GET", headers: { "x-admin-token": ADMIN } }),
      env,
      {},
    );
    const body = await res.json();
    for (const item of body.items || []) seen.push(item.customer_id);
    if (body.has_more !== true) break;
    cursor = body.next_cursor;
  }
  return seen;
}

test("concurrent same import_id and row_key creates one customer and keeps the index", async () => {
  const env = envWith(countingKV());
  const importId = newImportId(11);
  const row = customerRow(11, { phone: "+32470111011" });
  const [a, b] = await Promise.all([
    importBatch(env, importId, [row]),
    importBatch(env, importId, [row]),
  ]);
  assert.equal(a.res.status, 200, JSON.stringify(a.json));
  assert.equal(b.res.status, 200, JSON.stringify(b.json));
  const ids = [a.json.rows[0].customer_id, b.json.rows[0].customer_id].filter(Boolean);
  assert.equal(new Set(ids).size, 1);
  assert.ok(a.json.rows[0].replayed || b.json.rows[0].replayed || a.json.rows[0].idempotent || b.json.rows[0].idempotent);
  const listed = await walkList(env);
  assert.equal(listed.length, 1);
  assert.equal(listed[0], ids[0]);
  const got = await adminRequest(env, `/company/customers/${ids[0]}`);
  assert.equal(got.status, 200);
});

test("same key with changed content stays a conflict under concurrency", async () => {
  const env = envWith(countingKV());
  const importId = newImportId(12);
  const first = await importBatch(env, importId, [customerRow(12)]);
  assert.equal(first.json.rows[0].outcome, "created");
  const [left, right] = await Promise.all([
    importBatch(env, importId, [customerRow(12, { email: "changed-a@p0b.test", display_name: "Changed A" })]),
    importBatch(env, importId, [customerRow(12, { email: "changed-b@p0b.test", display_name: "Changed B" })]),
  ]);
  assert.equal(left.json.rows[0].outcome, "conflict");
  assert.equal(right.json.rows[0].outcome, "conflict");
  assert.equal(left.json.rows[0].error, "idempotency_payload_conflict");
  const listed = await walkList(env);
  assert.equal(listed.length, 1);
  assert.equal(listed[0], first.json.rows[0].customer_id);
});

test("concurrent different rows keep every confirmed customer readable", async () => {
  const env = envWith(countingKV());
  const importId = newImportId(13);
  const [a, b] = await Promise.all([
    importBatch(env, importId, [customerRow(31), customerRow(32)]),
    importBatch(env, importId, [customerRow(33), customerRow(34)]),
  ]);
  assert.equal(a.res.status, 200, JSON.stringify(a.json));
  assert.equal(b.res.status, 200, JSON.stringify(b.json));
  const created = [...a.json.rows, ...b.json.rows]
    .filter((row) => row.outcome === "created")
    .map((row) => row.customer_id);
  assert.equal(created.length, 4);
  assert.equal(new Set(created).size, 4);
  const listed = await walkList(env);
  assert.equal(listed.length, 4);
  assert.equal(new Set(listed).size, 4);
  for (const id of created) {
    assert.ok(listed.includes(id));
    const got = await adminRequest(env, `/company/customers/${id}`);
    assert.equal(got.status, 200);
  }
});

test("a lost batch response replays the same customers", async () => {
  const env = envWith(countingKV());
  const importId = newImportId(14);
  const first = await importBatch(env, importId, [customerRow(41), customerRow(42)]);
  assert.equal(first.json.added, 2);
  const retry = await importBatch(env, importId, [customerRow(41), customerRow(42)]);
  assert.equal(retry.res.status, 200);
  assert.equal(retry.json.added, 2);
  assert.ok(retry.json.rows.every((row) => row.replayed || row.idempotent));
  assert.deepEqual(
    retry.json.rows.map((row) => row.customer_id),
    first.json.rows.map((row) => row.customer_id),
  );
  const listed = await walkList(env);
  assert.equal(listed.length, 2);
});

test("expired import metadata refuses recreate and keeps confirmed customers", async () => {
  const started = 1_700_000_000_000;
  const env = envWith(countingKV(), { CUSTOMER_NOW_MS: started });
  const importId = newImportId(15);
  const created = await importBatch(env, importId, [customerRow(51, { email: "keep@p0b.test" })]);
  assert.equal(created.json.rows[0].outcome, "created");
  const customerId = created.json.rows[0].customer_id;
  env.CUSTOMER_NOW_MS = started + (CUSTOMER_IMPORT_TTL_SECONDS + 60) * 1000;
  const expiredGet = await adminRequest(env, `/company/customers/import/${importId}`);
  assert.equal(expiredGet.status, 410);
  const expiredGetBody = await expiredGet.json();
  assert.equal(expiredGetBody.error, "import_expired");
  assert.equal(expiredGetBody.next_step, "start_new_import");
  const expiredBatch = await importBatch(env, importId, [customerRow(51, { email: "keep@p0b.test" })]);
  assert.equal(expiredBatch.res.status, 410);
  assert.equal(expiredBatch.json.error, "import_expired");
  assert.equal(expiredBatch.json.next_step, "start_new_import");
  const listed = await walkList(env);
  assert.equal(listed.length, 1);
  assert.equal(listed[0], customerId);
});

test("unknown import is a clear miss and missing coordinator fails closed", async () => {
  const kv = countingKV();
  const withDo = envWith(kv);
  const missing = await adminRequest(withDo, `/company/customers/import/${newImportId(16)}`);
  assert.equal(missing.status, 404);
  const missingBody = await missing.json();
  assert.equal(missingBody.error, "import_not_found");
  assert.equal(missingBody.next_step, "start_new_import");

  const closed = {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: countingKV(),
  };
  const refused = await adminRequest(closed, `/company/customers/import/${newImportId(17)}/batches`, {
    method: "POST",
    body: { rows: [customerRow(61)] },
  });
  assert.equal(refused.status, 503);
  const refusedBody = await refused.json();
  assert.equal(refusedBody.error, "import_coordinator_unavailable");
});

test("tenant B cannot observe tenant A import ledger after a race", async () => {
  const env = envWith(countingKV());
  const importId = newImportId(18);
  await Promise.all([
    importBatch(env, importId, [customerRow(71, { email: "secret-a@p0b.test" })]),
    importBatch(env, importId, [customerRow(72)]),
  ]);
  const cross = await adminRequest(env, `/company/customers/import/${importId}`, {
    tenant: TENANT_B,
    company: COMPANY_B,
  });
  assert.equal(cross.status, 404);
  const crossBody = await cross.json();
  assert.equal(String(JSON.stringify(crossBody)).includes("secret-a@p0b.test"), false);
  const listedB = await walkList(env, { tenant: TENANT_B, company: COMPANY_B });
  assert.equal(listedB.length, 0);
});

test("list budget stays bounded after coordinated writes", async () => {
  const env = envWith(countingKV());
  const importId = newImportId(19);
  await importBatch(env, importId, [customerRow(81), customerRow(82)]);
  const before = env.BOOKING_KV.counts.get;
  const url = new URL("https://example.test/company/customers");
  url.searchParams.set("tenant_id", TENANT_A);
  url.searchParams.set("company_id", COMPANY_A);
  const res = await worker.fetch(
    new Request(url, { method: "GET", headers: { "x-admin-token": ADMIN } }),
    env,
    {},
  );
  assert.equal(res.status, 200);
  assert.ok(env.BOOKING_KV.counts.get - before <= CUSTOMER_GET_MAX_READS);
});
