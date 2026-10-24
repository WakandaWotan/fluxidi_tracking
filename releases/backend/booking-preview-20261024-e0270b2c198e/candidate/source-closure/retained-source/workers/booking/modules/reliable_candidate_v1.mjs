import {reliableRouteQualityV1,productPickupRangeV1} from './product_estimated_eta_v1.mjs';
import {resolveVehicleServiceCapacity} from './vehicle_service_capacity.mjs';
import {driverGpsConfidenceV1} from './national_road_access_v1.mjs';
import {officialAddressEvidencePickupV1,copyOfficialAddressRouteEvidenceV1} from './official_address_operational_adapter_v1.mjs';

export const RELIABLE_CHOICE_V1='fluxidi-reliable-choice-v1';
export const REQUIRED_BUSINESS_GATES=Object.freeze(['tenant','security','driver_vehicle_binding','capacity','category','capabilities','service_area','fleet_partner_hybrid','future_bookings','return','airport','reassignment','payment','pricing','operating_policy']);
const finite=n=>typeof n==='number'&&Number.isFinite(n),point=p=>p&&finite(p.latitude)&&finite(p.longitude)&&Math.abs(p.latitude)<=90&&Math.abs(p.longitude)<=180;
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const age=(now,at,max)=>finite(at)&&at<=now&&now-at<=max;
const copy=v=>structuredClone(v),freeze=v=>{if(v&&typeof v==='object'){Object.freeze(v);for(const x of Object.values(v))freeze(x);}return v;};
export const DEFAULT_RELIABLE_CHOICE_POLICY=Object.freeze({maxCandidates:5000,maxGpsAgeMs:30000,maxEvidenceAgeMs:15000,maxForecastAgeMs:30000,pageSize:25});

const pickupDistance=(a,b)=>{const rad=Math.PI/180,dLat=(b.latitude-a.latitude)*rad,dLon=(b.longitude-a.longitude)*rad,h=Math.sin(dLat/2)**2+Math.cos(a.latitude*rad)*Math.cos(b.latitude*rad)*Math.sin(dLon/2)**2;return 6371000*2*Math.asin(Math.min(1,Math.sqrt(h)));};
const gpsSampleBound=g=>g?.access?.kind==='gps'&&g.access.capturedAt===g.capturedAt&&g.access.accuracyMeters===g.accuracyMeters;
const gpsAccessBound=g=>gpsSampleBound(g)&&typeof g.access.continuityKey==='string'&&/^[a-zA-Z0-9_.:-]{1,160}$/.test(g.access.continuityKey);

// Low GPS precision is provisional only. A trusted server router must still
// prove a single safe road context before this can become a visible candidate.
export function operationalOriginV1(candidate,{now,maxGpsAgeMs=30000,maxForecastAgeMs=30000,pickup=null}){
 const d=candidate?.driver;
 if(!d||!point(d.gps)||!age(now,d.gps.capturedAt,maxGpsAgeMs)||!finite(d.gps.accuracyMeters)||d.gps.accuracyMeters<0)return {ok:false,reason:'stale_location'};
 const requiresGpsRoadProof=d.gps.accuracyMeters>50&&d.gps.accuracyMeters<=100,requiresNearPickupRoadProof=d.gps.accuracyMeters>100;
 if((requiresGpsRoadProof||requiresNearPickupRoadProof)&&(d.trip?.state!=='free'||!gpsSampleBound(d.gps)||requiresNearPickupRoadProof&&(!gpsAccessBound(d.gps)||!point(pickup)||pickupDistance(d.gps,pickup)>100)))return {ok:false,reason:'stale_location'};
 if(d.trip?.state==='busy'){
  const t=d.trip;
  if(!point(t.endpoint)||!age(now,t.forecastAt,maxForecastAgeMs)||!finite(t.availableAt)||t.availableAt<now||!finite(t.uncertaintySeconds)||t.uncertaintySeconds<0)return {ok:false,reason:'impossible_busy_driver'};
  return {ok:true,source:'current_trip_endpoint',point:copy(t.endpoint),availableAt:t.availableAt,availabilityErrorSeconds:t.uncertaintySeconds,currentTripState:'busy'};
 }
 if(d.trip?.state!=='free')return {ok:false,reason:'unknown_trip_state'};
 return {ok:true,source:'fresh_current_gps',point:{latitude:d.gps.latitude,longitude:d.gps.longitude,...(d.gps.access?{access:copy(d.gps.access)}:{})},availableAt:now,availabilityErrorSeconds:0,currentTripState:'free',...(requiresGpsRoadProof?{requiresGpsRoadProof:true}:{}),...(requiresNearPickupRoadProof?{requiresNearPickupRoadProof:true}:{})};
}

