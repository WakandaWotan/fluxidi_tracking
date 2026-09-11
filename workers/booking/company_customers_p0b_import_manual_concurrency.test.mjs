// COMPANY-CUSTOMER-OPS-P0B — import vs manual create/PATCH/archive.
//
// Import-vs-import tests do not cover packed-list races against manual writes.
// Uncoordinated overlapping writes share replaceCustomerInViews. The company
// Durable Object serializes both paths when the binding is present.
//
// Run:
//   node --test workers/booking/company_customers_p0b_import_manual_concurrency.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  createCompanyCustomer,
  getCompanyCustomer,
  listCompanyCustomers,
} from "./modules/company_customers.mjs";
import { processImportBatch } from "./modules/company_customers_import.mjs";
import { createMemoryCompanyCustomerImportCoordinatorBinding } from "./modules/company_customer_import_coordinator.mjs";

const ADMIN = "p0b-manual-admin";
const TENANT_A = "TA";
const COMPANY_A = "CA";
const SCOPE = { tenant_id: TENANT_A, company_id: COMPANY_A };

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

function yieldingKV() {
  const kv = countingKV();
  const yieldTick = () => new Promise((resolve) => setImmediate(resolve));
  return {
    store: kv.store,
    counts: kv.counts,
    async get(key, opts) {
      await yieldTick();
      return kv.get(key, opts);
    },
    async put(key, val) {
      await yieldTick();
      return kv.put(key, val);
    },
    async delete(key) {
      await yieldTick();
      return kv.delete(key);
    },
    async list() {
      await yieldTick();
      return kv.list();
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

async function importBatch(env, importId, rows) {
  const res = await adminRequest(env, `/company/customers/import/${importId}/batches`, {
    method: "POST",
    body: { rows },
  });
  return { res, json: await res.json() };
}

async function walkList(env, status = "active") {
  const seen = [];
  let cursor = "";
  for (let pages = 0; pages < 40; pages += 1) {
    const url = new URL("https://example.test/company/customers");
    url.searchParams.set("tenant_id", TENANT_A);
    url.searchParams.set("company_id", COMPANY_A);
    url.searchParams.set("status", status);
    url.searchParams.set("limit", "50");
    if (cursor) url.searchParams.set("cursor", cursor);
    const res = await worker.fetch(
      new Request(url, { method: "GET", headers: { "x-admin-token": ADMIN } }),
      env,
      {},
    );
    const body = await res.json();
    for (const item of body.items || []) seen.push(item);
    if (body.has_more !== true) break;
    cursor = body.next_cursor;
  }
  return seen;
}

function idsOf(rows) {
  return (rows || []).filter((row) => row.outcome === "created").map((row) => row.customer_id);
}

test("uncoordinated import and manual writes can drop a packed list row", async () => {
  let demonstrated = false;
  for (let trial = 0; trial < 20; trial += 1) {
    const env = { BOOKING_KV: yieldingKV() };
    const importId = newImportId(300 + trial);
    const [imported, created] = await Promise.all([
      processImportBatch(env, {
        scope: SCOPE,
        importId,
        rows: [customerRow(1, { email: `u${trial}a@p0b.test` }), customerRow(2, { email: `u${trial}b@p0b.test` })],
      }),
      createCompanyCustomer(env, {
        scope: SCOPE,
        body: { display_name: "Manual Create", email: `u${trial}m@p0b.test` },
      }),
    ]);
    const importedIds = idsOf(imported.body?.rows);
    const createdId = created.body?.customer?.customer_id;
    const listed = await listCompanyCustomers(env, { scope: SCOPE, status: "active", limit: 50 });
    const listedIds = (listed.body?.items || []).map((item) => item.customer_id);
    const expected = [...importedIds, createdId].filter(Boolean);
    if (expected.some((id) => !listedIds.includes(id))) {
      demonstrated = true;
      for (const id of expected) {
        const got = await getCompanyCustomer(env, { scope: SCOPE, customerId: id });
        assert.equal(got.ok, true, `record ${id} should remain readable after index loss`);
      }
      break;
    }
  }
  assert.equal(
    demonstrated,
    true,
    "expected at least one uncoordinated import+create trial to lose a list index row",
  );
});

test("coordinated import with manual create, PATCH and archive keeps records and index", async () => {
  const env = envWith(countingKV());
  const patchSeedRes = await adminRequest(env, "/company/customers", {
    method: "POST",
    body: { display_name: "Seed Patch", email: "seed-patch@p0b.test" },
  });
  assert.equal(patchSeedRes.status, 201, await patchSeedRes.clone().text());
  const patchSeed = (await patchSeedRes.json()).customer;
  const archiveSeedRes = await adminRequest(env, "/company/customers", {
    method: "POST",
    body: { display_name: "Seed Archive", email: "seed-archive@p0b.test" },
  });
  assert.equal(archiveSeedRes.status, 201);
  const archiveSeed = (await archiveSeedRes.json()).customer;
  const importId = newImportId(21);
  const [imported, created, patched, archived] = await Promise.all([
    importBatch(env, importId, [
      customerRow(91, { email: "imp91@p0b.test" }),
      customerRow(92, { email: "imp92@p0b.test" }),
    ]),
    adminRequest(env, "/company/customers", {
      method: "POST",
      body: { display_name: "Manual Ada", email: "manual-ada@p0b.test" },
    }),
    adminRequest(env, `/company/customers/${patchSeed.customer_id}`, {
      method: "PATCH",
      body: { display_name: "Seed Patched", revision: patchSeed.revision },
    }),
    adminRequest(env, `/company/customers/${archiveSeed.customer_id}/archive`, {
      method: "POST",
    }),
  ]);
  assert.equal(imported.res.status, 200, JSON.stringify(imported.json));
  assert.equal(created.status, 201, await created.clone().text());
  assert.equal(patched.status, 200, await patched.clone().text());
  assert.equal(archived.status, 200, await archived.clone().text());
  const importedIds = idsOf(imported.json.rows);
  assert.equal(importedIds.length, 2);
  const createdId = (await created.json()).customer.customer_id;
  const patchedBody = await patched.json();
  assert.equal(patchedBody.customer.display_name, "Seed Patched");
  const archivedBody = await archived.json();
  assert.equal(archivedBody.customer.status, "archived");

  const active = await walkList(env, "active");
  const activeIds = active.map((item) => item.customer_id);
  for (const id of [...importedIds, createdId, patchSeed.customer_id]) {
    assert.ok(activeIds.includes(id), `active list missing ${id}`);
    const got = await adminRequest(env, `/company/customers/${id}`);
    assert.equal(got.status, 200);
  }
  assert.equal(active.some((item) => item.customer_id === patchSeed.customer_id && item.display_name === "Seed Patched"), true);
  assert.equal(activeIds.includes(archiveSeed.customer_id), false);
  const archivedGot = await adminRequest(env, `/company/customers/${archiveSeed.customer_id}`);
  assert.equal(archivedGot.status, 200);
  assert.equal((await archivedGot.json()).customer.status, "archived");
  const archivedList = await walkList(env, "archived");
  assert.equal(archivedList.some((item) => item.customer_id === archiveSeed.customer_id), true);
});
