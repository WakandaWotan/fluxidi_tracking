// Operator-approved, effective-dated subscription contract change.
// Not a historical backfill. Catalog / UI / inventory are never a lock.
// Provenance is always an immutable contract_snapshot — never checkout,
// order, or payment evidence.

import {
  computeLockedRecurringTotal,
  nextSourceRevision,
  normalizePriceProvenance,
  parseIntegerCents,
  preserveLocksOnLifecycleWrite,
  qtyOf,
  requirePositiveIntegerCents,
  vatCentsFromExcl,
} from "./subscription_locked_addon_units.mjs";

export const CONTRACT_CHANGE_KIND = "operator_approved_contract_change";
export const CONTRACT_SNAPSHOT_SOURCE = "contract_snapshot";
export const BELGIAN_SAAS_VAT_RATE = 0.21;

export const FLX_00001_OPERATOR_CONTRACT = Object.freeze({
  company_code: "FLX-00001",
  confirmed_locked_price_cents: 6900,
  confirmed_extra_vehicle_unit_cents: 1900,
  confirmed_extra_driver_unit_cents: 900,
  confirmed_extra_vehicle_quantity: 3,
  confirmed_extra_driver_quantity: 1,
  locked_total_recurring_cents: 13500,
  vat_cents: 2835,
  incl_cents: 16335,
});

const FORBIDDEN_AUDIT_KEY_RE =
  /(token|secret|password|iban|oauth|api_key|payload|blob|bytes|gps|ping|credential|admin_token|mandate|card|iban)/i;

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function text(value, max = 160) {
  if (value == null) return "";
  return String(value).trim().slice(0, max);
}

function ok(extra = {}) {
  return { ok: true, error: null, ...extra };
}

function fail(error, extra = {}) {
  const httpStatus = extra.http_status || statusFor(error);
  const { http_status: _ignored, ...rest } = extra;
  return {
    ok: false,
    error,
    applied: false,
    dry_run: extra.dry_run === true,
    historical_backfill: false,
    retroactive: false,
    http_status: httpStatus,
    ...rest,
  };
}

function statusFor(error) {
  if (
    error === "tenant_mismatch"
    || error === "tenant_scope_conflict"
    || error === "wrong_tenant"
  ) {
    return 403;
  }
  if (
    error === "expected_source_revision_mismatch"
    || error === "already_applied"
    || error === "idempotency_key_conflict"
    || error === "duplicate_apply"
    || String(error || "").startsWith("conflicting_locked_")
  ) {
    return 409;
  }
  return 400;
}

function isoOrNull(value) {
  const raw = text(value, 48);
  if (!raw) return null;
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$/.test(raw)) return null;
  const ms = Date.parse(raw);
  return Number.isFinite(ms) ? raw.replace(/(\.\d{3})\d+Z$/, "$1Z") : null;
}

function revisionOf(value) {
  const parsed = parseIntegerCents(value);
  if (!parsed.ok) return parsed;
  if (!parsed.present) return { ok: true, value: 0, present: false };
  return { ok: true, value: parsed.value, present: true };
}

export function sanitizeIdempotencyKey(value) {
  const raw = text(value, 160);
  if (!/^[A-Za-z0-9._:-]{8,160}$/.test(raw)) {
    return fail("invalid_idempotency_key");
  }
  return ok({ value: raw });
}

function sanitizeOperatorId(value) {
  const raw = text(value, 80);
  if (!/^[A-Za-z0-9._:@-]{2,80}$/.test(raw)) return fail("invalid_operator_id");
  if (/(token|secret|password|bearer|api[_-]?key)/i.test(raw)) {
    return fail("invalid_operator_id");
  }
  return ok({ value: raw });
}

function sanitizeReason(value) {
  const raw = text(value, 500);
  if (raw.length < 8) return fail("invalid_reason");
  if (/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/.test(raw)) return fail("invalid_reason");
  return ok({ value: raw });
}

function walkForbiddenKeys(value, hits = []) {
  if (Array.isArray(value)) {
    for (const item of value) walkForbiddenKeys(item, hits);
    return hits;
  }
  if (!isPlainObject(value)) return hits;
  for (const [key, child] of Object.entries(value)) {
    if (FORBIDDEN_AUDIT_KEY_RE.test(key)) hits.push(key);
    walkForbiddenKeys(child, hits);
  }
  return hits;
}

