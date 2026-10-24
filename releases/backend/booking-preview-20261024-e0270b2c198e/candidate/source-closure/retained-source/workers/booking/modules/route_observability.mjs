// Allowlisted route metrics. No URL, coordinates, booking/customer/driver IDs or error text.
const operations = new Set(['planner','auto_candidate','next_leg','active_ride_forecast','reassignment_retry','customer_live_eta']);
const profiles = new Set(['mapbox/driving','mapbox/driving-traffic']);
import { emitTenantCostMetric } from './tenant_cost_metrics.mjs';
const scopeHashes = new Map();
async function digest(value) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('').slice(0, 24);
}
export async function emitRouteMetric(env, context = {}, result = {}) {
  if (env?.TENANT_COST_METRICS_ENABLED === '1') {
    await emitTenantCostMetric(env, context.scope, result.provider_request === false ? `cache_${result.cache}` : 'provider_calls');
    if (result.provider_request !== false && operations.has(context.operation)) await emitTenantCostMetric(env, context.scope, context.operation);
  }
  if (env?.ROUTE_METRICS_ENABLED !== '1') return;
  const configured = Number(env.ROUTE_METRICS_SAMPLE_RATE ?? 1);
  const rate = Number.isFinite(configured) ? Math.min(1, Math.max(0, configured)) : 1;
  if (rate === 0 || Math.random() >= rate) return;
  try {
    const scope = context.scope || {};
    const tenant = String(scope.tenant_id || ''), company = String(scope.company_id || '');
    const key = JSON.stringify([tenant,company]);
    let hashes = scopeHashes.get(key);
    if (!hashes) {
      hashes = { tenant_hash: tenant ? await digest(`tenant:${tenant}`) : null,
        company_hash: company ? await digest(`company:${key}`) : null };
      if (scopeHashes.size >= 256) scopeHashes.delete(scopeHashes.keys().next().value);
      scopeHashes.set(key, hashes);
    }
    const record = { event: 'route_metric_v1', ...hashes,
      operation: operations.has(context.operation) ? context.operation : 'unclassified',
      source: operations.has(context.source) ? context.source : (operations.has(context.operation) ? context.operation : 'unclassified'),
      profile: profiles.has(context.profile) ? context.profile : 'unknown',
      cache: ['hit','miss','joined','bypass'].includes(result.cache) ? result.cache : 'miss',
      provider_request: result.provider_request !== false,
      success: result.success === true,
      http_status: Number.isInteger(result.http_status) && result.http_status >= 100 && result.http_status <= 599 ? result.http_status : null,
      elapsed_ms: Math.max(0, Math.round(Number(result.elapsed_ms) || 0)),
      eligible_candidates: Number.isSafeInteger(context.eligible_candidates) && context.eligible_candidates >= 0 ? context.eligible_candidates : null,
      retry_attempt: Number.isSafeInteger(context.retry_attempt) && context.retry_attempt >= 0 ? context.retry_attempt : 0,
      sample_rate: rate,
    };
    if (typeof env.__routeMetricSink === 'function') await env.__routeMetricSink(record);
    else if (env.TENANT_COST_METRICS_ENABLED !== '1') console.log(`[ROUTE_METRICS] ${JSON.stringify(record)}`);
  } catch { /* metrics must never alter the route response/error */ }
}

export async function measureRouteCall(env, context, run) {
  const start = performance.now();
  let httpStatus = null, success = false, providerRequest = true;
  try {
    const value = await run(status => { httpStatus = status; });
    success = true;
    return value;
  } catch (error) {
    if (error?.providerRequestMade === false) providerRequest = false;
    throw error;
  } finally {
    await emitRouteMetric(env, context, { success, http_status: httpStatus,
      elapsed_ms: performance.now() - start, provider_request: providerRequest, cache: providerRequest ? 'miss' : 'bypass' });
  }
}
