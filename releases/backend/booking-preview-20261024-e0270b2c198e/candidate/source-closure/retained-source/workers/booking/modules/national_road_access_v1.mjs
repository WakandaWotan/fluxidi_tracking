import {validateOsmSpeedProfileV1} from './osm_speed_rules_v1.mjs';
// Bounded road-access validation for the existing partition router. It creates
// no road, driveway or terminal connector, and makes no provider request.
export const NATIONAL_ACCESS_V1='fluxidi-national-road-access-v1';
const finite=Number.isFinite,deny=s=>{throw Error(s);};
// Confidence uses the original observation clock, not receipt/heartbeat time.
export function driverGpsConfidenceV1({accuracyMeters,capturedAt}={},now=Date.now()){
 if(!finite(accuracyMeters)||accuracyMeters<0||!finite(capturedAt)||capturedAt>now||now-capturedAt>30000)return null;
 if(accuracyMeters<=20&&now-capturedAt<=10000)return 'high';
 if(accuracyMeters<=50)return 'normal';
 return accuracyMeters<=100?'low':null;
}
export function projectAccessV1(p,a,b){
 const x=111195*Math.cos(p.latitude*Math.PI/180),y=111195,dx=(b.longitude-a.longitude)*x,dy=(b.latitude-a.latitude)*y,len=dx*dx+dy*dy;
 const t=len?Math.max(0,Math.min(1,((p.longitude-a.longitude)*x*dx+(p.latitude-a.latitude)*y*dy)/len)):0;
 return {fraction:t,point:{longitude:a.longitude+(b.longitude-a.longitude)*t,latitude:a.latitude+(b.latitude-a.latitude)*t},meters:Math.hypot((p.longitude-a.longitude)*x-t*dx,(p.latitude-a.latitude)*y-t*dy)};
}
export function validateAccessContextV1(context,version){
 if(context?.schema!==NATIONAL_ACCESS_V1||context.graphVersion!==version||context.complete!==true||typeof context.revision!=='string'||!Array.isArray(context.ways)||context.ways.length>100000||!Array.isArray(context.negative)||context.negative.length>150000)deny('access_context_invalid');
 const frontageFields=new Set(['streetNames','country','postcode','locality']);let frontageBytes=0;
 const speedProfiles=context.speedProfiles??[];if(!Array.isArray(speedProfiles)||speedProfiles.length>256)deny('speed_profile_catalog_invalid');for(const p of speedProfiles){validateOsmSpeedProfileV1(p);frontageBytes+=JSON.stringify(p).length*2+128;}
 const ways=new Map();for(const [id,t]of context.ways){if(!Number.isSafeInteger(id)||ways.has(id)||typeof t?.highway!=='string'||Object.keys(t).length>21)deny('access_way_invalid');
  if(t.streetNames!==undefined){if(!Array.isArray(t.streetNames)||t.streetNames.length>16||t.streetNames.some(n=>typeof n!=='string'||n.length>160||/[\r\n\0]/.test(n)))deny('access_street_metadata_invalid');Object.freeze(t.streetNames);}
  for(const k of ['country','postcode','locality'])if(t[k]!==undefined&&(typeof t[k]!=='string'||t[k].length>160||/[\r\n\0]/.test(t[k])))deny('access_street_metadata_invalid');
  frontageBytes+=JSON.stringify(Object.fromEntries(Object.entries(t).filter(([k])=>frontageFields.has(k)))).length*2+64;
  if(t.speedProfileRef!==undefined){if(!Number.isSafeInteger(t.speedProfileRef)||!speedProfiles[t.speedProfileRef]||t.speedProfile)deny('speed_profile_reference_invalid');t.speedProfile=speedProfiles[t.speedProfileRef];}
  if(t.speedProfile&&t.speedProfileRef===undefined){validateOsmSpeedProfileV1(t.speedProfile);frontageBytes+=JSON.stringify(t.speedProfile).length*2+128;}
  ways.set(id,Object.freeze(t));}
 for(const n of context.negative)if(n.length!==9||!Number.isSafeInteger(n[0])||!n.slice(2,6).every(finite)||typeof n[6]!=='string'||!n.slice(7,9).every(Number.isSafeInteger))deny('access_negative_invalid');
 const grid=new Map(),long=[];let refs=0;
 for(const n of context.negative){const x0=Math.floor(Math.min(n[2],n[4])/.002),x1=Math.floor(Math.max(n[2],n[4])/.002),y0=Math.floor(Math.min(n[3],n[5])/.002),y1=Math.floor(Math.max(n[3],n[5])/.002);
  if((x1-x0+1)*(y1-y0+1)>64){long.push(n);continue;}
  for(let x=x0;x<=x1;x++)for(let y=y0;y<=y1;y++){const k=x+':'+y;if(!grid.has(k))grid.set(k,[]);grid.get(k).push(n);if(++refs>1000000)deny('access_negative_index_limit');}
 }
 return {ways,negative:context.negative,grid,long,revision:context.revision,residentBytes:ways.size*320+frontageBytes+context.negative.length*112+refs*16+grid.size*96};
}
function bearing(a,b){const r=Math.PI/180,y=Math.sin((b.longitude-a.longitude)*r)*Math.cos(b.latitude*r),x=Math.cos(a.latitude*r)*Math.sin(b.latitude*r)-Math.sin(a.latitude*r)*Math.cos(b.latitude*r)*Math.cos((b.longitude-a.longitude)*r);return (Math.atan2(y,x)/r+360)%360;}
// A mapped unnamed parking/service segment can retain its existing admission
// only with an actual directed, legal exit into the normal road network.
// This does not establish a named street from an uncorroborated GPS label.
export function provenUnnamedServiceExitV1(snap,segments,bans=new Set()){
 const byEdge=new Map(segments.map(s=>[s.edge,s]));
 const legal=t=>t&&!t.denied&&!t.bridge&&!t.tunnel&&(t.layer==null||String(t.layer)==='0')&&(t.level==null||String(t.level)==='0')&&!['no','private','destination','customers','delivery'].includes(t.motorcar??t.motor_vehicle??t.vehicle??t.access);
 return snap.kind==='segment'&&snap.alternatives?.length>0&&snap.alternatives.every(a=>{const s=byEdge.get(a.edge);return legal(s?.tags)&&s.tags.highway==='service'&&!(s.tags.streetNames?.length);})&&snap.alternatives.some(a=>segments.some(next=>next.from.nodeId===a.to.nodeId&&next.way!==byEdge.get(a.edge).way&&['residential','living_street','unclassified','tertiary','secondary','primary'].includes(next.tags?.highway)&&legal(next.tags)&&!bans.has(a.edge+':'+next.edge)));
}
export function resolveRoadAccessV1({input,segments,negative,graphVersion,revision,clock=Date.now}){return resolveRoadAccessCoreV1({input,segments,negative,graphVersion,revision,clock});}
export function commonRoadJunctionV1({input,rows,groups,contextWays,bans,graphVersion,revision}){
 const a=input.access,radius=Math.max(25,a.accuracyMeters);if(a.headingDegrees!=null||groups.size<2||groups.size>16)return null;
 const physical=new Map(),adjacency=new Map(),edgeIds=new Set();
 for(const s of rows){
  if(!['residential','living_street','unclassified','tertiary','secondary','primary'].includes(s.tags.highway)||s.tags.oneway!==0)return null;
  const key=[Math.min(s.from.nodeId,s.to.nodeId),Math.max(s.from.nodeId,s.to.nodeId)].join(':');
  if(!physical.has(key))physical.set(key,[]);physical.get(key).push(s);edgeIds.add(s.edge);
 }
 for(const rs of physical.values()){
  const s=rs[0];if(rs.some(r=>r.way!==s.way||!finite(r.lengthMeters)||r.lengthMeters<0||!finite(r.seconds)||r.seconds<0)||!rs.some(r=>r.from.nodeId===s.to.nodeId&&r.to.nodeId===s.from.nodeId))return null;
  for(const n of[s.from.nodeId,s.to.nodeId]){if(!adjacency.has(n))adjacency.set(n,[]);adjacency.get(n).push(s);}
 }
 const plausible=[...physical.values()].map(rs=>rs[0]).filter(s=>projectAccessV1(input,s.from,s.to).meters<=radius+1e-6),coreAdjacency=new Map();
 for(const s of plausible)for(const n of[s.from.nodeId,s.to.nodeId]){if(!coreAdjacency.has(n))coreAdjacency.set(n,[]);coreAdjacency.get(n).push(s);}
 // OSM way IDs and farther legal junctions do not by themselves create an
 // ambiguous origin. Prefer the existing unique practical anchor within25m.
 // If none exists, require exactly one anchor inside the REPORTED uncertainty;
 // this never enlarges the precision circle of an understated indoor fix.
 // Prove every hypothesis in the original uncertainty circle reaches it
 // through this same bidirectional, acyclic, restriction-free local network.
 const hubs=[...coreAdjacency].filter(([,rs])=>rs.length>2),within=limit=>hubs.filter(([n,rs])=>{const p=rs[0].from.nodeId===n?rs[0].from:rs[0].to;return projectAccessV1(input,p,p).meters<=limit+1e-6;});
 const practicalHubs=within(25),anchorRadius=practicalHubs.length?25:Math.max(25,a.accuracyMeters),coreHubs=practicalHubs.length?practicalHubs:within(anchorRadius);
 if(coreHubs.length!==1||physical.size!==adjacency.size-1)return null;
 const [nodeId,arms]=coreHubs[0],node=arms[0].from.nodeId===nodeId?arms[0].from:arms[0].to,distanceMeters=projectAccessV1(input,node,node).meters;
 if(distanceMeters>anchorRadius+1e-6||new Set(plausible.map(s=>s.way)).size!==groups.size)return null;
 const coreFound=new Set(),coreQueue=[nodeId];while(coreQueue.length){const n=coreQueue.pop();if(coreFound.has(n))continue;coreFound.add(n);for(const s of coreAdjacency.get(n)??[])coreQueue.push(s.from.nodeId,s.to.nodeId);}if(coreFound.size!==coreAdjacency.size)return null;
 const found=new Set(),queue=[nodeId];while(queue.length){const n=queue.pop();if(found.has(n))continue;found.add(n);for(const s of adjacency.get(n)??[])queue.push(s.from.nodeId,s.to.nodeId);}if(found.size!==adjacency.size)return null;
 for(const[n,rs]of adjacency){const c=rs[0].from.nodeId===n?rs[0].from:rs[0].to;
  if(rs.length>4||rs.length>2&&n!==nodeId&&projectAccessV1(input,c,c).meters<=anchorRadius+1e-6)return null;
  if(rs.length>2)for(let i=0;i<rs.length;i++)for(let j=i+1;j<rs.length;j++){const l=rs[i].from.nodeId===n?rs[i].to:rs[i].from,r=rs[j].from.nodeId===n?rs[j].to:rs[j].from;if(Math.abs(((bearing(c,l)-bearing(c,r)+540)%360)-180)<=35)return null;}
  if(rs.length===2){const l=rs[0].from.nodeId===n?rs[0].to:rs[0].from,r=rs[1].from.nodeId===n?rs[1].to:rs[1].from;if(Math.abs(((bearing(l,c)-bearing(c,r)+540)%360)-180)>35)return null;}
 }
 // A legal halo continuation is not an origin hypothesis. It may not hide
 // a true parallel shadow overlapping the interior of any plausible road.
 for(const rs of physical.values()){const s=rs[0];if(projectAccessV1(input,s.from,s.to).meters<=radius+1e-6)continue;
  for(const core of plausible){const angle=Math.abs(((bearing(s.from,s.to)-bearing(core.from,core.to)+540)%360)-180);if(Math.min(angle,180-angle)>35)continue;const f=projectAccessV1(s.from,core.from,core.to).fraction,t=projectAccessV1(s.to,core.from,core.to).fraction;if(Math.max(f,t)>1e-6&&Math.min(f,t)<1-1e-6)return null;}
 }
 for(const ban of bans??[]){const[from,to]=ban.split(':').map(Number);if(edgeIds.has(from)&&edgeIds.has(to))return null;}
 // All plausible portions of existing graph edges have a unique legal path
 // to this hub. The bounded practical search remains separate from the raw
 // measurement. Only graph lengths/times contribute, never a connector.
 let localLegDistanceBoundMeters=0,localLegTimeBoundSeconds=0;
 const paths=new Map([[nodeId,{meters:0,seconds:0}]]),pathQueue=[nodeId];while(pathQueue.length){const n=pathQueue.shift();for(const s of adjacency.get(n)??[]){const child=s.from.nodeId===n?s.to.nodeId:s.from.nodeId;if(paths.has(child))continue;const rs=physical.get([Math.min(n,child),Math.max(n,child)].join(':'));paths.set(child,{meters:paths.get(n).meters+Math.max(...rs.map(r=>r.lengthMeters)),seconds:paths.get(n).seconds+Math.max(...rs.map(r=>r.seconds))});pathQueue.push(child);}}
 const x=111195*Math.cos(input.latitude*Math.PI/180),y=111195;
 for(const s of plausible){const start=paths.get(s.from.nodeId).meters<=paths.get(s.to.nodeId).meters?s.from:s.to,other=start===s.from?s.to:s.from,costs=physical.get([Math.min(start.nodeId,other.nodeId),Math.max(start.nodeId,other.nodeId)].join(':')),px=(start.longitude-input.longitude)*x,py=(start.latitude-input.latitude)*y,dx=(other.longitude-start.longitude)*x,dy=(other.latitude-start.latitude)*y,aa=dx*dx+dy*dy,bb=2*(px*dx+py*dy),cc=px*px+py*py-radius*radius,disc=bb*bb-4*aa*cc;
  if(!finite(aa)||aa<=0||!finite(disc)||disc<0||!finite(s.lengthMeters)||s.lengthMeters<0||!finite(s.seconds)||s.seconds<0)return null;
  const fraction=Math.min(1,Math.max(0,(-bb+Math.sqrt(disc))/(2*aa)));localLegDistanceBoundMeters=Math.max(localLegDistanceBoundMeters,paths.get(start.nodeId).meters+fraction*Math.max(...costs.map(r=>r.lengthMeters)));localLegTimeBoundSeconds=Math.max(localLegTimeBoundSeconds,paths.get(start.nodeId).seconds+fraction*Math.max(...costs.map(r=>r.seconds)));
 }
 // Keep the original bound for practical anchors. A measured farther anchor
 // adds only its actual offset; all time/distance comes from real graph edges.
 // This changes no search radius and creates no off-road connector.
 if(!finite(localLegDistanceBoundMeters)||localLegDistanceBoundMeters>radius+Math.max(25,distanceMeters)+1||!finite(localLegTimeBoundSeconds)||localLegTimeBoundSeconds<0||localLegDistanceBoundMeters>0&&localLegTimeBoundSeconds<=0)return null;
 const junction={schema:'fluxidi-common-road-junction-v1',nodeId,point:{latitude:node.latitude,longitude:node.longitude},distanceMeters,...(distanceMeters>25?{anchorBasis:'reported_accuracy',anchorRadiusMeters:a.accuracyMeters}:{}),wayIds:[...groups.keys()].sort((x,y)=>x-y),edgeIds:[...edgeIds].sort((x,y)=>x-y),localLegDistanceBoundMeters,localLegTimeBoundSeconds};
 return {kind:'node',node,graphVersion,accessEvidence:{confidence:'MEDIUM_SAFE',schema:NATIONAL_ACCESS_V1,revision,kind:'driver_common_junction',snapMeters:distanceMeters,accuracyMeters:a.accuracyMeters,wayIds:junction.wayIds,direction:'two_way',junction}};
}
function resolveRoadAccessCoreV1({input,segments,negative,graphVersion,revision,clock=Date.now,nearPickup=false,practicalGps=false,driverJunction=false,bans=new Set()}){
 const gps=input.access?.kind==='gps',a=input.access??{},now=clock();
 if(gps&&(!finite(a.capturedAt)||a.capturedAt>now||now-a.capturedAt>30000||!finite(a.accuracyMeters)||a.accuracyMeters<=0||!nearPickup&&a.accuracyMeters>25))deny('access_gps_stale_or_accuracy');
 if(a.headingDegrees!=null&&(!finite(a.headingDegrees)||a.headingDegrees<0||a.headingDegrees>=360||!finite(a.speedMetersPerSecond)||a.speedMetersPerSecond<2))deny('access_heading_unreliable');
 // A bounded map-geometry tolerance is a separate server policy. It never
 // rewrites the original GPS precision or manufactures a connector leg.
 const radius=gps?(practicalGps?Math.max(25,a.accuracyMeters):a.accuracyMeters):.1,guardRadius=practicalGps?Math.max(50,radius):radius,groups=new Map(),nearNodes=new Map(),contextWays=new Set(),contextRows=[];
 const exactNodes=new Set();for(const s of segments)for(const node of [s.from,s.to])if(projectAccessV1(input,node,node).meters<=.1)exactNodes.add(node.nodeId);
 for(const n of negative){
  const p=projectAccessV1(input,{longitude:n[2],latitude:n[3]},{longitude:n[4],latitude:n[5]});
  // A forbidden branch sharing an actual junction does not forbid pickup
  // on the legal road at that exact node. Its interior is never accepted,
  // and identical coordinates with a different node ID do not prove access.
  const junction=p.meters<=.1&&(p.fraction<=1e-6&&exactNodes.has(n[7])||p.fraction>=1-1e-6&&exactNodes.has(n[8]));
  if(p.meters<=guardRadius+1e-6&&(!junction||nearPickup))deny('access_restricted_or_barrier_ambiguity');
 }
 for(const s of segments){
  const p=projectAccessV1(input,s.from,s.to);
  // A second road just outside the reported GPS accuracy can expose an
  // understated/outlier fix. This halo only rejects ambiguity; it never
  // enlarges the distance at which any road may be accepted.
  if(gps&&p.meters<=Math.max(50,nearPickup?radius:0)+1e-6)contextWays.add(s.way);
  if(p.meters>guardRadius+1e-6)continue;
  const t=s.tags;if(!t)deny('access_context_missing');
  // No coordinate, heading or nearest-distance ranking resolves vertical
  // ambiguity. Mapped bridge/tunnel/deck access needs a separate source proof.
  if(t.bridge||t.tunnel||t.layer!=null&&String(t.layer)!=='0'||t.level!=null&&String(t.level)!=='0')deny('access_vertical_layer_unproven');
  if(['motorway','motorway_link','trunk','trunk_link'].includes(t.highway))deny('access_motorway_pickup_unproven');
  if(t.denied||['private','no','destination','customers','delivery'].includes(t.access))deny('access_restricted_road');
  if(nearPickup&&(t.driveable===false||t.motorroad==='yes'||['no_stopping','no'].includes(t.stopping)||['private','no','destination','customers','delivery','agricultural','forestry','permit'].includes(t.motorcar??t.motor_vehicle??t.vehicle??t.access)))deny('access_restricted_road');
  if(practicalGps)contextRows.push({...s,...p});
  if(p.meters>radius+1e-6)continue;
  if(!groups.has(s.way))groups.set(s.way,[]);groups.get(s.way).push({...s,...p});
  for(const node of [s.from,s.to])if(projectAccessV1(input,node,node).meters<=.1)nearNodes.set(node.nodeId,node);
 }
 if(!groups.size)deny(gps?'access_no_road_within_accuracy':'access_mapped_connector_missing');
 if(nearPickup){
  if(driverJunction&&(groups.size!==1||contextWays.size!==1)){const junction=commonRoadJunctionV1({input,rows:contextRows,groups,contextWays,bans,graphVersion,revision});if(junction)return junction;}
  if(groups.size!==1||contextWays.size!==1)deny('access_parallel_or_junction_ambiguity');
  const rows=practicalGps?contextRows:[...groups.values()][0];singleRoadCorridorV1(rows);
  if(rows.some(s=>s.tags.oneway!==0)&&a.headingDegrees==null)deny('access_direction_unproven');
 }
 // Exact graph junctions preserve existing topology. Other plausible roads
 // must share this exact node; a parallel or crossing road cannot disappear.
 if(nearNodes.size===1){const node=[...nearNodes.values()][0],all=[...groups.values()].flat();if(all.every(s=>s.from.nodeId===node.nodeId||s.to.nodeId===node.nodeId)&&!(gps&&a.headingDegrees!=null))return {kind:'node',node,graphVersion,accessEvidence:{confidence:'HIGH',schema:NATIONAL_ACCESS_V1,revision,kind:gps?'gps':'mapped_road_point',snapMeters:0,wayIds:[...groups.keys()]}};
 }
 if(groups.size!==1)deny('access_parallel_or_junction_ambiguity');
 if(gps&&!nearNodes.size&&contextWays.size>1)deny('access_outlier_or_adjacent_road_ambiguity');
 const rows=[...groups.values()][0],physical=new Map();
 for(const s of rows){const k=[s.way,Math.min(s.from.nodeId,s.to.nodeId),Math.max(s.from.nodeId,s.to.nodeId)].join(':');if(!physical.has(k))physical.set(k,[]);physical.get(k).push(s);}
 const ranked=[...physical.values()].sort((x,y)=>x[0].meters-y[0].meters),best=ranked[0];
 if(ranked.length>1&&Math.abs(ranked[1][0].meters-best[0].meters)<.01)deny('access_segment_ambiguity');
 if(best[0].fraction<=1e-6||best[0].fraction>=1-1e-6)deny('access_junction_transition_unproven');
 let edges=best;
 if(gps&&best.some(s=>s.tags.oneway!==0)&&a.headingDegrees==null)deny('access_direction_unproven');
 if(a.headingDegrees!=null){edges=best.filter(s=>Math.abs(((a.headingDegrees-bearing(s.from,s.to)+540)%360)-180)<=35);if(!edges.length)deny('access_wrong_direction');}
 return {kind:'segment',alternatives:edges.map(s=>({edge:s.edge,way:s.way,...(s.partitionId?{partitionId:s.partitionId}:{}),...(s.ordinal!=null?{ordinal:s.ordinal}:{}),...(s.direction!=null?{direction:s.direction}:{}),...(s.speedProfile?{speedProfile:s.speedProfile,speedProfileKey:s.speedProfileKey}:{}),from:s.from,to:s.to,fraction:s.fraction,seconds:s.seconds,meters:s.lengthMeters,point:s.point})),graphVersion,accessEvidence:{confidence:'HIGH',schema:NATIONAL_ACCESS_V1,revision,kind:gps?'gps':'mapped_road_point',snapMeters:best[0].meters,accuracyMeters:gps?a.accuracyMeters:null,wayIds:[...groups.keys()],direction:edges.length===1?'directed':'two_way'}};
}

