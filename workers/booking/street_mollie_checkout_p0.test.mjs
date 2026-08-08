// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1
//
// Run:
//   node --test workers/booking/street_mollie_checkout_p0.test.mjs
//   node --test workers/booking/modules/street_mollie_checkout.js  (helpers covered here)

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  resolveStreetCheckoutAuthoritativeAmount,
  streetCheckoutEligibility,
  manualMarkPaidConflict,
  webhookAfterManualPaidConflict,
  readOpenStreetMollieCheckout,
  STREET_HOSTED_CHECKOUT_ROUTE_CHANNEL,
  STREET_HOSTED_CHECKOUT_ROUTE_SOURCE,
  STREET_HOSTED_PAYMENT_SHADOW_TTL_SECONDS,
} from "./modules/street_mollie_checkout.js";
import {
  buildScopedMollieConnectAuthKey,
  encryptMollieConnectTokenPayload,
} from "./modules/mollie_connect.js";
import { buildMolliePaymentRouteKey } from "./modules/pos_terminal_payment.mjs";

const ADMIN = "test-admin-token";
const ENC_KEY = "test-mollie-connect-encryption-key-please-rotate";

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
      return typeof raw === "string" ? raw : JSON.stringify(raw);
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

async function seedCompanySession({
  tokenValue,
  tenantId,
  companyId,
  role = "company_admin",
}) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `company_admin:session:${hash}:v1`,
    record: {
      role,
      tenant_id: tenantId,
      company_id: companyId,
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

async function seedDriverSession({
  tokenValue,
  tenantId,
  companyId,
  driverId,
}) {
  const hash = await sha256Hex(tokenValue);
  return {
    key: `public_driver:session:${hash}:v1`,
    record: {
      role: "driver",
      tenant_id: tenantId,
      company_id: companyId,
      driver_id: driverId,
      expires_at: new Date(Date.now() + 3600_000).toISOString(),
    },
  };
}

function seedStreetBooking({
  bookingId = "street_1001_abc",
  tenantId = "T1",
  companyId = "C1",
  driverId = "drv_1",
  status = "COMPLETED",
  paymentStatus = "unpaid",
  priceInclVat = 42.5,
  fareFinalized = true,
  currency = "EUR",
  paymentProvider = null,
  paymentMode = null,
  checkoutUrl = null,
  paymentBookingId = null,
  mollie = null,
  source = "street_ride",
  rideType = "direct",
}) {
  const record = {
    booking_id: bookingId,
    bookingId,
    tenant_id: tenantId,
    company_id: companyId,
    status,
    payment_status: paymentStatus,
    paymentStatus,
    assigned_driver_id: driverId,
    assignedDriverId: driverId,
    source,
    booking_source: source,
    ride_type: rideType,
    price_incl_vat: priceInclVat,
    street_ride_fare_finalized: fareFinalized,
    currency,
    from: "A",
    to: "B",
    pickup_iso: "2026-08-01T12:00:00.000Z",
    booking: {
      booking_id: bookingId,
      price_incl_vat: priceInclVat,
      currency,
      status,
      payment_status: paymentStatus,
    },
  };
  if (paymentProvider) {
    record.payment_provider = paymentProvider;
    record.paymentProvider = paymentProvider;
  }
  if (paymentMode) {
    record.payment_mode = paymentMode;
    record.paymentMode = paymentMode;
  }
  if (checkoutUrl) {
    record.checkout_url = checkoutUrl;
    record.checkoutUrl = checkoutUrl;
  }
  if (paymentBookingId) {
    record.payment_booking_id = paymentBookingId;
    record.paymentBookingId = paymentBookingId;
  }
  if (mollie) record.mollie = mollie;
  return { key: `booking:${bookingId}`, record };
}

function seedBusinessProfile(tenantId, companyId) {
  return {
    key: `tenant:${tenantId}:company:${companyId}:business_profile:v1`,
    record: {
      business_profile: {
        mollie_connected: true,
        mollieConnected: true,
        payment_owner_mode: "company_mollie",
        enabled_public_payment_options: [
          "cash",
          "qr_code",
          "online_payment",
          "bancontact",
        ],
      },
      payment_owner_mode: "company_mollie",
      mollie_connected: true,
      mollieConnected: true,
      enabled_public_payment_options: [
        "cash",
        "qr_code",
        "online_payment",
        "bancontact",
      ],
      enabledPublicPaymentOptions: [
        "cash",
        "qr_code",
        "online_payment",
        "bancontact",
      ],
    },
  };
}

function installMollieFetchMock({ paymentId = "tr_street_1", status = "open" } = {}) {
  const original = globalThis.fetch;
  const calls = [];
  // MOLLIE-OPEN-PAYMENT-RECOVERY-P0: DELETE must advance provider status so
  // post-cancel re-read can release the payment owner.
  let currentStatus = status;
  globalThis.fetch = async (input, init = {}) => {
    const href = typeof input === "string" ? input : String(input?.url || "");
    calls.push({ href, method: init.method || "GET", headers: init.headers || {}, body: init.body });
    if (/api\.mollie\.com\/v2\/payments\/?(\?|$)/.test(href) && (init.method || "GET") === "POST") {
      currentStatus = status;
      return new Response(
        JSON.stringify({
          id: paymentId,
          status: currentStatus,
          amount: { currency: "EUR", value: "42.50" },
          _links: {
            checkout: { href: `https://www.mollie.com/checkout/test/${paymentId}` },
          },
          details: {
            qrCode: { src: "https://www.mollie.com/qr/test.png" },
          },
        }),
        { status: 201, headers: { "content-type": "application/json" } },
      );
    }
    if (/api\.mollie\.com\/v2\/payments\//.test(href) && (init.method || "GET") === "GET") {
      return new Response(
        JSON.stringify({
          id: paymentId,
          status: currentStatus,
          _links: {
            checkout: { href: `https://www.mollie.com/checkout/test/${paymentId}` },
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    if (/api\.mollie\.com\/v2\/payments\//.test(href) && init.method === "DELETE") {
      currentStatus = "canceled";
      return new Response(JSON.stringify({ id: paymentId, status: "canceled" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    return new Response(JSON.stringify({ ok: false, error: "unexpected_fetch", href }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  };
  return {
    calls,
    restore() {
      globalThis.fetch = original;
    },
  };
}

async function makeEnv(extraSeed = {}) {
  const booking = seedStreetBooking({});
  const company = await seedCompanySession({
    tokenValue: "co_tok_1",
    tenantId: "T1",
    companyId: "C1",
  });
  const driver = await seedDriverSession({
    tokenValue: "drv_tok_1",
    tenantId: "T1",
    companyId: "C1",
    driverId: "drv_1",
  });
  const mollieKey = buildScopedMollieConnectAuthKey({
    tenant_id: "T1",
    company_id: "C1",
  });
  const encrypted = await encryptMollieConnectTokenPayload(
    {
      access_token: "access_tok_test_street",
      refresh_token: "refresh_tok_test",
    },
    { MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY },
  );
  const mollieRecord = {
    version: 1,
    connected: true,
    status: "connected",
    organizationId: "org_street_test",
    profileId: "pfl_street_test",
    mollie_profile_id: "pfl_street_test",
    mollie_mode: "test",
    onboardingStatus: "completed",
    canReceivePayments: true,
    ...encrypted,
    lastConnectedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  const profile = seedBusinessProfile("T1", "C1");
  const seed = {
    [booking.key]: booking.record,
    [company.key]: company.record,
    [driver.key]: driver.record,
    [mollieKey]: mollieRecord,
    [profile.key]: profile.record,
    ...extraSeed,
  };
  const kv = makeKV(seed);
  return {
    env: {
      ADMIN_TOKEN: ADMIN,
      BOOKING_KV: kv,
      MOLLIE_COMPANY_PAYMENTS_ENABLED: "true",
      MOLLIE_COMPANY_LIVE_PAYMENTS_ENABLED: "true",
      MOLLIE_CONNECT_ENCRYPTION_KEY: ENC_KEY,
    },
    kv,
    booking,
  };
}

function streetCheckoutRequest({
  bookingId = "street_1001_abc",
  token = "co_tok_1",
  body = {},
  admin = false,
}) {
  const headers = {
    "content-type": "application/json",
    accept: "application/json",
  };
  if (admin) headers["x-admin-token"] = ADMIN;
  else headers.authorization = `Bearer ${token}`;
  return new Request(
    `https://booking.internal/bookings/${encodeURIComponent(bookingId)}/street-checkout?tenant_id=T1&company_id=C1`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({ tenant_id: "T1", company_id: "C1", ...body }),
    },
  );
}

// ---------- pure helper tests ----------

test("amount: finalized price_incl_vat is authoritative", () => {
  const rec = seedStreetBooking({ priceInclVat: 12.34 }).record;
  const got = resolveStreetCheckoutAuthoritativeAmount(rec);
  assert.equal(got.ok, true);
  assert.equal(got.amount_cents, 1234);
  assert.equal(got.amount_value, "12.34");
});

test("amount: forged lower client amount rejected", () => {
  const rec = seedStreetBooking({ priceInclVat: 42.5 }).record;
  const got = resolveStreetCheckoutAuthoritativeAmount(rec, 1.0);
  assert.equal(got.ok, false);
  assert.equal(got.error, "client_amount_mismatch");
});

test("amount: forged higher client amount rejected", () => {
  const rec = seedStreetBooking({ priceInclVat: 42.5 }).record;
  const got = resolveStreetCheckoutAuthoritativeAmount(rec, 99.99);
  assert.equal(got.ok, false);
  assert.equal(got.error, "client_amount_mismatch");
});

test("amount: unfinalized fare rejected", () => {
  const rec = seedStreetBooking({ fareFinalized: false }).record;
  const got = resolveStreetCheckoutAuthoritativeAmount(rec);
  assert.equal(got.ok, false);
  assert.equal(got.error, "street_fare_not_finalized");
});

test("eligibility: non-COMPLETED rejected", () => {
  const rec = seedStreetBooking({ status: "PENDING" }).record;
  const got = streetCheckoutEligibility(rec, { isStreetDirect: true });
  assert.equal(got.ok, false);
  assert.equal(got.error, "street_not_completed");
});

test("eligibility: non-street rejected", () => {
  const rec = seedStreetBooking({}).record;
  const got = streetCheckoutEligibility(rec, { isStreetDirect: false });
  assert.equal(got.ok, false);
  assert.equal(got.error, "not_street_booking");
});

test("manual conflict: open Mollie blocks cash without confirm", () => {
  const rec = seedStreetBooking({
    paymentMode: "mollie",
    paymentProvider: "mollie",
    paymentStatus: "pending",
    checkoutUrl: "https://www.mollie.com/checkout/x",
    mollie: { id: "tr_1", payment_id: "tr_1", status: "open" },
  }).record;
  const got = manualMarkPaidConflict(rec, { confirmCancelOpenMollie: false });
  assert.equal(got.error, "open_mollie_checkout_exists");
});

test("manual conflict: Mollie paid blocks cash", () => {
  const rec = seedStreetBooking({
    paymentMode: "mollie",
    paymentProvider: "mollie",
    paymentStatus: "paid",
  }).record;
  const got = manualMarkPaidConflict(rec);
  assert.equal(got.error, "payment_already_paid_mollie");
});

test("webhook-after-cash conflict is visible", () => {
  const rec = seedStreetBooking({
    paymentStatus: "paid",
    paymentProvider: "manual",
    paymentMode: "manual",
  }).record;
  const got = webhookAfterManualPaidConflict(rec, "tr_other");
  assert.equal(got.error, "payment_reconciliation_conflict");
  assert.equal(got.reason, "canonical_already_paid_manual");
});

// ---------- route tests ----------

test("1. unauthenticated street checkout denied", async () => {
  const { env } = await makeEnv();
  const mock = installMollieFetchMock();
  try {
    const res = await worker.fetch(
      new Request(
        "https://booking.internal/bookings/street_1001_abc/street-checkout?tenant_id=T1&company_id=C1",
        {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ tenant_id: "T1", company_id: "C1" }),
        },
      ),
      env,
      {},
    );
    assert.equal(res.status, 401);
  } finally {
    mock.restore();
  }
});

test("2. foreign booking returns opaque 404", async () => {
  const foreign = seedStreetBooking({
    bookingId: "street_foreign",
    tenantId: "T2",
    companyId: "C2",
  });
  const { env } = await makeEnv({ [foreign.key]: foreign.record });
  const mock = installMollieFetchMock();
  try {
    const res = await worker.fetch(
      streetCheckoutRequest({ bookingId: "street_foreign", token: "co_tok_1" }),
      env,
      {},
    );
    assert.equal(res.status, 404);
    const body = await res.json();
    assert.equal(body.error, "booking_not_found");
  } finally {
    mock.restore();
  }
});

test("3. non-street booking rejected", async () => {
  const planned = seedStreetBooking({
    bookingId: "2026-08-999",
    source: "planned",
    rideType: "planned",
  });
  planned.record.source = "customer_app";
  planned.record.booking_source = "customer_app";
  planned.record.ride_type = "planned";
  // force non-street id
  const { env, kv } = await makeEnv();
  await kv.put(planned.key, JSON.stringify(planned.record));
  const mock = installMollieFetchMock();
  try {
    const res = await worker.fetch(
      streetCheckoutRequest({ bookingId: "2026-08-999" }),
      env,
      {},
    );
    assert.equal(res.status, 409);
    const body = await res.json();
    assert.equal(body.error, "not_street_booking");
  } finally {
    mock.restore();
  }
});

test("4-6. non-COMPLETED / unfinalized / zero fare rejected", async () => {
  const cases = [
    {
      bookingId: "street_pending",
      patch: { status: "PENDING" },
      error: "street_not_completed",
    },
    {
      bookingId: "street_unfinal",
      patch: { street_ride_fare_finalized: false },
      error: "street_fare_not_finalized",
    },
    {
      bookingId: "street_zero",
      patch: { price_incl_vat: 0, booking: { price_incl_vat: 0 } },
      error: "street_fare_unavailable",
    },
  ];
  for (const c of cases) {
    const b = seedStreetBooking({ bookingId: c.bookingId });
    Object.assign(b.record, c.patch);
    if (c.patch.booking) Object.assign(b.record.booking, c.patch.booking);
    const { env, kv } = await makeEnv();
    await kv.put(b.key, JSON.stringify(b.record));
    const mock = installMollieFetchMock();
    try {
      const res = await worker.fetch(
        streetCheckoutRequest({ bookingId: c.bookingId }),
        env,
        {},
      );
      assert.equal(res.status, 409, c.error);
      const body = await res.json();
      assert.equal(body.error, c.error);
    } finally {
      mock.restore();
    }
  }
});

test("7. client amount cannot override canonical amount", async () => {
  const { env } = await makeEnv();
  const mock = installMollieFetchMock();
  try {
    const res = await worker.fetch(
      streetCheckoutRequest({ body: { amount: 1.0 } }),
      env,
      {},
    );
    assert.equal(res.status, 409);
    const body = await res.json();
    assert.equal(body.error, "client_amount_mismatch");
    assert.equal(mock.calls.some((c) => /api\.mollie\.com/.test(c.href)), false);
  } finally {
    mock.restore();
  }
});

test("8-10. happy create uses company Mollie + Idempotency-Key", async () => {
  const { env } = await makeEnv();
  const mock = installMollieFetchMock({ paymentId: "tr_ok_1" });
  try {
    const res = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.reused, false);
    assert.equal(body.amount, "42.50");
    assert.equal(body.amount_cents, 4250);
    assert.match(body.checkout_url, /mollie\.com\/checkout/);
    assert.ok(body.payment_booking_id);
    const createCall = mock.calls.find(
      (c) => /api\.mollie\.com\/v2\/payments/.test(c.href) && c.method === "POST",
    );
    assert.ok(createCall);
    const headers = createCall.headers;
    const idem =
      headers["Idempotency-Key"] ||
      headers["idempotency-key"] ||
      (typeof headers.get === "function" ? headers.get("Idempotency-Key") : null);
    assert.ok(idem && String(idem).includes("fluxidi-street-checkout:"));
    const parsed = JSON.parse(createCall.body);
    assert.equal(parsed.amount.value, "42.50");
    assert.equal(parsed.method, undefined);
    assert.equal(parsed.metadata.canonicalBookingId, "street_1001_abc");
    assert.equal(parsed.profileId, "pfl_street_test");
  } finally {
    mock.restore();
  }
});

test("12. double tap returns same open checkout", async () => {
  const { env } = await makeEnv();
  const mock = installMollieFetchMock({ paymentId: "tr_reuse" });
  try {
    const first = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(first.status, 200);
    const a = await first.json();
    const second = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(second.status, 200);
    const b = await second.json();
    assert.equal(b.reused, true);
    assert.equal(b.payment_booking_id, a.payment_booking_id);
    assert.equal(b.checkout_url, a.checkout_url);
    const posts = mock.calls.filter(
      (c) => /api\.mollie\.com\/v2\/payments\/?(\?|$)/.test(c.href) && c.method === "POST",
    );
    assert.equal(posts.length, 1);
  } finally {
    mock.restore();
  }
});

test("14. already-paid ride cannot create checkout", async () => {
  const paid = seedStreetBooking({
    paymentStatus: "paid",
    paymentProvider: "manual",
    paymentMode: "manual",
  });
  const { env, kv } = await makeEnv();
  await kv.put(paid.key, JSON.stringify(paid.record));
  const mock = installMollieFetchMock();
  try {
    const res = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(res.status, 409);
    const body = await res.json();
    assert.ok(
      body.error === "payment_already_paid" ||
        body.error === "payment_already_paid_manual",
    );
  } finally {
    mock.restore();
  }
});

test("20. cash paid blocks new Mollie checkout", async () => {
  const paid = seedStreetBooking({
    paymentStatus: "paid",
    paymentProvider: "manual",
    paymentMode: "manual",
  });
  const { env, kv } = await makeEnv();
  await kv.put(paid.key, JSON.stringify(paid.record));
  const mock = installMollieFetchMock();
  try {
    const res = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(res.status, 409);
  } finally {
    mock.restore();
  }
});

test("21. Mollie paid blocks manual cash mark-paid", async () => {
  const paid = seedStreetBooking({
    paymentStatus: "paid",
    paymentProvider: "mollie",
    paymentMode: "mollie",
  });
  const { env, kv } = await makeEnv();
  await kv.put(paid.key, JSON.stringify(paid.record));
  const mock = installMollieFetchMock();
  try {
    const res = await worker.fetch(
      new Request(
        "https://booking.internal/bookings/street_1001_abc/payment?tenant_id=T1&company_id=C1",
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: "Bearer co_tok_1",
          },
          body: JSON.stringify({
            tenant_id: "T1",
            company_id: "C1",
            payment_status: "paid",
            payment_method: "cash",
            payment_source: "in_car",
            payment_provider: "manual",
            amount: 42.5,
          }),
        },
      ),
      env,
      {},
    );
    assert.equal(res.status, 409);
    const body = await res.json();
    assert.equal(body.error, "payment_already_paid_mollie");
  } finally {
    mock.restore();
  }
});

test("open Mollie blocks cash without confirm; confirm cancels", async () => {
  const { env } = await makeEnv();
  const mock = installMollieFetchMock({ paymentId: "tr_open_cash" });
  try {
    const created = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(created.status, 200);
    const blocked = await worker.fetch(
      new Request(
        "https://booking.internal/bookings/street_1001_abc/payment?tenant_id=T1&company_id=C1",
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: "Bearer co_tok_1",
          },
          body: JSON.stringify({
            tenant_id: "T1",
            company_id: "C1",
            payment_status: "paid",
            payment_method: "cash",
            payment_source: "in_car",
            payment_provider: "manual",
            amount: 42.5,
          }),
        },
      ),
      env,
      {},
    );
    assert.equal(blocked.status, 409);
    const blockedBody = await blocked.json();
    assert.equal(blockedBody.error, "open_mollie_checkout_exists");

    const confirmed = await worker.fetch(
      new Request(
        "https://booking.internal/bookings/street_1001_abc/payment?tenant_id=T1&company_id=C1",
        {
          method: "POST",
          headers: {
            "content-type": "application/json",
            authorization: "Bearer co_tok_1",
          },
          body: JSON.stringify({
            tenant_id: "T1",
            company_id: "C1",
            payment_status: "paid",
            payment_method: "cash",
            payment_source: "in_car",
            payment_provider: "manual",
            amount: 42.5,
            confirm_cancel_open_mollie: true,
          }),
        },
      ),
      env,
      {},
    );
    assert.equal(confirmed.status, 200);
    const okBody = await confirmed.json();
    assert.equal(okBody.ok, true);
  } finally {
    mock.restore();
  }
});

test("23. checkout create does not mutate fare", async () => {
  const { env, kv } = await makeEnv();
  const mock = installMollieFetchMock();
  try {
    const before = JSON.parse(await kv.get("booking:street_1001_abc"));
    const res = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(res.status, 200);
    const after = JSON.parse(await kv.get("booking:street_1001_abc"));
    assert.equal(after.price_incl_vat, before.price_incl_vat);
    assert.equal(after.street_ride_fare_finalized, true);
    assert.equal(String(after.status).toUpperCase(), "COMPLETED");
  } finally {
    mock.restore();
  }
});

test("readOpenStreetMollieCheckout detects open attempt", () => {
  const rec = seedStreetBooking({
    paymentMode: "mollie",
    paymentStatus: "pending",
    checkoutUrl: "https://www.mollie.com/checkout/x",
    paymentBookingId: "uuid-1",
    mollie: { id: "tr_1", status: "open" },
  }).record;
  const open = readOpenStreetMollieCheckout(rec);
  assert.ok(open);
  assert.equal(open.payment_booking_id, "uuid-1");
});

// ---------- PAYMENT-RECOVERY-OPEN-CANCEL-P0 ----------

function installMultiPaymentMollieMock(seedStatuses = {}) {
  const original = globalThis.fetch;
  const statuses = new Map(Object.entries(seedStatuses));
  let createSeq = 0;
  const calls = [];
  globalThis.fetch = async (input, init = {}) => {
    const href = typeof input === "string" ? input : String(input?.url || "");
    const method = init.method || "GET";
    calls.push({ href, method });
    const idMatch = href.match(/api\.mollie\.com\/v2\/payments\/([^/?]+)/);
    const paymentId = idMatch ? decodeURIComponent(idMatch[1]) : "";
    if (/api\.mollie\.com\/v2\/payments\/?(\?|$)/.test(href) && method === "POST") {
      createSeq += 1;
      const id = `tr_street_created_${createSeq}`;
      statuses.set(id, "open");
      return new Response(
        JSON.stringify({
          id,
          status: "open",
          amount: { currency: "EUR", value: "42.50" },
          _links: {
            checkout: { href: `https://www.mollie.com/checkout/test/${id}` },
          },
          details: { qrCode: { src: "https://www.mollie.com/qr/test.png" } },
        }),
        { status: 201, headers: { "content-type": "application/json" } },
      );
    }
    if (paymentId && method === "GET") {
      const status = statuses.get(paymentId) || "open";
      return new Response(
        JSON.stringify({
          id: paymentId,
          status,
          _links: {
            checkout: { href: `https://www.mollie.com/checkout/test/${paymentId}` },
          },
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    if (paymentId && method === "DELETE") {
      statuses.set(paymentId, "canceled");
      return new Response(
        JSON.stringify({ id: paymentId, status: "canceled" }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }
    return new Response(JSON.stringify({ ok: false, error: "unexpected_fetch", href }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  };
  return {
    calls,
    statuses,
    restore() {
      globalThis.fetch = original;
    },
  };
}

function recoveryRequest({
  bookingId = "street_1001_abc",
  action = "refresh",
  token = "co_tok_1",
  admin = false,
}) {
  const headers = {
    "content-type": "application/json",
    accept: "application/json",
  };
  if (admin) headers["x-admin-token"] = ADMIN;
  else headers.authorization = `Bearer ${token}`;
  return new Request(
    `https://booking.internal/bookings/${encodeURIComponent(bookingId)}/mollie-checkout-recovery?tenant_id=T1&company_id=C1`,
    {
      method: "POST",
      headers,
      body: JSON.stringify({ tenant_id: "T1", company_id: "C1", action }),
    },
  );
}

test("P0 recovery: pending online blocks duplicate street create (reuse)", async () => {
  const { env } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const first = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(first.status, 200);
    const firstBody = await first.json();
    assert.equal(firstBody.ok, true);
    assert.ok(firstBody.checkout_url);

    const second = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(second.status, 200);
    const secondBody = await second.json();
    assert.equal(secondBody.ok, true);
    assert.equal(secondBody.reused, true);
    assert.equal(secondBody.checkout_url, firstBody.checkout_url);
    assert.equal(mock.calls.filter((c) => c.method === "POST").length, 1);
  } finally {
    mock.restore();
  }
});

test("P0 recovery: resume via street-checkout returns same checkout URL", async () => {
  const { env } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const created = await worker.fetch(streetCheckoutRequest({}), env, {});
    const createdBody = await created.json();
    const resumed = await worker.fetch(streetCheckoutRequest({}), env, {});
    const resumedBody = await resumed.json();
    assert.equal(resumed.status, 200);
    assert.equal(resumedBody.reused, true);
    assert.equal(resumedBody.checkout_url, createdBody.checkout_url);
  } finally {
    mock.restore();
  }
});

test("P0 recovery: open POS blocks new street create until released", async () => {
  const intentKey =
    "tenant:T1:company:C1:mollie_driver_pos_intent:street_1001_abc:main:v1";
  const { env, kv } = await makeEnv({
    [intentKey]: {
      payment_id: "tr_pos_open_1",
      mollie_status: "open",
      status: "open",
      amount: { currency: "EUR", value: "42.50" },
    },
  });
  const mock = installMultiPaymentMollieMock({ tr_pos_open_1: "open" });
  // Force cancel_not_confirmed: DELETE leaves payment open.
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init = {}) => {
    const href = typeof input === "string" ? input : String(input?.url || "");
    if (/tr_pos_open_1/.test(href) && (init.method || "GET") === "DELETE") {
      return new Response(JSON.stringify({ id: "tr_pos_open_1", status: "open" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    return originalFetch(input, init);
  };
  try {
    const res = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(res.status, 409);
    const body = await res.json();
    assert.equal(body.error, "open_pos_payment_exists");
    assert.equal(body.creates_new_mollie_payment, false);
    // Intent still present — lock not cleared while POS payable.
    const intent = await kv.get(intentKey, { type: "json" });
    assert.ok(intent);
  } finally {
    globalThis.fetch = originalFetch;
    mock.restore();
  }
});

test("P0 recovery: cancel clears street lock and releases open POS", async () => {
  const intentKey =
    "tenant:T1:company:C1:mollie_driver_pos_intent:street_1001_abc:main:v1";
  const { env, kv } = await makeEnv({
    [intentKey]: {
      payment_id: "tr_pos_open_2",
      mollie_status: "open",
      status: "open",
      amount: { currency: "EUR", value: "42.50" },
    },
  });
  const mock = installMultiPaymentMollieMock({ tr_pos_open_2: "open" });
  try {
    // Seed hosted open checkout without minting while POS open: write booking markers.
    const booking = JSON.parse(await kv.get("booking:street_1001_abc"));
    booking.payment_status = "pending";
    booking.paymentStatus = "pending";
    booking.payment_provider = "mollie";
    booking.payment_mode = "mollie";
    booking.checkout_url = "https://www.mollie.com/checkout/test/tr_street_seed";
    booking.payment_booking_id = "pay-shadow-seed";
    booking.payment_id = "tr_street_seed";
    booking.mollie = { id: "tr_street_seed", payment_id: "tr_street_seed", status: "open" };
    await kv.put("booking:street_1001_abc", JSON.stringify(booking));
    mock.statuses.set("tr_street_seed", "open");

    const cancel = await worker.fetch(
      recoveryRequest({ action: "cancel", admin: true }),
      env,
      {},
    );
    assert.equal(cancel.status, 200);
    const cancelBody = await cancel.json();
    assert.equal(cancelBody.ok, true);
    assert.equal(cancelBody.fallback_allowed, true);
    assert.equal(cancelBody.payment_status, "unpaid");

    const after = JSON.parse(await kv.get("booking:street_1001_abc"));
    assert.ok(!readOpenStreetMollieCheckout(after));

    const posIntent = await kv.get(intentKey, { type: "json" });
    assert.ok(posIntent);
    assert.ok(["canceled", "cancelled"].includes(String(posIntent.status).toLowerCase()) ||
      ["canceled", "cancelled"].includes(String(posIntent.mollie_status).toLowerCase()));

    // New Tap/online allowed: street create must succeed after release.
    const recreate = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(recreate.status, 200);
    const recreateBody = await recreate.json();
    assert.equal(recreateBody.ok, true);
    assert.ok(recreateBody.checkout_url);
  } finally {
    mock.restore();
  }
});

test("P0 recovery: admin token can cancel (ops parity with street-checkout)", async () => {
  const { env, kv } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const created = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(created.status, 200);
    const cancel = await worker.fetch(
      recoveryRequest({ action: "cancel", admin: true }),
      env,
      {},
    );
    assert.equal(cancel.status, 200);
    const body = await cancel.json();
    assert.equal(body.ok, true);
    assert.equal(body.action, "cancel");
    const after = JSON.parse(await kv.get("booking:street_1001_abc"));
    assert.ok(!readOpenStreetMollieCheckout(after));
  } finally {
    mock.restore();
  }
});

test("P0 recovery: paid cannot be cancelled into unpaid", async () => {
  const paid = seedStreetBooking({
    paymentStatus: "paid",
    paymentProvider: "mollie",
    paymentMode: "mollie",
    checkoutUrl: "https://www.mollie.com/checkout/x",
    paymentBookingId: "uuid-paid",
    mollie: { id: "tr_paid_1", payment_id: "tr_paid_1", status: "paid" },
  });
  const { env, kv } = await makeEnv();
  await kv.put(paid.key, JSON.stringify(paid.record));
  const mock = installMultiPaymentMollieMock({ tr_paid_1: "paid" });
  try {
    const cancel = await worker.fetch(
      recoveryRequest({ action: "cancel", admin: true }),
      env,
      {},
    );
    const body = await cancel.json();
    // Authoritative paid wins — never project unpaid.
    assert.notEqual(body.payment_status, "unpaid");
    assert.ok(
      body.payment_status === "paid" ||
        body.error === "payment_already_paid" ||
        body.presentation_state === "paid",
    );
    const after = JSON.parse(await kv.get(paid.key));
    assert.equal(String(after.payment_status).toLowerCase(), "paid");
  } finally {
    mock.restore();
  }
});

test("P0 recovery: repeated cancel is idempotent after release", async () => {
  const { env } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const created = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(created.status, 200);
    const first = await worker.fetch(
      recoveryRequest({ action: "cancel", token: "co_tok_1" }),
      env,
      {},
    );
    assert.equal(first.status, 200);
    const second = await worker.fetch(
      recoveryRequest({ action: "cancel", token: "co_tok_1" }),
      env,
      {},
    );
    // Second cancel: no open owner — refresh/cancel path returns non-trapping outcome.
    const secondBody = await second.json();
    assert.ok(secondBody.ok === true || secondBody.error === "checkout_not_resumable" || secondBody.fallback_allowed === true);
  } finally {
    mock.restore();
  }
});

// ---------- STREET-ONLINE-PAYMENT-CONVERGENCE-P0 ----------

test("CONVERGE-P0: hosted create writes durable mollie_payment_route", async () => {
  const { env, kv } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const res = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.ok(body.checkout_url);
    const booking = JSON.parse(await kv.get("booking:street_1001_abc"));
    const paymentId = booking.mollie?.id || booking.payment_id;
    assert.ok(paymentId);
    const routeKey = buildMolliePaymentRouteKey(paymentId);
    const route = await kv.get(routeKey, { type: "json" });
    assert.ok(route, "durable route must exist");
    assert.equal(route.tenant_id, "T1");
    assert.equal(route.company_id, "C1");
    assert.equal(route.booking_id, "street_1001_abc");
    assert.equal(route.channel, STREET_HOSTED_CHECKOUT_ROUTE_CHANNEL);
    assert.equal(route.source, STREET_HOSTED_CHECKOUT_ROUTE_SOURCE);
    assert.equal(route.intent_key, body.payment_booking_id);
    assert.ok(STREET_HOSTED_PAYMENT_SHADOW_TTL_SECONDS >= 60 * 60 * 24 * 30);
  } finally {
    mock.restore();
  }
});

test("CONVERGE-P0: webhook after shadow loss resolves via durable hosted route", async () => {
  const { env, kv } = await makeEnv();
  const paymentId = "tr_street_route_1";
  const paymentBookingId = "shadow-evicted-uuid";
  const routeKey = buildMolliePaymentRouteKey(paymentId);
  await kv.put(
    routeKey,
    JSON.stringify({
      version: 1,
      payment_id: paymentId,
      tenant_id: "T1",
      company_id: "C1",
      booking_id: "street_1001_abc",
      channel: STREET_HOSTED_CHECKOUT_ROUTE_CHANNEL,
      source: STREET_HOSTED_CHECKOUT_ROUTE_SOURCE,
      profile_id: "pfl_street_test",
      intent_key: paymentBookingId,
      created_at: new Date().toISOString(),
    }),
  );
  // Canonical still shows open ownership; shadow intentionally missing.
  const booking = JSON.parse(await kv.get("booking:street_1001_abc"));
  booking.payment_status = "pending";
  booking.payment_provider = "mollie";
  booking.payment_mode = "mollie";
  booking.checkout_url = `https://www.mollie.com/checkout/test/${paymentId}`;
  booking.payment_booking_id = paymentBookingId;
  booking.payment_id = paymentId;
  booking.mollie = { id: paymentId, payment_id: paymentId, status: "open" };
  booking.payment_attempt_status = "mollie_open";
  await kv.put("booking:street_1001_abc", JSON.stringify(booking));

  const mock = installMultiPaymentMollieMock({ [paymentId]: "expired" });
  try {
    const res = await worker.fetch(
      new Request("https://booking.internal/webhook/mollie", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: paymentId }),
      }),
      env,
      {},
    );
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.street_hosted_reconcile, true);
    assert.equal(body.mollie_status, "expired");
    const after = JSON.parse(await kv.get("booking:street_1001_abc"));
    assert.equal(String(after.status).toUpperCase(), "COMPLETED");
    assert.ok(!readOpenStreetMollieCheckout(after));
    assert.ok(["expired", "cancelled", "canceled"].includes(
      String(after.payment_attempt_status || "").toLowerCase(),
    ));
  } finally {
    mock.restore();
  }
});

test("CONVERGE-P0: refresh paid releases nothing and projects paid", async () => {
  const { env, kv } = await makeEnv();
  const paymentId = "tr_refresh_paid";
  const shadowId = crypto.randomUUID();
  const booking = JSON.parse(await kv.get("booking:street_1001_abc"));
  booking.payment_status = "pending";
  booking.payment_provider = "mollie";
  booking.payment_mode = "mollie";
  booking.checkout_url = `https://www.mollie.com/checkout/test/${paymentId}`;
  booking.payment_booking_id = shadowId;
  booking.payment_id = paymentId;
  booking.mollie = { id: paymentId, payment_id: paymentId, status: "open" };
  booking.payment_attempt_status = "mollie_open";
  await kv.put("booking:street_1001_abc", JSON.stringify(booking));
  await kv.put(
    `booking:${shadowId}`,
    JSON.stringify({
      bookingId: shadowId,
      booking_id: shadowId,
      public_booking_id: "street_1001_abc",
      checkout_resume: true,
      street_checkout: true,
      payment_status: "pending",
      payment_id: paymentId,
      mollie: { id: paymentId, status: "open" },
      tenant_id: "T1",
      company_id: "C1",
      payload: {
        __checkout_resume: true,
        __street_checkout: true,
        tenant_id: "T1",
        company_id: "C1",
      },
      authoritative_amount_cents: 4250,
    }),
  );
  const mock = installMultiPaymentMollieMock({ [paymentId]: "paid" });
  try {
    const res = await worker.fetch(recoveryRequest({ action: "refresh" }), env, {});
    const body = await res.json();
    assert.equal(body.presentation_state, "paid");
    assert.equal(body.payment_status, "paid");
    assert.equal(body.fallback_allowed, false);
  } finally {
    mock.restore();
  }
});

for (const terminal of ["canceled", "failed", "expired"]) {
  test(`CONVERGE-P0: refresh ${terminal} releases ownership`, async () => {
    const { env, kv } = await makeEnv();
    const paymentId = `tr_refresh_${terminal}`;
    const booking = JSON.parse(await kv.get("booking:street_1001_abc"));
    booking.payment_status = "pending";
    booking.payment_provider = "mollie";
    booking.payment_mode = "mollie";
    booking.checkout_url = `https://www.mollie.com/checkout/test/${paymentId}`;
    booking.payment_booking_id = "shadow-x";
    booking.payment_id = paymentId;
    booking.mollie = { id: paymentId, payment_id: paymentId, status: "open" };
    booking.payment_attempt_status = "mollie_open";
    await kv.put("booking:street_1001_abc", JSON.stringify(booking));
    const mock = installMultiPaymentMollieMock({ [paymentId]: terminal });
    try {
      const res = await worker.fetch(recoveryRequest({ action: "refresh" }), env, {});
      const body = await res.json();
      assert.equal(body.ok, true);
      assert.equal(body.fallback_allowed, true);
      assert.ok(!readOpenStreetMollieCheckout(
        JSON.parse(await kv.get("booking:street_1001_abc")),
      ));
    } finally {
      mock.restore();
    }
  });
}

test("CONVERGE-P0: refresh still open does not release ownership", async () => {
  const { env, kv } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const created = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(created.status, 200);
    const res = await worker.fetch(recoveryRequest({ action: "refresh" }), env, {});
    const body = await res.json();
    assert.equal(body.ok, true);
    assert.equal(body.fallback_allowed, false);
    assert.equal(body.payment_status, "pending");
    assert.ok(readOpenStreetMollieCheckout(
      JSON.parse(await kv.get("booking:street_1001_abc")),
    ));
  } finally {
    mock.restore();
  }
});

test("CONVERGE-P0: cancel race — provider paid wins", async () => {
  const { env, kv } = await makeEnv();
  const paymentId = "tr_cancel_paid_race";
  const booking = JSON.parse(await kv.get("booking:street_1001_abc"));
  booking.payment_status = "pending";
  booking.payment_provider = "mollie";
  booking.payment_mode = "mollie";
  booking.checkout_url = `https://www.mollie.com/checkout/test/${paymentId}`;
  booking.payment_booking_id = "shadow-race";
  booking.payment_id = paymentId;
  booking.mollie = { id: paymentId, payment_id: paymentId, status: "open" };
  await kv.put("booking:street_1001_abc", JSON.stringify(booking));
  const mock = installMultiPaymentMollieMock({ [paymentId]: "paid" });
  try {
    const res = await worker.fetch(recoveryRequest({ action: "cancel" }), env, {});
    const body = await res.json();
    assert.notEqual(body.payment_status, "unpaid");
    assert.ok(
      body.presentation_state === "paid" ||
        body.payment_status === "paid" ||
        body.error === "payment_already_paid",
    );
    assert.equal(body.fallback_allowed, false);
  } finally {
    mock.restore();
  }
});

test("CONVERGE-P0: cancel confirmed releases; cancel not confirmed keeps block", async () => {
  const { env, kv } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const created = await worker.fetch(streetCheckoutRequest({}), env, {});
    assert.equal(created.status, 200);
    const cancelOk = await worker.fetch(recoveryRequest({ action: "cancel" }), env, {});
    const okBody = await cancelOk.json();
    assert.equal(okBody.ok, true);
    assert.equal(okBody.fallback_allowed, true);
    assert.ok(!readOpenStreetMollieCheckout(
      JSON.parse(await kv.get("booking:street_1001_abc")),
    ));
  } finally {
    mock.restore();
  }

  // Not-confirmed path: DELETE leaves payment open.
  const { env: env2, kv: kv2 } = await makeEnv();
  const paymentId = "tr_cancel_stuck";
  const booking = JSON.parse(await kv2.get("booking:street_1001_abc"));
  booking.payment_status = "pending";
  booking.payment_provider = "mollie";
  booking.payment_mode = "mollie";
  booking.checkout_url = `https://www.mollie.com/checkout/test/${paymentId}`;
  booking.payment_booking_id = "shadow-stuck";
  booking.payment_id = paymentId;
  booking.mollie = { id: paymentId, payment_id: paymentId, status: "open" };
  await kv2.put("booking:street_1001_abc", JSON.stringify(booking));
  const mock2 = installMultiPaymentMollieMock({ [paymentId]: "open" });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (input, init = {}) => {
    const href = typeof input === "string" ? input : String(input?.url || "");
    if (/tr_cancel_stuck/.test(href) && (init.method || "GET") === "DELETE") {
      return new Response(JSON.stringify({ id: paymentId, status: "open" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    return originalFetch(input, init);
  };
  try {
    const res = await worker.fetch(recoveryRequest({ action: "cancel" }), env2, {});
    const body = await res.json();
    assert.equal(body.ok, false);
    assert.equal(body.fallback_allowed, false);
    assert.ok(readOpenStreetMollieCheckout(
      JSON.parse(await kv2.get("booking:street_1001_abc")),
    ));
  } finally {
    globalThis.fetch = originalFetch;
    mock2.restore();
  }
});

test("CONVERGE-P0: hosted→hosted resume reuses, does not mint second payable", async () => {
  const { env } = await makeEnv();
  const mock = installMultiPaymentMollieMock();
  try {
    const first = await worker.fetch(streetCheckoutRequest({}), env, {});
    const firstBody = await first.json();
    const second = await worker.fetch(streetCheckoutRequest({}), env, {});
    const secondBody = await second.json();
    assert.equal(secondBody.reused, true);
    assert.equal(secondBody.creates_new_mollie_payment, false);
    assert.equal(secondBody.checkout_url, firstBody.checkout_url);
    assert.equal(mock.calls.filter((c) => c.method === "POST").length, 1);
  } finally {
    mock.restore();
  }
});

test("CONVERGE-P0: late orphan payment webhook cannot create duplicate paid", async () => {
  const { env, kv } = await makeEnv();
  const oldPaymentId = "tr_old_orphan";
  const currentPaymentId = "tr_current_paid";
  // Canonical already paid by a different Mollie payment.
  const booking = JSON.parse(await kv.get("booking:street_1001_abc"));
  booking.payment_status = "paid";
  booking.paymentStatus = "paid";
  booking.payment_provider = "mollie";
  booking.payment_mode = "mollie";
  booking.payment_id = currentPaymentId;
  booking.paid_at = "2026-08-08T10:00:00.000Z";
  booking.mollie = { id: currentPaymentId, payment_id: currentPaymentId, status: "paid" };
  await kv.put("booking:street_1001_abc", JSON.stringify(booking));
  await kv.put(
    buildMolliePaymentRouteKey(oldPaymentId),
    JSON.stringify({
      version: 1,
      payment_id: oldPaymentId,
      tenant_id: "T1",
      company_id: "C1",
      booking_id: "street_1001_abc",
      channel: STREET_HOSTED_CHECKOUT_ROUTE_CHANNEL,
      source: STREET_HOSTED_CHECKOUT_ROUTE_SOURCE,
      profile_id: "pfl_street_test",
      intent_key: "old-shadow",
    }),
  );
  const mock = installMultiPaymentMollieMock({ [oldPaymentId]: "paid" });
  try {
    const res = await worker.fetch(
      new Request("https://booking.internal/webhook/mollie", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ id: oldPaymentId }),
      }),
      env,
      {},
    );
    const body = await res.json();
    assert.equal(body.street_hosted_reconcile, true);
    assert.equal(body.creates_duplicate_paid, false);
    assert.ok(
      body.reason === "canonical_already_paid_different_mollie" ||
        body.already_paid === true,
    );
    const after = JSON.parse(await kv.get("booking:street_1001_abc"));
    assert.equal(after.payment_id, currentPaymentId);
    assert.equal(String(after.payment_status).toLowerCase(), "paid");
  } finally {
    mock.restore();
  }
});
