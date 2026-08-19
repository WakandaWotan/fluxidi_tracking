// LIMOUSINE-MARKETPLACE-P2A — server-owned public Limousine readiness projection.
//
// Recomputes a small, SAFE public readiness object from authoritative state and
// stamps it onto the partner public profile with a monotonic source_revision.
// Reuses the eligibility resolver (single source of truth) and the monotonic
// integer helper from business_profile_revision.mjs. No pricing, no customer or
// subscription-private data is ever placed in the projection.

import { toMonotonicInt } from "./business_profile_revision.mjs";
import {
  companyEnabledLimousine,
  evaluateLimousineProviderEligibility,
  isEligibleLimousineVehicle,
  projectLimousineEntitled,
} from "./limousine_provider_eligibility.mjs";
import { buildSafePublicLimousineOffers } from "./limousine_offers.mjs";

/// Safe, public-only readiness projection. Contains no price/plan/customer data.
///
/// LIMOUSINE-MARKETPLACE-P2B2: when commercial `offers` are supplied, a safe
/// `published_offer_count` is added (published + enabled + valid + eligible
/// only). Omitting `offers` keeps the projection byte-identical to P2A.
function publishedOfferCountForProjection(profile, options = {}) {
  if (options && Number.isFinite(Number(options.safeOfferCount))) {
    return Math.max(0, Math.trunc(Number(options.safeOfferCount)));
  }
  const p = profile && typeof profile === "object" ? profile : {};
  if (options && options.offers != null) {
    const evaluation = evaluateLimousineProviderEligibility(p);
    return buildSafePublicLimousineOffers(options.offers, {
      eligible: evaluation.eligible,
      knownVehicles: options.knownVehicles || [],
      knownClassIds: options.knownClassIds || [],
      readiness: evaluation.eligible,
    }).length;
  }
  if (Array.isArray(p.limousine_offers)) return p.limousine_offers.length;
  if (Array.isArray(p.limousineOffers)) return p.limousineOffers.length;
  return 0;
}

export function buildLimousineProjection(profile, options = {}) {
  const p = profile && typeof profile === "object" ? profile : {};
  const evaluation = evaluateLimousineProviderEligibility(p);
  const vehicles = Array.isArray(p.vehicles) ? p.vehicles : [];
  const eligibleVehicleCount = vehicles.filter((v) => isEligibleLimousineVehicle(v)).length;
  const publishedOfferCount = publishedOfferCountForProjection(p, options);
  const available = evaluation.eligible && publishedOfferCount > 0;
  return {
    limousine_service_enabled: companyEnabledLimousine(p),
    limousine_available: available,
    eligible_vehicle_count: eligibleVehicleCount,
    reason: evaluation.eligible && !available ? "no_published_offer" : evaluation.reason,
    published_offer_count: publishedOfferCount,
  };
}

/// The customer-safe offer list. Never includes the private operating-base
/// address, driver/customer data, internal costs or unpublished rules.
export function buildLimousinePublicOffers(profile, options = {}) {
  const p = profile && typeof profile === "object" ? profile : {};
  const evaluation = evaluateLimousineProviderEligibility(p);
  return buildSafePublicLimousineOffers(options.offers, {
    eligible: evaluation.eligible,
    knownVehicles: options.knownVehicles || [],
    knownClassIds: options.knownClassIds || [],
    readiness: evaluation.eligible,
  });
}

/// Public-safe digest of offer content, hero and selected vehicles. Count alone
/// is not enough: price, binding, title or hero changes must also project.
export function limousinePublicContentDigest({
  offers = [],
  hero = null,
  selectedVehicleIds = [],
} = {}) {
  const safeOffers = (Array.isArray(offers) ? offers : []).map((raw) => {
    const offer = raw && typeof raw === "object" ? raw : {};
    const vehicleIds = offer.vehicle_ids ?? offer.vehicleIds;
    return {
      offer_id: String(offer.offer_id ?? offer.offerId ?? ""),
      published: offer.published === true,
      enabled: offer.enabled !== false,
      price_presentation: String(
        offer.price_presentation ?? offer.pricePresentation ?? "",
      ),
      display_amount_cents:
        Number(offer.display_amount_cents ?? offer.displayAmountCents ?? 0) || 0,
      vehicle_id: String(offer.vehicle_id ?? offer.vehicleId ?? ""),
      vehicle_ids: Array.isArray(vehicleIds) ? [...vehicleIds].map(String).sort() : [],
      service_class_id: String(offer.service_class_id ?? offer.serviceClassId ?? ""),
      applies_to_all:
        offer.applies_to_all_selected_vehicles === true ||
        offer.appliesToAllSelectedVehicles === true,
      title: offer.title ?? {},
      description: offer.description ?? {},
    };
  });
  const h = hero && typeof hero === "object" ? hero : {};
  return JSON.stringify({
    offers: safeOffers,
    hero: {
      photo_url: String(h.photo_url ?? h.photoUrl ?? ""),
      source_kind: String(h.source_kind ?? h.sourceKind ?? ""),
      alignment: String(h.alignment ?? ""),
      source_revision: Number(h.source_revision ?? h.sourceRevision ?? 0) || 0,
    },
    selected: (Array.isArray(selectedVehicleIds) ? selectedVehicleIds : [])
      .map(String)
      .sort(),
  });
}