const gpsRoadGeometryBound=(road,accuracy)=>{
 if(!road||!finite(road.snapMeters)||road.snapMeters<0||road.accuracyMeters!==accuracy)return false;
 const practical=road.geometryToleranceMeters!=null||road.searchRadiusMeters!=null||road.practicalGeometryMatch!=null;
 if(!practical)return accuracy>5&&road.snapMeters<=accuracy;
 return road.geometryToleranceMeters===25&&road.searchRadiusMeters===Math.max(25,accuracy)&&road.snapMeters<=road.searchRadiusMeters+1e-6&&road.practicalGeometryMatch===(road.snapMeters>accuracy+1e-6);
};

// The router can attest one ordinary mapped junction instead of guessing
// between its legal arms. Preserve the raw fix and bind the complete road
// context to that actual node; no client-supplied nearest-road hint qualifies.
export function gpsRoadContextBoundV1(road,accuracy,origin){
 if(!gpsRoadGeometryBound(road,accuracy)||!Array.isArray(road.wayIds)||!road.wayIds.length||road.wayIds.some(id=>!Number.isSafeInteger(id)||id<=0))return false;
 if(road.wayIds.length===1)return road.junction==null;
 const j=road.junction,orderedIds=(ids,min,max,positive)=>Array.isArray(ids)&&ids.length>=min&&ids.length<=max&&ids.every((id,i)=>Number.isSafeInteger(id)&&id>=(positive?1:0)&&(i===0||ids[i-1]<id));
 const anchorBound=j?.distanceMeters<=25+1e-6||j?.anchorBasis==='reported_accuracy'&&finite(accuracy)&&accuracy>25&&accuracy<=100&&j.anchorRadiusMeters===accuracy&&j.distanceMeters<=accuracy+1e-6;
 return road.confidence==='MEDIUM_SAFE'&&road.direction==='two_way'&&road.geometryToleranceMeters===25
  &&j?.schema==='fluxidi-common-road-junction-v1'&&Number.isSafeInteger(j.nodeId)&&j.nodeId>0&&point(j.point)&&point(origin)
  &&orderedIds(j.wayIds,2,16,true)&&JSON.stringify(j.wayIds)===JSON.stringify(road.wayIds)
  &&orderedIds(j.edgeIds,6,8192,false)&&JSON.stringify(j.edgeIds)===JSON.stringify(road.edgeIds)
  &&finite(j.distanceMeters)&&j.distanceMeters>=0&&anchorBound&&Math.abs(j.distanceMeters-pickupDistance(origin,j.point))<=.01
  &&Math.abs(road.snapMeters-j.distanceMeters)<=1e-6
  &&finite(j.localLegDistanceBoundMeters)&&j.localLegDistanceBoundMeters>=0&&j.localLegDistanceBoundMeters<=Math.max(25,accuracy)+Math.max(25,j.distanceMeters)+1
  &&finite(j.localLegTimeBoundSeconds)&&j.localLegTimeBoundSeconds>=0&&(j.localLegDistanceBoundMeters===0||j.localLegTimeBoundSeconds>0);
}

