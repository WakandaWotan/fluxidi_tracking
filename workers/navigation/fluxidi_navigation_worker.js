// Fluxidi Navigation Core — CLOUD-NAV-1 foundation
// Separate Worker: Mapbox shield/proxy, route cache, country profiles,
// offline corridor metadata (no tile download), RouteSession DO skeleton.
//
// Required secret (set via wrangler secret put MAPBOX_ACCESS_TOKEN):
//   MAPBOX_ACCESS_TOKEN — Mapbox Directions access token (never expose to clients)
//
// Endpoints:
//   GET  /health
//   POST /route
//   POST /reroute
//   POST /offline-corridor/metadata

const SERVICE_NAME = "fluxidi-navigation-core";
const SERVICE_VERSION = "cloud-nav-1";
const DIAG_TAG = "CLOUD_NAV_1";

const MAX_BODY_BYTES = 24 * 1024;
const COORD_DECIMALS = 4;
const ALLOWED_COUNTRIES = new Set(["BE", "NL", "FR", "ES", "PT"]);
const ALLOWED_PROFILES = new Set(["driving"]);
const ALLOWED_REROUTE_REASONS = new Set([
  "off_route",
  "manual",
  "traffic",
  "unknown",
]);

const CACHE_HOST = "https://fluxidi-nav-cache.internal";

/** Country navigation profiles — cache TTL, language, offline corridor defaults. */
const COUNTRY_PROFILES = Object.freeze({
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
      toll_awareness: false,
    }),
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
      toll_awareness: false,
    }),
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
      toll_awareness: true,
    }),
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
      toll_awareness: true,
    }),
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
      toll_awareness: true,
    }),
  },
});

// ---------------------------------------------------------------------------
// HTTP helpers (matches Fluxidi booking worker CORS pattern)
// ---------------------------------------------------------------------------

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
}

function jsonResponse(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(),
    },
  });
}

// ---------------------------------------------------------------------------
// Diagnostics — bounded, no PII (no lat/lng, names, booking ids)
// ---------------------------------------------------------------------------

function logCloudNav(endpoint, { country = "na", cache = "na", reason = "na" } = {}) {
  const safeEndpoint = safeToken(endpoint, 16) || "unknown";
  const safeCountry = safeToken(country, 4) || "na";
  const safeCache = safeToken(cache, 12) || "na";
  const safeReason = safeToken(reason, 48) || "na";
  console.log(
    `[${DIAG_TAG}] endpoint=${safeEndpoint} country=${safeCountry} cache=${safeCache} reason=${safeReason}`,
  );
}

// ---------------------------------------------------------------------------
// Parsing / validation
// ---------------------------------------------------------------------------

function safeToken(value, maxLen = 64) {
  if (value === null || value === undefined) return "";
  const s = String(value).trim();
  if (!s) return "";
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

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

function normalizeCountry(value) {
  const code = safeToken(value, 4).toUpperCase();
  if (!ALLOWED_COUNTRIES.has(code)) return null;
  return code;
}

function normalizeProfile(value) {
  const profile = safeToken(value, 32).toLowerCase();
  if (!ALLOWED_PROFILES.has(profile)) return null;
  return profile;
}

function roundCoord(value) {
  const factor = 10 ** COORD_DECIMALS;
  return Math.round(value * factor) / factor;
}

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
    futureFlags: profile.futureFlags,
  };
}

async function readJsonBody(request) {
  const contentLength = Number(request.headers.get("content-length") || "0");
  if (Number.isFinite(contentLength) && contentLength > MAX_BODY_BYTES) {
    return { ok: false, error: "Request body too large", status: 413 };
  }
  let raw = "";
  try {
    raw = await request.text();
  } catch (_) {
    return { ok: false, error: "Unable to read request body", status: 400 };
  }
  if (raw.length > MAX_BODY_BYTES) {
    return { ok: false, error: "Request body too large", status: 413 };
  }
  if (!raw.trim()) {
    return { ok: false, error: "Request body is required", status: 400 };
  }
  try {
    const body = JSON.parse(raw);
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      return { ok: false, error: "JSON body must be an object", status: 400 };
    }
    return { ok: true, body };
  } catch (_) {
    return { ok: false, error: "Invalid JSON body", status: 400 };
  }
}

function requireMapboxToken(env) {
  const token = safeToken(env?.MAPBOX_ACCESS_TOKEN, 512);
  if (!token) {
    return {
      ok: false,
      error: "MAPBOX_ACCESS_TOKEN is not configured on the Worker",
      status: 500,
    };
  }
  return { ok: true, token };
}

// ---------------------------------------------------------------------------
// Route cache (Cloudflare Cache API, synthetic GET keys)
// ---------------------------------------------------------------------------

