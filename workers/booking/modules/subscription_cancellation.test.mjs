// Subscription base + add-on cancellation cascade helpers.
// Run: node --test workers/booking/modules/subscription_cancellation.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  resolveCancellationEffectiveAt,
  cascadeAddonCancellations,
  scheduleBaseCancellation,
  shouldRejectRecurringAfterCancel,
  materializeBaseCancellation,
  applyProviderCancelOutcome,
  needsProviderCancel,
  summarizeActiveAddonsForUi,
  clearCancellationLifecycleOnPaidActivation,
  needsPaidActivationCancellationHeal,
} from "./subscription_cancellation.mjs";

/** Mirrors worker reconcile already_exists guard (sub_… present → no second create). */
function recurringCreateWouldNoop(profile) {
  const id = String(profile?.provider_subscription_id || "").trim();
  return id.startsWith("sub_");
}

function baseProfile(extra = {}) {
  return {
    subscription_status: "active",
    status: "active",
    current_period_end: "2026-09-01T00:00:00.000Z",
    auto_renew: true,
    cancel_at_period_end: false,
    locked_price_cents: 5900,
    is_founder_customer: true,
    founder_slot_number: 12,
    included_vehicles: 1,
    max_vehicles: 2,
    max_drivers: 7,
    extra_vehicle_active_quantity: 0,
    extra_driver_active_quantity: 0,
    pdf500_active_quantity: 0,
    pdf1000_active_quantity: 0,
    pdf5000_active_quantity: 0,
    pdf_monthly_allowance: 0,
    provider_customer_id: "cst_test",
    provider_subscription_id: "sub_test",
    ...extra,
  };
}

test("1. base cancellation with no add-ons", () => {
  const r = scheduleBaseCancellation(baseProfile(), {
    nowIso: "2026-08-12T10:00:00.000Z",
  });
  assert.equal(r.ok, true);
  assert.equal(r.profile.cancel_at_period_end, true);
  assert.equal(r.profile.auto_renew, false);
  assert.equal(r.effectiveAt, "2026-09-01T00:00:00.000Z");
  assert.equal(r.addon_cascade.extra_vehicle, 0);
  assert.equal(r.founder_preserved.locked_price_cents, 5900);
});

test("2. base cancellation with vehicle add-on cascades qty", () => {
  const r = scheduleBaseCancellation(
    baseProfile({ extra_vehicle_active_quantity: 2 }),
    { nowIso: "2026-08-12T10:00:00.000Z" },
  );
  assert.equal(r.ok, true);
  assert.equal(r.profile.extra_vehicle_cancel_at_period_end_quantity, 2);
  assert.equal(
    r.profile.extra_vehicle_cancellation_effective_at,
    "2026-09-01T00:00:00.000Z",
  );
  assert.equal(r.profile.extra_vehicle_auto_renew, false);
  assert.equal(r.profile.max_vehicles, 2); // unchanged until materialize
});

test("3. base cancellation with PDF add-on cascades all bundles", () => {
  const r = scheduleBaseCancellation(
    baseProfile({
      pdf500_active_quantity: 1,
      pdf1000_active_quantity: 2,
      pdf5000_active_quantity: 1,
      pdf_monthly_allowance: 7500,
    }),
    { nowIso: "2026-08-12T10:00:00.000Z" },
  );
  assert.equal(r.profile.pdf500_cancel_at_period_end_quantity, 1);
  assert.equal(r.profile.pdf1000_cancel_at_period_end_quantity, 2);
  assert.equal(r.profile.pdf5000_cancel_at_period_end_quantity, 1);
  assert.equal(r.profile.pdf_monthly_allowance, 7500);
});

test("4. base cancellation with both add-on types", () => {
  const r = scheduleBaseCancellation(
    baseProfile({
      extra_vehicle_active_quantity: 1,
      extra_driver_active_quantity: 2,
      pdf5000_active_quantity: 1,
    }),
  );
  assert.equal(r.addon_cascade.extra_vehicle, 1);
  assert.equal(r.addon_cascade.extra_driver, 2);
  assert.equal(r.addon_cascade.pdf5000, 1);
});

test("5. no orphan add-on renewal after base cancellation (recurring reject)", () => {
  const scheduled = scheduleBaseCancellation(baseProfile()).profile;
  const guard = shouldRejectRecurringAfterCancel(scheduled);
  assert.equal(guard.reject, true);
  assert.equal(guard.reason, "cancel_at_period_end");
});

