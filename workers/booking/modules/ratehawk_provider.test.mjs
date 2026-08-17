// RATEHAWK-P0 fail-closed provider foundation
//
// Run:
//   node --test workers/booking/modules/ratehawk_provider.test.mjs

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  RATEHAWK_OVERVIEW_PATH,
  buildRatehawkPublicSearchGuardPayload,
  buildSafeRatehawkProviderStatus,
  isRatehawkInvocationAllowed,
  isRatehawkOperationAllowed,
  isRatehawkSearchSource,
  parseRatehawkBaseUrl,
  probeRatehawkOverview,
  redactRatehawkSecrets,
  resolveRatehawkConfig,
  toSafeRatehawkConfig,
} from "./ratehawk_provider.mjs";

const TEST_API_KEY = "rh_test_secret_do_not_leak_xyz";
const TEST_KEY_ID = "18292";

function validTestEnv(overrides = {}) {
  return {
    RATEHAWK_KEY_ID: TEST_KEY_ID,
    RATEHAWK_API_KEY: TEST_API_KEY,
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_ENABLED: "1",
    ...overrides,
  };
}

function validSandboxEnv(overrides = {}) {
  return validTestEnv({
    RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "sandbox",
    ...overrides,
  });
}

function assertNoSecrets(value, env) {
  const dumped = JSON.stringify(value);
  assert.equal(dumped.includes(TEST_API_KEY), false);
  assert.equal(/Basic\s+[A-Za-z0-9+/=_-]{8,}/i.test(dumped), false);
  const redacted = JSON.stringify(redactRatehawkSecrets(value, env));
  assert.equal(redacted.includes(TEST_API_KEY), false);
}

test("valid test configuration is configured and invocation-allowed when enabled", () => {
  const env = validTestEnv();
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, true);
  assert.equal(config.enabled, true);
  assert.equal(config.invocation_allowed, true);
  assert.equal(config.environment, "test");
  assert.equal(config.host, "api.ratehawk.com");
  assert.equal(config.base_url, "https://api.ratehawk.com");
  assert.equal(config.has_key_id, true);
  assert.equal(config.has_api_key, true);
  assert.deepEqual(config.missing_fields, []);
  assert.equal(config.reasons.includes("environment_host_mismatch"), false);
  assert.equal("api_key" in config, false);
  assert.equal("key_id" in config, false);
  assertNoSecrets(config, env);
  assertNoSecrets(toSafeRatehawkConfig(config), env);
});

test("valid sandbox configuration matches sandbox host only", () => {
  const env = validSandboxEnv();
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, true);
  assert.equal(config.environment, "sandbox");
  assert.equal(config.host, "api-sandbox.ratehawk.com");
  assert.equal(config.base_url, "https://api-sandbox.ratehawk.com");
  assert.equal(config.invocation_allowed, true);
  assertNoSecrets(config, env);
});

test("mismatched test key on sandbox host is rejected", async () => {
  const env = validTestEnv({
    RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com",
    RATEHAWK_ENVIRONMENT: "test",
    RATEHAWK_ENABLED: "1",
  });
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, false);
  assert.equal(config.invocation_allowed, false);
  assert.equal(config.reasons.includes("environment_host_mismatch"), true);
  assert.equal(isRatehawkInvocationAllowed(env), false);

  let fetchCalls = 0;
  const result = await probeRatehawkOverview({
    env,
    fetchImpl: async () => {
      fetchCalls += 1;
      throw new Error("must_not_call_ratehawk");
    },
  });
  assert.equal(result.invoked, false);
  assert.equal(result.connected, false);
  assert.equal(result.status, "environment_host_mismatch");
  assert.equal(fetchCalls, 0);
  assertNoSecrets(result, env);
});

test("mismatched sandbox key on test/production host is rejected", () => {
  const env = validSandboxEnv({
    RATEHAWK_BASE_URL: "https://api.ratehawk.com",
  });
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, false);
  assert.equal(config.reasons.includes("environment_host_mismatch"), true);
  assert.equal(isRatehawkInvocationAllowed(env), false);
});

