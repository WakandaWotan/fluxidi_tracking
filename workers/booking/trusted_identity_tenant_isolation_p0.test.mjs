// RELEASE-P0 — BOOKING WORKER TRUSTED-IDENTITY TENANT ISOLATION
//
// Focused route tests for tracking, driver status, customer read/cancel,
// pay/status, strict ownership, and allocator probe gating.
//
// Run:
//   node --test workers/booking/trusted_identity_tenant_isolation_p0.test.mjs

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

async function seedCustomerSession({
  tokenValue,
  tenantId,
  companyId,
  customerId,
  phoneHash = "phonehash_abc",
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
      phone_hash: phoneHash,
      expires_at: expiresAt,
    },
  };
}

function seedBooking({
  bookingId,
  tenantId,
  companyId,
  assignedDriverId = null,
  customerId = null,
  status = "CONFIRMED",
  trackingLast = null,
  omitCompanyId = false,
}) {
  const key = `booking:${bookingId}`;
  const record = {
    booking_id: bookingId,
    tenant_id: tenantId,
    ...(omitCompanyId ? {} : { company_id: companyId }),
    status,
    payment_status: "unpaid",
    ...(assignedDriverId
      ? {
          assigned_driver_id: assignedDriverId,
          assignedDriverId,
        }
      : {}),
    ...(customerId
      ? {
          customer_id: customerId,
          customerId,
          customer: { customer_id: customerId, customerId },
        }
      : {}),
    ...(trackingLast ? { tracking_last: trackingLast } : {}),
  };
  return { key, record };
}

async function makeEnv({
  bookings = [],
  driverSessions = [],
  companySessions = [],
  customerSessions = [],
  payments = [],
  probesEnabled = "0",
  legacyContact = "0",
} = {}) {
  const seed = {};
  for (const b of bookings) seed[b.key] = b.record;
  for (const d of driverSessions) seed[d.key] = d.record;
  for (const c of companySessions) seed[c.key] = c.record;
  for (const c of customerSessions) seed[c.key] = c.record;
  for (const p of payments) seed[p.key] = p.record;
  return {
    env: {
      ADMIN_TOKEN: ADMIN,
      BOOKING_KV: makeKV(seed),
      HUMAN_BOOKING_ID_PROBES_ENABLED: probesEnabled,
      ALLOW_LEGACY_CUSTOMER_CONTACT_PROOF: legacyContact,
    },
  };
}

function jsonReq(path, { method = "POST", token = null, adminToken = null, body = null, query = "" } = {}) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

