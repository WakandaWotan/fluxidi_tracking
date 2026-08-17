// RATEHAWK-P2T isolated admin test prebook + acceptance
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_test_prebook.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import { sha256Hex } from "./crypto_utils.js";
import { normalizeRatehawkRateOffer } from "./ratehawk_affiliate_contract.mjs";
import {
  handleAdminRatehawkTestPrebook,
  handleAdminRatehawkTestPrebookAccept,
  handlePublicRatehawkPrebook,
  runTaxiBookingIsolationProbe,
} from "../../booking/modules/ratehawk_hotels_facade.mjs";
import worker from "../../booking/fluxidi_booking_worker.js";
import {
  RATEHAWK_HOTELS_INTERNAL_PROXY,
  handleRatehawkHotelsWorkerFetch,
} from "../fluxidi_ratehawk_hotels_worker.js";
import { sealRatehawkOfferReference } from "./ratehawk_hotelpage_worker.mjs";
import {
  RATEHAWK_PREBOOK_PATH,
  buildOfferDisplaySnapshot,
  compareRatehawkPrebookTerms,
  fingerprintOfferDisplaySnapshot,
} from "./ratehawk_prebook_contract.mjs";
import {
  handleRatehawkPrebookRequest,
} from "./ratehawk_prebook_worker.mjs";
import {
  openRatehawkAcceptedReference,
  openRatehawkPrebookReference,
} from "./ratehawk_prebook_tokens.mjs";
import { createRatehawkQuotaBinding } from "./ratehawk_provider_quota.mjs";
import {
  RATEHAWK_TEST_DENIED_PATHS,
  RATEHAWK_TEST_HID,
  RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER,
  RATEHAWK_TEST_PREBOOK_TRIGGER,
  RATEHAWK_TEST_TOKEN_SURFACE,
  evaluateRatehawkTestPrebookGate,
  resolveRatehawkTestStay,
} from "./ratehawk_test_activation.mjs";
import {
  handleRatehawkTestPrebookAcceptRequest,
  handleRatehawkTestPrebookRequest,
} from "./ratehawk_test_prebook.mjs";
import { handleRatehawkTestHotelpageRequest } from "./ratehawk_test_hotelpage.mjs";
import { handleRatehawkTestSearchRequest } from "./ratehawk_test_search.mjs";
import { issueRatehawkViewStayContext } from "./ratehawk_view_stay_context.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TEST_API_KEY = "rh_test_prebook_secret_do_not_leak_xyz";
const TEST_KEY_ID = "18292";
const TEST_OFFER_SECRET = "rh_test_offer_ref_secret_not_real";
const PROD_OFFER_SECRET = "rh_prod_offer_ref_secret_not_real";
const CONTEXT_SECRET = "rh_view_stay_context_test_secret_not_real";
const BOOK_HASH = "h-test-prebook-secret-hash-do-not-leak";
const MATCH_HASH = "m-test-prebook-secret-hash-do-not-leak";
const ADMIN_TOKEN = "admin-test-token-not-real";
const NOW = Date.parse("2026-08-17T11:00:00.000Z");

const originalFetch = globalThis.fetch;
globalThis.fetch = async () => {
  throw new Error("global_fetch_must_not_be_used");
};
test.after(() => {
  globalThis.fetch = originalFetch;
});

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function hotelpageRate(overrides = {}) {
  return {
    book_hash: BOOK_HASH,
    match_hash: MATCH_HASH,
    room_name: "Superior Double",
    room_description: "City view",
    occupancy: { adults: 2 },
    meal: "breakfast",
    meal_data: { value: "breakfast", has_breakfast: true, no_child_meal: false },
    allotment: 2,
    rg_ext: { class: 3, quality: 2, bedding: 2 },
    amenities_data: ["non-smoking"],
    deposit: {
      amount: "50.00",
      currency_code: "EUR",
      is_refundable: true,
    },
    no_show: {
      amount: "25.00",
      currency_code: "USD",
      from_time: "18:00:00",
    },
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
          vat_data: { included: true, amount: "30.00", currency_code: "EUR" },
          tax_data: {
            taxes: [
              {
                name: "vat",
                included_by_supplier: true,
                amount: "30.00",
                currency_code: "EUR",
              },
              {
                name: "city_tax",
                included_by_supplier: false,
                amount: "7.50",
                currency_code: "EUR",
              },
            ],
          },
          cancellation_penalties: {
            free_cancellation_before: "2026-09-01T10:00:00",
            policies: [
              {
                start_at: null,
                end_at: "2026-09-01T10:00:00",
                amount_charge: "0.00",
                amount_show: "0.00",
              },
              {
                start_at: "2026-09-01T10:00:00",
                end_at: null,
                amount_charge: "180.00",
                amount_show: "180.00",
              },
            ],
          },
        },
      ],
    },
    ...overrides,
  };
}

