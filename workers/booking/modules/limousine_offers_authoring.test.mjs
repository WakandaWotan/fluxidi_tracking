// LIMOUSINE-MARKETPLACE-P2B2C — authoring roundtrip, authoritative vehicle
// join, full safe projection and price-semantics independence.
// Run: node --test workers/booking/modules/limousine_offers_authoring.test.mjs
//
// All amounts are illustrative TEST fixtures in integer cents.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  LIMOUSINE_OFFER_PRICING_MODES,
  LIMOUSINE_OFFER_TARGETS,
  LIMOUSINE_PRICE_PRESENTATIONS,
  LIMOUSINE_PRIVATE_VEHICLE_FIELDS,
  buildSafePublicLimousineOffers,
  buildSafePublicVehicle,
  normalizeLimousineOffers,
  offerCanProduceResolvedPrice,
  offerSupportedPricingModes,
  selectLimousineOfferForRequest,
} from "./limousine_offers.mjs";
import { resolveLimousineQuote } from "./limousine_pricing_resolver.mjs";
import { normalizeLimousinePricingSection } from "./limousine_pricing_resolver.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Authoritative scoped fleet record shape (as produced by _normalizeVehicleEntry).
const FLEET = [
  {
    vehicle_id: "vh_1",
    is_active: true,
    service_category: "limousine",
    service_class: "executive_sedan",
    passenger_capacity: 3,
    luggage_capacity: 2,
    color: "Black",
    public_photo_url: "https://cdn.example.com/v1.jpg",
    // Private fields that must never be published:
    license_plate: "1-ABC-123",
    vehicle_registration_number: "REG-9",
    exploitation_license_number: "EXP-7",
    assigned_driver: { driver_id: "drv_1", name: "Jan", phone: "+3211" },
    base_address: "Geheimestraat 1",
  },
  {
    vehicle_id: "vh_inactive",
    is_active: false,
    service_category: "limousine",
    service_class: "executive_sedan",
  },
  {
    vehicle_id: "vh_taxi",
    is_active: true,
    service_category: "",
    service_class: "",
  },
];

const CLASS_IDS = ["executive_sedan", "business_van"];

function fullyAuthoredOffer(overrides = {}) {
  return {
    offer_id: "off_full",
    enabled: true,
    published: true,
    target_type: LIMOUSINE_OFFER_TARGETS.VEHICLE,
    vehicle_id: "vh_1",
    service_class_id: "executive_sedan",
    price_presentation: LIMOUSINE_PRICE_PRESENTATIONS.EXACT_FIXED,
    currency: "EUR",
    journey_types: ["airport_transfer", "hourly_package"],
    title: { nl: "Executive", en: "Executive", fr: "Exécutive", es: "Ejecutiva" },
    description: { nl: "NL tekst", en: "EN text", fr: "FR texte", es: "ES texto" },
    important_information: { nl: "NL info", en: "EN info", fr: "FR info", es: "ES info" },
    fixed_rules: [
      {
        rule_id: "r_bru",
        enabled: true,
        journey_type: "airport_transfer",
        direction: "to_airport",
        airport_iata: "BRU",
        zone_type: "postcode",
        zone_value: "9000",
        amount_cents: 18000,
        vat_rate: 0.06,
        currency: "EUR",
        active_from_ms: 1,
        active_until_ms: 4102444800000,
      },
    ],
    hourly: {
      enabled: true,
      first_hour_cents: 12000,
      additional_hour_cents: 9000,
      minimum_duration_minutes: 180,
      maximum_duration_minutes: 600,
      included_hours: 3,
      package_duration_minutes: 240,
      package_amount_cents: 36000,
      excess_hour_cents: 9500,
      currency: "EUR",
    },
    distance_time: {
      enabled: true,
      base_incl_vat_cents: 5000,
      per_km_incl_vat_cents: 250,
      per_minute_incl_vat_cents: 120,
      minimum_incl_vat_cents: 9000,
      vat_rate: 0.06,
      currency: "EUR",
    },
    mobilisation: {
      method: "fixed_fee",
      outbound_charged: true,
      return_charged: false,
      included_distance_km: 15,
      included_minutes: 20,
      fee_cents: 4000,
      currency: "EUR",
      disclosure: { nl: "NL vrij", en: "EN disc", fr: "FR div", es: "ES div" },
      operating_base_address: "Geheimestraat 1, 9000 Gent",
    },
    included_services: [
      { item_id: "water", label: { nl: "Water", en: "Water", fr: "Eau", es: "Agua" }, active: true },
    ],
    paid_extras: [
      {
        extra_id: "wait",
        label: { nl: "Wachttijd", en: "Waiting", fr: "Attente", es: "Espera" },
        amount_cents: 2500,
        currency: "EUR",
        active: true,
        public: true,
      },
    ],
    source_revision: 4,
    ...overrides,
  };
}

