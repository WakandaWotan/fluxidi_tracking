// CHIRON-OFFLINE-ARRIVAL-P0-2 — Vertrektijdstip precision drift on replay.
//
// Field 03/08/2026, two street rides reached Chiron as Vertrek only:
//   * 16:17 street_1785766676167_7d1gy8ov, ride_start/ride_stop carry
//     started_at_utc = 2026-08-03T14:17:54.831478Z
//   * 16:45 street_1785768346529_2p5ohae0, ride_stop carries
//     started_at_utc = 2026-08-03T14:45:44.431816Z
// Chiron stores milliseconds (.831 / .431), so every replay of the
// microsecond-precision source value read as a CHANGED Vertrektijdstip and
// Chiron answered CH1303 ("Vertrektijdstip kreeg een nieuwe waarde … (oude
// waarde is …)"). The departure stayed failed/definitive and both Aankomst
// messages stayed parked on waiting_for_departure.
//
//   node --test workers/compliance/chiron_vertrektijdstip_precision_p0_2.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { __testInternals } from "./fluxidi_compliance_worker.js";

const {
  chironCanonicalDateTimeMs,
  _chironFreezeOutboundImmutableFields,
  _chironOutboundFingerprint,
  _chironEvaluateSubmitDuplicateGuard,
  _chironDuplicateVertrekFoutcodes,
  _chironIsDuplicateVertrekRejection,
  parseChironTaxiritSubmitResponse,
  buildChironOfficialPayloadDraft,
  buildChironTaxiritApiPayload,
  CHIRON_NEVER_CONFIRMING_FOUTCODES,
  CHIRON_FROZEN_OUTBOUND_FIELDS,
  CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS,
  CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS,
} = __testInternals;

// Exact field values from the stranded rides.
const FIELD_START_1617 = "2026-08-03T14:17:54.831478Z";
const FIELD_START_1645 = "2026-08-03T14:45:44.431816Z";
const CHIRON_STORED_1617 = "2026-08-03T14:17:54.831Z";
const CHIRON_STORED_1645 = "2026-08-03T14:45:44.431Z";

function rideStopEvent(overrides = {}) {
  return {
    event_type: "ride_stop",
    tenant_id: "t1",
    company_id: "c1",
    booking_id: "street_1785768346529_2p5ohae0",
    trip_id: "trip_4ebd45d6",
    created_at_utc: "2026-08-03T14:48:29.543Z",
    timestamps: {
      started_at_utc: FIELD_START_1645,
      stopped_at_utc: "2026-08-03T14:48:27.077123Z",
      event_at_utc: "2026-08-03T14:48:27.077123Z",
    },
    locations: {
      pickup: { lat: 50.7720822, lng: 3.6695827 },
      dropoff: { lat: 50.747619, lng: 3.602047 },
    },
    fare: { currency: "EUR", total_amount: 6.8, distance_km: 0.8264518597481564 },
    ...overrides,
  };
}

