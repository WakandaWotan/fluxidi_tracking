import {applyNationalSpeedTimeV1} from '../../../retained-source/workers/booking/modules/osm_speed_rules_v1.mjs';
// Product estimate, not a calibration certificate. Static times and policy
// margins are labelled assumptions. No network/provider dependency exists.
export const PRODUCT_ETA_V1='fluxidi-product-estimated-eta-v1';
const finite=n=>typeof n==='number'&&Number.isFinite(n),same=(a,b)=>['tenant_id','company_id','region_id','graphVersion','evidenceRevision'].every(k=>a?.[k]===b?.[k]);
const fresh=(r,now)=>finite(r?.observedAt)&&r.observedAt<=now&&now-r.observedAt<=300000&&finite(r.validUntil)&&r.validUntil>now;
export const TRAFFIC_PUBLICATION_STATES=Object.freeze(['AVAILABLE','UNAVAILABLE','STALE']);
const signalKinds=new Set(['closure','restriction','congestion','roadworks','measured-segment','observed-aggregate','fleet-traversal','historical-profile']);
const safeSignal=(s,scope,now)=>s&&s.graphVersion===scope.graphVersion&&s.match==='exact'&&s.rights==='usable'&&fresh(s,now)&&signalKinds.has(s.kind)&&Array.isArray(s.edgeIds)&&s.edgeIds.length>0&&s.edgeIds.length<=8192&&s.edgeIds.every(id=>Number.isSafeInteger(id)&&id>=0)&&
 (s.tenant_id==null||s.tenant_id===scope.tenant_id)&&(s.company_id==null||s.company_id===scope.company_id)&&
 (s.direction==null||['forward','both'].includes(s.direction));
