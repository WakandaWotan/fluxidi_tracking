// RATEHAWK-P1 mocked search DTO for existing hotel cards
//
// Run:
//   node --test workers/booking/modules/ratehawk_hotel_card_search.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { RATEHAWK_GEO_MATCH_MAX_METERS } from "./ratehawk_affiliate_contract.mjs";
import {
  buildExistingHotelCardSearchDto,
  buildExistingHotelSearchPayload,
  mapExistingStayToPublicHotelCard,
} from "./ratehawk_hotel_card_search.mjs";

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

const GOOGLE_PLACES_STAY = Object.freeze({
  id: "places:ChIJdemo",
  provider: "google-places",
  source_id: "ChIJdemo",
  name: "Hotel Metropole",
  type: "hotel",
  address: "Place de Brouckère 31, Brussels",
  city: "Brussel",
  region: "Brussels Hoofdstedelijk Gewest",
  country: "Belgium",
  lat: 50.851,
  lng: 4.352,
  image_url: "https://places.example/photo",
  image_ref: null,
  rating_label: "4.4 (1200)",
  price_hint: null,
  availability_label: null,
  external_url: null,
  provider_label: "Real place discovery",
  photo_attribution: "Google",
  source: "google_places",
  is_real_approved: true,
});

function ratehawkHotel(overrides = {}) {
  return {
    hid: "8473727",
    name: "RateHawk Demo Hotel",
    type: "hotel",
    address: "Rue Duquesnoy 5, 1000 Brussels, Belgium",
    city: "Brussel",
    region: "Brussels Hoofdstedelijk Gewest",
    country: "Belgium",
    lat: 50.845,
    lng: 4.3543,
    image_url: "https://img.example/licensed.jpg",
    image_ref: "ratehawk_static:8473727:hero",
    star_rating: 4,
    content_source: "offline_sync",
    ...overrides,
  };
}

function affiliateNowRate(overrides = {}) {
  return {
    book_hash: "h-search-now",
    match_hash: "m-search-now",
    room_name: "Superior Double",
    meal: "breakfast",
    meal_data: { value: "breakfast", has_breakfast: true },
    allotment: 2,
    occupancy: { adults: 2 },
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
        },
      ],
    },
    cancellation_penalties: {
      free_cancellation_before: "2026-09-01T10:00:00",
      policies: [],
    },
    ...overrides,
  };
}

function latOffsetMeters(lat, meters) {
  return lat + (meters / 6371000) * (180 / Math.PI);
}

test("existing non-RateHawk cards remain byte/contract compatible", () => {
  const approved = mapExistingStayToPublicHotelCard(APPROVED_WARWICK);
  const approvedAgain = mapExistingStayToPublicHotelCard(APPROVED_WARWICK);
  assert.equal(JSON.stringify(approved), JSON.stringify(approvedAgain));
  assert.equal(approved.id, "approved-warwick-brussels");
  assert.equal(approved.provider, "approved-local");
  assert.equal(approved.price_label, "Vanaf €145");
  assert.equal(approved.source, "approved_local");

  const payload = buildExistingHotelSearchPayload({
    source: "approved-local",
    existingStays: [APPROVED_WARWICK, GOOGLE_PLACES_STAY],
  });
  assert.equal(payload.ok, true);
  assert.equal(payload.source, "approved-local");
  assert.equal(payload.stays.length, 2);
  assert.equal(
    JSON.stringify(payload.stays[0]),
    JSON.stringify(mapExistingStayToPublicHotelCard(APPROVED_WARWICK)),
  );

  const places = buildExistingHotelCardSearchDto({
    source: "google-places",
    existingStay: GOOGLE_PLACES_STAY,
  });
  assert.equal(places.ok, true);
  assert.equal(places.stay.provider, "google-places");
  assert.equal(places.ratehawk_matched, false);
  assert.equal(places.stay.price_label, null);
  assert.deepEqual(Object.keys(places.stay), Object.keys(approved));
});

