// AIRPORT-RETURN-QUOTE-P0 — POST /quote must price a scheduled return leg or fail.
// Mocked Mapbox + in-memory KV. No deploy, no /book, no payment.
// Run: node --test workers/booking/airport_return_quote.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "./fluxidi_booking_worker.js";
import {
  companyFixedPricesKey,
  normalizeCompanyFixedPricesDocument,
} from "./modules/company_fixed_prices.mjs";

const TENANT = "TRET";
const COMPANY = "CRET";

const GENT = { lat: 51.0543, lng: 3.7253 };
const BRU = { lat: 50.9014, lng: 4.4844 };

const OUTBOUND = {
  from: "Korenmarkt, Gent",
  to: "Brussels Airport, Zaventem",
  date: "2026-09-25",
  time: "11:30",
  from_lat: GENT.lat,
  from_lng: GENT.lng,
  to_lat: BRU.lat,
  to_lng: BRU.lng,
  pax: 1,
  bags: 0,
  service: "airport",
  airport_iata: "BRU",
  airport_direction: "to_airport",
};

const SCHEDULED_RETURN = {
  return_enabled: true,
  return_kind: "noWait",
  return_from: "Brussels Airport, Zaventem",
  return_to: "Korenmarkt, Gent",
  return_date: "2026-09-27",
  return_time: "18:00",
};

function memoryKV(seed = {}) {
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
      if (!asJson) return raw;
      try {
        return typeof raw === "string" ? JSON.parse(raw) : raw;
      } catch {
        return null;
      }
    },
    async put(key, value) {
      store.set(key, value);
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
  return { BOOKING_KV: kv, MAPBOX_TOKEN: "test-mapbox" };
}

/** Mapbox stub that records every geocode query and every directions path. */
function mapboxFetch({
  distance = 67400,
  duration = 3300,
  geocodeEmptyFor = [],
  directionsFailFrom = 0,
} = {}) {
  const calls = { geocode: [], directions: [] };
  const fn = async (input) => {
    const url = String(input);
    if (url.includes("/geocoding/")) {
      const query = decodeURIComponent(
        url.split("/mapbox.places/")[1].split(".json")[0] || "",
      );
      calls.geocode.push(query);
      const empty = geocodeEmptyFor.some((needle) =>
        query.toLowerCase().includes(String(needle).toLowerCase()),
      );
      if (empty) return new Response(JSON.stringify({ features: [] }), { status: 200 });
      const center = /airport|zaventem|bru/i.test(query)
        ? [BRU.lng, BRU.lat]
        : [GENT.lng, GENT.lat];
      return new Response(
        JSON.stringify({ features: [{ center, place_name: query, relevance: 1 }] }),
        { status: 200 },
      );
    }
    if (url.includes("/directions/")) {
      const path = url.split("/mapbox/driving/")[1]?.split("?")[0] || "";
      calls.directions.push(path);
      if (directionsFailFrom && calls.directions.length >= directionsFailFrom) {
        return new Response(
          JSON.stringify({ code: "NoSegment", message: "no segment", routes: [] }),
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
  fn.calls = calls;
  return fn;
}

async function quote(env, body) {
  const res = await worker.fetch(
    new Request("https://example.test/quote", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ tenant_id: TENANT, company_id: COMPANY, ...body }),
    }),
    env,
    {},
  );
  return { res, json: await res.json() };
}

async function withMapbox(stub, run) {
  const original = globalThis.fetch;
  globalThis.fetch = stub;
  try {
    return await run(stub);
  } finally {
    globalThis.fetch = original;
  }
}

function airportFixedPricesDocument(priceInclVat) {
  return normalizeCompanyFixedPricesDocument({
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
        price_incl_vat: priceInclVat,
        currency: "EUR",
      },
      {
        name: "BRU naar Gent",
        rule_id: "fx_bru_gent",
        kind: "city_pair",
        direction: "one_way",
        priority: 20,
        origin: { type: "airport", airport_iata: "BRU" },
        destination: { type: "city", value: "Gent" },
        price_incl_vat: priceInclVat,
        currency: "EUR",
      },
    ],
  });
}

async function kvWithFixedPrices(priceInclVat) {
  const kv = memoryKV();
  await kv.put(
    companyFixedPricesKey({ tenant_id: TENANT, company_id: COMPANY }),
    JSON.stringify({
      version: 1,
      company_fixed_prices: airportFixedPricesDocument(priceInclVat),
    }),
  );
  return kv;
}

