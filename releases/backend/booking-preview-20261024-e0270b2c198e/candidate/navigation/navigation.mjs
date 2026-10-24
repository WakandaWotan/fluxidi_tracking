// national_navigation_relay.mjs
var json = (value, status = 200) => new Response(JSON.stringify(value), { status, headers: {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
  "access-control-allow-origin": "*",
  ...status === 429 ? { "retry-after": "10" } : {}
} });
var fail = (error, status) => json({ ok: false, error, provider_fallback: false }, status);
var hex = (value) => typeof value === "string" && /^[a-f0-9]{64}$/.test(value);
var scopePart = (value) => typeof value === "string" && value.length > 0 && value.length <= 200 && !/[\r\n\0]/.test(value);
async function boundedNavigationJson(message, limit, timeoutMs = 5e3) {
  const length = message.headers.get("content-length");
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > limit)) throw Error("body_limit");
  if (!message.body) throw Error("body_invalid");
  const reader = message.body.getReader(), chunks = [];
  let size = 0, expired = false;
  const cancel = () => {
    void reader.cancel().catch(() => {
    });
  };
  const timer = setTimeout(() => {
    expired = true;
    cancel();
  }, timeoutMs);
  message.signal?.addEventListener("abort", cancel, { once: true });
  try {
    for (; ; ) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > limit) {
        await reader.cancel();
        throw Error("body_limit");
      }
      chunks.push(value);
    }
    if (expired || message.signal?.aborted) throw Error("body_deadline");
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.byteLength;
    }
    return JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
  } finally {
    clearTimeout(timer);
    message.signal?.removeEventListener("abort", cancel);
    reader.releaseLock();
  }
}
async function storeSummary(env, scope, tripId, route) {
  if (!tripId || !env.ROUTE_SESSION) return false;
  if (!scopePart(scope?.tenant_id) || !scopePart(scope?.company_id) || scope.driver_id != null && !scopePart(scope.driver_id)) return false;
  const bytes = new TextEncoder().encode(JSON.stringify(["national-v1", scope.tenant_id, scope.company_id, scope.driver_id ?? null, tripId]));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  const key = Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
  try {
    const stub = env.ROUTE_SESSION.get(env.ROUTE_SESSION.idFromName("national-v1:" + key));
    const response = await stub.fetch(new Request("https://route-session.internal/summary", {
      method: "PUT",
      headers: { "content-type": "application/json" },
      signal: AbortSignal.timeout(2e3),
      body: JSON.stringify({ trip_id: tripId, route_hash: route.route_hash, distance_m: route.distance_m, duration_s: route.duration_s, profile: "driving" })
    }));
    if (response.status !== 200) {
      await response.body?.cancel();
      return false;
    }
    const ack = await boundedNavigationJson(response, 2048, 2e3);
    return ack?.ok === true && ack.stored === true;
  } catch {
    return false;
  }
}
async function relayNationalNavigation(request, env, { clock = Date.now } = {}) {
  const path = new URL(request.url).pathname;
  if (!["/route", "/reroute"].includes(path)) return null;
  if (request.method !== "POST") return fail("method_not_allowed", 405);
  const auth = request.headers.get("authorization");
  if (!auth || !/^Bearer [^\s]{1,4096}$/.test(auth)) return fail("unauthorized", 401);
  if (typeof env.BOOKING_ROUTER?.fetch !== "function") return fail("national_navigation_unavailable", 503);
  if (request.headers.has("content-encoding") || !/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get("content-type") ?? "")) return fail("navigation_input_invalid", 400);
  let body;
  try {
    body = await boundedNavigationJson(request, 8192);
  } catch (e) {
    return fail("navigation_input_invalid", e.message === "body_limit" ? 413 : e.message === "body_deadline" ? 408 : 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || body.trip_id != null && (!scopePart(body.trip_id) || body.trip_id.length > 160)) return fail("navigation_input_invalid", 400);
  const controller = new AbortController();
  const cancel = () => controller.abort();
  request.signal.addEventListener("abort", cancel, { once: true });
  const timer = setTimeout(cancel, 2e4);
  try {
    if (request.signal.aborted) return fail("navigation_cancelled", 499);
    const headers = new Headers({ "content-type": "application/json", "authorization": auth });
    const ip = request.headers.get("cf-connecting-ip");
    if (ip && ip.length <= 64) headers.set("cf-connecting-ip", ip);
    const response = await env.BOOKING_ROUTER.fetch(new Request("https://fluxidi-booking-api.fluxidi.workers.dev/company/navigation" + path, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
      signal: controller.signal
    }));
    const result = await boundedNavigationJson(response, 8 * 1024 * 1024, 15e3);
    if (controller.signal.aborted) return fail("navigation_deadline", 504);
    if (response.status !== 200) {
      const error = typeof result?.error === "string" && /^[a-z][a-z0-9_]{0,100}$/.test(result.error) ? result.error : "navigation_route_unavailable";
      return fail(error, [400, 401, 403, 408, 409, 413, 422, 429, 503, 504].includes(response.status) ? response.status : 502);
    }
    if (result?.ok !== true || result.source !== "fluxidi-national" || result.provider_source != null || result.route_basis !== "owned_immutable_route" || !hex(result.route_hash) || !hex(result.navigation_metadata_sha256) || !scopePart(result.graph_version) || !scopePart(result.evidence_revision) || !Number.isFinite(result.valid_until_ms) || result.valid_until_ms <= clock() || !scopePart(result.session_scope?.tenant_id) || !scopePart(result.session_scope?.company_id) || !Number.isFinite(result.distance_m) || result.distance_m < 0 || !Number.isFinite(result.duration_s) || result.duration_s < 0 || result.geometry?.type !== "LineString" || !Array.isArray(result.geometry.coordinates) || result.geometry.coordinates.length < 2 || !Array.isArray(result.legs) || !result.legs.length) return fail("navigation_contract_invalid", 502);
    const stored = await storeSummary(env, result.session_scope, body.trip_id, result);
    if (request.signal.aborted) return fail("navigation_cancelled", 499);
    if (result.valid_until_ms <= clock()) return fail("navigation_route_lease_expired", 409);
    const { session_scope: omitted, ...publicResult } = result;
    return json({ ...publicResult, route_session_updated: stored });
  } catch {
    return fail(request.signal.aborted ? "navigation_cancelled" : "navigation_route_unavailable", request.signal.aborted ? 499 : 503);
  } finally {
    clearTimeout(timer);
    request.signal.removeEventListener("abort", cancel);
  }
}