function safeGpsRoadProof(route,origin,pickup,context,driver,now,maxGpsAgeMs,maxEvidenceAgeMs){
 const proof=route?.gpsRoadEvidence,road=proof?.roadContext,gps=driver.gps,locationConfidence=driverGpsConfidenceV1(gps,proof?.observedAt);
 return proof?.schema==='fluxidi-driver-gps-road-v1'&&same(proof,context)&&proof.graphVersion===context.graphVersion
  &&typeof context.accessContextRevision==='string'&&proof.accessContextRevision===context.accessContextRevision
  &&origin?.source==='fresh_current_gps'&&gpsSampleBound(gps)&&gps.accuracyMeters>0&&gps.accuracyMeters<=100&&(gps.accuracyMeters>5||road?.practicalGeometryMatch===true||road?.junction)&&age(now,gps.capturedAt,maxGpsAgeMs)
  &&JSON.stringify(proof.origin)===JSON.stringify(origin.point)&&JSON.stringify(proof.pickup)===JSON.stringify(pickup)&&age(now,proof.observedAt,maxEvidenceAgeMs)
  &&finite(proof.validUntil)&&proof.validUntil>now&&proof.validUntil<=gps.capturedAt+maxGpsAgeMs&&proof.validUntil<=proof.observedAt+maxEvidenceAgeMs
  &&(!proof.continuity||gpsAccessBound(gps)&&gps.accuracyMeters<=25&&finite(proof.continuity.priorCapturedAt)&&proof.continuity.priorCapturedAt<gps.capturedAt&&age(proof.observedAt,proof.continuity.priorCapturedAt,15000)&&gps.capturedAt-proof.continuity.priorCapturedAt<=15000&&finite(proof.continuity.priorAccuracyMeters)&&proof.continuity.priorAccuracyMeters>0&&proof.continuity.priorAccuracyMeters<=5&&finite(proof.continuity.continuityMaxMeters)&&proof.continuity.continuityMaxMeters>=0&&proof.continuity.continuityMaxMeters<=100&&proof.validUntil<=proof.continuity.priorCapturedAt+15000)
  &&road?.confidence==='MEDIUM_SAFE'&&road.locationConfidence===locationConfidence
  &&Array.isArray(road.edgeIds)&&road.edgeIds.length>0&&road.edgeIds.length<=8192&&road.edgeIds.every(id=>Number.isSafeInteger(id)&&id>=0)&&['directed','two_way'].includes(road.direction)
  &&gpsRoadContextBoundV1(road,gps.accuracyMeters,origin.point)
  &&route.quality?.productGrade===true&&['high','medium'].includes(route.quality.tier)&&(!road.junction||route.quality.tier==='medium'&&route.quality.errorSeconds>=road.junction.localLegTimeBoundSeconds)&&(road.practicalGeometryMatch!==true||route.quality.tier==='medium')&&(locationConfidence!=='low'||route.quality.tier==='medium'&&route.quality.errorSeconds>=(road.junction?.localLegTimeBoundSeconds??90));
}

function safeNearPickupRoadProof(route,origin,pickup,context,driver,now,maxGpsAgeMs,maxEvidenceAgeMs){
 const proof=route?.nearPickupEvidence,road=proof?.roadContext,frontage=proof?.pickupFrontage;
 return proof?.schema==='fluxidi-near-pickup-road-v1'&&same(proof,context)&&proof.graphVersion===context.graphVersion
  &&typeof context.accessContextRevision==='string'&&proof.accessContextRevision===context.accessContextRevision
  &&origin?.source==='fresh_current_gps'&&gpsAccessBound(driver.gps)&&age(now,driver.gps.capturedAt,maxGpsAgeMs)
  &&JSON.stringify(proof.origin)===JSON.stringify(origin.point)&&JSON.stringify(proof.pickup)===JSON.stringify(pickup)
  &&point(pickup)&&pickupDistance(origin.point,pickup)<=100&&age(now,proof.observedAt,maxEvidenceAgeMs)
  &&finite(proof.validUntil)&&proof.validUntil>now&&proof.validUntil<=driver.gps.capturedAt+maxGpsAgeMs
  &&frontage?.schema==='fluxidi-practical-frontage-v1'&&frontage.graphVersion===context.graphVersion&&frontage.revision===context.accessContextRevision
  &&point(frontage.point)&&pickupDistance(origin.point,frontage.point)<=100&&Array.isArray(frontage.wayIds)&&frontage.wayIds.length>0&&frontage.wayIds.every(id=>Number.isSafeInteger(id)&&id>0)
  &&road?.confidence==='MEDIUM_SAFE'&&Array.isArray(road.wayIds)&&road.wayIds.length===1&&Number.isSafeInteger(road.wayIds[0])&&frontage.wayIds.includes(road.wayIds[0])
  &&Array.isArray(road.edgeIds)&&road.edgeIds.length>0&&road.edgeIds.every(id=>Number.isSafeInteger(id)&&id>=0)&&['directed','two_way'].includes(road.direction)
  &&finite(road.snapMeters)&&road.snapMeters>=0&&road.snapMeters<=driver.gps.accuracyMeters
  &&finite(road.pickupDistanceMeters)&&road.pickupDistanceMeters>=0&&road.pickupDistanceMeters<=100&&Math.abs(road.pickupDistanceMeters-pickupDistance(origin.point,pickup))<=.01
  &&finite(road.frontageDistanceMeters)&&road.frontageDistanceMeters>=0&&road.frontageDistanceMeters<=100&&Math.abs(road.frontageDistanceMeters-pickupDistance(origin.point,frontage.point))<=.01&&road.accuracyMeters===driver.gps.accuracyMeters
  &&route.quality?.productGrade===true&&route.quality.tier==='medium'&&route.quality.errorSeconds>=90;
}

