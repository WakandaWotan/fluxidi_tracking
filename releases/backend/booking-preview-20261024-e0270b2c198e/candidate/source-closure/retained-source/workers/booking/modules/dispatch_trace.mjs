import {mapboxDispatchAccessPhaseV1} from './mapbox_quote_request_v1.mjs';

// Outcome-only observer. Callers supply scalar, server-resolved context and
// already computed DTO fields, never an environment or I/O capability.
// failure() immediately reduces an exception to registered scalar codes only.
// This budget is per isolate (not a distributed rate limit); no timers/writes.
const outcomePending=new Map();
let outcomeWindowStart=0,outcomeWindowCount=0;
const outcomePhases=new Set(['request_entry','trial_ingress','writer_pause','routing','search_admission','route_dispatch','input_validation','scope_resolution','scope_normalization','authorization','company_policy','fleet','driver_index','presence',
 'commercial_route','tracking','duty','demand','manager_first','service_policy','quote_scope','quote_rows',
 'vehicle_projection','overlap','evaluation','response']);
const outcomeRouteBranches=new Set(['route_input_validation','no_route_required',
 'customer_mapbox_preparation','official_provider_preparation','official_regional_preparation']);
const outcomeCodes=new Set([
 'local_minimum_policy_required','mission_route_unavailable','mission_route_incomplete','local_municipality_unresolved','configured_money_policy_required','exception_day',
 'mapbox_quote_location_unbound','customer_route_provider_invalid',
 'dispatch_authority_vehicle_mismatch','driver_candidates_ready','driver_active_vehicle_ready','driver_vehicle_scope_conflict','driver_type_invalid','driver_vehicle_link_missing','partner_vehicle_owner_conflict',
 'manual_duty_ready','manual_duty_live_ready','manual_duty_missing','manual_duty_conflict',
 'dispatch_device_contract_unavailable','dispatch_device_lease_unavailable','dispatch_position_unavailable','dispatch_position_vehicle_mismatch',
 'manager_first','manual_quote_required','quote_only_day','financial_quote_failed','financial_quote_unavailable',
 'configured_money_policy_required','configured_tariff_required','vehicle_tariff_missing','vehicle_financial_route_policy_unproven',
 'airport_financial_floor_unproven','calculation_budget_exceeded','evidence_expired','evidence_integrity_failed','evidence_inputs_changed','evidence_tariff_changed',
 'staging_trial_configuration_required','staging_trial_operation_not_allowed','booking_writers_paused',
 'search_admission_unavailable','search_cancelled','driver_device_authority_unavailable','tracking_evidence_unavailable',
 'official_address_index_unavailable','driver_index_coordinator_failed','presence_coordinator_failed',
 'company_live_scope_invalid','street_occupancy_unavailable','capacity_snapshot_unavailable',
 'mission_tariff_invalid','mapbox_quote_scope_not_active','mapbox_quote_transport_not_configured','operating_policy_invalid',
 '', 'unauthorized','provider_dispatch_unavailable','pickup_coordinates_required','service_not_offered',
 'assignment_schedule_undeterminable','availability_failed','company_live_unavailable',
 'company_live_scope_mismatch','company_live_binding_unavailable','company_live_capacity_unavailable',
 'demand_index_unavailable','demand_index_missing','demand_index_invalid','missing_scope',
 'driver_index_recovery_pending','driver_index_scope_conflict','driver_index_read_failed',
 'quote_limiter_unavailable','rate_limited','booking_area_unverified','booking_area_not_served',
 'booking_area_unconfigured','reliable_route_evidence_unavailable','reliable_route_unreachable',
 'reliable_address_incomplete','reliable_address_invalid','reliable_address_access_forbidden',
 'reliable_road_access_confirmation_required','airport_route_context_required',
 'assignment_capacity','assignment_driver_no_vehicle','assignment_driver_inactive',
 'assignment_driver_blocked','assignment_driver_not_scheduled','assignment_driver_outside_hours',
 'assignment_driver_planned_break','assignment_driver_absent','assignment_driver_on_trip',
 'assignment_driver_offline','assignment_driver_not_live','assignment_driver_paused',
 'assignment_ride_after_hours','assignment_vehicle_busy','assignment_overlap',
 'assignment_availability_unknown','active_ride_end_unknown','eta_not_feasible',
 'vehicle_capacity_exceeded','live_location_unavailable','vehicle_unavailable',
 'no_suitable_vehicle','next_reservation_route_unavailable','vehicle_busy_with_next_reservation',
 'pickup_buffer_too_short','missing_vehicle_origin_location','origin_eta_not_feasible',
 'vehicle_cannot_reach_pickup_in_time','availability_pending',
]);
// Exact static codes from the sealed quote path and its direct financial/route guards.
// Never accept a runtime message merely because it looks like a code.
for(const code of ["acceptance_identity_missing","access_address_barrier_context_unproven","access_address_incomplete","access_address_parallel_ambiguity","access_gps_stale_or_accuracy","access_graph_attachment_changed","address_context_incomplete","address_graph_changed","airport_financial_floor_unproven","atomic_evidence_storage_required","availability_check_skipped","batch_vehicle_selection_conflict","booking_evidence_already_frozen","booking_evidence_missing","booking_evidence_reference_conflict","booking_evidence_reference_invalid","booking_evidence_reference_missing","booking_evidence_reference_unresolved","booking_financial_evidence_mismatch","booking_id_required","booking_requote_required","booking_reservation_policy_required","calculation_budget_exceeded","company_scope_unverified","company_service_unavailable","company_unavailable","configured_money_policy_required","configured_site_binding_unproven","customer_mapbox_mission_not_supported","customer_route_provider_invalid","evidence_expired","evidence_expiry_invalid","evidence_inputs_changed","evidence_integrity_failed","evidence_legs_invalid","evidence_money_invalid","evidence_points_invalid","evidence_scope_mismatch","evidence_scope_required","evidence_tariff_changed","evidence_value_invalid","financial_body_content_type","financial_body_limit","financial_body_required","financial_closure_integrity_failed","financial_contract_upgrade_required","financial_coordinate_alias_conflict","financial_currency_not_supported","financial_evidence_database_required","financial_evidence_storage_unavailable","financial_evidence_store_required","financial_evidence_write_failed","financial_historical_execution_held","financial_intent_closed","financial_intent_transition_conflict","financial_payment_amount_invalid","financial_payment_amount_mismatch","financial_price_consent_changed","financial_price_consent_required","financial_quote_owner_mismatch","financial_recovery_atomic_storage_required","financial_recovery_replay_required","financial_recovery_revision_changed","financial_recovery_storage_fence_required","financial_return_vehicle_alias_conflict","financial_route_not_certified","financial_route_points_required","financial_route_provider_invalid","financial_route_provider_not_approved","financial_route_retention_invalid","financial_sale_money_conflict","financial_sale_price_consent_changed","financial_sale_projection_invalid","financial_stop_binding_required","financial_transient_route_payload_not_allowed","financial_vehicle_alias_conflict","forbidden","gate_off","invalid_body","limousine_official_endpoint_binding","mapbox_operational_context_required","mapbox_quote_access_radius_invalid","mapbox_quote_access_runtime_unavailable","mapbox_quote_access_unavailable","mapbox_quote_access_unproven","mapbox_quote_area_ambiguous","mapbox_quote_area_context_required","mapbox_quote_area_country_invalid","mapbox_quote_area_point_mismatch","mapbox_quote_area_point_unbound","mapbox_quote_area_postcode_invalid","mapbox_quote_area_unavailable","mapbox_quote_bearing_invalid","mapbox_quote_context_changed","mapbox_quote_context_expired","mapbox_quote_context_required","mapbox_quote_endpoint_binding","mapbox_quote_geometry_binding","mapbox_quote_geometry_invalid","mapbox_quote_location_ambiguous","mapbox_quote_location_required","mapbox_quote_location_unbound","mapbox_quote_points_invalid","mapbox_quote_preview_invalid","mapbox_quote_request_binding_changed","mapbox_quote_request_configuration","mapbox_quote_request_limit","mapbox_quote_request_unproven","mapbox_quote_response_invalid","mapbox_quote_response_limit","mapbox_quote_route_inconsistent","mapbox_quote_scope_mismatch","mapbox_quote_scope_not_active","mapbox_quote_shared_budget_denied","mapbox_quote_stop_access_ambiguous","mapbox_quote_stop_binding","mapbox_quote_text_unbound","mapbox_quote_timeout","mapbox_quote_transport_error","mapbox_quote_transport_not_configured","mapbox_quote_waypoints_unproven","missing_pickup_time","mission_depot_required","mission_tariff_invalid","no_execution_started","official_address_index_changed","official_address_index_unavailable","official_address_position_changed","official_address_position_unusable","official_address_required","official_address_source_changed","official_municipality_required","private_chauffeur_tariff_missing","public_price_preview_invalid","public_price_preview_required","quote_already_accepted","rate_limited","reliable_choice_required","ride_input_required","route_config_missing","route_failed","route_not_usable","route_presentation_mode_invalid","separate_availability_required","service_not_offered","tenant_scope_conflict","unauthorized","vehicle_quote_limit","vehicle_quote_service_not_supported","vehicle_unavailable"])outcomeCodes.add(code);
const outcomeCode=value=>value==null?null:
 typeof value==='string'&&value.length<=100&&outcomeCodes.has(value)?value:'unclassified';