const projOpts = { eligible: true, knownVehicles: FLEET, knownClassIds: CLASS_IDS, readiness: true };

test("1) complete fixed-rule authoring survives a normalization roundtrip", () => {
  const [normalized] = normalizeLimousineOffers([fullyAuthoredOffer()]);
  const rule = normalized.fixed_rules[0];
  assert.equal(rule.rule_id, "r_bru");
  assert.equal(rule.journey_type, "airport_transfer");
  assert.equal(rule.direction, "to_airport");
  assert.equal(rule.airport_iata, "BRU");
  assert.equal(rule.zone_type, "postcode");
  assert.equal(rule.zone_value, "9000");
  assert.equal(rule.amount_cents, 18000);
  assert.equal(rule.currency, "EUR");
  assert.equal(rule.active_until_ms, 4102444800000);
  // Second pass is stable.
  const [again] = normalizeLimousineOffers([normalized]);
  assert.deepEqual(again.fixed_rules[0], rule);
});

test("2) hourly/package authoring survives a roundtrip", () => {
  const [normalized] = normalizeLimousineOffers([fullyAuthoredOffer()]);
  const h = normalized.hourly;
  assert.equal(h.first_hour_cents, 12000);
  assert.equal(h.additional_hour_cents, 9000);
  assert.equal(h.minimum_duration_minutes, 180);
  assert.equal(h.maximum_duration_minutes, 600);
  assert.equal(h.included_hours, 3);
  assert.equal(h.package_duration_minutes, 240);
  assert.equal(h.package_amount_cents, 36000);
  assert.equal(h.excess_hour_cents, 9500);
  const dt = normalized.distance_time;
  assert.equal(dt.base_incl_vat_cents, 5000);
  assert.equal(dt.per_km_incl_vat_cents, 250);
  assert.equal(dt.minimum_incl_vat_cents, 9000);
  const m = normalized.mobilisation;
  assert.equal(m.fee_cents, 4000);
  assert.equal(m.included_distance_km, 15);
  assert.equal(m.included_minutes, 20);
});

test("4) NL/EN/FR/ES values survive independently", () => {
  const [normalized] = normalizeLimousineOffers([fullyAuthoredOffer()]);
  assert.deepEqual(normalized.title, {
    nl: "Executive",
    en: "Executive",
    fr: "Exécutive",
    es: "Ejecutiva",
  });
  assert.equal(normalized.description.nl, "NL tekst");
  assert.equal(normalized.description.fr, "FR texte");
  assert.equal(normalized.important_information.es, "ES info");
  // Editing one language must not overwrite the others.
  const edited = normalizeLimousineOffers([
    { ...fullyAuthoredOffer(), title: { ...fullyAuthoredOffer().title, fr: "Nouveau" } },
  ])[0];
  assert.equal(edited.title.fr, "Nouveau");
  assert.equal(edited.title.nl, "Executive");
  assert.equal(edited.title.es, "Ejecutiva");
});

test("6) vehicle fields come from the authoritative fleet record", () => {
  const safe = buildSafePublicLimousineOffers([fullyAuthoredOffer()], projOpts);
  assert.equal(safe.length, 1);
  const v = safe[0].vehicle;
  assert.equal(v.vehicle_id, "vh_1");
  assert.equal(v.service_class_id, "executive_sedan");
  assert.equal(v.passenger_capacity, 3);
  assert.equal(v.luggage_capacity, 2);
  assert.equal(v.color, "Black");
  assert.equal(v.photo_url, "https://cdn.example.com/v1.jpg");
  // Even if the offer claims another class, the fleet record wins.
  const lying = buildSafePublicLimousineOffers(
    [fullyAuthoredOffer({ service_class_id: "business_van" })],
    projOpts,
  );
  assert.equal(lying[0].service_class_id, "executive_sedan");
});