// A delay can extend travel beyond the static calendar interval. Retain the
// precomputed all-time floor in that case, rather than using an unsafe night
// speed after an unmodelled daytime arrival. No repeated route search or I/O.
function bindSpeedTime(route,departureAt,traffic,scope,now){
 const delay=(traffic.signals??[]).some(s=>safeSignal(s,scope,now)&&!['closure','restriction'].includes(s.kind));
 const result=applyNationalSpeedTimeV1(route,delay?undefined:departureAt);
 return delay&&result.speedTimeEvidence?{...result,speedTimeEvidence:{mode:'ALL_TIME_CONSERVATIVE',reason:'traffic_duration_requires_conservative_floor'}}:result;
}
// A local policy decision is not a fresh traffic snapshot. Missing/stale input
// has no source timestamp; only newly calculated road evidence gets a 15s
// lease. No publication or synthetic traffic is written by this adapter.
export function resolveProductTrafficV1({traffic,scope,now,reason=null,retainedSignals=[],retainedRevision=''}){
 if(traffic?.schema==='fluxidi-product-traffic-policy-v1'&&same(traffic,scope))return traffic;
 let state='AVAILABLE';
 if(!traffic||!same(traffic,scope)||typeof traffic.revision!=='string'||!traffic.revision||!finite(traffic.observedAt)||traffic.observedAt>now||!finite(traffic.validUntil)||!Array.isArray(traffic.signals)||traffic.signals.length>8192||!['current','partial'].includes(traffic.status))state='UNAVAILABLE';
 else if(now-traffic.observedAt>300000||traffic.validUntil<=now)state='STALE';
 const accepted=state==='AVAILABLE'?traffic.signals.filter(s=>safeSignal(s,scope,now)):[];
 const ignored=state==='AVAILABLE'?traffic.signals.length-accepted.length:traffic?.signals?.length??0;
 if(state==='AVAILABLE'&&accepted.length===0&&(ignored>0||traffic.unmatchedCritical===true||traffic.criticalConflict===true))state='UNAVAILABLE';
 // A failed read/reused revision must not erase a still-fresh known closure.
 // Expired signals never acquire a new observation timestamp or lease.
 if(state!=='AVAILABLE')accepted.push(...retainedSignals.filter(s=>safeSignal(s,scope,now)&&(['closure','restriction'].includes(s.kind)||s.critical===true||s.conflict===true)));
 const degraded=ignored>0||traffic?.unmatchedCritical===true||traffic?.criticalConflict===true;
 return {schema:'fluxidi-product-traffic-policy-v1',...structuredClone(scope),trafficState:state,trafficConfidence:state==='AVAILABLE'?(degraded?'low':traffic.status==='current'?'high':'medium'):'unavailable',
  revision:state==='AVAILABLE'?traffic.revision:(state.toLowerCase()+(accepted.length?'.known.'+retainedRevision.slice(0,70):'')),
  publicationObservedAt:state==='AVAILABLE'?traffic.observedAt:null,publicationValidUntil:state==='AVAILABLE'?traffic.validUntil:null,
  policyObservedAt:now,policyValidUntil:Math.min(now+15000,state==='AVAILABLE'?traffic.validUntil:Infinity,...accepted.map(s=>s.validUntil)),
  signals:structuredClone(accepted),ignoredSignals:ignored,reason:reason??(state==='AVAILABLE'?degraded?'unsafe_items_ignored':null:state==='STALE'?'traffic_stale':'traffic_unavailable'),
  source:state==='AVAILABLE'?'graph-bound-traffic':'static-road-profile-policy',scientificGroundTruth:false};
}
export function reliableRouteQualityV1(route){
 const q=route?.quality;
 if(!q||!finite(q.errorSeconds)||q.errorSeconds<0||q.ambiguous||q.conflict||q.incident)return false;
 if(q.validated===true&&q.tier==='high')return true;
 return q.productGrade===true&&q.modelVersion===PRODUCT_ETA_V1&&q.validated===false&&['high','medium'].includes(q.tier)&&route.evidenceClass==='EXACT_STATIC_ROUTE'&&route.etaKind==='product_estimate'&&route.certifiedEta===false;
}
export function productPickupRangeV1({seconds,errorSeconds,availabilityErrorSeconds=0,confidence,conservative=false,trafficState,trafficConfidence}){
 if(!finite(seconds)||seconds<0||!finite(errorSeconds)||errorSeconds<0||!finite(availabilityErrorSeconds)||availabilityErrorSeconds<0||!['high','medium'].includes(confidence))return null;
 // ETA is an approximate arrival estimate. The upper edge includes the
 // transparent one-sided safety margin and uncertain busy availability.
 const upper=seconds+errorSeconds+availabilityErrorSeconds,quantum=upper<=120?5:60;
 const range=[Math.max(0,Math.floor((seconds+1e-6)/quantum)*quantum),Math.ceil(upper/quantum)*quantum];
 return range.every(finite)&&range[1]>=range[0]?range:null;
}
export function assessProductEtaV1({route,scope,traffic,departureAt,now}){
 if(!finite(now)||route?.graphVersion!==scope.graphVersion||route.evidenceClass!=='EXACT_STATIC_ROUTE'||!finite(route.staticSeconds)||route.staticSeconds<0||!finite(route.distanceMeters)||route.distanceMeters<0||!Array.isArray(route.edges)||!finite(departureAt)||departureAt<now-15000)return {visible:false,reason:'product_evidence_insufficient'};
 traffic=resolveProductTrafficV1({traffic,scope,now});
 route=bindSpeedTime(route,departureAt,traffic,scope,now);
 if(traffic.policyObservedAt>now||traffic.policyValidUntil<=now)return {visible:false,reason:'product_evidence_insufficient'};
 const ids=new Set(route.edges.map(e=>e.id)),secondsByEdge=new Map(),visits=new Map();for(const e of route.edges){if(!Number.isSafeInteger(e.id)||e.id<0||!finite(e.seconds)||e.seconds<0)return {visible:false,reason:'route_edge_invalid'};const total=(secondsByEdge.get(e.id)??0)+e.seconds;if(!finite(total))return {visible:false,reason:'route_edge_invalid'};secondsByEdge.set(e.id,total);visits.set(e.id,(visits.get(e.id)??0)+1);}
 // A less precise GPS observation can lie elsewhere on the same corridor.
 // Known hard restrictions on that proven context cannot be bypassed by the
 // route from its reported center. Travel adjustments still use route edges.
 const safetyIds=new Set(ids);
 for(const proof of [route.nearPickupEvidence,route.gpsRoadEvidence].filter(Boolean)){const contextEdges=proof.roadContext?.edgeIds;if(!Array.isArray(contextEdges)||!contextEdges.length||contextEdges.some(id=>!Number.isSafeInteger(id)||id<0))return {visible:false,reason:'product_frontage_invalid'};for(const id of contextEdges)safetyIds.add(id);}
 let conservative=traffic.trafficState!=='AVAILABLE'||traffic.trafficConfidence==='low';
 let seconds=route.staticSeconds,tier=!conservative&&traffic.trafficConfidence==='high'&&departureAt<=now+120000?'high':'medium',margin=0;const applied=[],quarantined=traffic.ignoredSignals?['unsafe_traffic_items_ignored']:[];
 for(const signal of traffic.signals){
  // Source binding and rights remain independent of product ETA. Missing
  // representativity can never turn point speed into segment travel time.
  if(signal.graphVersion!==scope.graphVersion||signal.match!=='exact'||!Array.isArray(signal.edgeIds)||!signal.edgeIds.length||!signal.edgeIds.some(id=>safetyIds.has(id))){quarantined.push('unmatched_or_other_route');if(signal.match!=='exact')tier='medium';continue;}
  if(!safeSignal(signal,scope,now)){quarantined.push('stale_or_unusable_route_signal');conservative=true;tier='medium';continue;}
  if(signal.kind==='closure'||signal.kind==='restriction')return {visible:false,reason:'official_hard_restriction'};
  if(signal.conflict||signal.critical===true)return {visible:false,reason:'critical_traffic_conflict'};
 }
 // Per edge authority precedence, never stack official and fleet modifiers.
 const rank={congestion:1,roadworks:1,'measured-segment':2,'observed-aggregate':2,'fleet-traversal':3,'historical-profile':4};
 for(const [id,base]of secondsByEdge){
  const choices=traffic.signals.filter(s=>s.graphVersion===scope.graphVersion&&s.match==='exact'&&s.edgeIds?.includes(id)&&fresh(s,now)&&s.rights==='usable'&&rank[s.kind]).sort((a,b)=>rank[a.kind]-rank[b.kind]||b.observedAt-a.observedAt);
  const signal=choices[0];if(!signal)continue;
  if(['congestion','roadworks'].includes(signal.kind)){
   // A bounded policy uplift, not a measured speed or claimed forecast.
   if(!['minor','moderate'].includes(signal.severity))return {visible:false,reason:'unresolved_incident'};
   const factor=signal.severity==='moderate'?1.5:1.2;
   seconds+=base*(factor-1);margin+=base*.15;tier='medium';applied.push({edgeId:id,source:signal.kind,policyFactor:factor});
  }else{
   if(signal.representative!==true||signal.edgeIds.length!==1||!finite(signal.seconds)||signal.seconds<=0||!finite(signal.confidence)||signal.confidence<.85){quarantined.push('representativity_or_quality_unproven');tier='medium';conservative=true;continue;}
   if(signal.seconds<base*.5||signal.seconds>base*4)return {visible:false,reason:'contradictory_speed_or_duration'};
   const adjusted=Math.max(base,signal.seconds*visits.get(id));seconds+=adjusted-base;applied.push({edgeId:id,source:signal.kind,seconds:adjusted});
  }
 }
 if(route.frontageConfidence==='medium')tier='medium';
 const frontageMargin=route.frontageUncertaintySeconds??0;
 if(!finite(frontageMargin)||frontageMargin<0)return {visible:false,reason:'product_frontage_invalid'};
 // A complete GPS road proof and actual unpacked edge costs allow a bounded
 // short-approach policy. Missing traffic remains explicitly unavailable:
 // use at least30s and up to100% of the drive time, capped at the previous
 // 150s floor. This is an uncalibrated uncertainty policy, not live traffic.
 // Other routes, longer approaches and incomplete edge evidence retain the
 // old floor. No road/access/closure gate is changed by this ETA policy.
 const shortProof=!!(route.gpsRoadEvidence||route.nearPickupEvidence||route.preciseGpsApproach===true)&&route.distanceMeters<=1000;
 const edgeMeters=shortProof?route.edges.reduce((sum,e)=>sum+(finite(e.distanceMeters)&&e.distanceMeters>=0?e.distanceMeters:NaN),0):NaN;
 const boundedShortApproach=shortProof&&finite(edgeMeters)&&Math.abs(edgeMeters-route.distanceMeters)<=1e-6*Math.max(1,route.distanceMeters);
 const modelFloor=conservative?(boundedShortApproach?Math.min(150,Math.max(30,seconds)):150):tier==='high'||boundedShortApproach?30:90;
 const modelMargin=Math.max(modelFloor,seconds*(conservative?.35:tier==='high'?.1:.25));
 const errorSeconds=modelMargin+margin+frontageMargin;
 // Keep the previous occupancy/conflict window until field calibration has
 // proved a smaller reservation safe. A better ETA must not silently release
 // capacity earlier or admit a conflicting future booking.
 const reservationFrontage=route.frontageReservationUncertaintySeconds??frontageMargin;
 if(!finite(reservationFrontage)||reservationFrontage<frontageMargin)return {visible:false,reason:'product_frontage_invalid'};
 const reservationErrorSeconds=Math.max(errorSeconds,Math.max(conservative?150:tier==='high'?30:90,seconds*(conservative?.35:tier==='high'?.1:.25))+margin+reservationFrontage);
 if(!finite(seconds)||seconds<0||!finite(margin)||margin<0||!finite(errorSeconds)||errorSeconds<0)return {visible:false,reason:'product_evidence_insufficient'};
 return {visible:true,seconds,errorSeconds,reservationErrorSeconds,confidence:tier,trafficState:traffic.trafficState,trafficConfidence:conservative?(traffic.trafficState==='AVAILABLE'?'low':'unavailable'):traffic.trafficConfidence,conservative,applied,quarantined,etaBreakdown:{drivingSeconds:seconds,modelUncertaintySeconds:modelMargin,incidentUncertaintySeconds:margin,gpsRoadUncertaintySeconds:frontageMargin,shortApproachPolicy:boundedShortApproach,calibrated:false},speedTimeEvidence:route.speedTimeEvidence??null,assumptions:'Static road-profile estimate; high margin max(30s,10%); medium max(90s,25%); missing traffic max(150s,35%). Complete GPS road proofs <=1km use30s medium floor and missing-traffic floor min(150s,max(30s,drive time)); bounded GPS/incident margins separate. Product policy, not measured calibration accuracy; previous reservation bounds retained.'};
}

