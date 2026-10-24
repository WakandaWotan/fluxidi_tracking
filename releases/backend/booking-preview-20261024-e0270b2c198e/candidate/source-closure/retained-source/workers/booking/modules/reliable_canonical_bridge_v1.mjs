import {reliableRouteQualityV1} from './product_estimated_eta_v1.mjs';
import {humanOfferDeliveryWindowV1} from './human_offer_delivery_budget_v1.mjs';
import {withCanonicalBookingAuthority} from './canonical_booking_authority.mjs';
import {generateReliableCandidatesV1,reliableCandidatePageV1,REQUIRED_BUSINESS_GATES,RELIABLE_CHOICE_V1,gpsRoadContextBoundV1} from './reliable_candidate_v1.mjs';
import {prepareCanonicalDispatchOffer,consumeCanonicalDispatchEvent} from './company_dispatch_delivery.mjs';
import {reliableDispatcherPayloadV1} from './reliable_choice_cycle_v1.mjs';
import {officialAddressEvidencePickupV1} from './official_address_operational_adapter_v1.mjs';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const point=p=>({latitude:Number(p?.latitude??p?.lat),longitude:Number(p?.longitude??p?.lng),...(p?.access?{access:structuredClone(p.access)}:{})});

// This capability replaces the request-local route memo, never invokes its
// legacy provider closure, and supplies conservative local travel times for
// ALL canonical approach/previous/next-reservation checks. A miss is a denial.
export function createReliableCanonicalRouteMemoV1({router,scope,departureAt,counters={},approachLowerBound=null,planningOnly=false,trustedPoints=[],approachPoints=null,gpsRoadApproach=null,clock=Date.now}){
 if(router?.kind!=='LOCAL_ROUTING_ONLY_V1')throw Error('reliable_canonical_local_routes_required');
 const gpsApproach=gpsRoadApproach?structuredClone(gpsRoadApproach):null;
 return {async resolve(key,_neverInvokeProvider,{routeRole}={}){
  counters.localRouteCalculations=(counters.localRouteCalculations??0)+1;counters.trafficLookups=(counters.trafficLookups??0)+1;
  try{
   const [tenant,company,legacyCacheLabel,from,to]=JSON.parse(key);
   if(tenant!==scope.tenant_id||company!==scope.company_id||!['mapbox/driving','fluxidi/local-planning-v1'].includes(legacyCacheLabel))throw Error('reliable_canonical_route_scope');
   // Preserve server-snapshot address/GPS context through the legacy numeric
   // memo key. No client can install a proof, and mismatched coordinates fail.
   const bind=(p,role)=>{const value=point(p),preferred=routeRole==='approach'?(role==='origin'?approachPoints?.origin??gpsApproach?.origin:approachPoints?.pickup??gpsApproach?.pickup):null;
    if(preferred&&preferred.latitude===value.latitude&&preferred.longitude===value.longitude)return structuredClone(preferred);
    const matches=trustedPoints.filter(k=>k&&k.latitude===value.latitude&&k.longitude===value.longitude),unique=[...new Map(matches.map(k=>[JSON.stringify(k),k])).values()];
    if(unique.length>1)throw Error('reliable_canonical_route_point_ambiguous');return unique.length?structuredClone(unique[0]):value;};
   const boundOrigin=bind(from,'origin'),boundPickup=bind(to,'destination'),gpsRoadContext=!planningOnly&&routeRole==='approach'&&gpsApproach&&Number.isFinite(gpsApproach.validUntil)&&gpsApproach.validUntil>clock()&&JSON.stringify(boundOrigin)===JSON.stringify(gpsApproach.origin)&&JSON.stringify(boundPickup)===JSON.stringify(gpsApproach.pickup);
   const r=planningOnly?await router.planRoute({scope,origin:boundOrigin,destination:boundPickup}):await router.route({scope,origin:boundOrigin,destination:boundPickup,departureAt,...(gpsRoadContext?{gpsRoadContext:true}:{})});
    if(planningOnly){if(r.planningOnly!==true||r.graphVersion!==scope.graphVersion||r.evidenceRevision!==scope.evidenceRevision||r.validUntil<=Date.now()||!Number.isFinite(r.operationalDurationBoundSeconds)||r.operationalDurationBoundSeconds<0)throw Error('reliable_manual_route_unknown');return {hit:false,value:{ok:true,travel_seconds:r.operationalDurationBoundSeconds,route_profile:'fluxidi/local-planning-only-v1'}};}
   if(!reliableRouteQualityV1(r)||!Number.isFinite(r.seconds)||!Number.isFinite(r.quality.errorSeconds))throw Error('reliable_canonical_route_uncertain');
   const lower=routeRole==='approach'&&approachLowerBound&&JSON.stringify(bind(from,'origin'))===JSON.stringify(bind(approachLowerBound.origin,'origin'))&&JSON.stringify(bind(to,'destination'))===JSON.stringify(bind(approachLowerBound.pickup,'destination'));
   return {hit:false,value:{ok:true,travel_seconds:Math.ceil(lower?Math.max(0,r.seconds-r.quality.errorSeconds):r.seconds+r.quality.errorSeconds),route_profile:'fluxidi/local-only-v1',route_failure_reason:null,route_validation_unavailable:false,route_used_coordinate_direct:true,route_used_geocode_fallback:false}};
  }catch{return {hit:false,value:{ok:false,travel_seconds:null,reason_code:'p12_local_route_unproven',route_failure_reason:'p12_local_route_unproven',route_validation_unavailable:true}};}
 }};
}

