// RATEHAWK-P1 isolated Hotels Worker + Booking facade
//
// Run:
//   node --test workers/booking/modules/ratehawk_isolation.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  bookingWorkerCanConstructRatehawkAuthorization,
  bookingWorkerHasRatehawkCredentials,
  buildRatehawkPublicSearchGuardPayload,
  handleAdminRatehawkTestHotelpage,
  handleAdminRatehawkTestSearch,
  handlePublicRatehawkHotelpage,
  issueRatehawkViewStayContext,
  runTaxiBookingIsolationProbe,
} from "./ratehawk_hotels_facade.mjs";
import { resolveRatehawkTestStay } from "../../ratehawk-hotels/modules/ratehawk_test_activation.mjs";
import {
  handleRatehawkHotelsWorkerFetch,
  RATEHAWK_HOTELS_INTERNAL_PROXY,
} from "../../ratehawk-hotels/fluxidi_ratehawk_hotels_worker.js";
import {
  handleRatehawkHotelpageRequest,
  isRatehawkContentSyncAllowedOnCustomerRequest,
} from "../../ratehawk-hotels/modules/ratehawk_hotelpage_worker.mjs";
import { createRatehawkQuotaBinding } from "../../ratehawk-hotels/modules/ratehawk_provider_quota.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TEST_API_KEY = "rh_test_secret_do_not_leak_xyz";
const TEST_KEY_ID = "18292";
const OFFER_SECRET = "rh_offer_ref_test_secret_not_real";
const CONTEXT_SECRET = "rh_view_stay_context_test_secret_not_real";
const BOOK_HASH = "h-hp-secret-hash-do-not-leak";
const MATCH_HASH = "m-hp-secret-hash-do-not-leak";
const RETRIEVED_AT = Date.parse("2026-08-17T07:10:00.000Z");

function memoryKv() {
  const store = new Map();
  return {
    async get(key, opts) {
      const raw = store.get(String(key));
      if (raw == null) return null;
      if (opts?.type === "json") return JSON.parse(raw);
      return raw;
    },
    async put(key, value) {
      store.set(String(key), String(value));
    },
  };
}

function hotelsEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: TEST_KEY_ID,
    RATEHAWK_API_KEY: TEST_API_KEY,
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_WORKER_SURFACE: "production",
    RATEHAWK_ENABLED: "1",
    RATEHAWK_HOTELPAGE_ENABLED: "1",
    RATEHAWK_OFFER_REF_SECRET: OFFER_SECRET,
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

function bookingEnv(hotelsBinding, overrides = {}) {
  return {
    BOOKING_KV: memoryKv(),
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_HOTELS: hotelsBinding,
    ...overrides,
  };
}

function bookingTestEnv(testBinding, overrides = {}) {
  return {
    BOOKING_KV: memoryKv(),
    RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_HOTELS_TEST: testBinding,
    RATEHAWK_HOTELS: {
      fetch: async () => {
        throw new Error("production_hotels_must_not_be_called");
      },
    },
    ...overrides,
  };
}

function testHotelsEnv(overrides = {}) {
  return hotelsEnv({
    RATEHAWK_WORKER_SURFACE: "test",
    RATEHAWK_ENABLED: "0",
    RATEHAWK_HOTELPAGE_ENABLED: "0",
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    ...overrides,
  });
}

function stay() {
  return {
    id: "approved-warwick-brussels",
    provider: "ratehawk",
    provider_id: "8473727",
    hid: 8473727,
    name: "Warwick Brussels",
  };
}

function searchFields(overrides = {}) {
  return {
    hid: 8473727,
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    residency: "be",
    currency: "EUR",
    guests: [{ adults: 2, children: [] }],
    ...overrides,
  };
}

async function issuedBody(overrides = {}, issuedAt = RETRIEVED_AT) {
  const fields = searchFields(overrides);
  const issued = await issueRatehawkViewStayContext(CONTEXT_SECRET, fields, {
    now: issuedAt,
  });
  assert.equal(issued.ok, true);
  return {
    trigger: "view_stay",
    language: "en",
    locale: "nl",
    selected_card_hid: fields.hid,
    stay: stay(),
    search_context: {
      hid: fields.hid,
      checkin: fields.checkin,
      checkout: fields.checkout,
      residency: fields.residency,
      language: "en",
      currency: fields.currency,
      guests: fields.guests,
    },
    view_stay_context: issued.token,
    ...fields,
    ...overrides,
  };
}

