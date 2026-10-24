// Merge a server-confirmed customer link without replacing historical ownership.
export function mergeSubscriptionProviderLink(existing, incoming) {
  const scope=value=>typeof value==='string'&&/^[A-Za-z0-9._-]{1,80}$/.test(value)&&!value.includes('..')&&value!=='global';
  const customer=value=>typeof value==='string'&&/^cst_[A-Za-z0-9_-]{1,120}$/.test(value);
  if(!scope(incoming?.tenant_id)||!scope(incoming?.company_id))throw Error('provider_link_scope_invalid');
  if(existing&&(existing.tenant_id!==incoming.tenant_id||existing.company_id!==incoming.company_id))throw Error('provider_link_owner_conflict');
  if(incoming.provider_customer_id!==undefined&&!customer(incoming.provider_customer_id))throw Error('provider_link_customer_invalid');
  if(existing?.provider_customer_id&&!customer(existing.provider_customer_id))throw Error('provider_link_stored_customer_invalid');
  if(existing?.provider_customer_id&&incoming.provider_customer_id&&existing.provider_customer_id!==incoming.provider_customer_id)throw Error('provider_link_customer_conflict');
  return {...existing,...incoming,...((incoming.provider_customer_id||existing?.provider_customer_id)?{provider_customer_id:incoming.provider_customer_id||existing.provider_customer_id}:{})};
}

// The caller must be a private authority handling a provider-confirmed result.
// A browser-supplied customer ID is never sufficient proof.
export async function storeSubscriptionProviderLink(storage,link){
  if(!/^sub_[A-Za-z0-9_-]{1,120}$/.test(link?.provider_subscription_id||'')||!/^cst_[A-Za-z0-9_-]{1,120}$/.test(link?.provider_customer_id||'')||!['live','test'].includes(link?.mode))throw Error('provider_link_identity_invalid');
  const record={tenant_id:link.tenant_id,company_id:link.company_id,provider_subscription_id:link.provider_subscription_id,provider_customer_id:link.provider_customer_id,mode:link.mode};
  mergeSubscriptionProviderLink(null,record);
  if(typeof storage?.transaction!=='function')throw Error('provider_link_transaction_required');
  const key=`subscription_provider_link:${record.mode}:${record.provider_subscription_id}`;
  const scopedKey=`subscription_provider_scope:${record.mode}:${record.tenant_id}:${record.company_id}:${record.provider_subscription_id}`;
  return storage.transaction(async txn=>{
    const existing=await txn.get(key);
    if(existing&&(existing.mode!==record.mode||existing.provider_subscription_id!==record.provider_subscription_id))throw Error('provider_link_stored_identity_invalid');
    const saved=mergeSubscriptionProviderLink(existing,record);
    if(!existing)await txn.put(key,saved);
    const indexed=await txn.get(scopedKey);
    if(indexed&&(indexed.provider_customer_id!==saved.provider_customer_id||indexed.provider_subscription_id!==saved.provider_subscription_id||indexed.tenant_id!==saved.tenant_id||indexed.company_id!==saved.company_id||indexed.mode!==saved.mode))throw Error('provider_link_stored_identity_invalid');
    if(!indexed)await txn.put(scopedKey,saved);
    return{ok:true,created:!existing};
  });
}

