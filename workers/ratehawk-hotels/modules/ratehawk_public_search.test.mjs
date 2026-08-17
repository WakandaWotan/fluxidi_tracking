// Gated public RateHawk Search + rhctx1 issuance.
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_public_search.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  handlePublicRatehawkHotelpage,
  handlePublicRatehawkSearch,
  runTaxiBookingIsolationProbe,
} from "../../booking/modules/ratehawk_hotels_facade.mjs";
import { handleRatehawkHotelsWorkerFetch } from "../fluxidi_ratehawk_hotels_worker.js";
import { RATEHAWK_ALLOWED_OPERATIONS } from "./ratehawk_provider.mjs";
import { createRatehawkQuotaBinding } from "./ratehawk_provider_quota.mjs";
import { handleRatehawkPublicSearchRequest } from "./ratehawk_public_search.mjs";
import {
  RATEHAWK_SERP_GEO_PATH,
  RATEHAWK_SERP_REGION_PATH,
} from "./ratehawk_market_search_limits.mjs";
import {
  openRatehawkViewStayContext,
  verifyRatehawkViewStayContext,
} from "./ratehawk_view_stay_context.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const NOW = Date.parse("2026-08-17T10:00:00Z");
const CONTEXT_SECRET = "public-search-context-secret-test-only";
const API_KEY = "must-not-leave-hotels-worker";

const BRUSSELS_MARKET = {
  market_key: "be:brussels",
  country_code: "BE",
  city_key: "brussels",
  aliases: ["brussel", "brussels", "bruxelles"],
  region_id: "2395",
  enabled: true,
};

const ANTWERP_MARKET = {
  market_key: "be:antwerp",
  country_code: "BE",
  city_key: "antwerp",
  aliases: ["antwerp", "antwerpen"],
  geo: { lat: 51.2194, lng: 4.4025, radius_m: 8000 },
  enabled: true,
};

function affiliateNowRate(overrides = {}) {
  return {
    book_hash: "h-public-now",
    match_hash: "m-public-now",
    room_name: "Superior Double",
    meal: "breakfast",
    meal_data: { value: "breakfast", has_breakfast: true },
    allotment: 2,
    payment_options: {
      payment_types: [
        {
          type: "now",
          amount: "180.00",
          show_amount: "180.00",
          currency_code: "EUR",
          show_currency_code: "EUR",
          tax_data: {
            taxes: [
              {
                name: "vat",
                included_by_supplier: true,
                amount: "30.00",
                currency_code: "EUR",
              },
            ],
          },
        },
      ],
    },
    cancellation_penalties: {
      free_cancellation_before: "2026-09-01T10:00:00",
      policies: [],
    },
    ...overrides,
  };
}

function mockHotel(hid = 6117198, extras = {}) {
  return {
    hid,
    name: "Example Brussels Hotel",
    address: "Rue Example 1, 1000 Brussels",
    city: "Brussels",
    country: "BE",
    lat: 50.8467,
    lng: 4.3525,
    star_rating: 4,
    rates: [affiliateNowRate()],
    ...extras,
  };
}

function memoryBookingKv(seed = {}) {
  const data = new Map(Object.entries(seed));
  return {
    async get(key, opts) {
      const raw = data.get(key);
      if (raw == null) return null;
      if (opts?.type === "json") {
        return typeof raw === "string" ? JSON.parse(raw) : raw;
      }
      return raw;
    },
    async put(key, value) {
      data.set(key, value);
    },
  };
}

function productionQuotaEnv() {
  return {
    RATEHAWK_ENVIRONMENT: "production",
    RATEHAWK_QUOTA_HOTELPAGE_LIMIT: "20",
    RATEHAWK_QUOTA_HOTELPAGE_WINDOW_SECONDS: "60",
    RATEHAWK_QUOTA_SERP_LIMIT: "15",
    RATEHAWK_QUOTA_SERP_WINDOW_SECONDS: "60",
    RATEHAWK_QUOTA_HOTEL_CONTENT_LIMIT: "30",
    RATEHAWK_QUOTA_HOTEL_CONTENT_WINDOW_SECONDS: "60",
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
  };
}

