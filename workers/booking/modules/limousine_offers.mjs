// LIMOUSINE-MARKETPLACE-P2B2 — company Limousine offers: normalization,
// validation, target precedence and the SAFE public projection.
//
// An "offer" is the commercial unit a limousine company actually sells:
//   * an exact vehicle, or an authoritative service class;
//   * a price presentation (exact / from / indicative / quote / unavailable);
//   * optional fixed journeys, hourly hire, or limousine distance/time;
//   * mobilisation (operating base -> pickup -> itinerary -> base);
//   * included services and separately priced extras.
//
// Hard rules:
//   * only `exact_fixed` may ever become a resolved, bookable price;
//   * `from_price` / `indicative` are marketing only and never enter a snapshot;
//   * `quote_required` never invents a total;
//   * an exact vehicle offer overrides a service-class offer;
//   * the private operating-base address is NEVER projected publicly;
//   * missing / contradictory configuration fails closed.
//
// All money is integer minor units (cents). No floats are monetary authority.

import { normalizeLimousineToken } from "./limousine_provider_eligibility.mjs";

export const LIMOUSINE_PRICE_PRESENTATIONS = Object.freeze({
  EXACT_FIXED: "exact_fixed",
  FROM_PRICE: "from_price",
  INDICATIVE: "indicative",
  QUOTE_REQUIRED: "quote_required",
  UNAVAILABLE: "unavailable",
});

const PRESENTATION_SET = new Set(Object.values(LIMOUSINE_PRICE_PRESENTATIONS));

export const LIMOUSINE_OFFER_TARGETS = Object.freeze({
  VEHICLE: "vehicle",
  SERVICE_CLASS: "service_class",
});

export const LIMOUSINE_MOBILISATION_METHODS = Object.freeze({
  INCLUDED: "included",
  FIXED_FEE: "fixed_fee",
  DISTANCE_TIME: "distance_time",
});

export const LIMOUSINE_OFFER_ERRORS = Object.freeze({
  MISSING_OFFER_ID: "missing_offer_id",
  UNKNOWN_TARGET: "unknown_target",
  UNKNOWN_VEHICLE: "unknown_vehicle",
  INACTIVE_VEHICLE: "inactive_vehicle",
  VEHICLE_NOT_LIMOUSINE: "vehicle_not_limousine",
  UNKNOWN_SERVICE_CLASS: "unknown_service_class",
  MISSING_CURRENCY: "missing_currency",
  CURRENCY_CONFLICT: "currency_conflict",
  NEGATIVE_AMOUNT: "negative_amount",
  INVALID_PRESENTATION: "invalid_presentation",
  MISSING_DISPLAY_AMOUNT: "missing_display_amount",
  INCOMPLETE_FIXED_RULE: "incomplete_fixed_rule",
  DUPLICATE_RULE: "duplicate_rule",
  HOURLY_MISSING_MINIMUM_DURATION: "hourly_missing_minimum_duration",
  HOURLY_INCOMPLETE: "hourly_incomplete",
  PACKAGE_INCOMPLETE: "package_incomplete",
  MOBILISATION_INCOMPLETE: "mobilisation_incomplete",
  MOBILISATION_CONTRADICTORY: "mobilisation_contradictory",
  PUBLISHED_WITHOUT_READINESS: "published_without_readiness",
  DISTANCE_TIME_INCOMPLETE: "distance_time_incomplete",
});

const ISO_CURRENCY = /^[A-Z]{3}$/;
const LANGS = ["nl", "en", "fr", "es"];

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function toInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.trunc(n);
}

/// Integer cents. Returns null for missing/invalid; negatives are preserved as
/// negative so validation can reject them explicitly (never silently clamped).
function toCents(value) {
  if (value == null || value === "") return null;
  return toInt(value);
}

function toBool(value, fallback = false) {
  if (value === true) return true;
  if (value === false) return false;
  const t = normalizeLimousineToken(value);
  if (t === "true" || t === "1" || t === "yes" || t === "on") return true;
  if (t === "false" || t === "0" || t === "no" || t === "off") return false;
  return fallback;
}

