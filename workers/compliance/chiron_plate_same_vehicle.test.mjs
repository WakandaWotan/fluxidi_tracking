// Dossier 03 — a plate may only ever come from the vehicle the ride is
// actually assigned to, and nothing goes to Chiron when that vehicle has no
// CH1211-valid plate.
//
// Run:
//   node --test workers/compliance/chiron_plate_same_vehicle.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  hydrateChironOfficialVehicleIdentity,
  buildChironTaxiritApiPayload,
  verifyChironOfficialLicensePlate,
  _chironVehicleIdentityIds,
} = __testInternals;

// The real account fleet: vh_1786881139131 carries the CH1211-short plate
// Tax002, while TXAA674 belongs to a different vehicle, vh_1.
const LIVE_FLEET = [
  { vehicle_id: "vh_1", license_plate: "T-XAA-674" },
  { vehicle_id: "vh_1786881139131", license_plate: "Tax002" },
  { vehicle_id: "vh_1787058237109", license_plate: "T-XAC- 002" },
  { vehicle_id: "vh_1787076028764", license_plate: "T-XAC-004" },
];

function hydrate(event, fleetVehicles = LIVE_FLEET) {
  return hydrateChironOfficialVehicleIdentity(event, {}, {
    scopedHydrationCache: { fleetLookup: "hit", fleetVehicles },
  });
}

test("ids keep the event snapshot and the roster assignment apart", () => {
  const ids = _chironVehicleIdentityIds(
    {
      vehicle: { vehicle_id: "vh_1786881139131", license_plate: "Tax002" },
      assignment: { vehicle_id: "vh_1" },
    },
    {},
  );
  assert.equal(ids.eventVehicleId, "vh_1786881139131");
  assert.equal(ids.assignmentVehicleId, "vh_1");
  assert.equal(ids.assignedVehicleId, "vh_1", "the roster assignment is the authority");
  assert.equal(ids.mismatch, true);
});

test("a stale event plate is replaced by the valid plate of the same vehicle", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1", license_plate: "Tax002" },
    assignment: { vehicle_id: "vh_1" },
  });
  assert.equal(hydrated.kentekenplaat, "T-XAA-674");
  assert.equal(hydrated.source, "scoped_vehicle");
  assert.equal(hydrated.plate_substituted_from, "Tax002");
  assert.equal(hydrated.plate_blocked_reason, null);
  assert.equal(hydrated.assigned_vehicle_id, "vh_1");
});

test("an assigned vehicle whose only plate is invalid sends nothing", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1786881139131", license_plate: "Tax002" },
    assignment: { vehicle_id: "vh_1786881139131" },
  });
  assert.equal(
    hydrated.kentekenplaat,
    "Tax002",
    "the real plate is kept so the record stays truthful",
  );
  assert.equal(hydrated.plate_substituted_from, null, "no plate was borrowed");
  assert.equal(hydrated.plate_blocked_reason, "ch1211_assigned_vehicle_plate_invalid");

  const check = verifyChironOfficialLicensePlate(hydrated.kentekenplaat);
  assert.equal(check.status, "format_invalid");
  assert.ok(check.errors.includes("ch1211_license_plate_too_short"));

  const body = buildChironTaxiritApiPayload({
    status: "vertrek",
    ritnummer: "2026-09-032",
    registratie: "0772.931.038",
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-09-18T10:00:00.000Z",
    kentekenplaat: hydrated.kentekenplaat,
    bestuurderspasnummer: "BE1234567A8B9012",
    vertrektijdstip: "2026-09-18T10:00:00.000Z",
    vertrekpunt_lengtegraad: 4.35662,
    vertrekpunt_breedtegraad: 50.845825,
  });
  assert.equal(body, null, "nothing may be shipped for an invalid plate");
});

test("TXAA674 is never borrowed from another vehicle", () => {
  const hydrated = hydrate({
    // The event still points at the Tax002 vehicle while the roster assigned
    // another car. Substituting either plate would report the wrong vehicle.
    vehicle: { vehicle_id: "vh_1786881139131", license_plate: "Tax002" },
    assignment: { vehicle_id: "vh_1787076028764" },
  });
  assert.notEqual(hydrated.kentekenplaat, "T-XAA-674");
  assert.equal(hydrated.plate_substituted_from, null);
  assert.equal(hydrated.plate_blocked_reason, "ch1211_vehicle_id_mismatch");
  assert.equal(hydrated.event_vehicle_id, "vh_1786881139131");
  assert.equal(hydrated.assignment_vehicle_id, "vh_1787076028764");
});

test("an unknown assigned vehicle with a short event plate stays blocked", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_not_in_fleet", license_plate: "Tax002" },
    assignment: { vehicle_id: "vh_not_in_fleet" },
  });
  assert.equal(hydrated.plate_blocked_reason, "ch1211_assigned_vehicle_not_in_fleet");
  assert.equal(hydrated.plate_substituted_from, null);
});

test("two fleet rows for one vehicle id never produce a plate", () => {
  const hydrated = hydrate(
    {
      vehicle: { vehicle_id: "vh_dup", license_plate: "Tax002" },
      assignment: { vehicle_id: "vh_dup" },
    },
    [
      { vehicle_id: "vh_dup", license_plate: "T-XAA-674" },
      { vehicle_id: "vh_dup", license_plate: "T-XAC-004" },
    ],
  );
  assert.equal(hydrated.plate_blocked_reason, "ch1211_vehicle_lookup_ambiguous");
  assert.equal(hydrated.plate_substituted_from, null);
});

test("a missing event plate still fills from the same assigned vehicle", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1787076028764" },
    assignment: { vehicle_id: "vh_1787076028764" },
  });
  assert.equal(hydrated.kentekenplaat, "T-XAC-004");
  assert.equal(hydrated.source, "scoped_vehicle");
  assert.equal(hydrated.plate_blocked_reason, null);
});

test("a spaced fleet plate still meets CH1211 on the wire", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1787058237109", license_plate: "Tax002" },
    assignment: { vehicle_id: "vh_1787058237109" },
  });
  assert.equal(hydrated.kentekenplaat, "T-XAC- 002");
  const body = buildChironTaxiritApiPayload({
    status: "vertrek",
    ritnummer: "2026-09-041",
    registratie: "0772.931.038",
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-09-18T10:00:00.000Z",
    kentekenplaat: hydrated.kentekenplaat,
    bestuurderspasnummer: "BE1234567A8B9012",
    vertrektijdstip: "2026-09-18T10:00:00.000Z",
    vertrekpunt_lengtegraad: 4.35662,
    vertrekpunt_breedtegraad: 50.845825,
  });
  assert.equal(body.rit.voertuig.nummerplaat, "TXAC002");
});

test("a valid event plate is never overwritten by the fleet", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1", license_plate: "T-XAA-674" },
    assignment: { vehicle_id: "vh_1" },
  });
  assert.equal(hydrated.kentekenplaat, "T-XAA-674");
  assert.equal(hydrated.source, "event");
  assert.equal(hydrated.plate_substituted_from, null);
});
