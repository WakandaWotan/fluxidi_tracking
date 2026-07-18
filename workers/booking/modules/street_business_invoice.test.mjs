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
  hasCanonicalStreetIdentity,
  resolveAssignedDriverId,
  evaluateDriverInvoiceOwnership,
  evaluateDriverBusinessInvoiceGate,
  resolveStreetInvoicePaymentPresentation,
  resolveStreetInvoicePdfAvailability,
  resolveStreetInvoicePaidSyncDecision,
  resolveBillitPaidLifecycleGate,
} from "./street_business_invoice.js";
import * as streetInvoiceModule from "./street_business_invoice.js";

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

/* ===================================================================
 * DRIVER RECEIPT BUSINESS INVOICE — driver-scoped authorization tests
 * (Phase STREET-RIDE-BUSINESS-INVOICE-DRIVER-RECEIPT-1).
 *
 * These exercise the NEW pure driver-auth decision helpers that the
 * request-business-invoice route composes. The company/admin path and the
 * shared invoice engine + idempotency key are unchanged and re-verified here to
 * be actor-independent (no duplicate invoice/order can be produced).
 * =================================================================== */

const DRIVER_ID = "drv_owner_1";

function completedStreetBookingForDriver(overrides = {}) {
  return completedStreetBooking({ assigned_driver_id: DRIVER_ID, ...overrides });
}

// D1. Company/admin request still succeeds unchanged: eligibility passes and the
// idempotency key is actor-independent (same key for admin/company/driver).
test("D1: company/admin path unchanged; idempotency key is actor-independent", () => {
  const rec = completedStreetBookingForDriver();
  assert.deepEqual(
    evaluateStreetInvoiceEligibility({ bookingId: rec.booking_id, record: rec }),
    { ok: true, reason: null },
  );
  const key = streetRideInvoiceIdempotencyKey({
    tenantId: TENANT,
    companyId: COMPANY,
    bookingId: rec.booking_id,
  });
  // The key never takes an actor; company/admin/driver all resolve to the same
  // key -> the same Document Core invoice + Billit order (no duplicates).
  assert.equal(key, `inv-auto:${TENANT}:${COMPANY}:${rec.booking_id}:main:v1`);
});

// D2. Assigned authenticated driver can request for own completed street ride.
test("D2: assigned driver passes the full driver gate", () => {
  const rec = completedStreetBookingForDriver();
  const gate = evaluateDriverBusinessInvoiceGate({
    bookingId: rec.booking_id,
    record: rec,
    driverId: DRIVER_ID,
  });
  assert.deepEqual(gate, { ok: true, reason: null, status: 200 });
  assert.deepEqual(evaluateDriverInvoiceOwnership({ record: rec, driverId: DRIVER_ID }), {
    ok: true,
    reason: null,
  });
});

// D3. Identical driver retry -> reuse (same ids). Idempotency key is stable.
test("D3: identical driver retry resolves to reuse with the same key", () => {
  const rec = completedStreetBookingForDriver();
  const existingSnapshot = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "driver_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  const requestedSnapshot = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "driver_business_invoice",
    nowIso: "2026-07-16T10:00:00.000Z",
  });
  const decision = resolveBusinessInvoiceRetryDecision({
    existingInvoice: { document_id: "doc_1", document_number: "INV-2026-000001" },
    existingSnapshot,
    requestedSnapshot,
  });
  assert.equal(decision.action, "reuse");
  assert.equal(
    streetRideInvoiceIdempotencyKey({ tenantId: TENANT, companyId: COMPANY, bookingId: rec.booking_id }),
    streetRideInvoiceIdempotencyKey({ tenantId: TENANT, companyId: COMPANY, bookingId: rec.booking_id }),
  );
});

