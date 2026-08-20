// LIMOUSINE-OPERATIONAL-HANDOFF-P3B — additive helpers on existing Fluxidi
// aggregates. No second booking DB, inbox, planner, driver inbox, status
// machine, payment/PDF/Billit/Chiron service, or Command Center projector.
//
// Limousine remains exclusively `service_type = limousine`. Taxi/airport
// normalizeService hashes stay untouched.

export const LIMOUSINE_SERVICE_TYPE = "limousine";

export const LIMOUSINE_COMPANY_CONFIRM_RAW_STATUSES = Object.freeze([
  "confirmed",
  "accepted",
  "booked",
  "company_confirmed",
]);

export const LIMOUSINE_ACCEPTANCE_ALREADY_USED = "acceptance_reference_already_used";
export const LIMOUSINE_COMPANY_CONFIRMATION_REQUIRED = "company_confirmation_required";

function token(value, max = 80) {
  return String(value ?? "").trim().toLowerCase().slice(0, max);
}

export function isLimousineServiceType(value) {
  return token(value, 64) === LIMOUSINE_SERVICE_TYPE;
}

export function firstLimousineServiceType(...values) {
  for (const value of values) {
    if (isLimousineServiceType(value)) return LIMOUSINE_SERVICE_TYPE;
  }
  return "";
}

export function preserveLimousineServiceType(existing, fallback) {
  if (isLimousineServiceType(existing)) return LIMOUSINE_SERVICE_TYPE;
  return fallback;
}

export function bookingRecordLimousineServiceType(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const payload = rec?.payload && typeof rec.payload === "object" ? rec.payload : {};
  const quote = rec?.quote && typeof rec.quote === "object" ? rec.quote : {};
  const snapshot =
    (booking.limousine_accepted_price && typeof booking.limousine_accepted_price === "object"
      ? booking.limousine_accepted_price
      : null) ||
    (rec?.limousine_accepted_price && typeof rec.limousine_accepted_price === "object"
      ? rec.limousine_accepted_price
      : null) ||
    {};
  return firstLimousineServiceType(
    rec?.service_type,
    rec?.serviceType,
    rec?.service_category,
    booking.service_type,
    booking.serviceType,
    booking.service_category,
    payload.service_type,
    payload.serviceType,
    payload.service_category,
    quote.service_type,
    quote.serviceType,
    snapshot.service_type,
    snapshot.service_category,
  );
}

export function isLimousineCompanyConfirmRawStatus(raw) {
  const normalized = token(raw, 40).replace(/-/g, "_");
  return LIMOUSINE_COMPANY_CONFIRM_RAW_STATUSES.includes(normalized);
}

export function bookingRequiresLimousineCompanyConfirmation(rec) {
  if (!rec || typeof rec !== "object") return false;
  const booking = rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const snapshot =
    (booking.limousine_accepted_price && typeof booking.limousine_accepted_price === "object"
      ? booking.limousine_accepted_price
      : null) ||
    (rec.limousine_accepted_price && typeof rec.limousine_accepted_price === "object"
      ? rec.limousine_accepted_price
      : null) ||
    {};
  return (
    rec.company_confirmation_required === true ||
    booking.company_confirmation_required === true ||
    snapshot.company_confirmation_required === true
  );
}

export function applyLimousineCompanyConfirmation(rec, nowIso) {
  const now = nowIso || new Date().toISOString();
  if (!rec || typeof rec !== "object") return rec;
  rec.company_confirmation_required = false;
  rec.company_confirmed_at = rec.company_confirmed_at || rec.companyConfirmedAt || now;
  rec.companyConfirmedAt = rec.company_confirmed_at;
  if (rec.booking && typeof rec.booking === "object") {
    rec.booking.company_confirmation_required = false;
    rec.booking.company_confirmed_at =
      rec.booking.company_confirmed_at || rec.booking.companyConfirmedAt || now;
    rec.booking.companyConfirmedAt = rec.booking.company_confirmed_at;
    if (
      rec.booking.limousine_accepted_price &&
      typeof rec.booking.limousine_accepted_price === "object"
    ) {
      rec.booking.limousine_accepted_price.company_confirmation_required = false;
    }
  }
  if (rec.limousine_accepted_price && typeof rec.limousine_accepted_price === "object") {
    rec.limousine_accepted_price.company_confirmation_required = false;
  }
  return rec;
}

export function limousinePaymentBlockedUntilCompanyConfirm(rec) {
  return bookingRequiresLimousineCompanyConfirmation(rec);
}

export function limousineInvoiceOrChironBlocked(rec) {
  if (!bookingRecordLimousineServiceType(rec)) return false;
  if (bookingRequiresLimousineCompanyConfirmation(rec)) return true;
  const status = String(rec?.status || rec?.booking?.status || rec?.stage || "")
    .trim()
    .toUpperCase();
  return status === "CANCELLED" || status === "CANCELED";
}

export function limousineAcceptanceAlreadyConsumed(record) {
  const state = token(record?.state, 40);
  const bookingReference = String(record?.booking_reference || "").trim();
  return state === "booking_created" || !!bookingReference;
}

export function projectLimousineOperationalListFields(rec) {
  if (!bookingRecordLimousineServiceType(rec)) return {};
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const snapshot =
    (booking.limousine_accepted_price && typeof booking.limousine_accepted_price === "object"
      ? booking.limousine_accepted_price
      : null) ||
    (rec?.limousine_accepted_price && typeof rec.limousine_accepted_price === "object"
      ? rec.limousine_accepted_price
      : null) ||
    (booking.pricing_snapshot && typeof booking.pricing_snapshot === "object"
      ? booking.pricing_snapshot
      : null) ||
    (rec?.pricing_snapshot && typeof rec.pricing_snapshot === "object"
      ? rec.pricing_snapshot
      : null) ||
    {};
  const confirmationRequired = bookingRequiresLimousineCompanyConfirmation(rec);
  const duration =
    booking.requested_duration_minutes ??
    rec?.requested_duration_minutes ??
    snapshot.requested_duration_minutes ??
    null;
  return {
    service_type: LIMOUSINE_SERVICE_TYPE,
    serviceType: LIMOUSINE_SERVICE_TYPE,
    service_category: LIMOUSINE_SERVICE_TYPE,
    pricing_mode:
      booking.pricing_mode ||
      rec?.pricing_mode ||
      snapshot.published_pricing_mode ||
      snapshot.pricing_mode ||
      "",
    occasion: booking.occasion || rec?.occasion || snapshot.occasion || "",
    requested_duration_minutes: duration,
    requestedDurationMinutes: duration,
    company_confirmation_required: confirmationRequired,
    companyConfirmationRequired: confirmationRequired,
    company_confirmed_at: booking.company_confirmed_at || rec?.company_confirmed_at || "",
    companyConfirmedAt: booking.company_confirmed_at || rec?.company_confirmed_at || "",
    ...(snapshot && Object.keys(snapshot).length
      ? {
          pricing_snapshot: snapshot,
          limousine_accepted_price: snapshot,
        }
      : {}),
  };
}

export function companyConfirmationBlockedPaymentResult() {
  return {
    ok: false,
    error: LIMOUSINE_COMPANY_CONFIRMATION_REQUIRED,
    message: "Booking is waiting for company confirmation",
  };
}