export function assertAuditPrivacy(record) {
  const hits = walkForbiddenKeys(record);
  if (hits.length) return fail("forbidden_audit_field", { keys: hits });
  return ok();
}

export function subscriptionContractChangeKeys(tenantId, companyId, idempotencyKey) {
  const tenant = text(tenantId, 80);
  const company = text(companyId, 80);
  const id = text(idempotencyKey, 160);
  if (!tenant || !company || !id) return fail("missing_tenant_scope");
  return ok({
    profile: `tenant:${tenant}:company:${company}:subscription:v1`,
    snapshot: `tenant:${tenant}:company:${company}:subscription:contract_snapshot:${id}:v1`,
    audit: `tenant:${tenant}:company:${company}:subscription:contract_change:audit:${id}:v1`,
    idempotency: `tenant:${tenant}:company:${company}:subscription:contract_change:idempotency:${id}:v1`,
  });
}

export function normalizeContractSnapshot(input) {
  if (!isPlainObject(input)) return null;
  const source = text(input.source ?? input.kind, 64).toLowerCase();
  if (source && source !== CONTRACT_SNAPSHOT_SOURCE && source !== CONTRACT_CHANGE_KIND) {
    return null;
  }
  const vehicle = parseIntegerCents(input.extra_vehicle_unit_cents ?? input.locked_extra_vehicle_unit_cents);
  const driver = parseIntegerCents(input.extra_driver_unit_cents ?? input.locked_extra_driver_unit_cents);
  if (!vehicle.ok || !driver.ok || !vehicle.present || !driver.present) return null;
  return {
    kind: CONTRACT_CHANGE_KIND,
    source: CONTRACT_SNAPSHOT_SOURCE,
    immutable: true,
    historical_proof: false,
    retroactive: false,
    historical_backfill: false,
    contract_change_id: text(input.contract_change_id, 160),
    tenant_id: text(input.tenant_id, 80),
    company_id: text(input.company_id, 80),
    company_code: text(input.company_code, 32).toUpperCase(),
    effective_at: text(input.effective_at, 48),
    recorded_at: text(input.recorded_at, 48),
    locked_price_cents: parseIntegerCents(input.locked_price_cents).value,
    extra_vehicle_unit_cents: vehicle.value,
    extra_driver_unit_cents: driver.value,
    extra_vehicle_quantity: qtyOf(input.extra_vehicle_quantity ?? input.extra_vehicle_active_quantity),
    extra_driver_quantity: qtyOf(input.extra_driver_quantity ?? input.extra_driver_active_quantity),
    locked_total_recurring_cents: parseIntegerCents(input.locked_total_recurring_cents).value,
    recurring_total_vat_cents: parseIntegerCents(input.recurring_total_vat_cents).value,
    recurring_total_incl_vat_cents: parseIntegerCents(input.recurring_total_incl_vat_cents).value,
    source_revision: parseIntegerCents(input.source_revision).present
      ? parseIntegerCents(input.source_revision).value
      : null,
  };
}

function requestFingerprint(parsed) {
  return JSON.stringify({
    tenant_id: parsed.tenant_id,
    company_id: parsed.company_id,
    company_code: parsed.company_code,
    operator_id: parsed.operator_id,
    reason: parsed.reason,
    effective_at: parsed.effective_at,
    expected_source_revision: parsed.expected_source_revision,
    confirmed_locked_price_cents: parsed.confirmed_locked_price_cents,
    confirmed_extra_vehicle_unit_cents: parsed.confirmed_extra_vehicle_unit_cents,
    confirmed_extra_driver_unit_cents: parsed.confirmed_extra_driver_unit_cents,
    confirmed_extra_vehicle_quantity: parsed.confirmed_extra_vehicle_quantity,
    confirmed_extra_driver_quantity: parsed.confirmed_extra_driver_quantity,
  });
}

function financialSlice(profile) {
  return {
    locked_price_cents: profile?.locked_price_cents ?? null,
    locked_extra_vehicle_unit_cents: profile?.locked_extra_vehicle_unit_cents ?? null,
    locked_extra_driver_unit_cents: profile?.locked_extra_driver_unit_cents ?? null,
    extra_vehicle_active_quantity: qtyOf(profile?.extra_vehicle_active_quantity),
    extra_driver_active_quantity: qtyOf(profile?.extra_driver_active_quantity),
    locked_total_recurring_cents: profile?.locked_total_recurring_cents ?? null,
    source_revision: profile?.source_revision ?? null,
  };
}

