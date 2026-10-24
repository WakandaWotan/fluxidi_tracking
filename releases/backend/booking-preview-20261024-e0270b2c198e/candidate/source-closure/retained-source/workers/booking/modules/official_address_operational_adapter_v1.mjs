import {createOfficialAddressAccessResolverV1,ADDRESS_ROUTE_CONTEXT_V1} from './official_address_access_resolver_v1.mjs';
import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {officialAddressReferenceV1,officialAddressPositionUsableV1} from './official_address_reference_v1.mjs';
import {projectAccessV1} from './national_road_access_v1.mjs';
const fail=s=>{throw Error(s);},same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const key=p=>JSON.stringify(p?.official_address??null),hash=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))),x=>x.toString(16).padStart(2,'0')).join('');
// A GPS route is proved to the resolved road pickup, not the building/source
// position. Bind that distinction privately to this exact server-produced
// route. JSON fields, copied routes and changed proofs are never authority.
const pickupEvidenceBindings=new WeakMap();
const evidenceBinding=r=>JSON.stringify([r.gpsRoadEvidence??null,r.nearPickupEvidence??null,r.addressContext,r.resolvedDestination]);
export function officialAddressEvidencePickupV1(route,origin,pickup,scope){
 const b=pickupEvidenceBindings.get(route);
 if(!b||b.origin!==JSON.stringify(origin)||b.pickup!==JSON.stringify(pickup)||b.scope!==JSON.stringify([scope?.tenant_id,scope?.company_id,scope?.graphVersion,scope?.accessContextRevision])||b.evidence!==evidenceBinding(route))return pickup;
 return b.resolved;
}
export function copyOfficialAddressRouteEvidenceV1(route){
 const next=structuredClone(route),b=pickupEvidenceBindings.get(route);
 if(b&&b.evidence===evidenceBinding(route))pickupEvidenceBindings.set(next,b);
 return next;
}
function requireAccess(result){
 if(result.status==='access_proven')return;
 fail(({access_uncertain:'access_address_parallel_ambiguity',access_forbidden:'address_access_forbidden',budget_exceeded:'address_candidate_limit',data_insufficient:'address_data_insufficient'})[result.status]??'address_context_incomplete');
}
// One instance per authenticated operational request; no process-wide mutable
// company/driver state. The base router remains the sole route/traffic engine.
export function createOfficialAddressOperationalAdapterV1({router,index,clock=Date.now}){
 if(router?.kind!=='LOCAL_ROUTING_ONLY_V1'||typeof router.resolveForJourney!=='function'||typeof router.addressGraph!=='function')fail('official_address_owned_router_required');
 let resolver=null,graph=null;const bindings=new Map(),prepared=new Map(),records=new Map();
 const readIndex={kind:index.kind,get revision(){return index.revision;},get(id){if(!records.has(id)){if(records.size>=128)fail('address_candidate_limit');records.set(id,index.get(id));}return records.get(id);}},authority=createOfficialAddressAuthorityV1({index:readIndex,allowUnknownOfficialAssignment:true,allowMissingPosition:true});
 const check=scope=>{if(!same(scope,router.scope)||scope.graphVersion!==router.scope.graphVersion)fail('address_route_scope');};
 const ensure=()=>{graph=router.addressGraph();if(!graph)fail('address_index_unavailable');resolver??=createOfficialAddressAccessResolverV1({index:readIndex,graph,scope:router.scope,clock});};
 async function officialPosition(input){const ref=officialAddressReferenceV1(input);if(!ref)return null;if(ref.index_revision!==index.revision)fail('address_index_changed');const a=await authority.resolve(ref.id);if(a.source!==ref.source||a.sourceVersion!==ref.source_version)fail('address_source_changed');if(!officialAddressPositionUsableV1(a))fail('address_data_insufficient');return a.point;}
 async function canonicalRecord(record){
  const merged={...record.p12_reliable_choice?.request_context,...record.booking,...record.payload,...record},next={...record};
  const consistent=(p,lat,lng)=>{if(lat==null&&lng==null)return;if(lat==null||lng==null||!Number.isFinite(Number(lat))||!Number.isFinite(Number(lng))||projectAccessV1(p,{latitude:Number(lat),longitude:Number(lng)},{latitude:Number(lat),longitude:Number(lng)}).meters>1)fail('address_source_position_changed');};
  for(const [field,lat,lng,aliasLat,aliasLng]of [['pickup_input','pickup_lat','pickup_lng','from_lat','from_lng'],['destination_input','dropoff_lat','dropoff_lng','to_lat','to_lng'],['return_pickup_input','return_pickup_lat','return_pickup_lng','return_from_lat','return_from_lng'],['return_destination_input','return_dropoff_lat','return_dropoff_lng','return_to_lat','return_to_lng']]){const p=await officialPosition(merged[field]);if(p){consistent(p,merged[lat],merged[lng]);consistent(p,merged[aliasLat],merged[aliasLng]);Object.assign(next,{[lat]:p.latitude,[lng]:p.longitude,[aliasLat]:p.latitude,[aliasLng]:p.longitude});}}
  for(const field of ['stop_coordinates','return_stop_coordinates'])if(Array.isArray(merged[field])){next[field]=[];for(const s of merged[field]){const p=await officialPosition(s.input);if(p){consistent(p,s.lat,s.lng);consistent(p,s.latitude,s.longitude);}next[field].push(p?{...s,lat:p.latitude,lng:p.longitude}:s);}}
  return next;
 }
 async function candidates(point,role){
  if(!point?.official_address)return [{id:null,point}];
  ensure();const result=await resolver.resolve({kind:'address',official_address:point.official_address},{role});requireAccess(result);
  let rows=result.candidates.filter(c=>c.status==='proven');const bound=bindings.get(key(point));
  if(bound){rows=rows.filter(c=>c.point.latitude===bound.point.latitude&&c.point.longitude===bound.point.longitude);if(!rows.length)fail('address_context_changed');}
  return rows.map(c=>({...c,point:resolver.routePoint(result,c.id),official:result}));
 }
 async function contextFor(origin,destination,o,d,evidence){
  const refs=[origin,destination].filter(p=>p?.official_address).map(p=>p.official_address),parts=[o,d].map(c=>c.official?{identity:c.official.addressSignature,candidate:c.id,point:c.point}:null),binding={schema:ADDRESS_ROUTE_CONTEXT_V1,tenant_id:router.scope.tenant_id,company_id:router.scope.company_id,index_revision:index.revision,graph_version:router.scope.graphVersion,access_revision:graph.revision,parts,route_evidence_id:evidence.evidenceId,traffic_revision:evidence.productEvidence?.trafficRevision??null};
  return Object.freeze({...binding,id:await hash(JSON.stringify(binding)),valid_until_ms:Math.min(evidence.validUntil,clock()+15000),status:'routeable',source_versions:refs.map(r=>({id:r.id,source:r.source,source_version:r.source_version}))});
 }
 async function route(method,args){
  check(args.scope);if(!args.origin?.official_address&&!args.destination?.official_address)return router[method](args);
  const os=await candidates(args.origin,'origin'),ds=await candidates(args.destination,'destination'),results=[],failures=[];
  for(const d of ds){
   const cacheKey=JSON.stringify([key(args.destination),d.id,args.gpsRoadContext===true]),warm=prepared.get(cacheKey);
   if(!warm||warm.until<=clock()||!os.every(o=>warm.origins.includes(JSON.stringify(o.point)))){await router.prepareCandidates({scope:router.scope,origins:os.map(o=>o.point),destination:d.point,gpsRoadContext:args.gpsRoadContext===true});prepared.set(cacheKey,{until:clock()+15000,origins:os.map(o=>JSON.stringify(o.point))});}
   for(const o of os)try{const e=await router[method]({...args,scope:router.scope,origin:o.point,destination:d.point});check(args.scope);if(e.graphVersion!==router.scope.graphVersion||e.evidenceRevision!==router.scope.evidenceRevision||!Number.isFinite(e.validUntil)||e.validUntil<=clock()||!Number.isFinite(e.distanceMeters)||e.distanceMeters<0)fail('address_route_evidence_invalid');results.push({o,d,e});}catch(error){failures.push(error.routeFailureReason??error.message);}
  }
  check(args.scope);resolver.assertCurrent();
  if(!results.length)fail(failures.length&&failures.every(r=>['graph_disconnected','graph_weak_component_disconnected','graph_local_no_legal_exit'].includes(r))?'address_route_unreachable':'address_route_evidence_unavailable');
  const seconds=r=>method==='planRoute'?r.e.operationalDurationBoundSeconds:r.e.seconds;
  if(results.some(r=>!Number.isFinite(seconds(r))||seconds(r)<0))fail('address_route_evidence_invalid');
  results.sort((a,b)=>seconds(a)-seconds(b)||a.e.distanceMeters-b.e.distanceMeters||String(a.o.id).localeCompare(String(b.o.id))||String(a.d.id).localeCompare(String(b.d.id)));
  const {o,d,e}=results[0];for(const [p,c]of [[args.origin,o],[args.destination,d]])if(p?.official_address)bindings.set(key(p),c);
  const addressContext=await contextFor(args.origin,args.destination,o,d,e);
  const result={...e,addressContext,addressRouteDiagnostics:{candidatePairs:os.length*ds.length,provenRoutes:results.length,failedRoutes:failures.length},resolvedOrigin:o.point,resolvedDestination:d.point};
  if(args.destination?.official_address&&(e.gpsRoadEvidence||e.nearPickupEvidence)){
   // The lower router must have checked this actual destination. Do not repair
   // a malformed lower proof or replace its GPS sample/session/freshness.
   for(const proof of [e.gpsRoadEvidence,e.nearPickupEvidence].filter(Boolean))if(JSON.stringify(proof.origin)!==JSON.stringify(args.origin)||JSON.stringify(proof.pickup)!==JSON.stringify(d.point))fail('address_route_evidence_invalid');
   pickupEvidenceBindings.set(result,{origin:JSON.stringify(args.origin),pickup:JSON.stringify(args.destination),scope:JSON.stringify([args.scope.tenant_id,args.scope.company_id,args.scope.graphVersion,args.scope.accessContextRevision]),evidence:evidenceBinding(result),resolved:Object.freeze(structuredClone(d.point))});
  }
  return result;
 }
 return Object.freeze({kind:'LOCAL_ROUTING_ONLY_V1',get scope(){return router.scope;},async resolveForJourney(record){bindings.clear();prepared.clear();records.clear();resolver=null;await router.resolveForJourney(await canonicalRecord(record));return router.scope;},async resolveAddressPoint(point){if(!point?.official_address)return point;const position=await officialPosition({kind:'address',official_address:point.official_address});return {...position,official_address:point.official_address,access:{kind:'address'}};},route:args=>route('route',args),planRoute:args=>route('planRoute',args),financialRoute:args=>route('financialRoute',args),navigationRoute:args=>route('navigationRoute',args),async prepareCandidates(args){check(args.scope);if(!args.destination?.official_address&&!args.origins.some(p=>p?.official_address))return router.prepareCandidates(args);const ds=await candidates(args.destination,'destination'),origins=[];for(const o of args.origins)for(const c of await candidates(o,'origin'))origins.push(c.point);if(origins.length>500)fail('address_origin_batch_limit');for(const d of ds){await router.prepareCandidates({...args,scope:router.scope,origins,destination:d.point});prepared.set(JSON.stringify([key(args.destination),d.id,args.gpsRoadContext===true]),{until:clock()+15000,origins:origins.map(o=>JSON.stringify(o))});}},addressGraph:()=>router.addressGraph(),resolveConfiguredSitePoint:args=>{if(typeof router.resolveConfiguredSitePoint!=='function')fail('configured_site_runtime_unavailable');return router.resolveConfiguredSitePoint(args);},diagnostics:()=>({...router.diagnostics(),officialAddress:resolver?.diagnostics()??null})});
}
