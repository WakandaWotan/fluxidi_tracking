// PAYMENT-AUTH-P0-1 - Regression tests proving the in-car payment routes
// (booking payment + operational-leg payment) accept the scoped
// driver-session / company-owner-session / admin-token contract instead of
// admin-only auth, while preserving tenant/company/driver isolation and
// payment idempotency.
//
// Run:
//   node --test workers/booking/payment_auth_p0_1.test.mjs

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
  role = "driver",
  origin = null,
  expiresAt = new Date(Date.now() + 3600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  const key = `public_driver:session:${hash}:v1`;
  return {
    key,
    record: {
      role,
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      expires_at: expiresAt,
      ...(origin ? { origin } : {}),
    },
  };
}

async function seedCompanySession({
  tokenValue,
  tenantId,
  companyId,
  role = "company_admin",
  expiresAt = new Date(Date.now() + 3600_000).toISOString(),
}) {
  const hash = await sha256Hex(tokenValue);
  const key = `company_admin:session:${hash}:v1`;
  return {
    key,
    record: {
      role,
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
  assignedDriverId = null,
  paymentStatus = "unpaid",
  status = "planned",
}) {
  // Real repository key used by loadBookingRecord / updateBookingPaymentAuthoritative.
  const key = `booking:${bookingId}`;
  const record = {
    booking_id: bookingId,
    tenant_id: tenantId,
    company_id: companyId,
    status,
    payment_status: paymentStatus,
    paymentStatus,
    ...(assignedDriverId
      ? {
          assigned_driver_id: assignedDriverId,
          assignedDriverId,
        }
      : {}),
  };
  return { key, record };
}

function assertNoOutboundPspFetch(label) {
  const original = global.fetch;
  const hits = [];
  global.fetch = async (input, init) => {
    const href = typeof input === "string" ? input : input?.url || "";
    hits.push(String(href));
    throw new Error(`${label}: unexpected outbound fetch to ${href}`);
  };
  return {
    hits,
    restore() {
      global.fetch = original;
    },
    assertClean() {
      const forbidden = hits.filter((h) =>
        /mollie|billit|pos\.|terminal/i.test(h),
      );
      assert.equal(
        forbidden.length,
        0,
        `${label}: unexpected Mollie/Billit/POS fetch(s): ${forbidden.join(", ")}`,
      );
    },
  };
}

async function makeEnv({ bookings = [], driverSessions = [], companySessions = [] } = {}) {
  const seed = {};
  for (const b of bookings) seed[b.key] = b.record;
  for (const d of driverSessions) seed[d.key] = d.record;
  for (const c of companySessions) seed[c.key] = c.record;
  const bookingKv = makeKV(seed);
  return {
    env: { ADMIN_TOKEN: ADMIN, BOOKING_KV: bookingKv },
    bookingKv,
  };
}

function paymentRequest({
  bookingId,
  legId = null,
  token = null,
  adminToken = null,
  body,
}) {
  const headers = { "content-type": "application/json" };
  if (adminToken) headers["x-admin-token"] = adminToken;
  if (token) headers["authorization"] = `Bearer ${token}`;
  const path = legId
    ? `/bookings/${bookingId}/legs/${legId}/payment`
    : `/bookings/${bookingId}/payment`;
  return new Request(`https://booking.internal${path}`, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function paidPayload(extra = {}) {
  return {
    payment_status: "paid",
    payment_method: "qr_code",
    payment_source: "in_car",
    amount: 24.5,
    currency: "EUR",
    ...extra,
  };
}

// ---------------------------------------------------------------------------
// No-auth remains a structured 401 on both routes.
// ---------------------------------------------------------------------------

test("no-auth -> 401 structured JSON on /bookings/:id/payment", async () => {
  const { env } = await makeEnv({
    bookings: [
      seedBooking({ bookingId: "b1", tenantId: "T1", companyId: "C1" }),
    ],
  });
  const res = await worker.fetch(
    paymentRequest({ bookingId: "b1", body: paidPayload({ tenant_id: "T1", company_id: "C1" }) }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.ok, false);
  assert.equal(j.error, "unauthorized");
});

test("no-auth -> 401 structured JSON on /bookings/:id/legs/:legId/payment", async () => {
  const { env } = await makeEnv({
    bookings: [
      seedBooking({ bookingId: "b1", tenantId: "T1", companyId: "C1" }),
    ],
  });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b1",
      legId: "leg1",
      body: paidPayload({ tenant_id: "T1", company_id: "C1" }),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 401);
  assert.equal(j.ok, false);
  assert.equal(j.error, "unauthorized");
});

// ---------------------------------------------------------------------------
// Driver-session mark-paid.
// ---------------------------------------------------------------------------

test("valid driver-session mark-paid succeeds for its assigned street ride", async () => {
  const booking = seedBooking({
    bookingId: "b_street_1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-alice",
    status: "completed",
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env, bookingKv } = await makeEnv({
    bookings: [booking],
    driverSessions: [driver],
  });
  // Positive control: fixture must start unpaid, otherwise a no-op path
  // could vacuously pass a "paid" assertion.
  assert.equal(bookingKv.store.get(booking.key).payment_status, "unpaid");
  const fetchGuard = assertNoOutboundPspFetch("street-driver-mark-paid");
  try {
    const res = await worker.fetch(
      paymentRequest({
        bookingId: "b_street_1",
        token: "alice-token",
        body: paidPayload({ payment_method: "cash" }),
      }),
      env,
      {},
    );
    const j = await res.json();
    assert.equal(res.status, 200);
    assert.equal(j.ok, true);
    assert.equal(j.payment_status, "paid");
    const stored = bookingKv.store.get(booking.key);
    const storedRec = typeof stored === "string" ? JSON.parse(stored) : stored;
    assert.equal(storedRec.payment_status, "paid");
    assert.notEqual(storedRec.payment_provider, "mollie");
    fetchGuard.assertClean();
  } finally {
    fetchGuard.restore();
  }
});

test("operator-minted driver session mark-paid succeeds identically to a standalone driver session", async () => {
  const booking = seedBooking({
    bookingId: "b_mint_1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-alice",
  });
  const minted = await seedDriverSession({
    tokenValue: "minted-alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    origin: "operator_mint",
  });
  const { env, bookingKv } = await makeEnv({
    bookings: [booking],
    driverSessions: [minted],
  });
  assert.equal(bookingKv.store.get(booking.key).payment_status, "unpaid");
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b_mint_1",
      token: "minted-alice-token",
      body: paidPayload({ payment_method: "qr_code" }),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.payment_status, "paid");
  const stored = bookingKv.store.get(booking.key);
  const storedRec = typeof stored === "string" ? JSON.parse(stored) : stored;
  assert.equal(storedRec.payment_status, "paid");
});

test("valid driver-session mark-paid succeeds for a planned assigned booking via leg route (no operational legs -> parent fallback)", async () => {
  const booking = seedBooking({
    bookingId: "b_planned_1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-alice",
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env } = await makeEnv({ bookings: [booking], driverSessions: [driver] });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b_planned_1",
      legId: "leg1",
      token: "alice-token",
      body: paidPayload(),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
});

test("driver A cannot mark driver B's booking paid -> 403", async () => {
  const booking = seedBooking({
    bookingId: "b_bob_1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-bob",
  });
  const alice = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env } = await makeEnv({ bookings: [booking], driverSessions: [alice] });
  const res = await worker.fetch(
    paymentRequest({ bookingId: "b_bob_1", token: "alice-token", body: paidPayload() }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "booking_not_assigned_to_driver");
});

test("driver A cannot mark driver B's leg-scoped booking paid -> 403", async () => {
  const booking = seedBooking({
    bookingId: "b_bob_2",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-bob",
  });
  const alice = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env } = await makeEnv({ bookings: [booking], driverSessions: [alice] });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b_bob_2",
      legId: "leg1",
      token: "alice-token",
      body: paidPayload(),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "booking_not_assigned_to_driver");
});

test("tenant/company A driver cannot mark tenant/company B's booking paid -> 403 (session-derived scope wins)", async () => {
  const booking = seedBooking({
    bookingId: "b_other_tenant",
    tenantId: "T2",
    companyId: "C2",
    assignedDriverId: "D-alice",
  });
  const alice = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env } = await makeEnv({ bookings: [booking], driverSessions: [alice] });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b_other_tenant",
      token: "alice-token",
      // Client tries to claim the foreign tenant/company explicitly.
      body: paidPayload({ tenant_id: "T2", company_id: "C2" }),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 403);
  assert.equal(j.ok, false);
  assert.equal(j.error, "forbidden");
});

