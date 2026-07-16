/* Pure, side-effect-free helpers for the street-ride business-invoice request
 * route (Phase STREET-RIDE-BUSINESS-INVOICE-A1).
 *
 * Hard rules for everything in this module:
 *   - no KV / DO / fetch / crypto / clock reads inside the decision helpers,
 *   - never mutates its inputs,
 *   - never allocates invoice numbers, never talks to Billit/Peppol,
 *   - only interprets already-loaded records / already-normalized identity.
 *
 * The Document Core invoice engine, the Billit order/paid-sync helpers and the
 * Peppol send helper are NOT moved here. The route composes them; this module
 * only holds the small NEW decision logic so it is unit-testable without
 * importing the ~90k-line Worker. */

import { safeStr } from "./parsing_utils.js";

export const STREET_BUSINESS_INVOICE_INTENT = "business_invoice";
export const STREET_INVOICE_REQUEST_SOURCE = "company_booking";

/* Authoritative pricing / payment / document-state fields that must NEVER be
 * trusted from the request body. All such state derives from the stored booking
 * and the Document Core engine. The route ignores these keys (they are never
 * read); this list exists so callers/tests can assert the contract. */
export const REJECTED_AUTHORITATIVE_REQUEST_FIELDS = Object.freeze([
  "paid",
  "payment_status",
  "paymentStatus",
  "paid_at",
  "paidAt",
  "payment_method",
  "paymentMethod",
  "payment_provider",
  "total",
  "total_incl_vat",
  "totalInclVat",
  "subtotal_ex_vat",
  "vat_amount",
  "vatAmount",
  "vat_totals",
  "status",
  "booking_status",
  "invoice_number",
  "invoiceNumber",
  "invoice_reference",
  "billit_order_id",
  "billitOrderId",
  "peppol_sent",
  "peppolSent",
]);

function _norm(v) {
  return safeStr(v);
}

function _lower(v) {
  return _norm(v).toLowerCase();
}

function _statusToken(raw) {
  return _norm(raw)
    .toUpperCase()
    .replace(/[-\s]+/g, "_");
}

/* True when the booking is a canonical street / direct ride:
 *   - id starts with "street_", OR
 *   - source / booking_source identifies a street ride, OR
 *   - ride_type identifies a direct / street-hail ride. */
export function isStreetRideBooking({ bookingId = "", record = null } = {}) {
  if (_lower(bookingId).startsWith("street_")) return true;
  const rec =
    record && typeof record === "object" && !Array.isArray(record) ? record : {};
  const booking =
    rec.booking && typeof rec.booking === "object" && !Array.isArray(rec.booking)
      ? rec.booking
      : {};
  const payload =
    rec.payload && typeof rec.payload === "object" && !Array.isArray(rec.payload)
      ? rec.payload
      : {};
  if (_lower(rec.booking_id ?? rec.bookingId).startsWith("street_")) return true;

  const sourceTokens = [
    rec.source,
    rec.booking_source,
    rec.bookingSource,
    booking.source,
    booking.booking_source,
    payload.source,
    payload.booking_source,
  ].map(_lower);
  if (
    sourceTokens.some(
      (t) => t === "street_ride" || t === "street" || t === "street_hail",
    )
  ) {
    return true;
  }

  const rideTypeTokens = [
    rec.ride_type,
    rec.rideType,
    booking.ride_type,
    payload.ride_type,
  ].map(_lower);
  if (
    rideTypeTokens.some(
      (t) => t === "direct" || t === "direct_trip" || t === "street_hail",
    )
  ) {
    return true;
  }
  return false;
}

function _bookingStatusToken(record) {
  const rec = record && typeof record === "object" ? record : {};
  const booking =
    rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  return _statusToken(rec.status ?? rec.stage ?? booking.status ?? booking.stage);
}

/* True when a normal (debit) invoice must NOT be created because the booking is
 * cancelled, refunded or credited. */