// Canonical allocator owns overlap/roster/driver binding/capacity. Separate
// trusted policyEvidence must attest the other existing rules; absent gates
// cannot be manufactured from allocator.allowed alone. No HTTP client input
// may supply this callback, snapshot, route capability or policy proof.
export function createReliableCanonicalBusinessV1({allocate,loadContext,policyEvidence,router,counters={},clock=Date.now,planningOnly=false}){
 if(typeof allocate!=='function'||typeof loadContext!=='function'||typeof policyEvidence!=='function'||router?.kind!=='LOCAL_ROUTING_ONLY_V1')throw Error('reliable_canonical_business_invalid');
 const sessions=new WeakMap();
 return async input=>{
  const {candidate,request,context,arrivalWindow,origin,route}=input,proof=await policyEvidence(input);
  if(REQUIRED_BUSINESS_GATES.some(k=>proof?.gates?.[k]===false)||!same(proof,context)||proof.evidenceRevision!==context.evidenceRevision||REQUIRED_BUSINESS_GATES.filter(k=>!['driver_vehicle_binding','capacity','category','future_bookings'].includes(k)).some(k=>proof.gates?.[k]!==true))return {allowed:false,gates:proof?.gates??{}};
  let session=input.evaluationSession&&sessions.get(input.evaluationSession);
  if(!session){
   session={scope:JSON.stringify(context),at:clock(),shared:Promise.resolve(loadContext(input)),memo:createReliableCanonicalRouteMemoV1({router,scope:context,departureAt:clock(),counters,planningOnly})};
   if(input.evaluationSession)sessions.set(input.evaluationSession,session);
   counters.contextLoads=(counters.contextLoads??0)+1;
  }
  if(session.scope!==JSON.stringify(context)||clock()<session.at||clock()-session.at>=15000)return {allowed:false,gates:{},canonicalReason:'request_snapshot_stale'};
  const shared=await session.shared,localMemo=session.memo;
  const evaluations=[];
  // Both bounds retain the complete existing planner gates. Checking just
  // the latest arrival can miss an early overlap at the preceding boundary.
  for(const pickupMs of [...new Set([arrivalWindow.from,arrivalWindow.until])]){
   const occupancyMinutes=request.serviceMinutes+(pickupMs===arrivalWindow.from?(arrivalWindow.until-arrivalWindow.from)/60000:0);
   const lower=!planningOnly&&pickupMs===arrivalWindow.from&&request.serverDecisionReadyAt&&origin?.point;
   // Reuse the candidate's already validated server-owned GPS road context
   // only for this same free ASAP approach. Neighbour/planned/busy routes
   // never inherit its opt-in, and its original observation lease is kept.
   const now=clock(),gps=candidate.driver?.gps,road=route?.gpsRoadEvidence,evidencePickup=officialAddressEvidencePickupV1(route,origin?.point,request.pickup,context);
   const gpsRoadApproach=!planningOnly&&request.pickupMode==='asap'&&origin?.source==='fresh_current_gps'&&candidate.driver?.trip?.state==='free'
    &&same(candidate,context)&&same(candidate.driver,context)&&same(candidate.vehicle,context)&&candidate.driver.vehicle_id===candidate.vehicle.vehicle_id
    &&same(request,context)&&same(route,context)&&route?.region_id===context.region_id&&route.graphVersion===context.graphVersion&&route.evidenceRevision===context.evidenceRevision&&reliableRouteQualityV1(route)
    &&road?.schema==='fluxidi-driver-gps-road-v1'&&same(road,context)&&road.graphVersion===context.graphVersion&&typeof context.accessContextRevision==='string'&&context.accessContextRevision.length>0&&road.accessContextRevision===context.accessContextRevision
    &&origin.point.access?.kind==='gps'&&gps?.access?.kind==='gps'&&origin.point.latitude===gps.latitude&&origin.point.longitude===gps.longitude&&JSON.stringify(origin.point.access)===JSON.stringify(gps.access)
    &&origin.point.access.capturedAt===gps.capturedAt&&origin.point.access.accuracyMeters===gps.accuracyMeters&&Number.isFinite(gps.capturedAt)&&gps.capturedAt<=now&&now-gps.capturedAt<=30000&&Number.isFinite(gps.accuracyMeters)&&gps.accuracyMeters>0&&gps.accuracyMeters<=100&&(gps.accuracyMeters>5||road?.roadContext?.practicalGeometryMatch===true||road?.roadContext?.junction)
    &&gpsRoadContextBoundV1(road?.roadContext,gps.accuracyMeters,origin.point)&&(!road.roadContext.junction||route.quality.tier==='medium'&&route.quality.errorSeconds>=road.roadContext.junction.localLegTimeBoundSeconds)&&(road.roadContext.practicalGeometryMatch!==true||route.quality.tier==='medium')
    &&JSON.stringify(road.origin)===JSON.stringify(origin.point)&&JSON.stringify(road.pickup)===JSON.stringify(evidencePickup)
    &&Number.isFinite(road.observedAt)&&road.observedAt<=now&&now-road.observedAt<=15000&&Number.isFinite(road.validUntil)&&road.validUntil>now&&road.validUntil<=gps.capturedAt+30000&&road.validUntil<=road.observedAt+15000
    &&Number.isFinite(route.validUntil)&&route.validUntil>now?{origin:origin.point,pickup:request.pickup,validUntil:Math.min(route.validUntil,road.validUntil)}:null;
   const boundMemo=createReliableCanonicalRouteMemoV1({router,scope:context,departureAt:clock(),counters,planningOnly,trustedPoints:[origin?.point,request.pickup,request.destination],approachPoints:origin?.point?{origin:origin.point,pickup:request.pickup}:null,approachLowerBound:lower?{origin:origin.point,pickup:request.pickup}:null,gpsRoadApproach,clock});
   const response=await allocate({action:'suggest',booking_id:request.booking_id,...(request.revalidation_offer?{revalidation_offer:request.revalidation_offer,revalidation_canonical_version:request.revalidation_canonical_version,revalidation_record_revision:request.revalidation_record_revision}:{}),pickup_mode:'scheduled',pickup_ms:pickupMs,service_min:occupancyMinutes,
    tier:candidate.vehicle.tier??candidate.vehicle.category,pax:request.passengers,bags:request.luggage,required_vehicle_id:candidate.vehicle.vehicle_id,pickup_lat:request.pickup.latitude,pickup_lng:request.pickup.longitude,
    dropoff_lat:request.destination?.latitude,dropoff_lng:request.destination?.longitude,...context},
    Object.assign(shared,{exactPreparationRoutes:boundMemo,isAsapSearch:request.pickupMode==='asap',sampleDispatchDetails:true,asapDirectValues:true}));
   if(!response?.ok)return {allowed:false,gates:{}};
   const result=await response.json();evaluations.push(result);
   if(!result.allowed||result.assigned_vehicle_id!==candidate.vehicle.vehicle_id||result.assigned_driver_id!==candidate.driver.driver_id)return {allowed:false,gates:{future_bookings:false},canonicalReason:result.reason};
  }
  counters.canonicalEvaluations=(counters.canonicalEvaluations??0)+evaluations.length;
  return {...proof,...context,allowed:true,checkedAt:clock(),validUntil:Math.min(proof.validUntil,clock()+15000),arrivalWindow:structuredClone(arrivalWindow),
   gates:{...proof.gates,driver_vehicle_binding:true,capacity:true,category:true,future_bookings:true},plannedAvailabilityVerified:request.pickupMode==='scheduled'?proof.plannedAvailabilityVerified===true:undefined};
 };
}