export function createAvailabilityOutcomeObserverV1(input={}) {
 try {
  const {enabled,hasScope,configuredScope,tenantId,companyId,mode,observationId,cfRay,startedAtMs}=input;
  const id=value=>typeof value==='string'&&/^[A-Za-z0-9_.-]{1,96}$/.test(value);
  const unresolved=input.allowUnresolvedScope===true&&hasScope!==true&&
   (configuredScope==='all'||typeof configuredScope==='string'&&configuredScope.split('/').length===2&&configuredScope.split('/').every(id));
  const scopeMatches=(t,c)=>configuredScope==='all'||configuredScope===t+'/'+c;
  let resolved=hasScope===true&&id(tenantId)&&id(companyId)&&scopeMatches(tenantId,companyId)?{tenantId,companyId}:null;
  let suppressed=false,failureCode=null,failureReason=null,exceptionCode=null;
  const functionName=input.functionName==='customer_vehicle_quotes'?'customer_vehicle_quotes':'partners_availability';
  let observedMode=mode,scheduledPolicy=null,decisionTruncated=false;const decisions=[],quoteContext=new Map();
  const candidateId=value=>typeof value==='string'&&/^[A-Za-z0-9_.-]{1,128}$/.test(value);
  let providerFlagReceived=['mapbox_v1','absent','not_observed'].includes(input.providerFlagReceived)?input.providerFlagReceived:'other_redacted';
  let routeBranch=functionName==='customer_vehicle_quotes'?'not_observed':'not_entered',providerMode=null;
  const version=typeof input.workerVersion==='string'&&/^[a-f0-9-]{36}$/.test(input.workerVersion)?input.workerVersion:null;
  if(enabled!==true||(!resolved&&!unresolved)||!['asap','later',...(functionName==='customer_vehicle_quotes'?['unknown']:[])].includes(mode)
   ||typeof observationId!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(observationId)
   ||!Number.isSafeInteger(startedAtMs)||startedAtMs<=0)return null;
  for(const [key,start] of outcomePending)if(startedAtMs-start>=60_000)outcomePending.delete(key);
  if(startedAtMs-outcomeWindowStart>=60_000){outcomeWindowStart=startedAtMs;outcomeWindowCount=0;}
  if(input.errorOnlyBudget!==true&&outcomeWindowCount>=60||outcomePending.size>=64||outcomePending.has(observationId))return null;
  if(input.errorOnlyBudget!==true)outcomeWindowCount++;
  outcomePending.set(observationId,startedAtMs);
  const ray=typeof cfRay==='string'&&/^[a-f0-9]{16}(?:-[A-Z]{3})?$/.test(cfRay)?cfRay:null;
  let phase=unresolved?'request_entry':'authorization',finished=false;
  return Object.freeze({
   stage(value){try{if(!finished&&outcomePhases.has(value))phase=value;}catch{}},
   mode(value){try{if(!finished&&functionName==='customer_vehicle_quotes'&&['asap','later','unknown'].includes(value))observedMode=value;}catch{}},
   pricePolicy(value){try{if(!finished)scheduledPolicy=['manager_first','existing'].includes(value)?value:'unclassified';}catch{}},
   providerFlag(value){try{if(!finished&&functionName==='customer_vehicle_quotes')providerFlagReceived=['mapbox_v1','absent'].includes(value)?value:'other_redacted';}catch{}},
   decision(row){try{
    if(finished||!resolved||input.includeVehicles===false||!candidateId(row?.candidate_id)||!['duty_projection','live_projection','driver_relation','driver_candidates','active_vehicle_link','dispatch_driver_filter'].includes(row.phase))return;
    // Keep the existing bounded accumulator, coalesced by vehicle. Seven duty
    // rows must not consume the budget before candidate/eligibility is reached.
    let record=decisions.find(d=>d.candidate_id===row.candidate_id);
    if(!record){if(decisions.length>=10){decisionTruncated=true;return;}record={candidate_id:row.candidate_id};decisions.push(record);}
    record.phase=row.phase;record.reason=outcomeCode(row.reason);
    if(candidateId(row.driver_id))record.driver_id=row.driver_id;
    if(row.phase==='duty_projection')record.duty_reason=record.reason;
    if(row.phase==='live_projection')record.live_reason=record.reason;
    if(['initial_selection','arrival_recheck','airport_recheck','allocator_selection','capacity_selection'].includes(row.evaluation_stage))record.evaluation_stage=row.evaluation_stage;
    for(const k of ['lease_valid','gps_fresh','vehicle_match'])if(typeof row[k]==='boolean')record[k]=row[k];
    for(const k of ['linked_driver_ids','linked_vehicle_ids'])if(Array.isArray(row[k])){
      record[k]=row[k].filter(candidateId).slice(0,4);
      if(row[k].length>4)record.links_truncated=true;
    }
    if(row.phase==='driver_relation'){
      record.relation_rejections??=[];
      if(record.relation_rejections.length<4&&candidateId(row.driver_id))record.relation_rejections.push({driver_id:row.driver_id,reason:record.reason});
      else record.links_truncated=true;
    }
    if(['empty_candidates','no_active_vehicle'].includes(row.producer))record.producer=row.producer;
    else if(row.phase==='driver_candidates'||row.phase==='active_vehicle_link')delete record.producer;
    if(!record.exclusion_phase&&record.reason&&!['manual_duty_ready','manual_duty_live_ready','driver_candidates_ready','driver_active_vehicle_ready'].includes(record.reason))record.exclusion_phase=row.phase;
   }catch{}},
   quoteResult(vehicleId,row){try{
    if(finished||!resolved||!candidateId(vehicleId)||quoteContext.size>=10&&!quoteContext.has(vehicleId))return;
    const record=quoteContext.get(vehicleId)??{};
    if(Number.isInteger(row?.http_status)&&row.http_status>=100&&row.http_status<=599)record.quote_http_status=row.http_status;
    for(const k of ['request_quote_required','booking_allowed','financial_quote_present'])if(typeof row?.[k]==='boolean')record[k]=row[k];
    quoteContext.set(vehicleId,record);
   }catch{}},
   quoteFailure(vehicleId,error){try{
    if(finished||!resolved||!candidateId(vehicleId)||quoteContext.size>=10&&!quoteContext.has(vehicleId))return;
    let code=null,reason=null;try{code=outcomeCode(error?.code);}catch{}try{reason=outcomeCode(error?.message);}catch{}
    const record=quoteContext.get(vehicleId)??{};
    record.exception_code=[code,reason].find(v=>v&&v!=='unclassified')??'unclassified';quoteContext.set(vehicleId,record);
   }catch{}},
   routeBranch(value,mode){try{
    if(!finished&&outcomeRouteBranches.has(value)){routeBranch=value;providerMode=mode==='provider_automatic'?mode:null;}
   }catch{}},
   resolvedScope(scope){try{
    if(finished)return;
    if(scope?.hasScope===true&&id(scope.tenant_id)&&id(scope.company_id)&&scopeMatches(scope.tenant_id,scope.company_id))resolved={tenantId:scope.tenant_id,companyId:scope.company_id};
    else {resolved=null;suppressed=true;}
   }catch{resolved=null;suppressed=true;}},
   failure(error){try{
    exceptionCode='unclassified';let code=null,message=null;
    try{code=error?.code;}catch{}try{message=error?.message;}catch{}
    failureCode=outcomeCode(code);failureReason=outcomeCode(message);
    // Exact registered identifiers only; never serialize an exception or accept
    // an arbitrary string merely because it resembles an internal error code.
    for(const value of [failureCode,failureReason])if(value&&value!=='unclassified'){exceptionCode=value;break;}
   }catch{}},
   finish(outcome,nowMs){
    try {
     if(finished)return null;finished=true;
     if(suppressed||!outcomePending.has(observationId)||!Number.isSafeInteger(nowMs)
      ||nowMs<startedAtMs||nowMs-startedAtMs>=60_000
      ||!(outcome?.status===null&&outcome?.completion==='exception_no_response')&&(!Number.isInteger(outcome?.status)||outcome.status<100||outcome.status>599))return null;
     if(input.errorOnlyBudget===true){
      if(outcome.status!==null&&outcome.status<400)return null;
      if(nowMs-outcomeWindowStart>=60_000){outcomeWindowStart=nowMs;outcomeWindowCount=0;}
      if(outcomeWindowCount>=60)return null;
      outcomeWindowCount++;
     }
     const rows=outcome.vehicles,vehicles=[];
     if(input.includeVehicles!==false&&Array.isArray(rows))for(let i=0;i<Math.min(rows.length,10);i++){
      const row=rows[i];if(!row||typeof row!=='object')continue;
      vehicles.push({row:i+1,...(candidateId(row.vehicle_id)?{vehicle_id:row.vehicle_id}:{}),available:typeof row.available==='boolean'?row.available:null,reason:outcomeCode(row.reason)});
     }
     const event={schema:'availability-outcome-v1',observation_id:observationId,cf_ray:ray,
      tenant_id:resolved?.tenantId??null,company_id:resolved?.companyId??null,
      scope_state:resolved?'server_resolved':'not_resolved',mode:observedMode,timestamp_ms:nowMs,http_status:outcome.status,phase,
      server_request_id:observationId,request_id_source:'server_generated',worker_version:version,
      function:functionName,classification:outcome.status===null?'technical_failure':outcome.status>=500?
       outcome.error==='booking_writers_paused'?'policy_refusal':'technical_failure':outcome.status>=400?'policy_refusal':'availability_result',
      error_state:outcome.error==null?'absent':outcomeCode(outcome.error)==='unclassified'?'redacted_unknown':'registered',
      code_state:outcome.code==null?'absent':outcomeCode(outcome.code)==='unclassified'?'redacted_unknown':'registered',
      reason_state:outcome.reason==null?'absent':outcomeCode(outcome.reason)==='unclassified'?'redacted_unknown':'registered',
      internal_code:failureCode,internal_reason:failureReason,
      provider_flag_received:providerFlagReceived,booking_mode:observedMode,provider_mode:providerMode,
      effective_route_branch:routeBranch,exception_code:exceptionCode,
      error:outcomeCode(outcome.error),code:outcomeCode(outcome.code),reason:outcomeCode(outcome.reason),
      vehicles_evaluated:Array.isArray(rows),vehicles_truncated:Array.isArray(rows)&&
       (rows.length>10||Number.isSafeInteger(outcome.vehicleCount)&&outcome.vehicleCount>10),vehicles};
     if(decisions.length){event.decisions=decisions;event.decisions_truncated=decisionTruncated;}
     if(functionName==='customer_vehicle_quotes'&&input.includeVehicles!==false){
      event.scheduled_dispatch_policy=scheduledPolicy;event.quotes=[];
      const policyCodes=new Set(['manager_first','manual_quote_required','quote_only_day']);
      const availabilityCodes=new Set(['vehicle_unavailable','assignment_capacity','assignment_vehicle_busy','assignment_overlap']);
      const technicalCodes=new Set(['financial_quote_failed','financial_quote_unavailable','configured_money_policy_required','configured_tariff_required','vehicle_tariff_missing','vehicle_financial_route_policy_unproven','airport_financial_floor_unproven','calculation_budget_exceeded','evidence_expired','evidence_integrity_failed','evidence_inputs_changed','evidence_tariff_changed','reliable_route_evidence_unavailable','mapbox_quote_location_unbound','route_failed','route_not_usable','financial_route_not_certified','mission_tariff_invalid']);
      for(const row of (Array.isArray(outcome.quotes)?outcome.quotes:[]).slice(0,10)){
       if(!candidateId(row?.vehicle_id))continue;const reason=outcomeCode(row.reason),status=['priced','quote_required','unavailable'].includes(row.status)?row.status:'unclassified';
       event.quotes.push({vehicle_id:row.vehicle_id,status,outcome:status,reason,quote_attempted:quoteContext.has(row.vehicle_id),...(quoteContext.get(row.vehicle_id)??{}),
        classification:status==='priced'?'priced':reason==null||reason==='unclassified'?'unclassified':policyCodes.has(reason)?'policy_refusal':availabilityCodes.has(reason)?'no_availability':status==='quote_required'&&(quoteContext.get(row.vehicle_id)?.request_quote_required===true)&&reason==='financial_quote_unavailable'?'unclassified':technicalCodes.has(reason)?'technical_failure':'unclassified'});
      }
      event.quotes_truncated=Array.isArray(outcome.quotes)&&outcome.quotes.length>10;
     }
     // Never lose the complete event when bounded extra details exceed its budget.
     while(JSON.stringify(event).length>4000&&event.decisions?.length){event.decisions.pop();event.decisions_truncated=true;}
     while(JSON.stringify(event).length>4000&&event.quotes?.length){event.quotes.pop();event.quotes_truncated=true;}
     while(JSON.stringify(event).length>4000&&event.vehicles.length){event.vehicles.pop();event.vehicles_truncated=true;}
     return JSON.stringify(event).length<=4000?event:null;
    }catch{return null;}finally{outcomePending.delete(observationId);}
   },
  });
 }catch{return null;}
}

