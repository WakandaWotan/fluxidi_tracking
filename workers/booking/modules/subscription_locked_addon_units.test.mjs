// Producer tests for locked extra-vehicle / extra-driver unit prices.
// Run: node --test workers/booking/modules/subscription_locked_addon_units.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING,
  parseIntegerCents,
  computeLockedRecurringTotal,
  vatCentsFromExcl,
  applyAuthorizedCheckoutLocks,
  applyAuthorizedAddonUnitLock,
  preserveLocksOnQuantityChange,
  preserveLocksOnLifecycleWrite,
  resolveAddonCheckoutUnitFromContract,
  resolveRecurringAddonUnitsFromLocks,
  evaluateLegacyAddonUnitRepair,
} from "./subscription_locked_addon_units.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const NOW = "2026-08-20T10:00:00.000Z";
const LATER = "2026-08-20T11:00:00.000Z";

function baseProfile(extra = {}) {
  return {
    tenant_id: "t_a",
    company_id: "c_a",
    currency: "EUR",
    subscription_status: "active",
    locked_price_cents: 6900,
    extra_vehicle_active_quantity: 0,
    extra_driver_active_quantity: 0,
    extra_vehicle_cancel_at_period_end_quantity: 0,
    extra_driver_cancel_at_period_end_quantity: 0,
    is_founder_customer: false,
    ...extra,
  };
}

test("parseIntegerCents: null is absent, never zero", () => {
  assert.deepEqual(parseIntegerCents(null), { ok: true, present: false, value: null });
  assert.deepEqual(parseIntegerCents(undefined), { ok: true, present: false, value: null });
  assert.deepEqual(parseIntegerCents(""), { ok: true, present: false, value: null });
  assert.equal(parseIntegerCents(0).value, 0);
  assert.equal(parseIntegerCents(0).present, true);
  assert.equal(parseIntegerCents(1900).value, 1900);
  assert.equal(parseIntegerCents(true).ok, false);
  assert.equal(parseIntegerCents(19.5).ok, false);
  assert.equal(parseIntegerCents(-1).ok, false);
});

