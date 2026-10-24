// Private, read-only composition of existing canonical and Room authorities.
// No KV booking fallback, recovery, offer expiry, financial read/write or grant.
import {trackingSource,trackingLegId,currentTrackingTrip} from './customer_tracking_access.mjs';
import {rideExecutionIdentityAtStart} from './company_ride_execution_identity.mjs';
import {dutyForRideExecution} from './company_vehicle_duty.mjs';
import {VEHICLE_DUTY_STATE_KEY,VEHICLE_DUTY_PROJECTION_KEY} from '../../tracking/modules/company_vehicle_duty_storage.mjs';
import {driverDispatchDevices} from '../../tracking/modules/dispatch_device_capability.mjs';
import {personalDriverExecutionV1} from '../../tracking/modules/personal_driver_execution_v1.mjs';
import {readCapacitySnapshot,hydrateCapacityRecords} from '../../tracking/modules/company_capacity_storage.mjs';
import {boundLocationOwner} from '../../tracking/modules/driver_location_owner.mjs';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const id=s=>typeof s==='string'&&s.length>0&&s.length<=160&&/^[A-Za-z0-9_.:-]+$/.test(s);
const hash=s=>typeof s==='string'&&/^[a-f0-9]{64}$/.test(s);
const deny=(error='navigation_trip_forbidden',status=403)=>({ok:false,error,status});
const terminal=r=>[r?.status,r?.stage,r?.lifecycle_status,r?.customer_tracking_phase].some(s=>['COMPLETED','CANCELLED','CANCELED','STOPPED','REJECTED','EXPIRED','NO_SHOW'].includes(String(s??'').toUpperCase()));
const internal=(request,env)=>request.method==='POST'&&typeof env.ADMIN_TOKEN==='string'&&env.ADMIN_TOKEN.length>0&&request.headers.get('x-admin-token')===env.ADMIN_TOKEN;
const response=r=>Response.json(r,{status:r.ok?200:r.status??503,headers:{'cache-control':'no-store'}});

export async function readCanonicalNavigationAuthorityV1(state,env,request,body){
 if(!internal(request,env)||body?.action!=='navigation_authority_read_v1'||!id(body.booking_id)||!id(body.scope?.tenant_id)||!id(body.scope?.company_id))return response(deny());
 if(env.BOOKING_RECORD_AUTHORITY_ENABLED!=='1')return response(deny('navigation_authority_unavailable',503));
 try{
  const pin=await state.storage.get('canonical-booking-scope'),envelope=await state.storage.get('canonical-booking:'+body.booking_id),r=envelope?.record;
  if(!same(pin,body.scope)||!same(envelope,body.scope)||!same(r,body.scope)||r.booking_id!==body.booking_id)return response(deny());
  if(envelope.schema!==1||!Number.isSafeInteger(envelope.version)||envelope.version<1||r._canonical_version!==envelope.version||envelope.projection_pending)return response(deny('navigation_authority_unavailable',503));
  const source=trackingSource(r,body.operational_leg??'');
  if(!source||terminal(r)||terminal(r.booking)||terminal(source))return response(deny());
  // Explicit child identities never fall back to a sibling/parent assignment.
  const driver=source.assigned_driver_id,vehicle=source.assigned_vehicle_id;
  if(!id(driver)||!id(vehicle))return response(deny());
  if(source.assignedDriverId!=null&&source.assignedDriverId!==driver||source.assignedVehicleId!=null&&source.assignedVehicleId!==vehicle)return response(deny());
  const offer=r.dispatch_offer;
  if(offer?.human_acceptance_required===true&&offer.state!=='committed')return response(deny());
  const execution=rideExecutionIdentityAtStart(r,{scope:body.scope,driverId:driver,vehicleId:vehicle,leg:source.leg_type??'outbound'});
  if(!execution.ok)return response(deny());
  const trip=currentTrackingTrip(source),phase=source.customer_tracking_phase??'assigned';
  if(!['assigned','en_route_pickup','arrived_pickup','in_progress'].includes(phase)||trip?.stopped_at)return response(deny());
  const tripIds=[trip?.session_id,trip?.trip_id].filter(id);
  if(body.trip_id){if(phase!=='in_progress'||!trip?.started_at||!tripIds.includes(body.trip_id))return response(deny());}
  else if(phase==='in_progress'||trip?.started_at)return response(deny());
  return response({ok:true,proof:{...body.scope,booking_id:body.booking_id,operational_leg:source===r?'primary':trackingLegId(source),canonical_version:envelope.version,
   driver_id:driver,vehicle_id:vehicle,phase,assignment_version:Number(source.customer_tracking_assignment_version)||1,
   trip_id:body.trip_id??null,execution_identity:execution.identity,offer_id:offer?.offer_id??null,offer_version:offer?.version??null,
   capacity_version:r.dispatch_capacity_checkpoint?.version??null}});
 }catch{return response(deny('navigation_authority_unavailable',503));}
}

