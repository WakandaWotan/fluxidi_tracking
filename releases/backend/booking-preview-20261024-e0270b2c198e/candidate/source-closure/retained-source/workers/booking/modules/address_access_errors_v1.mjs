// Public, closed error vocabulary. Neither raw source errors nor road/driver
// identifiers are exposed. Authentication/tenant resolution run before this.
const entries=[
 ['reliable_address_incomplete',422,true,['access_address_incomplete','reliable_address_incomplete']],
 ['reliable_address_invalid',422,true,['access_address_invalid','reliable_address_invalid','official_address_id_required','official_address_not_found','official_address_not_current','official_address_index_changed','address_source_changed','address_source_position_changed','address_index_changed']],
 ['reliable_road_access_confirmation_required',422,true,['access_address_parallel_ambiguity','access_address_competing_frontage','reliable_road_access_confirmation_required']],
 ['reliable_address_access_forbidden',422,false,['address_access_forbidden','reliable_address_access_forbidden']],
 ['reliable_route_unreachable',422,false,['address_route_unreachable','reliable_route_unreachable']],
 ['reliable_route_evidence_unavailable',503,null,['address_index_unavailable','address_data_insufficient','address_context_incomplete','address_candidate_limit','address_context_partition_limit','address_context_size_limit','address_graph_changed','address_route_scope','address_route_evidence_invalid','address_route_evidence_unavailable','address_context_changed','address_vehicle_profile_unproven','terminal_candidate_limit','official_address_record_invalid','reliable_route_evidence_unavailable']],
];
export function classifyAddressAccessFailureV1(error){
 if(error?.code==='official_address_index_unavailable')return {status:503,body:{ok:false,error:'reliable_route_evidence_unavailable',retryable:true}};
 const reason=typeof error==='string'?error:error?.message;
 const match=entries.find(e=>e[3].includes(reason));if(!match)return null;
 const [code,status,confirm]=match;return {status,body:{ok:false,error:code,...(confirm===null?{retryable:true}:{requires_address_confirmation:confirm})}};
}
