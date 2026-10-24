import {FLUXIDI_SELLER_ID} from './subscription_invoice_parties.mjs';
const scopePart=value=>typeof value==='string'&&/^[A-Za-z0-9_-]{1,80}$/.test(value)&&value!=='global';
const paymentId=value=>typeof value==='string'&&/^tr_[A-Za-z0-9_]{1,120}$/.test(value);
const cents=value=>Number.isSafeInteger(value)&&value>=0;
const iso=value=>typeof value==='string'&&Number.isFinite(Date.parse(value))&&new Date(value).toISOString()===value;

export function closeInvoiceDraft(row,scope){
  if(row?.version!=='subscription_invoice_draft_v1'||row.state!=='awaiting_issue'||row.invoice_number!==null||
    row.tenant_id!==scope.tenant_id||row.company_id!==scope.company_id||!paymentId(row.payment_id)||
    row.provider!=='mollie'||row.seller_id!==FLUXIDI_SELLER_ID||!row.review_reference||!row.fiscal_reference||
    !['live','test'].includes(row.mode)||!iso(row.paid_at)||! /^[A-Z]{3}$/.test(row.currency)||
    ![row.ex_vat_cents,row.vat_cents,row.gross_cents].every(cents)||row.ex_vat_cents+row.vat_cents!==row.gross_cents||
    !Number.isSafeInteger(row.vat_rate_bps)||row.vat_rate_bps<0||row.vat_rate_bps>10000||
    !['reviewed_taxable','eu_b2b_reverse_charge','reviewed_zero_rate'].includes(row.treatment)||
    (row.treatment==='reviewed_taxable'?(row.vat_rate_bps===0):(row.vat_rate_bps!==0||row.vat_cents!==0)))throw Error('invoice_draft_source_invalid');
  return {payment_id:row.payment_id,state:'awaiting_issue',invoice_issued:false,provider:'mollie',mode:row.mode,paid_at:row.paid_at,
    currency:row.currency,ex_vat_cents:row.ex_vat_cents,vat_cents:row.vat_cents,gross_cents:row.gross_cents,treatment:row.treatment,vat_rate_bps:row.vat_rate_bps};
}

/** Scoped immutable fiscal captures only; this read never issues an invoice. */
export async function readInvoiceDraftPage(storage,{tenant_id,company_id,cursor='',limit=50}={}){
  const scope={tenant_id,company_id};
  if(!scopePart(tenant_id)||!scopePart(company_id)||!Number.isInteger(limit)||limit<1||limit>50||cursor!==''&&!paymentId(cursor))throw Error('invoice_draft_query_invalid');
  return storage.transaction(async txn=>{
    const owner=await txn.get('invoice_draft_scope:v1');
    if(owner&&owner!==JSON.stringify([tenant_id,company_id]))throw Error('invoice_draft_scope_conflict');
    const rows=await txn.list({prefix:'invoice_draft:',...(cursor?{startAfter:`invoice_draft:${cursor}:v1`}:{}),limit:limit+1});
    if(!(rows instanceof Map)||rows.size>limit+1||(!owner&&rows.size))throw Error('invoice_draft_source_invalid');
    const closed=[...rows].map(([key,value])=>{
      const row=typeof value==='string'?JSON.parse(value):value;
      if(key!==`invoice_draft:${row?.payment_id}:v1`)throw Error('invoice_draft_identity_conflict');
      return closeInvoiceDraft(row,scope);
    });
    return {ok:true,schema_version:'command_center_invoice_drafts_v1',provenance:'verified_subscription_fiscal_drafts',coverage:'captured_fiscal_drafts_only',
      complete_provider_history:false,generated_at:new Date().toISOString(),items:closed.slice(0,limit),next_cursor:closed.length>limit?closed[limit-1].payment_id:null};
  });
}

export async function commandCenterInvoiceDrafts(env,scope,params){
  const binding=env.FLUXIDI_SUBSCRIPTION_FOUNDER_SLOTS;
  if(!binding?.idFromName||!binding?.get)throw Error('invoice_draft_binding_unavailable');
  const id=binding.idFromName(`subscription:invoice-drafts:${JSON.stringify([scope.tenant_id,scope.company_id])}`);
  const response=await binding.get(id).fetch(new Request('https://subscription-internal/invoice-drafts',{method:'POST',redirect:'manual',signal:AbortSignal.timeout(15000),
    headers:{'content-type':'application/json'},body:JSON.stringify({action:'invoice_drafts_read',tenant_id:scope.tenant_id,company_id:scope.company_id,cursor:params.get('cursor')||'',limit:Number(params.get('limit')||50)})}));
  if(!response.ok)throw Error('invoice_draft_source_unavailable');
  const data=await response.json();
  if(data?.ok!==true||data.schema_version!=='command_center_invoice_drafts_v1'||data.provenance!=='verified_subscription_fiscal_drafts'||data.coverage!=='captured_fiscal_drafts_only'||data.complete_provider_history!==false)throw Error('invoice_draft_source_invalid');
  return {...data,capture_enabled:!!env.FLUXIDI_SUBSCRIPTION_TAX_POLICY_VERSION};
}
