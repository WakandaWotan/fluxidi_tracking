/**
 * NAV-AI-5A: advisory learned navigation complexity rules (read-only).
 * Generates anonymous rules from sanitized nav_complexity_events aggregates.
 * Never emits coordinates, addresses, or identity fields.
 */

const ADVISORY_RULES_VERSION = 1;
const MIN_SAMPLES_GLOBAL = 5;
const MIN_SAMPLES_PER_RULE = 20;

const ADVISORY_EVENT_FILTER_SQL = `
  dry_run = 1
  OR source IN ('test', 'dry_run', 'manual_test', 'flutter_manual_test')
`;

const FORBIDDEN_PII_KEYS = [
  "latitude",
  "longitude",
  "lat",
  "lng",
  "lon",
  "address",
  "booking_id",
  "bookingid",
  "customer_id",
  "customerid",
  "driver_id",
  "driverid",
  "phone",
  "email",
  "name",
  "sessionhash",
  "session_hash",
];

/**
 * @param {number} n
 * @returns {number}
 */
function roundRatio(n) {
  return Math.round(n * 1000) / 1000;
}

/**
 * @param {unknown} value
 * @returns {boolean}
 */
function isTrue(value) {
  return value === 1 || value === true || value === "true";
}

/**
 * @param {Record<string, unknown>} row
 * @returns {Record<string, unknown>}
 */
function normalizeEventRow(row) {
  return {
    reason_code: String(row.reason_code ?? ""),
    severity: String(row.severity ?? ""),
    confidence_bucket: String(row.confidence_bucket ?? ""),
    snap_dist_bucket: String(row.snap_dist_bucket ?? ""),
    speed_bucket: String(row.speed_bucket ?? ""),
    maneuver_type: String(row.maneuver_type ?? ""),
    maneuver_modifier: String(row.maneuver_modifier ?? ""),
    prediction_repeated: row.prediction_repeated,
    trust_bearing: row.trust_bearing,
    trust_instruction: row.trust_instruction,
  };
}

/**
 * @param {Record<string, unknown>[]} events
 * @returns {{ rules: Array<Record<string, unknown>>, reason: string|null }}
 */
export function generateAdvisoryRules(events) {
  const normalized = events.map(normalizeEventRow);
  const total = normalized.length;

  if (total < MIN_SAMPLES_GLOBAL) {
    return { rules: [], reason: "insufficient_data" };
  }

  /** @type {Array<Record<string, unknown>>} */
  const rules = [];

  const cityUrban = normalized.filter((e) =>
    ["city", "urban"].includes(e.speed_bucket),
  );
  const cityUrbanPredRepeat = cityUrban.filter(
    (e) =>
      e.reason_code === "repeated_prediction" || isTrue(e.prediction_repeated),
  ).length;
  if (
    cityUrban.length >= MIN_SAMPLES_PER_RULE &&
    cityUrbanPredRepeat / cityUrban.length >= 0.25
  ) {
    rules.push({
      id: "rule_repeated_prediction_city",
      scope: "global",
      reasonCode: "repeated_prediction",
      speedBucket: "city",
      recommendation: "consider_prediction_hold_tuning",
      confidence: roundRatio(cityUrbanPredRepeat / cityUrban.length),
      minSamples: MIN_SAMPLES_PER_RULE,
      sampleCount: cityUrbanPredRepeat,
      enabledForRuntime: false,
    });
  }

  const highSnap = normalized.filter((e) =>
    ["15-30", "30+"].includes(e.snap_dist_bucket),
  );
  const highSnapBearingLow = highSnap.filter(
    (e) => !isTrue(e.trust_bearing),
  ).length;
  if (
    highSnap.length >= MIN_SAMPLES_PER_RULE &&
    highSnapBearingLow / highSnap.length >= 0.35
  ) {
    rules.push({
      id: "rule_snap_bearing_conflict",
      scope: "global",
      reasonCode: "high_snap_distance",
      snapDistBucket: "15-30",
      recommendation: "inspect_snap_bearing_conflict",
      confidence: roundRatio(highSnapBearingLow / highSnap.length),
      minSamples: MIN_SAMPLES_PER_RULE,
      sampleCount: highSnapBearingLow,
      enabledForRuntime: false,
    });
  }

  const ambiguous = normalized.filter(
    (e) => e.reason_code === "ambiguous_instruction",
  );
  const ambiguousComplex = ambiguous.filter((e) => {
    const type = e.maneuver_type;
    const mod = e.maneuver_modifier;
    return (
      type === "roundabout" ||
      type === "turn" ||
      mod === "unknown" ||
      mod.includes("unknown")
    );
  }).length;
  if (
    ambiguous.length >= Math.min(MIN_SAMPLES_PER_RULE, 10) &&
    ambiguousComplex / ambiguous.length >= 0.4
  ) {
    rules.push({
      id: "rule_ambiguous_maneuver_selection",
      scope: "global",
      reasonCode: "ambiguous_instruction",
      maneuverType: "roundabout",
      recommendation: "inspect_maneuver_selection",
      confidence: roundRatio(ambiguousComplex / ambiguous.length),
      minSamples: MIN_SAMPLES_PER_RULE,
      sampleCount: ambiguousComplex,
      enabledForRuntime: false,
    });
  }

  const warnings = normalized.filter((e) => e.severity === "warning");
  const warningsMidConf = warnings.filter(
    (e) => e.confidence_bucket === "60-80",
  ).length;
  if (
    warnings.length >= MIN_SAMPLES_PER_RULE &&
    warningsMidConf / warnings.length >= 0.3
  ) {
    rules.push({
      id: "rule_threshold_sensitivity",
      scope: "global",
      reasonCode: "low_confidence",
      confidenceBucket: "60-80",
      recommendation: "review_complexity_threshold_sensitivity",
      confidence: roundRatio(warningsMidConf / warnings.length),
      minSamples: MIN_SAMPLES_PER_RULE,
      sampleCount: warningsMidConf,
      enabledForRuntime: false,
    });
  }

  if (rules.length === 0) {
    return { rules: [], reason: "insufficient_data" };
  }

  return { rules, reason: null };
}

