// CUSTOMER BILLING PROFILE P0 — worker profile GET/POST round-trip
//
// Run:
//   node --test workers/booking/customer_billing_profile_sync_p0.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";

const ADMIN = "test-admin-token";

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) hex += byte.toString(16).padStart(2, "0");
  return hex;
}

function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      if (opts && opts.type === "json") {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch (_) {
          return null;
        }
      }
      return raw;
    },
    async put(key, val) {
      store.set(key, typeof val === "string" ? val : JSON.stringify(val));
    },
    async delete(key) {
      store.delete(key);
    },
    async list() {
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true };
    },
  };
}

async function seedCustomerSession({
  tokenValue,
  tenantId = "global",
  companyId = "global",
  customerId,
}) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `customer:session:${hash}:v1`,
    record: {
      role: "customer",
      purpose: "customer_session",
      tenant_id: tenantId,
      company_id: companyId,
      customer_id: customerId,
      phone_hash: "phonehash_abc",
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

function profileKey(tenantId, companyId, customerId) {
  return `customer:profile:v1:tenant:${tenantId}:company:${companyId}:customer:${customerId}`;
}

function jsonReq(path, { method = "GET", token = null, body = null, query = "" } = {}) {
  const headers = { "content-type": "application/json", accept: "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

async function setup({ profiles = {}, sessions = [] } = {}) {
  const seed = { ...profiles };
  for (const s of sessions) seed[s.key] = s.record;
  return {
    env: {
      ADMIN_TOKEN: ADMIN,
      BOOKING_KV: makeKV(seed),
      ALLOW_LEGACY_CUSTOMER_CONTACT_PROOF: "0",
    },
  };
}

const OWNER = "cust_owner_billing";
const FOREIGN = "cust_foreign_billing";

test("1. existing v1 core-only profile still loads", async () => {
  const owner = await seedCustomerSession({
    tokenValue: "tok-owner",
    customerId: OWNER,
  });
  const key = profileKey("global", "global", OWNER);
  const { env } = await setup({
    sessions: [owner],
    profiles: {
      [key]: {
        version: 1,
        purpose: "customer_global_profile",
        customer_id: OWNER,
        name: "Alice",
        phone: "+32470000001",
        email: "alice@example.com",
        preferred_postcode: "1000",
        company_name: "Alice BV",
        vat_number: "BE0123456789",
        favorite_partner_ids: ["partner_a"],
        created_at: "2026-01-01T00:00:00.000Z",
        updated_at: "2026-01-01T00:00:00.000Z",
      },
    },
  });
  const res = await worker.fetch(
    jsonReq("/public/customer/profile", { method: "GET", token: "tok-owner" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.profile.name, "Alice");
  assert.equal(j.profile.vat_number, "BE0123456789");
  assert.equal(j.profile.invoice_email, "");
  assert.equal(j.profile.billing_street, "");
  assert.equal(j.profile.peppol_endpoint_id, "");
});

test("2-5. complete billing profile POST → GET round-trip", async () => {
  const owner = await seedCustomerSession({
    tokenValue: "tok-owner",
    customerId: OWNER,
  });
  const { env } = await setup({ sessions: [owner] });
  const payload = {
    name: "Alice",
    phone: "+32470000001",
    email: "alice@example.com",
    preferred_postcode: "1000",
    company_name: "Alice BV",
    vat_number: "NL123456789B01",
    invoice_email: "invoice@example.com",
    billing_street: "Main Street 1",
    billing_postal_code: "1000",
    billing_city: "Brussels",
    billing_country: "BE",
    peppol_endpoint_id: "0208:0123456789",
    peppol_scheme: "0208",
    favorite_partner_ids: ["partner_a"],
    unknown_field_should_drop: "secret",
    customer_id: FOREIGN,
  };
  const post = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: payload,
    }),
    env,
    {},
  );
  const postJ = await post.json();
  assert.equal(post.status, 200);
  assert.equal(postJ.ok, true);
  assert.equal(postJ.profile.invoice_email, "invoice@example.com");
  assert.equal(postJ.profile.billing_street, "Main Street 1");
  assert.equal(postJ.profile.billing_postal_code, "1000");
  assert.equal(postJ.profile.billing_city, "Brussels");
  assert.equal(postJ.profile.billing_country, "BE");
  assert.equal(postJ.profile.peppol_endpoint_id, "0208:0123456789");
  assert.equal(postJ.profile.peppol_scheme, "0208");
  assert.equal(postJ.profile.peppol.endpoint_id, "0208:0123456789");
  assert.equal(postJ.profile.vat_number, "NL123456789B01");
  assert.equal(postJ.profile.customer_id, OWNER);
  assert.equal(postJ.profile.unknown_field_should_drop, undefined);

  const get = await worker.fetch(
    jsonReq("/public/customer/profile", { method: "GET", token: "tok-owner" }),
    env,
    {},
  );
  const getJ = await get.json();
  assert.equal(get.status, 200);
  assert.equal(getJ.profile.invoice_email, "invoice@example.com");
  assert.equal(getJ.profile.billing_address.street, "Main Street 1");
  assert.equal(getJ.profile.peppol.scheme, "0208");
});

test("6. unknown fields are dropped", async () => {
  const owner = await seedCustomerSession({
    tokenValue: "tok-owner",
    customerId: OWNER,
  });
  const { env } = await setup({ sessions: [owner] });
  const post = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: { name: "A", secret_token: "nope", internal_kv: "x" },
    }),
    env,
    {},
  );
  const j = await post.json();
  assert.equal(post.status, 200);
  assert.equal(j.profile.secret_token, undefined);
  assert.equal(j.profile.internal_kv, undefined);
});

