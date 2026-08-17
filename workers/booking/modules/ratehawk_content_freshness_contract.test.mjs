// RATEHAWK-P1 content completeness and live-price freshness contract
//
// Run:
//   node --test workers/booking/modules/ratehawk_content_freshness_contract.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { EXISTING_HOTEL_PAGE_ACTIONS } from "./ratehawk_affiliate_contract.mjs";
import {
  RATEHAWK_CONTENT_FIELD_REGISTRY,
  RATEHAWK_CUSTOMER_VISIBLE_STAGES,
  RATEHAWK_DISCLOSURE_LABELS,
  RATEHAWK_DISCLOSURE_LOCALES,
  RATEHAWK_LIVE_PRICE_PIPELINE,
  RATEHAWK_PREBOOK_REVALIDATE_DIMENSIONS,
  RATEHAWK_REFRESH_FAILED_PRICE_LABEL,
  RATEHAWK_REQUIRED_CONTENT_CATEGORIES,
  annotateLiveRateFreshness,
  assertLiveRateCachePolicy,
  assertRegistryCoversRequiredCategories,
  assertStaticContentSyncPath,
  collectUnmappedBookingCriticalFields,
  disclosureLabelsFor,
  evaluateRatehawkStayTermChanges,
  existingPageActionsPreserved,
  inspectRatehawkContentCompleteness,
  normalizeStaticHotelPolicies,
  projectCustomerRelevantStayContent,
  resolveLiveRatePresentation,
} from "./ratehawk_content_freshness_contract.mjs";

function staticHotel(overrides = {}) {
  return {
    hid: 8473727,
    name: "RateHawk Demo Hotel",
    address: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
    check_in_time: "15:00:00",
    check_in_time_end: "23:00:00",
    check_out_time: "11:00:00",
    content_revision: "static-v1",
    synced_at: "2026-08-01T00:00:00.000Z",
    amenity_groups: [
      {
        group_name: "Accessibility",
        amenities: ["wheelchair-access", "elevator"],
      },
    ],
    serp_filters: ["has_internet", "wheelchair-access"],
    metapolicy_extra_info: "City tax may be collected at the hotel.",
    policy_struct: [
      { title: "Important", paragraphs: ["Valid ID required at check-in."] },
    ],
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
      cot: [
        {
          amount: 1,
          inclusion: "included",
          price: "0.00",
          currency: "EUR",
          price_unit: "per_stay",
        },
      ],
      extra_bed: [
        {
          amount: 1,
          inclusion: "not_included",
          price: "35.00",
          currency: "EUR",
          price_unit: "per_night",
        },
      ],
      children_meal: [
        {
          meal_type: "breakfast",
          inclusion: "not_included",
          age_start: 2,
          age_end: 12,
          price: "8.00",
          currency: "EUR",
        },
      ],
      meal: [
        {
          meal_type: "breakfast",
          inclusion: "not_included",
          price: "18.00",
          currency: "EUR",
        },
      ],
      internet: [
        {
          internet_type: "wifi",
          inclusion: "included",
          price: "0.00",
          currency: "EUR",
          price_unit: "per_stay",
          work_area: "hotel",
        },
      ],
      parking: [
        {
          territory_type: "on_side",
          inclusion: "not_included",
          price: "20.00",
          currency: "EUR",
          price_unit: "per_car_per_night",
        },
      ],
      deposit: [
        {
          availability: "available",
          currency: "EUR",
          deposit_type: "unspecified",
          payment_type: "unspecified",
          price: "100.00",
          price_unit: "per_room_per_stay",
          pricing_method: "fixed",
        },
      ],
      add_fee: [
        {
          fee_type: "city_tax",
          price: "4.50",
          currency: "EUR",
          price_unit: "per_guest_per_night",
        },
      ],
      check_in_check_out: [
        {
          check_in_check_out_type: "early_checkin",
          inclusion: "not_included",
          price: "30.00",
          currency: "EUR",
        },
      ],
      no_show: {
        availability: "available",
        day_period: "after_midday",
        time: "18:00:00",
      },
      extra_bed: [
        {
          amount: 1,
          inclusion: "not_included",
          price: "35.00",
          currency: "EUR",
          price_unit: "per_night",
        },
      ],
    },
    ...overrides,
  };
}

