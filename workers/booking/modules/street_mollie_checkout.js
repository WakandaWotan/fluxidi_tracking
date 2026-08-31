// RELEASE-P0-MOLLIE-STREET-CHECKOUT-1
//
// Pure helpers for Mollie hosted checkout on a finalized street/direct ride.
// Network / KV I/O lives in fluxidi_booking_worker.js (createStreetRideCheckoutAuthoritative).

import { normalizePaymentMethodId } from "./payment_method_truth.js";
import { buildOpenMollieCheckoutRecoveryPayload } from "./mollie_open_payment_recovery.mjs";

/**
 * STREET-ONLINE-PAYMENT-CONVERGENCE-P0
 *
 * Payment-shadow TTL for driver street hosted checkout.
 * Matched to `MOLLIE_PAYMENT_ROUTE_TTL_SECONDS` (45d) so a late Mollie
 * webhook can still resolve the shadow while the durable payment route
 * exists. Mollie hosted checkouts typically expire within hours; 45d is a
 * safe bounded upper limit for delayed webhook delivery without unbounded
 * retention. Customer /pay/create shadows are intentionally unchanged.
 */
export const STREET_HOSTED_PAYMENT_SHADOW_TTL_SECONDS = 60 * 60 * 24 * 45;

/** Durable route channel for street hosted checkout (must NOT be pos_terminal). */
export const STREET_HOSTED_CHECKOUT_ROUTE_CHANNEL = "street_hosted_checkout";
export const STREET_HOSTED_CHECKOUT_ROUTE_SOURCE = "street_checkout";

