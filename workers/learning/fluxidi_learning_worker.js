// Fluxidi Learning API — CLOUD-LEARN-1 foundation
// Separate Worker: stores anonymized operational ride lessons for future
// AI dispatch learning. V1 is write/validate/store foundation only:
// no AI training, no booking mutations, no customer data.
//
// Storage: Cloudflare D1 via the LEARNING_DB binding. Until the D1 database
// is created and bound (see wrangler.toml TODO), the Worker runs in dry-run
// mode: payloads are fully validated but nothing is persisted.
//
// Tenant isolation (CLOUD-LEARN-1B): every lesson is partitioned by opaque
// tenant_scope_hash + company_scope_hash tokens. Raw tenant/company IDs and
// names are never accepted; summaries always filter on both scope hashes, so
// there is no global/cross-company read path.
//
// Suggested D1 schema (run once when creating fluxidi-learning-db):
//
//   CREATE TABLE IF NOT EXISTS ride_lessons (
//     id TEXT PRIMARY KEY,
//     created_at TEXT NOT NULL,
//     tenant_scope_hash TEXT NOT NULL,
//     company_scope_hash TEXT NOT NULL,
//     country TEXT NOT NULL,
//     ride_type TEXT NOT NULL,
//     airport_code TEXT,
//     weekday INTEGER,
//     hour_bucket INTEGER,
//     planned_duration_seconds INTEGER,
//     actual_duration_seconds INTEGER,
//     eta_delta_seconds INTEGER,
//     planned_distance_m INTEGER,
//     actual_distance_m INTEGER,
//     pickup_wait_seconds INTEGER,
//     driver_arrival_delta_seconds INTEGER,
//     route_confidence_avg REAL,
//     gps_confidence_avg REAL,
//     reroute_count INTEGER,
//     off_route_events INTEGER,
//     prediction_events INTEGER,
//     completed INTEGER,
//     cancelled INTEGER,
//     outcome TEXT,
//     sample_source TEXT
//   );
//   CREATE INDEX IF NOT EXISTS idx_ride_lessons_scope_lookup
//     ON ride_lessons (tenant_scope_hash, company_scope_hash, country,
//                      ride_type, airport_code, weekday, hour_bucket);
//
// Service auth (CLOUD-LEARN-3): all non-health endpoints require
//   Authorization: Bearer <LEARNING_SERVICE_TOKEN>
// The token is a Worker secret (wrangler secret put LEARNING_SERVICE_TOKEN),
// never stored in Git, never logged, never echoed. Auth is checked before the
// request body is read, so unauthenticated callers cannot probe validation.
//
// Endpoints:
//   GET  /health                (public)
//   POST /ride-lessons/ingest   (service auth required)
//   POST /insights/summary      (service auth required)
//   POST   /admin/nav-complexity-events/ingest-dry-run  (service auth, NAV-AI-3)
//   GET    /admin/nav-complexity-events/recent          (service auth, NAV-AI-3)
//   DELETE /admin/nav-complexity-events/test-data       (service auth, NAV-AI-3)

import {
  validateNavComplexityIngestRequest,
  navComplexityEventToDbRow,
  publicNavComplexityRow,
} from "./nav_complexity_event_schema.js";

const NAV_COMPLEXITY_DIAG_TAG = "NAV_AI_3";

const SERVICE_NAME = "fluxidi-learning";
const SERVICE_VERSION = "cloud-learn-1";
const DIAG_TAG = "CLOUD_LEARN_1";

const MAX_BODY_BYTES = 24 * 1024;
const MIN_SAMPLES_FOR_INSIGHTS = 25;

const ALLOWED_COUNTRIES = new Set(["BE", "NL", "FR", "ES", "PT"]);
const ALLOWED_AIRPORTS = new Set([
  "BRU", "CRL", "AMS", "CDG", "ORY", "LIL",
  "MAD", "BCN", "VLC", "AGP", "LIS", "OPO", "FAO",
]);
const ALLOWED_RIDE_TYPES = new Set(["airport", "local", "intercity"]);
const ALLOWED_OUTCOMES = new Set([
  "good",
  "late",
  "early",
  "cancelled",
  "needs_review",
]);
const ALLOWED_SAMPLE_SOURCES = new Set([
  "driver_os",
  "booking_worker",
  "manual_test",
]);

// ---------------------------------------------------------------------------
// PII guard — anonymized lessons only. Never log or store customer names,
// phone numbers, emails, exact addresses, booking IDs, lat/lng, flight
// passenger identity, payment IDs, or document IDs.
// ---------------------------------------------------------------------------

