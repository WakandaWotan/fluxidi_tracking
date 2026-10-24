// Non-serializable server capability. Client JSON can carry the coordinates or
// label, but cannot recreate the validated endpoint-only terminal permission.
const proofs=new WeakMap(),candidates=new WeakMap(),frontages=new WeakSet();
export function registerOfficialAddressCandidateV1(candidate,{graphVersion,revision,role,addressId}){candidates.set(candidate,{graphVersion,revision,role,addressId});}
export function verifyOfficialAddressCandidateV1(candidate,expected){const proof=candidates.get(candidate);if(candidate?.status!=='proven'||!proof||Object.keys(expected).some(k=>expected[k]!==proof[k]))throw Error('address_access_candidate_unproven');}
export function createOfficialTerminalFrontageV1({candidate,graphVersion,revision,role,addressId}){
 verifyOfficialAddressCandidateV1(candidate,{graphVersion,revision,role,addressId});
 const frontage=Object.freeze({point:candidate.point,offsetMeters:candidate.offsetMeters,confidence:'HIGH',wayIds:candidate.wayIds,graphVersion,revision,schema:'fluxidi-practical-frontage-v1',physicalEntranceRequired:false});frontages.add(frontage);return frontage;
}
export const officialTerminalFrontageVerifiedV1=frontage=>frontages.has(frontage);
export function createOfficialAddressRoutePointV1({point,snap,graphVersion,revision,role,candidateId}){
 const value=Object.freeze({latitude:point.latitude,longitude:point.longitude,access:Object.freeze({kind:'official_address_access',candidateId,role})});
 proofs.set(value,{snap,graphVersion,revision,role});return value;
}
export function readOfficialAddressRoutePointV1(point,{graphVersion,revision,role}){
 const proof=proofs.get(point);
 if(!proof){if(point?.access?.kind==='official_address_access')throw Error('address_access_handle_invalid');return null;}
 if(proof.graphVersion!==graphVersion||proof.revision!==revision||proof.role!==role)throw Error('address_access_handle_changed');
 return structuredClone(proof.snap);
}
