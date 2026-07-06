// Fluxidi Dispatch Intelligence — CLOUD-AI-1 foundation
// Separate Worker: deterministic dispatch advice for taxi and airport rides.
// Advice-only in v1 — this Worker must NOT mutate bookings.
//
// Optional Workers AI is stubbed behind USE_WORKERS_AI (default "false").
// No secrets required for v1.
//
// Endpoints:
//   GET  /health
//   POST /airport/pickup-advice
//   POST /ride-risk
//   POST /offline-map-suggestions

const SERVICE_NAME = "fluxidi-dispatch-intelligence";
const SERVICE_VERSION = "cloud-ai-1";
const DIAG_TAG = "CLOUD_AI_1";

const MAX_BODY_BYTES = 24 * 1024;
const ALLOWED_COUNTRIES = new Set(["BE", "NL", "FR", "ES", "PT"]);
const ALLOWED_RIDE_TYPES = new Set(["taxi", "airport", "direct", "scheduled"]);
const ALLOWED_FLIGHT_STATUSES = new Set([
  "scheduled",
  "on_time",
  "early",
  "delayed",
  "landed",
  "diverted",
  "cancelled",
  "unknown",
]);

// ---------------------------------------------------------------------------
// Launch airport profiles (buffer = curb-to-curb pickup slack in minutes)
// ---------------------------------------------------------------------------

const AIRPORT_PROFILES = Object.freeze({
  BRU: { country: "BE", label: "Brussels Airport", basePickupBufferMin: 14 },
  CRL: { country: "BE", label: "Brussels South Charleroi", basePickupBufferMin: 12 },
  AMS: { country: "NL", label: "Amsterdam Schiphol", basePickupBufferMin: 16 },
  CDG: { country: "FR", label: "Paris Charles de Gaulle", basePickupBufferMin: 18 },
  ORY: { country: "FR", label: "Paris Orly", basePickupBufferMin: 15 },
  LIL: { country: "FR", label: "Lille Airport", basePickupBufferMin: 10 },
  MAD: { country: "ES", label: "Madrid Barajas", basePickupBufferMin: 16 },
  BCN: { country: "ES", label: "Barcelona El Prat", basePickupBufferMin: 15 },
  VLC: { country: "ES", label: "Valencia Airport", basePickupBufferMin: 11 },
  AGP: { country: "ES", label: "Malaga Costa del Sol", basePickupBufferMin: 13 },
  LIS: { country: "PT", label: "Lisbon Humberto Delgado", basePickupBufferMin: 15 },
  OPO: { country: "PT", label: "Porto Francisco Sa Carneiro", basePickupBufferMin: 12 },
  FAO: { country: "PT", label: "Faro Airport", basePickupBufferMin: 12 },
});

// ---------------------------------------------------------------------------
// Offline map region catalog per country (deterministic suggestions)
// ---------------------------------------------------------------------------

