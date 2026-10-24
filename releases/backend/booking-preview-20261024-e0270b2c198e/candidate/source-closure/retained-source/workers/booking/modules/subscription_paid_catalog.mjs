// Modern contract prices come exclusively from a version-pinned server catalog.
// This resolver does not charge, reserve discounts or infer VAT treatment.
const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const text=value=>typeof value==='string'&&/^[A-Za-z0-9._-]{1,120}$/.test(value);
const iso=value=>typeof value==='string'&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value;
const price=value=>Number.isSafeInteger(value)&&value>0;
const fail=reason=>({ok:false,error:`subscription_paid_catalog_${reason}`});
export function resolveModernSubscriptionPrice(env,{market,plan_code,nowMs=Date.now()}={}){
  if(!['standard','smart'].includes(plan_code))return fail('target_plan_invalid');
  if(!/^[A-Z]{2}$/.test(market||''))return fail('market_invalid');
  const version=env?.FLUXIDI_SUBSCRIPTION_PAID_CATALOG_VERSION;
  const raw=env?.FLUXIDI_SUBSCRIPTION_PAID_CATALOG_JSON;
  if(!text(version)||typeof raw!=='string'||raw.length===0)return fail('unavailable');
  if(raw.length>16384)return fail('invalid');
  let catalog;try{catalog=JSON.parse(raw);}catch{return fail('invalid');}
  if(!plain(catalog)||catalog.schema_version!=='subscription_paid_catalog_v1'||catalog.version!==version||
    !text(catalog.review_reference)||catalog.price_basis!=='exclusive'||catalog.interval!=='1 month'||
    !iso(catalog.effective_from)||!iso(catalog.valid_until)||!Number.isFinite(nowMs)||
    Date.parse(catalog.effective_from)>nowMs||Date.parse(catalog.valid_until)<=nowMs||
    !plain(catalog.markets)||Object.keys(catalog.markets).length===0||Object.keys(catalog.markets).length>30)return fail('unproved');
  // Validate the entire advertised catalog, not only the requested price.
  for(const [country,entry] of Object.entries(catalog.markets)){
    if(!/^[A-Z]{2}$/.test(country)||!plain(entry)||entry.currency!=='EUR'||!plain(entry.plans)||
      Object.keys(entry.plans).length!==2||!['standard','smart'].every(plan=>plain(entry.plans[plan])&&price(entry.plans[plan].monthly_net_cents)))return fail('invalid');
  }
  if(!Object.hasOwn(catalog.markets,market))return fail('market_unavailable');
  const entry=catalog.markets[market];
  return{ok:true,plan_code,market,currency:entry.currency,monthly_net_cents:entry.plans[plan_code].monthly_net_cents,
    price_basis:'exclusive',interval:'1 month',catalog_version:catalog.version,review_reference:catalog.review_reference,
    effective_from:catalog.effective_from,valid_until:catalog.valid_until};
}

// Checkout needs an explicit capacity/discount contract, beyond display prices.
// This reads policy; it does not determine founder slot availability.
export function resolveModernSubscriptionContract(env,args={}){
  const snapshot={FLUXIDI_SUBSCRIPTION_PAID_CATALOG_VERSION:env?.FLUXIDI_SUBSCRIPTION_PAID_CATALOG_VERSION,
    FLUXIDI_SUBSCRIPTION_PAID_CATALOG_JSON:env?.FLUXIDI_SUBSCRIPTION_PAID_CATALOG_JSON};
  const base=resolveModernSubscriptionPrice(snapshot,args);
  if(!base.ok)return base;
  const catalog=JSON.parse(snapshot.FLUXIDI_SUBSCRIPTION_PAID_CATALOG_JSON);
  const plan=catalog.markets[base.market].plans[base.plan_code];
  if(!price(plan.extra_vehicle_monthly_net_cents)||!price(plan.extra_driver_monthly_net_cents)||
    typeof plan.new_founder_eligible!=='boolean'||!Object.hasOwn(plan,'founder_monthly_net_cents')||
    (plan.new_founder_eligible?!price(plan.founder_monthly_net_cents)||plan.founder_monthly_net_cents>base.monthly_net_cents:plan.founder_monthly_net_cents!==null))return fail('contract_unproved');
  return{...base,extra_vehicle_monthly_net_cents:plan.extra_vehicle_monthly_net_cents,
    extra_driver_monthly_net_cents:plan.extra_driver_monthly_net_cents,
    new_founder_eligible:plan.new_founder_eligible,founder_monthly_net_cents:plan.founder_monthly_net_cents};
}

// Validate historical policy at the time it was recorded, never against today's catalog.
export function normalizePaidContractSnapshot(value,scope={}){
  if(!plain(value)||value.schema_version!=='subscription_paid_contract_snapshot_v1'||value.ok!==true||
    !['standard','smart'].includes(value.plan_code)||! /^[A-Z]{2}$/.test(value.market||'')||value.currency!=='EUR'||
    value.price_basis!=='exclusive'||value.interval!=='1 month'||!text(value.catalog_version)||!text(value.review_reference)||
    !iso(value.recorded_at)||!iso(value.effective_from)||!iso(value.valid_until)||
    Date.parse(value.recorded_at)<Date.parse(value.effective_from)||Date.parse(value.recorded_at)>=Date.parse(value.valid_until)||
    !price(value.monthly_net_cents)||!price(value.extra_vehicle_monthly_net_cents)||!price(value.extra_driver_monthly_net_cents)||
    typeof value.new_founder_eligible!=='boolean'||
    (value.new_founder_eligible? !price(value.founder_monthly_net_cents)||value.founder_monthly_net_cents>value.monthly_net_cents:value.founder_monthly_net_cents!==null))return null;
  for(const key of ['tenant_id','company_id','activation_id'])if(typeof value[key]!=='string'||!value[key]||value[key].length>160||(scope[key]&&value[key]!==scope[key]))return null;
  return Object.fromEntries(['schema_version','ok','tenant_id','company_id','activation_id','plan_code','market','currency','price_basis','interval','catalog_version','review_reference','recorded_at','effective_from','valid_until','monthly_net_cents','extra_vehicle_monthly_net_cents','extra_driver_monthly_net_cents','new_founder_eligible','founder_monthly_net_cents'].map(key=>[key,value[key]]));
}

export function paidContractMatchesPending(record){
  const contract=normalizePaidContractSnapshot(record?.subscription_paid_contract_snapshot,record);
  if(!contract)return false;
  return contract.plan_code===record.plan_code&&contract.market===record.market&&contract.currency===record.currency&&
    contract.monthly_net_cents===record.normal_price_cents&&contract.founder_monthly_net_cents===record.founder_price_cents&&
    contract.extra_vehicle_monthly_net_cents===record.locked_extra_vehicle_unit_cents&&
    contract.extra_driver_monthly_net_cents===record.locked_extra_driver_unit_cents&&
    (record.founder_reserved!==true||contract.new_founder_eligible===true);
}