function normalizeCurrency(value) {
  const c = String(value ?? "").trim().toUpperCase();
  return ISO_CURRENCY.test(c) ? c : "";
}

function normalizeId(value, { max = 64 } = {}) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_:\-.]/g, "")
    .slice(0, max);
}

export function normalizeLocalizedText(raw, { max = 400 } = {}) {
  const src = asObject(raw);
  const out = {};
  for (const lang of LANGS) {
    out[lang] = String(src[lang] ?? "").trim().slice(0, max);
  }
  return out;
}

function localizedIsEmpty(text) {
  return LANGS.every((l) => !String(text?.[l] ?? "").trim());
}

function normalizeJourneyType(value) {
  const t = normalizeLimousineToken(value);
  switch (t) {
    case "point_to_point":
    case "pointtopoint":
    case "p2p":
      return "point_to_point";
    case "airport":
    case "airport_transfer":
      return "airport_transfer";
    case "hotel":
    case "hotel_transfer":
      return "hotel_transfer";
    case "event":
    case "event_transfer":
      return "event_transfer";
    case "hourly":
    case "hourly_package":
    case "package":
      return "hourly_package";
    default:
      return "";
  }
}

function normalizeDirection(value) {
  const t = normalizeLimousineToken(value);
  return t === "to_airport" || t === "from_airport" || t === "both" ? t : "";
}

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

export function normalizeOfferFixedRule(raw) {
  const src = asObject(raw);
  return {
    rule_id: normalizeId(src.rule_id ?? src.ruleId),
    enabled: toBool(src.enabled, false),
    journey_type: normalizeJourneyType(src.journey_type ?? src.journeyType),
    direction: normalizeDirection(src.direction),
    airport_iata: String(src.airport_iata ?? src.airportIata ?? "").trim().toUpperCase(),
    zone_type: normalizeLimousineToken(src.zone_type ?? src.zoneType) || "none",
    zone_value: String(src.zone_value ?? src.zoneValue ?? "").trim().toUpperCase(),
    zone_center_lat: Number(src.zone_center_lat ?? src.zoneCenterLat),
    zone_center_lng: Number(src.zone_center_lng ?? src.zoneCenterLng),
    radius_km: Number(src.radius_km ?? src.radiusKm),
    amount_cents: toCents(src.amount_cents ?? src.amountCents),
    vat_rate: Number(src.vat_rate ?? src.vatRate) || 0,
    currency: normalizeCurrency(src.currency),
    active_from_ms: toInt(src.active_from_ms ?? src.activeFromMs),
    active_until_ms: toInt(src.active_until_ms ?? src.activeUntilMs),
  };
}

export function normalizeOfferHourly(raw) {
  const src = asObject(raw);
  if (Object.keys(src).length === 0) return null;
  return {
    enabled: toBool(src.enabled, false),
    first_hour_cents: toCents(src.first_hour_cents ?? src.firstHourCents),
    additional_hour_cents: toCents(src.additional_hour_cents ?? src.additionalHourCents),
    minimum_duration_minutes: toInt(src.minimum_duration_minutes ?? src.minimumDurationMinutes),
    included_hours: toInt(src.included_hours ?? src.includedHours),
    package_duration_minutes: toInt(src.package_duration_minutes ?? src.packageDurationMinutes),
    package_amount_cents: toCents(src.package_amount_cents ?? src.packageAmountCents),
    maximum_duration_minutes: toInt(src.maximum_duration_minutes ?? src.maximumDurationMinutes),
    excess_hour_cents: toCents(src.excess_hour_cents ?? src.excessHourCents),
    currency: normalizeCurrency(src.currency),
  };
}

