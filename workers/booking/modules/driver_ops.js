/* Fluxidi driver/chauffeur read/auth/session helpers (BW-M7A).
 *
 * Verbatim extraction from workers/booking/fluxidi_booking_worker.js — no
 * behavior change. Strictly-acyclic helpers only:
 *
 *   - driver key-space constants (session, index, link, TTLs),
 *   - pure text/normalizer helpers,
 *   - env-flag readers,
 *   - crypto helpers (login salt/code, pairing code),
 *   - login-code verification (hash candidates + record match),
 *   - key builders,
 *   - session token hashing + read-only session key builder,
 *   - session-related payload helpers,
 *   - login/auth failure response builders.
 *
 * Explicitly NOT moved (STOP rule — booking/payment/dispatch/index
 * coupling):
 *   - `listDriverBookingsAuthoritative`, `listAdminDriverBookingsPreviewAuthoritative`
 *     — booking-index + payment-eligibility + dispatch-pool orchestrators.
 *   - `_loadPublicDriverSessionFromRequest` — mutates KV (deletes expired
 *     session key) and reads booking-adjacent session record shape.
 *   - `_issuePublicDriverSessionToken`, `_projectDriverSessionPayloadFromChallenge`
 *     — mint/write session and depend on photo helpers that live in main.
 *   - `_loadDriverIndexRecord`, `_saveDriverIndexRecord`,
 *     `_publicMediaDriverExistsInScope` — driver-index reader/writer that
 *     pulls in `_normalizeSafeRemoteMediaRef`, `_coerceBoolean` and other
 *     main-only helpers; touching these would broaden BW-M7A scope.
 *   - `_readDriverPhotoUrlFromRecord`, `_resolvePublicDriverPhotoForResponse`,
 *     `_driverPhotoResponseFields`, `_loadScopedDriverPhotoUrl` — depend on
 *     `_normalizeSafeRemoteMediaRef` (shared with vehicle helpers, in main).
 *   - `_generateSecureDriverLoginCode` — has a `_generateOpaqueToken`
 *     fallback path that lives in main; skipped to preserve the fallback
 *     without co-moving unrelated code.
 *
 * Acyclic import graph:
 *   parsing_utils.js ─┐
 *   crypto_utils.js  ─┼──►  driver_ops.js
 *   http_response.js ─┘
 * driver_ops.js does NOT import back into main.
 */

import { sanitizeTenantString, safeStr } from "./parsing_utils.js";
import { sha256Hex, constantTimeEquals } from "./crypto_utils.js";
import { json } from "./http_response.js";

/* ---- Driver key-space constants (BW-M7A, verbatim) ------------------- */

export const COMPANY_DRIVER_INDEX_KEY_PREFIX = "tenant:";
export const COMPANY_DRIVER_INDEX_KEY_MIDDLE = ":company:";
export const COMPANY_DRIVER_INDEX_KEY_SUFFIX = ":drivers:index:v1";

export const COMPANY_DRIVER_LINK_CHALLENGE_KEY_PREFIX = "company_driver_link:challenge:";
export const COMPANY_DRIVER_LINK_CHALLENGE_KEY_SUFFIX = ":v1";
export const COMPANY_DRIVER_LINK_ACTIVE_KEY_PREFIX = "company_driver_link:active:";
export const COMPANY_DRIVER_LINK_ACTIVE_KEY_SUFFIX = ":v1";

export const COMPANY_DRIVER_LINK_DEFAULT_TTL_SECONDS = 10 * 60;
export const COMPANY_DRIVER_LINK_MAX_TTL_SECONDS = 30 * 60;

export const PUBLIC_DRIVER_SESSION_KEY_PREFIX = "public_driver:session:";
export const PUBLIC_DRIVER_SESSION_KEY_SUFFIX = ":v1";

/* ---- Pure text/normalizer helpers ------------------------------------ */

export function _normalizeDriverPairingTtl(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return COMPANY_DRIVER_LINK_DEFAULT_TTL_SECONDS;
  const rounded = Math.round(parsed);
  if (rounded <= 0) return COMPANY_DRIVER_LINK_DEFAULT_TTL_SECONDS;
  return Math.min(COMPANY_DRIVER_LINK_MAX_TTL_SECONDS, rounded);
}

export function _normalizeDriverPairingCode(value) {
  return sanitizeTenantString(value, 40).toUpperCase().replace(/\s+/g, "");
}

