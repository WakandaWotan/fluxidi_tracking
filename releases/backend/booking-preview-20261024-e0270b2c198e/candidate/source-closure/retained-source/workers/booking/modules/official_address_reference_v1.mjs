const text=v=>typeof v==='string'&&v.length>0&&v.length<=500&&!/[\r\n\0]/.test(v);
export function officialAddressReferenceV1(input){
 const ref=input?.official_address;if(ref===undefined)return null;
 if(input.kind!=='address'||!ref||Array.isArray(ref)||Object.keys(ref).some(k=>!['id','index_revision','source','source_version'].includes(k))||!['id','index_revision','source','source_version'].every(k=>text(ref[k])))throw Error('reliable_address_invalid');
 return {...ref};
}
export function officialAddressPositionUsableV1(address){
 const p=address?.point,flags=address?.provenance?.sourceExtra?.inResearch;
 if(!p||!Number.isFinite(p.latitude)||!Number.isFinite(p.longitude))return false;
 if(flags&&typeof flags==='object'&&Object.values(flags).some(v=>Array.isArray(v)?v.length>0:v===true||typeof v==='string'&&['J','JA','TRUE','1'].includes(v.toUpperCase())))return false;
 return true;
}