test("6. cancel exactly one vehicle from quantity one (cascade schedules that one)", () => {
  const { profile } = cascadeAddonCancellations(
    baseProfile({ extra_vehicle_active_quantity: 1 }),
    { effectiveAt: "2026-09-01T00:00:00.000Z", requestedAt: "2026-08-12T10:00:00.000Z" },
  );
  assert.equal(profile.extra_vehicle_cancel_at_period_end_quantity, 1);
});

test("7. cancel vehicles from quantity greater than one", () => {
  const { profile } = cascadeAddonCancellations(
    baseProfile({ extra_vehicle_active_quantity: 3 }),
    { effectiveAt: "2026-09-01T00:00:00.000Z", requestedAt: "2026-08-12T10:00:00.000Z" },
  );
  assert.equal(profile.extra_vehicle_cancel_at_period_end_quantity, 3);
});

test("8. vehicle-only cascade leaves PDF active qty until its own schedule", () => {
  // Independent vehicle cancel-one is route-level; cascade with only vehicles
  // set still preserves PDF active quantities when cascading from a vehicle-only
  // profile change simulation (PDF active stays, cancel qty 0 when active 0).
  const { profile, summary } = cascadeAddonCancellations(
    baseProfile({
      extra_vehicle_active_quantity: 1,
      pdf5000_active_quantity: 1,
    }),
    { effectiveAt: "2026-09-01T00:00:00.000Z", requestedAt: "2026-08-12T10:00:00.000Z" },
  );
  assert.equal(summary.extra_vehicle, 1);
  assert.equal(summary.pdf5000, 1);
  assert.equal(profile.pdf5000_active_quantity, 1);
});

test("9. PDF schedule leaves vehicle active quantity", () => {
  const { profile } = cascadeAddonCancellations(
    baseProfile({
      extra_vehicle_active_quantity: 1,
      pdf1000_active_quantity: 1,
    }),
    { effectiveAt: "2026-09-01T00:00:00.000Z", requestedAt: "2026-08-12T10:00:00.000Z" },
  );
  assert.equal(profile.extra_vehicle_active_quantity, 1);
  assert.equal(profile.pdf1000_cancel_at_period_end_quantity, 1);
});

test("10. bundled 3-driver capacity is not reduced until materialize (schedule only)", () => {
  const r = scheduleBaseCancellation(
    baseProfile({ extra_vehicle_active_quantity: 1, max_drivers: 7 }),
  );
  assert.equal(r.profile.max_drivers, 7);
});

test("11. per-vehicle PDF base is display-side; schedule does not touch pdf_monthly_allowance", () => {
  const r = scheduleBaseCancellation(
    baseProfile({
      extra_vehicle_active_quantity: 1,
      pdf_monthly_allowance: 7500,
    }),
  );
  assert.equal(r.profile.pdf_monthly_allowance, 7500);
});

test("12. paid capacity remains until effective period end (materialize before due is noop)", () => {
  const scheduled = scheduleBaseCancellation(
    baseProfile({ current_period_end: "2026-09-01T00:00:00.000Z" }),
    { nowIso: "2026-08-12T10:00:00.000Z" },
  ).profile;
  const early = materializeBaseCancellation(scheduled, {
    nowMs: Date.parse("2026-08-15T00:00:00.000Z"),
  });
  assert.equal(early.changed, false);
  assert.equal(early.profile.subscription_status, "active");
});

test("13. repeated cancellation is idempotent", () => {
  const first = scheduleBaseCancellation(baseProfile(), {
    nowIso: "2026-08-12T10:00:00.000Z",
  });
  const second = scheduleBaseCancellation(first.profile, {
    nowIso: "2026-08-12T11:00:00.000Z",
  });
  assert.equal(second.ok, true);
  assert.equal(second.already_scheduled, true);
  assert.equal(second.effectiveAt, first.effectiveAt);
  assert.equal(second.profile.cancel_requested_at, first.profile.cancel_requested_at);
});

test("14. concurrent renew/cancel ordering: cancel wins over recurring apply", () => {
  const scheduled = scheduleBaseCancellation(baseProfile()).profile;
  assert.equal(shouldRejectRecurringAfterCancel(scheduled).reject, true);
  assert.equal(
    shouldRejectRecurringAfterCancel({
      ...baseProfile(),
      auto_renew: false,
      cancel_at_period_end: false,
    }).reject,
    true,
  );
});

