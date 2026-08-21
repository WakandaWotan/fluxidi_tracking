// P3H — proven live submit root causes.
// Run: node --test workers/booking/modules/limousine_p3h_live_root_causes.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "../fluxidi_booking_worker.js";
import { composeLimousineTotal } from "./limousine_booking.mjs";
import { deriveLimousineAirportPricingFacts } from "./limousine_transfer_endpoint.mjs";

const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3h";
const COMPANY = "company_limo_p3h";
const OTHER_TENANT = "fluxidi_other_p3h";
const OTHER_COMPANY = "company_other_p3h";
const CUSTOMER = "cust_limo_p3h";
const SECRET = "p3h-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const OTHER_PUBLIC_PARTNER = `company:${OTHER_TENANT}:${OTHER_COMPANY}`;
const OFFER = "off_party_hummer";
const HUMMER = "veh_hummer";

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
    async list() {
      return { keys: [...store.keys()].map((name) => ({ name })), list_complete: true };
    },
  };
}

async function seedSessions() {
  const companyHash = await sha256Hex("co-p3h");
  const otherHash = await sha256Hex("co-other-p3h");
  const customerHash = await sha256Hex("cus-p3h");
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
      phone_hash: "phonehash_p3h",
      expires_at: expires,
    },
  };
}

function publishedOffer(overrides = {}) {
  return {
    offer_id: OFFER,
    enabled: true,
    published: true,
    target_type: "vehicle",
    vehicle_id: HUMMER,
    vehicle_ids: [HUMMER, "veh_party"],
    service_class_id: "stretch_limousine",
    journey_types: ["point_to_point", "airport_transfer"],
    price_presentation: "quote_required",
    paid_extras: [],
    source_revision: 4,
    ...overrides,
  };
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

async function setup({ secret = SECRET, offer = publishedOffer() } = {}) {
  const sessions = await seedSessions();
  const seed = {
    ...sessions,
    [`tenant:${TENANT}:company:${COMPANY}:partner:profile:v1`]: {
      partner_profile: {
        partner_id: PUBLIC_PARTNER,
        company_name: "P3H Limo",
        company_id: COMPANY,
        is_active: true,
        bookable: true,
        profile_enabled: true,
        published_at: "2026-08-17T10:00:00Z",
        subscription_status: "active",
        limousine_entitled: true,
        services: ["limousine"],
        vehicles: [
          {
            vehicle_id: HUMMER,
            name: "Hummer white",
            service_category: "limousine",
            service_class: "stretch_limousine",
            is_active: true,
            photo_url: "https://cdn.example/hummer.jpg",
          },
        ],
      },
    },
    [`tenant:${TENANT}:company:${COMPANY}:pricing:v1`]: {
      pricing_profile: { limousine: { offers: [offer] } },
    },
    [`tenant:${TENANT}:company:${COMPANY}:fleet:vehicles:v1`]: {
      vehicles: [{ vehicle_id: HUMMER, is_active: true, active: true }],
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
  const extra = secret == null ? { LIMOUSINE_ACCEPTANCE_SECRET: undefined } : { LIMOUSINE_ACCEPTANCE_SECRET: secret };
  if (secret == null) delete extra.LIMOUSINE_ACCEPTANCE_SECRET;
  return { kv, env: envOf(kv, secret == null ? { LIMOUSINE_ACCEPTANCE_SECRET: "" } : extra) };
}

function jsonReq(path, { method = "POST", token = null, body = null, query = "" } = {}) {
  const headers = { "content-type": "application/json" };
  if (token) headers.authorization = `Bearer ${token}`;
  return new Request(`https://booking.internal${path}${query}`, {
    method,
    headers,
    body: body == null ? undefined : JSON.stringify(body),
  });
}

function quoteBody(extra = {}) {
  return {
    public_partner_id: PUBLIC_PARTNER,
    offer_id: OFFER,
    vehicle_id: HUMMER,
    journey_type: "point_to_point",
    from: "Korenmarkt 1, Gent",
    to: "Graslei 10, Gent",
    scheduled_pickup_iso: "2026-09-01T10:00:00.000Z",
    locale: "nl",
    ...extra,
  };
}

test("missing status secret is a visible 500 and writes no half record", async () => {
  const { kv, env } = await setup({ secret: null });
  const res = await worker.fetch(
    jsonReq("/limousine/quote-requests", { token: "cus-p3h", body: quoteBody() }),
    env,
    {},
  );
  const json = await res.json();
  assert.equal(res.status, 500, JSON.stringify(json));
  assert.equal(json.ok, false);
  assert.equal(json.error, "status_secret_missing");
  assert.equal(json.stage, "status_sign");
  assert.match(String(json.request_id || ""), /^lsub_/);
  assert.equal(json.quote_request_id, undefined);
  const quoteKeys = [...kv.store.keys()].filter((key) => key.includes("limousine_quote"));
  assert.deepEqual(quoteKeys, []);
});

test("configured status secret persists primary + inbox and retries stay idempotent", async () => {
  const { env } = await setup();
  const created = await worker.fetch(
    jsonReq("/limousine/quote-requests", { token: "cus-p3h", body: quoteBody() }),
    env,
    {},
  );
  const createdJson = await created.json();
  assert.equal(created.status, 200, JSON.stringify(createdJson));
  assert.equal(createdJson.ok, true);
  assert.equal(createdJson.quote_request_id, createdJson.quote_request.quote_request_id);
  assert.equal(createdJson.quote_request.vehicle_id, HUMMER);
  const quoteId = createdJson.quote_request_id;

  const retry = await worker.fetch(
    jsonReq("/limousine/quote-requests", { token: "cus-p3h", body: quoteBody() }),
    env,
    {},
  );
  const retryJson = await retry.json();
  assert.equal(retry.status, 200);
  assert.equal(retryJson.idempotent, true);
  assert.equal(retryJson.quote_request_id, quoteId);

  const listed = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-p3h",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    env,
    {},
  );
  const listedJson = await listed.json();
  assert.equal(listed.status, 200, JSON.stringify(listedJson));
  assert.equal(listedJson.items?.[0]?.quote_request_id, quoteId);
  assert.equal(listedJson.items?.[0]?.vehicle_id, HUMMER);
  const snapshotName =
    listedJson.items?.[0]?.vehicle_snapshot?.public_name ||
    listedJson.items?.[0]?.vehicle_snapshot?.name ||
    "";
  assert.match(String(snapshotName || listedJson.items?.[0]?.vehicle_id || ""), /hummer|veh_hummer/i);

  const other = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-other-p3h",
      query: `?tenant_id=${OTHER_TENANT}&company_id=${OTHER_COMPANY}`,
    }),
    env,
    {},
  );
  const otherJson = await other.json();
  const otherItems = Array.isArray(otherJson.items) ? otherJson.items : [];
  assert.equal(otherItems.some((item) => item.quote_request_id === quoteId), false);
});

