/* Billit provider foundation (OAuth, token lifecycle, sandbox order API).
 * Moved verbatim from fluxidi_booking_worker.js (patch BW-M4B), no behavior change.
 *
 * BW-M4B LITE scope: everything Billit-owned that does NOT reach across into
 * document core issue lifecycle, payment lifecycle, booking core, or
 * business_profile stays here. Route handlers and lifecycle orchestrators
 * remain in the main worker for a later patch (BW-M4C / document_core module).
 *
 * Not moved (bridge to document core / payment / booking / business_profile):
 *   - handleAdminBillitConnectionTest (route dispatcher; needs safeJson,
 *     requireExplicitBookingRouteScope)
 *   - persistBillitOrderExportOnDocumentRecord (document core registry write)
 *   - loadBillitSandboxOrderContext (document lifecycle context loader)
 *   - performBillitSandboxPeppolSend (document + Peppol lifecycle)
 *   - reconcileBillitSandboxSentState (document lifecycle)
 *   - handleAdminBillitSandboxOrderCreate / OrderStatus / OrderSend /
 *     OrderReconcileSent / LinkExistingSandboxOrder
 *   - handleCompanyBillitSandboxOrderStatus / OrderSend
 *   - ensureBillitSandboxOrderForIssuedInvoice (document core issue lifecycle)
 *   - ensureBillitOrderForPaidBusinessBooking / maybeRunBillitAutoCreateAfterPaidLifecycle
 *     / handleAdminBookingBillitAutoCreateSandbox (booking + payment lifecycle)
 *   - buildPeppolReadyBookingFixtureRecord / handleAdminPeppolReadyBookingFixture
 *   - handleAdminCompanyBillitAutoCreateSettingsGet/Update
 *   - handleCompanyBillitAutoCreateSettingsGet/Update
 *   - handleAdminBillitAutoCreateLifecycleSandboxTest
 *   - normalizeBillitAutoCreateSettingsFromBusinessProfile
 *   - readBillitAutoCreateSettingsForScope
 *   - buildBillitPayloadPreviewFromProviderNeutralDocument
 *   - buildBillitOrderCandidatePreview / buildBillitOfficialOrderRequestPreview
 *   - buildBillitOfficialOrderCreateRequestFromPreview
 */

import { safeStr, sanitizeTenantString } from "./parsing_utils.js";
import { base64urlEncodeBytes, base64urlDecodeToBytes } from "./crypto_utils.js";
import { missingTenantScopeError } from "./auth_scope.js";

/* ===================== Billit constants ===================== */

export const BILLIT_PROVIDER = "billit";
export const BILLIT_OAUTH_STATE_TTL_SECONDS = 600; // 10 minutes
// Explicit Fluxidi platform default invoice payment term (in days) used to
// derive a Billit official-order ExpiryDate when no document-level due_date and
// no company-configured payment_terms_days exist yet. This is intentionally an
// EXPLICIT, surfaced default (never silent): previews expose both
// payment_terms_days and payment_terms_source. A future Business Settings UI
// can override it per company.
export const DEFAULT_BILLIT_PAYMENT_TERMS_DAYS = 30;
// Single, isolated read-only probe endpoint (PATH only; the host comes from
// resolveBillitOAuthConfig().api_base_url, i.e. the sandbox host). Kept as one
// constant so the exact Billit "account/party info" resource is trivial to
// adjust once confirmed. It MUST stay a non-mutating GET resource.
// Per Billit's OAuth docs this is the canonical "who am I / auth works"
// endpoint: GET /v1/account/accountInformation needs only the auth header (no
// PartyID), returns the user's companies, and a 200 means auth works. It is
// NEVER an invoice/create/send/draft/export endpoint. Still overridable
// per-environment via env.BILLIT_CONNECTION_PROBE_PATH WITHOUT a code change
// (confirmed green at runtime via that override before this default landed).
export const BILLIT_SANDBOX_CONNECTION_PROBE_PATH = "/v1/account/accountInformation";

/* ===================== Small pure helpers ===================== */

// Normalize an invoice payment term to an integer number of days in [0, 365].
// Missing/invalid input falls back to the explicit platform default. This is a
// surfaced default (never silent) and is unrelated to subscription billing.
export function normalizeBillitPaymentTermsDays(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return DEFAULT_BILLIT_PAYMENT_TERMS_DAYS;
  const rounded = Math.trunc(n);
  if (rounded < 0 || rounded > 365) return DEFAULT_BILLIT_PAYMENT_TERMS_DAYS;
  return rounded;
}

export function _billitError(code) {
  const err = new Error(String(code || "billit_oauth_error"));
  err.code = String(code || "billit_oauth_error");
  return err;
}

/* Resolve Billit OAuth config from env. NEVER throws at module load and
 * NEVER fails startup; returns { configured:false, missing_fields:[...] }
 * when required secrets are absent. The returned object DOES carry the
 * client_id/client_secret/redirect_uri for internal use by the OAuth
 * helpers, but route responses must only surface the *_configured booleans
 * and never the secret values themselves. */
export function resolveBillitOAuthConfig(env) {
  const modeRaw = safeStr(
    env?.BILLIT_ENVIRONMENT ?? env?.BILLIT_MODE,
    24,
  ).toLowerCase();
  const environment = modeRaw === "production" ? "production" : "sandbox";
  const defaultApiBase =
    environment === "production"
      ? "https://api.billit.be"
      : "https://api.sandbox.billit.be";
  const apiBaseUrl = safeStr(env?.BILLIT_API_BASE_URL, 300) || defaultApiBase;
  const clientId = safeStr(env?.BILLIT_CLIENT_ID, 300);
  const clientSecret = safeStr(env?.BILLIT_CLIENT_SECRET, 600);
  const redirectUri = safeStr(env?.BILLIT_REDIRECT_URI, 600);
  // Defaults per Billit's official OAuth docs. The authorize/login URL lives on
  // the my.* host; the token endpoint lives on the api.* host. All three are
  // overridable via BILLIT_AUTHORIZE_URL / BILLIT_TOKEN_URL / BILLIT_API_BASE_URL.
  const defaultAuthorizeUrl =
    environment === "production"
      ? "https://my.billit.be/Account/Logon"
      : "https://my.sandbox.billit.be/Account/Logon";
  const defaultTokenUrl =
    environment === "production"
      ? "https://api.billit.be/OAuth2/token"
      : "https://api.sandbox.billit.be/OAuth2/token";
  const authorizeUrl =
    safeStr(env?.BILLIT_AUTHORIZE_URL, 600) || defaultAuthorizeUrl;
  const tokenUrl = safeStr(env?.BILLIT_TOKEN_URL, 600) || defaultTokenUrl;
  const scope = safeStr(env?.BILLIT_OAUTH_SCOPE, 300) || "";
  const missingFields = [];
  if (!clientId) missingFields.push("BILLIT_CLIENT_ID");
  if (!clientSecret) missingFields.push("BILLIT_CLIENT_SECRET");
  if (!redirectUri) missingFields.push("BILLIT_REDIRECT_URI");
  return {
    provider: BILLIT_PROVIDER,
    configured: missingFields.length === 0,
    environment,
    api_base_url: apiBaseUrl,
    authorize_url: authorizeUrl,
    token_url: tokenUrl,
    scope,
    client_id: clientId,
    client_secret: clientSecret,
    redirect_uri: redirectUri,
    has_client_id: !!clientId,
    has_client_secret: !!clientSecret,
    has_redirect_uri: !!redirectUri,
    missing_fields: missingFields,
  };
}

/* ===================== Scoped key builders + state generator ===================== */

// Scoped connection record key - one per tenant/company, never global.
export function buildBillitOAuthConnectionKey(scope = null) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(
    scope?.company_id ?? scope?.companyId,
    80,
  );
  if (!tenantId || !companyId) return null;
  return `integration:billit:oauth:${tenantId}:${companyId}`;
}

