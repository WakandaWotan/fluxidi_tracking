// COMPANY-CUSTOMER-OPS-P0B — hermetic customer import.
//
// Run:
//   node --test workers/booking/company_customers_p0b_import.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  CUSTOMER_GET_MAX_READS,
  CUSTOMER_IMPORT_BATCH_MAX,
  CUSTOMER_IMPORT_MAX_READS,
  CUSTOMER_IMPORT_MAX_WRITES,
  CUSTOMER_IMPORT_TTL_SECONDS,
  matchCompanyCustomersPath,
} from "./modules/company_customers.mjs";
import { companyCustomerImportKey } from "./modules/company_customers_import.mjs";
import { createMemoryCompanyCustomerImportCoordinatorBinding } from "./modules/company_customer_import_coordinator.mjs";

const ADMIN = "p0a-admin-token";
const TENANT_A = "TA";
const COMPANY_A = "CA";
const TENANT_B = "TB";
const COMPANY_B = "CB";

function countingKV(seed = {}) {
  const store = new Map();
  const meta = new Map();
  const counts = { get: 0, list: 0, put: 0, delete: 0, got: [], ttls: [] };
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
        } catch {
          return null;
        }
      }
      return raw;
    },
    async put(key, val, opts) {
      counts.put += 1;
      store.set(key, val);
      if (opts?.expirationTtl) counts.ttls.push({ key, ttl: opts.expirationTtl });
      if (opts?.metadata) meta.set(key, opts.metadata);
    },
    async delete(key) {
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
    row_key: `r${i}`,
    decision: "create",
    customer: {
      display_name: extras.display_name || `Import ${String(i).padStart(3, "0")}`,
      email: extras.email || `imp${i}@p0b.test`,
      phone: extras.phone,
      country_calling_code: extras.country_calling_code,
      first_name: extras.first_name,
      last_name: extras.last_name,
      company_name: extras.company_name,
      addresses: extras.addresses,
    },
  };
}

function assertNoPii(text, sample) {
  const hay = String(text || "").toLowerCase();
  for (const part of sample) {
    const needle = String(part || "").trim();
    if (!needle) continue;
    assert.equal(hay.includes(needle.toLowerCase()), false, `pii leaked: ${needle.length}`);
  }
}

async function adminRequest(env, path, { method = "GET", body, tenant = TENANT_A, company = COMPANY_A, headers = {} } = {}) {
  const url = new URL(`https://example.test${path}`);
  if (method === "GET") {
    url.searchParams.set("tenant_id", tenant);
    url.searchParams.set("company_id", company);
  }
  const payload = body && typeof body === "object"
    ? { tenant_id: tenant, company_id: company, ...body }
    : body;
  return worker.fetch(
    new Request(url, {
      method,
      headers: {
        "x-admin-token": ADMIN,
        "Content-Type": "application/json",
        ...headers,
      },
      body: method === "GET" ? undefined : JSON.stringify(payload || { tenant_id: tenant, company_id: company }),
    }),
    env,
    {},
  );
}

async function sessionRequest(env, token, path, { method = "GET", body, tenant = TENANT_A, company = COMPANY_A } = {}) {
  const url = new URL(`https://example.test${path}`);
  if (method === "GET") {
    url.searchParams.set("tenant_id", tenant);
    url.searchParams.set("company_id", company);
  }
  const payload = body && typeof body === "object"
    ? { tenant_id: tenant, company_id: company, ...body }
    : body;
  return worker.fetch(
    new Request(url, {
      method,
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: method === "GET" ? undefined : JSON.stringify(payload || { tenant_id: tenant, company_id: company }),
    }),
    env,
    {},
  );
}

async function importBatch(env, importId, rows, extras = {}) {
  const before = {
    get: env.BOOKING_KV.counts.get,
    put: env.BOOKING_KV.counts.put,
    list: env.BOOKING_KV.counts.list,
  };
  const res = await adminRequest(env, `/company/customers/import/${importId}/batches`, {
    method: "POST",
    body: { rows },
    ...extras,
  });
  const json = await res.json();
  return {
    res,
    json,
    reads: env.BOOKING_KV.counts.get - before.get,
    writes: env.BOOKING_KV.counts.put - before.put,
    lists: env.BOOKING_KV.counts.list - before.list,
  };
}