export function normalizeOfferDistanceTime(raw) {
  const src = asObject(raw);
  if (Object.keys(src).length === 0) return null;
  return {
    enabled: toBool(src.enabled, false),
    base_incl_vat_cents: toCents(src.base_incl_vat_cents ?? src.baseInclVatCents),
    per_km_incl_vat_cents: toCents(src.per_km_incl_vat_cents ?? src.perKmInclVatCents),
    per_minute_incl_vat_cents: toCents(src.per_minute_incl_vat_cents ?? src.perMinuteInclVatCents),
    minimum_incl_vat_cents: toCents(src.minimum_incl_vat_cents ?? src.minimumInclVatCents),
    vat_rate: Number(src.vat_rate ?? src.vatRate) || 0,
    currency: normalizeCurrency(src.currency),
  };
}

/// Mobilisation. `operating_base_*` is PRIVATE operational data and is kept out
/// of every public projection.
export function normalizeOfferMobilisation(raw) {
  const src = asObject(raw);
  if (Object.keys(src).length === 0) return null;
  const method = normalizeLimousineToken(src.method) || "included";
  return {
    method: Object.values(LIMOUSINE_MOBILISATION_METHODS).includes(method) ? method : "",
    outbound_charged: toBool(src.outbound_charged ?? src.outboundCharged, false),
    return_charged: toBool(src.return_charged ?? src.returnCharged, false),
    included_distance_km: Number(src.included_distance_km ?? src.includedDistanceKm) || 0,
    included_minutes: toInt(src.included_minutes ?? src.includedMinutes) ?? 0,
    fee_cents: toCents(src.fee_cents ?? src.feeCents),
    currency: normalizeCurrency(src.currency),
    disclosure: normalizeLocalizedText(src.disclosure, { max: 240 }),
    // PRIVATE — never projected publicly.
    operating_base_address: String(src.operating_base_address ?? src.operatingBaseAddress ?? "")
      .trim()
      .slice(0, 240),
  };
}

export function normalizeIncludedService(raw) {
  const src = asObject(raw);
  return {
    item_id: normalizeId(src.item_id ?? src.itemId),
    label: normalizeLocalizedText(src.label, { max: 120 }),
    active: toBool(src.active, true),
  };
}

export function normalizePaidExtra(raw) {
  const src = asObject(raw);
  return {
    extra_id: normalizeId(src.extra_id ?? src.extraId),
    label: normalizeLocalizedText(src.label, { max: 120 }),
    amount_cents: toCents(src.amount_cents ?? src.amountCents),
    quote_required: toBool(src.quote_required ?? src.quoteRequired, false),
    currency: normalizeCurrency(src.currency),
    active: toBool(src.active, true),
    public: toBool(src.public, true),
  };
}

export function normalizeLimousineOffer(raw) {
  const src = asObject(raw);
  const targetType = normalizeLimousineToken(src.target_type ?? src.targetType);
  const presentation = normalizeLimousineToken(src.price_presentation ?? src.pricePresentation);
  const journeyTypes = Array.isArray(src.journey_types ?? src.journeyTypes)
    ? Array.from(
        new Set(
          (src.journey_types ?? src.journeyTypes)
            .map(normalizeJourneyType)
            .filter((t) => t),
        ),
      )
    : [];
  return {
    offer_id: normalizeId(src.offer_id ?? src.offerId),
    enabled: toBool(src.enabled, false),
    published: toBool(src.published, false),
    target_type: Object.values(LIMOUSINE_OFFER_TARGETS).includes(targetType) ? targetType : "",
    vehicle_id: String(src.vehicle_id ?? src.vehicleId ?? "").trim(),
    service_class_id: normalizeId(src.service_class_id ?? src.serviceClassId),
    price_presentation: PRESENTATION_SET.has(presentation) ? presentation : "",
    currency: normalizeCurrency(src.currency),
    journey_types: journeyTypes,
    title: normalizeLocalizedText(src.title, { max: 120 }),
    description: normalizeLocalizedText(src.description, { max: 600 }),
    important_information: normalizeLocalizedText(
      src.important_information ?? src.importantInformation,
      { max: 600 },
    ),
    display_amount_cents: toCents(src.display_amount_cents ?? src.displayAmountCents),
    fixed_rules: Array.isArray(src.fixed_rules ?? src.fixedRules)
      ? (src.fixed_rules ?? src.fixedRules).map(normalizeOfferFixedRule)
      : [],
    hourly: normalizeOfferHourly(src.hourly),
    distance_time: normalizeOfferDistanceTime(src.distance_time ?? src.distanceTime),
    mobilisation: normalizeOfferMobilisation(src.mobilisation),
    included_services: Array.isArray(src.included_services ?? src.includedServices)
      ? (src.included_services ?? src.includedServices).map(normalizeIncludedService)
      : [],
    paid_extras: Array.isArray(src.paid_extras ?? src.paidExtras)
      ? (src.paid_extras ?? src.paidExtras).map(normalizePaidExtra)
      : [],
    source_revision: toInt(src.source_revision ?? src.sourceRevision) ?? 0,
  };
}

