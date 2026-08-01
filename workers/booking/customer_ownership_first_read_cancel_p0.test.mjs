// CUSTOMER BOOKING AUTH P0 — ownership-first read/cancel
//
// Run:
//   node --test workers/booking/customer_ownership_first_read_cancel_p0.test.mjs

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
      store.set(key, val);
    },
    async delete(key) {
      store.delete(key);
    },
    async list(opts = {}) {
      const prefix = String(opts?.prefix || "");
      const keys = [...store.keys()].filter((name) =>
        prefix ? name.startsWith(prefix) : true,
      );
      return { keys: keys.map((name) => ({ name })), list_complete: true };
    },
  };
}

async function seedCustomerSession({
  tokenValue,
  tenantId,
  companyId,
  customerId,
  expiresAt = new Date(Date.now() + 3600_000).toISOString(),
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
      expires_at: expiresAt,
    },
  };
}

async function seedDriverSession({
  tokenValue,
  tenantId,
  companyId,
  driverId,
  expiresAt = new Date(Date.now() + 3600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `public_driver:session:${hash}:v1`,
    record: {
      role: "driver",
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      expires_at: expiresAt,
    },
  };
}

async function seedCompanySession({
  tokenValue,
  tenantId,
  companyId,
  expiresAt = new Date(Date.now() + 3600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `company_admin:session:${hash}:v1`,
    record: {
      role: "company_admin",
      tenant_id: tenantId,
      company_id: companyId,
      expires_at: expiresAt,
    },
  };
}

function seedBooking({
  bookingId,
  tenantId,
  companyId,
  customerId,
  status = "BOOKED",
  assignedDriverId = "D-alice",
}) {
  return {
    key: `booking:${bookingId}`,
    record: {
      booking_id: bookingId,
      tenant_id: tenantId,
      company_id: companyId,
      status,
      payment_status: "unpaid",
      customer_id: customerId,
      customerId,
      customer: { customer_id: customerId, customerId },
      assigned_driver_id: assignedDriverId,
      assignedDriverId,
      public_booking_reference: "2026-08-000005",
      planning_reference: "PLN-2026-000379",
    },
  };
}

function jsonReq(path, { method = "POST", token = null, body = null, query = "" } = {}) {
  const headers = { "content-type": "application/json" };
  if (token) headers["authorization"] = `Bearer ${token}`;
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

async function setupEnv() {
  const owner = await seedCustomerSession({
    tokenValue: "cus-owner-global",
    tenantId: "global",
    companyId: "global",
    customerId: "cust_owner_003ca664",
  });
  const foreign = await seedCustomerSession({
    tokenValue: "cus-foreign-global",
    tenantId: "global",
    companyId: "global",
    customerId: "cust_foreign_zzzz",
  });
  const driver = await seedDriverSession({
    tokenValue: "drv-alice",
    tenantId: "fluxidi_fluxidi_ddmh9g",
    companyId: "fluxidi_fluxidi_ddmh9g",
    driverId: "D-alice",
  });
  const company = await seedCompanySession({
    tokenValue: "co-fluxidi",
    tenantId: "fluxidi_fluxidi_ddmh9g",
    companyId: "fluxidi_fluxidi_ddmh9g",
  });
  const booking = seedBooking({
    bookingId: "2026-08-161",
    tenantId: "fluxidi_fluxidi_ddmh9g",
    companyId: "fluxidi_fluxidi_ddmh9g",
    customerId: "cust_owner_003ca664",
  });
  const seed = {
    [owner.key]: owner.record,
    [foreign.key]: foreign.record,
    [driver.key]: driver.record,
    [company.key]: company.record,
    [booking.key]: booking.record,
  };
  return {
    env: {
      ADMIN_TOKEN: ADMIN,
      BOOKING_KV: makeKV(seed),
      ALLOW_LEGACY_CUSTOMER_CONTACT_PROOF: "0",
    },
  };
}

test("1. global customer owns company-scoped booking GET → 200", async () => {
  const { env } = await setupEnv();
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-161", {
      method: "GET",
      token: "cus-owner-global",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.notEqual(j.error, "tenant_scope_conflict");
});

test("2. same customer cancel → accepted by auth (lifecycle may 409)", async () => {
  const { env } = await setupEnv();
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-161/status", {
      token: "cus-owner-global",
      body: {
        status: "CANCELLED",
        actor_role: "customer",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.ok([200, 409, 400].includes(res.status), `status=${res.status}`);
  assert.notEqual(j.error, "unauthorized");
  assert.notEqual(j.error, "booking_not_found");
  assert.notEqual(j.error, "tenant_scope_conflict");
});

test("3. foreign customer canonical id → opaque 404", async () => {
  const { env } = await setupEnv();
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-161", {
      method: "GET",
      token: "cus-foreign-global",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
  assert.equal(j.ok, false);
});

test("4. missing booking → opaque 404", async () => {
  const { env } = await setupEnv();
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-999", {
      method: "GET",
      token: "cus-owner-global",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

test("5. matching client tenant/company cannot be authorization source (still owner → 200)", async () => {
  const { env } = await setupEnv();
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-161", {
      method: "GET",
      token: "cus-owner-global",
      query: "?tenant_id=fluxidi_fluxidi_ddmh9g&company_id=fluxidi_fluxidi_ddmh9g",
    }),
    env,
    {},
  );
  const j = await res.json();
  // Ownership grants access; client scope is ignored (no conflict).
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.notEqual(j.error, "tenant_scope_conflict");
});

test("6. foreign client tenant/company → no leakage / no ownership bypass", async () => {
  const { env } = await setupEnv();
  const ownerRes = await worker.fetch(
    jsonReq("/bookings/2026-08-161", {
      method: "GET",
      token: "cus-owner-global",
      query: "?tenant_id=T-OTHER&company_id=C-OTHER",
    }),
    env,
    {},
  );
  const ownerJ = await ownerRes.json();
  // Owner still succeeds; foreign query scope ignored after ownership.
  assert.equal(ownerRes.status, 200);
  assert.equal(ownerJ.ok, true);

  const foreignRes = await worker.fetch(
    jsonReq("/bookings/2026-08-161", {
      method: "GET",
      token: "cus-foreign-global",
      query: "?tenant_id=fluxidi_fluxidi_ddmh9g&company_id=fluxidi_fluxidi_ddmh9g",
    }),
    env,
    {},
  );
  const foreignJ = await foreignRes.json();
  assert.equal(foreignRes.status, 404);
  assert.equal(foreignJ.error, "booking_not_found");
});

test("7. driver authorization unchanged (own booking GET with driver session)", async () => {
  const { env } = await setupEnv();
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-161", {
      method: "GET",
      token: "drv-alice",
      query: "?tenant_id=fluxidi_fluxidi_ddmh9g&company_id=fluxidi_fluxidi_ddmh9g",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.ok([200, 403].includes(res.status), `driver status=${res.status}`);
  assert.notEqual(j.error, "tenant_scope_conflict");
});

test("7b. company session foreign booking → opaque 404", async () => {
  const { env } = await setupEnv();
  // Seed a foreign-company booking and prove company session cannot see it.
  const foreignBooking = seedBooking({
    bookingId: "2026-08-foreign",
    tenantId: "T2",
    companyId: "C2",
    customerId: "cust_other",
  });
  await env.BOOKING_KV.put(foreignBooking.key, foreignBooking.record);
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-foreign", {
      method: "GET",
      token: "co-fluxidi",
      query: "?tenant_id=fluxidi_fluxidi_ddmh9g&company_id=fluxidi_fluxidi_ddmh9g",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

test("8. public/planning reference does not bypass canonical ownership", async () => {
  const { env } = await setupEnv();
  for (const ref of ["2026-08-000005", "PLN-2026-000379"]) {
    const res = await worker.fetch(
      jsonReq(`/bookings/${encodeURIComponent(ref)}`, {
        method: "GET",
        token: "cus-owner-global",
      }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 404, `ref=${ref}`);
    assert.equal(j.error, "booking_not_found", `ref=${ref}`);
  }
});

test("9. contact-only auth remains disabled", async () => {
  const { env } = await setupEnv();
  const res = await worker.fetch(
    jsonReq("/bookings/2026-08-161", {
      method: "GET",
      query:
        "?tenant_id=fluxidi_fluxidi_ddmh9g&company_id=fluxidi_fluxidi_ddmh9g&customer_email=x@example.com",
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});