export async function readRoomNavigationAuthorityV1(state,env,request,body,now=Date.now()){
 if(!internal(request,env)||new URL(request.url).pathname!=='/navigation-authority'||!same(body?.proof,body?.scope)||!id(body?.driver_id)||!id(body?.vehicle_id)||!hash(body?.device_key))return response(deny());
 if(env.COMPANY_VEHICLE_OPERATIONS_ENABLED!=='1')return response(deny('navigation_authority_unavailable',503));
 try{
  const p=body.proof,s=state.storage;
  if(p.driver_id!==body.driver_id||p.vehicle_id!==body.vehicle_id||!Number.isFinite(body.session_expires_ms)||body.session_expires_ms<=now)return response(deny());
  const devices=await s.get('dispatch_devices_v1'),leases=driverDispatchDevices(devices,body.scope,body.driver_id,now,body.device_key);
  if(leases.length!==1||Boolean(leases[0].vehicle_device_id)!==Boolean(body.vehicle_device_id)||leases[0].vehicle_device_id!==body.vehicle_device_id&&Boolean(body.vehicle_device_id))return response(deny());
  if(await s.get(VEHICLE_DUTY_PROJECTION_KEY))return response(deny());
  const duty=await s.get(VEHICLE_DUTY_STATE_KEY),dutyProof=dutyForRideExecution(duty,{...body.scope,driver_id:body.driver_id},body.vehicle_id);
  const ledger=await hydrateCapacityRecords(s,await readCapacitySnapshot(s),{owner:[p.booking_id],offer:p.offer_id?[p.offer_id]:[]},body.scope),owner=ledger.owners?.[p.booking_id];
  if(!same(ledger.scope??ledger.baseline,body.scope)||!owner||owner.pending||owner.released||owner.version!==p.capacity_version)return response(deny());
  const claims=Object.values(ledger.claims??{}).filter(c=>same(c,body.scope)&&c.owner_id===p.booking_id&&c.driver_id===p.driver_id&&c.vehicle_id===p.vehicle_id
   &&(p.operational_leg==='primary'||c.claim_id===p.operational_leg)&&!c.capacity_pending&&!c.retiring);
  if(claims.length!==1)return response(deny());
  if(p.execution_identity){const offer=ledger.offers?.[p.offer_id];if(offer?.state!=='committed'||JSON.stringify(offer.receipts?.[p.driver_id]?.execution_identity)!==JSON.stringify(p.execution_identity))return response(deny());}
  if(p.execution_identity?.kind==='personal_driver_session'){
   if(body.vehicle_device_id)return response(deny());
   const identity=personalDriverExecutionV1({input:{...body.scope,driver_id:body.driver_id,vehicle_id:body.vehicle_id,device_key:body.device_key,
    offer_id:p.offer_id,version:p.offer_version,personal_execution_auth:{source:'booking_personal_driver_session_v1',...body.scope,driver_id:body.driver_id,vehicle_id:body.vehicle_id,device_key:body.device_key,session_expires_ms:body.session_expires_ms}},
    devices,duty,offer:ledger.offers?.[p.offer_id],nowMs:now});
   if(identity?.acceptance_id!==p.execution_identity.acceptance_id)return response(deny());
  }else{
   if(!dutyProof.ok||p.execution_identity&&dutyProof.execution_identity.duty_id!==p.execution_identity.duty_id)return response(deny());
   if(body.vehicle_device_id){
    const deviceScope=await s.get('vehicle_device_scope_v1'),device=await s.get('vehicle_device_v1:'+body.vehicle_device_id);
    const active=duty.duties.find(d=>d.duty_id===dutyProof.execution_identity.duty_id);
    if(!same(deviceScope,body.scope)||!device||device.revoked||device.expires_at_ms<=now||device.vehicle_id!==body.vehicle_id||active?.vehicle_device_id!==body.vehicle_device_id)return response(deny());
   }
  }
  const root=await s.get('drivers_v1'),row=root?.format==='per-driver-v2'?await s.get('tracking-driver:v2:'+encodeURIComponent(body.driver_id)):root?.[body.driver_id];
  const captured=Date.parse(row?.captured_at??'');
  if(!same(row,body.scope)||row.driver_id!==body.driver_id||row.vehicle_id!==body.vehicle_id||row.location_withdrawn===true||!Number.isFinite(captured)||captured>now||now-captured>30000
   ||!Number.isFinite(row.accuracy)||row.accuracy<=0||row.accuracy>100)return response(deny());
  if(row.publication_owner&&(!boundLocationOwner(row.publication_owner,now)||row.publication_owner.session_hash!==body.device_key))return response(deny());
  return response({ok:true,fence:JSON.stringify([p,owner.version,claims,dutyProof.ok?dutyProof.execution_identity:p.execution_identity,body.device_key,body.vehicle_device_id??null])});
 }catch{return response(deny('navigation_authority_unavailable',503));}
}

