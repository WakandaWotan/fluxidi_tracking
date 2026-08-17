// RATEHAWK-P2 admin test-search / test-Hotelpage isolation
//
// Run:
//   node --test workers/booking/modules/ratehawk_test_admin_routes.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import worker from "../fluxidi_booking_worker.js";
import {
  handleAdminRatehawkTestHotelpage,
  handleAdminRatehawkTestSearch,
  issueRatehawkViewStayContext,
} from "./ratehawk_hotels_facade.mjs";
import { handleRatehawkHotelsWorkerFetch } from "../../ratehawk-hotels/fluxidi_ratehawk_hotels_worker.js";
import { createRatehawkQuotaBinding } from "../../ratehawk-hotels/modules/ratehawk_provider_quota.mjs";
import { resolveRatehawkTestStay } from "../../ratehawk-hotels/modules/ratehawk_test_activation.mjs";

const ADMIN_TOKEN = "admin-test-token-not-real";
const CONTEXT_SECRET = "rh_view_stay_context_test_secret_not_real";
const OFFER_SECRET = "rh_offer_ref_test_secret_not_real";
const TEST_API_KEY = "rh_test_secret_do_not_leak_xyz";
const NOW = Date.parse("2026-08-17T07:10:00.000Z");

function hotelsEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: "18292",
    RATEHAWK_API_KEY: TEST_API_KEY,
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_WORKER_SURFACE: "test",
    RATEHAWK_ENABLED: "0",
    RATEHAWK_HOTELPAGE_ENABLED: "0",
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    RATEHAWK_OFFER_REF_SECRET: OFFER_SECRET,
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
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

test("17. unauthenticated admin test routes return 401 and make zero binding calls", async () => {
  const state = { calls: 0 };
  const env = {
    ADMIN_TOKEN,
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
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
  for (const path of [
    "/admin/hotels/ratehawk/test/search",
    "/admin/hotels/ratehawk/test/hotelpage",
    "/admin/hotels/ratehawk/test/prebook",
    "/admin/hotels/ratehawk/test/prebook/accept",
  ]) {
    const res = await worker.fetch(
      new Request(`https://fluxidi-booking-api.internal${path}`, {
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
  }
  assert.equal(state.calls, 0);
});

test("Hotels binding failure affects only the test hotel route", async () => {
  const env = {
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_HOTELS: {
      fetch: async () => ({
        json: async () => {
          throw new Error("production_hotels_must_not_be_called");
        },
      }),
    },
    RATEHAWK_HOTELS_TEST: {
      fetch: async () => {
        throw new Error("hotels_test_down");
      },
    },
  };
  const search = await handleAdminRatehawkTestSearch({ env, now: NOW });
  const stay = resolveRatehawkTestStay(NOW);
  const issued = await issueRatehawkViewStayContext(CONTEXT_SECRET, stay, { now: NOW });
  const hotelpage = await handleAdminRatehawkTestHotelpage({
    env,
    body: { view_stay_context: issued.token },
    now: NOW,
  });
  assert.equal(search.reason, "hotels_worker_unavailable");
  assert.equal(hotelpage.reason, "hotels_worker_unavailable");
  const publicSearch = await worker.fetch(
    new Request("https://fluxidi-booking-api.internal/public/hotels/search?source=ratehawk"),
    env,
    {},
  );
  const guarded = await publicSearch.json();
  assert.equal(guarded.count, 0);
  assert.equal(guarded.warnings.includes("ratehawk_invocation_blocked"), true);
});

test("authenticated test search proxies only the private test-search path", async () => {
  const { state, binding } = hotelsBinding(hotelsEnv(), async () => ({
    status: 200,
    json: async () => ({
      status: "ok",
      data: {
        hotels: [
          {
            hid: 8473727,
            rates: [
              {
                book_hash: "h-hp-secret-hash-do-not-leak",
                match_hash: "m-hp-secret-hash-do-not-leak",
                room_name: "Superior Double",
                occupancy: { adults: 2 },
                meal: "breakfast",
                meal_data: { value: "breakfast", has_breakfast: true },
                allotment: 2,
                rg_ext: { class: 3 },
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
                      tax_data: { taxes: [] },
                      cancellation_penalties: {
                        free_cancellation_before: "2026-09-01T10:00:00",
                        policies: [],
                      },
                    },
                  ],
                },
              },
            ],
          },
        ],
      },
    }),
  }));
  const dto = await handleAdminRatehawkTestSearch({
    env: {
      RATEHAWK_TEST_SEARCH_ENABLED: "1",
      RATEHAWK_TEST_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
      RATEHAWK_HOTELS: {
        fetch: async () => {
          throw new Error("production_hotels_must_not_be_called");
        },
      },
      RATEHAWK_HOTELS_TEST: binding,
    },
    now: NOW,
  });
  assert.equal(state.calls, 1);
  assert.deepEqual(state.paths, ["/internal/test-search"]);
  assert.equal(dto.invoked, true);
  assert.match(String(dto.view_stay_context || ""), /^rhctx1\./);
  assert.equal(JSON.stringify(dto).includes("h-hp-secret-hash-do-not-leak"), false);
});

test("public approved-local search is unchanged by test routes", async () => {
  const res = await worker.fetch(
    new Request("https://fluxidi-booking-api.internal/public/hotels/search"),
    {},
    {},
  );
  const dto = await res.json();
  assert.equal(res.status, 200);
  assert.equal(dto.source, "approved-local");
  assert.ok(dto.count >= 1);
});
