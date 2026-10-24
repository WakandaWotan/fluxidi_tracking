import {createNationalNavigationRoadTagsV1} from './national_navigation_road_tags_v1.mjs';
import {readNationalPublicationV1} from './reliable_national_publication_v1.mjs';
const buckets=new WeakMap();
const hash=s=>/^[a-f0-9]{64}$/.test(s??'');
async function retain(task){try{const runtime=await import('cloudflare:workers');runtime.waitUntil(task.catch(()=>{}));}catch{}}
// Immutable source metadata only; no tenant/fleet state or KV polling.
export async function loadNationalNavigationRoadTagsV1(env,scope){
 const bucket=env?.RELIABLE_GRAPH_OBJECTS,pin=env?.NATIONAL_NAVIGATION_TAGS_MANIFEST_SHA256;
 if(typeof bucket?.get!=='function'||!hash(pin)||!scope?.graphVersion)return null;
 let activation;try{const raw=env.RELIABLE_NATIONAL_ACTIVATION;if(typeof raw==='string'&&raw.length>20000)return null;activation=typeof raw==='string'?JSON.parse(raw):raw;}catch{return null;}
 if(activation?.state!=='active'||activation.graphVersion!==scope.graphVersion||!hash(activation.manifestSha256))return null;
 let versions=buckets.get(bucket);if(!versions){versions=new Map();buckets.set(bucket,versions);}
 const key=pin+':'+activation.manifestSha256;let entry=versions.get(key);
 if(entry?.failedUntil<=Date.now()){versions.delete(key);entry=null;}
 if(!entry){
  while(versions.size>=2)versions.delete(versions.keys().next().value);
  entry={loading:true,reader:null,waiting:0};versions.set(key,entry);
  const producer=(async()=>{try{
   const publication=await readNationalPublicationV1({bucket,reference:env.RELIABLE_NATIONAL_PUBLICATION_REF,publication:env.RELIABLE_NATIONAL_PUBLICATION,required:true});
   const object=await bucket.get('navigation/road-tags/publications/'+pin+'.json');
   if(!object||!Number.isSafeInteger(object.size)||object.size<1||object.size>2000000)throw Error('navigation_tags_manifest_unavailable');
   const bytes=new Uint8Array(await object.arrayBuffer());if(bytes.byteLength!==object.size)throw Error('navigation_tags_manifest_size');
   entry.reader=await createNationalNavigationRoadTagsV1({manifestBytes:bytes,manifestSha256:pin,graphManifest:publication.publication.manifest,graphManifestSha256:activation.manifestSha256,
    readObject:async(key,{maxBytes})=>{const value=await bucket.get('navigation/road-tags/'+key);if(!value||value.size!==maxBytes)throw Error('navigation_tags_object_unavailable');const bytes=new Uint8Array(await value.arrayBuffer());if(bytes.byteLength!==value.size)throw Error('navigation_tags_object_size');return bytes;}});
  }catch{entry.failedUntil=Date.now()+15000;}finally{entry.loading=false;}})();void retain(producer);await producer;
 }else if(entry.loading){
  if(entry.waiting>=32)return null;entry.waiting++;
  try{const deadline=Date.now()+2000;while(entry.loading&&Date.now()<deadline)await new Promise(resolve=>setTimeout(resolve,5));}finally{entry.waiting--;}
 }
 return entry.reader;
}
