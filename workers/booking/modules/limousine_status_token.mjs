// LIMOUSINE-MARKETPLACE-P2C2A — opaque, expiring customer status reference.
//
// Issued at quote-request creation so the customer can poll status without a
// guessable request id. The token is HMAC-sealed with the same server-only
// secret as the acceptance reference (LIMOUSINE_ACCEPTANCE_SECRET) but uses a
// distinct version prefix (`limqs1`) so the two tokens cannot be confused.
//
// This is a binding proof, not a store: status reads still load the
// authoritative quote record. The client cannot read or alter the payload.

import {
  base64urlEncodeBytes,
  base64urlDecodeToBytes,
  constantTimeEquals,
} from "./crypto_utils.js";

const encoder = new TextEncoder();

async function hmacSign(secret, message) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(String(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return base64urlEncodeBytes(new Uint8Array(signature));
}

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

/// Shape check only — no crypto, no KV. A bare quote-request id fails this.
export function limousineStatusRefLooksWellFormed(value) {
  const text = String(value ?? "").trim();
  return /^limqs1\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}$/.test(text);
}

export function ttlMinutesFromRange(issuedAtIso, expiresAtIso, fallback = LIMOUSINE_STATUS_REF_TTL_MINUTES) {
  const issued = Date.parse(String(issuedAtIso || ""));
  const expires = Date.parse(String(expiresAtIso || ""));
  if (!Number.isFinite(issued) || !Number.isFinite(expires) || expires <= issued) {
    return fallback;
  }
  return Math.max(1, Math.round((expires - issued) / 60000));
}

/// Seals a customer-status binding into an opaque, expiring reference.
export async function sealLimousineStatusRef({
  secret,
  binding,
  issuedAtIso = null,
  ttlMinutes = LIMOUSINE_STATUS_REF_TTL_MINUTES,
} = {}) {
  if (!secret) return { ok: false, error: LIMOUSINE_STATUS_ERRORS.MISSING_SECRET };
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
  const body = base64urlEncodeBytes(encoder.encode(JSON.stringify(payload)));
  const signature = await hmacSign(secret, body);
  return {
    ok: true,
    reference: `${LIMOUSINE_STATUS_TOKEN_VERSION}.${body}.${signature}`,
    issued_at: issuedAt,
    expires_at: expiresAt,
  };
}

/// Unseals and verifies a status reference. Tampered, expired, wrong-version
/// or wrong-purpose tokens all fail closed with the same public error.
export async function unsealLimousineStatusRef({
  secret,
  reference,
  nowIso = null,
} = {}) {
  if (!secret) return { ok: false, error: LIMOUSINE_STATUS_ERRORS.MISSING_SECRET };
  if (!limousineStatusRefLooksWellFormed(reference)) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.MALFORMED };
  }
  const parts = String(reference || "").split(".");
  const [version, body, signature] = parts;
  if (version !== LIMOUSINE_STATUS_TOKEN_VERSION) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.VERSION_MISMATCH };
  }
  const expected = await hmacSign(secret, body);
  if (!constantTimeEquals(expected, signature)) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.BAD_SIGNATURE };
  }
  let payload = null;
  try {
    payload = JSON.parse(new TextDecoder().decode(base64urlDecodeToBytes(body)));
  } catch (_) {
    return { ok: false, error: LIMOUSINE_STATUS_ERRORS.MALFORMED };
  }
  if (!payload || payload.v !== LIMOUSINE_STATUS_TOKEN_VERSION) {
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
