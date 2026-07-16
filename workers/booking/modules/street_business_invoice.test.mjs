/* Deterministic unit tests for the street-ride business-invoice pure helpers
 * (Phase STREET-RIDE-BUSINESS-INVOICE-A1). Runs with the built-in Node test
 * runner and needs no dependencies:
 *
 *   node --test workers/booking/modules/street_business_invoice.test.mjs
 *
 * These cover ONLY the new pure decision logic. The Document Core invoice
 * engine, Billit and Peppol helpers are not exercised here (they require the
 * Worker runtime); their reuse is verified by the static safety audit. */

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  STREET_BUSINESS_INVOICE_INTENT,
  STREET_INVOICE_REQUEST_SOURCE,
  REJECTED_AUTHORITATIVE_REQUEST_FIELDS,
  isStreetRideBooking,
  evaluateStreetInvoiceEligibility,
  streetRidePaymentStatus,
  shouldRejectForBillingReadiness,
  buildStreetBillingCustomerSnapshot,
  billingIdentityConflict,
  resolveBusinessInvoiceRetryDecision,
  streetRideInvoiceIdempotencyKey,
  buildBusinessInvoiceResponse,
} from "./street_business_invoice.js";

import { bookingMatchesRequiredTenantCompanyScope } from "./auth_scope.js";

const TENANT = "tenant_a";
const COMPANY = "company_a";

function completedStreetBooking(overrides = {}) {
  return {
    booking_id: "street_1720000000000_ab12cd34",
    tenant_id: TENANT,
    company_id: COMPANY,
    source: "street_ride",
    booking_source: "street_ride",
    ride_type: "direct",
    status: "COMPLETED",
    payment_status: "unpaid",
    currency: "EUR",
    price_incl_vat: 24.2,
    price_ex_vat: 20,
    price_vat: 4.2,
    vat_rate_percent: 21,
    customer_name: "Straatrit",
    booking: { from: "A", to: "B" },
    ...overrides,
  };
}

const READY_NORMALIZED = {
  display_name: "ACME Taxi Client",
  contact_email: "billing@acme.example",
  contact_phone: "+3212345678",
  customer_type: "business",
  legal_name: "ACME NV",
  vat_number: "BE0123456789",
  company_registration_number: "0123456789",
  buyer_reference: "PO-42",
  billing_address: {
    street: "Main 1",
    postal_code: "1000",
    city: "Brussels",
    country: "BE",
  },
  peppol: { endpoint_id: "0123456789", scheme: "0208" },
};

// 1. street booking eligibility succeeds
test("street COMPLETED booking is eligible", () => {
  const rec = completedStreetBooking();
  assert.equal(isStreetRideBooking({ bookingId: rec.booking_id, record: rec }), true);
  const res = evaluateStreetInvoiceEligibility({ bookingId: rec.booking_id, record: rec });
  assert.deepEqual(res, { ok: true, reason: null });
});

// 2. planned booking is rejected by this street-specific route
test("planned booking is rejected as not a street booking", () => {
  const rec = {
    booking_id: "b_9f8e7d6c",
    tenant_id: TENANT,
    company_id: COMPANY,
    source: "flutter_app",
    booking_source: "flutter_app",
    ride_type: "planned",
    status: "COMPLETED",
  };
  assert.equal(isStreetRideBooking({ bookingId: rec.booking_id, record: rec }), false);
  const res = evaluateStreetInvoiceEligibility({ bookingId: rec.booking_id, record: rec });
  assert.equal(res.ok, false);
  assert.equal(res.reason, "not_a_street_booking");
});

// 3. cross-company scope is rejected (uses the real scope matcher)
test("cross-company scope is rejected, same scope accepted", () => {
  const rec = completedStreetBooking();
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(rec, {
      tenant_id: TENANT,
      company_id: "other_company",
    }),
    false,
  );
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(rec, {
      tenant_id: TENANT,
      company_id: COMPANY,
    }),
    true,
  );
});

