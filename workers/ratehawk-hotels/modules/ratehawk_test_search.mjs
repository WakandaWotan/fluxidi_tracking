/**
 * Hotels Worker test-only search activation.
 *
 * Issues rhctx1 only after a privacy-safe card is built. Never returns
 * book_hash, match_hash, credentials, settlement, or the raw payload.
 */

import {
  RATEHAWK_STAY_CARD_SOURCE,
  normalizeRatehawkRateOffer,
} from "./ratehawk_affiliate_contract.mjs";
import { buildExistingHotelCardSearchDto } from "./ratehawk_hotel_card_search.mjs";
import { annotateSearchResultMetadata } from "./ratehawk_market_search_limits.mjs";
import { RATEHAWK_PROVIDER, redactRatehawkSecrets } from "./ratehawk_provider.mjs";
import { fetchRatehawkTestSerp } from "./ratehawk_serp_transport.mjs";
import {
  RATEHAWK_TEST_HID,
  RATEHAWK_TEST_HOTEL_IDENTITY,
  RATEHAWK_TEST_STAY22_FALLBACK_URL,
  assertRatehawkTestProviderConfig,
  evaluateRatehawkTestSearchGate,
  hasForbiddenRatehawkTestClientControl,
  resolveRatehawkTestStay,
} from "./ratehawk_test_activation.mjs";
import { issueRatehawkViewStayContext } from "./ratehawk_view_stay_context.mjs";

function _safeSearch({
  reason,
  invoked = false,
  stay = null,
  count = 0,
  warnings = [],
  extras = {},
}) {
  return {
    ok: reason == null,
    invoked: invoked === true,
    source: RATEHAWK_STAY_CARD_SOURCE,
    provider: RATEHAWK_PROVIDER,
    count,
    stays: stay ? [{ ...stay }] : [],
    stay: stay ? { ...stay } : null,
    reason,
    warnings,
    view_stay_context: null,
    view_stay_context_expires_at: null,
    highlights: null,
    live_rate: null,
    stay22_fallback: Boolean(stay?.external_url),
    mobility_independent_of_ratehawk: true,
    commercial: {
      fluxidi_role: "affiliate",
      customer_pays_fluxidi: false,
      mollie_involved: false,
    },
    ...extras,
  };
}

function _safeHighlights(offer) {
  if (!offer || offer.ok !== true) return null;
  return {
    meal_plan: offer.meal_plan ?? null,
    breakfast_included: offer.breakfast_included === true,
    refundable: offer.refundable === true,
    free_cancellation_before: offer.free_cancellation_before ?? null,
    remaining_availability: offer.remaining_availability ?? null,
  };
}

function _safeLiveRate(offer) {
  if (!offer || offer.ok !== true) return null;
  return {
    customer_total: offer.customer_total ?? null,
    customer_total_label: offer.customer_total_label ?? null,
  };
}

export async function handleRatehawkTestSearchRequest({
  env,
  body = {},
  fetchImpl = null,
  now = Date.now(),
  timeoutMs = null,
} = {}) {
  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (hasForbiddenRatehawkTestClientControl(requestBody)) {
    return redactRatehawkSecrets(
      _safeSearch({ reason: "client_control_forbidden" }),
      env,
    );
  }

  const gate = evaluateRatehawkTestSearchGate(env);
  if (gate.ok !== true) {
    return redactRatehawkSecrets(_safeSearch({ reason: gate.reason }), env);
  }

  const configCheck = assertRatehawkTestProviderConfig(env);
  if (configCheck.ok !== true) {
    return redactRatehawkSecrets(
      _safeSearch({ reason: configCheck.reason }),
      env,
    );
  }

  const contextSecret = String(env?.RATEHAWK_VIEW_STAY_CONTEXT_SECRET || "").trim();
  if (!contextSecret) {
    return redactRatehawkSecrets(
      _safeSearch({ reason: "view_stay_context_secret_missing" }),
      env,
    );
  }

  const stay = resolveRatehawkTestStay(now);
  const transport = await fetchRatehawkTestSerp({
    env,
    fetchImpl,
    timeoutMs,
    now,
  });
  if (transport.invoked !== true) {
    return redactRatehawkSecrets(
      _safeSearch({
        reason: transport.reason || "test_search_disabled",
        invoked: false,
      }),
      env,
    );
  }
  if (transport.ok !== true) {
    return redactRatehawkSecrets(
      _safeSearch({
        reason: transport.reason || "provider_error",
        invoked: true,
      }),
      env,
    );
  }

  const hotel = Array.isArray(transport.hotels) ? transport.hotels[0] : null;
  if (!hotel || Number(hotel.hid) !== RATEHAWK_TEST_HID) {
    return redactRatehawkSecrets(
      _safeSearch({
        reason: "test_hotel_unavailable",
        invoked: true,
        extras: {
          freshness: annotateSearchResultMetadata({
            requestedHids: [RATEHAWK_TEST_HID],
            receivedHids: [],
            timedOut: transport.reason === "timeout",
          }),
        },
      }),
      env,
    );
  }

  const rawRate = Array.isArray(hotel.rates) ? hotel.rates[0] : null;
  let liveRate = null;
  if (rawRate) {
    liveRate = normalizeRatehawkRateOffer(rawRate);
    if (liveRate.hard_stop === true) {
      return redactRatehawkSecrets(
        _safeSearch({
          reason: liveRate.reason || "unmapped_critical_field",
          invoked: true,
        }),
        env,
      );
    }
  }

  const mapped = buildExistingHotelCardSearchDto({
    source: RATEHAWK_STAY_CARD_SOURCE,
    search_contract_enabled: true,
    ratehawkHotel: {
      ...RATEHAWK_TEST_HOTEL_IDENTITY,
      hid: RATEHAWK_TEST_HID,
      name: hotel.name || RATEHAWK_TEST_HOTEL_IDENTITY.name,
    },
    liveRate: rawRate,
    stay22FallbackUrl: RATEHAWK_TEST_STAY22_FALLBACK_URL,
    fluxidiStayId: `ratehawk:${RATEHAWK_TEST_HID}`,
    catalogHid: RATEHAWK_TEST_HID,
  });
  if (mapped.ok !== true || !mapped.stay) {
    return redactRatehawkSecrets(
      _safeSearch({
        reason: mapped.reason || "card_normalization_failed",
        invoked: true,
      }),
      env,
    );
  }

  const issued = await issueRatehawkViewStayContext(contextSecret, stay, { now });
  if (issued.ok !== true) {
    return redactRatehawkSecrets(
      _safeSearch({
        reason: issued.reason || "view_stay_context_secret_missing",
        invoked: true,
      }),
      env,
    );
  }

  return redactRatehawkSecrets(
    {
      ..._safeSearch({
        reason: null,
        invoked: true,
        stay: mapped.stay,
        count: 1,
      }),
      view_stay_context: issued.token,
      view_stay_context_expires_at: issued.expires_at,
      highlights: _safeHighlights(liveRate),
      live_rate: _safeLiveRate(liveRate),
      freshness: {
        ...annotateSearchResultMetadata({
          requestedHids: [RATEHAWK_TEST_HID],
          receivedHids: [hotel],
        }),
        retrieved_at: Number(now),
      },
      stay_context: stay,
    },
    env,
  );
}