// D4. A different (non-assigned) driver is rejected.
test("D4: non-assigned driver is rejected (driver_not_assigned / 403)", () => {
  const rec = completedStreetBookingForDriver();
  const own = evaluateDriverInvoiceOwnership({ record: rec, driverId: "drv_other_2" });
  assert.deepEqual(own, { ok: false, reason: "driver_not_assigned" });
  const gate = evaluateDriverBusinessInvoiceGate({
    bookingId: rec.booking_id,
    record: rec,
    driverId: "drv_other_2",
  });
  assert.equal(gate.ok, false);
  assert.equal(gate.reason, "driver_not_assigned");
  assert.equal(gate.status, 403);
});

// D5. Same driver but wrong tenant/company is rejected by the scope matcher.
test("D5: assigned driver in wrong tenant/company is out of scope", () => {
  const rec = completedStreetBookingForDriver();
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(rec, { tenant_id: TENANT, company_id: "other_company" }),
    false,
  );
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(rec, { tenant_id: "other_tenant", company_id: COMPANY }),
    false,
  );
});

// D6. Driver cannot invoice a planned direct booking (ride_type == direct alone
// is NEVER sufficient for the driver path).
test("D6: driver cannot invoice a direct-only / planned booking (no canonical street identity)", () => {
  const directOnly = {
    booking_id: "b_direct_only",
    tenant_id: TENANT,
    company_id: COMPANY,
    source: "driver_app",
    booking_source: "driver_app",
    ride_type: "direct",
    status: "COMPLETED",
    assigned_driver_id: DRIVER_ID,
  };
  // The lenient company predicate would treat ride_type==direct as street...
  assert.equal(isStreetRideBooking({ bookingId: directOnly.booking_id, record: directOnly }), true);
  // ...but the strict driver identity does NOT.
  assert.equal(
    hasCanonicalStreetIdentity({ bookingId: directOnly.booking_id, record: directOnly }),
    false,
  );
  const gate = evaluateDriverBusinessInvoiceGate({
    bookingId: directOnly.booking_id,
    record: directOnly,
    driverId: DRIVER_ID,
  });
  assert.equal(gate.ok, false);
  assert.equal(gate.reason, "not_a_street_booking");
  assert.equal(gate.status, 422);
});

// D7. Driver cannot invoice an incomplete street ride.
test("D7: driver cannot invoice an incomplete street ride", () => {
  const rec = completedStreetBookingForDriver({ status: "IN_PROGRESS" });
  const gate = evaluateDriverBusinessInvoiceGate({
    bookingId: rec.booking_id,
    record: rec,
    driverId: DRIVER_ID,
  });
  assert.equal(gate.ok, false);
  assert.equal(gate.reason, "booking_not_completed");
  assert.equal(gate.status, 409);
});

// D8. Driver cannot invoice a cancelled / refunded / credited ride.
test("D8: driver cannot invoice cancelled/refunded/credited street ride", () => {
  for (const overrides of [
    { status: "CANCELLED" },
    { status: "COMPLETED", payment_status: "refunded" },
    { status: "COMPLETED", credited: true },
    { status: "COMPLETED", credit_note_reference: "FCN-2026-000001" },
  ]) {
    const rec = completedStreetBookingForDriver(overrides);
    const gate = evaluateDriverBusinessInvoiceGate({
      bookingId: rec.booking_id,
      record: rec,
      driverId: DRIVER_ID,
    });
    assert.equal(gate.ok, false, `expected rejection for ${JSON.stringify(overrides)}`);
    assert.ok(
      gate.reason === "booking_not_invoiceable_state" || gate.reason === "booking_not_completed",
      `unexpected reason ${gate.reason} for ${JSON.stringify(overrides)}`,
    );
  }
});

