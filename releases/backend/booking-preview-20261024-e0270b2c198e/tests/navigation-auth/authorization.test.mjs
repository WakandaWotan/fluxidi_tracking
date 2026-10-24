import {test} from 'node:test';import assert from 'node:assert/strict';
import {authFixture,tokenHash} from './auth-fixture.mjs';
import bookingWorker from '../backend/retained-source/workers/booking/quote_handler_candidate.js';
import {authorizeNationalNavigationV1} from './candidate/retained-source/workers/booking/modules/national_navigation_authorization_v1.mjs';
const request={booking_id:'B',operational_leg:'primary'};
async function status(f,body=request,options={}){const r=await f.run(body,options);assert.equal(r.status,options.expect??200,await r.clone().text());return r;}
test('committed canonical personal assignment permits route and GPS; no extra claim',async()=>{
 const f=await authFixture();await status(f,{...request,origin_input:{kind:'gps',capturedAt:Date.now(),accuracyMeters:8,speedMetersPerSecond:3,headingDegrees:90}});
 assert.equal(f.routeArgs().origin.access.headingDegrees,90);assert.equal(f.graphCalls(),1);
 assert.equal(Object.values(f.f.slot().data.get('company_capacity_ledger_v1').claims).filter(c=>c.owner_id==='B').length,1);
});
test('started canonical trip resolves existing session/trip hints and permits reroute',async()=>{
 const f=await authFixture();await f.start();await status(f,{trip_id:'SESSION'});await status(f,{trip_id:'TRIP',origin:undefined,current:{lat:51,lng:4}},{reroute:true});
});
test('address preview without operational identifiers keeps existing behavior',async()=>{const f=await authFixture({commit:false});await status(f,{});});
for(const [name,change]of [
 ['wrong driver',f=>{f.actor.driver_id='E';f.actor.vehicle_id='VE';f.actor.session_hash=tokenHash('token-E');}],
 ['wrong vehicle',f=>{f.actor.vehicle_id='VE';}],['foreign company',f=>{f.actor.scope={tenant_id:'T',company_id:'OTHER'};}],
 ['expired actor',f=>{f.actor.session_expires_ms=Date.now()-1;}],['admin cannot operate as driver',f=>{f.actor.role='company_admin';}],
 ['revoked lease',f=>{f.f.slot().data.get('dispatch_devices_v1').devices={};}],
 ['expired lease',f=>{f.f.slot().data.get('dispatch_devices_v1').devices[f.actor.session_hash].valid_until_ms=Date.now()-1;}],
 ['withdrawn GPS',f=>{f.f.slot().data.get('drivers_v1').D.location_withdrawn=true;}],
 ['stale GPS',f=>{f.f.slot().data.get('drivers_v1').D.captured_at=new Date(Date.now()-31000).toISOString();}],
 ['duty change projection',f=>{f.f.slot().data.set('vehicle_duty_projection_v1',{pending:true});}],
 ['personal cannot take over paused duty',f=>{f.f.slot().data.set('vehicle_duty_active_v1',{tenant_id:'T',company_id:'C',duties:[{duty_id:'DUTY',driver_id:'D',vehicle_id:'VD',ended_at_ms:null,paused_at_ms:Date.now()}]});}],
 ['released claim',f=>{f.f.slot().data.get('company_capacity_ledger_v1').owners.B.released=true;}],
 ['pending claim',f=>{f.f.slot().data.get('company_capacity_ledger_v1').owners.B.pending=true;}],
 ['missing canonical storage',f=>{f.f.coordinator().state.storage._store.delete('canonical-booking:B');}],
 ])test(name+' refuses before graph',async()=>{const f=await authFixture();await change(f);await status(f,request,{expect:403});assert.equal(f.graphCalls(),0);});
for(const [name,change]of [
 ['unassigned',r=>{delete r.assigned_driver_id;delete r.booking.assigned_driver_id;delete r.assigned_vehicle_id;delete r.booking.assigned_vehicle_id;}],
 ['reassigned',r=>{r.assigned_driver_id='E';r.assigned_vehicle_id='VE';}],
 ['cancelled',r=>{r.status='CANCELLED';}],['completed',r=>{r.status='COMPLETED';}],
 ['acceptance withdrawn',r=>{r.dispatch_offer.state='cancelled';}],
 ])test(name+' canonical assignment refuses',async()=>{const f=await authFixture();await f.mutate(change);await status(f,request,{expect:403});assert.equal(f.graphCalls(),0);});