test("valid hid-backed card uses Fluxidi stay id and hid as provider_id", () => {
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    existingStay: APPROVED_WARWICK,
    ratehawkHotel: ratehawkHotel(),
    catalogHid: "8473727",
    fluxidiStayId: "approved-warwick-brussels",
    stay22FallbackUrl: APPROVED_WARWICK.external_url,
    liveRate: null,
  });
  assert.equal(row.ok, true);
  assert.equal(row.ratehawk_matched, true);
  assert.equal(row.match.method, "hid");
  assert.equal(row.stay.id, "approved-warwick-brussels");
  assert.equal(row.stay.provider_id, "8473727");
  assert.equal(row.stay.provider, "ratehawk");
  assert.equal(row.stay.address.includes("Duquesnoy"), true);
  assert.equal(row.stay.lat, 50.845);
  assert.equal(row.stay.lng, 4.3543);
  assert.equal(row.stay.image_ref, "ratehawk_static:8473727:hero");
  assert.equal(row.stay.external_url.includes("stay22"), true);
  assert.ok(row.existing_page_actions_preserved.includes("saved"));
  assert.ok(row.existing_page_actions_preserved.includes("view_stay"));
  assert.ok(row.existing_page_actions_preserved.includes("taxi_to_this_stay"));
  assert.ok(row.existing_page_actions_preserved.includes("airport_transfer"));
  assert.ok(row.existing_page_actions_preserved.includes("nearby_events"));
});

test("ratehawk:{hid} is used only when no Fluxidi stay id exists", () => {
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    ratehawkHotel: ratehawkHotel(),
    catalogHid: "8473727",
    liveRate: null,
  });
  assert.equal(row.stay.id, "ratehawk:8473727");
  assert.equal(row.stay.provider_id, "8473727");
});

test("unmatched card retains Stay22 and mobility actions without RateHawk price", () => {
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    existingStay: APPROVED_WARWICK,
    ratehawkHotel: ratehawkHotel({
      hid: "999",
      address: "Other Street 1",
      lat: 51.2,
      lng: 3.2,
      name: "Unrelated",
    }),
    catalogHid: "111",
    stay22FallbackUrl: APPROVED_WARWICK.external_url,
    liveRate: affiliateNowRate(),
  });
  assert.equal(row.ok, true);
  assert.equal(row.ratehawk_matched, false);
  assert.equal(row.stay.id, "approved-warwick-brussels");
  assert.equal(row.stay.price_label, null);
  assert.equal(row.stay.availability_label, null);
  assert.equal(row.stay.external_url.includes("stay22"), true);
  assert.equal(row.stay.lat, 50.845);
  assert.ok(row.existing_page_actions_preserved.includes("taxi_to_this_stay"));
  assert.ok(row.existing_page_actions_preserved.includes("stay22_fallback_availability"));
});

test("live-rate-null shows no price or availability", () => {
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    ratehawkHotel: ratehawkHotel(),
    catalogHid: "8473727",
    liveRate: null,
    stay22FallbackUrl: APPROVED_WARWICK.external_url,
  });
  assert.equal(row.has_live_ratehawk_availability, false);
  assert.equal(row.stay.price_label, null);
  assert.equal(row.stay.availability_label, null);
});

test("validated live rate shows the RateHawk customer amount and currency", () => {
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    ratehawkHotel: ratehawkHotel(),
    catalogHid: "8473727",
    liveRate: affiliateNowRate(),
    stay22FallbackUrl: APPROVED_WARWICK.external_url,
  });
  assert.equal(row.ok, true);
  assert.equal(row.has_live_ratehawk_availability, true);
  assert.equal(row.stay.price_label, "EUR 180.00");
  assert.equal(row.stay.price_label.includes("189"), false);
  assert.equal(row.stay.price_label.includes("5%"), false);
});

test("deposit is hard-rejected and emits no card", () => {
  const deposit = affiliateNowRate();
  deposit.payment_options.payment_types[0].type = "deposit";
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    ratehawkHotel: ratehawkHotel(),
    catalogHid: "8473727",
    liveRate: deposit,
  });
  assert.equal(row.ok, false);
  assert.equal(row.hard_stop, true);
  assert.equal(row.reason, "deposit_requires_fluxidi_to_fund_etg");
  assert.equal(row.stay, null);
});