// One immutable preparation owns this bounded diagnostic accumulator.
export function logDispatchDetail(context,...args){
 if(!context?.sampleDispatchDetails){console.log(...args);return;}
 const trace=context.dispatchTrace ||= {total:0,sampled:0,tags:Object.create(null)};
 trace.total++;
 const tag=String(args[0]||'').match(/^\[[A-Z0-9_]+\](?:\[[A-Z0-9_]+\])?/)?.[0]||'[OTHER]';
 if(Object.hasOwn(trace.tags,tag)||Object.keys(trace.tags).length<64)trace.tags[tag]=(trace.tags[tag]||0)+1;
 if(trace.sampled<4){trace.sampled++;console.log('[DISPATCH][DETAIL_SAMPLE]',tag);}
}
export function finishDispatchTrace(context){if(context?.dispatchTrace)console.log('[DISPATCH][DETAIL_COUNTS]',context.dispatchTrace);}

// Private suffix for the existing ETA_CANDIDATE log, never a response field.
// Only the authenticated availability handler creates this request-owned sink.
const evaluatorContexts=new WeakMap(),evaluatorAttempts=new WeakMap();
const originValues={
 company_live_status:new Set(['unavailable','present','scope_mismatch','read_error','no_reliable_live_vehicle','invalid_location','binding_unavailable']),
 tracking_status:new Set(['not_needed','unavailable','present','binding_unavailable','no_usable_record']),
 current_origin_status:new Set(['no_live_origin','invalid_location','capture_missing_or_invalid','capture_outside_window','accepted']),
};
const originSources=new Set(['company_live','tracking_ping','previous_reservation_dropoff','last_completed_dropoff','vehicle_inventory',
 'vehicle_base','vehicle_last_location','vehicle_configured_base','company_configured_depot','company_business_base','unavailable']);
