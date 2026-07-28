/* B12-P1-1 — deterministic unit tests for the Billit total-reconciliation guard.
 *
 * Hermetic: pure functions only, no network, no KV, no Billit, no PDFShift.
 *
 *   node --test workers/booking/modules/billit_total_reconciliation.test.mjs
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  BILLIT_TOTAL_RECONCILIATION_ERROR,
  kBillitTotalReconciliationToleranceCents,
  billitAmountToCents,
  resolveAuthoritativeIssuedTotalInclVatCents,
  resolveAuthoritativeIssuedCurrency,
  computeBillitOrderLinesTotalInclVatCents,
  reconcileBillitOrderTotalAgainstDocument,
  formatBillitTotalReconciliationDiag,
  buildBillitTotalReconciliationFailurePayload,
} from "./billit_total_reconciliation.js";

/* Issued invoice record shaped like buildIssuedDocumentRegistryRecord output:
 * the hashed immutable_snapshot carries the authoritative totals, mirrored on
 * the envelope. */
function issuedInvoice({
  totalInclVat,
  subtotalExVat = null,
  vatAmount = null,
  vatRatePercent = null,
  currency = "EUR",
  envelopeTotalInclVat = undefined,
  omitSnapshot = false,
  omitEnvelope = false,
} = {}) {
  const totals = {
    total_incl_vat: totalInclVat,
    subtotal_ex_vat: subtotalExVat,
    vat_amount: vatAmount,
    vat_rate_percent: vatRatePercent,
  };
  const record = { document_type: "invoice", currency };
  if (!omitSnapshot) {
    record.immutable_snapshot = { currency, totals: { ...totals } };
  }
  if (!omitEnvelope) {
    record.totals = {
      ...totals,
      ...(envelopeTotalInclVat === undefined
        ? {}
        : { total_incl_vat: envelopeTotalInclVat }),
    };
  }
  return record;
}

/* Billit OrderLines exactly as buildBillitOfficialOrderRequestPreview emits. */
function orderLine({ quantity = 1, unitPriceExcl, vatPercentage }) {
  return {
    Quantity: quantity,
    UnitPriceExcl: unitPriceExcl,
    Description: "Taxirit",
    VATPercentage: vatPercentage,
  };
}

// ---------------------------------------------------------------------------
// Integer-cents conversion is decimal-safe (no naked float comparison).
// ---------------------------------------------------------------------------

test("billitAmountToCents rounds half away from zero and survives IEEE-754 drift", () => {
  assert.equal(billitAmountToCents(24.2), 2420);
  assert.equal(billitAmountToCents(0), 0);
  assert.equal(billitAmountToCents("105.98"), 10598);
  // 2.675 * 100 === 267.49999999999997 in IEEE-754; must still round to 268.
  assert.equal(billitAmountToCents(2.675), 268);
  assert.equal(billitAmountToCents(1.005), 101);
  assert.equal(billitAmountToCents(8.615), 862);
  assert.equal(billitAmountToCents(-2.675), -268);
});

test("billitAmountToCents refuses non-numeric input instead of coercing to 0", () => {
  for (const bad of [null, undefined, "", "abc", NaN, Infinity, -Infinity, {}]) {
    assert.equal(billitAmountToCents(bad), null, `expected null for ${String(bad)}`);
  }
});

// ---------------------------------------------------------------------------
// Authoritative total resolution.
// ---------------------------------------------------------------------------

test("authoritative total prefers the hashed immutable snapshot", () => {
  const out = resolveAuthoritativeIssuedTotalInclVatCents(
    issuedInvoice({ totalInclVat: 24.2 }),
  );
  assert.equal(out.ok, true);
  assert.equal(out.total_incl_vat_cents, 2420);
  assert.equal(out.source, "immutable_snapshot");
});

test("authoritative total falls back to envelope totals for pre-snapshot records", () => {
  const out = resolveAuthoritativeIssuedTotalInclVatCents(
    issuedInvoice({ totalInclVat: 24.2, omitSnapshot: true }),
  );
  assert.equal(out.ok, true);
  assert.equal(out.total_incl_vat_cents, 2420);
  assert.equal(out.source, "record_totals");
});

test("envelope drifting away from the hashed snapshot fails closed", () => {
  const out = resolveAuthoritativeIssuedTotalInclVatCents(
    issuedInvoice({ totalInclVat: 24.2, envelopeTotalInclVat: 30.0 }),
  );
  assert.equal(out.ok, false);
  assert.equal(out.reason, "authoritative_total_conflict");
  assert.equal(out.total_incl_vat_cents, null);
});

