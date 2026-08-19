// LIMOUSINE-MARKETPLACE-P1 — authoritative server-side provider eligibility.
//
// Pure, dependency-free module (mirrors the committed P0 Flutter contract in
// lib/limousine/*). It answers ONE question from authoritative projected state:
//
//   "May this company currently appear as a Limousine provider for this market?"
//
// Hard rules:
//   * fail closed on missing / stale / contradictory state;
//   * never infer from company name, vehicle name/brand/model, marketing words
//     (executive / premium / luxury / Mercedes), taxi tier, or historical use;
//   * entitlement (features['limousine']) is authoritative and server-owned;
//   * subscription lifecycle reuses the existing public-visibility semantics
//     (active / valid), never a new interpretation;
//   * older revisions may never overwrite a newer disable/suspension.

export const LIMOUSINE_SERVICE_TOKEN = "limousine";

const LIMOUSINE_SERVICE_ALIASES = new Set(["limousine", "limousine_service"]);

// Marketing/brand words that must NEVER, on their own, create eligibility.
const FORBIDDEN_CLASS_INFERENCE_TOKENS = new Set([
  "executive",
  "premium",
  "luxury",
  "vip",
  "business",
  "mercedes",
  "bmw",
  "audi",
  "tesla",
  "sclass",
  "s_class",
  "limo",
  "limousine",
  "comfort",
  "private",
]);

export const LIMOUSINE_ELIGIBILITY_REASONS = Object.freeze({
  ELIGIBLE: "eligible",
  COMPANY_INACTIVE: "company_inactive",
  COMPANY_SUSPENDED: "company_suspended",
  COMPANY_DELETED: "company_deleted",
  SUBSCRIPTION_NOT_PERMITTED: "subscription_not_permitted",
  NOT_ENTITLED: "not_entitled",
  NOT_ENABLED: "not_enabled",
  PROFILE_NOT_PUBLISHED: "profile_not_published",
  BOOKINGS_NOT_ACCEPTED: "bookings_not_accepted",
  MARKET_NOT_COVERED: "market_not_covered",
  NO_ELIGIBLE_VEHICLE: "no_eligible_vehicle",
});

export function normalizeLimousineToken(raw) {
  return String(raw ?? "")
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
}

export function isLimousineServiceToken(raw) {
  return LIMOUSINE_SERVICE_ALIASES.has(normalizeLimousineToken(raw));
}

export function isForbiddenClassInferenceToken(raw) {
  return FORBIDDEN_CLASS_INFERENCE_TOKENS.has(normalizeLimousineToken(raw));
}

function looksTruthy(value) {
  if (value === true) return true;
  if (typeof value === "number") return value !== 0;
  const token = normalizeLimousineToken(value);
  return token === "true" || token === "1" || token === "yes" || token === "on" || token === "enabled";
}

function looksFalsey(value) {
  if (value === false) return true;
  if (typeof value === "number") return value === 0;
  const token = normalizeLimousineToken(value);
  return token === "false" || token === "0" || token === "no" || token === "off" || token === "disabled";
}

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function serviceTokens(raw) {
  if (Array.isArray(raw)) {
    return raw.map((item) => normalizeLimousineToken(item)).filter((t) => t);
  }
  if (raw && typeof raw === "object") {
    return Object.keys(raw).map((k) => normalizeLimousineToken(k)).filter((t) => t);
  }
  return [];
}

/// Company explicitly enabled Limousine in its own public profile.
/// The durable opt-in is `services[]` containing a limousine token. A defaulted
/// `booking_capabilities.limousine=false` must not hide that token.
export function companyEnabledLimousine(candidate) {
  const c = asObject(candidate);
  if (serviceTokens(c.services).some((t) => LIMOUSINE_SERVICE_ALIASES.has(t))) {
    return true;
  }
  const capabilities = asObject(c.capabilities);
  const bookingCapabilities = asObject(c.booking_capabilities ?? c.bookingCapabilities);
  const explicit = [
    c.limousine_service_enabled,
    c.limousineServiceEnabled,
    capabilities.limousine,
    capabilities.limousine_service,
    bookingCapabilities.limousine,
    bookingCapabilities.limousine_service,
  ];
  let sawExplicit = false;
  let explicitTrue = false;
  let explicitFalse = false;
  for (const value of explicit) {
    if (value == null) continue;
    sawExplicit = true;
    if (looksTruthy(value)) explicitTrue = true;
    else if (looksFalsey(value)) explicitFalse = true;
  }
  if (explicitTrue) return true;
  if (explicitFalse || sawExplicit) return false;
  return false;
}

