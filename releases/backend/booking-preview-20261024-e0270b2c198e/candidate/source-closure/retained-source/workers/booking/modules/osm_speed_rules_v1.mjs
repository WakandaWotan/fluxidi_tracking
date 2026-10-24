// OSM speed is an ETA input, never an access grant. No I/O or provider fallback.
export const OSM_SPEED_RULES_V1='osm-speed-rules-v1';
export function numericOsmSpeedV1(value){
 if(typeof value!=='string')return null;
 const m=/^(\d+(?:\.\d+)?)(?: (km\/h|kmh|mph))?$/.exec(value.trim());
 if(value==='walk')return 5;
 if(!m||Number(m[1])<=0)return null;
 return Math.min(130,Number(m[1])*(m[2]==='mph'?1.609344:1));
}
export function osmSpeedFloorV1(tags={},direction=1){
 const key=direction===1?'forward':'backward',fallback=tags.highway==='living_street'?15:30;
 const base=numericOsmSpeedV1(tags['maxspeed:'+key]??tags.maxspeed)??fallback;
 const limits=[base];
 for(const k of ['maxspeed:conditional','maxspeed:'+key+':conditional']){
  const text=tags[k];if(typeof text!=='string')continue;
  for(const clause of text.split(';')){const n=numericOsmSpeedV1(clause.split('@')[0].trim());if(n!==null)limits.push(n);}
 }
 return Math.min(...limits);
}
// Immutable weekly speed runs are built offline by the existing time helper.
// Runtime only intersects these runs with at most 25 UTC-hour slices. Splitting
// at real UTC hours retains both repeated autumn hours and skips spring gaps.
const formatter=new Intl.DateTimeFormat('en-GB',{timeZone:'Europe/Brussels',weekday:'short',hour:'2-digit',minute:'2-digit',hourCycle:'h23'});
const days=['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
function weekMinute(at){const p=Object.fromEntries(formatter.formatToParts(at).map(x=>[x.type,x.value]));return days.indexOf(p.weekday)*1440+Number(p.hour)*60+Number(p.minute);}
export function speedIntervalWindowsV1(from,through){
 if(!Number.isSafeInteger(from)||!Number.isSafeInteger(through)||through<from||through-from>86400000)throw Error('speed_interval_invalid');
 const result=[];
 for(let at=from;at<=through;){const end=Math.min(through,(Math.floor(at/3600000)+1)*3600000-1),a=weekMinute(at),b=weekMinute(end);if(b<a||b-a>60)throw Error('speed_timezone_interval_invalid');result.push([a,b+1]);if(end===through)break;at=end+1;}
 return result;
}
export function speedForWindowsV1(profile,direction,windows){
 const p=direction===1?profile.forward:profile.backward;
 if(profile.schema!==OSM_SPEED_RULES_V1||!p||!Array.isArray(p.runs))throw Error('speed_profile_invalid');
 let speed=Infinity;
 for(const [a,b] of windows)for(const [lo,hi,kph] of p.runs)if(lo<b&&hi>a)speed=Math.min(speed,kph);
 if(!Number.isFinite(speed)||speed<=0||speed<p.floorKph-1e-9)throw Error('speed_profile_invalid');
 return speed;
}
export function applyNationalSpeedTimeV1(route,departureAt){
 if(!route?.edges?.some(e=>e.speedProfile))return route;
 if(!Number.isSafeInteger(departureAt))return {...route,speedTimeEvidence:{mode:'ALL_TIME_CONSERVATIVE',reason:'departure_time_not_provided'}};
 const through=departureAt+Math.ceil(Math.max(route.staticSeconds*1.5,route.staticSeconds+180)*1000);
 // Longer-than-one-day journeys retain the all-time conservative floor. Never
 // silently use a departure snapshot beyond the supported interval contract.
 if(!Number.isSafeInteger(departureAt)||through-departureAt>86400000)return {...route,speedTimeEvidence:{mode:'ALL_TIME_CONSERVATIVE',reason:'interval_outside_weekly_binding'}};
 const windows=speedIntervalWindowsV1(departureAt,through),cache=new Map();
 const edges=route.edges.map(e=>{if(!e.speedProfile)return e;const key=e.speedProfileKey+':'+e.direction;let kph=cache.get(key);if(kph===undefined){kph=speedForWindowsV1(e.speedProfile,e.direction,windows);cache.set(key,kph);}const seconds=e.distanceMeters/(kph/3.6);if(seconds>e.seconds+1e-6)throw Error('speed_floor_not_conservative');return {...e,seconds};});
 return {...route,staticSeconds:edges.reduce((s,e)=>s+e.seconds,0),edges,speedTimeEvidence:{mode:'PRECOMPUTED_WEEKLY_INTERVAL',from:departureAt,through,profiles:cache.size,timezone:'Europe/Brussels/Europe/Amsterdam',traffic:'NOT_LIVE',routeChoice:'ALL_TIME_CONSERVATIVE_WEIGHTS'}};
}

export function validateOsmSpeedProfileV1(p){
 if(p?.schema!==OSM_SPEED_RULES_V1||!Array.isArray(p.unknownConditional)||p.unknownConditional.length>3)throw Error('speed_profile_invalid');
 for(const k of ['forward','backward']){const v=p[k];let next=0;if(!Number.isFinite(v?.floorKph)||v.floorKph<=0||v.floorKph>130||!Array.isArray(v.runs)||v.runs.length>2048)throw Error('speed_profile_invalid');for(const row of v.runs){if(!Array.isArray(row)||row.length!==3||row[0]!==next||!Number.isSafeInteger(row[1])||row[1]<=next||row[1]>10080||!Number.isFinite(row[2])||row[2]<v.floorKph||row[2]>130)throw Error('speed_profile_invalid');next=row[1];Object.freeze(row);}if(next!==10080)throw Error('speed_profile_invalid');Object.freeze(v.runs);Object.freeze(v);}
 Object.freeze(p.unknownConditional);return Object.freeze(p);
}
