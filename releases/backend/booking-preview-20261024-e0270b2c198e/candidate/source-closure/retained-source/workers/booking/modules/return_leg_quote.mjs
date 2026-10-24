/* AIRPORT-RETURN-QUOTE-P0 — server-authoritative inputs for a scheduled return leg.
 *
 * A scheduled return leg (return_date + return_time, no waiting) is a second
 * real trip: its own addresses, its own moment, its own price. This module owns
 * the parts of that leg which can be decided without Mapbox or KV:
 *
 *   - which coordinates the return route is allowed to use;
 *   - whether the return leg is the exact reverse of the outbound leg;
 *   - the ordered return stops, as plain address strings;
 *   - cent-exact leg totals;
 *   - the stable `return_quote_failed` contract.
 *
 * Hard rule: nothing here may invent a price. When the return leg cannot be
 * priced, the caller must fail the quote instead of returning the outbound
 * amount as if it covered both legs.
 */

import { safeStr } from "./parsing_utils.js";

export const RETURN_QUOTE_FAILED = "return_quote_failed";

/// Internal failure phases. These stay in logs and in the caller's internal
/// bookkeeping; the storefront only ever sees RETURN_QUOTE_FAILED.
export const RETURN_QUOTE_PHASES = {
  GEOCODE: "return_geocode",
  ROUTE: "return_route",
  FIXED_PRICE: "return_fixed_price",
  PRICING: "return_pricing",
};

const RETURN_QUOTE_PHASE_VALUES = new Set(Object.values(RETURN_QUOTE_PHASES));

const MAX_RETURN_STOPS = 6;

/// Customer-facing message. No addresses, no provider text, no stack detail.
const RETURN_QUOTE_FAILED_MESSAGE =
  "De prijs van de terugrit kon niet worden berekend. Controleer de terugrit of probeer het later opnieuw.";

function normalizePhase(phase) {
  const value = safeStr(phase, 40);
  return RETURN_QUOTE_PHASE_VALUES.has(value) ? value : RETURN_QUOTE_PHASES.PRICING;
}

/// Address comparison used to decide whether the return leg is the exact
/// reverse of the outbound leg. Accent-, case- and punctuation-insensitive so
/// "Korenmarkt, Gent" and "korenmarkt gent" match, while a different street
/// never does.
export function normalizeAddressForCompare(value) {
  const raw = safeStr(value, 400);
  if (!raw) return "";
  let text = raw;
  if (typeof text.normalize === "function") {
    text = text.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  }
  return text
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}

export function addressesMatch(a, b) {
  const left = normalizeAddressForCompare(a);
  const right = normalizeAddressForCompare(b);
  return !!left && !!right && left === right;
}

/// True when return_from is the outbound destination and return_to is the
/// outbound origin. Only then may the outbound coordinates be swapped.
export function isReverseOfOutbound({
  outboundFrom,
  outboundTo,
  returnFrom,
  returnTo,
} = {}) {
  return (
    addressesMatch(returnFrom, outboundTo) && addressesMatch(returnTo, outboundFrom)
  );
}

// ---------------------------------------------------------------------------
// Fixed fare on the return leg — one canonical decision
// ---------------------------------------------------------------------------

/// Stable storefront code for a fixed-price route whose return leg cannot be
/// resolved to a fixed price. The calculator is never used to paper over this.
export const RETURN_FIXED_FARE_UNRESOLVED = "return_fixed_fare_unresolved";

const RETURN_FIXED_FARE_UNRESOLVED_MESSAGE =
  "De vaste prijs van de terugrit kon niet worden bepaald. Pas de terugrit aan of vraag een prijs op maat.";

/// Reasons the caller logs as `fallback=`.
export const RETURN_FIXED_FARE_REASONS = Object.freeze({
  notRequested: "not_requested",
  explicitReturnFixedFare: "explicit_return_fixed_fare",
  mainNotFixedFare: "main_not_fixed_fare",
  reusedMainFixedFareRule: "reused_main_fixed_fare_rule",
  directionNotReverse: "return_direction_not_reverse",
  airportNotSame: "return_airport_not_same",
  addressesNotReverse: "return_addresses_not_reverse",
});

const RETURN_PLACE_COORD_TOLERANCE_METERS = 250;

function placeTokens(value) {
  const key = normalizeAddressForCompare(value);
  return key ? key.split(" ") : [];
}

