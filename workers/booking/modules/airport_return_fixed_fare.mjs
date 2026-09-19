// Airport round trip: decide whether the return leg inherits the outbound fixed
// fare, and compose round-trip totals in integer cents.
//
// The previous inline gate in /quote and /book required byte-identical reverse
// addresses. A customer who had the return address prefilled or reformatted
// (same place, different text) silently dropped to the route calculator, so a
// 200 + 200 round trip could bill 200 + 201 = 401.

const RETURN_ADDRESS_COORD_TOLERANCE_METERS = 250;

export const AIRPORT_RETURN_FALLBACK_REASONS = Object.freeze({
  notRequested: "not_requested",
  explicitReturnFixedFare: "explicit_return_fixed_fare",
  mainNotFixedFare: "main_not_fixed_fare",
  reusedMainFixedFareRule: "reused_main_fixed_fare_rule",
  directionNotReverse: "return_direction_not_reverse",
  airportSideNotReverse: "return_airport_side_not_reverse",
  userSideNotReverse: "return_addresses_not_reverse",
});

function asText(value) {
  return typeof value === "string" ? value : value == null ? "" : String(value);
}

/**
 * Comparable form of a free-text address: accent-free lowercase alphanumeric
 * tokens. "Koekamerstraat 48A, 9688 Louise-Marie" -> "koekamerstraat 48a 9688 louise marie".
 */
