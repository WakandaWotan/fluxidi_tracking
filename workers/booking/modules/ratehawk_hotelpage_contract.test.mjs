// RATEHAWK-P1 mocked hotelpage contract for existing View stay
//
// Run:
//   node --test workers/booking/modules/ratehawk_hotelpage_contract.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { EXISTING_HOTEL_PAGE_ACTIONS } from "./ratehawk_affiliate_contract.mjs";
import {
  RATEHAWK_DISCLOSURE_LOCALES,
  RATEHAWK_REQUIRED_CONTENT_CATEGORIES,
} from "./ratehawk_content_freshness_contract.mjs";
import {
  EXISTING_HOTEL_DETAIL_ACTIONS,
  RATEHAWK_HOTELPAGE_PATH,
  RATEHAWK_HOTELPAGE_TTL_MS,
  RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
  buildHotelStayDetailAdapter,
  buildProposedTestHotelpageRequest,
  buildRatehawkHotelpageRequest,
  existingDetailActionsPreserved,
  normalizeRatehawkHotelpageResponse,
  shouldRequestRatehawkHotelpage,
} from "./ratehawk_hotelpage_contract.mjs";

const RETRIEVED_AT = Date.parse("2026-08-17T06:50:00.000Z");

function validRequest(overrides = {}) {
  return {
    hid: 8473727,
    selectedCardHid: 8473727,
    checkin: "2026-09-15",
    checkout: "2026-09-16",
    residency: "be",
    language: "en",
    currency: "EUR",
    guests: [{ adults: 2, children: [] }],
    trigger: "view_stay",
    searchContext: {
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

function staticHotel() {
  return {
    hid: 8473727,
    name: "RateHawk Demo Hotel",
    check_in_time: "15:00:00",
    check_out_time: "11:00:00",
    content_revision: "static-v1",
    amenity_groups: [
      { group_name: "Accessibility", amenities: ["wheelchair-access"] },
    ],
    serp_filters: ["wheelchair-access"],
    metapolicy_extra_info: "City tax may be collected at the hotel.",
    metapolicy_struct: {
      pets: [
        {
          pets_type: "lt_5kg",
          inclusion: "not_included",
          price: "25.00",
          currency: "EUR",
          price_unit: "per_stay",
        },
      ],
      children: [
        {
          extra_bed: "available",
          age_start: 0,
          age_end: 12,
          price: "0.00",
          currency: "EUR",
        },
      ],
      cot: [],
      extra_bed: [],
      children_meal: [],
      meal: [],
      internet: [],
      parking: [],
      deposit: [],
      add_fee: [],
      check_in_check_out: [],
      no_show: { availability: "unspecified", day_period: "unspecified", time: "" },
    },
  };
}

function hotelpageRate(overrides = {}) {
  return {
    book_hash: "h-hp-mock",
    match_hash: "m-hp-mock",
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
          is_need_credit_card_data: false,
          is_need_cvc: false,
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

function fluxidiStay() {
  return {
    id: "approved-warwick-brussels",
    provider: "ratehawk",
    provider_id: "8473727",
    name: "Warwick Brussels",
    address: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
    city: "Brussel",
    image_url: "https://img.example/demo.jpg",
  };
}

test("valid hid-backed hotelpage request is built and not executed", () => {
  const request = buildRatehawkHotelpageRequest(validRequest());
  assert.equal(request.ok, true);
  assert.equal(request.executed, false);
  assert.equal(request.method, "POST");
  assert.equal(request.path, RATEHAWK_HOTELPAGE_PATH);
  assert.equal(request.body.hid, 8473727);
  assert.equal(request.body.checkin, "2026-09-15");
  assert.equal(request.body.currency, "EUR");
  assert.equal(request.cacheable, false);
  assert.equal(request.must_prebook_before_confirmation, true);
  assert.equal(request.match_hash_not_bookable_proof, true);
});

test("missing or invalid hid is rejected; name identification is forbidden", () => {
  assert.equal(buildRatehawkHotelpageRequest(validRequest({ hid: null })).reason, "hid_required");
  assert.equal(
    buildRatehawkHotelpageRequest(validRequest({ hid: "Warwick Brussels" })).reason,
    "hotel_name_identification_forbidden",
  );
  assert.equal(
    buildRatehawkHotelpageRequest(
      validRequest({ hotelName: "Warwick Brussels", hid: 8473727 }),
    ).reason,
    "hotel_name_identification_forbidden",
  );
  assert.equal(buildRatehawkHotelpageRequest(validRequest({ hid: 0 })).reason, "hid_invalid");
});

test("hotelpage is never requested for list or card rendering", () => {
  assert.equal(shouldRequestRatehawkHotelpage("list_card").allowed, false);
  assert.equal(shouldRequestRatehawkHotelpage("card_render").allowed, false);
  assert.equal(shouldRequestRatehawkHotelpage("hotels_page_open").allowed, false);
  assert.equal(shouldRequestRatehawkHotelpage("serp_list").allowed, false);
  assert.equal(
    buildRatehawkHotelpageRequest(validRequest({ trigger: "list_card" })).reason,
    "hotelpage_forbidden_for_list_or_card",
  );
  assert.equal(shouldRequestRatehawkHotelpage("view_stay").allowed, true);
});

test("room and rate normalization reuses the committed real-shape contract", () => {
  const rate = hotelpageRate();
  rate.payment_options.payment_types[0].amount = "195.00";
  rate.payment_options.payment_types[0].currency_code = "USD";
  rate.payment_options.payment_types[0].cancellation_penalties.policies[1].amount_charge =
    "195.00";
  rate.deposit = {
    amount: "50.00",
    currency_code: "USD",
    is_refundable: true,
  };
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: 8473727,
    retrieved_at: RETRIEVED_AT,
    now: RETRIEVED_AT + 1_000,
    staticHotel: staticHotel(),
    hotels: [{ hid: 8473727, rates: [rate] }],
  });
  assert.equal(page.ok, true);
  assert.equal(page.hid, 8473727);
  assert.equal(page.offers.length, 1);
  const offer = page.offers[0];
  assert.equal(offer.room_name, "Superior Double");
  assert.equal(offer.breakfast_included, true);
  assert.equal(offer.remaining_availability, 2);
  assert.equal(offer.customer_total.currency, "EUR");
  assert.equal(offer.reconciliation_amount.currency, "USD");
  assert.equal(offer.included_taxes[0].name, "vat");
  assert.equal(offer.excluded_taxes[0].name, "city_tax");
  assert.equal(offer.payment.payment_type, "hotel");
  assert.equal(offer.payment.payment_recipient, "hotel");
  assert.equal(offer.card_data_required, false);
  assert.equal(offer.deposit.disclosed, true);
  assert.equal(offer.no_show.currency, "USD");
  assert.equal(offer.no_show.from_time, "18:00:00");
  assert.equal(offer.refundable, true);
  assert.equal(offer.cancellation_penalties.length, 2);
  assert.equal(offer.hashes_opaque, true);
  assert.equal(offer.freshness.match_hash_not_bookable_proof, true);
  assert.equal(offer.must_prebook_before_confirmation, true);
});

test("pets and children policies remain sourced from offline content", () => {
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: 8473727,
    retrieved_at: RETRIEVED_AT,
    now: RETRIEVED_AT + 1_000,
    staticHotel: staticHotel(),
    hotels: [{ hid: 8473727, rates: [hotelpageRate()] }],
  });
  assert.equal(page.static_policies.content_source, "offline_incremental_sync");
  assert.equal(page.static_policies.pets[0].currency, "EUR");
  assert.equal(page.static_policies.children[0].age_end, 12);
});

test("rate-level deposit and no-show are preserved", () => {
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: 8473727,
    retrieved_at: RETRIEVED_AT,
    now: RETRIEVED_AT + 1_000,
    hotels: [{ hid: 8473727, rates: [hotelpageRate()] }],
  });
  const offer = page.offers[0];
  assert.equal(offer.deposit.refundable, true);
  assert.equal(offer.deposit.amount.amount_minor, 5000);
  assert.equal(offer.no_show.disclosed, true);
  assert.equal(offer.no_show.included_in_room_total, false);
  assert.equal(offer.no_show.converted, false);
});