export function normalizeLimousineOffers(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map(normalizeLimousineOffer).filter((o) => o.offer_id);
}

// ---------------------------------------------------------------------------
// Validation (fail closed)
// ---------------------------------------------------------------------------

function fixedRuleComplete(rule) {
  if (!rule.rule_id) return false;
  if (!rule.journey_type) return false;
  if (rule.amount_cents == null || rule.amount_cents <= 0) return false;
  if (!rule.currency) return false;
  if (rule.journey_type === "airport_transfer" && !rule.airport_iata) return false;
  if (rule.zone_type === "radius") {
    if (!Number.isFinite(rule.zone_center_lat) || !Number.isFinite(rule.zone_center_lng)) {
      return false;
    }
    if (!Number.isFinite(rule.radius_km) || rule.radius_km <= 0) return false;
  }
  if (rule.zone_type === "postcode" || rule.zone_type === "city" || rule.zone_type === "country") {
    if (!rule.zone_value) return false;
  }
  return true;
}

function hourlyComplete(hourly) {
  if (!hourly || !hourly.enabled) return true; // not configured => not incomplete
  if (hourly.first_hour_cents == null || hourly.first_hour_cents <= 0) return false;
  if (hourly.additional_hour_cents == null || hourly.additional_hour_cents < 0) return false;
  return true;
}

function distanceTimeComplete(dt) {
  if (!dt || !dt.enabled) return true;
  for (const key of [
    "base_incl_vat_cents",
    "per_km_incl_vat_cents",
    "per_minute_incl_vat_cents",
    "minimum_incl_vat_cents",
  ]) {
    if (dt[key] == null) return false;
  }
  return !!dt.currency;
}

function collectNegativeAmounts(offer) {
  const values = [offer.display_amount_cents];
  for (const rule of offer.fixed_rules) values.push(rule.amount_cents);
  if (offer.hourly) {
    values.push(
      offer.hourly.first_hour_cents,
      offer.hourly.additional_hour_cents,
      offer.hourly.package_amount_cents,
      offer.hourly.excess_hour_cents,
    );
  }
  if (offer.distance_time) {
    values.push(
      offer.distance_time.base_incl_vat_cents,
      offer.distance_time.per_km_incl_vat_cents,
      offer.distance_time.per_minute_incl_vat_cents,
      offer.distance_time.minimum_incl_vat_cents,
    );
  }
  if (offer.mobilisation) values.push(offer.mobilisation.fee_cents);
  for (const extra of offer.paid_extras) values.push(extra.amount_cents);
  return values.filter((v) => v != null && v < 0);
}

