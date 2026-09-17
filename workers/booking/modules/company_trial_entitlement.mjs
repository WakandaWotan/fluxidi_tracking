/**
 * Personal trial entitlements per tenant+company.
 *
 * Separate from paid add-ons and account lifecycle. A platform-admin override
 * may raise the effective vehicle/driver totals while it is still in date.
 * It never lowers paid capacity, never changes subscription_status, and never
 * resumes a paused/blocked/closed account.
 *
 * After trial_ends_at the override stops applying. Existing vehicles and
 * drivers stay; new adds are refused. If usage is still above the then
 * effective limit, new rides are refused until the company deactivates
 * down to that limit. No auto-payment, deletion, ride cut, or vehicle pick.
 */

import {
  evaluateFleetCapacityWrite,
  resolveAuthoritativeVehicleCapacity,
} from "./fleet_vehicle_capacity.mjs";

export const TRIAL_ENTITLEMENT_KEY_SUFFIX = "trial_entitlement:v1";
export const DRIVER_LIMIT_REACHED = "driver_limit_reached";
export const TRIAL_CAPACITY_EXPIRED = "trial_capacity_expired";
export const MAX_TRIAL_VEHICLES = 99;
export const MAX_TRIAL_DRIVERS = 297;
export const DEFAULT_TRIAL_VEHICLES = 1;
export const DEFAULT_TRIAL_DRIVERS = 3;

function text(value) {
  return value == null ? "" : String(value).trim();
}

function truncNonNeg(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.trunc(n));
}

function clampAllowed(value, fallback, max) {
  const n = truncNonNeg(value, fallback);
  if (n < 1) return fallback;
  return Math.min(max, n);
}

export function trialEntitlementKey(tenantId, companyId) {
  const tenant = text(tenantId);
  const company = text(companyId);
  if (!tenant || !company) return "";
  return `tenant:${tenant}:company:${company}:${TRIAL_ENTITLEMENT_KEY_SUFFIX}`;
}

export function isTrialOverrideActive(record, now = new Date()) {
  if (!record || typeof record !== "object" || Array.isArray(record)) return false;
  const ends = Date.parse(record.trial_ends_at || "");
  if (!Number.isFinite(ends)) return false;
  const clock = now instanceof Date ? now.getTime() : Date.parse(now) || Date.now();
  return ends > clock;
}

export function resolveAuthoritativeDriverCapacity(profile = {}) {
  const includedVehiclesRaw = profile?.included_vehicles ?? profile?.includedVehicles;
  const includedVehicles = includedVehiclesRaw == null || includedVehiclesRaw === ""
    ? 1
    : truncNonNeg(includedVehiclesRaw, 1) || 1;
  const includedDrivers = Math.max(DEFAULT_TRIAL_DRIVERS, includedVehicles * DEFAULT_TRIAL_DRIVERS);
  const extraVehicles = truncNonNeg(
    profile?.extra_vehicle_active_quantity ?? profile?.extraVehicleActiveQuantity,
    0,
  );
  const extraDrivers = truncNonNeg(
    profile?.extra_driver_active_quantity ?? profile?.extraDriverActiveQuantity,
    0,
  );
  const status = text(profile?.status ?? profile?.subscription_status).toLowerCase();
  const paidFromExtras = includedDrivers + (extraVehicles * DEFAULT_TRIAL_DRIVERS) + extraDrivers;
  if (extraVehicles > 0 || extraDrivers > 0) return paidFromExtras;
  if (status === "active" || status === "past_due") {
    const maxD = truncNonNeg(profile?.max_drivers ?? profile?.maxDrivers, 0);
    if (maxD > includedDrivers) return maxD;
  }
  const stored = truncNonNeg(profile?.max_drivers ?? profile?.maxDrivers, 0);
  if (status === "trialing" || status === "trial" || status === "trial_active") {
    return includedDrivers;
  }
  return stored > 0 ? stored : includedDrivers;
}

export function evaluateDriverCapacityWrite({
  existingActiveIds = [],
  incomingActiveIds = [],
  allowed,
} = {}) {
  const decision = evaluateFleetCapacityWrite({
    existingActiveIds,
    incomingActiveIds,
    allowed,
  });
  if (!decision.ok) return { ...decision, error: DRIVER_LIMIT_REACHED };
  return decision;
}

export function resolvePaidVehicleCapacity(profile = {}) {
  return resolveAuthoritativeVehicleCapacity(profile);
}

export function resolvePaidDriverCapacity(profile = {}) {
  return resolveAuthoritativeDriverCapacity(profile);
}

