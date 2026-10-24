import {immutableBucketIdentityV1} from './quote_r2_budget_v1.mjs';
// Server-owned immutable publication metadata in the existing graph object
// store. Small reference bindings fit Workers variable limits; no graph KV,
// URLs, provider calls or per-candidate metadata loads.
const publications=new WeakMap(),limit=4*1024*1024;
const fail=reason=>{throw Error(reason);};
const freeze=value=>{if(value&&typeof value==='object'){for(const child of Object.values(value))freeze(child);Object.freeze(value);}return value;};
export async function readNationalPublicationV1({publication,reference,bucket,metadataBucket}){
 if(reference==null)return {publication,reads:0,bytes:0,cacheHits:0};
 // The graph remains on its original immutable reader. An isolated staging
 // metadata binding avoids publishing trial approvals into the live bucket.
 if(metadataBucket!==undefined)bucket=metadataBucket;
 let ref=reference;
 if(typeof ref==='string'){if(new TextEncoder().encode(ref).byteLength>5120)fail('national_reference_size');try{ref=JSON.parse(ref);}catch{fail('national_reference_json');}}
 if(ref?.schema!=='fluxidi-national-publication-ref-v1'||!/^[a-f0-9]{64}$/.test(ref.sha256)||ref.key!==`routing/national/publications/${ref.sha256}.json`||!Number.isSafeInteger(ref.bytes)||ref.bytes<1||ref.bytes>limit||typeof bucket?.get!=='function')fail('national_reference_invalid');
 const cacheIdentity=immutableBucketIdentityV1(bucket);let cache=publications.get(cacheIdentity);if(!cache){cache=new Map();publications.set(cacheIdentity,cache);}
 const key=ref.sha256+':'+ref.bytes;
 if(cache.has(key))return {publication:await cache.get(key),reads:0,bytes:0,cacheHits:1};
 // Bound both pending and completed publications. Concurrent consumers of
 // the same version share a single immutable read; failures are not cached.
 if(cache.size>=2)cache.delete(cache.keys().next().value);
 const pending=(async()=>{
  const object=await bucket.get(ref.key);
  if(!object||object.size!==ref.bytes||typeof object.arrayBuffer!=='function')fail('national_publication_object_size');
  const bytes=new Uint8Array(await object.arrayBuffer());
  if(bytes.byteLength!==ref.bytes)fail('national_publication_object_size');
  const hash=Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',bytes)),b=>b.toString(16).padStart(2,'0')).join('');
  if(hash!==ref.sha256)fail('national_publication_object_hash');
  let value;try{value=JSON.parse(new TextDecoder().decode(bytes));}catch{fail('national_publication_object_json');}
  return freeze(value);
 })();cache.set(key,pending);
 try{return {publication:await pending,reads:1,bytes:ref.bytes,cacheHits:0};}
 catch(e){if(cache.get(key)===pending)cache.delete(key);throw e;}
}
