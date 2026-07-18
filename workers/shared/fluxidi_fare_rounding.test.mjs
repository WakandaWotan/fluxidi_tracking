// FARE-ROUNDING-CENTRAL-0_10-1 — tests for the canonical worker fare rounding.
//
// Run: node --test workers/shared/fluxidi_fare_rounding.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  roundFareCentsToNearestTenCents,
  roundFareEuroToNearestTenCents,
} from "./fluxidi_fare_rounding.mjs";

test("pure rounding: canonical half-up €0.10 table", () => {
  const cases = [
    [0, 0],
    [1, 0],
    [4, 0],
    [5, 10],
    [14, 10],
    [15, 20],
    [19, 20],
    [21, 20],
    [22, 20],
    [25, 30],
    [37, 40],
    [38, 40],
    [314, 310],
    [315, 320],
    [319, 320],
    [321, 320],
    [337, 340],
  ];
  for (const [input, expected] of cases) {
    assert.equal(
      roundFareCentsToNearestTenCents(input),
      expected,
      `roundFareCentsToNearestTenCents(${input}) should be ${expected}`,
    );
  }
});

test("pure rounding: defensive inputs never silently become 0", () => {
  assert.equal(roundFareCentsToNearestTenCents(null), null);
  assert.equal(roundFareCentsToNearestTenCents(undefined), null);
  assert.equal(roundFareCentsToNearestTenCents(NaN), null);
  assert.equal(roundFareCentsToNearestTenCents(Infinity), null);
  assert.equal(roundFareCentsToNearestTenCents(-1), null);
  assert.equal(roundFareCentsToNearestTenCents(-500), null);
  // exact zero is a legitimate fare and stays zero
  assert.equal(roundFareCentsToNearestTenCents(0), 0);
});

test("euro wrapper mirrors the cents rule", () => {
  assert.equal(roundFareEuroToNearestTenCents(3.14), 3.1);
  assert.equal(roundFareEuroToNearestTenCents(3.15), 3.2);
  assert.equal(roundFareEuroToNearestTenCents(3.19), 3.2);
  assert.equal(roundFareEuroToNearestTenCents(3.21), 3.2);
  assert.equal(roundFareEuroToNearestTenCents(3.25), 3.3);
  assert.equal(roundFareEuroToNearestTenCents(3.37), 3.4);
  assert.equal(roundFareEuroToNearestTenCents(3.38), 3.4);
  assert.equal(roundFareEuroToNearestTenCents(0), 0);
  assert.equal(roundFareEuroToNearestTenCents(null), null);
  assert.equal(roundFareEuroToNearestTenCents(-3.2), null);
});

test("idempotency: rounding an already-rounded amount is a no-op", () => {
  for (const cents of [0, 10, 20, 320, 340, 3200]) {
    assert.equal(roundFareCentsToNearestTenCents(cents), cents);
  }
});

test("no floating-point drift: ten €3.20 rides sum to exactly €32.00", () => {
  let totalCents = 0;
  for (let i = 0; i < 10; i += 1) {
    totalCents += roundFareCentsToNearestTenCents(319); // raw 3.19 -> 3.20
  }
  assert.equal(totalCents, 3200);
  assert.equal(totalCents / 100, 32);
});