export function resolveEffectiveVehicleCapacity(profile = {}, override = null, now = new Date()) {
  const paid = resolvePaidVehicleCapacity(profile);
  if (!isTrialOverrideActive(override, now)) return paid;
  const personal = clampAllowed(override.vehicles_allowed, paid, MAX_TRIAL_VEHICLES);
  return Math.max(paid, personal);
}

export function resolveEffectiveDriverCapacity(profile = {}, override = null, now = new Date()) {
  const paid = resolvePaidDriverCapacity(profile);
  if (!isTrialOverrideActive(override, now)) return paid;
  const personal = clampAllowed(override.drivers_allowed, paid, MAX_TRIAL_DRIVERS);
  return Math.max(paid, personal);
}

export function trialExpiryConsequences({
  afterExpiryVehicles,
  afterExpiryDrivers,
  currentVehicles = 0,
  currentDrivers = 0,
} = {}) {
  return {
    after_expiry_vehicles: afterExpiryVehicles,
    after_expiry_drivers: afterExpiryDrivers,
    vehicles_over_limit: currentVehicles > afterExpiryVehicles,
    drivers_over_limit: currentDrivers > afterExpiryDrivers,
    no_auto_payment: true,
    no_vehicle_deletion: true,
    no_driver_deletion: true,
    no_ride_interruption: true,
    existing_overrun_preserved: true,
    new_adds_refused_when_over: true,
    new_rides_refused_when_over: true,
    company_chooses_active_fleet: true,
    account_unchanged: true,
    paid_rights_unchanged: true,
  };
}

export function summarizeTrialEntitlement({
  profile = {},
  override = null,
  usage = {},
  accountState = "active",
  now = new Date(),
} = {}) {
  const paidVehicles = resolvePaidVehicleCapacity(profile);
  const paidDrivers = resolvePaidDriverCapacity(profile);
  const active = isTrialOverrideActive(override, now);
  const effectiveVehicles = resolveEffectiveVehicleCapacity(profile, override, now);
  const effectiveDrivers = resolveEffectiveDriverCapacity(profile, override, now);
  const profileEnds = text(profile?.trial_ends_at ?? profile?.trialEndsAt);
  const overrideEnds = text(override?.trial_ends_at);
  const trialEndsAt = active ? (overrideEnds || profileEnds) : profileEnds;
  const source = active
    ? "personal_trial"
    : (paidVehicles > DEFAULT_TRIAL_VEHICLES || paidDrivers > DEFAULT_TRIAL_DRIVERS ? "paid" : "default_trial");
  const vehiclesUsed = truncNonNeg(usage.vehicles, 0);
  const driversUsed = truncNonNeg(usage.drivers, 0);
  return {
    account_state: text(accountState) || "active",
    subscription_status: text(profile?.status ?? profile?.subscription_status) || "trialing",
    paid: { vehicles: paidVehicles, drivers: paidDrivers },
    override: override && typeof override === "object"
      ? {
          active,
          vehicles_allowed: truncNonNeg(override.vehicles_allowed, 0),
          drivers_allowed: truncNonNeg(override.drivers_allowed, 0),
          trial_ends_at: overrideEnds || null,
          reason: text(override.reason) || null,
          actor_id: text(override.actor_id) || null,
          updated_at: text(override.updated_at) || null,
        }
      : null,
    effective: {
      vehicles: effectiveVehicles,
      drivers: effectiveDrivers,
      trial_ends_at: trialEndsAt || null,
      source,
      personal_active: active,
    },
    usage: { vehicles: vehiclesUsed, drivers: driversUsed },
    expiry: trialExpiryConsequences({
      afterExpiryVehicles: paidVehicles,
      afterExpiryDrivers: paidDrivers,
      currentVehicles: vehiclesUsed,
      currentDrivers: driversUsed,
    }),
    subscription_untouched: true,
    account_untouched: true,
  };
}

export function applyTrialOverlayToSubscriptionProfile(profile = {}, override = null, now = new Date()) {
  const effectiveVehicles = resolveEffectiveVehicleCapacity(profile, override, now);
  const effectiveDrivers = resolveEffectiveDriverCapacity(profile, override, now);
  const active = isTrialOverrideActive(override, now);
  const profileEnds = text(profile?.trial_ends_at ?? profile?.trialEndsAt);
  const effectiveEnds = resolveEffectiveTrialEndsAt(profile, override, now);
  return {
    ...profile,
    trial_ends_at: effectiveEnds || profileEnds || profile?.trial_ends_at,
    trialEndsAt: effectiveEnds || profileEnds || profile?.trialEndsAt,
    profile_trial_ends_at: profileEnds || null,
    effective_max_vehicles: effectiveVehicles,
    effective_max_drivers: effectiveDrivers,
    effective_trial_ends_at: effectiveEnds || null,
    trial_override: {
      active,
      vehicles_allowed: active ? truncNonNeg(override?.vehicles_allowed, 0) : 0,
      drivers_allowed: active ? truncNonNeg(override?.drivers_allowed, 0) : 0,
      trial_ends_at: active ? (text(override?.trial_ends_at) || null) : null,
    },
  };
}

