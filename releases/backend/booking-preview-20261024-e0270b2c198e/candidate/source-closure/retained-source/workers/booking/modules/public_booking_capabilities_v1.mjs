import {reliableChoiceEnabled} from './reliable_prebooking_v1.mjs';
import {mapboxAutomaticDispatchEnabledV1} from './mapbox_quote_request_v1.mjs';
export const PUBLIC_BOOKING_CAPABILITIES_V1='fluxidi-public-booking-capabilities-v1';
const response=(body,status=200)=>Response.json(body,{status,headers:{'cache-control':'no-store'}});
// Canonical account/plan decisions, not a public profile's price or a client
// plan hint. This read contract also works before the routing feature is on.
export async function handlePublicBookingCapabilitiesV1({request,env,loadCustomerSession,resolveRequestScope,operationDecision,admitPublicPreview}){
 if(new URL(request.url).pathname!=='/public/customer/booking-capabilities')return null;
 if(request.method!=='POST')return response({ok:false,error:'method_not_allowed'},405);
 const hasAuthorization=request.headers.has('authorization');
 const session=hasAuthorization?await loadCustomerSession(request,env):null;
 if(hasAuthorization&&!session?.customer_id)return response({ok:false,error:'unauthorized'},401);
 const text=await request.text();if(text.length>8192)return response({ok:false,error:'request_too_large'},413);
 let body;try{body=JSON.parse(text);}catch{return response({ok:false,error:'invalid_json'},400);}
 if(!body||Array.isArray(body)||typeof resolveRequestScope!=='function'||typeof operationDecision!=='function')return response({ok:false,error:'request_invalid'},400);
 const scope=await resolveRequestScope(body);if(!scope?.ok)return response({ok:false,error:scope?.error??'forbidden'},scope?.status??403);
 if(session&&!(session.tenant_id==='global'&&session.company_id==='global')&&
   (session.tenant_id!==scope.tenant_id||session.company_id!==scope.company_id))return response({ok:false,error:'unauthorized'},401);
 if(!session){
  if(typeof admitPublicPreview!=='function')return response({ok:false,error:'unauthorized'},401);
  const admission=await admitPublicPreview(request,env);
  if(!admission.ok)return response(admission.out,admission.status);
 }
 try{
  const decision=await operationDecision(scope,'create_company_booking');
  const dispatch=await operationDecision(scope,'automatic_dispatch');
  const tracking=await operationDecision(scope,'customer_live_tracking');
  const allowed=r=>r?.applicable===true&&r.ok===true;
  const provider=mapboxAutomaticDispatchEnabledV1(env,scope);
  const booking=allowed(decision),automatic=booking&&allowed(dispatch)&&(provider||reliableChoiceEnabled(env)),live=!!session&&booking&&allowed(tracking);
  // Smart without its own core must not silently use premium legacy dispatch.
  const mode=automatic?(provider?'provider_automatic':'reliable_choice'):booking&&decision.effective_plan==='standard'?'manual':'unavailable';
  return response({ok:true,schema:PUBLIC_BOOKING_CAPABILITIES_V1,booking_mode:mode,booking_allowed:booking,automatic_dispatch:automatic,customer_live_tracking:live});
 }catch{return response({ok:false,error:'booking_capabilities_unavailable'},503);}
}
