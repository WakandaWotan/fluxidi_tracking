import {subscriptionProfileAuthorityOperation as operate,subscriptionProfileProjection} from './subscription_profile_authority.mjs';

// Read-only source selection: never bootstrap or trust an older KV mirror once authority is enabled.
export async function readSubscriptionProfileSource(env,scope,readLegacy){
  if(env.FLUXIDI_SUBSCRIPTION_PROFILE_AUTHORITY_ENABLED!=='1')return readLegacy();
  const record=(await operate(env,scope,'profile_read')).record;
  if(!record)throw Error('subscription_profile_authority_uninitialized');
  const projection=subscriptionProfileProjection(record);
  return {...projection,updated_at:record.profile.updated_at,
    subscription_profile:{...projection.subscription_profile,source_revision:record.revision}};
}
