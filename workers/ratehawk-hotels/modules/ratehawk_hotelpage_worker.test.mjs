// RATEHAWK-P1 live hotelpage Worker integration
//
// Run:
//   node --test workers/ratehawk-hotels/modules/ratehawk_hotelpage_worker.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildExistingHotelCardSearchDto,
  buildExistingHotelSearchPayload,
  mapExistingStayToPublicHotelCard,
} from "./ratehawk_hotel_card_search.mjs";
import {
  RATEHAWK_HOTELPAGE_PATH as CONTRACT_HOTELPAGE_PATH,
  RATEHAWK_HOTELPAGE_TTL_MS,
  RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
} from "./ratehawk_hotelpage_contract.mjs";
import {
  RATEHAWK_HOTELPAGE_PUBLIC_PATH,
  handleRatehawkHotelpageRequest,
  isRatehawkBackedStay,
  openRatehawkOfferReference,
} from "./ratehawk_hotelpage_worker.mjs";
import {
  RATEHAWK_HOTELPAGE_PATH,
  buildRatehawkPublicSearchGuardPayload,
  isRatehawkHotelpageInvocationAllowed,
  isRatehawkOperationAllowed,
  redactRatehawkSecrets,
} from "./ratehawk_provider.mjs";
import { createRatehawkQuotaBinding } from "./ratehawk_provider_quota.mjs";

const TEST_API_KEY = "rh_test_secret_do_not_leak_xyz";
const TEST_KEY_ID = "18292";
const BOOK_HASH = "h-hp-secret-hash-do-not-leak";
const MATCH_HASH = "m-hp-secret-hash-do-not-leak";
const RETRIEVED_AT = Date.parse("2026-08-17T07:00:00.000Z");

const APPROVED_WARWICK = Object.freeze({
  id: "approved-warwick-brussels",
  provider: "approved-local",
  source_id: "approved-warwick-brussels",
  name: "Warwick Brussels",
  type: "hotel",
  address: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
  city: "Brussel",
  region: "Brussels Hoofdstedelijk Gewest",
  country: "Belgium",
  lat: 50.845,
  lng: 4.3543,
  image_url: null,
  image_ref: "approved_asset:assets/fluxidi/customer_home_business_banner.webp",
  rating: 4.3,
  price_hint: "Vanaf €145",
  availability_label: null,
  external_url: "https://www.stay22.com/embed/gm?aid=fluxidi",
  provider_label: null,
  photo_attribution: null,
  source: "approved_local",
  is_real_approved: true,
});

function validEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: TEST_KEY_ID,
    RATEHAWK_API_KEY: TEST_API_KEY,
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_ENABLED: "1",
    RATEHAWK_HOTELPAGE_ENABLED: "1",
    RATEHAWK_OFFER_REF_SECRET: "rh_offer_ref_test_secret_not_real",
    RATEHAWK_PROVIDER_QUOTA: createRatehawkQuotaBinding(),
    ...overrides,
  };
}

function ratehawkStay() {
  return {
    id: "approved-warwick-brussels",
    provider: "ratehawk",
    provider_id: "8473727",
    hid: 8473727,
    name: "Warwick Brussels",
    address: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
    city: "Brussel",
    image_url: "https://img.example/demo.jpg",
  };
}

