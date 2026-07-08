import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import worker from "./fluxidi_learning_worker.js";
import {
  generateAdvisoryRules,
  buildAdvisoryRulesResponse,
  assertAdvisoryRulesNoPii,
  MIN_SAMPLES_PER_RULE,
} from "./nav_complexity_advisory_rules.js";

const TOKEN = "test-learning-token";

function makeEvent(overrides = {}) {
  return {
    reason_code: "low_confidence",
    severity: "info",
    confidence_bucket: "40-60",
    snap_dist_bucket: "5-15",
    speed_bucket: "slow",
    maneuver_type: "turn",
    maneuver_modifier: "right",
    prediction_repeated: 0,
    trust_bearing: 1,
    trust_instruction: 1,
    ...overrides,
  };
}

function repeatedPredictionCityDataset() {
  const events = [];
  for (let i = 0; i < MIN_SAMPLES_PER_RULE; i += 1) {
    events.push(
      makeEvent({
        reason_code: "repeated_prediction",
        speed_bucket: i % 2 === 0 ? "city" : "urban",
        prediction_repeated: 1,
        severity: "warning",
      }),
    );
  }
  for (let i = 0; i < 5; i += 1) {
    events.push(
      makeEvent({
        reason_code: "low_confidence",
        speed_bucket: "city",
        prediction_repeated: 0,
      }),
    );
  }
  return events;
}

function createMockD1(initialRows = []) {
  const rows = [...initialRows];

  async function allStatement(sql) {
    if (sql.includes("FROM nav_complexity_events")) {
      if (sql.includes("reason_code, severity")) {
        return {
          results: rows.map((row) => ({
            reason_code: row.reason_code,
            severity: row.severity,
            confidence_bucket: row.confidence_bucket,
            snap_dist_bucket: row.snap_dist_bucket,
            speed_bucket: row.speed_bucket,
            maneuver_type: row.maneuver_type,
            maneuver_modifier: row.maneuver_modifier,
            prediction_repeated: row.prediction_repeated,
            trust_bearing: row.trust_bearing,
            trust_instruction: row.trust_instruction,
          })),
        };
      }
      const sorted = [...rows].sort((a, b) =>
        String(b.created_at).localeCompare(String(a.created_at)),
      );
      return { results: sorted.slice(0, 20) };
    }
    return { results: [] };
  }

  return {
    rows,
    prepare(sql) {
      return {
        bind(...args) {
          return {
            async run() {
              if (sql.includes("INSERT INTO nav_complexity_events")) {
                rows.push({
                  id: args[0],
                  created_at: args[1],
                  reason_code: args[2],
                  severity: args[3],
                  confidence_bucket: args[4],
                  snap_dist_bucket: args[5],
                  speed_bucket: args[6],
                  maneuver_type: args[7],
                  maneuver_modifier: args[8],
                  prediction_repeated: args[9],
                  trust_bearing: args[10],
                  trust_instruction: args[11],
                  dry_run: args[12],
                  source: args[13],
                  raw_json: args[14],
                });
                return { meta: { changes: 1 } };
              }
              if (sql.includes("DELETE FROM nav_complexity_events")) {
                const before = rows.length;
                for (let i = rows.length - 1; i >= 0; i -= 1) {
                  const row = rows[i];
                  if (
                    row.dry_run === 1 ||
                    row.source === "test" ||
                    row.source === "dry_run" ||
                    row.source === "manual_test" ||
                    row.source === "flutter_manual_test"
                  ) {
                    rows.splice(i, 1);
                  }
                }
                return { meta: { changes: before - rows.length } };
              }
              return { meta: { changes: 0 } };
            },
            all: () => allStatement(sql),
          };
        },
        all: () => allStatement(sql),
      };
    },
  };
}

function authHeaders(token = TOKEN) {
  return { Authorization: `Bearer ${token}` };
}

async function jsonFetch(url, init, env) {
  const request = new Request(url, init);
  const response = await worker.fetch(request, env);
  const body = await response.json();
  return { response, body };
}

describe("nav_complexity_advisory_rules module", () => {
  it("insufficient data returns empty advisory response", () => {
    const response = buildAdvisoryRulesResponse([makeEvent()]);
    assert.equal(response.ok, true);
    assert.equal(response.advisoryOnly, true);
    assert.deepEqual(response.rules, []);
    assert.equal(response.reason, "insufficient_data");
  });

  it("repeated prediction data generates advisory rule", () => {
    const events = repeatedPredictionCityDataset();
    const { rules } = generateAdvisoryRules(events);
    assert.ok(rules.some((r) => r.id === "rule_repeated_prediction_city"));
    const rule = rules.find((r) => r.id === "rule_repeated_prediction_city");
    assert.equal(rule.enabledForRuntime, false);
    assert.equal(rule.reasonCode, "repeated_prediction");
    assert.equal(rule.recommendation, "consider_prediction_hold_tuning");
  });

  it("no PII fields emitted", () => {
    const response = buildAdvisoryRulesResponse(repeatedPredictionCityDataset(), {
      generatedAt: "2026-07-08T08:00:00.000Z",
    });
    assertAdvisoryRulesNoPii(response);
    const serialized = JSON.stringify(response);
    assert.ok(!serialized.includes("sessionHash"));
    assert.ok(!serialized.includes("latitude"));
  });
});

describe("fluxidi_learning_worker nav-complexity advisory rules endpoint", () => {
  /** @type {ReturnType<typeof createMockD1>} */
  let db;
  /** @type {Record<string, unknown>} */
  let env;

  beforeEach(() => {
    db = createMockD1(repeatedPredictionCityDataset());
    env = { LEARNING_SERVICE_TOKEN: TOKEN, LEARNING_DB: db };
  });

  it("unauthorized rejected", async () => {
    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-rules/advisory",
      { method: "GET" },
      env,
    );
    assert.equal(response.status, 401);
    assert.equal(body.ok, false);
  });

  it("returns advisory rules for authorized request", async () => {
    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-rules/advisory",
      { method: "GET", headers: authHeaders() },
      env,
    );
    assert.equal(response.status, 200);
    assert.equal(body.ok, true);
    assert.equal(body.advisoryOnly, true);
    assert.ok(Array.isArray(body.rules));
    assert.ok(body.rules.length >= 1);
    assert.equal(body.rules[0].enabledForRuntime, false);
  });
});
