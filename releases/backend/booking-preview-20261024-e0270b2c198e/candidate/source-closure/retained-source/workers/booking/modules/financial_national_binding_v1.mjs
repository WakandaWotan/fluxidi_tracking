import {withOperationalRoutingV1,operationalRoutingInstalledV1} from './reliable_operational_routes_v1.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {officialAddressReferenceV1} from './official_address_reference_v1.mjs';
import {createNationalFinancialRequestV1} from './financial_national_request_v1.mjs';
import {financialRouteBatchContextV1} from './financial_route_batch_v1.mjs';

const fail=reason=>{throw Error(reason);};
const parse=value=>{
 if(typeof value==='string'){if(new TextEncoder().encode(value).byteLength>8192)fail('national_financial_policy_unproven');try{return JSON.parse(value);}catch{fail('national_financial_policy_unproven');}}
 return value;
};
const hex=s=>typeof s==='string'&&/^[a-f0-9]{64}$/.test(s);

// A configured financial policy cannot merely name a graph version. It must
// match the publication and manifest the existing owned runtime actually uses.
// No caller JSON can supply this policy, factory, scope or index.
export function nationalFinancialPolicyV1(env){
 if(env?.NATIONAL_FINANCIAL_ROUTING_ENABLED!=='1')fail('national_financial_unavailable');
 const policy=parse(env.NATIONAL_FINANCIAL_ROUTING_POLICY),activation=parse(env.RELIABLE_NATIONAL_ACTIVATION),reference=parse(env.RELIABLE_NATIONAL_PUBLICATION_REF);
 if(policy?.schema!=='fluxidi-national-financial-policy-v1'||policy.state!=='approved'||policy.durationPolicyVersion!=='be-nl-static-edge-time-v1'
  ||!['version','graphVersion','evidenceRevision'].every(k=>typeof policy[k]==='string'&&policy[k].length>0&&policy[k].length<=200)
  ||!hex(policy.acceptanceEvidenceSha256)||policy.acceptanceEvidenceSha256!==env.NATIONAL_FINANCIAL_ACCEPTANCE_SHA256
  ||activation?.state!=='active'||reference?.schema!=='fluxidi-national-publication-ref-v1'
  ||!hex(activation.manifestSha256)||!hex(activation.publicationSha256)||reference.sha256!==activation.publicationSha256
  ||policy.graphManifestSha256!==activation.manifestSha256||policy.publicationSha256!==activation.publicationSha256
  ||policy.graphVersion!==activation.graphVersion||policy.evidenceRevision!==activation.evidenceRevision)fail('national_financial_policy_unproven');
 return structuredClone(policy);
}

export async function bindNationalFinancialRequestV1({env,scope,locations,clock=Date.now,maxStops=6,
 createRouter=async(currentEnv,currentScope)=>{
  const owned=withOperationalRoutingV1(currentEnv);if(!operationalRoutingInstalledV1(owned))fail('national_financial_runtime_unavailable');
  return owned.__reliableRegionalRoutes(currentScope);
 },loadIndex=operationalOfficialAddressIndexV1}){
 const policy=nationalFinancialPolicyV1(env);
 if(!scope?.tenant_id||!scope?.company_id)fail('national_financial_scope_required');
 const router=await createRouter(env,{tenant_id:scope.tenant_id,company_id:scope.company_id});
 if(router?.kind!=='LOCAL_ROUTING_ONLY_V1')fail('national_financial_runtime_unavailable');
 let authority,index;
 async function resolveMunicipality(point){
  const ref=point?.official_address;
  if(!ref||!officialAddressReferenceV1({kind:'address',official_address:ref}))fail('national_financial_municipality_unproven');
  if(!index){index=await loadIndex(env);if(!index)fail('national_financial_municipality_unproven');authority=createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true});}
  if(index.revision!==ref.index_revision)fail('address_source_changed');
  const record=await authority.resolve(ref.id);
  if(record.source!==ref.source||record.sourceVersion!==ref.source_version)fail('address_source_changed');
  // Municipality, rather than an optional locality/submunicipality, determines
  // the existing local tariff. It comes from the verified source, never text.
  return record.address.municipality??record.address.locality;
 }
 return createNationalFinancialRequestV1({scope:{tenant_id:scope.tenant_id,company_id:scope.company_id},policy,router,locations,resolveMunicipality,clock,maxStops,reuseContext:financialRouteBatchContextV1(env)});
}
