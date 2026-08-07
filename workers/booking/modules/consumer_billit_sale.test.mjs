// CONSUMER-BILLIT-SERVER-CONTRACT-1 — pure decision tests
// Run: node --test workers/booking/modules/consumer_billit_sale.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  CONSUMER_SALE_BILLIT_ORDER_TYPE,
  CONSUMER_SALE_KIND,
  CONSUMER_SALE_INTENT_STATES,
  activeRevenueDocumentsAfterConversion,
  buildBillitConsumerSaleOrderCreateIdempotencyKey,
  buildConsumerBillitSaleIntentKey,
  buildConsumerConversionCreditIdempotencyKey,
  buildConsumerConversionLinkTrail,
  buildConsumerSaleDocumentMetadata,
  buildConsumerSaleIdempotencyKey,
  consumerSalePeppolPolicy,
  consumerSalePresentation,
  creditNoteTotalsMatchConsumerSale,
  canIssueBusinessInvoiceFromRecord,
  hasBusinessInvoiceIntent,
  hasMeaningfulBusinessBillingCustomer,
  isActiveRevenueDocument,
  isConsumerSaleEligibleRecord,
  mapConsumerSalePaymentMethodLabel,
  reconcileConsumerBillitCreateDecision,
  resolveConsumerSaleAmount,
  resolveConsumerSaleIssueOwnerDecision,
  resolveConsumerSalePaymentSyncGate,
  resolveConsumerSaleRegistrationGate,
  resolveConsumerSaleVatFromSnapshot,
  resolveConsumerToBusinessConversionDecision,
  roundtripAvoidsDoubleRevenue,
  shouldWarnMissingPeppolEndpointForSale,
} from "./consumer_billit_sale.mjs";

function planned(over = {}) {
  return {
    booking_id: "bk_plan_1",
    status: "COMPLETED",
    ride_type: "planned",
    source: "customer_app",
    price_incl_vat: 42.5,
    currency: "EUR",
    vat_rate_percent: 6,
    invoice_intent: "none",
    ...over,
  };
}

function street(over = {}) {
  return {
    booking_id: "street_1001_abc",
    status: "COMPLETED",
    ride_type: "direct",
    source: "street_ride",
    street_ride_fare_finalized: true,
    price_incl_vat: 18.6,
    currency: "EUR",
    vat_rate_percent: 6,
    invoice_intent: "none",
    ...over,
  };
}

test("1. planned ride uses fixed leg/booking price", () => {
  const out = resolveConsumerSaleAmount(
    planned({ leg_price_incl_vat: 22.5, price_incl_vat: 99 }),
  );
  assert.equal(out.ok, true);
  assert.equal(out.value, "22.50");
  assert.equal(out.source, "leg_price_incl_vat");
});

test("2. street ride uses finalized fare", () => {
  const out = resolveConsumerSaleAmount(street());
  assert.equal(out.ok, true);
  assert.equal(out.value, "18.60");
  assert.equal(out.source, "street_finalized");
  assert.equal(
    resolveConsumerSaleAmount(street({ street_ride_fare_finalized: false })).error,
    "street_fare_not_finalized",
  );
});

test("3. VAT comes from company/document snapshot (never invent 21)", () => {
  const fromBooking = resolveConsumerSaleVatFromSnapshot(planned({ vat_rate_percent: 6 }));
  assert.equal(fromBooking.ok, true);
  assert.equal(fromBooking.vat_rate_percent, 6);
  assert.equal(fromBooking.source, "booking_snapshot");

  const fromCompany = resolveConsumerSaleVatFromSnapshot(
    planned({ vat_rate_percent: undefined }),
    { default_vat_rate_percent: 12 },
  );
  assert.equal(fromCompany.ok, true);
  assert.equal(fromCompany.vat_rate_percent, 12);
  assert.equal(fromCompany.source, "company_tax_snapshot");

  const missing = resolveConsumerSaleVatFromSnapshot(
    planned({ vat_rate_percent: undefined }),
    {},
  );
  assert.equal(missing.ok, false);
});

test("4+5+6. consumer sale created once; STOP/retry/reconcile reuse", () => {
  const first = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 4250,
  });
  assert.equal(first.action, "create");

  const retry = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 4250,
    existingConsumerDocumentId: "doc_1",
    existingConsumerBillitOrderId: "ord_1",
  });
  assert.equal(retry.action, "reuse");
  assert.equal(retry.billit_order_id, "ord_1");

  const reconcile = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 4250,
    existingConsumerDocumentId: "doc_1",
  });
  assert.equal(reconcile.action, "ensure_billit_order");
});