export function _validateDriverPairingCode(value) {
  const code = _normalizeDriverPairingCode(value);
  if (!code) return { ok: false, code: "", error: "invalid_pairing_code" };
  if (!/^[A-Z0-9]{4,12}$/.test(code)) {
    return { ok: false, code, error: "invalid_pairing_code" };
  }
  return { ok: true, code };
}

export function _normalizeDriverDisplayName(value) {
  return sanitizeTenantString(value, 160);
}

export function _normalizeDriverEmployeeNumber(value) {
  return sanitizeTenantString(value, 80);
}

export function _normalizeDriverLoginCode(value) {
  return sanitizeTenantString(value, 80).trim().toLowerCase();
}

export function _maskPublicDriverLoginValue(value) {
  const text = sanitizeTenantString(value, 80);
  if (!text) return "empty";
  if (text.length <= 2) return "*".repeat(text.length);
  return `${text.slice(0, 1)}***${text.slice(-1)}(len=${text.length})`;
}

export function _driverCodeLast4(value) {
  const text = sanitizeTenantString(value, 120);
  if (!text) return "";
  return text.length <= 4 ? text : text.slice(-4);
}

export function _normalizeDriverPhone(value) {
  return sanitizeTenantString(value, 40);
}

export function _normalizeDriverPhoneForAdminUpsert(value) {
  const raw = sanitizeTenantString(value, 80).trim();
  if (!raw) return "";
  if (!raw.startsWith("+")) return "";
  const digits = raw.slice(1).replace(/[^0-9]/g, "");
  return `+${digits}`;
}

export function _normalizeDriverAvailabilityStatus(value, fallback = "available") {
  const normalized = sanitizeTenantString(value, 40).toLowerCase();
  switch (normalized) {
    case "available":
    case "ready":
    case "online":
      return "available";
    case "paused":
    case "pause":
    case "unavailable":
    case "not_available":
      return "paused";
    case "offline":
      return "offline";
    case "busy":
    case "on_trip":
    case "on_the_way":
    case "waiting":
      return "busy";
    default: {
      const safeFallback = sanitizeTenantString(fallback, 40).toLowerCase();
      if (
        safeFallback === "paused" ||
        safeFallback === "offline" ||
        safeFallback === "busy"
      ) {
        return safeFallback;
      }
      return "available";
    }
  }
}

export function _driverAvailabilityAllowsDispatch(status) {
  return _normalizeDriverAvailabilityStatus(status, "available") === "available";
}

export function _normalizeDriverPairingSessionExpiry(nowMs = Date.now()) {
  return new Date(nowMs + 12 * 60 * 60 * 1000).toISOString();
}

/* ---- Env-flag reader -------------------------------------------------- */

export function _allowDriverLoginPlaintextFallback(env) {
  const raw = sanitizeTenantString(
    env?.DRIVER_LOGIN_ALLOW_PLAINTEXT_FALLBACK,
    40,
  )
    .trim()
    .toLowerCase();
  if (raw === "false" || raw === "0") return false;
  return true;
}

/* ---- Crypto helpers --------------------------------------------------- */

export function _generateDriverLoginSalt() {
  return (crypto?.randomUUID ? crypto.randomUUID() : `dls_${Date.now()}_${Math.random()}`)
    .replace(/[^a-zA-Z0-9_-]+/g, "")
    .slice(0, 80);
}

export function _generateDriverPairingCode(length = 6) {
  const normalizedLength = Math.max(4, Math.min(12, Math.round(Number(length) || 6)));
  const alphabet = "0123456789";
  const values = new Uint8Array(normalizedLength);
  crypto.getRandomValues(values);
  let out = "";
  for (const value of values) {
    out += alphabet[value % alphabet.length];
  }
  return out;
}

/* ---- Login-code verification ----------------------------------------- */

export function _driverLoginHashCandidates(normalizedCode, salt) {
  const code = _normalizeDriverLoginCode(normalizedCode);
  if (!code) return [];
  const out = [code];
  const safeSalt = sanitizeTenantString(salt, 120);
  if (safeSalt) out.unshift(`${safeSalt}:${code}`);
  return out;
}

