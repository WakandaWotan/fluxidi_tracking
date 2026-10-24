import {osmSpeedFloorV1} from './osm_speed_rules_v1.mjs';
// Shared offline import admission. It does not fetch data or establish an
// address entrance. The caller owns the vehicle class and terminal evidence.
export const OSM_VEHICLE_ACCESS_V1='osm-vehicle-access-v1';
const classes=new Set(['motorway','motorway_link','trunk','trunk_link','primary','primary_link','secondary','secondary_link','tertiary','tertiary_link','unclassified','residential','living_street','service']);
const nonCarModes=new Set(['hgv','hgv_articulated','goods','bus','school_bus','tourist_bus','motorcycle','moped','mofa','bicycle','speed_pedelec','foot','horse','agricultural','forestry','emergency','police','garbage_truck','tram']);
const numerical=s=>typeof s==='string'&&/^\d+(?:\.\d+)?$/.test(s)&&Number(s)>0;
// OSM dimensions use metres/tonnes by default. Explicit metric units are
// equivalent; unknown textual values never become an unlimited permission.
const bound=(key,s)=>typeof s==='string'&&new RegExp('^\\d+(?:\\.\\d+)?(?: '+(key==='maxweight'?'t':'m')+')?$').test(s)&&parseFloat(s)>0?parseFloat(s):null;
const modes=['motorcar','motor_vehicle','vehicle','access'];
const legal=v=>['yes','permissive','designated'].includes(v);
function directionAccess(t,direction,{destinationEndpoint=false}={}){
 const permitted=v=>legal(v)||destinationEndpoint&&v==='destination';
 const arrays=modes.map(mode=>t[mode+':lanes:'+direction]??t[mode+':lanes']).filter(v=>v!=null).map(v=>String(v).split('|'));
 if(arrays.some(a=>a.length!==arrays[0].length))return null;
 const count=arrays[0]?.length??1;
 const lane=(index,level=0)=>{
  if(level===modes.length)return true;
  const mode=modes[level],value=t[mode+':lanes:'+direction]??t[mode+':lanes'];
  const explicit=value==null?'':String(value).split('|')[index].trim();
  if(explicit)return permitted(explicit);
  const parent=t[mode+':'+direction]??t[mode];
  return parent!=null?permitted(parent):lane(index,level+1);
 };
 return Array.from({length:count},(_,i)=>lane(i)).some(Boolean);
}
export function irrelevantToPassengerCarV1(key,vehicleClass='passenger_car') {
 if(vehicleClass!=='passenger_car')return false;
 // A mode before the final conditional suffix is relevant; malformed
 // nested suffixes must not accidentally become permissions.
 if(key.includes(':conditional')&&!key.endsWith(':conditional'))return false;
 return key.split(':').some(k=>nonCarModes.has(k));
}
export function evaluateOsmWayAccessV1(tags,profile={}, {terminal=false,countryCode=profile.countryCode??null}={}) {
 const t=tags??{},vehicleClass=profile.vehicleClass??'passenger_car';
 const dimensions={maxheight:profile.heightMeters??null,maxwidth:profile.widthMeters??null,maxweight:profile.massTonnes??null,maxlength:profile.lengthMeters??null};
 const result={schema:OSM_VEHICLE_ACCESS_V1,vehicleClass,ordinaryDimensions:{},conditionalRules:[],ignoredForClass:[],destinationOnly:false,forwardAllowed:true,backwardAllowed:true,effectiveOneway:null,speedKph:null,reason:null};
 const deny=reason=>({...result,reason});
 // OSM maxheight=default proves the country's ordinary legal clearance,
 // not unlimited height. BE/NL share a 4m general limit. Country must come
 // from trusted source metadata; unknown countries and physical text deny.
 const dimensionBound=(key,value)=>key==='maxheight'&&value==='default'&&['BE','NL','BE_NL'].includes(countryCode)?4:bound(key,value);
 if(vehicleClass!=='passenger_car')return deny('vehicle_class_unproven');
 if(!classes.has(t.highway))return deny('non_car_road');
 const exceptions=new Set(),conditionalKeys=Object.keys(t).filter(k=>k.includes(':conditional'));
 let speed=/^\d+(?:\.\d+)?$/.test(t.maxspeed??'')?Math.min(130,Number(t.maxspeed)):t.highway==='living_street'?15:30;
 for(const k of conditionalKeys){
  result.conditionalRules.push({key:k,value:t[k]});
  if(irrelevantToPassengerCarV1(k,vehicleClass)){
   result.ignoredForClass.push(k);continue;
  }
  const base=k.replace(/:conditional$/,'');
  // Speed uncertainty cannot revoke road access. Preserve rules for the
  // separately precomputed speed model; unrelated conditional access still denies.
  if(/^maxspeed(?::(?:forward|backward))?:conditional$/.test(k))continue;
  if(k!==base+':conditional'||!Object.hasOwn(dimensions,base)||t[k]!=='none @ destination'||![base,base+':forward',base+':backward'].some(bound=>numerical(t[bound])))return deny('conditional_unproven');
  exceptions.add(base);
  if(t[base]&&!Number.isFinite(dimensions[base])&&!terminal)return deny('conditional_unproven');
 }
 const accessKey=['motorcar','motor_vehicle','vehicle','access'].find(k=>t[k]);
 if(accessKey&&!['yes','permissive','designated'].includes(t[accessKey])){
  if(t[accessKey]==='destination'&&terminal)result.destinationOnly=true;
  else return deny('access_unproven');
 }
 // PSV includes taxis. Until an explicitly authorised taxi profile is used,
 // never silently discard these constraints like bus-only constraints.
 if(['psv','taxi'].some(k=>t[k]&&!['yes','permissive','designated'].includes(t[k])))return deny('access_unproven');
 const handled=new Set(['oneway:taxi', 'oneway:psv']);
 const oneKey=['oneway:motorcar','oneway:motor_vehicle','oneway:vehicle','oneway'].find(k=>t[k]!=null);
 const one=oneKey?t[oneKey]:(t.junction==='roundabout'||t.highway==='motorway'?'yes':'no');
 if(!['yes','no','1','-1','true','false'].includes(one))return deny('direction_unproven');
 result.effectiveOneway=one;
 for(const key of ['oneway:motorcar','oneway:motor_vehicle','oneway:vehicle'])handled.add(key);
 // These exceptions only grant another class/purpose an additional reverse
 // direction. An ordinary car can safely keep the more restrictive explicit
 // direction WITHOUT using that exception. Never interpret unknown values,
 // or an exception without an explicit ordinary direction, as permission.
 if(oneKey&&['yes','1','true','-1'].includes(one)){
  for(const suffix of ['motor_cycle','disabled_vehicle','disabled','microcar','destination','delivery','private','public_transport','truck','speed_pedelect']){
   const key='oneway:'+suffix;if(t[key]==='no')handled.add(key);
  }
  // The date annotates the source rule; retaining the restrictive direction
  // cannot grant a prohibited reverse movement before/after that date.
  if(/^\d{4}-\d{2}-\d{2}$/.test(t['oneway:start_date']??''))handled.add('oneway:start_date');
 }
 // An explicitly separate shared/turn/bus centre lane is never used as a
 // through lane. Only preserve separately counted ordinary lanes; without
 // that evidence the scoped rule remains closed.
 const n=k=>/^\d+$/.test(t[k]??'')?Number(t[k]):null;
 const center=n('lanes:both_ways'),forward=n('lanes:forward'),backward=n('lanes:backward');
 if(center>0&&n('lanes')===center+(forward??0)+(backward??0)&&(forward??0)+(backward??0)>0){
  for(const mode of [...modes,'oneway'])handled.add(mode+':lanes:both_ways');
  if(forward===0||forward==null)result.forwardAllowed=false;
  if(backward===0||backward==null)result.backwardAllowed=false;
 }
 for(const mode of ['motorcar','motor_vehicle','vehicle','access'])for(const suffix of ['forward','backward','lanes','lanes:forward','lanes:backward'])handled.add(mode+':'+suffix);
 // Directional/lane restrictions apply to their direction, never to an
 // unrelated vehicle class. At least one legally usable lane is required.
 for(const [direction,field]of [['forward','forwardAllowed'],['backward','backwardAllowed']]){
  // The already verified destination-only exception applies consistently to
  // inherited directional/lane access. It never enables ordinary transit,
  // overrides no/private, or changes the separately enforced one-way rule.
  const allowed=directionAccess(t,direction,{destinationEndpoint:terminal&&result.destinationOnly});
  if(allowed===null)return deny('scoped_rule_unproven');
  result[field]&&=allowed;
  for(const [key,value]of Object.entries(dimensions)){
   const directed=key+':'+direction;handled.add(directed);
   if(t[directed]&&t[directed]!=='none'&&(dimensionBound(key,t[directed])===null||!Number.isFinite(value)||value>dimensionBound(key,t[directed]))){
    if(terminal&&exceptions.has(key)&&numerical(t[directed]))result.destinationOnly=true;
    else result[field]=false;
   }
  }
 }
 // These are metadata about the ordinary bound, not a separate bound.
 for(const key of Object.keys(dimensions))for(const suffix of ['signed','source'])handled.add(key+':'+suffix);
 // Per-lane dimensions are safe without a lane-state router only if the
 // vehicle fits EVERY lane. Do not combine a wide prohibited lane with a
 // different narrow permitted lane to manufacture a route.
 for(const [key,value]of Object.entries(dimensions))for(const suffix of ['lanes','lanes:forward','lanes:backward']){
  const scoped=key+':'+suffix;
  if(t[scoped]==null)continue;
  const values=String(t[scoped]).split('|');
  if(values.every(v=>v===''||v==='none'||dimensionBound(key,v)!==null&&Number.isFinite(value)&&value<=dimensionBound(key,v)))handled.add(scoped);
 }
 for(const [key,value]of Object.entries(dimensions)){
  const physical=key+':physical';handled.add(physical);
  if(t[physical]&&t[physical]!=='none'&&(bound(key,t[physical])===null||!Number.isFinite(value)||value>bound(key,t[physical])))return deny('vehicle_dimension');
 }
 if(!result.forwardAllowed&&!result.backwardAllowed)return deny('access_unproven');
 if(Object.keys(t).some(k=>!k.includes(':conditional')&&/^(?:access|vehicle|motor_vehicle|motorcar|oneway|maxheight|maxwidth|maxweight|maxlength):/.test(k)&&!irrelevantToPassengerCarV1(k,vehicleClass)&&!handled.has(k)))return deny('scoped_rule_unproven');
 // Non-taxi passenger cars retain ordinary one-way restrictions. Taxi/PSV
 // exceptions are not used without an explicitly authorised taxi profile.
 if(profile.isTaxi&&['oneway:taxi','oneway:psv'].some(k=>t[k]))return deny('scoped_rule_unproven');
 for(const [key,value]of Object.entries(dimensions))if(t[key]){
  result.ordinaryDimensions[key]=t[key];
  if(t[key]==='none')continue;
  if(dimensionBound(key,t[key])===null)return deny('vehicle_dimension');
  if(t[key]==='default')result.defaultDimensionEvidence={countryCode,maxheightMeters:4,sourceValue:'default'};
  if(!Number.isFinite(value)||value>dimensionBound(key,t[key])){
   if(terminal&&exceptions.has(key))result.destinationOnly=true;
   else return deny('vehicle_dimension');
  }
 }
 // A class-specific ordinary dimension must never silently be ignored for
 // that class. Non-car profiles stay closed until their profile is supported.
 if(vehicleClass!=='passenger_car'&&Object.keys(t).some(k=>k.split(':').includes(vehicleClass)&&!k.endsWith(':conditional')))return deny('vehicle_class_rule_unproven');
 if(speed<=0)return deny('speed_unproven');
 result.speedKph=speed;result.speedForwardKph=osmSpeedFloorV1(t,1);result.speedBackwardKph=osmSpeedFloorV1(t,-1);return result;
}
export function restrictionAppliesToVehicleV1(tags={}, {vehicleClass='passenger_car',isTaxi=false}={}) {
 const keys=Object.keys(tags).filter(k=>k==='restriction'||k.startsWith('restriction:'));
 if(!keys.length)return true; // Malformed source still fails closed downstream.
 if(keys.every(k=>irrelevantToPassengerCarV1(k,vehicleClass)))return false;
 const except=String(tags.except??'').split(';').map(s=>s.trim());
 return !(except.includes('motorcar')&&vehicleClass==='passenger_car'||isTaxi===true&&(except.includes('taxi')||except.includes('psv')));
}
export function restrictionRuleForVehicleV1(tags={},profile={}) {
 const applies=restrictionAppliesToVehicleV1(tags,profile);
 if(!applies)return {applies:false,rule:null,unsupported:false};
 const relevant=Object.keys(tags).filter(k=>k.startsWith('restriction:')&&!irrelevantToPassengerCarV1(k,profile.vehicleClass??'passenger_car'));
 const keys=profile.isTaxi===true?['restriction:taxi','restriction:psv','restriction:motorcar','restriction:motor_vehicle','restriction:vehicle','restriction']:['restriction:motorcar','restriction:motor_vehicle','restriction:vehicle','restriction'];
 const key=keys.find(k=>tags[k]),rule=key?tags[key]:null;
 return {applies:true,rule,unsupported:relevant.some(k=>!keys.includes(k))||! /^(no_|only_)/.test(rule??'')};
}
