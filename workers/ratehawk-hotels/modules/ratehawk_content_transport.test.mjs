// RATEHAWK-P2 single-hid content transport
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_content_transport.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { runTaxiBookingIsolationProbe } from "../../booking/modules/ratehawk_hotels_facade.mjs";
import {
  RATEHAWK_CONTENT_STRATEGIES,
  isRatehawkBatchContentStrategyEnabled,
  resolveRatehawkContentStrategy,
} from "./ratehawk_content_strategy.mjs";
import {
  applyOfflineContentWrite,
  assertContentOperationAllowed,
  createMemoryContentStore,
  isRatehawkFullDumpRequest,
  livePriceKeysPresent,
  normalizeOfflineHotelProjection,
  planScopedContentSync,
  shouldRunRatehawkContentSync,
  toPublicStaticHotelCard,
} from "./ratehawk_content_sync.mjs";
import {
  executeRatehawkContentJob,
  executeRatehawkContentJobs,
  fetchRatehawkHotelInfo,
} from "./ratehawk_content_transport.mjs";
import {
  createRatehawkQuotaBinding,
  reserveRatehawkProviderQuota,
  resolveRatehawkProviderQuotaConfig,
} from "./ratehawk_provider_quota.mjs";

const TEST_HOTEL = Object.freeze({
  hid: 8473727,
  id: "test_hotel_legacy",
  name: "Warwick Brussels",
  address: "Rue Duquesnoy 5",
  latitude: 50.845,
  longitude: 4.3543,
  star_rating: 4,
  kind: "Hotel",
  star_certificate: {},
  description_struct: [{ title: "Location" }, { title: "Rooms" }],
  images: [{ url: "https://img.example/licensed.jpg" }],
  images_ext: [{ url: "https://img.example/licensed-ext.jpg" }],
  amenity_groups: [
    { group_name: "General", amenities: ["Wi-Fi"] },
    { group_name: "Services", amenities: ["24-hour reception"] },
    { group_name: "Room", amenities: ["Air conditioning"] },
    { group_name: "Other", amenities: ["Lift"] },
  ],
  room_groups: Array.from({ length: 13 }, (_, i) => ({
    name: `Room ${i + 1}`,
    room_amenities: ["Wi-Fi", "Safe"],
  })),
  check_in_time: "15:00:00",
  check_out_time: "12:00:00",
  metapolicy_extra_info: "Important hotel information for guests.",
  policy_struct: Array.from({ length: 6 }, (_, i) => ({ title: `Policy ${i + 1}` })),
  email: "restricted@example.test",
  phone: "+32000000000",
  metapolicy_struct: {
    children: [{}, {}, {}],
    cot: [{}],
    extra_bed: [{}],
    internet: [{}, {}],
    parking: [{}],
    deposit: [{}, {}, {}],
    no_show: { amount: "1", currency: "EUR", from_time: "18:00:00" },
    children_meal: [],
    shuttle: [],
    visa: [],
  },
});

function contentEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: "test-key",
    RATEHAWK_API_KEY: "test-api-secret-do-not-leak",
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_ENABLED: "1",
    RATEHAWK_CONTENT_SYNC_ENABLED: "1",
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

function okResponse(hotel = TEST_HOTEL, headers = {}) {
  return {
    status: 200,
    headers: {
      get(name) {
        return headers[name] ?? headers[String(name).toLowerCase()] ?? null;
      },
    },
    json: async () => ({ status: "ok", error: null, data: hotel }),
  };
}

