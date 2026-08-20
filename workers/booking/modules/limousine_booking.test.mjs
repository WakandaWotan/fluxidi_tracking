// LIMOUSINE-MARKETPLACE-P2C1 — authoritative totals, /book recompute-and-compare
// and the accepted-price snapshot.
// Run: node --test workers/booking/modules/limousine_booking.test.mjs
//
// All amounts are illustrative TEST fixtures in integer cents.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_BOOK_REASONS,
  LIMOUSINE_COMPONENT_TYPES,
  buildLimousineAcceptedSnapshot,
  buildLimousineQuoteResult,
  compareLimousineQuoteForBook,
  composeLimousineTotal,
  limousineBookGateEnabled,
  limousineQuoteFingerprint,
  safeMobilisationDisclosure,
} from "./limousine_booking.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const R = LIMOUSINE_BOOK_REASONS;
const ROUTE = { distance_km: 20, duration_min: 30 };

function offer(overrides = {}) {
  return {
    offer_id: "off_1",
    enabled: true,
    published: true,
    target_type: "service_class",
    service_class_id: "executive_sedan",
    price_presentation: "exact_fixed",
    currency: "EUR",
    journey_types: ["point_to_point", "airport_transfer", "hourly_package"],
    fixed_rules: [],
    mobilisation: { method: "included" },
    source_revision: 3,
    ...overrides,
  };
}

function section(offerOverrides = {}, sectionOverrides = {}) {
  return {
    enabled: true,
    currency: "EUR",
    source_revision: 5,
    offers: [offer(offerOverrides)],
    ...sectionOverrides,
  };
}

function compose(offerOverrides = {}, request = {}, routes = { main: ROUTE }) {
  return composeLimousineTotal({
    section: section(offerOverrides),
    offerId: "off_1",
    request: {
      service_class_id: "executive_sedan",
      journey_type: "point_to_point",
      currency: "EUR",
      ...request,
    },
    routes,
  });
}

const FIXED_RULE = {
  rule_id: "r1",
  enabled: true,
  journey_type: "point_to_point",
  zone_type: "none",
  amount_cents: 20000,
  vat_rate: 0.06,
  currency: "EUR",
};

const DISTANCE_TIME = {
  enabled: true,
  base_incl_vat_cents: 5000,
  per_km_incl_vat_cents: 200,
  per_minute_incl_vat_cents: 100,
  minimum_incl_vat_cents: 8000,
  vat_rate: 0.06,
  currency: "EUR",
};

const HOURLY = {
  enabled: true,
  first_hour_cents: 12000,
  additional_hour_cents: 9000,
  minimum_duration_minutes: 180,
  currency: "EUR",
  vat_rate: 0.06,
};

test("1/2) gates are independent and default OFF", () => {
  assert.equal(limousineBookGateEnabled("0"), false);
  assert.equal(limousineBookGateEnabled(undefined), false);
  assert.equal(limousineBookGateEnabled("false"), false);
  assert.equal(limousineBookGateEnabled("1"), true);
  const wrangler = readFileSync(join(__dirname, "..", "wrangler.toml"), "utf8");
  assert.ok(!wrangler.includes("LIMOUSINE_QUOTE_ENABLED"));
  assert.ok(!wrangler.includes("LIMOUSINE_BOOK_ENABLED"));
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.ok(worker.includes('env?.LIMOUSINE_QUOTE_ENABLED ?? "0"'));
  assert.ok(worker.includes('env?.LIMOUSINE_BOOK_ENABLED ?? "0"'));
});

test("3) fixed offer produces an itemized authoritative total", () => {
  const total = compose({ fixed_rules: [FIXED_RULE] });
  assert.equal(total.ok, true);
  assert.equal(total.pricing_mode, "fixed_route_or_airport_fare");
  assert.equal(total.components.length, 1);
  assert.equal(total.components[0].type, LIMOUSINE_COMPONENT_TYPES.MAIN_JOURNEY);
  assert.equal(total.components[0].amount_cents, 20000);
  assert.equal(total.components[0].source_revision, 3);
  assert.equal(total.total_incl_vat_cents, 20000);
  assert.equal(total.price_incl_vat, 200);
  assert.equal(total.currency, "EUR");
});

test("4) hourly bills at least the configured minimum duration", () => {
  const total = compose(
    { hourly: HOURLY },
    { journey_type: "hourly_package", requested_duration_minutes: 60 },
  );
  assert.equal(total.ok, true);
  // 180 min minimum => 3 hours => 12000 + 9000*2 = 30000c
  assert.equal(total.total_incl_vat_cents, 30000);
  assert.equal(total.legs[0].charged_duration_minutes, 180);
});

