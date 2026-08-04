// NAV-SIGNAL-P0A-WORKER-PARITY-1 / P0A1: pure helpers for Directions
// request/response signaling parity with the Flutter direct Mapbox path.
// No PII logging; counts only.

/** Fluxidi UI / Mapbox language allowlist (never country codes). */
export const NAVIGATION_LANGUAGE_ALLOWLIST = Object.freeze([
  "nl",
  "fr",
  "en",
  "es",
  "pt",
]);

/**
 * Normalize a candidate navigation language for Mapbox.
 * Accepts plain codes and locale forms like en-BE / fr_FR → base code.
 * Returns null when unsupported or malformed (never forwards arbitrary input).
 */
export function normalizeNavigationLanguage(raw) {
  if (raw == null) return null;
  const text = String(raw).trim().toLowerCase();
  if (!text) return null;
  const base = text.split(/[-_]/)[0] || "";
  if (!NAVIGATION_LANGUAGE_ALLOWLIST.includes(base)) return null;
  return base;
}

/**
 * Shared /route and /reroute language resolver.
 * A) valid body.language → B) countryProfile.maneuverLanguageHint → C) default.
 */
export function resolveMapboxDirectionsLanguage({
  bodyLanguage,
  countryLanguageHint,
  defaultLanguage = "en",
} = {}) {
  const fromBody = normalizeNavigationLanguage(bodyLanguage);
  if (fromBody) return fromBody;
  const fromCountry = normalizeNavigationLanguage(countryLanguageHint);
  if (fromCountry) return fromCountry;
  return normalizeNavigationLanguage(defaultLanguage) || "en";
}

/**
 * Stable cache-key material including effective navigation language.
 * Does not include tokens, geometry, or instruction text.
 */
export function buildRouteCacheKeyMaterial({
  kind,
  country,
  profile,
  originLat,
  originLng,
  destLat,
  destLng,
  avoidKey = "",
  language,
}) {
  return [
    kind,
    country,
    profile,
    originLat,
    originLng,
    destLat,
    destLng,
    avoidKey || "",
    language,
  ].join("|");
}

/**
 * Plans the effective Mapbox Directions query language + params for a
 * worker /route or /reroute request (shared builder; no network).
 */
export function planWorkerMapboxDirectionsRequest({
  kind,
  bodyLanguage,
  countryLanguageHint,
  accessToken = "test-token",
  avoidKey = "",
} = {}) {
  const language = resolveMapboxDirectionsLanguage({
    bodyLanguage,
    countryLanguageHint,
  });
  const params = buildMapboxDirectionsSearchParams({
    language,
    accessToken,
    avoidKey,
  });
  return {
    kind: kind === "reroute" ? "reroute" : "route",
    language,
    params,
  };
}

/** Query params aligned with lib/navigation/driver_navigation_directions_request.dart */
export function buildMapboxDirectionsSearchParams({
  language,
  accessToken,
  avoidKey = "",
  /** Optional Mapbox bearings string, e.g. "90.0,45;" (origin only). */
  bearings = "",
}) {
  const params = new URLSearchParams({
    geometries: "geojson",
    overview: "full",
    steps: "true",
    banner_instructions: "true",
    roundabout_exits: "true",
    alternatives: "false",
    language: language || "en",
    access_token: accessToken,
  });
  if (avoidKey) {
    params.set("exclude", avoidKey);
  }
  const bearingsText = typeof bearings === "string" ? bearings.trim() : "";
  if (bearingsText) {
    params.set("bearings", bearingsText);
  }
  return params;
}

/**
 * Lossless clone of Mapbox route.legs for client reshape.
 * Does not invent fields; returns [] when legs are absent.
 */
export function preserveRouteLegs(route) {
  const legs = Array.isArray(route?.legs) ? route.legs : [];
  if (legs.length === 0) return [];
  try {
    return JSON.parse(JSON.stringify(legs));
  } catch (_) {
    return [];
  }
}

/** Compact maneuver list kept for older Flutter clients. */
export function extractManeuvers(route) {
  const out = [];
  const legs = Array.isArray(route?.legs) ? route.legs : [];
  for (const leg of legs) {
    const steps = Array.isArray(leg?.steps) ? leg.steps : [];
    for (const step of steps) {
      const maneuver = step?.maneuver;
      if (!maneuver || typeof maneuver !== "object") continue;
      const location = Array.isArray(maneuver.location)
        ? {
            lng: Number(maneuver.location[0]),
            lat: Number(maneuver.location[1]),
          }
        : null;
      out.push({
        type: String(maneuver.type || "unknown").slice(0, 32),
        modifier: maneuver.modifier
          ? String(maneuver.modifier).slice(0, 32)
          : null,
        instruction:
          (maneuver.instruction && String(maneuver.instruction).slice(0, 256)) ||
          (step.name && String(step.name).slice(0, 256)) ||
          null,
        location,
        distance_m: Number(step.distance) || 0,
        duration_s: Number(step.duration) || 0,
      });
    }
  }
  return out;
}

/** Bounded non-PII signal counts for diagnostics. */
export function summarizeSignalCounts(legs) {
  let steps = 0;
  let banners = 0;
  let laneGroups = 0;
  let refs = 0;
  let destinations = 0;
  let roundaboutExits = 0;

  const list = Array.isArray(legs) ? legs : [];
  for (const leg of list) {
    const stepList = Array.isArray(leg?.steps) ? leg.steps : [];
    for (const step of stepList) {
      steps += 1;
      const bannersAny =
        step?.bannerInstructions || step?.banner_instructions;
      if (Array.isArray(bannersAny) && bannersAny.length > 0) {
        banners += bannersAny.length;
      }
      const intersections = Array.isArray(step?.intersections)
        ? step.intersections
        : [];
      let stepHasLanes = false;
      for (const intersection of intersections) {
        if (
          Array.isArray(intersection?.lanes) &&
          intersection.lanes.length > 0
        ) {
          stepHasLanes = true;
          break;
        }
      }
      if (stepHasLanes) laneGroups += 1;
      if (typeof step?.ref === "string" && step.ref.trim()) refs += 1;
      if (Array.isArray(step?.destinations) && step.destinations.length > 0) {
        destinations += 1;
      }
      const exit = step?.maneuver?.exit;
      const type = String(step?.maneuver?.type || "").toLowerCase();
      if (
        exit != null &&
        String(exit).trim() !== "" &&
        (type.includes("roundabout") || type.includes("rotary"))
      ) {
        roundaboutExits += 1;
      }
    }
  }

  return {
    steps,
    banners,
    laneGroups,
    refs,
    destinations,
    roundaboutExits,
  };
}

export function formatNavSignalResponseLog(summary, source = "worker") {
  const s = summary || {};
  return (
    `[NAV_SIGNAL_RESPONSE] source=${source} ` +
    `steps=${s.steps ?? 0} ` +
    `banners=${s.banners ?? 0} ` +
    `laneGroups=${s.laneGroups ?? 0} ` +
    `refs=${s.refs ?? 0} ` +
    `destinations=${s.destinations ?? 0} ` +
    `roundaboutExits=${s.roundaboutExits ?? 0}`
  );
}