/// Validates one offer. `knownVehicles` is a list of
/// `{ id, is_active, service_category, service_class_id }`; `knownClassIds` is
/// the authoritative active class-id set. `readiness` is the company's
/// entitlement/readiness flag used to block publishing.
export function validateLimousineOffer(
  offer,
  { knownVehicles = [], knownClassIds = [], readiness = false } = {},
) {
  const E = LIMOUSINE_OFFER_ERRORS;
  const o = normalizeLimousineOffer(offer);
  const errors = [];

  if (!o.offer_id) errors.push(E.MISSING_OFFER_ID);
  if (!o.target_type) errors.push(E.UNKNOWN_TARGET);
  if (!o.price_presentation) errors.push(E.INVALID_PRESENTATION);
  if (!o.currency) errors.push(E.MISSING_CURRENCY);

  const classIds = new Set(knownClassIds.map((c) => normalizeId(c)));

  if (o.target_type === LIMOUSINE_OFFER_TARGETS.VEHICLE) {
    // Accept both the local model shape (`id`) and the authoritative scoped
    // fleet record shape (`vehicle_id` / `service_class`).
    const vehicle = knownVehicles.find(
      (v) => String(v?.vehicle_id ?? v?.id ?? "").trim() === o.vehicle_id,
    );
    if (!o.vehicle_id || !vehicle) {
      errors.push(E.UNKNOWN_VEHICLE);
    } else {
      if (vehicle.is_active === false || vehicle.isActive === false) {
        errors.push(E.INACTIVE_VEHICLE);
      }
      if (
        normalizeLimousineToken(vehicle.service_category ?? vehicle.serviceCategory) !==
        "limousine"
      ) {
        errors.push(E.VEHICLE_NOT_LIMOUSINE);
      }
      const vehicleClassId = normalizeId(
        vehicle.service_class_id ?? vehicle.service_class ?? vehicle.serviceClassId,
      );
      if (!classIds.has(vehicleClassId)) errors.push(E.UNKNOWN_SERVICE_CLASS);
    }
  } else if (o.target_type === LIMOUSINE_OFFER_TARGETS.SERVICE_CLASS) {
    if (!classIds.has(o.service_class_id)) errors.push(E.UNKNOWN_SERVICE_CLASS);
  }

  if (collectNegativeAmounts(o).length > 0) errors.push(E.NEGATIVE_AMOUNT);

  // Currency consistency across every priced element.
  const currencies = new Set();
  if (o.currency) currencies.add(o.currency);
  for (const rule of o.fixed_rules) if (rule.currency) currencies.add(rule.currency);
  if (o.hourly?.currency) currencies.add(o.hourly.currency);
  if (o.distance_time?.currency) currencies.add(o.distance_time.currency);
  if (o.mobilisation?.currency) currencies.add(o.mobilisation.currency);
  for (const extra of o.paid_extras) if (extra.currency) currencies.add(extra.currency);
  if (currencies.size > 1) errors.push(E.CURRENCY_CONFLICT);

  // exact_fixed requires at least one complete matching rule OR a complete
  // hourly/distance-time configuration to be able to resolve.
  if (o.price_presentation === LIMOUSINE_PRICE_PRESENTATIONS.EXACT_FIXED) {
    const enabledRules = o.fixed_rules.filter((r) => r.enabled);
    const hasCompleteRule = enabledRules.length > 0 && enabledRules.every(fixedRuleComplete);
    const hasHourly = !!o.hourly?.enabled;
    const hasDt = !!o.distance_time?.enabled;
    if (enabledRules.length > 0 && !hasCompleteRule) errors.push(E.INCOMPLETE_FIXED_RULE);
    if (enabledRules.length === 0 && !hasHourly && !hasDt) {
      errors.push(E.INCOMPLETE_FIXED_RULE);
    }
  }

  // from_price / indicative are marketing; they need a display amount.
  if (
    o.price_presentation === LIMOUSINE_PRICE_PRESENTATIONS.FROM_PRICE ||
    o.price_presentation === LIMOUSINE_PRICE_PRESENTATIONS.INDICATIVE
  ) {
    if (o.display_amount_cents == null || o.display_amount_cents <= 0) {
      errors.push(E.MISSING_DISPLAY_AMOUNT);
    }
  }

  // Duplicate / ambiguous fixed rules.
  const ruleIds = o.fixed_rules.map((r) => r.rule_id).filter((id) => id);
  if (new Set(ruleIds).size !== ruleIds.length) errors.push(E.DUPLICATE_RULE);

  // Hourly hire.
  if (o.hourly?.enabled) {
    if (!hourlyComplete(o.hourly)) errors.push(E.HOURLY_INCOMPLETE);
    if (o.hourly.minimum_duration_minutes == null || o.hourly.minimum_duration_minutes <= 0) {
      errors.push(E.HOURLY_MISSING_MINIMUM_DURATION);
    }
    const hasPackageAmount = o.hourly.package_amount_cents != null;
    const hasPackageDuration =
      o.hourly.package_duration_minutes != null && o.hourly.package_duration_minutes > 0;
    if (hasPackageAmount !== hasPackageDuration) errors.push(E.PACKAGE_INCOMPLETE);
  }

  if (!distanceTimeComplete(o.distance_time)) errors.push(E.DISTANCE_TIME_INCOMPLETE);

  // Mobilisation.
  if (o.mobilisation) {
    const m = o.mobilisation;
    const charged = m.outbound_charged || m.return_charged;
    if (!m.method) {
      errors.push(E.MOBILISATION_INCOMPLETE);
    } else if (charged && m.method === LIMOUSINE_MOBILISATION_METHODS.INCLUDED) {
      errors.push(E.MOBILISATION_CONTRADICTORY);
    } else if (charged && m.method === LIMOUSINE_MOBILISATION_METHODS.FIXED_FEE) {
      if (m.fee_cents == null || m.fee_cents <= 0 || !m.currency) {
        errors.push(E.MOBILISATION_INCOMPLETE);
      }
    } else if (charged && m.method === LIMOUSINE_MOBILISATION_METHODS.DISTANCE_TIME) {
      if (!o.distance_time?.enabled || !distanceTimeComplete(o.distance_time)) {
        errors.push(E.MOBILISATION_INCOMPLETE);
      }
    }
  }

  // Publishing requires company readiness/entitlement.
  if (o.published && !readiness) errors.push(E.PUBLISHED_WITHOUT_READINESS);

  return { valid: errors.length === 0, errors: Array.from(new Set(errors)), offer: o };
}

