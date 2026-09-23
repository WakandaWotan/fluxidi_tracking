// Stay22 Europe P1C — opaque hotel Places pagination.
//
// Run:
//   node --test workers/booking/modules/google_places_pagination.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  EVENT_VENUE_GEOCODE_PREFIX,
  HOTEL_PLACES_CURSOR_PREFIX,
  HOTEL_PLACES_CURSOR_TTL_SECONDS,
  HOTEL_PLACES_MAX_PAGES,
  consumeHotelPlacesCursor,
  hotelPlacesCursorKey,
  googlePlacesSearchCenter,
  hotelPlacesQueryFingerprint,
  isHotelPlacesCursorKey,
  isUsableProviderToken,
  normalizeHotelPlacesCursorId,
  publicHotelPlacesPagination,
  readHotelPlacesCursor,
  sanitizeGooglePlacesLogDetails,
  storeHotelPlacesCursor,
  validateHotelPlacesCursorRecord,
} from "./google_places_pagination.mjs";
import { buildGooglePlacesTextQuery } from "./google_places_country.mjs";
import {
  fetchGooglePlacesTextSearchPage,
  resolveGooglePlacesHotelsSearch,
} from "./google_places_hotels_page.mjs";

function memoryKv() {
  const store = new Map();
  return {
    store,
    async get(key, opts) {
      const raw = store.get(String(key));
      if (raw == null) return null;
      if (opts?.type === "json") return JSON.parse(raw);
      return raw;
    },
    async put(key, value) {
      store.set(String(key), String(value));
    },
    async delete(key) {
      store.delete(String(key));
    },
  };
}

function googlePayload(results, nextPageToken = "") {
  return {
    status: results.length ? "OK" : "ZERO_RESULTS",
    results,
    next_page_token: nextPageToken || undefined,
  };
}

function lodging(id, name) {
  return {
    place_id: id,
    name,
    formatted_address: `${name}, Portugal`,
    geometry: { location: { lat: 38.7, lng: -9.1 } },
    rating: 4.4,
    user_ratings_total: 120,
    types: ["lodging", "hotel"],
  };
}

function httpError(status) {
  return { __httpError: status };
}

function mockFetch(sequence) {
  const calls = [];
  const requests = [];
  const fetchImpl = async (url, init) => {
    calls.push(String(url));
    requests.push({
      url: String(url),
      method: String(init?.method || "GET"),
      headers: init?.headers || {},
      body: String(init?.body || ""),
    });
    const next = sequence.shift();
    if (!next) {
      return {
        ok: true,
        status: 200,
        json: async () => googlePayload([]),
      };
    }
    if (next.__httpError) {
      return {
        ok: false,
        status: next.__httpError,
        json: async () => ({ error: { code: next.__httpError } }),
      };
    }
    return {
      ok: true,
      status: 200,
      json: async () => next,
    };
  };
  fetchImpl.calls = calls;
  fetchImpl.requests = requests;
  return fetchImpl;
}

function firstPageQuery() {
  return {
    source: "google-places",
    country_code: "PT",
    countryCode: "PT",
    country: "Portugal",
    city: "Lisbon",
    region: "Lisbon District",
    destination: "",
    searchText: "",
  };
}

test("old first-page requests remain compatible and cap at 20 rows", async () => {
  const results = Array.from({ length: 25 }, (_, i) =>
    lodging(`p${i}`, `Hotel ${i}`),
  );
  const fetchImpl = mockFetch([googlePayload(results)]);
  const resolved = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: { GOOGLE_PLACES_API_KEY: "test-key-not-for-production" },
    fetchImpl,
  });
  assert.equal(resolved.ok, true);
  assert.equal(resolved.http_status, 200);
  assert.equal(resolved.places.length, 20);
  assert.equal(resolved.pagination.page, 1);
  assert.equal(resolved.pagination.has_more, false);
  assert.equal(resolved.pagination.next_cursor, null);
  assert.equal(resolved.pagination.max_pages, HOTEL_PLACES_MAX_PAGES);
  const json = JSON.stringify(resolved);
  assert.equal(json.includes("test-key-not-for-production"), false);
  assert.equal(json.includes("maps.googleapis.com"), false);
});