test("15. provider failure keeps retryable pending state", () => {
  const scheduled = scheduleBaseCancellation(baseProfile()).profile;
  const failed = applyProviderCancelOutcome(scheduled, {
    ok: false,
    errorCode: "upstream_500",
    nowIso: "2026-08-12T10:00:00.000Z",
  });
  assert.equal(failed.provider_ok, false);
  assert.equal(failed.profile.provider_cancel_pending, true);
  assert.equal(failed.profile.cancel_at_period_end, true);
  assert.equal(needsProviderCancel(failed.profile), true);

  const ok = applyProviderCancelOutcome(failed.profile, {
    ok: true,
    nowIso: "2026-08-12T10:05:00.000Z",
    subscriptionId: "sub_test",
  });
  assert.equal(ok.provider_ok, true);
  assert.equal(ok.profile.provider_cancel_pending, false);
  assert.equal(needsProviderCancel(ok.profile), false);
});

test("16. webhook replay: already cancelled status rejects recurring", () => {
  const guard = shouldRejectRecurringAfterCancel({
    ...baseProfile(),
    subscription_status: "cancelled",
    status: "cancelled",
    cancel_at_period_end: false,
    auto_renew: true,
  });
  assert.equal(guard.reject, true);
  assert.equal(guard.reason, "already_cancelled");
});

test("17. tenant isolation is out-of-scope for pure helpers; summarizeActiveAddons is scope-agnostic", () => {
  const s = summarizeActiveAddonsForUi(
    baseProfile({ extra_vehicle_active_quantity: 1, pdf5000_active_quantity: 1 }),
  );
  assert.equal(s.extra_vehicle_active_quantity, 1);
  assert.equal(s.pdf5000_active_quantity, 1);
});

test("18. founder price preserved on add-on cascade / base schedule", () => {
  const r = scheduleBaseCancellation(
    baseProfile({
      locked_price_cents: 5900,
      is_founder_customer: true,
      founder_slot_number: 7,
      extra_vehicle_active_quantity: 1,
    }),
  );
  assert.equal(r.profile.locked_price_cents, 5900);
  assert.equal(r.profile.is_founder_customer, true);
  assert.equal(r.profile.founder_slot_number, 7);
});

test("19. founder consequence correct on base cancellation materialize (lock kept)", () => {
  const scheduled = scheduleBaseCancellation(
    baseProfile({
      locked_price_cents: 5900,
      is_founder_customer: true,
      founder_slot_number: 3,
      current_period_end: "2026-08-01T00:00:00.000Z",
    }),
  ).profile;
  const mat = materializeBaseCancellation(scheduled, {
    nowMs: Date.parse("2026-08-12T00:00:00.000Z"),
    nowIso: "2026-08-12T00:00:00.000Z",
  });
  assert.equal(mat.applied, true);
  assert.equal(mat.profile.subscription_status, "cancelled");
  assert.equal(mat.profile.locked_price_cents, 5900);
  assert.equal(mat.profile.is_founder_customer, true);
  assert.equal(mat.profile.founder_slot_number, 3);
});

test("20. no destructive resource deletion in schedule/materialize helpers", () => {
  const r = scheduleBaseCancellation(
    baseProfile({ max_vehicles: 4, max_drivers: 12, pdf_monthly_allowance: 7500 }),
  );
  assert.equal(r.profile.max_vehicles, 4);
  assert.equal(r.profile.max_drivers, 12);
  const mat = materializeBaseCancellation(
    { ...r.profile, cancellation_effective_at: "2026-08-01T00:00:00.000Z" },
    { nowMs: Date.parse("2026-08-12T00:00:00.000Z") },
  );
  assert.equal(mat.profile.max_vehicles, 4);
  assert.equal(mat.profile.max_drivers, 12);
  assert.equal(mat.profile.pdf_monthly_allowance, 7500);
});

test("resolveCancellationEffectiveAt falls back to trial then +30d", () => {
  assert.equal(
    resolveCancellationEffectiveAt({
      current_period_end: "",
      trial_ends_at: "2026-08-20T00:00:00.000Z",
    }),
    "2026-08-20T00:00:00.000Z",
  );
  const fallback = resolveCancellationEffectiveAt(
    { current_period_end: "", trial_ends_at: "" },
    Date.parse("2026-08-12T00:00:00.000Z"),
  );
  assert.equal(fallback, "2026-09-11T00:00:00.000Z");
});

test("non-active profiles cannot schedule cancel", () => {
  const r = scheduleBaseCancellation(baseProfile({ subscription_status: "suspended" }));
  assert.equal(r.ok, false);
  assert.equal(r.error, "subscription_not_cancelable");
});

