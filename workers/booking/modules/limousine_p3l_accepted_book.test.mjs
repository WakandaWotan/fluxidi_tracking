// P3L — accepted quotation /book, seller authority, QR, billing, dispatch.
// Run: node --test workers/booking/modules/limousine_p3l_accepted_book.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import worker from "../fluxidi_booking_worker.js";
import {
  buildLimousineAcceptanceBinding,
  publicLimousinePartnerId,
  publicLimousineQuoteView,
} from "./limousine_manual_quote.mjs";
import { sealLimousineAcceptance } from "./limousine_acceptance_token.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3l";
const COMPANY = "company_limo_p3l";
const OTHER_TENANT = "fluxidi_other_p3l";
const OTHER_COMPANY = "company_other_p3l";
const CUSTOMER = "cust_limo_p3l";
const DRIVER = "D-limo-p3l";
const VEHICLE = "veh_limo_p3l";
const SECRET = "p3l-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const OTHER_PUBLIC_PARTNER = `company:${OTHER_TENANT}:${OTHER_COMPANY}`;
const TOTAL_CENTS = 60000;

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

function vehicles() {
  return [
    {
      vehicle_id: VEHICLE,
      name: "Party Limo",
      service_category: "limousine",
      service_class: "stretch_limousine",
      is_active: true,
      active: true,
      photo_url: "https://cdn.example/party.jpg",
      passenger_capacity: 10,
      luggage_capacity: 4,
    },
  ];
}

function eligibleProfile() {
  return {
    partner_id: PUBLIC_PARTNER,
    company_name: "P3L Limo",
    company_id: COMPANY,
    is_active: true,
    bookable: true,
    profile_enabled: true,
    published_at: "2026-08-17T10:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine"],
    coverage: { city: "Gent" },
    vehicles: vehicles(),
  };
}

async function seedSessions() {
  const companyHash = await sha256Hex("co-p3l");
  const otherHash = await sha256Hex("co-other-p3l");
  const customerHash = await sha256Hex("cus-p3l");
  const globalHash = await sha256Hex("cus-global-p3l");
  const driverHash = await sha256Hex("drv-p3l");
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
      phone_hash: "phonehash_p3l",
      expires_at: expires,
    },
    [`customer:session:${globalHash}:v1`]: {
      role: "customer",
      purpose: "customer_session",
      tenant_id: "global",
      company_id: "global",
      customer_id: CUSTOMER,
      phone_hash: "phonehash_p3l_global",
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

function quoteRecord({ id, state = "accepted" } = {}) {
  const now = new Date().toISOString();
  return {
    quote_request_id: id,
    tenant_id: TENANT,
    company_id: COMPANY,
    public_partner_id: PUBLIC_PARTNER,
    state,
    revision: 3,
    offer_source_revision: 1,
    pricing_section_revision: 1,
    created_at: now,
    updated_at: now,
    accepted_at: now,
    request: {
      public_partner_id: PUBLIC_PARTNER,
      offer_id: "off_party",
      service_class_id: "stretch_limousine",
      vehicle_id: VEHICLE,
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-08-31T06:00:00.000Z",
      pax: 8,
      bags: 2,
      locale: "nl",
      service_type: "limousine",
      pricing_mode: "quote_required",
      vehicle_snapshot: {
        vehicle_id: VEHICLE,
        public_name: "Party Limo",
      },
    },
    quote: {
      total_incl_vat_cents: TOTAL_CENTS,
      currency: "EUR",
      vat_rate: 0.06,
      vat_treatment: "incl",
      terms: TERMS,
      terms_revision: 3,
      expires_at: "2099-01-01T00:00:00Z",
      quoted_at: now,
      mobilisation_disclosure: { en: "Mobilisation included" },
    },
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

function envOf(kv) {
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
  };
}

async function setup({ quotes = [] } = {}) {
  const sessions = await seedSessions();
  const seed = {
    ...sessions,
    [`tenant:${TENANT}:company:${COMPANY}:partner:profile:v1`]: {
      partner_profile: eligibleProfile(),
    },
    [`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`]: {
      vehicles: vehicles(),
    },
    [`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`]: {
      business_profile: {
        trading_name: "P3L Limo",
        legal_name: "P3L Limo BV",
        vat_number: "BE0772931038",
        address: "Markt 1",
        city: "Gent",
        postcode: "9000",
        country: "BE",
      },
    },
    "public:partners:booking-routes:v2": {
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
    },
  };
  for (const quote of quotes) {
    seed[`limousine_quote_record:${quote.quote_request_id}`] = quote;
  }
  const kv = makeKV(seed);
  return { kv, env: envOf(kv) };
}

async function sealAccepted(record) {
  const sealed = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBinding(record),
    ttlMinutes: 120,
  });
  assert.equal(sealed.ok, true, JSON.stringify(sealed));
  return sealed.reference;
}

