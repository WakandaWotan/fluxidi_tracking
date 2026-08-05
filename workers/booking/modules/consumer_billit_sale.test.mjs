// CONSUMER-BILLIT-SERVER-CONTRACT-1 — pure decision tests
// Run: node --test workers/booking/modules/consumer_billit_sale.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  CONSUMER_SALE_BILLIT_ORDER_TYPE,
  CONSUMER_SALE_KIND,
  buildConsumerSaleDocumentMetadata,
  buildConsumerSaleIdempotencyKey,
  consumerSalePeppolPolicy,
  consumerSalePresentation,
  hasBusinessInvoiceIntent,
  isActiveRevenueDocument,
  isConsumerSaleEligibleRecord,
  mapConsumerSalePaymentMethodLabel,
  resolveConsumerSaleAmount,
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

test("12. business invoice intent is not treated as consumer sale", () => {
  assert.equal(
    hasBusinessInvoiceIntent(planned({ invoice_intent: "business_invoice" })),
    true,
  );
  assert.equal(
    isConsumerSaleEligibleRecord(
      planned({ invoice_intent: "business_invoice" }),
    ),
    false,
  );
  assert.equal(
    resolveConsumerSaleRegistrationGate({
      completed: true,
      amountCents: 1000,
      businessInvoiceIntent: true,
    }).reason,
    "business_invoice_active",
  );
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

test("14. conversion to business invoice never double-counts active revenue", () => {
  const d = resolveConsumerToBusinessConversionDecision({
    hasConsumerSale: true,
    consumerBillitOrderId: "ord_c",
  });
  assert.equal(d.action, "supersede_consumer_then_create_business");
  assert.equal(d.double_revenue_risk, false);
  assert.equal(d.requires_consumer_supersede, true);
  assert.ok(String(d.accounting_note || "").includes("credit"));

  assert.equal(
    isActiveRevenueDocument({
      saleKind: CONSUMER_SALE_KIND,
      superseded: true,
    }),
    false,
  );
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