function stableAvoidKey(avoid) {
  if (!Array.isArray(avoid) || avoid.length === 0) return "";
  const parts = avoid
    .map((item) => safeToken(item, 32).toLowerCase())
    .filter(Boolean)
    .sort();
  return parts.join(",");
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

async function buildRouteCacheKey({
  kind,
  country,
  profile,
  originLat,
  originLng,
  destLat,
  destLng,
  avoid,
}) {
  const payload = [
    kind,
    country,
    profile,
    roundCoord(originLat),
    roundCoord(originLng),
    roundCoord(destLat),
    roundCoord(destLng),
    stableAvoidKey(avoid),
  ].join("|");
  const hash = await sha256Hex(payload);
  return {
    hash: hash.slice(0, 32),
    request: new Request(`${CACHE_HOST}/route/v1/${hash.slice(0, 32)}`, { method: "GET" }),
  };
}

async function readRouteCache(cacheRequest) {
  try {
    const cached = await caches.default.match(cacheRequest);
    if (!cached) return null;
    const text = await cached.text();
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== "object") return null;
    return parsed;
  } catch (_) {
    return null;
  }
}

async function writeRouteCache(cacheRequest, payload, ttlSeconds) {
  const body = JSON.stringify(payload);
  const response = new Response(body, {
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": `public, max-age=${Math.max(60, ttlSeconds)}`,
    },
  });
  try {
    await caches.default.put(cacheRequest, response);
  } catch (_) {
    // Cache write failures are non-fatal.
  }
}

// ---------------------------------------------------------------------------
// Mapbox Directions proxy (token stays server-side)
// ---------------------------------------------------------------------------

async function fetchMapboxDirections({
  token,
  origin,
  destination,
  profile,
  language,
  avoid,
}) {
  const coords = `${origin.lng},${origin.lat};${destination.lng},${destination.lat}`;
  const params = new URLSearchParams({
    geometries: "geojson",
    overview: "full",
    steps: "true",
    language: language || "en",
    access_token: token,
  });
  const avoidKey = stableAvoidKey(avoid);
  if (avoidKey) {
    params.set("exclude", avoidKey);
  }

  const url =
    `https://api.mapbox.com/directions/v5/mapbox/${profile}/${coords}` +
    `?${params.toString()}`;

  const response = await fetch(url, { method: "GET" });
  if (!response.ok) {
    return {
      ok: false,
      error: `Mapbox directions failed (${response.status})`,
      status: response.status >= 500 ? 502 : 400,
    };
  }

  let data;
  try {
    data = await response.json();
  } catch (_) {
    return { ok: false, error: "Mapbox directions returned invalid JSON", status: 502 };
  }

  const route = Array.isArray(data?.routes) ? data.routes[0] : null;
  if (!route?.geometry) {
    return { ok: false, error: "Mapbox directions returned no route", status: 404 };
  }

  return {
    ok: true,
    route,
    distance_m: Number(route.distance) || 0,
    duration_s: Number(route.duration) || 0,
    geometry: route.geometry,
    maneuvers: extractManeuvers(route),
  };
}

function extractManeuvers(route) {
  const out = [];
  const legs = Array.isArray(route?.legs) ? route.legs : [];
  for (const leg of legs) {
    const steps = Array.isArray(leg?.steps) ? leg.steps : [];
    for (const step of steps) {
      const maneuver = step?.maneuver;
      if (!maneuver || typeof maneuver !== "object") continue;
      const location = Array.isArray(maneuver.location)
        ? { lng: Number(maneuver.location[0]), lat: Number(maneuver.location[1]) }
        : null;
      out.push({
        type: safeToken(maneuver.type, 32) || "unknown",
        modifier: safeToken(maneuver.modifier, 32) || null,
        instruction:
          safeToken(maneuver.instruction, 256) ||
          safeToken(step.name, 256) ||
          null,
        location,
        distance_m: Number(step.distance) || 0,
        duration_s: Number(step.duration) || 0,
      });
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
// RouteSession Durable Object — trip route metadata only (no marker movement)
// ---------------------------------------------------------------------------

export class RouteSessionDurableObject {
  constructor(state, env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === "/summary" && request.method === "GET") {
      const session = (await this.state.storage.get("session")) || null;
      return jsonResponse({ ok: true, session });
    }

    if (url.pathname === "/summary" && request.method === "PUT") {
      let body;
      try {
        body = await request.json();
      } catch (_) {
        return jsonResponse({ ok: false, error: "Invalid JSON body" }, 400);
      }
      const tripId = safeToken(body?.trip_id, 64);
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
          profile: safeToken(body?.profile, 32) || "driving",
        },
        updated_at: new Date().toISOString(),
      };
      await this.state.storage.put("session", session);
      return jsonResponse({ ok: true, stored: true });
    }

    return jsonResponse({ ok: false, error: "Not Found" }, 404);
  }
}