test("7. payment update syncs existing document; never creates second sale", () => {
  const sync = resolveConsumerSalePaymentSyncGate({
    ridePaid: true,
    hasConsumerDocument: true,
    hasConsumerBillitOrder: true,
  });
  assert.equal(sync.action, "sync_paid");
  assert.equal(sync.creates_new_sale_document, false);

  const missingOrder = resolveConsumerSalePaymentSyncGate({
    ridePaid: true,
    hasConsumerDocument: true,
    hasConsumerBillitOrder: false,
  });
  assert.equal(missingOrder.creates_new_sale_document, false);
});

test("8. Tap to Pay paid maps as provider-confirmed terminal method", () => {
  const m = mapConsumerSalePaymentMethodLabel({
    paymentMethod: "pointofsale",
    paymentProvider: "mollie",
    paymentSource: "tap_to_pay",
  });
  assert.equal(m.key, "tapToPay");
  assert.equal(m.provider_confirmed, true);
  assert.equal(m.manual, false);
});

test("9. cash/manual Bancontact stay distinct from provider payments", () => {
  assert.equal(
    mapConsumerSalePaymentMethodLabel({ paymentMethod: "cash" }).manual,
    true,
  );
  const bancontact = mapConsumerSalePaymentMethodLabel({
    paymentMethod: "bancontact",
  });
  assert.equal(bancontact.key, "bancontactManual");
  assert.equal(bancontact.manual, true);
  assert.equal(bancontact.provider_confirmed, false);
});

test("10+11. consumer sale never triggers Peppol / missing-endpoint warnings", () => {
  const peppol = consumerSalePeppolPolicy();
  assert.equal(peppol.peppol_applicable, false);
  assert.equal(peppol.peppol_required, false);
  assert.equal(peppol.peppol_sent, false);
  assert.equal(peppol.suppress_missing_endpoint_warning, true);
  assert.equal(
    shouldWarnMissingPeppolEndpointForSale({ saleKind: CONSUMER_SALE_KIND }),
    false,
  );
});

test("12. issuable business invoice is not treated as consumer sale", () => {
  const realBusiness = planned({
    invoice_intent: "business_invoice",
    billing_customer_snapshot: {
      customer_type: "business",
      legal_name: "Acme BV",
      vat_number: "BE0123456789",
    },
  });
  assert.equal(hasBusinessInvoiceIntent(realBusiness), true);
  assert.equal(hasMeaningfulBusinessBillingCustomer(realBusiness), true);
  assert.equal(canIssueBusinessInvoiceFromRecord(realBusiness), true);
  assert.equal(isConsumerSaleEligibleRecord(realBusiness), false);
  assert.equal(
    resolveConsumerSaleRegistrationGate({
      completed: true,
      amountCents: 1000,
      businessInvoiceIntent: true,
    }).reason,
    "business_invoice_active",
  );
});

test("12b. soft business flags without billing customer still get consumer sale", () => {
  // Field evidence 2026-08-165: invoice_intent=business_invoice but no snapshot.
  const soft = planned({
    invoice_intent: "business_invoice",
    invoice_requested: true,
    business_detected: true,
    operational_legs: [
      {
        leg_id: "bk_plan_1:OUTBOUND",
        leg_type: "outbound",
        price_incl_vat: 35.4,
        status: "COMPLETED",
      },
    ],
  });
  assert.equal(hasBusinessInvoiceIntent(soft), true);
  assert.equal(hasMeaningfulBusinessBillingCustomer(soft), false);
  assert.equal(canIssueBusinessInvoiceFromRecord(soft), false);
  assert.equal(isConsumerSaleEligibleRecord(soft), true);
  const amount = resolveConsumerSaleAmount(soft, {
    legId: "bk_plan_1:OUTBOUND",
    legType: "outbound",
  });
  assert.equal(amount.ok, true);
  assert.equal(amount.value, "35.40");
  assert.equal(amount.source, "operational_leg_price");
});

test("12c. quote VAT snapshot is accepted (fraction or percent)", () => {
  const fromQuote = resolveConsumerSaleVatFromSnapshot(
    planned({
      vat_rate_percent: undefined,
      quote: { pricing_main: { breakdown: { vat_rate: 0.06 } } },
    }),
  );
  assert.equal(fromQuote.ok, true);
  assert.equal(fromQuote.vat_rate_percent, 6);
  assert.equal(fromQuote.source, "quote_vat_snapshot");
});

test("13. heen/terugrit must not register parent total AND legs", () => {
  const bad = roundtripAvoidsDoubleRevenue({
    registerParentTotal: true,
    registerOutboundLeg: true,
    registerReturnLeg: true,
  });
  assert.equal(bad.ok, false);
  const good = roundtripAvoidsDoubleRevenue({
    registerOutboundLeg: true,
    registerReturnLeg: true,
  });
  assert.equal(good.ok, true);
  assert.equal(good.strategy, "per_leg");
});

