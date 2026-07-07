/**
 * NAV-AI-3: sanitized nav_complexity_event schema validation.
 * Shared by Learning Worker admin dry-run ingest and offline analyzer tooling.
 */

export const FORBIDDEN_PII_KEYS = [
  "latitude",
  "longitude",
  "lat",
  "lng",
  "lon",
  "address",
  "bookingId",
  "booking_id",
  "customerId",
  "customer_id",
  "driverId",
  "driver_id",
  "phone",
  "email",
  "name",
  "street",
  "coordinate",
  "location",
  "passenger",
  "payment",
  "document",
  "free_text",
  "note",
  "comment",
];

export const ALLOWED_EVENT_KEYS = new Set([
  "type",
  "version",
  "app",
  "platform",
  "reasonCode",
  "severity",
  "confidenceBucket",
  "snapDistBucket",
  "speedBucket",
  "maneuverType",
  "maneuverModifier",
  "predictionRepeated",
  "trustBearing",
  "trustInstruction",
  "occurredAtMinuteBucket",
  "sessionHash",
]);

export const ALLOWED_INGEST_WRAPPER_KEYS = new Set([
  "dryRunStore",
  "source",
  "event",
]);

export const ALLOWED_SOURCES = new Set(["test", "manual_test", "dry_run"]);

export const ALLOWED_REASON_CODES = new Set([
  "low_confidence",
  "offroute_uncertain",
  "repeated_prediction",
  "ambiguous_instruction",
  "high_snap_distance",
  "heading_route_conflict",
  "dense_maneuver_area",
]);

export const ALLOWED_SEVERITIES = new Set(["info", "warning"]);
export const ALLOWED_CONFIDENCE_BUCKETS = new Set([
  "0-20",
  "20-40",
  "40-60",
  "60-80",
  "80-100",
  "unknown",
]);
export const ALLOWED_SNAP_DIST_BUCKETS = new Set([
  "0-5",
  "5-15",
  "15-30",
  "30+",
  "unknown",
]);
export const ALLOWED_SPEED_BUCKETS = new Set([
  "stopped",
  "slow",
  "city",
  "urban",
  "fast",
  "unknown",
]);
export const ALLOWED_MANEUVER_TYPES = new Set([
  "turn",
  "roundabout",
  "arrive",
  "depart",
  "unknown",
]);
export const ALLOWED_MANEUVER_MODIFIERS = new Set([
  "left",
  "right",
  "straight",
  "uturn",
  "unknown",
]);

/**
 * @param {unknown} value
 * @param {number} maxLen
 */
export function safeToken(value, maxLen = 64) {
  if (value === null || value === undefined) return "";
  const s = String(value).trim();
  if (!s) return "";
  return s.length > maxLen ? s.slice(0, maxLen) : s;
}

/**
 * @param {string} key
 * @param {Set<string>|null} allowedKeys
 */
function keyIsForbidden(key, allowedKeys = null) {
  if (allowedKeys && allowedKeys.has(key)) return false;
  const normalized = String(key).toLowerCase();
  return FORBIDDEN_PII_KEYS.some((forbidden) => {
    const fragment = forbidden.toLowerCase();
    return (
      normalized === fragment ||
      normalized.endsWith(`_${fragment}`) ||
      normalized.startsWith(`${fragment}_`) ||
      normalized.includes(`_${fragment}_`)
    );
  });
}

/**
 * @param {unknown} node
 * @param {number} depth
 * @param {Set<string>|null} allowedKeys
 * @returns {string|null}
 */
export function findForbiddenPiiKey(node, depth = 0, allowedKeys = null) {
  if (depth > 4 || node === null || node === undefined) return null;
  if (Array.isArray(node)) {
    for (const item of node) {
      const nested = findForbiddenPiiKey(item, depth + 1, allowedKeys);
      if (nested) return nested;
    }
    return null;
  }
  if (typeof node === "object") {
    for (const key of Object.keys(node)) {
      if (keyIsForbidden(key, allowedKeys)) return "forbidden_key";
      const nested = findForbiddenPiiKey(node[key], depth + 1, allowedKeys);
      if (nested) return nested;
    }
  }
  return null;
}

/**
 * @param {unknown} value
 * @returns {boolean|null}
 */
function strictBool(value) {
  if (value === true || value === false) return value;
  return null;
}

/**
 * @param {unknown} raw
 * @returns {{ ok: true, event: Record<string, unknown>, sanitized: Record<string, unknown> } | { ok: false, error: string, reason: string }}
 */