function validBody(overrides = {}) {
  return {
    trigger: "view_stay",
    hid: 8473727,
    selected_card_hid: 8473727,
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    residency: "be",
    language: "en",
    currency: "EUR",
    guests: [{ adults: 2, children: [] }],
    locale: "nl",
    stay: ratehawkStay(),
    search_context: {
      hid: 8473727,
      checkin: "2026-09-15",
      checkout: "2026-09-16",
      residency: "be",
      language: "en",
      currency: "EUR",
      guests: [{ adults: 2, children: [] }],
    },
    ...overrides,
  };
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

function etgOk(rates = [hotelpageRate()]) {
  return {
    status: "ok",
    data: {
      hotels: [{ hid: 8473727, rates }],
    },
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

function dump(value) {
  return JSON.stringify(value);
}

function assertNoSecretsOrHashes(value) {
  const text = dump(value);
  assert.equal(text.includes(TEST_API_KEY), false);
  assert.equal(text.includes(BOOK_HASH), false);
  assert.equal(text.includes(MATCH_HASH), false);
  assert.equal(/Basic\s+[A-Za-z0-9+/=_-]{8,}/i.test(text), false);
  assert.equal(text.includes("reconciliation_amount"), false);
  assert.equal(text.includes("fluxidi_affiliate_remuneration"), false);
  assert.equal(text.includes("commission_info"), false);
  assert.equal(text.includes("\"commission\""), false);
  assert.equal(text.includes("book_hash"), false);
  assert.equal(text.includes("match_hash"), false);
}

function assertExistingActions(dto) {
  assert.equal(dto.stay22_fallback_retained, true);
  assert.equal(dto.mobility_independent_of_ratehawk, true);
  assert.equal(dto.saved_retained, true);
  assert.equal(dto.nearby_events_retained, true);
  assert.ok(dto.existing_actions.includes("stay22_fallback_availability"));
  assert.ok(dto.existing_actions.includes("taxi_to_this_stay"));
  assert.ok(dto.existing_actions.includes("airport_transfer"));
  assert.equal(dto.commercial.customer_pays_fluxidi, false);
  assert.equal(dto.commercial.mollie_involved, false);
}

test("1. feature gate disabled performs zero transport", async () => {
  const cases = [
    validEnv({ RATEHAWK_HOTELPAGE_ENABLED: "0" }),
    validEnv({ RATEHAWK_ENABLED: "0" }),
    validEnv({ RATEHAWK_HOTELPAGE_ENABLED: "0", RATEHAWK_ENABLED: "0" }),
  ];
  for (const env of cases) {
    const { state, fetchImpl } = trackingFetch(async () => {
      throw new Error("must_not_call_ratehawk");
    });
    assert.equal(isRatehawkHotelpageInvocationAllowed(env), false);
    const dto = await handleRatehawkHotelpageRequest({
      env,
      body: validBody(),
      fetchImpl,
      now: RETRIEVED_AT,
    });
    assert.equal(state.calls, 0, dump(env));
    assert.equal(dto.invoked, false);
    assert.equal(dto.ratehawk.offers.length, 0);
    assert.equal(dto.reason, "hotelpage_disabled");
    assertExistingActions(dto);
    assertNoSecretsOrHashes(dto);
  }
});

test("2. invalid or missing hid performs zero transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const env = validEnv();
  const cases = [
    validBody({ hid: null, selected_card_hid: null, stay: { ...ratehawkStay(), provider_id: null, hid: null } }),
    validBody({ hid: "Warwick Brussels" }),
    validBody({ hid: [8473727, 1], stay: ratehawkStay() }),
    validBody({ hids: [8473727, 999], hid: undefined }),
  ];
  for (const body of cases) {
    const before = state.calls;
    const dto = await handleRatehawkHotelpageRequest({
      env,
      body,
      fetchImpl,
      now: RETRIEVED_AT,
    });
    assert.equal(state.calls, before);
    assert.equal(dto.invoked, false);
    assert.equal(dto.ratehawk.offers.length, 0);
    assertExistingActions(dto);
    assertNoSecretsOrHashes(dto);
  }
});

test("3. incomplete dates, guests or context perform zero transport", async () => {
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const env = validEnv();
  const cases = [
    validBody({ checkin: null }),
    validBody({ checkout: null }),
    validBody({ guests: null }),
    validBody({ residency: null }),
    validBody({ language: null }),
    validBody({ currency: null }),
    validBody({
      search_context: {
        hid: 8473727,
        checkin: "2026-09-20",
        checkout: "2026-09-16",
        residency: "be",
        language: "en",
        currency: "EUR",
        guests: [{ adults: 2, children: [] }],
      },
    }),
  ];
  for (const body of cases) {
    const before = state.calls;
    const dto = await handleRatehawkHotelpageRequest({
      env,
      body,
      fetchImpl,
      now: RETRIEVED_AT,
    });
    assert.equal(state.calls, before, dto.reason);
    assert.equal(dto.invoked, false);
    assert.equal(dto.ratehawk.offers.length, 0);
    assertExistingActions(dto);
    assertNoSecretsOrHashes(dto);
  }
});

test("4. exactly one selected hotel reaches hotelpage transport", async () => {
  const env = validEnv();
  const { state, fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 1);
  assert.equal(state.methods[0], "POST");
  assert.equal(state.urls[0], `https://api.ratehawk.com${RATEHAWK_HOTELPAGE_PATH}`);
  assert.equal(RATEHAWK_HOTELPAGE_PATH, CONTRACT_HOTELPAGE_PATH);
  assert.equal(state.bodies[0].hid, 8473727);
  assert.equal(state.bodies[0].checkin, "2026-09-15");
  assert.equal(dto.invoked, true);
  assert.equal(dto.ratehawk.state, "ready");
  assert.equal(dto.ratehawk.offers.length, 1);
  assert.equal(RATEHAWK_HOTELPAGE_PUBLIC_PATH, "/public/hotels/ratehawk/hotelpage");
});

test("5. mocked successful hotelpage response normalizes correctly", async () => {
  const env = validEnv();
  const { fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(dto.ok, true);
  assert.equal(dto.page, "HotelStayDetailPage");
  assert.equal(dto.rendered, false);
  assert.equal(dto.ratehawk.state, "ready");
  assert.equal(dto.ratehawk.hid, 8473727);
  const offer = dto.ratehawk.offers[0];
  assert.equal(offer.room_name, "Superior Double");
  assert.equal(offer.customer_total.currency, "EUR");
  assert.equal(offer.customer_total.amount_minor, 18000);
  assert.equal(offer.bookable, true);
  assert.equal(typeof offer.offer_ref, "string");
  assert.equal(offer.offer_ref.startsWith("rh1."), true);
  const opened = await openRatehawkOfferReference(env, offer.offer_ref, {
    now: RETRIEVED_AT,
    hid: 8473727,
  });
  assert.equal(opened.ok, true);
  assert.equal(opened.claims.book_hash, BOOK_HASH);
  assert.equal(opened.claims.match_hash, MATCH_HASH);
  assert.equal(opened.claims.expires_at - opened.claims.retrieved_at, RATEHAWK_HOTELPAGE_TTL_MS);
  assert.equal(opened.claims.expires_at - RETRIEVED_AT <= RATEHAWK_HOTELPAGE_TTL_MS, true);
  assertNoSecretsOrHashes(dto);
});

test("6. all customer-critical fields survive", async () => {
  const env = validEnv();
  const { fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  const offer = dto.ratehawk.offers[0];
  assert.equal(offer.room_name, "Superior Double");
  assert.equal(offer.room_description, "City view");
  assert.deepEqual(offer.occupancy, { adults: 2 });
  assert.deepEqual(offer.beds, { class: 3, quality: 2, bedding: 2 });
  assert.equal(offer.meal_plan, "breakfast");
  assert.equal(offer.breakfast_included, true);
  assert.equal(offer.customer_total_label, "EUR 180.00");
  assert.equal(offer.included_taxes.length, 1);
  assert.equal(offer.excluded_taxes.length, 1);
  assert.equal(offer.vat.included, true);
  assert.equal(offer.payment.type, "hotel");
  assert.equal(offer.payment.recipient, "hotel");
  assert.equal(offer.payment.timing, "at_hotel");
  assert.equal(offer.card_data_required, true);
  assert.equal(offer.cvc_required, true);
  assert.equal(offer.deposit.disclosed, true);
  assert.equal(offer.deposit.amount.amount_minor, 5000);
  assert.equal(offer.deposit.currency, "EUR");
  assert.equal(offer.refundable, true);
  assert.equal(offer.free_cancellation_before, "2026-09-01T10:00:00");
  assert.equal(offer.no_show.disclosed, true);
  assert.equal(offer.no_show.currency, "USD");
  assert.equal(offer.no_show.converted, false);
  assert.equal(offer.remaining_availability, 2);
  assert.equal(offer.retrieved_at, RETRIEVED_AT);
  assert.equal(offer.expires_at, RETRIEVED_AT + RATEHAWK_HOTELPAGE_TTL_MS);
  assert.equal(dto.ratehawk.retryable, false);
});

test("7. timeout returns retryable state", async () => {
  const env = validEnv();
  let calls = 0;
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    now: RETRIEVED_AT,
    timeoutMs: 25,
    fetchImpl: (_url, options) =>
      new Promise((_resolve, reject) => {
        calls += 1;
        const signal = options?.signal;
        if (!signal) {
          reject(new Error("missing_abort_signal"));
          return;
        }
        signal.addEventListener("abort", () => {
          const err = new Error("Aborted");
          err.name = "AbortError";
          reject(err);
        });
      }),
  });
  assert.equal(calls, 1);
  assert.equal(dto.invoked, true);
  assert.equal(dto.ratehawk.state, "retryable");
  assert.equal(dto.ratehawk.retryable, true);
  assert.equal(dto.ratehawk.offers.length, 0);
  assert.equal(dto.ratehawk.price_label, RATEHAWK_REFRESH_FAILED_PRICE_LABEL);
  assert.equal(dto.reason, "timeout");
  assertExistingActions(dto);
  assertNoSecretsOrHashes(dto);
});

test("8. provider error is safely redacted", async () => {
  const env = validEnv();
  const { state, fetchImpl } = trackingFetch(async () =>
    jsonResponse({
      status: "error",
      error: "incorrect_credentials",
      data: {
        book_hash: BOOK_HASH,
        match_hash: MATCH_HASH,
        api_key: TEST_API_KEY,
      },
      debug: { Authorization: `Basic ${TEST_API_KEY}` },
    }),
  );
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.invoked, true);
  assert.equal(dto.ratehawk.retryable, true);
  assert.equal(dto.ratehawk.offers.length, 0);
  assert.equal(dto.reason, "incorrect_credentials");
  assertExistingActions(dto);
  assertNoSecretsOrHashes(dto);
  assertNoSecretsOrHashes(redactRatehawkSecrets(dto, env));
});

test("9. no automatic retry occurs", async () => {
  const env = validEnv();
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error(`provider exploded ${TEST_API_KEY} ${BOOK_HASH}`);
  });
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.invoked, true);
  assert.equal(dto.ratehawk.retryable, true);
  assertNoSecretsOrHashes(dto);
});

