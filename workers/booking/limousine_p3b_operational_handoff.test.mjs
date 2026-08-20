// LIMOUSINE-OPERATIONAL-HANDOFF-P3B — persistent E2E on existing route handlers.
// Run: node --test workers/booking/limousine_p3b_operational_handoff.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  computeLimousineHourlyHireSnapshot,
  computeLimousinePackageSnapshot,
} from "./modules/limousine_unified_intent.mjs";
import { projectLimousineOperationalListFields } from "./modules/limousine_operational_handoff.mjs";

const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3b";
const COMPANY = "company_limo_p3b";
const OTHER_TENANT = "fluxidi_other_p3b";
const OTHER_COMPANY = "company_other_p3b";
const CUSTOMER = "cust_limo_p3b";
const DRIVER = "D-limo-p3b";
const VEHICLE = "veh_limo_existing";
const SECRET = "p3b-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const OTHER_PUBLIC_PARTNER = `company:${OTHER_TENANT}:${OTHER_COMPANY}`;

const TERMS = {
  terms_revision: 3,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 50,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
  mobilisation_disclosure: { en: "Mobilisation included" },
};

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

async function seedSessions() {
  const companyHash = await sha256Hex("co-p3b");
  const otherHash = await sha256Hex("co-other");
  const customerHash = await sha256Hex("cus-p3b");
  const driverHash = await sha256Hex("drv-p3b");
  const expires = new Date(Date.now() + 3600_000).toISOString();
  return {
    [`company_admin:session:${companyHash}:v1`]: {
      role: "company_admin",
      tenant_id: TENANT,
      company_id: COMPANY,
      expires_at: expires,
    },
    [`company_admin:session:${otherHash}:v1`]: {
      role: "company_admin",
      tenant_id: OTHER_TENANT,
      company_id: OTHER_COMPANY,
      expires_at: expires,
    },
    [`customer:session:${customerHash}:v1`]: {
      role: "customer",
      purpose: "customer_session",
      tenant_id: TENANT,
      company_id: COMPANY,
      customer_id: CUSTOMER,
      phone_hash: "phonehash_p3b",
      expires_at: expires,
    },
    [`customer:session:${await sha256Hex("cus-other")}:v1`]: {
      role: "customer",
      purpose: "customer_session",
      tenant_id: TENANT,
      company_id: COMPANY,
      customer_id: "cust_other_p3b",
      phone_hash: "phonehash_other",
      expires_at: expires,
    },
    [`public_driver:session:${driverHash}:v1`]: {
      role: "driver",
      tenant_id: TENANT,
      company_id: COMPANY,
      driver_id: DRIVER,
      expires_at: expires,
    },
  };
}

function pickupIso(offsetMs = -60 * 60 * 1000) {
  return new Date(Date.now() + offsetMs).toISOString();
}

function quoteRecord({
  id,
  state = "requested",
  pricingMode = "quote_required",
  fromPriceCents = null,
  bookingReference = "",
} = {}) {
  const now = new Date().toISOString();
  return {
    quote_request_id: id,
    tenant_id: TENANT,
    company_id: COMPANY,
    state,
    revision: state === "requested" ? 1 : 2,
    offer_source_revision: 1,
    pricing_section_revision: 1,
    created_at: now,
    updated_at: now,
    request: {
      offer_id: "off_exec",
      service_class_id: "executive_sedan",
      vehicle_id: VEHICLE,
      journey_type: "hourly_hire",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: pickupIso(2 * 3600_000),
      requested_duration_minutes: 180,
      occasion: "wedding",
      pax: 4,
      service_type: "limousine",
      pricing_mode: pricingMode,
    },
    pricing_snapshot: {
      service_type: "limousine",
      pricing_mode: pricingMode,
      ...(fromPriceCents != null ? { from_price_cents: fromPriceCents } : {}),
      requested_duration_minutes: 180,
    },
    ...(state === "quoted" || state === "accepted" || state === "booking_created"
      ? {
          quote: {
            total_incl_vat_cents: 18500,
            currency: "EUR",
            vat_rate: 0.06,
            vat_treatment: "incl",
            terms: TERMS,
            terms_revision: 3,
            expires_at: new Date(Date.now() + 48 * 3600_000).toISOString(),
            quoted_at: now,
            mobilisation_disclosure: { en: "Mobilisation included" },
          },
        }
      : {}),
    ...(bookingReference ? { booking_reference: bookingReference } : {}),
  };
}

