// Local transport bridge: real Dart HTTP caller -> real Workers and Room.
import http from 'node:http';
import {AsyncLocalStorage} from 'node:async_hooks';
import {pathToFileURL} from 'node:url';
const root = process.env.FLUXIDI_BACKEND_ROOT;
if (!root) throw Error('FLUXIDI_BACKEND_ROOT required');
const {default: bookingWorker}=await import(pathToFileURL(`${root}/workers/booking/fluxidi_booking_worker.js`));
const {default: trackingWorker}=await import(pathToFileURL(`${root}/workers/tracking/fluxidi_tracking_api_worker_V2_1_with_route_index.js`));
const {CompanyTrackingRoom}=await import(pathToFileURL(`${root}/workers/tracking/modules/company_tracking_room.mjs`));
const {createMemoryCompanyCustomerImportCoordinatorBinding}=await import(pathToFileURL(`${root}/workers/booking/modules/company_customer_import_coordinator.mjs`));
const {commitAgendaCapacity,confirmAgendaCapacity}=await import(pathToFileURL(`${root}/workers/booking/modules/company_agenda.mjs`));
globalThis.fetch=async()=>{throw Error('External network forbidden in caller test');};
function kv(){const values=new Map();return {values,writes:0,async get(k,o){const v=values.get(k);return v==null?null:o?.type==='json'?JSON.parse(v):v;},async put(k,v){this.writes++;values.set(k,v);},async delete(k){values.delete(k);},async list(){return {keys:[],list_complete:true};}};}
let env, room, calls=[], failure=null, releasePresence=null;
const realNow=Date.now; let clockOffset=0; Date.now=()=>realNow()+clockOffset;
const scope={tenant_id:'T1',company_id:'C1'};
// Only synthetic route-provider output is adapted. Access, driver/leg grants,
// phase and final response revalidation still belong to the actual handlers.
const snapshotContext=new AsyncLocalStorage();
async function customerEtaContractFixture({target}) {
 const context=snapshotContext.getStore();
 if(!context)throw Error('fixture_snapshot_context_required');
 const grantUrl=new URL('https://room/customer-grant');
 grantUrl.searchParams.set('booking_id','B1');grantUrl.searchParams.set('operational_leg',context.leg);
 const response=await room.fetch(new Request(grantUrl)),body=await response.json(),grant=body.grant;
 if(!response.ok||grant?.tenant_id!==scope.tenant_id||grant.company_id!==scope.company_id||grant.booking_id!=='B1'
  ||grant.operational_leg!==context.leg||grant.position_allowed!==true
  ||!['en_route_pickup','in_progress'].includes(grant.tracking_phase)
  ||target!==(grant.tracking_phase==='in_progress'?'destination':'pickup'))throw Error('fixture_enrichment_context_mismatch');
 return {ok:true,assignment_version:grant.assignment_version,tracking_phase:grant.tracking_phase,
  eta:{target,duration_seconds:180,distance_meters:1000,estimated:true,source:'synthetic-local-fixture'},route:null};
}
const request=(path,body,token)=>new Request(`https://local${path}`,{method:'POST',headers:{'content-type':'application/json',...(token?{authorization:`Bearer ${token}`}:{'x-admin-token':'admin'})},body:JSON.stringify({...scope,...body})});
async function reset(split=false,sameDriver=false,projectedSingleLeg=false){
 clockOffset=0;
 const b=kv(), t=kv(), storage=new Map();
 room=new CompanyTrackingRoom({storage:{async get(k){return storage.get(k)},async put(k,v){storage.set(k,v)}}},{});
 env={COMPANY_CUSTOMER_IMPORT_COORDINATOR:createMemoryCompanyCustomerImportCoordinatorBinding(),ADMIN_TOKEN:'admin',BOOKING_KV:b,FLUXIDI_TRACKING:t,tracking_realtime_do_enabled:'true',tracking_legacy_kv_ping_write_enabled:'false',
 __customerEtaFetch:customerEtaContractFixture,
 COMPANY_TRACKING:{idFromName:n=>n,get:()=>({async fetch(u,i){const r=u instanceof Request?u:new Request(u,i);
 if(failure==='room'&&r.method==='POST'&&new URL(r.url).pathname==='/customer-grant') {const e=await r.clone().json();if(e.kind==='lifecycle'&&e.tracking_phase==='in_progress'){failure=null;return Response.json({error:'offline'},{status:503});}}
 if(failure==='presence-room' && new URL(r.url).pathname==='/location') {failure=null;throw Error('Room unavailable');}
 return room.fetch(r);}})}};
 const leg=(type,driver)=>({leg_id:`B1:${type}`,leg_type:type.toLowerCase(),status:'PENDING',assigned_driver_id:driver,assigned_vehicle_id:driver==='D2'?'V2':'V1',pickup_iso:new Date(Date.now()-60000).toISOString(),customer_tracking_seq:1,customer_tracking_assignment_version:1,customer_tracking_phase:'assigned',pickup:{latitude:51,longitude:4},destination:{latitude:52,longitude:5}});
 await b.put('booking:B1',JSON.stringify({booking_id:'B1',...scope,customer_id:'owner',status:'ASSIGNED',assigned_driver_id:'D1',assigned_vehicle_id:'V1',pickup_iso:new Date(Date.now()-60000).toISOString(),duration_min:40,customer_tracking_seq:1,customer_tracking_assignment_version:1,customer_tracking_phase:'assigned',pickup:{latitude:51,longitude:4},destination:{latitude:52,longitude:5},...(split?{return_enabled:true,return_duration_min:40,return_pickup_iso:new Date(Date.now()+7200000).toISOString(),roundtrip_dispatch_mode:'split_no_wait',operational_legs:[leg('OUTBOUND','D1'),leg('RETURN',sameDriver?'D1':'D2')]}:projectedSingleLeg?{operational_legs:[leg('OUTBOUND','D1')]}:{})}));
 for(const id of ['D1','D2','owner']){const hash=Buffer.from(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(id))).toString('hex');
 await b.put(`${id==='owner'?'customer':'public_driver'}:session:${hash}:v1`,JSON.stringify({...scope,role:id==='owner'?'customer':'driver',purpose:'customer_session',driver_id:id,customer_id:'owner',email_hash:'abc',expires_at:new Date(Date.now()+3600000).toISOString()}));}
 await b.put('tenant:T1:company:C1:drivers:index:v1',JSON.stringify({drivers:Object.fromEntries(['D1','D2'].map(id=>[id,{driver_id:id,is_active:true,availability_status:'available',assigned_vehicle_id:id==='D2'?'V2':'V1',weekly_roster:{timezone:'Europe/Brussels',explicitly_set:true,days:Object.fromEntries(['mon','tue','wed','thu','fri','sat','sun'].map(day=>[day,[{start:'00:00',end:'23:59'}]]))}}]))}));
 await b.put('tenant:T1:company:C1:fleet:vehicles:v1',JSON.stringify({vehicles:[{vehicle_id:'V1',is_active:true},{vehicle_id:'V2',is_active:true}]}));
 // Owner bootstrap is an actual handler, never a direct lifecycle stamp.
 for(const leg of split?['B1:OUTBOUND','B1:RETURN']:['primary']){
 const res=await bookingWorker.fetch(request('/bookings/B1/customer-tracking',{operational_leg:leg},'owner'),env);
 const json=await res.json(); if(!json.ok)throw Error(JSON.stringify(json)); tokens.set(leg,json.tracking_session.token);
 }
 calls=[];failure=null;
}
const tokens=new Map();
const server=http.createServer(async(req,res)=>{try{
 const chunks=[]; for await (const chunk of req) chunks.push(chunk); const data=Buffer.concat(chunks).toString(); const url=new URL(req.url,'http://local'); let response;
 if(url.pathname==='/control'){
 const cmd=JSON.parse(data); if(cmd.action==='reset') {tokens.clear();await reset(cmd.split,cmd.sameDriver,cmd.projectedSingleLeg);}
 if(cmd.action==='fail') failure=cmd.kind;
 if(cmd.action==='clock') clockOffset=cmd.now-realNow();
 if(cmd.action==='duty') {
   const key='tenant:T1:company:C1:drivers:index:v1';
   const index=await env.BOOKING_KV.get(key,{type:'json'});
   const d=index.drivers[cmd.driver||'D1'];
   if(cmd.offDuty) d.weekly_roster.days=Object.fromEntries(Object.keys(d.weekly_roster.days).map(day=>[day,[]]));
   if(cmd.paused) { d.availability_status='paused'; d.paused_at=new Date(Date.now()-60000).toISOString(); d.paused_until=new Date(Date.now()+3600000).toISOString(); }
   await env.BOOKING_KV.put(key,JSON.stringify(index));
 }
 if(cmd.action==='release-presence') { releasePresence?.(); releasePresence=null; }
 if(cmd.action==='bootstrap') {
   const leg=cmd.leg||'primary';
   response=await bookingWorker.fetch(request('/bookings/B1/customer-tracking',{operational_leg:leg},'owner'),env);
   const body=await response.clone().json(); if(body.tracking_session)tokens.set(leg,body.tracking_session.token);
 }
 if(cmd.action==='mutate') response=await bookingWorker.fetch(request(cmd.path,cmd.body||{}),env);
 if(cmd.action==='initialize-capacity') {
   const record=await env.BOOKING_KV.get('booking:B1',{type:'json'});
   const args={tenantId:'T1',companyId:'C1',bookingId:'B1',record};
   const prepared=await commitAgendaCapacity(env,args);
   if(!prepared.ok)throw Error(JSON.stringify(prepared));
   await env.BOOKING_KV.put('booking:B1',JSON.stringify(record));
   response=Response.json(await confirmAgendaCapacity(env,args));
 }
 if(cmd.action==='position') {const gps=await trackingWorker.fetch(request('/track/driver/location',{driver_id:cmd.driver||'D1',latitude:51.1,longitude:4.1,captured_at:new Date().toISOString()},cmd.driver||'D1'),env);if(!gps.ok)throw Error(await gps.text());}
 if(cmd.action==='snapshot') {
  const leg=cmd.leg||'primary';
  const requestUrl=new URL('https://track/track/customer/live');
  for(const [key,value]of Object.entries({...scope,booking_id:'B1',operational_leg:leg}))requestUrl.searchParams.set(key,value);
  // This helper represents a route/ETA presentation request, not a GPS poll.
  // Tests for ordinary polling can explicitly opt out; production is unchanged.
  if(cmd.includeRoute!==false)requestUrl.searchParams.set('include_route','1');
  response=await snapshotContext.run({leg},()=>trackingWorker.fetch(new Request(requestUrl,{headers:{authorization:'Bearer '+tokens.get(leg)}}),env));
 }
 if(cmd.action==='state') response=Response.json({record:JSON.parse(await env.BOOKING_KV.get('booking:B1')),calls,bookingWrites:env.BOOKING_KV.writes,trackingWrites:env.FLUXIDI_TRACKING.writes});
 response ||=Response.json({ok:true});
 }else{
 const target=url.pathname.startsWith('/booking/')?bookingWorker:trackingWorker;
 const path=url.pathname.replace(/^\/(booking|tracking)/,''); calls.push({path,body:data?JSON.parse(data):null});
 if(failure===path){failure=null;response=Response.json({error:'offline'},{status:503});}
 else {
 if(failure==='hold-presence'&&path==='/track/driver/location') {failure=null;await new Promise(resolve=>releasePresence=resolve);}
 response=await target.fetch(new Request(`https://local${path}`,{method:req.method,headers:req.headers,...(data?{body:data}:{})}),env);
 if(failure==='lost-session'&&path==='/track/session/start'){failure=null;response=Response.json({error:'lost response'},{status:503});}}
 }
 res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text());
 }catch(e){res.writeHead(500);res.end(JSON.stringify({error:String(e),stack:e.stack}));}});
server.listen(0,'127.0.0.1',()=>process.stdout.write(`PORT=${server.address().port}\n`));
