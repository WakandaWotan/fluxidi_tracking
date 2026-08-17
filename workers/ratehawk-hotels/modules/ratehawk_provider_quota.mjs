/**
 * Endpoint-specific RateHawk provider quota (P2 foundation).
 *
 * Global allowance is coordinated by a Durable Object with transactional
 * storage. This is not the public per-client BOOKING_KV abuse limiter.
 * Production quotas must be explicit. Test/sandbox may use the documented
 * test-account endpoint ceilings. Company IDs and key IDs are never
 * hardcoded.
 *
 * This module does not call RateHawk.
 */

import { envFlag } from "./parsing_utils.js";

export const RATEHAWK_QUOTA_ENDPOINTS = Object.freeze({
  HOTELPAGE: "hotelpage",
  SERP: "serp",
});

export const RATEHAWK_TEST_ACCOUNT_QUOTAS = Object.freeze({
  hotelpage: Object.freeze({ limit: 5, window_seconds: 60 }),
  serp: Object.freeze({ limit: 15, window_seconds: 60 }),
});

function _trim(value, max = 200) {
  const text = String(value ?? "").trim();
  if (!text) return "";
  return text.length > max ? text.slice(0, max) : text;
}

function _int(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.trunc(n);
}

function _environment(env) {
  return _trim(env?.RATEHAWK_ENVIRONMENT, 32).toLowerCase();
}

function _readQuota(env, endpoint, fallback) {
  const prefix =
    endpoint === RATEHAWK_QUOTA_ENDPOINTS.HOTELPAGE
      ? "RATEHAWK_QUOTA_HOTELPAGE"
      : "RATEHAWK_QUOTA_SERP";
  const limit = _int(env?.[`${prefix}_LIMIT`]);
  const windowSeconds = _int(env?.[`${prefix}_WINDOW_SECONDS`]);
  if (limit == null && windowSeconds == null) {
    return fallback ? { ...fallback, source: "test_account_default" } : null;
  }
  if (limit == null || limit < 1 || windowSeconds == null || windowSeconds < 1) {
    return { ok: false, reason: "quota_config_invalid", endpoint };
  }
  return { limit, window_seconds: windowSeconds, source: "explicit" };
}

export function resolveRatehawkProviderQuotaConfig(env = {}) {
  const environment = _environment(env);
  const production = environment === "production";
  const fallback = production ? null : RATEHAWK_TEST_ACCOUNT_QUOTAS;
  const hotelpage = _readQuota(
    env,
    RATEHAWK_QUOTA_ENDPOINTS.HOTELPAGE,
    fallback?.hotelpage,
  );
  const serp = _readQuota(env, RATEHAWK_QUOTA_ENDPOINTS.SERP, fallback?.serp);
  if (hotelpage?.ok === false) return hotelpage;
  if (serp?.ok === false) return serp;
  if (!hotelpage || !serp) {
    return {
      ok: false,
      reason: production
        ? "production_quota_unconfigured"
        : "quota_config_missing",
      environment,
      endpoints: {},
    };
  }
  return {
    ok: true,
    reason: null,
    environment: environment || null,
    production,
    endpoints: {
      hotelpage,
      serp,
    },
  };
}

export function createMemoryDurableStorage() {
  const data = new Map();
  const storage = {
    async get(key) {
      return data.has(key) ? data.get(key) : undefined;
    },
    async put(key, value) {
      data.set(key, value);
    },
    async transaction(fn) {
      return fn(storage);
    },
  };
  return storage;
}

export class RatehawkProviderQuotaDO {
  constructor(stateOrCtx, env) {
    this.state = stateOrCtx;
    this.env = env;
  }