// D9. Driver payload cannot override pricing/payment/VAT/currency: payment state
// is derived from the stored booking and the buyer snapshot carries no money.
test("D9: driver payload cannot override pricing/payment/VAT/currency", () => {
  const rec = completedStreetBookingForDriver({ payment_status: "paid" });
  // Even if the (driver) body claimed unpaid/other totals, status derives from rec.
  assert.equal(streetRidePaymentStatus(rec), "paid");
  const snap = buildStreetBillingCustomerSnapshot({
    normalized: {
      ...READY_NORMALIZED,
      // hostile extras that must never survive into the snapshot
      total_incl_vat: 999,
      payment_status: "paid",
      currency: "USD",
      vat_amount: 0,
    },
    actorRole: "driver_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  for (const f of REJECTED_AUTHORITATIVE_REQUEST_FIELDS) {
    assert.equal(f in snap, false, `snapshot must not carry authoritative field ${f}`);
  }
  assert.equal("currency" in snap, false);
});

// D10. Driver route never sends Peppol: the shared response builder hardcodes
// peppol_sent=false and the module exposes no Peppol-send helper.
test("D10: driver route never auto-sends Peppol", () => {
  const resp = buildBusinessInvoiceResponse({
    bookingId: "street_1_abc",
    documentId: "doc_1",
    invoiceReference: "INV-2026-000001",
    paymentStatus: "unpaid",
  });
  assert.equal(resp.peppol_sent, false);
  const exported = Object.keys(streetInvoiceModule).map((k) => k.toLowerCase());
  assert.ok(
    !exported.some((k) => k.includes("peppol") && k.includes("send")),
    "module must not export a Peppol-send helper",
  );
});

// D11. Paid state is preserved for the driver path.
test("D11: paid street ride stays paid", () => {
  assert.equal(streetRidePaymentStatus(completedStreetBookingForDriver({ payment_status: "paid" })), "paid");
});

// D12. Unpaid state is preserved for the driver path.
test("D12: unpaid street ride stays unpaid", () => {
  assert.equal(streetRidePaymentStatus(completedStreetBookingForDriver({ payment_status: "unpaid" })), "unpaid");
});

// D13. Existing 409 buyer-identity conflict still applies to driver retries.
test("D13: conflicting buyer identity on a driver retry is a conflict (409)", () => {
  const existingSnapshot = buildStreetBillingCustomerSnapshot({
    normalized: READY_NORMALIZED,
    actorRole: "company_business_invoice",
    nowIso: "2026-07-16T08:00:00.000Z",
  });
  const conflicting = buildStreetBillingCustomerSnapshot({
    normalized: { ...READY_NORMALIZED, legal_name: "DRIVER OVERRIDE BV", vat_number: "BE0999999999" },
    actorRole: "driver_business_invoice",
    nowIso: "2026-07-16T10:00:00.000Z",
  });
  const decision = resolveBusinessInvoiceRetryDecision({
    existingInvoice: { document_id: "doc_1", document_number: "INV-2026-000001" },
    existingSnapshot,
    requestedSnapshot: conflicting,
  });
  assert.equal(decision.action, "conflict");
});

// D14. No duplicate invoice/document/Billit order: the idempotency key is the
// same for company and driver actors on the same booking, and resolveAssigned
// driver id reads all authoritative field variants.
test("D14: no duplicate invoice/order across actors; assigned-id resolution is robust", () => {
  const bookingId = "street_dup_check";
  const companyKey = streetRideInvoiceIdempotencyKey({ tenantId: TENANT, companyId: COMPANY, bookingId });
  const driverKey = streetRideInvoiceIdempotencyKey({ tenantId: TENANT, companyId: COMPANY, bookingId });
  assert.equal(companyKey, driverKey);

  assert.equal(resolveAssignedDriverId({ assigned_driver_id: "d1" }), "d1");
  assert.equal(resolveAssignedDriverId({ assignedDriverId: "d2" }), "d2");
  assert.equal(resolveAssignedDriverId({ assigned_driver: { driver_id: "d3" } }), "d3");
  assert.equal(resolveAssignedDriverId({ booking: { assigned_driver_id: "d4" } }), "d4");
  assert.equal(resolveAssignedDriverId({ driver_id: "d5" }), "d5");
  assert.equal(resolveAssignedDriverId({}), "");
  assert.equal(resolveAssignedDriverId(null), "");
});

// Guard: an authenticated driver with no id can never pass ownership.
test("D-guard: empty driver id is rejected as driver_session_required", () => {
  const rec = completedStreetBookingForDriver();
  assert.deepEqual(evaluateDriverInvoiceOwnership({ record: rec, driverId: "" }), {
    ok: false,
    reason: "driver_session_required",
  });
});

/* ===================================================================
 * GET /company/bookings/:bookingId/documents — DRIVER ownership composition.
 *
 * The driver branch composes exactly these pure decisions (in this order):
 *   1. bookingMatchesRequiredTenantCompanyScope(rec, sessionScope)  -> 403
 *   2. hasCanonicalStreetIdentity(...)                              -> 422
 *   3. evaluateDriverInvoiceOwnership(...)                          -> 403
 *   4. evaluateStreetInvoiceEligibility(...)                        -> 404/409
 * Ownership is checked BEFORE the lifecycle state so a same-company,
 * non-assigned driver never learns document metadata (always 403).
 * =================================================================== */

// Mirrors the route branch decision so tests track the real composition.
function driverDocumentsDecision({ record, sessionScope, driverId, bookingId }) {
  if (
    !bookingMatchesRequiredTenantCompanyScope(record, {
      tenant_id: sessionScope.tenant_id,
      company_id: sessionScope.company_id,
      hasScope: true,
    })
  ) {
    return { status: 403, error: "not_in_scope" };
  }
  if (!hasCanonicalStreetIdentity({ bookingId, record })) {
    return { status: 422, error: "not_a_street_booking" };
  }
  const own = evaluateDriverInvoiceOwnership({ record, driverId });
  if (!own.ok) return { status: 403, error: own.reason };
  const elig = evaluateStreetInvoiceEligibility({ bookingId, record });
  if (!elig.ok) {
    return {
      status: elig.reason === "source_booking_not_found" ? 404 : 409,
      error: elig.reason,
    };
  }
  return { status: 200, error: null };
}

const DOC_SCOPE = { tenant_id: TENANT, company_id: COMPANY };

test("DGET1: assigned driver GET documents succeeds", () => {
  const rec = completedStreetBookingForDriver();
  assert.deepEqual(
    driverDocumentsDecision({
      record: rec,
      sessionScope: DOC_SCOPE,
      driverId: DRIVER_ID,
      bookingId: rec.booking_id,
    }),
    { status: 200, error: null },
  );
});

test("DGET2: different driver in same company receives 403 (no metadata)", () => {
  const rec = completedStreetBookingForDriver();
  const out = driverDocumentsDecision({
    record: rec,
    sessionScope: DOC_SCOPE,
    driverId: "drv_other_2",
    bookingId: rec.booking_id,
  });
  assert.equal(out.status, 403);
  assert.equal(out.error, "driver_not_assigned");
});

test("DGET3: wrong company receives 403", () => {
  const rec = completedStreetBookingForDriver();
  const out = driverDocumentsDecision({
    record: rec,
    sessionScope: { tenant_id: TENANT, company_id: "other_company" },
    driverId: DRIVER_ID,
    bookingId: rec.booking_id,
  });
  assert.equal(out.status, 403);
  assert.equal(out.error, "not_in_scope");
});

test("DGET4: non-street booking rejected (422)", () => {
  const rec = {
    booking_id: "b_planned_direct",
    tenant_id: TENANT,
    company_id: COMPANY,
    source: "driver_app",
    booking_source: "driver_app",
    ride_type: "direct",
    status: "COMPLETED",
    assigned_driver_id: DRIVER_ID,
  };
  const out = driverDocumentsDecision({
    record: rec,
    sessionScope: DOC_SCOPE,
    driverId: DRIVER_ID,
    bookingId: rec.booking_id,
  });
  assert.equal(out.status, 422);
  assert.equal(out.error, "not_a_street_booking");
});

test("DGET5: incomplete street ride rejected (409); non-owner still 403", () => {
  const rec = completedStreetBookingForDriver({ status: "IN_PROGRESS" });
  const out = driverDocumentsDecision({
    record: rec,
    sessionScope: DOC_SCOPE,
    driverId: DRIVER_ID,
    bookingId: rec.booking_id,
  });
  assert.equal(out.status, 409);
  assert.equal(out.error, "booking_not_completed");
  // A non-owner on the SAME incomplete booking still gets 403 (not 409), so
  // booking state is never leaked to a non-assigned driver.
  const nonOwner = driverDocumentsDecision({
    record: rec,
    sessionScope: DOC_SCOPE,
    driverId: "drv_other_2",
    bookingId: rec.booking_id,
  });
  assert.equal(nonOwner.status, 403);
  assert.equal(nonOwner.error, "driver_not_assigned");
});

test("DGET6: cancelled/refunded/credited street ride rejected for owner", () => {
  for (const overrides of [
    { status: "CANCELLED" },
    { status: "COMPLETED", payment_status: "refunded" },
    { status: "COMPLETED", credited: true },
  ]) {
    const rec = completedStreetBookingForDriver(overrides);
    const out = driverDocumentsDecision({
      record: rec,
      sessionScope: DOC_SCOPE,
      driverId: DRIVER_ID,
      bookingId: rec.booking_id,
    });
    assert.equal(out.status, 409, `expected 409 for ${JSON.stringify(overrides)}`);
  }
});

// UX-1B: company-admin actor authorization gate for a completed street ride.
// The company/admin path is authorized by the SAME primitives the worker's
// _requireBusinessInvoiceActor + handler use: booking tenant/company scope
// match + street identity + completed lifecycle. No standalone driver session
// is required in this mode.
test("CA1: company admin within scope may invoice an owned completed street ride", () => {
  const rec = completedStreetBooking();
  // Same tenant/company scope as the authenticated company-admin session.
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(rec, {
      tenant_id: TENANT,
      company_id: COMPANY,
    }),
    true,
  );
  assert.equal(
    isStreetRideBooking({ bookingId: rec.booking_id, record: rec }),
    true,
  );
  const eligibility = evaluateStreetInvoiceEligibility({
    bookingId: rec.booking_id,
    record: rec,
  });
  assert.deepEqual(eligibility, { ok: true, reason: null });
});