// Short-lived OAuth state key (CSRF / flow binding). Keyed by the random
// state value, not by scope, so the callback can resolve scope from it.
export function buildBillitOAuthStateKey(state = "") {
  const safeState = safeStr(state, 200).replace(/[^a-zA-Z0-9_-]+/g, "");
  if (!safeState) return null;
  return `integration:billit:oauth_state:${safeState}`;
}

// Cryptographically strong OAuth state value (no Math.random fallback).
export function generateBillitOAuthState() {
  if (crypto?.randomUUID) {
    return crypto.randomUUID().replace(/[^a-zA-Z0-9_-]+/g, "");
  }
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return base64urlEncodeBytes(bytes);
}

/* ===================== Token encryption (AES-GCM) ===================== */

export function billitTokenEncryptionAvailable(env) {
  return !!String(env?.BILLIT_TOKEN_ENCRYPTION_KEY || "").trim();
}

export async function _importBillitTokenEncryptionKey(env) {
  const rawSecret = String(env?.BILLIT_TOKEN_ENCRYPTION_KEY || "").trim();
  if (!rawSecret) throw _billitError("missing_billit_token_encryption_key");
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

// Encrypt a single token string -> AES-GCM blob (same shape as the Mollie
// Connect token blobs). Returns null for an empty token. Never logs the
// plaintext token.
export async function encryptBillitTokenValue(tokenValue, env) {
  const token = String(tokenValue || "");
  if (!token) return null;
  const key = await _importBillitTokenEncryptionKey(env);
  const kid = safeStr(env?.BILLIT_TOKEN_ENCRYPTION_KID, 32) || "v1";
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(token);
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    plaintext,
  );
  return {
    alg: "AES-GCM",
    kid,
    iv: base64urlEncodeBytes(iv),
    ciphertext: base64urlEncodeBytes(new Uint8Array(encrypted)),
  };
}

// Decrypt a single AES-GCM token blob -> plaintext string. Provided for the
// FUTURE invoice-send patch; not invoked by this foundation patch's routes.
export async function decryptBillitTokenValue(encryptedObj, env) {
  if (!encryptedObj || typeof encryptedObj !== "object") return "";
  const alg = String(encryptedObj.alg || "").trim();
  if (alg !== "AES-GCM") throw _billitError("unsupported_billit_token_alg");
  const key = await _importBillitTokenEncryptionKey(env);
  const iv = base64urlDecodeToBytes(encryptedObj.iv);
  const ciphertext = base64urlDecodeToBytes(encryptedObj.ciphertext);
  if (!iv.length || !ciphertext.length) {
    throw _billitError("invalid_billit_token_blob");
  }
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(new Uint8Array(decrypted));
}

/* ===================== OAuth authorize / token flows ===================== */

/* ISOLATED authorization-URL builder. Keep all Billit-specific authorize
 * params + scopes here so they are trivial to adjust once Billit's exact
 * OAuth contract is confirmed. Per Billit's OAuth docs the Logon URL takes
 * only client_id + redirect_uri (+ optional state); a standard OAuth2
 * `response_type=code` param is NOT part of Billit's contract and makes the
 * sandbox reject the request as "Ongeldig OAuth2 request", so it is
 * intentionally omitted. Scope is still only sent when explicitly configured. */
export function buildBillitAuthorizationUrl(config, state) {
  const authUrl = new URL(config.authorize_url);
  authUrl.searchParams.set("client_id", config.client_id);
  authUrl.searchParams.set("redirect_uri", config.redirect_uri);
  authUrl.searchParams.set("state", String(state || ""));
  if (config.scope) authUrl.searchParams.set("scope", config.scope);
  return authUrl.toString();
}

/* ISOLATED token exchange. Per Billit docs: POST to /OAuth2/token with a JSON
 * body (Content-Type + Accept application/json, NO Authorization header).
 * Returns { ok:true, token_type, access_token, refresh_token, expires_in,
 * scope } or { ok:false, error }. NEVER logs the request body, code,
 * client_secret, or any token. */
export async function exchangeBillitOAuthCodeForToken(config, code) {
  let resp;
  try {
    resp = await fetch(config.token_url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        grant_type: "authorization_code",
        code: String(code || ""),
        client_id: config.client_id,
        client_secret: config.client_secret,
        redirect_uri: config.redirect_uri,
      }),
    });
  } catch (_) {
    return { ok: false, error: "token_request_failed" };
  }
  let data = null;
  try {
    data = await resp.json();
  } catch (_) {
    data = null;
  }
  if (!resp.ok || !data || typeof data !== "object" || Array.isArray(data)) {
    return { ok: false, error: "token_exchange_rejected" };
  }
  const accessToken = safeStr(data.access_token, 8000);
  if (!accessToken) return { ok: false, error: "token_response_missing_access_token" };
  const expiresInRaw = Number(data.expires_in);
  return {
    ok: true,
    token_type: safeStr(data.token_type, 40) || "Bearer",
    access_token: accessToken,
    refresh_token: safeStr(data.refresh_token, 8000) || "",
    expires_in: Number.isFinite(expiresInRaw) ? expiresInRaw : null,
    scope: safeStr(data.scope, 300) || "",
  };
}

/* ISOLATED token refresh helper for the FUTURE invoice-send patch. Per Billit
 * docs: POST to /OAuth2/token with a JSON refresh_token grant (NO Authorization
 * header). Billit refresh tokens are SINGLE-USE, so callers must persist the
 * newly returned refresh_token. NOT wired into any route here; performs no
 * decryption and is not invoked by this foundation. NEVER logs the request
 * body, client_secret, refresh_token, or any token. */
export async function refreshBillitOAuthToken(config, refreshToken) {
  let resp;
  try {
    resp = await fetch(config.token_url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        client_id: config.client_id,
        client_secret: config.client_secret,
        grant_type: "refresh_token",
        refresh_token: String(refreshToken || ""),
      }),
    });
  } catch (_) {
    return { ok: false, error: "token_refresh_failed" };
  }
  let data = null;
  try {
    data = await resp.json();
  } catch (_) {
    data = null;
  }
  if (!resp.ok || !data || typeof data !== "object" || Array.isArray(data)) {
    return { ok: false, error: "token_refresh_rejected" };
  }
  const accessToken = safeStr(data.access_token, 8000);
  if (!accessToken) return { ok: false, error: "token_refresh_missing_access_token" };
  const expiresInRaw = Number(data.expires_in);
  return {
    ok: true,
    token_type: safeStr(data.token_type, 40) || "Bearer",
    access_token: accessToken,
    refresh_token: safeStr(data.refresh_token, 8000) || "",
    expires_in: Number.isFinite(expiresInRaw) ? expiresInRaw : null,
    scope: null,
  };
}

/* ===================== Connection status + persistence ===================== */

// Safe public projection of a stored Billit connection record. NEVER surfaces
// encrypted/raw tokens or secrets - only status metadata.
export function _sanitizeBillitConnectionStatus(record) {
  const rec = record && typeof record === "object" ? record : {};
  const status = safeStr(rec.status, 40) || "not_configured";
  return {
    connected: rec.connected === true,
    status,
    party_id: safeStr(rec.party_id ?? rec.partyId, 120) || null,
    connected_at: safeStr(rec.connected_at, 40) || null,
    updated_at: safeStr(rec.updated_at, 40) || null,
    last_error_code: safeStr(rec.last_error_code, 80) || null,
  };
}

/* Shared Billit status reader for an already-authenticated tenant/company
 * scope. Returns the SAME safe projection body used by both admin and company
 * status routes - never tokens/secrets. */
