import {buildScopedMollieConnectStatusKey} from './mollie_connect.js';
import {buildBillitOAuthConnectionKey} from './billit_provider.js';
import {_proxyChironConfigStatusToComplianceWorker} from './chiron_bridge.js';

const iso=value=>typeof value==='string'&&Number.isFinite(Date.parse(value))?value:null;
const unknown=id=>({id,status:'unknown',environment:null,source_revision:null,source_updated_at:null,verified_at:null,production_verified:false});
const object=value=>value&&typeof value==='object'&&!Array.isArray(value);

async function chironFact(env,scope){
  if(!env.COMPLIANCE_WORKER?.fetch||!(env.COMPLIANCE_ADMIN_TOKEN||env.ADMIN_TOKEN))return unknown('chiron');
  let response,row;
  try{
    const boundedEnv={...env,COMPLIANCE_WORKER:{fetch:request=>env.COMPLIANCE_WORKER.fetch(new Request(request,{redirect:'manual',signal:AbortSignal.timeout(15000)}))}};
    response=await _proxyChironConfigStatusToComplianceWorker(boundedEnv,scope,{method:'GET'});
    if(!response.ok)return unknown('chiron');
    row=await response.json();
  }catch{return unknown('chiron');}
  if(row?.ok!==true||row.schema_version!=='chiron_connection_status_v1')return unknown('chiron');
  if(row.tenant_id!==scope.tenant_id||row.company_id!==scope.company_id)throw Error('integration_scope_conflict');
  const status=row.enabled===false?'disconnected':row.last_connection_status==='test_passed'?'connected':row.last_connection_status==='test_failed'?'error':'unknown';
  const rawEnvironment=row.effective_chiron_environment??row.environment;
  const environment=['production','prod','live'].includes(rawEnvironment)?'live':['acc','test'].includes(rawEnvironment)?rawEnvironment:null;
  return {...unknown('chiron'),status,environment,source_updated_at:iso(row.updated_at)};
}

/** Read saved connection facts only: no credential release, refresh, or provider call. */
export async function commandCenterIntegrationFacts(env,scope){
  const read=async key=>{
    if(!env.BOOKING_KV?.get)return null;
    try{
      const row=await env.BOOKING_KV.get(key,{type:'json'});
      if(!object(row))return null;
      if((row.tenant_id&&row.tenant_id!==scope.tenant_id)||(row.company_id&&row.company_id!==scope.company_id))throw Error('integration_scope_conflict');
      return row;
    }catch(error){if(error.message==='integration_scope_conflict')throw error;return null;}
  };
  const [mollie,billit,chiron]=await Promise.all([read(buildScopedMollieConnectStatusKey(scope)),read(buildBillitOAuthConnectionKey(scope)),chironFact(env,scope)]);
  const fact=(id,row,environment)=>{
    if(!row)return unknown(id);
    const status=row.connected===true&&row.status==='connected'?'connected':row.connected===false&&row.status==='disconnected'?'disconnected':['error','pending'].includes(row.status)?row.status:'unknown';
    return {...unknown(id),status,environment,source_revision:Number.isSafeInteger(row.source_revision)&&row.source_revision>=1?row.source_revision:null,source_updated_at:iso(row.source_updated_at??row.updated_at)};
  };
  return {schema_version:'command_center_integrations_v1',provenance:'booking_saved_connection_records',items:[
    fact('mollie',mollie,['test','live'].includes(mollie?.mollie_mode)?mollie.mollie_mode:null),
    fact('billit',billit,['production','live'].includes(billit?.environment)?'live':['sandbox','test'].includes(billit?.environment)?'sandbox':null),
    // Billit connection and VAT presence do not prove Peppol registration.
    // The scoped compliance status GET does not perform a connection test.
    unknown('peppol'),chiron,
  ]};
}