function wirePayload(overrides = {}) {
  return {
    status: "vertrek",
    ritnummer: "street_1785768346529_2p5ohae0",
    registratie: "0772.931.038",
    naam: "Fluxidi",
    broncreatiedatum: "2026-08-03T14:48:29.543Z",
    kentekenplaat: "1-ABC-123",
    bestuurderspasnummer: "PAS-1",
    vertrektijdstip: FIELD_START_1645,
    vertrekpunt_lengtegraad: 3.6695827,
    vertrekpunt_breedtegraad: 50.7720822,
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// A. sub-millisecond source values serialize to exactly 3 fractional digits
// ---------------------------------------------------------------------------

test("1) microsecond source timestamps canonicalize to exactly 3 fractional digits", () => {
  assert.equal(chironCanonicalDateTimeMs(FIELD_START_1617), CHIRON_STORED_1617);
  assert.equal(chironCanonicalDateTimeMs(FIELD_START_1645), CHIRON_STORED_1645);
  for (const value of [
    FIELD_START_1617,
    FIELD_START_1645,
    "2026-08-03T14:48:27.077Z",
    "2026-08-03T14:48:27.0771234567Z",
    "2026-08-03T14:48:27Z",
  ]) {
    const canonical = chironCanonicalDateTimeMs(value);
    assert.match(canonical, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/);
  }
});

test("2) the fraction is truncated, never rounded", () => {
  // Chiron stored .431 for a .431816 source: rounding to .432 would itself be
  // a changed Vertrektijdstip.
  assert.equal(chironCanonicalDateTimeMs("2026-08-03T14:45:44.431816Z"), CHIRON_STORED_1645);
  assert.equal(chironCanonicalDateTimeMs("2026-08-03T14:45:44.4319Z"), "2026-08-03T14:45:44.431Z");
  assert.equal(chironCanonicalDateTimeMs("2026-08-03T14:45:44.9999Z"), "2026-08-03T14:45:44.999Z");
  assert.equal(chironCanonicalDateTimeMs("2026-08-03T14:45:44.1Z"), "2026-08-03T14:45:44.100Z");
});

test("3) offsets normalize to UTC and unparseable values fail closed", () => {
  assert.equal(
    chironCanonicalDateTimeMs("2026-08-03T16:45:44.431816+02:00"),
    CHIRON_STORED_1645,
  );
  // No offset: a *_at_utc field is read as UTC, not as worker-local time.
  assert.equal(chironCanonicalDateTimeMs("2026-08-03T14:45:44.431816"), CHIRON_STORED_1645);
  for (const bad of ["", null, undefined, "not-a-date", "03/08/2026 16:45", "2026-08-03"]) {
    assert.equal(chironCanonicalDateTimeMs(bad), null);
  }
});

test("4) the official draft and the wire body both carry millisecond precision", () => {
  const draft = buildChironOfficialPayloadDraft(rideStopEvent(), {}, {}, "aankomst");
  assert.equal(draft.vertrektijdstip, CHIRON_STORED_1645);
  assert.equal(draft.aankomsttijdstip, "2026-08-03T14:48:27.077Z");
  assert.equal(draft.broncreatiedatum, "2026-08-03T14:48:29.543Z");
  // Final fare, coordinates and distance travel unchanged with the arrival.
  assert.equal(draft.kostprijs, 6.8);
  assert.equal(draft.aankomstpunt_breedtegraad, 50.747619);
  assert.equal(draft.aankomstpunt_lengtegraad, 3.602047);
  assert.ok(Number(draft.afstand) > 0);

  // A stored/legacy draft that still holds microseconds can never reach the
  // wire: the serializer is the single chokepoint.
  const body = buildChironTaxiritApiPayload(wirePayload());
  assert.equal(body.rit.vertrektijdstip, CHIRON_STORED_1645);
  assert.equal(body.broncreatiedatum, "2026-08-03T14:48:29.543Z");
  const arrivalBody = buildChironTaxiritApiPayload(
    wirePayload({
      status: "aankomst",
      aankomsttijdstip: "2026-08-03T14:48:27.077123Z",
      aankomstpunt_lengtegraad: 3.602047,
      aankomstpunt_breedtegraad: 50.747619,
      afstand: 0.826,
      kostprijs: 6.8,
    }),
  );
  assert.equal(arrivalBody.rit.aankomsttijdstip, "2026-08-03T14:48:27.077Z");
  assert.equal(arrivalBody.rit.vertrektijdstip, CHIRON_STORED_1645);
  assert.equal(arrivalBody.rit.kostprijs.waarde, 6.8);
});

test("5) a present but unparseable datetime fails closed instead of shipping", () => {
  assert.equal(buildChironTaxiritApiPayload(wirePayload({ vertrektijdstip: "gisteren" })), null);
  assert.equal(buildChironTaxiritApiPayload(wirePayload({ broncreatiedatum: "gisteren" })), null);
});

// ---------------------------------------------------------------------------
// B. first send and every retry are byte-equivalent
// ---------------------------------------------------------------------------

test("6) first send and retry contain an identical Vertrektijdstip", () => {
  const first = _chironFreezeOutboundImmutableFields(
    buildChironOfficialPayloadDraft(rideStopEvent(), {}, {}, "vertrek"),
    { previousStatus: null, frozenAt: "2026-08-03T14:48:30.000Z" },
  );
  const firstBody = buildChironTaxiritApiPayload(
    wirePayload({ vertrektijdstip: first.payload.vertrektijdstip }),
  );
  assert.equal(first.frozen.fields.vertrektijdstip, CHIRON_STORED_1645);
  assert.deepEqual(first.drift, []);

  const storedDoc = {
    sync_state: "failed",
    failure_kind: "definitive",
    outbound_frozen: first.frozen,
    outbound_fingerprint: _chironOutboundFingerprint(firstBody),
  };

  // Retry rebuilt from the same source event: same bytes, same fingerprint.
  const retry = _chironFreezeOutboundImmutableFields(
    buildChironOfficialPayloadDraft(rideStopEvent(), {}, {}, "vertrek"),
    { previousStatus: storedDoc },
  );
  const retryBody = buildChironTaxiritApiPayload(
    wirePayload({ vertrektijdstip: retry.payload.vertrektijdstip }),
  );
  assert.equal(retry.payload.vertrektijdstip, first.payload.vertrektijdstip);
  assert.equal(
    _chironOutboundFingerprint(retryBody),
    storedDoc.outbound_fingerprint,
  );
  assert.equal(_chironStableEquivalent(firstBody, retryBody), true);
});

function _chironStableEquivalent(a, b) {
  return JSON.stringify(a) === JSON.stringify(b);
}

test("7) frozen fields survive a changed source value; the change is reported, not sent", () => {
  const frozen = {
    shape: "chiron_taxirit_api_v1",
    frozen_at: "2026-08-03T14:48:30.000Z",
    fields: { vertrektijdstip: CHIRON_STORED_1645, broncreatiedatum: "2026-08-03T14:48:29.543Z" },
  };
  // The app re-sends the ride with a different departure second.
  const drifted = _chironFreezeOutboundImmutableFields(
    { vertrektijdstip: "2026-08-03T14:45:59.000Z", broncreatiedatum: "2026-08-03T14:48:29.543Z" },
    { previousStatus: { outbound_frozen: frozen } },
  );
  assert.equal(drifted.payload.vertrektijdstip, CHIRON_STORED_1645);
  assert.deepEqual(drifted.drift, ["vertrektijdstip"]);
  // Evidence is field names only — no response text, no ride or customer data.
  assert.deepEqual(Object.keys(drifted.frozen).sort(), ["fields", "frozen_at", "shape"]);
  for (const name of drifted.drift) {
    assert.ok(CHIRON_FROZEN_OUTBOUND_FIELDS.includes(name));
  }
});

test("8) improvable fields are never frozen", () => {
  const result = _chironFreezeOutboundImmutableFields(
    {
      vertrektijdstip: FIELD_START_1645,
      kostprijs: 6.8,
      afstand: 0.826,
      vertrekpunt_lengtegraad: 3.6695827,
      kentekenplaat: "1-ABC-123",
    },
    { previousStatus: null },
  );
  assert.deepEqual(Object.keys(result.frozen.fields), ["vertrektijdstip"]);
  assert.equal(result.payload.kostprijs, 6.8);
  assert.equal(result.payload.afstand, 0.826);
  assert.equal(result.payload.vertrekpunt_lengtegraad, 3.6695827);
  assert.equal(result.payload.kentekenplaat, "1-ABC-123");
});

test("9) an arrival repeats the exact Vertrektijdstip Chiron already holds", () => {
  // Departure and arrival come from two different events (ride_start /
  // ride_stop), so the arrival must not re-derive the value.
  const departureDoc = {
    sync_state: "synced",
    outbound_frozen: {
      shape: "chiron_taxirit_api_v1",
      frozen_at: "2026-08-03T14:18:00.000Z",
      fields: { vertrektijdstip: CHIRON_STORED_1617 },
    },
  };
  const arrival = _chironFreezeOutboundImmutableFields(
    { vertrektijdstip: "2026-08-03T14:17:54.999999Z", aankomsttijdstip: "2026-08-03T14:21:39.241532Z" },
    { previousStatus: null, inheritFrom: departureDoc },
  );
  assert.equal(arrival.payload.vertrektijdstip, CHIRON_STORED_1617);
  assert.equal(arrival.payload.aankomsttijdstip, "2026-08-03T14:21:39.241Z");
  assert.deepEqual(arrival.drift, ["vertrektijdstip"]);

  // Inheritance is scoped to vertrektijdstip only.
  const noLeak = _chironFreezeOutboundImmutableFields(
    { aankomsttijdstip: "2026-08-03T14:21:39.241532Z" },
    {
      previousStatus: null,
      inheritFrom: {
        outbound_frozen: { fields: { aankomsttijdstip: "1999-01-01T00:00:00.000Z" } },
      },
    },
  );
  assert.equal(noLeak.payload.aankomsttijdstip, "2026-08-03T14:21:39.241Z");
});

test("10) the fingerprint is stable, key-order independent and change sensitive", () => {
  const a = _chironOutboundFingerprint({ status: "vertrek", rit: { vertrektijdstip: CHIRON_STORED_1645 } });
  const b = _chironOutboundFingerprint({ rit: { vertrektijdstip: CHIRON_STORED_1645 }, status: "vertrek" });
  const c = _chironOutboundFingerprint({ status: "vertrek", rit: { vertrektijdstip: FIELD_START_1645 } });
  assert.equal(a, b);
  assert.notEqual(a, c);
  assert.equal(_chironOutboundFingerprint(null), null);
});

// ---------------------------------------------------------------------------
// C. CH1303 never opens the arrival gate
// ---------------------------------------------------------------------------

test("11) CH1303 can never be configured as an acceptance code", () => {
  assert.ok(CHIRON_NEVER_CONFIRMING_FOUTCODES.includes("CH1303"));
  assert.deepEqual(
    _chironDuplicateVertrekFoutcodes({ CHIRON_DUPLICATE_VERTREK_FOUTCODES: "CH1303" }),
    [],
  );
  assert.deepEqual(
    _chironDuplicateVertrekFoutcodes({ CHIRON_DUPLICATE_VERTREK_FOUTCODES: " ch1303 , CH1303" }),
    [],
  );
  // Even passed straight in, CH1303 is filtered out at the classifier.
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "vertrek",
      foutenCodes: ["CH1303"],
      foutenCount: 1,
      externalStatusCode: 200,
      configuredCodes: ["CH1303"],
    }),
    false,
  );
});

