// P3O — accepted limousine pax authority, checkout fields, frozen cancellation.
// Run: node --test workers/booking/modules/limousine_p3o_core.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import worker from "../fluxidi_booking_worker.js";
import {
  buildLimousineAcceptanceBinding,
  publicLimousinePartnerId,
} from "./limousine_manual_quote.mjs";
import { sealLimousineAcceptance } from "./limousine_acceptance_token.mjs";
import {
  attachLimousineQuotationSnapshot,
  buildLimousineAcceptanceBindingFromSnapshot,
  buildLimousineQuotationSnapshotFromRecord,
} from "./limousine_quotation_snapshot.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const WORKER_SRC = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3o";
const COMPANY = "company_limo_p3o";
const CUSTOMER = "cust_limo_p3o";
const DRIVER = "D-limo-p3o";
const VEHICLE = "veh_limo_p3o";
const SECRET = "p3o-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const TOTAL_CENTS = 106000;
const TERMS = {
  terms_revision: 4,
  cancellation_deadline_hours: 24,
  cancellation_penalty_percent: 25,
  waiting_time_included_minutes: 15,
  waiting_time_overage_cents_per_minute: 100,
  no_show_penalty_percent: 100,
  overtime_cents_per_hour: 9000,
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
      passenger_capacity: 16,
      luggage_capacity: 8,
    },
  ];
}

