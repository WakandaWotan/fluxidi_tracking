/**
 * RateHawk / Emerging Travel Group provider foundation (P0).
 *
 * Isolated, fail-closed config + mocked-transport overview probe only.
 * This module must never:
 *   - default a TEST key onto the sandbox host (or vice versa);
 *   - treat unknown/test as production;
 *   - return API keys, Basic auth material, or raw ETG payloads;
 *   - call RateHawk from existing booking/search flows.
 *
 * Official host contract (docs.emergingtravel.com):
 *   sandbox     → https://api-sandbox.ratehawk.com
 *   test        → https://api.ratehawk.com   (demo hotel hid 8473727 only)
 *   production  → https://api.ratehawk.com   (separate production key + gate)
 *
 * Secrets stay in env (wrangler secret put). Never log or snapshot them.
 */

import { envFlag, safeStr } from "./parsing_utils.js";

export const RATEHAWK_PROVIDER = "ratehawk";

export const RATEHAWK_ENVIRONMENTS = Object.freeze([
  "sandbox",
  "test",
  "production",
]);

export const RATEHAWK_HOST_BY_ENVIRONMENT = Object.freeze({
  sandbox: "api-sandbox.ratehawk.com",
  test: "api.ratehawk.com",
  production: "api.ratehawk.com",
});

export const RATEHAWK_ALLOWED_HOSTS = Object.freeze([
  "api.ratehawk.com",
  "api-sandbox.ratehawk.com",
]);

export const RATEHAWK_OVERVIEW_PATH = "/api/b2b/v3/overview/";
export const RATEHAWK_DEFAULT_TIMEOUT_MS = 12_000;
export const RATEHAWK_MIN_TIMEOUT_MS = 1_000;
export const RATEHAWK_MAX_TIMEOUT_MS = 60_000;

export const RATEHAWK_ALLOWED_OPERATIONS = Object.freeze(["overview"]);

export const RATEHAWK_SEARCH_SOURCES = Object.freeze([
  "ratehawk",
  "rate-hawk",
  "etg",
  "emerging-travel",
]);

const REQUIRED_ENV_FIELDS = Object.freeze([
  "RATEHAWK_KEY_ID",
  "RATEHAWK_API_KEY",
  "RATEHAWK_BASE_URL",
  "RATEHAWK_ENVIRONMENT",
]);

const PROVIDER_ERROR_CODES = Object.freeze([
  "incorrect_credentials",
  "invalid_auth_header",
  "no_auth_header",
  "endpoint_not_active",
  "endpoint_exceeded_limit",
  "endpoint_not_found",
  "invalid_params",
  "not_allowed",
  "not_allowed_host",
  "unknown",
  "timeout",
]);

function _trim(value, max = 600) {
  const text = safeStr(value);
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _normalizeEnvironment(raw) {
  const value = _trim(raw, 32).toLowerCase();
  if (!value) return "";
  if (RATEHAWK_ENVIRONMENTS.includes(value)) return value;
  return "";
}

function _unknownEnvironment(raw) {
  const value = _trim(raw, 32).toLowerCase();
  return Boolean(value) && !RATEHAWK_ENVIRONMENTS.includes(value);
}

function _clampTimeoutMs(raw, fallback = RATEHAWK_DEFAULT_TIMEOUT_MS) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return fallback;
  const rounded = Math.trunc(n);
  if (rounded < RATEHAWK_MIN_TIMEOUT_MS) return RATEHAWK_MIN_TIMEOUT_MS;
  if (rounded > RATEHAWK_MAX_TIMEOUT_MS) return RATEHAWK_MAX_TIMEOUT_MS;
  return rounded;
}

function _pushUnique(list, value) {
  if (!value || list.includes(value)) return;
  list.push(value);
}

/**
 * Parse RATEHAWK_BASE_URL. Rejects credentials-in-URL, non-https, ports
 * other than 443, query/hash, and any host outside the official allowlist.
 * Path may be empty or the API prefix `/api/b2b/v3`.
 */
