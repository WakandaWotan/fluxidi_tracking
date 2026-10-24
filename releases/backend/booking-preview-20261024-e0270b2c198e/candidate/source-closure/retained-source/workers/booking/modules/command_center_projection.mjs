import {normalizePaidContractSnapshot} from './subscription_paid_catalog.mjs';
const text=value=>typeof value==='string'?value.trim():'';
import {includedPdfCap} from './pdf_credits.mjs';
const pick=(row,fields)=>Object.fromEntries(fields.filter(key=>Object.hasOwn(row,key)).map(key=>[key,row[key]]));
const subscriptionFields=['plan_code','plan','subscription_status','status','market','currency','billing_test_mode','is_founder_customer','locked_price_cents','locked_extra_vehicle_unit_cents','locked_extra_driver_unit_cents','locked_total_recurring_cents','current_period_start','current_period_end','paid_until','next_charge_at','billing_interval','billing_interval_count','extra_vehicle_active_quantity','extra_driver_active_quantity','extra_vehicle_cancel_at_period_end_quantity','extra_driver_cancel_at_period_end_quantity','included_vehicles','max_vehicles','included_drivers','max_drivers','vehicle_used','driver_used','cancel_at_period_end','auto_renew','pdf_purchased_credits_remaining','pdf_monthly_allowance','pdf_included_monthly_limit','pdf_monthly_used','trial_started_at','trial_ends_at','trial_activation','source_revision','updated_at','created_at'];

export function commandCenterProjection({scope,index,businessProfile,rawSubscription,account,facts,observedAt=new Date().toISOString()}){
  const business=businessProfile?.business_profile??businessProfile?.profile??businessProfile;
  const subscription=rawSubscription?.subscription_profile??rawSubscription;
  if(!business||typeof business!=='object'||Array.isArray(business)||!subscription||typeof subscription!=='object'||Array.isArray(subscription)) throw Error('company_projection_source_unavailable');
  for(const row of [business,subscription])if((row.tenant_id&&row.tenant_id!==scope.tenant_id)||(row.company_id&&row.company_id!==scope.company_id))throw Error('company_projection_scope_conflict');
  const display=text(business.display_name??business.companyName??business.company_name??index.display_name);
  const updated=text(business.updated_at??businessProfile?.updated_at);
  const subUpdated=text(subscription.updated_at??rawSubscription?.updated_at);
  if(!display||!Number.isFinite(Date.parse(updated))||!Number.isFinite(Date.parse(subUpdated)))throw Error('company_projection_timestamp_unavailable');
  const contract=normalizePaidContractSnapshot(subscription.subscription_paid_contract_snapshot,{...scope,activation_id:subscription.activation_id});
  const contractProvenance=contract&&contract.activation_id===subscription.activation_id&&contract.plan_code===subscription.plan_code&&contract.currency===subscription.currency ? {schema_version:'command_center_contract_provenance_v1',catalog_version:contract.catalog_version,review_reference:contract.review_reference,recorded_at:contract.recorded_at,plan_code:contract.plan_code,market:contract.market,currency:contract.currency,price_basis:contract.price_basis,interval:contract.interval}:null;
  return{schema_version:'command_center_company_projection_v1',provenance:'booking_authority',company_code:scope.company_code,observed_at:observedAt,
    company:{...scope,display_name:display,market:text(business.market??business.country??subscription.market).toUpperCase()||null,
      linking_enabled:typeof index.linking_enabled==='boolean'?index.linking_enabled:null,
      account_enabled:typeof business.account_enabled==='boolean'?business.account_enabled:null,
      account_state:account.state??'unknown',source_revision:business.source_revision??null,updated_at:updated,
      contact_email:text(business.contact_email||business.email||business.companyEmail||business.company_email)||null,contact_phone:text(business.contact_phone||business.phone||business.phoneNumber)||null,
      vat_number:text(business.vat_number??business.vatNumber)||null},
    subscription:{...pick(subscription,subscriptionFields),contract_provenance:contractProvenance,...scope,updated_at:subUpdated,
      pdf_included_monthly_limit:Number.isSafeInteger(subscription.max_vehicles)&&subscription.max_vehicles>=0?includedPdfCap(subscription):null,
      pdf_usage_period_verified:!!subscription.pdf_usage_period_start&&subscription.pdf_usage_period_start===subscription.current_period_start&&Number.isFinite(Date.parse(subscription.current_period_start))&&Number.isFinite(Date.parse(subscription.current_period_end))&&Date.parse(subscription.current_period_start)<=Date.parse(observedAt)&&Date.parse(observedAt)<Date.parse(subscription.current_period_end)},facts};
}
