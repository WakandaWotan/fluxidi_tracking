/* Apply canonical booking payment fields onto a tracking trip row.
 *
 * Used by booking-worker trip KPI sync after in-car / booking mark-paid.
 * Root payment_status and nested booking_details.payment_status stay aligned
 * so Historiek cannot keep a stale unpaid details envelope.
 *
 * Run: node --test workers/booking/modules/tracking_trip_payment_apply.test.mjs
 */

function _asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : null;
}

function _text(value, max = 64) {
  if (value == null) return "";
  const text = String(value).trim();
  if (!text) return "";
  return max > 0 ? text.slice(0, max) : text;
}

function _finiteNumber(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function _writePaymentOnto(target, fields) {
  if (!_asObject(target)) return;
  const status = _text(fields.payment_status ?? fields.paymentStatus, 32);
  if (status) {
    target.payment_status = status;
    target.paymentStatus = status;
  }
  const paidAt = _text(fields.paid_at ?? fields.paidAt, 64);
  if (paidAt) {
    target.paid_at = paidAt;
    target.paidAt = paidAt;
  }
  const method = _text(fields.payment_method ?? fields.paymentMethod, 32);
  if (method) {
    target.payment_method = method;
    target.paymentMethod = method;
  }
  const source = _text(fields.payment_source ?? fields.paymentSource, 32);
  if (source) {
    target.payment_source = source;
    target.paymentSource = source;
  }
  const provider = _text(
    fields.payment_provider ?? fields.paymentProvider,
    32,
  );
  if (provider) {
    target.payment_provider = provider;
    target.paymentProvider = provider;
  }
  const amount = _finiteNumber(fields.payment_amount ?? fields.paymentAmount);
  if (amount != null) {
    target.payment_amount = amount;
    target.paymentAmount = amount;
  }
}

export function applyCanonicalPaymentFieldsToTrackingTrip(trip, fields = {}) {
  if (!_asObject(trip)) return trip;
  _writePaymentOnto(trip, fields);
  const existingDetails = _asObject(trip.booking_details);
  const details = existingDetails ? existingDetails : {};
  _writePaymentOnto(details, fields);
  if (Object.keys(details).length) {
    trip.booking_details = details;
  }
  return trip;
}
