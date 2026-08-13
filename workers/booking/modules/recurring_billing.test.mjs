import { test } from "node:test";
import assert from "node:assert/strict";

import {
  computeConsolidatedRecurringCents,
  computeConsolidatedRecurringCentsFromProfile,
  computeProrationCents,
  futureRecurringAddonQuantities,
  centsToMollieAmountValue,
  scheduleCancelOneExtraVehicle,
  undoCancelOneExtraVehicle,
  scheduleCancelOneExtraDriver,
  undoCancelOneExtraDriver,
  undoBaseCancellation,
} from "./recurring_billing.mjs";

test("consolidated total €69 and €59 bases with vehicle/driver mixes", () => {
  assert.equal(computeConsolidatedRecurringCents({
    lockedPriceCents: 6900, vehicleQty: 0, driverQty: 0,
  }), 6900);
  assert.equal(computeConsolidatedRecurringCents({
    lockedPriceCents: 6900, vehicleQty: 1, driverQty: 0,
  }), 8800);
  assert.equal(computeConsolidatedRecurringCents({
    lockedPriceCents: 6900, vehicleQty: 1, driverQty: 1,
  }), 9700);
  assert.equal(computeConsolidatedRecurringCents({
    lockedPriceCents: 5900, vehicleQty: 1, driverQty: 0,
  }), 7800);
  assert.equal(computeConsolidatedRecurringCents({
    lockedPriceCents: 6900, vehicleQty: 2, driverQty: 3,
  }), 6900 + 3800 + 2700);
});

test("PDF never affects consolidated recurring total", () => {
  const profile = {
    locked_price_cents: 6900,
    extra_vehicle_active_quantity: 1,
    extra_vehicle_cancel_at_period_end_quantity: 0,
    extra_driver_active_quantity: 0,
    extra_driver_cancel_at_period_end_quantity: 0,
    pdf_purchased_credits_remaining: 7500,
    pdf5000_active_quantity: 1,
  };
  assert.equal(computeConsolidatedRecurringCentsFromProfile(profile), 8800);
});

test("future qty = active minus scheduled cancel", () => {
  const q = futureRecurringAddonQuantities({
    extra_vehicle_active_quantity: 2,
    extra_vehicle_cancel_at_period_end_quantity: 1,
    extra_driver_active_quantity: 3,
    extra_driver_cancel_at_period_end_quantity: 1,
  });
  assert.equal(q.vehicle_qty, 1);
  assert.equal(q.driver_qty, 2);
});

test("deterministic proration cent rounding", () => {
  const periodStart = "2026-08-12T16:44:36.124Z";
  const periodEnd = "2026-09-11T16:44:36.124Z";
  const startMs = Date.parse(periodStart);
  const endMs = Date.parse(periodEnd);
  const midMs = startMs + Math.floor((endMs - startMs) / 2);
  const half = computeProrationCents({
    monthlyCents: 1900,
    periodStartIso: periodStart,
    periodEndIso: periodEnd,
    nowMs: midMs,
  });
  assert.equal(half, 950);
  assert.equal(computeProrationCents({
    monthlyCents: 1900,
    periodStartIso: periodStart,
    periodEndIso: periodEnd,
    nowMs: endMs,
  }), 0);
  assert.equal(computeProrationCents({
    monthlyCents: 1900,
    periodStartIso: periodStart,
    periodEndIso: periodEnd,
    nowMs: startMs,
  }), 1900);
  // Odd remaining fraction → Math.round
  const almostEnd = endMs - 1;
  const tiny = computeProrationCents({
    monthlyCents: 1900,
    periodStartIso: periodStart,
    periodEndIso: periodEnd,
    nowMs: almostEnd,
  });
  assert.equal(typeof tiny, "number");
  assert.ok(tiny >= 0 && tiny <= 1900);
});

test("centsToMollieAmountValue", () => {
  assert.equal(centsToMollieAmountValue(8800), "88.00");
  assert.equal(centsToMollieAmountValue(6900), "69.00");
});

test("cancel one vehicle retains active qty; future qty drops; undo restores", () => {
  let p = {
    extra_vehicle_active_quantity: 1,
    extra_vehicle_cancel_at_period_end_quantity: 0,
    current_period_end: "2026-09-11T16:44:36.124Z",
    locked_price_cents: 6900,
  };
  const scheduled = scheduleCancelOneExtraVehicle(p, {
    nowIso: "2026-08-13T10:00:00.000Z",
    effectiveAt: p.current_period_end,
  });
  assert.equal(scheduled.ok, true);
  assert.equal(scheduled.profile.extra_vehicle_active_quantity, 1);
  assert.equal(scheduled.profile.extra_vehicle_cancel_at_period_end_quantity, 1);
  assert.equal(futureRecurringAddonQuantities(scheduled.profile).vehicle_qty, 0);
  assert.equal(
    computeConsolidatedRecurringCentsFromProfile(scheduled.profile),
    6900,
  );

  const undone = undoCancelOneExtraVehicle(scheduled.profile);
  assert.equal(undone.ok, true);
  assert.equal(undone.already, false);
  assert.equal(undone.profile.extra_vehicle_cancel_at_period_end_quantity, 0);
  assert.equal(futureRecurringAddonQuantities(undone.profile).vehicle_qty, 1);
  assert.equal(
    computeConsolidatedRecurringCentsFromProfile(undone.profile),
    8800,
  );

  const again = undoCancelOneExtraVehicle(undone.profile);
  assert.equal(again.already, true);
  assert.equal(again.profile.extra_vehicle_active_quantity, 1);
});

test("cancel/undo driver; purchase vs undo remain distinct", () => {
  const p = {
    extra_driver_active_quantity: 1,
    extra_driver_cancel_at_period_end_quantity: 0,
    current_period_end: "2026-09-11T16:44:36.124Z",
    locked_price_cents: 6900,
    extra_vehicle_active_quantity: 0,
    extra_vehicle_cancel_at_period_end_quantity: 0,
  };
  const c = scheduleCancelOneExtraDriver(p, {
    nowIso: "2026-08-13T10:00:00.000Z",
    effectiveAt: p.current_period_end,
  });
  assert.equal(c.profile.extra_driver_active_quantity, 1); // access retained
  assert.equal(futureRecurringAddonQuantities(c.profile).driver_qty, 0);
  const u = undoCancelOneExtraDriver(c.profile);
  assert.equal(u.profile.extra_driver_active_quantity, 1); // undo ≠ buy
  assert.equal(futureRecurringAddonQuantities(u.profile).driver_qty, 1);
});

test("base undo before effective; expired requires reactivation", () => {
  const mid = {
    status: "active",
    subscription_status: "active",
    cancel_at_period_end: true,
    cancellation_effective_at: "2026-09-11T16:44:36.124Z",
    auto_renew: false,
    cancel_requested_at: "2026-08-13T10:00:00.000Z",
  };
  const ok = undoBaseCancellation(mid, {
    nowMs: Date.parse("2026-08-20T00:00:00.000Z"),
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.profile.cancel_at_period_end, false);
  assert.equal(ok.profile.auto_renew, true);

  const expired = undoBaseCancellation(mid, {
    nowMs: Date.parse("2026-09-12T00:00:00.000Z"),
  });
  assert.equal(expired.ok, false);
  assert.equal(expired.error, "reactivation_required");
});