test("missing configuration is rejected", () => {
  const env = {
    RATEHAWK_ENABLED: "1",
  };
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, false);
  assert.equal(config.invocation_allowed, false);
  assert.equal(config.reasons.includes("missing_configuration"), true);
  assert.deepEqual(config.missing_fields, [
    "RATEHAWK_KEY_ID",
    "RATEHAWK_API_KEY",
    "RATEHAWK_BASE_URL",
    "RATEHAWK_ENVIRONMENT",
  ]);
  assert.equal(isRatehawkInvocationAllowed(env), false);
  assertNoSecrets(config, env);
});

test("unknown environment is rejected and never treated as production", () => {
  const env = validTestEnv({ RATEHAWK_ENVIRONMENT: "live" });
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, false);
  assert.equal(config.environment, null);
  assert.equal(config.reasons.includes("unknown_environment"), true);
  assert.equal(config.invocation_allowed, false);
});

test("unapproved host is rejected", () => {
  const cases = [
    "https://api.worldota.net",
    "https://api-sandbox.worldota.net",
    "https://evil.example",
    "http://api.ratehawk.com",
    "https://user:pass@api.ratehawk.com",
    "https://api.ratehawk.com/evil",
  ];
  for (const baseUrl of cases) {
    const parsed = parseRatehawkBaseUrl(baseUrl);
    assert.equal(parsed.ok, false, baseUrl);
    assert.equal(parsed.reason, "unapproved_host", baseUrl);
    const env = validTestEnv({ RATEHAWK_BASE_URL: baseUrl });
    const config = resolveRatehawkConfig(env);
    assert.equal(config.configured, false, baseUrl);
    assert.equal(config.invocation_allowed, false, baseUrl);
    assert.equal(config.reasons.includes("unapproved_host"), true, baseUrl);
  }
});

test("feature gate blocks invocation when RATEHAWK_ENABLED is off", async () => {
  const env = validTestEnv({ RATEHAWK_ENABLED: "0" });
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, true);
  assert.equal(config.enabled, false);
  assert.equal(config.invocation_allowed, false);
  assert.equal(isRatehawkOperationAllowed(env, "overview"), false);
  assert.equal(isRatehawkOperationAllowed(env, "search"), false);
  assert.equal(isRatehawkOperationAllowed(env, "booking"), false);

  let fetchCalls = 0;
  const result = await probeRatehawkOverview({
    env,
    fetchImpl: async () => {
      fetchCalls += 1;
      return jsonResponse({ status: "ok", data: [] });
    },
  });
  assert.equal(fetchCalls, 0);
  assert.equal(result.invoked, false);
  assert.equal(result.connected, false);
  assert.equal(result.status, "disabled");
});

test("feature gate never allows search, booking, prebook or cancel", () => {
  const env = validTestEnv();
  assert.equal(isRatehawkOperationAllowed(env, "overview"), true);
  for (const op of ["search", "prebook", "booking", "finish", "cancel", "voucher"]) {
    assert.equal(isRatehawkOperationAllowed(env, op), false, op);
  }
  const guard = buildRatehawkPublicSearchGuardPayload({ env });
  assert.equal(guard.count, 0);
  assert.deepEqual(guard.stays, []);
  assert.equal(guard.ratehawk.invocation_allowed, false);
  assert.equal(guard.ratehawk.connected, false);
  assert.equal(guard.warnings.includes("ratehawk_invocation_blocked"), true);
  assert.equal(isRatehawkSearchSource("ratehawk"), true);
  assert.equal(isRatehawkSearchSource("expedia-rapid"), false);
  assertNoSecrets(guard, env);
});

test("production environment stays fail-closed without production gate", async () => {
  const env = validTestEnv({
    RATEHAWK_ENVIRONMENT: "production",
    RATEHAWK_ENABLED: "1",
  });
  const config = resolveRatehawkConfig(env);
  assert.equal(config.configured, true);
  assert.equal(config.invocation_allowed, false);
  assert.equal(config.reasons.includes("production_gate_closed"), true);
  let fetchCalls = 0;
  const result = await probeRatehawkOverview({
    env,
    fetchImpl: async () => {
      fetchCalls += 1;
      return jsonResponse({ status: "ok", data: [] });
    },
  });
  assert.equal(fetchCalls, 0);
  assert.equal(result.connected, false);
  assert.equal(result.status, "production_gate_closed");
});

