// Fluxidi Tracking API Worker — V2.1 (Cloudflare Dashboard JS)
// ✅ Full replacement file (paste into Cloudflare "index.js").
//
// Includes everything from V2 + housekeeping + NEW /track/route endpoint.
//
// NEW: POST /track/route  { "from": "Gent", "to": "Kortrijk", "profile": "driving" }
// - Uses server-side Mapbox (token stored as Worker secret MAPBOX_TOKEN)
// - Returns polyline geometry (GeoJSON), distance/duration, and resolved coordinates
// - Keeps Mapbox token off the device/app.
//
// Required secrets/bindings in Cloudflare Worker:
// - ADMIN_TOKEN (secret)
// - MAPBOX_TOKEN (secret)  <-- add this!
// - KV binding named: FLUXIDI_TRACKING
//
// -------------------------------
// Helpers
// -------------------------------
function json(data, init = {}) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(data, null, 2), { ...init, headers });
}

function withCors(resp, origin) {
  const headers = new Headers(resp.headers);
  headers.set("access-control-allow-origin", origin);
  headers.set("access-control-allow-methods", "GET,POST,OPTIONS");
  headers.set("access-control-allow-headers", "content-type,x-admin-token,authorization");
  headers.set("access-control-max-age", "86400");
  return new Response(resp.body, {
    status: resp.status,
    statusText: resp.statusText,
    headers,
  });
}

function getOrigin(req) {
  return req.headers.get("origin") ?? "*";
}

function getBearerToken(req) {
  const a = req.headers.get("authorization");
  if (!a) return "";
  const m = a.match(/^Bearer\s+(.+)$/i);
  return m ? (m[1] || "").trim() : "";
}

function getToken(req, url) {
  const h = req.headers.get("x-admin-token")?.trim();
  if (h) return h;

  const b = getBearerToken(req);
  if (b) return b;

  return "";
}

function requireAdmin(req, url, env) {
  const expected = (env.ADMIN_TOKEN || "").trim();
  if (!expected) {
    throw new Error("ADMIN_TOKEN is not configured on the Worker (set as secret).");
  }
  const got = getToken(req, url);
  if (!got || got !== expected) throw new Error("Unauthorized");
}

function hasValidAdminToken(req, url, env) {
  const expected = (env?.ADMIN_TOKEN || "").trim();
  if (!expected) return false;
  const got = getToken(req, url);
  return !!got && got === expected;
}

const COMPANY_SESSION_KEY_PREFIX = "company_admin:session:";
const COMPANY_SESSION_KEY_SUFFIX = ":v1";

function companySessionKey(tokenHash) {
  const safeHash = safeStr(tokenHash, 200);
  if (!safeHash) return "";
  return `${COMPANY_SESSION_KEY_PREFIX}${safeHash.toLowerCase()}${COMPANY_SESSION_KEY_SUFFIX}`;
}

async function sha256Hex(text) {
  const data = new TextEncoder().encode(String(text || ""));
  const digest = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(digest);
  let hex = "";
  for (const byte of bytes) {
    hex += byte.toString(16).padStart(2, "0");
  }
  return hex;
}

async function hashCompanySessionToken(token) {
  const normalized = safeStr(token, 512);
  if (!normalized) return "";
  const hash = await sha256Hex(normalized);
  const trimmed = safeStr(hash, 200);
  return trimmed ? trimmed.toLowerCase() : "";
}

async function loadCompanySessionFromRequest(req, env) {
  if (!env?.BOOKING_KV) return null;
  const token = getBearerToken(req);
  if (!token) return null;
  const tokenHash = await hashCompanySessionToken(token);
  if (!tokenHash) return null;
  const key = companySessionKey(tokenHash);
  if (!key) return null;
  const record = await env.BOOKING_KV.get(key, { type: "json" });
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  const role = (safeStr(record.role, 40) ?? "").toLowerCase();
  if (role !== "company_admin") return null;
  const tenantId = safeStr(record.tenant_id ?? record.tenantId, 80);
  const companyId = safeStr(record.company_id ?? record.companyId, 80);
  const expiresAt = safeStr(record.expires_at ?? record.expiresAt, 80);
  const expiresAtMs = Date.parse(expiresAt || "");
  if (!Number.isFinite(expiresAtMs) || Date.now() >= expiresAtMs) {
    try {
      await env.BOOKING_KV.delete(key);
    } catch (_) {}
    return null;
  }
  if (!tenantId || !companyId) return null;
  return { tenant_id: tenantId, company_id: companyId };
}

function maskScopeForTripKpiLog(value) {
  const text = safeStr(value, 80) ?? "";
  if (!text) return "-";
  if (text.length <= 4) return `…${text.substring(text.length - 1)}`;
  return `${text.substring(0, 2)}…${text.substring(text.length - 2)}`;
}

async function requireAdminOrCompanySessionForScope(req, url, env, scope, origin) {
  if (hasValidAdminToken(req, url, env)) {
    console.log("[TRIP_KPIS][AUTH] auth_mode=admin_token");
    return { ok: true, auth_mode: "admin_token" };
  }
  const companySession = await loadCompanySessionFromRequest(req, env);
  if (!companySession) {
    throw new Error("Unauthorized");
  }
  if (
    scope.tenant_id !== companySession.tenant_id ||
    scope.company_id !== companySession.company_id
  ) {
    return {
      ok: false,
      response: withCors(
        json({ ok: false, error: "forbidden" }, { status: 403 }),
        origin,
      ),
    };
  }
  console.log(
    `[TRIP_KPIS][AUTH] auth_mode=company_session tenant=${maskScopeForTripKpiLog(companySession.tenant_id)} company=${maskScopeForTripKpiLog(companySession.company_id)}`,
  );
  return { ok: true, auth_mode: "company_session" };
}

function requireMapbox(env) {
  const t = (env.MAPBOX_TOKEN || "").trim();
  if (!t) throw new Error("MAPBOX_TOKEN is not configured on the Worker (set as secret).");
  return t;
}

async function readJson(req) {
  const ct = req.headers.get("content-type") || "";
  if (!ct.toLowerCase().includes("application/json")) {
    throw new Error("Expected application/json");
  }
  return await req.json();
}

function nowIso() {
  return new Date().toISOString();
}

function safeNum(v, min, max) {
  const n = typeof v === "number" ? v : Number(v);
  if (!Number.isFinite(n)) return null;
  return Math.min(max, Math.max(min, n));
}

function safeStr(v, maxLen = 2000) {
  if (typeof v !== "string") return null;
  const s = v.trim();
  if (!s) return null;
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

function sanitizeTripIdentityToken(value, maxLen = 96) {
  const raw = safeStr(value, maxLen * 4);
  if (!raw) return null;
  const sanitized = raw
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "_")
    .replace(/_+/g, "_")
    .replace(/^_+|_+$/g, "");
  if (!sanitized) return null;
  return sanitized.length > maxLen ? sanitized.slice(0, maxLen) : sanitized;
}

function resolveTrackingActorFromRequest(request, url, body = null) {
  const search = url?.searchParams;
  const actor_role = (
    safeStr(
      body?.actor_role ??
        body?.actorRole ??
        search?.get("actor_role") ??
        search?.get("actorRole") ??
        request?.headers?.get?.("x-fluxidi-actor-role"),
      32,
    ) ?? ""
  ).toLowerCase();
  const actor_driver_id =
    safeStr(
      body?.actor_driver_id ??
        body?.actorDriverId ??
        body?.driver_id ??
        body?.driverId ??
        body?.paid_by_driver_id ??
        body?.paidByDriverId ??
        search?.get("actor_driver_id") ??
        search?.get("actorDriverId") ??
        search?.get("driver_id") ??
        search?.get("driverId") ??
        request?.headers?.get?.("x-fluxidi-driver-id") ??
        request?.headers?.get?.("x-driver-id"),
      96,
    ) ?? null;
  const actor_vehicle_id =
    safeStr(
      body?.actor_vehicle_id ??
        body?.actorVehicleId ??
        body?.vehicle_id ??
        body?.vehicleId ??
        search?.get("actor_vehicle_id") ??
        search?.get("actorVehicleId") ??
        search?.get("vehicle_id") ??
        search?.get("vehicleId") ??
        request?.headers?.get?.("x-fluxidi-vehicle-id") ??
        request?.headers?.get?.("x-vehicle-id"),
      96,
    ) ?? null;
  return { actor_role, actor_driver_id, actor_vehicle_id };
}

function _trackingOwnershipError(error) {
  return { ok: false, error };
}

function _trackingOwnershipValue(v, maxLen = 96) {
  return safeStr(v, maxLen) ?? "";
}

function _trackingOwnershipAllowed({
  actorDriverId,
  actorVehicleId,
  ownerDriverId,
  ownerVehicleId,
  fallbackDriverId = "",
  fallbackVehicleId = "",
}) {
  const actorDriver = _trackingOwnershipValue(actorDriverId);
  const actorVehicle = _trackingOwnershipValue(actorVehicleId);
  const ownerDriver = _trackingOwnershipValue(ownerDriverId);
  const ownerVehicle = _trackingOwnershipValue(ownerVehicleId);
  const tripDriver = _trackingOwnershipValue(fallbackDriverId);
  const tripVehicle = _trackingOwnershipValue(fallbackVehicleId);
  const candidateDriver = ownerDriver || tripDriver;
  const candidateVehicle = ownerVehicle || tripVehicle;

  if (!actorDriver && !actorVehicle) {
    return {
      allowed: false,
      certainMismatch: true,
      reason: "actor_identity_missing",
      candidateDriver,
      candidateVehicle,
    };
  }
  if (candidateDriver && actorDriver) {
    if (candidateDriver === actorDriver) {
      return { allowed: true, certainMismatch: false, reason: "driver_match", candidateDriver, candidateVehicle };
    }
    return { allowed: false, certainMismatch: true, reason: "driver_mismatch", candidateDriver, candidateVehicle };
  }
  if (candidateVehicle && actorVehicle) {
    if (candidateVehicle === actorVehicle) {
      return { allowed: true, certainMismatch: false, reason: "vehicle_match", candidateDriver, candidateVehicle };
    }
    return { allowed: false, certainMismatch: true, reason: "vehicle_mismatch", candidateDriver, candidateVehicle };
  }
  if (!candidateDriver && !candidateVehicle) {
    return {
      allowed: true,
      certainMismatch: false,
      reason: "ownership_unknown_allow_compat",
      candidateDriver,
      candidateVehicle,
    };
  }
  return {
    allowed: false,
    certainMismatch: false,
    reason: "insufficient_actor_fields",
    candidateDriver,
    candidateVehicle,
  };
}

function _logTrackingOwnershipCheck({
  target,
  targetId,
  actor,
  ownerDriverId,
  ownerVehicleId,
  allowed,
  reason,
}) {
  console.log(
    `[TRACKING_OWNERSHIP][CHECK] target=${target} id=${targetId} actor_role=${actor.actor_role || "-"} actor_driver=${actor.actor_driver_id || "-"} actor_vehicle=${actor.actor_vehicle_id || "-"} owner_driver=${ownerDriverId || "-"} owner_vehicle=${ownerVehicleId || "-"} allowed=${allowed} reason=${reason || "-"}`,
  );
}

function _logTrackingOwnershipBlock({
  target,
  targetId,
  actor,
  ownerDriverId,
  ownerVehicleId,
  error,
}) {
  console.log(
    `[TRACKING_OWNERSHIP][BLOCK] target=${target} id=${targetId} actor_role=${actor.actor_role || "-"} actor_driver=${actor.actor_driver_id || "-"} actor_vehicle=${actor.actor_vehicle_id || "-"} owner_driver=${ownerDriverId || "-"} owner_vehicle=${ownerVehicleId || "-"} error=${error}`,
  );
}

async function _driverVehicleOwnershipBestEffort(env, { tenant_id, company_id, driver_id, vehicle_id }) {
  const tenantId = _trackingOwnershipValue(tenant_id);
  const companyId = _trackingOwnershipValue(company_id);
  const driverId = _trackingOwnershipValue(driver_id);
  const vehicleId = _trackingOwnershipValue(vehicle_id);
  if (!tenantId || !driverId || !vehicleId) {
    return { allowed: false, certainMismatch: true, reason: "missing_driver_or_vehicle" };
  }
  const scopedKey = companyId ? scopedOwnerVehicleKey({ tenant_id: tenantId, company_id: companyId }, vehicleId) : null;
  const legacyKey = `owner_vehicle:${tenantId}:${vehicleId}`;
  const knownDriverId = _trackingOwnershipValue(
    (scopedKey ? await env.FLUXIDI_TRACKING.get(scopedKey) : null) ?? await env.FLUXIDI_TRACKING.get(legacyKey),
  );
  if (!knownDriverId) {
    return { allowed: true, certainMismatch: false, reason: "no_vehicle_owner_known" };
  }
  if (knownDriverId === driverId) {
    return { allowed: true, certainMismatch: false, reason: "vehicle_owner_match" };
  }
  return { allowed: false, certainMismatch: true, reason: "vehicle_owner_mismatch" };
}

async function _rememberVehicleOwnerBestEffort(env, { tenant_id, company_id, driver_id, vehicle_id }) {
  const tenantId = _trackingOwnershipValue(tenant_id);
  const companyId = _trackingOwnershipValue(company_id);
  const driverId = _trackingOwnershipValue(driver_id);
  const vehicleId = _trackingOwnershipValue(vehicle_id);
  if (!tenantId || !driverId || !vehicleId) return;
  const mapKey = companyId
    ? scopedOwnerVehicleKey({ tenant_id: tenantId, company_id: companyId }, vehicleId)
    : `owner_vehicle:${tenantId}:${vehicleId}`;
  await env.FLUXIDI_TRACKING.put(mapKey, driverId, { expirationTtl: TTL_TRIP });
}

