/**
 * Customer-safe mapping for /book online-checkout failures.
 * A Mollie create miss must not return a phantom booking_id that GET/resume 404s.
 * An uncertain create (tr_* exists) must keep an inspectable booking_id.
 */

function _asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function _safe(value, max = 80) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.slice(0, max);
}

export function molliePaymentIdFromCreateResult(pay) {
  const mollie = _asObject(pay?.mollie);
  const id = _safe(
    mollie.id || pay?.payment_id || pay?.paymentId,
    160,
  );
  return /^tr_[A-Za-z0-9]+$/.test(id) ? id : "";
}

export function mollieErrorFromCreateResult(pay) {
  const mollie = _asObject(pay?.mollie);
  const httpRaw = Number(pay?.mollie_http_status ?? mollie.status);
  const httpStatus =
    Number.isFinite(httpRaw) && httpRaw >= 100 && httpRaw <= 599 ? httpRaw : null;
  const message =
    _safe(
      mollie.detail ||
        mollie.title ||
        pay?.mollie_error_message ||
        pay?.message ||
        pay?.error,
      180,
    ) || null;
  const field =
    _safe(mollie.field || pay?.mollie_field || pay?.payment_error_field, 80) ||
    null;
  const requestId =
    _safe(pay?.mollie_request_id || mollie.request_id || mollie.requestId, 80) ||
    null;
  return {
    httpStatus,
    message,
    field,
    request_id: requestId,
    payment_id: molliePaymentIdFromCreateResult(pay) || null,
  };
}

export function onlineCheckoutUnavailableResponse({
  pay = null,
  canonicalBookingId = "",
} = {}) {
  const details = mollieErrorFromCreateResult(pay);
  const checkoutCreated = !!details.payment_id;
  const bookingId = _safe(canonicalBookingId, 160);
  const message = details.message
    ? `Online payment checkout could not be created: ${details.message}`
    : "Online payment checkout could not be created";
  const out = {
    ok: false,
    error: "payment_checkout_unavailable",
    code: "payment_checkout_unavailable",
    message,
    requiresPayment: true,
    paymentMode: "mollie",
    checkout_created: checkoutCreated,
    closeable: checkoutCreated !== true,
    inspectable: checkoutCreated === true,
    payment_error_code:
      _safe(pay?.error || pay?.code, 80) || "payment_checkout_unavailable",
    payment_error_message: details.message,
    payment_error_field: details.field,
    mollie_http_status: details.httpStatus,
    mollie_request_id: details.request_id,
    payment_id: details.payment_id,
  };
  if (checkoutCreated && bookingId) {
    out.booking_id = bookingId;
    out.bookingId = bookingId;
  }
  return out;
}