/** Only these top-level keys are accepted on /ride-lessons/ingest. */
const INGEST_ALLOWED_KEYS = new Set([
  "tenant_scope_hash",
  "company_scope_hash",
  "country",
  "ride_type",
  "airport_code",
  "weekday",
  "hour_bucket",
  "planned_duration_seconds",
  "actual_duration_seconds",
  "planned_distance_m",
  "actual_distance_m",
  "pickup_wait_seconds",
  "driver_arrival_delta_seconds",
  "route_confidence_avg",
  "gps_confidence_avg",
  "reroute_count",
  "off_route_events",
  "prediction_events",
  "completed",
  "cancelled",
  "outcome",
  "sample_source",
]);

/** Key fragments that immediately reject a payload, regardless of value. */
const FORBIDDEN_KEY_FRAGMENTS = [
  "booking_id",
  "bookingid",
  "customer",
  "tenant_id",
  "tenantid",
  "company_id",
  "companyid",
  "company_name",
  "passenger_name",
  "name",
  "phone",
  "email",
  "address",
  "street",
  "lat",
  "lng",
  "lon",
  "coordinate",
  "location",
  "payment",
  "document",
  "note",
  "comment",
  "free_text",
  "flight_passenger",
];

const EMAIL_LIKE = /[^\s@]{1,64}@[^\s@]{1,64}\.[a-z]{2,}/i;
const PHONE_LIKE = /(\+|00)\d[\d ().\-]{6,}|\b\d[\d ().\-]{8,}\d\b/;
const COORD_PAIR_LIKE = /-?\d{1,3}\.\d{3,}\s*[,;]\s*-?\d{1,3}\.\d{3,}/;

// CLOUD-LEARN-1B: opaque anonymized partition tokens. These are treated as
// blind hashes only — never parsed, never mapped back to a readable identity,
// never logged in full. They are validated by shape and excluded from the
// PII value scan (a digit-heavy hash must not be mistaken for a phone number).
const SCOPE_HASH_KEYS = new Set(["tenant_scope_hash", "company_scope_hash"]);
const SCOPE_HASH_RE = /^[a-zA-Z0-9_-]{12,96}$/;

/**
 * Validates one opaque scope hash. Returns { ok, value } or
 * { ok:false, reason: "missing_scope" | "invalid_scope" }.
 */
function validateScopeHash(value) {
  if (value === undefined || value === null || value === "") {
    return { ok: false, reason: "missing_scope" };
  }
  if (typeof value !== "string" || !SCOPE_HASH_RE.test(value)) {
    return { ok: false, reason: "invalid_scope" };
  }
  return { ok: true, value };
}

/** Body copy without scope hash fields, for the PII value scan. */
function withoutScopeHashKeys(body) {
  return Object.fromEntries(
    Object.entries(body).filter(([key]) => !SCOPE_HASH_KEYS.has(key)),
  );
}

function keyLooksForbidden(key) {
  const normalized = String(key).toLowerCase();
  return FORBIDDEN_KEY_FRAGMENTS.some((fragment) =>
    normalized.includes(fragment),
  );
}

function valueLooksLikePii(value) {
  if (typeof value !== "string") return false;
  const text = value.trim();
  if (!text) return false;
  return (
    EMAIL_LIKE.test(text) || PHONE_LIKE.test(text) || COORD_PAIR_LIKE.test(text)
  );
}

/**
 * Scans a decoded JSON payload (depth-limited) and returns a rejection
 * reason if any forbidden key or PII-like string value is present.
 */
function findPiiViolation(node, depth = 0) {
  if (depth > 4 || node === null || node === undefined) return null;
  if (Array.isArray(node)) {
    for (const item of node) {
      const nested = findPiiViolation(item, depth + 1);
      if (nested) return nested;
    }
    return null;
  }
  if (typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      if (keyLooksForbidden(key)) return "forbidden_key";
      const nested = findPiiViolation(value, depth + 1);
      if (nested) return nested;
    }
    return null;
  }
  if (valueLooksLikePii(node)) return "pii_like_value";
  return null;
}

// ---------------------------------------------------------------------------
// HTTP helpers (matches Fluxidi navigation/dispatch worker CORS pattern)
// ---------------------------------------------------------------------------

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
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
// Diagnostics — bounded, no PII
// ---------------------------------------------------------------------------