/**
 * @param {unknown} value
 * @param {string[]} path
 */
export function assertAdvisoryRulesNoPii(value, path = []) {
  if (value == null) return;
  if (Array.isArray(value)) {
    value.forEach((item, i) => assertAdvisoryRulesNoPii(item, [...path, String(i)]));
    return;
  }
  if (typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      const normalized = key.toLowerCase();
      if (FORBIDDEN_PII_KEYS.includes(normalized)) {
        throw new Error(`PII key in advisory rules output: ${key}`);
      }
      assertAdvisoryRulesNoPii(child, [...path, key]);
    }
  }
}

/**
 * @param {Record<string, unknown>[]} events
 * @param {{ generatedAt?: string }} opts
 * @returns {Record<string, unknown>}
 */
export function buildAdvisoryRulesResponse(events, opts = {}) {
  const { rules, reason } = generateAdvisoryRules(events);
  const response = {
    ok: true,
    advisoryOnly: true,
    version: ADVISORY_RULES_VERSION,
    generatedAt: opts.generatedAt ?? new Date().toISOString(),
    rules,
  };
  if (reason) {
    response.reason = reason;
  }
  assertAdvisoryRulesNoPii(response);
  for (const rule of rules) {
    if (rule.enabledForRuntime !== false) {
      throw new Error("Advisory rules must have enabledForRuntime:false");
    }
  }
  return response;
}

/**
 * @param {unknown} db
 * @returns {Promise<Record<string, unknown>[]>}
 */
export async function queryAdvisorySampleEvents(db) {
  const result = await db
    .prepare(
      `SELECT
         reason_code, severity, confidence_bucket, snap_dist_bucket,
         speed_bucket, maneuver_type, maneuver_modifier,
         prediction_repeated, trust_bearing, trust_instruction
       FROM nav_complexity_events
       WHERE ${ADVISORY_EVENT_FILTER_SQL}`,
    )
    .all();
  return Array.isArray(result?.results) ? result.results : [];
}

export {
  ADVISORY_RULES_VERSION,
  MIN_SAMPLES_GLOBAL,
  MIN_SAMPLES_PER_RULE,
  ADVISORY_EVENT_FILTER_SQL,
  FORBIDDEN_PII_KEYS,
};