test("5) package plus authoritative excess hours", () => {
  const total = compose(
    {
      hourly: {
        ...HOURLY,
        package_duration_minutes: 240,
        package_amount_cents: 36000,
        excess_hour_cents: 9500,
      },
    },
    { journey_type: "hourly_package", requested_duration_minutes: 330 },
  );
  assert.equal(total.ok, true);
  const types = total.components.map((c) => c.type);
  assert.ok(types.includes(LIMOUSINE_COMPONENT_TYPES.HOURLY_PACKAGE));
  assert.ok(types.includes(LIMOUSINE_COMPONENT_TYPES.EXCESS_HOURS));
  // 90 excess minutes => 2 started hours => 36000 + 19000 = 55000c
  assert.equal(total.total_incl_vat_cents, 55000);
  assert.equal(total.legs[0].charged_duration_minutes, 330);
});

test("maximum duration violation fails closed", () => {
  const total = compose(
    { hourly: { ...HOURLY, maximum_duration_minutes: 300 } },
    { journey_type: "hourly_package", requested_duration_minutes: 400 },
  );
  assert.equal(total.ok, false);
  assert.equal(total.reason, R.MAX_DURATION_EXCEEDED);
});

test("6) distance/time uses the SERVER route", () => {
  const total = compose({ distance_time: DISTANCE_TIME });
  // 5000 + 20*200 + 30*100 = 12000c
  assert.equal(total.total_incl_vat_cents, 12000);
  const longer = compose({ distance_time: DISTANCE_TIME }, {}, {
    main: { distance_km: 40, duration_min: 60 },
  });
  // 5000 + 8000 + 6000 = 19000c
  assert.equal(longer.total_incl_vat_cents, 19000);
  // Route failure fails closed.
  const noRoute = compose({ distance_time: DISTANCE_TIME }, {}, { main: null });
  assert.equal(noRoute.ok, false);
  assert.equal(noRoute.reason, R.ROUTE_FAILED);
});

test("7/8) outbound and return fixed-fee mobilisation are itemized once each", () => {
  const both = compose({
    fixed_rules: [FIXED_RULE],
    mobilisation: {
      method: "fixed_fee",
      outbound_charged: true,
      return_charged: true,
      fee_cents: 4000,
      currency: "EUR",
    },
  });
  const mobOut = both.components.filter(
    (c) => c.type === LIMOUSINE_COMPONENT_TYPES.MOBILISATION_OUTBOUND,
  );
  const mobRet = both.components.filter(
    (c) => c.type === LIMOUSINE_COMPONENT_TYPES.MOBILISATION_RETURN,
  );
  assert.equal(mobOut.length, 1);
  assert.equal(mobRet.length, 1);
  assert.equal(both.total_incl_vat_cents, 20000 + 4000 + 4000);

  const outboundOnly = compose({
    fixed_rules: [FIXED_RULE],
    mobilisation: {
      method: "fixed_fee",
      outbound_charged: true,
      fee_cents: 4000,
      currency: "EUR",
    },
  });
  assert.equal(outboundOnly.total_incl_vat_cents, 24000);
});

test("9) included mobilisation adds exactly zero", () => {
  const total = compose({
    fixed_rules: [FIXED_RULE],
    mobilisation: { method: "included" },
  });
  assert.equal(total.total_incl_vat_cents, 20000);
  assert.equal(
    total.components.some((c) => c.type.startsWith("mobilisation")),
    false,
  );
  assert.equal(total.mobilisation.included, true);
  assert.equal(total.mobilisation.charged_separately, false);
});

test("10) distance/time mobilisation uses server base legs, base address excluded", () => {
  const total = composeLimousineTotal({
    section: section({
      fixed_rules: [FIXED_RULE],
      distance_time: DISTANCE_TIME,
      mobilisation: {
        method: "distance_time",
        outbound_charged: true,
        included_distance_km: 5,
        included_minutes: 5,
        currency: "EUR",
        operating_base_address: "Geheimestraat 1, 9000 Gent",
        disclosure: { en: "Mobilisation charged separately" },
      },
    }),
    offerId: "off_1",
    request: {
      service_class_id: "executive_sedan",
      journey_type: "point_to_point",
      currency: "EUR",
    },
    routes: {
      main: ROUTE,
      mobilisation_outbound: { distance_km: 15, duration_min: 25 },
    },
  });
  assert.equal(total.ok, true);
  // (15-5)*200 + (25-5)*100 = 2000 + 2000 = 4000c
  const mob = total.components.find(
    (c) => c.type === LIMOUSINE_COMPONENT_TYPES.MOBILISATION_OUTBOUND,
  );
  assert.equal(mob.amount_cents, 4000);
  assert.equal(total.total_incl_vat_cents, 24000);
  const json = JSON.stringify(total);
  assert.ok(!json.includes("Geheimestraat"), "base address must never leak");
  assert.ok(!json.includes("operating_base_address"));
});