async function _assertTripOwnedByActorOrBlock({
  trip,
  trip_id,
  actor,
  error,
  origin,
}) {
  if (actor.actor_role !== "driver") return null;
  const ownerDriverId = _trackingOwnershipValue(trip?.owner_driver_id ?? trip?.driver_id);
  const ownerVehicleId = _trackingOwnershipValue(trip?.owner_vehicle_id ?? trip?.vehicle_id);
  const check = _trackingOwnershipAllowed({
    actorDriverId: actor.actor_driver_id,
    actorVehicleId: actor.actor_vehicle_id,
    ownerDriverId,
    ownerVehicleId,
    fallbackDriverId: _trackingOwnershipValue(trip?.driver_id),
    fallbackVehicleId: _trackingOwnershipValue(trip?.vehicle_id),
  });
  _logTrackingOwnershipCheck({
    target: "trip",
    targetId: _trackingOwnershipValue(trip_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    allowed: check.allowed,
    reason: check.reason,
  });
  if (check.allowed) return null;
  if (!check.certainMismatch) return null;
  _logTrackingOwnershipBlock({
    target: "trip",
    targetId: _trackingOwnershipValue(trip_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    error,
  });
  return withCors(json(_trackingOwnershipError(error), { status: 403 }), origin);
}

async function _assertSessionOwnedByActorOrBlock({
  session,
  session_id,
  actor,
  error,
  origin,
}) {
  if (actor.actor_role !== "driver") return null;
  const ownerDriverId = _trackingOwnershipValue(session?.owner_driver_id ?? session?.driver_id);
  const ownerVehicleId = _trackingOwnershipValue(session?.owner_vehicle_id ?? session?.vehicle_id);
  const check = _trackingOwnershipAllowed({
    actorDriverId: actor.actor_driver_id,
    actorVehicleId: actor.actor_vehicle_id,
    ownerDriverId,
    ownerVehicleId,
    fallbackDriverId: _trackingOwnershipValue(session?.driver_id),
    fallbackVehicleId: _trackingOwnershipValue(session?.vehicle_id),
  });
  _logTrackingOwnershipCheck({
    target: "session",
    targetId: _trackingOwnershipValue(session_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    allowed: check.allowed,
    reason: check.reason,
  });
  if (check.allowed) return null;
  if (!check.certainMismatch) return null;
  _logTrackingOwnershipBlock({
    target: "session",
    targetId: _trackingOwnershipValue(session_id) || "unknown",
    actor,
    ownerDriverId: check.candidateDriver,
    ownerVehicleId: check.candidateVehicle,
    error,
  });
  return withCors(json(_trackingOwnershipError(error), { status: 403 }), origin);
}

const COMPLIANCE_APPEND_PATH = "/compliance/events/append";

function safeKeyPart(value, maxLen = 128) {
  const raw = safeStr(value, maxLen);
  if (!raw) return null;
  const normalized = raw.replace(/[:\r\n\t]/g, "_").trim();
  return normalized || null;
}

function normalizeTenantCompanyScope(input = {}) {
  const tenant_id = safeStr(input.tenant_id ?? input.tenantId, 96) ?? null;
  const company_id = safeStr(input.company_id ?? input.companyId, 96) ?? null;
  if (!tenant_id && !company_id) return null;
  return { tenant_id, company_id };
}

function extractScopeFromQueryAndBody(url, body = null) {
  const search = url?.searchParams;
  return normalizeTenantCompanyScope({
    tenant_id: body?.tenant_id ?? body?.tenantId ?? search?.get("tenant_id") ?? search?.get("tenantId"),
    company_id: body?.company_id ?? body?.companyId ?? search?.get("company_id") ?? search?.get("companyId"),
  });
}

function extractScopeFromRecord(record) {
  return normalizeTenantCompanyScope({
    tenant_id:
      record?.tenant_id ??
      record?.tenantId ??
      record?.owner_tenant_id ??
      record?.ownerTenantId,
    company_id:
      record?.company_id ??
      record?.companyId ??
      record?.owner_company_id ??
      record?.ownerCompanyId,
  });
}

function missingScopeResponse(origin, message = "tenant_id and company_id are required") {
  return withCors(json({ ok: false, error: message }, { status: 400 }), origin ?? "*");
}

function parseRequiredTenantCompanyScope(request, url, body = null, options = {}) {
  const sourceScope = extractScopeFromQueryAndBody(url, body);
  const tenant_id = sourceScope?.tenant_id ?? null;
  const company_id = sourceScope?.company_id ?? null;
  const hasAnyScope = Boolean(tenant_id || company_id);
  if (!tenant_id || !company_id) {
    const message = hasAnyScope
      ? "tenant_id and company_id must both be provided"
      : "tenant_id and company_id are required";
    if (options.returnResponse === true) {
      return missingScopeResponse(options.origin, message);
    }
    throw new Error(message);
  }
  return { tenant_id, company_id };
}

function parseOptionalTenantCompanyScope(request, url, body = null, record = null) {
  const explicitScope = extractScopeFromQueryAndBody(url, body);
  if (explicitScope) {
    if (explicitScope.tenant_id && explicitScope.company_id) {
      return { tenant_id: explicitScope.tenant_id, company_id: explicitScope.company_id };
    }
    return null;
  }
  const recordScope = extractScopeFromRecord(record);
  if (recordScope?.tenant_id && recordScope?.company_id) {
    return { tenant_id: recordScope.tenant_id, company_id: recordScope.company_id };
  }
  return null;
}

function recordMatchesTenantCompanyScope(record, scope, options = {}) {
  const recordScope = extractScopeFromRecord(record);
  const targetScope = normalizeTenantCompanyScope(scope);
  if (!recordScope || !targetScope || !targetScope.tenant_id || !targetScope.company_id) {
    return false;
  }
  if (!recordScope.tenant_id) return false;
  if (recordScope.tenant_id !== targetScope.tenant_id) return false;
  if (!recordScope.company_id) {
    return options.allowLegacyCompanyless === true;
  }
  return recordScope.company_id === targetScope.company_id;
}

function normalizeScopedKeyScope(scope) {
  const normalized = normalizeTenantCompanyScope(scope);
  const tenantPart = safeKeyPart(normalized?.tenant_id, 96);
  const companyPart = safeKeyPart(normalized?.company_id, 96);
  if (!tenantPart || !companyPart) {
    throw new Error("tenant_id and company_id are required");
  }
  return { tenant_id: tenantPart, company_id: companyPart };
}

function scopedBookingIndexKey(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:booking_index`;
}

function scopedBookingSessionKey(scope, bookingId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const bookingPart = safeKeyPart(bookingId, 128);
  if (!bookingPart) throw new Error("booking_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:booking:${bookingPart}:session`;
}

function scopedSessionKey(scope, sessionId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const sessionPart = safeKeyPart(sessionId, 128);
  if (!sessionPart) throw new Error("session_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:session:${sessionPart}`;
}

function scopedPingLastKey(scope, sessionId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const sessionPart = safeKeyPart(sessionId, 128);
  if (!sessionPart) throw new Error("session_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:ping:${sessionPart}:last`;
}

function scopedPublicBookingKey(scope, token) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const tokenPart = safeKeyPart(token, 128);
  if (!tokenPart) throw new Error("public token is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:public:${tokenPart}:booking`;
}

function scopedTripKey(scope, tripId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const tripPart = safeKeyPart(tripId, 160);
  if (!tripPart) throw new Error("trip_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trip:${tripPart}`;
}

function scopedTripsIndexKey(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trips_index`;
}

function scopedTripsDriverIndexKey(scope, driverId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const driverPart = safeKeyPart(driverId, 96);
  if (!driverPart) throw new Error("driver_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trips_index:driver:${driverPart}`;
}

function scopedOwnerVehicleKey(scope, vehicleId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const vehiclePart = safeKeyPart(vehicleId, 96);
  if (!vehiclePart) throw new Error("vehicle_id is required");
  return `owner_vehicle:${normalizedScope.tenant_id}:${normalizedScope.company_id}:${vehiclePart}`;
}

function applyCanonicalScopeToRecord(record, scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  record.tenant_id = normalizedScope.tenant_id;
  record.company_id = normalizedScope.company_id;
  record.tenantId = normalizedScope.tenant_id;
  record.companyId = normalizedScope.company_id;
  return record;
}

function scopedDashboardTripKpisKey(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpis:v1`;
}

function scopedDashboardTripMonthKpisKey(scope, month) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpis:month:${month}:v1`;
}

function scopedDashboardTripContribKey(scope, tripId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const tripPart = safeKeyPart(tripId, 160);
  if (!tripPart) throw new Error("trip_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_contrib:${tripPart}:v1`;
}

function scopedDashboardTripPendingBookingKey(scope, bookingId) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const bookingPart = safeKeyPart(bookingId, 160);
  if (!bookingPart) throw new Error("booking_id is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_pending_booking:${bookingPart}:v1`;
}

function scopedDashboardTripPendingBookingPrefix(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_pending_booking:`;
}

function scopedDashboardTripDebugKey(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_debug:v1`;
}

function scopedDashboardBookingFinanceMonthKey(scope, month) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const monthPart = safeKeyPart(month, 16);
  if (!monthPart) throw new Error("month is required");
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:booking_finance:month:${monthPart}:v1`;
}

function scopedDashboardTripKpisMonthPrefix(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpis:month:`;
}

function scopedDashboardTripKpiContribPrefix(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_contrib:`;
}

function scopedDashboardBookingFinanceMonthPrefix(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:booking_finance:month:`;
}

function scopedDashboardBookingFinanceContribPrefix(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:booking_finance_contrib:`;
}

function scopedTripRecordsPrefix(scope) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  return `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:trip:`;
}

function allowDevResetEndpoints(env) {
  return String(env?.ALLOW_DEV_RESET_ENDPOINTS || "").trim().toLowerCase() === "true";
}

function allowDevResetExecute(env) {
  return String(env?.ALLOW_DEV_RESET || "").trim().toLowerCase() === "true";
}

function _coerceBoolean(value, fallback = false) {
  if (value == null) return fallback;
  const token = (safeStr(value, 16) ?? "").toLowerCase();
  if (!token) return fallback;
  if (token === "0" || token === "false" || token === "no") return false;
  if (token === "1" || token === "true" || token === "yes") return true;
  return fallback;
}

function _isUnsafeDevResetScope(tenantId, companyId) {
  const tenant = String(tenantId || "").trim().toLowerCase();
  const company = String(companyId || "").trim().toLowerCase();
  return tenant === "fluxidi" || company === "fluxidi";
}

function normalizeDashboardTripLifecycleStatus(value) {
  const raw = safeStr(value, 64);
  if (!raw) return "unknown";
  const s = raw.toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
  if (
    s === "stopped" ||
    s === "completed" ||
    s === "complete" ||
    s === "closed" ||
    s === "done" ||
    s === "finished" ||
    s === "finalized" ||
    s === "finalised"
  ) {
    return "completed";
  }
  if (
    s === "cancelled" ||
    s === "canceled" ||
    s === "deleted" ||
    s === "failed" ||
    s === "expired" ||
    s === "declined"
  ) {
    return "cancelled";
  }
  if (s === "active" || s === "running" || s === "pending" || s === "open") {
    return "active";
  }
  return "unknown";
}

function dashboardTripStatusIsCompleted(value) {
  return normalizeDashboardTripLifecycleStatus(value) === "completed";
}

function dashboardPaymentIsPaid(value) {
  return normalizeCompliancePaymentStatus(value) === "paid";
}

function _dashboardTripMonthFromIso(value) {
  const text = safeStr(value, 64);
  if (!text) return null;
  const ts = Date.parse(text);
  if (!Number.isFinite(ts)) return null;
  return new Date(ts).toISOString().slice(0, 7);
}

function _normalizeDashboardMonth(value) {
  const text = safeStr(value, 16);
  if (!text) return null;
  const m = text.match(/^(\d{4})-(\d{2})$/);
  if (!m) return null;
  const mm = Number(m[2]);
  if (!Number.isFinite(mm) || mm < 1 || mm > 12) return null;
  return `${m[1]}-${m[2]}`;
}

function _dashboardTripAmountCents(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}

function deriveDashboardTripKpiContribution(trip) {
  const tripId = safeStr(trip?.trip_id ?? trip?.tripId, 160);
  if (!tripId) return null;
  const completed = dashboardTripStatusIsCompleted(trip?.status ?? trip?.lifecycle_status);
  const paid = dashboardPaymentIsPaid(trip?.payment_status ?? trip?.paymentStatus);
  const paidAtMonth = _dashboardTripMonthFromIso(trip?.paid_at ?? trip?.paidAt);
  const paidFallbackMonth =
    paid && !paidAtMonth
      ? (_dashboardTripMonthFromIso(
          trip?.stopped_at ??
            trip?.stoppedAt ??
            trip?.ended_at ??
            trip?.endedAt ??
            trip?.completed_at ??
            trip?.completedAt,
        ) ?? null)
      : null;
  const paidMonth = paidAtMonth ?? paidFallbackMonth;

  const amountCents =
    _dashboardTripAmountCents(trip?.payment_amount) ??
    _dashboardTripAmountCents(trip?.paymentAmount) ??
    _dashboardTripAmountCents(trip?.final_amount) ??
    _dashboardTripAmountCents(trip?.finalAmount) ??
    _dashboardTripAmountCents(trip?.final_total) ??
    _dashboardTripAmountCents(trip?.finalTotal) ??
    _dashboardTripAmountCents(trip?.total_eur) ??
    _dashboardTripAmountCents(trip?.totalEur) ??
    0;

  const monthlyPaid = completed && paid && !!paidMonth;
  const missingAmount = monthlyPaid && amountCents <= 0;
  return {
    trip_id: tripId,
    completed_rides_count: completed ? 1 : 0,
    unpaid_completed_rides_count: completed && !paid ? 1 : 0,
    paid_month: monthlyPaid ? paidMonth : null,
    monthly_paid_rides_count: monthlyPaid ? 1 : 0,
    monthly_income_cents: monthlyPaid ? amountCents : 0,
    monthly_missing_amount_count: missingAmount ? 1 : 0,
  };
}

function _readDashboardContribShape(value, fallbackTripId = null) {
  const obj = value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const tripId = safeStr(obj.trip_id ?? fallbackTripId, 160) || null;
  const completed = Number(obj.completed_rides_count) === 1 ? 1 : 0;
  const unpaid = Number(obj.unpaid_completed_rides_count) === 1 ? 1 : 0;
  const paidMonth = _normalizeDashboardMonth(obj.paid_month);
  const monthlyPaidCount = Number(obj.monthly_paid_rides_count) === 1 ? 1 : 0;
  const monthlyIncomeCents = Number.isFinite(Number(obj.monthly_income_cents))
    ? Math.round(Number(obj.monthly_income_cents))
    : 0;
  const monthlyMissingAmountCount = Number.isFinite(Number(obj.monthly_missing_amount_count))
    ? Math.max(0, Math.round(Number(obj.monthly_missing_amount_count)))
    : 0;
  return {
    trip_id: tripId,
    completed_rides_count: completed,
    unpaid_completed_rides_count: unpaid,
    paid_month: paidMonth,
    monthly_paid_rides_count: monthlyPaidCount,
    monthly_income_cents: monthlyIncomeCents,
    monthly_missing_amount_count: monthlyMissingAmountCount,
  };
}

async function _applyPendingBookingPaymentToTripBestEffort(env, scope, trip) {
  try {
    if (!env?.FLUXIDI_TRACKING || !trip || typeof trip !== "object") return trip;
    const bookingIdCandidates = [
      safeStr(trip?.booking_id ?? trip?.bookingId, 160),
      safeStr(trip?.booking?.booking_id ?? trip?.booking?.bookingId, 160),
      safeStr(trip?.public_booking_reference ?? trip?.publicBookingReference, 160),
    ].filter((value) => !!value);
    if (!bookingIdCandidates.length) return trip;
    let marker = null;
    let markerKey = "";
    for (const bookingId of bookingIdCandidates) {
      const candidateKey = scopedDashboardTripPendingBookingKey(scope, bookingId);
      const candidateMarker = await kvGetJson(env.FLUXIDI_TRACKING, candidateKey);
      if (candidateMarker && typeof candidateMarker === "object" && !Array.isArray(candidateMarker)) {
        marker = candidateMarker;
        markerKey = candidateKey;
        break;
      }
    }
    if (!marker || typeof marker !== "object" || Array.isArray(marker)) return trip;
    const markerPayment = normalizeCompliancePaymentStatus(marker?.payment_status);
    if (markerPayment === "paid") {
      trip.payment_status = "paid";
      trip.paymentStatus = "paid";
      const paidAt = safeStr(marker?.paid_at, 64);
      if (paidAt) {
        trip.paid_at = paidAt;
        trip.paidAt = paidAt;
      }
      const amountCents = Number(marker?.payment_amount_cents);
      if (Number.isFinite(amountCents)) {
        const amount = Math.round(amountCents) / 100;
        trip.payment_amount = amount;
        trip.paymentAmount = amount;
      }
      const currency = safeStr(marker?.currency, 8).toUpperCase();
      if (currency) trip.currency = currency;
    }
    if (markerKey) {
      await kvDel(env.FLUXIDI_TRACKING, markerKey);
    }
    return trip;
  } catch (_) {
    return trip;
  }
}

async function materializeTripDashboardKpisBestEffort(env, scope, trip, sourceTag = "unknown") {
  try {
    if (!env?.FLUXIDI_TRACKING) return;
    trip = await _applyPendingBookingPaymentToTripBestEffort(env, scope, trip);
    const nextRaw = deriveDashboardTripKpiContribution(trip);
    if (!nextRaw?.trip_id) return;
    const normalizedScope = normalizeScopedKeyScope(scope);
    const tripKpisKey = scopedDashboardTripKpisKey(normalizedScope);
    const contribKey = scopedDashboardTripContribKey(normalizedScope, nextRaw.trip_id);
    const next = _readDashboardContribShape(nextRaw, nextRaw.trip_id);
    const prev = _readDashboardContribShape(
      await kvGetJson(env.FLUXIDI_TRACKING, contribKey),
      next.trip_id,
    );

    const globalCurrent = (await kvGetJson(env.FLUXIDI_TRACKING, tripKpisKey)) ?? {};
    const currentCompleted = Number.isFinite(Number(globalCurrent.completed_rides_count))
      ? Math.round(Number(globalCurrent.completed_rides_count))
      : 0;
    const currentUnpaid = Number.isFinite(
      Number(globalCurrent.unpaid_completed_rides_count),
    )
      ? Math.round(Number(globalCurrent.unpaid_completed_rides_count))
      : 0;
    const nextCompleted =
      currentCompleted + (next.completed_rides_count - prev.completed_rides_count);
    const nextUnpaid =
      currentUnpaid +
      (next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count);

    await kvPutJson(
      env.FLUXIDI_TRACKING,
      tripKpisKey,
      {
        completed_rides_count: Math.max(0, nextCompleted),
        unpaid_completed_rides_count: Math.max(0, nextUnpaid),
        updated_at: nowIso(),
      },
    );

    const monthDeltas = {};
    if (prev.paid_month && prev.monthly_paid_rides_count > 0) {
      monthDeltas[prev.paid_month] = monthDeltas[prev.paid_month] || {
        monthly_paid_rides_count: 0,
        monthly_income_cents: 0,
        monthly_missing_amount_count: 0,
      };
      monthDeltas[prev.paid_month].monthly_paid_rides_count -=
        prev.monthly_paid_rides_count;
      monthDeltas[prev.paid_month].monthly_income_cents -= prev.monthly_income_cents;
      monthDeltas[prev.paid_month].monthly_missing_amount_count -= prev.monthly_missing_amount_count;
    }
    if (next.paid_month && next.monthly_paid_rides_count > 0) {
      monthDeltas[next.paid_month] = monthDeltas[next.paid_month] || {
        monthly_paid_rides_count: 0,
        monthly_income_cents: 0,
        monthly_missing_amount_count: 0,
      };
      monthDeltas[next.paid_month].monthly_paid_rides_count +=
        next.monthly_paid_rides_count;
      monthDeltas[next.paid_month].monthly_income_cents += next.monthly_income_cents;
      monthDeltas[next.paid_month].monthly_missing_amount_count += next.monthly_missing_amount_count;
    }

    for (const [month, delta] of Object.entries(monthDeltas)) {
      if (
        !delta ||
        (!delta.monthly_paid_rides_count &&
          !delta.monthly_income_cents &&
          !delta.monthly_missing_amount_count)
      ) {
        continue;
      }
      const monthKey = scopedDashboardTripMonthKpisKey(normalizedScope, month);
      const current = (await kvGetJson(env.FLUXIDI_TRACKING, monthKey)) ?? {};
      const currentCount = Number.isFinite(Number(current.monthly_paid_rides_count))
        ? Math.round(Number(current.monthly_paid_rides_count))
        : 0;
      const currentIncome = Number.isFinite(Number(current.monthly_income_cents))
        ? Math.round(Number(current.monthly_income_cents))
        : 0;
      const currentMissingAmountCount = Number.isFinite(Number(current.monthly_missing_amount_count))
        ? Math.round(Number(current.monthly_missing_amount_count))
        : 0;
      await kvPutJson(
        env.FLUXIDI_TRACKING,
        monthKey,
        {
          month,
          currency: "EUR",
          monthly_paid_rides_count: Math.max(
            0,
            currentCount + delta.monthly_paid_rides_count,
          ),
          monthly_income_cents: Math.max(
            0,
            currentIncome + delta.monthly_income_cents,
          ),
          monthly_missing_amount_count: Math.max(
            0,
            currentMissingAmountCount + delta.monthly_missing_amount_count,
          ),
          updated_at: nowIso(),
        },
      );
    }

    await kvPutJson(
      env.FLUXIDI_TRACKING,
      contribKey,
      { ...next, updated_at: nowIso(), source: sourceTag },
    );
  } catch (err) {
    console.log(
      `[DASHBOARD_KPI][WARN] source=${sourceTag} reason=${safeStr(
        err?.message || err,
        200,
      ) || "unknown"}`,
    );
  }
}

async function getScopedOrLegacySessionForScope(env, scope, sessionId) {
  const scopedKey = scopedSessionKey(scope, sessionId);
  const scopedSession = await kvGetJson(env.FLUXIDI_TRACKING, scopedKey);
  if (scopedSession) {
    if (!recordMatchesTenantCompanyScope(scopedSession, scope)) {
      return { session: null, key: scopedKey, source: "scoped_mismatch" };
    }
    return { session: scopedSession, key: scopedKey, source: "scoped" };
  }

  const legacyKey = `session:${sessionId}`;
  const legacySession = await kvGetJson(env.FLUXIDI_TRACKING, legacyKey);
  if (!legacySession) return { session: null, key: scopedKey, source: "missing" };
  if (!recordMatchesTenantCompanyScope(legacySession, scope)) {
    return { session: null, key: scopedKey, source: "legacy_mismatch" };
  }

  const migrated = applyCanonicalScopeToRecord(legacySession, scope);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedKey, migrated, TTL_SESSION);
  return { session: migrated, key: scopedKey, source: "legacy_copied" };
}

async function getScopedOrLegacyTripForScope(env, scope, tripId) {
  const scopedKey = scopedTripKey(scope, tripId);
  const scopedTrip = await kvGetJson(env.FLUXIDI_TRACKING, scopedKey);
  if (scopedTrip) {
    if (!recordMatchesTenantCompanyScope(scopedTrip, scope)) {
      return { trip: null, key: scopedKey, source: "scoped_mismatch" };
    }
    return { trip: scopedTrip, key: scopedKey, source: "scoped" };
  }

  const legacyKey = tripKey(tripId);
  const legacyTrip = await kvGetJson(env.FLUXIDI_TRACKING, legacyKey);
  if (!legacyTrip) return { trip: null, key: scopedKey, source: "missing" };
  if (!recordMatchesTenantCompanyScope(legacyTrip, scope)) {
    return { trip: null, key: scopedKey, source: "legacy_mismatch" };
  }

  const migrated = applyCanonicalScopeToRecord(legacyTrip, scope);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedKey, migrated, TTL_TRIP);
  return { trip: migrated, key: scopedKey, source: "legacy_copied" };
}

async function getScopedOrLegacyBookingMapForScope(env, scope, bookingId) {
  const scopedKey = scopedBookingSessionKey(scope, bookingId);
  const scopedMap = await kvGetJson(env.FLUXIDI_TRACKING, scopedKey);
  if (scopedMap) {
    if (!recordMatchesTenantCompanyScope(scopedMap, scope)) {
      return { map: null, key: scopedKey, source: "scoped_mismatch" };
    }
    return { map: scopedMap, key: scopedKey, source: "scoped" };
  }

  const legacyKey = `booking:${bookingId}:session`;
  const legacyMap = await kvGetJson(env.FLUXIDI_TRACKING, legacyKey);
  if (!legacyMap) return { map: null, key: scopedKey, source: "missing" };
  if (!recordMatchesTenantCompanyScope(legacyMap, scope)) {
    return { map: null, key: scopedKey, source: "legacy_mismatch" };
  }

  const migrated = applyCanonicalScopeToRecord(legacyMap, scope);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedKey, migrated, TTL_SESSION);
  return { map: migrated, key: scopedKey, source: "legacy_copied" };
}

function normalizeComplianceText(v, fallback = "unknown", maxLen = 64) {
  const text = safeStr(v, maxLen);
  if (!text) return fallback;
  return text.toLowerCase();
}

function isUnknownLikeComplianceValue(v) {
  const raw = String(v ?? "").trim().toLowerCase();
  return (
    raw === "" ||
    raw === "unknown" ||
    raw === "onbekend" ||
    raw === "—" ||
    raw === "-" ||
    raw === "null" ||
    raw === "undefined"
  );
}

function isMollieLikePaymentId(v) {
  const raw = String(v ?? "").trim();
  return /^tr_[a-z0-9]+$/i.test(raw);
}

function resolveDirectTripPaymentProviderForCompliance(trip, paymentPayloadOrResult) {
  const explicitProvider = safeStr(
    trip?.payment_provider ??
      trip?.paymentProvider ??
      paymentPayloadOrResult?.payment_provider ??
      paymentPayloadOrResult?.paymentProvider,
    64,
  );
  if (explicitProvider && !isUnknownLikeComplianceValue(explicitProvider)) {
    return normalizeComplianceText(explicitProvider);
  }

  const source = normalizeComplianceText(
    trip?.payment_source ?? trip?.paymentSource ?? paymentPayloadOrResult?.payment_source ?? paymentPayloadOrResult?.paymentSource,
  );
  const method = normalizeComplianceText(
    trip?.payment_method ?? trip?.paymentMethod ?? paymentPayloadOrResult?.payment_method ?? paymentPayloadOrResult?.paymentMethod,
  );
  const paymentId = safeStr(
    trip?.payment_id ??
      trip?.paymentId ??
      paymentPayloadOrResult?.payment_id ??
      paymentPayloadOrResult?.paymentId,
    128,
  );
  const molliePaymentId = safeStr(
    paymentPayloadOrResult?.mollie_payment_id ??
      paymentPayloadOrResult?.molliePaymentId ??
      trip?.mollie_payment_id ??
      trip?.molliePaymentId ??
      trip?.mollie?.payment_id ??
      trip?.mollie?.id,
    128,
  );
  const hasReliableExternalPaymentId =
    isMollieLikePaymentId(paymentId) || isMollieLikePaymentId(molliePaymentId);
  const manualLikeSources = new Set([
    "in_car",
    "in_vehicle",
    "manual",
    "driver",
    "driver_app",
    "chauffeur",
    "cash",
  ]);
  const manualLikeMethods = new Set([
    "cash",
    "bancontact",
    "card",
    "pin",
    "qr",
    "in_car",
    "manual",
    "driver",
    "chauffeur",
  ]);
  if (
    manualLikeSources.has(source) &&
    manualLikeMethods.has(method) &&
    !hasReliableExternalPaymentId
  ) {
    return "manual";
  }

  return normalizeComplianceText(explicitProvider);
}

function buildComplianceAppendUrl(baseUrlRaw) {
  const normalized = safeStr(baseUrlRaw, 512);
  if (!normalized) return null;
  try {
    const parsed = new URL(normalized);
    parsed.search = "";
    parsed.hash = "";
    const normalizedPath = parsed.pathname.replace(/\/+$/, "");
    if (normalizedPath === COMPLIANCE_APPEND_PATH) {
      return parsed;
    }
    if (normalizedPath === "" || normalizedPath === "/") {
      parsed.pathname = COMPLIANCE_APPEND_PATH;
      return parsed;
    }
    return null;
  } catch (_) {
    return null;
  }
}

function buildDirectTripStopComplianceEvent(trip, stopPayload, stoppedAt, totals, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantFromTrip = safeStr(
    trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId,
    96,
  );
  const tenantFromPayload = safeStr(
    stopPayload?.tenant_id ?? stopPayload?.tenantId ?? stopPayload?.company_id ?? stopPayload?.companyId,
    96,
  );
  const tenantId = normalizedScope?.tenant_id ?? tenantFromTrip ?? tenantFromPayload;

  const companyFromTrip = safeStr(trip?.company_id ?? trip?.companyId, 96);
  const companyFromPayload = safeStr(stopPayload?.company_id ?? stopPayload?.companyId, 96);
  // TODO: tighten tenant/company authority from a single canonical source.
  const companyId = normalizedScope?.company_id ?? companyFromTrip ?? companyFromPayload;

  if (!tenantId || !companyId) {
    console.log(
      "[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope",
    );
    return null;
  }

  const pickup = trip?.origin && typeof trip.origin === "object"
    ? {
        label: safeStr(trip.origin.label, 256) ?? null,
        lat: Number.isFinite(Number(trip.origin.lat)) ? Number(trip.origin.lat) : null,
        lng: Number.isFinite(Number(trip.origin.lon)) ? Number(trip.origin.lon) : null,
      }
    : null;
  const dropoff = trip?.destination && typeof trip.destination === "object"
    ? {
        label: safeStr(trip.destination.label, 256) ?? null,
        lat: Number.isFinite(Number(trip.destination.lat)) ? Number(trip.destination.lat) : null,
        lng: Number.isFinite(Number(trip.destination.lon)) ? Number(trip.destination.lon) : null,
      }
    : null;

  const paymentAmountRaw = trip?.payment_amount ?? trip?.paymentAmount;
  const paymentAmount = Number.isFinite(Number(paymentAmountRaw))
    ? Number(paymentAmountRaw)
    : null;
  const legId =
    safeStr(
      trip?.leg_id ??
        trip?.legId ??
        stopPayload?.leg_id ??
        stopPayload?.legId,
      128,
    ) ?? undefined;
  const legType =
    safeStr(
      trip?.leg_type ??
        trip?.legType ??
        stopPayload?.leg_type ??
        stopPayload?.legType,
      64,
    ) ?? undefined;
  const parentBookingId =
    safeStr(
      trip?.parent_booking_id ??
        trip?.parentBookingId ??
        stopPayload?.parent_booking_id ??
        stopPayload?.parentBookingId,
      128,
    ) ?? undefined;
  const rowKey =
    safeStr(
      trip?.row_key ??
        trip?.rowKey ??
        stopPayload?.row_key ??
        stopPayload?.rowKey,
      196,
    ) ?? undefined;
  const fareCurrency =
    (safeStr(totals?.currency, 8) ??
      safeStr(trip?.currency, 8) ??
      safeStr(trip?.pricing_snapshot?.currency, 8) ??
      "EUR").toUpperCase();

  return {
    event_type: "ride_stop",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr(trip?.booking_id ?? trip?.bookingId, 128) ?? undefined,
    trip_id: safeStr(trip?.trip_id ?? trip?.tripId, 128) ?? undefined,
    ...(legId ? { leg_id: legId } : {}),
    ...(legType ? { leg_type: legType } : {}),
    ...(parentBookingId ? { parent_booking_id: parentBookingId } : {}),
    ...(rowKey ? { row_key: rowKey } : {}),
    session_id: safeStr(trip?.session_id ?? trip?.sessionId, 128) ?? undefined,
    receipt_reference: safeStr(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? undefined,
    ride_type: "direct",
    lifecycle_status: "stopped",
    timestamps: {
      event_at_utc: stoppedAt,
      started_at_utc: safeStr(trip?.started_at ?? trip?.startedAt ?? trip?.created_at, 64) ?? null,
      stopped_at_utc: stoppedAt,
    },
    driver: {
      driver_id: safeStr(trip?.driver_id ?? trip?.driverId, 96) ?? null,
    },
    vehicle: {
      vehicle_id: safeStr(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null,
      license_plate: safeStr(trip?.license_plate ?? trip?.licensePlate, 64) ?? undefined,
    },
    locations: {
      pickup,
      dropoff,
    },
    fare: {
      currency: fareCurrency,
      distance_km: Number.isFinite(Number(totals?.km_total)) ? Number(totals.km_total) : null,
      wait_seconds_total: Number.isFinite(Number(totals?.wait_seconds_total))
        ? Number(totals.wait_seconds_total)
        : null,
      total_amount: Number.isFinite(Number(totals?.total_eur)) ? Number(totals.total_eur) : null,
    },
    payment: {
      status: normalizeComplianceText(trip?.payment_status ?? trip?.paymentStatus),
      method: normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod),
      source: normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource),
      provider: normalizeComplianceText(trip?.payment_provider ?? trip?.paymentProvider),
      amount: paymentAmount ?? undefined,
      currency: fareCurrency,
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/stop",
      backend_confirmed: true,
      validation_state: "exportable",
    },
  };
}

function buildPlannedTripStopComplianceEvent(trip, stopPayload, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantFromPayload = safeStr(
    stopPayload?.tenant_id ?? stopPayload?.tenantId ?? stopPayload?.company_id ?? stopPayload?.companyId,
    96,
  );
  const tenantFromTrip = safeStr(
    trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId,
    96,
  );
  const tenantId = normalizedScope?.tenant_id ?? tenantFromPayload ?? tenantFromTrip;

  const companyFromPayload = safeStr(stopPayload?.company_id ?? stopPayload?.companyId, 96);
  const companyFromTrip = safeStr(trip?.company_id ?? trip?.companyId, 96);
  // TODO: tighten tenant/company authority from a single canonical source.
  const companyId = normalizedScope?.company_id ?? companyFromPayload ?? companyFromTrip;
  if (!tenantId || !companyId) {
    console.log(
      "[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope",
    );
    return null;
  }

  const stoppedAt = safeStr(
    trip?.stopped_at ?? trip?.stoppedAt ?? stopPayload?.stopped_at ?? stopPayload?.client_stopped_at,
    64,
  ) ?? null;
  const startedAt = safeStr(
    trip?.started_at ?? trip?.startedAt ?? stopPayload?.started_at ?? stopPayload?.client_started_at,
    64,
  ) ?? null;
  const fareCurrency =
    (safeStr(trip?.currency, 8) ??
      safeStr(stopPayload?.currency, 8) ??
      safeStr(trip?.pricing_snapshot?.currency, 8) ??
      "EUR").toUpperCase();
  const paymentAmountRaw = trip?.payment_amount ?? trip?.paymentAmount;
  const paymentAmount = Number.isFinite(Number(paymentAmountRaw))
    ? Number(paymentAmountRaw)
    : null;
  const legId =
    safeStr(
      trip?.leg_id ??
        trip?.legId ??
        stopPayload?.leg_id ??
        stopPayload?.legId,
      128,
    ) ?? undefined;
  const legType =
    safeStr(
      trip?.leg_type ??
        trip?.legType ??
        stopPayload?.leg_type ??
        stopPayload?.legType,
      64,
    ) ?? undefined;
  const parentBookingId =
    safeStr(
      trip?.parent_booking_id ??
        trip?.parentBookingId ??
        stopPayload?.parent_booking_id ??
        stopPayload?.parentBookingId,
      128,
    ) ?? undefined;
  const rowKey =
    safeStr(
      trip?.row_key ??
        trip?.rowKey ??
        stopPayload?.row_key ??
        stopPayload?.rowKey,
      196,
    ) ?? undefined;

  const pickup = trip?.origin && typeof trip.origin === "object"
    ? {
        label: safeStr(trip.origin.label, 256) ?? null,
        lat: Number.isFinite(Number(trip.origin.lat)) ? Number(trip.origin.lat) : null,
        lng: Number.isFinite(Number(trip.origin.lon)) ? Number(trip.origin.lon) : null,
      }
    : null;
  const dropoff = trip?.destination && typeof trip.destination === "object"
    ? {
        label: safeStr(trip.destination.label, 256) ?? null,
        lat: Number.isFinite(Number(trip.destination.lat)) ? Number(trip.destination.lat) : null,
        lng: Number.isFinite(Number(trip.destination.lon)) ? Number(trip.destination.lon) : null,
      }
    : null;

  return {
    event_type: "ride_stop",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr(trip?.booking_id ?? trip?.bookingId ?? stopPayload?.booking_id, 128) ?? undefined,
    trip_id: safeStr(trip?.trip_id ?? trip?.tripId, 128) ?? undefined,
    leg_id: legId,
    leg_type: legType,
    parent_booking_id: parentBookingId,
    row_key: rowKey,
    session_id: safeStr(trip?.session_id ?? trip?.sessionId, 128) ?? undefined,
    receipt_reference: safeStr(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? undefined,
    ride_type: "planned",
    lifecycle_status: "stopped",
    timestamps: {
      event_at_utc: stoppedAt,
      started_at_utc: startedAt,
      stopped_at_utc: stoppedAt,
    },
    driver: {
      driver_id: safeStr(trip?.driver_id ?? trip?.driverId, 96) ?? null,
    },
    vehicle: {
      vehicle_id: safeStr(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null,
    },
    locations: {
      pickup,
      dropoff,
    },
    fare: {
      currency: fareCurrency,
      distance_km: Number.isFinite(Number(trip?.km_total)) ? Number(trip.km_total) : null,
      wait_seconds_total: Number.isFinite(Number(trip?.wait_seconds_total))
        ? Number(trip.wait_seconds_total)
        : null,
      total_amount: Number.isFinite(Number(trip?.total_eur)) ? Number(trip.total_eur) : null,
    },
    payment: {
      status: normalizeComplianceText(trip?.payment_status ?? trip?.paymentStatus),
      method: normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod),
      source: normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource),
      provider: normalizeComplianceText(trip?.payment_provider ?? trip?.paymentProvider),
      amount: paymentAmount ?? undefined,
      currency: fareCurrency,
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/record-planned-stop",
      backend_confirmed: true,
      validation_state: "exportable",
    },
  };
}

function normalizeCompliancePaymentStatus(value) {
  const raw = safeStr(value, 64);
  if (!raw) return "unknown";
  const s = raw.toLowerCase();
  if (s === "paid" || s === "confirmed" || s === "completed" || s === "success" || s === "settled") {
    return "paid";
  }
  if (s === "pending" || s === "authorized" || s === "open" || s === "processing") {
    return "pending";
  }
  if (s === "failed" || s === "cancelled" || s === "canceled" || s === "declined") {
    return "failed";
  }
  if (s === "unpaid" || s === "not_paid") {
    return "unpaid";
  }
  return "unknown";
}

function buildTripPaymentUpdateComplianceEvent(trip, paymentPayloadOrResult, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantFromPayload = safeStr(
    paymentPayloadOrResult?.tenant_id ??
      paymentPayloadOrResult?.tenantId ??
      paymentPayloadOrResult?.company_id ??
      paymentPayloadOrResult?.companyId,
    96,
  );
  const tenantFromTrip = safeStr(
    trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId,
    96,
  );
  const tenantId = normalizedScope?.tenant_id ?? tenantFromPayload ?? tenantFromTrip;
  const companyFromPayload = safeStr(
    paymentPayloadOrResult?.company_id ?? paymentPayloadOrResult?.companyId,
    96,
  );
  const companyFromTrip = safeStr(trip?.company_id ?? trip?.companyId, 96);
  // TODO: tighten tenant/company authority from a single canonical source.
  const companyId = normalizedScope?.company_id ?? companyFromPayload ?? companyFromTrip;
  if (!tenantId || !companyId) {
    console.log(
      "[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope",
    );
    return null;
  }

  const paidAt =
    safeStr(
      trip?.paid_at ??
        trip?.paidAt ??
        paymentPayloadOrResult?.paid_at ??
        paymentPayloadOrResult?.paidAt,
      64,
    ) ?? nowIso();
  const fareCurrency =
    (safeStr(trip?.currency, 8) ??
      safeStr(paymentPayloadOrResult?.currency, 8) ??
      safeStr(trip?.pricing_snapshot?.currency, 8) ??
      "EUR").toUpperCase();
  const paymentAmountRaw =
    paymentPayloadOrResult?.amount ??
    paymentPayloadOrResult?.price ??
    paymentPayloadOrResult?.total ??
    trip?.payment_amount ??
    trip?.paymentAmount;
  const paymentAmount = Number.isFinite(Number(paymentAmountRaw))
    ? Number(paymentAmountRaw)
    : null;
  const fareTotalRaw = trip?.total_eur ?? trip?.totalEur ?? paymentPayloadOrResult?.total;
  const fareTotal = Number.isFinite(Number(fareTotalRaw)) ? Number(fareTotalRaw) : null;
  const legId =
    safeStr(
      trip?.leg_id ??
        trip?.legId ??
        paymentPayloadOrResult?.leg_id ??
        paymentPayloadOrResult?.legId,
      128,
    ) ?? undefined;
  const legType =
    safeStr(
      trip?.leg_type ??
        trip?.legType ??
        paymentPayloadOrResult?.leg_type ??
        paymentPayloadOrResult?.legType,
      64,
    ) ?? undefined;
  const parentBookingId =
    safeStr(
      trip?.parent_booking_id ??
        trip?.parentBookingId ??
        paymentPayloadOrResult?.parent_booking_id ??
        paymentPayloadOrResult?.parentBookingId,
      128,
    ) ?? undefined;
  const rowKey =
    safeStr(
      trip?.row_key ??
        trip?.rowKey ??
        paymentPayloadOrResult?.row_key ??
        paymentPayloadOrResult?.rowKey,
      196,
    ) ?? undefined;
  const rideType = (safeStr(trip?.trip_id ?? trip?.tripId, 160) ?? "").toLowerCase().startsWith("planned_")
    ? "planned"
    : "direct";

  return {
    event_type: "payment_update",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr(trip?.booking_id ?? trip?.bookingId, 128) ?? undefined,
    trip_id: safeStr(trip?.trip_id ?? trip?.tripId, 128) ?? undefined,
    leg_id: legId,
    leg_type: legType,
    parent_booking_id: parentBookingId,
    row_key: rowKey,
    session_id: safeStr(trip?.session_id ?? trip?.sessionId, 128) ?? undefined,
    receipt_reference: safeStr(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? undefined,
    ride_type: rideType,
    lifecycle_status: "payment_updated",
    timestamps: {
      event_at_utc: paidAt,
      paid_at_utc: paidAt,
    },
    driver: {
      driver_id: safeStr(trip?.driver_id ?? trip?.driverId, 96) ?? null,
    },
    vehicle: {
      vehicle_id: safeStr(trip?.vehicle_id ?? trip?.vehicleId, 96) ?? null,
    },
    fare: {
      currency: fareCurrency,
      total_amount: fareTotal,
    },
    payment: {
      status: normalizeCompliancePaymentStatus(trip?.payment_status ?? trip?.paymentStatus),
      method: normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod),
      source: normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource),
      provider: resolveDirectTripPaymentProviderForCompliance(trip, paymentPayloadOrResult),
      payment_id: safeStr(
        trip?.payment_id ??
          trip?.paymentId ??
          paymentPayloadOrResult?.payment_id ??
          paymentPayloadOrResult?.paymentId,
        128,
      ) ?? undefined,
      amount: paymentAmount ?? undefined,
      currency: fareCurrency,
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/payment",
      backend_confirmed: true,
      validation_state: "payment_update",
    },
  };
}

async function emitComplianceEventBestEffort(env, event, options = {}) {
  try {
    const baseUrlRaw = safeStr(env?.COMPLIANCE_API_URL, 512);
    const adminToken = safeStr(env?.COMPLIANCE_ADMIN_TOKEN, 512);
    if (!baseUrlRaw || !adminToken) {
      return { ok: false, skipped: "missing_config" };
    }
    if (!event || typeof event !== "object" || Array.isArray(event)) {
      return { ok: false, skipped: "invalid_event" };
    }
    const appendUrl = buildComplianceAppendUrl(baseUrlRaw);
    if (!appendUrl) {
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
      const logLabel = safeStr(options?.logLabel, 64) ?? "ride_stop";
      const resp = hasServiceBinding
        ? await env.COMPLIANCE_WORKER.fetch(req)
        : await fetch(req);

      if (!resp.ok) {
        console.log(
          `[COMPLIANCE_EMIT][${logLabel}] failed status=${resp.status} transport=${transport} origin=${appendUrl.origin} path=${appendUrl.pathname}`,
        );
        return { ok: false, status: resp.status };
      }
      return { ok: true, status: resp.status };
    } catch (err) {
      if (err?.name === "AbortError") {
        const logLabel = safeStr(options?.logLabel, 64) ?? "ride_stop";
        console.log(`[COMPLIANCE_EMIT][${logLabel}] failed error=timeout`);
        return { ok: false, error: "timeout" };
      }
      const logLabel = safeStr(options?.logLabel, 64) ?? "ride_stop";
      console.log(`[COMPLIANCE_EMIT][${logLabel}] failed error=fetch_failed`);
      return { ok: false, error: "fetch_failed" };
    } finally {
      clearTimeout(timer);
    }
  } catch (_) {
    return { ok: false, error: "internal_error" };
  }
}

function randToken(len = 20) {
  const alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  let out = "";
  for (let i = 0; i < len; i++) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

async function kvPutJson(kv, key, value, ttlSeconds) {
  const opts = {};
  if (ttlSeconds && Number.isFinite(ttlSeconds)) {
    opts.expirationTtl = Math.floor(ttlSeconds);
  }
  await kv.put(key, JSON.stringify(value), opts);
}

async function kvGetJson(kv, key) {
  const raw = await kv.get(key);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function kvDel(kv, key) {
  try {
    await kv.delete(key);
  } catch {
    // ignore
  }
}

// -------------------------------
// TTLs
// -------------------------------
const TTL_SESSION = 60 * 60 * 24 * 14;      // 14 days
const TTL_LASTPING = 60 * 60 * 24 * 14;     // 14 days
const TTL_INDEX = 60 * 60 * 24 * 30;        // 30 days
const TTL_PUBLIC_TOKEN = 60 * 60 * 24 * 14; // 14 days
const TTL_TRIP = 60 * 60 * 24 * 30;         // 30 days

// -------------------------------
// Mapbox helpers (server-side)
// -------------------------------
async function mapboxGeocode(token, q) {
  const query = encodeURIComponent(q);
  // limit=1 is fine for our driver UI; you can raise later.
  const url =
    `https://api.mapbox.com/geocoding/v5/mapbox.places/${query}.json` +
    `?limit=1&language=nl&country=BE&access_token=${encodeURIComponent(token)}`;

  const r = await fetch(url, { method: "GET" });
  if (!r.ok) throw new Error(`Mapbox geocode failed (${r.status})`);
  const j = await r.json();
  const f = Array.isArray(j.features) ? j.features[0] : null;
  if (!f || !Array.isArray(f.center) || f.center.length < 2) {
    throw new Error("Mapbox geocode: no result");
  }
  const lon = Number(f.center[0]);
  const lat = Number(f.center[1]);
  if (!Number.isFinite(lat) || !Number.isFinite(lon)) {
    throw new Error("Mapbox geocode: invalid coordinates");
  }
  return { lat, lon, place_name: f.place_name || q };
}

async function mapboxDirections(token, from, to, profile = "driving") {
  const prof = (profile || "driving").toString().trim().toLowerCase();
  const allowed = new Set(["driving", "driving-traffic", "walking", "cycling"]);
  const p = allowed.has(prof) ? prof : "driving";

  // Mapbox expects lon,lat;lon,lat
  const coords = `${from.lon},${from.lat};${to.lon},${to.lat}`;
  const url =
    `https://api.mapbox.com/directions/v5/mapbox/${p}/${coords}` +
    `?geometries=geojson&overview=full&steps=false&access_token=${encodeURIComponent(token)}`;

  const r = await fetch(url, { method: "GET" });
  if (!r.ok) throw new Error(`Mapbox directions failed (${r.status})`);
  const j = await r.json();
  const route = Array.isArray(j.routes) ? j.routes[0] : null;
  if (!route || !route.geometry) throw new Error("Mapbox directions: no route");
  return {
    distance_m: Number(route.distance) || 0,
    duration_s: Number(route.duration) || 0,
    geometry: route.geometry, // GeoJSON LineString
  };
}

// -------------------------------
// Direct trip helpers
// -------------------------------
function makeTripId() {
  if (globalThis.crypto && typeof globalThis.crypto.randomUUID === "function") {
    return `trip_${globalThis.crypto.randomUUID()}`;
  }
  return `trip_${Date.now().toString(36)}_${randToken(12)}`;
}

function tripKey(tripId) {
  return `trip:${tripId}`;
}

function money2Num(value) {
  return Math.round((Number(value) || 0) * 100) / 100;
}

function normalizeDestination(v) {
  if (!v || typeof v !== "object") return null;
  const label = safeStr(v.label ?? v.address ?? v.text ?? "", 256);
  const lat = safeNum(v.lat, -90, 90);
  const lon = safeNum(v.lon ?? v.lng, -180, 180);
  const out = {};
  if (label) out.label = label;
  if (lat !== null && lon !== null) {
    out.lat = lat;
    out.lon = lon;
  }
  return Object.keys(out).length ? out : null;
}

function normalizePricingSnapshot(v) {
  if (!v || typeof v !== "object") throw new Error("pricing_snapshot is required");
  const start_fee = safeNum(v.start_fee, 0, 10000);
  const per_km = safeNum(v.per_km, 0, 1000);
  const wait_per_min = safeNum(v.wait_per_min, 0, 1000);
  if (start_fee === null) throw new Error("pricing_snapshot.start_fee is required");
  if (per_km === null) throw new Error("pricing_snapshot.per_km is required");
  if (wait_per_min === null) throw new Error("pricing_snapshot.wait_per_min is required");
  const vat_rate_raw = safeNum(v.vat_rate, 0, 1);
  const vat_rate = vat_rate_raw === null ? 0 : vat_rate_raw;
  const vat_mode_raw = String(v.vat_mode ?? v.vatMode ?? "incl").trim().toLowerCase();
  const vat_mode = vat_mode_raw === "excl" ? "excl" : "incl";
  return {
    start_fee,
    per_km,
    wait_per_min,
    currency: safeStr(v.currency ?? "EUR", 8) ?? "EUR",
    vat_rate,
    vat_mode,
  };
}

function normalizeBookingDetails(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const allowed = [
    "pickup_address",
    "destination_address",
    "scheduled_pickup_at",
    "subtype",
    "customer_name",
    "customer_phone",
    "customer_email",
    "customerName",
    "customerPhone",
    "customerEmail",
    "name",
    "phone",
    "tel",
    "mobile",
    "email",
    "customer_country",
    "customerCountry",
    "country",
    "countryCode",
    "country_iso",
    "countryIso",
    "locale",
    "language",
    "phone_country_code",
    "phoneCountryCode",
    "dial_code",
    "dialCode",
    "service_type",
    "serviceType",
    "service",
    "tier",
    "vehicle_tier",
    "vehicleTier",
    "passengers",
    "luggage_count",
    "booked_wait_minutes",
    "booking_status",
    "leg_id",
    "legId",
    "leg_type",
    "legType",
    "row_key",
    "rowKey",
    "parent_booking_id",
    "parentBookingId",
    "is_operational_leg",
    "isOperationalLeg",
    "booking_total_eur",
    "segment_price_eur",
    "leg_price_incl_vat",
    "legPriceInclVat",
    "outbound_price_eur",
    "return_price_eur",
    "payment_status",
    "paymentStatus",
    "payment_method",
    "paymentMethod",
    "payment_source",
    "paymentSource",
    "return_scheduled_pickup_at",
    "return_route",
    "route_segments",
    "stops",
    "extras",
    "notes",
    "currency",
  ];
  const out = {};
  for (const key of allowed) {
    if (!(key in value)) continue;
    const v = value[key];
    if (v === null || v === undefined) continue;
    if (typeof v === "string") {
      const s = safeStr(v, key === "route_segments" ? 4096 : 1024);
      if (s) out[key] = s;
      continue;
    }
    if (typeof v === "number") {
      if (Number.isFinite(v)) out[key] = v;
      continue;
    }
    if (typeof v === "boolean") {
      out[key] = v;
      continue;
    }
    if (key === "route_segments" && Array.isArray(v)) {
      out[key] = v.slice(0, 12).map((segment) => {
        if (!segment || typeof segment !== "object") return null;
        return {
          from: safeStr(segment.from, 1024) ?? null,
          to: safeStr(segment.to, 1024) ?? null,
          distance_km: safeNum(segment.distance_km, 0, 100000),
          duration_min: safeNum(segment.duration_min, 0, 100000),
          kind: safeStr(segment.kind, 32) ?? null,
        };
      }).filter(Boolean);
      continue;
    }
    if (Array.isArray(v)) {
      out[key] = v.slice(0, 20).map((x) => safeStr(x, 512)).filter(Boolean);
    }
  }
  return Object.keys(out).length ? out : null;
}

async function prependIndex(kv, key, value, maxItems) {
  const existing = (await kvGetJson(kv, key)) ?? [];
  const arr = Array.isArray(existing) ? existing : [];
  const next = [value, ...arr.filter((x) => x !== value)].slice(0, maxItems);
  await kvPutJson(kv, key, next, TTL_TRIP);
}

function directTripTotals(trip, kmTotal, waitSecondsTotal) {
  const pricing = trip?.pricing_snapshot || {};
  const startFee = Number(pricing.start_fee) || 0;
  const perKm = Number(pricing.per_km) || 0;
  const waitPerMin = Number(pricing.wait_per_min) || 0;
  const waitMinutes = waitSecondsTotal / 60;
  const rawTotal = startFee + (kmTotal * perKm) + (waitMinutes * waitPerMin);
  const vatRateRaw = Number(pricing.vat_rate);
  const vatRate = Number.isFinite(vatRateRaw)
    ? Math.max(0, Math.min(1, vatRateRaw))
    : 0;
  const vatModeRaw = String(pricing.vat_mode ?? pricing.vatMode ?? "incl")
    .trim()
    .toLowerCase();
  const vatMode = vatModeRaw === "excl" ? "excl" : "incl";
  const hasVatMeta = pricing.vat_rate != null || pricing.vat_mode != null || pricing.vatMode != null;

  let priceExVat = rawTotal;
  let priceVat = 0;
  let priceInclVat = rawTotal;
  if (hasVatMeta) {
    if (vatMode === "incl") {
      priceExVat = vatRate > 0 ? rawTotal / (1 + vatRate) : rawTotal;
      priceVat = rawTotal - priceExVat;
      priceInclVat = rawTotal;
    } else {
      priceExVat = rawTotal;
      priceVat = rawTotal * vatRate;
      priceInclVat = rawTotal + priceVat;
    }
  }

  return {
    km_total: kmTotal,
    wait_seconds_total: waitSecondsTotal,
    wait_minutes: money2Num(waitMinutes),
    total_eur: money2Num(priceInclVat),
    price_ex_vat: money2Num(priceExVat),
    price_vat: money2Num(priceVat),
    price_incl_vat: money2Num(priceInclVat),
    vat_rate: vatRate,
    vat_mode: vatMode,
    currency: safeStr(pricing.currency ?? "EUR", 8) ?? "EUR",
  };
}

function summarizeTrip(trip) {
  const origin =
    trip?.origin && typeof trip.origin === "object"
      ? trip.origin
      : null;
  const destination =
    trip?.destination && typeof trip.destination === "object"
      ? trip.destination
      : null;
  const bookingDetails = normalizeBookingDetails(trip?.booking_details);
  return {
    trip_id: trip?.trip_id ?? null,
    kind: trip?.kind ?? null,
    booking_id: trip?.booking_id ?? null,
    tenant_id: trip?.tenant_id ?? null,
    driver_id: trip?.driver_id ?? null,
    vehicle_id: trip?.vehicle_id ?? null,
    status: trip?.status ?? null,
    started_at: trip?.started_at ?? trip?.created_at ?? null,
    stopped_at: trip?.stopped_at ?? null,
    origin: origin
      ? {
          label: origin.label ?? null,
          lat: origin.lat ?? null,
          lon: origin.lon ?? null,
        }
      : null,
    destination: destination
      ? {
          label: destination.label ?? null,
          lat: destination.lat ?? null,
          lon: destination.lon ?? null,
        }
      : null,
    km_total: Number.isFinite(Number(trip?.km_total)) ? Number(trip.km_total) : null,
    wait_seconds_total: Number.isFinite(Number(trip?.wait_seconds_total))
      ? Number(trip.wait_seconds_total)
      : 0,
    total_eur: Number.isFinite(Number(trip?.total_eur)) ? Number(trip.total_eur) : null,
    currency: safeStr(trip?.currency ?? trip?.pricing_snapshot?.currency ?? "EUR", 8) ?? "EUR",
    payment_status: safeStr(trip?.payment_status ?? trip?.paymentStatus ?? "", 32) ?? null,
    paymentStatus: safeStr(trip?.paymentStatus ?? trip?.payment_status ?? "", 32) ?? null,
    payment_method: safeStr(trip?.payment_method ?? trip?.paymentMethod ?? "", 32) ?? null,
    paymentMethod: safeStr(trip?.paymentMethod ?? trip?.payment_method ?? "", 32) ?? null,
    payment_source: safeStr(trip?.payment_source ?? trip?.paymentSource ?? "", 32) ?? null,
    paymentSource: safeStr(trip?.paymentSource ?? trip?.payment_source ?? "", 32) ?? null,
    paid_at: safeStr(trip?.paid_at ?? trip?.paidAt ?? "", 64) ?? null,
    paidAt: safeStr(trip?.paidAt ?? trip?.paid_at ?? "", 64) ?? null,
    paid_by_driver_id: safeStr(trip?.paid_by_driver_id ?? trip?.paidByDriverId ?? "", 96) ?? null,
    paidByDriverId: safeStr(trip?.paidByDriverId ?? trip?.paid_by_driver_id ?? "", 96) ?? null,
    payment_amount: Number.isFinite(Number(trip?.payment_amount))
      ? Number(trip.payment_amount)
      : Number.isFinite(Number(trip?.paymentAmount))
      ? Number(trip.paymentAmount)
      : null,
    paymentAmount: Number.isFinite(Number(trip?.paymentAmount))
      ? Number(trip.paymentAmount)
      : Number.isFinite(Number(trip?.payment_amount))
      ? Number(trip.payment_amount)
      : null,
    booking_details: bookingDetails,
  };
}

// -------------------------------
// Handlers
// -------------------------------
async function handleHealth(req, env, origin) {
  return withCors(
    json({ ok: true, service: "fluxidi-tracking-api", time: nowIso() }, { status: 200 }),
    origin
  );
}

async function _collectTripKpiPendingDiagnostics(env, scope) {
  const out = {
    trip_missing: 0,
    paid_but_not_completed: 0,
    trip_missing_active: 0,
    paid_but_not_completed_active: 0,
  };
  try {
    if (!env?.FLUXIDI_TRACKING || typeof env.FLUXIDI_TRACKING.list !== "function") {
      return out;
    }
    const prefix = scopedDashboardTripPendingBookingPrefix(scope);
    let cursor = undefined;
    let scanned = 0;
    const maxScan = 5000;
    do {
      const page = await env.FLUXIDI_TRACKING.list({ prefix, limit: 1000, cursor });
      for (const keyMeta of page?.keys || []) {
        if (scanned >= maxScan) break;
        scanned += 1;
        const key = safeStr(keyMeta?.name, 220);
        if (!key) continue;
        const marker = await kvGetJson(env.FLUXIDI_TRACKING, key);
        if (!marker || typeof marker !== "object" || Array.isArray(marker)) continue;
        const reason = (safeStr(marker?.reason, 64) ?? "").toLowerCase();
        if (reason === "trip_missing") out.trip_missing += 1;
        const paid = normalizeCompliancePaymentStatus(marker?.payment_status) === "paid";
        const completed = marker?.completed === true;
        if (paid && !completed) out.paid_but_not_completed += 1;
        const classification = await _classifyTripKpiPendingMarker(env, scope, marker);
        if (classification?.active === true) {
          if (reason === "trip_missing") out.trip_missing_active += 1;
          if (paid && !completed) out.paid_but_not_completed_active += 1;
        }
      }
      if (scanned >= maxScan) break;
      cursor = page?.cursor;
      if (page?.list_complete !== false) break;
    } while (cursor);
  } catch (_) {
    // best effort only
  }
  return out;
}

function _tripKpiMask(value) {
  const text = safeStr(value, 220);
  if (!text) return null;
  if (text.length <= 10) return text;
  return `${text.slice(0, 3)}...${text.slice(-3)}`;
}

function _tripKpiNormalizeToken(value) {
  return String(value ?? "").trim().toLowerCase().replaceAll("-", "_").replaceAll(" ", "_");
}

const TRIP_KPI_TERMINAL_BOOKING_STATUS_SET = new Set([
  "cancelled",
  "canceled",
  "deleted",
  "archived",
  "closed",
  "failed",
  "expired",
  "declined",
  "completed",
  "complete",
  "done",
  "finished",
]);

function _tripKpiVisibleAmountCentsFromTrip(trip) {
  const amountCents =
    _dashboardTripAmountCents(trip?.payment_amount) ??
    _dashboardTripAmountCents(trip?.paymentAmount) ??
    _dashboardTripAmountCents(trip?.final_amount) ??
    _dashboardTripAmountCents(trip?.finalAmount) ??
    _dashboardTripAmountCents(trip?.final_total) ??
    _dashboardTripAmountCents(trip?.finalTotal) ??
    _dashboardTripAmountCents(trip?.total_eur) ??
    _dashboardTripAmountCents(trip?.totalEur) ??
    _dashboardTripAmountCents(trip?.total) ??
    _dashboardTripAmountCents(trip?.booking_details?.booking_total_eur) ??
    _dashboardTripAmountCents(trip?.booking_details?.segment_price_eur) ??
    _dashboardTripAmountCents(trip?.booking_details?.outbound_price_eur);
  if (!Number.isFinite(Number(amountCents))) return null;
  const normalized = Math.round(Number(amountCents));
  return normalized > 0 ? normalized : null;
}

function _tripKpiHasVisiblePaymentArtifact(trip, bookingMap = null) {
  const paymentStatus = normalizeCompliancePaymentStatus(
    trip?.payment_status ?? trip?.paymentStatus,
  );
  if (paymentStatus === "pending" || paymentStatus === "failed") return true;
  const paymentMethod = normalizeComplianceText(trip?.payment_method ?? trip?.paymentMethod, "");
  const paymentSource = normalizeComplianceText(trip?.payment_source ?? trip?.paymentSource, "");
  if (paymentMethod && paymentMethod !== "unknown") return true;
  if (paymentSource && paymentSource !== "unknown") return true;
  const paymentId = safeStr(
    trip?.payment_id ??
      trip?.paymentId ??
      trip?.mollie_payment_id ??
      trip?.molliePaymentId ??
      trip?.mollie?.payment_id ??
      trip?.mollie?.id,
    160,
  );
  if (paymentId) return true;
  const receiptRef = safeStr(trip?.receipt_reference ?? trip?.receiptReference, 128);
  if (receiptRef) return true;
  const bookingStatus = _tripKpiNormalizeToken(
    trip?.booking_details?.booking_status ??
      bookingMap?.booking_status ??
      bookingMap?.bookingStatus,
  );
  if (bookingStatus.includes("payment")) return true;
  const hasTripProof =
    !!safeStr(trip?.trip_id ?? trip?.tripId, 160) ||
    !!safeStr(trip?.booking_id ?? trip?.bookingId, 160);
  if (hasTripProof && (_tripKpiVisibleAmountCentsFromTrip(trip) ?? 0) > 0) {
    return true;
  }
  return false;
}

function _tripKpiClassifyUnpaidCompleted(trip, bookingMap = null) {
  if (!trip || typeof trip !== "object") return "unpaid_completed_tracking_only";
  const tripStatus = normalizeDashboardTripLifecycleStatus(
    trip?.status ?? trip?.lifecycle_status,
  );
  const paymentStatus = normalizeCompliancePaymentStatus(
    trip?.payment_status ?? trip?.paymentStatus,
  );
  const amountCents = _tripKpiVisibleAmountCentsFromTrip(trip) ?? 0;
  const tripIdToken = (safeStr(trip?.trip_id ?? trip?.tripId, 160) ?? "").toLowerCase();
  const hasLegIdentity =
    !!safeStr(
      trip?.leg_id ??
        trip?.legId ??
        trip?.booking_details?.leg_id ??
        trip?.booking_details?.legId,
      160,
    ) ||
    !!safeStr(
      trip?.leg_type ??
        trip?.legType ??
        trip?.booking_details?.leg_type ??
        trip?.booking_details?.legType,
      64,
    ) ||
    trip?.booking_details?.is_operational_leg === true ||
    trip?.booking_details?.isOperationalLeg === true;
  const isPlannedOperationalLeg =
    tripIdToken.startsWith("planned_") && hasLegIdentity;
  const isCompletedUnpaidOperationalLegActionable =
    isPlannedOperationalLeg &&
    tripStatus === "completed" &&
    paymentStatus !== "paid" &&
    amountCents > 0;
  const bookingId = safeStr(trip?.booking_id ?? trip?.bookingId, 160);
  if (!bookingId || !bookingMap || typeof bookingMap !== "object") {
    if (isCompletedUnpaidOperationalLegActionable) {
      return "unpaid_completed_actionable";
    }
    return "unpaid_completed_tracking_only";
  }
  const bookingStatus = _tripKpiNormalizeToken(
    trip?.booking_details?.booking_status ??
      bookingMap?.booking_status ??
      bookingMap?.bookingStatus,
  );
  const terminal = tripStatus === "cancelled" || TRIP_KPI_TERMINAL_BOOKING_STATUS_SET.has(bookingStatus);
  if (terminal) return "unpaid_completed_stale_unactionable";
  if (!_tripKpiHasVisiblePaymentArtifact(trip, bookingMap)) {
    return "unpaid_completed_missing_visible_payment_artifact";
  }
  return "unpaid_completed_actionable";
}

async function _classifyTripKpiPendingMarker(env, scope, marker) {
  const bookingId = safeStr(marker?.booking_id, 160);
  const markerTripId = safeStr(marker?.trip_id, 160);
  const tripId = markerTripId || (bookingId ? `planned_${bookingId}` : "");
  const paid = normalizeCompliancePaymentStatus(marker?.payment_status) === "paid";
  const completed = marker?.completed === true;
  const amountCents = Number.isFinite(Number(marker?.payment_amount_cents))
    ? Math.max(0, Math.round(Number(marker.payment_amount_cents)))
    : 0;
  const statusToken = _tripKpiNormalizeToken(
    marker?.status ?? marker?.lifecycle_status ?? marker?.booking_status,
  );
  const terminal =
    marker?.terminal === true ||
    TRIP_KPI_TERMINAL_BOOKING_STATUS_SET.has(statusToken);
  let trip = null;
  let bookingMap = null;
  if (tripId) {
    try {
      const resolved = await getScopedOrLegacyTripForScope(env, scope, tripId);
      trip = resolved?.trip || null;
    } catch (_) {
      trip = null;
    }
  }
  if (bookingId) {
    try {
      const resolved = await getScopedOrLegacyBookingMapForScope(env, scope, bookingId);
      bookingMap = resolved?.map || null;
    } catch (_) {
      bookingMap = null;
    }
  }
  const hasTrip = !!(trip && recordMatchesTenantCompanyScope(trip, scope));
  const hasBookingMap = !!(bookingMap && recordMatchesTenantCompanyScope(bookingMap, scope));
  if (hasTrip) {
    return {
      classification: "pending_marker_resolvable_to_trip",
      active: true,
      clearable: false,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed,
    };
  }
  if (terminal) {
    return {
      classification: "pending_marker_terminal_or_cancelled",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed,
    };
  }
  if (!bookingId) {
    return {
      classification: "pending_marker_tracking_only_orphan",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed,
    };
  }
  if (!hasBookingMap && !hasTrip) {
    return {
      classification: "pending_marker_missing_booking",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed,
    };
  }
  if (paid && amountCents <= 0) {
    return {
      classification: "pending_marker_zero_amount_stale",
      active: false,
      clearable: true,
      bookingId,
      tripId,
      hasTrip,
      hasBookingMap,
      amountCents,
      paid,
      completed,
    };
  }
  return {
    classification: "pending_marker_waiting_for_trip",
    active: true,
    clearable: false,
    bookingId,
    tripId,
    hasTrip,
    hasBookingMap,
    amountCents,
    paid,
    completed,
  };
}

async function _collectTripKpiDebugDetails(env, scope, month, limit = 50) {
  const safeLimit = Math.max(1, Math.min(200, Number(limit) || 50));
  const out = {
    unpaid_completed_trip_contributors: [],
    pending_booking_markers: [],
    missing_amount_contributors: [],
    scope_mismatch_summary: { count: 0 },
  };
  const normalizedScope = normalizeScopedKeyScope(scope);
  const debugCounters = (await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardTripDebugKey(normalizedScope),
  )) ?? {};
  out.scope_mismatch_summary.count = Number.isFinite(Number(debugCounters.scope_mismatch))
    ? Math.max(0, Math.round(Number(debugCounters.scope_mismatch)))
    : 0;

  const contribPrefix = `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_contrib:`;
  let contribCursor = undefined;
  do {
    const page = await env.FLUXIDI_TRACKING.list({ prefix: contribPrefix, limit: 1000, cursor: contribCursor });
    for (const keyMeta of page?.keys || []) {
      const key = safeStr(keyMeta?.name, 260);
      if (!key) continue;
      const contrib = _readDashboardContribShape(
        await kvGetJson(env.FLUXIDI_TRACKING, key),
        null,
      );
      if (!contrib?.trip_id) continue;
      const trip = await kvGetJson(env.FLUXIDI_TRACKING, scopedTripKey(normalizedScope, contrib.trip_id));
      const tripStatus = normalizeDashboardTripLifecycleStatus(trip?.status ?? trip?.lifecycle_status);
      const paymentStatus = normalizeCompliancePaymentStatus(trip?.payment_status ?? trip?.paymentStatus);
      const bookingId = safeStr(trip?.booking_id ?? trip?.bookingId, 160);
      const bookingMapResolved = bookingId
        ? await getScopedOrLegacyBookingMapForScope(env, normalizedScope, bookingId)
        : null;
      const bookingMap = bookingMapResolved?.map || null;
      const unpaidClassification = _tripKpiClassifyUnpaidCompleted(trip, bookingMap);

      if (
        contrib.completed_rides_count > 0 &&
        contrib.unpaid_completed_rides_count > 0 &&
        out.unpaid_completed_trip_contributors.length < safeLimit
      ) {
        out.unpaid_completed_trip_contributors.push({
          reason: unpaidClassification,
          source_key_type: "trip_kpi_contrib",
          contrib_key_preview: _tripKpiMask(key),
          trip_id_preview: _tripKpiMask(contrib.trip_id),
          booking_id_preview: _tripKpiMask(bookingId),
          status: tripStatus || "unknown",
          payment_status: paymentStatus || "unknown",
          amount_cents: _tripKpiVisibleAmountCentsFromTrip(trip),
          contribution_shape: {
            completed_rides_count: contrib.completed_rides_count,
            unpaid_completed_rides_count: contrib.unpaid_completed_rides_count,
            monthly_paid_rides_count: contrib.monthly_paid_rides_count,
            monthly_income_cents: contrib.monthly_income_cents,
            paid_month: contrib.paid_month,
          },
        });
      }

      const missingAmountHit =
        (contrib.monthly_missing_amount_count || 0) > 0 ||
        (contrib.monthly_paid_rides_count > 0 && contrib.monthly_income_cents <= 0);
      if (
        missingAmountHit &&
        (!month || !contrib.paid_month || contrib.paid_month === month) &&
        out.missing_amount_contributors.length < safeLimit
      ) {
        out.missing_amount_contributors.push({
          reason: "missing_amount",
          source_key_type: "trip_kpi_contrib",
          contrib_key_preview: _tripKpiMask(key),
          trip_id_preview: _tripKpiMask(contrib.trip_id),
          booking_id_preview: _tripKpiMask(trip?.booking_id ?? trip?.bookingId),
          status: tripStatus || "unknown",
          payment_status: paymentStatus || "unknown",
          amount_cents: _tripKpiVisibleAmountCentsFromTrip(trip),
          month: contrib.paid_month || null,
          contribution_shape: {
            monthly_paid_rides_count: contrib.monthly_paid_rides_count,
            monthly_income_cents: contrib.monthly_income_cents,
            monthly_missing_amount_count: contrib.monthly_missing_amount_count,
          },
        });
      }
    }
    contribCursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (contribCursor);

  const pendingPrefix = scopedDashboardTripPendingBookingPrefix(normalizedScope);
  let pendingCursor = undefined;
  do {
    const page = await env.FLUXIDI_TRACKING.list({ prefix: pendingPrefix, limit: 1000, cursor: pendingCursor });
    for (const keyMeta of page?.keys || []) {
      if (out.pending_booking_markers.length >= safeLimit) break;
      const key = safeStr(keyMeta?.name, 260);
      if (!key) continue;
      const marker = await kvGetJson(env.FLUXIDI_TRACKING, key);
      if (!marker || typeof marker !== "object" || Array.isArray(marker)) continue;
      const markerClass = await _classifyTripKpiPendingMarker(env, normalizedScope, marker);
      const paid = markerClass?.paid === true;
      const completed = markerClass?.completed === true;
      const reason = markerClass?.classification || "pending_marker_waiting_for_trip";
      out.pending_booking_markers.push({
        reason,
        source_key_type: "pending_booking_marker",
        marker_key_preview: _tripKpiMask(key),
        booking_id_preview: _tripKpiMask(markerClass?.bookingId ?? marker?.booking_id),
        trip_id_preview: _tripKpiMask(markerClass?.tripId ?? marker?.trip_id),
        active: markerClass?.active === true,
        clearable: markerClass?.clearable === true,
        status: safeStr(marker?.status, 40) || null,
        payment_status: normalizeCompliancePaymentStatus(marker?.payment_status) || null,
        amount_cents: Number.isFinite(Number(marker?.payment_amount_cents))
          ? Math.max(0, Math.round(Number(marker.payment_amount_cents)))
          : null,
        month: _dashboardTripMonthFromIso(marker?.paid_at ?? null),
        contribution_shape: {
          completed: completed === true,
          terminal: marker?.terminal === true,
          marker_reason: safeStr(marker?.reason, 64) || null,
        },
      });
    }
    pendingCursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (pendingCursor);

  return out;
}

async function _reconcileTripKpiMissingAmountForMonthBestEffort(
  env,
  scope,
  month,
  { includeDebugRows = false, debugRowLimit = 50 } = {},
) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const safeMonth = _normalizeDashboardMonth(month);
  if (!safeMonth) {
    return {
      trip_kpi_reconcile_scanned: 0,
      trip_kpi_reconcile_recovered_missing_amount_count: 0,
      trip_kpi_reconcile_recovered_missing_amount_cents: 0,
      trip_kpi_reconcile_sum_cents: 0,
      rows: [],
    };
  }
  const contribPrefix = `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_contrib:`;
  const safeLimit = Math.max(1, Math.min(100, Number(debugRowLimit) || 50));
  const rows = [];
  let scanned = 0;
  let recoveredCount = 0;
  let recoveredCents = 0;

  let cursor = undefined;
  do {
    const page = await env.FLUXIDI_TRACKING.list({
      prefix: contribPrefix,
      limit: 1000,
      cursor,
    });
    for (const keyMeta of page?.keys || []) {
      const contribKey = safeStr(keyMeta?.name, 280);
      if (!contribKey) continue;
      const contribRaw = await kvGetJson(env.FLUXIDI_TRACKING, contribKey);
      const contrib = _readDashboardContribShape(contribRaw, null);
      if (!contrib?.trip_id) continue;
      if (!contrib.paid_month || contrib.paid_month !== safeMonth) continue;
      scanned += 1;

      const missingAmount =
        (contrib.monthly_missing_amount_count || 0) > 0 ||
        (contrib.monthly_paid_rides_count > 0 && contrib.monthly_income_cents <= 0);
      if (!missingAmount) continue;

      const previousIncomeCents = Number.isFinite(Number(contrib.monthly_income_cents))
        ? Math.max(0, Math.round(Number(contrib.monthly_income_cents)))
        : 0;
      const tripResolved = await getScopedOrLegacyTripForScope(
        env,
        normalizedScope,
        contrib.trip_id,
      );
      const trip = tripResolved?.trip || null;
      const hasTripRecord = !!trip && typeof trip === "object";
      const tripStatus = normalizeDashboardTripLifecycleStatus(
        trip?.status ?? trip?.lifecycle_status,
      );
      const paymentStatus = normalizeCompliancePaymentStatus(
        trip?.payment_status ?? trip?.paymentStatus,
      );
      const bookingPreview = _tripKpiMask(
        safeStr(
          trip?.booking_id ??
            trip?.bookingId ??
            trip?.public_booking_reference ??
            trip?.publicBookingReference,
          160,
        ),
      );
      const canonicalBookingPreview = _tripKpiMask(
        safeStr(
          trip?.public_booking_reference ??
            trip?.publicBookingReference ??
            trip?.booking?.booking_id ??
            trip?.booking?.bookingId,
          160,
        ),
      );
      const derivedAmountFromTripCents = _tripKpiVisibleAmountCentsFromTrip(trip) ?? 0;
      const derivedAmountFromContribCents = Number.isFinite(
        Number(
          contribRaw?.monthly_income_cents ??
            contribRaw?.income_cents ??
            contribRaw?.amount_cents ??
            contribRaw?.amountCents,
        ),
      )
        ? Math.max(
          0,
          Math.round(
            Number(
              contribRaw?.monthly_income_cents ??
                contribRaw?.income_cents ??
                contribRaw?.amount_cents ??
                contribRaw?.amountCents,
            ),
          ),
        )
        : 0;
      const recoveredAmountCents = Math.max(
        0,
        derivedAmountFromTripCents,
        derivedAmountFromContribCents,
      );
      const contribMissingMarker = (contrib.monthly_missing_amount_count || 0) > 0;
      const contribPaidRidesCount = Number.isFinite(Number(contrib.monthly_paid_rides_count))
        ? Math.max(0, Math.round(Number(contrib.monthly_paid_rides_count)))
        : 0;
      const eligibleCompleted =
        tripStatus === "completed" || (contrib.completed_rides_count || 0) > 0;
      // Missing-amount repair accepts contrib paid evidence when trip payment status is unknown.
      const eligiblePaid = paymentStatus === "paid" || contribPaidRidesCount > 0;
      const eligibleAmount = recoveredAmountCents > 0;
      const eligibleForRecover = eligibleCompleted && eligiblePaid && eligibleAmount;
      console.log(
        `[TRIP_KPI_RECONCILE][ELIGIBILITY] month=${safeMonth} trip=${_tripKpiMask(contrib.trip_id)} booking=${bookingPreview || "-"} has_trip_record=${hasTripRecord ? "true" : "false"} trip_status=${tripStatus || "unknown"} trip_payment_status=${paymentStatus || "unknown"} contrib_missing_marker=${contribMissingMarker ? "true" : "false"} contrib_paid_rides_count=${contribPaidRidesCount} eligible_completed=${eligibleCompleted ? "true" : "false"} eligible_paid=${eligiblePaid ? "true" : "false"} eligible_amount=${eligibleAmount ? "true" : "false"} derived_amount_from_trip_cents=${derivedAmountFromTripCents} derived_amount_from_contrib_cents=${derivedAmountFromContribCents}`,
      );
      let recovered = false;
      let recoveryReason = "not_eligible";
      if (eligibleForRecover) {
        const corrected = {
          ...(contribRaw && typeof contribRaw === "object" && !Array.isArray(contribRaw)
            ? contribRaw
            : {}),
          trip_id: contrib.trip_id,
          paid_month: safeMonth,
          monthly_paid_rides_count:
            Number.isFinite(Number(contrib.monthly_paid_rides_count)) &&
              Number(contrib.monthly_paid_rides_count) > 0
              ? Math.max(1, Math.round(Number(contrib.monthly_paid_rides_count)))
              : 1,
          monthly_income_cents: recoveredAmountCents,
          monthly_missing_amount_count: 0,
          updated_at: nowIso(),
          source: "trip_kpi_missing_amount_reconcile",
        };
        await kvPutJson(env.FLUXIDI_TRACKING, contribKey, corrected);
        recovered = true;
        recoveryReason = "completed_paid_visible_amount";
        recoveredCount += 1;
        recoveredCents += recoveredAmountCents;
        console.log(
          `[TRIP_KPI_RECONCILE][MISSING_AMOUNT_RECOVER] month=${safeMonth} trip=${_tripKpiMask(contrib.trip_id)} booking=${bookingPreview || "-"} previous_income_cents=${previousIncomeCents} recovered_amount_cents=${recoveredAmountCents} contrib_key=${_tripKpiMask(contribKey)}`,
        );
      }
      if (!recovered) {
        console.log(
          `[TRIP_KPI_RECONCILE][RECOVER_SKIP] month=${safeMonth} trip=${_tripKpiMask(contrib.trip_id)} booking=${bookingPreview || "-"} reason=${recoveryReason} has_trip_record=${hasTripRecord ? "true" : "false"} trip_status=${tripStatus || "unknown"} trip_payment_status=${paymentStatus || "unknown"} contrib_missing_marker=${contribMissingMarker ? "true" : "false"} contrib_paid_rides_count=${contribPaidRidesCount} eligible_completed=${eligibleCompleted ? "true" : "false"} eligible_paid=${eligiblePaid ? "true" : "false"} eligible_amount=${eligibleAmount ? "true" : "false"} derived_amount_from_trip_cents=${derivedAmountFromTripCents} derived_amount_from_contrib_cents=${derivedAmountFromContribCents}`,
        );
        console.log(
          `[TRIP_KPI_RECONCILE][MISSING_AMOUNT_RECOVER] month=${safeMonth} trip=${_tripKpiMask(contrib.trip_id)} booking=${bookingPreview || "-"} previous_income_cents=${previousIncomeCents} recovered_amount_cents=0 reason=${recoveryReason} status=${tripStatus || "unknown"} payment_status=${paymentStatus || "unknown"}`,
        );
      }
      if (includeDebugRows && rows.length < safeLimit) {
        rows.push({
          trip_preview: _tripKpiMask(contrib.trip_id),
          booking_preview: bookingPreview || null,
          canonical_booking_preview: canonicalBookingPreview || null,
          month: safeMonth,
          previous_income_cents: previousIncomeCents,
          recovered_amount_cents: recovered ? recoveredAmountCents : 0,
          recovered,
          included: recovered,
          recovery_reason: recoveryReason,
          recovery_source: recovered ? "trip_visible_amount" : null,
          eligible_completed: eligibleCompleted,
          eligible_paid: eligiblePaid,
          eligible_amount: eligibleAmount,
          has_trip_record: hasTripRecord,
          trip_payment_status: paymentStatus || "unknown",
          trip_status: tripStatus || "unknown",
          contrib_missing_marker: contribMissingMarker,
          contrib_paid_rides_count: contribPaidRidesCount,
          derived_amount_from_trip_cents: derivedAmountFromTripCents,
          derived_amount_from_contrib_cents: derivedAmountFromContribCents,
        });
      }
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (cursor);

  // Recompute month aggregate from contrib truth for idempotency.
  let sumCents = 0;
  let sumCount = 0;
  let sumMissingAmount = 0;
  cursor = undefined;
  do {
    const page = await env.FLUXIDI_TRACKING.list({
      prefix: contribPrefix,
      limit: 1000,
      cursor,
    });
    for (const keyMeta of page?.keys || []) {
      const contribKey = safeStr(keyMeta?.name, 280);
      if (!contribKey) continue;
      const contrib = _readDashboardContribShape(
        await kvGetJson(env.FLUXIDI_TRACKING, contribKey),
        null,
      );
      if (!contrib?.trip_id) continue;
      if (!contrib.paid_month || contrib.paid_month !== safeMonth) continue;
      if (contrib.monthly_paid_rides_count > 0) {
        sumCount += contrib.monthly_paid_rides_count;
        sumCents += Math.max(0, Math.round(Number(contrib.monthly_income_cents || 0)));
        sumMissingAmount += Math.max(
          0,
          Math.round(Number(contrib.monthly_missing_amount_count || 0)),
        );
      }
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (cursor);

  const monthKey = scopedDashboardTripMonthKpisKey(normalizedScope, safeMonth);
  await kvPutJson(env.FLUXIDI_TRACKING, monthKey, {
    month: safeMonth,
    currency: "EUR",
    monthly_paid_rides_count: Math.max(0, sumCount),
    monthly_income_cents: Math.max(0, sumCents),
    monthly_missing_amount_count: Math.max(0, sumMissingAmount),
    updated_at: nowIso(),
    source: "trip_kpi_missing_amount_reconcile",
  });
  console.log(
    `[TRIP_KPI_RECONCILE][AGG_WRITE] month=${safeMonth} key=${_tripKpiMask(monthKey)} monthly_paid_rides_count=${Math.max(0, sumCount)} monthly_income_cents=${Math.max(0, sumCents)} monthly_missing_amount_count=${Math.max(0, sumMissingAmount)}`,
  );
  console.log(
    `[TRIP_KPI_RECONCILE][RESULT] month=${safeMonth} scanned=${scanned} recovered_count=${recoveredCount} recovered_cents=${Math.max(0, recoveredCents)} sum_cents=${Math.max(0, sumCents)}`,
  );
  return {
    trip_kpi_reconcile_scanned: scanned,
    trip_kpi_reconcile_recovered_missing_amount_count: recoveredCount,
    trip_kpi_reconcile_recovered_missing_amount_cents: Math.max(0, recoveredCents),
    trip_kpi_reconcile_sum_cents: Math.max(0, sumCents),
    rows,
  };
}

async function _collectActionableUnpaidCompletedStats(env, scope) {
  const out = {
    actionable_count: 0,
    tracking_only: 0,
    stale_unactionable: 0,
    missing_visible_payment_artifact: 0,
    total_scanned_unpaid_completed: 0,
  };
  const normalizedScope = normalizeScopedKeyScope(scope);
  const contribPrefix = `tenant:${normalizedScope.tenant_id}:company:${normalizedScope.company_id}:dashboard:trip_kpi_contrib:`;
  let cursor = undefined;
  const maxScan = 5000;
  do {
    const page = await env.FLUXIDI_TRACKING.list({ prefix: contribPrefix, limit: 1000, cursor });
    for (const keyMeta of page?.keys || []) {
      if (out.total_scanned_unpaid_completed >= maxScan) break;
      const key = safeStr(keyMeta?.name, 280);
      if (!key) continue;
      const contrib = _readDashboardContribShape(
        await kvGetJson(env.FLUXIDI_TRACKING, key),
        null,
      );
      if (!contrib?.trip_id) continue;
      if (!(contrib.completed_rides_count === 1 && contrib.unpaid_completed_rides_count === 1)) {
        continue;
      }
      out.total_scanned_unpaid_completed += 1;
      const tripResolved = await getScopedOrLegacyTripForScope(env, normalizedScope, contrib.trip_id);
      const trip = tripResolved?.trip || null;
      const bookingId = safeStr(trip?.booking_id ?? trip?.bookingId, 160);
      const bookingMapResolved = bookingId
        ? await getScopedOrLegacyBookingMapForScope(env, normalizedScope, bookingId)
        : null;
      const bookingMap = bookingMapResolved?.map || null;
      const classification = _tripKpiClassifyUnpaidCompleted(trip, bookingMap);
      if (classification === "unpaid_completed_actionable") out.actionable_count += 1;
      else if (classification === "unpaid_completed_tracking_only") out.tracking_only += 1;
      else if (classification === "unpaid_completed_stale_unactionable") out.stale_unactionable += 1;
      else if (classification === "unpaid_completed_missing_visible_payment_artifact") {
        out.missing_visible_payment_artifact += 1;
      }
    }
    if (out.total_scanned_unpaid_completed >= maxScan) break;
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (cursor);
  return out;
}

function _coerceReconcileDryRun(value, fallback = true) {
  if (value == null) return fallback;
  const token = (safeStr(value, 16) ?? "").toLowerCase();
  if (!token) return fallback;
  if (token === "0" || token === "false" || token === "no") return false;
  if (token === "1" || token === "true" || token === "yes") return true;
  return fallback;
}

function _tripKpiAmountCentsFromTrip(trip) {
  return (
    _dashboardTripAmountCents(trip?.payment_amount) ??
    _dashboardTripAmountCents(trip?.paymentAmount) ??
    _dashboardTripAmountCents(trip?.final_amount) ??
    _dashboardTripAmountCents(trip?.finalAmount) ??
    _dashboardTripAmountCents(trip?.final_total) ??
    _dashboardTripAmountCents(trip?.finalTotal) ??
    _dashboardTripAmountCents(trip?.total_eur) ??
    _dashboardTripAmountCents(trip?.totalEur) ??
    0
  );
}

async function handleDashboardTripKpisReconcile(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = req.method === "POST" ? await readJson(req) : {};
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, {
    returnResponse: true,
    origin,
  });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = normalizeScopedKeyScope(requiredScope);
  const dryRun =
    _coerceReconcileDryRun(url.searchParams.get("dry_run"), true) &&
    _coerceReconcileDryRun(body?.dry_run, true);
  const limitRaw = safeStr(url.searchParams.get("limit"), 16) || safeStr(body?.limit, 16);
  const limit = Math.max(1, Math.min(500, Number(limitRaw) || 100));

  const pendingPrefix = scopedDashboardTripPendingBookingPrefix(scope);
  const actions = [];
  const summary = {
    scanned_markers: 0,
    resolved_to_trip_materialized: 0,
    cleared_terminal_marker: 0,
    unresolved_pending: 0,
    scanned_unpaid_completed_contribs: 0,
    unpaid_completed_still_unpaid: 0,
    unpaid_completed_resolvable_to_paid: 0,
    unpaid_completed_missing_booking: 0,
    unpaid_completed_missing_trip: 0,
    unpaid_completed_terminal_or_cancelled: 0,
    unpaid_completed_missing_amount: 0,
  };
  const expected_deltas = {
    completed_rides_count: 0,
    unpaid_completed_rides_count: 0,
    monthly_paid_rides_count: 0,
    monthly_income_cents: 0,
  };

  let cursor = undefined;
  do {
    const page = await env.FLUXIDI_TRACKING.list({ prefix: pendingPrefix, limit: 1000, cursor });
    for (const keyMeta of page?.keys || []) {
      if (summary.scanned_markers >= limit) break;
      summary.scanned_markers += 1;
      const markerKey = safeStr(keyMeta?.name, 260);
      if (!markerKey) continue;
      const marker = await kvGetJson(env.FLUXIDI_TRACKING, markerKey);
      if (!marker || typeof marker !== "object" || Array.isArray(marker)) continue;

      const markerClass = await _classifyTripKpiPendingMarker(env, scope, marker);
      const bookingId = markerClass?.bookingId || safeStr(marker?.booking_id, 160);
      const tripId = markerClass?.tripId || safeStr(marker?.trip_id, 160) || (bookingId ? `planned_${bookingId}` : "");
      const tripStorageKey = tripId ? scopedTripKey(scope, tripId) : "";
      const trip = tripStorageKey ? await kvGetJson(env.FLUXIDI_TRACKING, tripStorageKey) : null;
      const markerPaid = markerClass?.paid === true;

      if (trip && recordMatchesTenantCompanyScope(trip, scope)) {
        const projectedTrip = { ...trip };
        if (markerPaid) {
          projectedTrip.payment_status = "paid";
          projectedTrip.paymentStatus = "paid";
          const paidAt = safeStr(marker?.paid_at, 64);
          if (paidAt) {
            projectedTrip.paid_at = paidAt;
            projectedTrip.paidAt = paidAt;
          }
          const cents = Number(marker?.payment_amount_cents);
          if (Number.isFinite(cents)) {
            const amount = Math.round(cents) / 100;
            projectedTrip.payment_amount = amount;
            projectedTrip.paymentAmount = amount;
          }
        }

        const contribKey = scopedDashboardTripContribKey(scope, tripId);
        const prev = _readDashboardContribShape(await kvGetJson(env.FLUXIDI_TRACKING, contribKey), tripId);
        const next = _readDashboardContribShape(deriveDashboardTripKpiContribution(projectedTrip), tripId);
        expected_deltas.completed_rides_count += next.completed_rides_count - prev.completed_rides_count;
        expected_deltas.unpaid_completed_rides_count += next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count;
        expected_deltas.monthly_paid_rides_count += next.monthly_paid_rides_count - prev.monthly_paid_rides_count;
        expected_deltas.monthly_income_cents += next.monthly_income_cents - prev.monthly_income_cents;

        summary.resolved_to_trip_materialized += 1;
        actions.push({
          action: "resolved_to_trip_materialized",
          dry_run: dryRun,
          marker_key_preview: _tripKpiMask(markerKey),
          booking_id_preview: _tripKpiMask(bookingId),
          trip_id_preview: _tripKpiMask(tripId),
          marker_classification: markerClass?.classification || "pending_marker_resolvable_to_trip",
          marker_clearable: markerClass?.clearable === true,
          expected_delta: {
            completed_rides_count: next.completed_rides_count - prev.completed_rides_count,
            unpaid_completed_rides_count: next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count,
            monthly_paid_rides_count: next.monthly_paid_rides_count - prev.monthly_paid_rides_count,
            monthly_income_cents: next.monthly_income_cents - prev.monthly_income_cents,
          },
        });

        if (!dryRun) {
          await kvPutJson(env.FLUXIDI_TRACKING, tripStorageKey, projectedTrip, TTL_TRIP);
          await materializeTripDashboardKpisBestEffort(
            env,
            scope,
            projectedTrip,
            "trip_kpi_reconcile_pending_marker",
          );
          await kvDel(env.FLUXIDI_TRACKING, markerKey);
        }
        continue;
      }

      if (markerClass?.clearable === true) {
        summary.cleared_terminal_marker += 1;
        actions.push({
          action: markerClass?.classification || "pending_marker_terminal_or_cancelled",
          dry_run: dryRun,
          marker_key_preview: _tripKpiMask(markerKey),
          booking_id_preview: _tripKpiMask(bookingId),
          trip_id_preview: _tripKpiMask(tripId),
          marker_classification: markerClass?.classification || null,
          marker_clearable: true,
          reason: markerClass?.classification || "pending_marker_terminal_or_cancelled",
        });
        if (!dryRun) {
          await kvDel(env.FLUXIDI_TRACKING, markerKey);
        }
        continue;
      }

      summary.unresolved_pending += 1;
      actions.push({
        action: markerClass?.classification || "unresolved_pending",
        dry_run: dryRun,
        marker_key_preview: _tripKpiMask(markerKey),
        booking_id_preview: _tripKpiMask(bookingId),
        trip_id_preview: _tripKpiMask(tripId),
        marker_classification: markerClass?.classification || null,
        marker_clearable: markerClass?.clearable === true,
        reason: markerPaid ? "pending_paid_booking_no_trip" : "trip_missing",
      });
    }
    if (summary.scanned_markers >= limit) break;
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (cursor);

  const contribPrefix = `tenant:${scope.tenant_id}:company:${scope.company_id}:dashboard:trip_kpi_contrib:`;
  let contribCursor = undefined;
  do {
    const page = await env.FLUXIDI_TRACKING.list({ prefix: contribPrefix, limit: 1000, cursor: contribCursor });
    for (const keyMeta of page?.keys || []) {
      if (summary.scanned_unpaid_completed_contribs >= limit) break;
      const contribKeyRaw = safeStr(keyMeta?.name, 280);
      if (!contribKeyRaw) continue;
      const contrib = _readDashboardContribShape(
        await kvGetJson(env.FLUXIDI_TRACKING, contribKeyRaw),
        null,
      );
      if (!contrib?.trip_id) continue;
      if (
        !(contrib.completed_rides_count === 1 &&
          contrib.unpaid_completed_rides_count === 1 &&
          contrib.monthly_paid_rides_count === 0 &&
          contrib.monthly_income_cents === 0)
      ) {
        continue;
      }
      summary.scanned_unpaid_completed_contribs += 1;
      const tripId = safeStr(contrib.trip_id, 160);
      let tripResolved = null;
      let trip = null;
      try {
        tripResolved = await getScopedOrLegacyTripForScope(env, scope, tripId);
        trip = tripResolved?.trip || null;
      } catch (_) {
        trip = null;
      }
      if (!trip || !recordMatchesTenantCompanyScope(trip, scope)) {
        summary.unpaid_completed_missing_trip += 1;
        actions.push({
          action: "unpaid_completed_missing_trip",
          dry_run: dryRun,
          source_key_type: "trip_kpi_contrib",
          contrib_key_preview: _tripKpiMask(contribKeyRaw),
          trip_id_preview: _tripKpiMask(tripId),
          booking_id_preview: null,
          status: "missing",
          payment_status: "unknown",
          amount_cents: null,
          contribution_shape: {
            completed_rides_count: contrib.completed_rides_count,
            unpaid_completed_rides_count: contrib.unpaid_completed_rides_count,
            monthly_paid_rides_count: contrib.monthly_paid_rides_count,
            monthly_income_cents: contrib.monthly_income_cents,
            paid_month: contrib.paid_month,
          },
        });
        continue;
      }

      const tripStatus = normalizeDashboardTripLifecycleStatus(trip?.status ?? trip?.lifecycle_status);
      const tripPaymentStatus = normalizeCompliancePaymentStatus(trip?.payment_status ?? trip?.paymentStatus);
      const bookingId = safeStr(trip?.booking_id ?? trip?.bookingId, 160);
      const amountCents = _tripKpiAmountCentsFromTrip(trip);
      const markerKey = bookingId ? scopedDashboardTripPendingBookingKey(scope, bookingId) : "";
      const marker = markerKey ? await kvGetJson(env.FLUXIDI_TRACKING, markerKey) : null;
      const markerPaid = normalizeCompliancePaymentStatus(marker?.payment_status) === "paid";
      const markerPaidAt = safeStr(marker?.paid_at, 64);
      const bookingMap = bookingId ? (await getScopedOrLegacyBookingMapForScope(env, scope, bookingId))?.map : null;
      const bookingMapPaid = normalizeCompliancePaymentStatus(
        bookingMap?.payment_status ?? bookingMap?.paymentStatus,
      ) === "paid";
      const paidProof = tripPaymentStatus === "paid" || markerPaid || bookingMapPaid;
      const classification = _tripKpiClassifyUnpaidCompleted(trip, bookingMap);

      const actionBase = {
        dry_run: dryRun,
        source_key_type: "trip_kpi_contrib",
        contrib_key_preview: _tripKpiMask(contribKeyRaw),
        trip_id_preview: _tripKpiMask(tripId),
        booking_id_preview: _tripKpiMask(bookingId),
        status: tripStatus || "unknown",
        payment_status: tripPaymentStatus || "unknown",
        amount_cents: amountCents > 0 ? amountCents : null,
        month: contrib.paid_month || null,
        contribution_shape: {
          completed_rides_count: contrib.completed_rides_count,
          unpaid_completed_rides_count: contrib.unpaid_completed_rides_count,
          monthly_paid_rides_count: contrib.monthly_paid_rides_count,
          monthly_income_cents: contrib.monthly_income_cents,
          paid_month: contrib.paid_month,
        },
      };

      if (classification === "unpaid_completed_stale_unactionable") {
        summary.unpaid_completed_terminal_or_cancelled += 1;
        actions.push({
          action: "unpaid_completed_stale_unactionable",
          ...actionBase,
        });
        continue;
      }

      if (classification === "unpaid_completed_tracking_only") {
        summary.unpaid_completed_missing_booking += 1;
        actions.push({
          action: "unpaid_completed_tracking_only",
          ...actionBase,
        });
        continue;
      }

      if (classification === "unpaid_completed_missing_visible_payment_artifact") {
        summary.unpaid_completed_missing_amount += 1;
        actions.push({
          action: "unpaid_completed_missing_visible_payment_artifact",
          ...actionBase,
        });
        continue;
      }

      if (!paidProof) {
        summary.unpaid_completed_still_unpaid += 1;
        actions.push({
          action: "unpaid_completed_actionable",
          ...actionBase,
        });
        continue;
      }

      if (!(amountCents > 0)) {
        summary.unpaid_completed_missing_amount += 1;
        actions.push({
          action: "unpaid_completed_missing_amount",
          ...actionBase,
        });
        continue;
      }

      const projectedTrip = { ...trip };
      projectedTrip.payment_status = "paid";
      projectedTrip.paymentStatus = "paid";
      if (markerPaidAt && !safeStr(projectedTrip?.paid_at ?? projectedTrip?.paidAt, 64)) {
        projectedTrip.paid_at = markerPaidAt;
        projectedTrip.paidAt = markerPaidAt;
      }
      if (!Number.isFinite(Number(projectedTrip?.payment_amount)) && !Number.isFinite(Number(projectedTrip?.paymentAmount))) {
        const amount = Math.round(amountCents) / 100;
        projectedTrip.payment_amount = amount;
        projectedTrip.paymentAmount = amount;
      }

      const prev = _readDashboardContribShape(await kvGetJson(env.FLUXIDI_TRACKING, contribKeyRaw), tripId);
      const next = _readDashboardContribShape(deriveDashboardTripKpiContribution(projectedTrip), tripId);
      const deltaCompleted = next.completed_rides_count - prev.completed_rides_count;
      const deltaUnpaid = next.unpaid_completed_rides_count - prev.unpaid_completed_rides_count;
      const deltaMonthPaid = next.monthly_paid_rides_count - prev.monthly_paid_rides_count;
      const deltaIncome = next.monthly_income_cents - prev.monthly_income_cents;
      expected_deltas.completed_rides_count += deltaCompleted;
      expected_deltas.unpaid_completed_rides_count += deltaUnpaid;
      expected_deltas.monthly_paid_rides_count += deltaMonthPaid;
      expected_deltas.monthly_income_cents += deltaIncome;

      summary.unpaid_completed_resolvable_to_paid += 1;
      actions.push({
        action: "unpaid_completed_resolvable_to_paid",
        ...actionBase,
        expected_delta: {
          completed_rides_count: deltaCompleted,
          unpaid_completed_rides_count: deltaUnpaid,
          monthly_paid_rides_count: deltaMonthPaid,
          monthly_income_cents: deltaIncome,
        },
      });

      if (!dryRun) {
        const tripStorageKey =
          safeStr(tripResolved?.key, 260) || scopedTripKey(scope, tripId);
        await kvPutJson(env.FLUXIDI_TRACKING, tripStorageKey, projectedTrip, TTL_TRIP);
        await materializeTripDashboardKpisBestEffort(
          env,
          scope,
          projectedTrip,
          "trip_kpi_reconcile_unpaid_completed",
        );
        if (markerKey && marker) {
          await kvDel(env.FLUXIDI_TRACKING, markerKey);
        }
      }
    }
    if (summary.scanned_unpaid_completed_contribs >= limit) break;
    contribCursor = page?.cursor;
    if (page?.list_complete !== false) break;
  } while (contribCursor);

  return withCors(
    json(
      {
        ok: true,
        dry_run: dryRun,
        tenant_id: scope.tenant_id,
        company_id: scope.company_id,
        generated_at: nowIso(),
        summary,
        expected_deltas,
        actions,
      },
      { status: 200 },
    ),
    origin,
  );
}

async function handleDashboardTripKpis(req, url, env, origin) {
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, {
    returnResponse: true,
    origin,
  });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const auth = await requireAdminOrCompanySessionForScope(req, url, env, scope, origin);
  if (!auth.ok) return auth.response;
  const monthRaw = safeStr(url.searchParams.get("month"), 16);
  const defaultMonth = new Date().toISOString().slice(0, 7);
  const selectedMonth = monthRaw ? _normalizeDashboardMonth(monthRaw) : defaultMonth;
  const debugRaw = (safeStr(url.searchParams.get("debug"), 16) ?? "").toLowerCase();
  const debugEnabled = debugRaw === "1" || debugRaw === "true";
  const debugPaidContributorsRaw = (safeStr(url.searchParams.get("debug_paid_contributors"), 16) ?? "").toLowerCase();
  const debugPaidContributorsEnabled =
    debugPaidContributorsRaw === "1" || debugPaidContributorsRaw === "true";
  const debugLimit = Math.max(
    1,
    Math.min(200, Number(safeStr(url.searchParams.get("debug_limit"), 16) || "50") || 50),
  );
  if (!selectedMonth) {
    return withCors(
      json({ ok: false, error: "month must be YYYY-MM" }, { status: 400 }),
      origin,
    );
  }
  const normalizedScope = normalizeScopedKeyScope(scope);
  const reconcileResult = await _reconcileTripKpiMissingAmountForMonthBestEffort(
    env,
    normalizedScope,
    selectedMonth,
    {
      includeDebugRows: debugPaidContributorsEnabled,
      debugRowLimit: 50,
    },
  );
  const global = (await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardTripKpisKey(normalizedScope),
  )) ?? {};
  const month = (await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardTripMonthKpisKey(normalizedScope, selectedMonth),
  )) ?? {};
  const financeMonth = (await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardBookingFinanceMonthKey(normalizedScope, selectedMonth),
  )) ?? {};
  const debugCounters = (await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardTripDebugKey(normalizedScope),
  )) ?? {};
  const pendingDiagnostics = await _collectTripKpiPendingDiagnostics(env, normalizedScope);
  const unpaidActionableStats = await _collectActionableUnpaidCompletedStats(
    env,
    normalizedScope,
  );
  const completed = Number.isFinite(Number(global.completed_rides_count))
    ? Math.max(0, Math.round(Number(global.completed_rides_count)))
    : 0;
  const unpaidRaw = Number.isFinite(Number(global.unpaid_completed_rides_count))
    ? Math.max(0, Math.round(Number(global.unpaid_completed_rides_count)))
    : 0;
  const unpaid = Math.max(0, Math.round(Number(unpaidActionableStats.actionable_count) || 0));
  const monthPaid = Number.isFinite(Number(month.monthly_paid_rides_count))
    ? Math.max(0, Math.round(Number(month.monthly_paid_rides_count)))
    : 0;
  const monthIncomeCents = Number.isFinite(Number(month.monthly_income_cents))
    ? Math.max(0, Math.round(Number(month.monthly_income_cents)))
    : 0;
  const monthMissingAmount = Number.isFinite(Number(month.monthly_missing_amount_count))
    ? Math.max(0, Math.round(Number(month.monthly_missing_amount_count)))
    : 0;
  const monthBookingPaidCount = Number.isFinite(Number(financeMonth.monthly_paid_bookings_count))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_paid_bookings_count)))
    : 0;
  const monthBookingPaidIncomeCents = Number.isFinite(Number(financeMonth.monthly_paid_bookings_income_cents))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_paid_bookings_income_cents)))
    : 0;
  const blendedMonthlyIncomeCents = Math.max(monthIncomeCents, monthBookingPaidIncomeCents);
  const monthCancelledPaidCents = Number.isFinite(Number(financeMonth.monthly_cancelled_paid_bookings_cents))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_cancelled_paid_bookings_cents)))
    : 0;
  const monthPendingCreditCents = Number.isFinite(Number(financeMonth.monthly_pending_credit_cents))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_pending_credit_cents)))
    : 0;
  const monthCreditedCents = Number.isFinite(Number(financeMonth.monthly_credited_cents))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_credited_cents)))
    : 0;
  const grossMonthlyIncomeCents = blendedMonthlyIncomeCents;
  const pendingCreditCents = monthPendingCreditCents;
  const creditedCents = monthCreditedCents;
  const netMonthlyIncomeCents = Math.max(
    0,
    grossMonthlyIncomeCents - pendingCreditCents - creditedCents,
  );
  const scopeMismatchCount = Number.isFinite(Number(debugCounters.scope_mismatch))
    ? Math.max(0, Math.round(Number(debugCounters.scope_mismatch)))
    : 0;
  const missingAmountDebugCount = Number.isFinite(Number(debugCounters.missing_amount))
    ? Math.max(0, Math.round(Number(debugCounters.missing_amount)))
    : 0;
  const payload = {
    ok: true,
    tenant_id: normalizedScope.tenant_id,
    company_id: normalizedScope.company_id,
    month: selectedMonth,
    generated_at: nowIso(),
    currency: "EUR",
    completed_rides_count: completed,
    unpaid_completed_rides_count_raw: unpaidRaw,
    unpaid_completed_rides_count: unpaid,
    monthly_paid_rides_count: monthPaid,
    monthly_income_eur: blendedMonthlyIncomeCents / 100,
    monthly_income_cents: blendedMonthlyIncomeCents,
    gross_monthly_income_cents: grossMonthlyIncomeCents,
    gross_monthly_income_eur: grossMonthlyIncomeCents / 100,
    pending_credit_cents: pendingCreditCents,
    pending_credit_eur: pendingCreditCents / 100,
    monthly_credited_cents: creditedCents,
    monthly_credited_eur: creditedCents / 100,
    credited_cents: creditedCents,
    credited_eur: creditedCents / 100,
    net_monthly_income_cents: netMonthlyIncomeCents,
    net_monthly_income_eur: netMonthlyIncomeCents / 100,
    monthly_paid_bookings_count: monthBookingPaidCount,
    monthly_paid_bookings_income_cents: monthBookingPaidIncomeCents,
    monthly_paid_bookings_income_eur: monthBookingPaidIncomeCents / 100,
    trip_kpi_reconcile_scanned: Number.isFinite(Number(reconcileResult?.trip_kpi_reconcile_scanned))
      ? Math.max(0, Math.round(Number(reconcileResult.trip_kpi_reconcile_scanned)))
      : 0,
    trip_kpi_reconcile_recovered_missing_amount_count: Number.isFinite(
      Number(reconcileResult?.trip_kpi_reconcile_recovered_missing_amount_count),
    )
      ? Math.max(
        0,
        Math.round(Number(reconcileResult.trip_kpi_reconcile_recovered_missing_amount_count)),
      )
      : 0,
    trip_kpi_reconcile_recovered_missing_amount_cents: Number.isFinite(
      Number(reconcileResult?.trip_kpi_reconcile_recovered_missing_amount_cents),
    )
      ? Math.max(
        0,
        Math.round(Number(reconcileResult.trip_kpi_reconcile_recovered_missing_amount_cents)),
      )
      : 0,
    trip_kpi_reconcile_sum_cents: Number.isFinite(
      Number(reconcileResult?.trip_kpi_reconcile_sum_cents),
    )
      ? Math.max(0, Math.round(Number(reconcileResult.trip_kpi_reconcile_sum_cents)))
      : 0,
    monthly_cancelled_paid_bookings_cents: monthCancelledPaidCents,
    monthly_cancelled_paid_bookings_eur: monthCancelledPaidCents / 100,
    diagnostics: {
      trip_missing: pendingDiagnostics.trip_missing,
      trip_missing_active: pendingDiagnostics.trip_missing_active,
      paid_but_not_completed: pendingDiagnostics.paid_but_not_completed,
      paid_but_not_completed_active: pendingDiagnostics.paid_but_not_completed_active,
      completed_but_unpaid: unpaid,
      completed_but_unpaid_raw: unpaidRaw,
      unpaid_completed_actionable: unpaidActionableStats.actionable_count,
      unpaid_completed_stale_unactionable: unpaidActionableStats.stale_unactionable,
      unpaid_completed_tracking_only: unpaidActionableStats.tracking_only,
      unpaid_completed_missing_visible_payment_artifact:
        unpaidActionableStats.missing_visible_payment_artifact,
      completed_paid_contributed: monthPaid,
      scope_mismatch: scopeMismatchCount,
      scope_mismatch_historical: scopeMismatchCount,
      missing_amount: Math.max(monthMissingAmount, missingAmountDebugCount),
      missing_amount_historical: missingAmountDebugCount,
    },
    completeness: {
      level: "forward_aggregate",
      notes: [
        "Aggregates are maintained from KPI materialization time forward.",
        "Historical retained trips may require a rebuild/backfill endpoint.",
      ],
    },
  };
  if (debugEnabled) {
    payload.debug_enabled = true;
    payload.debug_limit = debugLimit;
    payload.debug_details = await _collectTripKpiDebugDetails(
      env,
      normalizedScope,
      selectedMonth,
      debugLimit,
    );
  }
  if (debugPaidContributorsEnabled) {
    payload.trip_paid_contributor_debug_rows = Array.isArray(reconcileResult?.rows)
      ? reconcileResult.rows
      : [];
    payload.trip_paid_contributor_debug_included = payload.trip_paid_contributor_debug_rows.filter(
      (row) => row?.included === true,
    ).length;
  }
  return withCors(
    json(payload, { status: 200 }),
    origin,
  );
}

