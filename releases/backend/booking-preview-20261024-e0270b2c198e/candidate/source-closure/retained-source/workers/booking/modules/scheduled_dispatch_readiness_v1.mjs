import {vehicleDispatchPreparation} from './company_vehicle_dispatch_policy.mjs';
import {readFinancialDispatchPriceV2} from './financial_dispatch_price_v2.mjs';
import {missionDispatchPricingConstraint} from './company_mission_dispatch_pricing.mjs';
const same=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const token=(v,max=200)=>typeof v==='string'&&v.length>0&&v.length<=max&&/^[a-zA-Z0-9_.:-]+$/.test(v);

// Internal transport for the existing scheduled ACK contract. Inputs are an
// authenticated paired session and fresh Room offers, never request JSON.
// Receipt is not human acceptance, an ASAP lease or route evidence.
export async function scheduledReadinessReceiptsV1(env,scope,session,offers,{clock=Date.now}={}){
 if(env.COMPANY_VEHICLE_OPERATIONS_ENABLED!=='1'||!same(session,scope)
   ||!token(session?.driver_id,96)||!token(session?.assigned_vehicle_id,128)
   ||!token(session?.vehicle_device_id,128))return [];
 const candidates=(Array.isArray(offers)?offers:[]).slice(0,8).filter(o=>
   (o.human_acceptance_required===undefined||o.human_acceptance_required===false)
   &&o.state==='offered'&&o.vehicle_id===session.assigned_vehicle_id
   &&token(o.offer_id)&&token(o.owner_id)&&Number.isSafeInteger(o.version)&&o.version>0
   &&Number.isFinite(o.ack_deadline_ms)&&o.ack_deadline_ms>clock());
 if(!candidates.length)return [];
 const raw=await env.BOOKING_KV.get(`tenant:${scope.tenant_id}:company:${scope.company_id}:business_profile:v1`,{type:'json'});
 if(!raw)return [];
 const profile=raw.business_profile??raw,receipts=[];
 for(const offer of candidates){
   const record=await env.BOOKING_KV.get('booking:'+offer.owner_id,{type:'json'}),intent=record?.dispatch_offer;
   if(!same(record,scope)||record.pickup_mode!=='scheduled'
     ||record.do_not_dispatch===true||record.company_confirmation_required===true
     ||record.assigned_driver_id||record.assigned_vehicle_id
     ||['CANCELLED','CANCELED','COMPLETED','STOPPED','EXPIRED','NO_SHOW'].includes(String(record.status).toUpperCase())
     ||intent?.offer_id!==offer.offer_id||intent.version!==offer.version
     ||intent.driver_id!==session.driver_id||intent.vehicle_id!==session.assigned_vehicle_id
     ||intent.human_acceptance_required===true)continue;
   let priceProof;
   try {priceProof=await readFinancialDispatchPriceV2(env,scope,record,offer.owner_id);}catch{continue;}
   const constraint=missionDispatchPricingConstraint(record,scope,priceProof);
   if(!constraint.ok||constraint.constrained&&!constraint.vehicle_ids.includes(session.assigned_vehicle_id))continue;
   const retained=vehicleDispatchPreparation(profile,record,priceProof);
   const current=vehicleDispatchPreparation(profile,{...record,vehicle_operating_policy_snapshot:null},priceProof);
   if(!retained.ok||retained.mode!=='existing'||!current.ok||current.mode!=='existing')continue;
   const pickup=record.pickup_iso??record.booking?.pickup_iso??record.booking?.pickupStartIso;
   if(typeof pickup!=='string'||!Number.isFinite(Date.parse(pickup))||Date.parse(pickup)<=clock())continue;
   receipts.push({schema:'fluxidi-scheduled-readiness-v1',readiness_type:'scheduled_readiness',
     ...scope,driver_id:session.driver_id,vehicle_id:session.assigned_vehicle_id,
     booking_id:offer.owner_id,offer_id:offer.offer_id,version:offer.version,
     human_acceptance_required:false,ack_deadline_ms:offer.ack_deadline_ms,pickup_iso:pickup});
 }
 return receipts;
}