const timePhases=new Set(['gps_capture_missing','gps_capture_invalid','gps_capture_future','gps_capture_expired',
 'operational_lease_expired','gps_check_entry','gps_check_before_access','gps_check_cached','gps_check_access','gps_check_provider','gps_check_after_provider']);
const gpsStates=new Set(['valid','not_applicable','missing','invalid','future','expired','unknown']);
const leaseStates=new Set(['valid','expired','unknown']);

export function createAvailabilityEvaluatorDiagnosticV1(env,request,scope){
 try{
  if(env?.AVAILABILITY_EVALUATOR_DIAGNOSTICS_ENABLED!=='1'||scope?.hasScope!==true
   ||env.AVAILABILITY_EVALUATOR_DIAGNOSTICS_SCOPE!==scope.tenant_id+'/'+scope.company_id)return null;
  const vehicle=env.AVAILABILITY_EVALUATOR_DIAGNOSTICS_VEHICLE,ray=request.headers.get('cf-ray');
  if(typeof vehicle!=='string'||!/^[A-Za-z0-9_-]{1,96}$/.test(vehicle)
   ||!ray||!/^[a-f0-9]{16}(?:-[A-Z]{3})?$/.test(ray)||request.method!=='GET')return null;
  const url=new URL(request.url);
  if(url.pathname!=='/partners/availability'||url.searchParams.get('asap')!=='true'
   ||url.searchParams.get('booking_mode')!=='provider_automatic')return null;
  const context=Object.freeze({begin:id=>beginAvailabilityEvaluatorDiagnosticV1(context,id)});
  evaluatorContexts.set(context,{vehicle,ray,count:0});return context;
 }catch{return null;}
}
export function beginAvailabilityEvaluatorDiagnosticV1(context,vehicleId){
 try{
  const owner=evaluatorContexts.get(context);
  if(!owner||owner.vehicle!==vehicleId||owner.count>=6)return null;
  const attempt=Object.freeze({
   origin:(field,value)=>observeAvailabilityOriginV1(attempt,field,value),
   route:observation=>observeAvailabilityRouteV1(attempt,observation),
   fields:values=>availabilityEvaluatorLogFieldsV1(attempt,values),
  });
  evaluatorAttempts.set(attempt,{ray:owner.ray,vehicle:owner.vehicle,sequence:++owner.count,
   origin:{},phases:new Set(),gps_status:'unknown',lease_status:'unknown',stage:'unknown',emitted:false});
  return attempt;
 }catch{return null;}
}
export function observeAvailabilityOriginV1(attempt,field,value){
 try{const saved=evaluatorAttempts.get(attempt);if(saved&&!saved.emitted&&originValues[field]?.has(value))saved.origin[field]=value;}catch{}
}
export function observeAvailabilityRouteV1(attempt,observation){
 try{
  const saved=evaluatorAttempts.get(attempt);if(!saved||saved.emitted)return;
  if(gpsStates.has(observation.gps_status))saved.gps_status=observation.gps_status;
  if(leaseStates.has(observation.lease_status))saved.lease_status=observation.lease_status;
  if(timePhases.has(observation.stage))saved.stage=observation.stage;
  if(Array.isArray(observation.phases))for(const phase of observation.phases.slice(0,32))
   if(timePhases.has(phase)&&saved.phases.size<10)saved.phases.add(phase);
 }catch{}
}
export function availabilityEvaluatorLogFieldsV1(attempt,{origin,travel}={}){
 try{
  const saved=evaluatorAttempts.get(attempt);if(!saved||saved.emitted)return '';
  saved.emitted=true;
  const source=originSources.has(origin?.source)?origin.source:'unknown';
  const status=saved.origin.current_origin_status??'unknown';
  const selection=['company_live','tracking_ping'].includes(source)?'selected_live'
   :['previous_reservation_dropoff','last_completed_dropoff'].includes(source)?'previous_dropoff'
   :['unavailable','unknown'].includes(source)?'unavailable'
   :source==='company_business_base'&&status==='no_live_origin'?'fallback_no_live_origin'
   :source==='company_business_base'&&status!=='accepted'&&status!=='unknown'?'fallback_rejected_live_origin':'other_known_origin';
  return ' evaluator='+JSON.stringify({schema:'availability-evaluator-v1',cf_ray:saved.ray,vehicle_id:saved.vehicle,
   evaluation_sequence:saved.sequence,route_error_code:mapboxDispatchAccessPhaseV1({message:travel?.route_error_code})??'unknown',
   origin_source:source,origin_selection_reason:selection,origin_has_location:origin?.has_location===true,
   origin_age_seconds:Number.isFinite(origin?.age_seconds)?Math.min(86400,Math.max(0,Math.round(origin.age_seconds))):null,
   company_live_status:saved.origin.company_live_status??'unknown',tracking_status:saved.origin.tracking_status??'unknown',
   current_origin_status:status,gps_status:saved.gps_status,lease_status:saved.lease_status,
   route_time_stage:saved.stage,phases:[...saved.phases]});
 }catch{return '';}
}