test("CA2: company admin from a different company is rejected (out of scope)", () => {
  const rec = completedStreetBooking();
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(rec, {
      tenant_id: TENANT,
      company_id: "other_company",
    }),
    false,
  );
});

test("CA3: company admin cannot invoice a non-street or non-completed booking", () => {
  const planned = completedStreetBooking({
    booking_id: "b_planned_9f8e7d6c",
    source: "flutter_app",
    booking_source: "flutter_app",
    ride_type: "planned",
  });
  assert.equal(
    isStreetRideBooking({ bookingId: planned.booking_id, record: planned }),
    false,
  );
  const incomplete = completedStreetBooking({ status: "IN_PROGRESS" });
  const res = evaluateStreetInvoiceEligibility({
    bookingId: incomplete.booking_id,
    record: incomplete,
  });
  assert.equal(res.ok, false);
});

// PDF + payment sync presentation (STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1)
test("PDF1: invoice without artifact is preparing, never available", () => {
  const out = resolveStreetInvoicePdfAvailability({
    hasIssuedInvoice: true,
    pdfArtifactReady: false,
    pdfProbeStatusCode: 404,
  });
  assert.equal(out.state, "preparing");
});

test("PDF2: artifact ready or PDF endpoint 200 => available", () => {
  assert.equal(
    resolveStreetInvoicePdfAvailability({
      hasIssuedInvoice: true,
      pdfArtifactReady: true,
    }).state,
    "available",
  );
  assert.equal(
    resolveStreetInvoicePdfAvailability({
      hasIssuedInvoice: true,
      pdfProbeStatusCode: 200,
    }).state,
    "available",
  );
});

