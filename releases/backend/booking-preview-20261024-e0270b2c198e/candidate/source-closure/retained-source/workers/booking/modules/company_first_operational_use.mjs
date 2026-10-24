import {readSubscriptionProfileSource} from './subscription_profile_source.mjs';
import {loadAccountLifecycle} from './company_account_lifecycle.mjs';
import {resolveFirstUseTrial} from './company_first_use_trial.mjs';
import {isInternalTestBooking} from './internal_test_booking.mjs';
import {isExcludedRide} from './ride_activity_summary.mjs';

// Called only after a server-owned customer assignment commit. Never accepts a
// public request body as the record. The canonical entitlement controls whether
// this company is still doing controlled tests, including on the live backend.
export async function recordFirstOperationalUse(env,scope,record,kind,{now=Date.now(),bookingId=record?.booking_id??record?.bookingId}={}) {
 if(!env?.BOOKING_KV)return {ok:true,skipped:'subscription_not_configured'};
 if(!scope?.tenant_id||!scope.company_id||record?.tenant_id!==scope.tenant_id||record?.company_id!==scope.company_id)
   throw Error('trial_first_use_scope_invalid');
 if((record.booking_id??record.bookingId)&&(record.booking_id??record.bookingId)!==bookingId)
   throw Error('trial_first_use_booking_conflict');
 const stored=await readSubscriptionProfileSource(env,scope,()=>env.BOOKING_KV.get(`tenant:${scope.tenant_id}:company:${scope.company_id}:subscription:v1`,{type:'json'}));
 const profile=stored?.subscription_profile??stored;
 if(profile?.plan_code!=='smart'||profile.trial_activation!=='first_use'
   ||!['trial_pending','trialing'].includes(profile.subscription_status))return {ok:true,skipped:'not_pending_smart_trial'};
 if(profile.trial_usage_mode!=='operational')return {ok:true,skipped:'controlled_test_or_unclassified'};
 if(['test','testing','fixture','local','development','staging'].includes(String(env.ENVIRONMENT??'').toLowerCase()))
   return {ok:true,skipped:'non_operational_environment'};
 const sources=[record,record.booking??{},record.payload??{}];
 if(isInternalTestBooking(record)||sources.some(isExcludedRide)
   ||sources.some(s=>[s.source,s.booking_source].some(value=>/^(admin|fixture|test|demo|setup|seed)(_|$)/i.test(String(value??'')))))
   return {ok:true,skipped:'non_operational_record'};
 const account=await loadAccountLifecycle(env.BOOKING_KV,{tenantId:scope.tenant_id,companyId:scope.company_id});
 if(account.state!=='active')return {ok:true,skipped:'company_not_active'};
 let occurredAt;
 if(kind==='customer_booking_accepted') {
  if(!record.customer_id||record.dispatch_offer?.state!=='committed'
    ||record.dispatch_offer.human_acceptance_required!==true
    ||!Object.values(record.dispatch_offer.execution_identities??{}).some(identity=>identity?.tenant_id===scope.tenant_id
      &&identity.company_id===scope.company_id&&identity.driver_id&&identity.vehicle_id&&identity.duty_id))
    return {ok:true,skipped:'no_customer_acceptance'};
  occurredAt=record.dispatch_offer.acknowledged_at;
 }else return {ok:true,skipped:'not_operational_event'};
 const created=Date.parse(profile.created_at),at=Date.parse(occurredAt);
 if(!Number.isFinite(created)||!Number.isFinite(at)||at<created)return {ok:true,skipped:'event_predates_entitlement'};
 // A setup -> operational transition is not a trial start. Its authority-owned
 // cutoff prevents retries of earlier controlled bookings from starting later.
 const operationalFrom=Date.parse(profile.trial_operational_from_at??'');
 const bookingCreated=Date.parse(record.created_at??record.createdAt??record.tenant_resolved_at??'');
 if(!Number.isFinite(operationalFrom)||operationalFrom<created||operationalFrom>at
   ||!Number.isFinite(bookingCreated)||bookingCreated<operationalFrom||bookingCreated>at)
   return {ok:true,skipped:'booking_outside_operational_window'};
 const profileWithClock=await resolveFirstUseTrial(env,scope,profile,{start:true,now,
   operationalEvent:{kind,id:String(bookingId??''),occurred_at:occurredAt}});
 return {ok:true,trial_started_at:profileWithClock.trial_started_at,trial_ends_at:profileWithClock.trial_ends_at};
}