export async function readBillitConnectionStatusForScope(env, scope) {
  const config = resolveBillitOAuthConfig(env);
  let record = null;
  if (env?.BOOKING_KV) {
    const key = buildBillitOAuthConnectionKey(scope);
    if (key) {
      try {
        record = await env.BOOKING_KV.get(key, { type: "json" });
      } catch (_) {
        record = null;
      }
    }
  }
  const projected = _sanitizeBillitConnectionStatus(record);
  const warnings = [];
  if (!config.configured) warnings.push("billit_oauth_not_configured");
  if (!billitTokenEncryptionAvailable(env)) {
    warnings.push("billit_token_encryption_key_missing");
  }
  return {
    ok: true,
    provider: BILLIT_PROVIDER,
    configured: config.configured,
    connected: projected.connected,
    environment: config.environment,
    api_base_url: config.api_base_url,
    redirect_uri_configured: config.has_redirect_uri,
    client_id_configured: config.has_client_id,
    client_secret_configured: config.has_client_secret,
    party_id: projected.party_id,
    status: projected.status,
    connected_at: projected.connected_at,
    updated_at: projected.updated_at,
    last_error_code: projected.last_error_code,
    warnings,
  };
}

/* Read-only PartyID resolver for an already-authenticated tenant/company scope.
 * Returns ONLY the Billit PartyID string (or null) from the stored OAuth
 * connection record. NEVER returns access/refresh tokens, encrypted values, or
 * the raw OAuth record. No token refresh, no external Billit call, strict
 * tenant/company scope. Used by the read-only Billit Order *candidate* preview;
 * any KV/binding error is swallowed into a null PartyID (non-blocking). */
export async function readBillitPartyIdForScope(env, scope) {
  if (!env?.BOOKING_KV) return null;
  const key = buildBillitOAuthConnectionKey(scope);
  if (!key) return null;
  let record = null;
  try {
    record = await env.BOOKING_KV.get(key, { type: "json" });
  } catch (_) {
    record = null;
  }
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    return null;
  }
  return safeStr(record.party_id ?? record.partyId, 120) || null;
}

/* Persist a sanitized Billit PartyID onto the scoped OAuth connection record
 * in KV. Used after a successful connection-test probe so read-only preview
 * routes can resolve party_id without another Billit call. Spreads the supplied
 * in-memory record (including any freshly refreshed encrypted tokens from the
 * same request) and only adds party_id metadata. Never stores probe raw body or
 * token plaintext; non-fatal on KV failure. */
export async function persistBillitPartyIdOnConnectionRecord(
  env,
  scope,
  record,
  partyId,
  checkedAt,
) {
  const safePartyId = safeStr(partyId, 120);
  if (!safePartyId) return record;
  if (!env?.BOOKING_KV) return record;
  if (!record || typeof record !== "object" || Array.isArray(record)) {
    return record;
  }
  const connKey = buildBillitOAuthConnectionKey(scope);
  if (!connKey) return record;
  const updated = {
    ...record,
    party_id: safePartyId,
    party_id_checked_at: safeStr(checkedAt, 40) || new Date().toISOString(),
    updated_at: new Date().toISOString(),
  };
  try {
    await env.BOOKING_KV.put(connKey, JSON.stringify(updated));
    return updated;
  } catch (_) {
    return record;
  }
}

/* Shared Billit OAuth start for an already-authenticated tenant/company scope.
 * Generates+stores the state, marks the connection authorization_started, and
 * returns { status, body } for the caller to serialise. No token call here, no
 * secrets in the body. */
export async function startBillitOAuthForScope(env, scope) {
  if (!env?.BOOKING_KV) {
    return { status: 503, body: { ok: false, error: "missing_binding" } };
  }
  const config = resolveBillitOAuthConfig(env);
  if (!config.configured) {
    return {
      status: 400,
      body: {
        ok: false,
        error: "billit_oauth_not_configured",
        missing_fields: config.missing_fields,
      },
    };
  }
  // Cryptographically random state, bound to scope + environment in KV with a
  // short TTL so the callback can validate + resolve scope.
  const state = generateBillitOAuthState();
  const stateKey = buildBillitOAuthStateKey(state);
  if (!stateKey) {
    return { status: 500, body: { ok: false, error: "state_generation_failed" } };
  }
  const nowIso = new Date().toISOString();
  const stateRecord = {
    provider: BILLIT_PROVIDER,
    tenant_id: scope.tenant_id,
    company_id: scope.company_id,
    environment: config.environment,
    created_at: nowIso,
  };
  await env.BOOKING_KV.put(stateKey, JSON.stringify(stateRecord), {
    expirationTtl: BILLIT_OAUTH_STATE_TTL_SECONDS,
  });
  // Mark the scoped connection as authorization_started (no tokens).
  const connKey = buildBillitOAuthConnectionKey(scope);
  if (connKey) {
    const startedRecord = {
      provider: BILLIT_PROVIDER,
      tenant_id: scope.tenant_id,
      company_id: scope.company_id,
      environment: config.environment,
      connected: false,
      status: "authorization_started",
      connected_at: null,
      updated_at: nowIso,
      token_type: null,
      access_token_encrypted: null,
      refresh_token_encrypted: null,
      expires_at: null,
      scope: config.scope || null,
      party_id: null,
      last_error_code: null,
      last_error_message: null,
    };
    try {
      await env.BOOKING_KV.put(connKey, JSON.stringify(startedRecord));
    } catch (_) {
      // non-fatal; the callback will (re)write the connection record
    }
  }
  const authorizationUrl = buildBillitAuthorizationUrl(config, state);
  console.log(
    `[BILLIT_OAUTH][START] tenant=${scope.tenant_id} company=${scope.company_id} env=${config.environment}`,
  );
  return {
    status: 200,
    body: {
      ok: true,
      authorization_url: authorizationUrl,
      state_expires_in_seconds: BILLIT_OAUTH_STATE_TTL_SECONDS,
      environment: config.environment,
      redirect_uri: config.redirect_uri,
    },
  };
}

/* Shared Billit disconnect for an already-authenticated tenant/company scope.
 * Clears the scoped connection record and returns { status, body }. */
export async function disconnectBillitOAuthForScope(env, scope) {
  if (!env?.BOOKING_KV) {
    return { status: 503, body: { ok: false, error: "missing_binding" } };
  }
  const connKey = buildBillitOAuthConnectionKey(scope);
  if (!connKey) {
    return { status: 400, body: missingTenantScopeError() };
  }
  try {
    await env.BOOKING_KV.delete(connKey);
  } catch (_) {
    // tolerate; treat as already-disconnected
  }
  console.log(
    `[BILLIT_OAUTH][DISCONNECT] tenant=${scope.tenant_id} company=${scope.company_id}`,
  );
  return {
    status: 200,
    body: {
      ok: true,
      provider: BILLIT_PROVIDER,
      tenant_id: scope.tenant_id,
      company_id: scope.company_id,
      connected: false,
      status: "not_configured",
    },
  };
}

/* ===================== Sandbox connection probe ===================== */

// Resolve the probe path, honouring an optional env override. Defensive:
// even an override can never point at a mutating invoice/send-like endpoint.
export function _resolveBillitConnectionProbePath(env) {
  const override = safeStr(env?.BILLIT_CONNECTION_PROBE_PATH, 300);
  const path = override || BILLIT_SANDBOX_CONNECTION_PROBE_PATH;
  const lowered = path.toLowerCase();
  const forbidden = [
    "invoice",
    "send",
    "draft",
    "export",
    "create",
    "document",
    "order",
    "peppol",
  ];
  for (const token of forbidden) {
    if (lowered.includes(token)) return BILLIT_SANDBOX_CONNECTION_PROBE_PATH;
  }
  return path.startsWith("/") ? path : `/${path}`;
}