async function setupBase() {
  const alice = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const bob = await seedDriverSession({
    tokenValue: "bob-token",
    tenantId: "T2",
    companyId: "C2",
    driverId: "D-bob",
  });
  const companyA = await seedCompanySession({
    tokenValue: "co-a-token",
    tenantId: "T1",
    companyId: "C1",
  });
  const companyB = await seedCompanySession({
    tokenValue: "co-b-token",
    tenantId: "T2",
    companyId: "C2",
  });
  const customerX = await seedCustomerSession({
    tokenValue: "cus-x-token",
    tenantId: "T1",
    companyId: "C1",
    customerId: "cust_x",
  });
  const customerY = await seedCustomerSession({
    tokenValue: "cus-y-token",
    tenantId: "T1",
    companyId: "C1",
    customerId: "cust_y",
  });
  const expiredCustomer = await seedCustomerSession({
    tokenValue: "cus-expired",
    tenantId: "T1",
    companyId: "C1",
    customerId: "cust_x",
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
  const bookingA = seedBooking({
    bookingId: "B-A1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-alice",
    customerId: "cust_x",
    trackingLast: { lat: 50.1, lng: 4.2, ts: "2026-08-01T10:00:00Z" },
  });
  const bookingB = seedBooking({
    bookingId: "B-B1",
    tenantId: "T2",
    companyId: "C2",
    assignedDriverId: "D-bob",
    customerId: "cust_foreign",
    trackingLast: { lat: 51.9, lng: 5.1, ts: "2026-08-01T11:00:00Z" },
  });
  const bookingUnassigned = seedBooking({
    bookingId: "B-U1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: null,
    customerId: "cust_x",
  });
  const bookingAmbiguous = seedBooking({
    bookingId: "B-AMB",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-alice",
    omitCompanyId: true,
  });
  const paymentA = {
    key: "payment:PAY-A1",
    record: {
      payment_id: "PAY-A1",
      booking_id: "B-A1",
      tenant_id: "T1",
      company_id: "C1",
      payment_status: "pending",
    },
  };
  const { env } = await makeEnv({
    bookings: [bookingA, bookingB, bookingUnassigned, bookingAmbiguous],
    driverSessions: [alice, bob],
    companySessions: [companyA, companyB],
    customerSessions: [customerX, customerY, expiredCustomer],
    payments: [paymentA],
  });
  return { env };
}

// ---- Tracking (1-7) ----

test("1. tracking/start no session → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/start", {
      body: { booking_id: "B-A1", tenant_id: "T1", company_id: "C1" },
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("2. tracking/start forged tenant/company without session → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/start", {
      body: { booking_id: "B-B1", tenant_id: "T2", company_id: "C2" },
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("3. tracking/start valid driver + assigned booking → allowed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/start", {
      token: "alice-token",
      body: { booking_id: "B-A1", tenant_id: "T1", company_id: "C1" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.ok(j.trip_id);
});

test("4. tracking/start valid driver + foreign booking → opaque 404", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/start", {
      token: "alice-token",
      body: { booking_id: "B-B1", tenant_id: "T1", company_id: "C1" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

test("5. tracking/last company session + owned booking → allowed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/last", {
      method: "GET",
      token: "co-a-token",
      query: "?booking_id=B-A1&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.tracking_last?.lat, 50.1);
});

test("6. tracking/last company session + foreign booking → opaque 404", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/last", {
      method: "GET",
      token: "co-a-token",
      query: "?booking_id=B-B1&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

test("7. tracking/last does not leak foreign GPS", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/last", {
      method: "GET",
      token: "alice-token",
      query: "?booking_id=B-B1&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
  assert.equal(j.tracking_last, undefined);
  assert.equal(j.data?.tracking_last, undefined);
});

// ---- Driver status (8-12) ----

test("8. spoof actor_driver_id without session → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      body: {
        status: "EN_ROUTE",
        actor_role: "driver",
        actor_driver_id: "D-alice",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("9. driver A session + driver B id in body → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      token: "alice-token",
      body: {
        status: "EN_ROUTE",
        actor_role: "driver",
        actor_driver_id: "D-bob",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  assert.equal(res.status, 403);
});

test("10. assigned driver session → valid transition allowed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      token: "alice-token",
      body: {
        status: "EN_ROUTE",
        actor_role: "driver",
        actor_driver_id: "D-alice",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.ok(res.status === 200 || res.status === 400 || res.status === 409);
  if (res.status === 200) assert.equal(j.ok, true);
  if (res.status !== 200) {
    // Auth passed; lifecycle may still reject transition — must not be 401/403/404 auth failure.
    assert.notEqual(j.error, "unauthorized");
    assert.notEqual(j.error, "booking_not_assigned_to_driver");
    assert.notEqual(j.error, "booking_not_found");
  }
});

test("11. unassigned driver session → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-U1/status", {
      token: "alice-token",
      body: {
        status: "EN_ROUTE",
        actor_role: "driver",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "booking_not_assigned_to_driver");
});

test("12. foreign-company driver session → opaque 404", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-B1/status", {
      token: "alice-token",
      body: {
        status: "EN_ROUTE",
        actor_role: "driver",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

// ---- Customer (13-17) ----

test("13. customer email/phone only → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1", {
      method: "GET",
      query: "?tenant_id=T1&company_id=C1&customer_email=x@example.com&customer_phone=%2B321234",
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("14. valid customer token for booking X → X allowed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1", {
      method: "GET",
      token: "cus-x-token",
      query: "?tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
});

test("15. token for X → booking Y denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-B1", {
      method: "GET",
      token: "cus-x-token",
      query: "?tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

test("16. expired customer token → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1", {
      method: "GET",
      token: "cus-expired",
      query: "?tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("17. cancel requires valid exact-booking token", async () => {
  const { env } = await setupBase();
  const noTok = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      body: {
        status: "CANCELLED",
        actor_role: "customer",
        customer_email: "x@example.com",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  assert.equal(noTok.status, 401);

  const wrongTok = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      token: "cus-y-token",
      body: {
        status: "CANCELLED",
        actor_role: "customer",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  const wrongJ = await wrongTok.json();
  assert.equal(wrongTok.status, 404);
  assert.equal(wrongJ.error, "booking_not_found");

  const okTok = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      token: "cus-x-token",
      body: {
        status: "CANCELLED",
        actor_role: "customer",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  const okJ = await okTok.json();
  // Auth passed; cancellation policy may still 409.
  assert.ok([200, 409, 400].includes(okTok.status));
  assert.notEqual(okJ.error, "unauthorized");
  assert.notEqual(okJ.error, "booking_not_found");
});

// ---- Payment (18-20) ----

test("18. unauthenticated pay/status → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/pay/status", {
      method: "GET",
      query: "?id=PAY-A1&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("19. valid company session pay/status → allowed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/pay/status", {
      method: "GET",
      token: "co-a-token",
      query: "?id=PAY-A1&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
});

test("20. foreign payment/booking → opaque 404", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/pay/status", {
      method: "GET",
      token: "co-b-token",
      query: "?id=PAY-A1&tenant_id=T2&company_id=C2",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

// ---- Strict ownership (21-22) ----

test("21. missing company_id on ambiguous record → fail closed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/start", {
      token: "alice-token",
      body: { booking_id: "B-AMB", tenant_id: "T1", company_id: "C1" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

test("22. body company_id cannot override authenticated scope", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/start", {
      token: "alice-token",
      body: { booking_id: "B-A1", tenant_id: "T1", company_id: "C2" },
    }),
    env,
    {},
  );
  assert.equal(res.status, 403);
});

// ---- Admin probes (23-25) ----

test("23. admin token + probes flag off → mutation denied", async () => {
  const { env } = await setupBase();
  env.HUMAN_BOOKING_ID_PROBES_ENABLED = "0";
  const res = await worker.fetch(
    jsonReq("/admin/booking-id-allocator/allocate-probe", {
      adminToken: ADMIN,
      body: { count: 1 },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "allocator_probes_disabled");
});

test("24. no admin token → probe denied", async () => {
  const { env } = await makeEnv({ probesEnabled: "1" });
  const res = await worker.fetch(
    jsonReq("/admin/booking-id-allocator/allocate-probe", {
      body: { count: 1 },
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("25. explicit temporary flag + admin token → probe gate opens (test only)", async () => {
  const { env } = await makeEnv({ probesEnabled: "1" });
  const res = await worker.fetch(
    jsonReq("/admin/booking-id-allocator/allocate-probe", {
      adminToken: ADMIN,
      body: { count: 1 },
    }),
    env,
    {},
  );
  const j = await res.json();
  // Gate passed; may fail later for missing DO binding — must not be probes_disabled.
  assert.notEqual(j.error, "allocator_probes_disabled");
  assert.notEqual(res.status, 401);
});

// ---- Expanded high-risk matrix ----

test("26. tracking/ping without trusted identity → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/ping", {
      body: {
        booking_id: "B-A1",
        tenant_id: "T1",
        company_id: "C1",
        lat: 50.1,
        lng: 4.2,
      },
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("27. tracking/last without trusted identity → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/last", {
      method: "GET",
      query: "?booking_id=B-A1&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("28. tracking/ping assigned driver → allowed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/ping", {
      token: "alice-token",
      body: {
        booking_id: "B-A1",
        tenant_id: "T1",
        company_id: "C1",
        lat: 50.11,
        lng: 4.21,
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.tracking_last?.lat, 50.11);
});

test("29. tracking/ping unassigned same-company booking → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/tracking/ping", {
      token: "alice-token",
      body: {
        booking_id: "B-U1",
        tenant_id: "T1",
        company_id: "C1",
        lat: 50.1,
        lng: 4.2,
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "booking_not_assigned_to_driver");
});

test("30. track/booking/status spoofed actor_driver_id without session → denied", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/track/booking/status", {
      body: {
        booking_id: "B-A1",
        status: "EN_ROUTE",
        actor_role: "driver",
        actor_driver_id: "D-alice",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("31. company session status cannot be overridden by body company_id", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      token: "co-a-token",
      body: {
        status: "CANCELLED",
        actor_role: "admin",
        tenant_id: "T1",
        company_id: "C2",
      },
    }),
    env,
    {},
  );
  assert.equal(res.status, 403);
});

test("32. company session cancels owned booking (auth passes)", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1/status", {
      token: "co-a-token",
      body: {
        status: "CANCELLED",
        actor_role: "admin",
        tenant_id: "T1",
        company_id: "C1",
      },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.ok([200, 400, 409].includes(res.status));
  assert.notEqual(j.error, "unauthorized");
  assert.notEqual(j.error, "booking_not_found");
});

test("33. revoked customer session → denied", async () => {
  const { env } = await setupBase();
  // Delete the session record to simulate revocation.
  const hash = await sha256Hex("cus-x-token");
  await env.BOOKING_KV.delete(`customer:session:${hash}:v1`);
  const res = await worker.fetch(
    jsonReq("/bookings/B-A1", {
      method: "GET",
      token: "cus-x-token",
      query: "?tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  assert.equal(res.status, 401);
});

test("34. missing booking and foreign booking → equivalent opaque 404", async () => {
  const { env } = await setupBase();
  const missing = await worker.fetch(
    jsonReq("/bookings/B-MISSING", {
      method: "GET",
      token: "cus-x-token",
      query: "?tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const foreign = await worker.fetch(
    jsonReq("/bookings/B-B1", {
      method: "GET",
      token: "cus-x-token",
      query: "?tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const mj = await missing.json();
  const fj = await foreign.json();
  assert.equal(missing.status, 404);
  assert.equal(foreign.status, 404);
  assert.equal(mj.error, "booking_not_found");
  assert.equal(fj.error, "booking_not_found");
  assert.deepEqual(Object.keys(mj).sort(), Object.keys(fj).sort());
});

test("35. missing payment and foreign payment → equivalent opaque 404", async () => {
  const { env } = await setupBase();
  const missing = await worker.fetch(
    jsonReq("/pay/status", {
      method: "GET",
      token: "co-a-token",
      query: "?id=PAY-MISSING&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const foreign = await worker.fetch(
    jsonReq("/pay/status", {
      method: "GET",
      token: "co-b-token",
      query: "?id=PAY-A1&tenant_id=T2&company_id=C2",
    }),
    env,
    {},
  );
  const mj = await missing.json();
  const fj = await foreign.json();
  assert.equal(missing.status, 404);
  assert.equal(foreign.status, 404);
  assert.equal(mj.error, "booking_not_found");
  assert.equal(fj.error, "booking_not_found");
});

test("36. record missing tenant_id → fail closed on tracking", async () => {
  const alice = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const booking = {
    key: "booking:B-NOTEN",
    record: {
      booking_id: "B-NOTEN",
      company_id: "C1",
      assigned_driver_id: "D-alice",
      status: "CONFIRMED",
    },
  };
  const { env } = await makeEnv({
    bookings: [booking],
    driverSessions: [alice],
  });
  const res = await worker.fetch(
    jsonReq("/tracking/start", {
      token: "alice-token",
      body: { booking_id: "B-NOTEN", tenant_id: "T1", company_id: "C1" },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 404);
  assert.equal(j.error, "booking_not_found");
});

test("37. all mutating allocator probes denied when flag off", async () => {
  const { env } = await makeEnv({ probesEnabled: "0" });
  const paths = [
    "/admin/booking-id-allocator/allocate-probe",
    "/admin/booking-id-allocator/create-probe",
    "/admin/booking-id-allocator/collision-probe",
    "/admin/booking-id-allocator/neutralize-probes",
    "/admin/booking-id-allocator/seed",
  ];
  for (const path of paths) {
    const res = await worker.fetch(
      jsonReq(path, { adminToken: ADMIN, body: { count: 1, apply: true } }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 403, path);
    assert.equal(j.error, "allocator_probes_disabled", path);
  }
});

test("38. rollback-prepare apply:true denied when probes flag off", async () => {
  const { env } = await makeEnv({ probesEnabled: "0" });
  const res = await worker.fetch(
    jsonReq("/admin/booking-id-allocator/rollback-prepare", {
      adminToken: ADMIN,
      body: { apply: true },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "allocator_probes_disabled");
});

test("39. rollback-prepare read-only preview allowed for admin when probes off", async () => {
  const { env } = await makeEnv({ probesEnabled: "0" });
  const res = await worker.fetch(
    jsonReq("/admin/booking-id-allocator/rollback-prepare", {
      adminToken: ADMIN,
      body: { apply: false },
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.notEqual(j.error, "allocator_probes_disabled");
  assert.notEqual(res.status, 401);
});

test("40. document registry skips records with missing ownership", async () => {
  const { listIssuedDocumentRecordsForBooking } = await import(
    "./modules/document_core.js"
  );
  const store = new Map();
  const scope = { tenant_id: "T1", company_id: "C1" };
  const bookingId = "B-DOC1";
  // Index points at a document whose registry record lacks company_id.
  const idxKey = `doc_by_booking:T1:C1:${bookingId}:invoice:DOC1`;
  store.set(idxKey, "DOC1");
  store.set("doc_registry:T1:C1:DOC1", JSON.stringify({
    document_id: "DOC1",
    tenant_id: "T1",
    // company_id intentionally missing → must fail closed
    source_booking_id: bookingId,
    document_type: "invoice",
  }));
  const env = {
    BOOKING_KV: {
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
      async list({ prefix }) {
        const keys = [...store.keys()]
          .filter((k) => k.startsWith(prefix))
          .map((name) => ({ name }));
        return { keys, list_complete: true };
      },
    },
  };
  const out = await listIssuedDocumentRecordsForBooking(env, scope, bookingId);
  assert.equal(out.ok, true);
  assert.equal((out.records || out.documents || []).length || 0, 0);
});

test("41. customer session pay/status for owned payment → allowed", async () => {
  const { env } = await setupBase();
  const res = await worker.fetch(
    jsonReq("/pay/status", {
      method: "GET",
      token: "cus-x-token",
      query: "?id=PAY-A1&tenant_id=T1&company_id=C1",
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
});

test("42. probes flag defaults off (missing env var)", async () => {
  const { env } = await makeEnv({});
  delete env.HUMAN_BOOKING_ID_PROBES_ENABLED;
  const res = await worker.fetch(
    jsonReq("/admin/booking-id-allocator/create-probe", {
      adminToken: ADMIN,
      body: {},
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.error, "allocator_probes_disabled");
});