export async function captureRecurringProviderLink(env,{payment,providerFetched=false,configuredMode,loadProviderIndex}){
  // No new linkage is inferred from initial payments without a recurring ID.
  if(payment?.metadata?.purpose!=='fluxidi_subscription_recurring')return{ok:true,skipped:true};
  if(providerFetched!==true||!['live','test'].includes(configuredMode)||payment?.mode!==configuredMode||payment?.resource!=='payment'||!/^tr_[A-Za-z0-9_-]{1,120}$/.test(payment.id||'')||!/^sub_[A-Za-z0-9_-]{1,120}$/.test(payment.subscriptionId||'')||!/^cst_[A-Za-z0-9_-]{1,120}$/.test(payment.customerId||''))return{ok:true,held_review:true};
  let index;
  try{index=await loadProviderIndex(payment.subscriptionId);}catch{return{ok:false,retryable:true};}
  const scope=index?.ok===true?index.record:null,meta=payment.metadata;
  if(!scope||scope.tenant_id!==meta.tenant_id||scope.company_id!==meta.company_id||meta.kind!=='recurring')return{ok:true,held_review:true};
  const link={tenant_id:scope.tenant_id,company_id:scope.company_id,provider_customer_id:payment.customerId,provider_subscription_id:payment.subscriptionId,mode:configuredMode};
  try{
    mergeSubscriptionProviderLink(null,link);
    const binding=env.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
    if(!binding)throw Error('provider_link_storage_missing');
    const response=await binding.get(binding.idFromName('provider-links')).fetch('https://private.invalid',{method:'POST',body:JSON.stringify({action:'subscription_provider_link_capture',link})});
    if(response.status===409)return{ok:true,held_review:true};
    if(!response.ok)throw Error('provider_link_storage_unavailable');
    const result=await response.json();
    if(result.ok!==true||typeof result.created!=='boolean')throw Error('provider_link_storage_invalid');
    return{ok:true,captured:true};
  }catch{return{ok:false,retryable:true};}
}

// Internal authority read: customer IDs must not be copied into browser DTOs.
export async function readSubscriptionProviderLinks(storage,{tenant_id,company_id,mode,cursor=null,limit=50}){
  mergeSubscriptionProviderLink(null,{tenant_id,company_id});
  if(!['live','test'].includes(mode)||!Number.isInteger(limit)||limit<1||limit>50||cursor!==null&&!/^sub_[A-Za-z0-9_-]{1,120}$/.test(cursor))throw Error('provider_link_page_invalid');
  const prefix=`subscription_provider_scope:${mode}:${tenant_id}:${company_id}:`;
  return storage.transaction(async txn=>{
    const rows=await txn.list({prefix,...(cursor?{startAfter:prefix+cursor}:{}),limit:limit+1});
    if(!(rows instanceof Map)||rows.size>limit+1)throw Error('provider_link_page_invalid');
    const entries=[...rows];const hasMore=entries.length>limit;const scanned=entries.slice(0,limit),items=[];
    let previous=cursor?prefix+cursor:'';
    for(const [key,row] of scanned){
      if(typeof key!=='string'||!key.startsWith(prefix)||key<=previous||!/^sub_[A-Za-z0-9_-]{1,120}$/.test(key.slice(prefix.length))||row?.mode!==mode||row?.provider_subscription_id!==key.slice(prefix.length))throw Error('provider_link_stored_identity_invalid');
      previous=key;
      mergeSubscriptionProviderLink(null,row);
      if(!/^cst_[A-Za-z0-9_-]{1,120}$/.test(row.provider_customer_id||''))throw Error('provider_link_stored_customer_invalid');
      if(row.tenant_id!==tenant_id||row.company_id!==company_id)throw Error('provider_link_owner_conflict');
      items.push({provider_subscription_id:row.provider_subscription_id,provider_customer_id:row.provider_customer_id,mode});
    }
    return{ok:true,items,next_cursor:hasMore?previous.slice(prefix.length):null,complete_provider_history:false};
  });
}

export async function lookupSubscriptionProviderLink(storage,{tenant_id,company_id,mode,provider_subscription_id}){
  mergeSubscriptionProviderLink(null,{tenant_id,company_id});
  if(!['live','test'].includes(mode)||!/^sub_[A-Za-z0-9_-]{1,120}$/.test(provider_subscription_id||''))throw Error('provider_link_identity_invalid');
  return storage.transaction(async txn=>{
    const row=await txn.get(`subscription_provider_link:${mode}:${provider_subscription_id}`);
    if(!row||row.tenant_id!==tenant_id||row.company_id!==company_id)return{ok:true,link:null};
    mergeSubscriptionProviderLink(null,row);
    if(row.mode!==mode||row.provider_subscription_id!==provider_subscription_id||!/^cst_[A-Za-z0-9_-]{1,120}$/.test(row.provider_customer_id||''))throw Error('provider_link_stored_identity_invalid');
    return{ok:true,link:{tenant_id,company_id,mode,provider_subscription_id,provider_customer_id:row.provider_customer_id}};
  });
}