async function walkList(env, { status = "active", tenant = TENANT_A, company = COMPANY_A, limit = 50 } = {}) {
  const seen = [];
  let cursor = "";
  let pages = 0;
  let lastBody = null;
  while (pages < 40) {
    pages += 1;
    const url = new URL("https://example.test/company/customers");
    url.searchParams.set("tenant_id", tenant);
    url.searchParams.set("company_id", company);
    url.searchParams.set("status", status);
    url.searchParams.set("limit", String(limit));
    if (cursor) url.searchParams.set("cursor", cursor);
    const beforeGets = env.BOOKING_KV.counts.get;
    const beforeLists = env.BOOKING_KV.counts.list;
    const res = await worker.fetch(
      new Request(url, { method: "GET", headers: { "x-admin-token": ADMIN } }),
      env,
      {},
    );
    const got = env.BOOKING_KV.counts.get - beforeGets;
    const listed = env.BOOKING_KV.counts.list - beforeLists;
    assert.ok(got <= CUSTOMER_GET_MAX_READS, `list GET used ${got} reads`);
    assert.equal(listed, 0);
    const body = await res.json();
    lastBody = body;
    for (const item of body.items) seen.push(item.customer_id);
    if (body.has_more !== true) break;
    cursor = body.next_cursor;
  }
  return { ids: seen, lastBody };
}

test("import path is not treated as a customer id", () => {
  const route = matchCompanyCustomersPath("/company/customers/import/imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/batches");
  assert.equal(route.kind, "import");
  assert.equal(route.importId, "imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
  assert.equal(route.action, "batches");
  assert.equal(route.customerId, "");
  const lookup = matchCompanyCustomersPath("/company/customers/import/imp_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/lookups");
  assert.equal(lookup.action, "lookups");
  const customer = matchCompanyCustomersPath("/company/customers/cus_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
  assert.equal(customer.kind, "customer");
  assert.equal(customer.customerId, "cus_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
});

test("form create still rejects a client source override", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const res = await adminRequest(env, "/company/customers", {
    method: "POST",
    body: { display_name: "Manual", email: "manual@p0b.test", source: "import" },
  });
  assert.equal(res.status, 400);
  const body = await res.json();
  assert.equal(body.fields.source, "manual_only");
});

test("import batch sets source=import and keeps sequential retry unique", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const importId = newImportId(1);
  const first = await importBatch(env, importId, [customerRow(1, { phone: "+32470111222" })]);
  assert.equal(first.res.status, 200);
  assert.ok(first.reads <= CUSTOMER_IMPORT_MAX_READS);
  assert.ok(first.writes <= CUSTOMER_IMPORT_MAX_WRITES);
  assert.equal(first.lists, 0);
  assert.equal(first.json.added, 1);
  assert.equal(first.json.rows[0].outcome, "created");
  const customerId = first.json.rows[0].customer_id;
  const got = await adminRequest(env, `/company/customers/${customerId}`);
  const customer = (await got.json()).customer;
  assert.equal(customer.source, "import");
  assert.equal(customer.phone, "+32470111222");

  const retry = await importBatch(env, importId, [customerRow(1, { phone: "+32470111222" })]);
  assert.equal(retry.res.status, 200);
  assert.equal(retry.json.added, 1);
  assert.equal(retry.json.rows[0].customer_id, customerId);
  assert.equal(retry.json.rows[0].replayed || retry.json.rows[0].idempotent, true);

  const conflict = await importBatch(env, importId, [
    customerRow(1, { email: "changed@p0b.test", display_name: "Changed" }),
  ]);
  assert.equal(conflict.json.rows[0].outcome, "conflict");
  assert.equal(conflict.json.rows[0].error, "idempotency_payload_conflict");
  assert.equal(conflict.json.added, 1);

  const metaKey = companyCustomerImportKey({ tenant_id: TENANT_A, company_id: COMPANY_A }, importId);
  assert.ok(kv.counts.ttls.some((item) => item.key === metaKey && item.ttl === CUSTOMER_IMPORT_TTL_SECONDS));
  const meta = JSON.parse(kv.store.get(metaKey));
  assertNoPii(JSON.stringify(meta), ["imp1@p0b.test", "+32470111222", "Import 001"]);
});

test("skip stays skip and oversized batches are rejected", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const importId = newImportId(2);
  const skipped = await importBatch(env, importId, [
    { row_key: "r1", decision: "skip", customer: { display_name: "Skip Me", email: "skip@p0b.test" } },
  ]);
  assert.equal(skipped.json.skipped, 1);
  assert.equal(skipped.json.added, 0);
  const tooBig = await importBatch(env, importId, [
    customerRow(2),
    customerRow(3),
    customerRow(4),
  ]);
  assert.equal(tooBig.res.status, 400);
  assert.equal(tooBig.json.error, "batch_too_large");
  assert.equal(CUSTOMER_IMPORT_BATCH_MAX, 2);
});

