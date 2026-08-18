// LIMOUSINE-MARKETPLACE-P2B2 — offers, precedence and safe public projection.
// Run: node --test workers/booking/modules/limousine_offers.test.mjs
//
// All amounts are illustrative TEST fixtures in integer cents, never production
// fares.

import test from "node:test";
import assert from "node:assert/strict";

import {
  LIMOUSINE_MOBILISATION_METHODS,
  LIMOUSINE_OFFER_ERRORS,
  LIMOUSINE_OFFER_TARGETS,
  LIMOUSINE_PRICE_PRESENTATIONS,
  buildSafePublicLimousineOffers,
  limousineOffersRevisionAccepts,
  normalizeLimousineOffers,
  offerAmountIsSnapshotEligible,
  offerCanProduceResolvedPrice,
  selectLimousineOfferForRequest,
  validateLimousineOffer,
} from "./limousine_offers.mjs";
import {
  computeOfferHourlyCents,
  resolveLimousineQuote,
} from "./limousine_pricing_resolver.mjs";

const CLASS_IDS = ["executive_sedan", "business_van"];
const VEHICLES = [
  {
    id: "vh_1",
    is_active: true,
    service_category: "limousine",
    service_class_id: "executive_sedan",
  },
  {
    id: "vh_taxi",
    is_active: true,
    service_category: "",
    service_class_id: "",
  },
  {
    id: "vh_inactive",
    is_active: false,
    service_category: "limousine",
    service_class_id: "executive_sedan",
  },
];

function classOffer(overrides = {}) {
  return {
    offer_id: "off_class",
    enabled: true,
    published: true,
    target_type: LIMOUSINE_OFFER_TARGETS.SERVICE_CLASS,
    service_class_id: "executive_sedan",
    price_presentation: LIMOUSINE_PRICE_PRESENTATIONS.EXACT_FIXED,
    currency: "EUR",
    journey_types: ["point_to_point"],
    title: { nl: "Klasse", en: "Class", fr: "Classe", es: "Clase" },
    fixed_rules: [
      {
        rule_id: "r1",
        enabled: true,
        journey_type: "point_to_point",
        zone_type: "none",
        amount_cents: 20000,
        currency: "EUR",
      },
    ],
    mobilisation: { method: LIMOUSINE_MOBILISATION_METHODS.INCLUDED },
    source_revision: 2,
    ...overrides,
  };
}

function vehicleOffer(overrides = {}) {
  return {
    ...classOffer(),
    offer_id: "off_vehicle",
    target_type: LIMOUSINE_OFFER_TARGETS.VEHICLE,
    vehicle_id: "vh_1",
    title: { nl: "Voertuig", en: "Vehicle", fr: "Véhicule", es: "Vehículo" },
    fixed_rules: [
      {
        rule_id: "r1",
        enabled: true,
        journey_type: "point_to_point",
        zone_type: "none",
        amount_cents: 15000,
        currency: "EUR",
      },
    ],
    ...overrides,
  };
}

const validateOpts = { knownVehicles: VEHICLES, knownClassIds: CLASS_IDS, readiness: true };

test("3) exact vehicle offer overrides the service-class offer", () => {
  const offers = [classOffer(), vehicleOffer()];
  const picked = selectLimousineOfferForRequest(offers, {
    vehicleId: "vh_1",
    serviceClassId: "executive_sedan",
    journeyType: "point_to_point",
  });
  assert.equal(picked.offer_id, "off_vehicle");
  // Without a vehicle in the request, the class offer applies.
  const classPick = selectLimousineOfferForRequest(offers, {
    serviceClassId: "executive_sedan",
    journeyType: "point_to_point",
  });
  assert.equal(classPick.offer_id, "off_class");
});