test("14. conversion credits consumer before business invoice", () => {
  // 1. consumer invoice → credit then business
  const d = resolveConsumerToBusinessConversionDecision({
    hasConsumerSale: true,
    consumerBillitOrderId: "ord_c",
  });
  assert.equal(d.action, "credit_then_business");
  assert.equal(d.requires_credit_note, true);
  assert.equal(d.allow_business_invoice, false);
  assert.equal(d.peppol_on_business_only, true);

  // 2. identical amounts/VAT on credit
  assert.equal(
    creditNoteTotalsMatchConsumerSale({
      consumerCents: 4250,
      consumerVatRatePercent: 6,
      consumerCurrency: "EUR",
      creditCents: 4250,
      creditVatRatePercent: 6,
      creditCurrency: "EUR",
    }).ok,
    true,
  );
  assert.equal(
    creditNoteTotalsMatchConsumerSale({
      consumerCents: 4250,
      consumerVatRatePercent: 6,
      consumerCurrency: "EUR",
      creditCents: 4250,
      creditVatRatePercent: 21,
      creditCurrency: "EUR",
    }).error,
    "credit_vat_mismatch",
  );

  // 3. retry after credit: resume business only (no second credit)
  const resume = resolveConsumerToBusinessConversionDecision({
    hasConsumerSale: true,
    consumerBillitOrderId: "ord_c",
    hasCreditNoteDocument: true,
    hasCreditNoteBillitOrder: true,
    consumerSaleSuperseded: true,
  });
  assert.equal(resume.action, "resume_business_after_credit");
  assert.equal(resume.requires_credit_note, false);
  assert.equal(resume.allow_business_invoice, true);

  // 4. credit failed → no business invoice
  const blocked = resolveConsumerToBusinessConversionDecision({
    hasConsumerSale: true,
    consumerBillitOrderId: "ord_c",
    creditFailed: true,
  });
  assert.equal(blocked.allow_business_invoice, false);
  assert.equal(blocked.action, "block_until_credit_succeeds");

  // 5. after credit, only business is active revenue
  const active = activeRevenueDocumentsAfterConversion({
    consumerSuperseded: true,
    creditNotePresent: true,
    businessInvoicePresent: true,
  });
  assert.equal(active.ok, true);
  assert.deepEqual(active.active, ["business_invoice"]);

  // 7. Peppol only on business
  assert.equal(d.peppol_on_business_only, true);

  // 11. no consumer → unchanged business flow
  const plain = resolveConsumerToBusinessConversionDecision({
    hasConsumerSale: false,
  });
  assert.equal(plain.action, "create_business");
  assert.equal(plain.requires_credit_note, false);

  assert.equal(
    isActiveRevenueDocument({
      saleKind: CONSUMER_SALE_KIND,
      superseded: true,
    }),
    false,
  );

  // link trail + per-leg idempotency (8/9)
  const k1 = buildConsumerConversionCreditIdempotencyKey({
    tenantId: "T1",
    companyId: "C1",
    bookingId: "bk1",
    legId: "leg_out",
  });
  const k2 = buildConsumerConversionCreditIdempotencyKey({
    tenantId: "T1",
    companyId: "C1",
    bookingId: "bk1",
    legId: "leg_ret",
  });
  assert.notEqual(k1, k2);
  const trail = buildConsumerConversionLinkTrail({
    bookingId: "bk1",
    consumerBillitOrderId: "ord_c",
    creditBillitOrderId: "ord_cn",
    businessBillitOrderId: "ord_b",
    paymentMethod: "pointofsale",
    paymentProvider: "mollie",
    paymentStatus: "paid",
  });
  assert.equal(trail.second_cashflow, false);
  assert.equal(trail.peppol_on, "business_invoice_only");
  assert.equal(trail.payment_method, "pointofsale");
});

test("15. foreign tenant cannot share consumer idempotency identity", () => {
  const a = buildConsumerSaleIdempotencyKey({
    tenantId: "T1",
    companyId: "C1",
    bookingId: "bk1",
  });
  const b = buildConsumerSaleIdempotencyKey({
    tenantId: "T2",
    companyId: "C1",
    bookingId: "bk1",
  });
  assert.notEqual(a, b);
  assert.match(a, /^inv-consumer:T1:C1:bk1:main:consumer_sale:v1$/);
});

test("16. invalid/zero price creates no sale document", () => {
  assert.equal(
    resolveConsumerSaleRegistrationGate({
      completed: true,
      amountCents: 0,
    }).reason,
    "invalid_or_zero_amount",
  );
  assert.equal(resolveConsumerSaleAmount(planned({ price_incl_vat: 0 })).ok, false);
});