test("lookups find same-company matches without merging", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  await adminRequest(env, "/company/customers", {
    method: "POST",
    body: { display_name: "Existing", email: "shared@p0b.test", phone: "+32470000001" },
  });
  const importId = newImportId(3);
  const res = await adminRequest(env, `/company/customers/import/${importId}/lookups`, {
    method: "POST",
    body: {
      contacts: [
        { row_key: "r1", email: "shared@p0b.test", phone: "+32470000001" },
      ],
    },
  });
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.ok(body.matches.some((row) => row.field === "email"));
  assert.ok(body.matches.some((row) => row.field === "phone"));
  assert.ok(body.matches.every((row) => row.email_masked.startsWith("*@")));
});

test("forged import scope is rejected and tenant B cannot read tenant A imports", async () => {
  const sessionA = await seedCompanySession({ tokenValue: "tok-a", tenantId: TENANT_A, companyId: COMPANY_A });
  const sessionB = await seedCompanySession({ tokenValue: "tok-b", tenantId: TENANT_B, companyId: COMPANY_B });
  const kv = countingKV({
    [sessionA.key]: sessionA.record,
    [sessionB.key]: sessionB.record,
  });
  const env = envWith(kv);
  const importId = newImportId(4);
  const created = await sessionRequest(env, "tok-a", `/company/customers/import/${importId}/batches`, {
    method: "POST",
    body: { rows: [customerRow(9, { email: "secret-a@p0b.test", display_name: "Secret A" })] },
  });
  assert.equal(created.status, 200);
  const customerId = (await created.json()).rows[0].customer_id;

  const forged = await sessionRequest(env, "tok-a", `/company/customers/import/${importId}/batches`, {
    method: "POST",
    tenant: TENANT_B,
    company: COMPANY_B,
    body: { rows: [customerRow(10)] },
  });
  assert.equal(forged.status, 403);

  const forgedRead = await sessionRequest(env, "tok-b", `/company/customers/import/${importId}`);
  assert.equal(forgedRead.status, 403);
  const cross = await sessionRequest(env, "tok-b", `/company/customers/import/${importId}`, {
    tenant: TENANT_B,
    company: COMPANY_B,
  });
  assert.equal(cross.status, 404);
  const crossBody = await cross.json();
  assertNoPii(JSON.stringify(crossBody), ["Secret A", "secret-a@p0b.test"]);

  const guess = await sessionRequest(env, "tok-b", `/company/customers/${customerId}`, {
    tenant: TENANT_B,
    company: COMPANY_B,
  });
  assert.equal(guess.status, 404);
});

test("401 imported contacts are fully readable without loss or duplicates", async () => {
  const kv = countingKV();
  const env = envWith(kv, { CUSTOMER_NOW_MS: 1_700_000_000_000 });
  const importId = newImportId(5);
  const expected = [];
  for (let i = 1; i <= 401; i += 2) {
    env.CUSTOMER_NOW_MS = 1_700_000_000_000 + i * 1000;
    const batch = [customerRow(i)];
    if (i + 1 <= 401) batch.push(customerRow(i + 1));
    const result = await importBatch(env, importId, batch);
    assert.equal(result.res.status, 200, JSON.stringify(result.json));
    assert.ok(result.reads <= CUSTOMER_IMPORT_MAX_READS, `reads ${result.reads}`);
    assert.ok(result.writes <= CUSTOMER_IMPORT_MAX_WRITES, `writes ${result.writes}`);
    assert.equal(result.lists, 0);
    for (const row of result.json.rows) {
      if (row.outcome === "created") expected.push(row.customer_id);
    }
  }
  assert.equal(expected.length, 401);
  assert.equal(new Set(expected).size, 401);
  const walked = await walkList(env);
  assert.equal(walked.ids.length, 401);
  assert.equal(new Set(walked.ids).size, 401);
  const sampleId = expected[0];
  const sample = await (await adminRequest(env, `/company/customers/${sampleId}`)).json();
  assert.equal(sample.customer.source, "import");
  const status = await (await adminRequest(env, `/company/customers/import/${importId}`)).json();
  assert.equal(status.import.added, 401);
  assert.equal(status.import.failed, 0);
});
