// Compatibility adapter for the existing quote/mission functions. It uses the
// existing official index and bounded local access resolver, never the national
// route search. No network default, persistent store or financial evidence type.
import {createCustomerMapboxQuoteApiV1} from './customer_mapbox_quote_request_v1.mjs';
import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {officialAddressReferenceV1,officialAddressPositionUsableV1} from './official_address_reference_v1.mjs';
import {createOfficialAddressAccessResolverV1} from './official_address_access_resolver_v1.mjs';
import {readConfiguredSiteRoutePointV1} from './configured_site_access_v1.mjs';
import {publicAddressPointV1,resolvePracticalFrontageV1} from './practical_frontage_v1.mjs';
import {projectAccessV1,resolveRoadAccessV1,resolveDriverGpsRoadAccessV1} from './national_road_access_v1.mjs';
import {boundedMapboxQuoteDirectionsV1} from './mapbox_quote_transport_v1.mjs';
import {financialQuoteInputs} from './financial_quote_lifecycle.mjs';
import {withOperationalRoutingV1,operationalRoutingInstalledV1} from './reliable_operational_routes_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
import {createMapboxQuoteTransportV1,mapboxQuoteTransportMetricsV1} from './mapbox_quote_transport_v1.mjs';
import {financialRouteBatchContextV1,financialDirectionsInBatchV1,financialMunicipalityInBatchV1,financialRouteBatchR2BudgetV1,transferFinancialRouteBatchContextV1} from './financial_route_batch_v1.mjs';
import {createQuoteR2BudgetV1} from '../../../../workers/booking/cache-correction/quote_r2_budget_v1.mjs';
import {reserveStagingTrialForEnvV1} from './staging_trial_budget_v1.mjs';
import {parseCompanyMissionTariff} from './company_mission_tariff_config.mjs';

const environments=new WeakMap(),requests=new WeakMap(),missionProofs=new WeakMap();
const requestSlot=Symbol('mapbox-quote-request-v1');
const roadSlot=Symbol('mapbox-operational-road-v1'),roadContexts=new WeakMap();
const diagnosticTimeSlot=Symbol('mapbox-dispatch-time-diagnostic-v1'),missingCaptureInputs=new WeakSet();
const fail=reason=>{throw Error(reason);};
const sameScope=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const text=v=>String(v??'').normalize('NFC').trim().replace(/\s+/g,' ');
const wire=p=>({lat:p.latitude,lng:p.longitude});
const same=(a,b)=>a?.lat===b?.lat&&a?.lng===b?.lng;
const canonical=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])):x);
const operationalInputs=body=>canonical(Object.fromEntries(['customer_route_provider','pickup_input','destination_input','return_pickup_input','return_destination_input','stop_coordinates','return_stop_coordinates'].map(k=>[k,body[k]??null])));
export function mapboxProviderScopeEnabledV1(env,scope){return env?.MAPBOX_QUOTE_ROUTING_ENABLED==='1'&&!!scope?.tenant_id&&!!scope?.company_id
  &&String(env.MAPBOX_QUOTE_ALLOWED_SCOPES??'').split(',').map(s=>s.trim()).includes(scope.tenant_id+'/'+scope.company_id);}
export function mapboxAutomaticDispatchEnabledV1(env,scope){return mapboxProviderScopeEnabledV1(env,scope)
  &&env.DISPATCH_DEVICE_ACK_ENABLED==='1'&&env.BOOKING_RECORD_AUTHORITY_ENABLED==='1';}