function etgOk(rate = hotelpageRate(), hid = RATEHAWK_TEST_HID) {
  return {
    status: "ok",
    data: { hotels: [{ hid, rates: [rate] }] },
  };
}

function jsonResponse(body, status = 200) {
  return {
    status,
    json: async () => body,
  };
}

function trackingFetch(impl) {
  const state = { calls: 0, urls: [], methods: [], bodies: [] };
  const fetchImpl = async (url, options) => {
    state.calls += 1;
    state.urls.push(String(url));
    state.methods.push(String(options?.method || "GET"));
    state.bodies.push(options?.body ? JSON.parse(options.body) : null);
    return impl(url, options, state);
  };
  return { state, fetchImpl };
}

function testEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: TEST_KEY_ID,
    RATEHAWK_API_KEY: TEST_API_KEY,
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_WORKER_SURFACE: "test",
    RATEHAWK_ENABLED: "0",
    RATEHAWK_HOTELPAGE_ENABLED: "0",
    RATEHAWK_SEARCH_ENABLED: "0",
    RATEHAWK_PREBOOK_ENABLED: "0",
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    RATEHAWK_OFFER_REF_SECRET: TEST_OFFER_SECRET,
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

async function sealTestRh1(env, rate = hotelpageRate(), now = NOW, extra = {}) {
  const stay = resolveRatehawkTestStay(now);
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, true, offer.reason);
  const display = buildOfferDisplaySnapshot(offer);
  const sealed = await sealRatehawkOfferReference(env, {
    v: 1,
    purpose: "hotelpage_offer",
    surface: RATEHAWK_TEST_TOKEN_SURFACE,
    hid: stay.hid,
    book_hash: offer.book_hash,
    match_hash: offer.match_hash,
    retrieved_at: now,
    expires_at: now + 30 * 60 * 1000,
    checkin: stay.checkin,
    checkout: stay.checkout,
    residency: stay.residency,
    currency: stay.currency,
    guests: stay.guests,
    language: stay.language,
    display_snapshot: display,
    display_fingerprint: await sha256Hex(fingerprintOfferDisplaySnapshot(display)),
    ...extra,
  });
  assert.equal(sealed.ok, true);
  return { token: sealed.offer_ref, offer, display, stay };
}

function assertNoSecrets(value) {
  const text = JSON.stringify(value);
  assert.equal(text.includes(TEST_API_KEY), false);
  assert.equal(text.includes(BOOK_HASH), false);
  assert.equal(text.includes(MATCH_HASH), false);
  assert.equal(text.includes("fluxidi_affiliate_remuneration"), false);
  assert.equal(/Basic\s+[A-Za-z0-9+/=_-]{8,}/i.test(text), false);
}

function hotelsBinding(hotels, fetchImpl, now = NOW) {
  const state = { calls: 0, paths: [] };
  return {
    state,
    binding: {
      fetch: async (request) => {
        state.calls += 1;
        state.paths.push(new URL(request.url).pathname);
        return handleRatehawkHotelsWorkerFetch(request, hotels, {
          fetchImpl,
          now,
        });
      },
    },
  };
}

test("1. unauthenticated admin prebook returns 401 with zero binding calls", async () => {
  const state = { calls: 0 };
  const env = {
    ADMIN_TOKEN,
    RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    RATEHAWK_HOTELS: {
      fetch: async () => {
        state.calls += 1;
        throw new Error("must_not_call_production_binding");
      },
    },
    RATEHAWK_HOTELS_TEST: {
      fetch: async () => {
        state.calls += 1;
        throw new Error("must_not_call_test_binding");
      },
    },
  };
  const res = await worker.fetch(
    new Request("https://fluxidi-booking-api.internal/admin/hotels/ratehawk/test/prebook", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    }),
    env,
    {},
  );
  const dto = await res.json();
  assert.equal(res.status, 401);
  assert.equal(dto.error, "unauthorized");
  assert.equal(state.calls, 0);
});

test("2. unauthenticated acceptance returns 401 with zero binding calls", async () => {
  const state = { calls: 0 };
  const env = {
    ADMIN_TOKEN,
    RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    RATEHAWK_HOTELS: {
      fetch: async () => {
        state.calls += 1;
        throw new Error("must_not_call_production_binding");
      },
    },
    RATEHAWK_HOTELS_TEST: {
      fetch: async () => {
        state.calls += 1;
        throw new Error("must_not_call_test_binding");
      },
    },
  };
  const res = await worker.fetch(
    new Request(
      "https://fluxidi-booking-api.internal/admin/hotels/ratehawk/test/prebook/accept",
      {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: "{}",
      },
    ),
    env,
    {},
  );
  const dto = await res.json();
  assert.equal(res.status, 401);
  assert.equal(dto.error, "unauthorized");
  assert.equal(state.calls, 0);
});

