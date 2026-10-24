import { _requireAdmin } from './auth_scope.js';
import {readSubscriptionProfileSource} from './subscription_profile_source.mjs';

const SAAS_DIAGNOSTIC_PROFILE_LIMIT = 65_536;
const SAAS_DIAGNOSTIC_PROVIDER_LIMIT = 32_768;
const SAAS_DIAGNOSTIC_TIMEOUT_MS = 3_500;
const SAAS_DIAGNOSTIC_SCOPE = /^[A-Za-z0-9_-]{1,80}$/;
const SAAS_DIAGNOSTIC_CUSTOMER = /^cst_[A-Za-z0-9]{1,64}$/;
const SAAS_DIAGNOSTIC_SUBSCRIPTION = /^sub_[A-Za-z0-9]{1,64}$/;

function saasDiagnosticResponse(payload, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'private, no-store',
      'Pragma': 'no-cache',
      'Vary': 'Authorization, X-Admin-Token',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

function saasDiagnosticFailure(error, status, extra = {}) {
  return saasDiagnosticResponse({ ok: false, read_only: true, error, ...extra }, status);
}

function saasDiagnosticObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function saasDiagnosticCents(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function saasDiagnosticQuantity(value) {
  return Number.isSafeInteger(value) && value >= 0 && value <= 10_000 ? value : null;
}

function saasDiagnosticEnum(value, allowed) {
  return typeof value === 'string' && allowed.includes(value) ? value : null;
}

function saasDiagnosticCurrency(value) {
  return typeof value === 'string' && /^[A-Z]{3}$/.test(value) ? value : null;
}

function saasDiagnosticProfile(profile) {
  const vehicles = saasDiagnosticQuantity(profile.extra_vehicle_active_quantity);
  const drivers = saasDiagnosticQuantity(profile.extra_driver_active_quantity);
  const base = saasDiagnosticCents(profile.locked_price_cents);
  const vehicleUnit = saasDiagnosticCents(profile.locked_extra_vehicle_unit_cents);
  const driverUnit = saasDiagnosticCents(profile.locked_extra_driver_unit_cents);
  return {
    plan_code: saasDiagnosticEnum(profile.plan_code, ['fluxidi_pro', 'starter', 'standard', 'smart', 'fluxidi_standard', 'fluxidi_smart']),
    market: typeof profile.market === 'string' && /^[A-Z]{2}$/.test(profile.market) ? profile.market : null,
    status: saasDiagnosticEnum(profile.subscription_status ?? profile.status, ['trialing', 'payment_required', 'active', 'past_due', 'suspended', 'cancelled', 'canceled', 'inactive', 'pending', 'incomplete']),
    currency: saasDiagnosticCurrency(profile.currency),
    recurring_currency: saasDiagnosticCurrency(profile.recurring_currency),
    normal_price_cents: saasDiagnosticCents(profile.normal_price_cents),
    founder_price_cents: saasDiagnosticCents(profile.founder_price_cents),
    is_founder_customer: typeof profile.is_founder_customer === 'boolean' ? profile.is_founder_customer : null,
    locked_price_cents: base,
    locked_extra_vehicle_unit_cents: vehicleUnit,
    locked_extra_driver_unit_cents: driverUnit,
    locked_total_recurring_cents: saasDiagnosticCents(profile.locked_total_recurring_cents),
    recurring_amount_cents: saasDiagnosticCents(profile.recurring_amount_cents),
    recurring_total_vat_cents: saasDiagnosticCents(profile.recurring_total_vat_cents),
    recurring_total_incl_vat_cents: saasDiagnosticCents(profile.recurring_total_incl_vat_cents),
    extra_vehicle_active_quantity: vehicles,
    extra_driver_active_quantity: drivers,
    price_locks_complete: base !== null && base > 0 && vehicles !== null && drivers !== null
      && (vehicles === 0 || (vehicleUnit !== null && vehicleUnit > 0))
      && (drivers === 0 || (driverUnit !== null && driverUnit > 0)),
  };
}

function saasDiagnosticConfig(env) {
  // Intentionally reads only the dedicated SaaS key. No ride/Connect fallback.
  const key = env?.FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY;
  if (typeof key !== 'string' || !/^(live|test)_[A-Za-z0-9]{1,128}$/.test(key)) {
    return { ok: false, error: 'subscription_provider_credential_unavailable' };
  }
  const credentialMode = key.startsWith('live_') ? 'live' : 'test';
  const configuredMode = saasDiagnosticEnum(env?.FLUXIDI_SUBSCRIPTION_MOLLIE_MODE, ['live', 'test']);
  return { ok: true, key, credentialMode, configuredMode };
}

function saasDiagnosticFetchFailureKind(error, timedOut) {
  if (timedOut) return 'timeout';
  // Fixed categories only: never echo provider/runtime exception text or cause.
  const message = error instanceof Error ? error.message : '';
  if (message === 'Illegal invocation') return 'fetch_receiver';
  if (message.startsWith('Invalid redirect value, must be one of "follow" or "manual"')) return 'fetch_redirect_mode';
  if (/^(?:Cannot|Can't) perform I\/O on behalf of a different request\./.test(message)
    || message.startsWith('Disallowed operation called within global scope.')) return 'fetch_context';
  return 'network';
}

async function saasDiagnosticProviderGet(url, config, fetchImpl, timeoutMs) {
  const controller = new AbortController();
  let timer;
  let reader;
  let timedOut = false;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => {
      timedOut = true;
      controller.abort();
      reject(new Error('timeout'));
    }, timeoutMs);
  });
  try {
    return await Promise.race([
      (async () => {
        const response = await fetchImpl(url, {
          method: 'GET',
          // Workers supports manual/follow only. Reject every 3xx below, with
          // no follow-up request that could send the credential to a new host.
          redirect: 'manual',
          signal: controller.signal,
          headers: { Authorization: `Bearer ${config.key}`, Accept: 'application/json' },
        });
        if (!response.ok) return { ok: false, error: 'provider_http_error', status: response.status };
        const declaredSize = Number(response.headers.get('Content-Length'));
        if (declaredSize > SAAS_DIAGNOSTIC_PROVIDER_LIMIT || response.redirected) {
          return { ok: false, error: 'provider_response_invalid', status: response.status };
        }
        const contentType = response.headers.get('Content-Type') ?? '';
        if (!/^(application\/json|application\/hal\+json)(?:\s*;|$)/i.test(contentType) || !response.body) {
          return { ok: false, error: 'provider_response_invalid', status: response.status };
        }
        reader = response.body.getReader();
        const decoder = new TextDecoder();
        let body = '';
        let size = 0;
        while (true) {
          const chunk = await reader.read();
          if (chunk.done) break;
          size += chunk.value.byteLength;
          if (size > SAAS_DIAGNOSTIC_PROVIDER_LIMIT) {
            void reader.cancel().catch(() => {});
            return { ok: false, error: 'provider_response_too_large', status: response.status };
          }
          body += decoder.decode(chunk.value, { stream: true });
        }
        body += decoder.decode();
        try {
          const data = JSON.parse(body);
          return saasDiagnosticObject(data)
            ? { ok: true, data }
            : { ok: false, error: 'provider_response_invalid', status: response.status };
        } catch {
          return { ok: false, error: 'provider_response_invalid', status: response.status };
        }
      })(),
      timeout,
    ]);
  } catch (error) {
    return {
      ok: false,
      error: timedOut ? 'provider_timeout' : 'provider_network_error',
      failureKind: saasDiagnosticFetchFailureKind(error, timedOut),
    };
  } finally {
    clearTimeout(timer);
    if (timedOut && reader) void reader.cancel().catch(() => {});
  }
}

