import {companyWorkAreaPostcodes} from './airport_company_policy.mjs';
import {isAirportWorkAreaRequest,isTaxiWorkAreaRequest} from './taxi_work_area_policy.mjs';
import {parseCompanyMissionTariff} from './company_mission_tariff_config.mjs';
import {officialAddressReferenceV1,officialAddressPositionUsableV1} from './official_address_reference_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {verifiedMapboxMissionAreaProofV1,mapboxQuoteRequestV1} from './mapbox_quote_request_v1.mjs';

// Applies to new searches only: never admission for payment, recovery, an
// existing booking, driver presence, tracking or a financial writer.
const searchPaths = new Set([
  '/quote','/public/quote','/public/airport/quote',
  '/public/customer/vehicle-quotes','/public/customer/official-address-search',
  '/public/customer/official-address-picker','/public/address/suggest',
  '/company/official-address-search',
  '/public/address/reverse','/public/airport/address/suggest',
  '/public/airport/address/reverse','/partners/availability',
  '/partners/private-chauffeur/availability','/availability',
]);
const retiredGeocoders = new Set(['/public/address/suggest','/public/address/reverse','/public/airport/address/suggest','/public/airport/address/reverse']);
const response = (error,status) => new Response(JSON.stringify({ok:false,error}),{
  status,headers:{'content-type':'application/json','cache-control':'no-store',
    'access-control-allow-origin':'*',...(status===429?{'retry-after':'60'}:{})},
});

// Native edge counters avoid KV reads/writes on rejected bursts. These are
// per-location abuse limits, NOT exact global billing caps. Both bindings must
// be configured before activation; missing/failed admission never fails open.
export async function bookingSearchIngress(request,env){
  const path=new URL(request.url).pathname;
  if(request.method==='OPTIONS'||!searchPaths.has(path))return null;
  if(retiredGeocoders.has(path))return response('official_address_required',410);
  const shared=env.BOOKING_SEARCH_LIMITER,client=env.BOOKING_SEARCH_CLIENT_LIMITER;
  if(typeof shared?.limit!=='function'||typeof client?.limit!=='function')return response('search_admission_unavailable',503);
  if(request.signal.aborted)return response('search_cancelled',499);
  // Cloudflare overwrites this header on ingress. It is only a coarse abuse
  // key, never a customer identity, company authorization or location proof.
  const ip=request.headers.get('cf-connecting-ip');
  if(!ip||ip.length>64)return response('search_admission_unavailable',503);
  let timer;
  try{
    const allowed=await Promise.race([
      (async()=>{
        if((await shared.limit({key:'new-booking-search'}))?.success!==true)return false;
        return (await client.limit({key:'new-booking-search:'+ip}))?.success===true;
      })(),
      new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('timeout')),1000);}),
    ]);
    if(request.signal.aborted)return response('search_cancelled',499);
    return allowed?null:response('rate_limited',429);
  }catch{return response('search_admission_unavailable',503);}
  finally{clearTimeout(timer);}
}

const deny=(error,status=422)=>({ok:false,status,error});