function _isNonInvoiceableState(record) {
  const rec = record && typeof record === "object" ? record : {};
  const booking =
    rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const status = _bookingStatusToken(record);
  if (
    status.includes("CANCEL") ||
    status === "DELETED" ||
    status.includes("REFUND") ||
    status.includes("CREDIT")
  ) {
    return true;
  }
  const payStatus = _lower(
    rec.payment_status ?? rec.paymentStatus ?? booking.payment_status,
  );
  if (payStatus === "refunded" || payStatus === "credited") return true;

  const refunded =
    rec.refunded === true ||
    booking.refunded === true ||
    _lower(rec.refund_status ?? booking.refund_status) === "refunded" ||
    _norm(rec.refunded_at ?? booking.refunded_at) !== "";
  const credited =
    rec.credited === true ||
    booking.credited === true ||
    _lower(rec.credit_status ?? booking.credit_status) === "credited" ||
    _norm(rec.credited_at ?? booking.credited_at) !== "" ||
    _norm(rec.credit_note_reference ?? booking.credit_note_reference) !== "";
  return refunded || credited;
}

/* Booking-level eligibility gate for this street-specific route. Returns
 * { ok, reason }. Order matters: identify the street booking first, then reject
 * non-invoiceable states, then require COMPLETED. */
export function evaluateStreetInvoiceEligibility({
  bookingId = "",
  record = null,
} = {}) {
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    return { ok: false, reason: "source_booking_not_found" };
  }
  if (!isStreetRideBooking({ bookingId, record })) {
    return { ok: false, reason: "not_a_street_booking" };
  }
  if (_isNonInvoiceableState(record)) {
    return { ok: false, reason: "booking_not_invoiceable_state" };
  }
  if (_bookingStatusToken(record) !== "COMPLETED") {
    return { ok: false, reason: "booking_not_completed" };
  }
  return { ok: true, reason: null };
}

/* Paid-now is derived ONLY from the stored booking, never the request body. */
export function streetRidePaymentStatus(record) {
  const rec = record && typeof record === "object" ? record : {};
  const booking =
    rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const raw = _lower(
    rec.payment_status ??
      rec.paymentStatus ??
      booking.payment_status ??
      booking.paymentStatus,
  );
  return raw === "paid" ? "paid" : "unpaid";
}

/* Interpret the existing billing-identity readiness verdict (computed by the
 * Worker's buildBillingCustomerIdentityReadiness). This helper does NOT
 * re-compute readiness — it only maps the verdict to a bounded reject decision
 * with a capped missing-field list. */
export function shouldRejectForBillingReadiness(readiness) {
  const r =
    readiness && typeof readiness === "object" && !Array.isArray(readiness)
      ? readiness
      : {};
  if (r.ready === true) return { reject: false, missing_fields: [] };
  const missing = Array.isArray(r.missing_fields)
    ? r.missing_fields.slice(0, 12).map((m) => _norm(m)).filter(Boolean)
    : [];
  return { reject: true, missing_fields: missing };
}

/* Build the audit snapshot persisted on the booking. Buyer/legal identity ONLY:
 * it never carries passenger pickup/dropoff or ride fields, keeping billing
 * identity strictly separate from passenger identity. Consumes an already
 * normalized billing customer (from normalizeBillingCustomerIdentityInput). */
export function buildStreetBillingCustomerSnapshot({
  normalized = null,
  actorRole = "",
  nowIso = "",
} = {}) {
  const n =
    normalized && typeof normalized === "object" && !Array.isArray(normalized)
      ? normalized
      : {};
  const ba =
    n.billing_address && typeof n.billing_address === "object"
      ? n.billing_address
      : {};
  const pp = n.peppol && typeof n.peppol === "object" ? n.peppol : {};
  return {
    customer_type: _norm(n.customer_type) || null,
    legal_name: _norm(n.legal_name) || null,
    display_name: _norm(n.display_name) || null,
    contact_email: _norm(n.contact_email) || null,
    contact_phone: _norm(n.contact_phone) || null,
    vat_number: _norm(n.vat_number) || null,
    company_registration_number: _norm(n.company_registration_number) || null,
    buyer_reference: _norm(n.buyer_reference) || null,
    billing_address: {
      street: _norm(ba.street) || null,
      postal_code: _norm(ba.postal_code) || null,
      city: _norm(ba.city) || null,
      country: _norm(ba.country).toUpperCase() || null,
    },
    peppol: {
      endpoint_id: _norm(pp.endpoint_id) || null,
      scheme: _norm(pp.scheme) || null,
    },
    snapshot_source: STREET_INVOICE_REQUEST_SOURCE,
    snapshot_actor_role: _norm(actorRole) || null,
    snapshot_at: _norm(nowIso) || null,
  };
}

/* Stable legal/tax/address/peppol fingerprint used to detect a conflicting
 * retry. Deliberately excludes display/contact convenience fields so a cosmetic
 * change (e.g. contact email) does not count as an identity conflict. */
