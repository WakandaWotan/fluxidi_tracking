/* B12-P1-1 — fail-closed reconciliation of the Billit order total against the
 * authoritative issued invoice total.
 *
 * Why this module exists:
 *   The Billit order-create payload carries OrderLines (Quantity /
 *   UnitPriceExcl / VATPercentage) but NO document-level total, so Billit
 *   derives the order total itself. The issued Fluxidi invoice already has an
 *   authoritative total that is frozen inside `immutable_snapshot.totals` and
 *   covered by `content_hash`. Nothing verified that the two agree.
 *
 *   Two real drift sources exist today:
 *     1. `_normalizeBeStatutoryVatPercentageForBillit` snaps a stored rate in
 *        the 5.95–6.05 band to exactly 6 (likewise 12 and 21) before it reaches
 *        the payload, so a stored 5.98% invoice is sent to Billit as 6%;
 *     2. when the registry record carries no stored line items, one line is
 *        synthesized from `totals.subtotal_ex_vat`, so the line total is only
 *        as consistent as that breakdown.
 *
 *   A Peppol/Billit document whose total disagrees with the legally issued
 *   invoice is a compliance defect, so this module refuses the export instead
 *   of correcting anything.
 *
 * Hard rules for everything in here:
 *   - pure: no KV / DO / fetch / crypto / clock access, no mutation of inputs;
 *   - never rewrites the document, the totals or the order lines;
 *   - never returns or logs buyer data, line descriptions or payload bodies —
 *     only integer cents, counts and stable reason codes;
 *   - all money arithmetic happens in integer cents.
 */

import { safeStr } from "./parsing_utils.js";

/* Stable route-level error code for a refused export. */
export const BILLIT_TOTAL_RECONCILIATION_ERROR =
  "billit_total_reconciliation_failed";

/* Allowed absolute difference between the authoritative document total and the
 * total Billit will derive from the order lines. One cent absorbs a single
 * legitimate half-cent rounding step; anything larger is a real disagreement. */
export const kBillitTotalReconciliationToleranceCents = 1;

/* Guard against binary representation error before rounding to cents:
 * 2.675 * 100 === 267.49999999999997 in IEEE-754, which would round down. */
const _CENTS_EPSILON = 1e-9;

/* Convert a decimal money amount to integer cents, half away from zero.
 * Returns null for anything non-numeric so callers can fail closed rather than
 * silently treating a bad amount as 0. */
export function billitAmountToCents(amount) {
  if (amount === null || amount === undefined || amount === "") return null;
  const value = Number(amount);
  if (!Number.isFinite(value)) return null;
  const scaled = value * 100;
  const nudged = scaled < 0 ? scaled - _CENTS_EPSILON : scaled + _CENTS_EPSILON;
  const rounded = nudged < 0 ? -Math.round(-nudged) : Math.round(nudged);
  return Object.is(rounded, -0) ? 0 : rounded;
}

/* Stable integer key for a VAT percentage (basis points), so 21 and 21.00 group
 * together and float keys never collide by accident. */
function _vatRateKey(vatPercentage) {
  const value = Number(vatPercentage);
  if (!Number.isFinite(value)) return null;
  const scaled = value * 100;
  const nudged = scaled < 0 ? scaled - _CENTS_EPSILON : scaled + _CENTS_EPSILON;
  return nudged < 0 ? -Math.round(-nudged) : Math.round(nudged);
}

function _totalsObject(candidate) {
  return candidate && typeof candidate === "object" && !Array.isArray(candidate)
    ? candidate
    : null;
}

/* Resolve the authoritative total-incl-VAT of an issued document, in cents.
 *
 * `immutable_snapshot.totals` is preferred because it is the hashed content the
 * document number was issued against; the envelope `totals` is only a fallback
 * for records written before the snapshot existed. When BOTH are present and
 * disagree, the envelope has drifted away from the hashed snapshot and the
 * export must be refused rather than guessed.
 *
 * Returns { ok, reason, total_incl_vat_cents, source }. */
export function resolveAuthoritativeIssuedTotalInclVatCents(record) {
  const rec =
    record && typeof record === "object" && !Array.isArray(record) ? record : {};
  const snapshotTotals = _totalsObject(
    _totalsObject(rec.immutable_snapshot ?? rec.immutableSnapshot)?.totals,
  );
  const envelopeTotals = _totalsObject(rec.totals);

  const snapshotCents = snapshotTotals
    ? billitAmountToCents(snapshotTotals.total_incl_vat)
    : null;
  const envelopeCents = envelopeTotals
    ? billitAmountToCents(envelopeTotals.total_incl_vat)
    : null;

  if (snapshotCents === null && envelopeCents === null) {
    return {
      ok: false,
      reason: "missing_authoritative_total",
      total_incl_vat_cents: null,
      source: null,
    };
  }
  if (
    snapshotCents !== null &&
    envelopeCents !== null &&
    snapshotCents !== envelopeCents
  ) {
    return {
      ok: false,
      reason: "authoritative_total_conflict",
      total_incl_vat_cents: null,
      source: null,
    };
  }

  const cents = snapshotCents !== null ? snapshotCents : envelopeCents;
  const source = snapshotCents !== null ? "immutable_snapshot" : "record_totals";
  // A sales invoice worth zero or a negative amount is never a valid Billit
  // Income order; refuse rather than export a nonsensical document.
  if (!Number.isFinite(cents) || cents <= 0) {
    return {
      ok: false,
      reason: "invalid_authoritative_total",
      total_incl_vat_cents: null,
      source,
    };
  }
  return { ok: true, reason: null, total_incl_vat_cents: cents, source };
}