function inboxIndex(entries) {
  return {
    v: 1,
    tenant_id: TENANT,
    company_id: COMPANY,
    next_activity_seq: entries.length + 1,
    entries: entries.map((entry, index) => ({
      quote_request_id: entry.quote_request_id,
      activity_seq: index + 1,
      updated_at: entry.updated_at,
      revision: entry.revision,
      state: entry.state,
    })),
  };
}

function limousineBooking({
  bookingId,
  confirmationRequired = true,
  pricingMode = "exact_fixed",
  status = "PENDING",
  paymentStatus = "unpaid",
  assignedDriverId = "",
  assignedVehicleId = "",
  snapshot = null,
} = {}) {
  const iso = pickupIso(-30 * 60 * 1000);
  const pricing = snapshot || {
    service_type: "limousine",
    published_pricing_mode: pricingMode,
    pricing_mode: pricingMode,
    amount_cents: 25000,
    requested_duration_minutes: 180,
    company_confirmation_required: confirmationRequired,
  };
  return {
    booking_id: bookingId,
    tenant_id: TENANT,
    company_id: COMPANY,
    customer_id: CUSTOMER,
    customerId: CUSTOMER,
    status,
    stage: status,
    payment_status: paymentStatus,
    payment_mode: "mollie",
    payment_provider: "mollie",
    service_type: "limousine",
    serviceType: "limousine",
    service_category: "limousine",
    pricing_mode: pricingMode,
    occasion: "gala",
    requested_duration_minutes: 180,
    company_confirmation_required: confirmationRequired,
    public_booking_reference: `P3B-${bookingId}`,
    planning_reference: `PLN-${bookingId}`,
    assigned_driver_id: assignedDriverId || undefined,
    assignedDriverId: assignedDriverId || undefined,
    assigned_vehicle_id: assignedVehicleId || undefined,
    assignedVehicleId: assignedVehicleId || undefined,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    booking: {
      bookingId,
      from: "Gent",
      to: "Brussel",
      pickup_iso: iso,
      pickupStartIso: iso,
      status,
      service_type: "limousine",
      pricing_mode: pricingMode,
      occasion: "gala",
      requested_duration_minutes: 180,
      company_confirmation_required: confirmationRequired,
      limousine_accepted_price: pricing,
      price_incl_vat: 250,
      currency: "EUR",
      customer_name: "Anna Klant",
      customer_id: CUSTOMER,
    },
    quote: {
      from: "Gent",
      to: "Brussel",
      pickup_iso: iso,
      pricing: { price_incl_vat: 250, currency: "EUR" },
    },
  };
}

function companyIndex(bookingIds) {
  const now = new Date().toISOString();
  return {
    version: 1,
    updated_at: now,
    items: bookingIds.map((bookingId) => ({
      booking_id: bookingId,
      sort_ts: Date.now(),
      pickup_iso: pickupIso(-30 * 60 * 1000),
      updated_at: now,
      lifecycle: "pending",
      status: "PENDING",
    })),
  };
}

function driverIndex(bookingIds) {
  const now = new Date().toISOString();
  return {
    version: 1,
    updated_at: now,
    items: bookingIds.map((bookingId) => ({
      booking_id: bookingId,
      sort_ts: Date.now(),
      pickup_iso: pickupIso(-30 * 60 * 1000),
      updated_at: now,
    })),
  };
}