export function buildCommandCenterSubscriptionSource(profile) {
  if (!isPlainObject(profile)) return fail("missing_profile");
  const composed = computeLockedRecurringTotal({
    locked_price_cents: profile.locked_price_cents,
    extra_vehicle_qty: profile.extra_vehicle_active_quantity,
    extra_driver_qty: profile.extra_driver_active_quantity,
    locked_extra_vehicle_unit_cents: profile.locked_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: profile.locked_extra_driver_unit_cents,
  });
  if (!composed.ok) return composed;
  const tax = vatCentsFromExcl(composed.total_cents, BELGIAN_SAAS_VAT_RATE);
  if (!tax.ok) return tax;
  return ok({
    source: {
      locked_price_cents: composed.base_cents,
      locked_extra_vehicle_unit_cents: profile.locked_extra_vehicle_unit_cents,
      locked_extra_driver_unit_cents: profile.locked_extra_driver_unit_cents,
      extra_vehicle_active_quantity: qtyOf(profile.extra_vehicle_active_quantity),
      extra_driver_active_quantity: qtyOf(profile.extra_driver_active_quantity),
      locked_total_recurring_cents: composed.total_cents,
      recurring_total_excl_vat_cents: composed.total_cents,
      recurring_total_vat_cents: tax.vat_cents,
      recurring_total_incl_vat_cents: tax.incl_cents,
      currency: text(profile.currency, 8).toUpperCase() || "EUR",
      tax_country: text(profile.tax_country || profile.market, 2).toUpperCase() || "BE",
      source_revision: profile.source_revision ?? null,
      price_provenance: normalizePriceProvenance(profile.price_provenance),
      lock_effective_at: text(profile.lock_effective_at, 48) || null,
      contract_snapshot_source: CONTRACT_SNAPSHOT_SOURCE,
      historical_proof: false,
      retroactive: false,
    },
  });
}

export function parseOperatorContractChangeRequest(input = {}, scope = {}) {
  if (!isPlainObject(input)) return fail("invalid_request");
  if (input.use_catalog === true || input.useCatalog === true) {
    return fail("catalog_price_is_not_a_lock");
  }
  const tenant = text(input.tenant_id ?? input.tenantId ?? scope.tenant_id, 80);
  const company = text(input.company_id ?? input.companyId ?? scope.company_id, 80);
  const scopeTenant = text(scope.tenant_id ?? scope.tenantId, 80);
  const scopeCompany = text(scope.company_id ?? scope.companyId, 80);
  if (!tenant || !company) return fail("missing_tenant_scope");
  if (scopeTenant && tenant !== scopeTenant) return fail("tenant_mismatch");
  if (scopeCompany && company !== scopeCompany) return fail("tenant_mismatch");
  const bodyTenant = text(input.tenant_id ?? input.tenantId, 80);
  const bodyCompany = text(input.company_id ?? input.companyId, 80);
  if (bodyTenant && scopeTenant && bodyTenant !== scopeTenant) return fail("tenant_mismatch");
  if (bodyCompany && scopeCompany && bodyCompany !== scopeCompany) return fail("tenant_mismatch");

  const operator = sanitizeOperatorId(input.operator_id ?? input.operatorId);
  if (!operator.ok) return operator;
  const reason = sanitizeReason(input.reason);
  if (!reason.ok) return reason;
  const effective = isoOrNull(input.effective_at ?? input.effectiveAt);
  if (!effective) return fail("invalid_effective_at");
  const idem = sanitizeIdempotencyKey(input.idempotency_key ?? input.idempotencyKey);
  if (!idem.ok) return idem;
  if (!Object.prototype.hasOwnProperty.call(input, "expected_source_revision")
    && !Object.prototype.hasOwnProperty.call(input, "expectedSourceRevision")) {
    return fail("missing_expected_source_revision");
  }
  const expected = revisionOf(input.expected_source_revision ?? input.expectedSourceRevision);
  if (!expected.ok) return fail("invalid_expected_source_revision");

  const base = requirePositiveIntegerCents(
    input.confirmed_locked_price_cents ?? input.confirmedLockedPriceCents,
    "confirmation_required",
  );
  const vehicle = requirePositiveIntegerCents(
    input.confirmed_extra_vehicle_unit_cents ?? input.confirmedExtraVehicleUnitCents,
    "confirmation_required",
  );
  const driver = requirePositiveIntegerCents(
    input.confirmed_extra_driver_unit_cents ?? input.confirmedExtraDriverUnitCents,
    "confirmation_required",
  );
  if (!base.ok) return fail("confirmation_required");
  if (!vehicle.ok) return fail("confirmation_required");
  if (!driver.ok) return fail("confirmation_required");

  const vQty = parseIntegerCents(
    input.confirmed_extra_vehicle_quantity ?? input.confirmedExtraVehicleQuantity,
  );
  const dQty = parseIntegerCents(
    input.confirmed_extra_driver_quantity ?? input.confirmedExtraDriverQuantity,
  );
  if (!vQty.ok || !vQty.present) return fail("confirmation_required");
  if (!dQty.ok || !dQty.present) return fail("confirmation_required");

  const parsed = {
    tenant_id: tenant,
    company_id: company,
    company_code: text(input.company_code ?? input.companyCode, 32).toUpperCase(),
    operator_id: operator.value,
    reason: reason.value,
    effective_at: effective,
    expected_source_revision: expected.present ? expected.value : 0,
    confirmed: input.confirmed === true,
    apply: input.apply === true,
    confirmed_locked_price_cents: base.value,
    confirmed_extra_vehicle_unit_cents: vehicle.value,
    confirmed_extra_driver_unit_cents: driver.value,
    confirmed_extra_vehicle_quantity: vQty.value,
    confirmed_extra_driver_quantity: dQty.value,
    idempotency_key: idem.value,
    catalog_proposal: isPlainObject(input.catalog_proposal) ? input.catalog_proposal : null,
  };
  parsed.fingerprint = requestFingerprint(parsed);
  return ok({ request: parsed });
}