// fluxidi_navigation_worker.mjs
var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var NAVIGATION_LANGUAGE_ALLOWLIST = Object.freeze([
  "nl",
  "fr",
  "en",
  "es",
  "pt"
]);
function summarizeSignalCounts(legs) {
  let steps = 0;
  let banners = 0;
  let laneGroups = 0;
  let refs = 0;
  let destinations = 0;
  let roundaboutExits = 0;
  const list = Array.isArray(legs) ? legs : [];
  for (const leg of list) {
    const stepList = Array.isArray(leg?.steps) ? leg.steps : [];
    for (const step of stepList) {
      steps += 1;
      const bannersAny = step?.bannerInstructions || step?.banner_instructions;
      if (Array.isArray(bannersAny) && bannersAny.length > 0) {
        banners += bannersAny.length;
      }
      const intersections = Array.isArray(step?.intersections) ? step.intersections : [];
      let stepHasLanes = false;
      for (const intersection of intersections) {
        if (Array.isArray(intersection?.lanes) && intersection.lanes.length > 0) {
          stepHasLanes = true;
          break;
        }
      }
      if (stepHasLanes) laneGroups += 1;
      if (typeof step?.ref === "string" && step.ref.trim()) refs += 1;
      if (Array.isArray(step?.destinations) && step.destinations.length > 0) {
        destinations += 1;
      }
      const exit = step?.maneuver?.exit;
      const type = String(step?.maneuver?.type || "").toLowerCase();
      if (exit != null && String(exit).trim() !== "" && (type.includes("roundabout") || type.includes("rotary"))) {
        roundaboutExits += 1;
      }
    }
  }
  return {
    steps,
    banners,
    laneGroups,
    refs,
    destinations,
    roundaboutExits
  };
}
__name(summarizeSignalCounts, "summarizeSignalCounts");
function formatNavSignalResponseLog(summary, source = "worker") {
  const s = summary || {};
  return `[NAV_SIGNAL_RESPONSE] source=${source} steps=${s.steps ?? 0} banners=${s.banners ?? 0} laneGroups=${s.laneGroups ?? 0} refs=${s.refs ?? 0} destinations=${s.destinations ?? 0} roundaboutExits=${s.roundaboutExits ?? 0}`;
}
__name(formatNavSignalResponseLog, "formatNavSignalResponseLog");
var SERVICE_NAME = "fluxidi-navigation-core";
var SERVICE_VERSION = "cloud-nav-national-v1";
var DIAG_TAG = "CLOUD_NAV_1";
var MAX_BODY_BYTES = 24 * 1024;
var COORD_DECIMALS = 4;
var ALLOWED_COUNTRIES = /* @__PURE__ */ new Set(["BE", "NL", "FR", "ES", "PT"]);
var ALLOWED_PROFILES = /* @__PURE__ */ new Set(["driving"]);
var CACHE_BYPASS_REROUTE_REASONS = /* @__PURE__ */ new Set([
  "off_route",
  "traffic",
  "opposite_direction",
  "wrong_street",
  "forced_detour",
  "wrong_exit"
]);
function shouldBypassRerouteCache(kind, rerouteReason) {
  if (kind !== "reroute") return false;
  const reason = String(rerouteReason || "").trim().toLowerCase();
  return CACHE_BYPASS_REROUTE_REASONS.has(reason);
}
__name(shouldBypassRerouteCache, "shouldBypassRerouteCache");
var COUNTRY_PROFILES = Object.freeze({
  BE: {
    code: "BE",
    defaultLanguage: "nl",
    drivingProfile: "driving",
    maxCacheTtlSeconds: 300,
    offlineCorridorBufferMeters: 800,
    maneuverLanguageHint: "nl",
    futureFlags: Object.freeze({
      low_emission_zones: true,
      airport_mode: true,
      toll_awareness: false
    })
  },
  NL: {
    code: "NL",
    defaultLanguage: "nl",
    drivingProfile: "driving",
    maxCacheTtlSeconds: 300,
    offlineCorridorBufferMeters: 750,
    maneuverLanguageHint: "nl",
    futureFlags: Object.freeze({
      low_emission_zones: true,
      airport_mode: true,
      toll_awareness: false
    })
  },
  FR: {
    code: "FR",
    defaultLanguage: "fr",
    drivingProfile: "driving",
    maxCacheTtlSeconds: 360,
    offlineCorridorBufferMeters: 900,
    maneuverLanguageHint: "fr",
    futureFlags: Object.freeze({
      low_emission_zones: true,
      airport_mode: true,
      toll_awareness: true
    })
  },
  ES: {
    code: "ES",
    defaultLanguage: "es",
    drivingProfile: "driving",
    maxCacheTtlSeconds: 360,
    offlineCorridorBufferMeters: 900,
    maneuverLanguageHint: "es",
    futureFlags: Object.freeze({
      low_emission_zones: true,
      airport_mode: true,
      toll_awareness: true
    })
  },
  PT: {
    code: "PT",
    defaultLanguage: "pt",
    drivingProfile: "driving",
    maxCacheTtlSeconds: 360,
    offlineCorridorBufferMeters: 850,
    maneuverLanguageHint: "pt",
    futureFlags: Object.freeze({
      low_emission_zones: false,
      airport_mode: true,
      toll_awareness: true
    })
  }
});
function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization"
  };
}
__name(corsHeaders, "corsHeaders");
function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders()
    }
  });
}
__name(jsonResponse, "jsonResponse");
function logCloudNav(endpoint, { country = "na", cache = "na", reason = "na" } = {}) {
  const safeEndpoint = safeToken(endpoint, 16) || "unknown";
  const safeCountry = safeToken(country, 4) || "na";
  const safeCache = safeToken(cache, 12) || "na";
  const safeReason = safeToken(reason, 48) || "na";
  console.log(
    `[${DIAG_TAG}] endpoint=${safeEndpoint} country=${safeCountry} cache=${safeCache} reason=${safeReason}`
  );
}
__name(logCloudNav, "logCloudNav");
function safeToken(value, maxLen = 64) {
  if (value === null || value === void 0) return "";
  const s = String(value).trim();
  if (!s) return "";
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}
__name(safeToken, "safeToken");
function parseCoordinatePair(obj, label) {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    return { ok: false, error: `${label} must be an object with lat and lng` };
  }
  const lat = Number(obj.lat);
  const lng = Number(obj.lng);
  if (!Number.isFinite(lat) || lat < -90 || lat > 90) {
    return { ok: false, error: `${label}.lat must be a number between -90 and 90` };
  }
  if (!Number.isFinite(lng) || lng < -180 || lng > 180) {
    return { ok: false, error: `${label}.lng must be a number between -180 and 180` };
  }
  return { ok: true, lat, lng };
}
__name(parseCoordinatePair, "parseCoordinatePair");
function normalizeCountry(value) {
  const code = safeToken(value, 4).toUpperCase();
  if (!ALLOWED_COUNTRIES.has(code)) return null;
  return code;
}
__name(normalizeCountry, "normalizeCountry");
function normalizeProfile(value) {
  const profile = safeToken(value, 32).toLowerCase();
  if (!ALLOWED_PROFILES.has(profile)) return null;
  return profile;
}
__name(normalizeProfile, "normalizeProfile");
function roundCoord(value) {
  const factor = 10 ** COORD_DECIMALS;
  return Math.round(value * factor) / factor;
}
__name(roundCoord, "roundCoord");
function publicCountryProfile(countryCode) {
  const profile = COUNTRY_PROFILES[countryCode];
  if (!profile) return null;
  return {
    code: profile.code,
    defaultLanguage: profile.defaultLanguage,
    drivingProfile: profile.drivingProfile,
    maxCacheTtlSeconds: profile.maxCacheTtlSeconds,
    offlineCorridorBufferMeters: profile.offlineCorridorBufferMeters,
    maneuverLanguageHint: profile.maneuverLanguageHint,
    futureFlags: profile.futureFlags
  };
}
__name(publicCountryProfile, "publicCountryProfile");
async function readJsonBody(request) {
  try {
    const body = await boundedNavigationJson(request, MAX_BODY_BYTES);
    if (!body || typeof body !== "object" || Array.isArray(body)) return { ok: false, error: "Invalid JSON body", status: 400 };
    return { ok: true, body };
  } catch (e) {
    return { ok: false, error: "Invalid JSON body", status: e.message === "body_limit" ? 413 : e.message === "body_deadline" ? 408 : 400 };
  }
}
function stableAvoidKey(avoid) {
  if (!Array.isArray(avoid) || avoid.length === 0) return "";
  const parts = avoid.map((item) => safeToken(item, 32).toLowerCase()).filter(Boolean).sort();
  return parts.join(",");
}
__name(stableAvoidKey, "stableAvoidKey");
var RouteSessionDurableObject = class {
  static {
    __name(this, "RouteSessionDurableObject");
  }
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/summary" && request.method === "GET") {
      const session = await this.state.storage.get("session") || null;
      return jsonResponse({ ok: true, session });
    }
    if (url.pathname === "/summary" && request.method === "PUT") {
      let body;
      try {
        body = await request.json();
      } catch (_) {
        return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400);
      }
      const tripId = typeof body?.trip_id === "string" && body.trip_id.length <= 160 && !/[\r\n\0]/.test(body.trip_id) ? body.trip_id : "";
      const routeHash = safeToken(body?.route_hash, 64);
      if (!tripId || !routeHash) {
        return jsonResponse({ ok: false, error: "trip_id and route_hash are required" }, 400);
      }
      const session = {
        trip_id: tripId,
        route_hash: routeHash,
        last_route_summary: {
          distance_m: Number(body?.distance_m) || 0,
          duration_s: Number(body?.duration_s) || 0,
          country: safeToken(body?.country, 4).toUpperCase() || null,
          profile: safeToken(body?.profile, 32) || "driving"
        },
        updated_at: (/* @__PURE__ */ new Date()).toISOString()
      };
      await this.state.storage.put("session", session);
      return jsonResponse({ ok: true, stored: true });
    }
    return jsonResponse({ ok: false, error: "Not Found" }, 404);
  }
};
async function handleHealth() {
  logCloudNav("health", { reason: "ok" });
  return jsonResponse({
    ok: true,
    service: SERVICE_NAME,
    version: SERVICE_VERSION
  });
}
__name(handleHealth, "handleHealth");
async function handleRoute(request, env) {
  return relayNationalNavigation(request, env);
}
function decodePolyline(encoded) {
  const coordinates = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let byte = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 31) << shift;
      shift += 5;
    } while (byte >= 32);
    const deltaLat = result & 1 ? ~(result >> 1) : result >> 1;
    lat += deltaLat;
    shift = 0;
    result = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 31) << shift;
      shift += 5;
    } while (byte >= 32);
    const deltaLng = result & 1 ? ~(result >> 1) : result >> 1;
    lng += deltaLng;
    coordinates.push([lng / 1e5, lat / 1e5]);
  }
  return coordinates;
}
__name(decodePolyline, "decodePolyline");
function extractLineCoordinates(geometryInput, polylineInput) {
  if (geometryInput && typeof geometryInput === "object") {
    if (geometryInput.type === "LineString" && Array.isArray(geometryInput.coordinates)) {
      return geometryInput.coordinates;
    }
    if (geometryInput.type === "Feature" && geometryInput.geometry?.type === "LineString" && Array.isArray(geometryInput.geometry.coordinates)) {
      return geometryInput.geometry.coordinates;
    }
  }
  if (typeof geometryInput === "string" && geometryInput.trim()) {
    return decodePolyline(geometryInput.trim());
  }
  if (typeof polylineInput === "string" && polylineInput.trim()) {
    return decodePolyline(polylineInput.trim());
  }
  return null;
}
__name(extractLineCoordinates, "extractLineCoordinates");
function haversineMeters(lng1, lat1, lng2, lat2) {
  const toRad = /* @__PURE__ */ __name((deg) => deg * Math.PI / 180, "toRad");
  const r = 6371e3;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)));
}
__name(haversineMeters, "haversineMeters");
function estimateRouteLengthMeters(coordinates) {
  if (!Array.isArray(coordinates) || coordinates.length < 2) return 0;
  let total = 0;
  for (let i = 1; i < coordinates.length; i += 1) {
    const prev = coordinates[i - 1];
    const curr = coordinates[i];
    if (!Array.isArray(prev) || !Array.isArray(curr)) continue;
    const lng1 = Number(prev[0]);
    const lat1 = Number(prev[1]);
    const lng2 = Number(curr[0]);
    const lat2 = Number(curr[1]);
    if (!Number.isFinite(lng1) || !Number.isFinite(lat1) || !Number.isFinite(lng2) || !Number.isFinite(lat2)) {
      continue;
    }
    total += haversineMeters(lng1, lat1, lng2, lat2);
  }
  return Math.round(total);
}
__name(estimateRouteLengthMeters, "estimateRouteLengthMeters");
function estimateOfflineCorridorTiles(routeLengthM, bufferM, zoomMin, zoomMax) {
  const corridorAreaM2 = Math.max(routeLengthM, 1e3) * Math.max(bufferM * 2, 200);
  let minTiles = 0;
  let maxTiles = 0;
  for (let z = zoomMin; z <= zoomMax; z += 1) {
    const metersPerTile = 156543.03392 * Math.cos(50 * Math.PI / 180) / 2 ** z;
    const tilesForZoom = Math.ceil(corridorAreaM2 / (metersPerTile * metersPerTile));
    minTiles += Math.max(1, Math.round(tilesForZoom * 0.35));
    maxTiles += Math.max(1, Math.round(tilesForZoom * 0.85));
  }
  return {
    min: Math.max(minTiles, 1),
    max: Math.max(maxTiles, minTiles)
  };
}
__name(estimateOfflineCorridorTiles, "estimateOfflineCorridorTiles");
async function handleOfflineCorridorMetadata(request) {
  const parsed = await readJsonBody(request);
  if (!parsed.ok) {
    logCloudNav("offline", { reason: "invalid_body" });
    return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
  }
  const body = parsed.body;
  const country = normalizeCountry(body.country);
  if (!country) {
    logCloudNav("offline", { reason: "invalid_country" });
    return jsonResponse({ ok: false, error: "country must be one of BE, NL, FR, ES, PT" }, 400);
  }
  const countryProfile = COUNTRY_PROFILES[country];
  const zoomMin = Number.isFinite(Number(body.zoom_min)) ? Math.max(0, Math.min(22, Math.floor(Number(body.zoom_min)))) : 10;
  const zoomMax = Number.isFinite(Number(body.zoom_max)) ? Math.max(zoomMin, Math.min(22, Math.floor(Number(body.zoom_max)))) : 14;
  const coordinates = extractLineCoordinates(body.geometry, body.polyline);
  const routeLengthM = estimateRouteLengthMeters(coordinates);
  const bufferM = countryProfile.offlineCorridorBufferMeters;
  const tileRange = null;
  const avgTileBytes = 42 * 1024;
  const sizeMin = null;
  const sizeMax = null;
  logCloudNav("offline", { country, cache: "bypass", reason: "metadata_only" });
  return jsonResponse({
    ok: true,
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
    endpoint: "offline-corridor/metadata",
    supported_status: "preparation_only",
    message: "Offline corridor tile packs are metadata-only in CLOUD-NAV-1. Tile download and full offline navigation are not available yet.",
    route_id: safeToken(body.route_id, 64) || null,
    country,
    corridor_buffer_meters: bufferM,
    zoom_min: zoomMin,
    zoom_max: zoomMax,
    route_length_m_estimate: routeLengthM,
    estimated_tile_count_range: tileRange,
    renderer: "maplibre",
    estimate_proven: false,
    estimated_size_bytes_range: {
      min: sizeMin,
      max: sizeMax
    },
    country_profile: publicCountryProfile(country)
  });
}
__name(handleOfflineCorridorMetadata, "handleOfflineCorridorMetadata");
var fluxidi_navigation_worker_default = {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }
    const url = new URL(request.url);
    try {
      if (url.pathname === "/health") {
        if (request.method !== "GET") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        return await handleHealth();
      }
      if (url.pathname === "/route") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        return await handleRoute(request, env, { kind: "route" });
      }
      if (url.pathname === "/reroute") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        return await handleRoute(request, env, { kind: "reroute" });
      }
      if (url.pathname === "/offline-corridor/metadata") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        return await handleOfflineCorridorMetadata(request);
      }
      return jsonResponse({ ok: false, error: "Not Found", path: url.pathname }, 404);
    } catch (_) {
      logCloudNav("unknown", { reason: "internal_error" });
      return jsonResponse({ ok: false, error: "Internal error" }, 500);
    }
  }
};
export {
  RouteSessionDurableObject,
  fluxidi_navigation_worker_default as default,
  shouldBypassRerouteCache
};