test("missing and invalid authoritative totals both fail closed", () => {
  const missing = resolveAuthoritativeIssuedTotalInclVatCents({
    document_type: "invoice",
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, "missing_authoritative_total");

  for (const bad of [null, "", "abc", NaN]) {
    const out = resolveAuthoritativeIssuedTotalInclVatCents(
      issuedInvoice({ totalInclVat: bad }),
    );
    assert.equal(out.ok, false, `expected failure for ${String(bad)}`);
    assert.equal(out.reason, "missing_authoritative_total");
  }
  for (const bad of [0, -24.2]) {
    const out = resolveAuthoritativeIssuedTotalInclVatCents(
      issuedInvoice({ totalInclVat: bad }),
    );
    assert.equal(out.ok, false, `expected failure for ${String(bad)}`);
    assert.equal(out.reason, "invalid_authoritative_total");
  }
});

test("authoritative currency prefers the snapshot and normalizes case", () => {
  assert.equal(
    resolveAuthoritativeIssuedCurrency(issuedInvoice({ totalInclVat: 1, currency: "eur" })),
    "EUR",
  );
  assert.equal(resolveAuthoritativeIssuedCurrency(null), "");
});

// ---------------------------------------------------------------------------
// Line total computation: BE statutory rates, quantities, VAT rate grouping.
// ---------------------------------------------------------------------------

test("21% single synthesized fallback line reproduces the document total exactly", () => {
  const out = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ quantity: 1, unitPriceExcl: 20.0, vatPercentage: 21 }),
  ]);
  assert.equal(out.ok, true);
  assert.equal(out.subtotal_ex_vat_cents, 2000);
  assert.equal(out.vat_cents, 420);
  assert.equal(out.total_incl_vat_cents, 2420);
  assert.equal(out.line_count, 1);
  assert.equal(out.vat_group_count, 1);
});

test("6% and 12% BE statutory rates compute exactly", () => {
  const six = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ unitPriceExcl: 100.0, vatPercentage: 6 }),
  ]);
  assert.equal(six.total_incl_vat_cents, 10600);

  const twelve = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ unitPriceExcl: 100.0, vatPercentage: 12 }),
  ]);
  assert.equal(twelve.total_incl_vat_cents, 11200);
});

test("quantity greater than 1 multiplies the ex-VAT base", () => {
  const out = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ quantity: 3, unitPriceExcl: 12.5, vatPercentage: 21 }),
  ]);
  // 3 x 12.50 = 37.50 ex VAT; VAT 7.875 -> 788 cents (half away from zero).
  assert.equal(out.subtotal_ex_vat_cents, 3750);
  assert.equal(out.vat_cents, 788);
  assert.equal(out.total_incl_vat_cents, 4538);
});

test("multiple lines at the same rate share ONE VAT group (Peppol TaxSubtotal model)", () => {
  const out = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ unitPriceExcl: 10.01, vatPercentage: 21 }),
    orderLine({ unitPriceExcl: 10.01, vatPercentage: 21 }),
    orderLine({ unitPriceExcl: 10.01, vatPercentage: 21 }),
  ]);
  assert.equal(out.vat_group_count, 1);
  assert.equal(out.line_count, 3);
  assert.equal(out.subtotal_ex_vat_cents, 3003);
  // Grouped: round(3003 * 0.21) = 631. Per-line rounding would give 3 x 210 = 630,
  // which is exactly the drift this grouping avoids.
  assert.equal(out.vat_cents, 631);
  assert.equal(out.total_incl_vat_cents, 3634);
});

test("mixed VAT rates produce one group per rate", () => {
  const out = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ unitPriceExcl: 100.0, vatPercentage: 21 }),
    orderLine({ unitPriceExcl: 50.0, vatPercentage: 6 }),
  ]);
  assert.equal(out.vat_group_count, 2);
  assert.equal(out.subtotal_ex_vat_cents, 15000);
  assert.equal(out.vat_cents, 2100 + 300);
  assert.equal(out.total_incl_vat_cents, 17400);
});

test("21 and 21.00 normalize to the same VAT group key", () => {
  const out = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ unitPriceExcl: 10.0, vatPercentage: 21 }),
    orderLine({ unitPriceExcl: 10.0, vatPercentage: 21.0 }),
  ]);
  assert.equal(out.vat_group_count, 1);
});

