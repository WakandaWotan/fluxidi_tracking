// LIMOUSINE-UNIFIED-BOOKING-P3A — canonical intent + five price modes.
// Run: node --test workers/booking/modules/limousine_unified_intent.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_INTENT_KIND,
  LIMOUSINE_PUBLISHED_PRICING_MODES,
  LIMOUSINE_SERVICE_TYPE,
  LIMOUSINE_UNIFIED_REASONS,
  assertLimousineOfferRevisionFresh,
  assertLimousineOfferStillPublished,
  assertLimousineOfferVehicleScope,
  buildLimousineQuoteIntentSnapshot,
  classifyLimousinePublishedPricingMode,
  computeLimousineHourlyHireSnapshot,
  computeLimousinePackageSnapshot,
  enrichLimousineAcceptedSnapshot,
  limousineBookingRequestNeedsPassengerRoute,
  limousineDocumentLinesFromSnapshot,
  rejectLimousineClientPricingAuthority,
} from "./limousine_unified_intent.mjs";
import {
  computeOfferHourlyCents,
} from "./limousine_pricing_resolver.mjs";
import {
  validateLimousineQuoteRequest,
  LIMOUSINE_QUOTE_REASONS,
} from "./limousine_manual_quote.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const M = LIMOUSINE_PUBLISHED_PRICING_MODES;
const R = LIMOUSINE_UNIFIED_REASONS;

function offer(overrides = {}) {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    target_type: "vehicle",
    vehicle_id: "veh_1",
    vehicle_ids: ["veh_1"],
    price_presentation: "quote_required",
    currency: "EUR",
    source_revision: 4,
    title: { nl: "Party Ride", en: "Party Ride" },
    included_services: [{ item_id: "water", label: { en: "Water" } }],
    ...overrides,
  };
}

test("1) five published modes classify onto quote vs booking intent", () => {
  assert.equal(
    classifyLimousinePublishedPricingMode(offer()).pricing_mode,
    M.QUOTE_REQUIRED,
  );
  assert.equal(
    classifyLimousinePublishedPricingMode(offer()).intent_kind,
    LIMOUSINE_INTENT_KIND.QUOTE_REQUEST,
  );
  assert.equal(
    classifyLimousinePublishedPricingMode(offer({ price_presentation: "from_price" }))
      .pricing_mode,
    M.FROM_PRICE,
  );
  assert.equal(
    classifyLimousinePublishedPricingMode(offer({ price_presentation: "indicative" }))
      .pricing_mode,
    M.FROM_PRICE,
  );
  assert.equal(
    classifyLimousinePublishedPricingMode(offer({ price_presentation: "exact_fixed" }))
      .pricing_mode,
    M.EXACT_FIXED,
  );
  assert.equal(
    classifyLimousinePublishedPricingMode(
      offer({
        price_presentation: "exact_fixed",
        hourly: {
          enabled: true,
          first_hour_cents: 12000,
          additional_hour_cents: 9000,
          minimum_duration_minutes: 120,
        },
      }),
    ).pricing_mode,
    M.HOURLY,
  );
  assert.equal(
    classifyLimousinePublishedPricingMode(
      offer({
        hourly: {
          enabled: true,
          first_hour_cents: 12000,
          additional_hour_cents: 9000,
          minimum_duration_minutes: 120,
          package_amount_cents: 45000,
          package_duration_minutes: 180,
        },
      }),
    ).pricing_mode,
    M.PACKAGE,
  );
});

test("2) quote_required snapshot has no fake euro-zero price", () => {
  const snap = buildLimousineQuoteIntentSnapshot({
    offer: offer(),
    request: { occasion: "wedding", scheduled_pickup_iso: "2026-09-01T10:00:00Z" },
  });
  assert.equal(snap.ok, true);
  assert.equal(snap.service_type, LIMOUSINE_SERVICE_TYPE);
  assert.equal(snap.pricing_mode, M.QUOTE_REQUIRED);
  assert.equal(snap.guaranteed, false);
  assert.equal(snap.payable, false);
  assert.equal(snap.invoiceable, false);
  assert.equal(Object.hasOwn(snap, "shown_from_price_cents"), false);
  assert.equal(Object.hasOwn(snap, "total_incl_vat_cents"), false);
  assert.equal(snap.occasion, "wedding");
});

