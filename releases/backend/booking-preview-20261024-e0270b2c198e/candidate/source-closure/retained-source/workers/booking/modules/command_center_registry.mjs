import {COMPANY_REGISTRY_MANIFEST_KEY,COMPANY_REGISTRY_PAGE_SIZE,registryPageKey,publicRegistryFields} from './company_registry_index.mjs';
const refuse=code=>{throw Object.assign(new Error(code),{code});};
const version=m=>JSON.stringify([m.membership_generation,m.page_count,m.total,m.write_token,m.updated_at]);
export async function commandCenterRegistryPage(kv,{page=1,generation=null}={}){
  if(!Number.isInteger(page)||page<1||page>10000) refuse('registry_page_invalid');
  const before=await kv.get(COMPANY_REGISTRY_MANIFEST_KEY,{type:'json'});
  if(!before||before.schema_version!==1||before.page_size!==COMPANY_REGISTRY_PAGE_SIZE||!Number.isSafeInteger(before.membership_generation)||before.membership_generation<0||!Number.isSafeInteger(before.total)||before.total<0||before.page_count!==Math.ceil(before.total/COMPANY_REGISTRY_PAGE_SIZE)) refuse('registry_manifest_unavailable');
  if(generation!==null&&generation!==before.membership_generation) refuse('registry_generation_changed');
  if(before.total===0){if(page!==1)refuse('registry_page_invalid');return{schema_version:'command_center_directory_v1',generation:before.membership_generation,total:0,page:1,page_count:0,items:[],next_page:null};}
  if(page>before.page_count) refuse('registry_page_invalid');
  const record=await kv.get(registryPageKey(page),{type:'json'});
  const expected=page===before.page_count?(before.total%COMPANY_REGISTRY_PAGE_SIZE||COMPANY_REGISTRY_PAGE_SIZE):COMPANY_REGISTRY_PAGE_SIZE;
  if(!record||record.page!==page||record.membership_generation!==before.membership_generation||!Array.isArray(record.companies)||record.companies.length!==expected||new Set(record.companies.map(row=>row.company_code)).size!==expected||record.companies.some(row=>!/^FLX-[0-9]{4,12}$/.test(row.company_code))) refuse('registry_page_incomplete');
  const after=await kv.get(COMPANY_REGISTRY_MANIFEST_KEY,{type:'json'});
  if(!after||version(after)!==version(before)) refuse('registry_generation_changed');
  return{schema_version:'command_center_directory_v1',generation:before.membership_generation,total:before.total,
    page,page_count:before.page_count,items:record.companies.map(publicRegistryFields),next_page:page<before.page_count?page+1:null};
}