export function reliableCandidatePublicV1(c,{now=Date.now()}={}){
 if(c.visibility!=='visible')throw Error('reliable_candidate_not_visible');
 const a=c.operationalOrigin?.access,locationConfidence=c.originSource==='fresh_current_gps'&&a?.kind==='gps'?(driverGpsConfidenceV1(a,now)??(a.accuracyMeters>100&&age(now,a.capturedAt,30000)&&c.uncertaintyReasons?.includes('gps_low_accuracy_near_pickup')?'low':null)):c.locationConfidence??null;
 // Presentation reference to the actual eligible driver. The client may join
 // only an already-published driver in this company's public profile; this is
 // neither a customer assignment hint nor a projection of private driver data.
 const publicDriverId=typeof c.driver_id==='string'&&/^[a-zA-Z0-9_.:-]{1,128}$/.test(c.driver_id)?c.driver_id:null;
 return {schema:RELIABLE_CHOICE_V1,vehicle_id:c.vehicle_id,...(publicDriverId?{public_driver_id:publicDriverId}:{}),vehicle_name:c.publicVehicleName,vehicle_type:c.vehicleType,vehicle_category:c.category,photo_url:c.publicPhotoUrl??null,passenger_capacity:c.passengerCapacity,luggage_capacity:c.luggageCapacity,
  pickup_eta_seconds:c.pickupMode==='asap'?Math.round(c.estimatedPickupEtaSeconds):null,pickup_eta_range_seconds:c.pickupMode==='asap'?copy(c.etaRangeSeconds):null,
  ...(c.pickupMode==='asap'&&c.etaBreakdown?{pickup_eta_components:copy(c.etaBreakdown)}:{}),
  pickup_distance_meters:c.pickupMode==='asap'?Math.round(c.estimatedPickupDistanceMeters):null,
  ...(c.pickupMode==='asap'&&finite(c.estimatedPickupDistanceUncertaintyMeters)&&c.estimatedPickupDistanceUncertaintyMeters>0?{pickup_distance_range_meters:[Math.floor(Math.max(0,c.estimatedPickupDistanceMeters-c.estimatedPickupDistanceUncertaintyMeters)),Math.ceil(c.estimatedPickupDistanceMeters+c.estimatedPickupDistanceUncertaintyMeters)]}:{}),
  status:c.pickupMode==='scheduled'?'available_for_selected_time':'estimated_availability',
  ...(locationConfidence?{eta_confidence:c.etaConfidence,location_confidence:locationConfidence,uncertainty_reasons:copy(c.uncertaintyReasons??[])}:{}),
  estimate:true,graph_version:c.graphVersion,route_evidence_id:c.routeEvidenceId,evidence_revision:c.evidenceRevision,valid_until_ms:c.validUntil};
}