function jsonReq(path, { method = "POST", token = null, admin = false, body = null, query = "" } = {}) {
  const headers = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  if (admin) headers["x-admin-token"] = ADMIN;
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

function envOf(kv, extra = {}) {
  return {
    ADMIN_TOKEN: ADMIN,
    BOOKING_KV: kv,
    LIMOUSINE_QUOTE_ENABLED: "1",
    LIMOUSINE_MANUAL_QUOTE_ENABLED: "1",
    LIMOUSINE_BOOK_ENABLED: "1",
    LIMOUSINE_TEST_COMPANY_ALLOWLIST: COMPANY,
    LIMOUSINE_ACCEPTANCE_SECRET: SECRET,
    fetch: async (input) => {
      throw new Error(`blocked outbound ${input?.url || input}`);
    },
    ...extra,
  };
}

async function setup({ quotes = [], bookings = [] } = {}) {
  const sessions = await seedSessions();
  const seed = { ...sessions };
  for (const quote of quotes) {
    seed[`limousine_quote_record:${quote.quote_request_id}`] = quote;
  }
  if (quotes.length) {
    seed[`limousine_quote_inbox_v1:${TENANT}:${COMPANY}`] = inboxIndex(quotes);
  }
  for (const booking of bookings) {
    seed[`booking:${booking.booking_id}`] = booking;
  }
  if (bookings.length) {
    seed[`tenant:${TENANT}:company:${COMPANY}:bookings:list:v1`] = companyIndex(
      bookings.map((item) => item.booking_id),
    );
  }
  seed[`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`] = {
    vehicles: [{ vehicle_id: VEHICLE, is_active: true, active: true }],
  };
  seed["public:partners:booking-routes:v2"] = {
    routes: [
      {
        partner_id: PUBLIC_PARTNER,
        tenant_id: TENANT,
        company_id: COMPANY,
        is_active: true,
        subscription_status: "active",
      },
      {
        partner_id: OTHER_PUBLIC_PARTNER,
        tenant_id: OTHER_TENANT,
        company_id: OTHER_COMPANY,
        is_active: true,
        subscription_status: "active",
      },
    ],
  };
  const kv = makeKV(seed);
  return { kv, env: envOf(kv) };
}

function bookBody(extra = {}) {
  return {
    public_partner_id: PUBLIC_PARTNER,
    from: "Gent",
    to: "Brussel",
    pickup_iso: pickupIso(2 * 3600_000),
    service: "limousine",
    service_category: "limousine",
    ...extra,
  };
}

test("A) quote_required inbox → company quote → accept keeps service_type=limousine", async () => {
  const requested = quoteRecord({ id: "limq_quote_a", pricingMode: "quote_required" });
  const { env } = await setup({ quotes: [requested] });
  const list = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-p3b",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    env,
    {},
  );
  const listed = await list.json();
  assert.equal(list.status, 200, JSON.stringify(listed));
  assert.equal(listed.items?.[0]?.service_type, "limousine");
  assert.equal(listed.items?.[0]?.pricing_mode, "quote_required");
  assert.equal(listed.items?.[0]?.occasion, "wedding");
  assert.equal(listed.items?.[0]?.vehicle_id, VEHICLE);

  const respond = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: "limq_quote_a",
        action: "quote",
        expected_revision: 1,
        total_incl_vat_cents: 18500,
        currency: "EUR",
        vat_rate: 0.06,
        terms: TERMS,
      },
    }),
    env,
    {},
  );
  const quoted = await respond.json();
  assert.equal(respond.status, 200, JSON.stringify(quoted));
  assert.equal(quoted.quote_request?.service_type, "limousine");
  assert.equal(quoted.quote_request?.quote?.total_incl_vat_cents, 18500);

  const accept = await worker.fetch(
    jsonReq("/limousine/quote-requests/accept", {
      token: "cus-p3b",
      body: {
        quote_request_id: "limq_quote_a",
        expected_revision: quoted.quote_request.revision,
      },
    }),
    env,
    {},
  );
  const accepted = await accept.json();
  assert.equal(accept.status, 200, JSON.stringify(accepted));
  assert.equal(accepted.quote_request?.state, "accepted");
  assert.equal(accepted.quote_request?.service_type, "limousine");
  assert.ok(String(accepted.acceptance_reference || "").startsWith("limacc1."));
});