async function _listAllKvKeysByPrefix(kv, prefix) {
  if (!kv || !prefix) return [];
  const out = [];
  let cursor = undefined;
  do {
    const page = await kv.list({ prefix, limit: 1000, cursor });
    for (const item of page?.keys || []) {
      const name = safeStr(item?.name, 320);
      if (name) out.push(name);
    }
    cursor = page?.cursor;
    if (page?.list_complete !== false) break;
    if (!cursor) break;
  } while (cursor);
  return out;
}

function _buildDashboardKpiResetCategories(scope, { includeTripHistory = false } = {}) {
  const categories = [
    {
      id: "trip_kpis_global",
      kind: "exact",
      keys: [scopedDashboardTripKpisKey(scope)],
    },
    {
      id: "trip_kpi_debug",
      kind: "exact",
      keys: [scopedDashboardTripDebugKey(scope)],
    },
    {
      id: "trip_kpis_month",
      kind: "prefix",
      prefix: scopedDashboardTripKpisMonthPrefix(scope),
    },
    {
      id: "trip_kpi_contrib",
      kind: "prefix",
      prefix: scopedDashboardTripKpiContribPrefix(scope),
    },
    {
      id: "trip_kpi_pending_booking",
      kind: "prefix",
      prefix: scopedDashboardTripPendingBookingPrefix(scope),
    },
    {
      id: "booking_finance_month",
      kind: "prefix",
      prefix: scopedDashboardBookingFinanceMonthPrefix(scope),
    },
    {
      id: "booking_finance_contrib",
      kind: "prefix",
      prefix: scopedDashboardBookingFinanceContribPrefix(scope),
    },
  ];
  if (includeTripHistory) {
    categories.push(
      {
        id: "trip_records",
        kind: "prefix",
        prefix: scopedTripRecordsPrefix(scope),
      },
      {
        id: "trips_index",
        kind: "exact",
        keys: [scopedTripsIndexKey(scope)],
      },
      {
        id: "trips_index_driver",
        kind: "prefix",
        prefix: `${scopedTripsIndexKey(scope)}:`,
      },
    );
  }
  return categories;
}