test("nested cancellation and separate currencies are preserved", () => {
  const rate = hotelpageRate();
  rate.payment_options.payment_types[0].show_amount = "180.00";
  rate.payment_options.payment_types[0].show_currency_code = "EUR";
  rate.payment_options.payment_types[0].amount = "195.00";
  rate.payment_options.payment_types[0].currency_code = "USD";
  rate.deposit.currency_code = "USD";
  rate.payment_options.payment_types[0].cancellation_penalties.policies[1] = {
    start_at: "2026-09-01T10:00:00",
    end_at: null,
    amount_charge: "195.00",
    amount_show: "180.00",
  };
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: 8473727,
    retrieved_at: RETRIEVED_AT,
    now: RETRIEVED_AT + 1_000,
    hotels: [{ hid: 8473727, rates: [rate] }],
  });
  const offer = page.offers[0];
  assert.equal(offer.customer_total.currency, "EUR");
  assert.equal(offer.reconciliation_amount.currency, "USD");
  assert.equal(offer.cancellation_penalties[1].show_amount.currency, "EUR");
  assert.equal(offer.cancellation_penalties[1].charge_amount.currency, "USD");
});

test("payment type deposit remains rejected", () => {
  const rate = hotelpageRate();
  rate.payment_options.payment_types[0].type = "deposit";
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: 8473727,
    retrieved_at: RETRIEVED_AT,
    now: RETRIEVED_AT + 1_000,
    hotels: [{ hid: 8473727, rates: [rate] }],
  });
  assert.equal(page.ok, false);
  assert.equal(page.rejected[0].reason, "deposit_requires_fluxidi_to_fund_etg");
});

