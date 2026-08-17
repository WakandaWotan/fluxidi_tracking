// RATEHAWK-P1 isolated Cloudflare test Worker environment
//
// Run:
//   node --test workers/booking/modules/ratehawk_environment_isolation.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  handleAdminRatehawkTestPrebook,
  handleAdminRatehawkTestSearch,
  handlePublicRatehawkHotelpage,
  issueRatehawkViewStayContext,
  runTaxiBookingIsolationProbe,
} from "./ratehawk_hotels_facade.mjs";
import {
  handleRatehawkHotelsWorkerFetch,
  RATEHAWK_HOTELS_INTERNAL_PROXY,
} from "../../ratehawk-hotels/fluxidi_ratehawk_hotels_worker.js";
import { createRatehawkQuotaBinding } from "../../ratehawk-hotels/modules/ratehawk_provider_quota.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const CONTEXT_SECRET = "rh_view_stay_context_test_secret_not_real";
const NOW = Date.parse("2026-08-17T07:10:00.000Z");

function sectionAfter(text, header) {
  const start = text.indexOf(header);
  if (start < 0) return "";
  return text.slice(start);
}

test("production Hotels config has no test host, environment or credentials", () => {
  const wrangler = readFileSync(
    join(HERE, "../../ratehawk-hotels/wrangler.toml"),
    "utf8",
  );
  const top = wrangler.slice(0, wrangler.indexOf("[env.test]"));
  assert.match(top, /RATEHAWK_WORKER_SURFACE = "production"/);
  assert.equal(/RATEHAWK_ENVIRONMENT\s*=\s*"test"/.test(top), false);
  assert.equal(/RATEHAWK_BASE_URL\s*=/.test(top), false);
  assert.equal(/RATEHAWK_API_KEY\s*=/.test(top), false);
  assert.equal(/RATEHAWK_KEY_ID\s*=/.test(top), false);
  assert.equal(/RATEHAWK_OFFER_REF_SECRET\s*=/.test(top), false);
  for (const name of [
    "RATEHAWK_ENABLED",
    "RATEHAWK_HOTELPAGE_ENABLED",
    "RATEHAWK_SEARCH_ENABLED",
    "RATEHAWK_PREBOOK_ENABLED",
    "RATEHAWK_CONTENT_SYNC_ENABLED",
    "RATEHAWK_CONTENT_BATCH_ENABLED",
    "RATEHAWK_TEST_SEARCH_ENABLED",
    "RATEHAWK_TEST_HOTELPAGE_ENABLED",
    "RATEHAWK_TEST_PREBOOK_ENABLED",
  ]) {
    assert.match(top, new RegExp(`${name} = "0"`));
  }
});

test("test Hotels env is a private isolated Worker with no D1 or content sync", () => {
  const wrangler = readFileSync(
    join(HERE, "../../ratehawk-hotels/wrangler.toml"),
    "utf8",
  );
  const testEnv = sectionAfter(wrangler, "[env.test]");
  assert.match(wrangler, /name = "fluxidi-ratehawk-hotels-api-test"/);
  assert.match(testEnv, /workers_dev = false/);
  assert.match(testEnv, /preview_urls = false/);
  assert.match(testEnv, /RATEHAWK_WORKER_SURFACE = "test"/);
  assert.match(testEnv, /RATEHAWK_ENVIRONMENT = "test"/);
  assert.match(testEnv, /RATEHAWK_BASE_URL = "https:\/\/api\.ratehawk\.com"/);
  assert.equal(/\[\[d1_databases\]\]/.test(testEnv), false);
  assert.equal(/RATEHAWK_HOTELS_DB/.test(testEnv), false);
  assert.equal(/64bd3865-419f-47cd-91db-cd20329614c5/.test(testEnv), false);
  assert.equal(/script_name/.test(testEnv), false);
  assert.match(testEnv, /class_name = "RatehawkProviderQuotaDO"/);
  assert.match(testEnv, /tag = "ratehawk-provider-quota-test-v1"/);
  for (const name of [
    "RATEHAWK_ENABLED",
    "RATEHAWK_HOTELPAGE_ENABLED",
    "RATEHAWK_SEARCH_ENABLED",
    "RATEHAWK_PREBOOK_ENABLED",
    "RATEHAWK_CONTENT_SYNC_ENABLED",
    "RATEHAWK_CONTENT_BATCH_ENABLED",
  ]) {
    assert.match(testEnv, new RegExp(`${name} = "0"`));
  }
  assert.match(testEnv, /RATEHAWK_TEST_SEARCH_ENABLED = "1"/);
  assert.match(testEnv, /RATEHAWK_TEST_HOTELPAGE_ENABLED = "1"/);
  assert.match(testEnv, /RATEHAWK_TEST_PREBOOK_ENABLED = "1"/);
});

