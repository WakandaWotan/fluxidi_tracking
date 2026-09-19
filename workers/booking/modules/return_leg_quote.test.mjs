// AIRPORT-RETURN-QUOTE-P0 — return leg inputs, money and failure contract.
// Run: node --test workers/booking/modules/return_leg_quote.test.mjs

import test from "node:test";
import assert from "node:assert/strict";

import {
  RETURN_QUOTE_FAILED,
  RETURN_QUOTE_PHASES,
  addressesMatch,
  centsToAmount,
  explicitReturnPoints,
  isReverseOfOutbound,
  isUsableAmount,
  momentMsFromDateTime,
  normalizeAddressForCompare,
  resolveReturnRoutePoints,
  returnAfterOutboundParts,
  returnMomentAfterOutbound,
  returnQuoteError,
  returnQuoteFailure,
  returnQuotePhaseOf,
  returnQuoteReasonOf,
  returnScheduleRequested,
  sanitizeReturnStops,
  sumLegAmounts,
  toCents,
} from "./return_leg_quote.mjs";

const GENT = { lat: 51.0543, lng: 3.7253 };
const BRU = { lat: 50.9014, lng: 4.4844 };

// ---------------------------------------------------------------------------
// Address comparison
// ---------------------------------------------------------------------------

test("addresses compare on meaning, not on punctuation or accents", () => {
  assert.equal(normalizeAddressForCompare("Korenmarkt, Gent"), "korenmarkt gent");
  assert.equal(addressesMatch("Korenmarkt, Gent", "korenmarkt  gent"), true);
  assert.equal(addressesMatch("Liège Airport", "Liege Airport"), true);
  assert.equal(addressesMatch("Korenmarkt, Gent", "Korenmarkt, Genk"), false);
  assert.equal(addressesMatch("", "Korenmarkt"), false);
});

test("only an exact reversal of the outbound leg counts as reverse", () => {
  const outbound = { outboundFrom: "Korenmarkt, Gent", outboundTo: "Brussels Airport, Zaventem" };
  assert.equal(
    isReverseOfOutbound({
      ...outbound,
      returnFrom: "brussels airport, zaventem",
      returnTo: "Korenmarkt, Gent",
    }),
    true,
  );
  // Customer edited the return destination: not a reversal any more.
  assert.equal(
    isReverseOfOutbound({
      ...outbound,
      returnFrom: "Brussels Airport, Zaventem",
      returnTo: "Sint-Pietersnieuwstraat, Gent",
    }),
    false,
  );
  // Same addresses but not swapped.
  assert.equal(
    isReverseOfOutbound({
      ...outbound,
      returnFrom: "Korenmarkt, Gent",
      returnTo: "Brussels Airport, Zaventem",
    }),
    false,
  );
});

// ---------------------------------------------------------------------------
// Return coordinates
// ---------------------------------------------------------------------------

test("explicit return coordinates win over everything else", () => {
  const resolved = resolveReturnRoutePoints({
    body: {
      return_from_lat: BRU.lat,
      return_from_lng: BRU.lng,
      return_to_lat: GENT.lat,
      return_to_lng: GENT.lng,
    },
    outboundFrom: "Korenmarkt, Gent",
    outboundTo: "Brussels Airport",
    returnFrom: "Brussels Airport",
    returnTo: "Korenmarkt, Gent",
    outboundFromPoint: GENT,
    outboundToPoint: BRU,
  });
  assert.deepEqual(resolved.fromPoint, BRU);
  assert.deepEqual(resolved.toPoint, GENT);
  assert.equal(resolved.strategy, "explicit");
  assert.equal(resolved.needsGeocode, false);
});

test("an exact reversal safely reuses the swapped outbound coordinates", () => {
  const resolved = resolveReturnRoutePoints({
    body: {},
    outboundFrom: "Korenmarkt, Gent",
    outboundTo: "Brussels Airport, Zaventem",
    returnFrom: "Brussels Airport, Zaventem",
    returnTo: "Korenmarkt, Gent",
    outboundFromPoint: GENT,
    outboundToPoint: BRU,
  });
  assert.deepEqual(resolved.fromPoint, BRU);
  assert.deepEqual(resolved.toPoint, GENT);
  assert.equal(resolved.strategy, "reverse_outbound");
  assert.equal(resolved.reverseOfOutbound, true);
  assert.equal(resolved.needsGeocode, false);
});