export function parseRatehawkBaseUrl(raw) {
  const text = _trim(raw, 300);
  if (!text) {
    return { ok: false, reason: "missing_base_url", host: null, base_url: null };
  }
  if (/\s/.test(text) || /@/.test(text) || /%40/i.test(text)) {
    return { ok: false, reason: "unapproved_host", host: null, base_url: null };
  }
  let url;
  try {
    url = new URL(text);
  } catch {
    return { ok: false, reason: "unapproved_host", host: null, base_url: null };
  }
  const host = String(url.hostname || "").toLowerCase();
  const port = String(url.port || "");
  const path = String(url.pathname || "").replace(/\/+$/, "") || "";
  const pathOk = path === "" || path === "/api/b2b/v3";
  if (url.protocol !== "https:") {
    return { ok: false, reason: "unapproved_host", host: null, base_url: null };
  }
  if (url.username || url.password) {
    return { ok: false, reason: "unapproved_host", host: null, base_url: null };
  }
  if (port && port !== "443") {
    return { ok: false, reason: "unapproved_host", host: null, base_url: null };
  }
  if (url.search || url.hash || !pathOk) {
    return { ok: false, reason: "unapproved_host", host: null, base_url: null };
  }
  if (!RATEHAWK_ALLOWED_HOSTS.includes(host)) {
    return { ok: false, reason: "unapproved_host", host: null, base_url: null };
  }
  return {
    ok: true,
    reason: null,
    host,
    base_url: `https://${host}`,
  };
}

function _expectedHost(environment) {
  return RATEHAWK_HOST_BY_ENVIRONMENT[environment] || null;
}

function _collectSecretValues(env) {
  const values = [];
  const apiKey = _trim(env?.RATEHAWK_API_KEY, 800);
  const keyId = _trim(env?.RATEHAWK_KEY_ID, 120);
  if (apiKey) values.push(apiKey);
  if (keyId) values.push(keyId);
  return values;
}

function _redactString(text, secrets) {
  let out = String(text ?? "");
  for (const secret of secrets) {
    if (!secret || secret.length < 2) continue;
    if (!out.includes(secret)) continue;
    out = out.split(secret).join("[redacted]");
  }
  out = out.replace(/Basic\s+[A-Za-z0-9+/=_-]+/gi, "Basic [redacted]");
  return out;
}

/**
 * Recursively strip RateHawk secrets from any log/error/test snapshot value.
 * Never throws.
 */
export function redactRatehawkSecrets(value, env = null) {
  const secrets = _collectSecretValues(env);
  const seen = new WeakSet();
  const walk = (node) => {
    if (node == null) return node;
    if (typeof node === "string") return _redactString(node, secrets);
    if (typeof node === "number" || typeof node === "boolean") return node;
    if (typeof node !== "object") return _redactString(String(node), secrets);
    if (seen.has(node)) return "[redacted_cycle]";
    seen.add(node);
    if (Array.isArray(node)) return node.map((item) => walk(item));
    const out = {};
    for (const [key, child] of Object.entries(node)) {
      if (/api[_-]?key|authorization|secret|password|token|basic/i.test(key)) {
        out[key] = "[redacted]";
        continue;
      }
      out[key] = walk(child);
    }
    return out;
  };
  return walk(value);
}

export function toSafeRatehawkConfig(config) {
  const src = config && typeof config === "object" ? config : {};
  return {
    provider: RATEHAWK_PROVIDER,
    configured: src.configured === true,
    enabled: src.enabled === true,
    production_enabled: src.production_enabled === true,
    invocation_allowed: src.invocation_allowed === true,
    environment: src.environment || null,
    base_url: src.base_url || null,
    host: src.host || null,
    has_key_id: src.has_key_id === true,
    has_api_key: src.has_api_key === true,
    missing_fields: Array.isArray(src.missing_fields)
      ? [...src.missing_fields]
      : [],
    reasons: Array.isArray(src.reasons) ? [...src.reasons] : [],
    timeout_ms: Number.isFinite(Number(src.timeout_ms))
      ? Number(src.timeout_ms)
      : RATEHAWK_DEFAULT_TIMEOUT_MS,
  };
}