test("4) unknown vehicle / class / non-limousine vehicle fail closed", () => {
  const unknownVehicle = validateLimousineOffer(
    vehicleOffer({ vehicle_id: "nope" }),
    validateOpts,
  );
  assert.equal(unknownVehicle.valid, false);
  assert.ok(unknownVehicle.errors.includes(LIMOUSINE_OFFER_ERRORS.UNKNOWN_VEHICLE));

  const taxiVehicle = validateLimousineOffer(
    vehicleOffer({ vehicle_id: "vh_taxi" }),
    validateOpts,
  );
  assert.ok(taxiVehicle.errors.includes(LIMOUSINE_OFFER_ERRORS.VEHICLE_NOT_LIMOUSINE));

  const inactive = validateLimousineOffer(
    vehicleOffer({ vehicle_id: "vh_inactive" }),
    validateOpts,
  );
  assert.ok(inactive.errors.includes(LIMOUSINE_OFFER_ERRORS.INACTIVE_VEHICLE));

  const unknownClass = validateLimousineOffer(
    classOffer({ service_class_id: "unknown_class" }),
    validateOpts,
  );
  assert.ok(unknownClass.errors.includes(LIMOUSINE_OFFER_ERRORS.UNKNOWN_SERVICE_CLASS));
});

test("5/6) hourly needs first+additional hour AND a minimum duration", () => {
  const missingMinimum = validateLimousineOffer(
    classOffer({
      hourly: {
        enabled: true,
        first_hour_cents: 12000,
        additional_hour_cents: 9000,
        currency: "EUR",
      },
    }),
    validateOpts,
  );
  assert.ok(
    missingMinimum.errors.includes(
      LIMOUSINE_OFFER_ERRORS.HOURLY_MISSING_MINIMUM_DURATION,
    ),
  );

  const missingRates = validateLimousineOffer(
    classOffer({
      hourly: { enabled: true, minimum_duration_minutes: 180, currency: "EUR" },
    }),
    validateOpts,
  );
  assert.ok(missingRates.errors.includes(LIMOUSINE_OFFER_ERRORS.HOURLY_INCOMPLETE));

  // Minimum duration is enforced when computing the hire total.
  const hourly = {
    enabled: true,
    first_hour_cents: 12000,
    additional_hour_cents: 9000,
    minimum_duration_minutes: 180,
    currency: "EUR",
  };
  // 60 minutes requested but 180 minimum => 3 hours billed.
  assert.equal(computeOfferHourlyCents(hourly, 60), 12000 + 9000 * 2);
  assert.equal(computeOfferHourlyCents(hourly, 240), 12000 + 9000 * 3);
  // A first-hour price alone is never a complete trip price.
  assert.equal(
    computeOfferHourlyCents(
      { enabled: true, first_hour_cents: 12000, additional_hour_cents: 9000 },
      120,
    ),
    null,
  );
});

test("7) exact fixed is accepted only with complete matching data", () => {
  const incomplete = validateLimousineOffer(
    classOffer({
      fixed_rules: [
        {
          rule_id: "r1",
          enabled: true,
          journey_type: "airport_transfer",
          zone_type: "none",
          amount_cents: 20000,
          currency: "EUR",
          // airport_iata missing => incomplete
        },
      ],
    }),
    validateOpts,
  );
  assert.ok(incomplete.errors.includes(LIMOUSINE_OFFER_ERRORS.INCOMPLETE_FIXED_RULE));
  assert.equal(validateLimousineOffer(classOffer(), validateOpts).valid, true);
});

test("8/9/10) from / indicative / quote never become a final price", () => {
  for (const presentation of [
    LIMOUSINE_PRICE_PRESENTATIONS.FROM_PRICE,
    LIMOUSINE_PRICE_PRESENTATIONS.INDICATIVE,
    LIMOUSINE_PRICE_PRESENTATIONS.QUOTE_REQUIRED,
  ]) {
    const offer = classOffer({ price_presentation: presentation, display_amount_cents: 19900 });
    assert.equal(offerCanProduceResolvedPrice(offer), false, presentation);
    assert.equal(offerAmountIsSnapshotEligible(offer), false, presentation);

    const resolution = resolveLimousineQuote({
      gateEnabled: true,
      eligible: true,
      section: { enabled: true, currency: "EUR", source_revision: 1, offers: [offer] },
      request: {
        service_category: "limousine",
        service_class_id: "executive_sedan",
        journey_type: "point_to_point",
        currency: "EUR",
      },
      route: { distance_km: 10, duration_min: 15 },
    });
    assert.equal(resolution.resolved, false, presentation);
    assert.equal(resolution.manual_quote_required, true, presentation);
    // No invented total.
    assert.equal(resolution.price_incl_vat, undefined, presentation);
  }
});

