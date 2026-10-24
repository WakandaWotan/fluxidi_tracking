// Classification only. Never calculates, changes or rounds a monetary amount.
// Called after the existing catalogue/engine chooses the actual leg sources,
// and before any new financial evidence is persisted.
const fixedSources=new Set(['airport_fixed_fare','company_fixed_price']);
const finite=n=>typeof n==='number'&&Number.isFinite(n)&&n>=0;
export function financialPriceIndependenceV1({body,quote,pricingProfile,missionMain,returnMission,mainUsesFixedFare,returnUsesFixedFare,returnPackage}){
 const reasons=[];
 const leg=(which,source,fixed,mission,breakdown)=>{
  // Actual catalogue matches are excluded from company-mission pricing by
  // the existing handler. Do not apply a fictional mission floor to them.
  if(fixed&&fixedSources.has(source))return;
  if(source==='company_mission'){
   const tariff=mission?.tariff_evidence;
   if(!mission?.ok||!tariff||!finite(tariff.minimum_per_minute_eur)){reasons.push(which+':mission_time_policy_unknown');return;}
   if(breakdown?.local_meter===true&&tariff.local_minimum_applies===false)return;
   if(tariff.minimum_per_minute_eur===0)return;
   reasons.push(which+':mission_duration_minimum_requires_approval');return;
  }
  if(source==='route_calc'){
   if(finite(pricingProfile?.price_per_minute)&&pricingProfile.price_per_minute===0)return;
   reasons.push(which+':route_duration_price_requires_approval');return;
  }
  reasons.push(which+':price_time_dependence_unproven');
 };
 if(returnPackage?.matched===true){
  if(quote?.return_package_applied===true&&quote?.pricing_source==='airport_fixed_fare')return {ok:true,reasons:[],classification:'matched_fixed_return_package'};
  return {ok:false,reasons:['return:fixed_package_unproven']};
 }
 leg('outbound',quote?.pricing_source_main??quote?.pricing_source,mainUsesFixedFare,missionMain,quote?.breakdown);
 if(body?.return_enabled===true)leg('return',quote?.pricing_source_return,returnUsesFixedFare,returnMission,quote?.return?.breakdown);
 return {ok:reasons.length===0,reasons,classification:reasons.length?'time_basis_approval_required':'price_independent_of_route_duration'};
}

export function holdUnapprovedTimePriceV1(quote,decision){
 const out={...quote,booking_allowed:false,financial_preview_only:true,request_quote_required:true,manual_quote_required:true,
  reason:'financial_time_basis_approval_required',financial_time_basis_reasons:decision.reasons,
  message:'Voor dit tijdsafhankelijke tarief moet de prijsgrondslag eerst worden bevestigd.'};
 for(const key of Object.keys(out))if(/(?:price|total).*?(?:vat|incl|excl)|financial_(?:quote|gross|net|vat)/i.test(key)&&typeof out[key]!=='boolean')out[key]=null;
 // No nested preview amount may be mistaken for an agreed sale.
 for(const key of ['pricing','pricing_main','pricing_return','breakdown','fixed_price_snapshot'])delete out[key];
 if(out.return)out.return={...out.return,price_ex_vat:null,price_vat:null,price_incl_vat:null,breakdown:null};
 delete out.financial_quote_id;delete out.financial_quote_expires_at;
 return out;
}