/**
 * Fail-closed env resolver. Never throws at module load.
 * Does not return RATEHAWK_API_KEY or RATEHAWK_KEY_ID values.
 */
export function resolveRatehawkConfig(env) {
  const missingFields = [];
  for (const name of REQUIRED_ENV_FIELDS) {
    if (!_trim(env?.[name], 800)) missingFields.push(name);
  }

  const environmentRaw = env?.RATEHAWK_ENVIRONMENT;
  const environment = _normalizeEnvironment(environmentRaw);
  const parsed = parseRatehawkBaseUrl(env?.RATEHAWK_BASE_URL);
  const enabled = envFlag(env?.RATEHAWK_ENABLED);
  const productionEnabled = envFlag(env?.RATEHAWK_PRODUCTION_ENABLED);
  const timeoutMs = _clampTimeoutMs(
    env?.RATEHAWK_TIMEOUT_MS,
    RATEHAWK_DEFAULT_TIMEOUT_MS,
  );
  const hasKeyId = Boolean(_trim(env?.RATEHAWK_KEY_ID, 120));
  const hasApiKey = Boolean(_trim(env?.RATEHAWK_API_KEY, 800));

  const reasons = [];
  if (missingFields.length) _pushUnique(reasons, "missing_configuration");
  if (_unknownEnvironment(environmentRaw)) {
    _pushUnique(reasons, "unknown_environment");
  }
  if (_trim(env?.RATEHAWK_BASE_URL, 300) && !parsed.ok) {
    _pushUnique(reasons, parsed.reason || "unapproved_host");
  }
  if (environment && parsed.ok) {
    const expected = _expectedHost(environment);
    if (expected && parsed.host !== expected) {
      _pushUnique(reasons, "environment_host_mismatch");
    }
  }
  if (!enabled) _pushUnique(reasons, "disabled");

  const hostMatches =
    Boolean(environment) &&
    parsed.ok === true &&
    parsed.host === _expectedHost(environment);
  const configured =
    missingFields.length === 0 &&
    Boolean(environment) &&
    parsed.ok === true &&
    hostMatches &&
    !_unknownEnvironment(environmentRaw);

  if (configured && environment === "production" && !productionEnabled) {
    _pushUnique(reasons, "production_gate_closed");
  }

  const invocationAllowed =
    configured === true &&
    enabled === true &&
    (environment !== "production" || productionEnabled === true);

  return toSafeRatehawkConfig({
    configured,
    enabled,
    production_enabled: productionEnabled,
    invocation_allowed: invocationAllowed,
    environment: environment || null,
    base_url: parsed.ok ? parsed.base_url : null,
    host: parsed.ok ? parsed.host : null,
    has_key_id: hasKeyId,
    has_api_key: hasApiKey,
    missing_fields: missingFields,
    reasons,
    timeout_ms: timeoutMs,
  });
}

export function isRatehawkSearchSource(source) {
  const value = _trim(source, 64).toLowerCase();
  return RATEHAWK_SEARCH_SOURCES.includes(value);
}

export function isRatehawkInvocationAllowed(env) {
  return resolveRatehawkConfig(env).invocation_allowed === true;
}

/**
 * Hard gate: only the overview probe may ever talk to RateHawk, and only
 * after config + feature + environment gates pass. Search/booking/cancel
 * are always denied in this P0 foundation.
 */
export function isRatehawkOperationAllowed(env, operation) {
  const op = _trim(operation, 40).toLowerCase();
  if (!RATEHAWK_ALLOWED_OPERATIONS.includes(op)) return false;
  return isRatehawkInvocationAllowed(env);
}

