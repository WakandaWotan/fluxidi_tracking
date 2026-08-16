/* Mollie Connect (admin integration) — OAuth, token lifecycle, terminals.
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M4A), no behavior change.
 *
 * BW-M4A LITE scope: everything Mollie-Connect-owned that does NOT reach
 * across into payment lifecycle (updateBookingPaymentAuthoritative,
 * normalizePaymentOwnerMode, DEFAULT_BUSINESS_PROFILE, loadBusinessProfile,
 * normalizeBusinessProfile) stays here. Functions that bridge to
 * business_profile / payment_owner_mode remain in the main worker for a
 * later patch (BW-M4B) once those domains are extracted.
 *
 * Not moved (bridge to business_profile / payment domains):
 *   - preserveServerOwnedBusinessProfilePaymentFields
 *   - updateBusinessProfileMollieMetadata
 *   - _isCompanyMollieOAuthCredentials
 *   - _companyMollieProfileId
 *   - fetchCompanyMollieTerminals
 *   - syncCompanyMollieTerminalsSnapshot
 *   - mollieConnectOAuthCallback
 *
 * Not moved (route dispatchers, kept inline in main router):
 *   - /admin/mollie/connect/*, /mollie/connect/callback, /admin/mollie/terminals,
 *     /admin/mollie/terminal-payment/start (all inline in the fetch handler)
 */

import { safeStr, sanitizeTenantString, boolish } from "./parsing_utils.js";
import {
  base64urlEncodeBytes,
  base64urlDecodeToBytes,
  jsonBase64urlEncode,
  jsonBase64urlDecode,
} from "./crypto_utils.js";
import { json } from "./http_response.js";

/* ===================== Mollie Connect OAuth constants ===================== */

export const MOLLIE_CONNECT_OAUTH_NONCE_TTL_SECONDS = 600;
export const MOLLIE_CONNECT_OAUTH_STATE_PURPOSE = "mollie_connect_oauth";
// MOLLIE-ONBOARDING-READ-SCOPE-P0-1: onboarding.read is required for
// GET /v2/onboarding/me (live status refresh). Keep payment-related scopes
// intact; order is deterministic and must stay centralised here.
export const MOLLIE_CONNECT_OAUTH_SCOPES =
  "organizations.read profiles.read payments.read payments.write refunds.read terminals.read onboarding.read";
export const MOLLIE_CONNECT_ONBOARDING_READ_SCOPE = "onboarding.read";
export const ADMIN_MOLLIE_CONNECT_TEST_PAYMENT_TTL_SECONDS = 60 * 60 * 24 * 30;

/** Normalize Mollie's granted `scope` string (space/comma separated). */
export function normalizeMollieConnectGrantedScopes(raw) {
  const preferred = String(MOLLIE_CONNECT_OAUTH_SCOPES)
    .split(/\s+/)
    .filter(Boolean);
  const preferredIndex = new Map(preferred.map((s, i) => [s, i]));
  const tokens = safeStr(raw, 800)
    .split(/[\s,]+/)
    .map((t) => t.trim().toLowerCase())
    .filter((t) => /^[a-z][a-z0-9_.-]{0,63}$/.test(t));
  const unique = [...new Set(tokens)];
  unique.sort((a, b) => {
    const ia = preferredIndex.has(a) ? preferredIndex.get(a) : Number.MAX_SAFE_INTEGER;
    const ib = preferredIndex.has(b) ? preferredIndex.get(b) : Number.MAX_SAFE_INTEGER;
    if (ia !== ib) return ia - ib;
    return a.localeCompare(b);
  });
  return unique.join(" ");
}

export function mollieConnectGrantedScopesInclude(raw, neededScope) {
  const needed = safeStr(neededScope, 80).toLowerCase();
  if (!needed) return false;
  const normalized = normalizeMollieConnectGrantedScopes(raw);
  if (!normalized) return false;
  return normalized.split(/\s+/).includes(needed);
}
export const ADMIN_MOLLIE_TERMINAL_PAYMENT_INTENT_TTL_SECONDS = 60 * 60 * 2;
export const MOLLIE_CONNECT_TOKEN_REFRESH_LEEWAY_MS = 60 * 1000;

/* ===================== Scoped key builders ===================== */

export function buildScopedMollieConnectAuthKey(scope = null) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return null;
  return `tenant:${tenantId}:company:${companyId}:mollie_connect_auth:v1`;
}

export function buildScopedMollieConnectStatusKey(scope = null) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return null;
  return `tenant:${tenantId}:company:${companyId}:integration:mollie:status:v1`;
}

export function publicMollieConnectStatusSnapshot(record, existing = null, scope = null) {
  const rec = record && typeof record === "object" ? record : {};
  const statusRaw = safeStr(rec.status, 64).toLowerCase() || "not_configured";
  const connected = rec.connected === true && statusRaw === "connected";
  const mode = safeStr(rec.mollie_mode ?? rec.mollieMode, 16).toLowerCase();
  const demo = rec.payment_demo_mode === true
    || rec.paymentDemoMode === true
    || rec.testmode === true
    || rec.testMode === true;
  const updated = safeStr(
    rec.updatedAt ?? rec.updated_at ?? rec.lastConnectedAt ?? rec.last_connected_at,
    64,
  ) || new Date().toISOString();
  const prevRev = Number(existing?.source_revision);
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId ?? rec.tenant_id, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId ?? rec.company_id, 80);
  return {
    ...(tenantId && companyId ? { tenant_id: tenantId, company_id: companyId } : {}),
    status: connected
      ? "connected"
      : (statusRaw === "disconnected" || rec.connected === false ? "disconnected" : (statusRaw || "unknown")),
    mollie_mode: mode === "test" || mode === "live" ? mode : null,
    payment_demo_mode: demo,
    connected,
    updated_at: updated,
    source_updated_at: updated,
    source_revision: Number.isInteger(prevRev) && prevRev >= 1 ? prevRev + 1 : 1,
  };
}

async function persistPublicMollieConnectStatus(env, scope, record) {
  const key = buildScopedMollieConnectStatusKey(scope);
  if (!key || !env?.BOOKING_KV) return;
  let existing = null;
  try {
    const raw = await env.BOOKING_KV.get(key, { type: "json" });
    existing = raw && typeof raw === "object" ? raw : null;
  } catch (_) {
    existing = null;
  }
  const snapshot = publicMollieConnectStatusSnapshot(record, existing, scope);
  await env.BOOKING_KV.put(key, JSON.stringify(snapshot));
}

export function buildScopedMollieConnectNonceKey(scope = null, nonce = "") {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const nonceId = String(nonce || "").trim().replace(/[^a-zA-Z0-9_-]+/g, "");
  if (!tenantId || !companyId || !nonceId) return null;
  return `tenant:${tenantId}:company:${companyId}:mollie_oauth_state_nonce:${nonceId}:v1`;
}

export function buildScopedMollieConnectTestPaymentKey(scope = null, paymentId = "") {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const safePaymentId = safeStr(paymentId).replace(/[^a-zA-Z0-9_-]+/g, "");
  if (!tenantId || !companyId || !safePaymentId) return null;
  return `tenant:${tenantId}:company:${companyId}:admin_mollie_test_payment:${safePaymentId}:v1`;
}

