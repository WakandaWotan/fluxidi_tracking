/**
 * NAV-AI-2: read-only Navigation Complexity Analyzer.
 *
 * Consumes sanitized nav_complexity_event records only (NAV-AI-1 shape).
 * Produces advisory distributions and threshold recommendations.
 * Does NOT modify navigation, routing, or dispatch behavior.
 */

/** Keys that must never appear on input or output payloads. */
const FORBIDDEN_PII_KEYS = [
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
];

const ALLOWED_EVENT_KEYS = new Set([
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

/**
 * @param {unknown} input JSON array, JSONL string, or single object
 * @returns {Array<Record<string, unknown>>}
 */
function parseNavComplexityEvents(input) {
  if (input == null) return [];
  if (Array.isArray(input)) {
    return input.flatMap((item) => extractNavComplexityEvent(item)).filter(Boolean);
  }
  if (typeof input === "string") {
    const trimmed = input.trim();
    if (!trimmed) return [];
    if (trimmed.startsWith("[")) {
      try {
        const parsed = JSON.parse(trimmed);
        return parseNavComplexityEvents(parsed);
      } catch {
        return [];
      }
    }
    const lines = trimmed.split(/\r?\n/);
    const events = [];
    for (const line of lines) {
      const row = line.trim();
      if (!row) continue;
      try {
        const parsed = JSON.parse(row);
        const event = extractNavComplexityEvent(parsed);
        if (event) events.push(event);
      } catch {
        // skip malformed JSONL lines
      }
    }
    return events;
  }
  if (typeof input === "object") {
    const one = extractNavComplexityEvent(input);
    return one ? [one] : [];
  }
  return [];
}

/**
 * @param {unknown} raw
 * @returns {Record<string, unknown>|null}
 */
function extractNavComplexityEvent(raw) {
  if (!raw || typeof raw !== "object") return null;
  const obj = /** @type {Record<string, unknown>} */ (raw);

  // Direct NAV-AI-1 export line.
  if (obj.type === "nav_complexity_event") {
    return sanitizeEvent(obj);
  }

  // Nav diagnostics envelope: { type, data: { ...fields } } or flat tag rows.
  if (obj.type === "nav_complexity_event" && obj.data && typeof obj.data === "object") {
    return sanitizeEvent({ ...obj.data, type: "nav_complexity_event" });
  }

  // Legacy/alternate: reasonCode present without type (still sanitized-only).
  if (typeof obj.reasonCode === "string" && obj.reasonCode.length > 0) {
    return sanitizeEvent({ type: "nav_complexity_event", ...obj });
  }

  return null;
}

/**
 * @param {Record<string, unknown>} raw
 * @returns {Record<string, unknown>|null}
 */
function sanitizeEvent(raw) {
  for (const key of Object.keys(raw)) {
    if (FORBIDDEN_PII_KEYS.includes(key)) return null;
  }
  const out = { type: "nav_complexity_event" };
  for (const key of ALLOWED_EVENT_KEYS) {
    if (key in raw && raw[key] !== undefined && raw[key] !== null) {
      out[key] = raw[key];
    }
  }
  if (typeof out.reasonCode !== "string") return null;
  return out;
}

/**
 * @param {Record<string, unknown>[]} events
 * @param {string} field
 * @returns {Record<string, number>}
 */
function countField(events, field) {
  /** @type {Record<string, number>} */
  const counts = {};
  for (const event of events) {
    const value = String(event[field] ?? "unknown");
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return sortDesc(counts);
}

/**
 * @param {Record<string, number>} map
 * @returns {Record<string, number>}
 */
function sortDesc(map) {
  return Object.fromEntries(
    Object.entries(map).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0])),
  );
}

/**
 * @param {Record<string, unknown>[]} events
 * @param {number} limit
 * @returns {Array<{ pattern: string, count: number, share: number }>}
 */
