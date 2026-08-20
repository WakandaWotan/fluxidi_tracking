// LIMOUSINE-MARKETPLACE-P2B1 — authoritative Limousine pricing storage + shared
// quote resolution. Pure, dependency-light, fully testable.
//
// Resolution hierarchy (never falls back to taxi pricing):
//   1. Matching Limousine fixed route/airport fare
//   2. Matching Limousine hourly/package fare
//   3. Limousine-specific distance/time calculation (server route only)
//   4. Manual quote
//   5. Unavailable
//
// Storage lives INSIDE the existing company pricing record (`pricing:v1`) under
// an optional `limousine` section. It is completely separate from the taxi
// pricing profile and the airport fixed-fare store, so:
//   * legacy taxi/airport rules never match Limousine;
//   * Limousine rules never match taxi/airport;
//   * the same airport/direction can carry distinct taxi and Limousine rules.
//
// All money is integer minor units (cents). Rounding reuses the shared €0.10
// half-up leg finalizer so Limousine matches the platform's rounding policy.

import { finalizeLegPricingInclVat } from "./leg_pricing_finalize.mjs";
import {
  isForbiddenClassInferenceToken,
  isLimousineServiceToken,
  normalizeLimousineToken,
} from "./limousine_provider_eligibility.mjs";
import {
  LIMOUSINE_PRICE_PRESENTATIONS,
  normalizeLimousineOffers,
  normalizeLocalizedText,
  selectLimousineOfferForRequest,
} from "./limousine_offers.mjs";
import {
  mergePublishedLimousineIdentity,
  normalizePublishedLimousineIdentity,
} from "./limousine_published_identity.mjs";

export const LIMOUSINE_PRICING_REASONS = Object.freeze({
  RESOLVED: "resolved",
  GATE_OFF: "gate_off",
  NOT_ELIGIBLE: "not_eligible",
  MISSING_CLASS: "missing_class",
  UNKNOWN_CLASS: "unknown_class",
  SECTION_DISABLED: "section_disabled",
  CLASS_DISABLED: "class_disabled",
  CURRENCY_MISMATCH: "currency_mismatch",
  UNSUPPORTED_JOURNEY_TYPE: "unsupported_journey_type",
  INCOMPLETE_FIXED_RULE: "incomplete_fixed_rule",
  AMBIGUOUS_FIXED_RULE: "ambiguous_fixed_rule",
  INCOMPLETE_PACKAGE: "incomplete_package",
  INCOMPLETE_DISTANCE_TIME: "incomplete_distance_time",
  ROUTE_FAILED: "route_failed",
  STALE_REVISION: "stale_revision",
  MANUAL_QUOTE: "manual_quote",
  UNAVAILABLE: "unavailable",
});

export const LIMOUSINE_PRICING_MODES = Object.freeze({
  FIXED: "fixed_route_or_airport_fare",
  PACKAGE: "hourly_or_package",
  DISTANCE_TIME: "limousine_distance_time",
});

const SUPPORTED_JOURNEY_TYPES = new Set([
  "point_to_point",
  "airport_transfer",
  "hotel_transfer",
  "event_transfer",
  "hourly_package",
]);

const ISO_CURRENCY = /^[A-Z]{3}$/;

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function toInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.trunc(n);
}

function toNonNegativeCents(value) {
  const n = toInt(value);
  if (n == null || n < 0) return null;
  return n;
}

function toBool(value, fallback = false) {
  if (value === true) return true;
  if (value === false) return false;
  const token = normalizeLimousineToken(value);
  if (token === "true" || token === "1" || token === "yes" || token === "on") return true;
  if (token === "false" || token === "0" || token === "no" || token === "off") return false;
  return fallback;
}

function normalizeCurrency(value) {
  const c = String(value ?? "").trim().toUpperCase();
  return ISO_CURRENCY.test(c) ? c : "";
}

