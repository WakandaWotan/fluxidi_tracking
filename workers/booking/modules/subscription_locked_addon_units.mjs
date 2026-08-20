// Canonical subscription producer: persist contractually locked extra-vehicle
// and extra-driver unit prices from an authorized checkout/contract snapshot.
//
// Fail-closed. Null is absent, never zero. Catalog / UI / inventory / current
// price lists are not a lock and are not historical proof.

export const BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING =
  "blocked_legacy_addon_unit_provenance_missing";

export const AUTHORIZED_SNAPSHOT_SOURCES = Object.freeze([
  "checkout_snapshot",
  "addon_checkout_snapshot",
  "contract_snapshot",
  "order_metadata",
  "payment_metadata",
]);

const FORBIDDEN_LOCK_SOURCES = Object.freeze([
  "catalog",
  "ui",
  "inventory",
  "current_catalog",
  "flutter_catalog",
  "price_list",
]);

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function text(value, max = 160) {
  if (value == null) return "";
  return String(value).trim().slice(0, max);
}

function ok(extra = {}) {
  return { ok: true, ...extra };
}

function fail(error, extra = {}) {
  return { ok: false, error, ...extra };
}

/**
 * Integer cents parser. `null` / `undefined` / `""` are absent — never `0`.
 * Rejects booleans and non-integers so `Number(null) === 0` cannot leak.
 */
export function parseIntegerCents(value) {
  if (value === null || value === undefined || value === "") {
    return { ok: true, present: false, value: null };
  }
  if (typeof value === "boolean") {
    return fail("invalid_integer_cents");
  }
  if (typeof value === "string" && value.trim() === "") {
    return { ok: true, present: false, value: null };
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value) || !Number.isInteger(value) || value < 0) {
      return fail("invalid_integer_cents");
    }
    return { ok: true, present: true, value };
  }
  if (typeof value === "string") {
    const trimmed = value.trim();
    if (!/^\d+$/.test(trimmed)) return fail("invalid_integer_cents");
    const n = Number(trimmed);
    if (!Number.isInteger(n) || n < 0) return fail("invalid_integer_cents");
    return { ok: true, present: true, value: n };
  }
  return fail("invalid_integer_cents");
}

export function requirePositiveIntegerCents(value, error = "unit_price_absent") {
  const parsed = parseIntegerCents(value);
  if (!parsed.ok) return parsed;
  if (!parsed.present || parsed.value < 1) return fail(error);
  return parsed;
}

export function qtyOf(value) {
  const parsed = parseIntegerCents(value);
  if (!parsed.ok || !parsed.present) return 0;
  return parsed.value;
}

export function nextSourceRevision(previous, changed) {
  const parsed = parseIntegerCents(previous);
  const prev = parsed.ok && parsed.present ? parsed.value : 0;
  if (!changed && prev >= 1) return { revision: prev, bumped: false };
  return { revision: prev + 1, bumped: true };
}

function requireCurrency(value) {
  const currency = text(value, 8).toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) return fail("invalid_currency");
  return ok({ currency });
}

function isoOrNull(value) {
  const raw = text(value, 48);
  if (!raw) return null;
  const ms = Date.parse(raw);
  return Number.isNaN(ms) ? null : raw;
}

function rejectForbiddenSource(source) {
  const token = text(source, 64).toLowerCase();
  if (!token) return null;
  if (FORBIDDEN_LOCK_SOURCES.includes(token)) return fail("catalog_price_is_not_a_lock");
  return null;
}

export function normalizePriceProvenance(input) {
  if (!isPlainObject(input)) return null;
  const out = {};
  for (const code of ["extra_vehicle", "extra_driver"]) {
    const row = input[code];
    if (!isPlainObject(row)) continue;
    const unit = parseIntegerCents(row.unit_cents ?? row.unit_price_cents);
    if (!unit.ok || !unit.present) continue;
    const source = text(row.source, 64).toLowerCase();
    if (FORBIDDEN_LOCK_SOURCES.includes(source)) continue;
    out[code] = {
      source: source || "checkout_snapshot",
      activation_id: text(row.activation_id ?? row.activationId, 160),
      unit_cents: unit.value,
      recorded_at: text(row.recorded_at ?? row.recordedAt, 48),
    };
  }
  return Object.keys(out).length ? out : null;
}

function stampProvenance(existing, code, row) {
  const current = normalizePriceProvenance(existing) || {};
  return {
    ...current,
    [code]: {
      source: row.source,
      activation_id: row.activation_id || "",
      unit_cents: row.unit_cents,
      recorded_at: row.recorded_at,
    },
  };
}

