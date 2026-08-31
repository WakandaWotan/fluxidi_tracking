// PLANNED-PAYMENT-DOCUMENT-REPAIR-P0
// Run: node --test workers/booking/modules/planned_payment_document_repair.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import {
  buildIssuedDocumentPublicMetadata,
  deriveIssuedDocumentPresentationContract,
  projectIssuedDocumentsListEnvelope,
} from "./document_core.js";
import {
  canIssueBusinessInvoiceFromRecord,
  buildConsumerSaleDocumentMetadata,
  resolveBusinessInvoiceIssueGuard,
  resolveConsumerSaleRegistrationGate,
  resolvePaidLifecycleFiscalOwner,
} from "./consumer_billit_sale.mjs";
import {
  isPlannedConsumerCheckoutRecord,
  resolvePlannedCheckoutAuthoritativeAmount,
  resolveStreetCheckoutAuthoritativeAmount,
  streetCheckoutEligibility,
} from "./street_mollie_checkout.js";

const ROOT = dirname(fileURLToPath(import.meta.url));

function plannedPaid(over = {}) {
  return {
    booking_id: "pln-repair-1",
    status: "COMPLETED",
    ride_type: "planned",
    source: "customer_app",
    currency: "EUR",
    payment_status: "paid",
    price_incl_vat: 9.4,
    invoice_intent: "none",
    ...over,
  };
}

function streetPaid(over = {}) {
  return {
    booking_id: "street_repair_1",
    status: "COMPLETED",
    ride_type: "direct",
    source: "street_ride",
    street_ride_fare_finalized: true,
    currency: "EUR",
    payment_status: "unpaid",
    price_incl_vat: 9.4,
    ...over,
  };
}

test("1. planned consumer + cash owns one consumer identity", () => {
  const rec = plannedPaid({ payment_method: "cash" });
  assert.equal(resolvePaidLifecycleFiscalOwner(rec).owner, "consumer_sale");
  assert.equal(canIssueBusinessInvoiceFromRecord(rec), false);
  const gate = resolveConsumerSaleRegistrationGate({
    completed: true,
    businessInvoiceIntent: canIssueBusinessInvoiceFromRecord(rec),
    amountCents: 940,
  });
  assert.equal(gate.action, "create");
});

test("2. planned consumer + QR owns the same consumer identity", () => {
  const rec = plannedPaid({ payment_method: "qr" });
  assert.equal(resolvePaidLifecycleFiscalOwner(rec).owner, "consumer_sale");
  const retry = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 940,
    existingConsumerDocumentId: "doc_one",
    existingConsumerBillitOrderId: "ord_one",
  });
  assert.equal(retry.action, "reuse");
  assert.equal(retry.document_id, "doc_one");
});

test("3. planned consumer + online checkout stays one consumer identity", () => {
  const rec = plannedPaid({ payment_method: "online", payment_status: "unpaid" });
  const eligible = streetCheckoutEligibility(rec, { isPlannedConsumer: true });
  assert.equal(eligible.ok, true);
  assert.equal(resolvePaidLifecycleFiscalOwner(rec).owner, "consumer_sale");
});

test("4. completion/payment/Billit retries reuse the same identity", () => {
  const first = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 940,
  });
  assert.equal(first.action, "create");
  for (const extra of [null, "cash", "qr", "online"]) {
    const again = resolveConsumerSaleRegistrationGate({
      completed: true,
      amountCents: 940,
      existingConsumerDocumentId: "doc_one",
      existingConsumerBillitOrderId: "ord_one",
      paymentMethod: extra,
    });
    assert.equal(again.action, "reuse");
    assert.equal(again.document_id, "doc_one");
  }
});

test("5. no explicit business request → no inv-auto and no Peppol candidate", () => {
  const rec = plannedPaid({ business_detected: true, invoice_intent: "business_invoice" });
  assert.equal(resolvePaidLifecycleFiscalOwner(rec).owner, "consumer_sale");
  const guard = resolveBusinessInvoiceIssueGuard({
    canIssueBusinessInvoice: canIssueBusinessInvoiceFromRecord(rec),
  });
  assert.equal(guard.action, "none");
  const meta = buildConsumerSaleDocumentMetadata({
    bookingId: rec.booking_id,
    amount: { currency: "EUR", value: "9.40" },
  });
  const projected = buildIssuedDocumentPublicMetadata({
    document_id: "doc_one",
    ...meta,
  });
  assert.equal(projected.peppol_applicable, false);
  assert.equal(projected.explicit_business_invoice, false);
});

