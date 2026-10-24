import {createRuntimeOfficialAddressIndexV2,OfficialIndexUnavailable} from './official_address_runtime_index_v2.mjs';
import {immutableBucketIdentityV1} from '../../../../workers/booking/cache-correction/quote_r2_budget_v1.mjs';

// Completed immutable manifest bytes only, at most two pinned versions per
// server binding. Readers, shard IO, counters and Promises remain request-owned.
const completedManifests = new WeakMap();

// Server-owned inputs only. This module creates no bindings, pointers, flags,
// endpoints or recurring tasks. An absent/false enable flag performs ZERO IO.
export async function bootstrapRuntimeOfficialAddressIndexV2({enabled=false,bucket,manifestSha256,
  cacheEntries=32,maxCacheDecodedBytes=8_000_000}={}){
 if(enabled!==true)return null;
 let retainOperation;try{const runtime=await import('cloudflare:workers');if(typeof runtime.waitUntil==='function')retainOperation=task=>runtime.waitUntil(task.catch(()=>{}));}catch{/* Portable Node tests exercise algorithmic checks; native tests prove lifecycle. */}
 if(typeof bucket?.get!=='function'||typeof manifestSha256!=='string'||!/^[a-f0-9]{64}$/.test(manifestSha256))
  throw new OfficialIndexUnavailable('bootstrap_config');
 async function bytes(key,maxBytes){
  try{
   const obj=await bucket.get(key);
   if(!obj||!Number.isSafeInteger(obj.size)||obj.size<0||obj.size>maxBytes||typeof obj.arrayBuffer!=='function')
    throw new OfficialIndexUnavailable('r2_object_missing_or_size');
   const body=new Uint8Array(await obj.arrayBuffer());
   if(body.byteLength!==obj.size||body.byteLength>maxBytes)throw new OfficialIndexUnavailable('r2_body_size');
   return body;
  }catch(e){if(e instanceof OfficialIndexUnavailable)throw e;throw new OfficialIndexUnavailable('r2_read_failed');}
 }
 const identity=immutableBucketIdentityV1(bucket);
 let versions=completedManifests.get(identity);
 if(!versions){versions=new Map();completedManifests.set(identity,versions);}
 const task=(async()=>{
  const cached=versions.get(manifestSha256);
  const manifestBytes=cached??await bytes('addresses/publications/'+manifestSha256+'.json',16_000_000);
  const index=await createRuntimeOfficialAddressIndexV2({manifestBytes,manifestSha256,cacheEntries,maxCacheDecodedBytes,retainOperation,
   readObject:(key,{maxBytes})=>bytes('addresses/'+key,maxBytes)});
  // Publish only after the existing SHA and manifest-contract checks succeed.
  if(!versions.has(manifestSha256)){
   while(versions.size>=2)versions.delete(versions.keys().next().value);
   versions.set(manifestSha256,manifestBytes.slice());
  }
  return index;
 })();
 retainOperation?.(task);return await task;
}