export function computeLockedRecurringTotal({
  locked_price_cents,
  extra_vehicle_qty = 0,
  extra_driver_qty = 0,
  locked_extra_vehicle_unit_cents = null,
  locked_extra_driver_unit_cents = null,
} = {}) {
  const base = requirePositiveIntegerCents(locked_price_cents, "locked_price_absent");
  if (!base.ok) return base;
  const vQty = qtyOf(extra_vehicle_qty);
  const dQty = qtyOf(extra_driver_qty);
  const vUnit = parseIntegerCents(locked_extra_vehicle_unit_cents);
  const dUnit = parseIntegerCents(locked_extra_driver_unit_cents);
  if (!vUnit.ok) return vUnit;
  if (!dUnit.ok) return dUnit;
  if (vQty > 0 && (!vUnit.present || vUnit.value < 1)) {
    return fail("locked_extra_vehicle_unit_absent");
  }
  if (dQty > 0 && (!dUnit.present || dUnit.value < 1)) {
    return fail("locked_extra_driver_unit_absent");
  }
  const vehicle = vQty === 0 ? 0 : vQty * vUnit.value;
  const driver = dQty === 0 ? 0 : dQty * dUnit.value;
  return ok({
    base_cents: base.value,
    extra_vehicle_cents: vehicle,
    extra_driver_cents: driver,
    total_cents: base.value + vehicle + driver,
  });
}

/** Same rounding the booking Worker uses: Math.round(excl * vatRate). */
export function vatCentsFromExcl(exclCents, vatRate) {
  const excl = parseIntegerCents(exclCents);
  if (!excl.ok || !excl.present) return fail("invalid_integer_cents");
  const rate = Number(vatRate);
  if (!Number.isFinite(rate) || rate < 0) return fail("invalid_vat_rate");
  const vat = Math.round(excl.value * rate);
  return ok({
    excl_cents: excl.value,
    vat_cents: vat,
    incl_cents: excl.value + vat,
  });
}

export function resolveRecurringAddonUnitsFromLocks(profile) {
  if (!isPlainObject(profile)) return fail("missing_profile");
  const vQty = qtyOf(profile.extra_vehicle_active_quantity);
  const dQty = qtyOf(profile.extra_driver_active_quantity);
  const vCancel = qtyOf(profile.extra_vehicle_cancel_at_period_end_quantity);
  const dCancel = qtyOf(profile.extra_driver_cancel_at_period_end_quantity);
  const futureV = Math.max(0, vQty - vCancel);
  const futureD = Math.max(0, dQty - dCancel);
  const vUnit = parseIntegerCents(profile.locked_extra_vehicle_unit_cents);
  const dUnit = parseIntegerCents(profile.locked_extra_driver_unit_cents);
  if (!vUnit.ok) return vUnit;
  if (!dUnit.ok) return dUnit;
  if (futureV > 0 && (!vUnit.present || vUnit.value < 1)) {
    return fail("locked_extra_vehicle_unit_absent");
  }
  if (futureD > 0 && (!dUnit.present || dUnit.value < 1)) {
    return fail("locked_extra_driver_unit_absent");
  }
  return ok({
    vehicleUnitCents: vUnit.present ? vUnit.value : null,
    driverUnitCents: dUnit.present ? dUnit.value : null,
  });
}

/**
 * First paid checkout: persist agreed addon unit prices from the pending
 * checkout snapshot. Existing locks are kept. A conflicting snapshot fails.
 */
