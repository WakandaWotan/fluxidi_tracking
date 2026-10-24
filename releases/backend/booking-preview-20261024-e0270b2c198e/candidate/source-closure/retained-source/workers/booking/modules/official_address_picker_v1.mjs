import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {officialAddressPositionUsableV1,officialAddressReferenceV1} from './official_address_reference_v1.mjs';

// Server-only read adapter for an explicit human area/ID choice. No endpoint,
// nationwide text search, first/nearest selection, source writes or road proof.
export const OFFICIAL_ADDRESS_PICKER_V1='fluxidi-official-address-picker-v1';
const plain=x=>x&&typeof x==='object'&&!Array.isArray(x),text=s=>typeof s==='string'&&s.length<=500&&!/[\r\n\0]/.test(s),keys=(o,allowed)=>plain(o)&&Object.keys(o).every(k=>allowed.includes(k));
const fold=s=>s.normalize('NFC').toLocaleLowerCase('und').trim().replace(/\s+/g,' ');
function boundsOf(b){
 if(!keys(b,['west','south','east','north'])||!['west','south','east','north'].every(k=>Number.isFinite(b[k])))throw Error('official_picker_bounds_invalid');
 const {west,east,south,north}=b;if(west<2||east>9||south<49||north>56||west>=east||south>=north)throw Error('official_picker_bounds_invalid');
 if((east-west)*111195*Math.cos((north+south)*Math.PI/360)>200||(north-south)*111195>200)throw Error('official_picker_bounds_limit');
 return {west,south,east,north};
}
function label(a){const suffix=[a.houseLetter,a.houseNumberAddition].filter(Boolean).join(''),box=a.boxNumber?' bus '+a.boxNumber:'';return `${a.street} ${a.houseNumber}${suffix}${box}, ${a.postcode} ${a.locality??a.municipality}, ${a.country}`;}
function presentationLabels(record){
 const a=record.address,names=record.provenance?.names,out=[label(a)],primaryMunicipality=a.municipality??a.locality;
 const officialText=s=>text(s)&&s.trim().length>0;
 for(const language of ['nl','fr','de']){
  const street=names?.street?.[language],municipality=names?.municipality?.[language];
  // A municipality translation is not a translation of a distinct district.
  const locality=a.locality===primaryMunicipality&&officialText(municipality)?municipality:a.locality;
  out.push(label({...a,street:officialText(street)?street:a.street,locality}));
 }
 return out;
}
function suggestion(record,revision){const ref={id:record.id,index_revision:revision,source:record.source,source_version:record.sourceVersion};return {label:label(record.address),lat:record.point.latitude,lon:record.point.longitude,placeType:'address',official_address:ref};}
const insufficient=(revision,reason)=>({schema:OFFICIAL_ADDRESS_PICKER_V1,ok:false,status:'data_insufficient',reason,index_revision:revision,accessProven:false,routeProven:false});
function incompleteBoundSource(record,ref,revision){
 const r=record,a=r?.address,p=r?.point,validText=s=>text(s)&&s.length>0;
 // Classify missing canonical fields only after the actual immutable source ID,
 // revision, source/version and remaining record contract have been checked.
 // A corrupted binding, schema or position must remain a technical error.
 if(r?.schema!=='fluxidi-official-address-v1'||r.id!==ref.id||r.indexRevision!==revision||r.source!==ref.source||r.sourceVersion!==ref.source_version||
  !validText(r.sourceRecordId)||r.streetId!=null&&!validText(r.streetId)||r.status!=='current'||r.officiallyAssigned!==true&&r.officiallyAssigned!=null||
  !['BE','NL'].includes(a?.country)||a.locality!=null&&!validText(a.locality)||['houseLetter','houseNumberAddition','boxNumber'].some(k=>a[k]!=null&&!validText(a[k]))||
  p!=null&&(!Number.isFinite(p.latitude)||!Number.isFinite(p.longitude)||Math.abs(p.latitude)>90||Math.abs(p.longitude)>180||p.latitude===0&&p.longitude===0))return false;
 const required=['street','houseNumber','postcode','municipality'];
 if(required.some(k=>a[k]!=null&&!validText(a[k])))return false;
 if(a.postcode!=null&&!(a.country==='BE'?/^\d{4}$/:/^[1-9]\d{3} ?[A-Z]{2}$/).test(a.postcode))return false;
 return required.some(k=>a[k]==null);
}
// Also used at the HTTP boundary, before manifest or source-object IO.
export function validateOfficialAddressPickerRequestV1(request){
 if(!plain(request)||request.schema!==OFFICIAL_ADDRESS_PICKER_V1)throw Error('official_picker_input_invalid');
 if(request.mode==='resolve_selected'){
  if(!keys(request,['schema','mode','official_address']))throw Error('official_picker_input_invalid');
  const ref=officialAddressReferenceV1({kind:'address',official_address:request.official_address});
  if(!ref)throw Error('official_picker_input_invalid');
  return {schema:request.schema,mode:request.mode,official_address:ref};
 }
 if(request.mode!=='catalogue'||!keys(request,['schema','mode','bounds','language','query'])||!['nl','fr','de','en'].includes(request.language)||!text(request.query)||request.query.length>100)throw Error('official_picker_input_invalid');
 return {schema:request.schema,mode:request.mode,bounds:boundsOf(request.bounds),language:request.language,query:request.query};
}
export async function readOfficialAddressPickerV1({index,request}){
 request=validateOfficialAddressPickerRequestV1(request);
 const revision=index?.revision;if(index?.kind!=='OFFICIAL_BE_NL_ADDRESS_INDEX_V1'||!text(revision)||!revision||typeof index.get!=='function'||typeof index.bbox!=='function'||typeof index.health!=='function')throw Error('official_picker_index_unavailable');
 const guard=()=>{if(index.revision!==revision)throw Error('official_address_index_changed');};
 if(!plain(request)||request.schema!==OFFICIAL_ADDRESS_PICKER_V1)throw Error('official_picker_input_invalid');
 if(request.mode==='resolve_selected'){
  if(!keys(request,['schema','mode','official_address']))throw Error('official_picker_input_invalid');
  const ref=officialAddressReferenceV1({kind:'address',official_address:request.official_address});
  if(!ref||ref.index_revision!==revision)throw Error('official_address_index_changed');
  let raw;
  const selectedIndex={kind:index.kind,revision,get:async id=>{raw=await index.get(id);guard();
   if(raw?.schema==='fluxidi-official-address-v1'&&raw.id===id&&raw.indexRevision===revision&&(raw.source!==ref.source||raw.sourceVersion!==ref.source_version))throw Error('address_source_changed');return raw;}};
  const authority=createOfficialAddressAuthorityV1({index:selectedIndex,allowUnknownOfficialAssignment:true,allowMissingPosition:true});let record;
  try{record=await authority.resolve(ref.id);}catch(e){guard();if(e.message==='official_address_record_invalid'&&incompleteBoundSource(raw,ref,revision))return insufficient(revision,'official_source_address_incomplete');throw e;}guard();
  if(record.source!==ref.source||record.sourceVersion!==ref.source_version)throw Error('address_source_changed');
  if(!officialAddressPositionUsableV1(record))return insufficient(revision,'official_identity_position_unavailable_or_in_research');
  return {schema:OFFICIAL_ADDRESS_PICKER_V1,ok:true,status:'identity_resolved',index_revision:revision,suggestion:suggestion(record,revision),officialIdentity:{id:record.id,address:record.address,status:record.status,officiallyAssigned:record.officiallyAssigned},officialPosition:{...record.point,provenance:record.provenance??null},accessProven:false,routeProven:false};
 }
 if(request.mode!=='catalogue'||!keys(request,['schema','mode','bounds','language','query'])||!['nl','fr','de','en'].includes(request.language)||!text(request.query)||request.query.length>100)throw Error('official_picker_input_invalid');
 const bounds=boundsOf(request.bounds),query=fold(request.query);
 if(index.health()?.coverage?.allFourSourcesIngested!==true)return insufficient(revision,'official_catalogue_coverage_incomplete');
 let result;try{result=await index.bbox({...bounds,maxResults:2048});}catch(e){guard();if(['address_bbox_cell_limit','address_bbox_object_limit'].includes(e.message))return insufficient(revision,'official_identity_discovery_limit');throw e;}
 guard();if(result?.indexRevision!==revision)throw Error('official_address_index_changed');
 if(result.truncated===true)return insufficient(revision,'official_identity_discovery_truncated');
 if(result.truncated!==false||!Array.isArray(result.records)||result.records.length>2048)throw Error('official_picker_reader_contract');
 // Validate the immutable bounded source snapshot without N additional R2
 // get(id) operations. Selection re-reads its one ID through the real index.
 const snapshot=new Map();for(const r of result.records){if(!plain(r)||!r.id||snapshot.has(r.id))throw Error('official_picker_reader_contract');snapshot.set(r.id,r);}
 const authority=createOfficialAddressAuthorityV1({index:{kind:index.kind,revision,get:async id=>snapshot.get(id)},allowUnknownOfficialAssignment:true,allowMissingPosition:true});
 let catalogueCount=0,excludedCount=0;const suggestions=[];
 for(const row of result.records){
  if(row.status!=='current'||row.officiallyAssigned===false||!officialAddressPositionUsableV1(row)){excludedCount++;continue;}
  let r;try{r=await authority.resolve(row.id);}catch(e){guard();if(e.message==='official_address_record_invalid'&&incompleteBoundSource(row,{id:row.id,source:row.source,source_version:row.sourceVersion},revision))return insufficient(revision,'official_source_address_incomplete');throw e;}guard();const p=r.point;
  if(p.longitude<bounds.west||p.longitude>bounds.east||p.latitude<bounds.south||p.latitude>bounds.north)throw Error('official_picker_reader_contract');
  catalogueCount++;const s=suggestion(r,revision);if(!query||presentationLabels(r).some(value=>fold(value).includes(query)))suggestions.push(s);
 }
 if(suggestions.length>128)return insufficient(revision,'official_catalogue_response_limit');
 suggestions.sort((a,b)=>a.label.localeCompare(b.label)||a.official_address.id.localeCompare(b.official_address.id));guard();
 return {schema:OFFICIAL_ADDRESS_PICKER_V1,ok:true,status:'catalogue',index_revision:revision,bounds,query:request.query,complete:true,truncated:false,catalogue_count:catalogueCount,matched_count:suggestions.length,excluded_source_count:excludedCount,suggestions,accessProven:false,routeProven:false};
}