// Own the existing observer for the whole availability fetch, including ingress.
// Same event schema/emitter/budgets. No response reads, storage, provider or timers.
export async function observeAvailabilityOutcomeRequestV1(request,env,run){
 let observer=null,capture=null,outcome=null,details=false,isQuote=false;
 try{
  if(env?.AVAILABILITY_OUTCOME_DIAGNOSTICS_ENABLED==='1'){
   const url=new URL(request.url),configuredScope=env.AVAILABILITY_OUTCOME_DIAGNOSTICS_SCOPE;
   isQuote=url.pathname==='/public/customer/vehicle-quotes'&&request.method==='POST';
   const availability=url.pathname==='/partners/availability'&&request.method==='GET';
   const parts=typeof configuredScope==='string'?configuredScope.split('/'):[];
   const target=parts.length===2&&parts.every(v=>/^[A-Za-z0-9_.-]{1,96}$/.test(v));
   const aliases=[...url.searchParams.getAll('partner_id'),...url.searchParams.getAll('partnerId')];
   const detailScope=env.AVAILABILITY_OUTCOME_DIAGNOSTICS_DETAIL_SCOPE;
   const detailParts=typeof detailScope==='string'?detailScope.split('/'):[];
   const detailConfigured=env.AVAILABILITY_OUTCOME_DIAGNOSTICS_DETAILS_ENABLED==='1'&&detailParts.length===2&&detailParts.every(v=>/^[A-Za-z0-9_.-]{1,96}$/.test(v));
   const detailSelected=configuredScope==='all'&&detailConfigured&&(isQuote||aliases.length>0&&aliases.every(v=>v==='company:'+detailParts[0]+':'+detailParts[1]));
   if((availability&&(configuredScope==='all'||target&&aliases.length>0&&aliases.every(v=>v==='company:'+parts[0]+':'+parts[1])))||isQuote&&detailSelected){
    details=!isQuote&&configuredScope!=='all';
    observer=createAvailabilityOutcomeObserverV1({enabled:true,hasScope:false,allowUnresolvedScope:true,
     configuredScope,mode:isQuote?'unknown':url.searchParams.get('asap')==='true'?'asap':'later',
     functionName:isQuote?'customer_vehicle_quotes':'partners_availability',
     providerFlagReceived:isQuote?'not_observed':!url.searchParams.has('customer_route_provider')?'absent':url.searchParams.get('customer_route_provider')==='mapbox_v1'?'mapbox_v1':'other_redacted',
     observationId:crypto.randomUUID(),cfRay:request.headers.get('cf-ray'),startedAtMs:Date.now(),
     workerVersion:env.WORKER_VERSION_METADATA?.id,includeVehicles:details||detailSelected,
     errorOnlyBudget:configuredScope==='all'&&!detailSelected});
    if(observer)capture=Object.freeze({stage:observer.stage,routeBranch:observer.routeBranch,mode:observer.mode,providerFlag:observer.providerFlag,
     resolvedScope(scope){observer.resolvedScope(scope);if(configuredScope==='all')details=detailSelected&&scope?.hasScope===true&&scope.tenant_id+'/'+scope.company_id===detailScope;},
     failure:observer.failure,decision(row){if(details)observer.decision(row);},
     pricePolicy(value){if(details)observer.pricePolicy(value);},
     quoteResult(vehicle,row){if(details)observer.quoteResult(vehicle,row);},
     quoteFailure(vehicle,error){if(details)observer.quoteFailure(vehicle,error);},
     outcome(body){try{
      outcome={error:outcomeCode(body?.error),code:outcomeCode(body?.code),reason:outcomeCode(body?.reason)};
      if(details&&Array.isArray(body?.vehicles))outcome={...outcome,vehicleCount:body.vehicles.length,
       vehicles:body.vehicles.slice(0,10).map(row=>({vehicle_id:row?.vehicle_id,available:typeof row?.available==='boolean'?row.available:null,reason:outcomeCode(row?.reason)}))};
      if(details&&Array.isArray(body?.quotes))outcome={...outcome,quotes:body.quotes.slice(0,11).map(row=>({vehicle_id:row?.vehicle_id,status:row?.status,reason:outcomeCode(row?.reason)}))};
     }catch{outcome=null;}}
    });
   }
  }
 }catch{}
 let response;
 try{response=await run(capture);return response;}
 catch(error){observer?.failure(error);throw error;}
 finally{try{
  const event=observer?.finish({...outcome,status:response?.status??null,...(response?{}:{completion:'exception_no_response'})},Date.now());
  if(event&&(details||!isQuote&&(event.http_status===null||event.http_status>=400))){
   const payload=JSON.stringify({...event,diagnostic_level:details?'detail':'basic'});
   if(payload.length<=4096)console.log('[AVAILABILITY][OUTCOME]',payload);
  }
 }catch{}}
}
