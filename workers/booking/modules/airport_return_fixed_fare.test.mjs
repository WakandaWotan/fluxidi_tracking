// Dossier 01 — airport round trip 200 + 200 must bill 400, never 401.
//
// Run:
//   node --test workers/booking/modules/airport_return_fixed_fare.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  AIRPORT_RETURN_FALLBACK_REASONS,
  airportReturnAddressKey,
  airportReturnAddressesMatch,
  airportReturnCoordsMatch,
  airportRoundTripTotalConsistency,
  composeAirportRoundTripTotals,
  resolveAirportReturnFixedFareDecision,
} from "./airport_return_fixed_fare.mjs";

const WORKER_SOURCE = readFileSync(
  new URL("../fluxidi_booking_worker.js", import.meta.url),
  "utf8",
);

// The observed booking: 19/09/2026 quote screen, Brussels South Charleroi
// Airport round trip, return 29/09/2026 23:00, shown total EUR 401,00.
const CHARLEROI = "Brussels South Charleroi Airport, Belgium";
const OUTBOUND_PICKUP = "Koekamerstraat 48A, 9688 Louise-Marie, Oost-Vlaanderen, België";
const RETURN_DROPOFF = "Koekamerstraat 48A, 9688";

// The gate that shipped in 1.0.4+25: byte-identical reverse addresses.
function legacyReverseByAddress({ returnFrom, returnTo, outboundFrom, outboundTo }) {
  return (
    String(returnFrom).trim().toLowerCase() === String(outboundTo).trim().toLowerCase() &&
    String(returnTo).trim().toLowerCase() === String(outboundFrom).trim().toLowerCase()
  );
}

function charleroiRoundTrip(overrides = {}) {
  return {
    returnRequested: true,
    mainFixedFareApplied: true,
    explicitReturnMatched: false,
    outboundDirection: "to_airport",
    returnDirection: "from_airport",
    outboundFrom: OUTBOUND_PICKUP,
    outboundTo: CHARLEROI,
    returnFrom: CHARLEROI,
    returnTo: RETURN_DROPOFF,
    ...overrides,
  };
}

test("reproduction: the shipped byte-equality gate denied the fixed fare for the Charleroi round trip", () => {
  const trip = charleroiRoundTrip();
  assert.equal(
    legacyReverseByAddress({
      returnFrom: trip.returnFrom,
      returnTo: trip.returnTo,
      outboundFrom: trip.outboundFrom,
      outboundTo: trip.outboundTo,
    }),
    false,
    "the airport side matched but the customer address text differed, so reuse was refused",
  );
  assert.equal(
    resolveAirportReturnFixedFareDecision(trip).fallbackReason,
    AIRPORT_RETURN_FALLBACK_REASONS.reusedMainFixedFareRule,
  );
});

test("the same place written differently keeps the outbound fixed fare", () => {
  const decision = resolveAirportReturnFixedFareDecision(charleroiRoundTrip());
  assert.equal(decision.useMainFixedFare, true);
  assert.equal(decision.fallbackReason, "reused_main_fixed_fare_rule");
});

test("coordinates inside 250 m keep the fixed fare even when the text is unrecognisable", () => {
  const decision = resolveAirportReturnFixedFareDecision(
    charleroiRoundTrip({
      returnTo: "huis",
      outboundUserSideCoords: { lat: 50.7452, lng: 3.5981 },
      returnUserSideCoords: { lat: 50.7454, lng: 3.5983 },
    }),
  );
  assert.equal(decision.useMainFixedFare, true);
});

test("a genuinely different return address still falls back to the calculator", () => {
  const decision = resolveAirportReturnFixedFareDecision(
    charleroiRoundTrip({ returnTo: "Grote Markt 1, 2000 Antwerpen" }),
  );
  assert.equal(decision.useMainFixedFare, false);
  assert.equal(decision.fallbackReason, "return_addresses_not_reverse");
});

test("a different house number in the same street is not the same place", () => {
  const decision = resolveAirportReturnFixedFareDecision(
    charleroiRoundTrip({ returnTo: "Koekamerstraat 12, 9688" }),
  );
  assert.equal(decision.useMainFixedFare, false);
  assert.equal(decision.fallbackReason, "return_addresses_not_reverse");
});

test("a return leg that lands at another airport is not the reverse trip", () => {
  const decision = resolveAirportReturnFixedFareDecision(
    charleroiRoundTrip({ returnFrom: "Brussels Airport, Belgium" }),
  );
  assert.equal(decision.useMainFixedFare, false);
  assert.equal(decision.fallbackReason, "return_airport_side_not_reverse");
});

test("a return direction that is not the reverse is refused", () => {
  const decision = resolveAirportReturnFixedFareDecision(
    charleroiRoundTrip({ returnDirection: "to_airport" }),
  );
  assert.equal(decision.useMainFixedFare, false);
  assert.equal(decision.fallbackReason, "return_direction_not_reverse");
});