function hotelpageRate() {
  return {
    book_hash: BOOK_HASH,
    match_hash: MATCH_HASH,
    room_name: "Superior Double",
    room_description: "City view",
    occupancy: { adults: 2 },
    meal: "breakfast",
    meal_data: { value: "breakfast", has_breakfast: true },
    allotment: 2,
    rg_ext: { class: 3, quality: 2, bedding: 2 },
    deposit: { amount: "50.00", currency_code: "EUR", is_refundable: true },
    no_show: { amount: "25.00", currency_code: "USD", from_time: "18:00:00" },
    payment_options: {
      payment_types: [
        {
          type: "hotel",
          amount: "180.00",
          show_amount: "180.00",
          currency_code: "EUR",
          show_currency_code: "EUR",
          is_need_credit_card_data: true,
          is_need_cvc: true,
          vat_data: { included: true },
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
          cancellation_penalties: {
            free_cancellation_before: "2026-09-01T10:00:00",
            policies: [],
          },
        },
      ],
    },
  };
}

function etgOk() {
  return {
    status: "ok",
    data: { hotels: [{ hid: 8473727, rates: [hotelpageRate()] }] },
  };
}

function trackingFetch(impl) {
  const state = { calls: 0 };
  const fetchImpl = async (...args) => {
    state.calls += 1;
    return impl(...args);
  };
  return { state, fetchImpl };
}

function hotelsBinding(hotels, fetchImpl, now = RETRIEVED_AT) {
  const state = { calls: 0 };
  return {
    state,
    binding: {
      fetch: async (request) => {
        state.calls += 1;
        return handleRatehawkHotelsWorkerFetch(request, hotels, {
          fetchImpl,
          now,
        });
      },
    },
  };
}

function publicRequest() {
  return new Request("https://fluxidi-booking-api.internal/public/hotels/ratehawk/hotelpage", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "cf-connecting-ip": "203.0.113.10",
    },
  });
}

function dump(value) {
  return JSON.stringify(value);
}

function assertSafeDto(dto) {
  const text = dump(dto);
  assert.equal(text.includes(TEST_API_KEY), false);
  assert.equal(text.includes(BOOK_HASH), false);
  assert.equal(text.includes(MATCH_HASH), false);
  assert.equal(text.includes("reconciliation_amount"), false);
  assert.equal(text.includes("fluxidi_affiliate_remuneration"), false);
  assert.equal(dto.stay22_fallback_retained, true);
  assert.equal(dto.commercial.customer_pays_fluxidi, false);
}

test("1. Booking Worker has no RateHawk credentials", () => {
  const env = bookingEnv({ fetch: async () => new Response("{}") });
  assert.equal(bookingWorkerHasRatehawkCredentials(env), false);
  const wrangler = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
  assert.equal(/RATEHAWK_API_KEY\s*=/.test(wrangler), false);
  assert.equal(/RATEHAWK_KEY_ID\s*=/.test(wrangler), false);
  assert.equal(/RATEHAWK_ENABLED\s*=/.test(wrangler), false);
  assert.match(wrangler, /RATEHAWK_TEST_SEARCH_ENABLED = "1"/);
  assert.match(wrangler, /RATEHAWK_TEST_HOTELPAGE_ENABLED = "1"/);
  assert.match(wrangler, /binding = "RATEHAWK_HOTELS"/);
  assert.match(wrangler, /service = "fluxidi-ratehawk-hotels-api"/);
  assert.match(wrangler, /binding = "RATEHAWK_HOTELS_TEST"/);
  assert.match(wrangler, /service = "fluxidi-ratehawk-hotels-api-test"/);
});