function _safeStr(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _lower(value) {
  return _safeStr(value, 200).toLowerCase();
}

function _asBool(value) {
  if (value === true) return true;
  if (value === false || value == null) return false;
  const t = _lower(value);
  return t === "1" || t === "true" || t === "yes" || t === "on";
}

function _parsePositiveEur(value) {
  if (value == null || value === "") return null;
  const n = typeof value === "number" ? value : Number(String(value).trim().replace(",", "."));
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.round(n * 100) / 100;
}

export function streetCheckoutLockKey(tenantId, companyId, bookingId) {
  const t = _safeStr(tenantId, 80);
  const c = _safeStr(companyId, 80);
  const b = _safeStr(bookingId, 160);
  if (!t || !c || !b) return null;
  return `tenant:${t}:company:${c}:street_checkout:${b}:lock:v1`;
}

/** Exclusive lock for refresh/cancel recovery (must not collide with create lock). */
export function streetCheckoutRecoveryLockKey(tenantId, companyId, bookingId) {
  const t = _safeStr(tenantId, 80);
  const c = _safeStr(companyId, 80);
  const b = _safeStr(bookingId, 160);
  if (!t || !c || !b) return null;
  return `tenant:${t}:company:${c}:street_checkout_recovery:${b}:lock:v1`;
}

export function streetCheckoutIdempotencyKey(bookingId, attemptId) {
  return `fluxidi-street-checkout:${_safeStr(bookingId, 160)}:${_safeStr(attemptId, 80)}`;
}

/**
 * Resolve the only amount Mollie may charge for a street checkout.
 * Client-supplied amounts are never authoritative; a differing client amount
 * is a hard reject.
 */
export function resolveStreetCheckoutAuthoritativeAmount(rec, clientAmountRaw = undefined) {
  if (!rec || typeof rec !== "object") {
    return { ok: false, error: "street_fare_unavailable" };
  }
  if (rec.street_ride_fare_finalized !== true && rec.streetRideFareFinalized !== true) {
    return { ok: false, error: "street_fare_not_finalized" };
  }
  const booking = rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const raw =
    rec.price_incl_vat ??
    rec.priceInclVat ??
    booking.price_incl_vat ??
    booking.priceInclVat ??
    null;
  const amount = _parsePositiveEur(raw);
  if (amount == null) {
    return { ok: false, error: "street_fare_unavailable" };
  }
  const currency = _safeStr(
    rec.currency ?? booking.currency ?? "EUR",
    8,
  ).toUpperCase() || "EUR";
  if (currency !== "EUR") {
    return { ok: false, error: "street_currency_unsupported", currency };
  }
  const amountCents = Math.round(amount * 100);
  if (!(amountCents > 0)) {
    return { ok: false, error: "street_fare_unavailable" };
  }

  if (clientAmountRaw !== undefined && clientAmountRaw !== null && String(clientAmountRaw).trim() !== "") {
    const clientAmount = _parsePositiveEur(clientAmountRaw);
    if (clientAmount == null) {
      return { ok: false, error: "client_amount_rejected" };
    }
    const clientCents = Math.round(clientAmount * 100);
    if (clientCents !== amountCents) {
      return {
        ok: false,
        error: "client_amount_mismatch",
        canonical_amount: amount,
        canonical_amount_cents: amountCents,
      };
    }
  }

  const amountValue = amount.toFixed(2);
  return {
    ok: true,
    amount,
    amount_cents: amountCents,
    amount_value: amountValue,
    currency: "EUR",
  };
}

function _plannedPriceInclVat(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const quote =
    (rec?.quote && typeof rec.quote === "object" && rec.quote) ||
    (booking.quote && typeof booking.quote === "object" && booking.quote) ||
    {};
  const pricing = quote.pricing && typeof quote.pricing === "object" ? quote.pricing : {};
  const pricingMain =
    quote.pricing_main && typeof quote.pricing_main === "object"
      ? quote.pricing_main
      : quote.pricingMain && typeof quote.pricingMain === "object"
        ? quote.pricingMain
        : {};
  return (
    rec?.price_incl_vat ??
    rec?.priceInclVat ??
    booking.price_incl_vat ??
    booking.priceInclVat ??
    rec?.leg_price_incl_vat ??
    rec?.legPriceInclVat ??
    pricing.price_incl_vat ??
    pricing.priceInclVat ??
    pricingMain.price_incl_vat ??
    pricingMain.priceInclVat ??
    null
  );
}

export function isPlannedConsumerCheckoutRecord(rec) {
  if (!rec || typeof rec !== "object") return false;
  const rideType = _lower(rec.ride_type ?? rec.booking?.ride_type);
  const kind = _lower(
    rec.kind ?? rec.booking?.kind ?? rec.ride_kind ?? rec.booking?.ride_kind,
  );
  const source = _lower(
    rec.source ??
      rec.booking_source ??
      rec.bookingSource ??
      rec.booking?.source ??
      rec.booking?.booking_source,
  );
  const id = _lower(rec.booking_id ?? rec.bookingId ?? rec.public_id ?? rec.publicId);
  const ref = _lower(
    rec.booking_public_id ?? rec.bookingPublicId ?? rec.reference ?? rec.booking_reference,
  );
  const planningRef = _lower(
    rec.planning_reference ??
      rec.planningReference ??
      rec.booking?.planning_reference ??
      rec.booking?.planningReference ??
      rec.references?.planning_reference ??
      rec.references?.planningReference,
  );
  if (rideType === "direct" || source === "street_ride" || id.startsWith("street_")) {
    return false;
  }
  return (
    rideType === "planned" ||
    kind === "planned" ||
    source === "planned" ||
    source === "customer_app" ||
    id.startsWith("pln-") ||
    ref.startsWith("pln-") ||
    planningRef.startsWith("pln-")
  );
}

export function resolvePlannedCheckoutAuthoritativeAmount(rec, clientAmountRaw = undefined) {
  if (!rec || typeof rec !== "object") {
    return { ok: false, error: "planned_fare_unavailable" };
  }
  const amount = _parsePositiveEur(_plannedPriceInclVat(rec));
  if (amount == null) {
    return { ok: false, error: "planned_fare_unavailable" };
  }
  const booking = rec.booking && typeof rec.booking === "object" ? rec.booking : {};
  const currency =
    _safeStr(rec.currency ?? booking.currency ?? "EUR", 8).toUpperCase() || "EUR";
  if (currency !== "EUR") {
    return { ok: false, error: "street_currency_unsupported", currency };
  }
  const amountCents = Math.round(amount * 100);
  if (!(amountCents > 0)) {
    return { ok: false, error: "planned_fare_unavailable" };
  }
  if (
    clientAmountRaw !== undefined &&
    clientAmountRaw !== null &&
    String(clientAmountRaw).trim() !== ""
  ) {
    const clientAmount = _parsePositiveEur(clientAmountRaw);
    if (clientAmount == null) {
      return { ok: false, error: "client_amount_rejected" };
    }
    const clientCents = Math.round(clientAmount * 100);
    if (clientCents !== amountCents) {
      return {
        ok: false,
        error: "client_amount_mismatch",
        canonical_amount: amount,
        canonical_amount_cents: amountCents,
      };
    }
  }
  return {
    ok: true,
    amount,
    amount_cents: amountCents,
    amount_value: amount.toFixed(2),
    currency: "EUR",
  };
}

export function resolveInVehicleCheckoutAuthoritativeAmount(
  rec,
  clientAmountRaw = undefined,
  { isStreetDirect = false, isPlannedConsumer = false } = {},
) {
  if (isStreetDirect === true) {
    return resolveStreetCheckoutAuthoritativeAmount(rec, clientAmountRaw);
  }
  if (isPlannedConsumer === true || isPlannedConsumerCheckoutRecord(rec)) {
    return resolvePlannedCheckoutAuthoritativeAmount(rec, clientAmountRaw);
  }
  return { ok: false, error: "not_street_booking" };
}

export function streetCheckoutLifecycleToken(rec) {
  return _safeStr(
    rec?.status ??
      rec?.lifecycle_status ??
      rec?.lifecycleStatus ??
      rec?.booking?.status ??
      "",
    40,
  ).toUpperCase();
}

export function streetCheckoutPaymentStatusToken(rec) {
  return _lower(
    rec?.payment_status ??
      rec?.paymentStatus ??
      rec?.booking?.payment_status ??
      rec?.booking?.paymentStatus ??
      "unpaid",
  );
}

export function isStreetCheckoutPaidLike(status) {
  const t = _lower(status);
  return (
    t === "paid" ||
    t === "confirmed" ||
    t === "completed" ||
    t === "success" ||
    t === "settled" ||
    t === "succeeded" ||
    t === "captured"
  );
}

export function isStreetCheckoutFailedLike(status) {
  const t = _lower(status);
  return (
    t === "failed" ||
    t === "canceled" ||
    t === "cancelled" ||
    t === "expired" ||
    t === "abandoned"
  );
}

export function isStreetCheckoutOpenLike(status) {
  const t = _lower(status);
  return t === "open" || t === "pending" || t === "authorized" || t === "mollie_open";
}

/**
 * MOLLIE-ONLINE-PAYMENT-USER-CANCEL-FALLBACK-RELEASE-P0:
 * Durable Fluxidi checkout abandonment (fallback allowed) — not Mollie status.
 */
export function isStreetCheckoutOwnershipAbandoned(rec) {
  if (!rec || typeof rec !== "object") return false;
  if (_asBool(rec.mollie_checkout_abandoned) || _asBool(rec.mollieCheckoutAbandoned)) {
    return true;
  }
  const attempt = _lower(
    rec.payment_attempt_status ??
      rec.paymentAttemptStatus ??
      rec.booking?.payment_attempt_status ??
      rec.booking?.paymentAttemptStatus,
  );
  return attempt === "abandoned";
}

/**
 * True when canonical record currently holds a reusable open Mollie checkout.
 */
export function readOpenStreetMollieCheckout(rec) {
  if (!rec || typeof rec !== "object") return null;
  const paymentStatus = streetCheckoutPaymentStatusToken(rec);
  if (isStreetCheckoutPaidLike(paymentStatus)) return null;
  if (isStreetCheckoutFailedLike(paymentStatus)) return null;
  // User-abandoned checkout must never resurrect as active owner even when
  // stale checkout_url / mollie.status=open remain for audit/reconciliation.
  if (isStreetCheckoutOwnershipAbandoned(rec)) return null;
  const mode = _lower(
    rec.payment_mode ??
      rec.paymentMode ??
      rec.booking?.payment_mode ??
      rec.payload?.payment_mode,
  );
  const provider = _lower(
    rec.payment_provider ??
      rec.paymentProvider ??
      rec.booking?.payment_provider ??
      rec.payload?.payment_provider,
  );
  if (mode !== "mollie" && provider !== "mollie") return null;
  const checkoutUrl = _safeStr(
    rec.checkout_url ??
      rec.checkoutUrl ??
      rec.payment_url ??
      rec.paymentUrl ??
      rec.booking?.checkout_url ??
      rec.booking?.checkoutUrl,
    2000,
  );
  if (!checkoutUrl) return null;
  const mollieStatus = _lower(
    rec.mollie?.status ?? rec.booking?.mollie?.status ?? paymentStatus,
  );
  if (mollieStatus && isStreetCheckoutFailedLike(mollieStatus)) return null;
  if (mollieStatus && !isStreetCheckoutOpenLike(mollieStatus) && mollieStatus !== "paid") {
    // unknown non-open → do not reuse
    if (mollieStatus && mollieStatus !== "open" && mollieStatus !== "pending") {
      if (!isStreetCheckoutOpenLike(mollieStatus)) {
        // allow empty
      }
    }
  }
  if (mollieStatus === "paid") return null;
  const paymentBookingId = _safeStr(
    rec.payment_booking_id ?? rec.paymentBookingId,
    160,
  );
  const molliePaymentId = _safeStr(
    rec.mollie?.payment_id ??
      rec.mollie?.id ??
      rec.payment_id ??
      rec.paymentId,
    120,
  );
  return {
    checkout_url: checkoutUrl,
    payment_booking_id: paymentBookingId || null,
    mollie_payment_id: molliePaymentId || null,
    mollie_status: mollieStatus || "open",
  };
}

export function streetCheckoutEligibility(rec, { isStreetDirect, isPlannedConsumer } = {}) {
  if (!rec || typeof rec !== "object") {
    return { ok: false, error: "booking_not_found" };
  }
  const planned = isPlannedConsumer === true;
  if (isStreetDirect !== true && planned !== true) {
    return { ok: false, error: "not_street_booking" };
  }
  const lifecycle = streetCheckoutLifecycleToken(rec);
  if (lifecycle === "CANCELLED" || lifecycle === "CANCELED" || lifecycle === "VOID") {
    return { ok: false, error: "booking_not_payable" };
  }
  if (lifecycle !== "COMPLETED") {
    return { ok: false, error: "street_not_completed" };
  }
  const payStatus = streetCheckoutPaymentStatusToken(rec);
  if (isStreetCheckoutPaidLike(payStatus)) {
    return { ok: false, error: "payment_already_paid" };
  }
  const amount =
    isStreetDirect === true
      ? resolveStreetCheckoutAuthoritativeAmount(rec)
      : resolvePlannedCheckoutAuthoritativeAmount(rec);
  if (!amount.ok) return amount;
  return { ok: true, amount, lifecycle, payment_status: payStatus };
}

/**
 * Manual in-car mark-paid vs open/paid Mollie.
 * Returns null when allowed, or { error, status } when blocked.
 */
export function manualMarkPaidConflict(rec, { confirmCancelOpenMollie = false } = {}) {
  if (!rec || typeof rec !== "object") return null;
  const payStatus = streetCheckoutPaymentStatusToken(rec);
  const provider = _lower(
    rec.payment_provider ??
      rec.paymentProvider ??
      rec.booking?.payment_provider ??
      "",
  );
  const mode = _lower(rec.payment_mode ?? rec.paymentMode ?? "");
  if (isStreetCheckoutPaidLike(payStatus) && (provider === "mollie" || mode === "mollie")) {
    return {
      error: "payment_already_paid_mollie",
      status: 409,
      message: "This ride was already paid online via Mollie.",
    };
  }
  const open = readOpenStreetMollieCheckout(rec);
  if (open && !confirmCancelOpenMollie) {
    // MOLLIE-OPEN-PAYMENT-RECOVERY-P0: include recovery actions so the client
    // can refresh / resume / cancel instead of dead-ending on 409.
    return buildOpenMollieCheckoutRecoveryPayload(open);
  }
  return open && confirmCancelOpenMollie
    ? { cancel_open: true, open_checkout: open }
    : null;
}

export function webhookAfterManualPaidConflict(canonicalRec, incomingMolliePaymentId) {
  const payStatus = streetCheckoutPaymentStatusToken(canonicalRec);
  if (!isStreetCheckoutPaidLike(payStatus)) return null;
  const provider = _lower(
    canonicalRec?.payment_provider ??
      canonicalRec?.paymentProvider ??
      canonicalRec?.booking?.payment_provider ??
      "",
  );
  const mode = _lower(
    canonicalRec?.payment_mode ?? canonicalRec?.paymentMode ?? "",
  );
  const existingMollieId = _safeStr(
    canonicalRec?.mollie?.payment_id ??
      canonicalRec?.mollie?.id ??
      canonicalRec?.payment_id ??
      canonicalRec?.paymentId,
    120,
  );
  const incoming = _safeStr(incomingMolliePaymentId, 120);
  if (provider === "manual" || mode === "manual" || !existingMollieId) {
    return {
      error: "payment_reconciliation_conflict",
      reason: "canonical_already_paid_manual",
      existing_provider: provider || mode || "manual",
      incoming_mollie_payment_id: incoming || null,
    };
  }
  if (existingMollieId && incoming && existingMollieId !== incoming) {
    return {
      error: "payment_reconciliation_conflict",
      reason: "canonical_already_paid_different_mollie",
      existing_mollie_payment_id: existingMollieId,
      incoming_mollie_payment_id: incoming,
    };
  }
  return null;
}

export function buildStreetCheckoutShadowPayload({
  canonicalBookingId,
  tenantId,
  companyId,
  amountValue,
  amountCents,
  currency,
  attemptId,
  returnUrl,
  from,
  to,
  pickupIso,
  paymentMethod = "",
  mollieMethod = "",
}) {
  // Prefer a concrete chosen method; only fall back to generic online_payment
  // when the concrete method is unknown. Never invent bank_transfer.
  const normalizedChosen = normalizePaymentMethodId(paymentMethod);
  const methodId =
    normalizedChosen && normalizedChosen !== "online_payment"
      ? normalizedChosen
      : "online_payment";
  const providerMethod =
    normalizePaymentMethodId(mollieMethod) ||
    String(mollieMethod || "").trim() ||
    null;
  // Keep raw mollie API token when provided (ideal/creditcard/…); store both.
  const providerMethodRaw = String(mollieMethod || "").trim() || null;
  return {
    __checkout_resume: true,
    checkout_resume: true,
    __street_checkout: true,
    street_checkout: true,
    __booking_id: canonicalBookingId,
    booking_id: canonicalBookingId,
    bookingId: canonicalBookingId,
    tenant_id: tenantId,
    tenantId,
    company_id: companyId,
    companyId,
    payment_mode: "mollie",
    paymentMode: "mollie",
    payment_provider: "mollie",
    paymentProvider: "mollie",
    payment_method: methodId,
    paymentMethod: methodId,
    ...(providerMethodRaw
      ? { mollie_method: providerMethodRaw, mollieMethod: providerMethodRaw }
      : providerMethod
        ? { mollie_method: providerMethod, mollieMethod: providerMethod }
        : {}),
    return_url: returnUrl || "fluxidi://pay/return",
    returnUrl: returnUrl || "fluxidi://pay/return",
    authoritative_amount: amountValue,
    authoritative_amount_cents: amountCents,
    currency,
    street_checkout_attempt_id: attemptId,
    from: from || "Street ride",
    to: to || "Street ride",
    pickup_iso: pickupIso || new Date().toISOString(),
    source: "street_ride",
    booking_source: "street_ride",
    ride_type: "direct",
  };
}

/**
 * Mollie redirectUrl for street checkout: always HTTPS worker /pay/return,
 * which then deep-links to the app. Never send fluxidi:// directly to Mollie.
 */
export function buildStreetMollieRedirectUrl({
  baseUrl,
  paymentBookingId,
  returnTo = "fluxidi://pay/return",
}) {
  const base = String(baseUrl || "").replace(/\/$/, "");
  const id = String(paymentBookingId || "").trim();
  const deep = String(returnTo || "fluxidi://pay/return").trim() || "fluxidi://pay/return";
  return `${base}/pay/return?id=${encodeURIComponent(id)}&return_to=${encodeURIComponent(deep)}`;
}
