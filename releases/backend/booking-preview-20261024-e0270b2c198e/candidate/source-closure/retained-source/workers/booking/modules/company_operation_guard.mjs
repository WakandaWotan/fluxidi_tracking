import {readSubscriptionProfileSource} from './subscription_profile_source.mjs';
import {loadAccountLifecycle} from './company_account_lifecycle.mjs';
import {loadTrialEntitlement} from './company_trial_entitlement.mjs';
import {resolveFirstUseTrial} from './company_first_use_trial.mjs';
import {companySubscriptionFacts,COMPANY_SUBSCRIPTION_OPERATIONS} from './company_subscription_facts.mjs';
import {loadInternalDevSubscriptionExemption,isScopedInternalDevSubscriptionExempt} from './internal_dev_subscription_exemption.mjs';
const modernPlans=new Set(['free','standard','smart']);
export function companyAgendaSubscriptionOperation(route,method){
  if(method==='POST'&&route?.kind==='rides')return 'create_company_booking';
  if(method==='POST'&&route?.kind==='quote')return 'respond_quote';
  if(!['POST','PATCH'].includes(method))return null;
  if(route?.kind==='assign')return 'assign_driver';
  if(['reschedule','operational-route','phone-confirm'].includes(route?.kind))return 'edit_booking';
  if(route?.kind==='unassign')return 'cancel_existing_trip';
  return null;
}
export function companyOperationDecision({profile,account,override,internalDevExemption,scope,operation,now=Date.now()}){
  const raw=profile?.subscription_profile??profile;
  const plan=String(raw?.plan_code??raw?.plan??'').trim().toLowerCase();
  if(!modernPlans.has(plan)&&!isScopedInternalDevSubscriptionExempt(internalDevExemption,scope))return{applicable:false};
  if(!COMPANY_SUBSCRIPTION_OPERATIONS.includes(operation))return{applicable:true,ok:false,error:'subscription_operation_not_supported'};
  if(!scope?.tenant_id||!scope.company_id||[raw,account].some(row=>row&&((row.tenant_id&&row.tenant_id!==scope.tenant_id)||(row.company_id&&row.company_id!==scope.company_id))))return{applicable:true,ok:false,error:'subscription_scope_conflict'};
  const facts=companySubscriptionFacts({profile:raw,account,override,internalDevExemption,scope,now});
  const decision=facts.operations[operation];
  return{applicable:true,ok:decision.allowed===true,...(decision.allowed===true?{}:{error:decision.reason||'subscription_access_required'}),effective_plan:facts.effective_plan,account_state:facts.account_state};
}

// Read-only canonical operation gate shared by Booking and native tracking.
// A revoked plan must also stop existing grants; reads never start a trial.
export async function readCompanyOperationDecision(env,scope,{operation='create_company_booking',startFirstUse=false}={}) {
  if(!env?.BOOKING_KV||!scope?.tenant_id||!scope.company_id)return {ok:true,applicable:false};
  try {
    const [stored,internalDevExemption]=await Promise.all([
      readSubscriptionProfileSource(env,scope,()=>env.BOOKING_KV.get(`tenant:${scope.tenant_id}:company:${scope.company_id}:subscription:v1`,{type:'json'})),
      loadInternalDevSubscriptionExemption(env.BOOKING_KV,{tenantId:scope.tenant_id,companyId:scope.company_id}),
    ]);
    const raw=stored?.subscription_profile??stored;
    const internalDev=isScopedInternalDevSubscriptionExempt(internalDevExemption,scope);
    if(!modernPlans.has(String(raw?.plan_code??raw?.plan??'').trim().toLowerCase())&&!internalDev)return {ok:true,applicable:false};
    const [account,override]=await Promise.all([
      loadAccountLifecycle(env.BOOKING_KV,{tenantId:scope.tenant_id,companyId:scope.company_id,companyCode:scope.company_code}),
      loadTrialEntitlement(env.BOOKING_KV,{tenantId:scope.tenant_id,companyId:scope.company_id}),
    ]);
    const profile=internalDev?raw:await resolveFirstUseTrial(env,scope,raw,{start:startFirstUse&&account.state==='active'});
    return companyOperationDecision({profile,account,override,internalDevExemption,scope,operation});
  }catch{return {ok:false,error:'subscription_source_unavailable'};}
}
