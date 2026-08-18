// LIMOUSINE-MARKETPLACE-P2C2B — opaque, expiring customer status reference.
//
// Issued at quote-request creation so the customer can poll status without a
// guessable request id. The token is AES-GCM sealed under a purpose-separated
// key derived from LIMOUSINE_ACCEPTANCE_SECRET:
//   limqs1.<iv>.<ciphertext>
//
// The previous HMAC form is rejected (intentional pre-activation break).
// Status and acceptance keys are never interchangeable.

import {
  LIMOUSINE_STATUS_KEY_PURPOSE,
  looksLikeLimousineAeadToken,
  sealLimousineAead,
  unsealLimousineAead,
} from "./limousine_aead_token.mjs";

export const LIMOUSINE_STATUS_TOKEN_VERSION = "limqs1";
export const LIMOUSINE_STATUS_PURPOSE = "customer_status";
export const LIMOUSINE_STATUS_REF_TTL_MINUTES = 30 * 24 * 60;

export const LIMOUSINE_STATUS_ERRORS = Object.freeze({
  MISSING_SECRET: "status_secret_missing",
  MALFORMED: "invalid_status_ref",
  BAD_SIGNATURE: "invalid_status_ref",
  EXPIRED: "invalid_status_ref",
  VERSION_MISMATCH: "invalid_status_ref",
  PURPOSE_MISMATCH: "invalid_status_ref",
});

function mapAeadError(error) {
  if (error === "secret_unusable") return LIMOUSINE_STATUS_ERRORS.MISSING_SECRET;
  return LIMOUSINE_STATUS_ERRORS.MALFORMED;
}

/// Shape check only — no crypto, no KV. A bare quote-request id fails this.
export function limousineStatusRefLooksWellFormed(value) {
  return looksLikeLimousineAeadToken(value, LIMOUSINE_STATUS_TOKEN_VERSION);
}

export function ttlMinutesFromRange(issuedAtIso, expiresAtIso, fallback = LIMOUSINE_STATUS_REF_TTL_MINUTES) {
  const issued = Date.parse(String(issuedAtIso || ""));
  const expires = Date.parse(String(expiresAtIso || ""));
  if (!Number.isFinite(issued) || !Number.isFinite(expires) || expires <= issued) {
    return fallback;
  }
  return Math.max(1, Math.round((expires - issued) / 60000));
}

/// Seals a customer-status binding into an opaque, expiring AES-GCM reference.
export async function sealLimousineStatusRef({
  secret,
  binding,
  issuedAtIso = null,
  ttlMinutes = LIMOUSINE_STATUS_REF_TTL_MINUTES,
} = {}) {
  const issuedAt = issuedAtIso || new Date().toISOString();
  const expiresAt = new Date(
    Date.parse(issuedAt) + Math.max(1, Number(ttlMinutes) || LIMOUSINE_STATUS_REF_TTL_MINUTES) * 60000,
  ).toISOString();
  const src = binding && typeof binding === "object" && !Array.isArray(binding) ? binding : {};
  const payload = {
    v: LIMOUSINE_STATUS_TOKEN_VERSION,
    purpose: LIMOUSINE_STATUS_PURPOSE,
    binding: {
      purpose: LIMOUSINE_STATUS_PURPOSE,
      tenant_id: String(src.tenant_id || ""),
      company_id: String(src.company_id || ""),
      quote_request_id: String(src.quote_request_id || ""),
      customer_fingerprint: String(src.customer_fingerprint || ""),
      created_revision: Number(src.created_revision) || 0,
    },
    issued_at: issuedAt,
    expires_at: expiresAt,
  };
  const sealed = await sealLimousineAead({
    secret,
    version: LIMOUSINE_STATUS_TOKEN_VERSION,
    purpose: LIMOUSINE_STATUS_KEY_PURPOSE,
    payload,
  });
  if (!sealed.ok) return { ok: false, error: mapAeadError(sealed.error) };
  return {
    ok: true,
    reference: sealed.reference,
    issued_at: issuedAt,
    expires_at: expiresAt,
  };
}

/// Unseals and verifies a status reference. Tampered, expired, wrong-version,
/// wrong-purpose, old HMAC or auth-failed tokens all fail closed with the
/// same public error (except a missing/unusable secret).
export async function unsealLimousineStatusRef({
  secret,
  reference,
  nowIso = null,
} = {}) {
  const text = String(reference || "").trim();
  if (!limousineStatusRefLooksWellFormed(text)) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.MALFORMED };
  }
  const opened = await unsealLimousineAead({
    secret,
    version: LIMOUSINE_STATUS_TOKEN_VERSION,
    purpose: LIMOUSINE_STATUS_KEY_PURPOSE,
    reference: text,
  });
  if (!opened.ok) return { ok: false, error: mapAeadError(opened.error) };
  const payload = opened.payload;
  if (payload.v !== LIMOUSINE_STATUS_TOKEN_VERSION) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.VERSION_MISMATCH };
  }
  if (payload.purpose !== LIMOUSINE_STATUS_PURPOSE) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.PURPOSE_MISMATCH };
  }
  const now = Date.parse(nowIso || new Date().toISOString());
  const expiry = Date.parse(String(payload.expires_at || ""));
  if (!Number.isFinite(expiry) || now > expiry) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.EXPIRED };
  }
  const binding = payload.binding && typeof payload.binding === "object" ? payload.binding : {};
  if (binding.purpose !== LIMOUSINE_STATUS_PURPOSE) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.PURPOSE_MISMATCH };
  }
  return {
    ok: true,
    binding,
    issued_at: String(payload.issued_at || ""),
    expires_at: String(payload.expires_at || ""),
  };
}

/// Verifies the unsealed binding still matches the authoritative record.
export function limousineStatusBindingMatches(binding, expected) {
  const a = binding && typeof binding === "object" ? binding : {};
  const b = expected && typeof expected === "object" ? expected : {};
  const keys = [
    "purpose",
    "tenant_id",
    "company_id",
    "quote_request_id",
    "customer_fingerprint",
    "created_revision",
  ];
  for (const key of keys) {
    if (String(a[key] ?? "") !== String(b[key] ?? "")) {
      return { ok: false, mismatched_field: key };
    }
  }
  return { ok: true };
}
