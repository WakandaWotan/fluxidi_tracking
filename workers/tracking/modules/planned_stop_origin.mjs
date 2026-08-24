/* Planned-stop origin GPS resolver.
 *
 * Limousine booking details often lack pickup_lat/from_lat. When the driver
 * already started the ride, session/trip/ride_start already hold the exact
 * departure coordinates. Reuse those; never invent or geocode.
 *
 * Run: node --test workers/tracking/modules/planned_stop_origin.test.mjs
 */

function _asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value
    : null;
}

function _finiteNumber(value) {
  if (value == null || value === "") return null;
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function _label(value) {
  if (value == null) return "";
  const text = String(value).trim();
  return text ? text.slice(0, 256) : "";
}

export function hasTrustedOriginCoords(origin) {
  const obj = _asObject(origin);
  if (!obj) return false;
  const lat = _finiteNumber(obj.lat ?? obj.latitude);
  const lon = _finiteNumber(obj.lon ?? obj.lng ?? obj.longitude);
  if (lat == null || lon == null) return false;
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return false;
  if (lat === 0 && lon === 0) return false;
  return true;
}

export function readTrustedOriginCoords(origin) {
  if (!hasTrustedOriginCoords(origin)) return null;
  const obj = _asObject(origin);
  return {
    lat: _finiteNumber(obj.lat ?? obj.latitude),
    lon: _finiteNumber(obj.lon ?? obj.lng ?? obj.longitude),
    label: _label(obj.label ?? obj.address ?? obj.text),
  };
}

export function resolvePlannedStopOrigin({
  payloadOrigin = null,
  existingTripOrigin = null,
  sessionOrigin = null,
  sessionPickup = null,
} = {}) {
  const payload = _asObject(payloadOrigin);
  const payloadCoords = readTrustedOriginCoords(payload);
  const reused =
    payloadCoords ||
    readTrustedOriginCoords(existingTripOrigin) ||
    readTrustedOriginCoords(sessionOrigin) ||
    readTrustedOriginCoords(sessionPickup);
  if (!reused) {
    return payload;
  }
  const label = _label(payload?.label ?? payload?.address ?? reused.label);
  const out = { lat: reused.lat, lon: reused.lon };
  if (label) out.label = label;
  return out;
}