function cloneRecords(rows) {
  return Array.isArray(rows) ? rows.map((row) => (isPlainObject(row) ? { ...row } : row)) : [];
}

function buildImmutableSnapshot(parsed, profile, composition, tax, revision) {
  return {
    kind: CONTRACT_CHANGE_KIND,
    source: CONTRACT_SNAPSHOT_SOURCE,
    immutable: true,
    historical_proof: false,
    retroactive: false,
    historical_backfill: false,
    not_checkout_evidence: true,
    not_order_evidence: true,
    not_payment_evidence: true,
    contract_change_id: parsed.idempotency_key,
    tenant_id: parsed.tenant_id,
    company_id: parsed.company_id,
    company_code: parsed.company_code,
    effective_at: parsed.effective_at,
    recorded_at: parsed.effective_at,
    locked_price_cents: parsed.confirmed_locked_price_cents,
    extra_vehicle_unit_cents: parsed.confirmed_extra_vehicle_unit_cents,
    extra_driver_unit_cents: parsed.confirmed_extra_driver_unit_cents,
    extra_vehicle_quantity: parsed.confirmed_extra_vehicle_quantity,
    extra_driver_quantity: parsed.confirmed_extra_driver_quantity,
    extra_vehicle_active_quantity: parsed.confirmed_extra_vehicle_quantity,
    extra_driver_active_quantity: parsed.confirmed_extra_driver_quantity,
    locked_total_recurring_cents: composition.total_cents,
    recurring_total_vat_cents: tax.vat_cents,
    recurring_total_incl_vat_cents: tax.incl_cents,
    source_revision: revision,
    currency: text(profile.currency, 8).toUpperCase() || "EUR",
  };
}

function buildAuditEntry(parsed, before, after, snapshot, nowIso) {
  const entry = {
    kind: CONTRACT_CHANGE_KIND,
    provenance: CONTRACT_SNAPSHOT_SOURCE,
    actor: { operator_id: parsed.operator_id },
    reason: parsed.reason,
    timestamp: nowIso,
    effective_at: parsed.effective_at,
    tenant_id: parsed.tenant_id,
    company_id: parsed.company_id,
    company_code: parsed.company_code || null,
    idempotency_key: parsed.idempotency_key,
    contract_change_id: parsed.idempotency_key,
    source_revision_before: before.source_revision,
    source_revision_after: after.source_revision,
    before,
    after,
    retroactive: false,
    historical_proof: false,
    historical_backfill: false,
    applies_from: parsed.effective_at,
    contract_snapshot_id: snapshot.contract_change_id,
  };
  const privacy = assertAuditPrivacy(entry);
  if (!privacy.ok) return privacy;
  return ok({ audit: entry });
}

