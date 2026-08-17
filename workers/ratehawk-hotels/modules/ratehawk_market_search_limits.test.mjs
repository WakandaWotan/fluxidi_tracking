// RATEHAWK-P1 mocked market-scope and search-limit contract
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_market_search_limits.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  RATEHAWK_DEFAULT_SEARCH_LIMITS,
  RATEHAWK_SEARCH_TRIGGERS,
  RATEHAWK_SERP_HOTELS_PATH,
  RATEHAWK_TEST_HOTEL_HID,
  annotateSearchResultMetadata,
  assertPublicSearchStayDates,
  buildProposedTestSearchRequest,
  createRateCache,
  createSearchFlightController,
  createStaticContentStore,
  dedupeHotelsByHid,
  hasForbiddenPublicSearchClientControl,
  isLiveSearchCriteriaComplete,
  nextHotelIdChunk,
  parseConfiguredSearchMarkets,
  planImmediateExistingCards,
  rateCacheKey,
  resolveEnabledMarket,
  resolveMarketSearchConfig,
  resolvePublicSearchMarket,
  shouldIssueRatehawkSearch,
} from "./ratehawk_market_search_limits.mjs";

const EXAMPLE_TEST_MARKETS = Object.freeze([
  {
    country_code: "BE",
    city_key: "brussels",
    aliases: ["brussel", "brussels", "bruxelles"],
    region_id: "test-region-example-not-production",
    enabled: true,
  },
  {
    country_code: "BE",
    city_key: "antwerp",
    geo: { lat: 51.2194, lng: 4.4025, radius_m: 8000 },
    enabled: true,
  },
]);

function exampleConfig(env = {}) {
  return resolveMarketSearchConfig(env, { markets: EXAMPLE_TEST_MARKETS });
}

test("server config has no hardcoded city list; example markets are test-only", () => {
  const empty = resolveMarketSearchConfig({});
  assert.deepEqual(empty.enabled_markets, []);
  assert.equal(empty.limits.initial_hotel_limit, 20);
  assert.equal(empty.limits.load_more_increment, 20);
  assert.equal(empty.limits.absolute_maximum, 100);

  const configured = exampleConfig({
    RATEHAWK_SEARCH_INITIAL_LIMIT: "8",
    RATEHAWK_SEARCH_LOAD_MORE_INCREMENT: "5",
    RATEHAWK_SEARCH_ABSOLUTE_MAX: "18",
  });
  assert.equal(configured.limits.initial_hotel_limit, 8);
  assert.equal(configured.limits.load_more_increment, 5);
  assert.equal(configured.limits.absolute_maximum, 18);
  assert.equal(configured.enabled_markets[0].region_id, "test-region-example-not-production");
  assert.equal(configured.enabled_markets[1].geo.radius_m, 8000);
});

test("enabled market resolves by country/city to region id or trusted geo", () => {
  const config = exampleConfig();
  const brussels = resolveEnabledMarket(config, {
    country_code: "BE",
    city_key: "brussels",
  });
  assert.equal(brussels.ok, true);
  assert.equal(brussels.market.region_id, "test-region-example-not-production");

  const antwerp = resolveEnabledMarket(config, {
    country_code: "BE",
    city_key: "antwerp",
  });
  assert.equal(antwerp.ok, true);
  assert.equal(antwerp.market.geo.lat, 51.2194);

  const paris = resolveEnabledMarket(config, {
    country_code: "FR",
    city_key: "paris",
  });
  assert.equal(paris.ok, false);
  assert.equal(paris.reason, "market_not_enabled");
});

test("opening HotelsPage never issues a RateHawk request", () => {
  const config = exampleConfig();
  const market = resolveEnabledMarket(config, {
    country_code: "BE",
    city_key: "brussels",
  });
  const criteria = isLiveSearchCriteriaComplete({
    destination: { country_code: "BE", city_key: "brussels" },
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    guests: [{ adults: 2, children: [] }],
  });
  const decision = shouldIssueRatehawkSearch({
    trigger: RATEHAWK_SEARCH_TRIGGERS.PAGE_OPEN,
    criteria,
    market,
  });
  assert.equal(decision.issue, false);
  assert.equal(decision.reason, "page_open_no_request");
});