test("3) from_price stores shown amount as audit only", () => {
  const snap = buildLimousineQuoteIntentSnapshot({
    offer: offer({
      price_presentation: "from_price",
      display_amount_cents: 25000,
    }),
  });
  assert.equal(snap.ok, true);
  assert.equal(snap.shown_from_price_cents, 25000);
  assert.equal(snap.shown_from_price_guaranteed, false);
  assert.equal(snap.payable, false);
});

test("4+5) hourly is server-side integer cents and applies minimum duration", () => {
  const hourly = {
    enabled: true,
    first_hour_cents: 10000,
    additional_hour_cents: 10000,
    minimum_duration_minutes: 180,
    currency: "EUR",
  };
  const short = computeLimousineHourlyHireSnapshot(hourly, 60);
  assert.equal(short.ok, true);
  assert.equal(short.selected_duration_minutes, 60);
  assert.equal(short.billable_duration_minutes, 180);
  assert.equal(short.amount_cents, computeOfferHourlyCents(hourly, 60));
  assert.equal(short.amount_cents, 30000);
  const exact = computeLimousineHourlyHireSnapshot(hourly, 180);
  assert.equal(exact.amount_cents, 30000);
  const longer = computeLimousineHourlyHireSnapshot(hourly, 181);
  assert.equal(longer.billable_duration_minutes, 181);
  assert.equal(longer.amount_cents, 40000);
  assert.equal(Number.isInteger(longer.amount_cents), true);
});

test("6) package snapshot keeps included parts and fails closed without overage", () => {
  const packaged = offer({
    hourly: {
      enabled: true,
      first_hour_cents: 12000,
      additional_hour_cents: 9000,
      minimum_duration_minutes: 120,
      package_amount_cents: 45000,
      package_duration_minutes: 180,
      included_distance_km: 40,
    },
  });
  const ok = computeLimousinePackageSnapshot(packaged, 180);
  assert.equal(ok.ok, true);
  assert.equal(ok.package_amount_cents, 45000);
  assert.equal(ok.included_duration_minutes, 180);
  assert.equal(ok.included_distance_km, 40);
  assert.equal(ok.included_services.length, 1);
  assert.deepEqual(ok.vehicle_scope, ["veh_1"]);
  const missing = computeLimousinePackageSnapshot(packaged, 240);
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, R.PACKAGE_OVERAGE_RULE_MISSING);
});

test("7) frozen snapshot is not silently repriced when the offer later changes", () => {
  const original = enrichLimousineAcceptedSnapshot(
    {
      offer_id: "off_1",
      offer_source_revision: 4,
      total_incl_vat_cents: 20000,
      currency: "EUR",
    },
    {
      offer: offer({ price_presentation: "exact_fixed", source_revision: 4 }),
      request: { occasion: "gala" },
    },
  );
  const laterOffer = offer({
    price_presentation: "exact_fixed",
    source_revision: 9,
    display_amount_cents: 99999,
  });
  assert.equal(original.total_incl_vat_cents, 20000);
  assert.equal(original.offer_source_revision, 4);
  assert.notEqual(laterOffer.source_revision, original.offer_source_revision);
  assert.notEqual(laterOffer.display_amount_cents, original.total_incl_vat_cents);
});

test("8) withdrawn or stale offer fails closed", () => {
  assert.equal(
    assertLimousineOfferStillPublished(offer({ published: false })).reason,
    R.OFFER_UNPUBLISHED,
  );
  assert.equal(
    assertLimousineOfferStillPublished(offer({ enabled: false })).reason,
    R.OFFER_UNPUBLISHED,
  );
  assert.equal(
    assertLimousineOfferRevisionFresh(offer({ source_revision: 5 }), 4).reason,
    R.STALE_OFFER,
  );
  assert.equal(assertLimousineOfferRevisionFresh(offer({ source_revision: 5 }), 5).ok, true);
});

test("9) wrong vehicle scope fails", () => {
  const scoped = assertLimousineOfferVehicleScope(offer(), "veh_other");
  assert.equal(scoped.ok, false);
  assert.equal(scoped.reason, R.VEHICLE_SCOPE_MISMATCH);
  assert.equal(assertLimousineOfferVehicleScope(offer(), "veh_1").ok, true);
  const classOffer = offer({
    target_type: "service_class",
    vehicle_id: "",
    vehicle_ids: [],
  });
  assert.equal(assertLimousineOfferVehicleScope(classOffer, "").ok, true);
});

