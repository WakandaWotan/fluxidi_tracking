/**
 * Production-shaped public RateHawk Search on the Hotels Worker.
 *
 * Fail-closed by default. Public Booking routes proxy here through
 * RATEHAWK_HOTELS only. Admin /internal/test-search stays separate.
 * Live transport requires RATEHAWK_ENABLED and RATEHAWK_SEARCH_ENABLED,
 * plus config, credentials, quota, market mapping and the production
 * view-stay context secret. Missing any of those yields zero provider
 * calls.
 */

import { envFlag } from "./parsing_utils.js";
import {
  RATEHAWK_DEFAULT_SEARCH_LIMITS,
  RATEHAWK_SEARCH_TRIGGERS,
  annotateSearchResultMetadata,
  assertPublicSearchStayDates,
  canonicalizePublicSearchCurrency,
  canonicalizePublicSearchGuests,
  canonicalizePublicSearchLanguage,
  canonicalizePublicSearchResidency,
  dedupeHotelsByHid,
  hasForbiddenPublicSearchClientControl,
  isPublicLiveSearchCriteriaComplete,
  parseConfiguredSearchMarkets,
  resolvePublicSearchMarket,
  resolvePublicSearchResultLimit,
  shouldIssueRatehawkSearch,
} from "./ratehawk_market_search_limits.mjs";
import { buildExistingHotelCardSearchDto } from "./ratehawk_hotel_card_search.mjs";
import {
  RATEHAWK_STAY_CARD_SOURCE,
  normalizeRatehawkRateOffer,
} from "./ratehawk_affiliate_contract.mjs";
import {
  isRatehawkInvocationAllowed,
  RATEHAWK_PROVIDER,
  redactRatehawkSecrets,
  resolveRatehawkConfig,
} from "./ratehawk_provider.mjs";
import { isRatehawkIsolatedTestWorker } from "./ratehawk_test_activation.mjs";
import { issueRatehawkViewStayContext } from "./ratehawk_view_stay_context.mjs";
import { fetchRatehawkPublicSerp } from "./ratehawk_public_serp_transport.mjs";

export const RATEHAWK_SEARCH_GATE = "RATEHAWK_SEARCH_ENABLED";
export const RATEHAWK_HOTELS_SEARCH_PATH = "/internal/search";
export const RATEHAWK_VIEW_STAY_CONTEXT_SECRET_NAME =
  "RATEHAWK_VIEW_STAY_CONTEXT_SECRET";

export function isRatehawkSearchEnabled(env) {
  return envFlag(env?.[RATEHAWK_SEARCH_GATE]);
}

export function isRatehawkSearchInvocationAllowed(env) {
  return isRatehawkInvocationAllowed(env) && isRatehawkSearchEnabled(env);
}

