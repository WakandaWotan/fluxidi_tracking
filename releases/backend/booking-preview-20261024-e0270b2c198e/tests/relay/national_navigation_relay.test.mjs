import test from 'node:test';
import assert from 'node:assert/strict';
import worker,{RouteSessionDurableObject} from './fluxidi_navigation_worker.mjs';
import {relayNationalNavigation,boundedNavigationJson} from './national_navigation_relay.mjs';

const now=1800000000000;
const payload={origin:{lat:51,lng:4},destination:{lat:51.001,lng:4.001},trip_id:'2026-10-028'};
const route=()=>({ok:true,source:'fluxidi-national',provider_source:null,route_basis:'owned_immutable_route',
 route_hash:'a'.repeat(64),navigation_metadata_sha256:'b'.repeat(64),graph_version:'GRAPH',evidence_revision:'EVIDENCE',valid_until_ms:now+15000,
 distance_m:100,duration_s:10,geometry:{type:'LineString',coordinates:[[4,51],[4.001,51.001]]},legs:[{steps:[]}],
 session_scope:{tenant_id:'T',company_id:'C',driver_id:'D'}});
const req=(body=payload,headers={})=>new Request('https://navigation.fixture/route',{method:'POST',headers:{authorization:'Bearer FIXTURE','content-type':'application/json','cf-connecting-ip':'192.0.2.1',...headers},body:JSON.stringify(body)});
function fixture({answer=route(),status=200,stored=true}={}){
 let calls=0,writes=0,lastRequest,lastSummary,keys=[];
 const env={BOOKING_ROUTER:{async fetch(request){calls++;lastRequest=request;return new Response(JSON.stringify(answer),{status});}},
 ROUTE_SESSION:{idFromName(key){keys.push(key);return key;},get(){return {async fetch(request){writes++;lastSummary=await request.json();return new Response(JSON.stringify({ok:true,stored}));}};}}};
 return {env,run:(request=req())=>relayNationalNavigation(request,env,{clock:()=>now}),counts:()=>({calls,writes}),last:()=>({lastRequest,lastSummary,keys})};
}

test('no bearer cannot reach Booking, R2, provider or DO',async()=>{
 const f=fixture(),r=req();r.headers.delete('authorization');assert.equal((await f.run(r)).status,401);assert.deepEqual(f.counts(),{calls:0,writes:0});
});
test('missing service binding has no public network fallback',async()=>{
 const r=await relayNationalNavigation(req(),{},{clock:()=>now});assert.equal(r.status,503);assert.equal((await r.json()).provider_fallback,false);
});
test('fixed native service receives bearer and only trusted ingress fields',async()=>{
 const f=fixture(),r=await f.run(req(payload,{'x-tenant-id':'OTHER','x-forwarded-host':'evil.invalid'}));assert.equal(r.status,200);
 const sent=f.last().lastRequest;assert.equal(sent.url,'https://fluxidi-booking-api.fluxidi.workers.dev/company/navigation/route');
 assert.equal(sent.headers.get('authorization'),'Bearer FIXTURE');assert.equal(sent.headers.get('cf-connecting-ip'),'192.0.2.1');assert.equal(sent.headers.get('x-tenant-id'),null);
 const j=await r.json();assert.equal(j.session_scope,undefined);assert.equal(j.route_session_updated,true);
});
test('reroute uses the same authority without old coordinate cache',async()=>{
 const f=fixture();const r=new Request('https://navigation.fixture/reroute',req());assert.equal((await f.run(r)).status,200);assert.ok(f.last().lastRequest.url.endsWith('/company/navigation/reroute'));
});
test('Mapbox and incomplete own contracts fail closed without session write',async()=>{
 for(const change of [{source:'mapbox'},{provider_source:'mapbox'},{navigation_metadata_sha256:undefined},{route_basis:'cache'},{session_scope:null},{valid_until_ms:now},{distance_m:-1},{route_hash:'bad'}]){
  const f=fixture({answer:{...route(),...change}});assert.equal((await f.run()).status,502);assert.equal(f.counts().writes,0);
 }
});
test('held own access proof is preserved without fallback',async()=>{
 const f=fixture({answer:{ok:false,error:'access_address_parallel_ambiguity'},status:422});const r=await f.run();assert.equal(r.status,422);assert.equal((await r.json()).error,'access_address_parallel_ambiguity');assert.equal(f.counts().writes,0);
});
test('limiter denial and session revocation are preserved',async()=>{
 for(const status of [401,403,409,429,503]){
  const f=fixture({answer:{ok:false,error:'rate_limited'},status});assert.equal((await f.run()).status,status);assert.equal(f.counts().writes,0);
 }
});
test('scope and full trip ID bind optional session without truncation collision',async()=>{
 const a=fixture(),b=fixture({answer:{...route(),session_scope:{tenant_id:'T',company_id:'OTHER',driver_id:'D'}}});
 const id='x'.repeat(100);await a.run(req({...payload,trip_id:id}));await b.run(req({...payload,trip_id:id}));assert.notDeepEqual(a.last().keys,b.last().keys);assert.equal(a.last().lastSummary.trip_id,id);
 const c=fixture();await c.run(req({...payload,trip_id:'x'.repeat(99)+'y'}));assert.notDeepEqual(a.last().keys,c.last().keys);
});
test('no session claim without actual server acknowledgement',async()=>{
 for(const stored of [false,true]){const f=fixture({stored});assert.equal((await(await f.run()).json()).route_session_updated,stored);}
 const f=fixture();delete f.env.ROUTE_SESSION;assert.equal((await(await f.run()).json()).route_session_updated,false);
});
test('oversized and streamed bodies stop before service requests',async()=>{
 const f=fixture();assert.equal((await f.run(req({...payload,junk:'x'.repeat(9000)}))).status,413);assert.equal(f.counts().calls,0);
 await assert.rejects(()=>boundedNavigationJson(new Response(new ReadableStream({start(c){c.enqueue(new Uint8Array(3000));c.enqueue(new Uint8Array(3000));c.close();}})),5000),/body_limit/);
});
test('slow request bodies have a bounded read lifetime',async()=>{
 const response=new Response(new ReadableStream({start(){},cancel(){}}));await assert.rejects(()=>boundedNavigationJson(response,100,5),/body_deadline/);
});
test('original DO storage remains compatible while preserving full new ID',async()=>{
 const values=new Map(),storage={get:async k=>values.get(k),put:async(k,v)=>{values.set(k,v);}};
 const obj=new RouteSessionDurableObject({storage},{}),id='x'.repeat(100);
 const r=await obj.fetch(new Request('https://do/summary',{method:'PUT',body:JSON.stringify({trip_id:id,route_hash:'a'.repeat(64),distance_m:100,duration_s:10})}));assert.equal(r.status,200);
 assert.equal((await(await obj.fetch(new Request('https://do/summary'))).json()).session.trip_id,id);
});
test('public Worker route is no longer an unauthenticated provider proxy',async()=>{
 const request=req();request.headers.delete('authorization');assert.equal((await worker.fetch(request,{})).status,401);
});