// ---------------------------------------------------------------------------
// Company-owner session mark-paid.
// ---------------------------------------------------------------------------

test("company-owner session succeeds for its own company's booking", async () => {
  const booking = seedBooking({ bookingId: "b_comp_1", tenantId: "T1", companyId: "C1" });
  const opA = await seedCompanySession({
    tokenValue: "operator-a-token",
    tenantId: "T1",
    companyId: "C1",
  });
  const { env } = await makeEnv({ bookings: [booking], companySessions: [opA] });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b_comp_1",
      token: "operator-a-token",
      body: paidPayload({ tenant_id: "T1", company_id: "C1" }),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.payment_status, "paid");
});

test("company-owner session cannot mark a foreign company's booking paid -> 403", async () => {
  const booking = seedBooking({ bookingId: "b_comp_2", tenantId: "T2", companyId: "C2" });
  const opA = await seedCompanySession({
    tokenValue: "operator-a-token",
    tenantId: "T1",
    companyId: "C1",
  });
  const { env } = await makeEnv({ bookings: [booking], companySessions: [opA] });
  // Client tries to claim the foreign scope explicitly - rejected at auth.
  const resClaim = await worker.fetch(
    paymentRequest({
      bookingId: "b_comp_2",
      token: "operator-a-token",
      body: paidPayload({ tenant_id: "T2", company_id: "C2" }),
    }),
    env,
    {},
  );
  const jClaim = await resClaim.json();
  assert.equal(resClaim.status, 403);
  assert.equal(jClaim.ok, false);
  assert.equal(jClaim.error, "forbidden");

  // Own-scope body against a foreign booking record - rejected at booking scope.
  const resScope = await worker.fetch(
    paymentRequest({
      bookingId: "b_comp_2",
      token: "operator-a-token",
      body: paidPayload({ tenant_id: "T1", company_id: "C1" }),
    }),
    env,
    {},
  );
  const jScope = await resScope.json();
  assert.equal(resScope.status, 403);
  assert.equal(jScope.ok, false);
  assert.equal(jScope.error, "forbidden");
  // Foreign booking must remain unpaid (positive control).
  const stored = env.BOOKING_KV.store.get("booking:b_comp_2");
  const storedRec = typeof stored === "string" ? JSON.parse(stored) : stored;
  assert.equal(storedRec.payment_status, "unpaid");
});