function _text(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _guard({
  reason,
  warnings = [],
  retryAfter = null,
  invoked = false,
  extras = {},
} = {}) {
  const nextWarnings = Array.isArray(warnings) ? [...warnings] : [];
  if (!nextWarnings.includes("ratehawk_invocation_blocked")) {
    nextWarnings.push("ratehawk_invocation_blocked");
  }
  return redactRatehawkSecrets({
    ok: true,
    source: RATEHAWK_STAY_CARD_SOURCE,
    provider: RATEHAWK_PROVIDER,
    count: 0,
    stays: [],
    invoked: invoked === true,
    reason: reason || "ratehawk_search_disabled",
    warnings: [...new Set(nextWarnings)],
    retry_after:
      retryAfter == null || !Number.isFinite(Number(retryAfter))
        ? null
        : Math.max(1, Math.round(Number(retryAfter))),
    retryable: [
      "timeout",
      "provider_error",
      "provider_fetch_failed",
      "provider_quota_exhausted",
      "production_quota_unconfigured",
      "quota_coordinator_missing",
    ].includes(reason),
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
    view_stay_context: null,
    view_stay_context_expires_at: null,
    ...extras,
  });
}

function _hotelIdentity(hotel, market) {
  const staticVm =
    hotel?.static_vm && typeof hotel.static_vm === "object"
      ? hotel.static_vm
      : {};
  const location =
    hotel?.location && typeof hotel.location === "object" ? hotel.location : {};
  const hid = hotel?.hid ?? hotel?.id ?? staticVm.hid;
  return {
    hid,
    name: hotel?.name || hotel?.hotel_name || staticVm.name || staticVm.hotel_name,
    address: hotel?.address || staticVm.address || staticVm.address_line,
    city:
      hotel?.city ||
      staticVm.city ||
      staticVm.region_name ||
      market?.city_key ||
      "",
    region: hotel?.region || staticVm.region || staticVm.region_name || market?.city_key || "",
    country: hotel?.country || staticVm.country || market?.country_code || "",
    lat: hotel?.lat ?? hotel?.latitude ?? staticVm.latitude ?? location.lat,
    lng: hotel?.lng ?? hotel?.longitude ?? staticVm.longitude ?? location.lng,
    image_url: hotel?.image_url || staticVm.image_url || null,
    image_ref: hotel?.image_ref || staticVm.image_ref || null,
    star_rating: hotel?.star_rating ?? staticVm.star_rating ?? hotel?.star_rating,
    type: hotel?.type || staticVm.kind || "hotel",
  };
}

function _firstAcceptedRate(rates) {
  if (!Array.isArray(rates)) return { raw: null, offer: null };
  for (const raw of rates) {
    const offer = normalizeRatehawkRateOffer(raw);
    if (offer?.ok === true && offer.hard_stop !== true) {
      return { raw, offer };
    }
  }
  return { raw: null, offer: null };
}

function _publicStayFields(stay, issued, now, ttlMs) {
  const next = { ...stay };
  next.retrieved_at = Number(now);
  next.expires_at = Number(now) + Number(ttlMs);
  if (issued?.ok === true) {
    next.view_stay_context = issued.token;
    next.view_stay_context_expires_at = issued.expires_at;
    next.stay_context = issued.claims;
    next.checkin = issued.claims.checkin;
    next.checkout = issued.claims.checkout;
    next.residency = issued.claims.residency;
    next.currency = issued.claims.currency;
    next.guests = issued.claims.guests;
    next.hid = issued.claims.hid;
  } else {
    next.view_stay_context = null;
    next.view_stay_context_expires_at = null;
    next.price_label = null;
    next.availability_label = null;
  }
  delete next.book_hash;
  delete next.match_hash;
  delete next.reconciliation_amount;
  delete next.internal_settlement;
  return next;
}

export async function handleRatehawkPublicSearchRequest({
  env = {},
  body = {},
  fetchImpl = null,
  now = Date.now(),
  contentStore = null,
} = {}) {
  if (isRatehawkIsolatedTestWorker(env)) {
    return _guard({ reason: "production_path_forbidden_on_test_worker" });
  }

  const requestBody =
    body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (hasForbiddenPublicSearchClientControl(requestBody)) {
    return _guard({ reason: "client_control_forbidden" });
  }

  const trigger = String(
    requestBody.trigger || RATEHAWK_SEARCH_TRIGGERS.LIVE_SEARCH,
  );
  const guestsCheck = canonicalizePublicSearchGuests(
    Array.isArray(requestBody.guests) ? requestBody.guests : [],
  );
  const criteria = isPublicLiveSearchCriteriaComplete({
    destination: {
      market_key: requestBody.market_key,
      country: requestBody.country,
      city: requestBody.city,
      region: requestBody.region,
      destination: requestBody.destination,
      q: requestBody.q,
    },
    checkin: requestBody.checkin,
    checkout: requestBody.checkout,
    guests: guestsCheck.ok ? guestsCheck.guests : requestBody.guests,
  });
  const decision = shouldIssueRatehawkSearch({
    trigger,
    criteria,
    market: { ok: true },
  });
  if (decision.issue !== true) {
    return _guard({ reason: decision.reason });
  }

  const dates = assertPublicSearchStayDates(
    requestBody.checkin,
    requestBody.checkout,
    now,
  );
  if (dates.ok !== true) {
    return _guard({ reason: dates.reason });
  }
  if (guestsCheck.ok !== true) {
    return _guard({ reason: guestsCheck.reason });
  }

  const language = canonicalizePublicSearchLanguage(requestBody.language);
  if (language.ok !== true) {
    return _guard({ reason: language.reason });
  }
  const currency = canonicalizePublicSearchCurrency(requestBody.currency);
  if (currency.ok !== true) {
    return _guard({ reason: currency.reason });
  }

  const marketConfig = parseConfiguredSearchMarkets(env);
  const market = resolvePublicSearchMarket(marketConfig, {
    market_key: requestBody.market_key,
    country: requestBody.country,
    city: requestBody.city,
    region: requestBody.region,
    destination: requestBody.destination,
    q: requestBody.q,
  });
  if (market.ok !== true) {
    return _guard({ reason: market.reason || "unsupported_market" });
  }

  const residency = canonicalizePublicSearchResidency(
    requestBody.residency,
    market.market,
  );
  if (residency.ok !== true) {
    return _guard({ reason: residency.reason });
  }

  if (!isRatehawkSearchInvocationAllowed(env)) {
    return _guard({ reason: "ratehawk_search_disabled" });
  }

  const config = resolveRatehawkConfig(env);
  if (config.invocation_allowed !== true || !config.has_key_id || !config.has_api_key) {
    return _guard({
      reason: config.reasons[0] || "missing_configuration",
    });
  }

  const contextSecret = _text(env?.[RATEHAWK_VIEW_STAY_CONTEXT_SECRET_NAME], 800);
  if (!contextSecret) {
    return _guard({ reason: "view_stay_context_secret_missing" });
  }

  if (contentStore && typeof contentStore.write === "function") {
    // Search never writes static Content D1. The injectable seam stays unused.
  }

  const stayIntent = {
    checkin: dates.checkin,
    checkout: dates.checkout,
    residency: residency.residency,
    language: language.language,
    currency: currency.currency,
    guests: guestsCheck.guests,
  };

  const transport = await fetchRatehawkPublicSerp({
    env,
    market: market.market,
    stay: stayIntent,
    fetchImpl,
    timeoutMs: marketConfig.limits.search_timeout_ms,
    now,
  });

  if (transport.invoked !== true) {
    return _guard({
      reason: transport.reason || "ratehawk_search_disabled",
      retryAfter: transport.retry_after,
    });
  }
  if (transport.ok !== true) {
    return _guard({
      reason: transport.reason || "provider_error",
      invoked: true,
      retryAfter: transport.retry_after,
    });
  }

  const limits = resolvePublicSearchResultLimit(
    marketConfig,
    market.market,
    trigger,
  );
  const hotels = dedupeHotelsByHid(
    Array.isArray(transport.hotels) ? transport.hotels : [],
  );
  const stays = [];
  const warnings = [];
  let envelopeContext = null;
  let envelopeExpires = null;
  let envelopeClaims = null;

  for (const hotel of hotels) {
    if (stays.length >= limits.take) break;
    const identity = _hotelIdentity(hotel, market.market);
    const accepted = _firstAcceptedRate(hotel?.rates);
    const mapped = buildExistingHotelCardSearchDto({
      source: RATEHAWK_STAY_CARD_SOURCE,
      search_contract_enabled: true,
      ratehawkHotel: identity,
      liveRate: accepted.raw,
      stay22FallbackUrl: null,
      fluxidiStayId: Number(identity.hid) > 0 ? `ratehawk:${Number(identity.hid)}` : null,
      catalogHid: identity.hid,
    });
    if (mapped.hard_stop === true || mapped.ok !== true || !mapped.stay) {
      if (mapped.reason) warnings.push(mapped.reason);
      continue;
    }

    let issued = null;
    if (mapped.has_live_ratehawk_availability === true) {
      issued = await issueRatehawkViewStayContext(
        contextSecret,
        {
          source: "ratehawk",
          hid: Number(identity.hid),
          checkin: stayIntent.checkin,
          checkout: stayIntent.checkout,
          residency: stayIntent.residency,
          currency: stayIntent.currency,
          guests: stayIntent.guests,
        },
        { now },
      );
      if (issued.ok !== true) {
        warnings.push(issued.reason || "view_stay_context_incomplete");
        issued = null;
      }
    }

    const publicStay = _publicStayFields(
      mapped.stay,
      issued,
      now,
      marketConfig.limits.rate_cache_ttl_ms,
    );
    stays.push(publicStay);
    if (issued?.ok === true && !envelopeContext) {
      envelopeContext = issued.token;
      envelopeExpires = issued.expires_at;
      envelopeClaims = issued.claims;
    }
  }

  return redactRatehawkSecrets(
    {
      ok: true,
      invoked: true,
      source: RATEHAWK_STAY_CARD_SOURCE,
      provider: RATEHAWK_PROVIDER,
      count: stays.length,
      stays,
      reason: null,
      warnings: [...new Set(warnings)],
      retry_after: null,
      retryable: false,
      ratehawk: {
        invocation_allowed: true,
        connected: true,
        status: "search_ok",
        search_enabled: true,
      },
      limits: {
        initial_hotel_limit: limits.initial_hotel_limit,
        load_more_increment: limits.load_more_increment,
        absolute_maximum: limits.absolute_maximum,
      },
      stay22_fallback_retained: true,
      mobility_independent_of_ratehawk: true,
      retrieved_at: Number(now),
      expires_at: Number(now) + marketConfig.limits.rate_cache_ttl_ms,
      view_stay_context: envelopeContext,
      view_stay_context_expires_at: envelopeExpires,
      stay_context: envelopeClaims,
      freshness: {
        ...annotateSearchResultMetadata({
          requestedHids: hotels.map((hotel) => hotel?.hid).filter(Boolean),
          receivedHids: stays.map((stay) => stay.provider_id),
        }),
        retrieved_at: Number(now),
        expires_at: Number(now) + marketConfig.limits.rate_cache_ttl_ms,
      },
    },
    env,
  );
}
