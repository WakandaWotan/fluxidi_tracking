// Decides whether a Mollie provider status must close the planned ride.
// Cash collection and an already settled ride stay untouched.
// A payment shadow is not the ride: the linked public booking id is.

function text(value, max = 160) {
  const raw = String(value ?? "").trim();
  if (!raw) return "";
  return raw.length > max ? raw.slice(0, max) : raw;
}

export function mollieStatusClosesUnpaidRide(status) {
  const token = text(status, 40).toLowerCase();
  return token === "canceled" || token === "cancelled" || token === "expired" || token === "failed";
}

export function bookingLooksPaid(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const paymentStatus = text(
    rec?.payment_status || rec?.paymentStatus || booking.payment_status || booking.paymentStatus,
    40,
  ).toLowerCase();
  if (paymentStatus === "paid" || paymentStatus === "settled") return true;
  return !!text(rec?.paid_at || rec?.paidAt || booking.paid_at || booking.paidAt, 40);
}

export function bookingIsCashCollection(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const method = text(
    rec?.payment_method || rec?.paymentMethod || booking.payment_method || booking.paymentMethod,
    40,
  ).toLowerCase();
  const mode = text(
    rec?.payment_mode || rec?.paymentMode || booking.payment_mode || booking.paymentMode,
    40,
  ).toLowerCase();
  return method === "cash" || method === "manual" || mode === "cash" || mode === "manual";
}

export function bookingIsStreetRide(rec) {
  const source = text(
    rec?.source || rec?.booking_source || rec?.booking?.source || rec?.booking?.booking_source,
    64,
  ).toLowerCase();
  const rideType = text(rec?.ride_type || rec?.rideType || rec?.booking?.ride_type, 40).toLowerCase();
  const id = text(rec?.booking_id || rec?.bookingId, 80).toLowerCase();
  return (
    source === "street_ride" ||
    rideType === "direct" ||
    id.startsWith("street_") ||
    rec?.street_ride === true ||
    rec?.streetRide === true ||
    rec?.booking?.street_ride === true
  );
}

function bookingLifecycleToken(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return text(rec?.status || rec?.stage || booking.status || booking.stage, 40).toUpperCase();
}

function hasOperationalLegs(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  return [rec?.operational_legs, rec?.operationalLegs, booking.operational_legs, booking.operationalLegs]
    .some((legs) => Array.isArray(legs) && legs.length > 0);
}

/**
 * @returns {{ cancelBookingId: string, reason: string }}
 * reason `canonical` means keyBookingId itself is the ride and must be closed
 * without a short payment-shadow TTL.
 * reason `linked_canonical` means the stored row is a payment shadow and
 * cancelBookingId is the public ride.
 */
export function onlinePaymentFailureCancelTarget(rec, keyBookingId, mollieStatus) {
  if (!mollieStatusClosesUnpaidRide(mollieStatus)) {
    return { cancelBookingId: "", reason: "provider_open" };
  }
  if (!rec || typeof rec !== "object") {
    return { cancelBookingId: "", reason: "missing_record" };
  }
  if (bookingLooksPaid(rec)) return { cancelBookingId: "", reason: "already_paid" };
  if (bookingIsCashCollection(rec)) return { cancelBookingId: "", reason: "cash" };
  if (bookingIsStreetRide(rec)) return { cancelBookingId: "", reason: "street" };
  const lifecycle = bookingLifecycleToken(rec);
  if (lifecycle === "COMPLETED" || lifecycle === "COMPLETE" || lifecycle === "DONE" || lifecycle === "CLOSED") {
    return { cancelBookingId: "", reason: "completed" };
  }
  const keyId = text(keyBookingId, 160);
  const publicId = text(
    rec.public_booking_id ||
      rec.publicBookingId ||
      rec.booking?.public_booking_id ||
      rec.booking?.booking_id ||
      rec.booking_id,
    160,
  );
  const canonicalHere =
    hasOperationalLegs(rec) ||
    (!!publicId && publicId === keyId && !!(rec.booking || rec.planning_reference || rec.planningReference));
  if (canonicalHere && keyId) return { cancelBookingId: keyId, reason: "canonical" };
  if (publicId && keyId && publicId !== keyId) {
    return { cancelBookingId: publicId, reason: "linked_canonical" };
  }
  return { cancelBookingId: "", reason: "not_a_ride" };
}