test("new subscription stores locked units from checkout snapshot", () => {
  const r = applyAuthorizedCheckoutLocks(baseProfile(), {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    locked_price_cents: 6900,
    currency: "EUR",
    activation_id: "act_new",
    nowIso: NOW,
  });
  assert.equal(r.ok, true);
  assert.equal(r.bumped, true);
  assert.equal(r.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(r.profile.locked_extra_driver_unit_cents, 900);
  assert.equal(r.profile.locked_price_cents, 6900);
  assert.equal(r.profile.source_revision, 1);
  assert.equal(r.profile.price_provenance.extra_vehicle.source, "checkout_snapshot");
  assert.equal(r.profile.price_provenance.extra_vehicle.unit_cents, 1900);
  assert.equal(r.profile.price_provenance.extra_driver.unit_cents, 900);
});

test("add-on add and remove keep the first lock", () => {
  const created = applyAuthorizedCheckoutLocks(baseProfile(), {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    currency: "EUR",
    nowIso: NOW,
  });
  const added = applyAuthorizedAddonUnitLock({
    ...created.profile,
    extra_vehicle_active_quantity: 1,
  }, {
    addon_code: "extra_vehicle",
    unit_price_cents: 1900,
    currency: "EUR",
    activation_id: "addon_1",
    nowIso: LATER,
  });
  assert.equal(added.kept_existing, true);
  assert.equal(added.profile.locked_extra_vehicle_unit_cents, 1900);
  const qty = preserveLocksOnQuantityChange(added.profile, {
    extra_vehicle_active_quantity: 3,
    extra_driver_active_quantity: 1,
  });
  assert.equal(qty.profile.extra_vehicle_active_quantity, 3);
  assert.equal(qty.profile.extra_driver_active_quantity, 1);
  assert.equal(qty.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(qty.profile.locked_extra_driver_unit_cents, 900);
  const removed = preserveLocksOnQuantityChange(qty.profile, {
    extra_vehicle_active_quantity: 2,
    extra_driver_active_quantity: 0,
  });
  assert.equal(removed.profile.extra_driver_active_quantity, 0);
  assert.equal(removed.profile.locked_extra_driver_unit_cents, 900);
});

test("quantity 0 keeps locks and recomputes base-only total", () => {
  const locked = applyAuthorizedCheckoutLocks(baseProfile({
    extra_vehicle_active_quantity: 3,
    extra_driver_active_quantity: 1,
  }), {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    currency: "EUR",
    nowIso: NOW,
  });
  assert.equal(locked.profile.locked_total_recurring_cents, 13500);
  const zeroed = preserveLocksOnQuantityChange(locked.profile, {
    extra_vehicle_active_quantity: 0,
    extra_driver_active_quantity: 0,
  });
  assert.equal(zeroed.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(zeroed.profile.locked_extra_driver_unit_cents, 900);
  assert.equal(zeroed.profile.locked_total_recurring_cents, 6900);
});

test("renewal and plan change preserve locks", () => {
  const locked = applyAuthorizedCheckoutLocks(baseProfile({
    extra_vehicle_active_quantity: 3,
    extra_driver_active_quantity: 1,
  }), {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    currency: "EUR",
    nowIso: NOW,
  });
  const renewal = preserveLocksOnLifecycleWrite(locked.profile, {
    current_period_start: "2026-09-20T10:00:00.000Z",
    current_period_end: "2026-10-20T10:00:00.000Z",
    last_recurring_payment_id: "tr_renew",
  });
  assert.equal(renewal.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(renewal.profile.locked_extra_driver_unit_cents, 900);
  assert.equal(renewal.profile.source_revision, locked.profile.source_revision);
  const plan = preserveLocksOnLifecycleWrite(locked.profile, {
    plan_code: "fluxidi_pro",
    market: "BE",
  });
  assert.equal(plan.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(plan.profile.locked_price_cents, 6900);
  const cancel = preserveLocksOnLifecycleWrite(locked.profile, {
    cancel_at_period_end: true,
    auto_renew: false,
  });
  assert.equal(cancel.profile.locked_extra_driver_unit_cents, 900);
});

test("webhook replay is idempotent and later catalog price cannot overwrite", () => {
  const first = applyAuthorizedCheckoutLocks(baseProfile(), {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    currency: "EUR",
    activation_id: "act_1",
    nowIso: NOW,
  });
  const replay = applyAuthorizedCheckoutLocks(first.profile, {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    currency: "EUR",
    activation_id: "act_1",
    nowIso: LATER,
  });
  assert.equal(replay.bumped, false);
  assert.equal(replay.kept_existing, true);
  assert.equal(replay.profile.source_revision, first.profile.source_revision);
  const conflict = applyAuthorizedCheckoutLocks(first.profile, {
    locked_extra_vehicle_unit_cents: 2100,
    locked_extra_driver_unit_cents: 900,
    currency: "EUR",
    nowIso: LATER,
  });
  assert.equal(conflict.ok, false);
  assert.equal(conflict.error, "conflicting_locked_extra_vehicle_unit_cents");
  const addonReplay = applyAuthorizedAddonUnitLock({
    ...first.profile,
    extra_driver_active_quantity: 1,
  }, {
    addon_code: "extra_driver",
    unit_price_cents: 900,
    currency: "EUR",
    nowIso: LATER,
  });
  assert.equal(addonReplay.kept_existing, true);
  const addonConflict = applyAuthorizedAddonUnitLock(first.profile, {
    addon_code: "extra_driver",
    unit_price_cents: 1100,
    currency: "EUR",
    nowIso: LATER,
  });
  assert.equal(addonConflict.error, "conflicting_locked_extra_driver_unit_cents");
});

test("tenant isolation: other-tenant evidence cannot repair this company", () => {
  const profile = baseProfile({
    extra_vehicle_active_quantity: 3,
    extra_driver_active_quantity: 1,
  });
  const r = evaluateLegacyAddonUnitRepair({
    companyCode: "FLX-00001",
    tenantId: "t_a",
    companyId: "c_a",
    subscriptionProfile: profile,
    evidence: {
      immutable: true,
      kind: "checkout_snapshot",
      tenant_id: "t_other",
      company_id: "c_other",
      company_code: "FLX-00002",
      extra_vehicle_unit_cents: 1900,
      extra_driver_unit_cents: 900,
    },
  });
  assert.equal(r.ok, false);
  assert.equal(r.error, BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING);
});

test("founder lock stays on base; addon units lock independently", () => {
  const founder = applyAuthorizedCheckoutLocks(baseProfile({
    locked_price_cents: 5900,
    is_founder_customer: true,
    founder_slot_number: 1,
  }), {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    locked_price_cents: 5900,
    currency: "EUR",
    nowIso: NOW,
  });
  assert.equal(founder.profile.locked_price_cents, 5900);
  assert.equal(founder.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(founder.profile.is_founder_customer, true);
  const lifecycle = preserveLocksOnLifecycleWrite(founder.profile, {
    cancel_at_period_end: true,
  });
  assert.equal(lifecycle.profile.locked_price_cents, 5900);
  assert.equal(lifecycle.profile.locked_extra_driver_unit_cents, 900);
});

test("missing or conflicting unit price fails closed; catalog is not a lock", () => {
  assert.equal(applyAuthorizedCheckoutLocks(baseProfile(), {
    currency: "EUR",
    nowIso: NOW,
  }).error, "checkout_snapshot_addon_units_missing");
  assert.equal(applyAuthorizedCheckoutLocks(baseProfile(), {
    catalog_price_cents: 1900,
    currency: "EUR",
    nowIso: NOW,
  }).error, "catalog_price_is_not_a_lock");
  assert.equal(applyAuthorizedAddonUnitLock(baseProfile(), {
    addon_code: "extra_vehicle",
    catalog_price_cents: 1900,
    currency: "EUR",
    nowIso: NOW,
  }).error, "catalog_price_is_not_a_lock");
  assert.equal(applyAuthorizedAddonUnitLock(baseProfile(), {
    addon_code: "extra_vehicle",
    expected_amount_cents: 950,
    currency: "EUR",
    nowIso: NOW,
  }).error, "proration_amount_is_not_a_lock");
  assert.equal(applyAuthorizedAddonUnitLock(baseProfile(), {
    addon_code: "extra_vehicle",
    currency: "EUR",
    nowIso: NOW,
  }).error, "unit_price_absent");
  assert.equal(applyAuthorizedCheckoutLocks(baseProfile(), {
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
    currency: "USD",
    nowIso: NOW,
  }).error, "currency_mismatch");
  assert.equal(computeLockedRecurringTotal({
    locked_price_cents: 6900,
    extra_vehicle_qty: 3,
    extra_driver_qty: 1,
  }).error, "locked_extra_vehicle_unit_absent");
});

test("integer cents 6900 + 3×1900 + 1×900 = 13500; VAT 2835; gross 16335", () => {
  const composed = computeLockedRecurringTotal({
    locked_price_cents: 6900,
    extra_vehicle_qty: 3,
    extra_driver_qty: 1,
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
  });
  assert.equal(composed.ok, true);
  assert.equal(composed.base_cents, 6900);
  assert.equal(composed.extra_vehicle_cents, 5700);
  assert.equal(composed.extra_driver_cents, 900);
  assert.equal(composed.total_cents, 13500);
  const tax = vatCentsFromExcl(13500, 0.21);
  assert.equal(tax.vat_cents, 2835);
  assert.equal(tax.incl_cents, 16335);
});

test("FLX-00001 repair without immutable evidence is blocked; invoices untouched", () => {
  const invoices = [{ id: "inv_1", amount_cents: 16335 }];
  const payments = [{ id: "tr_1", amount_cents: 16335 }];
  const missing = evaluateLegacyAddonUnitRepair({
    companyCode: "FLX-00001",
    tenantId: "t_a",
    companyId: "c_a",
    subscriptionProfile: baseProfile({
      extra_vehicle_active_quantity: 3,
      extra_driver_active_quantity: 1,
    }),
    evidence: null,
    invoiceRecords: invoices,
    paymentRecords: payments,
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.error, BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING);
  assert.equal(missing.applied, false);
  assert.equal(missing.live, false);
  assert.deepEqual(missing.invoiceRecords, invoices);
  assert.deepEqual(missing.paymentRecords, payments);
  const catalog = evaluateLegacyAddonUnitRepair({
    companyCode: "FLX-00001",
    tenantId: "t_a",
    companyId: "c_a",
    subscriptionProfile: baseProfile(),
    evidence: {
      immutable: true,
      kind: "catalog",
      tenant_id: "t_a",
      company_id: "c_a",
      company_code: "FLX-00001",
      extra_vehicle_unit_cents: 1900,
      extra_driver_unit_cents: 900,
    },
    invoiceRecords: invoices,
    paymentRecords: payments,
  });
  assert.equal(catalog.error, BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING);
  const planned = evaluateLegacyAddonUnitRepair({
    companyCode: "FLX-00001",
    tenantId: "t_a",
    companyId: "c_a",
    subscriptionProfile: baseProfile({
      extra_vehicle_active_quantity: 3,
      extra_driver_active_quantity: 1,
    }),
    evidence: {
      immutable: true,
      kind: "checkout_snapshot",
      tenant_id: "t_a",
      company_id: "c_a",
      company_code: "FLX-00001",
      extra_vehicle_unit_cents: 1900,
      extra_driver_unit_cents: 900,
      recorded_at: NOW,
    },
    invoiceRecords: invoices,
    paymentRecords: payments,
  });
  assert.equal(planned.ok, true);
  assert.equal(planned.live, false);
  assert.equal(planned.applied, false);
  assert.equal(planned.planned, true);
  assert.equal(planned.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(planned.profile.locked_total_recurring_cents, 13500);
  assert.deepEqual(planned.invoiceRecords, invoices);
  assert.deepEqual(planned.paymentRecords, payments);
});

test("legacy qty without lock cannot use live catalog as checkout unit", () => {
  const r = resolveAddonCheckoutUnitFromContract(baseProfile({
    extra_vehicle_active_quantity: 3,
  }), {
    addonCode: "extra_vehicle",
    snapshotUnitCents: 1900,
  });
  assert.equal(r.ok, false);
  assert.equal(r.error, BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING);
  const first = resolveAddonCheckoutUnitFromContract(baseProfile(), {
    addonCode: "extra_vehicle",
    snapshotUnitCents: 1900,
  });
  assert.equal(first.unit_price_cents, 1900);
  assert.equal(first.source, "checkout_snapshot");
  const locked = resolveAddonCheckoutUnitFromContract(baseProfile({
    extra_vehicle_active_quantity: 3,
    locked_extra_vehicle_unit_cents: 1900,
  }), {
    addonCode: "extra_vehicle",
    snapshotUnitCents: 2100,
  });
  assert.equal(locked.unit_price_cents, 1900);
  assert.equal(locked.source, "existing_lock");
});

test("recurring units fail closed without locks when future qty > 0", () => {
  const missing = resolveRecurringAddonUnitsFromLocks(baseProfile({
    extra_vehicle_active_quantity: 3,
  }));
  assert.equal(missing.error, "locked_extra_vehicle_unit_absent");
  const locked = resolveRecurringAddonUnitsFromLocks(baseProfile({
    extra_vehicle_active_quantity: 3,
    extra_driver_active_quantity: 1,
    locked_extra_vehicle_unit_cents: 1900,
    locked_extra_driver_unit_cents: 900,
  }));
  assert.equal(locked.vehicleUnitCents, 1900);
  assert.equal(locked.driverUnitCents, 900);
});

test("worker wires the producer; Flutter billing UI is not edited", () => {
  const worker = readFileSync(join(HERE, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.match(worker, /applyAuthorizedCheckoutLocks/);
  assert.match(worker, /applyAuthorizedAddonUnitLock/);
  assert.match(worker, /locked_extra_vehicle_unit_cents/);
  assert.match(worker, /locked_extra_driver_unit_cents/);
  assert.match(worker, /resolveAddonCheckoutUnitFromContract/);
  assert.match(worker, /resolveRecurringAddonUnitsFromLocks/);
  assert.match(worker, /function _recurringAddonUnitCentsForProfile[\s\S]*?resolveRecurringAddonUnitsFromLocks/);
  const billing = readFileSync(join(HERE, "..", "..", "..", "lib", "main_parts", "company_subscription_billing_state.dart"), "utf8");
  assert.match(billing, /catalog\.extraVehiclePriceCents/);
  assert.match(billing, /catalog\.extraDriverPriceCents/);
  assert.equal(billing.includes("locked_extra_vehicle_unit_cents"), false);
});
