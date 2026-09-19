// AIRPORT-RETURN-ASSIGNMENT-P0 — one vehicle and driver per ride leg.
// Run: node --test workers/booking/modules/return_leg_assignment.test.mjs

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import {
  legRequiredVehicleId,
  legsUseDifferentVehicles,
  perLegAssignmentFromLegResults,
  returnAssignmentRecordFields,
  returnRequestedDriverIdFromPayload,
  returnRequestedRecordFields,
  returnRequestedVehicleIdFromPayload,
} from "./return_leg_assignment.mjs";
import { taxiRequestedVehicleIdFromPayload } from "./required_vehicle_constraint.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const worker = readFileSync(join(__dirname, "..", "fluxidi_booking_worker.js"), "utf8");

const OUT_VEHICLE = "vh_outbound_sedan";
const RET_VEHICLE = "vh_return_cadillac";
const OUT_DRIVER = "drv_christophe";
const RET_DRIVER = "drv_wotan";

const WEBSITE_BODY = {
  vehicle_id: OUT_VEHICLE,
  preferred_vehicle_id: OUT_VEHICLE,
  assigned_driver_id: OUT_DRIVER,
  return_vehicle_id: RET_VEHICLE,
  preferred_return_vehicle_id: RET_VEHICLE,
  return_assigned_driver_id: RET_DRIVER,
};

// ---------------------------------------------------------------------------
// Contract fields
// ---------------------------------------------------------------------------

test("1) the canonical return fields are read from the booking contract", () => {
  assert.equal(returnRequestedVehicleIdFromPayload(WEBSITE_BODY), RET_VEHICLE);
  assert.equal(returnRequestedDriverIdFromPayload(WEBSITE_BODY), RET_DRIVER);
  // The outbound reader is untouched, so taxi and one-way stay as they were.
  assert.equal(taxiRequestedVehicleIdFromPayload(WEBSITE_BODY), OUT_VEHICLE);
  assert.equal(returnRequestedVehicleIdFromPayload({}), "");
  assert.equal(returnRequestedVehicleIdFromPayload(null), "");
  assert.equal(returnRequestedDriverIdFromPayload({}), "");
});

test("2) documented aliases are accepted, canonical names win", () => {
  assert.equal(
    returnRequestedVehicleIdFromPayload({ returnVehicleId: RET_VEHICLE }),
    RET_VEHICLE,
  );
  assert.equal(
    returnRequestedVehicleIdFromPayload({ preferred_return_vehicle_id: RET_VEHICLE }),
    RET_VEHICLE,
  );
  assert.equal(
    returnRequestedVehicleIdFromPayload({ return_preferred_vehicle_id: RET_VEHICLE }),
    RET_VEHICLE,
    "compatibility alias with the other word order is still read",
  );
  assert.equal(
    returnRequestedVehicleIdFromPayload({
      return_vehicle_id: RET_VEHICLE,
      return_preferred_vehicle_id: "vh_stale",
    }),
    RET_VEHICLE,
  );
  assert.equal(
    returnRequestedDriverIdFromPayload({ returnAssignedDriverId: RET_DRIVER }),
    RET_DRIVER,
  );
});

// ---------------------------------------------------------------------------
// Per-leg constraint
// ---------------------------------------------------------------------------

test("3) each leg is pinned to its own vehicle, never to the other leg's", () => {
  const pins = { outboundVehicleId: OUT_VEHICLE, returnVehicleId: RET_VEHICLE };
  assert.equal(legRequiredVehicleId({ legKey: "OUTBOUND", ...pins }), OUT_VEHICLE);
  assert.equal(legRequiredVehicleId({ legKey: "RETURN", ...pins }), RET_VEHICLE);
  assert.equal(legRequiredVehicleId({ legKey: "return", ...pins }), RET_VEHICLE);
});

test("4) without a return choice the return leg stays unpinned for its own moment", () => {
  assert.equal(
    legRequiredVehicleId({ legKey: "RETURN", outboundVehicleId: OUT_VEHICLE, returnVehicleId: "" }),
    "",
    "the outbound car is never silently pinned onto the return leg",
  );
  assert.equal(
    legRequiredVehicleId({ legKey: "OUTBOUND", outboundVehicleId: OUT_VEHICLE }),
    OUT_VEHICLE,
  );
  // Same car for both legs is allowed, but only when it was asked for.
  assert.equal(
    legRequiredVehicleId({
      legKey: "RETURN",
      outboundVehicleId: OUT_VEHICLE,
      returnVehicleId: OUT_VEHICLE,
    }),
    OUT_VEHICLE,
  );
});

// ---------------------------------------------------------------------------
// Confirmed assignment per leg
// ---------------------------------------------------------------------------

