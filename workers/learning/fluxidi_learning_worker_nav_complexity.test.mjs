import { describe, it, beforeEach } from "node:test";
import assert from "node:assert/strict";
import worker from "./fluxidi_learning_worker.js";

const TOKEN = "test-learning-token";

const validEvent = {
  type: "nav_complexity_event",
  version: 1,
  app: "driver",
  platform: "flutter",
  reasonCode: "repeated_prediction",
  severity: "warning",
  confidenceBucket: "40-60",
  snapDistBucket: "15-30",
  speedBucket: "city",
  maneuverType: "turn",
  maneuverModifier: "right",
  predictionRepeated: true,
  trustBearing: false,
  trustInstruction: true,
  occurredAtMinuteBucket: "2026-07-07T10:12:00.000Z",
  sessionHash: "sesshash1234",
};

function createMockD1() {
  /** @type {Array<Record<string, unknown>>} */
  const rows = [];

  function runStatement(sql, args = []) {
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
          row.source === "manual_test"
        ) {
          rows.splice(i, 1);
        }
      }
      return { meta: { changes: before - rows.length } };
    }
    return { meta: { changes: 0 } };
  }

  function allStatement(sql) {
    if (sql.includes("FROM nav_complexity_events")) {
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
              return runStatement(sql, args);
            },
            async all() {
              return allStatement(sql);
            },
          };
        },
        async all() {
          return allStatement(sql);
        },
        async run() {
          return runStatement(sql, []);
        },
      };
    },
  };
}

function authHeaders(token = TOKEN) {
  return {
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
  };
}

function makeEnv(db) {
  return {
    LEARNING_SERVICE_TOKEN: TOKEN,
    LEARNING_DB: db,
  };
}

async function jsonFetch(url, init, env) {
  const request = new Request(url, init);
  const response = await worker.fetch(request, env);
  const body = await response.json();
  return { response, body };
}

describe("fluxidi_learning_worker nav-complexity admin endpoints", () => {
  /** @type {ReturnType<typeof createMockD1>} */
  let db;
  /** @type {Record<string, unknown>} */
  let env;

  beforeEach(() => {
    db = createMockD1();
    env = makeEnv(db);
  });

  it("rejects unauthenticated ingest", async () => {
    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/ingest-dry-run",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ dryRunStore: true, event: validEvent }),
      },
      env,
    );
    assert.equal(response.status, 401);
    assert.equal(body.ok, false);
  });

  it("validates only when dryRunStore=false", async () => {
    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/ingest-dry-run",
      {
        method: "POST",
        headers: authHeaders(),
        body: JSON.stringify({ dryRunStore: false, source: "test", event: validEvent }),
      },
      env,
    );
    assert.equal(response.status, 200);
    assert.equal(body.validated, true);
    assert.equal(body.stored, false);
    assert.equal(db.rows.length, 0);
  });

  it("stores valid sanitized event when dryRunStore=true", async () => {
    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/ingest-dry-run",
      {
        method: "POST",
        headers: authHeaders(),
        body: JSON.stringify({ dryRunStore: true, source: "test", event: validEvent }),
      },
      env,
    );
    assert.equal(response.status, 200);
    assert.equal(body.stored, true);
    assert.equal(body.dry_run, true);
    assert.equal(db.rows.length, 1);
    assert.equal(db.rows[0].reason_code, "repeated_prediction");
    assert.equal(db.rows[0].source, "test");
    assert.equal(db.rows[0].dry_run, 1);
  });

  it("rejects forbidden PII in ingest payload", async () => {
    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/ingest-dry-run",
      {
        method: "POST",
        headers: authHeaders(),
        body: JSON.stringify({
          dryRunStore: true,
          event: { ...validEvent, driver_id: "x" },
        }),
      },
      env,
    );
    assert.equal(response.status, 400);
    assert.equal(body.ok, false);
    assert.equal(db.rows.length, 0);
  });

  it("returns recent sanitized rows with truncated session hash", async () => {
    await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/ingest-dry-run",
      {
        method: "POST",
        headers: authHeaders(),
        body: JSON.stringify({ dryRunStore: true, source: "test", event: validEvent }),
      },
      env,
    );

    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/recent",
      { method: "GET", headers: authHeaders() },
      env,
    );
    assert.equal(response.status, 200);
    assert.equal(body.count, 1);
    assert.equal(body.events[0].reason_code, "repeated_prediction");
    assert.equal(body.events[0].sanitized.sessionHash, "sess...");
    assert.ok(!body.events[0].sanitized.latitude);
  });

  it("deletes test/dry_run records", async () => {
    await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/ingest-dry-run",
      {
        method: "POST",
        headers: authHeaders(),
        body: JSON.stringify({ dryRunStore: true, source: "test", event: validEvent }),
      },
      env,
    );
    assert.equal(db.rows.length, 1);

    const { response, body } = await jsonFetch(
      "https://learning.test/admin/nav-complexity-events/test-data",
      { method: "DELETE", headers: authHeaders() },
      env,
    );
    assert.equal(response.status, 200);
    assert.equal(body.deleted, 1);
    assert.equal(db.rows.length, 0);
  });
});