function aggregateTopPatterns(events, limit = 10) {
  /** @type {Record<string, number>} */
  const counts = {};
  for (const event of events) {
    const key = [
      event.reasonCode ?? "unknown",
      event.severity ?? "unknown",
      event.confidenceBucket ?? "unknown",
      event.snapDistBucket ?? "unknown",
      event.speedBucket ?? "unknown",
      event.maneuverType ?? "unknown",
      event.maneuverModifier ?? "unknown",
      event.predictionRepeated === true ? "predRepeat" : "predOk",
      event.trustBearing === false ? "bearingLow" : "bearingOk",
      event.trustInstruction === false ? "instrLow" : "instrOk",
    ].join("|");
    counts[key] = (counts[key] ?? 0) + 1;
  }
  const total = events.length || 1;
  return Object.entries(counts)
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .slice(0, limit)
    .map(([pattern, count]) => ({
      pattern,
      count,
      share: roundRatio(count / total),
    }));
}

/**
 * @param {boolean} value
 * @returns {boolean}
 */
function isFalse(value) {
  return value === false || value === "false" || value === 0;
}

/**
 * @param {boolean} value
 * @returns {boolean}
 */
function isTrue(value) {
  return value === true || value === "true" || value === 1;
}

/**
 * @param {number} n
 * @returns {number}
 */
function roundRatio(n) {
  return Math.round(n * 1000) / 1000;
}

/**
 * @param {Record<string, unknown>[]} events
 * @param {Record<string, unknown>} stats
 * @returns {Array<{ id: string, priority: string, message: string }>}
 */
function buildRecommendations(events, stats) {
  /** @type {Array<{ id: string, priority: string, message: string }>} */
  const recs = [];
  const total = events.length;
  if (total === 0) return recs;

  const cityUrban = events.filter((e) =>
    ["city", "urban"].includes(String(e.speedBucket ?? "")),
  );
  const cityUrbanPredRepeat = cityUrban.filter((e) =>
    isTrue(e.predictionRepeated),
  ).length;
  if (
    cityUrban.length >= 3 &&
    cityUrbanPredRepeat / cityUrban.length >= 0.35
  ) {
    recs.push({
      id: "prediction_duration_city_urban",
      priority: "medium",
      message:
        "Advisory: repeated_prediction is elevated at city/urban speeds — review prediction/gap-bridge duration thresholds in NavComplexityGuard inputs (offline tuning only).",
    });
  }

  const highSnap = events.filter((e) =>
    ["15-30", "30+"].includes(String(e.snapDistBucket ?? "")),
  );
  const highSnapBearingLow = highSnap.filter((e) =>
    isFalse(e.trustBearing),
  ).length;
  if (highSnap.length >= 3 && highSnapBearingLow / highSnap.length >= 0.4) {
    recs.push({
      id: "snap_bearing_conflict",
      priority: "high",
      message:
        "Advisory: high_snap_distance often coincides with trustBearing=false — inspect route snap vs bearing conflict logic (read-only review; no auto threshold change).",
    });
  }

  const ambiguous = events.filter(
    (e) => String(e.reasonCode) === "ambiguous_instruction",
  );
  const ambiguousComplexManeuver = ambiguous.filter((e) => {
    const t = String(e.maneuverType ?? "");
    return (
      t === "roundabout" ||
      t === "fork" ||
      t === "merge" ||
      String(e.maneuverModifier ?? "").includes("unknown")
    );
  }).length;
  if (
    ambiguous.length >= 2 &&
    ambiguousComplexManeuver / ambiguous.length >= 0.5
  ) {
    recs.push({
      id: "ambiguous_roundabout_fork",
      priority: "medium",
      message:
        "Advisory: ambiguous_instruction clusters around roundabout/fork/merge — review maneuver step selection and banner copy clarity.",
    });
  }

  const lowConf = events.filter(
    (e) => String(e.reasonCode) === "low_confidence",
  );
  const lowConfSlow = lowConf.filter((e) =>
    ["stopped", "slow"].includes(String(e.speedBucket ?? "")),
  ).length;
  if (lowConf.length >= 3 && lowConfSlow / lowConf.length >= 0.5) {
    recs.push({
      id: "low_confidence_slow_speed",
      priority: "low",
      message:
        "Advisory: low_confidence appears mostly at stopped/slow speeds — consider low-speed hold or caution delay tuning in NavComplexityGuard (manual review only).",
    });
  }

  const warnings = events.filter((e) => String(e.severity) === "warning");
  const warningsMidConfidence = warnings.filter((e) =>
    String(e.confidenceBucket ?? "") === "60-80",
  ).length;
  if (
    warnings.length >= 4 &&
    warningsMidConfidence / warnings.length >= 0.35
  ) {
    recs.push({
      id: "warning_mid_confidence_sensitive",
      priority: "medium",
      message:
        "Advisory: many warning-severity events sit in confidence bucket 60-80 — guard thresholds may be slightly sensitive; validate with field logs before any change.",
    });
  }

  if (stats.rates.repeatedPrediction >= 0.3 && total >= 5) {
    const already = recs.some((r) => r.id === "prediction_duration_city_urban");
    if (!already) {
      recs.push({
        id: "prediction_repeat_global",
        priority: "medium",
        message:
          "Advisory: overall repeated_prediction rate is high — review gap-bridge activation frequency and prediction cooldown policy.",
      });
    }
  }

  return recs;
}

