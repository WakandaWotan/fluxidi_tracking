const encoder=new TextEncoder();
const hash=async bytes=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
const freeze=o=>{if(o&&typeof o==='object'){for(const v of Object.values(o))freeze(v);Object.freeze(o);}return o;};
export class OfficialIndexUnavailable extends Error{constructor(reason){super(reason);this.code='official_address_index_unavailable';}}

// Storage-injected reader. No fetch, KV, router, credentials or active pointer.
// Caller pins the immutable manifest SHA and owns bounded R2/local object reads.
export async function createOfficialAddressIndexV1({manifestBytes,manifestSha256,readObject,cacheEntries=32,maxCacheDecodedBytes=8_000_000}){
 if(typeof readObject!=='function'||!Number.isInteger(cacheEntries)||cacheEntries<0||cacheEntries>128||
   !Number.isInteger(maxCacheDecodedBytes)||maxCacheDecodedBytes<0||maxCacheDecodedBytes>16_000_000)throw Error('index_reader_config');
 if(manifestBytes.byteLength>16_000_000||await hash(manifestBytes)!==manifestSha256)throw new OfficialIndexUnavailable('manifest_integrity');
 const m=JSON.parse(new TextDecoder().decode(manifestBytes));
 if(m.schema!=='fluxidi-official-address-publication-v1'||m.kind!=='OFFICIAL_BE_NL_ADDRESS_INDEX_V1'||!m.revision||
   m.accessCertification!==false||m.limits?.maxDecodedObjectBytes>4_000_000)throw new OfficialIndexUnavailable('manifest_contract');
 freeze(m);const cache=new Map(),inflight=new Map();let cachedBytes=0,activeReads=0;
 const waiters=[];
 async function acquireSlot(){
  if(activeReads<2){activeReads++;return;}
  if(waiters.length>=32)throw new OfficialIndexUnavailable('reader_concurrency_limit');
  await new Promise(resolve=>waiters.push(resolve));
 }
 function releaseSlot(){const next=waiters.shift();if(next)next();else activeReads--;}
 async function object(h){
  if(cache.has(h)){const v=cache.get(h);cache.delete(h);cache.set(h,v);return v.data;}
  if(inflight.has(h))return inflight.get(h);
  const task=(async()=>{
   await acquireSlot();try{
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
   if(cacheEntries&&d.decodedBytes<=maxCacheDecodedBytes){cache.set(h,{data,bytes:d.decodedBytes});cachedBytes+=d.decodedBytes;
    while(cache.size>cacheEntries||cachedBytes>maxCacheDecodedBytes){const key=cache.keys().next().value;cachedBytes-=cache.get(key).bytes;cache.delete(key);}}
   return data;
   }finally{releaseSlot();}
  })();inflight.set(h,task);try{return await task;}catch(e){
   if(e instanceof OfficialIndexUnavailable)throw e;throw new OfficialIndexUnavailable('object_read_or_decode_failed');
  }finally{inflight.delete(h);}
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
  health:()=>freeze({revision:m.revision,manifestSha256,coverage:m.coverage,counts:m.sourceRecords,accessCertification:false}),
  provenance:()=>m.sources,
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
   // Explicit upper bound of 32 shard reads; callers narrow overly dense bbox.
   const hashes=[];for(let i=minX;i<=maxX;i++)for(let j=minY;j<=maxY;j++)hashes.push(...(m.cells[`12/${i}/${j}`]??[]));
   if(hashes.length>32)throw Error('address_bbox_object_limit');
   for(const h of hashes){for(const r of (await object(h)).records){
    const lon=r[15],lat=r[16];if(lon!=null&&lon>=west&&lon<=east&&lat>=south&&lat<=north){
     if(result.length===maxResults){truncated=true;break;}result.push(hydrate(r));}
   }if(truncated)break;}
   return freeze({records:result,truncated,indexRevision:m.revision});
  },
 });
}