function saasDiagnosticProviderFailure(result, resource) {
  return saasDiagnosticFailure(result.error, result.status === 429 ? 503 : 502, {
    provider_resource: resource,
    ...(Number.isInteger(result.status) ? { upstream_status: result.status } : {}),
    ...(['fetch_receiver', 'fetch_redirect_mode', 'fetch_context', 'network', 'timeout'].includes(result.failureKind)
      ? { failure_kind: result.failureKind } : {}),
  });
}

function saasDiagnosticAmount(amount) {
  if (!saasDiagnosticObject(amount) || !saasDiagnosticCurrency(amount.currency)
    || typeof amount.value !== 'string' || !/^\d{1,10}\.\d{2}$/.test(amount.value)) return null;
  const [units, decimals] = amount.value.split('.');
  const cents = Number(units) * 100 + Number(decimals);
  return Number.isSafeInteger(cents) ? { currency: amount.currency, cents } : null;
}

/**
 * Admin-only diagnostic: exactly one raw scoped KV read and at most two fixed
 * Mollie GETs. No subscription normalizer/materializer or mutation helper.
 * Dependencies are injectable only for local fixtures, never from a request.
 */
export async function handleAdminSubscriptionProviderDiagnostic(request, env, {
  fetchImpl = (input, init) => globalThis.fetch(input, init),
  timeoutMs = SAAS_DIAGNOSTIC_TIMEOUT_MS,
} = {}) {
  const url = new URL(request.url);
  if (typeof env?.ADMIN_TOKEN !== 'string' || !env.ADMIN_TOKEN.trim()) {
    return saasDiagnosticFailure('admin_auth_unavailable', 503);
  }
  try { _requireAdmin(request, url, env); } catch { return saasDiagnosticFailure('unauthorized', 401); }
  const auth = request.headers.get('Authorization');
  const adminHeader = request.headers.get('X-Admin-Token');
  if ((auth && !/^Bearer [^\s,]+$/i.test(auth))
    || (auth && adminHeader && auth.slice(7) !== adminHeader)) {
    return saasDiagnosticFailure('unauthorized', 401);
  }
  if (request.method !== 'GET') return saasDiagnosticFailure('method_not_allowed', 405);

  const allowedKeys = new Set(['tenant_id', 'company_id']);
  for (const key of url.searchParams.keys()) {
    if (!allowedKeys.has(key) || url.searchParams.getAll(key).length !== 1) {
      return saasDiagnosticFailure('invalid_scope_query', 400);
    }
  }
  const tenant = url.searchParams.get('tenant_id');
  const company = url.searchParams.get('company_id');
  if (!tenant || !company || !SAAS_DIAGNOSTIC_SCOPE.test(tenant) || !SAAS_DIAGNOSTIC_SCOPE.test(company)) {
    return saasDiagnosticFailure('invalid_scope_query', 400);
  }
  for (const [name, expected] of [['X-Tenant-Id', tenant], ['X-Tenant', tenant], ['X-Company-Id', company], ['X-Company', company]]) {
    const supplied = request.headers.get(name);
    if (supplied !== null && supplied !== expected) return saasDiagnosticFailure('scope_conflict', 400);
  }
  if (!env?.BOOKING_KV?.get) return saasDiagnosticFailure('subscription_store_unavailable', 503);
  let raw;
  try {
    raw = env.FLUXIDI_SUBSCRIPTION_PROFILE_AUTHORITY_ENABLED==='1'
      ? JSON.stringify(await readSubscriptionProfileSource(env,{tenant_id:tenant,company_id:company},()=>{throw Error('legacy_fallback_forbidden');}))
      : await env.BOOKING_KV.get(`tenant:${tenant}:company:${company}:subscription:v1`, { type: 'text' });
  } catch {
    return saasDiagnosticFailure('subscription_store_unavailable', 503);
  }
  if (raw === null || raw === undefined) return saasDiagnosticFailure('subscription_profile_not_found', 404);
  if (typeof raw !== 'string' || raw.length > SAAS_DIAGNOSTIC_PROFILE_LIMIT
    || new TextEncoder().encode(raw).byteLength > SAAS_DIAGNOSTIC_PROFILE_LIMIT) {
    return saasDiagnosticFailure('subscription_profile_invalid', 422);
  }
  let profile;
  try {
    const record = JSON.parse(raw);
    profile = saasDiagnosticObject(record) ? (record.subscription_profile ?? record) : null;
  } catch { return saasDiagnosticFailure('subscription_profile_invalid', 422); }
  if (!saasDiagnosticObject(profile)) return saasDiagnosticFailure('subscription_profile_invalid', 422);
  if (profile.tenant_id !== tenant || profile.company_id !== company) {
    return saasDiagnosticFailure('subscription_profile_scope_mismatch', 422);
  }
  const saved = saasDiagnosticProfile(profile);
  const customerId = profile.provider_customer_id;
  const subscriptionId = profile.provider_subscription_id;
  const customerPresent = customerId !== null && customerId !== undefined && customerId !== '';
  const subscriptionPresent = subscriptionId !== null && subscriptionId !== undefined && subscriptionId !== '';
  const base = {
    ok: true,
    read_only: true,
    scope_matches: true,
    saved_profile: saved,
    provider_references: { customer_present: customerPresent, subscription_present: subscriptionPresent },
  };
  if (!customerPresent || !subscriptionPresent) {
    return saasDiagnosticResponse({ ...base, provider: null, amount_parity: 'unknown', reason: 'provider_references_incomplete' });
  }
  if (typeof customerId !== 'string' || !SAAS_DIAGNOSTIC_CUSTOMER.test(customerId)
    || typeof subscriptionId !== 'string' || !SAAS_DIAGNOSTIC_SUBSCRIPTION.test(subscriptionId)) {
    return saasDiagnosticFailure('saved_provider_references_invalid', 422);
  }
  const config = saasDiagnosticConfig(env);
  if (!config.ok) return saasDiagnosticFailure(config.error, 503);
  const boundedTimeout = Number.isInteger(timeoutMs) && timeoutMs > 0
    ? Math.min(timeoutMs, SAAS_DIAGNOSTIC_TIMEOUT_MS) : SAAS_DIAGNOSTIC_TIMEOUT_MS;
  const customerUrl = `https://api.mollie.com/v2/customers/${customerId}`;
  const customer = await saasDiagnosticProviderGet(customerUrl, config, fetchImpl, boundedTimeout);
  if (!customer.ok) return saasDiagnosticProviderFailure(customer, 'customer');
  if (customer.data.resource !== 'customer' || customer.data.id !== customerId
    || customer.data.mode !== config.credentialMode) return saasDiagnosticFailure('provider_customer_identity_invalid', 502);

  const subscription = await saasDiagnosticProviderGet(`${customerUrl}/subscriptions/${subscriptionId}`, config, fetchImpl, boundedTimeout);
  if (!subscription.ok) return saasDiagnosticProviderFailure(subscription, 'subscription');
  const data = subscription.data;
  const status = saasDiagnosticEnum(data.status, ['pending', 'active', 'canceled', 'suspended', 'completed']);
  const amount = saasDiagnosticAmount(data.amount);
  if (data.resource !== 'subscription' || data.id !== subscriptionId || data.mode !== config.credentialMode
    || (data.customerId !== undefined && data.customerId !== customerId)
    || (data._links?.customer?.href !== undefined && data._links.customer.href !== customerUrl)
    || !status || !amount) return saasDiagnosticFailure('provider_subscription_identity_invalid', 502);

  const storedCurrency = saved.recurring_currency ?? saved.currency;
  const currenciesConflict = saved.recurring_currency !== null && saved.currency !== null
    && saved.recurring_currency !== saved.currency;
  const currencyMatches = !currenciesConflict && storedCurrency !== null ? amount.currency === storedCurrency : null;
  const amountMatches = currencyMatches !== null && saved.recurring_amount_cents !== null
    ? currencyMatches && amount.cents === saved.recurring_amount_cents : null;
  return saasDiagnosticResponse({
    ...base,
    provider: {
      customer_verified: true,
      subscription_verified: true,
      credential_mode: config.credentialMode,
      configured_mode: config.configuredMode,
      configured_mode_matches: config.configuredMode === null ? null : config.configuredMode === config.credentialMode,
      mode: data.mode,
      status,
      amount_cents: amount.cents,
      currency: amount.currency,
    },
    comparison: { currency_matches: currencyMatches, amount_matches_stored_recurring: amountMatches },
    amount_parity: amountMatches === null ? 'unknown' : amountMatches ? 'match' : 'mismatch',
  });
}
