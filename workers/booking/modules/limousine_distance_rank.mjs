// P2D4C1G — limousine discovery ranks by customer distance; it never excludes.
//
// Location is a sort origin only. Transaction gates, taxi radius and postcode
// coverage must not hide an otherwise eligible limousine provider.
// Source coordinates used for ranking are never copied onto public payloads.

import { normalizeLimousineToken } from "./limousine_provider_eligibility.mjs";

const EARTH_KM = 6371;

// Compact Belgian centroids for ranking. Unknown codes fall back to prefix
// zones so a far company still ranks instead of disappearing.
const POSTCODE_CENTROIDS = Object.freeze({
  1000: [50.8467, 4.3525],
  2000: [51.2194, 4.4025],
  3000: [50.8798, 4.7005],
  8000: [51.2093, 3.2247],
  9000: [51.0543, 3.7174],
  9050: [51.035, 3.76],
  9600: [50.85, 3.6],
  9680: [50.79, 3.59],
  9688: [50.796, 3.621],
  9700: [50.843, 3.604],
});

const PREFIX_ZONES = Object.freeze({
  10: [50.85, 4.35],
  20: [51.22, 4.4],
  30: [50.88, 4.7],
  80: [51.21, 3.22],
  90: [51.05, 3.72],
  96: [50.82, 3.61],
  97: [50.84, 3.6],
});

function asFinite(raw) {
  if (raw == null || raw === "") return null;
  const n = Number(raw);
  return Number.isFinite(n) ? n : null;
}

function normalizePostcode(raw) {
  const digits = String(raw ?? "").replace(/\D/g, "");
  return digits.length >= 4 ? digits.slice(0, 4) : "";
}

export function limousinePostcodeCentroid(raw) {
  const code = normalizePostcode(raw);
  if (!code) return null;
  const exact = POSTCODE_CENTROIDS[code];
  if (exact) return { lat: exact[0], lng: exact[1] };
  const zone = PREFIX_ZONES[code.slice(0, 2)];
  if (zone) return { lat: zone[0], lng: zone[1] };
  return null;
}

export function limousineHaversineKm(lat1, lng1, lat2, lng2) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return EARTH_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

export function resolveLimousineSearchOrigin({ postcode = "", lat = null, lng = null } = {}) {
  const originLat = asFinite(lat);
  const originLng = asFinite(lng);
  if (originLat != null && originLng != null) {
    return { lat: originLat, lng: originLng };
  }
  return limousinePostcodeCentroid(postcode);
}

export function resolveLimousineCompanyPoint({
  coverageLat = null,
  coverageLng = null,
  primaryPostcode = "",
  supportedPostcodes = [],
} = {}) {
  const lat = asFinite(coverageLat);
  const lng = asFinite(coverageLng);
  if (lat != null && lng != null) return { lat, lng };
  const fromPrimary = limousinePostcodeCentroid(primaryPostcode);
  if (fromPrimary) return fromPrimary;
  const codes = Array.isArray(supportedPostcodes) ? supportedPostcodes : [];
  for (const code of codes) {
    const point = limousinePostcodeCentroid(code);
    if (point) return point;
  }
  return null;
}

export function limousineNearbyDistanceKm({
  postcode = "",
  lat = null,
  lng = null,
  coverageLat = null,
  coverageLng = null,
  primaryPostcode = "",
  supportedPostcodes = [],
} = {}) {
  const origin = resolveLimousineSearchOrigin({ postcode, lat, lng });
  if (!origin) return null;
  const point = resolveLimousineCompanyPoint({
    coverageLat,
    coverageLng,
    primaryPostcode,
    supportedPostcodes,
  });
  if (!point) return null;
  return Number(limousineHaversineKm(origin.lat, origin.lng, point.lat, point.lng).toFixed(2));
}

export function compareLimousineNearbyRank(a, b) {
  const da = Number.isFinite(a?.distanceKm) ? a.distanceKm : Number.POSITIVE_INFINITY;
  const db = Number.isFinite(b?.distanceKm) ? b.distanceKm : Number.POSITIVE_INFINITY;
  if (da !== db) return da - db;
  const idA = String(a?.partnerId ?? a?.p?.partner_id ?? "");
  const idB = String(b?.partnerId ?? b?.p?.partner_id ?? "");
  if (idA !== idB) return idA < idB ? -1 : 1;
  return (Number(a?.idx) || 0) - (Number(b?.idx) || 0);
}

export function rankLimousineNearbyEntries(entries) {
  if (!Array.isArray(entries)) return [];
  return [...entries].sort(compareLimousineNearbyRank);
}

export function limousineNearbyIgnoresCoverageFilter(service) {
  return normalizeLimousineToken(service) === "limousine";
}

export function publicLimousineDistanceFields(distanceKm) {
  if (!Number.isFinite(distanceKm)) return {};
  return { distance_km: Number(distanceKm.toFixed(2)) };
}
