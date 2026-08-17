/**
 * Production RateHawk prebook transport.
 *
 * One allowlisted POST /api/b2b/v3/hotel/prebook/ with the unsealed
 * book_hash. Quota is consumed immediately before the request. No retry.
 */

import {
  RATEHAWK_PREBOOK_PATH,
  RATEHAWK_PROVIDER,
  isRatehawkPrebookInvocationAllowed,
  ratehawkProviderAuthHeader,
  redactRatehawkSecrets,
  resolveRatehawkConfig,
} from "./ratehawk_provider.mjs";
import {
  RATEHAWK_QUOTA_ENDPOINTS,
  reserveRatehawkProviderQuota,
} from "./ratehawk_provider_quota.mjs";
import { RATEHAWK_PREBOOK_TIMEOUT_MS } from "./ratehawk_prebook_contract.mjs";

export const RATEHAWK_PREBOOK_OPERATION = "prebook";

function _isAbortError(err) {
  const name = String(err?.name || "");
  const message = String(err?.message || "").toLowerCase();
  return name === "AbortError" || message.includes("abort");
}

function _empty({ config, status, reason, invoked = false, retryAfter = null }) {
  return redactRatehawkSecrets({
    ok: false,
    provider: RATEHAWK_PROVIDER,
    operation: RATEHAWK_PREBOOK_OPERATION,
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
  });
}

function _extractHotels(payload) {
  const data = payload?.data;
  if (Array.isArray(data?.hotels)) return data.hotels;
  if (Array.isArray(data)) return data;
  return [];
}

export async function fetchRatehawkPrebook({
  env,
  bookHash,
  fetchImpl = null,
  timeoutMs = RATEHAWK_PREBOOK_TIMEOUT_MS,
  now = Date.now(),
} = {}) {
  const config = resolveRatehawkConfig(env);
  if (!isRatehawkPrebookInvocationAllowed(env)) {
    return _empty({
      config,
      status: "prebook_disabled",
      reason: "prebook_disabled",
    });
  }
  const hash = String(bookHash || "").trim();
  if (!hash) {
    return _empty({
      config,
      status: "offer_ref_invalid",
      reason: "offer_ref_invalid",
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
    endpoint: RATEHAWK_QUOTA_ENDPOINTS.PREBOOK,
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

  const url = `${config.base_url}${RATEHAWK_PREBOOK_PATH}`;
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timer =
    controller && typeof setTimeout === "function"
      ? setTimeout(() => controller.abort(), Number(timeoutMs) || RATEHAWK_PREBOOK_TIMEOUT_MS)
      : null;

  try {
    const response = await fetchFn(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: authorization,
      },
      body: JSON.stringify({ hash }),
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
    return {
      ok: true,
      provider: RATEHAWK_PROVIDER,
      operation: RATEHAWK_PREBOOK_OPERATION,
      invoked: true,
      environment: config.environment,
      host: config.host,
      status: "prebook_ok",
      reason: null,
      http_status: httpStatus,
      hotels,
      hotel_count: hotels.length,
      retry_after: null,
    };
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