export function applyAuthorizedCheckoutLocks(profile, snapshot = {}) {
  if (!isPlainObject(profile)) return fail("missing_profile");
  const forbidden = rejectForbiddenSource(snapshot.source);
  if (forbidden) return forbidden;
  if (snapshot.catalog_price_cents != null && snapshot.locked_extra_vehicle_unit_cents == null
    && snapshot.locked_extra_driver_unit_cents == null) {
    return fail("catalog_price_is_not_a_lock");
  }
  const currency = requireCurrency(snapshot.currency || profile.currency);
  if (!currency.ok) return currency;
  if (profile.currency && text(profile.currency, 8).toUpperCase()
    && text(profile.currency, 8).toUpperCase() !== currency.currency) {
    return fail("currency_mismatch");
  }
  const vehicle = parseIntegerCents(
    snapshot.locked_extra_vehicle_unit_cents ?? snapshot.extra_vehicle_unit_cents,
  );
  const driver = parseIntegerCents(
    snapshot.locked_extra_driver_unit_cents ?? snapshot.extra_driver_unit_cents,
  );
  if (!vehicle.ok) return vehicle;
  if (!driver.ok) return driver;
  if (!vehicle.present || vehicle.value < 1 || !driver.present || driver.value < 1) {
    return fail("checkout_snapshot_addon_units_missing");
  }
  const existingV = parseIntegerCents(profile.locked_extra_vehicle_unit_cents);
  const existingD = parseIntegerCents(profile.locked_extra_driver_unit_cents);
  if (!existingV.ok) return existingV;
  if (!existingD.ok) return existingD;
  if (existingV.present && existingV.value !== vehicle.value) {
    return fail("conflicting_locked_extra_vehicle_unit_cents");
  }
  if (existingD.present && existingD.value !== driver.value) {
    return fail("conflicting_locked_extra_driver_unit_cents");
  }
  const effective = isoOrNull(snapshot.lock_effective_at || snapshot.nowIso);
  if (!effective) return fail("invalid_lock_effective_at");
  const same = existingV.present && existingD.present
    && existingV.value === vehicle.value
    && existingD.value === driver.value;
  if (same) {
    return ok({
      bumped: false,
      kept_existing: true,
      profile: { ...profile },
      source_revision: profile.source_revision ?? null,
    });
  }
  const rev = nextSourceRevision(profile.source_revision, true);
  const next = {
    ...profile,
    locked_extra_vehicle_unit_cents: vehicle.value,
    locked_extra_driver_unit_cents: driver.value,
    currency: currency.currency,
    source_revision: rev.revision,
    updated_at: effective,
    price_provenance: stampProvenance(
      stampProvenance(profile.price_provenance, "extra_vehicle", {
        source: text(snapshot.source, 64) || "checkout_snapshot",
        activation_id: text(snapshot.activation_id, 160),
        unit_cents: vehicle.value,
        recorded_at: effective,
      }),
      "extra_driver",
      {
        source: text(snapshot.source, 64) || "checkout_snapshot",
        activation_id: text(snapshot.activation_id, 160),
        unit_cents: driver.value,
        recorded_at: effective,
      },
    ),
  };
  const snapshotBase = parseIntegerCents(snapshot.locked_price_cents);
  if (snapshotBase.ok && snapshotBase.present) {
    next.locked_price_cents = snapshotBase.value;
  }
  const composed = computeLockedRecurringTotal({
    locked_price_cents: next.locked_price_cents,
    extra_vehicle_qty: next.extra_vehicle_active_quantity,
    extra_driver_qty: next.extra_driver_active_quantity,
    locked_extra_vehicle_unit_cents: next.locked_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: next.locked_extra_driver_unit_cents,
  });
  if (composed.ok) next.locked_total_recurring_cents = composed.total_cents;
  return ok({
    bumped: true,
    kept_existing: false,
    profile: next,
    source_revision: rev.revision,
    composition: composed.ok ? composed : null,
  });
}

/**
 * Add-on activation: lock from pending.unit_price_cents only.
 * First lock wins when equal. Conflict fails. Catalog / proration is not a lock.
 */
export function applyAuthorizedAddonUnitLock(profile, lock = {}) {
  if (!isPlainObject(profile)) return fail("missing_profile");
  const forbidden = rejectForbiddenSource(lock.source);
  if (forbidden) return forbidden;
  if (lock.catalog_price_cents != null && lock.unit_price_cents == null) {
    return fail("catalog_price_is_not_a_lock");
  }
  if (lock.expected_amount_cents != null && lock.unit_price_cents == null) {
    return fail("proration_amount_is_not_a_lock");
  }
  const code = text(lock.addon_code, 64).toLowerCase();
  if (code !== "extra_vehicle" && code !== "extra_driver") {
    return fail("invalid_addon_code");
  }
  const unit = requirePositiveIntegerCents(lock.unit_price_cents, "unit_price_absent");
  if (!unit.ok) return unit;
  const currency = requireCurrency(lock.currency || profile.currency);
  if (!currency.ok) return currency;
  if (profile.currency && text(profile.currency, 8).toUpperCase()
    && text(profile.currency, 8).toUpperCase() !== currency.currency) {
    return fail("currency_mismatch");
  }
  const field = code === "extra_vehicle"
    ? "locked_extra_vehicle_unit_cents"
    : "locked_extra_driver_unit_cents";
  const existing = parseIntegerCents(profile[field]);
  if (!existing.ok) return existing;
  if (existing.present && existing.value !== unit.value) {
    return fail(
      code === "extra_vehicle"
        ? "conflicting_locked_extra_vehicle_unit_cents"
        : "conflicting_locked_extra_driver_unit_cents",
    );
  }
  if (existing.present && existing.value === unit.value) {
    return ok({
      bumped: false,
      kept_existing: true,
      profile: { ...profile },
      source_revision: profile.source_revision ?? null,
    });
  }
  const effective = isoOrNull(lock.lock_effective_at || lock.nowIso);
  if (!effective) return fail("invalid_lock_effective_at");
  const next = {
    ...profile,
    [field]: unit.value,
    currency: currency.currency,
    price_provenance: stampProvenance(profile.price_provenance, code, {
      source: text(lock.source, 64) || "addon_checkout_snapshot",
      activation_id: text(lock.activation_id, 160),
      unit_cents: unit.value,
      recorded_at: effective,
    }),
  };
  const composed = computeLockedRecurringTotal({
    locked_price_cents: next.locked_price_cents,
    extra_vehicle_qty: next.extra_vehicle_active_quantity,
    extra_driver_qty: next.extra_driver_active_quantity,
    locked_extra_vehicle_unit_cents: next.locked_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: next.locked_extra_driver_unit_cents,
  });
  if (composed.ok) next.locked_total_recurring_cents = composed.total_cents;
  const rev = nextSourceRevision(profile.source_revision, true);
  next.source_revision = rev.revision;
  next.updated_at = effective;
  return ok({
    bumped: true,
    kept_existing: false,
    profile: next,
    source_revision: rev.revision,
    composition: composed.ok ? composed : null,
  });
}

