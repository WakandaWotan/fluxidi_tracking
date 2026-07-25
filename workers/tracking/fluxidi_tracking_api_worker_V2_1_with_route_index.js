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
const PUBLIC_DRIVER_SESSION_KEY_PREFIX = "public_driver:session:";
const PUBLIC_DRIVER_SESSION_KEY_SUFFIX = ":v1";

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

function publicDriverSessionKey(tokenHash) {
  const safeHash = safeStr(tokenHash, 200);
  if (!safeHash) return "";
  return `${PUBLIC_DRIVER_SESSION_KEY_PREFIX}${safeHash.toLowerCase()}${PUBLIC_DRIVER_SESSION_KEY_SUFFIX}`;
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

async function loadPublicDriverSessionFromRequest(req, env) {
  if (!env?.BOOKING_KV) return null;
  const token = getBearerToken(req);
  if (!token) return null;
  const tokenHash = await hashCompanySessionToken(token);
  if (!tokenHash) return null;
  const key = publicDriverSessionKey(tokenHash);
  if (!key) return null;
  const record = await env.BOOKING_KV.get(key, { type: "json" });
  if (!record || typeof record !== "object" || Array.isArray(record)) return null;
  const role = (safeStr(record.role, 24) ?? "").toLowerCase();
  if (role !== "driver") return null;
  const tenantId = safeStr(record.tenant_id ?? record.tenantId, 80);
  const companyId = safeStr(record.company_id ?? record.companyId, 80);
  const driverId = safeStr(record.driver_id ?? record.driverId, 96);
  const expiresAt = safeStr(record.expires_at ?? record.expiresAt, 80);
  const expiresAtMs = Date.parse(expiresAt || "");
  if (!Number.isFinite(expiresAtMs) || Date.now() >= expiresAtMs) {
    try {
      await env.BOOKING_KV.delete(key);
    } catch (_) {}
    return null;
  }
  if (!tenantId || !companyId || !driverId) return null;
  return {
    tenant_id: tenantId,
    company_id: companyId,
    driver_id: driverId,
  };
}

function maskScopeForTripKpiLog(value) {
  const text = safeStr(value, 80) ?? "";
  if (!text) return "-";
  if (text.length <= 4) return `…${text.substring(text.length - 1)}`;
  return `${text.substring(0, 2)}…${text.substring(text.length - 2)}`;
}

// Extract a caller-supplied driver_id from body/query/header candidates.
// Compatibility inputs only — the authoritative value is the driver-session record.
function _extractCallerSuppliedDriverId(req, url, body = null) {
  const search = url?.searchParams;
  return (
    safeStr(
      body?.driver_id ??
        body?.driverId ??
        body?.actor_driver_id ??
        body?.actorDriverId ??
        search?.get?.("driver_id") ??
        search?.get?.("driverId") ??
        req?.headers?.get?.("x-fluxidi-driver-id") ??
        req?.headers?.get?.("x-driver-id"),
      96,
    ) ?? ""
  );
}

// SECURITY-REMOVE-CLIENT-ADMIN-TOKEN-P0-1
// Authoritative auth for driver-initiated tracking operations.
//
// Preferred path: `Authorization: Bearer <driver session>` bound in KV under
// `public_driver:session:{sha256(token)}:v1`. tenant/company/driver are derived
// from that record and every caller-supplied scope field must exactly match or
// be omitted (fail closed with 403 on conflict).
//
// Dual auth: `ADMIN_TOKEN` is retained for platform-operator / internal
// server-to-server callers. Flutter must not send it after this migration.
async function requireDriverSessionOrAdminForScope(
  req,
  url,
  env,
  { body = null, routeLabel = "" } = {},
) {
  const origin = getOrigin(req);
  if (hasValidAdminToken(req, url, env)) {
    if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=admin_token`);
    return { ok: true, auth_mode: "admin_token", driver_session: null };
  }
  const driverSession = await loadPublicDriverSessionFromRequest(req, env);
  if (!driverSession) {
    if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=none result=unauthorized`);
    return {
      ok: false,
      response: withCors(
        json({ ok: false, error: "unauthorized" }, { status: 401 }),
        origin,
      ),
    };
  }
  const clientScope = extractScopeFromQueryAndBody(url, body);
  if (clientScope?.tenant_id && clientScope.tenant_id !== driverSession.tenant_id) {
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session result=forbidden reason=tenant_mismatch`,
      );
    }
    return {
      ok: false,
      response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
    };
  }
  if (clientScope?.company_id && clientScope.company_id !== driverSession.company_id) {
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session result=forbidden reason=company_mismatch`,
      );
    }
    return {
      ok: false,
      response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
    };
  }
  const clientDriverId = _extractCallerSuppliedDriverId(req, url, body);
  if (clientDriverId && clientDriverId !== driverSession.driver_id) {
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session result=forbidden reason=driver_mismatch`,
      );
    }
    return {
      ok: false,
      response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
    };
  }
  if (routeLabel) {
    console.log(
      `[${routeLabel}][AUTH] auth_mode=driver_session tenant=${maskScopeForTripKpiLog(driverSession.tenant_id)} company=${maskScopeForTripKpiLog(driverSession.company_id)} driver=${maskScopeForTripKpiLog(driverSession.driver_id)}`,
    );
  }
  return { ok: true, auth_mode: "driver_session", driver_session: driverSession };
}

// Merge session-derived tenant/company/driver into a request body so that
// downstream helpers (parseRequiredTenantCompanyScope, actor resolvers) see
// authoritative values without needing bespoke plumbing.
function applyDriverSessionToBody(body, driverSession) {
  if (!driverSession) return body;
  const out =
    body && typeof body === "object" && !Array.isArray(body) ? { ...body } : {};
  out.tenant_id = driverSession.tenant_id;
  out.tenantId = driverSession.tenant_id;
  out.company_id = driverSession.company_id;
  out.companyId = driverSession.company_id;
  if (!safeStr(out.driver_id, 96) && !safeStr(out.driverId, 96)) {
    out.driver_id = driverSession.driver_id;
    out.driverId = driverSession.driver_id;
  }
  if (!safeStr(out.actor_role, 32) && !safeStr(out.actorRole, 32)) {
    out.actor_role = "driver";
  }
  if (!safeStr(out.actor_driver_id, 96) && !safeStr(out.actorDriverId, 96)) {
    out.actor_driver_id = driverSession.driver_id;
    out.actorDriverId = driverSession.driver_id;
  }
  return out;
}

// Broader helper for routes callable by driver OR company OR admin
// (e.g. /track/booking, /track/bookings — driver in-app + company-preview UI).
async function requireDriverOrCompanyOrAdminForScope(
  req,
  url,
  env,
  { body = null, routeLabel = "" } = {},
) {
  const origin = getOrigin(req);
  if (hasValidAdminToken(req, url, env)) {
    if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=admin_token`);
    return { ok: true, auth_mode: "admin_token", driver_session: null, company_session: null };
  }
  const clientScope = extractScopeFromQueryAndBody(url, body);
  const companySession = await loadCompanySessionFromRequest(req, env);
  if (companySession) {
    if (clientScope?.tenant_id && clientScope.tenant_id !== companySession.tenant_id) {
      return {
        ok: false,
        response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
      };
    }
    if (clientScope?.company_id && clientScope.company_id !== companySession.company_id) {
      return {
        ok: false,
        response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
      };
    }
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=company_session tenant=${maskScopeForTripKpiLog(companySession.tenant_id)} company=${maskScopeForTripKpiLog(companySession.company_id)}`,
      );
    }
    return {
      ok: true,
      auth_mode: "company_session",
      driver_session: null,
      company_session: companySession,
    };
  }
  const driverSession = await loadPublicDriverSessionFromRequest(req, env);
  if (driverSession) {
    if (clientScope?.tenant_id && clientScope.tenant_id !== driverSession.tenant_id) {
      return {
        ok: false,
        response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
      };
    }
    if (clientScope?.company_id && clientScope.company_id !== driverSession.company_id) {
      return {
        ok: false,
        response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
      };
    }
    const clientDriverId = _extractCallerSuppliedDriverId(req, url, body);
    if (clientDriverId && clientDriverId !== driverSession.driver_id) {
      return {
        ok: false,
        response: withCors(json({ ok: false, error: "forbidden" }, { status: 403 }), origin),
      };
    }
    if (routeLabel) {
      console.log(
        `[${routeLabel}][AUTH] auth_mode=driver_session tenant=${maskScopeForTripKpiLog(driverSession.tenant_id)} company=${maskScopeForTripKpiLog(driverSession.company_id)} driver=${maskScopeForTripKpiLog(driverSession.driver_id)}`,
      );
    }
    return {
      ok: true,
      auth_mode: "driver_session",
      driver_session: driverSession,
      company_session: null,
    };
  }
  if (routeLabel) console.log(`[${routeLabel}][AUTH] auth_mode=none result=unauthorized`);
  return {
    ok: false,
    response: withCors(json({ ok: false, error: "unauthorized" }, { status: 401 }), origin),
  };
}

function _pickFinanceMonthCents(financeMonth, ...keys) {
  const obj = financeMonth && typeof financeMonth === "object" && !Array.isArray(financeMonth) ? financeMonth : {};
  for (const key of keys) {
    const n = Number(obj[key]);
    if (Number.isFinite(n)) return Math.max(0, Math.round(n));
  }
  return null;
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

async function resolveTripsHistoryAuth(req, url, env, scope, origin) {
  const tenantMasked = maskScopeForTripKpiLog(scope.tenant_id);
  const companyMasked = maskScopeForTripKpiLog(scope.company_id);
  const requestedDriverId = safeStr(url.searchParams.get("driver_id"), 96);

  if (hasValidAdminToken(req, url, env)) {
    console.log(
      `[TRIPS_HISTORY][AUTH] auth_mode=admin tenant=${tenantMasked} company=${companyMasked} driver=${requestedDriverId ? maskScopeForTripKpiLog(requestedDriverId) : "-"}`,
    );
    return { ok: true, auth_mode: "admin", forced_driver_id: null };
  }

  const companySession = await loadCompanySessionFromRequest(req, env);
  if (companySession) {
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
      `[TRIPS_HISTORY][AUTH] auth_mode=company_session tenant=${tenantMasked} company=${companyMasked} driver=${requestedDriverId ? maskScopeForTripKpiLog(requestedDriverId) : "-"}`,
    );
    return { ok: true, auth_mode: "company_session", forced_driver_id: null };
  }

  const driverSession = await loadPublicDriverSessionFromRequest(req, env);
  if (driverSession) {
    if (
      scope.tenant_id !== driverSession.tenant_id ||
      scope.company_id !== driverSession.company_id
    ) {
      return {
        ok: false,
        response: withCors(
          json({ ok: false, error: "forbidden" }, { status: 403 }),
          origin,
        ),
      };
    }
    if (requestedDriverId && requestedDriverId !== driverSession.driver_id) {
      console.log(
        `[TRIPS_HISTORY][AUTH] auth_mode=driver_session tenant=${tenantMasked} company=${companyMasked} driver=${maskScopeForTripKpiLog(requestedDriverId)} result=forbidden_driver_mismatch`,
      );
      return {
        ok: false,
        response: withCors(
          json({ ok: false, error: "forbidden" }, { status: 403 }),
          origin,
        ),
      };
    }
    console.log(
      `[TRIPS_HISTORY][AUTH] auth_mode=driver_session tenant=${tenantMasked} company=${companyMasked} driver=${maskScopeForTripKpiLog(driverSession.driver_id)}`,
    );
    return {
      ok: true,
      auth_mode: "driver_session",
      forced_driver_id: driverSession.driver_id,
    };
  }

  throw new Error("Unauthorized");
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

function _complianceLocationFromPoint(point) {
  if (!point || typeof point !== "object" || Array.isArray(point)) return null;
  const label = safeStr(point.label ?? point.address ?? point.text, 256) ?? null;
  const lat = Number.isFinite(Number(point.lat)) ? Number(point.lat) : null;
  const lng = Number.isFinite(Number(point.lon ?? point.lng)) ? Number(point.lon ?? point.lng) : null;
  if (!label && lat === null && lng === null) return null;
  return { label, lat, lng };
}

function buildDirectTripStartComplianceEvent(trip, startedAt, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantId =
    normalizedScope?.tenant_id ??
    safeStr(trip?.tenant_id ?? trip?.tenantId ?? trip?.company_id ?? trip?.companyId, 96);
  const companyId =
    normalizedScope?.company_id ?? safeStr(trip?.company_id ?? trip?.companyId, 96);
  if (!tenantId || !companyId) {
    console.log("[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope");
    return null;
  }

  const pickup = _complianceLocationFromPoint(trip?.origin);
  const dropoff = _complianceLocationFromPoint(trip?.destination);
  const eventAt = safeStr(startedAt, 64) ?? safeStr(trip?.started_at ?? trip?.startedAt, 64) ?? nowIso();

  return {
    event_type: "ride_start",
    tenant_id: tenantId,
    company_id: companyId,
    trip_id: safeStr(trip?.trip_id ?? trip?.tripId, 128) ?? undefined,
    session_id: safeStr(trip?.session_id ?? trip?.sessionId, 128) ?? undefined,
    receipt_reference: safeStr(trip?.receipt_reference ?? trip?.receiptReference, 128) ?? undefined,
    ride_type: "direct",
    lifecycle_status: "started",
    timestamps: {
      event_at_utc: eventAt,
      started_at_utc: eventAt,
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
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/trip/start-direct",
      backend_confirmed: true,
      validation_state: "exportable",
    },
  };
}

function buildPlannedSessionStartComplianceEvent(session, body, startedAt, canonicalScope = null) {
  const normalizedScope = normalizeTenantCompanyScope(canonicalScope);
  if (canonicalScope && (!normalizedScope?.tenant_id || !normalizedScope?.company_id)) {
    return null;
  }
  const tenantId =
    normalizedScope?.tenant_id ??
    safeStr(
      session?.tenant_id ??
        session?.tenantId ??
        session?.owner_tenant_id ??
        body?.tenant_id ??
        body?.tenantId,
      96,
    );
  const companyId =
    normalizedScope?.company_id ??
    safeStr(
      session?.company_id ??
        session?.companyId ??
        session?.owner_company_id ??
        body?.company_id ??
        body?.companyId,
      96,
    );
  if (!tenantId || !companyId) {
    console.log("[COMPLIANCE][SKIP_SCOPE] source=tracking reason=missing_tenant_company_scope");
    return null;
  }

  const originPoint =
    _complianceLocationFromPoint(body?.origin) ??
    _complianceLocationFromPoint(session?.origin) ??
    (safeStr(session?.pickup ?? body?.pickup, 256)
      ? { label: safeStr(session?.pickup ?? body?.pickup, 256), lat: null, lng: null }
      : null);
  const dropoffLabel = safeStr(session?.dropoff ?? body?.dropoff, 256);
  const dropoff = dropoffLabel ? { label: dropoffLabel, lat: null, lng: null } : null;
  const eventAt =
    safeStr(startedAt, 64) ??
    safeStr(session?.started_at ?? session?.startedAt ?? session?.created_at, 64) ??
    nowIso();

  return {
    event_type: "ride_start",
    tenant_id: tenantId,
    company_id: companyId,
    booking_id: safeStr(session?.booking_id ?? session?.bookingId ?? body?.booking_id, 128) ?? undefined,
    session_id: safeStr(session?.session_id ?? session?.sessionId, 128) ?? undefined,
    ride_type: "planned",
    lifecycle_status: "started",
    timestamps: {
      event_at_utc: eventAt,
      started_at_utc: eventAt,
    },
    driver: {
      driver_id: safeStr(
        session?.driver_id ??
          session?.driverId ??
          session?.owner_driver_id ??
          body?.driver_id ??
          body?.driverId,
        96,
      ) ?? null,
    },
    vehicle: {
      vehicle_id: safeStr(
        session?.vehicle_id ??
          session?.vehicleId ??
          session?.owner_vehicle_id ??
          body?.vehicle_id ??
          body?.vehicleId,
        96,
      ) ?? null,
    },
    locations: {
      pickup: originPoint,
      dropoff,
    },
    provenance: {
      producer: "tracking_worker",
      source_endpoint: "/track/session/start",
      backend_confirmed: true,
      validation_state: "exportable",
    },
  };
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

// FARE-ROUNDING-CENTRAL-0_10-1 — canonical Fluxidi final fare rounding.
// Mirrors workers/shared/fluxidi_fare_rounding.mjs (the documented, node-tested
// source of truth). Inlined here because this worker is deployed as a single
// self-contained file. Policy: round the definitive customer total to the
// nearest €0.10, half-up at exactly €0.05, applied EXACTLY ONCE at finalization,
// using integer cents (no floating-point drift).
//   - 0 stays 0;
//   - null/undefined/NaN/Infinity returns null (never silently 0);
//   - negative amounts (refunds) are not treated as a ride price -> null.
function roundFareCentsToNearestTenCents(rawCents) {
  if (rawCents === null || rawCents === undefined) return null;
  const value = Number(rawCents);
  if (!Number.isFinite(value)) return null;
  if (value === 0) return 0;
  if (value < 0) return null;
  const cents = Math.round(value);
  if (cents === 0) return 0;
  return Math.floor((cents + 5) / 10) * 10;
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

  // FARE-ROUNDING-CENTRAL-0_10-1: this is the definitive street-ride
  // finalization. Round the customer-facing total (incl VAT) to the nearest
  // €0.10 EXACTLY ONCE here, then derive the VAT split from the rounded total
  // so total_eur / price_incl_vat / price_ex_vat / price_vat are internally
  // consistent and every downstream surface reads the same rounded amount.
  const rawInclCents = Math.round(priceInclVat * 100);
  const roundedInclCents = roundFareCentsToNearestTenCents(rawInclCents);
  const finalInclVat =
    roundedInclCents === null ? money2Num(priceInclVat) : roundedInclCents / 100;
  let finalExVat;
  let finalVat;
  if (hasVatMeta && vatRate > 0) {
    finalExVat = money2Num(finalInclVat / (1 + vatRate));
    finalVat = money2Num(finalInclVat - finalExVat);
  } else {
    finalExVat = finalInclVat;
    finalVat = 0;
  }
  console.log(
    `[FARE_ROUNDING] phase=finalize source=street rawCents=${rawInclCents} roundedCents=${
      roundedInclCents === null ? "null" : roundedInclCents
    } alreadyFinalized=false`,
  );

  return {
    km_total: kmTotal,
    wait_seconds_total: waitSecondsTotal,
    wait_minutes: money2Num(waitMinutes),
    total_eur: finalInclVat,
    price_ex_vat: finalExVat,
    price_vat: finalVat,
    price_incl_vat: finalInclVat,
    vat_rate: vatRate,
    vat_mode: vatMode,
    currency: safeStr(pricing.currency ?? "EUR", 8) ?? "EUR",
    fare_rounding_policy: "nearest_ten_cents_half_up",
  };
}

// STREET-RIDE-DURABLE-COMPLETION-2: inlined mirror of the tested reference
// workers/tracking/modules/direct_booking_finalize.mjs (single-file Cloudflare
// deploy cannot import). If that module changes, this mirror must be updated in
// lockstep; the module's node tests are the source of truth.
const DIRECT_BOOKING_FINALIZE_STATE = { COMPLETED: "completed", PENDING: "pending" };
const DIRECT_RECONCILE_REASON = {
  REPAIRABLE: "repairable",
  ALREADY_COMPLETED: "already_completed",
  MISSING_TRIP: "skipped_missing_trip",
  NOT_STREET_DIRECT: "skipped_not_street_direct",
  MISSING_BOOKING_ID: "skipped_missing_trip",
  NON_TERMINAL: "skipped_non_terminal",
  MISSING_FARE: "skipped_missing_fare",
};
function _dbfStr(v, max = 200) {
  if (v === null || v === undefined) return "";
  const s = String(v).trim();
  return max > 0 ? s.slice(0, max) : s;
}
function _dbfNumOrNull(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
function isStreetDirectTrip(trip) {
  if (!trip || typeof trip !== "object") return false;
  const kind = _dbfStr(trip.kind).toLowerCase();
  const source = _dbfStr(trip.source).toLowerCase();
  return kind === "direct" || source === "street_ride";
}
function directTripIsTerminal(trip) {
  if (!trip || typeof trip !== "object") return false;
  const status = _dbfStr(trip.status).toLowerCase();
  if (status === "stopped" || status === "completed" || status === "done") return true;
  return _dbfStr(trip.stopped_at).length > 0;
}
function directBookingIdFromTrip(trip) {
  if (!trip || typeof trip !== "object") return "";
  return _dbfStr(trip.booking_id ?? trip.bookingId, 160);
}
function authoritativeTripFareCents(trip) {
  if (!trip || typeof trip !== "object") return null;
  for (const raw of [trip.price_incl_vat, trip.total_eur]) {
    const n = _dbfNumOrNull(raw);
    if (n !== null && n >= 0) return Math.round(n * 100);
  }
  return null;
}
function tripHasAuthoritativeFare(trip) {
  return authoritativeTripFareCents(trip) !== null;
}
function tripReconcileEligibility(trip) {
  if (!trip || typeof trip !== "object") return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_TRIP };
  if (!isStreetDirectTrip(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.NOT_STREET_DIRECT };
  if (!directBookingIdFromTrip(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_BOOKING_ID };
  if (!directTripIsTerminal(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.NON_TERMINAL };
  if (!tripHasAuthoritativeFare(trip)) return { ok: false, reason: DIRECT_RECONCILE_REASON.MISSING_FARE };
  return { ok: true, reason: DIRECT_RECONCILE_REASON.REPAIRABLE };
}
function bookingAlreadyFinalized(trip) {
  return _dbfStr(trip?.booking_finalize_state).toLowerCase() === DIRECT_BOOKING_FINALIZE_STATE.COMPLETED;
}
function buildFinalizePayloadFromTrip(trip, scope) {
  return {
    tenant_id: _dbfStr(scope?.tenant_id, 80),
    company_id: _dbfStr(scope?.company_id, 80),
    booking_id: directBookingIdFromTrip(trip),
    trip_id: _dbfStr(trip?.trip_id, 160) || null,
    stopped_at: _dbfStr(trip?.stopped_at, 80) || null,
    total_eur: _dbfNumOrNull(trip?.price_incl_vat ?? trip?.total_eur),
    price_ex_vat: _dbfNumOrNull(trip?.price_ex_vat),
    price_vat: _dbfNumOrNull(trip?.price_vat),
    vat_rate_percent: _dbfNumOrNull(trip?.vat_rate),
    currency: _dbfStr(trip?.currency ?? trip?.pricing_snapshot?.currency, 8) || "EUR",
    source: "street_ride_stop",
  };
}
function deriveFinalizeStateFromResult(res) {
  return res && res.ok === true ? DIRECT_BOOKING_FINALIZE_STATE.COMPLETED : DIRECT_BOOKING_FINALIZE_STATE.PENDING;
}
function finalizeErrorCodeFromResult(res) {
  if (res && res.ok === true) return null;
  return _dbfStr(res?.error, 120) || "unknown";
}
function applyBookingFinalizeAttempt(trip, { state, errorCode = null, nowIso, attemptDelta = 1 } = {}) {
  if (!trip || typeof trip !== "object") return trip;
  const completed = DIRECT_BOOKING_FINALIZE_STATE.COMPLETED;
  const nextState = bookingAlreadyFinalized(trip) ? completed : state;
  trip.booking_finalize_state = nextState;
  trip.booking_finalize_attempted_at = _dbfStr(nowIso, 80) || trip.booking_finalize_attempted_at || null;
  const prevCount = Number(trip.booking_finalize_attempt_count);
  trip.booking_finalize_attempt_count = (Number.isFinite(prevCount) ? prevCount : 0) + (Number(attemptDelta) || 0);
  trip.booking_finalize_last_error_code = nextState === completed ? null : errorCode || null;
  return trip;
}
function safeBookingFinalizeResponseFields(trip) {
  const completed = bookingAlreadyFinalized(trip);
  return {
    booking_id: directBookingIdFromTrip(trip) || null,
    booking_finalize_state: completed ? DIRECT_BOOKING_FINALIZE_STATE.COMPLETED : DIRECT_BOOKING_FINALIZE_STATE.PENDING,
    booking_finalized: completed,
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

// BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 commit 2 / 2.
//
// Inline copies of the pure KPI read-path helpers from
// `workers/shared/kpi_read_path.mjs`. Kept in sync with that module — see
// the tests there for the executable spec. Inlined rather than imported so
// this worker file (which has no top-level imports today) does not gain a
// new module boundary in a single-file deploy.
const _KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS = 200;

function _tripKpiGlobalStructurallyValidLocal(global) {
  if (!global || typeof global !== 'object' || Array.isArray(global)) {
    return false;
  }
  const completed = Number(global.completed_rides_count);
  const unpaid = Number(global.unpaid_completed_rides_count);
  return (
    Number.isFinite(completed) &&
    completed >= 0 &&
    Number.isFinite(unpaid) &&
    unpaid >= 0
  );
}

function _tripKpiMonthStructurallyValidLocal(month) {
  if (!month || typeof month !== 'object' || Array.isArray(month)) {
    return false;
  }
  const paid = Number(month.monthly_paid_rides_count);
  const income = Number(month.monthly_income_cents);
  return (
    Number.isFinite(paid) &&
    paid >= 0 &&
    Number.isFinite(income) &&
    income >= 0
  );
}

function _tripKpiAggregatesStructurallyValidLocal(global, month) {
  return (
    _tripKpiGlobalStructurallyValidLocal(global) &&
    _tripKpiMonthStructurallyValidLocal(month)
  );
}

function _formatKpiReadDiagnosticLocal({
  endpoint,
  source,
  reconcile,
  elapsedMs,
  status,
}) {
  const safeElapsed = Number.isFinite(Number(elapsedMs))
    ? Math.max(0, Math.min(60000, Math.round(Number(elapsedMs))))
    : 0;
  const safeStatus = Number.isFinite(Number(status))
    ? Math.max(100, Math.min(599, Math.round(Number(status))))
    : 500;
  return (
    `[KPI_READ] endpoint=${endpoint} source=${source} ` +
    `reconcile=${reconcile} elapsed_ms=${safeElapsed} status=${safeStatus}`
  );
}

async function _reconcileTripKpiMissingAmountForMonthBestEffort(
  env,
  scope,
  month,
  { includeDebugRows = false, debugRowLimit = 50, maxScanned = 0 } = {},
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
  // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: bounded fallback cap. When called
  // from the dashboard GET path, `maxScanned` is set to a small ceiling
  // (see `_KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS`) so a cold tenant with
  // many historical contributions cannot blow past the 12 s client timeout.
  // `maxScanned <= 0` means "no cap" for legacy callers (rebuild, cron,
  // explicit repair paths).
  const scanCap = Number.isFinite(Number(maxScanned)) && Number(maxScanned) > 0
    ? Math.max(1, Math.round(Number(maxScanned)))
    : 0;
  let scanBudgetExceeded = false;

  let cursor = undefined;
  do {
    if (scanCap > 0 && scanned >= scanCap) {
      scanBudgetExceeded = true;
      break;
    }
    const page = await env.FLUXIDI_TRACKING.list({
      prefix: contribPrefix,
      limit: 1000,
      cursor,
    });
    for (const keyMeta of page?.keys || []) {
      if (scanCap > 0 && scanned >= scanCap) {
        scanBudgetExceeded = true;
        break;
      }
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

  // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: if the bounded fallback exceeded
  // its scan budget during the missing-amount pass, do NOT run the second
  // full-recount pass and do NOT overwrite the persisted month aggregate
  // with a partial recount. Return the counters observed so far so the
  // dashboard can render `data_pending`-style diagnostics without
  // corrupting the authoritative aggregate.
  if (scanBudgetExceeded) {
    return {
      trip_kpi_reconcile_scanned: scanned,
      trip_kpi_reconcile_recovered_missing_amount_count: recoveredCount,
      trip_kpi_reconcile_recovered_missing_amount_cents: recoveredCents,
      trip_kpi_reconcile_sum_cents: 0,
      trip_kpi_reconcile_budget_exceeded: true,
      rows,
    };
  }
  // Recompute month aggregate from contrib truth for idempotency.
  let sumCents = 0;
  let sumCount = 0;
  let sumMissingAmount = 0;
  let recomputeBudgetExceeded = false;
  let recomputeScanned = 0;
  cursor = undefined;
  do {
    if (scanCap > 0 && recomputeScanned >= scanCap) {
      recomputeBudgetExceeded = true;
      break;
    }
    const page = await env.FLUXIDI_TRACKING.list({
      prefix: contribPrefix,
      limit: 1000,
      cursor,
    });
    for (const keyMeta of page?.keys || []) {
      if (scanCap > 0 && recomputeScanned >= scanCap) {
        recomputeBudgetExceeded = true;
        break;
      }
      recomputeScanned += 1;
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

  // Same safety net for the recount pass: never overwrite the persisted
  // month aggregate with a partial recount.
  if (recomputeBudgetExceeded) {
    return {
      trip_kpi_reconcile_scanned: scanned,
      trip_kpi_reconcile_recovered_missing_amount_count: recoveredCount,
      trip_kpi_reconcile_recovered_missing_amount_cents: recoveredCents,
      trip_kpi_reconcile_sum_cents: 0,
      trip_kpi_reconcile_budget_exceeded: true,
      rows,
    };
  }

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
  // BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1: normal GET reads the authoritative
  // aggregates directly. Reconciliation only runs when aggregates are
  // absent/malformed OR when the caller explicitly asks for the debug
  // contributor rows. Bounded fallback cap keeps a cold tenant response
  // well below the client 12 s timeout; expensive repair belongs to
  // `/admin/dashboard/trip-kpis/reconcile`.
  const kpiReadStartedAt = Date.now();
  const globalPrimary = (await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardTripKpisKey(normalizedScope),
  )) ?? {};
  const monthPrimary = (await kvGetJson(
    env.FLUXIDI_TRACKING,
    scopedDashboardTripMonthKpisKey(normalizedScope, selectedMonth),
  )) ?? {};
  const aggregatesReady = _tripKpiAggregatesStructurallyValidLocal(
    globalPrimary,
    monthPrimary,
  );
  const shouldReconcile = debugPaidContributorsEnabled || !aggregatesReady;
  const reconcileResult = shouldReconcile
    ? await _reconcileTripKpiMissingAmountForMonthBestEffort(
        env,
        normalizedScope,
        selectedMonth,
        {
          includeDebugRows: debugPaidContributorsEnabled,
          debugRowLimit: 50,
          maxScanned: debugPaidContributorsEnabled
            ? 0
            : _KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS,
        },
      )
    : null;
  const kpiReadSource = aggregatesReady
    ? 'aggregate'
    : reconcileResult?.trip_kpi_reconcile_budget_exceeded
      ? 'data_pending'
      : 'bounded_fallback';
  const kpiReadReconcile = shouldReconcile ? 'bounded' : 'skipped';
  // Re-read month aggregate after a successful reconciliation so the
  // response reflects the freshly-written values.
  const global = globalPrimary && Object.keys(globalPrimary).length > 0
    ? globalPrimary
    : ((await kvGetJson(
        env.FLUXIDI_TRACKING,
        scopedDashboardTripKpisKey(normalizedScope),
      )) ?? {});
  const month = shouldReconcile
    ? ((await kvGetJson(
        env.FLUXIDI_TRACKING,
        scopedDashboardTripMonthKpisKey(normalizedScope, selectedMonth),
      )) ?? monthPrimary ?? {})
    : monthPrimary;
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
  const monthCancelledPaidCents = Number.isFinite(Number(financeMonth.monthly_cancelled_paid_bookings_cents))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_cancelled_paid_bookings_cents)))
    : 0;
  const monthPendingCreditCents = Number.isFinite(Number(financeMonth.monthly_pending_credit_cents))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_pending_credit_cents)))
    : 0;
  const monthCreditedCents = Number.isFinite(Number(financeMonth.monthly_credited_cents))
    ? Math.max(0, Math.round(Number(financeMonth.monthly_credited_cents)))
    : 0;
  const pendingCreditCents = monthPendingCreditCents;
  const creditedCents = monthCreditedCents;
  const bookingFinanceNetCents = _pickFinanceMonthCents(
    financeMonth,
    "monthly_net_revenue_cents",
    "monthly_net_income_cents",
    "booking_finance_monthly_net_revenue_cents",
    "booking_finance_monthly_net_income_cents",
  );
  const bookingFinanceGrossCents =
    _pickFinanceMonthCents(
      financeMonth,
      "monthly_gross_paid_income_cents",
      "monthly_paid_bookings_income_cents",
      "booking_finance_monthly_gross_income_cents",
    ) ?? monthBookingPaidIncomeCents;
  const bookingFinanceCreditedCents =
    _pickFinanceMonthCents(financeMonth, "monthly_credited_cents", "booking_finance_monthly_credited_cents") ??
    creditedCents;
  const bookingFinanceRefundedCents =
    _pickFinanceMonthCents(financeMonth, "monthly_refunded_cents", "booking_finance_monthly_refunded_cents") ?? 0;
  const bookingFinanceRetainedCents =
    _pickFinanceMonthCents(financeMonth, "monthly_retained_cents", "booking_finance_monthly_retained_cents") ?? 0;
  const bookingFinanceAmbiguousManualCents =
    _pickFinanceMonthCents(
      financeMonth,
      "monthly_ambiguous_manual_cents",
      "booking_finance_monthly_ambiguous_manual_cents",
    ) ?? 0;
  const bookingFinanceManualUnresolvedCount =
    _pickFinanceMonthCents(financeMonth, "manual_unresolved_count", "booking_finance_manual_unresolved_count") ?? 0;
  const bookingFinanceNetIncomeCents =
    bookingFinanceNetCents != null
      ? bookingFinanceNetCents
      : Math.max(0, monthBookingPaidIncomeCents - pendingCreditCents - creditedCents);
  // Dashboard revenue source selection:
  //   Prefer completed-paid trip revenue (trip-KPI per-month aggregate)
  //   because it matches `completed_rides_count` 1:1 and cannot include
  //   cancelled/refunded/credited bookings. Booking-finance can include
  //   amounts for bookings whose lifecycle was cancelled after capture, so
  //   it inflates the visible revenue card vs. what a user sees in the
  //   Completed bookings tab. Fall back to booking-finance only when trip
  //   completed revenue is zero or missing, to preserve legacy months and
  //   tenants without trip-KPI materialization.
  const selectedMonthlyIncomeSource =
    monthIncomeCents > 0 ? "completed_trip_kpi" : "booking_finance_fallback";
  const selectedMonthlyIncomeCents =
    selectedMonthlyIncomeSource === "completed_trip_kpi"
      ? monthIncomeCents
      : monthBookingPaidIncomeCents;
  // Dashboard display fields all resolve to the selected source. We do NOT
  // subtract credits here: when the source is completed_trip_kpi the
  // cancelled/credited bookings are already excluded from the trip sum, and
  // when the source is booking_finance_fallback the credit-subtracted view
  // is still available as `booking_finance_net_income_cents` diagnostic.
  const dashboardMonthlyIncomeCents = selectedMonthlyIncomeCents;
  const blendedMonthlyIncomeCents = dashboardMonthlyIncomeCents;
  const grossMonthlyIncomeCents = dashboardMonthlyIncomeCents;
  let netMonthlyIncomeCents = dashboardMonthlyIncomeCents;
  let monthlyNetIncomeCents = dashboardMonthlyIncomeCents;
  let monthlyNetRevenueCents = dashboardMonthlyIncomeCents;
  let selectedNetRevenueSource = selectedMonthlyIncomeSource;
  if (bookingFinanceNetCents != null) {
    netMonthlyIncomeCents = bookingFinanceNetCents;
    monthlyNetIncomeCents = bookingFinanceNetCents;
    monthlyNetRevenueCents = bookingFinanceNetCents;
    selectedNetRevenueSource = "booking_finance_net";
    console.log(
      `[TRIP_KPI][NET_REVENUE_SOURCE] tenant=${maskScopeForTripKpiLog(normalizedScope.tenant_id)} company=${maskScopeForTripKpiLog(normalizedScope.company_id)} month=${selectedMonth} source=booking_finance_net net_cents=${bookingFinanceNetCents} gross_cents=${bookingFinanceGrossCents} credited_cents=${bookingFinanceCreditedCents} refunded_cents=${bookingFinanceRefundedCents}`,
    );
  } else {
    console.log(
      `[TRIP_KPI][NET_REVENUE_SOURCE] tenant=${maskScopeForTripKpiLog(normalizedScope.tenant_id)} company=${maskScopeForTripKpiLog(normalizedScope.company_id)} month=${selectedMonth} source=gross_fallback reason=missing_booking_finance_net`,
    );
  }
  console.log(
    `[DASHBOARD_REVENUE][DISPLAY_SOURCE] tenant=${maskScopeForTripKpiLog(normalizedScope.tenant_id)} company=${maskScopeForTripKpiLog(normalizedScope.company_id)} month=${selectedMonth} source=${selectedMonthlyIncomeSource} trip_cents=${monthIncomeCents} booking_finance_cents=${monthBookingPaidIncomeCents} booking_finance_net_cents=${bookingFinanceNetIncomeCents} selected_cents=${selectedMonthlyIncomeCents}`,
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
    monthly_net_income_cents: monthlyNetIncomeCents,
    monthly_net_income_eur: monthlyNetIncomeCents / 100,
    monthly_net_revenue_cents: monthlyNetRevenueCents,
    monthly_net_revenue_eur: monthlyNetRevenueCents / 100,
    monthly_paid_bookings_count: monthBookingPaidCount,
    monthly_paid_bookings_income_cents: monthBookingPaidIncomeCents,
    monthly_paid_bookings_income_eur: monthBookingPaidIncomeCents / 100,
    trip_monthly_income_cents: monthIncomeCents,
    trip_monthly_income_eur: monthIncomeCents / 100,
    booking_finance_monthly_income_cents: monthBookingPaidIncomeCents,
    booking_finance_monthly_income_eur: monthBookingPaidIncomeCents / 100,
    booking_finance_net_income_cents: bookingFinanceNetIncomeCents,
    booking_finance_net_income_eur: bookingFinanceNetIncomeCents / 100,
    booking_finance_net_monthly_income_cents: bookingFinanceNetCents ?? bookingFinanceNetIncomeCents,
    booking_finance_net_monthly_revenue_cents: bookingFinanceNetCents ?? bookingFinanceNetIncomeCents,
    booking_finance_gross_monthly_income_cents: bookingFinanceGrossCents,
    booking_finance_credited_cents: bookingFinanceCreditedCents,
    booking_finance_refunded_cents: bookingFinanceRefundedCents,
    booking_finance_retained_cents: bookingFinanceRetainedCents,
    booking_finance_ambiguous_manual_cents: bookingFinanceAmbiguousManualCents,
    booking_finance_manual_unresolved_count: bookingFinanceManualUnresolvedCount,
    dashboard_monthly_income_cents: dashboardMonthlyIncomeCents,
    dashboard_monthly_income_eur: dashboardMonthlyIncomeCents / 100,
    selected_monthly_income_source: selectedNetRevenueSource,
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
  console.log(
    _formatKpiReadDiagnosticLocal({
      endpoint: 'trip',
      source: kpiReadSource,
      reconcile: kpiReadReconcile,
      elapsedMs: Date.now() - kpiReadStartedAt,
      status: 200,
    }),
  );
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

// STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1 / 1A / 1B
//
// One physical street ride can be stored as TWO trip records: a `direct` trip
// (the ride source: real fare/distance/times) and a `planned` operational-leg
// shadow (km 0, total_eur 0, leg_type "outbound") projected from the linked
// direct booking. The planned shadow must not appear as a second history row
// nor be counted again.
//
// WHY 1A FAILED (runtime proof rowsBefore==rowsAfter): 1A matched on a shared
// booking_id / planned_<bookingId> name. Live data proved the shadow's
// booking_id / parent_booking_id differ from the direct trip's booking_id
// (pending link at start, later reconciliation, or a canonical id remap), so a
// booking-id/name match can never see the relation.
//
// CANONICAL CONTRACT (1B) — the reliable relation is the TRACKING TRIP ID:
//   * canonical_physical_ride_key: direct -> its own trip_id; planned ->
//     linked_tracking_trip_id (explicit write-time OR BOOKING_KV-resolved),
//     else legacy parent_booking_id/booking_id.
//   * canonical_trip_kind: "direct" | "operational_shadow" | "planned".
//   * is_operational_shadow: true only when a planned leg's tracking-trip link
//     (or, legacy, its booking key) is OWNED by a direct trip.
// Never dedupes on time / amount / address. Unresolved legacy shadows are kept.
//
// Mirrors the tested reference workers/tracking/modules/street_history_canonical.mjs
// (kept inline so this worker stays a single self-contained deploy file).
const STREET_HISTORY_CANONICAL_VERSION = "1B";
function _streetHistoryCanonicalKind(kind) {
  return String(kind ?? "").trim().toLowerCase();
}
function _streetHistoryCanonicalId(id) {
  return String(id ?? "").trim();
}
function _streetHistoryBookingDetails(trip) {
  const d = trip?.booking_details;
  return d && typeof d === "object" && !Array.isArray(d) ? d : {};
}
function _streetHistoryTripIdOf(trip) {
  return _streetHistoryCanonicalId(trip?.trip_id ?? trip?.tripId);
}
function _streetHistoryBookingIdOf(trip) {
  return _streetHistoryCanonicalId(trip?.booking_id ?? trip?.bookingId);
}
function _streetHistoryParentBookingId(trip) {
  const details = _streetHistoryBookingDetails(trip);
  return _streetHistoryCanonicalId(
    trip?.parent_booking_id ??
      trip?.parentBookingId ??
      details.parent_booking_id ??
      details.parentBookingId,
  );
}
function _streetHistoryLinkedTrackingTripId(trip) {
  const details = _streetHistoryBookingDetails(trip);
  return _streetHistoryCanonicalId(
    trip?.linked_tracking_trip_id ??
      trip?.linkedTrackingTripId ??
      details.linked_tracking_trip_id ??
      details.linkedTrackingTripId,
  );
}
function _streetHistoryIsOperationalLeg(trip) {
  const details = _streetHistoryBookingDetails(trip);
  if (details.is_operational_leg === true || details.isOperationalLeg === true) {
    return true;
  }
  if (trip?.is_operational_leg === true || trip?.isOperationalLeg === true) {
    return true;
  }
  const legId = _streetHistoryCanonicalId(
    trip?.leg_id ?? trip?.legId ?? details.leg_id ?? details.legId,
  );
  const legType = _streetHistoryCanonicalId(
    trip?.leg_type ?? trip?.legType ?? details.leg_type ?? details.legType,
  );
  return legId !== "" || legType !== "";
}
function _streetHistoryCanonicalRideKey(trip, resolvedLink) {
  if (_streetHistoryCanonicalKind(trip?.kind) === "direct") {
    return _streetHistoryTripIdOf(trip) || _streetHistoryBookingIdOf(trip);
  }
  const linked =
    _streetHistoryLinkedTrackingTripId(trip) ||
    _streetHistoryCanonicalId(resolvedLink);
  if (linked) return linked;
  return _streetHistoryParentBookingId(trip) || _streetHistoryBookingIdOf(trip);
}
// Non-reversible short fingerprint (FNV-1a 32-bit -> base36) for SAFE
// relational comparison in logs only. Never reversible to a raw id.
function _streetHistoryFingerprint(value) {
  const s = _streetHistoryCanonicalId(value);
  if (!s) return "-";
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i += 1) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return (h >>> 0).toString(36).padStart(7, "0").slice(0, 8);
}
function _streetHistoryTripShape(trip, resolvedLink) {
  const kind = _streetHistoryCanonicalKind(trip?.kind) || "unknown";
  const details = _streetHistoryBookingDetails(trip);
  const bookingId = _streetHistoryBookingIdOf(trip);
  const parentBookingId = _streetHistoryParentBookingId(trip);
  const tripId = _streetHistoryTripIdOf(trip);
  const linked =
    _streetHistoryLinkedTrackingTripId(trip) ||
    _streetHistoryCanonicalId(resolvedLink);
  const canonicalKey = _streetHistoryCanonicalRideKey(trip, resolvedLink);
  const legTypeRaw = _streetHistoryCanonicalId(
    trip?.leg_type ?? trip?.legType ?? details.leg_type ?? details.legType,
  ).toLowerCase();
  const legType =
    legTypeRaw === "outbound" || legTypeRaw === "return" ? legTypeRaw : "none";
  let tripIdShape = "other";
  if (kind === "direct") {
    tripIdShape = "direct";
  } else if (
    (bookingId && tripId === `planned_${bookingId}`) ||
    (parentBookingId && tripId === `planned_${parentBookingId}`)
  ) {
    tripIdShape = "planned_exact";
  } else if (
    (bookingId && tripId.startsWith(`planned_${bookingId}_`)) ||
    (parentBookingId && tripId.startsWith(`planned_${parentBookingId}_`))
  ) {
    tripIdShape = "planned_suffix";
  } else if (tripId.startsWith("planned_")) {
    tripIdShape = "planned_other";
  }
  const amount = Number(trip?.total_eur);
  const amountBucket = !Number.isFinite(amount)
    ? "missing"
    : amount > 0
      ? "positive"
      : "zero";
  const distance = Number(trip?.km_total);
  const sourceType =
    _streetHistoryCanonicalId(trip?.source).toLowerCase() === "street_ride"
      ? "streetRide"
      : kind === "planned"
        ? "planned"
        : kind === "direct"
          ? "streetRide"
          : "unknown";
  return {
    kind,
    tripIdShape,
    hasBookingId: bookingId !== "",
    hasParentBookingId: parentBookingId !== "",
    hasTrackingTripId: tripId !== "",
    hasLinkedTrackingTripId: linked !== "",
    hasCanonicalKey: canonicalKey !== "",
    isOperationalLeg: _streetHistoryIsOperationalLeg(trip),
    legType,
    sourceType,
    amountBucket,
    hasAmount: Number.isFinite(amount) && amount > 0,
    hasDistance: Number.isFinite(distance) && distance > 0,
    bookingKeyHash: _streetHistoryFingerprint(bookingId),
    parentKeyHash: _streetHistoryFingerprint(parentBookingId),
    trackingKeyHash: _streetHistoryFingerprint(tripId),
    canonicalKeyHash: _streetHistoryFingerprint(canonicalKey),
  };
}
// FASE 1 bounded live-shape diagnostic. Logged ONLY for direct trips,
// planned+outbound rows and operational legs (the records under investigation).
function _streetHistoryMaybeLogLiveShape(trip, resolvedLink) {
  const kind = _streetHistoryCanonicalKind(trip?.kind);
  const shape = _streetHistoryTripShape(trip, resolvedLink);
  const isPlannedOutbound = kind === "planned" && shape.legType === "outbound";
  if (kind !== "direct" && !isPlannedOutbound && !shape.isOperationalLeg) return;
  console.log(
    "[STREET_HISTORY_LIVE_SHAPE] " +
      `kind=${shape.kind} tripIdShape=${shape.tripIdShape} ` +
      `hasBookingId=${shape.hasBookingId} hasParentBookingId=${shape.hasParentBookingId} ` +
      `hasTrackingTripId=${shape.hasTrackingTripId} ` +
      `hasLinkedTrackingTripId=${shape.hasLinkedTrackingTripId} ` +
      `hasCanonicalKey=${shape.hasCanonicalKey} ` +
      `isOperationalLeg=${shape.isOperationalLeg} legType=${shape.legType} ` +
      `sourceType=${shape.sourceType} amountBucket=${shape.amountBucket} ` +
      `bookingKeyHash=${shape.bookingKeyHash} parentKeyHash=${shape.parentKeyHash} ` +
      `trackingKeyHash=${shape.trackingKeyHash} canonicalKeyHash=${shape.canonicalKeyHash}`,
  );
}
function _streetHistoryDirectRideKeySet(trips) {
  const keys = new Set();
  for (const trip of trips) {
    if (_streetHistoryCanonicalKind(trip?.kind) !== "direct") continue;
    const tripId = _streetHistoryTripIdOf(trip);
    const bookingId = _streetHistoryBookingIdOf(trip);
    if (tripId) keys.add(tripId);
    if (bookingId) keys.add(bookingId);
  }
  return keys;
}
function _streetHistoryIsCanonicalPlannedShadow(trip, directKeys, resolvedLink) {
  if (_streetHistoryCanonicalKind(trip?.kind) !== "planned") return false;
  const linked =
    _streetHistoryLinkedTrackingTripId(trip) ||
    _streetHistoryCanonicalId(resolvedLink);
  if (linked && directKeys.has(linked)) return true;
  const parent = _streetHistoryParentBookingId(trip);
  const bookingId = _streetHistoryBookingIdOf(trip);
  const ownedKey = [parent, bookingId].find((k) => k && directKeys.has(k));
  if (!ownedKey) return false;
  if (_streetHistoryIsOperationalLeg(trip)) return true;
  const tripId = _streetHistoryTripIdOf(trip);
  return (
    tripId === `planned_${ownedKey}` ||
    tripId.startsWith(`planned_${ownedKey}_`) ||
    tripId === `planned_${bookingId}` ||
    tripId.startsWith(`planned_${bookingId}_`)
  );
}
// FASE 2 server guard predicate (pure): refuse a redundant street-ride
// operational shadow write when the physical ride is already a direct trip.
function _streetRideBookingBlocksShadowWrite({
  source = "",
  rideType = "",
  trackingTripId = "",
  directTripExists = false,
} = {}) {
  const isStreetDirect =
    _streetHistoryCanonicalId(source).toLowerCase() === "street_ride" ||
    _streetHistoryCanonicalId(rideType).toLowerCase() === "direct";
  return Boolean(
    isStreetDirect && _streetHistoryCanonicalId(trackingTripId) && directTripExists,
  );
}
function dedupeCanonicalStreetHistoryTrips(trips, resolvedLinks) {
  const list = Array.isArray(trips) ? trips : [];
  const directKeys = _streetHistoryDirectRideKeySet(list);
  const links = resolvedLinks instanceof Map ? resolvedLinks : new Map();
  const linkFor = (trip) =>
    _streetHistoryCanonicalId(
      links.get(_streetHistoryParentBookingId(trip)) ||
        links.get(_streetHistoryBookingIdOf(trip)) ||
        "",
    );
  const kept = [];
  let dropped = 0;
  for (const trip of list) {
    const kind = _streetHistoryCanonicalKind(trip?.kind);
    const resolvedLink = kind === "planned" ? linkFor(trip) : "";
    const rideKey = _streetHistoryCanonicalRideKey(trip, resolvedLink);
    const shadow = _streetHistoryIsCanonicalPlannedShadow(
      trip,
      directKeys,
      resolvedLink,
    );
    _streetHistoryMaybeLogLiveShape(trip, resolvedLink);
    if (trip && typeof trip === "object") {
      trip.canonical_physical_ride_key = rideKey || null;
      trip.canonical_trip_kind =
        kind === "direct" ? "direct" : shadow ? "operational_shadow" : "planned";
      trip.is_operational_shadow = shadow;
      const linked = _streetHistoryLinkedTrackingTripId(trip) || resolvedLink;
      if (linked) trip.linked_tracking_trip_id = linked;
    }
    if (shadow) {
      dropped += 1;
      console.log(
        "[STREET_HISTORY_CANONICAL] phase=dedupe source=tracking " +
          "hasLinkedTrip=true hasLinkedBooking=true countContribution=0 " +
          "reason=street_planned_leg_shadow_of_direct_trip",
      );
      continue;
    }
    console.log(
      "[STREET_HISTORY_CANONICAL] " +
        `phase=${kind === "planned" ? "keep_separate" : "project"} source=tracking ` +
        `hasLinkedTrip=${kind === "direct"} hasLinkedBooking=${!!rideKey} ` +
        `countContribution=1 reason=${
          kind === "planned"
            ? "planned_leg_without_direct_trip_kept"
            : "canonical_ride_kept"
        }`,
    );
    kept.push(trip);
  }
  return { trips: kept, dropped };
}
// FASE 4 read-time enrichment: for candidate legacy shadows that don't yet
// carry a linked_tracking_trip_id and whose booking key is not already owned by
// a direct trip, read the linked booking from BOOKING_KV (bounded + cached) and
// resolve its tracking_trip_id. Returns Map<bookingKey, tracking_trip_id> only
// for PROVEN links (booking scope matches AND tracking_trip_id is present).
async function _resolveStreetHistoryTrackingLinks(env, scope, trips) {
  const out = new Map();
  if (!env?.BOOKING_KV) return out;
  const directKeys = _streetHistoryDirectRideKeySet(trips);
  const candidateIds = new Set();
  for (const trip of trips) {
    if (_streetHistoryCanonicalKind(trip?.kind) !== "planned") continue;
    if (_streetHistoryLinkedTrackingTripId(trip)) continue;
    const parent = _streetHistoryParentBookingId(trip);
    const bookingId = _streetHistoryBookingIdOf(trip);
    const alreadyOwned = [parent, bookingId].some((k) => k && directKeys.has(k));
    if (alreadyOwned) continue;
    if (parent) candidateIds.add(parent);
    if (bookingId) candidateIds.add(bookingId);
  }
  const MAX_LOOKUPS = 40;
  let used = 0;
  const tenantId = _streetHistoryCanonicalId(scope?.tenant_id);
  const companyId = _streetHistoryCanonicalId(scope?.company_id);
  for (const id of candidateIds) {
    if (used >= MAX_LOOKUPS) break;
    used += 1;
    let rec = null;
    try {
      rec = await env.BOOKING_KV.get(`booking:${id}`, { type: "json" });
    } catch (_) {
      rec = null;
    }
    if (!rec || typeof rec !== "object") continue;
    const recTenant = _streetHistoryCanonicalId(rec.tenant_id ?? rec.tenantId);
    const recCompany = _streetHistoryCanonicalId(rec.company_id ?? rec.companyId);
    if (tenantId && recTenant && recTenant !== tenantId) continue;
    if (companyId && recCompany && recCompany !== companyId) continue;
    const trackingTripId = _streetHistoryCanonicalId(
      rec.tracking_trip_id ?? rec.trackingTripId,
    );
    // Only trust the link when it points at a direct trip present in this list.
    if (trackingTripId && directKeys.has(trackingTripId)) {
      out.set(id, trackingTripId);
    }
  }
  if (used > 0) {
    console.log(
      `[STREET_HISTORY_CANONICAL] phase=enrich source=booking_kv lookups=${used} resolved=${out.size}`,
    );
  }
  return out;
}
// FASE 2 server guard: read the linked booking (bounded) to decide whether a
// record-planned-stop is a redundant street-ride shadow of an existing direct
// trip. Returns { block, source, rideType, trackingTripId }.
async function _streetRideShadowWriteGuard(env, scope, bookingId, parentBookingId) {
  const result = { block: false, source: "", rideType: "", trackingTripId: "" };
  if (!env?.BOOKING_KV) return result;
  const tenantId = _streetHistoryCanonicalId(scope?.tenant_id);
  const companyId = _streetHistoryCanonicalId(scope?.company_id);
  const ids = [
    _streetHistoryCanonicalId(bookingId),
    _streetHistoryCanonicalId(parentBookingId),
  ].filter((v, i, a) => v && a.indexOf(v) === i);
  for (const id of ids) {
    let rec = null;
    try {
      rec = await env.BOOKING_KV.get(`booking:${id}`, { type: "json" });
    } catch (_) {
      rec = null;
    }
    if (!rec || typeof rec !== "object") continue;
    const recTenant = _streetHistoryCanonicalId(rec.tenant_id ?? rec.tenantId);
    const recCompany = _streetHistoryCanonicalId(rec.company_id ?? rec.companyId);
    if (tenantId && recTenant && recTenant !== tenantId) continue;
    if (companyId && recCompany && recCompany !== companyId) continue;
    const source = _streetHistoryCanonicalId(rec.source ?? rec.booking_source);
    const rideType = _streetHistoryCanonicalId(rec.ride_type ?? rec.rideType);
    const trackingTripId = _streetHistoryCanonicalId(
      rec.tracking_trip_id ?? rec.trackingTripId,
    );
    let directTripExists = false;
    if (trackingTripId) {
      try {
        const resolved = await getScopedOrLegacyTripForScope(env, scope, trackingTripId);
        const directTrip = resolved?.trip;
        directTripExists =
          !!directTrip && _streetHistoryCanonicalKind(directTrip.kind) === "direct";
      } catch (_) {
        directTripExists = false;
      }
    }
    result.source = source;
    result.rideType = rideType;
    result.trackingTripId = trackingTripId;
    result.block = _streetRideBookingBlocksShadowWrite({
      source,
      rideType,
      trackingTripId,
      directTripExists,
    });
    if (result.block) return result;
  }
  return result;
}

async function handleTripsHistory(req, url, env, origin) {
  const requiredScope = parseRequiredTenantCompanyScope(req, url, null, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const auth = await resolveTripsHistoryAuth(req, url, env, scope, origin);
  if (!auth.ok) return auth.response;
  const tenant_id = scope.tenant_id;
  const company_id = scope.company_id;
  const driver_id =
    auth.forced_driver_id ?? safeStr(url.searchParams.get("driver_id"), 96);
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
    // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1A: intentionally NOT capped by
    // `limit` here. The planned operational-leg shadow must be deduped against
    // its direct trip BEFORE pagination, otherwise a shadow could survive on
    // page 1 while its direct trip sits beyond the cap (leaving total/completed
    // too high). The scan stays bounded by the trips index size
    // (<= 200 driver / <= 500 company).
  }

  if (cleaned.length !== tripIds.length) {
    await kvPutJson(
      env.FLUXIDI_TRACKING,
      scopedIndexKey,
      cleaned.slice(0, driver_id ? 200 : 500),
      TTL_TRIP
    );
  }

  // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1B: collapse the planned
  // operational-leg shadow of a linked street-ride direct trip so one physical
  // ride is returned exactly once. Pipeline:
  //   raw indexed trips -> summarize/expose relation fields
  //   -> enrich candidate legacy shadows from BOOKING_KV (tracking_trip_id)
  //   -> canonical annotation -> dedupe -> counts -> pagination (slice).
  // Dedupe MUST precede the slice so a shadow can never split from its direct
  // trip across a page boundary.
  const resolvedLinks = await _resolveStreetHistoryTrackingLinks(env, scope, trips);
  const canonical = dedupeCanonicalStreetHistoryTrips(trips, resolvedLinks);
  const canonicalTrips = canonical.trips.slice(0, limit);
  console.log(
    `[STREET_HISTORY_RUNTIME] source=worker canonicalVersion=${STREET_HISTORY_CANONICAL_VERSION} ` +
      `rowsBefore=${trips.length} rowsAfter=${canonical.trips.length} dropped=${canonical.dropped} returned=${canonicalTrips.length}`,
  );

  const resp = withCors(
    json(
      {
        ok: true,
        tenant_id,
        company_id,
        driver_id: driver_id ?? null,
        canonical_version: STREET_HISTORY_CANONICAL_VERSION,
        count: canonicalTrips.length,
        trips: canonicalTrips,
      },
      { status: 200 }
    ),
    origin
  );
  try {
    resp.headers.set("X-Fluxidi-History-Canonical", STREET_HISTORY_CANONICAL_VERSION);
  } catch (_) {
    // headers immutable in some runtimes; body canonical_version still proves it
  }
  return resp;
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
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_START_DIRECT",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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

  // STREET-RIDE-BOOKING-LIFECYCLE (staging-validate): backend-owned booking
  // creation. Booking-first: the booking is the durable, company-visible
  // record (goal = appear under Open/gepland), so we create it before
  // persisting the trip and embed the returned booking_id on the trip. The
  // direct_ride_key makes the create idempotent so a retried /trip/start-direct
  // never duplicates the booking. If booking creation fails, the ride still
  // proceeds trip-only with booking_link_state=pending (no orphan booking is
  // created; the trip carries direct_ride_key for later reconciliation).
  const directRideKey =
    safeStr(body["direct_ride_key"] ?? body["directRideKey"], 200) ||
    `direct_${trip_id}`;
  let booking_id = null;
  let booking_link_state = "pending";
  const bookingCreateRes = await _callBookingWorkerJson(
    env,
    "/track/booking/create-direct",
    {
      tenant_id,
      company_id,
      direct_ride_key: directRideKey,
      driver_id,
      vehicle_id,
      trip_id,
      origin: originData,
      destination,
      started_at: startedAt,
      currency: safeStr(pricing_snapshot?.currency, 8) || "EUR",
      pricing_snapshot,
    },
    { timeoutMs: 4000 },
  );
  if (bookingCreateRes?.ok === true && safeStr(bookingCreateRes?.booking_id, 160)) {
    booking_id = safeStr(bookingCreateRes.booking_id, 160);
    booking_link_state = "linked";
  } else {
    console.log(
      `[DIRECT_TRIP][BOOKING_CREATE][WARN] trip=${trip_id} link_state=pending reason=${safeStr(bookingCreateRes?.error, 120) || "unknown"}`,
    );
  }

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
    booking_id,
    bookingId: booking_id,
    direct_ride_key: directRideKey,
    booking_link_state,
    source: "street_ride",
    // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1B: write-time canonical
    // contract. The canonical physical ride key is the tracking trip id itself
    // so linked operational shadows can point at it explicitly.
    canonical_physical_ride_key: trip_id,
    canonical_trip_kind: "direct",
    is_operational_shadow: false,
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

  const startComplianceEvent = buildDirectTripStartComplianceEvent(trip, startedAt, scope);
  if (startComplianceEvent) {
    await emitComplianceEventBestEffort(env, startComplianceEvent, {
      timeoutMs: 1500,
      logLabel: "ride_start_direct",
    });
  }

  return withCors(
    json(
      {
        ok: true,
        trip_id,
        booking_id,
        booking_link_state,
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

// STREET-RIDE-BOOKING-LIFECYCLE (staging-validate): generic backend-to-backend
// call into the Booking Worker. Prefers the service binding (env.BOOKING_API),
// falls back to HTTP (env.BOOKING_API_URL). Returns the decoded JSON body or a
// { ok:false, error } shape; never throws. Mirrors the auth + target
// resolution used by _notifyBookingWorkerPlannedTripCompletionBestEffort.
async function _callBookingWorkerJson(env, path, payload, { timeoutMs = 4000 } = {}) {
  const adminToken = safeStr(env?.ADMIN_TOKEN, 512);
  if (!adminToken) return { ok: false, error: "missing_admin_token" };
  const requestInit = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${adminToken}`,
    },
    body: JSON.stringify(payload || {}),
  };
  const serviceBinding = env?.BOOKING_API;
  const baseUrl = safeStr(env?.BOOKING_API_URL, 200)?.replace(/\/+$/, "");
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    let res;
    if (serviceBinding && typeof serviceBinding.fetch === "function") {
      res = await serviceBinding.fetch(
        new Request(`https://booking.internal${path}`, {
          ...requestInit,
          signal: controller.signal,
        }),
      );
    } else if (baseUrl) {
      res = await fetch(`${baseUrl}${path}`, {
        ...requestInit,
        signal: controller.signal,
      });
    } else {
      return { ok: false, error: "missing_booking_api_target" };
    }
    const text = await res.text().catch(() => "");
    let decoded = null;
    try {
      decoded = text ? JSON.parse(text) : null;
    } catch (_) {
      decoded = null;
    }
    if (!res.ok) {
      return {
        ok: false,
        error: safeStr(decoded?.error, 120) || `http_${res.status}`,
      };
    }
    return decoded && typeof decoded === "object" ? decoded : { ok: true };
  } catch (err) {
    return {
      ok: false,
      error: safeStr(err?.message || err, 120) || "booking_worker_call_failed",
    };
  } finally {
    clearTimeout(timer);
  }
}