/// Authoritative, server-owned entitlement. Reads the projected boolean
/// (`limousine_entitled`) or the subscription features map. Missing / non-true
/// fails closed. Client-submitted values must already be stripped upstream.
export function resolveLimousineEntitlement(candidate) {
  const c = asObject(candidate);
  if (c.limousine_entitled === true) return true;
  if (c.limousine_entitled === false) return false;
  const features = asObject(c.features);
  if (features.limousine === true) return true;
  return false;
}

/// Public-discovery subscription gate. Reuses the existing
/// `_isSubscriptionActive` semantics (active / valid) — no new interpretation.
export function subscriptionPermitsLimousineDiscovery(status) {
  const s = normalizeLimousineToken(status);
  return s === "active" || s === "valid";
}

function recordIsBlocked(record) {
  const r = asObject(record);
  for (const key of [
    "deleted",
    "is_deleted",
    "isDeleted",
    "tombstoned",
    "is_tombstoned",
    "isTombstoned",
    "suspended",
    "is_suspended",
    "isSuspended",
  ]) {
    if (looksTruthy(r[key])) return true;
  }
  const status = normalizeLimousineToken(r.status ?? r.company_status ?? r.companyStatus);
  return status === "deleted" || status === "suspended" || status === "tombstoned" || status === "tombstone";
}

function recordIsActive(record, { missingMeansActive }) {
  const r = asObject(record);
  if (looksFalsey(r.is_active) || looksFalsey(r.isActive)) return false;
  if (looksTruthy(r.is_active) || looksTruthy(r.isActive)) return true;
  return missingMeansActive;
}

/// A vehicle/service qualifies only from authoritative configured identifiers:
/// service_category === 'limousine' AND a non-empty explicit service_class.
/// Never from name/brand/model/tier/marketing text.
export function isEligibleLimousineVehicle(vehicle) {
  const v = asObject(vehicle);
  if (recordIsBlocked(v)) return false;
  if (!recordIsActive(v, { missingMeansActive: true })) return false;
  const category = normalizeLimousineToken(v.service_category ?? v.serviceCategory);
  if (category !== LIMOUSINE_SERVICE_TOKEN) return false;
  const serviceClass = normalizeLimousineToken(v.service_class ?? v.serviceClass ?? v.service_class_id ?? v.serviceClassId);
  if (!serviceClass) return false;
  // A configured class id must not be a bare marketing/brand word.
  if (isForbiddenClassInferenceToken(serviceClass)) return false;
  return true;
}

function vehiclesFrom(candidate) {
  const c = asObject(candidate);
  const raw = c.vehicles ?? c.fleet ?? c.public_vehicles ?? c.publicVehicles;
  return Array.isArray(raw) ? raw : [];
}

export function hasEligibleLimousineVehicle(candidate) {
  return vehiclesFrom(candidate).some((v) => isEligibleLimousineVehicle(v));
}

function publicBookingsAccepted(candidate) {
  const c = asObject(candidate);
  if (looksFalsey(c.public_bookings_accepted) || looksFalsey(c.publicBookingsAccepted) || looksFalsey(c.bookable)) {
    return false;
  }
  const availability = normalizeLimousineToken(c.availability_status ?? c.availabilityStatus);
  if (availability === "inactive") return false;
  return true;
}

