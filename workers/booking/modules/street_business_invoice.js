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

/* Canonical street identity for the DRIVER path. STRICTER than
 * isStreetRideBooking: ride_type == "direct" alone is NEVER sufficient. A driver
 * may only request an invoice when the booking is unambiguously a street ride:
 *   - booking_id starts with "street_", OR
 *   - source == "street_ride", OR
 *   - booking_source == "street_ride". */
export function hasCanonicalStreetIdentity({ bookingId = "", record = null } = {}) {
  if (_lower(bookingId).startsWith("street_")) return true;
  const rec =
    record && typeof record === "object" && !Array.isArray(record) ? record : {};
  const booking =
    rec.booking && typeof rec.booking === "object" && !Array.isArray(rec.booking)
      ? rec.booking
      : {};
  if (_lower(rec.booking_id ?? rec.bookingId).startsWith("street_")) return true;
  const tokens = [
    rec.source,
    rec.booking_source,
    rec.bookingSource,
    booking.source,
    booking.booking_source,
  ].map(_lower);
  return tokens.some((t) => t === "street_ride");
}

/* Resolve the authoritative assigned-driver id from a stored booking record,
 * reading the same field variants the booking indexes use. Never throws. */
export function resolveAssignedDriverId(record) {
  const rec =
    record && typeof record === "object" && !Array.isArray(record) ? record : {};
  const booking =
    rec.booking && typeof rec.booking === "object" && !Array.isArray(rec.booking)
      ? rec.booking
      : {};
  const assignedObj =
    rec.assigned_driver && typeof rec.assigned_driver === "object"
      ? rec.assigned_driver
      : {};
  const candidates = [
    rec.assigned_driver_id,
    rec.assignedDriverId,
    assignedObj.driver_id,
    assignedObj.driverId,
    booking.assigned_driver_id,
    booking.assignedDriverId,
    rec.driver_id,
    rec.driverId,
    booking.driver_id,
  ];
  for (const c of candidates) {
    const v = _norm(c);
    if (v) return v;
  }
  return "";
}

/* Pure driver ownership decision: the authenticated driver may only invoice a
 * booking whose authoritative assigned_driver_id equals the caller's driver id.
 * Returns { ok, reason }. */
export function evaluateDriverInvoiceOwnership({ record = null, driverId = "" } = {}) {
  const caller = _norm(driverId);
  if (!caller) return { ok: false, reason: "driver_session_required" };
  const assigned = resolveAssignedDriverId(record);
  if (!assigned || assigned !== caller) {
    return { ok: false, reason: "driver_not_assigned" };
  }
  return { ok: true, reason: null };
}

/* Combined driver gate: canonical street identity (strict) + shared eligibility
 * (COMPLETED, not cancelled/refunded/credited) + assigned-driver ownership.
 * Returns { ok, reason, status } so the route can respond with a bounded error
 * without leaking whether another company's booking exists. */