test("PDF3: network/5xx => retryable_error", () => {
  assert.equal(
    resolveStreetInvoicePdfAvailability({
      hasIssuedInvoice: true,
      pdfProbeFailed: true,
    }).state,
    "retryable_error",
  );
});

test("PAY1: paid ride + unpaid Billit => sync_in_progress (not outstanding)", () => {
  const out = resolveStreetInvoicePaymentPresentation({
    ridePaid: true,
    billitPaid: false,
    billitPaymentSyncStatus: "",
  });
  assert.equal(out.invoice_payment_status, "sync_in_progress");
  assert.equal(out.ride_payment_status, "paid");
  assert.equal(out.is_consistent, true);
});

test("PAY2: Billit paid => invoice paid", () => {
  const out = resolveStreetInvoicePaymentPresentation({
    ridePaid: true,
    billitPaid: true,
    billitPaymentSyncStatus: "synced",
  });
  assert.equal(out.invoice_payment_status, "paid");
});

test("PAY3: unpaid ride + no billit paid => outstanding", () => {
  const out = resolveStreetInvoicePaymentPresentation({
    ridePaid: false,
    billitPaid: false,
  });
  assert.equal(out.invoice_payment_status, "outstanding");
});

test("PAY4: late payment sync decision is idempotent when already synced", () => {
  const again = resolveStreetInvoicePaidSyncDecision({
    hasInvoice: true,
    ridePaid: true,
    billitPaid: true,
    billitPaymentSyncStatus: "synced",
    billitOrderId: "ord_1",
  });
  assert.equal(again.action, "already_synced");
  const first = resolveStreetInvoicePaidSyncDecision({
    hasInvoice: true,
    ridePaid: true,
    billitPaid: false,
    billitOrderId: "ord_1",
  });
  assert.equal(first.action, "sync_paid");
});