// ---------------------------------------------------------------------------
// 1. One-way stays exactly as it was
// ---------------------------------------------------------------------------

test("1) a one-way airport quote has no return leg and no return pricing source", async () => {
  await withMapbox(mapboxFetch(), async () => {
    const { res, json } = await quote(envWith(memoryKV()), { ...OUTBOUND });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(Number(json.price_incl_vat_main) > 0);
    assert.equal(json.price_incl_vat_return, null);
    assert.equal(json.return, null);
    assert.equal(json.pricing_source_return, null);
    assert.equal(Number(json.total_price_incl_vat), Number(json.price_incl_vat_main));
  });
});

// ---------------------------------------------------------------------------
// 2. Exact reversal reuses the swapped outbound coordinates
// ---------------------------------------------------------------------------

test("2) an exact reversal routes on swapped outbound coordinates without geocoding", async () => {
  const stub = mapboxFetch();
  await withMapbox(stub, async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
    });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.deepEqual(stub.calls.geocode, [], "no address had to be geocoded");
    assert.equal(stub.calls.directions.length, 2, "one route per leg");
    assert.equal(json.return.route_strategy, "reverse_outbound");
    assert.ok(Number(json.price_incl_vat_return) > 0);
    // The return leg drives from the airport back to the city.
    assert.match(stub.calls.directions[1], /^4\.4844,50\.9014;3\.7253,51\.0543$/);
  });
});

// ---------------------------------------------------------------------------
// 3. Edited return addresses are geocoded on their own
// ---------------------------------------------------------------------------

test("3) an edited return destination is geocoded separately", async () => {
  const stub = mapboxFetch();
  await withMapbox(stub, async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
      return_to: "Sint-Pietersnieuwstraat, Gent",
    });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(
      stub.calls.geocode.some((q) => q.includes("Sint-Pietersnieuwstraat")),
      `edited return address was geocoded: ${JSON.stringify(stub.calls.geocode)}`,
    );
    assert.equal(json.return.route_strategy, "geocode");
    assert.ok(Number(json.price_incl_vat_return) > 0);
  });
});

// ---------------------------------------------------------------------------
// 4. Return stops belong to the return leg, in order
// ---------------------------------------------------------------------------

test("4) return stops are added to the return route in order", async () => {
  const stub = mapboxFetch();
  await withMapbox(stub, async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
      return_stops: [{ address: "Aalst" }, { address: "   " }, "Wetteren"],
    });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(stub.calls.geocode.length, 2, "only the two real stops were geocoded");
    assert.deepEqual(stub.calls.geocode, ["Aalst", "Wetteren"]);
    const returnPath = stub.calls.directions[1].split(";");
    assert.equal(returnPath.length, 4, "airport, stop, stop, city");
    assert.equal(returnPath[0], "4.4844,50.9014");
    assert.equal(returnPath[3], "3.7253,51.0543");
    assert.ok(Number(json.price_incl_vat_return) > 0);
  });
});

// ---------------------------------------------------------------------------
// 5 & 6. Return moments
// ---------------------------------------------------------------------------

test("5) a return on a later date is priced", async () => {
  await withMapbox(mapboxFetch(), async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
      return_date: "2026-10-02",
    });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(Number(json.price_incl_vat_return) > 0);
  });
});

test("6) a same-day return later in the evening is priced", async () => {
  await withMapbox(mapboxFetch(), async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
      return_date: "2026-09-25",
      return_time: "22:15",
    });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.ok(Number(json.price_incl_vat_return) > 0);
  });
});

test("7) a return before the outbound leg is refused, not priced", async () => {
  await withMapbox(mapboxFetch(), async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
      return_date: "2026-09-25",
      return_time: "07:00",
    });
    assert.equal(res.status, 422, JSON.stringify(json));
    assert.equal(json.error, "return_quote_failed");
    assert.equal(json.total_price_incl_vat, null);
  });
});

// ---------------------------------------------------------------------------
// 8 & 9. Failures produce return_quote_failed, never a one-way total
// ---------------------------------------------------------------------------

