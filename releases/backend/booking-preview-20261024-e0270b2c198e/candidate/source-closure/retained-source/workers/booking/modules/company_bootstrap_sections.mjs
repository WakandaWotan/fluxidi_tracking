import {hashDocumentSnapshot} from './document_core.js';
const names=new Set(['company_core','permissions','config','branding','drivers','vehicles','relations','documents_refs','service_areas','feature_flags','communications']);
export function parseBootstrapSectionRevisions(raw='') {
  if(typeof raw!=='string'||raw.length>4096)throw Error('bootstrap_revisions_invalid');
  let value;try{value=raw?JSON.parse(raw):{};}catch{throw Error('bootstrap_revisions_invalid');}
  if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).length>names.size)throw Error('bootstrap_revisions_invalid');
  for(const [key,revision]of Object.entries(value))if(!names.has(key)||typeof revision!=='string'||revision.length>160)throw Error('bootstrap_revisions_invalid');
  return value;
}
export async function revisionedBootstrapSections(scope,definitions,since={}) {
  if(!scope?.tenant_id||!scope.company_id)throw Error('bootstrap_scope_required');
  const revisions={},sections={},changed=[];
  for(const [name,definition]of Object.entries(definitions)){
    if(!names.has(name))throw Error('bootstrap_section_unknown');
    const revision=definition.revision===null?null:definition.revision||await hashDocumentSnapshot({scope,name,value:definition.value});
    revisions[name]=revision;
    if(revision===null||since[name]!==revision){sections[name]=definition.load?await definition.load():definition.value;changed.push(name);}
  }
  return {ok:true,bootstrap_contract_version:2,...scope,mode:'revisioned_sections',revisions,changed_sections:changed,sections,recovery_endpoint:'/company/bootstrap',collections_contract:'paged descriptors; full recovery remains the original endpoint'};
}