function profilePublished(candidate) {
  const c = asObject(candidate);
  if (looksFalsey(c.profile_enabled) || looksFalsey(c.profileEnabled)) return false;
  if (looksTruthy(c.profile_enabled) || looksTruthy(c.profileEnabled) || looksTruthy(c.public_profile_published)) {
    return true;
  }
  for (const key of ["published_at", "publishedAt", "public_partner_profile_published_at"]) {
    if (String(c[key] ?? "").trim()) return true;
  }
  return false;
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return 6371 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function normalizePostcode(raw) {
  return String(raw ?? "").trim().toUpperCase().replace(/\s+/g, "");
}

function marketCovered(candidate, request) {
  if (!request || typeof request !== "object") return true;
  const c = asObject(candidate);
  const coverage = asObject(c.coverage);
  const reqPostcode = normalizePostcode(request.postcode);
  if (reqPostcode) {
    const set = new Set(
      [
        normalizePostcode(coverage.primary_postcode ?? coverage.primaryPostcode),
        ...(Array.isArray(coverage.postcodes) ? coverage.postcodes.map(normalizePostcode) : []),
        ...(Array.isArray(c.supported_postcodes) ? c.supported_postcodes.map(normalizePostcode) : []),
      ].filter((x) => x),
    );
    if (set.size === 0 || !set.has(reqPostcode)) return false;
  }
  const reqCountry = normalizeLimousineToken(request.countryCode ?? request.country).toUpperCase();
  if (reqCountry) {
    const companyCountry = normalizeLimousineToken(
      coverage.country ?? coverage.country_code ?? c.country ?? c.country_code,
    ).toUpperCase();
    if (!companyCountry || companyCountry !== reqCountry) return false;
  }
  if (Number.isFinite(request.lat) && Number.isFinite(request.lng)) {
    const lat = Number(coverage.lat);
    const lng = Number(coverage.lng);
    const radiusKm = Number(coverage.service_radius_km ?? coverage.serviceRadiusKm);
    if (!Number.isFinite(lat) || !Number.isFinite(lng) || !Number.isFinite(radiusKm) || radiusKm <= 0) {
      return false;
    }
    if (haversineKm(request.lat, request.lng, lat, lng) > radiusKm) return false;
  }
  return true;
}

/// Authoritative eligibility composition. Returns `{ eligible, reason }`.
/// `reason` is a safe diagnostic code (no subscription-private detail).
export function evaluateLimousineProviderEligibility(candidate, { request = null } = {}) {
  const R = LIMOUSINE_ELIGIBILITY_REASONS;
  const c = asObject(candidate);

  if (recordIsBlocked(c)) return { eligible: false, reason: R.COMPANY_DELETED };
  if (!recordIsActive(c, { missingMeansActive: false })) {
    return { eligible: false, reason: R.COMPANY_INACTIVE };
  }
  if (!subscriptionPermitsLimousineDiscovery(c.subscription_status ?? c.subscriptionStatus)) {
    return { eligible: false, reason: R.SUBSCRIPTION_NOT_PERMITTED };
  }
  if (!resolveLimousineEntitlement(c)) return { eligible: false, reason: R.NOT_ENTITLED };
  if (!companyEnabledLimousine(c)) return { eligible: false, reason: R.NOT_ENABLED };
  if (!profilePublished(c)) return { eligible: false, reason: R.PROFILE_NOT_PUBLISHED };
  // Transaction gates, bookable flags and market/radius coverage never hide a
  // published limousine profile. `request` remains accepted for callers but is
  // ranking input only — nearby applies distance sort separately.
  if (request && typeof request === "object") {
    /* location is not a visibility filter */
  }
  if (!hasEligibleLimousineVehicle(c)) return { eligible: false, reason: R.NO_ELIGIBLE_VEHICLE };
  return { eligible: true, reason: R.ELIGIBLE };
}

export function isEligibleLimousineProvider(candidate, options = {}) {
  return evaluateLimousineProviderEligibility(candidate, options).eligible;
}

export function filterLimousineEligibleProviders(candidates, options = {}) {
  if (!Array.isArray(candidates)) return [];
  return candidates.filter((candidate) => isEligibleLimousineProvider(candidate, options));
}

/// Maps a `service` query param to a supported discovery filter. Unknown/empty
/// values return null (no service filter) and NEVER become limousine.
export function resolveNearbyServiceFilter(serviceParam) {
  const token = normalizeLimousineToken(serviceParam);
  if (!token) return null;
  if (LIMOUSINE_SERVICE_ALIASES.has(token)) return LIMOUSINE_SERVICE_TOKEN;
  return null;
}

/// Safe public capability signals to attach to a discovery payload. Contains
/// no subscription-private or customer-private data.
export function publicLimousineSignals(candidate) {
  return {
    limousine_available: isEligibleLimousineProvider(candidate),
    limousine_service_enabled: companyEnabledLimousine(candidate),
  };
}

/// Server-side entitlement projection stamped at publish time from the
/// authoritative subscription profile. Returns a single safe boolean.
export function projectLimousineEntitled({ features = null, subscriptionStatus = "" } = {}) {
  const f = asObject(features);
  const entitled = f.limousine === true;
  return entitled && subscriptionPermitsLimousineDiscovery(subscriptionStatus);
}

/// Monotonic availability transition: an older revision may never overwrite a
/// newer disable/suspension; equal revisions are idempotent replays; a newer
/// valid reactivation restores availability.
export function resolveLimousineAvailabilityTransition({
  currentCommand,
  currentRevision,
  incomingCommand,
  incomingRevision,
}) {
  const cur = Number(currentRevision) || 0;
  const next = Number(incomingRevision) || 0;
  if (next <= cur) {
    return {
      applied: false,
      effectiveCommand: currentCommand,
      effectiveRevision: cur,
      ignoredReason: next === cur ? "idempotent_replay" : "stale_revision",
    };
  }
  return {
    applied: true,
    effectiveCommand: incomingCommand,
    effectiveRevision: next,
    ignoredReason: null,
  };
}
