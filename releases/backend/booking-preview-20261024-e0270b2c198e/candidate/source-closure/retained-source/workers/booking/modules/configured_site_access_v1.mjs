import {foldStreetV1,resolveNamedSiteFrontageV1} from './practical_frontage_v1.mjs';
// Server-owned company configuration, not an official house-number identity or
// a GPS fix. JSON cannot recreate the resulting frontage or route capability.
const frontages=new WeakSet(),points=new WeakMap(),references=new WeakMap();
const fail=r=>{throw Error(r);};
const hex=s=>typeof s==='string'&&/^[a-f0-9]{64}$/.test(s);
const sameScope=(a,b)=>a?.tenant_id===b?.tenant_id&&a?.company_id===b?.company_id;
const samePoint=(a,b)=>a?.latitude===b?.latitude&&a?.longitude===b?.longitude;
// Persistence shape only: this does NOT mint an access capability. Runtime
// graph/source/point/scope checks still run before every materialization.
export function normalizeConfiguredSiteBindingV1(value){
 const token=s=>typeof s==='string'&&/^[a-zA-Z0-9_.-]{1,160}$/.test(s),p=value?.configuredPoint;
 if(value?.schema!=='fluxidi-configured-site-access-v1'||!token(value.tenant_id)||!token(value.company_id)||!token(value.graphVersion)
  ||!Number.isSafeInteger(value.way)||value.way<1||!hex(value.sourceSha256)||!hex(value.ownerConfirmationSha256)
  ||typeof value.street!=='string'||!value.street.trim()||value.street.length>160||/[\r\n\0]/.test(value.street)
  ||!Number.isFinite(p?.latitude)||Math.abs(p.latitude)>90||!Number.isFinite(p?.longitude)||Math.abs(p.longitude)>180||p.latitude===0&&p.longitude===0)return null;
 return {schema:value.schema,tenant_id:value.tenant_id,company_id:value.company_id,configuredPoint:{latitude:p.latitude,longitude:p.longitude},
  graphVersion:value.graphVersion,sourceSha256:value.sourceSha256,way:value.way,street:value.street,ownerConfirmationSha256:value.ownerConfirmationSha256};
}
export function createConfiguredSiteReferenceV1({point,binding,scope}){
 if(!scope?.tenant_id||!scope?.company_id||binding?.schema!=='fluxidi-configured-site-access-v1'||!sameScope(binding,scope)||!samePoint(binding.configuredPoint,point)||!hex(binding.ownerConfirmationSha256)||!hex(binding.sourceSha256))fail('configured_site_binding_unproven');
 const result=Object.freeze({...point,access:Object.freeze({kind:'configured_site_reference'})});references.set(result,{binding:structuredClone(binding),scope:structuredClone(scope)});return result;
}
export function readConfiguredSiteReferenceV1(point,{scope}){
 const ref=references.get(point);
 if(!ref){if(point?.access?.kind==='configured_site_reference')fail('configured_site_reference_invalid');return null;}
 if(!sameScope(ref.scope,scope))fail('configured_site_scope_changed');return structuredClone(ref.binding);
}
export function configuredSiteInputV1({point,binding,scope,manifest}){
 if(!scope?.tenant_id||!scope?.company_id||binding?.schema!=='fluxidi-configured-site-access-v1'||!sameScope(binding,scope)
  ||!samePoint(binding.configuredPoint,point)||!Number.isFinite(point?.latitude)||!Number.isFinite(point?.longitude)
  ||binding.graphVersion!==manifest.graphVersion||binding.sourceSha256!==manifest.terminalAccess?.sourceSha256
  ||!hex(binding.ownerConfirmationSha256)||!Number.isSafeInteger(binding.way)||binding.way<1
  ||typeof binding.street!=='string'||!binding.street.trim()||binding.street.length>160)fail('configured_site_binding_unproven');
 return {...point,address:{street:binding.street},access:{kind:'configured_site'}};
}
export function createConfiguredSiteFrontageV1({input,binding,scope,manifest,context}){
 configuredSiteInputV1({point:input,binding,scope,manifest});
 if(context?.graphVersion!==manifest.graphVersion||context.revision!==manifest.accessContext.revision)fail('configured_site_context_changed');
 const rows=context.terminalRows?.filter(r=>r.way===binding.way);
 if(rows?.length!==1||rows[0].sourceSha256!==binding.sourceSha256||!rows[0].frontageTags?.streetNames?.some(n=>foldStreetV1(n)===foldStreetV1(binding.street)))fail('configured_site_source_unproven');
 const frontage=resolveNamedSiteFrontageV1({input,segments:context.segments,graphVersion:manifest.graphVersion,revision:manifest.accessContext.revision});
 if(frontage.wayIds.length!==1||frontage.wayIds[0]!==binding.way)fail('configured_site_frontage_changed');
 const frozen=Object.freeze({...frontage,point:Object.freeze({...frontage.point}),wayIds:Object.freeze([...frontage.wayIds])});frontages.add(frozen);return frozen;
}
export const configuredSiteFrontageVerifiedV1=f=>frontages.has(f);
export function createConfiguredSiteRoutePointV1({point,snap,scope,manifest,role,frontage}){
 if(!frontages.has(frontage)||!['origin','destination'].includes(role)||snap?.kind!=='terminal'||snap.accessEvidence?.terminal?.throughAccess!==false||!samePoint(snap.accessEvidence.frontage.point,frontage.point))fail('configured_site_snap_unproven');
 const result=Object.freeze({...point,access:Object.freeze({kind:'configured_site_access',role})});
 points.set(result,{snap,scope:structuredClone(scope),graphVersion:manifest.graphVersion,revision:manifest.accessContext.revision,role});return result;
}
export function readConfiguredSiteRoutePointV1(point,{scope,graphVersion,revision,role}){
 const proof=points.get(point);
 if(!proof){if(point?.access?.kind==='configured_site_access'||point?.access?.kind==='configured_site')fail('configured_site_handle_invalid');return null;}
 if(!scope?.tenant_id||!sameScope(scope,proof.scope)||proof.graphVersion!==graphVersion||proof.revision!==revision||proof.role!==role)fail('configured_site_handle_changed');
 return structuredClone(proof.snap);
}
