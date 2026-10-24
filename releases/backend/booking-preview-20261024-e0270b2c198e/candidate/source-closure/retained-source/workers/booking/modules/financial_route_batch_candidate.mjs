// Request-owned financial routing only. No process-wide promise/cache, no
// operational ETA, no provider change and no financial quote identity sharing.
const slots = new WeakMap(), contexts = new WeakSet();
const slot = Symbol('financial-route-batch-v1');
const clone = value => structuredClone(value);
const canonical = value => JSON.stringify(value, (_, v) => v && typeof v === 'object' && !Array.isArray(v)
  ? Object.fromEntries(Object.keys(v).sort().map(k => [k,v[k]])) : v);
export function createFinancialRouteBatchV1({scope, inputs, deadlineMs=null}) {
  if (!scope?.tenant_id || !scope?.company_id) throw Error('financial_batch_scope_required');
  if(deadlineMs!==null&&!Number.isSafeInteger(deadlineMs))throw Error('financial_batch_deadline_invalid');
  const batch = {scope:clone(scope), inputs:clone(inputs), deadlineMs, routes:new Map(), pendingRoutes:new Map(), lookups:new Map(), attempts:0, hits:0,ownedAttempts:0,ownedHits:0,lookupAttempts:0,lookupHits:0};
  return Object.freeze({
    environment(env, vehicle) {
      // Unknown vehicle route dependencies never share a driving result. The
      // quote gateway separately refuses restrictions this provider cannot prove.
      const dependencies=Object.fromEntries(Object.entries(vehicle ?? {}).filter(([key]) =>
        /route|restriction|height|width|weight|length|access|depot|profile|emission/i.test(key)));
      const context={batch, dependencies}; contexts.add(context);
      const next={...env,[slot]:context}; slots.set(next,context); return next;
    },
    metrics(){return {provider_attempts:batch.attempts-batch.ownedAttempts,cache_hits:batch.hits,distinct_routes:batch.routes.size,
      lookup_attempts:batch.lookupAttempts,lookup_hits:batch.lookupHits,
      ...(batch.ownedAttempts?{own_route_calculations:batch.ownedAttempts,own_route_cache_hits:batch.ownedHits}:{})};},
  });
}
export function financialRouteBatchContextV1(env) { return slots.get(env) ?? null; }
export function assertFinancialBatchWriteBudgetV1(env){
  const context=slots.get(env);
  if(context&&contexts.has(context)&&context.batch.deadlineMs!==null&&Date.now()>=context.batch.deadlineMs)
    throw Error('calculation_budget_exceeded');
}
// Reuse only the existing request-owned bounded reader. Its private bucket is
// also the official index cache key, so a vehicle batch bootstraps one index
// instead of closing a new reader/counter over the same manifest per vehicle.
// Every actual miss remains charged to this shared request budget; no cache or
// mutable counter survives into another request, tenant or underlying binding.
export function financialRouteBatchR2BudgetV1({context,bucket,create}){
 if(!contexts.has(context))return create();
 const batch=context.batch;
 if(batch.r2Budget){if(batch.r2Bucket!==bucket)throw Error('financial_batch_bucket_changed');return batch.r2Budget;}
 const budget=create();
 if(typeof budget?.bucket?.get!=='function'||typeof budget.metrics!=='function')throw Error('financial_batch_budget_invalid');
 batch.r2Bucket=bucket;batch.r2Budget=budget;return budget;
}
export async function financialOwnedDirectionsInBatchV1({context,scope,policy,coords,identities,resolve,clock=Date.now}){
 if(!contexts.has(context))return resolve();
 const b=context.batch;
 if(scope?.tenant_id!==b.scope.tenant_id||scope?.company_id!==b.scope.company_id)throw Error('financial_batch_scope_changed');
 const key=canonical({scope:b.scope,inputs:b.inputs,dependencies:context.dependencies,
  source:'fluxidi-national',policy,coords,identities});
 const cached=b.routes.get(key),now=clock();
 if(cached&&cached.storedAt<=now&&cached.until>now){b.hits++;b.ownedHits++;return clone(cached.value);}
 if(cached)b.routes.delete(key);
 if(b.attempts>=32)throw Error('financial_route_batch_limit');
 b.attempts++;b.ownedAttempts++;const value=await resolve();
 // Keep the router's original short lease. Reuse never grants a new quote
 // identity or carries a route into another request/tenant/vehicle policy.
 if(value?.financial_route?.source!=='fluxidi-national'||value.financial_route.tenant_id!==scope.tenant_id||value.financial_route.company_id!==scope.company_id
  ||value.financial_route.policy_version!==policy?.version||value.financial_route.graph_checksum!==policy?.graphManifestSha256
  ||value.financial_route.source_version!==policy.graphVersion||value.financial_route.publication_sha256!==policy.publicationSha256
  ||value.financial_route.duration_policy_version!==policy.durationPolicyVersion||value.financial_route.acceptance_evidence_sha256!==policy.acceptanceEvidenceSha256
  ||!Number.isFinite(value.valid_until_ms)||value.valid_until_ms<=clock())throw Error('financial_owned_batch_evidence_unproven');
 b.routes.set(key,{storedAt:now,until:value.valid_until_ms,value:clone(value)});return value;
}
export async function financialMunicipalityInBatchV1({context,point,resolve}){
  if(!contexts.has(context))return resolve();
  const b=context.batch,key=canonical({scope:b.scope,source:'mapbox-geocoding/v5',
    point,lang:'nl',countryCode:null});
  if(b.lookups.has(key)){b.lookupHits++;return clone(b.lookups.get(key));}
  if(b.lookupAttempts>=32)throw Error('financial_lookup_batch_limit');
  b.lookupAttempts++;const result=await resolve();
  if(typeof result?.city==='string'&&result.city.trim())b.lookups.set(key,clone(result));
  return result;
}
export async function financialDirectionsInBatchV1({context,coords,options={},resolve}) {
  if (!contexts.has(context)) return resolve();
  const b=context.batch;
  // These are ALL current Directions parameters. No departure traffic is used
  // by this provider profile; requested journey dates/return context still bind.
  const key=canonical({scope:b.scope,inputs:b.inputs,dependencies:context.dependencies,
    source:'mapbox',source_version:'directions/v5',profile:'mapbox/driving',
    duration_basis:'provider_driving',overview:false,coords,radiuses:String(options.radiuses ?? '').trim()});
  if (b.routes.has(key)) {b.hits++; return clone(b.routes.get(key));}
  // Identical in-flight work is shared only inside this authenticated batch.
  // Each vehicle still creates and validates its own financial quote.
  if (b.pendingRoutes.has(key)) {b.hits++; return clone(await b.pendingRoutes.get(key));}
  if (b.attempts>=32) throw Error('financial_route_batch_limit');
  b.attempts++;
  const pending=Promise.resolve().then(resolve);
  b.pendingRoutes.set(key,pending);
  try {
  const route=await pending;
  // Malformed/failed responses never become reusable financial proof.
  if (Number.isFinite(route?.distance)&&route.distance>=0&&Number.isFinite(route?.duration)&&route.duration>=0
      &&Array.isArray(route.legs)&&route.legs.length===coords.length-1
      &&route.legs.every(l=>Number.isFinite(l.distance)&&l.distance>=0&&Number.isFinite(l.duration)&&l.duration>=0)) {
    b.routes.set(key,clone(route));
  }
  return route;
  } finally {b.pendingRoutes.delete(key);}
}

// Preserve private request-owned batch authority across a server env clone.
export function transferFinancialRouteBatchContextV1(source,target){const context=slots.get(source);if(context){if(!contexts.has(context))throw Error('financial_batch_context_invalid');slots.set(target,context);}}