export function createProductGradeRegionalRoutesV1({regional,scope,readTraffic,readRevision,clock=Date.now}){
 if(regional?.kind!=='STATIC_REGIONAL_POINTS_V1'||typeof readTraffic!=='function'||typeof readRevision!=='function'||!scope?.tenant_id||!scope.company_id||!scope.region_id||!scope.graphVersion||!scope.evidenceRevision)throw Error('product_regional_contract_invalid');
 const fixed=structuredClone(scope),cache=new Map();let prepared=null;
 const metrics={graphBatches:0,localRouteCalculations:0,routeReuses:0,trafficSnapshots:0,trafficLookups:0,etaAssessments:0,commercialDispatchCalls:0,prepareMs:0,lookupMs:0,adjustmentMs:0};
 // ASAP evidence must not be reused by the unchanged manual/planned path.
 const key=(a,b,gpsRoadContext=false)=>JSON.stringify([fixed,a,b,gpsRoadContext===true]);
 // The router's low-precision GPS proof is scoped to this exact observation
 // and pickup. A prepared static route must never extend its shorter lease.
 function nearPickupLease(raw,origin,destination,gpsRoadContext=false){
  const generic=raw?.route?.gpsRoadEvidence,proof=generic??raw?.route?.nearPickupEvidence;if(!proof)return prepared.until;
  const now=clock(),capturedAt=origin?.access?.capturedAt;
  if(generic&&gpsRoadContext!==true||proof.schema!==(generic?'fluxidi-driver-gps-road-v1':'fluxidi-near-pickup-road-v1')||proof.tenant_id!==fixed.tenant_id||proof.company_id!==fixed.company_id||proof.graphVersion!==fixed.graphVersion||proof.accessContextRevision!==fixed.accessContextRevision
   ||JSON.stringify(proof.origin)!==JSON.stringify(origin)||JSON.stringify(proof.pickup)!==JSON.stringify(destination)
   ||origin?.access?.kind!=='gps'||!finite(capturedAt)||capturedAt>now||now-capturedAt>30000
   ||!finite(proof.observedAt)||proof.observedAt>now||now-proof.observedAt>15000||!finite(proof.validUntil)||proof.validUntil<=now||proof.validUntil>capturedAt+30000)throw Error('near_pickup_road_context_unproven');
  if(generic?.continuity&&(!finite(generic.continuity.priorCapturedAt)||generic.continuity.priorCapturedAt>=capturedAt||proof.observedAt-generic.continuity.priorCapturedAt>15000||generic.continuity.priorCapturedAt>proof.observedAt||proof.validUntil>generic.continuity.priorCapturedAt+15000))throw Error('driver_gps_continuity_unproven');
  return Math.min(prepared.until,proof.validUntil);
 }
 async function prepare({origins,destination,scope:input,gpsRoadContext=false}){
  if(!same(input,fixed)||!Array.isArray(origins)||origins.length>5000)throw Error('product_route_scope');
  const start=performance.now(),now=clock();let inputTraffic;
  try{inputTraffic=await readTraffic(fixed);}catch{inputTraffic=null;}
  const traffic=structuredClone(resolveProductTrafficV1({traffic:inputTraffic,scope:fixed,now,retainedSignals:prepared?.traffic.signals??[],retainedRevision:prepared?.traffic.revision??''})),sourceRevision=readRevision();metrics.trafficSnapshots++;
  if(traffic.trafficState==='AVAILABLE'&&sourceRevision!==traffic.revision)throw Error('product_traffic_revision_changed');
  const batch=await regional.routeMany({origins,destination,scope:fixed,trafficRevision:traffic.revision,gpsRoadContext:gpsRoadContext===true});metrics.graphBatches++;metrics.localRouteCalculations+=origins.length;
  if(clock()<now)throw Error('product_clock_reversed');
  if(readRevision()!==sourceRevision)throw Error('product_traffic_revision_changed');
  if(clock()>=traffic.policyValidUntil)throw Error('product_traffic_evidence_expired');
  // Multi-leg canonical checks must not discard the prepared pickup batch.
  // Retained evidence keeps its original lease: a later route never refreshes
  // an older result or extends it across a traffic revision.
  const retain=prepared&&now>=prepared.at&&now<prepared.until&&prepared.traffic.revision===traffic.revision;
  if(!retain)cache.clear();
  for(let i=0;i<origins.length;i++){const k=key(origins[i],destination,gpsRoadContext);if(!cache.has(k)&&cache.size>=5000)cache.delete(cache.keys().next().value);cache.set(k,batch.results[i]);}
  prepared={traffic,sourceRevision,at:retain?prepared.at:now,until:Math.min(retain?prepared.until:now+15000,traffic.policyValidUntil)};metrics.prepareMs+=performance.now()-start;
 }
 return Object.freeze({kind:'LOCAL_ROUTING_ONLY_V1',productModelVersion:PRODUCT_ETA_V1,metrics,
  async prepareCandidates({origins,destination,scope:input,gpsRoadContext=false}){await prepare({origins,destination,scope:input,gpsRoadContext});},
  // Manual/planned occupancy is a static planning bound, never a public ETA
  // or a claim of future traffic accuracy. Known closures/ambiguity still deny.
  async planRoute({scope:input,origin,destination,departureAt,gpsRoadContext=false}){
   if(!same(input,fixed))throw Error('product_route_scope');const now=clock();
   if(!prepared||now<prepared.at||now>=prepared.until||readRevision()!==prepared.sourceRevision||!cache.has(key(origin,destination,gpsRoadContext)))await prepare({origins:[origin],destination,scope:input,gpsRoadContext});
   const raw=cache.get(key(origin,destination,gpsRoadContext)),traffic=prepared.traffic;
   if(!raw?.ok||raw.route.graphVersion!==fixed.graphVersion){const error=Error('reliable_planning_route_unknown');error.routeFailureReason=raw?.reason??null;throw error;}
   const validUntil=nearPickupLease(raw,origin,destination,gpsRoadContext);
   const ids=new Set([...raw.route.edges.map(e=>e.id),...(raw.route.nearPickupEvidence?.roadContext?.edgeIds??[]),...(raw.route.gpsRoadEvidence?.roadContext?.edgeIds??[])]);
   for(const signal of traffic.signals??[]){if(!safeSignal(signal,fixed,now))continue;if(signal.edgeIds.some(id=>ids.has(id))&&(signal.conflict||signal.critical===true||['closure','restriction'].includes(signal.kind)))throw Error('reliable_planning_route_closed');}
   const timeRoute=bindSpeedTime(raw.route,departureAt,traffic,fixed,now);let adjusted=0;
   for(const edge of timeRoute.edges){let bound=edge.seconds;
    for(const signal of traffic.signals??[]){if(!safeSignal(signal,fixed,now)||!signal.edgeIds.includes(edge.id))continue;
     if(signal.graphVersion!==fixed.graphVersion)throw Error('reliable_planning_traffic_graph');
     if(['congestion','roadworks'].includes(signal.kind)){if(!['minor','moderate'].includes(signal.severity))throw Error('reliable_planning_incident_unknown');bound=Math.max(bound,edge.seconds*(signal.severity==='moderate'?1.65:1.35));}
     else if(['measured-segment','observed-aggregate','fleet-traversal','historical-profile'].includes(signal.kind)){
      if(signal.representative!==true||signal.edgeIds.length!==1||!Number.isFinite(signal.seconds)||signal.seconds<=0||!Number.isFinite(signal.confidence)||signal.confidence<.85)continue;
      if(signal.seconds<edge.seconds*.5||signal.seconds>edge.seconds*4)throw Error('reliable_planning_speed_unknown');
      bound=Math.max(bound,signal.seconds*1.25);
     }else throw Error('reliable_planning_signal_unknown');
    }adjusted+=bound;
   }
   metrics.trafficLookups++;metrics.routeReuses++;
   return {...structuredClone(fixed),evidenceId:raw.route.evidenceId+':'+traffic.revision+':planning',distanceMeters:raw.route.distanceMeters,geometry:raw.route.geometry,observedAt:prepared.at,validUntil,planningOnly:true,operationalDurationBoundSeconds:Math.ceil(Math.max(adjusted*1.5,adjusted+180)),assumptions:'Static occupancy bound plus max(50%,180s), not calibrated ETA; existing operational buffers also apply.'};
  },
  // Internal navigation consumer. Immutable road metadata is bound to the
  // exact directed route, never inferred from a neighbouring road or provider.
  async navigationRoute(args){
   const checked=await this.route(args),raw=cache.get(key(args.origin,args.destination,args.gpsRoadContext===true));
   if(!raw?.ok||raw.route.graphVersion!==fixed.graphVersion||raw.route.evidenceClass!=='EXACT_STATIC_ROUTE'
     ||!Array.isArray(raw.route.edges)||!Array.isArray(raw.route.geometry)||raw.route.geometry.length!==raw.route.edges.length+1
     ||typeof regional.describeRouteEdges!=='function')throw Error('navigation_static_route_unproven');
   const edges=raw.route.edges.map(e=>({id:e.id,way:e.way,ordinal:e.ordinal,direction:e.direction,partitionId:e.partitionId,
    ...(e.terminalObject?{terminalObject:structuredClone(e.terminalObject)}:{}),
    seconds:e.seconds,distanceMeters:e.distanceMeters,...(e.partial===true?{partial:true}:{})}));
   const metadata=await regional.describeRouteEdges({scope:fixed,edges});
   if(metadata.graphVersion!==fixed.graphVersion||metadata.rows?.length!==edges.length||checked.validUntil<=clock())throw Error('navigation_metadata_unproven');
   return {...checked,navigationEvidence:{schema:'fluxidi-directed-navigation-evidence-v1',...structuredClone(fixed),
    coreEvidenceId:raw.route.evidenceId,staticSeconds:raw.route.staticSeconds,edges,roads:metadata.rows}};
  },
  // Internal consumer only: financial routing retains the exact existing core
  // basis, while the public ETA method and traffic confidence remain unchanged.
  async financialRoute(args){
   if(args.gpsRoadContext===true||args.origin?.access?.kind==='gps'||args.destination?.access?.kind==='gps')throw Error('financial_route_address_required');
   const checked=await this.route(args),raw=cache.get(key(args.origin,args.destination,false));
   if(!raw?.ok||raw.route.evidenceClass!=='EXACT_STATIC_ROUTE'||raw.route.graphVersion!==fixed.graphVersion||!Array.isArray(raw.route.edges)
     ||!finite(raw.route.staticSeconds)||raw.route.staticSeconds<0||!finite(raw.route.distanceMeters)||raw.route.distanceMeters<0
     ||checked.validUntil<=clock())throw Error('financial_static_route_unproven');
   const edges=raw.route.edges.map(e=>({id:e.id,seconds:e.seconds,distanceMeters:e.distanceMeters,
     ...(e.way!=null?{way:e.way}:{}),...(e.ordinal!=null?{ordinal:e.ordinal}:{}),...(e.direction!=null?{direction:e.direction}:{}),...(e.partial===true?{partial:true}:{})}));
   if(edges.some(e=>!finite(e.seconds)||e.seconds<0||!finite(e.distanceMeters)||e.distanceMeters<0)
     ||Math.abs(edges.reduce((n,e)=>n+e.seconds,0)-raw.route.staticSeconds)>1e-6*Math.max(1,raw.route.staticSeconds)
     ||Math.abs(edges.reduce((n,e)=>n+e.distanceMeters,0)-raw.route.distanceMeters)>1e-6*Math.max(1,raw.route.distanceMeters))throw Error('financial_static_edge_totals_conflict');
   return {...checked,seconds:raw.route.staticSeconds,etaKind:'financial_static_route',certifiedEta:false,
    staticFinancialEvidence:{schema:'fluxidi-static-financial-road-basis-v1',...structuredClone(fixed),
      coreEvidenceId:raw.route.evidenceId,staticSeconds:raw.route.staticSeconds,distanceMeters:raw.route.distanceMeters,
      edges,roadAccessEvidence:structuredClone(raw.route.roadAccessEvidence??null)}};
  },
  async route({scope:input,origin,destination,departureAt,gpsRoadContext=false}){
   if(!same(input,fixed))throw Error('product_route_scope');const start=performance.now(),now=clock();
   if(!prepared||now<prepared.at||now>=prepared.until||readRevision()!==prepared.sourceRevision||!cache.has(key(origin,destination,gpsRoadContext)))await prepare({origins:[origin],destination,scope:input,gpsRoadContext});
   else metrics.routeReuses++;
   const raw=cache.get(key(origin,destination,gpsRoadContext));if(!raw?.ok)throw Error(raw?.reason??'regional_route_unavailable');metrics.trafficLookups++;metrics.lookupMs+=performance.now()-start;
   const validUntil=nearPickupLease(raw,origin,destination,gpsRoadContext);
   const adjustmentAt=performance.now(),prediction=assessProductEtaV1({route:raw.route,scope:fixed,traffic:prepared.traffic,departureAt,now:clock()});metrics.etaAssessments++;metrics.adjustmentMs+=performance.now()-adjustmentAt;
   if(!prediction.visible)throw Error(prediction.reason);if(readRevision()!==prepared.sourceRevision)throw Error('product_traffic_revision_changed');
   return {...structuredClone(fixed),evidenceId:raw.route.evidenceId+':'+prepared.traffic.revision+':'+PRODUCT_ETA_V1,evidenceClass:raw.route.evidenceClass,etaKind:'product_estimate',certifiedEta:false,seconds:prediction.seconds,distanceMeters:raw.route.distanceMeters,geometry:raw.route.geometry,
    observedAt:prepared.at,validUntil,...(raw.route.nearPickupEvidence?{nearPickupEvidence:structuredClone(raw.route.nearPickupEvidence)}:{}),...(raw.route.gpsRoadEvidence?{gpsRoadEvidence:structuredClone(raw.route.gpsRoadEvidence)}:{}),quality:{tier:prediction.confidence,errorSeconds:prediction.errorSeconds,reservationErrorSeconds:prediction.reservationErrorSeconds,productGrade:true,modelVersion:PRODUCT_ETA_V1,validated:false,incident:false,conflict:false,ambiguous:false,trafficState:prediction.trafficState,trafficConfidence:prediction.trafficConfidence,conservative:prediction.conservative},productEvidence:{trafficRevision:prepared.traffic.revision,trafficSourceObservedAt:prepared.traffic.publicationObservedAt,...prediction}};
  },diagnostics(){return {...metrics,cacheEntries:cache.size,maximumEntries:5000,regional:regional.diagnostics()};}});
}