async function persistRouteSessionSummary(env, {
  tripId,
  routeHash,
  distance_m,
  duration_s,
  country,
  profile,
}) {
  if (!tripId || !env?.ROUTE_SESSION) return;
  try {
    const id = env.ROUTE_SESSION.idFromName(safeToken(tripId, 64));
    const stub = env.ROUTE_SESSION.get(id);
    await stub.fetch(
      new Request("https://route-session.internal/summary", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          trip_id: tripId,
          route_hash: routeHash,
          distance_m,
          duration_s,
          country,
          profile,
        }),
      }),
    );
  } catch (_) {
    // DO persistence is best-effort in CLOUD-NAV-1.
  }
}

// ---------------------------------------------------------------------------
// Handlers
// ---------------------------------------------------------------------------

async function handleHealth() {
  logCloudNav("health", { reason: "ok" });
  return jsonResponse({
    ok: true,
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
  });
}

async function handleRoute(request, env, { kind = "route" } = {}) {
  const parsed = await readJsonBody(request);
  if (!parsed.ok) {
    logCloudNav(kind, { reason: "invalid_body" });
    return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
  }
  const body = parsed.body;

  const country = normalizeCountry(body.country);
  if (!country) {
    logCloudNav(kind, { reason: "invalid_country" });
    return jsonResponse({ ok: false, error: "country must be one of BE, NL, FR, ES, PT" }, 400);
  }

  const profile = normalizeProfile(body.profile || "driving");
  if (!profile) {
    logCloudNav(kind, { country, reason: "invalid_profile" });
    return jsonResponse({ ok: false, error: 'profile must be "driving"' }, 400);
  }

  const originKey = kind === "reroute" ? "current" : "origin";
  const originParsed = parseCoordinatePair(body[originKey], originKey);
  if (!originParsed.ok) {
    logCloudNav(kind, { country, reason: "invalid_origin" });
    return jsonResponse({ ok: false, error: originParsed.error }, 400);
  }
  const destParsed = parseCoordinatePair(body.destination, "destination");
  if (!destParsed.ok) {
    logCloudNav(kind, { country, reason: "invalid_destination" });
    return jsonResponse({ ok: false, error: destParsed.error }, 400);
  }

  const tripId = safeToken(body.trip_id, 64) || null;
  const avoid = Array.isArray(body.avoid) ? body.avoid : [];
  const countryProfile = COUNTRY_PROFILES[country];

  let rerouteReason = null;
  if (kind === "reroute") {
    rerouteReason = safeToken(body.reason, 32).toLowerCase() || "unknown";
    if (!ALLOWED_REROUTE_REASONS.has(rerouteReason)) {
      logCloudNav(kind, { country, reason: "invalid_reroute_reason" });
      return jsonResponse(
        {
          ok: false,
          error: "reason must be one of off_route, manual, traffic, unknown",
        },
        400,
      );
    }
  }

  const tokenResult = requireMapboxToken(env);
  if (!tokenResult.ok) {
    logCloudNav(kind, { country, reason: "mapbox_token_missing" });
    return jsonResponse({ ok: false, error: tokenResult.error }, tokenResult.status);
  }

  const cacheKey = await buildRouteCacheKey({
    kind,
    country,
    profile,
    originLat: originParsed.lat,
    originLng: originParsed.lng,
    destLat: destParsed.lat,
    destLng: destParsed.lng,
    avoid,
  });

  const bypassCache = kind === "reroute" && (rerouteReason === "off_route" || rerouteReason === "traffic");
  let cacheStatus = bypassCache ? "bypass" : "miss";
  let routePayload = null;

  if (!bypassCache) {
    const cached = await readRouteCache(cacheKey.request);
    if (cached) {
      cacheStatus = "hit";
      routePayload = cached;
    }
  }

  if (!routePayload) {
    const mapbox = await fetchMapboxDirections({
      token: tokenResult.token,
      origin: { lat: originParsed.lat, lng: originParsed.lng },
      destination: { lat: destParsed.lat, lng: destParsed.lng },
      profile,
      language: countryProfile.maneuverLanguageHint,
      avoid,
    });

    if (!mapbox.ok) {
      logCloudNav(kind, { country, cache: "bypass", reason: "mapbox_error" });
      return jsonResponse({ ok: false, error: mapbox.error }, mapbox.status || 502);
    }

    routePayload = {
      distance_m: mapbox.distance_m,
      duration_s: mapbox.duration_s,
      geometry: mapbox.geometry,
      maneuvers: mapbox.maneuvers,
    };

    if (!bypassCache) {
      await writeRouteCache(
        cacheKey.request,
        routePayload,
        countryProfile.maxCacheTtlSeconds,
      );
    }
  }

  logCloudNav(kind, { country, cache: cacheStatus, reason: kind === "reroute" ? rerouteReason : "ok" });

  if (tripId) {
    await persistRouteSessionSummary(env, {
      tripId,
      routeHash: cacheKey.hash,
      distance_m: routePayload.distance_m,
      duration_s: routePayload.duration_s,
      country,
      profile,
    });
  }

  const response = {
    ok: true,
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
    cache: cacheStatus,
    country,
    profile,
    route_hash: cacheKey.hash,
    distance_m: routePayload.distance_m,
    duration_s: routePayload.duration_s,
    geometry: routePayload.geometry,
    maneuvers: routePayload.maneuvers || [],
    country_profile: publicCountryProfile(country),
  };

  if (kind === "reroute") {
    response.reason = rerouteReason;
    response.endpoint = "reroute";
  } else {
    response.endpoint = "route";
  }

  return jsonResponse(response);
}