test("11) an exact_fixed offer that cannot price never falls back to taxi", () => {
  const offer = classOffer({
    journey_types: ["point_to_point"],
    fixed_rules: [],
    hourly: null,
    distance_time: null,
  });
  const resolution = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: { enabled: true, currency: "EUR", source_revision: 1, offers: [offer] },
    request: {
      service_category: "limousine",
      service_class_id: "executive_sedan",
      journey_type: "point_to_point",
      currency: "EUR",
    },
    route: { distance_km: 10, duration_min: 15 },
  });
  assert.equal(resolution.resolved, false);
  assert.equal(resolution.price_incl_vat, undefined);
});

test("offer fixed rule resolves through the shared quote resolver", () => {
  const resolution = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: {
      enabled: true,
      currency: "EUR",
      source_revision: 1,
      offers: [vehicleOffer()],
    },
    request: {
      service_category: "limousine",
      service_class_id: "executive_sedan",
      vehicle_id: "vh_1",
      journey_type: "point_to_point",
      currency: "EUR",
    },
    route: { distance_km: 10, duration_min: 15 },
  });
  assert.equal(resolution.resolved, true);
  assert.equal(resolution.price_incl_vat, 150); // 15000 cents
  assert.equal(resolution.matched_rule_ref, "off_vehicle:r1");
});

test("12/13/14) mobilisation included, charged-complete, incomplete", () => {
  const included = validateLimousineOffer(
    classOffer({ mobilisation: { method: LIMOUSINE_MOBILISATION_METHODS.INCLUDED } }),
    validateOpts,
  );
  assert.equal(included.valid, true);

  const chargedComplete = validateLimousineOffer(
    classOffer({
      mobilisation: {
        method: LIMOUSINE_MOBILISATION_METHODS.FIXED_FEE,
        outbound_charged: true,
        fee_cents: 5000,
        currency: "EUR",
      },
    }),
    validateOpts,
  );
  assert.equal(chargedComplete.valid, true);

  const chargedIncomplete = validateLimousineOffer(
    classOffer({
      mobilisation: {
        method: LIMOUSINE_MOBILISATION_METHODS.FIXED_FEE,
        outbound_charged: true,
        currency: "EUR",
      },
    }),
    validateOpts,
  );
  assert.ok(
    chargedIncomplete.errors.includes(LIMOUSINE_OFFER_ERRORS.MOBILISATION_INCOMPLETE),
  );

  const contradictory = validateLimousineOffer(
    classOffer({
      mobilisation: {
        method: LIMOUSINE_MOBILISATION_METHODS.INCLUDED,
        outbound_charged: true,
      },
    }),
    validateOpts,
  );
  assert.ok(
    contradictory.errors.includes(LIMOUSINE_OFFER_ERRORS.MOBILISATION_CONTRADICTORY),
  );
});

test("15) the private operating-base address is never projected publicly", () => {
  const offer = classOffer({
    mobilisation: {
      method: LIMOUSINE_MOBILISATION_METHODS.INCLUDED,
      operating_base_address: "Geheimestraat 1, 9000 Gent",
      disclosure: { nl: "Voorrijden inbegrepen", en: "Mobilisation included", fr: "", es: "" },
    },
  });
  const safe = buildSafePublicLimousineOffers([offer], { eligible: true, ...validateOpts });
  assert.equal(safe.length, 1);
  const json = JSON.stringify(safe);
  assert.ok(!json.includes("Geheimestraat"), "base address must not leak");
  assert.ok(!json.includes("operating_base_address"), "key must not leak");
  assert.equal(safe[0].mobilisation.included, true);
  assert.equal(safe[0].mobilisation.charged_separately, false);
});