test("first page can return an opaque cursor without the provider token", async () => {
  const kv = memoryKv();
  const fetchImpl = mockFetch([
    googlePayload([lodging("a", "A")], "provider_token_page2_secret"),
  ]);
  const resolved = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: {
      GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
      BOOKING_KV: kv,
    },
    fetchImpl,
    nowMs: 1_000_000,
  });
  assert.equal(resolved.ok, true);
  assert.equal(resolved.pagination.has_more, true);
  assert.ok(resolved.pagination.next_cursor);
  assert.equal(
    normalizeHotelPlacesCursorId(resolved.pagination.next_cursor).length >= 16,
    true,
  );
  const body = JSON.stringify(resolved);
  assert.equal(body.includes("provider_token_page2_secret"), false);
  assert.equal(body.includes("test-key-not-for-production"), false);
  const keys = [...kv.store.keys()];
  assert.equal(keys.length, 1);
  assert.equal(keys[0].startsWith(HOTEL_PLACES_CURSOR_PREFIX), true);
  assert.equal(keys[0].startsWith(EVENT_VENUE_GEOCODE_PREFIX), false);
  const stored = JSON.parse(kv.store.get(keys[0]));
  assert.equal(stored.provider_token, "provider_token_page2_secret");
  assert.equal(stored.page, 2);
  assert.equal(stored.country_code, "PT");
  assert.equal(HOTEL_PLACES_CURSOR_TTL_SECONDS, 600);
});

test("premature cursor use does not call Google", async () => {
  const kv = memoryKv();
  const firstFetch = mockFetch([
    googlePayload([lodging("a", "A")], "provider_token_page2_secret"),
  ]);
  const first = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: {
      GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
      BOOKING_KV: kv,
    },
    fetchImpl: firstFetch,
    nowMs: 5_000,
  });
  const secondFetch = mockFetch([googlePayload([lodging("b", "B")])]);
  const second = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: first.pagination.next_cursor },
    env: {
      GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
      BOOKING_KV: kv,
    },
    fetchImpl: secondFetch,
    nowMs: 5_500,
  });
  assert.equal(second.ok, false);
  assert.equal(second.http_status, 425);
  assert.equal(second.error, "cursor_not_ready");
  assert.equal(second.google_called, false);
  assert.equal(secondFetch.calls.length, 0);
});

test("valid cursor requests page 2 and returns no page-3 cursor", async () => {
  const kv = memoryKv();
  const first = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: {
      GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
      BOOKING_KV: kv,
    },
    fetchImpl: mockFetch([
      googlePayload([lodging("a", "A")], "provider_token_page2_secret"),
    ]),
    nowMs: 10_000,
  });
  const page2Fetch = mockFetch([
    googlePayload(
      [lodging("b", "B"), lodging("b", "B-dup")],
      "should_never_be_exposed",
    ),
  ]);
  const second = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: first.pagination.next_cursor },
    env: {
      GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
      BOOKING_KV: kv,
    },
    fetchImpl: page2Fetch,
    nowMs: 13_000,
  });
  assert.equal(second.ok, true);
  assert.equal(second.http_status, 200);
  assert.equal(second.pagination.page, 2);
  assert.equal(second.pagination.has_more, false);
  assert.equal(second.pagination.next_cursor, null);
  assert.equal(second.preserved_country_code, "PT");
  assert.equal(
    second.preserved_fingerprint,
    hotelPlacesQueryFingerprint(firstPageQuery()),
  );
  assert.equal(page2Fetch.calls.length, 1);
  assert.equal(page2Fetch.calls[0].includes("pagetoken="), true);
  assert.equal(JSON.stringify(second).includes("should_never_be_exposed"), false);
  assert.equal(JSON.stringify(second).includes("provider_token_page2_secret"), false);
});