test("11) missing base for distance/time mobilisation fails closed", () => {
  const total = composeLimousineTotal({
    section: section({
      fixed_rules: [FIXED_RULE],
      distance_time: DISTANCE_TIME,
      mobilisation: {
        method: "distance_time",
        outbound_charged: true,
        currency: "EUR",
      },
    }),
    offerId: "off_1",
    request: {
      service_class_id: "executive_sedan",
      journey_type: "point_to_point",
      currency: "EUR",
    },
    // No mobilisation route supplied (missing base) => fail closed.
    routes: { main: ROUTE },
  });
  assert.equal(total.ok, false);
  assert.equal(total.reason, R.MOBILISATION_INCOMPLETE);
});

test("12/13/14) paid extras: authoritative only", () => {
  const withExtras = {
    fixed_rules: [FIXED_RULE],
    paid_extras: [
      { extra_id: "wait", label: { en: "Waiting" }, amount_cents: 2500, currency: "EUR", active: true, public: true },
      { extra_id: "hidden", label: { en: "Hidden" }, amount_cents: 999, currency: "EUR", active: true, public: false },
      { extra_id: "off", label: { en: "Off" }, amount_cents: 999, currency: "EUR", active: false, public: true },
      { extra_id: "deco", label: { en: "Decoration" }, quote_required: true, currency: "EUR", active: true, public: true },
    ],
  };
  // Valid extra.
  const ok = compose(withExtras, { selected_extra_ids: ["wait"] });
  assert.equal(ok.ok, true);
  assert.equal(ok.total_incl_vat_cents, 22500);
  assert.equal(ok.selected_extras[0].extra_id, "wait");
  // Unknown, non-public and inactive all fail closed.
  for (const id of ["nope", "hidden", "off"]) {
    const bad = compose(withExtras, { selected_extra_ids: [id] });
    assert.equal(bad.ok, false, id);
    assert.equal(bad.reason, R.INVALID_EXTRA, id);
  }
  // A quote-required extra makes the whole request manual.
  const manual = compose(withExtras, { selected_extra_ids: ["deco"] });
  assert.equal(manual.manual_quote_required, true);
  assert.equal(manual.reason, R.MANUAL_QUOTE_REQUIRED);
  // The same extra can never be double charged.
  const dedupe = compose(withExtras, { selected_extra_ids: ["wait", "wait"] });
  assert.equal(dedupe.total_incl_vat_cents, 22500);
});

test("15) from / indicative / quote_required / unavailable are not directly bookable", () => {
  for (const presentation of ["from_price", "indicative", "quote_required"]) {
    const total = compose({ fixed_rules: [FIXED_RULE], price_presentation: presentation });
    assert.equal(total.ok, false, presentation);
    assert.equal(total.manual_quote_required, true, presentation);
    assert.equal(total.total_incl_vat_cents, undefined, presentation);
  }
  const unavailable = compose({ fixed_rules: [FIXED_RULE], price_presentation: "unavailable" });
  assert.equal(unavailable.ok, false);
  assert.equal(unavailable.unavailable, true);
});

