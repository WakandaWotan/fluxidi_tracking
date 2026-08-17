// RATEHAWK-P1 mocked affiliate contract — existing hotel page mapping
//
// Run:
//   node --test workers/booking/modules/ratehawk_affiliate_contract.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  EXISTING_HOTEL_PAGE_ACTIONS,
  RATEHAWK_AFFILIATE_REMUNERATION_PERCENT,
  assertAffiliatePaymentSafe,
  assertOfflineContentNotUsedDuringLiveRender,
  buildRatehawkAcceptanceSnapshot,
  classifyRatehawkPaymentType,
  collectUnmappedFields,
  evaluateRatehawkPrebookChange,
  mapRatehawkHotelToExistingStayCard,
  moneyFromRatehawkAmount,
  normalizeRatehawkRateDeposit,
  normalizeRatehawkRateNoShow,
  normalizeRatehawkRateOffer,
  resolveRatehawkHotelMatch,
} from "./ratehawk_affiliate_contract.mjs";

function affiliateNowRate(overrides = {}) {
  return {
    book_hash: "h-mock-now",
    match_hash: "m-mock-now",
    room_name: "Superior Double",
    room_description: "City view, 1 king bed",
    meal: "breakfast",
    meal_data: { value: "breakfast", has_breakfast: true },
    allotment: 3,
    rg_ext: { class: 3, quality: 2, sex: 0, bathroom: 1, bedding: 2 },
    payment_options: {
      payment_types: [
        {
          type: "now",
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
        },
      ],
    },
    deposit: null,
    no_show: null,
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
    ...overrides,
  };
}

function affiliateHotelPayRate(overrides = {}) {
  const rate = affiliateNowRate({ book_hash: "h-mock-hotel", ...overrides });
  rate.payment_options.payment_types[0].type = "hotel";
  rate.payment_options.payment_types[0].is_need_credit_card_data = false;
  rate.payment_options.payment_types[0].is_need_cvc = false;
  return rate;
}

function depositRate(overrides = {}) {
  const rate = affiliateNowRate({ book_hash: "h-mock-deposit", ...overrides });
  rate.payment_options.payment_types[0].type = "deposit";
  return rate;
}

const brusselsHotel = {
  hid: "8473727",
  name: "RateHawk Demo Hotel",
  type: "hotel",
  address: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
  city: "Brussel",
  region: "Brussels Hoofdstedelijk Gewest",
  country: "Belgium",
  lat: 50.845,
  lng: 4.3543,
  image_url: "https://img.example/demo.jpg",
  star_rating: 4,
  content_source: "offline_sync",
};

test("affiliate now and hotel payment types are allowed; Fluxidi never collects", () => {
  const now = classifyRatehawkPaymentType("now");
  assert.equal(now.allowed, true);
  assert.equal(now.hard_stop, false);
  assert.equal(now.fluxidi_collects_customer_funds, false);
  assert.equal(now.payment_recipient, "ratehawk_etg");
  assert.equal(now.payment_timing, "at_booking");

  const hotel = classifyRatehawkPaymentType("hotel");
  assert.equal(hotel.allowed, true);
  assert.equal(hotel.payment_recipient, "hotel");
  assert.equal(hotel.payment_timing, "at_hotel");
  assert.equal(hotel.fluxidi_collects_customer_funds, false);
});

test("deposit and unknown payment types hard-stop", () => {
  const deposit = assertAffiliatePaymentSafe("deposit");
  assert.equal(deposit.hard_stop, true);
  assert.equal(deposit.reason, "deposit_requires_fluxidi_to_fund_etg");

  const unknown = assertAffiliatePaymentSafe("wallet");
  assert.equal(unknown.hard_stop, true);
  assert.equal(unknown.reason, "unsupported_payment_type");
});

test("money conversion requires explicit currency and uses minor units", () => {
  const ok = moneyFromRatehawkAmount("180.00", "EUR");
  assert.equal(ok.ok, true);
  assert.equal(ok.amount_minor, 18000);
  assert.equal(ok.currency, "EUR");

  const noCurrency = moneyFromRatehawkAmount("180.00", "");
  assert.equal(noCurrency.ok, false);
  assert.equal(noCurrency.reason, "currency_required");
});