// ---------------------------------------------------------------------------
// Target precedence
// ---------------------------------------------------------------------------

/// An exact vehicle offer overrides a service-class offer when both match.
/// Returns the winning offer or null. Only enabled offers participate.
export function selectLimousineOfferForRequest(
  offers,
  { vehicleId = "", serviceClassId = "", journeyType = "" } = {},
) {
  const list = normalizeLimousineOffers(offers).filter((o) => o.enabled);
  const wantedClass = normalizeId(serviceClassId);
  const wantedVehicle = String(vehicleId ?? "").trim();
  const wantedJourney = normalizeJourneyType(journeyType);

  const journeyOk = (offer) =>
    !wantedJourney ||
    offer.journey_types.length === 0 ||
    offer.journey_types.includes(wantedJourney);

  if (wantedVehicle) {
    const vehicleOffer = list.find(
      (o) =>
        o.target_type === LIMOUSINE_OFFER_TARGETS.VEHICLE &&
        o.vehicle_id === wantedVehicle &&
        journeyOk(o),
    );
    if (vehicleOffer) return vehicleOffer;
  }
  if (wantedClass) {
    const classOffer = list.find(
      (o) =>
        o.target_type === LIMOUSINE_OFFER_TARGETS.SERVICE_CLASS &&
        o.service_class_id === wantedClass &&
        journeyOk(o),
    );
    if (classOffer) return classOffer;
  }
  return null;
}

/// PRICING MODE vs PRESENTATION are independent axes.
///
/// `pricing_mode` describes HOW a total is computed (fixed journey, hourly /
/// package, limousine distance-time, or manual). `price_presentation`
/// describes WHAT the customer is shown (an exact bookable price, a "from"
/// price, an indicative price, quote required, or unavailable).
///
/// An `exact_fixed` presentation may therefore be produced by a fixed rule, an
/// hourly/package calculation OR a distance/time calculation — the token name
/// is historical and must never restrict resolution to fixed journeys only.
export const LIMOUSINE_OFFER_PRICING_MODES = Object.freeze({
  FIXED: "fixed",
  PACKAGE: "package",
  DISTANCE_TIME: "distance_time",
  MANUAL: "manual",
});

