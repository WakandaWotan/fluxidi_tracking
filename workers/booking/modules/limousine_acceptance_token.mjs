// LIMOUSINE-MARKETPLACE-P2C2 — sealed, expiring acceptance reference.
//
// After a customer accepts a manual quote the server issues an OPAQUE token
// that binds every fact the booking must honour. The client cannot read or
// alter the payload: it is base64url JSON sealed with an HMAC-SHA256 signature
// over a server-only secret, and it carries its own expiry.
//
// The token is a binding proof, not a store: /book still re-reads the
// authoritative quote record and re-validates eligibility.

const encoder = new TextEncoder();

function base64UrlEncode(bytes) {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  // btoa is available in Workers and Node 18+.
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecodeToBytes(text) {
  const normalized = String(text || "").replace(/-/g, "+").replace(/_/g, "/");
  const padded = normalized + "=".repeat((4 - (normalized.length % 4)) % 4);
  const binary = atob(padded);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

async function hmacSign(secret, message) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(String(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return base64UrlEncode(new Uint8Array(signature));
}

/// Constant-time-ish comparison (length-safe, no early exit on content).
function safeEqual(a, b) {
  const x = String(a || "");
  const y = String(b || "");
  if (x.length !== y.length) return false;
  let diff = 0;
  for (let i = 0; i < x.length; i++) diff |= x.charCodeAt(i) ^ y.charCodeAt(i);
  return diff === 0;
}

export const LIMOUSINE_ACCEPTANCE_TOKEN_VERSION = "limacc1";

export const LIMOUSINE_ACCEPTANCE_ERRORS = Object.freeze({
  MISSING_SECRET: "acceptance_secret_missing",
  MALFORMED: "acceptance_reference_malformed",
  BAD_SIGNATURE: "acceptance_reference_invalid",
  EXPIRED: "acceptance_reference_expired",
  VERSION_MISMATCH: "acceptance_reference_version",
});

/// Seals an acceptance binding into an opaque, expiring reference.
export async function sealLimousineAcceptance({
  secret,
  binding,
  acceptedAtIso = null,
  ttlMinutes = 60,
} = {}) {
  if (!secret) return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.MISSING_SECRET };
  const acceptedAt = acceptedAtIso || new Date().toISOString();
  const expiresAt = new Date(
    Date.parse(acceptedAt) + Math.max(1, Number(ttlMinutes) || 60) * 60000,
  ).toISOString();
  const payload = {
    v: LIMOUSINE_ACCEPTANCE_TOKEN_VERSION,
    binding: binding && typeof binding === "object" ? binding : {},
    accepted_at: acceptedAt,
    expires_at: expiresAt,
  };
  const body = base64UrlEncode(encoder.encode(JSON.stringify(payload)));
  const signature = await hmacSign(secret, body);
  return {
    ok: true,
    reference: `${LIMOUSINE_ACCEPTANCE_TOKEN_VERSION}.${body}.${signature}`,
    accepted_at: acceptedAt,
    expires_at: expiresAt,
  };
}

/// Unseals and verifies an acceptance reference. A tampered payload, a wrong
/// signature, an unknown version or an elapsed expiry all fail closed.
export async function unsealLimousineAcceptance({
  secret,
  reference,
  nowIso = null,
} = {}) {
  if (!secret) return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.MISSING_SECRET };
  const parts = String(reference || "").split(".");
  if (parts.length !== 3) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED };
  }
  const [version, body, signature] = parts;
  if (version !== LIMOUSINE_ACCEPTANCE_TOKEN_VERSION) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.VERSION_MISMATCH };
  }
  const expected = await hmacSign(secret, body);
  if (!safeEqual(expected, signature)) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE };
  }
  let payload = null;
  try {
    payload = JSON.parse(new TextDecoder().decode(base64UrlDecodeToBytes(body)));
  } catch (_) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED };
  }
  if (!payload || payload.v !== LIMOUSINE_ACCEPTANCE_TOKEN_VERSION) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.VERSION_MISMATCH };
  }
  const now = Date.parse(nowIso || new Date().toISOString());
  const expiry = Date.parse(String(payload.expires_at || ""));
  if (!Number.isFinite(expiry) || now > expiry) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.EXPIRED };
  }
  return {
    ok: true,
    binding: payload.binding && typeof payload.binding === "object" ? payload.binding : {},
    accepted_at: String(payload.accepted_at || ""),
    expires_at: String(payload.expires_at || ""),
  };
}

/// Verifies the unsealed binding still matches the authoritative quote record.
export function limousineAcceptanceBindingMatches(binding, expected) {
  const a = binding && typeof binding === "object" ? binding : {};
  const b = expected && typeof expected === "object" ? expected : {};
  const keys = [
    "tenant_id",
    "company_id",
    "quote_request_id",
    "quote_revision",
    "total_incl_vat_cents",
    "currency",
    "offer_id",
    "itinerary_fingerprint",
    "service_class_id",
    "vehicle_id",
    "terms_revision",
  ];
  for (const key of keys) {
    if (String(a[key] ?? "") !== String(b[key] ?? "")) {
      return { ok: false, mismatched_field: key };
    }
  }
  const aExtras = Array.isArray(a.selected_extra_ids) ? [...a.selected_extra_ids].sort() : [];
  const bExtras = Array.isArray(b.selected_extra_ids) ? [...b.selected_extra_ids].sort() : [];
  if (aExtras.join(",") !== bExtras.join(",")) {
    return { ok: false, mismatched_field: "selected_extra_ids" };
  }
  return { ok: true };
}
