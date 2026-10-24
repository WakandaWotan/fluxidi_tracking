import {importReliableOsmCorridorV1} from './reliable_osm_corridor_v1.mjs';
import {createReliableOsmPointRoutesV1} from './reliable_osm_point_routes_v1.mjs';
import {createProductGradeRegionalRoutesV1,resolveProductTrafficV1} from './product_estimated_eta_v1.mjs';
import {createReliableNationalPointsV1} from './reliable_national_points_v1.mjs';
import {readNationalPublicationV1} from './reliable_national_publication_v1.mjs';
import {validateNationalPublicationPolicyV1,nationalPublicationPolicyCurrentV1} from './reliable_national_publication_policy_v1.mjs';
import {createOfficialAddressOperationalAdapterV1} from './official_address_operational_adapter_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';

// Server-owned storage adapter for the existing core, not a new router.
// All companies use the same published region catalog. Only immutable road
// graphs are shared: traffic leases, route caches and policies remain scoped.
// This installs no data and enables no Cloudflare setting. Off-road access
// remains unproven by the current core and must continue to fail closed.
export const OPERATIONAL_ROUTING_SCHEMA='fluxidi-operational-routing-v1';
export const OPERATIONAL_REGION_CATALOG='routing:reliable:v1:regions';
const installed=Symbol('fluxidiOperationalRouting');
const graphs=new Map(),MAX_GRAPH_BYTES=8*1024*1024;
const token=s=>typeof s==='string'&&/^[a-zA-Z0-9_.-]{1,96}$/.test(s);
const digest=s=>typeof s==='string'&&/^[a-f0-9]{64}$/.test(s);
const fail=reason=>{throw Error(reason);};
const live=(r,now)=>Number.isFinite(r?.publishedAt)&&r.publishedAt<=now&&Number.isFinite(r.validUntil)&&r.validUntil>now;
const coordinate=p=>{
 const latitude=p?.latitude??p?.lat,longitude=p?.longitude??p?.lng??p?.lon;
 if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||Math.abs(latitude)>90||Math.abs(longitude)>180||(latitude===0&&longitude===0))fail('operational_journey_point_unknown');
 return {latitude,longitude,...(p?.access?{access:structuredClone(p.access)}:{}),...(p?.address&&typeof p.address==='object'?{address:structuredClone(p.address)}:{}),...(p?.official_address?{official_address:structuredClone(p.official_address)}:{})};
};
const contains=(b,p)=>p.longitude>=b[0]&&p.latitude>=b[1]&&p.longitude<=b[2]&&p.latitude<=b[3];
function journeyPoints(record){
 const leg=(record.operational_legs??record.booking?.operational_legs??[]).find(l=>l.leg_type==='outbound')??{};
 const s={...record.p12_reliable_choice?.request_context,...leg,...record.booking,...record.payload,...record};
 const points=[coordinate({lat:s.pickup_lat??s.from_lat,lng:s.pickup_lng??s.from_lng}),coordinate({lat:s.dropoff_lat??s.to_lat,lng:s.dropoff_lng??s.to_lng})];
 for(const p of [...(s.stop_coordinates??[]),...(s.return_stop_coordinates??[])])points.push(coordinate(p));
 if(s.return_enabled===true||s.return===true){
  for(const [lat,lng]of [[s.return_from_lat??s.return_pickup_lat,s.return_from_lng??s.return_pickup_lng],[s.return_to_lat??s.return_dropoff_lat,s.return_to_lng??s.return_dropoff_lng]])if(lat!=null||lng!=null)points.push(coordinate({lat,lng}));
 }
 if(points.length>21)fail('operational_journey_points_limit');
 return points;
}
async function readJson(store,key,maxBytes,missingReason=null){
 const text=await store.get(key);
 if(text==null&&missingReason)throw Object.assign(Error('operational_record_missing_or_oversized'),{dispatcherOnlyReason:missingReason});
 if(typeof text!=='string'||new TextEncoder().encode(text).byteLength>maxBytes)fail('operational_record_missing_or_oversized');
 try{return {text,value:JSON.parse(text)};}catch{fail('operational_record_invalid_json');}
}
async function sha256(text){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),b=>b.toString(16).padStart(2,'0')).join('');}
function validateRegion(r,now){
 if(!token(r?.id)||!digest(r.graphSha256)||r.graphKey!==`routing:reliable:v1:graph:${r.graphSha256}`||!token(r.evidenceRevision)||typeof r.graphVersion!=='string'||r.graphVersion.length>160||!live(r,now))fail('operational_region_invalid');
 if(!Array.isArray(r.bbox)||r.bbox.length!==4||!r.bbox.every(Number.isFinite)||r.bbox[0]>=r.bbox[2]||r.bbox[1]>=r.bbox[3]||r.bbox[0]<-180||r.bbox[2]>180||r.bbox[1]<-90||r.bbox[3]>90)fail('operational_region_bounds');
 // Rights are an explicit reviewed publication prerequisite. A download or
 // the presence of an ODbL string alone never supplies this attestation.
 if(r.reuse?.status!=='approved'||r.reuse.license!=='ODbL-1.0'||typeof r.reuse.evidenceRef!=='string'||!r.reuse.evidenceRef.trim()||typeof r.reuse.attribution!=='string'||!r.reuse.attribution.trim()||r.reuse.databaseObligationsSatisfied!==true)fail('operational_region_rights_unproven');
}
async function loadGraph(store,r,metrics){
 if(graphs.has(r.graphSha256)){
  const value=graphs.get(r.graphSha256);if(value.corridor.attribution!==r.reuse.attribution)fail('operational_graph_attribution');graphs.delete(r.graphSha256);graphs.set(r.graphSha256,value);metrics.graphReuseHits++;return value;
 }
 const {text,value}=await readJson(store,r.graphKey,MAX_GRAPH_BYTES);metrics.storageReads++;
 if(await sha256(text)!==r.graphSha256)fail('operational_graph_hash');
 if(value.attribution!==r.reuse.attribution)fail('operational_graph_attribution');
 const corridor=importReliableOsmCorridorV1(value);
 const result={corridor,regional:createReliableOsmPointRoutesV1(corridor),coverage:structuredClone(value.bbox),bytes:new TextEncoder().encode(text).byteLength};
 if(graphs.size>=2)graphs.delete(graphs.keys().next().value);
 graphs.set(r.graphSha256,result);metrics.graphLoads++;metrics.graphBytes+=result.bytes;return result;
}

