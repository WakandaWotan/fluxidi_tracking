const fail=s=>{throw Error(s);};
const digest=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
const encoder=new TextEncoder(),hash=s=>/^[a-f0-9]{64}$/.test(s??'');
const integer=(n,max)=>Number.isSafeInteger(n)&&n>0&&n<=max;
const plain=o=>o&&typeof o==='object'&&!Array.isArray(o);
const freeze=o=>{if(o&&typeof o==='object'){Object.values(o).forEach(freeze);Object.freeze(o);}return o;};

export async function createNationalNavigationRoadTagsV1({manifestBytes,manifestSha256,graphManifest,graphManifestSha256,readObject,maxCacheDecodedBytes=512000}){
 if(!hash(manifestSha256)||!hash(graphManifestSha256)||!(manifestBytes instanceof Uint8Array)||manifestBytes.byteLength>2000000
  ||await digest(manifestBytes)!==manifestSha256||await digest(encoder.encode(JSON.stringify(graphManifest)))!==graphManifestSha256
  ||typeof readObject!=='function'||!Number.isSafeInteger(maxCacheDecodedBytes)||maxCacheDecodedBytes<0||maxCacheDecodedBytes>2000000)fail('navigation_tags_manifest_integrity');
 const manifest=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(manifestBytes));
 if(manifest.schema!=='fluxidi-navigation-road-tags-publication-v1'||manifest.graphVersion!==graphManifest.graphVersion||manifest.graphManifestSha256!==graphManifestSha256
  ||!hash(manifest.sourceSha256)||manifest.license!=='ODbL-1.0'||typeof manifest.attribution!=='string'||!manifest.attribution
  ||manifest.navigationOnly!==true||manifest.accessCertification!==false||manifest.financialCertification!==false||manifest.graphOrWeightsModified!==false||manifest.fullPublication!==true
  ||!Array.isArray(manifest.partitions)||manifest.partitions.length!==graphManifest.partitions?.length||manifest.partitions.length>16384
  ||!Array.isArray(manifest.tagFields)||manifest.tagFields.some(k=>typeof k!=='string'||k.length>100))fail('navigation_tags_manifest_contract');
 const graphParts=new Map(graphManifest.partitions.map(p=>[p.id,p])),parts=new Map(),allowedFields=new Set(manifest.tagFields);
 for(const p of manifest.partitions){
  if(!/^r[0-3]*$/.test(p.partition)||parts.has(p.partition)||!graphParts.has(p.partition)||p.graphPartitionSha256!==graphParts.get(p.partition).sha256
   ||!hash(p.sha256)||p.key!=='objects/'+p.sha256+'.json.gz'||!integer(p.bytes,2000000)||!integer(p.decodedBytes,4000000)||!Number.isSafeInteger(p.ways)||p.ways<0||p.ways>100000)fail('navigation_tags_partition_contract');
  parts.set(p.partition,freeze(p));
 }
 const cache=new Map(),pending=new Map();let cachedBytes=0,reads=0,cacheHits=0,active=0,waiting=0;
 async function load(partition){
  const d=parts.get(partition);if(!d)fail('navigation_tags_partition_unknown');
  if(cache.has(partition)){const entry=cache.get(partition);cache.delete(partition);cache.set(partition,entry);cacheHits++;return entry;}
  if(pending.has(partition)){
   if(waiting>=32)fail('navigation_tags_queue_limit');waiting++;
   try{return await pending.get(partition);}finally{waiting--;}
  }
  if(active>=2)fail('navigation_tags_concurrency_limit');active++;
  let publish,reject;const shared=new Promise((resolve,deny)=>{publish=resolve;reject=deny;});void shared.catch(()=>{});pending.set(partition,shared);
  try{
   reads++;const compressed=await readObject(d.key,{maxBytes:d.bytes});
   if(!(compressed instanceof Uint8Array)||compressed.byteLength!==d.bytes||await digest(compressed)!==d.sha256)fail('navigation_tags_object_integrity');
   const reader=new Blob([compressed]).stream().pipeThrough(new DecompressionStream('gzip')).getReader(),chunks=[];let bytes=0;
   try{for(;;){const {done,value}=await reader.read();if(done)break;bytes+=value.byteLength;if(bytes>d.decodedBytes){await reader.cancel();fail('navigation_tags_inflation');}chunks.push(value);}}finally{reader.releaseLock();}
   if(bytes!==d.decodedBytes)fail('navigation_tags_decoded_size');
   const raw=new Uint8Array(bytes);let at=0;for(const c of chunks){raw.set(c,at);at+=c.byteLength;}
   const data=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));
   if(data.schema!=='fluxidi-navigation-way-tags-v1'||data.partition!==partition||data.graphVersion!==manifest.graphVersion
    ||data.graphPartitionSha256!==d.graphPartitionSha256||data.sourceSha256!==manifest.sourceSha256||!Array.isArray(data.ways)||data.ways.length!==d.ways)fail('navigation_tags_object_binding');
   const ways=new Map();
   for(const row of data.ways){
    if(!Array.isArray(row)||row.length!==2||!integer(row[0],Number.MAX_SAFE_INTEGER)||ways.has(row[0])||!plain(row[1])||!plain(row[1].tags)
     ||Object.entries(row[1].tags).some(([k,v])=>!allowedFields.has(k)||typeof v!=='string'||v.length>2048||/[\r\n\0]/.test(v))
     ||!Array.isArray(row[1].unsupported)||row[1].unsupported.some(k=>!allowedFields.has(k)))fail('navigation_tags_way_contract');
    ways.set(row[0],freeze(row[1]));
   }
   const entry={ways,decodedBytes:bytes,objectSha256:d.sha256};
   if(bytes<=maxCacheDecodedBytes){cache.set(partition,entry);cachedBytes+=bytes;while(cachedBytes>maxCacheDecodedBytes){const id=cache.keys().next().value;cachedBytes-=cache.get(id).decodedBytes;cache.delete(id);}}
   publish(entry);return entry;
  }catch(error){reject(error);throw error;}finally{active--;pending.delete(partition);}
 }
 return Object.freeze({graphVersion:manifest.graphVersion,graphManifestSha256,manifestSha256,sourceSha256:manifest.sourceSha256,
  async readWays(partition,ids){
   if(!Array.isArray(ids)||ids.length>4096||ids.some(id=>!integer(id,Number.MAX_SAFE_INTEGER)))fail('navigation_tags_way_limit');
   const entry=await load(partition),result=new Map();
   for(const id of ids){if(!entry.ways.has(id))fail('navigation_tags_way_missing');result.set(id,entry.ways.get(id));}
   return {ways:result,objectSha256:entry.objectSha256};
  },diagnostics:()=>({reads,cacheHits,cachedDecodedBytes:cachedBytes,maxCacheDecodedBytes,active,waiting,maxConcurrentReads:2,maxWaiting:32})});
}