// ---------------------------------------------------------------------------
// Offline corridor metadata (estimates only — no tile download)
// ---------------------------------------------------------------------------

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
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const deltaLat = (result & 1) ? ~(result >> 1) : result >> 1;
    lat += deltaLat;

    shift = 0;
    result = 0;
    do {
      byte = encoded.charCodeAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    const deltaLng = (result & 1) ? ~(result >> 1) : result >> 1;
    lng += deltaLng;

    coordinates.push([lng / 1e5, lat / 1e5]);
  }

  return coordinates;
}

function extractLineCoordinates(geometryInput, polylineInput) {
  if (geometryInput && typeof geometryInput === "object") {
    if (geometryInput.type === "LineString" && Array.isArray(geometryInput.coordinates)) {
      return geometryInput.coordinates;
    }
    if (
      geometryInput.type === "Feature" &&
      geometryInput.geometry?.type === "LineString" &&
      Array.isArray(geometryInput.geometry.coordinates)
    ) {
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

function haversineMeters(lng1, lat1, lng2, lat2) {
  const toRad = (deg) => (deg * Math.PI) / 180;
  const r = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.min(1, Math.sqrt(a)));
}

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

function estimateOfflineCorridorTiles(routeLengthM, bufferM, zoomMin, zoomMax) {
  const corridorAreaM2 = Math.max(routeLengthM, 1000) * Math.max(bufferM * 2, 200);
  let minTiles = 0;
  let maxTiles = 0;
  for (let z = zoomMin; z <= zoomMax; z += 1) {
    const metersPerTile = (156543.03392 * Math.cos((50 * Math.PI) / 180)) / 2 ** z;
    const tilesForZoom = Math.ceil(corridorAreaM2 / (metersPerTile * metersPerTile));
    minTiles += Math.max(1, Math.round(tilesForZoom * 0.35));
    maxTiles += Math.max(1, Math.round(tilesForZoom * 0.85));
  }
  return {
    min: Math.max(minTiles, 1),
    max: Math.max(maxTiles, minTiles),
  };
}

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
  const zoomMin = Number.isFinite(Number(body.zoom_min))
    ? Math.max(0, Math.min(22, Math.floor(Number(body.zoom_min))))
    : 10;
  const zoomMax = Number.isFinite(Number(body.zoom_max))
    ? Math.max(zoomMin, Math.min(22, Math.floor(Number(body.zoom_max))))
    : 14;

  const coordinates = extractLineCoordinates(body.geometry, body.polyline);
  const routeLengthM = estimateRouteLengthMeters(coordinates);
  const bufferM = countryProfile.offlineCorridorBufferMeters;
  const tileRange = estimateOfflineCorridorTiles(routeLengthM, bufferM, zoomMin, zoomMax);

  const avgTileBytes = 42 * 1024;
  const sizeMin = tileRange.min * Math.round(avgTileBytes * 0.55);
  const sizeMax = tileRange.max * Math.round(avgTileBytes * 1.35);

  logCloudNav("offline", { country, cache: "bypass", reason: "metadata_only" });

  return jsonResponse({
    ok: true,
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
    endpoint: "offline-corridor/metadata",
    supported_status: "preparation_only",
    message:
      "Offline corridor tile packs are metadata-only in CLOUD-NAV-1. " +
      "Tile download and full offline navigation are not available yet.",
    route_id: safeToken(body.route_id, 64) || null,
    country,
    corridor_buffer_meters: bufferM,
    zoom_min: zoomMin,
    zoom_max: zoomMax,
    route_length_m_estimate: routeLengthM,
    estimated_tile_count_range: tileRange,
    estimated_size_bytes_range: {
      min: sizeMin,
      max: sizeMax,
    },
    country_profile: publicCountryProfile(country),
  });
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

export default {
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
  },
};