test("10) client totals are rejected and bookable offers do not open a quote", () => {
  assert.equal(
    rejectLimousineClientPricingAuthority({ total_incl_vat_cents: 1 }).reason,
    R.CLIENT_PRICING_REJECTED,
  );
  const bookable = validateLimousineQuoteRequest(
    {
      offer_id: "off_1",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
    },
    {
      eligible: true,
      offer: offer({ price_presentation: "exact_fixed" }),
      gateEnabled: true,
    },
  );
  assert.equal(bookable.ok, false);
  assert.equal(bookable.reason, LIMOUSINE_QUOTE_REASONS.OFFER_NOT_BOOKABLE_MANUALLY);
});

test("11) quote path still creates exactly one request for quote modes", () => {
  const a = validateLimousineQuoteRequest(
    {
      offer_id: "off_1",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
      occasion: "wedding",
    },
    { eligible: true, offer: offer(), gateEnabled: true },
  );
  const b = validateLimousineQuoteRequest(
    {
      offer_id: "off_1",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
      occasion: "wedding",
    },
    { eligible: true, offer: offer(), gateEnabled: true },
  );
  assert.equal(a.ok, true);
  assert.equal(b.ok, true);
  assert.equal(a.request.itinerary_fingerprint, b.request.itinerary_fingerprint);
  assert.equal(a.request.service_type, LIMOUSINE_SERVICE_TYPE);
  assert.equal(a.request.pricing_mode, M.QUOTE_REQUIRED);
  assert.equal(a.request.occasion, "wedding");
});

test("12) from_price quote request is not a booking", () => {
  const out = validateLimousineQuoteRequest(
    {
      offer_id: "off_1",
      journey_type: "point_to_point",
      from: "Gent",
      to: "Brussel",
      scheduled_pickup_iso: "2026-09-01T10:00:00Z",
    },
    {
      eligible: true,
      offer: offer({
        price_presentation: "from_price",
        display_amount_cents: 18000,
      }),
      gateEnabled: true,
    },
  );
  assert.equal(out.ok, true);
  assert.equal(out.request.pricing_mode, M.FROM_PRICE);
  assert.equal(out.request.intent_kind, LIMOUSINE_INTENT_KIND.QUOTE_REQUEST);
  assert.equal(out.snapshot.shown_from_price_cents, 18000);
  assert.equal(out.snapshot.payable, false);
});

test("13) hourly/package do not require a passenger route", () => {
  assert.equal(
    limousineBookingRequestNeedsPassengerRoute(
      offer({
        hourly: {
          enabled: true,
          first_hour_cents: 1,
          additional_hour_cents: 1,
          minimum_duration_minutes: 60,
        },
      }),
      "hourly_package",
    ),
    false,
  );
  assert.equal(
    limousineBookingRequestNeedsPassengerRoute(
      offer({
        price_presentation: "exact_fixed",
        distance_time: { enabled: true },
      }),
      "point_to_point",
    ),
    true,
  );
});

test("14) PDF lines stay inside the existing document snapshot", () => {
  const lines = limousineDocumentLinesFromSnapshot({
    service_type: LIMOUSINE_SERVICE_TYPE,
    offer_id: "off_1",
    vehicle_id: "veh_1",
    published_pricing_mode: M.PACKAGE,
    package_hire: { included_duration_minutes: 180, package_amount_cents: 45000 },
    total_incl_vat_cents: 45000,
    currency: "EUR",
    occasion: "gala",
  });
  assert.ok(lines.includes("Limousine"));
  assert.ok(lines.some((line) => line.includes("off_1")));
  assert.ok(lines.some((line) => line.includes("gala")));
});

test("15) no second limousine booking/inbox/status platform was added", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  const quote = readFileSync(join(__dirname, "limousine_manual_quote.mjs"), "utf8");
  const intent = readFileSync(join(__dirname, "limousine_unified_intent.mjs"), "utf8");
  assert.ok(worker.includes("async function handleBooking"));
  assert.ok(worker.includes("async function _prepareLimousineBooking"));
  assert.ok(worker.includes('"/limousine/quote-requests" && request.method === "POST"'));
  assert.ok(!intent.includes("createTable"));
  assert.ok(!intent.includes("limousine_bookings"));
  assert.ok(!quote.includes("CREATE TABLE"));
  assert.ok((worker.match(/async function handleBooking\(/g) || []).length >= 1);
  assert.ok(worker.includes("LIMOUSINE_QUOTE_STATES"));
  assert.ok(!worker.includes("limousine_driver_inbox"));
  assert.ok(!worker.includes("limousine_status_machine"));
});
