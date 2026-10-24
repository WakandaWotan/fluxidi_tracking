import {RELIABLE_CHOICE_V1} from './reliable_candidate_v1.mjs';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const clone=v=>structuredClone(v);
export const CHOICE_CYCLE_POLICY_V1=Object.freeze({maxOffers:5,totalWaitMs:60000,offerResponseMs:30000});
// Pure state transitions; the existing canonical dispatch writer/Room owns all
// claims and confirmation. This module never assigns a driver by itself.
export function beginReliableChoiceV1({scope,bookingId,bookingRevision,choice,candidates,now,policy={}}){
 const p={...CHOICE_CYCLE_POLICY_V1,...policy};
 if(!scope?.tenant_id||!scope.company_id||!bookingId||!Number.isSafeInteger(bookingRevision)||bookingRevision<1||!Number.isFinite(now)
  ||!['exact','type'].includes(choice?.kind)||!choice.vehicle_id||choice.kind==='type'&&!choice.category||!Number.isSafeInteger(p.maxOffers)||p.maxOffers<1||p.maxOffers>20
  ||!Number.isSafeInteger(p.totalWaitMs)||p.totalWaitMs<30000||p.totalWaitMs>120000||!Number.isSafeInteger(p.offerResponseMs)||p.offerResponseMs<1000||p.offerResponseMs>30000)throw Error('reliable_choice_invalid');
 const state={schema:RELIABLE_CHOICE_V1,...clone(scope),bookingId,bookingRevision,choice:clone(choice),startedAt:now,deadlineAt:now+p.totalWaitMs,policy:p,attempts:[],status:'waiting_driver',confirmed:false,liveTracking:false,counters:{offers:0,accepts:0,rejects:0,timeouts:0,escalations:0,providerCalls:0}};
 return nextReliableOfferV1(state,{candidates,now});
}
export function escalateReliableChoiceV1(state,reason,now){return {...clone(state),status:'dispatcher',confirmed:false,liveTracking:false,escalationReason:reason,endedAt:now,counters:{...state.counters,escalations:state.counters.escalations+(state.status==='dispatcher'?0:1)}};}
export function nextReliableOfferV1(state,{candidates,now}){
 if(['confirmed','dispatcher','cancelled'].includes(state.status))return clone(state);
 if(now>=state.deadlineAt||state.deadlineAt-now<state.policy.offerResponseMs)return escalateReliableChoiceV1(state,'total_wait_limit',now);
 if(state.attempts.length>=state.policy.maxOffers)return escalateReliableChoiceV1(state,'offer_limit',now);
 if(candidates?.schema!==RELIABLE_CHOICE_V1||!same(candidates.scope,state)||candidates.validUntil<=now)return escalateReliableChoiceV1(state,'traffic_uncertainty',now);
 const offered=new Set(state.attempts.map(r=>r.vehicle_id));
 const chosen=candidates.rows.find(c=>c.vehicle_id===state.choice.vehicle_id);
 const allowed=c=>same(c,state)&&c.visibility==='visible'&&c.validUntil>now&&!offered.has(c.vehicle_id)
  &&(state.choice.kind==='exact'?c.vehicle_id===state.choice.vehicle_id:c.category===state.choice.category)
  &&(state.choice.capabilities??[]).every(x=>c.capabilities.includes(x))&&c.passengerCapacity>=(state.choice.passengers??1)&&c.luggageCapacity>=(state.choice.luggage??0);
 const candidate=state.attempts.length===0&&chosen&&allowed(chosen)?chosen:candidates.rows.find(allowed);
 if(!candidate)return escalateReliableChoiceV1(state,state.choice.kind==='exact'?'exact_vehicle_unavailable':'no_compatible_candidate',now);
 const attempt={number:state.attempts.length+1,driver_id:candidate.driver_id,vehicle_id:candidate.vehicle_id,category:candidate.category,evidenceRevision:candidate.evidenceRevision,
  startedAt:now,deadlineAt:now+state.policy.offerResponseMs,state:'offered'};
 return {...clone(state),status:'waiting_driver',current:attempt,attempts:[...clone(state.attempts),attempt],counters:{...state.counters,offers:state.counters.offers+1}};
}
export function reliableChoiceEventV1(state,event,{now,candidates,scope}){
 if(!same(state,scope)||event.bookingId!==state.bookingId||event.bookingRevision!==state.bookingRevision)throw Error('reliable_choice_event_scope');
 if(['confirmed','dispatcher','cancelled'].includes(state.status))return clone(state);
 if(!state.current||event.attempt!==state.current.number||event.driver_id!==state.current.driver_id||event.vehicle_id!==state.current.vehicle_id)throw Error('reliable_choice_old_offer');
 if(event.type==='accept'){
  if(now>=state.current.deadlineAt||now>=state.deadlineAt)return reliableChoiceEventV1(state,{...event,type:'timeout'},{now,candidates,scope});
  const p=event.canonicalProof;
  if(!p?.committed||!same(p,state)||p.bookingId!==state.bookingId||p.driver_id!==event.driver_id||p.vehicle_id!==event.vehicle_id||!Number.isSafeInteger(p.canonicalVersion)||p.canonicalVersion<=state.bookingRevision
   ||p.capacityConfirmed!==true||p.ackConfirmed!==true)return escalateReliableChoiceV1(state,'canonical_confirmation_unproven',now);
  const attempts=clone(state.attempts);attempts.at(-1).state='accepted';
  return {...clone(state),attempts,status:'confirmed',confirmed:true,liveTracking:false,acceptedCandidateNumber:state.current.number,acceptedAt:now,endedAt:now,counters:{...state.counters,accepts:state.counters.accepts+1}};
 }
 if(!['reject','timeout','capacity_conflict','evidence_invalidated'].includes(event.type))throw Error('reliable_choice_event_invalid');
 if(event.type==='timeout'&&now<state.current.deadlineAt)throw Error('reliable_choice_timeout_early');
 const attempts=clone(state.attempts);attempts.at(-1).state=event.type==='reject'?'rejected':event.type==='timeout'?'expired':'invalidated';
 const next={...clone(state),attempts,current:null,counters:{...state.counters,rejects:state.counters.rejects+Number(event.type==='reject'),timeouts:state.counters.timeouts+Number(event.type==='timeout')}};
 if(event.type==='capacity_conflict')return escalateReliableChoiceV1(next,'capacity',now);
 if(event.type==='evidence_invalidated')return escalateReliableChoiceV1(next,'traffic_uncertainty',now);
 return nextReliableOfferV1(next,{candidates,now});
}
export function reliableChoiceCustomerStatusV1(state){return {booking_id:state.bookingId,state:state.status==='confirmed'?'driver_confirmed':state.status==='dispatcher'?'dispatcher_review':state.attempts.length>1?'finding_next_vehicle':'waiting_driver_confirmation',confirmed:state.confirmed,eta_is_estimate:true,live_tracking:false};}
export function reliableDispatcherPayloadV1({state,request,candidates}){
 if(!same(state,request)||candidates&&!same(state,candidates.scope))throw Error('reliable_dispatcher_scope');
 return {schema:'fluxidi-reliable-dispatcher-v1',tenant_id:state.tenant_id,company_id:state.company_id,booking_id:state.bookingId,pickup_summary:String(request.pickupSummary??'').slice(0,300),destination_summary:String(request.destinationSummary??'').slice(0,300),requested_vehicle:clone(state.choice),
  candidates:(candidates?.rows??[]).filter(c=>c.visibility==='visible').slice(0,25).map(c=>({vehicle_id:c.vehicle_id,driver_id:c.driver_id,eta_range_seconds:clone(c.etaRangeSeconds),distance_meters:c.estimatedPickupDistanceMeters,evidence_revision:c.evidenceRevision})),
  reason:state.escalationReason,deadline_at:request.deadlineAt??state.deadlineAt,booking_revision:state.bookingRevision,manual_assignment_requires_existing_capacity_authority:true};
}