function liveRate(overrides = {}) {
  return {
    book_hash: "h-mock-content",
    match_hash: "m-mock-content",
    room_name: "Superior Double",
    occupancy: { adults: 2 },
    meal: "breakfast",
    meal_data: { value: "breakfast", has_breakfast: true, no_child_meal: false },
    allotment: 3,
    rg_ext: { class: 3, quality: 2, bedding: 2 },
    deposit: null,
    no_show: null,
    amenities_data: ["non-smoking"],
    payment_options: {
      payment_types: [
        {
          type: "now",
          amount: "180.00",
          show_amount: "180.00",
          currency_code: "EUR",
          show_currency_code: "EUR",
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
            policies: [
              {
                start_at: null,
                end_at: "2026-09-01T10:00:00",
                amount_charge: "0.00",
                amount_show: "0.00",
              },
            ],
          },
        },
      ],
    },
    ...overrides,
  };
}

test("registry covers every required customer-relevant category with stage, source and criticality", () => {
  const coverage = assertRegistryCoversRequiredCategories();
  assert.equal(coverage.ok, true);
  assert.deepEqual(coverage.missing_categories, []);
  assert.equal(RATEHAWK_CONTENT_FIELD_REGISTRY.length > 0, true);
  for (const row of RATEHAWK_CONTENT_FIELD_REGISTRY) {
    assert.equal(row.known, true);
    assert.equal(row.normalized, true);
    assert.ok(RATEHAWK_REQUIRED_CONTENT_CATEGORIES.includes(row.category));
    assert.ok(["static_content", "live_rate"].includes(row.source));
    assert.ok(row.stages.every((stage) => RATEHAWK_CUSTOMER_VISIBLE_STAGES.includes(stage)));
    assert.equal(typeof row.booking_critical, "boolean");
    assert.ok(row.freshness);
  }
});

test("unknown booking-critical fields fail closed and are never silently ignored", () => {
  const live = collectUnmappedBookingCriticalFields(
    liveRate({ guarantee_deposit_policy: { amount: "10.00" } }),
    { source: "live_rate" },
  );
  assert.equal(live.fail_closed, true);
  assert.ok(live.unmapped_critical_field_names.includes("guarantee_deposit_policy"));

  const hotel = staticHotel({
    child_surcharge_policy: { amount: "15.00" },
  });
  const completeness = inspectRatehawkContentCompleteness({
    staticHotel: hotel,
    liveRate: liveRate(),
  });
  assert.equal(completeness.ok, false);
  assert.equal(completeness.blocks_affected_rate, true);
  assert.equal(completeness.silently_ignored, false);
  assert.ok(completeness.unmapped_critical_field_names.includes("child_surcharge_policy"));
});

test("unknown non-critical fields do not block the rate", () => {
  const result = collectUnmappedBookingCriticalFields(
    liveRate({ photographer_credit: "studio" }),
    { source: "live_rate" },
  );
  assert.equal(result.fail_closed, false);
  assert.ok(result.unmapped_field_names.includes("photographer_credit"));
});

test("static policies keep pets, children, cots, meals, accessibility and fees", () => {
  const hotel = staticHotel();
  hotel.metapolicy_struct.extra_bed = [
    {
      amount: 1,
      inclusion: "not_included",
      price: "35.00",
      currency: "EUR",
      price_unit: "per_night",
    },
  ];
  const policies = normalizeStaticHotelPolicies(hotel);
  assert.equal(policies.ok, true);
  assert.equal(policies.discarded, false);
  assert.equal(policies.pets[0].currency, "EUR");
  assert.equal(policies.children[0].age_end, 12);
  assert.equal(policies.cots[0].amount, 1);
  assert.equal(policies.extra_beds[0].amount, 1);
  assert.equal(policies.children_meals[0].meal_type, "breakfast");
  assert.ok(policies.accessibility.includes("wheelchair-access"));
  assert.equal(policies.internet[0].internet_type, "wifi");
  assert.equal(policies.parking[0].territory_type, "on_side");
  assert.equal(policies.hotel_deposits[0].price, "100.00");
  assert.equal(policies.additional_fees[0].fee_type, "city_tax");
  assert.ok(policies.important_hotel_information.includes("City tax"));
  assert.equal(policies.check_in_time, "15:00:00");
  assert.equal(policies.check_out_time, "11:00:00");
});

