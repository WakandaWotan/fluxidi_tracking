// PLANNED-CONSUMER-CASH-DOCUMENT-BILLIT-P0-3 — planned cash consumer recovery.
// Run: node --test workers/booking/modules/planned_consumer_cash_document_recovery.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  canIssueBusinessInvoiceFromRecord,
  hasBusinessInvoiceIntent,
  isConsumerSaleEligibleRecord,
  resolveConsumerSaleAmount,
  resolveConsumerSalePaymentSyncGate,
  resolveConsumerSaleRegistrationGate,
  resolveConsumerSaleVatFromSnapshot,
  snapBelgianVatRatePercent,
} from "./consumer_billit_sale.mjs";

function cashPlannedSoftBusiness(over = {}) {
  return {
    booking_id: "2026-08-165",
    status: "COMPLETED",
    stage: "COMPLETED",
    ride_type: "planned",
    source: "flutter_app",
    currency: "EUR",
    payment_status: "paid",
    payment_method: "cash",
    payment_source: "in_car",
    payment_amount: 35.4,
    invoice_intent: "business_invoice",
    invoice_requested: true,
    business_detected: true,
    quote: {
      pricing: { price_incl_vat: "35.40" },
      pricing_main: {
        price_incl_vat: 35.4,
        breakdown: { vat_rate: 0.06, vat_amount: 2, total_incl: 35.4 },
      },
      pricing_profile: { vat_rate: 0.06 },
    },
    operational_legs: [
      {
        leg_id: "2026-08-165:OUTBOUND",
        leg_type: "outbound",
        status: "COMPLETED",
        price_incl_vat: 35.4,
        payment_status: "paid",
        payment_method: "cash",
      },
    ],
    ...over,
  };
}

test("1. paid cash planned soft-business STOP is consumer-sale eligible", () => {
  const rec = cashPlannedSoftBusiness();
  assert.equal(hasBusinessInvoiceIntent(rec), true);
  assert.equal(canIssueBusinessInvoiceFromRecord(rec), false);
  assert.equal(isConsumerSaleEligibleRecord(rec), true);
  const amount = resolveConsumerSaleAmount(rec, {
    legId: "2026-08-165:OUTBOUND",
    legType: "outbound",
  });
  const vat = resolveConsumerSaleVatFromSnapshot(rec);
  assert.equal(amount.ok, true);
  assert.equal(amount.value, "35.40");
  assert.equal(vat.ok, true);
  assert.equal(vat.vat_rate_percent, 6);
  const gate = resolveConsumerSaleRegistrationGate({
    completed: true,
    businessInvoiceIntent: canIssueBusinessInvoiceFromRecord(rec),
    amountCents: amount.cents,
  });
  assert.equal(gate.action, "create");
});

test("2. unpaid planned consumer STOP still creates open sale gate", () => {
  const rec = cashPlannedSoftBusiness({
    payment_status: "unpaid",
    payment_amount: undefined,
    invoice_intent: "none",
    invoice_requested: false,
    business_detected: false,
  });
  assert.equal(isConsumerSaleEligibleRecord(rec), true);
  const amount = resolveConsumerSaleAmount(rec, {
    legId: "2026-08-165:OUTBOUND",
  });
  assert.equal(amount.ok, true);
  assert.equal(
    resolveConsumerSaleRegistrationGate({
      completed: true,
      amountCents: amount.cents,
    }).action,
    "create",
  );
});

test("3. later pay sync updates existing order, no second create", () => {
  const sync = resolveConsumerSalePaymentSyncGate({
    hasConsumerDocument: true,
    hasConsumerBillitOrder: true,
    ridePaid: true,
    billitPaid: false,
  });
  assert.equal(sync.action, "sync_paid");
  assert.equal(sync.creates_new_sale_document, false);
  const reuse = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
    existingConsumerDocumentId: "doc_1",
    existingConsumerBillitOrderId: "ord_1",
  });
  assert.equal(reuse.action, "reuse");
});

test("4+5. repeated STOP/reconcile remain idempotent", () => {
  const first = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
  });
  assert.equal(first.action, "create");
  const again = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
    existingConsumerDocumentId: "doc_1",
    existingConsumerBillitOrderId: "ord_1",
  });
  assert.equal(again.action, "reuse");
  assert.equal(again.document_id, "doc_1");
  assert.equal(again.billit_order_id, "ord_1");
});