test("8) a return geocode failure answers return_quote_failed", async () => {
  const stub = mapboxFetch({ geocodeEmptyFor: ["Sint-Pietersnieuwstraat"] });
  await withMapbox(stub, async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
      return_to: "Sint-Pietersnieuwstraat, Gent",
    });
    assert.equal(res.status, 422, JSON.stringify(json));
    assert.equal(json.error, "return_quote_failed");
    assert.equal(json.error_code, "return_quote_failed");
  });
});

test("9) a return route failure answers return_quote_failed", async () => {
  const stub = mapboxFetch({ directionsFailFrom: 2 });
  await withMapbox(stub, async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
    });
    assert.equal(res.status, 422, JSON.stringify(json));
    assert.equal(json.error, "return_quote_failed");
  });
});

test("10) a failed return leg never returns HTTP 200 with the outbound price as total", async () => {
  const stub = mapboxFetch({ directionsFailFrom: 2 });
  await withMapbox(stub, async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
    });
    assert.notEqual(res.status, 200);
    assert.equal(json.price_incl_vat_main, null);
    assert.equal(json.price_incl_vat_return, null);
    assert.equal(json.total_price_incl_vat, null);
    assert.equal(json.pricing_source_return, null);
    assert.equal(json.return, null);
  });
});

// ---------------------------------------------------------------------------
// 11 & 12. Fixed price per leg and exact totals
// ---------------------------------------------------------------------------

test("11) a per-ride fixed price is charged for both legs of a round trip", async () => {
  const kv = await kvWithFixedPrices(200);
  await withMapbox(mapboxFetch(), async () => {
    const { res, json } = await quote(envWith(kv), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
    });
    assert.equal(res.status, 200, JSON.stringify(json));
    assert.equal(Number(json.price_incl_vat_main), 200);
    assert.equal(Number(json.price_incl_vat_return), 200);
    assert.equal(Number(json.total_price_incl_vat), 400);
    assert.match(String(json.pricing_source_return), /fixed|company|airport/i);
  });
});

test("12) the total is exactly main plus return, in cents", async () => {
  await withMapbox(mapboxFetch(), async () => {
    const { res, json } = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      ...SCHEDULED_RETURN,
    });
    assert.equal(res.status, 200, JSON.stringify(json));
    const mainCents = Math.round(Number(json.price_incl_vat_main) * 100);
    const returnCents = Math.round(Number(json.price_incl_vat_return) * 100);
    const totalCents = Math.round(Number(json.total_price_incl_vat) * 100);
    assert.equal(totalCents, mainCents + returnCents);
    assert.equal(
      Math.round(Number(json.total_price_ex_vat) * 100),
      Math.round(Number(json.price_ex_vat_main) * 100) +
        Math.round(Number(json.price_ex_vat_return) * 100),
    );
  });
});

// ---------------------------------------------------------------------------
// 13. pricing_source_return is never invented
// ---------------------------------------------------------------------------

test("13) pricing_source_return stays empty when there is no return quote", async () => {
  await withMapbox(mapboxFetch(), async () => {
    const oneWay = await quote(envWith(memoryKV()), { ...OUTBOUND });
    assert.equal(oneWay.json.pricing_source_return, null);

    // Waiting round trip: one leg, no separate schedule. Unchanged behaviour.
    const waiting = await quote(envWith(memoryKV()), {
      ...OUTBOUND,
      service: "taxi",
      airport_iata: undefined,
      airport_direction: undefined,
      return_enabled: true,
      wait_min: 45,
    });
    assert.equal(waiting.res.status, 200, JSON.stringify(waiting.json));
    assert.equal(waiting.json.pricing_source_return, null);
    assert.equal(waiting.json.price_incl_vat_return, null);
    assert.equal(
      Number(waiting.json.total_price_incl_vat),
      Number(waiting.json.price_incl_vat_main),
      "a waiting round trip still totals one leg",
    );
  });
});

test("14) a company with return pricing switched off refuses a scheduled return", async () => {
  const kv = memoryKV();
  await kv.put(
    `tenant:${TENANT}:company:${COMPANY}:pricing:v1`,
    JSON.stringify({ pricing_profile: { return_enabled: false } }),
  );
  await withMapbox(mapboxFetch(), async () => {
    const { res, json } = await quote(envWith(kv), { ...OUTBOUND, ...SCHEDULED_RETURN });
    assert.equal(res.status, 422, JSON.stringify(json));
    assert.equal(json.error, "return_quote_failed");
    assert.equal(json.total_price_incl_vat, null);
  });
});
