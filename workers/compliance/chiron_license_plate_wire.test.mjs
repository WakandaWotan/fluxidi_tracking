// RELEASE-P0-CHIRON-LICENSE-PLATE-WIRE-2026-07-31 — targeted tests for the
// alphanumeric-only wire canonicalization of the official Chiron
// `rit.voertuig.nummerplaat` field.
//
// Root cause of the previous CH1212 rejection: Chiron ACC requires the
// license-plate JSON field to contain only `[A-Z0-9]`; the Fluxidi vehicle
// profile stores plates in a human-readable dashed form (e.g. `T-XAA-674`
// or `TX-ABC-123`). The compliance worker previously emitted that literal
// display form on the wire.
//
// This test file guarantees:
//
//   * `chironOfficialKentekenplaatWire()` produces uppercased,
//     alphanumeric-only text for dashed / spaced / dotted / lowercased /
//     mixed inputs;
//   * fail-closed when the input can't be reduced to at least one
//     alphanumeric character;
//   * `buildChironTaxiritApiPayload()` emits
//     `rit.voertuig.nummerplaat = "TXAA674"` and never any variant with
//     dashes / dots / spaces / lowercase;
//   * `buildChironTaxiritApiPayload()` returns null when a non-empty
//     kentekenplaat can't be canonicalized (fail-closed);
//   * the internal `officialPayload.kentekenplaat` display form is
//     UNCHANGED (this is a wire-only transform);
//   * the idempotency key is unaffected by the plate transform (it's
//     keyed on registratie + ritnummer + status), so the export-status
//     storage-key of a prior failed/definitive submit stays valid and
//     the duplicate-guard still permits a controlled retry after CH1212.
//
// Run:
//   node --test workers/compliance/chiron_license_plate_wire.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  chironOfficialKentekenplaatWire,
  buildChironTaxiritApiPayload,
  buildChironOfficialIdempotencyKey,
  _chironEvaluateSubmitDuplicateGuard,
} = __testInternals;

const PLATE_DISPLAY = "T-XAA-674";
const PLATE_WIRE = "TXAA674";
const KBO_DISPLAY = "0772.931.038";
const KBO_WIRE = "0772931038";

function baseDeparturePayload(overrides = {}) {
  return {
    status: "vertrek",
    ritnummer: "street_1785495990483_qft51zlj",
    registratie: KBO_DISPLAY,
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-07-31T11:06:30.973Z",
    kentekenplaat: PLATE_DISPLAY,
    bestuurderspasnummer: "BE1234567A8B9012",
    vertrektijdstip: "2026-07-31T10:53:28.915Z",
    vertrekpunt_lengtegraad: 4.35662,
    vertrekpunt_breedtegraad: 50.845825,
    kostprijs: 12.5,
    ...overrides,
  };
}

// -----------------------------------------------------------------------
// A. chironOfficialKentekenplaatWire — pure canonicalizer.
// -----------------------------------------------------------------------

test("wire-plate: T-XAA-674 → TXAA674", () => {
  assert.equal(chironOfficialKentekenplaatWire("T-XAA-674"), "TXAA674");
});

test("wire-plate: lowercase t-xaa-674 → TXAA674", () => {
  assert.equal(chironOfficialKentekenplaatWire("t-xaa-674"), "TXAA674");
});

test("wire-plate: mixed case T-xAa-674 → TXAA674", () => {
  assert.equal(chironOfficialKentekenplaatWire("T-xAa-674"), "TXAA674");
});

test("wire-plate: spaces T XAA 674 → TXAA674", () => {
  assert.equal(chironOfficialKentekenplaatWire("T XAA 674"), "TXAA674");
});

test("wire-plate: dots T.XAA.674 → TXAA674", () => {
  assert.equal(chironOfficialKentekenplaatWire("T.XAA.674"), "TXAA674");
});

test("wire-plate: already alphanumeric TXAA674 → unchanged", () => {
  assert.equal(chironOfficialKentekenplaatWire("TXAA674"), "TXAA674");
});

test("wire-plate: leading/trailing whitespace stripped", () => {
  assert.equal(chironOfficialKentekenplaatWire("  T-XAA-674  "), "TXAA674");
});

test("wire-plate: standard Belgian plate 1-ABC-123 → 1ABC123", () => {
  assert.equal(chironOfficialKentekenplaatWire("1-ABC-123"), "1ABC123");
});

test("wire-plate: taxi plate TX-ABC-123 → TXABC123", () => {
  assert.equal(chironOfficialKentekenplaatWire("TX-ABC-123"), "TXABC123");
});

test("wire-plate: empty string → null (fail-closed)", () => {
  assert.equal(chironOfficialKentekenplaatWire(""), null);
});

test("wire-plate: null/undefined → null", () => {
  assert.equal(chironOfficialKentekenplaatWire(null), null);
  assert.equal(chironOfficialKentekenplaatWire(undefined), null);
});

test("wire-plate: only separators → null (fail-closed)", () => {
  assert.equal(chironOfficialKentekenplaatWire("---"), null);
  assert.equal(chironOfficialKentekenplaatWire("...  ..."), null);
});

test("wire-plate: unicode / diacritics stripped, digits kept", () => {
  assert.equal(chironOfficialKentekenplaatWire("Té-XÀA-674"), "TXA674");
});

