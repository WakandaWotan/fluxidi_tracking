import {subscriptionProfileAuthorityOperation as operate,subscriptionProfileProjection} from './subscription_profile_authority.mjs';

export async function loadVersionedSubscriptionProfile(env,scope,legacyProfile){
  let record=(await operate(env,scope,'profile_read')).record;
  if(!record&&legacyProfile){
    record=(await operate(env,scope,'profile_initialize',{profile:legacyProfile})).record;
  }
  return record?{...record.profile,subscription_authority_revision:record.revision}:null;
}

export async function saveVersionedSubscriptionProfile(env,scope,profile,expectedRevision,publish,operationId){
  let result;
  if(Number.isSafeInteger(expectedRevision)&&expectedRevision>=0){
    result=await operate(env,scope,'profile_compare_write',{profile,expected_revision:expectedRevision,...(operationId?{operation_id:operationId}:{})});
  }else{
    if(operationId!==undefined)throw Error('subscription_profile_operation_revision_required');
    result=await operate(env,scope,'profile_initialize',{profile});
    if(!result.initialized)throw Error('subscription_profile_revision_required');
  }
  // The authority is committed first. Failed/stale projection writes never become canonical reads.
  await publish(subscriptionProfileProjection(result.record));
  await operate(env,scope,'profile_projection_ack',{published_revision:result.record.revision});
  return {...result.record.profile,subscription_authority_revision:result.record.revision};
}

// Explicit projection maintenance, separate from entitlement mutation and read-only source endpoints.
// A concurrent canonical mutation requires another bounded attempt; never acknowledge an old revision.
export async function repairSubscriptionProfileProjection(env,scope,publish,{maxAttempts=2}={}){
  if(!Number.isSafeInteger(maxAttempts)||maxAttempts<1||maxAttempts>3)throw Error('subscription_profile_repair_attempts_invalid');
  for(let attempt=0;attempt<maxAttempts;attempt++){
    const record=(await operate(env,scope,'profile_read')).record;
    if(!record)throw Error('subscription_profile_authority_uninitialized');
    await publish(subscriptionProfileProjection(record));
    try{
      const acknowledged=(await operate(env,scope,'profile_projection_ack',{published_revision:record.revision})).record;
      return {repaired:true,revision:acknowledged.revision};
    }catch(error){
      if(error.message!=='subscription_profile_projection_revision_conflict')throw error;
    }
  }
  throw Error('subscription_profile_repair_concurrent_mutation');
}