test("3. test prebook gate off performs zero provider calls", async () => {
  const env = testEnv({ RATEHAWK_TEST_PREBOOK_ENABLED: "0" });
  const { token } = await sealTestRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "test_prebook_disabled");
  assert.equal(dto.prebook_ref, null);
  const booking = await handleAdminRatehawkTestPrebook({
    env: {
      RATEHAWK_TEST_PREBOOK_ENABLED: "0",
      RATEHAWK_HOTELS_TEST: {
        fetch: async () => {
          throw new Error("must_not_call_test_binding");
        },
      },
    },
    body: { offer_ref: token, locale: "nl" },
  });
  assert.equal(booking.reason, "test_prebook_disabled");
  assert.equal(booking.binding_called, false);
});

test("4. missing test binding fails only admin test prebook", async () => {
  let productionCalls = 0;
  const env = {
    RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    RATEHAWK_HOTELS: {
      fetch: async () => {
        productionCalls += 1;
        return {
          json: async () => ({
            ok: true,
            invoked: false,
            reason: "prebook_disabled",
          }),
        };
      },
    },
  };
  const dto = await handleAdminRatehawkTestPrebook({
    env,
    body: { offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(dto.reason, "hotels_test_worker_binding_missing");
  assert.equal(dto.binding_called, false);
  const publicDto = await handlePublicRatehawkPrebook({
    env: {
      BOOKING_KV: {
        async get() {
          return null;
        },
        async put() {},
      },
      RATEHAWK_HOTELS: env.RATEHAWK_HOTELS,
    },
    request: new Request("https://fluxidi-booking-api.internal/public/hotels/ratehawk/prebook"),
    body: { trigger: "prebook_revalidation", offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(productionCalls, 1);
  assert.equal(publicDto.reason, "prebook_disabled");
});

test("5. public routes cannot use the test binding", async () => {
  const facade = readFileSync(
    join(HERE, "../../booking/modules/ratehawk_hotels_facade.mjs"),
    "utf8",
  );
  const publicFn = facade.slice(
    facade.indexOf("export async function handlePublicRatehawkPrebook"),
    facade.indexOf("function _safeTestUnavailable"),
  );
  assert.match(publicFn, /RATEHAWK_HOTELS/);
  assert.equal(publicFn.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(publicFn.includes("/internal/test-prebook"), false);
  let testCalls = 0;
  await handlePublicRatehawkPrebook({
    env: {
      BOOKING_KV: {
        async get() {
          return null;
        },
        async put() {},
      },
      RATEHAWK_HOTELS: {
        async fetch() {
          return {
            json: async () => ({ ok: true, invoked: false, reason: "prebook_disabled" }),
          };
        },
      },
      RATEHAWK_HOTELS_TEST: {
        async fetch() {
          testCalls += 1;
          throw new Error("must_not_use_test_binding");
        },
      },
    },
    request: new Request("https://fluxidi-booking-api.internal/public/hotels/ratehawk/prebook"),
    body: { trigger: "prebook_revalidation", offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(testCalls, 0);
});

test("6. test routes cannot use the production binding", async () => {
  const facade = readFileSync(
    join(HERE, "../../booking/modules/ratehawk_hotels_facade.mjs"),
    "utf8",
  );
  const prebookFn = facade.slice(
    facade.indexOf("export async function handleAdminRatehawkTestPrebook"),
    facade.indexOf("export function runTaxiBookingIsolationProbe"),
  );
  assert.equal(prebookFn.includes("env.RATEHAWK_HOTELS"), false);
  assert.match(prebookFn, /RATEHAWK_HOTELS_TEST_PREBOOK_PATH/);
  let productionCalls = 0;
  const dto = await handleAdminRatehawkTestPrebook({
    env: {
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
      RATEHAWK_HOTELS: {
        fetch: async () => {
          productionCalls += 1;
          throw new Error("must_not_call_production_binding");
        },
      },
    },
    body: { offer_ref: "rh1.aaa.bbb", locale: "nl" },
  });
  assert.equal(productionCalls, 0);
  assert.equal(dto.reason, "hotels_test_worker_binding_missing");
});

test("7. production Worker rejects /internal/test-prebook", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const resp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/test-prebook", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: "{}",
    }),
    testEnv({
      RATEHAWK_WORKER_SURFACE: "production",
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    }),
    { fetchImpl, now: NOW },
  );
  const dto = await resp.json();
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "test_worker_required");
  assert.equal(state.calls, 0);
});

test("7b. test prebook cannot run on a production Worker surface even if gate is 1", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  assert.equal(
    evaluateRatehawkTestPrebookGate({
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
      RATEHAWK_WORKER_SURFACE: "production",
    }).reason,
    "test_worker_required",
  );
  const dto = await handleRatehawkTestPrebookRequest({
    env: testEnv({
      RATEHAWK_WORKER_SURFACE: "production",
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    }),
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: "rh1.aaa.bbb",
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "test_worker_required");
});

test("8. test Worker rejects production /internal/prebook", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const resp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/prebook", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: JSON.stringify({ trigger: "prebook_revalidation", offer_ref: "rh1.a.b" }),
    }),
    testEnv({ RATEHAWK_PREBOOK_ENABLED: "1" }),
    { fetchImpl, now: NOW },
  );
  const dto = await resp.json();
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "production_path_forbidden_on_test_worker");
  assert.equal(state.calls, 0);
});

