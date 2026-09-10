// COMPANY-CUSTOMER-OPS-P0A — hermetic company customer API.
//
// Run:
//   node --test workers/booking/company_customers_p0a.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  createCompanyCustomer,
  CUSTOMER_GET_MAX_READS,
} from "./modules/company_customers.mjs";

const ADMIN = "p0a-admin-token";
const TENANT_A = "TA";
const COMPANY_A = "CA";
const TENANT_B = "TB";
const COMPANY_B = "CB";
const SCOPE_A = { tenant_id: TENANT_A, company_id: COMPANY_A, hasScope: true };

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
        } catch {
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

function envWith(kv, extra = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    ...extra,
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

function assertNoPrefixScan(kv) {
  assert.equal(kv.counts.list, 0, "customer GET/mutate must not kv.list");
  assert.equal(
    kv.counts.got.some((key) => String(key).startsWith("booking:")),
    false,
    "customer routes must not hydrate booking:",
  );
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

async function createViaHttp(env, fields, extras = {}) {
  const res = await adminRequest(env, "/company/customers", {
    method: "POST",
    body: fields,
    ...extras,
  });
  const json = await res.json();
  return { res, json };
}

async function walkList(env, { status = "active", q = "", tenant = TENANT_A, company = COMPANY_A, limit = 50 } = {}) {
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
    if (q) url.searchParams.set("q", q);
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
    assert.equal(listed, 0, "list GET used kv.list");
    assert.equal(res.status, 200);
    const body = await res.json();
    lastBody = body;
    assert.equal(body.ok, true);
    assert.ok(Array.isArray(body.items));
    assert.ok(body.items.length <= limit);
    if (body.has_more === true) {
      assert.ok(String(body.next_cursor || "").trim(), "has_more requires cursor");
    } else {
      assert.equal(body.next_cursor, null);
    }
    for (const item of body.items) seen.push(item.customer_id);
    if (body.has_more !== true) break;
    cursor = body.next_cursor;
  }
  return { ids: seen, lastBody, pages };
}

test("create get update archive restore roundtrip", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createViaHttp(env, {
    display_name: "Ada Lovelace",
    first_name: "Ada",
    last_name: "Lovelace",
    email: "ada@example.test",
    phone: "+442071838750",
    locale: "en-GB",
    company_name: "Analytical Engines",
    vat_number: "GB123",
    internal_notes: "Not visible to the customer",
    addresses: [{ type: "billing", line1: "St James", city: "London", country_code: "GB" }],
    preferences: { version: 1, preferred_locale: "en-GB" },
  });
  assert.equal(created.res.status, 201);
  assert.equal(created.json.ok, true);
  const id = created.json.customer.customer_id;
  assert.match(id, /^cus_[a-f0-9]{32}$/);
  assert.equal(created.json.customer.source, "manual");
  assert.equal(created.json.customer.status, "active");
  assert.equal(created.json.customer.revision, 1);
  assert.equal(created.json.customer.company_id, COMPANY_A);

  const got = await adminRequest(env, `/company/customers/${id}`);
  assert.equal(got.status, 200);
  const gotBody = await got.json();
  assert.equal(gotBody.customer.email, "ada@example.test");
  assert.equal(gotBody.customer.addresses[0].type, "billing");

  const patched = await adminRequest(env, `/company/customers/${id}`, {
    method: "PATCH",
    body: { revision: 1, display_name: "Ada L.", email: "ada@example.test" },
  });
  assert.equal(patched.status, 200);
  const patchedBody = await patched.json();
  assert.equal(patchedBody.customer.display_name, "Ada L.");
  assert.equal(patchedBody.customer.revision, 2);
  assert.equal(patchedBody.customer.email, "ada@example.test");

  const archived = await adminRequest(env, `/company/customers/${id}/archive`, { method: "POST" });
  assert.equal(archived.status, 200);
  const archivedBody = await archived.json();
  assert.equal(archivedBody.customer.status, "archived");
  assert.ok(archivedBody.customer.archived_at);

  const active = await walkList(env, { status: "active" });
  assert.equal(active.ids.includes(id), false);
  const hidden = await walkList(env, { status: "archived" });
  assert.equal(hidden.ids.includes(id), true);

  const restored = await adminRequest(env, `/company/customers/${id}/restore`, { method: "POST" });
  assert.equal(restored.status, 200);
  const restoredBody = await restored.json();
  assert.equal(restoredBody.customer.status, "active");
  assert.equal(restoredBody.customer.archived_at, null);
});

test("create and archive restore are idempotent", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const first = await adminRequest(env, "/company/customers", {
    method: "POST",
    headers: { "Idempotency-Key": "create-1" },
    body: { display_name: "Idem", email: "idem@example.test" },
  });
  const second = await adminRequest(env, "/company/customers", {
    method: "POST",
    headers: { "Idempotency-Key": "create-1" },
    body: { display_name: "Idem", email: "idem@example.test" },
  });
  assert.equal(first.status, 201);
  assert.equal(second.status, 200);
  const a = await first.json();
  const b = await second.json();
  assert.equal(a.customer.customer_id, b.customer.customer_id);
  assert.equal(b.idempotent, true);

  const id = a.customer.customer_id;
  const arch1 = await adminRequest(env, `/company/customers/${id}/archive`, {
    method: "POST",
    headers: { "Idempotency-Key": "arch-1" },
  });
  const arch2 = await adminRequest(env, `/company/customers/${id}/archive`, {
    method: "POST",
    headers: { "Idempotency-Key": "arch-1" },
  });
  assert.equal(arch1.status, 200);
  assert.equal(arch2.status, 200);
  const archBody = await arch2.json();
  assert.equal(archBody.customer.status, "archived");
  assert.equal(archBody.idempotent, true);

  const rest1 = await adminRequest(env, `/company/customers/${id}/restore`, { method: "POST" });
  const rest2 = await adminRequest(env, `/company/customers/${id}/restore`, { method: "POST" });
  assert.equal((await rest1.json()).customer.status, "active");
  assert.equal((await rest2.json()).customer.status, "active");
});

