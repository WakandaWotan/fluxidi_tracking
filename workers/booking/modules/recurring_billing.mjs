// Consolidated recurring billing: base + vehicle + driver on one Mollie sub.
// PDF packs are never included. Pure helpers — no I/O.

function _qty(v) {
  const n = Math.trunc(Number(v) || 0);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function _cents(v) {
  const n = Math.trunc(Number(v));
  return Number.isFinite(n) && n >= 0 ? n : null;
}

function _str(v, max = 48) {
  if (v == null) return "";
  return String(v).trim().slice(0, max);
}

/** Default BE catalog units; callers should pass market catalog when known. */
export const DEFAULT_EXTRA_VEHICLE_MONTHLY_CENTS = 1900;
export const DEFAULT_EXTRA_DRIVER_MONTHLY_CENTS = 900;

/**
 * Future entitled recurring addon quantities = active − scheduled cancel.
 * Never negative. PDF packs are excluded by design.
 */
export function futureRecurringAddonQuantities(profile) {
  const vehicleActive = _qty(profile?.extra_vehicle_active_quantity);
  const vehicleCancel = _qty(profile?.extra_vehicle_cancel_at_period_end_quantity);
  const driverActive = _qty(profile?.extra_driver_active_quantity);
  const driverCancel = _qty(profile?.extra_driver_cancel_at_period_end_quantity);
  return {
    vehicle_qty: Math.max(0, vehicleActive - vehicleCancel),
    driver_qty: Math.max(0, driverActive - driverCancel),
  };
}

/**
 * Consolidated future Mollie renewal amount in cents.
 * locked base + (€19 × vehicles) + (€9 × drivers). PDF never included.
 */
export function computeConsolidatedRecurringCents({
  lockedPriceCents,
  vehicleQty = 0,
  driverQty = 0,
  vehicleUnitCents = DEFAULT_EXTRA_VEHICLE_MONTHLY_CENTS,
  driverUnitCents = DEFAULT_EXTRA_DRIVER_MONTHLY_CENTS,
} = {}) {
  const base = _cents(lockedPriceCents);
  if (base === null) return null;
  const v = Math.max(0, Math.trunc(Number(vehicleQty) || 0));
  const d = Math.max(0, Math.trunc(Number(driverQty) || 0));
  const vu = Math.max(0, Math.trunc(Number(vehicleUnitCents) || 0));
  const du = Math.max(0, Math.trunc(Number(driverUnitCents) || 0));
  return base + v * vu + d * du;
}

export function computeConsolidatedRecurringCentsFromProfile(profile, {
  vehicleUnitCents = DEFAULT_EXTRA_VEHICLE_MONTHLY_CENTS,
  driverUnitCents = DEFAULT_EXTRA_DRIVER_MONTHLY_CENTS,
} = {}) {
  const q = futureRecurringAddonQuantities(profile);
  return computeConsolidatedRecurringCents({
    lockedPriceCents: profile?.locked_price_cents,
    vehicleQty: q.vehicle_qty,
    driverQty: q.driver_qty,
    vehicleUnitCents,
    driverUnitCents,
  });
}

/**
 * Deterministic proration for mid-period add-on activation.
 * Uses remaining ms / period ms × monthlyCents, Math.round (half-up for ≥0).
 * Returns 0 when now is at/after period end; full monthly when now ≤ period start.
 */
export function computeProrationCents({
  monthlyCents,
  periodStartIso,
  periodEndIso,
  nowMs = Date.now(),
} = {}) {
  const monthly = _cents(monthlyCents);
  if (monthly === null || monthly === 0) return 0;
  const startMs = Date.parse(_str(periodStartIso, 48));
  const endMs = Date.parse(_str(periodEndIso, 48));
  if (!Number.isFinite(startMs) || !Number.isFinite(endMs) || endMs <= startMs) {
    return null;
  }
  if (nowMs >= endMs) return 0;
  if (nowMs <= startMs) return monthly;
  const totalMs = endMs - startMs;
  const remainingMs = endMs - nowMs;
  return Math.round((monthly * remainingMs) / totalMs);
}

/** Mollie amount value string from cents, e.g. 8800 → "88.00". */
export function centsToMollieAmountValue(cents) {
  const n = _cents(cents);
  if (n === null) return null;
  return (n / 100).toFixed(2);
}

/**
 * Schedule cancel of exactly one vehicle. Capacity unchanged until materialize.
 * Pure — caller syncs Mollie future amount from futureRecurringAddonQuantities.
 */
export function scheduleCancelOneExtraVehicle(profile, {
  nowIso,
  effectiveAt,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  const active = _qty(profile.extra_vehicle_active_quantity);
  const scheduled = _qty(profile.extra_vehicle_cancel_at_period_end_quantity);
  const cancelable = Math.max(0, active - scheduled);
  if (cancelable < 1) {
    return { ok: false, error: "no_extra_vehicle_to_cancel" };
  }
  const now = _str(nowIso, 48) || new Date().toISOString();
  const eff = _str(effectiveAt, 48) || _str(profile.current_period_end, 48);
  if (!eff) return { ok: false, error: "missing_effective_at" };
  return {
    ok: true,
    profile: {
      ...profile,
      extra_vehicle_cancel_at_period_end_quantity: scheduled + 1,
      extra_vehicle_cancel_requested_at: now,
      extra_vehicle_cancellation_effective_at: eff,
      extra_vehicle_auto_renew: false,
    },
  };
}

export function undoCancelOneExtraVehicle(profile) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  const scheduled = _qty(profile.extra_vehicle_cancel_at_period_end_quantity);
  if (scheduled < 1) {
    return { ok: true, already: true, profile };
  }
  const nextQty = scheduled - 1;
  return {
    ok: true,
    already: false,
    profile: {
      ...profile,
      extra_vehicle_cancel_at_period_end_quantity: nextQty,
      extra_vehicle_cancel_requested_at: nextQty > 0
        ? _str(profile.extra_vehicle_cancel_requested_at, 48)
        : "",
      extra_vehicle_cancellation_effective_at: nextQty > 0
        ? _str(profile.extra_vehicle_cancellation_effective_at, 48)
        : "",
      extra_vehicle_auto_renew: nextQty > 0 ? false : true,
    },
  };
}

export function scheduleCancelOneExtraDriver(profile, {
  nowIso,
  effectiveAt,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  const active = _qty(profile.extra_driver_active_quantity);
  const scheduled = _qty(profile.extra_driver_cancel_at_period_end_quantity);
  const cancelable = Math.max(0, active - scheduled);
  if (cancelable < 1) {
    return { ok: false, error: "no_extra_driver_to_cancel" };
  }
  const now = _str(nowIso, 48) || new Date().toISOString();
  const eff = _str(effectiveAt, 48) || _str(profile.current_period_end, 48);
  if (!eff) return { ok: false, error: "missing_effective_at" };
  return {
    ok: true,
    profile: {
      ...profile,
      extra_driver_cancel_at_period_end_quantity: scheduled + 1,
      extra_driver_cancel_requested_at: now,
      extra_driver_cancellation_effective_at: eff,
      extra_driver_auto_renew: false,
    },
  };
}

export function undoCancelOneExtraDriver(profile) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  const scheduled = _qty(profile.extra_driver_cancel_at_period_end_quantity);
  if (scheduled < 1) {
    return { ok: true, already: true, profile };
  }
  const nextQty = scheduled - 1;
  return {
    ok: true,
    already: false,
    profile: {
      ...profile,
      extra_driver_cancel_at_period_end_quantity: nextQty,
      extra_driver_cancel_requested_at: nextQty > 0
        ? _str(profile.extra_driver_cancel_requested_at, 48)
        : "",
      extra_driver_cancellation_effective_at: nextQty > 0
        ? _str(profile.extra_driver_cancellation_effective_at, 48)
        : "",
      extra_driver_auto_renew: nextQty > 0 ? false : true,
    },
  };
}

/**
 * Undo base cancel-at-period-end before effective date.
 * Does not touch addon quantities or Mollie ids (caller restores Mollie).
 */
export function undoBaseCancellation(profile, { nowMs = Date.now() } = {}) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  if (profile.cancel_at_period_end !== true) {
    return { ok: true, already: true, profile };
  }
  const eff = _str(profile.cancellation_effective_at, 48);
  const effMs = eff ? Date.parse(eff) : NaN;
  if (!Number.isNaN(effMs) && nowMs >= effMs) {
    return { ok: false, error: "reactivation_required" };
  }
  const status = _str(profile.subscription_status || profile.status).toLowerCase();
  if (status === "cancelled" || status === "canceled") {
    return { ok: false, error: "reactivation_required" };
  }
  return {
    ok: true,
    already: false,
    profile: {
      ...profile,
      cancel_at_period_end: false,
      auto_renew: true,
      cancel_requested_at: "",
      cancellation_effective_at: "",
      cancelled_at: "",
      provider_cancel_pending: false,
      provider_cancel_last_error: "",
    },
  };
}