test("9. test Worker rejects production environment or sandbox host", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const production = await handleRatehawkTestPrebookRequest({
    env: testEnv({ RATEHAWK_ENVIRONMENT: "production" }),
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(production.reason, "test_environment_required");
  const sandbox = await handleRatehawkTestPrebookRequest({
    env: testEnv({
      RATEHAWK_ENVIRONMENT: "sandbox",
      RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com",
    }),
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(sandbox.reason, "test_environment_required");
  const host = await handleRatehawkTestPrebookRequest({
    env: testEnv({ RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com" }),
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.ok(
    host.reason === "test_host_required" || host.reason === "test_environment_required",
  );
});

test("10. only official hid 8473727 is accepted", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env, hotelpageRate(), NOW, { hid: 1 });
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.reason, "test_hid_not_allowlisted");
});

test("11. arbitrary dates guests currency or hid cannot widen context", async () => {
  const env = testEnv();
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dates = await sealTestRh1(env, hotelpageRate(), NOW, {
    checkin: "2026-09-15",
    checkout: "2026-09-16",
  });
  const dateDto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: dates.token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(dateDto.reason, "test_dates_not_server_owned");
  const guests = await sealTestRh1(env, hotelpageRate(), NOW, {
    guests: [{ adults: 3, children: [] }],
  });
  const guestDto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: guests.token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(guestDto.reason, "test_guests_not_allowlisted");
  const currency = await sealTestRh1(env, hotelpageRate(), NOW, { currency: "USD" });
  const currencyDto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: currency.token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(currencyDto.reason, "test_currency_not_allowlisted");
  assert.equal(state.calls, 0);
});

test("12. client-supplied hashes host or endpoint are rejected", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  for (const extra of [
    { book_hash: BOOK_HASH },
    { match_hash: MATCH_HASH },
    { hash: BOOK_HASH },
    { host: "api.ratehawk.com" },
    { endpoint: RATEHAWK_PREBOOK_PATH },
    { hid: RATEHAWK_TEST_HID },
    { price: "1.00" },
    { currency: "EUR" },
  ]) {
    const dto = await handleRatehawkTestPrebookRequest({
      env,
      body: {
        trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
        offer_ref: token,
        locale: "nl",
        ...extra,
      },
      fetchImpl,
      now: NOW,
    });
    assert.equal(dto.reason, "client_control_forbidden", JSON.stringify(extra));
    assert.equal(dto.invoked, false);
  }
  assert.equal(state.calls, 0);
});

test("13. production rh1 cannot be accepted as a test token", async () => {
  const test = testEnv();
  const stay = resolveRatehawkTestStay(NOW);
  const offer = normalizeRatehawkRateOffer(hotelpageRate());
  const display = buildOfferDisplaySnapshot(offer);
  const productionShaped = await sealRatehawkOfferReference(test, {
    v: 1,
    purpose: "hotelpage_offer",
    hid: stay.hid,
    book_hash: offer.book_hash,
    match_hash: offer.match_hash,
    retrieved_at: NOW,
    expires_at: NOW + 30 * 60 * 1000,
    checkin: stay.checkin,
    checkout: stay.checkout,
    residency: stay.residency,
    currency: stay.currency,
    guests: stay.guests,
    display_snapshot: display,
  });
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const missingSurface = await handleRatehawkTestPrebookRequest({
    env: test,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: productionShaped.offer_ref,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(missingSurface.reason, "production_offer_ref_forbidden");
  const prodEnv = testEnv({ RATEHAWK_OFFER_REF_SECRET: PROD_OFFER_SECRET });
  const prodToken = await sealRatehawkOfferReference(prodEnv, {
    v: 1,
    purpose: "hotelpage_offer",
    hid: stay.hid,
    book_hash: offer.book_hash,
    match_hash: offer.match_hash,
    retrieved_at: NOW,
    expires_at: NOW + 30 * 60 * 1000,
    checkin: stay.checkin,
    checkout: stay.checkout,
    residency: stay.residency,
    currency: stay.currency,
    guests: stay.guests,
    display_snapshot: display,
  });
  const otherSecret = await handleRatehawkTestPrebookRequest({
    env: test,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: prodToken.offer_ref,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(otherSecret.reason, "offer_ref_invalid");
  assert.equal(state.calls, 0);
});

test("14. expired tampered or mismatched test rh1 fails before transport", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const expired = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW + 40 * 60 * 1000,
  });
  assert.equal(expired.reason, "offer_expired");
  const tampered = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: `${token.slice(0, -2)}aa`,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.ok(["rh1_invalid", "offer_ref_invalid"].includes(tampered.reason));
  const mismatched = await sealTestRh1(env, hotelpageRate(), NOW, { residency: "nl" });
  const mismatchDto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: mismatched.token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(mismatchDto.reason, "test_residency_not_allowlisted");
  assert.equal(state.calls, 0);
});

test("15-16. valid mocked test rh1 makes exactly one prebook call and no retry", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  assert.equal(state.methods[0], "POST");
  assert.equal(state.urls[0], `https://api.ratehawk.com${RATEHAWK_PREBOOK_PATH}`);
  assert.deepEqual(state.bodies[0], { hash: BOOK_HASH });
  assert.equal(dto.invoked, true);
  assert.equal(dto.acceptance_allowed, true);
  assert.equal(dto.changed, false);
  assert.equal(dto.prebook_ref.startsWith("rhp1."), true);
  assertNoSecrets(dto);
});

test("17. quota denial makes zero transport calls and returns integer retry_after", async () => {
  const env = testEnv({
    RATEHAWK_PROVIDER_QUOTA: {
      fetch: async () =>
        new Response(
          JSON.stringify({
            allowed: false,
            reason: "provider_quota_exhausted",
            retry_after: 12,
          }),
        ),
    },
  });
  const { token } = await sealTestRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "provider_quota_exhausted");
  assert.equal(dto.retry_after, 12);
  assert.equal(Number.isInteger(dto.retry_after), true);
});

test("18. timeout and provider error are redacted", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const timeout = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl: async () => {
      const err = new Error("aborted");
      err.name = "AbortError";
      throw err;
    },
    now: NOW,
  });
  assert.equal(timeout.invoked, true);
  assert.equal(timeout.retryable, true);
  assert.equal(timeout.reason, "timeout");
  assertNoSecrets(timeout);
  const provider = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl: async () => jsonResponse({ status: "error" }, 500),
    now: NOW,
  });
  assert.equal(provider.reason, "provider_error");
  assert.equal(provider.retryable, true);
  assertNoSecrets(provider);
});