function stampOperatorProvenance(profile, parsed, nowIso) {
  const current = normalizePriceProvenance(profile.price_provenance) || {};
  const row = (unit) => ({
    source: CONTRACT_SNAPSHOT_SOURCE,
    activation_id: "",
    unit_cents: unit,
    recorded_at: nowIso,
    effective_at: parsed.effective_at,
    retroactive: false,
    historical_proof: false,
    contract_change_id: parsed.idempotency_key,
  });
  return {
    ...current,
    extra_vehicle: row(parsed.confirmed_extra_vehicle_unit_cents),
    extra_driver: row(parsed.confirmed_extra_driver_unit_cents),
  };
}

function applyLocksToProfile(profile, parsed, nowIso) {
  const composed = computeLockedRecurringTotal({
    locked_price_cents: parsed.confirmed_locked_price_cents,
    extra_vehicle_qty: parsed.confirmed_extra_vehicle_quantity,
    extra_driver_qty: parsed.confirmed_extra_driver_quantity,
    locked_extra_vehicle_unit_cents: parsed.confirmed_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: parsed.confirmed_extra_driver_unit_cents,
  });
  if (!composed.ok) return composed;
  const tax = vatCentsFromExcl(composed.total_cents, BELGIAN_SAAS_VAT_RATE);
  if (!tax.ok) return tax;
  const rev = nextSourceRevision(profile.source_revision, true);
  const snapshot = buildImmutableSnapshot(parsed, profile, composed, tax, rev.revision);
  const next = {
    ...profile,
    tenant_id: parsed.tenant_id,
    company_id: parsed.company_id,
    locked_price_cents: parsed.confirmed_locked_price_cents,
    locked_extra_vehicle_unit_cents: parsed.confirmed_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: parsed.confirmed_extra_driver_unit_cents,
    extra_vehicle_active_quantity: parsed.confirmed_extra_vehicle_quantity,
    extra_driver_active_quantity: parsed.confirmed_extra_driver_quantity,
    locked_total_recurring_cents: composed.total_cents,
    recurring_amount_cents: composed.total_cents,
    provider_amount_desired_cents: composed.total_cents,
    recurring_total_vat_cents: tax.vat_cents,
    recurring_total_incl_vat_cents: tax.incl_cents,
    lock_effective_at: parsed.effective_at,
    contract_change_id: parsed.idempotency_key,
    contract_snapshot: snapshot,
    price_provenance: stampOperatorProvenance(profile, parsed, parsed.effective_at),
    source_revision: rev.revision,
    updated_at: nowIso,
  };
  return ok({
    profile: next,
    snapshot,
    composition: composed,
    tax,
    source_revision: rev.revision,
  });
}

function unchangedInvoicesPayments(invoiceRecords, paymentRecords) {
  return {
    invoiceRecords: cloneRecords(invoiceRecords),
    paymentRecords: cloneRecords(paymentRecords),
  };
}

function replayResult(parsed, profile, invoiceRecords, paymentRecords, { dryRun }) {
  const source = buildCommandCenterSubscriptionSource(profile);
  return ok({
    dry_run: dryRun,
    applied: !dryRun,
    replayed: true,
    historical_backfill: false,
    retroactive: false,
    http_status: 200,
    contract_change_id: parsed.idempotency_key,
    source_revision: profile.source_revision ?? null,
    profile,
    snapshot: normalizeContractSnapshot(profile.contract_snapshot),
    command_center_source: source.ok ? source.source : null,
    note: "Prices apply from the contract change effective_at and are not retroactive historical proof.",
    writes: [],
    ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
  });
}

