import test from'node:test';import a from'node:assert/strict';import fs from'node:fs';import vm from'node:vm';
import{fleetFixture}from'./fleet-policy-fixture.mjs';
import{currentConfirmedAsapClaimIds}from'../candidate/source-closure/retained-source/workers/booking/modules/dispatch_provisional_claims.mjs';
const s=fs.readFileSync(new URL('../candidate/source-closure/retained-source/workers/booking/quote_handler_candidate.js',import.meta.url),'utf8'),begin=s.indexOf('    const committedIntent=record.dispatch_offer,'),end=s.indexOf('    const context={...scope,...router.scope}',begin),fragment=s.slice(begin,end);a(begin>0&&end>begin);
for(const scenario of['valid','valid_outbound','wrong_vehicle','wrong_tenant','scheduled'])test('actual Reliable snapshot envelope remains bound to committed Room claim: '+scenario,async()=>{
 const f=await fleetFixture(),record=await f.x.f.read(),scope={tenant_id:'T',company_id:'C'},r=await f.x.slot.room.fetch(new Request('https://room/live?tenant_id=T&company_id=C')),snapshot=await r.json();
 if(scenario==='wrong_vehicle')record.dispatch_offer.claims[0].vehicle_id='OTHER';if(scenario==='wrong_tenant')snapshot.tenant_id='OTHER';if(scenario==='scheduled')record.pickup_mode='scheduled';
 if(scenario==='valid_outbound'){record.dispatch_offer.claims[0].claim_id='B:OUTBOUND';record.dispatch_capacity_checkpoint.claims[0].claim_id='B:OUTBOUND';snapshot.capacity_reservations.find(c=>c.owner_id==='B').claim_id='B:OUTBOUND';}
 let verified;
 const ctx={record,scope,bookingId:'B',confirmedAsapEtaAdvisory:true,structuredClone,Math,normalizeFleetTenantScope:x=>({...x,hasScope:true}),router:{},allocator:{prepareReliableChoiceContext:async(normalized,router,envelope)=>{verified=currentConfirmedAsapClaimIds(snapshot,scope,envelope);if(!verified.length)throw Error('dispatch_confirmed_revalidation_unverified');return{};}}};vm.createContext(ctx);
 const run=vm.runInContext('(async()=>{'+fragment+'return true;})',ctx);
 if(scenario.startsWith('valid')){a.equal(await run(),true);a.deepEqual(verified,[record.dispatch_offer.claims[0].claim_id]);}else await a.rejects(run,/dispatch_confirmed_revalidation_unverified/);
});
