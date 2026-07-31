// RELEASE-P0-CHIRON-REGISTRATION-KBO-CANONICAL-2026-07-31 — targeted tests
// for the digits-only wire canonicalization of the official Chiron
// `rit.taxibedrijf.aanbieder.registratie` field.
//
// Root cause of the previous street departure rejection:
//   Chiron ACC returned `fouten[0].omschrijving` mentioning
//   "kbonummers komen niet overeen, geauthenticeerd kbonummer (0772931038)
//    is niet gelijk aan registratie (0772.931.038)" — the OAuth-authenticated
//   KBO is byte-compared against the payload registratie, so a dotted
//   display form is rejected even though the numeric value matches.
//
// This test file guarantees:
//
//   * `chironOfficialRegistratieWire()` produces digits-only for
//     dotted / BE-prefixed / spaced / already-digits inputs;
//   * fail-closed when the input can't be normalized to exactly 10 digits;
//   * `buildChironTaxiritApiPayload()` emits
//     `rit.taxibedrijf.aanbieder.registratie = "0772931038"` and never the
//     dotted `"0772.931.038"` form;
//   * `buildChironTaxiritApiPayload()` returns null when a non-empty
//     registratie can't be canonicalized (fail-closed);
//   * the internal display form used for the idempotency key is unchanged,
//     i.e. the logical identity of the export status doc stays stable so a
//     previously definitively-failed submit is still retryable via the
//     duplicate-guard.
//
// Run:
//   node --test workers/compliance/chiron_registration_kbo_wire.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  chironOfficialRegistratieWire,
  buildChironTaxiritApiPayload,
  normalizeChironKboRegistration,
  buildChironOfficialIdempotencyKey,
  _chironEvaluateSubmitDuplicateGuard,
} = __testInternals;

const KBO_WIRE = "0772931038";
const KBO_DISPLAY = "0772.931.038";

function baseDepartureOfficialPayload(overrides = {}) {
  return {
    status: "vertrek",
    ritnummer: "street_1785495990483_qft51zlj",
    registratie: KBO_DISPLAY,
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-07-31T11:06:30.973Z",
    kentekenplaat: "T-XAA-674",
    bestuurderspasnummer: "BE1234567A8B9012",
    vertrektijdstip: "2026-07-31T10:53:28.915Z",
    vertrekpunt_lengtegraad: 4.35662,
    vertrekpunt_breedtegraad: 50.845825,
    kostprijs: 12.5,
    ...overrides,
  };
}

// -----------------------------------------------------------------------
// A. chironOfficialRegistratieWire — pure canonicalizer.
// -----------------------------------------------------------------------

test("wire-kbo: dotted 0772.931.038 → digits-only 0772931038", () => {
  assert.equal(chironOfficialRegistratieWire("0772.931.038"), "0772931038");
});

test("wire-kbo: BE-prefixed BE0772931038 → digits-only 0772931038", () => {
  assert.equal(chironOfficialRegistratieWire("BE0772931038"), "0772931038");
});

test("wire-kbo: BE-prefixed with dots BE0772.931.038 → digits-only 0772931038", () => {
  assert.equal(chironOfficialRegistratieWire("BE0772.931.038"), "0772931038");
});

test("wire-kbo: already digits-only 0772931038 → unchanged", () => {
  assert.equal(chironOfficialRegistratieWire("0772931038"), "0772931038");
});

test("wire-kbo: lower-case be prefix be0772931038 → digits-only 0772931038", () => {
  assert.equal(chironOfficialRegistratieWire("be0772931038"), "0772931038");
});

test("wire-kbo: input with surrounding whitespace → digits-only", () => {
  assert.equal(chironOfficialRegistratieWire("  0772.931.038  "), "0772931038");
});

test("wire-kbo: input with internal spaces → digits-only", () => {
  assert.equal(chironOfficialRegistratieWire("0772 931 038"), "0772931038");
});

test("wire-kbo: 9-digit input → null (fail-closed on short length)", () => {
  assert.equal(chironOfficialRegistratieWire("077293103"), null);
});

test("wire-kbo: 11-digit input → null (fail-closed on long length)", () => {
  assert.equal(chironOfficialRegistratieWire("07729310380"), null);
});

test("wire-kbo: empty/null/undefined input → null", () => {
  assert.equal(chironOfficialRegistratieWire(""), null);
  assert.equal(chironOfficialRegistratieWire(null), null);
  assert.equal(chironOfficialRegistratieWire(undefined), null);
});

test("wire-kbo: non-numeric garbage → null (fail-closed)", () => {
  assert.equal(chironOfficialRegistratieWire("abcdefghij"), null);
});

// -----------------------------------------------------------------------
// B. buildChironTaxiritApiPayload — wire body must carry digits-only KBO.
// -----------------------------------------------------------------------