function singleRoadCorridorV1(rows){
 const physical=new Map();for(const s of rows){const key=[Math.min(s.from.nodeId,s.to.nodeId),Math.max(s.from.nodeId,s.to.nodeId)].join(':');if(!physical.has(key))physical.set(key,s);}
 const adjacency=new Map();for(const s of physical.values())for(const n of [s.from.nodeId,s.to.nodeId]){if(!adjacency.has(n))adjacency.set(n,[]);adjacency.get(n).push(s);}
 for(const [n,edges] of adjacency){if(edges.length>2)deny('access_near_pickup_context_not_unique');if(edges.length===2){const common=edges[0].from.nodeId===n?edges[0].from:edges[0].to,left=edges[0].from.nodeId===n?edges[0].to:edges[0].from,right=edges[1].from.nodeId===n?edges[1].to:edges[1].from;if(Math.abs(((bearing(left,common)-bearing(common,right)+540)%360)-180)>35)deny('access_near_pickup_context_not_unique');}}
 const found=new Set(),queue=[rows[0].from.nodeId];while(queue.length){const n=queue.pop();if(found.has(n))continue;found.add(n);for(const s of adjacency.get(n)??[])queue.push(s.from.nodeId,s.to.nodeId);}
 if(found.size!==adjacency.size)deny('access_near_pickup_context_not_unique');
}
// This opt-in is supplied only by the trusted ASAP candidate router. The
// reported accuracy remains observation evidence. A separate bounded25m
// practical graph tolerance may find one road; the full50m-or-larger context
// must still deny forbidden geometry and every plausible alternative.
// Candidate scope/binding is the authority; optional continuity labels only
// identify an actual prior-anchor cache, never generic geometry eligibility.
export function resolveDriverGpsRoadAccessV1(args){
 const {input,segments,completeContext,clock=Date.now}=args,a=input?.access;
 if(a?.kind!=='gps'||!finite(input.latitude)||!finite(input.longitude))deny('access_driver_gps_sample_unbound');
 if(!finite(a.accuracyMeters)||a.accuracyMeters<=0||a.accuracyMeters>100)deny('access_driver_gps_accuracy');
 if(completeContext!==true||!Array.isArray(segments)||segments.length>8192)deny('access_driver_gps_context_incomplete');
 let snap;
 try{snap=resolveRoadAccessCoreV1({...args,nearPickup:true,practicalGps:true,driverJunction:true});}
 catch(error){
  // Static hard guards have already scanned the full original circle. Only
  // the unchanged precise/recent topology proof may remove an unreachable
  // ambiguous alternative; LOW precision never widens that prior policy.
  if(args.prior&&a.accuracyMeters<=25&&['access_parallel_or_junction_ambiguity','access_outlier_or_adjacent_road_ambiguity','access_junction_transition_unproven','access_direction_unproven'].includes(error.message))snap=resolveDriverContinuityV1(args);
  else throw error;
 }
 const e=snap.accessEvidence;
 if(!Array.isArray(e?.wayIds)||e.wayIds.length!==1&&!e.junction)deny('access_driver_gps_context_not_unique');
 const searchRadiusMeters=Math.max(25,a.accuracyMeters),corridor=segments.filter(s=>e.wayIds.includes(s.way)&&projectAccessV1(input,s.from,s.to).meters<=searchRadiusMeters+1e-6),edgeIds=e.junction?[...e.junction.edgeIds]:[...new Set(corridor.map(s=>s.edge))].sort((x,y)=>x-y);
 if(!edgeIds.length||edgeIds.some(id=>!Number.isSafeInteger(id)||id<0))deny('access_driver_gps_context_incomplete');
 const now=clock(),locationConfidence=driverGpsConfidenceV1(a,now),direction=e.direction??(corridor.every(s=>corridor.some(r=>r.from.nodeId===s.to.nodeId&&r.to.nodeId===s.from.nodeId))?'two_way':'directed');
 const continuity=e.kind==='driver_continuity'?{priorCapturedAt:e.priorCapturedAt,priorAccuracyMeters:args.prior.input.access.accuracyMeters,continuityMaxMeters:e.continuityMaxMeters}:null;
 return {...snap,accessEvidence:{...e,kind:'driver_gps_road_context',confidence:'MEDIUM_SAFE',gpsRoad:{roadContext:{wayIds:[...e.wayIds],edgeIds,direction,confidence:'MEDIUM_SAFE',snapMeters:e.snapMeters??0,accuracyMeters:a.accuracyMeters,geometryToleranceMeters:25,searchRadiusMeters,practicalGeometryMatch:(e.snapMeters??0)>a.accuracyMeters+1e-6,locationConfidence,...(e.junction?{junction:e.junction}:{})},...(continuity?{continuity}:{}),observedAt:now,validUntil:Math.min(now+15000,a.capturedAt+30000,continuity?continuity.priorCapturedAt+15000:Infinity)}}};
}