/// Every pricing mode this offer can actually compute with, independent of how
/// the price is presented.
export function offerSupportedPricingModes(offer) {
  const o = normalizeLimousineOffer(offer);
  const modes = [];
  if (o.fixed_rules.some((r) => r.enabled)) modes.push(LIMOUSINE_OFFER_PRICING_MODES.FIXED);
  if (o.hourly?.enabled) modes.push(LIMOUSINE_OFFER_PRICING_MODES.PACKAGE);
  if (o.distance_time?.enabled) modes.push(LIMOUSINE_OFFER_PRICING_MODES.DISTANCE_TIME);
  if (modes.length === 0) modes.push(LIMOUSINE_OFFER_PRICING_MODES.MANUAL);
  return modes;
}

/// Only an "exact" presentation may become a resolved, bookable total — but it
/// may be produced by ANY pricing mode (fixed, package or distance/time).
export function offerCanProduceResolvedPrice(offer) {
  const o = normalizeLimousineOffer(offer);
  return o.price_presentation === LIMOUSINE_PRICE_PRESENTATIONS.EXACT_FIXED;
}

/// `from_price` and `indicative` are marketing-only and must never be written
/// into an accepted-price snapshot.
export function offerAmountIsSnapshotEligible(offer) {
  return offerCanProduceResolvedPrice(offer);
}

// ---------------------------------------------------------------------------
// Safe public projection
// ---------------------------------------------------------------------------

/// Fields that must NEVER leave the authoritative vehicle record. Kept as an
/// explicit deny-list so a future field addition cannot silently leak.
export const LIMOUSINE_PRIVATE_VEHICLE_FIELDS = Object.freeze([
  "license_plate",
  "licensePlate",
  "vin",
  "vehicle_registration_number",
  "vehicleRegistrationNumber",
  "exploitation_license_number",
  "exploitationLicenseNumber",
  "assigned_driver",
  "assigned_driver_id",
  "driver_id",
  "driverId",
  "notes",
  "internal_notes",
  "base_address",
  "current_address",
]);

/// Builds the customer-safe vehicle block from the AUTHORITATIVE scoped fleet
/// record. Returns null when the vehicle is missing, inactive or not an
/// explicitly classified limousine (fail closed). Never reads Flutter-submitted
/// public vehicle fields and never emits a private field.
export function buildSafePublicVehicle(vehicle) {
  const v = asObject(vehicle);
  const id = String(v.vehicle_id ?? v.id ?? "").trim();
  if (!id) return null;
  if (v.is_active === false || v.isActive === false) return null;
  for (const key of ["deleted", "is_deleted", "tombstoned", "suspended"]) {
    if (toBool(v[key], false)) return null;
  }
  if (normalizeLimousineToken(v.service_category ?? v.serviceCategory) !== "limousine") {
    return null;
  }
  const serviceClassId = normalizeId(
    v.service_class ?? v.serviceClass ?? v.service_class_id ?? v.serviceClassId,
  );
  if (!serviceClassId) return null;
  const pax = toInt(v.passenger_capacity ?? v.passengerCapacity ?? v.pax);
  const luggage = toInt(v.luggage_capacity ?? v.luggageCapacity ?? v.luggage);
  const color = String(v.color ?? "").trim().slice(0, 40);
  const photoUrl = String(v.public_photo_url ?? v.publicPhotoUrl ?? "").trim();
  const safePhoto = /^https:\/\//i.test(photoUrl) ? photoUrl.slice(0, 600) : "";
  return {
    vehicle_id: id,
    service_class_id: serviceClassId,
    ...(pax != null && pax > 0 ? { passenger_capacity: pax } : {}),
    ...(luggage != null && luggage > 0 ? { luggage_capacity: luggage } : {}),
    ...(color ? { color } : {}),
    ...(safePhoto ? { photo_url: safePhoto } : {}),
  };
}

