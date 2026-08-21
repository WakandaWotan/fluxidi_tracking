/* Customer-safe payment capability of the company that will perform a ride.
 *
 * Taxi and airport customers book inside the operating company's own app, so
 * that app already knows which payment methods the company accepts. A
 * marketplace customer does not: the company is a partner they picked, and it
 * is not the company on their device. This projection is what lets such a
 * customer be offered exactly the methods that partner accepts, using the same
 * client-side resolver taxi and airport use.
 *
 * It is a UX projection only. The worker stays authoritative for creating a
 * payment, and nothing here widens what a customer may request.
 *
 * Credentials never appear. Neither does the IBAN: whether a bank transfer is
 * possible is a boolean, because the account number itself is not the
 * customer's business at this point in the flow.
 */

import { sanitizeTenantString } from "./parsing_utils.js";

const MAX_PUBLIC_PAYMENT_OPTIONS = 24;

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function optionalBoolean(value) {
  return typeof value === "boolean" ? value : null;
}

/// Published payment option ids, de-duplicated and length-capped.
function publicPaymentOptions(source) {
  const raw = Array.isArray(source) ? source : [];
  const out = [];
  const seen = new Set();
  for (const entry of raw) {
    const id = sanitizeTenantString(entry, 40).toLowerCase();
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push(id);
    if (out.length >= MAX_PUBLIC_PAYMENT_OPTIONS) break;
  }
  return out;
}

/// Projects the payment capability a customer-facing surface may read.
///
/// `livePaymentsEnabled` and `mollieForcedTestMode` come from the Mollie
/// runtime rather than the stored profile, so callers pass them in.
export function projectPublicPaymentCapability({
  businessProfile = null,
  livePaymentsEnabled = null,
  mollieForcedTestMode = null,
} = {}) {
  const profile = asObject(businessProfile);
  return {
    payment_owner_mode: sanitizeTenantString(
      profile.payment_owner_mode ?? profile.paymentOwnerMode,
      40,
    ).toLowerCase(),
    payment_demo_mode:
      optionalBoolean(profile.payment_demo_mode ?? profile.paymentDemoMode) ??
      true,
    mollie_connected:
      optionalBoolean(profile.mollie_connected ?? profile.mollieConnected) ??
      false,
    live_payments_enabled: optionalBoolean(livePaymentsEnabled),
    mollie_forced_test_mode: optionalBoolean(mollieForcedTestMode),
    public_payment_options: publicPaymentOptions(
      profile.public_payment_options ?? profile.publicPaymentOptions,
    ),
    // Presence only. The account number stays server-side.
    qr_transfer_available:
      sanitizeTenantString(profile.iban, 64).trim().length > 0,
    country: sanitizeTenantString(profile.country, 40),
  };
}

/// True when a projection would let a customer reach a hosted checkout.
///
/// Mirrors the client-side ownership gate so the server and the picker cannot
/// disagree about whether online payment is on the table.
export function publicPaymentCapabilityAllowsOnline(capability) {
  const cap = asObject(capability);
  switch (sanitizeTenantString(cap.payment_owner_mode, 40).toLowerCase()) {
    case "manual_only":
      return false;
    case "company_mollie":
      return cap.mollie_connected === true;
    case "fluxidi_central_demo":
      return true;
    default:
      return false;
  }
}
