// LIMOUSINE-MARKETPLACE-P2C2B — authenticated encryption for capability tokens.
//
// Pre-activation format break: the previous HMAC form
//   limqs1|limacc1.{base64url JSON}.{HMAC}
// is intentionally NOT accepted. Gates are OFF and no real reference exists.
// Tokens are now AES-256-GCM with a fresh random 12-byte IV:
//   <version>.<iv>.<ciphertext>
//
// One Cloudflare secret (LIMOUSINE_ACCEPTANCE_SECRET) is HKDF-expanded into
// purpose-separated keys. The raw secret is never used as AES key material,
// token output, or log material.

import { base64urlDecodeToBytes, base64urlEncodeBytes } from "./crypto_utils.js";

const encoder = new TextEncoder();

export const LIMOUSINE_AEAD_IV_BYTES = 12;
export const LIMOUSINE_AEAD_TAG_BITS = 128;
export const LIMOUSINE_TOKEN_HKDF_SALT = "fluxidi.limousine.token.v1";
export const LIMOUSINE_STATUS_KEY_PURPOSE = "limousine_status_reference_v1";
export const LIMOUSINE_ACCEPTANCE_KEY_PURPOSE = "limousine_acceptance_reference_v1";
export const LIMOUSINE_TOKEN_SECRET_MIN_LENGTH = 16;

const PLACEHOLDER_SECRETS = Object.freeze([
  "changeme",
  "change-me",
  "change_me",
  "secret",
  "password",
  "placeholder",
  "todo",
  "xxx",
  "your-secret-here",
  "replace-me",
  "replace_me",
  "example",
  "dummy",
  "limousine_acceptance_secret",
  "lorem",
]);

export const LIMOUSINE_AEAD_ERRORS = Object.freeze({
  SECRET_UNUSABLE: "secret_unusable",
  MALFORMED: "malformed",
  AUTH: "auth",
});

/// Missing, blank, short or placeholder secrets fail closed. Never echo the
/// secret. Public callers map this to a safe missing-secret code.
export function inspectLimousineTokenSecret(secret) {
  if (secret == null) return { ok: false, reason: "missing" };
  const raw = String(secret).trim();
  if (!raw) return { ok: false, reason: "missing" };
  if (raw.length < LIMOUSINE_TOKEN_SECRET_MIN_LENGTH) return { ok: false, reason: "short" };
  if (PLACEHOLDER_SECRETS.includes(raw.toLowerCase())) return { ok: false, reason: "placeholder" };
  return { ok: true, secret: raw };
}

export function looksLikeLimousineAeadToken(reference, version) {
  const text = String(reference ?? "").trim();
  if (!text || !version) return false;
  const parts = text.split(".");
  if (parts.length !== 3) return false;
  if (parts[0] !== version) return false;
  if (!/^[A-Za-z0-9_-]{16}$/.test(parts[1])) return false;
  if (!/^[A-Za-z0-9_-]{22,}$/.test(parts[2])) return false;
  return true;
}

async function deriveAesGcmKey(secret, purpose) {
  const baseKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    "HKDF",
    false,
    ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    {
      name: "HKDF",
      hash: "SHA-256",
      salt: encoder.encode(LIMOUSINE_TOKEN_HKDF_SALT),
      info: encoder.encode(purpose),
    },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

function aadBytes(version, purpose) {
  return encoder.encode(`${version}|${purpose}`);
}

/// Seals `payload` under a purpose-separated AES-GCM key. A fresh IV is
/// generated for every call, so the same payload never yields the same token.
export async function sealLimousineAead({ secret, version, purpose, payload } = {}) {
  const checked = inspectLimousineTokenSecret(secret);
  if (!checked.ok) {
    return { ok: false, error: LIMOUSINE_AEAD_ERRORS.SECRET_UNUSABLE };
  }
  if (!version || !purpose) {
    return { ok: false, error: LIMOUSINE_AEAD_ERRORS.MALFORMED };
  }
  const key = await deriveAesGcmKey(checked.secret, purpose);
  const iv = crypto.getRandomValues(new Uint8Array(LIMOUSINE_AEAD_IV_BYTES));
  const plaintext = encoder.encode(JSON.stringify(payload ?? {}));
  const ciphertext = new Uint8Array(
    await crypto.subtle.encrypt(
      {
        name: "AES-GCM",
        iv,
        additionalData: aadBytes(version, purpose),
        tagLength: LIMOUSINE_AEAD_TAG_BITS,
      },
      key,
      plaintext,
    ),
  );
  return {
    ok: true,
    reference: `${version}.${base64urlEncodeBytes(iv)}.${base64urlEncodeBytes(ciphertext)}`,
  };
}

/// Decrypts and authenticates a token. Failures never include the token, IV,
/// ciphertext or decrypted payload.
export async function unsealLimousineAead({ secret, version, purpose, reference } = {}) {
  const checked = inspectLimousineTokenSecret(secret);
  if (!checked.ok) {
    return { ok: false, error: LIMOUSINE_AEAD_ERRORS.SECRET_UNUSABLE };
  }
  if (!looksLikeLimousineAeadToken(reference, version)) {
    return { ok: false, error: LIMOUSINE_AEAD_ERRORS.MALFORMED };
  }
  const parts = String(reference).trim().split(".");
  let iv;
  let ciphertext;
  try {
    iv = base64urlDecodeToBytes(parts[1]);
    ciphertext = base64urlDecodeToBytes(parts[2]);
  } catch (_) {
    return { ok: false, error: LIMOUSINE_AEAD_ERRORS.MALFORMED };
  }
  if (iv.length !== LIMOUSINE_AEAD_IV_BYTES || ciphertext.length < 17) {
    return { ok: false, error: LIMOUSINE_AEAD_ERRORS.MALFORMED };
  }
  try {
    const key = await deriveAesGcmKey(checked.secret, purpose);
    const plain = await crypto.subtle.decrypt(
      {
        name: "AES-GCM",
        iv,
        additionalData: aadBytes(version, purpose),
        tagLength: LIMOUSINE_AEAD_TAG_BITS,
      },
      key,
      ciphertext,
    );
    const payload = JSON.parse(new TextDecoder().decode(plain));
    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      return { ok: false, error: LIMOUSINE_AEAD_ERRORS.MALFORMED };
    }
    return { ok: true, payload };
  } catch (_) {
    return { ok: false, error: LIMOUSINE_AEAD_ERRORS.AUTH };
  }
}

/// True when a token segment base64url-decodes to JSON. Used only in tests to
/// prove confidentiality; production verifiers never decode the body as JSON.
export function tokenSegmentLooksLikeJson(segment) {
  try {
    const bytes = base64urlDecodeToBytes(segment);
    if (!bytes.length) return false;
    const text = new TextDecoder().decode(bytes);
    const parsed = JSON.parse(text);
    return !!parsed && typeof parsed === "object";
  } catch (_) {
    return false;
  }
}
