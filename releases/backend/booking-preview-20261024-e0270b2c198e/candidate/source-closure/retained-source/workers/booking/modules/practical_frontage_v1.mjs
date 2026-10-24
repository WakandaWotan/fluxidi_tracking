import {projectAccessV1} from './national_road_access_v1.mjs';
import {officialAddressReferenceV1} from './official_address_reference_v1.mjs';

// Existing practical street-side policy, evaluated against trusted immutable
// partition metadata. Client coordinates/names never supply a road attestation.
export const PRACTICAL_FRONTAGE_V1='fluxidi-practical-frontage-v1';
export const foldStreetV1=s=>String(s??'').normalize('NFKD').replace(/\p{M}/gu,'').toLowerCase().replace(/[^\p{L}\p{N}]/gu,'');
const fail=reason=>{throw Error(reason);};
const ordinary=new Set(['residential','living_street','unclassified','tertiary','secondary','primary','tertiary_link','secondary_link','primary_link']);
const forbidden=new Set(['no','private','destination','customers','delivery','agricultural','forestry','permit']);
const vertical=t=>t.bridge&&t.bridge!=='no'||t.tunnel&&t.tunnel!=='no'||t.layer!=null&&String(t.layer)!=='0'||t.level!=null&&String(t.level)!=='0';
const motorway=t=>['motorway','motorway_link','trunk','trunk_link'].includes(t.highway);
const legal=t=>t&&!t.denied&&t.driveable!==false&&!vertical(t)&&!motorway(t)&&!forbidden.has(t.motorcar??t.motor_vehicle??t.vehicle??t.access)&&t.motorroad!=='yes'&&!['no_stopping','no'].includes(t.stopping)&&(ordinary.has(t.highway)||t.highway==='service'&&!['parking_aisle','driveway','drive-through'].includes(t.service));
const bearing=s=>Math.atan2((s.to.longitude-s.from.longitude)*Math.cos(s.from.latitude*Math.PI/180),s.to.latitude-s.from.latitude)*180/Math.PI;
const parallel=(a,b)=>{const d=Math.abs(((a-b+540)%360)-180);return d<=25||d>=155;};
const shares=(a,b)=>[a.from.nodeId,a.to.nodeId].some(id=>id===b.from.nodeId||id===b.to.nodeId);
// A bend whose nearest projection is the shared endpoint of an already
// evaluated segment is not another entrance/corridor. Require the actual node,
// not merely coincident coordinates, and never merge an interior projection.
const endpointContinuation=(a,b)=>[a.from,a.to].some(n=>
 [b.from,b.to].some(m=>m.nodeId===n.nodeId&&
  projectAccessV1(b.point,n,n).meters<=.1&&projectAccessV1(b.point,m,m).meters<=.1));
