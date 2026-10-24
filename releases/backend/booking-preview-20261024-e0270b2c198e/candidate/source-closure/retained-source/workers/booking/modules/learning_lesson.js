/* CLOUD-LEARN-4B: dry-run anonymized learning-lesson preview builder.
 *
 * Pure module: no network, no KV/D1, no env, no logging inside the builder,
 * never mutates the booking record, never spreads/clones/forwards `rec`.
 *
 * The preview mirrors the Learning Worker ride-lesson field allowlist
 * (workers/learning) but is NEVER sent anywhere in 4B. Scope hashes are
 * fixed dry-run placeholders because no LEARNING_SCOPE_HASH_SECRET exists
 * yet; they satisfy the Learning Worker scope regex on purpose so a later
 * real producer can reuse the shape, but they must never be used for real
 * ingest.
 *
 * PII policy: every value in `fields` is derived from an explicit scalar
 * read below. Forbidden and never read: booking_id, booking references,
 * raw tenant/company ids, customer name/email/phone, pickup/dropoff
 * addresses or labels, lat/lng/coordinates, payment/document/invoice ids,
 * vehicle plates, driver names, free-text notes.
 */

import { safeStr } from "./parsing_utils.js";

// Keep in sync with the Learning Worker ingest allowlist.
export const LEARNING_LESSON_ALLOWED_FIELD_KEYS = Object.freeze([
  "tenant_scope_hash",
  "company_scope_hash",
  "country",
  "airport_code",
  "ride_type",
  "weekday",
  "hour_bucket",
  "planned_duration_seconds",
  "actual_duration_seconds",
  "pickup_wait_seconds",
  "route_confidence_avg",
  "gps_confidence_avg",
  "reroute_count",
  "outcome",
  "sample_source",
]);

// Dry-run placeholders only (no HMAC secret exists in 4B). They match the
// Learning Worker SCOPE_HASH_RE (/^[a-zA-Z0-9_-]{12,96}$/) but are obvious
// fakes and must never reach real ingest.
const DRY_RUN_TENANT_SCOPE_HASH = "dryRunTenantScope_0001";
const DRY_RUN_COMPANY_SCOPE_HASH = "dryRunCompanyScope_0001";

const LEARNING_ALLOWED_COUNTRIES = new Set(["BE", "NL", "FR", "ES", "PT"]);
const AIRPORT_CODE_RE = /^[A-Z0-9]{3,8}$/;

function _nestedObject(rec, key) {
  const value = rec && typeof rec === "object" ? rec[key] : null;
  return value && typeof value === "object" && !Array.isArray(value) ? value : null;
}

function _firstSafeToken(values, maxLen) {
  for (const value of values) {
    const text = safeStr(value, maxLen);
    if (text) return text;
  }
  return "";
}

/* Country: ISO-2 uppercase from explicit country scalars only; restricted to
 * the Learning Worker country allowlist. Never parsed from addresses. */
function _deriveLearningCountry(rec, booking, payload) {
  const raw = _firstSafeToken(
    [
      rec?.reporting_region,
      rec?.reportingRegion,
      rec?.country_code,
      rec?.countryCode,
      rec?.country,
      booking?.country_code,
      booking?.countryCode,
      booking?.country,
      payload?.country_code,
      payload?.countryCode,
    ],
    64,
  );
  if (!raw) return { value: null, warning: null };
  const normalized = raw.toUpperCase().replace(/[^A-Z]/g, "");
  if (normalized.length !== 2) return { value: null, warning: "country_not_iso2" };
  if (!LEARNING_ALLOWED_COUNTRIES.has(normalized)) {
    return { value: null, warning: "country_not_in_allowlist" };
  }
  return { value: normalized, warning: null };
}

/* Airport code: explicit IATA/code scalar fields only. Never airport names,
 * address labels, or coordinates. */
function _deriveLearningAirportCode(rec, booking, payload) {
  const raw = _firstSafeToken(
    [
      rec?.airport_iata,
      rec?.airportIata,
      rec?.airport_code,
      rec?.airportCode,
      booking?.airport_iata,
      booking?.airportIata,
      booking?.airport_code,
      booking?.airportCode,
      payload?.airport_iata,
      payload?.airportIata,
      payload?.airport_code,
      payload?.airportCode,
    ],
    16,
  );
  if (!raw) return { value: null, warning: null };
  const normalized = raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (!AIRPORT_CODE_RE.test(normalized)) {
    return { value: null, warning: "airport_code_invalid_format" };
  }
  return { value: normalized, warning: null };
}

