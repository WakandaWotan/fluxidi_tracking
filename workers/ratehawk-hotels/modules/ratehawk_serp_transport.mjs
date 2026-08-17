/**
 * Dedicated RateHawk test-only SERP transport.
 *
 * Operation name is test_serp_hotels — never a generic "search" allowlist
 * entry. Quota uses the existing serp Durable Object endpoint. One POST,
 * no retry, injectable fetch/time.
 */

import { RATEHAWK_PROVIDER, redactRatehawkSecrets } from "./ratehawk_provider.mjs";
import {
  RATEHAWK_QUOTA_ENDPOINTS,
  reserveRatehawkProviderQuota,
} from "./ratehawk_provider_quota.mjs";
import {
  RATEHAWK_TEST_HID,
  RATEHAWK_TEST_OPERATION_SERP,
  RATEHAWK_TEST_TIMEOUT_MS,
  assertRatehawkTestProviderConfig,
  buildRatehawkTestSerpRequest,
  evaluateRatehawkTestSearchGate,
} from "./ratehawk_test_activation.mjs";
import { postRatehawkTestOnce } from "./ratehawk_test_transport.mjs";

function _empty({ config, status, reason, invoked = false }) {
  return redactRatehawkSecrets({
    ok: false,
    provider: RATEHAWK_PROVIDER,
    operation: RATEHAWK_TEST_OPERATION_SERP,
    invoked: invoked === true,
    environment: config?.environment || null,
    host: config?.host || null,
    status,
    reason,
    http_status: null,
    hotels: [],
    hotel_count: 0,
    request: null,
  });
}

export async function fetchRatehawkTestSerp({
  env,
  fetchImpl = null,
  timeoutMs = RATEHAWK_TEST_TIMEOUT_MS,
  now = Date.now(),
} = {}) {
  const gate = evaluateRatehawkTestSearchGate(env);
  const configCheck = assertRatehawkTestProviderConfig(env);
  const config = configCheck.config || null;
  if (gate.ok !== true) {
    return _empty({
      config,
      status: gate.reason,
      reason: gate.reason,
    });
  }
  if (configCheck.ok !== true) {
    return _empty({
      config,
      status: configCheck.reason,
      reason: configCheck.reason,
    });
  }

  const request = buildRatehawkTestSerpRequest(now);
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
    });
  }

  const transport = await postRatehawkTestOnce({
    env,
    operation: RATEHAWK_TEST_OPERATION_SERP,
    path: request.path,
    body: request.body,
    fetchImpl,
    timeoutMs,
  });

  const hotels = Array.isArray(transport.hotels)
    ? transport.hotels.filter((hotel) => Number(hotel?.hid) === RATEHAWK_TEST_HID)
    : [];
  return redactRatehawkSecrets({
    ...transport,
    operation: RATEHAWK_TEST_OPERATION_SERP,
    hotels,
    hotel_count: hotels.length,
    request: {
      operation: request.operation,
      path: request.path,
      host: request.host,
      body: request.body,
      stay: request.stay,
    },
  });
}
