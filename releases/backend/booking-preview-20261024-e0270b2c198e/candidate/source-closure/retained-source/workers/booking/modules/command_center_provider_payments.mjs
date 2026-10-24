import {affiliateAmountCents} from './affiliate_payment_adapter.mjs';

export async function commandCenterProviderSubscriptions(env,scope,params,{now=Date.now()}={}){
  if(env.COMMAND_CENTER_PROVIDER_PAYMENTS_READ_ENABLED!=='1')throw Error('provider_payments_not_enabled');
  const key=env.FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY,binding=env.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
  if(typeof key!=='string'||! /^(live|test)_[A-Za-z0-9_-]+$/.test(key)||!binding||!Number.isFinite(now))throw Error('provider_payments_configuration_required');
  const mode=key.startsWith('live_')?'live':'test',limit=Number(params.get('limit')||50),cursor=params.get('cursor');
  if(!Number.isInteger(limit)||limit<1||limit>50||cursor&&!/^sub_[A-Za-z0-9_-]{1,120}$/.test(cursor))throw Error('provider_payments_budget_invalid');
  const response=await binding.get(binding.idFromName('provider-links')).fetch('https://private.invalid',{method:'POST',body:JSON.stringify({action:'subscription_provider_links_read',tenant_id:scope.tenant_id,company_id:scope.company_id,mode,limit,cursor})});
  if(!response.ok)throw Error('provider_payments_link_unavailable');
  const page=await response.json();
  if(page.ok!==true||page.complete_provider_history!==false||!Array.isArray(page.items)||page.items.length>limit||page.next_cursor!==null&&!/^sub_[A-Za-z0-9_-]{1,120}$/.test(page.next_cursor))throw Error('provider_payments_link_invalid');
  const seen=new Set(),items=page.items.map(row=>{
    if(row.mode!==mode||!/^sub_[A-Za-z0-9_-]{1,120}$/.test(row.provider_subscription_id||'')||seen.has(row.provider_subscription_id))throw Error('provider_payments_link_invalid');
    seen.add(row.provider_subscription_id);return{subscription_id:row.provider_subscription_id,mode};
  });
  return{ok:true,schema_version:'command_center_provider_subscriptions_v1',provenance:'verified_provider_link_registry',generated_at:new Date(now).toISOString(),complete_provider_history:false,next_cursor:page.next_cursor,items};
}

const paymentId=value=>typeof value==='string'&&/^tr_[A-Za-z0-9_-]{1,120}$/.test(value);
const stamp=value=>typeof value==='string'&&/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(value)&&Number.isFinite(Date.parse(value))?value:null;
const statuses=new Set(['open','pending','authorized','paid','failed','canceled','expired']);
const amount=(value,currency)=>value==null?null:value.currency===currency?affiliateAmountCents(value.value):null;