/* Ride type: conservative mapping onto the Learning Worker's
 * airport/local/intercity vocabulary. null when uncertain. */
function _deriveLearningRideType(rec, booking, payload, airportCode) {
  const tokens = [
    rec?.service_bucket,
    rec?.serviceBucket,
    booking?.service_bucket,
    booking?.serviceBucket,
    rec?.ride_type,
    rec?.rideType,
    booking?.ride_type,
    booking?.rideType,
    payload?.ride_type,
    payload?.rideType,
    rec?.service,
    rec?.service_type,
    rec?.serviceType,
    booking?.service,
    booking?.service_type,
    booking?.serviceType,
    payload?.service,
    rec?.trip_type,
    rec?.tripType,
    booking?.trip_type,
    booking?.tripType,
  ]
    .map((value) => safeStr(value, 64).toLowerCase().replaceAll("-", "_"))
    .filter((value) => !!value);
  const hasAirportToken = tokens.some(
    (token) => token.includes("airport") || token.includes("luchthaven"),
  );
  if (airportCode || hasAirportToken) return "airport";
  if (tokens.some((token) => token.includes("intercity"))) return "intercity";
  const LOCAL_TOKENS = new Set(["direct", "direct_trip", "street_hail", "taxi", "local"]);
  if (tokens.some((token) => LOCAL_TOKENS.has(token))) return "local";
  return null;
}

/* Pickup ISO: same scalar fields the read model uses
 * (bookingPickupIsoFromRecord in booking_read_model.js). */
function _pickupIsoFromRecord(rec, booking, payload) {
  const quote = _nestedObject(rec, "quote");
  return _firstSafeToken(
    [
      booking?.pickupStartIso,
      booking?.pickup_iso,
      quote?.pickup_iso,
      payload?.pickup_iso,
      payload?.pickupIso,
    ],
    80,
  );
}

function _parseUtcMillis(isoText) {
  const text = safeStr(isoText, 80);
  if (!text) return null;
  const millis = Date.parse(text);
  return Number.isFinite(millis) ? millis : null;
}

/* Weekday 1 (Mon) .. 7 (Sun), never 0, per Learning Worker contract. */
function _weekdayFromMillis(millis) {
  const jsDay = new Date(millis).getUTCDay(); // 0=Sun..6=Sat
  return ((jsDay + 6) % 7) + 1;
}

function _clampIntOrNull(value, min, max) {
  const num = Number(value);
  if (!Number.isFinite(num)) return null;
  const rounded = Math.round(num);
  if (rounded < min || rounded > max) return null;
  return rounded;
}

/* Planned duration: only persisted explicit duration scalars; the quote
 * route pipeline does not reliably persist one, so null is common. */
function _derivePlannedDurationSeconds(rec, booking) {
  const quote = _nestedObject(rec, "quote");
  const quoteRoute = _nestedObject(quote || {}, "route");
  const candidates = [
    booking?.duration_seconds,
    booking?.durationSeconds,
    rec?.duration_seconds,
    rec?.durationSeconds,
    quote?.duration_seconds,
    quote?.durationSeconds,
    quoteRoute?.duration_seconds,
    quoteRoute?.durationSeconds,
  ];
  for (const candidate of candidates) {
    if (candidate === undefined || candidate === null) continue;
    const clamped = _clampIntOrNull(candidate, 60, 172800);
    if (clamped !== null) return clamped;
  }
  return null;
}

/* Actual duration: started/completed record scalars only; null when either
 * side is missing or the delta is implausible. */
function _deriveActualDurationSeconds(rec, booking) {
  const startedMillis = _parseUtcMillis(
    _firstSafeToken(
      [rec?.started_at, rec?.startedAt, booking?.started_at, booking?.startedAt],
      80,
    ),
  );
  const completedMillis = _parseUtcMillis(
    _firstSafeToken(
      [rec?.completed_at, rec?.completedAt, booking?.completed_at, booking?.completedAt],
      80,
    ),
  );
  if (startedMillis === null || completedMillis === null) return null;
  const seconds = Math.round((completedMillis - startedMillis) / 1000);
  if (seconds <= 0 || seconds > 172800) return null;
  return seconds;
}

/**
 * Builds a dry-run anonymized ride-lesson preview from a booking record.
 * Pure allowlist extraction: reads a fixed set of scalar fields and returns
 * only LEARNING_LESSON_ALLOWED_FIELD_KEYS. Never returns identifiers.
 *
 * options: { nowIso } — completion fallback timestamp for weekday/hour.
 */