test("hid match is authoritative; name-only match is rejected", () => {
  const hid = resolveRatehawkHotelMatch({
    ratehawkHid: "8473727",
    catalogHid: "8473727",
    ratehawkName: "Other Name",
    catalogName: "Warwick Brussels",
  });
  assert.equal(hid.matched, true);
  assert.equal(hid.method, "hid");

  const nameOnly = resolveRatehawkHotelMatch({
    ratehawkName: "Warwick Brussels",
    catalogName: "Warwick Brussels",
  });
  assert.equal(nameOnly.matched, false);
  assert.equal(nameOnly.method, "name_only_rejected");
  assert.equal(nameOnly.stay22_only, true);
});

test("address plus coordinates can prove a match without hid equality", () => {
  const geo = resolveRatehawkHotelMatch({
    ratehawkAddress: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
    catalogAddress: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
    ratehawkLat: 50.845,
    ratehawkLng: 4.3543,
    catalogLat: 50.84505,
    catalogLng: 4.35435,
  });
  assert.equal(geo.matched, true);
  assert.equal(geo.method, "address_geo");
});

test("unmatched hotels stay Stay22-only with no RateHawk availability claim", () => {
  const miss = resolveRatehawkHotelMatch({
    ratehawkHid: "999",
    catalogHid: "111",
    ratehawkAddress: "Other street 1",
    catalogAddress: "Rue Duquesnoy 5",
    ratehawkLat: 51.0,
    ratehawkLng: 4.0,
    catalogLat: 50.845,
    catalogLng: 4.3543,
  });
  assert.equal(miss.matched, false);
  assert.equal(miss.stay22_only, true);
});

