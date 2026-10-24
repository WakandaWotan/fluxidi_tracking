// Dossier 02 — one canonical payment truth.
//
// Only a verified payment-provider status of `paid` may make a booking
// canonically paid. A completed ride, a chosen payment method, a return from
// the checkout page or an optimistic client patch must never imply payment.
//
// Every server path that decides "is this paid?" reads this module so the
// receipt, the booking list, the credit gate and the invoice gate cannot
// disagree with each other.

export const CANONICAL_PAID = "paid";
export const CANONICAL_PENDING = "pending";
export const CANONICAL_FAILED = "failed";
export const CANONICAL_UNPAID = "unpaid";

/** The only provider status that proves money arrived. */
const VERIFIED_PAID_PROVIDER_STATUSES = new Set(["paid"]);

const PENDING_PROVIDER_STATUSES = new Set([
  "open",
  "pending",
  "authorized",
  "created",
  "processing",
  "checkout_open",
  "online_pending",
  "waiting",
  "initializing",
  "not_confirmed",
  // A settlement batch is a payout stage, not a customer payment.
  "settled",
]);

const FAILED_PROVIDER_STATUSES = new Set([
  "failed",
  "canceled",
  "cancelled",
  "expired",
  "abandoned",
  "declined",
  "chargeback",
  "charged_back",
  "payment_checkout_failed",
]);

/**
 * Tokens that used to leak into paid classification. They describe the ride,
 * the chosen method or a UI moment — never a verified settlement.
 */
export const TOKENS_THAT_NEVER_IMPLY_PAID = Object.freeze([
  "completed",
  "confirmed",
  "success",
  "succeeded",
  "captured",
  "bancontact",
  "card",
  "qr",
  "cash",
  "ideal",
  "return_from_checkout",
  "checkout_started",
  "method_selected",
]);

export function normalizeCanonicalPaymentToken(value) {
  if (value === null || value === undefined) return "";
  return String(value)
    .trim()
    .toLowerCase()
    .replaceAll("-", "_")
    .replaceAll(" ", "_");
}

/** True only for a verified provider settlement. */
export function providerStatusIsVerifiedPaid(value) {
  return VERIFIED_PAID_PROVIDER_STATUSES.has(normalizeCanonicalPaymentToken(value));
}

/**
 * Map a provider or stored status onto the canonical vocabulary. Anything
 * unrecognised is `unpaid`: an unknown token must never fall through to paid.
 */
export function canonicalPaymentStatusFromProvider(value) {
  const token = normalizeCanonicalPaymentToken(value);
  if (!token) return CANONICAL_UNPAID;
  if (VERIFIED_PAID_PROVIDER_STATUSES.has(token)) return CANONICAL_PAID;
  if (PENDING_PROVIDER_STATUSES.has(token)) return CANONICAL_PENDING;
  if (FAILED_PROVIDER_STATUSES.has(token)) return CANONICAL_FAILED;
  return CANONICAL_UNPAID;
}

/** Channels where the money only ever arrives through the provider. */
const ONLINE_CHANNEL_TOKENS = new Set([
  "mollie",
  "online",
  "online_payment",
  "online_payments",
  "checkout",
]);

/** Sources that mean an authorised person collected the money in the car. */
const IN_CAR_COLLECTION_SOURCES = new Set([
  "in_car",
  "in_vehicle",
  "manual",
  "driver",
  "terminal",
]);

/**
 * Canonical status for an authoritative payment write.
 *
 * A provider status decides whenever one is present, so `open` stays pending,
 * `completed` stays unpaid and only a verified `paid` is paid. Mollie therefore
 * has exactly one route to paid.
 *
 * An **absent** status is how the driver's "cash received" and "paid by
 * terminal" actions have always posted: they carry the method, an explicit
 * in-car source and an audit actor, but no provider status. Such a write
 * records paid, which is what the production build did.
 *
 * Every other write with no status stays unpaid. There is no general rule that
 * an empty or unknown status becomes paid: the caller must name an explicit
 * in-car source **and** an audit actor, and an online channel never qualifies.
 */
export function canonicalPaymentStatusForWrite({
  providerStatus = "",
  paymentSource = "",
  paymentProvider = "",
  paymentMethod = "",
  confirmedBy = "",
} = {}) {
  const status = normalizeCanonicalPaymentToken(providerStatus);
  if (status) return canonicalPaymentStatusFromProvider(status);

  const source = normalizeCanonicalPaymentToken(paymentSource);
  const provider = normalizeCanonicalPaymentToken(paymentProvider);
  const method = normalizeCanonicalPaymentToken(paymentMethod);
  if (
    ONLINE_CHANNEL_TOKENS.has(source) ||
    ONLINE_CHANNEL_TOKENS.has(provider) ||
    ONLINE_CHANNEL_TOKENS.has(method)
  ) {
    return CANONICAL_UNPAID;
  }
  // The source must be stated by the caller, never inherited from a default,
  // and the confirmation must be attributable.
  if (!IN_CAR_COLLECTION_SOURCES.has(source)) return CANONICAL_UNPAID;
  if (!String(confirmedBy ?? "").trim()) return CANONICAL_UNPAID;
  return CANONICAL_PAID;
}

/**
 * Canonical paid for a set of status tokens collected from a booking record.
 * `verifiedPaidFlag` is the server-side webhook marker (`__mollie_paid`).
 */
export function canonicalPaidFromStatusTokens(tokens, { verifiedPaidFlag = false } = {}) {
  const list = Array.isArray(tokens) ? tokens : [];
  if (list.some((token) => providerStatusIsVerifiedPaid(token))) return true;
  return verifiedPaidFlag === true;
}

/** A payment method is a choice, not a payment. */
export function paymentMethodImpliesPaid() {
  return false;
}
