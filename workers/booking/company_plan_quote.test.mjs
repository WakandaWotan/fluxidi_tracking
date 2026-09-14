import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  buildCompanyAgendaQuoteRequestBody,
  publicCompanyAgendaQuote,
} from "./modules/company_plan_quote.mjs";
import { normalizeCompanyFixedPricesDocument } from "./modules/company_fixed_prices.mjs";
import { companyFixedPricesKey } from "./modules/company_fixed_prices.mjs";

const ADMIN = "p0-agenda-admin";
const TENANT_A = "TA";
const COMPANY_A = "CA";

function countingKV(seed = {}) {
  const store = new Map();
  for (const [key, value] of Object.entries(seed)) {
    store.set(key, typeof value === "string" ? value : JSON.stringify(value));
  }
  return {
    store,
    async get(key, opts) {
      if (!store.has(key)) return null;
      const raw = store.get(key);
      const asJson = opts === "json" || (opts && opts.type === "json");
      if (asJson) {
        try {
          return typeof raw === "string" ? JSON.parse(raw) : raw;
        } catch {
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
      return { keys: [], list_complete: true };
    },
  };
}

function envWith(kv) {
  return { ADMIN_TOKEN: ADMIN, BOOKING_KV: kv, MAPBOX_TOKEN: "test-mapbox" };
}

function mapboxFetch({
  distance = 34200,
  duration = 1740,
  failFirst = 0,
  failCode = "NoSegment",
  onDirections,
} = {}) {
  let directions = 0;
  return async (input) => {
    const url = String(input);
    if (url.includes("/geocoding/")) {
      return new Response(
        JSON.stringify({
          features: [{ center: [3.725, 51.054], place_name: "Gent" }],
        }),
        { status: 200 },
      );
    }
    if (url.includes("/directions/")) {
      directions += 1;
      onDirections?.(directions, url);
      if (directions <= failFirst) {
        return new Response(
          JSON.stringify({
            code: failCode,
            message: "Could not find a matching segment for input coordinates",
            routes: [],
          }),
          { status: 200 },
        );
      }
      return new Response(
        JSON.stringify({
          code: "Ok",
          routes: [{ distance, duration, legs: [{ distance, duration }] }],
        }),
        { status: 200 },
      );
    }
    return new Response("unmocked", { status: 500 });
  };
}

async function quoteRequest(env, body) {
  return worker.fetch(
    new Request("https://example.test/company/agenda/quote", {
      method: "POST",
      headers: {
        "x-admin-token": ADMIN,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        tenant_id: TENANT_A,
        company_id: COMPANY_A,
        ...body,
      }),
    }),
    env,
    {},
  );
}

test("agenda quote body keeps hourly package on the existing quote path", () => {
  const built = buildCompanyAgendaQuoteRequestBody(
    {
      from: "Gent",
      to: "Brussel",
      pickup_iso: "2026-09-15T07:00:00.000Z",
      service: "hourly",
      requested_duration_minutes: 180,
    },
    { tenant_id: TENANT_A, company_id: COMPANY_A },
  );
  assert.equal(built.ok, true);
  assert.equal(built.body.journey_type, "hourly_package");
  assert.equal(built.body.requested_duration_minutes, 180);
  assert.equal(built.body.date, "2026-09-15");
  assert.equal(built.body.time, "09:00");
});

test("public quote keeps route when automatic price is off", () => {
  const pub = publicCompanyAgendaQuote({
    distance_km: 34.2,
    duration_min: 29,
    pricing_source: "calculator_off",
    price_incl_vat: 46.7,
    currency: "EUR",
  });
  assert.equal(pub.duration_min, 29);
  assert.equal(pub.distance_km, 34.2);
  assert.equal(pub.price_available, false);
  assert.equal(pub.price_incl_vat, null);
});

test("normal route uses company tariffs via calcPrice", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch();
  try {
    const env = envWith(countingKV());
    const res = await quoteRequest(env, {
      from: "Korenmarkt 1, Gent",
      to: "Grote Markt, Ronse",
      pickup_iso: "2026-09-15T07:00:00.000Z",
      from_lat: 51.0543,
      from_lng: 3.7226,
      to_lat: 50.744,
      to_lng: 3.6002,
      passengers: 2,
      tier: "comfort",
      service: "passenger",
    });
    const json = await res.json();
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(json.duration_min, 29);
    assert.equal(json.distance_km, 34.2);
    assert.equal(json.price_available, true);
    assert.ok(Number(json.price_incl_vat) > 0);
    assert.equal(json.pricing_source, "route_calc");
    assert.equal(json.currency, "EUR");
  } finally {
    globalThis.fetch = original;
  }
});