test("live card maps onto existing HotelStay/public-card fields without replacing page actions", () => {
  const mapped = mapRatehawkHotelToExistingStayCard({
    hotel: brusselsHotel,
    liveRate: affiliateNowRate(),
    stay22FallbackUrl: "https://www.stay22.com/embed/gm?aid=fluxidi",
    fluxidiStayId: "approved-warwick-brussels",
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.stay.id, "approved-warwick-brussels");
  assert.equal(mapped.stay.provider, "ratehawk");
  assert.equal(mapped.stay.provider_id, "8473727");
  assert.equal(mapped.stay.price_label, "EUR 180.00");
  assert.equal(mapped.has_live_ratehawk_availability, true);
  assert.equal(mapped.stay22_fallback, true);
  assert.equal(mapped.stay.external_url.includes("stay22"), true);
  assert.deepEqual(mapped.existing_page_actions_preserved, [
    ...EXISTING_HOTEL_PAGE_ACTIONS,
  ]);
});

test("without a current RateHawk rate, card has no availability/price claim", () => {
  const mapped = mapRatehawkHotelToExistingStayCard({
    hotel: brusselsHotel,
    stay22FallbackUrl: "https://www.stay22.com/embed/gm?aid=fluxidi",
  });
  assert.equal(mapped.ok, true);
  assert.equal(mapped.stay.price_label, null);
  assert.equal(mapped.stay.availability_label, null);
  assert.equal(mapped.has_live_ratehawk_availability, false);
});

test("normalize now-rate keeps taxes, cancellation, meal and rejects Fluxidi rails", () => {
  const offer = normalizeRatehawkRateOffer(affiliateNowRate());
  assert.equal(offer.ok, true);
  assert.equal(offer.customer_total.amount_minor, 18000);
  assert.equal(offer.customer_total.currency, "EUR");
  assert.equal(offer.excluded_taxes.length, 1);
  assert.equal(offer.excluded_taxes[0].name, "city_tax");
  assert.equal(offer.breakfast_included, true);
  assert.equal(offer.refundable, true);
  assert.equal(offer.fluxidi_adds_booking_fee, false);
  assert.equal(offer.fluxidi_is_merchant_of_record, false);
  assert.equal(offer.fluxidi_affiliate_remuneration_percent, 5);
  assert.ok(offer.payment_rail_forbidden.includes("mollie"));
  assert.equal(RATEHAWK_AFFILIATE_REMUNERATION_PERCENT, 5);
});

test("hotel pay-at-hotel rate is allowed; deposit rate is rejected", () => {
  const hotel = normalizeRatehawkRateOffer(affiliateHotelPayRate());
  assert.equal(hotel.ok, true);
  assert.equal(hotel.payment.payment_type, "hotel");

  const deposit = normalizeRatehawkRateOffer(depositRate());
  assert.equal(deposit.ok, false);
  assert.equal(deposit.hard_stop, true);
  assert.equal(deposit.reason, "deposit_requires_fluxidi_to_fund_etg");
});

test("unknown critical provider fields fail closed and are named, not dropped", () => {
  const raw = affiliateNowRate({ guarantee_deposit_policy: { amount: "10" } });
  const unmapped = collectUnmappedFields(raw);
  assert.equal(unmapped.fail_closed, true);
  assert.ok(unmapped.unmapped_critical_field_names.includes("guarantee_deposit_policy"));

  const offer = normalizeRatehawkRateOffer(raw);
  assert.equal(offer.ok, false);
  assert.equal(offer.reason, "unmapped_critical_field");
});

test("prebook price change must be redisplayed; auto finish is forbidden", () => {
  const before = normalizeRatehawkRateOffer(affiliateNowRate());
  const afterRaw = affiliateNowRate();
  afterRaw.payment_options.payment_types[0].show_amount = "195.00";
  afterRaw.payment_options.payment_types[0].amount = "195.00";
  const after = normalizeRatehawkRateOffer(afterRaw);
  const change = evaluateRatehawkPrebookChange(before, after);
  assert.equal(change.ok, true);
  assert.equal(change.price_changed, true);
  assert.equal(change.must_redisplay_to_customer, true);
  assert.equal(change.auto_finish_forbidden, true);
  assert.equal(change.new_total.amount_minor, 19500);
});

test("acceptance snapshot is privacy-minimized and has no card/secrets", () => {
  const offer = normalizeRatehawkRateOffer(affiliateNowRate());
  const snapshot = buildRatehawkAcceptanceSnapshot({
    hid: "8473727",
    bookHash: offer.book_hash,
    roomName: offer.room_name,
    offer,
    locale: "nl",
    providerBookingReference: "RH-TEST-1",
    termsRevision: "content-v1",
    acceptedAt: "2026-08-17T06:00:00.000Z",
  });
  assert.equal(snapshot.ok, true);
  const dumped = JSON.stringify(snapshot);
  assert.equal(dumped.includes("cvc"), true); // omitted list names the exclusion
  assert.equal(snapshot.omitted.includes("card_data"), true);
  assert.equal(snapshot.omitted.includes("cvc"), true);
  assert.equal(snapshot.omitted.includes("api_credentials"), true);
  assert.equal(snapshot.payment.recipient, "ratehawk_etg");
  assert.equal(snapshot.customer_total.amount_minor, 18000);
  assert.equal("guest_email" in snapshot, false);
  assert.equal("raw_provider_payload" in snapshot, false);
});

test("static content fetch is forbidden during live card render", () => {
  const live = assertOfflineContentNotUsedDuringLiveRender("live_card_render");
  assert.equal(live.ok, false);
  const sync = assertOfflineContentNotUsedDuringLiveRender("offline_sync");
  assert.equal(sync.ok, true);
});

function hotelDeposit(overrides = {}) {
  return {
    amount: "50.00",
    currency_code: "EUR",
    is_refundable: true,
    ...overrides,
  };
}

function officialNoShow(overrides = {}) {
  return {
    amount: "25.00",
    currency_code: "EUR",
    from_time: "18:00:00",
    ...overrides,
  };
}

function nestedCancellation({
  freeCancellationBefore = "2026-09-01T10:00:00",
  chargeAmount = "180.00",
  showAmount = "180.00",
} = {}) {
  return {
    free_cancellation_before: freeCancellationBefore,
    policies: [
      {
        start_at: null,
        end_at: freeCancellationBefore,
        amount_charge: freeCancellationBefore ? "0.00" : chargeAmount,
        amount_show: freeCancellationBefore ? "0.00" : showAmount,
      },
      ...(freeCancellationBefore
        ? [
            {
              start_at: freeCancellationBefore,
              end_at: null,
              amount_charge: chargeAmount,
              amount_show: showAmount,
            },
          ]
        : []),
    ],
  };
}

function sanitizedSerpRateShape(index) {
  const paymentType = index % 2 === 0 ? "hotel" : "now";
  const mixedCurrency = index % 5 === 0;
  const showCurrency = "EUR";
  const chargeCurrency = mixedCurrency ? "USD" : "EUR";
  const showAmount = (100 + index).toFixed(2);
  const chargeAmount = mixedCurrency ? (110 + index).toFixed(2) : showAmount;
  const depositMode = index % 3;
  const noShowMode = index % 4;
  const freeCancel = index % 3 === 1 ? "2026-09-01T10:00:00" : null;

  let deposit = null;
  if (paymentType === "hotel" && depositMode !== 0) {
    deposit = {
      amount: "50.00",
      currency_code: chargeCurrency,
      is_refundable: depositMode === 1,
    };
  }

  const noShow =
    noShowMode === 0
      ? null
      : {
          amount: "25.00",
          currency_code: chargeCurrency,
          from_time: "18:00:00",
        };

  return {
    book_hash: `h-sanitized-${String(index + 1).padStart(2, "0")}`,
    match_hash: `m-sanitized-${String(index + 1).padStart(2, "0")}`,
    daily_prices: [showAmount],
    meal: "nomeal",
    meal_data: {
      value: "nomeal",
      has_breakfast: false,
      no_child_meal: true,
    },
    room_name: "Sanitized Double",
    room_name_info: { original_rate_name: "Sanitized Double" },
    room_data_trans: {
      main_room_type: "Double",
      main_name: "Double",
      bathroom: null,
      bedding_type: "double",
      misc_room_type: null,
    },
    rg_ext: { class: 3, quality: 2, sex: 0, bathroom: 1, bedding: 2 },
    serp_filters: ["has_bathroom"],
    allotment: 2,
    amenities_data: ["non-smoking"],
    any_residency: true,
    is_package: false,
    sell_price_limits: null,
    legal_info: {
      provider: { name: "", address: "" },
      hotel: { name: "Test Hotel", address: "Test Street" },
    },
    deposit,
    no_show: noShow,
    payment_options: {
      payment_types: [
        {
          type: paymentType,
          amount: chargeAmount,
          show_amount: showAmount,
          currency_code: chargeCurrency,
          show_currency_code: showCurrency,
          is_need_credit_card_data: paymentType === "now",
          is_need_cvc: paymentType === "now",
          tax_data: {
            taxes: [
              {
                name: "vat",
                included_by_supplier: true,
                amount: "10.00",
                currency_code: chargeCurrency,
              },
            ],
          },
          cancellation_penalties: nestedCancellation({
            freeCancellationBefore: freeCancel,
            chargeAmount,
            showAmount,
          }),
        },
      ],
    },
  };
}

test("rate-level deposit null means no hotel deposit disclosed", () => {
  const direct = normalizeRatehawkRateDeposit(null);
  assert.equal(direct.ok, true);
  assert.equal(direct.disclosed, false);
  assert.equal(direct.customer_disclosure_required, false);

  const offer = normalizeRatehawkRateOffer(affiliateNowRate({ deposit: null }));
  assert.equal(offer.ok, true);
  assert.equal(offer.deposit.disclosed, false);
  assert.equal(offer.reason, undefined);
});

test("valid refundable hotel deposit is displayed, not rejected for its key name", () => {
  const rate = affiliateHotelPayRate();
  rate.deposit = hotelDeposit({ is_refundable: true });
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, true);
  assert.equal(offer.payment.payment_type, "hotel");
  assert.equal(offer.deposit.disclosed, true);
  assert.equal(offer.deposit.refundable, true);
  assert.equal(offer.deposit.amount.amount_minor, 5000);
  assert.equal(offer.deposit.currency, "EUR");
  assert.equal(offer.deposit.payment_recipient, "hotel");
  assert.equal(offer.deposit.payment_timing, "at_hotel");
  assert.equal(offer.deposit.customer_disclosure_required, true);
});