test("1. batch strategy remains disabled", () => {
  const batch = resolveRatehawkContentStrategy("batch_content_by_ids");
  assert.equal(batch.ok, false);
  assert.equal(batch.available, false);
  assert.equal(batch.fallback_used, false);
  assert.equal(batch.reason, "batch_content_by_ids_unavailable");
  assert.equal(isRatehawkBatchContentStrategyEnabled(), false);
  const planned = planScopedContentSync({
    strategy: RATEHAWK_CONTENT_STRATEGIES.BATCH_CONTENT_BY_IDS,
    markets: [
      {
        country_code: "BE",
        city_key: "brussels",
        region_id: "test-region-example-not-production",
      },
    ],
    hidLists: { "BE:brussels": [8473727] },
    locales: ["en"],
  });
  assert.equal(planned.ok, false);
  assert.deepEqual(planned.jobs, []);
  assert.equal(planned.provider_requested, false);
});

test("2. full custom and incremental dumps are forbidden", () => {
  assert.equal(isRatehawkFullDumpRequest("/api/b2b/v3/hotel/info/dump/"), true);
  assert.equal(isRatehawkFullDumpRequest("/api/b2b/v3/hotel/info/incremental_dump/"), true);
  assert.equal(isRatehawkFullDumpRequest("custom_dump"), true);
  assert.equal(assertContentOperationAllowed("dump_all").ok, false);
});

test("3. one job produces exactly one hid and one locale", () => {
  const planned = planScopedContentSync({
    markets: [
      {
        country_code: "BE",
        city_key: "brussels",
        region_id: "test-region-example-not-production",
      },
    ],
    hidLists: { "BE:brussels": [8473727] },
    locales: ["en"],
  });
  assert.equal(planned.jobs.length, 1);
  assert.equal(planned.jobs[0].hid, 8473727);
  assert.equal(planned.jobs[0].locale, "en");
  assert.deepEqual(planned.jobs[0].hids, [8473727]);
  assert.equal(planned.jobs[0].strategy, "single_hid_info");
});

test("4. invalid hid or locale produces zero transport", async () => {
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return okResponse();
  };
  const env = contentEnv();
  const badHid = await fetchRatehawkHotelInfo({
    env,
    hid: "not-a-hid",
    language: "en",
    fetchImpl,
  });
  const badLocale = await fetchRatehawkHotelInfo({
    env,
    hid: 8473727,
    language: "de",
    fetchImpl,
  });
  assert.equal(badHid.invoked, false);
  assert.equal(badHid.reason, "invalid_hid");
  assert.equal(badLocale.invoked, false);
  assert.equal(badLocale.reason, "locale_unsupported");
  assert.equal(calls, 0);
});

test("5. customer requests cannot invoke content", async () => {
  let calls = 0;
  const env = contentEnv();
  const result = await executeRatehawkContentJob({
    env,
    job: { hid: 8473727, locale: "en", strategy: "single_hid_info" },
    trigger: "view_stay",
    fetchImpl: async () => {
      calls += 1;
      return okResponse();
    },
  });
  assert.equal(result.invoked, false);
  assert.equal(result.reason, "content_sync_forbidden_on_customer_request");
  assert.equal(shouldRunRatehawkContentSync({ trigger: "prebook", env }).run, false);
  assert.equal(calls, 0);
});

test("6. quota denial produces zero transport", async () => {
  const env = contentEnv({
    RATEHAWK_QUOTA_HOTEL_CONTENT_LIMIT: "1",
    RATEHAWK_QUOTA_HOTEL_CONTENT_WINDOW_SECONDS: "60",
  });
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return okResponse();
  };
  const first = await executeRatehawkContentJob({
    env,
    job: { hid: 8473727, locale: "en", strategy: "single_hid_info" },
    fetchImpl,
    now: 1_000,
  });
  const second = await executeRatehawkContentJob({
    env,
    job: { hid: 8473727, locale: "nl", strategy: "single_hid_info" },
    fetchImpl,
    now: 1_100,
  });
  assert.equal(first.invoked, true);
  assert.equal(second.invoked, false);
  assert.equal(second.requeue, true);
  assert.equal(second.busy_loop, false);
  assert.equal(calls, 1);
});