test("critical unknown fields fail closed", () => {
  const dirty = affiliateNowRate({ extra_cancellation_cash_penalty: "40.00" });
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    ratehawkHotel: ratehawkHotel(),
    catalogHid: "8473727",
    liveRate: dirty,
  });
  assert.equal(row.ok, false);
  assert.equal(row.hard_stop, true);
  assert.equal(row.reason, "unmapped_critical_field");
});

test("affiliate remuneration stays internal and does not leak into customer price", () => {
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    ratehawkHotel: ratehawkHotel(),
    catalogHid: "8473727",
    liveRate: affiliateNowRate(),
    providerSettlement: {
      affiliate_remuneration_percent: 5,
      amount_minor: 900,
      currency: "EUR",
    },
  });
  assert.equal(row.stay.price_label, "EUR 180.00");
  assert.equal(row.internal_settlement.customer_facing, false);
  assert.equal(row.internal_settlement.source, "provider_settlement");
  assert.equal(row.internal_settlement.affiliate_remuneration_percent, 5);
  assert.equal(row.internal_settlement.amount_minor, 900);
  const dumpedStay = JSON.stringify(row.stay);
  assert.equal(dumpedStay.includes("affiliate"), false);
  assert.equal(dumpedStay.includes("remuneration"), false);
  assert.equal(dumpedStay.includes("900"), false);
});

test("name-only matching is rejected", () => {
  const row = buildExistingHotelCardSearchDto({
    source: "ratehawk",
    search_contract_enabled: true,
    existingStay: {
      ...APPROVED_WARWICK,
      address: "Completely Different 9",
      lat: 51.0,
      lng: 3.0,
    },
    ratehawkHotel: ratehawkHotel({
      hid: "555",
      name: "Warwick Brussels",
      address: "Somewhere Else 2",
      lat: 49.0,
      lng: 6.0,
    }),
    catalogHid: "111",
    stay22FallbackUrl: APPROVED_WARWICK.external_url,
  });
  assert.equal(row.ratehawk_matched, false);
  assert.equal(row.match.method, "name_only_rejected");
  assert.equal(row.stay.price_label, null);
});

test("75-metre address/coordinate fallback boundaries", () => {
  assert.equal(RATEHAWK_GEO_MATCH_MAX_METERS, 75);
  const base = {
    source: "ratehawk",
    search_contract_enabled: true,
    existingStay: APPROVED_WARWICK,
    stay22FallbackUrl: APPROVED_WARWICK.external_url,
    liveRate: null,
  };

  const inside = buildExistingHotelCardSearchDto({
    ...base,
    ratehawkHotel: ratehawkHotel({
      hid: "no-hid-match",
      lat: latOffsetMeters(APPROVED_WARWICK.lat, 74),
      lng: APPROVED_WARWICK.lng,
    }),
    catalogHid: "other",
  });
  assert.equal(inside.ratehawk_matched, true);
  assert.equal(inside.match.method, "address_geo");
  assert.ok(inside.match.distance_meters <= RATEHAWK_GEO_MATCH_MAX_METERS);

  const outside = buildExistingHotelCardSearchDto({
    ...base,
    ratehawkHotel: ratehawkHotel({
      hid: "no-hid-match",
      lat: latOffsetMeters(APPROVED_WARWICK.lat, 76),
      lng: APPROVED_WARWICK.lng,
    }),
    catalogHid: "other",
  });
  assert.equal(outside.ratehawk_matched, false);
  assert.equal(outside.stay.external_url.includes("stay22"), true);
});

test("gated source=ratehawk does not emit cards while the search contract is off", () => {
  const payload = buildExistingHotelSearchPayload({
    source: "ratehawk",
    search_contract_enabled: false,
    ratehawkItems: [
      {
        ratehawkHotel: ratehawkHotel(),
        catalogHid: "8473727",
        liveRate: affiliateNowRate(),
      },
    ],
  });
  assert.equal(payload.ok, true);
  assert.equal(payload.count, 0);
  assert.deepEqual(payload.stays, []);
  assert.ok(payload.warnings.includes("ratehawk_invocation_blocked"));
});
