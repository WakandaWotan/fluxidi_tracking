/**
 * One-shot RateHawk test-only provider POST.
 *
 * Used only by the dedicated test SERP and test Hotelpage modules.
 * Never added to RATEHAWK_ALLOWED_OPERATIONS. No retry. Never returns
 * Authorization, credentials, or the raw provider payload.
 */

import {
  RATEHAWK_HOTELPAGE_PATH,
  RATEHAWK_PROVIDER,
  ratehawkProviderAuthHeader,
  redactRatehawkSecrets,
} from "./ratehawk_provider.mjs";
import {
  RATEHAWK_SERP_HOTELS_PATH,
  RATEHAWK_TEST_HOST,
} from "./ratehawk_market_search_limits.mjs";
import {
  RATEHAWK_TEST_OPERATION_HOTELPAGE,
  RATEHAWK_TEST_OPERATION_SERP,
  RATEHAWK_TEST_TIMEOUT_MS,
  assertRatehawkTestHids,
  assertRatehawkTestHid,
  assertRatehawkTestProviderConfig,
  assertRatehawkTestProviderPath,
  isRatehawkTestPathDenied,
} from "./ratehawk_test_activation.mjs";

function _isAbortError(err) {
  const name = String(err?.name || "");
  const message = String(err?.message || "").toLowerCase();
  return name === "AbortError" || message.includes("abort");
}

function _empty({ config, operation, status, reason, invoked = false }) {
  return redactRatehawkSecrets({
    ok: false,
    provider: RATEHAWK_PROVIDER,
    operation,
    invoked: invoked === true,
    environment: config?.environment || null,
    host: config?.host || null,
    status,
    reason,
    http_status: null,
    hotels: [],
    hotel_count: 0,
  });
}

function _expectedPath(operation) {
  if (operation === RATEHAWK_TEST_OPERATION_SERP) return RATEHAWK_SERP_HOTELS_PATH;
  if (operation === RATEHAWK_TEST_OPERATION_HOTELPAGE) return RATEHAWK_HOTELPAGE_PATH;
  return null;
}

function _assertTestBody(operation, body) {
  const src = body && typeof body === "object" && !Array.isArray(body) ? body : {};
  if (
    src.region_id != null ||
    src.longitude != null ||
    src.latitude != null ||
    src.ids != null
  ) {
    return { ok: false, reason: "test_path_denied" };
  }
  if (operation === RATEHAWK_TEST_OPERATION_SERP) {
    return assertRatehawkTestHids(src.hids);
  }
  if (operation === RATEHAWK_TEST_OPERATION_HOTELPAGE) {
    return assertRatehawkTestHid(src.hid);
  }
  return { ok: false, reason: "test_operation_not_allowlisted" };
}

export async function postRatehawkTestOnce({
  env,
  operation,
  path,
  body,
  fetchImpl = null,
  timeoutMs = RATEHAWK_TEST_TIMEOUT_MS,
} = {}) {
  const configCheck = assertRatehawkTestProviderConfig(env);
  const config = configCheck.config || null;
  const expectedPath = _expectedPath(operation);
  if (!expectedPath) {
    return _empty({
      config,
      operation: operation || null,
      status: "test_operation_not_allowlisted",
      reason: "test_operation_not_allowlisted",
    });
  }
  if (isRatehawkTestPathDenied(path)) {
    return _empty({
      config,
      operation,
      status: "test_path_denied",
      reason: "test_path_denied",
    });
  }
  const pathCheck = assertRatehawkTestProviderPath(path, expectedPath);
  if (pathCheck.ok !== true) {
    return _empty({
      config,
      operation,
      status: pathCheck.reason,
      reason: pathCheck.reason,
    });
  }
  if (configCheck.ok !== true) {
    return _empty({
      config,
      operation,
      status: configCheck.reason,
      reason: configCheck.reason,
    });
  }
  const bodyCheck = _assertTestBody(operation, body);
  if (bodyCheck.ok !== true) {
    return _empty({
      config,
      operation,
      status: bodyCheck.reason,
      reason: bodyCheck.reason,
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
      operation,
      status: "transport_unavailable",
      reason: "transport_unavailable",
    });
  }

  const authorization = ratehawkProviderAuthHeader(env);
  if (!authorization) {
    return _empty({
      config,
      operation,
      status: "missing_configuration",
      reason: "missing_configuration",
    });
  }

  const url = `${RATEHAWK_TEST_HOST}${expectedPath}`;
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timer =
    controller && typeof setTimeout === "function"
      ? setTimeout(() => controller.abort(), Number(timeoutMs) || RATEHAWK_TEST_TIMEOUT_MS)
      : null;

  try {
    const response = await fetchFn(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        Authorization: authorization,
      },
      body: JSON.stringify(body),
      signal: controller?.signal,
    });
    const httpStatus = Number(response?.status || 0);
    if (httpStatus === 429) {
      return {
        ..._empty({
          config,
          operation,
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
          operation,
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
          operation,
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
          operation,
          status: "provider_error",
          reason: "provider_error",
          invoked: true,
        }),
        http_status: httpStatus,
      };
    }

    const data = payload?.data;
    const hotels = Array.isArray(data?.hotels)
      ? data.hotels
      : Array.isArray(data)
        ? data
        : [];
    return redactRatehawkSecrets({
      ok: true,
      provider: RATEHAWK_PROVIDER,
      operation,
      invoked: true,
      environment: config.environment,
      host: config.host,
      status: "test_provider_ok",
      reason: null,
      http_status: httpStatus,
      hotels,
      hotel_count: hotels.length,
    });
  } catch (err) {
    if (_isAbortError(err)) {
      return _empty({
        config,
        operation,
        status: "timeout",
        reason: "timeout",
        invoked: true,
      });
    }
    return _empty({
      config,
      operation,
      status: "provider_fetch_failed",
      reason: "provider_fetch_failed",
      invoked: true,
    });
  } finally {
    if (timer) clearTimeout(timer);
  }
}
