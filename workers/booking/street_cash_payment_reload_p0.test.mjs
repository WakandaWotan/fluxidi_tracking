// STREET-CASH-PAYMENT-RELOAD-P0
//
// Proves cash mark-paid on a street booking:
//   * persists payment_status=paid on BOOKING_KV;
//   * syncs the same Paid fields onto the tracking trip via tracking_trip_id;
//   * returns Paid on an authenticated GET of the same booking;
//   * is idempotent on duplicate cash confirmation;
//   * does not auto-create a business invoice / outbound Billit call;
//   * blocks cross-tenant access.
//
// Run:
//   node --test workers/booking/street_cash_payment_reload_p0.test.mjs

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

function scopedTripKey(tenantId, companyId, tripId) {
  return `tenant:${tenantId}:company:${companyId}:trip:${tripId}`;
}

function seedStreetBooking({
  bookingId,
  tenantId,
  companyId,
  driverId,
  tripId,
  paymentStatus = "unpaid",
}) {
  return {
    key: `booking:${bookingId}`,
    record: {
      booking_id: bookingId,
      tenant_id: tenantId,
      company_id: companyId,
      status: "completed",
      payment_status: paymentStatus,
      paymentStatus,
      assigned_driver_id: driverId,
      assignedDriverId: driverId,
      tracking_trip_id: tripId,
      trackingTripId: tripId,
      kind: "direct",
      ride_type: "street",
    },
  };
}

function seedTrackingTrip({ tenantId, companyId, tripId, bookingId }) {
  const key = scopedTripKey(tenantId, companyId, tripId);
  return {
    key,
    record: {
      trip_id: tripId,
      booking_id: bookingId,
      tenant_id: tenantId,
      company_id: companyId,
      payment_status: "unpaid",
      paymentStatus: "unpaid",
      booking_details: { payment_status: "unpaid" },
      kind: "direct",
      status: "stopped",
    },
  };
}

function assertNoOutboundPspFetch(label) {
  const original = global.fetch;
  const hits = [];
  global.fetch = async (input) => {
    const href = typeof input === "string" ? input : input?.url || "";
    hits.push(String(href));
    throw new Error(`${label}: unexpected outbound fetch to ${href}`);
  };
  return {
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

async function makeEnv({ bookings = [], trips = [], driverSessions = [] } = {}) {
  const bookingSeed = {};
  for (const b of bookings) bookingSeed[b.key] = b.record;
  for (const d of driverSessions) bookingSeed[d.key] = d.record;
  const tripSeed = {};
  for (const t of trips) tripSeed[t.key] = t.record;
  const bookingKv = makeKV(bookingSeed);
  const trackingKv = makeKV(tripSeed);
  return {
    env: {
      ADMIN_TOKEN: ADMIN,
      BOOKING_KV: bookingKv,
      FLUXIDI_TRACKING: trackingKv,
    },
    bookingKv,
    trackingKv,
  };
}

function paymentRequest({ bookingId, token, method = "cash", bodyExtra = {} }) {
  return new Request(
    `https://booking.internal/bookings/${bookingId}/payment`,
    {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        payment_status: "paid",
        payment_method: method,
        payment_source: "in_car",
        amount: 18.5,
        currency: "EUR",
        ...bodyExtra,
      }),
    },
  );
}

function getBookingRequest({ bookingId, token, tenantId, companyId }) {
  const url = new URL(
    `https://booking.internal/bookings/${bookingId}`,
  );
  url.searchParams.set("tenant_id", tenantId);
  url.searchParams.set("company_id", companyId);
  return new Request(url, {
    method: "GET",
    headers: {
      accept: "application/json",
      authorization: `Bearer ${token}`,
    },
  });
}

function parseStored(raw) {
  return typeof raw === "string" ? JSON.parse(raw) : raw;
}