test("2. Booking Worker cannot construct provider Authorization", () => {
  const env = bookingEnv({ fetch: async () => new Response("{}") });
  assert.equal(bookingWorkerCanConstructRatehawkAuthorization(env), false);
  const facade = readFileSync(join(HERE, "ratehawk_hotels_facade.mjs"), "utf8");
  assert.equal(facade.includes("btoa("), false);
  assert.equal(facade.includes("_basicAuthHeader"), false);
  assert.equal(facade.includes("api.ratehawk.com"), false);
  const worker = readFileSync(join(HERE, "../fluxidi_booking_worker.js"), "utf8");
  assert.equal(worker.includes("ratehawk_provider.mjs"), false);
  assert.equal(worker.includes("handleRatehawkHotelpageRequest"), false);
});

test("3. Booking Worker delegates Hotelpage through RATEHAWK_HOTELS", async () => {
  const { state, fetchImpl } = trackingFetch(async () => ({
    status: 200,
    json: async () => etgOk(),
  }));
  const hotels = hotelsBinding(hotelsEnv(), fetchImpl);
  const env = bookingEnv(hotels.binding);
  const dto = await handlePublicRatehawkHotelpage({
    env,
    request: publicRequest(),
    body: await issuedBody(),
    now: RETRIEVED_AT,
  });
  assert.equal(hotels.state.calls, 1);
  assert.equal(state.calls, 1);
  assert.equal(dto.invoked, true);
  assert.equal(dto.ratehawk.state, "ready");
  assertSafeDto(dto);
});

test("4. Dedicated Worker alone performs provider transport", async () => {
  const { state, fetchImpl } = trackingFetch(async (url, options) => {
    assert.equal(String(url), "https://api.ratehawk.com/api/b2b/v3/search/hp/");
    assert.equal(options.method, "POST");
    assert.equal(String(options.headers.Authorization).startsWith("Basic "), true);
    return { status: 200, json: async () => etgOk() };
  });
  const booking = bookingEnv({
    fetch: async () => {
      throw new Error("booking_must_not_call_provider");
    },
  });
  assert.equal(bookingWorkerHasRatehawkCredentials(booking), false);
  const dto = await handleRatehawkHotelpageRequest({
    env: hotelsEnv(),
    body: await issuedBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.ratehawk.offers[0].room_name, "Superior Double");
});

test("5. Dedicated Worker has no public route", async () => {
  const { fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const publicResp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.workers.dev/internal/hotelpage", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    }),
    hotelsEnv(),
    { fetchImpl, now: RETRIEVED_AT },
  );
  assert.equal(publicResp.status, 404);
  const unknown = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/public/hotels/search", {
      method: "GET",
      headers: { "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY },
    }),
    hotelsEnv(),
    { fetchImpl, now: RETRIEVED_AT },
  );
  assert.equal(unknown.status, 404);
});

test("6. Missing Service Binding fails only the hotel route", async () => {
  const env = bookingEnv(undefined);
  const hotel = await handlePublicRatehawkHotelpage({
    env,
    request: publicRequest(),
    body: await issuedBody(),
    now: RETRIEVED_AT,
  });
  assert.equal(hotel.reason, "hotels_worker_binding_missing");
  assert.equal(hotel.ratehawk.offers.length, 0);
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 8 });
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  assert.equal(taxi.amount_minor, 2000);
});

test("7. Taxi booking remains green when RateHawk is disabled", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const hotels = hotelsBinding(hotelsEnv({ RATEHAWK_ENABLED: "0" }), fetchImpl);
  const env = bookingEnv(hotels.binding);
  const hotel = await handlePublicRatehawkHotelpage({
    env,
    request: publicRequest(),
    body: await issuedBody(),
    now: RETRIEVED_AT,
  });
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 4 });
  assert.equal(state.calls, 0);
  assert.equal(hotel.invoked, false);
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
});

test("8. Taxi booking remains green when RateHawk times out", async () => {
  const hotels = {
    fetch: async () => {
      const err = new Error("Aborted");
      err.name = "AbortError";
      throw err;
    },
  };
  const env = bookingEnv(hotels);
  const hotel = await handlePublicRatehawkHotelpage({
    env,
    request: publicRequest(),
    body: await issuedBody(),
    now: RETRIEVED_AT,
  });
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 3 });
  assert.equal(hotel.reason, "hotels_worker_unavailable");
  assert.equal(taxi.ok, true);
  assert.equal(taxi.amount_minor, 750);
});

