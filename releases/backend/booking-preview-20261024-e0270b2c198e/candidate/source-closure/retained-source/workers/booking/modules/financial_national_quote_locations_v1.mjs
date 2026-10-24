// Collect the existing quote/return/stops/depot contract for the owned request
// adapter. No geocoding, provider requests, prices, writes or inferred addresses.
const fail=r=>{throw Error(r);};
const text=v=>typeof v==='string'&&v.trim()&&v.length<=500;
function declaredStopText(value){
 if(text(value))return value.trim();
 if(value&&typeof value==='object'&&!Array.isArray(value)){
  const label=value.address??value.text??value.label??value.name??value.place;
  if(text(label))return label.trim();
 }
 fail('national_financial_stops_invalid');
}
// Build the return journey only after the existing return-contract resolver
// has established its endpoints. Never inherit outward coordinates or an
// outward official identity for a different return address.
export function nationalFinancialReturnBodyV1({body,from,to,points,stops,maxStops=6}){
 if(![6,8].includes(maxStops))fail('national_financial_stops_invalid');
 if(!text(from)||!text(to)||!points||!Array.isArray(stops))fail('national_financial_return_invalid');
 const result={...body,from,to,date:body.return_date??body.returnDate,time:body.return_time??body.returnTime,
  stop_points:stops,stops_addresses:stops,stop_addresses:stops,stops,waypoints:stops,
  stop_coordinates:body.return_stop_coordinates,wait_min:0};
 for(const key of ['from_lat','from_lng','from_lon','pickup_lat','pickup_lng','pickup_lon','to_lat','to_lng','to_lon','dropoff_lat','dropoff_lng','dropoff_lon','pickup_input','destination_input'])delete result[key];
 for(let i=1;i<=maxStops;i++){delete result['stop'+i];delete result['stop_'+i];}
 const declared=body.return_stops??body.returnStops;
 if(declared!=null){
  if(!Array.isArray(declared)||declared.length>maxStops)fail('national_financial_stops_invalid');
  const labels=declared.map(declaredStopText);
  if(JSON.stringify(labels)!==JSON.stringify(stops))fail('national_financial_stops_invalid');
 }
 for(const [role,field,outwardField]of [['from','return_pickup_input','destination_input'],['to','return_destination_input','pickup_input']]){
  const point=role==='from'?points.fromPoint:points.toPoint;
  const aliases=role==='from'
   ? [['return_from_lat','return_from_lng','return_from_lon'],['returnFromLat','returnFromLng','returnFromLon'],['return_pickup_lat','return_pickup_lng'],['returnPickupLat','returnPickupLng']]
   : [['return_to_lat','return_to_lng','return_to_lon'],['returnToLat','returnToLng','returnToLon'],['return_destination_lat','return_destination_lng'],['returnDestinationLat','returnDestinationLng']];
  for(const [latKey,lngKey,lonKey]of aliases){
   const lat=body[latKey],lng=body[lngKey]??(lonKey?body[lonKey]:null);
   if(lat==null&&lng==null)continue;
   if(typeof lat!=='number'||typeof lng!=='number'||!Number.isFinite(lat)||!Number.isFinite(lng)||Math.abs(lat)>90||Math.abs(lng)>180||!point||lat!==point.lat||lng!==point.lng||lonKey&&body[lngKey]!=null&&body[lonKey]!=null&&body[lngKey]!==body[lonKey])fail('national_financial_coordinate_binding');
  }
  if(point){result[role+'_lat']=point.lat;result[role+'_lng']=point.lng;}
  const input=body[field]??(points.reverseOfOutbound===true?body[outwardField]:null);
  if(input)result[role==='from'?'pickup_input':'destination_input']=input;
 }
 return result;
}
function point(body,role){
 const pairs=role==='from'?[['from_lat','from_lng'],['pickup_lat','pickup_lng']]:[['to_lat','to_lng'],['dropoff_lat','dropoff_lng']];
 const points=[];
 for(const [a,b]of pairs){
  const lng=body[b]??body[b.replace(/_lng$/,'_lon')],lat=body[a];
  if(lat==null&&lng==null)continue;
  if(typeof lat!=='number'||!Number.isFinite(lat)||Math.abs(lat)>90||typeof lng!=='number'||!Number.isFinite(lng)||Math.abs(lng)>180)fail('national_financial_coordinate_binding');
  if(body[b]!=null&&body[b.replace(/_lng$/,'_lon')]!=null&&body[b]!==body[b.replace(/_lng$/,'_lon')])fail('national_financial_coordinate_binding');
  points.push({lat,lng});
 }
 if(points.some(p=>p.lat!==points[0].lat||p.lng!==points[0].lng))fail('national_financial_coordinate_binding');
 return points[0]??{};
}
export function nationalFinancialQuoteLocationsV1({body,returnBody=null,profile,scope,includeDepot=false,readStops,maxStops=6}){
 if(![6,8].includes(maxStops))fail('national_financial_stops_invalid');
 if(!body||typeof readStops!=='function'||!scope?.tenant_id||!scope?.company_id)fail('national_financial_scope_required');
 const locations=[];
 function journey(request){
  const declared=request.stop_points??request.stops_addresses??request.stop_addresses??request.stops??request.waypoints;
  if(declared!=null&&(!Array.isArray(declared)||declared.length>maxStops||declared.some(s=>!text(s))))fail('national_financial_stops_invalid');
  for(const [role,field]of [['from','pickup_input'],['to','destination_input']]){
   if(!text(request[role]))fail('national_financial_address_required');
   locations.push({label:request[role],...point(request,role),...(request[field]?{input:request[field]}:{}),...(request.country_code??request.country?{country:request.country_code??request.country}:{})});
  }
  const stops=readStops(request),stored=request.stop_coordinates??[];
  if(!Array.isArray(stops)||stops.length>maxStops||!Array.isArray(stored)||stored.length>stops.length)fail('national_financial_stops_invalid');
  for(const [i,label]of stops.entries()){
   if(!text(label))fail('national_financial_stops_invalid');const s=stored[i];
   if(s!=null&&(!s||typeof s!=='object'||Array.isArray(s)||s.address!==label||s.invalidated===true||s.confirmed===false||s.coordinates_valid===false||s.coordinate_valid===false||s.needs_confirmation===true||s.needs_address_confirmation===true))fail('national_financial_stop_binding');
   locations.push({label,...(s?point({from_lat:s.lat,from_lng:s.lng??s.lon},'from'):{}),...(s?.input?{input:s.input}:{})});
  }
 }
 journey(body);if(returnBody)journey(returnBody);
 if(includeDepot){
  const depot=profile?.mission_tariff?.depot,binding=profile?.depot_access;
  if(profile?.mission_tariff?.enabled!==true||!depot)fail('configured_site_binding_unproven');
  if(binding){
   if(binding.tenant_id!==scope.tenant_id||binding.company_id!==scope.company_id||binding.configuredPoint?.latitude!==depot.lat||binding.configuredPoint?.longitude!==depot.lng)fail('configured_site_binding_unproven');
   locations.push({label:text(depot.label)?depot.label:'Bedrijfsdepot',lat:depot.lat,lng:depot.lng,configuredSiteBinding:binding});
  }else{
   // Existing numbered/official company depots keep their normal address path.
   // The request adapter, not a nonempty display label, proves their access.
   if(!text(depot.label)&&!depot.input?.official_address)fail('configured_site_binding_unproven');
   locations.push({label:text(depot.label)?depot.label:'Bedrijfsdepot',lat:depot.lat,lng:depot.lng,...(depot.input?{input:depot.input}:{})});
  }
 }
 if(locations.length>4+2*maxStops+1)fail('national_financial_locations_invalid');
 return locations;
}