export function evaluatePickupRangeQualityV1({rangeSeconds,actualSeconds,toleranceSeconds=60}){
 if(!Array.isArray(rangeSeconds)||rangeSeconds.length!==2||rangeSeconds.some(x=>!finite(x)||x<0)||rangeSeconds[1]<rangeSeconds[0]||!finite(actualSeconds)||actualSeconds<0||!finite(toleranceSeconds)||toleranceSeconds<0)throw Error('product_quality_sample_invalid');
 const lateSeconds=Math.max(0,actualSeconds-rangeSeconds[1]);return {inside:actualSeconds>=rangeSeconds[0]&&actualSeconds<=rangeSeconds[1],lateSeconds,tolerated:lateSeconds<=toleranceSeconds,grossMiss:lateSeconds>Math.max(120,(rangeSeconds[1]-rangeSeconds[0])*2)};
}

// Offline aggregate contract only. No identity, production persistence or
// retention change. NAV-to-arrival remains a distinct realized pickup leg.
export function pickupLearningAggregateV1(input){
 const keys=['graphVersion','region','segmentIds','direction','weekday','timeBucket','trafficRevision','predictedSeconds','actualNavToArrivalSeconds','quality'];
 if(!input||Object.keys(input).some(k=>!keys.includes(k))||!input.graphVersion||!['forward','backward'].includes(input.direction)||!input.region||!Number.isInteger(input.weekday)||input.weekday<0||input.weekday>6||!Number.isInteger(input.timeBucket)||input.timeBucket<0||input.timeBucket>95||!input.trafficRevision||!Array.isArray(input.segmentIds)||input.segmentIds.length<1||input.segmentIds.length>512||input.segmentIds.some(x=>!Number.isSafeInteger(x)||x<0)||!finite(input.predictedSeconds)||input.predictedSeconds<=0||!finite(input.actualNavToArrivalSeconds)||input.actualNavToArrivalSeconds<=0||!finite(input.quality)||input.quality<.85||input.quality>1)throw Error('product_learning_privacy_or_quality');
 const errorSeconds=input.predictedSeconds-input.actualNavToArrivalSeconds;return {...structuredClone(input),errorSeconds,absoluteErrorSeconds:Math.abs(errorSeconds),relativeError:errorSeconds/input.actualNavToArrivalSeconds,scope:'offline aggregate; no driver/customer/booking identity or raw GPS; prediction is pre-NAV, actual is NAV-to-arrival'};
}

