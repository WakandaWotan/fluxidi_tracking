// RATEHAWK-P2 provider quota + scoped content sync foundation
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_quota_content_sync.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { runTaxiBookingIsolationProbe } from "../../booking/modules/ratehawk_hotels_facade.mjs";
import {
  handleRatehawkContentSyncRequest,
  handleRatehawkHotelsScheduled,
  handleRatehawkHotelsWorkerFetch,
  RATEHAWK_HOTELS_INTERNAL_PROXY,
} from "../fluxidi_ratehawk_hotels_worker.js";
import {
  RATEHAWK_CONTENT_DUMP_PATH,
  RATEHAWK_DISCLOSURE_LOCALES,
  RATEHAWK_REQUIRED_CONTENT_CATEGORIES,
  applyOfflineContentWrite,
  assertContentOperationAllowed,
  createMemoryContentStore,
  isRatehawkFullDumpRequest,
  livePriceKeysPresent,
  normalizeOfflineHotelProjection,
  planScopedContentSync,
  shouldRunRatehawkContentSync,
} from "./ratehawk_content_sync.mjs";
import { handleRatehawkHotelpageRequest } from "./ratehawk_hotelpage_worker.mjs";
import {
  RATEHAWK_TEST_ACCOUNT_QUOTAS,
  createRatehawkQuotaBinding,
  reserveRatehawkProviderQuota,
  resolveRatehawkProviderQuotaConfig,
} from "./ratehawk_provider_quota.mjs";