const REGION_CATALOG = Object.freeze({
  BE: [
    { region_id: "be_brussels_capital", label: "Brussels Capital Region", keywords: ["brussel", "bruxelles", "brussels"] },
    { region_id: "be_antwerp_region", label: "Antwerp Region", keywords: ["antwerp", "antwerpen", "anvers"] },
    { region_id: "be_ghent_region", label: "Ghent Region", keywords: ["gent", "ghent", "gand"] },
    { region_id: "be_liege_region", label: "Liege Region", keywords: ["liege", "luik"] },
    { region_id: "be_bru_airport_corridor", label: "Brussels Airport Corridor", keywords: ["zaventem"], airport: "BRU" },
    { region_id: "be_crl_airport_corridor", label: "Charleroi Airport Corridor", keywords: ["charleroi", "gosselies"], airport: "CRL" },
  ],
  NL: [
    { region_id: "nl_amsterdam_region", label: "Amsterdam Region", keywords: ["amsterdam"] },
    { region_id: "nl_rotterdam_den_haag", label: "Rotterdam / Den Haag Region", keywords: ["rotterdam", "den haag", "the hague"] },
    { region_id: "nl_utrecht_region", label: "Utrecht Region", keywords: ["utrecht"] },
    { region_id: "nl_ams_airport_corridor", label: "Schiphol Airport Corridor", keywords: ["schiphol"], airport: "AMS" },
  ],
  FR: [
    { region_id: "fr_paris_ile_de_france", label: "Paris / Ile-de-France", keywords: ["paris"] },
    { region_id: "fr_lille_metropole", label: "Lille Metropole", keywords: ["lille"] },
    { region_id: "fr_cdg_airport_corridor", label: "CDG Airport Corridor", keywords: ["roissy", "charles de gaulle"], airport: "CDG" },
    { region_id: "fr_ory_airport_corridor", label: "Orly Airport Corridor", keywords: ["orly"], airport: "ORY" },
    { region_id: "fr_lil_airport_corridor", label: "Lille Airport Corridor", keywords: ["lesquin"], airport: "LIL" },
  ],
  ES: [
    { region_id: "es_madrid_region", label: "Madrid Region", keywords: ["madrid"] },
    { region_id: "es_barcelona_region", label: "Barcelona Region", keywords: ["barcelona"] },
    { region_id: "es_valencia_region", label: "Valencia Region", keywords: ["valencia"] },
    { region_id: "es_malaga_costa_del_sol", label: "Malaga / Costa del Sol", keywords: ["malaga", "marbella", "torremolinos"] },
    { region_id: "es_mad_airport_corridor", label: "Madrid Barajas Corridor", keywords: ["barajas"], airport: "MAD" },
    { region_id: "es_bcn_airport_corridor", label: "Barcelona El Prat Corridor", keywords: ["el prat"], airport: "BCN" },
    { region_id: "es_vlc_airport_corridor", label: "Valencia Airport Corridor", keywords: ["manises"], airport: "VLC" },
    { region_id: "es_agp_airport_corridor", label: "Malaga Airport Corridor", keywords: ["costa del sol airport"], airport: "AGP" },
  ],
  PT: [
    { region_id: "pt_lisbon_region", label: "Lisbon Region", keywords: ["lisboa", "lisbon"] },
    { region_id: "pt_porto_region", label: "Porto Region", keywords: ["porto", "oporto"] },
    { region_id: "pt_algarve_region", label: "Algarve Region", keywords: ["algarve", "albufeira", "lagos"] },
    { region_id: "pt_lis_airport_corridor", label: "Lisbon Airport Corridor", keywords: ["portela"], airport: "LIS" },
    { region_id: "pt_opo_airport_corridor", label: "Porto Airport Corridor", keywords: ["maia", "sa carneiro"], airport: "OPO" },
    { region_id: "pt_fao_airport_corridor", label: "Faro Airport Corridor", keywords: ["faro"], airport: "FAO" },
  ],
});

// ---------------------------------------------------------------------------
// HTTP helpers (matches Fluxidi navigation/booking worker CORS pattern)
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
// Diagnostics — bounded, no PII (no names, phones, emails, exact addresses)
// ---------------------------------------------------------------------------

function safeToken(value, maxLen = 64) {
  if (value === null || value === undefined) return "";
  const s = String(value).trim();
  if (!s) return "";
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

function logCloudAi(endpoint, { result = "na", country = "na", reason = "na" } = {}) {
  const safeEndpoint = safeToken(endpoint, 32) || "unknown";
  const safeResult = safeToken(result, 32) || "na";
  const safeCountry = safeToken(country, 4) || "na";
  const safeReason = safeToken(reason, 48) || "na";
  console.log(
    `[${DIAG_TAG}] endpoint=${safeEndpoint} result=${safeResult} country=${safeCountry} reason=${safeReason}`,
  );
}

// ---------------------------------------------------------------------------
// Parsing / validation
// ---------------------------------------------------------------------------

function normalizeCountry(value) {
  const code = safeToken(value, 4).toUpperCase();
  if (!ALLOWED_COUNTRIES.has(code)) return null;
  return code;
}

function normalizeAirportCode(value) {
  const code = safeToken(value, 8).toUpperCase();
  if (!Object.prototype.hasOwnProperty.call(AIRPORT_PROFILES, code)) return null;
  return code;
}

function normalizeFlightStatus(value) {
  const status = safeToken(value, 24).toLowerCase();
  if (!status) return "unknown";
  return ALLOWED_FLIGHT_STATUSES.has(status) ? status : "unknown";
}

function parseIsoTimestamp(value, label) {
  const raw = safeToken(value, 48);
  if (!raw) return { ok: false, error: `${label} is required` };
  const ms = Date.parse(raw);
  if (!Number.isFinite(ms)) {
    return { ok: false, error: `${label} must be a valid ISO-8601 timestamp` };
  }
  return { ok: true, ms };
}

function optionalNonNegativeNumber(value, maxValue) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.min(n, maxValue);
}