async function _collectExistingDashboardKpiResetCategoryKeys(env, category) {
  if (!env?.FLUXIDI_TRACKING) return [];
  if (category.kind === "exact") {
    const out = [];
    for (const key of category.keys || []) {
      if (!key) continue;
      try {
        const raw = await env.FLUXIDI_TRACKING.get(key);
        if (raw != null) out.push(key);
      } catch (_) {
        // skip unreadable keys
      }
    }
    return out;
  }
  if (category.kind === "prefix" && category.prefix) {
    return await _listAllKvKeysByPrefix(env.FLUXIDI_TRACKING, category.prefix);
  }
  return [];
}

async function _readCurrentDashboardKpiValues(env, scope, month) {
  const normalizedScope = normalizeScopedKeyScope(scope);
  const global =
    (await kvGetJson(env.FLUXIDI_TRACKING, scopedDashboardTripKpisKey(normalizedScope))) ?? {};
  const monthData = month
    ? ((await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedDashboardTripMonthKpisKey(normalizedScope, month),
    )) ?? {})
    : {};
  const financeMonth = month
    ? ((await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedDashboardBookingFinanceMonthKey(normalizedScope, month),
    )) ?? {})
    : {};
  const completed = Number.isFinite(Number(global.completed_rides_count))
    ? Math.max(0, Math.round(Number(global.completed_rides_count)))
    : 0;
  const unpaid = Number.isFinite(Number(global.unpaid_completed_rides_count))
    ? Math.max(0, Math.round(Number(global.unpaid_completed_rides_count)))
    : 0;
  const monthIncomeCents = Number.isFinite(Number(monthData.monthly_income_cents))
    ? Math.max(0, Math.round(Number(monthData.monthly_income_cents)))
    : 0;
  const bookingFinanceIncomeCents = Number.isFinite(
    Number(financeMonth.monthly_paid_bookings_income_cents),
  )
    ? Math.max(0, Math.round(Number(financeMonth.monthly_paid_bookings_income_cents)))
    : 0;
  return {
    completed_rides_count: completed,
    unpaid_completed_rides_count: unpaid,
    monthly_income_cents: Math.max(monthIncomeCents, bookingFinanceIncomeCents),
    monthly_paid_bookings_income_cents: bookingFinanceIncomeCents,
    trip_monthly_income_cents: monthIncomeCents,
  };
}