function postcodeTokens(tokens) {
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
  return (
    [...a].every((token) => b.has(token)) || [...b].every((token) => a.has(token))
  );
}

/**
 * Two free-text addresses that describe the same place written differently.
 *
 * A shared postcode or house number anchors the comparison; only then may one
 * side be a subset of the other, so "Koekamerstraat 48A, 9688 Louise-Marie"
 * matches "Koekamerstraat 48A, 9688". Without such an anchor the words must
 * match exactly, which is what keeps Brussels Airport away from Brussels South
 * Charleroi Airport.
 */
export function samePlaceByText(left, right) {
  const leftTokens = placeTokens(left);
  const rightTokens = placeTokens(right);
  if (!leftTokens.length || !rightTokens.length) return false;
  if (sameTokenSet(leftTokens, rightTokens)) return true;

  const leftPostcodes = postcodeTokens(leftTokens);
  const rightPostcodes = postcodeTokens(rightTokens);
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

  const anchored =
    (leftPostcodes.length > 0 && rightPostcodes.length > 0) ||
    (leftHouse.length > 0 && rightHouse.length > 0);
  const leftWords = wordTokens(leftTokens);
  const rightWords = wordTokens(rightTokens);
  return anchored
    ? oneSideContainsTheOther(leftWords, rightWords)
    : sameTokenSet(leftWords, rightWords);
}

export function samePlaceByCoords(
  left,
  right,
  toleranceMeters = RETURN_PLACE_COORD_TOLERANCE_METERS,
) {
  const a = coordinatePair(left?.lat, left?.lng);
  const b = coordinatePair(right?.lat, right?.lng);
  if (!a || !b) return false;
  const meanLat = ((a.lat + b.lat) / 2) * (Math.PI / 180);
  const dLat = (b.lat - a.lat) * 111_320;
  const dLng = (b.lng - a.lng) * 111_320 * Math.cos(meanLat);
  return Math.sqrt(dLat * dLat + dLng * dLng) <= toleranceMeters;
}

/**
 * The same airport on both legs. An IATA code decides when both legs carry
 * one; otherwise the airport texts must match exactly. Never a subset, because
 * "Brussels Airport" is a subset of "Brussels South Charleroi Airport".
 */
export function sameAirportIdentity({
  outboundText,
  returnText,
  outboundIata,
  returnIata,
} = {}) {
  const left = safeStr(outboundIata, 8).toUpperCase();
  const right = safeStr(returnIata, 8).toUpperCase();
  if (left && right) return left === right;
  return sameTokenSet(placeTokens(outboundText), placeTokens(returnText));
}

function normalizeDirectionToken(value) {
  const token = normalizeAddressForCompare(value).replace(/ /g, "_");
  return token === "to_airport" || token === "from_airport" ? token : "";
}

/**
 * Which side of a leg is the airport. On a to_airport outbound the airport is
 * the destination, and on its return leg the airport is the origin.
 */
function legSides({ outboundDirection, outboundFrom, outboundTo, returnFrom, returnTo }) {
  const toAirport = normalizeDirectionToken(outboundDirection) !== "from_airport";
  return toAirport
    ? {
        outboundAirport: outboundTo,
        returnAirport: returnFrom,
        outboundCustomer: outboundFrom,
        returnCustomer: returnTo,
      }
    : {
        outboundAirport: outboundFrom,
        returnAirport: returnTo,
        outboundCustomer: outboundTo,
        returnCustomer: returnFrom,
      };
}

/**
 * The one decision that says whether the return leg inherits the outbound
 * fixed fare. Both `/quote` and `/book` call this, so an offer and its booking
 * can never price the return leg differently.
 */
