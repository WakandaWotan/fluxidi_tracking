import test,{mock} from'node:test';import a from'node:assert/strict';import{createHash}from'node:crypto';
import {fixture,scope} from'./backend-fixture.mjs';
import {withCanonicalBookingAuthority} from'../candidate/source-closure/retained-source/workers/booking/modules/canonical_booking_authority.mjs';
import {prepareCanonicalDispatchOffer,consumeCanonicalDispatchEvent} from'../candidate/source-closure/retained-source/workers/booking/modules/company_dispatch_delivery.mjs';
import {queueConfirmedSuccessorChecks} from'../candidate/source-closure/retained-source/workers/tracking/modules/company_dispatch_offers.mjs';
import {projectPickupTimingAttention} from'../candidate/source-closure/retained-source/workers/booking/modules/pickup_timing_attention.mjs';
import {committed,now} from './committed-fixture.mjs';
const rejection={ok:false,reason:'not_allowed',allocator_reason:'vehicle_cannot_reach_pickup_in_time',alloc:{allowed:false,reason:'vehicle_cannot_reach_pickup_in_time',available_seconds:132,required_seconds:181,origin_travel_seconds:181}};
function eta(seconds=181){return {reason:'asap_eta_updated',estimated:true,status:'available',duration_seconds:seconds,eta_range_seconds:[seconds,seconds+30],arrival_at:new Date(Date.now()+(seconds+30)*1000).toISOString(),generated_at_ms:Date.now(),valid_until_ms:Date.now()+15000,source:'fluxidi/local-product-estimate',certified_eta:false};}
async function recheck(x,{seconds=181,block='',publishFail=false}={}){
 let validation,publications=[];
 const result=await consumeCanonicalDispatchEvent(x.env,scope,{event_id:x.intent.offer_id+':revalidate'},{selectCandidate:async(rec,id,v)=>{if(v)validation=v;
  if(block)return {ok:false,reason:block,allocator_reason:block};
  return v?.confirmedAsapEtaAdvisory?{ok:true,assignedDriverId:'D',assignedVehicleId:'VD',alloc:{allowed:true,asap_eta_advisory:eta(seconds)}}:rejection;
 },publishAssignment:async(id,rec)=>{publications.push(structuredClone(rec));return{ok:!publishFail};}});
 return {result,validation,publications,after:await x.f.read()};
}
test('committed ASAP 181 versus 132 keeps canonical assignment, claims and price and publishes updated ETA',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed(),claims=JSON.stringify(x.before.dispatch_capacity_checkpoint),r=await recheck(x);
 a.equal(r.result.ok,true,JSON.stringify(r.result));a.equal(r.validation.confirmedAsapEtaAdvisory,true);a.equal(r.after.assigned_driver_id,'D');a.equal(r.after.assigned_vehicle_id,'VD');a.equal(r.after.dispatch_offer.state,'committed');a.equal(JSON.stringify(r.after.dispatch_capacity_checkpoint),claims);a.equal(r.after.pickup_iso,x.before.pickup_iso);a.equal(r.after.revision,x.before.revision);a.equal(r.after.dispatch_timing_attention.reason,'asap_eta_updated');a.equal(r.after.dispatch_timing_attention.eta.duration_seconds,181);a.equal(r.publications.length,1);a.equal(projectPickupTimingAttention(r.after).eta.duration_seconds,181);
 }finally{mock.restoreAll();}
});
for(const seconds of[300,900])test('normal ASAP ETA delay '+seconds+' seconds is advisory after canonical commit',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed(),r=await recheck(x,{seconds});a.equal(r.after.assigned_driver_id,'D');a.equal(r.after.dispatch_timing_attention.eta.duration_seconds,seconds);}finally{mock.restoreAll();}
});
test('scheduled Later retains fixed-pickup revalidation and can retire an infeasible assignment',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed({asap:false}),r=await recheck(x);a.notEqual(r.validation.confirmedAsapEtaAdvisory,true);a(!r.after.assigned_driver_id);a.equal(r.after.dispatch_offer.reason,'confirmed_pickup_no_longer_feasible');}finally{mock.restoreAll();}
});
test('an explicit retained request deadline is not relaxed by ASAP policy',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed({hardDeadline:true}),r=await recheck(x);a.notEqual(r.validation.confirmedAsapEtaAdvisory,true);a(!r.after.assigned_driver_id);}finally{mock.restoreAll();}
});
test('human acceptance without final canonical commit still has the original ETA eligibility gate',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed({commit:false});let advisory=false;const r=await consumeCanonicalDispatchEvent(x.env,scope,{event_id:x.intent.offer_id+':commit'},{selectCandidate:async(rec,id,v)=>{advisory||=v?.confirmedAsapEtaAdvisory===true;return rejection;},publishAssignment:x.f.hooks.publishAssignment});a.notEqual(advisory,true);a(!(await x.f.read()).assigned_driver_id);a.notEqual((await x.f.read()).dispatch_offer.state,'committed');}finally{mock.restoreAll();}
});
test('canonical cancellation remains terminal and cannot acquire a new ETA or assignment',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed(),r=await x.f.read();r.status='CANCELLED';r.assigned_driver_id=null;r.assigned_vehicle_id=null;await x.env.BOOKING_KV.put('booking:B',JSON.stringify(r));const result=await recheck(x);a.equal(result.after.status,'CANCELLED');a.equal(result.after.assigned_driver_id,null);a.equal(result.publications.length,0);a.equal(projectPickupTimingAttention(result.after),null);}finally{mock.restoreAll();}
});
test('real authorization withdrawal is not hidden by an overdue ASAP estimate',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed();mock.method(Date,'now',()=>now+300000);const r=await recheck(x,{block:'assignment_driver_not_authorized'});a(!r.after.assigned_driver_id);a.equal(r.after.dispatch_offer.reason,'confirmed_pickup_no_longer_feasible');}finally{mock.restoreAll();}
});
for(const reason of['assignment_driver_not_authorized','dispatch_device_lease_unavailable','vehicle_capacity_exceeded','vehicle_cannot_reach_next_reservation'])test('real rejection retained: '+reason,async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed(),r=await recheck(x,{block:reason});a(!r.after.assigned_driver_id);a.equal(r.after.dispatch_offer.reason,'confirmed_pickup_no_longer_feasible');}finally{mock.restoreAll();}
});
test('missing technical evidence remains retryable and does not become permission',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed(),r=await recheck(x,{block:'company_live_unavailable'});a.equal(r.result.ok,false);a.equal(r.after.assigned_driver_id,'D');a.equal(r.after.dispatch_timing_attention,undefined);a.equal(r.publications.length,0);}finally{mock.restoreAll();}
});
test('advisory publication failure keeps assignment and pending retry; duplicate success is idempotent',async()=>{
 mock.method(Date,'now',()=>now);try{const x=await committed(),r=await recheck(x,{publishFail:true});a.equal(r.result.ok,false);a.equal(r.after.assigned_driver_id,'D');const g=await recheck(x);a.equal(g.result.ok,true);a.equal(g.after.assigned_driver_id,'D');const duplicate=await recheck(x);a.equal(duplicate.result.already_delivered,true);a.equal(duplicate.publications.length,0);}finally{mock.restoreAll();}
});