// Only a server operational origin with an opaque current-owner label may use
// the already validated address frontage. The label is not a prior GPS anchor.
// All geometry within the original reported uncertainty remains visible.
export function resolveNearPickupRoadAccessV1({input,pickup,pickupSnap,completeContext,segments,negative,graphVersion,revision,clock=Date.now}){
 const a=input?.access,frontage=pickupSnap?.accessEvidence?.frontage,now=clock();
 if(a?.kind!=='gps'||typeof a.continuityKey!=='string'||!/^[-a-zA-Z0-9_.:]{1,160}$/.test(a.continuityKey)||!finite(input.latitude)||!finite(input.longitude)||!finite(pickup?.latitude)||!finite(pickup?.longitude))deny('access_near_pickup_owner_or_point_unbound');
 if(completeContext!==true||segments.length>8192)deny('access_near_pickup_context_incomplete');
 if(pickupSnap.accessEvidence?.kind!=='address_frontage'||frontage?.schema!=='fluxidi-practical-frontage-v1'||frontage.graphVersion!==graphVersion||frontage.revision!==revision||!finite(frontage.point?.latitude)||!finite(frontage.point?.longitude)||!Array.isArray(frontage.wayIds)||frontage.wayIds.length!==1||!frontage.wayIds.every(Number.isSafeInteger))deny('access_near_pickup_frontage_unbound');
 const measured=p=>{const r=Math.PI/180,h=Math.sin((p.latitude-input.latitude)*r/2)**2+Math.cos(input.latitude*r)*Math.cos(p.latitude*r)*Math.sin((p.longitude-input.longitude)*r/2)**2;return 12742000*Math.asin(Math.min(1,Math.sqrt(h)));},pickupDistanceMeters=measured(pickup),frontageDistanceMeters=measured(frontage.point);
 if(pickupDistanceMeters>100||frontageDistanceMeters>100)deny('access_near_pickup_distance');
 const snap=resolveRoadAccessCoreV1({input,segments,negative,graphVersion,revision,clock,nearPickup:true});
 if(snap.accessEvidence.wayIds.length!==1||snap.accessEvidence.wayIds[0]!==frontage.wayIds[0])deny('access_near_pickup_frontage_conflict');
 // Keep every plausible corridor edge for existing known-closure checks,
 // including pieces beyond the chosen centre snap. Do not change the route.
 const edges=[...new Set(segments.filter(s=>s.way===frontage.wayIds[0]&&projectAccessV1(input,s.from,s.to).meters<=a.accuracyMeters+1e-6).map(s=>s.edge))].sort((a,b)=>a-b);
 return {...snap,accessEvidence:{...snap.accessEvidence,confidence:'MEDIUM_SAFE',kind:'driver_near_pickup',nearPickup:{roadContext:{wayIds:[...snap.accessEvidence.wayIds],edgeIds:edges,direction:snap.accessEvidence.direction??'two_way',confidence:'MEDIUM_SAFE',snapMeters:snap.accessEvidence.snapMeters,pickupDistanceMeters,frontageDistanceMeters,accuracyMeters:a.accuracyMeters},observedAt:now,validUntil:Math.min(now+15000,a.capturedAt+30000)}}};
}

