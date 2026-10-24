import {loadOfficialAddressTextIndexV1} from './official_address_text_http_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
import {resolveOfficialAddressTextV1,ADDRESS_TEXT_V1} from './official_address_text_search_v1.mjs';
import {sanitizeLimousineTransferEndpoint} from './limousine_transfer_endpoint.mjs';
import {nationalFinancialQuoteLocationsV1} from './financial_national_quote_locations_v1.mjs';
import {bindNationalFinancialRequestV1} from './financial_national_binding_v1.mjs';
const fail=()=>{throw Error('limousine_official_endpoint_binding');};
const text=s=>typeof s==='string'?s.trim().replace(/\s+/g,' '):'';
function endpoint(body,role,raw){
 if(raw==null)return;
 const e=sanitizeLimousineTransferEndpoint(raw);if(!e||text(e.formatted_address)!==text(body[role]))fail();
 if(e.latitude==null||e.longitude==null)fail();
 for(const [a,b]of role==='from'?[['from_lat','from_lng'],['pickup_lat','pickup_lng']]:[['to_lat','to_lng'],['dropoff_lat','dropoff_lng']]){
  if(body[a]!=null&&body[a]!==e.latitude||body[b]!=null&&body[b]!==e.longitude)fail();
 }
 const field=role==='from'?'pickup_input':'destination_input';
 if(body[field]?.kind==='gps')fail();
 if(body[field]?.official_address&&JSON.stringify(body[field].official_address)!==JSON.stringify(e.official_address))fail();
 body[role+'_lat']=e.latitude;body[role+'_lng']=e.longitude;
 body[field]={kind:'address',label:body[role],...(e.official_address?{official_address:e.official_address}:{})};
}
// Reuse typed itinerary and the existing financial routing authority. No new
// quote identity, price, source approval, geocoding fallback or tenant override.
export function limousineOwnedJourneyBodiesV1(itinerary){
 const body={...itinerary};endpoint(body,'from',itinerary.from_endpoint);endpoint(body,'to',itinerary.to_endpoint);
 const stops=body.stops??[];if(!Array.isArray(stops)||stops.length>8)fail();
 const endpoints=itinerary.stop_endpoints;
 if(endpoints!=null&&(!Array.isArray(endpoints)||endpoints.length!==stops.length))fail();
 if(endpoints?.length){
  body.stop_coordinates=endpoints.map((raw,i)=>{
   const point={from:stops[i]};endpoint(point,'from',raw);
   const original=body.stop_coordinates?.[i];
   if(original&&(original.address!==stops[i]||original.lat!==point.from_lat||(original.lng??original.lon)!==point.from_lng||original.invalidated===true||original.confirmed===false||original.coordinates_valid===false||original.needs_confirmation===true))fail();
   return {...original,address:stops[i],lat:point.from_lat,lng:point.from_lng,input:point.pickup_input};
  });
 }
 let returnBody=null;
 if(itinerary.roundtrip===true||itinerary.return_enabled===true||itinerary.returnEnabled===true){
  const from=text(itinerary.return_from??itinerary.returnFrom)||text(itinerary.return_pickup_endpoint?.formatted_address)||text(body.to),to=text(itinerary.return_to??itinerary.returnTo)||text(itinerary.return_destination_endpoint?.formatted_address)||text(body.from);
  body.return_from=from;body.return_to=to;
  returnBody={from,to,stops:itinerary.return_stops??[],stop_coordinates:itinerary.return_stop_coordinates};
  // A reverse identity may be reused only for that exact canonical label.
  const fromEndpoint=itinerary.return_pickup_endpoint??(from===text(body.to)?itinerary.to_endpoint:null);
  const toEndpoint=itinerary.return_destination_endpoint??(to===text(body.from)?itinerary.from_endpoint:null);
  for(const [role,pairs]of [['from',[['return_from_lat','return_from_lng'],['return_pickup_lat','return_pickup_lng']]],['to',[['return_to_lat','return_to_lng'],['return_destination_lat','return_destination_lng']]]]) {
   for(const [lat,lng]of pairs)if(itinerary[lat]!=null||itinerary[lng]!=null){
    if(returnBody[role+'_lat']!=null&&(returnBody[role+'_lat']!==itinerary[lat]||returnBody[role+'_lng']!==itinerary[lng]))fail();
    returnBody[role+'_lat']=itinerary[lat];returnBody[role+'_lng']=itinerary[lng];
   }
  }
  endpoint(returnBody,'from',fromEndpoint);endpoint(returnBody,'to',toEndpoint);
  for(const role of ['from','to'])if(returnBody[role+'_lat']!=null){body['return_'+role+'_lat']=returnBody[role+'_lat'];body['return_'+role+'_lng']=returnBody[role+'_lng'];}
  if(returnBody.pickup_input)body.return_pickup_input=returnBody.pickup_input;
  if(returnBody.destination_input)body.return_destination_input=returnBody.destination_input;
 }
 return {body,returnBody};
}
export async function bindLimousineOwnedRouteV1({env,scope,itinerary,readStops,extraLocations=[]}){
 const {body,returnBody}=limousineOwnedJourneyBodiesV1(itinerary);
 const locations=nationalFinancialQuoteLocationsV1({body,returnBody,scope,maxStops:8,readStops:request=>request.stops??readStops(request)});
 // Old accepted snapshots legitimately contain only their sealed full label.
 // Resolve that exact official identity, not mutable request GPS or a nearby hit.
 for (let i=0;i<locations.length;i++) {
  const l=locations[i];
  if(!l.input?.official_address && (!Number.isFinite(l.lat)||!Number.isFinite(l.lng))) {
   locations[i]=await resolveLimousineOwnedBaseV1({env,label:l.label});
  }
 }
 const financialRequest=await bindNationalFinancialRequestV1({env,scope,maxStops:8,locations:[...locations,...extraLocations]});
 return {body,returnBody,financialRequest};
}