export function buildLearningRideLessonPreview(rec, options = {}) {
  const record = rec && typeof rec === "object" && !Array.isArray(rec) ? rec : {};
  const booking = _nestedObject(record, "booking") || {};
  const payload = _nestedObject(record, "payload") || {};
  const warnings = [];

  const countryResult = _deriveLearningCountry(record, booking, payload);
  if (countryResult.warning) warnings.push(countryResult.warning);

  const airportResult = _deriveLearningAirportCode(record, booking, payload);
  if (airportResult.warning) warnings.push(airportResult.warning);

  const rideType = _deriveLearningRideType(record, booking, payload, airportResult.value);

  // Time basis: pickup ISO preferred; completion timestamp fallback.
  const pickupMillis = _parseUtcMillis(_pickupIsoFromRecord(record, booking, payload));
  const completionMillis =
    _parseUtcMillis(
      _firstSafeToken(
        [record?.completed_at, record?.completedAt, booking?.completed_at],
        80,
      ),
    ) ?? _parseUtcMillis(options?.nowIso);
  const timeBasisMillis = pickupMillis ?? completionMillis;
  if (timeBasisMillis === null) warnings.push("no_parseable_timestamp");

  const fields = {
    tenant_scope_hash: DRY_RUN_TENANT_SCOPE_HASH,
    company_scope_hash: DRY_RUN_COMPANY_SCOPE_HASH,
    country: countryResult.value,
    airport_code: airportResult.value,
    ride_type: rideType,
    weekday: timeBasisMillis === null ? null : _weekdayFromMillis(timeBasisMillis),
    hour_bucket:
      timeBasisMillis === null ? null : new Date(timeBasisMillis).getUTCHours(),
    planned_duration_seconds: _derivePlannedDurationSeconds(record, booking),
    actual_duration_seconds: _deriveActualDurationSeconds(record, booking),
    // No true pickup-arrival wait source exists backend-side in 4B; paid
    // in-ride waiting time is a different concept and must not be used.
    pickup_wait_seconds: null,
    // Nav-telemetry metrics have no backend producer yet (4A audit).
    route_confidence_avg: null,
    gps_confidence_avg: null,
    reroute_count: null,
    outcome: "good",
    sample_source: "booking_worker_status_update",
  };

  const missingFields = LEARNING_LESSON_ALLOWED_FIELD_KEYS.filter(
    (key) => fields[key] === null,
  );
  return {
    ok: true,
    mode: "dry_run",
    fields,
    presentCount: LEARNING_LESSON_ALLOWED_FIELD_KEYS.length - missingFields.length,
    missingCount: missingFields.length,
    missingFields,
    warnings,
  };
}

/* Development self-check: true only when `fields` carries exactly the
 * allowlisted keys. Not wired to any endpoint. */
export function learningLessonPreviewHasOnlyAllowedKeys(preview) {
  const fields = preview?.fields;
  if (!fields || typeof fields !== "object" || Array.isArray(fields)) return false;
  const keys = Object.keys(fields);
  if (keys.length !== LEARNING_LESSON_ALLOWED_FIELD_KEYS.length) return false;
  return keys.every((key) => LEARNING_LESSON_ALLOWED_FIELD_KEYS.includes(key));
}

/* Bounded dry-run logger. Logs derived aggregate tokens only — never ids,
 * scope hashes, payloads, or free text. Kept outside the pure builder. */
export function logLearningRideLessonDryRun(preview) {
  try {
    if (!preview || preview.ok !== true || !learningLessonPreviewHasOnlyAllowedKeys(preview)) {
      console.log("[CLOUD_LEARN_4] mode=dry_run result=error reason=invalid_preview_shape");
      return;
    }
    const country = safeStr(preview.fields.country, 2) || "na";
    const rideType = safeStr(preview.fields.ride_type, 16) || "na";
    const present = Number.isFinite(Number(preview.presentCount))
      ? Math.round(Number(preview.presentCount))
      : 0;
    const missing = Number.isFinite(Number(preview.missingCount))
      ? Math.round(Number(preview.missingCount))
      : 0;
    console.log(
      `[CLOUD_LEARN_4] mode=dry_run result=ok country=${country} ride_type=${rideType} fields=${present} missing=${missing}`,
    );
  } catch (_) {
    console.log("[CLOUD_LEARN_4] mode=dry_run result=error reason=log_helper_exception");
  }
}