test("valid non-refundable hotel deposit is displayed", () => {
  const rate = affiliateHotelPayRate();
  rate.deposit = hotelDeposit({ is_refundable: false, amount: "75.00" });
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, true);
  assert.equal(offer.deposit.disclosed, true);
  assert.equal(offer.deposit.refundable, false);
  assert.equal(offer.deposit.amount.amount_minor, 7500);
});

test("malformed rate-level deposit fails closed", () => {
  const missing = normalizeRatehawkRateOffer(
    affiliateHotelPayRate({ deposit: { amount: "50.00", currency_code: "EUR" } }),
  );
  assert.equal(missing.ok, false);
  assert.equal(missing.hard_stop, true);
  assert.equal(missing.reason, "deposit_incomplete");

  const unknown = normalizeRatehawkRateOffer(
    affiliateHotelPayRate({
      deposit: { ...hotelDeposit(), prepaid_by: "guest" },
    }),
  );
  assert.equal(unknown.ok, false);
  assert.equal(unknown.reason, "deposit_unknown_field");

  const notObject = normalizeRatehawkRateOffer(
    affiliateHotelPayRate({ deposit: "50.00" }),
  );
  assert.equal(notObject.ok, false);
  assert.equal(notObject.reason, "deposit_malformed");
});

test("rate-level no_show null means no separate no-show data", () => {
  const direct = normalizeRatehawkRateNoShow(null);
  assert.equal(direct.ok, true);
  assert.equal(direct.disclosed, false);
  assert.equal(direct.customer_disclosure_required, false);

  const offer = normalizeRatehawkRateOffer(affiliateNowRate({ no_show: null }));
  assert.equal(offer.ok, true);
  assert.equal(offer.no_show.disclosed, false);
});

