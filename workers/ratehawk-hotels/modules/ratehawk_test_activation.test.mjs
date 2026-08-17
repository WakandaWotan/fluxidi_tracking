// RATEHAWK-P2 gated test search + test Hotelpage
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_test_activation.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import { RATEHAWK_ALLOWED_OPERATIONS } from "./ratehawk_provider.mjs";
import { createRatehawkQuotaBinding } from "./ratehawk_provider_quota.mjs";
import {
  RATEHAWK_SERP_GEO_PATH,
  RATEHAWK_SERP_HOTELS_PATH,
  RATEHAWK_SERP_REGION_PATH,
} from "./ratehawk_market_search_limits.mjs";
import { RATEHAWK_HOTELPAGE_PATH } from "./ratehawk_hotelpage_contract.mjs";
import {
  RATEHAWK_TEST_DENIED_PATHS,
  RATEHAWK_TEST_HID,
  RATEHAWK_TEST_OPERATION_SERP,
  assertRatehawkTestHids,
  assertRatehawkTestHid,
  assertRatehawkTestProviderConfig,
  assertRatehawkTestProviderPath,
  assertRatehawkTestStay,
  buildRatehawkTestSerpRequest,
  evaluateRatehawkTestHotelpageGate,
  evaluateRatehawkTestPrebookGate,
  evaluateRatehawkTestSearchGate,
  resolveRatehawkTestStay,
} from "./ratehawk_test_activation.mjs";
import { postRatehawkTestOnce } from "./ratehawk_test_transport.mjs";
import { fetchRatehawkTestSerp } from "./ratehawk_serp_transport.mjs";
import { handleRatehawkTestSearchRequest } from "./ratehawk_test_search.mjs";
import { handleRatehawkTestHotelpageRequest } from "./ratehawk_test_hotelpage.mjs";
import {
  handleRatehawkHotelsWorkerFetch,
  RATEHAWK_HOTELS_INTERNAL_PROXY,
} from "../fluxidi_ratehawk_hotels_worker.js";
import {
  issueRatehawkViewStayContext,
  verifyRatehawkViewStayContext,
} from "./ratehawk_view_stay_context.mjs";
import { handleRatehawkHotelpageRequest } from "./ratehawk_hotelpage_worker.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const TEST_API_KEY = "rh_test_secret_do_not_leak_xyz";
const TEST_KEY_ID = "18292";
const OFFER_SECRET = "rh_offer_ref_test_secret_not_real";
const CONTEXT_SECRET = "rh_view_stay_context_test_secret_not_real";
const BOOK_HASH = "h-hp-secret-hash-do-not-leak";
const MATCH_HASH = "m-hp-secret-hash-do-not-leak";
const NOW = Date.parse("2026-08-17T07:10:00.000Z");

function hotelsEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: TEST_KEY_ID,
    RATEHAWK_API_KEY: TEST_API_KEY,
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_ENABLED: "0",
    RATEHAWK_HOTELPAGE_ENABLED: "0",
    RATEHAWK_WORKER_SURFACE: "test",
    RATEHAWK_TEST_SEARCH_ENABLED: "1",
    RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    RATEHAWK_OFFER_REF_SECRET: OFFER_SECRET,
    RATEHAWK_VIEW_STAY_CONTEXT_SECRET: CONTEXT_SECRET,
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

function trackingFetch(impl) {
  const state = { calls: 0, urls: [], bodies: [] };
  const fetchImpl = async (url, options) => {
    state.calls += 1;
    state.urls.push(String(url));
    state.bodies.push(options?.body ? JSON.parse(options.body) : null);
    return impl(url, options);
  };
  return { state, fetchImpl };
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

function dump(value) {
  return JSON.stringify(value);
}

function assertRedacted(value) {
  const text = dump(value);
  assert.equal(text.includes(TEST_API_KEY), false);
  assert.equal(text.includes(BOOK_HASH), false);
  assert.equal(text.includes(MATCH_HASH), false);
  assert.equal(text.includes("reconciliation_amount"), false);
  assert.equal(/Basic\s+[A-Za-z0-9+/=_-]{8,}/i.test(text), false);
}

async function issuedTestContext(now = NOW) {
  const stay = resolveRatehawkTestStay(now);
  const issued = await issueRatehawkViewStayContext(CONTEXT_SECRET, stay, { now });
  assert.equal(issued.ok, true);
  return { stay, token: issued.token };
}

test("20. all six RateHawk gates default to 0", () => {
  const wrangler = readFileSync(join(HERE, "../wrangler.toml"), "utf8");
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
    assert.match(wrangler, new RegExp(`${name} = "0"`));
  }
  assert.equal(/RATEHAWK_PRODUCTION_ENABLED\s*=/.test(wrangler), false);
  assert.equal(RATEHAWK_ALLOWED_OPERATIONS.includes("search"), false);
  assert.deepEqual(RATEHAWK_ALLOWED_OPERATIONS, ["overview"]);
});

