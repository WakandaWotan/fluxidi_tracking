/**
 * Production-shaped public RateHawk Search on the Hotels Worker.
 *
 * Fail-closed by default. Never calls RateHawk. Never uses the test
 * Worker surface. Public Booking routes proxy here through RATEHAWK_HOTELS
 * only. Admin /internal/test-search stays separate.
 */

import { envFlag } from "./parsing_utils.js";
import {
  RATEHAWK_DEFAULT_SEARCH_LIMITS,
  RATEHAWK_SEARCH_TRIGGERS,
  isLiveSearchCriteriaComplete,
  shouldIssueRatehawkSearch,
} from "./ratehawk_market_search_limits.mjs";
import { buildExistingHotelSearchPayload } from "./ratehawk_hotel_card_search.mjs";
import {
  isRatehawkInvocationAllowed,
  RATEHAWK_PROVIDER,
} from "./ratehawk_provider.mjs";
import { RATEHAWK_STAY_CARD_SOURCE } from "./ratehawk_affiliate_contract.mjs";
import { isRatehawkIsolatedTestWorker } from "./ratehawk_test_activation.mjs";

export const RATEHAWK_SEARCH_GATE = "RATEHAWK_SEARCH_ENABLED";
export const RATEHAWK_HOTELS_SEARCH_PATH = "/internal/search";

export function isRatehawkSearchEnabled(env) {
  return envFlag(env?.[RATEHAWK_SEARCH_GATE]);
}

export function isRatehawkSearchInvocationAllowed(env) {
  return isRatehawkInvocationAllowed(env) && isRatehawkSearchEnabled(env);
}

function _guard({ reason, warnings = [] } = {}) {
  const nextWarnings = Array.isArray(warnings) ? [...warnings] : [];
  if (!nextWarnings.includes("ratehawk_invocation_blocked")) {
    nextWarnings.push("ratehawk_invocation_blocked");
  }
  const payload = buildExistingHotelSearchPayload({
    source: RATEHAWK_STAY_CARD_SOURCE,
    search_contract_enabled: false,
  });
  return {
    ...payload,
    invoked: false,
    reason: reason || "ratehawk_search_disabled",
    warnings: [...new Set([...payload.warnings, ...nextWarnings])],
    ratehawk: {
      invocation_allowed: false,
      connected: false,
      status: "fail_closed",
      search_enabled: false,
    },
    limits: {
      initial_hotel_limit: RATEHAWK_DEFAULT_SEARCH_LIMITS.initial_hotel_limit,
      load_more_increment: RATEHAWK_DEFAULT_SEARCH_LIMITS.load_more_increment,
      absolute_maximum: RATEHAWK_DEFAULT_SEARCH_LIMITS.absolute_maximum,
    },
    stay22_fallback_retained: true,
    mobility_independent_of_ratehawk: true,
    provider: RATEHAWK_PROVIDER,
  };
}

export function handleRatehawkPublicSearchRequest({
  env = {},
  body = {},
} = {}) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return _guard({ reason: "production_path_forbidden_on_test_worker" });
  }

  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  const trigger = String(requestBody.trigger || RATEHAWK_SEARCH_TRIGGERS.LIVE_SEARCH);
  const criteria = isLiveSearchCriteriaComplete({
    destination: {
      country: requestBody.country,
      city: requestBody.city,
      region_id: requestBody.region_id,
    },
    checkin: requestBody.checkin,
    checkout: requestBody.checkout,
    guests: Array.isArray(requestBody.guests) ? requestBody.guests : [],
  });
  const decision = shouldIssueRatehawkSearch({
    trigger,
    criteria,
    market: { ok: true },
  });

  if (decision.issue !== true) {
    return _guard({ reason: decision.reason });
  }

  if (!isRatehawkSearchInvocationAllowed(env)) {
    return _guard({ reason: "ratehawk_search_disabled" });
  }

  return _guard({
    reason: "ratehawk_search_not_implemented",
    warnings: ["ratehawk_search_not_implemented"],
  });
}