export function limousinePublicContentDigestFromProfile(profile) {
  const p = profile && typeof profile === "object" ? profile : {};
  return limousinePublicContentDigest({
    offers: p.limousine_offers ?? p.limousineOffers ?? [],
    hero: {
      photo_url: p.limousine_hero_url ?? p.limousineHeroUrl,
      source_kind: p.limousine_hero_source ?? p.limousineHeroSource,
      alignment: p.limousine_hero_alignment ?? p.limousineHeroAlignment,
      source_revision: p.limousine_hero_revision ?? p.limousineHeroRevision,
    },
    selectedVehicleIds: p.selected_vehicle_ids ?? p.selectedVehicleIds ?? [],
  });
}

/// Deterministic fingerprint of the safe projection + the entitlement input, so
/// an idempotent replay does not advance the revision but a real change does.
export function limousineProjectionFingerprint(projection, entitled, contentDigest = "") {
  const p = projection && typeof projection === "object" ? projection : {};
  return JSON.stringify([
    entitled === true,
    p.limousine_service_enabled === true,
    p.limousine_available === true,
    toMonotonicInt(p.eligible_vehicle_count),
    String(p.reason || ""),
    toMonotonicInt(p.published_offer_count),
    String(contentDigest || ""),
  ]);
}

function readProjectionRevision(record, profile) {
  const rec = record && typeof record === "object" ? record : {};
  const prof = profile && typeof profile === "object" ? profile : {};
  const proj =
    prof.limousine_projection && typeof prof.limousine_projection === "object"
      ? prof.limousine_projection
      : {};
  return Math.max(
    toMonotonicInt(rec.source_revision),
    toMonotonicInt(rec.version),
    toMonotonicInt(prof.source_revision),
    toMonotonicInt(proj.source_revision),
  );
}

/// Monotonic projection resolver.
///   - unchanged fingerprint with a prior revision >= 1 => idempotent replay
///     (revision preserved, changed=false);
///   - otherwise a strictly higher revision is allocated (floor + 1);
///   - an older/equal externally-supplied revision can never lower the result.
export function resolveLimousineProjectionRevision({
  existingRecord = null,
  existingProfile = null,
  nextProjection = null,
  entitled = false,
  nowIso = null,
  existingContentDigest,
  nextContentDigest,
} = {}) {
  const now = String(nowIso || new Date().toISOString());
  const floor = readProjectionRevision(existingRecord, existingProfile);
  const existingProj =
    existingProfile && typeof existingProfile === "object"
      ? existingProfile.limousine_projection
      : null;
  const existingEntitled =
    existingProfile && typeof existingProfile === "object"
      ? existingProfile.limousine_entitled === true
      : false;
  const existingDigest =
    existingContentDigest ?? limousinePublicContentDigestFromProfile(existingProfile);
  const nextDigest = nextContentDigest ?? existingDigest;

  const unchanged =
    limousineProjectionFingerprint(existingProj, existingEntitled, existingDigest) ===
    limousineProjectionFingerprint(nextProjection, entitled, nextDigest);

  if (unchanged && floor >= 1) {
    const prevUpdatedAt =
      typeof existingRecord?.updated_at === "string" && existingRecord.updated_at.trim()
        ? existingRecord.updated_at
        : now;
    return { source_revision: floor, updated_at: prevUpdatedAt, changed: false };
  }
  return { source_revision: floor + 1, updated_at: now, changed: true };
}

/// Stamp the entitlement + safe projection + monotonic revision onto a partner
/// public profile object (returns a new object; never mutates the input).
export function stampLimousineProjectionOnProfile({
  profile,
  entitled,
  projection,
  sourceRevision,
}) {
  const base = profile && typeof profile === "object" ? profile : {};
  const revision = toMonotonicInt(sourceRevision) || 1;
  return {
    ...base,
    limousine_entitled: entitled === true,
    limousine_projection: {
      ...(projection && typeof projection === "object" ? projection : {}),
      source_revision: revision,
    },
    source_revision: revision,
  };
}

/// Copies the sanitized limousine sub-document onto one public profile entry.
/// Other partners and non-limousine fields stay untouched.
export function applyLimousinePublicFieldsToProfileEntry(entry, stamped) {
  if (!entry || typeof entry !== "object") return entry;
  const src = stamped && typeof stamped === "object" ? stamped : {};
  const next = { ...entry };
  const proj =
    src.limousine_projection && typeof src.limousine_projection === "object"
      ? src.limousine_projection
      : {};
  const offers = Array.isArray(src.limousine_offers) ? src.limousine_offers : [];
  next.limousine_entitled = src.limousine_entitled === true;
  next.limousine_service_enabled =
    src.limousine_service_enabled === true || proj.limousine_service_enabled === true;
  next.limousine_available =
    src.limousine_available === true || proj.limousine_available === true;
  if (src.limousine_projection) next.limousine_projection = src.limousine_projection;
  next.limousine_offers = offers;
  if (src.limousine_hero_url) {
    next.limousine_hero_url = src.limousine_hero_url;
    next.limousine_hero_source = src.limousine_hero_source || "";
    next.limousine_hero_alignment = src.limousine_hero_alignment || "";
    next.limousine_hero_revision = src.limousine_hero_revision || 0;
  } else {
    delete next.limousine_hero_url;
    delete next.limousine_hero_source;
    delete next.limousine_hero_alignment;
    delete next.limousine_hero_revision;
  }
  if (src.source_revision != null) next.source_revision = src.source_revision;
  if (offers.length === 0) {
    next.limousine_available = false;
    if (next.limousine_projection && typeof next.limousine_projection === "object") {
      next.limousine_projection = {
        ...next.limousine_projection,
        limousine_available: false,
        published_offer_count: 0,
        reason:
          next.limousine_projection.reason === "eligible"
            ? "no_published_offer"
            : next.limousine_projection.reason,
      };
    }
  }
  return next;
}