test("10. payment type deposit fails closed", async () => {
  const env = validEnv();
  const { state, fetchImpl } = trackingFetch(async () =>
    jsonResponse(
      etgOk([
        hotelpageRate({
          payment_options: {
            payment_types: [
              {
                type: "deposit",
                amount: "20.00",
                show_amount: "20.00",
                currency_code: "EUR",
                show_currency_code: "EUR",
              },
            ],
          },
        }),
      ]),
    ),
  );
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 1);
  assert.equal(dto.invoked, true);
  assert.equal(dto.ratehawk.offers.length, 0);
  assert.equal(dto.ratehawk.state, "unavailable");
  assert.equal(dto.reason, "deposit_requires_fluxidi_to_fund_etg");
  assert.notEqual(dto.ratehawk.price_label, "EUR 20.00");
  assertExistingActions(dto);
  assertNoSecretsOrHashes(dto);
});

test("11. reconciliation, commission and settlement never reach the client DTO", async () => {
  const env = validEnv();
  const { fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  const text = dump(dto);
  assert.equal(text.includes("reconciliation_amount"), false);
  assert.equal(text.includes("fluxidi_affiliate_remuneration_percent"), false);
  assert.equal(text.includes("commission"), false);
  assert.equal(text.includes("charge_amount"), false);
  assert.equal(dto.commercial.fluxidi_role, "affiliate");
  assert.equal(dto.commercial.customer_pays_fluxidi, false);
  assert.equal(dto.commercial.mollie_involved, false);
  const offer = dto.ratehawk.offers[0];
  assert.equal("reconciliation_amount" in offer, false);
  assert.equal(offer.cancellation.penalties.every((row) => !("charge_amount" in row)), true);
});

test("12. credentials and hashes do not appear in logs or errors", async () => {
  const env = validEnv();
  const dirty = {
    Authorization: `Basic ${TEST_API_KEY}`,
    book_hash: BOOK_HASH,
    match_hash: MATCH_HASH,
    nested: { RATEHAWK_API_KEY: TEST_API_KEY },
  };
  const redacted = redactRatehawkSecrets(dirty, env);
  assert.equal(redacted.Authorization, "[redacted]");
  assert.equal(redacted.book_hash, "[redacted]");
  assert.equal(redacted.match_hash, "[redacted]");
  assert.equal(dump(redacted).includes(TEST_API_KEY), false);
  assert.equal(dump(redacted).includes(BOOK_HASH), false);

  const { fetchImpl } = trackingFetch(async () => jsonResponse(etgOk()));
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody(),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assertNoSecretsOrHashes(dto);
  assert.equal(dump(dto).includes(TEST_KEY_ID), false);
});

test("13. card, list and page-open paths cannot invoke hotelpage", async () => {
  const env = validEnv();
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  for (const trigger of [
    "list_card",
    "card_render",
    "hotels_page_open",
    "serp_list",
    "nearby_events",
    "saved",
  ]) {
    const dto = await handleRatehawkHotelpageRequest({
      env,
      body: validBody({ trigger }),
      fetchImpl,
      now: RETRIEVED_AT,
    });
    assert.equal(dto.invoked, false, trigger);
    assert.equal(dto.ratehawk.offers.length, 0, trigger);
    assert.equal(dto.reason, "hotelpage_forbidden_for_list_or_card", trigger);
    assertExistingActions(dto);
  }
  assert.equal(state.calls, 0);
  assert.equal(isRatehawkOperationAllowed(env, "hotelpage"), false);

  const guard = buildRatehawkPublicSearchGuardPayload({ env });
  assert.equal(guard.count, 0);
  assert.deepEqual(guard.stays, []);
  assert.equal(guard.ratehawk.connected, false);
});

test("14. existing non-RateHawk and Stay22 hotel behaviour remains unchanged", async () => {
  const env = validEnv();
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody({
      stay: APPROVED_WARWICK,
      hid: 8473727,
    }),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "stay_not_ratehawk_backed");
  assert.equal(isRatehawkBackedStay(APPROVED_WARWICK, 8473727), false);
  assertExistingActions(dto);

  const approved = mapExistingStayToPublicHotelCard(APPROVED_WARWICK);
  assert.equal(approved.provider, "approved-local");
  assert.equal(approved.price_hint || approved.price_label, "Vanaf €145");
  const payload = buildExistingHotelSearchPayload({
    source: "approved-local",
    existingStays: [APPROVED_WARWICK],
  });
  assert.equal(payload.ok, true);
  assert.equal(payload.stays.length, 1);
  const gated = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: false,
  });
  assert.equal(gated.stay, null);
  assert.equal(gated.gated, true);
});

test("15. client provider control is rejected with zero transport", async () => {
  const env = validEnv();
  const { state, fetchImpl } = trackingFetch(async () => {
    throw new Error("must_not_call_ratehawk");
  });
  const dto = await handleRatehawkHotelpageRequest({
    env,
    body: validBody({
      host: "https://evil.example",
      api_key: "stolen",
    }),
    fetchImpl,
    now: RETRIEVED_AT,
  });
  assert.equal(state.calls, 0);
  assert.equal(dto.invoked, false);
  assert.equal(dto.reason, "client_control_forbidden");
  assertExistingActions(dto);
});