  async fetch(request) {
    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }
    const action = _trim(body?.action, 40).toLowerCase();
    if (action === "consume") return this._consume(body);
    if (action === "status") return this._status(body);
    return this._json({ ok: false, reason: "unknown_action" }, 400);
  }

  async _consume(body) {
    const endpoint = _trim(body?.endpoint, 40).toLowerCase();
    if (
      endpoint !== RATEHAWK_QUOTA_ENDPOINTS.HOTELPAGE &&
      endpoint !== RATEHAWK_QUOTA_ENDPOINTS.SERP
    ) {
      return this._json({ ok: false, allowed: false, reason: "quota_endpoint_unknown" });
    }
    const limit = _int(body?.limit);
    const windowSeconds = _int(body?.window_seconds);
    if (limit == null || limit < 1 || windowSeconds == null || windowSeconds < 1) {
      return this._json({
        ok: false,
        allowed: false,
        reason: "quota_config_invalid",
      });
    }
    const now = Number(body?.now);
    const nowMs = Number.isFinite(now) ? now : Date.now();
    const windowMs = windowSeconds * 1000;
    const result = await this.state.storage.transaction(async (txn) => {
      const key = `stamps:${endpoint}`;
      const raw = (await txn.get(key)) || [];
      const stamps = Array.isArray(raw) ? raw.map((n) => Number(n)).filter(Number.isFinite) : [];
      const active = stamps.filter((stamp) => stamp > nowMs - windowMs);
      if (active.length >= limit) {
        const oldest = Math.min(...active);
        const retryAfter = Math.max(1, Math.ceil((oldest + windowMs - nowMs) / 1000));
        return {
          allowed: false,
          remaining: 0,
          retry_after: retryAfter,
          count: active.length,
        };
      }
      active.push(nowMs);
      await txn.put(key, active);
      return {
        allowed: true,
        remaining: Math.max(0, limit - active.length),
        retry_after: null,
        count: active.length,
      };
    });
    return this._json({
      ok: result.allowed === true,
      allowed: result.allowed === true,
      reason: result.allowed ? null : "provider_quota_exhausted",
      retryable: result.allowed !== true,
      endpoint,
      ...result,
    });
  }

  async _status(body) {
    const endpoint = _trim(body?.endpoint, 40).toLowerCase();
    const stamps = (await this.state.storage.get(`stamps:${endpoint}`)) || [];
    return this._json({
      ok: true,
      endpoint,
      count: Array.isArray(stamps) ? stamps.length : 0,
    });
  }

  _json(obj, status = 200) {
    return new Response(JSON.stringify(obj), {
      status,
      headers: { "content-type": "application/json; charset=utf-8" },
    });
  }
}

export const RATEHAWK_PROVIDER_QUOTA_INSTANCE = "global";

export function createRatehawkQuotaBinding(storage = createMemoryDurableStorage(), env = {}) {
  const durable = new RatehawkProviderQuotaDO({ storage }, env);
  let chain = Promise.resolve();
  const originalFetch = durable.fetch.bind(durable);
  durable.fetch = (request) => {
    const run = chain.then(() => originalFetch(request));
    chain = run.then(
      () => undefined,
      () => undefined,
    );
    return run;
  };
  return {
    idFromName(name) {
      return { name: String(name || RATEHAWK_PROVIDER_QUOTA_INSTANCE) };
    },
    get() {
      return durable;
    },
  };
}

function _quotaStub(env) {
  const binding = env?.RATEHAWK_PROVIDER_QUOTA;
  if (!binding) return null;
  if (typeof binding.idFromName === "function" && typeof binding.get === "function") {
    return binding.get(binding.idFromName(RATEHAWK_PROVIDER_QUOTA_INSTANCE));
  }
  if (typeof binding.fetch === "function") {
    return binding;
  }
  return null;
}

export async function reserveRatehawkProviderQuota({
  env,
  endpoint,
  now = Date.now(),
} = {}) {
  const config = resolveRatehawkProviderQuotaConfig(env);
  if (config.ok !== true) {
    return {
      ok: false,
      allowed: false,
      invoked: false,
      reason: config.reason,
      retryable: true,
      retry_after: null,
      endpoint: endpoint || null,
    };
  }
  const spec = config.endpoints[endpoint];
  if (!spec) {
    return {
      ok: false,
      allowed: false,
      invoked: false,
      reason: "quota_endpoint_unknown",
      retryable: true,
      retry_after: null,
      endpoint,
    };
  }
  const stub = _quotaStub(env);
  if (!stub || typeof stub.fetch !== "function") {
    return {
      ok: false,
      allowed: false,
      invoked: false,
      reason: "quota_coordinator_missing",
      retryable: true,
      retry_after: null,
      endpoint,
    };
  }
  const resp = await stub.fetch(
    new Request("https://ratehawk-provider-quota.internal/consume", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        action: "consume",
        endpoint,
        limit: spec.limit,
        window_seconds: spec.window_seconds,
        now,
      }),
    }),
  );
  const payload = await resp.json();
  return {
    ok: payload?.allowed === true,
    allowed: payload?.allowed === true,
    invoked: false,
    reason: payload?.reason || (payload?.allowed ? null : "provider_quota_exhausted"),
    retryable: payload?.allowed !== true,
    retry_after: payload?.retry_after ?? null,
    remaining: payload?.remaining ?? null,
    endpoint,
  };
}

export function envFlagOn(env, name) {
  return envFlag(env?.[name]);
}