test("Booking binds production and test Hotels Workers separately", () => {
  const wrangler = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
  assert.match(wrangler, /binding = "RATEHAWK_HOTELS"/);
  assert.match(wrangler, /service = "fluxidi-ratehawk-hotels-api"/);
  assert.match(wrangler, /binding = "RATEHAWK_HOTELS_TEST"/);
  assert.match(wrangler, /service = "fluxidi-ratehawk-hotels-api-test"/);
  assert.equal(/RATEHAWK_API_KEY\s*=/.test(wrangler), false);
  assert.equal(/RATEHAWK_KEY_ID\s*=/.test(wrangler), false);
  assert.equal(/RATEHAWK_OFFER_REF_SECRET\s*=/.test(wrangler), false);
  assert.match(wrangler, /RATEHAWK_TEST_SEARCH_ENABLED = "1"/);
  assert.match(wrangler, /RATEHAWK_TEST_HOTELPAGE_ENABLED = "1"/);
  assert.match(wrangler, /RATEHAWK_TEST_PREBOOK_ENABLED = "1"/);
  assert.equal(/RATEHAWK_PREBOOK_ENABLED\s*=\s*"1"/.test(wrangler), false);
});

test("production facade paths cannot use RATEHAWK_HOTELS_TEST", () => {
  const facade = readFileSync(join(HERE, "ratehawk_hotels_facade.mjs"), "utf8");
  const publicFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkHotelpage"),
    facade.indexOf("function _safeTestUnavailable"),
  );
  const publicSearchFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkSearch"),
    facade.indexOf("export async function handlePublicRatehawkHotelpage"),
  );
  const statusFn = facade.slice(
    facade.indexOf("export async function fetchRatehawkHotelsStatus"),
    facade.indexOf("export async function handlePublicRatehawkSearch"),
  );
  assert.match(publicFn, /env\?\.RATEHAWK_HOTELS/);
  assert.equal(publicFn.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.match(publicSearchFn, /env\?\.RATEHAWK_HOTELS/);
  assert.match(publicSearchFn, /RATEHAWK_HOTELS_SEARCH_PATH/);
  assert.equal(publicSearchFn.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.match(publicFn, /RATEHAWK_HOTELS_PREBOOK_PATH/);
  assert.equal(publicFn.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(publicSearchFn.includes("/internal/test-search"), false);
  assert.equal(publicSearchFn.includes("/internal/test-prebook"), false);
  assert.equal(publicSearchFn.includes("/admin/hotels/ratehawk/test"), false);
  assert.equal(publicFn.includes("/internal/test-prebook"), false);
  assert.match(statusFn, /env\?\.RATEHAWK_HOTELS/);
  assert.equal(statusFn.includes("RATEHAWK_HOTELS_TEST"), false);
});

test("admin test paths cannot use RATEHAWK_HOTELS", () => {
  const facade = readFileSync(join(HERE, "ratehawk_hotels_facade.mjs"), "utf8");
  const proxyFn = facade.slice(
    facade.indexOf("async function _proxyHotelsTestPath"),
    facade.indexOf("export async function handleAdminRatehawkTestSearch"),
  );
  const searchFn = facade.slice(
    facade.indexOf("export async function handleAdminRatehawkTestSearch"),
    facade.indexOf("export async function handleAdminRatehawkTestHotelpage"),
  );
  const hotelpageFn = facade.slice(
    facade.indexOf("export async function handleAdminRatehawkTestHotelpage"),
    facade.indexOf("export async function handleAdminRatehawkTestPrebook"),
  );
  const prebookFn = facade.slice(
    facade.indexOf("export async function handleAdminRatehawkTestPrebook"),
    facade.indexOf("export function runTaxiBookingIsolationProbe"),
  );
  assert.match(proxyFn, /RATEHAWK_HOTELS_TEST/);
  assert.equal(proxyFn.includes("env?.RATEHAWK_HOTELS.fetch"), false);
  assert.equal(searchFn.includes("env.RATEHAWK_HOTELS"), false);
  assert.equal(hotelpageFn.includes("env.RATEHAWK_HOTELS"), false);
  assert.equal(prebookFn.includes("env.RATEHAWK_HOTELS"), false);
  assert.match(prebookFn, /RATEHAWK_HOTELS_TEST_PREBOOK_PATH/);
  assert.match(searchFn, /RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET/);
  assert.match(hotelpageFn, /RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET/);
  assert.equal(searchFn.includes("RATEHAWK_VIEW_STAY_CONTEXT_SECRET"), false);
  assert.equal(hotelpageFn.includes("env?.RATEHAWK_VIEW_STAY_CONTEXT_SECRET"), false);
});

test("missing test binding fails only admin RateHawk test routes", async () => {
  let productionCalls = 0;
  const env = {
    BOOKING_KV: {
      async get() {
        return null;
      },
      async put() {},
    },
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_HOTELS: {
      fetch: async () => {
        productionCalls += 1;
        return new Response(
          JSON.stringify({
            ok: true,
            invoked: false,
            reason: "hotelpage_disabled",
            ratehawk: { offers: [] },
          }),
        );
      },
    },
  };
  const search = await handleAdminRatehawkTestSearch({ env, now: NOW });
  assert.equal(search.reason, "hotels_test_worker_binding_missing");
  assert.equal(search.binding_called, false);
  const prebook = await handleAdminRatehawkTestPrebook({
    env: { ...env, RATEHAWK_TEST_PREBOOK_ENABLED: "1" },
    body: { trigger: "test_prebook_revalidation", offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(prebook.reason, "hotels_test_worker_binding_missing");
  assert.equal(prebook.binding_called, false);
  assert.equal(prebook.progress_blocked, true);
  const issued = await issueRatehawkViewStayContext(
    CONTEXT_SECRET,
    {
      hid: 8473727,
      checkin: "2026-09-03",
      checkout: "2026-09-04",
      residency: "be",
      currency: "EUR",
      guests: [{ adults: 2, children: [] }],
    },
    { now: NOW },
  );
  const publicDto = await handlePublicRatehawkHotelpage({
    env,
    request: new Request("https://fluxidi-booking-api.internal/public/hotels/ratehawk/hotelpage", {
      method: "POST",
      headers: { "cf-connecting-ip": "203.0.113.10" },
    }),
    body: {
      trigger: "view_stay",
      hid: 8473727,
      checkin: "2026-09-03",
      checkout: "2026-09-04",
      residency: "be",
      currency: "EUR",
      guests: [{ adults: 2, children: [] }],
      stay: { provider: "ratehawk", provider_id: "8473727", hid: 8473727 },
      view_stay_context: issued.token,
    },
    now: NOW,
  });
  assert.equal(productionCalls, 1);
  assert.equal(publicDto.reason, "hotelpage_disabled");
});

test("production Hotels Worker rejects test routes", async () => {
  const resp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/test-search", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    {
      RATEHAWK_WORKER_SURFACE: "production",
      RATEHAWK_TEST_SEARCH_ENABLED: "1",
      RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    },
  );
  const dto = await resp.json();
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "test_worker_required");
  const prebook = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/test-prebook", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    {
      RATEHAWK_WORKER_SURFACE: "production",
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
      RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    },
  );
  const prebookDto = await prebook.json();
  assert.equal(prebookDto.invoked, false);
  assert.equal(prebookDto.reason, "test_worker_required");
  const accept = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/test-prebook/accept", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    {
      RATEHAWK_WORKER_SURFACE: "production",
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    },
  );
  const acceptDto = await accept.json();
  assert.equal(acceptDto.invoked, false);
  assert.equal(acceptDto.reason, "test_worker_required");
});

