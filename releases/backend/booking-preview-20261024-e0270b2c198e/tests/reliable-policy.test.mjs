import test from'node:test';import a from'node:assert/strict';
import{createReliableChoiceDispatchV1}from'../candidate/source-closure/retained-source/workers/booking/modules/reliable_canonical_bridge_v1.mjs';
import{REQUIRED_BUSINESS_GATES}from'../candidate/source-closure/retained-source/workers/booking/modules/reliable_candidate_v1.mjs';
import{sanitizeAsapEtaAdvisory}from'../candidate/source-closure/retained-source/workers/booking/modules/pickup_timing_attention.mjs';
import{fleetFixture}from'./fleet-policy-fixture.mjs';
async function fixture({blocked=false,stale=false,conflict=false,hard=false,pricing=false,vehicleMismatch=false,committed=true}={}){
 const f=await fleetFixture(),now=Date.now(),scope={tenant_id:'T',company_id:'C'},context={...scope,region_id:'R',graphVersion:'G',evidenceRevision:'E'};
 const record=await f.x.f.read();record.pickup_mode='scheduled';record.p12_reliable_choice.startedAt=now-120000;
 record.vehicle_dispatch_attempts=Array.from({length:5},()=>({vehicle_id:'VD'}));if(hard)record.p12_reliable_choice.request_context={deadlineAt:now+130000};if(!committed)record.dispatch_offer.state='offered';
 const gps={latitude:51,longitude:4,capturedAt:now-(stale?120000:1000),accuracyMeters:3,access:{kind:'gps',capturedAt:now-(stale?120000:1000),accuracyMeters:3}};
 const candidate={...context,relation:'fleet',operationalBufferSeconds:0,driver:{...scope,driver_id:'D',vehicle_id:'VD',active:true,blocked,presence:{status:'online',observedAt:now},gps,trip:{state:'free'}},vehicle:{...scope,vehicle_id:'VD',active:true,blocked:false,category:'comfort',passenger_capacity:4,luggage_capacity:4,capabilities:[]}};
 if(vehicleMismatch)candidate.driver.vehicle_id='OTHER';
 let snapshotOptions,evaluations=0;
 const router={kind:'LOCAL_ROUTING_ONLY_V1',route:async()=>({...context,evidenceId:'SYNTHETIC',evidenceClass:'EXACT_STATIC_ROUTE',etaKind:'product_estimate',certifiedEta:false,seconds:181,distanceMeters:1,observedAt:now,validUntil:now+15000,quality:{productGrade:true,modelVersion:'fluxidi-product-estimated-eta-v1',validated:false,tier:'high',errorSeconds:30,reservationErrorSeconds:30,trafficState:'AVAILABLE',trafficConfidence:'high'}})};
 const bridge=createReliableChoiceDispatchV1({env:f.x.env,scope,companyCoordinator:{state:f.x.slot.state,env:f.x.env},alreadyCoordinated:true,publishAssignment:async()=>({ok:true}),clock:()=>now,loadSnapshot:async(r,id,options)=>{snapshotOptions=options;return{context,request:{...context,pickupMode:r.pickup_mode,pickupAt:Date.parse(record.pickup_iso),revalidation_offer:record.dispatch_offer,passengers:1,luggage:0,category:'comfort',capabilities:[],service:'passenger',serviceMinutes:20,pickup:{latitude:51.001,longitude:4.001},destination:{latitude:51.002,longitude:4.002}},candidates:[candidate],router,evaluateBusiness:async input=>{evaluations++;return{...context,allowed:!conflict,canonicalReason:conflict?'vehicle_cannot_reach_next_reservation':null,gates:Object.fromEntries(REQUIRED_BUSINESS_GATES.map(k=>[k,k!=='future_bookings'||!conflict])),checkedAt:now,validUntil:now+15000,arrivalWindow:input.arrivalWindow,plannedAvailabilityVerified:input.request.pickupMode==='scheduled'};}};}});
 return{record,now,call:()=>bridge.selectCandidate(record,'B',{confirmedAsapEtaAdvisory:true}),options:()=>snapshotOptions,evaluations:()=>evaluations};
}
test('Reliable Choice committed ASAP ignores discovery timeout and old arrival cap while retaining same resource and canonical pickup',async()=>{
 const f=await fixture(),before=JSON.stringify(f.record),r=await f.call();a.equal(r.ok,true,JSON.stringify(r));a.equal(f.options().confirmedAsapEtaAdvisory,true);a.equal(r.assignedDriverId,'D');a.equal(r.assignedVehicleId,'VD');a.equal(r.alloc.pickup_ms,Date.parse(f.record.pickup_iso));a.equal(r.alloc.asap_eta_advisory.duration_seconds,181);a(sanitizeAsapEtaAdvisory(r.alloc.asap_eta_advisory,f.now));a.equal(JSON.stringify(f.record),before);a.equal(f.evaluations(),1);
});
 for(const label of['blocked','stale','conflict','hard','uncommitted','vehicleMismatch'])test('Reliable Choice retains real gate: '+label,async()=>{
 const f=await fixture({[label]:true,...(label==='uncommitted'?{committed:false}:{})}),r=await f.call();a.equal(r.ok,false,JSON.stringify(r));
 if(label==='conflict')a.equal(f.evaluations(),1);if(['hard','uncommitted'].includes(label))a.notEqual(f.options()?.confirmedAsapEtaAdvisory,true);
});