// ---------------------------------------------------------------------------
// Admin backward-compatible fallback.
// ---------------------------------------------------------------------------

test("admin token compatibility remains for /bookings/:id/payment", async () => {
  const booking = seedBooking({ bookingId: "b_admin_1", tenantId: "T1", companyId: "C1" });
  const { env } = await makeEnv({ bookings: [booking] });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b_admin_1",
      adminToken: ADMIN,
      body: paidPayload({ tenant_id: "T1", company_id: "C1" }),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
  assert.equal(j.payment_status, "paid");
});

test("admin token compatibility remains for the leg payment route", async () => {
  const booking = seedBooking({ bookingId: "b_admin_2", tenantId: "T1", companyId: "C1" });
  const { env } = await makeEnv({ bookings: [booking] });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "b_admin_2",
      legId: "leg1",
      adminToken: ADMIN,
      body: paidPayload({ tenant_id: "T1", company_id: "C1" }),
    }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.ok, true);
});

// ---------------------------------------------------------------------------
// Idempotency and no Mollie/Billit side effect for local EPC/cash mark-paid.
// ---------------------------------------------------------------------------

test("repeated identical driver-session mark-paid is idempotent (no duplicate paid_at, no error)", async () => {
  const booking = seedBooking({
    bookingId: "b_idem_1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-alice",
  });
  const alice = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env, bookingKv } = await makeEnv({ bookings: [booking], driverSessions: [alice] });

  const res1 = await worker.fetch(
    paymentRequest({ bookingId: "b_idem_1", token: "alice-token", body: paidPayload() }),
    env,
    {},
  );
  const j1 = await res1.json();
  assert.equal(res1.status, 200);
  assert.equal(j1.ok, true);
  assert.equal(j1.payment_status, "paid");
  const firstPaidAt = j1.paid_at;

  const res2 = await worker.fetch(
    paymentRequest({ bookingId: "b_idem_1", token: "alice-token", body: paidPayload() }),
    env,
    {},
  );
  const j2 = await res2.json();
  assert.equal(res2.status, 200);
  assert.equal(j2.ok, true);
  assert.equal(j2.payment_status, "paid");

  // No Mollie/Billit invoice provider was ever attributed to a manual in-car
  // mark-paid; both calls remain on the "manual" payment mode/provider.
  assert.notEqual(j1.payment_provider, "mollie");
  assert.notEqual(j2.payment_provider, "mollie");

  const finalRecordRaw = bookingKv.store.get("booking:b_idem_1");
  const finalRecord =
    typeof finalRecordRaw === "string" ? JSON.parse(finalRecordRaw) : finalRecordRaw;
  assert.equal(finalRecord.payment_status, "paid");
  // paid_at is only (re)stamped on a genuinely new paid transition; the
  // repeat call must not fabricate a second distinct paid_at from scratch
  // when the payload paid_at is omitted both times (same request shape).
  assert.equal(typeof firstPaidAt, "string");
});

