import test,{mock}from'node:test';import a from'node:assert/strict';import{fleetFixture}from'./fleet-policy-fixture.mjs';
async function run(f){const r=await f.fleet._allocate(f.body,f.context);return r.json?await r.json():r;}
test('actual FleetAllocator retains exact committed resource for 181 versus 132 and returns independent Core ETA',async()=>{
 const f=await fleetFixture(),before=JSON.stringify(await f.x.f.read()),r=await run(f);a.equal(r.allowed,true,JSON.stringify(r));a.equal(r.assigned_vehicle_id,'VD');a.equal(f.context.confirmedAsapEtaAdvisory,true);a.equal(r.asap_eta_advisory.duration_seconds,1);a.equal(r.asap_eta_advisory.planning_only,false);a.equal(JSON.stringify(await f.x.f.read()),before);
});
test('without the private advisory request the old strict ETA comparison still rejects',async()=>{
 const f=await fleetFixture();delete f.body.revalidation_eta_advisory;const r=await run(f);a.equal(r.allowed,false);a.equal(r.reason,'vehicle_cannot_reach_pickup_in_time');a.equal(r.required_seconds,181);
});
for(const label of['uncommitted','foreign_scope','wrong_vehicle','pending_claim'])test('forged advisory cannot bypass committed-claim proof: '+label,async()=>{
 const f=await fleetFixture();if(label==='uncommitted')f.body.revalidation_offer.state='offered';if(label==='foreign_scope')f.body.tenant_id='OTHER';if(label==='wrong_vehicle')f.body.required_vehicle_id='VE';if(label==='pending_claim')f.body.revalidation_checkpoint.version++;
 await a.rejects(()=>run(f),/dispatch_confirmed_revalidation_unverified/);a.notEqual(f.context.confirmedAsapEtaAdvisory,true);
});
for(const label of['revoked_driver','no_lease','stale_gps','capacity','other_claim'])test('actual FleetAllocator non-ETA gate retained: '+label,async()=>{
 const f=await fleetFixture();
 if(label==='revoked_driver'){const key='tenant:T:company:C:drivers:index:v1',v=JSON.parse(f.x.f.records.get(key));v.drivers.D.is_active=false;f.x.f.records.set(key,JSON.stringify(v));}
 if(label==='capacity')f.body.pax=9;
 if(label==='no_lease'||label==='stale_gps'){const r=await f.x.f.slot().room.fetch(new Request('https://room/live?tenant_id=T&company_id=C&include_access_context=1'));a.equal(r.status,200);const live=await r.json();if(label==='no_lease')live.dispatch_devices=[];else for(const d of live.drivers){d.position_captured_at=new Date(Date.now()-120000).toISOString();d.captured_at=d.position_captured_at;d.location_age_ms=120000;}f.context.companyLive=live;}
 if(label==='other_claim')f.context.forecastDemandPromise=Promise.resolve({ok:true,items:[{booking_id:'OTHER',pickupMs:f.body.pickup_ms,serviceMin:20,assigned_vehicle_id:'VD',assigned_driver_id:'D',capacityOnly:true}]});
 const r=await run(f);a.notEqual(r.allowed,true,JSON.stringify(r));
});
test('Core ETA failure stays explicitly unavailable without withdrawing a technically eligible committed assignment',async()=>{
 const f=await fleetFixture(),get=f.fleet.env.__reliableRegionalRoutes;f.fleet.env.__reliableRegionalRoutes=async()=>({...await get(),route:async()=>{throw Error('synthetic route unavailable');}});const r=await run(f);a.equal(r.allowed,true);a.equal(r.asap_eta_advisory,null);
});
for(const conflict of[false,true])test('updated real ETA rechecks future reservations; conflict='+conflict,async()=>{
 const f=await fleetFixture(),get=f.fleet.env.__reliableRegionalRoutes;
 f.fleet.env.__reliableRegionalRoutes=async()=>({...await get(),route:async()=>({...await(await get()).route(),seconds:1800,distanceMeters:10000})});
 if(conflict)f.context.forecastDemandPromise=Promise.resolve({ok:true,items:[{booking_id:'FUTURE',pickupMs:Date.now()+45*60000,serviceMin:10,assigned_vehicle_id:'VD',assigned_driver_id:'D',pickupPoint:{lat:51.17,lng:4.15},capacityOnly:true}]});
 const before=JSON.stringify(await f.x.f.read()),r=await run(f);a.equal(r.allowed,!conflict,JSON.stringify(r));a.equal(JSON.stringify(await f.x.f.read()),before);if(!conflict)a.equal(r.asap_eta_advisory.duration_seconds,1800);
});
for(const advisory of[false,true])test('previous-dropoff approach ETA is also advisory only after verified commit: '+advisory,async()=>{
 const f=await fleetFixture();f.body.revalidation_eta_advisory=advisory;f.context.forecastDemandPromise=Promise.resolve({ok:true,items:[{booking_id:'PREVIOUS',pickupMs:Date.now()-20*60000,dropoffAtMs:Date.now()-10*60000,serviceMin:10,routeDurationSeconds:600,assigned_vehicle_id:'VD',assigned_driver_id:'D',dropoffPoint:{lat:51.16,lng:4.14},capacityOnly:true}]});const r=await run(f);a.equal(r.allowed,advisory,JSON.stringify(r));if(advisory)a.equal(r.asap_eta_advisory,null);
});
test('a passed ASAP estimate does not become a hard appointment and current evidence is rechecked',async()=>{
 const f=await fleetFixture(),advanced=Date.now()+300000;mock.method(Date,'now',()=>advanced);try{
 await f.x.f.roomPost('location',{driver_id:'D',vehicle_id:'VD',latitude:51.165,longitude:4.142,accuracy:8,captured_at:new Date(advanced).toISOString()});
 const hash=f.x.intent.device_key||await crypto.subtle.digest('SHA-256',new TextEncoder().encode('token-D')).then(b=>Buffer.from(b).toString('hex'));
 await f.x.f.roomPost('dispatch-device',{driver_id:'D',device_key:hash,protocol:1,session_expires_ms:advanced+3600000});
 f.x.f.records.set('tenant:T:company:C:driver_presence:v1',JSON.stringify({drivers:{D:{last_seen_at:new Date(advanced).toISOString()}}}));
 const r=await run(f);a.equal(r.allowed,true,JSON.stringify(r));a(r.asap_eta_advisory?.duration_seconds>=0);
 }finally{mock.restoreAll();}
});