export function operationalRoutingInstalledV1(env){return env?.[installed]===true&&env.RELIABLE_CHOICE_ENABLED==='1';}
// Compatibility boundary for existing hard reservation/transfer checks. It
// carries a conservative occupancy bound, never a customer ETA certificate.
// No textual geocoding or commercial fallback is available in this path.
export async function operationalRoadTravelV1({env,scope,from,to,departureAt,gpsRoadContext=false,configuredOriginSiteBinding=null}){
 const unavailable=reason=>({ok:false,travel_seconds:null,reason_code:reason,route_failure_reason:reason,route_validation_unavailable:true,route_used_coordinate_direct:false,route_used_geocode_fallback:false,route_profile:'fluxidi/local-planning-v1'});
 if(!operationalRoutingInstalledV1(env))return unavailable('local_dispatch_route_required');
 const point=p=>{
  const latitude=p?.latitude??p?.lat,longitude=p?.longitude??p?.lng??p?.lon;
  return typeof latitude==='number'&&typeof longitude==='number'&&Number.isFinite(latitude)&&Number.isFinite(longitude)&&Math.abs(latitude)<=90&&Math.abs(longitude)<=180?coordinate(p):null;
 };
 const a=point(from),b=point(to);
 if(!a||!b)return unavailable('local_dispatch_location_required');
 try{
  const router=await env.__reliableRegionalRoutes(scope);
  await router.resolveForJourney({pickup_lat:a.latitude,pickup_lng:a.longitude,dropoff_lat:b.latitude,dropoff_lng:b.longitude,...(a.official_address?{pickup_input:{kind:'address',official_address:a.official_address}}:{}),...(b.official_address?{destination_input:{kind:'address',official_address:b.official_address}}:{})});
  let origin=a;
  if(configuredOriginSiteBinding){
   if(a.access?.kind==='gps'||typeof router.resolveConfiguredSitePoint!=='function')fail('configured_site_runtime_unavailable');
   origin=await router.resolveConfiguredSitePoint({point:{latitude:a.latitude,longitude:a.longitude},binding:configuredOriginSiteBinding,role:'origin'});
  }
  // Only the scoped server-selected, temporally appropriate Later origin
  // can request GPS road context. Raw coordinates and every other caller
  // retain ordinary planning access; the original sample is never altered.
  const access=a.access,now=Date.now();
  const useGpsRoadContext=gpsRoadContext===true&&access?.kind==='gps'
   &&typeof access.capturedAt==='number'&&Number.isFinite(access.capturedAt)
   &&access.capturedAt<=now&&now-access.capturedAt<=30000
   &&typeof access.accuracyMeters==='number'&&Number.isFinite(access.accuracyMeters)
   &&access.accuracyMeters>0&&access.accuracyMeters<=100;
  const route=await router.planRoute({scope:router.scope,origin,destination:b,...(Number.isSafeInteger(departureAt)?{departureAt}:{}),gpsRoadContext:useGpsRoadContext});
  if(useGpsRoadContext){const finished=Date.now();if(access.capturedAt>finished||finished-access.capturedAt>30000||!Number.isFinite(route.validUntil)||route.validUntil<=finished)throw Error('operational_route_gps_lease_expired');}
  if(!Number.isFinite(route.operationalDurationBoundSeconds)||route.operationalDurationBoundSeconds<0||!Number.isFinite(route.distanceMeters)||route.distanceMeters<0)throw Error('operational_route_bound_invalid');
  return {ok:true,travel_seconds:route.operationalDurationBoundSeconds,distance_meters:route.distanceMeters,route_profile:'fluxidi/local-planning-v1',route_used_coordinate_direct:true,route_used_geocode_fallback:false,route_validation_unavailable:false,graph_version:route.graphVersion,route_evidence_id:route.evidenceId,route_valid_until_ms:route.validUntil,planning_only:true,certified_eta:false};
 }catch(error){if(typeof error?.message==='string'&&/^[a-z][a-z0-9_]{0,99}$/.test(error.message))console.warn('[LOCAL_DISPATCH_ROUTE] reason='+error.message);return unavailable('local_dispatch_route_unavailable');}
}
export function withOperationalRoutingV1(env){
 if(env?.RELIABLE_CHOICE_ENABLED!=='1'||operationalRoutingInstalledV1(env))return env;
 if(typeof env.BOOKING_KV?.get!=='function')return env;
 // Never accept a router supplied by a request or a production fixture.
 // A configured national publication never falls back to the corridor or KV
 // graph catalog, even when its object binding/publication is invalid.
 const nationalRequired=env.RELIABLE_NATIONAL_REQUIRED==='1';
 const national=env.RELIABLE_NATIONAL_PUBLICATION_REF!=null||env.RELIABLE_NATIONAL_PUBLICATION!=null||env.RELIABLE_NATIONAL_ACTIVATION!=null||nationalRequired?{publication:env.RELIABLE_NATIONAL_PUBLICATION,reference:env.RELIABLE_NATIONAL_PUBLICATION_REF,activation:env.RELIABLE_NATIONAL_ACTIVATION,bucket:env.RELIABLE_GRAPH_OBJECTS,required:nationalRequired}:null;
 if(national&&env.STAGING_TRIAL_MODE==='1'&&env.STAGING_TRIAL_ENVIRONMENT==='staging')
   national.metadataBucket=env.STAGING_TRIAL_PUBLICATION_OBJECTS;
 return {...env,[installed]:true,__reliableRegionalRoutes:async scope=>createOperationalRegionalResolverV1({store:env.BOOKING_KV,scope,national,officialAddressIndex:await operationalOfficialAddressIndexV1(env)})};
}