test("wire-body: departure body contains registratie=0772931038, never dotted form", () => {
  const wire = buildChironTaxiritApiPayload(baseDepartureOfficialPayload());
  assert.ok(wire && typeof wire === "object", "wire body must be present");
  assert.equal(wire.rit.taxibedrijf.aanbieder.registratie, KBO_WIRE);
  const serialized = JSON.stringify(wire);
  assert.ok(
    serialized.includes(`"registratie":"${KBO_WIRE}"`),
    "wire JSON must contain digits-only registratie",
  );
  assert.ok(
    !serialized.includes(KBO_DISPLAY),
    "wire JSON must NOT contain the dotted display form of the KBO",
  );
});

test("wire-body: arrival body also carries digits-only registratie", () => {
  const wire = buildChironTaxiritApiPayload({
    status: "aankomst",
    ritnummer: "street_1785495990483_qft51zlj",
    registratie: KBO_DISPLAY,
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-07-31T11:06:30.973Z",
    aankomsttijdstip: "2026-07-31T11:10:00Z",
    aankomstpunt_lengtegraad: 4.36,
    aankomstpunt_breedtegraad: 50.85,
    afstand: 1.234,
    kostprijs: 13.5,
  });
  assert.equal(wire.rit.taxibedrijf.aanbieder.registratie, KBO_WIRE);
  assert.ok(!JSON.stringify(wire).includes(KBO_DISPLAY));
});

test("wire-body: reservatie body also carries digits-only registratie", () => {
  const wire = buildChironTaxiritApiPayload({
    status: "reservatie",
    ritnummer: "planned_x",
    registratie: KBO_DISPLAY,
    naam: "VC Construct & Graphics",
    broncreatiedatum: "2026-07-31T11:06:30.973Z",
  });
  assert.equal(wire.rit.taxibedrijf.aanbieder.registratie, KBO_WIRE);
  assert.ok(!JSON.stringify(wire).includes(KBO_DISPLAY));
});

test("wire-body: BE-prefixed input also emitted as digits-only", () => {
  const wire = buildChironTaxiritApiPayload(
    baseDepartureOfficialPayload({ registratie: "BE0772931038" }),
  );
  assert.equal(wire.rit.taxibedrijf.aanbieder.registratie, KBO_WIRE);
});

test("wire-body: null when non-empty registratie can't be canonicalized (fail-closed)", () => {
  const wire = buildChironTaxiritApiPayload(
    baseDepartureOfficialPayload({ registratie: "077293103" }),
  );
  assert.equal(wire, null);
});

test("wire-body: null when registratie contains only garbage (fail-closed)", () => {
  const wire = buildChironTaxiritApiPayload(
    baseDepartureOfficialPayload({ registratie: "not-a-kbo" }),
  );
  assert.equal(wire, null);
});

test("wire-body: registratie absent is allowed at wire level (aanbieder omitted)", () => {
  const wire = buildChironTaxiritApiPayload(
    baseDepartureOfficialPayload({ registratie: "" }),
  );
  assert.ok(wire && typeof wire === "object");
  assert.equal(wire.rit.taxibedrijf.aanbieder.registratie, undefined);
});

// -----------------------------------------------------------------------
// C. Idempotency-key identity must stay stable across the wire change.
// -----------------------------------------------------------------------

test("idempotency: internal display form still dotted, so key is unchanged", () => {
  const display = normalizeChironKboRegistration("0772931038");
  assert.equal(display, KBO_DISPLAY, "display form remains dotted");
  const scope = { tenant_id: "T1", company_id: "C1" };
  const keyBefore = buildChironOfficialIdempotencyKey(
    scope,
    KBO_DISPLAY,
    "street_1785495990483_qft51zlj",
    "vertrek",
  );
  const keyAfter = buildChironOfficialIdempotencyKey(
    scope,
    display,
    "street_1785495990483_qft51zlj",
    "vertrek",
  );
  assert.equal(keyBefore, keyAfter);
  assert.ok(
    keyBefore.includes(KBO_DISPLAY),
    "idempotency key must still carry the display (dotted) form to preserve logical identity",
  );
});

// -----------------------------------------------------------------------
// D. Retry-after-definitive-failure (Chiron rejection like CH0106 /
//    KBO-mismatch): the duplicate-guard must still allow exactly one
//    controlled retry after the previous failed/definitive attempt.
// -----------------------------------------------------------------------

test("retry: failed + definitive + external 400 + fouten>0 → allow", () => {
  const previousStatus = {
    sync_state: "failed",
    failure_kind: "definitive",
    external_status_code: 400,
    fouten_count: 1,
  };
  assert.deepEqual(_chironEvaluateSubmitDuplicateGuard(previousStatus), {
    decision: "allow",
  });
});

test("retry: failed + definitive alone → allow (guard trusts marker)", () => {
  assert.deepEqual(
    _chironEvaluateSubmitDuplicateGuard({
      sync_state: "failed",
      failure_kind: "definitive",
    }),
    { decision: "allow" },
  );
});

test("retry: still refuses when previously synced (no accidental resubmit after fix)", () => {
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