// One previously accepted operational fix, never a location history. The
// caller owns the tenant/session cache; customer targets cannot use it.
export function resolveDriverContinuityV1({input,prior,segments,negative,bans=new Set(),graphVersion,revision,clock=Date.now}){
 const now=clock(),a=input.access??{},pa=prior?.input?.access??{};
 if(a.kind!=='gps'||!prior||prior.graphVersion!==graphVersion||prior.revision!==revision||pa.kind!=='gps'||!finite(pa.accuracyMeters)||pa.accuracyMeters<=0||pa.accuracyMeters>5||!finite(pa.capturedAt)||now-pa.capturedAt>15000||a.capturedAt<=pa.capturedAt||a.capturedAt-pa.capturedAt>15000)deny('access_continuity_expired_or_unbound');
 if(!finite(a.capturedAt)||a.capturedAt>now||now-a.capturedAt>30000||!finite(a.accuracyMeters)||a.accuracyMeters<=0||a.accuracyMeters>25)deny('access_gps_stale_or_accuracy');
 if(a.headingDegrees!=null&&(!finite(a.headingDegrees)||a.headingDegrees<0||a.headingDegrees>=360||!finite(a.speedMetersPerSecond)||a.speedMetersPerSecond<2))deny('access_heading_unreliable');
 const previous=resolveRoadAccessV1({input:prior.input,segments,negative,graphVersion,revision,clock});
 if(JSON.stringify(previous.accessEvidence.wayIds)!==JSON.stringify(prior.snap.accessEvidence.wayIds))deny('access_continuity_anchor_changed');
 const dt=(a.capturedAt-pa.capturedAt)/1000;
 if(!finite(a.speedMetersPerSecond)||!finite(pa.speedMetersPerSecond)||a.speedMetersPerSecond<0||pa.speedMetersPerSecond<0||a.speedMetersPerSecond>15||pa.speedMetersPerSecond>15)deny('access_continuity_motion_unproven');
 if(a.headingDegrees!=null&&pa.headingDegrees!=null&&Math.abs(((a.headingDegrees-pa.headingDegrees+540)%360)-180)>35)deny('access_continuity_heading_change');
 const maxMeters=Math.min(100,Math.max(a.speedMetersPerSecond,pa.speedMetersPerSecond)*dt+dt*dt+pa.accuracyMeters+a.accuracyMeters);
 if(projectAccessV1(input,prior.input,prior.input).meters>maxMeters)deny('access_continuity_movement_implausible');
 if(segments.length>8192)deny('access_continuity_context_limit');
 const legal=s=>s.tags&&!s.tags.denied&&!s.tags.bridge&&!s.tags.tunnel&&(s.tags.layer==null||String(s.tags.layer)==='0')&&(s.tags.level==null||String(s.tags.level)==='0')&&!['private','no','destination','customers','delivery'].includes(s.tags.access)&&!['motorway','motorway_link','trunk','trunk_link'].includes(s.tags.highway);
 const byId=new Map(segments.map(s=>[s.edge,s])),out=new Map(),dist=new Map(),queue=[];
 for(const s of segments)if(legal(s)){if(!out.has(s.from.nodeId))out.set(s.from.nodeId,[]);out.get(s.from.nodeId).push(s);}
 const seeds=previous.kind==='segment'?previous.alternatives:[];
 for(const s of seeds)dist.set(s.edge,-s.fraction*s.meters);
 if(previous.kind==='node')for(const s of out.get(previous.node.nodeId)??[])dist.set(s.edge,0);
 queue.push(...dist.keys());let expansions=0;
 while(queue.length){if(++expansions>16384)deny('access_continuity_search_limit');const k=queue.shift(),s=byId.get(k);if(!s||!legal(s))continue;const end=dist.get(k)+s.lengthMeters;if(end>maxMeters)continue;for(const next of out.get(s.to.nodeId)??[]){if(bans.has(k+':'+next.edge))continue;if(!dist.has(next.edge)||end<dist.get(next.edge)){dist.set(next.edge,end);queue.push(next.edge);}}}
 const candidates=[];
 for(const s of segments){if(!legal(s)||!dist.has(s.edge))continue;const p=projectAccessV1(input,s.from,s.to),progress=dist.get(s.edge)+p.fraction*s.lengthMeters;if(p.meters>a.accuracyMeters+1e-6||progress< -1e-6||progress>maxMeters)continue;if(a.headingDegrees!=null&&Math.abs(((a.headingDegrees-bearing(s.from,s.to)+540)%360)-180)>35)continue;candidates.push({...s,...p});}
 const physical=new Map();for(const s of candidates){const key=[Math.min(s.from.nodeId,s.to.nodeId),Math.max(s.from.nodeId,s.to.nodeId)].join(':');if(!physical.has(key))physical.set(key,[]);physical.get(key).push(s);}
 if(!physical.size||new Set(candidates.map(s=>s.way)).size!==1)deny('access_continuity_not_unique');
 // Adjacent pieces of the same source carriageway may straddle one node.
 // Separate parallel pieces or a hairpin are not one proven local corridor.
 if(physical.size>1){const adjacency=new Map();for(const rows of physical.values()){const s=rows[0];for(const n of[s.from.nodeId,s.to.nodeId]){if(!adjacency.has(n))adjacency.set(n,[]);adjacency.get(n).push(s);}}for(const[n,rows]of adjacency){if(rows.length>2)deny('access_continuity_not_unique');if(rows.length===2){const common=rows[0].from.nodeId===n?rows[0].from:rows[0].to,left=rows[0].from.nodeId===n?rows[0].to:rows[0].from,right=rows[1].from.nodeId===n?rows[1].to:rows[1].from;if(Math.abs(((bearing(left,common)-bearing(common,right)+540)%360)-180)>35)deny('access_continuity_not_unique');}}const found=new Set(),q=[candidates[0].from.nodeId];while(q.length){const n=q.pop();if(found.has(n))continue;found.add(n);for(const s of adjacency.get(n)??[])q.push(s.from.nodeId,s.to.nodeId);}if(found.size!==adjacency.size)deny('access_continuity_not_unique');}
 const rows=candidates;
 // Re-run every static hard guard using the now topology-proven physical
 // candidates. Forbidden geometry remains fully visible; no larger envelope.
 const local=resolveRoadAccessV1({input,segments:rows,negative,graphVersion,revision,clock});
 return {...local,accessEvidence:{...local.accessEvidence,kind:'driver_continuity',priorCapturedAt:pa.capturedAt,continuityMaxMeters:maxMeters},continuityOnly:true};
}