export function bindMapboxOperationalContextV1(env,scope){
  if(!mapboxProviderScopeEnabledV1(env,scope))return env;
  const current=roadContexts.get(env?.[roadSlot]);if(current&&sameScope(current.scope,scope))return env;
  const capability=Object.freeze({}),budget=createQuoteR2BudgetV1(env.RELIABLE_GRAPH_OBJECTS,{readLimit:64,byteLimit:32*1024*1024});
  const bounded={...env,RELIABLE_GRAPH_OBJECTS:budget.bucket,RELIABLE_CHOICE_ENABLED:'1',RELIABLE_NATIONAL_REQUIRED:'1',
    RELIABLE_NATIONAL_PUBLICATION_REF:env.OWNED_QUOTE_PUBLICATION_REF??env.RELIABLE_NATIONAL_PUBLICATION_REF,
    RELIABLE_NATIONAL_ACTIVATION:env.OWNED_QUOTE_ACTIVATION??env.RELIABLE_NATIONAL_ACTIVATION};
  for(const symbol of Object.getOwnPropertySymbols(bounded))if(operationalRoutingInstalledV1({RELIABLE_CHOICE_ENABLED:'1',[symbol]:bounded[symbol]}))delete bounded[symbol];
  const expiresAt=Date.now()+15000,operational=withOperationalRoutingV1(bounded);
  const transport=createMapboxQuoteTransportV1({scope,expiresAt,maxRequests:8,
    reserve:async()=>typeof env.BOOKING_SEARCH_LIMITER?.limit==='function'&&(await env.BOOKING_SEARCH_LIMITER.limit({key:'mapbox-directions-actual-request'}))?.success===true
      &&await reserveStagingTrialForEnvV1(env,'mapbox_directions'),
    send:(url,init)=>globalThis.fetch(url,init)});
  roadContexts.set(capability,{scope:{tenant_id:scope.tenant_id,company_id:scope.company_id},operational,bounded,transport,budget,expiresAt,routes:new Map(),timePhases:env[diagnosticTimeSlot]??new Set()});
  return {...env,[roadSlot]:capability};
}

// Existing national *access* checks plus the existing bounded provider helper.
// No national path search, geocoder, price recalculation or persistent route.
export async function mapboxOperationalRoadTravelV1({env,scope,from,to,configuredOriginSiteBinding=null,diagnostic=null}){
  const context=roadContexts.get(env?.[roadSlot]);
  if(!context||!sameScope(context.scope,scope)||Date.now()>=context.expiresAt){
    if(context&&sameScope(context.scope,scope))recordMapboxDispatchTimeV1(context,[], 'gps_check_entry',undefined,diagnostic);
    fail('mapbox_operational_context_required');
  }
  const point=p=>({latitude:p?.latitude??p?.lat,longitude:p?.longitude??p?.lng,...(p?.access?{access:p.access}:{}),...(p?.official_address?{official_address:p.official_address}:{})});
  const a=point(from),b=point(to);
  if([a,b].some(p=>!Number.isFinite(p.latitude)||Math.abs(p.latitude)>90||!Number.isFinite(p.longitude)||Math.abs(p.longitude)>180))fail('mapbox_quote_points_invalid');
  const gpsExpiry=Math.min(context.expiresAt,...[a,b].filter(p=>p.access?.kind==='gps').map(p=>p.access.capturedAt+30000));
  const assertFresh=stage=>{const now=Date.now();observeMapboxDispatchRouteTimeV1(diagnostic,context,[a,b],stage,now);if(!Number.isFinite(gpsExpiry)||now>=gpsExpiry
    ||[a,b].some(p=>p.access?.kind==='gps'&&(!Number.isFinite(p.access.capturedAt)||p.access.capturedAt>now))){
    recordMapboxDispatchTimeV1(context,[a,b],stage,now);fail('access_gps_stale_or_accuracy');}};
  assertFresh('gps_check_before_access');
  const key=canonical([a,b,configuredOriginSiteBinding]);
  if(context.routes.has(key)){assertFresh('gps_check_cached');return structuredClone(context.routes.get(key));}
  const router=await context.operational.__reliableRegionalRoutes(scope);
  await router.resolveForJourney({pickup_lat:a.latitude,pickup_lng:a.longitude,dropoff_lat:b.latitude,dropoff_lng:b.longitude});
  const graph=router.addressGraph(),graphScope=router.scope,index=await operationalOfficialAddressIndexV1(context.bounded);
  const resolver=index?createOfficialAddressAccessResolverV1({index,graph,scope:graphScope}):null;
  async function anchor(input,role){
    if(input.official_address){
      if(!resolver)fail('official_address_index_unavailable');
      const record=await createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true}).resolve(input.official_address.id);
      if(projectAccessV1(record.point,input,input).meters>1)fail('official_address_position_changed');
      const result=await resolver.resolve({kind:'address',official_address:input.official_address},{role});
      const candidates=result.candidates.filter(c=>c.status==='proven');
      if(result.status!=='access_proven'||candidates.length!==1)fail('mapbox_quote_access_unproven');
      resolver.routePoint(result,candidates[0].id);return wire(candidates[0].point);
    }
    if(role==='origin'&&configuredOriginSiteBinding){
      const materialized=await router.resolveConfiguredSitePoint({point:input,binding:configuredOriginSiteBinding,role});
      const snap=readConfiguredSiteRoutePointV1(materialized,{scope:graphScope,graphVersion:graph.graphVersion,revision:graph.revision,role});
      if(!snap?.accessEvidence?.frontage?.point)fail('configured_site_binding_unproven');return wire(snap.accessEvidence.frontage.point);
    }
    const raw=await graph.readContext({point:input,address:{id:'operational-road-point',address:{}},role,radiusMeters:Math.max(100,input.access?.accuracyMeters??0)});
    if(raw?.complete!==true||raw.graphVersion!==graph.graphVersion||raw.revision!==graph.revision)fail('mapbox_quote_access_unproven');
    const args={input,segments:raw.segments,negative:raw.negative,graphVersion:graph.graphVersion,revision:graph.revision,completeContext:raw.complete};
    let snap;
    try{snap=input.access?.kind==='gps'?resolveDriverGpsRoadAccessV1(args):resolveRoadAccessV1(args);}
    catch(error){if(error?.message==='access_gps_stale_or_accuracy')recordMapboxDispatchTimeV1(context,[a,b],'gps_check_access',undefined,diagnostic);throw error;}
    const positions=snap.kind==='node'?[snap.node]:snap.alternatives?.map(s=>s.point)??[];
    if(!positions.length||positions.some(p=>p.latitude!==positions[0].latitude||p.longitude!==positions[0].longitude))fail('mapbox_quote_access_unproven');
    return wire(positions[0]);
  }
  const anchors=[await anchor(a,'origin'),await anchor(b,'destination')];
  let route;
  try{route=await boundedMapboxQuoteDirectionsV1({context:context.transport,scope,coords:anchors,token:env.MAPBOX_TOKEN,radiuses:[1,1],
    bearings:a.access?.headingDegrees!=null?[[a.access.headingDegrees,35],null]:null});}
  catch(error){recordMapboxDispatchTimeV1(context,[a,b],'gps_check_provider',undefined,diagnostic);throw error;}
  if(Date.now()>=context.expiresAt){recordMapboxDispatchTimeV1(context,[a,b],'gps_check_after_provider',undefined,diagnostic);fail('mapbox_quote_context_expired');}
  assertFresh('gps_check_after_provider');
  const result={ok:true,travel_seconds:Math.ceil(route.duration),route_profile:'mapbox/driving',route_validation_unavailable:false,
    route_used_geocode_fallback:false,route_used_coordinate_direct:true,route_http_status:200,route_valid_until_ms:gpsExpiry,
    distance_meters:route.distance,route:route.geometry};
  context.routes.set(key,structuredClone(result));return result;
}