// Existing advice/live-route response shape, supplied by the same local core.
// The caller still owns authentication, NAV, grant and assignment validation.
export async function operationalCustomerRouteEtaV1(env,args={}){
 const installedEnv=withOperationalRoutingV1(env);
 if(!operationalRoutingInstalledV1(installedEnv))throw Error('local_route_runtime_required');
 const scope=args.observability?.scope??args.context;
 const origin=coordinate(args.origin),destination=coordinate(args.destination);
 const router=await installedEnv.__reliableRegionalRoutes(scope);
 await router.resolveForJourney({pickup_lat:origin.latitude,pickup_lng:origin.longitude,dropoff_lat:destination.latitude,dropoff_lng:destination.longitude});
 const evidence=await router.route({scope:router.scope,origin,destination,departureAt:Date.now()});
 if(!Number.isFinite(evidence.seconds)||evidence.seconds<0||!Number.isFinite(evidence.distanceMeters)||evidence.distanceMeters<0||evidence.validUntil<=Date.now())throw Error('local_route_evidence_invalid');
 const coordinates=Array.isArray(evidence.geometry)?evidence.geometry:null;
 const route=coordinates&&coordinates.length>=2&&coordinates.length<=5000?{coordinates:structuredClone(coordinates)}:null;
 return {target:args.target,duration_seconds:evidence.seconds,duration_typical_seconds:null,distance_meters:evidence.distanceMeters,route,source:'fluxidi/local-product-estimate',provider_source:null,estimated:true,estimate_source:'local_route',graph_version:evidence.graphVersion,evidence_revision:evidence.evidenceRevision,route_evidence_id:evidence.evidenceId,traffic_revision:evidence.productEvidence?.trafficRevision,valid_until:new Date(evidence.validUntil).toISOString(),calibrated:false,certified_eta:false};
}