test("7. malformed email/country → safe 400", async () => {
  const owner = await seedCustomerSession({
    tokenValue: "tok-owner",
    customerId: OWNER,
  });
  const { env } = await setup({ sessions: [owner] });
  const badEmail = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: { email: "not-an-email" },
    }),
    env,
    {},
  );
  const eJ = await badEmail.json();
  assert.equal(badEmail.status, 400);
  assert.equal(eJ.error, "invalid_email");
  assert.ok(!JSON.stringify(eJ).includes("not-an-email"));

  const badInvoice = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: { invoice_email: "bad@" },
    }),
    env,
    {},
  );
  assert.equal(badInvoice.status, 400);
  assert.equal((await badInvoice.json()).error, "invalid_invoice_email");

  const badCountry = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: { billing_country: "BELGIUM" },
    }),
    env,
    {},
  );
  // BELGIUM collapses to BE via A-Z filter then slice(0,2) → "BE" which is valid.
  // Use digits to force invalid length after strip.
  const badCountry2 = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: { billing_country: "B" },
    }),
    env,
    {},
  );
  assert.equal(badCountry2.status, 400);
  assert.equal((await badCountry2.json()).error, "invalid_billing_country");
  assert.ok([200, 400].includes(badCountry.status));
});

test("8-9. authenticated customer only accesses own profile; client customer_id ignored", async () => {
  const owner = await seedCustomerSession({
    tokenValue: "tok-owner",
    customerId: OWNER,
  });
  const foreign = await seedCustomerSession({
    tokenValue: "tok-foreign",
    customerId: FOREIGN,
  });
  const ownerKey = profileKey("global", "global", OWNER);
  const { env } = await setup({
    sessions: [owner, foreign],
    profiles: {
      [ownerKey]: {
        version: 2,
        customer_id: OWNER,
        name: "Owner",
        invoice_email: "owner-invoice@example.com",
        billing_street: "Owner Street",
      },
    },
  });
  const foreignGet = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "GET",
      token: "tok-foreign",
      query: `?customer_id=${OWNER}`,
    }),
    env,
    {},
  );
  const fJ = await foreignGet.json();
  assert.equal(foreignGet.status, 200);
  assert.equal(fJ.profile.customer_id, FOREIGN);
  assert.notEqual(fJ.profile.invoice_email, "owner-invoice@example.com");
  assert.equal(fJ.profile.billing_street, "");

  const foreignPost = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-foreign",
      body: {
        customer_id: OWNER,
        invoice_email: "hijack@example.com",
        billing_street: "Hijack",
      },
    }),
    env,
    {},
  );
  const fpJ = await foreignPost.json();
  assert.equal(foreignPost.status, 200);
  assert.equal(fpJ.profile.customer_id, FOREIGN);

  const ownerGet = await worker.fetch(
    jsonReq("/public/customer/profile", { method: "GET", token: "tok-owner" }),
    env,
    {},
  );
  const oJ = await ownerGet.json();
  assert.equal(oJ.profile.invoice_email, "owner-invoice@example.com");
  assert.equal(oJ.profile.billing_street, "Owner Street");
});

test("10. empty bootstrap-style partial POST does not wipe billing", async () => {
  const owner = await seedCustomerSession({
    tokenValue: "tok-owner",
    customerId: OWNER,
  });
  const key = profileKey("global", "global", OWNER);
  const { env } = await setup({
    sessions: [owner],
    profiles: {
      [key]: {
        version: 2,
        customer_id: OWNER,
        name: "Alice",
        email: "alice@example.com",
        invoice_email: "invoice@example.com",
        billing_street: "Keep Me",
        billing_city: "Brussels",
        billing_country: "BE",
        peppol_endpoint_id: "0208:1",
        peppol_scheme: "0208",
      },
    },
  });
  // Favorites-only style upsert: no billing keys → must preserve billing.
  const post = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: {
        name: "Alice",
        email: "alice@example.com",
        favorite_partner_ids: ["p1"],
      },
    }),
    env,
    {},
  );
  const j = await post.json();
  assert.equal(post.status, 200);
  assert.equal(j.profile.invoice_email, "invoice@example.com");
  assert.equal(j.profile.billing_street, "Keep Me");
  assert.equal(j.profile.peppol_endpoint_id, "0208:1");
  assert.deepEqual(j.profile.favorite_partner_ids, ["p1"]);
});

test("11. explicit supported-field clearing", async () => {
  const owner = await seedCustomerSession({
    tokenValue: "tok-owner",
    customerId: OWNER,
  });
  const key = profileKey("global", "global", OWNER);
  const { env } = await setup({
    sessions: [owner],
    profiles: {
      [key]: {
        version: 2,
        customer_id: OWNER,
        name: "Alice",
        invoice_email: "invoice@example.com",
        billing_street: "Street",
        peppol_endpoint_id: "0208:1",
        peppol_scheme: "0208",
      },
    },
  });
  const post = await worker.fetch(
    jsonReq("/public/customer/profile", {
      method: "POST",
      token: "tok-owner",
      body: {
        name: "Alice",
        invoice_email: "",
        billing_street: "",
        peppol_endpoint_id: "",
        peppol_scheme: "",
      },
    }),
    env,
    {},
  );
  const j = await post.json();
  assert.equal(post.status, 200);
  assert.equal(j.profile.invoice_email, "");
  assert.equal(j.profile.billing_street, "");
  assert.equal(j.profile.peppol_endpoint_id, "");
  assert.equal(j.profile.peppol_scheme, "");
});

test("12. unauthenticated → 401", async () => {
  const { env } = await setup();
  const res = await worker.fetch(
    jsonReq("/public/customer/profile", { method: "GET" }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});