export function resolveReturnFixedFareDecision({
  returnRequested = true,
  outboundFixedFareApplied = false,
  explicitReturnMatched = false,
  outboundDirection = "",
  returnDirection = "",
  outboundFrom = "",
  outboundTo = "",
  returnFrom = "",
  returnTo = "",
  outboundAirportIata = "",
  returnAirportIata = "",
  outboundCustomerCoords = null,
  returnCustomerCoords = null,
} = {}) {
  const deny = (reason) => ({ useMainFixedFare: false, reason });
  if (!returnRequested) return deny(RETURN_FIXED_FARE_REASONS.notRequested);
  if (explicitReturnMatched) {
    return deny(RETURN_FIXED_FARE_REASONS.explicitReturnFixedFare);
  }
  if (!outboundFixedFareApplied) {
    return deny(RETURN_FIXED_FARE_REASONS.mainNotFixedFare);
  }

  const expected =
    normalizeDirectionToken(outboundDirection) === "from_airport"
      ? "to_airport"
      : "from_airport";
  const declared = normalizeDirectionToken(returnDirection);
  if (declared && declared !== expected) {
    return deny(RETURN_FIXED_FARE_REASONS.directionNotReverse);
  }

  const sides = legSides({
    outboundDirection,
    outboundFrom,
    outboundTo,
    returnFrom,
    returnTo,
  });
  const airportOk = sameAirportIdentity({
    outboundText: sides.outboundAirport,
    returnText: sides.returnAirport,
    outboundIata: outboundAirportIata,
    returnIata: returnAirportIata,
  });
  if (!airportOk) return deny(RETURN_FIXED_FARE_REASONS.airportNotSame);

  const customerOk =
    samePlaceByCoords(outboundCustomerCoords, returnCustomerCoords) ||
    samePlaceByText(sides.outboundCustomer, sides.returnCustomer);
  if (!customerOk) return deny(RETURN_FIXED_FARE_REASONS.addressesNotReverse);

  return {
    useMainFixedFare: true,
    reason: RETURN_FIXED_FARE_REASONS.reusedMainFixedFareRule,
  };
}

/**
 * How the return leg of this trip may be priced.
 *
 * A fixed-price outbound forces a fixed-price return. The route calculator is
 * only the configured price when the outbound itself is route priced, meaning
 * no fixed-price rule covers this route at all. It is never a rescue for a
 * fixed-price match that failed.
 */
export function returnLegPricingMode({
  outboundFixedFareApplied = false,
  returnFixedFareResolved = false,
} = {}) {
  if (!outboundFixedFareApplied) return "route";
  return returnFixedFareResolved ? "fixed" : "unresolved";
}

/**
 * The 422 answer for a fixed-price route whose return leg stays unresolved.
 * Carries no amounts, so no caller can show the outbound price as a total.
 */
export function returnFixedFareUnresolvedFailure({ reason, status = 422 } = {}) {
  const safeReason = safeStr(reason, 64) || "unknown";
  return {
    status,
    phase: RETURN_QUOTE_PHASES.FIXED_PRICE,
    reason: safeReason,
    logLine: `[RETURN_QUOTE][FAILED] phase=${RETURN_QUOTE_PHASES.FIXED_PRICE} reason=${safeReason} code=${RETURN_FIXED_FARE_UNRESOLVED}`,
    out: {
      ok: false,
      error: RETURN_FIXED_FARE_UNRESOLVED,
      error_code: RETURN_FIXED_FARE_UNRESOLVED,
      message: RETURN_FIXED_FARE_UNRESOLVED_MESSAGE,
      price_incl_vat: null,
      price_incl_vat_main: null,
      price_incl_vat_return: null,
      total_price_incl_vat: null,
      pricing_source_return: null,
      return: null,
    },
  };
}

function finiteCoordinate(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return n;
}

function coordinatePair(lat, lng) {
  const latNum = finiteCoordinate(lat);
  const lngNum = finiteCoordinate(lng);
  if (latNum === null || lngNum === null) return null;
  if (Math.abs(latNum) > 90 || Math.abs(lngNum) > 180) return null;
  // Null island is never a real pickup or drop-off.
  if (latNum === 0 && lngNum === 0) return null;
  return { lat: latNum, lng: lngNum };
}

/// Explicit return coordinates as the client may send them.
export function explicitReturnPoints(body) {
  const src = body && typeof body === "object" ? body : {};
  const from = coordinatePair(
    src.return_from_lat ?? src.returnFromLat ?? src.return_pickup_lat ?? src.returnPickupLat,
    src.return_from_lng ??
      src.returnFromLng ??
      src.return_from_lon ??
      src.returnFromLon ??
      src.return_pickup_lng ??
      src.returnPickupLng,
  );
  const to = coordinatePair(
    src.return_to_lat ?? src.returnToLat ?? src.return_destination_lat ?? src.returnDestinationLat,
    src.return_to_lng ??
      src.returnToLng ??
      src.return_to_lon ??
      src.returnToLon ??
      src.return_destination_lng ??
      src.returnDestinationLng,
  );
  return { from, to };
}