// One bounded provider GET. A page is current-customer evidence, never a claim
// that every historic customer account or all company payments were indexed.
export async function commandCenterProviderPayments(env,scope,stored,params,{fetchImpl=fetch,now=Date.now()}={}){
  if(env.COMMAND_CENTER_PROVIDER_PAYMENTS_READ_ENABLED!=='1')throw Error('provider_payments_not_enabled');
  const profile=stored?.subscription_profile??stored;
  if(!profile||profile.tenant_id!==scope.tenant_id||profile.company_id!==scope.company_id)throw Error('provider_payments_scope_required');
  let customer=profile.provider_customer_id;
  const key=env.FLUXIDI_SUBSCRIPTION_MOLLIE_API_KEY,subscription=params.get('subscription');
  if(subscription){
    if(!/^sub_[A-Za-z0-9_-]{1,120}$/.test(subscription)||typeof key!=='string'||! /^(live|test)_[A-Za-z0-9_-]+$/.test(key))throw Error('provider_payments_configuration_required');
    const binding=env.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
    if(!binding)throw Error('provider_payments_link_unavailable');
    const mode=key.startsWith('live_')?'live':'test';
    const response=await binding.get(binding.idFromName('provider-links')).fetch('https://private.invalid',{method:'POST',body:JSON.stringify({action:'subscription_provider_link_lookup',tenant_id:scope.tenant_id,company_id:scope.company_id,mode,provider_subscription_id:subscription})});
    if(!response.ok)throw Error('provider_payments_link_unavailable');
    const result=await response.json(),link=result.link;
    if(result.ok!==true||!link||link.tenant_id!==scope.tenant_id||link.company_id!==scope.company_id||link.mode!==mode||link.provider_subscription_id!==subscription)throw Error('provider_payments_link_unavailable');
    customer=link.provider_customer_id;
  }
  if(typeof customer!=='string'||!/^cst_[A-Za-z0-9_-]{1,120}$/.test(customer)||typeof key!=='string'||! /^(live|test)_[A-Za-z0-9_-]+$/.test(key))throw Error('provider_payments_configuration_required');
  const mode=key.startsWith('live_')?'live':'test',cursor=params.get('cursor');
  if(cursor&&!paymentId(cursor))throw Error('provider_payments_cursor_invalid');
  const limit=Number(params.get('limit')||50);
  if(!Number.isInteger(limit)||limit<1||limit>50||!Number.isFinite(now))throw Error('provider_payments_budget_invalid');
  const path=`/v2/customers/${customer}/payments`,target=new URL(path,'https://api.mollie.com');
  target.searchParams.set('limit',String(limit));if(cursor)target.searchParams.set('from',cursor);
  const result=await fetchImpl(target,{method:'GET',redirect:'manual',signal:AbortSignal.timeout(15000),headers:{Accept:'application/json',Authorization:`Bearer ${key}`}});
  if(!result.ok)throw Error('provider_payments_unavailable');
  const body=await result.text();if(body.length>2000000)throw Error('provider_payments_budget_exceeded');
  const page=JSON.parse(body),rows=page?._embedded?.payments;
  if(!Array.isArray(rows)||rows.length>limit||page.count!==rows.length||!page._links||!Object.hasOwn(page._links,'next'))throw Error('provider_payments_page_invalid');
  let next=null;
  if(page._links.next!==null){
    const href=page._links.next?.href;if(typeof href!=='string')throw Error('provider_payments_page_invalid');
    const url=new URL(href);
    if(url.origin!=='https://api.mollie.com'||![path,'/v2/payments'].includes(url.pathname)||url.username||url.password||url.hash||[...url.searchParams.keys()].some(name=>!['from','limit','sort'].includes(name))||['from','limit','sort'].some(name=>url.searchParams.getAll(name).length>1)||url.searchParams.getAll('from').length!==1||!paymentId(url.searchParams.get('from'))||url.searchParams.get('from')===cursor||url.searchParams.has('limit')&&Number(url.searchParams.get('limit'))!==limit||url.searchParams.has('sort')&&url.searchParams.get('sort')!=='desc')throw Error('provider_payments_pagination_invalid');
    next=url.searchParams.get('from');
  }
  const ids=new Set(),items=[];let excluded=0;
  for(const row of rows){
    if(!paymentId(row?.id)||ids.has(row.id)||row.resource!=='payment'||row.mode!==mode||row.customerId!==customer)throw Error('provider_payments_identity_invalid');
    ids.add(row.id);
    const meta=row.metadata,kind=meta?.purpose==='fluxidi_subscription_recurring'&&meta.kind==='recurring'&&/^sub_[A-Za-z0-9_-]+$/.test(row.subscriptionId||'')?'subscription_recurring':meta?.purpose==='fluxidi_subscription'&&typeof meta.activation_id==='string'&&meta.activation_id.length>0&&['first','addon'].includes(meta.kind)?meta.kind==='addon'?'subscription_addon':'subscription_initial':null;
    if(!kind||meta.tenant_id!==scope.tenant_id||meta.company_id!==scope.company_id){excluded++;continue;}
    const currency=row.amount?.currency,gross=amount(row.amount,currency),paidAt=stamp(row.paidAt),createdAt=stamp(row.createdAt);
    if(!/^[A-Z]{3}$/.test(currency||'')||gross===null||!statuses.has(row.status)||!createdAt||Date.parse(createdAt)>now||row.status==='paid'&&(!paidAt||Date.parse(paidAt)>now))throw Error('provider_payments_evidence_invalid');
    const refunded=amount(row.amountRefunded,currency),chargedBack=amount(row.amountChargedBack,currency);
    if(row.amountRefunded!=null&&refunded===null||row.amountChargedBack!=null&&chargedBack===null)throw Error('provider_payments_evidence_invalid');
    items.push({payment_id:row.id,kind,mode,status:row.status,currency,gross_cents:gross,refunded_gross_cents:refunded,charged_back_gross_cents:chargedBack,created_at:createdAt,paid_at:paidAt,scope_verified:true});
  }
  return{ok:true,schema_version:'command_center_provider_payments_v1',provenance:'mollie_customer_payments',coverage:subscription?'registered_subscription_customer_payments':'current_provider_customer_payments',complete_provider_history:false,generated_at:new Date(now).toISOString(),page_complete:next===null,next_cursor:next,excluded_unmatched_count:excluded,net_vat_basis:'requires_payment_fiscal_evidence',items};
}