function safeToken(value, maxLen = 64) {
  if (value === null || value === undefined) return "";
  const s = String(value).trim();
  if (!s) return "";
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

function logCloudLearn(endpoint, { result = "ok", country = "na", reason = "na" } = {}) {
  const safeEndpoint = safeToken(endpoint, 16) || "unknown";
  const safeResult = safeToken(result, 16) || "na";
  const safeCountry = safeToken(country, 4) || "na";
  const safeReason = safeToken(reason, 48) || "na";
  console.log(
    `[${DIAG_TAG}] endpoint=${safeEndpoint} result=${safeResult} country=${safeCountry} reason=${safeReason}`,
  );
}

function logNavComplexity(endpoint, { result = "ok", reason = "na" } = {}) {
  const safeEndpoint = safeToken(endpoint, 24) || "unknown";
  const safeResult = safeToken(result, 16) || "na";
  const safeReason = safeToken(reason, 48) || "na";
  console.log(
    `[${NAV_COMPLEXITY_DIAG_TAG}] endpoint=${safeEndpoint} result=${safeResult} reason=${safeReason}`,
  );
}

// ---------------------------------------------------------------------------
// Service-to-service auth (CLOUD-LEARN-3)
// ---------------------------------------------------------------------------

/**
 * Timing-resistant full-string comparison. Always scans the longest length so
 * neither a length mismatch nor a partial prefix match can short-circuit.
 */
function timingSafeEqualStr(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  let diff = ab.length === bb.length ? 0 : 1;
  const len = Math.max(ab.length, bb.length, 1);
  for (let i = 0; i < len; i += 1) {
    const x = i < ab.length ? ab[i] : 0;
    const y = i < bb.length ? bb[i] : 0;
    diff |= x ^ y;
  }
  return diff === 0;
}

/**
 * Requires `Authorization: Bearer <LEARNING_SERVICE_TOKEN>`. The token is
 * only ever accepted from the header — never query string or body. Neither
 * the expected token nor the presented value is logged or echoed.
 * Returns { ok:true } or { ok:false, status, error, reason }.
 */
function requireServiceAuth(request, env) {
  const expected = typeof env?.LEARNING_SERVICE_TOKEN === "string"
    ? env.LEARNING_SERVICE_TOKEN
    : "";
  if (!expected) {
    return {
      ok: false,
      status: 503,
      error: "service_auth_not_configured",
      reason: "service_auth_not_configured",
    };
  }
  const header = request.headers.get("authorization");
  if (!header) {
    return {
      ok: false,
      status: 401,
      error: "unauthorized",
      reason: "service_auth_missing",
    };
  }
  const prefix = "Bearer ";
  if (!header.startsWith(prefix)) {
    return {
      ok: false,
      status: 401,
      error: "unauthorized",
      reason: "service_auth_invalid",
    };
  }
  const presented = header.slice(prefix.length);
  if (!presented || !timingSafeEqualStr(presented, expected)) {
    return {
      ok: false,
      status: 401,
      error: "unauthorized",
      reason: "service_auth_invalid",
    };
  }
  return { ok: true };
}

// ---------------------------------------------------------------------------
// Parsing / validation
// ---------------------------------------------------------------------------

function normalizeCountry(value) {
  const code = safeToken(value, 4).toUpperCase();
  return ALLOWED_COUNTRIES.has(code) ? code : null;
}

function normalizeAirportCode(value) {
  const code = safeToken(value, 8).toUpperCase();
  return ALLOWED_AIRPORTS.has(code) ? code : null;
}

function clampInt(value, min, max) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, Math.round(n)));
}

function clampReal(value, min, max) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.max(min, Math.min(max, n));
}

