import {createOfficialAddressIndexV1,OfficialIndexUnavailable} from './official_address_index_v1.mjs';

// Server-owned inputs only. This module creates no bindings, pointers, flags,
// endpoints or recurring tasks. An absent/false enable flag performs ZERO IO.
export async function bootstrapOfficialAddressIndexV1({enabled=false,bucket,manifestSha256,
  cacheEntries=32,maxCacheDecodedBytes=8_000_000}={}){
 if(enabled!==true)return null;
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
 const manifestBytes=await bytes('addresses/publications/'+manifestSha256+'.json',16_000_000);
 return createOfficialAddressIndexV1({manifestBytes,manifestSha256,cacheEntries,maxCacheDecodedBytes,
  readObject:(key,{maxBytes})=>bytes('addresses/'+key,maxBytes)});
}