test("static content may only sync offline or incrementally", () => {
  assert.equal(assertStaticContentSyncPath("offline_sync").ok, true);
  assert.equal(assertStaticContentSyncPath("incremental_sync").ok, true);
  assert.equal(assertStaticContentSyncPath("live_card_render").ok, false);
  assert.equal(assertStaticContentSyncPath("live_search").ok, false);
  assert.equal(assertStaticContentSyncPath("hotelpage").ok, false);
  assert.equal(assertStaticContentSyncPath("prebook").ok, false);
});

test("live pipeline is search, hotelpage refresh, prebook, acceptance, booking", () => {
  assert.deepEqual(RATEHAWK_LIVE_PRICE_PIPELINE, [
    "search",
    "hotelpage_refresh",
    "prebook_revalidation",
    "explicit_acceptance_of_changes",
    "booking",
  ]);
});

test("live rates require retrieved_at and provider hashes; stale rates are not bookable", () => {
  const retrieved = Date.parse("2026-08-17T06:00:00.000Z");
  const missingTime = annotateLiveRateFreshness({
    book_hash: "h-mock-content",
    match_hash: "m-mock-content",
  });
  assert.equal(missingTime.bookable, false);
  assert.equal(missingTime.state, "missing_retrieved_at");

  const missingHash = annotateLiveRateFreshness({
    retrieved_at: retrieved,
    match_hash: "m-mock-content",
  });
  assert.equal(missingHash.bookable, false);
  assert.equal(missingHash.state, "missing_book_hash");

  const fresh = annotateLiveRateFreshness({
    retrieved_at: retrieved,
    book_hash: "h-mock-content",
    match_hash: "m-mock-content",
    stage: "search",
    now: retrieved + 1_000,
  });
  assert.equal(fresh.bookable, true);
  assert.equal(fresh.state, "fresh");

  const stale = annotateLiveRateFreshness({
    retrieved_at: retrieved,
    book_hash: "h-mock-content",
    match_hash: "m-mock-content",
    stage: "search",
    now: retrieved + 120_001,
  });
  assert.equal(stale.bookable, false);
  assert.equal(stale.state, "expired");
  const shown = resolveLiveRatePresentation({ freshness: stale });
  assert.equal(shown.bookable, false);
  assert.equal(shown.stale_shown_as_bookable, false);
  assert.equal(shown.price_label, RATEHAWK_REFRESH_FAILED_PRICE_LABEL);
});

test("refresh failure replaces the price with Beschikbaarheid controleren and keeps Stay22", () => {
  const freshness = annotateLiveRateFreshness({
    retrieved_at: Date.parse("2026-08-17T06:00:00.000Z"),
    book_hash: "h-mock-content",
    match_hash: "m-mock-content",
    refresh_failed: true,
  });
  assert.equal(freshness.state, "refresh_failed");
  const shown = resolveLiveRatePresentation({
    freshness,
    refresh_failed: true,
    offer: { customer_total_label: "EUR 180.00" },
  });
  assert.equal(shown.price_label, "Beschikbaarheid controleren");
  assert.equal(shown.stay22_fallback_retained, true);
  assert.deepEqual(shown.existing_page_actions_preserved, [
    ...EXISTING_HOTEL_PAGE_ACTIONS,
  ]);
});

test("hotelpage and prebook rates are not cacheable", () => {
  assert.equal(assertLiveRateCachePolicy("hotelpage").cacheable, false);
  assert.equal(assertLiveRateCachePolicy("prebook").cacheable, false);
  const search = assertLiveRateCachePolicy("search");
  assert.equal(search.cacheable, true);
  assert.equal(search.distinct_from_static, true);
});

