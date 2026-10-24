import {foldStreetV1,resolvePracticalFrontageV1} from './practical_frontage_v1.mjs';
import {projectAccessV1} from './national_road_access_v1.mjs';
import {officialTerminalFrontageVerifiedV1} from './official_address_route_point_v1.mjs';
import {configuredSiteFrontageVerifiedV1} from './configured_site_access_v1.mjs';
const trustedRows=new WeakSet();
const fail=s=>{throw Error(s);},finite=Number.isFinite;
const point=(nodeId,c)=>({nodeId,longitude:c[0],latitude:c[1]});
const digest=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
async function terminalDescriptors({index,input,manifest,storage,cache,metrics}){
 if(index.graphVersion!==manifest.graphVersion)fail('terminal_index_invalid');
 if(index.schema==='fluxidi-national-terminal-index-v1'){
  if(!Array.isArray(index.ways)||index.ways.length>4096)fail('terminal_index_invalid');
  return index.ways;
 }
 // Name-hash shards extend the existing immutable index without loading the
 // country's terminal roads for every address or raising candidate/cache caps.
 if(index.schema!=='fluxidi-national-terminal-index-v2'||index.shardAlgorithm!=='sha256-fold-street-prefix-2'||!index.shards||Array.isArray(index.shards)||Object.keys(index.shards).length>256)fail('terminal_index_invalid');
 const prefix=(await digest(new TextEncoder().encode(foldStreetV1(input.address.street)))).slice(0,2),desc=index.shards[prefix];
 if(!desc)return [];
 if(!new RegExp('^terminals/indexes/'+prefix+'-[a-f0-9]{64}\\.json$').test(desc.key)||!Number.isSafeInteger(desc.bytes)||desc.bytes<1||desc.bytes>1048576||!/^[a-f0-9]{64}$/.test(desc.sha256))fail('terminal_shard_descriptor_invalid');
 const data=await cache.load('terminal-index:'+manifest.graphVersion+':'+desc.sha256,async()=>{
  metrics.graphStorageReads++;metrics.terminalIndexReads=(metrics.terminalIndexReads??0)+1;
  const bytes=new Uint8Array(await storage.getObject(desc.key));metrics.bytesLoaded+=bytes.length;
  if(bytes.length!==desc.bytes)fail('terminal_shard_size');
  if(await digest(bytes)!==desc.sha256)fail('terminal_shard_hash');
  return {...JSON.parse(new TextDecoder().decode(bytes)),residentBytes:bytes.length*6};
 },metrics);
 if(data.schema!=='fluxidi-national-terminal-shard-v1'||data.prefix!==prefix||data.graphVersion!==index.graphVersion||data.sourceSha256!==index.sourceSha256||!Array.isArray(data.ways)||data.ways.length>4096)fail('terminal_shard_invalid');
 return data.ways;
}
// Immutable source-road attachment at an actual journey endpoint. These edges
// NEVER enter the national through graph, portal overlay or ordinary GPS snap.
export async function readNationalTerminalContextV1({input,manifest,storage,cache,metrics,maxWays=4096}){
 const index=manifest.terminalAccess;
 if(!input.address||!index)return null;
 const descriptors=await terminalDescriptors({index,input,manifest,storage,cache,metrics});
 const name=foldStreetV1(input.address.street),matches=descriptors.filter(w=>w.names.some(n=>foldStreetV1(n)===name)&&input.longitude>=w.bbox[0]-.002&&input.longitude<=w.bbox[2]+.002&&input.latitude>=w.bbox[1]-.001&&input.latitude<=w.bbox[3]+.001);
 if(!matches.length)return null;
 if(!Number.isSafeInteger(maxWays)||maxWays<1||matches.length>maxWays)fail('terminal_candidate_limit');
 const rows=[];
 for(const desc of matches){
  if(!Number.isSafeInteger(desc.way)||!/^terminals\/[0-9]+-[a-f0-9]{64}\.json$/.test(desc.key)||!Number.isSafeInteger(desc.bytes)||desc.bytes<1||desc.bytes>1048576||!/^[a-f0-9]{64}$/.test(desc.sha256))fail('terminal_descriptor_invalid');
  const data=await cache.load('terminal:'+manifest.graphVersion+':'+desc.sha256,async()=>{metrics.graphStorageReads++;metrics.terminalObjectReads=(metrics.terminalObjectReads??0)+1;const value=await storage.getObject(desc.key),bytes=new Uint8Array(value);metrics.bytesLoaded+=bytes.length;if(bytes.length!==desc.bytes)fail('terminal_object_size');const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');if(hash!==desc.sha256)fail('terminal_object_hash');return {...JSON.parse(new TextDecoder().decode(bytes)),residentBytes:bytes.length*6};},metrics);
  if(data.schema!=='fluxidi-national-terminal-way-v1'||data.graphVersion!==manifest.graphVersion||data.way!==desc.way||data.sourceSha256!==index.sourceSha256||!Array.isArray(data.edges)||data.edges.length>20000||!Array.isArray(data.anchors)||data.anchors.length>2000||!Array.isArray(data.bans))fail('terminal_object_invalid');
  if(data.connectorEdges!==undefined&&(!Array.isArray(data.connectorEdges)||data.connectorEdges.length+data.edges.length>20000||!Array.isArray(data.terminalComponentWays)||data.terminalComponentWays.length>4096||!data.terminalComponentWays.includes(data.way)||data.connectorEdges.some(e=>e.way===data.way||!data.terminalComponentWays.includes(e.way))))fail('terminal_component_invalid');
  rows.push({...data,objectDescriptor:{way:desc.way,key:desc.key,bytes:desc.bytes,sha256:desc.sha256}});
 }
 trustedRows.add(rows);return rows;
}
export async function resolveNationalTerminalV1({input,manifest,storage,segments,negative,role,cache,metrics,frontageOverride=null,sourceRows=null}){
 if(!input.address||!manifest.terminalAccess)return null;
 if(!['origin','destination'].includes(role))fail('terminal_endpoint_role_required');
 if(sourceRows&&!trustedRows.has(sourceRows)||frontageOverride&&!officialTerminalFrontageVerifiedV1(frontageOverride)&&!configuredSiteFrontageVerifiedV1(frontageOverride))fail('terminal_source_context_unproven');
 const rows=sourceRows??await readNationalTerminalContextV1({input,manifest,storage,cache,metrics});if(!rows?.length)return null;
 const index=manifest.terminalAccess,virtual=rows.flatMap(r=>r.edges.map(e=>({...e,tags:r.frontageTags,way:r.way}))),all=[...segments,...virtual];
 // Optional override is a SERVER call argument from the independently proven
 // official-access resolver, never read from input/client JSON. Directed local
 // search, anchors, source hash, foreign negative context and turns still run.
 const frontage=frontageOverride??resolvePracticalFrontageV1({input,segments:all,graphVersion:manifest.graphVersion,revision:manifest.accessContext.revision});
 if(frontage.graphVersion!==manifest.graphVersion||frontage.revision!==manifest.accessContext.revision||!Array.isArray(frontage.wayIds)||!Number.isFinite(frontage.point?.latitude)||!Number.isFinite(frontage.point?.longitude))fail('terminal_frontage_unproven');
 const selected=rows.filter(r=>frontage.wayIds.includes(r.way));
 if(selected.length!==1)fail('terminal_frontage_unproven');
 const data=selected[0],bans=new Set(data.bans),outgoing=new Map(),incoming=new Map();
 const primary=virtual.filter(e=>e.way===data.way),network=[...primary,...(data.connectorEdges??[])];
 for(const n of negative)if(n[0]!==data.way&&projectAccessV1(frontage.point,{longitude:n[2],latitude:n[3]},{longitude:n[4],latitude:n[5]}).meters<=.1)fail('terminal_conflicting_restriction');
 for(const e of network){
  if(!Number.isSafeInteger(e.edge)||!finite(e.seconds)||e.seconds<0||!finite(e.lengthMeters)||e.lengthMeters<0)fail('terminal_edge_invalid');
  if(!outgoing.has(e.from.nodeId))outgoing.set(e.from.nodeId,[]);outgoing.get(e.from.nodeId).push(e);
  if(!incoming.has(e.to.nodeId))incoming.set(e.to.nodeId,[]);incoming.get(e.to.nodeId).push(e);
 }
 const alternatives=[];
 // The local source-way search is bounded and edge-state aware. The portal
 // anchor is an existing national directed edge, preserving the NEXT turn.
 // Restrictions at the source/national junction are applied before joining.
 for(const e of primary){
  const p=projectAccessV1(frontage.point,e.from,e.to);if(p.meters>.1)continue;
  const reverse=role==='destination',initialFraction=reverse?p.fraction:1-p.fraction;
  const first={id:e.edge,terminalObject:data.objectDescriptor,...(e.way!=null?{way:e.way}:{}),...(e.ordinal!=null?{ordinal:e.ordinal}:{}),...(e.direction!=null?{direction:e.direction}:{}),seconds:e.seconds*initialFraction,distanceMeters:e.lengthMeters*initialFraction,...(e.speedProfile?{speedProfile:e.speedProfile}:{}),partial:true};
  const start=reverse?e.from.nodeId:e.to.nodeId,queue=[{node:start,last:e.edge,seconds:first.seconds,meters:first.distanceMeters,edges:[first],geometry:reverse?[e.from,frontage.point]:[frontage.point,e.to]}],best=new Map();let visits=0;
  while(queue.length){queue.sort((a,b)=>a.seconds-b.seconds||a.meters-b.meters);const v=queue.shift(),key=v.node+':'+v.last;if(best.has(key)&&best.get(key)<=v.seconds)continue;best.set(key,v.seconds);if(++visits>20000)fail('terminal_search_limit');
   for(const a of data.anchors){
    if(reverse?a.to!==v.node:a.from!==v.node)continue;
    if(bans.has(reverse?a.id+':'+v.last:v.last+':'+a.id))continue;
    const node=reverse?{...a.fromPoint,nodeId:a.from,finish:{edge:a.id,fraction:1,point:a.toPoint}}:{...a.toPoint,nodeId:a.to,incomingEdge:a.id,initialFraction:1,startPoint:a.fromPoint};
    alternatives.push({node,terminalLeg:{seconds:v.seconds,distanceMeters:v.meters,edgeSequence:v.edges,geometry:v.geometry},anchorEdge:a.id});
   }
   for(const next of (reverse?incoming:outgoing).get(v.node)??[]){
    if(bans.has(reverse?next.edge+':'+v.last:v.last+':'+next.edge))continue;
    const leg={id:next.edge,terminalObject:data.objectDescriptor,...(next.way!=null?{way:next.way}:{}),...(next.ordinal!=null?{ordinal:next.ordinal}:{}),...(next.direction!=null?{direction:next.direction}:{}),seconds:next.seconds,distanceMeters:next.lengthMeters,...(next.speedProfile?{speedProfile:next.speedProfile}:{})};
    queue.push({node:reverse?next.from.nodeId:next.to.nodeId,last:next.edge,seconds:v.seconds+next.seconds,meters:v.meters+next.lengthMeters,edges:reverse?[leg,...v.edges]:[...v.edges,leg],geometry:reverse?[next.from,...v.geometry]:[...v.geometry,next.to]});
   }
  }
 }
 if(!alternatives.length)fail('terminal_no_legal_national_connection');
 if(alternatives.length>2048)fail('terminal_portal_limit');
 return {kind:'terminal',alternatives,graphVersion:manifest.graphVersion,accessEvidence:{kind:'address_frontage',wayIds:[data.way],frontage,terminal:{schema:data.schema,revision:index.revision,way:data.way,role,sourceSha256:data.sourceSha256,throughAccess:false}}};
}