export function evaluateDriverBusinessInvoiceGate({
  bookingId = "",
  record = null,
  driverId = "",
} = {}) {
  if (!hasCanonicalStreetIdentity({ bookingId, record })) {
    return { ok: false, reason: "not_a_street_booking", status: 422 };
  }
  const eligibility = evaluateStreetInvoiceEligibility({ bookingId, record });
  if (!eligibility.ok) {
    const status = eligibility.reason === "source_booking_not_found" ? 404 : 409;
    return { ok: false, reason: eligibility.reason, status };
  }
  const ownership = evaluateDriverInvoiceOwnership({ record, driverId });
  if (!ownership.ok) {
    return { ok: false, reason: ownership.reason, status: 403 };
  }
  return { ok: true, reason: null, status: 200 };
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

/* STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1 / 1B: pure presentation of ride
 * vs invoice payment. Priority:
 *   1. invoicePaymentConfirmedPaid → paid
 *   2. ridePaid && billitPaymentSyncPending → sync_in_progress
 *   3. !ridePaid → outstanding
 *   4. terminal sync failure → sync_failed (never outstanding)
 * `billitPaid === false` alone must NOT become outstanding when the ride is
 * already paid and Billit is still updating / sync-pending. */
export function resolveStreetInvoicePaymentPresentation({
  ridePaid = false,
  responsePaymentPaid = false,
  billitPaid = null,
  billitPaymentSyncStatus = "",
  billitUpdating = false,
  syncPending = false,
} = {}) {
  const syncToken = _lower(billitPaymentSyncStatus);
  const rideConfirmedPaid = ridePaid === true || responsePaymentPaid === true;
  const invoicePaymentConfirmedPaid =
    billitPaid === true || syncToken === "synced";
  const billitSyncFailed = syncToken === "failed";
  const billitPaymentSyncPending =
    syncPending === true ||
    billitUpdating === true ||
    syncToken === "pending" ||
    syncToken === "in_progress" ||
    syncToken === "" ||
    billitPaid === false ||
    billitPaid == null;

  if (invoicePaymentConfirmedPaid) {
    return {
      ride_payment_status: rideConfirmedPaid ? "paid" : "unpaid",
      invoice_payment_status: "paid",
      is_consistent: true,
      reason: billitPaid === true ? "billit_paid" : "billit_sync_synced",
    };
  }
  if (rideConfirmedPaid && billitSyncFailed) {
    return {
      ride_payment_status: "paid",
      invoice_payment_status: "sync_failed",
      is_consistent: true,
      reason: "payment_sync_failed_retryable",
    };
  }
  if (rideConfirmedPaid && billitPaymentSyncPending) {
    return {
      ride_payment_status: "paid",
      invoice_payment_status: "sync_in_progress",
      is_consistent: true,
      reason: "payment_sync_in_progress",
    };
  }
  if (rideConfirmedPaid) {
    return {
      ride_payment_status: "paid",
      invoice_payment_status: "sync_in_progress",
      is_consistent: true,
      reason: "payment_sync_in_progress",
    };
  }
  return {
    ride_payment_status: "unpaid",
    invoice_payment_status: "outstanding",
    is_consistent: true,
    reason: "invoice_outstanding",
  };
}

/* Pure PDF readiness classifier. invoice_reference / billit_order_id alone are
 * NEVER enough — only an explicit artifact-ready flag or a successful PDF probe
 * status (200) proves availability. */
export function resolveStreetInvoicePdfAvailability({
  hasIssuedInvoice = false,
  pdfArtifactReady = null,
  pdfProbeStatusCode = null,
  pdfProbeFailed = false,
} = {}) {
  if (!hasIssuedInvoice) {
    return { state: "unavailable", reason: "no_invoice" };
  }
  if (pdfArtifactReady === true || pdfProbeStatusCode === 200) {
    return {
      state: "available",
      reason: pdfArtifactReady === true ? "artifact_ready" : "pdf_endpoint_ok",
    };
  }
  if (pdfProbeStatusCode === 401 || pdfProbeStatusCode === 403) {
    return { state: "unavailable", reason: "pdf_auth_denied" };
  }
  if (
    pdfProbeFailed === true ||
    (typeof pdfProbeStatusCode === "number" &&
      pdfProbeStatusCode >= 500 &&
      pdfProbeStatusCode < 600)
  ) {
    return { state: "retryable_error", reason: "pdf_probe_failed" };
  }
  return {
    state: "preparing",
    reason:
      pdfProbeStatusCode === 404
        ? "pdf_not_persisted_yet"
        : pdfArtifactReady === false
          ? "artifact_pending"
          : "awaiting_pdf_evidence",
  };
}

/* Idempotent paid-sync decision for an existing street invoice. Never issues a
 * second document/order; only reports whether a Billit paid sync should run. */
export function resolveStreetInvoicePaidSyncDecision({
  hasInvoice = false,
  ridePaid = false,
  billitPaid = null,
  billitPaymentSyncStatus = "",
  billitOrderId = "",
} = {}) {
  if (!hasInvoice) {
    return { action: "none", reason: "no_invoice" };
  }
  if (!ridePaid) {
    return { action: "none", reason: "ride_unpaid" };
  }
  if (billitPaid === true || _lower(billitPaymentSyncStatus) === "synced") {
    return { action: "already_synced", reason: "already_paid" };
  }
  if (!_norm(billitOrderId)) {
    return { action: "ensure_order_then_sync", reason: "missing_billit_order" };
  }
  return { action: "sync_paid", reason: "ride_paid_billit_pending" };
}

/* STREET-BUSINESS-INVOICE-PDF-PAYMENT-SYNC-1A — paid-lifecycle gate.
 *
 * The company Billit auto-create setting may ONLY gate creation of a NEW
 * invoice / Billit order. When an issued business invoice and/or Billit order
 * already exists for the booking, a canonical cash/card/QR payment MUST always
 * sync that existing order to paid — independent of auto-create.
 *
 * Actions:
 *   - sync_paid_existing  → run maybeSyncBillitSandboxOrderPaymentState (no create)
 *   - already_synced      → no-op (idempotent)
 *   - create_then_sync    → auto-create path (setting ON, no existing)
 *   - ensure_order_then_sync → existing invoice without order; only when setting ON
 *   - none                → setting off / unpaid / nothing to do
 */
export function resolveBillitPaidLifecycleGate({
  autoCreateEnabled = false,
  hasExistingInvoice = false,
  hasExistingBillitOrder = false,
  ridePaid = false,
  billitPaid = null,
  billitPaymentSyncStatus = "",
  paymentMethod = "",
} = {}) {
  // paymentMethod is accepted for test/diagnostic parity (cash / bancontact /
  // qr_code) — the gate itself is method-agnostic once the ride is paid.
  void paymentMethod;

  if (!ridePaid) {
    return { action: "none", reason: "ride_unpaid", bypasses_auto_create: false };
  }

  const syncToken = _lower(billitPaymentSyncStatus);
  const alreadyPaid =
    billitPaid === true || syncToken === "synced";

  // Existing invoice and/or Billit order: paid sync is setting-independent.
  if (hasExistingInvoice || hasExistingBillitOrder) {
    if (alreadyPaid) {
      return {
        action: "already_synced",
        reason: "already_paid",
        bypasses_auto_create: true,
      };
    }
    if (hasExistingBillitOrder) {
      return {
        action: "sync_paid_existing",
        reason: "existing_invoice_paid_sync_bypass_auto_create",
        bypasses_auto_create: true,
      };
    }
    // Invoice exists but no Billit order yet: creating an order is still a
    // NEW Billit-order create → stays behind the auto-create gate.
    if (autoCreateEnabled === true) {
      return {
        action: "ensure_order_then_sync",
        reason: "existing_invoice_missing_order",
        bypasses_auto_create: false,
      };
    }
    return {
      action: "none",
      reason: "existing_invoice_no_order_auto_create_off",
      bypasses_auto_create: false,
    };
  }

  // No existing invoice/order: NEW create only when auto-create is ON.
  if (autoCreateEnabled !== true) {
    return {
      action: "none",
      reason: "setting_off",
      bypasses_auto_create: false,
    };
  }
  return {
    action: "create_then_sync",
    reason: "auto_create_enabled",
    bypasses_auto_create: false,
  };
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
