import assert from "node:assert/strict";
import test from "node:test";
import {
  DEFAULT_TRIAL_DRIVERS,
  DEFAULT_TRIAL_VEHICLES,
  DRIVER_LIMIT_REACHED,
  TRIAL_CAPACITY_EXPIRED,
  applyTrialOverlayToSubscriptionProfile,
  evaluateDriverCapacityWrite,
  evaluateTrialCapacityForNewWork,
  isTrialOverrideActive,
  previewTrialEntitlementWrite,
  resolveAuthoritativeDriverCapacity,
  resolveEffectiveDriverCapacity,
  resolveEffectiveVehicleCapacity,
  summarizeTrialEntitlement,
  trialEntitlementKey,
} from "./company_trial_entitlement.mjs";
import { resolveAuthoritativeVehicleCapacity } from "./fleet_vehicle_capacity.mjs";

const NOW = new Date("2026-09-11T14:00:00.000Z");
const FUTURE = "2026-10-01T00:00:00.000Z";
const PAST = "2026-09-01T00:00:00.000Z";

const TRIAL = {
  status: "trialing",
  subscription_status: "trialing",
  included_vehicles: 1,
  max_vehicles: 1,
  max_drivers: 3,
  extra_vehicle_active_quantity: 0,
  extra_driver_active_quantity: 0,
  trial_ends_at: "2026-09-25T00:00:00.000Z",
};

const PAID = {
  status: "active",
  subscription_status: "active",
  included_vehicles: 1,
  max_vehicles: 2,
  max_drivers: 6,
  extra_vehicle_active_quantity: 1,
  extra_driver_active_quantity: 0,
};

test("default trial remains one vehicle and three drivers", () => {
  assert.equal(resolveAuthoritativeVehicleCapacity(TRIAL), DEFAULT_TRIAL_VEHICLES);
  assert.equal(resolveAuthoritativeDriverCapacity(TRIAL), DEFAULT_TRIAL_DRIVERS);
  assert.equal(resolveEffectiveVehicleCapacity(TRIAL, null, NOW), 1);
  assert.equal(resolveEffectiveDriverCapacity(TRIAL, null, NOW), 3);
});

test("a personal fleet trial raises totals while it is in date", () => {
  const override = { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: FUTURE };
  assert.equal(isTrialOverrideActive(override, NOW), true);
  assert.equal(resolveEffectiveVehicleCapacity(TRIAL, override, NOW), 7);
  assert.equal(resolveEffectiveDriverCapacity(TRIAL, override, NOW), 21);
});

test("an expired personal trial no longer grants extra capacity", () => {
  const override = { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: PAST };
  assert.equal(isTrialOverrideActive(override, NOW), false);
  assert.equal(resolveEffectiveVehicleCapacity(TRIAL, override, NOW), 1);
  assert.equal(resolveEffectiveDriverCapacity(TRIAL, override, NOW), 3);
});

test("a trial adjustment cannot lower paid vehicle or driver rights", () => {
  const override = { vehicles_allowed: 1, drivers_allowed: 1, trial_ends_at: FUTURE };
  assert.equal(resolveEffectiveVehicleCapacity(PAID, override, NOW), 2);
  assert.equal(resolveEffectiveDriverCapacity(PAID, override, NOW), 6);
  const preview = previewTrialEntitlementWrite({
    current: summarizeTrialEntitlement({ profile: PAID, override: null, usage: { vehicles: 2, drivers: 4 } }),
    nextVehicles: 1,
    nextDrivers: 1,
    nextEndsAt: FUTURE,
  });
  assert.equal(preview.next.vehicles, 2);
  assert.equal(preview.next.drivers, 6);
  assert.equal(preview.paid_floor_applied, true);
  assert.match(preview.consequences.join(" "), /Betaalde rechten blijven/);
});

test("lowering under current use is allowed and names the overrun", () => {
  const current = summarizeTrialEntitlement({
    profile: TRIAL,
    override: { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: FUTURE },
    usage: { vehicles: 7, drivers: 10 },
    now: NOW,
  });
  const preview = previewTrialEntitlementWrite({
    current,
    nextVehicles: 2,
    nextDrivers: 3,
    nextEndsAt: FUTURE,
  });
  assert.equal(preview.next.vehicles, 2);
  assert.ok(preview.consequences.some((line) => line.includes("7 voertuigen")));
  assert.ok(preview.consequences.some((line) => line.includes("10 chauffeurs")));
  assert.ok(preview.consequences.every((line) => !/automatische betaling/.test(line) || /Geen automatische betaling/.test(line)));
});