export function bindMapboxQuoteRequestV1(environment,request){
  if(!requests.has(request))fail('mapbox_quote_request_unproven');
  const next={...environment,[requestSlot]:request};
  transferFinancialRouteBatchContextV1(environment,next);
  environments.set(next,request);return next;
}
export function mapboxQuoteRequestV1(environment,{scope,body}={}){
  const request=environments.get(environment)??environment?.[requestSlot];if(!request)return null;
  const info=requests.get(request);
  if(!info)fail('mapbox_quote_request_unproven');
  if(!sameScope(info.scope,scope)||info.input!==canonical(financialQuoteInputs(body))||info.operationalInput!==operationalInputs(body))fail('mapbox_quote_request_binding_changed');
  return request;
}
export function verifiedMapboxMissionAreaProofV1(proof,scope){
  const saved=missionProofs.get(proof);return !!saved&&sameScope(saved.scope,scope)&&saved.clock()<saved.expiresAt;
}

export async function createMapboxQuoteRequestV1({scope,body,locations,index,router,transport,token,clock=Date.now,expiresAt=clock()+15000,reuseDirections=(_,resolve)=>resolve()}){
  if(!scope?.tenant_id||!scope?.company_id||!sameScope(router?.scope,scope)||typeof router.resolveForJourney!=='function'
    ||!Array.isArray(locations)||locations.length<2||locations.length>17||!Number.isSafeInteger(expiresAt)||expiresAt<=clock()||expiresAt>clock()+15000)fail('mapbox_quote_request_configuration');
  scope=structuredClone(scope);body=structuredClone(body);locations=structuredClone(locations);
  const authority=createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true}),registered=[];
  for(const loc of locations){
    if(!text(loc?.label))fail('mapbox_quote_location_required');
    if(loc.configuredSiteBinding){registered.push({label:text(loc.label),original:{lat:loc.lat,lng:loc.lng},configured:structuredClone(loc.configuredSiteBinding)});continue;}
    const ref=officialAddressReferenceV1(loc.input);
    if(!ref){
      // Provider/user-selected coordinates are not official authority. Admit
      // only a complete address, bound to this request, through the same
      // immutable street/frontage and road-access checks before Directions.
      if(loc.input?.official_address!=null||loc.input?.kind!=='address'||text(loc.input.label)!==text(loc.label))fail('official_address_required');
      if(!Number.isFinite(loc.lat)||!Number.isFinite(loc.lng)||Math.abs(loc.lat)>90||Math.abs(loc.lng)>180||loc.lat===0&&loc.lng===0)fail('mapbox_quote_points_invalid');
      const selected=publicAddressPointV1({from:loc.label,pickup_lat:loc.lat,pickup_lng:loc.lng,pickup_input:loc.input});
      if(!selected.address?.street||!selected.address.houseNumber)fail('access_address_incomplete');
      registered.push({label:text(loc.label),original:{lat:loc.lat,lng:loc.lng},selected:structuredClone(selected)});continue;
    }
    if(ref.index_revision!==index.revision)fail('official_address_index_changed');
    const address=await authority.resolve(ref.id);
    if(address.source!==ref.source||address.sourceVersion!==ref.source_version)fail('official_address_source_changed');
    if(!officialAddressPositionUsableV1(address))fail('official_address_position_unusable');
    if(!Number.isFinite(loc.lat)||!Number.isFinite(loc.lng)||projectAccessV1(address.point,{latitude:loc.lat,longitude:loc.lng},{latitude:loc.lat,longitude:loc.lng}).meters>1)fail('official_address_position_changed');
    registered.push({label:text(loc.label),original:wire(address.point),ref:structuredClone(ref),address});
  }
  await router.resolveForJourney({pickup_lat:registered[0].original.lat,pickup_lng:registered[0].original.lng,
    dropoff_lat:registered[1].original.lat,dropoff_lng:registered[1].original.lng,stop_coordinates:registered.slice(2).map(r=>r.original)});
  const graph=router.addressGraph(),graphScope=structuredClone(router.scope),resolver=createOfficialAddressAccessResolverV1({index,graph,scope:graphScope,clock});
  const guard=()=>{if(clock()>=expiresAt)fail('mapbox_quote_context_expired');if(!sameScope(router.scope,scope)||router.scope.graphVersion!==graphScope.graphVersion||router.scope.accessContextRevision!==graphScope.accessContextRevision)fail('address_graph_changed');resolver.assertCurrent();};
  function find(point){
    const found=registered.filter(r=>same(r.original,point));
    if(!found.length)fail('mapbox_quote_location_unbound');
    if(new Set(found.map(r=>canonical(r.ref??r.configured??r.selected))).size>1)fail('mapbox_quote_location_ambiguous');
    return found[0];
  }
  async function anchor(record,role){
    guard();record.anchors??={};if(record.anchors[role])return record.anchors[role];
    let point;
    if(record.selected){
      const address={id:'selected:'+canonical(record.original),address:record.selected.address,point:record.selected};
      const context=await graph.readContext({point:record.selected,address,role,radiusMeters:100});
      if(context?.complete!==true||context.graphVersion!==graph.graphVersion||context.revision!==graph.revision||context.radiusMeters<100||!context.center||projectAccessV1(record.selected,context.center,context.center).meters>.1)fail('address_context_incomplete');
      const frontage=resolvePracticalFrontageV1({input:record.selected,segments:context.segments,graphVersion:graph.graphVersion,revision:graph.revision});
      if(context.barriers?.length)fail('access_address_barrier_context_unproven');
      const access=resolveRoadAccessV1({input:frontage.point,segments:context.segments,negative:context.negative,graphVersion:graph.graphVersion,revision:graph.revision,clock});
      if(access.accessEvidence.wayIds.some(id=>!frontage.wayIds.includes(id))&&access.kind!=='node')fail('access_graph_attachment_changed');
      point=frontage.point;
      // Only immutable road metadata may attest a postcode service area.
      // Provider/client labels cannot grant service-area membership.
      const tags=context.segments.filter(s=>frontage.wayIds.includes(s.way)).map(s=>s.tags);
      const unique=k=>{const values=[...new Set(tags.map(t=>t[k]).filter(v=>typeof v==='string'&&v.trim()))];return values.length===1?values[0]:null;};
      record.selectedArea={point:{latitude:record.original.lat,longitude:record.original.lng},address:{postcode:unique('postcode'),country:unique('country')},source:'validated_selected_street'};
      graph.releaseContext?.({address,role});
    }else if(record.configured){
      const materialized=await router.resolveConfiguredSitePoint({point:{latitude:record.original.lat,longitude:record.original.lng},binding:record.configured,role});
      const snap=readConfiguredSiteRoutePointV1(materialized,{scope:graphScope,graphVersion:graph.graphVersion,revision:graph.revision,role});
      point=snap?.accessEvidence?.frontage?.point;if(!point)fail('configured_site_binding_unproven');
    }else{
      const result=await resolver.resolve({kind:'address',official_address:record.ref},{role});
      const candidates=result.candidates.filter(c=>['proven','unproven'].includes(c.status));
      if(result.status!=='access_proven')fail(({access_forbidden:'address_access_forbidden',data_insufficient:'address_data_insufficient',budget_exceeded:'address_candidate_limit'})[result.status]??'access_address_parallel_ambiguity');
      if(candidates.length!==1||candidates[0].status!=='proven')fail('access_address_parallel_ambiguity');
      resolver.routePoint(result,candidates[0].id); // Check private access authority.
      point=candidates[0].point;
    }
    if(!Number.isFinite(point.latitude)||!Number.isFinite(point.longitude))fail('mapbox_quote_access_unproven');
    guard();return record.anchors[role]=wire(point);
  }
  const routes=new Map();
  const api={
    // Only our own frozen sale may persist. Provider route results remain
    // transient; this capability never authorizes the former full snapshot.
    financialRouteRetention:'sale_only',
    async selectedAddressForArea(point){guard();const record=find(point);if(!record.selected)return null;await anchor(record,'origin');guard();return structuredClone(record.selectedArea);},
    async geocode(label){guard();const found=registered.filter(r=>r.label===text(label));if(!found.length||new Set(found.map(r=>canonical(r.original))).size!==1)fail('mapbox_quote_text_unbound');return {...found[0].original};},
    async municipality(points){guard();return points.map(p=>{const r=find(p);if(!r.address)fail('official_municipality_required');return r.address.address.municipality??r.address.address.locality;});},
    async directions(points){
      guard();if(!Array.isArray(points)||points.length<2||points.length>10)fail('mapbox_quote_points_invalid');
      const selected=points.map(find),anchors=[];
      for(const [i,r] of selected.entries()){
        const a=await anchor(r,i===points.length-1?'destination':'origin');
        if(i>0&&i<points.length-1&&!same(a,await anchor(r,'destination')))fail('mapbox_quote_stop_access_ambiguous');
        anchors.push(a);
      }
      const key=canonical(anchors);
      if(routes.has(key)){guard();return structuredClone(routes.get(key));}
      // One metre only allows coordinate serialization at the independently
      // proven road anchor. Never snap across an unproved building connector.
      const radiuses=anchors.map(()=>1);
      const route=await reuseDirections({coords:anchors,radiuses},()=>boundedMapboxQuoteDirectionsV1({context:transport,scope,coords:anchors,token,radiuses}));
      guard();routes.set(key,structuredClone(route));return route;
    },
    async itinerary(args,build){
      const {fromText,toText,fromPoint,toPoint,stopsTexts=[],stopCoordinates=[]}=args;
      const from=await api.geocode(fromText),to=await api.geocode(toText);
      if(fromPoint&&!same(from,fromPoint)||toPoint&&!same(to,toPoint)||!Array.isArray(stopsTexts)||stopsTexts.length>6||stopCoordinates.length!==stopsTexts.length)fail('mapbox_quote_endpoint_binding');
      const stops=[];
      for(const [i,label]of stopsTexts.entries()){
        const stored=stopCoordinates[i],point=await api.geocode(label);
        if(stored?.address!==label||stored.invalidated===true||stored.confirmed===false||stored.needs_confirmation===true||stored.coordinates_valid===false||stored.coordinate_valid===false||!same(point,stored))fail('mapbox_quote_stop_binding');
        stops.push(point);
      }
      const coords=[from,...stops,to],route=await api.directions(coords);
      const out=await build({...args,fromPoint:from,toPoint:to,route});
      guard();return out;
    },
    async proveMissionArea({depot,body:journey,readStops}){
      const from=await api.geocode(journey.from),to=await api.geocode(journey.to),stops=await Promise.all(readStops(journey).map(api.geocode));
      const r=await api.directions([depot,from,...stops,to,depot]);
      const proof=Object.freeze({ok:true,route_profile:'mapbox/driving',route_used_geocode_fallback:false,route_validation_unavailable:false,
        distance_meters:r.legs[0].distance,route_valid_until_ms:expiresAt,source:'mapbox',source_version:'directions/v5',access_proven:true});
      missionProofs.set(proof,{scope:structuredClone(scope),clock,expiresAt});return proof;
    },
    diagnostics:()=>({source:'mapbox',nationalRouteCalculations:0,access:resolver.diagnostics(),distinctRoutes:routes.size}),
  };
  requests.set(api,{scope:structuredClone(scope),input:canonical(financialQuoteInputs(body)),operationalInput:operationalInputs(body)});return Object.freeze(api);
}

