// Existing release wrapper and read host, retained around the current source.
import booking from '../../retained-source/workers/booking/quote_handler_candidate.js';
export * from '../../retained-source/workers/booking/quote_handler_candidate.js';
import {mountReadHost} from './deployment/read-addon.mjs';
import {customerTransientRouteV1} from '../../retained-source/workers/booking/modules/customer_transient_route_v1.mjs';
import {stagingTrialIngressV1} from '../../retained-source/workers/booking/modules/staging_trial_ingress_v1.mjs';
import {observeAvailabilityOutcomeRequestV1} from '../../retained-source/workers/booking/modules/dispatch_trace.mjs';
const readHost=mountReadHost(booking),quotePaths=new Set(['/quote','/public/quote','/public/customer/vehicle-quotes']);
export default {...booking,async fetch(request,env,ctx){
  const stagingTrialRefusal=stagingTrialIngressV1(request,env);
  if(stagingTrialRefusal)return observeAvailabilityOutcomeRequestV1(request,env,async capture=>{
    capture?.stage('trial_ingress');
    capture?.outcome({error:stagingTrialRefusal.status===503?'staging_trial_configuration_required':'staging_trial_operation_not_allowed'});
    return stagingTrialRefusal;
  });
  const path=new URL(request.url).pathname;
  if(path==='/track/internal/customer-route'&&request.method==='POST'){
    const token=(request.headers.get('authorization')??'').replace(/^Bearer\s+/i,'').trim();
    if(!env.ADMIN_TOKEN?.trim()||token!==env.ADMIN_TOKEN.trim())return Response.json({ok:false,error:'unauthorized'},{status:401});
    const text=await request.text();if(new TextEncoder().encode(text).byteLength>4096)return Response.json({ok:false,error:'body_limit'},{status:413});
    try{return Response.json(await customerTransientRouteV1(env,JSON.parse(text)),{headers:{'cache-control':'no-store'}});}
    catch(e){return Response.json({ok:false,error:e.message==='tracking_route_rate_limited'?'rate_limited':'route_unavailable'},{status:e.message==='tracking_route_rate_limited'?429:503,headers:{'cache-control':'no-store'}});}
  }
  if(env.BOOKING_WRITER_PAUSE_ENABLED==='1'&&request.method==='POST'&&quotePaths.has(path))return Response.json({ok:false,error:'owned_quote_activation_hold',booking_allowed:false,price_incl_vat:null},{status:503});
  if(request.method==='POST'&&['/book','/public/book'].includes(path)){
    let body;try{body=await request.clone().json();}catch{return Response.json({ok:false,error:'invalid_body'},{status:400});}
    if(!body?.financial_quote_id)return Response.json({ok:false,error:'financial_quote_required'},{status:409});
  }
  return await readHost(request,env,ctx)||booking.fetch(request,env,ctx);
}};
