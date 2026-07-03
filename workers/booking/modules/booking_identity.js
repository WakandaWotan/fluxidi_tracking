/* Fluxidi booking identity / shadow classifier helpers (BW-M9).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. This module owns the pure identity / shadow
 * classification helpers that:
 *   - detect whether a KV record is a payment/checkout shadow row rather
 *     than a real canonical booking,
 *   - resolve the canonical booking number for a shadow record, and
 *   - derive the identity meta / stable identity-key used by the
 *     dashboard bookings-list and audit pipelines.
 *
 * Exported scope (7 helpers, all pure, no KV writes, no mutation flows):
 *   - `_dashboardBoolLike`
 *   - `_dashboardCanonicalBookingNumber`
 *   - `_dashboardUuidLikeId`
 *   - `_dashboardIdentityMeta`
 *   - `_dashboardBookingIdentityKey`  (identity-key builder — sole external
 *     caller is `_dashboardBookingIdentityInfo` in main; extracted because
 *     it is the second half of the identity-meta surface and reuses
 *     `_dashboardCanonicalBookingNumber`).
 *   - `_bookingListIsPaymentShadowRecord`
 *   - `_resolveCanonicalBookingIdFromShadow`
 *
 * Explicitly NOT moved (STOP rule — either KV/mutation flow, or
 * lifecycle/actionability logic that is not identity/shadow):
 *   - `_dashboardTimestampMs`, `_dashboardPickupTimestampMs`,
 *     `_dashboardOperationalLegFieldValues`,
 *     `_dashboardRecordHasTerminalLifecycle`,
 *     `_isDashboardActionableOpenBooking`,
 *     `_isDashboardTerminalBookingLifecycle`,
 *     `_normalizeDashboardBookingLifecycle` — lifecycle / actionability
 *     surface, not identity/shadow. Stay in main.
 *   - Booking create/update/status/payment mutations, dispatch open pool,
 *     driver list/preview, document/Billit/Peppol/Chiron, dev reset — not
 *     in scope; untouched.
 *
 * Acyclic import graph:
 *   parsing_utils.js  ─►  booking_identity.js
 *   booking_utils.js  ─►  booking_identity.js
 *   booking_identity.js does NOT import back into main.
 */

import { safeStr } from "./parsing_utils.js";
import { _pick, _bookingIntentMask } from "./booking_utils.js";

/* ---- Primitive classifiers ------------------------------------------- */

export function _dashboardBoolLike(value) {
  if (value === true) return true;
  if (value === false || value == null) return false;
  const token = String(value).trim().toLowerCase();
  return token === "1" || token === "true" || token === "yes" || token === "ja" || token === "y";
}

export function _dashboardCanonicalBookingNumber(value) {
  const token = safeStr(value, 120);
  if (!token) return "";
  if (/^[0-9]{4}-[0-9]{2}-[0-9]{3,}$/i.test(token)) return token;
  return "";
}

export function _dashboardUuidLikeId(value) {
  const token = safeStr(value, 160);
  if (!token) return false;
  if (/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(token)) return true;
  if (/^[0-9a-f]{32}$/i.test(token)) return true;
  return false;
}

/* ---- Identity meta / identity-key ----------------------------------- */

export function _dashboardIdentityMeta(rec, recordKeyId = "") {
  const bookingObj = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payloadObj = rec?.payload && typeof rec.payload === "object" ? rec.payload : {};

  const bookingIdField =
    safeStr(
      rec?.id ??
        rec?.booking_id ??
        rec?.bookingId ??
        bookingObj?.id ??
        bookingObj?.booking_id ??
        bookingObj?.bookingId,
      120,
    ) || "";
  const publicReference =
    safeStr(
      rec?.public_booking_reference ??
        rec?.publicBookingReference ??
        rec?.booking_reference ??
        rec?.bookingReference ??
        rec?.public_reference ??
        rec?.publicReference ??
        bookingObj?.public_booking_reference ??
        bookingObj?.publicBookingReference ??
        bookingObj?.booking_reference ??
        bookingObj?.bookingReference ??
        bookingObj?.public_reference ??
        bookingObj?.publicReference ??
        payloadObj?.public_booking_reference ??
        payloadObj?.publicBookingReference ??
        payloadObj?.booking_reference ??
        payloadObj?.bookingReference ??
        payloadObj?.public_reference ??
        payloadObj?.publicReference,
      160,
    ) || "";
  const canonicalFromKey = _dashboardCanonicalBookingNumber(recordKeyId);
  const canonicalFromField = _dashboardCanonicalBookingNumber(bookingIdField);
  const hasCanonicalBookingNumber = !!(canonicalFromKey || canonicalFromField);
  const hasPublicBookingReference = !!publicReference;

  const hasPaymentFlowHints =
    !!safeStr(rec?.payment_booking_id ?? rec?.paymentBookingId, 80) ||
    !!safeStr(rec?.checkout_url ?? rec?.checkoutUrl ?? rec?.payment_url ?? rec?.paymentUrl, 120);
  const hasTrackingShadowHints =
    (rec?.trip && typeof rec.trip === "object") ||
    (rec?.tracking_last && typeof rec.tracking_last === "object") ||
    !!safeStr(rec?.trip_id ?? rec?.tripId, 80);
  const internalIdLike =
    _dashboardUuidLikeId(recordKeyId) ||
    _dashboardUuidLikeId(bookingIdField) ||
    /^u_[0-9a-z_]+$/i.test(recordKeyId) ||
    /^u_[0-9a-z_]+$/i.test(bookingIdField);

  let recordShapeHint = "unknown";
  if (hasCanonicalBookingNumber || hasPublicBookingReference) {
    recordShapeHint = "canonical_booking";
  } else if (hasTrackingShadowHints) {
    recordShapeHint = "tracking_shadow_record";
  } else if (hasPaymentFlowHints || internalIdLike) {
    recordShapeHint = "provisional_payment_record";
  }

  return {
    record_key_preview: _bookingIntentMask(recordKeyId),
    booking_id_field_preview: _bookingIntentMask(bookingIdField),
    public_reference_preview: _bookingIntentMask(publicReference),
    has_public_booking_reference: hasPublicBookingReference,
    has_canonical_booking_number: hasCanonicalBookingNumber,
    record_shape_hint: recordShapeHint,
    internal_id_like: internalIdLike,
    canonical_booking_number: canonicalFromKey || canonicalFromField,
  };
}