function gatedProductionEnv(overrides = {}) {
  return {
    RATEHAWK_WORKER_SURFACE: "production",
    RATEHAWK_ENABLED: "1",
    RATEHAWK_SEARCH_ENABLED: "1",
    RATEHAWK_HOTELPAGE_ENABLED: "0",
    RATEHAWK_PRODUCTION_ENABLED: "1",
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_KEY_ID: "18292",
    RATEHAWK_API_KEY: API_KEY,
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_SEARCH_MARKETS: JSON.stringify([BRUSSELS_MARKET, ANTWERP_MARKET]),
    ...productionQuotaEnv(),
    ...overrides,
  };
}

function completeBody(overrides = {}) {
  return {
    trigger: "live_search",
    city: "Brussel",
    country: "BE",
    checkin: "2026-09-03",
    checkout: "2026-09-04",
    guests: [{ adults: 2, children: [] }],
    language: "nl",
    currency: "EUR",
    ...overrides,
  };
}

function recordingFetch(hotels = [mockHotel()], { status = 200, etg = "ok", fail } = {}) {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({
      url: String(url),
      method: init?.method,
      body: JSON.parse(init?.body || "{}"),
      hasAuthorization: Boolean(init?.headers?.Authorization),
    });
    if (typeof fail === "function") return fail(url, init);
    return {
      status,
      async json() {
        return { status: etg, data: { hotels } };
      },
    };
  };
  return { calls, fetchImpl };
}

function assertNoLeaks(value) {
  const raw = JSON.stringify(value);
  assert.equal(raw.includes("h-public-now"), false);
  assert.equal(raw.includes("m-public-now"), false);
  assert.equal(raw.includes(API_KEY), false);
  assert.equal(raw.includes("Basic "), false);
  assert.equal(/commission|remuneration|affiliate_remuneration/i.test(raw), false);
  assert.equal(raw.includes("reconciliation_amount"), false);
}

test("1. page open produces zero provider calls", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: { ...completeBody(), trigger: "page_open" },
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "page_open_no_request");
});

test("2. incomplete search produces zero provider calls", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: { trigger: "live_search", city: "Brussel" },
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 0);
  assert.equal(dto.reason, "live_search_incomplete");
});

test("3. unsupported market produces zero provider calls", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody({ city: "Paris", country: "FR" }),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 0);
  assert.equal(dto.reason, "unsupported_market");
});

