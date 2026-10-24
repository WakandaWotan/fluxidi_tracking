// New account baseline, never a migration of existing subscription evidence.
export function buildFreeCompanySubscriptionProfile({tenantId,companyId,market='',currency='EUR',billingEmail='',now=Date.now()}={}){
  if(!tenantId||!companyId||!Number.isFinite(now)||! /^[A-Z]{3}$/.test(currency))throw Error('free_subscription_configuration_invalid');
  const timestamp=new Date(now).toISOString();
  return{tenant_id:tenantId,company_id:companyId,plan_code:'free',subscription_status:'free',market,currency,
    trial_activation:null,trial_started_at:'',trial_ends_at:'',white_label:false,
    activated_at:'',cancelled_at:'',current_period_start:'',current_period_end:'',locked_price_cents:null,
    normal_price_cents:null,founder_price_cents:null,is_founder_customer:false,founder_slot_number:null,
    founder_assigned_at:'',payment_provider:'',provider_customer_id:'',provider_subscription_id:'',
    billing_email:billingEmail,created_at:timestamp,updated_at:timestamp,warnings:[]};
}