test("revision conflict returns 409 without applying the write", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const created = await createViaHttp(env, { display_name: "Rev", email: "rev@example.test" });
  const id = created.json.customer.customer_id;
  const stale = await adminRequest(env, `/company/customers/${id}`, {
    method: "PATCH",
    body: { revision: 0, display_name: "Nope" },
  });
  assert.equal(stale.status, 409);
  const staleBody = await stale.json();
  assert.equal(staleBody.error, "revision_conflict");
  const got = await (await adminRequest(env, `/company/customers/${id}`)).json();
  assert.equal(got.customer.display_name, "Rev");
  assert.equal(got.customer.revision, 1);
});

test("validation rejects missing contact, bad email, and import source", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const noContact = await createViaHttp(env, { display_name: "Anon only" });
  assert.equal(noContact.res.status, 400);
  assert.equal(noContact.json.error, "invalid_customer");
  assert.equal(noContact.json.fields.contact, "required");
  assertNoPii(JSON.stringify(noContact.json), ["Anon only"]);

  const badEmail = await createViaHttp(env, { display_name: "Bad", email: "not-an-email" });
  assert.equal(badEmail.res.status, 400);
  assert.equal(badEmail.json.fields.email, "invalid");
  assertNoPii(JSON.stringify(badEmail.json), ["not-an-email"]);

  const imported = await createViaHttp(env, {
    display_name: "Import",
    email: "import@example.test",
    source: "import",
  });
  assert.equal(imported.res.status, 400);
  assert.equal(imported.json.fields.source, "manual_only");
});

test("same-company duplicate is a warning, never a block", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const first = await createViaHttp(env, { display_name: "One", email: "same@example.test" });
  const second = await createViaHttp(env, { display_name: "Two", email: "same@example.test" });
  assert.equal(first.res.status, 201);
  assert.equal(second.res.status, 201);
  assert.notEqual(second.json.customer.customer_id, first.json.customer.customer_id);
  assert.equal(second.json.duplicate_warning.matches[0].field, "email");
  assert.equal(second.json.duplicate_warning.matches[0].customer_id, first.json.customer.customer_id);
});