// Adapter over the existing P11 scoped view. No fresh feed is asserted merely
// because a cached XML file exists. Exact binding/representativity is retained.
export function productTrafficFromFabricV1({fabric,scope,now=Date.now()}){
 if(fabric?.scope?.tenant_id!==scope.tenant_id||fabric?.scope?.company_id!==scope.company_id||fabric?.graph?.version!==scope.graphVersion)throw Error('product_fabric_scope');
 const safety=fabric.safety(),snapshot=fabric.snapshotCosts(fabric.scope,{departureMs:now});
 const signals=[];
 for(const edge of snapshot.evidence){
  const common={graphVersion:scope.graphVersion,match:'exact',edgeIds:[edge.segmentId],observedAt:snapshot.at,validUntil:edge.validUntil,rights:'usable'};
  if(edge.closed){signals.push({...common,kind:'closure'});continue;}
  if(edge.conflict){signals.push({...common,kind:'congestion',critical:true});continue;}
  if(edge.incident){signals.push({...common,kind:'congestion',severity:'unknown'});continue;}
  const kind=edge.source==='official-current'&&edge.officialCoverage?'measured-segment':edge.effectiveSamples>=5&&edge.tier==='high'?'fleet-traversal':null;
  if(kind)signals.push({...common,kind,seconds:edge.seconds,representative:true,confidence:edge.confidence});
 }
 return {...structuredClone(scope),revision:String(safety.revision),observedAt:now,validUntil:Math.min(now+15000,...signals.map(s=>s.validUntil)),status:safety.degraded||!safety.coverageCertified?'partial':'current',unmatchedCritical:safety.unmatchedCritical===true,signals,source:'P11-scoped-fabric',scientificGroundTruth:false};
}