test("4. ambiguous destination fails closed", async () => {
  const rec = recordingFetch();
  const env = gatedProductionEnv({
    RATEHAWK_SEARCH_MARKETS: JSON.stringify([
      BRUSSELS_MARKET,
      {
        market_key: "fr:lookalike",
        country_code: "FR",
        city_key: "bruxelles-sud",
        aliases: ["brussels"],
        region_id: "1",
        enabled: true,
      },
    ]),
  });
  const dto = await handleRatehawkPublicSearchRequest({
    env,
    body: completeBody({ city: "brussels", country: "" }),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 0);
  assert.equal(dto.reason, "ambiguous_destination");
});

test("5. client-supplied host/endpoint/region/hid is rejected", async () => {
  const rec = recordingFetch();
  for (const extra of [
    { hid: 8473727 },
    { region_id: 2395 },
    { host: "api.ratehawk.com" },
    { endpoint: "/api/b2b/v3/search/serp/region/" },
  ]) {
    const dto = await handleRatehawkPublicSearchRequest({
      env: gatedProductionEnv(),
      body: completeBody(extra),
      fetchImpl: rec.fetchImpl,
      now: NOW,
    });
    assert.equal(dto.reason, "client_control_forbidden");
  }
  assert.equal(rec.calls.length, 0);
});

test("6. missing production market config produces zero provider calls", async () => {
  const rec = recordingFetch();
  const env = gatedProductionEnv();
  delete env.RATEHAWK_SEARCH_MARKETS;
  const dto = await handleRatehawkPublicSearchRequest({
    env,
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 0);
  assert.equal(dto.reason, "production_markets_unconfigured");
});

test("7. missing gate/config/credential/context secret produces zero transport", async () => {
  const rec = recordingFetch();
  const gatedOff = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv({ RATEHAWK_SEARCH_ENABLED: "0" }),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  const noSecret = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv({ RATEHAWK_VIEW_STAY_CONTEXT_SECRET: "" }),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  const noKey = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv({ RATEHAWK_API_KEY: "" }),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 0);
  assert.equal(gatedOff.reason, "ratehawk_search_disabled");
  assert.equal(noSecret.reason, "view_stay_context_secret_missing");
  assert.equal(noKey.invoked, false);
});

test("8. public abuse-limit denial produces zero Hotels binding/provider calls", async () => {
  let hotelsCalls = 0;
  const dto = await handlePublicRatehawkSearch({
    env: {
      BOOKING_KV: {
        async get() {
          return { count: 20 };
        },
        async put() {
          throw new Error("must_not_write_after_limit");
        },
      },
      RATEHAWK_HOTELS: {
        fetch: async () => {
          hotelsCalls += 1;
          throw new Error("must_not_call_hotels");
        },
      },
    },
    query: {
      source: "ratehawk",
      city: "Brussel",
      country: "BE",
      checkin: "2026-09-03",
      checkout: "2026-09-04",
      rooms: "1",
      adults: "2",
    },
    request: new Request("https://booking.internal/public/hotels/search"),
  });
  assert.equal(hotelsCalls, 0);
  assert.equal(dto.reason, "rate_limited");
  assert.equal(dto.count, 0);
});

test("9. provider quota denial produces zero transport", async () => {
  const rec = recordingFetch();
  const env = gatedProductionEnv({
    RATEHAWK_QUOTA_SERP_LIMIT: "1",
  });
  const first = await handleRatehawkPublicSearchRequest({
    env,
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(first.invoked, true);
  assert.equal(rec.calls.length, 1);
  const denied = await handleRatehawkPublicSearchRequest({
    env,
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 1);
  assert.equal(denied.invoked, false);
  assert.equal(denied.reason, "provider_quota_exhausted");
  assert.equal(Number.isInteger(denied.retry_after), true);
  assert.ok(denied.retry_after >= 1);
});

test("10. one accepted request produces exactly one provider call and no retry", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(rec.calls.length, 1);
  assert.equal(dto.invoked, true);
  assert.equal(rec.calls[0].url.endsWith(RATEHAWK_SERP_REGION_PATH), true);
  assert.equal(rec.calls[0].body.region_id, 2395);
  assert.equal(rec.calls[0].body.language, "nl");
  assert.equal(Object.hasOwn(rec.calls[0].body, "hids"), false);
});

test("11. timeout/error is redacted and retryable", async () => {
  const timeout = recordingFetch([], {
    fail: async () => {
      const err = new Error("aborted");
      err.name = "AbortError";
      throw err;
    },
  });
  const timed = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: timeout.fetchImpl,
    now: NOW,
  });
  assert.equal(timed.reason, "timeout");
  assert.equal(timed.retryable, true);
  assert.equal(timed.invoked, true);
  assertNoLeaks(timed);

  const errored = recordingFetch([], { status: 500, etg: API_KEY });
  const fail = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: errored.fetchImpl,
    now: NOW,
  });
  assert.equal(fail.reason, "provider_error");
  assert.equal(fail.retryable, true);
  assert.equal(errored.calls.length, 1);
  assertNoLeaks(fail);
});

test("12. result limit 20 / load-more 20 / max 100 is enforced", async () => {
  const hotels = Array.from({ length: 40 }, (_, i) =>
    mockHotel(1000 + i, { name: `Hotel ${i}` }),
  );
  const rec = recordingFetch(hotels);
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(dto.count, 20);
  assert.equal(dto.limits.initial_hotel_limit, 20);
  assert.equal(dto.limits.load_more_increment, 20);
  assert.equal(dto.limits.absolute_maximum, 100);
});

