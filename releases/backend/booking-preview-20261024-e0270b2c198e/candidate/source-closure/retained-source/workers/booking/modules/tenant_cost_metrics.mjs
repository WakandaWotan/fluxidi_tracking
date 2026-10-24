// Bounded, allowlisted local aggregates. A downstream metrics sink may export
// these to an existing collector; these are never invoices or exact CF CPU.
const allowed = new Set(['active_drivers','online_drivers','online_driver_seconds','trips','planner','auto_candidate','next_leg',
  'active_ride_forecast','customer_live_eta','reassignment_retry','provider_calls','cache_hit','cache_miss','cache_joined',
  'workers_requests','kv_reads','kv_writes','kv_lists','kv_deletes','do_requests','storage_reads','storage_writes','storage_bytes',
  'prepare_ms','commit_ms','queue_ms','dispatch_ms','candidate_initial','candidate_active','candidate_cheap','candidate_expansions',
  'candidate_pruned','candidate_evaluated','preparation_shared','preparation_loaded']);
const rows = new Map(), hashCache = new Map();
const buckets = [1,5,10,25,50,100,250,500,1000,2000,3000,5000,10000,30000,60000,Infinity];
async function scopeHash(scope) {
  const value = JSON.stringify([scope?.tenant_id, scope?.company_id]);
  if (!scope?.tenant_id || !scope?.company_id) return null;
  if (!hashCache.has(value)) {
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
    if (hashCache.size >= 128) hashCache.delete(hashCache.keys().next().value);
    hashCache.set(value,[...new Uint8Array(digest)].map(v=>v.toString(16).padStart(2,'0')).join('').slice(0,24));
  }
  return hashCache.get(value);
}
export async function emitTenantCostMetric(env, scope, name, value = 1) {
  if (env?.TENANT_COST_METRICS_ENABLED !== '1' || !allowed.has(name) || !Number.isFinite(value) || value < 0) return;
  try {
    const hash = await scopeHash(scope); if (!hash) return;
    const minute = Math.floor(Date.now()/60000), key = hash + ':' + minute;
    for (const [old, row] of rows) if (row.minute < minute - 4) rows.delete(old);
    if (!rows.has(key)) {
      if (rows.size >= 128) rows.delete(rows.keys().next().value);
      rows.set(key,{company_scope_hash:hash,minute,counters:{},latency:{}});
    }
    const row = rows.get(key);
    if (name.endsWith('_ms')) {
      const histogram = row.latency[name] ||= Array(buckets.length).fill(0);
      histogram[buckets.findIndex(limit=>value<=limit)]++;
    } else if (name === 'active_drivers' || name === 'online_drivers') row.counters[name]=value;
    else row.counters[name]=(row.counters[name]||0)+value;
    if (typeof env.__tenantCostMetricSink === 'function') await env.__tenantCostMetricSink({company_scope_hash:hash,minute,name,value});
  } catch { /* bounded diagnostics never authorize or alter business writes */ }
}
export async function tenantCostSnapshot(scope) {
  const hash=await scopeHash(scope);
  return [...rows.values()].filter(row=>row.company_scope_hash===hash).map(row=>structuredClone(row));
}

const metered = Symbol('tenantCostMetered');
const bindingWrappers = new WeakMap();
export function meterTenantBindings(env, scope) {
  if (env?.TENANT_COST_METRICS_ENABLED !== '1' || env[metered] || !scope?.tenant_id || !scope?.company_id) return env;
  const scopeKey = JSON.stringify([scope.tenant_id, scope.company_id]);
  let wrappers = bindingWrappers.get(env);
  if (!wrappers) { wrappers = new Map(); bindingWrappers.set(env, wrappers); }
  if (wrappers.has(scopeKey)) return wrappers.get(scopeKey);
  const result = { ...env, [metered]: true };
  for (const name of ['BOOKING_KV','FLUXIDI_TRACKING']) if (env[name]) result[name] = new Proxy(env[name], { get(target, property) {
    const value=Reflect.get(target,property);
    if (['get','getWithMetadata','put','delete','list'].includes(property) && typeof value==='function') return async(...args)=>{
      await emitTenantCostMetric(env,scope,property==='put'?'kv_writes':property==='delete'?'kv_deletes':property==='list'?'kv_lists':'kv_reads');
      return value.apply(target,args);
    };
    return typeof value==='function'?value.bind(target):value;
  }});
  for (const name of ['COMPANY_TRACKING','FLEET_ALLOCATOR','DRIVER_INDEX_COORDINATOR','CANONICAL_BOOKING_DIRECTORY']) if (env[name]) {
    result[name]=new Proxy(env[name],{get(target,property){
      const value=Reflect.get(target,property);
      if(property==='get')return(...args)=>{const stub=value.apply(target,args);return new Proxy(stub,{get(owner,key){
        const method=Reflect.get(owner,key);
        if(key==='fetch')return async(...input)=>{await emitTenantCostMetric(env,scope,'do_requests');return method.apply(owner,input);};
        return typeof method==='function'?method.bind(owner):method;
      }});};
      return typeof value==='function'?value.bind(target):value;
    }});
  }
  if (wrappers.size >= 128) wrappers.delete(wrappers.keys().next().value);
  wrappers.set(scopeKey, result);
  return result;
}