test("19. production prebook normalizer and comparator are reused", () => {
  const source = readFileSync(join(HERE, "ratehawk_test_prebook.mjs"), "utf8");
  assert.match(source, /import \{ normalizeRatehawkRateOffer \}/);
  assert.match(source, /from "\.\/ratehawk_affiliate_contract\.mjs"/);
  assert.match(source, /compareRatehawkPrebookTerms/);
  assert.match(source, /from "\.\/ratehawk_prebook_contract\.mjs"/);
  assert.equal(source.includes("function normalizeRatehawkRateOffer"), false);
  assert.equal(source.includes("function compareRatehawkPrebookTerms"), false);
  assert.equal(typeof normalizeRatehawkRateOffer, "function");
  assert.equal(typeof compareRatehawkPrebookTerms, "function");
});

test("20. same terms produce a deliberate-confirmation result", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const dto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  assert.equal(dto.changed, false);
  assert.equal(dto.changes.length, 0);
  assert.equal(dto.acceptance_allowed, true);
  assert.equal(dto.progress_blocked, false);
  assert.equal(dto.prebook_ref.startsWith("rhp1."), true);
});

test("21. changed terms produce a complete before/after disclosure", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const after = clone(hotelpageRate());
  after.room_name = "Deluxe Suite";
  after.payment_options.payment_types[0].show_amount = "195.00";
  after.payment_options.payment_types[0].amount = "195.00";
  const dto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "en",
    },
    fetchImpl: async () => jsonResponse(etgOk(after)),
    now: NOW,
  });
  assert.equal(dto.changed, true);
  assert.ok(dto.changes.some((row) => row.code === "price_changed"));
  assert.ok(dto.changes.some((row) => row.code === "room_changed"));
  const price = dto.changes.find((row) => row.code === "price_changed");
  assert.ok(price.before);
  assert.ok(price.after);
  assert.equal(dto.acceptance_allowed, true);
});

