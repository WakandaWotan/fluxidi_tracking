import {affiliateAmountCents} from './affiliate_payment_adapter.mjs';

// Recovery only reads the existing provider subscription. No creation request.
export async function verifyRecurringRecovery(env,scope,record,{fetchImpl=fetch}={}){
  const key=env.FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY;
  if(!scope?.tenant_id||!scope?.company_id||record?.tenant_id!==scope.tenant_id||record?.company_id!==scope.company_id||!record.activation_id||!/^mdt_[A-Za-z0-9_-]{1,120}$/.test(record.mandate_id||'')||!Number.isSafeInteger(record.amount_cents)||record.amount_cents<=0||! /^[A-Z]{3}$/.test(record.currency||'')||record.interval!=='1 month'||!/^sub_[A-Za-z0-9_-]{1,120}$/.test(record?.provider_subscription_id||'')||!/^cst_[A-Za-z0-9_-]{1,120}$/.test(record?.customer_id||'')||typeof key!=='string'||! /^(live|test)_[A-Za-z0-9_-]+$/.test(key))return{ok:false,held_review:true};
  const target=`https://api.mollie.com/v2/customers/${record.customer_id}/subscriptions/${record.provider_subscription_id}`;
  let response,subscription;
  try{
    response=await fetchImpl(target,{method:'GET',redirect:'error',signal:AbortSignal.timeout(15000),headers:{Authorization:`Bearer ${key}`,Accept:'application/json'}});
    if(!response.ok)return{ok:false,retryable:response.status>=500||response.status===429,held_review:response.status<500&&response.status!==429};
    const text=await response.text();if(text.length>100000)return{ok:false,held_review:true};subscription=JSON.parse(text);
  }catch{return{ok:false,retryable:true};}
  const meta=subscription?.metadata;
  if(subscription?.resource!=='subscription'||subscription.id!==record.provider_subscription_id||subscription.customerId!==record.customer_id||subscription.status!=='active'||subscription.mandateId!==record.mandate_id||subscription.interval!==record.interval||subscription.amount?.currency!==record.currency||affiliateAmountCents(subscription.amount?.value)!==record.amount_cents||meta?.purpose!=='fluxidi_subscription_recurring'||meta?.kind!=='recurring'||meta?.tenant_id!==scope.tenant_id||meta?.company_id!==scope.company_id||meta?.activation_id!==record.activation_id)return{ok:false,held_review:true};
  return{ok:true,patch:{provider_customer_id:record.customer_id,provider_subscription_id:record.provider_subscription_id,mandate_id:record.mandate_id,recurring_amount_cents:record.amount_cents,recurring_currency:record.currency,recurring_interval:record.interval}};
}

// Recover durable history linkage independently of mutable profile state.
export async function recoverRecurringHistoryLink(env,scope,record,options={}){
  const verified=await verifyRecurringRecovery(env,scope,record,options);
  if(!verified.ok)return verified;
  const mode=env.FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY.startsWith('live_')?'live':'test';
  const link={tenant_id:scope.tenant_id,company_id:scope.company_id,mode,provider_subscription_id:verified.patch.provider_subscription_id,provider_customer_id:verified.patch.provider_customer_id};
  try{
    const binding=env.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
    if(!binding)return{ok:false,retryable:true};
    const response=await binding.get(binding.idFromName('provider-links')).fetch('https://private.invalid',{method:'POST',body:JSON.stringify({action:'subscription_provider_link_capture',link})});
    if(response.status===409)return{ok:false,held_review:true};
    if(!response.ok)return{ok:false,retryable:true};
    const result=await response.json();
    if(result.ok!==true||typeof result.created!=='boolean')return{ok:false,retryable:true};
    return{ok:true,recovered:true};
  }catch{return{ok:false,retryable:true};}
}

export async function captureInitialRecurringRecovery(env,{payment,providerFetched=false,configuredMode,loadFailure,fetchImpl=fetch}){
  const meta=payment?.metadata;
  if(meta?.purpose!=='fluxidi_subscription'||meta.kind!=='first'||payment.status!=='paid')return{ok:true,skipped:true};
  if(providerFetched!==true||payment.resource!=='payment'||payment.mode!==configuredMode||!['live','test'].includes(configuredMode)||typeof meta.activation_id!=='string'||!meta.activation_id||!meta.tenant_id||!meta.company_id)return{ok:true,held_review:true};
  let record;
  try{record=await loadFailure(meta.activation_id);}catch{return{ok:false,retryable:true};}
  if(!record?.provider_subscription_id)return{ok:true,skipped:true};
  if(record.activation_id!==meta.activation_id||record.customer_id!==payment.customerId)return{ok:true,held_review:true};
  const result=await recoverRecurringHistoryLink(env,{tenant_id:meta.tenant_id,company_id:meta.company_id},record,{fetchImpl});
  if(result.held_review)return{ok:true,held_review:true};
  return result;
}