export function billingIdentityFingerprint(snapshot) {
  const s =
    snapshot && typeof snapshot === "object" && !Array.isArray(snapshot)
      ? snapshot
      : {};
  const ba =
    s.billing_address && typeof s.billing_address === "object"
      ? s.billing_address
      : {};
  const pp = s.peppol && typeof s.peppol === "object" ? s.peppol : {};
  return [
    _lower(s.legal_name),
    _lower(s.vat_number),
    _lower(s.company_registration_number),
    _lower(ba.street),
    _lower(ba.postal_code),
    _lower(ba.city),
    _lower(ba.country),
    _lower(pp.endpoint_id),
    _lower(pp.scheme),
  ].join("|");
}

const _EMPTY_IDENTITY_FINGERPRINT = ["", "", "", "", "", "", "", "", ""].join(
  "|",
);

/* True when the requested identity conflicts with an already-issued snapshot.
 * An empty/absent existing identity is NOT a conflict (first meaningful write
 * wins). */
export function billingIdentityConflict(existingSnapshot, requestedSnapshot) {
  if (!existingSnapshot || typeof existingSnapshot !== "object") return false;
  const existing = billingIdentityFingerprint(existingSnapshot);
  if (existing === _EMPTY_IDENTITY_FINGERPRINT) return false;
  return existing !== billingIdentityFingerprint(requestedSnapshot);
}

/* Deterministic invoice idempotency key. Matches the established Document Core
 * booking-invoice key convention (inv-auto:{tenant}:{company}:{bookingId}:{leg}
 * :v1) with leg="main" because street rides are never leg-scoped. Sharing the
 * convention guarantees at-most-one invoice per booking even if the same street
 * booking is later touched by the paid-business auto path. */
export function streetRideInvoiceIdempotencyKey({
  tenantId = "",
  companyId = "",
  bookingId = "",
} = {}) {
  return `inv-auto:${_norm(tenantId)}:${_norm(companyId)}:${_norm(bookingId)}:main:v1`;
}

/* Decide the action for an incoming request given whether an invoice already
 * exists and the requested vs stored identity. Pure decision (no I/O):
 *   - no existing invoice            -> "issue"
 *   - existing invoice + same buyer  -> "reuse"
 *   - existing invoice + diff buyer  -> "conflict" (never overwrite issued). */
export function resolveBusinessInvoiceRetryDecision({
  existingInvoice = null,
  existingSnapshot = null,
  requestedSnapshot = null,
} = {}) {
  const hasInvoice = !!(
    existingInvoice &&
    typeof existingInvoice === "object" &&
    (safeStr(existingInvoice.document_id) || existingInvoice.ok === true)
  );
  if (!hasInvoice) return { action: "issue" };
  if (billingIdentityConflict(existingSnapshot, requestedSnapshot)) {
    return { action: "conflict" };
  }
  return { action: "reuse" };
}

/* Bounded success response. Only safe, non-PII fields: ids, references, status
 * tokens and the masked warning list. Never carries buyer/seller snapshots,
 * tokens, KV keys or secrets. */
export function buildBusinessInvoiceResponse({
  bookingId = "",
  documentId = "",
  invoiceReference = "",
  reused = false,
  paymentStatus = "unpaid",
  billitEnvironment = "sandbox",
  billitOrderId = null,
  billitOrderReused = false,
  billitPaymentSyncStatus = null,
  paymentReconciliation = null,
  warnings = [],
} = {}) {
  const out = {
    ok: true,
    booking_id: _norm(bookingId),
    document_id: _norm(documentId) || null,
    invoice_reference: _norm(invoiceReference) || null,
    reused: reused === true,
    payment_status: paymentStatus === "paid" ? "paid" : "unpaid",
    billit_environment: _norm(billitEnvironment) || null,
    billit_order_id: _norm(billitOrderId) || null,
    billit_order_reused: billitOrderReused === true,
    billit_payment_sync_status: _norm(billitPaymentSyncStatus) || null,
    peppol_sent: false,
    warnings: Array.isArray(warnings)
      ? warnings
          .map((w) => _norm(w))
          .filter(Boolean)
          .slice(0, 20)
      : [],
  };
  const reconciliation = _norm(paymentReconciliation);
  if (reconciliation) out.payment_reconciliation = reconciliation;
  return out;
}
