import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  chironOfficialKentekenplaatWire,
  chironOfficialPlateMeetsCh1211,
  hydrateChironOfficialVehicleIdentity,
  verifyChironOfficialLicensePlate,
  buildChironTaxiritApiPayload,
} = __testInternals;

test("TAX002 is CH1211-short and is never padded", () => {
  assert.equal(chironOfficialKentekenplaatWire("TAX002"), "TAX002");
  assert.equal(chironOfficialPlateMeetsCh1211("TAX002"), false);
  const check = verifyChironOfficialLicensePlate("TAX002");
  assert.notEqual(check.status, "format_invalid");
  assert.ok(check.warnings.includes("ch1211_license_plate_too_short"));
});

test("hydrate prefers fleet T-XAA-674 over event TAX002", () => {
  const hydrated = hydrateChironOfficialVehicleIdentity(
    {
      vehicle_id: "veh_chiron",
      vehicle: { license_plate: "TAX002" },
    },
    {},
    {
      scopedHydrationCache: {
        fleetLookup: "hit",
        fleetVehicles: [
          { vehicle_id: "veh_chiron", license_plate: "T-XAA-674" },
        ],
      },
    },
  );
  assert.equal(hydrated.kentekenplaat, "T-XAA-674");
  assert.equal(hydrated.source, "scoped_vehicle");
});

test("serializer ships TAX002 unpadded instead of withholding the ride", () => {
  const body = buildChironTaxiritApiPayload({
    status: "vertrek",
    ritnummer: "2026-09-032",
    registratie: "0772.931.038",
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-09-18T10:00:00.000Z",
    kentekenplaat: "TAX002",
    bestuurderspasnummer: "BE1234567A8B9012",
    vertrektijdstip: "2026-09-18T10:00:00.000Z",
    vertrekpunt_lengtegraad: 4.35662,
    vertrekpunt_breedtegraad: 50.845825,
  });
  assert.equal(body.rit.voertuig.nummerplaat, "TAX002");
});