test("timeout/abort handling does not leak secrets", async () => {
  const env = validTestEnv({ RATEHAWK_TIMEOUT_MS: "20" });
  const result = await probeRatehawkOverview({
    env,
    timeoutMs: 20,
    fetchImpl: (_url, options) =>
      new Promise((_resolve, reject) => {
        const signal = options?.signal;
        if (!signal) {
          reject(new Error("missing_abort_signal"));
          return;
        }
        signal.addEventListener("abort", () => {
          const err = new Error("Aborted");
          err.name = "AbortError";
          reject(err);
        });
      }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.invoked, true);
  assert.equal(result.status, "timeout");
  assert.equal(result.connected, false);
  assertNoSecrets(result, env);
});

test("secrets are redacted from snapshots and never appear on config", () => {
  const env = validTestEnv();
  const dirty = {
    Authorization: `Basic ${TEST_API_KEY}`,
    nested: { RATEHAWK_API_KEY: TEST_API_KEY, note: `key=${TEST_API_KEY}` },
  };
  const redacted = redactRatehawkSecrets(dirty, env);
  const dumped = JSON.stringify(redacted);
  assert.equal(dumped.includes(TEST_API_KEY), false);
  assert.equal(redacted.Authorization, "[redacted]");
  assert.equal(redacted.nested.RATEHAWK_API_KEY, "[redacted]");
  assert.equal(redacted.nested.note.includes(TEST_API_KEY), false);
  const config = resolveRatehawkConfig(env);
  assert.equal(JSON.stringify(config).includes(TEST_API_KEY), false);
});

test("mocked /overview/ success returns sanitized connectivity, not raw payload", async () => {
  const env = validTestEnv();
  let seenUrl = "";
  let seenAuth = "";
  const result = await probeRatehawkOverview({
    env,
    fetchImpl: async (url, options) => {
      seenUrl = String(url);
      seenAuth = String(options?.headers?.Authorization || "");
      return jsonResponse({
        status: "ok",
        data: [{ endpoint: "/api/b2b/v3/search/hp/" }, { endpoint: "/api/b2b/v3/overview/" }],
        debug: { api_key_id: TEST_KEY_ID, request_id: "abc" },
        error: null,
      });
    },
  });
  assert.equal(seenUrl, `https://api.ratehawk.com${RATEHAWK_OVERVIEW_PATH}`);
  assert.equal(seenAuth.startsWith("Basic "), true);
  assert.equal(result.ok, true);
  assert.equal(result.invoked, true);
  assert.equal(result.status, "test_environment_reachable");
  assert.equal(result.connected, false);
  assert.equal(result.endpoint_count, 2);
  assert.equal(result.http_status, 200);
  assert.equal("data" in result, false);
  assert.equal("debug" in result, false);
  assertNoSecrets(result, env);
});

test("mocked /overview/ provider error is normalized and not connected", async () => {
  const env = validSandboxEnv();
  const result = await probeRatehawkOverview({
    env,
    fetchImpl: async () =>
      jsonResponse({
        status: "error",
        error: "incorrect_credentials",
        data: null,
      }),
  });
  assert.equal(result.ok, false);
  assert.equal(result.invoked, true);
  assert.equal(result.status, "provider_error");
  assert.equal(result.reason, "incorrect_credentials");
  assert.equal(result.connected, false);
  assert.equal(result.environment, "sandbox");
  assertNoSecrets(result, env);
});

test("admin status never claims LIVE/connected from config alone", () => {
  const mismatch = buildSafeRatehawkProviderStatus(
    validTestEnv({ RATEHAWK_BASE_URL: "https://api-sandbox.ratehawk.com" }),
  );
  assert.equal(mismatch.connected, false);
  assert.equal(mismatch.status, "environment_host_mismatch");
  assert.equal(mismatch.invocation_allowed, false);

  const ready = buildSafeRatehawkProviderStatus(validTestEnv());
  assert.equal(ready.connected, false);
  assert.equal(ready.status, "foundation_ready");
  assert.equal(ready.configured, true);
});

function jsonResponse(body, status = 200) {
  return {
    status,
    json: async () => body,
  };
}