test("6. lifecycle COMPLETED + document missing => create", () => {
  const rec = cashPlannedSoftBusiness();
  assert.equal(isConsumerSaleEligibleRecord(rec), true);
  assert.equal(
    resolveConsumerSaleRegistrationGate({
      completed: true,
      businessInvoiceIntent: canIssueBusinessInvoiceFromRecord(rec),
      amountCents: 3540,
      existingConsumerDocumentId: "",
    }).action,
    "create",
  );
});

test("7. document exists + link missing => ensure Billit order (no duplicate doc)", () => {
  const gate = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
    existingConsumerDocumentId: "doc_existing",
    existingConsumerBillitOrderId: "",
  });
  assert.equal(gate.action, "ensure_billit_order");
  assert.equal(gate.document_id, "doc_existing");
});

test("8. Billit order exists + local state missing => reuse order", () => {
  const gate = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
    existingConsumerDocumentId: "doc_1",
    existingConsumerBillitOrderId: "3150999",
  });
  assert.equal(gate.action, "reuse");
  assert.equal(gate.billit_order_id, "3150999");
});

test("9. cash/QR/Tap to Pay share same issuance eligibility chain", () => {
  for (const method of ["cash", "bancontact", "tap_to_pay", "qr"]) {
    const rec = cashPlannedSoftBusiness({
      payment_method: method,
      invoice_intent: "none",
      business_detected: false,
      invoice_requested: false,
    });
    assert.equal(isConsumerSaleEligibleRecord(rec), true, method);
  }
});

test("10. street consumer soft-business remains consumer-sale eligible", () => {
  const rec = cashPlannedSoftBusiness({
    ride_type: "street",
    source: "street_ride",
  });
  assert.equal(isConsumerSaleEligibleRecord(rec), true);
  assert.equal(canIssueBusinessInvoiceFromRecord(rec), false);
});

test("11. real business invoice with VAT customer stays business path", () => {
  const rec = cashPlannedSoftBusiness({
    billing_customer_snapshot: {
      name: "Acme NV",
      vat_number: "BE0123456789",
      company_name: "Acme NV",
    },
  });
  assert.equal(hasBusinessInvoiceIntent(rec), true);
  assert.equal(canIssueBusinessInvoiceFromRecord(rec), true);
  assert.equal(isConsumerSaleEligibleRecord(rec), false);
});

test("12. consumer sale remains Peppol N/A even when soft business flags present", () => {
  const rec = cashPlannedSoftBusiness();
  assert.equal(canIssueBusinessInvoiceFromRecord(rec), false);
  assert.equal(isConsumerSaleEligibleRecord(rec), true);
});

test("13. tenant isolation: gate keys stay booking-scoped (no cross-tenant reuse)", () => {
  const a = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
    existingConsumerDocumentId: "tenantA_doc",
    existingConsumerBillitOrderId: "tenantA_ord",
  });
  const b = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
  });
  assert.equal(a.action, "reuse");
  assert.equal(a.document_id, "tenantA_doc");
  assert.equal(b.action, "create");
  assert.notEqual(b.document_id || "", a.document_id);
});

test("14. amount/VAT/fixed price unchanged for €35.40 / 6%", () => {
  const rec = cashPlannedSoftBusiness();
  const amount = resolveConsumerSaleAmount(rec, {
    legId: "2026-08-165:OUTBOUND",
  });
  const vat = resolveConsumerSaleVatFromSnapshot(rec);
  assert.equal(amount.value, "35.40");
  assert.equal(amount.cents, 3540);
  assert.equal(vat.vat_rate_percent, 6);
  // Billit BE catalog snap: euro-derived 5.99 must become 6.
  assert.equal(snapBelgianVatRatePercent(5.99), 6);
  assert.equal(snapBelgianVatRatePercent(0.06), 6);
});

test("15. registration gate failure path leaves create when no existing doc", () => {
  // Durable retry is stamped by worker stampConsumerSaleFailureOnBooking;
  // gate must still allow create after a prior missing-document failure.
  const gate = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 3540,
    existingConsumerDocumentId: "",
    existingConsumerBillitOrderId: "",
  });
  assert.equal(gate.action, "create");
});
