/* Customer-safe payment capability on the public partner profile.
 *
 * Taxi and airport customers who book a company that is not the company on
 * their device need the same projection the limousine flow already publishes.
 * This module never exposes credentials, Mollie organisation/profile ids or
 * an IBAN — only booleans, published option ids and a country.
 */

import {
  projectPublicPaymentCapability,
  publicPaymentCapabilityAllowsOnline,
} from "./public_payment_capability.mjs";

export const PUBLIC_PARTNER_PAYMENT_CAPABILITY_ALLOWLIST_VAR =
  "PUBLIC_PARTNER_PAYMENT_CAPABILITY_COMPANIES";

export const PUBLIC_PARTNER_PAYMENT_CAPABILITY_TESTERS_VAR =
  "PUBLIC_PARTNER_PAYMENT_CAPABILITY_TESTERS";

export const PAYMENT_CAPABILITY_STATUS = {
  OK: "ok",
  LOAD_FAILED: "load_failed",
  MISSING: "missing",
  NOT_OFFERED: "not_offered",
};

function normalizeId(value) {
  return String(value ?? "").trim().toLowerCase();
}

export function publicPartnerPaymentCapabilityAllowlist(env) {
  const raw = String(
    env?.[PUBLIC_PARTNER_PAYMENT_CAPABILITY_ALLOWLIST_VAR] || "",
  );
  const out = new Set();
  for (const entry of raw.split(",")) {
    const id = normalizeId(entry);
    if (id) out.add(id);
  }
  return out;
}

export function publicPartnerPaymentCapabilityTesters(env) {
  const raw = String(env?.[PUBLIC_PARTNER_PAYMENT_CAPABILITY_TESTERS_VAR] || "");
  const out = new Set();
  for (const entry of raw.split(",")) {
    const id = normalizeId(entry);
    if (id) out.add(id);
  }
  return out;
}

export function publicPartnerPaymentCapabilityEnabled(env, companyId) {
  const id = normalizeId(companyId);
  if (!id) return false;
  return publicPartnerPaymentCapabilityAllowlist(env).has(id);
}

export function publicPartnerPaymentCapabilityViewerAllowed({
  env,
  viewerCustomerId = "",
  viewerAuthenticated = false,
} = {}) {
  if (!viewerAuthenticated) return false;
  const id = normalizeId(viewerCustomerId);
  if (!id) return false;
  return publicPartnerPaymentCapabilityTesters(env).has(id);
}

const FORBIDDEN_PUBLIC_KEYS = [
  "iban",
  "api_key",
  "apiKey",
  "mollie_api_key",
  "mollieApiKey",
  "access_token",
  "accessToken",
  "refresh_token",
  "refreshToken",
  "client_secret",
  "clientSecret",
  "mollie_organization_id",
  "mollieOrganizationId",
  "mollie_profile_id",
  "mollieProfileId",
  "webhook_secret",
  "webhookSecret",
];

export function sanitizePublicPartnerPaymentCapability(capability) {
  if (!capability || typeof capability !== "object") return null;
  const allowed = [
    "payment_owner_mode",
    "payment_demo_mode",
    "mollie_connected",
    "live_payments_enabled",
    "mollie_forced_test_mode",
    "public_payment_options",
    "qr_transfer_available",
    "country",
  ];
  const out = {};
  for (const key of allowed) {
    if (key in capability) out[key] = capability[key];
  }
  for (const forbidden of FORBIDDEN_PUBLIC_KEYS) {
    if (forbidden in out) delete out[forbidden];
  }
  return out;
}

function classifyPaymentCapability(capability) {
  if (!capability) return PAYMENT_CAPABILITY_STATUS.MISSING;
  const owner = String(capability.payment_owner_mode || "").trim().toLowerCase();
  const options = Array.isArray(capability.public_payment_options)
    ? capability.public_payment_options
    : [];
  const hasSignal =
    owner.length > 0 ||
    options.length > 0 ||
    capability.mollie_connected === true ||
    capability.qr_transfer_available === true;
  if (!hasSignal) return PAYMENT_CAPABILITY_STATUS.MISSING;
  if (owner === "manual_only") return PAYMENT_CAPABILITY_STATUS.NOT_OFFERED;
  if (!publicPaymentCapabilityAllowsOnline(capability) && options.length === 0) {
    return PAYMENT_CAPABILITY_STATUS.NOT_OFFERED;
  }
  return PAYMENT_CAPABILITY_STATUS.OK;
}

/// Builds the projection for one partner, or null when the optional gates
/// refuse it. Used by tests and any remaining allowlisted caller.
export async function buildPublicPartnerPaymentCapability({
  env,
  partnerId,
  scopeFromPartnerId,
  loadBusinessProfile,
  livePaymentsEnabled = null,
  mollieForcedTestMode = null,
  viewerCustomerId = "",
  viewerAuthenticated = false,
} = {}) {
  const projection = await projectPublicPartnerPaymentForProfile({
    env,
    partnerId,
    scopeFromPartnerId,
    loadBusinessProfile,
    livePaymentsEnabled,
    mollieForcedTestMode,
    requireAllowlist: true,
    viewerCustomerId,
    viewerAuthenticated,
  });
  if (projection.status !== PAYMENT_CAPABILITY_STATUS.OK) return null;
  return projection.payment_capability;
}

/// Always-on taxi/airport projection. Distinguishes load failure, missing
/// settings and a company that simply does not offer online methods.
export async function projectPublicPartnerPaymentForProfile({
  env,
  partnerId,
  scopeFromPartnerId,
  loadBusinessProfile,
  livePaymentsEnabled = null,
  mollieForcedTestMode = null,
  requireAllowlist = false,
  viewerCustomerId = "",
  viewerAuthenticated = false,
} = {}) {
  const scope = scopeFromPartnerId ? scopeFromPartnerId(partnerId) : null;
  const companyId = scope?.company_id ?? scope?.companyId ?? "";
  if (requireAllowlist) {
    if (!publicPartnerPaymentCapabilityEnabled(env, companyId)) {
      return { status: PAYMENT_CAPABILITY_STATUS.MISSING, payment_capability: null };
    }
    if (
      !publicPartnerPaymentCapabilityViewerAllowed({
        env,
        viewerCustomerId,
        viewerAuthenticated,
      })
    ) {
      return { status: PAYMENT_CAPABILITY_STATUS.MISSING, payment_capability: null };
    }
  }

  let businessProfile = null;
  try {
    businessProfile = await loadBusinessProfile(scope);
  } catch {
    return { status: PAYMENT_CAPABILITY_STATUS.LOAD_FAILED, payment_capability: null };
  }
  if (!businessProfile || typeof businessProfile !== "object") {
    return { status: PAYMENT_CAPABILITY_STATUS.MISSING, payment_capability: null };
  }

  const capability = sanitizePublicPartnerPaymentCapability(
    projectPublicPaymentCapability({
      businessProfile,
      livePaymentsEnabled,
      mollieForcedTestMode,
    }),
  );
  const status = classifyPaymentCapability(capability);
  return {
    status,
    payment_capability:
      status === PAYMENT_CAPABILITY_STATUS.MISSING ? capability : capability,
  };
}
