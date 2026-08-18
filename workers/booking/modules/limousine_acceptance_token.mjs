// LIMOUSINE-MARKETPLACE-P2C2B — sealed, expiring acceptance reference.
//
// After a customer accepts a manual quote the server issues a truly opaque
// AES-GCM token (`limacc1.<iv>.<ciphertext>`). The client cannot read or
// alter the payload. The previous HMAC form (readable base64url JSON + MAC)
// is rejected; this is an intentional pre-activation format break.
//
// The token is a binding proof, not a store: /book still re-reads the
// authoritative quote record and re-validates eligibility.

import {
  LIMOUSINE_ACCEPTANCE_KEY_PURPOSE,
  looksLikeLimousineAeadToken,
  sealLimousineAead,
  unsealLimousineAead,
} from "./limousine_aead_token.mjs";

export const LIMOUSINE_ACCEPTANCE_TOKEN_VERSION = "limacc1";

export const LIMOUSINE_ACCEPTANCE_ERRORS = Object.freeze({
  MISSING_SECRET: "acceptance_secret_missing",
  MALFORMED: "acceptance_reference_malformed",
  BAD_SIGNATURE: "acceptance_reference_invalid",
  EXPIRED: "acceptance_reference_expired",
  VERSION_MISMATCH: "acceptance_reference_version",
});

function mapAeadError(error) {
  if (error === "secret_unusable") return LIMOUSINE_ACCEPTANCE_ERRORS.MISSING_SECRET;
  if (error === "auth") return LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE;
  return LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED;
}

/// Seals an acceptance binding into an opaque, expiring AES-GCM reference.
export async function sealLimousineAcceptance({
  secret,
  binding,
  acceptedAtIso = null,
  ttlMinutes = 60,
} = {}) {
  const acceptedAt = acceptedAtIso || new Date().toISOString();
  const expiresAt = new Date(
    Date.parse(acceptedAt) + Math.max(1, Number(ttlMinutes) || 60) * 60000,
  ).toISOString();
  const payload = {
    v: LIMOUSINE_ACCEPTANCE_TOKEN_VERSION,
    purpose: LIMOUSINE_ACCEPTANCE_KEY_PURPOSE,
    binding: binding && typeof binding === "object" ? binding : {},
    issued_at: acceptedAt,
    accepted_at: acceptedAt,
    expires_at: expiresAt,
  };
  const sealed = await sealLimousineAead({
    secret,
    version: LIMOUSINE_ACCEPTANCE_TOKEN_VERSION,
    purpose: LIMOUSINE_ACCEPTANCE_KEY_PURPOSE,
    payload,
  });
  if (!sealed.ok) return { ok: false, error: mapAeadError(sealed.error) };
  return {
    ok: true,
    reference: sealed.reference,
    accepted_at: acceptedAt,
    expires_at: expiresAt,
  };
}

/// Unseals and verifies an acceptance reference. Tampered, expired, wrong
/// purpose/key, old HMAC format or an unknown version all fail closed.
export async function unsealLimousineAcceptance({
  secret,
  reference,
  nowIso = null,
} = {}) {
  const text = String(reference || "").trim();
  const prefix = text.split(".")[0] || "";
  if (prefix !== LIMOUSINE_ACCEPTANCE_TOKEN_VERSION) {
    if (/^lim(acc|qs)\d+$/.test(prefix)) {
      return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.VERSION_MISMATCH };
    }
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED };
  }
  if (!looksLikeLimousineAeadToken(text, LIMOUSINE_ACCEPTANCE_TOKEN_VERSION)) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.MALFORMED };
  }
  const opened = await unsealLimousineAead({
    secret,
    version: LIMOUSINE_ACCEPTANCE_TOKEN_VERSION,
    purpose: LIMOUSINE_ACCEPTANCE_KEY_PURPOSE,
    reference: text,
  });
  if (!opened.ok) return { ok: false, error: mapAeadError(opened.error) };
  const payload = opened.payload;
  if (payload.v !== LIMOUSINE_ACCEPTANCE_TOKEN_VERSION) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.VERSION_MISMATCH };
  }
  if (payload.purpose && payload.purpose !== LIMOUSINE_ACCEPTANCE_KEY_PURPOSE) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.BAD_SIGNATURE };
  }
  const now = Date.parse(nowIso || new Date().toISOString());
  const expiry = Date.parse(String(payload.expires_at || ""));
  if (!Number.isFinite(expiry) || now > expiry) {
    return { ok: false, error: LIMOUSINE_ACCEPTANCE_ERRORS.EXPIRED };
  }
  return {
    ok: true,
    binding: payload.binding && typeof payload.binding === "object" ? payload.binding : {},
    accepted_at: String(payload.accepted_at || payload.issued_at || ""),
    issued_at: String(payload.issued_at || payload.accepted_at || ""),
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
    "vat_treatment",
    "offer_id",
    "offer_source_revision",
    "pricing_section_revision",
    "itinerary_fingerprint",
    "service_class_id",
    "vehicle_id",
    "terms_revision",
    "expires_at",
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
  const langs = ["nl", "en", "fr", "es"];
  const aMob = a.mobilisation_disclosure && typeof a.mobilisation_disclosure === "object"
    ? a.mobilisation_disclosure
    : {};
  const bMob = b.mobilisation_disclosure && typeof b.mobilisation_disclosure === "object"
    ? b.mobilisation_disclosure
    : {};
  for (const lang of langs) {
    if (String(aMob[lang] ?? "") !== String(bMob[lang] ?? "")) {
      return { ok: false, mismatched_field: "mobilisation_disclosure" };
    }
  }
  return { ok: true };
}
