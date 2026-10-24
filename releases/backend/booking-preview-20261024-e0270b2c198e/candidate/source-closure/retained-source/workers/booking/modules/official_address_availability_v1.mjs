import {officialAddressReferenceV1} from './official_address_reference_v1.mjs';
import {classifyAddressAccessFailureV1} from './address_access_errors_v1.mjs';
import {buildReliableJourneyV1} from './reliable_journey_v1.mjs';
import {mapboxAutomaticDispatchEnabledV1,bindConfiguredMapboxQuoteRequestV1,mapboxQuoteRequestV1} from './mapbox_quote_request_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {nationalFinancialQuoteLocationsV1,nationalFinancialReturnBodyV1} from './financial_national_quote_locations_v1.mjs';
import {admitBookingQuoteArea} from './booking_search_cost_guard.mjs';
import {readCompanyOperationDecision} from './company_operation_guard.mjs';
// Store only server-validated official reference inputs, not a transferable
// access capability. A future dispatch still re-reads the index and route.
export function officialAddressInputsFromJourneyV1(journey){
 const inputs={},input=p=>p?.official_address?{kind:'address',official_address:structuredClone(p.official_address)}:null;
 for(const [field,p]of [['pickup_input',journey.outbound?.pickup],['destination_input',journey.outbound?.destination],['return_pickup_input',journey.inbound?.pickup],['return_destination_input',journey.inbound?.destination]]){const r=input(p);if(r)inputs[field]=r;}
 for(const [field,names,leg]of [['stop_coordinates',journey.stops??[],'outbound'],['return_stop_coordinates',journey.returnStops??[],'return']]){
  const stops=names.map((address,index)=>{const point=journey.evidence.find(e=>e.leg===leg&&e.index===index)?.target;if(!point)throw Error('reliable_journey_stop_evidence_missing');return {address,lat:point.latitude,lng:point.longitude,...(input(point)?{input:input(point)}:{})};});
  if(stops.some(s=>s.input))inputs[field]=stops;
 }
 return inputs;
}
export async function prepareOfficialAddressAvailabilityV1({env,scope,params,departureAt,postBufferMinutes=15,stopMinutes=7,profile=null,proveCompanyRadius=null,observeRouteBranch=null}){
 const observeBranch=(branch,mode=null)=>{try{observeRouteBranch?.(branch,mode);}catch{/* Diagnostics cannot affect routing. */}};
 observeBranch('route_input_validation');
 const customerRoute=params.has('customer_route_provider');
 if(customerRoute&&(params.get('customer_route_provider')!=='mapbox_v1'||params.get('booking_mode')!=='provider_automatic'))throw Error('customer_route_provider_invalid');
 const inputs={};for(const field of ['pickup_input','destination_input','return_pickup_input','return_destination_input','stop_coordinates','return_stop_coordinates','stops','return_stops'])if(params.has(field)){const raw=params.get(field);if(raw.length>8192)throw Error('reliable_address_invalid');try{inputs[field]=JSON.parse(raw);}catch{throw Error('reliable_address_invalid');}}
 const official=[inputs.pickup_input,inputs.destination_input,inputs.return_pickup_input,inputs.return_destination_input,...(Array.isArray(inputs.stop_coordinates)?inputs.stop_coordinates.map(s=>s.input):[]),...(Array.isArray(inputs.return_stop_coordinates)?inputs.return_stop_coordinates.map(s=>s.input):[])].map(officialAddressReferenceV1).some(Boolean);
 if(!official&&params.get('booking_mode')!=='provider_automatic'){observeBranch('no_route_required');return null;}
 if(params.get('booking_mode')==='provider_automatic'){
  if(!mapboxAutomaticDispatchEnabledV1(env,scope)||!profile)throw Error('provider_dispatch_unavailable');
  // This is an entered preparation branch, not proof of provider network I/O.
  observeBranch(customerRoute?'customer_mapbox_preparation':'official_provider_preparation','provider_automatic');
  // A validated Customer provider intent binds the selected Mapbox/GPS point
  // directly. Legacy and white-label calls retain their official-index path.
  const index=customerRoute?null:await operationalOfficialAddressIndexV1(env);if(!customerRoute&&!index)throw Error('official_address_index_unavailable');
  const authority=index?createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true}):null;
  const label=async input=>{if(customerRoute){if(!['address','gps'].includes(input?.kind)||typeof input.label!=='string'||!input.label.trim()||input.label.length>500||/[\r\n\0]/.test(input.label))throw Error('reliable_address_invalid');return input.label.trim();}const ref=officialAddressReferenceV1(input);if(!ref){if(input?.official_address!=null||input?.kind!=='address'||typeof input.label!=='string'||!input.label.trim()||input.label.length>500||/[\r\n\0]/.test(input.label))throw Error('official_address_required');return input.label.trim();}const r=await authority.resolve(ref.id);return `${r.address.street} ${r.address.houseNumber}, ${r.address.postcode} ${r.address.municipality??r.address.locality}`;};
  const coordinate=key=>customerRoute&&(!params.has(key)||!params.get(key).trim())?NaN:Number(params.get(key));
  const body={...inputs,tenant_id:scope.tenant_id,company_id:scope.company_id,booking_mode:'provider_automatic',
    ...(customerRoute?{customer_route_provider:'mapbox_v1'}:{}),
    from:await label(inputs.pickup_input),to:await label(inputs.destination_input),
    from_lat:coordinate('pickup_lat'),from_lng:coordinate('pickup_lng'),to_lat:coordinate('dropoff_lat'),to_lng:coordinate('dropoff_lng'),
    pickup_mode:params.get('asap')==='true'?'asap':'scheduled',pickup_iso:new Date(departureAt).toISOString(),
    return_enabled:params.get('return_enabled')==='true',wait_min:Number(params.get('wait_min')??0),
    airport_direction:params.get('airport_direction')??undefined,
    airportDirection:params.get('airportDirection')??undefined,
    service:params.get('service')||'passenger',stops:inputs.stops??inputs.stop_coordinates?.map(s=>s.address)??[]};
  let returnBody=null;
  if(body.return_enabled){
    body.return_pickup_input=inputs.return_pickup_input??inputs.destination_input;body.return_destination_input=inputs.return_destination_input??inputs.pickup_input;
    body.return_from=await label(body.return_pickup_input);body.return_to=await label(body.return_destination_input);
    const reverse=!inputs.return_pickup_input&&!inputs.return_destination_input;
    const fromPoint=reverse?{lat:body.to_lat,lng:body.to_lng}:{lat:coordinate('return_from_lat'),lng:coordinate('return_from_lng')};
    const toPoint=reverse?{lat:body.from_lat,lng:body.from_lng}:{lat:coordinate('return_to_lat'),lng:coordinate('return_to_lng')};
    returnBody=nationalFinancialReturnBodyV1({body,from:body.return_from,to:body.return_to,points:{fromPoint,toPoint,reverseOfOutbound:reverse},stops:inputs.return_stops??inputs.return_stop_coordinates?.map(s=>s.address)??[]});
  }
  const readStops=b=>b.stops??[],locations=nationalFinancialQuoteLocationsV1({body,returnBody,scope,profile,
    includeDepot:!customerRoute&&env.COMPANY_MISSION_PRICING_ENABLED==='1'&&profile.mission_tariff?.enabled===true,readStops});
  const bound=await bindConfiguredMapboxQuoteRequestV1({env,scope,body,locations,...(customerRoute?{customerRoute:true}:{})}),api=mapboxQuoteRequestV1(bound,{scope,body});
  const area=await admitBookingQuoteArea({body,env:bound,scope,profile,companyDecision:await readCompanyOperationDecision(env,scope),
    readPoint:(b,role)=>({lat:b[role+'_lat'],lng:b[role+'_lng']}),proveMissionArea:args=>api.proveMissionArea({...args,readStops}),proveCompanyRadius});
  if(!area.ok){const denial=Error(area.error);denial.bookingAreaResult={status:area.status,error:area.error};throw denial;}
  const points=b=>[{lat:b.from_lat,lng:b.from_lng},...(b.stop_coordinates??[]).map(s=>({lat:s.lat,lng:s.lng})),{lat:b.to_lat,lng:b.to_lng}];
  const outbound=await api.directions(points(body)),inbound=returnBody?await api.directions(points(returnBody)):null;
  const handling=(body.stops.length*stopMinutes+postBufferMinutes),returnHandling=((returnBody?.stops?.length??0)*stopMinutes+postBufferMinutes);
  const returnAt=inbound?(params.get('return_pickup_iso')?Date.parse(params.get('return_pickup_iso')):departureAt+outbound.duration*1000+body.wait_min*60000):null;
  if(inbound&&(!Number.isFinite(returnAt)||returnAt<departureAt+outbound.duration*1000))throw Error('reliable_journey_return_before_outbound_end');
  return {context:null,pickup:{latitude:body.from_lat,longitude:body.from_lng},destination:{latitude:body.to_lat,longitude:body.to_lng},
    operationalDurationBoundSeconds:outbound.duration+handling*60,journey:{outbound:{routeSeconds:outbound.duration,handlingMinutes:handling},
      ...(inbound?{inbound:{routeMinutes:inbound.duration/60,handlingMinutes:returnHandling}}:{}),returnAt}};
 }
 observeBranch('official_regional_preparation');
 if(typeof env.__reliableRegionalRoutes!=='function')throw Error('address_index_unavailable');
 const number=key=>params.has(key)?Number(params.get(key)):undefined;
 const source={...inputs,pickup_lat:number('pickup_lat'),pickup_lng:number('pickup_lng'),dropoff_lat:number('dropoff_lat'),dropoff_lng:number('dropoff_lng'),pickup_iso:new Date(departureAt).toISOString(),return_enabled:params.get('return_enabled')==='true',return_pickup_iso:params.get('return_pickup_iso')||undefined,wait_min:number('wait_min')};
 for(const k of ['return_from_lat','return_from_lng','return_to_lat','return_to_lng'])if(params.has(k))source[k]=number(k);
 try{const router=await env.__reliableRegionalRoutes(scope);await router.resolveForJourney(source);
  const journey=await buildReliableJourneyV1({source,router,context:router.scope,now:Date.now(),stopNames:inputs.stops??inputs.stop_coordinates?.map(s=>s.address)??[],returnStopNames:inputs.return_stops??inputs.return_stop_coordinates?.map(s=>s.address)??[],postBufferMinutes,stopMinutes,manual:true});
  if(!journey.address_context||journey.address_context.valid_until_ms<=Date.now())throw Error('address_route_evidence_unavailable');
  return {context:journey.address_context,pickup:journey.outbound.pickup,destination:journey.outbound.destination,operationalDurationBoundSeconds:journey.outbound.routeSeconds+journey.outbound.handlingMinutes*60,journey};
 }catch(error){if(classifyAddressAccessFailureV1(error))throw error;throw Error('address_route_evidence_unavailable');}
}