test("16) included services and paid extras stay separate", () => {
  const offer = classOffer({
    included_services: [
      { item_id: "water", label: { nl: "Water", en: "Water", fr: "Eau", es: "Agua" }, active: true },
    ],
    paid_extras: [
      {
        extra_id: "wait",
        label: { nl: "Wachttijd", en: "Waiting time", fr: "Attente", es: "Espera" },
        amount_cents: 2500,
        currency: "EUR",
        active: true,
        public: true,
      },
      {
        extra_id: "deco",
        label: { nl: "Decoratie", en: "Decoration", fr: "Décoration", es: "Decoración" },
        quote_required: true,
        currency: "EUR",
        active: true,
        public: true,
      },
    ],
  });
  const safe = buildSafePublicLimousineOffers([offer], { eligible: true, ...validateOpts })[0];
  assert.equal(safe.included_services.length, 1);
  assert.equal(safe.paid_extras.length, 2);
  assert.equal(safe.included_services[0].item_id, "water");
  // Included services never carry an amount.
  assert.equal(safe.included_services[0].amount_cents, undefined);
  // A quote-required extra exposes no amount.
  const deco = safe.paid_extras.find((e) => e.extra_id === "deco");
  assert.equal(deco.quote_required, true);
  assert.equal(deco.amount_cents, undefined);
});

test("17) unpublished or disabled offers are excluded from the projection", () => {
  const unpublished = classOffer({ published: false });
  const disabled = classOffer({ offer_id: "off_disabled", enabled: false });
  const safe = buildSafePublicLimousineOffers([unpublished, disabled], {
    eligible: true,
    ...validateOpts,
  });
  assert.deepEqual(safe, []);
});

test("18) an ineligible company projects nothing", () => {
  const safe = buildSafePublicLimousineOffers([classOffer()], {
    eligible: false,
    ...validateOpts,
  });
  assert.deepEqual(safe, []);
  // Publishing while not ready is a validation error.
  const published = validateLimousineOffer(classOffer(), {
    knownVehicles: VEHICLES,
    knownClassIds: CLASS_IDS,
    readiness: false,
  });
  assert.ok(
    published.errors.includes(LIMOUSINE_OFFER_ERRORS.PUBLISHED_WITHOUT_READINESS),
  );
});

test("19) an older revision can never overwrite newer configuration", () => {
  assert.equal(limousineOffersRevisionAccepts({ currentRevision: 5, incomingRevision: 4 }), false);
  assert.equal(limousineOffersRevisionAccepts({ currentRevision: 5, incomingRevision: 5 }), false);
  assert.equal(limousineOffersRevisionAccepts({ currentRevision: 5, incomingRevision: 6 }), true);
});

test("20) disabling an offer only stops discovery; config is preserved", () => {
  const offer = classOffer();
  const disabled = { ...offer, enabled: false };
  // Configuration is untouched (no destructive cleanup).
  assert.equal(disabled.fixed_rules.length, offer.fixed_rules.length);
  assert.equal(disabled.offer_id, offer.offer_id);
  assert.equal(disabled.source_revision, offer.source_revision);
  // But it no longer reaches discovery.
  assert.deepEqual(
    buildSafePublicLimousineOffers([disabled], { eligible: true, ...validateOpts }),
    [],
  );
  assert.equal(
    selectLimousineOfferForRequest([disabled], {
      serviceClassId: "executive_sedan",
      journeyType: "point_to_point",
    }),
    null,
  );
});

test("negative amounts and currency conflicts fail closed", () => {
  const negative = validateLimousineOffer(
    classOffer({ display_amount_cents: -100 }),
    validateOpts,
  );
  assert.ok(negative.errors.includes(LIMOUSINE_OFFER_ERRORS.NEGATIVE_AMOUNT));

  const conflict = validateLimousineOffer(
    classOffer({
      fixed_rules: [
        {
          rule_id: "r1",
          enabled: true,
          journey_type: "point_to_point",
          zone_type: "none",
          amount_cents: 20000,
          currency: "USD",
        },
      ],
    }),
    validateOpts,
  );
  assert.ok(conflict.errors.includes(LIMOUSINE_OFFER_ERRORS.CURRENCY_CONFLICT));
});

test("normalization keeps stable ids and drops idless rows", () => {
  const normalized = normalizeLimousineOffers([classOffer(), { enabled: true }]);
  assert.equal(normalized.length, 1);
  assert.equal(normalized[0].offer_id, "off_class");
});