/* ISOLATED read-only Billit sandbox probe. Performs exactly ONE GET with the
 * decrypted access token in an Authorization header. Returns ONLY safe status
 * metadata; NEVER returns the raw body and NEVER logs the token. */
export async function callBillitSandboxConnectionProbe(config, accessToken, env) {
  const base = String(config.api_base_url || "").replace(/\/+$/, "");
  const probePath = _resolveBillitConnectionProbePath(env);
  const probeUrl = `${base}${probePath}`;
  let resp;
  try {
    resp = await fetch(probeUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
      },
    });
  } catch (_) {
    return {
      ok: false,
      status_code: null,
      billit_error_code: "probe_request_failed",
      billit_error_description: null,
      party_id: null,
    };
  }
  const statusCode = resp.status;
  let data = null;
  try {
    data = await resp.json();
  } catch (_) {
    data = null;
  }
  const isObj = data && typeof data === "object" && !Array.isArray(data);
  // Billit validation errors use the shape { "errors": [ { "Code", "Description" } ] }.
  const firstError =
    isObj && Array.isArray(data.errors) && data.errors.length > 0 &&
    data.errors[0] && typeof data.errors[0] === "object"
      ? data.errors[0]
      : null;
  if (!resp.ok) {
    // Surface only short, safe error fields (never the raw body / tokens).
    const billitErrorCode = isObj
      ? safeStr(
          (firstError && (firstError.Code ?? firstError.code)) ??
            data.error ??
            data.Error ??
            data.code ??
            data.Code ??
            data.error_code,
          80,
        ) || null
      : null;
    const billitErrorDescription = isObj
      ? safeStr(
          (firstError && (firstError.Description ?? firstError.description)) ??
            data.error_description ??
            data.message ??
            data.Message,
          200,
        ) || null
      : null;
    return {
      ok: false,
      status_code: statusCode,
      billit_error_code: billitErrorCode,
      billit_error_description: billitErrorDescription,
      party_id: null,
    };
  }
  // Safe party id extraction only (no other body fields are surfaced). Billit's
  // accountInformation returns PartyID nested in the Companies[] array.
  const companies = isObj && Array.isArray(data.companies)
    ? data.companies
    : isObj && Array.isArray(data.Companies)
      ? data.Companies
      : [];
  const firstCompany =
    companies.length > 0 && companies[0] && typeof companies[0] === "object"
      ? companies[0]
      : null;
  const partyId = isObj
    ? safeStr(
        data.PartyID ??
          data.partyID ??
          data.party_id ??
          data.partyId ??
          data.id ??
          data.Id ??
          data.ID ??
          (firstCompany &&
            (firstCompany.PartyID ??
              firstCompany.partyID ??
              firstCompany.party_id ??
              firstCompany.partyId)),
        120,
      ) || null
    : null;
  return {
    ok: true,
    status_code: statusCode,
    billit_error_code: null,
    billit_error_description: null,
    party_id: partyId,
  };
}

/* ===================== Sandbox access-token acquisition (with refresh) ===================== */

export async function acquireBillitSandboxAccessToken(env, scope, config) {
  if (!env?.BOOKING_KV) {
    return { ok: false, status: 503, error: "missing_binding" };
  }
  const connKey = buildBillitOAuthConnectionKey(scope);
  if (!connKey) {
    return { ok: false, status: 400, error: "missing_tenant_scope" };
  }
  let record = null;
  try {
    record = await env.BOOKING_KV.get(connKey, { type: "json" });
  } catch (_) {
    record = null;
  }
  if (
    !record ||
    typeof record !== "object" ||
    record.connected !== true ||
    !record.access_token_encrypted
  ) {
    return { ok: false, status: 409, error: "billit_not_connected" };
  }
  if (!billitTokenEncryptionAvailable(env)) {
    return { ok: false, status: 400, error: "billit_token_encryption_unavailable" };
  }
  let accessToken = "";
  try {
    accessToken = await decryptBillitTokenValue(record.access_token_encrypted, env);
  } catch (_) {
    accessToken = "";
  }
  if (!accessToken) {
    return { ok: false, status: 500, error: "billit_token_decrypt_failed" };
  }

  // Single-use refresh when expired (or within a 60s skew) AND a refresh token
  // is available. Mirrors the connection-test refresh path exactly.
  let refreshed = false;
  const expiresAtMs = record.expires_at ? Date.parse(record.expires_at) : NaN;
  const isExpired = Number.isFinite(expiresAtMs)
    ? expiresAtMs - Date.now() <= 60_000
    : false;
  if (isExpired) {
    if (!record.refresh_token_encrypted) {
      return { ok: false, status: 409, error: "billit_token_expired_no_refresh" };
    }
    let refreshToken = "";
    try {
      refreshToken = await decryptBillitTokenValue(record.refresh_token_encrypted, env);
    } catch (_) {
      refreshToken = "";
    }
    if (!refreshToken) {
      return { ok: false, status: 500, error: "billit_token_decrypt_failed" };
    }
    const refreshResult = await refreshBillitOAuthToken(config, refreshToken);
    if (!refreshResult.ok) {
      try {
        await env.BOOKING_KV.put(
          connKey,
          JSON.stringify({
            ...record,
            updated_at: new Date().toISOString(),
            last_error_code: "token_refresh_failed",
          }),
        );
      } catch (_) {
        // non-fatal
      }
      return { ok: false, status: 502, error: "billit_token_refresh_failed" };
    }
    try {
      const newAccessEncrypted = await encryptBillitTokenValue(refreshResult.access_token, env);
      const newRefreshEncrypted = refreshResult.refresh_token
        ? await encryptBillitTokenValue(refreshResult.refresh_token, env)
        : record.refresh_token_encrypted;
      const newExpiresAt =
        refreshResult.expires_in !== null && refreshResult.expires_in !== undefined
          ? new Date(Date.now() + refreshResult.expires_in * 1000).toISOString()
          : null;
      const updatedRecord = {
        ...record,
        updated_at: new Date().toISOString(),
        token_type: refreshResult.token_type || record.token_type || "Bearer",
        access_token_encrypted: newAccessEncrypted,
        refresh_token_encrypted: newRefreshEncrypted,
        expires_at: newExpiresAt,
        last_error_code: null,
      };
      await env.BOOKING_KV.put(connKey, JSON.stringify(updatedRecord));
      record = updatedRecord;
      accessToken = refreshResult.access_token;
      refreshed = true;
    } catch (_) {
      return { ok: false, status: 500, error: "billit_token_persist_failed" };
    }
  }

  const partyId = safeStr(record.party_id ?? record.partyId, 120) || null;
  return { ok: true, status: 200, access_token: accessToken, refreshed, party_id: partyId };
}

/* ===================== Sandbox order API wrappers ===================== */

/* The ONLY new outbound Billit call in B6a: create exactly one order via
 * POST {api_base_url}/v1/orders against the SANDBOX host. Returns a sanitized
 * summary only; NEVER logs/returns the token or the raw provider body. */