export function buildSafeRatehawkProviderStatus(env) {
  const config = resolveRatehawkConfig(env);
  let status = "provider_not_configured";
  if (config.reasons.includes("environment_host_mismatch")) {
    status = "environment_host_mismatch";
  } else if (config.reasons.includes("unapproved_host")) {
    status = "unapproved_host";
  } else if (config.reasons.includes("unknown_environment")) {
    status = "unknown_environment";
  } else if (config.configured && config.reasons.includes("production_gate_closed")) {
    status = "production_gate_closed";
  } else if (config.configured && !config.enabled) {
    status = "disabled";
  } else if (config.invocation_allowed) {
    status = "foundation_ready";
  } else if (config.reasons.includes("missing_configuration")) {
    status = "provider_not_configured";
  } else if (!config.enabled) {
    status = "disabled";
  }

  return {
    configured: config.configured === true,
    enabled: config.enabled === true,
    invocation_allowed: config.invocation_allowed === true,
    role: "native_inventory",
    status,
    environment: config.environment,
    host: config.host,
    // Never claim LIVE/connected from config alone. A later live probe
    // (production + production gate + successful overview) may set this.
    connected: false,
    reasons: [...config.reasons],
  };
}

export function buildRatehawkPublicSearchGuardPayload({
  env,
  warnings = [],
  source = "ratehawk",
} = {}) {
  const nextWarnings = Array.isArray(warnings) ? [...warnings] : [];
  const config = resolveRatehawkConfig(env);
  _pushUnique(nextWarnings, "ratehawk_invocation_blocked");
  if (config.reasons.includes("environment_host_mismatch")) {
    _pushUnique(nextWarnings, "ratehawk_environment_host_mismatch");
  } else if (config.reasons.includes("unapproved_host")) {
    _pushUnique(nextWarnings, "ratehawk_unapproved_host");
  } else if (!config.configured) {
    _pushUnique(nextWarnings, "provider_not_configured");
  } else if (!config.enabled) {
    _pushUnique(nextWarnings, "ratehawk_disabled");
  } else {
    _pushUnique(nextWarnings, "ratehawk_search_not_implemented");
  }
  const normalizedSource = isRatehawkSearchSource(source)
    ? "ratehawk"
    : _trim(source, 64) || "ratehawk";
  return {
    ok: true,
    source: normalizedSource,
    provider: RATEHAWK_PROVIDER,
    count: 0,
    stays: [],
    warnings: nextWarnings,
    ratehawk: {
      invocation_allowed: false,
      connected: false,
      status: buildSafeRatehawkProviderStatus(env).status,
    },
  };
}

function _authMaterial(env) {
  return {
    keyId: _trim(env?.RATEHAWK_KEY_ID, 120),
    apiKey: _trim(env?.RATEHAWK_API_KEY, 800),
  };
}

function _basicAuthHeader(keyId, apiKey) {
  const raw = `${keyId}:${apiKey}`;
  const token =
    typeof btoa === "function"
      ? btoa(raw)
      : Buffer.from(raw, "utf8").toString("base64");
  return `Basic ${token}`;
}

function _isAbortError(err) {
  const name = String(err?.name || "");
  const message = String(err?.message || "").toLowerCase();
  return name === "AbortError" || message.includes("abort");
}

function _allowlistedProviderError(raw) {
  const code = _trim(raw, 80).toLowerCase();
  if (!code) return "provider_error";
  return PROVIDER_ERROR_CODES.includes(code) ? code : "provider_error";
}

function _emptyConnectivity({ config, status, reason, invoked = false }) {
  return {
    ok: false,
    provider: RATEHAWK_PROVIDER,
    probe: "overview",
    invoked: invoked === true,
    environment: config?.environment || null,
    host: config?.host || null,
    status,
    reason,
    http_status: null,
    endpoint_count: null,
    connected: false,
  };
}

