// Pure helpers for Fluxidi base + add-on cancellation cascade.
// Run tests: node --test workers/booking/modules/subscription_cancellation.test.mjs

function _qty(v) {
  const n = Math.trunc(Number(v) || 0);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function _str(v, max = 128) {
  if (v == null) return "";
  return String(v).trim().slice(0, max);
}

/**
 * Resolve cancel-at-period-end effective timestamp.
 * Precedence: current_period_end -> trial_ends_at -> now+30d.
 */
export function resolveCancellationEffectiveAt(profile, nowMs = Date.now()) {
  const periodEnd = _str(profile?.current_period_end, 48);
  const trialEnds = _str(profile?.trial_ends_at, 48);
  if (periodEnd && !Number.isNaN(Date.parse(periodEnd))) return periodEnd;
  if (trialEnds && !Number.isNaN(Date.parse(trialEnds))) return trialEnds;
  return new Date(nowMs + 30 * 24 * 60 * 60 * 1000).toISOString();
}

/**
 * Schedule cancel for recurring add-ons (vehicle/driver) onto the same
 * effective date. PDF packs are prepaid consumables and are NEVER cascaded.
 * Does not touch founder fields, max_*, purchased PDF credits, or Mollie ids.
 */
export function cascadeAddonCancellations(profile, {
  effectiveAt,
  requestedAt,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { profile, cascaded: false, summary: {} };
  }
  const eff = _str(effectiveAt, 48) || resolveCancellationEffectiveAt(profile);
  const req = _str(requestedAt, 48) || new Date().toISOString();

  const vehicleActive = _qty(profile.extra_vehicle_active_quantity);
  const driverActive = _qty(profile.extra_driver_active_quantity);

  const next = {
    ...profile,
    extra_vehicle_cancel_at_period_end_quantity: vehicleActive,
    extra_vehicle_cancel_requested_at: vehicleActive > 0 ? req : _str(profile.extra_vehicle_cancel_requested_at, 48),
    extra_vehicle_cancellation_effective_at: vehicleActive > 0 ? eff : _str(profile.extra_vehicle_cancellation_effective_at, 48),
    extra_vehicle_auto_renew: vehicleActive > 0 ? false : profile.extra_vehicle_auto_renew !== false,

    extra_driver_cancel_at_period_end_quantity: driverActive,
    extra_driver_cancel_requested_at: driverActive > 0 ? req : _str(profile.extra_driver_cancel_requested_at, 48),
    extra_driver_cancellation_effective_at: driverActive > 0 ? eff : _str(profile.extra_driver_cancellation_effective_at, 48),
    extra_driver_auto_renew: driverActive > 0 ? false : profile.extra_driver_auto_renew !== false,

    // PDF prepaid: never schedule cancellation from base cancel.
    pdf500_cancel_at_period_end_quantity: 0,
    pdf500_cancel_requested_at: "",
    pdf500_cancellation_effective_at: "",
    pdf1000_cancel_at_period_end_quantity: 0,
    pdf1000_cancel_requested_at: "",
    pdf1000_cancellation_effective_at: "",
    pdf5000_cancel_at_period_end_quantity: 0,
    pdf5000_cancel_requested_at: "",
    pdf5000_cancellation_effective_at: "",
  };

  const summary = {
    extra_vehicle: vehicleActive,
    extra_driver: driverActive,
    pdf500: 0,
    pdf1000: 0,
    pdf5000: 0,
  };
  const cascaded = vehicleActive + driverActive > 0;

  return { profile: next, cascaded, summary, effectiveAt: eff, requestedAt: req };
}

/**
 * Schedule base cancel-at-period-end and cascade add-ons.
 * Preserves founder lock fields. Does not call Mollie.
 */
export function scheduleBaseCancellation(profile, {
  nowIso,
  nowMs,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { ok: false, error: "missing_profile" };
  }
  const status = _str(profile.subscription_status || profile.status).toLowerCase();
  if (status !== "active" && status !== "trialing") {
    return { ok: false, error: "subscription_not_cancelable", status };
  }

  const already = profile.cancel_at_period_end === true;
  const now = _str(nowIso, 48) || new Date(nowMs || Date.now()).toISOString();
  const effectiveAt = already
    ? (_str(profile.cancellation_effective_at, 48) || resolveCancellationEffectiveAt(profile, nowMs || Date.now()))
    : resolveCancellationEffectiveAt(profile, nowMs || Date.now());

  let next = {
    ...profile,
    cancel_at_period_end: true,
    auto_renew: false,
    cancel_requested_at: already
      ? (_str(profile.cancel_requested_at, 48) || now)
      : now,
    cancellation_effective_at: effectiveAt,
    // Founder fields intentionally untouched.
  };

  const cascaded = cascadeAddonCancellations(next, {
    effectiveAt,
    requestedAt: now,
  });
  next = cascaded.profile;

  return {
    ok: true,
    already_scheduled: already,
    profile: next,
    effectiveAt,
    requestedAt: now,
    addon_cascade: cascaded.summary,
    // Founder proof for tests / callers.
    founder_preserved: {
      locked_price_cents: next.locked_price_cents,
      is_founder_customer: next.is_founder_customer === true,
      founder_slot_number: next.founder_slot_number,
    },
  };
}

/**
 * Clear base cancellation + provider-cancel + dunning lifecycle fields after a
 * verified paid first activation / reactivation. Pure — does not touch period,
 * price, founder, provider ids, or add-on quantities.
 *
 * Required so a later materializeBaseCancellation pass cannot flip a newly
 * activated profile back to cancelled when the prior effective date is past.
 */
export function clearCancellationLifecycleOnPaidActivation(profile) {
  if (!profile || typeof profile !== "object") return profile;
  return {
    ...profile,
    subscription_status: "active",
    status: "active",
    cancel_at_period_end: false,
    auto_renew: true,
    cancellation_effective_at: "",
    cancel_requested_at: "",
    cancelled_at: "",
    provider_cancel_pending: false,
    provider_cancel_last_error: "",
    provider_cancel_attempted_at: "",
    provider_cancel_completed_at: "",
    // Dunning markers cleared on the same successful paid path.
    past_due_since: "",
    suspended_at: "",
  };
}

/**
 * True when a profile still carries base-cancel lifecycle that would let
 * materializeBaseCancellation undo a matching paid activation.
 */
export function needsPaidActivationCancellationHeal(profile, {
  activationId = "",
} = {}) {
  if (!profile || typeof profile !== "object") return false;
  const act = _str(activationId, 80);
  const profileAct = _str(profile.activation_id, 80);
  if (!act || !profileAct || act !== profileAct) return false;
  if (profile.cancel_at_period_end === true) return true;
  if (profile.provider_cancel_pending === true) return true;
  if (_str(profile.cancellation_effective_at, 48)) return true;
  if (_str(profile.cancel_requested_at, 48)) return true;
  if (_str(profile.cancelled_at, 48)) return true;
  if (profile.auto_renew === false) return true;
  const status = _str(profile.subscription_status || profile.status).toLowerCase();
  if (status === "cancelled" || status === "canceled") return true;
  return false;
}

/**
 * Whether a verified Mollie recurring payment must be ignored because the
 * company already scheduled cancellation / disabled renew.
 */
export function shouldRejectRecurringAfterCancel(profile, {
  nowMs = Date.now(),
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { reject: false, reason: "missing_profile" };
  }
  if (profile.cancel_at_period_end === true) {
    return { reject: true, reason: "cancel_at_period_end" };
  }
  if (profile.auto_renew === false) {
    return { reject: true, reason: "auto_renew_false" };
  }
  const status = _str(profile.subscription_status || profile.status).toLowerCase();
  if (status === "cancelled" || status === "canceled") {
    return { reject: true, reason: "already_cancelled" };
  }
  const effectiveAt = _str(profile.cancellation_effective_at, 48);
  const effMs = effectiveAt ? Date.parse(effectiveAt) : NaN;
  if (!Number.isNaN(effMs) && nowMs >= effMs && profile.cancel_at_period_end === true) {
    return { reject: true, reason: "past_effective_cancel" };
  }
  return { reject: false, reason: "" };
}

/**
 * Pure materialize of a due base cancellation. Does not save KV.
 * Sets status cancelled, zeroes renew flags, clears provider_cancel_pending.
 * Does NOT release founder slot / locked price.
 * Caller should still run addon materializers for entitlement reductions.
 */
export function materializeBaseCancellation(profile, {
  nowMs = Date.now(),
  nowIso,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { changed: false, profile, applied: false };
  }
  if (profile.cancel_at_period_end !== true) {
    return { changed: false, profile, applied: false };
  }
  const effectiveAt = _str(profile.cancellation_effective_at, 48);
  const effMs = effectiveAt ? Date.parse(effectiveAt) : NaN;
  if (Number.isNaN(effMs) || nowMs < effMs) {
    return { changed: false, profile, applied: false };
  }

  const status = _str(profile.subscription_status || profile.status).toLowerCase();
  if (status === "cancelled" || status === "canceled") {
    // Already materialised; still clear pending provider flag if set.
    if (profile.provider_cancel_pending === true) {
      return {
        changed: true,
        applied: false,
        profile: {
          ...profile,
          provider_cancel_pending: false,
          auto_renew: false,
        },
      };
    }
    return { changed: false, profile, applied: false };
  }

  const now = _str(nowIso, 48) || new Date(nowMs).toISOString();
  return {
    changed: true,
    applied: true,
    profile: {
      ...profile,
      subscription_status: "cancelled",
      status: "cancelled",
      cancelled_at: _str(profile.cancelled_at, 48) || now,
      auto_renew: false,
      cancel_at_period_end: true,
      provider_cancel_pending: false,
      // Keep cancellation_effective_at for UI/history.
      // Founder fields untouched.
    },
  };
}

/**
 * Apply Mollie DELETE outcome onto the scheduled-cancel profile.
 * success clears pending; failure keeps schedule + pending for retry.
 */
export function applyProviderCancelOutcome(profile, {
  ok,
  errorCode,
  nowIso,
  subscriptionId,
} = {}) {
  if (!profile || typeof profile !== "object") {
    return { profile, provider_ok: false };
  }
  const now = _str(nowIso, 48) || new Date().toISOString();
  if (ok) {
    return {
      profile: {
        ...profile,
        provider_cancel_pending: false,
        provider_cancel_last_error: "",
        provider_cancel_attempted_at: now,
        provider_cancel_completed_at: now,
        provider_subscription_id: _str(subscriptionId || profile.provider_subscription_id, 128),
      },
      provider_ok: true,
    };
  }
  return {
    profile: {
      ...profile,
      provider_cancel_pending: true,
      provider_cancel_last_error: _str(errorCode, 200) || "provider_cancel_failed",
      provider_cancel_attempted_at: now,
    },
    provider_ok: false,
  };
}

/** True when a Mollie DELETE (or retry) should be attempted. */
export function needsProviderCancel(profile) {
  if (!profile || typeof profile !== "object") return false;
  if (profile.cancel_at_period_end !== true) return false;
  const subId = _str(profile.provider_subscription_id, 128);
  if (!subId.startsWith("sub_")) return false;
  if (profile.provider_cancel_pending === true) return true;
  // Fresh schedule: no completed cancel yet.
  if (!_str(profile.provider_cancel_completed_at, 48)) return true;
  return false;
}

export function summarizeActiveAddonsForUi(profile) {
  return {
    extra_vehicle_active_quantity: _qty(profile?.extra_vehicle_active_quantity),
    extra_driver_active_quantity: _qty(profile?.extra_driver_active_quantity),
    pdf500_active_quantity: _qty(profile?.pdf500_active_quantity),
    pdf1000_active_quantity: _qty(profile?.pdf1000_active_quantity),
    pdf5000_active_quantity: _qty(profile?.pdf5000_active_quantity),
  };
}