test("9. Missing RATEHAWK_OFFER_REF_SECRET performs zero provider calls", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkHotelpageRequest({
    env: hotelsEnv({ RATEHAWK_OFFER_REF_SECRET: "" }),
    body: await issuedBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "offer_ref_secret_missing");
});

test("10. Tampered selected-card context performs zero provider calls", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const hotels = hotelsBinding(hotelsEnv(), fetchImpl);
  const env = bookingEnv(hotels.binding);
  const body = await issuedBody();
  body.hid = 1;
  body.selected_card_hid = 1;
  const dto = await handlePublicRatehawkHotelpage({
    env,
    request: publicRequest(),
    body,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 0);
  assert.equal(hotels.state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "view_stay_context_mismatch");
});

test("11. Expired selected-card context performs zero provider calls", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const hotels = hotelsBinding(hotelsEnv(), fetchImpl);
  const env = bookingEnv(hotels.binding);
  const body = await issuedBody({}, RETRIEVED_AT - 16 * 60 * 1000);
  const dto = await handlePublicRatehawkHotelpage({
    env,
    request: publicRequest(),
    body,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 0);
  assert.equal(hotels.state.calls, 0);
  assert.equal(dto.reason, "view_stay_context_expired");
});

test("12. Valid context allows exactly one selected hid", async () => {
  const { state, fetchImpl } = trackingFetch(async (_url, options) => {
    const posted = JSON.parse(options.body);
    assert.equal(posted.hid, 8473727);
    return { status: 200, json: async () => etgOk() };
  });
  const hotels = hotelsBinding(hotelsEnv(), fetchImpl);
  const env = bookingEnv(hotels.binding);
  const dto = await handlePublicRatehawkHotelpage({
    env,
    request: publicRequest(),
    body: await issuedBody(),
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.ratehawk.hid, 8473727);
  assert.equal(dto.ratehawk.offers.length, 1);
});

test("13. Concurrent identical calls respect single-flight", async () => {
  let started = 0;
  let release;
  const gate = new Promise((resolve) => {
    release = resolve;
  });
  const fetchImpl = async () => {
    started += 1;
    await gate;
    return { status: 200, json: async () => etgOk() };
  };
  const body = await issuedBody();
  const env = hotelsEnv();
  const first = handleRatehawkHotelpageRequest({
    env,
    body,
    fetchImpl,
    now: RETRIEVED_AT,
  });
  const second = handleRatehawkHotelpageRequest({
    env,
    body,
    fetchImpl,
    now: RETRIEVED_AT,
  });
  for (let i = 0; i < 50 && started === 0; i += 1) {
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
  assert.equal(started, 1);
  release();
  const [a, b] = await Promise.all([first, second]);
  assert.equal(started, 1);
  assert.equal(a.ratehawk.state, "ready");
  assert.equal(b.ratehawk.state, "ready");
});

test("14. Existing safe customer DTO remains unchanged", async () => {
  const { fetchImpl } = trackingFetch(async () => ({
    status: 200,
    json: async () => etgOk(),
  }));
  const hotels = hotelsBinding(hotelsEnv(), fetchImpl);
  const dto = await handlePublicRatehawkHotelpage({
    env: bookingEnv(hotels.binding),
    request: publicRequest(),
    body: await issuedBody(),
    now: RETRIEVED_AT,
  });
  const offer = dto.ratehawk.offers[0];
  assert.equal(dto.page, "HotelStayDetailPage");
  assert.equal(dto.rendered, false);
  assert.equal(offer.room_name, "Superior Double");
  assert.equal(offer.customer_total.amount_minor, 18000);
  assert.equal(offer.payment.type, "hotel");
  assert.equal(offer.deposit.disclosed, true);
  assert.equal(offer.no_show.currency, "USD");
  assert.equal(typeof offer.offer_ref, "string");
  assert.equal("reconciliation_amount" in offer, false);
  assert.equal("book_hash" in offer, false);
  assertSafeDto(dto);
  assert.equal(isRatehawkContentSyncAllowedOnCustomerRequest(), false);
  const search = buildRatehawkPublicSearchGuardPayload({ source: "ratehawk" });
  assert.equal(search.count, 0);
  assert.deepEqual(search.stays, []);
});

test("15. disabled test search makes zero binding calls", async () => {
  const hotels = hotelsBinding(testHotelsEnv(), async () => {
    throw new Error("must_not_call_hotels");
  });
  const dto = await handleAdminRatehawkTestSearch({
    env: bookingTestEnv(hotels.binding, { RATEHAWK_TEST_SEARCH_ENABLED: "0" }),
    now: RETRIEVED_AT,
  });
  assert.equal(hotels.state.calls, 0);
  assert.equal(dto.reason, "test_search_disabled");
  assert.equal(dto.binding_called, false);
});

test("16. disabled test Hotelpage makes zero binding calls", async () => {
  const hotels = hotelsBinding(testHotelsEnv(), async () => {
    throw new Error("must_not_call_hotels");
  });
  const stay = resolveRatehawkTestStay(RETRIEVED_AT);
  const issued = await issueRatehawkViewStayContext(CONTEXT_SECRET, stay, {
    now: RETRIEVED_AT,
  });
  const dto = await handleAdminRatehawkTestHotelpage({
    env: bookingTestEnv(hotels.binding, { RATEHAWK_TEST_HOTELPAGE_ENABLED: "0" }),
    body: { view_stay_context: issued.token },
    now: RETRIEVED_AT,
  });
  assert.equal(hotels.state.calls, 0);
  assert.equal(dto.reason, "test_hotelpage_disabled");
});

test("17. missing context secret fails only RateHawk test functionality", async () => {
  const hotels = hotelsBinding(testHotelsEnv(), async () => {
    throw new Error("must_not_call_hotels");
  });
  const env = bookingTestEnv(hotels.binding, {
    RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET: "",
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
  });
  const search = await handleAdminRatehawkTestSearch({ env, now: RETRIEVED_AT });
  const hotelpage = await handleAdminRatehawkTestHotelpage({
    env,
    body: { view_stay_context: "rhctx1.x.y" },
    now: RETRIEVED_AT,
  });
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 5 });
  assert.equal(hotels.state.calls, 0);
  assert.equal(search.reason, "view_stay_context_secret_missing");
  assert.equal(hotelpage.reason, "view_stay_context_secret_missing");
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  assert.equal(taxi.invoked_ratehawk_test, false);
});

