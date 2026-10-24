import {loadSubscriptionTaxDecision} from './subscription_checkout_tax.mjs';
export async function commandCenterTaxFacts(env,scope,now){
  const result=await loadSubscriptionTaxDecision(env,scope,now);
  if(!result.ok||!result.enabled)return null;
  const row=result.decision;
  return {schema_version:'command_center_tax_v1',provenance:'validated_subscription_tax_decision',source_revision:row.revision,price_basis:row.price_basis,vat_rate_bps:row.vat_rate_bps,treatment:row.treatment,customer_country:row.customer_country,effective_from:row.effective_from,valid_until:row.valid_until};
}
