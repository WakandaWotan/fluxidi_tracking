/**
 * Opaque RateHawk prebook (`rhp1`) and accepted-prebook (`rha1`) tokens.
 *
 * AES-GCM sealed with RATEHAWK_OFFER_REF_SECRET and a purpose-specific
 * salt. Flutter/Booking never see book_hash or match_hash.
 */

import {
  base64urlDecodeToBytes,
  base64urlEncodeBytes,
} from "./crypto_utils.js";
import {
  RATEHAWK_ACCEPTED_PURPOSE,
  RATEHAWK_ACCEPTED_REF_PREFIX,
  RATEHAWK_PREBOOK_ACCEPT_TTL_MS,
  RATEHAWK_PREBOOK_PURPOSE,
  RATEHAWK_PREBOOK_REF_PREFIX,
  RATEHAWK_PREBOOK_TTL_MS,
} from "./ratehawk_prebook_contract.mjs";

function _text(value, max = 800) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

async function _deriveKey(env, purpose) {
  const secret = _text(env?.RATEHAWK_OFFER_REF_SECRET, 800);
  if (!secret) return null;
  const material = new TextEncoder().encode(`${secret}|${purpose}`);
  const digest = await crypto.subtle.digest("SHA-256", material);
  return crypto.subtle.importKey(
    "raw",
    digest,
    { name: "AES-GCM" },
    false,
    ["encrypt", "decrypt"],
  );
}

async function _seal(env, purpose, prefix, claims) {
  const key = await _deriveKey(env, purpose);
  if (!key) return { ok: false, reason: "offer_ref_secret_unavailable" };
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const cipher = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    new TextEncoder().encode(JSON.stringify(claims)),
  );
  return {
    ok: true,
    token: `${prefix}.${base64urlEncodeBytes(iv)}.${base64urlEncodeBytes(new Uint8Array(cipher))}`,
    expires_at: claims.expires_at,
    claims,
  };
}

async function _open(env, purpose, prefix, token, now) {
  const key = await _deriveKey(env, purpose);
  if (!key) return { ok: false, reason: "offer_ref_secret_unavailable" };
  const parts = String(token || "").split(".");
  if (parts.length !== 3 || parts[0] !== prefix) {
    return { ok: false, reason: `${prefix}_malformed` };
  }
  try {
    const iv = base64urlDecodeToBytes(parts[1]);
    const cipher = base64urlDecodeToBytes(parts[2]);
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv },
      key,
      cipher,
    );
    const claims = JSON.parse(new TextDecoder().decode(plain));
    if (Number(now) >= Number(claims.expires_at)) {
      return { ok: false, reason: `${prefix}_expired` };
    }
    if (claims.purpose !== purpose) {
      return { ok: false, reason: `${prefix}_purpose_mismatch` };
    }
    return { ok: true, claims };
  } catch {
    return { ok: false, reason: `${prefix}_invalid` };
  }
}

export async function sealRatehawkPrebookReference(env, input, { now = Date.now() } = {}) {
  const expiresAt = Number(now) + RATEHAWK_PREBOOK_TTL_MS;
  return _seal(env, RATEHAWK_PREBOOK_PURPOSE, RATEHAWK_PREBOOK_REF_PREFIX, {
    ...input,
    purpose: RATEHAWK_PREBOOK_PURPOSE,
    iat: Number(now),
    expires_at: expiresAt,
  });
}

export async function openRatehawkPrebookReference(env, token, { now = Date.now() } = {}) {
  return _open(
    env,
    RATEHAWK_PREBOOK_PURPOSE,
    RATEHAWK_PREBOOK_REF_PREFIX,
    token,
    now,
  );
}

export async function sealRatehawkAcceptedReference(env, input, { now = Date.now() } = {}) {
  const expiresAt = Number(now) + RATEHAWK_PREBOOK_ACCEPT_TTL_MS;
  return _seal(env, RATEHAWK_ACCEPTED_PURPOSE, RATEHAWK_ACCEPTED_REF_PREFIX, {
    ...input,
    purpose: RATEHAWK_ACCEPTED_PURPOSE,
    iat: Number(now),
    accepted_at: Number(now),
    expires_at: expiresAt,
  });
}

export async function openRatehawkAcceptedReference(env, token, { now = Date.now() } = {}) {
  return _open(
    env,
    RATEHAWK_ACCEPTED_PURPOSE,
    RATEHAWK_ACCEPTED_REF_PREFIX,
    token,
    now,
  );
}