export function validateNavComplexityEvent(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return {
      ok: false,
      error: "event must be a JSON object",
      reason: "invalid_event_shape",
    };
  }

  const body = /** @type {Record<string, unknown>} */ (raw);
  const piiViolation = findForbiddenPiiKey(body, 0, ALLOWED_EVENT_KEYS);
  if (piiViolation) {
    return {
      ok: false,
      error: "Payload contains disallowed data",
      reason: piiViolation,
    };
  }

  const unknownKeys = Object.keys(body).filter((key) => !ALLOWED_EVENT_KEYS.has(key));
  if (unknownKeys.length > 0) {
    return {
      ok: false,
      error: "event contains unknown fields",
      reason: "unknown_fields",
    };
  }

  if (body.type !== "nav_complexity_event") {
    return {
      ok: false,
      error: "event.type must be nav_complexity_event",
      reason: "invalid_type",
    };
  }

  const version = Number(body.version);
  if (!Number.isFinite(version) || version !== 1) {
    return {
      ok: false,
      error: "event.version must be 1",
      reason: "invalid_version",
    };
  }

  const reasonCode = safeToken(body.reasonCode, 48);
  if (!ALLOWED_REASON_CODES.has(reasonCode)) {
    return {
      ok: false,
      error: "event.reasonCode is not allowed",
      reason: "invalid_reason_code",
    };
  }

  const severity = safeToken(body.severity, 16);
  if (!ALLOWED_SEVERITIES.has(severity)) {
    return {
      ok: false,
      error: "event.severity must be info or warning",
      reason: "invalid_severity",
    };
  }

  const confidenceBucket = safeToken(body.confidenceBucket, 16);
  if (!ALLOWED_CONFIDENCE_BUCKETS.has(confidenceBucket)) {
    return {
      ok: false,
      error: "event.confidenceBucket is not allowed",
      reason: "invalid_confidence_bucket",
    };
  }

  const snapDistBucket = safeToken(body.snapDistBucket, 16);
  if (!ALLOWED_SNAP_DIST_BUCKETS.has(snapDistBucket)) {
    return {
      ok: false,
      error: "event.snapDistBucket is not allowed",
      reason: "invalid_snap_dist_bucket",
    };
  }

  const speedBucket = safeToken(body.speedBucket, 16);
  if (!ALLOWED_SPEED_BUCKETS.has(speedBucket)) {
    return {
      ok: false,
      error: "event.speedBucket is not allowed",
      reason: "invalid_speed_bucket",
    };
  }

  const maneuverType = safeToken(body.maneuverType, 24);
  if (!ALLOWED_MANEUVER_TYPES.has(maneuverType)) {
    return {
      ok: false,
      error: "event.maneuverType is not allowed",
      reason: "invalid_maneuver_type",
    };
  }

  const maneuverModifier = safeToken(body.maneuverModifier, 24);
  if (!ALLOWED_MANEUVER_MODIFIERS.has(maneuverModifier)) {
    return {
      ok: false,
      error: "event.maneuverModifier is not allowed",
      reason: "invalid_maneuver_modifier",
    };
  }

  const predictionRepeated = strictBool(body.predictionRepeated);
  const trustBearing = strictBool(body.trustBearing);
  const trustInstruction = strictBool(body.trustInstruction);
  if (
    predictionRepeated === null ||
    trustBearing === null ||
    trustInstruction === null
  ) {
    return {
      ok: false,
      error: "predictionRepeated, trustBearing, trustInstruction must be booleans",
      reason: "invalid_flags",
    };
  }

  const occurredAtMinuteBucket = safeToken(body.occurredAtMinuteBucket, 32);
  if (!occurredAtMinuteBucket || Number.isNaN(Date.parse(occurredAtMinuteBucket))) {
    return {
      ok: false,
      error: "event.occurredAtMinuteBucket must be an ISO timestamp",
      reason: "invalid_occurred_at",
    };
  }

  let sessionHash = null;
  if (body.sessionHash !== undefined && body.sessionHash !== null && body.sessionHash !== "") {
    sessionHash = safeToken(body.sessionHash, 96);
    if (!/^[a-zA-Z0-9_-]{4,96}$/.test(sessionHash)) {
      return {
        ok: false,
        error: "event.sessionHash must be an opaque hash token",
        reason: "invalid_session_hash",
      };
    }
  }

  const app = safeToken(body.app, 16) || "driver";
  const platform = safeToken(body.platform, 16) || "flutter";

  const sanitized = {
    type: "nav_complexity_event",
    version: 1,
    app,
    platform,
    reasonCode,
    severity,
    confidenceBucket,
    snapDistBucket,
    speedBucket,
    maneuverType,
    maneuverModifier,
    predictionRepeated,
    trustBearing,
    trustInstruction,
    occurredAtMinuteBucket,
    ...(sessionHash ? { sessionHash } : {}),
  };

  return { ok: true, event: sanitized, sanitized };
}