export function buildScopedMollieTerminalPaymentIntentKey(scope = null, bookingId = "", terminalId = "") {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const safeBookingId = safeStr(bookingId, 160).replace(/[^a-zA-Z0-9_-]+/g, "");
  const safeTerminalId = safeStr(terminalId, 120).replace(/[^a-zA-Z0-9_-]+/g, "");
  if (!tenantId || !companyId || !safeBookingId || !safeTerminalId) return null;
  return `tenant:${tenantId}:company:${companyId}:mollie_terminal_payment_intent:${safeBookingId}:${safeTerminalId}:v1`;
}

export function buildScopedMollieTerminalsSnapshotKey(scope = null) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const testMode = boolish(scope?.testmode ?? scope?.testMode);
  if (!tenantId || !companyId) return null;
  if (testMode) return `tenant:${tenantId}:company:${companyId}:mollie_terminals:test:v1`;
  return `tenant:${tenantId}:company:${companyId}:mollie_terminals:v1`;
}

/* ===================== Admin Mollie test-payment normalizers ===================== */

export function _normalizeAdminMollieTestAmount(value) {
  if (value === null || value === undefined || value === "") {
    return "1.00";
  }
  let num = null;
  if (typeof value === "number") {
    num = value;
  } else if (typeof value === "string") {
    const trimmed = value.trim();
    if (!trimmed) return "1.00";
    if (!/^-?[0-9]+([.,][0-9]+)?$/.test(trimmed)) return null;
    num = Number(trimmed.replace(",", "."));
  } else {
    return null;
  }
  if (!Number.isFinite(num) || num <= 0) return null;
  const cents = Math.round(num * 100);
  if (!Number.isFinite(cents) || cents <= 0 || cents > 200) return null;
  return (cents / 100).toFixed(2);
}

export function _sanitizeAdminMollieConnectTestPaymentCurrency(value) {
  const currency = safeStr(value || "EUR").toUpperCase();
  return currency === "EUR" ? "EUR" : "";
}

export function _sanitizeAdminMollieConnectTestPaymentDescription(value) {
  return (
    safeStr(value || "Fluxidi company Mollie test payment").slice(0, 120) ||
    "Fluxidi company Mollie test payment"
  );
}

export function _mollieConnectOauthError(code) {
  const err = new Error(String(code || "mollie_connect_oauth_error"));
  err.code = String(code || "mollie_connect_oauth_error");
  return err;
}

export function mollieCompanyPaymentsEnabled(env) {
  return String(env?.MOLLIE_COMPANY_PAYMENTS_ENABLED || "").trim() === "true";
}

/* ===================== OAuth state signing (HMAC-SHA256) ===================== */

export async function _importMollieConnectHmacKey(secret) {
  const normalized = String(secret || "").trim();
  if (!normalized) throw _mollieConnectOauthError("missing_mollie_connect_state_secret");
  const raw = new TextEncoder().encode(normalized);
  return crypto.subtle.importKey(
    "raw",
    raw,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

export async function signMollieConnectOAuthState(payloadB64, secret) {
  const key = await _importMollieConnectHmacKey(secret);
  const data = new TextEncoder().encode(String(payloadB64 || ""));
  const signature = await crypto.subtle.sign("HMAC", key, data);
  return base64urlEncodeBytes(new Uint8Array(signature));
}

export async function verifyMollieConnectOAuthState(payloadB64, sigB64, secret) {
  const key = await _importMollieConnectHmacKey(secret);
  const data = new TextEncoder().encode(String(payloadB64 || ""));
  const sig = base64urlDecodeToBytes(sigB64);
  if (!sig.length) return false;
  return crypto.subtle.verify("HMAC", key, sig, data);
}

export async function buildSignedMollieConnectOAuthState(payloadObj, secret) {
  const payloadBase64 = jsonBase64urlEncode(payloadObj);
  const signatureBase64 = await signMollieConnectOAuthState(payloadBase64, secret);
  return `${payloadBase64}.${signatureBase64}`;
}

export async function parseAndVerifyMollieConnectOAuthState(state, secret) {
  const raw = String(state || "").trim();
  if (!raw) throw _mollieConnectOauthError("missing_state");
  const parts = raw.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw _mollieConnectOauthError("invalid_state_format");
  }
  const [payloadBase64, signatureBase64] = parts;
  const ok = await verifyMollieConnectOAuthState(payloadBase64, signatureBase64, secret);
  if (!ok) throw _mollieConnectOauthError("invalid_state_signature");
  const payload = jsonBase64urlDecode(payloadBase64);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw _mollieConnectOauthError("invalid_state_payload");
  }
  return { payloadBase64, signatureBase64, payload };
}

/* ===================== Token payload encryption (AES-GCM) ===================== */

export async function _importMollieConnectEncryptionKey(env) {
  const rawSecret = String(env?.MOLLIE_CONNECT_ENCRYPTION_KEY || "").trim();
  if (!rawSecret) throw _mollieConnectOauthError("missing_mollie_connect_encryption_key");
  const keyMaterial = new TextEncoder().encode(rawSecret);
  const digest = await crypto.subtle.digest("SHA-256", keyMaterial);
  return crypto.subtle.importKey(
    "raw",
    digest,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function encryptMollieConnectTokenPayload(payload, env) {
  const accessToken = safeStr(payload?.access_token ?? payload?.accessToken);
  const refreshToken = safeStr(payload?.refresh_token ?? payload?.refreshToken);
  if (!accessToken) throw _mollieConnectOauthError("missing_access_token");
  const kid = safeStr(env?.MOLLIE_CONNECT_ENCRYPTION_KID, 32) || "v1";
  const key = await _importMollieConnectEncryptionKey(env);

  async function encryptOne(tokenValue) {
    const token = String(tokenValue || "");
    if (!token) return null;
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const plaintext = new TextEncoder().encode(token);
    const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plaintext);
    return {
      alg: "AES-GCM",
      kid,
      iv: base64urlEncodeBytes(iv),
      ciphertext: base64urlEncodeBytes(new Uint8Array(encrypted)),
    };
  }

  const accessTokenEncrypted = await encryptOne(accessToken);
  const refreshTokenEncrypted = await encryptOne(refreshToken);
  return {
    accessTokenEncrypted,
    ...(refreshTokenEncrypted ? { refreshTokenEncrypted } : {}),
  };
}

export async function decryptMollieConnectTokenPayload(encryptedPayload, env) {
  if (!encryptedPayload || typeof encryptedPayload !== "object") {
    throw _mollieConnectOauthError("invalid_encrypted_token_payload");
  }
  const key = await _importMollieConnectEncryptionKey(env);

  async function decryptOne(encryptedObj) {
    if (!encryptedObj || typeof encryptedObj !== "object") return "";
    const alg = String(encryptedObj.alg || "").trim();
    if (alg !== "AES-GCM") throw _mollieConnectOauthError("unsupported_encrypted_token_alg");
    const iv = base64urlDecodeToBytes(encryptedObj.iv);
    const ciphertext = base64urlDecodeToBytes(encryptedObj.ciphertext);
    if (!iv.length || !ciphertext.length) {
      throw _mollieConnectOauthError("invalid_encrypted_token_blob");
    }
    const decrypted = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, ciphertext);
    return new TextDecoder().decode(new Uint8Array(decrypted));
  }

  const accessToken = await decryptOne(
    encryptedPayload.accessTokenEncrypted ?? encryptedPayload.access_token_encrypted,
  );
  const refreshToken = await decryptOne(
    encryptedPayload.refreshTokenEncrypted ?? encryptedPayload.refresh_token_encrypted,
  );
  return {
    access_token: safeStr(accessToken),
    refresh_token: safeStr(refreshToken),
  };
}