const TEST_MARKETS = Object.freeze([
  {
    country_code: "BE",
    city_key: "brussels",
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

function quotaEnv(overrides = {}) {
  return {
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

test("full dump cannot be requested", () => {
  assert.equal(isRatehawkFullDumpRequest(RATEHAWK_CONTENT_DUMP_PATH), true);
  assert.equal(isRatehawkFullDumpRequest("dump_all"), true);
  assert.equal(isRatehawkFullDumpRequest("/api/b2b/v3/hotel/info/incremental_dump/"), true);
  const denied = assertContentOperationAllowed("dump_all");
  assert.equal(denied.ok, false);
  assert.equal(denied.reason, "full_dump_forbidden");
  const allowed = assertContentOperationAllowed("hotel_content_by_ids");
  assert.equal(allowed.ok, true);
  const custom = assertContentOperationAllowed("custom_dump");
  assert.equal(custom.ok, false);
});

test("empty production markets produce no work", () => {
  const planned = planScopedContentSync({
    env: { RATEHAWK_ENVIRONMENT: "production" },
    markets: [],
  });
  assert.equal(planned.ok, true);
  assert.deepEqual(planned.jobs, []);
  assert.equal(planned.reason, "no_configured_markets");
  assert.equal(planned.provider_requested, false);
});

test("only configured markets and hids are scheduled", () => {
  const planned = planScopedContentSync({
    env: {},
    markets: TEST_MARKETS,
    hidLists: {
      "BE:brussels": [8473727, 8473727, "not-a-hid"],
      "BE:antwerp": [1001, 1002],
      "FR:paris": [9],
    },
  });
  assert.equal(planned.jobs.length, 12);
  const keys = new Set(planned.jobs.map((job) => job.market_key));
  assert.deepEqual([...keys].sort(), ["BE:antwerp", "BE:brussels"]);
  const brussels = planned.jobs.filter((job) => job.market_key === "BE:brussels");
  assert.equal(brussels.length, 4);
  assert.ok(brussels.every((job) => job.hid === 8473727 && job.hids.length === 1));
  assert.equal(brussels[0].dump_forbidden, true);
  assert.equal(brussels[0].strategy, "single_hid_info");
});

test("hotel limits are enforced", () => {
  const many = Array.from({ length: 40 }, (_, i) => i + 1);
  const planned = planScopedContentSync({
    env: {
      RATEHAWK_SEARCH_INITIAL_LIMIT: "3",
      RATEHAWK_SEARCH_ABSOLUTE_MAX: "3",
    },
    markets: [TEST_MARKETS[0]],
    hidLists: { "BE:brussels": many },
    locales: ["en"],
  });
  assert.equal(planned.jobs.length, 3);
  assert.ok(planned.jobs.every((job) => job.hids.length === 1 && job.locale === "en"));
  assert.equal(planned.jobs[0].truncated, true);
});

test("customer requests cannot trigger sync", async () => {
  const env = { RATEHAWK_CONTENT_SYNC_ENABLED: "1" };
  for (const trigger of [
    "page_open",
    "live_search",
    "view_stay",
    "hotelpage",
    "customer_request",
    "prebook",
    "booking",
  ]) {
    const gate = shouldRunRatehawkContentSync({ trigger, env });
    assert.equal(gate.run, false, trigger);
    assert.equal(gate.reason, "content_sync_forbidden_on_customer_request", trigger);
  }
  const customer = await handleRatehawkContentSyncRequest({
    env,
    trigger: "view_stay",
    body: { markets: TEST_MARKETS },
  });
  assert.equal(customer.executed, false);
  assert.equal(customer.provider_requested, false);
  const scheduledOff = await handleRatehawkHotelsScheduled({}, {});
  assert.equal(scheduledOff.reason, "content_sync_disabled");
});

test("global provider quota denies excess calls with zero transport", async () => {
  const env = quotaEnv({
    RATEHAWK_QUOTA_HOTELPAGE_LIMIT: "1",
    RATEHAWK_QUOTA_HOTELPAGE_WINDOW_SECONDS: "60",
    RATEHAWK_QUOTA_SERP_LIMIT: "15",
    RATEHAWK_QUOTA_SERP_WINDOW_SECONDS: "60",
  });
  const first = await reserveRatehawkProviderQuota({
    env,
    endpoint: "hotelpage",
    now: 1_000,
  });
  assert.equal(first.allowed, true);
  let transport = 0;
  const denied = await reserveRatehawkProviderQuota({
    env,
    endpoint: "hotelpage",
    now: 1_100,
  });
  assert.equal(denied.allowed, false);
  assert.equal(denied.reason, "provider_quota_exhausted");
  assert.equal(Number.isInteger(denied.retry_after) && denied.retry_after >= 1, true);
  assert.equal(transport, 0);
});

test("quota denial performs zero hotelpage transport and retry_after is safe", async () => {
  const env = {
    RATEHAWK_KEY_ID: "test-key",
    RATEHAWK_API_KEY: "test-api",
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_ENABLED: "1",
    RATEHAWK_HOTELPAGE_ENABLED: "1",
    RATEHAWK_OFFER_REF_SECRET: "rh_offer_ref_test_secret_not_real",
    RATEHAWK_QUOTA_HOTELPAGE_LIMIT: "1",
    RATEHAWK_QUOTA_HOTELPAGE_WINDOW_SECONDS: "60",
    RATEHAWK_QUOTA_SERP_LIMIT: "15",
    RATEHAWK_QUOTA_SERP_WINDOW_SECONDS: "60",
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
  };
  const body = {
    trigger: "view_stay",
    hid: 8473727,
    selected_card_hid: 8473727,
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    residency: "be",
    language: "en",
    currency: "EUR",
    guests: [{ adults: 2, children: [] }],
    stay: { provider: "ratehawk", provider_id: "8473727", hid: 8473727 },
  };
  let calls = 0;
  const fetchImpl = async () => {
    calls += 1;
    return { status: 200, json: async () => ({ status: "ok", data: { hotels: [] } }) };
  };
  await handleRatehawkHotelpageRequest({
    env,
    body,
    fetchImpl,
    now: Date.parse("2026-08-17T07:20:00.000Z"),
  });
  const denied = await handleRatehawkHotelpageRequest({
    env,
    body,
    fetchImpl,
    now: Date.parse("2026-08-17T07:20:01.000Z"),
  });
  assert.equal(denied.invoked, false);
  assert.equal(denied.ratehawk.retryable, true);
  assert.equal(denied.reason, "provider_quota_exhausted");
  assert.equal(Number(denied.ratehawk.retry_after) >= 1, true);
  assert.equal(JSON.stringify(denied).includes("test-api"), false);
  assert.equal(calls <= 1, true);
});

test("production quota is fail-closed when absent", async () => {
  const config = resolveRatehawkProviderQuotaConfig({
    RATEHAWK_ENVIRONMENT: "production",
  });
  assert.equal(config.ok, false);
  assert.equal(config.reason, "production_quota_unconfigured");
  const reserved = await reserveRatehawkProviderQuota({
    env: { RATEHAWK_ENVIRONMENT: "production" },
    endpoint: "hotelpage",
  });
  assert.equal(reserved.allowed, false);
  assert.equal(RATEHAWK_TEST_ACCOUNT_QUOTAS.hotelpage.limit, 5);
  assert.equal(RATEHAWK_TEST_ACCOUNT_QUOTAS.serp.limit, 15);
  assert.equal(RATEHAWK_TEST_ACCOUNT_QUOTAS.hotel_content.limit, 30);
  const content = await reserveRatehawkProviderQuota({
    env: { RATEHAWK_ENVIRONMENT: "production" },
    endpoint: "hotel_content",
  });
  assert.equal(content.allowed, false);
  assert.equal(content.reason, "production_quota_unconfigured");
});

test("locale projections stay separated", async () => {
  const store = createMemoryContentStore();
  const hotel = {
    hid: 8473727,
    name: "Demo",
    address: "Rue Demo 1",
    lat: 50.85,
    lng: 4.35,
    content_revision: "2",
    amenity_groups: [{ group_name: "General", amenities: ["wifi"] }],
    metapolicy_struct: { pets: [{ pets_type: "lt_5kg" }], children: [], cot: [], extra_bed: [] },
  };
  for (const locale of RATEHAWK_DISCLOSURE_LOCALES) {
    const projection = normalizeOfflineHotelProjection(hotel, {
      locale,
      revision: "2",
      retrieved_at: 100,
    });
    await applyOfflineContentWrite(store, projection);
  }
  const nl = await store.get(8473727, "nl");
  const en = await store.get(8473727, "en");
  assert.equal(nl.locale, "nl");
  assert.equal(en.locale, "en");
  assert.notEqual(nl, en);
});

test("older content cannot overwrite newer content and tombstones work", async () => {
  const store = createMemoryContentStore();
  const newer = normalizeOfflineHotelProjection(
    { hid: 8473727, name: "New", content_revision: "5" },
    { locale: "en", revision: "5", retrieved_at: 500 },
  );
  const older = normalizeOfflineHotelProjection(
    { hid: 8473727, name: "Old", content_revision: "4" },
    { locale: "en", revision: "4", retrieved_at: 400 },
  );
  assert.equal((await applyOfflineContentWrite(store, newer)).written, true);
  assert.equal((await applyOfflineContentWrite(store, older)).written, false);
  assert.equal((await store.get(8473727, "en")).name, "New");
  const stone = await store.tombstone({
    hid: 8473727,
    locale: "en",
    revision: "6",
    retrieved_at: 600,
  });
  assert.equal(stone.written, true);
  assert.equal((await store.get(8473727, "en")).tombstone, true);
  const staleStone = await store.tombstone({
    hid: 8473727,
    locale: "en",
    revision: "1",
    retrieved_at: 100,
  });
  assert.equal(staleStone.written, false);
});

test("all required content categories survive and live prices stay out", () => {
  const hotel = {
    hid: 8473727,
    name: "Demo Hotel",
    address: "Rue Duquesnoy 5",
    lat: 50.845,
    lng: 4.3543,
    star_rating: 4,
    images: [{ url: "https://img.example/licensed.jpg", category: "hero" }],
    amenity_groups: [
      { group_name: "Accessibility", amenities: ["wheelchair-access"] },
    ],
    check_in_time: "15:00:00",
    check_out_time: "11:00:00",
    metapolicy_extra_info: "City tax may apply.",
    policy_struct: [{ title: "House rules" }],
    room_groups: [{ name: "Superior", rg_ext: { bedding: 2 } }],
    metapolicy_struct: {
      pets: [{ pets_type: "lt_5kg", inclusion: "not_included" }],
      children: [{ age_start: 0, age_end: 12 }],
      cot: [{ inclusion: "available" }],
      extra_bed: [{ inclusion: "available" }],
      children_meal: [],
      meal: [{ inclusion: "breakfast" }],
      internet: [{ inclusion: "included" }],
      parking: [{ inclusion: "not_included" }],
      deposit: [{ amount: "50.00", currency: "EUR" }],
      add_fee: [{ name: "city_tax" }],
      check_in_check_out: [{ inclusion: "early_check_in" }],
    },
    rates: [{ book_hash: "secret", show_amount: "180.00" }],
    payment_options: { payment_types: [{ type: "now" }] },
    book_hash: "secret",
    unknown_critical_policy: { note: "retain-for-review" },
  };
  const projection = normalizeOfflineHotelProjection(hotel, {
    locale: "nl",
    revision: "9",
    retrieved_at: 900,
    market_key: "BE:brussels",
  });
  assert.equal(projection.ok, true);
  assert.equal(projection.live_price_excluded, true);
  assert.equal(projection.has_live_rates, false);
  assert.equal(livePriceKeysPresent(projection.categories), false);
  assert.equal(projection.image_binaries_downloaded, false);
  assert.equal(projection.image_refs[0].binary, false);
  assert.equal(projection.coordinates.lat, 50.845);
  for (const category of [
    "pets",
    "children_age_ranges",
    "cots_extra_beds",
    "accessibility",
    "amenities",
    "check_in_check_out",
    "early_late_check_in",
    "internet_parking",
    "hotel_deposits",
    "important_hotel_information",
  ]) {
    assert.ok(projection.categories[category] != null, category);
  }
  for (const category of RATEHAWK_REQUIRED_CONTENT_CATEGORIES) {
    assert.ok(
      Object.prototype.hasOwnProperty.call(projection.categories, category),
      category,
    );
  }
  assert.ok(
    projection.unmapped_critical_field_names.includes("unknown_critical_policy"),
  );
  assert.deepEqual(projection.unmapped_fields_for_review.unknown_critical_policy, {
    note: "retain-for-review",
  });
  assert.equal(JSON.stringify(projection).includes("secret"), false);
  assert.equal(JSON.stringify(projection).includes("180.00"), false);
});

test("customer hotelpage and public worker paths cannot start content sync", async () => {
  const env = {
    RATEHAWK_CONTENT_SYNC_ENABLED: "1",
    RATEHAWK_CONTENT_MARKETS: JSON.stringify(TEST_MARKETS),
  };
  const publicSync = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.workers.dev/internal/content-sync", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ markets: TEST_MARKETS }),
    }),
    env,
  );
  assert.equal(publicSync.status, 404);
  const hotelpage = await handleRatehawkHotelpageRequest({
    env: {
      ...env,
      RATEHAWK_ENABLED: "0",
      RATEHAWK_HOTELPAGE_ENABLED: "0",
    },
    body: { trigger: "view_stay", hid: 8473727 },
  });
  assert.equal("jobs" in hotelpage, false);
  assert.equal(hotelpage.invoked, false);
  const scheduled = await handleRatehawkHotelsScheduled(
    {},
    { RATEHAWK_CONTENT_SYNC_ENABLED: "1" },
  );
  assert.equal(scheduled.executed, false);
  assert.equal(scheduled.provider_requested, false);
  assert.equal(scheduled.reason, "no_configured_markets");
  const admin = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/content-sync", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: JSON.stringify({ markets: TEST_MARKETS, hid_lists: { "BE:brussels": [8473727] } }),
    }),
    { RATEHAWK_CONTENT_SYNC_ENABLED: "1" },
  );
  const planned = await admin.json();
  assert.equal(planned.executed, false);
  assert.equal(planned.provider_requested, false);
  assert.equal(planned.jobs.length, 4);
  assert.ok(planned.jobs.every((job) => job.hid === 8473727 && job.hids.length === 1));
});