test("16/27) one-way quote result and snapshot carry complete provenance", () => {
  const total = compose({ fixed_rules: [FIXED_RULE] });
  const quote = buildLimousineQuoteResult(total, {
    distanceKm: 20,
    durationMin: 30,
    scheduledPickupIso: "2026-09-01T10:00:00Z",
    pax: 2,
    bags: 1,
  });
  assert.equal(quote.resolved, true);
  assert.ok(quote.quote_reference.startsWith("limq_"));
  for (const key of [
    "offer_id",
    "service_class_id",
    "journey_type",
    "pricing_mode",
    "legs",
    "components",
    "mobilisation",
    "subtotal_cents",
    "total_incl_vat_cents",
    "currency",
    "offer_source_revision",
    "pricing_section_revision",
    "quoted_at",
    "expires_at",
  ]) {
    assert.ok(quote[key] !== undefined, `quote missing ${key}`);
  }
  const snapshot = buildLimousineAcceptedSnapshot({
    total,
    quoteReference: quote.quote_reference,
    acceptedAtIso: "2026-08-17T12:00:00Z",
    scheduledPickupIso: "2026-09-01T10:00:00Z",
    companyId: "cmp_x",
  });
  for (const key of [
    "service_category",
    "journey_type",
    "offer_id",
    "service_class_id",
    "pricing_mode",
    "quote_reference",
    "offer_source_revision",
    "pricing_section_revision",
    "components",
    "legs",
    "mobilisation",
    "subtotal_cents",
    "total_incl_vat_cents",
    "currency",
    "scheduled_pickup_iso",
    "accepted_at",
  ]) {
    assert.ok(snapshot[key] !== undefined, `snapshot missing ${key}`);
  }
  assert.equal(snapshot.service_category, "limousine");
});

test("17) roundtrip prices both legs without duplicating mobilisation", () => {
  const total = composeLimousineTotal({
    section: section({
      fixed_rules: [
        { ...FIXED_RULE, rule_id: "r_to", journey_type: "airport_transfer", airport_iata: "BRU", direction: "to_airport", amount_cents: 18000 },
        { ...FIXED_RULE, rule_id: "r_from", journey_type: "airport_transfer", airport_iata: "BRU", direction: "from_airport", amount_cents: 17000 },
      ],
      mobilisation: {
        method: "fixed_fee",
        outbound_charged: true,
        return_charged: true,
        fee_cents: 4000,
        currency: "EUR",
      },
    }),
    offerId: "off_1",
    request: {
      service_class_id: "executive_sedan",
      journey_type: "airport_transfer",
      direction: "to_airport",
      airport_iata: "BRU",
      currency: "EUR",
      roundtrip: true,
    },
    routes: { main: ROUTE, return: { distance_km: 21, duration_min: 32 } },
  });
  assert.equal(total.ok, true);
  assert.equal(total.legs.length, 2);
  // Direction-specific rules used per leg.
  assert.equal(total.legs[0].amount_cents, 18000);
  assert.equal(total.legs[1].amount_cents, 17000);
  // Exactly one outbound + one return mobilisation row (no duplication).
  assert.equal(
    total.components.filter((c) => c.type.startsWith("mobilisation")).length,
    2,
  );
  assert.equal(total.total_incl_vat_cents, 18000 + 17000 + 4000 + 4000);
});

test("roundtrip fails closed when one leg cannot be priced", () => {
  const total = composeLimousineTotal({
    section: section({
      fixed_rules: [
        { ...FIXED_RULE, rule_id: "r_to", journey_type: "airport_transfer", airport_iata: "BRU", direction: "to_airport" },
      ],
    }),
    offerId: "off_1",
    request: {
      service_class_id: "executive_sedan",
      journey_type: "airport_transfer",
      direction: "to_airport",
      airport_iata: "BRU",
      currency: "EUR",
      roundtrip: true,
    },
    routes: { main: ROUTE, return: { distance_km: 21, duration_min: 32 } },
  });
  assert.equal(total.ok, false);
  assert.equal(total.total_incl_vat_cents, undefined);
});

test("18/19/20) /book recompute matches, changes are rejected, client total ignored", () => {
  const total = compose({ fixed_rules: [FIXED_RULE] });
  const reference = limousineQuoteFingerprint(total);

  // Matching recompute is accepted.
  const match = compareLimousineQuoteForBook({
    recomputed: total,
    clientQuoteReference: reference,
  });
  assert.equal(match.ok, true);
  assert.equal(match.quote_reference, reference);

  // A changed price yields a different fingerprint => refresh required.
  const changed = compose({
    fixed_rules: [{ ...FIXED_RULE, amount_cents: 25000 }],
  });
  const mismatch = compareLimousineQuoteForBook({
    recomputed: changed,
    clientQuoteReference: reference,
  });
  assert.equal(mismatch.ok, false);
  assert.equal(mismatch.reason, R.QUOTE_MISMATCH);
  assert.equal(mismatch.refresh_required, true);

  // A changed offer revision also invalidates the quote.
  const bumped = compose({ fixed_rules: [FIXED_RULE], source_revision: 4 });
  assert.notEqual(limousineQuoteFingerprint(bumped), reference);

  // A missing reference is rejected rather than trusted.
  assert.equal(
    compareLimousineQuoteForBook({ recomputed: total, clientQuoteReference: "" }).reason,
    R.MISSING_QUOTE_REFERENCE,
  );

  // The composer never reads a client total.
  const withClientTotal = composeLimousineTotal({
    section: section({ fixed_rules: [FIXED_RULE] }),
    offerId: "off_1",
    request: {
      service_class_id: "executive_sedan",
      journey_type: "point_to_point",
      currency: "EUR",
      price_incl_vat: 1,
      total_incl_vat_cents: 1,
      price_ex_vat: 1,
    },
    routes: { main: ROUTE },
  });
  assert.equal(withClientTotal.total_incl_vat_cents, 20000);
});

