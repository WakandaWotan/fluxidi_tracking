import {authorizeNationalNavigationV1} from './national_navigation_authorization_v1.mjs';
import {publicAddressPointV1} from './practical_frontage_v1.mjs';
import {nationalNavigationDirectionsV1} from './national_navigation_directions_v1.mjs';

const paths=new Set(['/company/navigation/route','/company/navigation/reroute']);
const respond=(value,status=200)=>new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','access-control-allow-origin':'*',...(status===429?{'retry-after':'10'}:{})}});
const bad=(error,status)=>respond({ok:false,error,provider_fallback:false},status);
const finite=n=>typeof n==='number'&&Number.isFinite(n);
const pair=p=>p&&finite(p.lat)&&finite(p.lng)&&Math.abs(p.lat)<=90&&Math.abs(p.lng)<=180&&!(p.lat===0&&p.lng===0);
const text=s=>typeof s==='string'&&s.length<=500&&!/[\r\n\0]/.test(s);
async function bodyJson(request){
 const length=request.headers.get('content-length');if(length!==null&&(!/^\d+$/.test(length)||Number(length)>8192))throw Error('navigation_body_limit');
 if(!request.body)throw Error('navigation_input_invalid');
 const reader=request.body.getReader(),chunks=[];let size=0,expired=false;
 const cancel=()=>{void reader.cancel().catch(()=>{});};
 const timer=setTimeout(()=>{expired=true;cancel();},5000);request.signal.addEventListener('abort',cancel,{once:true});
 try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>8192){await reader.cancel();throw Error('navigation_body_limit');}chunks.push(value);}
  if(expired)throw Error('navigation_body_deadline');if(request.signal.aborted)throw Error('navigation_cancelled');
  const bytes=new Uint8Array(size);let at=0;for(const c of chunks){bytes.set(c,at);at+=c.length;}return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
 }finally{clearTimeout(timer);request.signal.removeEventListener('abort',cancel);reader.releaseLock();}
}
function routePoint(position,input,label,actor,now,role){
 if(!pair(position)||label!=null&&!text(label)||input!=null&&(typeof input!=='object'||Array.isArray(input)))throw Error('navigation_input_invalid');
 if(input?.kind==='gps'){
  if(role!=='origin'||actor.role!=='driver'||!finite(input.capturedAt)||input.capturedAt>now||now-input.capturedAt>30000
   ||!finite(input.accuracyMeters)||input.accuracyMeters<=0||input.accuracyMeters>100)throw Error('navigation_gps_unproven');
  const speed=input.speedMetersPerSecond;
  if(speed!=null&&(!finite(speed)||speed<0))throw Error('navigation_gps_unproven');
  const access={kind:'gps',capturedAt:input.capturedAt,accuracyMeters:input.accuracyMeters,
   ...(speed!=null?{speedMetersPerSecond:speed}:{}),
   ...(speed>=2&&finite(input.headingDegrees)&&input.headingDegrees>=0&&input.headingDegrees<360?{headingDegrees:input.headingDegrees}:{}),
   // The caller cannot borrow another chauffeur's continuity history.
   continuityKey:'nav:'+actor.driver_id};
  return {latitude:position.lat,longitude:position.lng,access};
 }
 return publicAddressPointV1({from:label??'',from_lat:position.lat,from_lng:position.lng,...(input?{pickup_input:input}:{})});
}