export function resolveEffectiveTrialEndsAt(profile = {}, override = null, now = new Date()) {
  const profileEnds = text(profile?.trial_ends_at ?? profile?.trialEndsAt);
  if (isTrialOverrideActive(override, now)) {
    return text(override?.trial_ends_at) || profileEnds || null;
  }
  return profileEnds || null;
}

export function evaluateTrialCapacityForNewWork({
  profile = {},
  override = null,
  usage = {},
  accountState = "active",
  now = new Date(),
} = {}) {
  const state = text(accountState).toLowerCase();
  if (state === "paused" || state === "blocked" || state === "closed" || state === "archived") {
    return { ok: true, deferred: "account" };
  }
  if (!override || typeof override !== "object" || Array.isArray(override)) {
    return { ok: true, skipped: "no_personal_override" };
  }
  const effectiveVehicles = resolveEffectiveVehicleCapacity(profile, override, now);
  const effectiveDrivers = resolveEffectiveDriverCapacity(profile, override, now);
  const usedVehicles = truncNonNeg(usage.vehicles, 0);
  const usedDrivers = truncNonNeg(usage.drivers, 0);
  if (usedVehicles <= effectiveVehicles && usedDrivers <= effectiveDrivers) {
    return {
      ok: true,
      within_limit: true,
      personal_active: isTrialOverrideActive(override, now),
      effective_vehicles: effectiveVehicles,
      effective_drivers: effectiveDrivers,
    };
  }
  return {
    ok: false,
    error: TRIAL_CAPACITY_EXPIRED,
    personal_active: isTrialOverrideActive(override, now),
    effective_vehicles: effectiveVehicles,
    effective_drivers: effectiveDrivers,
    used_vehicles: usedVehicles,
    used_drivers: usedDrivers,
    no_auto_payment: true,
    no_vehicle_deletion: true,
    no_driver_deletion: true,
    no_ride_interruption: true,
    company_chooses_active_fleet: true,
  };
}

export function previewTrialEntitlementWrite({
  current,
  nextVehicles,
  nextDrivers,
  nextEndsAt,
  reason = "",
  now = new Date(),
} = {}) {
  const paidVehicles = current?.paid?.vehicles ?? DEFAULT_TRIAL_VEHICLES;
  const paidDrivers = current?.paid?.drivers ?? DEFAULT_TRIAL_DRIVERS;
  const requestedVehicles = clampAllowed(nextVehicles, paidVehicles, MAX_TRIAL_VEHICLES);
  const requestedDrivers = clampAllowed(nextDrivers, paidDrivers, MAX_TRIAL_DRIVERS);
  const effectiveVehicles = Math.max(paidVehicles, requestedVehicles);
  const effectiveDrivers = Math.max(paidDrivers, requestedDrivers);
  const usedVehicles = current?.usage?.vehicles ?? 0;
  const usedDrivers = current?.usage?.drivers ?? 0;
  const paidFloorApplied = requestedVehicles < paidVehicles || requestedDrivers < paidDrivers;
  const consequences = [];
  consequences.push("Na de einddatum gelden opnieuw de betaalde of standaardproefrechten. Bestaande voertuigen en chauffeurs blijven staan.");
  consequences.push("Geen automatische betaling, geen verwijdering van voertuigen of chauffeurs, en geen onderbreking van een lopende rit.");
  if (current?.account_state && current.account_state !== "active") {
    consequences.push("Deze aanpassing activeert een gepauzeerd, geblokkeerd of gesloten account niet.");
  }
  if (paidFloorApplied) {
    consequences.push(`Betaalde rechten blijven ${paidVehicles} voertuig(en) en ${paidDrivers} chauffeur(s). Een proefaanpassing verlaagt die niet.`);
  }
  if (usedVehicles > effectiveVehicles) {
    consequences.push(`Er zijn nu ${usedVehicles} voertuigen actief, boven de nieuwe limiet van ${effectiveVehicles}. Bestaande voertuigen blijven; nieuwe toevoegingen worden geweigerd.`);
  }
  if (usedDrivers > effectiveDrivers) {
    consequences.push(`Er zijn nu ${usedDrivers} chauffeurs actief, boven de nieuwe limiet van ${effectiveDrivers}. Bestaande chauffeurs blijven; nieuwe toevoegingen worden geweigerd.`);
  }
  if (usedVehicles > effectiveVehicles || usedDrivers > effectiveDrivers) {
    consequences.push("Nieuwe ritten starten wordt geweigerd tot het gebruik weer binnen de limiet valt. Lopende ritten blijven afhandelbaar. U kiest welke voertuigen en chauffeurs actief blijven; Fluxidi selecteert geen klantvoertuigen.");
  }
  const endsMs = Date.parse(text(nextEndsAt) || "");
  const clock = now instanceof Date ? now.getTime() : Date.parse(now) || Date.now();
  if (Number.isFinite(endsMs) && endsMs <= clock) {
    consequences.push("De gekozen einddatum is al verstreken of is nu. Persoonlijke proefrechten gelden daarna niet meer; betaalde of standaardproefrechten blijven.");
  }
  return {
    old: {
      vehicles: current?.effective?.vehicles ?? paidVehicles,
      drivers: current?.effective?.drivers ?? paidDrivers,
      trial_ends_at: current?.effective?.trial_ends_at || null,
    },
    requested: {
      vehicles: requestedVehicles,
      drivers: requestedDrivers,
      trial_ends_at: text(nextEndsAt) || null,
      reason: text(reason) || null,
    },
    next: {
      vehicles: effectiveVehicles,
      drivers: effectiveDrivers,
      trial_ends_at: text(nextEndsAt) || null,
    },
    paid_floor_applied: paidFloorApplied,
    consequences,
  };
}