test("valid no-show amount, currency and hotel-local from_time are disclosed", () => {
  const offer = normalizeRatehawkRateOffer(
    affiliateNowRate({ no_show: officialNoShow() }),
  );
  assert.equal(offer.ok, true);
  assert.equal(offer.no_show.disclosed, true);
  assert.equal(offer.no_show.amount.amount_minor, 2500);
  assert.equal(offer.no_show.currency, "EUR");
  assert.equal(offer.no_show.from_time, "18:00:00");
  assert.equal(offer.no_show.timezone_context, "hotel_local_time");
  assert.equal(offer.no_show.customer_disclosure_required, true);
});

test("malformed rate-level no_show fails closed", () => {
  const missing = normalizeRatehawkRateOffer(
    affiliateNowRate({ no_show: { amount: "25.00", currency_code: "EUR" } }),
  );
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, "no_show_incomplete");

  const badTime = normalizeRatehawkRateOffer(
    affiliateNowRate({ no_show: officialNoShow({ from_time: "8pm" }) }),
  );
  assert.equal(badTime.ok, false);
  assert.equal(badTime.reason, "no_show_from_time_unmapped");

  const unknown = normalizeRatehawkRateOffer(
    affiliateNowRate({
      no_show: officialNoShow({ deadline: "2026-09-10T18:00:00" }),
    }),
  );
  assert.equal(unknown.ok, false);
  assert.equal(unknown.reason, "no_show_unknown_field");
});

test("cancellation terms normalize from selected payment_types, not rate top level", () => {
  const rate = affiliateNowRate();
  delete rate.cancellation_penalties;
  rate.payment_options.payment_types[0].cancellation_penalties =
    nestedCancellation({
      freeCancellationBefore: "2026-09-02T12:00:00",
    });
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, true);
  assert.equal(offer.cancellation_source, "payment_type");
  assert.equal(offer.refundable, true);
  assert.equal(offer.free_cancellation_before, "2026-09-02T12:00:00");
  assert.equal(offer.cancellation_penalties.length, 2);
  assert.equal(offer.no_show.disclosed, false);
});