export async function postBillitSandboxOrderCreate(config, accessToken, partyId, createRequest) {
  const base = String(config.api_base_url || "").replace(/\/+$/, "");
  const endpoint = safeStr(createRequest?.endpoint, 80) || "/v1/orders";
  const createUrl = `${base}${endpoint}`;
  let resp;
  try {
    resp = await fetch(createUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        PartyID: safeStr(partyId, 120),
        "Idempotent-Key": safeStr(createRequest?.idempotency_key, 200),
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify(createRequest?.body ?? {}),
    });
  } catch (_) {
    return {
      ok: false,
      status_code: null,
      billit_error_code: "order_create_request_failed",
      billit_error_description: null,
      summary: null,
    };
  }
  const statusCode = resp.status;
  let data = null;
  try {
    data = await resp.json();
  } catch (_) {
    data = null;
  }
  const isObj = data && typeof data === "object" && !Array.isArray(data);
  const firstError =
    isObj && Array.isArray(data.errors) && data.errors.length > 0 &&
    data.errors[0] && typeof data.errors[0] === "object"
      ? data.errors[0]
      : null;
  if (!resp.ok) {
    const billitErrorCode = isObj
      ? safeStr(
          (firstError && (firstError.Code ?? firstError.code)) ??
            data.error ??
            data.Error ??
            data.code ??
            data.Code ??
            data.error_code,
          80,
        ) || null
      : null;
    const billitErrorDescription = isObj
      ? safeStr(
          (firstError && (firstError.Description ?? firstError.description)) ??
            data.error_description ??
            data.message ??
            data.Message,
          200,
        ) || null
      : null;
    return {
      ok: false,
      status_code: statusCode,
      billit_error_code: billitErrorCode,
      billit_error_description: billitErrorDescription,
      summary: null,
    };
  }
  // Billit POST /v1/orders commonly returns the new OrderID as a bare
  // number/string; otherwise it is an object with order identity fields.
  let summary;
  if (typeof data === "number" || (typeof data === "string" && data.trim() !== "")) {
    summary = {
      billit_order_id: safeStr(data, 120) || null,
      billit_order_number: null,
      billit_status: null,
    };
  } else {
    summary = sanitizeBillitOrderCreateResponse(data);
  }
  return {
    ok: true,
    status_code: statusCode,
    billit_error_code: null,
    billit_error_description: null,
    summary,
  };
}

/* Pure sanitizer for a Billit Order Object returned by the read endpoint
 * (Patch B6c). Extracts ONLY safe scalar identity/status/date fields, tolerating
 * casing variants. NEVER surfaces Customer, Addresses, OrderLines, VAT details,
 * files/PDF/UBL/XML, or the raw response body. Booleans normalize to
 * true/false/null; strings are safeStr-bounded. */
export function sanitizeBillitOrderReadResponse(data) {
  const obj =
    data && typeof data === "object" && !Array.isArray(data) ? data : null;
  if (!obj) {
    return {
      order_id: null,
      order_number: null,
      order_status: null,
      order_date: null,
      expiry_date: null,
      created: null,
      last_modified: null,
      is_sent: null,
      paid: null,
      paid_date: null,
      currency: null,
      order_type: null,
      order_direction: null,
    };
  }
  const _bool = (v) => (typeof v === "boolean" ? v : null);
  const _date = (v) => safeStr(v, 40) || null;
  return {
    order_id:
      safeStr(
        obj.OrderID ?? obj.OrderId ?? obj.orderID ?? obj.orderId ?? obj.ID ?? obj.Id ?? obj.id,
        120,
      ) || null,
    order_number:
      safeStr(obj.OrderNumber ?? obj.orderNumber ?? obj.Number ?? obj.number, 80) || null,
    order_status:
      safeStr(obj.OrderStatus ?? obj.orderStatus ?? obj.Status ?? obj.status, 80) || null,
    order_date: _date(obj.OrderDate ?? obj.orderDate),
    expiry_date: _date(obj.ExpiryDate ?? obj.expiryDate),
    created: _date(obj.Created ?? obj.created),
    last_modified: _date(obj.LastModified ?? obj.lastModified),
    is_sent: _bool(obj.IsSent ?? obj.isSent),
    paid: _bool(obj.Paid ?? obj.paid),
    paid_date: _date(obj.PaidDate ?? obj.paidDate),
    currency: safeStr(obj.Currency ?? obj.currency, 8).toUpperCase() || null,
    order_type: safeStr(obj.OrderType ?? obj.orderType, 40) || null,
    order_direction: safeStr(obj.OrderDirection ?? obj.orderDirection, 40) || null,
  };
}

/* The ONLY new outbound Billit call in B6c: read exactly one order via
 * GET {api_base_url}/v1/orders/{orderId} against the SANDBOX host. Includes the
 * PartyID header to define company context (per Billit docs). Exactly one fetch,
 * no retry loop. Returns a sanitized order summary or a safe error; NEVER logs/
 * returns the token, request headers, or the raw provider body. */
export async function fetchBillitSandboxOrderById(config, accessToken, partyId, orderId) {
  const base = String(config.api_base_url || "").replace(/\/+$/, "");
  const safeOrderId = safeStr(orderId, 120);
  if (!safeOrderId) {
    return {
      ok: false,
      status: 400,
      error: "billit_order_read_failed",
      billit_error_code: "missing_order_id",
      billit_error_description: null,
    };
  }
  const readUrl = `${base}/v1/orders/${encodeURIComponent(safeOrderId)}`;
  let resp;
  try {
    resp = await fetch(readUrl, {
      method: "GET",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        PartyID: safeStr(partyId, 120),
      },
    });
  } catch (_) {
    return {
      ok: false,
      status: null,
      error: "billit_order_read_failed",
      billit_error_code: "order_read_request_failed",
      billit_error_description: null,
    };
  }
  const statusCode = resp.status;
  let data = null;
  try {
    data = await resp.json();
  } catch (_) {
    data = null;
  }
  const isObj = data && typeof data === "object" && !Array.isArray(data);
  const firstError =
    isObj && Array.isArray(data.errors) && data.errors.length > 0 &&
    data.errors[0] && typeof data.errors[0] === "object"
      ? data.errors[0]
      : null;
  if (!resp.ok) {
    const billitErrorCode = isObj
      ? safeStr(
          (firstError && (firstError.Code ?? firstError.code)) ??
            data.error ??
            data.Error ??
            data.code ??
            data.Code ??
            data.error_code,
          80,
        ) || null
      : null;
    const billitErrorDescription = isObj
      ? safeStr(
          (firstError && (firstError.Description ?? firstError.description)) ??
            data.error_description ??
            data.message ??
            data.Message,
          200,
        ) || null
      : null;
    return {
      ok: false,
      status: statusCode,
      error: "billit_order_read_failed",
      billit_error_code: billitErrorCode,
      billit_error_description: billitErrorDescription,
    };
  }
  return { ok: true, status: statusCode, order: sanitizeBillitOrderReadResponse(data) };
}

/* Billit PATCH payment-status: confirmed-safe PaymentMethod enum (Billit docs). */
const BILLIT_PATCH_PAYMENT_METHOD_WIRED = "Wired";

/* Defensive Fluxidi → Billit PaymentMethod mapping. Returns null when uncertain
 * so the PATCH omits PaymentMethod and never fails solely on an unknown enum. */
export function mapFluxidiPaymentMethodToBillitPaymentMethod(
  paymentMethod,
  paymentProvider,
  paymentSource,
) {
  const method = safeStr(paymentMethod, 80).toLowerCase();
  const provider = safeStr(paymentProvider, 40).toLowerCase();
  const source = safeStr(paymentSource, 40).toLowerCase();

  if (
    method === "bancontact" ||
    method === "bancontact_qr" ||
    method === "belfius" ||
    method === "kbc" ||
    method === "kbc_cbc" ||
    method === "ideal" ||
    method === "card" ||
    method === "creditcard" ||
    method === "card_payment" ||
    method === "cartes_bancaires" ||
    method === "paypal" ||
    method === "applepay" ||
    method === "googlepay" ||
    method === "online_payment" ||
    method === "online" ||
    method === "mollie"
  ) {
    return BILLIT_PATCH_PAYMENT_METHOD_WIRED;
  }
  if (provider === "mollie") {
    return BILLIT_PATCH_PAYMENT_METHOD_WIRED;
  }
  if (
    method === "qr_code" ||
    method === "bank_transfer" ||
    method === "wire_transfer" ||
    method === "sepa" ||
    source === "qr"
  ) {
    return BILLIT_PATCH_PAYMENT_METHOD_WIRED;
  }
  // cash / in-car / manual: omit PaymentMethod (Paid + PaidDate are sufficient).
  if (
    method === "cash" ||
    method === "in_vehicle_card" ||
    method === "pay_in_car" ||
    method === "in_car" ||
    provider === "manual" ||
    source === "in_car"
  ) {
    return null;
  }
  return null;
}

