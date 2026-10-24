import test from'node:test';import a from'node:assert/strict';import fs from'node:fs';import{quoteConfiguredCompanyMission}from'../../candidate/source-closure/retained-source/workers/booking/modules/company_mission_quote.mjs';
const saved=JSON.parse(fs.readFileSync(new URL('./CURRENT_SETTINGS_VERIFIED.json',import.meta.url))).companies['cmp_taxi-mario_4b6d297325'].mission;
const tariff={...structuredClone(saved),depot:{lat:51.02,lng:4.02},local_municipality:'Synthetic'};delete tariff.depotCoordinatesValid;
function options(x={}){return{enabled:true,tariff,vehicleCategory:'car',pickup:{lat:51,lng:4},destination:{lat:51.01,lng:4.01},stops:[],pickupLocalDate:'2026-10-23',billingMode:'immediate',vatRate:.06,calculatedTariffEur:39.2,directions:async points=>({legs:points.slice(1).map(()=>({distance:14000,duration:1200}))}),municipality:async()=>['Other','Other'],...x};}
for(const [name,change,reason]of[
 ['missing authorized depot',{tariff:{...tariff,depot:null}},'mission_tariff_invalid'],
 ['invalid depot point',{tariff:{...tariff,depot:{lat:NaN,lng:4}}},'mission_tariff_invalid'],
 ['unresolved destination',{destination:{lat:NaN,lng:4}},'mission_location_unresolved'],
 ['missing VAT evidence',{vatRate:undefined},'vat_rate_required'],
])test(name+' cannot mint a mission price',async()=>{const r=await quoteConfiguredCompanyMission(options(change));a.equal(r.ok,false);a.equal(r.reason,reason);a.equal(r.pricing,undefined);});
