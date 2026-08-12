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
} from "./subscription_cancellation.mjs";

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