/* Billit expects PaidDate with date + time (no timezone suffix required). */
export function formatBillitPaidDateForPatch(paidAtIso) {
  const s = safeStr(paidAtIso, 40);
  if (!s) return new Date().toISOString().slice(0, 19);
  const ms = Date.parse(s);
  if (!Number.isFinite(ms)) return new Date().toISOString().slice(0, 19);
  return new Date(ms).toISOString().slice(0, 19);
}

/* Pure builder for PATCH /v1/orders/{orderId} payment sync (P1-C-A). */
export function buildBillitSandboxOrderPaymentPatchBody({
  paidAt,
  paymentMethod,
  paymentProvider,
  paymentSource,
  internalInfo,
} = {}) {
  const body = {
    Paid: true,
    PaidDate: formatBillitPaidDateForPatch(paidAt),
  };
  const billitMethod = mapFluxidiPaymentMethodToBillitPaymentMethod(
    paymentMethod,
    paymentProvider,
    paymentSource,
  );
  if (billitMethod) {
    body.PaymentMethod = billitMethod;
  }
  const info = safeStr(internalInfo, 200);
  if (info) {
    body.InternalInfo = info;
  }
  return body;
}

/* PATCH {api_base_url}/v1/orders/{orderId} — sandbox payment-state sync (P1-C-A).
 * Same auth/header pattern as fetchBillitSandboxOrderById. Never logs tokens or
 * raw provider bodies. */
export async function patchBillitSandboxOrderPaymentStatus(
  config,
  accessToken,
  partyId,
  orderId,
  patchBody,
) {
  const base = String(config.api_base_url || "").replace(/\/+$/, "");
  const safeOrderId = safeStr(orderId, 120);
  if (!safeOrderId) {
    return {
      ok: false,
      status_code: 400,
      error: "billit_order_payment_patch_failed",
      billit_error_code: "missing_order_id",
      billit_error_description: null,
    };
  }
  const body =
    patchBody && typeof patchBody === "object" && !Array.isArray(patchBody)
      ? patchBody
      : null;
  if (!body || body.Paid !== true) {
    return {
      ok: false,
      status_code: 400,
      error: "billit_order_payment_patch_failed",
      billit_error_code: "invalid_patch_body",
      billit_error_description: null,
    };
  }
  const patchUrl = `${base}/v1/orders/${encodeURIComponent(safeOrderId)}`;
  let resp;
  try {
    resp = await fetch(patchUrl, {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        "Content-Type": "application/json",
        PartyID: safeStr(partyId, 120),
      },
      body: JSON.stringify(body),
    });
  } catch (_) {
    return {
      ok: false,
      status_code: null,
      error: "billit_order_payment_patch_failed",
      billit_error_code: "order_payment_patch_request_failed",
      billit_error_description: null,
    };
  }
  const statusCode = resp.status;
  let data = null;
  try {
    const text = await resp.text();
    if (text && text.trim()) {
      data = JSON.parse(text);
    }
  } catch (_) {
    data = null;
  }
  const isObj = data && typeof data === "object" && !Array.isArray(data);
  const firstError =
    isObj && Array.isArray(data.errors) && data.errors.length > 0 &&
    data.errors[0] && typeof data.errors[0] === "object"
      ? data.errors[0]
      : null;
  if (!resp.ok) {
    const billitErrorCode = isObj
      ? safeStr(
          (firstError && (firstError.Code ?? firstError.code)) ??
            data.error ??
            data.Error ??
            data.code ??
            data.Code ??
            data.error_code,
          80,
        ) || null
      : null;
    const billitErrorDescription = isObj
      ? safeStr(
          (firstError && (firstError.Description ?? firstError.description)) ??
            data.error_description ??
            data.message ??
            data.Message,
          200,
        ) || null
      : null;
    return {
      ok: false,
      status_code: statusCode,
      error: "billit_order_payment_patch_failed",
      billit_error_code: billitErrorCode,
      billit_error_description: billitErrorDescription,
    };
  }
  return { ok: true, status_code: statusCode };
}

/* Merge payment-sync envelope fields onto an existing billit_export object.
 * Never mutates sent/peppol_sent to true. */
export function mergeBillitExportPaymentSyncFields(existingExport, syncFields = {}) {
  const base =
    existingExport && typeof existingExport === "object" && !Array.isArray(existingExport)
      ? { ...existingExport }
      : {};
  const nowIso = safeStr(syncFields.billit_payment_synced_at, 40) || new Date().toISOString();
  return {
    ...base,
    billit_paid:
      typeof syncFields.billit_paid === "boolean" ? syncFields.billit_paid : base.billit_paid ?? null,
    billit_paid_date:
      safeStr(syncFields.billit_paid_date, 40) || safeStr(base.billit_paid_date, 40) || null,
    billit_payment_sync_status:
      safeStr(syncFields.billit_payment_sync_status, 40) ||
      safeStr(base.billit_payment_sync_status, 40) ||
      null,
    billit_payment_synced_at:
      safeStr(syncFields.billit_payment_synced_at, 40) ||
      safeStr(base.billit_payment_synced_at, 40) ||
      null,
    billit_payment_sync_error:
      safeStr(syncFields.billit_payment_sync_error, 120) ||
      safeStr(base.billit_payment_sync_error, 120) ||
      null,
    sent: base.sent === true,
    peppol_sent: base.peppol_sent === true,
    updated_at: nowIso,
  };
}

/* Pure builder (Patch B7) for the Billit sandbox order SEND command request.
 * Fail-closed: the transport type allowlist is intentionally ["Peppol"] ONLY —
 * SMTP/email and Letter are deliberately unsupported. Returns null on any
 * invalid input so the caller stays fail-closed. Exactly ONE order id (never a
 * batch). Uses the EXACT Billit casing `Transporttype` + `OrderIDs`. A numeric
 * order id string is sent as a Number (Billit's create returns bare numbers);
 * otherwise the string id is preserved. No token/secret is ever referenced. */
export function buildBillitSandboxOrderSendRequest({ orderId, transportType } = {}) {
  const allowedTransports = new Set(["Peppol"]);
  const transport = safeStr(transportType, 24);
  if (!allowedTransports.has(transport)) return null;
  const safeOrderId = safeStr(orderId, 120);
  if (!safeOrderId) return null;
  const orderIdValue = /^[0-9]+$/.test(safeOrderId) ? Number(safeOrderId) : safeOrderId;
  return {
    endpoint: "/v1/orders/commands/send",
    method: "POST",
    body: {
      Transporttype: transport,
      OrderIDs: [orderIdValue],
    },
  };
}

/* Pure sanitizer (Patch B7) for the Billit send-command response. Extracts ONLY
 * a tiny, safe summary: send_status (string|null), transport_id (string|null),
 * accepted (true/false/null). Tolerates an empty 2xx body, a bare scalar id, and
 * object shapes using Success/Status/TransportID/CommandID/id casing variants.
 * NEVER returns the raw response body, tokens, headers, or any Customer/
 * Addresses/OrderLines/VAT/files. */