// Only trusted server code supplies evaluateBusiness. It must run the existing
// canonical gates for the entire arrival window; a partial/missing proof hides
// the vehicle. No client hint is an eligibility or capacity authority.
export async function generateReliableCandidatesV1({candidates,request,context,router,evaluateBusiness,policy={},clock=Date.now,readRevision}){
 const p={...DEFAULT_RELIABLE_CHOICE_POLICY,...policy},maxPresenceAgeMs=p.maxPresenceAgeMs??p.maxGpsAgeMs,now=clock(),tick=()=>globalThis.performance?.now?.()??Date.now();
 if(!same(context,request)||!context.tenant_id||!context.company_id||!context.region_id||!context.graphVersion||typeof context.evidenceRevision!=='string'||!context.evidenceRevision
  ||!['asap','scheduled'].includes(request.pickupMode)||!point(request.pickup)||!Number.isSafeInteger(request.passengers)||request.passengers<1||!Number.isSafeInteger(request.luggage)||request.luggage<0
  ||!Array.isArray(candidates)||candidates.length>p.maxCandidates||typeof evaluateBusiness!=='function'||router?.kind!=='LOCAL_ROUTING_ONLY_V1'
  ||!finite(now)||Object.entries(p).some(([k,v])=>k!=='pageSize'&&(!finite(v)||v<=0))||!Array.isArray(request.capabilities??[])||!finite(request.serviceMinutes)||request.serviceMinutes<=0||!finite(request.humanResponseAllowanceSeconds??0)||(request.humanResponseAllowanceSeconds??0)<0||(request.humanResponseAllowanceSeconds??0)>30||!Number.isSafeInteger(p.maxCandidates)||p.maxCandidates<1||!Number.isSafeInteger(p.pageSize)||p.pageSize<1||p.pageSize>100)throw Error('reliable_candidate_contract_invalid');
 if(request.pickupMode==='scheduled'&&(!finite(request.pickupAt)||request.pickupAt<=now))throw Error('reliable_scheduled_time_invalid');
 if(request.deadlineAt!=null&&(!finite(request.deadlineAt)||request.deadlineAt<=now))return freeze({schema:RELIABLE_CHOICE_V1,scope:copy(context),at:now,validUntil:now,rows:[],rejected:[{reason:'deadline'}],escalationReason:'deadline',counters:{candidateRequests:1,localRouteCalculations:0,trafficLookups:0,premiumAiDispatchCalls:0}});
 const evaluationSession=Object.freeze({});
 const rows=[],rejected=[],counters={candidateRequests:1,inputCandidates:candidates.length,eligibilityChecks:0,localRouteCalculations:0,trafficLookups:0,premiumAiDispatchCalls:0,visible:0,payloadBytes:0,phaseTimingsMs:{}};
 let phase=null,phaseAt=tick();const mark=next=>{const at=tick();if(phase)counters.phaseTimingsMs[phase]=(counters.phaseTimingsMs[phase]??0)+at-phaseAt;phase=next;phaseAt=at;};
 let preparationError=null;
 if(request.pickupMode==='asap'&&typeof router.prepareCandidates==='function'){
  mark('regionalBatchPreparation');
  const origins=candidates.filter(c=>same(c,context)&&same(c.driver,context)&&same(c.vehicle,context)&&c.driver?.presence?.status==='online'&&age(now,c.driver.presence.observedAt,maxPresenceAgeMs)&&c.driver.paused!==true&&c.driver.blocked!==true&&c.vehicle.active===true&&c.vehicle.blocked!==true).map(c=>operationalOriginV1(c,{now,maxGpsAgeMs:p.maxGpsAgeMs,maxForecastAgeMs:p.maxForecastAgeMs,pickup:request.pickup})).filter(o=>o.ok);
  try{for(const free of [true,false]){const group=origins.filter(o=>(o.source==='fresh_current_gps')===free).map(o=>o.point);if(group.length)await router.prepareCandidates({origins:group,destination:copy(request.pickup),scope:copy(context),gpsRoadContext:free});}}catch(e){preparationError=e.message;}
  mark(null);
 }
 const seen=new Set(),deny=(c,reason,routeReason=null)=>{mark(null);rejected.push({vehicle_id:c?.vehicle?.vehicle_id??null,driver_id:c?.driver?.driver_id??null,reason,...(typeof routeReason==='string'&&/^[a-z][a-z0-9_]{0,99}$/.test(routeReason)?{route_reason:routeReason}:{})});};
 for(const raw of candidates){
  mark('eligibilityFiltering');
  const c=copy(raw),v=c.vehicle,d=c.driver;counters.eligibilityChecks++;
  if(!same(c,context)||!same(v,context)||!same(d,context)){deny(c,'tenant');continue;}
  if(!v?.vehicle_id||!d?.driver_id||d.vehicle_id!==v.vehicle_id){deny(c,'driver_vehicle_binding');continue;}
  const id=d.driver_id+'\0'+v.vehicle_id;if(seen.has(id)){deny(c,'duplicate_candidate');continue;}seen.add(id);
  if(v.blocked===true||v.active!==true||d.blocked===true||d.active===false||d.is_active===false){deny(c,'blocked');continue;}
  if(d.paused===true){deny(c,'paused');continue;}
  mark('presenceFreshness');
  if(request.pickupMode==='asap'&&d.presence?.status!=='online'){deny(c,'offline');continue;}
  if(request.pickupMode==='asap'&&!age(now,d.presence?.observedAt,maxPresenceAgeMs)){deny(c,'stale_presence');continue;}
  mark('vehicleRequirements');
  const capacity=resolveVehicleServiceCapacity(v,request.service);
  if(capacity.passengers==null||capacity.passengers<request.passengers||request.luggage>0&&(capacity.baggage==null||capacity.baggage<request.luggage)){deny(c,'capacity');continue;}
  if(!v.category||request.category&&v.category!==request.category){deny(c,'category');continue;}
  if(!Array.isArray(v.capabilities)||(request.capabilities??[]).some(x=>!v.capabilities.includes(x))){deny(c,'capabilities');continue;}
  if(!['fleet','partner','hybrid'].includes(c.relation)){deny(c,'fleet_partner_hybrid');continue;}
  if(!finite(c.operationalBufferSeconds)||c.operationalBufferSeconds<0){deny(c,'operational_buffer_unknown');continue;}
  let origin=null,route=null,lower=null,upper=null,estimate=null,displayRange=null,nearPickupProof=null,gpsRoadProof=null;
  if(request.pickupMode==='asap'){
   mark('operationalOrigin');
   origin=operationalOriginV1(c,{now:clock(),maxGpsAgeMs:p.maxGpsAgeMs,maxForecastAgeMs:p.maxForecastAgeMs,pickup:request.pickup});if(!origin.ok){deny(c,origin.reason);continue;}
   mark('localRouteEtaAndTraffic');
   try{if(preparationError)throw Error(preparationError);counters.localRouteCalculations++;counters.trafficLookups++;route=await router.route({scope:copy(context),origin:origin.point,destination:copy(request.pickup),departureAt:Math.max(clock(),origin.availableAt)+c.operationalBufferSeconds*1000,gpsRoadContext:origin.source==='fresh_current_gps'});}catch(error){deny(c,'graph_ambiguity',error?.message);continue;}
   mark('candidateConfidence');
   const evidencePickup=officialAddressEvidencePickupV1(route,origin.point,request.pickup,context);
   if(route?.gpsRoadEvidence||origin.requiresGpsRoadProof&&!route?.nearPickupEvidence){
    if(!safeGpsRoadProof(route,origin,evidencePickup,context,d,clock(),p.maxGpsAgeMs,p.maxEvidenceAgeMs)){deny(c,'graph_ambiguity','driver_gps_road_context_unproven');continue;}
    gpsRoadProof=route.gpsRoadEvidence;
   }
   if(origin.requiresNearPickupRoadProof||route?.nearPickupEvidence){
    if(!safeNearPickupRoadProof(route,origin,evidencePickup,context,d,clock(),p.maxGpsAgeMs,p.maxEvidenceAgeMs)){deny(c,'graph_ambiguity','near_pickup_road_context_unproven');continue;}
    nearPickupProof=route.nearPickupEvidence;
   }
   if(!route||route.graphVersion!==context.graphVersion||route.evidenceRevision!==context.evidenceRevision||!same(route,context)||!reliableRouteQualityV1(route)
    ||route.quality.incident===true||route.quality.conflict===true||route.quality.ambiguous===true||!age(clock(),route.observedAt,p.maxEvidenceAgeMs)||!finite(route.validUntil)||route.validUntil<=now
    ||!finite(route.seconds)||route.seconds<0||!finite(route.distanceMeters)||route.distanceMeters<0||!finite(route.quality.errorSeconds)||route.quality.errorSeconds<0){deny(c,'traffic_uncertainty');continue;}
   const ready=Math.max(0,(Math.max(origin.availableAt,route.observedAt)-now)/1000)+c.operationalBufferSeconds;
   const reservationError=route.quality.reservationErrorSeconds??route.quality.errorSeconds;
   if(!finite(reservationError)||reservationError<route.quality.errorSeconds){deny(c,'traffic_uncertainty');continue;}
   lower=Math.max(ready,ready+route.seconds-reservationError,request.serverDecisionReadyAt?Math.max(0,(request.serverDecisionReadyAt-now)/1000):0);estimate=ready+route.seconds+(request.humanResponseAllowanceSeconds??0);upper=estimate+reservationError+origin.availabilityErrorSeconds;
   if(route.quality.productGrade===true){const range=productPickupRangeV1({seconds:estimate,errorSeconds:route.quality.errorSeconds,availabilityErrorSeconds:origin.availabilityErrorSeconds,confidence:route.quality.tier,conservative:route.quality.conservative,trafficState:route.quality.trafficState,trafficConfidence:route.quality.trafficConfidence});if(!range){deny(c,'traffic_uncertainty');continue;}displayRange=range;
    // The canonical approach planner uses whole seconds rounded upward.
    // Anchor the earliest possible departure to this candidate's current
    // evaluation time, not the start of a potentially long batch. Matching
    // that precision prevents fractional seconds becoming a false rejection.
    // Busy availability and the operational buffer remain part of the bound.
    const departureReadyAt=Math.max(clock(),origin.availableAt)+c.operationalBufferSeconds*1000;
    lower=Math.max(lower,(departureReadyAt+Math.ceil(Math.max(0,route.seconds-reservationError))*1000-now)/1000);
    lower=(Math.ceil((now+lower*1000)/1000)*1000-now)/1000;
    // Display rounding is presentation. Reserve an extra minute that covers
    // its outward rounding, then quantize the absolute upper timestamp.
    // Relative minute rounding would drift a prepared offer on every ms.
    upper=(Math.ceil((now+(upper+60)*1000)/1000)*1000-now)/1000;}
   // Only the trusted canonical bridge supplies this existing reservation.
   // Fresh route, GPS, traffic and availability still have to fit; every
   // business gate below checks the full interval through the sealed upper
   // bound, including future bookings in the retained response slack.
   if(request.reservationPickupAt!=null){
    if(!finite(request.reservationPickupAt)||request.reservationPickupAt<=now||now+upper*1000>request.reservationPickupAt){deny(c,'reservation_window_unreachable');continue;}
    upper=(request.reservationPickupAt-now)/1000;
   }
   // Duration and a wider honest ETA range rank the candidate; they do not
   // hide it. Existing business gates still validate the full arrival window.
  }
  const arrivalWindow=request.pickupMode==='asap'?{from:now+lower*1000,until:now+upper*1000}:{from:request.pickupAt,until:request.pickupAt};
  if(!finite(arrivalWindow.from)||!finite(arrivalWindow.until)||arrivalWindow.from<now||arrivalWindow.until<arrivalWindow.from){deny(c,'traffic_uncertainty');continue;}
  mark('canonicalBusinessAndFutureBookingGates');
  let business;try{business=await evaluateBusiness({evaluationSession,candidate:copy(c),request:copy(request),context:copy(context),arrivalWindow:copy(arrivalWindow),origin:copy(origin),route:copyOfficialAddressRouteEvidenceV1(route)});}catch{deny(c,'business_evidence_unavailable');continue;}
  const failed=REQUIRED_BUSINESS_GATES.find(k=>business?.gates?.[k]!==true);
  if(!business?.allowed||failed||!same(business,context)||business.evidenceRevision!==context.evidenceRevision||!age(clock(),business.checkedAt,p.maxEvidenceAgeMs)
   ||business.arrivalWindow?.from!==arrivalWindow.from||business.arrivalWindow?.until!==arrivalWindow.until||request.pickupMode==='scheduled'&&business.plannedAvailabilityVerified!==true){deny(c,business?.canonicalReason??failed??'business_evidence_stale');continue;}
  const validUntil=Math.min(now+p.maxEvidenceAgeMs,business.validUntil??0,route?.validUntil??Infinity,nearPickupProof?.validUntil??Infinity,gpsRoadProof?.validUntil??Infinity,request.deadlineAt??Infinity,request.pickupMode==='asap'?d.gps.capturedAt+p.maxGpsAgeMs:Infinity);
  if(!finite(validUntil)||validUntil<=now){deny(c,'stale_evidence');continue;}
  rows.push({schema:RELIABLE_CHOICE_V1,...copy(context),driver_id:d.driver_id,vehicle_id:v.vehicle_id,vehicleType:v.vehicleType??v.vehicle_type??v.category,category:v.category,passengerCapacity:capacity.passengers,luggageCapacity:capacity.baggage,
   capabilities:copy(v.capabilities),presence:copy(d.presence),gpsFreshnessMs:request.pickupMode==='asap'?now-d.gps.capturedAt:null,operationalOrigin:copy(origin?.point??null),originSource:origin?.source??'planned_schedule',
   availableAt:origin?.availableAt??request.pickupAt,currentTripState:origin?.currentTripState??d.trip?.state??'planned',operationalBufferSeconds:c.operationalBufferSeconds,
   futureBookingConflicts:false,serviceAreaEligible:true,relation:c.relation,estimatedPickupEtaSeconds:estimate,estimatedPickupDistanceMeters:route?.distanceMeters??null,estimatedPickupDistanceUncertaintyMeters:gpsRoadProof?.roadContext.junction?.localLegDistanceBoundMeters??0,
   ...(request.pickupMode==='asap'&&route?.productEvidence?.etaBreakdown?{etaBreakdown:{...copy(route.productEvidence.etaBreakdown),responseAllowanceSeconds:request.humanResponseAllowanceSeconds??0,operationalWaitSeconds:Math.max(0,(Math.max(origin.availableAt,route.observedAt)-now)/1000)+c.operationalBufferSeconds,availabilityUncertaintySeconds:origin.availabilityErrorSeconds,trafficState:route.quality.trafficState,trafficConfidence:route.quality.trafficConfidence}}:{}),
   reservationPickupUpperSeconds:upper,etaRangeSeconds:request.pickupMode==='asap'?(displayRange??[lower,upper]):null,etaConfidence:route?.quality.tier??'planned_verified',routeConfidence:route?.quality.tier??'planned_verified',locationConfidence:origin?.source==='fresh_current_gps'?driverGpsConfidenceV1(d.gps,clock()):null,uncertaintyReasons:gpsRoadProof?.roadContext.locationConfidence==='low'?['gps_accuracy_road_context']:nearPickupProof?['gps_low_accuracy_near_pickup']:[],
   etaKind:route?.etaKind??'validated_estimate',certifiedEta:route?.certifiedEta??false,visibility:'visible',routeEvidenceId:route?.evidenceId??null,offerPriority:0,evidenceRevision:context.evidenceRevision,validUntil,pickupMode:request.pickupMode,publicPhotoUrl:typeof v.public_photo_url==='string'&&/^https:\/\/[^@\s]+$/.test(v.public_photo_url)&&v.public_photo_url.length<=2048?v.public_photo_url:null,publicVehicleName:typeof v.publicName==='string'?v.publicName.slice(0,100):v.category});
  mark(null);
 }
 mark('sortingAndVehicleDeduplication');
 rows.sort((a,b)=>(a.estimatedPickupEtaSeconds??0)-(b.estimatedPickupEtaSeconds??0)||(request.pickupMode==='asap'?a.estimatedPickupDistanceMeters-b.estimatedPickupDistanceMeters||a.availableAt-b.availableAt||(['high','medium'].indexOf(a.etaConfidence)-['high','medium'].indexOf(b.etaConfidence)):0)||a.vehicle_id.localeCompare(b.vehicle_id)||a.driver_id.localeCompare(b.driver_id));
 const finishedAt=clock();
 const vehicleIds=new Set();
 const unique=rows.filter(r=>{if(request.deadlineAt!=null&&finishedAt>=request.deadlineAt){rejected.push({vehicle_id:r.vehicle_id,driver_id:r.driver_id,reason:'deadline'});return false;}if(r.validUntil<=finishedAt){rejected.push({vehicle_id:r.vehicle_id,driver_id:r.driver_id,reason:'stale_evidence'});return false;}if(vehicleIds.has(r.vehicle_id))return false;vehicleIds.add(r.vehicle_id);return true;});unique.forEach((r,i)=>r.offerPriority=i);
 if(readRevision&&await readRevision()!==context.evidenceRevision){unique.length=0;rejected.push({reason:'evidence_revision_changed'});}
 mark('payloadConstruction');
 counters.visible=unique.length;counters.payloadBytes=new TextEncoder().encode(JSON.stringify(unique.map(c=>reliableCandidatePublicV1(c,{now:clock()})))).length;
 mark(null);
 return freeze({schema:RELIABLE_CHOICE_V1,scope:copy(context),at:now,validUntil:unique.length?Math.min(...unique.map(r=>r.validUntil)):now,rows:unique,rejected,counters,
  escalationReason:unique.length?null:rejected[0]?.reason??'no_candidate',publicIntegration:false,authorityCommitted:false});
}

export function reliableCandidatePageV1(list,{offset=0,limit=10,now=Date.now(),evidenceRevision=list.scope.evidenceRevision}={}){
 if(!Number.isSafeInteger(offset)||offset<0||offset>list.rows.length||!Number.isSafeInteger(limit)||limit<1||limit>100||now>=list.validUntil||evidenceRevision!==list.scope.evidenceRevision)throw Error('reliable_candidate_page_stale');
 return {schema:RELIABLE_CHOICE_V1,evidence_revision:evidenceRevision,estimate:true,vehicles:list.rows.slice(offset,offset+limit).map(c=>reliableCandidatePublicV1(c,{now})),next_offset:offset+limit<list.rows.length?offset+limit:null};
}