function bookBody({
  acceptanceReference,
  paymentMethod = "qr_code",
  publicPartnerId = PUBLIC_PARTNER,
  billing = null,
  extra = {},
} = {}) {
  return {
    ...(publicPartnerId ? { public_partner_id: publicPartnerId } : {}),
    limousine_acceptance_reference: acceptanceReference,
    from: "Gent",
    to: "Brussel",
    pickup_iso: "2026-08-31T06:00:00.000Z",
    service: "limousine",
    service_category: "limousine",
    pax: 8,
    bags: 2,
    payment_mode: "manual",
    payment_provider: "manual",
    payment_method: paymentMethod,
    customer_id: CUSTOMER,
    customer: {
      name: "Ada",
      phone: "+32470000000",
      email: "ada@example.test",
    },
    ...(billing ? { billing_customer: billing } : {}),
    ...extra,
  };
}

const BUSINESS_BILLING = {
  legal_name: "Acme Events BV",
  vat_number: "BE0123456789",
  street: "Kerkstraat 12",
  postal_code: "2000",
  city: "Antwerpen",
  country: "BE",
  contact_email: "facturen@acme.test",
};

function acceptedTotalCents(stored) {
  return (
    Number(stored.limousine_accepted_price?.amount_cents) ||
    Number(stored.quote?.pricing?.total_incl_vat_cents) ||
    Math.round(Number(stored.quote?.pricing?.price_incl_vat || stored.price_incl_vat || 0) * 100)
  );
}

function assertSellerAuthority(stored, body) {
  assert.equal(stored.tenant_id, TENANT);
  assert.equal(stored.company_id, COMPANY);
  assert.notEqual(stored.tenant_id, "global");
  assert.notEqual(stored.company_id, "global");
  const billingName = String(
    stored.billing_customer_snapshot?.legal_name ||
      stored.billing_customer?.legal_name ||
      "",
  ).toLowerCase();
  if (billingName) {
    assert.notEqual(String(stored.company_id).toLowerCase(), billingName);
    assert.notEqual(String(stored.tenant_id).toLowerCase(), billingName);
  }
  assert.equal(acceptedTotalCents(stored), TOTAL_CENTS);
  assert.equal(String(stored.service_type || stored.serviceType || "").toLowerCase(), "limousine");
  const vehicle = String(
    stored.assigned_vehicle_id ||
      stored.required_vehicle_id ||
      stored.booking?.vehicle_id ||
      stored.limousine_accepted_price?.vehicle_id ||
      "",
  );
  if (vehicle) assert.equal(vehicle, VEHICLE);
  assert.equal(String(body?.error || ""), "");
}

test("1) public partner id prefers stored then derives company:tenant:company", () => {
  assert.equal(
    publicLimousinePartnerId({
      tenant_id: TENANT,
      company_id: COMPANY,
      public_partner_id: PUBLIC_PARTNER,
    }),
    PUBLIC_PARTNER,
  );
  assert.equal(
    publicLimousinePartnerId({ tenant_id: TENANT, company_id: COMPANY }),
    PUBLIC_PARTNER,
  );
  assert.equal(publicLimousinePartnerId({}), "");
  const view = publicLimousineQuoteView(quoteRecord({ id: "limq_view" }));
  assert.equal(view.public_partner_id, PUBLIC_PARTNER);
  assert.equal(view.quote.total_incl_vat_cents, TOTAL_CENTS);
});

test("2) worker keeps accepted-seller /book wiring", () => {
  assert.ok(WORKER_SRC.includes("async function _resolveAcceptedQuoteBookScope"));
  assert.ok(WORKER_SRC.includes('tenant_resolution_mode: "accepted_quote_seller"'));
  assert.ok(WORKER_SRC.includes("claimedIsCustomerGlobal"));
  assert.ok(WORKER_SRC.includes("_isLimousineGlobalCustomerSession"));
  assert.ok(WORKER_SRC.includes("trusted_source: \"accepted_quote_seller\"") || WORKER_SRC.includes('trusted_source: "accepted_quote_seller"'));
  assert.ok(WORKER_SRC.includes("customerSession: await _loadCustomerSessionFromRequest"));
  assert.ok(!WORKER_SRC.toLowerCase().includes("billit.create") || WORKER_SRC.includes("_prepareLimousineManualBooking"));
});