test("18. public RateHawk search remains guarded and empty", () => {
  const search = buildRatehawkPublicSearchGuardPayload({ source: "ratehawk" });
  assert.equal(search.count, 0);
  assert.deepEqual(search.stays, []);
  assert.equal(search.warnings.includes("ratehawk_invocation_blocked"), true);
});

test("19. taxi-shaped work cannot reach test routes", () => {
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 12 });
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  const facade = readFileSync(join(HERE, "ratehawk_hotels_facade.mjs"), "utf8");
  assert.equal(facade.includes("runTaxiBookingIsolationProbe"), true);
  const street = readFileSync(join(HERE, "street_ride_never_planned.test.mjs"), "utf8");
  const fleet = readFileSync(join(HERE, "fleet_vehicle_tombstone.mjs"), "utf8");
  assert.equal(street.includes("/admin/hotels/ratehawk/test/search"), false);
  assert.equal(street.includes("/internal/test-search"), false);
  assert.equal(street.includes("RATEHAWK_HOTELS"), false);
  assert.equal(street.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(fleet.includes("/admin/hotels/ratehawk/test/hotelpage"), false);
  assert.equal(fleet.includes("/internal/test-hotelpage"), false);
  assert.equal(fleet.includes("RATEHAWK_HOTELS"), false);
  assert.equal(fleet.includes("RATEHAWK_HOTELS_TEST"), false);
});

test("Booking verifies context before proxying test Hotelpage", async () => {
  const hotels = hotelsBinding(testHotelsEnv(), async () => {
    throw new Error("must_not_call_hotels");
  });
  const dto = await handleAdminRatehawkTestHotelpage({
    env: bookingTestEnv(hotels.binding, { RATEHAWK_TEST_HOTELPAGE_ENABLED: "1" }),
    body: { view_stay_context: "rhctx1.not-a-token.nope" },
    now: RETRIEVED_AT,
  });
  assert.equal(hotels.state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.ok(
    dto.reason === "view_stay_context_required" ||
      dto.reason === "view_stay_context_malformed" ||
      dto.reason === "view_stay_context_tampered",
  );
});
