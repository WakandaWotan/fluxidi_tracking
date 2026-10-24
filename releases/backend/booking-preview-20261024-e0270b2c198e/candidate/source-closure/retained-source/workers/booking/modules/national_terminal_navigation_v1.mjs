// Navigation metadata for the existing endpoint-only source-road component.
// Never creates routing access, edges or through-road permissions.
const fail=r=>{throw Error(r);},hex=s=>typeof s==='string'&&/^[a-f0-9]{64}$/.test(s);
const digest=async b=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',b)),v=>v.toString(16).padStart(2,'0')).join('');
export function createTerminalNavigationReaderV1({manifest,storage,cache,metrics}){
 const index=manifest.terminalAccess,sources=new Map(),wayRecords=new Map();let retained=0;
 const hold=size=>{retained+=size;if(retained>8*1024*1024)fail('navigation_terminal_metadata_limit');};
 async function pinned(desc,prefix){
  if(!hex(desc?.sha256)||!Number.isSafeInteger(desc.bytes)||desc.bytes<1||desc.bytes>1048576)fail('navigation_terminal_descriptor');
  return cache.load(prefix+':'+manifest.graphVersion+':'+desc.sha256,async()=>{
   metrics.graphStorageReads++;metrics.terminalNavigationReads=(metrics.terminalNavigationReads??0)+1;
   const b=new Uint8Array(await storage.getObject(desc.key));metrics.bytesLoaded+=b.length;
   if(b.length!==desc.bytes||await digest(b)!==desc.sha256)fail('navigation_terminal_integrity');
   return {...JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(b)),residentBytes:b.length*6};
  },metrics);
 }
 async function wayRecord(way){
  if(wayRecords.has(way))return wayRecords.get(way);
  if(!Number.isSafeInteger(way)||way<1||index?.schema!=='fluxidi-national-terminal-index-v2'||index.graphVersion!==manifest.graphVersion||index.wayShardAlgorithm!=='positive-way-id-modulo-256'||!index.wayShards||Object.keys(index.wayShards).length>256)fail('navigation_terminal_index');
  const prefix=(way%256).toString(16).padStart(2,'0'),desc=index.wayShards[prefix];
  if(!new RegExp('^terminals/way-indexes/'+prefix+'-[a-f0-9]{64}\\.json$').test(desc?.key??''))fail('navigation_terminal_descriptor');
  const shard=await pinned(desc,'terminal-way-index');
  if(shard.schema!=='fluxidi-national-terminal-way-index-shard-v1'||shard.prefix!==prefix||shard.graphVersion!==index.graphVersion||shard.sourceSha256!==index.sourceSha256||!Array.isArray(shard.ways)||shard.ways.length>4096)fail('navigation_terminal_index');
  const matches=shard.ways.filter(d=>d.way===way);if(matches.length!==1)fail('navigation_terminal_way_missing');
  const row=matches[0];if(!Array.isArray(row.names)||!row.names.length||row.names.some(n=>typeof n!=='string'||n.length>500)||!row.navigationTags||typeof row.navigationTags!=='object'||Array.isArray(row.navigationTags))fail('navigation_terminal_tags');
  const navigationTags={},unsupported=[];
  for(const [k,v]of Object.entries(row.navigationTags)){if(k.length>100){unsupported.push(k.includes('lanes')?'lanes:unsupported-source-tag':k.startsWith('maxspeed')?'maxspeed:unsupported-source-tag':'unsupported-source-tag');continue;}if(typeof v!=='string'||v.length>2048||/[\r\n\0]/.test(v)){unsupported.push(k);continue;}navigationTags[k]=v;}
  const raw=navigationTags['oneway:motorcar']??navigationTags['oneway:motor_vehicle']??navigationTags['oneway:vehicle']??navigationTags.oneway??(navigationTags.junction==='roundabout'?'yes':'no');
  const oneway=['yes','1','true'].includes(raw)?1:raw==='-1'?-1:0;
  const tags={streetNames:row.names.slice(0,16),oneway};for(const k of ['highway','ref','junction','lanes'])if(typeof navigationTags[k]==='string')tags[k]=navigationTags[k];
  const result={descriptor:row,tags,navigationTags,navigationUnsupported:unsupported,sourceSha256:index.sourceSha256,wayIndexSha256:desc.sha256};
  hold(new TextEncoder().encode(JSON.stringify(result)).length*6);wayRecords.set(way,result);return result;
 }
 async function source(object){
  if(!object||!Number.isSafeInteger(object.way))fail('navigation_terminal_source');
  if(sources.has(object.sha256)){
   const hit=sources.get(object.sha256);if(['way','key','sha256','bytes'].some(k=>hit.descriptor[k]!==object[k]))fail('navigation_terminal_source');return hit;
  }
  const primary=await wayRecord(object.way),desc=primary.descriptor;
  if(object.key!==desc.key||object.sha256!==desc.sha256||object.bytes!==desc.bytes||!/^terminals\/[0-9]+-[a-f0-9]{64}\.json$/.test(desc.key))fail('navigation_terminal_source');
  const data=await pinned(desc,'terminal');
  if(data.schema!=='fluxidi-national-terminal-way-v1'||data.way!==object.way||data.graphVersion!==manifest.graphVersion||data.sourceSha256!==index.sourceSha256||data.throughAccess!==false||!Array.isArray(data.edges)||!Array.isArray(data.connectorEdges??[])||data.edges.length+(data.connectorEdges?.length??0)>20000||!Array.isArray(data.anchors)||data.anchors.length>2000||!Array.isArray(data.bans))fail('navigation_terminal_source');
  hold(desc.bytes*6);const result={data,descriptor:desc,edges:new Map([...data.edges,...(data.connectorEdges??[])].map(e=>[e.edge,e])),bans:new Set(data.bans)};sources.set(object.sha256,result);return result;
 }
 return {async describe(selected,previous){
  const s=await source(selected.terminalObject),e=s.edges.get(selected.id);
  if(!e||e.way!==selected.way||e.ordinal!==selected.ordinal||e.direction!==selected.direction||previous&&previous.toNode!==e.from.nodeId||previous&&s.bans.has(previous.id+':'+selected.id))fail('navigation_terminal_edge_binding');
  const own=await wayRecord(e.way);
  // The source component proves its legal directed path, not exhaustive physical
  // junction branches. Do not fabricate lane arrows or numbered roundabout exits.
  return {row:{id:e.edge,way:e.way,ordinal:e.ordinal,direction:e.direction,fullDistanceMeters:e.lengthMeters,
   fromNode:e.from.nodeId,toNode:e.to.nodeId,from:{longitude:e.from.longitude,latitude:e.from.latitude},to:{longitude:e.to.longitude,latitude:e.to.latitude},
   tags:own.tags,options:[],physicalOptions:[],junctionComplete:false,physicalJunctionComplete:false,
   terminalMetadata:{sourceSha256:own.sourceSha256,objectSha256:own.wayIndexSha256,terminalObjectSha256:selected.terminalObject.sha256,throughAccess:false},
   navigationTags:own.navigationTags,navigationUnsupported:own.navigationUnsupported},source:s};
 }};
}