test("missing quota coordinator denies with zero transport", async () => {
  let transport = 0;
  const denied = await reserveRatehawkProviderQuota({
    env: {
      RATEHAWK_ENVIRONMENT: "test",
      RATEHAWK_QUOTA_HOTELPAGE_LIMIT: "5",
      RATEHAWK_QUOTA_HOTELPAGE_WINDOW_SECONDS: "60",
      RATEHAWK_QUOTA_SERP_LIMIT: "15",
      RATEHAWK_QUOTA_SERP_WINDOW_SECONDS: "60",
    },
    endpoint: "hotelpage",
  });
  assert.equal(denied.allowed, false);
  assert.equal(denied.reason, "quota_coordinator_missing");
  assert.equal(transport, 0);
});

test("taxi routes remain unaffected by quota and content sync", async () => {
  const env = quotaEnv({
    RATEHAWK_QUOTA_HOTELPAGE_LIMIT: "1",
    RATEHAWK_QUOTA_HOTELPAGE_WINDOW_SECONDS: "60",
    RATEHAWK_QUOTA_SERP_LIMIT: "1",
    RATEHAWK_QUOTA_SERP_WINDOW_SECONDS: "60",
  });
  await reserveRatehawkProviderQuota({ env, endpoint: "hotelpage", now: 1 });
  const denied = await reserveRatehawkProviderQuota({
    env,
    endpoint: "hotelpage",
    now: 2,
  });
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 6 });
  assert.equal(denied.allowed, false);
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  const sync = shouldRunRatehawkContentSync({
    trigger: "customer_request",
    env: { RATEHAWK_CONTENT_SYNC_ENABLED: "1" },
  });
  assert.equal(sync.run, false);
  assert.equal(taxi.amount_minor, 1500);
});