test("0% VAT lines are computable and contribute no VAT", () => {
  const out = computeBillitOrderLinesTotalInclVatCents([
    orderLine({ unitPriceExcl: 40.0, vatPercentage: 0 }),
  ]);
  assert.equal(out.ok, true);
  assert.equal(out.vat_cents, 0);
  assert.equal(out.total_incl_vat_cents, 4000);
});

test("missing, empty and non-array order lines fail closed", () => {
  for (const bad of [null, undefined, [], {}, "lines"]) {
    const out = computeBillitOrderLinesTotalInclVatCents(bad);
    assert.equal(out.ok, false, `expected failure for ${JSON.stringify(bad)}`);
    assert.equal(out.reason, "missing_order_lines");
  }
});

test("uncomputable line fields fail closed rather than defaulting to zero", () => {
  const cases = [
    { quantity: null, unitPriceExcl: 20, vatPercentage: 21 },
    { quantity: 1, unitPriceExcl: null, vatPercentage: 21 },
    { quantity: 1, unitPriceExcl: 20, vatPercentage: null },
    { quantity: 1, unitPriceExcl: 20, vatPercentage: -21 },
    { quantity: "abc", unitPriceExcl: 20, vatPercentage: 21 },
  ];
  for (const c of cases) {
    const out = computeBillitOrderLinesTotalInclVatCents([orderLine(c)]);
    assert.equal(out.ok, false, `expected failure for ${JSON.stringify(c)}`);
    assert.equal(out.reason, "line_amount_not_computable");
  }
  const nonObject = computeBillitOrderLinesTotalInclVatCents([null]);
  assert.equal(nonObject.ok, false);
  assert.equal(nonObject.reason, "line_amount_not_computable");
});

// ---------------------------------------------------------------------------
// THE GUARD: exact match, boundary, mismatch.
// ---------------------------------------------------------------------------

test("exactly equal totals pass with delta 0", () => {
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({
      totalInclVat: 24.2,
      subtotalExVat: 20.0,
      vatRatePercent: 21,
    }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(out.ok, true);
  assert.equal(out.reason, null);
  assert.equal(out.expected_total_cents, 2420);
  assert.equal(out.calculated_total_cents, 2420);
  assert.equal(out.delta_cents, 0);
});

test("a one-cent difference is inside tolerance in BOTH directions", () => {
  const overByOne = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.19 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(overByOne.ok, true);
  assert.equal(overByOne.delta_cents, 1);

  const underByOne = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.21 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(underByOne.ok, true);
  assert.equal(underByOne.delta_cents, -1);
  assert.equal(kBillitTotalReconciliationToleranceCents, 1);
});

test("a two-cent difference fails closed with total_mismatch and reports the delta", () => {
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.18 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "total_mismatch");
  assert.equal(out.expected_total_cents, 2418);
  assert.equal(out.calculated_total_cents, 2420);
  assert.equal(out.delta_cents, 2);
  assert.equal(out.tolerance_cents, 1);
});

test("REGRESSION: a normalized BE VAT rate that differs from the stored rate is caught", () => {
  // _normalizeBeStatutoryVatPercentageForBillit snaps a stored 5.98% into the
  // 6% band before the payload is built. Storage says 100.00 + 5.98% = 105.98;
  // Billit would derive 100.00 + 6% = 106.00. Two cents apart -> refuse.
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({
      totalInclVat: 105.98,
      subtotalExVat: 100.0,
      vatAmount: 5.98,
      vatRatePercent: 5.98,
    }),
    orderLines: [orderLine({ unitPriceExcl: 100.0, vatPercentage: 6 })],
    orderCurrency: "EUR",
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "total_mismatch");
  assert.equal(out.expected_total_cents, 10598);
  assert.equal(out.calculated_total_cents, 10600);
  assert.equal(out.delta_cents, 2);
});

test("the same VAT normalization within one cent still passes (no false positive)", () => {
  // Stored 20.00 + 5.98% = 21.196 -> 2120 cents; normalized 6% -> 21.20 -> 2120.
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({
      totalInclVat: 21.196,
      subtotalExVat: 20.0,
      vatRatePercent: 5.98,
    }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 6 })],
    orderCurrency: "EUR",
  });
  assert.equal(out.ok, true);
  assert.equal(out.delta_cents, 0);
});

