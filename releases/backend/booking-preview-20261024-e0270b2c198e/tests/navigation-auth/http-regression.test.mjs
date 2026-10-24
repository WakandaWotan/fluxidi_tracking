import test from 'node:test';import assert from 'node:assert/strict';
import {handleNationalNavigationHttpV1} from '../backend/retained-source/workers/booking/modules/national_navigation_http_v1.mjs';
const now=1800000000000,scope={tenant_id:'T',company_id:'C',graphVersion:'G',evidenceRevision:'E'};
const actor={role:'driver',driver_id:'D',session_hash:'FIXTURE',scope:{tenant_id:'T',company_id:'C'}};
const body={origin:{lat:51,lng:4},destination:{lat:51,lng:4.001},origin_label:'Teststraat 1, 9000 Gent',destination_label:'Teststraat 2, 9000 Gent',country:'BE'};
function fixture(){
 let authCalls=0,routerCalls=0,currentActor=actor,lastArgs;
 const geometry=[{latitude:51,longitude:4},{latitude:51,longitude:4.001}];
 const e={id:1,way:100,ordinal:0,direction:1,seconds:10,distanceMeters:100};
 const route={...scope,evidenceId:'SYNTHETIC',validUntil:now+15000,distanceMeters:100,seconds:10,geometry,
  navigationEvidence:{...scope,schema:'fluxidi-directed-navigation-evidence-v1',coreEvidenceId:'SYNTHETIC',staticSeconds:10,edges:[e],roads:[{...e,fullDistanceMeters:100,fromNode:1,toNode:2,from:geometry[0],to:geometry[1],tags:{streetNames:['Teststraat'],highway:'residential'},options:[],junctionComplete:true}]}};
 const env={NATIONAL_NAVIGATION_ENABLED:'1',BOOKING_NAVIGATION_IP_LIMITER:{limit:async()=>({success:true})},BOOKING_NAVIGATION_CLIENT_LIMITER:{limit:async()=>({success:true})}};
 const auth=async()=>{authCalls++;return currentActor;};
 const create=async(_env,s)=>{routerCalls++;assert.deepEqual(s,actor.scope);return {kind:'LOCAL_ROUTING_ONLY_V1',scope,async resolveForJourney(){},async navigationRoute(args){lastArgs=args;return route;}};};
 const run=async(payload=body,overrides={})=>handleNationalNavigationHttpV1({request:new Request('https://fixture/company/navigation/route',{method:'POST',headers:{'content-type':'application/json','cf-connecting-ip':'192.0.2.1'},body:JSON.stringify(payload)}),env,authenticate:auth,createRouter:create,clock:()=>now,...overrides});
 return {run,env,route,setActor:a=>{currentActor=a;},counts:()=>({authCalls,routerCalls}),lastArgs:()=>lastArgs};
}
test('owned route retains existing DTO; no financial or external provider side effect',async()=>{
 const f=fixture(),r=await f.run(),j=await r.json();assert.equal(r.status,200);assert.equal(j.source,'fluxidi-national');assert.equal(j.provider_source,null);
 assert.equal(j.route_session_updated,false);assert.equal(j.legs[0].steps.at(-1).maneuver.type,'arrive');assert.equal(f.counts().authCalls,2);
 assert.deepEqual(j.session_scope,{tenant_id:'T',company_id:'C',driver_id:'D'});assert.equal(j.price_incl_vat,undefined);
});
test('disabled or unavailable native limiter does not read sessions or graph',async()=>{
 for(const env of [{},{NATIONAL_NAVIGATION_ENABLED:'1'}]){
  const f=fixture();assert.equal((await f.run(body,{env})).status,503);assert.deepEqual(f.counts(),{authCalls:0,routerCalls:0});
 }
});
test('rejected edge burst incurs no KV authentication or graph reads',async()=>{
 const f=fixture();f.env.BOOKING_NAVIGATION_IP_LIMITER.limit=async()=>({success:false});
 assert.equal((await f.run()).status,429);assert.deepEqual(f.counts(),{authCalls:0,routerCalls:0});
});
test('unauthenticated request never creates a route',async()=>{
 const f=fixture();f.setActor(null);assert.equal((await f.run()).status,401);assert.equal(f.counts().routerCalls,0);
});
test('authenticated budget denies routing and is distinct for drivers behind one IP',async()=>{
 const f=fixture();let keys=[];f.env.BOOKING_NAVIGATION_CLIENT_LIMITER.limit=async({key})=>{keys.push(key);return {success:false};};
 assert.equal((await f.run()).status,429);assert.deepEqual(f.counts(),{authCalls:1,routerCalls:0});
 f.setActor({...actor,driver_id:'OTHER'});assert.equal((await f.run()).status,429);assert.notEqual(keys[0],keys[1]);
});
test('client scope or graph substitution is rejected',async()=>{
 for(const extra of [{tenant_id:'OTHER'},{company_id:'OTHER'},{driver_id:'OTHER'},{graphVersion:'OTHER'},{router:{}},{financial_route:{}}]){
  const f=fixture();assert.equal((await f.run({...body,...extra})).status,400);assert.equal(f.counts().routerCalls,0);
 }
});
test('country hint does not block BE/NL or a neighbouring served route',async()=>{
 for(const country of ['BE','NL','FR','DE','LU'])assert.equal((await fixture().run({...body,country})).status,200);
});
test('stale/unknown GPS and customer-substituted actor never mint route evidence',async()=>{
 for(const input of [{kind:'gps'},{kind:'gps',capturedAt:now-31000,accuracyMeters:5},{kind:'gps',capturedAt:now+1,accuracyMeters:5},{kind:'gps',capturedAt:now,accuracyMeters:101}]){
  const f=fixture();assert.equal((await f.run({...body,origin_input:input})).status,422);assert.equal(f.counts().routerCalls,0);
 }
});
test('GPS without operational context cannot mint a route',async()=>{
 const f=fixture();assert.equal((await f.run({...body,origin_input:{kind:'gps',capturedAt:now,accuracyMeters:12,headingDegrees:90}})).status,403);assert.equal(f.counts().routerCalls,0);
});
test('speed/heading cannot replace missing operational context',async()=>{
 for(const speed of [0,3]){
  const f=fixture();assert.equal((await f.run({...body,origin_input:{kind:'gps',capturedAt:now,accuracyMeters:5,speedMetersPerSecond:speed,headingDegrees:90}})).status,403);assert.equal(f.counts().routerCalls,0);
 }
});
test('revoked or switched session cannot receive old scoped route',async()=>{
 const f=fixture();let n=0;const r=await f.run(body,{authenticate:async()=>++n===1?actor:{...actor,scope:{tenant_id:'T',company_id:'OTHER'}}});
 assert.equal(r.status,401);assert.equal((await r.json()).session_scope,undefined);
});
test('malformed/oversized body and coordinate types never reach graph',async()=>{
 for(const input of [{...body,origin:{lat:'51',lng:4}},{...body,origin:{lat:null,lng:4}},{...body,origin_label:'x'.repeat(9000)}]){
  const f=fixture(),r=await f.run(input);assert.ok([400,413].includes(r.status));assert.equal(f.counts().routerCalls,0);
 }
});
test('failed owned routing returns an explicit hold and never a provider fallback',async()=>{
 const f=fixture();const r=await f.run(body,{createRouter:async()=>{throw Error('access_address_parallel_ambiguity');}});
 assert.equal(r.status,422);assert.deepEqual(await r.json(),{ok:false,error:'access_address_parallel_ambiguity',provider_fallback:false});
});

test('required operational invariant: unassigned trip must be refused',async()=>{
 for(const trip_id of ['LOCAL_UNASSIGNED','LOCAL_ASSIGNED_TO_OTHER_DRIVER']){
  const f=fixture(); const r=await f.run({...body,trip_id});assert.equal(r.status,403);
  assert.equal(f.lastArgs()?.trip_id,undefined);assert.equal(f.counts().routerCalls,0);
 }
});