// Authentication and runtime construction are the existing Booking authorities.
// This handler never accepts a router, actor, tenant, graph or financial data
// from JSON, never writes a booking, and never invokes a paid provider.
export async function handleNationalNavigationHttpV1({request,env,authenticate,createRouter,enrichRoute=async route=>route,clock=Date.now}){
 const path=new URL(request.url).pathname;if(!paths.has(path))return null;
 if(request.method!=='POST')return bad('method_not_allowed',405);
 if(env?.NATIONAL_NAVIGATION_ENABLED!=='1')return bad('national_navigation_unavailable',503);
 const limiter=env.BOOKING_NAVIGATION_IP_LIMITER,actorLimiter=env.BOOKING_NAVIGATION_CLIENT_LIMITER,ip=request.headers.get('cf-connecting-ip');
 if(typeof limiter?.limit!=='function'||typeof actorLimiter?.limit!=='function'||!ip||ip.length>64)return bad('navigation_admission_unavailable',503);
 try{if((await limiter.limit({key:'navigation:'+ip}))?.success!==true)return bad('rate_limited',429);}catch{return bad('navigation_admission_unavailable',503);}
 if(request.signal.aborted)return bad('navigation_cancelled',499);
 let actor;try{actor=await authenticate(request,env);}catch{return bad('navigation_auth_unavailable',503);}
 if(!actor||!['company_admin','driver'].includes(actor.role)||!actor.scope?.tenant_id||!actor.scope?.company_id||typeof actor.session_hash!=='string'||!actor.session_hash||actor.role==='driver'&&!actor.driver_id)return bad('unauthorized',401);
 // A shared mobile/NAT or Worker hop must not become the only route budget.
 // The fine-grained budget belongs to the server-authenticated actor, never a
 // caller-provided company, driver or country. No additional KV counters.
 try{if((await actorLimiter.limit({key:'navigation-actor:'+JSON.stringify([actor.scope.tenant_id,actor.scope.company_id,actor.role,actor.driver_id??null,actor.session_hash])}))?.success!==true)return bad('rate_limited',429);}catch{return bad('navigation_admission_unavailable',503);}
 if(request.headers.has('content-encoding')||!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get('content-type')??''))return bad('navigation_input_invalid',400);
 let body;
 try{body=await bodyJson(request);}catch(e){return bad(['navigation_body_limit','navigation_body_deadline','navigation_cancelled'].includes(e.message)?e.message:'navigation_input_invalid',e.message==='navigation_body_limit'?413:e.message==='navigation_body_deadline'?408:request.signal.aborted?499:400);}
 const allowed=['origin','current','destination','origin_input','destination_input','origin_label','destination_label','country','profile','language','trip_id','booking_id','operational_leg','reason','heading_deg'];
 if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!allowed.includes(k))||body.profile!=null&&!['car','driving'].includes(body.profile)
  ||body.country!=null&&!/^[A-Z]{2}$/.test(body.country)||body.language!=null&&!/^[a-z]{2}(?:[-_][A-Za-z]{2})?$/.test(body.language)
  ||['trip_id','booking_id','operational_leg'].some(k=>body[k]!=null&&(!text(body[k])||!body[k]||body[k].length>160))||body.reason!=null&&(!text(body.reason)||body.reason.length>80))return bad('navigation_input_invalid',400);
 const position=path.endsWith('/reroute')?body.current:body.origin;
 if(!pair(position)||!pair(body.destination)||body.origin!=null&&body.current!=null)return bad('navigation_input_invalid',400);
 try{
  const origin=routePoint(position,body.origin_input,body.origin_label,actor,clock(),'origin');
  const destination=routePoint(body.destination,body.destination_input,body.destination_label,actor,clock(),'destination');
  const authority=await authorizeNationalNavigationV1({env,actor,body,path,clock});
  if(!authority.ok)return bad(authority.error,authority.status);
  const router=await createRouter(env,actor.scope);
  if(router?.kind!=='LOCAL_ROUTING_ONLY_V1'||router.scope?.tenant_id!==actor.scope.tenant_id||router.scope?.company_id!==actor.scope.company_id||typeof router.navigationRoute!=='function')throw Error('navigation_runtime_unavailable');
  const record={pickup_lat:position.lat,pickup_lng:position.lng,dropoff_lat:body.destination.lat,dropoff_lng:body.destination.lng,
   ...(body.origin_input?{pickup_input:body.origin_input}:{}),...(body.destination_input?{destination_input:body.destination_input}:{})};
  await router.resolveForJourney(record);
  if(request.signal.aborted)return bad('navigation_cancelled',499);
  const scope=router.scope,raw=await router.navigationRoute({scope,origin,destination,departureAt:clock(),gpsRoadContext:origin.access?.kind==='gps'});
  const result=await enrichRoute(raw,env,scope);
  if(request.signal.aborted)return bad('navigation_cancelled',499);
  const output=await nationalNavigationDirectionsV1({route:result,scope,language:body.language??'nl',clock});
  // Revoke/owner changes during a slow route must not disclose the old scope.
  const currentActor=await authenticate(request,env);
  if(!currentActor||currentActor.role!==actor.role||currentActor.scope?.tenant_id!==actor.scope.tenant_id||currentActor.scope?.company_id!==actor.scope.company_id||currentActor.driver_id!==actor.driver_id||currentActor.session_hash!==actor.session_hash||currentActor.vehicle_id!==actor.vehicle_id||currentActor.vehicle_device_id!==actor.vehicle_device_id)return bad('unauthorized',401);
  if(request.signal.aborted)return bad('navigation_cancelled',499);
  const currentAuthority=await authorizeNationalNavigationV1({env,actor:currentActor,body,path,clock});
  if(!currentAuthority.ok)return bad(currentAuthority.error,currentAuthority.status);
  if(currentAuthority.fence!==authority.fence)return bad('navigation_assignment_changed',409);
  if(output.valid_until_ms<=clock())return bad('navigation_route_lease_expired',409);
  return respond({...output,endpoint:path.endsWith('/reroute')?'reroute':'route',route_session_updated:false,
   // Internal service consumers can bind optional route-session state to this
   // authenticated scope. This is not financial evidence or a new booking ID.
   session_scope:{...actor.scope,...(actor.driver_id?{driver_id:actor.driver_id}:{})}});
 }catch(error){
  const reason=typeof error?.message==='string'&&/^[a-z][a-z0-9_]{0,100}$/.test(error.message)?error.message:'navigation_route_unavailable';
  return bad(reason,422);
 }
}
