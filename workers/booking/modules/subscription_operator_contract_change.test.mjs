// Operator-approved legacy addon-unit contract change.
// Run: node --test workers/booking/modules/subscription_operator_contract_change.test.mjs

import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  computeLockedRecurringTotal,
  vatCentsFromExcl,
} from "./subscription_locked_addon_units.mjs";
import {
  BELGIAN_SAAS_VAT_RATE,
  CONTRACT_SNAPSHOT_SOURCE,
  FLX_00001_OPERATOR_CONTRACT,
  buildCommandCenterSubscriptionSource,
  executeOperatorAddonUnitContractChange,
  planOperatorAddonUnitContractChange,
  renewalUsesNewLocks,
} from "./subscription_operator_contract_change.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const NOW = "2026-08-20T15:00:00.000Z";

function legacyFlx00001(extra = {}) {
  return {
    tenant_id: "t_a",
    company_id: "c_a",
    currency: "EUR",
    market: "BE",
    subscription_status: "active",
    locked_price_cents: 6900,
    extra_vehicle_active_quantity: 3,
    extra_driver_active_quantity: 1,
    extra_vehicle_cancel_at_period_end_quantity: 0,
    extra_driver_cancel_at_period_end_quantity: 0,
    ...extra,
  };
}

function flxRequest(extra = {}) {
  return {
    tenant_id: "t_a",
    company_id: "c_a",
    company_code: "FLX-00001",
    operator_id: "fluxidi.ops.billing",
    reason: "Ratify FLX-00001 addon unit contract from application time",
    effective_at: NOW,
    expected_source_revision: null,
    confirmed: true,
    apply: true,
    confirmed_locked_price_cents: 6900,
    confirmed_extra_vehicle_unit_cents: 1900,
    confirmed_extra_driver_unit_cents: 900,
    confirmed_extra_vehicle_quantity: 3,
    confirmed_extra_driver_quantity: 1,
    idempotency_key: "flx-00001-addon-units-2026-08-20",
    ...extra,
  };
}

function memoryStore(seed = {}) {
  const data = { ...seed };
  const writes = [];
  return {
    data,
    writes,
    async get(key) {
      return Object.prototype.hasOwnProperty.call(data, key) ? data[key] : null;
    },
    async put(key, value) {
      writes.push(key);
      data[key] = value;
    },
  };
}

const SCOPE = { tenant_id: "t_a", company_id: "c_a" };

test("dry-run writes nothing", async () => {
  const store = memoryStore();
  const persisted = [];
  const invoices = [{ id: "inv_1", amount_cents: 16335 }];
  const payments = [{ id: "tr_1", amount_cents: 16335 }];
  const result = await executeOperatorAddonUnitContractChange({
    mode: "dry_run",
    request: flxRequest({ apply: true, confirmed: false }),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
    store,
    persistProfile: async (next) => {
      persisted.push(next);
      return next;
    },
    invoiceRecords: invoices,
    paymentRecords: payments,
  });
  assert.equal(result.ok, true);
  assert.equal(result.dry_run, true);
  assert.equal(result.applied, false);
  assert.deepEqual(result.writes, []);
  assert.equal(store.writes.length, 0);
  assert.equal(persisted.length, 0);
  assert.equal(result.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(result.snapshot.source, CONTRACT_SNAPSHOT_SOURCE);
  assert.equal(result.snapshot.historical_proof, false);
  assert.equal(result.retroactive, false);
});

test("apply without explicit confirmation fails", async () => {
  const store = memoryStore();
  const result = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ confirmed: false }),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
    store,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "confirmation_required");
  assert.equal(result.applied, false);
  assert.equal(store.writes.length, 0);
});

test("apply without apply:true fails", async () => {
  const result = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ apply: false }),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "apply_not_confirmed");
});