test("6. explicit valid business request follows replacement/history contract", () => {
  const guard = resolveBusinessInvoiceIssueGuard({
    canIssueBusinessInvoice: true,
    existingConsumerDocumentId: "doc_one",
    explicitBusinessRequest: true,
  });
  assert.equal(guard.action, "create");
  const superseded = buildIssuedDocumentPublicMetadata({
    document_id: "doc_one",
    document_type: "invoice",
    fluxidi_sale_kind: "consumer_sale",
    superseded: true,
    lifecycle_state: "superseded",
    active_revenue: false,
  });
  const business = buildIssuedDocumentPublicMetadata({
    document_id: "doc_biz",
    document_type: "invoice",
    fluxidi_sale_kind: "business_invoice",
    invoice_intent: "business_invoice",
  });
  const list = projectIssuedDocumentsListEnvelope([superseded, business]);
  assert.equal(list.active_payable_count, 1);
  assert.equal(list.review_required, false);
  assert.equal(superseded.active_payable_revenue, false);
  assert.equal(business.active_payable_revenue, true);
});

test("7. PDF fiscal title key equals list metadata", () => {
  const meta = buildConsumerSaleDocumentMetadata({
    bookingId: "pln-repair-1",
    amount: { currency: "EUR", value: "9.40" },
  });
  const projected = buildIssuedDocumentPublicMetadata({
    document_id: "doc_one",
    ...meta,
  });
  const derived = deriveIssuedDocumentPresentationContract(projected);
  assert.equal(projected.presentation_label_key, derived.presentation_label_key);
  assert.equal(projected.fiscal_kind, derived.fiscal_kind);
  assert.equal(projected.presentation_label_key, "consumerSale");
});

test("12. old APK response keys remain intact", () => {
  const projected = buildIssuedDocumentPublicMetadata({
    document_id: "doc_legacy",
    document_type: "invoice",
    document_number: "INV-TEST-2",
  });
  for (const key of [
    "document_id",
    "document_type",
    "document_number",
    "lifecycle_state",
    "fluxidi_sale_kind",
    "presentation_label_key",
  ]) {
    assert.equal(Object.prototype.hasOwnProperty.call(projected, key), true);
  }
  assert.equal(projected.presentation_label_key, "invoiceNeutral");
});

test("10. planned checkout amount matches street availability shape", () => {
  const planned = plannedPaid({ payment_status: "unpaid" });
  const street = streetPaid();
  const plannedAmount = resolvePlannedCheckoutAuthoritativeAmount(planned);
  const streetAmount = resolveStreetCheckoutAuthoritativeAmount(street);
  assert.equal(plannedAmount.ok, true);
  assert.equal(streetAmount.ok, true);
  assert.equal(plannedAmount.amount_cents, streetAmount.amount_cents);
  assert.equal(isPlannedConsumerCheckoutRecord(planned), true);
  assert.equal(isPlannedConsumerCheckoutRecord(street), false);
  assert.equal(
    streetCheckoutEligibility(street, { isStreetDirect: true }).ok,
    true,
  );
  assert.equal(
    streetCheckoutEligibility(planned, { isPlannedConsumer: true }).ok,
    true,
  );
});

test("13. paid lifecycle no longer uses soft businessInvoiceIntent as owner", () => {
  const worker = readFileSync(join(ROOT, "..", "fluxidi_booking_worker.js"), "utf8");
  assert.match(worker, /resolvePaidLifecycleFiscalOwner\(rec\)/);
  assert.match(worker, /canIssueBusinessInvoiceFromRecord\(bookingRecForLegDetection\)/);
  assert.match(worker, /resolveInVehicleCheckoutAuthoritativeAmount\(/);
  assert.doesNotMatch(
    worker,
    /if \(!ctx\.businessInvoiceIntent\) \{\s*const consumerSync/,
  );
});