async function privateRead(env,binding,name,path,body){
 if(!binding?.idFromName||!binding?.get||!env.ADMIN_TOKEN)return deny('navigation_authority_unavailable',503);
 try{const r=await binding.get(binding.idFromName(name)).fetch(new Request('https://internal'+path,{method:'POST',headers:{'content-type':'application/json','x-admin-token':env.ADMIN_TOKEN},body:JSON.stringify(body),signal:AbortSignal.timeout(5000)}));
  const result=await r.json();return result?.ok===true&&r.status===200?result:deny(r.status>=500?'navigation_authority_unavailable':'navigation_trip_forbidden',r.status>=500?503:403);
 }catch{return deny('navigation_authority_unavailable',503);}
}

export async function authorizeNationalNavigationV1({env,actor,body,path,clock=Date.now}){
 const operational=Boolean(body.trip_id||body.booking_id||body.operational_leg||body.origin_input?.kind==='gps'||path.endsWith('/reroute'));
 if(!operational)return {ok:true,fence:'address-preview'};
 if(actor?.role!=='driver'||!id(actor.scope?.tenant_id)||!id(actor.scope?.company_id)||!id(actor.driver_id)||!id(actor.vehicle_id)||!hash(actor.session_hash)||!Number.isFinite(actor.session_expires_ms)||actor.session_expires_ms<=clock())return deny();
 if(env.BOOKING_RECORD_AUTHORITY_ENABLED!=='1')return deny('navigation_authority_unavailable',503);
 let bookingId=body.booking_id;
 if(!bookingId&&id(body.trip_id)){
  // Existing scoped mapping is only a lookup hint; canonical read verifies it.
  const prefix=`tenant:${actor.scope.tenant_id}:company:${actor.scope.company_id}:tracking:`;
  const ids=[];try{for(const kind of ['session','trip']){const value=await env.BOOKING_KV.get(prefix+kind+':'+body.trip_id+':booking:v1',{type:'json'});if(value?.booking_id)ids.push(value.booking_id);}}catch{return deny('navigation_authority_unavailable',503);}
  if(new Set(ids).size===1)bookingId=ids[0];
 }
 if(!id(bookingId))return deny();
 const input={action:'navigation_authority_read_v1',scope:actor.scope,booking_id:bookingId,...(body.trip_id?{trip_id:body.trip_id}:{}),...(body.operational_leg?{operational_leg:body.operational_leg}:{})};
 const read=()=>privateRead(env,env.COMPANY_CUSTOMER_IMPORT_COORDINATOR,actor.scope.tenant_id+':'+actor.scope.company_id,'/navigation-authority',input);
 const first=await read();if(!first.ok)return first;
 if(first.proof?.driver_id!==actor.driver_id||first.proof?.vehicle_id!==actor.vehicle_id)return deny();
 const room=await privateRead(env,env.COMPANY_TRACKING,actor.scope.tenant_id+'\n'+actor.scope.company_id,'/navigation-authority',{scope:actor.scope,proof:first.proof,
  driver_id:actor.driver_id,vehicle_id:actor.vehicle_id,device_key:actor.session_hash,session_expires_ms:actor.session_expires_ms,...(actor.vehicle_device_id?{vehicle_device_id:actor.vehicle_device_id}:{})});
 if(!room.ok)return room;
 const second=await read();if(!second.ok)return second;
 if(JSON.stringify(first.proof)!==JSON.stringify(second.proof))return deny('navigation_assignment_changed',409);
 return {ok:true,fence:room.fence};
}
