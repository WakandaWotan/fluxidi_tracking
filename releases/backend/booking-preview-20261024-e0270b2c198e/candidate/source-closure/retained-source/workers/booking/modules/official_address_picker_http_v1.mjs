import {readOfficialAddressPickerV1,validateOfficialAddressPickerRequestV1,OFFICIAL_ADDRESS_PICKER_V1} from './official_address_picker_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';

export const OFFICIAL_ADDRESS_PICKER_PATH_V1='/public/customer/official-address-picker';
const hash=async text=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text))),b=>b.toString(16).padStart(2,'0')).join('');
const text=x=>typeof x==='string'&&x.length>0&&x.length<=500&&!/[\r\n\0]/.test(x);
const reply=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff','access-control-allow-origin':'*'}});
const failure=(error,status)=>{const response=reply({schema:OFFICIAL_ADDRESS_PICKER_V1,ok:false,error,accessProven:false,routeProven:false},status);if(status===429||status===503)response.headers.set('retry-after','1');return response;};
function errorResponse(e){
 const reason=e?.message;
 if(['official_picker_input_invalid','official_picker_bounds_invalid','official_picker_bounds_limit','reliable_address_invalid'].includes(reason))return failure(reason,400);
 if(['official_address_index_changed','address_source_changed','official_address_not_current'].includes(reason))return failure(reason,409);
 if(reason==='official_address_not_found')return failure(reason,404);
 // Never expose storage paths, provider errors, session fields or a false empty catalogue.
 return failure('official_picker_unavailable',503);
}
async function boundedBody(request,onReader){
 const length=request.headers.get('content-length');
 if(length!==null&&(!/^\d+$/.test(length)||Number(length)>2048))throw Error('official_picker_body_limit');
 if(!request.body)throw Error('official_picker_input_invalid');
 const reader=request.body.getReader(),chunks=[];let size=0;
 onReader(()=>{void reader.cancel().catch(()=>{});});
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;
  if(size>2048)throw Error('official_picker_body_limit');chunks.push(value);}
  const bytes=new Uint8Array(size);let at=0;for(const chunk of chunks){bytes.set(chunk,at);at+=chunk.length;}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 }catch(e){void reader.cancel().catch(()=>{});if(e?.message==='official_picker_body_limit')throw e;throw Error('official_picker_input_invalid');}
 finally{reader.releaseLock();}
}
function verifiedPrincipal(session){
 if(session?.purpose!=='customer_session'||!text(session.key)||!text(session.token_hash)||
  !['tenant_id','company_id','customer_id'].every(k=>text(session[k]))||!Number.isFinite(Date.parse(session.expires_at))||Date.parse(session.expires_at)<=Date.now())return null;
 // Stable verified identity, not bearer token or caller/tenant-selected strings.
 if(text(session.phone_hash))return 'phone:'+session.phone_hash.toLowerCase();
 if(text(session.email_hash))return 'email:'+session.email_hash.toLowerCase();
 return null;
}
// One bounded gate per storage binding/isolate. KV's existing non-atomic limiter
// adds a cross-isolate best-effort guard; it is NOT a hard global rate guarantee.
// Successful probe results are reused for <=1s per verified principal/storage
// binding to respect KV's 1 write/s/key limit. It counts probe moments, not each
// request. Authentication is never cached. Local per-request bounds still apply.
// No new DO, scheduled task, anonymous catalogue, writes to addresses or routing.
export function createOfficialAddressPickerHttpV1({clock=Date.now,deadlineMs=5000}={}){
 if(typeof clock!=='function'||!Number.isInteger(deadlineMs)||deadlineMs<1||deadlineMs>10000)throw Error('official_picker_gate_config');
 const gates=new WeakMap();
 function reserve(bucket,principal){
  let state=gates.get(bucket);if(!state){state={actors:new Map(),active:0,now:0};gates.set(bucket,state);}
  const stamp=clock();if(!Number.isFinite(stamp))throw Error('official_picker_gate_clock');
  state.now=Math.max(state.now,stamp);const now=state.now;
  let actor=state.actors.get(principal);
  if(!actor){for(const [key,value] of state.actors)if(value.active===0&&value.until<=now)state.actors.delete(key);
   if(state.actors.size>=512)return null;actor={active:0,count:0,until:now+60000,probe:null,probeUntil:0,pendingProbe:null};state.actors.set(principal,actor);}
  if(actor.until<=now){actor.count=0;actor.until=now+60000;}
  if(state.active>=8||actor.active>=2||actor.count>=30)return null;
  actor.count++;actor.active++;state.active++;
  let released=false;const release=()=>{if(!released){released=true;actor.active--;state.active--;}};
  return {release,async probe(invoke){
   const stamp=clock();if(!Number.isFinite(stamp))throw Error('official_picker_gate_clock');state.now=Math.max(state.now,stamp);
   if(actor.probe&&actor.probeUntil>state.now)return actor.probe;
   if(actor.pendingProbe)return actor.pendingProbe;
   const pending=(async()=>{const rate=await invoke();
    if(typeof rate?.limited!=='boolean'||!Number.isSafeInteger(rate.count)||(rate.limited?rate.count<30:rate.count<1||rate.count>30))throw Error('official_picker_budget_unavailable');
    const completed=clock();if(!Number.isFinite(completed))throw Error('official_picker_gate_clock');state.now=Math.max(state.now,completed);
    actor.probe=Object.freeze({limited:rate.limited,count:rate.count});actor.probeUntil=state.now+1000;return actor.probe;
   })();actor.pendingProbe=pending;try{return await pending;}finally{actor.pendingProbe=null;}
  }};
 }
 return async function handle({request,env,loadCustomerSession,consumeRateBudget,loadIndex=operationalOfficialAddressIndexV1}){
  const url=new URL(request.url);if(url.pathname!==OFFICIAL_ADDRESS_PICKER_PATH_V1)return null;
  if(request.method!=='POST')return failure('method_not_allowed',405);
  if(request.signal.aborted)return failure('official_picker_cancelled',499);
  if(env?.OFFICIAL_ADDRESS_PICKER_ENABLED!=='1'||env?.OFFICIAL_ADDRESS_INDEX_ENABLED!=='1')return failure('official_picker_unavailable',503);
  if(url.search||!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get('content-type')??'')||request.headers.has('content-encoding'))return failure('official_picker_input_invalid',400);
  const layout=env.OFFICIAL_ADDRESS_INDEX_LAYOUT??'1';
  if(!['1','2'].includes(layout)||!/^[a-f0-9]{64}$/.test(env.OFFICIAL_ADDRESS_INDEX_MANIFEST_SHA256??'')||
   !env.BOOKING_KV||typeof env.BOOKING_KV.get!=='function'||typeof env.BOOKING_KV.put!=='function'||
   typeof loadCustomerSession!=='function'||typeof consumeRateBudget!=='function')return failure('official_picker_unavailable',503);
  let session,principal;try{session=await loadCustomerSession(request,env);principal=verifiedPrincipal(session);}catch{return failure('official_picker_unavailable',503);}
  if(request.signal.aborted)return failure('official_picker_cancelled',499);
  if(!principal)return failure('unauthorized',401);
  const rateKey='customer:official-address-picker:'+await hash(principal)+':v1';
  if(request.signal.aborted)return failure('official_picker_cancelled',499);
  let admission;try{admission=reserve(env.BOOKING_KV,rateKey);}catch{return failure('official_picker_unavailable',503);}
  if(!admission)return failure('rate_limited',429);
  let timer,expired=false,cancelled=false,cancelBody=()=>{if(request.body&&!request.body.locked)void request.body.cancel().catch(()=>{});},resolveCancelled;
  const cancellation=new Promise(resolve=>{resolveCancelled=resolve;});
  const onAbort=()=>{cancelled=true;cancelBody();resolveCancelled(failure('official_picker_cancelled',499));};
  request.signal.addEventListener('abort',onAbort,{once:true});if(request.signal.aborted)onAbort();
  const stop=()=>cancelled?failure('official_picker_cancelled',499):expired?failure('official_picker_deadline',503):!verifiedPrincipal(session)?failure('unauthorized',401):null;
  // A response deadline does not release admission slots while its underlying
  // read is still alive. This prevents timed-out callers bypassing concurrency.
  const work=(async()=>{
   try{
    let stopped=stop();if(stopped)return stopped;
    const rate=await admission.probe(()=>consumeRateBudget({env,rateKey,maxCount:30,windowSeconds:60}));
    stopped=stop();if(stopped)return stopped;
    if(typeof rate?.limited!=='boolean'||!Number.isSafeInteger(rate.count)||(rate.limited?rate.count<30:rate.count<1||rate.count>30))throw Error('official_picker_budget_unavailable');
    if(rate.limited)return failure('rate_limited',429);
    let payload;try{payload=validateOfficialAddressPickerRequestV1(await boundedBody(request,cancel=>{cancelBody=cancel;}));}
    catch(e){return e?.message==='official_picker_body_limit'?failure('official_picker_body_limit',413):errorResponse(e);}
    stopped=stop();if(stopped)return stopped;
    const index=await loadIndex(env);stopped=stop();if(stopped)return stopped;if(!index)return failure('official_picker_unavailable',503);
    const result=await readOfficialAddressPickerV1({index,request:payload});stopped=stop();if(stopped)return stopped;
    return reply(result);
   }catch(e){return errorResponse(e);}finally{admission.release();}
  })();
  try{return await Promise.race([work,cancellation,new Promise(resolve=>{timer=setTimeout(()=>{expired=true;cancelBody();resolve(failure('official_picker_deadline',503));},deadlineMs);})]);}
  finally{clearTimeout(timer);request.signal.removeEventListener('abort',onAbort);}
 };
}
export const handleOfficialAddressPickerHttpV1=createOfficialAddressPickerHttpV1();