test("12) a CH1303 departure stays failed, so the arrival gate stays shut", () => {
  const rejected = parseChironTaxiritSubmitResponse(200, {
    fouten: [{ foutcode: "CH1303", omschrijving: "Vertrektijdstip kreeg een nieuwe waarde" }],
  });
  assert.equal(rejected.ok, false);
  assert.deepEqual(rejected.fouten_codes, ["CH1303"]);
  // The arrival gate only opens on synced / departure_confirmed_external, and
  // CH1303 can reach neither.
  assert.equal(
    _chironIsDuplicateVertrekRejection({
      officialStatus: "vertrek",
      foutenCodes: rejected.fouten_codes,
      foutenCount: rejected.fouten_count,
      externalStatusCode: rejected.external_status_code,
      configuredCodes: _chironDuplicateVertrekFoutcodes({
        CHIRON_DUPLICATE_VERTREK_FOUTCODES: "CH1303",
      }),
    }),
    false,
  );
});

test("13) an arrival can still only become synced on 2xx plus empty fouten[]", () => {
  assert.equal(parseChironTaxiritSubmitResponse(200, { fouten: [{ foutcode: "CH1303" }] }).ok, false);
  assert.equal(parseChironTaxiritSubmitResponse(500, { fouten: [] }).ok, false);
  const accepted = parseChironTaxiritSubmitResponse(200, { fouten: [] });
  assert.equal(accepted.ok, true);
  assert.deepEqual(accepted.fouten_codes, []);
});