test("1. search gate off performs zero transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkTestSearchRequest({
    env: hotelsEnv({ RATEHAWK_TEST_SEARCH_ENABLED: "0" }),
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "test_search_disabled");
  assert.equal(dto.view_stay_context, null);
});

test("production worker surface cannot run test search even when gates are on", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkTestSearchRequest({
    env: hotelsEnv({
      RATEHAWK_WORKER_SURFACE: "production",
      RATEHAWK_TEST_SEARCH_ENABLED: "1",
    }),
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.reason, "test_worker_required");
});

test("production gates do not enable test search or test prebook", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkTestSearchRequest({
    env: hotelsEnv({
      RATEHAWK_ENABLED: "1",
      RATEHAWK_HOTELPAGE_ENABLED: "1",
      RATEHAWK_PREBOOK_ENABLED: "1",
      RATEHAWK_TEST_SEARCH_ENABLED: "0",
    }),
    fetchImpl,
    now: NOW,
  });
  assert.equal(
    evaluateRatehawkTestPrebookGate({
      RATEHAWK_PREBOOK_ENABLED: "1",
      RATEHAWK_TEST_PREBOOK_ENABLED: "0",
      RATEHAWK_WORKER_SURFACE: "test",
    }).reason,
    "test_prebook_disabled",
  );
  assert.equal(state.calls, 0);
  assert.equal(dto.reason, "test_search_disabled");
});

test("2. hotelpage test gate off performs zero transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const { token } = await issuedTestContext();
  const dto = await handleRatehawkTestHotelpageRequest({
    env: hotelsEnv({ RATEHAWK_TEST_HOTELPAGE_ENABLED: "0" }),
    body: { view_stay_context: token },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "test_hotelpage_disabled");
});

