import assert from 'node:assert/strict';import {createHash} from 'node:crypto';
import {fixture,scope} from '../backend-fixture.mjs';
import {withCanonicalBookingAuthority} from '../backend/retained-source/workers/booking/modules/canonical_booking_authority.mjs';
import {prepareCanonicalDispatchOffer,consumeCanonicalDispatchEvent} from '../backend/retained-source/workers/booking/modules/company_dispatch_delivery.mjs';
import {handleNationalNavigationHttpV1} from '../backend/retained-source/workers/booking/modules/national_navigation_http_v1.mjs';
export const tokenHash=t=>createHash('sha256').update(t).digest('hex');
export async function authFixture({commit=true,vehicleDuty=false,vehicleDevice=false}={}){
 const f=await fixture({authority:true,vehicleOperations:true});
 for(const id of ['D','E']){const key='public_driver:session:'+tokenHash('token-'+id)+':v1',s=JSON.parse(f.records.get(key));s.assigned_vehicle_id='V'+id;f.records.set(key,JSON.stringify(s));}
 const raw=await f.read();raw.p12_reliable_choice={schema:'fluxidi-reliable-choice-v1',kind:'exact',vehicle_id:'VD',passengers:1,luggage:0};f.records.set('booking:B',JSON.stringify(raw));
 if(vehicleDuty){
  f.slot().data.set('vehicle_duty_active_v1',{...scope,version:1,duties:[{duty_id:'DUTY',driver_id:'D',vehicle_id:'VD',...(vehicleDevice?{vehicle_device_id:'DEVICE'}:{}),started_at_ms:Date.now()-60000,ended_at_ms:null,paused_at_ms:null,pause_intervals:[]}]});
 }
 if(vehicleDevice){
  const key='public_driver:session:'+tokenHash('token-D')+':v1',s=JSON.parse(f.records.get(key));Object.assign(s,{vehicle_device_id:'DEVICE',vehicle_device_token_hash:tokenHash('vehicle')});f.records.set(key,JSON.stringify(s));
  const slot=f.slot();slot.storage.transaction=fn=>fn(slot.storage);
  slot.data.set('vehicle_device_scope_v1',scope);slot.data.set('vehicle_device_v1:DEVICE',{device_id:'DEVICE',vehicle_id:'VD',token_hash:tokenHash('vehicle'),expires_at_ms:Date.now()+3600000,revoked:false});
  const registered=await f.roomPost('dispatch-device',{driver_id:'D',device_key:tokenHash('token-D'),vehicle_device_id:'DEVICE',protocol:1,session_expires_ms:Date.now()+3600000});assert.equal(registered.status,200);
 }
 const env=withCanonicalBookingAuthority(f.env);assert.equal((await prepareCanonicalDispatchOffer(env,scope,'B',f.hooks)).ok,true);
 const intent=(await env.BOOKING_KV.get('booking:B',{type:'json'})).dispatch_offer;
 const ack=await f.http('/public/driver/dispatch/ack',{offer_id:intent.offer_id,version:intent.version},'token-D');assert.equal(ack.status,200,await ack.clone().text());
 const decision=await f.http('/public/driver/dispatch/decision',{offer_id:intent.offer_id,version:intent.version,action:'accept'},'token-D');assert.equal(decision.status,200,await decision.clone().text());
 if(commit){const result=await consumeCanonicalDispatchEvent(env,scope,{event_id:intent.offer_id+':commit'},f.hooks);assert.equal(result.ok,true,JSON.stringify(result));}
 Object.assign(env,{NATIONAL_NAVIGATION_ENABLED:'1',BOOKING_NAVIGATION_IP_LIMITER:{limit:async()=>({success:true})},BOOKING_NAVIGATION_CLIENT_LIMITER:{limit:async()=>({success:true})}});
 const read=()=>env.BOOKING_KV.get('booking:B',{type:'json'});
 const actor={role:'driver',scope,driver_id:'D',vehicle_id:'VD',session_hash:tokenHash('token-D'),session_expires_ms:Date.now()+3600000,...(vehicleDevice?{vehicle_device_id:'DEVICE'}:{})};
 const geometry=[{latitude:51,longitude:4},{latitude:51,longitude:4.001}],edge={id:1,way:100,ordinal:0,direction:1,seconds:10,distanceMeters:100};
 const routingScope={...scope,graphVersion:'G',evidenceRevision:'E'};
 let graphCalls=0,routeArgs;
 const run=(payload={},options={})=>handleNationalNavigationHttpV1({request:new Request('https://fixture/company/navigation/'+(options.reroute?'reroute':'route'),{method:'POST',headers:{'content-type':'application/json','cf-connecting-ip':'192.0.2.1',authorization:'Bearer token-D'},body:JSON.stringify({origin:{lat:51,lng:4},destination:{lat:51,lng:4.001},...payload})}),env,
  authenticate:async()=>actor,createRouter:async()=>({kind:'LOCAL_ROUTING_ONLY_V1',scope:routingScope,resolveForJourney:async()=>{},navigationRoute:async args=>{graphCalls++;routeArgs=args;await options.onRoute?.();return {...routingScope,evidenceId:'SYNTHETIC',validUntil:Date.now()+60000,distanceMeters:100,seconds:10,geometry,navigationEvidence:{...routingScope,schema:'fluxidi-directed-navigation-evidence-v1',coreEvidenceId:'SYNTHETIC',staticSeconds:10,edges:[edge],roads:[{...edge,fullDistanceMeters:100,fromNode:1,toNode:2,from:geometry[0],to:geometry[1],tags:{streetNames:['Teststraat'],highway:'residential'},options:[],junctionComplete:true}]}};}}),...options});
 return {f,env,intent,actor,read,run,graphCalls:()=>graphCalls,routeArgs:()=>routeArgs,scope,
  async mutate(change){const record=await read();change(record);await env.BOOKING_KV.put('booking:B',JSON.stringify(record));},
  async start(){await this.mutate(r=>{r.customer_tracking_phase='in_progress';r.trip={session_id:'SESSION',trip_id:'TRIP',started_at:new Date().toISOString(),operational_leg:'primary',assignment_version:r.customer_tracking_assignment_version};});
   for(const [kind,id] of [['session','SESSION'],['trip','TRIP']])f.records.set(`tenant:T:company:C:tracking:${kind}:${id}:booking:v1`,JSON.stringify({booking_id:'B'}));}
 };
}
