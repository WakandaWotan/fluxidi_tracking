// Shared coordinate-first Mapbox Directions retries for /quote and travel.
// Sequence: direct → 50 m → 200 m → 500 m. Only NoSegment retries.
// A usable route must have a positive finite distance AND duration.

export const NO_SEGMENT_RETRY_STEPS = Object.freeze([
  { label: "direct", radiuses: "", snap_penalty_seconds: 0 },
  { label: "50", radiuses: "50;50", snap_penalty_seconds: 0 },
  { label: "200", radiuses: "200;200", snap_penalty_seconds: 60 },
  { label: "500", radiuses: "500;500", snap_penalty_seconds: 120 },
]);

export function isNoSegmentError(errorCode, errorMessage) {
  const code = String(errorCode || "").trim().toLowerCase();
  const msg = String(errorMessage || "").trim().toLowerCase();
  return code === "nosegment" || msg.includes("matching segment");
}

export function isUsableMapboxRoute(route) {
  const distance = Number(route?.distance);
  const duration = Number(route?.duration);
  return Number.isFinite(distance) && distance > 0 && Number.isFinite(duration) && duration > 0;
}

export function routeFailureFromError(error) {
  const code = String(error?.route_error_code || error?.code || "route_error").trim() || "route_error";
  const message =
    String(error?.route_error_message || error?.message || "").trim() ||
    "De route kon niet worden berekend.";
  return {
    code,
    message: message.includes("Directions failed")
      ? "Er is geen bruikbare wegroute gevonden tussen deze adressen."
      : message,
  };
}

export async function directionsWithNoSegmentRetry({
  coords,
  token,
  directions,
}) {
  if (typeof directions !== "function") {
    throw new Error("directions_fn_required");
  }
  const attempts = NO_SEGMENT_RETRY_STEPS;
  const summary = [];
  let lastError = null;
  for (let idx = 0; idx < attempts.length; idx += 1) {
    const step = attempts[idx];
    try {
      const route = await directions(
        coords,
        token,
        step.radiuses ? { radiuses: step.radiuses } : {},
      );
      if (!isUsableMapboxRoute(route)) {
        const err = new Error("Directions failed");
        err.route_error_code = "route_not_usable";
        err.route_error_message = "Route heeft geen positieve afstand of duur.";
        throw err;
      }
      summary.push(`${step.label}:ok`);
      if (route && typeof route === "object") {
        route._retry = {
          route_retry_used: idx > 0,
          route_retry_success: idx > 0,
          route_retry_reason: idx > 0 ? "nosegment_progressive_retry" : null,
          route_retry_radius_used: step.radiuses || null,
          route_retry_attempts_count: idx + 1,
          route_retry_attempts_summary: summary.join(","),
        };
      }
      return route;
    } catch (error) {
      lastError = error;
      const code = String(error?.route_error_code || error?.code || "route_error");
      summary.push(`${step.label}:${code}`);
      const canRetry =
        idx < attempts.length - 1 &&
        isNoSegmentError(code, error?.route_error_message || error?.message);
      if (canRetry) continue;
      if (lastError && typeof lastError === "object") {
        lastError.route_retry_used = idx > 0;
        lastError.route_retry_success = false;
        lastError.route_retry_reason = idx > 0 ? "nosegment_progressive_retry" : null;
        lastError.route_retry_attempts_count = idx + 1;
        lastError.route_retry_attempts_summary = summary.join(",");
      }
      throw lastError;
    }
  }
  throw lastError || new Error("Directions failed");
}
