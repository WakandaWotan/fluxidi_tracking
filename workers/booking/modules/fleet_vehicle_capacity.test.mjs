import assert from "node:assert/strict";
import test from "node:test";
import {
  DEMO_SEED_PLATE,
  VEHICLE_LIMIT_REACHED,
  dropUnpersistedDemoVehicles,
  evaluateFleetCapacityWrite,
  isDemoSeedFingerprint,
  isUnpersistedDemoVehicle,
  resolveAuthoritativeVehicleCapacity,
  vehicleLimitMessage,
} from "./fleet_vehicle_capacity.mjs";

const DEMO = {
  vehicle_id: "vh_1",
  vehicle_name: "Hoofdwagen",
  brand_model: "Tesla Model 3",
  license_plate: DEMO_SEED_PLATE,
};

test("trial with no paid extra grants exactly one vehicle", () => {
  assert.equal(resolveAuthoritativeVehicleCapacity({
    status: "trialing",
    included_vehicles: 1,
    max_vehicles: 1,
    extra_vehicle_active_quantity: 0,
  }), 1);
});

test("a requested or client-inflated max_vehicles does not grant trial capacity", () => {
  assert.equal(resolveAuthoritativeVehicleCapacity({
    status: "trialing",
    included_vehicles: 1,
    max_vehicles: 99,
    extra_vehicle_active_quantity: 0,
  }), 1);
});

test("a stored paid extra vehicle slot is added to the included vehicle", () => {
  assert.equal(resolveAuthoritativeVehicleCapacity({
    status: "active",
    included_vehicles: 1,
    max_vehicles: 2,
    extra_vehicle_active_quantity: 1,
  }), 2);
});

test("a legacy active profile that only baked extras into max_vehicles keeps working", () => {
  assert.equal(resolveAuthoritativeVehicleCapacity({
    status: "active",
    included_vehicles: 1,
    max_vehicles: 3,
    extra_vehicle_active_quantity: 0,
  }), 3);
});

test("missing rights fail closed to one vehicle, never unlimited", () => {
  assert.equal(resolveAuthoritativeVehicleCapacity(null), 1);
  assert.equal(resolveAuthoritativeVehicleCapacity({}), 1);
});

test("the first trial vehicle is allowed", () => {
  const decision = evaluateFleetCapacityWrite({
    existingActiveIds: [],
    incomingActiveIds: ["vh_ford"],
    allowed: 1,
  });
  assert.equal(decision.ok, true);
});

test("a second trial vehicle without a paid right is refused", () => {
  const decision = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1"],
    incomingActiveIds: ["vh_1", "vh_ford"],
    allowed: 1,
  });
  assert.equal(decision.ok, false);
  assert.equal(decision.error, VEHICLE_LIMIT_REACHED);
  assert.match(vehicleLimitMessage(), /proefperiode/);
});

test("an extra vehicle with a valid paid right is allowed", () => {
  const decision = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1"],
    incomingActiveIds: ["vh_1", "vh_ford"],
    allowed: 2,
  });
  assert.equal(decision.ok, true);
});

test("repeating the same request does not create another vehicle", () => {
  const first = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1", "vh_ford"],
    incomingActiveIds: ["vh_1", "vh_ford"],
    allowed: 1,
  });
  const second = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1", "vh_ford"],
    incomingActiveIds: ["vh_1", "vh_ford"],
    allowed: 1,
  });
  assert.equal(first.ok, true);
  assert.equal(first.preserved_overrun, true);
  assert.equal(first.added, 0);
  assert.deepEqual(second, first);
});

test("an existing overrun can be edited but not grown", () => {
  const edit = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1", "vh_ford"],
    incomingActiveIds: ["vh_1", "vh_ford"],
    allowed: 1,
  });
  const grow = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1", "vh_ford"],
    incomingActiveIds: ["vh_1", "vh_ford", "vh_van"],
    allowed: 1,
  });
  assert.equal(edit.ok, true);
  assert.equal(grow.ok, false);
});

test("two concurrent second-vehicle writes against the same snapshot cannot both stay", () => {
  const allowed = 1;
  const first = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1"],
    incomingActiveIds: ["vh_1", "vh_a"],
    allowed,
  });
  const afterFirst = first.ok ? ["vh_1", "vh_a"] : ["vh_1"];
  const second = evaluateFleetCapacityWrite({
    existingActiveIds: afterFirst,
    incomingActiveIds: ["vh_1", "vh_b"],
    allowed,
  });
  assert.equal(first.ok, false);
  assert.equal(second.ok, false);
  assert.equal(afterFirst.length, 1);
});

const JM_RIGHTS = {
  status: "trialing",
  included_vehicles: 1,
  max_vehicles: 1,
  extra_vehicle_active_quantity: 0,
};

const JM_DEMO = {
  vehicle_id: "vh_1",
  vehicle_name: "Hoofdwagen",
  brand_model: "Tesla Model 3",
  license_plate: "1-ABC-123",
  is_active: true,
};

