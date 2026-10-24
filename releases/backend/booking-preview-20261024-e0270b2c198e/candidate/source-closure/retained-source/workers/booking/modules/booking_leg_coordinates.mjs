import { trackingRoutePoint, trackingLegId } from "./customer_tracking_access.mjs";
import { safeStr } from "./parsing_utils.js";

// Customer tracking needs real coordinates: an address string can never become
// a destination pin, a route or an ETA. Only a finite in-range pair is stored.
function coordinate(value, limit) {
  if (value === null || value === undefined) return null;
  if (typeof value === "boolean") return null;
  const text = String(value).trim();
  if (!text) return null;
  const num = Number(text);
  if (!Number.isFinite(num) || Math.abs(num) > limit) return null;
  return num;
}

function pair(lat, lng) {
  const latitude = coordinate(lat, 90);
  const longitude = coordinate(lng, 180);
  if (latitude === null || longitude === null) return null;
  // A 0,0 pair is the classic "unset" sentinel, never a Belgian ride.
  if (latitude === 0 && longitude === 0) return null;
  return { lat: latitude, lng: longitude };
}

function firstAliasPair(source, latKeys, lngKeys) {
  if (!source || typeof source !== "object") return null;
  for (let i = 0; i < latKeys.length; i += 1) {
    const found = pair(source[latKeys[i]], source[lngKeys[i]]);
    if (found) return found;
  }
  return null;
}

const PICKUP_LAT_KEYS = ["pickup_lat", "pickupLat", "from_lat", "fromLat"];
const PICKUP_LNG_KEYS = ["pickup_lng", "pickupLng", "from_lng", "fromLng"];
const DROPOFF_LAT_KEYS = [
  "dropoff_lat",
  "dropoffLat",
  "to_lat",
  "toLat",
  "destination_lat",
  "destinationLat",
];
const DROPOFF_LNG_KEYS = [
  "dropoff_lng",
  "dropoffLng",
  "to_lng",
  "toLng",
  "destination_lng",
  "destinationLng",
];

function routePointPair(point) {
  if (!point || typeof point !== "object") return null;
  return (
    pair(point.lat, point.lng) ||
    pair(point.latitude, point.longitude) ||
    pair(point.lat, point.lon) ||
    (Array.isArray(point.coordinates)
      ? pair(point.coordinates[1], point.coordinates[0])
      : null)
  );
}

/**
 * Stored pickup/destination coordinates for a single persisted ride.
 *
 * Explicit client coordinates win, then the resolved Mapbox route, then an
 * already accepted quote or an earlier record. Every source is validated, so a
 * textual or out-of-range value is dropped instead of stored. Keys are omitted
 * entirely when nothing valid exists, which keeps the existing behaviour for a
 * booking that genuinely has no destination coordinates.
 */
export function resolveBookingTrackingCoordinateFields({
  payload = null,
  outboundRoute = null,
  fallbackSources = [],
} = {}) {
  const pickup =
    firstAliasPair(payload, PICKUP_LAT_KEYS, PICKUP_LNG_KEYS) ||
    routePointPair(outboundRoute?.resolved_from_point) ||
    fallbackSources.reduce(
      (found, source) =>
        found ||
        firstAliasPair(source, PICKUP_LAT_KEYS, PICKUP_LNG_KEYS) ||
        routePointPair(source?.pickup),
      null,
    );
  const destination =
    firstAliasPair(payload, DROPOFF_LAT_KEYS, DROPOFF_LNG_KEYS) ||
    routePointPair(outboundRoute?.resolved_to_point) ||
    fallbackSources.reduce(
      (found, source) =>
        found ||
        firstAliasPair(source, DROPOFF_LAT_KEYS, DROPOFF_LNG_KEYS) ||
        routePointPair(source?.destination),
      null,
    );
  return {
    ...(pickup ? { from_lat: pickup.lat, from_lng: pickup.lng } : {}),
    ...(destination ? { to_lat: destination.lat, to_lng: destination.lng } : {}),
  };
}

// Concrete route points belong to a leg, never to an inferred parent/sibling.
export function fillBookingLegTrackingCoordinates(legs, payload, outboundRoute, returnRoute, previousLegs = []) {
  if (!Array.isArray(legs) || legs.length < 2) return;
  const returnPayload = {};
  for (const [key, value] of Object.entries(payload || {})) {
    if (key.startsWith("return_")) returnPayload[key.slice(7)] = value;
    else if (/^return[A-Z]/.test(key)) {
      const name = key.slice(6);
      returnPayload[name[0].toLowerCase() + name.slice(1)] = value;
    }
  }
  for (const leg of legs) {
    const type = String(leg.leg_type || leg.legType || "").toLowerCase();
    if (type !== "outbound" && type !== "return") continue;
    const source = type === "return" ? returnPayload : payload;
    const route = type === "return" ? returnRoute : outboundRoute;
    const expectedFrom = type === "return" ? (payload?.return_from || payload?.returnFrom || payload?.to) : payload?.from;
    const expectedTo = type === "return" ? (payload?.return_to || payload?.returnTo || payload?.from) : payload?.to;
    if (!expectedFrom || !expectedTo || leg.from !== safeStr(expectedFrom, 320) || leg.to !== safeStr(expectedTo, 320)) continue;
    // Finalization may rebuild the same legs. Preserve already stored points
    // only for the exact leg and unchanged addresses, never by array position.
    const previous = previousLegs.find(old =>
      trackingLegId(old) === trackingLegId(leg) && trackingLegId(leg) &&
      old.from === leg.from && old.to === leg.to &&
      String(old.leg_type || old.legType || "").toLowerCase() === type);
    for (const side of ["pickup", "destination"]) {
      const resolved = side === "pickup" ? route?.resolved_from_point : route?.resolved_to_point;
      const point = trackingRoutePoint(leg, side) || trackingRoutePoint(previous, side) ||
        trackingRoutePoint(source, side) || trackingRoutePoint({ [side]: resolved }, side);
      if (point) leg[side] = point;
    }
  }
}

