/* DOCUMENT-PRESENTATION-CONTRACT-P0C
 *
 *   node --test workers/booking/modules/document_presentation_contract.test.mjs
 */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildIssuedDocumentPublicMetadata,
  deriveIssuedDocumentPresentationContract,
  projectIssuedDocumentsListEnvelope,
} from "./document_core.js";
import {
  CONSUMER_SALE_KIND,
  activeRevenueDocumentsAfterConversion,
  buildConsumerSaleDocumentMetadata,
  isActiveRevenueDocument,
  resolveConsumerSaleRegistrationGate,
} from "./consumer_billit_sale.mjs";

const LEGACY_PUBLIC_KEYS = [
  "document_id",
  "document_type",
  "document_number",
  "proof_reference",
  "lifecycle_state",
  "document_status",
  "issue_timestamp",
  "currency",
  "content_hash",
  "source_booking_id",
  "source_leg_id",
  "source_leg_type",
  "fluxidi_sale_kind",
  "sale_kind",
  "presentation_label_key",
  "invoice_intent",
  "created_by_role",
  "peppol_applicable",
  "superseded",
  "billit_export",
  "billit_link_status",
];

test("one private ride yields one active consumer-sale revenue identity", () => {
  const meta = buildConsumerSaleDocumentMetadata({
    bookingId: "bk_private_1",
    amount: { currency: "EUR", value: "25.00" },
  });
  const projected = buildIssuedDocumentPublicMetadata({
    document_id: "doc_consumer_1",
    document_type: meta.document_type,
    ...meta,
  });
  assert.equal(projected.fiscal_kind, "consumer_sale");
  assert.equal(projected.consumer_sale, true);
  assert.equal(projected.explicit_business_invoice, false);
  assert.equal(projected.presentation_label_key, "consumerSale");
  assert.equal(projected.peppol_applicable, false);
  assert.equal(projected.active_payable_revenue, true);
  assert.equal(projected.fiscal_identity, "doc_consumer_1");
  assert.equal(projected.document_type, "invoice");
  assert.notEqual(projected.presentation_label_key, "invoice");
  const list = projectIssuedDocumentsListEnvelope([projected]);
  assert.equal(list.active_payable_count, 1);
  assert.equal(list.documents.length, 1);
});

test("repeated completion/payment/retry reuses the same consumer identity", () => {
  const first = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 2500,
  });
  assert.equal(first.action, "create");
  const retry = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 2500,
    existingConsumerDocumentId: "doc_consumer_1",
    existingConsumerBillitOrderId: "ord_keep",
  });
  assert.equal(retry.action, "reuse");
  assert.equal(retry.document_id, "doc_consumer_1");
  const paymentRetry = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 2500,
    existingConsumerDocumentId: "doc_consumer_1",
    existingConsumerBillitOrderId: "ord_keep",
  });
  assert.equal(paymentRetry.document_id, retry.document_id);
  assert.equal(
    isActiveRevenueDocument({
      saleKind: CONSUMER_SALE_KIND,
      superseded: false,
    }),
    true,
  );
});

test("explicit business conversion cannot double-count active revenue", () => {
  const converted = activeRevenueDocumentsAfterConversion({
    consumerSuperseded: true,
    creditNotePresent: true,
    businessInvoicePresent: true,
  });
  assert.equal(converted.ok, true);
  assert.equal(converted.double_active_sales, false);
  assert.deepEqual(converted.active, ["business_invoice"]);

  const consumer = buildIssuedDocumentPublicMetadata({
    document_id: "doc_consumer_1",
    document_type: "invoice",
    fluxidi_sale_kind: "consumer_sale",
    superseded: true,
    active_revenue: false,
    lifecycle_state: "superseded",
  });
  const credit = buildIssuedDocumentPublicMetadata({
    document_id: "doc_credit_1",
    document_type: "credit_note",
    fluxidi_sale_kind: "credit_note",
  });
  const business = buildIssuedDocumentPublicMetadata({
    document_id: "doc_business_1",
    document_type: "invoice",
    fluxidi_sale_kind: "business_invoice",
    invoice_intent: "business_invoice",
  });
  const list = projectIssuedDocumentsListEnvelope([consumer, credit, business]);
  assert.equal(list.documents.length, 3);
  assert.equal(list.active_payable_count, 1);
  assert.equal(consumer.active_payable_revenue, false);
  assert.equal(credit.active_payable_revenue, false);
  assert.equal(business.active_payable_revenue, true);
  assert.equal(business.explicit_business_invoice, true);
  assert.equal(consumer.consumer_sale, true);
});

test("consumer sale metadata cannot be classified as business", () => {
  const projected = buildIssuedDocumentPublicMetadata({
    document_id: "doc_consumer_2",
    document_type: "invoice",
    fluxidi_sale_kind: "consumer_sale",
    created_by_role: "system_consumer_sale",
    peppol_applicable: false,
  });
  assert.equal(projected.fiscal_kind, "consumer_sale");
  assert.equal(projected.explicit_business_invoice, false);
  assert.equal(projected.presentation_label_key, "consumerSale");
  assert.notEqual(projected.fiscal_kind, "business_invoice");
});

test("default list keeps historical rows but only one active payable", () => {
  const rows = [
    buildIssuedDocumentPublicMetadata({
      document_id: "doc_consumer_1",
      document_type: "invoice",
      fluxidi_sale_kind: "consumer_sale",
      superseded: true,
    }),
    buildIssuedDocumentPublicMetadata({
      document_id: "doc_business_1",
      document_type: "invoice",
      fluxidi_sale_kind: "business_invoice",
      invoice_intent: "business_invoice",
    }),
  ];
  const list = projectIssuedDocumentsListEnvelope(rows);
  assert.equal(list.documents.length, 2);
  assert.equal(list.active_payable_count, 1);
  assert.equal(list.documents[0].superseded, true);
  assert.equal(list.documents[0].active_payable_revenue, false);
});

test("legacy public keys remain present and new fields are additive", () => {
  const projected = buildIssuedDocumentPublicMetadata({
    document_id: "doc_legacy_1",
    document_type: "invoice",
    document_number: "INV-TEST-1",
    lifecycle_state: "issued",
  });
  for (const key of LEGACY_PUBLIC_KEYS) {
    assert.equal(Object.prototype.hasOwnProperty.call(projected, key), true);
  }
  assert.equal(projected.document_type, "invoice");
  assert.equal(projected.document_id, "doc_legacy_1");
  assert.equal(projected.fiscal_kind, "unspecified");
  assert.equal(projected.presentation_label_key, "invoiceNeutral");
  assert.equal(projected.explicit_business_invoice, false);
  assert.equal(projected.consumer_sale, false);
  assert.equal(projected.fiscal_identity, "doc_legacy_1");
});

test("bare invoice without business evidence stays fiscally unspecified", () => {
  const derived = deriveIssuedDocumentPresentationContract({
    document_id: "doc_bare",
    document_type: "invoice",
  });
  assert.equal(derived.fiscal_kind, "unspecified");
  assert.equal(derived.presentation_label_key, "invoiceNeutral");
  assert.equal(derived.explicit_business_invoice, false);
  assert.equal(derived.peppol_applicable, null);
});