test("wrong vehicle or journey stays rejected", async () => {
  const { env } = await setup();
  const wrongVehicle = await worker.fetch(
    jsonReq("/limousine/quote-requests", {
      token: "cus-p3h",
      body: quoteBody({ vehicle_id: "vh_other" }),
    }),
    env,
    {},
  );
  const wrongVehicleJson = await wrongVehicle.json();
  assert.equal(wrongVehicle.status, 400);
  assert.equal(wrongVehicleJson.error, "vehicle_scope_mismatch");

  const wrongJourney = await worker.fetch(
    jsonReq("/limousine/quote-requests", {
      token: "cus-p3h",
      body: quoteBody({ journey_type: "hourly_package" }),
    }),
    env,
    {},
  );
  const wrongJourneyJson = await wrongJourney.json();
  assert.equal(wrongJourney.status, 400);
  assert.equal(wrongJourneyJson.error, "journey_type_not_allowed");
});

test("live-shaped airport book facts resolve IATA from the endpoint", () => {
  const facts = deriveLimousineAirportPricingFacts({
    journey_type: "airport_transfer",
    to_endpoint: {
      kind: "airport",
      display_name: "Brussels Airport (BRU)",
      formatted_address: "Brussels Airport",
      airport_name: "Brussels Airport",
      iata_code: "BRU",
      country_code: "BE",
      latitude: 50.901,
      longitude: 4.484,
    },
    from_endpoint: {
      kind: "address",
      display_name: "Oudenaarde",
      formatted_address: "Oudenaarde",
      latitude: 50.843,
      longitude: 3.604,
    },
  });
  assert.equal(facts.airport_iata, "BRU");
  assert.equal(facts.direction, "to_airport");

  const total = composeLimousineTotal({
    section: {
      enabled: true,
      currency: "EUR",
      offers: [
        {
          offer_id: "offer_1787077871217",
          enabled: true,
          published: true,
          target_type: "vehicle",
          vehicle_id: "vh_1787076028764",
          vehicle_ids: ["vh_1787076028764"],
          service_class_id: "stretch_limousine",
          journey_types: ["airport_transfer"],
          price_presentation: "exact_fixed",
          currency: "EUR",
          fixed_rules: [
            {
              rule_id: "r_bru",
              enabled: true,
              journey_type: "airport_transfer",
              airport_iata: "BRU",
              direction: "to_airport",
              amount_cents: 18900,
              currency: "EUR",
            },
          ],
        },
      ],
    },
    offerId: "offer_1787077871217",
    request: {
      vehicle_id: "vh_1787076028764",
      journey_type: "airport_transfer",
      currency: "EUR",
      to_endpoint: {
        kind: "airport",
        display_name: "Brussels Airport (BRU)",
        formatted_address: "Brussels Airport",
        airport_name: "Brussels Airport",
        iata_code: "BRU",
        country_code: "BE",
        latitude: 50.901,
        longitude: 4.484,
      },
    },
    routes: { main: { distance_km: 70, duration_min: 55 } },
  });
  assert.equal(total.ok, true, JSON.stringify(total));
  assert.equal(total.total_incl_vat_cents, 18900);
});
