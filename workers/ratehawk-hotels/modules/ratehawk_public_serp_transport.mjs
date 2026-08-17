/**
 * Production public RateHawk SERP transport.
 *
 * Used only by the gated public /internal/search path on the production
 * Hotels Worker. Never imported by admin test search. Quota is consumed
 * immediately before the single allowlisted POST. No retry.
 */

import {
  RATEHAWK_PROVIDER,
  ratehawkProviderAuthHeader,
  redactRatehawkSecrets,
  resolveRatehawkConfig,
} from "./ratehawk_provider.mjs";
import {
  RATEHAWK_QUOTA_ENDPOINTS,
  reserveRatehawkProviderQuota,
} from "./ratehawk_provider_quota.mjs";
import {
  RATEHAWK_DEFAULT_SEARCH_LIMITS,
  RATEHAWK_SERP_GEO_PATH,
  RATEHAWK_SERP_REGION_PATH,
} from "./ratehawk_market_search_limits.mjs";

export const RATEHAWK_PUBLIC_SERP_OPERATION = "public_serp";

function _isAbortError(err) {
  const name = String(err?.name || "");
  const message = String(err?.message || "").toLowerCase();
  return name === "AbortError" || message.includes("abort");
}

function _empty({ config, status, reason, invoked = false, retryAfter = null }) {
  return redactRatehawkSecrets({
    ok: false,
    provider: RATEHAWK_PROVIDER,
    operation: RATEHAWK_PUBLIC_SERP_OPERATION,
    invoked: invoked === true,
    environment: config?.environment || null,
    host: config?.host || null,
    status,
    reason,
    http_status: null,
    hotels: [],
    hotel_count: 0,
    retry_after:
      retryAfter == null || !Number.isFinite(Number(retryAfter))
        ? null
        : Math.max(1, Math.round(Number(retryAfter))),
    request: null,
  });
}

export function buildPublicSerpRequest({ market, stay, timeoutSeconds = 30 } = {}) {
  if (!market || typeof market !== "object") {
    return { ok: false, reason: "market_not_enabled" };
  }
  const body = {
    checkin: stay.checkin,
    checkout: stay.checkout,
    residency: stay.residency,
    language: stay.language,
    guests: stay.guests,
    timeout: Number(timeoutSeconds) || 30,
  };
  if (stay.currency) body.currency = stay.currency;

  if (market.region_id) {
    const regionId = Number(market.region_id);
    if (!Number.isInteger(regionId) || regionId <= 0) {
      return { ok: false, reason: "market_region_unusable" };
    }
    return {
      ok: true,
      path: RATEHAWK_SERP_REGION_PATH,
      body: { ...body, region_id: regionId },
    };
  }

  const lat = Number(market.geo?.lat);
  const lng = Number(market.geo?.lng);
  const radiusM = Number(market.geo?.radius_m);
  if (
    !Number.isFinite(lat) ||
    !Number.isFinite(lng) ||
    !Number.isFinite(radiusM) ||
    radiusM <= 0
  ) {
    return { ok: false, reason: "market_geo_unusable" };
  }
  return {
    ok: true,
    path: RATEHAWK_SERP_GEO_PATH,
    body: {
      ...body,
      latitude: lat,
      longitude: lng,
      radius: Math.max(1, radiusM / 1000),
    },
  };
}

function _extractHotels(payload) {
  const data = payload?.data;
  if (Array.isArray(data?.hotels)) return data.hotels;
  if (Array.isArray(data)) return data;
  return [];
}