test("B) from_price stays informational and is never the booking total", async () => {
  const requested = quoteRecord({
    id: "limq_from_b",
    pricingMode: "from_price",
    fromPriceCents: 12000,
  });
  const { env } = await setup({ quotes: [requested] });
  const list = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-p3b",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    env,
    {},
  );
  const listed = await list.json();
  assert.equal(listed.items?.[0]?.pricing_mode, "from_price");
  assert.equal(listed.items?.[0]?.pricing_snapshot?.from_price_cents, 12000);
  assert.notEqual(listed.items?.[0]?.pricing_snapshot?.from_price_cents, 0);
  assert.equal(listed.items?.[0]?.quote, undefined);
});

test("C) exact_fixed request → confirm on existing status POST → payment unblocked", async () => {
  const booking = limousineBooking({
    bookingId: "2026-08-301",
    pricingMode: "exact_fixed",
    confirmationRequired: true,
  });
  const { env } = await setup({ bookings: [booking] });
  const beforePay = await worker.fetch(
    jsonReq("/bookings/2026-08-301/checkout-resume", {
      token: "co-p3b",
      body: { tenant_id: TENANT, company_id: COMPANY },
    }),
    env,
    {},
  );
  const before = await beforePay.json();
  assert.equal(before.ok, false);
  assert.equal(before.error, "company_confirmation_required");

  const confirm = await worker.fetch(
    jsonReq("/bookings/2026-08-301/status", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        status: "confirmed",
        actor_role: "admin",
      },
    }),
    env,
    {},
  );
  const confirmed = await confirm.json();
  assert.equal(confirm.status, 200, JSON.stringify(confirmed));
  assert.equal(confirmed.ok, true);
  const stored = await env.BOOKING_KV.get("booking:2026-08-301", { type: "json" });
  assert.equal(stored.company_confirmation_required, false);
  assert.equal(String(stored.status).toUpperCase(), "PENDING");
  assert.equal(stored.service_type, "limousine");
  assert.ok(stored.company_confirmed_at);

  const afterPay = await worker.fetch(
    jsonReq("/bookings/2026-08-301/checkout-resume", {
      token: "co-p3b",
      body: { tenant_id: TENANT, company_id: COMPANY },
    }),
    env,
    {},
  );
  const after = await afterPay.json();
  assert.notEqual(after.error, "company_confirmation_required");
});

test("D) hourly billable is max(requested, minimum) integer cents", () => {
  const hourly = {
    enabled: true,
    first_hour_cents: 10000,
    additional_hour_cents: 8000,
    minimum_duration_minutes: 120,
    currency: "EUR",
  };
  const below = computeLimousineHourlyHireSnapshot(hourly, 60);
  const above = computeLimousineHourlyHireSnapshot(hourly, 180);
  assert.equal(below.billable_duration_minutes, 120);
  assert.equal(above.billable_duration_minutes, 180);
  assert.equal(Number.isInteger(below.amount_cents), true);
  const rec = limousineBooking({
    bookingId: "2026-08-302",
    pricingMode: "hourly",
    snapshot: {
      service_type: "limousine",
      published_pricing_mode: "hourly",
      amount_cents: below.amount_cents,
      requested_duration_minutes: 60,
      billable_duration_minutes: 120,
    },
  });
  const row = projectLimousineOperationalListFields(rec);
  assert.equal(row.service_type, "limousine");
  assert.equal(row.pricing_mode, "hourly");
  assert.equal(row.pricing_snapshot.billable_duration_minutes, 120);
});

test("E) package included scope stays and missing overage fails closed", () => {
  const offer = {
    offer_id: "off_pkg",
    hourly: {
      enabled: true,
      package_amount_cents: 45000,
      package_duration_minutes: 180,
      included_distance_km: 40,
    },
    included_services: [{ item_id: "chauffeur" }],
  };
  const included = computeLimousinePackageSnapshot(offer, 180);
  assert.equal(included.ok, true);
  assert.equal(included.package_amount_cents, 45000);
  assert.equal(included.included_duration_minutes, 180);
  const missing = computeLimousinePackageSnapshot(offer, 240);
  assert.equal(missing.ok, false);
});