/* Authoritative currency of an issued document, snapshot first. */
export function resolveAuthoritativeIssuedCurrency(record) {
  const rec =
    record && typeof record === "object" && !Array.isArray(record) ? record : {};
  const snapshot = _totalsObject(rec.immutable_snapshot ?? rec.immutableSnapshot);
  return (
    safeStr(snapshot?.currency, 8).toUpperCase() ||
    safeStr(rec.currency, 8).toUpperCase() ||
    ""
  );
}

/* Compute the total-incl-VAT (in cents) that Billit will derive from the exact
 * order lines being sent.
 *
 * VAT is accumulated PER RATE GROUP, not per line: that is how Peppol BIS 3
 * TaxSubtotal and Billit's own order totals work, and it avoids inventing
 * per-line rounding steps that the provider would not perform.
 *
 * Returns { ok, reason, total_incl_vat_cents, subtotal_ex_vat_cents,
 *           vat_cents, line_count, vat_group_count }. */
export function computeBillitOrderLinesTotalInclVatCents(orderLines) {
  const lines = Array.isArray(orderLines) ? orderLines : null;
  if (!lines || lines.length === 0) {
    return {
      ok: false,
      reason: "missing_order_lines",
      total_incl_vat_cents: null,
      subtotal_ex_vat_cents: null,
      vat_cents: null,
      line_count: 0,
      vat_group_count: 0,
    };
  }

  // Accumulate ex-VAT cents per VAT rate group.
  const groups = new Map();
  let lineCount = 0;
  for (const line of lines) {
    if (!line || typeof line !== "object" || Array.isArray(line)) {
      return _lineFailure(lineCount);
    }
    lineCount += 1;

    const quantity = Number(line.Quantity ?? line.quantity);
    const unitPriceExcl = Number(line.UnitPriceExcl ?? line.unit_price_ex_vat);
    const vatPercentage = Number(line.VATPercentage ?? line.vat_rate_percent);
    if (
      !Number.isFinite(quantity) ||
      !Number.isFinite(unitPriceExcl) ||
      !Number.isFinite(vatPercentage) ||
      vatPercentage < 0
    ) {
      return _lineFailure(lineCount);
    }

    const lineExCents = billitAmountToCents(quantity * unitPriceExcl);
    const rateKey = _vatRateKey(vatPercentage);
    if (lineExCents === null || rateKey === null) {
      return _lineFailure(lineCount);
    }
    const existing = groups.get(rateKey);
    if (existing) {
      existing.exCents += lineExCents;
    } else {
      groups.set(rateKey, { exCents: lineExCents, ratePercent: vatPercentage });
    }
  }

  let subtotalExVatCents = 0;
  let vatCents = 0;
  for (const group of groups.values()) {
    subtotalExVatCents += group.exCents;
    // VAT per rate group, rounded once, on integer cents.
    const groupVat = (group.exCents * group.ratePercent) / 100;
    const nudged =
      groupVat < 0 ? groupVat - _CENTS_EPSILON : groupVat + _CENTS_EPSILON;
    const groupVatCents = nudged < 0 ? -Math.round(-nudged) : Math.round(nudged);
    if (!Number.isFinite(groupVatCents)) return _lineFailure(lineCount);
    vatCents += groupVatCents;
  }

  return {
    ok: true,
    reason: null,
    total_incl_vat_cents: subtotalExVatCents + vatCents,
    subtotal_ex_vat_cents: subtotalExVatCents,
    vat_cents: vatCents,
    line_count: lineCount,
    vat_group_count: groups.size,
  };
}

function _lineFailure(lineCount) {
  return {
    ok: false,
    reason: "line_amount_not_computable",
    total_incl_vat_cents: null,
    subtotal_ex_vat_cents: null,
    vat_cents: null,
    line_count: lineCount,
    vat_group_count: 0,
  };
}

/* THE GUARD. Compares the total Billit will derive from `orderLines` against
 * the authoritative issued total on `documentRecord`, fail-closed.
 *
 * Every failure mode returns ok:false with a stable, PII-free reason:
 *   missing_authoritative_total | invalid_authoritative_total |
 *   authoritative_total_conflict | missing_order_lines |
 *   line_amount_not_computable | currency_mismatch | total_mismatch
 *
 * Never mutates the record, the totals or the order lines, and never corrects a
 * mismatch — a refused export is the intended outcome. */