test("multi-line mismatch fails closed and still reports both totals", () => {
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 100.0 }),
    orderLines: [
      orderLine({ quantity: 2, unitPriceExcl: 20.0, vatPercentage: 21 }),
      orderLine({ unitPriceExcl: 15.0, vatPercentage: 6 }),
    ],
    orderCurrency: "EUR",
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "total_mismatch");
  // 4000 ex @21% -> 840 VAT; 1500 ex @6% -> 90 VAT; total 6430.
  assert.equal(out.calculated_total_cents, 6430);
  assert.equal(out.expected_total_cents, 10000);
  assert.equal(out.delta_cents, -3570);
  assert.equal(out.vat_group_count, 2);
});

test("a currency that differs from the document fails closed even when the number matches", () => {
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.2, currency: "EUR" }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "USD",
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "currency_mismatch");
  assert.equal(out.delta_cents, 0);
});

test("an absent payload currency fails closed", () => {
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.2 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "",
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "currency_mismatch");
});

test("guard-level failures surface the authoritative-total reasons unchanged", () => {
  const missing = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: { document_type: "invoice", currency: "EUR" },
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(missing.ok, false);
  assert.equal(missing.reason, "missing_authoritative_total");
  assert.equal(missing.calculated_total_cents, null);

  const conflict = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.2, envelopeTotalInclVat: 25.0 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(conflict.ok, false);
  assert.equal(conflict.reason, "authoritative_total_conflict");

  const zeroTotal = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 0 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(zeroTotal.ok, false);
  assert.equal(zeroTotal.reason, "invalid_authoritative_total");
});

test("uncomputable lines fail closed but still report the expected total", () => {
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.2 }),
    orderLines: [orderLine({ unitPriceExcl: null, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "line_amount_not_computable");
  assert.equal(out.expected_total_cents, 2420);
  assert.equal(out.calculated_total_cents, null);
});

test("the guard never mutates the record or the order lines", () => {
  const record = issuedInvoice({ totalInclVat: 24.18 });
  const lines = [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })];
  const recordBefore = JSON.stringify(record);
  const linesBefore = JSON.stringify(lines);
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: record,
    orderLines: lines,
    orderCurrency: "EUR",
  });
  assert.equal(out.ok, false);
  assert.equal(JSON.stringify(record), recordBefore);
  assert.equal(JSON.stringify(lines), linesBefore);
});

test("an explicit zero tolerance rejects the one-cent case", () => {
  const out = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.19 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
    toleranceCents: 0,
  });
  assert.equal(out.ok, false);
  assert.equal(out.reason, "total_mismatch");
  assert.equal(out.tolerance_cents, 0);
});

// ---------------------------------------------------------------------------
// Diagnostics and failure payload carry no PII.
// ---------------------------------------------------------------------------

test("the diagnostic line emits only numbers, counts and the reason code", () => {
  const result = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.18 }),
    orderLines: [
      { ...orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 }), Description: "Jan Peeters, Kortrijkstraat 1" },
    ],
    orderCurrency: "EUR",
  });
  const diag = formatBillitTotalReconciliationDiag(result);
  assert.match(diag, /reason=total_mismatch/);
  assert.match(diag, /expected_cents=2418/);
  assert.match(diag, /calculated_cents=2420/);
  assert.match(diag, /delta_cents=2/);
  assert.match(diag, /lines=1/);
  assert.doesNotMatch(diag, /Jan Peeters/);
  assert.doesNotMatch(diag, /Kortrijkstraat/);
  assert.doesNotMatch(diag, /Taxirit/);
});

test("the failure payload is bounded and carries the stable error code", () => {
  const result = reconcileBillitOrderTotalAgainstDocument({
    documentRecord: issuedInvoice({ totalInclVat: 24.18 }),
    orderLines: [orderLine({ unitPriceExcl: 20.0, vatPercentage: 21 })],
    orderCurrency: "EUR",
  });
  const payload = buildBillitTotalReconciliationFailurePayload(result);
  assert.equal(payload.ok, false);
  assert.equal(payload.error, BILLIT_TOTAL_RECONCILIATION_ERROR);
  assert.equal(payload.error, "billit_total_reconciliation_failed");
  assert.equal(payload.reason, "total_mismatch");
  assert.equal(payload.expected_total_cents, 2418);
  assert.equal(payload.calculated_total_cents, 2420);
  assert.equal(payload.delta_cents, 2);
  assert.equal(payload.currency, "EUR");
  assert.deepEqual(Object.keys(payload).sort(), [
    "calculated_total_cents",
    "currency",
    "delta_cents",
    "error",
    "expected_total_cents",
    "ok",
    "reason",
    "tolerance_cents",
  ]);
});
