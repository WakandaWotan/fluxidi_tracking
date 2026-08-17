/**
 * RateHawk static-content provider strategy seam.
 *
 * single_hid_info is the authorized fallback.
 * batch_content_by_ids stays unavailable until RateHawk grants permission.
 * A batch request must not silently fall back to the single-hid endpoint.
 */

export const RATEHAWK_CONTENT_STRATEGIES = Object.freeze({
  SINGLE_HID_INFO: "single_hid_info",
  BATCH_CONTENT_BY_IDS: "batch_content_by_ids",
});

export const RATEHAWK_CONTENT_BATCH_PATH = "/api/content/v1/hotel_content_by_ids/";
export const RATEHAWK_CONTENT_SINGLE_HID_PATH = "/api/b2b/v3/hotel/info/";

function _lower(value) {
  return String(value ?? "").trim().toLowerCase();
}

export function resolveRatehawkContentStrategy(requested = RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO) {
  const value = _lower(requested);
  if (
    value === RATEHAWK_CONTENT_STRATEGIES.BATCH_CONTENT_BY_IDS ||
    value === "batch" ||
    value === "hotel_content_by_ids_batch"
  ) {
    return {
      ok: false,
      available: false,
      strategy: RATEHAWK_CONTENT_STRATEGIES.BATCH_CONTENT_BY_IDS,
      reason: "batch_content_by_ids_unavailable",
      fallback_used: false,
      path: RATEHAWK_CONTENT_BATCH_PATH,
    };
  }
  if (value && value !== RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO) {
    return {
      ok: false,
      available: false,
      strategy: value,
      reason: "content_strategy_unknown",
      fallback_used: false,
      path: null,
    };
  }
  return {
    ok: true,
    available: true,
    strategy: RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO,
    reason: null,
    fallback_used: false,
      path: RATEHAWK_CONTENT_SINGLE_HID_PATH,
  };
}

export function isRatehawkBatchContentStrategyEnabled() {
  return false;
}
