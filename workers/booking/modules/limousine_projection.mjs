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
export function buildLimousineProjection(profile, options = {}) {
  const p = profile && typeof profile === "object" ? profile : {};
  const evaluation = evaluateLimousineProviderEligibility(p);
  const vehicles = Array.isArray(p.vehicles) ? p.vehicles : [];
  const eligibleVehicleCount = vehicles.filter((v) => isEligibleLimousineVehicle(v)).length;
  const base = {
    limousine_service_enabled: companyEnabledLimousine(p),
    limousine_available: evaluation.eligible,
    eligible_vehicle_count: eligibleVehicleCount,
    reason: evaluation.reason,
  };
  if (!options || options.offers == null) return base;
  const safeOffers = buildSafePublicLimousineOffers(options.offers, {
    eligible: evaluation.eligible,
    knownVehicles: options.knownVehicles || [],
    knownClassIds: options.knownClassIds || [],
    readiness: evaluation.eligible,
  });
  return { ...base, published_offer_count: safeOffers.length };
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

/// Deterministic fingerprint of the safe projection + the entitlement input, so
/// an idempotent replay does not advance the revision but a real change does.
export function limousineProjectionFingerprint(projection, entitled) {
  const p = projection && typeof projection === "object" ? projection : {};
  return JSON.stringify([
    entitled === true,
    p.limousine_service_enabled === true,
    p.limousine_available === true,
    toMonotonicInt(p.eligible_vehicle_count),
    String(p.reason || ""),
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

  const unchanged =
    limousineProjectionFingerprint(existingProj, existingEntitled) ===
    limousineProjectionFingerprint(nextProjection, entitled);

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