// ---------------------------------------------------------------------------
// Booking and leg payment routes share the same scoped contract.
// ---------------------------------------------------------------------------

test("booking and leg payment routes both reject a random bearer with 401", async () => {
  const booking = seedBooking({ bookingId: "b_rand_1", tenantId: "T1", companyId: "C1" });
  const { env } = await makeEnv({ bookings: [booking] });

  const resBooking = await worker.fetch(
    paymentRequest({
      bookingId: "b_rand_1",
      token: "does-not-exist",
      body: paidPayload({ tenant_id: "T1", company_id: "C1" }),
    }),
    env,
    {},
  );
  assert.equal(resBooking.status, 401);

  const resLeg = await worker.fetch(
    paymentRequest({
      bookingId: "b_rand_1",
      legId: "leg1",
      token: "does-not-exist",
      body: paidPayload({ tenant_id: "T1", company_id: "C1" }),
    }),
    env,
    {},
  );
  assert.equal(resLeg.status, 401);
});

test("booking and leg payment routes both reject expired driver sessions with 401", async () => {
  const booking = seedBooking({
    bookingId: "b_exp_1",
    tenantId: "T1",
    companyId: "C1",
    assignedDriverId: "D-alice",
  });
  const expired = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    expiresAt: new Date(Date.now() - 60_000).toISOString(),
  });
  const { env } = await makeEnv({ bookings: [booking], driverSessions: [expired] });

  const resBooking = await worker.fetch(
    paymentRequest({ bookingId: "b_exp_1", token: "alice-token", body: paidPayload() }),
    env,
    {},
  );
  assert.equal(resBooking.status, 401);

  const resLeg = await worker.fetch(
    paymentRequest({
      bookingId: "b_exp_1",
      legId: "leg1",
      token: "alice-token",
      body: paidPayload(),
    }),
    env,
    {},
  );
  assert.equal(resLeg.status, 401);
});
