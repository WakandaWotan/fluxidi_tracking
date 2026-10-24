import {sha256Hex}from'./crypto_utils.js';
import {normalizeCustomerScope}from'./company_customers.mjs';
import {readBoundedJson,writeBoundedJson,deleteBoundedJson}from'./bounded_json_storage.mjs';
const KEY='customer-projection-journal-v1',SCOPE='customer-projection-scope-v1';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const canonical=v=>Array.isArray(v)?v.map(canonical):v&&typeof v==='object'?Object.fromEntries(Object.keys(v).sort().map(k=>[k,canonical(v[k])])):v;
const signature=body=>sha256Hex(JSON.stringify(canonical(body)));
function validateScope(scope){const normalized=normalizeCustomerScope(scope);if(!normalized.hasScope)throw Error('customer_journal_scope_invalid');return{tenant_id:normalized.tenant_id,company_id:normalized.company_id};}
function validatePlan(plan,scope){
 if(plan?.schema!==1||!same(plan.scope,scope)||!Array.isArray(plan.kv)||plan.kv.length>128||!Array.isArray(plan.durable)||plan.durable.length>4||!Number.isInteger(plan.response?.status)||!/^[a-f0-9]{64}$/.test(plan.signature))throw Error('customer_journal_invalid');
 const prefix='tenant:'+scope.tenant_id+':company:'+scope.company_id+':';
 for(const row of plan.kv)if(!['put','delete'].includes(row.method)||typeof row.key!=='string'||!row.key.startsWith(prefix))throw Error('customer_journal_key_scope_invalid');
 for(const row of plan.durable)if(row.method!=='put'||!/^import:imp_[a-f0-9]{32}$/.test(row.key))throw Error('customer_journal_durable_key_invalid');
}
async function replay(storage,env,plan){
 for(const row of plan.kv)if(row.method==='put'){
   const options={...row.options};
   if(row.expires_at!=null){const remaining=Math.ceil(row.expires_at-Date.now()/1000);if(remaining<=0)continue;delete options.expiration;if(remaining<60)throw Error('customer_projection_ttl_pending');options.expirationTtl=remaining;}
   await env.BOOKING_KV.put(row.key,row.value,Object.keys(options).length?options:undefined);
 }else await env.BOOKING_KV.delete(row.key);
 for(const row of plan.durable)await writeBoundedJson(storage,row.key,row.value);
 await deleteBoundedJson(storage,KEY);
}
export async function recoverCustomerProjection(storage,env,scope,body=null){
 const plan=await readBoundedJson(storage,KEY);if(!plan)return null;scope=validateScope(scope);validatePlan(plan,scope);
 await replay(storage,env,plan);
 return body&&await signature(body)===plan.signature?new Response(plan.response.body,{status:plan.response.status,headers:{'content-type':'application/json'}}):null;
}
export async function runCustomerProjection(storage,env,body,run){
 const scope=validateScope(body.scope);const bound=await storage.get(SCOPE);if(bound&&!same(bound,scope))throw Error('customer_journal_scope_conflict');if(!bound)await storage.put(SCOPE,scope);
 const kv=[],durable=[],overlay=new Map(),prefix='tenant:'+scope.tenant_id+':company:'+scope.company_id+':';
 const assertKey=key=>{if(typeof key!=='string'||!key.startsWith(prefix))throw Error('customer_journal_key_scope_invalid');};
 const stagedKv=new Proxy(env.BOOKING_KV,{get(target,name){
  if(name==='get')return async(key,options)=>{if(!overlay.has(key))return target.get(key,options);const value=overlay.get(key);if(value==null)return null;return options==='json'||options?.type==='json'?JSON.parse(value):value;};
  if(name==='put')return async(key,value,options)=>{assertKey(key);if(kv.length>=128)throw Error('customer_journal_budget_exceeded');const expires_at=options?.expiration??(Number.isFinite(options?.expirationTtl)?Date.now()/1000+options.expirationTtl:null);const raw=typeof value==='string'?value:JSON.stringify(value);kv.push({method:'put',key,value:raw,options,...(expires_at!=null?{expires_at}:{})});overlay.set(key,raw);};
  if(name==='delete')return async key=>{assertKey(key);if(kv.length>=128)throw Error('customer_journal_budget_exceeded');kv.push({method:'delete',key});overlay.set(key,null);};
  const value=Reflect.get(target,name);return typeof value==='function'?value.bind(target):value;
 }});
 const stagedStorage=new Proxy(storage,{get(target,name){
  if(name==='put')return async(key,value)=>{if(durable.length>=4||!/^import:imp_[a-f0-9]{32}$/.test(key))throw Error('customer_journal_durable_key_invalid');durable.push({method:'put',key,value:structuredClone(value)});};
  const value=Reflect.get(target,name);return typeof value==='function'?value.bind(target):value;
 }});
 const response=await run({...env,BOOKING_KV:stagedKv},stagedStorage);
 if(!response.ok||!kv.length&&!durable.length)return response;
 const plan={schema:1,scope,signature:await signature(body),kv,durable,response:{status:response.status,body:await response.clone().text()}};validatePlan(plan,scope);
 // Durable intent precedes every external projection write. Replaying exact
 // bytes preserves UUIDs, revisions, packed pages and import identity.
 const alarm=await storage.getAlarm?.();await storage.setAlarm(Math.min(Number.isFinite(alarm)?alarm:Infinity,Date.now()+60000));
 await writeBoundedJson(storage,KEY,plan);
 await replay(storage,env,plan);return response;
}