// ---------------------------------------------------------------------------
// D. the corrected replay is retryable; an identical rejected body is not
// ---------------------------------------------------------------------------

const COOLDOWN_PASSED = Date.parse("2026-08-03T17:19:15.376Z") + CHIRON_DEFINITIVE_RETRY_COOLDOWN_MS + 1;

function strandedDepartureDoc(overrides = {}) {
  return {
    sync_state: "failed",
    failure_kind: "definitive",
    external_status_code: 200,
    fouten_count: 1,
    fouten_codes: ["CH1303"],
    attempt_count: 4,
    last_attempt_at: "2026-08-03T17:19:15.376Z",
    ...overrides,
  };
}

test("14) the corrected replay is allowed even past the definitive attempt cap", () => {
  const guard = _chironEvaluateSubmitDuplicateGuard(
    strandedDepartureDoc({
      attempt_count: CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS + 3,
      outbound_fingerprint: "fnv1a_deadbeefdeadbeef_100",
      outbound_fingerprint_definitive_attempts: CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS,
    }),
    COOLDOWN_PASSED,
    { outboundFingerprint: "fnv1a_0000000100000002_101" },
  );
  assert.equal(guard.decision, "allow");
  assert.equal(guard.outbound_payload_changed, true);
});

test("15) the field docs (no fingerprint yet) become retryable exactly once", () => {
  const legacy = strandedDepartureDoc();
  const first = _chironEvaluateSubmitDuplicateGuard(legacy, COOLDOWN_PASSED, {
    outboundFingerprint: "fnv1a_0000000100000002_101",
  });
  assert.equal(first.decision, "allow");
  assert.equal(first.outbound_payload_changed, true);

  // After that attempt the doc carries the fingerprint; an identical rebuild is
  // bounded again by the per-payload cap.
  const afterCap = _chironEvaluateSubmitDuplicateGuard(
    {
      ...legacy,
      outbound_fingerprint: "fnv1a_0000000100000002_101",
      outbound_fingerprint_definitive_attempts: CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS,
    },
    COOLDOWN_PASSED,
    { outboundFingerprint: "fnv1a_0000000100000002_101" },
  );
  assert.equal(afterCap.decision, "not_retryable");
});

