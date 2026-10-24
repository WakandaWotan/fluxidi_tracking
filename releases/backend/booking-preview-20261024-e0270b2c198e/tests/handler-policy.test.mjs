import test from'node:test';import a from'node:assert/strict';import{fleetFixture}from'./fleet-policy-fixture.mjs';
import worker from'../candidate/source-closure/retained-source/workers/booking/quote_handler_candidate.js';
test('actual private dispatch-event HTTP handler carries advisory capability through canonical writer and native Fleet checks',async()=>{
 const f=await fleetFixture(),record=await f.x.f.read();delete record.p12_reliable_choice;await f.x.env.BOOKING_KV.put('booking:B',JSON.stringify(record));
 let received;f.x.f.env.FLEET_ALLOCATOR={idFromName:n=>n,get:()=>({fetch:async(req,init)=>{received=await(req instanceof Request?req:new Request(req,init)).json();const r=await f.fleet._allocate(received,f.context);return r instanceof Response?r:Response.json(r.json?await r.json():r);}})};
 const response=await f.x.f.http('/track/dispatch/event',{tenant_id:'T',company_id:'C',event_id:f.x.intent.offer_id+':revalidate'}),data=await response.json();a.equal(response.status,200,JSON.stringify(data));a.equal(data.ok,true,JSON.stringify(data));a.equal(received.revalidation_eta_advisory,true);const after=await f.x.f.read();a.equal(after.assigned_driver_id,'D');a.equal(after.assigned_vehicle_id,'VD');a.equal(after.dispatch_offer.state,'committed');a.equal(after.dispatch_timing_attention.eta.duration_seconds,1);a.deepEqual(after.dispatch_capacity_checkpoint,record.dispatch_capacity_checkpoint);
 for(let refresh=0;refresh<2;refresh++){
  const res=await worker.fetch(new Request('https://booking/driver/bookings',{headers:{authorization:'Bearer token-D'}}),f.x.f.env,{}),body=await res.json();a.equal(res.status,200,JSON.stringify(body));const row=body.items.find(r=>(r.booking_id||r.bookingId||r.id)==='B');a(row,JSON.stringify(body));a.equal(row.assigned_driver_id,'D');a.notEqual(row.available_unassigned,true);a.equal(row.dispatch_timing_attention.eta.duration_seconds,1);
 }
});
