import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';import test from 'node:test';
const root=import.meta.dirname,base=fs.readFileSync(new URL('../active/fluxidi-booking-api/entry.mjs',import.meta.url),'utf8'),candidate=fs.readFileSync(process.env.CANDIDATE_RUNTIME,'utf8');
const extract=s=>s.slice(s.indexOf('function currentConfirmedAsapClaimIds('),s.indexOf('\nvar init_dispatch_provisional_claims',s.indexOf('function currentConfirmedAsapClaimIds(')));
assert.equal(extract(base).replace(/\bsame\d+\b/g,'same'),extract(candidate).replace(/\bsame\d+\b/g,'same'));const ctx={};vm.createContext(ctx);vm.runInContext(extract(candidate)+'\nthis.check=currentConfirmedAsapClaimIds',ctx);
const scope={tenant_id:'tenant-a',company_id:'company-a'},claim={claim_id:'booking-a:OUTBOUND',driver_id:'driver-a',vehicle_id:'vehicle-a',start_ms:1000000,end_ms:3100000,active:false};
function fixture(){const body={revalidation_confirmed_asap:true,action:'suggest',pickup_mode:'scheduled',booking_id:'booking-a',revalidation_canonical_version:4,revalidation_record_revision:2,required_vehicle_id:'vehicle-a',service_min:35,pickup_ms:1000000,revalidation_offer:{state:'committed',owner_id:'booking-a',offer_id:'offer-a',version:3,record_revision:2,record_canonical_version:2,asap_requested_ms:500000,asap_search_expires_ms:1100000,claims:[{...claim}]},revalidation_checkpoint:{version:3,claims:[{...claim}]}};const snapshot={...scope,capacity_reservations:[{...claim,...scope,owner_id:'booking-a',offer_id:'offer-a',capacity_version:3,capacity_pending:false,capacity_offer_state:'committed'}]};return {body,snapshot};}
test('verified committed claim accepted',()=>{const x=fixture();assert.equal(ctx.check(x.snapshot,scope,x.body).length,1)});
for(const [label,change] of [
 ['wrong tenant',x=>x.snapshot.tenant_id='tenant-b'],
 ['wrong driver',x=>x.snapshot.capacity_reservations[0].driver_id='driver-b'],
 ['wrong vehicle',x=>x.body.required_vehicle_id='vehicle-b'],
 ['pending capacity',x=>x.snapshot.capacity_reservations[0].capacity_pending=true],
 ['uncommitted offer',x=>x.body.revalidation_offer.state='offered'],
 ['active trip',x=>x.snapshot.capacity_reservations[0].active=true],
 ['expired reservation',x=>x.snapshot.capacity_reservations[0].reservation_expired=true],
 ['wrong canonical version',x=>x.body.revalidation_canonical_version=1],
 ['caller flag without checkpoint',x=>delete x.body.revalidation_checkpoint]
])test(label+' cannot authorize confirmed ASAP',()=>{const x=fixture();change(x);assert.equal(ctx.check(x.snapshot,scope,x.body).length,0)});