/**
 * @param {unknown} raw
 * @returns {{ ok: true, dryRunStore: boolean, source: string, event: Record<string, unknown>, sanitized: Record<string, unknown> } | { ok: false, error: string, reason: string }}
 */
export function validateNavComplexityIngestRequest(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return {
      ok: false,
      error: "Request body must be a JSON object",
      reason: "invalid_body",
    };
  }

  const body = /** @type {Record<string, unknown>} */ (raw);
  const piiViolation = findForbiddenPiiKey(body, 0, ALLOWED_INGEST_WRAPPER_KEYS);
  if (piiViolation) {
    return {
      ok: false,
      error: "Payload contains disallowed data",
      reason: piiViolation,
    };
  }

  const unknownKeys = Object.keys(body).filter(
    (key) => !ALLOWED_INGEST_WRAPPER_KEYS.has(key),
  );
  if (unknownKeys.length > 0) {
    return {
      ok: false,
      error: "Request contains unknown fields",
      reason: "unknown_fields",
    };
  }

  const dryRunStore = strictBool(body.dryRunStore);
  if (dryRunStore === null) {
    return {
      ok: false,
      error: "dryRunStore must be a boolean",
      reason: "invalid_dry_run_store",
    };
  }

  let source = "test";
  if (body.source !== undefined && body.source !== null && body.source !== "") {
    source = safeToken(body.source, 24).toLowerCase();
    if (!ALLOWED_SOURCES.has(source)) {
      return {
        ok: false,
        error: "source must be one of test, manual_test, dry_run",
        reason: "invalid_source",
      };
    }
  }

  const validatedEvent = validateNavComplexityEvent(body.event);
  if (!validatedEvent.ok) {
    return validatedEvent;
  }

  return {
    ok: true,
    dryRunStore,
    source,
    event: validatedEvent.event,
    sanitized: validatedEvent.sanitized,
  };
}

/**
 * @param {string|null|undefined} hash
 * @returns {string|null}
 */
export function truncateSessionHash(hash) {
  if (!hash) return null;
  const s = String(hash);
  if (s.length <= 4) return "****";
  return `${s.slice(0, 4)}...`;
}

/**
 * @param {Record<string, unknown>} row
 * @returns {Record<string, unknown>}
 */
export function publicNavComplexityRow(row) {
  let raw = null;
  if (row.raw_json) {
    try {
      raw = JSON.parse(String(row.raw_json));
      if (raw && typeof raw === "object" && "sessionHash" in raw) {
        raw = { ...raw, sessionHash: truncateSessionHash(raw.sessionHash) };
      }
    } catch {
      raw = null;
    }
  }

  return {
    id: row.id,
    created_at: row.created_at,
    reason_code: row.reason_code,
    severity: row.severity,
    confidence_bucket: row.confidence_bucket,
    snap_dist_bucket: row.snap_dist_bucket,
    speed_bucket: row.speed_bucket,
    maneuver_type: row.maneuver_type,
    maneuver_modifier: row.maneuver_modifier,
    prediction_repeated: row.prediction_repeated === 1,
    trust_bearing: row.trust_bearing === 1,
    trust_instruction: row.trust_instruction === 1,
    dry_run: row.dry_run === 1,
    source: row.source,
    ...(raw ? { sanitized: raw } : {}),
  };
}

/**
 * @param {Record<string, unknown>} sanitized
 * @param {{ source: string, dryRun: boolean, createdAt?: string, id?: string }} opts
 */
export function navComplexityEventToDbRow(sanitized, opts) {
  const id = opts.id ?? `navcx_${crypto.randomUUID().replaceAll("-", "")}`;
  const createdAt = opts.createdAt ?? new Date().toISOString();
  return {
    id,
    created_at: createdAt,
    reason_code: sanitized.reasonCode,
    severity: sanitized.severity,
    confidence_bucket: sanitized.confidenceBucket,
    snap_dist_bucket: sanitized.snapDistBucket,
    speed_bucket: sanitized.speedBucket,
    maneuver_type: sanitized.maneuverType,
    maneuver_modifier: sanitized.maneuverModifier,
    prediction_repeated: sanitized.predictionRepeated ? 1 : 0,
    trust_bearing: sanitized.trustBearing ? 1 : 0,
    trust_instruction: sanitized.trustInstruction ? 1 : 0,
    dry_run: opts.dryRun ? 1 : 0,
    source: opts.source,
    raw_json: JSON.stringify(sanitized),
  };
}
