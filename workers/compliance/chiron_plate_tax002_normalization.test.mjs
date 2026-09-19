// The production normalization for a Chiron licence plate, restored.
//
// Golden reference: client 1ff827c5 (Play production 1.0.1+4). Its compliance
// worker had no CH1211 length rule at all: a plate was uppercased, stripped of
// non-alphanumeric characters, and shipped. A later CH1211 gate turned a
// reportable ride into a ride that was never exported, so the gate is a warning
// again while the same-vehicle rule stays.
//
// Run:
//   node --test workers/compliance/chiron_plate_tax002_normalization.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  chironOfficialKentekenplaatWire,
  chironOfficialPlateMeetsCh1211,
  verifyChironOfficialLicensePlate,
  hydrateChironOfficialVehicleIdentity,
  buildChironTaxiritApiPayload,
} = __testInternals;

const LIVE_FLEET = [
  { vehicle_id: "vh_1", license_plate: "T-XAA-674" },
  { vehicle_id: "vh_1786881139131", license_plate: "Tax002" },
];

function hydrate(event, fleetVehicles = LIVE_FLEET) {
  return hydrateChironOfficialVehicleIdentity(event, {}, {
    scopedHydrationCache: { fleetLookup: "hit", fleetVehicles },
  });
}

function wireBody(kentekenplaat) {
  return buildChironTaxiritApiPayload({
    status: "vertrek",
    ritnummer: "2026-09-032",
    registratie: "0772.931.038",
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-09-18T15:56:44.772Z",
    kentekenplaat,
    bestuurderspasnummer: "BE1234567A8B9012",
    vertrektijdstip: "2026-09-18T15:56:44.772Z",
    vertrekpunt_lengtegraad: 3.6694744,
    vertrekpunt_breedtegraad: 50.7719435,
  });
}

test("Tax002 normalizes to exactly TAX002", () => {
  assert.equal(chironOfficialKentekenplaatWire("Tax002"), "TAX002");
  assert.equal(chironOfficialKentekenplaatWire("tax-002"), "TAX002");
  assert.equal(chironOfficialKentekenplaatWire(" Tax 002 "), "TAX002");
  // Six characters. Nothing is padded to reach seven.
  assert.equal(chironOfficialKentekenplaatWire("Tax002").length, 6);
  assert.equal(chironOfficialPlateMeetsCh1211("Tax002"), false);
});

test("a short plate is a warning, not an invalid format", () => {
  const out = verifyChironOfficialLicensePlate("Tax002", {
    source: "vehicle_profile",
    country: "BE",
    service: "taxi",
  });
  assert.notEqual(out.status, "format_invalid");
  assert.ok(
    out.warnings.includes("ch1211_license_plate_too_short"),
    `expected a CH1211 warning, got ${JSON.stringify(out.warnings)}`,
  );
  assert.ok(!out.errors.includes("ch1211_license_plate_too_short"));
});

test("TAX002 is shipped on the wire, as the production build did", () => {
  const body = wireBody("Tax002");
  assert.ok(body, "a payload must be built for a short plate");
  assert.equal(body.rit.voertuig.nummerplaat, "TAX002");
});

test("a plate without any alphanumeric character still yields no payload", () => {
  assert.equal(wireBody("---"), null);
});

test("the same assigned vehicle's valid plate still wins over a short one", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1", license_plate: "Tax002" },
    assignment: { vehicle_id: "vh_1" },
  });
  assert.equal(hydrated.kentekenplaat, "T-XAA-674");
  assert.equal(hydrated.plate_substituted_from, "Tax002");
  assert.equal(wireBody(hydrated.kentekenplaat).rit.voertuig.nummerplaat, "TXAA674");
});

test("2026-09-032 exports TAX002 and still asks for a data correction", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1786881139131" },
    booking_id: "2026-09-032",
  });
  assert.equal(hydrated.kentekenplaat, "Tax002");
  assert.equal(hydrated.plate_substituted_from, null, "no plate was borrowed");
  assert.equal(
    hydrated.plate_blocked_reason,
    "ch1211_assigned_vehicle_plate_invalid",
    "the dashboard still learns the fleet row needs a correct plate",
  );
  assert.equal(wireBody(hydrated.kentekenplaat).rit.voertuig.nummerplaat, "TAX002");
});

test("TXAA674 is never borrowed when the roster names another vehicle", () => {
  const hydrated = hydrate({
    vehicle: { vehicle_id: "vh_1786881139131", license_plate: "Tax002" },
    assignment: { vehicle_id: "vh_1787076028764" },
  });
  assert.notEqual(hydrated.kentekenplaat, "T-XAA-674");
  assert.equal(hydrated.plate_substituted_from, null);
});