// The selected service area is attested by the SAME server-owned official
// record as the coordinates handed to the existing quote engine. No client
// postcode/country, GPS proximity, provider geocode or IP country is authority.
export async function admitBookingQuoteArea({body,env,profile,scope,companyDecision,
  readPoint,proveMissionArea,proveCompanyRadius,airportRoutePresentation=false,loadIndex=operationalOfficialAddressIndexV1}){
  if(companyDecision?.applicable!==true||companyDecision.ok!==true)return deny('company_unavailable',403);
  if(!scope?.tenant_id||!scope.company_id||!profile||
    ['tenant_id','tenantId'].some(k=>profile[k]!=null&&profile[k]!==scope.tenant_id)||
    ['company_id','companyId'].some(k=>profile[k]!=null&&profile[k]!==scope.company_id))return deny('company_scope_unverified',403);
  const airport=isAirportWorkAreaRequest(body);
  const directions=[body.airport_direction,body.airportDirection,body.ride_options?.airport_direction,
    body.airport_transfer?.airport_direction].filter(v=>v!=null&&v!=='').map(v=>String(v).trim().toLowerCase());
  if(airport&&(!directions.length||directions.some(v=>!['from_airport','to_airport'].includes(v)||v!==directions[0])))return deny('airport_direction_unverified');
  // Only the handler's moneyless airport presentation branch may omit the
  // commercial service-area decision. A privately bound Mapbox request still
  // attests the selected points; this is never fare/availability authority.
  if(airportRoutePresentation){
    if(!airport || body.service!=='airport' || body.customer_route_provider!=='mapbox_v1'
      || body.route_presentation_mode!=='route_only_v1' || body.public_price_preview!=null
      || body.financial_context!=null || body.financial_quote_id!=null
      || !mapboxQuoteRequestV1(env,{scope,body}))return deny('route_presentation_mode_invalid',400);
    return {ok:true,area:{configured:false,checked:false,inside:false,outside:false,source:'route_presentation_only'}};
  }
  const side=airport&&directions[0]==='from_airport'?'to':'from';
  const mission=env.COMPANY_MISSION_PRICING_ENABLED==='1'&&!airport&&isTaxiWorkAreaRequest(body)
    &&profile.mission_tariff?.enabled===true?parseCompanyMissionTariff(profile.mission_tariff):null;
  const served=companyWorkAreaPostcodes(profile);
  let ref,address;
  // A private Customer request reuses its chosen position for a published
  // radius, or its bounded SERVER Mapbox area lookup for an explicit postcode
  // list. Client postcode labels never establish service-area membership.
  if(body.customer_route_provider==='mapbox_v1'){
    try{const api=mapboxQuoteRequestV1(env,{scope,body});address=await api?.selectedAddressForArea(readPoint(body,side),{requirePostcode:!mission&&served.size>0});}
    catch{return deny('booking_area_unverified');}
    if(!address)return deny('booking_area_unverified');
  }
  try{ref=officialAddressReferenceV1(body[side==='from'?'pickup_input':'destination_input']);}
  catch{return deny('official_address_required');}
  if(ref&&!address){
    try{
      const index=await loadIndex(env);
      if(!index)return deny('official_address_index_unavailable',503);
      if(ref.index_revision!==index.revision)return deny('official_address_index_changed',409);
      // Identity selection is separate from assignment/access certification.
      // The existing access resolver already preserves current official records
      // whose regional source does not publish an assignment boolean.
      address=await createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true}).resolve(ref.id);
      if(address.source!==ref.source||address.sourceVersion!==ref.source_version)return deny('official_address_source_changed',409);
      if(!officialAddressPositionUsableV1(address))return deny('official_address_position_unusable');
      const point=readPoint(body,side);
      if(!point||!Number.isFinite(point.lat)||!Number.isFinite(point.lng)||
        Math.abs(point.lat-address.point.latitude)>1e-7||Math.abs(point.lng-address.point.longitude)>1e-7)return deny('official_address_position_changed',409);
    }catch{return deny('booking_area_unverified');}
  }
  // Preserve the existing company mission policy: its depot mission replaces
  // postcode-only scope. In particular, a national border is NOT a denial.
  // The existing owned engine or an explicitly bound server Mapbox request
  // attests this bound. A copied provider-shaped JSON proof is not authority.
  // No new radius, country list or client-side override.
  if(mission){
    if(!mission.ok||typeof proveMissionArea!=='function')return deny('booking_area_unverified');
    try{
      const proof=await proveMissionArea({scope,body,depot:mission.tariff.depot});
      const mapbox=verifiedMapboxMissionAreaProofV1(proof,scope);
      if(proof?.ok!==true||(!mapbox&&proof.route_profile!=='fluxidi/local-planning-v1')||
        proof.route_used_geocode_fallback!==false||proof.route_validation_unavailable!==false||
        !Number.isFinite(proof.distance_meters)||proof.distance_meters<0||
        !Number.isFinite(proof.route_valid_until_ms)||proof.route_valid_until_ms<=Date.now())return deny('booking_area_unverified');
      return {ok:true,area:{configured:true,checked:true,inside:true,outside:false,
        source:mapbox?'company_mission_mapbox_route':'company_mission_owned_route',...(mapbox?{}:{graph_version:proof.graph_version})}};
    }catch{return deny('booking_area_unverified');}
  }
  if(!address){
    try{const api=mapboxQuoteRequestV1(env,{scope,body});address=await api?.selectedAddressForArea(readPoint(body,side));}
    catch{return deny('booking_area_unverified');}
    if(!address)return deny('official_address_required');
  }
  // Reuse the same server-published geographic coverage as nearby discovery
  // when no explicit postcode list is configured. Never invent postcodes or
  // interpret an empty field as evidence that the company has no radius.
  if(served.size===0){
    if(typeof proveCompanyRadius!=='function')return deny('booking_area_unconfigured');
    let radius;try{radius=await proveCompanyRadius({address});}catch{return deny('booking_area_unverified');}
    if(radius?.configured!==true)return deny('booking_area_unconfigured');
    if(!Number.isFinite(radius.distance_km)||radius.distance_km<0||!Number.isFinite(radius.service_radius_km)||radius.service_radius_km<=0)return deny('booking_area_unverified');
    if(radius.inside!==true||radius.distance_km>radius.service_radius_km)return deny('booking_area_not_served');
    return {ok:true,area:{configured:true,checked:true,inside:true,outside:false,
      source:'existing_published_company_radius',distance_km:radius.distance_km,service_radius_km:radius.service_radius_km,
      customer_postcode:address.address.postcode,customer_country:address.address.country,official_address_id:address.id}};
  }
    if(typeof address.address.postcode!=='string')return deny('booking_area_unverified');
    const postcode=address.address.postcode.replace(/\s/g,'').toUpperCase();
    // Legacy served lists support BE four-digit and NL full postcodes. Their
    // meaning comes from the official record, never the company's home country
    // or a client country string. Mixed BE/NL work areas remain valid.
    if(!served.has(postcode))return deny('booking_area_not_served');
    return {ok:true,area:{configured:true,checked:true,inside:true,outside:false,
      customer_postcode:postcode,customer_country:address.address.country,official_address_id:address.id}};
}
