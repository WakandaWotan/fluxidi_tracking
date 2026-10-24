// Read-only enrichment of the existing customer tracking grant. No quote,
// booking journal, route archive or payment mutation is involved.
import {companyTrackingObjectName} from '../../tracking/modules/company_tracking_room.mjs';
import {bindMapboxOperationalContextV1,mapboxOperationalRoadTravelV1,mapboxProviderScopeEnabledV1} from './mapbox_quote_request_v1.mjs';
import {trackingFactsFromRecord} from './customer_tracking_access.mjs';
import {officialAddressReferenceV1} from './official_address_reference_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
const fail=code=>{throw Error(code);};
export async function customerTransientRouteV1(env,input){
  const {tenant_id,company_id,booking_id,operational_leg='primary',access_token_hash,assignment_version}=input??{};
  if(![tenant_id,company_id,booking_id].every(v=>typeof v==='string'&&v.length>0&&v.length<=160)
    ||! /^[a-f0-9]{64}$/.test(access_token_hash??''))fail('tracking_route_access_required');
  const scope={tenant_id,company_id};
  if(!mapboxProviderScopeEnabledV1(env,scope))fail('tracking_route_not_active');
  const room=env.COMPANY_TRACKING.get(env.COMPANY_TRACKING.idFromName(companyTrackingObjectName(tenant_id,company_id)));
  const url=new URL('https://room/customer-live');
  for(const [k,v]of Object.entries({tenant_id,company_id,booking_id,operational_leg,access_token_hash,assignment_version}))if(v!=null)url.searchParams.set(k,String(v));
  const read=async()=>{const r=await room.fetch(url);if(!r.ok)fail('tracking_route_access_changed');return r.json();};
  const snapshot=await read();
  if(!snapshot.position||!['en_route_pickup','in_progress'].includes(snapshot.tracking_phase))fail('tracking_route_position_unavailable');
  const record=await env.BOOKING_KV.get('booking:'+booking_id,{type:'json'});
  const facts=trackingFactsFromRecord(record,null,operational_leg);
  const samePhase=facts.tracking_phase===snapshot.tracking_phase
    || facts.tracking_phase==='assigned'&&snapshot.tracking_phase==='en_route_pickup';
  if(facts.tenant_id!==tenant_id||facts.company_id!==company_id||facts.booking_id!==booking_id
    ||facts.assignment_version!==snapshot.assignment_version||!samePhase)fail('tracking_route_assignment_changed');
  if(typeof env.BOOKING_SEARCH_LIMITER?.limit!=='function'||typeof env.CUSTOMER_ROUTE_LIMITER?.limit!=='function')fail('tracking_route_limiter_unavailable');
  if(!(await env.CUSTOMER_ROUTE_LIMITER.limit({key:'customer-route:'+tenant_id+':'+company_id+':'+booking_id+':'+operational_leg}))?.success)fail('tracking_route_rate_limited');
  // Use only the authorized read-only customer snapshot. /live expires offers
  // as a side effect and must not be used for this presentation read.
  const latitude=snapshot.position.latitude,longitude=snapshot.position.longitude,
    capturedAt=Date.parse(snapshot.position.captured_at??'');
  const target=snapshot.tracking_phase==='in_progress'?'destination':'pickup',destination=facts[target];
  if(!destination)fail('tracking_route_target_unavailable');
  const own=record.financial_evidence?.inputs?.official_inputs??record.official_address_route_context?.inputs;
  const refs=[];function collect(v){if(!v||typeof v!=='object')return;if(v.kind==='address'){const ref=officialAddressReferenceV1(v);if(ref)refs.push(ref);}else for(const x of Object.values(v))collect(x);}
  collect(own);if(refs.length<2||refs.length>24)fail('tracking_route_official_reference_required');
  const index=await operationalOfficialAddressIndexV1(env),authority=createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true});
  let reference=null;
  for(const ref of refs){const address=await authority.resolve(ref.id);if(address.point.latitude===destination.latitude&&address.point.longitude===destination.longitude){if(reference&&reference.id!==ref.id)fail('tracking_route_target_ambiguous');reference=ref;}}
  if(!reference)fail('tracking_route_target_unproven');
  const bound=bindMapboxOperationalContextV1(env,scope);
  const result=await mapboxOperationalRoadTravelV1({env:bound,scope,
    from:{latitude,longitude,access:{kind:'gps',capturedAt,accuracyMeters:snapshot.position.accuracy}},
    to:{...destination,official_address:reference}});
  const latest=await read();
  if(!latest.position||latest.response_version!==snapshot.response_version||latest.assignment_version!==snapshot.assignment_version
    ||latest.tracking_phase!==snapshot.tracking_phase)fail('tracking_route_access_changed');
  const valid_until=new Date(Math.min(Date.now()+60000,Date.parse(latest.refresh?.access_until??''))).toISOString();
  return {ok:true,assignment_version:latest.assignment_version,tracking_phase:latest.tracking_phase,
    route:{coordinates:result.route.coordinates.map(([longitude,latitude])=>({latitude,longitude})),source:'mapbox',valid_until},
    eta:{target,source:'mapbox/driving',duration_seconds:result.travel_seconds,distance_meters:result.distance_meters,valid_until}};
}