// ---------------------------------------------------------------------------
// Paid reactivation after expired/cancelled base (P0 regression)
// ---------------------------------------------------------------------------

function expiredCancelledProfile(extra = {}) {
  return baseProfile({
    subscription_status: "cancelled",
    status: "cancelled",
    cancel_at_period_end: true,
    auto_renew: false,
    cancel_requested_at: "2026-08-12T16:39:22.624Z",
    cancellation_effective_at: "2026-07-26T20:51:06.937Z",
    cancelled_at: "2026-08-12T16:39:22.816Z",
    provider_cancel_pending: true,
    provider_cancel_last_error: "upstream_500",
    provider_cancel_attempted_at: "2026-08-12T16:39:22.700Z",
    provider_cancel_completed_at: "",
    past_due_since: "2026-08-01T00:00:00.000Z",
    suspended_at: "",
    current_period_start: "2026-06-26T20:51:06.937Z",
    current_period_end: "2026-07-26T20:51:06.937Z",
    locked_price_cents: 6900,
    is_founder_customer: false,
    founder_slot_number: null,
    activation_id: "act_old",
    provider_subscription_id: "",
    extra_vehicle_active_quantity: 1,
    max_vehicles: 2,
    max_drivers: 6,
    pdf_monthly_used: 32,
    ...extra,
  });
}

test("paid reactivation: clears cancel lifecycle, activates, materialize no-op, one sub, add-ons kept", () => {
  const activationId = "act_995770da-fca5-48ee-ac2d-1c4098c2dec0";
  const periodStart = "2026-08-12T16:44:36.124Z";
  const periodEnd = "2026-09-11T16:44:36.124Z";
  const newSubId = "sub_95EYivj6uP";

  // 1–3. Expired/cancelled base → new activation + verified first payment paid
  //    (modeled as the activator compose after payment status=paid).
  const afterPaidActivate = clearCancellationLifecycleOnPaidActivation({
    ...expiredCancelledProfile(),
    activation_id: activationId,
    current_period_start: periodStart,
    current_period_end: periodEnd,
    locked_price_cents: 6900,
    is_founder_customer: false,
    provider_subscription_id: newSubId,
    provider_customer_id: "cst_AD",
    mandate_id: "mdt_cV",
  });

  // 4–6. Active, every stale cancel field cleared, auto_renew true
  assert.equal(afterPaidActivate.status, "active");
  assert.equal(afterPaidActivate.subscription_status, "active");
  assert.equal(afterPaidActivate.cancel_at_period_end, false);
  assert.equal(afterPaidActivate.auto_renew, true);
  assert.equal(afterPaidActivate.cancellation_effective_at, "");
  assert.equal(afterPaidActivate.cancel_requested_at, "");
  assert.equal(afterPaidActivate.cancelled_at, "");
  assert.equal(afterPaidActivate.provider_cancel_pending, false);
  assert.equal(afterPaidActivate.provider_cancel_last_error, "");
  assert.equal(afterPaidActivate.provider_cancel_attempted_at, "");
  assert.equal(afterPaidActivate.provider_cancel_completed_at, "");
  assert.equal(afterPaidActivate.past_due_since, "");
  assert.equal(afterPaidActivate.suspended_at, "");

  // Period / price / identity preserved
  assert.equal(afterPaidActivate.current_period_start, periodStart);
  assert.equal(afterPaidActivate.current_period_end, periodEnd);
  assert.equal(afterPaidActivate.locked_price_cents, 6900);
  assert.equal(afterPaidActivate.activation_id, activationId);
  assert.equal(afterPaidActivate.provider_subscription_id, newSubId);

  // 7. Subsequent materialize is a no-op
  const mat = materializeBaseCancellation(afterPaidActivate, {
    nowMs: Date.parse("2026-08-12T16:44:40.253Z"),
    nowIso: "2026-08-12T16:44:40.253Z",
  });
  assert.equal(mat.changed, false);
  assert.equal(mat.applied, false);
  assert.equal(mat.profile.subscription_status, "active");

  // 8. Exactly one recurring subscription (create skipped when sub_ present)
  assert.equal(recurringCreateWouldNoop(afterPaidActivate), true);

  // 9–10. Duplicate heal / reconcile idempotent — no period extension, still one sub
  const healedAgain = clearCancellationLifecycleOnPaidActivation(afterPaidActivate);
  assert.equal(healedAgain.current_period_end, periodEnd);
  assert.equal(healedAgain.current_period_start, periodStart);
  assert.equal(healedAgain.provider_subscription_id, newSubId);
  assert.equal(recurringCreateWouldNoop(healedAgain), true);
  assert.equal(
    needsPaidActivationCancellationHeal(healedAgain, { activationId }),
    false,
  );

  // 11. Dunning / provider-cancel errors cleared (asserted above)
  // 12. Add-on quantities and usage unchanged
  assert.equal(afterPaidActivate.extra_vehicle_active_quantity, 1);
  assert.equal(afterPaidActivate.max_vehicles, 2);
  assert.equal(afterPaidActivate.max_drivers, 6);
  assert.equal(afterPaidActivate.pdf_monthly_used, 32);
});