function strictBool(value) {
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

/**
 * Validates and normalizes an ingest payload into a storable lesson.
 * Returns { ok:true, lesson, warnings } or { ok:false, error, reason }.
 */
function buildRideLesson(body) {
  // PII guard runs before anything else, on the raw payload.
  const piiViolation = findPiiViolation(
    Object.fromEntries(
      Object.entries(body).filter(([key]) => !INGEST_ALLOWED_KEYS.has(key)),
    ),
  );
  if (piiViolation) {
    return { ok: false, error: "Payload contains disallowed data", reason: piiViolation };
  }
  const unknownKeys = Object.keys(body).filter(
    (key) => !INGEST_ALLOWED_KEYS.has(key),
  );
  if (unknownKeys.length > 0) {
    return {
      ok: false,
      error: "Payload contains unknown fields (free-text/extra fields are not accepted)",
      reason: "unknown_fields",
    };
  }
  // Scope hashes are validated by strict shape, then excluded from the PII
  // value scan below (they are opaque tokens, not human-readable IDs).
  const tenantScope = validateScopeHash(body.tenant_scope_hash);
  if (!tenantScope.ok) {
    return { ok: false, error: "tenant_scope_hash is required and must be an opaque token", reason: tenantScope.reason };
  }
  const companyScope = validateScopeHash(body.company_scope_hash);
  if (!companyScope.ok) {
    return { ok: false, error: "company_scope_hash is required and must be an opaque token", reason: companyScope.reason };
  }

  const valueViolation = findPiiViolation(withoutScopeHashKeys(body));
  if (valueViolation) {
    return { ok: false, error: "Payload contains disallowed data", reason: valueViolation };
  }

  const country = normalizeCountry(body.country);
  if (!country) {
    return { ok: false, error: "country must be one of BE, NL, FR, ES, PT", reason: "invalid_country" };
  }

  const rideType = safeToken(body.ride_type, 16).toLowerCase();
  if (!ALLOWED_RIDE_TYPES.has(rideType)) {
    return { ok: false, error: "ride_type must be one of airport, local, intercity", reason: "invalid_ride_type" };
  }

  let airportCode = null;
  if (body.airport_code !== undefined && body.airport_code !== null && body.airport_code !== "") {
    airportCode = normalizeAirportCode(body.airport_code);
    if (!airportCode) {
      return { ok: false, error: "airport_code is not a supported launch airport", reason: "invalid_airport" };
    }
  }

  const outcome = safeToken(body.outcome, 16).toLowerCase();
  if (!ALLOWED_OUTCOMES.has(outcome)) {
    return {
      ok: false,
      error: "outcome must be one of good, late, early, cancelled, needs_review",
      reason: "invalid_outcome",
    };
  }

  const sampleSource = safeToken(body.sample_source, 24).toLowerCase();
  if (!ALLOWED_SAMPLE_SOURCES.has(sampleSource)) {
    return {
      ok: false,
      error: "sample_source must be one of driver_os, booking_worker, manual_test",
      reason: "invalid_sample_source",
    };
  }

  const warnings = [];

  let weekday = null;
  if (body.weekday !== undefined && body.weekday !== null) {
    weekday = clampInt(body.weekday, 1, 7);
    if (weekday === null || Number(body.weekday) < 1 || Number(body.weekday) > 7) {
      return { ok: false, error: "weekday must be an integer 1-7", reason: "invalid_weekday" };
    }
  }

  let hourBucket = null;
  if (body.hour_bucket !== undefined && body.hour_bucket !== null) {
    hourBucket = clampInt(body.hour_bucket, 0, 23);
    if (hourBucket === null || Number(body.hour_bucket) < 0 || Number(body.hour_bucket) > 23) {
      return { ok: false, error: "hour_bucket must be an integer 0-23", reason: "invalid_hour_bucket" };
    }
  }

  const plannedDurationS = clampInt(body.planned_duration_seconds, 0, 6 * 3600);
  const actualDurationS = clampInt(body.actual_duration_seconds, 0, 12 * 3600);
  const etaDeltaS =
    plannedDurationS !== null && actualDurationS !== null
      ? actualDurationS - plannedDurationS
      : null;
  if (etaDeltaS === null) {
    warnings.push("eta_delta_unavailable");
  }

  const completed = strictBool(body.completed);
  const cancelled = strictBool(body.cancelled);
  if (completed === null || cancelled === null) {
    return { ok: false, error: "completed and cancelled must be booleans", reason: "invalid_flags" };
  }

  const lesson = {
    id: `learn_${crypto.randomUUID().replaceAll("-", "")}`,
    created_at: new Date().toISOString(),
    tenant_scope_hash: tenantScope.value,
    company_scope_hash: companyScope.value,
    country,
    ride_type: rideType,
    airport_code: airportCode,
    weekday,
    hour_bucket: hourBucket,
    planned_duration_seconds: plannedDurationS,
    actual_duration_seconds: actualDurationS,
    eta_delta_seconds: etaDeltaS,
    planned_distance_m: clampInt(body.planned_distance_m, 0, 1000000),
    actual_distance_m: clampInt(body.actual_distance_m, 0, 1500000),
    pickup_wait_seconds: clampInt(body.pickup_wait_seconds, 0, 4 * 3600),
    driver_arrival_delta_seconds: clampInt(
      body.driver_arrival_delta_seconds,
      -2 * 3600,
      4 * 3600,
    ),
    route_confidence_avg: clampReal(body.route_confidence_avg, 0, 100),
    gps_confidence_avg: clampReal(body.gps_confidence_avg, 0, 100),
    reroute_count: clampInt(body.reroute_count, 0, 50),
    off_route_events: clampInt(body.off_route_events, 0, 200),
    prediction_events: clampInt(body.prediction_events, 0, 500),
    completed: completed ? 1 : 0,
    cancelled: cancelled ? 1 : 0,
    outcome,
    sample_source: sampleSource,
  };

  return { ok: true, lesson, warnings };
}

// ---------------------------------------------------------------------------
// Storage abstraction — D1 when bound, dry-run otherwise (no KV for analytics)
// ---------------------------------------------------------------------------

function storageMode(env) {
  return env && env.LEARNING_DB ? "d1" : "dry_run";
}

async function storeRideLesson(env, lesson) {
  if (storageMode(env) !== "d1") {
    return { ok: true, storage: "dry_run", dry_run_storage: true };
  }
  try {
    await env.LEARNING_DB.prepare(
      `INSERT INTO ride_lessons (
         id, created_at, tenant_scope_hash, company_scope_hash,
         country, ride_type, airport_code, weekday, hour_bucket,
         planned_duration_seconds, actual_duration_seconds, eta_delta_seconds,
         planned_distance_m, actual_distance_m, pickup_wait_seconds,
         driver_arrival_delta_seconds, route_confidence_avg, gps_confidence_avg,
         reroute_count, off_route_events, prediction_events,
         completed, cancelled, outcome, sample_source
       ) VALUES (
         ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15,
         ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23, ?24, ?25
       )`,
    )
      .bind(
        lesson.id,
        lesson.created_at,
        lesson.tenant_scope_hash,
        lesson.company_scope_hash,
        lesson.country,
        lesson.ride_type,
        lesson.airport_code,
        lesson.weekday,
        lesson.hour_bucket,
        lesson.planned_duration_seconds,
        lesson.actual_duration_seconds,
        lesson.eta_delta_seconds,
        lesson.planned_distance_m,
        lesson.actual_distance_m,
        lesson.pickup_wait_seconds,
        lesson.driver_arrival_delta_seconds,
        lesson.route_confidence_avg,
        lesson.gps_confidence_avg,
        lesson.reroute_count,
        lesson.off_route_events,
        lesson.prediction_events,
        lesson.completed,
        lesson.cancelled,
        lesson.outcome,
        lesson.sample_source,
      )
      .run();
    return { ok: true, storage: "d1", dry_run_storage: false };
  } catch (_) {
    return { ok: false, storage: "d1", error: "d1_insert_failed" };
  }
}

// ---------------------------------------------------------------------------
// GET /health
// ---------------------------------------------------------------------------

function handleHealth(env) {
  logCloudLearn("health", { result: "ok", reason: storageMode(env) });
  return jsonResponse({
    ok: true,
    service: SERVICE_NAME,
    version: SERVICE_VERSION,
    storage: storageMode(env),
  });
}

// ---------------------------------------------------------------------------
// POST /ride-lessons/ingest
// ---------------------------------------------------------------------------

async function handleIngest(request, env) {
  const parsed = await readJsonBody(request);
  if (!parsed.ok) {
    logCloudLearn("ingest", { result: "error", reason: "invalid_body" });
    return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
  }

  const built = buildRideLesson(parsed.body);
  if (!built.ok) {
    logCloudLearn("ingest", { result: "error", reason: built.reason });
    return jsonResponse({ ok: false, error: built.error }, 400);
  }

  const stored = await storeRideLesson(env, built.lesson);
  if (!stored.ok) {
    logCloudLearn("ingest", {
      result: "error",
      country: built.lesson.country,
      reason: stored.error,
    });
    return jsonResponse({ ok: false, error: "Failed to store ride lesson" }, 500);
  }

  logCloudLearn("ingest", {
    result: "ok",
    country: built.lesson.country,
    reason: `stored_${stored.storage}`,
  });

  return jsonResponse({
    ok: true,
    accepted: true,
    lesson_id: built.lesson.id,
    storage: stored.storage,
    warnings: built.warnings,
  });
}

// ---------------------------------------------------------------------------
// POST /insights/summary
// ---------------------------------------------------------------------------

function unavailableInsights(reason, sampleCount = 0) {
  return {
    ok: true,
    available: false,
    reason,
    minimum_samples_required: MIN_SAMPLES_FOR_INSIGHTS,
    sample_count: sampleCount,
    insights: [],
  };
}

async function handleInsightsSummary(request, env) {
  const parsed = await readJsonBody(request);
  if (!parsed.ok) {
    logCloudLearn("insights", { result: "error", reason: "invalid_body" });
    return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
  }
  const body = parsed.body;

  // CLOUD-LEARN-1B: no global summary path — tenant + company scope are
  // mandatory and every query is partitioned by both.
  const tenantScope = validateScopeHash(body.tenant_scope_hash);
  if (!tenantScope.ok) {
    logCloudLearn("insights", { result: "error", reason: tenantScope.reason });
    return jsonResponse(
      { ok: false, error: "tenant_scope_hash is required and must be an opaque token" },
      400,
    );
  }
  const companyScope = validateScopeHash(body.company_scope_hash);
  if (!companyScope.ok) {
    logCloudLearn("insights", { result: "error", reason: companyScope.reason });
    return jsonResponse(
      { ok: false, error: "company_scope_hash is required and must be an opaque token" },
      400,
    );
  }

  const country = normalizeCountry(body.country);
  if (!country) {
    logCloudLearn("insights", { result: "error", reason: "invalid_country" });
    return jsonResponse(
      { ok: false, error: "country must be one of BE, NL, FR, ES, PT" },
      400,
    );
  }

  let airportCode = null;
  if (body.airport_code !== undefined && body.airport_code !== null && body.airport_code !== "") {
    airportCode = normalizeAirportCode(body.airport_code);
    if (!airportCode) {
      logCloudLearn("insights", { result: "error", country, reason: "invalid_airport" });
      return jsonResponse(
        { ok: false, error: "airport_code is not a supported launch airport" },
        400,
      );
    }
  }

  let rideType = null;
  if (body.ride_type !== undefined && body.ride_type !== null && body.ride_type !== "") {
    rideType = safeToken(body.ride_type, 16).toLowerCase();
    if (!ALLOWED_RIDE_TYPES.has(rideType)) {
      logCloudLearn("insights", { result: "error", country, reason: "invalid_ride_type" });
      return jsonResponse(
        { ok: false, error: "ride_type must be one of airport, local, intercity" },
        400,
      );
    }
  }

  const weekday = body.weekday === undefined || body.weekday === null
    ? null
    : clampInt(body.weekday, 1, 7);
  const hourBucket = body.hour_bucket === undefined || body.hour_bucket === null
    ? null
    : clampInt(body.hour_bucket, 0, 23);

  if (storageMode(env) !== "d1") {
    logCloudLearn("insights", {
      result: "ok",
      country,
      reason: "learning_store_not_connected",
    });
    return jsonResponse(unavailableInsights("learning_store_not_connected"));
  }

  try {
    const conditions = [
      "tenant_scope_hash = ?1",
      "company_scope_hash = ?2",
      "country = ?3",
    ];
    const bindings = [tenantScope.value, companyScope.value, country];
    if (rideType) {
      bindings.push(rideType);
      conditions.push(`ride_type = ?${bindings.length}`);
    }
    if (airportCode) {
      bindings.push(airportCode);
      conditions.push(`airport_code = ?${bindings.length}`);
    }
    if (weekday !== null) {
      bindings.push(weekday);
      conditions.push(`weekday = ?${bindings.length}`);
    }
    if (hourBucket !== null) {
      bindings.push(hourBucket);
      conditions.push(`hour_bucket = ?${bindings.length}`);
    }

    const row = await env.LEARNING_DB.prepare(
      `SELECT
         COUNT(*) AS sample_count,
         AVG(eta_delta_seconds) AS avg_eta_delta_seconds,
         AVG(pickup_wait_seconds) AS avg_pickup_wait_seconds,
         AVG(route_confidence_avg) AS avg_route_confidence,
         AVG(gps_confidence_avg) AS avg_gps_confidence,
         AVG(reroute_count) AS avg_reroute_count
       FROM ride_lessons
       WHERE ${conditions.join(" AND ")}`,
    )
      .bind(...bindings)
      .first();

    const sampleCount = Number(row?.sample_count) || 0;
    if (sampleCount < MIN_SAMPLES_FOR_INSIGHTS) {
      logCloudLearn("insights", { result: "ok", country, reason: "not_enough_samples" });
      return jsonResponse(unavailableInsights("not_enough_samples", sampleCount));
    }

    const round1 = (value) =>
      Number.isFinite(Number(value)) ? Math.round(Number(value) * 10) / 10 : null;
    const avgEtaDelta = round1(row.avg_eta_delta_seconds) ?? 0;
    const avgPickupWait = round1(row.avg_pickup_wait_seconds) ?? 0;

    // Deterministic buffer suggestion: absorb the average lateness plus half
    // of the typical pickup wait, capped at 30 minutes.
    const recommendedBufferSeconds = Math.max(
      0,
      Math.min(1800, Math.round(Math.max(0, avgEtaDelta) + avgPickupWait / 2)),
    );

    logCloudLearn("insights", { result: "ok", country, reason: "aggregates" });
    return jsonResponse({
      ok: true,
      available: true,
      reason: "ok",
      minimum_samples_required: MIN_SAMPLES_FOR_INSIGHTS,
      sample_count: sampleCount,
      insights: [
        { metric: "avg_eta_delta_seconds", value: avgEtaDelta },
        { metric: "avg_pickup_wait_seconds", value: avgPickupWait },
        { metric: "avg_route_confidence", value: round1(row.avg_route_confidence) },
        { metric: "avg_gps_confidence", value: round1(row.avg_gps_confidence) },
        { metric: "avg_reroute_count", value: round1(row.avg_reroute_count) },
        { metric: "recommended_buffer_seconds", value: recommendedBufferSeconds },
      ],
    });
  } catch (_) {
    logCloudLearn("insights", { result: "error", country, reason: "d1_query_failed" });
    return jsonResponse({ ok: false, error: "Failed to query learning store" }, 500);
  }
}

// ---------------------------------------------------------------------------
// NAV-AI-3: admin dry-run nav complexity ingest (sanitized events only)
// ---------------------------------------------------------------------------

async function storeNavComplexityEvent(env, row) {
  if (storageMode(env) !== "d1") {
    return { ok: true, storage: "dry_run", dry_run_storage: true };
  }
  try {
    await env.LEARNING_DB.prepare(
      `INSERT INTO nav_complexity_events (
         id, created_at, reason_code, severity, confidence_bucket,
         snap_dist_bucket, speed_bucket, maneuver_type, maneuver_modifier,
         prediction_repeated, trust_bearing, trust_instruction,
         dry_run, source, raw_json
       ) VALUES (
         ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15
       )`,
    )
      .bind(
        row.id,
        row.created_at,
        row.reason_code,
        row.severity,
        row.confidence_bucket,
        row.snap_dist_bucket,
        row.speed_bucket,
        row.maneuver_type,
        row.maneuver_modifier,
        row.prediction_repeated,
        row.trust_bearing,
        row.trust_instruction,
        row.dry_run,
        row.source,
        row.raw_json,
      )
      .run();
    return { ok: true, storage: "d1", dry_run_storage: false };
  } catch (_) {
    return { ok: false, storage: "d1", error: "d1_insert_failed" };
  }
}

async function handleNavComplexityIngestDryRun(request, env) {
  const parsed = await readJsonBody(request);
  if (!parsed.ok) {
    logNavComplexity("ingest-dry-run", { result: "error", reason: "invalid_body" });
    return jsonResponse({ ok: false, error: parsed.error }, parsed.status || 400);
  }

  const built = validateNavComplexityIngestRequest(parsed.body);
  if (!built.ok) {
    logNavComplexity("ingest-dry-run", { result: "error", reason: built.reason });
    return jsonResponse({ ok: false, error: built.error, reason: built.reason }, 400);
  }

  if (!built.dryRunStore) {
    logNavComplexity("ingest-dry-run", { result: "ok", reason: "validate_only" });
    return jsonResponse({
      ok: true,
      advisoryOnly: true,
      validated: true,
      stored: false,
      dryRunStore: false,
      storage: "validate_only",
      reason_code: built.sanitized.reasonCode,
    });
  }

  const row = navComplexityEventToDbRow(built.sanitized, {
    source: built.source,
    dryRun: true,
  });

  const stored = await storeNavComplexityEvent(env, row);
  if (!stored.ok) {
    logNavComplexity("ingest-dry-run", { result: "error", reason: stored.error });
    return jsonResponse({ ok: false, error: "Failed to store nav complexity event" }, 500);
  }

  logNavComplexity("ingest-dry-run", {
    result: "ok",
    reason: `stored_${stored.storage}`,
  });

  return jsonResponse({
    ok: true,
    advisoryOnly: true,
    validated: true,
    stored: true,
    dryRunStore: true,
    storage: stored.storage,
    event_id: row.id,
    dry_run: true,
    source: built.source,
    reason_code: row.reason_code,
  });
}

async function handleNavComplexityRecent(_request, env) {
  if (storageMode(env) !== "d1") {
    logNavComplexity("recent", { result: "ok", reason: "learning_store_not_connected" });
    return jsonResponse({
      ok: true,
      advisoryOnly: true,
      count: 0,
      storage: "dry_run",
      events: [],
    });
  }

  try {
    const result = await env.LEARNING_DB.prepare(
      `SELECT
         id, created_at, reason_code, severity, confidence_bucket,
         snap_dist_bucket, speed_bucket, maneuver_type, maneuver_modifier,
         prediction_repeated, trust_bearing, trust_instruction,
         dry_run, source, raw_json
       FROM nav_complexity_events
       ORDER BY created_at DESC
       LIMIT 20`,
    ).all();

    const rows = Array.isArray(result?.results) ? result.results : [];
    logNavComplexity("recent", { result: "ok", reason: `rows_${rows.length}` });
    return jsonResponse({
      ok: true,
      advisoryOnly: true,
      count: rows.length,
      storage: "d1",
      events: rows.map((row) => publicNavComplexityRow(row)),
    });
  } catch (_) {
    logNavComplexity("recent", { result: "error", reason: "d1_query_failed" });
    return jsonResponse({ ok: false, error: "Failed to query nav complexity events" }, 500);
  }
}

async function handleNavComplexityDeleteTestData(_request, env) {
  if (storageMode(env) !== "d1") {
    logNavComplexity("delete-test", { result: "ok", reason: "learning_store_not_connected" });
    return jsonResponse({
      ok: true,
      advisoryOnly: true,
      deleted: 0,
      storage: "dry_run",
    });
  }

  try {
    const result = await env.LEARNING_DB.prepare(
      `DELETE FROM nav_complexity_events
       WHERE dry_run = 1
          OR source IN ('test', 'dry_run', 'manual_test', 'flutter_manual_test')`,
    ).run();
    const deleted = Number(result?.meta?.changes) || 0;
    logNavComplexity("delete-test", { result: "ok", reason: `deleted_${deleted}` });
    return jsonResponse({
      ok: true,
      advisoryOnly: true,
      deleted,
      storage: "d1",
    });
  } catch (_) {
    logNavComplexity("delete-test", { result: "error", reason: "d1_delete_failed" });
    return jsonResponse({ ok: false, error: "Failed to delete test nav complexity data" }, 500);
  }
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
        return handleHealth(env);
      }

      if (url.pathname === "/ride-lessons/ingest") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        // Auth before body read/validation/D1 — no unauthenticated probing.
        const auth = requireServiceAuth(request, env);
        if (!auth.ok) {
          logCloudLearn("ingest", { result: "error", reason: auth.reason });
          return jsonResponse({ ok: false, error: auth.error }, auth.status);
        }
        return await handleIngest(request, env);
      }

      if (url.pathname === "/insights/summary") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        // Auth before body read/validation/D1 — no unauthenticated probing.
        const auth = requireServiceAuth(request, env);
        if (!auth.ok) {
          logCloudLearn("insights", { result: "error", reason: auth.reason });
          return jsonResponse({ ok: false, error: auth.error }, auth.status);
        }
        return await handleInsightsSummary(request, env);
      }

      if (url.pathname === "/admin/nav-complexity-events/ingest-dry-run") {
        if (request.method !== "POST") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        const auth = requireServiceAuth(request, env);
        if (!auth.ok) {
          logNavComplexity("ingest-dry-run", { result: "error", reason: auth.reason });
          return jsonResponse({ ok: false, error: auth.error }, auth.status);
        }
        return await handleNavComplexityIngestDryRun(request, env);
      }

      if (url.pathname === "/admin/nav-complexity-events/recent") {
        if (request.method !== "GET") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        const auth = requireServiceAuth(request, env);
        if (!auth.ok) {
          logNavComplexity("recent", { result: "error", reason: auth.reason });
          return jsonResponse({ ok: false, error: auth.error }, auth.status);
        }
        return await handleNavComplexityRecent(request, env);
      }

      if (url.pathname === "/admin/nav-complexity-events/test-data") {
        if (request.method !== "DELETE") {
          return jsonResponse({ ok: false, error: "Method Not Allowed" }, 405);
        }
        const auth = requireServiceAuth(request, env);
        if (!auth.ok) {
          logNavComplexity("delete-test", { result: "error", reason: auth.reason });
          return jsonResponse({ ok: false, error: auth.error }, auth.status);
        }
        return await handleNavComplexityDeleteTestData(request, env);
      }

      return jsonResponse({ ok: false, error: "Not Found", path: url.pathname }, 404);
    } catch (_) {
      logCloudLearn("unknown", { result: "error", reason: "internal_error" });
      return jsonResponse({ ok: false, error: "Internal error" }, 500);
    }
  },
};