test("expired hotelpage rate is not bookable", () => {
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: 8473727,
    retrieved_at: RETRIEVED_AT,
    now: RETRIEVED_AT + RATEHAWK_HOTELPAGE_TTL_MS + 1,
    hotels: [{ hid: 8473727, rates: [hotelpageRate()] }],
  });
  assert.equal(page.offers[0].freshness.bookable, false);
  assert.equal(page.offers[0].freshness.state, "expired");
  assert.equal(page.stale, true);
  assert.equal(
    page.offers[0].presentation.price_label,
    RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
  );
});

test("unknown booking-critical field fails closed", () => {
  const page = normalizeRatehawkHotelpageResponse({
    requestedHid: 8473727,
    retrieved_at: RETRIEVED_AT,
    now: RETRIEVED_AT + 1_000,
    hotels: [
      {
        hid: 8473727,
        rates: [hotelpageRate({ guarantee_deposit_policy: { amount: "10.00" } })],
      },
    ],
  });
  assert.equal(page.ok, false);
  assert.ok(page.unmapped_critical_field_names.includes("guarantee_deposit_policy"));
});

test("existing mobility and Stay22 detail actions remain without RateHawk rates", () => {
  const adapter = buildHotelStayDetailAdapter({
    stay: fluxidiStay(),
    staticHotel: staticHotel(),
    hotelpage: null,
    state: "unavailable",
    locale: "nl",
  });
  assert.equal(adapter.rendered, false);
  assert.equal(adapter.page, "HotelStayDetailPage");
  assert.equal(adapter.mobility_independent_of_ratehawk, true);
  assert.equal(adapter.stay22_fallback_retained, true);
  assert.deepEqual(adapter.existing_actions, [...EXISTING_HOTEL_DETAIL_ACTIONS]);
  for (const action of [
    "saved",
    "nearby_events",
    "taxi_to_this_event",
    "taxi_to_this_stay",
    "airport_transfer",
    "stay22_fallback_availability",
  ]) {
    assert.ok(adapter.existing_actions.includes(action), action);
  }
  assert.ok(EXISTING_HOTEL_PAGE_ACTIONS.includes("view_stay"));
  assert.equal(adapter.ratehawk.offers.length, 0);
  assert.equal(adapter.ratehawk.unavailable, true);
});

test("NL/EN/FR/ES disclosure contract remains on the detail adapter", () => {
  for (const locale of RATEHAWK_DISCLOSURE_LOCALES) {
    const adapter = buildHotelStayDetailAdapter({
      stay: fluxidiStay(),
      staticHotel: staticHotel(),
      state: "unavailable",
      locale,
    });
    for (const category of RATEHAWK_REQUIRED_CONTENT_CATEGORIES) {
      assert.equal(typeof adapter.labels[category], "string");
    }
  }
  assert.deepEqual(existingDetailActionsPreserved(), [
    ...EXISTING_HOTEL_DETAIL_ACTIONS,
  ]);
});

test("proposed later test-hotelpage request is hid-backed and not executed", () => {
  const proposed = buildProposedTestHotelpageRequest();
  assert.equal(proposed.ok, true);
  assert.equal(proposed.executed, false);
  assert.equal(proposed.body.hid, 8473727);
  assert.equal(proposed.body.checkin, "2026-09-15");
  assert.equal(proposed.body.checkout, "2026-09-16");
  assert.equal(proposed.body.residency, "be");
  assert.equal(proposed.body.language, "en");
  assert.equal(proposed.body.currency, "EUR");
  assert.deepEqual(proposed.body.guests, [{ adults: 2, children: [] }]);
  assert.equal(proposed.body.timeout, 30);
});