export function planOperatorAddonUnitContractChange({
  mode = "dry_run",
  request = {},
  scope = {},
  profile = {},
  nowIso = "2026-08-20T15:00:00.000Z",
  invoiceRecords = [],
  paymentRecords = [],
  existingIdempotencyRecord = null,
} = {}) {
  const dryRun = mode !== "apply";
  const parsedWrap = parseOperatorContractChangeRequest(request, scope);
  if (!parsedWrap.ok) {
    return { ...parsedWrap, dry_run: dryRun, ...unchangedInvoicesPayments(invoiceRecords, paymentRecords) };
  }
  const parsed = parsedWrap.request;
  if (!isPlainObject(profile)) {
    return fail("missing_profile", { dry_run: dryRun, ...unchangedInvoicesPayments(invoiceRecords, paymentRecords) });
  }
  if (dryRun && request.apply === true) {
    // Still a dry-run: never write. Surface that apply was ignored.
    parsed.apply_ignored = true;
  }
  if (!dryRun && parsed.apply !== true) {
    return fail("apply_not_confirmed", {
      dry_run: false,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }
  if (!dryRun && parsed.confirmed !== true) {
    return fail("confirmation_required", {
      dry_run: false,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }

  if (isPlainObject(existingIdempotencyRecord)) {
    const storedFp = text(existingIdempotencyRecord.fingerprint, 2000);
    if (storedFp && storedFp !== parsed.fingerprint) {
      return fail("idempotency_key_conflict", {
        dry_run: dryRun,
        ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
      });
    }
    return replayResult(parsed, profile, invoiceRecords, paymentRecords, { dryRun });
  }

  const existingChangeId = text(profile.contract_change_id || profile.contract_snapshot?.contract_change_id, 160);
  if (existingChangeId && existingChangeId === parsed.idempotency_key) {
    return replayResult(parsed, profile, invoiceRecords, paymentRecords, { dryRun });
  }

  const currentRev = revisionOf(profile.source_revision);
  if (!currentRev.ok) {
    return fail("invalid_source_revision", {
      dry_run: dryRun,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }
  if (currentRev.value !== parsed.expected_source_revision) {
    return fail("expected_source_revision_mismatch", {
      dry_run: dryRun,
      current_source_revision: currentRev.present ? currentRev.value : null,
      expected_source_revision: parsed.expected_source_revision,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }

  const currentBase = requirePositiveIntegerCents(profile.locked_price_cents, "locked_price_absent");
  if (!currentBase.ok) {
    return { ...currentBase, dry_run: dryRun, applied: false, ...unchangedInvoicesPayments(invoiceRecords, paymentRecords) };
  }
  if (currentBase.value !== parsed.confirmed_locked_price_cents) {
    return fail("base_lock_mismatch", {
      dry_run: dryRun,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }
  if (qtyOf(profile.extra_vehicle_active_quantity) !== parsed.confirmed_extra_vehicle_quantity
    || qtyOf(profile.extra_driver_active_quantity) !== parsed.confirmed_extra_driver_quantity) {
    return fail("quantity_confirmation_mismatch", {
      dry_run: dryRun,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }

  const existingV = parseIntegerCents(profile.locked_extra_vehicle_unit_cents);
  const existingD = parseIntegerCents(profile.locked_extra_driver_unit_cents);
  if (!existingV.ok || !existingD.ok) {
    return fail("invalid_integer_cents", {
      dry_run: dryRun,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }
  if (existingV.present !== existingD.present) {
    return fail("incomplete_existing_addon_unit_locks", {
      dry_run: dryRun,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }
  if (existingV.present && existingD.present) {
    if (existingV.value !== parsed.confirmed_extra_vehicle_unit_cents) {
      return fail("conflicting_locked_extra_vehicle_unit_cents", {
        dry_run: dryRun,
        ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
      });
    }
    if (existingD.value !== parsed.confirmed_extra_driver_unit_cents) {
      return fail("conflicting_locked_extra_driver_unit_cents", {
        dry_run: dryRun,
        ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
      });
    }
    return fail("already_applied", {
      dry_run: dryRun,
      ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
    });
  }

  const applied = applyLocksToProfile(profile, parsed, nowIso);
  if (!applied.ok) {
    return { ...applied, dry_run: dryRun, applied: false, ...unchangedInvoicesPayments(invoiceRecords, paymentRecords) };
  }
  const before = financialSlice(profile);
  const after = financialSlice(applied.profile);
  const auditWrap = buildAuditEntry(parsed, before, after, applied.snapshot, nowIso);
  if (!auditWrap.ok) {
    return { ...auditWrap, dry_run: dryRun, ...unchangedInvoicesPayments(invoiceRecords, paymentRecords) };
  }
  const cc = buildCommandCenterSubscriptionSource(applied.profile);
  const keys = subscriptionContractChangeKeys(
    parsed.tenant_id,
    parsed.company_id,
    parsed.idempotency_key,
  );
  return ok({
    dry_run: dryRun,
    applied: false,
    planned: true,
    historical_backfill: false,
    retroactive: false,
    http_status: 200,
    request: parsed,
    profile: applied.profile,
    snapshot: applied.snapshot,
    audit: auditWrap.audit,
    keys: keys.ok ? keys : null,
    source_revision: applied.source_revision,
    command_center_source: cc.ok ? cc.source : null,
    read_only_catalog_proposal: parsed.catalog_proposal,
    catalog_used_as_lock: false,
    note: "New prices apply from effective_at. They are not retroactive historical proof.",
    ...unchangedInvoicesPayments(invoiceRecords, paymentRecords),
  });
}

export async function executeOperatorAddonUnitContractChange({
  mode = "dry_run",
  request = {},
  scope = {},
  profile = {},
  nowIso = "2026-08-20T15:00:00.000Z",
  invoiceRecords = [],
  paymentRecords = [],
  store = null,
  persistProfile = null,
} = {}) {
  const dryRun = mode !== "apply";
  let existingIdempotencyRecord = null;
  const parsedPreview = parseOperatorContractChangeRequest(request, scope);
  if (parsedPreview.ok && store && typeof store.get === "function") {
    const keys = subscriptionContractChangeKeys(
      parsedPreview.request.tenant_id,
      parsedPreview.request.company_id,
      parsedPreview.request.idempotency_key,
    );
    if (keys.ok) {
      existingIdempotencyRecord = await store.get(keys.idempotency);
    }
  }
  const planned = planOperatorAddonUnitContractChange({
    mode,
    request,
    scope,
    profile,
    nowIso,
    invoiceRecords,
    paymentRecords,
    existingIdempotencyRecord,
  });
  if (!planned.ok) return planned;
  if (dryRun) {
    return {
      ...planned,
      dry_run: true,
      applied: false,
      writes: [],
    };
  }
  if (planned.replayed) {
    return { ...planned, applied: true, writes: [] };
  }
  const writes = [];
  if (typeof persistProfile === "function") {
    const saved = await persistProfile(planned.profile);
    writes.push("subscription_profile");
    planned.profile = saved || planned.profile;
  } else if (store && planned.keys?.profile) {
    await store.put(planned.keys.profile, {
      version: 1,
      updated_at: nowIso,
      subscription_profile: planned.profile,
    });
    writes.push(planned.keys.profile);
  }
  if (store && planned.keys?.snapshot) {
    await store.put(planned.keys.snapshot, planned.snapshot);
    writes.push(planned.keys.snapshot);
  }
  if (store && planned.keys?.audit) {
    await store.put(planned.keys.audit, planned.audit);
    writes.push(planned.keys.audit);
  }
  if (store && planned.keys?.idempotency) {
    await store.put(planned.keys.idempotency, {
      fingerprint: planned.request.fingerprint,
      contract_change_id: planned.request.idempotency_key,
      source_revision: planned.source_revision,
      written_at: nowIso,
    });
    writes.push(planned.keys.idempotency);
  }
  return {
    ...planned,
    dry_run: false,
    applied: true,
    planned: false,
    writes,
  };
}

export function renewalUsesNewLocks(profile) {
  const preserved = preserveLocksOnLifecycleWrite(profile, {
    current_period_start: "2026-09-20T00:00:00.000Z",
    current_period_end: "2026-10-20T00:00:00.000Z",
  });
  if (!preserved.ok) return preserved;
  const composed = computeLockedRecurringTotal({
    locked_price_cents: preserved.profile.locked_price_cents,
    extra_vehicle_qty: preserved.profile.extra_vehicle_active_quantity,
    extra_driver_qty: preserved.profile.extra_driver_active_quantity,
    locked_extra_vehicle_unit_cents: preserved.profile.locked_extra_vehicle_unit_cents,
    locked_extra_driver_unit_cents: preserved.profile.locked_extra_driver_unit_cents,
  });
  return { ...preserved, composition: composed };
}