async function handleDevDashboardKpisReset(req, url, env, origin, { forceDryRun = false } = {}) {
  requireAdmin(req, url, env);
  if (!allowDevResetEndpoints(env)) {
    return withCors(
      json({ ok: false, error: "dev reset endpoints are disabled" }, { status: 403 }),
      origin,
    );
  }

  let body = {};
  if (req.method === "POST") {
    try {
      body = await readJson(req);
    } catch (_) {
      body = {};
    }
  }

  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, {
    returnResponse: true,
    origin,
  });
  if (requiredScope instanceof Response) return requiredScope;

  const tenantId = requiredScope.tenant_id;
  const companyId = requiredScope.company_id;
  if (_isUnsafeDevResetScope(tenantId, companyId)) {
    return withCors(
      json({ ok: false, error: "unsafe_legacy_scope_not_allowed" }, { status: 400 }),
      origin,
    );
  }

  const dryRun =
    forceDryRun ||
    (_coerceReconcileDryRun(url.searchParams.get("dry_run"), true) &&
      _coerceReconcileDryRun(body?.dry_run ?? body?.dryRun, true));

  if (!dryRun && !allowDevResetExecute(env)) {
    return withCors(json({ ok: false, error: "dev_reset_disabled" }, { status: 403 }), origin);
  }

  const includeTripHistory = _coerceBoolean(
    body?.include_trip_history ??
      body?.includeTripHistory ??
      url.searchParams.get("include_trip_history"),
    false,
  );

  const monthRaw = safeStr(url.searchParams.get("month") ?? body?.month, 16);
  const month = monthRaw ? _normalizeDashboardMonth(monthRaw) : new Date().toISOString().slice(0, 7);

  if (!env?.FLUXIDI_TRACKING) {
    return withCors(
      json({ ok: false, error: "FLUXIDI_TRACKING binding missing" }, { status: 500 }),
      origin,
    );
  }

  const normalizedScope = normalizeScopedKeyScope(requiredScope);
  const categoryDefs = _buildDashboardKpiResetCategories(normalizedScope, { includeTripHistory });

  const categories = [];
  const keysByCategory = {};
  let wouldDeleteTotal = 0;

  for (const def of categoryDefs) {
    const keys = await _collectExistingDashboardKpiResetCategoryKeys(env, def);
    keysByCategory[def.id] = keys;
    wouldDeleteTotal += keys.length;
    categories.push({
      id: def.id,
      kind: def.kind,
      count: keys.length,
      sample_key_previews: keys.slice(0, 5).map((key) => _tripKpiMask(key)),
    });
  }

  const currentDashboardValues = await _readCurrentDashboardKpiValues(env, normalizedScope, month);
  const postResetExpected = {
    completed_rides_count: 0,
    unpaid_completed_rides_count: 0,
    monthly_income_cents: 0,
    monthly_paid_bookings_income_cents: 0,
  };

  const errors = [];
  let deletedTotal = 0;
  const deletedByCategory = {};

  if (!dryRun) {
    for (const def of categoryDefs) {
      const keys = keysByCategory[def.id] || [];
      let deleted = 0;
      for (const key of keys) {
        try {
          await env.FLUXIDI_TRACKING.delete(key);
          deleted += 1;
          deletedTotal += 1;
        } catch (err) {
          errors.push({
            category: def.id,
            key_preview: _tripKpiMask(key),
            error: safeStr(String(err?.message || err), 120),
          });
        }
      }
      deletedByCategory[def.id] = deleted;
    }
    console.log(
      `[DEV_DASHBOARD_KPI_RESET][EXECUTE] tenant=${_tripKpiMask(tenantId)} company=${_tripKpiMask(companyId)} deleted=${deletedTotal} include_trip_history=${includeTripHistory ? "true" : "false"} errors=${errors.length}`,
    );
  } else {
    console.log(
      `[DEV_DASHBOARD_KPI_RESET][DRY_RUN] tenant=${_tripKpiMask(tenantId)} company=${_tripKpiMask(companyId)} would_delete=${wouldDeleteTotal} include_trip_history=${includeTripHistory ? "true" : "false"}`,
    );
  }

  return withCors(
    json(
      {
        ok: true,
        dry_run: dryRun,
        tenant_id: tenantId,
        company_id: companyId,
        month,
        include_trip_history: includeTripHistory,
        categories,
        would_delete_total: wouldDeleteTotal,
        current_dashboard_values: currentDashboardValues,
        post_reset_expected: postResetExpected,
        ...(dryRun
          ? {}
          : {
              deleted_total: deletedTotal,
              deleted_by_category: deletedByCategory,
              errors,
            }),
        message: dryRun
          ? "Dry-run only. Scoped dashboard KPI reset candidates collected."
          : "Scoped dashboard KPI reset completed.",
      },
      { status: 200 },
    ),
    origin,
  );
}