test("22. currency and availability changes block progress", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const currencyRate = clone(hotelpageRate());
  currencyRate.payment_options.payment_types[0].show_currency_code = "USD";
  const currency = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl: async () => jsonResponse(etgOk(currencyRate)),
    now: NOW,
  });
  assert.equal(currency.progress_blocked, true);
  assert.equal(currency.acceptance_allowed, false);
  assert.equal(currency.prebook_ref, null);
  assert.equal(currency.reason, "currency_changed");
  const empty = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl: async () => jsonResponse({ status: "ok", data: { hotels: [] } }),
    now: NOW,
  });
  assert.equal(empty.reason, "availability_lost");
  assert.equal(empty.progress_blocked, true);
  assert.equal(empty.prebook_ref, null);
});

test("23. rhp1 is opaque and context-bound to the test surface", async () => {
  const env = testEnv();
  const { token, stay } = await sealTestRh1(env);
  const dto = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  assert.equal(dto.prebook_ref.startsWith("rhp1."), true);
  assertNoSecrets(dto);
  const opened = await openRatehawkPrebookReference(env, dto.prebook_ref, { now: NOW });
  assert.equal(opened.ok, true);
  assert.equal(opened.claims.purpose, "prebook");
  assert.equal(opened.claims.surface, RATEHAWK_TEST_TOKEN_SURFACE);
  assert.equal(opened.claims.hid, RATEHAWK_TEST_HID);
  assert.equal(opened.claims.checkin, stay.checkin);
  assert.equal(opened.claims.checkout, stay.checkout);
  assert.equal(opened.claims.book_hash, BOOK_HASH);
  const expired = await openRatehawkPrebookReference(env, dto.prebook_ref, {
    now: NOW + 16 * 60 * 1000,
  });
  assert.equal(expired.ok, false);
  assert.equal(expired.reason, "rhp1_expired");
});

test("24-26. acceptance makes zero provider calls, issues rha1, and rejects stale revision", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const prebook = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  const accepted = await handleRatehawkTestPrebookAcceptRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER,
      prebook_ref: prebook.prebook_ref,
      terms_revision: prebook.terms_revision,
      locale: "nl",
    },
    now: NOW + 1000,
  });
  assert.equal(state.calls, 1);
  assert.equal(accepted.invoked, false);
  assert.equal(accepted.accepted, true);
  assert.equal(accepted.accepted_ref.startsWith("rha1."), true);
  const opened = await openRatehawkAcceptedReference(env, accepted.accepted_ref, {
    now: NOW + 1000,
  });
  assert.equal(opened.ok, true);
  assert.equal(opened.claims.surface, RATEHAWK_TEST_TOKEN_SURFACE);
  assert.equal(opened.claims.terms_revision, prebook.terms_revision);
  const mismatch = await handleRatehawkTestPrebookAcceptRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER,
      prebook_ref: prebook.prebook_ref,
      terms_revision: "different-revision",
      locale: "nl",
    },
    now: NOW + 1000,
  });
  assert.equal(mismatch.reason, "terms_revision_mismatch");
  assert.equal(mismatch.accepted_ref, null);
});

test("27. safe dispute snapshot contains no prohibited data", async () => {
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const prebook = await handleRatehawkTestPrebookRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_TRIGGER,
      offer_ref: token,
      locale: "nl",
    },
    fetchImpl: async () => jsonResponse(etgOk()),
    now: NOW,
  });
  const accepted = await handleRatehawkTestPrebookAcceptRequest({
    env,
    body: {
      trigger: RATEHAWK_TEST_PREBOOK_ACCEPT_TRIGGER,
      prebook_ref: prebook.prebook_ref,
      terms_revision: prebook.terms_revision,
      locale: "nl",
    },
    now: NOW + 2000,
  });
  const snap = accepted.dispute_snapshot;
  assert.equal(snap.ok, true);
  assert.equal(snap.hid, RATEHAWK_TEST_HID);
  assert.equal(snap.room_name, "Superior Double");
  assert.equal(snap.customer_total.currency, "EUR");
  assert.ok(Array.isArray(snap.included_taxes));
  assert.ok(snap.payment);
  assert.ok(snap.cancellation);
  assert.ok(snap.no_show);
  assert.ok(snap.deposit);
  assert.ok(snap.omitted.includes("book_hash"));
  assert.ok(snap.omitted.includes("commission"));
  assert.ok(snap.omitted.includes("reconciliation_amount"));
  assertNoSecrets(snap);
  assertNoSecrets(accepted);
});