export async function fetchRatehawkPublicSerp({
  env,
  market,
  stay,
  fetchImpl = null,
  timeoutMs = RATEHAWK_DEFAULT_SEARCH_LIMITS.search_timeout_ms,
  now = Date.now(),
} = {}) {
  const config = resolveRatehawkConfig(env);
  const request = buildPublicSerpRequest({
    market,
    stay,
    timeoutSeconds: Math.round(Number(timeoutMs) / 1000) || 30,
  });
  if (request.ok !== true) {
    return _empty({
      config,
      status: request.reason,
      reason: request.reason,
    });
  }
  if (
    request.path !== RATEHAWK_SERP_REGION_PATH &&
    request.path !== RATEHAWK_SERP_GEO_PATH
  ) {
    return _empty({
      config,
      status: "provider_path_not_allowlisted",
      reason: "provider_path_not_allowlisted",
    });
  }
  if (!config.base_url || !config.host) {
    return _empty({
      config,
      status: "missing_configuration",
      reason: "missing_configuration",
    });
  }

  const fetchFn =
    typeof fetchImpl === "function"
      ? fetchImpl
      : typeof fetch === "function"
        ? fetch
        : null;
  if (!fetchFn) {
    return _empty({
      config,
      status: "transport_unavailable",
      reason: "transport_unavailable",
    });
  }

  const authorization = ratehawkProviderAuthHeader(env);
  if (!authorization) {
    return _empty({
      config,
      status: "missing_configuration",
      reason: "missing_configuration",
    });
  }

  const quota = await reserveRatehawkProviderQuota({
    env,
    endpoint: RATEHAWK_QUOTA_ENDPOINTS.SERP,
    now,
  });
  if (quota.allowed !== true) {
    return _empty({
      config,
      status: quota.reason || "provider_quota_exhausted",
      reason: quota.reason || "provider_quota_exhausted",
      retryAfter: quota.retry_after,
    });
  }

  const url = `${config.base_url}${request.path}`;
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timer =
    controller && typeof setTimeout === "function"
      ? setTimeout(
          () => controller.abort(),
          Number(timeoutMs) || RATEHAWK_DEFAULT_SEARCH_LIMITS.search_timeout_ms,
        )
      : null;

  try {
    const response = await fetchFn(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: authorization,
      },
      body: JSON.stringify(request.body),
      signal: controller?.signal,
    });
    const httpStatus = Number(response?.status || 0);
    if (httpStatus === 429) {
      return {
        ..._empty({
          config,
          status: "rate_limited",
          reason: "endpoint_exceeded_limit",
          invoked: true,
        }),
        http_status: httpStatus,
      };
    }
    if (httpStatus < 200 || httpStatus >= 300) {
      return {
        ..._empty({
          config,
          status: "provider_error",
          reason: "provider_error",
          invoked: true,
        }),
        http_status: httpStatus,
      };
    }

    let payload = null;
    try {
      payload = await response.json();
    } catch {
      return {
        ..._empty({
          config,
          status: "provider_malformed_response",
          reason: "provider_malformed_response",
          invoked: true,
        }),
        http_status: httpStatus,
      };
    }

    const etgStatus = String(payload?.status || "").trim().toLowerCase();
    if (etgStatus !== "ok") {
      return {
        ..._empty({
          config,
          status: "provider_error",
          reason: "provider_error",
          invoked: true,
        }),
        http_status: httpStatus,
      };
    }

    const hotels = _extractHotels(payload);
    return redactRatehawkSecrets({
      ok: true,
      provider: RATEHAWK_PROVIDER,
      operation: RATEHAWK_PUBLIC_SERP_OPERATION,
      invoked: true,
      environment: config.environment,
      host: config.host,
      status: "search_ok",
      reason: null,
      http_status: httpStatus,
      hotels,
      hotel_count: hotels.length,
      retry_after: null,
      request: null,
    });
  } catch (err) {
    if (_isAbortError(err)) {
      return _empty({
        config,
        status: "timeout",
        reason: "timeout",
        invoked: true,
      });
    }
    return _empty({
      config,
      status: "provider_fetch_failed",
      reason: "provider_fetch_failed",
      invoked: true,
    });
  } finally {
    if (timer) clearTimeout(timer);
  }
}