test("13-16. safe card DTO has hid, current rate, and bound rhctx1", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(dto.count, 1);
  const stay = dto.stays[0];
  assert.equal(stay.source, "ratehawk");
  assert.equal(stay.provider_id, "6117198");
  assert.equal(stay.hid, 6117198);
  assert.equal(typeof stay.price_label, "string");
  assert.ok(stay.price_label.includes("180"));
  assert.equal(stay.view_stay_context.startsWith("rhctx1."), true);
  const opened = await openRatehawkViewStayContext(
    CONTEXT_SECRET,
    stay.view_stay_context,
    { now: NOW },
  );
  assert.equal(opened.ok, true);
  assert.deepEqual(opened.claims, {
    source: "ratehawk",
    hid: 6117198,
    checkin: "2026-09-03",
    checkout: "2026-09-04",
    residency: "be",
    currency: "EUR",
    guests: [{ adults: 2, children: [] }],
    purpose: "view_stay",
  });
  assertNoLeaks(dto);
});

test("14. no live rate means no invented price", async () => {
  const rec = recordingFetch([
    mockHotel(6117198, { rates: [] }),
  ]);
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(dto.stays[0].price_label, null);
  assert.equal(dto.stays[0].view_stay_context, null);
});

test("17. tampering or expiry is rejected by the existing Hotelpage path", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  const stay = dto.stays[0];
  const expected = stay.stay_context;
  const good = await verifyRatehawkViewStayContext(
    CONTEXT_SECRET,
    stay.view_stay_context,
    expected,
    { now: NOW },
  );
  assert.equal(good.ok, true);
  const tampered = `${stay.view_stay_context.slice(0, -2)}aa`;
  const bad = await verifyRatehawkViewStayContext(
    CONTEXT_SECRET,
    tampered,
    expected,
    { now: NOW },
  );
  assert.equal(bad.ok, false);
  assert.equal(bad.reason, "view_stay_context_tampered");
  const expired = await verifyRatehawkViewStayContext(
    CONTEXT_SECRET,
    stay.view_stay_context,
    expected,
    { now: NOW + 16 * 60 * 1000 },
  );
  assert.equal(expired.reason, "view_stay_context_expired");

  let hotelsCalls = 0;
  const hotelpage = await handlePublicRatehawkHotelpage({
    env: {
      BOOKING_KV: memoryBookingKv(),
      RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
      RATEHAWK_HOTELS: {
        fetch: async () => {
          hotelsCalls += 1;
          throw new Error("must_not_call_after_tamper");
        },
      },
    },
    request: new Request("https://booking.internal/public/hotels/ratehawk/hotelpage", {
      method: "POST",
    }),
    body: {
      view_stay_context: tampered,
      hid: expected.hid,
      checkin: expected.checkin,
      checkout: expected.checkout,
      residency: expected.residency,
      currency: expected.currency,
      guests: expected.guests,
    },
    now: NOW,
  });
  assert.equal(hotelsCalls, 0);
  assert.equal(hotelpage.invoked, false);
  assert.equal(hotelpage.reason, "view_stay_context_tampered");
});

test("18. no hashes, credentials, reconciliation or commission leave Hotels Worker", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assertNoLeaks(dto);
  assert.equal(dto.internal, undefined);
});

test("22. stale rates are not bookable", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.ok(dto.expires_at > dto.retrieved_at);
  assert.ok(dto.stays[0].expires_at > NOW);
  assert.ok(dto.stays[0].view_stay_context_expires_at > dto.stays[0].expires_at);
  const expired = await openRatehawkViewStayContext(
    CONTEXT_SECRET,
    dto.stays[0].view_stay_context,
    { now: dto.stays[0].view_stay_context_expires_at },
  );
  assert.equal(expired.ok, false);
});