export function airportReturnAddressKey(value) {
  return asText(value)
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

function addressTokens(value) {
  const key = airportReturnAddressKey(value);
  return key ? key.split(" ") : [];
}

function belgianPostcodeTokens(tokens) {
  return tokens.filter((token) => /^[0-9]{4}$/.test(token));
}

function houseNumberTokens(tokens) {
  return tokens.filter(
    (token) => /^[0-9]{1,4}[a-z]?$/.test(token) && !/^[0-9]{4}$/.test(token),
  );
}

function wordTokens(tokens) {
  return tokens.filter((token) => /[a-z]/.test(token) && !/^[0-9]/.test(token));
}

function sameTokenSet(left, right) {
  if (!left.length || !right.length) return false;
  const a = new Set(left);
  const b = new Set(right);
  for (const token of a) if (!b.has(token)) return false;
  for (const token of b) if (!a.has(token)) return false;
  return true;
}

function oneSideContainsTheOther(left, right) {
  if (!left.length || !right.length) return false;
  const a = new Set(left);
  const b = new Set(right);
  const aInB = [...a].every((token) => b.has(token));
  const bInA = [...b].every((token) => a.has(token));
  return aInB || bInA;
}

/**
 * Same real-world place written differently. Requires the identifying parts to
 * agree: postcode and house number when present, plus street/place words that
 * are a subset of one another. A different city or house number never matches.
 */
export function airportReturnAddressesMatch(left, right) {
  const leftTokens = addressTokens(left);
  const rightTokens = addressTokens(right);
  if (!leftTokens.length || !rightTokens.length) return false;
  if (sameTokenSet(leftTokens, rightTokens)) return true;

  const leftPostcodes = belgianPostcodeTokens(leftTokens);
  const rightPostcodes = belgianPostcodeTokens(rightTokens);
  if (leftPostcodes.length && rightPostcodes.length) {
    if (!sameTokenSet(leftPostcodes, rightPostcodes)) return false;
  }

  const leftHouse = houseNumberTokens(leftTokens);
  const rightHouse = houseNumberTokens(rightTokens);
  if (leftHouse.length && rightHouse.length) {
    if (!sameTokenSet(leftHouse, rightHouse)) return false;
  } else if (leftHouse.length !== rightHouse.length) {
    return false;
  }

  // Only a shared postcode or house number anchors the two texts to one place.
  // Without an anchor, "Brussels Airport" would pass as "Brussels South
  // Charleroi Airport", so the words must then match exactly.
  const anchored =
    (leftPostcodes.length > 0 && rightPostcodes.length > 0) ||
    (leftHouse.length > 0 && rightHouse.length > 0);
  const leftWords = wordTokens(leftTokens);
  const rightWords = wordTokens(rightTokens);
  return anchored
    ? oneSideContainsTheOther(leftWords, rightWords)
    : sameTokenSet(leftWords, rightWords);
}

function finiteOrNull(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

export function airportReturnCoordsMatch(
  left,
  right,
  toleranceMeters = RETURN_ADDRESS_COORD_TOLERANCE_METERS,
) {
  const leftLat = finiteOrNull(left?.lat);
  const leftLng = finiteOrNull(left?.lng);
  const rightLat = finiteOrNull(right?.lat);
  const rightLng = finiteOrNull(right?.lng);
  if (leftLat === null || leftLng === null) return false;
  if (rightLat === null || rightLng === null) return false;
  const meanLat = ((leftLat + rightLat) / 2) * (Math.PI / 180);
  const dLat = (rightLat - leftLat) * 111_320;
  const dLng = (rightLng - leftLng) * 111_320 * Math.cos(meanLat);
  return Math.sqrt(dLat * dLat + dLng * dLng) <= toleranceMeters;
}

function normalizeDirection(value) {
  const text = airportReturnAddressKey(value).replace(/ /g, "_");
  return text === "to_airport" || text === "from_airport" ? text : "";
}

/**
 * Which side of each leg is the airport and which is the customer address.
 * Outbound to_airport => outbound `to` and return `from` are the airport.
 */
function legSides({ outboundDirection, outboundFrom, outboundTo, returnFrom, returnTo }) {
  const toAirport = normalizeDirection(outboundDirection) !== "from_airport";
  return toAirport
    ? {
        outboundAirportSide: outboundTo,
        returnAirportSide: returnFrom,
        outboundUserSide: outboundFrom,
        returnUserSide: returnTo,
      }
    : {
        outboundAirportSide: outboundFrom,
        returnAirportSide: returnTo,
        outboundUserSide: outboundTo,
        returnUserSide: returnFrom,
      };
}

/**
 * Decide the return-leg pricing source for one airport round trip.
 * Returns the reason string that /quote and /book log as `fallback=`.
 */
export function resolveAirportReturnFixedFareDecision({
  returnRequested = true,
  mainFixedFareApplied = false,
  explicitReturnMatched = false,
  outboundDirection = "",
  returnDirection = "",
  outboundFrom = "",
  outboundTo = "",
  returnFrom = "",
  returnTo = "",
  outboundUserSideCoords = null,
  returnUserSideCoords = null,
} = {}) {
  const deny = (fallbackReason) => ({ useMainFixedFare: false, fallbackReason });
  if (!returnRequested) return deny(AIRPORT_RETURN_FALLBACK_REASONS.notRequested);
  if (explicitReturnMatched) {
    return deny(AIRPORT_RETURN_FALLBACK_REASONS.explicitReturnFixedFare);
  }
  if (!mainFixedFareApplied) {
    return deny(AIRPORT_RETURN_FALLBACK_REASONS.mainNotFixedFare);
  }

  const expectedReturnDirection =
    normalizeDirection(outboundDirection) === "from_airport" ? "to_airport" : "from_airport";
  const declaredReturnDirection = normalizeDirection(returnDirection);
  if (declaredReturnDirection && declaredReturnDirection !== expectedReturnDirection) {
    return deny(AIRPORT_RETURN_FALLBACK_REASONS.directionNotReverse);
  }

  const sides = legSides({ outboundDirection, outboundFrom, outboundTo, returnFrom, returnTo });
  if (!airportReturnAddressesMatch(sides.outboundAirportSide, sides.returnAirportSide)) {
    return deny(AIRPORT_RETURN_FALLBACK_REASONS.airportSideNotReverse);
  }

  const userSideMatches =
    airportReturnCoordsMatch(outboundUserSideCoords, returnUserSideCoords) ||
    airportReturnAddressesMatch(sides.outboundUserSide, sides.returnUserSide);
  if (!userSideMatches) {
    return deny(AIRPORT_RETURN_FALLBACK_REASONS.userSideNotReverse);
  }

  return {
    useMainFixedFare: true,
    fallbackReason: AIRPORT_RETURN_FALLBACK_REASONS.reusedMainFixedFareRule,
  };
}

function toCents(value) {
  const n = Number(String(value ?? "0").replace(",", "."));
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100);
}

function fromCents(cents) {
  return Math.round(cents) / 100;
}

/**
 * Round-trip totals summed in integer cents so 20000 + 20000 is exactly 40000.
 */
export function composeAirportRoundTripTotals({ main = {}, ret = null } = {}) {
  const mainExCents = toCents(main.price_ex_vat);
  const mainVatCents = toCents(main.price_vat);
  const mainInclCents = toCents(main.price_incl_vat);
  const retExCents = ret ? toCents(ret.price_ex_vat) : 0;
  const retVatCents = ret ? toCents(ret.price_vat) : 0;
  const retInclCents = ret ? toCents(ret.price_incl_vat) : 0;
  return {
    price_incl_vat_main_cents: mainInclCents,
    price_incl_vat_return_cents: ret ? retInclCents : null,
    total_price_ex_vat_cents: mainExCents + retExCents,
    total_price_vat_cents: mainVatCents + retVatCents,
    total_price_incl_vat_cents: mainInclCents + retInclCents,
    total_price_ex_vat: fromCents(mainExCents + retExCents),
    total_price_vat: fromCents(mainVatCents + retVatCents),
    total_price_incl_vat: fromCents(mainInclCents + retInclCents),
  };
}

/**
 * A round-trip total must equal the sum of its legs. Returning the mismatch
 * lets the caller report it instead of silently repairing the number.
 */
export function airportRoundTripTotalConsistency({ mainIncl, returnIncl, listedTotal } = {}) {
  const mainCents = mainIncl == null ? null : toCents(mainIncl);
  const returnCents = returnIncl == null ? null : toCents(returnIncl);
  const listedCents = listedTotal == null ? null : toCents(listedTotal);
  if (mainCents === null || returnCents === null || listedCents === null) {
    return { comparable: false, consistent: true, legSumCents: null, listedCents, driftCents: 0 };
  }
  const legSumCents = mainCents + returnCents;
  return {
    comparable: true,
    consistent: legSumCents === listedCents,
    legSumCents,
    listedCents,
    driftCents: listedCents - legSumCents,
  };
}