async function handleTripsHistory(req, url, env, origin) {
  requireAdmin(req, url, env);

  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const tenant_id = scope.tenant_id;
  const company_id = scope.company_id;
  const driver_id = safeStr(url.searchParams.get("driver_id"), 96);
  const limit = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") || 50)));
  const includeActive = (url.searchParams.get("include_active") || "").toLowerCase() === "1";
  const includeArchived = (url.searchParams.get("include_archived") || "").toLowerCase() === "1";
  const scopedIndexKey = driver_id
    ? scopedTripsDriverIndexKey(scope, driver_id)
    : scopedTripsIndexKey(scope);
  const scopedIds = (await kvGetJson(env.FLUXIDI_TRACKING, scopedIndexKey)) ?? [];
  const tripIds = Array.isArray(scopedIds)
    ? scopedIds
    : [];
  const trips = [];
  const cleaned = [];

  for (const trip_id of tripIds) {
    const safeTripId = safeStr(trip_id, 128);
    if (!safeTripId) continue;
    const scopedTripStorageKey = scopedTripKey(scope, safeTripId);
    let trip = await kvGetJson(env.FLUXIDI_TRACKING, scopedTripStorageKey);
    if (!trip) {
      const legacyTrip = await kvGetJson(env.FLUXIDI_TRACKING, tripKey(safeTripId));
      if (
        legacyTrip &&
        recordMatchesTenantCompanyScope(legacyTrip, scope)
      ) {
        const migratedTrip = applyCanonicalScopeToRecord(
          { ...legacyTrip },
          scope,
        );
        await kvPutJson(env.FLUXIDI_TRACKING, scopedTripStorageKey, migratedTrip, TTL_TRIP);
        trip = migratedTrip;
      }
    }
    if (!trip) continue;
    if (!recordMatchesTenantCompanyScope(trip, scope)) {
      continue;
    }
    cleaned.push(safeTripId);
    if (!includeActive && trip.status === "active") continue;
    if (!includeArchived && trip.archived === true) continue;
    trips.push(summarizeTrip(trip));
    if (trips.length >= limit) break;
  }

  if (cleaned.length !== tripIds.length) {
    await kvPutJson(
      env.FLUXIDI_TRACKING,
      scopedIndexKey,
      cleaned.slice(0, driver_id ? 200 : 500),
      TTL_TRIP
    );
  }

  return withCors(
    json({ ok: true, tenant_id, company_id, driver_id: driver_id ?? null, count: trips.length, trips }, { status: 200 }),
    origin
  );
}

async function handleArchiveTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const tenant_id = scope.tenant_id;
  const company_id = scope.company_id;
  const driver_id = safeStr(body["driver_id"], 96);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const tripResolved = await getScopedOrLegacyTripForScope(env, scope, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope)) throw new Error("invalid trip scope");
  const key = tripResolved.key;

  const tripDriver = safeStr(trip.driver_id, 96);
  if (driver_id && tripDriver && tripDriver !== driver_id) {
    throw new Error("Trip driver mismatch");
  }

  const archived = body["archived"] !== false;
  trip.archived = archived;
  if (archived) {
    trip.archived_at = nowIso();
    trip.archived_by = driver_id || "admin";
  } else {
    trip.archived_at = null;
    trip.archived_by = driver_id || "admin";
  }
  applyCanonicalScopeToRecord(trip, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  return withCors(
    json({ ok: true, archived, trip_id }, { status: 200 }),
    origin
  );
}