test("matching city pair uses the company fixed price", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch();
  try {
    const kv = countingKV();
    const document = normalizeCompanyFixedPricesDocument({
      fallback: "calculator",
      rules: [
        {
          name: "Gent-Ronse vast",
          rule_id: "fx_gent_ronse",
          kind: "city_pair",
          direction: "one_way",
          priority: 20,
          origin: { type: "city", value: "Gent" },
          destination: { type: "city", value: "Ronse" },
          price_incl_vat: 55,
          currency: "EUR",
        },
      ],
    });
    await kv.put(
      companyFixedPricesKey({ tenant_id: TENANT_A, company_id: COMPANY_A }),
      JSON.stringify({ version: 1, company_fixed_prices: document }),
    );
    const res = await quoteRequest(envWith(kv), {
      from: "Korenmarkt 1, Gent",
      to: "Grote Markt, Ronse",
      pickup_iso: "2026-09-15T07:00:00.000Z",
      from_lat: 51.0543,
      from_lng: 3.7226,
      to_lat: 50.744,
      to_lng: 3.6002,
    });
    const json = await res.json();
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(json.duration_min, 29);
    assert.equal(json.price_incl_vat, 55);
    assert.match(String(json.pricing_source), /fixed|company/i);
  } finally {
    globalThis.fetch = original;
  }
});

test("airport ride uses the airport fixed price", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch({ distance: 18000, duration: 1500 });
  try {
    const kv = countingKV();
    const document = normalizeCompanyFixedPricesDocument({
      fallback: "calculator",
      rules: [
        {
          name: "Gent naar BRU",
          rule_id: "fx_gent_bru",
          kind: "city_pair",
          direction: "one_way",
          priority: 20,
          origin: { type: "city", value: "Gent" },
          destination: { type: "airport", airport_iata: "BRU" },
          price_incl_vat: 85,
          currency: "EUR",
        },
      ],
    });
    await kv.put(
      companyFixedPricesKey({ tenant_id: TENANT_A, company_id: COMPANY_A }),
      JSON.stringify({ version: 1, company_fixed_prices: document }),
    );
    const res = await quoteRequest(envWith(kv), {
      from: "Korenmarkt 1, Gent",
      to: "Brussels Airport",
      pickup_iso: "2026-09-15T07:00:00.000Z",
      from_lat: 51.0543,
      from_lng: 3.7226,
      to_lat: 50.901,
      to_lng: 4.484,
      service: "airport",
      airport_iata: "BRU",
      airport_direction: "to_airport",
    });
    const json = await res.json();
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(json.duration_min, 25);
    assert.equal(json.price_incl_vat, 85);
    assert.match(String(json.pricing_source), /fixed|airport|company/i);
  } finally {
    globalThis.fetch = original;
  }
});

test("calculator off still returns distance and duration", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch();
  try {
    const kv = countingKV();
    await kv.put(
      `tenant:${TENANT_A}:company:${COMPANY_A}:pricing:v1`,
      JSON.stringify({
        version: 1,
        pricing_profile: { calculator_enabled: false, currency: "EUR" },
      }),
    );
    const res = await quoteRequest(envWith(kv), {
      from: "Korenmarkt 1, Gent",
      to: "Grote Markt, Ronse",
      pickup_iso: "2026-09-15T07:00:00.000Z",
      from_lat: 51.0543,
      from_lng: 3.7226,
      to_lat: 50.744,
      to_lng: 3.6002,
    });
    const json = await res.json();
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(json.duration_min, 29);
    assert.equal(json.distance_km, 34.2);
    assert.equal(json.price_available, false);
    assert.equal(json.price_incl_vat, null);
    assert.equal(json.pricing_source, "calculator_off");
  } finally {
    globalThis.fetch = original;
  }
});

test("NoSegment retries once then returns a real route", async () => {
  const original = globalThis.fetch;
  const urls = [];
  globalThis.fetch = mapboxFetch({
    failFirst: 1,
    onDirections: (_n, url) => urls.push(url),
  });
  try {
    const res = await quoteRequest(envWith(countingKV()), {
      from: "Korenmarkt 1, Gent",
      to: "Grote Markt, Ronse",
      pickup_iso: "2026-09-15T07:00:00.000Z",
      from_lat: 51.0543,
      from_lng: 3.7226,
      to_lat: 50.744,
      to_lng: 3.6002,
    });
    const json = await res.json();
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(json.duration_min, 29);
    assert.equal(urls.length, 2);
    assert.match(urls[1], /radiuses=50%3B50|radiuses=50;50/);
  } finally {
    globalThis.fetch = original;
  }
});

test("route failure keeps no invented duration", async () => {
  const original = globalThis.fetch;
  globalThis.fetch = mapboxFetch({ failFirst: 4, failCode: "NoRoute" });
  try {
    const res = await quoteRequest(envWith(countingKV()), {
      from: "Korenmarkt 1, Gent",
      to: "Grote Markt, Ronse",
      pickup_iso: "2026-09-15T07:00:00.000Z",
      from_lat: 51.0543,
      from_lng: 3.7226,
      to_lat: 50.744,
      to_lng: 3.6002,
    });
    const json = await res.json();
    assert.equal(res.status, 422);
    assert.equal(json.ok, false);
    assert.equal(json.duration_min, null);
    assert.equal(json.distance_km, null);
    assert.ok(String(json.message || json.error).length > 0);
  } finally {
    globalThis.fetch = original;
  }
});