test("7) inactive / non-limousine / missing vehicle removes the public offer", () => {
  for (const vehicleId of ["vh_inactive", "vh_taxi", "vh_missing"]) {
    const safe = buildSafePublicLimousineOffers(
      [fullyAuthoredOffer({ vehicle_id: vehicleId })],
      projOpts,
    );
    assert.deepEqual(safe, [], vehicleId);
  }
  assert.equal(buildSafePublicVehicle(FLEET[1]), null);
  assert.equal(buildSafePublicVehicle(FLEET[2]), null);
  assert.equal(buildSafePublicVehicle({ vehicle_id: "x", is_active: true }), null);
});

test("8) plate / VIN / licences / driver / base address never appear publicly", () => {
  const safe = buildSafePublicLimousineOffers([fullyAuthoredOffer()], projOpts);
  const json = JSON.stringify(safe);
  for (const secret of [
    "1-ABC-123",
    "REG-9",
    "EXP-7",
    "drv_1",
    "Geheimestraat",
    "+3211",
  ]) {
    assert.ok(!json.includes(secret), `leaked: ${secret}`);
  }
  for (const key of LIMOUSINE_PRIVATE_VEHICLE_FIELDS) {
    assert.ok(!json.includes(`"${key}"`), `leaked key: ${key}`);
  }
  assert.ok(!json.includes("operating_base_address"));
});

test("9) the full safe offer array is published with all safe sections", () => {
  const [safe] = buildSafePublicLimousineOffers([fullyAuthoredOffer()], projOpts);
  for (const key of [
    "offer_id",
    "target_type",
    "vehicle",
    "service_class_id",
    "title",
    "description",
    "important_information",
    "pricing_modes",
    "price_presentation",
    "currency",
    "journey_types",
    "hourly",
    "included_services",
    "paid_extras",
    "mobilisation",
    "source_revision",
  ]) {
    assert.ok(safe[key] !== undefined, `missing ${key}`);
  }
  assert.equal(safe.hourly.minimum_duration_minutes, 180);
  assert.equal(safe.mobilisation.charged_separately, true);
  assert.equal(safe.source_revision, 4);
});

test("11) pricing mode and presentation are independent", () => {
  // Same offer content, different presentations => same computable modes.
  const modes = offerSupportedPricingModes(fullyAuthoredOffer());
  assert.deepEqual(modes.sort(), [
    LIMOUSINE_OFFER_PRICING_MODES.DISTANCE_TIME,
    LIMOUSINE_OFFER_PRICING_MODES.FIXED,
    LIMOUSINE_OFFER_PRICING_MODES.PACKAGE,
  ].sort());
  for (const presentation of Object.values(LIMOUSINE_PRICE_PRESENTATIONS)) {
    assert.deepEqual(
      offerSupportedPricingModes(fullyAuthoredOffer({ price_presentation: presentation })).sort(),
      modes.sort(),
      presentation,
    );
  }
  // An offer with no computable mode falls back to manual, whatever the token.
  assert.deepEqual(
    offerSupportedPricingModes(
      fullyAuthoredOffer({ fixed_rules: [], hourly: null, distance_time: null }),
    ),
    [LIMOUSINE_OFFER_PRICING_MODES.MANUAL],
  );
});

test("11b) an exact presentation resolves via hourly/package, not only fixed", () => {
  // Hourly journey, no matching fixed rule for that journey => package resolves.
  const offer = fullyAuthoredOffer({ fixed_rules: [] });
  const resolution = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: { enabled: true, currency: "EUR", source_revision: 1, offers: [offer] },
    request: {
      service_category: "limousine",
      service_class_id: "executive_sedan",
      vehicle_id: "vh_1",
      journey_type: "hourly_package",
      requested_duration_minutes: 240,
      currency: "EUR",
    },
    route: { distance_km: 30, duration_min: 45 },
  });
  assert.equal(resolution.resolved, true);
  assert.equal(resolution.pricing_mode, "hourly_or_package");
  assert.equal(resolution.price_incl_vat, 360); // package 36000 cents
});