// Existing runtime/index/access modules, installed at the authenticated quote
// boundary and again inside the existing booking coordinator. No JSON field
// can grant this capability. The limiter is an edge abuse bound, not a global
// invoice cap; the scoped activation allowlist remains mandatory.
export async function bindConfiguredMapboxQuoteRequestV1({env,scope,body,locations,customerRoute=false}){
  if(env.MAPBOX_QUOTE_ROUTING_ENABLED!=='1')return env;
  if(mapboxQuoteRequestV1(env,{scope,body}))return env;
  const allowed=String(env.MAPBOX_QUOTE_ALLOWED_SCOPES??'').split(',').map(s=>s.trim());
  if(!allowed.includes(scope.tenant_id+'/'+scope.company_id))fail('mapbox_quote_scope_not_active');
  if(typeof env.BOOKING_SEARCH_LIMITER?.limit!=='function'||!env.MAPBOX_TOKEN?.trim())fail('mapbox_quote_transport_not_configured');
  const context=financialRouteBatchContextV1(env);
  if(customerRoute===true){
    if(body.customer_route_provider!=='mapbox_v1')fail('customer_route_provider_invalid');
    // Only the scoped server profile grants a depot capability. Customer JSON
    // and the public location list cannot add a depot or broaden route rights.
    let missionDepot=null;
    if(env.COMPANY_MISSION_PRICING_ENABLED==='1'){
      const raw=await env.BOOKING_KV.get(`tenant:${scope.tenant_id}:company:${scope.company_id}:business_profile:v1`,{type:'json'});
      const profile=raw?.business_profile??raw;
      if(profile&&['tenant_id','company_id'].some(k=>[raw?.[k],profile[k]].some(v=>v!=null&&v!==scope[k])))fail('company_scope_unverified');
      if(profile?.mission_tariff?.enabled===true){
        const parsed=parseCompanyMissionTariff(profile.mission_tariff);if(!parsed.ok)fail('mission_tariff_invalid');
        missionDepot=parsed.tariff.depot;
      }
    }
    const expiresAt=Math.min(Date.now()+15000,...locations.filter(location=>location.input?.kind==='gps')
      .map(location=>location.input.capturedAt+30000));
    const transport=createMapboxQuoteTransportV1({scope,expiresAt,maxRequests:4,pointPolicy:'customer_selected_v1',
      reserve:async()=> (await env.BOOKING_SEARCH_LIMITER.limit({key:'mapbox-directions-actual-request'}))?.success===true
        &&await reserveStagingTrialForEnvV1(env,'mapbox_directions'),
      send:(url,init)=>globalThis.fetch(url,init)});
    const api=createCustomerMapboxQuoteApiV1({scope,body,locations,transport,token:env.MAPBOX_TOKEN,expiresAt,missionDepot,
      sealMissionProof:proof=>{missionProofs.set(proof,{scope:structuredClone(scope),clock:Date.now,expiresAt});return proof;},
      reuseArea:({point},resolve)=>financialMunicipalityInBatchV1({context,point,resolve}),
      reuseDirections:async({coords},resolve)=>{
        try{return await financialDirectionsInBatchV1({context,coords,options:{pointPolicy:'customer_selected_v1'},resolve});}
        finally{console.info(JSON.stringify({event:'mapbox_quote_resources_v1',nationalRouteCalculations:0,...mapboxQuoteTransportMetricsV1(transport)}));}
      }});
    requests.set(api,{scope:structuredClone(scope),input:canonical(financialQuoteInputs(body)),operationalInput:operationalInputs(body)});
    return bindMapboxQuoteRequestV1(env,api);
  }
  const budget=financialRouteBatchR2BudgetV1({context,bucket:env.RELIABLE_GRAPH_OBJECTS,
    create:()=>createQuoteR2BudgetV1(env.RELIABLE_GRAPH_OBJECTS,{readLimit:64,byteLimit:32*1024*1024,completedCacheBytes:4*1024*1024})});
  const bounded={...env,RELIABLE_GRAPH_OBJECTS:budget.bucket,RELIABLE_CHOICE_ENABLED:'1',RELIABLE_NATIONAL_REQUIRED:'1',
    RELIABLE_NATIONAL_PUBLICATION_REF:env.OWNED_QUOTE_PUBLICATION_REF??env.RELIABLE_NATIONAL_PUBLICATION_REF,
    RELIABLE_NATIONAL_ACTIVATION:env.OWNED_QUOTE_ACTIVATION??env.RELIABLE_NATIONAL_ACTIVATION};
  // A previously installed resolver closes over the old bucket. Remove only
  // its private installation marker so all real cache misses are bounded.
  for(const symbol of Object.getOwnPropertySymbols(bounded))if(operationalRoutingInstalledV1({RELIABLE_CHOICE_ENABLED:'1',[symbol]:bounded[symbol]}))delete bounded[symbol];
  const operational=withOperationalRoutingV1(bounded),index=await operationalOfficialAddressIndexV1(bounded);
  if(!index||!operationalRoutingInstalledV1(operational))fail('mapbox_quote_access_runtime_unavailable');
  const router=await operational.__reliableRegionalRoutes(scope),expiresAt=Date.now()+15000;
  const transport=createMapboxQuoteTransportV1({scope,expiresAt,maxRequests:4,
    reserve:async()=> (await env.BOOKING_SEARCH_LIMITER.limit({key:'mapbox-directions-actual-request'}))?.success===true
      &&await reserveStagingTrialForEnvV1(env,'mapbox_directions'),
    send:(url,init)=>globalThis.fetch(url,init)});
  const api=await createMapboxQuoteRequestV1({scope,body,locations,index,router,transport,token:env.MAPBOX_TOKEN,expiresAt,
    reuseDirections:async({coords,radiuses},resolve)=>{
      try{return await financialDirectionsInBatchV1({context,coords,options:{radiuses:radiuses.join(';')},resolve});}
      finally{console.info(JSON.stringify({event:'mapbox_quote_resources_v1',...budget.metrics(),...mapboxQuoteTransportMetricsV1(transport)}));}
    }});
  return bindMapboxQuoteRequestV1(env,api);
}