/** Confidence values are 0..100 (percent-like); anything else is ignored. */
function optionalConfidence(value) {
  const n = optionalNonNegativeNumber(value, 100);
  return n === null ? null : Math.round(n);
}

function optionalBool(value) {
  if (value === true || value === false) return value;
  return null;
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

// ---------------------------------------------------------------------------
// Workers AI (stub — deterministic rules only in CLOUD-AI-1)
// ---------------------------------------------------------------------------

function workersAiEnabled(env) {
  return safeToken(env?.USE_WORKERS_AI, 8).toLowerCase() === "true";
}

/**
 * Placeholder for the future Workers AI enrichment pass. In CLOUD-AI-1 this
 * never runs a model: even when the flag is on, there is no AI binding yet,
 * so deterministic advice is always returned unchanged.
 */
function aiMeta(env) {
  return {
    used: false,
    provider: workersAiEnabled(env) ? "workers_ai_pending" : null,
  };
}

// ---------------------------------------------------------------------------
// GET /health
// ---------------------------------------------------------------------------

function handleHealth() {
  return jsonResponse({
    ok: true,
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
  });
}

// ---------------------------------------------------------------------------
// POST /airport/pickup-advice — deterministic wait/leave advice
// ---------------------------------------------------------------------------

function handleAirportPickupAdvice(body, env) {
  const country = normalizeCountry(body.country);
  if (!country) {
    logCloudAi("pickup-advice", { result: "rejected", reason: "invalid_country" });
    return jsonResponse(
      { ok: false, error: "country must be one of BE, NL, FR, ES, PT" },
      400,
    );
  }

  const airportCode = normalizeAirportCode(body.airport_code);
  if (!airportCode) {
    logCloudAi("pickup-advice", { result: "rejected", country, reason: "invalid_airport" });
    return jsonResponse(
      { ok: false, error: "airport_code is not a supported launch airport" },
      400,
    );
  }

  const pickupTs = parseIsoTimestamp(body.scheduled_pickup_iso, "scheduled_pickup_iso");
  if (!pickupTs.ok) {
    logCloudAi("pickup-advice", { result: "rejected", country, reason: "invalid_pickup_iso" });
    return jsonResponse({ ok: false, error: pickupTs.error }, 400);
  }

  const airport = AIRPORT_PROFILES[airportCode];
  const flightStatus = normalizeFlightStatus(body.flight_status);
  const hasFlightNumber = Boolean(safeToken(body.flight_number, 12));
  const driverEtaSec = optionalNonNegativeNumber(body.driver_eta_seconds, 6 * 3600);
  const routeDurationSec = optionalNonNegativeNumber(body.route_duration_seconds, 6 * 3600);
  const routeConfidence = optionalConfidence(body.route_confidence);
  const gpsConfidence = optionalConfidence(body.gps_confidence);
  const passengerCount = optionalNonNegativeNumber(body.passenger_count, 16);
  const luggageCount = optionalNonNegativeNumber(body.luggage_count, 32);

  const reasons = [];

  // Pickup buffer: airport curb slack + group/luggage handling time.
  let pickupBufferMin = airport.basePickupBufferMin;
  if (luggageCount !== null && luggageCount >= 3) {
    pickupBufferMin += 3;
    reasons.push("extra_luggage_buffer");
  }
  if (passengerCount !== null && passengerCount >= 5) {
    pickupBufferMin += 2;
    reasons.push("large_group_buffer");
  }

  const minutesUntilPickup = (pickupTs.ms - Date.now()) / 60000;
  const travelSec = driverEtaSec !== null ? driverEtaSec : routeDurationSec;
  const travelMin = travelSec !== null ? travelSec / 60 : null;

  const lowRouteConfidence = routeConfidence !== null && routeConfidence < 40;
  const lowGpsConfidence = gpsConfidence !== null && gpsConfidence < 40;
  if (lowRouteConfidence) reasons.push("low_route_confidence");
  if (lowGpsConfidence) reasons.push("low_gps_confidence");

  let action;
  let recommendedWaitMin = 0;
  let riskLevel = "low";

  if (flightStatus === "cancelled" || flightStatus === "diverted") {
    action = "needs_dispatcher_review";
    riskLevel = "high";
    reasons.push(`flight_${flightStatus}`);
  } else if (travelMin === null) {
    // No travel estimate — cannot compute slack deterministically.
    action = minutesUntilPickup <= pickupBufferMin ? "needs_dispatcher_review" : "monitor";
    riskLevel = minutesUntilPickup <= pickupBufferMin ? "high" : "medium";
    reasons.push("no_travel_estimate");
  } else {
    const slackMin = minutesUntilPickup - travelMin - pickupBufferMin;
    if (slackMin <= 0) {
      action = "leave_now";
      riskLevel = slackMin <= -10 ? "high" : slackMin <= -3 ? "medium" : "low";
      reasons.push(slackMin < 0 ? "arrival_slack_negative" : "arrival_slack_exhausted");
    } else if (slackMin <= 8) {
      action = "leave_now";
      riskLevel = "low";
      reasons.push("arrival_slack_small");
    } else if (slackMin <= 20) {
      action = "monitor";
      recommendedWaitMin = Math.max(0, Math.round(slackMin - 8));
      reasons.push("arrival_slack_moderate");
    } else {
      action = "wait";
      recommendedWaitMin = Math.round(slackMin - 10);
      reasons.push("arrival_slack_comfortable");
    }

    if (flightStatus === "delayed") {
      // Delayed inbound flight: waiting longer is usually safer than idling curbside.
      if (action === "leave_now") {
        action = "monitor";
        recommendedWaitMin = Math.max(recommendedWaitMin, 5);
      }
      reasons.push("flight_delayed");
    } else if (flightStatus === "landed") {
      // Passenger already on the ground: shrink any advised wait.
      recommendedWaitMin = Math.min(recommendedWaitMin, 5);
      reasons.push("flight_landed");
    } else if (flightStatus === "early") {
      recommendedWaitMin = Math.max(0, recommendedWaitMin - 5);
      reasons.push("flight_early");
    }

    if (lowRouteConfidence || lowGpsConfidence) {
      if (riskLevel === "low") riskLevel = "medium";
      if (action === "wait") {
        action = "monitor";
        reasons.push("confidence_downgrade_to_monitor");
      }
    }
  }

  if (!hasFlightNumber && flightStatus === "unknown") {
    reasons.push("no_flight_tracking_data");
  }

  logCloudAi("pickup-advice", { result: action, country, reason: reasons[0] || "na" });

  return jsonResponse({
    ok: true,
    advice: {
      action,
      recommended_wait_minutes: Math.max(0, Math.round(recommendedWaitMin)),
      pickup_buffer_minutes: Math.round(pickupBufferMin),
      risk_level: riskLevel,
      reasons,
    },
    ai: aiMeta(env),
  });
}

// ---------------------------------------------------------------------------
// POST /ride-risk — deterministic 0..100 risk score
// ---------------------------------------------------------------------------

function handleRideRisk(body, env) {
  const country = normalizeCountry(body.country);
  if (!country) {
    logCloudAi("ride-risk", { result: "rejected", reason: "invalid_country" });
    return jsonResponse(
      { ok: false, error: "country must be one of BE, NL, FR, ES, PT" },
      400,
    );
  }

  const rideType = safeToken(body.ride_type, 24).toLowerCase();
  if (!ALLOWED_RIDE_TYPES.has(rideType)) {
    logCloudAi("ride-risk", { result: "rejected", country, reason: "invalid_ride_type" });
    return jsonResponse(
      { ok: false, error: "ride_type must be one of taxi, airport, direct, scheduled" },
      400,
    );
  }

  const pickupTs = parseIsoTimestamp(body.pickup_iso, "pickup_iso");
  if (!pickupTs.ok) {
    logCloudAi("ride-risk", { result: "rejected", country, reason: "invalid_pickup_iso" });
    return jsonResponse({ ok: false, error: pickupTs.error }, 400);
  }

  const airportCode = body.airport_code === undefined || body.airport_code === null
    ? null
    : normalizeAirportCode(body.airport_code);
  if (body.airport_code !== undefined && body.airport_code !== null && !airportCode) {
    logCloudAi("ride-risk", { result: "rejected", country, reason: "invalid_airport" });
    return jsonResponse(
      { ok: false, error: "airport_code is not a supported launch airport" },
      400,
    );
  }

  const driverEtaSec = optionalNonNegativeNumber(body.driver_eta_seconds, 6 * 3600);
  const routeConfidence = optionalConfidence(body.route_confidence);
  const gpsConfidence = optionalConfidence(body.gps_confidence);
  const offRouteLikely = optionalBool(body.off_route_likely);
  const predictionActive = optionalBool(body.prediction_active);
  const rerouteCount = optionalNonNegativeNumber(body.reroute_count, 50);

  let score = 0;
  const reasons = [];
  const recommendedActions = [];

  // Time pressure: driver ETA vs scheduled pickup.
  const minutesUntilPickup = (pickupTs.ms - Date.now()) / 60000;
  if (driverEtaSec !== null) {
    const etaSlackMin = minutesUntilPickup - driverEtaSec / 60;
    if (etaSlackMin <= -10) {
      score += 35;
      reasons.push("driver_eta_far_past_pickup");
    } else if (etaSlackMin <= 0) {
      score += 22;
      reasons.push("driver_eta_past_pickup");
    } else if (etaSlackMin <= 5) {
      score += 10;
      reasons.push("driver_eta_tight");
    }
  } else {
    score += 8;
    reasons.push("no_driver_eta");
  }

  // Navigation confidence signals.
  if (routeConfidence !== null && routeConfidence < 30) {
    score += 25;
    reasons.push("route_confidence_very_low");
  } else if (routeConfidence !== null && routeConfidence < 50) {
    score += 12;
    reasons.push("route_confidence_low");
  }
  if (gpsConfidence !== null && gpsConfidence < 30) {
    score += 18;
    reasons.push("gps_confidence_very_low");
  } else if (gpsConfidence !== null && gpsConfidence < 50) {
    score += 8;
    reasons.push("gps_confidence_low");
  }
  if (offRouteLikely === true) {
    score += 15;
    reasons.push("off_route_likely");
  }
  if (predictionActive === true) {
    score += 8;
    reasons.push("gps_prediction_active");
  }
  if (rerouteCount !== null && rerouteCount >= 4) {
    score += 18;
    reasons.push("frequent_reroutes");
  } else if (rerouteCount !== null && rerouteCount >= 2) {
    score += 9;
    reasons.push("multiple_reroutes");
  }

  // Airport rides carry coordination overhead (terminal, curb, flight timing).
  if (rideType === "airport" || airportCode !== null) {
    score += 5;
    reasons.push("airport_ride_complexity");
  }

  score = Math.max(0, Math.min(100, Math.round(score)));
  const riskLevel = score < 30 ? "low" : score < 60 ? "medium" : "high";

  if (riskLevel === "high") {
    recommendedActions.push("notify_dispatcher");
    recommendedActions.push("contact_driver");
  } else if (riskLevel === "medium") {
    recommendedActions.push("monitor_ride");
  }
  if (reasons.includes("driver_eta_far_past_pickup")) {
    recommendedActions.push("consider_reassignment_review");
  }
  if (reasons.includes("off_route_likely") || reasons.includes("frequent_reroutes")) {
    recommendedActions.push("verify_route_with_driver");
  }
  if (reasons.includes("gps_confidence_very_low") || reasons.includes("gps_prediction_active")) {
    recommendedActions.push("expect_position_uncertainty");
  }
  if (recommendedActions.length === 0) {
    recommendedActions.push("no_action_needed");
  }

  logCloudAi("ride-risk", { result: riskLevel, country, reason: reasons[0] || "nominal" });

  return jsonResponse({
    ok: true,
    risk_level: riskLevel,
    score,
    reasons,
    recommended_actions: recommendedActions,
    ai: aiMeta(env),
  });
}

// ---------------------------------------------------------------------------
// POST /offline-map-suggestions — deterministic region catalog matching
// ---------------------------------------------------------------------------

function matchRegionsByAreaText(catalog, areaText) {
  const needle = safeToken(areaText, 96).toLowerCase();
  if (!needle) return [];
  return catalog.filter((region) =>
    region.keywords.some((keyword) => needle.includes(keyword)),
  );
}

function handleOfflineMapSuggestions(body, env) {
  const country = normalizeCountry(body.country);
  if (!country) {
    logCloudAi("offline-maps", { result: "rejected", reason: "invalid_country" });
    return jsonResponse(
      { ok: false, error: "country must be one of BE, NL, FR, ES, PT" },
      400,
    );
  }

  const catalog = REGION_CATALOG[country] || [];
  const airportCode = body.airport_code === undefined || body.airport_code === null
    ? null
    : normalizeAirportCode(body.airport_code);
  if (body.airport_code !== undefined && body.airport_code !== null && !airportCode) {
    logCloudAi("offline-maps", { result: "rejected", country, reason: "invalid_airport" });
    return jsonResponse(
      { ok: false, error: "airport_code is not a supported launch airport" },
      400,
    );
  }

  const suggestionsById = new Map();
  const addSuggestion = (region, priority, reason) => {
    const existing = suggestionsById.get(region.region_id);
    if (existing && existing.priority <= priority) return;
    suggestionsById.set(region.region_id, {
      region_id: region.region_id,
      label: region.label,
      country,
      priority,
      reason,
    });
  };

  // 1. Airport corridor for the requested airport (highest priority).
  if (airportCode) {
    const airportRegion = catalog.find((r) => r.airport === airportCode);
    if (airportRegion) addSuggestion(airportRegion, 1, "requested_airport_corridor");
  }

  // 2. Pickup/dropoff area keyword matches (area text is matched, never logged).
  for (const region of matchRegionsByAreaText(catalog, body.pickup_area)) {
    addSuggestion(region, 2, "pickup_area_match");
  }
  for (const region of matchRegionsByAreaText(catalog, body.dropoff_area)) {
    addSuggestion(region, 2, "dropoff_area_match");
  }

  // 3. Frequent regions reported by the app (validated against the catalog).
  const frequent = Array.isArray(body.frequent_regions) ? body.frequent_regions : [];
  for (const rawId of frequent.slice(0, 12)) {
    const regionId = safeToken(rawId, 48).toLowerCase();
    const region = catalog.find((r) => r.region_id === regionId);
    if (region) addSuggestion(region, 3, "frequent_region");
  }

  // 4. Country fallback: primary metro region so drivers always get a result.
  if (suggestionsById.size === 0 && catalog.length > 0) {
    addSuggestion(catalog[0], 4, "country_default_region");
  }

  const suggestions = Array.from(suggestionsById.values()).sort(
    (a, b) => a.priority - b.priority || a.region_id.localeCompare(b.region_id),
  );

  logCloudAi("offline-maps", {
    result: `suggestions_${suggestions.length}`,
    country,
    reason: suggestions[0]?.reason || "none",
  });

  return jsonResponse({
    ok: true,
    suggestions,
    ai: aiMeta(env),
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
        return handleHealth();
      }

      if (url.pathname === "/airport/pickup-advice") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        const parsed = await readJsonBody(request);
        if (!parsed.ok) {
          logCloudAi("pickup-advice", { result: "rejected", reason: "invalid_body" });
          return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
        }
        return handleAirportPickupAdvice(parsed.body, env);
      }

      if (url.pathname === "/ride-risk") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        const parsed = await readJsonBody(request);
        if (!parsed.ok) {
          logCloudAi("ride-risk", { result: "rejected", reason: "invalid_body" });
          return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
        }
        return handleRideRisk(parsed.body, env);
      }

      if (url.pathname === "/offline-map-suggestions") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        const parsed = await readJsonBody(request);
        if (!parsed.ok) {
          logCloudAi("offline-maps", { result: "rejected", reason: "invalid_body" });
          return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
        }
        return handleOfflineMapSuggestions(parsed.body, env);
      }

      return jsonResponse({ ok: false, error: "Not Found", path: url.pathname }, 404);
    } catch (_) {
      logCloudAi("unknown", { result: "error", reason: "internal_error" });
      return jsonResponse({ ok: false, error: "Internal error" }, 500);
    }
  },
};