function eligibleProfile() {
  return {
    partner_id: PUBLIC_PARTNER,
    company_name: "P3O Limo",
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
  const companyHash = await sha256Hex("co-p3o");
  const customerHash = await sha256Hex("cus-p3o");
  const globalHash = await sha256Hex("cus-global-p3o");
  const driverHash = await sha256Hex("drv-p3o");
  const expires = new Date(Date.now() + 3600_000).toISOString();
  return {
    [`company_admin:session:${companyHash}:v1`]: {
      role: "company_admin",
      tenant_id: TENANT,
      company_id: COMPANY,
      expires_at: expires,
    },
    [`customer:session:${customerHash}:v1`]: {
      role: "customer",
      purpose: "customer_session",
      tenant_id: TENANT,
      company_id: COMPANY,
      customer_id: CUSTOMER,
      phone_hash: "phonehash_p3o",
      expires_at: expires,
    },
    [`customer:session:${globalHash}:v1`]: {
      role: "customer",
      purpose: "customer_session",
      tenant_id: "global",
      company_id: "global",
      customer_id: CUSTOMER,
      phone_hash: "phonehash_p3o_global",
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

function quoteRecord({ id, pax = 8, bags = 2, pickupIso = "2026-09-30T10:00:00.000Z" } = {}) {
  const now = new Date().toISOString();
  return {
    quote_request_id: id,
    tenant_id: TENANT,
    company_id: COMPANY,
    public_partner_id: PUBLIC_PARTNER,
    state: "accepted",
    revision: 6,
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
      scheduled_pickup_iso: pickupIso,
      pax,
      bags,
      locale: "nl",
      service_type: "limousine",
      pricing_mode: "quote_required",
      vehicle_snapshot: { vehicle_id: VEHICLE, public_name: "Party Limo" },
    },
    quote: {
      total_incl_vat_cents: TOTAL_CENTS,
      currency: "EUR",
      vat_rate: 0.06,
      vat_treatment: "incl",
      terms: TERMS,
      terms_revision: 4,
      expires_at: "2099-01-01T00:00:00Z",
      quoted_at: now,
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

async function setup({ quotes = [], extra = {} } = {}) {
  const sessions = await seedSessions();
  const seed = {
    ...sessions,
    ...extra,
    [`tenant:${TENANT}:company:${COMPANY}:partner:profile:v1`]: {
      partner_profile: eligibleProfile(),
    },
    [`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`]: {
      vehicles: vehicles(),
    },
    [`tenant:${TENANT}:company:${COMPANY}:business_profile:v1`]: {
      business_profile: {
        trading_name: "P3O Limo",
        legal_name: "P3O Limo BV",
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
      ],
    },
  };
  for (const quote of quotes) {
    seed[`limousine_quote_record:${quote.quote_request_id}`] = quote;
  }
  const kv = makeKV(seed);
  return { kv, env: envOf(kv) };
}

async function withSnapshot(record) {
  const snap = await buildLimousineQuotationSnapshotFromRecord({ record });
  return attachLimousineQuotationSnapshot(record, snap).record;
}

async function bookAccepted({
  id,
  pax = 8,
  bags = 2,
  pickupIso = "2026-09-30T10:00:00.000Z",
  paymentMode = "manual",
  paymentProvider = "manual",
  paymentMethod = "qr_code",
  extra = {},
  omitServiceTokens = false,
  payloadPax = null,
  bookingId = `2026-09-7${String(id).slice(-2)}`,
}) {
  let record = quoteRecord({ id, pax, bags, pickupIso });
  record = await withSnapshot(record);
  const { env, kv } = await setup({ quotes: [record] });
  const sealed = await sealLimousineAcceptance({
    secret: SECRET,
    binding: buildLimousineAcceptanceBindingFromSnapshot(
      record,
      record.quotation_snapshots[String(record.quotation_revision)],
    ),
    ttlMinutes: 120,
  });
  assert.equal(sealed.ok, true, JSON.stringify(sealed));
  const body = {
    public_partner_id: PUBLIC_PARTNER,
    limousine_acceptance_reference: sealed.reference,
    from: "Gent",
    to: "Brussel",
    pickup_iso: pickupIso,
    pax: payloadPax == null ? pax : payloadPax,
    bags,
    payment_mode: paymentMode,
    payment_provider: paymentProvider,
    payment_method: paymentMethod,
    customer_id: CUSTOMER,
    customer: { name: "Ada", phone: "+32470000000", email: "ada@example.test" },
    __booking_id: bookingId,
    __public_booking_reference: `FLX-${bookingId}`,
    __planning_reference: `PLN-${bookingId}`,
    ...extra,
  };
  if (!omitServiceTokens) {
    body.service = "limousine";
    body.service_category = "limousine";
  }
  const res = await worker.fetch(
    jsonReq("/book", { token: "cus-global-p3o", body }),
    env,
    {},
  );
  const json = await res.json();
  const storedId = json.booking_id || extra.__booking_id || bookingId;
  const stored = storedId ? await kv.get(`booking:${storedId}`, { type: "json" }) : null;
  return { env, kv, res, body: json, stored, record };
}

test("worker still clamps taxi pax 1..3 and limousine 1..16", () => {
  assert.match(WORKER_SRC, /clampInt\(payload\?\.pax, 1, 3\)/);
  assert.match(WORKER_SRC, /clampInt\(payload\?\.pax, 1, 16\)/);
  assert.match(WORKER_SRC, /limousine_acceptance_reference/);
  assert.ok(WORKER_SRC.includes("_freezeLimousineAcceptedRideFacts"));
  assert.ok(WORKER_SRC.includes("_readFrozenLimousineCancellationTerms"));
  assert.ok(!WORKER_SRC.includes("billit.createInvoice"));
});

test("accepted 8/2 without service tokens stays 8/2 and freezes 24/25/100", async () => {
  const out = await bookAccepted({
    id: "limq_p3o_pax",
    omitServiceTokens: true,
    payloadPax: 3,
    extra: {
      __booking_id: "2026-09-701",
      __public_booking_reference: "FLX-P3O-701",
      __planning_reference: "PLN-P3O-701",
    },
  });
  assert.equal(out.res.status, 200, JSON.stringify(out.body));
  assert.equal(out.body.ok, true, JSON.stringify(out.body));
  assert.ok(out.stored);
  assert.equal(Number(out.stored.booking?.pax ?? out.stored.pax), 8);
  assert.equal(Number(out.stored.booking?.bags ?? out.stored.bags), 2);
  assert.equal(out.stored.service_type || out.stored.serviceType, "limousine");
  const accepted = out.stored.quote?.limousine_accepted_price || out.stored.limousine_accepted_price;
  assert.equal(accepted.pax, 8);
  assert.equal(accepted.bags, 2);
  assert.equal(accepted.cancellation_deadline_hours, 24);
  assert.equal(accepted.cancellation_penalty_percent, 25);
  assert.equal(accepted.no_show_penalty_percent, 100);
  assert.equal(accepted.cancellation_canonical_gross_cents, TOTAL_CENTS);
  assert.equal(accepted.cancellation_terms_source, "frozen_quotation");
  assert.equal(out.stored.cancellation_deadline_hours, 24);
  assert.equal(out.stored.cancellation_penalty_percent, 25);
  assert.equal(out.stored.payment_method || out.stored.paymentMethod, "qr_code");
  assert.equal(String(out.stored.payment_mode || "").toLowerCase(), "manual");
});

test("pax 1 and pax 16 survive accepted book", async () => {
  for (const pax of [1, 16]) {
    const out = await bookAccepted({
      id: `limq_p3o_pax_${pax}`,
      pax,
      extra: {
        __booking_id: `2026-09-7${10 + pax}`,
        __public_booking_reference: `FLX-P3O-${pax}`,
        __planning_reference: `PLN-P3O-${pax}`,
      },
    });
    assert.equal(out.res.status, 200, JSON.stringify(out.body));
    assert.equal(Number(out.stored.booking?.pax ?? out.stored.pax), pax);
  }
});

test("manual QR and pay-in-car stay manual with persisted payment_method", async () => {
  const qr = await bookAccepted({
    id: "limq_p3o_qr",
    paymentMethod: "qr_code",
    extra: { __booking_id: "2026-09-720" },
  });
  assert.equal(qr.res.status, 200, JSON.stringify(qr.body));
  assert.equal(qr.stored.payment_mode, "manual");
  assert.equal(qr.stored.payment_method, "qr_code");
  assert.ok(!qr.body.checkout_url);

  const car = await bookAccepted({
    id: "limq_p3o_car",
    paymentMethod: "in_vehicle_card",
    extra: { __booking_id: "2026-09-721" },
  });
  assert.equal(car.res.status, 200, JSON.stringify(car.body));
  assert.equal(car.stored.payment_mode, "manual");
  assert.equal(car.stored.payment_method, "in_vehicle_card");
});

test("Mollie checkout methods fail safely when checkout cannot be created", async () => {
  for (const [method, mollie] of [
    ["bancontact", "bancontact"],
    ["kbc_cbc", "kbc"],
    ["belfius", "belfius"],
    ["card_payment", "creditcard"],
    ["paypal", "paypal"],
    ["google_pay", "googlepay"],
  ]) {
    const out = await bookAccepted({
      id: `limq_p3o_${method}`,
      paymentMode: "mollie",
      paymentProvider: "mollie",
      paymentMethod: method,
      extra: {
        mollie_method: mollie,
        __booking_id: `2026-09-73${method.length}`,
      },
    });
    assert.notEqual(out.body.ok, true, `${method} ${JSON.stringify(out.body)}`);
    assert.ok(
      ["payment_checkout_unavailable", "mollie_unavailable", "company_mollie_payments_not_enabled", "payment_method_disabled_for_company"].includes(out.body.error) ||
        out.res.status >= 400,
      JSON.stringify(out.body),
    );
    if (out.stored) {
      assert.notEqual(String(out.stored.payment_mode || "").toLowerCase(), "manual");
    }
  }
});

test("before deadline cancel is 0%; after deadline keeps frozen 25% even if company cutoff changes", async () => {
  const far = await bookAccepted({
    id: "limq_p3o_cx_far",
    pickupIso: "2026-12-01T10:00:00.000Z",
    extra: { __booking_id: "2026-09-740" },
  });
  assert.equal(far.res.status, 200, JSON.stringify(far.body));
  await far.kv.put(`tenant:${TENANT}:company:${COMPANY}:cancellation_policy:v1`, {
    cancellation_policy_profile: {
      allow_customer_online_cancellation: true,
      taxi_cutoff_minutes: 20000,
      airport_cutoff_minutes: 20000,
      business_cutoff_minutes: 20000,
    },
  });
  const farCancel = await worker.fetch(
    jsonReq("/track/booking/status", {
      token: "cus-p3o",
      body: {
        booking_id: "2026-09-740",
        status: "CANCELLED",
        actor_role: "customer",
        tenant_id: TENANT,
        company_id: COMPANY,
      },
    }),
    far.env,
    {},
  );
  const farJson = await farCancel.json();
  assert.equal(farCancel.status, 200, JSON.stringify(farJson));
  const farStored = await far.kv.get("booking:2026-09-740", { type: "json" });
  assert.equal(farStored.applicable_penalty_percent, 0);
  assert.equal(farStored.cancellation_penalty_cents, 0);

  const near = await bookAccepted({
    id: "limq_p3o_cx_near",
    pickupIso: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    extra: { __booking_id: "2026-09-741" },
  });
  assert.equal(near.res.status, 200, JSON.stringify(near.body));
  await near.kv.put(`tenant:${TENANT}:company:${COMPANY}:cancellation_policy:v1`, {
    cancellation_policy_profile: {
      allow_customer_online_cancellation: true,
      taxi_cutoff_minutes: 20000,
      airport_cutoff_minutes: 20000,
      business_cutoff_minutes: 20000,
    },
  });
  const nearCancel = await worker.fetch(
    jsonReq("/track/booking/status", {
      token: "cus-p3o",
      body: {
        booking_id: "2026-09-741",
        status: "CANCELLED",
        actor_role: "customer",
        tenant_id: TENANT,
        company_id: COMPANY,
      },
    }),
    near.env,
    {},
  );
  const nearJson = await nearCancel.json();
  assert.equal(nearCancel.status, 200, JSON.stringify(nearJson));
  const nearStored = await near.kv.get("booking:2026-09-741", { type: "json" });
  assert.equal(nearStored.cancellation_deadline_hours, 24);
  assert.equal(nearStored.applicable_penalty_percent, 25);
  assert.equal(nearStored.cancellation_penalty_cents, 26500);
  assert.equal(nearStored.outstanding_cancellation_cents, 26500);
  assert.equal(nearStored.refund_required, false);
});

test("paid frozen cancel uses existing refund_required fields, not a new engine", async () => {
  const out = await bookAccepted({
    id: "limq_p3o_paid",
    pickupIso: new Date(Date.now() + 60 * 60 * 1000).toISOString(),
    extra: { __booking_id: "2026-09-742" },
  });
  const rec = out.stored;
  rec.payment_status = "paid";
  rec.paymentStatus = "paid";
  rec.booking.payment_status = "paid";
  rec.paid_amount_cents = TOTAL_CENTS;
  await out.kv.put("booking:2026-09-742", rec);
  const cancel = await worker.fetch(
    jsonReq("/track/booking/status", {
      token: "cus-p3o",
      body: {
        booking_id: "2026-09-742",
        status: "CANCELLED",
        actor_role: "customer",
        tenant_id: TENANT,
        company_id: COMPANY,
      },
    }),
    out.env,
    {},
  );
  const json = await cancel.json();
  assert.equal(cancel.status, 200, JSON.stringify(json));
  const stored = await out.kv.get("booking:2026-09-742", { type: "json" });
  assert.equal(stored.refund_required, true);
  assert.equal(stored.refund_amount_cents, 79500);
  assert.equal(stored.cancellation_penalty_cents, 26500);
  const keys = [...out.kv.store.keys()].join(",");
  assert.ok(!keys.toLowerCase().includes("billit_outbox"));
});

test("legacy booking without frozen terms still uses the taxi cutoff", async () => {
  const { env, kv } = await setup();
  const pickup = new Date(Date.now() + 30 * 60 * 1000).toISOString();
  await kv.put("booking:2026-09-799", {
    tenant_id: TENANT,
    company_id: COMPANY,
    status: "BOOKED",
    stage: "BOOKED",
    service_type: "taxi",
    payment_status: "unpaid",
    pickupStartIso: pickup,
    customer_id: CUSTOMER,
    customerId: CUSTOMER,
    custPhone: "+32470000000",
    booking: {
      pickupStartIso: pickup,
      service_type: "taxi",
      customer_id: CUSTOMER,
      customerId: CUSTOMER,
      custPhone: "+32470000000",
    },
  });
  const cancel = await worker.fetch(
    jsonReq("/track/booking/status", {
      token: "cus-p3o",
      body: {
        booking_id: "2026-09-799",
        status: "CANCELLED",
        actor_role: "customer",
        tenant_id: TENANT,
        company_id: COMPANY,
      },
    }),
    env,
    {},
  );
  const json = await cancel.json();
  assert.equal(cancel.status, 409, JSON.stringify(json));
  assert.equal(json.error, "cancellation_window_closed");
});

test("public partner helper is unused for this suite but keeps the import live", () => {
  assert.equal(publicLimousinePartnerId({ tenant_id: TENANT, company_id: COMPANY }), PUBLIC_PARTNER);
  assert.ok(typeof buildLimousineAcceptanceBinding === "function");
});
