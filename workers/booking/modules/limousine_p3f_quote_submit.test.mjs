// P3F — quote submit persist + real company inbox read.
// Run: node --test workers/booking/modules/limousine_p3f_quote_submit.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "../fluxidi_booking_worker.js";

const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3f";
const COMPANY = "company_limo_p3f";
const OTHER_TENANT = "fluxidi_other_p3f";
const OTHER_COMPANY = "company_other_p3f";
const CUSTOMER = "cust_limo_p3f";
const SECRET = "p3f-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const OTHER_PUBLIC_PARTNER = `company:${OTHER_TENANT}:${OTHER_COMPANY}`;
const OFFER = "off_p3f";
const VEHICLE = "veh_p3f";

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
  const companyHash = await sha256Hex("co-p3f");
  const otherHash = await sha256Hex("co-other-p3f");
  const customerHash = await sha256Hex("cus-p3f");
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
      phone_hash: "phonehash_p3f",
      expires_at: expires,
    },
  };
}

function eligibleProfile() {
  return {
    partner_id: PUBLIC_PARTNER,
    company_name: "P3F Limo",
    company_id: COMPANY,
    is_active: true,
    bookable: true,
    profile_enabled: true,
    published_at: "2026-08-17T10:00:00Z",
    subscription_status: "active",
    limousine_entitled: true,
    services: ["limousine"],
    coverage: { city: "Gent" },
    vehicles: [
      {
        vehicle_id: VEHICLE,
        name: "Executive",
        service_category: "limousine",
        service_class: "executive_sedan",
        is_active: true,
        photo_url: "https://cdn.example/v1.jpg",
      },
    ],
  };
}

function publishedOffer(overrides = {}) {
  return {
    offer_id: OFFER,
    enabled: true,
    published: true,
    target_type: "vehicle",
    vehicle_id: VEHICLE,
    vehicle_ids: [VEHICLE],
    service_class_id: "executive_sedan",
    journey_types: ["point_to_point"],
    price_presentation: "quote_required",
    paid_extras: [],
    source_revision: 4,
    ...overrides,
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

async function setup({ offer = publishedOffer() } = {}) {
  const sessions = await seedSessions();
  const seed = {
    ...sessions,
    [`tenant:${TENANT}:company:${COMPANY}:partner:profile:v1`]: {
      partner_profile: eligibleProfile(),
    },
    [`tenant:${TENANT}:company:${COMPANY}:pricing:v1`]: {
      pricing_profile: {
        limousine: {
          offers: [offer],
        },
      },
    },
    [`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`]: {
      vehicles: [{ vehicle_id: VEHICLE, is_active: true, active: true }],
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
  const kv = makeKV(seed);
  return { kv, env: envOf(kv) };
}

function quoteBody(extra = {}) {
  return {
    public_partner_id: PUBLIC_PARTNER,
    offer_id: OFFER,
    vehicle_id: VEHICLE,
    journey_type: "point_to_point",
    from: "Korenmarkt 1, Gent",
    to: "Graslei 10, Gent",
    scheduled_pickup_iso: "2026-09-01T10:00:00.000Z",
    locale: "nl",
    ...extra,
  };
}

test("p3f persist + inbox: one request is tenant/company scoped and listed", async () => {
  const { kv, env } = await setup();
  const created = await worker.fetch(
    jsonReq("/limousine/quote-requests", { token: "cus-p3f", body: quoteBody() }),
    env,
    {},
  );
  const createdJson = await created.json();
  assert.equal(created.status, 200, JSON.stringify(createdJson));
  assert.equal(createdJson.ok, true);
  assert.ok(createdJson.quote_request?.quote_request_id);
  assert.equal(createdJson.quote_request.service_type, "limousine");
  const quoteId = createdJson.quote_request.quote_request_id;
  assert.match(quoteId, /^limq_/);

  const retry = await worker.fetch(
    jsonReq("/limousine/quote-requests", { token: "cus-p3f", body: quoteBody() }),
    env,
    {},
  );
  const retryJson = await retry.json();
  assert.equal(retry.status, 200, JSON.stringify(retryJson));
  assert.equal(retryJson.idempotent, true);
  assert.equal(retryJson.quote_request.quote_request_id, quoteId);

  const listed = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-p3f",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    env,
    {},
  );
  const listedJson = await listed.json();
  assert.equal(listed.status, 200, JSON.stringify(listedJson));
  assert.equal(listedJson.items?.[0]?.quote_request_id, quoteId);
  assert.equal(listedJson.items?.[0]?.service_type, "limousine");

  const other = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-other-p3f",
      query: `?tenant_id=${OTHER_TENANT}&company_id=${OTHER_COMPANY}`,
    }),
    env,
    {},
  );
  const otherJson = await other.json();
  const otherItems = Array.isArray(otherJson.items) ? otherJson.items : [];
  assert.equal(
    otherItems.some((item) => item.quote_request_id === quoteId),
    false,
  );

  const bookingKeys = [...kv.store.keys()].filter((key) =>
    key.startsWith("booking:") || key.includes(":bookings:"),
  );
  assert.deepEqual(bookingKeys, []);
});

test("p3f rejects wrong vehicle/journey and unpublished drafts", async () => {
  const { env } = await setup();
  const wrongVehicle = await worker.fetch(
    jsonReq("/limousine/quote-requests", {
      token: "cus-p3f",
      body: quoteBody({ vehicle_id: "veh_other" }),
    }),
    env,
    {},
  );
  const wrongVehicleJson = await wrongVehicle.json();
  assert.equal(wrongVehicle.status, 400, JSON.stringify(wrongVehicleJson));
  assert.equal(wrongVehicleJson.error, "vehicle_scope_mismatch");

  const wrongJourney = await worker.fetch(
    jsonReq("/limousine/quote-requests", {
      token: "cus-p3f",
      body: quoteBody({ journey_type: "airport_transfer" }),
    }),
    env,
    {},
  );
  const wrongJourneyJson = await wrongJourney.json();
  assert.equal(wrongJourney.status, 400, JSON.stringify(wrongJourneyJson));
  assert.equal(wrongJourneyJson.error, "journey_type_not_allowed");

  const { env: draftEnv } = await setup({
    offer: publishedOffer({ published: false }),
  });
  const draft = await worker.fetch(
    jsonReq("/limousine/quote-requests", {
      token: "cus-p3f",
      body: quoteBody(),
    }),
    draftEnv,
    {},
  );
  const draftJson = await draft.json();
  assert.equal(draft.status, 400, JSON.stringify(draftJson));
  assert.equal(draftJson.error, "offer_unpublished");
});

test("p3f taxi/airport/street symbols stay outside quote persist", async () => {
  const { readFileSync } = await import("node:fs");
  const { fileURLToPath } = await import("node:url");
  const { dirname, join } = await import("node:path");
  const here = dirname(fileURLToPath(import.meta.url));
  const src = readFileSync(join(here, "../fluxidi_booking_worker.js"), "utf8");
  const quoteStart = src.indexOf('"/limousine/quote-requests" && request.method === "POST"');
  const quoteEnd = src.indexOf('"/admin/limousine/quote-requests/respond"');
  const slice = src.slice(quoteStart, quoteEnd);
  assert.ok(!slice.includes("mollie"));
  assert.ok(!slice.includes("billit"));
  assert.ok(!slice.includes("chiron"));
  assert.ok(src.includes("function calcPrice({"));
  assert.ok(src.includes("function resolveAirportFixedFare("));
});