function normalizeJourneyType(value) {
  const token = normalizeLimousineToken(value);
  switch (token) {
    case "point_to_point":
    case "pointtopoint":
    case "p2p":
    case "direct":
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
  const token = normalizeLimousineToken(value);
  if (token === "to_airport" || token === "from_airport" || token === "both") return token;
  return "";
}

function normalizeClassId(value) {
  const token = normalizeLimousineToken(value);
  if (!token) return "";
  // A class id can never be a bare marketing/brand word.
  if (isForbiddenClassInferenceToken(token)) return "";
  return token;
}

// ---------------------------------------------------------------------------
// Storage normalization (optional `limousine` section inside pricing:v1)
// ---------------------------------------------------------------------------

function normalizeFixedRule(raw) {
  const src = asObject(raw);
  const ruleId = String(src.rule_id ?? src.ruleId ?? "").trim();
  const journeyType = normalizeJourneyType(src.journey_type ?? src.journeyType);
  const priceCents = toNonNegativeCents(src.price_incl_vat_cents ?? src.priceInclVatCents);
  const currency = normalizeCurrency(src.currency);
  const zoneType = normalizeLimousineToken(src.zone_type ?? src.zoneType) || "none";
  const rule = {
    rule_id: ruleId,
    enabled: toBool(src.enabled, false),
    priority: toInt(src.priority) ?? 0,
    journey_type: journeyType,
    direction: normalizeDirection(src.direction),
    airport_iata: String(src.airport_iata ?? src.airportIata ?? "").trim().toUpperCase(),
    zone_type: zoneType,
    zone_value: String(src.zone_value ?? src.zoneValue ?? "").trim().toUpperCase(),
    zone_center_lat: Number(src.zone_center_lat ?? src.zoneCenterLat),
    zone_center_lng: Number(src.zone_center_lng ?? src.zoneCenterLng),
    radius_km: Number(src.radius_km ?? src.radiusKm),
    price_incl_vat_cents: priceCents,
    vat_rate: Number(src.vat_rate ?? src.vatRate) || 0,
    currency,
    active_from_ms: Number(src.active_from_ms ?? src.activeFromMs) || null,
    active_until_ms: Number(src.active_until_ms ?? src.activeUntilMs) || null,
    source_revision: toInt(src.source_revision ?? src.sourceRevision) ?? 0,
  };
  return rule;
}

function fixedRuleIsComplete(rule) {
  if (!rule.rule_id) return false;
  if (!rule.journey_type) return false;
  if (rule.price_incl_vat_cents == null || rule.price_incl_vat_cents <= 0) return false;
  if (!rule.currency) return false;
  return true;
}

function normalizePackage(raw) {
  const src = asObject(raw);
  return {
    package_id: String(src.package_id ?? src.packageId ?? "").trim(),
    enabled: toBool(src.enabled, false),
    journey_type: normalizeJourneyType(src.journey_type ?? src.journeyType) || "hourly_package",
    duration_minutes: toInt(src.duration_minutes ?? src.durationMinutes),
    included_distance_km: Number(src.included_distance_km ?? src.includedDistanceKm),
    total_incl_vat_cents: toNonNegativeCents(src.total_incl_vat_cents ?? src.totalInclVatCents),
    vat_rate: Number(src.vat_rate ?? src.vatRate) || 0,
    currency: normalizeCurrency(src.currency),
    excess_per_km_cents: toNonNegativeCents(src.excess_per_km_cents ?? src.excessPerKmCents),
    excess_per_minute_cents: toNonNegativeCents(
      src.excess_per_minute_cents ?? src.excessPerMinuteCents,
    ),
    source_revision: toInt(src.source_revision ?? src.sourceRevision) ?? 0,
  };
}

function packageIsComplete(pkg) {
  if (!pkg.package_id) return false;
  if (pkg.journey_type !== "hourly_package") return false;
  if (pkg.duration_minutes == null || pkg.duration_minutes <= 0) return false;
  if (pkg.total_incl_vat_cents == null || pkg.total_incl_vat_cents <= 0) return false;
  if (!pkg.currency) return false;
  return true;
}

function normalizeDistanceTime(raw) {
  const src = asObject(raw);
  if (Object.keys(src).length === 0) return null;
  return {
    enabled: toBool(src.enabled, false),
    base_incl_vat_cents: toNonNegativeCents(src.base_incl_vat_cents ?? src.baseInclVatCents),
    per_km_incl_vat_cents: toNonNegativeCents(src.per_km_incl_vat_cents ?? src.perKmInclVatCents),
    per_minute_incl_vat_cents: toNonNegativeCents(
      src.per_minute_incl_vat_cents ?? src.perMinuteInclVatCents,
    ),
    minimum_incl_vat_cents: toNonNegativeCents(src.minimum_incl_vat_cents ?? src.minimumInclVatCents),
    vat_rate: Number(src.vat_rate ?? src.vatRate) || 0,
    currency: normalizeCurrency(src.currency),
    source_revision: toInt(src.source_revision ?? src.sourceRevision) ?? 0,
  };
}

function distanceTimeIsComplete(dt) {
  if (!dt) return false;
  if (dt.base_incl_vat_cents == null) return false;
  if (dt.per_km_incl_vat_cents == null) return false;
  if (dt.per_minute_incl_vat_cents == null) return false;
  if (dt.minimum_incl_vat_cents == null) return false;
  if (!dt.currency) return false;
  return true;
}

function normalizeClassPricing(raw) {
  const src = asObject(raw);
  const classId = normalizeClassId(src.service_class_id ?? src.serviceClassId);
  return {
    service_class_id: classId,
    enabled: toBool(src.enabled, false),
    currency: normalizeCurrency(src.currency),
    fixed_rules: Array.isArray(src.fixed_rules ?? src.fixedRules)
      ? (src.fixed_rules ?? src.fixedRules).map(normalizeFixedRule)
      : [],
    packages: Array.isArray(src.packages) ? src.packages.map(normalizePackage) : [],
    distance_time: normalizeDistanceTime(src.distance_time ?? src.distanceTime),
    manual_quote_fallback: toBool(src.manual_quote_fallback ?? src.manualQuoteFallback, false),
    source_revision: toInt(src.source_revision ?? src.sourceRevision) ?? 0,
  };
}

/// Normalizes the optional `limousine` section of a company pricing record.
/// Absent/invalid input yields a disabled section (no effect on taxi pricing).
function normalizeSelectedVehicleIds(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  const seen = new Set();
  for (const item of raw) {
    const id = String(item || "").trim();
    if (!id || id.length > 96 || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
  }
  return out;
}

const LIMOUSINE_HERO_SOURCES = new Set(["upload", "vehicle_media"]);
const LIMOUSINE_HERO_ALIGNMENTS = new Set(["center", "top", "bottom", "left", "right"]);

function httpsOnly(raw) {
  const text = String(raw ?? "").trim();
  return /^https:\/\//i.test(text) ? text.slice(0, 600) : "";
}

export function normalizeLimousineHero(raw) {
  const src = asObject(raw);
  const nested = asObject(src.limousine_hero ?? src.limousineHero);
  const photo = httpsOnly(
    nested.photo_url ??
      nested.photoUrl ??
      src.limousine_hero_url ??
      src.limousineHeroUrl,
  );
  const source = normalizeLimousineToken(
    nested.source_kind ?? nested.sourceKind ?? src.limousine_hero_source,
  );
  const alignment = normalizeLimousineToken(
    nested.alignment ?? src.limousine_hero_alignment,
  );
  return {
    photo_url: photo,
    source_kind: LIMOUSINE_HERO_SOURCES.has(source) ? source : photo ? "upload" : "",
    vehicle_id: String(nested.vehicle_id ?? nested.vehicleId ?? "").trim().slice(0, 96),
    alignment: LIMOUSINE_HERO_ALIGNMENTS.has(alignment) ? alignment : "center",
    source_revision: toInt(nested.source_revision ?? nested.sourceRevision ?? src.limousine_hero_revision) ?? 0,
  };
}

export function applyPublicLimousineHeroFields(profile, section) {
  const base = profile && typeof profile === "object" ? { ...profile } : {};
  const hero = normalizeLimousineHero(section);
  delete base.limousine_hero_url;
  delete base.limousine_hero_source;
  delete base.limousine_hero_alignment;
  delete base.limousine_hero_revision;
  if (!hero.photo_url) return base;
  return {
    ...base,
    limousine_hero_url: hero.photo_url,
    limousine_hero_source: hero.source_kind || "upload",
    limousine_hero_alignment: hero.alignment,
    limousine_hero_revision: hero.source_revision,
  };
}

function incomingHasOwn(source, keys) {
  if (!source || typeof source !== "object" || Array.isArray(source)) return false;
  return keys.some((key) => Object.prototype.hasOwnProperty.call(source, key));
}

export function normalizeLimousinePricingSection(raw) {
  const src = asObject(raw);
  const published = normalizePublishedLimousineIdentity(src);
  return {
    enabled: toBool(src.enabled, false),
    currency: normalizeCurrency(src.currency),
    source_revision: toInt(src.source_revision ?? src.sourceRevision) ?? 0,
    updated_at: String(src.updated_at ?? src.updatedAt ?? "").trim(),
    classes: Array.isArray(src.classes) ? src.classes.map(normalizeClassPricing) : [],
    // LIMOUSINE-MARKETPLACE-P2B2: commercial offers (additive; P2B1 records
    // without `offers` keep parsing and resolving exactly as before).
    offers: normalizeLimousineOffers(src.offers),
    selected_vehicle_ids: normalizeSelectedVehicleIds(
      src.selected_vehicle_ids ?? src.selectedVehicleIds,
    ),
    public_title: normalizeLocalizedText(src.public_title ?? src.publicTitle, { max: 120 }),
    public_description: normalizeLocalizedText(
      src.public_description ?? src.publicDescription,
      { max: 4000 },
    ),
    limousine_hero: normalizeLimousineHero(src),
    published_public_title: published.published_public_title,
    published_public_description: published.published_public_description,
    published_limousine_profile_cover: published.published_limousine_profile_cover,
    published_limousine_hero: published.published_limousine_hero,
    published_limousine_profile_logo: published.published_limousine_profile_logo,
    published_limousine_logo: published.published_limousine_logo,
    published_limousine_visiting_card: published.published_limousine_visiting_card,
    ...(published.published_limousine_vehicle_public_copy
      ? {
          published_limousine_vehicle_public_copy:
            published.published_limousine_vehicle_public_copy,
        }
      : {}),
    published_at: published.published_at,
    limousine_profile_cover_schema: published.limousine_profile_cover_schema,
    limousine_profile_logo_schema: published.limousine_profile_logo_schema,
    ...(published.tenant_id ? { tenant_id: published.tenant_id } : {}),
    ...(published.company_id ? { company_id: published.company_id } : {}),
    ...(published.partner_id ? { partner_id: published.partner_id } : {}),
  };
}

/// PATCH-like merge: omitted fields keep the stored value. An explicit empty
/// array/object is a deliberate clear. Full records still normalize as before.
export function mergeLimousinePricingSection(existingRaw, incomingRaw) {
  const existing = normalizeLimousinePricingSection(existingRaw);
  const incoming =
    incomingRaw && typeof incomingRaw === "object" && !Array.isArray(incomingRaw)
      ? incomingRaw
      : {};
  const merged = { ...incoming };
  if (!incomingHasOwn(incoming, ["enabled"])) merged.enabled = existing.enabled;
  if (!incomingHasOwn(incoming, ["currency"])) merged.currency = existing.currency;
  if (!incomingHasOwn(incoming, ["classes"])) merged.classes = existing.classes;
  if (!incomingHasOwn(incoming, ["offers"])) merged.offers = existing.offers;
  if (!incomingHasOwn(incoming, ["selected_vehicle_ids", "selectedVehicleIds"])) {
    merged.selected_vehicle_ids = existing.selected_vehicle_ids;
  }
  if (!incomingHasOwn(incoming, ["public_title", "publicTitle"])) {
    merged.public_title = existing.public_title;
  }
  if (!incomingHasOwn(incoming, ["public_description", "publicDescription"])) {
    merged.public_description = existing.public_description;
  }
  if (
    !incomingHasOwn(incoming, [
      "limousine_hero",
      "limousineHero",
      "limousine_hero_url",
      "limousineHeroUrl",
    ])
  ) {
    merged.limousine_hero = existing.limousine_hero;
  }
  const published = mergePublishedLimousineIdentity(existing, incoming);
  merged.published_public_title = published.published_public_title;
  merged.published_public_description = published.published_public_description;
  merged.published_limousine_profile_cover = published.published_limousine_profile_cover;
  merged.published_limousine_hero = published.published_limousine_hero;
  merged.published_limousine_profile_logo = published.published_limousine_profile_logo;
  merged.published_limousine_logo = published.published_limousine_logo;
  merged.published_limousine_visiting_card = published.published_limousine_visiting_card;
  if (published.published_limousine_vehicle_public_copy) {
    merged.published_limousine_vehicle_public_copy =
      published.published_limousine_vehicle_public_copy;
  }
  merged.published_at = published.published_at;
  merged.limousine_profile_cover_schema = published.limousine_profile_cover_schema;
  merged.limousine_profile_logo_schema = published.limousine_profile_logo_schema;
  if (published.tenant_id) merged.tenant_id = published.tenant_id;
  if (published.company_id) merged.company_id = published.company_id;
  if (published.partner_id) merged.partner_id = published.partner_id;
  return normalizeLimousinePricingSection(merged);
}

export function countPublishedLimousineOffers(section) {
  const offers = Array.isArray(section?.offers) ? section.offers : [];
  return offers.filter((offer) => offer && offer.enabled !== false && offer.published === true)
    .length;
}

export function findLimousineClassPricing(section, classId) {
  const normalized = normalizeClassId(classId);
  if (!normalized) return null;
  const classes = Array.isArray(section?.classes) ? section.classes : [];
  return classes.find((c) => c.service_class_id === normalized) || null;
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

function haversineKm(lat1, lng1, lat2, lng2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function zoneSpecificity(zoneType) {
  switch (zoneType) {
    case "postcode":
      return 4;
    case "city":
      return 3;
    case "radius":
      return 2;
    case "country":
      return 1;
    default:
      return 0;
  }
}

function directionMatches(ruleDirection, requestDirection) {
  if (!ruleDirection || ruleDirection === "both") return true;
  if (!requestDirection) return false;
  return ruleDirection === requestDirection;
}

function zoneMatches(rule, request) {
  const zoneType = rule.zone_type || "none";
  if (zoneType === "none") return true;
  if (zoneType === "postcode") {
    const rv = String(rule.zone_value || "").toUpperCase().replace(/\s+/g, "");
    const req = String(request.postcode || "").toUpperCase().replace(/\s+/g, "");
    return !!rv && !!req && rv === req;
  }
  if (zoneType === "city") {
    const rv = normalizeLimousineToken(rule.zone_value);
    const req = normalizeLimousineToken(request.city);
    return !!rv && !!req && rv === req;
  }
  if (zoneType === "country") {
    const rv = String(rule.zone_value || "").toUpperCase();
    const req = String(request.country || "").toUpperCase();
    return !!rv && !!req && rv === req;
  }
  if (zoneType === "radius") {
    if (
      !Number.isFinite(rule.zone_center_lat) ||
      !Number.isFinite(rule.zone_center_lng) ||
      !Number.isFinite(rule.radius_km) ||
      rule.radius_km <= 0 ||
      !Number.isFinite(request.lat) ||
      !Number.isFinite(request.lng)
    ) {
      return false;
    }
    return haversineKm(request.lat, request.lng, rule.zone_center_lat, rule.zone_center_lng) <=
      rule.radius_km;
  }
  return false;
}

function ruleActive(rule, nowMs) {
  const now = Number.isFinite(nowMs) ? nowMs : Date.now();
  if (Number.isFinite(rule.active_from_ms) && rule.active_from_ms && now < rule.active_from_ms) {
    return false;
  }
  if (Number.isFinite(rule.active_until_ms) && rule.active_until_ms && now > rule.active_until_ms) {
    return false;
  }
  return true;
}

function selectBestFixedRule(candidates) {
  if (candidates.length === 0) return { rule: null, ambiguous: false };
  const sorted = [...candidates].sort((a, b) => {
    if (b.priority !== a.priority) return b.priority - a.priority;
    const sa = zoneSpecificity(a.zone_type);
    const sb = zoneSpecificity(b.zone_type);
    if (sb !== sa) return sb - sa;
    if (a.zone_type === "radius" && b.zone_type === "radius") {
      if (a.radius_km !== b.radius_km) return a.radius_km - b.radius_km;
    }
    return String(a.rule_id).localeCompare(String(b.rule_id));
  });
  const top = sorted[0];
  const second = sorted[1];
  // Ambiguous when the two best rules are indistinguishable on every
  // deterministic key (fail closed rather than pick arbitrarily).
  if (
    second &&
    second.priority === top.priority &&
    zoneSpecificity(second.zone_type) === zoneSpecificity(top.zone_type) &&
    (top.zone_type !== "radius" || second.radius_km === top.radius_km) &&
    second.rule_id === top.rule_id
  ) {
    return { rule: null, ambiguous: true };
  }
  return { rule: top, ambiguous: false };
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

function unresolved(reason, extra = {}) {
  const manual = reason === LIMOUSINE_PRICING_REASONS.MANUAL_QUOTE;
  return {
    resolved: false,
    manual_quote_required: manual,
    unavailable: !manual,
    reason,
    ...extra,
  };
}

function pricedResult({
  mode,
  classId,
  journeyType,
  request,
  route,
  ruleRef,
  sourceRevision,
  inclVatCents,
  vatRate,
  currency,
}) {
  const finalized = finalizeLegPricingInclVat({
    rawInclVat: inclVatCents / 100,
    vatRate: Number(vatRate) || 0,
  });
  return {
    resolved: true,
    manual_quote_required: false,
    unavailable: false,
    reason: LIMOUSINE_PRICING_REASONS.RESOLVED,
    service_category: "limousine",
    journey_type: journeyType,
    service_class_id: classId,
    pricing_mode: mode,
    matched_rule_ref: ruleRef,
    source_revision: sourceRevision,
    distance_km: route?.distance_km ?? null,
    duration_min: route?.duration_min ?? null,
    direction: request.direction || "",
    zone_value: request.postcode || request.city || request.country || "",
    price_incl_vat: finalized.price_incl_vat,
    price_ex_vat: finalized.price_ex_vat,
    price_vat: finalized.price_vat,
    currency,
    vat_mode: "incl",
    included_options: [],
    separately_disclosed_charges: [],
  };
}

/// Hourly hire total in integer cents. Enforces the minimum hire duration and
/// the configured maximum; returns null when the configuration is incomplete.
export function computeOfferHourlyCents(hourly, requestedMinutes) {
  if (!hourly || !hourly.enabled) return null;
  if (hourly.first_hour_cents == null || hourly.first_hour_cents < 0) return null;
  if (hourly.additional_hour_cents == null || hourly.additional_hour_cents < 0) return null;
  if (hourly.minimum_duration_minutes == null || hourly.minimum_duration_minutes <= 0) {
    return null;
  }
  const requested = Number.isFinite(Number(requestedMinutes))
    ? Math.max(0, Math.trunc(Number(requestedMinutes)))
    : 0;
  if (
    hourly.maximum_duration_minutes != null &&
    hourly.maximum_duration_minutes > 0 &&
    requested > hourly.maximum_duration_minutes
  ) {
    return null;
  }
  // A package covers the whole hire when it is fully configured and long enough.
  if (
    hourly.package_amount_cents != null &&
    hourly.package_amount_cents > 0 &&
    hourly.package_duration_minutes != null &&
    hourly.package_duration_minutes > 0 &&
    requested <= hourly.package_duration_minutes
  ) {
    return hourly.package_amount_cents;
  }
  const billableMinutes = Math.max(requested, hourly.minimum_duration_minutes);
  const hours = Math.max(1, Math.ceil(billableMinutes / 60));
  return hourly.first_hour_cents + hourly.additional_hour_cents * (hours - 1);
}

/// Resolves an outcome from a matched commercial offer. Returns null when the
/// offer cannot decide and the legacy class-level path should be consulted.
function resolveFromOffer({
  offer,
  classId,
  journeyType,
  request,
  route,
  nowMs,
  sectionCurrency,
}) {
  const R = LIMOUSINE_PRICING_REASONS;
  const P = LIMOUSINE_PRICE_PRESENTATIONS;

  if (offer.price_presentation === P.UNAVAILABLE) return unresolved(R.UNAVAILABLE);
  // Marketing-only presentations never produce a final customer price.
  if (
    offer.price_presentation === P.QUOTE_REQUIRED ||
    offer.price_presentation === P.FROM_PRICE ||
    offer.price_presentation === P.INDICATIVE
  ) {
    return unresolved(R.MANUAL_QUOTE);
  }
  if (offer.price_presentation !== P.EXACT_FIXED) return unresolved(R.UNAVAILABLE);

  const currency =
    normalizeCurrency(request.currency) || offer.currency || sectionCurrency;
  if (!currency) return unresolved(R.CURRENCY_MISMATCH);
  if (offer.currency && offer.currency !== currency) return unresolved(R.CURRENCY_MISMATCH);

  // 1) Fixed journey rules on the offer.
  const candidates = offer.fixed_rules.filter((rule) => {
    if (!rule.enabled) return false;
    if (rule.amount_cents == null || rule.amount_cents <= 0) return false;
    if (rule.currency && rule.currency !== currency) return false;
    if (rule.journey_type !== journeyType) return false;
    if (journeyType === "airport_transfer") {
      const reqIata = String(request.airport_iata || "").trim().toUpperCase();
      if (!rule.airport_iata || !reqIata || rule.airport_iata !== reqIata) return false;
      if (!directionMatches(rule.direction, normalizeDirection(request.direction))) return false;
    }
    if (!zoneMatches(rule, request)) return false;
    if (!ruleActive(rule, nowMs)) return false;
    return true;
  });
  if (candidates.length > 0) {
    const { rule, ambiguous } = selectBestFixedRule(
      candidates.map((r) => ({ ...r, priority: r.priority ?? 0 })),
    );
    if (ambiguous) return unresolved(R.AMBIGUOUS_FIXED_RULE);
    if (rule) {
      return pricedResult({
        mode: LIMOUSINE_PRICING_MODES.FIXED,
        classId,
        journeyType,
        request,
        route,
        ruleRef: `${offer.offer_id}:${rule.rule_id}`,
        sourceRevision: offer.source_revision,
        inclVatCents: rule.amount_cents,
        vatRate: rule.vat_rate,
        currency,
      });
    }
  }

  // 2) Hourly hire (only for an hourly journey).
  if (journeyType === "hourly_package" && offer.hourly?.enabled) {
    if (offer.hourly.currency && offer.hourly.currency !== currency) {
      return unresolved(R.CURRENCY_MISMATCH);
    }
    const cents = computeOfferHourlyCents(offer.hourly, request.requested_duration_minutes);
    if (cents == null) return unresolved(R.INCOMPLETE_PACKAGE);
    return pricedResult({
      mode: LIMOUSINE_PRICING_MODES.PACKAGE,
      classId,
      journeyType,
      request,
      route,
      ruleRef: `${offer.offer_id}:hourly`,
      sourceRevision: offer.source_revision,
      inclVatCents: cents,
      vatRate: offer.hourly.vat_rate ?? 0,
      currency,
    });
  }

  // 3) Offer-level limousine distance/time using the SERVER route only.
  const dt = offer.distance_time;
  if (dt && dt.enabled) {
    const incomplete =
      dt.base_incl_vat_cents == null ||
      dt.per_km_incl_vat_cents == null ||
      dt.per_minute_incl_vat_cents == null ||
      dt.minimum_incl_vat_cents == null ||
      !dt.currency;
    if (incomplete) return unresolved(R.INCOMPLETE_DISTANCE_TIME);
    if (dt.currency !== currency) return unresolved(R.CURRENCY_MISMATCH);
    if (!route || !Number.isFinite(route.distance_km) || !Number.isFinite(route.duration_min)) {
      return unresolved(R.ROUTE_FAILED);
    }
    const km = Math.max(0, Number(route.distance_km));
    const min = Math.max(0, Number(route.duration_min));
    const rawCents =
      dt.base_incl_vat_cents +
      Math.round(km * dt.per_km_incl_vat_cents) +
      Math.round(min * dt.per_minute_incl_vat_cents);
    return pricedResult({
      mode: LIMOUSINE_PRICING_MODES.DISTANCE_TIME,
      classId,
      journeyType,
      request,
      route,
      ruleRef: `${offer.offer_id}:distance_time`,
      sourceRevision: offer.source_revision,
      inclVatCents: Math.max(dt.minimum_incl_vat_cents, rawCents),
      vatRate: dt.vat_rate,
      currency,
    });
  }

  // An exact_fixed offer that cannot price this request fails closed rather
  // than falling back to taxi pricing or to another company's configuration.
  return unresolved(R.UNAVAILABLE);
}

/// Full authoritative resolution for an explicit Limousine quote request.
/// Encapsulates the server gate + provider eligibility + the pricing hierarchy
/// so the whole decision is a single, pure, testable unit. Never returns a taxi
/// price and never invents a number on a manual/unavailable outcome.
export function resolveLimousineQuote({
  gateEnabled = false,
  eligible = false,
  section = null,
  request = {},
  route = null,
  nowMs = null,
} = {}) {
  const R = LIMOUSINE_PRICING_REASONS;
  if (!gateEnabled) return unresolved(R.GATE_OFF);
  if (!eligible) return unresolved(R.NOT_ELIGIBLE);

  // Explicit category + class are required; never inferred.
  if (!isLimousineServiceToken(request.service_category)) {
    return unresolved(R.UNAVAILABLE);
  }
  const classId = normalizeClassId(request.service_class_id);
  if (!classId) return unresolved(R.MISSING_CLASS);

  const normalizedSection = normalizeLimousinePricingSection(section);
  if (!normalizedSection.enabled) return unresolved(R.SECTION_DISABLED);

  // Stale/contradictory revision: when the caller asserts an expected pricing
  // revision, a mismatch fails closed rather than pricing against stale data.
  if (request.expected_source_revision != null) {
    const expected = toInt(request.expected_source_revision);
    if (expected == null || normalizedSection.source_revision !== expected) {
      return unresolved(R.STALE_REVISION);
    }
  }

  const journeyTypeEarly = normalizeJourneyType(request.journey_type);
  if (!journeyTypeEarly || !SUPPORTED_JOURNEY_TYPES.has(journeyTypeEarly)) {
    return unresolved(R.UNSUPPORTED_JOURNEY_TYPE);
  }

  // LIMOUSINE-MARKETPLACE-P2B2: a configured commercial offer wins, with an
  // exact vehicle offer overriding a service-class offer. Only `exact_fixed`
  // may resolve; from/indicative are marketing and quote_required is manual.
  const matchedOffer = selectLimousineOfferForRequest(normalizedSection.offers, {
    vehicleId: request.vehicle_id,
    serviceClassId: classId,
    journeyType: journeyTypeEarly,
  });
  if (matchedOffer) {
    const offerOutcome = resolveFromOffer({
      offer: matchedOffer,
      classId,
      journeyType: journeyTypeEarly,
      request,
      route,
      nowMs,
      sectionCurrency: normalizedSection.currency,
    });
    if (offerOutcome) return offerOutcome;
  }

  const classPricing = findLimousineClassPricing(normalizedSection, classId);
  if (!classPricing) return unresolved(R.UNKNOWN_CLASS);
  if (!classPricing.enabled) return unresolved(R.CLASS_DISABLED);

  const journeyType = journeyTypeEarly;

  const expectedCurrency =
    normalizeCurrency(request.currency) ||
    classPricing.currency ||
    normalizedSection.currency;
  if (!expectedCurrency) return unresolved(R.CURRENCY_MISMATCH);

  // 1) Fixed route/airport fare.
  const fixedCandidates = classPricing.fixed_rules.filter((rule) => {
    if (!rule.enabled) return false;
    if (!fixedRuleIsComplete(rule)) return false;
    if (rule.currency !== expectedCurrency) return false;
    if (rule.journey_type !== journeyType) return false;
    if (journeyType === "airport_transfer") {
      const reqIata = String(request.airport_iata || "").trim().toUpperCase();
      if (!rule.airport_iata || !reqIata || rule.airport_iata !== reqIata) return false;
      if (!directionMatches(rule.direction, normalizeDirection(request.direction))) return false;
    }
    if (!zoneMatches(rule, request)) return false;
    if (!ruleActive(rule, nowMs)) return false;
    return true;
  });
  // Any complete-but-currency-mismatched rule that would otherwise match is a
  // hard fail-closed signal.
  const currencyConflict = classPricing.fixed_rules.some(
    (rule) =>
      rule.enabled &&
      fixedRuleIsComplete(rule) &&
      rule.journey_type === journeyType &&
      rule.currency !== expectedCurrency,
  );
  if (currencyConflict && fixedCandidates.length === 0) {
    return unresolved(R.CURRENCY_MISMATCH);
  }
  if (fixedCandidates.length > 0) {
    const { rule, ambiguous } = selectBestFixedRule(fixedCandidates);
    if (ambiguous) return unresolved(R.AMBIGUOUS_FIXED_RULE);
    if (rule) {
      return pricedResult({
        mode: LIMOUSINE_PRICING_MODES.FIXED,
        classId,
        journeyType,
        request,
        route,
        ruleRef: rule.rule_id,
        sourceRevision: rule.source_revision || classPricing.source_revision,
        inclVatCents: rule.price_incl_vat_cents,
        vatRate: rule.vat_rate,
        currency: expectedCurrency,
      });
    }
  }

  // 2) Hourly/package fare — only for hourlyPackage journeys.
  if (journeyType === "hourly_package") {
    const pkgs = classPricing.packages.filter(
      (pkg) => pkg.enabled && pkg.currency === expectedCurrency,
    );
    if (pkgs.length > 0) {
      const complete = pkgs.filter(packageIsComplete);
      if (complete.length === 0) return unresolved(R.INCOMPLETE_PACKAGE);
      const pkg = complete.sort((a, b) =>
        String(a.package_id).localeCompare(String(b.package_id)),
      )[0];
      return pricedResult({
        mode: LIMOUSINE_PRICING_MODES.PACKAGE,
        classId,
        journeyType,
        request,
        route,
        ruleRef: pkg.package_id,
        sourceRevision: pkg.source_revision || classPricing.source_revision,
        inclVatCents: pkg.total_incl_vat_cents,
        vatRate: pkg.vat_rate,
        currency: expectedCurrency,
      });
    }
    // A hourly journey with no usable package falls through to distance/time
    // only if the class explicitly configures one; otherwise manual/unavailable.
  }

  // 3) Limousine-specific distance/time using the SERVER route only.
  const dt = classPricing.distance_time;
  if (dt && dt.enabled) {
    if (!distanceTimeIsComplete(dt)) return unresolved(R.INCOMPLETE_DISTANCE_TIME);
    if (dt.currency !== expectedCurrency) return unresolved(R.CURRENCY_MISMATCH);
    if (!route || !Number.isFinite(route.distance_km) || !Number.isFinite(route.duration_min)) {
      return unresolved(R.ROUTE_FAILED);
    }
    const km = Math.max(0, Number(route.distance_km));
    const min = Math.max(0, Number(route.duration_min));
    const rawCents =
      dt.base_incl_vat_cents +
      Math.round(km * dt.per_km_incl_vat_cents) +
      Math.round(min * dt.per_minute_incl_vat_cents);
    const inclCents = Math.max(dt.minimum_incl_vat_cents, rawCents);
    return pricedResult({
      mode: LIMOUSINE_PRICING_MODES.DISTANCE_TIME,
      classId,
      journeyType,
      request,
      route,
      ruleRef: `distance_time:${classId}`,
      sourceRevision: dt.source_revision || classPricing.source_revision,
      inclVatCents: inclCents,
      vatRate: dt.vat_rate,
      currency: expectedCurrency,
    });
  }

  // 4) Manual quote if authoritative, else 5) unavailable.
  if (classPricing.manual_quote_fallback) return unresolved(R.MANUAL_QUOTE);
  return unresolved(R.UNAVAILABLE);
}

/// Reads a "0"/"1"/"true" style server gate. Default OFF.
export function limousineQuoteGateEnabled(rawValue) {
  const token = normalizeLimousineToken(rawValue);
  return token === "1" || token === "true" || token === "yes" || token === "on";
}
