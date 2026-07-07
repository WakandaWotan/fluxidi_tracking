const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  FORBIDDEN_PII_KEYS,
  ALLOWED_EVENT_KEYS,
  parseNavComplexityEvents,
  analyzeNavComplexityEvents,
  aggregateTopPatterns,
  buildRecommendations,
} = require("./nav_complexity_analyzer.js");

const samplePath = path.join(
  __dirname,
  "fixtures",
  "nav_complexity_events_sample.json",
);

function loadSample() {
  return JSON.parse(fs.readFileSync(samplePath, "utf8"));
}

describe("NAV-AI-2 nav_complexity_analyzer", () => {
  it("empty input returns no insights", () => {
    const report = analyzeNavComplexityEvents([]);
    assert.equal(report.totalEvents, 0);
    assert.deepEqual(report.recommendations, []);
    assert.deepEqual(report.topPatterns, []);
    assert.equal(report.advisoryOnly, true);
    assert.equal(report.dryRun, true);
    assert.equal(report.connectedToLiveIngest, false);
  });

  it("empty JSONL string returns no insights", () => {
    const report = analyzeNavComplexityEvents("\n\n");
    assert.equal(report.totalEvents, 0);
    assert.deepEqual(report.recommendations, []);
  });

  it("distributions are counted correctly", () => {
    const events = loadSample();
    const report = analyzeNavComplexityEvents(events);

    assert.equal(report.totalEvents, 12);
    assert.equal(report.distributions.reasonCode.repeated_prediction, 3);
    assert.equal(report.distributions.reasonCode.low_confidence, 3);
    assert.equal(report.distributions.reasonCode.ambiguous_instruction, 2);
    assert.equal(report.distributions.severity.warning, 7);
    assert.equal(report.distributions.severity.info, 5);
    assert.equal(report.distributions.confidenceBucket["60-80"], 4);
    assert.equal(report.distributions.snapDistBucket["30+"], 3);
    assert.equal(report.distributions.speedBucket.city, 3);
    assert.equal(report.distributions.speedBucket.slow, 5);
  });

  it("rates are computed correctly", () => {
    const report = analyzeNavComplexityEvents(loadSample());
    assert.equal(report.rates.repeatedPrediction, 0.333);
    assert.equal(report.rates.trustBearingFalse, 0.5);
    assert.equal(report.rates.trustInstructionFalse, 0.5);
  });

  it("top pattern aggregation works", () => {
    const events = loadSample();
    const patterns = aggregateTopPatterns(events, 3);
    assert.equal(patterns.length, 3);
    assert.ok(patterns[0].count >= patterns[1].count);
    assert.match(patterns[0].pattern, /^[a-z_]+(\|[^|]+){9}$/);
    assert.equal(typeof patterns[0].share, "number");
    assert.ok(patterns[0].share > 0 && patterns[0].share <= 1);

    const allPatterns = aggregateTopPatterns(events, 20);
    assert.ok(
      allPatterns.some((p) => p.pattern.startsWith("repeated_prediction|")),
    );
  });

  it("recommendations are generated from known patterns", () => {
    const report = analyzeNavComplexityEvents(loadSample());
    const ids = report.recommendations.map((r) => r.id);

    assert.ok(ids.includes("prediction_duration_city_urban"));
    assert.ok(ids.includes("snap_bearing_conflict"));
    assert.ok(ids.includes("ambiguous_roundabout_fork"));
    assert.ok(ids.includes("low_confidence_slow_speed"));
    assert.ok(ids.includes("warning_mid_confidence_sensitive"));

    for (const rec of report.recommendations) {
      assert.match(rec.message, /^Advisory:/);
      assert.ok(["low", "medium", "high"].includes(rec.priority));
    }
  });

  it("buildRecommendations returns empty for insufficient data", () => {
    const recs = buildRecommendations([], { rates: {} });
    assert.deepEqual(recs, []);
  });

  it("no PII fields are required or emitted", () => {
    const report = analyzeNavComplexityEvents(loadSample());
    const serialized = JSON.stringify(report);

    for (const key of FORBIDDEN_PII_KEYS) {
      assert.ok(!serialized.includes(`"${key}"`), `output must not contain ${key}`);
    }

    assert.equal(report.advisoryOnly, true);
    assert.ok(!("sessionHash" in report));
  });

  it("rejects events containing PII keys during parse", () => {
    const tainted = [
      {
        type: "nav_complexity_event",
        reasonCode: "low_confidence",
        latitude: 51.2,
        severity: "info",
      },
    ];
    const parsed = parseNavComplexityEvents(tainted);
    assert.equal(parsed.length, 0);
  });

  it("allowed event keys match NAV-AI-1 schema", () => {
    const event = loadSample()[0];
    for (const key of Object.keys(event)) {
      assert.ok(ALLOWED_EVENT_KEYS.has(key), `unexpected key in fixture: ${key}`);
    }
  });

  it("parses JSONL with mixed nav diagnostics lines", () => {
    const jsonl = [
      JSON.stringify({
        type: "nav_engine",
        tag: "NAV_R14_COMPLEXITY",
        message: "ignored",
      }),
      JSON.stringify({
        type: "nav_complexity_event",
        reasonCode: "low_confidence",
        severity: "info",
        confidenceBucket: "40-60",
        snapDistBucket: "0-5",
        speedBucket: "slow",
        maneuverType: "turn",
        maneuverModifier: "left",
        predictionRepeated: false,
        trustBearing: true,
        trustInstruction: true,
        occurredAtMinuteBucket: "2026-07-07T10:00:00.000Z",
      }),
    ].join("\n");

    const parsed = parseNavComplexityEvents(jsonl);
    assert.equal(parsed.length, 1);
    assert.equal(parsed[0].reasonCode, "low_confidence");
  });
});