test("prebook term changes show before/after and require explicit acceptance", () => {
  const hotel = staticHotel();
  hotel.metapolicy_struct.extra_bed = [];
  const before = projectCustomerRelevantStayContent({
    staticHotel: hotel,
    liveRate: liveRate(),
    retrieved_at: Date.parse("2026-08-17T06:00:00.000Z"),
  });
  const afterRate = liveRate({
    room_name: "Deluxe King",
    meal: "nomeal",
    meal_data: { value: "nomeal", has_breakfast: false },
    deposit: {
      amount: "50.00",
      currency_code: "USD",
      is_refundable: false,
    },
    no_show: {
      amount: "25.00",
      currency_code: "EUR",
      from_time: "18:00:00",
    },
  });
  afterRate.payment_options.payment_types[0].type = "hotel";
  afterRate.payment_options.payment_types[0].show_amount = "200.00";
  afterRate.payment_options.payment_types[0].amount = "220.00";
  afterRate.payment_options.payment_types[0].currency_code = "USD";
  afterRate.payment_options.payment_types[0].tax_data.taxes.push({
    name: "city_tax",
    included_by_supplier: false,
    amount: "7.50",
    currency_code: "EUR",
  });
  afterRate.payment_options.payment_types[0].cancellation_penalties = {
    free_cancellation_before: null,
    policies: [
      {
        start_at: null,
        end_at: null,
        amount_charge: "220.00",
        amount_show: "200.00",
      },
    ],
  };
  const after = projectCustomerRelevantStayContent({
    staticHotel: hotel,
    liveRate: afterRate,
    retrieved_at: Date.parse("2026-08-17T06:05:00.000Z"),
  });
  const change = evaluateRatehawkStayTermChanges(before.live_offer, after.live_offer);
  assert.equal(change.ok, true);
  assert.equal(change.explicit_acceptance_required, true);
  assert.equal(change.must_redisplay_to_customer, true);
  assert.equal(change.auto_finish_forbidden, true);
  const dimensions = change.changes.map((row) => row.dimension);
  for (const name of RATEHAWK_PREBOOK_REVALIDATE_DIMENSIONS) {
    assert.ok(dimensions.includes(name), name);
    const row = change.changes.find((item) => item.dimension === name);
    assert.notEqual(_stable(row.before), _stable(row.after));
  }
});

test("NL/EN/FR/ES disclosure labels exist for every required category", () => {
  for (const locale of RATEHAWK_DISCLOSURE_LOCALES) {
    const labels = disclosureLabelsFor(locale);
    for (const category of RATEHAWK_REQUIRED_CONTENT_CATEGORIES) {
      assert.equal(typeof labels[category], "string");
      assert.ok(labels[category].length > 0);
    }
    assert.ok(labels.check_availability);
    assert.ok(labels.accept_changed_terms);
  }
  assert.equal(
    RATEHAWK_DISCLOSURE_LABELS.check_availability.nl,
    "Beschikbaarheid controleren",
  );
});

test("existing Saved, Stay22 and mobility actions remain", () => {
  const actions = existingPageActionsPreserved();
  for (const required of [
    "saved",
    "stay22_fallback_availability",
    "nearby_events",
    "taxi_to_this_event",
    "taxi_to_this_stay",
    "airport_transfer",
  ]) {
    assert.ok(actions.includes(required), required);
  }
});

test("projected stay content keeps customer-relevant fields and live currencies separate", () => {
  const hotel = staticHotel();
  hotel.metapolicy_struct.extra_bed = [
    {
      amount: 1,
      inclusion: "not_included",
      price: "35.00",
      currency: "EUR",
      price_unit: "per_night",
    },
  ];
  const rate = liveRate({
    no_show: { amount: "25.00", currency_code: "USD", from_time: "18:00:00" },
  });
  rate.payment_options.payment_types[0].amount = "195.00";
  rate.payment_options.payment_types[0].currency_code = "USD";
  const retrievedAt = Date.parse("2026-08-17T06:00:00.000Z");
  const projected = projectCustomerRelevantStayContent({
    staticHotel: hotel,
    liveRate: rate,
    locale: "nl",
    retrieved_at: retrievedAt,
    now: retrievedAt + 1_000,
  });
  assert.equal(projected.ok, true);
  assert.equal(projected.discarded, false);
  assert.equal(projected.customer_visible.pets.length, 1);
  assert.equal(projected.customer_visible.children_age_ranges[0].age_end, 12);
  assert.equal(projected.customer_visible.cots[0].amount, 1);
  assert.ok(projected.customer_visible.accessibility.includes("wheelchair-access"));
  assert.equal(projected.customer_visible.price.customer_total.currency, "EUR");
  assert.equal(projected.customer_visible.price.reconciliation_amount.currency, "USD");
  assert.equal(projected.customer_visible.no_show.currency, "USD");
  assert.equal(projected.customer_visible.no_show.included_in_room_total, false);
  assert.equal(projected.labels.pets, "Huisdieren");
  assert.equal(projected.presentation.bookable, true);
});

function _stable(value) {
  return JSON.stringify(value ?? null);
}