test("paid reactivation: without clear, materialize re-cancels (pre-fix proof)", () => {
  const broken = {
    ...expiredCancelledProfile({
      activation_id: "act_995770da-fca5-48ee-ac2d-1c4098c2dec0",
    }),
    // Activator wrote active + new period but left cancel flags (bug shape).
    subscription_status: "active",
    status: "active",
    current_period_start: "2026-08-12T16:44:36.124Z",
    current_period_end: "2026-09-11T16:44:36.124Z",
    provider_subscription_id: "sub_95EYivj6uP",
  };
  const mat = materializeBaseCancellation(broken, {
    nowMs: Date.parse("2026-08-12T16:44:40.253Z"),
  });
  assert.equal(mat.applied, true);
  assert.equal(mat.profile.subscription_status, "cancelled");
  assert.equal(mat.profile.current_period_end, "2026-09-11T16:44:36.124Z");
});

test("needsPaidActivationCancellationHeal requires matching activation_id", () => {
  const p = expiredCancelledProfile({
    activation_id: "act_995770da-fca5-48ee-ac2d-1c4098c2dec0",
  });
  assert.equal(
    needsPaidActivationCancellationHeal(p, {
      activationId: "act_995770da-fca5-48ee-ac2d-1c4098c2dec0",
    }),
    true,
  );
  assert.equal(
    needsPaidActivationCancellationHeal(p, { activationId: "act_other" }),
    false,
  );
  const healthy = clearCancellationLifecycleOnPaidActivation({
    ...p,
    provider_subscription_id: "sub_95EYivj6uP",
  });
  assert.equal(
    needsPaidActivationCancellationHeal(healthy, {
      activationId: "act_995770da-fca5-48ee-ac2d-1c4098c2dec0",
    }),
    false,
  );
});

test("same-period undo vs post-expiry reactivation: contracts stay distinct", () => {
  // A. Undo before effective end: schedule only — status stays active, no new period.
  const midPeriod = baseProfile({
    current_period_end: "2026-09-01T00:00:00.000Z",
    locked_price_cents: 5900,
    is_founder_customer: true,
  });
  const scheduled = scheduleBaseCancellation(midPeriod, {
    nowIso: "2026-08-12T10:00:00.000Z",
  }).profile;
  assert.equal(scheduled.subscription_status, "active");
  assert.equal(scheduled.cancel_at_period_end, true);
  assert.equal(scheduled.current_period_end, "2026-09-01T00:00:00.000Z");
  assert.equal(scheduled.locked_price_cents, 5900);
  // Clearing schedule flags (product undo) is NOT the paid-reactivation path;
  // paid clear is only for verified first payment after expiry.
  const undoLocal = {
    ...scheduled,
    cancel_at_period_end: false,
    auto_renew: true,
    cancellation_effective_at: "",
    cancel_requested_at: "",
  };
  assert.equal(undoLocal.current_period_end, "2026-09-01T00:00:00.000Z");
  assert.equal(undoLocal.locked_price_cents, 5900);

  // B. Reactivate after effective end: new period + market price via paid clear.
  const postExpiry = clearCancellationLifecycleOnPaidActivation({
    ...expiredCancelledProfile(),
    activation_id: "act_new",
    current_period_start: "2026-08-12T16:44:36.124Z",
    current_period_end: "2026-09-11T16:44:36.124Z",
    locked_price_cents: 6900,
    is_founder_customer: false,
    provider_subscription_id: "sub_new",
  });
  assert.equal(postExpiry.subscription_status, "active");
  assert.equal(postExpiry.current_period_end, "2026-09-11T16:44:36.124Z");
  assert.equal(postExpiry.locked_price_cents, 6900);
  assert.equal(postExpiry.is_founder_customer, false);
});
