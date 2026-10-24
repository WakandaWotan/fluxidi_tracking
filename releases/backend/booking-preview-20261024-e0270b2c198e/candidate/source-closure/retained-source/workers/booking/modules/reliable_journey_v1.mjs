import {publicAddressPointV1} from './practical_frontage_v1.mjs';
import {reliableRouteQualityV1} from './product_estimated_eta_v1.mjs';
const point=p=>{const latitude=Number(p?.latitude??p?.lat),longitude=Number(p?.longitude??p?.lng??p?.lon);if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||Math.abs(latitude)>90||Math.abs(longitude)>180||latitude===0&&longitude===0)throw Error('reliable_journey_point_unknown');return {latitude,longitude,...(p?.access?{access:structuredClone(p.access)}:{}),...(p?.address?{address:structuredClone(p.address)}:{})};};
export function reliableStopPointsV1(names,coordinates){
 if(!Array.isArray(names)||names.length>6)throw Error('reliable_journey_stops_invalid');
 if(!names.length){if(coordinates?.length)throw Error('reliable_journey_stop_binding');return [];}
 if(!Array.isArray(coordinates)||coordinates.length!==names.length)throw Error('reliable_journey_stop_binding');
 return names.map((name,i)=>{if(typeof name!=='string'||coordinates[i]?.address!==name)throw Error('reliable_journey_stop_binding');return publicAddressPointV1({...coordinates[i],from:coordinates[i].address,pickup_lat:coordinates[i].lat??coordinates[i].latitude,pickup_lng:coordinates[i].lng??coordinates[i].longitude,pickup_input:coordinates[i].input});});
}
// This is the existing itinerary's local proof. It is independent of financial
// quote distance/time and never updates prices, accepted quote or payment data.
export async function buildReliableJourneyV1({source,router,context,now,stopNames=[],returnStopNames=[],postBufferMinutes=15,stopMinutes=7,manual=false}){
 const resolve=async p=>{if(p?.official_address&&typeof router.resolveAddressPoint!=='function')throw Error('address_index_unavailable');return router.resolveAddressPoint?router.resolveAddressPoint(p):p;};
 const pickup=await resolve(publicAddressPointV1(source)),destination=await resolve(publicAddressPointV1(source,{label:'to',latitude:'dropoff_lat',longitude:'dropoff_lng',latAlias:'to_lat',lngAlias:'to_lng',inputField:'destination_input'}));
 const stops=await Promise.all(reliableStopPointsV1(stopNames,source.stop_coordinates).map(resolve)),hasReturn=source.return_enabled===true||source.return===true;
 const wait=Math.max(0,Number(source.wait_min)||0),rawReturn=source.return_pickup_iso??source.returnPickupIso;
 let returnAt=rawReturn?Date.parse(rawReturn):null;
 if(hasReturn&&rawReturn&&!Number.isFinite(returnAt))throw Error('reliable_return_time_invalid');
 // Existing customer wait quotes use the outbound pickup as a placeholder;
 // an explicit waiting duration owns the return window in that contract.
 const pickupAt=Date.parse(source.pickup_iso??source.pickupIso);
 if(wait>0&&Number.isFinite(returnAt)&&Number.isFinite(pickupAt)&&Math.abs(returnAt-pickupAt)<=15000)returnAt=null;
 const mode=hasReturn?(wait>0?'continuous_wait':Number.isFinite(returnAt)?'split_no_wait':'continuous_wait'):'single';
 const returning=hasReturn?{pickup:source.return_pickup_input?.official_address!==undefined||source.return_from_lat!=null||source.return_pickup_lat!=null?publicAddressPointV1(source,{label:'return_from',latitude:'return_pickup_lat',longitude:'return_pickup_lng',latAlias:'return_from_lat',lngAlias:'return_from_lng',inputField:'return_pickup_input'}):source.return_from&&source.return_from!==source.to?(()=>{throw Error('reliable_return_origin_unknown');})():destination,
  destination:source.return_destination_input?.official_address!==undefined||source.return_to_lat!=null||source.return_dropoff_lat!=null?publicAddressPointV1(source,{label:'return_to',latitude:'return_dropoff_lat',longitude:'return_dropoff_lng',latAlias:'return_to_lat',lngAlias:'return_to_lng',inputField:'return_destination_input'}):source.return_to&&source.return_to!==source.from?(()=>{throw Error('reliable_return_destination_unknown');})():pickup,
  stops:reliableStopPointsV1(returnStopNames,source.return_stop_coordinates)}:null;
 if(returning){returning.pickup=await resolve(returning.pickup);returning.destination=await resolve(returning.destination);returning.stops=await Promise.all(returning.stops.map(resolve));}
 const evidence=[],compute=async(origin,target,leg,index,planned=false)=>{
  const plannedDeparture=planned&&Number.isFinite(returnAt)?returnAt:Number.isFinite(pickupAt)?pickupAt:now;
  const r=(manual||planned)&&router.planRoute?await router.planRoute({scope:context,origin,destination:target,departureAt:plannedDeparture}):await router.route({scope:context,origin,destination:target,departureAt:now});
  if(r.graphVersion!==context.graphVersion||r.evidenceRevision!==context.evidenceRevision||r.validUntil<=now||(!r.planningOnly&&!reliableRouteQualityV1(r)))throw Error('reliable_journey_route_unknown');
  const upper=r.planningOnly?r.operationalDurationBoundSeconds:r.seconds+r.quality.errorSeconds;
  if(!Number.isFinite(upper)||upper<0||!Number.isFinite(r.distanceMeters)||r.distanceMeters<0)throw Error('reliable_journey_route_unknown');
  evidence.push({leg,index,origin,target,evidenceId:r.evidenceId,graphVersion:r.graphVersion,evidenceRevision:r.evidenceRevision,distanceMeters:r.distanceMeters,upperSeconds:upper,planningOnly:r.planningOnly===true,...(r.addressContext?{addressContext:r.addressContext}:{})});return upper;
 };
 const leg=async(origin,targets,type,planned)=>{let seconds=0,current=origin;for(let i=0;i<targets.length;i++){seconds+=await compute(current,targets[i],type,i,planned);current=targets[i];}return {pickup:origin,destination:current,routeSeconds:seconds,routeMinutes:Math.max(1,Math.ceil(seconds/60)),handlingMinutes:(targets.length-1)*stopMinutes,distanceMeters:evidence.filter(r=>r.leg===type).reduce((n,r)=>n+r.distanceMeters,0)};};
 const outbound=await leg(pickup,[...stops,destination],'outbound',false),inbound=returning?await leg(returning.pickup,[...returning.stops,returning.destination],'return',true):null;
 const outMinutes=outbound.routeMinutes+outbound.handlingMinutes+(mode==='single'?wait:0),retMinutes=inbound?inbound.routeMinutes+inbound.handlingMinutes+postBufferMinutes:0;
 const serviceStart=Number.isFinite(pickupAt)?pickupAt:now;
 if(mode==='split_no_wait'&&returnAt<serviceStart+(outMinutes+10)*60000)throw Error('reliable_return_before_outbound_end');
 if(mode==='continuous_wait'&&returnAt&&returnAt<serviceStart+outMinutes*60000)throw Error('reliable_return_before_outbound_end');
 const serviceMinutes=mode==='continuous_wait'?(returnAt?Math.ceil((returnAt-serviceStart)/60000):outMinutes+wait)+retMinutes:outMinutes+postBufferMinutes;
 const addressContexts=evidence.filter(e=>e.addressContext).map(e=>[e.leg,e.index,e.addressContext]);let address_context=null;
 if(addressContexts.length){const revisions=[...new Set(addressContexts.map(e=>e[2].index_revision))];if(revisions.length!==1)throw Error('address_index_changed');const bytes=new TextEncoder().encode(JSON.stringify([context.tenant_id,context.company_id,context.graphVersion,addressContexts.map(e=>[e[0],e[1],e[2].id])]));const id=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');address_context={schema:'fluxidi-address-route-context-v1',id,index_revision:revisions[0],graph_version:context.graphVersion,valid_until_ms:Math.min(now+15000,...addressContexts.map(e=>e[2].valid_until_ms)),status:'routeable'};}
 return {schema:'fluxidi-reliable-journey-v1',...context,mode,outbound,inbound,returnAt,waitMinutes:wait,serviceMinutes,outboundMinutes:outMinutes+(mode==='split_no_wait'?postBufferMinutes:0),returnMinutes:retMinutes,postBufferMinutes,stops:stopNames,returnStops:returnStopNames,evidence,totalDistanceMeters:evidence.reduce((n,r)=>n+r.distanceMeters,0),validUntil:now+15000,manualPlanning:manual,...(address_context?{address_context}:{})};
}
export function stampReliableJourneyReservationV1(record,journey){
 if(!journey||journey.graphVersion!==record.p12_reliable_choice?.graph_version&&record.p12_reliable_choice?.graph_version)throw Error('reliable_journey_graph_changed');
 record.p22_journey=structuredClone(journey);
 record.p22_occupancy_duration_min=Math.max(Number(record.p22_occupancy_duration_min)||0,journey.mode==='continuous_wait'?journey.outboundMinutes:journey.serviceMinutes);
 record.p22_return_occupancy_min=Math.max(Number(record.p22_return_occupancy_min)||0,journey.returnMinutes);
 for(const rows of [record.operational_legs,record.booking?.operational_legs])for(const leg of rows??[]){const minutes=leg.leg_type==='return'?journey.returnMinutes:journey.outboundMinutes;leg.p22_occupancy_duration_min=Math.max(Number(leg.p22_occupancy_duration_min)||0,minutes);const type=leg.leg_type==='return'?'return':'outbound',names=type==='return'?journey.returnStops:journey.stops;leg.stops=[...names];leg.stop_coordinates=names.map((address,index)=>{const e=journey.evidence.find(e=>e.leg===type&&e.index===index);if(!e)throw Error('reliable_journey_stop_evidence_missing');return {address,lat:e.target.latitude,lng:e.target.longitude};});}
 return record;
}

export function reliableReturnInfoV1(record){
 const booking=record.booking??{},context=record.p12_reliable_choice?.request_context??{},journey=record.p22_journey??record.p12_reliable_choice?.journey;
 const enabled=record.return_enabled===true||booking.return_enabled===true||context.return_enabled===true;
 const leg=(record.operational_legs??booking.operational_legs??[]).find(l=>l.leg_type==='return');
 let clock=record.return_pickup_iso??booking.return_pickup_iso??context.return_pickup_iso??leg?.pickup_iso??null,estimated=false;
 if(!clock&&enabled&&journey?.mode==='continuous_wait'){
  const pickup=Date.parse(record.pickup_iso??booking.pickup_iso),minutes=journey.outbound.routeMinutes+journey.outbound.handlingMinutes+journey.waitMinutes;
  if(Number.isFinite(pickup)&&Number.isFinite(minutes)){clock=new Date(pickup+minutes*60000).toISOString();estimated=true;}
 }
 return {enabled,mode:journey?.mode??record.roundtrip_dispatch_mode??null,pickup_time:clock,estimated,wait_minutes:journey?.waitMinutes??record.wait_min??booking.wait_min??0,
  pickup:String(record.return_from??booking.return_from??context.return_from??booking.to??'').slice(0,500),destination:String(record.return_to??booking.return_to??context.return_to??booking.from??'').slice(0,500),stops:(context.return_stops??record.return_stops??booking.return_stops??[]).filter(v=>typeof v==='string').slice(0,6)};
}