test("absent or null free_cancellation_before is never invented as free cancellation", () => {
  const absent = affiliateNowRate();
  delete absent.cancellation_penalties;
  const absentOffer = normalizeRatehawkRateOffer(absent);
  assert.equal(absentOffer.ok, true);
  assert.equal(absentOffer.refundable, false);
  assert.equal(absentOffer.free_cancellation_before, null);

  const explicitNull = affiliateNowRate();
  explicitNull.cancellation_penalties = {
    free_cancellation_before: null,
    policies: [
      {
        start_at: null,
        end_at: null,
        amount_charge: "180.00",
        amount_show: "180.00",
      },
    ],
  };
  const nullOffer = normalizeRatehawkRateOffer(explicitNull);
  assert.equal(nullOffer.ok, true);
  assert.equal(nullOffer.refundable, false);
  assert.equal(nullOffer.free_cancellation_before, null);
});

test("payment type deposit remains rejected even when rate-level deposit is valid", () => {
  const rate = depositRate();
  rate.deposit = hotelDeposit();
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, false);
  assert.equal(offer.hard_stop, true);
  assert.equal(offer.reason, "deposit_requires_fluxidi_to_fund_etg");
});

test("rate-level deposit with payment type hotel is accepted", () => {
  const rate = affiliateHotelPayRate();
  rate.deposit = hotelDeposit({ is_refundable: true });
  rate.no_show = officialNoShow();
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, true);
  assert.equal(offer.payment.payment_type, "hotel");
  assert.equal(offer.deposit.disclosed, true);
  assert.equal(offer.no_show.disclosed, true);
});

test("customer-facing show currency stays separate from charge currency", () => {
  const rate = affiliateNowRate();
  rate.payment_options.payment_types[0].show_amount = "180.00";
  rate.payment_options.payment_types[0].show_currency_code = "EUR";
  rate.payment_options.payment_types[0].amount = "195.00";
  rate.payment_options.payment_types[0].currency_code = "USD";
  rate.cancellation_penalties.policies = [
    {
      start_at: null,
      end_at: "2026-09-01T10:00:00",
      amount_charge: "0.00",
      amount_show: "0.00",
    },
    {
      start_at: "2026-09-01T10:00:00",
      end_at: null,
      amount_charge: "195.00",
      amount_show: "180.00",
    },
  ];
  const offer = normalizeRatehawkRateOffer(rate);
  assert.equal(offer.ok, true);
  assert.equal(offer.customer_total.currency, "EUR");
  assert.equal(offer.customer_total.amount_minor, 18000);
  assert.equal(offer.reconciliation_amount.currency, "USD");
  assert.equal(offer.reconciliation_amount.amount_minor, 19500);
  assert.notEqual(
    offer.customer_total.currency,
    offer.reconciliation_amount.currency,
  );
  assert.equal(offer.cancellation_penalties[1].show_amount.currency, "EUR");
  assert.equal(offer.cancellation_penalties[1].charge_amount.currency, "USD");
});

test("all 25 sanitized SERP rate shapes pass when known fields are valid", () => {
  const shapes = Array.from({ length: 25 }, (_, index) =>
    sanitizedSerpRateShape(index),
  );
  assert.equal(shapes.length, 25);
  const paymentTypes = new Set();
  for (const [index, shape] of shapes.entries()) {
    const offer = normalizeRatehawkRateOffer(shape);
    assert.equal(offer.ok, true, `shape ${index + 1} ${offer.reason || ""}`);
    assert.equal(offer.hard_stop, false);
    assert.ok(["hotel", "now"].includes(offer.payment.payment_type));
    assert.notEqual(offer.payment.payment_type, "deposit");
    assert.equal(offer.customer_total.currency, "EUR");
    assert.ok(["EUR", "USD"].includes(offer.reconciliation_amount.currency));
    if (offer.customer_total.currency !== offer.reconciliation_amount.currency) {
      assert.equal(offer.reconciliation_amount.currency, "USD");
    }
    paymentTypes.add(offer.payment.payment_type);
  }
  assert.deepEqual([...paymentTypes].sort(), ["hotel", "now"]);
});