const JM_FORD = {
  vehicle_id: "vh_1788969226792",
  vehicle_name: "Ford Tourneo courier",
  brand_model: "Ford Tourneo courier",
  license_plate: "T-XAS-307",
  is_active: true,
};

const FLUXIDI_TESLA = {
  vehicle_id: "vh_1",
  vehicle_name: "Hoofdwagen",
  brand_model: "Tesla Model 3",
  license_plate: "T-XAA-674",
  is_active: true,
};

test("JM trial rights stay at one vehicle", () => {
  assert.equal(resolveAuthoritativeVehicleCapacity(JM_RIGHTS), 1);
});

test("a stored JM demo row is not dropped and counts toward the trial limit", () => {
  assert.equal(isUnpersistedDemoVehicle(JM_DEMO, ["vh_1", "vh_1788969226792"]), false);
  const kept = dropUnpersistedDemoVehicles([JM_DEMO, JM_FORD], ["vh_1", "vh_1788969226792"]);
  assert.deepEqual(kept.map((row) => row.vehicle_id), ["vh_1", "vh_1788969226792"]);
  const counted = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_1", "vh_1788969226792"],
    incomingActiveIds: kept.map((row) => row.vehicle_id),
    allowed: resolveAuthoritativeVehicleCapacity(JM_RIGHTS),
  });
  assert.equal(counted.ok, true);
  assert.equal(counted.preserved_overrun, true);
  assert.equal(counted.incoming, 2);
  assert.equal(counted.allowed, 1);
});

test("JM may edit or shrink the overrun but cannot add or swap a third id", () => {
  const allowed = 1;
  const existing = ["vh_1", "vh_1788969226792"];
  const edit = evaluateFleetCapacityWrite({
    existingActiveIds: existing,
    incomingActiveIds: existing,
    allowed,
  });
  const grow = evaluateFleetCapacityWrite({
    existingActiveIds: existing,
    incomingActiveIds: [...existing, "vh_van"],
    allowed,
  });
  const swapFord = evaluateFleetCapacityWrite({
    existingActiveIds: existing,
    incomingActiveIds: ["vh_1", "vh_new_van"],
    allowed,
  });
  const dropDemoKeepFord = evaluateFleetCapacityWrite({
    existingActiveIds: existing,
    incomingActiveIds: ["vh_1788969226792"],
    allowed,
  });
  const dropFordKeepDemo = evaluateFleetCapacityWrite({
    existingActiveIds: existing,
    incomingActiveIds: ["vh_1"],
    allowed,
  });
  assert.equal(edit.ok, true);
  assert.equal(grow.ok, false);
  assert.equal(swapFord.ok, false);
  assert.equal(dropDemoKeepFord.ok, true);
  assert.equal(dropFordKeepDemo.ok, true);
});

test("Christophe Tesla is kept by plate, not by vh_1 or Hoofdwagen", () => {
  assert.equal(isDemoSeedFingerprint(FLUXIDI_TESLA), false);
  assert.equal(isDemoSeedFingerprint(JM_DEMO), true);
  assert.equal(isUnpersistedDemoVehicle(FLUXIDI_TESLA, []), false);
});

test("first-run vh_1 Hoofdwagen without a plate is a demo seed", () => {
  const firstRun = { vehicle_id: "vh_1", vehicle_name: "Hoofdwagen", license_plate: "" };
  assert.equal(isDemoSeedFingerprint(firstRun), true);
  assert.equal(isUnpersistedDemoVehicle(firstRun, []), true);
  assert.equal(isDemoSeedFingerprint(FLUXIDI_TESLA), false);
});

test("a disjoint replacement at capacity one is refused", () => {
  const decision = evaluateFleetCapacityWrite({
    existingActiveIds: ["vh_a"],
    incomingActiveIds: ["vh_b"],
    allowed: 1,
  });
  assert.equal(decision.ok, false);
  assert.equal(decision.error, VEHICLE_LIMIT_REACHED);
});

test("a new company demo seed never becomes a stored row", () => {
  const incoming = dropUnpersistedDemoVehicles([JM_DEMO], []);
  assert.deepEqual(incoming, []);
  const onlyDemo = evaluateFleetCapacityWrite({
    existingActiveIds: [],
    incomingActiveIds: incoming.map((row) => row.vehicle_id),
    allowed: 1,
  });
  assert.equal(onlyDemo.ok, true);
  assert.equal(onlyDemo.incoming, 0);
});

test("a new demo seed is dropped; a stored Tesla with the same shape is kept", () => {
  assert.equal(isUnpersistedDemoVehicle(DEMO, []), true);
  assert.equal(isUnpersistedDemoVehicle(DEMO, ["vh_1"]), false);
  const incoming = dropUnpersistedDemoVehicles(
    [DEMO, { vehicle_id: "vh_ford", license_plate: "T-XAS-307", vehicle_name: "Ford Tourneo courier" }],
    [],
  );
  assert.deepEqual(incoming.map((row) => row.vehicle_id), ["vh_ford"]);
  const kept = dropUnpersistedDemoVehicles([DEMO], ["vh_1"]);
  assert.equal(kept.length, 1);
});