// Private operating-base text is selected only by complete exact official
// label (optionally without the country suffix), never the first ranked hit.
function completeOfficialLabels(candidate){
 const labels=[candidate.canonical_label],a=candidate.address;
 if(a&&typeof a==='object'){
  const names=candidate.names??candidate.provenance?.names;
  const streets=new Set([a.street,...Object.values(names?.street??{})].filter(s=>typeof s==='string'&&s.trim()));
  const cities=new Set([a.locality,a.municipality,...Object.values(names?.municipality??{})].filter(s=>typeof s==='string'&&s.trim()));
  const addition=a.houseNumberAddition?(/^[\s\-/]/.test(a.houseNumberAddition)?a.houseNumberAddition:'-'+a.houseNumberAddition):'';
  const number=[a.houseNumber,a.houseLetter].filter(Boolean).join('')+addition;
  if(a.houseNumber&&a.postcode&&['BE','NL'].includes(a.country))for(const street of streets)for(const city of cities){
   labels.push([street,number,a.boxNumber?'bus '+a.boxNumber:null].filter(Boolean).join(' ')+', '+[a.postcode,city,a.country].join(' '));
  }
 }
 return labels.filter(s=>typeof s==='string').flatMap(s=>[s,s.replace(/ (BE|NL)$/,'')]);
}
export async function resolveLimousineOwnedBaseV1({env,label,loadSearch=loadOfficialAddressTextIndexV1,loadIndex=operationalOfficialAddressIndexV1}){
 const search=await loadSearch(env);if(!search)fail();
 const result=await search.suggest({schema:ADDRESS_TEXT_V1,mode:'suggest',query:label,limit:6});
 const norm=s=>text(s).toLowerCase().replace(/,\s*(\d{4})\s*([a-z]{2})(?=\s|$)/,',$1$2');
 const matches=(result.candidates??[]).filter(c=>completeOfficialLabels(c).some(s=>norm(s)===norm(label)));
 if(result.ok!==true||result.complete!==true||matches.length!==1)fail();
 const index=await loadIndex(env);if(!index)fail();
 const r=await resolveOfficialAddressTextV1({index,request:{schema:ADDRESS_TEXT_V1,mode:'select',official_address:matches[0].official_address}}),c=r.candidate;
 if(r.ok!==true||c.source_status!=='current'||c.officially_assigned===false||c.position_status!=='official_source_position'||!c.position)fail();
 return {label,lat:c.position.latitude,lng:c.position.longitude,input:{kind:'address',official_address:c.official_address}};
}