// 4. incomplete billing identity returns validation failure
test("incomplete billing identity is rejected; ready identity passes", () => {
  const notReady = shouldRejectForBillingReadiness({
    ready: false,
    missing_fields: ["customer_legal_name_missing", "customer_billing_address_missing"],
  });
  assert.equal(notReady.reject, true);
  assert.deepEqual(notReady.missing_fields, [
    "customer_legal_name_missing",
    "customer_billing_address_missing",
  ]);

  const ready = shouldRejectForBillingReadiness({ ready: true, missing_fields: [] });
  assert.equal(ready.reject, false);
});

// 5. billing identity remains separate from passenger identity
test("snapshot carries buyer identity only, never passenger/ride fields", () => {
  const snap = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "company_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  assert.equal(snap.legal_name, "ACME NV");
  assert.equal(snap.vat_number, "BE0123456789");
  assert.equal(snap.billing_address.city, "Brussels");
  assert.equal(snap.snapshot_source, STREET_INVOICE_REQUEST_SOURCE);
  // No passenger / ride leakage.
  assert.equal("customer_name" in snap, false);
  assert.equal("from" in snap, false);
  assert.equal("to" in snap, false);
  assert.equal("pickup_iso" in snap, false);
});

// 6. deterministic invoice idempotency key
test("idempotency key is deterministic and uses the booking-invoice convention", () => {
  const key = streetRideInvoiceIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId: "street_1_abc",
  });
  assert.equal(key, "inv-auto:tenant_a:company_a:street_1_abc:main:v1");
  // Stable across calls.
  assert.equal(
    key,
    streetRideInvoiceIdempotencyKey({
      tenantId: TENANT,
      companyId: COMPANY,
      bookingId: "street_1_abc",
    }),
  );
});

// 7. identical retry resolves to reused result
test("identical retry with an existing invoice resolves to reuse", () => {
  const existingSnapshot = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "company_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  const requestedSnapshot = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "company_business_invoice",
    // different timestamp/actor must NOT matter for identity
    nowIso: "2026-07-16T09:30:00.000Z",
  });
  const decision = resolveBusinessInvoiceRetryDecision({
    existingInvoice: { document_id: "doc_1", document_number: "INV-2026-000001" },
    existingSnapshot,
    requestedSnapshot,
  });
  assert.equal(decision.action, "reuse");
});

// 8. conflicting retry does not overwrite issued snapshot
test("conflicting identity retry resolves to conflict (never overwrite)", () => {
  const existingSnapshot = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "company_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  const conflicting = buildStreetBillingCustomerSnapshot({
    normalized: { ...READY_NORMALIZED, legal_name: "DIFFERENT BV", vat_number: "BE0999999999" },
    actorRole: "company_business_invoice",
    nowIso: "2026-07-16T09:30:00.000Z",
  });
  assert.equal(billingIdentityConflict(existingSnapshot, conflicting), true);
  const decision = resolveBusinessInvoiceRetryDecision({
    existingInvoice: { document_id: "doc_1", document_number: "INV-2026-000001" },
    existingSnapshot,
    requestedSnapshot: conflicting,
  });
  assert.equal(decision.action, "conflict");
});

test("first request with no existing invoice resolves to issue", () => {
  const requestedSnapshot = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "company_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  const decision = resolveBusinessInvoiceRetryDecision({
    existingInvoice: null,
    existingSnapshot: null,
    requestedSnapshot,
  });
  assert.equal(decision.action, "issue");
});

// 9. paid-now mode is derived from stored booking, not request body
test("paid-now is derived from stored booking payment_status", () => {
  assert.equal(streetRidePaymentStatus(completedStreetBooking({ payment_status: "paid" })), "paid");
  // A record that is not paid stays unpaid regardless of any request intent.
  assert.equal(streetRidePaymentStatus(completedStreetBooking({ payment_status: "open" })), "unpaid");
  // The function only accepts a record; it structurally cannot read a body.
  assert.equal(streetRidePaymentStatus.length, 1);
});