export function createOperationalRegionalResolverV1({store,scope,clock=Date.now,national=null,officialAddressIndex=null}){
 if(!token(scope?.tenant_id)||!token(scope?.company_id)||typeof store?.get!=='function')fail('operational_route_scope');
 const fixed={tenant_id:scope.tenant_id,company_id:scope.company_id};
 let engine=null,selected=null,nationalPolicy=null,currentScope={...fixed},revision=null,lastPublication=null,addressGraph=null,configuredSiteResolver=null;
 const metrics={catalogReads:0,storageReads:0,graphLoads:0,graphReuseHits:0,graphBytes:0,trafficReads:0,publicationObjectReads:0,publicationObjectBytes:0,publicationCacheHits:0,commercialDispatchCalls:0,trafficState:'UNAVAILABLE'};
 async function traffic(){
  if(!selected)fail('operational_region_unresolved');
  metrics.storageReads++;metrics.trafficReads++;
  let text,t,reason=null;
  try{const read=await readJson(store,`routing:reliable:v1:traffic:${selected.id}`,512*1024);text=read.text;t=read.value;}catch{reason='traffic_read_unavailable';}
  const now=clock();
  if(t&&(t.schema!==OPERATIONAL_ROUTING_SCHEMA||t.region_id!==selected.id||t.graphVersion!==selected.graphVersion||t.evidenceRevision!==selected.evidenceRevision||!token(t.revision)||t.tenant_id!=null||t.company_id!=null)){t=null;reason='traffic_publication_rejected';}
  // The shared publication is official road evidence, never another tenant's
  // fleet history, GPS or learned profiles. Such evidence needs scoped ingest.
  if(t&&Array.isArray(t.signals)){
   const shared=t.signals.filter(s=>s&&s.tenant_id==null&&s.company_id==null&&['closure','restriction','congestion','roadworks','measured-segment','observed-aggregate'].includes(s.kind));
   if(shared.length!==t.signals.length)t={...t,signals:shared,unmatchedCritical:true};
  }
  if(t&&lastPublication?.revision===t.revision&&lastPublication.text!==text){t=null;reason='traffic_revision_reused';}
  const policy=resolveProductTrafficV1({traffic:t?{...structuredClone(t),...currentScope}:null,scope:currentScope,now,reason,retainedSignals:lastPublication?.policy.signals??[],retainedRevision:lastPublication?.revision??''});
  if(policy.trafficState==='AVAILABLE')lastPublication={revision:t.revision,text,policy};
  revision=policy.revision;metrics.trafficState=policy.trafficState;return policy;
 }
 async function resolveForJourney(record){
  const officialSource={...record.booking,...record.payload,...record};if(!officialAddressIndex&&['pickup_input','destination_input','return_pickup_input','return_destination_input'].some(k=>officialSource[k]?.official_address!==undefined))fail('address_index_unavailable');
  if(national){
   engine=null;selected=null;nationalPolicy=null;addressGraph=null;configuredSiteResolver=null;
   const now=clock(),points=journeyPoints(record);
   if(national.required&&national.reference==null&&national.publication==null)fail('national_configuration_required');
   const loaded=await readNationalPublicationV1(national);
   metrics.publicationObjectReads+=loaded.reads;metrics.publicationObjectBytes+=loaded.bytes;metrics.publicationCacheHits+=loaded.cacheHits;
   let p=loaded.publication;
   if(typeof p==='string'){if(new TextEncoder().encode(p).byteLength>4*1024*1024)fail('national_publication_size');try{p=JSON.parse(p);}catch{fail('national_publication_invalid');}}
   const policy=await validateNationalPublicationPolicyV1({...national,publication:p,now});
   if(!token(p.region?.id)||!token(p.region?.evidenceRevision)||p.region?.graphVersion!==p.manifest?.graphVersion||typeof national.bucket?.get!=='function')fail('national_publication_invalid');
   const r={...p.region,publishedAt:p.publishedAt,validUntil:p.validUntil};
   // Same reviewed rights prerequisite as the corridor, without KV keys.
   if(r.reuse?.status!=='approved'||r.reuse.license!=='ODbL-1.0'||!r.reuse.evidenceRef?.trim()||!r.reuse.attribution?.trim()||r.reuse.databaseObligationsSatisfied!==true)fail('operational_region_rights_unproven');
   const bbox=p.manifest?.tree?.[p.manifest.root]?.bbox;
   if(!Array.isArray(bbox)||bbox.length!==4||!points.every(point=>contains(bbox,point)))fail('operational_region_uncovered');
   selected=structuredClone(r);nationalPolicy=policy;currentScope={...fixed,region_id:r.id,graphVersion:r.graphVersion,evidenceRevision:r.evidenceRevision,...(p.manifest.accessContext?.schema==='fluxidi-national-road-access-v1'?{accessContextRevision:p.manifest.accessContext.revision}:{})};revision=null;lastPublication=null;
   const regional=createReliableNationalPointsV1({manifest:p.manifest,bucket:national.bucket,scope:currentScope});
   configuredSiteResolver=args=>regional.configuredSiteRoutePoint(args);
   const addressContexts=new Map();
   addressGraph=Object.freeze({graphVersion:currentScope.graphVersion,revision:currentScope.accessContextRevision,async readContext(args){const c=await regional.addressAccessContext(args.point,{radiusMeters:args.radiusMeters,address:args.address.address,role:args.role});if(addressContexts.size>=4)addressContexts.delete(addressContexts.keys().next().value);addressContexts.set(JSON.stringify([args.address.id,args.role]),c);return c;},releaseContext:args=>addressContexts.delete(JSON.stringify([args.address.id,args.role])),materialize:args=>{const context=addressContexts.get(JSON.stringify([args.address.id,args.role]));if(!context)fail('address_context_changed');return regional.addressRoutePoint({...args,context});}});
   engine=createProductGradeRegionalRoutesV1({regional,scope:currentScope,readTraffic:traffic,readRevision:()=>revision,clock});return {...currentScope};
  }
  const now=clock(),points=journeyPoints(record),{value:c}=await readJson(store,OPERATIONAL_REGION_CATALOG,64*1024,'operational_region_uncovered');metrics.storageReads++;metrics.catalogReads++;
  if(c.schema!==OPERATIONAL_ROUTING_SCHEMA||!live(c,now)||!Array.isArray(c.regions)||c.regions.length>64)fail('operational_catalog_invalid_or_stale');
  for(const r of c.regions)validateRegion(r,now);
  const matches=c.regions.filter(r=>points.every(p=>contains(r.bbox,p)));
  if(matches.length!==1)fail(matches.length?'operational_region_ambiguous':'operational_region_uncovered');
  const r=matches[0],g=await loadGraph(store,r,metrics);
  if(g.corridor.graph.version!==r.graphVersion)fail('operational_graph_version');
  // Complete OSM ways legitimately include nodes outside the requested
  // extract box. The publication must bind the extract's declared coverage,
  // while actual reachability/access is still proved by the routing core.
  if(!Array.isArray(g.coverage)||r.bbox.some((v,i)=>v!==g.coverage[i]))fail('operational_graph_bounds');
  selected=structuredClone(r);currentScope={...fixed,region_id:r.id,graphVersion:r.graphVersion,evidenceRevision:r.evidenceRevision};
  revision=null;lastPublication=null;engine=createProductGradeRegionalRoutesV1({regional:g.regional,scope:currentScope,readTraffic:traffic,readRevision:()=>revision,clock});
  return {...currentScope};
 }
 const ready=()=>{if(!engine||!selected||!(national?nationalPublicationPolicyCurrentV1(nationalPolicy,clock()):live(selected,clock())))fail('operational_region_unresolved_or_expired');};
 const checked=async(method,input)=>{
  ready();const readsBefore=metrics.trafficReads,result=await engine[method](input);
  // Re-read the publication after async routing. A changed revision cannot
  // validate a candidate or a lease built against the old snapshot.
  // Cached route results already carry the core's <=15s immutable lease.
  // Do not add one storage read per driver in a 500-origin batch.
  if(metrics.trafficReads!==readsBefore){const before=revision,stateBefore=metrics.trafficState;await traffic();if(revision!==before||metrics.trafficState!==stateBefore)fail('operational_traffic_revision_changed');}
  ready();return result;
 };
 const officialChecked=(method,input)=>{if(input?.origin?.official_address||input?.destination?.official_address||input?.origins?.some(p=>p?.official_address))fail('address_index_unavailable');return checked(method,input);};
 const base=Object.freeze({kind:'LOCAL_ROUTING_ONLY_V1',get scope(){return {...currentScope};},resolveForJourney,addressGraph:()=>addressGraph,
  async resolveConfiguredSitePoint(args){ready();if(!configuredSiteResolver)fail('configured_site_runtime_unavailable');const result=await configuredSiteResolver(args);ready();return result;},
  prepareCandidates:input=>officialChecked('prepareCandidates',input),route:input=>officialChecked('route',input),planRoute:input=>officialChecked('planRoute',input),financialRoute:input=>officialChecked('financialRoute',input),navigationRoute:input=>officialChecked('navigationRoute',input),
  diagnostics(){return {...metrics,publicationPolicy:nationalPolicy?{...nationalPolicy}:null,graphCacheEntries:graphs.size,maximumGraphCacheEntries:2,maximumGraphBytes:MAX_GRAPH_BYTES,engine:engine?.diagnostics()??null};}});
 return officialAddressIndex?createOfficialAddressOperationalAdapterV1({router:base,index:officialAddressIndex,clock}):base;
}
