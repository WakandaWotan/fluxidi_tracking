/**
 * Authorized single-hid RateHawk static-content transport.
 *
 * POST /api/b2b/v3/hotel/info/ with exactly one hid and one locale.
 * Background execution only. No automatic retry. No raw-response storage.
 */

import {
  RATEHAWK_CONTENT_HOTEL_INFO_PATH,
  RATEHAWK_DISCLOSURE_LOCALES,
  applyOfflineContentWrite,
  livePriceKeysPresent,
  normalizeOfflineHotelProjection,
  shouldRunRatehawkContentSync,
  toPublicStaticHotelCard,
  toStoredStaticHotelProjection,
} from "./ratehawk_content_sync.mjs";
import {
  RATEHAWK_CONTENT_STRATEGIES,
  resolveRatehawkContentStrategy,
} from "./ratehawk_content_strategy.mjs";
import {
  RATEHAWK_QUOTA_ENDPOINTS,
  parseRatehawkRateLimitHeaders,
  reconcileRatehawkProviderQuota,
  reserveRatehawkProviderQuota,
} from "./ratehawk_provider_quota.mjs";
import {
  isRatehawkInvocationAllowed,
  ratehawkProviderAuthHeader,
  redactRatehawkSecrets,
  resolveRatehawkConfig,
} from "./ratehawk_provider.mjs";
import { envFlag } from "./parsing_utils.js";

export const RATEHAWK_HOTEL_INFO_TIMEOUT_MS = 15_000;

function _text(value, max = 80) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _hid(value) {
  const text = _text(value?.hid ?? value, 16);
  if (!/^\d{1,10}$/.test(text)) return null;
  return Number(text);
}

function _locale(value) {
  const locale = _text(value, 8).toLowerCase();
  return RATEHAWK_DISCLOSURE_LOCALES.includes(locale) ? locale : null;
}

function _isAbortError(err) {
  const name = String(err?.name || "");
  const message = String(err?.message || "").toLowerCase();
  return name === "AbortError" || message.includes("abort");
}

function _emptyTransport({ reason, invoked = false, rateLimit = null }) {
  return {
    ok: false,
    invoked: invoked === true,
    reason,
    hotel: null,
    http_status: null,
    rate_limit: rateLimit,
    retryable: reason === "timeout" || reason === "provider_error" || reason === "endpoint_exceeded_limit",
  };
}

function _unwrapHotel(payload) {
  const data = payload?.data;
  if (Array.isArray(data)) return data[0] || null;
  if (data && typeof data === "object") {
    if (data.hid != null || data.id != null || data.name != null) return data;
    if (Array.isArray(data.hotels)) return data.hotels[0] || null;
    if (data.hotel && typeof data.hotel === "object") return data.hotel;
  }
  return null;
}

export function buildRatehawkHotelInfoRequest({ hid, language } = {}) {
  const resolvedHid = _hid(hid);
  const locale = _locale(language);
  if (resolvedHid == null) {
    return { ok: false, reason: "invalid_hid", body: null };
  }
  if (!locale) {
    return { ok: false, reason: "locale_unsupported", body: null };
  }
  return {
    ok: true,
    reason: null,
    body: { hid: resolvedHid, language: locale },
  };
}

export function isRatehawkContentTransportAllowed(env) {
  return isRatehawkInvocationAllowed(env) && envFlag(env?.RATEHAWK_CONTENT_SYNC_ENABLED);
}

export async function fetchRatehawkHotelInfo({
  env,
  hid,
  language,
  fetchImpl = null,
  timeoutMs = null,
} = {}) {
  const request = buildRatehawkHotelInfoRequest({ hid, language });
  if (request.ok !== true) {
    return _emptyTransport({ reason: request.reason, invoked: false });
  }
  if (!isRatehawkContentTransportAllowed(env)) {
    return _emptyTransport({
      reason: envFlag(env?.RATEHAWK_CONTENT_SYNC_ENABLED)
        ? resolveRatehawkConfig(env).reasons[0] || "disabled"
        : "content_sync_disabled",
      invoked: false,
    });
  }
  const config = resolveRatehawkConfig(env);
  if (!config.base_url || !config.host) {
    return _emptyTransport({ reason: config.reasons[0] || "unapproved_host", invoked: false });
  }
  const auth = ratehawkProviderAuthHeader(env);
  if (!auth) {
    return _emptyTransport({ reason: "missing_configuration", invoked: false });
  }
  const fetchFn =
    typeof fetchImpl === "function"
      ? fetchImpl
      : typeof fetch === "function"
        ? fetch
        : null;
  if (!fetchFn) {
    return _emptyTransport({ reason: "transport_unavailable", invoked: false });
  }

  const url = `${config.base_url}${RATEHAWK_CONTENT_HOTEL_INFO_PATH}`;
  const effectiveTimeout = Math.min(
    60_000,
    Math.max(1_000, Number(timeoutMs) || RATEHAWK_HOTEL_INFO_TIMEOUT_MS),
  );
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timer =
    controller && typeof setTimeout === "function"
      ? setTimeout(() => controller.abort(), effectiveTimeout)
      : null;

  try {
    const response = await fetchFn(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: auth,
      },
      body: JSON.stringify(request.body),
      signal: controller?.signal,
    });
    const rateLimit = parseRatehawkRateLimitHeaders(response?.headers);
    const httpStatus = Number(response?.status || 0);
    if (httpStatus === 429) {
      return {
        ..._emptyTransport({
          reason: "endpoint_exceeded_limit",
          invoked: true,
          rateLimit,
        }),
        http_status: httpStatus,
        retry_after: rateLimit.retry_after,
      };
    }
    if (httpStatus < 200 || httpStatus >= 300) {
      return {
        ..._emptyTransport({
          reason: "provider_error",
          invoked: true,
          rateLimit,
        }),
        http_status: httpStatus,
      };
    }
    let payload = null;
    try {
      payload = await response.json();
    } catch {
      return {
        ..._emptyTransport({
          reason: "provider_malformed_response",
          invoked: true,
          rateLimit,
        }),
        http_status: httpStatus,
      };
    }
    const etgStatus = _text(payload?.status, 24).toLowerCase();
    if (etgStatus !== "ok") {
      const code = _text(payload?.error, 80).toLowerCase();
      return {
        ..._emptyTransport({
          reason: code || "provider_error",
          invoked: true,
          rateLimit,
        }),
        http_status: httpStatus,
      };
    }
    const hotel = _unwrapHotel(payload);
    if (!hotel) {
      return {
        ..._emptyTransport({
          reason: "hotel_unwrap_failed",
          invoked: true,
          rateLimit,
        }),
        http_status: httpStatus,
      };
    }
    return {
      ok: true,
      invoked: true,
      reason: null,
      hotel,
      http_status: httpStatus,
      rate_limit: rateLimit,
      retryable: false,
    };
  } catch (err) {
    if (_isAbortError(err)) {
      return _emptyTransport({ reason: "timeout", invoked: true });
    }
    return _emptyTransport({ reason: "provider_fetch_failed", invoked: true });
  } finally {
    if (timer) clearTimeout(timer);
  }
}