// 10. unpaid mode remains unpaid
test("unpaid booking maps to unpaid + pending reconciliation hint", () => {
  const rec = completedStreetBooking({ payment_status: "unpaid" });
  const status = streetRidePaymentStatus(rec);
  assert.equal(status, "unpaid");
  const resp = buildBusinessInvoiceResponse({
    bookingId: rec.booking_id,
    documentId: "doc_1",
    invoiceReference: "INV-2026-000001",
    paymentStatus: status,
    paymentReconciliation: status === "paid" ? null : "pending_external_payment",
  });
  assert.equal(resp.payment_status, "unpaid");
  assert.equal(resp.payment_reconciliation, "pending_external_payment");
  assert.equal(resp.peppol_sent, false);
});

// 11. invoice issue is revenue-neutral (response carries no monetary totals)
test("response is revenue-neutral: no amount/total/revenue fields", () => {
  const resp = buildBusinessInvoiceResponse({
    bookingId: "street_1_abc",
    documentId: "doc_1",
    invoiceReference: "INV-2026-000001",
    reused: false,
    paymentStatus: "paid",
    billitOrderId: "ord_1",
    billitOrderReused: false,
    billitPaymentSyncStatus: "synced",
  });
  for (const forbidden of [
    "total",
    "total_incl_vat",
    "subtotal_ex_vat",
    "vat_amount",
    "amount",
    "revenue",
    "price",
    "kpi",
  ]) {
    assert.equal(forbidden in resp, false, `response must not contain ${forbidden}`);
  }
});

// 12. response does not expose PII
test("response never leaks buyer PII from the snapshot", () => {
  const snap = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "company_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  const resp = buildBusinessInvoiceResponse({
    bookingId: "street_1_abc",
    documentId: "doc_1",
    invoiceReference: "INV-2026-000001",
    paymentStatus: "paid",
    // intentionally feed forbidden extras: they must be dropped by the builder
    warnings: ["ok"],
  });
  const serialized = JSON.stringify(resp);
  for (const pii of [
    snap.legal_name,
    snap.vat_number,
    snap.contact_email,
    snap.contact_phone,
    snap.billing_address.street,
    snap.company_registration_number,
  ]) {
    assert.equal(serialized.includes(pii), false, `response leaked ${pii}`);
  }
  // Only the safe bounded key set is present.
  assert.deepEqual(
    Object.keys(resp).sort(),
    [
      "billit_environment",
      "billit_order_id",
      "billit_order_reused",
      "billit_payment_sync_status",
      "booking_id",
      "document_id",
      "invoice_reference",
      "ok",
      "payment_status",
      "peppol_sent",
      "reused",
      "warnings",
    ].sort(),
  );
});

// 13. cancelled / refunded / credited booking is rejected
test("cancelled / refunded / credited street bookings are rejected", () => {
  for (const overrides of [
    { status: "CANCELLED" },
    { status: "COMPLETED", payment_status: "refunded" },
    { status: "COMPLETED", credited: true },
    { status: "COMPLETED", refund_status: "refunded" },
    { status: "COMPLETED", credit_note_reference: "FCN-2026-000001" },
  ]) {
    const rec = completedStreetBooking(overrides);
    const res = evaluateStreetInvoiceEligibility({ bookingId: rec.booking_id, record: rec });
    assert.equal(res.ok, false, `expected rejection for ${JSON.stringify(overrides)}`);
    assert.ok(
      res.reason === "booking_not_invoiceable_state" || res.reason === "booking_not_completed",
      `unexpected reason ${res.reason} for ${JSON.stringify(overrides)}`,
    );
  }
});

// Contract guard: the intent constant and rejected-field list are stable.
test("intent constant and rejected authoritative fields are declared", () => {
  assert.equal(STREET_BUSINESS_INVOICE_INTENT, "business_invoice");
  for (const f of ["paid", "payment_status", "total", "invoice_number", "billit_order_id"]) {
    assert.ok(REJECTED_AUTHORITATIVE_REQUEST_FIELDS.includes(f), `missing rejected field ${f}`);
  }
});