// Phases this road-access call can throw. Anything else stays unclassified
// so a stack, coordinate or token never becomes a response field.
const DISPATCH_ACCESS_PHASES = new Set([
  'mapbox_operational_context_required','mapbox_quote_points_invalid','mapbox_quote_context_expired',
  'mapbox_quote_access_unproven','mapbox_quote_context_required','mapbox_quote_context_changed',
  'mapbox_quote_scope_mismatch','mapbox_quote_access_radius_invalid','mapbox_quote_bearing_invalid',
  'mapbox_quote_request_limit','mapbox_quote_shared_budget_denied','mapbox_quote_response_limit',
  'mapbox_quote_response_invalid','mapbox_quote_route_inconsistent','mapbox_quote_waypoints_unproven',
  'mapbox_quote_geometry_invalid','mapbox_quote_geometry_binding','mapbox_quote_transport_error',
  'mapbox_quote_transport_not_configured','mapbox_quote_preview_invalid','mapbox_quote_access_runtime_unavailable',
  'route_config_missing','mapbox_quote_timeout','mapbox_quote_provider_limited','mapbox_quote_provider_http_error',
  'mapbox_quote_no_segment','mapbox_quote_no_route',
  'official_address_index_unavailable','official_address_position_changed','configured_site_binding_unproven',
  'access_gps_stale_or_accuracy','access_heading_unreliable','access_restricted_or_barrier_ambiguity',
  'access_context_missing','access_context_invalid','access_vertical_layer_unproven','access_motorway_pickup_unproven',
  'access_restricted_road','access_parallel_or_junction_ambiguity','access_direction_unproven',
  'access_outlier_or_adjacent_road_ambiguity','access_segment_ambiguity','access_junction_transition_unproven',
  'access_wrong_direction','access_driver_gps_sample_unbound','access_driver_gps_accuracy',
  'access_driver_gps_context_incomplete','access_driver_gps_context_not_unique','access_way_invalid',
  'access_street_metadata_invalid','access_negative_invalid','access_negative_index_limit',
  'access_mapped_connector_missing',
  'speed_profile_catalog_invalid','speed_profile_reference_invalid',
  'owned_quote_r2_read_budget','owned_quote_r2_byte_budget',
]);
// Request-local private categories only. Original rejection codes and deadlines
// stay authoritative; this observer never adjusts capture time or route leases.
const DISPATCH_TIME_PHASES=new Set(['gps_capture_missing','gps_capture_invalid','gps_capture_future','gps_capture_expired',
  'operational_lease_expired','gps_check_entry','gps_check_before_access','gps_check_cached','gps_check_access','gps_check_provider','gps_check_after_provider']);
