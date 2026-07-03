/* Fluxidi pure payment-classification / read helpers (BW-M8b).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. Strictly-acyclic, pure read helpers only. All four
 * functions read `rec.payment_status`, `rec.__mollie_paid`, and adjacent
 * fields and return normalized tokens/booleans/strings. None of them
 * writes to KV, mutates records, or triggers any payment-lifecycle side
 * effect.
 *
 * Scope:
 *   - `_bookingPaymentStatusTokens`                — collect + normalize
 *                                                    payment-status tokens
 *                                                    from all record layers.
 *   - `_bookingRecordIsPaidForCredit`              — paid-for-credit
 *                                                    predicate used by
 *                                                    refund/credit gates.
 *   - `_bookingRecordPaymentStatusNormalized`      — canonical
 *                                                    compliance-payment
 *                                                    status string.
 *   - `_resolveBookingRecordPaymentStatusForProjection` — read-model
 *                                                    projection helper for
 *                                                    the flatten pipeline.
 *
 * Explicitly NOT moved (STOP rule — KV writers, mutations, or
 * payment-lifecycle side effects):
 *   - updateBookingPaymentAuthoritative, /bookings/:id/payment handlers,
 *     /pay/create, /webhook/mollie, /pay/status.
 *   - credit / refund lifecycle mutations (applyPendingCreditStateOnPaidCancellation,
 *     _bookingRecordIsCancelledForCreditDecision usage in mutation flows,
 *     Mollie refund gate mutations, credit decision writers).
 *   - _logBookingPaymentClassify — kept in main because it composes with
 *     _bookingRecordIsCancelledForCreditDecision (booking-core coupling)
 *     and belongs alongside the lifecycle-audit log surface.
 *   - _bookingRecordOnlinePaidProviderSet / _bookingRecordPaymentProviderToken
 *     — pure but used exclusively by _bookingRecordIsMollieOnlinePayment
 *     (Mollie payment-provider classification, a distinct semantic domain
 *     from status classification). Kept in main to respect BW-M8b's named
 *     scope.
 *
 * Acyclic import graph:
 *   parsing_utils.js  ─►  compliance_events.js  ─►  booking_payment_classify.js
 *   parsing_utils.js  ─►  booking_payment_classify.js
 *   booking_payment_classify.js does NOT import back into main.
 */

import { safeStr } from "./parsing_utils.js";
import { normalizeCompliancePaymentStatus } from "./compliance_events.js";

/* ---- Payment-status token collector ---------------------------------- */

// Byte-identical to `_bookingPaymentStatusTokens` in
// fluxidi_booking_worker.js. Gathers status strings from all record
// layers (rec, rec.booking, rec.payload, rec.*.mollie.status),
// lowercases + underscore-normalizes, drops empties.
export function _bookingPaymentStatusTokens(rec) {
  if (!rec || typeof rec !== "object") return [];
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payload = rec?.payload && typeof rec.payload === "object" ? rec.payload : {};
  return [
    rec?.payment_status,
    rec?.paymentStatus,
    booking?.payment_status,
    booking?.paymentStatus,
    payload?.payment_status,
    payload?.paymentStatus,
    rec?.mollie?.status,
    booking?.mollie?.status,
    payload?.mollie?.status,
  ]
    .map((value) =>
      safeStr(value, 64).toLowerCase().replaceAll("-", "_").replaceAll(" ", "_"),
    )
    .filter(Boolean);
}

/* ---- Paid-for-credit predicate --------------------------------------- */

// Byte-identical to `_bookingRecordIsPaidForCredit` in
// fluxidi_booking_worker.js. Classifies whether a booking record is
// definitively "paid" for the purposes of credit/refund eligibility
// checks. Never mutates the record.
export function _bookingRecordIsPaidForCredit(rec) {
  if (!rec || typeof rec !== "object") return false;
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payload = rec?.payload && typeof rec.payload === "object" ? rec.payload : {};
  const paidLike = new Set([
    "paid",
    "confirmed",
    "completed",
    "success",
    "settled",
    "succeeded",
    "captured",
  ]);
  const notPaidLike = new Set([
    "pending",
    "open",
    "checkout_open",
    "online_pending",
    "created",
    "waiting",
    "failed",
    "cancelled",
    "canceled",
    "expired",
    "abandoned",
    "not_confirmed",
    "unknown",
    "unpaid",
    "not_paid",
    "initializing",
    "payment_checkout_failed",
    "processing",
    "authorized",
  ]);
  const statusTokens = _bookingPaymentStatusTokens(rec);
  if (statusTokens.some((token) => paidLike.has(token))) return true;
  if (statusTokens.some((token) => notPaidLike.has(token))) return false;
  if (
    rec?.__mollie_paid === true ||
    booking?.__mollie_paid === true ||
    payload?.__mollie_paid === true
  ) {
    return true;
  }
  return false;
}

/* ---- Canonical compliance-status string ------------------------------ */

// Byte-identical to `_bookingRecordPaymentStatusNormalized` in
// fluxidi_booking_worker.js. Returns the canonical compliance-payment
// status ("paid" when paid-for-credit, else the compliance-normalized
// raw status). Uses `normalizeCompliancePaymentStatus` from the existing
// compliance_events.js module (already imported in main since BW-M5).
export function _bookingRecordPaymentStatusNormalized(rec) {
  if (_bookingRecordIsPaidForCredit(rec)) return "paid";
  return normalizeCompliancePaymentStatus(
    rec?.payment_status ??
      rec?.paymentStatus ??
      rec?.booking?.payment_status ??
      rec?.booking?.paymentStatus ??
      rec?.payload?.payment_status ??
      rec?.payload?.paymentStatus,
  );
}

/* ---- Projection helper for flatten pipeline / read-model ------------- */

// Byte-identical to `_resolveBookingRecordPaymentStatusForProjection` in
// fluxidi_booking_worker.js. Returns "paid" when paid-for-credit, else
// the raw payment_status string from any record layer (up to 40 chars),
// or null when no raw status is present. Used exclusively by the
// flatten/read-model pipeline for the rides-list projection.
export function _resolveBookingRecordPaymentStatusForProjection(rec) {
  if (_bookingRecordIsPaidForCredit(rec)) return "paid";
  const raw = safeStr(
    rec?.payment_status ??
      rec?.paymentStatus ??
      rec?.booking?.payment_status ??
      rec?.booking?.paymentStatus ??
      rec?.payload?.payment_status ??
      rec?.payload?.paymentStatus,
    40,
  );
  return raw || null;
}