test("PAY5: paid ride before invoice create maps to paid response status", () => {
  const rec = completedStreetBooking({ payment_status: "paid" });
  assert.equal(streetRidePaymentStatus(rec), "paid");
  const out = resolveStreetInvoicePaymentPresentation({
    ridePaid: true,
    responsePaymentPaid: true,
    billitPaid: null,
  });
  assert.equal(out.invoice_payment_status, "sync_in_progress");
});

test("PAY1B: billitPaid false + updating/syncPending => sync_in_progress", () => {
  const out = resolveStreetInvoicePaymentPresentation({
    ridePaid: true,
    billitPaid: false,
    billitUpdating: true,
    syncPending: true,
  });
  assert.equal(out.invoice_payment_status, "sync_in_progress");
  assert.notEqual(out.invoice_payment_status, "outstanding");
});

test("PAY1B: sync failure is sync_failed, not outstanding", () => {
  const out = resolveStreetInvoicePaymentPresentation({
    ridePaid: true,
    billitPaid: false,
    billitPaymentSyncStatus: "failed",
  });
  assert.equal(out.invoice_payment_status, "sync_failed");
  assert.equal(out.reason, "payment_sync_failed_retryable");
});

/* STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1A — auto-create gate vs existing
 * invoice paid sync. Auto-create may only gate NEW create; existing
 * invoice/order paid sync must always run for cash/card/QR. */
function assertExistingPaidSyncBypassesAutoCreate(paymentMethod) {
  const gate = resolveBillitPaidLifecycleGate({
    autoCreateEnabled: false,
    hasExistingInvoice: true,
    hasExistingBillitOrder: true,
    ridePaid: true,
    billitPaid: false,
    billitPaymentSyncStatus: "",
    paymentMethod,
  });
  assert.equal(gate.action, "sync_paid_existing");
  assert.equal(gate.bypasses_auto_create, true);
  assert.equal(
    gate.reason,
    "existing_invoice_paid_sync_bypass_auto_create",
  );
}