export function reconcileBillitOrderTotalAgainstDocument({
  documentRecord = null,
  orderLines = null,
  orderCurrency = "",
  toleranceCents = kBillitTotalReconciliationToleranceCents,
} = {}) {
  const tolerance =
    Number.isFinite(Number(toleranceCents)) && Number(toleranceCents) >= 0
      ? Math.trunc(Number(toleranceCents))
      : kBillitTotalReconciliationToleranceCents;

  const authoritative = resolveAuthoritativeIssuedTotalInclVatCents(documentRecord);
  if (!authoritative.ok) {
    return {
      ok: false,
      reason: authoritative.reason,
      expected_total_cents: null,
      calculated_total_cents: null,
      delta_cents: null,
      tolerance_cents: tolerance,
      currency: resolveAuthoritativeIssuedCurrency(documentRecord) || null,
      line_count: Array.isArray(orderLines) ? orderLines.length : 0,
      vat_group_count: 0,
    };
  }

  const computed = computeBillitOrderLinesTotalInclVatCents(orderLines);
  if (!computed.ok) {
    return {
      ok: false,
      reason: computed.reason,
      expected_total_cents: authoritative.total_incl_vat_cents,
      calculated_total_cents: null,
      delta_cents: null,
      tolerance_cents: tolerance,
      currency: resolveAuthoritativeIssuedCurrency(documentRecord) || null,
      line_count: computed.line_count,
      vat_group_count: computed.vat_group_count,
    };
  }

  // The payload currency must be the document currency: an identical number in
  // a different currency is not a match.
  const documentCurrency = resolveAuthoritativeIssuedCurrency(documentRecord);
  const payloadCurrency = safeStr(orderCurrency, 8).toUpperCase();
  const currencyMismatch =
    !documentCurrency ||
    !payloadCurrency ||
    documentCurrency !== payloadCurrency;

  const expected = authoritative.total_incl_vat_cents;
  const calculated = computed.total_incl_vat_cents;
  const delta = calculated - expected;

  const base = {
    expected_total_cents: expected,
    calculated_total_cents: calculated,
    delta_cents: delta,
    tolerance_cents: tolerance,
    currency: documentCurrency || null,
    line_count: computed.line_count,
    vat_group_count: computed.vat_group_count,
  };

  if (currencyMismatch) {
    return { ok: false, reason: "currency_mismatch", ...base };
  }
  if (Math.abs(delta) > tolerance) {
    return { ok: false, reason: "total_mismatch", ...base };
  }
  return { ok: true, reason: null, ...base };
}

/* PII-free single-line diagnostic. Emits only integer cents, counts and the
 * reason code — never a line description, buyer field or payload body. */
export function formatBillitTotalReconciliationDiag(result) {
  const r = result && typeof result === "object" ? result : {};
  return [
    `reason=${safeStr(r.reason, 60) || "-"}`,
    `expected_cents=${Number.isFinite(r.expected_total_cents) ? r.expected_total_cents : "-"}`,
    `calculated_cents=${Number.isFinite(r.calculated_total_cents) ? r.calculated_total_cents : "-"}`,
    `delta_cents=${Number.isFinite(r.delta_cents) ? r.delta_cents : "-"}`,
    `tolerance_cents=${Number.isFinite(r.tolerance_cents) ? r.tolerance_cents : "-"}`,
    `currency=${safeStr(r.currency, 8) || "-"}`,
    `lines=${Number.isFinite(r.line_count) ? r.line_count : "-"}`,
    `vat_groups=${Number.isFinite(r.vat_group_count) ? r.vat_group_count : "-"}`,
  ].join(" ");
}

/* Bounded, PII-free response payload for a refused export. Shared by the admin
 * route (json) and the auto-create orchestrator (plain object) so both surface
 * exactly the same fields. */
export function buildBillitTotalReconciliationFailurePayload(result) {
  const r = result && typeof result === "object" ? result : {};
  return {
    ok: false,
    error: BILLIT_TOTAL_RECONCILIATION_ERROR,
    reason: safeStr(r.reason, 60) || "unknown",
    expected_total_cents: Number.isFinite(r.expected_total_cents)
      ? r.expected_total_cents
      : null,
    calculated_total_cents: Number.isFinite(r.calculated_total_cents)
      ? r.calculated_total_cents
      : null,
    delta_cents: Number.isFinite(r.delta_cents) ? r.delta_cents : null,
    tolerance_cents: Number.isFinite(r.tolerance_cents)
      ? r.tolerance_cents
      : kBillitTotalReconciliationToleranceCents,
    currency: safeStr(r.currency, 8) || null,
  };
}