async function _notifyBookingWorkerPlannedTripCompletionBestEffort(env, scope, trip, ctx) {
  const adminToken = safeStr(env?.ADMIN_TOKEN, 512);
  if (!adminToken) {
    console.log("[TRACKING][PLANNED_STOP][BOOKING_SYNC] skipped reason=missing_admin_token");
    return;
  }
  const bookingId = safeStr(
    trip?.parent_booking_id ??
      trip?.parentBookingId ??
      trip?.booking_id ??
      trip?.bookingId,
    160,
  );
  if (!bookingId) {
    console.log("[TRACKING][PLANNED_STOP][BOOKING_SYNC] skipped reason=missing_booking_id");
    return;
  }
  const payload = {
    tenant_id: scope?.tenant_id,
    company_id: scope?.company_id,
    booking_id: bookingId,
    leg_id: safeStr(trip?.leg_id ?? trip?.legId, 200) || null,
    trip_id: safeStr(trip?.trip_id ?? trip?.tripId, 160) || null,
    stopped_at: safeStr(trip?.stopped_at ?? trip?.stoppedAt, 80) || null,
    source: "planned_trip_stop",
  };
  const requestInit = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${adminToken}`,
    },
    body: JSON.stringify(payload),
  };
  const serviceBinding = env?.BOOKING_API;
  const baseUrl = safeStr(env?.BOOKING_API_URL, 200)?.replace(/\/+$/, "");
  const targetUrl = `${baseUrl || "https://fluxidi-booking-api.fluxidi.workers.dev"}/track/booking/complete-from-planned-stop`;
  const syncTask = (async () => {
    try {
      let res;
      if (serviceBinding && typeof serviceBinding.fetch === "function") {
        res = await serviceBinding.fetch(
          new Request(`https://booking.internal/track/booking/complete-from-planned-stop`, requestInit),
        );
      } else if (baseUrl) {
        res = await fetch(targetUrl, requestInit);
      } else {
        console.log("[TRACKING][PLANNED_STOP][BOOKING_SYNC] skipped reason=missing_booking_api_target");
        return;
      }
      const bodyText = await res.text().catch(() => "");
      console.log(
        `[TRACKING][PLANNED_STOP][BOOKING_SYNC] booking=${bookingId} leg=${safeStr(trip?.leg_id ?? trip?.legId, 200) || "-"} trip=${safeStr(trip?.trip_id ?? trip?.tripId, 160) || "-"} http=${res.status} body=${safeStr(bodyText, 160) || "-"}`,
      );
    } catch (err) {
      console.log(
        `[TRACKING][PLANNED_STOP][BOOKING_SYNC] booking=${bookingId} failed reason=${safeStr(err?.message || err, 120) || "unknown"}`,
      );
    }
  })();
  if (ctx && typeof ctx.waitUntil === "function") {
    ctx.waitUntil(syncTask);
  } else {
    await syncTask;
  }
}

