// P2D4C1F — bounded public limousine discovery / test-preview projection.
//
// Pure helper. No KV, fetch, cron, binding, or logs of coordinates / IDs /
// secrets. Nearby still uses the existing directory + profiles + routes
// loaders (max 6 KV gets). This module only shapes in-memory public rows.

import {
  isEligibleLimousineProvider,
  isEligibleLimousineVehicle,
  normalizeLimousineToken,
} from "./limousine_provider_eligibility.mjs";
import { publicPublishedLimousineIdentityFields } from "./limousine_published_identity.mjs";

export const LIMOUSINE_DISCOVERY_LISTING_MODE_TEST_PREVIEW = "test_preview";
export const LIMOUSINE_DISCOVERY_NEARBY_LOADERS = Object.freeze([
  "_loadPartnerDirectory",
  "_loadPublicPartnerProfiles",
  "_loadPartnerBookingRoutes",
]);
// Each loader may read v2 then v1. No per-partner get. No list().
export const LIMOUSINE_DISCOVERY_NEARBY_MAX_KV_GETS = 6;

export const LIMOUSINE_DISCOVERY_FORBIDDEN_KEYS = Object.freeze([
  "operating_base",
  "operating_base_address",
  "operating_base_lat",
  "operating_base_lng",
  "tenant_id",
  "company_id",
  "license_plate",
  "licenseplate",
  "vin",
  "driver_id",
  "assigned_driver",
  "LIMOUSINE_ACCEPTANCE_SECRET",
  "limacc1",
  "limqs1",
]);

const PRESENTATION = new Set([
  "quote_required",
  "from_price",
  "exact_fixed",
  "indicative",
]);

function asObject(raw) {
  return raw && typeof raw === "object" && !Array.isArray(raw) ? raw : {};
}

function looksTruthy(value) {
  if (value === true) return true;
  if (typeof value === "number") return value !== 0;
  const token = normalizeLimousineToken(value);
  return token === "true" || token === "1" || token === "yes" || token === "on";
}

function looksFalsey(value) {
  if (value === false) return true;
  if (typeof value === "number") return value === 0;
  const token = normalizeLimousineToken(value);
  return token === "false" || token === "0" || token === "no" || token === "off";
}

function httpsOnly(raw) {
  const text = String(raw ?? "").trim();
  return /^https:\/\//i.test(text) ? text.slice(0, 600) : "";
}

function positiveInt(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.trunc(n);
}

function safeText(raw, max) {
  const text = String(raw ?? "").trim();
  return text ? text.slice(0, max) : "";
}

function offerLooksDraftOrUnpublished(offer) {
  const o = asObject(offer);
  if (looksTruthy(o.draft) || looksTruthy(o.is_draft) || looksTruthy(o.preview)) {
    return true;
  }
  const status = normalizeLimousineToken(o.status);
  if (status === "draft" || status === "unpublished" || status === "preview") {
    return true;
  }
  if (Object.prototype.hasOwnProperty.call(o, "published") && looksFalsey(o.published)) {
    return true;
  }
  if (Object.prototype.hasOwnProperty.call(o, "enabled") && looksFalsey(o.enabled)) {
    return true;
  }
  return false;
}

function offerPresentation(offer) {
  return normalizeLimousineToken(
    offer?.price_presentation ?? offer?.pricePresentation,
  );
}

function publishedLimousineOffers(profile) {
  const p = asObject(profile);
  const raw = p.limousine_offers ?? p.limousineOffers ?? p.offers;
  if (!Array.isArray(raw)) return [];
  return raw.filter((item) => {
    if (!item || typeof item !== "object") return false;
    if (offerLooksDraftOrUnpublished(item)) return false;
    const presentation = offerPresentation(item);
    if (presentation === "unavailable") return false;
    if (PRESENTATION.has(presentation)) return true;
    return looksTruthy(item.quote_required);
  });
}

export function limousineNearbyAllowsUnscopedListing({
  service = null,
  postcode = "",
  lat = null,
  lng = null,
} = {}) {
  if (normalizeLimousineToken(service) !== "limousine") return false;
  if (String(postcode || "").trim()) return false;
  if (Number.isFinite(lat) || Number.isFinite(lng)) return false;
  return true;
}

export function hasPublishedLimousineOfferOrQuoteRequired(profile) {
  const p = asObject(profile);
  const partnerPresentation = normalizeLimousineToken(
    p.limousine_price_presentation ?? p.limousinePricePresentation,
  );
  if (partnerPresentation === "quote_required") return true;
  if (looksTruthy(p.quote_required) || looksTruthy(p.price_on_request)) return true;
  return publishedLimousineOffers(p).length > 0;
}

/// Discovery listing: entitled + classified limousine vehicle + published
/// offer/quote-required. Name, brand, image and services[] never include.
export function isLimousineDiscoveryListable(profile) {
  const p = asObject(profile);
  if (!isEligibleLimousineProvider(p)) return false;
  const vehicles = Array.isArray(p.vehicles) ? p.vehicles : [];
  if (!vehicles.some(isEligibleLimousineVehicle)) return false;
  if (!hasPublishedLimousineOfferOrQuoteRequired(p)) return false;
  return true;
}

function publicCity(profile) {
  const p = asObject(profile);
  const coverage = asObject(p.coverage);
  for (const value of [
    p.public_city,
    p.publicCity,
    p.service_region,
    p.serviceRegion,
    coverage.city,
    coverage.region,
    coverage.public_city,
  ]) {
    const text = safeText(value, 80);
    if (text) return text;
  }
  return "";
}

