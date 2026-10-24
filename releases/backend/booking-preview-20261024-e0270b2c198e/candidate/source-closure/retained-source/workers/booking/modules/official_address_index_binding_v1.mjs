import {bootstrapOfficialAddressIndexV1} from '../vendor/official-address-index/official_address_bootstrap_v1.mjs';
import {bootstrapRuntimeOfficialAddressIndexV2} from './official_address_runtime_bootstrap_v2.mjs';

// Immutable public address data, shared per server-owned R2 binding and pinned
// manifest. No tenant state, active pointer, writes or provider fallback.
// Index failures must never disable the existing GPS/numeric national router.
const bindings=new WeakMap();
export async function operationalOfficialAddressIndexV1(env,{clock=Date.now}={}){
 if(env?.OFFICIAL_ADDRESS_INDEX)return env.OFFICIAL_ADDRESS_INDEX;
 if(env?.OFFICIAL_ADDRESS_INDEX_ENABLED!=='1')return null;
 // Explicit trusted server configuration; never infer a new layout from a
 // manifest or replace the pinned V1 reader silently.
 const layout=env.OFFICIAL_ADDRESS_INDEX_LAYOUT??'1';
 if(layout!=='1'&&layout!=='2')return null;
 const bucket=env.RELIABLE_GRAPH_OBJECTS,hash=env.OFFICIAL_ADDRESS_INDEX_MANIFEST_SHA256;
 if(typeof bucket?.get!=='function'||typeof hash!=='string'||!/^[a-f0-9]{64}$/.test(hash))return null;
 let versions=bindings.get(bucket);if(!versions){versions=new Map();bindings.set(bucket,versions);}
 const key=layout+':'+hash;let entry=versions.get(key);
 if(entry&&entry.retryAt<=clock()){versions.delete(key);entry=null;}
 if(!entry){
  while(versions.size>=2)versions.delete(versions.keys().next().value);
  entry={retryAt:Infinity,index:null,loading:true};versions.set(key,entry);
  const bootstrap=layout==='2'?bootstrapRuntimeOfficialAddressIndexV2:bootstrapOfficialAddressIndexV1;
  // V1's frozen reader deliberately ignores extra manifest fields. Check the
  // requested layout at the trusted storage seam so a V2 publication cannot
  // silently run through the old whole-parent bbox reader.
  const checkedBucket={async get(objectKey){
   const object=await bucket.get(objectKey);
   if(objectKey!=='addresses/publications/'+hash+'.json'||!object||typeof object.arrayBuffer!=='function')return object;
   return {size:object.size,async arrayBuffer(){
    const bytes=new Uint8Array(await object.arrayBuffer());
    if(bytes.byteLength>16_000_000||bytes.byteLength!==object.size)throw Error('address_manifest_size');
    const manifest=JSON.parse(new TextDecoder().decode(bytes)),actual=manifest.spatialLayout??1;
    if(actual!==(layout==='2'?2:1))throw Error('address_manifest_layout');
    return bytes;
   }};
  }};
  // The frozen V2 factory itself requires spatialLayout===2. Parsing its 9 MB
  // manifest a second time here adds avoidable transient heap/CPU. V1 retains
  // the extra check because its frozen factory ignores the new layout field.
  // Local national Workerd measurements leave no safe margin at an 8 MB cache.
  // Reduce only the server-owned V2 cache; vendor/default V1 bytes stay intact.
  try{const loading=bootstrap({enabled:true,bucket:layout==='2'?bucket:checkedBucket,manifestSha256:hash,
    ...(layout==='2'?{maxCacheDecodedBytes:2_000_000}:{})
  });
  // Keep the independently sealed V1 bootstrap contract unchanged. Only V2
  // switches to completed-only bootstrap publication.
  if(layout==='1')entry.promise=loading;entry.index=await loading;
  }catch{entry.retryAt=clock()+15000;entry.index=null;}finally{entry.loading=false;}
 }
 let index=entry.index;
 if(entry.loading){
  if(layout==='1'&&entry.promise){try{index=await entry.promise;}catch{return null;}}
  else{
   if((entry.waiting??0)>=32)return null;entry.waiting=(entry.waiting??0)+1;
   const deadline=clock()+2000;try{while(entry.loading&&clock()<deadline)await new Promise(resolve=>setTimeout(resolve,5));
    if(entry.loading)return null;index=entry.index;
   }finally{entry.waiting--;}
  }
 }

 return index?.health().coverage?.fixtureOnly===true&&env.ENVIRONMENT!=='local'?null:index;
}