export async function bindNationalNavigationRoadTagsV1({route,reader}){
 const evidence=route?.navigationEvidence;
 if(evidence?.schema!=='fluxidi-directed-navigation-evidence-v1'||reader?.graphVersion!==evidence.graphVersion||!hash(reader.manifestSha256)||!Array.isArray(evidence.roads)||evidence.roads.length!==evidence.edges?.length)fail('navigation_tags_route_binding');
 const wanted=new Map();let count=0;
 for(let i=0;i<evidence.roads.length;i++){
  const r=evidence.roads[i],edge=evidence.edges[i];
  if(r.id!==edge.id||r.way!==edge.way||r.partitionId!==edge.partitionId||!Array.isArray(r.options))fail('navigation_tags_route_binding');
  if(r.terminalMetadata||edge.terminalObject){
   const t=r.terminalMetadata;
   if(!t||!edge.terminalObject||t.terminalObjectSha256!==edge.terminalObject.sha256||t.graphManifestSha256!==reader.graphManifestSha256
    ||t.sourceSha256!==reader.sourceSha256||!hash(t.objectSha256)||t.throughAccess!==false||r.physicalJunctionComplete!==false||r.junctionComplete!==false
    ||r.options.length||(r.physicalOptions??[]).length||!plain(r.navigationTags)||!Array.isArray(r.navigationUnsupported)
    ||Object.entries(r.navigationTags).some(([k,v])=>k.length>100||typeof v!=='string'||v.length>2048||/[\r\n\0]/.test(v))
    ||r.navigationUnsupported.some(k=>typeof k!=='string'||k.length>100))fail('navigation_tags_terminal_binding');
   if(++count>4096)fail('navigation_tags_route_limit');continue;
  }
  let ids=wanted.get(r.partitionId);if(!ids){ids=new Set();wanted.set(r.partitionId,ids);}
  for(const id of [r.way,...r.options.map(o=>o.way),...(r.physicalOptions??[]).map(o=>o.way)])if(!ids.has(id)){ids.add(id);if(++count>4096)fail('navigation_tags_route_limit');}
 }
 const read=new Map();
 for(const [partition,ids]of wanted)read.set(partition,await reader.readWays(partition,[...ids]));
 const roads=evidence.roads.map(r=>{
  if(r.terminalMetadata)return {...r,navigationSource:{manifestSha256:reader.manifestSha256,objectSha256:r.terminalMetadata.objectSha256,sourceSha256:reader.sourceSha256,kind:'immutable_endpoint_source'}};
  const p=read.get(r.partitionId),value=p.ways.get(r.way);
  return {...r,navigationTags:value.tags,navigationUnsupported:value.unsupported,
   navigationSource:{manifestSha256:reader.manifestSha256,objectSha256:p.objectSha256,sourceSha256:reader.sourceSha256},
   options:r.options.map(o=>({...o,navigationTags:p.ways.get(o.way).tags,navigationUnsupported:p.ways.get(o.way).unsupported})),
   physicalOptions:(r.physicalOptions??[]).map(o=>({...o,navigationTags:p.ways.get(o.way).tags,navigationUnsupported:p.ways.get(o.way).unsupported}))};
 });
 return {...route,navigationEvidence:{...evidence,roads,navigationMetadataSha256:reader.manifestSha256}};
}