test("expiry consequences never delete, charge, or cut a ride", () => {
  const summary = summarizeTrialEntitlement({
    profile: TRIAL,
    override: { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: FUTURE },
    usage: { vehicles: 7, drivers: 8 },
    now: NOW,
  });
  assert.equal(summary.expiry.no_auto_payment, true);
  assert.equal(summary.expiry.no_vehicle_deletion, true);
  assert.equal(summary.expiry.no_driver_deletion, true);
  assert.equal(summary.expiry.no_ride_interruption, true);
  assert.equal(summary.expiry.after_expiry_vehicles, 1);
  assert.equal(summary.expiry.vehicles_over_limit, true);
});

test("a paused account stays paused in the summary", () => {
  const summary = summarizeTrialEntitlement({
    profile: TRIAL,
    override: { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: FUTURE },
    accountState: "paused",
    now: NOW,
  });
  assert.equal(summary.account_state, "paused");
  assert.equal(summary.account_untouched, true);
  assert.equal(summary.subscription_untouched, true);
});

test("two concurrent extra-driver writes against the same snapshot cannot both stay", () => {
  const allowed = 3;
  const first = evaluateDriverCapacityWrite({
    existingActiveIds: ["drv_1", "drv_2"],
    incomingActiveIds: ["drv_1", "drv_2", "drv_a"],
    allowed,
  });
  const afterFirst = first.ok ? ["drv_1", "drv_2", "drv_a"] : ["drv_1", "drv_2"];
  const second = evaluateDriverCapacityWrite({
    existingActiveIds: afterFirst,
    incomingActiveIds: [...afterFirst, "drv_b"],
    allowed,
  });
  assert.equal(first.ok, true);
  assert.equal(second.ok, false);
  assert.equal(second.error, DRIVER_LIMIT_REACHED);
  assert.equal(afterFirst.length, 3);
});

test("subscription overlay exposes effective totals without rewriting paid max fields", () => {
  const overlay = applyTrialOverlayToSubscriptionProfile(
    TRIAL,
    { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: FUTURE },
    NOW,
  );
  assert.equal(overlay.max_vehicles, 1);
  assert.equal(overlay.max_drivers, 3);
  assert.equal(overlay.effective_max_vehicles, 7);
  assert.equal(overlay.effective_max_drivers, 21);
  assert.equal(overlay.trial_override.active, true);
  assert.equal(overlay.trial_ends_at, FUTURE);
  assert.equal(overlay.profile_trial_ends_at, TRIAL.trial_ends_at);
});

test("new work is refused only when a personal override exists and usage is over the effective limit", () => {
  const expired = { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: PAST };
  const active = { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: FUTURE };
  const seven = { vehicles: 7, drivers: 10 };
  assert.equal(evaluateTrialCapacityForNewWork({
    profile: TRIAL,
    override: expired,
    usage: seven,
    now: NOW,
  }).error, TRIAL_CAPACITY_EXPIRED);
  assert.equal(evaluateTrialCapacityForNewWork({
    profile: TRIAL,
    override: null,
    usage: { vehicles: 2, drivers: 2 },
    now: NOW,
  }).ok, true);
  assert.equal(evaluateTrialCapacityForNewWork({
    profile: TRIAL,
    override: expired,
    usage: seven,
    accountState: "paused",
    now: NOW,
  }).deferred, "account");
  assert.equal(evaluateTrialCapacityForNewWork({
    profile: TRIAL,
    override: active,
    usage: seven,
    now: NOW,
  }).ok, true);
  assert.equal(evaluateTrialCapacityForNewWork({
    profile: TRIAL,
    override: { vehicles_allowed: 2, drivers_allowed: 3, trial_ends_at: FUTURE },
    usage: seven,
    now: NOW,
  }).error, TRIAL_CAPACITY_EXPIRED);
});

test("preview names that the company chooses which vehicles stay active", () => {
  const preview = previewTrialEntitlementWrite({
    current: summarizeTrialEntitlement({
      profile: TRIAL,
      override: { vehicles_allowed: 7, drivers_allowed: 21, trial_ends_at: FUTURE },
      usage: { vehicles: 7, drivers: 10 },
      now: NOW,
    }),
    nextVehicles: 2,
    nextDrivers: 3,
    nextEndsAt: FUTURE,
  });
  assert.ok(preview.consequences.some((line) => line.includes("Nieuwe ritten starten")));
  assert.ok(preview.consequences.some((line) => line.includes("selecteert geen klantvoertuigen")));
});

test("trial entitlement keys stay scoped to one company", () => {
  const a = trialEntitlementKey("cmp_a", "cmp_a");
  const b = trialEntitlementKey("cmp_b", "cmp_b");
  assert.equal(a, "tenant:cmp_a:company:cmp_a:trial_entitlement:v1");
  assert.notEqual(a, b);
});