// -----------------------------------------------------------------------
// B. buildChironTaxiritApiPayload — wire body must carry alphanumeric plate.
// -----------------------------------------------------------------------

test("wire-body: departure emits nummerplaat=TXAA674 and never T-XAA-674", () => {
  const wire = buildChironTaxiritApiPayload(baseDeparturePayload());
  assert.ok(wire && typeof wire === "object");
  assert.equal(wire.rit.voertuig.nummerplaat, PLATE_WIRE);
  const serialized = JSON.stringify(wire);
  assert.ok(
    serialized.includes(`"nummerplaat":"${PLATE_WIRE}"`),
    "wire JSON must contain alphanumeric-only plate",
  );
  assert.ok(
    !serialized.includes(PLATE_DISPLAY),
    "wire JSON must NOT contain the dashed display plate",
  );
  assert.ok(
    !serialized.includes("t-xaa-674"),
    "wire JSON must NOT contain any lowercase dashed variant",
  );
});

test("wire-body: arrival emits nummerplaat=TXAA674 and never T-XAA-674", () => {
  const wire = buildChironTaxiritApiPayload({
    status: "aankomst",
    ritnummer: "street_1785495990483_qft51zlj",
    registratie: KBO_DISPLAY,
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-07-31T11:06:30.973Z",
    kentekenplaat: PLATE_DISPLAY,
    bestuurderspasnummer: "BE1234567A8B9012",
    aankomsttijdstip: "2026-07-31T11:10:00Z",
    aankomstpunt_lengtegraad: 4.36,
    aankomstpunt_breedtegraad: 50.85,
    afstand: 1.234,
    kostprijs: 13.5,
  });
  assert.equal(wire.rit.voertuig.nummerplaat, PLATE_WIRE);
  assert.ok(!JSON.stringify(wire).includes(PLATE_DISPLAY));
});

test("wire-body: registratie stays digits-only alongside the plate transform", () => {
  const wire = buildChironTaxiritApiPayload(baseDeparturePayload());
  assert.equal(wire.rit.taxibedrijf.aanbieder.registratie, KBO_WIRE);
  const serialized = JSON.stringify(wire);
  assert.ok(!serialized.includes(KBO_DISPLAY));
});

test("wire-body: reservatie has no voertuig block regardless of plate", () => {
  const wire = buildChironTaxiritApiPayload({
    status: "reservatie",
    ritnummer: "planned_x",
    registratie: KBO_DISPLAY,
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-07-31T11:06:30.973Z",
    kentekenplaat: PLATE_DISPLAY,
  });
  assert.ok(wire && typeof wire === "object");
  assert.equal(wire.rit.voertuig, undefined);
  assert.ok(!JSON.stringify(wire).includes(PLATE_DISPLAY));
});

test("wire-body: fail-closed when non-empty plate can't be canonicalized", () => {
  const wire = buildChironTaxiritApiPayload(
    baseDeparturePayload({ kentekenplaat: "---" }),
  );
  assert.equal(wire, null);
});

test("wire-body: plate absent is allowed (voertuig omitted, body still emitted)", () => {
  const wire = buildChironTaxiritApiPayload(
    baseDeparturePayload({ kentekenplaat: "" }),
  );
  assert.ok(wire && typeof wire === "object");
  assert.equal(wire.rit.voertuig, undefined);
});

test("wire-body: internal officialPayload.kentekenplaat display form is NOT mutated", () => {
  const original = baseDeparturePayload();
  const before = original.kentekenplaat;
  buildChironTaxiritApiPayload(original);
  assert.equal(
    original.kentekenplaat,
    before,
    "officialPayload.kentekenplaat must remain the dashed display form for internal use",
  );
  assert.equal(before, PLATE_DISPLAY);
});

// -----------------------------------------------------------------------
// C. Idempotency-key + storage-key stability across the plate transform.
// -----------------------------------------------------------------------

test("idempotency: key is keyed on registratie/ritnummer/status, plate transform doesn't shift it", () => {
  const scope = { tenant_id: "T1", company_id: "C1" };
  const keyWithDashedPlate = buildChironOfficialIdempotencyKey(
    scope,
    KBO_DISPLAY,
    "street_1785495990483_qft51zlj",
    "vertrek",
  );
  const keyAgain = buildChironOfficialIdempotencyKey(
    scope,
    KBO_DISPLAY,
    "street_1785495990483_qft51zlj",
    "vertrek",
  );
  assert.equal(keyWithDashedPlate, keyAgain);
  assert.ok(
    !keyWithDashedPlate.includes(PLATE_DISPLAY) &&
      !keyWithDashedPlate.includes(PLATE_WIRE),
    "plate must not participate in the idempotency key",
  );
});

// -----------------------------------------------------------------------
// D. Retry after CH1212 rejection (Chiron 200 with fouten>0 = definitive).
// -----------------------------------------------------------------------

test("retry: failed + definitive + Chiron 200 + fouten>0 (CH1212 shape) → allow", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      failure_kind: "definitive",
      external_status_code: 200,
      fouten_count: 1,
    }),
    { decision: "allow" },
  );
});

test("retry: still refuses when previously synced (no accidental resubmit after plate fix)", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "synced",
      external_status_code: 200,
      fouten_count: 0,
    }),
    { decision: "already_synced" },
  );
});

test("retry: still refuses when verification_required (operator resolution needed)", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "verification_required",
    }),
    { decision: "verification_required" },
  );
});
