import test from'node:test';import a from'node:assert/strict';import fs from'node:fs';
import{finalizeCompanyMissionAmount}from'../../candidate/source-closure/retained-source/workers/booking/modules/company_mission_pricing.mjs';
const saved=JSON.parse(fs.readFileSync(new URL('./CURRENT_CONFIG_SAFE.json',import.meta.url))).companies['cmp_taxi-mario_4b6d297325'].mission;
for(const billingMode of ['immediate','business_invoice']){
 test('existing floor retains trusted 85 EUR fare above 60-minute floor: '+billingMode,()=>{const r=finalizeCompanyMissionAmount({tariff:saved,calculatedTariffEur:85,missionMinutes:60,billingMode});a.equal(r.ok,true);a.equal(r.amount_cents,8500);a.equal(r.minimum_amount_cents,6000);a.equal(r.minimum_applied,false);a.equal(r.vat_basis,billingMode==='immediate'?'inclusive':'exclusive');});
 test('existing helper detects 85 EUR fare below full 180-minute floor: '+billingMode,()=>{const r=finalizeCompanyMissionAmount({tariff:saved,calculatedTariffEur:85,missionMinutes:180,billingMode});a.equal(r.ok,true);a.equal(r.amount_cents,18000);a.equal(r.minimum_applied,true);});
}
for(const missionMinutes of [undefined,NaN,-1,Infinity])test('no floor from invalid mission duration '+String(missionMinutes),()=>{a.equal(finalizeCompanyMissionAmount({tariff:saved,calculatedTariffEur:85,missionMinutes,billingMode:'immediate'}).reason,'complete_mission_duration_required');});
test('passenger duration is not the complete mission: same saved floor produces different amounts',()=>{const calculate=missionMinutes=>finalizeCompanyMissionAmount({tariff:saved,calculatedTariffEur:85,missionMinutes,billingMode:'immediate'});a.equal(calculate(60).amount_cents,8500);a.equal(calculate(180).amount_cents,18000);});