test("17. client amount is not part of server amount resolver API", () => {
  // Resolver signature has no clientAmount parameter — server sources only.
  const out = resolveConsumerSaleAmount(planned());
  assert.equal(out.value, "42.50");
  assert.equal(Object.prototype.hasOwnProperty.call(out, "ignored_client"), false);
});

test("18. existing Billit document link preserved on retry (reuse)", () => {
  const gate = resolveConsumerSaleRegistrationGate({
    completed: true,
    amountCents: 1860,
    existingConsumerDocumentId: "doc_keep",
    existingConsumerBillitOrderId: "ord_keep",
  });
  assert.equal(gate.action, "reuse");
  assert.equal(gate.document_id, "doc_keep");
  assert.equal(gate.billit_order_id, "ord_keep");
});

test("presentation never uses Factuur label for consumer sale", () => {
  const p = consumerSalePresentation();
  assert.equal(p.forbid_invoice_label, true);
  assert.equal(p.document_label_nl, "Particuliere verkoop");
  assert.equal(p.billit_order_type, CONSUMER_SALE_BILLIT_ORDER_TYPE);
  const meta = buildConsumerSaleDocumentMetadata({
    bookingId: "bk1",
    amount: { currency: "EUR", value: "10.00" },
  });
  assert.equal(meta.fluxidi_sale_kind, CONSUMER_SALE_KIND);
  assert.equal(meta.peppol_applicable, false);
});

test("eligibility requires completed private ride", () => {
  assert.equal(isConsumerSaleEligibleRecord(planned()), true);
  assert.equal(
    isConsumerSaleEligibleRecord(planned({ status: "PENDING" })),
    false,
  );
  assert.equal(isConsumerSaleEligibleRecord(street()), true);
});

test("P0 exactly-once: canonical sale + intent keys are stable and tenant-isolated", () => {
  const sale = buildConsumerSaleIdempotencyKey({
    tenantId: "T1",
    companyId: "C1",
    bookingId: "street_1",
    legId: null,
  });
  assert.equal(sale, "inv-consumer:T1:C1:street_1:main:consumer_sale:v1");
  const intent = buildConsumerBillitSaleIntentKey({
    tenantId: "T1",
    companyId: "C1",
    bookingId: "street_1",
  });
  assert.equal(
    intent,
    "tenant:T1:company:C1:consumer_billit_sale_intent:street_1:main:v1",
  );
  const billitKey = buildBillitConsumerSaleOrderCreateIdempotencyKey(sale);
  assert.equal(
    billitKey,
    `fluxidi-billit-consumer-order:${sale}:sandbox:v1`,
  );
  assert.notEqual(
    buildConsumerBillitSaleIntentKey({
      tenantId: "T2",
      companyId: "C1",
      bookingId: "street_1",
    }),
    intent,
  );
  // Roundtrip legs remain distinct.
  assert.notEqual(
    buildConsumerSaleIdempotencyKey({
      tenantId: "T1",
      companyId: "C1",
      bookingId: "bk_rt",
      legId: "leg_out",
    }),
    buildConsumerSaleIdempotencyKey({
      tenantId: "T1",
      companyId: "C1",
      bookingId: "bk_rt",
      legId: "leg_ret",
    }),
  );
});

test("P0 exactly-once: owner/waiter decision never double-mints", () => {
  assert.equal(
    resolveConsumerSaleIssueOwnerDecision({ isOwner: true }).action,
    "issue",
  );
  assert.equal(
    resolveConsumerSaleIssueOwnerDecision({ isOwner: false }).action,
    "wait",
  );
  assert.equal(
    resolveConsumerSaleIssueOwnerDecision({
      isOwner: true,
      intentDocumentId: "doc-1",
    }).may_issue,
    false,
  );
  assert.equal(
    resolveConsumerSaleIssueOwnerDecision({
      isOwner: false,
      existingDocumentId: "doc-1",
      existingBillitOrderId: "ord-1",
    }).action,
    "reuse",
  );
});

test("P0 exactly-once: ambiguous timeout reconciles before CREATE", () => {
  assert.equal(
    reconcileConsumerBillitCreateDecision({
      intentDocumentId: "doc-1",
      intentBillitOrderId: "ord-1",
    }).may_create,
    false,
  );
  const ambiguous = reconcileConsumerBillitCreateDecision({
    intentDocumentId: "doc-1",
    lastError: "ambiguous_remote_timeout",
  });
  assert.equal(ambiguous.action, "retry_same_sale_key");
  assert.equal(ambiguous.may_create, true);
  assert.equal(ambiguous.creates_new_sale_document, false);
  assert.equal(
    reconcileConsumerBillitCreateDecision({
      intentDocumentId: "",
    }).action,
    "need_document",
  );
  assert.equal(CONSUMER_SALE_INTENT_STATES.BILLIT_CREATING, "billit_creating");
});