/** Quantity changes never rewrite unit locks, including quantity 0. */
export function preserveLocksOnQuantityChange(profile, nextQuantities = {}) {
  if (!isPlainObject(profile)) return fail("missing_profile");
  const next = { ...profile };
  if (nextQuantities.extra_vehicle_active_quantity !== undefined) {
    const q = parseIntegerCents(nextQuantities.extra_vehicle_active_quantity);
    if (!q.ok) return q;
    next.extra_vehicle_active_quantity = q.present ? q.value : 0;
  }
  if (nextQuantities.extra_driver_active_quantity !== undefined) {
    const q = parseIntegerCents(nextQuantities.extra_driver_active_quantity);
    if (!q.ok) return q;
    next.extra_driver_active_quantity = q.present ? q.value : 0;
  }
  next.locked_extra_vehicle_unit_cents = profile.locked_extra_vehicle_unit_cents ?? null;
  next.locked_extra_driver_unit_cents = profile.locked_extra_driver_unit_cents ?? null;
  next.price_provenance = normalizePriceProvenance(profile.price_provenance);
  const composed = computeLockedRecurringTotal({
    locked_price_cents: next.locked_price_cents,
    extra_vehicle_qty: next.extra_vehicle_active_quantity,
    extra_driver_qty: next.extra_driver_active_quantity,
    locked_extra_vehicle_unit_cents: next.locked_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: next.locked_extra_driver_unit_cents,
  });
  if (composed.ok) next.locked_total_recurring_cents = composed.total_cents;
  const changed =
    next.extra_vehicle_active_quantity !== profile.extra_vehicle_active_quantity
    || next.extra_driver_active_quantity !== profile.extra_driver_active_quantity;
  const rev = nextSourceRevision(profile.source_revision, changed);
  next.source_revision = rev.revision;
  return ok({
    bumped: rev.bumped,
    profile: next,
    source_revision: rev.revision,
    composition: composed.ok ? composed : null,
  });
}

export function preserveLocksOnLifecycleWrite(profile, patch = {}) {
  if (!isPlainObject(profile)) return fail("missing_profile");
  const next = { ...profile, ...(isPlainObject(patch) ? patch : {}) };
  next.locked_extra_vehicle_unit_cents = profile.locked_extra_vehicle_unit_cents ?? null;
  next.locked_extra_driver_unit_cents = profile.locked_extra_driver_unit_cents ?? null;
  next.locked_price_cents = profile.locked_price_cents ?? null;
  next.price_provenance = normalizePriceProvenance(profile.price_provenance);
  next.source_revision = profile.source_revision ?? null;
  return ok({ profile: next, kept_existing: true });
}

/**
 * Additional add-on checkout uses the existing lock. First add-on of a type
 * may take unit_price_cents from the checkout snapshot being formed.
 * Legacy qty>0 without a lock fails closed — never the live catalog.
 */