async function handleRecordPlannedStopTrip(req, url, env, origin, ctx) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_RECORD_PLANNED_STOP",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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

  // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1B (FASE 2 server guard): a
  // street-ride / direct booking's synthetic operational leg is ALREADY stored
  // as kind=direct via /trip/stop. Refuse the redundant shadow write so it never
  // becomes a second €0,00 Outbound history row. Real planned outbound/return
  // bookings (ride_type=planned, not street_ride) are unaffected and still
  // stored below.
  const shadowGuard = await _streetRideShadowWriteGuard(
    env,
    scope,
    booking_id,
    parent_booking_id,
  );
  if (shadowGuard.block) {
    console.log(
      "[STREET_HISTORY_SHADOW_WRITE] action=skip source=streetRide " +
        `syntheticLeg=true hasDirectTrip=true reason=street_ride_direct_trip_already_stored`,
    );
    return withCors(
      json(
        {
          ok: true,
          skipped: true,
          reason: "street_ride_direct_trip_already_stored",
          linked_tracking_trip_id: shadowGuard.trackingTripId || null,
          canonical_physical_ride_key: shadowGuard.trackingTripId || null,
          booking_id,
        },
        { status: 200 }
      ),
      origin
    );
  }

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

  // STREET-RIDE-HISTORY-DUPLICATE-ZERO-BOOKING-1B (FASE 3): explicit write-time
  // canonical relation. Reaching this point means the shadow guard did NOT block
  // (i.e. a real planned leg, or a compat store with no proven direct trip), so
  // this row is a first-class planned leg — not an operational shadow. If a
  // tracking link is nonetheless known, expose it so read-time dedupe is exact.
  const linkedTrackingTripId = safeStr(shadowGuard.trackingTripId, 160) || null;
  const canonicalPhysicalRideKey =
    linkedTrackingTripId || parent_booking_id || booking_id || null;
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
    linked_tracking_trip_id: linkedTrackingTripId,
    linkedTrackingTripId: linkedTrackingTripId,
    canonical_physical_ride_key: canonicalPhysicalRideKey,
    canonical_trip_kind: "planned",
    is_operational_shadow: false,
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

  console.log(
    "[STREET_HISTORY_SHADOW_WRITE] action=store " +
      `source=${shadowGuard.source === "street_ride" ? "streetRide" : "planned"} ` +
      `syntheticLeg=${is_operational_leg} hasDirectTrip=${!!linkedTrackingTripId} ` +
      "reason=planned_leg_stored",
  );
  await kvPutJson(env.FLUXIDI_TRACKING, scopedTripKey(scope, trip_id), trip, TTL_TRIP);
  await materializeTripDashboardKpisBestEffort(
    env,
    scope,
    trip,
    "planned_trip_stop",
  );
  await _notifyBookingWorkerPlannedTripCompletionBestEffort(env, scope, trip, ctx);
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
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_WAIT_START",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_WAIT_END",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_STOP",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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

  // STREET-RIDE-BOOKING-LIFECYCLE (staging-validate): finalize the linked
  // street-ride booking (fare/payment + COMPLETED) so it moves from
  // Open/gepland to Afgerond/voltooid in the company Bookings screen. The
  // finalize endpoint is idempotent (COMPLETED is terminal); a transient
  // failure here leaves the booking IN_PROGRESS and reconcilable — no data
  // loss (the trip is stopped and the compliance ledger carries booking_id).
  const directBookingId = safeStr(
    trip?.booking_id ?? trip?.bookingId ?? body["booking_id"] ?? body["bookingId"],
    160,
  );
  // STREET-RIDE-DURABLE-COMPLETION-2: the tracking trip is already persisted as
  // `stopped` above (authoritative totals stored). Finalize the linked booking
  // with a BOUNDED, AWAITED call — no longer fire-and-forget — and record the
  // outcome durably on the trip (booking_finalize_state). A failed finalize
  // NEVER rolls back the stopped trip; it stays `pending` and is retryable via
  // /trip/reconcile-direct-booking (client startup recovery + batch repair).
  if (directBookingId) {
    const finalizePayload = buildFinalizePayloadFromTrip(trip, scope);
    let finalizeRes = null;
    try {
      finalizeRes = await _callBookingWorkerJson(
        env,
        "/track/booking/finalize-direct",
        finalizePayload,
        { timeoutMs: 4000 },
      );
    } catch (err) {
      finalizeRes = { ok: false, error: safeStr(err?.message || err, 120) || "finalize_call_failed" };
    }
    applyBookingFinalizeAttempt(trip, {
      state: deriveFinalizeStateFromResult(finalizeRes),
      errorCode: finalizeErrorCodeFromResult(finalizeRes),
      nowIso: nowIso(),
    });
    applyCanonicalScopeToRecord(trip, scope);
    await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);
    if (finalizeRes?.ok !== true) {
      console.log(
        `[DIRECT_TRIP][BOOKING_FINALIZE][WARN] booking=${directBookingId} trip=${trip_id} state=pending reason=${finalizeErrorCodeFromResult(finalizeRes) || "unknown"} attempt=${trip.booking_finalize_attempt_count}`,
      );
    } else {
      console.log(
        `[DIRECT_TRIP][BOOKING_FINALIZE][OK] booking=${directBookingId} trip=${trip_id} state=completed`,
      );
    }
  }

  const stopFinalizeFields = safeBookingFinalizeResponseFields(trip);
  return withCors(
    json(
      {
        ok: true,
        trip_id,
        booking_id: stopFinalizeFields.booking_id,
        booking_finalize_state: stopFinalizeFields.booking_finalize_state,
        booking_finalized: stopFinalizeFields.booking_finalized,
        status: "stopped",
        stopped_at: stoppedAt,
        totals,
      },
      { status: 200 }
    ),
    origin
  );
}