export function sanitizeBillitSendCommandResponse(data) {
  if (data === null || data === undefined || data === "") {
    return { send_status: null, transport_id: null, accepted: null };
  }
  if (typeof data === "number" || (typeof data === "string" && data.trim() !== "")) {
    return { send_status: null, transport_id: safeStr(data, 120) || null, accepted: null };
  }
  const obj = data && typeof data === "object" && !Array.isArray(data) ? data : null;
  if (!obj) return { send_status: null, transport_id: null, accepted: null };
  const sendStatus =
    safeStr(
      obj.Status ?? obj.status ?? obj.SendStatus ?? obj.sendStatus ??
        obj.TransportStatus ?? obj.transportStatus,
      80,
    ) || null;
  const transportId =
    safeStr(
      obj.TransportID ?? obj.TransportId ?? obj.transportId ??
        obj.CommandID ?? obj.CommandId ?? obj.commandId ??
        obj.ID ?? obj.Id ?? obj.id,
      120,
    ) || null;
  const rawAccepted =
    obj.Success ?? obj.success ?? obj.Accepted ?? obj.accepted ?? obj.OK ?? obj.ok;
  const accepted = typeof rawAccepted === "boolean" ? rawAccepted : null;
  return { send_status: sendStatus, transport_id: transportId, accepted };
}

/* The ONLY new outbound Billit call in B7: send exactly ONE order via
 * POST {api_base_url}/v1/orders/commands/send against the SANDBOX host. Includes
 * the PartyID header (as create/read do). Exactly one fetch, no retry loop.
 * Returns a sanitized summary or a safe error; NEVER logs/returns the token,
 * request headers, or the raw provider body. */
export async function postBillitSandboxOrderSend(config, accessToken, partyId, sendRequest) {
  const base = String(config.api_base_url || "").replace(/\/+$/, "");
  const endpoint = safeStr(sendRequest?.endpoint, 80) || "/v1/orders/commands/send";
  const sendUrl = `${base}${endpoint}`;
  let resp;
  try {
    resp = await fetch(sendUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/json",
        "Content-Type": "application/json",
        PartyID: safeStr(partyId, 120),
      },
      body: JSON.stringify(sendRequest?.body ?? {}),
    });
  } catch (_) {
    return {
      ok: false,
      status: null,
      error: "billit_order_send_failed",
      billit_error_code: "order_send_request_failed",
      billit_error_description: null,
    };
  }
  const statusCode = resp.status;
  let data = null;
  try {
    data = await resp.json();
  } catch (_) {
    data = null;
  }
  const isObj = data && typeof data === "object" && !Array.isArray(data);
  const firstError =
    isObj && Array.isArray(data.errors) && data.errors.length > 0 &&
    data.errors[0] && typeof data.errors[0] === "object"
      ? data.errors[0]
      : null;
  if (!resp.ok) {
    const billitErrorCode = isObj
      ? safeStr(
          (firstError && (firstError.Code ?? firstError.code)) ??
            data.error ?? data.Error ?? data.code ?? data.Code ?? data.error_code,
          80,
        ) || null
      : null;
    const billitErrorDescription = isObj
      ? safeStr(
          (firstError && (firstError.Description ?? firstError.description)) ??
            data.error_description ?? data.message ?? data.Message,
          200,
        ) || null
      : null;
    return {
      ok: false,
      status: statusCode,
      error: "billit_order_send_failed",
      billit_error_code: billitErrorCode,
      billit_error_description: billitErrorDescription,
    };
  }
  return { ok: true, status: statusCode, send: sanitizeBillitSendCommandResponse(data) };
}

/* ===================== Small callback page ===================== */