export async function writeReliableDispatcherQueueV1(env,scope,bookingId,reason,payload){
 if(payload.booking_id!==bookingId||!same(payload,scope)||typeof reason!=='string'||reason.length>100)throw Error('reliable_dispatcher_queue_scope');
 const key=`tenant:${scope.tenant_id}:company:${scope.company_id}:p12_dispatcher_queue:${bookingId}`;
 const old=await env.BOOKING_KV.get(key,{type:'json'});
 if(old?.booking_id!==bookingId||!same(old,scope)||old.reason!==reason)await env.BOOKING_KV.put(key,JSON.stringify({...payload,reason,queued_at:new Date().toISOString()}),{expirationTtl:86400});
 return {schema:'fluxidi-reliable-dispatcher-v1',reason,queued_at:old?.queued_at??new Date().toISOString()};
}
export async function enqueueReliableDispatcherV1(env,scope,bookingId,reason,payload){
 const record=await env.BOOKING_KV.get('booking:'+bookingId,{type:'json'});
 if(!same(record,scope)||payload.booking_id!==bookingId||!same(payload,scope))throw Error('reliable_dispatcher_record_scope');
 if(record.assigned_driver_id||record.assigned_vehicle_id||record.dispatch_offer?.state==='committed')return {ok:false,error:'reliable_dispatcher_already_assigned'};
 if(['prepared','offered','committing'].includes(record.dispatch_offer?.state))return {ok:false,error:'reliable_dispatcher_capacity_reconciliation_required'};
 if(record.p12_dispatcher_review?.reason===reason&&record.do_not_dispatch===true)return {ok:true,manager_review:true,reason};
 const copy=structuredClone(record);copy.p12_dispatcher_review=await writeReliableDispatcherQueueV1(env,scope,bookingId,reason,payload);
 copy.do_not_dispatch=true;copy.dispatch_search={state:'manager_review',reason};copy.revision=(Number(copy.revision)||1)+1;
 await env.BOOKING_KV.put('booking:'+bookingId,JSON.stringify(copy));return {ok:true,assigned:false,manager_review:true,reason};
}

