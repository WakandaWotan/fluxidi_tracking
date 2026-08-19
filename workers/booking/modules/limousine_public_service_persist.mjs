// Durable public-service toggle persist/merge.
// Omitted fields stay unchanged. Only an explicit payload may turn Limousine off.

export const PUBLIC_SERVICE_CATALOG = Object.freeze([
  "taxi_vvb",
  "airport_transfer",
  "business_rides",
  "event_mobility",
  "hotel_bnb_pickup",
  "online_payments",
  "limousine",
]);

const LIMOUSINE_CAPABILITY_KEYS = Object.freeze([
  "limousine",
  "limousine_service",
  "limousine_service_enabled",
  "limousineServiceEnabled",
]);

export function incomingHasOwn(source, keys) {
  if (!source || typeof source !== "object" || Array.isArray(source)) return false;
  return keys.some((key) => Object.prototype.hasOwnProperty.call(source, key));
}

export function sanitizePublicServiceIds(values) {
  const allowed = new Set(PUBLIC_SERVICE_CATALOG);
  const out = [];
  const seen = new Set();
  const list = Array.isArray(values) ? values : [];
  for (const raw of list) {
    const token = String(raw ?? "")
      .trim()
      .toLowerCase()
      .replace(/[\s-]+/g, "_");
    if (!token || !allowed.has(token) || seen.has(token)) continue;
    seen.add(token);
    out.push(token);
  }
  return out;
}

function readConfiguredFlag(source) {
  if (!source || typeof source !== "object") return false;
  return source.publicServicesConfigured === true ||
    source.public_services_configured === true;
}

export function mergeBusinessProfilePublicServices(existing = {}, incoming = {}) {
  const current = existing && typeof existing === "object" ? existing : {};
  const next = incoming && typeof incoming === "object" ? incoming : {};
  const existingIds = sanitizePublicServiceIds(
    current.publicServiceIds ?? current.public_service_ids,
  );
  const existingConfigured = readConfiguredFlag(current);
  const hasIds = incomingHasOwn(next, ["publicServiceIds", "public_service_ids"]);
  const hasConfigured = incomingHasOwn(next, [
    "publicServicesConfigured",
    "public_services_configured",
  ]);

  if (!hasIds && !hasConfigured) {
    return {
      publicServiceIds: existingIds,
      public_service_ids: existingIds,
      publicServicesConfigured: existingConfigured,
      public_services_configured: existingConfigured,
    };
  }

  const incomingIds = hasIds
    ? sanitizePublicServiceIds(next.publicServiceIds ?? next.public_service_ids)
    : existingIds;
  const incomingConfigured = hasConfigured
    ? readConfiguredFlag(next)
    : existingConfigured || incomingIds.length > 0;

  return {
    publicServiceIds: incomingIds,
    public_service_ids: incomingIds,
    publicServicesConfigured: incomingConfigured,
    public_services_configured: incomingConfigured,
  };
}

function readLimousineCapability(source) {
  if (!source || typeof source !== "object") return undefined;
  for (const key of LIMOUSINE_CAPABILITY_KEYS) {
    if (!Object.prototype.hasOwnProperty.call(source, key)) continue;
    const value = source[key];
    if (value == null) continue;
    if (value === true || value === 1 || value === "1" || value === "true") return true;
    if (value === false || value === 0 || value === "0" || value === "false") return false;
  }
  return undefined;
}

export function mergePublicPartnerProfilePreserveOmitted(existing = {}, incoming = {}) {
  const current = existing && typeof existing === "object" ? existing : {};
  const next = incoming && typeof incoming === "object" ? incoming : {};
  const merged = { ...current, ...next };

  if (!Array.isArray(next.services)) {
    merged.services = Array.isArray(current.services) ? current.services.slice() : [];
  }

  const incomingCaps = next.booking_capabilities ?? next.bookingCapabilities;
  const existingCaps =
    current.booking_capabilities ?? current.bookingCapabilities ?? {};
  if (incomingCaps == null || typeof incomingCaps !== "object" || Array.isArray(incomingCaps)) {
    merged.booking_capabilities = existingCaps;
    delete merged.bookingCapabilities;
  } else {
    const incomingLimo = readLimousineCapability(incomingCaps);
    const existingLimo = readLimousineCapability(existingCaps);
    merged.booking_capabilities = {
      ...existingCaps,
      ...incomingCaps,
      limousine: incomingLimo !== undefined ? incomingLimo : existingLimo === true,
    };
    delete merged.bookingCapabilities;
  }

  if (!incomingHasOwn(next, ["limousine_offers", "limousineOffers"]) &&
      Array.isArray(current.limousine_offers)) {
    merged.limousine_offers = current.limousine_offers;
  }
  if (!incomingHasOwn(next, ["vehicles"]) && Array.isArray(current.vehicles)) {
    merged.vehicles = current.vehicles;
  }
  if (!incomingHasOwn(next, ["limousine_hero_url", "limousineHeroUrl"]) &&
      (current.limousine_hero_url || current.limousineHeroUrl)) {
    merged.limousine_hero_url = current.limousine_hero_url || current.limousineHeroUrl;
    merged.limousine_hero_source = current.limousine_hero_source || current.limousineHeroSource;
    merged.limousine_hero_alignment =
      current.limousine_hero_alignment || current.limousineHeroAlignment;
  }

  return merged;
}

export function isStalePartnerPublish({ existingRevision, incomingRevision } = {}) {
  const existing = Number(existingRevision);
  const incoming = Number(incomingRevision);
  if (!Number.isFinite(existing) || existing <= 0) return false;
  if (!Number.isFinite(incoming)) return false;
  return incoming < existing;
}

export function publicServicesIncludeLimousine(values) {
  return sanitizePublicServiceIds(values).includes("limousine");
}
