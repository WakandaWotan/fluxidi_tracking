import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import test from 'node:test';
const source=fs.readFileSync(process.env.CANDIDATE_RUNTIME||'D:/Projecten/outputs/agent2_credential_final_preparation_20261023/baseline/active/fluxidi-booking-api/entry.mjs','utf8');
const start=source.indexOf('async function _deriveVehicleOrigin('),end=source.indexOf('\nasync function ',start+1);
const nextPlain=source.indexOf('\nfunction ',start+1),stop=Math.min(...[end,nextPlain].filter(x=>x>start));
const fn=source.slice(start,stop);
const now=1792815539079;
async function evaluate({confirmed=false,asap=false,live=true,age=1000,base=true,routeOk=true}={}){
 const scope={tenant_id:'synthetic',company_id:'synthetic',hasScope:true};let validations=[];
 const ctx={Date:class extends Date {static now(){return now;}},console,Number,Math,Map,Set,normalizeFleetTenantScope:x=>x,
 _allocatorOriginMaxAgeSeconds:()=>120,safeStr:(x)=>x==null?'':String(x),rideIsSoon:()=>true,
 _readCompanyLiveOriginForVehicle:async()=>live?{point:{lat:1,lng:2,access:{kind:'gps'}},at_ms:now-age}:null,
 _readTrackingOriginForVehicle:async()=>null,_isUsableLocationPoint:p=>Number.isFinite(p?.lat)&&Number.isFinite(p?.lng),
 _allocatorResolvePointCoordinates:p=>({usable:Number.isFinite(p?.lat)&&Number.isFinite(p?.lng),lat:p?.lat,lng:p?.lng,source:'synthetic'}),
 _locationPointFromAny:o=>({lat:o.lat??o.current_lat??o.base_lat,lng:o.lng??o.current_lng??o.base_lng,address:o.address}),
 _allocatorMapboxCountryHint:()=>'',loadBusinessProfile:async()=>base?{base_lat:3,base_lng:4}:{},
 _demandDropoffTiming:()=>({}),_allocatorForwardGeocodeOriginPoint:async()=>({ok:false}),_sanitizeRouteErrorMessage:()=>''};
 vm.createContext(ctx);vm.runInContext(fn+'\nthis.derive=_deriveVehicleOrigin;',ctx);
 const result=await ctx.derive({},{vehicle_id:'synthetic-v'},[],now+195000,{tenantScope:scope,requestContext:{isAsapSearch:asap,confirmedAsapRevalidation:confirmed},validatePlannedRoute:async origin=>{validations.push(origin.source);return routeOk?{ok:true,travel_seconds:180}:{ok:false,reason_code:'synthetic_route_unavailable'};}});
 return {result,validations};
}
test('verified confirmed ASAP preserves valid live origin ahead of business base',async()=>{const {result,validations}=await evaluate({confirmed:true});assert.equal(result.source,'company_live');assert.equal(result.planned_route_result.ok,true);assert.deepEqual(validations,['company_live']);});
test('initial ASAP still uses valid live origin',async()=>assert.equal((await evaluate({asap:true})).result.source,'company_live'));
test('ordinary planned ride retains base-first policy',async()=>assert.equal((await evaluate()).result.source,'company_business_base'));
test('unverified/false confirmed context cannot change planned policy',async()=>assert.equal((await evaluate({confirmed:false})).result.source,'company_business_base'));
test('confirmed ASAP without live evidence retains base fallback',async()=>assert.equal((await evaluate({confirmed:true,live:false})).result.source,'company_business_base'));
test('stale live evidence is not made fresh by confirmed context',async()=>assert.equal((await evaluate({confirmed:true,age:180000})).result.source,'company_business_base'));
test('route refusal remains a refusal',async()=>{const {result}=await evaluate({confirmed:true,routeOk:false});assert.notEqual(result.planned_route_result?.ok,true);});
test('confirmed ASAP retains strict existing 30 second revalidation freshness rule',async()=>assert.equal((await evaluate({confirmed:true,age:45000})).result.source,'company_business_base'));
