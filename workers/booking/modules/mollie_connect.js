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
export const MOLLIE_CONNECT_OAUTH_SCOPES =
  "organizations.read profiles.read payments.read payments.write refunds.read terminals.read";
export const ADMIN_MOLLIE_CONNECT_TEST_PAYMENT_TTL_SECONDS = 60 * 60 * 24 * 30;
export const ADMIN_MOLLIE_TERMINAL_PAYMENT_INTENT_TTL_SECONDS = 60 * 60 * 2;
export const MOLLIE_CONNECT_TOKEN_REFRESH_LEEWAY_MS = 60 * 1000;

/* ===================== Scoped key builders ===================== */

export function buildScopedMollieConnectAuthKey(scope = null) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return null;
  return `tenant:${tenantId}:company:${companyId}:mollie_connect_auth:v1`;
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
    last_connected_at:
      safeStr(rec.lastConnectedAt ?? rec.last_connected_at, 64) || null,
    updated_at: safeStr(rec.updatedAt ?? rec.updated_at, 64) || null,
    last_error_code: safeStr(rec.lastErrorCode ?? rec.last_error_code, 120) || null,
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

export async function fetchMollieConnectAccountMetadata(accessToken) {
  const token = safeStr(accessToken);
  if (!token) {
    return {
      organizationId: "",
      profileId: "",
      mollieMode: "unknown",
      onboardingStatus: null,
    };
  }
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/json",
  };
  let organizationId = "";
  let onboardingStatus = null;
  try {
    const orgRes = await fetch("https://api.mollie.com/v2/organizations/me", { headers });
    if (orgRes.ok) {
      const org = await orgRes.json();
      organizationId = safeStr(org?.id, 80);
      onboardingStatus =
        safeStr(org?.status, 64) ||
        safeStr(org?.onboarding?.status ?? org?.onboardingStatus, 64) ||
        null;
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
  return { organizationId, profileId, mollieMode, onboardingStatus };
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

export async function refreshMollieConnectTokens(env, scope, existingRecord) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) {
    return { ok: false, code: "missing_tenant_scope" };
  }
  if (!existingRecord || typeof existingRecord !== "object") {
    return { ok: false, code: "company_mollie_token_missing" };
  }
  const clientId = safeStr(env?.MOLLIE_CONNECT_CLIENT_ID);
  const clientSecret = safeStr(env?.MOLLIE_CONNECT_CLIENT_SECRET);
  if (!clientId || !clientSecret) {
    return { ok: false, code: "missing_mollie_connect_client_config" };
  }
  const encryptedRefresh =
    existingRecord.refreshTokenEncrypted ?? existingRecord.refresh_token_encrypted;
  if (!encryptedRefresh || typeof encryptedRefresh !== "object") {
    return { ok: false, code: "company_mollie_token_missing" };
  }
  let decrypted;
  try {
    decrypted = await decryptMollieConnectTokenPayload(
      { refreshTokenEncrypted: encryptedRefresh },
      env,
    );
  } catch (_) {
    return { ok: false, code: "company_mollie_token_refresh_failed" };
  }
  const refreshTokenPlain = safeStr(decrypted?.refresh_token);
  if (!refreshTokenPlain) {
    return { ok: false, code: "company_mollie_token_missing" };
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
    return { ok: false, code: "company_mollie_token_refresh_failed" };
  }
  if (!res.ok) {
    return { ok: false, code: "company_mollie_token_refresh_failed" };
  }
  let tokens = null;
  try {
    tokens = await res.json();
  } catch (_) {
    return { ok: false, code: "company_mollie_token_refresh_failed" };
  }
  const newAccessToken = safeStr(tokens?.access_token);
  if (!newAccessToken) {
    return { ok: false, code: "company_mollie_token_refresh_failed" };
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
    return { ok: false, code: "company_mollie_token_refresh_failed" };
  }
  const expiresInSec = Number(tokens?.expires_in);
  const nowMs = Date.now();
  const expiresAt =
    Number.isFinite(expiresInSec) && expiresInSec > 0
      ? new Date(nowMs + expiresInSec * 1000).toISOString()
      : null;
  const nowIso = new Date(nowMs).toISOString();
  const updatedRecord = {
    ...existingRecord,
    accessTokenEncrypted: encryptedTokens.accessTokenEncrypted,
    ...(encryptedTokens.refreshTokenEncrypted
      ? { refreshTokenEncrypted: encryptedTokens.refreshTokenEncrypted }
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
    return { ok: false, code: "company_mollie_token_refresh_failed" };
  }
  return {
    ok: true,
    record: updatedRecord,
    accessToken: newAccessToken,
  };
}

export async function resolveCompanyMollieConnectCredentials(env, scope, _options = {}) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) {
    return { ok: false, error: "company_mollie_credentials_unavailable" };
  }
  const scopedState = { tenant_id: tenantId, company_id: companyId };
  let record = null;
  try {
    record = await loadScopedMollieConnectAuthRecord(env, scopedState);
  } catch (_) {
    record = null;
  }
  if (!record || typeof record !== "object") {
    return { ok: false, error: "company_mollie_not_connected" };
  }
  const statusLower = safeStr(record.status, 32).toLowerCase();
  if (record.connected !== true || statusLower !== "connected") {
    return { ok: false, error: "company_mollie_not_connected" };
  }
  const encryptedAccess = record.accessTokenEncrypted ?? record.access_token_encrypted;
  const encryptedRefresh = record.refreshTokenEncrypted ?? record.refresh_token_encrypted;
  if (
    !encryptedAccess ||
    typeof encryptedAccess !== "object" ||
    !encryptedRefresh ||
    typeof encryptedRefresh !== "object"
  ) {
    return { ok: false, error: "company_mollie_token_missing" };
  }

  let workingRecord = record;
  let accessTokenPlain = "";

  if (_isMollieConnectAccessTokenExpired(workingRecord)) {
    const refreshed = await refreshMollieConnectTokens(env, scopedState, workingRecord);
    if (!refreshed?.ok) {
      return { ok: false, error: "company_mollie_token_refresh_failed" };
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
      const refreshed = await refreshMollieConnectTokens(env, scopedState, workingRecord);
      if (!refreshed?.ok) {
        return { ok: false, error: "company_mollie_token_refresh_failed" };
      }
      workingRecord = refreshed.record;
      accessTokenPlain = safeStr(refreshed.accessToken);
    }
  }

  if (!accessTokenPlain) {
    return { ok: false, error: "company_mollie_credentials_unavailable" };
  }

  const modeRaw = safeStr(
    workingRecord.mollie_mode ?? workingRecord.mollieMode,
    16,
  ).toLowerCase();
  const mode = modeRaw === "test" || modeRaw === "live" ? modeRaw : "unknown";
  return {
    ok: true,
    apiKey: accessTokenPlain,
    keyKind: "oauth",
    mode,
    payment_owner_mode: "company_mollie",
    payment_credential_source: "company_mollie",
    payment_company_id: companyId,
    payment_demo_mode: false,
    mollie_organization_id:
      safeStr(workingRecord.organizationId ?? workingRecord.organization_id, 80) || null,
    mollie_profile_id:
      safeStr(workingRecord.profileId ?? workingRecord.profile_id, 80) || null,
  };
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
  return {
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
  };
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
