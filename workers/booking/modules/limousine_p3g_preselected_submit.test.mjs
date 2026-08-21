// P3G — locked vehicle_id + public snapshot persist/inbox/idempotency.
// Run: node --test workers/booking/modules/limousine_p3g_preselected_submit.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "../fluxidi_booking_worker.js";
import {
  buildLimousinePublicVehicleSnapshot,
  validateLimousineQuoteRequest,
} from "./limousine_manual_quote.mjs";

const ADMIN = "test-admin-token";
const TENANT = "fluxidi_limo_p3g";
const COMPANY = "company_limo_p3g";
const OTHER_TENANT = "fluxidi_other_p3g";
const OTHER_COMPANY = "company_other_p3g";
const CUSTOMER = "cust_limo_p3g";
const SECRET = "p3g-acceptance-secret-not-production";
const PUBLIC_PARTNER = `company:${TENANT}:${COMPANY}`;
const OTHER_PUBLIC_PARTNER = `company:${OTHER_TENANT}:${OTHER_COMPANY}`;
const OFFER = "off_party_hummer";
const HUMMER = "veh_hummer";
const PARTY = "veh_party";

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
  const companyHash = await sha256Hex("co-p3g");
  const otherHash = await sha256Hex("co-other-p3g");
  const customerHash = await sha256Hex("cus-p3g");
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
      phone_hash: "phonehash_p3g",
      expires_at: expires,
    },
  };
}

function vehicles() {
  return [
    {
      vehicle_id: PARTY,
      name: "Party Limo",
      service_category: "limousine",
      service_class: "stretch_limousine",
      is_active: true,
      photo_url: "https://cdn.example/party.jpg",
      passenger_capacity: 10,
      luggage_capacity: 4,
    },
    {
      vehicle_id: HUMMER,
      name: "Hummer white",
      service_category: "limousine",
      service_class: "stretch_limousine",
      is_active: true,
      photo_url: "https://cdn.example/hummer.jpg",
      passenger_capacity: 8,
      luggage_capacity: 3,
    },
  ];
}

function eligibleProfile() {
  return {
    partner_id: PUBLIC_PARTNER,
    company_name: "P3G Limo",
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

function publishedOffer(overrides = {}) {
  return {
    offer_id: OFFER,
    enabled: true,
    published: true,
    target_type: "vehicle",
    vehicle_ids: [PARTY, HUMMER],
    vehicles: vehicles(),
    service_class_id: "stretch_limousine",
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
      vehicles: vehicles().map((item) => ({ ...item, active: true })),
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
    vehicle_id: HUMMER,
    journey_type: "point_to_point",
    from: "Korenmarkt 1, Gent",
    to: "Graslei 10, Gent",
    scheduled_pickup_iso: "2026-09-01T10:00:00.000Z",
    locale: "nl",
    ...extra,
  };
}

test("p3g snapshot prefers the selected Hummer on a two-vehicle offer", () => {
  const snapshot = buildLimousinePublicVehicleSnapshot({
    offer: publishedOffer(),
    vehicleId: HUMMER,
    publishedVehicles: vehicles(),
  });
  assert.equal(snapshot.vehicle_id, HUMMER);
  assert.equal(snapshot.public_name, "Hummer white");
  assert.equal(snapshot.photo_url, "https://cdn.example/hummer.jpg");
  const validated = validateLimousineQuoteRequest(quoteBody(), {
    eligible: true,
    offer: publishedOffer(),
    gateEnabled: true,
    publishedVehicles: vehicles(),
  });
  assert.equal(validated.ok, true, JSON.stringify(validated));
  assert.equal(validated.request.vehicle_id, HUMMER);
  assert.equal(validated.request.vehicle_snapshot.public_name, "Hummer white");
});

test("p3g persist + inbox keep Hummer white and reject a swapped vehicle", async () => {
  const { kv, env } = await setup();
  const created = await worker.fetch(
    jsonReq("/limousine/quote-requests", { token: "cus-p3g", body: quoteBody() }),
    env,
    {},
  );
  const createdJson = await created.json();
  assert.equal(created.status, 200, JSON.stringify(createdJson));
  assert.equal(createdJson.quote_request.vehicle_id, HUMMER);
  assert.equal(createdJson.quote_request.vehicle_snapshot.public_name, "Hummer white");
  assert.equal(createdJson.quote_request.vehicle_snapshot.photo_url, "https://cdn.example/hummer.jpg");
  const quoteId = createdJson.quote_request.quote_request_id;

  const swapped = await worker.fetch(
    jsonReq("/limousine/quote-requests", {
      token: "cus-p3g",
      body: quoteBody({ vehicle_id: "veh_other" }),
    }),
    env,
    {},
  );
  const swappedJson = await swapped.json();
  assert.equal(swapped.status, 400, JSON.stringify(swappedJson));
  assert.equal(swappedJson.error, "vehicle_scope_mismatch");

  const retry = await worker.fetch(
    jsonReq("/limousine/quote-requests", { token: "cus-p3g", body: quoteBody() }),
    env,
    {},
  );
  const retryJson = await retry.json();
  assert.equal(retry.status, 200, JSON.stringify(retryJson));
  assert.equal(retryJson.idempotent, true);
  assert.equal(retryJson.quote_request.quote_request_id, quoteId);
  assert.equal(retryJson.quote_request.vehicle_id, HUMMER);

  const listed = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-p3g",
      query: `?tenant_id=${TENANT}&company_id=${COMPANY}`,
    }),
    env,
    {},
  );
  const listedJson = await listed.json();
  assert.equal(listed.status, 200, JSON.stringify(listedJson));
  assert.equal(listedJson.items?.[0]?.quote_request_id, quoteId);
  assert.equal(listedJson.items?.[0]?.vehicle_id, HUMMER);
  assert.equal(listedJson.items?.[0]?.vehicle_snapshot?.public_name, "Hummer white");

  const other = await worker.fetch(
    jsonReq("/admin/limousine/quote-requests", {
      method: "GET",
      token: "co-other-p3g",
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
