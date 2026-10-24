import {ownedReleaseFetchV1 as fetch} from './owned_release_fetch_v1.mjs';
// Driving ETA for dispatch advice. Uses the existing Mapbox Directions API.
// No haversine substitute. A missing token or a failed call throws so the
// planner falls back to schedule_fallback.
import { measureRouteCall } from './route_observability.mjs';
import {reserveStagingTrialForEnvV1} from './staging_trial_budget_v1.mjs';

export function dispatchDirectionsUrl(token, from, to, departAt, includeGeometry = false) {
  const path = `${from.longitude},${from.latitude};${to.longitude},${to.latitude}`;
  const depart = departAtIso(departAt);
  const departQuery = depart ? `&depart_at=${encodeURIComponent(depart)}` : "";
  return (
    `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${path}` +
    `?overview=${includeGeometry ? "simplified&geometries=geojson" : "false"}${departQuery}&access_token=${encodeURIComponent(token)}`
  );
}

export async function mapboxDispatchRouteEta(env, args = {}) {
  if(env?.RELIABLE_CHOICE_ENABLED==='1')throw new Error('commercial_dispatch_routing_disabled');
  // Validate before measuring: rejected input caused no provider request.
  const { origin, destination, depart_at, includeGeometry = false, observability } = args;
  const token = String(env?.MAPBOX_TOKEN || "").trim();
  if (!token) throw new Error("mapbox_unconfigured");
  const from = point(origin);
  const to = point(destination);
  if (!from || !to) throw new Error("mapbox_coordinates");
  const url = dispatchDirectionsUrl(token, from, to, depart_at, includeGeometry);
  return measureRouteCall(env, { ...observability, profile: 'mapbox/driving-traffic' }, async markStatus => {
  await reserveStagingTrialForEnvV1(env,'mapbox_directions');
  const response = await fetch(url);
  markStatus(response.status);
  if (!response.ok) throw new Error("mapbox_http");
  const body = await response.json();
  const route = body?.routes?.[0];
  const duration = Number(route?.duration);
  const distance = Number(route?.distance);
  const typical = Number(route?.duration_typical);
  if (!Number.isFinite(duration)) throw new Error("mapbox_empty");
  return {
    ...(includeGeometry ? { route: publicRouteGeometry(route?.geometry) } : {}),
    duration_seconds: duration,
    duration_typical_seconds: Number.isFinite(typical) ? typical : null,
    distance_meters: Number.isFinite(distance) ? distance : null,
  };
  });
}

function departAtIso(value) {
  if (value == null || value === "") return "";
  const ms = Date.parse(String(value));
  if (!Number.isFinite(ms)) return "";
  return new Date(ms).toISOString();
}

function point(value) {
  const latitude = Number(value?.latitude ?? value?.lat);
  const longitude = Number(value?.longitude ?? value?.lon ?? value?.lng);
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
  return { latitude, longitude };
}

// Public route from this same Directions result; never GPS history or a guess.
export function publicRouteGeometry(geometry) {
  if (geometry?.type !== "LineString" || !Array.isArray(geometry.coordinates) ||
      geometry.coordinates.length < 2 || geometry.coordinates.length > 5000) return null;
  const points = geometry.coordinates.map(c => Array.isArray(c) && c.length >= 2 &&
    typeof c[0] === "number" && typeof c[1] === "number" ? point({ longitude:c[0], latitude:c[1] }) : null);
  return points.every(Boolean) ? { coordinates: points } : null;
}
