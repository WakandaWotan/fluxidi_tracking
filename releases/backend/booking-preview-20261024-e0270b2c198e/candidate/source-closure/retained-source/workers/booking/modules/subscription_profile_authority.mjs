const scopePart=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,80}$/.test(value);
const plain=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
const key='subscription_profile_authority:v1';
const reject=error=>({ok:false,error});

// Internal company-scoped authority. KV publication is a separate projection step.
export async function subscriptionProfileAuthority(storage,body){
  if(!scopePart(body?.tenant_id)||!scopePart(body?.company_id))return reject('subscription_profile_scope_invalid');
  const scope={tenant_id:body.tenant_id,company_id:body.company_id};
  const profile=body.profile;
  if(body.operation_id!==undefined&&(typeof body.operation_id!=='string'||!/^[A-Za-z0-9_-]{1,160}$/.test(body.operation_id)))return reject('subscription_profile_operation_invalid');
  if(!['profile_read','profile_operation_read','profile_projection_ack'].includes(body.action)&&(!plain(profile)||profile.tenant_id!==scope.tenant_id||profile.company_id!==scope.company_id||JSON.stringify(profile).length>65536))
    return reject('subscription_profile_payload_invalid');
  return storage.transaction(async txn=>{
    const current=await txn.get(key);
    if(current&&(current.tenant_id!==scope.tenant_id||current.company_id!==scope.company_id))return reject('subscription_profile_scope_conflict');
    if(body.action==='profile_read')return {ok:true,record:current||null};
    const receiptKey=body.operation_id?`subscription_profile_operation:v1:${body.operation_id}`:null;
    if(body.action==='profile_operation_read')return receiptKey?{ok:true,receipt:await txn.get(receiptKey)||null}:reject('subscription_profile_operation_invalid');
    if(body.action==='profile_projection_ack'){
      if(!current||body.published_revision!==current.revision)return reject('subscription_profile_projection_revision_conflict');
      const record={...current,publication_pending:false};
      await txn.put(key,record);return {ok:true,record};
    }
    if(body.action==='profile_initialize'){
      if(current)return {ok:true,initialized:false,record:current};
      const record={version:1,...scope,revision:0,publication_pending:true,profile:structuredClone(profile)};
      await txn.put(key,record);return {ok:true,initialized:true,record};
    }
    if(body.action!=='profile_compare_write')return reject('subscription_profile_action_invalid');
    if(!current)return reject('subscription_profile_authority_uninitialized');
    if(receiptKey&&await txn.get(receiptKey))return reject('subscription_profile_operation_already_applied');
    if(!Number.isSafeInteger(body.expected_revision)||body.expected_revision<0||body.expected_revision!==current.revision)
      return {...reject('subscription_profile_revision_conflict'),current_revision:current.revision};
    if(current.revision>=Number.MAX_SAFE_INTEGER)return reject('subscription_profile_revision_exhausted');
    const record={version:1,...scope,revision:current.revision+1,publication_pending:true,profile:structuredClone(profile)};
    await txn.put(key,record);
    if(receiptKey)await txn.put(receiptKey,{revision:record.revision});
    return {ok:true,record};
  });
}

export function subscriptionProfileProjection(authority){
  if(!plain(authority)||!Number.isSafeInteger(authority.revision)||authority.revision<0||!plain(authority.profile)||
    authority.profile.tenant_id!==authority.tenant_id||authority.profile.company_id!==authority.company_id)
    throw Error('subscription_profile_authority_record_invalid');
  return {version:1,authority_revision:authority.revision,subscription_profile:structuredClone(authority.profile)};
}

export function subscriptionProfileProjectionMatches(authority,projection){
  try{
    const expected=subscriptionProfileProjection(authority);
    return projection?.authority_revision===expected.authority_revision&&JSON.stringify(projection.subscription_profile)===JSON.stringify(expected.subscription_profile);
  }catch(_){return false;}
}

export async function subscriptionProfileAuthorityOperation(env,scope,action,fields={}){
  const binding=env?.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
  if(!binding||!scopePart(scope?.tenant_id)||!scopePart(scope?.company_id))throw Error('subscription_profile_authority_missing');
  const name=`subscription:profile:${JSON.stringify([scope.tenant_id,scope.company_id])}`;
  const response=await binding.get(binding.idFromName(name)).fetch('https://founder-slots/profile',{
    method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({...fields,...scope,action}),
  });
  const result=await response.json();
  if(!response.ok||result.ok!==true)throw Error(result.error||'subscription_profile_authority_failed');
  return result;
}