/**
 * Decides which coordinates the return route may use.
 *
 * Order:
 *   1. valid explicit return coordinates from the request;
 *   2. the swapped outbound coordinates, but only when the return leg is the
 *      exact reverse of the outbound leg (normalised address compare);
 *   3. nothing, so the caller geocodes the return addresses separately.
 *
 * A partially usable pair is never mixed with a swapped one: each endpoint is
 * resolved on its own, and the strategy reports what actually happened.
 */
export function resolveReturnRoutePoints({
  body,
  outboundFrom,
  outboundTo,
  returnFrom,
  returnTo,
  outboundFromPoint,
  outboundToPoint,
} = {}) {
  const explicit = explicitReturnPoints(body);
  const reverse = isReverseOfOutbound({
    outboundFrom,
    outboundTo,
    returnFrom,
    returnTo,
  });
  const swappedFrom = reverse ? coordinatePair(outboundToPoint?.lat, outboundToPoint?.lng) : null;
  const swappedTo = reverse ? coordinatePair(outboundFromPoint?.lat, outboundFromPoint?.lng) : null;

  const fromPoint = explicit.from || swappedFrom || null;
  const toPoint = explicit.to || swappedTo || null;

  const fromSource = explicit.from ? "explicit" : swappedFrom ? "reverse_outbound" : "geocode";
  const toSource = explicit.to ? "explicit" : swappedTo ? "reverse_outbound" : "geocode";

  let strategy = "geocode";
  if (fromSource === toSource) strategy = fromSource;
  else if (fromSource !== "geocode" && toSource !== "geocode") strategy = "mixed";
  else strategy = "partial_geocode";

  return {
    fromPoint,
    toPoint,
    fromSource,
    toSource,
    strategy,
    reverseOfOutbound: reverse,
    needsGeocode: fromSource === "geocode" || toSource === "geocode",
  };
}