export function _billitCallbackHtml(message, status = 200) {
  const safeMessage = safeStr(message, 240) || "Billit.";
  const body = `<!doctype html><html lang="nl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Billit</title></head><body style="font-family:system-ui,sans-serif;padding:24px;color:#111">${safeMessage}</body></html>`;
  return new Response(body, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

/* ===================== Pure Billit export/response builders ===================== */

// Pure idempotency-key builder used by every Billit sandbox order-create call.
export function buildBillitSandboxOrderCreateIdempotencyKey(documentId) {
  const id = safeStr(documentId, 200);
  if (!id) return null;
  return `fluxidi-billit-order-create:${id}:sandbox:v1`;
}

/* Pure Billit order-create response sanitizer. Extracts ONLY the safe order
 * identity fields (OrderID / OrderNumber / OrderStatus) with case-tolerant
 * fallbacks. NEVER surfaces the raw response body, Customer/Addresses/
 * OrderLines/VAT/files, or any secret. Returns a stable shape with nulls when
 * absent so callers can safely destructure. */
export function sanitizeBillitOrderCreateResponse(responseJson) {
  const data =
    responseJson && typeof responseJson === "object" && !Array.isArray(responseJson)
      ? responseJson
      : null;
  if (!data) {
    return {
      billit_order_id: null,
      billit_order_number: null,
      billit_status: null,
    };
  }
  const orderId =
    safeStr(
      data.OrderID ??
        data.orderID ??
        data.OrderId ??
        data.orderId ??
        data.ID ??
        data.Id ??
        data.id,
      120,
    ) || null;
  const orderNumber =
    safeStr(
      data.OrderNumber ??
        data.orderNumber ??
        data.Number ??
        data.number,
      120,
    ) || null;
  const status =
    safeStr(
      data.OrderStatus ??
        data.orderStatus ??
        data.Status ??
        data.status,
      80,
    ) || null;
  return {
    billit_order_id: orderId,
    billit_order_number: orderNumber,
    billit_status: status,
  };
}

/* Pure builder for the envelope-only billit_export metadata stored on an issued
 * document registry record (Patch B6b). Sandbox-only for B6b. Returns a small,
 * fully-sanitized object containing ONLY a Billit order LINK + local lifecycle
 * label — never an access/refresh token, never an encrypted token, never the
 * raw OAuth record, never the raw Billit response, never an Authorization
 * header. `status` is a LOCAL lifecycle label ("created"), not Billit's live UI
 * status. Returns { ok:false } when required link fields are missing/invalid so
 * the caller can fail closed without writing partial metadata. */
export function normalizeBillitExportMetadata(input = {}) {
  const src = input && typeof input === "object" ? input : {};
  const environment = safeStr(src.environment, 24).toLowerCase() || "sandbox";
  // B6b is sandbox-only; refuse anything else so production links never persist.
  if (environment !== "sandbox") {
    return { ok: false, error: "billit_export_sandbox_only" };
  }
  const orderId = safeStr(src.order_id ?? src.orderId, 120);
  if (!orderId) {
    return { ok: false, error: "billit_order_id_required" };
  }
  const orderNumber = safeStr(src.order_number ?? src.orderNumber, 80) || null;
  const partyId = safeStr(src.party_id ?? src.partyId, 120) || null;
  const idempotencyKey = safeStr(src.idempotency_key ?? src.idempotencyKey, 200) || null;
  const source = safeStr(src.source, 64) || "admin_sandbox_create";
  const nowIso = new Date().toISOString();
  const createdAt = safeStr(src.created_at ?? src.createdAt, 40) || nowIso;
  const updatedAt = safeStr(src.updated_at ?? src.updatedAt, 40) || nowIso;
  return {
    ok: true,
    export: {
      provider: "billit",
      environment: "sandbox",
      party_id: partyId,
      order_id: orderId,
      order_number: orderNumber,
      // LOCAL lifecycle label only. Never Billit's live UI status.
      status: "created",
      sent: false,
      peppol_sent: false,
      idempotency_key: idempotencyKey,
      source,
      created_at: createdAt,
      updated_at: updatedAt,
    },
  };
}

/* Pure builder: safe projection of a stored billit_export envelope (Patch B6b/
 * B7b). Accepts either a full document record (with .billit_export) or a bare
 * export object. Returns null when no order id is present. NEVER includes
 * tokens/secrets or raw provider bodies. */
export function buildSafeBillitExportProjection(recordOrExport) {
  const obj =
    recordOrExport && typeof recordOrExport === "object" && !Array.isArray(recordOrExport)
      ? recordOrExport
      : null;
  if (!obj) return null;
  const exp =
    obj.billit_export && typeof obj.billit_export === "object" && !Array.isArray(obj.billit_export)
      ? obj.billit_export
      : obj;
  const orderId = safeStr(exp.order_id ?? exp.orderId, 120) || null;
  if (!orderId) return null;
  return {
    provider: safeStr(exp.provider, 24) || "billit",
    environment: safeStr(exp.environment, 24) || null,
    party_id: safeStr(exp.party_id ?? exp.partyId, 120) || null,
    order_id: orderId,
    order_number: safeStr(exp.order_number ?? exp.orderNumber, 80) || null,
    status: safeStr(exp.status, 40) || null,
    sent: exp.sent === true,
    peppol_sent: exp.peppol_sent === true,
    idempotency_key: safeStr(exp.idempotency_key ?? exp.idempotencyKey, 200) || null,
    created_at: safeStr(exp.created_at ?? exp.createdAt, 40) || null,
    updated_at: safeStr(exp.updated_at ?? exp.updatedAt, 40) || null,
    source: safeStr(exp.source, 64) || null,
    // Envelope-only reconciled sent-state fields (Patch B7b). All safe, non-secret
    // lifecycle values; null before a reconcile has run. Never a raw Billit body.
    billit_status: safeStr(exp.billit_status, 80) || null,
    billit_is_sent: typeof exp.billit_is_sent === "boolean" ? exp.billit_is_sent : null,
    billit_paid: typeof exp.billit_paid === "boolean" ? exp.billit_paid : null,
    billit_paid_date: safeStr(exp.billit_paid_date ?? exp.billitPaidDate, 40) || null,
    billit_payment_sync_status: safeStr(exp.billit_payment_sync_status, 40) || null,
    billit_payment_synced_at: safeStr(exp.billit_payment_synced_at, 40) || null,
    billit_payment_sync_error: safeStr(exp.billit_payment_sync_error, 120) || null,
    transport_type: safeStr(exp.transport_type ?? exp.transportType, 24) || null,
    sent_at: safeStr(exp.sent_at ?? exp.sentAt, 40) || null,
    peppol_sent_at: safeStr(exp.peppol_sent_at ?? exp.peppolSentAt, 40) || null,
    status_checked_at: safeStr(exp.status_checked_at ?? exp.statusCheckedAt, 40) || null,
    send_pending: exp.send_pending === true,
    peppol_send_pending: exp.peppol_send_pending === true,
    reconcile_pending: exp.reconcile_pending === true,
  };
}

/* Pure builder (Patch B12-K) that marks a sandbox billit_export as Peppol-send
 * pending immediately after Billit accepts the send command, BEFORE reconcile
 * readback confirms is_sent. Preserves link-identity + prior lifecycle fields;
 * does NOT set sent/peppol_sent true. Concurrent/retry sends must fail closed
 * on the pending flags until reconcile clears them. */
export function buildBillitExportPeppolSendPendingEnvelope({ existingExport, nowIso }) {
  const src =
    existingExport && typeof existingExport === "object" && !Array.isArray(existingExport)
      ? existingExport
      : {};
  const now = safeStr(nowIso, 40) || new Date().toISOString();
  return {
    provider: safeStr(src.provider, 24) || "billit",
    environment: safeStr(src.environment, 24) || "sandbox",
    party_id: safeStr(src.party_id ?? src.partyId, 120) || null,
    order_id: safeStr(src.order_id ?? src.orderId, 120) || null,
    order_number: safeStr(src.order_number ?? src.orderNumber, 80) || null,
    idempotency_key: safeStr(src.idempotency_key ?? src.idempotencyKey, 200) || null,
    created_at: safeStr(src.created_at ?? src.createdAt, 40) || now,
    source: safeStr(src.source, 64) || "admin_sandbox_create",
    status: safeStr(src.status, 40) || "created",
    billit_status: safeStr(src.billit_status, 80) || null,
    billit_is_sent: typeof src.billit_is_sent === "boolean" ? src.billit_is_sent : null,
    billit_paid: typeof src.billit_paid === "boolean" ? src.billit_paid : null,
    billit_paid_date: safeStr(src.billit_paid_date ?? src.billitPaidDate, 40) || null,
    billit_payment_sync_status: safeStr(src.billit_payment_sync_status, 40) || null,
    billit_payment_synced_at: safeStr(src.billit_payment_synced_at, 40) || null,
    billit_payment_sync_error: safeStr(src.billit_payment_sync_error, 120) || null,
    sent: src.sent === true,
    peppol_sent: src.peppol_sent === true,
    sent_at: safeStr(src.sent_at ?? src.sentAt, 40) || null,
    peppol_sent_at: safeStr(src.peppol_sent_at ?? src.peppolSentAt, 40) || null,
    transport_type: "Peppol",
    status_checked_at: safeStr(src.status_checked_at ?? src.statusCheckedAt, 40) || null,
    updated_at: now,
    send_pending: true,
    peppol_send_pending: true,
    reconcile_pending: true,
  };
}

/* Pure builder (Patch B7b) that reconciles the stored envelope-only
 * billit_export with a SANITIZED live Billit order (output of
 * sanitizeBillitOrderReadResponse / fetchBillitSandboxOrderById) once Billit
 * confirms the order is sent. Preserves every link-identity field byte-for-byte
 * (provider/environment/party_id/order_id/order_number/idempotency_key/
 * created_at/source) and only ADDS/UPDATES envelope-level lifecycle fields.
 * NEVER includes the raw live order, Customer/Addresses/OrderLines/VAT/files, or
 * any token/secret. Idempotent on sent_at / peppol_sent_at (first-write-wins). */
export function buildReconciledBillitExportFromLiveStatus({
  existingExport,
  liveOrder,
  transportType,
  nowIso,
}) {
  const src =
    existingExport && typeof existingExport === "object" && !Array.isArray(existingExport)
      ? existingExport
      : {};
  const live =
    liveOrder && typeof liveOrder === "object" && !Array.isArray(liveOrder)
      ? liveOrder
      : {};
  const now = safeStr(nowIso, 40) || new Date().toISOString();
  const isPeppol = safeStr(transportType, 24) === "Peppol";
  const existingSentAt = safeStr(src.sent_at ?? src.sentAt, 40) || null;
  const existingPeppolSentAt = safeStr(src.peppol_sent_at ?? src.peppolSentAt, 40) || null;
  return {
    // Preserved link-identity fields (byte-for-byte from the stored export).
    provider: safeStr(src.provider, 24) || "billit",
    environment: safeStr(src.environment, 24) || "sandbox",
    party_id: safeStr(src.party_id ?? src.partyId, 120) || null,
    order_id: safeStr(src.order_id ?? src.orderId, 120) || null,
    order_number: safeStr(src.order_number ?? src.orderNumber, 80) || null,
    idempotency_key: safeStr(src.idempotency_key ?? src.idempotencyKey, 200) || null,
    created_at: safeStr(src.created_at ?? src.createdAt, 40) || now,
    source: safeStr(src.source, 64) || "admin_sandbox_create",
    // Envelope-level reconciled lifecycle (never the raw live order).
    status: "sent",
    billit_status: safeStr(live.order_status, 80) || null,
    billit_is_sent: live.is_sent === true,
    billit_paid: live.paid === true,
    sent: true,
    peppol_sent: isPeppol ? true : src.peppol_sent === true,
    sent_at: existingSentAt || now,
    peppol_sent_at: isPeppol ? existingPeppolSentAt || now : existingPeppolSentAt,
    transport_type: "Peppol",
    status_checked_at: now,
    updated_at: now,
    last_reconciled_by: "admin_sandbox_reconcile_sent",
    send_pending: false,
    peppol_send_pending: false,
    reconcile_pending: false,
  };
}
