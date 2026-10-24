import {RELIABLE_CHOICE_V1} from './reliable_candidate_v1.mjs';
import {trackingFactsFromRecord} from './customer_tracking_access.mjs';
import {reliableReturnInfoV1} from './reliable_journey_v1.mjs';
import {reliableChoiceEnabled} from './reliable_prebooking_v1.mjs';
import {classifyAddressAccessFailureV1} from './address_access_errors_v1.mjs';
import {verifyBookingFinancialEvidence} from './financial_quote_lifecycle.mjs';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const response=(body,status=200)=>Response.json(body,{status,headers:{'cache-control':'no-store'}});
const enabled=reliableChoiceEnabled;
const id=s=>typeof s==='string'&&/^[a-zA-Z0-9_.:-]{1,128}$/.test(s);
const scopedId=s=>typeof s==='string'&&/^[a-zA-Z0-9_.-]{1,96}$/.test(s);

// Public transport over the existing canonical Reliable Choice
// service. Server capabilities never come from JSON, headers or a public URL.
// Missing integration/evidence fails closed; there is no legacy route fallback.
export async function handleReliablePublicFlowV1({request,env,loadCustomerSession,authorizeCompany,resolveRequestScope,command,trackingDecision}){
 const url=new URL(request.url);
 const customer=url.pathname.match(/^\/public\/customer\/reliable-choice\/([^/]+)\/(vehicles|choice|status)$/);
 const dispatcher=url.pathname==='/admin/company/reliable-choice/queue',prebook=url.pathname==='/public/customer/reliable-choice/vehicles';
 if(!customer&&!dispatcher&&!prebook)return null;
 if(!enabled(env))return response({ok:false,error:'reliable_choice_local_disabled'},503);
 const runtimeFor=async scope=>typeof env.__reliableChoiceRuntime==='function'?env.__reliableChoiceRuntime(scope):
   typeof command==='function'?{kind:'P12_LOCAL_SHADOW_ONLY',open:input=>command(scope,'open',input),choose:input=>command(scope,'choose',input),openRequest:input=>command(scope,'open_request',input)}:null;
 if(prebook){
  if(request.method!=='POST')return response({ok:false,error:'method_not_allowed'},405);
  const session=await loadCustomerSession(request,env);if(!session?.customer_id)return response({ok:false,error:'unauthorized'},401);
  const text=await request.text();if(text.length>8192)return response({ok:false,error:'reliable_request_invalid'},400);
  let body;try{body=JSON.parse(text);}catch{return response({ok:false,error:'invalid_json'},400);}
  if(!body||Array.isArray(body)||body.pickup_mode!=='asap'||typeof resolveRequestScope!=='function')return response({ok:false,error:'reliable_request_invalid'},400);
  const resolved=await resolveRequestScope(body);if(!resolved?.ok)return response({ok:false,error:resolved?.error||'forbidden'},resolved?.status||403);
  try{const service=await runtimeFor({tenant_id:resolved.tenant_id,company_id:resolved.company_id});if(typeof service?.openRequest!=='function')throw Error('runtime');const result=await service.openRequest({customerId:session.customer_id,body});if(result?.ok===false){
    const addressFailure=classifyAddressAccessFailureV1(result.error);if(addressFailure)return response(addressFailure.body,addressFailure.status);
    return response({ok:false,error:'reliable_evidence_unavailable'},503);
   }return response(result);}
  catch{return response({ok:false,error:'reliable_evidence_unavailable'},503);}
 }
 if(customer){
  const bookingId=customer[1],action=customer[2];
  if(!id(bookingId))return response({ok:false,error:'reliable_booking_invalid'},400);
  if(request.method!==(action==='choice'?'POST':'GET'))return response({ok:false,error:'method_not_allowed'},405);
  const session=await loadCustomerSession(request,env);
  if(!session?.customer_id)return response({ok:false,error:'unauthorized'},401);
  const record=await env.BOOKING_KV.get('booking:'+bookingId,{type:'json'});
  if(!record||record.customer_id!==session.customer_id)return response({ok:false,error:'forbidden'},403);
  if(!same(record,session)){
   // A global customer can read only its own new vehicle-financial sale. The
   // canonical booking supplies the company; no URL/body tenant is authority.
   // Existing mutation/legacy gates remain scoped. Financial input ownership
   // and integrity must agree with the authenticated and persisted customer.
   if(action!=='status'||session.tenant_id!=='global'||session.company_id!=='global'||
     !scopedId(record.tenant_id)||!scopedId(record.company_id))return response({ok:false,error:'forbidden'},403);
   try{const finance=await verifyBookingFinancialEvidence(record);
    if(finance?.inputs?.financial_context?.schema!=='fluxidi-vehicle-financial-context-v1'||
      finance.inputs.financial_context.customer_id!==session.customer_id)throw Error('owner');
   }catch{return response({ok:false,error:'forbidden'},403);}
  }
  const scope={tenant_id:record.tenant_id,company_id:record.company_id};
  if(action==='status'){
   const phase=trackingFactsFromRecord(record,bookingId).tracking_phase;
   const assigned=!!record.assigned_driver_id&&!!record.assigned_vehicle_id;
   const terminal=['completed','cancelled','stopped'].includes(phase);
   let trackingAllowed=env.RELIABLE_CHOICE_ENABLED!=='1';
   if(!trackingAllowed&&typeof trackingDecision==='function'){try{const access=await trackingDecision(scope);trackingAllowed=access?.applicable===true&&access.ok===true;}catch{trackingAllowed=false;}}
   const live=trackingAllowed&&assigned&&!terminal&&['en_route_pickup','arrived_pickup','in_progress'].includes(phase);
   return response({ok:true,schema:RELIABLE_CHOICE_V1,booking_id:bookingId,state:terminal?phase:assigned?'driver_confirmed':record.p12_dispatcher_review?'dispatcher_review':record.vehicle_dispatch_attempts?.length?'finding_next_vehicle':'waiting_driver_confirmation',confirmed:assigned&&!terminal,eta_is_estimate:!live,live_tracking:live});
  }
  const service=await runtimeFor(scope);
  if(service?.kind!=='P12_LOCAL_SHADOW_ONLY')return response({ok:false,error:'reliable_local_runtime_required'},503);
  const credential=request.headers.get('authorization')?.replace(/^Bearer\s+/i,'')??'';
  try{
   if(action==='vehicles')return response({ok:true,...await service.open({bookingId,credential})});
   const text=await request.text();if(text.length>2048)return response({ok:false,error:'reliable_choice_invalid'},400);
   let body;try{body=JSON.parse(text);}catch{return response({ok:false,error:'invalid_json'},400);}
   if(!body||Array.isArray(body)||Object.keys(body).some(k=>!['vehicle_id','kind'].includes(k))||!id(body.vehicle_id)||!['exact','type'].includes(body.kind))return response({ok:false,error:'reliable_choice_invalid'},400);
   // The existing service reopens/rechecks the complete reliable set and uses
   // the company writer plus Room capacity; no client ETA is authoritative.
   const result=await service.choose({bookingId,credential,vehicleId:body.vehicle_id,kind:body.kind});
   return response(result,result.ok?200:409);
  }catch(error){return response({ok:false,error:/unauthorized|scope/.test(error.message)?'forbidden':'reliable_evidence_unavailable'},/unauthorized|scope/.test(error.message)?403:503);}
 }
 if(request.method!=='GET')return response({ok:false,error:'method_not_allowed'},405);
 const scope={tenant_id:url.searchParams.get('tenant_id'),company_id:url.searchParams.get('company_id')};
 if(!scopedId(scope.tenant_id)||!scopedId(scope.company_id))return response({ok:false,error:'scope_required'},400);
 const authorized=await authorizeCompany(request,url,env,scope);
 if(!authorized?.ok)return authorized?.response??response({ok:false,error:'forbidden'},403);
 if(authorized.auth_mode!=='admin_token'&&(!same(authorized.company_session,scope)||authorized.auth_mode!=='company_session'))return response({ok:false,error:'forbidden'},403);
 const prefix=`tenant:${scope.tenant_id}:company:${scope.company_id}:p12_dispatcher_queue:`;
 const page=await env.BOOKING_KV.list({prefix,limit:25,...(url.searchParams.get('cursor')?{cursor:url.searchParams.get('cursor')}:{} )}),rows=[];
 for(const key of (page.keys??[]).slice(0,25)){
  if(!key.name.startsWith(prefix))continue;
  const row=await env.BOOKING_KV.get(key.name,{type:'json'});
  if(!same(row,scope)||!id(row.booking_id))continue;
  const record=await env.BOOKING_KV.get('booking:'+row.booking_id,{type:'json'});
  if(!same(record,scope)||!record.p12_dispatcher_review)continue;
   const split=record.roundtrip_dispatch_mode==='split_no_wait',pending=split?(record.operational_legs??record.booking?.operational_legs??[]).filter(l=>!['completed','cancelled','stopped','no_show'].includes(String(l.status).toLowerCase())&&(!l.assigned_driver_id||!l.assigned_vehicle_id)).map(l=>l.leg_type):record.assigned_driver_id||record.assigned_vehicle_id?[]:['outbound'];
   if(!pending.length)continue;const assignmentLeg=pending[0];
  let fresh=[];
  if(!env.__reliableRegionalRoutes)fresh=(Array.isArray(row.candidates)?row.candidates:[]).slice(0,25).filter(c=>id(c.vehicle_id)&&id(c.driver_id)).map(c=>({vehicle_id:c.vehicle_id,driver_id:c.driver_id,eta_range_seconds:null,distance_meters:null,evidence_status:'refresh_required'}));
  if(typeof command==='function')try{const result=await command(scope,'shortlist',{bookingId:row.booking_id,leg:assignmentLeg});if(result?.ok)fresh=result.candidates??[];}catch{}
  let manual=[];
  if(!fresh.length&&typeof command==='function')try{const result=await command(scope,'manual_options',{bookingId:row.booking_id});if(result?.ok)manual=result.candidates??[];}catch{}
  // Queue documents can live24h, while route evidence is leased for15s.
  // Never promote a stored shortlist's km/ETA into current reliable evidence.
  // A future scoped refresh can supply them after checking graph/traffic again.
  rows.push({schema:'fluxidi-reliable-dispatcher-v1',...scope,booking_id:row.booking_id,assignment_leg:assignmentLeg,pending_legs:pending,
   reason:typeof row.reason==='string'?row.reason.slice(0,100):'evidence_unavailable',
   requested_vehicle:row.requested_vehicle?{kind:row.requested_vehicle.kind,vehicle_id:row.requested_vehicle.dispatcher_only?null:row.requested_vehicle.vehicle_id,category:row.requested_vehicle.category,vehicle_type:row.requested_vehicle.vehicle_type}:null,pickup_summary:row.pickup_summary,destination_summary:row.destination_summary,
   deadline_at:row.deadline_at,booking_revision:row.booking_revision,
   requirements:{passengers:record.p12_reliable_choice?.passengers,luggage:record.p12_reliable_choice?.luggage,capabilities:record.p12_reliable_choice?.capabilities??[]},
   candidates:fresh.filter(c=>id(c.vehicle_id)&&id(c.driver_id)&&(c.valid_until_ms>Date.now()||!env.__reliableRegionalRoutes&&c.evidence_status==='refresh_required')).slice(0,25),
    stops:(record.p12_reliable_choice?.request_context?.stops??record.payload?.stops??record.booking?.stops??[]).filter(v=>typeof v==='string').slice(0,6),
    return_info:reliableReturnInfoV1(record),
    manual_candidates:manual.filter(c=>id(c.vehicle_id)&&id(c.driver_id)).slice(0,25),warnings:fresh.length?[]:['NO_RELIABLE_CANDIDATE','ETA_UNCERTAIN_MANUAL_REVIEW'],
    manual_assignment_endpoint:'/bookings/'+row.booking_id+'/assign',manual_assignment_requires_existing_capacity_authority:true});
 }
 return response({ok:true,schema:'fluxidi-reliable-dispatcher-v1',items:rows,next_cursor:page.list_complete?null:page.cursor??null});
}

// Used by the existing dispatch event path. An accepted Reliable Choice
// booking must never accidentally reenter premium legacy selection.
export async function consumeReliablePublicDispatchV1(env,scope,body){
 if(!enabled(env)||typeof env.__reliableChoiceRuntime!=='function')return {ok:false,error:'reliable_local_runtime_required',status:503};
 const runtime=await env.__reliableChoiceRuntime({tenant_id:scope.tenant_id,company_id:scope.company_id});
 if(runtime?.kind!=='P12_LOCAL_SHADOW_ONLY')return {ok:false,error:'reliable_local_runtime_required',status:503};
 return runtime.consumeCoordinated(body);
}
