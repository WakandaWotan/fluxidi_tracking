import {projectAccessV1} from './national_road_access_v1.mjs';
import {navigationRoadNameV1,navigationDestinationV1,navigationLaneIntersectionV1} from './national_navigation_signals_v1.mjs';
// Formats the selected national route for the existing Fluxidi guidance parser.
// Street/ref/junction facts come from sealed graph metadata. A lane count is
// never promoted into a lane indication. No I/O, provider or path selection.
const fail=s=>{throw Error(s);};
const finite=n=>typeof n==='number'&&Number.isFinite(n)&&n>=0;
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id&&a?.graphVersion===b?.graphVersion&&a?.evidenceRevision===b?.evidenceRevision;
const radians=Math.PI/180;
const bearing=(a,b)=>(Math.atan2((b.longitude-a.longitude)*Math.cos((a.latitude+b.latitude)*radians/2),b.latitude-a.latitude)/radians+360)%360;
const delta=(a,b)=>((b-a+540)%360)-180;
const point=p=>p&&Number.isFinite(p.latitude)&&Math.abs(p.latitude)<=90&&Number.isFinite(p.longitude)&&Math.abs(p.longitude)<=180;
const distance=(a,b)=>12742000*Math.asin(Math.min(1,Math.sqrt(Math.sin((b.latitude-a.latitude)*radians/2)**2+Math.cos(a.latitude*radians)*Math.cos(b.latitude*radians)*Math.sin((b.longitude-a.longitude)*radians/2)**2)));
const fold=s=>String(s??'').normalize('NFKD').toLowerCase().replace(/\p{M}/gu,'').replace(/[^\p{L}\p{N}]/gu,'');
const name=(r,language)=>navigationRoadNameV1(r,language);
const circle=r=>r.tags.junction==='roundabout';
const link=r=>['motorway_link','trunk_link'].includes(r.tags.highway);
const main=r=>['motorway','trunk'].includes(r.tags.highway);
const modifier=angle=>Math.abs(angle)>=165?'uturn':Math.abs(angle)<20?'straight':(Math.abs(angle)<45?'slight ':Math.abs(angle)>135?'sharp ':'')+(angle<0?'left':'right');
const translations={
 nl:{depart:'Vertrek',arrive:'Je bent op je bestemming',continue:'Ga verder',left:'Sla linksaf',right:'Sla rechtsaf','slight left':'Houd links aan','slight right':'Houd rechts aan','sharp left':'Sla scherp linksaf','sharp right':'Sla scherp rechtsaf',uturn:'Keer om',roundabout:'Neem de rotonde',exit:'Verlaat de rotonde',ramp:'Neem de afrit',merge:'Voeg in',onto:' naar ',exitNumber:n=>'Neem op de rotonde afrit '+n},
 en:{depart:'Depart',arrive:'You have arrived',continue:'Continue',left:'Turn left',right:'Turn right','slight left':'Keep left','slight right':'Keep right','sharp left':'Turn sharp left','sharp right':'Turn sharp right',uturn:'Make a U-turn',roundabout:'Enter the roundabout',exit:'Exit the roundabout',ramp:'Take the exit',merge:'Merge',onto:' onto ',exitNumber:n=>'At the roundabout, take exit '+n},
 fr:{depart:'Partez',arrive:'Vous êtes arrivé',continue:'Continuez',left:'Tournez à gauche',right:'Tournez à droite','slight left':'Restez à gauche','slight right':'Restez à droite','sharp left':'Tournez complètement à gauche','sharp right':'Tournez complètement à droite',uturn:'Faites demi-tour',roundabout:'Prenez le rond-point',exit:'Quittez le rond-point',ramp:'Prenez la sortie',merge:'Insérez-vous',onto:' vers ',exitNumber:n=>'Au rond-point, prenez la sortie '+n},
 es:{depart:'Salga',arrive:'Ha llegado a su destino',continue:'Continúe',left:'Gire a la izquierda',right:'Gire a la derecha','slight left':'Manténgase a la izquierda','slight right':'Manténgase a la derecha','sharp left':'Gire pronunciadamente a la izquierda','sharp right':'Gire pronunciadamente a la derecha',uturn:'Dé la vuelta',roundabout:'Entre en la rotonda',exit:'Salga de la rotonda',ramp:'Tome la salida',merge:'Incorpórese',onto:' hacia ',exitNumber:n=>'En la rotonda, tome la salida '+n},
 pt:{depart:'Parta',arrive:'Chegou ao destino',continue:'Continue',left:'Vire à esquerda',right:'Vire à direita','slight left':'Mantenha-se à esquerda','slight right':'Mantenha-se à direita','sharp left':'Vire acentuadamente à esquerda','sharp right':'Vire acentuadamente à direita',uturn:'Inverta o sentido',roundabout:'Entre na rotunda',exit:'Saia da rotunda',ramp:'Siga pela saída',merge:'Entre na via',onto:' para ',exitNumber:n=>'Na rotunda, siga pela saída '+n},
};
function checkedRoundaboutExit(roads,start,end){
 if(start===0||end>=roads.length)return null;
 let count=0;
 for(let i=start;i<end;i++)if(!circle(roads[i])||![1,-1].includes(roads[i].tags.oneway))return null;
 for(let i=start+1;i<=end;i++){
  const road=roads[i];if(!road.junctionComplete||road.physicalJunctionComplete!==true||!Array.isArray(road.physicalOptions))return null;
  const exits=road.physicalOptions.filter(o=>o.tags.junction!=='roundabout');
  // Multiple diverging arms at one node need a stronger physical-exit model.
  // Omit the number rather than guess how a posted roundabout counts them.
  if(exits.length>1||exits.some(o=>o.turnAllowed!==true))return null;
  if(exits.length===1)count++;
 }
 return count>0?count:null;
}
export async function nationalNavigationDirectionsV1({route,scope,language='nl',clock=Date.now}){
 const n=route?.navigationEvidence,g=route?.geometry;
 if(n?.schema!=='fluxidi-directed-navigation-evidence-v1'||!same(route,scope)||!same(n,scope)
   ||!finite(route.validUntil)||route.validUntil<=clock()||!finite(route.distanceMeters)||!finite(route.seconds)
   ||!finite(n.staticSeconds)||!Array.isArray(n.edges)||!Array.isArray(n.roads)||n.edges.length!==n.roads.length
   ||!Array.isArray(g)||g.length!==n.edges.length+1||!g.every(point)||n.edges.length>20000)fail('navigation_route_unproven');
 const {edges,roads}=n;
 let meters=0,seconds=0;
 for(let i=0;i<edges.length;i++){
  const e=edges[i],r=roads[i];
  if(!Number.isSafeInteger(e.id)||e.id!==r.id||e.way!==r.way||e.ordinal!==r.ordinal||e.direction!==r.direction
    ||![1,-1].includes(e.direction)||!finite(e.distanceMeters)||!finite(e.seconds)||!point(r.from)||!point(r.to)
    ||!Array.isArray(r.tags?.streetNames)||r.tags.streetNames.some(s=>typeof s!=='string'||s.length>500)
    ||!Array.isArray(r.options)||i>0&&roads[i-1].toNode!==r.fromNode)fail('navigation_edge_evidence_conflict');
  if(e.partial!==true&&(distance(g[i],r.from)>.2||distance(g[i+1],r.to)>.2))fail('navigation_geometry_binding');
  if(!finite(r.fullDistanceMeters))fail('navigation_geometry_binding');
  const start=projectAccessV1(g[i],r.from,r.to),end=projectAccessV1(g[i+1],r.from,r.to);
  if(start.meters>.2||end.meters>.2||end.fraction<start.fraction-1e-9
    ||Math.abs(e.distanceMeters-r.fullDistanceMeters*(end.fraction-start.fraction))>Math.max(.05,r.fullDistanceMeters*1e-6))fail('navigation_geometry_binding');
  meters+=e.distanceMeters;seconds+=e.seconds;
 }
 if(Math.abs(meters-route.distanceMeters)>1e-6*Math.max(1,meters)||Math.abs(seconds-n.staticSeconds)>1e-6*Math.max(1,seconds))fail('navigation_route_totals_conflict');
 const lang=String(language).toLowerCase().split(/[-_]/)[0],t=translations[lang]??translations.nl;
 const events=[];
 if(edges.length)events.push({index:0,type:'depart',modifier:'straight'});
 for(let i=1;i<edges.length;i++){
  const previous=roads[i-1],current=roads[i],angle=delta(bearing(g[i-1],g[i]),bearing(g[i],g[i+1]));
  if(circle(current)&&!circle(previous)){
   let end=i;while(end<roads.length&&circle(roads[end]))end++;
   const exit=checkedRoundaboutExit(roads,i,end);
   events.push({index:i,type:'roundabout',modifier:modifier(angle),...(exit?{exit}:{})});
  }else if(!circle(current)&&circle(previous))events.push({index:i,type:'exit roundabout',modifier:modifier(angle)});
  else if(circle(current))continue;
  else if(main(previous)&&link(current))events.push({index:i,type:'off ramp',modifier:modifier(angle)});
  else if(link(previous)&&main(current))events.push({index:i,type:'merge',modifier:modifier(angle)});
  else {
   const reverse=previous.fromNode,alternatives=current.options.filter(o=>o.toNode!==reverse&&o.id!==current.id);
   const decision=current.junctionComplete&&alternatives.length>0;
   const changed=fold(name(previous,lang))!==fold(name(current,lang));
   if(decision&&Math.abs(angle)>=20)events.push({index:i,type:'turn',modifier:modifier(angle)});
   else if(changed&&(current.way!==previous.way))events.push({index:i,type:'new name',modifier:'straight'});
   else if(navigationLaneIntersectionV1({incoming:previous,chosen:current,location:g[i],bearingBefore:bearing(g[i-1],g[i]),bearingAfter:bearing(g[i],g[i+1])}))events.push({index:i,type:'continue',modifier:modifier(angle)});
  }
 }
 events.push({index:edges.length,type:'arrive',modifier:'straight'});
 const steps=events.map((event,i)=>{
  const end=events[i+1]?.index??event.index,road=roads[event.index],stepEdges=edges.slice(event.index,end);
  const distance=stepEdges.reduce((n,e)=>n+e.distanceMeters,0),staticSeconds=stepEdges.reduce((n,e)=>n+e.seconds,0);
  const duration=n.staticSeconds>0?staticSeconds*route.seconds/n.staticSeconds:0;
  const text=event.type==='depart'?t.depart:event.type==='arrive'?t.arrive:event.type==='roundabout'?(event.exit?t.exitNumber(event.exit):t.roundabout):event.type==='exit roundabout'?t.exit:event.type==='off ramp'?t.ramp:event.type==='merge'?t.merge:event.type==='turn'?t[event.modifier]:t.continue;
  const street=road?name(road,lang):'',instruction=text+(street&&event.type!=='arrive'?t.onto+street:'');
  const at=g[event.index],before=event.index?bearing(g[event.index-1],at):edges.length?bearing(at,g[1]):0,after=event.index<edges.length?bearing(at,g[event.index+1]):before;
  const lanes=road&&event.index>0?navigationLaneIntersectionV1({incoming:roads[event.index-1],chosen:road,location:at,bearingBefore:before,bearingAfter:after}):null;
  const destination=road?navigationDestinationV1(road):null;
  return {distance,duration,name:street,...(road?.tags.ref?{ref:road.tags.ref}:{}),...(destination?{destinations:destination}:{}),
   geometry:{type:'LineString',coordinates:g.slice(event.index,Math.max(event.index+1,end+1)).map(p=>[p.longitude,p.latitude])},
   maneuver:{type:event.type,modifier:event.modifier,location:[at.longitude,at.latitude],bearing_before:before,bearing_after:after,instruction,...(event.exit?{exit:event.exit}:{})},
   banner_instructions:[{distanceAlongGeometry:distance,primary:{text:street||text,type:event.type,modifier:event.modifier,...(event.exit?{exit:event.exit}:{}),components:[{type:'text',text:street||text}]}}],
   intersections:lanes?[lanes]:[],source:'fluxidi-national',lane_guidance:lanes?'source_and_route_bound':'not_proven'};
 });
 const material=JSON.stringify([scope,n.coreEvidenceId,route.evidenceId,n.navigationMetadataSha256??null,g,steps.map(s=>s.maneuver),lang]);
 const routeHash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(material))),b=>b.toString(16).padStart(2,'0')).join('');
 if(route.validUntil<=clock())fail('navigation_route_lease_expired');
 return {ok:true,service:'fluxidi-navigation',version:'national-directions-v1',source:'fluxidi-national',provider_source:null,estimated:true,certified_eta:false,
  route_hash:routeHash,distance_m:route.distanceMeters,duration_s:Math.ceil(route.seconds),geometry:{type:'LineString',coordinates:g.map(p=>[p.longitude,p.latitude])},
  legs:[{distance:route.distanceMeters,duration:route.seconds,steps}],maneuvers:steps.map(s=>({...s.maneuver,location:{lng:s.maneuver.location[0],lat:s.maneuver.location[1]},distance_m:s.distance,duration_s:s.duration})),
  graph_version:scope.graphVersion,evidence_revision:scope.evidenceRevision,valid_until_ms:route.validUntil,cache:'bypass',route_basis:'owned_immutable_route',
  ...(n.navigationMetadataSha256?{navigation_metadata_sha256:n.navigationMetadataSha256}:{}),
  capabilities:{geometry:true,streetNames:true,maneuvers:true,roundabouts:true,exitNumbers:'only_when_proven',laneGuidance:steps.some(s=>s.intersections.some(i=>i.lanes?.length)),speedSigns:false}};
}