async function handleStartDirectTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const tenant_id = scope.tenant_id;
  const company_id = scope.company_id;
  const driver_id = safeStr(body["driver_id"], 96);
  if (!driver_id) throw new Error("driver_id is required");

  const vehicle_id = safeStr(body["vehicle_id"], 96) ?? null;
  const owner_company_id = company_id;
  if (actor.actor_role === "driver") {
    if (!actor.actor_driver_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver",
      });
      return withCors(json(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    if (!vehicle_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver",
      });
      return withCors(json(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    if (actor.actor_driver_id !== driver_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver",
      });
      return withCors(json(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    if (actor.actor_vehicle_id && actor.actor_vehicle_id !== vehicle_id) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct",
        targetId: "new",
        actor,
        ownerDriverId: driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver",
      });
      return withCors(json(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
    const vehicleOwnership = await _driverVehicleOwnershipBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id,
      vehicle_id,
    });
    _logTrackingOwnershipCheck({
      target: "trip_start_direct_vehicle",
      targetId: vehicle_id,
      actor,
      ownerDriverId: actor.actor_driver_id,
      ownerVehicleId: vehicle_id,
      allowed: vehicleOwnership.allowed,
      reason: vehicleOwnership.reason,
    });
    if (!vehicleOwnership.allowed && vehicleOwnership.certainMismatch) {
      _logTrackingOwnershipBlock({
        target: "trip_start_direct_vehicle",
        targetId: vehicle_id,
        actor,
        ownerDriverId: actor.actor_driver_id,
        ownerVehicleId: vehicle_id,
        error: "trip_not_assigned_to_driver",
      });
      return withCors(json(_trackingOwnershipError("trip_not_assigned_to_driver"), { status: 403 }), origin);
    }
  }
  const originData = normalizeDestination(body["origin"]);
  const destination = normalizeDestination(body["destination"]);
  const pricing_snapshot = normalizePricingSnapshot(body["pricing_snapshot"]);
  const createdAt = nowIso();
  const startedAt = safeStr(body["client_started_at"], 64) ?? createdAt;
  const trip_id = makeTripId();

  const startEvent = {
    type: "start",
    ts: startedAt,
    source: "driver_app",
  };

  const trip = {
    trip_id,
    kind: "direct",
    tenant_id,
    driver_id,
    vehicle_id,
    origin: originData,
    destination,
    pricing_snapshot,
    status: "active",
    timeline: [startEvent],
    created_at: createdAt,
    started_at: startedAt,
    stopped_at: null,
    wait_started_at: null,
    km_total: null,
    wait_seconds_total: 0,
    total_eur: null,
    owner_driver_id: actor.actor_role === "driver" ? actor.actor_driver_id : driver_id,
    owner_vehicle_id: actor.actor_role === "driver" ? (actor.actor_vehicle_id ?? vehicle_id) : vehicle_id,
    owner_tenant_id: tenant_id,
    owner_company_id,
  };
  applyCanonicalScopeToRecord(trip, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, scopedTripKey(scope, trip_id), trip, TTL_TRIP);
  if (actor.actor_role === "driver") {
    await _rememberVehicleOwnerBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id,
      vehicle_id,
    });
  }
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsIndexKey(scope), trip_id, 500);
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsDriverIndexKey(scope, driver_id), trip_id, 200);

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        kind: "direct",
        tenant_id,
        company_id,
        driver_id,
        vehicle_id,
        status: "active",
        created_at: createdAt,
        started_at: startedAt,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleRecordPlannedStopTrip(req, url, env, origin, ctx) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const booking_id = safeStr(body["booking_id"], 96);
  if (!booking_id) throw new Error("booking_id is required");

  const tenant_id = scope.tenant_id;
  const company_id = scope.company_id;
  const driver_id = safeStr(body["driver_id"], 96);
  if (!driver_id) throw new Error("driver_id is required");

  const vehicle_id = safeStr(body["vehicle_id"], 96) ?? null;
  const originData = normalizeDestination(body["origin"]);
  const destination = normalizeDestination(body["destination"]);
  let booking_details = normalizeBookingDetails(body["booking_details"]);
  const leg_id = safeStr(
    body["leg_id"] ??
      body["legId"] ??
      booking_details?.leg_id ??
      booking_details?.legId,
    160,
  ) ?? null;
  const leg_type = safeStr(
    body["leg_type"] ??
      body["legType"] ??
      booking_details?.leg_type ??
      booking_details?.legType,
    32,
  ) ?? null;
  const row_key = safeStr(
    body["row_key"] ??
      body["rowKey"] ??
      booking_details?.row_key ??
      booking_details?.rowKey,
    240,
  ) ?? null;
  const parent_booking_id = safeStr(
    body["parent_booking_id"] ??
      body["parentBookingId"] ??
      booking_details?.parent_booking_id ??
      booking_details?.parentBookingId,
    96,
  ) ?? booking_id;
  const is_operational_leg = !!(leg_id || row_key);
  if (is_operational_leg || parent_booking_id !== booking_id || leg_type) {
    const detailsNext =
      booking_details && typeof booking_details === "object"
        ? { ...booking_details }
        : {};
    if (leg_id) {
      detailsNext.leg_id = leg_id;
      detailsNext.legId = leg_id;
    }
    if (leg_type) {
      detailsNext.leg_type = leg_type;
      detailsNext.legType = leg_type;
    }
    if (row_key) {
      detailsNext.row_key = row_key;
      detailsNext.rowKey = row_key;
    }
    if (parent_booking_id) {
      detailsNext.parent_booking_id = parent_booking_id;
      detailsNext.parentBookingId = parent_booking_id;
    }
    detailsNext.is_operational_leg = is_operational_leg;
    detailsNext.isOperationalLeg = is_operational_leg;
    booking_details = detailsNext;
  }
  const startedAt = safeStr(body["started_at"] ?? body["client_started_at"], 64) ?? null;
  const stoppedAt = safeStr(body["stopped_at"] ?? body["client_stopped_at"], 64) ?? nowIso();
  const km_total = safeNum(body["km_total"], 0, 100000);
  const wait_seconds_total = safeNum(body["wait_seconds_total"] ?? 0, 0, 60 * 60 * 24 * 7) ?? 0;
  const total_eur = safeNum(body["total_eur"], 0, 1000000);
  const currency = safeStr(body["currency"] ?? "EUR", 8) ?? "EUR";
  const tripSuffix =
    sanitizeTripIdentityToken(leg_id, 96) ??
    sanitizeTripIdentityToken(row_key, 96);
  const trip_id = tripSuffix
    ? `planned_${booking_id}_${tripSuffix}`
    : `planned_${booking_id}`;
  const owner_company_id = company_id;

  console.log(
    `[TRACKING][PLANNED_STOP][LEG_IDENTITY] booking=${booking_id} trip=${trip_id} leg=${leg_id || row_key || "-"} type=${leg_type || "-"}`,
  );

  const existingTripResolved = await getScopedOrLegacyTripForScope(env, scope, trip_id);
  const existingTrip = existingTripResolved.trip;
  if (existingTrip) {
    const ownershipBlock = await _assertTripOwnedByActorOrBlock({
      trip: existingTrip,
      trip_id,
      actor,
      error: "trip_not_assigned_to_driver",
      origin,
    });
    if (ownershipBlock) {
      const resolved = await resolveSessionByBookingForScope(env, scope, booking_id);
      const resolvedSession = resolved?.session;
      const resolvedMap = resolved?.map;
      const sessionStatus = safeStr(resolvedSession?.status, 32)?.toLowerCase() ?? "";
      const sessionBookingId = _trackingOwnershipValue(
        resolvedSession?.owner_booking_id ??
          resolvedSession?.booking_id ??
          resolvedSession?.bookingId ??
          resolvedMap?.owner_booking_id,
      );
      const sessionOwnerCheck = _trackingOwnershipAllowed({
        actorDriverId: actor.actor_driver_id,
        actorVehicleId: actor.actor_vehicle_id,
        ownerDriverId: _trackingOwnershipValue(
          resolvedSession?.owner_driver_id ?? resolvedSession?.driver_id,
        ),
        ownerVehicleId: _trackingOwnershipValue(
          resolvedSession?.owner_vehicle_id ?? resolvedSession?.vehicle_id,
        ),
        fallbackDriverId: _trackingOwnershipValue(resolvedSession?.driver_id),
        fallbackVehicleId: _trackingOwnershipValue(resolvedSession?.vehicle_id),
      });
      const sessionOwnershipProofPassed =
        sessionStatus === "stopped" &&
        (!sessionBookingId || sessionBookingId === booking_id) &&
        sessionOwnerCheck.allowed &&
        (sessionOwnerCheck.reason === "driver_match" ||
          sessionOwnerCheck.reason === "vehicle_match");
      if (!sessionOwnershipProofPassed) return ownershipBlock;
      console.log(
        `[TRACKING_OWNERSHIP][PLANNED_STOP_SESSION_PROOF_OVERRIDE] booking_id=${booking_id} trip_id=${trip_id} reason=stale_existing_trip_owner`,
      );
    }
  }

  const trip = {
    trip_id,
    kind: "planned",
    booking_id,
    leg_id,
    legId: leg_id,
    leg_type,
    legType: leg_type,
    row_key,
    rowKey: row_key,
    parent_booking_id,
    parentBookingId: parent_booking_id,
    is_operational_leg,
    isOperationalLeg: is_operational_leg,
    tenant_id,
    driver_id,
    vehicle_id,
    origin: originData,
    destination,
    booking_details,
    status: "stopped",
    timeline: [
      {
        type: "planned_stop",
        ts: stoppedAt,
        source: "driver_app",
        booking_id,
        km_total,
        wait_seconds_total,
        total_eur,
      },
    ],
    created_at: startedAt ?? stoppedAt,
    started_at: startedAt,
    stopped_at: stoppedAt,
    wait_started_at: null,
    km_total,
    wait_seconds_total,
    total_eur,
    currency,
    owner_driver_id: actor.actor_role === "driver" ? actor.actor_driver_id : driver_id,
    owner_vehicle_id: actor.actor_role === "driver" ? (actor.actor_vehicle_id ?? vehicle_id) : vehicle_id,
    owner_tenant_id: tenant_id,
    owner_company_id,
    owner_booking_id: booking_id,
  };
  applyCanonicalScopeToRecord(trip, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, scopedTripKey(scope, trip_id), trip, TTL_TRIP);
  await materializeTripDashboardKpisBestEffort(
    env,
    scope,
    trip,
    "planned_trip_stop",
  );
  if (actor.actor_role === "driver") {
    await _rememberVehicleOwnerBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id ?? driver_id,
      vehicle_id: actor.actor_vehicle_id ?? vehicle_id,
    });
  }
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsIndexKey(scope), trip_id, 500);
  await prependIndex(env.FLUXIDI_TRACKING, scopedTripsDriverIndexKey(scope, driver_id), trip_id, 200);

  const complianceEvent = buildPlannedTripStopComplianceEvent(trip, body, scope);
  if (complianceEvent) {
    const emitTask = emitComplianceEventBestEffort(env, complianceEvent, {
      timeoutMs: 1500,
      logLabel: "planned_ride_stop",
    });
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        kind: "planned",
        booking_id,
        status: "stopped",
        stopped_at: stoppedAt,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleWaitStartTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const tripResolved = await getScopedOrLegacyTripForScope(env, scope, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope)) throw new Error("invalid trip scope");
  const key = tripResolved.key;
  if (trip.status !== "active") throw new Error("Trip is not active");
  if (trip.wait_started_at) {
    return withCors(
      json({ ok: false, error: "Wait already active", trip_id, wait_started_at: trip.wait_started_at }, { status: 409 }),
      origin
    );
  }

  const waitStartedAt = safeStr(body["client_wait_started_at"], 64) ?? nowIso();
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "wait_start",
    ts: waitStartedAt,
    source: "driver_app",
  });

  trip.wait_started_at = waitStartedAt;
  trip.timeline = timeline;
  trip.wait_seconds_total = Number.isFinite(Number(trip.wait_seconds_total))
    ? Number(trip.wait_seconds_total)
    : 0;
  applyCanonicalScopeToRecord(trip, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  return withCors(
    json({ ok: true, trip_id, status: "active", wait_started_at: waitStartedAt }, { status: 200 }),
    origin
  );
}

async function handleWaitEndTrip(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const tripResolved = await getScopedOrLegacyTripForScope(env, scope, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope)) throw new Error("invalid trip scope");
  const key = tripResolved.key;
  if (trip.status !== "active") throw new Error("Trip is not active");
  if (!trip.wait_started_at) {
    return withCors(
      json({ ok: false, error: "No active wait", trip_id }, { status: 409 }),
      origin
    );
  }

  const waitEndedAt = safeStr(body["client_wait_ended_at"], 64) ?? nowIso();
  const startedMs = Date.parse(trip.wait_started_at);
  const endedMs = Date.parse(waitEndedAt);
  const addedWaitSeconds =
    Number.isFinite(startedMs) && Number.isFinite(endedMs)
      ? Math.max(0, Math.round((endedMs - startedMs) / 1000))
      : 0;
  const currentWaitSeconds = Number.isFinite(Number(trip.wait_seconds_total))
    ? Number(trip.wait_seconds_total)
    : 0;
  const nextWaitSeconds = currentWaitSeconds + addedWaitSeconds;

  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "wait_end",
    ts: waitEndedAt,
    source: "driver_app",
    wait_seconds_added: addedWaitSeconds,
    wait_seconds_total: nextWaitSeconds,
  });

  trip.wait_started_at = null;
  trip.wait_seconds_total = nextWaitSeconds;
  trip.timeline = timeline;
  applyCanonicalScopeToRecord(trip, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        status: "active",
        wait_ended_at: waitEndedAt,
        wait_seconds_added: addedWaitSeconds,
        wait_seconds_total: nextWaitSeconds,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleStopTrip(req, url, env, origin, ctx) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const tripResolved = await getScopedOrLegacyTripForScope(env, scope, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope)) throw new Error("invalid trip scope");
  const key = tripResolved.key;
  const ownershipBlock = await _assertTripOwnedByActorOrBlock({
    trip,
    trip_id,
    actor,
    error: "trip_not_assigned_to_driver",
    origin,
  });
  if (ownershipBlock) return ownershipBlock;
  if (trip.status !== "active") throw new Error("Trip is not active");

  const km_total = safeNum(body["km_total"], 0, 100000);
  if (km_total === null) throw new Error("km_total is required");

  const wait_seconds_total = safeNum(body["wait_seconds_total"] ?? 0, 0, 60 * 60 * 24 * 7);
  if (wait_seconds_total === null) throw new Error("wait_seconds_total is invalid");

  const stoppedAt = safeStr(body["client_stopped_at"], 64) ?? nowIso();
  const totals = directTripTotals(trip, km_total, wait_seconds_total);
  console.log(
    `[DIRECT_TRIP][STOP_PRICING] source=snapshot vatMode=${totals.vat_mode ?? "incl"} totalIncl=${Number(totals.price_incl_vat ?? totals.total_eur ?? 0).toFixed(2)}`,
  );
  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "stop",
    ts: stoppedAt,
    source: "driver_app",
    km_total: totals.km_total,
    wait_seconds_total: totals.wait_seconds_total,
    total_eur: totals.total_eur,
    price_ex_vat: totals.price_ex_vat,
    price_vat: totals.price_vat,
    price_incl_vat: totals.price_incl_vat,
    vat_rate: totals.vat_rate,
    vat_mode: totals.vat_mode,
  });

  trip.status = "stopped";
  trip.stopped_at = stoppedAt;
  trip.km_total = totals.km_total;
  trip.wait_seconds_total = totals.wait_seconds_total;
  trip.total_eur = totals.total_eur;
  trip.price_ex_vat = totals.price_ex_vat;
  trip.price_vat = totals.price_vat;
  trip.price_incl_vat = totals.price_incl_vat;
  trip.vat_rate = totals.vat_rate;
  trip.vat_mode = totals.vat_mode;
  trip.timeline = timeline;
  applyCanonicalScopeToRecord(trip, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);
  await materializeTripDashboardKpisBestEffort(
    env,
    scope,
    trip,
    "direct_trip_stop",
  );

  const complianceEvent = buildDirectTripStopComplianceEvent(trip, body, stoppedAt, totals, scope);
  if (!complianceEvent) {
    console.log(`[COMPLIANCE_EMIT][direct_stop] skipped reason=missing_canonical_scope trip_id=${trip_id}`);
  }
  if (complianceEvent) {
    const emitTask = emitComplianceEventBestEffort(env, complianceEvent, { timeoutMs: 1500 });
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        status: "stopped",
        stopped_at: stoppedAt,
        totals,
      },
      { status: 200 }
    ),
    origin
  );
}

async function handleTripPayment(req, url, env, origin, ctx) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const trip_id = safeStr(body["trip_id"], 128);
  if (!trip_id) throw new Error("trip_id is required");

  const tripResolved = await getScopedOrLegacyTripForScope(env, scope, trip_id);
  const trip = tripResolved.trip;
  if (!trip) throw new Error("Unknown trip_id");
  if (!recordMatchesTenantCompanyScope(trip, scope)) throw new Error("invalid trip scope");
  const key = tripResolved.key;
  const ownershipBlock = await _assertTripOwnedByActorOrBlock({
    trip,
    trip_id,
    actor,
    error: "trip_not_assigned_to_driver",
    origin,
  });
  if (ownershipBlock) return ownershipBlock;

  const rawStatus = String(body["payment_status"] ?? body["paymentStatus"] ?? "")
    .trim()
    .toLowerCase();
  const payment_status =
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

  const payment_method = safeStr(
    String(body["payment_method"] ?? body["paymentMethod"] ?? "").toLowerCase(),
    32,
  );
  const payment_source =
    safeStr(
      String(body["payment_source"] ?? body["paymentSource"] ?? "in_car").toLowerCase(),
      32,
    ) ?? "in_car";
  const paid_at = safeStr(body["paid_at"] ?? body["paidAt"], 64) ?? nowIso();
  const currency =
    (safeStr(body["currency"], 8) ??
      safeStr(trip?.currency, 8) ??
      safeStr(trip?.pricing_snapshot?.currency, 8) ??
      "EUR").toUpperCase();
  const amountRaw = body["amount"] ?? body["price"] ?? body["total"];
  const amountNum = Number(amountRaw);
  const amount = Number.isFinite(amountNum) ? amountNum : null;
  const paid_by_driver_id = safeStr(
    body["paid_by_driver_id"] ?? body["paidByDriverId"],
    96,
  );
  const leg_id = safeStr(
    body["leg_id"] ?? body["legId"] ?? trip?.leg_id ?? trip?.legId,
    160,
  );
  const leg_type = safeStr(
    body["leg_type"] ?? body["legType"] ?? trip?.leg_type ?? trip?.legType,
    64,
  );
  const parent_booking_id = safeStr(
    body["parent_booking_id"] ??
      body["parentBookingId"] ??
      trip?.parent_booking_id ??
      trip?.parentBookingId,
    160,
  );
  const row_key = safeStr(
    body["row_key"] ?? body["rowKey"] ?? trip?.row_key ?? trip?.rowKey,
    240,
  );

  trip.payment_status = payment_status;
  trip.paymentStatus = payment_status;
  trip.payment_source = payment_source;
  trip.paymentSource = payment_source;
  trip.paid_at = paid_at;
  trip.paidAt = paid_at;
  trip.currency = currency;
  if (payment_method) {
    trip.payment_method = payment_method;
    trip.paymentMethod = payment_method;
  }
  if (amount !== null) {
    trip.payment_amount = amount;
    trip.paymentAmount = amount;
  }
  if (paid_by_driver_id) {
    trip.paid_by_driver_id = paid_by_driver_id;
    trip.paidByDriverId = paid_by_driver_id;
  }
  if (leg_id) {
    trip.leg_id = leg_id;
    trip.legId = leg_id;
  }
  if (leg_type) {
    trip.leg_type = leg_type;
    trip.legType = leg_type;
  }
  if (parent_booking_id) {
    trip.parent_booking_id = parent_booking_id;
    trip.parentBookingId = parent_booking_id;
  }
  if (row_key) {
    trip.row_key = row_key;
    trip.rowKey = row_key;
  }
  if (leg_id || leg_type || row_key) {
    trip.is_operational_leg = true;
    trip.isOperationalLeg = true;
  }
  const nextBookingDetails =
    trip?.booking_details &&
    typeof trip.booking_details === "object" &&
    !Array.isArray(trip.booking_details)
      ? { ...trip.booking_details }
      : {};
  if (leg_id) {
    nextBookingDetails.leg_id = leg_id;
    nextBookingDetails.legId = leg_id;
  }
  if (leg_type) {
    nextBookingDetails.leg_type = leg_type;
    nextBookingDetails.legType = leg_type;
  }
  if (parent_booking_id) {
    nextBookingDetails.parent_booking_id = parent_booking_id;
    nextBookingDetails.parentBookingId = parent_booking_id;
  }
  if (row_key) {
    nextBookingDetails.row_key = row_key;
    nextBookingDetails.rowKey = row_key;
  }
  if (leg_id || leg_type || row_key) {
    nextBookingDetails.is_operational_leg = true;
    nextBookingDetails.isOperationalLeg = true;
  }
  const normalizedBookingDetails = normalizeBookingDetails(nextBookingDetails);
  if (normalizedBookingDetails) {
    trip.booking_details = normalizedBookingDetails;
  }

  const timeline = Array.isArray(trip.timeline) ? trip.timeline : [];
  timeline.push({
    type: "payment_marked",
    ts: paid_at,
    source: "driver_app",
    payment_status,
    payment_method: payment_method ?? null,
    payment_source,
    currency,
    amount,
    paid_by_driver_id: paid_by_driver_id ?? null,
  });
  trip.timeline = timeline;
  applyCanonicalScopeToRecord(trip, scope);
  const tripIdPreview = _tripKpiMask(trip_id) || "-";
  const bookingIdPreview = _tripKpiMask(safeStr(trip?.booking_id ?? trip?.bookingId, 96)) || "-";
  const legIdPreview = _tripKpiMask(leg_id) || "-";
  console.log(
    `[TRIP_PAYMENT][UPDATE] trip=${tripIdPreview} booking=${bookingIdPreview} leg=${legIdPreview} type=${leg_type || "-"} status=${payment_status} method=${payment_method || "-"} amount=${
      amount !== null ? amount : "-"
    }`,
  );

  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);
  await materializeTripDashboardKpisBestEffort(
    env,
    scope,
    trip,
    "trip_payment_update",
  );

  const complianceEvent = buildTripPaymentUpdateComplianceEvent(trip, body, scope);
  if (!complianceEvent) {
    console.log(`[COMPLIANCE_EMIT][direct_payment_update] skipped reason=missing_canonical_scope trip_id=${trip_id}`);
  }
  if (complianceEvent) {
    const emitTask = emitComplianceEventBestEffort(env, complianceEvent, {
      timeoutMs: 1500,
      logLabel: "direct_payment_update",
    });
    if (ctx && typeof ctx.waitUntil === "function") {
      ctx.waitUntil(emitTask);
    } else {
      await emitTask;
    }
  }

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        payment: {
          payment_status,
          payment_method: payment_method ?? null,
          payment_source,
          paid_at,
          currency,
          amount,
          paid_by_driver_id: paid_by_driver_id ?? null,
        },
        trip: summarizeTrip(trip),
      },
      { status: 200 },
    ),
    origin,
  );
}