test("28. no prebook token or hash is logged or saved", () => {
  const hotelsSource = readFileSync(join(HERE, "ratehawk_test_prebook.mjs"), "utf8");
  const facade = readFileSync(
    join(HERE, "../../booking/modules/ratehawk_hotels_facade.mjs"),
    "utf8",
  );
  const adminPrebook = facade.slice(
    facade.indexOf("function _safeTestPrebookUnavailable"),
    facade.indexOf("export function runTaxiBookingIsolationProbe"),
  );
  const source = `${hotelsSource}\n${adminPrebook}`;
  assert.equal(
    /console\.(log|info|debug|warn)\([^\n]*(offer_ref|prebook_ref|book_hash|rhp1|rha1)/.test(
      source,
    ),
    false,
  );
  assert.equal(source.includes("BOOKING_KV"), false);
  assert.equal(source.includes("RATEHAWK_HOTELS_DB"), false);
});

test("29. existing admin test Search remains green", async () => {
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkTestSearchRequest({
    env: testEnv({ RATEHAWK_TEST_PREBOOK_ENABLED: "0" }),
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.invoked, true);
  assert.match(String(dto.view_stay_context || ""), /^rhctx1\./);
  assertNoSecrets(dto);
});

test("30. existing admin test Hotelpage remains green and seals surface=test", async () => {
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const stay = resolveRatehawkTestStay(NOW);
  const issued = await issueRatehawkViewStayContext(CONTEXT_SECRET, stay, { now: NOW });
  const dto = await handleRatehawkTestHotelpageRequest({
    env: testEnv({ RATEHAWK_TEST_PREBOOK_ENABLED: "0" }),
    body: { view_stay_context: issued.token },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.ratehawk.state, "ready");
  assert.equal(dto.ratehawk.offers[0].offer_ref.startsWith("rh1."), true);
  assert.equal("book_hash" in dto.ratehawk.offers[0], false);
  assertNoSecrets(dto);
});

test("31. public Search remains fail-closed with production gates off", async () => {
  const res = await worker.fetch(
    new Request("https://fluxidi-booking-api.internal/public/hotels/search?source=ratehawk"),
    {
      RATEHAWK_HOTELS: {
        fetch: async () => {
          throw new Error("must_not_call_hotels");
        },
      },
      RATEHAWK_HOTELS_TEST: {
        fetch: async () => {
          throw new Error("must_not_call_test_binding");
        },
      },
    },
    {},
  );
  const dto = await res.json();
  assert.equal(dto.count, 0);
  assert.equal(dto.warnings.includes("ratehawk_invocation_blocked"), true);
});

test("32. taxi isolation cannot reach test prebook", () => {
  const taxi = runTaxiBookingIsolationProbe({ distance_km: 8 });
  assert.equal(taxi.ok, true);
  assert.equal(taxi.invoked_ratehawk, false);
  assert.equal(taxi.invoked_ratehawk_test, false);
  const street = readFileSync(
    join(HERE, "../../booking/modules/street_ride_never_planned.test.mjs"),
    "utf8",
  );
  const fleet = readFileSync(
    join(HERE, "../../booking/modules/fleet_vehicle_tombstone.mjs"),
    "utf8",
  );
  assert.equal(street.includes("/admin/hotels/ratehawk/test/prebook"), false);
  assert.equal(fleet.includes("/internal/test-prebook"), false);
});

test("33. all production and test prebook gates remain 0", () => {
  const hotels = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
  const booking = readFileSync(join(HERE, "../../booking/wrangler.toml"), "utf8");
  const top = hotels.slice(0, hotels.indexOf("[env.test]"));
  const testSection = hotels.slice(hotels.indexOf("[env.test]"));
  assert.match(top, /RATEHAWK_PREBOOK_ENABLED = "0"/);
  assert.match(top, /RATEHAWK_TEST_PREBOOK_ENABLED = "0"/);
  assert.match(testSection, /RATEHAWK_PREBOOK_ENABLED = "0"/);
  assert.match(testSection, /RATEHAWK_TEST_PREBOOK_ENABLED = "0"/);
  assert.match(booking, /RATEHAWK_TEST_PREBOOK_ENABLED = "0"/);
  assert.equal(/RATEHAWK_PREBOOK_ENABLED\s*=\s*"1"/.test(hotels), false);
  assert.equal(/RATEHAWK_TEST_PREBOOK_ENABLED\s*=\s*"1"/.test(hotels), false);
  assert.equal(/RATEHAWK_TEST_PREBOOK_ENABLED\s*=\s*"1"/.test(booking), false);
  assert.equal(
    evaluateRatehawkTestPrebookGate({
      RATEHAWK_PREBOOK_ENABLED: "1",
      RATEHAWK_TEST_PREBOOK_ENABLED: "0",
      RATEHAWK_WORKER_SURFACE: "test",
    }).ok,
    false,
  );
  assert.equal(
    evaluateRatehawkTestPrebookGate({
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
      RATEHAWK_WORKER_SURFACE: "production",
    }).reason,
    "test_worker_required",
  );
});

test("34. no booking finish cancel or voucher implementation is introduced", async () => {
  const source = [
    readFileSync(join(HERE, "ratehawk_test_prebook.mjs"), "utf8"),
    readFileSync(join(HERE, "ratehawk_test_activation.mjs"), "utf8"),
  ].join("\n");
  assert.equal(source.includes("/public/hotels/ratehawk/book"), false);
  assert.equal(source.includes("/public/hotels/ratehawk/finish"), false);
  assert.equal(source.includes("/public/hotels/ratehawk/cancel"), false);
  assert.equal(source.includes("/public/hotels/ratehawk/voucher"), false);
  assert.equal(source.includes("/api/b2b/v3/hotel/order/booking/form/"), true);
  assert.equal(RATEHAWK_TEST_DENIED_PATHS.includes("/api/b2b/v3/hotel/prebook/"), true);
  assert.equal(
    RATEHAWK_TEST_DENIED_PATHS.includes("/api/b2b/v3/hotel/order/booking/form/"),
    true,
  );
  const env = testEnv();
  const { token } = await sealTestRh1(env);
  const publicDto = await handleRatehawkPrebookRequest({
    env: testEnv({
      RATEHAWK_TEST_PREBOOK_ENABLED: "1",
      RATEHAWK_PREBOOK_ENABLED: "0",
    }),
    body: { trigger: "prebook_revalidation", offer_ref: token, locale: "nl" },
    fetchImpl: async () => {
      throw new Error("must_not_call_ratehawk");
    },
    now: NOW,
  });
  assert.equal(publicDto.reason, "production_path_forbidden_on_test_worker");
});

test("admin test chain rhctx1 to rh1 to rhp1 to rha1 stays on the test binding", async () => {
  const { state, fetchImpl } = trackingFetch(async (url) => {
    if (String(url).includes("/search/serp/hotels/")) return jsonResponse(etgOk());
    if (String(url).includes("/search/hp/")) return jsonResponse(etgOk());
    if (String(url).includes("/hotel/prebook/")) return jsonResponse(etgOk());
    throw new Error(`unexpected_url:${url}`);
  });
  const hotels = hotelsBinding(testEnv(), fetchImpl);
  const bookingEnv = {
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    RATEHAWK_TEST_PREBOOK_ENABLED: "1",
    RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_HOTELS: {
      fetch: async () => {
        throw new Error("must_not_call_production_binding");
      },
    },
    RATEHAWK_HOTELS_TEST: hotels.binding,
  };
  const search = await handleRatehawkTestSearchRequest({
    env: testEnv(),
    fetchImpl,
    now: NOW,
  });
  assert.match(String(search.view_stay_context || ""), /^rhctx1\./);
  const hotelpage = await handleRatehawkTestHotelpageRequest({
    env: testEnv(),
    body: { view_stay_context: search.view_stay_context },
    fetchImpl,
    now: NOW,
  });
  const offerRef = hotelpage.ratehawk.offers[0].offer_ref;
  assert.match(offerRef, /^rh1\./);
  const prebook = await handleAdminRatehawkTestPrebook({
    env: bookingEnv,
    body: { offer_ref: offerRef, locale: "nl" },
  });
  assert.deepEqual(hotels.state.paths, ["/internal/test-prebook"]);
  assert.equal(prebook.prebook_ref.startsWith("rhp1."), true);
  const accepted = await handleAdminRatehawkTestPrebookAccept({
    env: bookingEnv,
    body: {
      prebook_ref: prebook.prebook_ref,
      terms_revision: prebook.terms_revision,
      locale: "nl",
    },
  });
  assert.deepEqual(hotels.state.paths, [
    "/internal/test-prebook",
    "/internal/test-prebook/accept",
  ]);
  assert.equal(accepted.accepted_ref.startsWith("rha1."), true);
  assert.equal(state.urls.filter((url) => url.includes("/hotel/prebook/")).length, 1);
});

test("missing internal proxy header cannot reach test prebook", async () => {
  const resp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api-test.internal/internal/test-prebook", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
    }),
    testEnv(),
  );
  assert.equal(resp.status, 404);
});

test("Flutter customer sources cannot reach admin test prebook", () => {
  const flutter = [
    readFileSync(join(HERE, "../../../lib/hotels/ratehawk_search.dart"), "utf8"),
    readFileSync(join(HERE, "../../../lib/hotels/ratehawk_search_panel.dart"), "utf8"),
    readFileSync(join(HERE, "../../../lib/hotels/ratehawk_hotelpage.dart"), "utf8"),
    readFileSync(join(HERE, "../../../lib/hotels/ratehawk_prebook.dart"), "utf8"),
    readFileSync(join(HERE, "../../../lib/hotels/hotels_page.dart"), "utf8"),
  ].join("\n");
  assert.equal(flutter.includes("/admin/hotels/ratehawk/test/prebook"), false);
  assert.equal(flutter.includes("RATEHAWK_HOTELS_TEST"), false);
  assert.equal(flutter.includes("x-admin-token"), false);
});
