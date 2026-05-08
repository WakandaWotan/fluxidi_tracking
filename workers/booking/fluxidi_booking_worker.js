/* -------- Google API helpers (hoisted at top to avoid any ReferenceError) -------- */

/* Build tag (helps verify which Worker is deployed) */
const FLUXIDI_BUILD = 'v36-2026-04-27-white-label-communication';
const BUILD_TAG = FLUXIDI_BUILD;

function buildScopedGoogleCalendarAuthKey(scope = null) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return null;
  return `tenant:${tenantId}:company:${companyId}:google_calendar_auth:v1`;
}

function hasExplicitCalendarTenantScope(scope = null) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return false;
  const resolutionMode = safeStr(
    scope?.tenant_resolution_mode ?? scope?.tenantResolutionMode,
    64,
  ).toLowerCase();
  if (resolutionMode === "legacy_fallback") return false;
  if (scope?.legacy_fallback === true || scope?.legacyFallback === true) return false;
  return true;
}

function shouldAllowGlobalGoogleCalendarFallback(env, scope = null) {
  if (!hasExplicitCalendarTenantScope(scope)) return true;

  const explicitAllowToggle = safeStr(
    env?.CALENDAR_ALLOW_GLOBAL_FALLBACK_FOR_SCOPED_TENANTS,
    24,
  ).toLowerCase();
  if (explicitAllowToggle === "true" || explicitAllowToggle === "1") return true;

  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return false;

  const allowlistRaw = safeStr(env?.CALENDAR_GLOBAL_FALLBACK_ALLOWLIST, 4096);
  if (!allowlistRaw) return false;
  const tenantLower = tenantId.toLowerCase();
  const companyLower = companyId.toLowerCase();
  const pairLower = `${tenantLower}:${companyLower}`;
  const entries = allowlistRaw
    .split(",")
    .map((entry) => safeStr(entry, 200).toLowerCase())
    .filter(Boolean);
  for (const entry of entries) {
    if (entry === pairLower || entry === tenantLower || entry === companyLower) {
      return true;
    }
  }
  return false;
}

const CALENDAR_OAUTH_NONCE_TTL_SECONDS = 600;
const CALENDAR_OAUTH_STATE_PURPOSE = "google_calendar_oauth";

function base64urlEncodeBytes(bytes) {
  const arr = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes || []);
  let binary = "";
  const chunkSize = 0x2000;
  for (let i = 0; i < arr.length; i += chunkSize) {
    const end = Math.min(i + chunkSize, arr.length);
    let chunk = "";
    for (let j = i; j < end; j++) chunk += String.fromCharCode(arr[j]);
    binary += chunk;
  }
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64urlDecodeToBytes(str) {
  const raw = String(str || "").trim();
  if (!raw) return new Uint8Array();
  const normalized = raw
    .replace(/-/g, "+")
    .replace(/_/g, "/")
    .padEnd(Math.ceil(raw.length / 4) * 4, "=");
  const bin = atob(normalized);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function jsonBase64urlEncode(obj) {
  const text = JSON.stringify(obj ?? {});
  const bytes = new TextEncoder().encode(text);
  return base64urlEncodeBytes(bytes);
}

function jsonBase64urlDecode(str) {
  const bytes = base64urlDecodeToBytes(str);
  const text = new TextDecoder().decode(bytes);
  return JSON.parse(text);
}

async function importHmacKey(secret) {
  const normalized = String(secret || "").trim();
  if (!normalized) throw new Error("missing_calendar_oauth_state_secret");
  const raw = new TextEncoder().encode(normalized);
  return crypto.subtle.importKey(
    "raw",
    raw,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign", "verify"],
  );
}

async function signCalendarOAuthState(payloadB64, secret) {
  const key = await importHmacKey(secret);
  const data = new TextEncoder().encode(String(payloadB64 || ""));
  const signature = await crypto.subtle.sign("HMAC", key, data);
  return base64urlEncodeBytes(new Uint8Array(signature));
}

async function verifyCalendarOAuthState(payloadB64, sigB64, secret) {
  const key = await importHmacKey(secret);
  const data = new TextEncoder().encode(String(payloadB64 || ""));
  const sig = base64urlDecodeToBytes(sigB64);
  if (!sig.length) return false;
  return crypto.subtle.verify("HMAC", key, sig, data);
}

async function _importCalendarEncryptionKey(env) {
  const rawSecret = String(env?.CALENDAR_AUTH_ENCRYPTION_KEY || "").trim();
  if (!rawSecret) throw new Error("missing_calendar_auth_encryption_key");
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

async function encryptCalendarRefreshToken(refreshToken, env) {
  const token = String(refreshToken || "");
  if (!token) throw new Error("missing_refresh_token");
  const key = await _importCalendarEncryptionKey(env);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plaintext = new TextEncoder().encode(token);
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    key,
    plaintext,
  );
  return {
    alg: "AES-GCM",
    kid: safeStr(env?.CALENDAR_AUTH_ENCRYPTION_KID, 32) || "v1",
    iv: base64urlEncodeBytes(iv),
    ciphertext: base64urlEncodeBytes(new Uint8Array(encrypted)),
  };
}

async function decryptCalendarRefreshToken(encryptedObj, env) {
  if (!encryptedObj || typeof encryptedObj !== "object") {
    throw new Error("invalid_encrypted_refresh_token");
  }
  const alg = String(encryptedObj.alg || "").trim();
  if (alg !== "AES-GCM") throw new Error("unsupported_encrypted_refresh_token_alg");
  const iv = base64urlDecodeToBytes(encryptedObj.iv);
  const ciphertext = base64urlDecodeToBytes(encryptedObj.ciphertext);
  if (!iv.length || !ciphertext.length) {
    throw new Error("invalid_encrypted_refresh_token_payload");
  }
  const key = await _importCalendarEncryptionKey(env);
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv },
    key,
    ciphertext,
  );
  return new TextDecoder().decode(new Uint8Array(decrypted));
}

function buildCalendarOAuthNonceKey(scope = null, nonce = "") {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const nonceId = String(nonce || "").trim().replace(/[^a-zA-Z0-9_-]+/g, "");
  if (!tenantId || !companyId || !nonceId) return null;
  return `tenant:${tenantId}:company:${companyId}:google_oauth_state_nonce:${nonceId}:v1`;
}

async function createCalendarOAuthNonce(env, scope) {
  if (!env?.BOOKING_KV) throw new Error("missing_booking_kv");
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) throw new Error("missing_tenant_scope");
  const nonce = (crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}_${Math.random()}`)
    .replace(/[^a-zA-Z0-9_-]+/g, "");
  const nowMs = Date.now();
  const expiresMs = nowMs + CALENDAR_OAUTH_NONCE_TTL_SECONDS * 1000;
  const key = buildCalendarOAuthNonceKey(
    { tenant_id: tenantId, company_id: companyId },
    nonce,
  );
  if (!key) throw new Error("invalid_oauth_nonce_key");
  const record = {
    purpose: CALENDAR_OAUTH_STATE_PURPOSE,
    tenant_id: tenantId,
    company_id: companyId,
    nonce,
    issued_at: new Date(nowMs).toISOString(),
    expires_at: new Date(expiresMs).toISOString(),
    consumed: false,
  };
  await env.BOOKING_KV.put(key, JSON.stringify(record), {
    expirationTtl: CALENDAR_OAUTH_NONCE_TTL_SECONDS,
  });
  return {
    nonce,
    issuedAt: record.issued_at,
    expiresAt: record.expires_at,
    expiresIn: CALENDAR_OAUTH_NONCE_TTL_SECONDS,
    key,
  };
}

async function consumeCalendarOAuthNonce(env, scope, nonce) {
  if (!env?.BOOKING_KV) {
    return { ok: false, code: "missing_booking_kv" };
  }
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const key = buildCalendarOAuthNonceKey(
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
  if (String(rec?.purpose || "") !== CALENDAR_OAUTH_STATE_PURPOSE) {
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

async function loadGoogleCalendarAuthConfig(env, scope = null) {
  const scopedKey = buildScopedGoogleCalendarAuthKey(scope);
  const baseClientId = safeStr(env?.GOOGLE_CLIENT_ID);
  const baseClientSecret = safeStr(env?.GOOGLE_CLIENT_SECRET);
  const baseRefreshToken = safeStr(env?.GOOGLE_REFRESH_TOKEN);
  const baseCalendarId = safeStr(env?.GOOGLE_CALENDAR_ID);
  let scopedErrorCode = null;

  if (scopedKey && env?.BOOKING_KV) {
    try {
      const raw = await env.BOOKING_KV.get(scopedKey, { type: "json" });
      const scoped = raw && typeof raw === "object"
        ? (raw.google_calendar_auth && typeof raw.google_calendar_auth === "object"
            ? raw.google_calendar_auth
            : raw)
        : null;
      if (scoped) {
        const connected = scoped.connected === undefined
          ? true
          : !!scoped.connected;
        const status = safeStr(scoped.status, 64) || null;
        const scopedClientId = safeStr(
          scoped.clientId ?? scoped.client_id ?? baseClientId,
        );
        const scopedClientSecret = safeStr(
          scoped.clientSecret ?? scoped.client_secret ?? baseClientSecret,
        );
        let scopedRefreshToken = "";
        if (
          scoped.refreshTokenEncrypted &&
          typeof scoped.refreshTokenEncrypted === "object"
        ) {
          try {
            scopedRefreshToken = safeStr(
              await decryptCalendarRefreshToken(scoped.refreshTokenEncrypted, env),
            );
          } catch (_) {
            scopedErrorCode = "scoped_token_decrypt_failed";
            console.log(
              `[CALENDAR_AUTH][WARN] source=scoped key=${scopedKey} reason=${scopedErrorCode}`,
            );
          }
        }
        if (!scopedRefreshToken) {
          // Phase 1/2 migration compatibility path:
          // plain refreshToken from KV is supported temporarily, but production
          // should store encrypted refresh tokens with key rotation.
          scopedRefreshToken = safeStr(
            scoped.refreshToken ?? scoped.refresh_token,
          );
        }
        const scopedCalendarId = safeStr(
          scoped.calendarId ?? scoped.calendar_id,
        ) || "primary";
        const accountEmail = safeStr(
          scoped.accountEmail ?? scoped.account_email,
          320,
        ) || null;
        const scopedConfigured =
          connected &&
          !!scopedClientId &&
          !!scopedClientSecret &&
          !!scopedRefreshToken;
        if (scopedConfigured) {
          return {
            source: "scoped",
            configured: true,
            clientId: scopedClientId,
            clientSecret: scopedClientSecret,
            refreshToken: scopedRefreshToken,
            calendarId: scopedCalendarId,
            status,
            accountEmail,
            scopedKey,
          };
        }
        if (scoped.connected !== undefined && scoped.connected !== null) {
          scopedErrorCode = scopedErrorCode || "scoped_not_usable";
        }
      }
    } catch (scopedErr) {
      scopedErrorCode = scopedErrorCode || "scoped_lookup_failed";
      console.log(
        `[CALENDAR_AUTH][WARN] source=scoped key=${scopedKey} reason=${safeStr(scopedErr?.message || scopedErr, 140) || scopedErrorCode}`,
      );
      // Best-effort scoped lookup. Global fallback remains available.
    }
  }

  const globalConfigured =
    !!baseClientId &&
    !!baseClientSecret &&
    !!baseRefreshToken &&
    !!baseCalendarId;
  if (globalConfigured) {
    // Global env Calendar fallback is disabled by default for explicit scoped
    // tenants to prevent cross-company calendar leakage.
    const allowGlobalFallback = shouldAllowGlobalGoogleCalendarFallback(
      env,
      scope,
    );
    if (!allowGlobalFallback) {
      const blockedTenant = sanitizeTenantString(
        scope?.tenant_id ?? scope?.tenantId,
        80,
      ) || "-";
      const blockedCompany = sanitizeTenantString(
        scope?.company_id ?? scope?.companyId,
        80,
      ) || "-";
      console.log(
        `[CALENDAR_AUTH][GLOBAL_FALLBACK_BLOCKED] tenant=${blockedTenant} company=${blockedCompany}`,
      );
      return {
        source: "none",
        configured: false,
        clientId: "",
        clientSecret: "",
        refreshToken: "",
        calendarId: "",
        status: null,
        accountEmail: null,
        scopedKey,
        scopedErrorCode: scopedErrorCode || "global_fallback_blocked",
      };
    }
    if (scopedErrorCode) {
      console.log(
        `[CALENDAR_AUTH][WARN] source=global_env reason=scoped_unusable code=${scopedErrorCode}`,
      );
    }
    return {
      source: "global_env",
      configured: true,
      clientId: baseClientId,
      clientSecret: baseClientSecret,
      refreshToken: baseRefreshToken,
      calendarId: baseCalendarId,
      status: null,
      accountEmail: null,
      scopedKey,
      scopedErrorCode,
    };
  }

  return {
    source: "none",
    configured: false,
    clientId: "",
    clientSecret: "",
    refreshToken: "",
    calendarId: "",
    status: null,
    accountEmail: null,
    scopedKey,
  };
}

async function googleAccessTokenFromConfig(config) {
  const clientId = safeStr(config?.clientId);
  const clientSecret = safeStr(config?.clientSecret);
  const refreshToken = safeStr(config?.refreshToken);
  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error("Google Calendar is not configured (missing client credentials or refresh token).");
  }

  const tokenUrl = 'https://oauth2.googleapis.com/token';
  const form = new URLSearchParams();
  form.set('client_id', clientId);
  form.set('client_secret', clientSecret);
  form.set('refresh_token', refreshToken);
  form.set('grant_type', 'refresh_token');

  const r = await fetch(tokenUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: form.toString(),
  });

  const j = await r.json().catch(() => ({}));
  if (!r.ok || !j.access_token) {
    throw new Error(j?.error_description || j?.error || 'Failed to refresh Google access token.');
  }
  return j.access_token;
}

/* Single source of truth for Google token refresh. */
async function googleAccessToken(env) {
  const cfg = await loadGoogleCalendarAuthConfig(env, null);
  if (!cfg?.configured) {
    throw new Error('Google Calendar is not configured (missing GOOGLE_CLIENT_ID/SECRET/REFRESH_TOKEN).');
  }
  return googleAccessTokenFromConfig(cfg);
}

/* Backward-compatible aliases (older code paths may call these). */
async function getGoogleAccessToken(env) { return googleAccessToken(env); }
async function refreshGoogleAccessToken(env) { return googleAccessToken(env); }

function isGoogleCalendarAuthError(err) {
  let serialized = "";
  try {
    serialized = JSON.stringify(err || {});
  } catch (_) {
    serialized = "";
  }
  const text = [
    err?.message,
    err?.error,
    typeof err === "string" ? err : "",
    serialized,
  ]
    .filter(Boolean)
    .join(" | ")
    .toLowerCase();
  if (!text) return false;
  return (
    text.includes("invalid_grant") ||
    text.includes("token has been expired or revoked") ||
    text.includes("expired or revoked") ||
    text.includes("unauthorized_client") ||
    text.includes("invalid_client") ||
    text.includes("failed to refresh google access token")
  );
}

// Extra safety: expose in global scope (helps when older code references global names).
try {
  globalThis.googleAccessToken = googleAccessToken;
  globalThis.getGoogleAccessToken = getGoogleAccessToken;
  globalThis.refreshGoogleAccessToken = refreshGoogleAccessToken;
} catch (_) {}


// ==============================
// Global numeric helpers (must be in module scope)
// ==============================
function toInt(value, fallback = 0) {
  const n = Number.parseInt(String(value ?? '').trim(), 10);
  return Number.isFinite(n) ? n : fallback;
}

function toNum(value, fallback = 0) {
  const n = Number(String(value ?? '').trim());
  return Number.isFinite(n) ? n : fallback;
}

function _adminTokenFromRequest(request, url) {
  const h = (request.headers.get("x-admin-token") || "").trim();
  if (h) return h;
  const auth = request.headers.get("authorization") || "";
  const m = auth.match(/^Bearer\s+(.+)$/i);
  if (m && (m[1] || "").trim()) return m[1].trim();
  return (url.searchParams.get("admin_token") || "").trim();
}

async function _allocatorRequest(env, pickupIso, payload) {
  if (!env?.FLEET_ALLOCATOR) throw new Error("FLEET_ALLOCATOR binding is missing");
  const tenantScope = normalizeFleetTenantScope(
    payload?.tenantScope ?? payload?.tenant_scope ?? payload,
  );
  const scopeKey = _fleetAllocatorScopeKey(pickupIso, tenantScope);
  const id = env.FLEET_ALLOCATOR.idFromName(scopeKey);
  const stub = env.FLEET_ALLOCATOR.get(id);
  const res = await stub.fetch("https://fleet-allocator/internal", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      ...payload,
      scope_key: scopeKey,
      tenant_id: tenantScope.tenant_id || undefined,
      company_id: tenantScope.company_id || undefined,
    }),
  });
  const out = await res.json().catch(() => ({}));
  if (!res.ok) {
    throw new Error(String(out?.error || "Fleet allocator failed"));
  }
  return out;
}

function _fleetAllocatorScopeKey(pickupIso, scope = null) {
  const normalizedScope = normalizeFleetTenantScope(scope);
  try {
    const d = new Date(pickupIso);
    if (isNaN(d.getTime())) {
      if (normalizedScope.hasScope) {
        return `fleet:${normalizedScope.tenant_id}:${normalizedScope.company_id}:invalid-date`;
      }
      return "fleet:invalid-date";
    }
    const day = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Europe/Brussels",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(d);
    if (normalizedScope.hasScope) {
      return `fleet:${normalizedScope.tenant_id}:${normalizedScope.company_id}:${day}`;
    }
    return `fleet:${day}`;
  } catch (_) {
    if (normalizedScope.hasScope) {
      return `fleet:${normalizedScope.tenant_id}:${normalizedScope.company_id}:fallback`;
    }
    return "fleet:fallback";
  }
}

function _bookingLifecycleValue(rec) {
  return (
    rec?.status ??
    rec?.stage ??
    rec?.booking?.status ??
    rec?.booking?.stage ??
    null
  );
}

export class FleetAllocatorDO {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    let body = {};
    try {
      body = await request.json();
    } catch (_) {
      body = {};
    }
    const action = String(body?.action || "").trim().toLowerCase();
    if (action === "allocate") return this._allocate(body);
    if (action === "release") return this._release(body);
    return new Response(JSON.stringify({ ok: false, error: "Unknown action" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  async _allocate(body) {
    const bookingId = String(body?.booking_id || "").trim();
    const pickupMs = Number(body?.pickup_ms);
    const serviceMin = Math.max(1, Number(body?.service_min) || 1);
    const tier = String(body?.tier || "comfort").trim().toLowerCase();
    const pax = Number(body?.pax ?? 1);
    const bags = Number(body?.bags ?? 0);
    if (!bookingId || !Number.isFinite(pickupMs)) {
      return this._json({ ok: false, error: "Invalid allocate request" }, 400);
    }

    const tenantScope = normalizeFleetTenantScope(body);
    const req = { pickupMs, serviceMin, tier, pax, bags, tenantScope };
    const reservations = await this._loadReservations();
    let reservationsDirty = false;

    // Idempotency for retried booking confirmation
    if (reservations[bookingId]?.vehicle_id) {
      let keepReservation = true;
      try {
        const linked = await this.env.BOOKING_KV.get(`booking:${bookingId}`, {
          type: "json",
        });
        if (!linked || isTerminalLifecycleStatus(_bookingLifecycleValue(linked))) {
          delete reservations[bookingId];
          reservationsDirty = true;
          keepReservation = false;
          console.log(
            `[FLEET][ALLOCATOR][PRUNE_STALE_RESERVATION] booking=${_bookingIntentMask(bookingId)} reason=${!linked ? "missing_booking" : "terminal_booking"}`,
          );
        }
      } catch (_) {
        // Best-effort stale-prune check only.
      }
      if (keepReservation) {
        if (reservationsDirty) {
          await this._saveReservations(reservations);
          reservationsDirty = false;
        }
        return this._json({
          ok: true,
          allowed: true,
          booking_id: bookingId,
          assigned_vehicle_id: reservations[bookingId].vehicle_id,
          source: "existing_reservation",
        });
      }
    }
    if (reservationsDirty) {
      await this._saveReservations(reservations);
      reservationsDirty = false;
    }

    const vehicles = await _loadVehicleInventory(this.env, { scope: tenantScope });
    const suitableVehicles = vehicles.filter((v) => _vehicleSupportsRequest(v, req));
    if (suitableVehicles.length === 0) {
      return this._json({
        ok: true,
        allowed: false,
        reason: "no_suitable_vehicle",
        suitable_vehicle_count: 0,
      });
    }

    const suitableIds = new Set(suitableVehicles.map((v) => v.vehicle_id));
    const occupiedAssignedIds = new Set();
    let overlappingUnassignedDemand = 0;

    // Existing persisted bookings from KV
    const listed = await this.env.BOOKING_KV.list({ prefix: "booking:", limit: 1000 });
    for (const k of listed?.keys || []) {
      const key = String(k?.name || "");
      if (!key.startsWith("booking:")) continue;
      const rec = await this.env.BOOKING_KV.get(key, { type: "json" });
      if (!rec || typeof rec !== "object") continue;
      if (!_bookingMatchesFleetScopeOrLegacyGlobal(rec, tenantScope)) continue;
      if (isTerminalLifecycleStatus(_bookingLifecycleValue(rec))) continue;
      const d = _bookingDemandFromRecord(rec, this.env);
      if (!Number.isFinite(d.pickupMs)) continue;
      if (!_windowsOverlap(req.pickupMs, req.serviceMin, d.pickupMs, d.serviceMin)) continue;
      const assignedVehicleId = _assignedVehicleIdFromRecord(rec);
      if (assignedVehicleId && suitableIds.has(assignedVehicleId)) {
        occupiedAssignedIds.add(assignedVehicleId);
        continue;
      }
      if (suitableVehicles.some((v) => _vehicleSupportsRequest(v, d))) {
        overlappingUnassignedDemand += 1;
      }
    }

    // Serialized in-flight reservations inside DO
    for (const [id, r] of Object.entries(reservations)) {
      if (!r || id === bookingId) continue;
      try {
        const linked = await this.env.BOOKING_KV.get(`booking:${id}`, { type: "json" });
        if (!linked || isTerminalLifecycleStatus(_bookingLifecycleValue(linked))) {
          delete reservations[id];
          reservationsDirty = true;
          console.log(
            `[FLEET][ALLOCATOR][PRUNE_STALE_RESERVATION] booking=${_bookingIntentMask(id)} reason=${!linked ? "missing_booking" : "terminal_booking"}`,
          );
          continue;
        }
      } catch (_) {
        // Best-effort stale-prune check only.
      }
      const rPickup = Number(r.pickup_ms);
      const rService = Math.max(1, Number(r.service_min) || 1);
      if (!Number.isFinite(rPickup)) continue;
      if (!_windowsOverlap(req.pickupMs, req.serviceMin, rPickup, rService)) continue;
      const rv = String(r.vehicle_id || "").trim();
      if (rv && suitableIds.has(rv)) {
        occupiedAssignedIds.add(rv);
      }
    }
    if (reservationsDirty) {
      await this._saveReservations(reservations);
      reservationsDirty = false;
    }

    const freeVehicles = suitableVehicles
      .filter((v) => !occupiedAssignedIds.has(v.vehicle_id))
      .sort((a, b) => String(a.vehicle_id).localeCompare(String(b.vehicle_id)));
    const availableSlots = freeVehicles.length - overlappingUnassignedDemand;
    if (availableSlots <= 0 || freeVehicles.length === 0) {
      return this._json({
        ok: true,
        allowed: false,
        reason: "vehicle_capacity_exceeded",
        suitable_vehicle_count: suitableVehicles.length,
        occupied_assigned_count: occupiedAssignedIds.size,
        overlapping_unassigned_demand: overlappingUnassignedDemand,
        available_slots: Math.max(0, availableSlots),
      });
    }

    const chosen = freeVehicles[0];
    reservations[bookingId] = {
      vehicle_id: chosen.vehicle_id,
      pickup_ms: req.pickupMs,
      service_min: req.serviceMin,
      created_at: Date.now(),
    };
    await this._saveReservations(reservations);
    return this._json({
      ok: true,
      allowed: true,
      booking_id: bookingId,
      assigned_vehicle_id: chosen.vehicle_id,
      assigned_driver: _assignedDriverFromVehicle(chosen),
      source: "new_reservation",
    });
  }

  async _release(body) {
    const bookingId = String(body?.booking_id || "").trim();
    if (!bookingId) return this._json({ ok: false, error: "booking_id required" }, 400);
    const reservations = await this._loadReservations();
    delete reservations[bookingId];
    await this._saveReservations(reservations);
    return this._json({ ok: true, released: true, booking_id: bookingId });
  }

  async _loadReservations() {
    const r = await this.state.storage.get("reservations");
    return r && typeof r === "object" ? r : {};
  }

  async _saveReservations(v) {
    await this.state.storage.put("reservations", v);
  }

  _json(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

export class BookingReferenceSequenceDO {
  constructor(stateOrCtx, env) {
    this.state = stateOrCtx;
    this.env = env;
  }

  async fetch(request) {
    let body = {};
    try {
      body = await request.json();
    } catch (_) {
      body = {};
    }
    const action = String(body?.action || "").trim().toLowerCase();
    if (action !== "allocate") {
      return this._json({ ok: false, error: "Unknown action" }, 400);
    }
    return this._allocate(body);
  }

  async _allocate(body) {
    const tenantId = safeStr(body?.tenant_id || body?.tenantId, 120) || "fluxidi";
    const companyId = safeStr(body?.company_id || body?.companyId, 120) || tenantId;
    const yearMonth =
      normalizeBookingReferenceYearMonth(body?.year_month || body?.yearMonth) ||
      bookingReferenceYearMonthFromPickupIso(body?.pickup_iso || body?.pickupIso) ||
      bookingReferenceYearMonthFromPickupIso(new Date().toISOString());
    if (!yearMonth) {
      return this._json({ ok: false, error: "Unable to resolve year_month" }, 400);
    }

    const next = await this.state.storage.transaction(async (txn) => {
      const current = clampInt(await txn.get("next"), 0, 999999999);
      const nextValue = current + 1;
      await txn.put("next", nextValue);
      return nextValue;
    });

    const publicBookingReference = `${yearMonth}-${String(next).padStart(6, "0")}`;
    return this._json({
      ok: true,
      tenant_id: tenantId,
      company_id: companyId,
      year_month: yearMonth,
      seq: next,
      public_booking_reference: publicBookingReference,
      publicBookingReference: publicBookingReference,
      booking_reference: publicBookingReference,
      bookingReference: publicBookingReference,
    });
  }

  _json(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

export class DocumentReferenceSequenceDO {
  constructor(stateOrCtx, env) {
    this.state = stateOrCtx;
    this.env = env;
  }

  async fetch(request) {
    let body = {};
    try {
      body = await request.json();
    } catch (_) {
      body = {};
    }
    const action = String(body?.action || "").trim().toLowerCase();
    if (action !== "allocate") {
      return this._json({ ok: false, error: "Unknown action" }, 400);
    }
    return this._allocate(body);
  }

  async _allocate(body) {
    const tenantId = safeStr(body?.tenant_id || body?.tenantId, 120) || "fluxidi";
    const companyId = safeStr(body?.company_id || body?.companyId, 120) || tenantId;
    const sequenceType = documentReferenceTypePart(
      body?.sequence_type || body?.sequenceType || body?.type,
      "",
    );
    if (!sequenceType) {
      return this._json({ ok: false, error: "Missing sequence_type" }, 400);
    }
    const prefix = safeStr(
      body?.prefix || body?.reference_prefix || body?.referencePrefix,
      16,
    ).toUpperCase();
    if (!prefix) {
      return this._json({ ok: false, error: "Missing prefix" }, 400);
    }
    const year =
      normalizeDocumentReferenceYear(body?.year) ||
      documentReferenceYearFromPickupIso(body?.pickup_iso || body?.pickupIso) ||
      documentReferenceYearFromPickupIso(new Date().toISOString());
    if (!year) {
      return this._json({ ok: false, error: "Unable to resolve year" }, 400);
    }

    const next = await this.state.storage.transaction(async (txn) => {
      const current = clampInt(await txn.get("next"), 0, 999999999);
      const nextValue = current + 1;
      await txn.put("next", nextValue);
      return nextValue;
    });

    const documentReference = `${prefix}-${year}-${String(next).padStart(6, "0")}`;
    return this._json({
      ok: true,
      tenant_id: tenantId,
      company_id: companyId,
      sequence_type: sequenceType,
      prefix,
      year,
      seq: next,
      document_reference: documentReference,
      documentReference,
    });
  }

  _json(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

function _requireAdmin(request, url, env) {
  const expected = (env.ADMIN_TOKEN || "").trim();
  if (!expected) throw new Error("ADMIN_TOKEN is not configured");
  const got = _adminTokenFromRequest(request, url);
  if (!got || got !== expected) throw new Error("Unauthorized");
}

function hasValidAdminToken(request, url, env) {
  const expected = (env?.ADMIN_TOKEN || "").trim();
  if (!expected) return false;
  const got = _adminTokenFromRequest(request, url);
  return !!got && got === expected;
}

function allowDevResetEndpoints(env) {
  return String(env?.ALLOW_DEV_RESET_ENDPOINTS || "").trim().toLowerCase() === "true";
}

const TENANT_BUSINESS_PROFILE_KEY = "tenant:business_profile:v1";
const TENANT_TAX_PROFILE_KEY = "tenant:tax_profile:v1";
const TENANT_SUBSCRIPTION_PROFILE_KEY = "tenant:subscription:v1";
const TENANT_COMMUNICATION_TEMPLATES_KEY = "tenant:communication_templates:v1";

const DEFAULT_BUSINESS_PROFILE = {
  version: 1,
  companyName: "Fluxidi Taxi",
  legalName: "Fluxidi Taxi",
  vatNumber: "",
  companyRegistrationNumber: "",
  address: "",
  postcode: "",
  city: "",
  country: "BE",
  phone: "",
  companyEmail: "",
  email: "",
  supportEmail: "",
  replyToEmail: "",
  website: "",
  publicLogoUrl: "",
  publicHeroPhotoUrl: "",
  publicServedPostcodes: "",
  publicPartnerProfilePublishedAt: "",
  publicPartnerProfilePublishStatus: "",
  invoiceEmail: "",
  billingEmail: "",
  notificationEmail: "",
  bookingEmail: "",
  iban: "",
  paymentReferencePrefix: "FLX",
  invoiceReceiptFooterText: "",
};

const DEFAULT_TAX_PROFILE = {
  version: 1,
  vatEnabled: true,
  vatRate: 0.06,
  vatDisplayMode: "excl",
  vatLabels: {
    nl: "BTW",
    en: "VAT",
    fr: "TVA",
    es: "IVA",
  },
};

const DEFAULT_SUBSCRIPTION_PROFILE = {
  version: 1,
  tenant_id: "",
  company_id: "",
  plan: "starter",
  status: "trialing",
  trial_started_at: "",
  trial_ends_at: "",
  billing_email: "",
  included_vehicles: 1,
  max_vehicles: 1,
  max_drivers: 3,
  features: {
    ai_assistant: false,
    airport_module: false,
    live_dispatch: false,
    ev_dispatch: false,
    compliance_dashboard: true,
    white_label_branding: false,
    public_booking: false,
    receipt_pdf: true,
    whatsapp_email_receipts: true,
  },
  created_at: "",
  updated_at: "",
};

const DEFAULT_COMMUNICATION_TEMPLATES = {
  version: 1,
  templates: {
    nl: {
      bookingConfirmationEmailSubject: "Bevestiging van je Fluxidi rit {bookingId}",
      bookingConfirmationEmailBody: "Dag {customerName}, je rit van {pickup} naar {destination} is bevestigd. Totaal: {priceTotal}.",
      invoiceEmailSubject: "Factuur {bookingId}",
      invoiceEmailBody: "Dag {customerName}, in bijlage vindt u uw factuur.",
      receiptEmailSubject: "Uw ritbon {bookingId}",
      receiptEmailBody: "Dag {customerName}, hierbij ontvangt u uw ritbon.",
      paymentRequestEmailText: "Gelieve de betaling te voldoen via {paymentLink}.",
      paymentRequestWhatsAppText: "Betaalverzoek voor rit {bookingId}: {paymentLink}",
      receiptWhatsAppText: "Ritbon {bookingId}: {pickup} naar {destination}, totaal {priceTotal}.",
      footerDisclaimerText: "{companyName} - bedankt voor uw vertrouwen.",
    },
    en: {
      bookingConfirmationEmailSubject: "Your Fluxidi ride confirmation {bookingId}",
      bookingConfirmationEmailBody: "Hello {customerName}, your ride from {pickup} to {destination} is confirmed. Total: {priceTotal}.",
      invoiceEmailSubject: "Invoice {bookingId}",
      invoiceEmailBody: "Hello {customerName}, please find your invoice attached.",
      receiptEmailSubject: "Your ride receipt {bookingId}",
      receiptEmailBody: "Hello {customerName}, please find your ride receipt.",
      paymentRequestEmailText: "Please complete your payment via {paymentLink}.",
      paymentRequestWhatsAppText: "Payment request for ride {bookingId}: {paymentLink}",
      receiptWhatsAppText: "Ride receipt {bookingId}: {pickup} to {destination}, total {priceTotal}.",
      footerDisclaimerText: "{companyName} - thank you for your trust.",
    },
    fr: {
      bookingConfirmationEmailSubject: "Confirmation de votre trajet Fluxidi {bookingId}",
      bookingConfirmationEmailBody: "Bonjour {customerName}, votre trajet de {pickup} vers {destination} est confirme. Total : {priceTotal}.",
      invoiceEmailSubject: "Facture {bookingId}",
      invoiceEmailBody: "Bonjour {customerName}, veuillez trouver votre facture en piece jointe.",
      receiptEmailSubject: "Votre recu de course {bookingId}",
      receiptEmailBody: "Bonjour {customerName}, voici votre recu de course.",
      paymentRequestEmailText: "Veuillez effectuer le paiement via {paymentLink}.",
      paymentRequestWhatsAppText: "Demande de paiement pour la course {bookingId} : {paymentLink}",
      receiptWhatsAppText: "Recu {bookingId} : {pickup} vers {destination}, total {priceTotal}.",
      footerDisclaimerText: "{companyName} - merci pour votre confiance.",
    },
    es: {
      bookingConfirmationEmailSubject: "Confirmacion de tu viaje Fluxidi {bookingId}",
      bookingConfirmationEmailBody: "Hola {customerName}, tu viaje de {pickup} a {destination} esta confirmado. Total: {priceTotal}.",
      invoiceEmailSubject: "Factura {bookingId}",
      invoiceEmailBody: "Hola {customerName}, adjuntamos tu factura.",
      receiptEmailSubject: "Tu recibo de viaje {bookingId}",
      receiptEmailBody: "Hola {customerName}, aqui tienes tu recibo de viaje.",
      paymentRequestEmailText: "Por favor completa el pago mediante {paymentLink}.",
      paymentRequestWhatsAppText: "Solicitud de pago para el viaje {bookingId}: {paymentLink}",
      receiptWhatsAppText: "Recibo {bookingId}: {pickup} a {destination}, total {priceTotal}.",
      footerDisclaimerText: "{companyName} - gracias por tu confianza.",
    },
  },
};

const TENANT_TEMPLATE_LANGUAGES = ["nl", "en", "fr", "es"];
const TENANT_TEMPLATE_FIELDS = [
  "bookingConfirmationEmailSubject",
  "bookingConfirmationEmailBody",
  "invoiceEmailSubject",
  "invoiceEmailBody",
  "receiptEmailSubject",
  "receiptEmailBody",
  "paymentRequestEmailText",
  "paymentRequestWhatsAppText",
  "receiptWhatsAppText",
  "footerDisclaimerText",
];

function sanitizeTenantString(value, maxLength = 240) {
  const text = String(value == null ? "" : value).replace(/\0/g, "").trim();
  return text.length > maxLength ? text.slice(0, maxLength) : text;
}

function normalizeBusinessProfile(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  const companyEmail = sanitizeTenantString(
    source.companyEmail ??
    source.company_email ??
    source.infoEmail ??
    source.info_email ??
    source.email ??
    DEFAULT_BUSINESS_PROFILE.companyEmail,
    160
  );
  const email = sanitizeTenantString(
    source.email ??
    source.companyEmail ??
    source.company_email ??
    source.infoEmail ??
    source.info_email ??
    DEFAULT_BUSINESS_PROFILE.email,
    160
  );
  return {
    version: 1,
    companyName: sanitizeTenantString(source.companyName ?? DEFAULT_BUSINESS_PROFILE.companyName, 120),
    legalName: sanitizeTenantString(source.legalName ?? DEFAULT_BUSINESS_PROFILE.legalName, 160),
    vatNumber: sanitizeTenantString(source.vatNumber ?? source.vat_number ?? DEFAULT_BUSINESS_PROFILE.vatNumber, 64),
    companyRegistrationNumber: sanitizeTenantString(source.companyRegistrationNumber ?? source.registrationNumber ?? DEFAULT_BUSINESS_PROFILE.companyRegistrationNumber, 80),
    address: sanitizeTenantString(source.address ?? DEFAULT_BUSINESS_PROFILE.address, 220),
    postcode: sanitizeTenantString(source.postcode ?? source.postalCode ?? DEFAULT_BUSINESS_PROFILE.postcode, 24),
    city: sanitizeTenantString(source.city ?? DEFAULT_BUSINESS_PROFILE.city, 80),
    country: sanitizeTenantString(source.country ?? DEFAULT_BUSINESS_PROFILE.country, 64),
    phone: sanitizeTenantString(source.phone ?? DEFAULT_BUSINESS_PROFILE.phone, 64),
    companyEmail,
    email,
    supportEmail: sanitizeTenantString(source.supportEmail ?? source.support_email ?? DEFAULT_BUSINESS_PROFILE.supportEmail, 160),
    replyToEmail: sanitizeTenantString(source.replyToEmail ?? source.reply_to_email ?? source.reply_to ?? DEFAULT_BUSINESS_PROFILE.replyToEmail, 160),
    website: sanitizeTenantString(source.website ?? DEFAULT_BUSINESS_PROFILE.website, 200),
    publicLogoUrl: sanitizeTenantString(
      source.publicLogoUrl ??
      source.public_logo_url ??
      DEFAULT_BUSINESS_PROFILE.publicLogoUrl,
      600
    ),
    publicHeroPhotoUrl: sanitizeTenantString(
      source.publicHeroPhotoUrl ??
      source.public_hero_photo_url ??
      DEFAULT_BUSINESS_PROFILE.publicHeroPhotoUrl,
      600
    ),
    publicServedPostcodes: sanitizeTenantString(
      source.publicServedPostcodes ??
      source.public_served_postcodes ??
      DEFAULT_BUSINESS_PROFILE.publicServedPostcodes,
      1200
    ),
    publicPartnerProfilePublishedAt: sanitizeTenantString(
      source.publicPartnerProfilePublishedAt ??
      source.public_partner_profile_published_at ??
      DEFAULT_BUSINESS_PROFILE.publicPartnerProfilePublishedAt,
      80
    ),
    publicPartnerProfilePublishStatus: sanitizeTenantString(
      source.publicPartnerProfilePublishStatus ??
      source.public_partner_profile_publish_status ??
      DEFAULT_BUSINESS_PROFILE.publicPartnerProfilePublishStatus,
      32
    ).toLowerCase(),
    invoiceEmail: sanitizeTenantString(source.invoiceEmail ?? source.invoice_email ?? DEFAULT_BUSINESS_PROFILE.invoiceEmail, 160),
    billingEmail: sanitizeTenantString(source.billingEmail ?? source.billing_email ?? source.invoiceEmail ?? source.invoice_email ?? DEFAULT_BUSINESS_PROFILE.billingEmail, 160),
    notificationEmail: sanitizeTenantString(source.notificationEmail ?? source.notification_email ?? DEFAULT_BUSINESS_PROFILE.notificationEmail, 160),
    bookingEmail: sanitizeTenantString(
      source.bookingEmail ??
      source.bookingsEmail ??
      source.reservationEmail ??
      source.reservationsEmail ??
      source.dispatchEmail ??
      source.notificationEmail ??
      source.notification_email ??
      DEFAULT_BUSINESS_PROFILE.bookingEmail,
      160
    ),
    iban: sanitizeTenantString(source.iban ?? source.bankAccount ?? DEFAULT_BUSINESS_PROFILE.iban, 80),
    paymentReferencePrefix: sanitizeTenantString(source.paymentReferencePrefix ?? DEFAULT_BUSINESS_PROFILE.paymentReferencePrefix, 24),
    invoiceReceiptFooterText: sanitizeTenantString(source.invoiceReceiptFooterText ?? DEFAULT_BUSINESS_PROFILE.invoiceReceiptFooterText, 1000),
  };
}

function normalizeTaxProfile(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  const vatRateRaw = Number(source.vatRate ?? source.vat_rate ?? DEFAULT_TAX_PROFILE.vatRate);
  const vatRate = Number.isFinite(vatRateRaw)
    ? Math.max(0, Math.min(1, vatRateRaw))
    : DEFAULT_TAX_PROFILE.vatRate;
  const vatDisplayModeRaw = String(source.vatDisplayMode ?? source.vat_mode ?? DEFAULT_TAX_PROFILE.vatDisplayMode).trim().toLowerCase();
  const labels = source.vatLabels && typeof source.vatLabels === "object" ? source.vatLabels : {};
  return {
    version: 1,
    vatEnabled: typeof source.vatEnabled === "boolean" ? source.vatEnabled : DEFAULT_TAX_PROFILE.vatEnabled,
    vatRate,
    vatDisplayMode: vatDisplayModeRaw === "incl" ? "incl" : "excl",
    vatLabels: {
      nl: sanitizeTenantString(labels.nl ?? DEFAULT_TAX_PROFILE.vatLabels.nl, 32),
      en: sanitizeTenantString(labels.en ?? DEFAULT_TAX_PROFILE.vatLabels.en, 32),
      fr: sanitizeTenantString(labels.fr ?? DEFAULT_TAX_PROFILE.vatLabels.fr, 32),
      es: sanitizeTenantString(labels.es ?? DEFAULT_TAX_PROFILE.vatLabels.es, 32),
    },
  };
}

function normalizeSubscriptionProfile(input = {}, scope = null) {
  const source = input && typeof input === "object" ? input : {};
  const scopeTenant = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const scopeCompany = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  let tenantId = sanitizeTenantString(
    source.tenant_id ?? source.tenantId ?? scopeTenant ?? "",
    80,
  );
  let companyId = sanitizeTenantString(
    source.company_id ?? source.companyId ?? scopeCompany ?? "",
    80,
  );
  if (!tenantId && companyId) tenantId = companyId;
  if (!companyId && tenantId) companyId = tenantId;

  const allowedPlans = new Set(["starter", "pro", "business", "enterprise"]);
  const allowedStatuses = new Set(["trialing", "active", "past_due", "canceled", "suspended"]);
  const rawPlan = sanitizeTenantString(source.plan ?? DEFAULT_SUBSCRIPTION_PROFILE.plan, 32).toLowerCase();
  const rawStatus = sanitizeTenantString(source.status ?? DEFAULT_SUBSCRIPTION_PROFILE.status, 32).toLowerCase();
  const inFeatures = source.features && typeof source.features === "object" ? source.features : {};
  const defaultFeatures = DEFAULT_SUBSCRIPTION_PROFILE.features;

  return {
    version: 1,
    tenant_id: tenantId,
    company_id: companyId,
    plan: allowedPlans.has(rawPlan) ? rawPlan : DEFAULT_SUBSCRIPTION_PROFILE.plan,
    status: allowedStatuses.has(rawStatus) ? rawStatus : DEFAULT_SUBSCRIPTION_PROFILE.status,
    trial_started_at: sanitizeTenantString(source.trial_started_at ?? source.trialStartedAt ?? DEFAULT_SUBSCRIPTION_PROFILE.trial_started_at, 48),
    trial_ends_at: sanitizeTenantString(source.trial_ends_at ?? source.trialEndsAt ?? DEFAULT_SUBSCRIPTION_PROFILE.trial_ends_at, 48),
    billing_email: sanitizeTenantString(source.billing_email ?? source.billingEmail ?? DEFAULT_SUBSCRIPTION_PROFILE.billing_email, 160),
    included_vehicles: Math.max(0, clampInt(source.included_vehicles ?? source.includedVehicles, DEFAULT_SUBSCRIPTION_PROFILE.included_vehicles)),
    max_vehicles: Math.max(0, clampInt(source.max_vehicles ?? source.maxVehicles, DEFAULT_SUBSCRIPTION_PROFILE.max_vehicles)),
    max_drivers: Math.max(0, clampInt(source.max_drivers ?? source.maxDrivers, DEFAULT_SUBSCRIPTION_PROFILE.max_drivers)),
    features: {
      ai_assistant: typeof inFeatures.ai_assistant === "boolean" ? inFeatures.ai_assistant : defaultFeatures.ai_assistant,
      airport_module: typeof inFeatures.airport_module === "boolean" ? inFeatures.airport_module : defaultFeatures.airport_module,
      live_dispatch: typeof inFeatures.live_dispatch === "boolean" ? inFeatures.live_dispatch : defaultFeatures.live_dispatch,
      ev_dispatch: typeof inFeatures.ev_dispatch === "boolean" ? inFeatures.ev_dispatch : defaultFeatures.ev_dispatch,
      compliance_dashboard: typeof inFeatures.compliance_dashboard === "boolean" ? inFeatures.compliance_dashboard : defaultFeatures.compliance_dashboard,
      white_label_branding: typeof inFeatures.white_label_branding === "boolean" ? inFeatures.white_label_branding : defaultFeatures.white_label_branding,
      public_booking: typeof inFeatures.public_booking === "boolean" ? inFeatures.public_booking : defaultFeatures.public_booking,
      receipt_pdf: typeof inFeatures.receipt_pdf === "boolean" ? inFeatures.receipt_pdf : defaultFeatures.receipt_pdf,
      whatsapp_email_receipts: typeof inFeatures.whatsapp_email_receipts === "boolean" ? inFeatures.whatsapp_email_receipts : defaultFeatures.whatsapp_email_receipts,
    },
    created_at: sanitizeTenantString(source.created_at ?? source.createdAt ?? DEFAULT_SUBSCRIPTION_PROFILE.created_at, 48),
    updated_at: sanitizeTenantString(source.updated_at ?? source.updatedAt ?? DEFAULT_SUBSCRIPTION_PROFILE.updated_at, 48),
  };
}

function normalizeCommunicationTemplates(input = {}) {
  const source = input && typeof input === "object" ? input : {};
  const sourceTemplates = source.templates && typeof source.templates === "object"
    ? source.templates
    : source;
  const out = { version: 1, templates: {} };
  for (const lang of TENANT_TEMPLATE_LANGUAGES) {
    const defaults = DEFAULT_COMMUNICATION_TEMPLATES.templates[lang];
    const incoming = sourceTemplates[lang] && typeof sourceTemplates[lang] === "object"
      ? sourceTemplates[lang]
      : {};
    out.templates[lang] = {};
    for (const field of TENANT_TEMPLATE_FIELDS) {
      const value = incoming[field];
      out.templates[lang][field] = typeof value === "string"
        ? sanitizeTenantString(value, 4000)
        : defaults[field];
    }
  }
  return out;
}

function resolveAdminSettingsScope({ request, url, body = null } = {}) {
  const tenantFromQuery = sanitizeTenantString(
    url?.searchParams?.get("tenant_id") ?? url?.searchParams?.get("tenantId"),
    80,
  );
  const companyFromQuery = sanitizeTenantString(
    url?.searchParams?.get("company_id") ?? url?.searchParams?.get("companyId"),
    80,
  );
  const tenantFromBody = sanitizeTenantString(body?.tenant_id ?? body?.tenantId, 80);
  const companyFromBody = sanitizeTenantString(body?.company_id ?? body?.companyId, 80);
  const tenantFromHeader = sanitizeTenantString(
    request?.headers?.get?.("x-tenant-id") ?? request?.headers?.get?.("x-tenant"),
    80,
  );
  const companyFromHeader = sanitizeTenantString(
    request?.headers?.get?.("x-company-id") ?? request?.headers?.get?.("x-company"),
    80,
  );

  let tenantId =
    tenantFromQuery ||
    tenantFromBody ||
    tenantFromHeader ||
    "";
  let companyId =
    companyFromQuery ||
    companyFromBody ||
    companyFromHeader ||
    "";
  if (!tenantId && companyId) tenantId = companyId;
  if (!companyId && tenantId) companyId = tenantId;
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId && companyId),
  };
}

function buildScopedSettingsKeys(scope) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return null;
  return {
    businessProfileKey: `tenant:${tenantId}:company:${companyId}:business_profile:v1`,
    taxProfileKey: `tenant:${tenantId}:company:${companyId}:tax_profile:v1`,
    pricingProfileKey: `tenant:${tenantId}:company:${companyId}:pricing:v1`,
    subscriptionProfileKey: `tenant:${tenantId}:company:${companyId}:subscription:v1`,
  };
}

function communicationTemplatesScopedKeyForScope(scope) {
  const tenantId = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const companyId = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  if (!tenantId || !companyId) return "";
  return `tenant:${tenantId}:company:${companyId}:communication_templates:v1`;
}

function resolveAdminExplicitTenantCompanyScope({ request, url, body = null } = {}) {
  const resolved = resolveAdminSettingsScope({ request, url, body });
  const tenantExplicit = sanitizeTenantString(
    url?.searchParams?.get("tenant_id") ??
      url?.searchParams?.get("tenantId") ??
      body?.tenant_id ??
      body?.tenantId ??
      request?.headers?.get?.("x-tenant-id") ??
      request?.headers?.get?.("x-tenant"),
    80,
  );
  const companyExplicit = sanitizeTenantString(
    url?.searchParams?.get("company_id") ??
      url?.searchParams?.get("companyId") ??
      body?.company_id ??
      body?.companyId ??
      request?.headers?.get?.("x-company-id") ??
      request?.headers?.get?.("x-company"),
    80,
  );
  if (!tenantExplicit || !companyExplicit) return null;
  return {
    tenant_id: tenantExplicit,
    company_id: companyExplicit,
    hasScope: true,
    resolved_scope: resolved,
  };
}

function _validateSettingsPayloadScope(payload, scope) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return { ok: true };
  }
  const scopeTenant = sanitizeTenantString(scope?.tenant_id ?? scope?.tenantId, 80);
  const scopeCompany = sanitizeTenantString(scope?.company_id ?? scope?.companyId, 80);
  const payloadTenantSnake = sanitizeTenantString(payload.tenant_id, 80);
  const payloadTenantCamel = sanitizeTenantString(payload.tenantId, 80);
  const payloadCompanySnake = sanitizeTenantString(payload.company_id, 80);
  const payloadCompanyCamel = sanitizeTenantString(payload.companyId, 80);
  const tenantValues = [payloadTenantSnake, payloadTenantCamel].filter((v) => !!v);
  const companyValues = [payloadCompanySnake, payloadCompanyCamel].filter((v) => !!v);
  if (tenantValues.some((v) => v !== scopeTenant)) {
    return { ok: false, error: "settings payload scope does not match request scope" };
  }
  if (companyValues.some((v) => v !== scopeCompany)) {
    return { ok: false, error: "settings payload scope does not match request scope" };
  }
  return { ok: true };
}

async function loadBusinessProfile(
  env,
  scope = null,
  { allowTenantLegacyFallback = true } = {},
) {
  if (!env?.BOOKING_KV) return normalizeBusinessProfile(DEFAULT_BUSINESS_PROFILE);
  const scopedKeys = buildScopedSettingsKeys(scope);
  let raw = null;
  if (scopedKeys) {
    raw = await env.BOOKING_KV.get(scopedKeys.businessProfileKey, { type: "json" });
  }
  if (!raw && allowTenantLegacyFallback) {
    raw = await env.BOOKING_KV.get(TENANT_BUSINESS_PROFILE_KEY, { type: "json" });
  }
  return normalizeBusinessProfile(raw?.business_profile ?? raw ?? DEFAULT_BUSINESS_PROFILE);
}

async function saveBusinessProfile(
  env,
  profile,
  scope = null,
  { allowTenantLegacyWrite = true } = {},
) {
  if (!env?.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const normalized = normalizeBusinessProfile(profile);
  const scopedKeys = buildScopedSettingsKeys(scope);
  const targetKey = scopedKeys?.businessProfileKey ||
    (allowTenantLegacyWrite ? TENANT_BUSINESS_PROFILE_KEY : "");
  if (!targetKey) throw new Error("missing_tenant_scope");
  await env.BOOKING_KV.put(targetKey, JSON.stringify({
    version: 1,
    updated_at: new Date().toISOString(),
    business_profile: normalized,
  }));
  return normalized;
}

async function loadTaxProfile(
  env,
  scope = null,
  { allowTenantLegacyFallback = true } = {},
) {
  if (!env?.BOOKING_KV) return normalizeTaxProfile(DEFAULT_TAX_PROFILE);
  const scopedKeys = buildScopedSettingsKeys(scope);
  let raw = null;
  if (scopedKeys) {
    raw = await env.BOOKING_KV.get(scopedKeys.taxProfileKey, { type: "json" });
  }
  if (!raw && allowTenantLegacyFallback) {
    raw = await env.BOOKING_KV.get(TENANT_TAX_PROFILE_KEY, { type: "json" });
  }
  return normalizeTaxProfile(raw?.tax_profile ?? raw ?? DEFAULT_TAX_PROFILE);
}

async function saveTaxProfile(
  env,
  profile,
  scope = null,
  { allowTenantLegacyWrite = true } = {},
) {
  if (!env?.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const normalized = normalizeTaxProfile(profile);
  const scopedKeys = buildScopedSettingsKeys(scope);
  const targetKey = scopedKeys?.taxProfileKey ||
    (allowTenantLegacyWrite ? TENANT_TAX_PROFILE_KEY : "");
  if (!targetKey) throw new Error("missing_tenant_scope");
  await env.BOOKING_KV.put(targetKey, JSON.stringify({
    version: 1,
    updated_at: new Date().toISOString(),
    tax_profile: normalized,
  }));
  return normalized;
}

async function loadSubscriptionProfile(
  env,
  scope = null,
  { allowTenantLegacyFallback = true } = {},
) {
  if (!env?.BOOKING_KV) return normalizeSubscriptionProfile(DEFAULT_SUBSCRIPTION_PROFILE, scope);
  const scopedKeys = buildScopedSettingsKeys(scope);
  let raw = null;
  if (scopedKeys) {
    raw = await env.BOOKING_KV.get(scopedKeys.subscriptionProfileKey, { type: "json" });
  }
  if (!raw && allowTenantLegacyFallback) {
    raw = await env.BOOKING_KV.get(TENANT_SUBSCRIPTION_PROFILE_KEY, { type: "json" });
  }
  return normalizeSubscriptionProfile(raw?.subscription_profile ?? raw ?? DEFAULT_SUBSCRIPTION_PROFILE, scope);
}

async function saveSubscriptionProfile(
  env,
  profile,
  scope = null,
  { allowTenantLegacyWrite = true } = {},
) {
  if (!env?.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const nowIso = new Date().toISOString();
  const normalized = normalizeSubscriptionProfile({
    ...profile,
    updated_at: nowIso,
  }, scope);
  const scopedKeys = buildScopedSettingsKeys(scope);
  const targetKey = scopedKeys?.subscriptionProfileKey ||
    (allowTenantLegacyWrite ? TENANT_SUBSCRIPTION_PROFILE_KEY : "");
  if (!targetKey) throw new Error("missing_tenant_scope");
  await env.BOOKING_KV.put(targetKey, JSON.stringify({
    version: 1,
    updated_at: nowIso,
    subscription_profile: {
      ...normalized,
      created_at: normalized.created_at || nowIso,
      updated_at: nowIso,
    },
  }));
  return {
    ...normalized,
    created_at: normalized.created_at || nowIso,
    updated_at: nowIso,
  };
}

async function loadCommunicationTemplates(
  env,
  scopeOrTenant = null,
  companyIdArg = null,
  { allowTenantLegacyFallback = true } = {},
) {
  if (!env?.BOOKING_KV) return normalizeCommunicationTemplates(DEFAULT_COMMUNICATION_TEMPLATES);
  const scope =
    scopeOrTenant && typeof scopeOrTenant === "object" && !Array.isArray(scopeOrTenant)
      ? scopeOrTenant
      : {
          tenant_id: scopeOrTenant,
          company_id: companyIdArg,
        };
  const scopedKey = communicationTemplatesScopedKeyForScope(scope);
  let raw = null;
  if (scopedKey) {
    raw = await env.BOOKING_KV.get(scopedKey, { type: "json" });
  }
  if (!raw && allowTenantLegacyFallback) {
    raw = await env.BOOKING_KV.get(TENANT_COMMUNICATION_TEMPLATES_KEY, { type: "json" });
  }
  return normalizeCommunicationTemplates(raw?.communication_templates ?? raw ?? DEFAULT_COMMUNICATION_TEMPLATES);
}

async function saveCommunicationTemplates(
  env,
  templates,
  scopeOrTenant = null,
  companyIdArg = null,
  { allowTenantLegacyWrite = true } = {},
) {
  if (!env?.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const scope =
    scopeOrTenant && typeof scopeOrTenant === "object" && !Array.isArray(scopeOrTenant)
      ? scopeOrTenant
      : {
          tenant_id: scopeOrTenant,
          company_id: companyIdArg,
        };
  const scopedKey = communicationTemplatesScopedKeyForScope(scope) ||
    (allowTenantLegacyWrite ? TENANT_COMMUNICATION_TEMPLATES_KEY : "");
  if (!scopedKey) throw new Error("missing_tenant_scope");
  const normalized = normalizeCommunicationTemplates(templates);
  await env.BOOKING_KV.put(scopedKey, JSON.stringify({
    version: 1,
    updated_at: new Date().toISOString(),
    communication_templates: normalized,
  }));
  return normalized;
}

function sanitizePublicCompanyId(value) {
  const trimmed = sanitizeTenantString(value, 80);
  if (!trimmed) return "";
  return trimmed.replace(/[^a-zA-Z0-9_.-]/g, "");
}

function pickFirstPublicValue(...values) {
  for (const value of values) {
    const candidate = sanitizeTenantString(value, 240);
    if (candidate) return candidate;
  }
  return "";
}

async function handlePublicBootstrap(url, env) {
  const rawCompanyId =
    url.searchParams.get("company_id") ??
    url.searchParams.get("companyId") ??
    "";
  const companyId = sanitizePublicCompanyId(rawCompanyId);
  if (!companyId) {
    return json({ ok: false, error: "missing_company_id" }, 400);
  }

  console.log(`[PUBLIC_BOOTSTRAP] company=${companyId}`);

  const payload = await buildPublicBootstrapPayload(companyId, env);
  return json(payload, 200);
}

async function buildPublicBootstrapPayload(companyId, env) {
  let businessProfile = null;
  try {
    businessProfile = await loadBusinessProfile(env, {
      tenant_id: companyId,
      company_id: companyId,
    });
  } catch (_) {
    businessProfile = null;
  }
  const business =
    businessProfile && typeof businessProfile === "object"
      ? businessProfile
      : {};

  const displayName = pickFirstPublicValue(
    business.companyName,
    business.legalName,
    business.name,
    business.displayName,
    "Fluxidi",
  );

  const defaultLanguage = pickFirstPublicValue(
    business.locale,
    "nl",
  ).toLowerCase();

  return {
    ok: true,
    phase: "public_bootstrap_v1",
    tenant_id: companyId,
    company_id: companyId,
    booking_enabled: false,
    public_booking_status: "prepared",
    display_name: displayName || "Fluxidi",
    default_language: defaultLanguage || "nl",
    supported_languages: ["nl", "en", "fr", "es"],
    public_contact: {
      email: pickFirstPublicValue(
        business.companyEmail,
        business.email,
        business.supportEmail,
        business.bookingEmail,
      ),
      phone: pickFirstPublicValue(
        business.phone,
        business.companyPhone,
      ),
      website: pickFirstPublicValue(business.website),
    },
    branding: {
      logo_url: pickFirstPublicValue(business.logoUrl),
      primary_color: pickFirstPublicValue(
        business.primaryColor,
        business.primary_color,
      ),
      accent_color: pickFirstPublicValue(
        business.accentColor,
        business.accent_color,
      ),
    },
    features: {
      public_page: false,
      qr: false,
      embed: false,
    },
  };
}

function normalizePublicPreviewLanguage(raw) {
  const normalized = sanitizeTenantString(raw, 8).toLowerCase();
  return ["nl", "en", "fr", "es"].includes(normalized) ? normalized : "nl";
}

function normalizePublicStatusKey(rawStatus) {
  const key = sanitizeTenantString(rawStatus, 64).toLowerCase();
  if (!key) return "unknown";
  if (key === "cancelled" || key === "canceled") return "cancelled";
  if (
    key === "prepared" ||
    key === "pending" ||
    key === "confirmed" ||
    key === "completed" ||
    key === "planned" ||
    key === "direct" ||
    key === "ride_stop" ||
    key === "payment_update"
  ) {
    return key;
  }
  return "unknown";
}

function publicStatusLabel(lang, rawStatus) {
  const key = normalizePublicStatusKey(rawStatus);
  const labels = {
    nl: {
      prepared: "Voorbereid",
      pending: "In afwachting",
      confirmed: "Bevestigd",
      cancelled: "Geannuleerd",
      completed: "Afgerond",
      planned: "Gepland",
      direct: "Direct",
      ride_stop: "Rit beëindigd",
      payment_update: "Betaling bijgewerkt",
      unknown: "Onbekend",
    },
    en: {
      prepared: "Prepared",
      pending: "Pending",
      confirmed: "Confirmed",
      cancelled: "Cancelled",
      completed: "Completed",
      planned: "Scheduled",
      direct: "Direct",
      ride_stop: "Ride ended",
      payment_update: "Payment updated",
      unknown: "Unknown",
    },
    fr: {
      prepared: "Préparé",
      pending: "En attente",
      confirmed: "Confirmé",
      cancelled: "Annulé",
      completed: "Terminée",
      planned: "Planifiée",
      direct: "Directe",
      ride_stop: "Course terminée",
      payment_update: "Paiement mis à jour",
      unknown: "Inconnu",
    },
    es: {
      prepared: "Preparado",
      pending: "Pendiente",
      confirmed: "Confirmado",
      cancelled: "Cancelado",
      completed: "Finalizado",
      planned: "Programado",
      direct: "Directo",
      ride_stop: "Viaje finalizado",
      payment_update: "Pago actualizado",
      unknown: "Desconocido",
    },
  };
  const table = labels[lang] || labels.nl;
  return table[key] || table.unknown;
}

function publicPreviewCopy(lang) {
  const dictionary = {
    nl: {
      pageTitle: "Publieke boekingspagina",
      heading: "Online boeken wordt binnenkort beschikbaar.",
      description:
        "Deze publieke boekingspagina is voorbereid voor websiteboekingen, QR-codes en sociale media.",
      cta: "Boeking binnenkort beschikbaar",
      contactTitle: "Publiek contact",
      email: "E-mail",
      phone: "Telefoon",
      website: "Website",
    },
    en: {
      pageTitle: "Public booking page",
      heading: "Online booking will be available soon.",
      description:
        "This public booking page is prepared for website bookings, QR codes and social media.",
      cta: "Booking coming soon",
      contactTitle: "Public contact",
      email: "Email",
      phone: "Phone",
      website: "Website",
    },
    fr: {
      pageTitle: "Page de réservation publique",
      heading: "La réservation en ligne sera bientôt disponible.",
      description:
        "Cette page de réservation publique est préparée pour les réservations via site web, QR codes et réseaux sociaux.",
      cta: "Réservation bientôt disponible",
      contactTitle: "Contact public",
      email: "E-mail",
      phone: "Téléphone",
      website: "Site web",
    },
    es: {
      pageTitle: "Página pública de reserva",
      heading: "La reserva online estará disponible pronto.",
      description:
        "Esta página pública de reserva está preparada para reservas desde la web, códigos QR y redes sociales.",
      cta: "Reserva próximamente",
      contactTitle: "Contacto público",
      email: "Correo",
      phone: "Teléfono",
      website: "Sitio web",
    },
  };
  return dictionary[lang] || dictionary.nl;
}

async function handlePublicBookingPreview(url, env) {
  const rawCompanyId =
    url.searchParams.get("company_id") ??
    url.searchParams.get("companyId") ??
    "";
  const companyId = sanitizePublicCompanyId(rawCompanyId);
  if (!companyId) {
    return html(
      `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="font-family:system-ui;background:#0B1020;color:#fff;padding:24px"><h1 style="font-size:20px;margin:0 0 8px">missing_company_id</h1><p style="margin:0;color:#AEB8D0">Provide ?company_id=...</p></body></html>`,
      400,
    );
  }

  const lang = normalizePublicPreviewLanguage(url.searchParams.get("lang"));
  const copy = publicPreviewCopy(lang);
  const data = await buildPublicBootstrapPayload(companyId, env);
  const localizedStatus = publicStatusLabel(lang, data?.public_booking_status);
  const displayName = sanitizeTenantString(data?.display_name || "Fluxidi", 120);
  const contact = data?.public_contact && typeof data.public_contact === "object"
    ? data.public_contact
    : {};
  const contactEmail = sanitizeTenantString(contact.email, 240);
  const contactPhone = sanitizeTenantString(contact.phone, 120);
  const contactWebsite = sanitizeTenantString(contact.website, 240);
  const hasContact = !!(contactEmail || contactPhone || contactWebsite);
  const supportedLanguages = Array.isArray(data?.supported_languages)
    ? data.supported_languages.filter((code) => ["nl", "en", "fr", "es"].includes(String(code || "").toLowerCase()))
    : ["nl", "en", "fr", "es"];

  const langChips = supportedLanguages
    .map((codeRaw) => String(codeRaw || "").toLowerCase())
    .filter((code, idx, arr) => code && arr.indexOf(code) === idx)
    .map((code) => {
      const active = code === lang;
      const href = `/public/book?company_id=${encodeURIComponent(companyId)}&lang=${encodeURIComponent(code)}`;
      return `<a href="${href}" style="text-decoration:none;border:1px solid ${active ? "#22C55E" : "#2D3859"};background:${active ? "#12331F" : "#131C33"};color:${active ? "#B9F5CA" : "#D7E1FF"};padding:6px 10px;border-radius:999px;font-size:12px;font-weight:700;letter-spacing:0.2px">${escapeHtml(code.toUpperCase())}</a>`;
    })
    .join("");

  return html(
    `<!doctype html>
<html lang="${escapeHtml(lang)}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>${escapeHtml(copy.pageTitle)} - ${escapeHtml(displayName)}</title>
  </head>
  <body style="margin:0;background:#0B1020;color:#E8EEFF;font-family:Inter,Segoe UI,system-ui,-apple-system,sans-serif;">
    <main style="max-width:760px;margin:0 auto;padding:22px 16px 28px;">
      <section style="background:#121A30;border:1px solid #26314F;border-radius:16px;padding:18px;">
        <div style="display:flex;justify-content:space-between;align-items:flex-start;gap:10px;flex-wrap:wrap;">
          <div>
            <div style="font-size:12px;color:#AEB8D0;">Fluxidi</div>
            <h1 style="margin:4px 0 0;font-size:23px;line-height:1.2;">${escapeHtml(displayName)}</h1>
          </div>
          <span style="display:inline-flex;align-items:center;border:1px solid #355C3C;background:#12331F;color:#B9F5CA;border-radius:999px;padding:6px 11px;font-size:12px;font-weight:700;">
            ${escapeHtml(localizedStatus)}
          </span>
        </div>
        <div style="display:flex;gap:8px;flex-wrap:wrap;margin-top:14px;">${langChips}</div>
        <h2 style="margin:18px 0 8px;font-size:21px;line-height:1.28;">${escapeHtml(copy.heading)}</h2>
        <p style="margin:0;color:#AEB8D0;font-size:14px;line-height:1.5;">${escapeHtml(copy.description)}</p>
        <button type="button" disabled style="margin-top:16px;width:100%;border:none;border-radius:12px;padding:13px 16px;background:#28324C;color:#A4AFCB;font-size:15px;font-weight:700;cursor:not-allowed;opacity:0.95;">
          ${escapeHtml(copy.cta)}
        </button>
      </section>
      ${
        hasContact
          ? `<section style="margin-top:14px;background:#121A30;border:1px solid #26314F;border-radius:16px;padding:16px;">
        <h3 style="margin:0 0 10px;font-size:16px;">${escapeHtml(copy.contactTitle)}</h3>
        ${contactEmail ? `<div style="margin:0 0 6px;color:#D7E1FF;"><strong>${escapeHtml(copy.email)}:</strong> ${escapeHtml(contactEmail)}</div>` : ""}
        ${contactPhone ? `<div style="margin:0 0 6px;color:#D7E1FF;"><strong>${escapeHtml(copy.phone)}:</strong> ${escapeHtml(contactPhone)}</div>` : ""}
        ${contactWebsite ? `<div style="margin:0;color:#D7E1FF;"><strong>${escapeHtml(copy.website)}:</strong> ${escapeHtml(contactWebsite)}</div>` : ""}
      </section>`
          : ""
      }
    </main>
  </body>
</html>`,
    200,
  );
}

function isValidEmail(value) {
  const email = safeStr(value).toLowerCase();
  if (!email) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function pickFirstValidEmail(...candidates) {
  for (const candidate of candidates) {
    const email = safeStr(candidate).toLowerCase();
    if (isValidEmail(email)) return email;
  }
  return "";
}

function safeBrandName(value, fallback = "Fluxidi Taxi") {
  const brand = sanitizeTenantString(value, 120);
  return brand || fallback;
}

function maybeNormalizeCommunicationProfile(raw) {
  const source = raw && typeof raw === "object" ? raw : {};
  const brandName = safeBrandName(source.brandName, "Fluxidi Taxi");
  const legalName = sanitizeTenantString(source.legalName, 160) || brandName;
  const bookingEmail = pickFirstValidEmail(
    source.bookingEmail,
    source.bookingsEmail,
    source.reservationEmail,
    source.reservationsEmail,
    source.dispatchEmail,
  );
  const companyEmail = pickFirstValidEmail(source.companyEmail);
  const supportEmail = pickFirstValidEmail(source.supportEmail, companyEmail);
  const invoiceEmail = pickFirstValidEmail(source.invoiceEmail);
  const billingEmail = pickFirstValidEmail(source.billingEmail, invoiceEmail);
  const notificationEmail = pickFirstValidEmail(source.notificationEmail, companyEmail, invoiceEmail);
  const replyToEmail = pickFirstValidEmail(source.replyToEmail, companyEmail, supportEmail, invoiceEmail);
  const locale = sanitizeTenantString(source.locale, 16).toLowerCase() || "nl";
  const currencyRaw = sanitizeTenantString(source.currency, 8).toUpperCase();
  const currency = /^[A-Z]{3}$/.test(currencyRaw) ? currencyRaw : "EUR";
  return {
    brandName,
    legalName,
    bookingEmail,
    companyEmail,
    supportEmail,
    invoiceEmail,
    billingEmail,
    notificationEmail,
    replyToEmail,
    phone: sanitizeTenantString(source.phone, 64),
    website: sanitizeTenantString(source.website, 200),
    address: sanitizeTenantString(source.address, 280),
    vatNumber: sanitizeTenantString(source.vatNumber, 64),
    companyNumber: sanitizeTenantString(source.companyNumber, 80),
    logoUrl: sanitizeTenantString(source.logoUrl, 1000),
    invoiceFooter: sanitizeTenantString(source.invoiceFooter, 2000),
    receiptFooter: sanitizeTenantString(source.receiptFooter, 2000),
    locale,
    currency,
  };
}

async function resolveTenantCommunicationProfile(env, tenantId = null, companyId = null) {
  let businessProfile = null;
  let communicationTemplates = null;
  try {
    businessProfile = await loadBusinessProfile(env, {
      tenant_id: tenantId,
      company_id: companyId,
    });
  } catch (_) {
    businessProfile = null;
  }
  try {
    communicationTemplates = await loadCommunicationTemplates(env, {
      tenant_id: tenantId,
      company_id: companyId,
    });
  } catch (_) {
    communicationTemplates = null;
  }

  const business = businessProfile && typeof businessProfile === "object"
    ? businessProfile
    : DEFAULT_BUSINESS_PROFILE;

  const templateByLocale = communicationTemplates?.templates?.[business?.locale] || communicationTemplates?.templates?.nl || null;
  const fallbackTemplate = communicationTemplates?.templates?.nl || templateByLocale || null;
  const footerTemplate = sanitizeTenantString(
    templateByLocale?.footerDisclaimerText ||
    fallbackTemplate?.footerDisclaimerText ||
    "",
    2000,
  );

  const addressParts = [
    sanitizeTenantString(business?.address, 220),
    [sanitizeTenantString(business?.postcode, 24), sanitizeTenantString(business?.city, 80)].filter(Boolean).join(" "),
    sanitizeTenantString(business?.country, 64),
  ].filter(Boolean);

  const mapped = {
    tenantId: sanitizeTenantString(tenantId, 80),
    companyId: sanitizeTenantString(companyId, 80),
    brandName: business?.companyName,
    legalName: business?.legalName || business?.companyName,
    bookingEmail: business?.bookingEmail || business?.bookingsEmail || business?.reservationEmail || business?.reservationsEmail || business?.dispatchEmail,
    companyEmail: business?.companyEmail || business?.email,
    supportEmail: business?.supportEmail || business?.email,
    invoiceEmail: business?.invoiceEmail,
    billingEmail: business?.billingEmail || business?.invoiceEmail,
    notificationEmail: business?.notificationEmail || business?.email || business?.invoiceEmail,
    replyToEmail: business?.replyToEmail,
    phone: business?.phone,
    website: business?.website,
    address: addressParts.join("\n"),
    vatNumber: business?.vatNumber,
    companyNumber: business?.companyRegistrationNumber,
    logoUrl: env?.INVOICE_LOGO_URL,
    invoiceFooter: business?.invoiceReceiptFooterText || footerTemplate,
    receiptFooter: business?.invoiceReceiptFooterText || footerTemplate,
    locale: business?.locale || "nl",
    currency: business?.currency || "EUR",
  };

  return maybeNormalizeCommunicationProfile(mapped);
}

// DEV/TEST ONLY. Must be disabled or protected before production.
const SAFE_RESET_BOOKING_KV_PREFIXES = [
  { category: "plannedBookings", prefix: "booking:" },
];

const SAFE_RESET_TRACKING_KV_PREFIXES = [
  { category: "activeRideSessions", prefix: "session:" },
  { category: "liveTrackingPings", prefix: "ping:" },
  { category: "publicTrackingLinks", prefix: "public:" },
  { category: "temporaryBookingTrackingLinks", prefix: "booking:" },
  { category: "tripHistory", prefix: "trip:" },
  { category: "tripHistoryIndexes", prefix: "trips_index:" },
];

const SAFE_RESET_TRACKING_KV_EXACT_KEYS = [
  { category: "temporaryBookingTrackingIndex", key: "booking_index" },
];

const SAFE_RESET_PROTECTED_BOOKING_KV_EXACT_KEYS = [
  "tenant:pricing:v1",
  "tenant:business_profile:v1",
  "tenant:tax_profile:v1",
  "tenant:subscription:v1",
  "tenant:communication_templates:v1",
  "fleet:vehicles:v1",
  "partners:directory:v1",
];

const SAFE_RESET_PROTECTED_BOOKING_KV_PREFIXES = [
  "tenant:",
  "company:",
  "pricing:",
  "fleet:vehicles",
  "fleet:drivers",
  "vehicle:",
  "vehicles:",
  "driver:",
  "drivers:",
  "branding:",
  "language:",
  "lang:",
  "saas:",
  "subscription:",
  "partner:",
  "partners:",
  "admin:",
  "config:",
];

async function listKvKeyNames(namespace, prefix) {
  if (!namespace) return [];
  const out = [];
  let cursor = undefined;
  do {
    const page = await namespace.list({ prefix, limit: 1000, cursor });
    for (const item of page?.keys || []) {
      if (item?.name) out.push(item.name);
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (cursor);
  return out;
}

async function collectSafeResetKeys(env) {
  const categories = {};
  const keys = [];
  const protectedKeys = [];

  const addKeys = (namespaceName, category, names) => {
    const clean = Array.from(new Set((names || []).filter(Boolean)));
    categories[category] = (categories[category] || 0) + clean.length;
    for (const key of clean) keys.push({ namespace: namespaceName, category, key });
  };

  if (env?.BOOKING_KV) {
    for (const item of SAFE_RESET_BOOKING_KV_PREFIXES) {
      addKeys("BOOKING_KV", item.category, await listKvKeyNames(env.BOOKING_KV, item.prefix));
    }

    for (const key of SAFE_RESET_PROTECTED_BOOKING_KV_EXACT_KEYS) {
      const value = await env.BOOKING_KV.get(key);
      if (value != null) protectedKeys.push({ namespace: "BOOKING_KV", key });
    }

    for (const prefix of SAFE_RESET_PROTECTED_BOOKING_KV_PREFIXES) {
      const names = await listKvKeyNames(env.BOOKING_KV, prefix);
      for (const key of names) {
        if (!protectedKeys.some((item) => item.namespace === "BOOKING_KV" && item.key === key)) {
          protectedKeys.push({ namespace: "BOOKING_KV", key });
        }
      }
    }
  }

  if (env?.FLUXIDI_TRACKING) {
    for (const item of SAFE_RESET_TRACKING_KV_PREFIXES) {
      addKeys("FLUXIDI_TRACKING", item.category, await listKvKeyNames(env.FLUXIDI_TRACKING, item.prefix));
    }
    for (const item of SAFE_RESET_TRACKING_KV_EXACT_KEYS) {
      const value = await env.FLUXIDI_TRACKING.get(item.key);
      if (value != null) addKeys("FLUXIDI_TRACKING", item.category, [item.key]);
    }
  }

  const unique = [];
  const seen = new Set();
  for (const item of keys) {
    const id = `${item.namespace}:${item.key}`;
    if (seen.has(id)) continue;
    seen.add(id);
    unique.push(item);
  }

  return {
    keys: unique,
    categories,
    totalCount: unique.length,
    protectedKeys,
    protectedSkipped: protectedKeys.length,
  };
}

function groupedSafeResetKeys(keys) {
  const grouped = {};
  for (const item of keys || []) {
    grouped[item.namespace] = grouped[item.namespace] || {};
    grouped[item.namespace][item.category] = grouped[item.namespace][item.category] || [];
    grouped[item.namespace][item.category].push(item.key);
  }
  return grouped;
}

async function releaseSafeResetBookingReservation(env, key) {
  if (!env?.FLEET_ALLOCATOR || !env?.BOOKING_KV) return false;
  const bookingId = String(key || "").startsWith("booking:")
    ? String(key).slice("booking:".length)
    : "";
  if (!bookingId) return false;

  const rec = await env.BOOKING_KV.get(key, { type: "json" });
  const pickupIso =
    rec?.booking?.pickupStartIso ||
    rec?.booking?.pickup_iso ||
    rec?.quote?.pickup_iso ||
    rec?.payload?.pickup_iso ||
    rec?.payload?.pickupIso ||
    null;
  if (!pickupIso) return false;

  try {
    const tenantScope = normalizeFleetTenantScope(
      resolveBookingTenantScopeFromRecord(rec),
    );
    await _allocatorRequest(env, pickupIso, {
      action: "release",
      booking_id: bookingId,
      tenantScope,
    });
    return true;
  } catch (_) {
    return false;
  }
}

function _safeResetScopePart(value, maxLen = 120) {
  const text = _scopeText(value, maxLen);
  if (!text) return "";
  return text.replace(/[:\r\n\t]/g, "_");
}

function _safeResetNormalizedScope(scope) {
  const tenantId = _safeResetScopePart(scope?.tenant_id);
  const companyId = _safeResetScopePart(scope?.company_id);
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId && companyId),
  };
}

function _safeResetScopedBookingMapKey(scope, bookingId) {
  const normalized = _safeResetNormalizedScope(scope);
  const safeBookingId = _safeResetScopePart(bookingId, 160);
  if (!normalized.hasScope || !safeBookingId) return "";
  return `tenant:${normalized.tenant_id}:company:${normalized.company_id}:booking:${safeBookingId}:session`;
}

function _safeResetScopedSessionKey(scope, sessionId) {
  const normalized = _safeResetNormalizedScope(scope);
  const safeSessionId = _safeResetScopePart(sessionId, 160);
  if (!normalized.hasScope || !safeSessionId) return "";
  return `tenant:${normalized.tenant_id}:company:${normalized.company_id}:session:${safeSessionId}`;
}

function _safeResetScopedPingKey(scope, sessionId) {
  const normalized = _safeResetNormalizedScope(scope);
  const safeSessionId = _safeResetScopePart(sessionId, 160);
  if (!normalized.hasScope || !safeSessionId) return "";
  return `tenant:${normalized.tenant_id}:company:${normalized.company_id}:ping:${safeSessionId}:last`;
}

function _safeResetScopedPublicTokenKey(scope, publicToken) {
  const normalized = _safeResetNormalizedScope(scope);
  const safeToken = _safeResetScopePart(publicToken, 200);
  if (!normalized.hasScope || !safeToken) return "";
  return `tenant:${normalized.tenant_id}:company:${normalized.company_id}:public:${safeToken}:booking`;
}

function _safeResetScopedBookingIndexKey(scope) {
  const normalized = _safeResetNormalizedScope(scope);
  if (!normalized.hasScope) return "";
  return `tenant:${normalized.tenant_id}:company:${normalized.company_id}:booking_index`;
}

async function collectScopedResetBookingIds(env, requestedScope) {
  if (!env?.BOOKING_KV) return { bookingIds: [], skipped: 0 };
  const listed = await env.BOOKING_KV.list({ prefix: "booking:", limit: 1000 });
  const bookingIds = [];
  let skipped = 0;
  for (const item of listed?.keys || []) {
    const key = String(item?.name || "");
    if (!key.startsWith("booking:")) continue;
    const rec = await env.BOOKING_KV.get(key, { type: "json" });
    if (!rec || typeof rec !== "object") {
      skipped += 1;
      continue;
    }
    if (!bookingMatchesRequestedTenantScope(rec, requestedScope)) {
      skipped += 1;
      continue;
    }
    const bookingId = key.slice("booking:".length);
    if (!bookingId) {
      skipped += 1;
      continue;
    }
    bookingIds.push(bookingId);
  }
  return { bookingIds, skipped };
}

async function scopedResetTrackingByBookingIds(env, requestedScope, bookingIds = [], { dryRun = false } = {}) {
  if (!env?.FLUXIDI_TRACKING) {
    return { deletedTrackingKeys: 0, skippedUnscopedOrUnknown: 0, legacyUnmodified: 0 };
  }
  const normalizedScope = _safeResetNormalizedScope(requestedScope);
  if (!normalizedScope.hasScope) {
    return { deletedTrackingKeys: 0, skippedUnscopedOrUnknown: 0, legacyUnmodified: 0 };
  }
  let deletedTrackingKeys = 0;
  let skippedUnscopedOrUnknown = 0;
  let legacyUnmodified = 0;
  const uniqueBookingIds = Array.from(
    new Set((bookingIds || []).map((v) => String(v || "").trim()).filter(Boolean)),
  );
  const deletedBookingIdSet = new Set(uniqueBookingIds);
  const scopedBookingIndexKey = _safeResetScopedBookingIndexKey(normalizedScope);

  for (const bookingId of uniqueBookingIds) {
    const mapKey = _safeResetScopedBookingMapKey(normalizedScope, bookingId);
    if (!mapKey) {
      skippedUnscopedOrUnknown += 1;
      continue;
    }
    let mapRaw = null;
    try {
      mapRaw = await env.FLUXIDI_TRACKING.get(mapKey);
    } catch (_) {
      skippedUnscopedOrUnknown += 1;
      continue;
    }
    if (mapRaw == null) {
      try {
        const legacyMapRaw = await env.FLUXIDI_TRACKING.get(`booking:${bookingId}:session`);
        if (legacyMapRaw != null) legacyUnmodified += 1;
      } catch (_) {
        skippedUnscopedOrUnknown += 1;
      }
      continue;
    }
    if (!dryRun) {
      await env.FLUXIDI_TRACKING.delete(mapKey);
    }
    deletedTrackingKeys += 1;

    let map = null;
    try {
      map = JSON.parse(mapRaw);
    } catch (_) {
      map = null;
    }
    if (!map || typeof map !== "object") {
      skippedUnscopedOrUnknown += 1;
      continue;
    }

    const sessionId = safeStr(map?.session_id || map?.sessionId, 160);
    if (sessionId) {
      const sessionKey = _safeResetScopedSessionKey(normalizedScope, sessionId);
      const pingKey = _safeResetScopedPingKey(normalizedScope, sessionId);
      if (sessionKey) {
        if (!dryRun) await env.FLUXIDI_TRACKING.delete(sessionKey);
        deletedTrackingKeys += 1;
      }
      if (pingKey) {
        if (!dryRun) await env.FLUXIDI_TRACKING.delete(pingKey);
        deletedTrackingKeys += 1;
      }
    } else {
      skippedUnscopedOrUnknown += 1;
    }

    const publicToken = safeStr(map?.public_token || map?.publicToken, 200);
    if (publicToken) {
      const publicKey = _safeResetScopedPublicTokenKey(normalizedScope, publicToken);
      if (publicKey) {
        if (!dryRun) await env.FLUXIDI_TRACKING.delete(publicKey);
        deletedTrackingKeys += 1;
      } else {
        skippedUnscopedOrUnknown += 1;
      }
    }
  }

  if (scopedBookingIndexKey) {
    try {
      const rawIdx = await env.FLUXIDI_TRACKING.get(scopedBookingIndexKey);
      if (rawIdx != null) {
        let idx = [];
        try {
          idx = JSON.parse(rawIdx || "[]");
        } catch (_) {
          idx = [];
        }
        if (Array.isArray(idx)) {
          const next = idx.filter((id) => !deletedBookingIdSet.has(String(id || "").trim()));
          if (next.length !== idx.length) {
            if (!dryRun) {
              await env.FLUXIDI_TRACKING.put(
                scopedBookingIndexKey,
                JSON.stringify(next),
                { expirationTtl: 60 * 60 * 24 * 30 },
              );
            }
            deletedTrackingKeys += 1;
          }
        } else {
          skippedUnscopedOrUnknown += 1;
        }
      }
    } catch (_) {
      skippedUnscopedOrUnknown += 1;
    }
  }

  return { deletedTrackingKeys, skippedUnscopedOrUnknown, legacyUnmodified };
}

async function handleSafeResetDryRun(request, url, env) {
  _requireAdmin(request, url, env);
  const requestedScope = resolveExplicitBookingRequestScope({
    request,
    url,
    allowLegacyFallback: false,
  });
  if (!requestedScope?.hasScope) {
    return json(
      requestedScope?.error === "tenant_scope_conflict" ? scopeConflictError() : missingTenantScopeError(),
      400,
    );
  }
  const requestedTenant = _scopeText(requestedScope?.tenant_id);
  const requestedCompany = _scopeText(requestedScope?.company_id);
  if (requestedTenant === "fluxidi" || requestedCompany === "fluxidi") {
    return json({ ok: false, error: "unsafe_legacy_scope_not_allowed" }, 400);
  }

  const collected = await collectScopedResetBookingIds(env, requestedScope);
  const trackingPreview = await scopedResetTrackingByBookingIds(
    env,
    requestedScope,
    collected.bookingIds,
    { dryRun: true },
  );
  const skipped = Number(collected?.skipped || 0) + Number(trackingPreview?.skippedUnscopedOrUnknown || 0);
  const legacyUnmodified = Number(trackingPreview?.legacyUnmodified || 0);
  console.log(
    `[SAFE_RESET][DRY_RUN][SCOPED] tenant=${requestedTenant} company=${requestedCompany} bookingCandidates=${collected.bookingIds.length} trackingCandidates=${Number(trackingPreview?.deletedTrackingKeys || 0)} skipped=${skipped} legacyUnmodified=${legacyUnmodified}`
  );
  return json({
    ok: true,
    dryRun: true,
    scoped: true,
    tenant_id: requestedTenant,
    company_id: requestedCompany,
    candidates: {
      bookings: collected.bookingIds.length,
      tracking_keys: Number(trackingPreview?.deletedTrackingKeys || 0),
    },
    skipped_unscoped_or_unknown: skipped,
    legacy_unmodified: legacyUnmodified,
    message: "Dry-run only. Scoped operational reset candidates collected safely.",
  }, 200);
}

async function handleSafeResetOperationalData(request, url, env) {
  _requireAdmin(request, url, env);
  if (String(env?.ALLOW_DEV_RESET || "").trim() !== "true") {
    return json({ ok: false, error: "dev_reset_disabled" }, 403);
  }
  const body = await safeJson(request);
  const requestedScope = resolveExplicitBookingRequestScope({
    request,
    url,
    body,
    allowLegacyFallback: false,
  });
  if (!requestedScope?.hasScope) {
    return json(
      requestedScope?.error === "tenant_scope_conflict" ? scopeConflictError() : missingTenantScopeError(),
      400,
    );
  }
  const requestedTenant = _scopeText(requestedScope?.tenant_id);
  const requestedCompany = _scopeText(requestedScope?.company_id);
  if (requestedTenant === "fluxidi" || requestedCompany === "fluxidi") {
    return json({ ok: false, error: "unsafe_legacy_scope_not_allowed" }, 400);
  }

  const collected = await collectScopedResetBookingIds(env, requestedScope);
  let deletedBookings = 0;
  const deletedBookingIds = [];
  let deletedTrackingKeys = 0;
  let skippedUnscopedOrUnknown = Number(collected?.skipped || 0);
  let legacyUnmodified = 0;
  let reservationsReleased = 0;
  for (const bookingId of collected.bookingIds || []) {
    const key = `booking:${bookingId}`;
    try {
      const rec = await env.BOOKING_KV.get(key, { type: "json" });
      if (!rec || typeof rec !== "object") {
        skippedUnscopedOrUnknown += 1;
        continue;
      }
      if (!bookingMatchesRequestedTenantScope(rec, requestedScope)) {
        skippedUnscopedOrUnknown += 1;
        continue;
      }
      if (await releaseSafeResetBookingReservation(env, key)) {
        reservationsReleased += 1;
      }
      await env.BOOKING_KV.delete(key);
      deletedBookings += 1;
      deletedBookingIds.push(bookingId);
      console.log(
        `[SAFE_RESET][SCOPED_DELETE][BOOKING] tenant=${requestedTenant} company=${requestedCompany} booking=${_bookingIntentMask(bookingId)}`,
      );
    } catch (err) {
      skippedUnscopedOrUnknown += 1;
      console.log(
        `[SAFE_RESET][SCOPED_DELETE][BOOKING][ERROR] tenant=${requestedTenant} company=${requestedCompany} booking=${_bookingIntentMask(bookingId)} failed=${String(err?.message || err)}`
      );
    }
  }

  const trackingReset = await scopedResetTrackingByBookingIds(
    env,
    requestedScope,
    deletedBookingIds,
    { dryRun: false },
  );
  deletedTrackingKeys += Number(trackingReset?.deletedTrackingKeys || 0);
  skippedUnscopedOrUnknown += Number(trackingReset?.skippedUnscopedOrUnknown || 0);
  legacyUnmodified += Number(trackingReset?.legacyUnmodified || 0);

  console.log(
    `[SAFE_RESET][SCOPED_DONE] tenant=${requestedTenant} company=${requestedCompany} deletedBookings=${deletedBookings} deletedTrackingKeys=${deletedTrackingKeys} skipped=${skippedUnscopedOrUnknown} legacyUnmodified=${legacyUnmodified} reservationsReleased=${reservationsReleased}`
  );

  return json({
    ok: true,
    scoped: true,
    tenant_id: requestedTenant,
    company_id: requestedCompany,
    deleted_bookings: deletedBookings,
    deleted_tracking_keys: deletedTrackingKeys,
    skipped_unscoped_or_unknown: skippedUnscopedOrUnknown,
    legacy_unmodified: legacyUnmodified,
    reservationsReleased,
    message: "Scoped operational test data reset completed safely",
  }, 200);
}

export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);
      const pathParts = url.pathname.split("/").filter(Boolean);

      // CORS preflight
      if (request.method === "OPTIONS") {
        return new Response(null, { headers: corsHeaders() });
      }

      // OAUTH
      if (url.pathname === "/oauth/start" && request.method === "GET") return oauthStart(request, env);
      if (url.pathname === "/oauth/callback" && request.method === "GET") return oauthCallback(request, env);
      if (url.pathname === "/admin/google-calendar/oauth/start" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({
          request,
          url,
          body,
        });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const missingEnv = [];
        if (!safeStr(env?.GOOGLE_CLIENT_ID)) missingEnv.push("GOOGLE_CLIENT_ID");
        if (!safeStr(env?.GOOGLE_CLIENT_SECRET)) missingEnv.push("GOOGLE_CLIENT_SECRET");
        if (!safeStr(env?.CALENDAR_OAUTH_STATE_SECRET)) missingEnv.push("CALENDAR_OAUTH_STATE_SECRET");
        if (!safeStr(env?.CALENDAR_AUTH_ENCRYPTION_KEY)) missingEnv.push("CALENDAR_AUTH_ENCRYPTION_KEY");
        if (!env?.BOOKING_KV) missingEnv.push("BOOKING_KV");
        if (missingEnv.length) {
          return json(
            {
              ok: false,
              error: "calendar_oauth_not_configured",
              missing: missingEnv,
            },
            500,
          );
        }
        const nonceOut = await createCalendarOAuthNonce(env, explicitScope);
        const iat = Math.floor(Date.now() / 1000);
        const exp = iat + CALENDAR_OAUTH_NONCE_TTL_SECONDS;
        const kid = safeStr(env?.CALENDAR_AUTH_ENCRYPTION_KID, 32) || "v1";
        const statePayload = {
          v: 1,
          purpose: CALENDAR_OAUTH_STATE_PURPOSE,
          tenant_id: explicitScope.tenant_id,
          company_id: explicitScope.company_id,
          nonce: nonceOut.nonce,
          iat,
          exp,
          kid,
        };
        const signedState = await buildSignedCalendarOAuthState(
          statePayload,
          env.CALENDAR_OAUTH_STATE_SECRET,
        );
        const base = getBaseUrl(request);
        const redirectUri = `${base}/oauth/callback`;
        const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
        authUrl.searchParams.set("client_id", env.GOOGLE_CLIENT_ID);
        authUrl.searchParams.set("redirect_uri", redirectUri);
        authUrl.searchParams.set("response_type", "code");
        authUrl.searchParams.set("scope", "https://www.googleapis.com/auth/calendar");
        authUrl.searchParams.set("access_type", "offline");
        authUrl.searchParams.set("prompt", "consent");
        authUrl.searchParams.set("include_granted_scopes", "true");
        authUrl.searchParams.set("state", signedState);
        console.log(
          `[CALENDAR_OAUTH][START] tenant=${explicitScope.tenant_id} company=${explicitScope.company_id} nonce=${nonceOut.nonce}`,
        );
        return json(
          {
            ok: true,
            auth_url: authUrl.toString(),
            expires_in: CALENDAR_OAUTH_NONCE_TTL_SECONDS,
          },
          200,
        );
      }
      if (url.pathname === "/admin/google-calendar/disconnect" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({
          request,
          url,
          body,
        });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        if (!env?.BOOKING_KV) {
          return json({ ok: false, error: "missing_booking_kv" }, 500);
        }
        const tenantId = explicitScope.tenant_id;
        const companyId = explicitScope.company_id;
        const scopedKey = buildScopedGoogleCalendarAuthKey(explicitScope);
        if (!scopedKey) {
          return json(missingTenantScopeError(), 400);
        }
        let existing = null;
        try {
          const raw = await env.BOOKING_KV.get(scopedKey, { type: "json" });
          existing = raw && typeof raw === "object"
            ? (raw.google_calendar_auth && typeof raw.google_calendar_auth === "object"
                ? raw.google_calendar_auth
                : raw)
            : null;
        } catch (_) {
          existing = null;
        }
        const nowIso = new Date().toISOString();
        const disconnected = {
          version: 1,
          connected: false,
          status: "disconnected",
          calendarId:
            safeStr(existing?.calendarId ?? existing?.calendar_id, 160) || "primary",
          accountEmail:
            safeStr(existing?.accountEmail ?? existing?.account_email, 320) || null,
          lastConnectedAt:
            safeStr(existing?.lastConnectedAt ?? existing?.last_connected_at, 64) ||
            null,
          lastDisconnectedAt: nowIso,
          lastSyncAt:
            safeStr(existing?.lastSyncAt ?? existing?.last_sync_at, 64) || null,
          lastErrorCode: null,
          lastErrorAt: null,
          updatedAt: nowIso,
        };
        await env.BOOKING_KV.put(scopedKey, JSON.stringify(disconnected));
        console.log(
          `[CALENDAR_AUTH][DISCONNECT] tenant=${tenantId} company=${companyId}`,
        );
        return json(
          {
            ok: true,
            tenant_id: tenantId,
            company_id: companyId,
            source: "scoped",
            connected: false,
            status: "disconnected",
            calendar_id: disconnected.calendarId,
            last_disconnected_at: disconnected.lastDisconnectedAt,
          },
          200,
        );
      }
      if (url.pathname === "/admin/google-calendar/status" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const scopedKey = buildScopedGoogleCalendarAuthKey(explicitScope);
        const tenantId = explicitScope.tenant_id;
        const companyId = explicitScope.company_id;
        let scopedRecord = null;
        if (scopedKey && env?.BOOKING_KV) {
          try {
            const raw = await env.BOOKING_KV.get(scopedKey, { type: "json" });
            const scoped = raw && typeof raw === "object"
              ? (raw.google_calendar_auth && typeof raw.google_calendar_auth === "object"
                  ? raw.google_calendar_auth
                  : raw)
              : null;
            if (scoped) scopedRecord = scoped;
          } catch (_) {
            scopedRecord = null;
          }
        }
        if (scopedRecord) {
          const scopedStatusRaw = safeStr(scopedRecord.status, 64);
          const scopedStatus = scopedStatusRaw || "connected";
          const scopedStatusLower = scopedStatus.toLowerCase();
          const scopedConnected =
            scopedRecord.connected === true && scopedStatusLower === "connected";
          const hasScopedTokenMaterial = !!(
            safeStr(scopedRecord.refreshToken ?? scopedRecord.refresh_token) ||
            (scopedRecord.refreshTokenEncrypted &&
              typeof scopedRecord.refreshTokenEncrypted === "object")
          );
          const scopedConfigured = scopedConnected && hasScopedTokenMaterial;
          const scopedReportedStatus =
            scopedStatusLower === "disconnected" || scopedRecord.connected === false
              ? "disconnected"
              : scopedStatus;
          return json(
            {
              ok: true,
              tenant_id: tenantId,
              company_id: companyId,
              source: "scoped",
              configured: scopedConfigured,
              connected: scopedConnected,
              status: scopedReportedStatus,
              calendar_id:
                safeStr(scopedRecord.calendarId ?? scopedRecord.calendar_id, 160) ||
                "primary",
              account_email:
                safeStr(scopedRecord.accountEmail ?? scopedRecord.account_email, 320) ||
                null,
              last_connected_at:
                safeStr(
                  scopedRecord.lastConnectedAt ?? scopedRecord.last_connected_at,
                  64,
                ) || null,
              last_disconnected_at:
                safeStr(
                  scopedRecord.lastDisconnectedAt ??
                    scopedRecord.last_disconnected_at,
                  64,
                ) || null,
              last_sync_at:
                safeStr(scopedRecord.lastSyncAt ?? scopedRecord.last_sync_at, 64) ||
                null,
              last_error_code:
                safeStr(
                  scopedRecord.lastErrorCode ?? scopedRecord.last_error_code,
                  120,
                ) || null,
              last_error_at:
                safeStr(scopedRecord.lastErrorAt ?? scopedRecord.last_error_at, 64) ||
                null,
              updated_at:
                safeStr(scopedRecord.updatedAt ?? scopedRecord.updated_at, 64) ||
                null,
            },
            200,
          );
        }

        const globalConfigured = !!(
          safeStr(env?.GOOGLE_CLIENT_ID) &&
          safeStr(env?.GOOGLE_CLIENT_SECRET) &&
          safeStr(env?.GOOGLE_REFRESH_TOKEN)
        );
        if (
          globalConfigured &&
          shouldAllowGlobalGoogleCalendarFallback(env, explicitScope)
        ) {
          return json(
            {
              ok: true,
              tenant_id: tenantId,
              company_id: companyId,
              source: "global_env",
              configured: true,
              connected: true,
              status: "legacy_global",
              calendar_id: safeStr(env?.GOOGLE_CALENDAR_ID, 160) || "primary",
            },
            200,
          );
        }

        return json(
          {
            ok: true,
            tenant_id: tenantId,
            company_id: companyId,
            source: "none",
            configured: false,
            connected: false,
            status: "not_configured",
          },
          200,
        );
      }

      // Home
      if (url.pathname === "/" && request.method === "GET") {
        return new Response(
          `Fluxidi Booking API ✅

Build: ${FLUXIDI_BUILD}

POST /quote
POST /lead
POST /availability (calendar)
POST /book (calendar + email + invoice)

Payments (Mollie):
POST /pay/create
POST /webhook/mollie
GET  /pay/status?id=
GET  /pay/return?id=

Invoice:
POST /invoice/preview
POST /invoice/pdf

OAuth:
GET /oauth/start
GET /oauth/callback
`,
          { headers: { "Content-Type": "text/plain; charset=utf-8", ...corsHeaders() } }
        );
      }

      // =========================
      // PAYMENTS (MOLLIE)
      // =========================

      // Create payment (PENDING booking saved in KV)
      if (url.pathname === "/pay/create" && request.method === "POST") {
        const body = await safeJson(request);
        const paymentScope = resolveExplicitBookingRequestScope({
          request,
          url,
          body,
          allowLegacyFallback: false,
        });
        if (!paymentScope?.hasScope) {
          return json(
            paymentScope?.error === "tenant_scope_conflict" ? scopeConflictError() : missingTenantScopeError(),
            400,
          );
        }
        const normalizedBody = {
          ...body,
          tenant_id: paymentScope.tenant_id,
          tenantId: paymentScope.tenant_id,
          company_id: paymentScope.company_id,
          companyId: paymentScope.company_id,
        };
        const out = await mollieCreatePayment(normalizedBody, env, request);
        return json(out, out.ok ? 200 : 400);
      }

      // Mollie webhook: verify payment -> if paid, confirm booking
      if (url.pathname === "/webhook/mollie" && request.method === "POST") {
        const out = await mollieWebhook(request, env);
        // Mollie expects 200 even if we already processed (idempotent)
        return json(out, 200);
      }

      // Debug status: check booking in KV
      if (url.pathname === "/pay/status" && request.method === "GET") {
        const statusScope = resolveExplicitBookingRequestScope({
          request,
          url,
          allowLegacyFallback: false,
        });
        if (!statusScope?.hasScope) {
          return json(
            statusScope?.error === "tenant_scope_conflict" ? scopeConflictError() : missingTenantScopeError(),
            400,
          );
        }
        return payStatus(request, env, statusScope);
      }

      // Simple return page (fallback redirectUrl)
      if (url.pathname === "/pay/return" && request.method === "GET") {
        const id = (url.searchParams.get("id") || "").trim();
        const requestedReturnTo = (url.searchParams.get("return_to") || "").trim();
        const recoveredScope = await _resolvePaymentReturnScope(env, id);
        // Default to the Fluxidi app deep link so the customer is bounced back automatically.
        const returnTo = requestedReturnTo || "fluxidi://pay/return";
        return html(`
          <div style="font-family: ui-sans-serif, system-ui; max-width: 860px; margin: 40px auto; line-height: 1.5;">
            <h1>✅ Bedankt!</h1>
            <p>We verwerken je booking nu. Dit kan enkele seconden duren.</p>
            <p><b>Booking ID:</b> ${escapeHtml(id || "(geen id)")}</p>

            <div id="fx-status" style="margin-top:18px;padding:14px;border:1px solid #e5e7eb;border-radius:12px;background:#fafafa;">
              Status: <b>Bezig met verwerken…</b>
            </div>

            <div id="fx-app-cta" style="margin-top:18px;display:none;">
              <a id="fx-app-link" href="#" style="display:inline-block;padding:12px 18px;border-radius:10px;background:#0F172A;color:#fff;text-decoration:none;font-weight:700;">Open Fluxidi app</a>
              <p style="margin-top:8px;color:#6b7280;font-size:13px;">Werkt de automatische terugkeer niet? Tik hierboven.</p>
            </div>

            <p style="margin-top:14px;color:#6b7280;font-size:14px;">
              Als dit scherm blijft hangen: open <code>/pay/status?id=${escapeHtml(id || "")}</code>.
            </p>
          </div>

          <script>
            (function(){
              const BOOKING_ID = ${JSON.stringify(id || "")};
              const RETURN_TO = ${JSON.stringify(returnTo || "")};
              const RECOVERED_SCOPE = ${JSON.stringify(
                recoveredScope?.hasScope
                  ? {
                      tenant_id: recoveredScope.tenant_id,
                      company_id: recoveredScope.company_id,
                    }
                  : null,
              )};
              const statusEl = document.getElementById('fx-status');
              const appCtaEl = document.getElementById('fx-app-cta');
              const appLinkEl = document.getElementById('fx-app-link');
              let appOpenAttempted = false;

              function setStatus(html){
                if (statusEl) statusEl.innerHTML = 'Status: ' + html;
              }

              function buildAppReturnUrl(humanId, paymentId){
                if (!RETURN_TO) return '';
                const sep = RETURN_TO.includes('?') ? '&' : '?';
                const params = new URLSearchParams();
                params.set('booking_id', humanId || '');
                params.set('payment_booking_id', paymentId || '');
                params.set('status', 'confirmed');
                if (RECOVERED_SCOPE && RECOVERED_SCOPE.tenant_id && RECOVERED_SCOPE.company_id) {
                  params.set('tenant_id', RECOVERED_SCOPE.tenant_id);
                  params.set('company_id', RECOVERED_SCOPE.company_id);
                  params.set('tenantId', RECOVERED_SCOPE.tenant_id);
                  params.set('companyId', RECOVERED_SCOPE.company_id);
                }
                return RETURN_TO + sep + params.toString();
              }

              function buildStatusUrl(){
                const params = new URLSearchParams();
                params.set('id', BOOKING_ID);
                if (RECOVERED_SCOPE && RECOVERED_SCOPE.tenant_id && RECOVERED_SCOPE.company_id) {
                  params.set('tenant_id', RECOVERED_SCOPE.tenant_id);
                  params.set('company_id', RECOVERED_SCOPE.company_id);
                  params.set('tenantId', RECOVERED_SCOPE.tenant_id);
                  params.set('companyId', RECOVERED_SCOPE.company_id);
                }
                return window.location.origin + '/pay/status?' + params.toString();
              }

              function showAppCta(target){
                if (!appCtaEl || !appLinkEl) return;
                appLinkEl.setAttribute('href', target);
                appCtaEl.style.display = 'block';
              }

              function attemptOpenApp(target){
                if (!target || appOpenAttempted) return;
                appOpenAttempted = true;
                showAppCta(target);
                try { window.location.assign(target); } catch (_) {}
                setTimeout(() => { try { window.location.href = target; } catch (_) {} }, 450);
                setTimeout(() => { try { window.open(target, '_self'); } catch (_) {} }, 1200);
              }

              async function poll(attempt){
                try {
                  const res = await fetch(buildStatusUrl(), { method: 'GET' });
                  const j = await res.json().catch(() => ({}));

                  if (!res.ok || !j || !j.ok) {
                    setStatus('<b>Wachten op bevestiging…</b> (probeer ' + attempt + ')');
                    return false;
                  }

                  const data = j.data || {};
                  const bookingHumanId = (data.booking_id || data.bookingId || data.public_booking_id || data.publicBookingId || '').toString();
                  const mollieStatus = String((data.mollie && data.mollie.status) || '').toLowerCase();
                  const paymentStatus = String(data.payment_status || data.paymentStatus || '').toLowerCase();
                  const confirmedAt = (data.confirmed_at || data.confirmedAt || '').toString().trim();
                  const confirmed = !!confirmedAt;
                  const paid = (mollieStatus === 'paid' || paymentStatus === 'paid');
                  const settledEnoughForApp = confirmed || paid;

                  if (settledEnoughForApp) {
                    (function(){
                      const dbg = (data && data.finalize_debug) ? data.finalize_debug : null;
                      let extra = '';
                      if (dbg && dbg.email) {
                        const so = dbg.email.sent_owner ? '✅' : '❌';
                        const sc = dbg.email.sent_customer ? '✅' : '❌';
                        extra += '<br><small>E-mail eigenaar: ' + so + ' • E-mail klant: ' + sc + '</small>';
                        if (dbg.email.errors && dbg.email.errors.length) {
                          extra += '<br><small style="color:#b45309">E-mail errors: ' + String(dbg.email.errors.join(' | ')).replace(/</g,'&lt;') + '</small>';
                        }
                      }
                      if (dbg && dbg.invoice) {
                        const inv = dbg.invoice.sent ? '✅' : '❌';
                        extra += '<br><small>Factuur e-mail: ' + inv + (dbg.invoice_number ? (' • ' + dbg.invoice_number) : '') + '</small>';
                        if (dbg.invoice.error) {
                          extra += '<br><small style="color:#b45309">Factuur error: ' + String(dbg.invoice.error).replace(/</g,'&lt;') + '</small>';
                        }
                      }
                      const title = confirmed
                        ? '<b>✅ Bevestigd!</b> Je booking is verwerkt.'
                        : '<b>Betaling ok ✅</b> We finaliseren je booking...';
                      setStatus(title + (bookingHumanId ? ('<br><small>Booking: ' + bookingHumanId + '</small>') : '') + extra);
                    })();
                    const target = buildAppReturnUrl(bookingHumanId, BOOKING_ID);
                    if (target) {
                      attemptOpenApp(target);
                    }
                    // If already confirmed, we can stop polling.
                    // If only paid/finalizing, keep polling in the background.
                    return confirmed;
                  }

                  if (paid && !confirmed) {
                    setStatus('<b>Betaling ok ✅</b> We finaliseren je booking…');
                    const target = buildAppReturnUrl(bookingHumanId, BOOKING_ID);
                    if (target) {
                      showAppCta(target);
                      // Force app return even before confirmed_at exists to avoid
                      // browser lock-in; Flutter will continue reconciliation via /pay/status.
                      if (attempt >= 2) attemptOpenApp(target);
                    }
                    return false;
                  }

                  setStatus('<b>Wachten op betaling…</b>');
                  return false;
                } catch (e) {
                  setStatus('<b>Wachten op bevestiging…</b>');
                  return false;
                }
              }

              let attempt = 1;
              (async function loop(){
                const done = await poll(attempt);
                if (done) return;
                if (attempt >= 30) {
                  const target = buildAppReturnUrl('', BOOKING_ID);
                  if (target) showAppCta(target);
                  setStatus('<b>⚠️ Nog niet bevestigd.</b> Open <code>/pay/status?id=' + BOOKING_ID + '</code> of probeer opnieuw.');
                  return;
                }
                attempt++;
                setTimeout(loop, 2000);
              })();
            })();
          </script>
        `, 200);
      }

      // =========================
      // QUOTE (SERVER-SIDE SOURCE OF TRUTH)
      // =========================
      if (url.pathname === "/quote" && request.method === "POST") {
        let body = {};
        try { body = await request.json(); }
        catch { return json({ ok: false, error: "Invalid JSON body" }, 400); }

        if (!body.from || !body.to || !body.date || !body.time) {
          return json({ ok: false, error: "Missing fields: from, to, date, time" }, 400);
        }

        const requestedPublicPartnerId = _extractRequestedPublicPartnerId({ url, body });
        let quoteScope = null;
        let routedPublicPartner = null;
        if (requestedPublicPartnerId) {
          routedPublicPartner = await resolvePublicPartnerBookingScope(
            env,
            requestedPublicPartnerId,
          );
          if (!routedPublicPartner?.ok) {
            return json({ ok: false, error: routedPublicPartner?.error || "invalid public partner" }, routedPublicPartner?.status || 400);
          }
          quoteScope = {
            tenant_id: routedPublicPartner.tenant_id,
            company_id: routedPublicPartner.company_id,
            hasScope: true,
          };
        } else {
          const allowLegacyScopeFallback = String(env?.ALLOW_LEGACY_SCOPE_FALLBACK || "").trim().toLowerCase() === "true";
          quoteScope = resolveExplicitBookingRequestScope({
            request,
            url,
            body,
            allowLegacyFallback: allowLegacyScopeFallback,
          });
        }
        if (!quoteScope?.hasScope) {
          return json(
            quoteScope?.error === "tenant_scope_conflict" ? scopeConflictError() : missingTenantScopeError(),
            400,
          );
        }
        body = {
          ...body,
          tenant_id: quoteScope.tenant_id,
          tenantId: quoteScope.tenant_id,
          company_id: quoteScope.company_id,
          companyId: quoteScope.company_id,
          ...(routedPublicPartner?.ok
            ? {
                public_partner_id: routedPublicPartner.partner_id,
                publicPartnerId: routedPublicPartner.partner_id,
                partner_id: routedPublicPartner.partner_id,
                partnerId: routedPublicPartner.partner_id,
              }
            : {}),
        };
        const pricingProfile = await _loadTenantPricingProfile(env, quoteScope);
        const vat_rate = clampNumber(
          pricingProfile?.vat_rate,
          clampNumber(body.vat_rate, 0.06, 0, 1),
          0,
          1,
        );

        // Enforce business rules (Tesla Model 3)
        const pax = clampInt(body.pax, 1, 3);
        const bags = Math.max(0, clampInt(body.bags, 0, 99));

        const tier = normalizeTier(body.tier || "comfort");
        const service = normalizeService(body.service || "passenger");

        // Stops + wait (tolerant input)
        const stops = normalizeStops(body); // array of stop addresses
        const wait_min = parseDurationMin(body.wait_min ?? body.wait_minutes ?? body.waiting_min ?? body.wait, 0);
        const stop_count = stops.length;
        

        // ✅ Business detection (NEW)
        const biz = normalizeBusiness(body);
        const business_detected = !!biz.vat_number;
        const invoice_requested = business_detected ? true : !!biz.invoice_requested;

        // Route WITH waypoints + per-leg breakdown
        const routeOut = await routeFromTextsWithStopsDetailed({
          fromText: body.from,
          toText: body.to,
          stopsTexts: stops,
          token: env.MAPBOX_TOKEN
        });

        const route = routeOut.route;
        const legs = routeOut.legs || [];

        const distance_km = round1(route.distance / 1000);
        const duration_route_min = Math.round(route.duration / 60);

        const mainWhen = normalizeWhen(body.date, body.time);

        // Pricing: server truth
        const mainPricing = calcPrice({
          distance_km,
          duration_min: duration_route_min,
          tier,
          service,
          when: mainWhen,
          time_str: body.time,
          pax,
          bags,
          vat_rate,
          stop_count,
          wait_min,
          pricing_profile: pricingProfile,
          apply_return_fee: false,
        });

        // ✅ Optional return trip quote (client sends return_enabled + return_* fields)
        let returnQuote = null;
        try {
          if (pricingProfile.return_enabled && body.return_enabled && body.return_date && body.return_time) {
            const rf = body.return_from || body.to;
            const rt = body.return_to || body.from;
            if (!rf || !rt) throw new Error('Missing return_from/return_to');
            const retRouteOut = await routeFromTextsWithStopsDetailed({
              fromText: rf,
              toText: rt,
              stopsTexts: [],
              token: env.MAPBOX_TOKEN
            });

            const retRoute = retRouteOut.route;
            const retDistance_km = round1(retRoute.distance / 1000);
            const retDuration_min = Math.round(retRoute.duration / 60);
            const retWhen = normalizeWhen(body.return_date, body.return_time);

            const retPricing = calcPrice({
              distance_km: retDistance_km,
              duration_min: retDuration_min,
              tier,
              service,
              when: retWhen,
              time_str: body.return_time,
              pax,
              bags,
              vat_rate,
              stop_count: 0,
              wait_min: 0,
              pricing_profile: pricingProfile,
              apply_return_fee: true,
            });

            returnQuote = {
              distance_km: retDistance_km,
              duration_min: retDuration_min,
              price_ex_vat: retPricing.price_ex_vat,
              price_vat: retPricing.price_vat,
              price_incl_vat: retPricing.price_incl_vat,
              note: retPricing.note
            };
          }
        } catch (e) {
          // If return quote fails, we keep main quote and simply omit returnQuote
          returnQuote = null;
        }

        return json({
          ok: true,
          inputs: {
            from: body.from,
            to: body.to,
            date: body.date,
            time: body.time,
            tier,
            service,
            pax,
            bags,
            vat_rate,
            stop_count,
            wait_min,
            stops,

            // ✅ business fields echoed back
            business_detected,
            invoice_requested,
            company_name: biz.company_name || "",
            vat_number: biz.vat_number || ""
          },
          distance_km,
          duration_min: duration_route_min,
          legs,

          price_ex_vat: mainPricing.price_ex_vat,
          price_vat: mainPricing.price_vat,
          price_incl_vat: mainPricing.price_incl_vat,
          note: mainPricing.note,
          pricing_profile: pricingProfile,

          // totals (main + optional return)
          total_price_ex_vat: round2((mainPricing.price_ex_vat || 0) + (returnQuote ? (returnQuote.price_ex_vat || 0) : 0)),
          total_price_vat: round2((mainPricing.price_vat || 0) + (returnQuote ? (returnQuote.price_vat || 0) : 0)),
          total_price_incl_vat: round2((mainPricing.price_incl_vat || 0) + (returnQuote ? (returnQuote.price_incl_vat || 0) : 0)),

          return: returnQuote,
          breakdown: mainPricing.breakdown
        });
      }

      // LEAD
      if (url.pathname === "/lead" && request.method === "POST") return json({ ok: true });

      // AVAILABILITY
      if (url.pathname === "/availability" && request.method === "POST") {
        const body = await safeJson(request);
        const out = await handleAvailability(body, env, request, url);
        return json(out, 200);
      }

      // =========================
      // INVOICE PREVIEW (HTML)
      // =========================
      if (url.pathname === "/invoice/preview" && request.method === "POST") {
        const body = await safeJson(request);
        const demo = normalizeInvoiceInputForTest(body);
        const commProfile = await resolveTenantCommunicationProfile(env);
        const htmlOut = renderInvoiceHtml(env, demo, commProfile);
        return html(htmlOut, 200);
      }

      // =========================
      // INVOICE PDF (TEST)
      // =========================
      if (url.pathname === "/invoice/pdf" && request.method === "POST") {
        const body = await safeJson(request);
        const demo = normalizeInvoiceInputForTest(body);
        const commProfile = await resolveTenantCommunicationProfile(env);
        const htmlOut = renderInvoiceHtml(env, demo, commProfile);

        const pdfBytes = await renderPdfFromHtml(htmlOut, env);
        if (!pdfBytes) {
          return json({
            ok: false,
            error: "PDF rendering not configured. Set PDFSHIFT_API_KEY (preferred) or set PDF_RENDER_URL (and optionally PDF_RENDER_KEY).",
            hint: "You can still use /invoice/preview to see the HTML."
          }, 500);
        }

        return new Response(pdfBytes, {
          status: 200,
          headers: {
            "Content-Type": "application/pdf",
            "Content-Disposition": `inline; filename="factuur-${demo.invoiceNumber}.pdf"`,
            ...corsHeaders()
          }
        });
      }

      // BOOK
      if (url.pathname === "/book" && request.method === "POST") {
        const body = await safeJson(request);
        const requestedPublicPartnerId = _extractRequestedPublicPartnerId({
          url,
          body,
        });
        let requestScope = null;
        let routedPublicPartner = null;
        if (requestedPublicPartnerId) {
          routedPublicPartner = await resolvePublicPartnerBookingScope(
            env,
            requestedPublicPartnerId,
          );
          if (!routedPublicPartner?.ok) {
            return json(
              { ok: false, error: routedPublicPartner?.error || "invalid public partner" },
              routedPublicPartner?.status || 400,
            );
          }
          requestScope = {
            tenant_id: routedPublicPartner.tenant_id,
            company_id: routedPublicPartner.company_id,
            hasScope: true,
          };
        } else {
          const allowLegacyScopeFallback = String(env?.ALLOW_LEGACY_SCOPE_FALLBACK || "").trim().toLowerCase() === "true";
          requestScope = resolveExplicitBookingRequestScope({
            request,
            url,
            body,
            allowLegacyFallback: allowLegacyScopeFallback,
          });
        }
        if (!requestScope?.hasScope) {
          return json(
            requestScope?.error === "tenant_scope_conflict" ? scopeConflictError() : missingTenantScopeError(),
            400,
          );
        }
        const normalizedBody = {
          ...body,
          tenant_id: requestScope.tenant_id,
          tenantId: requestScope.tenant_id,
          company_id: requestScope.company_id,
          companyId: requestScope.company_id,
          ...(routedPublicPartner?.ok
            ? {
                public_partner_id: routedPublicPartner.partner_id,
                publicPartnerId: routedPublicPartner.partner_id,
                partner_id: routedPublicPartner.partner_id,
                partnerId: routedPublicPartner.partner_id,
              }
            : {}),
        };
        const out = await handleBooking(normalizedBody, env, request);
        // Build tag helps verify correct deployment
        if (out && typeof out === "object") out.build = "v15-2026-01-20-gcal-hardfix";
        return json(out, 200);
      }

      // PUBLIC BOOTSTRAP (phase 2B, read-only)
      if (url.pathname === "/public/bootstrap") {
        if (request.method !== "GET") {
          return json({ ok: false, error: "method_not_allowed" }, 405);
        }
        return handlePublicBootstrap(url, env);
      }

      // PUBLIC BOOKING PREVIEW (phase 3A, read-only)
      if (url.pathname === "/public/book") {
        if (request.method !== "GET") {
          return json({ ok: false, error: "method_not_allowed" }, 405);
        }
        return handlePublicBookingPreview(url, env);
      }

      // PUBLIC MEDIA (read-only, path-limited)
      if (url.pathname.startsWith("/public/media/") && request.method === "GET") {
        const keyPart = url.pathname.slice("/public/media/".length);
        const decodedKey = _decodePublicMediaKeyFromPath(keyPart);
        const keyValidation = _validatePublicMediaReadKey(decodedKey);
        if (!keyValidation.ok) {
          return json({ ok: false, error: keyValidation.error }, 400);
        }
        if (!env.PUBLIC_MEDIA) {
          return json({ ok: false, error: "PUBLIC_MEDIA binding is missing" }, 500);
        }
        const object = await env.PUBLIC_MEDIA.get(decodedKey);
        if (!object) {
          return new Response("Not Found", { status: 404, headers: corsHeaders() });
        }
        const headers = new Headers(corsHeaders());
        if (typeof object.writeHttpMetadata === "function") {
          object.writeHttpMetadata(headers);
        }
        if (!headers.has("Content-Type")) {
          headers.set("Content-Type", "application/octet-stream");
        }
        if (!headers.has("Cache-Control")) {
          headers.set("Cache-Control", "public, max-age=3600, stale-while-revalidate=86400");
        }
        if (object.httpEtag) headers.set("ETag", object.httpEtag);
        return new Response(object.body, { status: 200, headers });
      }

      // =========================
      // AUTHORITATIVE BOOKINGS API (minimal v1 for app rides list/lifecycle)
      // =========================
      // GET /bookings?limit=50&include_history=1
      if (url.pathname === "/bookings" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const limit = Number(url.searchParams.get("limit") || "50");
        const includeHistory =
          (url.searchParams.get("include_history") || "").toLowerCase() === "1";
        const scopedRoute = requireExplicitBookingRouteScope({ request, url });
        if (!scopedRoute.ok) return scopedRoute.response;
        const tenantScope = scopedRoute.scope;
        const items = await listBookingsAuthoritative(env, {
          limit,
          includeHistory,
          tenantScope,
        });
        return json({ ok: true, items, count: items.length }, 200);
      }

      if (
        url.pathname === "/admin/dashboard/bookings-kpis" &&
        request.method === "GET"
      ) {
        _requireAdmin(request, url, env);
        const scopedRoute = requireExplicitBookingRouteScope({ request, url });
        if (!scopedRoute.ok) return scopedRoute.response;
        const out = await computeDashboardBookingsKpis(env, {
          tenantScope: scopedRoute.scope,
        });
        if (!out?.ok) {
          return json(out, out?.error === "tenant_scope_conflict" ? 409 : 400);
        }
        return json(out, 200);
      }

      // GET /partners/nearby?postcode=...
      if (url.pathname === "/partners/nearby" && request.method === "GET") {
        const postcode = String(url.searchParams.get("postcode") || "").trim();
        if (!postcode) {
          return json({ ok: false, error: "postcode is required" }, 400);
        }
        const partners = await listNearbyPartnersByPostcode(env, postcode);
        return json({
          ok: true,
          postcode,
          count: partners.length,
          partners,
        }, 200);
      }

      // GET /partners/profile?partner_id=...
      if (url.pathname === "/partners/profile" && request.method === "GET") {
        const partnerId = String(
          url.searchParams.get("partner_id") || url.searchParams.get("partnerId") || "",
        ).trim();
        if (!partnerId) {
          return json({ ok: false, error: "partner_id is required" }, 400);
        }
        const profile = await getPublicPartnerProfileById(env, partnerId);
        if (!profile) {
          return json({ ok: false, error: "partner profile not found" }, 404);
        }
        return json({ ok: true, profile }, 200);
      }

      // POST /bookings/availability-check (alias for existing /availability)
      if (url.pathname === "/bookings/availability-check" && request.method === "POST") {
        const body = await safeJson(request);
        const out = await handleAvailability(body, env, request, url);
        return json(out, 200);
      }

      // Minimal admin fleet inventory endpoints (testing-only foundation)
      if (url.pathname === "/admin/fleet/vehicles" && request.method === "GET") {
        _requireAdmin(request, url, env);
        if (!env.BOOKING_KV) return json({ ok: false, error: "BOOKING_KV binding is missing" }, 500);
        const requestedScope = extractBookingTenantScope({ request, url });
        if (!requestedScope.tenant_id || !requestedScope.company_id) {
          return json({ ok: false, error: "tenant_id and company_id are required" }, 400);
        }
        const scope = normalizeFleetTenantScope(requestedScope);
        const includeLegacyFallback =
          String(url.searchParams.get("include_legacy_fallback") || "").trim().toLowerCase() ===
          "true";
        const fleetRead = await _loadFleetInventoryRawForScope(env, scope, {
          allowLegacyFallback: includeLegacyFallback,
        });
        const vehicles = fleetRead.vehiclesRaw;
        const normalized = vehicles
          .map((entry) => _normalizeVehicleEntry(entry, { scope }))
          .filter((v) => v !== null);
        const response = {
          ok: true,
          key: fleetRead.key,
          source: fleetRead.source,
          scoped_key: fleetRead.scoped_key,
          legacy_key: fleetRead.legacy_key,
          count: normalized.length,
          vehicles: normalized,
        };
        if (includeLegacyFallback) {
          // Legacy fleet fallback is diagnostic/read-only only; scoped fleet stays the active operational source.
          const diagnosticLegacy = (fleetRead.legacyVehiclesRaw || [])
            .map(_normalizeVehicleEntry)
            .filter(
              (vehicle) =>
                vehicle !== null &&
                _scopeText(vehicle.tenant_id ?? vehicle.tenantId) === scope.tenant_id &&
                _scopeText(vehicle.company_id ?? vehicle.companyId) === scope.company_id,
            );
          response.legacy_diagnostic_enabled = true;
          response.legacy_diagnostic_source = "legacy_read_only";
          response.diagnostic_legacy_count = diagnosticLegacy.length;
          response.diagnostic_legacy_vehicles = diagnosticLegacy;
        }
        return json(response, 200);
      }

      if (url.pathname === "/admin/fleet/vehicles" && request.method === "POST") {
        _requireAdmin(request, url, env);
        if (!env.BOOKING_KV) return json({ ok: false, error: "BOOKING_KV binding is missing" }, 500);
        const body = await safeJson(request);
        const requestedScope = extractBookingTenantScope({ request, url, body });
        if (!requestedScope.tenant_id || !requestedScope.company_id) {
          return json({ ok: false, error: "tenant_id and company_id are required" }, 400);
        }
        const scope = normalizeFleetTenantScope(requestedScope);
        const incoming = Array.isArray(body)
          ? body
          : (Array.isArray(body?.vehicles) ? body.vehicles : null);
        if (!Array.isArray(incoming)) {
          return json({ ok: false, error: "Body must be an array or { vehicles: [] }" }, 400);
        }
        for (const row of incoming) {
          if (!row || typeof row !== "object") continue;
          const rowTenantId = _scopeText(row.tenant_id ?? row.tenantId);
          const rowCompanyId = _scopeText(row.company_id ?? row.companyId);
          if (
            (rowTenantId && rowTenantId !== scope.tenant_id) ||
            (rowCompanyId && rowCompanyId !== scope.company_id)
          ) {
            return json(
              { ok: false, error: "vehicle row scope does not match request scope" },
              400,
            );
          }
        }
        const normalized = incoming
          .map((entry) => _normalizeVehicleEntry(entry, { scope }))
          .filter((v) => v !== null);
        const scopedKey = fleetInventoryScopedKeyForScope(scope);
        const payload = {
          version: 1,
          updated_at: new Date().toISOString(),
          vehicles: normalized,
        };
        await env.BOOKING_KV.put(scopedKey, JSON.stringify(payload));
        return json({
          ok: true,
          key: scopedKey,
          source: "scoped",
          scoped_key: scopedKey,
          legacy_key: VEHICLE_INVENTORY_KEY,
          count: normalized.length,
          vehicles: normalized,
        }, 200);
      }

      if (url.pathname === "/admin/pricing/profile" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const profile = await _loadTenantPricingProfile(env, explicitScope, {
          allowTenantLegacyFallback: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.pricingProfileKey || TENANT_PRICING_PROFILE_KEY,
          pricing_profile: profile,
        }, 200);
      }

      if (url.pathname === "/admin/pricing/profile" && request.method === "POST") {
        _requireAdmin(request, url, env);
        if (!env.BOOKING_KV) return json({ ok: false, error: "BOOKING_KV binding is missing" }, 500);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url, body });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const incoming = body?.pricing_profile && typeof body.pricing_profile === "object"
          ? body.pricing_profile
          : body;
        const bodyScopeCheck = _validateSettingsPayloadScope(body, explicitScope);
        if (!bodyScopeCheck.ok) return json(bodyScopeCheck, 400);
        const incomingScopeCheck = _validateSettingsPayloadScope(incoming, explicitScope);
        if (!incomingScopeCheck.ok) return json(incomingScopeCheck, 400);
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const normalized = await _saveTenantPricingProfile(env, incoming, explicitScope, {
          allowTenantLegacyWrite: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.pricingProfileKey || TENANT_PRICING_PROFILE_KEY,
          pricing_profile: normalized,
        }, 200);
      }

      if (url.pathname === "/admin/business/profile" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const profile = await loadBusinessProfile(env, explicitScope, {
          allowTenantLegacyFallback: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.businessProfileKey || TENANT_BUSINESS_PROFILE_KEY,
          business_profile: profile,
        }, 200);
      }

      if (url.pathname === "/admin/business/profile" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url, body });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const incoming = body?.business_profile && typeof body.business_profile === "object"
          ? body.business_profile
          : body;
        const bodyScopeCheck = _validateSettingsPayloadScope(body, explicitScope);
        if (!bodyScopeCheck.ok) return json(bodyScopeCheck, 400);
        const incomingScopeCheck = _validateSettingsPayloadScope(incoming, explicitScope);
        if (!incomingScopeCheck.ok) return json(incomingScopeCheck, 400);
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const profile = await saveBusinessProfile(env, incoming, explicitScope, {
          allowTenantLegacyWrite: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.businessProfileKey || TENANT_BUSINESS_PROFILE_KEY,
          business_profile: profile,
        }, 200);
      }

      if (url.pathname === "/admin/partners/media/upload" && request.method === "POST") {
        _requireAdmin(request, url, env);
        if (!env.PUBLIC_MEDIA) return json({ ok: false, error: "PUBLIC_MEDIA binding is missing" }, 500);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const tenantId = sanitizeTenantString(explicitScope.tenant_id, 120);
        const companyId = sanitizeTenantString(explicitScope.company_id, 120);
        if (!tenantId || !companyId) {
          return json({ ok: false, error: "tenant_id and company_id are required" }, 400);
        }
        const contentType = String(request.headers.get("content-type") || "").toLowerCase();
        if (!contentType.includes("multipart/form-data")) {
          return json({ ok: false, error: "multipart/form-data is required" }, 400);
        }
        const form = await request.formData();
        const mediaType = sanitizeTenantString(form.get("media_type"), 64).toLowerCase();
        const mediaTypeValidation = _validateCompanyMediaType(mediaType);
        if (!mediaTypeValidation.ok) {
          return json({ ok: false, error: mediaTypeValidation.error }, 400);
        }
        const entityIdValidation = _validatePublicMediaEntityId(
          mediaType,
          form.get("entity_id"),
        );
        if (!entityIdValidation.ok) {
          return json({ ok: false, error: entityIdValidation.error }, 400);
        }
        const filePart = form.get("file");
        if (!filePart || typeof filePart.arrayBuffer !== "function") {
          return json({ ok: false, error: "file is required" }, 400);
        }
        const bytes = new Uint8Array(await filePart.arrayBuffer());
        if (!bytes.length) return json({ ok: false, error: "file is empty" }, 400);
        if (bytes.length > 5 * 1024 * 1024) {
          return json({ ok: false, error: "file exceeds 5MB limit" }, 400);
        }
        const declaredType = String(filePart.type || "").trim().toLowerCase();
        const declaredUnknownOrMissing =
          !declaredType ||
          declaredType === "application/octet-stream" ||
          declaredType === "binary/octet-stream";
        const declaredAllowed = _isAllowedPublicImageContentType(declaredType);
        if (!declaredUnknownOrMissing && !declaredAllowed) {
          return json({ ok: false, error: "unsupported content type" }, 400);
        }
        const detected = _detectPublicImageFormat(bytes);
        if (!detected.ok) return json({ ok: false, error: "unsupported content type" }, 400);
        if (declaredAllowed && declaredType !== detected.content_type) {
          return json({ ok: false, error: "content_type_mismatch" }, 400);
        }

        const objectKey = _buildPublicCompanyMediaKey({
          tenantId,
          companyId,
          mediaType,
          entityId: entityIdValidation.entity_id,
          ext: detected.ext,
        });
        await env.PUBLIC_MEDIA.put(objectKey, bytes, {
          httpMetadata: {
            contentType: detected.content_type,
            cacheControl: "public, max-age=3600, stale-while-revalidate=86400",
          },
        });
        const uploadedAt = Date.now();
        const mediaUrl =
          `${url.origin}/public/media/${_encodePublicMediaKeyForUrl(objectKey)}?v=${uploadedAt}`;
        return json({
          ok: true,
          media_type: mediaType,
          entity_id: entityIdValidation.entity_id || "",
          key: objectKey,
          url: mediaUrl,
          uploaded_at: uploadedAt,
          content_type: detected.content_type,
          size: bytes.length,
        }, 200);
      }

      if (url.pathname === "/admin/partners/profile/publish" && request.method === "POST") {
        _requireAdmin(request, url, env);
        if (!env.BOOKING_KV) return json({ ok: false, error: "BOOKING_KV binding is missing" }, 500);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url, body });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const incoming = body?.partner_profile && typeof body.partner_profile === "object"
          ? body.partner_profile
          : body;
        if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
          return json({ ok: false, error: "partner_profile object is required" }, 400);
        }
        const bodyScopeCheck = _validateSettingsPayloadScope(body, explicitScope);
        if (!bodyScopeCheck.ok) return json(bodyScopeCheck, 400);
        const incomingScopeCheck = _validateSettingsPayloadScope(incoming, explicitScope);
        if (!incomingScopeCheck.ok) return json(incomingScopeCheck, 400);

        const scopeCompanyId = sanitizeTenantString(explicitScope.company_id, 120);
        const normalizedProfile = _normalizePublicPartnerProfileEntry({
          ...incoming,
          partner_id: incoming.partner_id ?? incoming.partnerId ?? scopeCompanyId,
          company_name: incoming.company_name ?? incoming.companyName,
        });
        if (!normalizedProfile) {
          return json({ ok: false, error: "invalid partner_profile payload" }, 400);
        }

        const rawProfiles = await env.BOOKING_KV.get(PARTNER_PROFILES_KEY, { type: "json" });
        const currentProfiles = Array.isArray(rawProfiles)
          ? rawProfiles
          : (rawProfiles && typeof rawProfiles === "object" && Array.isArray(rawProfiles.profiles)
              ? rawProfiles.profiles
              : []);
        const existingProfiles = currentProfiles
          .map(_normalizePublicPartnerProfileEntry)
          .filter((p) => p !== null);
        const nextProfiles = existingProfiles
          .filter((p) => p.partner_id !== normalizedProfile.partner_id)
          .concat([normalizedProfile]);
        await env.BOOKING_KV.put(
          PARTNER_PROFILES_KEY,
          JSON.stringify({ profiles: nextProfiles }),
        );

        const normalizedDirectoryEntry = _normalizePartnerEntry({
          partner_id: normalizedProfile.partner_id,
          company_name: normalizedProfile.company_name,
          is_active: normalizedProfile.is_active === true,
          subscription_status: normalizedProfile.subscription_status,
          primary_postcode: normalizedProfile?.coverage?.primary_postcode ?? "",
          supported_postcodes: Array.isArray(normalizedProfile?.coverage?.postcodes)
            ? normalizedProfile.coverage.postcodes
            : [],
        });
        if (!normalizedDirectoryEntry) {
          return json({ ok: false, error: "invalid directory projection" }, 400);
        }
        const rawDirectory = await env.BOOKING_KV.get(PARTNER_DIRECTORY_KEY, { type: "json" });
        const currentDirectory = Array.isArray(rawDirectory)
          ? rawDirectory
          : (rawDirectory && typeof rawDirectory === "object" && Array.isArray(rawDirectory.partners)
              ? rawDirectory.partners
              : []);
        const existingDirectory = currentDirectory
          .map(_normalizePartnerEntry)
          .filter((p) => p !== null);
        const nextDirectory = existingDirectory
          .filter((p) => p.partner_id !== normalizedDirectoryEntry.partner_id)
          .concat([normalizedDirectoryEntry]);
        await env.BOOKING_KV.put(
          PARTNER_DIRECTORY_KEY,
          JSON.stringify({ partners: nextDirectory }),
        );

        const partnerRouteEntry = _normalizePartnerBookingRouteEntry({
          partner_id: normalizedProfile.partner_id,
          tenant_id: explicitScope.tenant_id,
          company_id: explicitScope.company_id,
          company_name: normalizedProfile.company_name,
          is_active: normalizedProfile.is_active === true,
          subscription_status: normalizedProfile.subscription_status,
          updated_at: new Date().toISOString(),
        });
        if (!partnerRouteEntry) {
          return json({ ok: false, error: "invalid partner booking route projection" }, 400);
        }
        const rawRoutes = await env.BOOKING_KV.get(PARTNER_BOOKING_ROUTE_KEY, {
          type: "json",
        });
        const currentRoutes = Array.isArray(rawRoutes)
          ? rawRoutes
          : (rawRoutes && typeof rawRoutes === "object" && Array.isArray(rawRoutes.routes)
              ? rawRoutes.routes
              : []);
        const existingRoutes = currentRoutes
          .map(_normalizePartnerBookingRouteEntry)
          .filter((entry) => entry !== null);
        const nextRoutes = existingRoutes
          .filter((entry) => entry.partner_id !== partnerRouteEntry.partner_id)
          .concat([partnerRouteEntry]);
        await env.BOOKING_KV.put(
          PARTNER_BOOKING_ROUTE_KEY,
          JSON.stringify({ routes: nextRoutes }),
        );

        return json({
          ok: true,
          profile: normalizedProfile,
          directory_entry: normalizedDirectoryEntry,
          booking_route: partnerRouteEntry,
        }, 200);
      }

      if (url.pathname === "/admin/tax/profile" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const profile = await loadTaxProfile(env, explicitScope, {
          allowTenantLegacyFallback: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.taxProfileKey || TENANT_TAX_PROFILE_KEY,
          tax_profile: profile,
        }, 200);
      }

      if (url.pathname === "/admin/tax/profile" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url, body });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const incoming = body?.tax_profile && typeof body.tax_profile === "object"
          ? body.tax_profile
          : body;
        const bodyScopeCheck = _validateSettingsPayloadScope(body, explicitScope);
        if (!bodyScopeCheck.ok) return json(bodyScopeCheck, 400);
        const incomingScopeCheck = _validateSettingsPayloadScope(incoming, explicitScope);
        if (!incomingScopeCheck.ok) return json(incomingScopeCheck, 400);
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const profile = await saveTaxProfile(env, incoming, explicitScope, {
          allowTenantLegacyWrite: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.taxProfileKey || TENANT_TAX_PROFILE_KEY,
          tax_profile: profile,
        }, 200);
      }

      if (url.pathname === "/admin/subscription/profile" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const profile = await loadSubscriptionProfile(env, explicitScope, {
          allowTenantLegacyFallback: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.subscriptionProfileKey || TENANT_SUBSCRIPTION_PROFILE_KEY,
          subscription_profile: profile,
        }, 200);
      }

      if (url.pathname === "/admin/subscription/profile" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url, body });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const incoming = body?.subscription_profile && typeof body.subscription_profile === "object"
          ? body.subscription_profile
          : body;
        const bodyScopeCheck = _validateSettingsPayloadScope(body, explicitScope);
        if (!bodyScopeCheck.ok) return json(bodyScopeCheck, 400);
        const incomingScopeCheck = _validateSettingsPayloadScope(incoming, explicitScope);
        if (!incomingScopeCheck.ok) return json(incomingScopeCheck, 400);
        const scopedKeys = buildScopedSettingsKeys(explicitScope);
        const profile = await saveSubscriptionProfile(env, incoming, explicitScope, {
          allowTenantLegacyWrite: false,
        });
        return json({
          ok: true,
          key: scopedKeys?.subscriptionProfileKey || TENANT_SUBSCRIPTION_PROFILE_KEY,
          subscription_profile: profile,
        }, 200);
      }

      if (url.pathname === "/admin/communication/templates" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const scopedKey = communicationTemplatesScopedKeyForScope(explicitScope);
        const templates = await loadCommunicationTemplates(env, explicitScope, null, {
          allowTenantLegacyFallback: false,
        });
        return json({
          ok: true,
          key: scopedKey || TENANT_COMMUNICATION_TEMPLATES_KEY,
          communication_templates: templates,
        }, 200);
      }

      if (url.pathname === "/admin/communication/templates" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const explicitScope = resolveAdminExplicitTenantCompanyScope({ request, url, body });
        if (!explicitScope?.hasScope) {
          return json(missingTenantScopeError(), 400);
        }
        const incoming = body?.communication_templates && typeof body.communication_templates === "object"
          ? body.communication_templates
          : body;
        const bodyScopeCheck = _validateSettingsPayloadScope(body, explicitScope);
        if (!bodyScopeCheck.ok) return json(bodyScopeCheck, 400);
        const incomingScopeCheck = _validateSettingsPayloadScope(incoming, explicitScope);
        if (!incomingScopeCheck.ok) return json(incomingScopeCheck, 400);
        const scopedKey = communicationTemplatesScopedKeyForScope(explicitScope);
        const templates = await saveCommunicationTemplates(
          env,
          incoming,
          explicitScope,
          null,
          { allowTenantLegacyWrite: false },
        );
        return json({
          ok: true,
          key: scopedKey || TENANT_COMMUNICATION_TEMPLATES_KEY,
          communication_templates: templates,
        }, 200);
      }

      // DEV/TEST ONLY. Must be disabled or protected before production.
      if (url.pathname === "/admin/dev/reset-operational-data/dry-run" && request.method === "GET") {
        if (!allowDevResetEndpoints(env)) {
          return json({ ok: false, error: "dev reset endpoints are disabled" }, 403);
        }
        return await handleSafeResetDryRun(request, url, env);
      }

      // DEV/TEST ONLY. Must be disabled or protected before production.
      if (url.pathname === "/admin/dev/reset-operational-data" && request.method === "POST") {
        if (!allowDevResetEndpoints(env)) {
          return json({ ok: false, error: "dev reset endpoints are disabled" }, 403);
        }
        return await handleSafeResetOperationalData(request, url, env);
      }

      // Raw persisted booking debug for overlap reconstruction audits
      if (url.pathname === "/debug/fleet/recent-bookings" && request.method === "GET") {
        _requireAdmin(request, url, env);
        const scopedRoute = requireExplicitBookingRouteScope({ request, url });
        if (!scopedRoute.ok) return scopedRoute.response;
        const tenantScope = scopedRoute.scope;
        const out = await debugFleetRecentBookings(url, env, tenantScope);
        return json(out, 200);
      }

      // Debug-only fleet availability simulation (no booking creation)
      if (url.pathname === "/debug/fleet/availability" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const scopedRoute = requireExplicitBookingRouteScope({ request, url, body });
        if (!scopedRoute.ok) return scopedRoute.response;
        const tenantScope = scopedRoute.scope;
        const out = await debugFleetAvailability(body, env, tenantScope);
        return json(out, out.ok ? 200 : 400);
      }

      // Dynamic booking routes:
      // GET  /bookings/:id
      // POST /bookings/:id/status
      // POST /bookings/:id/payment
      // POST /bookings/:id/receipt/email
      // POST /bookings/:id/assign (placeholder for future)
      // POST /bookings/:id/delete
      if (pathParts.length >= 2 && pathParts[0] === "bookings") {
        const bookingId = decodeURIComponent(pathParts[1] || "").trim();
        if (!bookingId) return json({ ok: false, error: "booking_id is required" }, 400);

        if (pathParts.length === 2 && request.method === "GET") {
          const scopedRoute = requireExplicitBookingRouteScope({ request, url });
          if (!scopedRoute.ok) return scopedRoute.response;
          const tenantScope = scopedRoute.scope;
          let preloadedRec = null;
          const adminAuthorized = hasValidAdminToken(request, url, env);
          if (!adminAuthorized) {
            const loaded = await loadBookingRecord(env, bookingId);
            preloadedRec = loaded?.rec || null;
            const proof = _requestCustomerContactProof({ url });
            if (!customerProofMatchesBooking(preloadedRec, proof)) {
              return json({ ok: false, error: "customer ownership verification failed" }, 403);
            }
          }
          const out = await getBookingAuthoritative(bookingId, env, tenantScope, preloadedRec);
          return json(
            out,
            out?.error === "missing_tenant_scope"
              ? 400
              : (out?.error === "forbidden" ? 403 : 200),
          );
        }

        if (
          pathParts.length === 3 &&
          pathParts[2] === "status" &&
          request.method === "POST"
        ) {
          const body = await safeJson(request);
          const scopedRoute = requireExplicitBookingRouteScope({ request, url, body });
          if (!scopedRoute.ok) return scopedRoute.response;
          const tenantScope = scopedRoute.scope;
          const { rec } = await loadBookingRecord(env, bookingId);
          const actorRole = _scopeText(body?.actor_role ?? body?.actorRole, 32).toLowerCase();
          const adminAuthorized = hasValidAdminToken(request, url, env);
          if (!adminAuthorized) {
            if (actorRole === "customer") {
              const proof = _requestCustomerContactProof({ url, body });
              if (!customerProofMatchesBooking(rec, proof)) {
                return json({ ok: false, error: "customer ownership verification failed" }, 403);
              }
            } else if (actorRole === "driver") {
              const ownershipBlock = await enforceDriverOwnershipForMutation({
                request,
                url,
                body,
                rec,
                tenantScope,
                env,
              });
              if (ownershipBlock) {
                return json({ ok: false, error: "booking_not_assigned_to_driver" }, 403);
              }
            } else {
              return json({ ok: false, error: "Unauthorized" }, 401);
            }
          }
          const ownershipBlock = await enforceDriverOwnershipForMutation({
            request,
            url,
            body,
            rec,
            tenantScope,
            env,
          });
          if (ownershipBlock) {
            return json({ ok: false, error: "booking_not_assigned_to_driver" }, 403);
          }
          const out = await updateBookingStatusAuthoritative(
            bookingId,
            body?.status,
            env,
            tenantScope,
          );
          return json(
            out,
            out?.error === "missing_tenant_scope"
              ? 400
              : (out?.error === "forbidden" ? 403 : (out.ok ? 200 : 400)),
          );
        }

        if (
          pathParts.length === 3 &&
          pathParts[2] === "payment" &&
          request.method === "POST"
        ) {
          _requireAdmin(request, url, env);
          const body = await safeJson(request);
          const scopedRoute = requireExplicitBookingRouteScope({ request, url, body });
          if (!scopedRoute.ok) return scopedRoute.response;
          const tenantScope = scopedRoute.scope;
          const { rec } = await loadBookingRecord(env, bookingId);
          const ownershipBlock = await enforceDriverOwnershipForMutation({
            request,
            url,
            body,
            rec,
            tenantScope,
            env,
          });
          if (ownershipBlock) {
            return json({ ok: false, error: "booking_not_assigned_to_driver" }, 403);
          }
          const out = await updateBookingPaymentAuthoritative(
            bookingId,
            body,
            env,
            ctx,
            tenantScope,
          );
          return json(
            out,
            out?.error === "missing_tenant_scope"
              ? 400
              : (out?.error === "forbidden" ? 403 : (out.ok ? 200 : 400)),
          );
        }

        if (
          pathParts.length === 4 &&
          pathParts[2] === "receipt" &&
          pathParts[3] === "email" &&
          request.method === "POST"
        ) {
          const body = await safeJson(request);
          const out = await handleManualReceiptEmail(request, url, env, bookingId, body);
          if (out?.ok && out?.status === "already_sent") return json(out, 200);
          if (out?.ok) return json(out, 200);
          if (out?.status === "missing_email") return json(out, 400);
          if (out?.status === "skipped") return json(out, 400);
          return json(out, 500);
        }

        if (
          pathParts.length === 3 &&
          pathParts[2] === "assign" &&
          request.method === "POST"
        ) {
          _requireAdmin(request, url, env);
          const body = await safeJson(request);
          const tenantScope = extractBookingTenantScope({ request, url, body });
          if (!tenantScope.hasScope) {
            return json(missingTenantScopeError(), 400);
          }
          const fleetScope = normalizeFleetTenantScope(tenantScope);
          const vehicleId = String(body?.vehicle_id || body?.assigned_vehicle_id || "").trim();
          if (!vehicleId) {
            return json({ ok: false, error: "vehicle_id is required", booking_id: bookingId }, 400);
          }
          const { key, rec } = await loadBookingRecord(env, bookingId);
          if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) {
            return json({ ok: false, error: "forbidden" }, 403);
          }
          const scopedVehicles = await _loadVehicleInventory(env, { scope: fleetScope });
          const vehicleInScope = scopedVehicles.some((v) => String(v?.vehicle_id || "").trim() === vehicleId);
          if (!vehicleInScope) {
            return json({
              ok: false,
              error: "vehicle_not_in_scope",
              booking_id: bookingId,
              assigned_vehicle_id: vehicleId,
            }, 403);
          }
          rec.assigned_vehicle_id = vehicleId;
          if (rec.booking && typeof rec.booking === "object") {
            rec.booking.assigned_vehicle_id = vehicleId;
          }
          rec.updatedAt = new Date().toISOString();
          await env.BOOKING_KV.put(key, JSON.stringify(rec));
          return json({ ok: true, booking_id: bookingId, assigned_vehicle_id: vehicleId }, 200);
        }

        if (
          pathParts.length === 3 &&
          pathParts[2] === "delete" &&
          request.method === "POST"
        ) {
          _requireAdmin(request, url, env);
          const body = await safeJson(request);
          const tenantScope = extractBookingTenantScope({ request, url, body });
          if (!tenantScope.hasScope) {
            return json(missingTenantScopeError(), 400);
          }
          const { rec } = await loadBookingRecord(env, bookingId);
          const ownershipBlock = await enforceDriverOwnershipForMutation({
            request,
            url,
            body,
            rec,
            tenantScope,
            env,
          });
          if (ownershipBlock) {
            return json({ ok: false, error: "booking_not_assigned_to_driver" }, 403);
          }
          const out = await deleteBookingAuthoritative(bookingId, env, tenantScope);
          return json(
            out,
            out?.error === "missing_tenant_scope"
              ? 400
              : (out?.error === "forbidden" ? 403 : (out.ok ? 200 : 404)),
          );
        }
      }

      // Compatibility aliases for existing tracking-style app routes
      if (
        (url.pathname === "/track/bookings" || url.pathname === "/tracking/bookings") &&
        request.method === "GET"
      ) {
        _requireAdmin(request, url, env);
        const limit = Number(url.searchParams.get("limit") || "50");
        const includeHistory =
          (url.searchParams.get("include_history") || "").toLowerCase() === "1";
        const scopedRoute = requireExplicitBookingRouteScope({ request, url });
        if (!scopedRoute.ok) return scopedRoute.response;
        const tenantScope = scopedRoute.scope;
        const items = await listBookingsAuthoritative(env, {
          limit,
          includeHistory,
          tenantScope,
        });
        return json({ ok: true, items, count: items.length }, 200);
      }

      if (url.pathname === "/track/booking/status" && request.method === "POST") {
        const body = await safeJson(request);
        const bookingId = String(body?.booking_id || body?.bookingId || "").trim();
        const scopedRoute = requireExplicitBookingRouteScope({ request, url, body });
        if (!scopedRoute.ok) return scopedRoute.response;
        const tenantScope = scopedRoute.scope;
        const { rec } = await loadBookingRecord(env, bookingId);
        const actorRole = _scopeText(body?.actor_role ?? body?.actorRole, 32).toLowerCase();
        const adminAuthorized = hasValidAdminToken(request, url, env);
        if (!adminAuthorized) {
          if (actorRole === "customer") {
            const proof = _requestCustomerContactProof({ url, body });
            if (!customerProofMatchesBooking(rec, proof)) {
              return json({ ok: false, error: "customer ownership verification failed" }, 403);
            }
          } else if (actorRole === "driver") {
            const ownershipBlock = await enforceDriverOwnershipForMutation({
              request,
              url,
              body,
              rec,
              tenantScope,
              env,
            });
            if (ownershipBlock) {
              return json({ ok: false, error: "booking_not_assigned_to_driver" }, 403);
            }
          } else {
            return json({ ok: false, error: "Unauthorized" }, 401);
          }
        }
        const ownershipBlock = await enforceDriverOwnershipForMutation({
          request,
          url,
          body,
          rec,
          tenantScope,
          env,
        });
        if (ownershipBlock) {
          return json({ ok: false, error: "booking_not_assigned_to_driver" }, 403);
        }
        const out = await updateBookingStatusAuthoritative(
          bookingId,
          body?.status,
          env,
          tenantScope,
        );
        return json(
          out,
          out?.error === "missing_tenant_scope"
            ? 400
            : (out?.error === "forbidden" ? 403 : (out.ok ? 200 : 400)),
        );
      }

      if (url.pathname === "/track/booking/delete" && request.method === "POST") {
        _requireAdmin(request, url, env);
        const body = await safeJson(request);
        const bookingId = String(body?.booking_id || body?.bookingId || "").trim();
        const scopedRoute = requireExplicitBookingRouteScope({ request, url, body });
        if (!scopedRoute.ok) return scopedRoute.response;
        const tenantScope = scopedRoute.scope;
        const { rec } = await loadBookingRecord(env, bookingId);
        const ownershipBlock = await enforceDriverOwnershipForMutation({
          request,
          url,
          body,
          rec,
          tenantScope,
          env,
        });
        if (ownershipBlock) {
          return json({ ok: false, error: "booking_not_assigned_to_driver" }, 403);
        }
        const out = await deleteBookingAuthoritative(bookingId, env, tenantScope);
        return json(
          out,
          out?.error === "missing_tenant_scope"
            ? 400
            : (out?.error === "forbidden" ? 403 : (out.ok ? 200 : 404)),
        );
      }

      // =========================
      // LIVE TRIP TRACKING (Driver phone + Passenger tablet)
      // Minimal, non-breaking add-on:
      // - Stores last GPS ping inside the existing BOOKING_KV record
      // - Exposes endpoints for the app to fetch booking + pricing + last GPS
      // =========================

      // Get booking + quote/pricing for a given booking_id (used by the apps)
      if (url.pathname === "/tracking/booking" && request.method === "POST") {
        const body = await safeJson(request);
        const scopedRoute = requireExplicitBookingRouteScope({ request, url, body });
        if (!scopedRoute.ok) return scopedRoute.response;
        const tenantScope = scopedRoute.scope;
        const out = await trackingGetBooking(body, env, tenantScope);
        return json(
          out,
          out?.error === "missing_tenant_scope" || out?.error === "missing_tracking_booking_scope"
            ? 400
            : (out?.error === "forbidden" ? 403 : 200),
        );
      }

      // Start a tracking session (creates trip_id, persists on booking)
      if (url.pathname === "/tracking/start" && request.method === "POST") {
        const body = await safeJson(request);
        const tenantScope = extractBookingTenantScope({ request, url, body });
        const out = await trackingStart(body, env, tenantScope);
        return json(
          out,
          out?.error === "missing_tenant_scope" || out?.error === "missing_tracking_booking_scope"
            ? 400
            : (out?.error === "forbidden" ? 403 : 200),
        );
      }

      // GPS ping from driver phone
      if (url.pathname === "/tracking/ping" && request.method === "POST") {
        const body = await safeJson(request);
        const tenantScope = extractBookingTenantScope({ request, url, body });
        const out = await trackingPing(body, env, tenantScope);
        return json(
          out,
          out?.error === "missing_tenant_scope" || out?.error === "missing_tracking_booking_scope"
            ? 400
            : (out?.error === "forbidden" ? 403 : 200),
        );
      }

      // Read last GPS ping (tablet + diagnostics)
      if (url.pathname === "/tracking/last" && request.method === "GET") {
        const tenantScope = extractBookingTenantScope({ request, url });
        const out = await trackingLast(url, env, tenantScope);
        return json(
          out,
          out?.error === "missing_tenant_scope" || out?.error === "missing_tracking_booking_scope"
            ? 400
            : (out?.error === "forbidden" ? 403 : 200),
        );
      }

      return new Response("Not Found", { status: 404, headers: corsHeaders() });
    } catch (err) {
      if (err?.message === "Unauthorized") {
        return json({ ok: false, error: "Unauthorized" }, 401);
      }
      return json({ ok: false, error: err?.message || "Server error" }, 500);
    }
  },
};

/* ===================== CORS + JSON ===================== */

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders() },
  });
}

function html(content, status = 200) {
  return new Response(content, {
    status,
    headers: { "Content-Type": "text/html; charset=utf-8", ...corsHeaders() },
  });
}

async function safeJson(request) {
  const text = await request.text();
  if (!text) return {};
  try { return JSON.parse(text); } catch { return {}; }
}

function _scopeText(value, maxLen = 80) {
  return safeStr(value, maxLen) || "";
}

function extractBookingTenantScope({ request, url, body = null } = {}) {
  const search = url?.searchParams;
  const tenantFromQuery = _scopeText(
    search?.get("tenant_id") ?? search?.get("tenantId"),
  );
  const companyFromQuery = _scopeText(
    search?.get("company_id") ?? search?.get("companyId"),
  );
  const tenantFromBody = _scopeText(
    body?.tenant_id ?? body?.tenantId,
  );
  const companyFromBody = _scopeText(
    body?.company_id ?? body?.companyId,
  );

  // Optional headers for integrations that already carry tenant context.
  const tenantFromHeader = _scopeText(
    request?.headers?.get?.("x-tenant-id") ?? request?.headers?.get?.("x-tenant"),
  );
  const companyFromHeader = _scopeText(
    request?.headers?.get?.("x-company-id") ?? request?.headers?.get?.("x-company"),
  );

  const tenantId = tenantFromQuery || tenantFromBody || tenantFromHeader || "";
  const companyId = companyFromQuery || companyFromBody || companyFromHeader || "";
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId || companyId),
  };
}

function missingTenantScopeError() {
  return { ok: false, error: "missing_tenant_scope" };
}

function scopeConflictError() {
  return { ok: false, error: "tenant_scope_conflict" };
}

function _scopeDistinctNonEmpty(...values) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const text = _scopeText(value);
    if (!text || seen.has(text)) continue;
    seen.add(text);
    out.push(text);
  }
  return out;
}

function resolveExplicitBookingRequestScope({ request, url, body = null, allowLegacyFallback = false } = {}) {
  const search = url?.searchParams;
  const tenantBodySnake = _scopeText(body?.tenant_id);
  const tenantBodyCamel = _scopeText(body?.tenantId);
  const companyBodySnake = _scopeText(body?.company_id);
  const companyBodyCamel = _scopeText(body?.companyId);
  const tenantQuerySnake = _scopeText(search?.get("tenant_id"));
  const tenantQueryCamel = _scopeText(search?.get("tenantId"));
  const companyQuerySnake = _scopeText(search?.get("company_id"));
  const companyQueryCamel = _scopeText(search?.get("companyId"));
  const tenantHeaderPrimary = _scopeText(request?.headers?.get?.("x-tenant-id"));
  const tenantHeaderAlias = _scopeText(request?.headers?.get?.("x-tenant"));
  const companyHeaderPrimary = _scopeText(request?.headers?.get?.("x-company-id"));
  const companyHeaderAlias = _scopeText(request?.headers?.get?.("x-company"));

  if (tenantBodySnake && tenantBodyCamel && tenantBodySnake !== tenantBodyCamel) return scopeConflictError();
  if (companyBodySnake && companyBodyCamel && companyBodySnake !== companyBodyCamel) return scopeConflictError();
  if (tenantQuerySnake && tenantQueryCamel && tenantQuerySnake !== tenantQueryCamel) return scopeConflictError();
  if (companyQuerySnake && companyQueryCamel && companyQuerySnake !== companyQueryCamel) return scopeConflictError();
  if (tenantHeaderPrimary && tenantHeaderAlias && tenantHeaderPrimary !== tenantHeaderAlias) return scopeConflictError();
  if (companyHeaderPrimary && companyHeaderAlias && companyHeaderPrimary !== companyHeaderAlias) return scopeConflictError();

  const tenantValues = _scopeDistinctNonEmpty(
    tenantBodySnake,
    tenantBodyCamel,
    tenantQuerySnake,
    tenantQueryCamel,
    tenantHeaderPrimary,
    tenantHeaderAlias,
  );
  const companyValues = _scopeDistinctNonEmpty(
    companyBodySnake,
    companyBodyCamel,
    companyQuerySnake,
    companyQueryCamel,
    companyHeaderPrimary,
    companyHeaderAlias,
  );
  if (tenantValues.length > 1 || companyValues.length > 1) {
    return scopeConflictError();
  }

  const tenantId = tenantValues[0] || "";
  const companyId = companyValues[0] || "";

  if (!tenantId && !companyId) {
    if (allowLegacyFallback) {
      return {
        tenant_id: "fluxidi",
        company_id: "fluxidi",
        hasScope: true,
        legacy_fallback: true,
      };
    }
    return missingTenantScopeError();
  }
  if (!tenantId || !companyId) return missingTenantScopeError();

  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: true,
  };
}

function requireExplicitBookingRouteScope({ request, url, body = null } = {}) {
  const scope = resolveExplicitBookingRequestScope({
    request,
    url,
    body,
    allowLegacyFallback: false,
  });
  if (!scope?.hasScope) {
    return {
      ok: false,
      response: json(
        scope?.error === "tenant_scope_conflict"
          ? scopeConflictError()
          : missingTenantScopeError(),
        400,
      ),
    };
  }
  return { ok: true, scope };
}

function isLegacyTenantScopeRequest(requestedScope) {
  const legacyId = "fluxidi";
  const requestedTenant = _scopeText(requestedScope?.tenant_id);
  const requestedCompany = _scopeText(requestedScope?.company_id);
  return requestedTenant === legacyId || requestedCompany === legacyId;
}

function resolveBookingTenantScopeFromRecord(rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : null;
  const tenantId = _scopeText(
    rec?.tenant_id ??
      rec?.tenantId ??
      booking?.tenant_id ??
      booking?.tenantId ??
      rec?.company_id ??
      rec?.companyId ??
      booking?.company_id ??
      booking?.companyId,
  );
  const companyId = _scopeText(
    rec?.company_id ??
      rec?.companyId ??
      booking?.company_id ??
      booking?.companyId ??
      rec?.tenant_id ??
      rec?.tenantId ??
      booking?.tenant_id ??
      booking?.tenantId,
  );
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId || companyId),
  };
}

function bookingMatchesRequestedTenantScope(rec, requestedScope) {
  if (!requestedScope?.hasScope) return false;
  const recordScope = resolveBookingTenantScopeFromRecord(rec);
  // Legacy MVP bookings may not have tenant/company metadata yet.
  // Keep those readable/updatable only for explicit legacy scope requests.
  if (!recordScope.hasScope) return isLegacyTenantScopeRequest(requestedScope);

  if (
    requestedScope.tenant_id &&
    recordScope.tenant_id &&
    requestedScope.tenant_id !== recordScope.tenant_id
  ) {
    return false;
  }
  if (
    requestedScope.company_id &&
    recordScope.company_id &&
    requestedScope.company_id !== recordScope.company_id
  ) {
    return false;
  }
  return true;
}

function _normalizeCustomerEmail(value) {
  return _scopeText(value, 320).toLowerCase();
}

function _normalizeCustomerPhone(value) {
  const raw = _scopeText(value, 80);
  if (!raw) return "";
  const keepPlus = raw.startsWith("+");
  const digits = raw.replace(/[^0-9]/g, "");
  if (!digits) return "";
  return keepPlus ? `+${digits}` : digits;
}

function _bookingCustomerContacts(rec) {
  const emails = new Set();
  const phones = new Set();
  const addEmail = (value) => {
    const normalized = _normalizeCustomerEmail(value);
    if (normalized) emails.add(normalized);
  };
  const addPhone = (value) => {
    const normalized = _normalizeCustomerPhone(value);
    if (normalized) phones.add(normalized);
  };

  addEmail(rec?.customer_email);
  addEmail(rec?.customerEmail);
  addEmail(rec?.email);
  addEmail(rec?.customer?.email);
  addEmail(rec?.booking?.customer_email);
  addEmail(rec?.booking?.customerEmail);
  addEmail(rec?.booking?.email);
  addEmail(rec?.booking?.customer?.email);
  addEmail(rec?.contact?.email);

  addPhone(rec?.customer_phone);
  addPhone(rec?.customerPhone);
  addPhone(rec?.phone);
  addPhone(rec?.customer?.phone);
  addPhone(rec?.booking?.customer_phone);
  addPhone(rec?.booking?.customerPhone);
  addPhone(rec?.booking?.phone);
  addPhone(rec?.booking?.customer?.phone);
  addPhone(rec?.contact?.phone);

  return {
    emails: Array.from(emails),
    phones: Array.from(phones),
  };
}

function _requestCustomerContactProof({ url, body = null } = {}) {
  const search = url?.searchParams;
  const email = _normalizeCustomerEmail(
    body?.customer_email ??
      body?.customerEmail ??
      body?.email ??
      body?.contact_email ??
      body?.contactEmail ??
      search?.get("customer_email") ??
      search?.get("customerEmail") ??
      search?.get("email") ??
      search?.get("contact_email") ??
      search?.get("contactEmail"),
  );
  const phone = _normalizeCustomerPhone(
    body?.customer_phone ??
      body?.customerPhone ??
      body?.phone ??
      body?.contact_phone ??
      body?.contactPhone ??
      search?.get("customer_phone") ??
      search?.get("customerPhone") ??
      search?.get("phone") ??
      search?.get("contact_phone") ??
      search?.get("contactPhone"),
  );
  return {
    email,
    phone,
    hasProof: !!(email || phone),
  };
}

function customerProofMatchesBooking(rec, proof) {
  if (!proof?.hasProof) return false;
  const bookingContacts = _bookingCustomerContacts(rec);
  if (proof.email && bookingContacts.emails.includes(proof.email)) {
    return true;
  }
  if (proof.phone && bookingContacts.phones.includes(proof.phone)) {
    return true;
  }
  return false;
}

function resolveMutationActorFromRequest(request, url, body = null) {
  const search = url?.searchParams;
  const actorRole = _scopeText(
    body?.actor_role ??
      body?.actorRole ??
      search?.get("actor_role") ??
      search?.get("actorRole") ??
      request?.headers?.get?.("x-fluxidi-actor-role"),
    32,
  ).toLowerCase();
  const actorDriverId = _scopeText(
    body?.actor_driver_id ??
      body?.actorDriverId ??
      body?.driver_id ??
      body?.driverId ??
      search?.get("actor_driver_id") ??
      search?.get("actorDriverId") ??
      search?.get("driver_id") ??
      search?.get("driverId") ??
      request?.headers?.get?.("x-driver-id") ??
      request?.headers?.get?.("x-fluxidi-driver-id"),
    96,
  );
  const actorVehicleId = _scopeText(
    body?.actor_vehicle_id ??
      body?.actorVehicleId ??
      body?.vehicle_id ??
      body?.vehicleId ??
      search?.get("actor_vehicle_id") ??
      search?.get("actorVehicleId") ??
      search?.get("vehicle_id") ??
      search?.get("vehicleId") ??
      request?.headers?.get?.("x-vehicle-id") ??
      request?.headers?.get?.("x-fluxidi-vehicle-id"),
    128,
  );
  return {
    actor_role: actorRole,
    actor_driver_id: actorDriverId,
    actor_vehicle_id: actorVehicleId,
  };
}

function _bookingMutationReadPath(root, paths = []) {
  for (const path of paths) {
    let cursor = root;
    let ok = true;
    for (const key of path) {
      if (!cursor || typeof cursor !== "object" || !(key in cursor)) {
        ok = false;
        break;
      }
      cursor = cursor[key];
    }
    if (!ok) continue;
    const text = _scopeText(cursor, 128);
    if (text) return text;
  }
  return "";
}

function bookingAssignedVehicleId(rec) {
  return _bookingMutationReadPath(rec, [
    ["assigned_vehicle_id"],
    ["assignedVehicleId"],
    ["vehicle_id"],
    ["vehicleId"],
    ["booking", "assigned_vehicle_id"],
    ["booking", "assignedVehicleId"],
    ["booking", "vehicle_id"],
    ["booking", "vehicleId"],
    ["record", "booking", "assigned_vehicle_id"],
    ["record", "booking", "assignedVehicleId"],
    ["record", "booking", "vehicle_id"],
    ["record", "booking", "vehicleId"],
  ]);
}

function bookingAssignedDriverId(rec) {
  return _bookingMutationReadPath(rec, [
    ["assigned_driver", "driver_id"],
    ["assigned_driver", "driverId"],
    ["assigned_driver", "id"],
    ["assignedDriver", "driver_id"],
    ["assignedDriver", "driverId"],
    ["assignedDriver", "id"],
    ["driver_id"],
    ["driverId"],
    ["booking", "assigned_driver", "driver_id"],
    ["booking", "assigned_driver", "driverId"],
    ["booking", "assigned_driver", "id"],
    ["booking", "assignedDriver", "driver_id"],
    ["booking", "assignedDriver", "driverId"],
    ["booking", "assignedDriver", "id"],
    ["booking", "driver_id"],
    ["booking", "driverId"],
    ["record", "booking", "assigned_driver", "driver_id"],
    ["record", "booking", "assigned_driver", "driverId"],
    ["record", "booking", "assigned_driver", "id"],
    ["record", "booking", "assignedDriver", "driver_id"],
    ["record", "booking", "assignedDriver", "driverId"],
    ["record", "booking", "assignedDriver", "id"],
    ["record", "booking", "driver_id"],
    ["record", "booking", "driverId"],
  ]);
}

async function fleetDriverIdForVehicle(env, vehicleId, tenantScope) {
  const wantedVehicleId = _scopeText(vehicleId, 128);
  if (!wantedVehicleId) return "";
  const scopedVehicles = await _loadVehicleInventory(env, { scope: tenantScope });
  const hit = scopedVehicles.find((v) => _scopeText(v?.vehicle_id, 128) === wantedVehicleId);
  if (!hit || typeof hit !== "object") return "";
  return _bookingMutationReadPath(hit, [
    ["assigned_driver", "driver_id"],
    ["assigned_driver", "driverId"],
    ["assigned_driver", "id"],
    ["assignedDriver", "driver_id"],
    ["assignedDriver", "driverId"],
    ["assignedDriver", "id"],
    ["driver_id"],
    ["driverId"],
  ]);
}

async function driverOwnsBookingForMutation({
  rec,
  actorDriverId,
  actorVehicleId,
  tenantScope,
  env,
}) {
  const driverId = _scopeText(actorDriverId, 96);
  const vehicleId = _scopeText(actorVehicleId, 128);
  const assignedDriverId = bookingAssignedDriverId(rec);
  const assignedVehicleId = bookingAssignedVehicleId(rec);

  if (driverId && assignedDriverId && driverId === assignedDriverId) return true;
  if (vehicleId && assignedVehicleId && vehicleId === assignedVehicleId) return true;
  if (driverId && assignedVehicleId) {
    const linkedDriverId = await fleetDriverIdForVehicle(
      env,
      assignedVehicleId,
      tenantScope,
    );
    if (linkedDriverId && linkedDriverId === driverId) return true;
  }
  return false;
}

async function enforceDriverOwnershipForMutation({
  request,
  url,
  body,
  rec,
  tenantScope,
  env,
}) {
  const actor = resolveMutationActorFromRequest(request, url, body);
  if (actor.actor_role !== "driver") return null;
  const actorDriverId = _scopeText(actor.actor_driver_id, 96);
  const actorVehicleId = _scopeText(actor.actor_vehicle_id, 128);
  const assignedVehicleId = bookingAssignedVehicleId(rec);
  const bookingId =
    _scopeText(rec?.booking_id ?? rec?.bookingId ?? rec?.booking?.booking_id ?? rec?.booking?.bookingId, 128) ||
    "unknown";

  let allowed = false;
  if (actorDriverId || actorVehicleId) {
    allowed = await driverOwnsBookingForMutation({
      rec,
      actorDriverId,
      actorVehicleId,
      tenantScope,
      env,
    });
  }
  console.log(
    `[DRIVER_OWNERSHIP][CHECK] booking=${bookingId} actor_driver=${actorDriverId || "-"} actor_vehicle=${actorVehicleId || "-"} assigned_vehicle=${assignedVehicleId || "-"} allowed=${allowed}`,
  );
  if (allowed) return null;
  console.log(
    `[DRIVER_OWNERSHIP][BLOCK] booking=${bookingId} actor_driver=${actorDriverId || "-"} actor_vehicle=${actorVehicleId || "-"} assigned_vehicle=${assignedVehicleId || "-"}`,
  );
  return { ok: false, error: "booking_not_assigned_to_driver" };
}

/* ===================== OAUTH ROUTES (unchanged) ===================== */

function getBaseUrl(request) {
  const u = new URL(request.url);
  return `${u.protocol}//${u.host}`;
}

function _calendarOauthError(code) {
  const err = new Error(String(code || "calendar_oauth_error"));
  err.code = String(code || "calendar_oauth_error");
  return err;
}

async function buildSignedCalendarOAuthState(payloadObj, secret) {
  const payloadBase64 = jsonBase64urlEncode(payloadObj);
  const signatureBase64 = await signCalendarOAuthState(payloadBase64, secret);
  return `${payloadBase64}.${signatureBase64}`;
}

async function parseAndVerifyCalendarOAuthState(state, secret) {
  const raw = String(state || "").trim();
  if (!raw) throw _calendarOauthError("missing_state");
  const parts = raw.split(".");
  if (parts.length !== 2 || !parts[0] || !parts[1]) {
    throw _calendarOauthError("invalid_state_format");
  }
  const [payloadBase64, signatureBase64] = parts;
  const ok = await verifyCalendarOAuthState(payloadBase64, signatureBase64, secret);
  if (!ok) throw _calendarOauthError("invalid_state_signature");
  const payload = jsonBase64urlDecode(payloadBase64);
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw _calendarOauthError("invalid_state_payload");
  }
  return { payloadBase64, signatureBase64, payload };
}

async function saveScopedGoogleCalendarAuthRecord(env, scope, nextRecord) {
  if (!env?.BOOKING_KV) throw _calendarOauthError("missing_booking_kv");
  const scopedKey = buildScopedGoogleCalendarAuthKey(scope);
  if (!scopedKey) throw _calendarOauthError("missing_tenant_scope");
  await env.BOOKING_KV.put(scopedKey, JSON.stringify(nextRecord));
  return { scopedKey };
}

async function saveScopedGoogleCalendarAuthFailureStatus(
  env,
  scope,
  {
    status = "failed",
    errorCode = "oauth_callback_failed",
  } = {},
) {
  if (!env?.BOOKING_KV) return;
  const scopedKey = buildScopedGoogleCalendarAuthKey(scope);
  if (!scopedKey) return;
  const nowIso = new Date().toISOString();
  let existing = null;
  try {
    const raw = await env.BOOKING_KV.get(scopedKey, { type: "json" });
    existing = raw && typeof raw === "object"
      ? (raw.google_calendar_auth && typeof raw.google_calendar_auth === "object"
          ? raw.google_calendar_auth
          : raw)
      : null;
  } catch (_) {
    existing = null;
  }
  const next = {
    version: 1,
    connected: false,
    status: String(status || "failed"),
    calendarId: safeStr(existing?.calendarId ?? existing?.calendar_id ?? env?.GOOGLE_CALENDAR_ID) || "primary",
    accountEmail: safeStr(existing?.accountEmail ?? existing?.account_email, 320) || null,
    refreshTokenEncrypted:
      existing?.refreshTokenEncrypted && typeof existing.refreshTokenEncrypted === "object"
        ? existing.refreshTokenEncrypted
        : null,
    lastConnectedAt: safeStr(existing?.lastConnectedAt ?? existing?.last_connected_at) || null,
    lastSyncAt: safeStr(existing?.lastSyncAt ?? existing?.last_sync_at) || null,
    lastErrorCode: String(errorCode || "oauth_callback_failed"),
    lastErrorAt: nowIso,
    updatedAt: nowIso,
  };
  await env.BOOKING_KV.put(scopedKey, JSON.stringify(next));
}

function oauthStart(request, env) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) {
    return html(`
      <h2>Missing Google OAuth config</h2>
      <p>Set Cloudflare secrets:</p>
      <ul>
        <li>GOOGLE_CLIENT_ID</li>
        <li>GOOGLE_CLIENT_SECRET</li>
      </ul>
    `, 500);
  }

  const base = getBaseUrl(request);
  const redirectUri = `${base}/oauth/callback`;
  const scope = "https://www.googleapis.com/auth/calendar";

  const authUrl = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authUrl.searchParams.set("client_id", env.GOOGLE_CLIENT_ID);
  authUrl.searchParams.set("redirect_uri", redirectUri);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", scope);
  authUrl.searchParams.set("access_type", "offline");
  authUrl.searchParams.set("prompt", "consent");
  authUrl.searchParams.set("include_granted_scopes", "true");

  return Response.redirect(authUrl.toString(), 302);
}

async function oauthCallback(request, env) {
  if (!env.GOOGLE_CLIENT_ID || !env.GOOGLE_CLIENT_SECRET) {
    return html("<h2>Missing GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET</h2>", 500);
  }

  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const err = url.searchParams.get("error");
  const state = url.searchParams.get("state");

  if (err) return html(`<h2>OAuth error</h2><p>${escapeHtml(err)}</p>`, 400);
  if (!code) return html("<h2>No authorization code</h2><p>Missing ?code=</p>", 400);

  const base = getBaseUrl(request);
  const redirectUri = `${base}/oauth/callback`;

  // Legacy manual flow: keep existing behavior unchanged when no state is provided.
  if (!state) {
    const tokens = await exchangeCodeForTokens({
      code,
      clientId: env.GOOGLE_CLIENT_ID,
      clientSecret: env.GOOGLE_CLIENT_SECRET,
      redirectUri
    });

    const refresh = tokens.refresh_token || "";

    return html(`
      <div style="font-family: ui-sans-serif, system-ui; max-width: 900px; margin: 40px auto; line-height: 1.4;">
        <h1>✅ OAuth gelukt</h1>

        <h3>1) Refresh token</h3>
        <p>Kopieer dit naar Cloudflare → Worker → Settings → Variables & Secrets:</p>
        <pre style="padding:12px; background:#0f0f10; color:#fff; border-radius:12px; overflow:auto;">${escapeHtml(refresh || "(geen refresh_token ontvangen — klik /oauth/start opnieuw en zorg dat prompt=consent gebruikt wordt)")}</pre>

        <h3>2) Cloudflare secrets die je moet zetten</h3>
        <ul>
          <li><b>GOOGLE_REFRESH_TOKEN</b> = (bovenstaande waarde)</li>
          <li><b>GOOGLE_CALENDAR_ID</b> = <code>primary</code> (simpel) of een specifieke calendar id</li>
        </ul>

        <h3>3) Daarna</h3>
        <p>Deploy opnieuw en test:</p>
        <ul>
          <li><code>POST /availability</code></li>
          <li><code>POST /book</code></li>
        </ul>
      </div>
    `);
  }

  let scopedState = null;
  let callbackErrorCode = "oauth_callback_failed";
  try {
    if (!safeStr(env?.CALENDAR_OAUTH_STATE_SECRET)) {
      throw _calendarOauthError("missing_calendar_oauth_state_secret");
    }
    if (!safeStr(env?.CALENDAR_AUTH_ENCRYPTION_KEY)) {
      throw _calendarOauthError("missing_calendar_auth_encryption_key");
    }
    if (!env?.BOOKING_KV) {
      throw _calendarOauthError("missing_booking_kv");
    }

    const parsed = await parseAndVerifyCalendarOAuthState(
      state,
      env.CALENDAR_OAUTH_STATE_SECRET,
    );
    const payload = parsed.payload;
    const nowSec = Math.floor(Date.now() / 1000);
    const purpose = safeStr(payload?.purpose, 64);
    const tenantId = sanitizeTenantString(payload?.tenant_id ?? payload?.tenantId, 80);
    const companyId = sanitizeTenantString(payload?.company_id ?? payload?.companyId, 80);
    const nonce = String(payload?.nonce || "").trim().replace(/[^a-zA-Z0-9_-]+/g, "");
    const iat = Number(payload?.iat);
    const exp = Number(payload?.exp);
    if (purpose !== CALENDAR_OAUTH_STATE_PURPOSE) {
      throw _calendarOauthError("invalid_state_purpose");
    }
    if (!tenantId || !companyId) {
      throw _calendarOauthError("missing_state_scope");
    }
    if (!nonce) {
      throw _calendarOauthError("missing_state_nonce");
    }
    if (!Number.isFinite(iat) || !Number.isFinite(exp) || iat <= 0 || exp <= 0 || exp <= iat) {
      throw _calendarOauthError("invalid_state_timing");
    }
    if (nowSec < iat - 30 || nowSec > exp) {
      throw _calendarOauthError("state_expired");
    }
    scopedState = {
      tenant_id: tenantId,
      company_id: companyId,
      nonce,
      kid: safeStr(payload?.kid, 32) || "v1",
    };
    const nonceResult = await consumeCalendarOAuthNonce(
      env,
      scopedState,
      nonce,
    );
    if (!nonceResult?.ok) {
      throw _calendarOauthError(nonceResult?.code || "nonce_invalid");
    }

    const tokens = await exchangeCodeForTokens({
      code,
      clientId: env.GOOGLE_CLIENT_ID,
      clientSecret: env.GOOGLE_CLIENT_SECRET,
      redirectUri,
    });
    const refreshToken = safeStr(tokens?.refresh_token);
    if (!refreshToken) {
      callbackErrorCode = "missing_refresh_token";
      await saveScopedGoogleCalendarAuthFailureStatus(env, scopedState, {
        status: "auth_required",
        errorCode: callbackErrorCode,
      });
      throw _calendarOauthError(callbackErrorCode);
    }
    const encryptedRefreshToken = await encryptCalendarRefreshToken(
      refreshToken,
      env,
    );
    const nowIso = new Date().toISOString();
    const scopedRecord = {
      version: 1,
      connected: true,
      status: "connected",
      calendarId: safeStr(env?.GOOGLE_CALENDAR_ID) || "primary",
      accountEmail: null,
      refreshTokenEncrypted: encryptedRefreshToken,
      lastConnectedAt: nowIso,
      lastSyncAt: null,
      lastErrorCode: null,
      lastErrorAt: null,
      updatedAt: nowIso,
    };
    await saveScopedGoogleCalendarAuthRecord(env, scopedState, scopedRecord);
    console.log(
      `[CALENDAR_OAUTH][CALLBACK_OK] tenant=${scopedState.tenant_id} company=${scopedState.company_id}`,
    );
    return html(`
      <div style="font-family: ui-sans-serif, system-ui; max-width: 900px; margin: 40px auto; line-height: 1.4;">
        <h1>✅ Google Calendar is gekoppeld.</h1>
        <p>Je kunt dit venster sluiten en teruggaan naar Fluxidi.</p>
      </div>
    `);
  } catch (callbackErr) {
    callbackErrorCode =
      safeStr(callbackErr?.code || callbackErr?.message, 64) ||
      callbackErrorCode;
    if (scopedState?.tenant_id && scopedState?.company_id) {
      try {
        await saveScopedGoogleCalendarAuthFailureStatus(env, scopedState, {
          status: callbackErrorCode === "missing_refresh_token" ? "auth_required" : "failed",
          errorCode: callbackErrorCode,
        });
      } catch (_) {
        // Best-effort status write only.
      }
      console.log(
        `[CALENDAR_OAUTH][CALLBACK_FAIL] tenant=${scopedState.tenant_id} company=${scopedState.company_id} code=${callbackErrorCode}`,
      );
    } else {
      console.log(
        `[CALENDAR_OAUTH][CALLBACK_FAIL] code=${callbackErrorCode}`,
      );
    }
    return html(`
      <div style="font-family: ui-sans-serif, system-ui; max-width: 900px; margin: 40px auto; line-height: 1.4;">
        <h1>⚠️ Google Calendar koppeling mislukt</h1>
        <p>Probeer opnieuw vanuit de beheeromgeving.</p>
      </div>
    `, 400);
  }
}

async function exchangeCodeForTokens({ code, clientId, clientSecret, redirectUri }) {
  const tokenUrl = "https://oauth2.googleapis.com/token";
  const form = new URLSearchParams();
  form.set("code", code);
  form.set("client_id", clientId);
  form.set("client_secret", clientSecret);
  form.set("redirect_uri", redirectUri);
  form.set("grant_type", "authorization_code");

  const r = await fetch(tokenUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: form.toString()
  });

  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j?.error_description || j?.error || "Token exchange failed");
  return j;
}

function escapeHtml(str) {
  return String(str || "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

// --- Safety helpers (added) ---
function safeStr(v) {
  if (v === null || v === undefined) return "";
  return String(v).trim();
}


/* ===================== PAYMENTS (MOLLIE) ===================== */

function money2(value) {
  // Robust euro number parsing: accepts numbers, "143.24", "143,24", "€ 143,24"
  if (value == null) return "0.00";
  let s = String(value).trim();
  // keep digits, dot, comma, minus
  s = s.replace(/[^0-9,\.\-]/g, "");
  // If we have both comma and dot, assume dot is thousands sep and comma is decimal (e.g. 1.234,56)
  if (s.includes(",") && s.includes(".")) {
    // remove dots (thousands), then replace comma with dot
    s = s.replace(/\./g, "").replace(/,/g, ".");
  } else {
    // otherwise just replace comma with dot
    s = s.replace(/,/g, ".");
  }
  const n = Number(s);
  if (!Number.isFinite(n)) return "0.00";
  return (Math.round(n * 100) / 100).toFixed(2);
}

function envFlag(value) {
  return ["1", "true", "yes", "on"].includes(String(value ?? "").trim().toLowerCase());
}

function mollieKeyKind(apiKey) {
  const key = String(apiKey || "").trim();
  if (key.startsWith("test_")) return "test";
  if (key.startsWith("live_")) return "live";
  return "unknown";
}

function mollieRuntimeEnv(env) {
  return String(
    env?.MOLLIE_ENV ||
    env?.APP_ENV ||
    env?.ENVIRONMENT ||
    env?.NODE_ENV ||
    env?.CF_ENV ||
    env?.ENV ||
    ""
  ).trim().toLowerCase();
}

function isDevelopmentLikeMollieEnv(runtimeEnv) {
  return ["dev", "development", "test", "testing", "local", "staging", "preview"].includes(runtimeEnv);
}

function getMollieConfig(env) {
  const apiKey = String(env?.MOLLIE_API_KEY || "").trim();
  if (!apiKey) {
    return { ok: false, error: "Missing MOLLIE_API_KEY secret in Cloudflare." };
  }

  const keyKind = mollieKeyKind(apiKey);
  const runtimeEnv = mollieRuntimeEnv(env);
  const rawMode = String(env?.MOLLIE_MODE || "").trim().toLowerCase();
  const mode = rawMode === "live" || rawMode === "test" ? rawMode : (keyKind === "live" ? "live" : "test");
  const devLike = isDevelopmentLikeMollieEnv(runtimeEnv);
  const liveAllowed = envFlag(env?.MOLLIE_ALLOW_LIVE_PAYMENTS) && !devLike;

  console.log(`[MOLLIE_MODE] mode=${mode} key=${keyKind} env=${runtimeEnv || "unset"} live_allowed=${liveAllowed}`);

  if (mode === "test" && keyKind !== "test") {
    return { ok: false, error: "Mollie test mode requires a test_ API key." };
  }
  if (mode === "live" && keyKind !== "live") {
    return { ok: false, error: "Mollie live mode requires a live_ API key." };
  }
  if (keyKind === "live" && devLike) {
    return { ok: false, error: "Live Mollie payments are blocked in development/test environments." };
  }
  if (keyKind === "live" && !liveAllowed) {
    return { ok: false, error: "Live Mollie payments are disabled. Use a test_ API key during test phase." };
  }

  return { ok: true, apiKey, mode, keyKind };
}

function normalizePaymentStatus(value) {
  const s = String(value || "").trim().toLowerCase();
  if (s === "paid" || s === "settled") return "paid";
  if (s === "failed" || s === "canceled" || s === "cancelled" || s === "expired") return "failed";
  if (s === "open" || s === "pending" || s === "authorized") return "pending";
  return "unpaid";
}

function normalizedPaymentFields({ status, provider = "mollie", paymentId = null, paidAt = null } = {}) {
  const paymentStatus = normalizePaymentStatus(status);
  const resolvedPaidAt = paymentStatus === "paid"
    ? (safeStr(paidAt) || new Date().toISOString())
    : null;
  return {
    payment_status: paymentStatus,
    paymentStatus,
    payment_provider: provider,
    paymentProvider: provider,
    payment_id: safeStr(paymentId) || null,
    paymentId: safeStr(paymentId) || null,
    ...(resolvedPaidAt ? { paid_at: resolvedPaidAt, paidAt: resolvedPaidAt } : {}),
  };
}

function paymentFieldsFromPayload(payload) {
  return normalizedPaymentFields({
    status: payload?.payment_status || payload?.paymentStatus,
    provider: payload?.payment_provider || payload?.paymentProvider || "mollie",
    paymentId: payload?.payment_id || payload?.paymentId || payload?.mollie_payment_id || payload?.molliePaymentId,
    paidAt: payload?.paid_at || payload?.paidAt,
  });
}

const COMPLIANCE_APPEND_PATH = "/compliance/events/append";

function buildComplianceAppendUrl(baseUrlRaw) {
  const normalized = safeStr(baseUrlRaw);
  if (!normalized) return null;
  try {
    const parsed = new URL(normalized);
    parsed.search = "";
    parsed.hash = "";
    const normalizedPath = parsed.pathname.replace(/\/+$/, "");
    if (normalizedPath === COMPLIANCE_APPEND_PATH) return parsed;
    if (normalizedPath === "" || normalizedPath === "/") {
      parsed.pathname = COMPLIANCE_APPEND_PATH;
      return parsed;
    }
    return null;
  } catch (_) {
    return null;
  }
}

function normalizeCompliancePaymentStatus(value) {
  const raw = safeStr(value).toLowerCase();
  if (!raw) return "unknown";
  if (raw === "paid" || raw === "confirmed" || raw === "completed" || raw === "success" || raw === "settled") {
    return "paid";
  }
  if (raw === "pending" || raw === "authorized" || raw === "open" || raw === "processing") {
    return "pending";
  }
  if (raw === "failed" || raw === "cancelled" || raw === "canceled" || raw === "declined") {
    return "failed";
  }
  if (raw === "unpaid" || raw === "not_paid") {
    return "unpaid";
  }
  return "unknown";
}

function normalizeComplianceText(value, fallback = "unknown") {
  const text = safeStr(value).toLowerCase();
  return text || fallback;
}

function buildBookingPaymentUpdateComplianceEvent(recordOrBooking, bookingId, payment) {
  const rec = recordOrBooking && typeof recordOrBooking === "object" ? recordOrBooking : {};
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const isUnknownLikePaymentValue = (value) => {
    const raw = String(value ?? "").trim().toLowerCase();
    return (
      raw === "" ||
      raw === "unknown" ||
      raw === "onbekend" ||
      raw === "—" ||
      raw === "-" ||
      raw === "null" ||
      raw === "undefined"
    );
  };
  const pickMeaningfulPaymentValue = (...candidates) => {
    for (const candidate of candidates) {
      const text = safeStr(candidate);
      if (!text) continue;
      if (isUnknownLikePaymentValue(text)) continue;
      return text;
    }
    return null;
  };
  const explicitTenantId = safeStr(
    payment?.tenant_id ||
      payment?.tenantId ||
      payment?.company_id ||
      payment?.companyId ||
      rec?.tenant_id ||
      rec?.tenantId ||
      booking?.tenant_id ||
      booking?.tenantId ||
      rec?.company_id ||
      rec?.companyId ||
      booking?.company_id ||
      booking?.companyId,
  );
  // TODO: replace Fluxidi fallback with strict tenant/company authority before production.
  const tenantId = explicitTenantId || "fluxidi";
  const explicitCompanyId = safeStr(
    payment?.company_id ||
      payment?.companyId ||
      rec?.company_id ||
      rec?.companyId ||
      booking?.company_id ||
      booking?.companyId,
  );
  const companyId = explicitCompanyId || tenantId;
  if (!tenantId || !companyId) return null;

  const paidAt = safeStr(
    rec?.paid_at ||
      rec?.paidAt ||
      booking?.paid_at ||
      booking?.paidAt ||
      payment?.paid_at ||
      payment?.paidAt,
  );
  const eventAt = paidAt || new Date().toISOString();
  const currency = (
    safeStr(
      payment?.currency ||
        rec?.currency ||
        booking?.currency ||
        booking?.booking_currency ||
        "EUR",
    ) || "EUR"
  ).toUpperCase();
  const amountRaw =
    payment?.amount ??
    payment?.price ??
    payment?.total ??
    rec?.payment_amount ??
    rec?.paymentAmount ??
    booking?.payment_amount ??
    booking?.paymentAmount;
  const amountNum = Number(amountRaw);
  const amount = Number.isFinite(amountNum) ? amountNum : null;
  const totalRaw =
    booking?.price_incl_vat ??
    booking?.priceInclVat ??
    rec?.price_incl_vat ??
    rec?.priceInclVat ??
    amountRaw;
  const totalNum = Number(totalRaw);
  const totalAmount = Number.isFinite(totalNum) ? totalNum : null;
  const paymentMethod = normalizeComplianceText(
    pickMeaningfulPaymentValue(
      rec?.payment_method,
      rec?.paymentMethod,
      booking?.payment_method,
      booking?.paymentMethod,
      payment?.payment_method,
      payment?.paymentMethod,
    ),
  );
  const paymentSource = normalizeComplianceText(
    pickMeaningfulPaymentValue(
      rec?.payment_source,
      rec?.paymentSource,
      booking?.payment_source,
      booking?.paymentSource,
      payment?.payment_source,
      payment?.paymentSource,
    ),
  );
  const rawProvider = pickMeaningfulPaymentValue(
    rec?.payment_provider,
    rec?.paymentProvider,
    booking?.payment_provider,
    booking?.paymentProvider,
    payment?.payment_provider,
    payment?.paymentProvider,
  );
  const normalizedProvider = normalizeComplianceText(rawProvider);
  const paymentId = safeStr(
    rec?.payment_id ||
      rec?.paymentId ||
      booking?.payment_id ||
      booking?.paymentId ||
      payment?.payment_id ||
      payment?.paymentId,
  ) || undefined;
  const molliePaymentId = safeStr(
    payment?.mollie_payment_id ||
      payment?.molliePaymentId ||
      rec?.mollie_payment_id ||
      rec?.molliePaymentId ||
      rec?.mollie?.payment_id ||
      rec?.mollie?.id ||
      booking?.mollie_payment_id ||
      booking?.molliePaymentId ||
      booking?.mollie?.payment_id ||
      booking?.mollie?.id,
  );
  const looksLikeMolliePaymentId = (value) => /^tr_[a-z0-9]+$/i.test(String(value || "").trim());
  const hasReliableExternalPaymentId = looksLikeMolliePaymentId(molliePaymentId) || looksLikeMolliePaymentId(paymentId);
  const isManualLikeSource = (value) =>
    [
      "in_car",
      "in-car",
      "in_vehicle",
      "in-vehicle",
      "manual",
      "driver",
      "driver_app",
      "chauffeur",
      "cash",
    ].includes(String(value || "").trim().toLowerCase());
  const isManualLikeMethod = (value) =>
    [
      "cash",
      "bancontact",
      "card",
      "pin",
      "qr",
      "in_car",
      "manual",
      "driver",
      "chauffeur",
    ].includes(String(value || "").trim().toLowerCase());
  const shouldSanitizeManualProvider =
    isManualLikeSource(paymentSource) &&
    isManualLikeMethod(paymentMethod) &&
    !hasReliableExternalPaymentId &&
    normalizedProvider === "mollie";
  const compliancePaymentProvider = shouldSanitizeManualProvider ? "manual" : normalizedProvider;
  const publicBookingReference = safeStr(
    payment?.public_booking_reference ||
      payment?.publicBookingReference ||
      payment?.booking_reference ||
      payment?.bookingReference ||
      payment?.public_reference ||
      payment?.publicReference ||
      rec?.public_booking_reference ||
      rec?.publicBookingReference ||
      rec?.booking_reference ||
      rec?.bookingReference ||
      rec?.public_reference ||
      rec?.publicReference ||
      booking?.public_booking_reference ||
      booking?.publicBookingReference ||
      booking?.booking_reference ||
      booking?.bookingReference ||
      booking?.public_reference ||
      booking?.publicReference,
  );
  const receiptReference = safeStr(
    rec?.receipt_reference ||
      rec?.receiptReference ||
      booking?.receipt_reference ||
      booking?.receiptReference,
  ) || publicBookingReference || undefined;

  return {
    event_type: "payment_update",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr(bookingId) || undefined,
    trip_id: safeStr(rec?.trip_id || rec?.tripId || booking?.trip_id || booking?.tripId) || undefined,
    receipt_reference: receiptReference,
    receiptReference: receiptReference,
    public_booking_reference: publicBookingReference || undefined,
    publicBookingReference: publicBookingReference || undefined,
    booking_reference: publicBookingReference || undefined,
    bookingReference: publicBookingReference || undefined,
    public_reference: publicBookingReference || undefined,
    publicReference: publicBookingReference || undefined,
    ride_type: "planned",
    lifecycle_status: "payment_updated",
    timestamps: {
      event_at_utc: eventAt,
      paid_at_utc: paidAt || undefined,
    },
    fare: {
      currency,
      total_amount: totalAmount,
    },
    payment: {
      status: normalizeCompliancePaymentStatus(
        rec?.payment_status ||
          rec?.paymentStatus ||
          booking?.payment_status ||
          booking?.paymentStatus ||
          payment?.payment_status ||
          payment?.paymentStatus,
      ),
      method: paymentMethod,
      source: paymentSource,
      provider: compliancePaymentProvider,
      payment_id: paymentId,
      amount: amount ?? undefined,
      currency,
    },
    provenance: {
      producer: "booking_worker",
      source_endpoint: "/bookings/:id/payment",
      backend_confirmed: true,
      validation_state: "payment_update",
    },
  };
}

async function emitComplianceEventBestEffort(env, event, options = {}) {
  try {
    const baseUrlRaw = safeStr(env?.COMPLIANCE_API_URL);
    const adminToken = safeStr(env?.COMPLIANCE_ADMIN_TOKEN || env?.ADMIN_TOKEN);
    const logLabel = safeStr(options?.logLabel) || "payment_update";
    if (!baseUrlRaw || !adminToken) {
      console.log(`[COMPLIANCE_EMIT][${logLabel}] skipped reason=missing_config`);
      return { ok: false, skipped: "missing_config" };
    }
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      console.log(`[COMPLIANCE_EMIT][${logLabel}] skipped reason=invalid_event`);
      return { ok: false, skipped: "invalid_event" };
    }
    const appendUrl = buildComplianceAppendUrl(baseUrlRaw);
    if (!appendUrl) {
      console.log(`[COMPLIANCE_EMIT][${logLabel}] skipped reason=invalid_url_config`);
      return { ok: false, skipped: "invalid_url_config" };
    }

    const requestedTimeout = Number(options?.timeoutMs);
    const timeoutMs = Number.isFinite(requestedTimeout)
      ? Math.max(1, Math.min(1500, Math.round(requestedTimeout)))
      : 1500;
    const controller = new AbortController();
    const timer = setTimeout(() => {
      controller.abort();
    }, timeoutMs);

    try {
      const req = new Request(appendUrl.toString(), {
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: `Bearer ${adminToken}`,
        },
        body: JSON.stringify(event),
        signal: controller.signal,
      });
      const hasServiceBinding = !!(env?.COMPLIANCE_WORKER && typeof env.COMPLIANCE_WORKER.fetch === "function");
      const transport = hasServiceBinding ? "service_binding" : "public_fetch";
      const resp = hasServiceBinding
        ? await env.COMPLIANCE_WORKER.fetch(req)
        : await fetch(req);
      if (!resp.ok) {
        console.log(
          `[COMPLIANCE_EMIT][${logLabel}] failed status=${resp.status} transport=${transport} origin=${appendUrl.origin} path=${appendUrl.pathname}`,
        );
        return { ok: false, status: resp.status };
      }
      // TODO: reduce/remove success log after rollout verification.
      console.log(`[COMPLIANCE_EMIT][${logLabel}] ok transport=${transport}`);
      return { ok: true, status: resp.status };
    } catch (err) {
      if (err?.name === "AbortError") {
        console.log(`[COMPLIANCE_EMIT][${logLabel}] failed error=timeout`);
        return { ok: false, error: "timeout" };
      }
      console.log(`[COMPLIANCE_EMIT][${logLabel}] failed error=fetch_failed`);
      return { ok: false, error: "fetch_failed" };
    } finally {
      clearTimeout(timer);
    }
  } catch (_) {
    return { ok: false, error: "internal_error" };
  }
}

function maskEmailForLog(value) {
  const email = safeStr(value);
  if (!email) return "";
  const at = email.indexOf("@");
  if (at <= 0) return "***";
  return `${email.slice(0, 1)}***${email.slice(at)}`;
}


async function mollieCreatePayment(payload, env, request) {
  try {
    const mollieConfig = getMollieConfig(env);
    if (!mollieConfig.ok) return mollieConfig;
    if (!env.BOOKING_KV) {
      return { ok: false, error: "Missing BOOKING_KV binding in Cloudflare." };
    }

    // Minimal required fields for quote
    if (!payload?.from || !payload?.to || (!(payload?.date && payload?.time) && !payload?.pickup_iso)) {
      return { ok: false, error: "Missing fields: from, to, and either (date+time) or pickup_iso" };
    }

    // If we received a booking-style payload (pickup_iso), derive date/time for quote
    let date = safeStr(payload?.date);
    let time = safeStr(payload?.time);
    const pickupIso = safeStr(payload?.pickup_iso);

    if ((!date || !time) && pickupIso) {
      const parts = brusselsDateTimePartsFromIso(pickupIso);
      date = parts.date;
      time = parts.time;

      // Fallbacks: accept "datetime-local" strings (no timezone) or EU formats.
      // Some front-ends send pickup_iso as "YYYY-MM-DDTHH:MM" (without Z/offset).
      // If Intl-based extraction above couldn't parse it, derive date/time manually.
      if (!date || !time) {
        const m1 = pickupIso.match(/^([0-9]{4}-[0-9]{2}-[0-9]{2})[T ]([0-9]{2}:[0-9]{2})/);
        if (m1) {
          date = m1[1];
          time = m1[2];
        }
      }
      if (!date || !time) {
        const m2 = pickupIso.match(/^([0-9]{2})\/([0-9]{2})\/([0-9]{4})[ T]([0-9]{2}:[0-9]{2})/);
        if (m2) {
          // Keep EU date format for /quote (it supports dd/mm/yyyy)
          date = `${m2[1]}/${m2[2]}/${m2[3]}`;
          time = m2[4];
        }
      }
    }

    // If we still couldn't derive a usable date/time, fail fast with a clear message.
    if (!date || !time) {
      return {
        ok: false,
        error: "Could not derive date/time from pickup_iso. Send either (date+time) or a valid pickup_iso (e.g. 2026-01-18T22:00:00.000Z).",
        received: { date: safeStr(payload?.date), time: safeStr(payload?.time), pickup_iso: pickupIso }
      };
    }

    // Quote payload MUST contain date/time.
    // We prefer the server-side quote, but if the front-end already computed a fresh quote
    // (which uses this same worker as source-of-truth), we can reuse it to avoid a second
    // Mapbox call and reduce the chance of geocode hiccups.
    const payloadClean = { ...(payload || {}) };
    const requestedScope = resolveExplicitBookingRequestScope({
      request,
      url: new URL(request.url),
      body: payload,
      allowLegacyFallback: false,
    });
    if (!requestedScope?.hasScope) {
      return requestedScope?.error === "tenant_scope_conflict"
        ? scopeConflictError()
        : missingTenantScopeError();
    }
    const paymentTenantId = safeStr(requestedScope.tenant_id, 80);
    const paymentCompanyId = safeStr(requestedScope.company_id, 80);
    payloadClean.tenant_id = paymentTenantId;
    payloadClean.tenantId = paymentTenantId;
    payloadClean.company_id = paymentCompanyId;
    payloadClean.companyId = paymentCompanyId;
    const sourceBookingId = safeStr(
      payload?.booking_id ??
        payload?.bookingId,
      160,
    );
    if (sourceBookingId) {
      const loaded = await loadBookingRecord(env, sourceBookingId);
      if (!bookingMatchesRequestedTenantScope(loaded?.rec, requestedScope)) {
        return { ok: false, error: "forbidden" };
      }
    }
    const clientQuote = payloadClean.quote;
    const quotePayload = {
      ...payloadClean,
      date,
      time,
      ...(paymentTenantId ? { tenant_id: paymentTenantId, tenantId: paymentTenantId } : {}),
      ...(paymentCompanyId ? { company_id: paymentCompanyId, companyId: paymentCompanyId } : {}),
    };

    // 1) payment booking id (internal, used for Mollie + status polling)
    const bookingId = crypto.randomUUID();

    // Public booking id (human readable) coming from /book pipeline
    const publicBookingId = safeStr(payload?.__booking_id || payload?.booking_id || payload?.bookingId || payload?.public_booking_id);
    if (publicBookingId) {
      // Make sure we persist it inside the stored payload too (so finalize uses the same id everywhere)
      payloadClean.__booking_id = publicBookingId;
    }
    const publicBookingReference = safeStr(
      payload?.__public_booking_reference ||
        payload?.public_booking_reference ||
        payload?.publicBookingReference ||
        payload?.booking_reference ||
        payload?.bookingReference ||
        payload?.public_reference ||
        payload?.publicReference,
    );
    if (publicBookingReference) {
      payloadClean.__public_booking_reference = publicBookingReference;
      attachPublicBookingReferenceAliases(payloadClean, publicBookingReference);
    }

    // 2) compute quote
    let quote = null;

    if (clientQuote && clientQuote.ok && clientQuote.price_incl_vat != null) {
      // Use client quote (already computed via /quote)
      quote = clientQuote;
    } else {
      // Compute quote via internal call
      const quoteRes = await fetch(new URL("/quote", request.url), {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(quotePayload)
      });

      quote = await quoteRes.json().catch(() => ({}));
      if (!quoteRes.ok || !quote?.ok) {
        return { ok: false, error: "Quote failed", details: quote };
      }
    }

    // ✅ Amount must include return trip if enabled.
    // /quote returns the return leg as a separate object: quote.return.price_incl_vat
    const mainIncl = Number(quote?.price_incl_vat || 0);
    const retIncl = Number(quote?.return?.price_incl_vat || 0);
    const totalIncl = (Number.isFinite(mainIncl) ? mainIncl : 0) + (Number.isFinite(retIncl) ? retIncl : 0);

    const amountValue = money2(totalIncl);
    const initialPaymentFields = paymentFieldsFromPayload(payload);

    // 3) store booking as PENDING
    const createdAt = new Date().toISOString();
    await env.BOOKING_KV.put(
      `booking:${bookingId}`,
      JSON.stringify({
        bookingId,
        status: "PENDING",
        createdAt,
        tenant_id: paymentTenantId,
        tenantId: paymentTenantId,
        company_id: paymentCompanyId,
        companyId: paymentCompanyId,
        public_booking_id: publicBookingId || null,
        public_booking_reference: publicBookingReference || null,
        publicBookingReference: publicBookingReference || null,
        booking_reference: publicBookingReference || null,
        bookingReference: publicBookingReference || null,
        planning_reference: safeStr(payloadClean?.__planning_reference) || null,
        planningReference: safeStr(payloadClean?.__planning_reference) || null,
        payload: payloadClean,
        quote,
        mollie: null,
        confirmed: null,
        ...initialPaymentFields
      }),
      { expirationTtl: 60 * 60 } // 1 hour
    );

    // 4) Mollie payment create
    const base = getBaseUrl(request);

    // redirectUrl: your front-end can pass return_url; default to the Fluxidi app deep link
    // so customers are bounced back automatically after Mollie checkout.
    const returnToRaw = safeStr(payload?.return_url);
    const returnTo = returnToRaw || "fluxidi://pay/return";
    // Always go through the worker return page so we can auto-finalize even if the webhook fails.
    // After finalize, we redirect back to the deep link (or the explicit returnTo).
    const redirectUrl = `${base}/pay/return?id=${encodeURIComponent(bookingId)}&return_to=${encodeURIComponent(returnTo)}`;
    // webhookUrl: points to this worker
    const webhookUrl = `${base}/webhook/mollie`;

    const commProfile = await resolveTenantCommunicationProfile(env, paymentTenantId, paymentCompanyId);
    const description = `${safeBrandName(commProfile?.brandName, "Fluxidi Taxi")} booking ${bookingId}`;

    const mollieRes = await fetch("https://api.mollie.com/v2/payments", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${mollieConfig.apiKey}`,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        amount: { currency: "EUR", value: amountValue },
        description,
        redirectUrl,
        webhookUrl,
        metadata: { bookingId }
      })
    });

    const mollie = await mollieRes.json().catch(() => ({}));
    if (!mollieRes.ok || !mollie?.id || !mollie?._links?.checkout?.href) {
      // Keep booking in KV for debugging
      await env.BOOKING_KV.put(
        `booking:${bookingId}`,
        JSON.stringify({
          bookingId,
          status: "PENDING",
          createdAt,
          tenant_id: paymentTenantId,
          tenantId: paymentTenantId,
          company_id: paymentCompanyId,
          companyId: paymentCompanyId,
          payload: payloadClean,
          quote,
          mollie_error: mollie
        }),
        { expirationTtl: 60 * 60 }
      );

      return { ok: false, error: "Mollie payment failed", mollie };
    }

    // 5) Update KV with mollie id
    const storedRaw = await env.BOOKING_KV.get(`booking:${bookingId}`);
    const stored = storedRaw ? JSON.parse(storedRaw) : {};
    Object.assign(stored, normalizedPaymentFields({
      status: mollie.status || "open",
      paymentId: mollie.id,
    }));
    stored.mollie = { id: mollie.id, payment_id: mollie.id, status: mollie.status || "open" };

    await env.BOOKING_KV.put(
      `booking:${bookingId}`,
      JSON.stringify(stored),
      { expirationTtl: 60 * 60 }
    );

    return {
      ok: true,
      bookingId, // internal payment booking id
      publicBookingId: publicBookingId || null,
      amount: { currency: "EUR", value: amountValue },
      checkoutUrl: mollie._links.checkout.href,
      statusUrl: `${base}/pay/status?id=${encodeURIComponent(bookingId)}`
    };
  } catch (e) {
    return { ok: false, error: String(e?.message || e) };
  }
}

async function mollieFetchPayment(molliePaymentId, env) {
  const mollieConfig = getMollieConfig(env);
  if (!mollieConfig.ok) {
    return { ok: false, status: 500, data: { error: mollieConfig.error } };
  }
  const r = await fetch(`https://api.mollie.com/v2/payments/${encodeURIComponent(molliePaymentId)}`, {
    method: "GET",
    headers: { "Authorization": `Bearer ${mollieConfig.apiKey}` }
  });
  const j = await r.json().catch(() => ({}));
  return { ok: r.ok, status: r.status, data: j };
}

/**
 * Mollie sends webhooks with content-type application/x-www-form-urlencoded by default.
 * Typically it includes "id=tr_..."
 */
async function mollieWebhook(request, env) {
  // ✅ Webhook should NEVER finalize bookings.
  // Reason: /pay/status (called from /pay/return polling) is the single "finalizer".
  // Webhook only updates KV with the latest Mollie status so the poller can act.
  try {
    const mollieConfig = getMollieConfig(env);
    if (!mollieConfig.ok) return { ok: false, error: mollieConfig.error };
    if (!env.BOOKING_KV) return { ok: false, error: "Missing BOOKING_KV binding" };

    const ct = request.headers.get("content-type") || "";
    let mollieId = "";

    if (ct.includes("application/json")) {
      const body = await safeJson(request);
      mollieId = safeStr(body?.id);
    } else {
      const raw = await request.text();
      const params = new URLSearchParams(raw);
      mollieId = safeStr(params.get("id"));
    }

    if (!mollieId) {
      return { ok: true, received: true, processed: false, reason: "Missing Mollie payment id" };
    }

    const p = await mollieFetchPayment(mollieId, env);
    if (!p.ok) {
      return { ok: true, received: true, processed: false, reason: "Failed to fetch Mollie payment" };
    }

    const bookingId = safeStr(p.data?.metadata?.bookingId);
    const mollieStatus = safeStr(p.data?.status);

    if (!bookingId) {
      return { ok: true, received: true, processed: false, reason: "No bookingId in Mollie metadata" };
    }

    const key = `booking:${bookingId}`;
    const stored = (await env.BOOKING_KV.get(key, "json")) || {};

    // Persist latest Mollie status
    Object.assign(stored, normalizedPaymentFields({
      status: mollieStatus,
      paymentId: mollieId,
      paidAt: stored.paid_at,
    }));
    stored.mollie = {
      id: mollieId,
      payment_id: mollieId,
      status: mollieStatus,
      last_webhook_at: new Date().toISOString()
    };

    // Update "status" markers for admin visibility (but do NOT confirm here)
    if (mollieStatus === "paid") {
      stored.status = stored.status === "CONFIRMED" ? "CONFIRMED" : "PAID";
      stored.paid_at = stored.paid_at || new Date().toISOString();
      stored.paidAt = stored.paidAt || stored.paid_at;
      stored.public_booking_id = stored.public_booking_id || safeStr(stored?.payload?.__booking_id) || null;
    } else if (["canceled", "expired", "failed"].includes(mollieStatus)) {
      stored.status = "FAILED";
      stored.failed_at = stored.failed_at || new Date().toISOString();
    } else {
      stored.status = stored.status === "CONFIRMED" ? "CONFIRMED" : "PENDING";
    }

    await env.BOOKING_KV.put(key, JSON.stringify(stored), { expirationTtl: 60 * 60 * 24 * 30 });

    return { ok: true, received: true, processed: true, bookingId, mollieStatus, action: "status-updated" };
  } catch (e) {
    // Mollie expects 200. We still return ok-ish to avoid retries storms.
    return { ok: false, received: true, processed: false, error: String(e?.message || e) };
  }
}


/* ===================== BOOKING (CALENDAR + EMAIL + INVOICE) ===================== */

// /book calls this directly.
// Mollie webhook calls this after payment and sets payload.__mollie_paid = true.
// This function must never throw (to avoid 500s). It returns {ok:false,error} on failures.

function _sanitizeBookingSourceContext(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) return {};
  const out = {};
  const entries = Object.entries(input).slice(0, 12);
  for (const [rawKey, rawValue] of entries) {
    const key = safeStr(rawKey, 64);
    if (!key) continue;
    if (rawValue == null) {
      out[key] = null;
      continue;
    }
    const t = typeof rawValue;
    if (t === "boolean") {
      out[key] = rawValue;
      continue;
    }
    if (t === "number") {
      out[key] = Number.isFinite(rawValue) ? rawValue : null;
      continue;
    }
    if (t === "string") {
      out[key] = safeStr(rawValue, 240);
      continue;
    }
    // Keep source_context JSON-safe and shallow in Phase 1.
    out[key] = safeStr(String(rawValue), 240);
  }
  return out;
}

function resolveBookingTenantContext({ payload, request, env }) {
  let tenantId = "";
  let companyId = "";
  let tenantResolutionMode = "";

  // Future trusted route/server context can be injected here and should win.
  const trustedContext =
    payload &&
    typeof payload === "object" &&
    payload.__trusted_tenant_context &&
    typeof payload.__trusted_tenant_context === "object" &&
    !Array.isArray(payload.__trusted_tenant_context)
      ? payload.__trusted_tenant_context
      : null;
  if (trustedContext) {
    tenantId = safeStr(trustedContext.tenant_id ?? trustedContext.tenantId, 80);
    companyId = safeStr(trustedContext.company_id ?? trustedContext.companyId, 80);
    if (tenantId) {
      tenantResolutionMode = "trusted_route";
    }
  }

  // Phase 1 accepts app context from payload.
  if (!tenantId) {
    tenantId = safeStr(
      payload?.tenant_id ?? payload?.tenantId ?? payload?.company_id ?? payload?.companyId,
      80,
    );
    if (tenantId) tenantResolutionMode = "payload_context";
  }
  if (!companyId) {
    companyId = safeStr(payload?.company_id ?? payload?.companyId ?? tenantId, 80);
  }

  // Legacy fallback for existing MVP behavior.
  if (!tenantId) {
    tenantId = "fluxidi";
    tenantResolutionMode = "legacy_fallback";
  }
  if (!companyId) companyId = tenantId;

  const bookingSource = safeStr(
    payload?.booking_source ?? payload?.bookingSource ?? "flutter_app",
    64,
  ) || "flutter_app";
  const entryChannel = safeStr(
    payload?.entry_channel ?? payload?.entryChannel ?? "flutter_calculator",
    64,
  ) || "flutter_calculator";
  const sourceContext = _sanitizeBookingSourceContext(
    payload?.source_context ?? payload?.sourceContext,
  );

  return {
    tenant_id: tenantId,
    company_id: companyId,
    booking_source: bookingSource,
    entry_channel: entryChannel,
    source_context: sourceContext,
    tenant_resolution_mode: tenantResolutionMode || "legacy_fallback",
    tenant_resolved_at: new Date().toISOString(),
  };
}

const BOOKING_INTENT_TTL_SECONDS = 20 * 60;

function _bookingIntentNormalizeText(value, maxLen = 240) {
  const raw = safeStr(value, maxLen).toLowerCase();
  if (!raw) return "";
  return raw.replace(/\s+/g, " ").trim();
}

function _bookingIntentNormalizeBool(value) {
  if (value === true) return "1";
  if (value === false) return "0";
  const raw = _bookingIntentNormalizeText(value, 24);
  if (!raw) return "0";
  if (raw === "1" || raw === "true" || raw === "yes" || raw === "ja" || raw === "on") {
    return "1";
  }
  return "0";
}

function _bookingIntentNormalizeInt(value, fallback = 0, min = 0, max = 9999) {
  const asNumber = Number(value);
  if (Number.isFinite(asNumber)) {
    return String(Math.max(min, Math.min(max, Math.trunc(asNumber))));
  }
  const raw = _bookingIntentNormalizeText(value, 24);
  if (!raw) return String(fallback);
  const parsed = Number.parseInt(raw, 10);
  if (!Number.isFinite(parsed)) return String(fallback);
  return String(Math.max(min, Math.min(max, parsed)));
}

function _bookingIntentStableValue(value) {
  if (value == null) return null;
  if (Array.isArray(value)) {
    return value.map((item) => _bookingIntentStableValue(item));
  }
  if (typeof value === "object") {
    const out = {};
    const keys = Object.keys(value).sort();
    for (const key of keys) {
      out[key] = _bookingIntentStableValue(value[key]);
    }
    return out;
  }
  if (typeof value === "boolean") return value;
  if (typeof value === "number") {
    if (!Number.isFinite(value)) return null;
    return Number(value.toFixed(6));
  }
  return _bookingIntentNormalizeText(String(value), 240);
}

function _bookingIntentNormalizeStops(stops) {
  if (!Array.isArray(stops) || !stops.length) return "[]";
  const normalized = stops.map((item) => _bookingIntentStableValue(item));
  return JSON.stringify(normalized);
}

function _bookingIntentScopePart(value, fallback) {
  const raw = _bookingIntentNormalizeText(value, 120);
  if (!raw) return fallback;
  const normalized = raw.replace(/[^a-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return normalized || fallback;
}

function _bookingIntentHash(parts = []) {
  // FNV-1a 32-bit (fast, deterministic, sufficient for short-lived dedupe keying)
  const input = parts.join("|");
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

function _bookingIntentMask(value) {
  const raw = safeStr(value, 128);
  if (!raw) return "";
  if (raw.length <= 6) return raw;
  return `${raw.slice(0, 3)}...${raw.slice(-3)}`;
}

function _bookingIntentScopeMask(scope = {}) {
  return {
    tenant: _bookingIntentMask(scope?.tenant_id),
    company: _bookingIntentMask(scope?.company_id),
  };
}

function buildBookingIntentDescriptor({
  tenant_id,
  company_id,
  pickup_iso,
  from,
  to,
  customer_email,
  customer_phone,
  service,
  extra_service,
  extra_service_key,
  wait_min,
  return_flag,
  return_enabled,
  return_from,
  return_to,
  return_pickup_iso,
  stop_count,
  stops,
  tier,
  pax,
  bags,
} = {}) {
  const tenantPart = _bookingIntentScopePart(tenant_id, "fluxidi");
  const companyPart = _bookingIntentScopePart(company_id || tenant_id, tenantPart);
  const normalizedPickupIso = _bookingIntentNormalizeText(pickup_iso, 80);
  const normalizedFrom = _bookingIntentNormalizeText(from, 240);
  const normalizedTo = _bookingIntentNormalizeText(to, 240);
  const normalizedEmail = _bookingIntentNormalizeText(customer_email, 180);
  const normalizedPhone = _bookingIntentNormalizeText(customer_phone, 64);
  const normalizedService = _bookingIntentNormalizeText(service, 32);
  const normalizedExtraService = _bookingIntentNormalizeText(extra_service, 64);
  const normalizedExtraServiceKey = _bookingIntentNormalizeText(extra_service_key, 64);
  const normalizedWaitMin = _bookingIntentNormalizeInt(wait_min, 0, 0, 9999);
  const normalizedReturnEnabled = _bookingIntentNormalizeBool(
    return_enabled != null ? return_enabled : return_flag,
  );
  const normalizedReturnFrom = _bookingIntentNormalizeText(return_from, 240);
  const normalizedReturnTo = _bookingIntentNormalizeText(return_to, 240);
  const normalizedReturnPickupIso = _bookingIntentNormalizeText(return_pickup_iso, 80);
  const normalizedStopCount = _bookingIntentNormalizeInt(stop_count, 0, 0, 99);
  const normalizedStops = _bookingIntentNormalizeStops(stops);
  const normalizedTier = _bookingIntentNormalizeText(tier, 32);
  const normalizedPax = String(clampInt(pax, 1, 12));
  const normalizedBags = String(Math.max(0, clampInt(bags, 0, 99)));
  const contact = normalizedEmail || normalizedPhone || "";
  const hash = _bookingIntentHash([
    tenantPart,
    companyPart,
    normalizedPickupIso,
    normalizedFrom,
    normalizedTo,
    contact,
    normalizedService,
    normalizedExtraService,
    normalizedExtraServiceKey,
    normalizedWaitMin,
    normalizedReturnEnabled,
    normalizedReturnFrom,
    normalizedReturnTo,
    normalizedReturnPickupIso,
    normalizedStopCount,
    normalizedStops,
    normalizedTier,
    normalizedPax,
    normalizedBags,
  ]);
  const key = `booking_intent:${tenantPart}:${companyPart}:${hash}`;
  return {
    key,
    hash,
    tenantPart,
    companyPart,
  };
}

function buildIdempotentBookingHitResponse(canonicalBookingId, rec) {
  const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
  const publicBookingReference = safeStr(
    rec?.public_booking_reference ||
      rec?.publicBookingReference ||
      rec?.booking_reference ||
      rec?.bookingReference ||
      rec?.public_reference ||
      rec?.publicReference ||
      booking?.public_booking_reference ||
      booking?.publicBookingReference ||
      booking?.booking_reference ||
      booking?.bookingReference ||
      booking?.public_reference ||
      booking?.publicReference,
  );
  const planningReference = safeStr(
    rec?.planning_reference ||
      rec?.planningReference ||
      booking?.planning_reference ||
      booking?.planningReference,
  );
  const paymentStatus = safeStr(
    rec?.payment_status ||
      rec?.paymentStatus ||
      booking?.payment_status ||
      booking?.paymentStatus,
  );
  return {
    ok: true,
    booking_id: canonicalBookingId,
    bookingId: canonicalBookingId,
    public_booking_id: canonicalBookingId,
    public_booking_reference: publicBookingReference || undefined,
    publicBookingReference: publicBookingReference || undefined,
    booking_reference: publicBookingReference || undefined,
    bookingReference: publicBookingReference || undefined,
    public_reference: publicBookingReference || undefined,
    publicReference: publicBookingReference || undefined,
    planning_reference: planningReference || undefined,
    planningReference: planningReference || undefined,
    status: _normLifecycleStatus(rec?.status || rec?.stage || null),
    payment_status: paymentStatus || undefined,
    paymentStatus: paymentStatus || undefined,
  };
}

async function handleBooking(payload, env, request) {
  try {
    if (!env?.BOOKING_KV) {
      return { ok: false, error: "Missing BOOKING_KV binding" };
    }

    const from = safeStr(payload?.from);
    const to = safeStr(payload?.to);
    if (!from || !to) return { ok: false, error: "Missing fields: from, to" };

    // Accept either (date+time) OR pickup_iso.
    let date = safeStr(payload?.date);
    let time = safeStr(payload?.time);
    const pickupIsoRaw = safeStr(payload?.pickup_iso);

    if ((!date || !time) && pickupIsoRaw) {
      const parts = brusselsDateTimePartsFromIso(pickupIsoRaw);
      date = parts.date;
      time = parts.time;

      // Fallback for datetime-local strings.
      if (!date || !time) {
        const m1 = pickupIsoRaw.match(/^([0-9]{4}-[0-9]{2}-[0-9]{2})[T ]([0-9]{2}:[0-9]{2})/);
        if (m1) {
          date = m1[1];
          time = m1[2];
        }
      }
      if (!date || !time) {
        const m2 = pickupIsoRaw.match(/^([0-9]{2})\/([0-9]{2})\/([0-9]{4})[ T]([0-9]{2}:[0-9]{2})/);
        if (m2) {
          date = `${m2[1]}/${m2[2]}/${m2[3]}`;
          time = m2[4];
        }
      }
    }

    if (!date || !time) {
      return {
        ok: false,
        error: "Missing fields: either (date+time) or pickup_iso",
        received: { date: safeStr(payload?.date), time: safeStr(payload?.time), pickup_iso: pickupIsoRaw }
      };
    }
    const tenantContext = resolveBookingTenantContext({ payload, request, env });
    const fleetScope = normalizeFleetTenantScope(tenantContext);

    const pricingProfile = await _loadTenantPricingProfile(env, tenantContext);
    const vat_rate = clampNumber(
      pricingProfile?.vat_rate,
      clampNumber(payload?.vat_rate, 0.06, 0, 1),
      0,
      1,
    );
    const pax = clampInt(payload?.pax, 1, 3);
    const bags = Math.max(0, clampInt(payload?.bags, 0, 99));
    const tier = normalizeTier(payload?.tier || "comfort");
    const service = normalizeService(payload?.service || "passenger");
    const stops = normalizeStops(payload);
    const wait_min = parseDurationMin(payload?.wait_min ?? payload?.wait_minutes ?? payload?.waiting_min ?? payload?.wait, 0);
    const requestedAssignedVehicleId =
      safeStr(payload?.assigned_vehicle_id || payload?.vehicle_id, 128) || null;
    let resolvedAssignedVehicleId = requestedAssignedVehicleId;
    let resolvedAssignedDriver = null;
    const stop_count = stops.length;
    

    const biz = normalizeBusiness(payload);
    const business_detected = !!biz.vat_number;
    const customerContact = normalizeCustomerContact(payload);
    const customerEmailLanguage = normalizeCustomerEmailLanguage(payload);

    // Business rule: if VAT is provided => upfront payment required (Mollie test/live).
    // Private customers can book without immediate payment.
    const requiresPayment = business_detected;
    const paymentFields = paymentFieldsFromPayload(payload);
    const molliePaidConfirmed = payload.__mollie_paid === true && paymentFields.payment_status === "paid";
    const shouldReserveNow = !(business_detected && !molliePaidConfirmed);

    // Invoices are mandatory for business bookings; optional for private (if you ever enable it later).
    const invoice_requested = business_detected ? true : !!biz.invoice_requested;

    // If no payment is required, we mark as "paid" so the flow skips Mollie and confirms immediately.
    if (!requiresPayment) payload.__mollie_paid = true;

    // Extra service only for PREMIUM
    const extra = normalizeExtraService(payload, tier);

    // Build pickup ISO (canonical) in Brussels.
    // If payload already has pickup_iso, keep it, else derive from date+time.
    let pickup_iso = pickupIsoRaw;
    if (!pickup_iso) {
      // date can be dd/mm/yyyy (preferred) or yyyy-mm-dd
      const isoGuess = brusselsIsoFromDateTime(date, time);
      pickup_iso = isoGuess;
    }

    if (!pickup_iso) return { ok: false, error: "Could not create pickup_iso" };

    const bookingIntent = buildBookingIntentDescriptor({
      tenant_id: tenantContext.tenant_id,
      company_id: tenantContext.company_id,
      pickup_iso,
      from,
      to,
      customer_email: customerContact.email,
      customer_phone: customerContact.phone,
      service,
      extra_service: payload?.extra_service,
      extra_service_key: extra?.key || payload?.extra_service_key,
      wait_min,
      return_flag: payload?.return,
      return_enabled: payload?.return_enabled ?? payload?.returnEnabled,
      return_from: payload?.return_from ?? payload?.returnFrom,
      return_to: payload?.return_to ?? payload?.returnTo,
      return_pickup_iso: payload?.return_pickup_iso ?? payload?.returnPickupIso,
      stop_count,
      stops,
      tier,
      pax,
      bags,
    });
    const idempotencyScope = {
      tenant_id: tenantContext.tenant_id,
      company_id: tenantContext.company_id,
      hasScope: true,
    };
    const mappedCanonicalId = safeStr(await env.BOOKING_KV.get(bookingIntent.key));
    if (mappedCanonicalId) {
      const mappedRecord = await env.BOOKING_KV.get(`booking:${mappedCanonicalId}`, { type: "json" });
      if (mappedRecord && bookingMatchesRequestedTenantScope(mappedRecord, idempotencyScope)) {
        if (isTerminalLifecycleStatus(_bookingLifecycleValue(mappedRecord))) {
          const maskedScope = _bookingIntentScopeMask(idempotencyScope);
          console.log(
            `[BOOKING][IDEMPOTENCY][STALE_TERMINAL] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(mappedCanonicalId)}`,
          );
          try {
            await env.BOOKING_KV.delete(bookingIntent.key);
          } catch (_) {
            // Best-effort cleanup only.
          }
        } else {
          const maskedScope = _bookingIntentScopeMask(idempotencyScope);
          console.log(
            `[BOOKING][IDEMPOTENCY][HIT] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(mappedCanonicalId)}`,
          );
          return buildIdempotentBookingHitResponse(mappedCanonicalId, mappedRecord);
        }
      } else {
        const maskedScope = _bookingIntentScopeMask(idempotencyScope);
        console.log(
          `[BOOKING][IDEMPOTENCY][STALE] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(mappedCanonicalId)}`,
        );
        try {
          await env.BOOKING_KV.delete(bookingIntent.key);
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    } else {
      const maskedScope = _bookingIntentScopeMask(idempotencyScope);
      console.log(
        `[BOOKING][IDEMPOTENCY][MISS] tenant=${maskedScope.tenant} company=${maskedScope.company}`,
      );
    }

    // =========================
    // BOOKING ID (human + uuid)
    // =========================
    const providedId = safeStr(payload?.__booking_id || payload?.bookingId || payload?.booking_id);
    const providedPublicBookingReference = safeStr(
      payload?.__public_booking_reference ||
        payload?.public_booking_reference ||
        payload?.publicBookingReference ||
        payload?.booking_reference ||
        payload?.bookingReference ||
        payload?.public_reference ||
        payload?.publicReference,
    );
    const providedPlanningReference = safeStr(
      payload?.__planning_reference ||
        payload?.planning_reference ||
        payload?.planningReference,
    );
    const booking_uuid = (crypto?.randomUUID ? crypto.randomUUID() : `u_${Date.now()}_${Math.random().toString(16).slice(2)}`);
    const canonicalBookingId = providedId || await nextHumanBookingId(env, pickup_iso);
    const publicBookingReference = await allocateAndReservePublicBookingReference(env, {
      tenant_id: tenantContext.tenant_id,
      company_id: tenantContext.company_id,
      pickup_iso,
      canonical_booking_id: canonicalBookingId,
      preferred_reference: providedPublicBookingReference || null,
    });
    attachPublicBookingReferenceAliases(payload, publicBookingReference);
    payload.__public_booking_reference = publicBookingReference;
    const planningReference = await allocateAndReserveDocumentReference(env, {
      tenant_id: tenantContext.tenant_id,
      company_id: tenantContext.company_id,
      sequence_type: "planning",
      prefix: "PLN",
      pickup_iso,
      canonical_booking_id: canonicalBookingId,
      preferred_reference: providedPlanningReference || null,
    });
    attachPlanningReferenceAliases(payload, planningReference);
    payload.__planning_reference = planningReference;



    // Compute server-side quote (source of truth)
    const routeOut = await routeFromTextsWithStopsDetailed({
      fromText: from,
      toText: to,
      stopsTexts: stops,
      token: env.MAPBOX_TOKEN
    });

    const distance_km = round1((routeOut?.route?.distance || 0) / 1000);
    const duration_route_min = Math.round((routeOut?.route?.duration || 0) / 60);

    // Return planning (optional)
    
    const ret = normalizeReturnEnabled(payload, wait_min);
    if (!pricingProfile.return_enabled) {
      ret.enabled = false;
    }

    // If UI provides a separate return date/time, we treat the return leg as a separate trip moment.
    const return_date = safeStr(payload?.return_date || payload?.returnDate);
    const return_time = safeStr(payload?.return_time || payload?.returnTime);
    const hasReturnSchedule = !!(ret.enabled && return_date && return_time);
    const return_pickup_iso = hasReturnSchedule ? brusselsIsoFromDateTime(return_date, return_time) : null;

    let return_from = "";
    let return_to = "";
    let return_distance_km = 0;
    let return_duration_min = 0;
    let returnPricing = null;
    let returnLegs = [];

    if (ret.enabled) {
      return_from = safeStr(payload?.return_from || payload?.returnFrom) || to;
      return_to = safeStr(payload?.return_to || payload?.returnTo) || from;
      if (return_from && return_to) {
        const outR = await routeFromTextsWithStopsDetailed({
          fromText: return_from,
          toText: return_to,
          stopsTexts: [],
          token: env.MAPBOX_TOKEN
        });
        return_distance_km = round1((outR?.route?.distance || 0) / 1000);
        return_duration_min = Math.round((outR?.route?.duration || 0) / 60);
        returnLegs = Array.isArray(outR?.legs) ? outR.legs : [];
        returnPricing = calcPrice({
          distance_km: return_distance_km,
          duration_min: return_duration_min,
          tier,
          service,
          when: normalizeWhen(date, time),
          time_str: time,
          pax,
          bags,
          vat_rate,
          stop_count: 0,
          wait_min: 0,
          pricing_profile: pricingProfile,
          apply_return_fee: true,
        });
      }
    }

    const when = normalizeWhen(date, time);
    const mainPricing = calcPrice({
      distance_km,
      duration_min: duration_route_min,
      tier,
      service,
      when,
      time_str: time,
      pax,
      bags,
      vat_rate,
      stop_count,
      wait_min,
      pricing_profile: pricingProfile,
      apply_return_fee: false,
    });

    // Total pricing = main + (optional) return
    const totalPricing = (() => {
      const main = mainPricing || {};
      const retp = (ret.enabled && returnPricing) ? returnPricing : null;

      // NOTE: calcPrice returns monetary fields as strings ("143.24"), so we MUST cast to numbers before summing.
      const mainEx = Number(String(main.price_ex_vat ?? "0").replace(",", "."));
      const mainVat = Number(String(main.price_vat ?? "0").replace(",", "."));
      const mainIncl = Number(String(main.price_incl_vat ?? "0").replace(",", "."));

      const retEx = retp ? Number(String(retp.price_ex_vat ?? "0").replace(",", ".")) : 0;
      const retVat = retp ? Number(String(retp.price_vat ?? "0").replace(",", ".")) : 0;
      const retIncl = retp ? Number(String(retp.price_incl_vat ?? "0").replace(",", ".")) : 0;

      const ex = round2((Number.isFinite(mainEx) ? mainEx : 0) + (Number.isFinite(retEx) ? retEx : 0));
      const vat = round2((Number.isFinite(mainVat) ? mainVat : 0) + (Number.isFinite(retVat) ? retVat : 0));
      const incl = round2((Number.isFinite(mainIncl) ? mainIncl : 0) + (Number.isFinite(retIncl) ? retIncl : 0));

      return { price_ex_vat: ex, price_vat: vat, price_incl_vat: incl };
    })();

    // Calendar availability + creation (if configured)
    const calendarAuthConfig = await loadGoogleCalendarAuthConfig(env, tenantContext);
    const calendarConfigured = !!calendarAuthConfig?.configured;
    const calendarAuthSource = safeStr(calendarAuthConfig?.source, 24) || "none";
    console.log(
      `[CALENDAR_AUTH][SOURCE] bookingId=${canonicalBookingId} source=${calendarAuthSource} tenant=${tenantContext?.tenant_id || "-"} company=${tenantContext?.company_id || "-"}`,
    );
    const availabilityMode = _availabilityMode(env);
    const bookingServiceMin = Math.max(
      30,
      Math.round(
        Math.max(0, duration_route_min) +
          (hasReturnSchedule ? 0 : Math.max(0, return_duration_min)) +
          Math.max(0, wait_min) +
          Math.max(0, getStopHandlingMin(stop_count, env)) +
          Math.max(0, getPostBufferMin(env)),
      ),
    );
    let calendar_event_id = null;
    let htmlLink = null;
    let calendar = {
      configured: calendarConfigured,
      created: false,
      calendar_auth_source: calendarAuthSource,
      calendarAuthSource: calendarAuthSource,
    };
    let calendarSyncStatus = null;
    let calendarSyncErrorCode = null;
    let calendarSyncFailedAt = null;
    let calendarSyncError = null;
    let calendarSyncSuppressed = false;
    let calendarAllocatorHandled = false;
    let calendarPaymentHandled = false;

    if (calendarConfigured) {
      try {
        const calendarId = safeStr(calendarAuthConfig?.calendarId) || "primary";
        const accessToken = await googleAccessTokenFromConfig(calendarAuthConfig);

        const stopHandlingMin = getStopHandlingMin(stop_count, env);
        const postBufferMin = getPostBufferMin(env);

        const duration_main_min = Math.max(0, duration_route_min);
        const duration_return_min = Math.max(0, return_duration_min);

        // If return is scheduled separately, the outbound window should only block the outbound time.
        // Otherwise (classic round-trip), one event blocks both legs.
        const duration_total_min = hasReturnSchedule ? duration_main_min : (duration_main_min + duration_return_min);

        const totalServiceMin = duration_total_min + Math.max(0, wait_min) + Math.max(0, stopHandlingMin);
        const busyMin = totalServiceMin + postBufferMin;
        const win = computeWindow(pickup_iso, busyMin);

        if (availabilityMode !== "multi_vehicle") {
          // Travel gap rule: ensure enough time from previous drop-off to this pickup.
          const gapCheck = await ensureTravelGapFromPreviousEvent({
            accessToken,
            calendarId,
            pickupIso: pickup_iso,
            pickupFromText: from,
            env
          });
          if (gapCheck && gapCheck.ok === false) {
            return { ok: false, error: "Niet beschikbaar: onvoldoende rijtijd tussen boekingen.", availability: gapCheck };
          }

          const busy = await googleFreeBusy(accessToken, calendarId, win.start.toISOString(), win.end.toISOString());
          if (Array.isArray(busy) && busy.length) {
            return { ok: false, error: "Niet beschikbaar op dit moment (agenda is bezet).", busy };
          }

          // If return is scheduled separately, also validate availability for the return pickup time.
          if (hasReturnSchedule) {
            if (!return_pickup_iso) {
              return { ok: false, error: "Return scheduling selected but return_pickup_iso could not be built." };
            }
            const rPickup = new Date(return_pickup_iso);
            if (isNaN(rPickup.getTime())) {
              return { ok: false, error: "Ongeldige retourdatum/tijd." };
            }

            // Ensure enough travel time from previous events to the return pickup location.
            const gapCheckR = await ensureTravelGapFromPreviousEvent({
              accessToken,
              calendarId,
              pickupIso: return_pickup_iso,
              pickupFromText: return_from || to,
              env
            });
            if (gapCheckR && gapCheckR.ok === false) {
              return { ok: false, error: "Niet beschikbaar: onvoldoende rijtijd tussen boekingen (retour).", availability: gapCheckR };
            }

            const busyMinReturn = (duration_return_min + postBufferMin);
            const winR = computeWindow(return_pickup_iso, busyMinReturn);
            const busyR = await googleFreeBusy(accessToken, calendarId, winR.start.toISOString(), winR.end.toISOString());
            if (Array.isArray(busyR) && busyR.length) {
              return { ok: false, error: "Niet beschikbaar op het retourmoment (agenda is bezet).", busy: busyR };
            }
          }
        }

        if (availabilityMode === "multi_vehicle") {
          calendarAllocatorHandled = true;
          if (shouldReserveNow) {
            const alloc = await _allocatorRequest(env, pickup_iso, {
              action: "allocate",
              booking_id: canonicalBookingId,
              pickup_ms: Date.parse(pickup_iso),
              service_min: bookingServiceMin,
              tier,
              pax,
              bags,
              tenantScope: fleetScope,
            });
            if (!alloc?.allowed) {
              return {
                ok: false,
                error: "Niet beschikbaar: geen geschikt voertuig beschikbaar.",
                availability: {
                  reason: "vehicle_capacity",
                  availability_mode: availabilityMode,
                  allocator_reason: alloc?.reason || "vehicle_capacity_exceeded",
                  suitable_vehicle_count: Number(alloc?.suitable_vehicle_count || 0),
                  available_slots: Number(alloc?.available_slots || 0),
                },
              };
            }
            if (alloc?.assigned_vehicle_id) {
              resolvedAssignedVehicleId = String(alloc.assigned_vehicle_id);
              resolvedAssignedDriver = alloc?.assigned_driver || null;
            }
          } else {
            const vehicleCapacity = await _vehicleCapacityGateForRequest(env, {
              pickupMs: Date.parse(pickup_iso),
              serviceMin: bookingServiceMin,
              tier,
              pax,
              bags,
              tenantScope: fleetScope,
            });
            if (!vehicleCapacity.ok) {
              return {
                ok: false,
                error: "Niet beschikbaar: geen geschikt voertuig beschikbaar.",
                availability: {
                  reason: "vehicle_capacity",
                  availability_mode: availabilityMode,
                  ...vehicleCapacity,
                },
              };
            }
          }
          if (!resolvedAssignedDriver && resolvedAssignedVehicleId) {
            resolvedAssignedDriver = await _driverSummaryForVehicleId(
              env,
              resolvedAssignedVehicleId,
              fleetScope,
            );
          }
        }

        // Business bookings must be paid before creating the authoritative
        // calendar event. Availability has been checked above; creation happens
        // only when Mollie has actually reported "paid".
        if (business_detected && !molliePaidConfirmed) {
          calendarPaymentHandled = true;
          const pay = await mollieCreatePayment(
            {
              ...payload,
              __booking_id: canonicalBookingId,
              __public_booking_reference: publicBookingReference,
              bookingId: canonicalBookingId,
              tenant_id: tenantContext.tenant_id,
              tenantId: tenantContext.tenant_id,
              company_id: tenantContext.company_id,
              companyId: tenantContext.company_id,
              total_incl_vat: totalPricing.price_incl_vat,
              total_ex_vat: totalPricing.price_ex_vat,
              vat_amount: totalPricing.price_vat,
            },
            env,
            request
          );

          return {
            ok: true,
            booking_id: canonicalBookingId,
            bookingId: canonicalBookingId,
            public_booking_id: canonicalBookingId,
            public_booking_reference: publicBookingReference,
            publicBookingReference: publicBookingReference,
            booking_reference: publicBookingReference,
            bookingReference: publicBookingReference,
            public_reference: publicBookingReference,
            publicReference: publicBookingReference,
            planning_reference: planningReference,
            planningReference: planningReference,
            payment_booking_id: pay.bookingId || null,
            paymentBookingId: pay.bookingId || null,
            requiresPayment: true,
            paymentMode: "mollie",
            checkoutUrl: pay.checkoutUrl,
            statusUrl: pay.statusUrl || null,
            amount: pay.amount || null,
          };
        }

        const bookingForCalendar = {
          bookingId: canonicalBookingId,
          from,
          to,
          stops,
          wait_min,
          pax,
          bags,
          tier,
          service,
          return_enabled: ret.enabled,
          return_from,
          return_to,
          business_detected,
          invoice_requested,
          company_name: biz.company_name || "",
          vat_number: biz.vat_number || "",
          extra_service_label: extra.label || "",
          pickupStartIso: pickup_iso,
          price_incl_vat: totalPricing?.price_incl_vat,
          price_ex_vat: totalPricing?.price_ex_vat,
          price_vat: totalPricing?.price_vat,
          price_incl_vat_main: mainPricing?.price_incl_vat,
          price_incl_vat_return: returnPricing?.price_incl_vat,
          vat_rate
        };

        const title = `🚖 Fluxidi — ${humanServiceLabel(service)} — ${safeStr(payload?.name || payload?.custName || payload?.customer_name || "Klant")}`;
        const legsMain = Array.isArray(routeOut?.legs) ? routeOut.legs : [];
        const legsReturn = (ret.enabled && Array.isArray(returnLegs)) ? returnLegs : [];
        const allLegs = legsReturn.length
          ? [...legsMain, ...legsReturn.map((l, i) => ({ ...l, index: (legsMain.length + i + 1) }))]
          : legsMain;

        const desc = renderCalendarDescription(bookingForCalendar, allLegs, { returnPricing, returnRoute: { from: return_from, to: return_to, distance_km: return_distance_km, duration_min: return_duration_min } });

        // Calendar event(s)
        console.log(`[CALENDAR_CREATE][REQUEST] bookingId=${canonicalBookingId} reason=booking_confirmed hasCustomerCompany=${!!biz.company_name} hasCustomerVat=${!!biz.vat_number}`);
        const existingCalendar = await existingCalendarForBooking(env, canonicalBookingId);
        if (existingCalendar?.eventId) {
          calendar_event_id = existingCalendar.eventId;
          htmlLink = existingCalendar.htmlLink || null;
          calendar = {
            configured: true,
            created: false,
            skipped_duplicate: true,
            calendar_event_id,
            htmlLink,
            ...(existingCalendar.returnEventId ? { return_event_id: existingCalendar.returnEventId } : {}),
            ...(existingCalendar.returnHtmlLink ? { return_htmlLink: existingCalendar.returnHtmlLink } : {}),
          };
          console.log(`[CALENDAR_CREATE][SKIP_DUPLICATE] bookingId=${canonicalBookingId}`);
        } else if (!hasReturnSchedule) {
          const event = {
            summary: title,
            description: desc,
            start: { dateTime: win.start.toISOString() },
            end: { dateTime: win.end.toISOString() }
          };

          const created = await googleCreateEvent(accessToken, calendarId, event);
          calendar_event_id = created?.id || null;
          htmlLink = created?.htmlLink || null;
          calendar = { configured: true, created: true, calendar_event_id, htmlLink };
          console.log(`[CALENDAR_CREATE][DONE] bookingId=${canonicalBookingId} eventId=${calendar_event_id || ""}`);
        } else {
          // Outbound event (only outbound time window)
          const eventMain = {
            summary: title,
            description: desc + `

Retour gepland: ${whenFromPickupIsoBrussels(return_pickup_iso)}
Retour route: ${return_from || to} → ${return_to || from}`,
            start: { dateTime: win.start.toISOString() },
            end: { dateTime: win.end.toISOString() }
          };
          const createdMain = await googleCreateEvent(accessToken, calendarId, eventMain);

          // Return event
          const busyMinReturn = (duration_return_min + postBufferMin);
          const winReturn = computeWindow(return_pickup_iso, busyMinReturn);
          const titleReturn = `${title} (Retour)`;
          const bookingForCalendarReturn = {
            ...bookingForCalendar,
            bookingId: canonicalBookingId + "-R",
            from: return_from || to,
            to: return_to || from,
            stops: [],
            wait_min: 0,
            pickupStartIso: return_pickup_iso,
            return_enabled: false
          };
          const descReturn = renderCalendarDescription(bookingForCalendarReturn, legsReturn, { returnPricing: null, returnRoute: null });

          const eventReturn = {
            summary: titleReturn,
            description: descReturn,
            start: { dateTime: winReturn.start.toISOString() },
            end: { dateTime: winReturn.end.toISOString() }
          };
          const createdReturn = await googleCreateEvent(accessToken, calendarId, eventReturn);

          calendar_event_id = createdMain?.id || null;
          htmlLink = createdMain?.htmlLink || null;
          calendar = {
            configured: true,
            created: true,
            calendar_event_id,
            htmlLink,
            return_event_id: createdReturn?.id || null,
            return_htmlLink: createdReturn?.htmlLink || null
          };
          console.log(`[CALENDAR_CREATE][DONE] bookingId=${canonicalBookingId} eventId=${calendar_event_id || ""}`);
        }
      } catch (calendarErr) {
        const calendarErrorText = String(
          calendarErr?.message || calendarErr?.error || calendarErr || "",
        ).toLowerCase();
        const isCalendarIntegrationError =
          calendarErrorText.includes("google") ||
          calendarErrorText.includes("calendar") ||
          calendarErrorText.includes("oauth") ||
          calendarErrorText.includes("freebusy") ||
          calendarErrorText.includes("access token") ||
          calendarErrorText.includes("invalid_grant") ||
          calendarErrorText.includes("expired or revoked") ||
          calendarErrorText.includes("unauthorized_client") ||
          calendarErrorText.includes("invalid_client");
        if (!isCalendarIntegrationError) {
          throw calendarErr;
        }
        const isAuthError = isGoogleCalendarAuthError(calendarErr);
        calendarSyncSuppressed = true;
        calendarSyncStatus = isAuthError ? "auth_required" : "failed";
        calendarSyncErrorCode = isAuthError ? "google_auth_expired" : "calendar_sync_failed";
        calendarSyncFailedAt = new Date().toISOString();
        calendarSyncError = calendarSyncErrorCode;
        calendar = {
          ...calendar,
          configured: calendarConfigured,
          created: false,
          sync_failed: true,
          calendar_sync_status: calendarSyncStatus,
          calendarSyncStatus: calendarSyncStatus,
          calendar_sync_error_code: calendarSyncErrorCode,
          calendarSyncErrorCode: calendarSyncErrorCode,
          calendar_sync_failed_at: calendarSyncFailedAt,
          calendarSyncFailedAt: calendarSyncFailedAt,
        };
        console.log(
          `[CALENDAR_SYNC][WARN] bookingId=${canonicalBookingId} status=${calendarSyncStatus} code=${calendarSyncErrorCode} reason=${safeStr(calendarErr?.message || calendarErr, 160) || "unknown"}`,
        );
      }
    }

    if ((!calendarConfigured || calendarSyncSuppressed) && availabilityMode === "multi_vehicle" && !calendarAllocatorHandled) {
      if (shouldReserveNow) {
        const alloc = await _allocatorRequest(env, pickup_iso, {
          action: "allocate",
          booking_id: canonicalBookingId,
          pickup_ms: Date.parse(pickup_iso),
          service_min: bookingServiceMin,
          tier,
          pax,
          bags,
          tenantScope: fleetScope,
        });
        if (!alloc?.allowed) {
          return {
            ok: false,
            error: "Niet beschikbaar: geen geschikt voertuig beschikbaar.",
            availability: {
              reason: "vehicle_capacity",
              availability_mode: availabilityMode,
              allocator_reason: alloc?.reason || "vehicle_capacity_exceeded",
              suitable_vehicle_count: Number(alloc?.suitable_vehicle_count || 0),
              available_slots: Number(alloc?.available_slots || 0),
            },
          };
        }
        if (alloc?.assigned_vehicle_id) {
          resolvedAssignedVehicleId = String(alloc.assigned_vehicle_id);
          resolvedAssignedDriver = alloc?.assigned_driver || null;
        }
      } else {
        const vehicleCapacity = await _vehicleCapacityGateForRequest(env, {
          pickupMs: Date.parse(pickup_iso),
          serviceMin: bookingServiceMin,
          tier,
          pax,
          bags,
          tenantScope: fleetScope,
        });
        if (!vehicleCapacity.ok) {
          return {
            ok: false,
            error: "Niet beschikbaar: geen geschikt voertuig beschikbaar.",
            availability: {
              reason: "vehicle_capacity",
              availability_mode: availabilityMode,
              ...vehicleCapacity,
            },
          };
        }
      }
      if (!resolvedAssignedDriver && resolvedAssignedVehicleId) {
        resolvedAssignedDriver = await _driverSummaryForVehicleId(
          env,
          resolvedAssignedVehicleId,
          fleetScope,
        );
      }
    }

    if ((!calendarConfigured || calendarSyncSuppressed) && business_detected && !molliePaidConfirmed && !calendarPaymentHandled) {
      const pay = await mollieCreatePayment(
        {
          ...payload,
          __booking_id: canonicalBookingId,
          __public_booking_reference: publicBookingReference,
          bookingId: canonicalBookingId,
          tenant_id: tenantContext.tenant_id,
          tenantId: tenantContext.tenant_id,
          company_id: tenantContext.company_id,
          companyId: tenantContext.company_id,
          total_incl_vat: totalPricing.price_incl_vat,
          total_ex_vat: totalPricing.price_ex_vat,
          vat_amount: totalPricing.price_vat,
        },
        env,
        request
      );

      return {
        ok: true,
        booking_id: canonicalBookingId,
        bookingId: canonicalBookingId,
        public_booking_id: canonicalBookingId,
        public_booking_reference: publicBookingReference,
        publicBookingReference: publicBookingReference,
        booking_reference: publicBookingReference,
        bookingReference: publicBookingReference,
        public_reference: publicBookingReference,
        publicReference: publicBookingReference,
        planning_reference: planningReference,
        planningReference: planningReference,
        payment_booking_id: pay.bookingId || null,
        paymentBookingId: pay.bookingId || null,
        requiresPayment: true,
        paymentMode: "mollie",
        checkoutUrl: pay.checkoutUrl,
        statusUrl: pay.statusUrl || null,
        amount: pay.amount || null,
      };
    }

    // Build booking object used by email templates
    // bookingId already computed earlier (canonicalBookingId) + booking_uuid

    const booking = {
      bookingId: canonicalBookingId,
      booking_uuid: booking_uuid,
      createdAt: new Date().toISOString(),
      tenant_id: tenantContext.tenant_id,
      company_id: tenantContext.company_id,
      public_booking_reference: publicBookingReference,
      publicBookingReference: publicBookingReference,
      booking_reference: publicBookingReference,
      bookingReference: publicBookingReference,
      planning_reference: planningReference,
      planningReference: planningReference,
      booking_source: tenantContext.booking_source,
      entry_channel: tenantContext.entry_channel,
      source_context: tenantContext.source_context,
      tenant_resolution_mode: tenantContext.tenant_resolution_mode,
      tenant_resolved_at: tenantContext.tenant_resolved_at,

      // customer
      custName: customerContact.name,
      custPhone: customerContact.phone,
      custEmail: customerContact.email,
      customerLanguage: customerEmailLanguage.normalizedLanguage,
      customerLanguageDetected: customerEmailLanguage.detectedLanguage,

      // trip
      from,
      to,
      stops,
      wait_min,
      pax,
      bags,
      tier,
      service,
      pickupStartIso: pickup_iso,
      returnPickupIso: return_pickup_iso,

      // return
      return_enabled: ret.enabled,
      return_forced_by_wait: false,
      return_from,
      return_to,
      assigned_vehicle_id: resolvedAssignedVehicleId,
      assigned_driver: resolvedAssignedDriver,

      // business
      business_detected,
      invoice_requested,
      company_name: biz.company_name || "",
      vat_number: biz.vat_number || "",
      invoice_address: biz.invoice_address || "",

      // extras
      extra_service_key: extra.key,
      extra_service_label: extra.label,

      // price (TOTAL: main + return if enabled)
      vat_rate,
      price_ex_vat: totalPricing?.price_ex_vat,
      price_vat: totalPricing?.price_vat,
      price_incl_vat: totalPricing?.price_incl_vat,

      // parts (handig voor UI/agenda)
      price_ex_vat_main: mainPricing?.price_ex_vat,
      price_vat_main: mainPricing?.price_vat,
      price_incl_vat_main: mainPricing?.price_incl_vat,
      price_ex_vat_return: returnPricing?.price_ex_vat,
      price_vat_return: returnPricing?.price_vat,
      price_incl_vat_return: returnPricing?.price_incl_vat,

      note: mainPricing?.note || "",
      calendar_auth_source: calendarAuthSource,
      calendarAuthSource: calendarAuthSource,
      ...paymentFields,
      ...(calendarSyncStatus
        ? {
            calendar_sync_status: calendarSyncStatus,
            calendarSyncStatus: calendarSyncStatus,
            calendar_sync_error_code: calendarSyncErrorCode,
            calendarSyncErrorCode: calendarSyncErrorCode,
            calendar_sync_failed_at: calendarSyncFailedAt,
            calendarSyncFailedAt: calendarSyncFailedAt,
          }
        : {}),

      // quote meta
      distance_km,
      duration_route_min,
      legs: routeOut?.legs || [],
      return: ret.enabled ? {
        from: return_from,
        to: return_to,
        distance_km: return_distance_km,
        duration_min: return_duration_min,
        pricing: returnPricing
      } : null
    };

    // Persist canonical record (used by tracking apps)
    const record = {
      stage: "BOOKED",
      tenant_id: tenantContext.tenant_id,
      company_id: tenantContext.company_id,
      public_booking_reference: publicBookingReference,
      publicBookingReference: publicBookingReference,
      booking_reference: publicBookingReference,
      bookingReference: publicBookingReference,
      planning_reference: planningReference,
      planningReference: planningReference,
      booking_source: tenantContext.booking_source,
      entry_channel: tenantContext.entry_channel,
      source_context: tenantContext.source_context,
      tenant_resolution_mode: tenantContext.tenant_resolution_mode,
      tenant_resolved_at: tenantContext.tenant_resolved_at,
      assigned_vehicle_id: resolvedAssignedVehicleId,
      assigned_driver: resolvedAssignedDriver,
      calendar_auth_source: calendarAuthSource,
      calendarAuthSource: calendarAuthSource,
      ...paymentFields,
      ...(calendarSyncStatus
        ? {
            calendar_sync_status: calendarSyncStatus,
            calendarSyncStatus: calendarSyncStatus,
            calendar_sync_error_code: calendarSyncErrorCode,
            calendarSyncErrorCode: calendarSyncErrorCode,
            calendar_sync_failed_at: calendarSyncFailedAt,
            calendarSyncFailedAt: calendarSyncFailedAt,
          }
        : {}),
      booking: {
        bookingId: booking.bookingId,
        createdAt: booking.createdAt,
        tenant_id: tenantContext.tenant_id,
        company_id: tenantContext.company_id,
        public_booking_reference: publicBookingReference,
        publicBookingReference: publicBookingReference,
        booking_reference: publicBookingReference,
        bookingReference: publicBookingReference,
        planning_reference: planningReference,
        planningReference: planningReference,
        booking_source: tenantContext.booking_source,
        entry_channel: tenantContext.entry_channel,
        source_context: tenantContext.source_context,
        tenant_resolution_mode: tenantContext.tenant_resolution_mode,
        tenant_resolved_at: tenantContext.tenant_resolved_at,
        custName: booking.custName || "",
        custPhone: booking.custPhone || "",
        custEmail: booking.custEmail || "",
        customerLanguage: booking.customerLanguage || "nl",
        language: booking.customerLanguage || "nl",
        customer_name: booking.custName || "",
        customer_phone: booking.custPhone || "",
        customer_email: booking.custEmail || "",
        name: booking.custName || "",
        phone: booking.custPhone || "",
        email: booking.custEmail || "",
        customer: {
          name: booking.custName || "",
          phone: booking.custPhone || "",
          email: booking.custEmail || "",
        },
        pickupStartIso: booking.pickupStartIso,
        pickup_iso: booking.pickupStartIso,
        tier: booking.tier,
        pax: booking.pax,
        bags: booking.bags,
        wait_min: booking.wait_min,
        stops: Array.isArray(booking.stops) ? booking.stops : [],
        duration_route_min: booking.duration_route_min,
        return_enabled: !!booking.return_enabled,
        returnPickupIso: booking.returnPickupIso || null,
        return_duration_min: Number(
          _pick(booking, ["return", "duration_min"], 0) ?? 0,
        ),
        assigned_vehicle_id: resolvedAssignedVehicleId,
        assigned_driver: resolvedAssignedDriver,
        calendar_event_id,
        calendarEventId: calendar_event_id || null,
        return_event_id: safeStr(calendar?.return_event_id || null),
        returnEventId: safeStr(calendar?.return_event_id || null),
        htmlLink,
        return_htmlLink: safeStr(calendar?.return_htmlLink || null),
        returnHtmlLink: safeStr(calendar?.return_htmlLink || null),
        calendar_auth_source: calendarAuthSource,
        calendarAuthSource: calendarAuthSource,
        ...paymentFields,
        ...(calendarSyncStatus
          ? {
              calendar_sync_status: calendarSyncStatus,
              calendarSyncStatus: calendarSyncStatus,
              calendar_sync_error_code: calendarSyncErrorCode,
              calendarSyncErrorCode: calendarSyncErrorCode,
              calendar_sync_failed_at: calendarSyncFailedAt,
              calendarSyncFailedAt: calendarSyncFailedAt,
            }
          : {}),
      },
      quote: {
        ok: true,
        pickup_iso: booking.pickupStartIso,
        from,
        to,
        stops,
        distance_km,
        duration_min: duration_route_min,
        pricing: totalPricing,
        pricing_main: mainPricing,
        pricing_return: returnPricing,
        pricing_profile: pricingProfile,
        return: ret.enabled ? {
          enabled: true,
          from: return_from,
          to: return_to,
          distance_km: return_distance_km,
          duration_min: return_duration_min,
          pricing: returnPricing
        } : { enabled: false }
      },
      tracking_last: null,
      trip: null
    };

    try {
      await env.BOOKING_KV.put(`booking:${booking.bookingId}`, JSON.stringify(record));
    } catch (persistErr) {
      if (availabilityMode === "multi_vehicle") {
        try {
          await _allocatorRequest(env, pickup_iso, {
            action: "release",
            booking_id: canonicalBookingId,
            tenantScope: fleetScope,
          });
        } catch (_) {
          // Best-effort rollback; do not mask original persistence error.
        }
      }
      throw persistErr;
    }
    const maskedScope = _bookingIntentScopeMask(idempotencyScope);
    let idempotencyStored = false;
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        await env.BOOKING_KV.put(
          bookingIntent.key,
          booking.bookingId,
          { expirationTtl: BOOKING_INTENT_TTL_SECONDS },
        );
        idempotencyStored = true;
        console.log(
          `[BOOKING][IDEMPOTENCY][STORE] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(booking.bookingId)} attempt=${attempt}`,
        );
        break;
      } catch (idempotencyErr) {
        console.log(
          `[BOOKING][IDEMPOTENCY][STORE_WARN] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(booking.bookingId)} attempt=${attempt} reason=${safeStr(idempotencyErr?.message || idempotencyErr, 140) || "unknown"}`,
        );
      }
    }
    if (!idempotencyStored) {
      // Best-effort only; booking persistence already succeeded.
      console.log(
        `[BOOKING][IDEMPOTENCY][STORE_GIVEUP] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(booking.bookingId)}`,
      );
    }

    // Bridge website-created bookings into tracking index so they appear in /track/bookings.
    // Best-effort only: booking confirmation flow must never fail because tracking KV is missing.
    await bridgeBookingIntoTrackingIndex(env, booking);

    // Send emails (best-effort)
    const email = await sendBookingEmails({ env, booking });

    // Invoice (best-effort)
    let invoice = null;
    if (invoice_requested) {
      invoice = await generateAndSendInvoice({ env, booking: {
        // bookkeeping / numbering
        pickupStartIso: booking.pickupStartIso,
        tripDate: date,
        pickupTime: time,
        bookingPublicId: booking.bookingId,
        bookingId: booking.booking_uuid,
        tenant_id: safeStr(booking.tenant_id || booking.tenantId || tenantContext?.tenant_id, 120),
        company_id: safeStr(booking.company_id || booking.companyId || tenantContext?.company_id, 120),

        // route
        from: booking.from,
        to: booking.to,
        stops: Array.isArray(booking.stops) ? booking.stops : [],
        returnTrip: !!booking.return_enabled,
        routeKm: (typeof booking.distance_km === "number") ? booking.distance_km : null,
        routeMinutes: (typeof booking.duration_route_min === "number") ? booking.duration_route_min : null,

        // service
        tier: booking.tier,
        service: booking.service,
        pax: booking.pax,
        bags: booking.bags,
        waitMinutes: booking.wait_min || 0,

        // customer
        customerName: booking.custName,
        customerEmail: booking.custEmail,
        customerPhone: booking.custPhone,
        customerVat: booking.vat_number || "",
        customerCompany: booking.company_name || "",
        invoiceAddress: booking.invoice_address || "",

        // totals (numbers; formatter happens in invoice renderer)
        vat_rate: booking.vat_rate,
        subtotalEx: booking.price_ex_vat,
        vatAmount: booking.price_vat,
        total: booking.price_incl_vat,

        // optional split for display
        priceMainIncl: booking.price_incl_vat_main,
        priceReturnIncl: booking.price_incl_vat_return
      } });    }

    
    // Push notification (best-effort)
    const push = await sendPushbulletNote(env, {
      title: `Nieuwe booking ${booking.bookingId} — ${date} ${time}`,
      body: [
        `Service: ${humanServiceLabel(service)} • Tier: ${humanTierLabel(tier)}`,
        `Van: ${from}`,
        `Naar: ${to}`,
        (ret.enabled ? `Retour: JA (${return_from} → ${return_to})` : `Retour: nee`),
        (wait_min ? `Wacht: ${wait_min} min` : ``),
        (extra?.label ? `Extra: ${extra.label}` : ``),
        `Totaal: €${money2(booking.price_incl_vat)} incl btw`,
        (ret.enabled ? `Heen: €${money2(booking.price_incl_vat_main)} • Retour: €${money2(returnPricing?.price_incl_vat)}` : `Heen: €${money2(booking.price_incl_vat_main)}`),
        (invoice_requested ? (invoice?.ok ? `Factuur: verzonden (${invoice.invoiceNumber})` : `Factuur: FOUT (${(invoice?.error || "unknown").slice(0,120)})`) : ``),
        (htmlLink ? `Agenda: ${htmlLink}` : ``)
      ].filter(Boolean).join("\n")
    });

return {
      ok: true,
      bookingId: booking.bookingId,
      booking_id: booking.bookingId,
      public_booking_id: booking.bookingId,
      public_booking_reference: publicBookingReference,
      publicBookingReference: publicBookingReference,
      booking_reference: publicBookingReference,
      bookingReference: publicBookingReference,
      public_reference: publicBookingReference,
      publicReference: publicBookingReference,
      planning_reference: planningReference,
      planningReference: planningReference,
      booking_uuid: booking.booking_uuid,
      push,

      calendar_event_id,
      htmlLink,
      calendar,
      calendar_auth_source: calendarAuthSource,
      calendarAuthSource: calendarAuthSource,
      ...(calendarSyncStatus
        ? {
            calendar_sync_status: calendarSyncStatus,
            calendarSyncStatus: calendarSyncStatus,
            calendar_sync_error_code: calendarSyncErrorCode,
            calendarSyncErrorCode: calendarSyncErrorCode,
            calendar_sync_failed_at: calendarSyncFailedAt,
            calendarSyncFailedAt: calendarSyncFailedAt,
            calendar_sync_error: calendarSyncError,
            calendarSyncError: calendarSyncError,
          }
        : {}),
      email,
      invoice
    };
  } catch (e) {
    return { ok: false, error: String(e?.message || e) };
  }
}

async function bridgeBookingIntoTrackingIndex(env, booking) {
  try {
    if (!env?.FLUXIDI_TRACKING) return;
    if (!booking?.bookingId) return;

    const bookingId = safeStr(booking.bookingId);
    if (!bookingId) return;

    const createdAt = safeStr(booking.createdAt) || new Date().toISOString();
    const pickup = safeStr(booking.from) || null;
    const dropoff = safeStr(booking.to) || null;

    // Create a placeholder session so listing/details work before /track/session/start.
    const bootstrapSessionId = `s_bootstrap_${bookingId}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
    const session = {
      session_id: bootstrapSessionId,
      booking_id: bookingId,
      pickup,
      dropoff,
      status: "pending",
      created_at: createdAt,
      last_ping_at: null,
      points: [],
      public_token: null
    };

    await env.FLUXIDI_TRACKING.put(
      `session:${bootstrapSessionId}`,
      JSON.stringify(session),
      { expirationTtl: 60 * 60 * 24 * 30 }
    );

    const bookingMap = {
      session_id: bootstrapSessionId,
      created_at: createdAt,
      pickup,
      dropoff,
      public_token: null
    };
    await env.FLUXIDI_TRACKING.put(
      `booking:${bookingId}:session`,
      JSON.stringify(bookingMap),
      { expirationTtl: 60 * 60 * 24 * 30 }
    );

    const rawIdx = await env.FLUXIDI_TRACKING.get("booking_index");
    let idx = [];
    try { idx = JSON.parse(rawIdx || "[]"); } catch (_) { idx = []; }
    if (!Array.isArray(idx)) idx = [];

    const next = [bookingId, ...idx.filter((x) => x !== bookingId)].slice(0, 200);
    await env.FLUXIDI_TRACKING.put(
      "booking_index",
      JSON.stringify(next),
      { expirationTtl: 60 * 60 * 24 * 30 }
    );
  } catch (_) {
    // Best-effort bridge: intentionally swallow errors.
  }
}

function brusselsIsoFromDateTime(dateStr, timeStr) {
  try {
    const d = safeStr(dateStr);
    const t = safeStr(timeStr) || "00:00";

    // dd/mm/yyyy
    const mEU = d.match(/^([0-9]{2})\/([0-9]{2})\/([0-9]{4})$/);
    if (mEU) {
      const dd = Number(mEU[1]);
      const mm = Number(mEU[2]);
      const yyyy = Number(mEU[3]);
      const [hh, mi] = t.split(":").map(Number);
      const dt = new Date(yyyy, mm - 1, dd, hh || 0, mi || 0, 0, 0);
      // Treat as Brussels local time.
      // We store ISO in UTC to avoid ambiguity.
      return new Date(dt.getTime() - tzOffsetMsForBrussels(dt)).toISOString();
    }

    // yyyy-mm-dd
    const mISO = d.match(/^([0-9]{4})-([0-9]{2})-([0-9]{2})$/);
    if (mISO) {
      const yyyy = Number(mISO[1]);
      const mm = Number(mISO[2]);
      const dd = Number(mISO[3]);
      const [hh, mi] = t.split(":").map(Number);
      const dt = new Date(yyyy, mm - 1, dd, hh || 0, mi || 0, 0, 0);
      return new Date(dt.getTime() - tzOffsetMsForBrussels(dt)).toISOString();
    }

    return "";
  } catch {
    return "";
  }
}

// Returns offset in ms between Brussels local time and UTC for a given local Date.
function tzOffsetMsForBrussels(localDate) {
  try {
    const fmt = new Intl.DateTimeFormat("en-US", { timeZone: "Europe/Brussels", hour12: false,
      year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit" });
    const parts = fmt.formatToParts(localDate).reduce((acc, p) => (acc[p.type] = p.value, acc), {});
    const asIfUTC = Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day), Number(parts.hour), Number(parts.minute), Number(parts.second));
    return asIfUTC - localDate.getTime();
  } catch {
    return 0;
  }
}

function renderCalendarDescription(booking, legs, { returnPricing, returnRoute } = {}) {
  const lines = [];
  if (booking?.bookingId) lines.push(`Booking ID: ${booking.bookingId}`);
  lines.push(`When: ${whenFromPickupIsoBrussels(booking.pickupStartIso)}`);
  lines.push(`Service: ${humanServiceLabel(booking.service)}`);
  lines.push(`Tier: ${String(booking.tier || "").toUpperCase()}`);
  lines.push(`From: ${booking.from}`);
  lines.push(`To: ${booking.to}`);
  if (Array.isArray(booking.stops) && booking.stops.length) {
    lines.push(`Stops: ${booking.stops.join(" | ")}`);
  }
  lines.push(`Pax: ${booking.pax} | Bags: ${booking.bags}`);
  lines.push(`Wait: ${booking.wait_min || 0} min`);
  if (booking.extra_service_label) lines.push(`Extra: ${booking.extra_service_label}`);
  if (booking.business_detected) {
    lines.push(`Business: YES | Company: ${booking.company_name || "-"} | VAT: ${booking.vat_number || "-"} | Invoice: ${booking.invoice_requested ? "YES" : "NO"}`);
  }
  lines.push("");

  // Route segments (heen + eventuele retour)
  if (Array.isArray(legs) && legs.length) {
    lines.push("Route segments:");
    for (const l of legs) {
      lines.push(`${l.index}. ${l.from} → ${l.to}: ${l.distance_km} km, ${l.duration_min} min`);
    }
    lines.push("");
  } else if (booking.return_enabled && returnRoute?.from && returnRoute?.to) {
    // Fallback: show return summary if we don't have leg details
    lines.push(`Retour route: ${returnRoute.from} → ${returnRoute.to}: ${returnRoute.distance_km} km, ${returnRoute.duration_min} min`);
    lines.push("");
  }

  // Prices (always total first)
  const totalIncl = money2(booking.price_incl_vat);
  lines.push(`Totaal: €${totalIncl} incl btw`);

  // Detail legs
  if (booking.price_incl_vat_main != null) {
    lines.push(`Prijs (heen): €${money2(booking.price_incl_vat_main)} incl btw`);
  }
  if (booking.return_enabled && returnPricing?.price_incl_vat != null) {
    lines.push(`Prijs (retour): €${money2(returnPricing.price_incl_vat)} incl btw`);
  }

  return lines.join("\n");
}

/* ===================== HELPERS ===================== */

const BASE_ADDRESS_FIXED = "Koekamerstraat 48, Maarkedal";
const BUFFER_PLUS_MIN = 5;

function round1(n) { return Math.round(n * 10) / 10; }

function clampNumber(v, fallback, min, max) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, n));
}

function clampInt(v, fallback, max) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  const i = Math.trunc(n);
  return Math.max(fallback, Math.min(max, i));
}

function normalizeTier(t) {
  const s = String(t || "").trim().toLowerCase();
  if (s === "private") return "private";
  if (s === "premium") return "premium";
  return "comfort";
}

function normalizeService(svc) {
  const s = String(svc || "").trim().toLowerCase();
  if (s === "airport") return "airport";
  if (s === "business") return "business";
  if (s === "event") return "event";
  if (s === "special" || s === "speciale_gelegenheid") return "event";
  if (s === "wedding") return "event";
  if (s === "hourly") return "hourly";
  if (s === "care") return "care";
  if (s === "courier") return "courier";
  return "passenger";
}

/* ========= ✅ EXTRA SERVICE (Premium add-on) ========= */

function normalizeExtraService(body, tier) {
  // Extra service is only relevant for PREMIUM.
  // We accept multiple possible keys so the UI can evolve without breaking emails.
  const t = normalizeTier(tier);

  // Hard-enforce: only PREMIUM can have an extra service
  if (t !== 'premium') return { key: 'none', label: '' };

  const raw =
    body?.extra_service_label ??
    body?.extraServiceLabel ??
    body?.extra_service_key ??
    body?.extraServiceKey ??
    body?.extra_service ??
    body?.extraService ??
    body?.extra ??
    body?.addon ??
    body?.add_on ??
    body?.premium_extra ??
    body?.premiumExtra ??
    body?.extra_option ??
    body?.extraOption ??
    body?.extraservice ??
    body?.extras?.service ??
    body?.extras?.extra_service ??
    body?.extras?.extraService ??
    body?.extras?.addon ??
    body?.extras?.extra_service_key ??
    body?.extras?.extraServiceKey ??
    body?.extras?.extra_service_label;

  const s = String(raw == null ? "" : raw).trim();
  if (!s) return { key: "none", label: "" };

  // UI might send a human label already (e.g. "Drankservice (water/fris ...)"),
  // or a stable key ("drinks", "worktable"). We normalize both.
  const low = s.toLowerCase();
  if (low === "none" || low === "geen" || low.includes("geen extra")) return { key: "none", label: "" };

  if (low.includes("drank") || low.includes("drink") || low.includes("water") || low.includes("fris")) {
    return {
      key: "drinks",
      label: "🍾 Drankservice (water/fris – alcoholisch op aanvraag)"
    };
  }

  if (low.includes("werk") || low.includes("laptop") || low.includes("tafel") || low.includes("worktable")) {
    return {
      key: "worktable",
      label: "💻 Werktafel (laptop/werkmodus)"
    };
  }

  // Fallback: keep whatever came in (but we still hide it if not PREMIUM)
  return { key: "custom", label: s };
}

function normalizeReturnEnabled(body, wait_min) {
  // Return must be explicitly selected by the customer.
  // Waiting time can mean "wait and continue elsewhere" — so we never auto-force return.
  const explicit = !!(body?.return_enabled ?? body?.return ?? body?.isReturn ?? body?.retour ?? body?.retour_enabled);
  const forced = false;
  const enabled = explicit;
  return { explicit, forced, enabled };
}

function humanServiceLabel(s) {
  const map = {
    airport: "Luchthavenvervoer",
    business: "Zakelijk vervoer",
    event: "Speciale gelegenheid",
    hourly: "Uurservice",
    care: "Zorgvervoer",
    courier: "Spoedkoerier",
    passenger: "Personenvervoer"
  };
  return map[s] || s || "-";
}

function humanTierLabel(tier) {
  const t = String(tier || "").toLowerCase();
  if (t === "comfort") return "Comfort";
  if (t === "private") return "Private";
  if (t === "premium") return "Premium";
  return String(tier || "").toUpperCase() || "—";
}


/* ========= ✅ BUSINESS NORMALIZATION ========= */

function normalizeVatNumber(v) {
  let s = String(v || "").trim().toUpperCase();
  if (!s) return "";
  s = s.replace(/[.\s]/g, "");
  if (/^\d{9,12}$/.test(s)) s = "BE" + s;
  return s;
}

function normalizeBusiness(body) {
  const b = body?.business || {};
  const company_name = safeStr(b?.company_name || body?.company_name || body?.company || body?.companyName);

  const vat_number_raw =
    (b?.vat_number ?? body?.vat_number ?? body?.vat ?? body?.btw ?? body?.btw_number ?? body?.btw_nummer);
  const vat_number = normalizeVatNumber(vat_number_raw);

  const invoice_requested = !!(b?.invoice_requested ?? body?.invoice_requested ?? body?.invoice ?? body?.factuur);

  // Optional invoice/billing address (shown on PDF if provided)
  const invoice_address =
    safeStr(b?.invoice_address || b?.billing_address || body?.invoice_address || body?.billing_address || body?.factuuradres || body?.facturatieadres || body?.invoiceAddress);

  return { company_name, vat_number, invoice_requested, invoice_address };
}

function normalizeCustomerContact(payload) {
  const customer =
    payload?.customer && typeof payload.customer === "object"
      ? payload.customer
      : {};
  const name = safeStr(
    customer?.name ||
    customer?.full_name ||
    payload?.name ||
    payload?.customer_name ||
    payload?.custName ||
    payload?.customerName
  );
  const phone = safeStr(
    customer?.phone ||
    payload?.phone ||
    payload?.customer_phone ||
    payload?.custPhone ||
    payload?.customerPhone
  );
  const email = safeStr(
    customer?.email ||
    payload?.email ||
    payload?.customer_email ||
    payload?.custEmail ||
    payload?.customerEmail
  );
  return { name, phone, email };
}

const CUSTOMER_EMAIL_I18N = {
  nl: {
    subjectBusiness: "Zakelijke rit aanvraag",
    subjectPrivate: "Bevestiging van je Fluxidi rit",
    headingBusiness: "Zakelijke booking",
    headingPrivate: "Bevestiging van je Fluxidi rit",
    greeting: (name) => `Dag ${name},`,
    introBusiness: "we hebben je zakelijke booking goed ontvangen.",
    introPrivate: "je rit is bevestigd.",
    bookingId: "Booking ID",
    pickup: "Ophaalmoment",
    from: "Vertrek",
    destination: "Bestemming",
    route: "Route",
    choices: "Jouw keuzes",
    service: "Service",
    tier: "Ritniveau",
    returnTrip: "Retourrit",
    returnTime: "Retour tijd",
    stops: "Tussenstops",
    passengers: "Aantal reizigers",
    bags: "Koffers",
    waitingTime: "Wachttijd",
    extraService: "Extra service",
    price: "Prijs",
    total: "Totaal",
    exclVat: "Excl. btw",
    vat: "BTW",
    rate: "tarief",
    inclVat: "incl. btw",
    businessDetails: "Zakelijke gegevens",
    company: "Bedrijf",
    invoice: "Factuur",
    invoiceYes: "JA (PDF in bijlage)",
    invoiceNo: "NEE",
    yes: "JA",
    no: "NEE",
    bagFee: "koffer",
    contact: "Heb je extra bagage of speciale wensen? Antwoord op deze mail of contacteer ons.",
    footer: "Fluxidi Taxi - premium service, transparante tarieven.",
    services: {
      airport: "Luchthavenvervoer",
      business: "Zakelijk vervoer",
      event: "Speciale gelegenheid",
      hourly: "Uurservice",
      care: "Zorgvervoer",
      courier: "Spoedkoerier",
      passenger: "Personenvervoer",
    },
  },
  en: {
    subjectBusiness: "Business ride request",
    subjectPrivate: "Your Fluxidi ride confirmation",
    headingBusiness: "Business booking",
    headingPrivate: "Your Fluxidi ride is confirmed",
    greeting: (name) => `Hello ${name},`,
    introBusiness: "we have received your business booking.",
    introPrivate: "your ride is confirmed.",
    bookingId: "Booking ID",
    pickup: "Pickup time",
    from: "Pickup",
    destination: "Destination",
    route: "Route",
    choices: "Your choices",
    service: "Service",
    tier: "Ride level",
    returnTrip: "Return trip",
    returnTime: "Return time",
    stops: "Stops",
    passengers: "Passengers",
    bags: "Bags",
    waitingTime: "Waiting time",
    extraService: "Extra service",
    price: "Price",
    total: "Total",
    exclVat: "Excl. VAT",
    vat: "VAT",
    rate: "rate",
    inclVat: "incl. VAT",
    businessDetails: "Business details",
    company: "Company",
    invoice: "Invoice",
    invoiceYes: "YES (PDF attached)",
    invoiceNo: "NO",
    yes: "YES",
    no: "NO",
    bagFee: "bag",
    contact: "Do you have extra luggage or special requests? Reply to this email or contact us.",
    footer: "Fluxidi Taxi - premium service, transparent rates.",
    services: {
      airport: "Airport transfer",
      business: "Business transport",
      event: "Special occasion",
      hourly: "Hourly service",
      care: "Care transport",
      courier: "Express courier",
      passenger: "Passenger transport",
    },
  },
  fr: {
    subjectBusiness: "Demande de trajet professionnel",
    subjectPrivate: "Confirmation de votre trajet Fluxidi",
    headingBusiness: "Réservation professionnelle",
    headingPrivate: "Votre trajet Fluxidi est confirmé",
    greeting: (name) => `Bonjour ${name},`,
    introBusiness: "nous avons bien reçu votre réservation professionnelle.",
    introPrivate: "votre trajet est confirmé.",
    bookingId: "Référence de réservation",
    pickup: "Heure de prise en charge",
    from: "Départ",
    destination: "Destination",
    route: "Itinéraire",
    choices: "Vos choix",
    service: "Service",
    tier: "Niveau de trajet",
    returnTrip: "Trajet retour",
    returnTime: "Heure du retour",
    stops: "Arrêts intermédiaires",
    passengers: "Passagers",
    bags: "Bagages",
    waitingTime: "Temps d'attente",
    extraService: "Service supplémentaire",
    price: "Prix",
    total: "Total",
    exclVat: "Hors TVA",
    vat: "TVA",
    rate: "taux",
    inclVat: "TVA incluse",
    businessDetails: "Données professionnelles",
    company: "Entreprise",
    invoice: "Facture",
    invoiceYes: "OUI (PDF en pièce jointe)",
    invoiceNo: "NON",
    yes: "OUI",
    no: "NON",
    bagFee: "bagage",
    contact: "Vous avez des bagages supplémentaires ou une demande particulière ? Répondez à cet e-mail ou contactez-nous.",
    footer: "Fluxidi Taxi - service premium, tarifs transparents.",
    services: {
      airport: "Transfert aéroport",
      business: "Transport professionnel",
      event: "Occasion spéciale",
      hourly: "Service à l'heure",
      care: "Transport médicalisé",
      courier: "Coursier express",
      passenger: "Transport de personnes",
    },
  },
  es: {
    subjectBusiness: "Solicitud de viaje profesional",
    subjectPrivate: "Confirmación de tu viaje Fluxidi",
    headingBusiness: "Reserva profesional",
    headingPrivate: "Tu viaje Fluxidi está confirmado",
    greeting: (name) => `Hola ${name},`,
    introBusiness: "hemos recibido tu reserva profesional.",
    introPrivate: "tu viaje está confirmado.",
    bookingId: "Referencia de reserva",
    pickup: "Hora de recogida",
    from: "Recogida",
    destination: "Destino",
    route: "Ruta",
    choices: "Tus opciones",
    service: "Servicio",
    tier: "Nivel del viaje",
    returnTrip: "Viaje de vuelta",
    returnTime: "Hora de vuelta",
    stops: "Paradas intermedias",
    passengers: "Pasajeros",
    bags: "Equipaje",
    waitingTime: "Tiempo de espera",
    extraService: "Servicio adicional",
    price: "Precio",
    total: "Total",
    exclVat: "Sin IVA",
    vat: "IVA",
    rate: "tipo",
    inclVat: "IVA incluido",
    businessDetails: "Datos profesionales",
    company: "Empresa",
    invoice: "Factura",
    invoiceYes: "SÍ (PDF adjunto)",
    invoiceNo: "NO",
    yes: "SÍ",
    no: "NO",
    bagFee: "maleta",
    contact: "¿Tienes equipaje adicional o alguna petición especial? Responde a este correo o contáctanos.",
    footer: "Fluxidi Taxi - servicio premium, tarifas transparentes.",
    services: {
      airport: "Traslado al aeropuerto",
      business: "Transporte profesional",
      event: "Ocasión especial",
      hourly: "Servicio por horas",
      care: "Transporte asistencial",
      courier: "Mensajería urgente",
      passenger: "Transporte de pasajeros",
    },
  },
};

function normalizeCustomerEmailLanguage(payload) {
  const raw = safeStr(
    payload?.language ||
    payload?.lang ||
    payload?.locale ||
    payload?.customerLanguage ||
    payload?.appLanguage
  );
  const normalized = raw.toLowerCase().replace("_", "-").split("-")[0];
  const supported = ["nl", "en", "fr", "es"];
  const lang = supported.includes(normalized) ? normalized : "nl";
  return {
    detectedLanguage: raw || null,
    normalizedLanguage: lang,
    fallbackUsed: lang !== normalized,
  };
}

function customerEmailText(lang) {
  return CUSTOMER_EMAIL_I18N[lang] || CUSTOMER_EMAIL_I18N.nl;
}

function customerEmailServiceLabel(service, lang) {
  const t = customerEmailText(lang);
  return t.services?.[service] || humanServiceLabel(service);
}

function customerEmailTierLabel(tier) {
  return humanTierLabel(tier);
}

/* ========= date/time helper ========= */

function normalizeWhen(dateStr, timeStr) {
  const d = String(dateStr || "").trim();
  const t = String(timeStr || "").trim() || "12:00";

  const iso = d.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (iso) return `${iso[3]}/${iso[2]}/${iso[1]} ${t}`;

  const eu = d.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (eu) return `${d} ${t}`;

  const parsed = new Date(d);
  if (!isNaN(parsed.getTime())) {
    const dd = String(parsed.getDate()).padStart(2, "0");
    const mm = String(parsed.getMonth() + 1).padStart(2, "0");
    const yyyy = String(parsed.getFullYear());
    return `${dd}/${mm}/${yyyy} ${t}`;
  }
  return `${d} ${t}`;
}

async function geocode(query, token) {
  if (!token) throw new Error("Missing MAPBOX_TOKEN in Worker secrets");

  const u =
    "https://api.mapbox.com/geocoding/v5/mapbox.places/" +
    encodeURIComponent(query) +
    ".json?limit=1&country=BE&language=nl&access_token=" +
    token;

  const r = await fetch(u);
  const j = await r.json();
  if (!j.features?.length) throw new Error("Geocode failed");
  const [lng, lat] = j.features[0].center;
  return { lat, lng };
}

async function geocodeText(query, token) { return geocode(query, token); }

async function directionsMulti(coords, token) {
  if (!token) throw new Error("Missing MAPBOX_TOKEN in Worker secrets");
  if (!coords || coords.length < 2) throw new Error("Need at least 2 coordinates for directions");

  const path = coords.map(c => `${c.lng},${c.lat}`).join(";");
  const u = `https://api.mapbox.com/directions/v5/mapbox/driving/${path}?overview=false&access_token=${token}`;

  const r = await fetch(u);
  const j = await r.json();
  if (!j.routes?.length) throw new Error("Directions failed");
  return j.routes[0];
}

function normalizeStops(body) {
  const out = [];

  const arr =
    body?.stop_points ??
    body?.stops_addresses ??
    body?.stop_addresses ??
    body?.stops ??
    body?.waypoints ??
    null;

  if (Array.isArray(arr)) {
    arr.forEach(x => {
      const s = String(x || "").trim();
      if (s) out.push(s);
    });
  }

  for (let i = 1; i <= 6; i++) {
    const v = body?.[`stop${i}`] ?? body?.[`stop_${i}`] ?? null;
    if (v != null) {
      const s = String(v || "").trim();
      if (s && !out.includes(s)) out.push(s);
    }
  }

  return out.slice(0, 6);
}

async function routeFromTextsWithStopsDetailed({ fromText, toText, stopsTexts, token }) {
  const from = await geocode(fromText, token);
  const to = await geocode(toText, token);

  const stops = Array.isArray(stopsTexts) ? stopsTexts : [];
  const stopCoords = [];
  const stopNamesOk = [];

  for (const s of stops) {
    try {
      stopCoords.push(await geocode(s, token));
      stopNamesOk.push(String(s).trim());
    } catch {
      // ignore invalid stop
    }
  }

  const waypointNames = [String(fromText || "").trim(), ...stopNamesOk, String(toText || "").trim()].filter(Boolean);
  const coords = [from, ...stopCoords, to];

  const route = await directionsMulti(coords, token);

  const legs = Array.isArray(route.legs) ? route.legs : [];
  const legsOut = legs.map((leg, idx) => {
    const fromName = waypointNames[idx] || `Stop ${idx}`;
    const toName = waypointNames[idx + 1] || `Stop ${idx + 1}`;
    return {
      index: idx + 1,
      from: fromName,
      to: toName,
      distance_km: round1((Number(leg.distance || 0) / 1000)),
      duration_min: Math.round((Number(leg.duration || 0) / 60))
    };
  });

  return { route, legs: legsOut, waypointNames };
}

/* ===================== PRICING ===================== */

const TENANT_PRICING_PROFILE_KEY = "tenant:pricing:v1";
const DEFAULT_TENANT_PRICING_PROFILE = {
  base_fare: 3.0,
  price_per_km: 1.5,
  price_per_minute: 0.2,
  minimum_fare: 3.0,
  wait_per_minute: 40.0 / 60.0,
  vat_rate: 0.06,
  vat_mode: "excl",
  bag_fee_each: 5.0,
  stop_fee_each: 7.5,
  tier_fee_comfort: 0.0,
  tier_fee_private: 5.0,
  tier_fee_premium: 10.0,
  night_surcharge_rate: 0.12,
  weekend_surcharge_rate: 0.08,
  surcharge_cap_rate: 0.20,
  return_enabled: true,
  return_fee: 0.0,
  fuel_surcharge: 0.0,
};

function _numOr(v, fb) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fb;
}

function _normalizeTenantPricingProfile(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  return {
    base_fare: Math.max(0, _numOr(src.base_fare, DEFAULT_TENANT_PRICING_PROFILE.base_fare)),
    price_per_km: Math.max(0, _numOr(src.price_per_km, DEFAULT_TENANT_PRICING_PROFILE.price_per_km)),
    price_per_minute: Math.max(0, _numOr(src.price_per_minute, DEFAULT_TENANT_PRICING_PROFILE.price_per_minute)),
    minimum_fare: Math.max(0, _numOr(src.minimum_fare, DEFAULT_TENANT_PRICING_PROFILE.minimum_fare)),
    wait_per_minute: Math.max(0, _numOr(src.wait_per_minute, DEFAULT_TENANT_PRICING_PROFILE.wait_per_minute)),
    vat_rate: Math.max(0, Math.min(1, _numOr(src.vat_rate, DEFAULT_TENANT_PRICING_PROFILE.vat_rate))),
    vat_mode: String(src.vat_mode || DEFAULT_TENANT_PRICING_PROFILE.vat_mode).trim().toLowerCase() === "incl"
      ? "incl"
      : "excl",
    bag_fee_each: Math.max(0, _numOr(src.bag_fee_each, DEFAULT_TENANT_PRICING_PROFILE.bag_fee_each)),
    stop_fee_each: Math.max(0, _numOr(src.stop_fee_each, DEFAULT_TENANT_PRICING_PROFILE.stop_fee_each)),
    tier_fee_comfort: Math.max(0, _numOr(src.tier_fee_comfort, DEFAULT_TENANT_PRICING_PROFILE.tier_fee_comfort)),
    tier_fee_private: Math.max(0, _numOr(src.tier_fee_private, DEFAULT_TENANT_PRICING_PROFILE.tier_fee_private)),
    tier_fee_premium: Math.max(0, _numOr(src.tier_fee_premium, DEFAULT_TENANT_PRICING_PROFILE.tier_fee_premium)),
    night_surcharge_rate: Math.max(0, _numOr(src.night_surcharge_rate, DEFAULT_TENANT_PRICING_PROFILE.night_surcharge_rate)),
    weekend_surcharge_rate: Math.max(0, _numOr(src.weekend_surcharge_rate, DEFAULT_TENANT_PRICING_PROFILE.weekend_surcharge_rate)),
    surcharge_cap_rate: Math.max(0, _numOr(src.surcharge_cap_rate, DEFAULT_TENANT_PRICING_PROFILE.surcharge_cap_rate)),
    return_enabled: src.return_enabled == null
      ? !!DEFAULT_TENANT_PRICING_PROFILE.return_enabled
      : !!src.return_enabled,
    return_fee: Math.max(0, _numOr(src.return_fee, DEFAULT_TENANT_PRICING_PROFILE.return_fee)),
    fuel_surcharge: Math.max(0, _numOr(src.fuel_surcharge, DEFAULT_TENANT_PRICING_PROFILE.fuel_surcharge)),
  };
}

async function _loadTenantPricingProfile(
  env,
  scope = null,
  { allowTenantLegacyFallback = true } = {},
) {
  if (!env?.BOOKING_KV) return { ...DEFAULT_TENANT_PRICING_PROFILE };
  const scopedKeys = buildScopedSettingsKeys(scope);
  let raw = null;
  if (scopedKeys) {
    raw = await env.BOOKING_KV.get(scopedKeys.pricingProfileKey, { type: "json" });
  }
  if (!raw && allowTenantLegacyFallback) {
    raw = await env.BOOKING_KV.get(TENANT_PRICING_PROFILE_KEY, { type: "json" });
  }
  const incoming = raw && typeof raw === "object"
    ? (raw.pricing_profile && typeof raw.pricing_profile === "object" ? raw.pricing_profile : raw)
    : null;
  if (!incoming) return { ...DEFAULT_TENANT_PRICING_PROFILE };
  return _normalizeTenantPricingProfile(incoming);
}

async function _saveTenantPricingProfile(
  env,
  incoming,
  scope = null,
  { allowTenantLegacyWrite = true } = {},
) {
  if (!env?.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const normalized = _normalizeTenantPricingProfile(incoming);
  const scopedKeys = buildScopedSettingsKeys(scope);
  const targetKey = scopedKeys?.pricingProfileKey ||
    (allowTenantLegacyWrite ? TENANT_PRICING_PROFILE_KEY : "");
  if (!targetKey) throw new Error("missing_tenant_scope");
  await env.BOOKING_KV.put(targetKey, JSON.stringify({
    version: 1,
    updated_at: new Date().toISOString(),
    pricing_profile: normalized,
  }));
  return normalized;
}

function tierFeeEx(tier) {
  const t = String(tier || "comfort").toLowerCase();
  if (t === "private") return 5.0;
  if (t === "premium") return 10.0;
  return 0.0;
}

function tierFeeFromProfileEx(tier, profile) {
  const t = String(tier || "comfort").toLowerCase();
  if (t === "private") return Number(profile?.tier_fee_private || 0);
  if (t === "premium") return Number(profile?.tier_fee_premium || 0);
  return Number(profile?.tier_fee_comfort || 0);
}

function calcPrice({
  distance_km,
  duration_min,
  tier,
  service,
  when,
  time_str,
  pax,
  bags,
  vat_rate,
  stop_count = 0,
  wait_min = 0,
  pricing_profile = DEFAULT_TENANT_PRICING_PROFILE,
  apply_return_fee = false,
}) {
  const profile = _normalizeTenantPricingProfile(pricing_profile);
  const startFee = profile.base_fare;
  const perKm = profile.price_per_km;
  const perMin = profile.price_per_minute;

  const bagFeeEach = profile.bag_fee_each;
  const bagsFee = Math.max(0, (bags || 0)) * bagFeeEach;

  const stopFeeEach = profile.stop_fee_each;
  const stopsFee = Math.max(0, stop_count) * stopFeeEach;

  const waitPerMin = profile.wait_per_minute;
  const waitingFee = Math.max(0, wait_min) * waitPerMin;

  const tFee = tierFeeFromProfileEx(tier, profile);

  const d = parseWhen(when, time_str);
  const isNight = d.hour >= 22 || d.hour < 6;
  const isWeekend = d.day === 0 || d.day === 6;

  let surchargeRate = 0;
  if (isNight) surchargeRate += profile.night_surcharge_rate;
  if (isWeekend) surchargeRate += profile.weekend_surcharge_rate;
  const surchargeCap = profile.surcharge_cap_rate;
  if (surchargeRate > surchargeCap) surchargeRate = surchargeCap;

  const timeCostEx = duration_min * perMin;
  const distanceCostEx = distance_km * perKm;
  const baseDriveEx = startFee + distanceCostEx + timeCostEx;
  const returnFee = apply_return_fee ? profile.return_fee : 0;
  const fuelSurcharge = profile.fuel_surcharge;

  const surchargeBaseEx = baseDriveEx + stopsFee + waitingFee;
  const surchargeAmount = surchargeBaseEx * surchargeRate;

  const computedEx = (baseDriveEx + stopsFee + waitingFee + surchargeAmount) + bagsFee + tFee + returnFee + fuelSurcharge;
  const price_ex = Math.max(profile.minimum_fare, computedEx);

  const rate = Math.max(
    0,
    Math.min(
      1,
      Number.isFinite(Number(profile.vat_rate))
        ? Number(profile.vat_rate)
        : (Number.isFinite(Number(vat_rate)) ? Number(vat_rate) : 0),
    ),
  );
  const vatMode = profile.vat_mode === "incl" ? "incl" : "excl";
  const price_ex_raw = vatMode === "incl" ? (price_ex / (1 + rate)) : price_ex;
  const price_vat_raw = vatMode === "incl" ? (price_ex - price_ex_raw) : (price_ex * rate);
  const price_incl_raw = vatMode === "incl" ? price_ex : (price_ex + price_vat_raw);
  const price_ex_out = Math.max(profile.minimum_fare, price_ex_raw);
  const price_vat = vatMode === "incl" ? (price_ex_out * rate) : price_vat_raw;
  const price_incl = vatMode === "incl" ? (price_ex_out + price_vat) : (price_ex_out + price_vat);

  return {
    price_ex_vat: to2(price_ex_out),
    price_vat: to2(price_vat),
    price_incl_vat: to2(price_incl),
    note: buildNote({ isNight, isWeekend, surchargeRate, tier, pax, bags, stop_count, wait_min, profile }),
    breakdown: {
      start_fee_ex: to2(startFee),
      per_km_ex: to2(perKm),
      per_km_total_ex: to2(distanceCostEx),
      distance_cost_ex: to2(distanceCostEx),
      per_min_ex: to2(perMin),
      per_min_total_ex: to2(timeCostEx),
      time_cost_ex: to2(timeCostEx),

      distance_km: round1(distance_km),
      duration_min: Math.round(duration_min),

      base_drive_ex: to2(baseDriveEx),
      extra_stops_ex: to2(stopsFee),
      waiting_ex: to2(waitingFee),
      return_fee_ex: to2(returnFee),
      fuel_surcharge_ex: to2(fuelSurcharge),

      surcharge_rate: surchargeRate,
      surcharge_base_ex: to2(surchargeBaseEx),
      surcharge_amount_ex: to2(surchargeAmount),

      bags_ex: to2(bagsFee),
      tier: String(tier || "comfort"),
      tier_fee_ex: to2(tFee),
      vat_mode: vatMode,

      total_ex: to2(price_ex_out),
      vat_rate: rate,
      vat_amount: to2(price_vat),
      total_incl: to2(price_incl)
    }
  };
}

function to2(n) { return (Math.round(Number(n || 0) * 100) / 100).toFixed(2); }

function round2(n) {
  // keep monetary rounding consistent
  return to2(n);
}

function buildNote({ isNight, isWeekend, surchargeRate, tier, pax, bags, stop_count, wait_min, profile }) {
  let note = "Indicatief tarief op basis van route + rijtijd. Definitieve bevestiging na acceptatie.";
  const tags = [];
  tags.push(`tier: ${String(tier || "comfort").toUpperCase()} (+€${tierFeeFromProfileEx(tier, profile).toFixed(0)})`);
  tags.push(`pax: ${pax}`);
  tags.push(`bags: ${bags} (€${Number(profile?.bag_fee_each || 0).toFixed(2)}/koffer)`);
  if (stop_count) tags.push(`stops: ${stop_count}`);
  if (wait_min) tags.push(`wachttijd: ${wait_min} min`);
  if (isNight) tags.push("nachttarief +12%");
  if (isWeekend) tags.push("weekendtoeslag +8%");
  if (isNight && isWeekend && surchargeRate >= 0.20) tags.push("combinatie max +20%");
  if (tags.length) note += " (" + tags.join(", ") + ")";
  return note;
}

function parseWhen(whenStr, fallbackTimeStr) {
  try {
    const raw = String(whenStr || "").trim();
    const parts = raw.split(" ");
    const dpart = parts[0] || "";
    const tpart = parts[1] || fallbackTimeStr || "12:00";

    const [dd, mm, yyyy] = dpart.split("/").map((x) => Number(x));
    const [hh, mi] = String(tpart).split(":").map((x) => Number(x));

    const safeY = Number.isFinite(yyyy) ? yyyy : 2026;
    const safeM = Number.isFinite(mm) ? (mm - 1) : 0;
    const safeD = Number.isFinite(dd) ? dd : 1;
    const safeH = Number.isFinite(hh) ? hh : 12;
    const safeI = Number.isFinite(mi) ? mi : 0;

    const dt = new Date(safeY, safeM, safeD, safeH, safeI, 0, 0);
    return { day: dt.getDay(), hour: dt.getHours() };
  } catch {
    const [hh] = String(fallbackTimeStr || "12:00").split(":").map(Number);
    return { day: 1, hour: Number.isFinite(hh) ? hh : 12 };
  }
}

/* ===================== CALENDAR LOGIC (GOOGLE) ===================== */

function fmtLocalNLFromIso(isoString) {
  const d = new Date(isoString);
  const parts = new Intl.DateTimeFormat("nl-BE", {
    timeZone: "Europe/Brussels",
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false
  }).formatToParts(d);

  const get = (t) => parts.find(p => p.type === t)?.value || "";
  return `${get("day")}/${get("month")}/${get("year")} ${get("hour")}u${get("minute")}`;
}

function brusselsDateTimePartsFromIso(isoString) {
  try {
    const d = new Date(isoString);

    // Use a stable locale that outputs YYYY-MM-DD and HH:MM
    const date = new Intl.DateTimeFormat('sv-SE', {
      timeZone: 'Europe/Brussels',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(d);

    const time = new Intl.DateTimeFormat('sv-SE', {
      timeZone: 'Europe/Brussels',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).format(d);

    return { date, time };
  } catch {
    return { date: '', time: '' };
  }
}

function parseDurationMin(x, fallback = 0) {
  if (x == null) return fallback;
  if (typeof x === "number" && Number.isFinite(x)) return Math.trunc(x);
  const s = String(x).trim();
  if (!s) return fallback;
  const m = s.match(/(\d+)/);
  if (!m) return fallback;
  const n = Number(m[1]);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function computeWindow(pickupIso, busyMin) {
  const start = new Date(pickupIso);
  if (isNaN(start.getTime())) throw new Error("pickup_iso is invalid ISO datetime");
  const end = new Date(start.getTime() + busyMin * 60000);
  return { start, end };
}

function getStopHandlingMin(stopCount, env) {
  const perStop = toInt(env.STOP_EXTRA_MINUTES, 7);
  return Math.max(0, stopCount) * perStop;
}

function getBaseAddress(env) {
  return safeStr(env.BASE_ADDRESS) || BASE_ADDRESS_FIXED;
}

async function computeBufferMinLastPointToBase({ lastPointText, env }) {
  const base = getBaseAddress(env);
  if (!lastPointText || !base) return BUFFER_PLUS_MIN;

  try {
    const out = await routeFromTextsWithStopsDetailed({
      fromText: lastPointText,
      toText: base,
      stopsTexts: [],
      token: env.MAPBOX_TOKEN
    });
    const min = Math.round((out.route.duration || 0) / 60);
    return Math.max(0, min) + BUFFER_PLUS_MIN;
  } catch {
    return BUFFER_PLUS_MIN;
  }
}

// ========= ✅ BUFFER + TRAVEL GAP (Calendar availability) =========
// We no longer block time for "back to base" by default.
// Instead we reserve a small post-ride buffer, and when a NEW booking comes in,
// we validate there is enough travel time from the previous ride's drop-off to the new pickup.

const POST_BUFFER_MIN_DEFAULT = 15;      // post-ride handling (drop-off/payment)
const TRAVEL_GAP_MIN_DEFAULT = 15;       // margin for traffic / handover

function getPostBufferMin(env) {
  return Math.max(0, toInt(env.POST_BUFFER_MINUTES, POST_BUFFER_MIN_DEFAULT));
}

function getTravelGapMin(env) {
  return Math.max(0, toInt(env.TRAVEL_GAP_MINUTES, TRAVEL_GAP_MIN_DEFAULT));
}

function whenFromPickupIsoBrussels(pickupIso) {
  try {
    const d = new Date(pickupIso);
    if (isNaN(d.getTime())) return "";

    const date = new Intl.DateTimeFormat('nl-BE', {
      timeZone: 'Europe/Brussels',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit'
    }).format(d);

    const time = new Intl.DateTimeFormat('nl-BE', {
      timeZone: 'Europe/Brussels',
      hour: '2-digit',
      minute: '2-digit',
      hour12: false
    }).format(d);

    return `${date} ${time}`;
  } catch {
    return "";
  }
}

async function computeTravelMin({ fromText, toText, env }) {
  if (!fromText || !toText) return 0;
  try {
    const out = await routeFromTextsWithStopsDetailed({
      fromText,
      toText,
      stopsTexts: [],
      token: env.MAPBOX_TOKEN
    });
    return Math.max(0, Math.round((out.route.duration || 0) / 60));
  } catch {
    return 0;
  }
}

function parseLastPointFromDescription(desc) {
  const t = String(desc || "");

  // Prefer the last ROUTE LEG destination if present
  // Example: "2. A → B: 23.6 km • 30 min"
  const re = /^\s*\d+\.\s+.*?→\s+(.+?)\s*:\s*\d+/gm;
  let last = "";
  let m;
  while ((m = re.exec(t)) !== null) {
    last = String(m[1] || "").trim();
  }
  if (last) return last;

  // Fallback to "To:" line
  const m2 = t.match(/^To:\s*(.+)$/mi);
  if (m2) return String(m2[1] || "").trim();

  return "";
}

async function googleListEvents(accessToken, calendarId, timeMinIso, timeMaxIso) {
  const params = new URLSearchParams({
    timeMin: timeMinIso,
    timeMax: timeMaxIso,
    singleEvents: "true",
    orderBy: "startTime",
    maxResults: "50"
  });

  const u = `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events?${params.toString()}`;
  const r = await fetch(u, { headers: { Authorization: `Bearer ${accessToken}` } });
  const j = await r.json().catch(() => ({}));
  return Array.isArray(j.items) ? j.items : [];
}

async function ensureTravelGapFromPreviousEvent({ accessToken, calendarId, pickupIso, pickupFromText, env }) {
  try {
    const pickup = new Date(pickupIso);
    if (isNaN(pickup.getTime())) return { ok: true };

    const lookback = new Date(pickup.getTime() - 24 * 60 * 60 * 1000);
    const items = await googleListEvents(accessToken, calendarId, lookback.toISOString(), pickup.toISOString());
    if (!items.length) return { ok: true };

    const pickupT = pickup.getTime();
    let prev = null;
    let prevEndT = -1;

    for (const ev of items) {
      const endIso = ev?.end?.dateTime || ev?.end?.date;
      if (!endIso) continue;
      const t = new Date(endIso).getTime();
      if (isNaN(t)) continue;
      if (t < pickupT && t > prevEndT) {
        prevEndT = t;
        prev = ev;
      }
    }

    if (!prev) return { ok: true };

    const prevEndIso = String(prev?.end?.dateTime || prev?.end?.date || "");
    const prevLastPoint = parseLastPointFromDescription(prev?.description || "") || "";
    if (!prevLastPoint) return { ok: true, prev_end_iso: prevEndIso };

    const travelMin = await computeTravelMin({ fromText: prevLastPoint, toText: pickupFromText, env });
    const gapMin = getTravelGapMin(env);
    const requiredStartT = prevEndT + (travelMin + gapMin) * 60000;

    if (pickupT < requiredStartT) {
      return {
        ok: false,
        reason: "travel",
        prev_event_summary: String(prev?.summary || ""),
        prev_end_iso: prevEndIso,
        prev_last_point: prevLastPoint,
        travel_min: travelMin,
        gap_min: gapMin,
        required_pickup_iso: new Date(requiredStartT).toISOString()
      };
    }

    return { ok: true, prev_end_iso: prevEndIso, prev_last_point: prevLastPoint, travel_min: travelMin, gap_min: gapMin };
  } catch {
    return { ok: true };
  }
}


// =========================
// Tracking helpers (stored inside BOOKING_KV)
// =========================

function requireStr(v, name) {
  if (typeof v !== "string" || !v.trim()) throw new Error(`${name} is required`);
  return v.trim();
}

async function loadBookingRecord(env, bookingId) {
  if (!env.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const key = `booking:${bookingId}`;
  const rec = await env.BOOKING_KV.get(key, { type: "json" });
  if (!rec) throw new Error("Booking not found");
  return { key, rec };
}

function ensureTrackingScopeForRecord(rec, requestedScope) {
  if (!requestedScope?.hasScope) return missingTenantScopeError();
  if (!bookingMatchesRequestedTenantScope(rec, requestedScope)) {
    return { ok: false, error: "forbidden" };
  }
  return null;
}

async function _resolveTrackingBookingBySessionId(env, sessionOrTripId) {
  const wanted = String(sessionOrTripId || "").trim();
  if (!wanted) return null;
  if (!env?.BOOKING_KV) return null;
  const listed = await env.BOOKING_KV.list({ prefix: "booking:", limit: 1000 });
  for (const k of listed?.keys || []) {
    const key = String(k?.name || "");
    if (!key.startsWith("booking:")) continue;
    const rec = await env.BOOKING_KV.get(key, { type: "json" });
    if (!rec || typeof rec !== "object") continue;
    const recTripId = safeStr(
      rec?.trip?.trip_id ||
        rec?.trip?.session_id ||
        rec?.tracking_last?.trip_id ||
        rec?.tracking_last?.session_id,
      160,
    );
    if (!recTripId || recTripId !== wanted) continue;
    return {
      booking_id: key.slice("booking:".length),
      key,
      rec,
    };
  }
  return null;
}

async function trackingGetBooking(body, env, requestedScope = null) {
  try {
    const booking_id = requireStr(body?.booking_id || body?.bookingId, "booking_id");
    const { rec } = await loadBookingRecord(env, booking_id);
    const scopeBlock = ensureTrackingScopeForRecord(rec, requestedScope);
    if (scopeBlock) return scopeBlock;

    // The booking record already contains the canonical quote from your /book flow.
    // We simply return it so the app can display pricing + options consistently.
    return {
      ok: true,
      booking_id,
      build: FLUXIDI_BUILD,
      stage: rec?.stage || null,
      booking: rec?.booking || null,
      quote: rec?.quote || null,
      tracking_last: rec?.tracking_last || null,
      trip: rec?.trip || null,
      payment_status: rec?.payment_status || rec?.paymentStatus || rec?.booking?.payment_status || null,
      paymentStatus: rec?.paymentStatus || rec?.payment_status || rec?.booking?.paymentStatus || null,
      paid_at: rec?.paid_at || rec?.paidAt || rec?.booking?.paid_at || null,
      paidAt: rec?.paidAt || rec?.paid_at || rec?.booking?.paidAt || null,
      payment_method: rec?.payment_method || rec?.paymentMethod || rec?.booking?.payment_method || null,
      paymentMethod: rec?.paymentMethod || rec?.payment_method || rec?.booking?.paymentMethod || null,
      payment_source: rec?.payment_source || rec?.paymentSource || rec?.booking?.payment_source || null,
      paymentSource: rec?.paymentSource || rec?.payment_source || rec?.booking?.paymentSource || null,
      payment_provider: rec?.payment_provider || rec?.paymentProvider || rec?.booking?.payment_provider || null,
      paymentProvider: rec?.paymentProvider || rec?.payment_provider || rec?.booking?.paymentProvider || null,
      payment_id: rec?.payment_id || rec?.paymentId || rec?.booking?.payment_id || null,
      paymentId: rec?.paymentId || rec?.payment_id || rec?.booking?.paymentId || null,
    };
  } catch (err) {
    return { ok: false, error: err?.message || "trackingGetBooking failed" };
  }
}

async function trackingStart(body, env, requestedScope = null) {
  try {
    const booking_id = requireStr(body?.booking_id || body?.bookingId, "booking_id");
    const { key, rec } = await loadBookingRecord(env, booking_id);
    const scopeBlock = ensureTrackingScopeForRecord(rec, requestedScope);
    if (scopeBlock) return scopeBlock;

    const trip_id = crypto?.randomUUID ? crypto.randomUUID() : `trip_${Date.now()}_${Math.random().toString(16).slice(2)}`;
    rec.trip = {
      trip_id,
      started_at: new Date().toISOString(),
      started_by: body?.started_by || body?.device || "driver_phone",
    };

    await env.BOOKING_KV.put(key, JSON.stringify(rec));
    return { ok: true, booking_id,
      build: FLUXIDI_BUILD, trip_id };
  } catch (err) {
    return { ok: false, error: err?.message || "trackingStart failed" };
  }
}

async function trackingPing(body, env, requestedScope = null) {
  try {
    const booking_id = safeStr(body?.booking_id || body?.bookingId);
    const session_id = safeStr(
      body?.session_id ||
        body?.sessionId ||
        body?.trip_id ||
        body?.tripId,
      160,
    );
    const lat = Number(body?.lat);
    const lng = Number(body?.lng);
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) throw new Error("lat/lng are required numbers");

    const speed = body?.speed == null ? null : Number(body.speed);
    const accuracy = body?.accuracy == null ? null : Number(body.accuracy);
    const heading = body?.heading == null ? null : Number(body.heading);

    let resolvedBookingId = booking_id;
    let loaded = null;
    if (resolvedBookingId) {
      loaded = await loadBookingRecord(env, resolvedBookingId);
    } else if (session_id) {
      const resolved = await _resolveTrackingBookingBySessionId(env, session_id);
      if (!resolved?.booking_id || !resolved?.rec) {
        throw new Error("Booking not found");
      }
      resolvedBookingId = resolved.booking_id;
      loaded = { key: resolved.key, rec: resolved.rec };
    } else {
      throw new Error("booking_id is required");
    }
    const { key, rec } = loaded;
    const scopeBlock = ensureTrackingScopeForRecord(rec, requestedScope);
    if (scopeBlock) return scopeBlock;

    rec.tracking_last = {
      lat,
      lng,
      speed: Number.isFinite(speed) ? speed : null,
      accuracy: Number.isFinite(accuracy) ? accuracy : null,
      heading: Number.isFinite(heading) ? heading : null,
      ts: body?.ts || new Date().toISOString(),
      device: body?.device || "driver_phone",
    };

    await env.BOOKING_KV.put(key, JSON.stringify(rec));

    return { ok: true, booking_id: resolvedBookingId,
      build: FLUXIDI_BUILD, tracking_last: rec.tracking_last };
  } catch (err) {
    return { ok: false, error: err?.message || "trackingPing failed" };
  }
}

async function trackingLast(url, env, requestedScope = null) {
  try {
    if (!requestedScope?.hasScope) {
      return missingTenantScopeError();
    }
    const booking_id = safeStr(
      url?.searchParams?.get("booking_id") ||
        url?.searchParams?.get("bookingId"),
    );
    const session_id = safeStr(
      url?.searchParams?.get("session_id") ||
        url?.searchParams?.get("sessionId") ||
        url?.searchParams?.get("trip_id") ||
        url?.searchParams?.get("tripId"),
      160,
    );

    let resolvedBookingId = booking_id;
    let rec = null;
    if (resolvedBookingId) {
      const loaded = await loadBookingRecord(env, resolvedBookingId);
      rec = loaded.rec;
    } else if (session_id) {
      const resolved = await _resolveTrackingBookingBySessionId(env, session_id);
      if (!resolved?.booking_id || !resolved?.rec) {
        return { ok: false, error: "missing_tracking_booking_scope" };
      }
      resolvedBookingId = resolved.booking_id;
      rec = resolved.rec;
    } else {
      return { ok: false, error: "missing_tracking_booking_scope" };
    }
    const scopeBlock = ensureTrackingScopeForRecord(rec, requestedScope);
    if (scopeBlock) return scopeBlock;

    return { ok: true, booking_id: resolvedBookingId,
      build: FLUXIDI_BUILD, tracking_last: rec?.tracking_last || null, trip: rec?.trip || null };
  } catch (err) {
    return { ok: false, error: err?.message || "trackingLast failed" };
  }
}

function _normLifecycleStatus(v) {
  const raw = String(v || "").toUpperCase().trim();
  if (raw === "COMPLETED" || raw === "COMPLETE" || raw === "DONE" || raw === "CLOSED") {
    return "COMPLETED";
  }
  if (
    raw === "CANCELLED" ||
    raw === "CANCELED" ||
    raw === "DELETED" ||
    raw === "ARCHIVED" ||
    raw === "DECLINED" ||
    raw === "FAILED" ||
    raw === "EXPIRED"
  ) {
    return "CANCELLED";
  }
  if (raw === "BOOKED" || raw === "CONFIRMED" || raw === "PENDING" || raw === "ACTIVE" || raw === "OPEN") {
    return "PENDING";
  }
  return "PENDING";
}

const TERMINAL_BOOKING_LIFECYCLE_STATUSES = new Set([
  "COMPLETED",
  "CANCELLED",
  "CANCELED",
  "DELETED",
  "DECLINED",
  "FAILED",
  "EXPIRED",
]);

function isTerminalLifecycleStatus(value) {
  const raw = String(value || "").toUpperCase().trim();
  if (TERMINAL_BOOKING_LIFECYCLE_STATUSES.has(raw)) return true;
  const normalized = _normLifecycleStatus(raw);
  return normalized === "COMPLETED" || normalized === "CANCELLED";
}

function bookingPickupIsoFromRecord(rec) {
  return safeStr(
    rec?.booking?.pickupStartIso ||
      rec?.booking?.pickup_iso ||
      rec?.quote?.pickup_iso ||
      rec?.payload?.pickup_iso ||
      rec?.payload?.pickupIso,
  );
}

async function releaseAllocatorReservationForBooking({
  env,
  bookingId,
  rec,
  logTag,
}) {
  if (!env?.FLEET_ALLOCATOR || !env?.BOOKING_KV) return false;
  const canonicalBookingId = safeStr(bookingId);
  const pickupIso = bookingPickupIsoFromRecord(rec);
  if (!canonicalBookingId || !pickupIso) return false;
  const tenantScope = normalizeFleetTenantScope(resolveBookingTenantScopeFromRecord(rec));
  const assignedVehicleId = safeStr(_assignedVehicleIdFromRecord(rec));
  const maskedScope = _bookingIntentScopeMask(tenantScope);
  try {
    await _allocatorRequest(env, pickupIso, {
      action: "release",
      booking_id: canonicalBookingId,
      assigned_vehicle_id: assignedVehicleId || undefined,
      tenantScope,
    });
    console.log(
      `[FLEET][ALLOCATOR][${logTag}][OK] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(canonicalBookingId)}`,
    );
    return true;
  } catch (err) {
    console.log(
      `[FLEET][ALLOCATOR][${logTag}][ERROR] tenant=${maskedScope.tenant} company=${maskedScope.company} booking=${_bookingIntentMask(canonicalBookingId)} reason=${safeStr(err?.message || err, 140) || "unknown"}`,
    );
    return false;
  }
}

function _pick(obj, path, fb = null) {
  let cur = obj;
  for (const key of path) {
    if (!cur || typeof cur !== "object" || !(key in cur)) return fb;
    cur = cur[key];
  }
  return cur == null ? fb : cur;
}

async function existingCalendarForBooking(env, bookingId) {
  try {
    if (!env?.BOOKING_KV || !bookingId) return null;
    const rec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    if (!rec || typeof rec !== "object") return null;
    const eventId =
      rec.calendar_event_id ||
      rec.calendarEventId ||
      _pick(rec, ["calendar", "calendar_event_id"], null) ||
      _pick(rec, ["calendar", "calendarEventId"], null) ||
      _pick(rec, ["booking", "calendar_event_id"], null);
    if (!eventId) return null;
    return {
      eventId,
      htmlLink:
        rec.htmlLink ||
        _pick(rec, ["calendar", "htmlLink"], null) ||
        _pick(rec, ["booking", "htmlLink"], null),
      returnEventId:
        rec.return_event_id ||
        rec.returnEventId ||
        _pick(rec, ["calendar", "return_event_id"], null) ||
        _pick(rec, ["calendar", "returnEventId"], null) ||
        _pick(rec, ["booking", "return_event_id"], null) ||
        _pick(rec, ["booking", "returnEventId"], null),
      returnHtmlLink:
        rec.return_htmlLink ||
        rec.returnHtmlLink ||
        _pick(rec, ["calendar", "return_htmlLink"], null) ||
        _pick(rec, ["calendar", "returnHtmlLink"], null) ||
        _pick(rec, ["booking", "return_htmlLink"], null) ||
        _pick(rec, ["booking", "returnHtmlLink"], null),
    };
  } catch (_) {
    return null;
  }
}

function _flattenBookingForRidesList(bookingId, rec) {
  const from = _pick(rec, ["quote", "from"], null) ?? _pick(rec, ["booking", "from"], null);
  const to = _pick(rec, ["quote", "to"], null) ?? _pick(rec, ["booking", "to"], null);
  const tier = _pick(rec, ["booking", "tier"], null) ?? _pick(rec, ["quote", "tier"], null);
  const pax = _pick(rec, ["booking", "pax"], null);
  const bags = _pick(rec, ["booking", "bags"], null);
  const pickupIso =
    _pick(rec, ["booking", "pickupStartIso"], null) ??
    _pick(rec, ["booking", "pickup_iso"], null) ??
    _pick(rec, ["quote", "pickup_iso"], null) ??
    _pick(rec, ["booking", "createdAt"], null);
  const pricing = _pick(rec, ["quote", "pricing"], null) || {};
  const price =
    pricing.price_incl_vat ??
    pricing.total_price ??
    pricing.total ??
    _pick(rec, ["booking", "price_incl_vat"], null) ??
    _pick(rec, ["booking", "price"], null);
  const customerName =
    _pick(rec, ["booking", "customer_name"], null) ??
    _pick(rec, ["booking", "custName"], null) ??
    _pick(rec, ["booking", "name"], null) ??
    _pick(rec, ["booking", "customer", "name"], null);
  const customerPhone =
    _pick(rec, ["booking", "customer_phone"], null) ??
    _pick(rec, ["booking", "custPhone"], null) ??
    _pick(rec, ["booking", "phone"], null) ??
    _pick(rec, ["booking", "customer", "phone"], null);
  const customerEmail =
    _pick(rec, ["booking", "customer_email"], null) ??
    _pick(rec, ["booking", "custEmail"], null) ??
    _pick(rec, ["booking", "email"], null) ??
    _pick(rec, ["booking", "customer", "email"], null);
  const paymentStatus =
    rec?.payment_status ??
    rec?.paymentStatus ??
    _pick(rec, ["booking", "payment_status"], null) ??
    _pick(rec, ["booking", "paymentStatus"], null);
  const paidAt =
    rec?.paid_at ??
    rec?.paidAt ??
    _pick(rec, ["booking", "paid_at"], null) ??
    _pick(rec, ["booking", "paidAt"], null);
  const paymentProvider =
    rec?.payment_provider ??
    rec?.paymentProvider ??
    _pick(rec, ["booking", "payment_provider"], null) ??
    _pick(rec, ["booking", "paymentProvider"], null);
  const paymentId =
    rec?.payment_id ??
    rec?.paymentId ??
    _pick(rec, ["booking", "payment_id"], null) ??
    _pick(rec, ["booking", "paymentId"], null);
  const paymentMethod =
    rec?.payment_method ??
    rec?.paymentMethod ??
    _pick(rec, ["booking", "payment_method"], null) ??
    _pick(rec, ["booking", "paymentMethod"], null);
  const paymentSource =
    rec?.payment_source ??
    rec?.paymentSource ??
    _pick(rec, ["booking", "payment_source"], null) ??
    _pick(rec, ["booking", "paymentSource"], null);

  return {
    booking_id: bookingId,
    pickup_iso: pickupIso,
    from,
    to,
    tier,
    pax,
    bags,
    assigned_vehicle_id:
      _pick(rec, ["assigned_vehicle_id"], null) ??
      _pick(rec, ["booking", "assigned_vehicle_id"], null),
    customer_name: customerName,
    customer_phone: customerPhone,
    customer_email: customerEmail,
    custName: customerName,
    custPhone: customerPhone,
    custEmail: customerEmail,
    name: customerName,
    phone: customerPhone,
    email: customerEmail,
    customer: {
      name: customerName || "",
      phone: customerPhone || "",
      email: customerEmail || "",
    },
    status: _normLifecycleStatus(rec?.status || rec?.stage || null),
    price,
    currency: _pick(rec, ["booking", "currency"], "EUR") || "EUR",
    payment_status: paymentStatus,
    paymentStatus,
    paid_at: paidAt,
    paidAt,
    payment_provider: paymentProvider,
    paymentProvider,
    payment_id: paymentId,
    paymentId,
    payment_method: paymentMethod,
    paymentMethod,
    payment_source: paymentSource,
    paymentSource,
  };
}

const VEHICLE_INVENTORY_KEY = "fleet:vehicles:v1";
const PARTNER_DIRECTORY_KEY = "partners:directory:v1";
const PARTNER_PROFILES_KEY = "partners:profiles:v1";
const PARTNER_BOOKING_ROUTE_KEY = "partners:booking-routes:v1";
const PARTNER_DIRECTORY_SEED = [
  {
    partner_id: "partner_fluxidi_antwerp",
    company_name: "Fluxidi Antwerp",
    is_active: true,
    subscription_status: "active",
    supported_postcodes: ["2000", "2018", "2060"],
  },
  {
    partner_id: "partner_fluxidi_brussels",
    company_name: "Fluxidi Brussels",
    is_active: true,
    subscription_status: "active",
    supported_postcodes: ["1000", "1020", "1030"],
  },
  {
    partner_id: "partner_demo_inactive",
    company_name: "Demo Partner Inactive",
    is_active: false,
    subscription_status: "active",
    supported_postcodes: ["9000"],
  },
];
const PARTNER_PROFILES_SEED = [
  {
    partner_id: "partner_fluxidi_taxi_9688",
    company_name: "Fluxidi Taxi",
    profile_enabled: true,
    is_active: true,
    subscription_status: "active",
    tagline: "Premium mobiliteit in jouw regio",
    about_short: "Comfortabele en professionele ritten voor particulieren en bedrijven.",
    about_long:
      "Fluxidi Taxi biedt betrouwbare deur-tot-deur mobiliteit met professionele chauffeurs, premium voertuigen en heldere communicatie.",
    coverage: {
      region_label: "Belgie",
      postcodes: ["9688"],
    },
    public_contact: {
      website: "https://fluxidi.com",
      public_phone: "",
      booking_email: "",
    },
    media: {
      logo_url: "",
      hero_photo_url: "",
      gallery: [],
    },
    services: [
      "taxi_vvb",
      "airport_transfer",
      "business_rides",
      "hotel_bnb_pickup",
      "event_mobility",
      "online_payments",
    ],
    payment_methods: ["cash", "qr", "online_payment"],
    vehicles: [
      {
        name: "Premium sedan",
        brand_model: "Tesla Model 3",
        category: "Premium",
        pax: 3,
        luggage: 3,
        features: ["comfort", "ev_available"],
        photo_url: "",
      },
    ],
    drivers: [
      {
        display_name: "Professionele chauffeur",
        languages: ["NL", "FR", "EN"],
        badges: ["verified_professional"],
      },
    ],
    trust: {
      verified_partner: true,
      professional_badge: true,
    },
    booking_capabilities: {
      online_payments: true,
      instant_quote: false,
      profile_enabled: true,
    },
  },
];
const PARTNER_BOOKING_ROUTE_SEED = [
  {
    partner_id: "partner_fluxidi_antwerp",
    tenant_id: "fluxidi",
    company_id: "fluxidi",
    company_name: "Fluxidi Antwerp",
    is_active: true,
    subscription_status: "active",
  },
  {
    partner_id: "partner_fluxidi_brussels",
    tenant_id: "fluxidi",
    company_id: "fluxidi",
    company_name: "Fluxidi Brussels",
    is_active: true,
    subscription_status: "active",
  },
  {
    partner_id: "partner_demo_inactive",
    tenant_id: "fluxidi",
    company_id: "fluxidi",
    company_name: "Demo Partner Inactive",
    is_active: false,
    subscription_status: "active",
  },
  {
    partner_id: "partner_fluxidi_taxi_9688",
    tenant_id: "fluxidi",
    company_id: "fluxidi",
    company_name: "Fluxidi Taxi",
    is_active: true,
    subscription_status: "active",
  },
];

function _normalizePostcode(v) {
  return String(v || "")
    .trim()
    .toUpperCase()
    .replace(/\s+/g, "");
}

function _normalizePartnerEntry(raw) {
  if (!raw || typeof raw !== "object") return null;
  const partnerId = String(raw.partner_id || raw.id || "").trim();
  const companyName = String(raw.company_name || raw.name || "").trim();
  const isActive = raw.is_active === true;
  const subscriptionStatus = String(raw.subscription_status || "").trim().toLowerCase();
  const sourcePostcodes = Array.isArray(raw.supported_postcodes) ? raw.supported_postcodes : [];
  const sourcePrimary = raw.primary_postcode ?? raw.primaryPostcode ?? "";
  const primaryPostcode = _normalizePostcode(sourcePrimary);
  const supportedSet = new Set(
    sourcePostcodes
      .map(_normalizePostcode)
      .filter((x) => !!x),
  );
  if (primaryPostcode) supportedSet.add(primaryPostcode);
  const supportedPostcodes = Array.from(supportedSet);
  if (!partnerId || !companyName) return null;
  return {
    partner_id: partnerId,
    company_name: companyName,
    is_active: isActive,
    subscription_status: subscriptionStatus,
    primary_postcode: primaryPostcode,
    supported_postcodes: supportedPostcodes,
  };
}

function _isSubscriptionActive(status) {
  const s = String(status || "").trim().toLowerCase();
  return s === "active" || s === "valid";
}

async function _loadPartnerDirectory(env) {
  const fallback = PARTNER_DIRECTORY_SEED
    .map(_normalizePartnerEntry)
    .filter((p) => p !== null);
  if (!env?.BOOKING_KV) return fallback;
  const raw = await env.BOOKING_KV.get(PARTNER_DIRECTORY_KEY, { type: "json" });
  const incoming = Array.isArray(raw)
    ? raw
    : (raw && typeof raw === "object" && Array.isArray(raw.partners) ? raw.partners : null);
  if (!Array.isArray(incoming)) return fallback;
  const normalized = incoming
    .map(_normalizePartnerEntry)
    .filter((p) => p !== null);
  return normalized.length > 0 ? normalized : fallback;
}

async function listNearbyPartnersByPostcode(env, postcode) {
  const needle = _normalizePostcode(postcode);
  if (!needle) return [];
  const partners = await _loadPartnerDirectory(env);
  const profiles = await _loadPublicPartnerProfiles(env);
  const publicMediaByPartnerId = new Map(
    profiles
      .filter((profile) => _isPublicPartnerProfileVisible(profile))
      .map((profile) => {
        const media = profile && typeof profile.media === "object" ? profile.media : {};
        const heroUrl = _safePublicHttpsUrl(media.hero_photo_url ?? media.heroPhotoUrl, 600);
        const logoUrl = _safePublicHttpsUrl(media.logo_url ?? media.logoUrl, 600);
        return [profile.partner_id, { hero_photo_url: heroUrl, logo_url: logoUrl }];
      }),
  );
  const coverageByPartnerId = new Map(
    profiles
      .filter((profile) => _isPublicPartnerProfileVisible(profile))
      .map((profile) => {
        const coverage = profile && typeof profile.coverage === "object" ? profile.coverage : {};
        const profilePostcodes = Array.isArray(coverage.postcodes) ? coverage.postcodes : [];
        const normalizedPostcodes = Array.from(
          new Set(
            profilePostcodes
              .map(_normalizePostcode)
              .filter((x) => !!x),
          ),
        );
        const profilePrimary = _normalizePostcode(coverage.primary_postcode ?? coverage.primaryPostcode);
        return [
          profile.partner_id,
          {
            primary_postcode: profilePrimary,
            postcodes: normalizedPostcodes,
          },
        ];
      }),
  );
  return partners
    .map((p, idx) => ({ p, idx }))
    .filter(({ p }) => p.is_active === true)
    .filter(({ p }) => _isSubscriptionActive(p.subscription_status))
    .map(({ p, idx }) => {
      const profileCoverage = coverageByPartnerId.get(p.partner_id) || {};
      const supportedSet = new Set(
        Array.isArray(p.supported_postcodes) ? p.supported_postcodes : [],
      );
      const profilePostcodes = Array.isArray(profileCoverage.postcodes)
        ? profileCoverage.postcodes
        : [];
      for (const code of profilePostcodes) supportedSet.add(code);
      const supportedPostcodes = Array.from(supportedSet);
      const primaryPostcode = _normalizePostcode(
        p.primary_postcode || profileCoverage.primary_postcode,
      );
      return {
        p,
        idx,
        supportedPostcodes,
        primaryPostcode,
        matches: supportedPostcodes.includes(needle),
      };
    })
    .filter((entry) => entry.matches)
    .sort((a, b) => {
      const aRank = a.primaryPostcode && a.primaryPostcode === needle ? 0 : 1;
      const bRank = b.primaryPostcode && b.primaryPostcode === needle ? 0 : 1;
      if (aRank !== bRank) return aRank - bRank;
      return a.idx - b.idx;
    })
    .map((entry) => {
      const p = entry.p;
      const media = publicMediaByPartnerId.get(p.partner_id) || {};
      return {
        partner_id: p.partner_id,
        company_name: p.company_name,
        is_active: true,
        subscription_status: p.subscription_status,
        supported_postcodes: entry.supportedPostcodes,
        hero_photo_url: _safePublicHttpsUrl(media.hero_photo_url, 600),
        logo_url: _safePublicHttpsUrl(media.logo_url, 600),
      };
    });
}

function _extractRequestedPublicPartnerId({ url, body = null } = {}) {
  const search = url?.searchParams;
  return _safePublicText(
    body?.public_partner_id ??
      body?.publicPartnerId ??
      body?.partner_id ??
      body?.partnerId ??
      search?.get("public_partner_id") ??
      search?.get("publicPartnerId") ??
      search?.get("partner_id") ??
      search?.get("partnerId"),
    120,
  );
}

function _normalizePartnerBookingRouteEntry(raw) {
  if (!raw || typeof raw !== "object") return null;
  const partnerId = _safePublicText(raw.partner_id ?? raw.partnerId, 120);
  const tenantId = sanitizeTenantString(raw.tenant_id ?? raw.tenantId, 80);
  const companyId =
    sanitizeTenantString(raw.company_id ?? raw.companyId, 80) || tenantId;
  if (!partnerId || !tenantId || !companyId) return null;
  const updatedAt = _safePublicText(raw.updated_at ?? raw.updatedAt, 80);
  return {
    partner_id: partnerId,
    tenant_id: tenantId,
    company_id: companyId,
    company_name: _safePublicText(raw.company_name ?? raw.companyName, 160),
    is_active: raw.is_active === true,
    subscription_status: _safePublicText(
      raw.subscription_status ?? raw.subscriptionStatus,
      32,
    ).toLowerCase(),
    updated_at: updatedAt || new Date().toISOString(),
  };
}

async function _loadPartnerBookingRoutes(env) {
  const fallback = PARTNER_BOOKING_ROUTE_SEED
    .map(_normalizePartnerBookingRouteEntry)
    .filter((entry) => entry !== null);
  if (!env?.BOOKING_KV) return fallback;
  const raw = await env.BOOKING_KV.get(PARTNER_BOOKING_ROUTE_KEY, {
    type: "json",
  });
  const incoming = Array.isArray(raw)
    ? raw
    : raw &&
        typeof raw === "object" &&
        Array.isArray(raw.routes)
    ? raw.routes
    : null;
  if (!Array.isArray(incoming)) return fallback;
  const normalized = incoming
    .map(_normalizePartnerBookingRouteEntry)
    .filter((entry) => entry !== null);
  return normalized.length > 0 ? normalized : fallback;
}

function _isPartnerBookingRouteActive(entry) {
  if (!entry || typeof entry !== "object") return false;
  if (entry.is_active !== true) return false;
  return _isSubscriptionActive(entry.subscription_status);
}

async function resolvePublicPartnerBookingScope(env, partnerId) {
  const requestedPartnerId = _safePublicText(partnerId, 120);
  if (!requestedPartnerId) {
    return { ok: false, error: "public_partner_id is required", status: 400 };
  }
  const routes = await _loadPartnerBookingRoutes(env);
  const match = routes.find((entry) => entry.partner_id === requestedPartnerId);
  if (!match) {
    return { ok: false, error: "public partner not found", status: 404 };
  }
  if (!_isPartnerBookingRouteActive(match)) {
    return { ok: false, error: "public partner is inactive", status: 409 };
  }
  return {
    ok: true,
    partner_id: match.partner_id,
    company_name: match.company_name,
    tenant_id: match.tenant_id,
    company_id: match.company_id,
  };
}

function _isAllowedPublicImageContentType(contentType) {
  const normalized = String(contentType || "").trim().toLowerCase();
  return (
    normalized === "image/jpeg" ||
    normalized === "image/png" ||
    normalized === "image/webp"
  );
}

function _detectPublicImageFormat(bytes) {
  if (!(bytes instanceof Uint8Array) || bytes.length < 12) {
    return { ok: false, error: "invalid or too small image" };
  }
  const startsWithPng =
    bytes.length >= 8 &&
    bytes[0] === 0x89 &&
    bytes[1] === 0x50 &&
    bytes[2] === 0x4e &&
    bytes[3] === 0x47 &&
    bytes[4] === 0x0d &&
    bytes[5] === 0x0a &&
    bytes[6] === 0x1a &&
    bytes[7] === 0x0a;
  if (startsWithPng) return { ok: true, ext: "png", content_type: "image/png" };

  const startsWithJpeg =
    bytes.length >= 3 &&
    bytes[0] === 0xff &&
    bytes[1] === 0xd8 &&
    bytes[2] === 0xff;
  if (startsWithJpeg) return { ok: true, ext: "jpg", content_type: "image/jpeg" };

  const startsWithWebp =
    bytes.length >= 12 &&
    String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3]) === "RIFF" &&
    String.fromCharCode(bytes[8], bytes[9], bytes[10], bytes[11]) === "WEBP";
  if (startsWithWebp) return { ok: true, ext: "webp", content_type: "image/webp" };

  return { ok: false, error: "unsupported image format" };
}

function _sanitizePublicMediaSegment(value) {
  const raw = sanitizeTenantString(value, 120).toLowerCase();
  const sanitized = raw.replace(/[^a-z0-9._-]/g, "-").replace(/-+/g, "-");
  return sanitized.replace(/^-+/, "").replace(/-+$/, "");
}

function _validateCompanyMediaType(mediaType) {
  if (
    mediaType === "company_logo" ||
    mediaType === "company_hero" ||
    mediaType === "vehicle_photo"
  ) {
    return { ok: true };
  }
  return { ok: false, error: "unsupported media_type" };
}

function _validatePublicMediaEntityId(mediaType, entityIdRaw) {
  if (mediaType !== "vehicle_photo") return { ok: true, entity_id: "" };
  const raw = sanitizeTenantString(entityIdRaw, 120);
  if (!raw) return { ok: false, error: "entity_id is required for vehicle_photo" };
  if (raw.includes("/") || raw.includes("\\") || raw.includes("..")) {
    return { ok: false, error: "invalid entity_id" };
  }
  const safe = _sanitizePublicMediaSegment(raw);
  if (!safe || !/^[a-z0-9._-]+$/.test(safe)) {
    return { ok: false, error: "invalid entity_id" };
  }
  return { ok: true, entity_id: safe };
}

function _buildPublicCompanyMediaKey({ tenantId, companyId, mediaType, entityId, ext }) {
  const tenantSeg = _sanitizePublicMediaSegment(tenantId);
  const companySeg = _sanitizePublicMediaSegment(companyId);
  if (!tenantSeg || !companySeg) {
    throw new Error("invalid tenant/company scope");
  }
  const safeExt = _sanitizePublicMediaSegment(ext || "jpg") || "jpg";
  if (mediaType === "company_logo" || mediaType === "company_hero") {
    const fileName = mediaType === "company_logo" ? `logo.${safeExt}` : `hero.${safeExt}`;
    return `public-media/${tenantSeg}/${companySeg}/company/${fileName}`;
  }
  if (mediaType === "vehicle_photo") {
    const entitySeg = _sanitizePublicMediaSegment(entityId);
    if (!entitySeg) throw new Error("invalid vehicle entity scope");
    return `public-media/${tenantSeg}/${companySeg}/vehicles/${entitySeg}/photo.${safeExt}`;
  }
  throw new Error("unsupported media type");
}

function _encodePublicMediaKeyForUrl(key) {
  return String(key || "")
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
}

function _decodePublicMediaKeyFromPath(pathPart) {
  const chunks = String(pathPart || "").split("/").filter((s) => s.length > 0);
  try {
    return chunks.map((s) => decodeURIComponent(s)).join("/");
  } catch {
    return "";
  }
}

function _validatePublicMediaReadKey(key) {
  const candidate = String(key || "");
  if (!candidate) return { ok: false, error: "missing media key" };
  if (!candidate.startsWith("public-media/")) {
    return { ok: false, error: "invalid media key prefix" };
  }
  if (candidate.includes("..") || candidate.includes("\\")) {
    return { ok: false, error: "invalid media key" };
  }
  return { ok: true };
}

function _safePublicText(value, maxLen = 240) {
  return sanitizeTenantString(value, maxLen);
}

function _safePublicBool(value, fallback = false) {
  return typeof value === "boolean" ? value : fallback;
}

function _safePublicInt(value, fallback = 0, min = 0, max = 99) {
  const n = Number(value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(n)));
}

function _safePublicStringList(value, { maxItems = 20, maxItemLen = 80 } = {}) {
  if (!Array.isArray(value)) return [];
  const out = [];
  for (const item of value) {
    if (out.length >= maxItems) break;
    const text = _safePublicText(item, maxItemLen);
    if (!text) continue;
    out.push(text);
  }
  return out;
}

function _safePublicHttpsUrl(value, maxLen = 600) {
  const text = _safePublicText(value, maxLen);
  if (!text) return "";
  const lower = text.toLowerCase();
  if (!lower.startsWith("https://")) return "";
  if (lower.startsWith("https://localhost")) return "";
  if (lower.includes("..\\")) return "";
  return text;
}

function _normalizePublicCoverage(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  const primaryPostcode = _normalizePostcode(
    src.primary_postcode ?? src.primaryPostcode,
  );
  const supportedSet = new Set(
    _safePublicStringList(src.postcodes, { maxItems: 40, maxItemLen: 24 })
      .map(_normalizePostcode)
      .filter((v) => !!v),
  );
  if (primaryPostcode) supportedSet.add(primaryPostcode);
  return {
    region_label: _safePublicText(src.region_label ?? src.regionLabel, 120),
    primary_postcode: primaryPostcode,
    postcodes: Array.from(supportedSet),
  };
}

function _normalizePublicContact(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  return {
    website: _safePublicText(src.website, 240),
    public_phone: _safePublicText(src.public_phone ?? src.publicPhone, 64),
    booking_email: _safePublicText(src.booking_email ?? src.bookingEmail, 160),
  };
}

function _normalizePublicMedia(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  return {
    logo_url: _safePublicHttpsUrl(src.logo_url ?? src.logoUrl, 600),
    hero_photo_url: _safePublicHttpsUrl(src.hero_photo_url ?? src.heroPhotoUrl, 600),
    gallery: _safePublicStringList(src.gallery, { maxItems: 12, maxItemLen: 600 })
      .map((v) => _safePublicHttpsUrl(v, 600))
      .filter((v) => !!v),
  };
}

function _normalizePublicVehicles(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const row of raw) {
    if (!row || typeof row !== "object") continue;
    out.push({
      name: _safePublicText(row.name, 120),
      brand_model: _safePublicText(row.brand_model ?? row.brandModel, 120),
      category: _safePublicText(row.category, 80),
      pax: _safePublicInt(row.pax, 0, 0, 99),
      luggage: _safePublicInt(row.luggage, 0, 0, 99),
      features: _safePublicStringList(row.features, { maxItems: 12, maxItemLen: 80 }),
      photo_url: _safePublicHttpsUrl(row.photo_url ?? row.photoUrl, 600),
    });
  }
  return out;
}

function _normalizePublicDrivers(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const row of raw) {
    if (!row || typeof row !== "object") continue;
    out.push({
      display_name: _safePublicText(row.display_name ?? row.displayName, 120),
      languages: _safePublicStringList(row.languages, { maxItems: 8, maxItemLen: 12 }),
      badges: _safePublicStringList(row.badges, { maxItems: 8, maxItemLen: 64 }),
      portrait_url: _safePublicHttpsUrl(row.portrait_url ?? row.portraitUrl, 600),
    });
  }
  return out;
}

function _normalizePublicTrust(raw) {
  const src = raw && typeof raw === "object" ? raw : {};
  return {
    verified_partner: _safePublicBool(src.verified_partner ?? src.verifiedPartner, false),
    professional_badge: _safePublicBool(src.professional_badge ?? src.professionalBadge, false),
  };
}

function _normalizePublicBookingCapabilities(raw, profileEnabled) {
  const src = raw && typeof raw === "object" ? raw : {};
  return {
    online_payments: _safePublicBool(src.online_payments ?? src.onlinePayments, false),
    instant_quote: _safePublicBool(src.instant_quote ?? src.instantQuote, false),
    profile_enabled: !!profileEnabled,
  };
}

function _normalizePublicPartnerProfileEntry(raw) {
  if (!raw || typeof raw !== "object") return null;
  const partnerId = _safePublicText(raw.partner_id ?? raw.partnerId, 120);
  const companyName = _safePublicText(raw.company_name ?? raw.companyName, 160);
  const profileEnabled = _safePublicBool(raw.profile_enabled ?? raw.profileEnabled, false);
  const isActive = raw.is_active === true;
  const subscriptionStatus = _safePublicText(raw.subscription_status ?? raw.subscriptionStatus, 32)
    .toLowerCase();
  if (!partnerId || !companyName) return null;
  return {
    partner_id: partnerId,
    company_name: companyName,
    profile_enabled: profileEnabled,
    is_active: isActive,
    subscription_status: subscriptionStatus,
    tagline: _safePublicText(raw.tagline, 180),
    about_short: _safePublicText(raw.about_short ?? raw.aboutShort, 400),
    about_long: _safePublicText(raw.about_long ?? raw.aboutLong, 2000),
    coverage: _normalizePublicCoverage(raw.coverage),
    public_contact: _normalizePublicContact(raw.public_contact ?? raw.publicContact),
    media: _normalizePublicMedia(raw.media),
    services: _safePublicStringList(raw.services, { maxItems: 24, maxItemLen: 64 }),
    payment_methods: _safePublicStringList(raw.payment_methods ?? raw.paymentMethods, {
      maxItems: 12,
      maxItemLen: 40,
    }),
    vehicles: _normalizePublicVehicles(raw.vehicles),
    drivers: _normalizePublicDrivers(raw.drivers),
    trust: _normalizePublicTrust(raw.trust),
    booking_capabilities: _normalizePublicBookingCapabilities(
      raw.booking_capabilities ?? raw.bookingCapabilities,
      profileEnabled,
    ),
  };
}

function _isPublicPartnerProfileVisible(profile) {
  if (!profile || typeof profile !== "object") return false;
  if (profile.profile_enabled !== true) return false;
  if (profile.is_active !== true) return false;
  return _isSubscriptionActive(profile.subscription_status);
}

async function _loadPublicPartnerProfiles(env) {
  const fallback = PARTNER_PROFILES_SEED
    .map(_normalizePublicPartnerProfileEntry)
    .filter((p) => p !== null);
  if (!env?.BOOKING_KV) return fallback;
  const raw = await env.BOOKING_KV.get(PARTNER_PROFILES_KEY, { type: "json" });
  const incoming = Array.isArray(raw)
    ? raw
    : (raw && typeof raw === "object" && Array.isArray(raw.profiles) ? raw.profiles : null);
  if (!Array.isArray(incoming)) return fallback;
  const normalized = incoming
    .map(_normalizePublicPartnerProfileEntry)
    .filter((p) => p !== null);
  return normalized;
}

async function getPublicPartnerProfileById(env, partnerId) {
  const needle = _safePublicText(partnerId, 120);
  if (!needle) return null;
  const profiles = await _loadPublicPartnerProfiles(env);
  const profile = profiles.find((p) => p.partner_id === needle);
  if (!profile) return null;
  if (!_isPublicPartnerProfileVisible(profile)) return null;
  return {
    partner_id: profile.partner_id,
    company_name: profile.company_name,
    profile_enabled: true,
    is_active: true,
    subscription_status: profile.subscription_status,
    tagline: profile.tagline,
    about_short: profile.about_short,
    about_long: profile.about_long,
    coverage: profile.coverage,
    public_contact: profile.public_contact,
    media: profile.media,
    services: profile.services,
    payment_methods: profile.payment_methods,
    vehicles: profile.vehicles,
    drivers: profile.drivers,
    trust: profile.trust,
    booking_capabilities: profile.booking_capabilities,
  };
}

function _normTierForVehicleMatch(v) {
  const s = String(v || "").trim().toLowerCase();
  if (!s) return "*";
  if (s === "any" || s === "all" || s === "*") return "*";
  return s;
}

function _toPositiveInt(v, fallback = 0) {
  const n = Number(v);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(0, Math.trunc(n));
}

function _bookingMatchesFleetScopeOrLegacyGlobal(rec, fleetScope) {
  const normalizedScope = normalizeFleetTenantScope(fleetScope);
  if (!normalizedScope.hasScope) return true;
  return bookingMatchesRequestedTenantScope(rec, normalizedScope);
}

function normalizeFleetTenantScope(scope) {
  const tenantIdRaw = _scopeText(scope?.tenant_id ?? scope?.tenantId);
  const companyIdRaw = _scopeText(scope?.company_id ?? scope?.companyId);
  const tenantId = tenantIdRaw || companyIdRaw || "";
  const companyId = companyIdRaw || tenantId || "";
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: !!(tenantId || companyId),
  };
}

function fleetInventoryScopedKeyForScope(scope) {
  const normalized = normalizeFleetTenantScope(scope);
  if (!normalized.hasScope) return VEHICLE_INVENTORY_KEY;
  return `tenant:${normalized.tenant_id}:company:${normalized.company_id}:fleet:vehicles:v1`;
}

function _fleetVehiclesRawFromKv(raw) {
  if (Array.isArray(raw)) return raw;
  if (raw && typeof raw === "object" && Array.isArray(raw.vehicles)) return raw.vehicles;
  return [];
}

async function _loadFleetInventoryRawForScope(env, scope, { allowLegacyFallback = false } = {}) {
  if (!env.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const normalizedScope = normalizeFleetTenantScope(scope);
  const scopedKey = fleetInventoryScopedKeyForScope(normalizedScope);
  const scopedRaw = await env.BOOKING_KV.get(scopedKey, { type: "json" });
  const scopedVehiclesRaw = _fleetVehiclesRawFromKv(scopedRaw);
  if (scopedVehiclesRaw.length > 0) {
    const response = {
      key: scopedKey,
      source: "scoped",
      scoped_key: scopedKey,
      legacy_key: VEHICLE_INVENTORY_KEY,
      vehiclesRaw: scopedVehiclesRaw,
    };
    if (allowLegacyFallback) {
      const legacyRaw = await env.BOOKING_KV.get(VEHICLE_INVENTORY_KEY, { type: "json" });
      response.legacyVehiclesRaw = _fleetVehiclesRawFromKv(legacyRaw);
      response.legacy_source = "legacy_diagnostic";
    }
    return response;
  }
  if (!allowLegacyFallback) {
    // Default scoped fleet reads prevent global legacy rows from being treated as active company fleet.
    return {
      key: scopedKey,
      source: "scoped_empty",
      scoped_key: scopedKey,
      legacy_key: VEHICLE_INVENTORY_KEY,
      vehiclesRaw: [],
    };
  }
  const legacyRaw = await env.BOOKING_KV.get(VEHICLE_INVENTORY_KEY, { type: "json" });
  const legacyVehiclesRaw = _fleetVehiclesRawFromKv(legacyRaw);
  return {
    key: scopedKey,
    source: "scoped_empty",
    scoped_key: scopedKey,
    legacy_key: VEHICLE_INVENTORY_KEY,
    vehiclesRaw: [],
    legacyVehiclesRaw,
    legacy_source: "legacy_diagnostic",
  };
}

function _normalizeVehicleEntry(raw, { scope = null } = {}) {
  if (!raw || typeof raw !== "object") return null;
  const vehicleId = String(raw.vehicle_id || raw.id || "").trim();
  if (!vehicleId) return null;
  const isActive = raw.is_active == null ? true : !!raw.is_active;
  const tier = _normTierForVehicleMatch(raw.tier || raw.service_class || raw.class || "*");
  const passengerCapacity = _toPositiveInt(raw.passenger_capacity ?? raw.pax_capacity ?? raw.pax ?? 0, 0);
  const luggageCapacity = _toPositiveInt(raw.luggage_capacity ?? raw.bags_capacity ?? raw.bags ?? 0, 0);
  const driverRaw = raw.assigned_driver || raw.driver || null;
  let assignedDriver = null;
  if (driverRaw && typeof driverRaw === "object") {
    const driverId = String(driverRaw.driver_id || driverRaw.id || "").trim();
    const name = String(driverRaw.name || driverRaw.full_name || "").trim();
    const phone = String(driverRaw.phone || "").trim();
    if (driverId || name || phone) {
      assignedDriver = {
        driver_id: driverId || null,
        name: name || null,
        phone: phone || null,
      };
    }
  }
  const normalizedScope = normalizeFleetTenantScope(scope);
  const tenantId = _scopeText(raw.tenant_id ?? raw.tenantId) || normalizedScope.tenant_id || "";
  const companyId = _scopeText(raw.company_id ?? raw.companyId) || normalizedScope.company_id || tenantId;
  return {
    vehicle_id: vehicleId,
    is_active: isActive,
    tier,
    passenger_capacity: passengerCapacity,
    luggage_capacity: luggageCapacity,
    assigned_driver: assignedDriver,
    tenant_id: tenantId,
    company_id: companyId,
    tenantId: tenantId,
    companyId: companyId,
  };
}

async function _loadVehicleInventory(env, { scope = null } = {}) {
  if (!env.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const fleetRead = scope?.hasScope
    ? await _loadFleetInventoryRawForScope(env, scope)
    : { vehiclesRaw: await (async () => {
      const raw = await env.BOOKING_KV.get(VEHICLE_INVENTORY_KEY, { type: "json" });
      if (Array.isArray(raw)) return raw;
      if (raw && typeof raw === "object" && Array.isArray(raw.vehicles)) return raw.vehicles;
      return [];
    })() };
  const vehiclesRaw = Array.isArray(fleetRead?.vehiclesRaw) ? fleetRead.vehiclesRaw : [];
  const normalizedScope = scope?.hasScope ? normalizeFleetTenantScope(scope) : null;
  const normalized = vehiclesRaw
    .map((entry) => _normalizeVehicleEntry(entry, { scope: normalizedScope }))
    .filter((v) => v && v.is_active);
  if (normalized.length > 0) return normalized;

  // Backward-safe default: preserve existing single-resource behavior when no backend fleet is configured yet.
  return [
    {
      vehicle_id: "default_company_vehicle",
      is_active: true,
      tier: "*",
      passenger_capacity: 99,
      luggage_capacity: 99,
    },
  ];
}

function _vehicleSupportsRequest(vehicle, req) {
  if (!vehicle || !vehicle.is_active) return false;
  // Tier remains part of the data model (commercial label),
  // but operational suitability is driven by real capacity constraints.
  const reqPax = _toPositiveInt(req?.pax ?? 0, 0);
  const reqBags = _toPositiveInt(req?.bags ?? 0, 0);
  if (_toPositiveInt(vehicle?.passenger_capacity ?? 0, 0) < reqPax) return false;
  if (_toPositiveInt(vehicle?.luggage_capacity ?? 0, 0) < reqBags) return false;
  return true;
}

function _windowsOverlap(aStartMs, aDurMin, bStartMs, bDurMin) {
  if (!Number.isFinite(aStartMs) || !Number.isFinite(bStartMs)) return false;
  const aEnd = aStartMs + Math.max(1, Number(aDurMin) || 1) * 60000;
  const bEnd = bStartMs + Math.max(1, Number(bDurMin) || 1) * 60000;
  return aStartMs < bEnd && bStartMs < aEnd;
}

function _bookingDemandFromRecord(rec, env) {
  const pickupIso =
    _pick(rec, ["booking", "pickupStartIso"], null) ??
    _pick(rec, ["booking", "pickup_iso"], null) ??
    _pick(rec, ["quote", "pickup_iso"], null);
  const pickupMs = pickupIso ? Date.parse(pickupIso) : Number.NaN;
  const tier = normalizeTier(
    _pick(rec, ["booking", "tier"], null) ??
      _pick(rec, ["quote", "tier"], null) ??
      "comfort",
  );
  const pax = _toPositiveInt(_pick(rec, ["booking", "pax"], null), 1);
  const bags = _toPositiveInt(_pick(rec, ["booking", "bags"], null), 0);
  const durationRoute = Number(
    _pick(rec, ["booking", "duration_route_min"], null) ??
      _pick(rec, ["quote", "duration_min"], null) ??
      _pick(rec, ["quote", "duration_route_min"], null) ??
      0,
  );
  const returnEnabled = !!(
    _pick(rec, ["booking", "return_enabled"], null) ??
    _pick(rec, ["quote", "return", "enabled"], null) ??
    false
  );
  const hasReturnSchedule = !!(
    _pick(rec, ["booking", "returnPickupIso"], null) ??
    _pick(rec, ["booking", "return_pickup_iso"], null) ??
    _pick(rec, ["quote", "return", "pickup_iso"], null)
  );
  const returnDuration = Number(
    _pick(rec, ["booking", "return_duration_min"], null) ??
    _pick(rec, ["quote", "return", "duration_min"], null) ??
    0,
  );
  const waitMin = _toPositiveInt(
    _pick(rec, ["booking", "wait_min"], null) ??
      _pick(rec, ["quote", "wait_min"], null),
    0,
  );
  const stopCount = Math.max(
    0,
    _toPositiveInt(
      _pick(rec, ["booking", "stop_count"], null) ??
        (Array.isArray(_pick(rec, ["booking", "stops"], null))
          ? _pick(rec, ["booking", "stops"], []).length
          : null) ??
        (Array.isArray(_pick(rec, ["quote", "stops"], null))
          ? _pick(rec, ["quote", "stops"], []).length
          : null),
      0,
    ),
  );
  const durationMainMin = Math.max(0, Number.isFinite(durationRoute) ? durationRoute : 0);
  const durationReturnMin = Math.max(0, Number.isFinite(returnDuration) ? returnDuration : 0);
  const durationTotalMin = hasReturnSchedule
    ? durationMainMin
    : (durationMainMin + (returnEnabled ? durationReturnMin : 0));
  const stopHandlingMin = getStopHandlingMin(stopCount, env || {});
  const postBufferMin = getPostBufferMin(env || {});
  const serviceMin = Math.max(
    30,
    Math.round(durationTotalMin + waitMin + Math.max(0, stopHandlingMin) + Math.max(0, postBufferMin)),
  );
  return {
    pickupMs,
    tier,
    pax,
    bags,
    serviceMin,
  };
}

function _availabilityMode(env) {
  const raw = String(
    env?.FLEET_AVAILABILITY_MODE ??
    env?.AVAILABILITY_MODE ??
    "single_resource",
  )
    .trim()
    .toLowerCase();
  return raw === "multi_vehicle" ? "multi_vehicle" : "single_resource";
}

async function _vehicleCapacityGateForRequest(env, req) {
  const fleetScope = normalizeFleetTenantScope(req?.tenantScope ?? req?.tenant_scope ?? req);
  const vehicles = await _loadVehicleInventory(env, { scope: fleetScope });
  const suitableVehicles = vehicles.filter((v) => _vehicleSupportsRequest(v, req));
  if (suitableVehicles.length === 0) {
    return {
      ok: false,
      reason: "no_suitable_vehicle",
      suitable_vehicle_count: 0,
      overlapping_demand_count: 0,
      available_slots: 0,
      needed_slots: 1,
    };
  }

  const assignment = await _pickVehicleAssignmentForRequest(env, {
    ...req,
    tenantScope: fleetScope,
  });
  const availableSlots = Number(assignment?.available_slots ?? 0);
  const overlappingDemand = Number(assignment?.overlapping_demand_count ?? 0);
  if (availableSlots <= 0) {
    return {
      ok: false,
      reason: "vehicle_capacity_exceeded",
      suitable_vehicle_count: suitableVehicles.length,
      overlapping_demand_count: overlappingDemand,
      available_slots: Math.max(0, availableSlots),
      needed_slots: 1,
    };
  }

  return {
    ok: true,
    suitable_vehicle_count: suitableVehicles.length,
    overlapping_demand_count: overlappingDemand,
    available_slots: availableSlots,
    needed_slots: 1,
  };
}

function _assignedVehicleIdFromRecord(rec) {
  return (
    _pick(rec, ["assigned_vehicle_id"], null) ??
    _pick(rec, ["booking", "assigned_vehicle_id"], null) ??
    null
  );
}

function _assignedDriverFromVehicle(vehicle) {
  const d = vehicle?.assigned_driver;
  if (!d || typeof d !== "object") return null;
  const driverId = String(d.driver_id || "").trim();
  const name = String(d.name || "").trim();
  const phone = String(d.phone || "").trim();
  if (!driverId && !name && !phone) return null;
  return {
    driver_id: driverId || null,
    name: name || null,
    phone: phone || null,
  };
}

async function _pickVehicleAssignmentForRequest(env, req) {
  const evaluation = await _evaluateFleetAvailability(env, req);
  return {
    vehicle_id: evaluation?.next_vehicle_candidate?.vehicle_id || null,
    assigned_driver: evaluation?.next_vehicle_candidate?.assigned_driver || null,
    suitable_vehicle_count: Number(evaluation?.suitable_vehicle_count || 0),
    overlapping_demand_count:
      Number(evaluation?.occupied_assigned_vehicle_ids?.length || 0) +
      Number(evaluation?.overlapping_unassigned_demand || 0),
    available_slots: Number(evaluation?.available_slots || 0),
    needed_slots: 1,
  };
}

async function _evaluateFleetAvailability(env, req) {
  const fleetScope = normalizeFleetTenantScope(req?.tenantScope ?? req?.tenant_scope ?? req);
  const vehicles = await _loadVehicleInventory(env, { scope: fleetScope });
  const suitableVehicles = vehicles.filter((v) => _vehicleSupportsRequest(v, req));
  const pickupMs = Number(req?.pickupMs);
  const serviceMin = Math.max(1, Number(req?.serviceMin) || 1);
  const pickupEndMs =
    Number.isFinite(pickupMs) ? pickupMs + serviceMin * 60000 : Number.NaN;

  if (suitableVehicles.length === 0) {
    return {
      request: {
        tier: req?.tier ?? null,
        pax: req?.pax ?? null,
        bags: req?.bags ?? null,
        pickup_ms: Number.isFinite(pickupMs) ? pickupMs : null,
        pickup_window_end_ms: Number.isFinite(pickupEndMs) ? pickupEndMs : null,
        service_min: serviceMin,
      },
      suitable_vehicle_ids: [],
      overlapping_actionable_bookings: [],
      occupied_assigned_vehicle_ids: [],
      overlapping_unassigned_demand: 0,
      suitable_vehicle_count: 0,
      available_slots: 0,
      free_vehicle_count: 0,
      would_allow_booking: false,
      next_vehicle_candidate: null,
      block_reason: "no_suitable_vehicle",
    };
  }

  const suitableIds = new Set(suitableVehicles.map((v) => v.vehicle_id));
  const listed = await env.BOOKING_KV.list({ prefix: "booking:", limit: 1000 });
  const occupiedAssignedIds = new Set();
  let overlappingUnassignedDemand = 0;
  const overlappingBookings = [];

  for (const k of listed?.keys || []) {
    const key = String(k?.name || "");
    if (!key.startsWith("booking:")) continue;
    const rec = await env.BOOKING_KV.get(key, { type: "json" });
    if (!rec || typeof rec !== "object") continue;
    if (!_bookingMatchesFleetScopeOrLegacyGlobal(rec, fleetScope)) continue;

    if (isTerminalLifecycleStatus(_bookingLifecycleValue(rec))) continue;

    const d = _bookingDemandFromRecord(rec, env);
    if (!Number.isFinite(d.pickupMs)) continue;
    if (!_windowsOverlap(pickupMs, serviceMin, d.pickupMs, d.serviceMin)) continue;
    const bookingId = key.slice("booking:".length);
    const demandEndMs = d.pickupMs + Math.max(1, Number(d.serviceMin) || 1) * 60000;
    const assignedVehicleId = _assignedVehicleIdFromRecord(rec);
    if (assignedVehicleId && suitableIds.has(assignedVehicleId)) {
      occupiedAssignedIds.add(assignedVehicleId);
      overlappingBookings.push({
        booking_id: bookingId || null,
        assigned_vehicle_id: assignedVehicleId,
        pickup_ms: d.pickupMs,
        pickup_window_end_ms: demandEndMs,
        counted_as: "assigned_occupied",
      });
      continue;
    }

    const demandServiceable = suitableVehicles.some((v) => _vehicleSupportsRequest(v, d));
    if (!demandServiceable) {
      overlappingBookings.push({
        booking_id: bookingId || null,
        assigned_vehicle_id: assignedVehicleId || null,
        pickup_ms: d.pickupMs,
        pickup_window_end_ms: demandEndMs,
        counted_as: "ignored_not_serviceable_for_pool",
      });
      continue;
    }
    overlappingUnassignedDemand += 1;
    overlappingBookings.push({
      booking_id: bookingId || null,
      assigned_vehicle_id: assignedVehicleId || null,
      pickup_ms: d.pickupMs,
      pickup_window_end_ms: demandEndMs,
      counted_as: "unassigned_demand",
    });
  }

  const freeVehicles = suitableVehicles.filter(
    (v) => !occupiedAssignedIds.has(v.vehicle_id),
  );
  freeVehicles.sort((a, b) =>
    String(a.vehicle_id).localeCompare(String(b.vehicle_id)),
  );
  const availableSlots = freeVehicles.length - overlappingUnassignedDemand;
  const nextVehicle = availableSlots > 0 && freeVehicles.length
    ? {
        vehicle_id: freeVehicles[0].vehicle_id,
        assigned_driver: _assignedDriverFromVehicle(freeVehicles[0]),
      }
    : null;

  return {
    request: {
      tier: req?.tier ?? null,
      pax: req?.pax ?? null,
      bags: req?.bags ?? null,
      pickup_ms: Number.isFinite(pickupMs) ? pickupMs : null,
      pickup_window_end_ms: Number.isFinite(pickupEndMs) ? pickupEndMs : null,
      service_min: serviceMin,
    },
    suitable_vehicle_ids: suitableVehicles.map((v) => v.vehicle_id),
    overlapping_actionable_bookings: overlappingBookings,
    occupied_assigned_vehicle_ids: Array.from(occupiedAssignedIds),
    overlapping_unassigned_demand: overlappingUnassignedDemand,
    suitable_vehicle_count: suitableVehicles.length,
    free_vehicle_count: freeVehicles.length,
    available_slots: Math.max(0, availableSlots),
    would_allow_booking: availableSlots > 0,
    next_vehicle_candidate: nextVehicle,
    block_reason: availableSlots > 0 ? null : "vehicle_capacity_exceeded",
  };
}

async function _driverSummaryForVehicleId(env, vehicleId, scope = null) {
  const wanted = String(vehicleId || "").trim();
  if (!wanted) return null;
  const normalizedScope = normalizeFleetTenantScope(scope);
  const vehicles = await _loadVehicleInventory(env, { scope: normalizedScope });
  const hit = vehicles.find((v) => v?.vehicle_id === wanted);
  return _assignedDriverFromVehicle(hit || null);
}

function _pickupIsoForFleetDebug(body) {
  const direct = safeStr(body?.pickup_iso || body?.pickupIso);
  if (direct) return direct;
  const date = safeStr(body?.date);
  const time = safeStr(body?.time);
  if (!date || !time) return "";
  return brusselsIsoFromDateTime(date, time) || "";
}

async function debugFleetAvailability(body, env, tenantScope = null) {
  try {
    if (!env?.BOOKING_KV) {
      return { ok: false, error: "Missing BOOKING_KV binding" };
    }
    const pickupIso = _pickupIsoForFleetDebug(body);
    if (!pickupIso) {
      return { ok: false, error: "Missing pickup_iso (or date+time)" };
    }
    const pickupMs = Date.parse(pickupIso);
    if (!Number.isFinite(pickupMs)) {
      return { ok: false, error: "Invalid pickup_iso" };
    }
    const tier = normalizeTier(body?.tier || "comfort");
    const pax = clampInt(body?.pax, 1, 99);
    const bags = Math.max(0, clampInt(body?.bags, 0, 99));
    const serviceMin = Math.max(
      30,
      Math.round(
        Number(body?.duration_min ?? body?.duration_route_min ?? body?.durationMin ?? 0) +
          Number(body?.wait_min ?? body?.wait_minutes ?? body?.waitMin ?? 0) +
          15,
      ),
    );
    const decision = await _evaluateFleetAvailability(env, {
      pickupMs,
      serviceMin,
      tier,
      pax,
      bags,
      tenantScope: normalizeFleetTenantScope(tenantScope),
    });

    return {
      ok: true,
      simulation_only: true,
      request: {
        pickup_iso: pickupIso,
        ...(decision.request || {}),
      },
      suitable_vehicle_ids: decision.suitable_vehicle_ids || [],
      overlapping_actionable_bookings:
        decision.overlapping_actionable_bookings || [],
      occupied_assigned_vehicle_ids:
        decision.occupied_assigned_vehicle_ids || [],
      overlapping_unassigned_demand:
        Number(decision.overlapping_unassigned_demand || 0),
      suitable_vehicle_count: Number(decision.suitable_vehicle_count || 0),
      free_vehicle_count: Number(decision.free_vehicle_count || 0),
      available_slots: Number(decision.available_slots || 0),
      would_allow_booking: !!decision.would_allow_booking,
      next_vehicle_candidate: decision.next_vehicle_candidate || null,
      block_reason: decision.block_reason || null,
    };
  } catch (e) {
    return { ok: false, error: String(e?.message || e) };
  }
}

async function debugFleetRecentBookings(url, env, tenantScope = null) {
  if (!env?.BOOKING_KV) {
    return { ok: false, error: "Missing BOOKING_KV binding" };
  }
  if (!tenantScope?.hasScope) {
    return missingTenantScopeError();
  }
  const limit = Math.max(
    1,
    Math.min(200, Number(url.searchParams.get("limit") || "50") || 50),
  );
  const listed = await env.BOOKING_KV.list({ prefix: "booking:", limit: 1000 });
  const keys = Array.isArray(listed?.keys) ? listed.keys : [];
  const rows = [];

  for (const k of keys) {
    const key = String(k?.name || "");
    if (!key.startsWith("booking:")) continue;
    const rec = await env.BOOKING_KV.get(key, { type: "json" });
    if (!rec || typeof rec !== "object") continue;
    if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) continue;
    const bookingId = key.slice("booking:".length) || null;
    const rawStage = rec?.stage ?? null;
    const rawStatus = rec?.status ?? null;
    const normalized = _normLifecycleStatus(rawStatus || rawStage || null);
    const pickupIso =
      _pick(rec, ["booking", "pickupStartIso"], null) ??
      _pick(rec, ["booking", "pickup_iso"], null) ??
      _pick(rec, ["quote", "pickup_iso"], null);
    const d = _bookingDemandFromRecord(rec, env);
    const pickupMs = Number.isFinite(d?.pickupMs) ? d.pickupMs : null;
    const serviceMin = Number.isFinite(d?.serviceMin) ? d.serviceMin : null;
    const pickupWindowEndMs =
      pickupMs != null && serviceMin != null
        ? pickupMs + Math.max(1, serviceMin) * 60000
        : null;
    const actionableForOverlap =
      normalized !== "COMPLETED" &&
      normalized !== "CANCELLED" &&
      pickupMs != null;

    rows.push({
      kv_key: key,
      booking_id: bookingId,
      raw_stage: rawStage,
      raw_status: rawStatus,
      normalized_status: normalized,
      pickup_fields: {
        booking_pickupStartIso: _pick(rec, ["booking", "pickupStartIso"], null),
        booking_pickup_iso: _pick(rec, ["booking", "pickup_iso"], null),
        quote_pickup_iso: _pick(rec, ["quote", "pickup_iso"], null),
        effective_pickup_iso: pickupIso ?? null,
      },
      assigned_vehicle_id: _assignedVehicleIdFromRecord(rec),
      duration_route_min:
        _pick(rec, ["booking", "duration_route_min"], null) ??
        _pick(rec, ["quote", "duration_min"], null) ??
        _pick(rec, ["quote", "duration_route_min"], null) ??
        null,
      wait_min:
        _pick(rec, ["booking", "wait_min"], null) ??
        _pick(rec, ["quote", "wait_min"], null) ??
        null,
      return_enabled:
        _pick(rec, ["booking", "return_enabled"], null) ??
        _pick(rec, ["quote", "return", "enabled"], null) ??
        null,
      return_pickup_fields: {
        booking_returnPickupIso: _pick(rec, ["booking", "returnPickupIso"], null),
        booking_return_pickup_iso: _pick(rec, ["booking", "return_pickup_iso"], null),
        quote_return_pickup_iso: _pick(rec, ["quote", "return", "pickup_iso"], null),
      },
      return_duration_min:
        _pick(rec, ["booking", "return_duration_min"], null) ??
        _pick(rec, ["quote", "return", "duration_min"], null) ??
        null,
      actionable_for_overlap: actionableForOverlap,
      reconstructed_overlap: {
        pickup_ms: pickupMs,
        service_min: serviceMin,
        pickup_window_end_ms: pickupWindowEndMs,
      },
    });
    if (rows.length >= limit) break;
  }

  return {
    ok: true,
    limit,
    count: rows.length,
    items: rows,
  };
}

async function listBookingsAuthoritative(
  env,
  { limit = 50, includeHistory = false, tenantScope = null } = {},
) {
  if (!tenantScope?.hasScope) return [];
  if (!env.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const lim = Math.min(200, Math.max(1, Number(limit) || 50));
  const nowMs = Date.now();
  const actionableGraceMs = 6 * 60 * 60 * 1000; // keep slightly-past rides visible for operational safety
  const cutoffMs = nowMs - actionableGraceMs;
  const listed = await env.BOOKING_KV.list({ prefix: "booking:", limit: 1000 });
  const out = [];
  for (const k of listed?.keys || []) {
    const name = String(k?.name || "");
    if (!name.startsWith("booking:")) continue;
    const bookingId = name.slice("booking:".length);
    if (!bookingId) continue;
    const rec = await env.BOOKING_KV.get(name, { type: "json" });
    if (!rec || typeof rec !== "object") continue;
    if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) continue;
    const row = _flattenBookingForRidesList(bookingId, rec);
    if (!includeHistory && (row.status === "COMPLETED" || row.status === "CANCELLED")) continue;
    if (!includeHistory) {
      const pickupTs = row.pickup_iso ? Date.parse(row.pickup_iso) : Number.NaN;
      // For "available rides", require a valid pickup datetime.
      // Historical/debug records with missing/invalid pickup should stay out of operational list.
      if (!Number.isFinite(pickupTs)) continue;
      if (Number.isFinite(pickupTs) && pickupTs < cutoffMs) continue;
    }
    out.push(row);
  }

  out.sort((a, b) => {
    const ta = a.pickup_iso ? Date.parse(a.pickup_iso) : Number.POSITIVE_INFINITY;
    const tb = b.pickup_iso ? Date.parse(b.pickup_iso) : Number.POSITIVE_INFINITY;
    return ta - tb;
  });

  return out.slice(0, lim);
}

const DASHBOARD_BOOKINGS_KPI_EXCLUDED_TERMINAL_STATUSES = [
  "completed",
  "cancelled",
  "canceled",
  "deleted",
  "archived",
  "closed",
  "failed",
  "expired",
  "declined",
];

const DASHBOARD_BOOKINGS_KPI_TERMINAL_STATUS_SET = new Set(
  DASHBOARD_BOOKINGS_KPI_EXCLUDED_TERMINAL_STATUSES,
);

function _normalizeDashboardBookingLifecycle(value) {
  const raw = String(value || "")
    .trim()
    .toLowerCase()
    .replaceAll("-", "_")
    .replaceAll(" ", "_");
  if (!raw) return "";
  if (raw === "complete" || raw === "done") return "completed";
  if (raw === "canceled") return "cancelled";
  return raw;
}

function _isDashboardTerminalBookingLifecycle(value) {
  const normalized = _normalizeDashboardBookingLifecycle(value);
  if (!normalized) return false;
  if (DASHBOARD_BOOKINGS_KPI_TERMINAL_STATUS_SET.has(normalized)) return true;
  return isTerminalLifecycleStatus(value);
}

async function computeDashboardBookingsKpis(env, { tenantScope } = {}) {
  if (!tenantScope?.hasScope) return missingTenantScopeError();
  if (!env?.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");

  let scannedKeys = 0;
  let matchedScope = 0;
  let consideredOpen = 0;
  let cursor = undefined;
  let scanComplete = true;

  do {
    const page = await env.BOOKING_KV.list({
      prefix: "booking:",
      limit: 1000,
      cursor,
    });
    for (const item of page?.keys || []) {
      const key = String(item?.name || "");
      if (!key.startsWith("booking:")) continue;
      scannedKeys += 1;
      const rec = await env.BOOKING_KV.get(key, { type: "json" });
      if (!rec || typeof rec !== "object") continue;
      if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) continue;
      matchedScope += 1;
      if (_isDashboardTerminalBookingLifecycle(_bookingLifecycleValue(rec))) {
        continue;
      }
      consideredOpen += 1;
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
    if (!cursor) {
      scanComplete = false;
      break;
    }
  } while (cursor);

  return {
    ok: true,
    tenant_id: tenantScope.tenant_id,
    company_id: tenantScope.company_id,
    generated_at: new Date().toISOString(),
    open_bookings_count: consideredOpen,
    excluded_terminal_statuses: DASHBOARD_BOOKINGS_KPI_EXCLUDED_TERMINAL_STATUSES,
    scan_complete: scanComplete,
    scan_stats: {
      scanned_keys: scannedKeys,
      matched_scope: matchedScope,
      considered_open: consideredOpen,
    },
  };
}

async function getBookingAuthoritative(bookingId, env, tenantScope = null, preloadedRec = null) {
  if (!tenantScope?.hasScope) {
    return missingTenantScopeError();
  }
  const rec = preloadedRec || (await loadBookingRecord(env, bookingId)).rec;
  if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) {
    return { ok: false, error: "forbidden" };
  }
  return {
    ok: true,
    booking_id: bookingId,
    status: _normLifecycleStatus(rec?.status || rec?.stage || null),
    record: rec,
  };
}

async function updateBookingStatusAuthoritative(bookingId, status, env, tenantScope = null) {
  if (!tenantScope?.hasScope) {
    return missingTenantScopeError();
  }
  const normalized = _normLifecycleStatus(status);
  if (!["COMPLETED", "CANCELLED", "PENDING"].includes(normalized)) {
    return { ok: false, error: "Invalid status" };
  }
  const { key, rec } = await loadBookingRecord(env, bookingId);
  if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) {
    return { ok: false, error: "forbidden" };
  }
  const nowIso = new Date().toISOString();
  rec.status = normalized;
  rec.stage = normalized;
  rec.lifecycle_status = normalized.toLowerCase();
  rec.lifecycleStatus = normalized.toLowerCase();
  rec.booking_status = normalized.toLowerCase();
  rec.bookingStatus = normalized.toLowerCase();
  rec.updatedAt = nowIso;
  if (rec.booking && typeof rec.booking === "object") {
    rec.booking.status = normalized;
    rec.booking.stage = normalized;
    rec.booking.lifecycle_status = normalized.toLowerCase();
    rec.booking.lifecycleStatus = normalized.toLowerCase();
    rec.booking.booking_status = normalized.toLowerCase();
    rec.booking.bookingStatus = normalized.toLowerCase();
  }
  if (normalized === "CANCELLED") {
    rec.cancelled_at = rec.cancelled_at || nowIso;
    rec.cancelledAt = rec.cancelledAt || rec.cancelled_at;
    rec.canceled_at = rec.canceled_at || rec.cancelled_at;
    rec.canceledAt = rec.canceledAt || rec.cancelled_at;
    if (rec.booking && typeof rec.booking === "object") {
      rec.booking.cancelled_at = rec.booking.cancelled_at || rec.cancelled_at;
      rec.booking.cancelledAt = rec.booking.cancelledAt || rec.cancelled_at;
      rec.booking.canceled_at = rec.booking.canceled_at || rec.cancelled_at;
      rec.booking.canceledAt = rec.booking.canceledAt || rec.cancelled_at;
    }
  } else if (normalized === "COMPLETED") {
    rec.completed_at = rec.completed_at || nowIso;
    rec.completedAt = rec.completedAt || rec.completed_at;
    if (rec.booking && typeof rec.booking === "object") {
      rec.booking.completed_at = rec.booking.completed_at || rec.completed_at;
      rec.booking.completedAt = rec.booking.completedAt || rec.completed_at;
    }
  }
  if (normalized === "COMPLETED" || normalized === "CANCELLED") {
    await cleanupBookingCalendarEvents(env, rec, tenantScope);
  }
  await env.BOOKING_KV.put(key, JSON.stringify(rec));
  if (isTerminalLifecycleStatus(normalized)) {
    await releaseAllocatorReservationForBooking({
      env,
      bookingId,
      rec,
      logTag: "RELEASE_ON_TERMINAL",
    });
  }
  return { ok: true, booking_id: bookingId, status: normalized };
}

async function updateBookingPaymentAuthoritative(
  bookingId,
  payment,
  env,
  ctx,
  tenantScope = null,
) {
  if (!tenantScope?.hasScope) {
    return missingTenantScopeError();
  }
  const { key, rec } = await loadBookingRecord(env, bookingId);
  if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) {
    return { ok: false, error: "forbidden" };
  }
  const asText = (value) => String(value ?? "").trim();
  const wasAlreadyPaid =
    String(rec?.payment_status || rec?.paymentStatus || "").toLowerCase() === "paid";

  const rawStatus = asText(payment?.payment_status || payment?.paymentStatus).toLowerCase();
  const normalizedStatus =
    rawStatus === "paid" ||
    rawStatus === "confirmed" ||
    rawStatus === "completed" ||
    rawStatus === "success" ||
    rawStatus === "settled"
      ? "paid"
      : rawStatus === "pending" || rawStatus === "authorized" || rawStatus === "open"
        ? "pending"
        : rawStatus === "failed" || rawStatus === "cancelled" || rawStatus === "canceled"
          ? "failed"
          : "paid";

  const method = asText(payment?.payment_method || payment?.paymentMethod).toLowerCase();
  const source = asText(payment?.payment_source || payment?.paymentSource).toLowerCase() || "in_car";
  const paidAt = asText(payment?.paid_at || payment?.paidAt) || new Date().toISOString();
  const currency = asText(payment?.currency || rec?.booking?.currency || rec?.currency || "EUR").toUpperCase() || "EUR";
  const amountRaw = payment?.amount ?? payment?.price ?? payment?.total;
  const amountNum = Number(amountRaw);
  const amount = Number.isFinite(amountNum) ? amountNum : null;
  const paidByDriverId = asText(payment?.paid_by_driver_id || payment?.paidByDriverId);

  rec.payment_status = normalizedStatus;
  rec.paymentStatus = normalizedStatus;
  if (normalizedStatus === "paid") {
    rec.paid_at = paidAt;
    rec.paidAt = paidAt;
  }
  if (method) {
    rec.payment_method = method;
    rec.paymentMethod = method;
  }
  if (source) {
    rec.payment_source = source;
    rec.paymentSource = source;
  }
  rec.currency = currency;
  if (amount != null) {
    rec.payment_amount = amount;
    rec.paymentAmount = amount;
  }
  if (paidByDriverId) {
    rec.paid_by_driver_id = paidByDriverId;
    rec.paidByDriverId = paidByDriverId;
  }

  if (rec.booking && typeof rec.booking === "object") {
    rec.booking.payment_status = normalizedStatus;
    rec.booking.paymentStatus = normalizedStatus;
    if (normalizedStatus === "paid") {
      rec.booking.paid_at = paidAt;
      rec.booking.paidAt = paidAt;
    }
    if (method) {
      rec.booking.payment_method = method;
      rec.booking.paymentMethod = method;
    }
    if (source) {
      rec.booking.payment_source = source;
      rec.booking.paymentSource = source;
    }
    rec.booking.currency = rec.booking.currency || currency;
    if (amount != null) {
      rec.booking.payment_amount = amount;
      rec.booking.paymentAmount = amount;
    }
    if (paidByDriverId) {
      rec.booking.paid_by_driver_id = paidByDriverId;
      rec.booking.paidByDriverId = paidByDriverId;
    }
  }

  rec.updatedAt = new Date().toISOString();

  if (normalizedStatus === "paid" && !wasAlreadyPaid) {
    let shouldLogInvoiceCustomerErrors = false;
    try {
      const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : null;
      const profile = await resolveTenantCommunicationProfile(env);
      const adminInvoiceEmail = pickFirstValidEmail(
        profile.invoiceEmail,
        profile.billingEmail,
        profile.notificationEmail,
        env.OWNER_EMAIL,
      );
      const customerEmail = pickFirstValidEmail(
        booking?.custEmail,
        booking?.customer_email,
        booking?.customerEmail,
        booking?.email,
      );
      const parseBoolFlag = (value) => {
        if (value === true) return true;
        if (value === false || value == null) return false;
        const raw = String(value).trim().toLowerCase();
        return raw === "1" || raw === "true" || raw === "yes" || raw === "ja" || raw === "y";
      };
      const customerCompany = safeStr(
        booking?.company_name ||
        booking?.companyName ||
        booking?.customer_company ||
        booking?.customerCompany,
      );
      const customerVat = safeStr(
        booking?.vat_number ||
        booking?.vatNumber ||
        booking?.customer_vat ||
        booking?.customerVat,
      );
      const customerInvoiceEmail = pickFirstValidEmail(
        booking?.invoice_email,
        booking?.invoiceEmail,
        booking?.customer_invoice_email,
        booking?.customerInvoiceEmail,
      );
      const invoiceRequested = parseBoolFlag(
        booking?.invoice_requested ??
        booking?.invoiceRequested ??
        rec?.invoice_requested ??
        rec?.invoiceRequested,
      );
      const businessDetected = parseBoolFlag(
        booking?.business_detected ??
        booking?.businessDetected ??
        rec?.business_detected ??
        rec?.businessDetected,
      );
      const businessInvoiceContext =
        invoiceRequested ||
        businessDetected ||
        !!customerCompany ||
        !!customerVat ||
        (!!customerInvoiceEmail && (!!customerCompany || !!customerVat));
      const sendCustomerInvoiceEmail = !!businessInvoiceContext;
      shouldLogInvoiceCustomerErrors = sendCustomerInvoiceEmail;
      const providerConfigured = !!safeStr(env?.RESEND_API_KEY) && !!safeStr(env?.EMAIL_FROM);
      const hasCustomerEmail = !!customerEmail;
      const hasInvoiceEmail = !!adminInvoiceEmail;
      const pickupIso = safeStr(booking?.pickupStartIso || booking?.pickup_iso);
      const pickupParts = brusselsDateTimePartsFromIso(pickupIso);
      const parseNum = (value, fallback = 0) => {
        const num = Number(value);
        return Number.isFinite(num) ? num : fallback;
      };

      if (sendCustomerInvoiceEmail) {
        console.log(
          `[EMAIL][INVOICE_CUSTOMER][START] bookingId=${safeStr(bookingId)} providerConfigured=${providerConfigured} hasCustomerEmail=${hasCustomerEmail} source=payment_update`,
        );
      } else {
        console.log(
          `[EMAIL][INVOICE_CUSTOMER][SKIP] bookingId=${safeStr(bookingId)} reason=private_ride_manual_pdf_flow source=payment_update`,
        );
      }
      console.log(
        `[EMAIL][INVOICE_ADMIN][START] bookingId=${safeStr(bookingId)} providerConfigured=${providerConfigured} hasInvoiceEmail=${hasInvoiceEmail} source=payment_update`,
      );

      if (!booking) {
        if (sendCustomerInvoiceEmail) {
          console.log(
            `[EMAIL][INVOICE_CUSTOMER][ERROR] bookingId=${safeStr(bookingId)} reason=missing_booking_payload`,
          );
        }
        console.log(
          `[EMAIL][INVOICE_ADMIN][ERROR] bookingId=${safeStr(bookingId)} reason=missing_booking_payload`,
        );
      } else {
        if (sendCustomerInvoiceEmail && !hasCustomerEmail) {
          console.log(
            `[EMAIL][INVOICE_CUSTOMER][ERROR] bookingId=${safeStr(bookingId)} reason=missing_customer_email`,
          );
        }
        const invoiceResult = await generateAndSendInvoice({
          env,
          booking: {
            pickupStartIso: pickupIso,
            tripDate: safeStr(booking?.tripDate || booking?.date || pickupParts.date),
            pickupTime: safeStr(booking?.pickupTime || booking?.time || pickupParts.time),
            bookingPublicId: safeStr(booking?.bookingId || bookingId),
            bookingId: safeStr(booking?.booking_uuid || booking?.bookingId || bookingId),
            tenant_id: safeStr(
              booking?.tenant_id ??
                booking?.tenantId ??
                rec?.tenant_id ??
                rec?.tenantId,
              120,
            ),
            company_id: safeStr(
              booking?.company_id ??
                booking?.companyId ??
                rec?.company_id ??
                rec?.companyId,
              120,
            ),
            from: safeStr(booking?.from),
            to: safeStr(booking?.to),
            stops: Array.isArray(booking?.stops) ? booking.stops : [],
            returnTrip: !!booking?.return_enabled,
            routeKm: parseNum(
              booking?.distance_km ??
              booking?.distanceKm ??
              _pick(rec, ["quote", "distance_km"], null),
              0,
            ),
            routeMinutes: parseNum(
              booking?.duration_route_min ??
              booking?.durationRouteMin ??
              _pick(rec, ["quote", "duration_min"], null),
              0,
            ),
            tier: safeStr(booking?.tier),
            service: safeStr(booking?.service),
            pax: parseNum(booking?.pax, 0),
            bags: parseNum(booking?.bags, 0),
            waitMinutes: parseNum(booking?.wait_min, 0),
            customerName: safeStr(booking?.custName || booking?.customer_name || booking?.name),
            customerEmail,
            customerPhone: safeStr(booking?.custPhone || booking?.customer_phone || booking?.phone),
            customerVat: safeStr(booking?.vat_number),
            customerCompany: safeStr(booking?.company_name),
            invoiceAddress: safeStr(booking?.invoice_address),
            vat_rate: parseNum(booking?.vat_rate, 0.06),
            subtotalEx: parseNum(
              booking?.price_ex_vat ?? _pick(rec, ["quote", "pricing", "price_ex_vat"], 0),
              0,
            ),
            vatAmount: parseNum(
              booking?.price_vat ?? _pick(rec, ["quote", "pricing", "price_vat"], 0),
              0,
            ),
            total: parseNum(
              booking?.price_incl_vat ?? _pick(rec, ["quote", "pricing", "price_incl_vat"], 0),
              0,
            ),
            priceMainIncl: parseNum(booking?.price_incl_vat_main, 0),
            priceReturnIncl: parseNum(booking?.price_incl_vat_return, 0),
          },
          emailPolicy: {
            sendCustomerEmail: sendCustomerInvoiceEmail,
            customerSkipReason: sendCustomerInvoiceEmail ? "" : "private_ride_manual_pdf_flow",
          },
        });

        if (invoiceResult?.ok) {
          if (sendCustomerInvoiceEmail) {
            console.log(
              `[EMAIL][INVOICE_CUSTOMER][OK] bookingId=${safeStr(bookingId)} invoiceNumber=${safeStr(invoiceResult?.invoiceNumber)}`,
            );
          }
          const customerInvoiceSent = invoiceResult?.email?.customer?.sent === true;
          if (customerInvoiceSent) {
            const sentAt = new Date().toISOString();
            const sentTo = customerEmail || "";
            const documentType = safeStr(invoiceResult?.documentType || "receipt");
            rec.receipt_email_sent_at = sentAt;
            rec.receipt_email_sent_to = sentTo;
            rec.receipt_email_sent_source = "payment_update_auto";
            rec.receipt_email_document_type = documentType;
            rec.receipt_email_send_context = "automatic_payment_update";
            if (rec.booking && typeof rec.booking === "object") {
              rec.booking.receipt_email_sent_at = sentAt;
              rec.booking.receipt_email_sent_to = sentTo;
              rec.booking.receipt_email_sent_source = "payment_update_auto";
              rec.booking.receipt_email_document_type = documentType;
              rec.booking.receipt_email_send_context = "automatic_payment_update";
            }
          }
          const adminCopySent = invoiceResult?.email?.admin_copy?.sent === true;
          if (adminCopySent || !hasInvoiceEmail) {
            const adminReason = adminCopySent ? "admin_copy_sent" : "missing_admin_recipient";
            const adminTag = adminCopySent ? "OK" : "ERROR";
            console.log(
              `[EMAIL][INVOICE_ADMIN][${adminTag}] bookingId=${safeStr(bookingId)} invoiceNumber=${safeStr(invoiceResult?.invoiceNumber)} reason=${adminReason}`,
            );
          } else {
            console.log(
              `[EMAIL][INVOICE_ADMIN][ERROR] bookingId=${safeStr(bookingId)} invoiceNumber=${safeStr(invoiceResult?.invoiceNumber)} reason=admin_copy_not_sent`,
            );
          }
        } else {
          const invoiceReason = safeStr(invoiceResult?.error || "invoice_generation_failed").slice(0, 160) || "invoice_generation_failed";
          if (sendCustomerInvoiceEmail) {
            console.log(
              `[EMAIL][INVOICE_CUSTOMER][ERROR] bookingId=${safeStr(bookingId)} reason=${invoiceReason}`,
            );
          }
          console.log(
            `[EMAIL][INVOICE_ADMIN][ERROR] bookingId=${safeStr(bookingId)} reason=${invoiceReason}`,
          );
        }
      }
    } catch (invoiceErr) {
      if (shouldLogInvoiceCustomerErrors) {
        console.log(
          `[EMAIL][INVOICE_CUSTOMER][ERROR] bookingId=${safeStr(bookingId)} reason=${safeStr(invoiceErr?.message || invoiceErr).slice(0, 160)}`,
        );
      }
      console.log(
        `[EMAIL][INVOICE_ADMIN][ERROR] bookingId=${safeStr(bookingId)} reason=${safeStr(invoiceErr?.message || invoiceErr).slice(0, 160)}`,
      );
    }
  }

  await env.BOOKING_KV.put(key, JSON.stringify(rec));
  const complianceEvent = buildBookingPaymentUpdateComplianceEvent(rec, bookingId, payment);
  if (complianceEvent) {
    const emitTask = emitComplianceEventBestEffort(env, complianceEvent, {
      timeoutMs: 1500,
      logLabel: "planned_payment_update",
    });
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  } else {
    console.log("[COMPLIANCE_EMIT][planned_payment_update] skipped reason=builder_null");
  }
  return {
    ok: true,
    booking_id: bookingId,
    payment_status: rec.payment_status,
    paymentStatus: rec.paymentStatus,
    paid_at: rec.paid_at || null,
    paidAt: rec.paidAt || null,
    payment_method: rec.payment_method || null,
    paymentMethod: rec.paymentMethod || null,
    payment_source: rec.payment_source || null,
    paymentSource: rec.paymentSource || null,
  };
}

async function handleManualReceiptEmail(request, url, env, bookingId, body = {}) {
  try {
    _requireAdmin(request, url, env);
    const manual = body?.manual === true;
    const sourceRaw = safeStr(body?.source || "manual_unknown");
    const source = sanitizeTenantString(sourceRaw || "manual_unknown", 80) || "manual_unknown";
    const languageRaw = safeStr(body?.language || "").toLowerCase();

    if (!manual) {
      console.log(
        `[EMAIL][RECEIPT_CUSTOMER_MANUAL][SKIP] bookingId=${safeStr(bookingId)} reason=manual_flag_required source=${safeStr(source)}`,
      );
      return {
        ok: false,
        status: "skipped",
        reason: "manual_flag_required",
      };
    }

    const { key, rec } = await loadBookingRecord(env, bookingId);
    const booking = rec?.booking && typeof rec.booking === "object" ? rec.booking : {};
    const bookingLanguageRaw = safeStr(
      booking?.language || booking?.lang || rec?.language || rec?.lang || "nl",
    ).toLowerCase();
    const language = ["nl", "en", "fr", "es"].includes(languageRaw)
      ? languageRaw
      : (["nl", "en", "fr", "es"].includes(bookingLanguageRaw) ? bookingLanguageRaw : "nl");
    const customerEmail = pickFirstValidEmail(
      booking?.custEmail,
      booking?.customer_email,
      booking?.customerEmail,
      booking?.email,
      booking?.customer?.email,
      booking?.customer?.mail,
    );
    const hasCustomerEmail = !!customerEmail;

    console.log(
      `[EMAIL][RECEIPT_CUSTOMER_MANUAL][START] bookingId=${safeStr(bookingId)} hasCustomerEmail=${hasCustomerEmail} source=${safeStr(source)} language=${safeStr(language || "-")}`,
    );

    if (!customerEmail) {
      console.log(
        `[EMAIL][RECEIPT_CUSTOMER_MANUAL][MISSING_EMAIL] bookingId=${safeStr(bookingId)} source=${safeStr(source)}`,
      );
      return {
        ok: false,
        status: "missing_email",
        message: "No customer email found",
      };
    }

    const parseBoolFlag = (value) => {
      if (value === true) return true;
      if (value === false || value == null) return false;
      const raw = String(value).trim().toLowerCase();
      return raw === "1" || raw === "true" || raw === "yes" || raw === "ja" || raw === "y";
    };
    const customerCompany = safeStr(
      booking?.company_name ||
      booking?.companyName ||
      booking?.customer_company ||
      booking?.customerCompany,
    );
    const customerVat = safeStr(
      booking?.vat_number ||
      booking?.vatNumber ||
      booking?.customer_vat ||
      booking?.customerVat,
    );
    const customerInvoiceEmail = pickFirstValidEmail(
      booking?.invoice_email,
      booking?.invoiceEmail,
      booking?.customer_invoice_email,
      booking?.customerInvoiceEmail,
    );
    const invoiceRequested = parseBoolFlag(
      booking?.invoice_requested ??
      booking?.invoiceRequested ??
      rec?.invoice_requested ??
      rec?.invoiceRequested,
    );
    const businessDetected = parseBoolFlag(
      booking?.business_detected ??
      booking?.businessDetected ??
      rec?.business_detected ??
      rec?.businessDetected,
    );
    const businessInvoiceContext =
      invoiceRequested ||
      businessDetected ||
      !!customerCompany ||
      !!customerVat ||
      (!!customerInvoiceEmail && (!!customerCompany || !!customerVat));

    const existingSentAt = safeStr(
      rec?.receipt_email_sent_at ||
      rec?.receiptEmailSentAt ||
      rec?.invoice_email_sent_at ||
      rec?.invoiceEmailSentAt ||
      rec?.customer_invoice_sent_at ||
      rec?.customerInvoiceSentAt ||
      rec?.booking?.receipt_email_sent_at ||
      rec?.booking?.receiptEmailSentAt ||
      rec?.booking?.invoice_email_sent_at ||
      rec?.booking?.invoiceEmailSentAt ||
      rec?.booking?.customer_invoice_sent_at ||
      rec?.booking?.customerInvoiceSentAt,
    );
    if (businessInvoiceContext && existingSentAt) {
      console.log(
        `[EMAIL][RECEIPT_CUSTOMER_MANUAL][ALREADY_SENT] bookingId=${safeStr(bookingId)} sentAt=${safeStr(existingSentAt)} source=${safeStr(source)}`,
      );
      return {
        ok: true,
        status: "already_sent",
        message: "Invoice already sent",
      };
    }

    const pickupIso = safeStr(booking?.pickupStartIso || booking?.pickup_iso);
    const pickupParts = brusselsDateTimePartsFromIso(pickupIso);
    const parseNum = (value, fallback = 0) => {
      const num = Number(value);
      return Number.isFinite(num) ? num : fallback;
    };
    const invoiceInput = {
      pickupStartIso: pickupIso,
      tripDate: safeStr(booking?.tripDate || booking?.date || pickupParts.date),
      pickupTime: safeStr(booking?.pickupTime || booking?.time || pickupParts.time),
      bookingPublicId: safeStr(booking?.bookingId || bookingId),
      bookingId: safeStr(booking?.booking_uuid || booking?.bookingId || bookingId),
      tenant_id: safeStr(
        booking?.tenant_id ??
          booking?.tenantId ??
          rec?.tenant_id ??
          rec?.tenantId,
        120,
      ),
      company_id: safeStr(
        booking?.company_id ??
          booking?.companyId ??
          rec?.company_id ??
          rec?.companyId,
        120,
      ),
      from: safeStr(booking?.from),
      to: safeStr(booking?.to),
      stops: Array.isArray(booking?.stops) ? booking.stops : [],
      returnTrip: !!booking?.return_enabled,
      routeKm: parseNum(
        booking?.distance_km ??
        booking?.distanceKm ??
        _pick(rec, ["quote", "distance_km"], null),
        0,
      ),
      routeMinutes: parseNum(
        booking?.duration_route_min ??
        booking?.durationRouteMin ??
        _pick(rec, ["quote", "duration_min"], null),
        0,
      ),
      tier: safeStr(booking?.tier),
      service: safeStr(booking?.service),
      pax: parseNum(booking?.pax, 0),
      bags: parseNum(booking?.bags, 0),
      waitMinutes: parseNum(booking?.wait_min, 0),
      customerName: safeStr(booking?.custName || booking?.customer_name || booking?.name),
      customerEmail,
      customerPhone: safeStr(booking?.custPhone || booking?.customer_phone || booking?.phone),
      customerVat: safeStr(booking?.vat_number),
      customerCompany: safeStr(booking?.company_name),
      invoiceAddress: safeStr(booking?.invoice_address),
      vat_rate: parseNum(booking?.vat_rate, 0.06),
      subtotalEx: parseNum(
        booking?.price_ex_vat ?? _pick(rec, ["quote", "pricing", "price_ex_vat"], 0),
        0,
      ),
      vatAmount: parseNum(
        booking?.price_vat ?? _pick(rec, ["quote", "pricing", "price_vat"], 0),
        0,
      ),
      total: parseNum(
        booking?.price_incl_vat ?? _pick(rec, ["quote", "pricing", "price_incl_vat"], 0),
        0,
      ),
      priceMainIncl: parseNum(booking?.price_incl_vat_main, 0),
      priceReturnIncl: parseNum(booking?.price_incl_vat_return, 0),
    };
    const invoiceResult = await generateAndSendInvoice({
      env,
      booking: invoiceInput,
      emailPolicy: {
        sendCustomerEmail: true,
        customerSkipReason: "",
        context: "manual_flutter_receipt_button",
        allowManualPrivateCustomerSend: true,
        language: language || undefined,
        source,
      },
    });

    if (!invoiceResult?.ok) {
      const reason = safeStr(invoiceResult?.error || "invoice_generation_failed").slice(0, 160) || "invoice_generation_failed";
      console.log(
        `[EMAIL][RECEIPT_CUSTOMER_MANUAL][ERROR] bookingId=${safeStr(bookingId)} reason=${reason} source=${safeStr(source)}`,
      );
      return {
        ok: false,
        status: "error",
        message: reason,
      };
    }

    const customerSend = invoiceResult?.email?.customer || {};
    if (!customerSend?.sent) {
      const reason = customerSend?.skipped
        ? (safeStr(customerSend?.reason) || "customer_send_skipped")
        : "customer_send_failed";
      console.log(
        `[EMAIL][RECEIPT_CUSTOMER_MANUAL][SKIP] bookingId=${safeStr(bookingId)} reason=${safeStr(reason)} source=${safeStr(source)}`,
      );
      return {
        ok: false,
        status: "skipped",
        reason: safeStr(reason) || "customer_send_skipped",
      };
    }

    const sentAt = new Date().toISOString();
    const documentType = safeStr(invoiceResult?.documentType || "receipt");
    rec.receipt_email_sent_at = sentAt;
    rec.receipt_email_sent_to = customerEmail;
    rec.receipt_email_sent_source = source;
    rec.receipt_email_document_type = documentType;
    rec.receipt_email_send_context = "manual_flutter_receipt_button";
    rec.updatedAt = sentAt;
    if (rec.booking && typeof rec.booking === "object") {
      rec.booking.receipt_email_sent_at = sentAt;
      rec.booking.receipt_email_sent_to = customerEmail;
      rec.booking.receipt_email_sent_source = source;
      rec.booking.receipt_email_document_type = documentType;
      rec.booking.receipt_email_send_context = "manual_flutter_receipt_button";
    }
    await env.BOOKING_KV.put(key, JSON.stringify(rec));

    console.log(
      `[EMAIL][RECEIPT_CUSTOMER_MANUAL][OK] bookingId=${safeStr(bookingId)} recipient=${maskEmailForLog(customerEmail)} sentAt=${sentAt} source=${safeStr(source)}`,
    );
    return {
      ok: true,
      status: "sent",
      booking_id: bookingId,
      recipient: maskEmailForLog(customerEmail),
      sent_at: sentAt,
    };
  } catch (err) {
    const message = safeStr(err?.message || err).slice(0, 200) || "manual_receipt_email_failed";
    console.log(
      `[EMAIL][RECEIPT_CUSTOMER_MANUAL][ERROR] bookingId=${safeStr(bookingId)} reason=${message}`,
    );
    return {
      ok: false,
      status: "error",
      message,
    };
  }
}

async function deleteBookingAuthoritative(bookingId, env, tenantScope = null) {
  if (!tenantScope?.hasScope) {
    return missingTenantScopeError();
  }
  if (!env.BOOKING_KV) throw new Error("BOOKING_KV binding is missing");
  const key = `booking:${bookingId}`;
  const rec = await env.BOOKING_KV.get(key, { type: "json" });
  if (!rec) return { ok: false, error: "Booking not found" };
  if (!bookingMatchesRequestedTenantScope(rec, tenantScope)) {
    return { ok: false, error: "forbidden" };
  }
  await cleanupBookingCalendarEvents(env, rec, tenantScope);
  await releaseAllocatorReservationForBooking({
    env,
    bookingId,
    rec,
    logTag: "RELEASE_ON_DELETE",
  });
  await env.BOOKING_KV.delete(key);
  return { ok: true, booking_id: bookingId, deleted: true };
}

async function cleanupBookingCalendarEvents(env, rec, tenantScope = null) {
  const booking =
    rec?.booking && typeof rec.booking === "object" ? rec.booking : null;
  const calendar =
    rec?.calendar && typeof rec.calendar === "object" ? rec.calendar : null;

  const mainEventId =
    safeStr(rec?.calendar_event_id) ||
    safeStr(rec?.calendarEventId) ||
    safeStr(calendar?.calendar_event_id) ||
    safeStr(calendar?.calendarEventId) ||
    safeStr(booking?.calendar_event_id) ||
    safeStr(booking?.calendarEventId);
  const returnEventId =
    safeStr(rec?.return_event_id) ||
    safeStr(rec?.returnEventId) ||
    safeStr(calendar?.return_event_id) ||
    safeStr(calendar?.returnEventId) ||
    safeStr(booking?.return_event_id) ||
    safeStr(booking?.returnEventId);

  const events = [];
  if (mainEventId) {
    events.push({ kind: "main", eventId: mainEventId });
  }
  if (returnEventId && returnEventId !== mainEventId) {
    events.push({ kind: "return", eventId: returnEventId });
  }
  const attemptedAt = new Date().toISOString();
  const setCalendarCancelMetadata = ({
    status,
    errorCode = null,
    failedAt = null,
    cancelledAt = null,
  }) => {
    const normalizedStatus = safeStr(status || "failed", 40) || "failed";
    const normalizedErrorCode = safeStr(errorCode, 80) || null;
    const normalizedFailedAt = safeStr(failedAt, 64) || null;
    const normalizedCancelledAt = safeStr(cancelledAt, 64) || null;
    rec.calendar_cancel_status = normalizedStatus;
    rec.calendarCancelStatus = normalizedStatus;
    if (normalizedErrorCode) {
      rec.calendar_cancel_error_code = normalizedErrorCode;
      rec.calendarCancelErrorCode = normalizedErrorCode;
    } else {
      rec.calendar_cancel_error_code = null;
      rec.calendarCancelErrorCode = null;
    }
    if (normalizedFailedAt) {
      rec.calendar_cancel_failed_at = normalizedFailedAt;
      rec.calendarCancelFailedAt = normalizedFailedAt;
    }
    if (normalizedCancelledAt) {
      rec.calendar_cancelled_at = normalizedCancelledAt;
      rec.calendarCancelledAt = normalizedCancelledAt;
    }
    if (booking) {
      booking.calendar_cancel_status = normalizedStatus;
      booking.calendarCancelStatus = normalizedStatus;
      if (normalizedErrorCode) {
        booking.calendar_cancel_error_code = normalizedErrorCode;
        booking.calendarCancelErrorCode = normalizedErrorCode;
      } else {
        booking.calendar_cancel_error_code = null;
        booking.calendarCancelErrorCode = null;
      }
      if (normalizedFailedAt) {
        booking.calendar_cancel_failed_at = normalizedFailedAt;
        booking.calendarCancelFailedAt = normalizedFailedAt;
      }
      if (normalizedCancelledAt) {
        booking.calendar_cancelled_at = normalizedCancelledAt;
        booking.calendarCancelledAt = normalizedCancelledAt;
      }
    }
    if (calendar) {
      calendar.calendar_cancel_status = normalizedStatus;
      calendar.calendarCancelStatus = normalizedStatus;
      if (normalizedErrorCode) {
        calendar.calendar_cancel_error_code = normalizedErrorCode;
        calendar.calendarCancelErrorCode = normalizedErrorCode;
      } else {
        calendar.calendar_cancel_error_code = null;
        calendar.calendarCancelErrorCode = null;
      }
      if (normalizedFailedAt) {
        calendar.calendar_cancel_failed_at = normalizedFailedAt;
        calendar.calendarCancelFailedAt = normalizedFailedAt;
      }
      if (normalizedCancelledAt) {
        calendar.calendar_cancelled_at = normalizedCancelledAt;
        calendar.calendarCancelledAt = normalizedCancelledAt;
      }
    }
  };
  if (booking) booking.calendar_clear_attempted_at = attemptedAt;
  if (calendar) calendar.calendar_clear_attempted_at = attemptedAt;
  rec.calendar_clear_attempted_at = attemptedAt;
  if (!events.length) {
    setCalendarCancelMetadata({
      status: "no_event",
      cancelledAt: attemptedAt,
    });
    return;
  }

  const derivedScope = tenantScope?.hasScope
    ? tenantScope
    : resolveBookingTenantScopeFromRecord(rec);
  const calendarAuthConfig = await loadGoogleCalendarAuthConfig(
    env,
    derivedScope?.hasScope ? derivedScope : null,
  );
  const calendarAuthSource = safeStr(calendarAuthConfig?.source, 24) || "none";
  const deleteBookingId = safeStr(
    rec?.booking_id ??
      rec?.bookingId ??
      booking?.booking_id ??
      booking?.bookingId,
    120,
  ) || "unknown";
  console.log(
    `[CALENDAR_AUTH][SOURCE] bookingId=${deleteBookingId} source=${calendarAuthSource} tenant=${derivedScope?.tenant_id || "-"} company=${derivedScope?.company_id || "-"}`,
  );

  if (!calendarAuthConfig?.configured) {
    setCalendarCancelMetadata({
      status: "failed",
      errorCode: "calendar_delete_failed",
      failedAt: attemptedAt,
    });
    return;
  }

  let accessToken = null;
  const calendarId = safeStr(calendarAuthConfig?.calendarId) || "primary";
  try {
    accessToken = await googleAccessTokenFromConfig(calendarAuthConfig);
  } catch (tokenErr) {
    const authError = isGoogleCalendarAuthError(tokenErr);
    setCalendarCancelMetadata({
      status: authError ? "auth_required" : "failed",
      errorCode: authError ? "google_auth_expired" : "calendar_delete_failed",
      failedAt: attemptedAt,
    });
    return;
  }

  let allCleared = true;
  let deleteErrorCode = null;
  for (const item of events) {
    try {
      await googleDeleteEvent(accessToken, calendarId, item.eventId);
      if (item.kind === "main") {
        rec.calendar_event_id = null;
        rec.calendarEventId = null;
        if (calendar) {
          calendar.calendar_event_id = null;
          calendar.calendarEventId = null;
        }
        if (booking) {
          booking.calendar_event_id = null;
          booking.calendarEventId = null;
        }
      } else {
        rec.return_event_id = null;
        rec.returnEventId = null;
        if (calendar) {
          calendar.return_event_id = null;
          calendar.returnEventId = null;
        }
        if (booking) {
          booking.return_event_id = null;
          booking.returnEventId = null;
        }
      }
    } catch (deleteErr) {
      allCleared = false;
      if (!deleteErrorCode) {
        deleteErrorCode = isGoogleCalendarAuthError(deleteErr)
          ? "google_auth_expired"
          : "calendar_delete_failed";
      }
    }
  }

  const remaining =
    safeStr(rec?.calendar_event_id) ||
    safeStr(rec?.calendarEventId) ||
    safeStr(rec?.return_event_id) ||
    safeStr(rec?.returnEventId) ||
    safeStr(calendar?.calendar_event_id) ||
    safeStr(calendar?.calendarEventId) ||
    safeStr(calendar?.return_event_id) ||
    safeStr(calendar?.returnEventId) ||
    safeStr(booking?.calendar_event_id) ||
    safeStr(booking?.calendarEventId) ||
    safeStr(booking?.return_event_id) ||
    safeStr(booking?.returnEventId);
  if (allCleared && !remaining) {
    const clearedAt = new Date().toISOString();
    if (booking) booking.calendar_cleared_at = clearedAt;
    if (calendar) calendar.calendar_cleared_at = clearedAt;
    rec.calendar_cleared_at = clearedAt;
    setCalendarCancelMetadata({
      status: "deleted",
      cancelledAt: clearedAt,
    });
  } else {
    const failedAt = new Date().toISOString();
    setCalendarCancelMetadata({
      status: deleteErrorCode === "google_auth_expired" ? "auth_required" : "failed",
      errorCode: deleteErrorCode || "calendar_delete_failed",
      failedAt,
    });
  }
}

async function handleAvailability(body, env, request = null, url = null) {
  const availabilityMode = _availabilityMode(env);
  const explicitScope = resolveExplicitBookingRequestScope({
    request,
    url,
    body,
    allowLegacyFallback: false,
  });
  const scopedContext = explicitScope?.hasScope ? explicitScope : null;
  const tenantContext =
    scopedContext || resolveBookingTenantContext({ payload: body || {}, request, env });
  const fleetScope = normalizeFleetTenantScope(tenantContext);
  const calendarAuthConfig = await loadGoogleCalendarAuthConfig(env, scopedContext);
  const calendarConfigured = !!calendarAuthConfig?.configured;
  const calendarAuthSource = safeStr(calendarAuthConfig?.source, 24) || "none";
  console.log(
    `[CALENDAR_AUTH][SOURCE] bookingId=- source=${calendarAuthSource} tenant=${tenantContext?.tenant_id || "-"} company=${tenantContext?.company_id || "-"}`,
  );
  // Availability is optional. If Google creds are missing, default to available.
  if (!calendarConfigured) {
    return { ok: true, available: true, calendar_configured: false, build: BUILD_TAG };
  }

  const pickupIsoRaw = (body && (body.pickup_iso || body.pickupIso)) || "";
  if (!pickupIsoRaw) {
    return { ok: false, error: "Missing pickup_iso", build: BUILD_TAG };
  }

  let start;
  try {
    start = new Date(pickupIsoRaw);
    if (Number.isNaN(start.getTime())) throw new Error("Invalid date");
  } catch {
    return { ok: false, error: "Invalid pickup_iso", build: BUILD_TAG };
  }

  const timeMin = start.toISOString();
  const timeMax = new Date(start.getTime() + 60 * 1000).toISOString(); // 1-minute window

  const vehicleCapacity = await _vehicleCapacityGateForRequest(env, {
    pickupMs: Date.parse(timeMin),
    serviceMin: Math.max(
      30,
      Math.round(
        Number(body?.duration_min ?? body?.duration_route_min ?? body?.durationMin ?? 0) +
          Number(body?.wait_min ?? body?.wait_minutes ?? body?.waitMin ?? 0) +
          15,
      ),
    ),
    tier: normalizeTier(body?.tier || "comfort"),
    pax: clampInt(body?.pax, 1, 99),
    bags: Math.max(0, clampInt(body?.bags, 0, 99)),
    tenantScope: fleetScope,
  });
  if (!vehicleCapacity.ok) {
    return {
      ok: true,
      available: false,
      reason: "vehicle_capacity",
      vehicle_capacity: vehicleCapacity,
      availability_mode: availabilityMode,
      calendar_configured: calendarConfigured,
      build: BUILD_TAG,
    };
  }

  if (availabilityMode === "multi_vehicle") {
    return {
      ok: true,
      available: true,
      reason: "vehicle_capacity_ok",
      vehicle_capacity: vehicleCapacity,
      availability_mode: availabilityMode,
      calendar_configured: calendarConfigured,
      build: BUILD_TAG,
    };
  }

  const accessToken = await googleAccessTokenFromConfig(calendarAuthConfig);
  const calendarId = safeStr(calendarAuthConfig?.calendarId) || "primary";

  // 1) Basic free/busy check for the pickup moment
  const busy = await googleFreeBusy(accessToken, calendarId, timeMin, timeMax);
  if (busy && busy.length) {
    return {
      ok: true,
      available: false,
      reason: "busy",
      busy,
      calendar_configured: true,
      build: BUILD_TAG,
    };
  }

  // 2) Travel gap check from previous event location -> new pickup (plus margin)
  //    This uses your existing helper that already applies the +15 min (or configured) margin.
  const pickupFromText = (body && (body.from || body.pickup_from || body.pickupFrom)) || "";
  const gapCheck = await ensureTravelGapFromPreviousEvent({
    accessToken,
    calendarId,
    pickupIso: timeMin,
    pickupFromText,
    env,
  });

  if (!gapCheck || gapCheck.ok === false) {
    return gapCheck || { ok: false, error: "availability check failed", build: BUILD_TAG };
  }

  if (gapCheck.available === false) {
    return { ...gapCheck, calendar_configured: true, build: BUILD_TAG };
  }

  return { ok: true, available: true, calendar_configured: true, build: BUILD_TAG };
}


async function googleFreeBusy(accessToken, calendarId, timeMinIso, timeMaxIso) {
  const url = "https://www.googleapis.com/calendar/v3/freeBusy";
  const payload = { timeMin: timeMinIso, timeMax: timeMaxIso, items: [{ id: calendarId }] };

  const r = await fetch(url, {
    method: "POST",
    headers: { "authorization": `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify(payload)
  });

  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j?.error?.message || "Google freeBusy failed.");

  const cal = j?.calendars?.[calendarId];
  return cal?.busy || [];
}

async function googleCreateEvent(accessToken, calendarId, event) {
  const url = `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}/events`;

  const r = await fetch(url, {
    method: "POST",
    headers: { "authorization": `Bearer ${accessToken}`, "content-type": "application/json" },
    body: JSON.stringify(event)
  });

  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j?.error?.message || "Google create event failed.");
  return j;
}

async function googleDeleteEvent(accessToken, calendarId, eventId) {
  const url =
    `https://www.googleapis.com/calendar/v3/calendars/${encodeURIComponent(calendarId)}` +
    `/events/${encodeURIComponent(eventId)}`;

  const r = await fetch(url, {
    method: "DELETE",
    headers: { "authorization": `Bearer ${accessToken}` },
  });

  if ([200, 204, 404, 410].includes(r.status)) {
    return { ok: true, status: r.status };
  }

  const j = await r.json().catch(() => ({}));
  throw new Error(j?.error?.message || `Google delete event failed (${r.status})`);
}


/* ===================== BOOKING ID (HUMAN) ===================== */

// Generates human-friendly sequential IDs like 2026-01-001.
// Uses BOOKING_KV as a lightweight counter store (OK for low volume).
async function nextHumanBookingId(env, pickupIso) {
  if (!env?.BOOKING_KV) throw new Error("Missing BOOKING_KV binding (needed for booking ids)");
  const parts = brusselsDateTimePartsFromIso(pickupIso || new Date().toISOString());

  // parts.date is usually dd/mm/yyyy
  let yyyy = "";
  let mm = "";

  if (safeStr(parts?.date).includes("/")) {
    const a = String(parts.date).split("/");
    if (a.length === 3) {
      yyyy = a[2];
      mm = a[1];
    }
  }

  if (!yyyy || !mm) {
    const m = safeStr(parts?.date).match(/^([0-9]{4})-([0-9]{2})-/);
    if (m) { yyyy = m[1]; mm = m[2]; }
  }

  if (!yyyy || !mm) {
    const d = new Date();
    yyyy = String(d.getUTCFullYear());
    mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  }

  const counterKey = `seq:${yyyy}-${mm}`;
  const maxTries = 6;

  for (let i = 0; i < maxTries; i++) {
    const curRaw = await env.BOOKING_KV.get(counterKey);
    const cur = clampInt(curRaw, 0, 0, 999999);
    const next = cur + 1;
    await env.BOOKING_KV.put(counterKey, String(next));

    const id = `${yyyy}-${mm}-${String(next).padStart(3, "0")}`;
    const exists = await env.BOOKING_KV.get(`booking:${id}`);
    if (!exists) return id;
  }

  return `${yyyy}-${mm}-${String(Date.now()).slice(-6)}`;
}

function normalizeBookingReferenceYearMonth(value) {
  const raw = safeStr(value);
  if (!raw) return "";
  const m = raw.match(/^([0-9]{4})-([0-9]{2})$/);
  if (!m) return "";
  return `${m[1]}-${m[2]}`;
}

function bookingReferenceYearMonthFromPickupIso(pickupIso) {
  const parts = brusselsDateTimePartsFromIso(pickupIso || new Date().toISOString());
  let yyyy = "";
  let mm = "";

  if (safeStr(parts?.date).includes("/")) {
    const seg = String(parts.date).split("/");
    if (seg.length === 3) {
      yyyy = safeStr(seg[2]);
      mm = safeStr(seg[1]).padStart(2, "0");
    }
  }

  if (!yyyy || !mm) {
    const m = safeStr(parts?.date).match(/^([0-9]{4})-([0-9]{2})-/);
    if (m) {
      yyyy = m[1];
      mm = m[2];
    }
  }

  if (!yyyy || !mm) {
    const d = new Date();
    yyyy = String(d.getUTCFullYear());
    mm = String(d.getUTCMonth() + 1).padStart(2, "0");
  }

  return `${yyyy}-${mm}`;
}

function normalizeDocumentReferenceYear(value) {
  const raw = safeStr(value);
  if (!raw) return "";
  const m = raw.match(/^([0-9]{4})$/);
  if (!m) return "";
  return m[1];
}

function documentReferenceYearFromPickupIso(pickupIso) {
  // Keep the same Brussels/business date source that booking references use.
  const parts = brusselsDateTimePartsFromIso(pickupIso || new Date().toISOString());
  let yyyy = "";

  if (safeStr(parts?.date).includes("/")) {
    const seg = String(parts.date).split("/");
    if (seg.length === 3) {
      yyyy = safeStr(seg[2]);
    }
  }

  if (!yyyy) {
    const m = safeStr(parts?.date).match(/^([0-9]{4})-([0-9]{2})-/);
    if (m) {
      yyyy = m[1];
    }
  }

  if (!yyyy) {
    const d = new Date();
    yyyy = String(d.getUTCFullYear());
  }

  return yyyy;
}

function bookingReferenceScopePart(value, fallback) {
  const raw = safeStr(value, 120).toLowerCase();
  if (!raw) return fallback;
  const normalized = raw.replace(/[^a-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return normalized || fallback;
}

function bookingReferenceScopeName(tenantId, companyId, yearMonth) {
  const tenantPart = bookingReferenceScopePart(tenantId, "fluxidi");
  const companyPart = bookingReferenceScopePart(companyId || tenantId, tenantPart);
  return `booking_ref:${tenantPart}:${companyPart}:${yearMonth}`;
}

function documentReferenceTypePart(value, fallback) {
  const raw = safeStr(value, 64).toLowerCase();
  if (!raw) return fallback;
  const normalized = raw.replace(/[^a-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "");
  return normalized || fallback;
}

function documentReferenceScopeName(tenantId, companyId, sequenceType, year) {
  const tenantPart = bookingReferenceScopePart(tenantId, "fluxidi");
  const companyPart = bookingReferenceScopePart(companyId || tenantId, tenantPart);
  const typePart = documentReferenceTypePart(sequenceType, "generic");
  return `doc_ref_seq:${tenantPart}:${companyPart}:${typePart}:${year}`;
}

function attachPublicBookingReferenceAliases(target, publicBookingReference) {
  if (!target || typeof target !== "object") return target;
  const value = safeStr(publicBookingReference);
  if (!value) return target;
  target.public_booking_reference = value;
  target.publicBookingReference = value;
  target.booking_reference = value;
  target.bookingReference = value;
  target.public_reference = value;
  target.publicReference = value;
  return target;
}

function attachPlanningReferenceAliases(target, planningReference) {
  if (!target || typeof target !== "object") return target;
  const value = safeStr(planningReference);
  if (!value) return target;
  target.planning_reference = value;
  target.planningReference = value;
  return target;
}

async function allocatePublicBookingReference(env, params = {}) {
  if (!env?.BOOKING_REFERENCE_SEQUENCE) {
    throw new Error("Missing BOOKING_REFERENCE_SEQUENCE binding");
  }
  const tenantId = safeStr(params?.tenant_id, 120) || "fluxidi";
  const companyId = safeStr(params?.company_id, 120) || tenantId;
  const yearMonth =
    normalizeBookingReferenceYearMonth(params?.year_month || params?.yearMonth) ||
    bookingReferenceYearMonthFromPickupIso(
      params?.pickup_iso || params?.pickupIso || new Date().toISOString(),
    );
  if (!yearMonth) throw new Error("Cannot allocate public booking reference: missing yearMonth");

  const instanceName = bookingReferenceScopeName(tenantId, companyId, yearMonth);
  const stub = env.BOOKING_REFERENCE_SEQUENCE.get(
    env.BOOKING_REFERENCE_SEQUENCE.idFromName(instanceName),
  );
  const resp = await stub.fetch("https://do/allocate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      action: "allocate",
      tenant_id: tenantId,
      company_id: companyId,
      year_month: yearMonth,
      pickup_iso: params?.pickup_iso || params?.pickupIso || null,
    }),
  });
  const body = await resp.json().catch(() => ({}));
  const publicBookingReference = safeStr(
    body?.public_booking_reference ||
      body?.publicBookingReference ||
      body?.booking_reference ||
      body?.bookingReference,
  );
  if (!resp.ok || !publicBookingReference) {
    throw new Error(
      safeStr(body?.error) || `Public booking reference allocation failed (${resp.status})`,
    );
  }
  return publicBookingReference;
}

async function allocateAndReservePublicBookingReference(env, params = {}) {
  const tenantId = safeStr(params?.tenant_id, 120) || "fluxidi";
  const companyId = safeStr(params?.company_id, 120) || tenantId;
  const canonicalBookingId = safeStr(
    params?.canonical_booking_id || params?.canonicalBookingId || params?.booking_id,
  );
  if (!canonicalBookingId) {
    throw new Error("Missing canonical booking id for public booking reference allocation");
  }

  const maxAttempts = clampInt(params?.max_attempts, 10, 20);
  let candidate = safeStr(
    params?.preferred_reference ||
      params?.public_booking_reference ||
      params?.publicBookingReference,
  );

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (!candidate) {
      candidate = await allocatePublicBookingReference(env, {
        tenant_id: tenantId,
        company_id: companyId,
        pickup_iso: params?.pickup_iso || params?.pickupIso || null,
        year_month: params?.year_month || params?.yearMonth || null,
      });
    }

    const indexed = await putPublicBookingReferenceIndex(env, {
      tenant_id: tenantId,
      company_id: companyId,
      public_booking_reference: candidate,
      canonical_booking_id: canonicalBookingId,
    });
    if (indexed?.ok) return candidate;
    if (!indexed?.collision) {
      throw new Error(
        safeStr(indexed?.error) || "Failed to reserve public booking reference index",
      );
    }
    candidate = "";
  }

  throw new Error(
    `Public booking reference allocation failed after ${maxAttempts} attempts (tenant=${tenantId}, company=${companyId})`,
  );
}

async function putPublicBookingReferenceIndex(env, params = {}) {
  if (!env?.BOOKING_KV) return { ok: false, error: "Missing BOOKING_KV binding" };
  const tenantPart = bookingReferenceScopePart(params?.tenant_id, "fluxidi");
  const companyPart = bookingReferenceScopePart(params?.company_id || params?.tenant_id, tenantPart);
  const publicBookingReference = safeStr(
    params?.public_booking_reference || params?.publicBookingReference,
  );
  const canonicalBookingId = safeStr(
    params?.canonical_booking_id || params?.canonicalBookingId || params?.booking_id,
  );
  if (!publicBookingReference || !canonicalBookingId) {
    return { ok: false, error: "Missing public_booking_reference or canonical booking id" };
  }

  const key = `booking_ref:${tenantPart}:${companyPart}:${publicBookingReference}`;
  const existing = safeStr(await env.BOOKING_KV.get(key));
  if (existing && existing !== canonicalBookingId) {
    return { ok: false, collision: true, existing, key };
  }
  await env.BOOKING_KV.put(key, canonicalBookingId);
  return { ok: true, key, existing: existing || canonicalBookingId };
}

async function allocateDocumentReference(env, params = {}) {
  if (!env?.DOCUMENT_REFERENCE_SEQUENCE) {
    throw new Error("Missing DOCUMENT_REFERENCE_SEQUENCE binding");
  }
  const tenantId = safeStr(params?.tenant_id, 120) || "fluxidi";
  const companyId = safeStr(params?.company_id, 120) || tenantId;
  const sequenceType = documentReferenceTypePart(
    params?.sequence_type || params?.sequenceType || params?.type,
    "",
  );
  if (!sequenceType) throw new Error("Cannot allocate document reference: missing sequence_type");
  const prefix = safeStr(params?.prefix || params?.reference_prefix || params?.referencePrefix, 16).toUpperCase();
  if (!prefix) throw new Error("Cannot allocate document reference: missing prefix");
  const year =
    normalizeDocumentReferenceYear(params?.year) ||
    documentReferenceYearFromPickupIso(params?.pickup_iso || params?.pickupIso || new Date().toISOString());
  if (!year) throw new Error("Cannot allocate document reference: missing year");

  const instanceName = documentReferenceScopeName(tenantId, companyId, sequenceType, year);
  const stub = env.DOCUMENT_REFERENCE_SEQUENCE.get(
    env.DOCUMENT_REFERENCE_SEQUENCE.idFromName(instanceName),
  );
  const resp = await stub.fetch("https://do/allocate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      action: "allocate",
      tenant_id: tenantId,
      company_id: companyId,
      sequence_type: sequenceType,
      prefix,
      year,
      pickup_iso: params?.pickup_iso || params?.pickupIso || null,
    }),
  });
  const body = await resp.json().catch(() => ({}));
  const documentReference = safeStr(body?.document_reference || body?.documentReference);
  if (!resp.ok || !documentReference) {
    throw new Error(
      safeStr(body?.error) || `Document reference allocation failed (${resp.status})`,
    );
  }
  return documentReference;
}

async function putDocumentReferenceIndex(env, params = {}) {
  if (!env?.BOOKING_KV) return { ok: false, error: "Missing BOOKING_KV binding" };
  const tenantPart = bookingReferenceScopePart(params?.tenant_id, "fluxidi");
  const companyPart = bookingReferenceScopePart(params?.company_id || params?.tenant_id, tenantPart);
  const sequenceType = documentReferenceTypePart(
    params?.sequence_type || params?.sequenceType || params?.type,
    "",
  );
  const documentReference = safeStr(
    params?.document_reference || params?.documentReference || params?.reference,
  );
  const canonicalBookingId = safeStr(
    params?.canonical_booking_id || params?.canonicalBookingId || params?.booking_id,
  );
  if (!sequenceType || !documentReference || !canonicalBookingId) {
    return {
      ok: false,
      error: "Missing sequence_type, document_reference, or canonical booking id",
    };
  }

  const key = `doc_ref:${tenantPart}:${companyPart}:${sequenceType}:${documentReference}`;
  const existing = safeStr(await env.BOOKING_KV.get(key));
  if (existing && existing !== canonicalBookingId) {
    return { ok: false, collision: true, existing, key };
  }
  await env.BOOKING_KV.put(key, canonicalBookingId);
  return { ok: true, key, existing: existing || canonicalBookingId };
}

async function allocateAndReserveDocumentReference(env, params = {}) {
  const tenantId = safeStr(params?.tenant_id, 120) || "fluxidi";
  const companyId = safeStr(params?.company_id, 120) || tenantId;
  const sequenceType = documentReferenceTypePart(
    params?.sequence_type || params?.sequenceType || params?.type,
    "",
  );
  if (!sequenceType) {
    throw new Error("Missing sequence_type for document reference allocation");
  }
  const canonicalBookingId = safeStr(
    params?.canonical_booking_id || params?.canonicalBookingId || params?.booking_id,
  );
  if (!canonicalBookingId) {
    throw new Error("Missing canonical booking id for document reference allocation");
  }
  const maxAttempts = clampInt(params?.max_attempts, 10, 20);
  let candidate = safeStr(
    params?.preferred_reference ||
      params?.document_reference ||
      params?.documentReference,
  );

  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    if (!candidate) {
      candidate = await allocateDocumentReference(env, {
        tenant_id: tenantId,
        company_id: companyId,
        sequence_type: sequenceType,
        prefix: params?.prefix,
        year: params?.year,
        pickup_iso: params?.pickup_iso || params?.pickupIso || null,
      });
    }

    const indexed = await putDocumentReferenceIndex(env, {
      tenant_id: tenantId,
      company_id: companyId,
      sequence_type: sequenceType,
      document_reference: candidate,
      canonical_booking_id: canonicalBookingId,
    });
    if (indexed?.ok) return candidate;
    if (!indexed?.collision) {
      throw new Error(
        safeStr(indexed?.error) || "Failed to reserve document reference index",
      );
    }
    candidate = "";
  }

  throw new Error(
    `Document reference allocation failed after ${maxAttempts} attempts (tenant=${tenantId}, company=${companyId}, type=${sequenceType})`,
  );
}

/* ===================== PUSHBULLET ===================== */

async function sendPushbulletNote(env, { title, body, device_iden = "" }) {
  const token = safeStr(env.PUSHBULLET_TOKEN);
  if (!token) {
    return { enabled: false, sent: false, warning: "Missing PUSHBULLET_TOKEN" };
  }

  const payload = {
    type: "note",
    title: String(title || "Fluxidi Taxi"),
    body: String(body || ""),
  };

  const forcedDevice = safeStr(device_iden || env.PUSHBULLET_DEVICE_IDEN);
  if (forcedDevice) payload.device_iden = forcedDevice;

  try {
    const r = await fetch("https://api.pushbullet.com/v2/pushes", {
      method: "POST",
      headers: {
        "Access-Token": token,
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j?.error?.message || j?.error || "Pushbullet push failed");

    return { enabled: true, sent: true, iden: j?.iden || null };
  } catch (e) {
    return { enabled: true, sent: false, error: String(e?.message || e) };
  }
}

/* ===================== EMAIL (RESEND) ===================== */

async function sendBookingEmails({ env, booking }) {
  const apiKey = safeStr(env.RESEND_API_KEY);
  const emailFrom = safeStr(env.EMAIL_FROM);
  const commProfile = await resolveTenantCommunicationProfile(
    env,
    safeStr(booking?.tenant_id ?? booking?.tenantId, 80),
    safeStr(booking?.company_id ?? booking?.companyId, 80),
  );
  const ownerEmail = pickFirstValidEmail(
    commProfile.bookingEmail,
    commProfile.notificationEmail,
    commProfile.companyEmail,
    commProfile.invoiceEmail,
    env.OWNER_EMAIL,
  );
  const replyTo = pickFirstValidEmail(
    commProfile.replyToEmail,
    commProfile.companyEmail,
    commProfile.supportEmail,
    commProfile.invoiceEmail,
    env.EMAIL_REPLY_TO,
  );

  if (!apiKey || !emailFrom) {
    return {
      enabled: false,
      sent_owner: false,
      sent_customer: false,
      warning: "Email not configured (missing RESEND_API_KEY / EMAIL_FROM)."
    };
  }

  const customerTo = pickFirstValidEmail(
    booking?.custEmail,
    booking?.customerEmail,
    booking?.customer_email,
    booking?.email,
  );
  const hasCustomerEmail = !!customerTo;
  const hasBookingEmail = !!ownerEmail;
  const providerConfigured = !!apiKey && !!emailFrom;
  const bookingRef = safeStr(booking?.bookingId || booking?.booking_id);
  const languageInfo = normalizeCustomerEmailLanguage({
    language: booking.customerLanguageDetected || booking.customerLanguage,
  });
  const detectedLanguage = safeStr(languageInfo.detectedLanguage);
  const normalizedLanguage = languageInfo.normalizedLanguage;
  const fallbackUsed = languageInfo.fallbackUsed;
  console.log(
    `[EMAIL_LANG][CONFIRMATION] bookingId=${safeStr(booking.bookingId)} detectedLanguage=${detectedLanguage || "-"} normalizedLanguage=${normalizedLanguage} fallbackUsed=${fallbackUsed}`
  );

  const brandName = safeBrandName(commProfile.brandName, "Fluxidi Taxi");
  const subjectOwner = `🚖 Nieuwe ${brandName} booking — ${fmtLocalNLFromIso(booking.pickupStartIso)}`;
  const subjectCustomer = customerConfirmationSubject(booking, normalizedLanguage, commProfile);

  const ownerHtml = renderOwnerEmailHtml(booking, commProfile);
  const customerHtml = renderCustomerEmailHtml(booking, normalizedLanguage, commProfile);

  const headers = { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" };

  const basePayload = (to, subject, html, cc = null) => ({
    from: emailFrom,
    to: [to],
    subject,
    html,
    ...(replyTo ? { reply_to: replyTo } : {}),
    ...(cc && cc.length ? { cc } : {})
  });

  let sentOwner = false;
  let sentCustomer = false;
  let errors = [];

  console.log(
    `[EMAIL][BOOKING_ADMIN][START] bookingId=${bookingRef} providerConfigured=${providerConfigured} hasBookingEmail=${hasBookingEmail}`,
  );
  if (!ownerEmail) {
    console.log(
      `[EMAIL][BOOKING_ADMIN][ERROR] bookingId=${bookingRef} reason=missing_booking_email`,
    );
    errors.push("Missing booking/admin notification email.");
  } else {
    try {
      const r1 = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers,
        body: JSON.stringify(basePayload(ownerEmail, subjectOwner, ownerHtml))
      });
      const j1 = await r1.json().catch(() => ({}));
      if (!r1.ok) throw new Error(j1?.message || "Resend owner mail failed");
      sentOwner = true;
      console.log(
        `[EMAIL][BOOKING_ADMIN][OK] bookingId=${bookingRef}`,
      );
    } catch (e) {
      console.log(
        `[EMAIL][BOOKING_ADMIN][ERROR] bookingId=${bookingRef} reason=${safeStr(e?.message || e).slice(0, 160)}`,
      );
      errors.push(String(e?.message || e));
    }
  }

  console.log(
    `[EMAIL][BOOKING_CUSTOMER][SKIP] bookingId=${bookingRef} reason=cost_control_customer_confirmation_disabled`,
  );

  return {
    enabled: true,
    sent_owner: sentOwner,
    sent_customer: sentCustomer,
    errors: errors.length ? errors : null
  };
}

function renderOwnerEmailHtml(b, commProfile = null) { 
  const brandName = safeBrandName(commProfile?.brandName, "Fluxidi Taxi");
  const route = renderRouteTextWithReturn(b);

  const stopCount = Array.isArray(b.stops) ? b.stops.length : 0;
  const retourText = b.return_enabled
    ? (b.return_forced_by_wait ? "JA" : "JA")
    : "NEE";

  const bizBlock = b.business_detected ? `
    <p style="margin:8px 0 0"><b>Zakelijk</b>: JA • <b>Bedrijf</b>: ${escapeHtml(b.company_name || "-")} • <b>BTW</b>: ${escapeHtml(b.vat_number || "-")} • <b>Factuur</b>: ${b.invoice_requested ? "JA" : "NEE"}</p>
  ` : "";

  const choices = [
    `Service: ${humanServiceLabel(b.service)}`,
    `Ritniveau: ${escapeHtml(String(b.tier || "").toUpperCase())}`,
    `Pax: ${escapeHtml(String(b.pax ?? "-"))}`,
    `Koffers: ${escapeHtml(String(b.bags ?? "-"))} (€5/koffer)`,
    `Wachttijd: ${escapeHtml(String(b.wait_min ?? 0))} min`,
    `Retourrit: ${escapeHtml(retourText)}`,
    ...(b.return_enabled && b.returnPickupIso ? [`Retour tijd: ${escapeHtml(whenFromPickupIsoBrussels(b.returnPickupIso))}`] : []),
    `Tussenstops: ${escapeHtml(String(stopCount))}`,
    ...(b.extra_service_label ? [`Extra service: ${escapeHtml(b.extra_service_label)}`] : [])
  ].join(" • ");

  // Basic price breakdown (we keep it readable for owner too)
  const priceLines = `
    <div style="margin-top:10px;padding:10px;border:1px dashed #ddd;border-radius:10px;background:#fff">
      <div style="font-weight:700;margin:0 0 6px">Prijs</div>
      <div style="color:#111;margin:0 0 4px">Totaal: <b>€${Number(b.price_incl_vat || 0).toFixed(2)}</b> incl btw</div>
      <div style="color:#555;margin:0">Ex btw: €${Number(b.price_ex_vat || 0).toFixed(2)} • BTW: €${Number(b.price_vat || 0).toFixed(2)} • tarief ${(Number(b.vat_rate || 0) * 100).toFixed(0)}%</div>
    </div>
  `;
  // Technische planning details worden enkel intern bijgehouden (agenda).
  const techLines = ``;

  return `
  <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial;line-height:1.5">
    <h2 style="margin:0 0 10px">🚖 Nieuwe ${escapeHtml(brandName)} booking</h2>
    <p style="margin:0 0 12px;color:#444"><b>Booking ID</b>: ${escapeHtml(b.bookingId || "-")}<br/>Pickup: <b>${escapeHtml(fmtLocalNLFromIso(b.pickupStartIso))}</b></p>

    <div style="padding:12px;border:1px solid #eee;border-radius:10px;background:#fafafa">
      <p style="margin:0 0 6px"><b>Klant</b>: ${escapeHtml(b.custName)} — ${escapeHtml(b.custPhone)} — ${escapeHtml(b.custEmail)}</p>
      ${bizBlock}
      <p style="margin:8px 0 6px"><b>Keuzes</b>: ${choices}</p>
      <p style="margin:0 0 6px"><b>Route</b>: ${escapeHtml(route)}</p>
      ${stopCount ? `<div style="margin:0 0 6px;color:#333"><b>Tussenstops</b>:<br/>${(b.stops || []).map(s => `• ${escapeHtml(String(s))}`).join("<br/>")}</div>` : ""}
    </div>

    ${priceLines}
    ${techLines}

    ${b.eventLink ? `<p style="margin:12px 0 0"><a href="${escapeHtml(b.eventLink)}">Open in Google Calendar</a></p>` : ""}
  </div>
  `;
}

function customerConfirmationSubject(b, lang, commProfile = null) {
  const t = customerEmailText(lang);
  const prefix = b.business_detected ? t.subjectBusiness : t.subjectPrivate;
  const brandName = safeBrandName(commProfile?.brandName, "Fluxidi Taxi");
  return `${prefix} — ${brandName} 🚖 — ${fmtLocalNLFromIso(b.pickupStartIso)}`;
}

function renderCustomerEmailHtml(b, lang = "nl", commProfile = null) {
  const t = customerEmailText(lang);
  const route = renderRouteTextWithReturnLocalized(b, lang);

  const stopCount = Array.isArray(b.stops) ? b.stops.length : 0;
  const retourText = b.return_enabled ? t.yes : t.no;

  const intro = b.business_detected
    ? `${t.greeting(escapeHtml(b.custName || ""))} ${t.introBusiness}`
    : `${t.greeting(escapeHtml(b.custName || ""))} ${t.introPrivate}`;

  // Always show choices (both B2C + B2B)
  const choicesList = `
    <ul style="margin:10px 0 0;padding-left:18px;color:#333">
      <li><b>${t.service}</b>: ${escapeHtml(customerEmailServiceLabel(b.service, lang))}</li>
      <li><b>${t.tier}</b>: ${escapeHtml(customerEmailTierLabel(b.tier))}</li>
      <li><b>${t.returnTrip}</b>: ${escapeHtml(retourText)}</li>
      ${b.return_enabled && b.returnPickupIso ? `<li><b>${t.returnTime}</b>: ${escapeHtml(fmtLocalNLFromIso(b.returnPickupIso))}</li>` : ""}
      <li><b>${t.stops}</b>: ${escapeHtml(String(stopCount))}${stopCount ? ` — ${escapeHtml(String((b.stops || []).join(" • ")))}` : ""}</li>
      <li><b>${t.passengers}</b>: ${escapeHtml(String(b.pax ?? "-"))}</li>
      <li><b>${t.bags}</b>: ${escapeHtml(String(b.bags ?? "-"))} (€5/${t.bagFee})</li>
      <li><b>${t.waitingTime}</b>: ${escapeHtml(String(b.wait_min ?? 0))} min</li>
      ${b.extra_service_label ? `<li><b>${t.extraService}</b>: ${escapeHtml(b.extra_service_label)}</li>` : ""}
    </ul>
  `;

  // Price breakdown (simple + clear)
  const priceBlock = `
    <div style="margin-top:12px;padding:12px;border:1px solid #eee;border-radius:12px;background:#fafafa">
      <div style="font-weight:800;margin:0 0 8px">${t.price}</div>
      <div style="margin:0 0 6px;color:#111">${t.total}: <b>€${Number(b.price_incl_vat || 0).toFixed(2)}</b> ${t.inclVat}</div>
      <div style="color:#555;font-size:13px">
        ${t.exclVat}: €${Number(b.price_ex_vat || 0).toFixed(2)} • ${t.vat}: €${Number(b.price_vat || 0).toFixed(2)} • ${t.rate} ${(Number(b.vat_rate || 0) * 100).toFixed(0)}%
      </div>
    </div>
  `;

  // Business block only if B2B detected
  const bizBox = b.business_detected ? `
    <div style="margin-top:12px;padding:12px;border:1px solid rgba(255,200,0,.35);border-radius:12px;background:#fffdf2">
      <div style="font-weight:800;margin:0 0 6px">${t.businessDetails}</div>
      <div style="color:#333;font-size:14px;line-height:1.5">
        <b>${t.company}</b>: ${escapeHtml(b.company_name || "-")}<br/>
        <b>${t.vat}</b>: ${escapeHtml(b.vat_number || "-")}<br/>
        <b>${t.invoice}</b>: ${b.invoice_requested ? t.invoiceYes : t.invoiceNo}
      </div>
    </div>
  ` : "";

  const footerText = safeStr(commProfile?.receiptFooter) || safeStr(commProfile?.invoiceFooter) || t.footer;

  return `
  <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial;line-height:1.55">
    <h2 style="margin:0 0 10px">${b.business_detected ? t.headingBusiness : t.headingPrivate} 🚖</h2>
    <p style="margin:0 0 10px;color:#444">${intro}</p>

    <div style="padding:12px;border:1px solid #eee;border-radius:12px;background:#ffffff">
      <div style="margin:0 0 8px"><b>${t.bookingId}</b>: ${escapeHtml(b.bookingId || "-")}</div>
      <div style="margin:0 0 8px"><b>${t.pickup}</b>: ${escapeHtml(fmtLocalNLFromIso(b.pickupStartIso))}</div>
      <div style="margin:0 0 8px"><b>${t.route}</b>: ${escapeHtml(route)}</div>
      <div style="margin:0 0 6px"><b>${t.choices}</b>:</div>
      ${choicesList}
      ${priceBlock}
      ${bizBox}
    </div>

    <p style="margin:12px 0 0;color:#555">
      ${t.contact}
    </p>

    <p style="margin:12px 0 0;color:#999;font-size:12px">
      ${escapeHtml(footerText)}
    </p>
  </div>
  `;
}
function renderRouteTextWithReturnLocalized(b, lang = "nl") {
  const t = customerEmailText(lang);
  const outbound = renderRouteTextLocalized(b.from, b.stops || [], b.to, lang);
  if (!b.return_enabled) return outbound;
  const rf = b.return_from || b.to;
  const rt = b.return_to || b.from;
  const back = renderRouteTextLocalized(rf, [], rt, lang);
  return `${outbound} | ${t.returnTrip}: ${back}`;
}

function renderRouteTextLocalized(from, stops, to, lang = "nl") {
  const t = customerEmailText(lang);
  const parts = [];
  if (from) parts.push(`${t.from}: ${from}`);
  if (Array.isArray(stops) && stops.length) {
    parts.push(`${t.stops}: ${stops.join(" • ")}`);
  }
  if (to) parts.push(`${t.destination}: ${to}`);
  return parts.join(" → ");
}
function renderRouteTextWithReturn(b) {
  const outbound = renderRouteText(b.from, b.stops || [], b.to);
  if (!b.return_enabled) return outbound;
  const rf = b.return_from || b.to;
  const rt = b.return_to || b.from;
  const back = renderRouteText(rf, [], rt);
  return `${outbound} | Retour: ${back}`;
}

function renderRouteText(from, stops, to) {
  const pts = [from, ...(Array.isArray(stops) ? stops : []), to].filter(Boolean);
  return pts.join(" → ");
}

function fmtWhenFromIso(pickupIso) {
  try {
    const d = new Date(pickupIso);
    const dd = String(d.getDate()).padStart(2, "0");
    const mm = String(d.getMonth() + 1).padStart(2, "0");
    const yyyy = String(d.getFullYear());
    const hh = String(d.getHours()).padStart(2, "0");
    const mi = String(d.getMinutes()).padStart(2, "0");
    return `${dd}/${mm}/${yyyy} ${hh}:${mi}`;
  } catch {
    return "";
  }
}

/* ===================== DESCRIPTION BUILDERS ===================== */

function buildSummary(service, tier, business_detected) {
  const s = humanServiceLabel(service);
  const t = tier ? String(tier).toUpperCase() : "";
  const b = business_detected ? " • B2B" : "";
  return `Fluxidi Taxi • ${s}${t ? " • " + t : ""}${b}`;
}

function buildDescription(d) {
  const lines = [];
  lines.push("FLUXIDI TAXI — BOOKING DETAILS");
  lines.push("--------------------------------");

  lines.push(`From: ${d.from || "-"}`);
  if (Array.isArray(d.stops) && d.stops.length) {
    lines.push("Stops:");
    d.stops.forEach((s, i) => lines.push(`  ${i + 1}. ${s}`));
  }
  lines.push(`To: ${d.to || "-"}`);

  lines.push(`Service: ${humanServiceLabel(d.service)}`);
  lines.push(`Tier: ${String(d.tier || "-").toUpperCase()} (fee €${tierFeeEx(d.tier).toFixed(0)})`);

  // ✅ selections that impact service/prep
  if (typeof d.return_enabled === "boolean") {
    const r = d.return_enabled ? (d.return_forced_by_wait ? "YES" : "YES") : "NO";
    lines.push(`Return: ${r}`);
  }
  if (d.extra_service_label) {
    lines.push(`Extra service: ${d.extra_service_label}`);
  }

  lines.push(`Pax: ${d.pax ?? "-"}`);
  lines.push(`Bags: ${d.bags ?? "-"} ( €5/koffer )`);

  if (d.wait_min) lines.push(`Waiting time: ${d.wait_min} min`);
  if (d.stopHandlingMin) lines.push(`Stop handling: ${d.stopHandlingMin} min`);

  lines.push("");
  lines.push("BUSINESS");
  lines.push(`Business detected: ${d.business_detected ? "YES" : "NO"}`);
  if (d.business_detected) {
    lines.push(`Company: ${d.company_name || "-"}`);
    lines.push(`VAT: ${d.vat_number || "-"}`);
    lines.push(`Invoice requested: ${d.invoice_requested ? "YES" : "NO"}`);
  }

  lines.push("");

  if (d.pickupStartIso && d.pickupEndIso) {
    lines.push(`Pickup: ${fmtLocalNLFromIso(d.pickupStartIso)}`);
    lines.push(`Total distance: ${Number(d.distance_km || 0).toFixed(1)} km`);
    lines.push(`Total route time (with stops): ${Number(d.durationRouteMin || 0)} min`);

    if (Array.isArray(d.legs) && d.legs.length) {
      lines.push("");
      lines.push("ROUTE LEGS (per segment):");
      d.legs.forEach((leg) => {
        lines.push(`  ${leg.index}. ${leg.from} → ${leg.to}: ${Number(leg.distance_km || 0).toFixed(1)} km • ${Number(leg.duration_min || 0)} min`);
      });
    }

    lines.push("");
    lines.push(`Total service time (busy calc): ${Number(d.totalServiceMin || 0)} min`);
    lines.push(`Buffer (drop-off/payment): ${Number(d.postBufferMin || 0)} min`);
    lines.push(`TOTAL BUSY: ${Number(d.busyMin || 0)} min`);
    lines.push(`Reserved until: ${fmtLocalNLFromIso(d.pickupEndIso)}`);
    lines.push("");
  }

  const p = d.pricing;
  if (p) {
    lines.push(`Price incl VAT: €${Number(p.price_incl_vat).toFixed(2)}`);
    lines.push(`Price ex VAT: €${Number(p.price_ex_vat).toFixed(2)}`);
    lines.push(`VAT: €${Number(p.price_vat).toFixed(2)} • rate ${(Number(d.pricing?.breakdown?.vat_rate || 0) * 100).toFixed(0)}%`);
  }

  lines.push("");
  lines.push("CUSTOMER");
  lines.push(`Name: ${d.custName || "-"}`);
  lines.push(`Phone: ${d.custPhone || "-"}`);
  lines.push(`Email: ${d.custEmail || "-"}`);

  return lines.join("\n");
}

/* ===================== INVOICE (HTML + PDF + EMAIL) ✅ ===================== */

function normalizeInvoiceInputForTest(body) {
  const now = new Date();
  const dd = String(now.getDate()).padStart(2, "0");
  const mm = String(now.getMonth() + 1).padStart(2, "0");
  const yyyy = String(now.getFullYear());

  return {
    invoiceNumber: body.invoiceNumber || `FLX-${yyyy}-${mm}-0001`,
    invoiceDate: body.invoiceDate || `${dd}/${mm}/${yyyy}`,
    tripDate: body.tripDate || `${dd}/${mm}/${yyyy}`,
    pickupTime: body.pickupTime || "12:00",

    from: body.from || "Kortrijk Station",
    to: body.to || "Brussels Airport",
    tier: body.tier || "COMFORT",
    pax: body.pax ?? 1,
    bags: body.bags ?? 0,

    customerName: body.customerName || "Jan Peeters",
    customerEmail: body.customerEmail || "jan@example.com",
    customerPhone: body.customerPhone || "+32 470 00 00 00",
    customerVat: body.customerVat || "",
    companyName: body.companyName || "",

    basePrice: body.basePrice || "100.00",
    bagFee: body.bagFee || "0.00",
    waitFee: body.waitFee || "0.00",

    subtotal: body.subtotal || "100.00",
    vatAmount: body.vatAmount || "21.00",
    total: body.total || "121.00",
    vat_rate: body.vat_rate ?? 0.21
  };
}

/**
 * Invoice numbers keep display format FLX-YYYY-MM-####
 * - Scoped path: DOCUMENT_REFERENCE_SEQUENCE (atomic, tenant/company + month)
 * - Legacy fallback: INVOICE_KV key invoice:YYYY-MM when scope is missing
 */
function invoiceYearMonthPartsFromInput(pickupIsoOrDate = null) {
  let d = null;
  if (pickupIsoOrDate) {
    const tmp = new Date(pickupIsoOrDate);
    if (!isNaN(tmp.getTime())) d = tmp;
  }
  if (!d) d = new Date();
  const yyyy = String(d.getFullYear());
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  return { yyyy, mm };
}

async function allocateScopedInvoiceSequence(env, { tenant_id, company_id, pickup_iso } = {}) {
  if (!env?.DOCUMENT_REFERENCE_SEQUENCE) {
    throw new Error("Missing DOCUMENT_REFERENCE_SEQUENCE binding");
  }
  const tenantId = safeStr(tenant_id, 120);
  const companyId = safeStr(company_id, 120);
  if (!tenantId || !companyId) {
    throw new Error("missing_tenant_scope");
  }
  const parts = invoiceYearMonthPartsFromInput(pickup_iso || null);
  const yyyy = parts.yyyy;
  const mm = parts.mm;
  const sequenceType = `invoice_${yyyy}_${mm}`;
  const instanceName = documentReferenceScopeName(tenantId, companyId, sequenceType, yyyy);
  const stub = env.DOCUMENT_REFERENCE_SEQUENCE.get(
    env.DOCUMENT_REFERENCE_SEQUENCE.idFromName(instanceName),
  );
  const resp = await stub.fetch("https://do/allocate", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({
      action: "allocate",
      tenant_id: tenantId,
      company_id: companyId,
      sequence_type: sequenceType,
      prefix: "FLX",
      year: yyyy,
      pickup_iso: pickup_iso || null,
    }),
  });
  const body = await resp.json().catch(() => ({}));
  const seqNum = Number(body?.seq);
  if (!resp.ok || !Number.isFinite(seqNum) || seqNum <= 0) {
    throw new Error(
      safeStr(body?.error) || `Scoped invoice sequence allocation failed (${resp.status})`,
    );
  }
  const seq = String(Math.trunc(seqNum)).padStart(4, "0");
  return `FLX-${yyyy}-${mm}-${seq}`;
}

async function nextInvoiceNumber(env, pickupIsoOrDate = null, scope = null) {
  const scopeTenant = safeStr(scope?.tenant_id ?? scope?.tenantId, 120);
  const scopeCompany = safeStr(scope?.company_id ?? scope?.companyId, 120);
  if (scopeTenant && scopeCompany) {
    return await allocateScopedInvoiceSequence(env, {
      tenant_id: scopeTenant,
      company_id: scopeCompany,
      pickup_iso: pickupIsoOrDate,
    });
  }
  console.log("[INVOICE_SEQ][LEGACY_FALLBACK] reason=missing_scope");
  const kv = env.INVOICE_KV;
  const parts = invoiceYearMonthPartsFromInput(pickupIsoOrDate);
  const yyyy = parts.yyyy;
  const mm = parts.mm;
  const key = `invoice:${yyyy}-${mm}`;

  if (!kv) {
    const rnd = String(Math.floor(Math.random() * 9000 + 1000)).padStart(4, "0");
    return `FLX-${yyyy}-${mm}-${rnd}`;
  }

  const raw = await kv.get(key);
  const cur = Number(raw || "0");
  const next = cur + 1;
  await kv.put(key, String(next));

  const seq = String(next).padStart(4, "0");
  return `FLX-${yyyy}-${mm}-${seq}`;
}

function findExistingInvoiceNumber(source) {
  return safeStr(
    source?.invoice_number ||
      source?.invoiceNumber ||
      source?.invoice?.invoice_number ||
      source?.invoice?.invoiceNumber ||
      source?.invoice?.number ||
      source?.booking?.invoice_number ||
      source?.booking?.invoiceNumber ||
      source?.booking?.invoice?.number,
    120,
  );
}

function resolveInvoiceBookingId(bookingInput) {
  const out = [];
  const seen = new Set();
  const add = (value) => {
    const text = safeStr(value, 160);
    if (!text || seen.has(text)) return;
    seen.add(text);
    out.push(text);
  };

  add(bookingInput?.bookingId);
  add(bookingInput?.booking_id);
  add(bookingInput?.bookingPublicId);
  add(bookingInput?.public_booking_id);
  add(bookingInput?.__booking_id);
  add(bookingInput?.booking_uuid);

  add(bookingInput?.booking?.bookingId);
  add(bookingInput?.booking?.booking_id);
  add(bookingInput?.booking?.bookingPublicId);
  add(bookingInput?.booking?.public_booking_id);
  add(bookingInput?.booking?.__booking_id);
  add(bookingInput?.booking?.booking_uuid);

  return out;
}

async function loadInvoiceBookingRecord(env, bookingInput) {
  const candidates = resolveInvoiceBookingId(bookingInput);
  if (!env?.BOOKING_KV) {
    return { booking_id: candidates[0] || null, key: null, rec: null };
  }
  for (const bookingId of candidates) {
    const key = `booking:${bookingId}`;
    try {
      const rec = await env.BOOKING_KV.get(key, { type: "json" });
      if (rec && typeof rec === "object") {
        return { booking_id: bookingId, key, rec };
      }
    } catch (_) {
      // Try next candidate.
    }
  }
  return { booking_id: candidates[0] || null, key: null, rec: null };
}

async function persistInvoiceNumberForBooking(env, bookingRecordInfo, invoiceNumber, invoiceScope = null) {
  const key = safeStr(bookingRecordInfo?.key);
  if (!key || !env?.BOOKING_KV) {
    console.log("[INVOICE_SEQ][PERSIST_SKIP] reason=missing_booking_record");
    return { ok: false, skipped: true };
  }
  try {
    const latest = await env.BOOKING_KV.get(key, { type: "json" });
    if (!latest || typeof latest !== "object") {
      console.log("[INVOICE_SEQ][PERSIST_SKIP] reason=record_not_found");
      return { ok: false, skipped: true };
    }
    const existing = findExistingInvoiceNumber(latest);
    if (existing) {
      console.log("[INVOICE_SEQ][PERSIST_SKIP] reason=already_exists");
      return { ok: true, skipped: true, invoice_number: existing };
    }
    const issuedAt = new Date().toISOString();
    latest.invoice_number = invoiceNumber;
    latest.invoiceNumber = invoiceNumber;
    latest.invoice_issued_at = issuedAt;
    latest.invoiceIssuedAt = issuedAt;
    if (latest.booking && typeof latest.booking === "object") {
      latest.booking.invoice_number = invoiceNumber;
      latest.booking.invoiceNumber = invoiceNumber;
    }
    if (invoiceScope?.tenant_id && invoiceScope?.company_id) {
      latest.invoice_scope = {
        tenant_id: invoiceScope.tenant_id,
        company_id: invoiceScope.company_id,
      };
    }
    await env.BOOKING_KV.put(key, JSON.stringify(latest));
    console.log("[INVOICE_SEQ][PERSISTED] ok=true");
    return { ok: true, persisted: true, invoice_number: invoiceNumber };
  } catch (err) {
    console.log(
      `[INVOICE_SEQ][PERSIST_ERROR] reason=${safeStr(err?.message || err).slice(0, 120) || "unknown"}`,
    );
    return { ok: false, error: safeStr(err?.message || err) || "persist_error" };
  }
}

function todayNL() {
  const d = new Date();
  const dd = String(d.getDate()).padStart(2, "0");
  const mm = String(d.getMonth() + 1).padStart(2, "0");
  const yyyy = String(d.getFullYear());
  return `${dd}/${mm}/${yyyy}`;
}

function computeInvoiceBaseLineEx(pricing) {
  try {
    const totalEx = Number(pricing?.breakdown?.total_ex ?? pricing?.price_ex_vat ?? 0);
    const bagsEx = Number(pricing?.breakdown?.bags_ex ?? 0);
    const waitingEx = Number(pricing?.breakdown?.waiting_ex ?? 0);
    const base = Math.max(0, totalEx - bagsEx - waitingEx);
    return to2(base);
  } catch {
    return to2(pricing?.price_ex_vat ?? 0);
  }
}

function renderInvoiceHtml(env, data, commProfile = null) {
  const d = data || {};
  const profile = maybeNormalizeCommunicationProfile(commProfile || {});

  const DEFAULT_LOGO_URL = "https://cdn.shopify.com/s/files/1/0959/4788/2827/files/ChatGPT_Image_9_jan_2026_17_37_39_fef5e6e4-ad29-43cd-b950-c98f77f27e0d.png?v=1768311638";
  const LOGO_URL = safeStr(profile.logoUrl) || safeStr(env?.INVOICE_LOGO_URL) || safeStr(d.logoUrl) || DEFAULT_LOGO_URL;
  const sellerBrand = safeBrandName(profile.brandName, "Fluxidi Taxi");
  const sellerLegal = sanitizeTenantString(profile.legalName || sellerBrand, 160) || sellerBrand;
  const sellerAddress = safeStr(profile.address) || "Koekamerstraat 48\n9680 Maarkedal\nBelgië";
  const sellerVat = safeStr(profile.vatNumber) || "BE0772931038";
  const sellerPhone = safeStr(profile.phone) || "+32 491 59 75 54";
  const sellerFooter = safeStr(profile.invoiceFooter) || `Dank u voor het vertrouwen in ${sellerBrand} — wij brengen u in stijl.`;
  const sellerAddressHtml = escapeHtml(sellerAddress).replace(/\n/g, "<br>");

  const vatRatePct = toInt(d.vatRate, (typeof d.vat_rate === "number" ? Math.round(d.vat_rate * 100) : 6));
  const eur = (v) => `€${money2(v)}`;

  const stops = Array.isArray(d.stops) ? d.stops.filter(Boolean) : [];
  const stopsLine = stops.length
    ? `<span class="muted">Tussenstops: ${stops.map(s => escapeHtml(String(s))).join(" • ")}</span><br>`
    : "";

  const kmLine = (typeof d.routeKm === "number" && d.routeKm >= 0)
    ? `<span class="muted">Afstand: ${escapeHtml(String(Math.round(d.routeKm * 10) / 10))} km</span>`
    : "";

  const minLine = (typeof d.routeMinutes === "number" && d.routeMinutes >= 0)
    ? `<span class="muted">${kmLine ? " • " : ""}Duur: ${escapeHtml(String(Math.round(d.routeMinutes)))} min</span>`
    : "";

  const invoiceAddressBlock = safeStr(d.invoiceAddress)
    ? `<small><strong>Facturatieadres</strong><br>${escapeHtml(d.invoiceAddress).replace(/\n/g, "<br>")}</small>`
    : "";

  const customerCompanyBlock = safeStr(d.customerCompany)
    ? `<div><strong>${escapeHtml(d.customerCompany)}</strong></div>`
    : "";

  const returnLine = d.returnTrip ? `<span class="muted">Retourrit inbegrepen.</span><br>` : "";

  const splitLines = (safeStr(d.priceReturnIncl) && money2(d.priceReturnIncl) !== "0.00")
    ? `<tr><td class="muted">Retourdeel</td><td class="right">${eur(d.priceReturnIncl)}</td></tr>`
    : "";

  return `<!DOCTYPE html>
<html lang="nl">
<head>
  <meta charset="UTF-8" />
  <title>Factuur ${escapeHtml(d.invoiceNumber || "")}</title>
</head>
<body>
<p>&nbsp;</p>
<style>
  body {
    font-family: Arial, Helvetica, sans-serif;
    background: #ffffff;
    margin: 0;
    padding: 0;
    color: #111;
  }

  .invoice-wrapper {
    max-width: 820px;
    margin: 36px auto;
    padding: 32px;
    border: 1px solid #ddd;
  }

  .header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border-bottom: 2px solid #f0c400;
    padding-bottom: 14px;
    margin-bottom: 22px;
    gap: 16px;
  }

  .logo img { height: 160px; object-fit: contain; }

  .company-info {
    text-align: right;
    font-size: 13px;
    line-height: 1.6;
  }

  h1 { font-size: 26px; margin: 0 0 14px 0; }

  .meta {
    display: flex;
    justify-content: space-between;
    margin-bottom: 18px;
    font-size: 14px;
    gap: 18px;
  }

  .box { width: 48%; }
  .box strong { display: block; margin-bottom: 6px; }
  .meta small { color: #444; display:block; margin-top:6px; line-height:1.5; }

  .pill {
    display: inline-block;
    padding: 4px 10px;
    border-radius: 999px;
    background: #fff6cc;
    border: 1px solid #f0c400;
    font-size: 12px;
    margin-left: 8px;
  }

  table { width: 100%; border-collapse: collapse; margin-top: 18px; }

  table th {
    background: #f5f5f5;
    text-align: left;
    padding: 10px;
    font-size: 14px;
    border-bottom: 2px solid #ddd;
  }

  table td {
    padding: 10px;
    font-size: 14px;
    border-bottom: 1px solid #eee;
    vertical-align: top;
  }

  .muted { color: #555; }
  .right { text-align:right; }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, "Liberation Mono", "Courier New", monospace; }

  .totals {
    margin-top: 18px;
    width: 100%;
    max-width: 340px;
    margin-left: auto;
  }

  .totals td { padding: 6px 10px; }
  .totals tr:last-child td {
    font-weight: bold;
    font-size: 16px;
    border-top: 2px solid #000;
  }

  .footer {
    margin-top: 34px;
    font-size: 12px;
    color: #555;
    text-align: center;
    line-height: 1.6;
  }
</style>

<div class="invoice-wrapper">

  <div class="header">
    <div class="logo">
      <img alt="${escapeHtml(sellerBrand)}" src="${escapeHtml(LOGO_URL)}">
    </div>
    <div class="company-info">
      <strong>${escapeHtml(sellerLegal)}</strong><br>
      ${sellerAddressHtml}<br>
      BTW: ${escapeHtml(sellerVat)}<br>
      Tel: ${escapeHtml(sellerPhone)}
    </div>
  </div>

  <h1>Factuur</h1>

  <div class="meta">
    <div class="box">
      <strong>Gefactureerd aan</strong>
      ${customerCompanyBlock}
      ${escapeHtml(safeStr(d.customerName) || "—")}<br>
      ${escapeHtml(safeStr(d.customerEmail) || "—")}<br>
      ${escapeHtml(safeStr(d.customerPhone) || "—")}<br>
      <span class="mono">${safeStr(d.customerVat) ? "BTW: " + escapeHtml(d.customerVat) : "BTW: —"}</span>
      ${invoiceAddressBlock ? `<div style="margin-top:10px">${invoiceAddressBlock}</div>` : ""}
    </div>

    <div class="box" style="text-align:right;">
      <strong>Factuurnummer:</strong> <span class="mono">${escapeHtml(safeStr(d.invoiceNumber) || "—")}</span><br>
      <strong>Factuurdatum:</strong> ${escapeHtml(safeStr(d.invoiceDate) || "—")}<br>
      <strong>Datum dienst:</strong> ${escapeHtml(safeStr(d.tripDate) || "—")}<br>

      <small>
        <strong>Booking ID:</strong> <span class="mono">${escapeHtml(safeStr(d.bookingPublicId) || safeStr(d.bookingId) || "—")}</span><br>
        <strong>Ritniveau:</strong> ${escapeHtml(safeStr(d.tier) || "—")}${safeStr(d.service) ? ` <span class="pill">${escapeHtml(d.service)}</span>` : ""}<br>
        <strong>Ophaaltijd:</strong> ${escapeHtml(safeStr(d.pickupTime) || "—")}<br>
        <strong>Passagiers / Koffers:</strong> ${escapeHtml(String(toInt(d.pax, 0)))} / ${escapeHtml(String(toInt(d.bags, 0)))}<br>
        <strong>Wachttijd:</strong> ${escapeHtml(String(toInt(d.waitMinutes, 0)))} min<br>
        <strong>Retour:</strong> ${d.returnTrip ? "JA" : "NEE"}
      </small>
    </div>
  </div>

  <table>
    <thead>
      <tr>
        <th>Omschrijving</th>
        <th class="right">Bedrag (€)</th>
      </tr>
    </thead>
    <tbody>
      <tr>
        <td>
          <strong>Taxidienst</strong> <span class="muted">(${escapeHtml(safeStr(d.tier) || "—")})</span><br>
          ${escapeHtml(safeStr(d.from) || "—")} → ${escapeHtml(safeStr(d.to) || "—")}<br>
          ${stopsLine}
          ${returnLine}
          ${kmLine}${minLine}
        </td>
        <td class="right">${eur(d.total)}</td>
      </tr>
      ${splitLines}
    </tbody>
  </table>

  <table class="totals">
    <tbody>
      <tr>
        <td>Subtotaal (excl. btw)</td>
        <td class="right">${eur(d.subtotalEx)}</td>
      </tr>
      <tr>
        <td>BTW (${escapeHtml(String(vatRatePct))}%)</td>
        <td class="right">${eur(d.vatAmount)}</td>
      </tr>
      <tr>
        <td>Totaal (incl. btw)</td>
        <td class="right">${eur(d.total)}</td>
      </tr>
    </tbody>
  </table>

  <div class="footer">
    BTW aangerekend volgens de Belgische BTW-wetgeving (personenvervoer).<br>
    ${escapeHtml(sellerFooter)}
  </div>

</div>
</body>
</html>`;
}

async function renderPdfFromDlexLayout(layoutDataObj, env) {
  const apiKey = safeStr(env.DPDF_API_KEY);
  const dlexPath = safeStr(env.DPDF_DLEX_PATH);
  if (!apiKey || !dlexPath) return null;

  const form = new FormData();
  form.append("DlexPath", dlexPath);

  const json = JSON.stringify(layoutDataObj || {});
  const blob = new Blob([json], { type: "application/json" });
  form.append("LayoutData", blob, "layout-data.json");

  const r = await fetch("https://api.dpdf.io/v1.0/dlex-layout", {
    method: "POST",
    headers: { "Authorization": `Bearer ${apiKey}` },
    body: form
  });

  if (!r.ok) {
    const t = await r.text().catch(() => "");
    throw new Error(`DynamicPDF dlex-layout failed: ${r.status} ${t}`.slice(0, 400));
  }

  const buf = await r.arrayBuffer();
  return new Uint8Array(buf);
}

async function renderPdfFromHtml(htmlString, env) {
  // ✅ PDFShift (preferred): render Shopify HTML invoice to PDF
  const pdfShiftKey = safeStr(env.PDFSHIFT_API_KEY);
  if (pdfShiftKey) {
    const r = await fetch("https://api.pdfshift.io/v3/convert/pdf", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-API-Key": pdfShiftKey
      },
      body: JSON.stringify({
        source: String(htmlString || ""),
        landscape: false,
        use_print: true,
        sandbox: false
      })
    });

    if (!r.ok) {
      const t = await r.text().catch(() => "");
      throw new Error(`PDFShift render failed: ${r.status} ${t}`.slice(0, 300));
    }

    const buf = await r.arrayBuffer();
    return new Uint8Array(buf);
  }

  const url = safeStr(env.PDF_RENDER_URL);
  if (!url) return null;

  const key = safeStr(env.PDF_RENDER_KEY);
  const headers = { "Content-Type": "application/json" };
  if (key) headers["Authorization"] = `Bearer ${key}`;

  const r = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ html: String(htmlString || "") })
  });

  if (!r.ok) {
    const t = await r.text().catch(() => "");
    throw new Error(`PDF render failed: ${r.status} ${t}`.slice(0, 300));
  }

  const buf = await r.arrayBuffer();
  return new Uint8Array(buf);
}

async function sendInvoiceEmailWithPdf({
  env,
  toEmail,
  invoiceNumber,
  pdfBytes,
  commProfile = null,
  sendCustomerEmail = true,
  customerSkipReason = "",
}) {
  const apiKey = safeStr(env.RESEND_API_KEY);
  const emailFrom = safeStr(env.EMAIL_FROM);
  const profile = commProfile || await resolveTenantCommunicationProfile(env);
  const replyTo = pickFirstValidEmail(
    profile.replyToEmail,
    profile.companyEmail,
    profile.supportEmail,
    profile.invoiceEmail,
    env.EMAIL_REPLY_TO,
  );
  const customerEmail = safeStr(toEmail);
  const adminCopyEmail = pickFirstValidEmail(
    profile.invoiceEmail,
    profile.billingEmail,
    profile.notificationEmail,
    env.OWNER_EMAIL,
  );
  const brandName = safeBrandName(profile.brandName, "Fluxidi Taxi");
  const legalName = sanitizeTenantString(profile.legalName || brandName, 160) || brandName;
  const legalBits = [
    safeStr(profile.address),
    (safeStr(profile.vatNumber) ? `BTW ${safeStr(profile.vatNumber)}` : ""),
    safeStr(profile.phone),
  ].filter(Boolean).join(" — ");
  const footerLine = legalBits ? `${legalName} — ${legalBits}` : legalName;
  const providerConfigured = !!apiKey && !!emailFrom;
  const hasCustomerEmail = isValidEmail(customerEmail);
  const hasInvoiceEmail = !!adminCopyEmail;
  const shouldSendCustomerEmail = sendCustomerEmail !== false;
  const attachmentBase64 = bytesToBase64Chunked(pdfBytes);
  const hasAttachment = !!attachmentBase64;

  if (shouldSendCustomerEmail) {
    console.log(
      `[EMAIL][INVOICE_CUSTOMER][START] bookingId=${safeStr(invoiceNumber)} providerConfigured=${providerConfigured} hasCustomerEmail=${hasCustomerEmail} attachment_included=${hasAttachment}`,
    );
  } else {
    console.log(
      `[EMAIL][INVOICE_CUSTOMER][SKIP] bookingId=${safeStr(invoiceNumber)} reason=${safeStr(customerSkipReason || "private_ride_manual_pdf_flow")}`,
    );
  }
  console.log(
    `[EMAIL][INVOICE_ADMIN][START] bookingId=${safeStr(invoiceNumber)} providerConfigured=${providerConfigured} hasInvoiceEmail=${hasInvoiceEmail} attachment_included=${hasAttachment}`,
  );
  if (!apiKey || !emailFrom) {
    if (shouldSendCustomerEmail) {
      console.log(
        `[EMAIL][INVOICE_CUSTOMER][ERROR] bookingId=${safeStr(invoiceNumber)} reason=provider_not_configured`,
      );
    }
    console.log(
      `[EMAIL][INVOICE_ADMIN][ERROR] bookingId=${safeStr(invoiceNumber)} reason=provider_not_configured`,
    );
    return { enabled: false, sent: false, warning: "Email not configured (missing RESEND_API_KEY / EMAIL_FROM)." };
  }
  if (shouldSendCustomerEmail && !hasCustomerEmail) {
    console.log(
      `[EMAIL][INVOICE_CUSTOMER][ERROR] bookingId=${safeStr(invoiceNumber)} reason=missing_customer_email`,
    );
  }

  const subject = `${brandName} factuur ${invoiceNumber}`;
  const invoiceMessage = hasAttachment
    ? `In bijlage vindt u uw factuur van ${escapeHtml(brandName)}.`
    : "Uw betaling werd ontvangen, maar de factuur-PDF kon niet automatisch als bijlage worden toegevoegd. Neem contact op indien u de PDF nodig heeft.";
  const htmlBody = `
    <div style="font-family:system-ui,-apple-system,Segoe UI,Roboto,Arial;line-height:1.6">
      <h2 style="margin:0 0 10px">Factuur ${escapeHtml(invoiceNumber)}</h2>
      <p style="margin:0 0 12px;color:#444">
        ${invoiceMessage}
      </p>
      <p style="margin:12px 0 0;color:#666;font-size:12px">
        ${escapeHtml(footerLine)}
      </p>
    </div>
  `;
  const payloadFor = (to, mailSubject) => ({
    from: emailFrom,
    to: [to],
    subject: mailSubject,
    html: htmlBody,
    ...(replyTo ? { reply_to: replyTo } : {}),
    ...(hasAttachment ? {
      attachments: [
        {
          filename: `factuur-${invoiceNumber}.pdf`,
          content: attachmentBase64
        }
      ],
    } : {})
  });

  const headers = { "Authorization": `Bearer ${apiKey}`, "Content-Type": "application/json" };
  let customerSend = { sent: false, skipped: false };
  if (shouldSendCustomerEmail && hasCustomerEmail) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers,
      body: JSON.stringify(payloadFor(customerEmail, subject))
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(j?.message || "Resend invoice mail failed");
    customerSend = { sent: true, skipped: false, resend_id: j?.id || null };
    console.log(
      `[EMAIL][INVOICE_CUSTOMER][OK] bookingId=${safeStr(invoiceNumber)} resendId=${safeStr(j?.id) || "-"}`,
    );
  } else {
    customerSend = { sent: false, skipped: true };
  }

  let adminCopy = { sent: false, skipped: true };
  if (adminCopyEmail && (!hasCustomerEmail || adminCopyEmail.toLowerCase() !== customerEmail.toLowerCase() || !shouldSendCustomerEmail)) {
    const adminPayload = payloadFor(adminCopyEmail, `[ADMIN COPY] ${subject}`);
    const adminRes = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers,
      body: JSON.stringify(adminPayload)
    });
    const adminJson = await adminRes.json().catch(() => ({}));
    adminCopy = {
      sent: adminRes.ok,
      to: maskEmailForLog(adminCopyEmail),
      resend_id: adminJson?.id || null,
      error: adminRes.ok ? null : (adminJson?.message || `HTTP ${adminRes.status}`),
    };
    if (adminRes.ok) {
      console.log(
        `[EMAIL][INVOICE_ADMIN][OK] bookingId=${safeStr(invoiceNumber)} resendId=${safeStr(adminJson?.id) || "-"}`,
      );
    } else {
      console.log(
        `[EMAIL][INVOICE_ADMIN][ERROR] bookingId=${safeStr(invoiceNumber)} reason=${safeStr(adminCopy.error).slice(0, 160)}`,
      );
    }
  } else if (!adminCopyEmail) {
    console.log(
      `[EMAIL][INVOICE_ADMIN][ERROR] bookingId=${safeStr(invoiceNumber)} reason=missing_admin_recipient`,
    );
  } else {
    console.log(
      `[EMAIL][INVOICE_ADMIN][OK] bookingId=${safeStr(invoiceNumber)} reason=same_as_customer`,
    );
  }

  return {
    enabled: true,
    sent: !!(customerSend.sent || adminCopy.sent),
    attachment_included: hasAttachment,
    customer: customerSend,
    admin_copy: adminCopy,
  };
}

async function generateAndSendInvoice({ env, booking, emailPolicy = null }) {
  try {
    const bookingInput = booking && typeof booking === "object" ? booking : {};
    const invoiceTenantId = safeStr(
      bookingInput.tenant_id ??
        bookingInput.tenantId,
      120,
    );
    const invoiceCompanyId = safeStr(
      bookingInput.company_id ??
        bookingInput.companyId,
      120,
    );
    const invoiceScope = invoiceTenantId && invoiceCompanyId
      ? { tenant_id: invoiceTenantId, company_id: invoiceCompanyId }
      : null;
    const commProfile = await resolveTenantCommunicationProfile(env, invoiceTenantId, invoiceCompanyId);
    const profileMissing = !safeStr(commProfile?.brandName) && !safeStr(commProfile?.legalName);
    const bookingRecordInfo = await loadInvoiceBookingRecord(env, bookingInput);
    const existingInvoiceNumber =
      findExistingInvoiceNumber(bookingRecordInfo?.rec) ||
      findExistingInvoiceNumber(bookingInput);
    let invoiceNumber = existingInvoiceNumber || "";
    let allocatedNow = false;
    if (invoiceNumber) {
      console.log("[INVOICE_SEQ][REUSE] source=existing_record");
    } else {
      invoiceNumber = await nextInvoiceNumber(env, bookingInput.pickupStartIso, invoiceScope);
      allocatedNow = true;
      console.log("[INVOICE_SEQ][ALLOCATED] source=sequence_allocator");
    }
    if (allocatedNow) {
      const persisted = await persistInvoiceNumberForBooking(
        env,
        bookingRecordInfo,
        invoiceNumber,
        invoiceScope,
      );
      if (persisted?.invoice_number && persisted.invoice_number !== invoiceNumber) {
        invoiceNumber = persisted.invoice_number;
        console.log("[INVOICE_SEQ][REUSE] source=persisted_record");
      }
    }
    const invoiceDate = todayNL();
    const parseAmount = (value) => {
      const num = Number(value);
      return Number.isFinite(num) ? round2(num) : null;
    };
    const vatRateNormalized = (typeof bookingInput.vat_rate === "number" && Number.isFinite(bookingInput.vat_rate))
      ? bookingInput.vat_rate
      : 0.06;
    const totalRaw = parseAmount(bookingInput.total);
    const subtotalRaw = parseAmount(bookingInput.subtotalEx ?? bookingInput.subtotal);
    const vatRaw = parseAmount(bookingInput.vatAmount);
    const derivedTotal = totalRaw ?? ((subtotalRaw != null && vatRaw != null) ? round2(subtotalRaw + vatRaw) : null);
    const derivedSubtotal = subtotalRaw ?? (derivedTotal != null ? round2(derivedTotal / (1 + vatRateNormalized)) : null);
    const derivedVat = vatRaw ?? (
      derivedTotal != null && derivedSubtotal != null
        ? round2(derivedTotal - derivedSubtotal)
        : null
    );
    const finalTotal = derivedTotal ?? 0;
    const finalSubtotal = derivedSubtotal ?? 0;
    const finalVat = derivedVat ?? 0;
    const missingTotal = !(derivedTotal != null && derivedTotal > 0);
    const customerEmail = pickFirstValidEmail(
      bookingInput.customerEmail,
      bookingInput.custEmail,
      bookingInput.customer_email,
      bookingInput.email,
    );
    const missingCustomerEmail = !customerEmail;
    const missingBookingData = !safeStr(bookingInput.from) || !safeStr(bookingInput.to) || !safeStr(bookingInput.pickupTime || bookingInput.tripDate || bookingInput.pickupStartIso);
    const pdfProviderConfigured = !!safeStr(env?.PDFSHIFT_API_KEY) || !!safeStr(env?.PDF_RENDER_URL);
    console.log(
      `[INVOICE_GEN] bookingId=${safeStr(bookingInput.bookingPublicId || bookingInput.bookingId)} missingTotal=${missingTotal} missingCustomerEmail=${missingCustomerEmail} missingBookingData=${missingBookingData} missingBusinessProfile=${profileMissing} pdfProviderConfigured=${pdfProviderConfigured}`,
    );

    const data = {
      // numbering
      invoiceNumber,
      invoiceDate,
      bookingPublicId: bookingInput.bookingPublicId || bookingInput.bookingId || "",
      bookingId: bookingInput.bookingId || "",

      // trip meta
      tripDate: bookingInput.tripDate || "",
      pickupTime: bookingInput.pickupTime || "",
      waitMinutes: toInt(bookingInput.waitMinutes, 0),
      returnTrip: !!bookingInput.returnTrip,

      // route
      from: bookingInput.from || "",
      to: bookingInput.to || "",
      stops: Array.isArray(bookingInput.stops) ? bookingInput.stops : [],
      routeKm: (typeof bookingInput.routeKm === "number") ? bookingInput.routeKm : null,
      routeMinutes: (typeof bookingInput.routeMinutes === "number") ? bookingInput.routeMinutes : null,

      // service
      tier: bookingInput.tier || "",
      service: bookingInput.service || "",
      pax: toInt(bookingInput.pax, 0),
      bags: toInt(bookingInput.bags, 0),

      // customer
      customerName: bookingInput.customerName || "",
      customerEmail: customerEmail || "",
      customerPhone: bookingInput.customerPhone || "",
      customerVat: bookingInput.customerVat || "",
      customerCompany: bookingInput.customerCompany || "",
      invoiceAddress: bookingInput.invoiceAddress || "",

      // totals
      vat_rate: vatRateNormalized,
      vatRate: Math.round(vatRateNormalized * 100),
      subtotalEx: finalSubtotal,
      vatAmount: finalVat,
      total: finalTotal,

      // optional split (display only)
      priceMainIncl: bookingInput.priceMainIncl ?? "",
      priceReturnIncl: bookingInput.priceReturnIncl ?? ""
    };

    const htmlOut = renderInvoiceHtml(env, data, commProfile);
    console.log(
      `[INVOICE_GEN] bookingId=${safeStr(data.bookingPublicId || data.bookingId)} htmlRendered=${!!safeStr(htmlOut)}`,
    );

    let pdfBytes = null;
    try {
      pdfBytes = await renderPdfFromHtml(htmlOut, env);
    } catch (pdfErr) {
      console.log(
        `[INVOICE_GEN] bookingId=${safeStr(data.bookingPublicId || data.bookingId)} pdfGenerated=false pdfError=${safeStr(pdfErr?.message || pdfErr).slice(0, 160)}`,
      );
      pdfBytes = null;
    }
    console.log(
      `[INVOICE_GEN] bookingId=${safeStr(data.bookingPublicId || data.bookingId)} pdfGenerated=${!!(pdfBytes && pdfBytes.length)} pdfProviderConfigured=${pdfProviderConfigured}`,
    );

    const emailTo = customerEmail;
    const emailResult = await sendInvoiceEmailWithPdf({
      env,
      toEmail: emailTo,
      invoiceNumber,
      pdfBytes: pdfBytes || new Uint8Array(0),
      commProfile,
      sendCustomerEmail: emailPolicy?.sendCustomerEmail !== false,
      customerSkipReason: safeStr(emailPolicy?.customerSkipReason || ""),
    });

    const documentType = (safeStr(data.customerCompany) || safeStr(data.customerVat)) ? "invoice" : "receipt";
    return {
      ok: true,
      invoiceNumber,
      documentType,
      emailed_to: emailTo,
      email: emailResult,
      html_preview_available: true,
      pdf_generated: !!(pdfBytes && pdfBytes.length),
      pdf_provider_configured: pdfProviderConfigured,
    };
  } catch (e) {
    return { ok: false, error: String(e?.message || e) };
  }
}

/**
 * ✅ Robust base64 for Uint8Array PDFs
 * - Avoids Function.apply() argument limits (which can silently break attachments)
 */
function bytesToBase64Chunked(bytes) {
  if (!bytes || !bytes.length) return "";

  let binary = "";
  const chunkSize = 0x2000; // safer for all JS engines
  for (let i = 0; i < bytes.length; i += chunkSize) {
    const end = Math.min(i + chunkSize, bytes.length);
    let chunkStr = "";
    for (let j = i; j < end; j++) chunkStr += String.fromCharCode(bytes[j]);
    binary += chunkStr;
  }
  return btoa(binary);
}

/* ===================== Missing bits used earlier ===================== */

function toStr(x) { return String(x ?? ""); }

/* ===================== END ===================== */



// ===============================
// PAY STATUS (fallback finalizer)
// ===============================
function _payStatusExplicitScope(tenantValue, companyValue) {
  const tenantId = _scopeText(tenantValue);
  const companyId = _scopeText(companyValue);
  if (!tenantId || !companyId) return null;
  return {
    tenant_id: tenantId,
    company_id: companyId,
    hasScope: true,
  };
}

function _payStatusScopeMatches(a, b) {
  if (!a?.hasScope || !b?.hasScope) return false;
  return (
    _scopeText(a?.tenant_id) === _scopeText(b?.tenant_id) &&
    _scopeText(a?.company_id) === _scopeText(b?.company_id)
  );
}

function _payStatusScopeFromBookingRecord(rec) {
  return _payStatusExplicitScope(
    rec?.tenant_id ??
      rec?.tenantId ??
      rec?.booking?.tenant_id ??
      rec?.booking?.tenantId,
    rec?.company_id ??
      rec?.companyId ??
      rec?.booking?.company_id ??
      rec?.booking?.companyId,
  );
}

function _payStatusScopeFromPaymentRecord(rec) {
  return _payStatusExplicitScope(
    rec?.tenant_id ??
      rec?.tenantId ??
      rec?.payload?.tenant_id ??
      rec?.payload?.tenantId,
    rec?.company_id ??
      rec?.companyId ??
      rec?.payload?.company_id ??
      rec?.payload?.companyId,
  );
}

function _payStatusBookingIdCandidates(data, id, includeRawId = false) {
  const out = [];
  const add = (value) => {
    const bookingId = safeStr(value, 160);
    if (!bookingId) return;
    if (!out.includes(bookingId)) out.push(bookingId);
  };
  add(data?.booking_id);
  add(data?.bookingId);
  add(data?.public_booking_id);
  add(data?.publicBookingId);
  add(data?.payload?.__booking_id);
  add(data?.payload?.booking_id);
  add(data?.payload?.bookingId);
  if (includeRawId) add(id);
  return out;
}

function _payStatusFirstScope(scopes = []) {
  for (const scope of scopes) {
    if (scope?.hasScope) return scope;
  }
  return null;
}

function _payStatusScopesConflict(a, b) {
  if (!a?.hasScope || !b?.hasScope) return false;
  return !_payStatusScopeMatches(a, b);
}

async function _resolvePaymentReturnScope(env, id) {
  const bookingId = safeStr(id, 160);
  if (!bookingId || !env?.BOOKING_KV) return { hasScope: false };
  const candidateScopes = [];
  const candidateBookings = [];

  try {
    const bookingRec = await env.BOOKING_KV.get(`booking:${bookingId}`, { type: "json" });
    if (bookingRec && typeof bookingRec === "object") {
      const bookingScope = _payStatusScopeFromBookingRecord(bookingRec);
      if (bookingScope?.hasScope) candidateScopes.push(bookingScope);
    }
  } catch (_) {}

  let paymentRec = null;
  try {
    const loaded = await env.BOOKING_KV.get(`payment:${bookingId}`, { type: "json" });
    if (loaded && typeof loaded === "object") {
      paymentRec = loaded;
      const paymentScope = _payStatusScopeFromPaymentRecord(loaded);
      if (paymentScope?.hasScope) candidateScopes.push(paymentScope);
      const hintedBookingIds = _payStatusBookingIdCandidates(loaded, bookingId, true);
      for (const hintedBookingId of hintedBookingIds) {
        if (!hintedBookingId) continue;
        if (!candidateBookings.includes(hintedBookingId)) {
          candidateBookings.push(hintedBookingId);
        }
      }
    }
  } catch (_) {}

  if (!candidateBookings.includes(bookingId)) {
    candidateBookings.push(bookingId);
  }
  if (paymentRec) {
    const hintedFromPayment = _payStatusBookingIdCandidates(paymentRec, bookingId, true);
    for (const hintedBookingId of hintedFromPayment) {
      if (!hintedBookingId) continue;
      if (!candidateBookings.includes(hintedBookingId)) {
        candidateBookings.push(hintedBookingId);
      }
    }
  }

  for (const candidateBookingId of candidateBookings) {
    try {
      const loaded = await loadBookingRecord(env, candidateBookingId);
      const bookingScope = _payStatusScopeFromBookingRecord(loaded?.rec);
      if (bookingScope?.hasScope) candidateScopes.push(bookingScope);
    } catch (_) {
      // Best-effort only for /pay/return rendering.
    }
  }

  let resolved = null;
  for (const scope of candidateScopes) {
    if (!scope?.hasScope) continue;
    if (!resolved) {
      resolved = scope;
      continue;
    }
    if (_payStatusScopesConflict(resolved, scope)) {
      return { hasScope: false };
    }
  }

  const firstScope = _payStatusFirstScope([resolved]);
  if (!firstScope?.hasScope) return { hasScope: false };
  return {
    tenant_id: firstScope.tenant_id,
    company_id: firstScope.company_id,
    hasScope: true,
  };
}

async function payStatus(request, env, requestedScopeOverride = null) {
  const url = new URL(request.url);
  const id = (url.searchParams.get("id") || "").trim();
  if (!id) return json({ ok: false, error: "missing id" }, 400);

  // Backwards compatible keys
  const kvKeyBooking = `booking:${id}`;
  const kvKeyPayment = `payment:${id}`;

  // Determine which key exists
  const hasPaymentKey = !!(await env.BOOKING_KV.get(kvKeyPayment));
  const keyToUse = hasPaymentKey ? kvKeyPayment : kvKeyBooking;

  let data = await env.BOOKING_KV.get(keyToUse, "json");
  if (!data && !hasPaymentKey) {
    // if booking key didn't exist, try payment key (edge)
    data = await env.BOOKING_KV.get(kvKeyPayment, "json");
  }
  if (!data) return json({ ok: false, error: "not found" }, 404);

  const resolvedScope =
    requestedScopeOverride && requestedScopeOverride.hasScope
      ? requestedScopeOverride
      : resolveExplicitBookingRequestScope({
          request,
          url,
          allowLegacyFallback: false,
        });
  if (!resolvedScope?.hasScope) {
    return json(
      resolvedScope?.error === "tenant_scope_conflict" ? scopeConflictError() : missingTenantScopeError(),
      400,
    );
  }
  const requestedScope = {
    tenant_id: _scopeText(resolvedScope.tenant_id),
    company_id: _scopeText(resolvedScope.company_id),
    hasScope: true,
  };

  let linkedBooking = null;
  const bookingCandidates = _payStatusBookingIdCandidates(data, id, !hasPaymentKey);
  for (const bookingId of bookingCandidates) {
    try {
      const loaded = await loadBookingRecord(env, bookingId);
      if (loaded?.rec) {
        linkedBooking = { booking_id: bookingId, key: loaded.key, rec: loaded.rec };
        break;
      }
    } catch (_) {
      // Try next candidate.
    }
  }

  const bookingScope = _payStatusScopeFromBookingRecord(linkedBooking?.rec);
  const paymentScope = _payStatusScopeFromPaymentRecord(data);

  if (bookingScope && !_payStatusScopeMatches(bookingScope, requestedScope)) {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (paymentScope && !_payStatusScopeMatches(paymentScope, requestedScope)) {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (!bookingScope && !paymentScope) {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  if (linkedBooking?.rec && !bookingMatchesRequestedTenantScope(linkedBooking.rec, requestedScope)) {
    return json({ ok: false, error: "forbidden" }, 403);
  }

  const effectiveScope = requestedScope;

  // Helper: clear stale confirming lock
  const clearStaleLockIfNeeded = () => {
    try {
      if (data?.confirming_at) {
        const started = Date.parse(data.confirming_at);
        // If lock older than 3 minutes, consider it stale and recover.
        if (Number.isFinite(started) && (Date.now() - started) > 180_000) {
          data.confirming_at = null;
          data.confirm_error = (data.confirm_error || "") + (data.confirm_error ? " | " : "") + "Recovered stale confirming_at lock";
        }
      }
    } catch (_) {}
  };

  // Always attempt stale-lock recovery (prevents permanent deadlocks)
  clearStaleLockIfNeeded();

  // If Mollie payment exists, fetch latest status (best effort)
  const paymentId = data?.mollie?.payment_id || data?.mollie?.id || data?.mollie_payment_id || data?.payment_id;

  // We will persist back no matter what happens
  let finalizeAttempted = false;
  let compliancePaymentUpdateEmitAttempted = false;

  try {
    if (paymentId) {
      const pay = await mollieFetchPaymentJson(paymentId, env);
      const status = pay?.status || null;
      const normalized = normalizedPaymentFields({
        status,
        paymentId,
        paidAt: data?.paid_at,
      });

      Object.assign(data, normalized);
      data.mollie = data.mollie || {};
      data.mollie.status = status;
      data.mollie.last_checked_at = new Date().toISOString();

      // Keep webhook timestamp if present
      if (data?.mollie?.last_webhook_at) {
        data.mollie.last_webhook_at = data.mollie.last_webhook_at;
      }

      // If paid and not yet confirmed -> finalize here (single source of truth)
      if (status === "paid" && !data.confirmed_at) {
        if (!effectiveScope?.hasScope) {
          data.confirm_error = data.confirm_error || "missing_tenant_scope_for_finalization";
          data.confirming_at = null;
          return json({ ok: false, error: "missing_tenant_scope_for_finalization" }, 400);
        }
        if (!data.payload || typeof data.payload !== "object") {
          data.payload = {};
        }
        if (!safeStr(data.payload.tenant_id || data.payload.tenantId, 80)) {
          data.payload.tenant_id = effectiveScope.tenant_id;
        }
        if (!safeStr(data.payload.company_id || data.payload.companyId, 80)) {
          data.payload.company_id = effectiveScope.company_id;
        }
        data.paid_at = data.paid_at || new Date().toISOString();
        data.paidAt = data.paidAt || data.paid_at;
        data.payment_status = "paid";
        data.paymentStatus = "paid";
        // Best-effort lock
        try {
          if (data?.confirming_at) {
            const started = Date.parse(data.confirming_at);
            if (Number.isFinite(started) && (Date.now() - started) < 120_000) {
              // Another finalize is running; just persist and return
              await env.BOOKING_KV.put(keyToUse, JSON.stringify(data), { expirationTtl: 60 * 60 * 24 * 30 });
              return json({ ok: true, data, alreadyRunning: true });
            }
          }
        } catch (_) {}

        // Ensure we keep the canonical human id
        data.public_booking_id = data.public_booking_id || safeStr(data?.payload?.__booking_id) || null;

        // Persist confirming lock BEFORE running finalize (reduces races)
        data.confirming_at = new Date().toISOString();
        await env.BOOKING_KV.put(keyToUse, JSON.stringify(data), { expirationTtl: 60 * 60 * 24 * 30 });

        // Run finalize (never throws; returns {ok, updatedStored})
        finalizeAttempted = true;
        const result = await finalizeBookingFromStored(data, env, request, { bypassLock: true });
        data = result?.updatedStored || data;
      }
    }

    // Emit one backend compliance payment_update for Mollie/online finalized bookings.
    // This is best-effort only and must never block payment finalization.
    const shouldEmitCompliancePaymentUpdate =
      String(data?.payment_status || data?.paymentStatus || "").toLowerCase() === "paid" &&
      !!data?.confirmed_at &&
      !safeStr(data?.compliance_payment_update_emitted_at);

    if (shouldEmitCompliancePaymentUpdate) {
      compliancePaymentUpdateEmitAttempted = true;
      const isUnknownLikePaymentValue = (value) => {
        const raw = String(value ?? "").trim().toLowerCase();
        return (
          raw === "" ||
          raw === "unknown" ||
          raw === "onbekend" ||
          raw === "—" ||
          raw === "-" ||
          raw === "null" ||
          raw === "undefined"
        );
      };
      const pickMeaningfulPaymentValue = (...candidates) => {
        for (const candidate of candidates) {
          const text = safeStr(candidate);
          if (!text) continue;
          if (isUnknownLikePaymentValue(text)) continue;
          return text;
        }
        return null;
      };
      const complianceBookingId =
        safeStr(
          data?.booking_id ||
            data?.public_booking_id ||
            data?.payload?.__booking_id ||
            data?.payload?.booking_id ||
            data?.payload?.bookingId ||
            id,
        ) || id;
      const compliancePaymentPayload = {
        payment_status: data?.payment_status || data?.paymentStatus || "paid",
        payment_method:
          pickMeaningfulPaymentValue(
            data?.payment_method,
            data?.paymentMethod,
            data?.payload?.payment_method,
            data?.payload?.paymentMethod,
          ) ||
          "online_payment",
        payment_source:
          pickMeaningfulPaymentValue(
            data?.payment_source,
            data?.paymentSource,
            data?.payload?.payment_source,
            data?.payload?.paymentSource,
          ) ||
          "mollie",
        payment_provider:
          pickMeaningfulPaymentValue(
            data?.payment_provider,
            data?.paymentProvider,
            data?.payload?.payment_provider,
            data?.payload?.paymentProvider,
          ) ||
          "mollie",
        payment_id:
          safeStr(data?.payment_id || data?.paymentId || data?.mollie?.payment_id || data?.mollie?.id) || null,
        paid_at: safeStr(data?.paid_at || data?.paidAt) || null,
        currency: safeStr(data?.currency || data?.payload?.currency || "EUR") || "EUR",
        tenant_id: effectiveScope?.tenant_id || null,
        company_id: effectiveScope?.company_id || null,
      };
      if (effectiveScope?.hasScope) {
        const complianceEvent = buildBookingPaymentUpdateComplianceEvent(
          data,
          complianceBookingId,
          compliancePaymentPayload,
        );
        if (complianceEvent) {
          const emitted = await emitComplianceEventBestEffort(env, complianceEvent, {
            timeoutMs: 1500,
            logLabel: "planned_mollie_payment_update",
          });
          if (emitted?.ok) {
            data.compliance_payment_update_emitted_at = new Date().toISOString();
          }
        } else {
          console.log("[COMPLIANCE_EMIT][planned_mollie_payment_update] skipped reason=builder_null");
        }
      } else {
        console.log("[COMPLIANCE_EMIT][planned_mollie_payment_update] skipped reason=missing_tenant_scope");
      }
    }
  } catch (e) {
    // Don't fail /pay/status; persist error for diagnostics
    data.mollie = data.mollie || {};
    data.mollie.status_error = String(e?.message || e);
    // If an error happened during finalize attempt, make sure we do not leave a permanent lock
    try {
      if (finalizeAttempted) {
        data.confirm_error = data.confirm_error || "Finalize failed inside /pay/status";
        data.confirming_at = null;
      }
      if (compliancePaymentUpdateEmitAttempted) {
        data.confirm_error =
          data.confirm_error || "Compliance payment_update emit failed inside /pay/status";
      }
    } catch (_) {}
  } finally {
    // Always persist the latest state (including lock recovery)
    await env.BOOKING_KV.put(keyToUse, JSON.stringify(data), { expirationTtl: 60 * 60 * 24 * 30 });
  }

  return json({ ok: true, data });
}

async function mollieFetchPaymentJson(paymentId, env) {
  const mollieConfig = getMollieConfig(env);
  if (!mollieConfig.ok) throw new Error(mollieConfig.error);
  const url = `https://api.mollie.com/v2/payments/${encodeURIComponent(paymentId)}`;
  const res = await fetch(url, {
    headers: {
      Authorization: `Bearer ${mollieConfig.apiKey}`,
      "Content-Type": "application/json",
    },
  });
  const txt = await res.text();
  let j = null;
  try { j = JSON.parse(txt); } catch (_) {}
  if (!res.ok) throw new Error(`Mollie get payment failed (${res.status}): ${txt?.slice(0, 300)}`);
  return j;
}

async function finalizeBookingFromStored(stored, env, request, opts = {}) {
  // Idempotent: if already confirmed, do nothing
  if (stored?.confirmed_at) {
    stored.confirming_at = null;
    return { ok: true, updatedStored: stored, already: true };
  }

  // Stale lock recovery (important!)
  try {
    if (stored?.confirming_at) {
      const started = Date.parse(stored.confirming_at);
      if (Number.isFinite(started) && (Date.now() - started) > 180_000) {
        stored.confirming_at = null;
        stored.confirm_error = (stored.confirm_error || "") + (stored.confirm_error ? " | " : "") + "Recovered stale confirming_at lock (finalizeBookingFromStored)";
      }
    }
  } catch (_) {}

  // If another finalize started very recently, skip (unless bypassLock=true)
  if (!opts?.bypassLock) {
    try {
      if (stored?.confirming_at) {
        const started = Date.parse(stored.confirming_at);
        if (Number.isFinite(started) && (Date.now() - started) < 120_000) {
          return { ok: true, updatedStored: stored, alreadyRunning: true };
        }
      }
    } catch (_) {}
  }

  if (!stored?.payload) {
    stored.confirm_error = "Cannot finalize: missing stored.payload";
    stored.confirming_at = null;
    return { ok: false, updatedStored: stored, error: stored.confirm_error };
  }

  const nowIso = new Date().toISOString();
  stored.confirming_at = nowIso;

  // Initialize debug container early so even early crashes are visible
  stored.finalize_debug = stored.finalize_debug || {};
  stored.finalize_debug.attempted_at = nowIso;
  stored.finalize_debug.stage = "start";
  stored.finalize_debug.error = null;

  try {
    // Ensure payload is treated as paid so it won't create a NEW Mollie payment.
    stored.payload.__mollie_paid = true;
    const finalPaymentFields = normalizedPaymentFields({
      status: stored.payment_status || stored.paymentStatus || stored?.mollie?.status,
      paymentId: stored.payment_id || stored.paymentId || stored?.mollie?.payment_id || stored?.mollie?.id,
      paidAt: stored.paid_at || stored.paidAt,
    });
    Object.assign(stored.payload, finalPaymentFields);
    Object.assign(stored, finalPaymentFields);
    console.log("[PAYMENT_STATUS][FINALIZE]", JSON.stringify({
      payment_id: finalPaymentFields.payment_id || null,
      payment_status: finalPaymentFields.payment_status || null,
      paid_at: finalPaymentFields.paid_at || null,
      booking_id: stored.booking_id || stored.public_booking_id || stored.payload.booking_id || stored.payload.bookingId || null,
    }));

    // Re-use the original human booking id if present (canonical ID everywhere)
    if (stored.public_booking_id) stored.payload.__booking_id = stored.public_booking_id;
    if (stored.booking_id) stored.payload.__booking_id = stored.booking_id;
    if (stored.payload.booking_id) stored.payload.__booking_id = stored.payload.booking_id;
    if (stored.payload.bookingId) stored.payload.__booking_id = stored.payload.bookingId;
    const storedPublicBookingReference = safeStr(
      stored.public_booking_reference ||
        stored.publicBookingReference ||
        stored.booking_reference ||
        stored.bookingReference ||
        stored.payload?.__public_booking_reference ||
        stored.payload?.public_booking_reference ||
        stored.payload?.publicBookingReference,
    );
    if (storedPublicBookingReference) {
      stored.payload.__public_booking_reference = storedPublicBookingReference;
      attachPublicBookingReferenceAliases(stored.payload, storedPublicBookingReference);
    }

    // Use the current request origin (prevents "https://internal" links in emails)
    const origin = (() => {
      try { return request ? (new URL(request.url)).origin : "https://fluxidi-booking-api.fluxidi.workers.dev"; }
      catch { return "https://fluxidi-booking-api.fluxidi.workers.dev"; }
    })();

    const fakeReq = new Request(origin + "/book", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(stored.payload),
    });

    stored.finalize_debug.stage = "handleBooking";
    const bookingResult = await handleBooking(stored.payload, env, fakeReq);

    // If the booking pipeline still thinks payment is required, do NOT confirm.
    if (!bookingResult?.ok || bookingResult?.requiresPayment) {
      stored.confirm_error = bookingResult?.error || JSON.stringify(bookingResult || {});
      stored.finalize_debug.stage = "handleBooking_failed";
      stored.finalize_debug.error = stored.confirm_error;
      stored.confirming_at = null;
      return { ok: false, updatedStored: stored, bookingResult };
    }

    // Mark confirmed (even if some non-critical outputs had warnings)
    stored.confirmed_at = new Date().toISOString();
    stored.confirming_at = null;

    // Persist useful ids (best-effort)
    if (bookingResult?.booking_id) stored.booking_id = bookingResult.booking_id;
    if (bookingResult?.calendar_event_id) stored.calendar_event_id = bookingResult.calendar_event_id;

    // Store debug summary for /pay/status troubleshooting
    stored.finalize_debug = {
      at: new Date().toISOString(),
      stage: "done",
      booking_id: bookingResult?.booking_id || null,
      calendar_event_id: bookingResult?.calendar_event_id || null,
      email: bookingResult?.email || null,
      invoice: bookingResult?.invoice || null,
      invoice_number: bookingResult?.invoice_number || bookingResult?.invoiceNumber || null,
      warnings: bookingResult?.warnings || null,
      error: null
    };

    return { ok: true, updatedStored: stored, bookingResult };

  } catch (e) {
    // NEVER throw here — we must not leave the booking in a permanent lock.
    stored.confirm_error = String(e?.message || e);
    stored.finalize_debug = stored.finalize_debug || {};
    stored.finalize_debug.stage = stored.finalize_debug.stage || "unknown";
    stored.finalize_debug.error = stored.confirm_error;

    // Clear lock so the next /pay/status poll can retry
    stored.confirming_at = null;

    return { ok: false, updatedStored: stored, error: stored.confirm_error };
  }
}