function _reachableStatus(environment) {
  if (environment === "sandbox") return "sandbox_environment_reachable";
  if (environment === "test") return "test_environment_reachable";
  if (environment === "production") return "production_environment_reachable";
  return "provider_reachable";
}

/**
 * Environment-gated GET /api/b2b/v3/overview/.
 *
 * Never fires transport when config is missing, mismatched, disabled, or
 * the operation is not allowlisted. Prefer an injected `fetchImpl` so tests
 * stay deterministic; global fetch is used only after every gate passes.
 */
export async function probeRatehawkOverview({
  env,
  fetchImpl = null,
  timeoutMs = null,
} = {}) {
  const config = resolveRatehawkConfig(env);
  if (!isRatehawkOperationAllowed(env, "overview")) {
    const status = buildSafeRatehawkProviderStatus(env).status;
    return _emptyConnectivity({
      config,
      status,
      reason: config.reasons[0] || "disabled",
      invoked: false,
    });
  }

  const fetchFn =
    typeof fetchImpl === "function"
      ? fetchImpl
      : typeof fetch === "function"
        ? fetch
        : null;
  if (!fetchFn) {
    return _emptyConnectivity({
      config,
      status: "transport_unavailable",
      reason: "transport_unavailable",
      invoked: false,
    });
  }

  const { keyId, apiKey } = _authMaterial(env);
  if (!keyId || !apiKey) {
    return _emptyConnectivity({
      config,
      status: "provider_not_configured",
      reason: "missing_configuration",
      invoked: false,
    });
  }

  const url = `${config.base_url}${RATEHAWK_OVERVIEW_PATH}`;
  const effectiveTimeout = _clampTimeoutMs(
    timeoutMs ?? config.timeout_ms,
    config.timeout_ms,
  );
  const controller =
    typeof AbortController === "function" ? new AbortController() : null;
  const timer =
    controller && typeof setTimeout === "function"
      ? setTimeout(() => controller.abort(), effectiveTimeout)
      : null;

  try {
    const response = await fetchFn(url, {
      method: "GET",
      headers: {
        Accept: "application/json",
        Authorization: _basicAuthHeader(keyId, apiKey),
      },
      signal: controller?.signal,
    });
    const httpStatus = Number(response?.status || 0);
    if (httpStatus === 429) {
      return {
        ..._emptyConnectivity({
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
        ..._emptyConnectivity({
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
        ..._emptyConnectivity({
          config,
          status: "provider_malformed_response",
          reason: "provider_malformed_response",
          invoked: true,
        }),
        http_status: httpStatus,
      };
    }

    const etgStatus = _trim(payload?.status, 24).toLowerCase();
    const etgError = _allowlistedProviderError(payload?.error);
    if (etgStatus !== "ok") {
      return {
        ..._emptyConnectivity({
          config,
          status: "provider_error",
          reason: payload?.error ? etgError : "provider_error",
          invoked: true,
        }),
        http_status: httpStatus,
      };
    }

    const data = payload?.data;
    const endpointCount = Array.isArray(data) ? data.length : 0;
    const reachable = _reachableStatus(config.environment);
    return {
      ok: true,
      provider: RATEHAWK_PROVIDER,
      probe: "overview",
      invoked: true,
      environment: config.environment,
      host: config.host,
      status: reachable,
      reason: null,
      http_status: httpStatus,
      endpoint_count: endpointCount,
      // Fail-closed LIVE claim: only production + production gate + probe ok.
      connected:
        config.environment === "production" &&
        config.production_enabled === true,
    };
  } catch (err) {
    if (_isAbortError(err)) {
      return _emptyConnectivity({
        config,
        status: "timeout",
        reason: "timeout",
        invoked: true,
      });
    }
    return _emptyConnectivity({
      config,
      status: "provider_fetch_failed",
      reason: "provider_fetch_failed",
      invoked: true,
    });
  } finally {
    if (timer) clearTimeout(timer);
  }
}
