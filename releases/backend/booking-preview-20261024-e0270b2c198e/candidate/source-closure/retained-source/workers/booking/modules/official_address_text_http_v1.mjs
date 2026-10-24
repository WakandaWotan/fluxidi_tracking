import {ADDRESS_TEXT_V1,validateOfficialAddressTextRequestV1,resolveOfficialAddressTextV1,createOfficialAddressTextIndexV1} from './official_address_text_search_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
export const OFFICIAL_ADDRESS_TEXT_PATH_V1='/public/customer/official-address-search';
const encoder=new TextEncoder(),hex=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',encoder.encode(s))),n=>n.toString(16).padStart(2,'0')).join('');
const respond=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','access-control-allow-origin':'*',...(status===429||status===503?{'retry-after':'1'}:{})}});
const bad=(error,status)=>respond({schema:ADDRESS_TEXT_V1,ok:false,error,accessProven:false,routeProven:false},status);
const principal=s=>s?.purpose==='customer_session'&&['key','token_hash','customer_id','tenant_id','company_id'].every(k=>typeof s[k]==='string'&&s[k])&&Date.parse(s.expires_at)>Date.now()?(s.phone_hash?'phone:'+s.phone_hash:s.email_hash?'email:'+s.email_hash:null):null;
async function readBody(request,registerCancel){
 const length=request.headers.get('content-length');if(length!==null&&(!/^\d+$/.test(length)||Number(length)>2048))throw Error('official_text_body_limit');if(!request.body)throw Error('official_text_input_invalid');
 const reader=request.body.getReader(),chunks=[];let n=0;registerCancel(()=>{void reader.cancel().catch(()=>{});});try{for(;;){const {done,value}=await reader.read();if(done)break;n+=value.byteLength;if(n>2048){await reader.cancel();throw Error('official_text_body_limit');}chunks.push(value);}const b=new Uint8Array(n);let at=0;for(const c of chunks){b.set(c,at);at+=c.length;}return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(b));}finally{reader.releaseLock();}
}
async function retain(task){try{const {waitUntil}=await import('cloudflare:workers');waitUntil(task.catch(()=>{}));}catch{}}
const indexes=new WeakMap();
export async function loadOfficialAddressTextIndexV1(env){
 if(env?.OFFICIAL_ADDRESS_TEXT_SEARCH_ENABLED!=='1')return null;
 if(env.OFFICIAL_ADDRESS_TEXT_INDEX)return env.OFFICIAL_ADDRESS_TEXT_INDEX.fixtureOnly&&env.ENVIRONMENT!=='local'?null:env.OFFICIAL_ADDRESS_TEXT_INDEX;
 const bucket=env.RELIABLE_GRAPH_OBJECTS,pin=env.OFFICIAL_ADDRESS_TEXT_MANIFEST_SHA256,base=env.OFFICIAL_ADDRESS_INDEX_MANIFEST_SHA256;
 if(typeof bucket?.get!=='function'||!/^[a-f0-9]{64}$/.test(pin??'')||!/^[a-f0-9]{64}$/.test(base??'')||env.OFFICIAL_ADDRESS_INDEX_LAYOUT!=='2')return null;
 let versions=indexes.get(bucket);if(!versions){versions=new Map();indexes.set(bucket,versions);}const key=pin+':'+base;
 let entry=versions.get(key);if(entry?.failedUntil<=Date.now()){versions.delete(key);entry=null;}
 if(!entry){while(versions.size>=2)versions.delete(versions.keys().next().value);entry={loading:true,index:null,waiting:0};versions.set(key,entry);
  const producer=(async()=>{try{const object=await bucket.get('addresses/text/publications/'+pin+'.json');if(!object||object.size>6_000_000)throw Error('official_text_manifest_unavailable');const bytes=new Uint8Array(await object.arrayBuffer());if(bytes.length!==object.size)throw Error('official_text_manifest_size');entry.index=await createOfficialAddressTextIndexV1({manifestBytes:bytes,manifestSha256:pin,baseManifestSha256:base,retainOperation:retain,readObject:async(key,{source,maxBytes})=>{const o=await bucket.get((source==='base'?'addresses/':'addresses/text/')+key);if(!o||o.size>maxBytes)throw Error('official_text_object_unavailable');const data=new Uint8Array(await o.arrayBuffer());if(data.byteLength!==o.size)throw Error('official_text_object_size');return data;}});}catch{entry.failedUntil=Date.now()+15000;}finally{entry.loading=false;}})();void retain(producer);await producer;
 }else if(entry.loading){if(entry.waiting>=32)return null;entry.waiting++;try{const end=Date.now()+2000;while(entry.loading&&Date.now()<end)await new Promise(r=>setTimeout(r,5));}finally{entry.waiting--;}}
 return entry.index;
}
export function createOfficialAddressTextHttpV1({path=OFFICIAL_ADDRESS_TEXT_PATH_V1,actorPrincipal=principal,rateNamespace='customer'}={}){
 if(![OFFICIAL_ADDRESS_TEXT_PATH_V1,'/company/official-address-search'].includes(path)||typeof actorPrincipal!=='function'||!['customer','operator'].includes(rateNamespace))throw Error('official_text_server_config');
 const gates=new WeakMap();
 function reserve(storage,key){let g=gates.get(storage);if(!g){g={active:0,actors:new Map()};gates.set(storage,g);}const now=Date.now();
  for(const [k,v]of g.actors)if(v.active===0&&!v.pending&&v.until<=now)g.actors.delete(k);
  let a=g.actors.get(key);
  if(!a){if(g.actors.size>=512)return null;a={active:0,count:0,until:now+60000,probeUntil:0,probe:null,pending:false};g.actors.set(key,a);}
  if(a.until<=now){a.count=0;a.until=now+60000;}if(a.active>=2||g.active>=8||a.count>=30||a.pending)return null;a.active++;a.count++;g.active++;
  return {release:()=>{a.active--;g.active--;},async rate(invoke){if(a.probeUntil>Date.now())return a.probe;if(a.pending)return null;a.pending=true;a.probe=null;try{const result=await invoke();if(typeof result?.limited!=='boolean'||!Number.isSafeInteger(result.count)||result.count<1||!result.limited&&result.count>30||result.limited&&result.count<30)throw Error('official_text_rate_contract');a.probe=result;return result;}finally{a.pending=false;a.probeUntil=Date.now()+1100;}}};
 }
 return async({request,env,loadCustomerSession,consumeRateBudget,loadSearch=loadOfficialAddressTextIndexV1,loadIndex=operationalOfficialAddressIndexV1})=>{
  const url=new URL(request.url);if(url.pathname!==path)return null;if(request.method!=='POST')return bad('method_not_allowed',405);
  if(env?.OFFICIAL_ADDRESS_TEXT_SEARCH_ENABLED!=='1'||env.OFFICIAL_ADDRESS_INDEX_ENABLED!=='1')return bad('official_text_unavailable',503);
  if(url.search||request.headers.has('content-encoding')||!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get('content-type')??''))return bad('official_text_input_invalid',400);
  if(!env.BOOKING_KV||typeof loadCustomerSession!=='function'||typeof consumeRateBudget!=='function')return bad('official_text_unavailable',503);
  let s,p;try{s=await loadCustomerSession(request,env);p=actorPrincipal(s);}catch{return bad('official_text_unavailable',503);}if(!p)return bad('unauthorized',401);
  if(request.signal.aborted)return bad('official_text_cancelled',499);
  const key=rateNamespace+':official-text:'+await hex(p)+':v1',admission=reserve(env.BOOKING_KV,key);if(!admission)return bad('rate_limited',429);
  let expired=false,cancelBody=()=>{},timer;const stopped=()=>expired?bad('official_text_deadline',503):request.signal.aborted?bad('official_text_cancelled',499):null;
  const work=(async()=>{try{const rate=await admission.rate(()=>consumeRateBudget({env,rateKey:key,maxCount:30,windowSeconds:60}));if(!rate||rate.limited)return bad('rate_limited',429);
   if(stopped())return stopped();if(actorPrincipal(await loadCustomerSession(request,env))!==p)return bad('unauthorized',401);
   let b;try{b=validateOfficialAddressTextRequestV1(await readBody(request,fn=>{cancelBody=fn;}));}catch(e){if(stopped())return stopped();return bad(e.message==='official_text_body_limit'?e.message:'official_text_input_invalid',e.message==='official_text_body_limit'?413:400);}
   if(stopped())return stopped();
   let result;if(b.mode==='suggest'){const search=await loadSearch(env);if(!search)return bad('official_text_unavailable',503);if(search.baseIndexRevision!==env.OFFICIAL_ADDRESS_TEXT_BASE_REVISION)return bad('official_text_unavailable',503);result=await search.suggest(b);}else{const index=await loadIndex(env);if(!index)return bad('official_text_unavailable',503);result=await resolveOfficialAddressTextV1({index,request:b});}
   if(stopped())return stopped();if(actorPrincipal(await loadCustomerSession(request,env))!==p)return bad('unauthorized',401);if(stopped())return stopped();
   if(encoder.encode(JSON.stringify(result)).byteLength>100_000)return bad('official_text_response_limit',503);return respond(result);
  }catch(e){if(['official_address_index_changed','address_source_changed'].includes(e.message))return bad(e.message,409);if(e.message==='official_address_not_found')return bad(e.message,404);return bad('official_text_unavailable',503);}finally{admission.release();}})();void retain(work);try{return await Promise.race([work,new Promise(resolve=>{timer=setTimeout(()=>{expired=true;cancelBody();resolve(bad('official_text_deadline',503));},5000);})]);}finally{clearTimeout(timer);}
 };
}
export const handleOfficialAddressTextHttpV1=createOfficialAddressTextHttpV1();