// Uses `sha256Hex` + `constantTimeEquals` from crypto_utils.js, byte-identical
// to main's `_sha256Hex` / `_constantTimeEquals` (both of which remain in
// main to keep their 40+ / 19 callers stable). Behavior identical.
export async function _driverRecordMatchesLoginCode(driverRecord, enteredCode, env = null) {
  const normalizedEntered = _normalizeDriverLoginCode(enteredCode);
  if (!normalizedEntered) return { matched: false, mode: "none" };
  const hash = sanitizeTenantString(
    driverRecord?.driver_code_hash ??
      driverRecord?.driverCodeHash,
    200,
  ).toLowerCase();
  const salt = sanitizeTenantString(
    driverRecord?.driver_code_salt ??
      driverRecord?.driverCodeSalt,
    120,
  );
  if (hash) {
    const hashCandidates = _driverLoginHashCandidates(normalizedEntered, salt);
    for (const candidate of hashCandidates) {
      const computed = (await sha256Hex(candidate)).toLowerCase();
      if (constantTimeEquals(hash, computed)) return { matched: true, mode: "hash" };
    }
  }
  if (_allowDriverLoginPlaintextFallback(env)) {
    const codeCandidates = [
      { matched_field: "driver_code", value: driverRecord?.driver_code },
      { matched_field: "driver_code", value: driverRecord?.driverCode },
      { matched_field: "login_code", value: driverRecord?.login_code },
      { matched_field: "login_code", value: driverRecord?.loginCode },
      { matched_field: "employee_number", value: driverRecord?.employee_number },
      { matched_field: "employee_number", value: driverRecord?.employeeNumber },
    ]
      .map((entry) => ({
        matched_field: entry.matched_field,
        value: _normalizeDriverLoginCode(entry.value),
      }))
      .filter((entry) => !!entry.value);
    for (const candidate of codeCandidates) {
      if (constantTimeEquals(candidate.value, normalizedEntered)) {
        return {
          matched: true,
          mode: "plaintext",
          matched_field: candidate.matched_field,
        };
      }
    }
  }
  return { matched: false, mode: "none" };
}

/* ---- Key builders ---------------------------------------------------- */

export function _companyDriverIndexKey(scope) {
  return `${COMPANY_DRIVER_INDEX_KEY_PREFIX}${scope.tenant_id}${COMPANY_DRIVER_INDEX_KEY_MIDDLE}${scope.company_id}${COMPANY_DRIVER_INDEX_KEY_SUFFIX}`;
}

export function _companyDriverLinkChallengeKey(challengeId) {
  return `${COMPANY_DRIVER_LINK_CHALLENGE_KEY_PREFIX}${challengeId}${COMPANY_DRIVER_LINK_CHALLENGE_KEY_SUFFIX}`;
}

export function _companyDriverLinkActiveKey(companyCode) {
  return `${COMPANY_DRIVER_LINK_ACTIVE_KEY_PREFIX}${companyCode}${COMPANY_DRIVER_LINK_ACTIVE_KEY_SUFFIX}`;
}

export function _publicDriverSessionKey(tokenHash) {
  const safeHash = sanitizeTenantString(tokenHash, 200).toLowerCase();
  if (!safeHash) return "";
  return `${PUBLIC_DRIVER_SESSION_KEY_PREFIX}${safeHash}${PUBLIC_DRIVER_SESSION_KEY_SUFFIX}`;
}

export function _companyDriverLinkChallengeId() {
  return (crypto?.randomUUID ? crypto.randomUUID() : `dcl_${Date.now()}_${Math.random()}`)
    .replace(/[^a-zA-Z0-9_-]+/g, "");
}

/* ---- Session token hashing ------------------------------------------- */

// Uses `sha256Hex` from crypto_utils.js, byte-identical to main's
// `_sha256Hex` (which stays in main to keep its 40+ callers stable).
export async function _hashDriverSessionToken(token) {
  const normalized = sanitizeTenantString(token, 512);
  if (!normalized) return "";
  const hash = await sha256Hex(normalized);
  return sanitizeTenantString(hash, 200).toLowerCase();
}

/* ---- Login/auth failure response builders ---------------------------- */

export function _publicDriverLoginFail(reason = "verification_failed") {
  console.log(`[PUBLIC_DRIVER_LOGIN][FAIL] reason=${sanitizeTenantString(reason, 48) || "verification_failed"}`);
  return json({ ok: false, error: "verification_failed" }, 403);
}

export function _publicDriverAuthFail() {
  return json({ ok: false, error: "unauthorized" }, 401);
}

/* ---- Payload helpers -------------------------------------------------- */

export function _readPayloadDriverIdCandidates(body) {
  const candidates = [
    safeStr(body?.driver_id ?? body?.driverId, 96),
    safeStr(body?.assigned_driver_id ?? body?.assignedDriverId, 96),
  ].filter(Boolean);
  return [...new Set(candidates)];
}

export function _assignedDriverSummaryFromDriverId(driverId) {
  const normalized = safeStr(driverId, 96);
  if (!normalized) return null;
  return {
    driver_id: normalized,
    driverId: normalized,
    id: normalized,
  };
}