async function handleStart(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const booking_id = safeStr(body["booking_id"], 64);
  if (!booking_id) throw new Error("booking_id is required");

  const pickup = safeStr(body["pickup"], 200) ?? null;
  const dropoff = safeStr(body["dropoff"], 200) ?? null;
  const tenant_id = scope.tenant_id;
  const company_id = scope.company_id;
  const owner_driver_id = safeStr(body["driver_id"], 96) ?? actor.actor_driver_id ?? null;
  const owner_vehicle_id = safeStr(body["vehicle_id"], 96) ?? actor.actor_vehicle_id ?? null;
  const directStartOwnerCheck = _trackingOwnershipAllowed({
    actorDriverId: actor.actor_driver_id,
    actorVehicleId: actor.actor_vehicle_id,
    ownerDriverId: owner_driver_id,
    ownerVehicleId: owner_vehicle_id,
  });
  const directStartOwnershipPassed =
    directStartOwnerCheck.allowed &&
    (directStartOwnerCheck.reason === "driver_match" ||
      directStartOwnerCheck.reason === "vehicle_match");
  if (actor.actor_role === "driver") {
    _logTrackingOwnershipCheck({
      target: "session_start_payload",
      targetId: booking_id,
      actor,
      ownerDriverId: directStartOwnerCheck.candidateDriver,
      ownerVehicleId: directStartOwnerCheck.candidateVehicle,
      allowed: directStartOwnerCheck.allowed,
      reason: directStartOwnerCheck.reason,
    });
  }

  if (actor.actor_role === "driver" && !actor.actor_driver_id) {
    _logTrackingOwnershipBlock({
      target: "session_start",
      targetId: booking_id,
      actor,
      ownerDriverId: owner_driver_id,
      ownerVehicleId: owner_vehicle_id,
      error: "booking_not_assigned_to_driver",
    });
    return withCors(json(_trackingOwnershipError("booking_not_assigned_to_driver"), { status: 403 }), origin);
  }
  if (actor.actor_role === "driver") {
    const existingBookingMap = await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedBookingSessionKey(scope, booking_id),
    );
    let assignmentOwnershipPassed = false;
    if (existingBookingMap && !recordMatchesTenantCompanyScope(existingBookingMap, scope)) {
      throw new Error("invalid booking scope");
    }
    if (existingBookingMap) {
      const existingSessionId = safeStr(existingBookingMap.session_id ?? existingBookingMap.sessionId, 128);
      const existingSession = existingSessionId
        ? await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope, existingSessionId))
        : null;
      if (existingSession && !recordMatchesTenantCompanyScope(existingSession, scope)) {
        throw new Error("invalid session scope");
      }
      const assignmentOwnerDriverId = _trackingOwnershipValue(
        existingBookingMap.owner_driver_id ??
          existingBookingMap.assigned_driver_id ??
          existingBookingMap.assignedDriverId ??
          existingBookingMap.driver_id ??
          existingBookingMap.driverId ??
          existingBookingMap?.assigned_driver?.driver_id ??
          existingBookingMap?.assigned_driver?.driverId ??
          existingBookingMap?.assignedDriver?.driver_id ??
          existingBookingMap?.assignedDriver?.driverId ??
          existingSession?.owner_driver_id ??
          existingSession?.assigned_driver_id ??
          existingSession?.assignedDriverId ??
          existingSession?.driver_id ??
          existingSession?.driverId ??
          existingSession?.assigned_driver?.driver_id ??
          existingSession?.assigned_driver?.driverId ??
          existingSession?.assignedDriver?.driver_id ??
          existingSession?.assignedDriver?.driverId,
      );
      const assignmentOwnerVehicleId = _trackingOwnershipValue(
        existingBookingMap.owner_vehicle_id ??
          existingBookingMap.assigned_vehicle_id ??
          existingBookingMap.assignedVehicleId ??
          existingBookingMap.vehicle_id ??
          existingBookingMap.vehicleId ??
          existingSession?.owner_vehicle_id ??
          existingSession?.assigned_vehicle_id ??
          existingSession?.assignedVehicleId ??
          existingSession?.vehicle_id ??
          existingSession?.vehicleId,
      );
      const ownerCheck = _trackingOwnershipAllowed({
        actorDriverId: actor.actor_driver_id,
        actorVehicleId: actor.actor_vehicle_id,
        ownerDriverId: assignmentOwnerDriverId,
        ownerVehicleId: assignmentOwnerVehicleId,
      });
      assignmentOwnershipPassed =
        ownerCheck.allowed &&
        (ownerCheck.reason === "driver_match" || ownerCheck.reason === "vehicle_match");
      _logTrackingOwnershipCheck({
        target: "session_start_booking",
        targetId: booking_id,
        actor,
        ownerDriverId: ownerCheck.candidateDriver,
        ownerVehicleId: ownerCheck.candidateVehicle,
        allowed: ownerCheck.allowed,
        reason: ownerCheck.reason,
      });
      if (!ownerCheck.allowed && ownerCheck.certainMismatch) {
        _logTrackingOwnershipBlock({
          target: "session_start_booking",
          targetId: booking_id,
          actor,
          ownerDriverId: ownerCheck.candidateDriver,
          ownerVehicleId: ownerCheck.candidateVehicle,
          error: "booking_not_assigned_to_driver",
        });
        return withCors(json(_trackingOwnershipError("booking_not_assigned_to_driver"), { status: 403 }), origin);
      }
    }
    if (actor.actor_vehicle_id) {
      const vehicleOwnership = await _driverVehicleOwnershipBestEffort(env, {
        tenant_id,
        company_id,
        driver_id: actor.actor_driver_id,
        vehicle_id: actor.actor_vehicle_id,
      });
      _logTrackingOwnershipCheck({
        target: "session_start_vehicle",
        targetId: actor.actor_vehicle_id,
        actor,
        ownerDriverId: actor.actor_driver_id,
        ownerVehicleId: actor.actor_vehicle_id,
        allowed: vehicleOwnership.allowed,
        reason: vehicleOwnership.reason,
      });
      const ownershipProofPassed = assignmentOwnershipPassed || directStartOwnershipPassed;
      if (
        !vehicleOwnership.allowed &&
        vehicleOwnership.certainMismatch &&
        vehicleOwnership.reason === "vehicle_owner_mismatch" &&
        ownershipProofPassed
      ) {
        console.log(
          `[TRACKING_OWNERSHIP][REPAIR_OWNER_VEHICLE] target=session_start_vehicle vehicle=${actor.actor_vehicle_id} driver=${actor.actor_driver_id} reason=assignment_match_overrides_stale_owner_map`,
        );
        await _rememberVehicleOwnerBestEffort(env, {
          tenant_id,
          company_id,
          driver_id: actor.actor_driver_id,
          vehicle_id: actor.actor_vehicle_id,
        });
      }
      if (!vehicleOwnership.allowed && vehicleOwnership.certainMismatch && !ownershipProofPassed) {
        _logTrackingOwnershipBlock({
          target: "session_start_vehicle",
          targetId: actor.actor_vehicle_id,
          actor,
          ownerDriverId: actor.actor_driver_id,
          ownerVehicleId: actor.actor_vehicle_id,
          error: "booking_not_assigned_to_driver",
        });
        return withCors(json(_trackingOwnershipError("booking_not_assigned_to_driver"), { status: 403 }), origin);
      }
    }
  }

  const sessionId = `s_${booking_id}_${Date.now().toString(36)}_${Math.random()
    .toString(36)
    .slice(2, 8)}`;

  const public_token = `p_${randToken(24)}`;

  const session = {
    session_id: sessionId,
    booking_id,
    pickup,
    dropoff,
    status: "active",
    created_at: nowIso(),
    last_ping_at: null,
    points: [],
    public_token,
    driver_id: owner_driver_id,
    vehicle_id: owner_vehicle_id,
    owner_driver_id: actor.actor_role === "driver" ? actor.actor_driver_id : owner_driver_id,
    owner_vehicle_id: actor.actor_role === "driver" ? (actor.actor_vehicle_id ?? owner_vehicle_id) : owner_vehicle_id,
    owner_booking_id: booking_id,
    owner_tenant_id: tenant_id,
    owner_company_id: company_id,
  };
  applyCanonicalScopeToRecord(session, scope);

  const scopedSession = scopedSessionKey(scope, sessionId);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedSession, session, TTL_SESSION);

  const bookingMap = {
    session_id: sessionId,
    created_at: session.created_at,
    pickup,
    dropoff,
    public_token,
    owner_driver_id: session.owner_driver_id ?? null,
    owner_vehicle_id: session.owner_vehicle_id ?? null,
    owner_booking_id: booking_id,
    owner_tenant_id: session.owner_tenant_id ?? null,
    owner_company_id: session.owner_company_id ?? null,
  };
  applyCanonicalScopeToRecord(bookingMap, scope);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedBookingSessionKey(scope, booking_id), bookingMap, TTL_SESSION);
  if (actor.actor_role === "driver") {
    await _rememberVehicleOwnerBestEffort(env, {
      tenant_id,
      company_id,
      driver_id: actor.actor_driver_id,
      vehicle_id: actor.actor_vehicle_id ?? owner_vehicle_id,
    });
  }

  await kvPutJson(
    env.FLUXIDI_TRACKING,
    scopedPublicBookingKey(scope, public_token),
    {
      booking_id,
      session_id: sessionId,
      tenant_id,
      company_id,
      tenantId: tenant_id,
      companyId: company_id,
      created_at: session.created_at,
    },
    TTL_PUBLIC_TOKEN
  );
  // Public token mappings are scoped-only in normal operation.

  const idx = (await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope))) ?? [];
  const next = [booking_id, ...idx.filter((x) => x !== booking_id)].slice(0, 200);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope), next, TTL_INDEX);

  return withCors(
    json({ ok: true, session_id: sessionId, booking_id, created_at: session.created_at, public_token }, { status: 200 }),
    origin
  );
}

async function handlePing(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const session_id = safeStr(body["session_id"], 128);
  if (!session_id) throw new Error("session_id is required");

  const lat = safeNum(body["lat"], -90, 90);
  const lon = safeNum(body["lon"], -180, 180);
  if (lat === null || lon === null) throw new Error("lat/lon invalid");

  const speed = safeNum(body["speed"], 0, 200) ?? null;
  const heading = safeNum(body["heading"], 0, 360) ?? null;

  const sessionKey = scopedSessionKey(scope, session_id);
  const session = await kvGetJson(env.FLUXIDI_TRACKING, sessionKey);
  if (!session) throw new Error("Unknown session_id");
  if (!recordMatchesTenantCompanyScope(session, scope)) throw new Error("invalid session scope");
  const ownershipBlock = await _assertSessionOwnedByActorOrBlock({
    session,
    session_id,
    actor,
    error: "session_not_assigned_to_driver",
    origin,
  });
  if (ownershipBlock) return ownershipBlock;

  if (session.status === "stopped") {
    return withCors(json({ ok: false, error: "Session stopped" }, { status: 409 }), origin);
  }

  const point = { lat, lon, ts: nowIso(), speed, heading };

  const points = Array.isArray(session.points) ? session.points : [];
  points.push(point);
  if (points.length > 1200) points.splice(0, points.length - 1200);

  session.points = points;
  session.last_ping_at = point.ts;
  applyCanonicalScopeToRecord(session, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, sessionKey, session, TTL_SESSION);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedPingLastKey(scope, session_id), point, TTL_LASTPING);

  return withCors(json({ ok: true, session_id, ts: point.ts }, { status: 200 }), origin);
}

async function handleStop(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const session_id = safeStr(body["session_id"], 128);
  if (!session_id) throw new Error("session_id is required");

  const sessionKey = scopedSessionKey(scope, session_id);
  const session = await kvGetJson(env.FLUXIDI_TRACKING, sessionKey);
  if (!session) throw new Error("Unknown session_id");
  if (!recordMatchesTenantCompanyScope(session, scope)) throw new Error("invalid session scope");
  const ownershipBlock = await _assertSessionOwnedByActorOrBlock({
    session,
    session_id,
    actor,
    error: "session_not_assigned_to_driver",
    origin,
  });
  if (ownershipBlock) return ownershipBlock;

  session.status = "stopped";
  session.stopped_at = nowIso();
  applyCanonicalScopeToRecord(session, scope);

  await kvPutJson(env.FLUXIDI_TRACKING, sessionKey, session, TTL_INDEX);

  return withCors(json({ ok: true, session_id, status: "stopped" }, { status: 200 }), origin);
}

// Resolve booking -> map + session + last ping (scoped-only)
async function resolveSessionByBookingForScope(env, scope, booking_id) {
  const map = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedBookingSessionKey(scope, booking_id),
  );
  if (!map) return null;
  if (!recordMatchesTenantCompanyScope(map, scope)) return null;

  const sessionId = safeStr(map?.session_id ?? map?.sessionId, 128);
  if (!sessionId) return null;

  const session = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedSessionKey(scope, sessionId),
  );
  if (!session) return null;
  if (!recordMatchesTenantCompanyScope(session, scope)) return null;

  const last = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedPingLastKey(scope, sessionId),
  );
  return { map, session, last, session_id: sessionId };
}

// GET /track/bookings (auto-cleans orphans)
async function handleBookings(req, url, env, origin) {
  requireAdmin(req, url, env);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;

  const scopedIndex = (await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope))) ?? [];
  const idx = Array.isArray(scopedIndex) ? scopedIndex : [];
  const limit = Math.min(200, Math.max(1, Number(url.searchParams.get("limit") || 50)));

  const bookings = [];
  const cleanedIndex = [];

  for (const booking_id of idx) {
    const map = await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedBookingSessionKey(scope, booking_id),
    );
    if (!map) continue; // orphan index entry: drop it
    if (!recordMatchesTenantCompanyScope(map, scope)) continue;

    const sessionId = safeStr(map.session_id ?? map.sessionId, 128);
    if (!sessionId) continue;
    const session = await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedSessionKey(scope, sessionId),
    );
    if (!session || !recordMatchesTenantCompanyScope(session, scope)) continue;

    cleanedIndex.push(booking_id);

    const last = await kvGetJson(
      env.FLUXIDI_TRACKING,
      scopedPingLastKey(scope, sessionId),
    );
    bookings.push({
      booking_id,
      session_id: sessionId,
      created_at: map.created_at,
      pickup: map.pickup ?? null,
      dropoff: map.dropoff ?? null,
      public_token: map.public_token ?? null,
      last_ping: last ?? null,
    });

    if (bookings.length >= limit) break;
  }

  const indexTrimmed = cleanedIndex.slice(0, 200);
  if (cleanedIndex.length !== idx.length || !Array.isArray(scopedIndex) || scopedIndex.length === 0) {
    await kvPutJson(env.FLUXIDI_TRACKING, scopedBookingIndexKey(scope), indexTrimmed, TTL_INDEX);
  }

  return withCors(json({ ok: true, count: bookings.length, bookings }, { status: 200 }), origin);
}

// GET /track/booking?booking_id=...
async function handleBookingDetails(req, url, env, origin) {
  requireAdmin(req, url, env);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;

  const booking_id = safeStr(url.searchParams.get("booking_id"), 64);
  if (!booking_id) throw new Error("booking_id is required");

  const resolved = await resolveSessionByBookingForScope(env, scope, booking_id);
  if (!resolved) throw new Error("Unknown booking_id");

  const { map, session, last, session_id } = resolved;

  return withCors(
    json(
      {
        ok: true,
        booking_id,
        session_id,
        created_at: map.created_at,
        pickup: map.pickup ?? null,
        dropoff: map.dropoff ?? null,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points_count: Array.isArray(session?.points) ? session.points.length : 0,
        public_token: map.public_token ?? session?.public_token ?? null,
      },
      { status: 200 }
    ),
    origin
  );
}

// GET /track/live?booking_id=...&limit=...
async function handleLive(req, url, env, origin) {
  requireAdmin(req, url, env);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;

  const booking_id = safeStr(url.searchParams.get("booking_id"), 64);
  if (!booking_id) throw new Error("booking_id is required");

  const limit = Math.min(1200, Math.max(1, Number(url.searchParams.get("limit") || 300)));

  const resolved = await resolveSessionByBookingForScope(env, scope, booking_id);
  if (!resolved) throw new Error("Unknown booking_id");

  const { session, last, session_id } = resolved;

  const points = Array.isArray(session?.points) ? session.points : [];
  const sliced = points.slice(Math.max(0, points.length - limit));

  return withCors(
    json(
      {
        ok: true,
        booking_id,
        session_id,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points: sliced,
      },
      { status: 200 }
    ),
    origin
  );
}

// GET /track/public/live?token=...&limit=...
async function handlePublicLive(req, url, env, origin) {
  const token = safeStr(url.searchParams.get("token"), 128);
  if (!token) throw new Error("token is required");

  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const explicitScope = requiredScope;
  const link = await kvGetJson(env.FLUXIDI_TRACKING, scopedPublicBookingKey(explicitScope, token));
  if (!link || !link.booking_id) throw new Error("Invalid token");
  if (!recordMatchesTenantCompanyScope(link, explicitScope)) {
    throw new Error("invalid token scope");
  }

  const linkScope = explicitScope;
  const booking_id = safeStr(link.booking_id, 96);
  if (!booking_id) throw new Error("Invalid token");
  const session_id_from_link = safeStr(link.session_id ?? link.sessionId, 128);

  const limit = Math.min(1200, Math.max(1, Number(url.searchParams.get("limit") || 300)));
  const map = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedBookingSessionKey(linkScope, booking_id),
  );
  if (map && !recordMatchesTenantCompanyScope(map, linkScope)) {
    throw new Error("invalid booking scope");
  }
  const resolvedSessionId = safeStr(map?.session_id ?? map?.sessionId ?? session_id_from_link, 128);
  if (!resolvedSessionId) throw new Error("Unknown booking_id");
  const session = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedSessionKey(linkScope, resolvedSessionId),
  );
  if (!session) throw new Error("Unknown booking_id");
  if (!recordMatchesTenantCompanyScope(session, linkScope)) throw new Error("invalid session scope");
  const last = await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedPingLastKey(linkScope, resolvedSessionId),
  );
  const points = Array.isArray(session?.points) ? session.points : [];
  const sliced = points.slice(Math.max(0, points.length - limit));

  return withCors(
    json(
      {
        ok: true,
        booking_id,
        session_id: resolvedSessionId,
        status: session?.status ?? null,
        last_ping: last ?? null,
        points: sliced,
      },
      { status: 200 }
    ),
    origin
  );
}

// POST /track/route  { from, to, profile? }
async function handleRoute(req, url, env, origin) {
  requireAdmin(req, url, env);

  const token = requireMapbox(env);

  const body = await readJson(req);
  const fromQ = safeStr(body["from"], 256);
  const toQ = safeStr(body["to"], 256);
  const profile = safeStr(body["profile"], 32) ?? "driving";

  if (!fromQ || !toQ) throw new Error("from/to are required");

  // Geocode both sides
  const from = await mapboxGeocode(token, fromQ);
  const to = await mapboxGeocode(token, toQ);

  // Directions
  const dir = await mapboxDirections(token, from, to, profile);

  return withCors(
    json(
      {
        ok: true,
        from: { query: fromQ, ...from },
        to: { query: toQ, ...to },
        profile,
        distance_m: dir.distance_m,
        duration_s: dir.duration_s,
        geometry: dir.geometry,
      },
      { status: 200 }
    ),
    origin
  );
}

// -------------------------------
// Housekeeping endpoints
// -------------------------------
async function handleDeleteBooking(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const booking_id = safeStr(body["booking_id"], 64);
  if (!booking_id) throw new Error("booking_id is required");

  const scopedIndexStorageKey = scopedBookingIndexKey(scope);
  const scopedIndex = (await kvGetJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey)) ?? [];
  const currentIndex = Array.isArray(scopedIndex) ? scopedIndex : [];

  const mapKey = scopedBookingSessionKey(scope, booking_id);
  const map = await kvGetJson(env.FLUXIDI_TRACKING, mapKey);

  if (map && !recordMatchesTenantCompanyScope(map, scope)) {
    throw new Error("invalid booking scope");
  }

  if (!map) {
    const next = currentIndex.filter((x) => x !== booking_id);
    if (next.length !== currentIndex.length || !Array.isArray(scopedIndex)) {
      await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, next, TTL_INDEX);
    }

    return withCors(
      json(
        {
          ok: true,
          deleted: false,
          booking_id,
          scope_mode: "scoped",
          note: "No scoped mapping found; removed from scoped index if present.",
        },
        { status: 200 },
      ),
      origin
    );
  }

  const session_id = safeStr(map.session_id ?? map.sessionId, 128);
  const public_token = safeStr(map.public_token ?? "", 128) || null;

  if (session_id) {
    const session = await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope, session_id));
    if (session && !recordMatchesTenantCompanyScope(session, scope)) {
      throw new Error("invalid session scope");
    }
  }

  await kvDel(env.FLUXIDI_TRACKING, mapKey);
  if (session_id) {
    await kvDel(env.FLUXIDI_TRACKING, scopedSessionKey(scope, session_id));
    await kvDel(env.FLUXIDI_TRACKING, scopedPingLastKey(scope, session_id));
  }
  if (public_token) {
    await kvDel(env.FLUXIDI_TRACKING, scopedPublicBookingKey(scope, public_token));
  }

  const next = currentIndex.filter((x) => x !== booking_id);
  if (next.length !== currentIndex.length || !Array.isArray(scopedIndex)) {
    await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, next, TTL_INDEX);
  }

  return withCors(
    json(
      {
        ok: true,
        deleted: true,
        booking_id,
        session_id,
        public_token,
        scope_mode: "scoped",
      },
      { status: 200 },
    ),
    origin
  );
}

async function handleClearBookings(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const scopedIndexStorageKey = scopedBookingIndexKey(scope);
  await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, [], TTL_INDEX);
  return withCors(
    json({ ok: true, cleared: true, what: "booking_index", scope_mode: "scoped" }, { status: 200 }),
    origin,
  );
}

async function handlePurgeOrphans(req, url, env, origin) {
  requireAdmin(req, url, env);
  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;

  const scopedIndexStorageKey = scopedBookingIndexKey(scope);
  const idx = (await kvGetJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey)) ?? [];
  const cleaned = [];

  for (const rawBookingId of idx) {
    const booking_id = safeStr(rawBookingId, 128);
    if (!booking_id) continue;
    const map = await kvGetJson(env.FLUXIDI_TRACKING, scopedBookingSessionKey(scope, booking_id));
    if (!map) continue;
    if (!recordMatchesTenantCompanyScope(map, scope)) continue;
    const session_id = safeStr(map.session_id ?? map.sessionId, 128);
    if (!session_id) continue;
    const session = await kvGetJson(env.FLUXIDI_TRACKING, scopedSessionKey(scope, session_id));
    if (!session) continue;
    if (!recordMatchesTenantCompanyScope(session, scope)) continue;
    cleaned.push(booking_id);
  }

  await kvPutJson(env.FLUXIDI_TRACKING, scopedIndexStorageKey, cleaned, TTL_INDEX);

  return withCors(
    json(
      {
        ok: true,
        before: Array.isArray(idx) ? idx.length : 0,
        after: cleaned.length,
        removed: (Array.isArray(idx) ? idx.length : 0) - cleaned.length,
        scope_mode: "scoped",
      },
      { status: 200 },
    ),
    origin,
  );
}

// -------------------------------
// Router
// -------------------------------
export default {
  async fetch(req, env, ctx) {
    const origin = getOrigin(req);
    const url = new URL(req.url);

    if (req.method === "OPTIONS") {
      return withCors(new Response(null, { status: 204 }), origin);
    }

    try {
      if (req.method === "GET" && url.pathname === "/health") return await handleHealth(req, env, origin);

      // direct trips
      if (req.method === "GET" && url.pathname === "/admin/dashboard/trip-kpis") return await handleDashboardTripKpis(req, url, env, origin);
      if ((req.method === "POST" || req.method === "GET") && url.pathname === "/admin/dashboard/trip-kpis/reconcile") {
        return await handleDashboardTripKpisReconcile(req, url, env, origin);
      }
      // DEV/TEST ONLY. Must be disabled or protected before production.
      if (req.method === "GET" && url.pathname === "/admin/dev/dashboard-kpis/reset/dry-run") {
        return await handleDevDashboardKpisReset(req, url, env, origin, { forceDryRun: true });
      }
      if (req.method === "POST" && url.pathname === "/admin/dev/dashboard-kpis/reset") {
        return await handleDevDashboardKpisReset(req, url, env, origin);
      }
      if (req.method === "GET" && url.pathname === "/trips/history") return await handleTripsHistory(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trips/archive") return await handleArchiveTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/start-direct") return await handleStartDirectTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/record-planned-stop") return await handleRecordPlannedStopTrip(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/trip/wait-start") return await handleWaitStartTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/wait-end") return await handleWaitEndTrip(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/stop") return await handleStopTrip(req, url, env, origin, ctx);
      if (req.method === "POST" && url.pathname === "/trip/payment") return await handleTripPayment(req, url, env, origin, ctx);

      // core
      if (req.method === "POST" && url.pathname === "/track/session/start") return await handleStart(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/ping") return await handlePing(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/session/stop") return await handleStop(req, url, env, origin);

      if (req.method === "GET" && url.pathname === "/track/bookings") return await handleBookings(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/booking") return await handleBookingDetails(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/live") return await handleLive(req, url, env, origin);
      if (req.method === "GET" && url.pathname === "/track/public/live") return await handlePublicLive(req, url, env, origin);

      // NEW: route
      if (req.method === "POST" && url.pathname === "/track/route") return await handleRoute(req, url, env, origin);

      // housekeeping
      if (req.method === "POST" && url.pathname === "/track/booking/delete") return await handleDeleteBooking(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/bookings/clear") return await handleClearBookings(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/track/bookings/purge_orphans") return await handlePurgeOrphans(req, url, env, origin);

      return withCors(json({ ok: false, error: "Not Found", path: url.pathname }, { status: 404 }), origin);
    } catch (err) {
      const msg = typeof err?.message === "string" ? err.message : "Unknown error";
      const status =
        msg === "Unauthorized"
          ? 401
          : msg.includes("required") || msg.includes("invalid") || msg.includes("Expected")
          ? 400
          : msg.includes("Unknown") || msg.includes("Not Found") || msg.includes("Invalid") || msg.includes("no result")
          ? 404
          : 500;
      return withCors(json({ ok: false, error: msg }, { status }), origin);
    }
  },
};