// STREET-RIDE-DURABLE-COMPLETION-2: idempotent retry of a street/direct booking
// finalization from the persisted tracking trip. Fare is derived EXCLUSIVELY
// from the stored trip totals (never from request input); never creates a
// second booking; repeated calls are safe. Returns `completed` immediately when
// the booking is already finalized.
async function handleReconcileDirectBooking(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRIP_RECONCILE_DIRECT_BOOKING",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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

  // Already durably completed → idempotent no-op.
  if (bookingAlreadyFinalized(trip)) {
    const already = safeBookingFinalizeResponseFields(trip);
    return withCors(
      json({ ok: true, trip_id, reconciled: false, reason: DIRECT_RECONCILE_REASON.ALREADY_COMPLETED, ...already }, { status: 200 }),
      origin,
    );
  }

  const elig = tripReconcileEligibility(trip);
  if (!elig.ok) {
    return withCors(
      json({ ok: false, trip_id, reconciled: false, reason: elig.reason, ...safeBookingFinalizeResponseFields(trip) }, { status: 409 }),
      origin,
    );
  }

  const finalizePayload = buildFinalizePayloadFromTrip(trip, scope);
  let finalizeRes = null;
  try {
    finalizeRes = await _callBookingWorkerJson(
      env,
      "/track/booking/finalize-direct",
      finalizePayload,
      { timeoutMs: 4000 },
    );
  } catch (err) {
    finalizeRes = { ok: false, error: safeStr(err?.message || err, 120) || "finalize_call_failed" };
  }
  applyBookingFinalizeAttempt(trip, {
    state: deriveFinalizeStateFromResult(finalizeRes),
    errorCode: finalizeErrorCodeFromResult(finalizeRes),
    nowIso: nowIso(),
  });
  applyCanonicalScopeToRecord(trip, scope);
  await kvPutJson(env.FLUXIDI_TRACKING, key, trip, TTL_TRIP);

  const out = safeBookingFinalizeResponseFields(trip);
  console.log(
    `[DIRECT_TRIP][RECONCILE] trip=${trip_id} booking=${directBookingIdFromTrip(trip)} state=${out.booking_finalize_state} attempt=${trip.booking_finalize_attempt_count}`,
  );
  return withCors(
    json(
      {
        ok: out.booking_finalized,
        trip_id,
        reconciled: out.booking_finalized,
        reason: out.booking_finalized ? DIRECT_RECONCILE_REASON.REPAIRABLE : (finalizeErrorCodeFromResult(finalizeRes) || "pending"),
        ...out,
      },
      { status: 200 }
    ),
    origin
  );
}