test("from_airport outbound reverses the sides", () => {
  const decision = resolveAirportReturnFixedFareDecision({
    returnRequested: true,
    mainFixedFareApplied: true,
    outboundDirection: "from_airport",
    returnDirection: "to_airport",
    outboundFrom: CHARLEROI,
    outboundTo: OUTBOUND_PICKUP,
    returnFrom: RETURN_DROPOFF,
    returnTo: CHARLEROI,
  });
  assert.equal(decision.useMainFixedFare, true);
});

test("an explicit return rule wins over reuse, and a calculated outbound never reuses", () => {
  assert.equal(
    resolveAirportReturnFixedFareDecision(
      charleroiRoundTrip({ explicitReturnMatched: true }),
    ).fallbackReason,
    "explicit_return_fixed_fare",
  );
  assert.equal(
    resolveAirportReturnFixedFareDecision(
      charleroiRoundTrip({ mainFixedFareApplied: false }),
    ).fallbackReason,
    "main_not_fixed_fare",
  );
  assert.equal(
    resolveAirportReturnFixedFareDecision(
      charleroiRoundTrip({ returnRequested: false }),
    ).fallbackReason,
    "not_requested",
  );
});

test("address key strips accents, punctuation and case", () => {
  assert.equal(
    airportReturnAddressKey("Koekamerstraat 48A, 9688 Louise-Marie, België"),
    "koekamerstraat 48a 9688 louise marie belgie",
  );
  assert.equal(airportReturnAddressesMatch("", "Koekamerstraat 48A"), false);
  assert.equal(airportReturnCoordsMatch(null, { lat: 1, lng: 1 }), false);
});

test("200 + 200 is exactly 40000 cents", () => {
  const totals = composeAirportRoundTripTotals({
    main: { price_ex_vat: 188.68, price_vat: 11.32, price_incl_vat: 200 },
    ret: { price_ex_vat: 188.68, price_vat: 11.32, price_incl_vat: 200 },
  });
  assert.equal(totals.price_incl_vat_main_cents, 20000);
  assert.equal(totals.price_incl_vat_return_cents, 20000);
  assert.equal(totals.total_price_incl_vat_cents, 40000);
  assert.equal(totals.total_price_incl_vat, 400);
});

test("a calculator-priced return leg is what produced 40100 cents", () => {
  const totals = composeAirportRoundTripTotals({
    main: { price_incl_vat: 200 },
    ret: { price_incl_vat: 201 },
  });
  assert.equal(totals.total_price_incl_vat_cents, 40100);
  assert.equal(totals.total_price_incl_vat, 401);
});

test("a single leg keeps a null return total", () => {
  const totals = composeAirportRoundTripTotals({ main: { price_incl_vat: 200 } });
  assert.equal(totals.price_incl_vat_return_cents, null);
  assert.equal(totals.total_price_incl_vat_cents, 20000);
});

test("a listed total that disagrees with the legs is reported, not repaired", () => {
  const drift = airportRoundTripTotalConsistency({
    mainIncl: 200,
    returnIncl: 200,
    listedTotal: 401,
  });
  assert.equal(drift.comparable, true);
  assert.equal(drift.consistent, false);
  assert.equal(drift.legSumCents, 40000);
  assert.equal(drift.listedCents, 40100);
  assert.equal(drift.driftCents, 100);

  const clean = airportRoundTripTotalConsistency({
    mainIncl: 200,
    returnIncl: 200,
    listedTotal: 400,
  });
  assert.equal(clean.consistent, true);
  assert.equal(clean.driftCents, 0);
  assert.equal(
    airportRoundTripTotalConsistency({ mainIncl: 200, listedTotal: 200 }).comparable,
    false,
  );
});

test("quote and book both delegate the return decision to this module", () => {
  assert.ok(
    WORKER_SOURCE.includes('from "./modules/airport_return_fixed_fare.mjs"'),
    "worker must import the shared decision module",
  );
  const calls = WORKER_SOURCE.match(/resolveAirportReturnFixedFareDecision\(/g) || [];
  assert.equal(calls.length, 2, "one call in /quote and one in /book");
  const totals = WORKER_SOURCE.match(/composeAirportRoundTripTotals\(/g) || [];
  assert.equal(totals.length, 2, "quote and book totals both summed in cents");
});

test("the byte-identical reverse gate is gone from the worker", () => {
  assert.ok(
    !WORKER_SOURCE.includes("const reverseByAddress ="),
    "inline reverseByAddress must be replaced by the shared decision",
  );
  assert.ok(
    !WORKER_SOURCE.includes("const reverseByDirection ="),
    "inline reverseByDirection must be replaced by the shared decision",
  );
});
