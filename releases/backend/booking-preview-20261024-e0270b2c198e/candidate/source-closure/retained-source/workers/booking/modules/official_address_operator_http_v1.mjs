import {createOfficialAddressTextHttpV1} from './official_address_text_http_v1.mjs';

// These objects must come from the existing company/driver session loaders.
// This endpoint accepts no client actor, tenant scope or administrator secret.
export function officialAddressOperatorPrincipalV1(s){
 if(!s||!['key','token_hash','tenant_id','company_id'].every(k=>typeof s[k]==='string'&&s[k])||!(Date.parse(s.expires_at)>Date.now()))return null;
 if(s.role==='company_admin')return JSON.stringify(['company',s.tenant_id,s.company_id,s.token_hash]);
 if(s.role==='driver'&&typeof s.driver_id==='string'&&s.driver_id)return JSON.stringify(['driver',s.tenant_id,s.company_id,s.driver_id,s.token_hash]);
 return null;
}
export const handleOfficialAddressOperatorHttpV1=createOfficialAddressTextHttpV1({path:'/company/official-address-search',actorPrincipal:officialAddressOperatorPrincipalV1,rateNamespace:'operator'});