export function resolveAddonCheckoutUnitFromContract(profile, {
  addonCode,
  snapshotUnitCents,
} = {}) {
  if (!isPlainObject(profile)) return fail("missing_profile");
  const code = text(addonCode, 64).toLowerCase();
  if (code !== "extra_vehicle" && code !== "extra_driver") {
    return fail("invalid_addon_code");
  }
  const field = code === "extra_vehicle"
    ? "locked_extra_vehicle_unit_cents"
    : "locked_extra_driver_unit_cents";
  const qtyField = code === "extra_vehicle"
    ? "extra_vehicle_active_quantity"
    : "extra_driver_active_quantity";
  const existing = parseIntegerCents(profile[field]);
  if (!existing.ok) return existing;
  if (existing.present && existing.value >= 1) {
    return ok({ unit_price_cents: existing.value, source: "existing_lock" });
  }
  if (qtyOf(profile[qtyField]) > 0) {
    return fail(BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING);
  }
  const snapshot = requirePositiveIntegerCents(snapshotUnitCents, "unit_price_absent");
  if (!snapshot.ok) return snapshot;
  return ok({ unit_price_cents: snapshot.value, source: "checkout_snapshot" });
}

const AUTHORIZED_EVIDENCE_KINDS = Object.freeze([
  "checkout_snapshot",
  "order_metadata",
  "contract_snapshot",
  "payment_metadata",
]);

function evidenceIsAuthorized(evidence, expectedScope = {}) {
  if (!isPlainObject(evidence) || evidence.immutable !== true) return false;
  const kind = text(evidence.kind, 64).toLowerCase();
  if (!AUTHORIZED_EVIDENCE_KINDS.includes(kind)) return false;
  if (FORBIDDEN_LOCK_SOURCES.includes(kind) || FORBIDDEN_LOCK_SOURCES.includes(text(evidence.source, 64).toLowerCase())) {
    return false;
  }
  const tenant = text(evidence.tenant_id ?? evidence.tenantId, 80);
  const company = text(evidence.company_id ?? evidence.companyId, 80);
  const code = text(evidence.company_code ?? evidence.companyCode, 32).toUpperCase();
  if (expectedScope.tenant_id && tenant !== text(expectedScope.tenant_id, 80)) return false;
  if (expectedScope.company_id && company !== text(expectedScope.company_id, 80)) return false;
  if (expectedScope.company_code && code !== text(expectedScope.company_code, 32).toUpperCase()) {
    return false;
  }
  const vehicle = requirePositiveIntegerCents(evidence.extra_vehicle_unit_cents, "unit_price_absent");
  const driver = requirePositiveIntegerCents(evidence.extra_driver_unit_cents, "unit_price_absent");
  if (!vehicle.ok || !driver.ok) return false;
  return {
    extra_vehicle_unit_cents: vehicle.value,
    extra_driver_unit_cents: driver.value,
    tenant_id: tenant,
    company_id: company,
    company_code: code,
    kind,
  };
}

/**
 * Deterministic repair planner. Never invents catalog amounts.
 * Without immutable checkout/order/contract/payment evidence it stops.
 * Does not write invoices, payments, or live KV.
 */
export function evaluateLegacyAddonUnitRepair({
  companyCode,
  tenantId,
  companyId,
  subscriptionProfile,
  evidence = null,
  invoiceRecords = [],
  paymentRecords = [],
} = {}) {
  const invoices = Array.isArray(invoiceRecords) ? invoiceRecords.map((row) => ({ ...row })) : [];
  const payments = Array.isArray(paymentRecords) ? paymentRecords.map((row) => ({ ...row })) : [];
  const authorized = evidenceIsAuthorized(evidence, {
    tenant_id: tenantId,
    company_id: companyId,
    company_code: companyCode,
  });
  if (!authorized) {
    return {
      ok: false,
      error: BLOCKED_LEGACY_ADDON_UNIT_PROVENANCE_MISSING,
      applied: false,
      live: false,
      invoiceRecords: invoices,
      paymentRecords: payments,
    };
  }
  const applied = applyAuthorizedCheckoutLocks(subscriptionProfile || {}, {
    locked_extra_vehicle_unit_cents: authorized.extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: authorized.extra_driver_unit_cents,
    locked_price_cents: subscriptionProfile?.locked_price_cents,
    currency: subscriptionProfile?.currency || "EUR",
    source: authorized.kind,
    activation_id: text(evidence.activation_id, 160),
    nowIso: text(evidence.recorded_at, 48) || "2026-08-20T00:00:00.000Z",
  });
  if (!applied.ok) {
    return {
      ...applied,
      applied: false,
      live: false,
      invoiceRecords: invoices,
      paymentRecords: payments,
    };
  }
  return {
    ok: true,
    live: false,
    applied: false,
    planned: true,
    profile: applied.profile,
    source_revision: applied.source_revision,
    invoiceRecords: invoices,
    paymentRecords: payments,
  };
}