export async function executeRatehawkContentJob({
  env,
  job = {},
  fetchImpl = null,
  store = null,
  now = Date.now(),
  timeoutMs = null,
  trigger = "admin_internal",
} = {}) {
  const gate = shouldRunRatehawkContentSync({ trigger: job.trigger || trigger, env });
  if (gate.run !== true) {
    return {
      ok: false,
      invoked: false,
      reason: gate.reason,
      requeue: false,
      hid: job.hid ?? null,
      locale: job.locale ?? null,
    };
  }
  const strategy = resolveRatehawkContentStrategy(job.strategy);
  if (strategy.ok !== true) {
    return {
      ok: false,
      invoked: false,
      reason: strategy.reason,
      fallback_used: false,
      requeue: false,
      hid: job.hid ?? null,
      locale: job.locale ?? null,
    };
  }
  const hid = _hid(job.hid ?? job.hids?.[0]);
  const locale = _locale(job.locale);
  if (hid == null) {
    return { ok: false, invoked: false, reason: "invalid_hid", requeue: false, hid: null, locale };
  }
  if (!locale) {
    return { ok: false, invoked: false, reason: "locale_unsupported", requeue: false, hid, locale: null };
  }

  const quota = await reserveRatehawkProviderQuota({
    env,
    endpoint: RATEHAWK_QUOTA_ENDPOINTS.HOTEL_CONTENT,
    now,
  });
  if (quota.allowed !== true) {
    return {
      ok: false,
      invoked: false,
      reason: quota.reason || "provider_quota_exhausted",
      retry_after: quota.retry_after,
      retryable: true,
      requeue: true,
      busy_loop: false,
      hid,
      locale,
    };
  }

  const transport = await fetchRatehawkHotelInfo({
    env,
    hid,
    language: locale,
    fetchImpl,
    timeoutMs,
  });
  if (transport.rate_limit) {
    await reconcileRatehawkProviderQuota({
      env,
      endpoint: RATEHAWK_QUOTA_ENDPOINTS.HOTEL_CONTENT,
      remaining: transport.rate_limit.remaining,
      reset: transport.rate_limit.reset,
      now,
    });
  }
  if (transport.ok !== true) {
    return redactRatehawkSecrets({
      ok: false,
      invoked: transport.invoked === true,
      reason: transport.reason,
      retryable: transport.retryable === true,
      retry_after: transport.retry_after ?? transport.rate_limit?.retry_after ?? null,
      requeue: transport.retryable === true,
      busy_loop: false,
      hid,
      locale,
      http_status: transport.http_status,
      rate_limit: transport.rate_limit,
    }, env);
  }

  const projection = normalizeOfflineHotelProjection(transport.hotel, {
    locale,
    retrieved_at: now,
    revision: transport.hotel?.content_revision ?? null,
    market_key: job.market_key ?? null,
  });
  const stored = toStoredStaticHotelProjection(projection);
  if (store && stored.ok === true) {
    await applyOfflineContentWrite(store, stored);
  }
  return redactRatehawkSecrets({
    ok: stored.ok === true,
    invoked: true,
    reason: stored.reason ?? null,
    hid,
    locale,
    strategy: RATEHAWK_CONTENT_STRATEGIES.SINGLE_HID_INFO,
    requeue: false,
    busy_loop: false,
    rate_limit: transport.rate_limit,
    projection: stored,
    public_card: toPublicStaticHotelCard(stored),
    review_required: stored.state === "review_required",
  }, env);
}

export async function executeRatehawkContentJobs({
  env,
  jobs = [],
  fetchImpl = null,
  store = null,
  now = Date.now(),
  timeoutMs = null,
  trigger = "admin_internal",
} = {}) {
  const results = [];
  let wait = null;
  for (const job of jobs) {
    if (wait) {
      results.push({
        ok: false,
        invoked: false,
        reason: "waiting_for_quota",
        retry_after: wait,
        requeue: true,
        busy_loop: false,
        hid: job.hid ?? null,
        locale: job.locale ?? null,
      });
      continue;
    }
    const result = await executeRatehawkContentJob({
      env,
      job,
      fetchImpl,
      store,
      now,
      timeoutMs,
      trigger,
    });
    results.push(result);
    if (result.requeue === true || Number(result.rate_limit?.remaining) === 0) {
      wait = result.retry_after ?? 1;
    }
  }
  return results;
}

export { livePriceKeysPresent };