test("correct apply creates one new contract revision", async () => {
  const store = memoryStore();
  const persisted = [];
  const result = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
    store,
    persistProfile: async (next) => {
      persisted.push(next);
      return next;
    },
  });
  assert.equal(result.ok, true);
  assert.equal(result.applied, true);
  assert.equal(result.dry_run, false);
  assert.equal(result.source_revision, 1);
  assert.equal(result.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(result.profile.locked_extra_driver_unit_cents, 900);
  assert.equal(result.profile.locked_total_recurring_cents, 13500);
  assert.equal(result.profile.locked_price_cents, 6900);
  assert.equal(result.profile.price_provenance.extra_vehicle.source, CONTRACT_SNAPSHOT_SOURCE);
  assert.equal(result.profile.price_provenance.extra_vehicle.historical_proof, false);
  assert.equal(result.snapshot.source, CONTRACT_SNAPSHOT_SOURCE);
  assert.equal(result.snapshot.not_checkout_evidence, true);
  assert.equal(result.snapshot.not_order_evidence, true);
  assert.equal(result.snapshot.not_payment_evidence, true);
  assert.equal(result.audit.actor.operator_id, "fluxidi.ops.billing");
  assert.equal(result.audit.source_revision_before, null);
  assert.equal(result.audit.source_revision_after, 1);
  assert.equal(result.audit.before.locked_extra_vehicle_unit_cents, null);
  assert.equal(result.audit.after.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(persisted.length, 1);
  assert.equal(store.writes.length, 3);
  assert.ok(store.writes.some((key) => key.includes("contract_snapshot")));
  assert.ok(store.writes.some((key) => key.includes("contract_change:audit")));
  assert.ok(store.writes.some((key) => key.includes("idempotency")));
});

test("replay is idempotent", async () => {
  const store = memoryStore();
  let profile = legacyFlx00001();
  const first = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile,
    nowIso: NOW,
    store,
    persistProfile: async (next) => {
      profile = next;
      return next;
    },
  });
  assert.equal(first.applied, true);
  const writesAfterFirst = store.writes.length;
  const replay = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile,
    nowIso: "2026-08-20T16:00:00.000Z",
    store,
    persistProfile: async (next) => {
      profile = next;
      return next;
    },
  });
  assert.equal(replay.ok, true);
  assert.equal(replay.replayed, true);
  assert.equal(replay.source_revision, first.source_revision);
  assert.equal(store.writes.length, writesAfterFirst);
  const conflict = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({
      confirmed_extra_vehicle_unit_cents: 2100,
      reason: "Different payload same idempotency key xx",
    }),
    scope: SCOPE,
    profile,
    nowIso: NOW,
    store,
  });
  assert.equal(conflict.ok, false);
  assert.equal(conflict.error, "idempotency_key_conflict");
});

test("expected-revision mismatch fails", async () => {
  const result = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ expected_source_revision: 4 }),
    scope: SCOPE,
    profile: legacyFlx00001({ source_revision: 1 }),
    nowIso: NOW,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "expected_source_revision_mismatch");
  assert.equal(result.http_status, 409);
});

test("tenant A cannot change tenant B", async () => {
  const result = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ tenant_id: "t_b", company_id: "c_b" }),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "tenant_mismatch");
  assert.equal(result.http_status, 403);
});

test("quantity and unit price are integer cents", () => {
  const badUnit = planOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ confirmed_extra_vehicle_unit_cents: "19.00" }),
    scope: SCOPE,
    profile: legacyFlx00001(),
  });
  assert.equal(badUnit.ok, false);
  const badQty = planOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ confirmed_extra_vehicle_quantity: 3.5 }),
    scope: SCOPE,
    profile: legacyFlx00001(),
  });
  assert.equal(badQty.ok, false);
  const okInts = planOperatorAddonUnitContractChange({
    mode: "dry_run",
    request: flxRequest({ confirmed: false, apply: false }),
    scope: SCOPE,
    profile: legacyFlx00001(),
  });
  assert.equal(okInts.ok, true);
  assert.equal(okInts.profile.locked_extra_vehicle_unit_cents, 1900);
});

test("existing base lock is preserved", async () => {
  const result = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ confirmed_locked_price_cents: 5900 }),
    scope: SCOPE,
    profile: legacyFlx00001({ locked_price_cents: 6900 }),
    nowIso: NOW,
  });
  assert.equal(result.ok, false);
  assert.equal(result.error, "base_lock_mismatch");
  const kept = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile: legacyFlx00001({ locked_price_cents: 6900 }),
    nowIso: NOW,
  });
  assert.equal(kept.profile.locked_price_cents, 6900);
});

