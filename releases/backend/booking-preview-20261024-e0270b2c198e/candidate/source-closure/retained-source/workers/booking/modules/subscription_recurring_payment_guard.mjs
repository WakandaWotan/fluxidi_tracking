import {loadRecurringTaxSnapshot} from './subscription_checkout_tax.mjs';
import {buildSubscriptionInvoiceDraft} from './subscription_invoice_draft.mjs';

// Protect entitlement mutation with the same immutable evidence used for invoicing.
export async function reviewedRecurringPaymentGuard(env,{scope,profile,payment,configuredMode}){
  const required=['standard','smart'].includes(profile?.plan_code)||payment?.metadata?.fluxidi_tax_snapshot_id!==undefined;
  if(!required)return {ok:true,required:false};
  if(profile?.provider_subscription_id!==payment?.subscriptionId||profile?.provider_customer_id!==payment?.customerId)
    return {ok:false,error:'subscription_recurring_contract_identity_conflict'};
  const evidence=await loadRecurringTaxSnapshot(env,scope,payment.subscriptionId,payment.metadata?.fluxidi_tax_snapshot_id);
  if(!evidence)return {ok:false,error:'subscription_recurring_fiscal_evidence_unproved'};
  const checked=buildSubscriptionInvoiceDraft(payment,evidence,{providerFetched:true,configuredMode});
  if(!checked.ok)return {ok:false,error:checked.error};
  return {ok:true,required:true};
}
