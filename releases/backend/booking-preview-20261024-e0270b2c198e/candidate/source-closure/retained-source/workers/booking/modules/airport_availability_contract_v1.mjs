import {normalizeServiceKind} from './vehicle_service_capacity.mjs';

const finite=n=>typeof n==='number'&&Number.isFinite(n);
const limit=8*24*60;
const error=reason=>({ok:false,error:reason,status:400});
function coordinate(params,key,max){const raw=params.get(key);if(raw==null||!raw.trim())return null;const n=Number(raw);return Number.isFinite(n)&&Math.abs(n)<=max?n:null;}
function minutes(params,names,{optional=false}={}){
 const name=names.find(n=>params.has(n));if(!name)return optional?0:null;
 const raw=params.get(name);if(!raw?.trim())return null;
 const n=Number(raw);return Number.isFinite(n)&&n>=0&&n<=limit?n:null;
}
// Null means the untouched ordinary taxi contract. No duration is invented for
// airport offers. These are advisory inputs; booking confirmation remains the
// canonical quote/reservation authority and must revalidate the mission.
export function parseAirportAvailabilityV1(params,nowMs=Date.now()){
 if(normalizeServiceKind(params.get('service'))!=='airport')return null;
 const asap=params.get('asap')==='true',pickupMs=asap?nowMs+1000:Date.parse(params.get('pickup_iso')??params.get('pickupIso')??'');
 if(!Number.isFinite(pickupMs)||pickupMs<=nowMs)return error('airport_pickup_time_required');
 const durationMin=minutes(params,['duration_min','durationMin']);
 const waitMin=minutes(params,['wait_min','waitMin'],{optional:true}),returnDurationMin=minutes(params,['return_duration_min','returnDurationMin'],{optional:true});
 if(durationMin==null||durationMin<=0)return error('airport_duration_required');
 if(waitMin==null||returnDurationMin==null||durationMin+waitMin+returnDurationMin>limit)return error('airport_mission_duration_invalid');
 const pickupLat=coordinate(params,'pickup_lat',90),pickupLng=coordinate(params,'pickup_lng',180),dropoffLat=coordinate(params,'dropoff_lat',90),dropoffLng=coordinate(params,'dropoff_lng',180);
 return {ok:true,service:'airport',asap,pickupMs,durationMin,waitMin,returnDurationMin,missionMinutes:durationMin+waitMin+returnDurationMin,
  hasRouteCoordinates:pickupLat!=null&&pickupLng!=null&&dropoffLat!=null&&dropoffLng!=null&&!(pickupLat===0&&pickupLng===0)&&!(dropoffLat===0&&dropoffLng===0)};
}

// Reuse the successful existing Smart feasibility result; never run a second
// route calculation or turn an unavailable route into a guessed approach.
export function airportDutyWindowV1(input,feasibility,pickupMs,vehicleId){
 const candidate=feasibility?.next_vehicle_candidate;
 const invalid=()=>({ok:false,error:'airport_approach_window_unavailable'});
 if(input?.ok!==true||feasibility?.would_allow_booking!==true||!candidate||candidate.vehicle_id!==vehicleId||!finite(pickupMs))return invalid();
 const travel=candidate.origin_travel_seconds,buffer=candidate.required_buffer_seconds,required=candidate.required_seconds;
 if(!finite(travel)||travel<0||!finite(buffer)||buffer<0||!finite(required)||required<travel+buffer||required>limit*60)return invalid();
 const startMs=pickupMs-required*1000,endMs=pickupMs+input.missionMinutes*60000,durationMin=(endMs-startMs)/60000;
 if(!finite(startMs)||!finite(endMs)||startMs<0||durationMin<=0||durationMin>limit)return invalid();
 return {ok:true,startMs,endMs,durationMin,approachSeconds:travel,preparationSeconds:buffer};
}

export function airportOverrideCoversWindowV1(driver,window){
 const raw=driver?.manual_override??driver?.manualOverride;
 const kind=String(raw?.kind??raw?.type??raw?.status??'').trim().toLowerCase();
 const until=Date.parse(raw?.until??raw?.until_iso??raw?.untilIso??'');
 return window?.ok===true&&kind==='active'&&Number.isFinite(until)&&until>=window.endMs;
}