test("F1) planning, assign, driver, complete and history stay on existing routes", async () => {
  const booking = limousineBooking({
    bookingId: "2026-08-303",
    pricingMode: "package",
    confirmationRequired: false,
  });
  const { env } = await setup({ bookings: [booking] });
  const list = await worker.fetch(
    jsonReq("/bookings", {
      method: "GET",
      token: "co-p3b",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    env,
    {},
  );
  const listed = await list.json();
  assert.equal(list.status, 200, JSON.stringify(listed));
  const row = (listed.items || []).find((item) => item.booking_id === "2026-08-303");
  assert.ok(row, JSON.stringify(listed));
  assert.equal(row.service_type, "limousine");
  assert.equal(row.pricing_mode, "package");
  assert.equal(row.occasion, "gala");

  const assign = await worker.fetch(
    jsonReq("/bookings/2026-08-303/assign", {
      admin: true,
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        vehicle_id: VEHICLE,
        driver_id: DRIVER,
      },
    }),
    env,
    {},
  );
  const assigned = await assign.json();
  assert.equal(assign.status, 200, JSON.stringify(assigned));
  assert.equal(assigned.assigned_vehicle_id, VEHICLE);
  assert.equal(assigned.assigned_driver_id, DRIVER);

  const driverList = await worker.fetch(
    jsonReq("/driver/bookings", { method: "GET", token: "drv-p3b" }),
    env,
    {},
  );
  const driverJson = await driverList.json();
  assert.equal(driverList.status, 200, JSON.stringify(driverJson));
  const driverRow = (driverJson.items || []).find((item) =>
    String(item.booking_id || "").includes("2026-08-303"),
  );
  assert.ok(driverRow, JSON.stringify(driverJson));
  assert.equal(driverRow.service_type, "limousine");

  const complete = await worker.fetch(
    jsonReq("/bookings/2026-08-303/status", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        status: "COMPLETED",
        actor_role: "admin",
      },
    }),
    env,
    {},
  );
  const completed = await complete.json();
  assert.equal(complete.status, 200, JSON.stringify(completed));
  const history = await worker.fetch(
    jsonReq("/bookings", {
      method: "GET",
      token: "co-p3b",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}&include_history=1`,
    }),
    env,
    {},
  );
  const historyJson = await history.json();
  const historyRow = (historyJson.items || []).find((item) =>
    String(item.booking_id || "").includes("2026-08-303"),
  );
  assert.ok(historyRow, JSON.stringify(historyJson));
  assert.equal(String(historyRow.status).toUpperCase(), "COMPLETED");
  assert.equal(historyRow.service_type, "limousine");
  const keys = [...env.BOOKING_KV.store.keys()].join(",");
  assert.ok(!keys.toLowerCase().includes("billit_outbox"));
  assert.ok(!keys.toLowerCase().includes("chiron"));
});

test("F2) decline, cancel, wrong tenant, pay-before-confirm and gate-off stay fail-closed", async () => {
  const requested = quoteRecord({ id: "limq_neg_f" });
  const booking = limousineBooking({ bookingId: "2026-08-304" });
  const { env } = await setup({ quotes: [requested], bookings: [booking] });

  const decline = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: "limq_neg_f",
        action: "decline",
        expected_revision: 1,
        reason_code: "company_declined",
      },
    }),
    env,
    {},
  );
  const declined = await decline.json();
  assert.equal(declined.quote_request?.state, "declined");

  const payEarly = await worker.fetch(
    jsonReq("/bookings/2026-08-304/payment", {
      admin: true,
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        payment_status: "paid",
        payment_provider: "mollie",
      },
    }),
    env,
    {},
  );
  const paidEarly = await payEarly.json();
  assert.equal(paidEarly.error, "company_confirmation_required");

  const cancel = await worker.fetch(
    jsonReq("/bookings/2026-08-304/status", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        status: "CANCELLED",
        actor_role: "admin",
      },
    }),
    env,
    {},
  );
  const cancelled = await cancel.json();
  assert.equal(cancel.status, 200, JSON.stringify(cancelled));
  const stored = await env.BOOKING_KV.get("booking:2026-08-304", { type: "json" });
  assert.equal(String(stored.status).toUpperCase(), "CANCELLED");
  const keys = [...env.BOOKING_KV.store.keys()].join(",");
  assert.ok(!keys.toLowerCase().includes("billit_outbox"));

  const foreign = await worker.fetch(
    jsonReq("/bookings", {
      method: "GET",
      token: "co-other",
      query: `?tenant_id=${OTHER_TENANT}&company_id=${OTHER_COMPANY}`,
    }),
    env,
    {},
  );
  const foreignJson = await foreign.json();
  const leaked = (foreignJson.items || []).some((item) =>
    String(item.booking_id || "").includes("2026-08-304"),
  );
  assert.equal(leaked, false);

  const gated = envOf(env.BOOKING_KV, { LIMOUSINE_MANUAL_QUOTE_ENABLED: "0" });
  const gateOff = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-p3b",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    gated,
    {},
  );
  assert.equal(gateOff.status, 404);
});

test("F3) customer GET keeps service_type=limousine and Command Center uses existing KPI", async () => {
  const quoteOnly = quoteRecord({ id: "limq_cc_quote" });
  const booking = limousineBooking({
    bookingId: "2026-08-305",
    confirmationRequired: true,
  });
  const { env } = await setup({ quotes: [quoteOnly], bookings: [booking] });
  const get = await worker.fetch(
    jsonReq("/bookings/2026-08-305", { method: "GET", token: "cus-p3b" }),
    env,
    {},
  );
  const json = await get.json();
  assert.equal(get.status, 200, JSON.stringify(json));
  assert.equal(json.record?.service_type, "limousine");
  assert.equal(json.record?.booking?.service_type, "limousine");
  assert.equal(json.record?.company_confirmation_required, true);
  assert.equal(String(json.record?.payment_status || "unpaid").toLowerCase(), "unpaid");

  const confirm = await worker.fetch(
    jsonReq("/bookings/2026-08-305/status", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        status: "confirmed",
        actor_role: "admin",
      },
    }),
    env,
    {},
  );
  assert.equal(confirm.status, 200, JSON.stringify(await confirm.json()));
  const complete = await worker.fetch(
    jsonReq("/bookings/2026-08-305/status", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        status: "COMPLETED",
        actor_role: "admin",
      },
    }),
    env,
    {},
  );
  assert.equal(complete.status, 200, JSON.stringify(await complete.json()));
  const kpiKeys = [...env.BOOKING_KV.store.keys()].filter((key) =>
    key.includes("dashboard:bookings_kpi"),
  );
  assert.ok(
    kpiKeys.some((key) => key.includes(`tenant:${TENANT}:company:${COMPANY}`)),
    kpiKeys.join(","),
  );
  assert.equal(
    kpiKeys.some((key) => key.includes(OTHER_TENANT) || key.includes(OTHER_COMPANY)),
    false,
  );
  const quoteKeys = [...env.BOOKING_KV.store.keys()].filter((key) =>
    key.includes("limousine_quote"),
  );
  assert.ok(quoteKeys.length > 0);
  assert.equal(
    quoteKeys.some((key) => key.includes("dashboard:bookings_kpi")),
    false,
  );
});

test("F4) double accept, expired quote and consume-once stay fail-closed", async () => {
  const requested = quoteRecord({ id: "limq_dup_a" });
  const expired = quoteRecord({
    id: "limq_exp_a",
    state: "quoted",
  });
  expired.quote.expires_at = new Date(Date.now() - 60_000).toISOString();
  expired.revision = 2;
  const { env } = await setup({ quotes: [requested, expired] });

  const respond = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: "limq_dup_a",
        action: "quote",
        expected_revision: 1,
        total_incl_vat_cents: 18500,
        currency: "EUR",
        vat_rate: 0.06,
        terms: TERMS,
      },
    }),
    env,
    {},
  );
  const quoted = await respond.json();
  assert.equal(respond.status, 200, JSON.stringify(quoted));

  const acceptBody = {
    quote_request_id: "limq_dup_a",
    expected_revision: quoted.quote_request.revision,
  };
  const acceptA = await worker.fetch(
    jsonReq("/limousine/quote-requests/accept", { token: "cus-p3b", body: acceptBody }),
    env,
    {},
  );
  const acceptedA = await acceptA.json();
  assert.equal(acceptA.status, 200, JSON.stringify(acceptedA));
  const acceptB = await worker.fetch(
    jsonReq("/limousine/quote-requests/accept", { token: "cus-p3b", body: acceptBody }),
    env,
    {},
  );
  const acceptedB = await acceptB.json();
  assert.notEqual(acceptB.status, 200, JSON.stringify(acceptedB));

  const expiredAccept = await worker.fetch(
    jsonReq("/limousine/quote-requests/accept", {
      token: "cus-p3b",
      body: { quote_request_id: "limq_exp_a", expected_revision: 2 },
    }),
    env,
    {},
  );
  const expiredJson = await expiredAccept.json();
  assert.notEqual(expiredAccept.status, 200, JSON.stringify(expiredJson));

  const quoteId = "limq_dup_a";
  const storedQuote = await env.BOOKING_KV.get(`limousine_quote_record:${quoteId}`, {
    type: "json",
  });
  storedQuote.state = "booking_created";
  storedQuote.booking_reference = "2026-08-399";
  await env.BOOKING_KV.put(`limousine_quote_record:${quoteId}`, storedQuote);
  const replay = await worker.fetch(
    jsonReq("/book", {
      token: "cus-p3b",
      body: bookBody({
        customer_id: CUSTOMER,
        limousine_acceptance_reference: acceptedA.acceptance_reference,
      }),
    }),
    env,
    {},
  );
  const replayed = await replay.json();
  assert.equal(replayed.error, "acceptance_reference_already_used", JSON.stringify(replayed));
});

test("F5) wrong tenant/customer and unpublished/missing-duration stay fail-closed", async () => {
  const requested = quoteRecord({ id: "limq_scope_a" });
  const { env } = await setup({ quotes: [requested] });
  const respond = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests/respond", {
      token: "co-p3b",
      body: {
        tenant_id: TENANT,
        company_id: COMPANY,
        quote_request_id: "limq_scope_a",
        action: "quote",
        expected_revision: 1,
        total_incl_vat_cents: 18500,
        currency: "EUR",
        vat_rate: 0.06,
        terms: TERMS,
      },
    }),
    env,
    {},
  );
  const quoted = await respond.json();
  const accept = await worker.fetch(
    jsonReq("/limousine/quote-requests/accept", {
      token: "cus-p3b",
      body: {
        quote_request_id: "limq_scope_a",
        expected_revision: quoted.quote_request.revision,
      },
    }),
    env,
    {},
  );
  const accepted = await accept.json();
  assert.equal(accept.status, 200, JSON.stringify(accepted));

  const foreignBook = await worker.fetch(
    jsonReq("/book", {
      token: "co-other",
      body: bookBody({
        public_partner_id: OTHER_PUBLIC_PARTNER,
        limousine_acceptance_reference: accepted.acceptance_reference,
      }),
    }),
    env,
    {},
  );
  const foreignJson = await foreignBook.json();
  assert.ok(
    ["unauthorized_scope", "limousine_unavailable", "missing_tenant_scope"].includes(
      foreignJson.error,
    ),
    JSON.stringify(foreignJson),
  );

  const wrongCustomer = await worker.fetch(
    jsonReq("/book", {
      token: "cus-other",
      body: bookBody({
        customer_id: "cust_other_p3b",
        limousine_acceptance_reference: accepted.acceptance_reference,
      }),
    }),
    env,
    {},
  );
  const wrongCustomerJson = await wrongCustomer.json();
  assert.ok(
    ["unauthorized_scope", "acceptance_reference_already_used", "limousine_unavailable"].includes(
      wrongCustomerJson.error,
    ) || wrongCustomer.status !== 200,
    JSON.stringify(wrongCustomerJson),
  );

  const missingDuration = await worker.fetch(
    jsonReq("/book", {
      token: "cus-p3b",
      body: bookBody({
        offer_id: "off_unpublished",
        pricing_mode: "hourly",
      }),
    }),
    env,
    {},
  );
  const missingJson = await missingDuration.json();
  assert.notEqual(missingDuration.status, 200, JSON.stringify(missingJson));
  assert.notEqual(missingJson.error, undefined);
});
