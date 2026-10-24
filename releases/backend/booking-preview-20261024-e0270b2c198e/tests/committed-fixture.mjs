import test,{mock} from'node:test';import a from'node:assert/strict';import{createHash}from'node:crypto';
import {fixture,scope} from'./backend-fixture.mjs';
import {withCanonicalBookingAuthority} from'../candidate/source-closure/retained-source/workers/booking/modules/canonical_booking_authority.mjs';
import {prepareCanonicalDispatchOffer,consumeCanonicalDispatchEvent} from'../candidate/source-closure/retained-source/workers/booking/modules/company_dispatch_delivery.mjs';
import {queueConfirmedSuccessorChecks} from'../candidate/source-closure/retained-source/workers/tracking/modules/company_dispatch_offers.mjs';
import {projectPickupTimingAttention} from'../candidate/source-closure/retained-source/workers/booking/modules/pickup_timing_attention.mjs';
const now=Date.now();
export async function committed({asap=true,advance=0,commit=true,hardDeadline=false}={}){
 const f=await fixture({authority:true,vehicleOperations:true}),env=withCanonicalBookingAuthority(f.env),record=await f.read();
 for(const id of['D','E']){const key='public_driver:session:'+createHash('sha256').update('token-'+id).digest('hex')+':v1',s=JSON.parse(f.records.get(key));s.assigned_vehicle_id='V'+id;f.records.set(key,JSON.stringify(s));}
 record.p12_reliable_choice={schema:'fluxidi-reliable-choice-v1',kind:'exact',vehicle_id:'VD',passengers:1,luggage:0,...(hardDeadline?{request_context:{deadlineAt:now+132000}}:{})};
 Object.assign(record,{pickup_mode:asap?'asap':'scheduled',pickup_iso:new Date(now+132000).toISOString(),...(asap?{asap_requested_at:new Date(now-1000).toISOString(),asap_search_expires_at:new Date(now-1000+600000).toISOString()}:{})});
 Object.assign(record.booking,{pickup_mode:record.pickup_mode,pickup_iso:record.pickup_iso});f.records.set('booking:B',JSON.stringify(record));
 a.equal((await prepareCanonicalDispatchOffer(env,scope,'B',f.hooks)).ok,true);
 const intent=(await f.read()).dispatch_offer;
 a.equal((await f.http('/public/driver/dispatch/ack',{offer_id:intent.offer_id,version:intent.version},'token-D')).status,200);
 const decision=await f.http('/public/driver/dispatch/decision',{offer_id:intent.offer_id,version:intent.version,action:'accept'},'token-D');a.equal(decision.status,200,await decision.clone().text());
 if(commit){const c=await consumeCanonicalDispatchEvent(env,scope,{event_id:intent.offer_id+':commit'},f.hooks);a.equal(c.ok,true,JSON.stringify(c));}
 const slot=f.slot();slot.room.capacity=queueConfirmedSuccessorChecks(slot.room.capacity,now+advance);
 return {f,env,intent,slot,before:await f.read()};
}

export {now};