test("16) an identical rejected body stays bounded by cap and cooldown", () => {
  const same = {
    ...strandedDepartureDoc(),
    outbound_fingerprint: "fnv1a_0000000100000002_101",
    outbound_fingerprint_definitive_attempts: 1,
  };
  // Cooldown not elapsed: never retried, even with a changed payload.
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(same, Date.parse("2026-08-03T17:20:00.000Z"), {
      outboundFingerprint: "fnv1a_totally_different_9",
    }).decision,
    "not_retryable",
  );
  // Cooldown elapsed, same body, budget left: retried.
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(same, COOLDOWN_PASSED, {
      outboundFingerprint: "fnv1a_0000000100000002_101",
    }).decision,
    "allow",
  );
  // Same body, budget spent: blocked.
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(
      { ...same, outbound_fingerprint_definitive_attempts: CHIRON_DEFINITIVE_RETRY_MAX_ATTEMPTS },
      COOLDOWN_PASSED,
      { outboundFingerprint: "fnv1a_0000000100000002_101" },
    ).decision,
    "not_retryable",
  );
});

test("17) accepted and in-flight states are unaffected by the fingerprint rule", () => {
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "synced" }, COOLDOWN_PASSED, {
      outboundFingerprint: "fnv1a_new_1",
    }).decision,
    "already_synced",
  );
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard(
      { sync_state: "pending", last_attempt_at: new Date(COOLDOWN_PASSED - 1000).toISOString() },
      COOLDOWN_PASSED,
      { outboundFingerprint: "fnv1a_new_1" },
    ).decision,
    "conflict_pending",
  );
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "verification_required" }, COOLDOWN_PASSED, {
      outboundFingerprint: "fnv1a_new_1",
    }).decision,
    "verification_required",
  );
  assert.equal(
    _chironEvaluateSubmitDuplicateGuard({ sync_state: "waiting_for_departure" }, COOLDOWN_PASSED, {
      outboundFingerprint: "fnv1a_new_1",
    }).decision,
    "allow",
  );
});

test("18) both stranded rides produce exactly the value Chiron stored", () => {
  const ride1617 = buildChironOfficialPayloadDraft(
    rideStopEvent({
      booking_id: "street_1785766676167_7d1gy8ov",
      created_at_utc: "2026-08-03T14:21:41.706Z",
      timestamps: {
        started_at_utc: FIELD_START_1617,
        stopped_at_utc: "2026-08-03T14:21:39.241532Z",
      },
      fare: { currency: "EUR", total_amount: 7.9, distance_km: 0.004794334993071499 },
    }),
    {},
    {},
    "aankomst",
  );
  assert.equal(ride1617.vertrektijdstip, CHIRON_STORED_1617);
  assert.equal(ride1617.aankomsttijdstip, "2026-08-03T14:21:39.241Z");
  assert.equal(ride1617.kostprijs, 7.9);

  const ride1645 = buildChironOfficialPayloadDraft(rideStopEvent(), {}, {}, "aankomst");
  assert.equal(ride1645.vertrektijdstip, CHIRON_STORED_1645);
  assert.equal(ride1645.kostprijs, 6.8);
});
