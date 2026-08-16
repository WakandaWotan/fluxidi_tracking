// FLEET-VEHICLE-TOMBSTONE-P0 (pure module)
//
// Run:
//   node --test workers/booking/modules/fleet_vehicle_tombstone.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  deletedVehicleIdList,
  filterActiveVehicles,
  mergeVehicleTombstones,
  normalizeDeletedVehicleMap,
  resolveFleetRevision,
  sanitizeVehicleTombstoneId,
  toMonotonicRevision,
} from "./fleet_vehicle_tombstone.mjs";

test("sanitizeVehicleTombstoneId keeps opaque ids, drops unsafe/oversized", () => {
  assert.equal(sanitizeVehicleTombstoneId("vh_123"), "vh_123");
  assert.equal(sanitizeVehicleTombstoneId("  vh_abc  "), "vh_abc");
  assert.equal(sanitizeVehicleTombstoneId("bad id"), "");
  assert.equal(sanitizeVehicleTombstoneId("a/b"), "");
  assert.equal(sanitizeVehicleTombstoneId("../x"), "");
  assert.equal(sanitizeVehicleTombstoneId("x".repeat(97)), "");
  assert.equal(sanitizeVehicleTombstoneId(null), "");
});

test("normalizeDeletedVehicleMap parses map and array, keeps/repairs timestamps", () => {
  const map = normalizeDeletedVehicleMap(
    { vh_a: "2026-08-16T10:00:00.000Z", "bad id": "x", vh_b: "" },
    { nowIso: "2026-08-16T12:00:00.000Z" },
  );
  assert.equal(map.vh_a, "2026-08-16T10:00:00.000Z");
  assert.equal(map.vh_b, "2026-08-16T12:00:00.000Z"); // empty -> fallback now
  assert.equal(Object.prototype.hasOwnProperty.call(map, "bad id"), false);

  const fromArray = normalizeDeletedVehicleMap(["vh_x", "vh_y", "bad id"], {
    nowIso: "2026-08-16T12:00:00.000Z",
  });
  assert.deepEqual(Object.keys(fromArray).sort(), ["vh_x", "vh_y"]);
});

test("mergeVehicleTombstones unions and never removes an existing tombstone", () => {
  const existing = { vh_ferrari: "2026-08-16T10:00:00.000Z" };
  const added = mergeVehicleTombstones(existing, {
    vh_new: "2026-08-16T11:00:00.000Z",
  });
  assert.equal(added.map.vh_ferrari, "2026-08-16T10:00:00.000Z");
  assert.equal(added.map.vh_new, "2026-08-16T11:00:00.000Z");
  assert.equal(added.changed, true);

  // An incoming payload that omits an existing tombstone cannot remove it.
  const omitted = mergeVehicleTombstones(added.map, {});
  assert.equal(omitted.map.vh_ferrari, "2026-08-16T10:00:00.000Z");
  assert.equal(omitted.changed, false);

  // Re-sending the same tombstone is idempotent and keeps the original stamp.
  const repeated = mergeVehicleTombstones(added.map, {
    vh_ferrari: "2026-08-16T13:00:00.000Z",
  });
  assert.equal(repeated.changed, false);
  assert.equal(repeated.map.vh_ferrari, "2026-08-16T10:00:00.000Z");
});

test("filterActiveVehicles drops tombstoned vehicles by id", () => {
  const vehicles = [
    { vehicle_id: "vh_tesla" },
    { vehicle_id: "vh_ferrari" },
    { id: "vh_cadillac" },
  ];
  const active = filterActiveVehicles(vehicles, { vh_ferrari: "t" });
  assert.deepEqual(
    active.map((v) => v.vehicle_id ?? v.id),
    ["vh_tesla", "vh_cadillac"],
  );
  // A genuine new local-only vehicle (not tombstoned) stays.
  const withNew = filterActiveVehicles(
    [...vehicles, { vehicle_id: "vh_new" }],
    { vh_ferrari: "t" },
  );
  assert.ok(withNew.some((v) => (v.vehicle_id ?? v.id) === "vh_new"));
});

test("resolveFleetRevision bumps on change, holds idempotently, seeds baseline", () => {
  assert.equal(resolveFleetRevision({ existingRevision: 2, changed: true }), 3);
  assert.equal(resolveFleetRevision({ existingRevision: 2, changed: false }), 2);
  assert.equal(resolveFleetRevision({ existingRevision: 0, changed: false }), 1);
  assert.equal(resolveFleetRevision({ existingRevision: 0, changed: true }), 1);
  assert.equal(resolveFleetRevision({ existingRevision: null, changed: true }), 1);
});

test("deletedVehicleIdList sorts ids; toMonotonicRevision clamps", () => {
  assert.deepEqual(deletedVehicleIdList({ vh_b: "t", vh_a: "t" }), [
    "vh_a",
    "vh_b",
  ]);
  assert.equal(toMonotonicRevision("3"), 3);
  assert.equal(toMonotonicRevision(-1), 0);
  assert.equal(toMonotonicRevision(null), 0);
});