test("unknown, malformed, expired and consumed cursors are rejected", async () => {
  const kv = memoryKv();
  const env = {
    GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
    BOOKING_KV: kv,
  };
  const unknown = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: "aaaaaaaaaaaaaaaaaaaa" },
    env,
    fetchImpl: mockFetch([]),
    nowMs: 20_000,
  });
  assert.equal(unknown.ok, false);
  assert.equal(unknown.error, "unknown_cursor");

  const malformed = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: "bad" },
    env,
    fetchImpl: mockFetch([]),
    nowMs: 20_000,
  });
  assert.equal(malformed.ok, false);
  assert.equal(malformed.error, "malformed_cursor");
  assert.equal(malformed.google_called, false);

  const stored = await storeHotelPlacesCursor(
    env,
    {
      providerToken: "provider_token_page2_secret",
      fingerprint: hotelPlacesQueryFingerprint(firstPageQuery()),
      countryCode: "PT",
      issuedAtMs: 1_000,
      availableAtMs: 1_000,
      page: 2,
    },
    { nowMs: 1_000 },
  );
  const expired = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: stored.cursor },
    env,
    fetchImpl: mockFetch([googlePayload([lodging("z", "Z")])]),
    nowMs: 1_000 + HOTEL_PLACES_CURSOR_TTL_SECONDS * 1000 + 5,
  });
  assert.equal(expired.ok, false);
  assert.equal(expired.error, "expired_cursor");
  assert.equal(expired.google_called, false);

  const fresh = await storeHotelPlacesCursor(
    env,
    {
      providerToken: "provider_token_page2_secret",
      fingerprint: hotelPlacesQueryFingerprint(firstPageQuery()),
      countryCode: "PT",
      issuedAtMs: 50_000,
      availableAtMs: 50_000,
      page: 2,
    },
    { nowMs: 50_000 },
  );
  const firstUse = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: fresh.cursor },
    env,
    fetchImpl: mockFetch([googlePayload([lodging("c", "C")])]),
    nowMs: 52_000,
  });
  assert.equal(firstUse.ok, true);
  const replay = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: fresh.cursor },
    env,
    fetchImpl: mockFetch([googlePayload([lodging("d", "D")])]),
    nowMs: 53_000,
  });
  assert.equal(replay.ok, false);
  assert.equal(["consumed_cursor", "unknown_cursor"].includes(replay.error), true);
  assert.equal(replay.google_called, false);
});

test("conflicting cursor query is rejected and does not become a first page", async () => {
  const kv = memoryKv();
  const env = {
    GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
    BOOKING_KV: kv,
  };
  const first = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env,
    fetchImpl: mockFetch([
      googlePayload([lodging("a", "A")], "provider_token_page2_secret"),
    ]),
    nowMs: 80_000,
  });
  const fetchImpl = mockFetch([googlePayload([lodging("x", "Spain")])]);
  const conflict = await resolveGooglePlacesHotelsSearch({
    query: {
      ...firstPageQuery(),
      country_code: "ES",
      countryCode: "ES",
      country: "Spain",
      cursor: first.pagination.next_cursor,
    },
    env,
    fetchImpl,
    nowMs: 83_000,
  });
  assert.equal(conflict.ok, false);
  assert.equal(conflict.error, "conflicting_cursor_query");
  assert.equal(conflict.google_called, false);
  assert.equal(fetchImpl.calls.length, 0);
});