async function bookAccepted({
  id,
  token = "cus-global-p3l",
  paymentMethod = "qr_code",
  publicPartnerId = PUBLIC_PARTNER,
  billing = null,
  extra = {},
}) {
  const record = quoteRecord({ id });
  const { env, kv } = await setup({ quotes: [record] });
  const acceptanceReference = await sealAccepted(record);
  const res = await worker.fetch(
    jsonReq("/book", {
      token,
      body: bookBody({
        acceptanceReference,
        paymentMethod,
        publicPartnerId,
        billing,
        extra,
      }),
    }),
    env,
    {},
  );
  const body = await res.json();
  return { env, kv, res, body, acceptanceReference };
}

test("3-16) accepted /book QR + billing keeps seller, price, dispatch eligibility", async () => {
  const qr = await bookAccepted({
    id: "limq_p3l_qr",
    paymentMethod: "qr_code",
    billing: BUSINESS_BILLING,
    extra: {
      __booking_id: "2026-08-601",
      __public_booking_reference: "FLX-P3L-601",
      __planning_reference: "PLN-P3L-601",
    },
  });
  assert.equal(qr.res.status, 200, JSON.stringify(qr.body));
  assert.equal(qr.body.ok, true, JSON.stringify(qr.body));
  const qrId = qr.body.booking_id || qr.body.bookingId || "2026-08-601";
  const stored = await qr.kv.get(`booking:${qrId}`, { type: "json" });
  assert.ok(stored, JSON.stringify(qr.body));
  assertSellerAuthority(stored, qr.body);
  assert.equal(String(stored.payment_mode || stored.paymentMode).toLowerCase(), "manual");
  assert.ok(stored.billing_customer_snapshot?.legal_name);
  const keys = [...qr.kv.store.keys()].join(",");
  assert.ok(!keys.toLowerCase().includes("billit_outbox"));
  assert.ok(!keys.toLowerCase().includes("peppol_outbox"));
  const companyList = await worker.fetch(
    jsonReq("/bookings", {
      method: "GET",
      token: "co-p3l",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    qr.env,
    {},
  );
  const listed = await companyList.json();
  const row = (listed.items || []).find((item) =>
    String(item.booking_id || "").includes(String(qrId)),
  );
  assert.ok(row, JSON.stringify(listed));
  const assign = await worker.fetch(
    jsonReq(`/bookings/${qrId}/assign`, {
      admin: true,
      body: { tenant_id: TENANT, company_id: COMPANY, vehicle_id: VEHICLE, driver_id: DRIVER },
    }),
    qr.env,
    {},
  );
  const assigned = await assign.json();
  assert.equal(assign.status, 200, JSON.stringify(assigned));
  const driverList = await worker.fetch(
    jsonReq("/driver/bookings", { method: "GET", token: "drv-p3l" }),
    qr.env,
    {},
  );
  const driverJson = await driverList.json();
  assert.equal(driverList.status, 200, JSON.stringify(driverJson));
  const driverRow = (driverJson.items || []).find((item) =>
    String(item.booking_id || "").includes(String(qrId)),
  );
  assert.ok(driverRow, JSON.stringify(driverJson));

  const manual = await bookAccepted({
    id: "limq_p3l_manual",
    paymentMethod: "in_vehicle_card",
    extra: {
      __booking_id: "2026-08-602",
      __public_booking_reference: "FLX-P3L-602",
      __planning_reference: "PLN-P3L-602",
    },
  });
  assert.equal(manual.res.status, 200, JSON.stringify(manual.body));
  const storedManual = await manual.kv.get(
    `booking:${manual.body.booking_id || "2026-08-602"}`,
    { type: "json" },
  );
  assert.ok(storedManual);
  assertSellerAuthority(storedManual, manual.body);
  assert.equal(storedManual.billing_customer_snapshot, undefined);

  const noPartner = await bookAccepted({
    id: "limq_p3l_nopartner",
    publicPartnerId: "",
    extra: {
      __booking_id: "2026-08-603",
      __public_booking_reference: "FLX-P3L-603",
      __planning_reference: "PLN-P3L-603",
    },
  });
  assert.equal(noPartner.res.status, 200, JSON.stringify(noPartner.body));
  assert.notEqual(noPartner.body.error, "unauthorized_scope");

  const wrong = await bookAccepted({
    id: "limq_p3l_wrong",
    publicPartnerId: OTHER_PUBLIC_PARTNER,
    extra: { __booking_id: "2026-08-604" },
  });
  assert.ok(
    ["unauthorized_scope", "limousine_unavailable", "public partner not found"].includes(wrong.body.error) ||
      wrong.res.status !== 200,
    JSON.stringify(wrong.body),
  );
});