// Local/shadow entrypoint. Invoke only inside the existing scoped canonical
// company writer. Public HTTP routing and the legacy default are unchanged.
export function createReliableChoiceDispatchV1({env,scope,companyCoordinator,loadSnapshot,publishAssignment,validateSplitAssignments,authorizeCustomer,clock=Date.now,alreadyCoordinated=false}){
 if(!companyCoordinator?.state?.storage||companyCoordinator.env!==env||env.BOOKING_RECORD_AUTHORITY_ENABLED!=='1'||typeof loadSnapshot!=='function'||typeof publishAssignment!=='function'||!scope?.tenant_id||!scope.company_id)throw Error('reliable_choice_bridge_invalid');
 env=withCanonicalBookingAuthority(env,{state:companyCoordinator.state,scope});
 const serialized=fn=>{if(alreadyCoordinated)return fn();const run=(companyCoordinator._gate??Promise.resolve()).then(fn);companyCoordinator._gate=run.then(()=>undefined,()=>undefined);return run;};
 const counters={candidateLists:0,localRouteCalculations:0,premiumAiDispatchCalls:0,escalations:0};
 async function selectCandidate(record,bookingId,validation=null){
  const etaAdvisory=validation?.confirmedAsapEtaAdvisory===true&&record.dispatch_offer?.state==='committed'
   &&Number.isFinite(record.dispatch_offer.asap_requested_ms)
   &&record.dispatch_offer.asap_search_expires_ms===record.dispatch_offer.asap_requested_ms+600000
   &&record.p12_reliable_choice?.request_context?.deadlineAt==null;
  if(etaAdvisory)record={...record,pickup_mode:'asap'}; // Local evaluation only; canonical window is never rewritten.
  const choice=record.p12_reliable_choice,now=clock();
  if(!same(record,scope)||choice?.schema!==RELIABLE_CHOICE_V1||!['type','exact'].includes(choice.kind)||!Number.isFinite(choice.startedAt)||choice.startedAt>now||typeof choice.vehicle_id!=='string'||!choice.vehicle_id||choice.kind==='type'&&(typeof choice.category!=='string'||!choice.category))return {ok:false,error:'p12_choice_missing'};
  const attempts=record.vehicle_dispatch_attempts??[];
  const deliveryWindow=humanOfferDeliveryWindowV1(record,bookingId,now);
  const reason=record.do_not_dispatch===true?'company_manual_policy':!etaAdvisory&&attempts.length>=5?'offer_limit':!etaAdvisory&&!deliveryWindow&&(now-choice.startedAt>=60000||!['prepared','offered','committing','committed'].includes(record.dispatch_offer?.state)&&now-choice.startedAt>30000)?'total_wait_limit':null;
  const snapshot=await loadSnapshot(record,bookingId,{confirmedAsapEtaAdvisory:etaAdvisory});
  const activeOffer=['prepared','offered','committing','committed'].includes(record.dispatch_offer?.state);
  const sealedPickupMs=Date.parse(record.pickup_iso??record.booking?.pickup_iso);
  // A canonical receipt revalidates an existing appointment. Its human
  // response has already happened; starting another response allowance moves
  // that appointment after every asynchronous batch. Recheck the complete
  // sealed interval instead, rejecting a fresh route that no longer fits.
  const receipt=activeOffer&&snapshot.request.revalidation_offer?.offer_id===record.dispatch_offer.offer_id;
  const responseRemaining=receipt?0:activeOffer?Math.max(0,Math.min(30,(Date.parse(record.dispatch_offer.created_at)+30000-clock())/1000)):30;
  snapshot.request={...snapshot.request,humanResponseAllowanceSeconds:snapshot.request.pickupMode==='asap'?responseRemaining:0,
   ...(receipt&&!etaAdvisory&&snapshot.request.pickupMode==='asap'?{reservationPickupAt:sealedPickupMs}:{})};
  const list=reason?null:await generateReliableCandidatesV1({...snapshot,clock});
  counters.candidateLists++;counters.localRouteCalculations+=list?.counters.localRouteCalculations??0;
  const pinned=['prepared','offered','committing','committed'].includes(record.dispatch_offer?.state)?(record.dispatch_offer.assignments?.find(a=>a.leg===(record._reliable_leg_type??'outbound'))?.vehicle_id??record.dispatch_offer.vehicle_id):choice.kind==='exact'?choice.vehicle_id:null;
  const used=new Set(attempts.map(x=>x.vehicle_id)),excluded=new Set((record.dispatch_exclusions??[]).filter(x=>x.until_ms>now).map(x=>x.driver_id));
  const eligible=(list?.rows??[]).filter(c=>(!pinned||c.vehicle_id===pinned)&&(etaAdvisory&&c.vehicle_id===pinned||!used.has(c.vehicle_id))&&!excluded.has(c.driver_id)
   &&(choice.kind==='exact'?c.vehicle_id===choice.vehicle_id:c.category===choice.category)
   &&(!choice.vehicle_type||c.vehicleType===choice.vehicle_type)&&c.passengerCapacity>=(choice.passengers??1)&&c.luggageCapacity>=(choice.luggage??0)&&(choice.capabilities??[]).every(x=>c.capabilities.includes(x)));
  const selected=pinned?eligible[0]:eligible.find(c=>c.vehicle_id===choice.vehicle_id)??eligible[0];
  if(reason||!selected){
   const why=reason??(choice.kind==='exact'?'exact_vehicle_unavailable':list?.escalationReason??'no_compatible_candidate');
   const state={...scope,bookingId,bookingRevision:Number(record.revision)||1,choice,deadlineAt:choice.startedAt+60000,escalationReason:why};
   const payload=reliableDispatcherPayloadV1({state,request:{...snapshot.request,...scope},candidates:list});
   return {ok:false,error:'p12_dispatcher_review',allocator_reason:why,reliableDispatcherPayload:payload,
    enqueueDispatcher:async()=>{const marker=await writeReliableDispatcherQueueV1(env,scope,bookingId,why,payload);counters.escalations++;return marker;}};
  }
  // Candidate reservation bounds are relative to list.at, captured after
  // asynchronous snapshot loading. Rebase onto that exact evaluation clock
  // so confirmation reserves the same absolute window the planner validated.
  const feasiblePickupMs=selected.pickupMode==='asap'?Math.ceil(list.at+(selected.reservationPickupUpperSeconds??selected.etaRangeSeconds[1])*1000):snapshot.request.pickupAt;
  // Receipt may keep the sealed appointment only while its current upper
  // bound still fits. A later ETA is never rounded into a false confirmation.
  const pickupMs=etaAdvisory||activeOffer&&selected.pickupMode==='asap'&&feasiblePickupMs<=sealedPickupMs?sealedPickupMs:feasiblePickupMs;
  const eta=etaAdvisory&&Array.isArray(selected.etaRangeSeconds)?{estimated:true,source:'fluxidi/local-product-estimate',certified_eta:false,
   duration_seconds:selected.estimatedPickupEtaSeconds,eta_range_seconds:[...selected.etaRangeSeconds],generated_at_ms:list.at,
   arrival_at:new Date(list.at+selected.etaRangeSeconds[1]*1000).toISOString(),valid_until_ms:selected.validUntil}:null;
  return {ok:true,assignedDriverId:selected.driver_id,assignedVehicleId:selected.vehicle_id,alloc:{pickup_ms:pickupMs,...(etaAdvisory?{asap_eta_advisory:eta}:{})},reliableCandidate:selected};
 }
 async function customerRecord(bookingId,credential){
  if(typeof authorizeCustomer!=='function')throw Error('reliable_customer_authority_missing');
  const identity=await authorizeCustomer(credential),record=await env.BOOKING_KV.get('booking:'+bookingId,{type:'json'});
  if(!same(identity,scope)||!same(record,scope)||!identity.customer_id||record.customer_id!==identity.customer_id)throw Error('reliable_customer_scope');
  return record;
 }
 async function customerList(record,bookingId){
  const snapshot=await loadSnapshot(record,bookingId);
  return generateReliableCandidatesV1({...snapshot,clock});
 }
 // Internal methods below are for the existing company writer while its gate
 // is already held. Re-enqueuing on that same gate would deadlock. Never bind
 // these capabilities directly from an HTTP body.
 async function prepareCoordinated(bookingId){
  const record=await env.BOOKING_KV.get('booking:'+bookingId,{type:'json'});
  if(!same(record,scope)||record.p12_reliable_choice?.schema!==RELIABLE_CHOICE_V1)return {ok:false,error:'p12_choice_missing'};
  if(record.assigned_driver_id||record.assigned_vehicle_id)return {ok:false,error:'reliable_dispatcher_already_assigned'};
  if(record.p12_reliable_choice.dispatcher_only===true){
   const choice=record.p12_reliable_choice,request={...scope,pickupSummary:choice.request_context?.from??record.booking?.from??'',destinationSummary:choice.request_context?.to??record.booking?.to??''};
   const payload=reliableDispatcherPayloadV1({state:{...scope,bookingId,bookingRevision:Number(record.revision)||1,choice,deadlineAt:choice.startedAt+60000,escalationReason:'no_reliable_candidates'},request,candidates:null});
   return enqueueReliableDispatcherV1(env,scope,bookingId,'no_reliable_candidates',payload);
  }
  const candidate=await selectCandidate(record,bookingId);if(!candidate.ok){if(candidate.error!=='p12_dispatcher_review')return candidate;
   const queued=await enqueueReliableDispatcherV1(env,scope,bookingId,candidate.allocator_reason,candidate.reliableDispatcherPayload);if(queued.ok)counters.escalations++;return queued;}
  return prepareCanonicalDispatchOffer(env,scope,bookingId,hooks);

 }
 const hooks={selectCandidate,publishAssignment,validateSplitAssignments,requireHumanAcceptance:true};
 return Object.freeze({kind:'P12_LOCAL_SHADOW_ONLY',counters,selectCandidate,
  open({bookingId,credential}){return serialized(async()=>{
   const record=await customerRecord(bookingId,credential),list=await customerList(record,bookingId);counters.candidateLists++;
   return list.rows.length?reliableCandidatePageV1(list,{now:clock()}):{schema:RELIABLE_CHOICE_V1,vehicles:[],estimate:true,status:'dispatcher_review'};
  });},
  choose({bookingId,credential,vehicleId,kind='exact'}){return serialized(async()=>{
   const record=await customerRecord(bookingId,credential);
   if(!['type','exact'].includes(kind)||typeof vehicleId!=='string'||!vehicleId)throw Error('reliable_choice_invalid');
   if(record.assigned_driver_id||record.assigned_vehicle_id||['prepared','offered','committing','committed'].includes(record.dispatch_offer?.state))return {ok:false,error:'reliable_choice_already_active'};
   const list=await customerList(record,bookingId),selected=list.rows.find(r=>r.vehicle_id===vehicleId);
   if(!selected){
    const state={...scope,bookingId,bookingRevision:Number(record.revision)||1,choice:{kind,vehicle_id:vehicleId},deadlineAt:clock()+60000,escalationReason:'exact_vehicle_unavailable'};
    const payload=reliableDispatcherPayloadV1({state,request:{...scope},candidates:list});
    return enqueueReliableDispatcherV1(env,scope,bookingId,'exact_vehicle_unavailable',payload);
   }
   record.p12_reliable_choice={schema:RELIABLE_CHOICE_V1,kind,vehicle_id:vehicleId,category:selected.category,vehicle_type:selected.vehicleType,startedAt:clock(),passengers:selected.passengerCapacity,luggage:selected.luggageCapacity,capabilities:[...selected.capabilities]};
   record.revision=(Number(record.revision)||1)+1;
   await env.BOOKING_KV.put('booking:'+bookingId,JSON.stringify(record));
   return prepareCanonicalDispatchOffer(env,scope,bookingId,hooks);
  });},prepare(bookingId){return serialized(()=>prepareCoordinated(bookingId));},
  prepareCoordinated,consumeCoordinated(input){return consumeCanonicalDispatchEvent(env,scope,input,hooks);},
  consume(input){return serialized(()=>consumeCanonicalDispatchEvent(env,scope,input,hooks));}});
}
