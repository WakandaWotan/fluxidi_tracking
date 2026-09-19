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