test("3) canonical server response for the same street ride is Paid after cash", async () => {
  const bookingId = "street_1785400671167_x5d21ooz";
  const tripId = "trip_street_cash_1";
  const booking = seedStreetBooking({
    bookingId,
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    tripId,
  });
  const trip = seedTrackingTrip({
    tenantId: "T1",
    companyId: "C1",
    tripId,
    bookingId,
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env, bookingKv, trackingKv } = await makeEnv({
    bookings: [booking],
    trips: [trip],
    driverSessions: [driver],
  });
  const fetchGuard = assertNoOutboundPspFetch("cash-canonical-paid");
  try {
    const payRes = await worker.fetch(
      paymentRequest({ bookingId, token: "alice-token", method: "cash" }),
      env,
      {},
    );
    const payJson = await payRes.json();
    assert.equal(payRes.status, 200);
    assert.equal(payJson.ok, true);
    assert.equal(payJson.payment_status, "paid");
    assert.equal(payJson.payment_method, "cash");

    const storedBooking = parseStored(bookingKv.store.get(booking.key));
    assert.equal(storedBooking.payment_status, "paid");
    assert.equal(storedBooking.payment_method, "cash");

    const storedTrip = parseStored(trackingKv.store.get(trip.key));
    assert.equal(
      storedTrip.payment_status,
      "paid",
      "tracking trip must inherit Paid via tracking_trip_id",
    );
    assert.equal(storedTrip.payment_method, "cash");
    assert.equal(storedTrip.booking_details.payment_status, "paid");
    assert.equal(storedTrip.booking_details.payment_method, "cash");

    const getRes = await worker.fetch(
      getBookingRequest({
        bookingId,
        token: "alice-token",
        tenantId: "T1",
        companyId: "C1",
      }),
      env,
      {},
    );
    const getJson = await getRes.json();
    assert.equal(getRes.status, 200);
    assert.equal(getJson.ok, true);
    const status =
      getJson.payment_status ||
      getJson.paymentStatus ||
      getJson.record?.payment_status ||
      getJson.record?.paymentStatus ||
      getJson.booking?.payment_status ||
      getJson.booking?.paymentStatus;
    assert.equal(status, "paid");
    fetchGuard.assertClean();
  } finally {
    fetchGuard.restore();
  }
});

test("7) duplicate cash confirmation is idempotent", async () => {
  const bookingId = "street_cash_idem_1";
  const tripId = "trip_cash_idem_1";
  const booking = seedStreetBooking({
    bookingId,
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    tripId,
  });
  const trip = seedTrackingTrip({
    tenantId: "T1",
    companyId: "C1",
    tripId,
    bookingId,
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env, bookingKv } = await makeEnv({
    bookings: [booking],
    trips: [trip],
    driverSessions: [driver],
  });
  const first = await worker.fetch(
    paymentRequest({ bookingId, token: "alice-token", method: "cash" }),
    env,
    {},
  );
  const firstJson = await first.json();
  assert.equal(first.status, 200);
  assert.equal(firstJson.payment_status, "paid");

  const second = await worker.fetch(
    paymentRequest({ bookingId, token: "alice-token", method: "cash" }),
    env,
    {},
  );
  const secondJson = await second.json();
  assert.equal(second.status, 200);
  assert.equal(secondJson.ok, true);
  assert.equal(secondJson.payment_status, "paid");
  const after = parseStored(bookingKv.store.get(booking.key));
  assert.equal(after.payment_status, "paid");
  assert.equal(after.payment_method, "cash");
});

test("8) QR payment keeps the same durable paid truth + trip sync", async () => {
  const bookingId = "street_qr_1";
  const tripId = "trip_qr_1";
  const booking = seedStreetBooking({
    bookingId,
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    tripId,
  });
  const trip = seedTrackingTrip({
    tenantId: "T1",
    companyId: "C1",
    tripId,
    bookingId,
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env, trackingKv } = await makeEnv({
    bookings: [booking],
    trips: [trip],
    driverSessions: [driver],
  });
  const res = await worker.fetch(
    paymentRequest({ bookingId, token: "alice-token", method: "qr_code" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.payment_status, "paid");
  assert.equal(parseStored(trackingKv.store.get(trip.key)).payment_status, "paid");
});

test("9) terminal (bancontact) confirmation keeps the same durable paid truth", async () => {
  const bookingId = "street_term_1";
  const tripId = "trip_term_1";
  const booking = seedStreetBooking({
    bookingId,
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    tripId,
  });
  const trip = seedTrackingTrip({
    tenantId: "T1",
    companyId: "C1",
    tripId,
    bookingId,
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env, trackingKv } = await makeEnv({
    bookings: [booking],
    trips: [trip],
    driverSessions: [driver],
  });
  const res = await worker.fetch(
    paymentRequest({ bookingId, token: "alice-token", method: "bancontact" }),
    env,
    {},
  );
  const j = await res.json();
  assert.equal(res.status, 200);
  assert.equal(j.payment_status, "paid");
  assert.equal(parseStored(trackingKv.store.get(trip.key)).payment_status, "paid");
});

test("10) successful cash payment does not auto-create a business invoice "
  + "(no Billit outbound)", async () => {
  const bookingId = "street_no_invoice_1";
  const tripId = "trip_no_invoice_1";
  const booking = seedStreetBooking({
    bookingId,
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    tripId,
  });
  const trip = seedTrackingTrip({
    tenantId: "T1",
    companyId: "C1",
    tripId,
    bookingId,
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env } = await makeEnv({
    bookings: [booking],
    trips: [trip],
    driverSessions: [driver],
  });
  const fetchGuard = assertNoOutboundPspFetch("cash-no-invoice");
  try {
    const res = await worker.fetch(
      paymentRequest({ bookingId, token: "alice-token", method: "cash" }),
      env,
      {},
    );
    assert.equal(res.status, 200);
    fetchGuard.assertClean();
  } finally {
    fetchGuard.restore();
  }
});

test("12) cross-tenant cash mark-paid remains blocked", async () => {
  const booking = seedStreetBooking({
    bookingId: "street_xtenant_1",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
    tripId: "trip_xtenant_1",
  });
  const foreign = await seedDriverSession({
    tokenValue: "bob-token",
    tenantId: "T2",
    companyId: "C2",
    driverId: "D-bob",
  });
  const { env, bookingKv } = await makeEnv({
    bookings: [booking],
    driverSessions: [foreign],
  });
  const res = await worker.fetch(
    paymentRequest({
      bookingId: "street_xtenant_1",
      token: "bob-token",
      method: "cash",
    }),
    env,
    {},
  );
  assert.notEqual(res.status, 200);
  const stored = parseStored(bookingKv.store.get(booking.key));
  assert.equal(stored.payment_status, "unpaid");
});

test("tracking_trip_id is required for street trip sync "
  + "(pre-fix miss would leave History Unpaid)", async () => {
  const bookingId = "street_no_link_1";
  const tripId = "trip_no_link_1";
  // Booking WITHOUT tracking_trip_id — pre-fix resolver miss.
  const booking = {
    key: `booking:${bookingId}`,
    record: {
      booking_id: bookingId,
      tenant_id: "T1",
      company_id: "C1",
      status: "completed",
      payment_status: "unpaid",
      assigned_driver_id: "D-alice",
      assignedDriverId: "D-alice",
      kind: "direct",
    },
  };
  const trip = seedTrackingTrip({
    tenantId: "T1",
    companyId: "C1",
    tripId,
    bookingId,
  });
  const driver = await seedDriverSession({
    tokenValue: "alice-token",
    tenantId: "T1",
    companyId: "C1",
    driverId: "D-alice",
  });
  const { env, bookingKv, trackingKv } = await makeEnv({
    bookings: [booking],
    trips: [trip],
    driverSessions: [driver],
  });
  const res = await worker.fetch(
    paymentRequest({ bookingId, token: "alice-token", method: "cash" }),
    env,
    {},
  );
  assert.equal(res.status, 200);
  assert.equal(parseStored(bookingKv.store.get(booking.key)).payment_status, "paid");
  // Without tracking_trip_id the trip stays unpaid — documents the pre-fix
  // History miss. With tracking_trip_id (tests above) the trip becomes paid.
  assert.equal(
    parseStored(trackingKv.store.get(trip.key)).payment_status,
    "unpaid",
  );
});