test("historical invoices and payments stay byte-identical", async () => {
  const invoices = [{ id: "inv_1", amount_cents: 16335, pdf: "unchanged" }];
  const payments = [{ id: "tr_1", amount_cents: 16335, provider: "mollie" }];
  const beforeInv = JSON.stringify(invoices);
  const beforePay = JSON.stringify(payments);
  const result = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
    invoiceRecords: invoices,
    paymentRecords: payments,
  });
  assert.equal(result.ok, true);
  assert.equal(JSON.stringify(result.invoiceRecords), beforeInv);
  assert.equal(JSON.stringify(result.paymentRecords), beforePay);
  assert.equal(JSON.stringify(invoices), beforeInv);
  assert.equal(JSON.stringify(payments), beforePay);
});

test("renewal uses the new locks", async () => {
  const applied = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
  });
  const renewal = renewalUsesNewLocks(applied.profile);
  assert.equal(renewal.ok, true);
  assert.equal(renewal.profile.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(renewal.profile.locked_extra_driver_unit_cents, 900);
  assert.equal(renewal.composition.total_cents, 13500);
});

test("Command Center source form contains 1900/900 and total 13500", async () => {
  const applied = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
  });
  const source = applied.command_center_source;
  assert.equal(source.locked_extra_vehicle_unit_cents, 1900);
  assert.equal(source.locked_extra_driver_unit_cents, 900);
  assert.equal(source.locked_total_recurring_cents, 13500);
  assert.equal(source.recurring_total_excl_vat_cents, 13500);
  assert.equal(source.recurring_total_vat_cents, 2835);
  assert.equal(source.recurring_total_incl_vat_cents, 16335);
  assert.equal(source.historical_proof, false);
  const rebuilt = buildCommandCenterSubscriptionSource(applied.profile);
  assert.equal(rebuilt.source.locked_total_recurring_cents, 13500);
});

test("VAT 2835 and gross 16335", () => {
  const composed = computeLockedRecurringTotal({
    locked_price_cents: FLX_00001_OPERATOR_CONTRACT.confirmed_locked_price_cents,
    extra_vehicle_qty: FLX_00001_OPERATOR_CONTRACT.confirmed_extra_vehicle_quantity,
    extra_driver_qty: FLX_00001_OPERATOR_CONTRACT.confirmed_extra_driver_quantity,
    locked_extra_vehicle_unit_cents: FLX_00001_OPERATOR_CONTRACT.confirmed_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: FLX_00001_OPERATOR_CONTRACT.confirmed_extra_driver_unit_cents,
  });
  assert.equal(composed.total_cents, 13500);
  const tax = vatCentsFromExcl(13500, BELGIAN_SAAS_VAT_RATE);
  assert.equal(tax.vat_cents, 2835);
  assert.equal(tax.incl_cents, 16335);
});

test("catalog proposal cannot become a lock", () => {
  const missing = planOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({
      confirmed_extra_vehicle_unit_cents: undefined,
      catalog_proposal: { extra_vehicle_unit_cents: 1900, extra_driver_unit_cents: 900 },
    }),
    scope: SCOPE,
    profile: legacyFlx00001(),
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.error, "confirmation_required");
  const flagged = planOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({ use_catalog: true }),
    scope: SCOPE,
    profile: legacyFlx00001(),
  });
  assert.equal(flagged.ok, false);
  assert.equal(flagged.error, "catalog_price_is_not_a_lock");
});

test("already-locked profile cannot be applied again with a new key", async () => {
  const first = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest(),
    scope: SCOPE,
    profile: legacyFlx00001(),
    nowIso: NOW,
  });
  const second = await executeOperatorAddonUnitContractChange({
    mode: "apply",
    request: flxRequest({
      idempotency_key: "flx-00001-addon-units-retry-2",
      expected_source_revision: first.source_revision,
    }),
    scope: SCOPE,
    profile: first.profile,
    nowIso: NOW,
  });
  assert.equal(second.ok, false);
  assert.equal(second.error, "already_applied");
});

test("worker wires admin dry-run/apply; Flutter UI is not edited", () => {
  const worker = readFileSync(join(HERE, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.match(worker, /\/admin\/subscription\/contract-change\/dry-run/);
  assert.match(worker, /\/admin\/subscription\/contract-change/);
  assert.match(worker, /executeOperatorAddonUnitContractChange/);
  assert.match(worker, /normalizeContractSnapshot/);
  const billing = readFileSync(
    join(HERE, "..", "..", "..", "lib", "main_parts", "company_subscription_billing_state.dart"),
    "utf8",
  );
  assert.match(billing, /catalog\.extraVehiclePriceCents/);
  assert.equal(billing.includes("locked_extra_vehicle_unit_cents"), false);
});
