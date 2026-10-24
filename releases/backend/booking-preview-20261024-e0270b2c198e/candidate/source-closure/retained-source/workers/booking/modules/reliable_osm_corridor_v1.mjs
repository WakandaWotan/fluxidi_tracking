import {DirectedRoadGraph} from './routing_evidence_core.mjs';
import {FluxidiRoutingCore} from './routing_core_v1.mjs';
import {evaluateOsmWayAccessV1,irrelevantToPassengerCarV1,restrictionRuleForVehicleV1} from './osm_vehicle_access_v1.mjs';
import {createReliableOsmPointRoutesV1} from './reliable_osm_point_routes_v1.mjs';
const meters=(a,b)=>{const r=x=>x*Math.PI/180,h=Math.sin(r(b.latitude-a.latitude)/2)**2+Math.cos(r(a.latitude))*Math.cos(r(b.latitude))*Math.sin(r(b.longitude-a.longitude)/2)**2;return 12742000*Math.asin(Math.min(1,Math.sqrt(h)));};
const OSM_VEHICLE_POLICY_REVISION='car-speed-time-envelope-20261012';
// Small pinned R&D extract adapter, not a complete regional OSM importer.
// Unknown access, conditional rules, barriers and unsupported restrictions
// fail closed. Static geometry must never manufacture an ETA certificate.
export function importReliableOsmCorridorV1(data,{heightMeters=2.5,widthMeters=2,massTonnes=3,lengthMeters=null,vehicleClass='passenger_car',isTaxi=false}={}){
 return buildCorridor(data,{heightMeters,widthMeters,massTonnes,lengthMeters,vehicleClass,isTaxi});
}
function buildCorridor(data,{heightMeters,widthMeters,massTonnes,lengthMeters,vehicleClass,isTaxi},terminalWays=new Map()){
 if(data?.source==='OpenStreetMap Geofabrik PBF'&&(!Array.isArray(data.provenance)||data.provenance.length<1||data.provenance.length>3||data.provenance.some(p=>!/^https:\/\/download\.geofabrik\.de\/europe\/(?:belgium|netherlands|benelux)-latest\.osm\.pbf$/.test(p?.url)||!/^[a-f0-9]{64}$/.test(p?.sha256)||!Number.isFinite(Date.parse(p?.snapshotAt)))))throw Error('osm_pbf_provenance_invalid');
 if(!['OpenStreetMap API 0.6','OpenStreetMap Overpass','OpenStreetMap Geofabrik PBF'].includes(data?.source)||data.license!=='ODbL-1.0'||!/^[a-f0-9]{64}$/.test(data.rawSha256)||!Array.isArray(data.nodes)||!Array.isArray(data.ways)||!Array.isArray(data.relations)||data.nodes.length>100000)throw Error('osm_corridor_invalid');
 if(![heightMeters,widthMeters,massTonnes].every(v=>Number.isFinite(v)&&v>0)||lengthMeters!==null&&(!Number.isFinite(lengthMeters)||lengthMeters<=0))throw Error('osm_vehicle_dimensions_invalid');
 const coordinates=data.nodes.map(n=>({latitude:n.latitude,longitude:n.longitude})),index=new Map(data.nodes.map((n,i)=>[n.id,i])),edges=[],denied=[],excludedSegments=[];
 const profile={heightMeters,widthMeters,massTonnes,lengthMeters,vehicleClass,isTaxi},retainedRoadRules=[];
 const exclude=way=>{for(let i=1;i<way.nodes.length;i++){const a=index.get(way.nodes[i-1]),b=index.get(way.nodes[i]);if(a!==undefined&&b!==undefined)excludedSegments.push({from:coordinates[a],to:coordinates[b],osmWay:way.id});}};
 for(const way of data.ways){const access=evaluateOsmWayAccessV1(way.tags,profile,{terminal:terminalWays.has(way.id)}),reason=access.reason;
  retainedRoadRules.push({way:way.id,tags:{...way.tags},access});
  if(reason){denied.push({way:way.id,reason});exclude(way);continue;}
  const t=way.tags,one=access.effectiveOneway;
  const speed=/^\d+(?:\.\d+)?$/.test(t.maxspeed??'')?Math.min(130,Number(t.maxspeed)):t.highway==='living_street'?15:30;
  if(speed<=0){denied.push({way:way.id,reason:'speed_unproven'});exclude(way);continue;}
  for(let i=1;i<way.nodes.length;i++){
   const a=index.get(way.nodes[i-1]),b=index.get(way.nodes[i]);if(a===undefined||b===undefined)throw Error('osm_node_missing');
   if([a,b].some(n=>{const tags=data.nodes[n].tags??{};return tags.barrier&&tags.barrier!=='no'||Object.keys(tags).some(k=>k.includes(':conditional')&&!irrelevantToPassengerCarV1(k,vehicleClass))||evaluateOsmWayAccessV1({...tags,highway:'service'},profile).reason;})){denied.push({way:way.id,reason:'barrier_unproven'});continue;}
   const d=meters(coordinates[a],coordinates[b]);
   const add=(from,to,speed)=>edges.push({from,to,minimum:d/(speed/3.6),distanceMeters:d,geometry:[coordinates[from],coordinates[to]],osmWay:way.id,kind:t.bridge&&t.bridge!=='no'?'bridge':t.tunnel&&t.tunnel!=='no'?'tunnel':'local',roadClass:t.highway,roundabout:t.junction==='roundabout',ramp:t.highway.endsWith('_link'),serviceRoad:t.highway==='service',staticSpeedKph:speed,speedEvidence:/^\d+(?:\.\d+)?$/.test(t.maxspeed??'')?'OSM_TAG':'CONSERVATIVE_PROFILE',oneWay:one!=='no'&&one!=='false'});
   if(one!=='-1'&&access.forwardAllowed)add(a,b,access.speedForwardKph);if(!['yes','1','true'].includes(one)&&access.backwardAllowed)add(b,a,access.speedBackwardKph);
  }
 }
 const turns=[],restrictions=[],outgoingByNode=new Map();
 edges.forEach((e,i)=>{if(!outgoingByNode.has(e.from))outgoingByNode.set(e.from,[]);outgoingByNode.get(e.from).push(i);});
 // A destination exception is a terminal permission, never a shortcut. The
 // existing edge-state router enforces the entry/exit bans even after a
 // point split. This temporary projection is never exposed to the caller.
 for(const rule of retainedRoadRules.filter(r=>r.access.destinationOnly&&!r.access.reason)){
  const role=terminalWays.get(rule.way);
  for(let i=0;i<edges.length;i++)for(const j of outgoingByNode.get(edges[i].to)??[]){
   const a=edges[i],b=edges[j];
   const leaving=a.osmWay===rule.way&&b.osmWay!==rule.way;
   const entering=a.osmWay!==rule.way&&b.osmWay===rule.way;
   if((leaving&&role.destination)||(entering&&role.origin))turns.push({fromEdge:i,toEdge:j,disabled:true});
  }
 }
 for(const relation of data.relations){
  const rule=restrictionRuleForVehicleV1(relation.tags,profile);
  if(!rule.applies){restrictions.push({id:relation.id,status:'not_applicable_to_profile',tags:{...relation.tags}});continue;}
  const from=relation.members.filter(m=>m.role==='from'&&m.type==='way'),to=relation.members.filter(m=>m.role==='to'&&m.type==='way'),via=relation.members.filter(m=>m.role==='via'&&m.type==='node');
  const incoming=edges.map((e,i)=>({e,i})).filter(x=>from.some(m=>m.ref===x.e.osmWay));
  const supported=from.length===1&&to.length===1&&via.length===1&&index.has(via[0].ref)&&!rule.unsupported;
  if(!supported){incoming.forEach(x=>x.e.disabled=true);restrictions.push({id:relation.id,status:'incoming_disabled_unsupported'});continue;}
  const node=index.get(via[0].ref);let count=0;
  for(const x of incoming.filter(x=>x.e.to===node))for(let j=0;j<edges.length;j++){
   const e=edges[j];if(e.from!==node)continue;
   const prohibited=rule.rule.startsWith('only_')?e.osmWay!==to[0].ref:e.osmWay===to[0].ref;
   if(prohibited){turns.push({fromEdge:x.i,toEdge:j,disabled:true});count++;}
  }
  restrictions.push({id:relation.id,status:'applied_car_conservative',turns:count});
 }
 // Capture excluded node/barrier road pieces too: a nearby legal road must
 // not absorb a GPS measurement actually located on a denied private piece.
 const barrierWays=new Set(denied.filter(d=>d.reason==='barrier_unproven').map(d=>d.way));
 for(const way of data.ways)if(barrierWays.has(way.id))exclude(way);
 const graph=new DirectedRoadGraph({nodes:coordinates.length,edges,turns,version:'osm-corridor-v5-'+data.rawSha256.slice(0,16)+'-'+vehicleClass+'-'+[heightMeters,widthMeters,massTonnes,lengthMeters??'unknown-length',isTaxi].join('-')+'-'+OSM_VEHICLE_POLICY_REVISION+(terminalWays.size?':terminals:'+JSON.stringify([...terminalWays].sort(([a],[b])=>a-b)):'' )}),core=new FluxidiRoutingCore({graph,coordinates});
 return {graph,core,coordinates,turns,denied,restrictions,retainedRoadRules,excludedSegments,source:data.source,license:data.license,attribution:data.attribution,staticEtaOnly:true,trafficCalibration:null,
  snapExact(point){const s=core.snap(point,{maxDistanceMeters:0.1});if(!graph.edges.some(e=>!e.disabled&&(e.from===s.node||e.to===s.node)))throw Error('osm_access_unproven');const tied=coordinates.some((p,i)=>i!==s.node&&meters(p,point)<=0.1);if(tied)throw Error('osm_snap_ambiguous');return {...s,confidence:1,ambiguous:false};},
  context(from,to,scope){return {...scope,graphVersion:graph.version,fromNode:from,toNode:to,from:coordinates[from],to:coordinates[to],profile:'car',options:{},leg:'pickup',departureSemantics:'now'};}};
}
// Offline/local on-road routing only. This is not building-to-road access
// evidence, an address entrance assertion, or a public caller-supplied override.
export async function routeReliableOsmTerminalJourneyV1(data,{origin,destination,scope,profile={}}){
 const nodes=new Map(data.nodes.map(n=>[n.id,n]));
 function terminalWay(point){
  if(!point||![point.latitude,point.longitude].every(Number.isFinite))throw Error('osm_point_invalid');
  const x=111195*Math.cos(point.latitude*Math.PI/180),y=111195,matches=[];
  for(const w of data.ways){let on=false;for(let i=1;i<w.nodes.length;i++){
   const a=nodes.get(w.nodes[i-1]),b=nodes.get(w.nodes[i]);if(!a||!b)throw Error('osm_node_missing');
   const dx=(b.longitude-a.longitude)*x,dy=(b.latitude-a.latitude)*y,t=Math.max(0,Math.min(1,((point.longitude-a.longitude)*x*dx+(point.latitude-a.latitude)*y*dy)/(dx*dx+dy*dy||1)));
   if(Math.hypot((point.longitude-a.longitude)*x-t*dx,(point.latitude-a.latitude)*y-t*dy)<=.1)on=true;
  }if(on)matches.push(w.id);}
  if(matches.length!==1)throw Error(matches.length?'osm_snap_ambiguous':'osm_access_unproven');return matches[0];
 }
 const a=terminalWay(origin),b=terminalWay(destination),terminals=new Map();
 terminals.set(a,{origin:true,destination:a===b});if(a!==b)terminals.set(b,{origin:false,destination:true});
 const c=buildCorridor(data,{heightMeters:2.5,widthMeters:2,massTonnes:3,lengthMeters:null,vehicleClass:'passenger_car',isTaxi:false,...profile},terminals);
 const result=await createReliableOsmPointRoutesV1(c).route({origin,destination,scope});
 return {...result,terminalAccessPolicy:'on-road-terminal-entry-exit-v1',terminalSourceWays:[...terminals],commercialRoutingCalls:0};
}