function safePublicMobilisation(mobilisation) {
  if (!mobilisation) return null;
  const charged = mobilisation.outbound_charged || mobilisation.return_charged;
  // Only a safe statement — never the private operating-base address.
  return {
    included: !charged && mobilisation.method === LIMOUSINE_MOBILISATION_METHODS.INCLUDED,
    charged_separately: !!charged,
    disclosure: mobilisation.disclosure,
  };
}

/// Projects ONLY customer-safe, published and eligible offers. Excludes the
/// private operating-base address, internal costs, unpublished rules and raw
/// pricing records. Fails closed to an empty list.
export function buildSafePublicLimousineOffers(
  offers,
  { eligible = false, knownVehicles = [], knownClassIds = [], readiness = false } = {},
) {
  if (!eligible) return [];
  const normalized = normalizeLimousineOffers(offers);
  const out = [];
  for (const offer of normalized) {
    if (!offer.enabled || !offer.published) continue;
    const { valid } = validateLimousineOffer(offer, {
      knownVehicles,
      knownClassIds,
      readiness,
    });
    if (!valid) continue;
    if (offer.price_presentation === LIMOUSINE_PRICE_PRESENTATIONS.UNAVAILABLE) continue;

    // Authoritative vehicle join: an exact-vehicle offer only publishes when the
    // scoped fleet record still resolves to an active, classified limousine.
    let safeVehicle = null;
    if (offer.target_type === LIMOUSINE_OFFER_TARGETS.VEHICLE) {
      const record = knownVehicles.find(
        (v) => String(v?.vehicle_id ?? v?.id ?? "").trim() === offer.vehicle_id,
      );
      safeVehicle = buildSafePublicVehicle(record);
      if (!safeVehicle) continue;
    }

    const showsAmount =
      offer.price_presentation !== LIMOUSINE_PRICE_PRESENTATIONS.QUOTE_REQUIRED &&
      offer.display_amount_cents != null &&
      offer.display_amount_cents > 0;

    out.push({
      offer_id: offer.offer_id,
      target_type: offer.target_type,
      ...(safeVehicle ? { vehicle: safeVehicle, vehicle_id: safeVehicle.vehicle_id } : {}),
      service_class_id: safeVehicle
        ? safeVehicle.service_class_id
        : offer.service_class_id,
      title: offer.title,
      description: offer.description,
      ...(localizedIsEmpty(offer.important_information)
        ? {}
        : { important_information: offer.important_information }),
      pricing_modes: offerSupportedPricingModes(offer),
      price_presentation: offer.price_presentation,
      ...(showsAmount ? { display_amount_cents: offer.display_amount_cents } : {}),
      currency: offer.currency,
      journey_types: offer.journey_types,
      ...(offer.hourly?.enabled
        ? {
            hourly: {
              first_hour_cents: offer.hourly.first_hour_cents,
              additional_hour_cents: offer.hourly.additional_hour_cents,
              minimum_duration_minutes: offer.hourly.minimum_duration_minutes,
              ...(offer.hourly.included_hours != null
                ? { included_hours: offer.hourly.included_hours }
                : {}),
            },
          }
        : {}),
      included_services: offer.included_services
        .filter((s) => s.active && !localizedIsEmpty(s.label))
        .map((s) => ({ item_id: s.item_id, label: s.label })),
      paid_extras: offer.paid_extras
        .filter((e) => e.active && e.public && !localizedIsEmpty(e.label))
        .map((e) => ({
          extra_id: e.extra_id,
          label: e.label,
          quote_required: e.quote_required,
          ...(e.quote_required || e.amount_cents == null
            ? {}
            : { amount_cents: e.amount_cents }),
          currency: e.currency,
        })),
      mobilisation: safePublicMobilisation(offer.mobilisation),
      source_revision: offer.source_revision,
    });
  }
  return out;
}

/// Monotonic guard: an older revision may never overwrite newer configuration.
export function limousineOffersRevisionAccepts({ currentRevision, incomingRevision } = {}) {
  const cur = toInt(currentRevision) ?? 0;
  const next = toInt(incomingRevision) ?? 0;
  return next > cur;
}
