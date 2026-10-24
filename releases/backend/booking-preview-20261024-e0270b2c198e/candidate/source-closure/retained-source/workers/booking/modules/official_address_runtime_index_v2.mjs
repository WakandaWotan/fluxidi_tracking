// Backend-owned runtime adaptation of the exact pinned V2 reader. Vendor/data untouched.
import {OfficialIndexUnavailable} from '../vendor/official-address-index/official_address_index_v2.mjs';
export {OfficialIndexUnavailable};
const encoder=new TextEncoder();
const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
const freeze=o=>{if(o&&typeof o==='object'){for(const v of Object.values(o))freeze(v);Object.freeze(o);}return o;};

// Storage-injected reader. No fetch, KV, router, credentials or active pointer.
// Caller pins the immutable manifest SHA and owns bounded R2/local object reads.
export async function createRuntimeOfficialAddressIndexV2({manifestBytes,manifestSha256,readObject,cacheEntries=32,maxCacheDecodedBytes=8_000_000,maxQueueWaitMs=2000,retainOperation}){
 if(retainOperation!==undefined&&typeof retainOperation!=='function')throw Error('index_lifecycle_config');
 if(!Number.isInteger(maxQueueWaitMs)||maxQueueWaitMs<1||maxQueueWaitMs>5000)throw Error('index_queue_budget');
 if(typeof readObject!=='function'||!Number.isInteger(cacheEntries)||cacheEntries<0||cacheEntries>128||
   !Number.isInteger(maxCacheDecodedBytes)||maxCacheDecodedBytes<0||maxCacheDecodedBytes>16_000_000)throw Error('index_reader_config');
 if(manifestBytes.byteLength>16_000_000||await hash(manifestBytes)!==manifestSha256)throw new OfficialIndexUnavailable('manifest_integrity');
 const m=JSON.parse(new TextDecoder().decode(manifestBytes));
 if(m.schema!=='fluxidi-official-address-publication-v1'||m.kind!=='OFFICIAL_BE_NL_ADDRESS_INDEX_V1'||!m.revision||
   m.accessCertification!==false||m.limits?.maxDecodedObjectBytes>4_000_000||m.spatialLayout!==2||!m.spatialParents)throw new OfficialIndexUnavailable('manifest_contract');
 freeze(m);const cache=new Map();let cachedBytes=0,activeReads=0,peakActiveReads=0,peakWaitingTickets=0;
 // Only plain FIFO tickets cross HTTP contexts. Every timer Promise belongs
 // to its own request; release never resolves a different request's Promise.
 const tickets=new Map();let sequence=0;
 async function acquireSlot(){
  if(activeReads<2&&tickets.size===0){activeReads++;peakActiveReads=Math.max(peakActiveReads,activeReads);return;}
  if(tickets.size>=32)throw new OfficialIndexUnavailable('reader_concurrency_limit');
  const id=++sequence,deadline=Date.now()+maxQueueWaitMs;tickets.set(id,deadline);peakWaitingTickets=Math.max(peakWaitingTickets,tickets.size);
  try{for(;;){
   const now=Date.now();for(const [key,end]of tickets)if(end<=now)tickets.delete(key);
   if(!tickets.has(id))throw new OfficialIndexUnavailable('reader_queue_deadline');
   if(activeReads<2&&tickets.keys().next().value===id){tickets.delete(id);activeReads++;peakActiveReads=Math.max(peakActiveReads,activeReads);return;}
   await new Promise(resolve=>setTimeout(resolve,Math.min(5,deadline-now)));
  }}finally{tickets.delete(id);}
 }
 function releaseSlot(){activeReads--;}
 async function object(h){
  if(cache.has(h)){const v=cache.get(h);cache.delete(h);cache.set(h,v);return v.data;}
  const task=(async()=>{await acquireSlot();try{
   // An earlier request may have completed while this ticket waited.
   if(cache.has(h)){const v=cache.get(h);cache.delete(h);cache.set(h,v);return v.data;}
   const d=m.objects[h];if(!d||d.sha256!==h||d.key!=='objects/'+h+'.json.gz'||d.bytes>2_000_000||d.decodedBytes>4_000_000)
    throw new OfficialIndexUnavailable('object_descriptor');
   const bytes=await readObject(d.key,{maxBytes:d.bytes});
   if(!bytes||bytes.byteLength!==d.bytes||await hash(bytes)!==h)throw new OfficialIndexUnavailable('object_integrity');
   const stream=new Blob([bytes]).stream().pipeThrough(new DecompressionStream('gzip'));
   const chunks=[],reader=stream.getReader();let length=0;
   for(;;){const {done,value}=await reader.read();if(done)break;length+=value.length;
    if(length>d.decodedBytes||length>4_000_000){await reader.cancel();throw new OfficialIndexUnavailable('object_inflation_bound');}chunks.push(value);}
   if(length!==d.decodedBytes)throw new OfficialIndexUnavailable('object_decoded_length');
   const all=new Uint8Array(length);let at=0;for(const chunk of chunks){all.set(chunk,at);at+=chunk.length;}
   const data=freeze(JSON.parse(new TextDecoder().decode(all)));
   if(data.schema!==d.schema)throw new OfficialIndexUnavailable('object_schema');
   if(cacheEntries&&d.decodedBytes<=maxCacheDecodedBytes){if(cache.has(h))cachedBytes-=cache.get(h).bytes;cache.set(h,{data,bytes:d.decodedBytes});cachedBytes+=d.decodedBytes;
    while(cache.size>cacheEntries||cachedBytes>maxCacheDecodedBytes){const key=cache.keys().next().value;cachedBytes-=cache.get(key).bytes;cache.delete(key);}}
   return data;
  }catch(e){
   if(e instanceof OfficialIndexUnavailable)throw e;throw new OfficialIndexUnavailable('object_read_or_decode_failed');
  }finally{releaseSlot();}})();
  // This task belongs only to the caller. Native retention lets its real IO
  // finish cleanup after client disconnect; no other request awaits it.
  retainOperation?.(task);return await task;
 }
 function hydrate(row){
  if(!Array.isArray(row)||row.length!==m.columns.length)throw new OfficialIndexUnavailable('record_shape');
  const r=Object.fromEntries(m.columns.map((k,i)=>[k,row[i]])),s=m.sources[r.region];
  if(!s)throw new OfficialIndexUnavailable('record_source');
  return freeze({schema:'fluxidi-official-address-v1',id:r.id,indexRevision:m.revision,source:s.source,
   sourceVersion:r.sourceVersion,sourceRecordId:r.sourceRecordId,streetId:r.streetId,status:r.status,officiallyAssigned:r.officiallyAssigned,
   address:{country:r.region==='NL'?'NL':'BE',street:r.street,houseNumber:r.houseNumber,
    boxNumber:r.boxNumber,houseLetter:r.houseLetter,houseNumberAddition:r.houseNumberAddition,
    postcode:r.postcode,municipality:r.municipality,locality:r.locality},
   point:r.longitude==null?null:{longitude:r.longitude,latitude:r.latitude},
   provenance:{region:r.region,datasetVersion:s.datasetVersion,payloadSha256:s.sourceSha256,
    capturedAt:Date.parse(s.acquisition.finishedAt),license:s.license,licenseReview:s.license?'source_terms_archived':'pending',
    originalCRS:s.crs,originalPosition:{x:r.originalX,y:r.originalY},axisOrder:'longitude,latitude',
    coordinateTransformation:s.coordinateTransformation,positionMethod:r.positionMethod,positionQuality:r.positionQuality,
    sourceStatus:r.sourceStatus,names:r.names,sourceExtra:r.extra},accessProven:false});
 }
 return Object.freeze({kind:m.kind,revision:m.revision,
  health:()=>freeze({revision:m.revision,manifestSha256,coverage:m.coverage,counts:m.sourceRecords,spatialLayout:2,accessCertification:false}),
  provenance:()=>m.sources,
  runtimeDiagnostics:()=>({activeReads,waitingTickets:tickets.size,peakActiveReads,peakWaitingTickets,maxActiveReads:2,maxWaitingTickets:32,maxQueueWaitMs,retentionSupported:typeof retainOperation==='function'}),
  async get(id){
   if(typeof id!=='string'||!id||id.length>500||/[\r\n\0]/.test(id))throw Error('official_address_id_required');
   const bucket=(await hash(encoder.encode(id))).slice(0,3),h=m.idBuckets[bucket];
   const entries=h?(await object(h)).entries:[];const found=entries.find(e=>e[0]===id);
   if(!found){if(!m.coverage.allFourSourcesIngested)throw new OfficialIndexUnavailable('partial_source_coverage');return null;}
   const data=await object(found[1]),row=data.records?.[found[2]];
   if(row?.[0]!==id)throw new OfficialIndexUnavailable('locator_binding');
   return hydrate(row);
  },
  async bbox({west,south,east,north,maxResults=1000}){
   if(![west,south,east,north].every(Number.isFinite)||west>east||south>north||west<2||east>9||south<49||north>56||
     !Number.isInteger(maxResults)||maxResults<1||maxResults>2048)throw Error('address_bbox_invalid');
   const x=lon=>Math.floor((lon+180)/360*4096),y=lat=>Math.floor((1-Math.asinh(Math.tan(lat*Math.PI/180))/Math.PI)/2*4096);
   const minX=x(west),maxX=x(east),minY=y(north),maxY=y(south);
   if((maxX-minX+1)*(maxY-minY+1)>16)throw Error('address_bbox_cell_limit');
   const result=[];let truncated=false;
   // The same cache/concurrency bounds apply to hierarchy and data objects.
   // Count all planned reads, including metadata, before reading data shards.
   const hashes=new Set();let metadataReads=0;
   for(let i=minX;i<=maxX;i++)for(let j=minY;j<=maxY;j++){
    const parent=`12/${i}/${j}`,h=m.spatialParents[parent];
    if(h){
     metadataReads++;if(metadataReads>32)throw Error('address_bbox_object_limit');
     const hierarchy=await object(h);
     if(hierarchy.schema!=='fluxidi-official-address-spatial-parent-v2'||hierarchy.parent!==parent||!Array.isArray(hierarchy.leaves))
      throw new OfficialIndexUnavailable('spatial_parent_binding');
     for(const leaf of hierarchy.leaves){
      if(!Array.isArray(leaf.bounds)||leaf.bounds.length!==4||!leaf.bounds.every(Number.isFinite)||!Array.isArray(leaf.objects))
       throw new OfficialIndexUnavailable('spatial_leaf_contract');
      const [w,s,e,n]=leaf.bounds;
      if(w>e||s>n)throw new OfficialIndexUnavailable('spatial_leaf_bounds');
      if(w<=east&&e>=west&&s<=north&&n>=south)for(const part of leaf.objects)hashes.add(part);
     }
    }else for(const part of m.cells[parent]??[])hashes.add(part);
   }
   if(metadataReads+hashes.size>32)throw Error('address_bbox_object_limit');
   for(const h of hashes){for(const r of (await object(h)).records){
    const lon=r[15],lat=r[16];if(lon!=null&&lon>=west&&lon<=east&&lat>=south&&lat<=north){
     if(result.length===maxResults){truncated=true;break;}result.push(hydrate(r));}
   }if(truncated)break;}
   return freeze({records:result,truncated,indexRevision:m.revision});
  },
 });
}