// STREET-RIDE-DURABLE-COMPLETION-2: bounded, authenticated batch repair of
// historical stuck street/direct bookings. DRY-RUN BY DEFAULT (no writes unless
// the caller explicitly passes dry_run:false). Scans the scoped trips index,
// classifies each street/direct trip, and reconciles only terminal trips that
// carry a durable booking id + authoritative fare — reusing the idempotent
// finalize-direct path. Never touches planned/customer bookings, never
// completes an active trip, never guesses a fare. Returns summary counts only
// (PII-free) with cursor-based continuation.
async function handleRepairDirectBookings(req, url, env, origin) {
  requireAdmin(req, url, env);

  const body = await readJson(req);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;

  // Dry-run is the default: only an explicit dry_run:false performs writes.
  const dryRun = body?.dry_run !== false && body?.dryRun !== false;
  const limitRaw = Number(body?.limit ?? body?.batch_size);
  const limit = Number.isFinite(limitRaw) ? Math.max(1, Math.min(200, Math.floor(limitRaw))) : 50;
  const cursorRaw = Number(body?.cursor);
  const cursorStart = Number.isFinite(cursorRaw) ? Math.max(0, Math.floor(cursorRaw)) : 0;

  const indexKey = scopedTripsIndexKey(scope);
  const idsRaw = (await kvGetJson(env.FLUXIDI_TRACKING, indexKey)) ?? [];
  const tripIds = Array.isArray(idsRaw) ? idsRaw : [];
  const slice = tripIds.slice(cursorStart, cursorStart + limit);

  const summary = {
    candidates: 0,
    repairable: 0,
    skipped_non_terminal: 0,
    skipped_missing_trip: 0,
    skipped_missing_fare: 0,
    already_completed: 0,
    errors: 0,
  };

  for (const rawTripId of slice) {
    const tripId = safeStr(rawTripId, 160);
    if (!tripId) continue;
    try {
      const resolved = await getScopedOrLegacyTripForScope(env, scope, tripId);
      const trip = resolved.trip;
      if (!trip || !recordMatchesTenantCompanyScope(trip, scope)) {
        summary.skipped_missing_trip++;
        continue;
      }
      // Only street/direct rides are candidates; planned/customer bookings are
      // never considered here.
      if (!isStreetDirectTrip(trip)) continue;
      summary.candidates++;
      if (bookingAlreadyFinalized(trip)) {
        summary.already_completed++;
        continue;
      }
      const elig = tripReconcileEligibility(trip);
      if (!elig.ok) {
        if (elig.reason === DIRECT_RECONCILE_REASON.NON_TERMINAL) summary.skipped_non_terminal++;
        else if (elig.reason === DIRECT_RECONCILE_REASON.MISSING_FARE) summary.skipped_missing_fare++;
        else summary.skipped_missing_trip++;
        continue;
      }
      summary.repairable++;
      if (!dryRun) {
        let finalizeRes = null;
        try {
          finalizeRes = await _callBookingWorkerJson(
            env,
            "/track/booking/finalize-direct",
            buildFinalizePayloadFromTrip(trip, scope),
            { timeoutMs: 4000 },
          );
        } catch (err) {
          finalizeRes = { ok: false, error: safeStr(err?.message || err, 120) || "finalize_call_failed" };
        }
        applyBookingFinalizeAttempt(trip, {
          state: deriveFinalizeStateFromResult(finalizeRes),
          errorCode: finalizeErrorCodeFromResult(finalizeRes),
          nowIso: nowIso(),
        });
        applyCanonicalScopeToRecord(trip, scope);
        await kvPutJson(env.FLUXIDI_TRACKING, resolved.key, trip, TTL_TRIP);
        if (finalizeRes?.ok !== true) summary.errors++;
      }
    } catch (_) {
      summary.errors++;
    }
  }

  const nextCursor = cursorStart + slice.length;
  const hasMore = nextCursor < tripIds.length;
  console.log(
    `[DIRECT_TRIP][REPAIR] dry_run=${dryRun} scanned=${slice.length} candidates=${summary.candidates} repairable=${summary.repairable} already_completed=${summary.already_completed} skipped_non_terminal=${summary.skipped_non_terminal} skipped_missing_fare=${summary.skipped_missing_fare} skipped_missing_trip=${summary.skipped_missing_trip} errors=${summary.errors}`,
  );
  return withCors(
    json(
      {
        ok: true,
        dry_run: dryRun,
        summary,
        scanned: slice.length,
        index_size: tripIds.length,
        cursor: hasMore ? nextCursor : null,
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
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRACK_SESSION_START",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
  const requiredScope = parseRequiredTenantCompanyScope(req, url, body, { returnResponse: true, origin });
  if (requiredScope instanceof Response) return requiredScope;
  const scope = requiredScope;
  const actor = resolveTrackingActorFromRequest(req, url, body);
  const booking_id = safeStr(body["booking_id"], 64);
  if (!booking_id) throw new Error("booking_id is required");

  const pickup = safeStr(body["pickup"], 200) ?? null;
  const dropoff = safeStr(body["dropoff"], 200) ?? null;
  const originData = normalizeDestination(body["origin"]);
  const startedAt = safeStr(body["client_started_at"], 64) ?? nowIso();
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
    ...(originData ? { origin: originData } : {}),
    status: "active",
    created_at: nowIso(),
    started_at: startedAt,
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

  const startComplianceEvent = buildPlannedSessionStartComplianceEvent(session, body, startedAt, scope);
  if (startComplianceEvent) {
    await emitComplianceEventBestEffort(env, startComplianceEvent, {
      timeoutMs: 1500,
      logLabel: "ride_start_planned",
    });
  }

  return withCors(
    json({ ok: true, session_id: sessionId, booking_id, created_at: session.created_at, public_token }, { status: 200 }),
    origin
  );
}

async function handlePing(req, url, env, origin) {
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRACK_PING",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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
  const rawBody = await readJson(req);
  const auth = await requireDriverSessionOrAdminForScope(req, url, env, {
    body: rawBody,
    routeLabel: "TRACK_SESSION_STOP",
  });
  if (!auth.ok) return auth.response;
  const body = applyDriverSessionToBody(rawBody, auth.driver_session);
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
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_BOOKINGS",
  });
  if (!auth.ok) return auth.response;
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
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_BOOKING",
  });
  if (!auth.ok) return auth.response;
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
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_LIVE",
  });
  if (!auth.ok) return auth.response;
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
// Auth: driver session OR company session OR admin — this route proxies
// billable Mapbox and must not be reachable anonymously.
async function handleRoute(req, url, env, origin) {
  const auth = await requireDriverOrCompanyOrAdminForScope(req, url, env, {
    routeLabel: "TRACK_ROUTE",
  });
  if (!auth.ok) return auth.response;

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
      if (req.method === "POST" && url.pathname === "/trip/reconcile-direct-booking") return await handleReconcileDirectBooking(req, url, env, origin);
      if (req.method === "POST" && url.pathname === "/trip/repair-direct-bookings") return await handleRepairDirectBookings(req, url, env, origin);
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