test('committing 200 without canonical commit cannot navigate',async()=>{const f=await authFixture({commit:false});await status(f,request,{expect:403});});
test('wrong, old, sibling or omitted trip cannot borrow an active assignment',async()=>{
 const f=await authFixture();await f.start();for(const body of [{...request,trip_id:'WRONG'},request,{booking_id:'B',trip_id:'SESSION',operational_leg:'B:RETURN'}])await status(f,body,{expect:403});
});
test('reroute and live GPS without operational identity refuse',async()=>{const f=await authFixture();await status(f,{origin_input:{kind:'gps',capturedAt:Date.now(),accuracyMeters:8}},{expect:403});await status(f,{origin:undefined,current:{lat:51,lng:4}},{reroute:true,expect:403});});
test('canonical change during route withholds the old route',async()=>{const f=await authFixture();await status(f,request,{onRoute:()=>f.mutate(r=>{r.assigned_driver_id='E';}),expect:403});});
test('lease revoked during route withholds the old route',async()=>{const f=await authFixture();await status(f,request,{onRoute:async()=>{f.f.slot().data.get('dispatch_devices_v1').devices={};},expect:403});});
test('private read refuses unsigned calls before recovery/load; snapshots remain byte-identical',async()=>{
 const f=await authFixture();const co=f.f.coordinator(),room=f.f.slot();
 const before=JSON.stringify({co:[...co.state.storage._store],room:[...room.data],kv:[...f.f.records],alarm:room.alarmAt});
 co._fetchBody=()=>{throw Error('Recovery branch must never run');};room.room.load=()=>{throw Error('Mutating Room load must never run');};
 for(let i=0;i<2;i++){const allowed=await authorizeNationalNavigationV1({env:f.env,actor:f.actor,body:request,path:'/company/navigation/route'});assert.equal(allowed.ok,true,JSON.stringify(allowed));}
 const denied=await co.fetch(new Request('https://internal/',{method:'POST',body:JSON.stringify({action:'navigation_authority_read_v1',scope:f.scope,booking_id:'B'})}));assert.equal(denied.status,403);
 const roomDenied=await room.room.fetch(new Request('https://internal/navigation-authority',{method:'POST',body:JSON.stringify({scope:f.scope,driver_id:'D',vehicle_id:'VD'})}));assert.equal(roomDenied.status,403);
 const after=JSON.stringify({co:[...co.state.storage._store],room:[...room.data],kv:[...f.f.records],alarm:room.alarmAt});assert.equal(after,before);
});
test('active duty on bound vehicle permits route; pause, device switch and revoke refuse',async()=>{
 const f=await authFixture({vehicleDuty:true,vehicleDevice:true});await status(f);
 const duty=f.f.slot().data.get('vehicle_duty_active_v1').duties[0];duty.paused_at_ms=Date.now();await status(f,request,{expect:403});duty.paused_at_ms=null;
 const device=f.f.slot().data.get('vehicle_device_v1:DEVICE');device.vehicle_id='VE';await status(f,request,{expect:403});device.vehicle_id='VD';device.revoked=true;await status(f,request,{expect:403});
});
test('opaque actor/session change after graph is rejected',async()=>{
 const f=await authFixture();let n=0;await status(f,request,{authenticate:async()=>++n===1?f.actor:{...f.actor,vehicle_id:'VE'},expect:401});
});
test('canonical version change during route returns conflict even if ownership unchanged',async()=>{
 const f=await authFixture();await status(f,request,{onRoute:()=>f.mutate(r=>{r.revision++;}),expect:409});
});
test('storage outage does not become permission or booking adoption',async()=>{
 const f=await authFixture();f.f.coordinator().state.storage.get=async()=>{throw Error('storage outage');};await status(f,request,{expect:503});assert.equal(f.graphCalls(),0);
});
test('measured GPS retains time, accuracy and continuity; unknown heading is never fabricated',async()=>{
 for(const speed of [undefined,0,3]){const f=await authFixture();const capturedAt=Date.now();await status(f,{...request,origin_input:{kind:'gps',capturedAt,accuracyMeters:12,...(speed===undefined?{}:{speedMetersPerSecond:speed}),headingDegrees:90}});
  const a=f.routeArgs().origin.access;assert.equal(a.capturedAt,capturedAt);assert.equal(a.accuracyMeters,12);assert.equal(a.continuityKey,'nav:D');assert.equal(a.speedMetersPerSecond,speed);assert.equal(a.headingDegrees,speed>=2?90:undefined);}
});
test('real public Booking callback supplies verified vehicle context; wrong driver never reaches router',async()=>{
 const f=await authFixture();Object.assign(f.f.env,{NATIONAL_NAVIGATION_ENABLED:'1',BOOKING_NAVIGATION_IP_LIMITER:f.env.BOOKING_NAVIGATION_IP_LIMITER,BOOKING_NAVIGATION_CLIENT_LIMITER:f.env.BOOKING_NAVIGATION_CLIENT_LIMITER});
 const payload={...request,origin:{lat:51,lng:4},destination:{lat:51,lng:4.001}};
 const call=token=>bookingWorker.fetch(new Request('https://booking/company/navigation/route',{method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json','cf-connecting-ip':'192.0.2.1'},body:JSON.stringify(payload)}),f.f.env,{});
 const good=await call('token-D');assert.equal(good.status,422,await good.clone().text());assert.equal((await good.json()).error,'navigation_runtime_unavailable','authorized actor reaches deliberately absent synthetic router');
 const wrong=await call('token-E');assert.equal(wrong.status,403);
});
