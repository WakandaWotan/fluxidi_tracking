import {DirectedRoadGraph} from './routing_evidence_core.mjs';
import {FluxidiRoutingCore} from './routing_core_v1.mjs';
import {createRegionalManyToOneV1} from './reliable_regional_many_to_one_v1.mjs';
import {createReliableGpsRoadMatcherV1} from './reliable_gps_road_match_v1.mjs';
const valid=p=>p&&Number.isFinite(p.latitude)&&Number.isFinite(p.longitude)&&Math.abs(p.latitude)<=90&&Math.abs(p.longitude)<=180;
const project=(p,a,b)=>{
 const x=111195*Math.cos(p.latitude*Math.PI/180),y=111195;
 const dx=(b.longitude-a.longitude)*x,dy=(b.latitude-a.latitude)*y;
 const t=Math.max(0,Math.min(1,((p.longitude-a.longitude)*x*dx+(p.latitude-a.latitude)*y*dy)/(dx*dx+dy*dy||1)));
 const point={latitude:a.latitude+(b.latitude-a.latitude)*t,longitude:a.longitude+(b.longitude-a.longitude)*t};
 return {t,point,distanceMeters:Math.hypot((p.longitude-point.longitude)*x,(p.latitude-point.latitude)*y)};
};

// Access connectors cannot be inferred from GPS proximity. This narrow adapter
// accepts points actually on a mapped road (10cm numerical tolerance) only.
// It splits an ephemeral graph; the original graph and turn states stay intact.
export function createReliableOsmPointRoutesV1(corridor,{clock=Date.now}={}){
 const {graph,coordinates,turns}=corridor;
 const indexStarted=performance.now();
 const metrics={spatialIndexBuilds:1,spatialIndexMs:0,pickupSnapMs:0,originSnapMs:0,targetPrepareMs:0,routeEvidenceMs:0,pointGraphMs:0,snapQueries:0,nodeSnaps:0,edgeSnaps:0,pickupSnaps:0,originSnaps:0,graphReuseHits:0,pointGraphBuilds:0,pointContextHits:0,batchQueries:0,trafficLookups:0,providerCalls:0};
 const grid=new Map(),nodeGrid=new Map(),overflow=[],step=.00025,incident=new Set();let gridEntries=0;
 const cell=(lat,lon)=>Math.floor(lat/step)+':'+Math.floor(lon/step);
 for(let i=0;i<coordinates.length;i++){const p=coordinates[i],k=cell(p.latitude,p.longitude);if(!nodeGrid.has(k))nodeGrid.set(k,[]);nodeGrid.get(k).push(i);}
 for(const e of graph.edges){if(e.disabled)continue;incident.add(e.from);incident.add(e.to);
  const a=coordinates[e.from],b=coordinates[e.to],xmin=Math.floor(Math.min(a.latitude,b.latitude)/step)-1,xmax=Math.floor(Math.max(a.latitude,b.latitude)/step)+1,ymin=Math.floor(Math.min(a.longitude,b.longitude)/step)-1,ymax=Math.floor(Math.max(a.longitude,b.longitude)/step)+1;
  const count=(xmax-xmin+1)*(ymax-ymin+1);
  if(count>5000||gridEntries+count>500000){overflow.push(e.id);continue;}
  for(let x=xmin;x<=xmax;x++)for(let y=ymin;y<=ymax;y++){const k=x+':'+y;if(!grid.has(k))grid.set(k,[]);grid.get(k).push(e.id);gridEntries++;}
 }
 metrics.spatialIndexMs=performance.now()-indexStarted;
 const edgeCandidates=p=>[...(grid.get(cell(p.latitude,p.longitude))||[]),...overflow];
 const meters=(a,b)=>{const r=x=>x*Math.PI/180,h=Math.sin(r(b.latitude-a.latitude)/2)**2+Math.cos(r(a.latitude))*Math.cos(r(b.latitude))*Math.sin(r(b.longitude-a.longitude)/2)**2;return 12742000*Math.asin(Math.min(1,Math.sqrt(h)));};
 const decorate=(result,snaps,version)=>({...result,graphVersion:graph.version,queryGraphVersion:version,snaps,source:'open-regional-graph',routeScope:'on-road-point-to-point',snapAccessCost:'ZERO_ON_ROAD_ONLY',staticEtaOnly:true,pickupEtaCertified:false,trafficCalibration:null});
 const prepared=createRegionalManyToOneV1({graph,core:corridor.core,coordinates,clock});
 function diagnostics(){return {...metrics,spatialGridEntries:gridEntries,spatialGridCells:grid.size,spatialOverflowEdges:overflow.length,prepared:prepared.diagnostics()};}

 function snap(point){
  if(!valid(point))throw Error('osm_point_invalid');
  metrics.snapQueries++;
  const nearby=[],lat=Math.floor(point.latitude/step),lon=Math.floor(point.longitude/step);
  // Longitude cells are small at the poles; inspect a complete metric envelope.
  const lonRadius=Math.ceil(.1/(111195*Math.max(1e-6,Math.cos(point.latitude*Math.PI/180))*step))+1;
  if(lonRadius>1000){for(let i=0;i<coordinates.length;i++){const d=meters(point,coordinates[i]);if(d<=.1)nearby.push({node:i,distanceMeters:d});}}
  else for(let x=lat-1;x<=lat+1;x++)for(let y=lon-lonRadius;y<=lon+lonRadius;y++)for(const node of nodeGrid.get(x+':'+y)||[]){const d=meters(point,coordinates[node]);if(d<=.1)nearby.push({node,distanceMeters:d});}
  nearby.sort((a,b)=>a.distanceMeters-b.distanceMeters||a.node-b.node);
  if(nearby.length){const nearest=nearby[0];if(!incident.has(nearest.node))throw Error('osm_access_unproven');if(nearby.length>1)throw Error('osm_snap_ambiguous');metrics.nodeSnaps++;return {...nearest,point:coordinates[nearest.node],kind:'node',confidence:1,ambiguous:false,graphVersion:graph.version};}

  const matches=new Map();
  for(const id of edgeCandidates(point)){const e=graph.edges[id];
   if(e.disabled)continue;
   const p=project(point,coordinates[e.from],coordinates[e.to]);
   if(p.distanceMeters>0.1||p.t<=1e-9||p.t>=1-1e-9)continue;
   const key=[e.osmWay,...[e.from,e.to].sort((a,b)=>a-b)].join(':');
   if(!matches.has(key)||p.distanceMeters<matches.get(key).distanceMeters)matches.set(key,{...p,edge:e.id});
  }
  if(matches.size!==1)throw Error(matches.size?'osm_snap_ambiguous':'osm_access_unproven');
  const selected=matches.values().next().value;
  // Preserve the caller's exact on-road coordinate when projection differs
  // only by floating point roundoff; no access connector is added.
  if(selected.distanceMeters<1e-7)selected.point={...point};
  metrics.edgeSnaps++;return {...selected,kind:'edge',confidence:1,ambiguous:false,graphVersion:graph.version};
 }
 async function routeMany({origins,destination,scope,graphVersion=graph.version,options={},trafficRevision='static'}){
  if(graphVersion!==graph.version)throw Error('osm_graph_revision_stale');
  if(!Array.isArray(origins)||origins.length>5000)throw Error('osm_origin_batch_invalid');
  metrics.batchQueries++;metrics.pickupSnaps++;const pickupAt=performance.now(),target=snap(destination);metrics.pickupSnapMs+=performance.now()-pickupAt;const originsAt=performance.now();
  const snaps=origins.map(origin=>{metrics.originSnaps++;try{return {snap:snap(origin)};}catch(error){return {error:error.message};}});
  metrics.originSnapMs+=performance.now()-originsAt;const prepareAt=performance.now();
  let query=null,version=graphVersion;
  const validSnaps=[...snaps.flatMap(x=>x.snap?[x.snap]:[]),target];
  if(validSnaps.every(x=>x.kind==='node'))query=prepared.prepare({target:target.node,scope,options,trafficRevision,graphVersion});
  else{
   const key=JSON.stringify([graphVersion,scope?.tenant_id,scope?.company_id,scope?.policyRevision,trafficRevision,target.point,validSnaps.filter(x=>x.kind==='edge').map(x=>[x.edge,x.point]).sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)))]);
   let context;
   if(lastPoints?.key===key&&clock()>=lastPoints.at&&clock()<lastPoints.at+60000){metrics.pointContextHits++;context=lastPoints.context;}
   else{context=await splitBatch(validSnaps);lastPoints={key,at:clock(),context};}
   version=context.graph.version;
   for(const p of validSnaps)if(p.kind==='edge')p.node=context.nodesByPoint.get(pointKey(p));
   query=context.prepared.prepare({target:target.node,scope,options,trafficRevision,graphVersion:version});
  }
  metrics.targetPrepareMs+=performance.now()-prepareAt;const routesAt=performance.now();
  const results=[];
  for(let i=0;i<snaps.length;i++){
   const entry=snaps[i];if(entry.error){results.push({ok:false,reason:entry.error});continue;}
   try{
    let route;
    metrics.graphReuseHits++;route=decorate(await query.route(entry.snap.node),[entry.snap,target],version);
    results.push({ok:true,route});
   }catch(error){results.push({ok:false,reason:error.message});}
  }
  metrics.routeEvidenceMs+=performance.now()-routesAt;
  return {graphVersion,trafficRevision,results,diagnostics:diagnostics(),pickupEtaCertified:false};
 }
 let lastPoints=null;
 const pointKey=p=>JSON.stringify([graph.edges[p.edge].osmWay,...[graph.edges[p.edge].from,graph.edges[p.edge].to].sort((a,b)=>a-b),p.point.latitude,p.point.longitude]);
 async function splitBatch(snaps){
  const graphAt=performance.now();metrics.pointGraphBuilds++;
  const unique=new Map(snaps.filter(p=>p.kind==='edge').map(p=>[pointKey(p),p]));
  const nodes=[...coordinates],nodesByPoint=new Map(),cutsByEdge=new Map();
  for(const[key,p]of [...unique].sort(([a],[b])=>a.localeCompare(b))){const node=nodes.length;nodes.push(p.point);nodesByPoint.set(key,node);const source=graph.edges[p.edge];
   for(const e of graph.edges)if(source.osmWay===e.osmWay&&((source.from===e.from&&source.to===e.to)||(source.from===e.to&&source.to===e.from))){if(!cutsByEdge.has(e.id))cutsByEdge.set(e.id,[]);cutsByEdge.get(e.id).push({t:source.from===e.from?p.t:1-p.t,node});}
  }
  const edges=[],first=[],last=[],incoming=new Map(),outgoing=new Map();
  for(const e of graph.edges){const cuts=[{t:0,node:e.from},...(cutsByEdge.get(e.id)||[]),{t:1,node:e.to}].sort((a,b)=>a.t-b.t);first[e.id]=edges.length;
   for(let i=1;i<cuts.length;i++){const u=cuts[i-1],v=cuts[i];if(v.t-u.t<1e-12)continue;
    const id=edges.length;edges.push({...e,id:undefined,from:u.node,to:v.node,minimum:e.minimum*(v.t-u.t),distanceMeters:e.distanceMeters*(v.t-u.t),geometry:[nodes[u.node],nodes[v.node]],sourceEdge:e.id});
    if(v.node>=coordinates.length){if(!incoming.has(v.node))incoming.set(v.node,[]);incoming.get(v.node).push(id);}
    if(u.node>=coordinates.length){if(!outgoing.has(u.node))outgoing.set(u.node,[]);outgoing.get(u.node).push(id);}
   }last[e.id]=edges.length-1;
  }
  const queryTurns=turns.map(t=>({...t,fromEdge:last[t.fromEdge],toEdge:first[t.toEdge]}));
  for(const[node,ins]of incoming)for(const i of ins)for(const j of outgoing.get(node)||[])if(edges[i].sourceEdge!==edges[j].sourceEdge)queryTurns.push({fromEdge:i,toEdge:j,disabled:true});
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify([...nodesByPoint])));
  const version=graph.version+':points-batch:'+Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,'0')).join('');
  const temporary=new DirectedRoadGraph({nodes:nodes.length,edges,turns:queryTurns,version}),core=new FluxidiRoutingCore({graph:temporary,coordinates:nodes,clock});
  metrics.pointGraphMs+=performance.now()-graphAt;
  return {graph:temporary,nodesByPoint,prepared:createRegionalManyToOneV1({graph:temporary,core,coordinates:nodes,clock})};
 }

 let gpsMatcher=null;
 // Explicit diagnostic/ingest contract. A GPS measurement match does not
 // attest pickup/building access and cannot replace the strict route snap.
 const matchGps=sample=>(gpsMatcher??=createReliableGpsRoadMatcherV1(corridor,{clock})).match(sample);
 return Object.freeze({kind:'STATIC_REGIONAL_POINTS_V1',snap,matchGps,routeMany,diagnostics,async route({origin,destination,scope,graphVersion=graph.version,options={}}){
  if(graphVersion!==graph.version)throw Error('osm_graph_revision_stale');
  const a=snap(origin),b=snap(destination);
  if(a.kind==='node'&&b.kind==='node'){metrics.graphReuseHits++;const result=await corridor.core.routeEvidence({...scope,graphVersion,fromNode:a.node,toNode:b.node,from:a.point,to:b.point,profile:'car',options,leg:'pickup',departureSemantics:'static'});return decorate(result,[a,b],graphVersion);}
  metrics.pointGraphBuilds++;const nodes=[...coordinates],split=[];
  for(const p of [a,b]){
   if(p.kind==='node')continue;
   const same=split.find(q=>Math.abs(q.point.latitude-p.point.latitude)<1e-12&&Math.abs(q.point.longitude-p.point.longitude)<1e-12&&q.edge===p.edge);
   p.node=same?.node??nodes.length;
   if(!same){nodes.push(p.point);split.push(p);}
  }
  const edges=[],first=[],last=[];
  for(const e of graph.edges){
   const cuts=[{t:0,node:e.from},{t:1,node:e.to}];
   for(const p of split){const source=graph.edges[p.edge];if(source.osmWay!==e.osmWay||!((source.from===e.from&&source.to===e.to)||(source.from===e.to&&source.to===e.from)))continue;cuts.push({t:source.from===e.from?p.t:1-p.t,node:p.node});}
   cuts.sort((x,y)=>x.t-y.t);first[e.id]=edges.length;
   for(let i=1;i<cuts.length;i++){const u=cuts[i-1],v=cuts[i];if(v.t-u.t<1e-12)continue;edges.push({...e,id:undefined,from:u.node,to:v.node,minimum:e.minimum*(v.t-u.t),distanceMeters:e.distanceMeters*(v.t-u.t),geometry:[nodes[u.node],nodes[v.node]],sourceEdge:e.id});}
   last[e.id]=edges.length-1;
  }
  const version=graph.version+':points:'+JSON.stringify([a.point,b.point]);
  const queryTurns=turns.map(t=>({...t,fromEdge:last[t.fromEdge],toEdge:first[t.toEdge]}));
  // Splitting must not create a new U-turn or cross-carriageway junction.
  for(let node=coordinates.length;node<nodes.length;node++){
   for(let i=0;i<edges.length;i++)if(edges[i].to===node)
    for(let j=0;j<edges.length;j++)if(edges[j].from===node&&edges[i].sourceEdge!==edges[j].sourceEdge)queryTurns.push({fromEdge:i,toEdge:j,disabled:true});
  }
  const temporary=new DirectedRoadGraph({nodes:nodes.length,edges,turns:queryTurns,version});
  const core=new FluxidiRoutingCore({graph:temporary,coordinates:nodes});
  const result=await core.routeEvidence({...scope,graphVersion:version,fromNode:a.node,toNode:b.node,from:a.point,to:b.point,profile:'car',options,leg:'pickup',departureSemantics:'static'});
  return {...result,graphVersion:graph.version,queryGraphVersion:version,snaps:[a,b],source:'open-regional-graph',routeScope:'on-road-point-to-point',snapAccessCost:'ZERO_ON_ROAD_ONLY',staticEtaOnly:true,pickupEtaCertified:false,trafficCalibration:null};
 }});
}