/**
 * @param {unknown} input
 * @returns {Record<string, unknown>}
 */
function analyzeNavComplexityEvents(input) {
  const events = parseNavComplexityEvents(input);
  const totalEvents = events.length;

  if (totalEvents === 0) {
    return {
      advisoryOnly: true,
      dryRun: true,
      connectedToLiveIngest: false,
      totalEvents: 0,
      distributions: {
        reasonCode: {},
        severity: {},
        confidenceBucket: {},
        snapDistBucket: {},
        speedBucket: {},
      },
      rates: {
        repeatedPrediction: 0,
        trustBearingFalse: 0,
        trustInstructionFalse: 0,
      },
      topPatterns: [],
      recommendations: [],
    };
  }

  const repeatedPredictionCount = events.filter((e) =>
    isTrue(e.predictionRepeated),
  ).length;
  const trustBearingFalseCount = events.filter((e) =>
    isFalse(e.trustBearing),
  ).length;
  const trustInstructionFalseCount = events.filter((e) =>
    isFalse(e.trustInstruction),
  ).length;

  const rates = {
    repeatedPrediction: roundRatio(repeatedPredictionCount / totalEvents),
    trustBearingFalse: roundRatio(trustBearingFalseCount / totalEvents),
    trustInstructionFalse: roundRatio(trustInstructionFalseCount / totalEvents),
  };

  const report = {
    advisoryOnly: true,
    dryRun: true,
    connectedToLiveIngest: false,
    totalEvents,
    distributions: {
      reasonCode: countField(events, "reasonCode"),
      severity: countField(events, "severity"),
      confidenceBucket: countField(events, "confidenceBucket"),
      snapDistBucket: countField(events, "snapDistBucket"),
      speedBucket: countField(events, "speedBucket"),
    },
    rates,
    topPatterns: aggregateTopPatterns(events, 10),
    recommendations: buildRecommendations(events, { rates }),
  };

  assertNoPiiInOutput(report);
  return report;
}

/**
 * @param {unknown} value
 * @param {string[]} path
 */
function assertNoPiiInOutput(value, path = []) {
  if (value == null) return;
  if (Array.isArray(value)) {
    value.forEach((item, i) => assertNoPiiInOutput(item, [...path, String(i)]));
    return;
  }
  if (typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      if (FORBIDDEN_PII_KEYS.includes(key)) {
        throw new Error(`PII key emitted in analyzer output: ${key}`);
      }
      assertNoPiiInOutput(child, [...path, key]);
    }
  }
}

module.exports = {
  FORBIDDEN_PII_KEYS,
  ALLOWED_EVENT_KEYS,
  parseNavComplexityEvents,
  analyzeNavComplexityEvents,
  aggregateTopPatterns,
  buildRecommendations,
};