test("live search requires complete destination, dates and guests", () => {
  const incomplete = isLiveSearchCriteriaComplete({
    destination: { country_code: "BE", city_key: "brussels" },
    checkin: "2026-09-15",
    guests: [{ adults: 2 }],
  });
  assert.equal(incomplete.complete, false);
  assert.equal(incomplete.has_dates, false);

  const noGuests = isLiveSearchCriteriaComplete({
    destination: { country_code: "BE", city_key: "brussels" },
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    guests: [],
  });
  assert.equal(noGuests.complete, false);

  const ready = isLiveSearchCriteriaComplete({
    destination: { country_code: "BE", city_key: "brussels" },
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    guests: [{ adults: 2, children: [] }],
  });
  assert.equal(ready.complete, true);

  const blocked = shouldIssueRatehawkSearch({
    trigger: RATEHAWK_SEARCH_TRIGGERS.LIVE_SEARCH,
    criteria: incomplete,
    market: { ok: true },
  });
  assert.equal(blocked.issue, false);
  assert.equal(blocked.reason, "live_search_incomplete");
});

test("existing cards render immediately without a RateHawk request", () => {
  const plan = planImmediateExistingCards([
    { id: "approved-warwick-brussels", name: "Warwick Brussels" },
  ]);
  assert.equal(plan.render_immediately, true);
  assert.equal(plan.existing_cards.length, 1);
  assert.equal(plan.ratehawk.requested, false);
  assert.equal(plan.ratehawk.status, "not_requested");
});

test("hotels are deduplicated by hid", () => {
  const deduped = dedupeHotelsByHid([
    { hid: "8473727", name: "A" },
    { provider_id: "8473727", name: "A-dup" },
    { hid: "100", name: "B" },
    { hid: "", name: "drop" },
  ]);
  assert.deepEqual(
    deduped.map((item) => item.hid || item.provider_id),
    ["8473727", "100"],
  );
});

test("chunks use configurable limits and never invent pagination", () => {
  const limits = {
    ...RATEHAWK_DEFAULT_SEARCH_LIMITS,
    initial_hotel_limit: 2,
    load_more_increment: 2,
    absolute_maximum: 5,
  };
  const hids = ["1", "2", "3", "4", "5", "6"];
  const first = nextHotelIdChunk({
    hidList: hids,
    offset: 0,
    trigger: RATEHAWK_SEARCH_TRIGGERS.LIVE_SEARCH,
    limits,
  });
  assert.deepEqual(first.hids, ["1", "2"]);
  assert.equal(first.pagination_token, null);
  assert.equal(first.invented, false);
  assert.equal(first.has_more, true);

  const more = nextHotelIdChunk({
    hidList: hids,
    offset: first.next_offset,
    trigger: RATEHAWK_SEARCH_TRIGGERS.LOAD_MORE,
    limits,
  });
  assert.deepEqual(more.hids, ["3", "4"]);

  const last = nextHotelIdChunk({
    hidList: hids,
    offset: more.next_offset,
    trigger: RATEHAWK_SEARCH_TRIGGERS.LOAD_MORE,
    limits,
  });
  assert.deepEqual(last.hids, ["5"]);
  assert.equal(last.has_more, false);

  const empty = nextHotelIdChunk({
    hidList: [],
    trigger: RATEHAWK_SEARCH_TRIGGERS.LOAD_MORE,
    limits,
  });
  assert.deepEqual(empty.hids, []);
  assert.equal(empty.has_more, false);
  assert.equal(empty.invented, false);
});

test("short-lived rate cache is isolated from offline static content", () => {
  let now = 1_000;
  const rates = createRateCache({ nowFn: () => now, ttlMs: 1_000 });
  const staticStore = createStaticContentStore();
  assert.notEqual(rates.namespace, staticStore.namespace);
  assert.equal(staticStore.kind, "offline_sync");

  const key = rateCacheKey({
    hid: "8473727",
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    guestsDigest: "2a",
  });
  rates.set(key, { price_label: "EUR 180.00" });
  assert.equal(rates.get(key).price_label, "EUR 180.00");
  now = 2_100;
  assert.equal(rates.get(key), null);
});

