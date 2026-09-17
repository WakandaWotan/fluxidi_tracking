import test from "node:test";
import assert from "node:assert/strict";
import {
  shouldFanOutAllCategories,
  mergePublicEvents,
  isRealPublicEvent,
  ticketmasterLocale,
  normalizeEventCountry,
  publicEventsCacheKey,
  readPublicEventsCache,
  writePublicEventsCache,
  clearPublicEventsCache,
  ALL_CATEGORY_CLASSIFICATIONS,
  FLUXIDI_LAUNCH_EVENT_COUNTRIES,
  FLUXIDI_EVENT_MARKET_KEYS,
  FLUXIDI_EVENT_MARKETS_SOURCE,
  FLUXIDI_TM_PROVEN_EXTRA_COUNTRIES,
  eventDedupeKey,
  ticketmasterDiscoveryAttempts,
  isLuxembourgEvent,
  luxembourgNeighborQueries,
} from "./public_events_search_plan.mjs";

test("UK becomes GB for Ticketmaster, launch list is 18 selectable event countries", () => {
  assert.equal(normalizeEventCountry("UK"), "GB");
  assert.equal(normalizeEventCountry("", "uk"), "GB");
  assert.equal(ticketmasterLocale("ES"), "es-es");
  assert.equal(ticketmasterLocale("FR"), "fr-fr");
  assert.equal(ticketmasterLocale("IT"), "it-it");
  assert.deepEqual(FLUXIDI_LAUNCH_EVENT_COUNTRIES, [
    "BE",
    "NL",
    "FR",
    "GB",
    "DE",
    "LU",
    "ES",
    "PT",
    "IT",
    "AT",
    "IE",
    "CH",
    "DK",
    "SE",
    "NO",
    "FI",
    "PL",
    "CZ",
  ]);
  assert.deepEqual(FLUXIDI_EVENT_MARKET_KEYS, [
    "be",
    "nl",
    "fr",
    "uk",
    "de",
    "lu",
    "es",
    "pt",
    "it",
    "at",
    "ie",
    "ch",
    "dk",
    "se",
    "no",
    "fi",
    "pl",
    "cz",
  ]);
  assert.equal(FLUXIDI_EVENT_MARKET_KEYS.length, 18);
  assert.ok(FLUXIDI_EVENT_MARKET_KEYS.includes("dk"));
  assert.deepEqual(FLUXIDI_TM_PROVEN_EXTRA_COUNTRIES, []);
});

test("empty category and keyword must fan out, music must not", () => {
  assert.equal(shouldFanOutAllCategories({ category: "", keyword: "" }), true);
  assert.equal(shouldFanOutAllCategories({ category: "music" }), false);
  assert.equal(shouldFanOutAllCategories({ keyword: "madrid" }), false);
  assert.ok(ALL_CATEGORY_CLASSIFICATIONS.length >= 4);
});

test("seed rows and incomplete rows are not real events", () => {
  assert.equal(
    isRealPublicEvent({
      id: "seed",
      title: "Antwerp Jazz",
      provider: "worker_seed",
      starts_at_utc: "2026-06-12T17:30:00.000Z",
      city: "Antwerpen",
    }),
    false,
  );
  assert.equal(
    isRealPublicEvent({
      id: "tm_1",
      title: "Concert",
      provider: "ticketmaster",
      starts_at_utc: "2026-10-01T18:00:00.000Z",
      city: "Madrid",
    }),
    true,
  );
  assert.equal(
    isRealPublicEvent({
      id: "tm_2",
      title: "No date",
      provider: "ticketmaster",
      city: "Paris",
    }),
    false,
  );
});

test("event catalog source is independent of company registration", () => {
  assert.match(FLUXIDI_EVENT_MARKETS_SOURCE, /independent of company/);
  assert.match(FLUXIDI_EVENT_MARKETS_SOURCE, /not full Europe/);
  assert.ok(ticketmasterDiscoveryAttempts({ country: "FR" }).some((row) => row.id === "minimal"));
});

test("distinct showtimes with the same id stay separate", () => {
  const merged = mergePublicEvents(
    [
      [
        {
          id: "show",
          title: "Evening",
          provider: "ticketmaster",
          starts_at_utc: "2026-10-01T19:00:00.000Z",
          city: "Paris",
        },
        {
          id: "show",
          title: "Matinee",
          provider: "ticketmaster",
          starts_at_utc: "2026-10-01T14:00:00.000Z",
          city: "Paris",
        },
      ],
    ],
    50,
  );
  assert.equal(merged.length, 2);
  assert.notEqual(eventDedupeKey(merged[0]), eventDedupeKey(merged[1]));
});

test("merge dedupes and keeps earliest dates within the cap", () => {
  const merged = mergePublicEvents(
    [
      [
        {
          id: "a",
          title: "Later",
          provider: "ticketmaster",
          starts_at_utc: "2026-12-01T18:00:00.000Z",
          city: "Madrid",
        },
        {
          id: "b",
          title: "Sooner",
          provider: "ticketmaster",
          starts_at_utc: "2026-10-01T18:00:00.000Z",
          city: "Barcelona",
        },
      ],
      [
        {
          id: "a",
          title: "Later duplicate",
          provider: "ticketmaster",
          starts_at_utc: "2026-12-01T18:00:00.000Z",
          city: "Madrid",
        },
      ],
    ],
    50,
  );
  assert.equal(merged.length, 2);
  assert.equal(merged[0].id, "b");
});

test("Luxembourg neighbor queries relax country match and keep a city keyword", () => {
  const neighbors = luxembourgNeighborQueries({ country: "LU", market: "lu", dateMode: "year", limit: 50 });
  assert.deepEqual(
    neighbors.map((item) => item.country),
    ["BE", "FR", "DE"],
  );
  assert.equal(neighbors[0].keyword, "luxembourg");
  assert.equal(neighbors[0].relaxCountryMatch, true);
  assert.equal(
    isLuxembourgEvent({
      id: "lu_1",
      title: "Concert",
      provider: "ticketmaster",
      starts_at_utc: "2026-10-01T18:00:00.000Z",
      city: "Luxembourg",
      country_code: "BE",
    }),
    true,
  );
  assert.equal(
    isLuxembourgEvent({
      id: "be_1",
      title: "Concert",
      provider: "ticketmaster",
      starts_at_utc: "2026-10-01T18:00:00.000Z",
      city: "Brussel",
      country_code: "BE",
    }),
    false,
  );
});

test("memory cache expires by key", () => {
  clearPublicEventsCache();
  const key = publicEventsCacheKey({ country: "ES", dateMode: "year", limit: 50 });
  writePublicEventsCache(key, { events: [1] });
  assert.equal(readPublicEventsCache(key).events[0], 1);
  clearPublicEventsCache();
  assert.equal(readPublicEventsCache(key), null);
});
