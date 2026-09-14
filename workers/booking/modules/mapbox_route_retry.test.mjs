import { test } from "node:test";
import assert from "node:assert/strict";
import {
  directionsWithNoSegmentRetry,
  isNoSegmentError,
  isUsableMapboxRoute,
  NO_SEGMENT_RETRY_STEPS,
} from "./mapbox_route_retry.mjs";

test("NoSegment retries keep the direct → 50 → 200 → 500 sequence", () => {
  assert.deepEqual(
    NO_SEGMENT_RETRY_STEPS.map((step) => step.label),
    ["direct", "50", "200", "500"],
  );
  assert.equal(isNoSegmentError("NoSegment", "Could not find a matching segment"), true);
  assert.equal(isUsableMapboxRoute({ distance: 34200, duration: 1740 }), true);
  assert.equal(isUsableMapboxRoute({ distance: 0, duration: 1740 }), false);
  assert.equal(isUsableMapboxRoute({ distance: 34200, duration: 0 }), false);
});

test("NoSegment retries once and then accepts a real route", async () => {
  const calls = [];
  const route = await directionsWithNoSegmentRetry({
    coords: [
      { lat: 50.8, lng: 3.7 },
      { lat: 50.74, lng: 3.6 },
    ],
    token: "test",
    directions: async (_coords, _token, options) => {
      calls.push(options?.radiuses || "");
      if (calls.length === 1) {
        const err = new Error("Directions failed");
        err.route_error_code = "NoSegment";
        err.route_error_message = "Could not find a matching segment";
        throw err;
      }
      return { distance: 34200, duration: 1740 };
    },
  });
  assert.deepEqual(calls, ["", "50;50"]);
  assert.equal(route.distance, 34200);
  assert.equal(route._retry.route_retry_used, true);
  assert.equal(route._retry.route_retry_attempts_count, 2);
});

test("a failed Mapbox route does not invent duration", async () => {
  await assert.rejects(
    () =>
      directionsWithNoSegmentRetry({
        coords: [
          { lat: 50.8, lng: 3.7 },
          { lat: 50.74, lng: 3.6 },
        ],
        token: "test",
        directions: async () => {
          const err = new Error("Directions failed");
          err.route_error_code = "NoRoute";
          err.route_error_message = "no route";
          throw err;
        },
      }),
    (error) => {
      assert.equal(error.route_error_code, "NoRoute");
      return true;
    },
  );
});