test("12) from / indicative / quote-required never create accepted totals", () => {
  for (const presentation of [
    LIMOUSINE_PRICE_PRESENTATIONS.FROM_PRICE,
    LIMOUSINE_PRICE_PRESENTATIONS.INDICATIVE,
    LIMOUSINE_PRICE_PRESENTATIONS.QUOTE_REQUIRED,
  ]) {
    const offer = fullyAuthoredOffer({ price_presentation: presentation });
    assert.equal(offerCanProduceResolvedPrice(offer), false, presentation);
    const resolution = resolveLimousineQuote({
      gateEnabled: true,
      eligible: true,
      section: { enabled: true, currency: "EUR", source_revision: 1, offers: [offer] },
      request: {
        service_category: "limousine",
        service_class_id: "executive_sedan",
        vehicle_id: "vh_1",
        journey_type: "hourly_package",
        requested_duration_minutes: 240,
        currency: "EUR",
      },
      route: { distance_km: 30, duration_min: 45 },
    });
    assert.equal(resolution.resolved, false, presentation);
    assert.equal(resolution.price_incl_vat, undefined, presentation);
  }
});

test("5) exact vehicle offer still beats the class offer", () => {
  const classOnly = fullyAuthoredOffer({
    offer_id: "off_class",
    target_type: LIMOUSINE_OFFER_TARGETS.SERVICE_CLASS,
    vehicle_id: "",
  });
  const picked = selectLimousineOfferForRequest([classOnly, fullyAuthoredOffer()], {
    vehicleId: "vh_1",
    serviceClassId: "executive_sedan",
    journeyType: "airport_transfer",
  });
  assert.equal(picked.offer_id, "off_full");
});

test("10) unpublished / invalid offers are excluded", () => {
  assert.deepEqual(
    buildSafePublicLimousineOffers([fullyAuthoredOffer({ published: false })], projOpts),
    [],
  );
  // Hourly without a minimum duration is invalid => excluded.
  const invalid = fullyAuthoredOffer({
    hourly: { enabled: true, first_hour_cents: 12000, additional_hour_cents: 9000, currency: "EUR" },
  });
  assert.deepEqual(buildSafePublicLimousineOffers([invalid], projOpts), []);
});

test("15) legacy pricing:v1 limousine records remain readable", () => {
  // A P2B1-era section (classes only, no offers) still parses and keeps classes.
  const legacy = normalizeLimousinePricingSection({
    enabled: true,
    currency: "EUR",
    source_revision: 2,
    classes: [
      {
        service_class_id: "executive_sedan",
        enabled: true,
        currency: "EUR",
        distance_time: {
          enabled: true,
          base_incl_vat_cents: 5000,
          per_km_incl_vat_cents: 200,
          per_minute_incl_vat_cents: 100,
          minimum_incl_vat_cents: 8000,
          vat_rate: 0.06,
          currency: "EUR",
        },
      },
    ],
  });
  assert.equal(legacy.classes.length, 1);
  assert.deepEqual(legacy.offers, []);
  // And it still resolves through the class path.
  const resolution = resolveLimousineQuote({
    gateEnabled: true,
    eligible: true,
    section: legacy,
    request: {
      service_category: "limousine",
      service_class_id: "executive_sedan",
      journey_type: "point_to_point",
      currency: "EUR",
    },
    route: { distance_km: 20, duration_min: 30 },
  });
  assert.equal(resolution.resolved, true);
  assert.equal(resolution.pricing_mode, "limousine_distance_time");
});

test("13/14/16) worker preserves taxi + airport data and publishes offers", () => {
  const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");
  // Taxi profile save preserves the limousine section.
  assert.ok(worker.includes("normalized.limousine = preservedLimousine"));
  // The limousine endpoint merges over the raw record (taxi + airport untouched).
  assert.ok(worker.includes("const mergedProfile = { ...rawProfile, limousine: nextSection };"));
  // Airport fixed fares live in their own store and are not written here.
  assert.ok(!/\/admin\/pricing\/limousine[\s\S]{0,4000}airport_fixed_fares/.test(worker));
  // Monotonic revision on the limousine section.
  assert.ok(worker.includes("stale_source_revision"));
  assert.ok(worker.includes("nextSection.source_revision = existingSection.source_revision + 1;"));
  // Full safe offer array is published from authoritative state.
  assert.ok(worker.includes("_buildAuthoritativeLimousinePublicOffers"));
  assert.ok(worker.includes("limousine_offers: _limousinePublicOffers"));
  // Server does not trust Flutter-submitted public vehicle fields for the join.
  assert.ok(worker.includes("_normalizeVehicleEntry(entry, { scope })"));
});