export function _dashboardBookingIdentityKey(rec, recordKeyId = "") {
  const bookingObj = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payloadObj = rec?.payload && typeof rec.payload === "object" ? rec.payload : {};

  const preferredBookingId = safeStr(
    rec?.booking_id ??
      rec?.bookingId ??
      bookingObj?.booking_id ??
      bookingObj?.bookingId ??
      payloadObj?.booking_id ??
      payloadObj?.bookingId,
    160,
  );
  const canonicalFromPreferred = _dashboardCanonicalBookingNumber(preferredBookingId);
  if (canonicalFromPreferred) return canonicalFromPreferred;

  const recId = safeStr(rec?.id ?? bookingObj?.id, 160);
  const canonicalFromRecId = _dashboardCanonicalBookingNumber(recId);
  if (canonicalFromRecId) return canonicalFromRecId;

  const publicReference = safeStr(
    rec?.public_booking_reference ??
      rec?.publicBookingReference ??
      rec?.booking_reference ??
      rec?.bookingReference ??
      rec?.public_reference ??
      rec?.publicReference ??
      bookingObj?.public_booking_reference ??
      bookingObj?.publicBookingReference ??
      bookingObj?.booking_reference ??
      bookingObj?.bookingReference ??
      bookingObj?.public_reference ??
      bookingObj?.publicReference ??
      payloadObj?.public_booking_reference ??
      payloadObj?.publicBookingReference ??
      payloadObj?.booking_reference ??
      payloadObj?.bookingReference ??
      payloadObj?.public_reference ??
      payloadObj?.publicReference,
    160,
  );
  if (publicReference) return `ref:${publicReference.toLowerCase()}`;

  const canonicalFromRecordKey = _dashboardCanonicalBookingNumber(recordKeyId);
  if (canonicalFromRecordKey) return canonicalFromRecordKey;

  const fallback =
    safeStr(recordKeyId, 160) ||
    recId ||
    preferredBookingId ||
    publicReference ||
    "";
  return fallback ? `key:${fallback.toLowerCase()}` : "";
}

/* ---- Payment-shadow classifier + canonical resolver ------------------ */

export function _bookingListIsPaymentShadowRecord(rec, recordKeyId) {
  if (!rec || typeof rec !== "object") return false;
  const meta = _dashboardIdentityMeta(rec, recordKeyId);
  if (meta?.has_canonical_booking_number === true) return false;
  if (meta?.internal_id_like !== true) return false;
  return true;
}

// G1: resolve the canonical booking number for a payment-shadow record. The
// canonical id can be referenced by several fields depending on which leg of
// the Mollie/checkout-resume flow wrote the shadow. We accept any field whose
// value matches the canonical 2026-MM-NNNN pattern. PLN-/public references are
// not returned here because they are not direct KV record keys.
export function _resolveCanonicalBookingIdFromShadow(rec, recordKeyId = "") {
  if (!rec || typeof rec !== "object") return "";
  const direct = _dashboardCanonicalBookingNumber(safeStr(recordKeyId, 160));
  if (direct) return direct;
  const candidates = [
    rec?.canonical_booking_id,
    rec?.canonicalBookingId,
    rec?.parent_booking_id,
    rec?.parentBookingId,
    rec?.public_booking_id,
    rec?.publicBookingId,
    rec?.booking_id,
    rec?.bookingId,
    rec?.id,
    _pick(rec, ["booking", "canonical_booking_id"], null),
    _pick(rec, ["booking", "canonicalBookingId"], null),
    _pick(rec, ["booking", "parent_booking_id"], null),
    _pick(rec, ["booking", "parentBookingId"], null),
    _pick(rec, ["booking", "public_booking_id"], null),
    _pick(rec, ["booking", "publicBookingId"], null),
    _pick(rec, ["booking", "booking_id"], null),
    _pick(rec, ["booking", "bookingId"], null),
    _pick(rec, ["booking", "id"], null),
    _pick(rec, ["payload", "__booking_id"], null),
    _pick(rec, ["payload", "booking_id"], null),
    _pick(rec, ["payload", "bookingId"], null),
    _pick(rec, ["payload", "canonical_booking_id"], null),
    _pick(rec, ["payload", "canonicalBookingId"], null),
  ];
  for (const candidate of candidates) {
    const canonical = _dashboardCanonicalBookingNumber(safeStr(candidate, 160));
    if (canonical) return canonical;
  }
  return "";
}