export function observeMapboxDispatchCaptureV1(access,rawCapture){
  if(access?.kind==='gps'&&(rawCapture==null||rawCapture===''))missingCaptureInputs.add(access);
}
export function classifyMapboxDispatchTimeV1({points=[],expiresAt,now=Date.now()}={}){
  const phases=new Set();
  if(Number.isFinite(expiresAt)&&now>=expiresAt)phases.add('operational_lease_expired');
  for(const point of points){
    if(point?.access?.kind!=='gps')continue;
    const capturedAt=point.access.capturedAt;
    if(capturedAt==null||missingCaptureInputs.has(point.access))phases.add('gps_capture_missing');
    else if(!Number.isFinite(capturedAt))phases.add('gps_capture_invalid');
    else if(capturedAt>now)phases.add('gps_capture_future');
    else if(now>=capturedAt+30000)phases.add('gps_capture_expired');
  }
  return [...phases];
}
function observeMapboxDispatchRouteTimeV1(observer,context,points,stage,now){
  if(typeof observer!=='function')return;
  try{
    const phases=classifyMapboxDispatchTimeV1({points,expiresAt:context.expiresAt,now});
    const gpsPhase=phases.find(phase=>phase.startsWith('gps_capture_'));
    observer({phases:phases.length?[...phases,stage]:[],stage,
      lease_status:Number.isFinite(context.expiresAt)?(now>=context.expiresAt?'expired':'valid'):'unknown',
      gps_status:stage==='gps_check_entry'?'unknown':gpsPhase?gpsPhase.slice('gps_capture_'.length)
        :points.some(point=>point?.access?.kind==='gps')?'valid':'not_applicable'});
  }catch{/* A private observer cannot change a route decision. */}
}
function recordMapboxDispatchTimeV1(context,points,stage,now=Date.now(),observer=null){
  observeMapboxDispatchRouteTimeV1(observer,context,points,stage,now);
  const phases=classifyMapboxDispatchTimeV1({points,expiresAt:context.expiresAt,now});
  if(!phases.length)return;
  context.timePhases??=new Set();
  for(const phase of phases)context.timePhases.add(phase);
  if(DISPATCH_TIME_PHASES.has(stage))context.timePhases.add(stage);
}
export function bindMapboxDispatchTimeDiagnosticV1(env){
  return {...env,[diagnosticTimeSlot]:new Set()};
}
export function mapboxDispatchTimePhasesV1(env){
  if(!env)return [];
  return [...(env[diagnosticTimeSlot]??roadContexts.get(env[roadSlot])?.timePhases??[])];
}
export function mapboxDispatchAccessPhaseV1(error){
  const message = typeof error?.message === 'string' ? error.message : '';
  return DISPATCH_ACCESS_PHASES.has(message) ? message : null;
}
export function mapboxDispatchAccessRefusalV1(error){
  const phase = mapboxDispatchAccessPhaseV1(error);
  return {ok:false,travel_seconds:null,reason_code:'provider_dispatch_access_unavailable',
    route_failure_reason:'provider_dispatch_access_unavailable',
    ...(phase ? {route_error_code:phase} : {}),
    route_validation_unavailable:true,route_used_geocode_fallback:false,route_profile:'mapbox/driving'};
}
export function mapboxDispatchAccessPhaseHeaderV1(phases){
  const safe=[], seen=new Set();
  for(const phase of phases??[]){
    if(typeof phase!=='string'||(!DISPATCH_ACCESS_PHASES.has(phase)&&!DISPATCH_TIME_PHASES.has(phase))||seen.has(phase))continue;
    seen.add(phase);safe.push(phase);
  }
  return safe.join(',');
}
export function mapboxDispatchAccessPhaseResponseV1(response,{authorized=false,phases=[],env}={}){
  const value=authorized===true?mapboxDispatchAccessPhaseHeaderV1([...phases,...mapboxDispatchTimePhasesV1(env)]):'';
  if(!value)return response;
  const headers=new Headers(response.headers);
  headers.set('x-fluxidi-dispatch-phase',value);
  headers.set('cache-control','private, no-store');
  return new Response(response.body,{status:response.status,statusText:response.statusText,headers});
}
