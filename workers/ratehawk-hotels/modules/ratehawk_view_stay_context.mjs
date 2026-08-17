/**
 * Server-issued View stay / selected-card search context.
 *
 * Live RateHawk search must issue this token. Hotelpage stays fail-closed
 * until a valid token is presented. The client cannot change hid, dates,
 * guests or currency and keep a valid context.
 *
 * This module does not resolve RateHawk credentials or call the provider.
 */

import {
  base64urlDecodeToBytes,
  base64urlEncodeBytes,
  constantTimeEquals,
  jsonBase64urlDecode,
  jsonBase64urlEncode,
} from "./crypto_utils.js";

export const RATEHAWK_VIEW_STAY_CONTEXT_PREFIX = "rhctx1";
export const RATEHAWK_VIEW_STAY_CONTEXT_PURPOSE = "view_stay";
export const RATEHAWK_VIEW_STAY_CONTEXT_TTL_MS = 15 * 60 * 1000;

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _canonicalGuests(guests) {
  if (!Array.isArray(guests)) return null;
  return guests.map((room) => ({
    adults: Number(room?.adults),
    children: Array.isArray(room?.children)
      ? room.children.map((age) => Number(age))
      : [],
  }));
}

export function canonicalizeViewStayContextClaims(input = {}) {
  const hid = Number(input.hid);
  const guests = _canonicalGuests(input.guests);
  return {
    source: "ratehawk",
    hid: Number.isInteger(hid) && hid > 0 ? hid : null,
    checkin: _text(input.checkin, 10),
    checkout: _text(input.checkout, 10),
    residency: _text(input.residency, 2).toLowerCase(),
    currency: _text(input.currency, 3).toUpperCase(),
    guests,
    purpose: RATEHAWK_VIEW_STAY_CONTEXT_PURPOSE,
  };
}

function _claimsComplete(claims) {
  return Boolean(
    claims.source === "ratehawk" &&
      Number.isInteger(claims.hid) &&
      claims.hid > 0 &&
      /^\d{4}-\d{2}-\d{2}$/.test(claims.checkin) &&
      /^\d{4}-\d{2}-\d{2}$/.test(claims.checkout) &&
      /^[a-z]{2}$/.test(claims.residency) &&
      /^[A-Z]{3}$/.test(claims.currency) &&
      Array.isArray(claims.guests) &&
      claims.guests.length >= 1 &&
      claims.purpose === RATEHAWK_VIEW_STAY_CONTEXT_PURPOSE,
  );
}

function _claimsMatch(issued, expected) {
  return JSON.stringify(issued) === JSON.stringify(expected);
}

async function _hmacSign(secret, payloadB64) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(payloadB64),
  );
  return base64urlEncodeBytes(new Uint8Array(signature));
}

async function _hmacVerify(secret, payloadB64, sigB64) {
  const expected = await _hmacSign(secret, payloadB64);
  return constantTimeEquals(expected, String(sigB64 || ""));
}

export async function issueRatehawkViewStayContext(
  secret,
  input = {},
  { now = Date.now() } = {},
) {
  const signingSecret = _text(secret, 800);
  if (!signingSecret) {
    return { ok: false, reason: "view_stay_context_secret_missing" };
  }
  const claims = canonicalizeViewStayContextClaims(input);
  if (!_claimsComplete(claims)) {
    return { ok: false, reason: "view_stay_context_incomplete" };
  }
  const payload = {
    ...claims,
    iat: Number(now),
    exp: Number(now) + RATEHAWK_VIEW_STAY_CONTEXT_TTL_MS,
  };
  const payloadB64 = jsonBase64urlEncode(payload);
  const sigB64 = await _hmacSign(signingSecret, payloadB64);
  return {
    ok: true,
    token: `${RATEHAWK_VIEW_STAY_CONTEXT_PREFIX}.${payloadB64}.${sigB64}`,
    expires_at: payload.exp,
    claims,
  };
}

export async function openRatehawkViewStayContext(
  secret,
  token,
  { now = Date.now() } = {},
) {
  const signingSecret = _text(secret, 800);
  if (!signingSecret) {
    return { ok: false, reason: "view_stay_context_secret_missing" };
  }
  const raw = _text(token, 4000);
  const parts = raw.split(".");
  if (
    parts.length !== 3 ||
    parts[0] !== RATEHAWK_VIEW_STAY_CONTEXT_PREFIX ||
    !parts[1] ||
    !parts[2]
  ) {
    return { ok: false, reason: "view_stay_context_required" };
  }
  let payload = null;
  try {
    payload = jsonBase64urlDecode(parts[1]);
  } catch {
    return { ok: false, reason: "view_stay_context_malformed" };
  }
  const validSig = await _hmacVerify(signingSecret, parts[1], parts[2]);
  if (!validSig) {
    return { ok: false, reason: "view_stay_context_tampered" };
  }
  if (Number(now) >= Number(payload?.exp)) {
    return { ok: false, reason: "view_stay_context_expired" };
  }
  const issued = canonicalizeViewStayContextClaims(payload);
  if (!_claimsComplete(issued)) {
    return { ok: false, reason: "view_stay_context_incomplete" };
  }
  return { ok: true, claims: issued, expires_at: Number(payload.exp) };
}

export async function verifyRatehawkViewStayContext(
  secret,
  token,
  expectedInput = {},
  { now = Date.now() } = {},
) {
  const signingSecret = _text(secret, 800);
  if (!signingSecret) {
    return { ok: false, reason: "view_stay_context_secret_missing" };
  }
  const raw = _text(token, 4000);
  const parts = raw.split(".");
  if (
    parts.length !== 3 ||
    parts[0] !== RATEHAWK_VIEW_STAY_CONTEXT_PREFIX ||
    !parts[1] ||
    !parts[2]
  ) {
    return { ok: false, reason: "view_stay_context_required" };
  }
  let payload = null;
  try {
    payload = jsonBase64urlDecode(parts[1]);
  } catch {
    return { ok: false, reason: "view_stay_context_malformed" };
  }
  const validSig = await _hmacVerify(signingSecret, parts[1], parts[2]);
  if (!validSig) {
    return { ok: false, reason: "view_stay_context_tampered" };
  }
  if (Number(now) >= Number(payload?.exp)) {
    return { ok: false, reason: "view_stay_context_expired" };
  }
  const issued = canonicalizeViewStayContextClaims(payload);
  if (!_claimsComplete(issued)) {
    return { ok: false, reason: "view_stay_context_incomplete" };
  }
  const expected = canonicalizeViewStayContextClaims(expectedInput);
  if (!_claimsComplete(expected) || !_claimsMatch(issued, expected)) {
    return { ok: false, reason: "view_stay_context_mismatch" };
  }
  return { ok: true, claims: issued, expires_at: Number(payload.exp) };
}

export function decodeViewStayContextBytesForTests(token) {
  const parts = String(token || "").split(".");
  if (parts.length !== 3) return null;
  return base64urlDecodeToBytes(parts[1]);
}