/* ===================== Nonce lifecycle ===================== */

export async function createMollieConnectOAuthNonce(env, scope) {
  if (!env?.BOOKING_KV) throw _mollieConnectOauthError("missing_booking_kv");
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) throw _mollieConnectOauthError("missing_tenant_scope");
  const nonce = (crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}_${Math.random()}`)
    .replace(/[^a-zA-Z0-9_-]+/g, "");
  const nowMs = Date.now();
  const expiresMs = nowMs + MOLLIE_CONNECT_OAUTH_NONCE_TTL_SECONDS * 1000;
  const key = buildScopedMollieConnectNonceKey(
    { tenant_id: tenantId, company_id: companyId },
    nonce,
  );
  if (!key) throw _mollieConnectOauthError("invalid_oauth_nonce_key");
  const record = {
    purpose: MOLLIE_CONNECT_OAUTH_STATE_PURPOSE,
    tenant_id: tenantId,
    company_id: companyId,
    nonce,
    issued_at: new Date(nowMs).toISOString(),
    expires_at: new Date(expiresMs).toISOString(),
    consumed: false,
  };
  await env.BOOKING_KV.put(key, JSON.stringify(record), {
    expirationTtl: MOLLIE_CONNECT_OAUTH_NONCE_TTL_SECONDS,
  });
  return {
    nonce,
    issuedAt: record.issued_at,
    expiresAt: record.expires_at,
    expiresIn: MOLLIE_CONNECT_OAUTH_NONCE_TTL_SECONDS,
    key,
  };
}

export async function consumeMollieConnectOAuthNonce(env, scope, nonce) {
  if (!env?.BOOKING_KV) {
    return { ok: false, code: "missing_booking_kv" };
  }
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const key = buildScopedMollieConnectNonceKey(
    { tenant_id: tenantId, company_id: companyId },
    nonce,
  );
  if (!key || !tenantId || !companyId) {
    return { ok: false, code: "invalid_nonce_scope" };
  }
  const rec = await env.BOOKING_KV.get(key, { type: "json" });
  if (!rec || typeof rec !== "object") {
    return { ok: false, code: "nonce_missing" };
  }
  if (String(rec?.purpose || "") !== MOLLIE_CONNECT_OAUTH_STATE_PURPOSE) {
    return { ok: false, code: "nonce_purpose_mismatch" };
  }
  if (
    sanitizeTenantString(rec?.tenant_id ?? rec?.tenantId, 80) !== tenantId ||
    sanitizeTenantString(rec?.company_id ?? rec?.companyId, 80) !== companyId
  ) {
    return { ok: false, code: "nonce_scope_mismatch" };
  }
  if (String(rec?.nonce || "").trim() !== String(nonce || "").trim()) {
    return { ok: false, code: "nonce_value_mismatch" };
  }
  if (rec?.consumed === true) {
    return { ok: false, code: "nonce_consumed" };
  }
  const expiresAt = Date.parse(String(rec?.expires_at || ""));
  if (!Number.isFinite(expiresAt) || Date.now() > expiresAt) {
    return { ok: false, code: "nonce_expired" };
  }
  await env.BOOKING_KV.delete(key);
  return { ok: true };
}

/* ===================== Auth record persistence ===================== */

export async function saveScopedMollieConnectAuthRecord(env, scope, nextRecord) {
  if (!env?.BOOKING_KV) throw _mollieConnectOauthError("missing_booking_kv");
  const scopedKey = buildScopedMollieConnectAuthKey(scope);
  if (!scopedKey) throw _mollieConnectOauthError("missing_tenant_scope");
  await env.BOOKING_KV.put(scopedKey, JSON.stringify(nextRecord));
  try {
    await persistPublicMollieConnectStatus(env, scope, nextRecord);
  } catch (_) {
    // Auth remains authoritative. Command Center reads the public snapshot only.
  }
  return { scopedKey };
}

export async function loadScopedMollieConnectAuthRecord(env, scope) {
  const scopedKey = buildScopedMollieConnectAuthKey(scope);
  if (!scopedKey || !env?.BOOKING_KV) return null;
  try {
    const raw = await env.BOOKING_KV.get(scopedKey, { type: "json" });
    if (!raw || typeof raw !== "object") return null;
    return raw.mollie_connect_auth && typeof raw.mollie_connect_auth === "object"
      ? raw.mollie_connect_auth
      : raw;
  } catch (_) {
    return null;
  }
}

export function sanitizeMollieConnectStatus(record, businessProfile) {
  const rec = record && typeof record === "object" ? record : {};
  const profile = businessProfile && typeof businessProfile === "object" ? businessProfile : {};
  const statusRaw = safeStr(rec.status, 64) || "not_configured";
  const statusLower = statusRaw.toLowerCase();
  const hasTokenMaterial = !!(
    (rec.accessTokenEncrypted && typeof rec.accessTokenEncrypted === "object") ||
    (rec.refreshTokenEncrypted && typeof rec.refreshTokenEncrypted === "object")
  );
  const profileConnected = boolish(profile.mollie_connected ?? profile.mollieConnected);
  const connected =
    rec.connected === true &&
    statusLower === "connected" &&
    hasTokenMaterial &&
    profileConnected;
  const reportedStatus =
    statusLower === "disconnected" || rec.connected === false
      ? "disconnected"
      : connected
        ? "connected"
        : statusRaw;
  return {
    connected,
    status: reportedStatus,
    mollie_organization_id:
      safeStr(
        rec.organizationId ??
          rec.organization_id ??
          profile.mollie_organization_id ??
          profile.mollieOrganizationId,
        80,
      ) || null,
    mollie_profile_id:
      safeStr(
        rec.profileId ??
          rec.profile_id ??
          profile.mollie_profile_id ??
          profile.mollieProfileId,
        80,
      ) || null,
    mollie_mode: (() => {
      const mode = safeStr(rec.mollie_mode ?? rec.mollieMode, 16).toLowerCase();
      return mode === "test" || mode === "live" ? mode : "unknown";
    })(),
    onboarding_status:
      safeStr(rec.onboardingStatus ?? rec.onboarding_status, 64) || null,
    // MOLLIE-ONBOARDING-STATUS-P1: authoritative "can this organization
    // receive payments right now" signal from Mollie's onboarding resource.
    // `null` means it has never been captured (legacy record, pre-fix) —
    // callers must treat that as "unknown", never as false.
    can_receive_payments: (() => {
      const raw = rec.canReceivePayments ?? rec.can_receive_payments;
      return typeof raw === "boolean" ? raw : null;
    })(),
    last_connected_at:
      safeStr(rec.lastConnectedAt ?? rec.last_connected_at, 64) || null,
    updated_at: safeStr(rec.updatedAt ?? rec.updated_at, 64) || null,
    last_error_code: safeStr(rec.lastErrorCode ?? rec.last_error_code, 120) || null,
    // Diagnostics for the most recent LIVE re-verification attempt (distinct
    // from lastErrorCode, which is about the OAuth connection itself). A
    // transient failure here must never overwrite onboarding_status /
    // can_receive_payments — see refreshMollieOnboardingCapabilityStatus.
    last_status_check_error:
      safeStr(rec.lastStatusCheckError ?? rec.last_status_check_error, 120) || null,
    last_status_checked_at:
      safeStr(rec.lastStatusCheckedAt ?? rec.last_status_checked_at, 64) || null,
    // MOLLIE-ONBOARDING-READ-SCOPE-P0-1: granted OAuth scopes when captured.
    // Legacy records without this field keep `oauth_scopes: null` /
    // `onboarding_read_granted: null` (unknown — not false).
    oauth_scopes: (() => {
      const normalized = normalizeMollieConnectGrantedScopes(
        rec.oauthScopes ?? rec.oauth_scopes,
      );
      return normalized || null;
    })(),
    onboarding_read_granted: (() => {
      const raw = rec.oauthScopes ?? rec.oauth_scopes;
      if (!safeStr(raw, 800)) return null;
      return mollieConnectGrantedScopesInclude(
        raw,
        MOLLIE_CONNECT_ONBOARDING_READ_SCOPE,
      );
    })(),
  };
}

export function hasSuccessfulMollieConnectRecord(record) {
  if (!record || typeof record !== "object") return false;
  const status = safeStr(record.status, 64).toLowerCase();
  if (record.connected === true || status === "connected") return true;
  const lastConnectedAt = safeStr(record.lastConnectedAt ?? record.last_connected_at, 64);
  const organizationId = safeStr(record.organizationId ?? record.organization_id, 80);
  const profileId = safeStr(record.profileId ?? record.profile_id, 80);
  const hasTokenMaterial = !!(
    (record.accessTokenEncrypted && typeof record.accessTokenEncrypted === "object") ||
    (record.refreshTokenEncrypted && typeof record.refreshTokenEncrypted === "object")
  );
  return !!lastConnectedAt && hasTokenMaterial && (!!organizationId || !!profileId);
}

export async function saveScopedMollieConnectAuthFailureStatus(
  env,
  scope,
  { status = "failed", errorCode = "mollie_connect_callback_failed" } = {},
) {
  if (!env?.BOOKING_KV) return;
  const scopedKey = buildScopedMollieConnectAuthKey(scope);
  if (!scopedKey) return;
  const nowIso = new Date().toISOString();
  const existing = await loadScopedMollieConnectAuthRecord(env, scope);
  const safeErrorCode = String(errorCode || "mollie_connect_callback_failed");
  const safeFailureStatus = String(status || "failed");
  if (hasSuccessfulMollieConnectRecord(existing)) {
    const existingStatus = safeStr(existing.status, 64).toLowerCase();
    const next = {
      ...existing,
      connected: true,
      status: existingStatus === "connected" ? safeStr(existing.status, 64) : "connected",
      tokenRef: safeStr(existing.tokenRef ?? existing.token_ref, 512) || scopedKey,
      lastErrorCode: safeErrorCode,
      last_error_code: safeErrorCode,
      lastErrorAt: nowIso,
      last_error_at: nowIso,
      lastFailedAt: nowIso,
      last_failed_at: nowIso,
      lastFailureStatus: safeFailureStatus,
      last_failure_status: safeFailureStatus,
      lastCallbackErrorCode: safeErrorCode,
      last_callback_error_code: safeErrorCode,
      updatedAt: nowIso,
      updated_at: nowIso,
    };
    await env.BOOKING_KV.put(scopedKey, JSON.stringify(next));
    return;
  }
  const next = {
    version: 1,
    connected: false,
    status: safeFailureStatus,
    organizationId: safeStr(existing?.organizationId ?? existing?.organization_id, 80) || null,
    profileId: safeStr(existing?.profileId ?? existing?.profile_id, 80) || null,
    mollie_mode: safeStr(existing?.mollie_mode ?? existing?.mollieMode, 16) || "unknown",
    onboardingStatus: safeStr(existing?.onboardingStatus ?? existing?.onboarding_status, 64) || null,
    accessTokenEncrypted:
      existing?.accessTokenEncrypted && typeof existing.accessTokenEncrypted === "object"
        ? existing.accessTokenEncrypted
        : null,
    refreshTokenEncrypted:
      existing?.refreshTokenEncrypted && typeof existing.refreshTokenEncrypted === "object"
        ? existing.refreshTokenEncrypted
        : null,
    tokenRef: scopedKey,
    lastConnectedAt: safeStr(existing?.lastConnectedAt ?? existing?.last_connected_at, 64) || null,
    lastErrorCode: safeErrorCode,
    lastErrorAt: nowIso,
    lastFailedAt: nowIso,
    lastFailureStatus: safeFailureStatus,
    lastCallbackErrorCode: safeErrorCode,
    createdAt: safeStr(existing?.createdAt ?? existing?.created_at, 64) || nowIso,
    updatedAt: nowIso,
  };
  await env.BOOKING_KV.put(scopedKey, JSON.stringify(next));
}

/* ===================== OAuth token exchange + metadata ===================== */

export async function exchangeMollieConnectCodeForTokens({
  code,
  clientId,
  clientSecret,
  redirectUri,
}) {
  const tokenUrl = "https://api.mollie.com/oauth2/tokens";
  const credentials = `${String(clientId || "").trim()}:${String(clientSecret || "").trim()}`;
  const basic = btoa(credentials);
  const form = new URLSearchParams();
  form.set("grant_type", "authorization_code");
  form.set("code", String(code || "").trim());
  form.set("redirect_uri", String(redirectUri || "").trim());
  const res = await fetch(tokenUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      Authorization: `Basic ${basic}`,
    },
    body: form.toString(),
  });
  const txt = await res.text();
  let parsed = null;
  try {
    parsed = JSON.parse(txt);
  } catch (_) {}
  if (!res.ok) {
    const errCode = safeStr(parsed?.error, 64) || "mollie_token_exchange_failed";
    throw _mollieConnectOauthError(errCode);
  }
  return parsed && typeof parsed === "object" ? parsed : {};
}

// MOLLIE-ONBOARDING-STATUS-P1: onboarding status + "can receive payments" are
// NOT fields on /v2/organizations/me (that endpoint has no onboarding data at
// all — organizations have no `status` field). The Mollie API only exposes
// this via the dedicated Onboarding resource: GET /v2/onboarding/me, whose
// `status` is one of `needs-data` / `in-review` / `completed`, alongside an
// authoritative `canReceivePayments` boolean. Reading the wrong endpoint here
// previously meant `onboardingStatus` was always null, forever, for every
// company, and the account-level UI could never distinguish "genuinely still
// under review" from "review complete but nothing receivable yet" from
// "fully active" — see MOLLIE-ONBOARDING-STATUS-P1 root-cause report.
//
// Central capability-status adapter: keep ALL Mollie capability/onboarding
// lookups behind this helper so a future migration is isolated here.
// TODO(MOLLIE-ONBOARDING-STATUS-P1): Migrate onboarding capability lookup to
// Mollie Capabilities API after its contract is stable and before the
// Onboarding API is retired. Do not broaden call sites until then.
export async function fetchMollieOnboardingStatus(accessToken) {
  const token = safeStr(accessToken);
  if (!token) {
    return {
      ok: false,
      onboardingStatus: null,
      canReceivePayments: null,
      upstream_http_status: null,
      mollie_error_type: null,
      mollie_error_code: "empty_access_token",
      response_shape: "empty_token",
    };
  }
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
  };
  try {
    const res = await fetch("https://api.mollie.com/v2/onboarding/me", { headers });
    const upstreamHttpStatus = Number(res.status) || null;
    if (!res.ok) {
      let mollieErrorType = null;
      let mollieErrorCode = null;
      try {
        const errBody = await res.json();
        mollieErrorType = _sanitizeMollieLiveStatusDiagType(errBody?.type);
        mollieErrorCode =
          _sanitizeMollieLiveStatusDiagCode(errBody?.code) ||
          (Number.isFinite(Number(errBody?.status))
            ? String(Math.trunc(Number(errBody.status)))
            : null) ||
          (upstreamHttpStatus != null ? String(upstreamHttpStatus) : null);
      } catch (_) {
        mollieErrorCode =
          upstreamHttpStatus != null ? String(upstreamHttpStatus) : null;
      }
      return {
        ok: false,
        onboardingStatus: null,
        canReceivePayments: null,
        upstream_http_status: upstreamHttpStatus,
        mollie_error_type: mollieErrorType,
        mollie_error_code: mollieErrorCode,
        response_shape: "http_error",
      };
    }
    let onboarding = null;
    try {
      onboarding = await res.json();
    } catch (_) {
      return {
        ok: false,
        onboardingStatus: null,
        canReceivePayments: null,
        upstream_http_status: upstreamHttpStatus,
        mollie_error_type: null,
        mollie_error_code: "invalid_json",
        response_shape: "json_parse_error",
      };
    }
    const onboardingStatus = safeStr(onboarding?.status, 64) || null;
    const canReceivePaymentsRaw =
      onboarding?.canReceivePayments ?? onboarding?.can_receive_payments;
    const canReceivePayments =
      typeof canReceivePaymentsRaw === "boolean" ? canReceivePaymentsRaw : null;
    return {
      ok: true,
      onboardingStatus,
      canReceivePayments,
      upstream_http_status: upstreamHttpStatus,
      mollie_error_type: null,
      mollie_error_code: null,
      response_shape: _classifyMollieOnboardingResponseShape({
        ok: true,
        onboardingStatus,
        canReceivePayments,
        upstreamHttpStatus,
      }),
    };
  } catch (_) {
    return {
      ok: false,
      onboardingStatus: null,
      canReceivePayments: null,
      upstream_http_status: null,
      mollie_error_type: null,
      mollie_error_code: "network_error",
      response_shape: "network_error",
    };
  }
}

export async function fetchMollieConnectAccountMetadata(accessToken) {
  const token = safeStr(accessToken);
  if (!token) {
    return {
      organizationId: "",
      profileId: "",
      mollieMode: "unknown",
      onboardingStatus: null,
      canReceivePayments: null,
    };
  }
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
  };
  let organizationId = "";
  try {
    const orgRes = await fetch("https://api.mollie.com/v2/organizations/me", { headers });
    if (orgRes.ok) {
      const org = await orgRes.json();
      organizationId = safeStr(org?.id, 80);
    }
  } catch (_) {
    // Best-effort metadata only.
  }
  let profileId = "";
  let mollieMode = "unknown";
  try {
    const profileRes = await fetch("https://api.mollie.com/v2/profiles?limit=5", { headers });
    if (profileRes.ok) {
      const profilePage = await profileRes.json();
      const profiles = profilePage?._embedded?.profiles;
      if (Array.isArray(profiles) && profiles.length) {
        const primary =
          profiles.find((p) => safeStr(p?.status, 32).toLowerCase() === "verified") ||
          profiles[0];
        profileId = safeStr(primary?.id, 80);
        const mode = safeStr(primary?.mode, 16).toLowerCase();
        if (mode === "test" || mode === "live") mollieMode = mode;
      }
    }
  } catch (_) {
    // Best-effort metadata only.
  }
  const onboarding = await fetchMollieOnboardingStatus(token);
  return {
    organizationId,
    profileId,
    mollieMode,
    onboardingStatus: onboarding.onboardingStatus,
    canReceivePayments: onboarding.canReceivePayments,
  };
}

/* ===================== Access token expiry + refresh ===================== */

export function _isMollieConnectAccessTokenExpired(record, nowMs = Date.now()) {
  if (!record || typeof record !== "object") return true;
  const expiresAtRaw = safeStr(record.expiresAt ?? record.expires_at);
  if (!expiresAtRaw) return false;
  const t = Date.parse(expiresAtRaw);
  if (!Number.isFinite(t)) return false;
  return nowMs + MOLLIE_CONNECT_TOKEN_REFRESH_LEEWAY_MS >= t;
}

export async function refreshMollieConnectTokens(env, scope, existingRecord, options = {}) {
  const diag =
    options?.diag && typeof options.diag.emit === "function" ? options.diag : null;
  const tokenFlags = _mollieConnectRecordTokenDiagFlags(existingRecord);
  const fail = (code, extra = {}) => {
    diag?.emit("token_refresh_failed", {
      upstream_endpoint_name: "oauth2_tokens",
      mollie_error_code: _sanitizeMollieLiveStatusDiagCode(code) || "company_mollie_token_refresh_failed",
      token_refresh_attempted: true,
      ...tokenFlags,
      ...extra,
    });
    return { ok: false, code };
  };
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) {
    return fail("missing_tenant_scope");
  }
  if (!existingRecord || typeof existingRecord !== "object") {
    return fail("company_mollie_token_missing");
  }
  diag?.emit("token_refresh_started", {
    upstream_endpoint_name: "oauth2_tokens",
    token_refresh_attempted: true,
    ...tokenFlags,
  });
  const clientId = safeStr(env?.MOLLIE_CONNECT_CLIENT_ID);
  const clientSecret = safeStr(env?.MOLLIE_CONNECT_CLIENT_SECRET);
  if (!clientId || !clientSecret) {
    return fail("missing_mollie_connect_client_config");
  }
  const encryptedRefresh =
    existingRecord.refreshTokenEncrypted ?? existingRecord.refresh_token_encrypted;
  if (!encryptedRefresh || typeof encryptedRefresh !== "object") {
    return fail("company_mollie_token_missing");
  }
  let decrypted;
  try {
    decrypted = await decryptMollieConnectTokenPayload(
      { refreshTokenEncrypted: encryptedRefresh },
      env,
    );
  } catch (_) {
    return fail("company_mollie_token_refresh_failed");
  }
  const refreshTokenPlain = safeStr(decrypted?.refresh_token);
  if (!refreshTokenPlain) {
    return fail("company_mollie_token_missing");
  }
  const basic = btoa(`${clientId}:${clientSecret}`);
  const form = new URLSearchParams();
  form.set("grant_type", "refresh_token");
  form.set("refresh_token", refreshTokenPlain);
  let res;
  try {
    res = await fetch("https://api.mollie.com/oauth2/tokens", {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Authorization: `Basic ${basic}`,
      },
      body: form.toString(),
    });
  } catch (_) {
    return fail("company_mollie_token_refresh_failed", {
      response_shape: "network_error",
    });
  }
  if (!res.ok) {
    return fail("company_mollie_token_refresh_failed", {
      upstream_http_status: Number(res.status) || undefined,
      response_shape: "http_error",
    });
  }
  let tokens = null;
  try {
    tokens = await res.json();
  } catch (_) {
    return fail("company_mollie_token_refresh_failed", {
      upstream_http_status: Number(res.status) || undefined,
      response_shape: "json_parse_error",
    });
  }
  const newAccessToken = safeStr(tokens?.access_token);
  if (!newAccessToken) {
    return fail("company_mollie_token_refresh_failed", {
      upstream_http_status: Number(res.status) || undefined,
      response_shape: "token_response_empty",
    });
  }
  const newRefreshTokenRaw = safeStr(tokens?.refresh_token);
  const newRefreshToken = newRefreshTokenRaw || refreshTokenPlain;
  let encryptedTokens;
  try {
    encryptedTokens = await encryptMollieConnectTokenPayload(
      { access_token: newAccessToken, refresh_token: newRefreshToken },
      env,
    );
  } catch (_) {
    return fail("company_mollie_token_refresh_failed");
  }
  const expiresInSec = Number(tokens?.expires_in);
  const nowMs = Date.now();
  const expiresAt =
    Number.isFinite(expiresInSec) && expiresInSec > 0
      ? new Date(nowMs + expiresInSec * 1000).toISOString()
      : null;
  const nowIso = new Date(nowMs).toISOString();
  const grantedScopes = normalizeMollieConnectGrantedScopes(tokens?.scope);
  const updatedRecord = {
    ...existingRecord,
    accessTokenEncrypted: encryptedTokens.accessTokenEncrypted,
    ...(encryptedTokens.refreshTokenEncrypted
      ? { refreshTokenEncrypted: encryptedTokens.refreshTokenEncrypted }
      : {}),
    ...(grantedScopes
      ? { oauthScopes: grantedScopes, oauth_scopes: grantedScopes }
      : {}),
    expiresAt,
    expires_at: expiresAt,
    updatedAt: nowIso,
    updated_at: nowIso,
  };
  try {
    await saveScopedMollieConnectAuthRecord(
      env,
      { tenant_id: tenantId, company_id: companyId },
      updatedRecord,
    );
  } catch (_) {
    return fail("company_mollie_token_refresh_failed");
  }
  diag?.emit("token_refresh_completed", {
    upstream_endpoint_name: "oauth2_tokens",
    upstream_http_status: Number(res.status) || 200,
    token_refresh_attempted: true,
    token_present: true,
    refresh_token_present: true,
    token_expired: false,
  });
  return {
    ok: true,
    record: updatedRecord,
    accessToken: newAccessToken,
  };
}

export async function resolveCompanyMollieConnectCredentials(env, scope, _options = {}) {
  const diag =
    _options?.diag && typeof _options.diag.emit === "function" ? _options.diag : null;
  let tokenRefreshAttempted = false;
  const fail = (error, extra = {}) => {
    diag?.emit("credential_resolve_failed", {
      mollie_error_code:
        _sanitizeMollieLiveStatusDiagCode(error) ||
        "company_mollie_credentials_unavailable",
      token_refresh_attempted: tokenRefreshAttempted,
      ...extra,
    });
    return { ok: false, error, token_refresh_attempted: tokenRefreshAttempted };
  };
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) {
    return fail("company_mollie_credentials_unavailable");
  }
  diag?.emit("credential_resolve_started", {
    token_refresh_attempted: false,
  });
  const scopedState = { tenant_id: tenantId, company_id: companyId };
  let record = null;
  try {
    record = await loadScopedMollieConnectAuthRecord(env, scopedState);
  } catch (_) {
    record = null;
  }
  if (!record || typeof record !== "object") {
    return fail("company_mollie_not_connected");
  }
  const tokenFlags = _mollieConnectRecordTokenDiagFlags(record);
  const statusLower = safeStr(record.status, 32).toLowerCase();
  if (record.connected !== true || statusLower !== "connected") {
    return fail("company_mollie_not_connected", tokenFlags);
  }
  const encryptedAccess = record.accessTokenEncrypted ?? record.access_token_encrypted;
  const encryptedRefresh = record.refreshTokenEncrypted ?? record.refresh_token_encrypted;
  if (
    !encryptedAccess ||
    typeof encryptedAccess !== "object" ||
    !encryptedRefresh ||
    typeof encryptedRefresh !== "object"
  ) {
    return fail("company_mollie_token_missing", tokenFlags);
  }

  let workingRecord = record;
  let accessTokenPlain = "";

  if (_isMollieConnectAccessTokenExpired(workingRecord)) {
    tokenRefreshAttempted = true;
    const refreshed = await refreshMollieConnectTokens(env, scopedState, workingRecord, {
      diag,
    });
    if (!refreshed?.ok) {
      return fail("company_mollie_token_refresh_failed", {
        ..._mollieConnectRecordTokenDiagFlags(workingRecord),
      });
    }
    workingRecord = refreshed.record;
    accessTokenPlain = safeStr(refreshed.accessToken);
  } else {
    try {
      const decrypted = await decryptMollieConnectTokenPayload(
        { accessTokenEncrypted: encryptedAccess },
        env,
      );
      accessTokenPlain = safeStr(decrypted?.access_token);
    } catch (_) {
      accessTokenPlain = "";
    }
    if (!accessTokenPlain) {
      tokenRefreshAttempted = true;
      const refreshed = await refreshMollieConnectTokens(env, scopedState, workingRecord, {
        diag,
      });
      if (!refreshed?.ok) {
        return fail("company_mollie_token_refresh_failed", {
          ..._mollieConnectRecordTokenDiagFlags(workingRecord),
        });
      }
      workingRecord = refreshed.record;
      accessTokenPlain = safeStr(refreshed.accessToken);
    }
  }

  if (!accessTokenPlain) {
    return fail("company_mollie_credentials_unavailable", {
      ..._mollieConnectRecordTokenDiagFlags(workingRecord),
    });
  }

  const modeRaw = safeStr(
    workingRecord.mollie_mode ?? workingRecord.mollieMode,
    16,
  ).toLowerCase();
  const mode = modeRaw === "test" || modeRaw === "live" ? modeRaw : "unknown";
  diag?.emit("credential_resolve_completed", {
    token_present: true,
    refresh_token_present: true,
    token_expired: false,
    token_refresh_attempted: tokenRefreshAttempted,
  });
  return {
    ok: true,
    apiKey: accessTokenPlain,
    keyKind: "oauth",
    mode,
    payment_owner_mode: "company_mollie",
    payment_credential_source: "company_mollie",
    payment_company_id: companyId,
    payment_demo_mode: false,
    token_refresh_attempted: tokenRefreshAttempted,
    mollie_organization_id:
      safeStr(workingRecord.organizationId ?? workingRecord.organization_id, 80) || null,
    mollie_profile_id:
      safeStr(workingRecord.profileId ?? workingRecord.profile_id, 80) || null,
  };
}

/* ===================== Onboarding/capability live refresh ===================== */

// MOLLIE-LIVE-STATUS-DIAGNOSTICS-P0-1: structured, sanitized stage events for
// GET /admin/mollie/connect/status?refresh=live. Never logs tokens, auth
// headers, company/org/profile/payment IDs, or upstream bodies.
const MOLLIE_LIVE_STATUS_DIAG_ALLOWED_KEYS = new Set([
  "stage",
  "auth_mode",
  "correlation_id",
  "upstream_endpoint_name",
  "upstream_http_status",
  "mollie_error_type",
  "mollie_error_code",
  "token_present",
  "refresh_token_present",
  "token_expired",
  "token_refresh_attempted",
  "response_shape",
  "can_receive_payments",
  "status_check",
  "duration_ms",
]);

const MOLLIE_LIVE_STATUS_SANITIZED_CODE_RE = /^[a-z0-9][a-z0-9_.-]{0,79}$/i;

export function _sanitizeMollieLiveStatusDiagCode(value) {
  const raw = safeStr(value, 80).trim();
  if (!raw) return null;
  if (!MOLLIE_LIVE_STATUS_SANITIZED_CODE_RE.test(raw)) return null;
  return raw.slice(0, 80);
}

export function _sanitizeMollieLiveStatusDiagType(value) {
  const raw = safeStr(value, 200).trim();
  if (!raw) return null;
  // Mollie `type` is often a docs URL — keep only the last path segment.
  const segment = raw.includes("/")
    ? raw.split("/").filter(Boolean).pop()
    : raw;
  return _sanitizeMollieLiveStatusDiagCode(segment);
}

export function logMollieLiveStatusDiag(fields = {}) {
  const src = fields && typeof fields === "object" ? fields : {};
  const out = {};
  for (const key of MOLLIE_LIVE_STATUS_DIAG_ALLOWED_KEYS) {
    if (!(key in src)) continue;
    const value = src[key];
    if (value === undefined) continue;
    if (
      key === "mollie_error_type" ||
      key === "mollie_error_code" ||
      key === "response_shape" ||
      key === "stage" ||
      key === "auth_mode" ||
      key === "correlation_id" ||
      key === "upstream_endpoint_name" ||
      key === "status_check"
    ) {
      const sanitized =
        key === "mollie_error_type"
          ? _sanitizeMollieLiveStatusDiagType(value)
          : key === "mollie_error_code" || key === "response_shape" || key === "stage"
            ? _sanitizeMollieLiveStatusDiagCode(value)
            : safeStr(value, 80) || null;
      if (sanitized != null && sanitized !== "") out[key] = sanitized;
      continue;
    }
    if (
      key === "token_present" ||
      key === "refresh_token_present" ||
      key === "token_expired" ||
      key === "token_refresh_attempted" ||
      key === "can_receive_payments"
    ) {
      if (typeof value === "boolean") out[key] = value;
      continue;
    }
    if (key === "upstream_http_status" || key === "duration_ms") {
      const n = Number(value);
      if (Number.isFinite(n) && n >= 0) out[key] = Math.trunc(n);
      continue;
    }
  }
  if (!out.stage) return;
  console.log(`[MOLLIE_LIVE_STATUS] ${JSON.stringify(out)}`);
}

export function createMollieLiveStatusDiag({
  authMode = null,
  correlationId = null,
} = {}) {
  const startedAt = Date.now();
  const correlation_id =
    safeStr(correlationId, 80) ||
    (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function"
      ? crypto.randomUUID()
      : `mls_${Date.now().toString(36)}`);
  const auth_mode = safeStr(authMode, 40) || null;
  return {
    correlation_id,
    auth_mode,
    startedAt,
    emit(stage, fields = {}) {
      logMollieLiveStatusDiag({
        auth_mode,
        correlation_id,
        ...(fields && typeof fields === "object" ? fields : {}),
        stage,
        duration_ms:
          fields?.duration_ms != null
            ? fields.duration_ms
            : Math.max(0, Date.now() - startedAt),
      });
    },
  };
}

function _mollieConnectRecordTokenDiagFlags(record) {
  const encryptedAccess =
    record?.accessTokenEncrypted ?? record?.access_token_encrypted;
  const encryptedRefresh =
    record?.refreshTokenEncrypted ?? record?.refresh_token_encrypted;
  return {
    token_present: !!(encryptedAccess && typeof encryptedAccess === "object"),
    refresh_token_present: !!(
      encryptedRefresh && typeof encryptedRefresh === "object"
    ),
    token_expired: _isMollieConnectAccessTokenExpired(record),
  };
}

function _classifyMollieOnboardingResponseShape({
  ok,
  onboardingStatus,
  canReceivePayments,
  upstreamHttpStatus,
  networkError,
} = {}) {
  if (networkError) return "network_error";
  if (upstreamHttpStatus != null && upstreamHttpStatus !== 200) {
    return "http_error";
  }
  if (!ok) return "lookup_failed";
  if (typeof canReceivePayments === "boolean" && onboardingStatus) {
    return "onboarding_me_status_bool";
  }
  if (onboardingStatus || typeof canReceivePayments === "boolean") {
    return "onboarding_me_partial";
  }
  return "onboarding_me_empty";
}

// MOLLIE-ONBOARDING-STATUS-P1: "Refresh status" in the UI previously just
// re-read the same cached KV record — it never asked Mollie anything, so a
// stale/incorrect onboarding_status (e.g. captured once, wrongly, at connect
// time) could never self-heal no matter how many times the merchant clicked
// refresh. This performs a real, read-only re-check against Mollie's
// Onboarding API and persists the result, WITHOUT touching credentials,
// OAuth tokens, the webhook, or the payment flow.
//
// On success: persists the fresh onboarding_status/can_receive_payments and
// clears any prior status-check error.
// On failure (network/API error, not "not connected"): persists ONLY a
// last_status_check_error/last_status_checked_at pair and explicitly leaves
// onboarding_status/can_receive_payments untouched, so a transient failure
// can never downgrade an already-confirmed active account.
export async function refreshMollieOnboardingCapabilityStatus(env, scope, options = {}) {
  const diag =
    options?.diag && typeof options.diag.emit === "function" ? options.diag : null;
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) {
    diag?.emit("live_status_failed", {
      status_check: "failed",
      mollie_error_code: "missing_tenant_scope",
    });
    return { ok: false, code: "missing_tenant_scope" };
  }
  const scopedState = { tenant_id: tenantId, company_id: companyId };
  const credentials = await resolveCompanyMollieConnectCredentials(env, scopedState, {
    purpose: "onboarding_status_refresh",
    diag,
  });
  if (!credentials?.ok) {
    // Not connected / no usable token at all — not a "lookup failure" in the
    // live-check sense, the caller already knows the account isn't
    // connected from the base status record.
    const code =
      _sanitizeMollieLiveStatusDiagCode(
        credentials?.error || "company_mollie_credentials_unavailable",
      ) || "company_mollie_credentials_unavailable";
    diag?.emit("live_status_failed", {
      status_check: "failed",
      mollie_error_code: code,
      token_refresh_attempted: !!credentials?.token_refresh_attempted,
    });
    return { ok: false, code };
  }
  diag?.emit("mollie_status_request_started", {
    upstream_endpoint_name: "onboarding_me",
    token_present: true,
    token_refresh_attempted: !!credentials.token_refresh_attempted,
  });
  const onboarding = await fetchMollieOnboardingStatus(credentials.apiKey);
  const nowIso = new Date().toISOString();
  const existing = await loadScopedMollieConnectAuthRecord(env, scopedState);
  if (!existing || typeof existing !== "object") {
    diag?.emit("live_status_failed", {
      status_check: "failed",
      mollie_error_code: "company_mollie_not_connected",
      upstream_endpoint_name: "onboarding_me",
      upstream_http_status: onboarding.upstream_http_status ?? undefined,
      response_shape: onboarding.response_shape || undefined,
    });
    return { ok: false, code: "company_mollie_not_connected" };
  }
  if (!onboarding.ok) {
    // MOLLIE-ONBOARDING-READ-SCOPE-P0-1: HTTP 403 from onboarding/me is the
    // proven missing-scope case (onboarding.read). Preserve confirmed
    // onboarding/can_receive_payments; map to a distinct canonical code.
    const failureCode =
      onboarding.upstream_http_status === 403
        ? "mollie_onboarding_permission_missing"
        : "mollie_onboarding_lookup_failed";
    diag?.emit("mollie_status_request_failed", {
      upstream_endpoint_name: "onboarding_me",
      upstream_http_status: onboarding.upstream_http_status ?? undefined,
      mollie_error_type: onboarding.mollie_error_type || undefined,
      mollie_error_code: onboarding.mollie_error_code || failureCode,
      response_shape: onboarding.response_shape || "lookup_failed",
      token_refresh_attempted: !!credentials.token_refresh_attempted,
    });
    const nextOnFailure = {
      ...existing,
      lastStatusCheckError: failureCode,
      last_status_check_error: failureCode,
      lastStatusCheckedAt: nowIso,
      last_status_checked_at: nowIso,
    };
    try {
      await saveScopedMollieConnectAuthRecord(env, scopedState, nextOnFailure);
    } catch (_) {
      // Best-effort persistence of the failure marker only; the in-memory
      // record below is still returned so the caller can render truthfully.
    }
    diag?.emit("live_status_failed", {
      status_check: "failed",
      mollie_error_code: failureCode,
      upstream_endpoint_name: "onboarding_me",
      upstream_http_status: onboarding.upstream_http_status ?? undefined,
      mollie_error_type: onboarding.mollie_error_type || undefined,
      response_shape: onboarding.response_shape || "lookup_failed",
      can_receive_payments:
        typeof existing.canReceivePayments === "boolean"
          ? existing.canReceivePayments
          : typeof existing.can_receive_payments === "boolean"
            ? existing.can_receive_payments
            : undefined,
      token_refresh_attempted: !!credentials.token_refresh_attempted,
    });
    return { ok: false, code: failureCode, record: nextOnFailure };
  }
  diag?.emit("mollie_status_response_received", {
    upstream_endpoint_name: "onboarding_me",
    upstream_http_status: onboarding.upstream_http_status ?? 200,
    response_shape: onboarding.response_shape || "onboarding_me_status_bool",
    can_receive_payments:
      typeof onboarding.canReceivePayments === "boolean"
        ? onboarding.canReceivePayments
        : undefined,
    token_refresh_attempted: !!credentials.token_refresh_attempted,
  });
  diag?.emit("response_mapping_started", {
    upstream_endpoint_name: "onboarding_me",
    response_shape: onboarding.response_shape || undefined,
  });
  const nextOnSuccess = {
    ...existing,
    onboardingStatus: onboarding.onboardingStatus,
    onboarding_status: onboarding.onboardingStatus,
    canReceivePayments: onboarding.canReceivePayments,
    can_receive_payments: onboarding.canReceivePayments,
    lastStatusCheckError: null,
    last_status_check_error: null,
    lastStatusCheckedAt: nowIso,
    last_status_checked_at: nowIso,
  };
  await saveScopedMollieConnectAuthRecord(env, scopedState, nextOnSuccess);
  diag?.emit("response_mapping_completed", {
    response_shape: onboarding.response_shape || undefined,
    can_receive_payments:
      typeof onboarding.canReceivePayments === "boolean"
        ? onboarding.canReceivePayments
        : undefined,
  });
  diag?.emit("live_status_succeeded", {
    status_check: "ok",
    upstream_endpoint_name: "onboarding_me",
    upstream_http_status: onboarding.upstream_http_status ?? 200,
    response_shape: onboarding.response_shape || undefined,
    can_receive_payments:
      typeof onboarding.canReceivePayments === "boolean"
        ? onboarding.canReceivePayments
        : undefined,
    token_refresh_attempted: !!credentials.token_refresh_attempted,
  });
  return { ok: true, record: nextOnSuccess };
}

/* ===================== Terminal snapshot helpers ===================== */

export function _sanitizeMollieTerminalForSnapshot(terminal = {}) {
  const source = terminal && typeof terminal === "object" ? terminal : {};
  const profileId =
    safeStr(
      source.profile_id ??
        source.profileId ??
        source.profile?.id ??
        source.profile?.profile_id ??
        source.profile?.profileId,
      80,
    ) || null;
  const forgotten =
    source.forgotten === true ||
    source.forgotten === "true" ||
    source.removed_from_fluxidi === true ||
    source.removedFromFluxidi === true;
  const excluded =
    forgotten ||
    source.excluded === true ||
    source.excluded === "true" ||
    source.linked === false ||
    source.linked === "false";
  const out = {
    id: safeStr(source.id, 80),
    description:
      safeStr(source.description ?? source.name ?? source.alias, 160) || null,
    status: safeStr(source.status, 64) || null,
    brand: safeStr(source.brand, 80) || null,
    model: safeStr(source.model, 80) || null,
    serial_number:
      safeStr(source.serial_number ?? source.serialNumber, 120) || null,
    currency: safeStr(source.currency, 8) || null,
    profile_id: profileId,
    created_at: safeStr(source.created_at ?? source.createdAt, 80) || null,
    updated_at: safeStr(source.updated_at ?? source.updatedAt, 80) || null,
    // Fluxidi link/exclusion/forget (not Mollie provider DELETE).
    linked: excluded ? false : true,
    excluded: !!excluded,
    forgotten: !!forgotten,
    excluded_at: safeStr(source.excluded_at ?? source.excludedAt, 80) || null,
    forgotten_at: safeStr(source.forgotten_at ?? source.forgottenAt, 80) || null,
  };
  return out;
}

export function _mollieTerminalsScopeMissingFromResponse(status, payload = {}, text = "") {
  const haystack = [
    status,
    payload?.status,
    payload?.code,
    payload?.error,
    payload?.title,
    payload?.detail,
    payload?.message,
    text,
  ]
    .map((v) => safeStr(v, 500).toLowerCase())
    .filter(Boolean)
    .join(" ");
  return (
    haystack.includes("terminals.read") ||
    haystack.includes("insufficient_scope") ||
    haystack.includes("missing scope") ||
    haystack.includes("permission") ||
    haystack.includes("not authorized")
  );
}

/* ===================== POS terminal (admin) helpers ===================== */

export function _adminPosTerminalError(error, status = 400, extra = {}) {
  const code = safeStr(error, 80) || "mollie_terminal_payment_create_failed";
  return json({ ok: false, error: code, code, ...extra }, status);
}

export function _sanitizeAdminPosTerminalDescription(value) {
  const text = safeStr(value, 140).trim();
  return text || "Fluxidi terminal test payment";
}

export function _adminPosTerminalIntentKeyValue({ tenantId, companyId, bookingId, terminalId } = {}) {
  return [
    safeStr(tenantId, 80),
    safeStr(companyId, 80),
    safeStr(bookingId, 160),
    safeStr(terminalId, 120),
  ].join(":");
}

export function _adminPosTerminalResponseTerminal(terminal = {}) {
  return {
    id: safeStr(terminal.id, 80),
    description: safeStr(terminal.description, 160) || null,
    status: safeStr(terminal.status, 64) || null,
    profile_id: safeStr(terminal.profile_id ?? terminal.profileId, 80) || null,
  };
}