test("tenant A cannot read search change archive or guess tenant B customers", async () => {
  const sessionA = await seedCompanySession({ tokenValue: "tok-a", tenantId: TENANT_A, companyId: COMPANY_A });
  const sessionB = await seedCompanySession({ tokenValue: "tok-b", tenantId: TENANT_B, companyId: COMPANY_B });
  const kv = countingKV({
    [sessionA.key]: sessionA.record,
    [sessionB.key]: sessionB.record,
  });
  const env = envWith(kv);
  const createdB = await adminRequest(env, "/company/customers", {
    method: "POST",
    tenant: TENANT_B,
    company: COMPANY_B,
    body: { display_name: "Secret B", email: "secret-b@example.test", phone: "+34911222333" },
  });
  assert.equal(createdB.status, 201);
  const idB = (await createdB.json()).customer.customer_id;

  const createdA = await sessionRequest(env, "tok-a", "/company/customers", {
    method: "POST",
    body: { display_name: "Visible A", email: "a@example.test" },
  });
  assert.equal(createdA.status, 201);

  const crossScope = await sessionRequest(env, "tok-a", `/company/customers/${idB}`, {
    tenant: TENANT_B,
    company: COMPANY_B,
  });
  assert.equal(crossScope.status, 403);
  const crossScopeBody = await crossScope.json();
  assert.equal(crossScopeBody.error, "forbidden");

  const guessOwnScope = await sessionRequest(env, "tok-a", `/company/customers/${idB}`);
  const missingOwn = await sessionRequest(env, "tok-a", "/company/customers/cus_ffffffffffffffffffffffffffffffff");
  assert.equal(guessOwnScope.status, 404);
  assert.equal(missingOwn.status, 404);
  const guessBody = await guessOwnScope.json();
  const missingBody = await missingOwn.json();
  assert.deepEqual(guessBody, missingBody);
  assert.equal(guessBody.error, "not_found");
  assertNoPii(JSON.stringify(guessBody), ["Secret B", "secret-b@example.test", "+34911222333"]);

  const searchRes = await sessionRequest(env, "tok-a", "/company/customers");
  assert.equal(searchRes.status, 200);
  const searchBody = await searchRes.json();
  assert.equal(searchBody.items.some((row) => row.customer_id === idB), false);

  const qUrl = new URL("https://example.test/company/customers");
  qUrl.searchParams.set("tenant_id", TENANT_A);
  qUrl.searchParams.set("company_id", COMPANY_A);
  qUrl.searchParams.set("q", "secret-b");
  const qRes = await worker.fetch(
    new Request(qUrl, { headers: { Authorization: "Bearer tok-a" } }),
    env,
    {},
  );
  const qBody = await qRes.json();
  assert.equal(qBody.items.length, 0);

  const patch = await sessionRequest(env, "tok-a", `/company/customers/${idB}`, {
    method: "PATCH",
    body: { revision: 1, display_name: "Hacked" },
  });
  const archive = await sessionRequest(env, "tok-a", `/company/customers/${idB}/archive`, {
    method: "POST",
  });
  assert.equal(patch.status, 404);
  assert.equal(archive.status, 404);
  assert.equal((await patch.json()).error, "not_found");
  assert.equal((await archive.json()).error, "not_found");

  const stillB = await adminRequest(env, `/company/customers/${idB}`, {
    tenant: TENANT_B,
    company: COMPANY_B,
  });
  assert.equal((await stillB.json()).customer.display_name, "Secret B");
});

test("active archived and all filters plus search", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const live = await createViaHttp(env, { display_name: "Live One", email: "live@example.test" });
  const dest = await createViaHttp(env, { display_name: "Parked Two", email: "parked@example.test" });
  const destId = dest.json.customer.customer_id;
  await adminRequest(env, `/company/customers/${destId}/archive`, { method: "POST" });
  const active = await walkList(env, { status: "active" });
  const archived = await walkList(env, { status: "archived" });
  const all = await walkList(env, { status: "all" });
  assert.equal(active.ids.includes(live.json.customer.customer_id), true);
  assert.equal(active.ids.includes(destId), false);
  assert.equal(archived.ids.includes(destId), true);
  assert.equal(all.ids.length, 2);

  const qUrl = new URL("https://example.test/company/customers");
  qUrl.searchParams.set("tenant_id", TENANT_A);
  qUrl.searchParams.set("company_id", COMPANY_A);
  qUrl.searchParams.set("q", "parked");
  qUrl.searchParams.set("status", "all");
  const qRes = await worker.fetch(
    new Request(qUrl, { headers: { "x-admin-token": ADMIN } }),
    env,
    {},
  );
  const qBody = await qRes.json();
  assert.equal(qBody.items.length, 1);
  assert.equal(qBody.items[0].customer_id, destId);
  assert.ok(qBody.items[0].email_masked.startsWith("*@"));
});

test("401 customers are fully walkable without duplicates or list scans", async () => {
  const kv = countingKV();
  const env = envWith(kv, { CUSTOMER_NOW_MS: 1_700_000_000_000 });
  const ids = [];
  for (let i = 0; i < 401; i += 1) {
    env.CUSTOMER_NOW_MS = 1_700_000_000_000 + i * 1000;
    const result = await createCompanyCustomer(env, {
      scope: SCOPE_A,
      body: { display_name: `Cust ${String(i).padStart(3, "0")}`, email: `c${i}@ex.test` },
    });
    assert.equal(result.ok, true);
    ids.push(result.body.customer.customer_id);
  }
  kv.counts.get = 0;
  kv.counts.list = 0;
  kv.counts.got = [];
  const walked = await walkList(env, { status: "active", limit: 50 });
  assert.equal(walked.ids.length, 401);
  assert.equal(new Set(walked.ids).size, 401);
  assert.equal(walked.lastBody.total_count, 401);
  assertNoPrefixScan(kv);

  env.CUSTOMER_NOW_MS = 1_800_000_000_000;
  const newest = await createCompanyCustomer(env, {
    scope: SCOPE_A,
    body: { display_name: "Newest Front", email: "newest@ex.test" },
  });
  const firstUrl = new URL("https://example.test/company/customers");
  firstUrl.searchParams.set("tenant_id", TENANT_A);
  firstUrl.searchParams.set("company_id", COMPANY_A);
  firstUrl.searchParams.set("limit", "50");
  const firstRes = await worker.fetch(
    new Request(firstUrl, { headers: { "x-admin-token": ADMIN } }),
    env,
    {},
  );
  const firstBody = await firstRes.json();
  assert.equal(firstBody.items[0].customer_id, newest.body.customer.customer_id);
  const walkedAfter = await walkList(env, { status: "active" });
  assert.equal(walkedAfter.ids.length, 402);
  assert.equal(new Set(walkedAfter.ids).size, 402);
});

