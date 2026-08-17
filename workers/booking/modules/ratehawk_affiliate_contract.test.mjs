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
    cancellation_penalties: {
      free_cancellation_before: "2026-09-01T10:00:00",
      policies: [
        {
          start_at: null,
          end_at: "2026-09-01T10:00:00",
          amount_charge: "0.00",
          currency_code: "EUR",
        },
        {
          start_at: "2026-09-01T10:00:00",
          end_at: null,
          amount_charge: "180.00",
          currency_code: "EUR",
        },
      ],
      no_show: { deadline: "2026-09-10T18:00:00", amount_charge: "180.00" },
    },
    ...overrides,
  };
}

function affiliateHotelPayRate() {
  const rate = affiliateNowRate({ book_hash: "h-mock-hotel" });
  rate.payment_options.payment_types[0].type = "hotel";
  rate.payment_options.payment_types[0].is_need_credit_card_data = false;
  rate.payment_options.payment_types[0].is_need_cvc = false;
  return rate;
}

function depositRate() {
  const rate = affiliateNowRate({ book_hash: "h-mock-deposit" });
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