/// Return stops belong to the return leg only, in the order the customer set
/// them, as plain strings. Object shapes ({ address, lat, lng }) are accepted
/// because the website sends those, and empty entries are dropped so an empty
/// field can never turn into an unroutable "[object Object]" waypoint.
export function sanitizeReturnStops(body) {
  const src = body && typeof body === "object" ? body : {};
  const raw = Array.isArray(src.return_stops)
    ? src.return_stops
    : Array.isArray(src.returnStops)
      ? src.returnStops
      : [];
  const out = [];
  for (const entry of raw) {
    let text = "";
    if (entry && typeof entry === "object") {
      text = safeStr(
        entry.address ?? entry.text ?? entry.label ?? entry.name ?? entry.place ?? "",
        320,
      );
    } else {
      text = safeStr(entry, 320);
    }
    if (!text) continue;
    out.push(text);
    if (out.length >= MAX_RETURN_STOPS) break;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Money: cent-exact, never floating point sums
// ---------------------------------------------------------------------------

/// Parses a server amount into whole cents. Returns null for anything that is
/// not a usable number, so a missing leg can never read as 0.
export function toCents(value) {
  if (value === null || value === undefined || value === "") return null;
  const n = typeof value === "number" ? value : Number(String(value).replace(",", "."));
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100);
}

export function centsToAmount(cents) {
  if (cents === null || cents === undefined || !Number.isFinite(Number(cents))) return null;
  return Math.round(Number(cents)) / 100;
}

/// main + return, in cents, with no floating point drift. Returns null when a
/// requested leg amount is missing, because a partial total is a wrong total.
export function sumLegAmounts(mainAmount, returnAmount, { returnRequired = false } = {}) {
  const mainCents = toCents(mainAmount);
  if (mainCents === null) return null;
  if (returnAmount === null || returnAmount === undefined) {
    return returnRequired ? null : centsToAmount(mainCents);
  }
  const returnCents = toCents(returnAmount);
  if (returnCents === null) return null;
  return centsToAmount(mainCents + returnCents);
}

export function isUsableAmount(value) {
  const cents = toCents(value);
  return cents !== null && cents >= 0;
}

// ---------------------------------------------------------------------------
// Return moment
// ---------------------------------------------------------------------------

/// A scheduled return is only requested when the client asked for a return AND
/// supplied both a return date and a return time. A waiting round trip has no
/// separate schedule and must keep its existing single-leg pricing.
export function returnScheduleRequested(body) {
  const src = body && typeof body === "object" ? body : {};
  const enabled =
    src.return_enabled === true ||
    src.returnEnabled === true ||
    src.return === true ||
    safeStr(src.return_enabled, 8).toLowerCase() === "true" ||
    safeStr(src.return_enabled, 8) === "1";
  const date = safeStr(src.return_date ?? src.returnDate, 24);
  const time = safeStr(src.return_time ?? src.returnTime, 16);
  return !!(enabled && date && time);
}

/// The return leg must start after the outbound leg. Both inputs are compared
/// as milliseconds; unparsable input is not treated as a violation here because
/// the route/pricing phases already refuse unusable moments.
export function returnMomentAfterOutbound(outboundIso, returnIso) {
  const outboundMs = Date.parse(safeStr(outboundIso, 64));
  const returnMs = Date.parse(safeStr(returnIso, 64));
  if (!Number.isFinite(outboundMs) || !Number.isFinite(returnMs)) return true;
  return returnMs > outboundMs;
}

/// Wall-clock milliseconds for a booking date + time as the clients send them:
/// `YYYY-MM-DD` or `DD/MM/YYYY`, with `HH:mm`. Both legs are read the same way,
/// so comparing them stays timezone-neutral.
export function momentMsFromDateTime(date, time) {
  const day = safeStr(date, 24);
  const clock = safeStr(time, 16) || "12:00";
  const hhmm = clock.match(/^(\d{1,2}):(\d{2})/);
  if (!hhmm) return Number.NaN;
  let year;
  let month;
  let dayOfMonth;
  const iso = day.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  const eu = day.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (iso) {
    year = Number(iso[1]);
    month = Number(iso[2]);
    dayOfMonth = Number(iso[3]);
  } else if (eu) {
    dayOfMonth = Number(eu[1]);
    month = Number(eu[2]);
    year = Number(eu[3]);
  } else {
    return Number.NaN;
  }
  return Date.UTC(year, month - 1, dayOfMonth, Number(hhmm[1]), Number(hhmm[2]), 0, 0);
}

/// Same rule as `returnMomentAfterOutbound`, on the raw date/time parts.
export function returnAfterOutboundParts({
  outboundDate,
  outboundTime,
  returnDate,
  returnTime,
} = {}) {
  const outboundMs = momentMsFromDateTime(outboundDate, outboundTime);
  const returnMs = momentMsFromDateTime(returnDate, returnTime);
  if (!Number.isFinite(outboundMs) || !Number.isFinite(returnMs)) return true;
  return returnMs > outboundMs;
}

// ---------------------------------------------------------------------------
// Failure contract
// ---------------------------------------------------------------------------

/// Tagged error so the quote handler can keep one try/catch per phase without
/// losing which phase failed.
export function returnQuoteError(phase, reason) {
  const err = new Error(RETURN_QUOTE_FAILED);
  err.returnQuotePhase = normalizePhase(phase);
  err.returnQuoteReason = safeStr(reason, 64) || "unknown";
  return err;
}

export function returnQuotePhaseOf(err, fallbackPhase) {
  if (err && err.returnQuotePhase) return normalizePhase(err.returnQuotePhase);
  return normalizePhase(fallbackPhase);
}

export function returnQuoteReasonOf(err, fallbackReason) {
  if (err && err.returnQuoteReason) return safeStr(err.returnQuoteReason, 64);
  return safeStr(fallbackReason, 64) || "unknown";
}

/**
 * The single failure answer for a return leg that cannot be priced.
 * `out` is what the storefront receives: a stable error code and a plain
 * message, with no amounts at all so no caller can mistake the outbound price
 * for a round-trip total. `phase` and `reason` stay internal for logging.
 */
export function returnQuoteFailure({ phase, reason, status = 422 } = {}) {
  const safePhase = normalizePhase(phase);
  const safeReason = safeStr(reason, 64) || "unknown";
  return {
    status,
    phase: safePhase,
    reason: safeReason,
    logLine: `[RETURN_QUOTE][FAILED] phase=${safePhase} reason=${safeReason}`,
    out: {
      ok: false,
      error: RETURN_QUOTE_FAILED,
      error_code: RETURN_QUOTE_FAILED,
      message: RETURN_QUOTE_FAILED_MESSAGE,
      price_incl_vat: null,
      price_incl_vat_main: null,
      price_incl_vat_return: null,
      total_price_incl_vat: null,
      pricing_source_return: null,
      return: null,
    },
  };
}