test("24. public route cannot use the test binding", async () => {
  let testCalls = 0;
  const rec = recordingFetch();
  const hotelsEnv = gatedProductionEnv();
  const dto = await handlePublicRatehawkSearch({
    env: {
      BOOKING_KV: memoryBookingKv(),
      RATEHAWK_HOTELS: {
        fetch: async (request) =>
          handleRatehawkHotelsWorkerFetch(request, hotelsEnv, {
            fetchImpl: rec.fetchImpl,
            now: NOW,
          }),
      },
      RATEHAWK_HOTELS_TEST: {
        fetch: async () => {
          testCalls += 1;
          throw new Error("test_binding_must_not_be_used");
        },
      },
    },
    query: {
      source: "ratehawk",
      city: "Brussel",
      country: "BE",
      checkin: "2026-09-03",
      checkout: "2026-09-04",
      rooms: "1",
      adults: "2",
      language: "nl",
    },
  });
  assert.equal(testCalls, 0);
  assert.equal(dto.invoked, true);
  assert.equal(rec.calls.length, 1);
});

test("25. admin test route source cannot become the public customer backend", () => {
  const worker = readFileSync(join(HERE, "../fluxidi_ratehawk_hotels_worker.js"), "utf8");
  const publicSearch = readFileSync(join(HERE, "ratehawk_public_search.mjs"), "utf8");
  const transport = readFileSync(join(HERE, "ratehawk_public_serp_transport.mjs"), "utf8");
  assert.equal(publicSearch.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(publicSearch.includes("RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET"), false);
  assert.equal(publicSearch.includes("8473727"), false);
  assert.equal(transport.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(transport.includes("RATEHAWK_SERP_HOTELS_PATH"), false);
  assert.match(worker, /RATEHAWK_HOTELS_SEARCH_PATH/);
  assert.deepEqual(RATEHAWK_ALLOWED_OPERATIONS, ["overview"]);
});

test("26. taxi/airport/events/Saved/Stay22 remain unchanged", () => {
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 4 });
  assert.equal(taxi.invoked_ratehawk, false);
  const facade = readFileSync(join(HERE, "../../booking/modules/ratehawk_hotels_facade.mjs"), "utf8");
  assert.match(facade, /existing_actions/);
  assert.match(facade, /taxi_to_this_stay/);
  assert.match(facade, /stay22_fallback_availability/);
  const searchFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkSearch"),
    facade.indexOf("export async function handlePublicRatehawkHotelpage"),
  );
  assert.equal(searchFn.includes("RATEHAWK_HOTELS_TEST"), false);
});

test("27. production and test gates remain isolated", () => {
  const wrangler = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
  assert.match(wrangler, /RATEHAWK_ENABLED = "0"/);
  assert.match(wrangler, /RATEHAWK_SEARCH_ENABLED = "0"/);
  assert.match(wrangler, /RATEHAWK_HOTELPAGE_ENABLED = "0"/);
  assert.equal(/RATEHAWK_SEARCH_ENABLED = "1"/.test(wrangler), false);
  assert.equal(/RATEHAWK_SEARCH_MARKETS\s*=/.test(wrangler), false);
});

test("28. no static Content D1 write occurs from Search", async () => {
  const writes = [];
  const rec = recordingFetch();
  await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody(),
    fetchImpl: rec.fetchImpl,
    now: NOW,
    contentStore: {
      write: async (row) => {
        writes.push(row);
      },
    },
  });
  assert.equal(writes.length, 0);
  const searchSrc = readFileSync(join(HERE, "ratehawk_public_search.mjs"), "utf8");
  const transportSrc = readFileSync(join(HERE, "ratehawk_public_serp_transport.mjs"), "utf8");
  assert.equal(searchSrc.includes("RATEHAWK_HOTELS_DB"), false);
  assert.equal(transportSrc.includes("RATEHAWK_HOTELS_DB"), false);
  assert.equal(searchSrc.includes("openRatehawkContentStore"), false);
});

test("geo market uses the allowlisted geo SERP path", async () => {
  const rec = recordingFetch();
  const dto = await handleRatehawkPublicSearchRequest({
    env: gatedProductionEnv(),
    body: completeBody({ city: "Antwerp", country: "BE" }),
    fetchImpl: rec.fetchImpl,
    now: NOW,
  });
  assert.equal(dto.invoked, true);
  assert.equal(rec.calls[0].url.endsWith(RATEHAWK_SERP_GEO_PATH), true);
  assert.equal(rec.calls[0].body.latitude, 51.2194);
  assert.equal(Object.hasOwn(rec.calls[0].body, "region_id"), false);
});