function nearbyVehicles(profile) {
  const vehicles = Array.isArray(profile?.vehicles) ? profile.vehicles : [];
  const out = [];
  for (const vehicle of vehicles) {
    if (!isEligibleLimousineVehicle(vehicle)) continue;
    const serviceClassId = normalizeLimousineToken(
      vehicle.service_class_id ??
        vehicle.serviceClassId ??
        vehicle.service_class ??
        vehicle.serviceClass,
    );
    if (!serviceClassId) continue;
    const vehicleId = safeText(vehicle.vehicle_id ?? vehicle.vehicleId, 96);
    out.push({
      service_category: "limousine",
      ...(vehicleId ? { vehicle_id: vehicleId } : {}),
      photo_url: httpsOnly(
        vehicle.primary_photo_url ??
          vehicle.photo_url ??
          vehicle.photoUrl ??
          vehicle.public_photo_url,
      ),
      service_class_id: serviceClassId,
      ...(positiveInt(vehicle.passenger_capacity ?? vehicle.passengerCapacity ?? vehicle.pax) != null
        ? {
            passenger_capacity: positiveInt(
              vehicle.passenger_capacity ?? vehicle.passengerCapacity ?? vehicle.pax,
            ),
          }
        : {}),
      ...(positiveInt(vehicle.luggage_capacity ?? vehicle.luggageCapacity ?? vehicle.luggage) != null
        ? {
            luggage_capacity: positiveInt(
              vehicle.luggage_capacity ?? vehicle.luggageCapacity ?? vehicle.luggage,
            ),
          }
        : {}),
    });
    if (out.length === 2) break;
  }
  return out;
}

function offerAmountCents(offer) {
  const hourly = asObject(offer?.hourly);
  const packageAmount = positiveInt(hourly.package_amount_cents ?? hourly.packageAmountCents);
  if (packageAmount != null) return packageAmount;
  const firstHour = positiveInt(hourly.first_hour_cents ?? hourly.firstHourCents);
  if (firstHour != null) return firstHour;
  return positiveInt(offer?.display_amount_cents ?? offer?.displayAmountCents);
}

function offerLooksHourlyOrPackage(offer) {
  const hourly = asObject(offer?.hourly);
  return looksTruthy(hourly.enabled);
}

function nearbyPrice(profile) {
  const offers = publishedLimousineOffers(profile);
  let chosen = null;
  let lowest = null;
  for (const offer of offers) {
    if (offerPresentation(offer) !== "from_price") continue;
    const amount = offerAmountCents(offer);
    if (amount == null) continue;
    if (lowest == null || amount < lowest.amount) {
      lowest = { offer, amount };
    }
  }
  if (lowest) chosen = lowest.offer;
  if (!chosen) {
    chosen =
      offers.find((offer) => {
        const presentation = offerPresentation(offer);
        return (
          presentation === "exact_fixed" ||
          offerLooksHourlyOrPackage(offer)
        ) && offerAmountCents(offer) != null;
      }) ||
      offers[0] ||
      null;
  }
  const presentation =
    offerPresentation(chosen) ||
    normalizeLimousineToken(
      profile?.limousine_price_presentation ?? profile?.limousinePricePresentation,
    );
  if (!PRESENTATION.has(presentation)) return {};
  const amount = chosen
    ? offerAmountCents(chosen)
    : positiveInt(profile?.display_amount_cents);
  const currency = safeText(chosen?.currency ?? profile?.currency, 8).toUpperCase();
  const out = { limousine_price_presentation: presentation };
  if (presentation !== "quote_required" && amount != null && currency) {
    out.display_amount_cents = amount;
    out.currency = currency;
  }
  return out;
}

/// Safe nearby card fields from an already-loaded public profile.
/// Never copies private operating-base geometry, IDs, plates or drivers.
export function buildLimousineNearbyCardProjection(profile, { testPreview = true } = {}) {
  const p = asObject(profile);
  if (!isLimousineDiscoveryListable(p)) return {};
  const city = publicCity(p);
  const trust = asObject(p.trust);
  const verified = p.verified_partner === true || trust.verified_partner === true;
  const media = asObject(p.media);
  const logoUrl = httpsOnly(p.logo_url ?? p.logoUrl ?? media.logo_url ?? media.logoUrl);
  return {
    limousine_available: true,
    limousine_service_enabled: true,
    ...(logoUrl ? { logo_url: logoUrl } : {}),
    ...(city ? { public_city: city, service_region: city } : {}),
    trust: { verified_partner: verified },
    limousine_vehicles: nearbyVehicles(p),
    ...nearbyPrice(p),
    ...(testPreview ? { test_preview: true } : {}),
    ...publicPublishedLimousineIdentityFields(p, { publicSurface: true }),
  };
}

export function limousineDiscoveryPayloadHasPrivateFields(payload) {
  const walk = (value) => {
    if (!value || typeof value !== "object") return false;
    if (Array.isArray(value)) return value.some(walk);
    for (const [key, child] of Object.entries(value)) {
      const token = normalizeLimousineToken(key);
      if (LIMOUSINE_DISCOVERY_FORBIDDEN_KEYS.some((forbidden) => normalizeLimousineToken(forbidden) === token)) {
        return true;
      }
      if (walk(child)) return true;
    }
    return false;
  };
  return walk(payload);
}

export function filterLimousineDiscoveryPartners(partners, { allowlisted = (id) => false } = {}) {
  if (!Array.isArray(partners)) return [];
  return partners.filter((partner) => {
    const p = asObject(partner);
    if (!isLimousineDiscoveryListable(p)) return false;
    const companyId = String(p.company_id ?? p.companyId ?? "").trim();
    return allowlisted(companyId);
  });
}