test("debounce, cancellation and single-flight contracts", () => {
  const flight = createSearchFlightController({ debounceMs: 400 });
  assert.equal(flight.debounce_ms, 400);
  const pageOpen = flight.decide({
    key: "be:brussels:2026-09-15",
    trigger: RATEHAWK_SEARCH_TRIGGERS.PAGE_OPEN,
    ready: true,
  });
  assert.equal(pageOpen.start, false);

  const scheduled = flight.schedule("be:brussels:2026-09-15");
  assert.equal(scheduled.debounce_ms, 400);
  const gen = flight.markInFlight("be:brussels:2026-09-15");
  const again = flight.decide({
    key: "be:brussels:2026-09-15",
    trigger: RATEHAWK_SEARCH_TRIGGERS.LIVE_SEARCH,
    ready: true,
  });
  assert.equal(again.start, false);
  assert.equal(again.reason, "single_flight");

  flight.cancel();
  assert.equal(flight.isCancelled(gen), true);
  assert.equal(flight.inFlightKey(), null);
});

test("timeout and partial-result metadata does not invent pages", () => {
  const meta = annotateSearchResultMetadata({
    requestedHids: ["8473727", "100", "101"],
    receivedHids: ["8473727"],
    timedOut: true,
    elapsedMs: 30_000,
  });
  assert.equal(meta.timed_out, true);
  assert.equal(meta.partial, true);
  assert.equal(meta.requested_count, 3);
  assert.equal(meta.received_count, 1);
  assert.equal(meta.invented_pagination, false);
});

test("proposed first test-search request is hotels-by-hid and is not executed", () => {
  const request = buildProposedTestSearchRequest({
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    residency: "be",
    language: "en",
    guests: [{ adults: 2, children: [] }],
    timeout: 30,
  });
  assert.equal(request.executed, false);
  assert.equal(request.method, "POST");
  assert.equal(request.path, RATEHAWK_SERP_HOTELS_PATH);
  assert.equal(request.environment, "test");
  assert.deepEqual(request.body.hids, [Number(RATEHAWK_TEST_HOTEL_HID)]);
  assert.equal(request.body.checkin, "2026-09-15");
  assert.equal(request.body.checkout, "2026-09-16");
  assert.equal(request.url.startsWith("https://api.ratehawk.com"), true);
});

test("public destination resolves to exactly one enabled market or fails closed", () => {
  const empty = parseConfiguredSearchMarkets({});
  assert.deepEqual(empty.enabled_markets, []);
  assert.equal(
    resolvePublicSearchMarket(empty, { city: "Brussel", country: "BE" }).reason,
    "production_markets_unconfigured",
  );

  const config = exampleConfig();
  const brussels = resolvePublicSearchMarket(config, {
    city: "Brussel",
    country: "Belgium",
  });
  assert.equal(brussels.ok, true);
  assert.equal(brussels.market.city_key, "brussels");

  const missing = resolvePublicSearchMarket(config, {
    city: "Paris",
    country: "FR",
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, "unsupported_market");

  const ambiguousConfig = resolveMarketSearchConfig({}, {
    markets: [
      ...EXAMPLE_TEST_MARKETS,
      {
        country_code: "FR",
        city_key: "bruxelles-sud",
        aliases: ["brussels"],
        region_id: "1",
      },
    ],
  });
  const ambiguous = resolvePublicSearchMarket(ambiguousConfig, {
    city: "brussels",
  });
  assert.equal(ambiguous.ok, false);
  assert.equal(ambiguous.reason, "ambiguous_destination");
});

test("public search rejects client transport controls and out-of-bound dates", () => {
  assert.equal(hasForbiddenPublicSearchClientControl({ city: "Brussel" }), false);
  assert.equal(hasForbiddenPublicSearchClientControl({ region_id: "2395" }), true);
  assert.equal(hasForbiddenPublicSearchClientControl({ hid: 8473727 }), true);
  assert.equal(hasForbiddenPublicSearchClientControl({ host: "api.ratehawk.com" }), true);
  assert.equal(hasForbiddenPublicSearchClientControl({ latitude: 50.8 }), true);

  const now = Date.parse("2026-08-17T10:00:00Z");
  const ok = assertPublicSearchStayDates("2026-09-03", "2026-09-04", now);
  assert.equal(ok.ok, true);
  const longStay = assertPublicSearchStayDates("2026-09-03", "2026-10-20", now);
  assert.equal(longStay.ok, false);
  assert.equal(longStay.reason, "stay_dates_out_of_bounds");
});
