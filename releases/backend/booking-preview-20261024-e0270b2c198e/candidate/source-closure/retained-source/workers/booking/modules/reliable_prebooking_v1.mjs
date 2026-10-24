import {RELIABLE_CHOICE_V1,reliableCandidatePageV1,generateReliableCandidatesV1} from './reliable_candidate_v1.mjs';
import {financialQuoteInputs} from './financial_quote_lifecycle.mjs';
import {operationalRoutingInstalledV1} from './reliable_operational_routes_v1.mjs';
import {classifyAddressAccessFailureV1} from './address_access_errors_v1.mjs';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
export const reliableChoiceEnabled=env=>env.ENVIRONMENT==='local'&&env.RELIABLE_CHOICE_LOCAL_ENABLED==='1'||operationalRoutingInstalledV1(env);
// Preserve the original export for existing consumers and sealed fixtures.
export const reliableLocalEnabled=reliableChoiceEnabled;
const hash=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))),b=>b.toString(16).padStart(2,'0')).join('');
export function reliableRequiredCapabilitiesV1(body){
 const declared=body.required_capabilities??body.capabilities??[],special=body.special_requirements??[];
 if(!Array.isArray(declared)||!Array.isArray(special)||declared.length+special.length>32||[...declared,...special].some(c=>typeof c!=='string'||!/^[a-z0-9_:-]{1,64}$/.test(c)))throw Error('reliable_requirements_invalid');
 const flags=['wheelchair','child_seat'].filter(k=>body[k]===true||typeof body[k]==='number'&&body[k]>0);
 return [...new Set([...declared,...special,...flags])].sort();
}
export function reliableRequestInputs(body){
 let f;try{f=financialQuoteInputs(body);}catch{throw Error('reliable_selection_inputs_changed');}const asap=body.pickup_mode==='asap';
 // Time and selected vehicle affect checkout, but an ASAP display lease is not
 // an appointment or a capacity claim. All other price/policy inputs are bound.
 const {vehicle,driver,category,date,time,pricing_options,...rest}=f;
 const options=Object.fromEntries(Object.entries(pricing_options).filter(([k])=>!['pickup_iso','pickup_mode'].includes(k)));
 const operational=Object.fromEntries(['pickup_input','destination_input','return_pickup_input','return_destination_input','from_address_context','to_address_context'].filter(k=>body[k]!==undefined).map(k=>[k,body[k]]));
 return {...rest,...(Object.keys(operational).length?{operational_inputs:operational}:{}),pricing_options:options,pickup_mode:asap?'asap':'scheduled',...(asap?{}:{date,time,pickup_iso:body.pickup_iso}),
  capabilities:reliableRequiredCapabilitiesV1(body),vehicle_category:body.vehicle_category??null,stop_coordinates:body.stop_coordinates??[],return_stop_coordinates:body.return_stop_coordinates??[]};
}
export function reliableCandidateObservationsV1(candidates,scope,observedAt,rejected=[]){
 const reasons=new Set(['stale_location','graph_ambiguity','stale_evidence','graph_unavailable','location_unavailable']);
 const failed=new Set(rejected.filter(r=>reasons.has(r.reason)).map(r=>r.vehicle_id));
 return (candidates??[]).filter(c=>failed.has(c.vehicle?.vehicle_id)&&same(c,scope)&&same(c.driver,scope)&&same(c.vehicle,scope)).slice(0,10).map(c=>{
  const gps=c.driver.gps??{},at=gps.capturedAt;
  return {vehicle_id:c.vehicle.vehicle_id,driver_id:c.driver.driver_id,observed_at_ms:observedAt,
   captured_at_ms:Number.isFinite(at)?at:null,gps_age_ms:Number.isFinite(at)&&at<=observedAt?observedAt-at:null,
   accuracy_meters:Number.isFinite(gps.accuracyMeters)?gps.accuracyMeters:null,
   publisher_context_bound:typeof gps.access?.continuityKey==='string'&&gps.access.continuityKey.length>0};
 });
}
export async function openReliableRequestV1({env,scope,customerId,body,loadSnapshot,clock=Date.now}){
 if(!reliableLocalEnabled(env)||!customerId)throw Error('reliable_local_runtime_required');
 if(body.pickup_mode!=='asap')throw Error('reliable_request_asap_required');
 const inputs=reliableRequestInputs(body),token=crypto.randomUUID(),record={...scope,...body,booking_id:'RC-'+token,customer_id:customerId,status:'DRAFT',booking:{...body},pickup_mode:'asap',pickup_iso:new Date(clock()).toISOString()};
 const reasonCode=value=>typeof value==='string'&&/^[a-z][a-z0-9_]{0,99}$/.test(value)?value:'candidate_evaluation_failed';
 let snapshot,list,inputFailure=null;try{snapshot=await loadSnapshot(record,record.booking_id);list=await generateReliableCandidatesV1({...snapshot,clock});}catch(error){
  const reason=reasonCode(error?.message);list={rows:[],rejected:[],escalationReason:reason};
  // A whole-journey input failure is not an evaluated empty driver fleet.
  // Keep its coded private diagnosis, but issue no usable selection token or
  // dispatcher fallback. Per-driver GPS/route rejections remain ordinary rows.
  // Preserve the existing explicit dispatcher-only path for a region outside
  // published routing coverage. It creates no vehicle/ETA/automatic match.
  // Other technical failures are not a successful evaluated empty fleet.
  inputFailure=reason==='operational_region_uncovered'||error?.dispatcherOnlyReason==='operational_region_uncovered'?null:classifyAddressAccessFailureV1(error)??{status:503,body:{ok:false,error:'reliable_evidence_unavailable'}};
 }
 const dispatcherOnly=list.rows.length===0;
 // Retain bounded original-sample evidence in this SAME private 15-minute
 // lease. No extra KV operation, GPS history, coordinate or session token.
 // Public responses and all candidate eligibility checks remain unchanged.
 const observation_samples=reliableCandidateObservationsV1(snapshot?.candidates,scope,clock(),list.rejected??[]);
 const candidate_diagnostics={input_count:list.counters?.inputCandidates??snapshot?.candidates?.length??0,visible_count:list.rows.length,reason:list.escalationReason==null?null:reasonCode(list.escalationReason),...(observation_samples.length?{observation_samples}:{}),rejected:(list.rejected??[]).slice(0,100).map(r=>({vehicle_id:typeof r.vehicle_id==='string'&&/^[a-zA-Z0-9_.:-]{1,128}$/.test(r.vehicle_id)?r.vehicle_id:null,reason:reasonCode(r.reason),...(r.route_reason?{route_reason:reasonCode(r.route_reason)}:{})}))};
 await env.BOOKING_KV.put(`tenant:${scope.tenant_id}:company:${scope.company_id}:reliable_request:${token}`,JSON.stringify({...scope,customer_id:customerId,inputs,body,dispatcher_only:dispatcherOnly&&!inputFailure,request_contract:snapshot?.request??null,candidate_diagnostics,createdAt:clock(),expiresAt:clock()+900000}),{expirationTtl:900});
 if(inputFailure)return inputFailure.body;
 return {ok:true,...(list.rows.length?reliableCandidatePageV1(list,{now:clock()}):{schema:RELIABLE_CHOICE_V1,vehicles:[],estimate:true,status:'dispatcher_review'}),selection_token:token,...(snapshot?.request?.journey?.address_context?{address_context:snapshot.request.journey.address_context}:{}),...(snapshot?.returnList?{return_vehicles:snapshot.returnList.rows.slice(0,10).map(r=>({...reliableCandidatePageV1({...snapshot.returnList,rows:[r],validUntil:r.validUntil},{now:clock()}).vehicles[0],return_availability:'available_for_return_time'}))}:{})};
}
export async function validateReliableRequestV1({env,scope,customerId,body,loadSnapshot,clock=Date.now}){
 const choice=body.reliable_choice;
 if(!choice||Object.keys(choice).some(k=>!['selection_token','vehicle_id','kind'].includes(k))||!['exact','type','dispatcher'].includes(choice.kind)||(choice.kind!=='dispatcher'&&(typeof choice.vehicle_id!=='string'||!/^[a-zA-Z0-9_.:-]{1,128}$/.test(choice.vehicle_id)))||(choice.kind==='dispatcher'&&choice.vehicle_id!==undefined)||!/^[a-f0-9-]{36}$/.test(choice.selection_token??''))throw Error('reliable_choice_invalid');
 const key=`tenant:${scope.tenant_id}:company:${scope.company_id}:reliable_request:${choice.selection_token}`,lease=await env.BOOKING_KV.get(key,{type:'json'});
 if(!same(lease,scope)||lease.customer_id!==customerId||lease.createdAt>clock()||lease.expiresAt<=clock())throw Error('reliable_selection_expired');
 if(await hash(JSON.stringify(lease.inputs))!==await hash(JSON.stringify(reliableRequestInputs(body))))throw Error('reliable_selection_inputs_changed');
 if(choice.kind==='dispatcher'){
  if(lease.dispatcher_only!==true)throw Error('reliable_dispatcher_request_not_allowed');
  return {schema:RELIABLE_CHOICE_V1,kind:'type',vehicle_id:'unresolved',category:lease.request_contract?.category??String(body.tier??'comfort').toLowerCase(),startedAt:clock(),passengers:Number(body.pax??1),luggage:Number(body.bags??0),capabilities:reliableRequiredCapabilitiesV1(body),selection_token:choice.selection_token,dispatcher_only:true,
   request_context:structuredClone(lease.body)};
 }
 let snapshot;try{snapshot=await loadSnapshot({...scope,...body,booking_id:'RC-'+choice.selection_token,customer_id:customerId,status:'DRAFT',booking:{...body},pickup_mode:'asap',pickup_iso:new Date(clock()).toISOString()},'RC-'+choice.selection_token);}catch(error){const failure=classifyAddressAccessFailureV1(error);if(failure?.status===422)throw Error('reliable_selection_candidate_changed');throw error;}
 const list=await generateReliableCandidatesV1({...snapshot,clock});
 const previous=lease.request_contract?.journey,current=snapshot.request.journey;
 const signature=j=>JSON.stringify({graph:j?.graphVersion,revision:j?.evidenceRevision,edges:j?.evidence?.map(e=>[e.leg,e.index,e.evidenceId,e.addressContext?.id??null])});
 if(!previous||signature(previous)!==signature(current))throw Error('reliable_selection_candidate_changed');
 if(body.address_context_id!==undefined&&body.address_context_id!==current.address_context?.id)throw Error('reliable_selection_candidate_changed');
 const selected=list.rows.find(r=>r.vehicle_id===choice.vehicle_id);
 if(!selected)throw Error('reliable_selected_vehicle_unavailable');
 return {schema:RELIABLE_CHOICE_V1,kind:choice.kind,vehicle_id:selected.vehicle_id,category:selected.category,vehicle_type:selected.vehicleType,startedAt:clock(),
  passengers:snapshot.request.passengers,luggage:snapshot.request.luggage,capabilities:[...(snapshot.request.capabilities??[])],selection_token:choice.selection_token,
  route_evidence_id:selected.routeEvidenceId,graph_version:selected.graphVersion,journey:structuredClone(snapshot.request.journey),return_choice:snapshot.returnList?{kind:body.return_vehicle_id||body.preferred_return_vehicle_id?'exact':'type',vehicle_id:body.return_vehicle_id??body.preferred_return_vehicle_id??snapshot.returnList.rows[0]?.vehicle_id,category:snapshot.returnList.rows.find(r=>r.vehicle_id===(body.return_vehicle_id??body.preferred_return_vehicle_id??snapshot.returnList.rows[0]?.vehicle_id))?.category}:null,
  request_context:Object.fromEntries(['pickup_input','destination_input','return_pickup_input','return_destination_input','from_address_context','to_address_context','service_category','airport_iata','airportIata','airport_transfer','booking_type','booking_source','return_enabled','return_date','return_time','return_from','return_to','return_stops','stops','stop_coordinates','return_stop_coordinates','return_pickup_iso','return_from_lat','return_from_lng','return_to_lat','return_to_lng','wait_min','child_seat','wheelchair','special_requirements'].filter(k=>body[k]!==undefined).map(k=>[k,structuredClone(body[k])]))};
}
