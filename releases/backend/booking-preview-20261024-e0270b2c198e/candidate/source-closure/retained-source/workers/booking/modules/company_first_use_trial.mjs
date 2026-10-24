import {loadTrialEntitlement} from './company_trial_entitlement.mjs';
const FIRST_USE_TRIAL_MS=14*86400000;
const firstUseText=x=>typeof x==='string'?x.trim():'';
export function firstUseOperationalEvent(event, now=Date.now()) {
 const at=Date.parse(event?.occurred_at ?? '');
 if(event?.kind!=='customer_booking_accepted'
   ||!firstUseText(event?.id)||event.id.length>200||!Number.isFinite(at)||!Number.isFinite(now)||at>now)
   throw Error('trial_first_use_event_invalid');
 return {kind:event.kind,id:event.id,occurred_at:new Date(at).toISOString()};
}
export async function firstUseTrialClock(storage,body,now=Date.now()){
 const tenant=firstUseText(body.tenant_id),company=firstUseText(body.company_id),cycle=firstUseText(body.cycle);
 if(!tenant||!company||tenant.length>160||company.length>160||!cycle||cycle.length>80||!Number.isFinite(now))throw Error('trial_first_use_scope_invalid');
 return storage.transaction(async txn=>{
  const old=await txn.get('first_use_trial_clock:v1');
  if(old&&(old.tenant_id!==tenant||old.company_id!==company||old.cycle!==cycle))throw Error('trial_first_use_scope_conflict');
  if(old||body.action==='first_use_trial_read')return old||null;
  if(body.action!=='first_use_trial_start')throw Error('trial_first_use_action_invalid');
  const event=firstUseOperationalEvent(body.operational_event,now);
  const start=Date.parse(event.occurred_at);
  const clock={tenant_id:tenant,company_id:company,cycle,started_at:event.occurred_at,ends_at:new Date(start+FIRST_USE_TRIAL_MS).toISOString(),operational_event:event};
  await txn.put('first_use_trial_clock:v1',clock);return clock;
 });
}
export async function firstUseTrialClockReadOnly(storage,body,now=Date.now()){
 const tenant=firstUseText(body?.tenant_id),company=firstUseText(body?.company_id),cycle=firstUseText(body?.cycle);
 if(!tenant||!company||tenant.length>160||company.length>160||!cycle||cycle.length>80
   ||!Number.isFinite(now)||typeof storage?.get!=='function')throw Error('trial_first_use_scope_invalid');
 const old=await storage.get('first_use_trial_clock:v1');
 if(old&&(old.tenant_id!==tenant||old.company_id!==company||old.cycle!==cycle))throw Error('trial_first_use_scope_conflict');
 return old||null;
}
export async function resolveFirstUseTrial(env,scope,profile,{start=false,operationalEvent=null,now=Date.now()}={}){
 if(profile?.trial_activation!=='first_use')return profile;
 if(!['trial_pending','trialing','free'].includes(profile.subscription_status))return profile;
 if(!scope?.tenant_id||!scope.company_id||profile.tenant_id!==scope.tenant_id||profile.company_id!==scope.company_id||!profile.created_at||!env.FLEET_ALLOCATOR)throw Error('trial_first_use_scope_invalid');
 const id=env.FLEET_ALLOCATOR.idFromName('first-use-trial:'+JSON.stringify([scope.tenant_id,scope.company_id]));
 // A boolean in a setup/eligibility call is never proof of operational use.
 const event=start&&operationalEvent?firstUseOperationalEvent(operationalEvent,now):null;
 const response=await env.FLEET_ALLOCATOR.get(id).fetch('https://fleet-allocator/internal',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({action:event?'first_use_trial_start':'first_use_trial_read',tenant_id:scope.tenant_id,company_id:scope.company_id,cycle:profile.created_at,...(event?{operational_event:event}:{})})});
 const result=await response.json();if(!response.ok||result.ok!==true)throw Error('trial_first_use_clock_unavailable');
 const clock=result.clock;
 if(!clock){
  if(profile.subscription_status!=='trial_pending'||profile.trial_started_at||profile.trial_ends_at)throw Error('trial_first_use_clock_missing');
  return {...profile,status:'trial_pending',subscription_status:'trial_pending',trial_started_at:null,trial_ends_at:null};
 }
 if(clock.tenant_id!==scope.tenant_id||clock.company_id!==scope.company_id||clock.cycle!==profile.created_at||!Number.isFinite(Date.parse(clock.started_at))||Date.parse(clock.ends_at)-Date.parse(clock.started_at)!==FIRST_USE_TRIAL_MS)throw Error('trial_first_use_clock_invalid');
 const override=env.BOOKING_KV?await loadTrialEntitlement(env.BOOKING_KV,{tenantId:scope.tenant_id,companyId:scope.company_id}):null;
 const effectiveEnd=override?.tenant_id===scope.tenant_id&&override?.company_id===scope.company_id&&override.actor_id&&override.reason&&Date.parse(override.trial_ends_at)>Date.parse(clock.ends_at)?Date.parse(override.trial_ends_at):Date.parse(clock.ends_at);
 const status=now<effectiveEnd?'trialing':'free';
 return {...profile,status,subscription_status:status,trial_started_at:clock.started_at,trial_ends_at:clock.ends_at};
}