test("more than 200 customers stay packed and newest land on the first page", async () => {
  const kv = countingKV();
  const env = envWith(kv, { CUSTOMER_NOW_MS: 1_700_000_000_000 });
  for (let i = 0; i < 210; i += 1) {
    env.CUSTOMER_NOW_MS = 1_700_000_000_000 + i * 1000;
    const result = await createCompanyCustomer(env, {
      scope: SCOPE_A,
      body: { display_name: `Pack ${i}`, email: `p${i}@ex.test` },
    });
    assert.equal(result.ok, true);
  }
  const walked = await walkList(env, { limit: 50 });
  assert.equal(walked.ids.length, 210);
  assert.equal(new Set(walked.ids).size, 210);
  const marker = JSON.parse(
    kv.store.get(`tenant:${TENANT_A}:company:${COMPANY_A}:customers:list:v1:marker`),
  );
  assert.equal(marker.views.active.row_count, 210);
  assert.ok(marker.views.active.page_count <= 2);
});

test("missing scope and missing auth fail closed", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const noScope = await worker.fetch(
    new Request("https://example.test/company/customers", {
      headers: { "x-admin-token": ADMIN },
    }),
    env,
    {},
  );
  assert.equal(noScope.status, 400);
  const noAuth = await worker.fetch(
    new Request("https://example.test/company/customers?tenant_id=TA&company_id=CA"),
    env,
    {},
  );
  assert.equal(noAuth.status, 401);
  const noAuthBody = await noAuth.json();
  assert.equal(noAuthBody.error, "unauthorized");
});

test("PII stays out of logs and public list rows", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const logs = [];
  const orig = console.log;
  console.log = (...args) => {
    logs.push(args.map(String).join(" "));
  };
  try {
    const created = await createViaHttp(env, {
      display_name: "Pii Person",
      email: "pii-person@example.test",
      phone: "+498900112233",
    });
    assert.equal(created.res.status, 201);
    const list = await walkList(env);
    assert.equal(list.lastBody.items[0].email_masked, "*@example.test");
    assert.match(list.lastBody.items[0].phone_masked, /^\*\*\*\d{2}$/);
    const hay = logs.join("\n");
    assertNoPii(hay, ["Pii Person", "pii-person@example.test", "+498900112233", "498900112233"]);
  } finally {
    console.log = orig;
  }
});

test("sequential create with the same idempotency key rejects a changed payload", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  const first = await createViaHttp(
    env,
    { display_name: "Idem One", email: "idem-one@example.test" },
    { headers: { "Idempotency-Key": "create-one" } },
  );
  assert.equal(first.res.status, 201);
  const changed = await createViaHttp(
    env,
    { display_name: "Idem Two", email: "idem-two@example.test" },
    { headers: { "Idempotency-Key": "create-one" } },
  );
  assert.equal(changed.res.status, 409);
  assert.equal(changed.json.error, "idempotency_payload_conflict");
  const replay = await createViaHttp(
    env,
    { display_name: "Idem One", email: "idem-one@example.test" },
    { headers: { "Idempotency-Key": "create-one" } },
  );
  assert.equal(replay.res.status, 200);
  assert.equal(replay.json.idempotent, true);
  assert.equal(replay.json.customer.customer_id, first.json.customer.customer_id);
});

test("client-invented cursor is rejected", async () => {
  const kv = countingKV();
  const env = envWith(kv);
  await createViaHttp(env, { display_name: "Cursor", email: "cursor@example.test" });
  const url = new URL("https://example.test/company/customers");
  url.searchParams.set("tenant_id", TENANT_A);
  url.searchParams.set("company_id", COMPANY_A);
  url.searchParams.set("cursor", "not-a-server-cursor");
  const res = await worker.fetch(
    new Request(url, { headers: { "x-admin-token": ADMIN } }),
    env,
    {},
  );
  assert.equal(res.status, 400);
  assert.equal((await res.json()).error, "invalid_cursor");
});