test("empty page-2 results stay safe and logs never include secrets", async () => {
  const kv = memoryKv();
  const first = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: {
      GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
      BOOKING_KV: kv,
    },
    fetchImpl: mockFetch([
      googlePayload([lodging("a", "A")], "provider_token_page2_secret"),
    ]),
    nowMs: 90_000,
  });
  const second = await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), cursor: first.pagination.next_cursor },
    env: {
      GOOGLE_PLACES_API_KEY: "test-key-not-for-production",
      BOOKING_KV: kv,
    },
    fetchImpl: mockFetch([googlePayload([])]),
    nowMs: 93_000,
  });
  assert.equal(second.ok, true);
  assert.deepEqual(second.places, []);
  assert.equal(second.pagination.has_more, false);
  const sanitized = sanitizeGooglePlacesLogDetails({
    status: 200,
    key: "test-key-not-for-production",
    token: "provider_token_page2_secret",
    url: "https://maps.googleapis.com/maps/api/place/textsearch/json?key=test",
  });
  assert.equal(sanitized.status, 200);
  assert.equal(Object.prototype.hasOwnProperty.call(sanitized, "key"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(sanitized, "token"), false);
  assert.equal(Object.prototype.hasOwnProperty.call(sanitized, "url"), false);
});

test("cursor helpers stay namespaced away from Events geocode keys", () => {
  assert.equal(isHotelPlacesCursorKey(`${HOTEL_PLACES_CURSOR_PREFIX}abc`), true);
  assert.equal(isHotelPlacesCursorKey(`${EVENT_VENUE_GEOCODE_PREFIX}abc`), false);
  assert.equal(hotelPlacesCursorKey("bad"), "");
  assert.ok(publicHotelPlacesPagination({ page: 2 }).next_cursor === null);
});

test("read after consume cannot reuse the provider token", async () => {
  const kv = memoryKv();
  const env = { BOOKING_KV: kv };
  const stored = await storeHotelPlacesCursor(
    env,
    {
      providerToken: "provider_token_page2_secret",
      fingerprint: "fp",
      countryCode: "PT",
      issuedAtMs: 1,
      availableAtMs: 1,
      page: 2,
    },
    { nowMs: 1 },
  );
  const loaded = await readHotelPlacesCursor(env, stored.cursor);
  await consumeHotelPlacesCursor(env, loaded.key, loaded.record);
  const again = await readHotelPlacesCursor(env, stored.cursor);
  if (again.ok) {
    const validated = validateHotelPlacesCursorRecord(again.record, { nowMs: 2 });
    assert.equal(validated.ok, false);
  } else {
    assert.equal(again.error, "unknown_cursor");
  }
});

test("real-size Google page tokens are accepted, junk is still rejected", async () => {
  // Production returned an 847-character token for "hotels in Paris, France";
  // the previous 800-character bound dropped it and page 2 never appeared.
  const realistic = `A${"aZ9_-".repeat(169)}`;
  assert.equal(realistic.length, 846);
  assert.equal(isUsableProviderToken(realistic), true);
  assert.equal(isUsableProviderToken(`${realistic}==`), true);

  assert.equal(isUsableProviderToken("short"), false);
  assert.equal(isUsableProviderToken(`tok${"!".repeat(20)}`), false);
  assert.equal(isUsableProviderToken("a".repeat(5000)), false);

  const kv = memoryKv();
  const env = { BOOKING_KV: kv };
  const stored = await storeHotelPlacesCursor(
    env,
    {
      providerToken: realistic,
      fingerprint: "fp",
      countryCode: "FR",
      issuedAtMs: 1,
      availableAtMs: 1,
      page: 2,
    },
    { nowMs: 1 },
  );
  assert.equal(stored.ok, true);
});