test("5) confirmed per-leg assignment reports two different cars and drivers", () => {
  const perLeg = perLegAssignmentFromLegResults([
    { legKey: "OUTBOUND", assignedVehicleId: OUT_VEHICLE, assignedDriverId: OUT_DRIVER },
    { legKey: "RETURN", assignedVehicleId: RET_VEHICLE, assignedDriver: { driver_id: RET_DRIVER } },
  ]);
  assert.deepEqual(perLeg.outbound, { vehicle_id: OUT_VEHICLE, driver_id: OUT_DRIVER });
  assert.deepEqual(perLeg.return, { vehicle_id: RET_VEHICLE, driver_id: RET_DRIVER });
  assert.equal(legsUseDifferentVehicles(perLeg), true);
});

test("6) the same car on both legs is reported as such, not as two cars", () => {
  const perLeg = perLegAssignmentFromLegResults([
    { legKey: "OUTBOUND", assignedVehicleId: OUT_VEHICLE, assignedDriverId: OUT_DRIVER },
    { legKey: "RETURN", assignedVehicleId: OUT_VEHICLE, assignedDriverId: OUT_DRIVER },
  ]);
  assert.equal(perLeg.return.vehicle_id, OUT_VEHICLE);
  assert.equal(legsUseDifferentVehicles(perLeg), false);
});

test("7) an unassigned return leg is reported as unassigned, not as available", () => {
  const perLeg = perLegAssignmentFromLegResults([
    { legKey: "OUTBOUND", assignedVehicleId: OUT_VEHICLE, assignedDriverId: OUT_DRIVER },
  ]);
  assert.deepEqual(perLeg.return, { vehicle_id: null, driver_id: null });
  assert.equal(legsUseDifferentVehicles(perLeg), false);
  assert.deepEqual(returnAssignmentRecordFields(perLeg), {});
  assert.deepEqual(perLegAssignmentFromLegResults(null).outbound, {
    vehicle_id: null,
    driver_id: null,
  });
});

// ---------------------------------------------------------------------------
// Storage fields
// ---------------------------------------------------------------------------

test("8) the confirmed return assignment is stored under stable field names", () => {
  const fields = returnAssignmentRecordFields({
    outbound: { vehicle_id: OUT_VEHICLE, driver_id: OUT_DRIVER },
    return: { vehicle_id: RET_VEHICLE, driver_id: RET_DRIVER },
  });
  assert.equal(fields.return_vehicle_id, RET_VEHICLE);
  assert.equal(fields.returnVehicleId, RET_VEHICLE);
  assert.equal(fields.return_assigned_vehicle_id, RET_VEHICLE);
  assert.equal(fields.return_assigned_driver_id, RET_DRIVER);
  assert.equal(fields.returnAssignedDriverId, RET_DRIVER);
});

test("9) the requested return choice is kept apart from the confirmed one", () => {
  const requested = returnRequestedRecordFields({
    vehicleId: RET_VEHICLE,
    driverId: RET_DRIVER,
  });
  assert.equal(requested.customer_requested_return_vehicle_id, RET_VEHICLE);
  assert.equal(requested.customer_requested_return_driver_id, RET_DRIVER);
  assert.equal("return_vehicle_id" in requested, false, "a request is not a confirmation");
  assert.deepEqual(returnRequestedRecordFields({}), {});
});

// ---------------------------------------------------------------------------
// Wiring proof in the worker
// ---------------------------------------------------------------------------

test("10) /book reads the return choice and pins each leg separately", () => {
  assert.match(
    worker,
    /returnRequestedVehicleIdFromPayload as _returnRequestedVehicleIdFromPayload/,
    "the worker imports the canonical return vehicle reader",
  );
  assert.match(
    worker,
    /_bookingRequestedReturnVehicleId = !_limousineAccepted/,
    "/book computes a return vehicle pin of its own",
  );
  assert.match(
    worker,
    /returnRequiredVehicleId: _bookingRequestedReturnVehicleId/,
    "the return pin is handed to the fleet dispatch",
  );
  assert.match(
    worker,
    /_legRequiredVehicleId\(\{\s*legKey: spec\.legKey/,
    "each dispatched leg resolves its own vehicle constraint",
  );
  assert.match(
    worker,
    /_returnAssignmentRecordFields\(bookingPerLegAssignment\)/,
    "the confirmed return assignment is written onto the booking record",
  );
  assert.match(
    worker,
    /assignment_by_leg: bookingAssignmentByLeg\(\)/,
    "the /book response exposes the confirmed assignment per leg",
  );
});

test("11) a failed leg still releases reservations before anything is stored", () => {
  // Atomicity guard: booking creation requires all legs and rolls back.
  assert.match(worker, /requireAllLegs: true,\s*\n\s*allowPartialLegAssignment: false,/);
  assert.match(
    worker,
    /await _releaseFleetLegReservations\(env, acquiredReservations, fleetScope\);\s*\n\s*return \{\s*\n\s*ok: false,/,
  );
});