test("3. wrong environment or host performs zero transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const sandbox = await fetchRatehawkTestSerp({
    env: hotelsEnv({
      RATEHAWK_ENVIRONMENT: "sandbox",
      RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com",
    }),
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(sandbox.invoked, false);
  assert.equal(sandbox.reason, "test_environment_required");
  const host = await fetchRatehawkTestSerp({
    env: hotelsEnv({
      RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com",
    }),
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(host.invoked, false);
  assert.ok(
    host.reason === "test_host_required" ||
      host.reason === "test_environment_required" ||
      assertRatehawkTestProviderConfig(
        hotelsEnv({ RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com" }),
      ).ok === false,
  );
});

test("4. any hid other than 8473727 is denied before transport", async () => {
  assert.equal(assertRatehawkTestHid(1).ok, false);
  assert.equal(assertRatehawkTestHid("8473728").ok, false);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const transport = await postRatehawkTestOnce({
    env: hotelsEnv(),
    operation: RATEHAWK_TEST_OPERATION_SERP,
    path: RATEHAWK_SERP_HOTELS_PATH,
    body: { hids: [1] },
    fetchImpl,
  });
  assert.equal(state.calls, 0);
  assert.equal(transport.invoked, false);
  const search = await handleRatehawkTestSearchRequest({
    env: hotelsEnv(),
    body: { hid: 1 },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(search.reason, "client_control_forbidden");
});

test("5. multiple hids are denied before transport", async () => {
  assert.equal(assertRatehawkTestHids([8473727, 1]).ok, false);
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const transport = await postRatehawkTestOnce({
    env: hotelsEnv(),
    operation: RATEHAWK_TEST_OPERATION_SERP,
    path: RATEHAWK_SERP_HOTELS_PATH,
    body: { hids: [8473727, 8473728] },
    fetchImpl,
  });
  assert.equal(state.calls, 0);
  assert.equal(transport.reason, "test_multiple_hids_forbidden");
});

test("6. region geo dump prebook book and cancel paths are denied", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  for (const path of [
    RATEHAWK_SERP_REGION_PATH,
    RATEHAWK_SERP_GEO_PATH,
    ...RATEHAWK_TEST_DENIED_PATHS,
  ]) {
    const denied = assertRatehawkTestProviderPath(path, RATEHAWK_SERP_HOTELS_PATH);
    assert.equal(denied.ok, false);
    const transport = await postRatehawkTestOnce({
      env: hotelsEnv(),
      operation: RATEHAWK_TEST_OPERATION_SERP,
      path,
      body: { hids: [RATEHAWK_TEST_HID] },
      fetchImpl,
    });
    assert.equal(transport.invoked, false);
  }
  assert.equal(state.calls, 0);
});

test("7. SERP request uses exact hids [8473727]", async () => {
  const request = buildRatehawkTestSerpRequest(NOW);
  assert.deepEqual(request.body.hids, [8473727]);
  assert.equal(request.path, RATEHAWK_SERP_HOTELS_PATH);
  const { state, fetchImpl } = trackingFetch(async () => ({
    status: 200,
    json: async () => etgOk(),
  }));
  await handleRatehawkTestSearchRequest({
    env: hotelsEnv(),
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  assert.equal(state.urls[0], "https://api.ratehawk.com/api/b2b/v3/search/serp/hotels/");
  assert.deepEqual(state.bodies[0].hids, [8473727]);
  assert.equal(state.bodies[0].residency, "be");
  assert.equal(state.bodies[0].language, "en");
  assert.equal(state.bodies[0].guests.length, 1);
  assert.equal(state.bodies[0].guests[0].adults, 2);
  assert.deepEqual(state.bodies[0].guests[0].children, []);
});

test("8. quota denial performs zero provider transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const env = hotelsEnv({
    RATEHAWK_PROVIDER_QUOTA: {
      fetch: async () =>
        new Response(JSON.stringify({ allowed: false, reason: "provider_quota_exhausted" })),
    },
  });
  const search = await handleRatehawkTestSearchRequest({
    env,
    fetchImpl,
    now: NOW,
  });
  const { token } = await issuedTestContext();
  const hotelpage = await handleRatehawkTestHotelpageRequest({
    env,
    body: { view_stay_context: token },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(search.invoked, false);
  assert.equal(search.reason, "provider_quota_exhausted");
  assert.equal(hotelpage.invoked, false);
  assert.equal(hotelpage.reason, "provider_quota_exhausted");
});

test("9. timeout makes one request and does not retry", async () => {
  const { state, fetchImpl } = trackingFetch(async (_url, options) => {
    await new Promise((_, reject) => {
      options.signal.addEventListener("abort", () => {
        const err = new Error("Aborted");
        err.name = "AbortError";
        reject(err);
      });
    });
  });
  const dto = await handleRatehawkTestSearchRequest({
    env: hotelsEnv(),
    fetchImpl,
    now: NOW,
    timeoutMs: 20,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.invoked, true);
  assert.equal(dto.reason, "timeout");
  assert.equal(dto.view_stay_context, null);
});

test("10. successful search returns a safe card DTO", async () => {
  const { fetchImpl } = trackingFetch(async () => ({
    status: 200,
    json: async () => etgOk(),
  }));
  const dto = await handleRatehawkTestSearchRequest({
    env: hotelsEnv(),
    fetchImpl,
    now: NOW,
  });
  assert.equal(dto.ok, true);
  assert.equal(dto.invoked, true);
  assert.equal(dto.source, "ratehawk");
  assert.equal(dto.stay.provider, "ratehawk");
  assert.equal(dto.stay.provider_id, "8473727");
  assert.equal(dto.stay.name, "Warwick Brussels");
  assert.equal(dto.highlights.breakfast_included, true);
  assert.equal(dto.live_rate.customer_total.amount_minor, 18000);
  assert.equal(dto.mobility_independent_of_ratehawk, true);
  assert.equal("internal_settlement" in dto, false);
  assertRedacted(dto);
});

test("11-12. context token is issued only after safe search and binds required fields", async () => {
  const stay = resolveRatehawkTestStay(NOW);
  const { fetchImpl } = trackingFetch(async () => ({
    status: 200,
    json: async () => etgOk(),
  }));
  const dto = await handleRatehawkTestSearchRequest({
    env: hotelsEnv(),
    fetchImpl,
    now: NOW,
  });
  assert.match(dto.view_stay_context, /^rhctx1\./);
  const verified = await verifyRatehawkViewStayContext(
    CONTEXT_SECRET,
    dto.view_stay_context,
    stay,
    { now: NOW },
  );
  assert.equal(verified.ok, true);
  assert.equal(verified.claims.hid, 8473727);
  assert.equal(verified.claims.checkin, stay.checkin);
  assert.equal(verified.claims.checkout, stay.checkout);
  assert.equal(verified.claims.residency, "be");
  assert.equal(verified.claims.currency, "EUR");
  assert.deepEqual(verified.claims.guests, [{ adults: 2, children: [] }]);
  assert.equal(verified.claims.purpose, "view_stay");
  assert.equal(dto.view_stay_context_expires_at, NOW + 15 * 60 * 1000);
});

test("13. tampered or expired context is rejected with zero transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const { token } = await issuedTestContext();
  const tampered = `${token.slice(0, -2)}xx`;
  const bad = await handleRatehawkTestHotelpageRequest({
    env: hotelsEnv(),
    body: { view_stay_context: tampered },
    fetchImpl,
    now: NOW,
  });
  const expired = await issueRatehawkViewStayContext(
    CONTEXT_SECRET,
    resolveRatehawkTestStay(NOW),
    { now: NOW - 16 * 60 * 1000 },
  );
  const stale = await handleRatehawkTestHotelpageRequest({
    env: hotelsEnv(),
    body: { view_stay_context: expired.token },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(bad.reason, "view_stay_context_tampered");
  assert.equal(stale.reason, "view_stay_context_expired");
});

test("14. Hotels independently verifies context before test Hotelpage", async () => {
  const { state, fetchImpl } = trackingFetch(async () => ({
    status: 200,
    json: async () => etgOk(),
  }));
  const { token } = await issuedTestContext();
  const resp = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/test-hotelpage", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: JSON.stringify({ view_stay_context: token }),
    }),
    hotelsEnv(),
    { fetchImpl, now: NOW },
  );
  const dto = await resp.json();
  assert.equal(state.calls, 1);
  assert.equal(dto.invoked, true);
  const denied = await handleRatehawkHotelsWorkerFetch(
    new Request("https://fluxidi-ratehawk-hotels-api.internal/internal/test-hotelpage", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-fluxidi-internal-proxy": RATEHAWK_HOTELS_INTERNAL_PROXY,
      },
      body: JSON.stringify({ view_stay_context: `${token}x` }),
    }),
    hotelsEnv(),
    { fetchImpl, now: NOW },
  );
  const deniedDto = await denied.json();
  assert.equal(state.calls, 1);
  assert.equal(deniedDto.invoked, false);
});

test("15-16. test Hotelpage returns sealed offer refs without hashes", async () => {
  const { state, fetchImpl } = trackingFetch(async (url, options) => {
    assert.equal(String(url), "https://api.ratehawk.com/api/b2b/v3/search/hp/");
    assert.equal(options.method, "POST");
    const posted = JSON.parse(options.body);
    assert.equal(posted.hid, 8473727);
    assert.equal(posted.residency, "be");
    assert.equal(posted.currency, "EUR");
    return { status: 200, json: async () => etgOk() };
  });
  const { token } = await issuedTestContext();
  const dto = await handleRatehawkTestHotelpageRequest({
    env: hotelsEnv(),
    body: { view_stay_context: token },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.ratehawk.state, "ready");
  assert.equal(dto.ratehawk.offers[0].offer_ref.startsWith("rh1."), true);
  assert.equal("book_hash" in dto.ratehawk.offers[0], false);
  assert.equal("match_hash" in dto.ratehawk.offers[0], false);
  assertRedacted(dto);
});

test("public Hotelpage stays on its own gates", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const stay = resolveRatehawkTestStay(NOW);
  const issued = await issueRatehawkViewStayContext(CONTEXT_SECRET, stay, { now: NOW });
  const dto = await handleRatehawkHotelpageRequest({
    env: hotelsEnv({
      RATEHAWK_ENABLED: "0",
      RATEHAWK_HOTELPAGE_ENABLED: "0",
      RATEHAWK_TEST_HOTELPAGE_ENABLED: "1",
    }),
    body: {
      trigger: "view_stay",
      hid: stay.hid,
      checkin: stay.checkin,
      checkout: stay.checkout,
      residency: stay.residency,
      currency: stay.currency,
      guests: stay.guests,
      stay: { provider: "ratehawk", provider_id: "8473727", hid: 8473727 },
      view_stay_context: issued.token,
    },
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.reason, "hotelpage_disabled");
});

test("test dates are server-owned and do not expire as a hardcoded calendar day", () => {
  const first = resolveRatehawkTestStay(NOW);
  const later = resolveRatehawkTestStay(NOW + 10 * 60 * 1000);
  assert.equal(first.checkin, later.checkin);
  assert.equal(first.checkout, later.checkout);
  assert.notEqual(first.checkin, "2026-08-17");
  const far = resolveRatehawkTestStay(Date.parse("2027-03-01T00:00:00.000Z"));
  assert.match(far.checkin, /^\d{4}-\d{2}-\d{2}$/);
  assert.notEqual(far.checkin, first.checkin);
  assert.equal(assertRatehawkTestStay({ ...first, checkin: "2026-09-15" }, NOW).ok, false);
});

test("missing context secret performs zero search transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkTestSearchRequest({
    env: hotelsEnv({ RATEHAWK_VIEW_STAY_CONTEXT_SECRET: "" }),
    fetchImpl,
    now: NOW,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.reason, "view_stay_context_secret_missing");
});
