import {createNationalFinancialRouteAdapterV1} from './financial_national_route_adapter_v1.mjs';
import {publicAddressPointV1,foldStreetV1} from './practical_frontage_v1.mjs';
import {projectAccessV1} from './national_road_access_v1.mjs';
import {createConfiguredSiteReferenceV1,readConfiguredSiteReferenceV1} from './configured_site_access_v1.mjs';
import {financialOwnedDirectionsInBatchV1} from './financial_route_batch_v1.mjs';

const fail=reason=>{throw Error(reason);};
const coordinates=p=>({lat:p.latitude,lng:p.longitude});
const same=(a,b)=>a?.lat===b?.lat&&a?.lng===b?.lng;
const label=s=>String(s??'').normalize('NFC').trim().replace(/\s+/g,' ');
const requests=new WeakMap();
// Internal capability: JSON or a copied object cannot enable a financial
// provider. Existing quote/mission code can inspect only a factory instance.
export function nationalFinancialRequestInfoV1(request){const info=requests.get(request);return info?structuredClone(info):null;}

// One authenticated quote/request owns this lookup. Coordinates never acquire
// access merely by being near a registered address, and text never invokes a
// provider or silently substitutes a different house number.
export async function createNationalFinancialRequestV1({scope,policy,router,locations,resolveMunicipality,clock=Date.now,reuseContext=null,maxStops=6}){
 // Existing service limits: four endpoints, six taxi/eight limousine stops per direction,
 // and one company depot. The bound must not drop the final declared location.
 if(![6,8].includes(maxStops))fail('national_financial_stops_invalid');
 const maxLocations=4+2*maxStops+1;
 if(!Array.isArray(locations)||locations.length<2||locations.length>maxLocations)fail('national_financial_locations_invalid');
 const registered=[];
 for(const location of locations){
  if(!location||!label(location.label))fail('national_financial_address_required');
  if(location.configuredSiteBinding){
   const point=createConfiguredSiteReferenceV1({point:{latitude:location.lat,longitude:location.lng},binding:location.configuredSiteBinding,scope});
   registered.push({label:label(location.label),point});continue;
  }
  const raw=publicAddressPointV1({from:location.label,from_lat:location.lat,from_lng:location.lng,
   ...(location.input?{pickup_input:location.input}:{}),...(location.country?{country:location.country}:{})});
  if(raw.access?.kind==='gps')fail('national_financial_gps_not_address');
  const point=raw.official_address?await router.resolveAddressPoint(raw):raw;
  if(!point.official_address&&!point.address)fail('national_financial_address_required');
  // A stale position bound to an official identity must not be silently repaired.
  if(raw.official_address&&(location.lat!=null||location.lng!=null)&&
    (!Number.isFinite(location.lat)||!Number.isFinite(location.lng)||
      projectAccessV1(point,{latitude:location.lat,longitude:location.lng},{latitude:location.lat,longitude:location.lng}).meters>1))fail('address_source_position_changed');
  registered.push({label:label(location.label),point});
 }
 const [origin,destination,...extra]=registered.map(r=>r.point);
 await router.resolveForJourney({pickup_lat:origin.latitude,pickup_lng:origin.longitude,
  dropoff_lat:destination.latitude,dropoff_lng:destination.longitude,
  stop_coordinates:extra.map(coordinates)});
 const sealedPolicy=structuredClone(policy),resolve=createNationalFinancialRouteAdapterV1({scope,policy:sealedPolicy,router,clock});
 function findPoint(p){
  if(!p||!Number.isFinite(p.lat)||!Number.isFinite(p.lng))fail('national_financial_location_unbound');
  const matches=registered.filter(r=>same(coordinates(r.point),p));
  if(!matches.length)fail('national_financial_location_unbound');
  // Prefer an official identity when a configured depot is the same point.
  const official=matches.filter(r=>r.point.official_address);
  if(new Set(official.map(r=>JSON.stringify(r.point.official_address))).size>1)fail('national_financial_location_ambiguous');
  if(!official.length&&new Set(matches.map(r=>JSON.stringify(readConfiguredSiteReferenceV1(r.point,{scope})??[foldStreetV1(r.point.address?.street),foldStreetV1(r.point.address?.houseNumber)]))).size>1)fail('national_financial_location_ambiguous');
  return (official[0]??matches[0]).point;
 }
 const api={
  async geocode(text){
   const matches=registered.filter(r=>r.label===label(text));
   if(!matches.length||new Set(matches.map(r=>JSON.stringify(coordinates(r.point)))).size!==1)fail('national_financial_text_unbound');
   return coordinates(matches[0].point);
  },
  async directions(points){
   const selected=points.map(findPoint),identities=selected.map(p=>readConfiguredSiteReferenceV1(p,{scope})??p.official_address??p.address);
   const result=await financialOwnedDirectionsInBatchV1({context:reuseContext,scope,policy:sealedPolicy,coords:points,identities,clock,resolve:()=>resolve(selected)});
   return {...result.route,_financial_route:result.financial_route};
  },
  async municipality(points){
   // Municipality affects local tariff minimums. Customer label text is not
   // independent jurisdiction evidence, even after frontage is routeable.
   if(typeof resolveMunicipality!=='function')fail('national_financial_municipality_unproven');
   return Promise.all(points.map(async p=>{
    const city=await resolveMunicipality(findPoint(p));
    if(typeof city!=='string'||!city.trim()||city.length>160)fail('national_financial_municipality_unproven');
    return city;
   }));
  },
  async itinerary({fromText,toText,fromPoint=null,toPoint=null,stopsTexts=[],stopCoordinates=[]}){
   if(!Array.isArray(stopsTexts)||stopsTexts.length>maxStops||!Array.isArray(stopCoordinates)||stopCoordinates.length>stopsTexts.length)fail('national_financial_stops_invalid');
   const from=await api.geocode(fromText),to=await api.geocode(toText),stops=[];
   if(fromPoint&&!same(from,fromPoint)||toPoint&&!same(to,toPoint))fail('national_financial_endpoint_binding');
   for(const [i,text]of stopsTexts.entries()){
    if(typeof text!=='string'||!label(text))fail('national_financial_stops_invalid');
    const stored=stopCoordinates[i];
    // An invalid or changed stored stop is not dropped or silently repaired.
    if(stored!=null&&(!stored||typeof stored!=='object'||stored.address!==text||stored.invalidated===true||stored.confirmed===false||stored.needs_confirmation===true
      ||stored.coordinates_valid===false||stored.coordinate_valid===false||stored.needs_address_confirmation===true
      ||!Number.isFinite(stored.lat)||!Number.isFinite(stored.lng??stored.lon)))fail('national_financial_stop_binding');
    const point=await api.geocode(text);
    if(stored&&!same(point,{lat:stored.lat,lng:stored.lng??stored.lon}))fail('national_financial_stop_binding');
    stops.push(point);
   }
   const coords=[from,...stops,to],route=await api.directions(coords),waypointNames=[label(fromText),...stopsTexts.map(label),label(toText)];
   if(route.legs.length!==coords.length-1)fail('national_financial_route_incomplete');
   return {route,waypointNames,financial_route:route._financial_route,
    legs:route.legs.map((l,i)=>({index:i+1,from:waypointNames[i],to:waypointNames[i+1],distance_km:Math.round(l.distance/100)/10,duration_min:Math.round(l.duration/60)})),
    resolved_from_point:{...from},resolved_to_point:{...to},fromSource:fromPoint?'coordinates':'text',toSource:toPoint?'coordinates':'text'};
  },
 };
 requests.set(api,{scope:structuredClone(scope),policy:structuredClone(sealedPolicy)});
 return Object.freeze(api);
}
