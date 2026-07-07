import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  validateNavComplexityEvent,
  validateNavComplexityIngestRequest,
  truncateSessionHash,
  publicNavComplexityRow,
  navComplexityEventToDbRow,
  FORBIDDEN_PII_KEYS,
} from "./nav_complexity_event_schema.js";

const validEvent = {
  type: "nav_complexity_event",
  version: 1,
  app: "driver",
  platform: "flutter",
  reasonCode: "low_confidence",
  severity: "warning",
  confidenceBucket: "40-60",
  snapDistBucket: "15-30",
  speedBucket: "city",
  maneuverType: "turn",
  maneuverModifier: "right",
  predictionRepeated: false,
  trustBearing: true,
  trustInstruction: false,
  occurredAtMinuteBucket: "2026-07-07T10:12:00.000Z",
  sessionHash: "a1b2c3d4e5f6",
};

describe("nav_complexity_event_schema", () => {
  it("accepts a valid sanitized event", () => {
    const result = validateNavComplexityEvent(validEvent);
    assert.equal(result.ok, true);
    assert.equal(result.sanitized.reasonCode, "low_confidence");
    assert.equal(result.sanitized.sessionHash, "a1b2c3d4e5f6");
  });

  it("rejects forbidden PII keys", () => {
    const result = validateNavComplexityEvent({
      ...validEvent,
      latitude: 51.2,
    });
    assert.equal(result.ok, false);
    assert.equal(result.reason, "forbidden_key");
  });

  it("rejects unknown fields", () => {
    const result = validateNavComplexityEvent({
      ...validEvent,
      bookingId: "secret",
    });
    assert.equal(result.ok, false);
    assert.ok(
      result.reason === "forbidden_key" || result.reason === "unknown_fields",
    );
  });

  it("validates ingest wrapper with dryRunStore=false", () => {
    const result = validateNavComplexityIngestRequest({
      dryRunStore: false,
      source: "test",
      event: validEvent,
    });
    assert.equal(result.ok, true);
    assert.equal(result.dryRunStore, false);
    assert.equal(result.source, "test");
  });

  it("truncates session hash for public responses", () => {
    assert.equal(truncateSessionHash("a1b2c3d4"), "a1b2...");
    assert.equal(truncateSessionHash(null), null);
  });

  it("public row hides full session hash inside sanitized payload", () => {
    const row = navComplexityEventToDbRow(validEvent, {
      source: "test",
      dryRun: true,
      id: "navcx_test1",
      createdAt: "2026-07-07T10:00:00.000Z",
    });
    const pub = publicNavComplexityRow(row);
    assert.equal(pub.id, "navcx_test1");
    assert.equal(pub.sanitized.sessionHash, "a1b2...");
    for (const key of FORBIDDEN_PII_KEYS) {
      assert.ok(!(key in pub));
    }
  });
});
