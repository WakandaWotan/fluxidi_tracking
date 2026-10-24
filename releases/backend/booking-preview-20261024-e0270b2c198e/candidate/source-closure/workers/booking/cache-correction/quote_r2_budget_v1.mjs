// Private server-owned association. Request JSON cannot supply cache authority.
const identities = new WeakMap();
export function immutableBucketIdentityV1(bucket) { return identities.get(bucket) ?? bucket; }
export function createQuoteR2BudgetV1(bucket, {readLimit=1250, byteLimit=268435456, completedCacheBytes=0}={}) {
 if(typeof bucket?.get!=='function'||!Number.isSafeInteger(readLimit)||readLimit<1||!Number.isSafeInteger(byteLimit)||byteLimit<1)throw Error('owned_quote_r2_budget_config');
 if(!Number.isSafeInteger(completedCacheBytes)||completedCacheBytes<0||completedCacheBytes>4194304)throw Error('owned_quote_r2_cache_config');
 let reads=0,bytes=0,reservedBytes=0,cachedBytes=0,cacheHits=0;
 const completed=new Map();
 const replay=(object,value)=>new Proxy(object,{get(target,key){
  if(key==='arrayBuffer')return async()=>value.slice(0);
  if(key==='text')return async()=>new TextDecoder().decode(value);
  if(key==='json')return async()=>JSON.parse(new TextDecoder().decode(value));
  if(key==='body')throw Error('owned_quote_r2_stream_not_budgeted');
  const v=Reflect.get(target,key,target);return typeof v==='function'?v.bind(target):v;
 }});
 const boundedBucket=Object.freeze({async get(...args){
  // Request-owned, whole immutable objects only. No range/conditional reads,
  // mutable partition names, nulls, failures or in-flight Promises are cached.
  const key=args.length===1&&typeof args[0]==='string'&&/[a-f0-9]{64}\.json(?:\.gz)?$/.test(args[0])?args[0]:null;
  if(completedCacheBytes&&key&&completed.has(key)){cacheHits++;const hit=completed.get(key);return replay(hit.object,hit.value);}
  if(reads>=readLimit)throw Error('owned_quote_r2_read_budget');
  reads++;const object=await bucket.get(...args);if(object==null)return object;
  if(!Number.isSafeInteger(object.size)||object.size<0)throw Error('owned_quote_r2_object_size');
  if(reservedBytes+object.size>byteLimit)throw Error('owned_quote_r2_byte_budget');
  reservedBytes+=object.size;let body;
  const arrayBuffer=()=>body??=(async()=>{
   const value=await object.arrayBuffer(),length=value?.byteLength;
   if(!Number.isSafeInteger(length)||length<0)throw Error('owned_quote_r2_body_size');
   bytes+=length;
   if(bytes>byteLimit)throw Error('owned_quote_r2_byte_budget');
   if(length!==object.size)throw Error('owned_quote_r2_body_size');
   if(key&&completedCacheBytes&&length<=completedCacheBytes&&!completed.has(key)){
    while(cachedBytes+length>completedCacheBytes){const oldest=completed.keys().next().value;cachedBytes-=completed.get(oldest).value.byteLength;completed.delete(oldest);}
    completed.set(key,{object,value:value.slice(0)});cachedBytes+=length;
   }
   return value;
  })();
  return new Proxy(object,{get(target,key){
   if(key==='arrayBuffer')return arrayBuffer;
   if(key==='text')return async()=>new TextDecoder().decode(await arrayBuffer());
   if(key==='json')return async()=>JSON.parse(new TextDecoder().decode(await arrayBuffer()));
   if(key==='body')throw Error('owned_quote_r2_stream_not_budgeted');
   const value=Reflect.get(target,key,target);return typeof value==='function'?value.bind(target):value;
  }});
 }});
 identities.set(boundedBucket,immutableBucketIdentityV1(bucket));
 return Object.freeze({bucket:boundedBucket,metrics:()=>({r2Reads:reads,r2Bytes:bytes,reservedBytes,readLimit,byteLimit,
  ...(completedCacheBytes?{cacheHits,cachedBytes,completedCacheBytes}:{})})});
}