test("test Hotels Worker rejects production Hotelpage and content sync", async () => {
  const hotelpage = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/hotelpage", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    { RATEHAWK_WORKER_SURFACE: "test" },
  );
  const hotelpageDto = await hotelpage.json();
  assert.equal(hotelpageDto.invoked, false);
  assert.equal(hotelpageDto.reason, "production_path_forbidden_on_test_worker");
  const sync = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/content-sync", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    { RATEHAWK_WORKER_SURFACE: "test" },
  );
  const syncDto = await sync.json();
  assert.equal(syncDto.provider_requested, false);
  assert.equal(syncDto.reason, "production_path_forbidden_on_test_worker");
  const search = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/search", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    { RATEHAWK_WORKER_SURFACE: "test" },
  );
  const searchDto = await search.json();
  assert.equal(searchDto.invoked, false);
  assert.equal(searchDto.count, 0);
  assert.equal(searchDto.reason, "production_path_forbidden_on_test_worker");
  const prebook = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/prebook", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    { RATEHAWK_WORKER_SURFACE: "test" },
  );
  const prebookDto = await prebook.json();
  assert.equal(prebookDto.invoked, false);
  assert.equal(prebookDto.reason, "production_path_forbidden_on_test_worker");
  const accept = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/prebook/accept", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    { RATEHAWK_WORKER_SURFACE: "test" },
  );
  const acceptDto = await accept.json();
  assert.equal(acceptDto.invoked, false);
  assert.equal(acceptDto.reason, "production_path_forbidden_on_test_worker");
});

test("taxi isolation cannot call either Hotels binding", () => {
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 7 });
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  assert.equal(taxi.invoked_ratehawk_test, false);
  const worker = readFileSync(join(HERE, "../fluxidi_booking_worker.js"), "utf8");
  assert.equal(worker.includes("RATEHAWK_HOTELS_TEST"), false);
  const street = readFileSync(join(HERE, "street_ride_never_planned.test.mjs"), "utf8");
  const fleet = readFileSync(join(HERE, "fleet_vehicle_tombstone.mjs"), "utf8");
  assert.equal(street.includes("RATEHAWK_HOTELS"), false);
  assert.equal(street.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(fleet.includes("RATEHAWK_HOTELS"), false);
  assert.equal(fleet.includes("RATEHAWK_HOTELS_TEST"), false);
});