test("edited return addresses are left to be geocoded separately", () => {
  const resolved = resolveReturnRoutePoints({
    body: {},
    outboundFrom: "Korenmarkt, Gent",
    outboundTo: "Brussels Airport, Zaventem",
    returnFrom: "Brussels Airport, Zaventem",
    returnTo: "Sint-Pietersnieuwstraat, Gent",
    outboundFromPoint: GENT,
    outboundToPoint: BRU,
  });
  assert.equal(resolved.fromPoint, null);
  assert.equal(resolved.toPoint, null);
  assert.equal(resolved.strategy, "geocode");
  assert.equal(resolved.needsGeocode, true);
});

test("unusable coordinates are refused instead of routing to null island", () => {
  assert.deepEqual(explicitReturnPoints({ return_from_lat: 0, return_from_lng: 0 }).from, null);
  assert.deepEqual(explicitReturnPoints({ return_to_lat: 91, return_to_lng: 4 }).to, null);
  assert.deepEqual(explicitReturnPoints({ return_from_lat: "abc", return_from_lng: 4 }).from, null);
  assert.deepEqual(
    explicitReturnPoints({ return_from_lat: "50.9014", return_from_lng: "4.4844" }).from,
    BRU,
  );
});

test("one explicit endpoint plus one edited endpoint reports partial geocoding", () => {
  const resolved = resolveReturnRoutePoints({
    body: { return_from_lat: BRU.lat, return_from_lng: BRU.lng },
    outboundFrom: "Korenmarkt, Gent",
    outboundTo: "Brussels Airport",
    returnFrom: "Brussels Airport",
    returnTo: "Sint-Pietersnieuwstraat, Gent",
    outboundFromPoint: GENT,
    outboundToPoint: BRU,
  });
  assert.deepEqual(resolved.fromPoint, BRU);
  assert.equal(resolved.toPoint, null);
  assert.equal(resolved.strategy, "partial_geocode");
  assert.equal(resolved.needsGeocode, true);
});

// ---------------------------------------------------------------------------
// Return stops
// ---------------------------------------------------------------------------

test("return stops keep their order, drop empties and never become [object Object]", () => {
  const stops = sanitizeReturnStops({
    return_stops: [
      { address: "Aalst", lat: 50.9, lng: 4.03 },
      { address: "   " },
      "Wetteren",
      { text: "Merelbeke" },
      null,
    ],
  });
  assert.deepEqual(stops, ["Aalst", "Wetteren", "Merelbeke"]);
  assert.equal(
    sanitizeReturnStops({ return_stops: [{ lat: 1, lng: 2 }] }).length,
    0,
    "a stop without any address text is dropped, not sent as an object",
  );
  assert.deepEqual(sanitizeReturnStops({ returnStops: ["Aalst"] }), ["Aalst"]);
  assert.equal(sanitizeReturnStops({}).length, 0);
  assert.equal(
    sanitizeReturnStops({ return_stops: ["a", "b", "c", "d", "e", "f", "g"] }).length,
    6,
  );
});

// ---------------------------------------------------------------------------
// Money
// ---------------------------------------------------------------------------

test("leg totals are summed in whole cents", () => {
  assert.equal(toCents("144.60"), 14460);
  assert.equal(toCents("144,60"), 14460);
  assert.equal(toCents(null), null);
  assert.equal(toCents("abc"), null);
  assert.equal(centsToAmount(14460), 144.6);
  assert.equal(sumLegAmounts(0.1, 0.2), 0.3);
  assert.equal(sumLegAmounts(200, 200), 400);
  assert.equal(sumLegAmounts(144.6, 131.1), 275.7);
  assert.equal(sumLegAmounts("81.70", "79.20"), 160.9);
});

test("a requested return leg without an amount has no total at all", () => {
  assert.equal(sumLegAmounts(131.1, null, { returnRequired: true }), null);
  assert.equal(sumLegAmounts(131.1, null, { returnRequired: false }), 131.1);
  assert.equal(sumLegAmounts(null, 131.1), null);
  assert.equal(isUsableAmount(0), true);
  assert.equal(isUsableAmount(null), false);
  assert.equal(isUsableAmount("x"), false);
});

// ---------------------------------------------------------------------------
// Return moment
// ---------------------------------------------------------------------------

test("only a return with its own date and time is a scheduled return", () => {
  assert.equal(
    returnScheduleRequested({ return_enabled: true, return_date: "2026-09-27", return_time: "18:00" }),
    true,
  );
  // Waiting round trip: one leg, no separate schedule, unchanged pricing.
  assert.equal(returnScheduleRequested({ return_enabled: true, wait_min: 45 }), false);
  assert.equal(
    returnScheduleRequested({ return_enabled: false, return_date: "2026-09-27", return_time: "18:00" }),
    false,
  );
  assert.equal(returnScheduleRequested(null), false);
});