export function publicAddressPointV1(source,{label='from',latitude='pickup_lat',longitude='pickup_lng',latAlias='from_lat',lngAlias='from_lng',inputField='pickup_input'}={}){
 const lat=source[latitude]??source[latAlias],lng=source[longitude]??source[longitude.replace(/_lng$/,'_lon')]??source[lngAlias]??source[lngAlias.replace(/_lng$/,'_lon')];
 const declared=source[inputField],official=officialAddressReferenceV1(declared);
 if(official)return {official_address:official,access:{kind:'address'}};
 if(lat==null||lng==null||typeof lat==='boolean'||typeof lng==='boolean'||!Number.isFinite(Number(lat))||!Number.isFinite(Number(lng)))fail('reliable_journey_point_unknown');
 const point={latitude:Number(lat),longitude:Number(lng)};
 if(Math.abs(point.latitude)>90||Math.abs(point.longitude)>180||point.latitude===0&&point.longitude===0)fail('reliable_journey_point_unknown');
 const structured=declared?.address??source[label+'_address_context'];
 // A reverse-geocoded GPS label is not independent address authority.
 // Retain the measured fix quality unless the customer supplies an address.
 if(declared?.kind==='gps'&&!structured)return {...point,access:{kind:'gps',capturedAt:declared.capturedAt,accuracyMeters:declared.accuracyMeters,speedMetersPerSecond:0}};
 const text=String(declared?.label??source[label]??'').trim();
 const parts=text.split(',').map(s=>s.trim()),first=parts[0]??'';
 const inline=parts.length===1?first.match(/^(.+?)\s+(\d+[\p{L}\d /;-]*?)\s+(\d{4}(?:\s?[A-Z]{2})?)\s+(.+)$/u):null;
 const match=inline??first.match(/^(.+?)\s+(\d+[\p{L}\d /;-]*)$/u);
 const postal=inline?[null,inline[3],inline[4]]:parts.slice(1).map(s=>s.match(/^(\d{4}(?:\s?[A-Z]{2})?)\s+(.+)$/u)).find(Boolean);
 const address=structured&&typeof structured==='object'?{street:structured.street,houseNumber:structured.houseNumber??structured.housenumber,postcode:structured.postcode,locality:structured.locality,country:structured.country}:{street:match?.[1],houseNumber:match?.[2],postcode:postal?.[1],locality:postal?.[2],country:source.country_code??source.country};
 if(address.street&&address.houseNumber){
  if(Object.values(address).some(v=>v!=null&&(typeof v!=='string'||v.length>160||/[\r\n\0]/.test(v))))fail('access_address_invalid');
  return {...point,address:Object.fromEntries(Object.entries(address).filter(([,v])=>v!=null)),access:{kind:'address'}};
 }
 if(declared?.kind==='address'||structured)fail('access_address_incomplete');
 if(declared?.kind==='gps')return {...point,access:{kind:'gps',capturedAt:declared.capturedAt,accuracyMeters:declared.accuracyMeters,speedMetersPerSecond:0}};
 return point;
}
export function resolvePracticalFrontageV1(args){return resolveNamedFrontage({...args,requireHouseNumber:true});}
// Internal configured-site adapter only. A station/depot is not a fabricated
// numbered address. Public address parsing still requires its real house number.
export function resolveNamedSiteFrontageV1(args){return resolveNamedFrontage({...args,requireHouseNumber:false});}
function resolveNamedFrontage({input,segments,graphVersion,revision,searchRadiusMeters=100,officialGeometry=false,requireHouseNumber}){
 // Optional controls are server call arguments, never read from public input.
 // Existing callers retain exactly their 100m named-street behavior.
 if(!Number.isFinite(searchRadiusMeters)||searchRadiusMeters<=0||searchRadiusMeters>250)fail('access_address_search_radius_invalid');
 const address=input.address;
 if(!address||typeof address.street!=='string'||!address.street.trim()||requireHouseNumber&&(typeof address.houseNumber!=='string'||!address.houseNumber.trim()))fail('access_address_incomplete');
 const name=foldStreetV1(address.street),claimedCountry=String(address.country??'').toUpperCase();
 const country=({BELGIUM:'BE','BELGIË':'BE',BELGIQUE:'BE',NETHERLANDS:'NL',NEDERLAND:'NL',
  FRANCE:'FR',FRANKRIJK:'FR',GERMANY:'DE',DEUTSCHLAND:'DE',DUITSLAND:'DE',
  LUXEMBOURG:'LU',LUXEMBURG:'LU'})[claimedCountry]??claimedCountry;
 if(country&&!/^[A-Z]{2}$/.test(country))fail('access_address_country');
 const rows=segments.map(s=>({...s,...projectAccessV1(input,s.from,s.to),bearing:bearing(s)}));
 if(rows.some(s=>!Array.isArray(s.tags?.streetNames)))fail('access_street_metadata_missing');
 const nameMatch=s=>officialGeometry||s.tags.streetNames.some(n=>foldStreetV1(n)===name);
 const matches=rows.filter(s=>s.meters<=searchRadiusMeters&&nameMatch(s));
 if(!matches.length)fail('access_address_street_unmatched');
 // A country label is not road-access evidence. Published graph coverage,
 // coordinate-bound named geometry and the existing legal/topological checks
 // remain authoritative at a border as within BE/NL. OSM roads need not carry
 // a country tag; when explicit metadata exists it must not conflict.
 const safe=matches.filter(s=>legal(s.tags)&&(!country||!s.tags.country||
   typeof s.tags.country==='string'&&s.tags.country.toUpperCase()===country));
 if(!safe.length)fail('access_address_restricted_or_unrouteable');
 for(const s of safe)for(const k of ['postcode','locality'])if(address[k]&&s.tags[k]&&foldStreetV1(address[k])!==foldStreetV1(s.tags[k]))fail('access_address_locality_conflict');
 safe.sort((a,b)=>a.meters-b.meters||a.edge-b.edge);const best=safe[0];
 // A selected named frontage can be the exact shared endpoint of curved
 // street segments. They are the same reachable junction, not competing
 // frontages. Do not merge disconnected coordinates or a remote connection
 // around a canal; only the selected point's actual graph node qualifies.
 const frontageNode=[best.from,best.to].find(n=>projectAccessV1(best.point,n,n).meters<=.1)?.nodeId;
 const corridor=new Set(),queue=[best];
 while(queue.length){const s=queue.shift();if(corridor.has(s.edge))continue;corridor.add(s.edge);if(corridor.size>8192)fail('access_address_context_limit');for(const next of safe)if(!corridor.has(next.edge)&&shares(s,next)&&(parallel(s.bearing,next.bearing)||endpointContinuation(s,next)||frontageNode!=null&&[s.from.nodeId,s.to.nodeId].includes(frontageNode)&&[next.from.nodeId,next.to.nodeId].includes(frontageNode)))queue.push(next);}
 // A named street's directly connected ordinary roundabout is junction
 // geometry, not an unnamed parallel street. Require trusted junction tags,
 // legal same-level access and actual node connectivity inside the existing
 // address search context; disconnected or restricted roads remain blockers.
 const roundabout=new Set(),junctionQueue=[best];
 const junctionRows=rows.filter(s=>s.meters<=searchRadiusMeters&&s.tags.junction==='roundabout'&&
   !s.tags.streetNames.length&&legal(s.tags));
 while(junctionQueue.length){const s=junctionQueue.shift();for(const next of junctionRows){
  if(roundabout.has(next.edge)||!shares(s,next))continue;
  roundabout.add(next.edge);if(roundabout.size>8192)fail('access_address_context_limit');
  junctionQueue.push(next);
 }}
 for(const s of rows){
  if(corridor.has(s.edge)||shares(best,s)||roundabout.has(s.edge))continue;
  const at=projectAccessV1(best.point,s.from,s.to).meters;
  if(at>25||s.meters>best.meters+25)continue;
  if(vertical(s.tags)){
   if(nameMatch(s)||at<=.1||(!s.tags.streetNames.length&&s.tags.highway!=='service'))fail('access_address_vertical_ambiguity');
  }else if(motorway(s.tags)&&parallel(best.bearing,s.bearing))fail('access_address_motorway_ambiguity');
  else if(parallel(best.bearing,s.bearing)){
   const explicitlyOther=s.tags.streetNames.length&&!nameMatch(s),internal=s.tags.highway==='service'&&!nameMatch(s);
   if(!explicitlyOther&&!internal)fail('access_address_parallel_ambiguity');
  }
 }
 if(safe.some(s=>!corridor.has(s.edge)&&s.meters<=Math.min(searchRadiusMeters,best.meters+15)))fail('access_address_competing_frontage');
 return {point:best.point,offsetMeters:best.meters,confidence:best.meters<=50&&best.tags.highway!=='service'?'HIGH':'MEDIUM_SAFE',wayIds:[best.way],graphVersion,revision,schema:PRACTICAL_FRONTAGE_V1,physicalEntranceRequired:false};
}