test("currency mismatch and unknown offer fail closed", () => {
  assert.equal(compose({ fixed_rules: [FIXED_RULE] }, { currency: "USD" }).ok, false);
  const unknown = composeLimousineTotal({
    section: section({ fixed_rules: [FIXED_RULE] }),
    offerId: "off_missing",
    request: { journey_type: "point_to_point", currency: "EUR" },
    routes: { main: ROUTE },
  });
  assert.equal(unknown.reason, R.UNKNOWN_OFFER);
  const disabled = compose({ fixed_rules: [FIXED_RULE], enabled: false });
  assert.equal(disabled.reason, R.OFFER_DISABLED);
});

test("28) quote result and snapshot expose no private or internal fields", () => {
  const total = compose({
    fixed_rules: [FIXED_RULE],
    mobilisation: {
      method: "included",
      operating_base_address: "Geheimestraat 1",
      disclosure: { en: "Included" },
    },
  });
  const rendered = JSON.stringify([
    buildLimousineQuoteResult(total, {}),
    buildLimousineAcceptedSnapshot({ total, acceptedAtIso: "x" }),
    safeMobilisationDisclosure(total),
  ]);
  for (const secret of [
    "Geheimestraat",
    "operating_base_address",
    "license_plate",
    "driver_id",
    "subscription",
    "margin",
  ]) {
    assert.ok(!rendered.includes(secret), `leaked ${secret}`);
  }
});

test("21/22/23/24/25/26) worker wiring: isolation, idempotency and no fallback", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  // Book gate checked before ANY write, and independent of the quote gate.
  assert.ok(worker.includes("function _limousineBookGateEnabled(env)"));
  assert.ok(worker.includes('return { ok: false, error: "limousine_book_disabled" };'));
  // Pre-flight runs before booking-intent idempotency + reference allocation.
  const preflightIdx = worker.indexOf("_prepareLimousineBooking(env, tenantContext, payload");
  const intentIdx = worker.indexOf("const bookingIntent = buildBookingIntentDescriptor({");
  const idIdx = worker.indexOf("const canonicalBookingId = providedId || await nextHumanBookingId(");
  assert.ok(preflightIdx > 0 && intentIdx > preflightIdx, "pre-flight precedes idempotency");
  assert.ok(idIdx > preflightIdx, "pre-flight precedes reference allocation");
  // Existing idempotency semantics are untouched (still intent-hash based).
  assert.ok(worker.includes("buildBookingIntentDescriptor({"));
  assert.ok(worker.includes("putBookingCreateIfAbsent"));
  // No taxi fallback: limousine replaces calcPrice and disables airport fares.
  assert.ok(worker.includes("const mainPricing = _limousineAccepted"));
  assert.ok(worker.includes("!_limousineAccepted &&\n      _isAirportFixedFareEligiblePayload(payload)"));
  assert.ok(worker.includes("if (_limousineAccepted) {\n      ret.enabled = false;\n    }"));
  // Accepted snapshot frozen on the booking record.
  assert.ok(worker.includes("limousine_accepted_price: _limousineAccepted.snapshot"));
  // Street-meter finalization is never used for limousine (direct-ride module
  // is untouched by the limousine branch).
  const branchStart = worker.indexOf("async function _prepareLimousineBooking");
  const branchEnd = worker.indexOf("/// Shared authoritative Limousine resolution");
  const branch = worker.slice(branchStart, branchEnd);
  for (const forbidden of ["calcPrice(", "resolveAirportFixedFare(", "directTripTotals", "street"]) {
    assert.ok(!branch.includes(forbidden), `limousine pre-flight must not use ${forbidden}`);
  }
  // Deactivation guard still only blocks NEW bookings.
  assert.ok(worker.includes("_assertFluxidiCompanyCanCreateNewBooking"));
});