test("the return leg must start after the outbound leg", () => {
  assert.equal(
    returnMomentAfterOutbound("2026-09-25T09:30:00.000Z", "2026-09-25T16:00:00.000Z"),
    true,
  );
  assert.equal(
    returnMomentAfterOutbound("2026-09-25T09:30:00.000Z", "2026-09-27T16:00:00.000Z"),
    true,
  );
  assert.equal(
    returnMomentAfterOutbound("2026-09-25T09:30:00.000Z", "2026-09-25T07:00:00.000Z"),
    false,
  );
  assert.equal(
    returnMomentAfterOutbound("2026-09-25T09:30:00.000Z", "2026-09-25T09:30:00.000Z"),
    false,
  );
});

test("the same rule holds on raw date and time parts, in both client formats", () => {
  const outbound = { outboundDate: "2026-09-25", outboundTime: "11:30" };
  assert.equal(
    returnAfterOutboundParts({ ...outbound, returnDate: "2026-09-25", returnTime: "22:15" }),
    true,
  );
  assert.equal(
    returnAfterOutboundParts({ ...outbound, returnDate: "2026-09-27", returnTime: "18:00" }),
    true,
  );
  assert.equal(
    returnAfterOutboundParts({ ...outbound, returnDate: "2026-09-25", returnTime: "07:00" }),
    false,
  );
  assert.equal(
    returnAfterOutboundParts({ ...outbound, returnDate: "2026-09-24", returnTime: "23:59" }),
    false,
  );
  assert.equal(
    returnAfterOutboundParts({
      outboundDate: "25/09/2026",
      outboundTime: "11:30",
      returnDate: "25/09/2026",
      returnTime: "07:00",
    }),
    false,
  );
  assert.equal(Number.isNaN(momentMsFromDateTime("not-a-date", "11:30")), true);
  assert.equal(
    momentMsFromDateTime("2026-09-25", "11:30"),
    momentMsFromDateTime("25/09/2026", "11:30"),
  );
});

// ---------------------------------------------------------------------------
// Failure contract
// ---------------------------------------------------------------------------

test("a failed return leg answers with one stable code and no amounts", () => {
  const failure = returnQuoteFailure({
    phase: RETURN_QUOTE_PHASES.ROUTE,
    reason: "return_route_not_usable",
  });
  assert.equal(failure.status, 422);
  assert.equal(failure.out.ok, false);
  assert.equal(failure.out.error, RETURN_QUOTE_FAILED);
  assert.equal(failure.out.error_code, "return_quote_failed");
  assert.equal(failure.out.price_incl_vat, null);
  assert.equal(failure.out.price_incl_vat_main, null);
  assert.equal(failure.out.price_incl_vat_return, null);
  assert.equal(failure.out.total_price_incl_vat, null);
  assert.equal(failure.out.pricing_source_return, null);
  assert.equal(failure.out.return, null);
  // The phase stays internal: it is logged, never sent to the storefront.
  assert.equal(failure.phase, "return_route");
  assert.equal(failure.reason, "return_route_not_usable");
  assert.equal("phase" in failure.out, false);
  assert.equal("reason" in failure.out, false);
  assert.match(failure.logLine, /phase=return_route reason=return_route_not_usable/);
  assert.equal(/[0-9]/.test(failure.out.message), false, "no amounts in the customer message");
});

test("every internal phase is preserved and unknown phases fall back to pricing", () => {
  for (const phase of Object.values(RETURN_QUOTE_PHASES)) {
    assert.equal(returnQuoteFailure({ phase, reason: "x" }).phase, phase);
  }
  assert.equal(returnQuoteFailure({ phase: "nonsense" }).phase, "return_pricing");
  const tagged = returnQuoteError(RETURN_QUOTE_PHASES.GEOCODE, "return_geocode_no_features");
  assert.equal(tagged.message, RETURN_QUOTE_FAILED);
  assert.equal(returnQuotePhaseOf(tagged, RETURN_QUOTE_PHASES.PRICING), "return_geocode");
  assert.equal(returnQuoteReasonOf(tagged, "other"), "return_geocode_no_features");
  // An untagged failure keeps the caller's phase hint.
  assert.equal(returnQuotePhaseOf(new Error("boom"), RETURN_QUOTE_PHASES.FIXED_PRICE), "return_fixed_price");
  assert.equal(returnQuoteReasonOf(new Error("boom"), "fallback"), "fallback");
});