export function normalizeTrialEntitlementWrite({
  vehiclesAllowed,
  driversAllowed,
  trialEndsAt,
  reason,
  actorId,
  tenantId,
  companyId,
  companyCode,
  now = new Date(),
} = {}) {
  const ends = text(trialEndsAt);
  const parsed = Date.parse(ends);
  if (!ends || !Number.isFinite(parsed)) {
    return { ok: false, error: "trial_ends_at_required" };
  }
  const vehicles = clampAllowed(vehiclesAllowed, 0, MAX_TRIAL_VEHICLES);
  const drivers = clampAllowed(driversAllowed, 0, MAX_TRIAL_DRIVERS);
  if (vehicles < 1) return { ok: false, error: "vehicles_allowed_required" };
  if (drivers < 1) return { ok: false, error: "drivers_allowed_required" };
  return {
    ok: true,
    record: {
      vehicles_allowed: vehicles,
      drivers_allowed: drivers,
      trial_ends_at: new Date(parsed).toISOString(),
      reason: text(reason).slice(0, 240) || null,
      actor_id: text(actorId) || "platform_admin",
      updated_at: now instanceof Date ? now.toISOString() : text(now) || new Date().toISOString(),
      tenant_id: text(tenantId),
      company_id: text(companyId),
      company_code: text(companyCode) || null,
      subscription_status_untouched: true,
      account_untouched: true,
    },
  };
}

export async function loadTrialEntitlement(kv, { tenantId = "", companyId = "" } = {}) {
  const key = trialEntitlementKey(tenantId, companyId);
  if (!kv || !key) return null;
  const raw = await kv.get(key, { type: "json" });
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  return raw;
}

export async function saveTrialEntitlement(kv, record) {
  const key = trialEntitlementKey(record?.tenant_id, record?.company_id);
  if (!kv || !key) return { ok: false, error: "kv_unavailable" };
  await kv.put(key, JSON.stringify(record));
  return { ok: true, record };
}

export function driverLimitMessage() {
  return "Tijdens de proefperiode zijn drie chauffeurs inbegrepen. Extra capaciteit vereist een betaalde uitbreiding of een persoonlijke proefaanpassing.";
}

export function activeDriverIdsFromIndex(index = {}) {
  const deleted = index?.deleted_drivers || index?.deletedDrivers || {};
  const drivers = index?.drivers && typeof index.drivers === "object" ? index.drivers : {};
  return Object.keys(drivers).filter((id) => {
    if (!id || Object.prototype.hasOwnProperty.call(deleted, id)) return false;
    const row = drivers[id] || {};
    return row.is_active !== false && row.isActive !== false;
  });
}

export function activeVehicleIdsFromFleet(fleet = {}) {
  const vehicles = Array.isArray(fleet?.vehicles) ? fleet.vehicles : (Array.isArray(fleet) ? fleet : []);
  const deleted = fleet?.deletedVehicleIds || fleet?.deleted_vehicle_ids || {};
  return vehicles
    .filter((row) => {
      const id = text(row?.vehicle_id ?? row?.vehicleId ?? row?.id);
      if (!id || Object.prototype.hasOwnProperty.call(deleted, id)) return false;
      return row?.is_active !== false && row?.isActive !== false;
    })
    .map((row) => text(row?.vehicle_id ?? row?.vehicleId ?? row?.id));
}