test("a dropped cursor is reported instead of looking like no page 2", async () => {
  const oversized = "a".repeat(5000);
  const noKv = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: { GOOGLE_PLACES_API_KEY: "k" },
    fetchImpl: mockFetch([googlePayload([lodging("a", "A")], oversized)]),
    nowMs: 1_000,
  });
  assert.equal(noKv.pagination.has_more, false);
  assert.ok(noKv.warnings.includes("hotel_places_cursor_missing_kv"));

  const rejected = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: { GOOGLE_PLACES_API_KEY: "k", BOOKING_KV: memoryKv() },
    fetchImpl: mockFetch([googlePayload([lodging("a", "A")], oversized)]),
    nowMs: 1_000,
  });
  assert.equal(rejected.pagination.has_more, false);
  assert.ok(rejected.warnings.includes("hotel_places_token_rejected"));

  const absent = await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: { GOOGLE_PLACES_API_KEY: "k", BOOKING_KV: memoryKv() },
    fetchImpl: mockFetch([googlePayload([lodging("a", "A")])]),
    nowMs: 1_000,
  });
  assert.equal(absent.pagination.has_more, false);
  assert.ok(absent.warnings.includes("google_places_no_next_page_token"));
});

test("coordinates use nearby search; text search ignores lat and radius", async () => {
  const textOnly = mockFetch([googlePayload([lodging("a", "Lisbon Hotel")])]);
  await resolveGooglePlacesHotelsSearch({
    query: firstPageQuery(),
    env: { GOOGLE_PLACES_API_KEY: "test-key-not-for-production" },
    fetchImpl: textOnly,
  });
  const textUrl = new URL(textOnly.calls[0]);
  assert.equal(textUrl.pathname, "/maps/api/place/textsearch/json");
  assert.equal(textUrl.searchParams.get("query"), buildGooglePlacesTextQuery(firstPageQuery()));
  assert.equal(textUrl.searchParams.has("location"), false);
  assert.equal(textUrl.searchParams.has("radius"), false);
  assert.equal(textUrl.searchParams.get("type"), "lodging");

  const zeroFetch = mockFetch([googlePayload([lodging("z", "Zero")])]);
  await resolveGooglePlacesHotelsSearch({
    query: { ...firstPageQuery(), latitude: 0, longitude: 0, radiusKm: 15 },
    env: { GOOGLE_PLACES_API_KEY: "test-key-not-for-production" },
    fetchImpl: zeroFetch,
  });
  assert.equal(new URL(zeroFetch.calls[0]).pathname, "/maps/api/place/textsearch/json");

  const spirit = {
    source: "google-places",
    countryCode: "BE",
    country: "Belgium",
    destination: "Place du Martyr, 16, Verviers, Belgium",
    searchText: "Spirit of 66",
    latitude: 50.59353,
    longitude: 5.86109,
    radiusKm: 15,
  };
  const nearbyFetch = mockFetch([
    {
      places: [
        {
          id: "v",
          displayName: { text: "Van der Valk Hotel Verviers" },
          formattedAddress: "Rue de la Station 4, Verviers",
          location: { latitude: 50.5918, longitude: 5.8634 },
          rating: 4.2,
          userRatingCount: 80,
          primaryType: "hotel",
          types: ["lodging", "hotel"],
          photos: [
            {
              name: "places/v/photos/Abcdefghijklmnop",
              authorAttributions: [{ displayName: "A Google user" }],
            },
          ],
        },
      ],
    },
  ]);
  const kv = memoryKv();
  const first = await resolveGooglePlacesHotelsSearch({
    query: spirit,
    env: { GOOGLE_PLACES_API_KEY: "test-key-not-for-production", BOOKING_KV: kv },
    fetchImpl: nearbyFetch,
    nowMs: 50_000,
  });
  const nearbyRequest = nearbyFetch.requests[0];
  const nearbyUrl = new URL(nearbyRequest.url);
  assert.equal(nearbyUrl.hostname, "places.googleapis.com");
  assert.equal(nearbyUrl.pathname, "/v1/places:searchNearby");
  assert.equal(nearbyUrl.search, "");
  assert.equal(nearbyRequest.method, "POST");
  assert.equal(nearbyRequest.headers["X-Goog-Api-Key"], "test-key-not-for-production");
  assert.equal(nearbyRequest.headers["X-Goog-FieldMask"].includes("places.photos"), true);
  const nearbyBody = JSON.parse(nearbyRequest.body);
  assert.deepEqual(nearbyBody.includedTypes, ["lodging"]);
  assert.equal(nearbyBody.locationRestriction.circle.center.latitude, 50.59353);
  assert.equal(nearbyBody.locationRestriction.circle.center.longitude, 5.86109);
  assert.equal(nearbyBody.locationRestriction.circle.radius, 15000);
  assert.equal(nearbyRequest.body.includes("Spirit of 66"), false);
  assert.equal(nearbyRequest.body.includes("Place du Martyr"), false);
  assert.equal(nearbyFetch.calls.length, 1);
  assert.equal(first.places[0].displayName.text, "Van der Valk Hotel Verviers");
  assert.equal(first.places[0].photos[0].name, "places/v/photos/Abcdefghijklmnop");
  assert.equal(googlePlacesSearchCenter(spirit).radiusMeters, 15000);
  assert.equal(googlePlacesSearchCenter({ latitude: 50.59, longitude: 5.86, radiusKm: 80 }).radiusMeters, 50000);
  assert.equal(googlePlacesSearchCenter({ latitude: 50.59, longitude: 5.86, radiusKm: 0.1 }).radiusMeters, 1000);
  assert.equal(googlePlacesSearchCenter({ lat: 50.847232, lng: 4.348831 }).radiusMeters, 15000);

  const brussels = { ...spirit, latitude: 50.847232, longitude: 4.348831, destination: "", searchText: "" };
  assert.notEqual(
    hotelPlacesQueryFingerprint(spirit),
    hotelPlacesQueryFingerprint(brussels),
  );
  assert.notEqual(
    hotelPlacesQueryFingerprint(spirit),
    hotelPlacesQueryFingerprint(firstPageQuery()),
  );

  const fallback = mockFetch([
    httpError(403),
    googlePayload([lodging("v", "Van der Valk Hotel Verviers")]),
    {
      status: "OK",
      result: {
        photos: [
          {
            photo_reference: "Abcdefghijklmnop",
            html_attributions: ["<a href=\"https://example.test\">A Google user</a>"],
          },
        ],
      },
    },
  ]);
  const fellBack = await resolveGooglePlacesHotelsSearch({
    query: spirit,
    env: { GOOGLE_PLACES_API_KEY: "test-key-not-for-production" },
    fetchImpl: fallback,
  });
  assert.equal(fellBack.places[0].name, "Van der Valk Hotel Verviers");
  assert.equal(fellBack.places[0].photos[0].photo_reference, "Abcdefghijklmnop");
  assert.equal(new URL(fallback.calls[1]).pathname, "/maps/api/place/nearbysearch/json");
  const detailsUrl = new URL(fallback.calls[2]);
  assert.equal(detailsUrl.pathname, "/maps/api/place/details/json");
  assert.equal(detailsUrl.searchParams.get("place_id"), "v");
  assert.equal(detailsUrl.searchParams.get("fields"), "photo");
  assert.equal(detailsUrl.searchParams.get("key"), "test-key-not-for-production");
  assert.equal(JSON.stringify(fellBack).includes("test-key-not-for-production"), false);

  const page2 = mockFetch([googlePayload([lodging("v2", "Hotel des Ardennes")])]);
  await fetchGooglePlacesTextSearchPage({
    query: spirit,
    apiKey: "test-key-not-for-production",
    pageToken: "provider_token_page2_secret",
    fetchImpl: page2,
  });
  const page2Url = new URL(page2.calls[0]);
  assert.equal(page2Url.pathname, "/maps/api/place/nearbysearch/json");
  assert.equal(page2Url.searchParams.get("location"), "50.59353,5.86109");
  assert.equal(page2Url.searchParams.get("radius"), "15000");
  assert.equal(page2Url.searchParams.get("pagetoken"), "provider_token_page2_secret");
  assert.equal(String(page2Url).includes("Spirit of 66"), false);
});