test("7. missing production quota fails closed", async () => {
  const config = resolveRatehawkProviderQuotaConfig({
    RATEHAWK_ENVIRONMENT: "production",
  });
  assert.equal(config.ok, false);
  const reserved = await reserveRatehawkProviderQuota({
    env: { RATEHAWK_ENVIRONMENT: "production" },
    endpoint: "hotel_content",
  });
  assert.equal(reserved.allowed, false);
  assert.equal(reserved.reason, "production_quota_unconfigured");
});

test("8. timeout and provider errors are redacted", async () => {
  const env = contentEnv();
  const timeout = await fetchRatehawkHotelInfo({
    env,
    hid: 8473727,
    language: "en",
    timeoutMs: 20,
    fetchImpl: (_url, options) =>
      new Promise((_, reject) => {
        options?.signal?.addEventListener("abort", () => {
          const err = new Error("aborted");
          err.name = "AbortError";
          reject(err);
        });
      }),
  });
  assert.equal(timeout.reason, "timeout");
  assert.equal(timeout.invoked, true);
  assert.equal(JSON.stringify(timeout).includes("test-api-secret-do-not-leak"), false);
  const errored = await executeRatehawkContentJob({
    env,
    job: { hid: 8473727, locale: "en", strategy: "single_hid_info" },
    fetchImpl: async () => ({
      status: 500,
      headers: { get: () => null },
      json: async () => ({
        status: "error",
        error: "provider_error",
        leak: "test-api-secret-do-not-leak",
      }),
    }),
  });
  assert.equal(errored.invoked, true);
  assert.equal(JSON.stringify(errored).includes("test-api-secret-do-not-leak"), false);
});

test("9. no automatic retry", async () => {
  const env = contentEnv();
  let calls = 0;
  await executeRatehawkContentJob({
    env,
    job: { hid: 8473727, locale: "en", strategy: "single_hid_info" },
    fetchImpl: async () => {
      calls += 1;
      return {
        status: 500,
        headers: { get: () => null },
        json: async () => ({ status: "error", error: "provider_error" }),
      };
    },
  });
  assert.equal(calls, 1);
});

test("10. all observed test-hotel categories normalize", () => {
  const projection = normalizeOfflineHotelProjection(TEST_HOTEL, {
    locale: "en",
    retrieved_at: 1,
  });
  assert.equal(projection.ok, true);
  assert.equal(projection.hid, 8473727);
  assert.equal(projection.categories.children_age_ranges.length, 3);
  assert.equal(projection.categories.cots_extra_beds.length, 2);
  assert.equal(projection.categories.amenities.length, 4);
  assert.equal(projection.categories.check_in_check_out.check_in_time, "15:00:00");
  assert.equal(projection.categories.internet_parking.internet.length, 2);
  assert.equal(projection.categories.internet_parking.parking.length, 1);
  assert.equal(projection.categories.hotel_deposits.length, 3);
  assert.equal(projection.categories.room_type_beds_occupancy.length, 13);
  assert.equal(projection.categories.important_hotel_information != null, true);
  assert.equal(projection.description_struct.length, 2);
  assert.equal(projection.categories.pets.length, 0);
  assert.equal(projection.categories.accessibility.length, 0);
});

test("11. description is not searchable or indexed", async () => {
  const store = createMemoryContentStore();
  const projection = normalizeOfflineHotelProjection(TEST_HOTEL, {
    locale: "en",
    retrieved_at: 2,
  });
  await applyOfflineContentWrite(store, projection);
  const index = await store.listIndex();
  assert.equal(projection.description_indexed, false);
  assert.ok(projection.searchable_text_excludes.includes("description_struct"));
  assert.equal(index[0].description_indexed, false);
  assert.equal("description_struct" in index[0], false);
});