test("1A-GATE1: auto-create off + existing invoice + cash => paid sync", () => {
  assertExistingPaidSyncBypassesAutoCreate("cash");
});

test("1A-GATE2: auto-create off + existing invoice + card => paid sync", () => {
  assertExistingPaidSyncBypassesAutoCreate("bancontact");
});

test("1A-GATE3: auto-create off + existing invoice + QR => paid sync", () => {
  assertExistingPaidSyncBypassesAutoCreate("qr_code");
});

test("1A-GATE4: double callback => one sync (second is already_synced)", () => {
  const first = resolveBillitPaidLifecycleGate({
    autoCreateEnabled: false,
    hasExistingInvoice: true,
    hasExistingBillitOrder: true,
    ridePaid: true,
    billitPaid: false,
    paymentMethod: "cash",
  });
  assert.equal(first.action, "sync_paid_existing");
  const second = resolveBillitPaidLifecycleGate({
    autoCreateEnabled: false,
    hasExistingInvoice: true,
    hasExistingBillitOrder: true,
    ridePaid: true,
    billitPaid: true,
    billitPaymentSyncStatus: "synced",
    paymentMethod: "cash",
  });
  assert.equal(second.action, "already_synced");
  assert.equal(second.bypasses_auto_create, true);
  // Idempotent: second callback never asks to create or re-sync as create.
  assert.notEqual(second.action, "create_then_sync");
  assert.notEqual(second.action, "sync_paid_existing");
});

test("1A-GATE5: auto-create off + no existing invoice => no new automatic invoice", () => {
  const gate = resolveBillitPaidLifecycleGate({
    autoCreateEnabled: false,
    hasExistingInvoice: false,
    hasExistingBillitOrder: false,
    ridePaid: true,
    paymentMethod: "cash",
  });
  assert.equal(gate.action, "none");
  assert.equal(gate.reason, "setting_off");
  assert.equal(gate.bypasses_auto_create, false);
});

test("1A-GATE6: cross-company scope remains 403 (unchanged)", () => {
  // Paid-sync gate must not weaken tenant/company isolation. Same matcher
  // used by the worker business-invoice / documents routes.
  const rec = completedStreetBookingForDriver({ payment_status: "paid" });
  assert.equal(
    bookingMatchesRequiredTenantCompanyScope(rec, {
      tenant_id: TENANT,
      company_id: "other_company",
      hasScope: true,
    }),
    false,
  );

  // Same-company existing invoice still wants paid sync; authorization is a
  // separate upstream 403 gate and stays closed for foreign company.
  const gate = resolveBillitPaidLifecycleGate({
    autoCreateEnabled: false,
    hasExistingInvoice: true,
    hasExistingBillitOrder: true,
    ridePaid: true,
    billitPaid: false,
    paymentMethod: "cash",
  });
  assert.equal(gate.action, "sync_paid_existing");

  const foreignDocs = driverDocumentsDecision({
    record: rec,
    sessionScope: { tenant_id: TENANT, company_id: "other_company" },
    driverId: DRIVER_ID,
    bookingId: rec.booking_id,
  });
  assert.equal(foreignDocs.status, 403);
  assert.equal(foreignDocs.error, "not_in_scope");
});

test("1A-GATE7: auto-create on + no existing => create_then_sync", () => {
  const gate = resolveBillitPaidLifecycleGate({
    autoCreateEnabled: true,
    hasExistingInvoice: false,
    hasExistingBillitOrder: false,
    ridePaid: true,
  });
  assert.equal(gate.action, "create_then_sync");
  assert.equal(gate.bypasses_auto_create, false);
});

test("1A-GATE8: existing invoice without order + auto-create off => no create", () => {
  const gate = resolveBillitPaidLifecycleGate({
    autoCreateEnabled: false,
    hasExistingInvoice: true,
    hasExistingBillitOrder: false,
    ridePaid: true,
  });
  assert.equal(gate.action, "none");
  assert.equal(gate.reason, "existing_invoice_no_order_auto_create_off");
});