test("12. restricted contact fields stay out of public DTOs", () => {
  const projection = normalizeOfflineHotelProjection(TEST_HOTEL, {
    locale: "en",
    retrieved_at: 3,
  });
  const card = toPublicStaticHotelCard(projection);
  assert.equal(card.restricted_contact_excluded, true);
  assert.equal("email" in card, false);
  assert.equal("phone" in card, false);
  assert.equal(JSON.stringify(card).includes("restricted@example.test"), false);
  assert.equal(JSON.stringify(card).includes("+32000000000"), false);
  assert.equal(projection.restricted_contact.email_present, true);
  assert.equal(projection.restricted_contact.values_retained, false);
});

test("13. live price keys cannot enter static storage", async () => {
  const store = createMemoryContentStore();
  const projection = normalizeOfflineHotelProjection(
    { ...TEST_HOTEL, rates: [{ show_amount: "180.00" }] },
    { locale: "en", retrieved_at: 4 },
  );
  assert.equal(livePriceKeysPresent(projection), false);
  const leaked = {
    ...projection,
    rates: [{ show_amount: "180.00" }],
  };
  const written = await applyOfflineContentWrite(store, leaked);
  assert.equal(written.written, false);
  assert.equal(written.reason, "live_price_forbidden_in_static_content");
});

test("14. taxi routes remain unaffected", async () => {
  const env = contentEnv({
    RATEHAWK_QUOTA_HOTEL_CONTENT_LIMIT: "1",
    RATEHAWK_QUOTA_HOTEL_CONTENT_WINDOW_SECONDS: "60",
  });
  await reserveRatehawkProviderQuota({
    env,
    endpoint: "hotel_content",
    now: 1,
  });
  const denied = await reserveRatehawkProviderQuota({
    env,
    endpoint: "hotel_content",
    now: 2,
  });
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 6 });
  assert.equal(denied.allowed, false);
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  assert.equal(taxi.amount_minor, 1500);
});

test("15. future batch strategy can reuse the same normalized projection", async () => {
  const batch = resolveRatehawkContentStrategy("batch_content_by_ids");
  assert.equal(batch.ok, false);
  assert.equal(batch.fallback_used, false);
  const fromSingle = normalizeOfflineHotelProjection(TEST_HOTEL, {
    locale: "fr",
    retrieved_at: 5,
  });
  const fromFutureBatchPayload = normalizeOfflineHotelProjection(TEST_HOTEL, {
    locale: "fr",
    retrieved_at: 5,
  });
  assert.equal(fromSingle.ok, true);
  assert.equal(fromFutureBatchPayload.ok, true);
  assert.equal(fromSingle.hid, fromFutureBatchPayload.hid);
  assert.equal(fromSingle.locale, fromFutureBatchPayload.locale);
  assert.deepEqual(fromSingle.categories.pets, fromFutureBatchPayload.categories.pets);
  const env = contentEnv();
  const refused = await executeRatehawkContentJob({
    env,
    job: {
      hid: 8473727,
      locale: "en",
      strategy: RATEHAWK_CONTENT_STRATEGIES.BATCH_CONTENT_BY_IDS,
    },
    fetchImpl: async () => {
      throw new Error("batch_must_not_transport");
    },
  });
  assert.equal(refused.invoked, false);
  assert.equal(refused.reason, "batch_content_by_ids_unavailable");
});

test("waiting jobs requeue instead of busy-looping after remaining=0", async () => {
  const env = contentEnv();
  const results = await executeRatehawkContentJobs({
    env,
    jobs: [
      { hid: 8473727, locale: "en", strategy: "single_hid_info" },
      { hid: 8473727, locale: "nl", strategy: "single_hid_info" },
    ],
    fetchImpl: async () =>
      okResponse(TEST_HOTEL, {
        "X-RateLimit-Remaining": "0",
        "X-RateLimit-Reset": "2026-08-17T07:40:00Z",
      }),
  });
  assert.equal(results[0].invoked, true);
  assert.equal(results[1].invoked, false);
  assert.equal(results[1].reason, "waiting_for_quota");
  assert.equal(results[1].busy_loop, false);
});
