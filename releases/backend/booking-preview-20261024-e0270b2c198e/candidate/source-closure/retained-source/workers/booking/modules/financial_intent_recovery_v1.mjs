import {financialEvidenceStore,financialQuoteInputs,verifyBookingFinancialEvidence} from './financial_quote_lifecycle.mjs';
import {verifyFinancialClosureV1} from './financial_route_evidence.mjs';
import {canonicalBookingOperation,canonicalBookingAuthorityEnabled} from './canonical_booking_authority.mjs';
import {resolveCanonicalFinancialIntentV1} from './financial_intent_resolution_v1.mjs';
import {assertFinancialSaleBookBodyV2} from './financial_sale_projection_v2.mjs';
export const FINANCIAL_RECOVERY_PATH_V1='/public/customer/financial-intent';
export const FINANCIAL_RECOVERY_SCHEMA_V1='fluxidi-financial-intent-recovery-v1';
const plain=x=>x&&typeof x==='object'&&!Array.isArray(x);
const failure=(error,status=409)=>({ok:false,error,status,safe_to_requote:false});
const canonical=x=>JSON.stringify(x,(_,v)=>plain(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
export async function financialRecoveryBodyHashV1(body){return [...new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(canonical(body))))].map(x=>x.toString(16).padStart(2,'0')).join('');}
export async function readFinancialRecoveryRequestV1(request){
  if(!/^application\/json(?:;|$)/i.test(request.headers.get('content-type')??''))throw Error('financial_recovery_input_invalid');
  if(new URL(request.url).search||request.headers.has('content-encoding'))throw Error('financial_recovery_input_invalid');
  const reader=request.body?.getReader();if(!reader)throw Error('financial_recovery_input_invalid');
  const chunks=[];let size=0;try{for(;;){const x=await reader.read();if(x.done)break;size+=x.value.length;if(size>65536){await reader.cancel();throw Error('financial_recovery_body_limit');}chunks.push(x.value);}}finally{reader.releaseLock();}
  const b=new Uint8Array(size);let i=0;for(const c of chunks){b.set(c,i);i+=c.length;}
  return validateFinancialRecoveryRequestV1(JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(b)));
}
export function validateFinancialRecoveryRequestV1(b){
  if(!plain(b)||b.schema!==FINANCIAL_RECOVERY_SCHEMA_V1||!['status','close'].includes(b.operation)
    ||Object.keys(b).some(k=>!['schema','operation','financial_request_body','expected_revision'].includes(k))
    ||!plain(b.financial_request_body)||new TextEncoder().encode(JSON.stringify(b.financial_request_body)).length>32768
    ||!/^[a-f0-9]{64}$/.test(b.financial_request_body.financial_quote_id??'')
    ||b.operation==='close'&&(!Number.isSafeInteger(b.expected_revision)||b.expected_revision<0))throw Error('financial_recovery_input_invalid');
  return b;
}
// Called only under the existing serialized company coordinator. No allocator,
// provider request, dispatch, price computation, KV adoption or booking creation.
export async function financialIntentRecoveryV1({state,env,scope,actor,body,bookedResponse,now=Date.now()}){
  try{
    validateFinancialRecoveryRequestV1(body);
    if(!actor?.customer_id)return failure('unauthorized',401);
    if(!(actor.tenant_id==='global'&&actor.company_id==='global')&&(actor.tenant_id!==scope.tenant_id||actor.company_id!==scope.company_id))return failure('forbidden',403);
    const frozen=body.financial_request_body,store=financialEvidenceStore(env,scope);
    if(!store)return failure('financial_evidence_storage_unavailable',503);
    const inspected=await store.inspectIntent({quoteId:frozen.financial_quote_id,scope,inputs:financialQuoteInputs(frozen)}),{quote,claim}=inspected;
    if(quote.inputs.financial_context?.schema!=='fluxidi-vehicle-financial-context-v1')return failure('financial_recovery_owner_unproven');
    if(quote.inputs.financial_context.customer_id!==actor.customer_id)return failure('forbidden',403);
    if(quote.version===2)assertFinancialSaleBookBodyV2(frozen,quote.money);
    if(frozen.financial_price_consent&&(frozen.financial_price_consent.financial_quote_id!==quote.id
      ||frozen.financial_price_consent.currency!==quote.money.currency
      ||frozen.financial_price_consent.gross_cents!==quote.money.gross_cents))return failure('financial_recovery_price_binding_changed');
    const base={schema:FINANCIAL_RECOVERY_SCHEMA_V1,ok:true,financial_quote_id:quote.id,owner_id:actor.customer_id,
      scope:quote.scope,financial_input_hash:quote.input_hash,request_body_hash:await financialRecoveryBodyHashV1(frozen),
      financial_snapshot:{...(quote.version===2?{version:2}:{}),evidence_id:quote.id,money:quote.money,...(quote.version===1?{route:quote.route}:{}),scope:quote.scope},
      revision:claim?.revision??0,booking_id:claim?.booking_id??claim?.closed_booking_id??null,safe_to_requote:false};
    if(!canonicalBookingAuthorityEnabled(env))return failure('financial_recovery_canonical_authority_required',503);
    const identity=claim?.booking_id??claim?.closed_booking_id;
    const canonicalRecord=identity ? await canonicalBookingOperation(state,env,{operation:'inspect',scope,bookingId:identity}):{ok:true,record:null};
    if(!canonicalRecord.ok)return failure(canonicalRecord.error,503);
    const record=canonicalRecord.record;
    base.canonical_revision=record?._canonical_version??null;
    if(record){
      if(claim?.state==='closed')return failure('financial_recovery_closed_effect_conflict');
      const evidence=await verifyBookingFinancialEvidence(record);
      if(!evidence||evidence.id!==quote.id||record.customer_id&&record.customer_id!==actor.customer_id)return failure('financial_recovery_canonical_evidence_conflict');
      const financialResolution=await resolveCanonicalFinancialIntentV1({state,env,scope,bookingId:identity});
      if(financialResolution.ok){
        const result={...bookedResponse(claim.booking_id,record),financial_quote_id:quote.id,financial_acceptance_status:'booked',financial_snapshot:base.financial_snapshot};
        // The legacy builder describes the online payment channel with
        // requiresPayment=true even after payment. Only the private resolver's
        // bound provider proof may turn that into a settled recovery receipt.
        if(financialResolution.payment_basis==='canonical_paid')Object.assign(result,{
          financial_payment_resolution:'canonical_paid',requiresPayment:false,requires_payment:false,
        });
        return {...base,...(body.operation==='close'?{ok:false,status:409,error:'financial_recovery_booking_exists'}:{}),state:'booked',replay_required:false,
          result};
      }
      // BOOKED is an operational fact, not proof that the financial owner
      // fence resolved. Existing clients stop on 409 and retain their journal.
      if(record.stage==='BOOKED')return {...base,...failure('financial_recovery_pending'),state:'pending',reason:financialResolution.reason,replay_required:false};
      return {...base,...(body.operation==='close'?{ok:false,status:409,error:'financial_recovery_replay_required'}:{}),state:'pending',reason:'canonical_checkout_pending',replay_required:true};
    }
    const payment=identity ? await state.storage.get(`initial-booking-payment:${identity}`):null;
    if(claim?.state==='closed'){
      await store.storage.assertCloseFence();
      if(inspected.frozen||payment)return failure('financial_recovery_closed_effect_conflict');
      return {...base,state:'closed',replay_required:false,safe_to_requote:true,closure_receipt:await verifyFinancialClosureV1(claim,quote,actor.customer_id)};
    }
    if(inspected.frozen||payment||claim&&claim.state!=='reserved')return {...base,...(body.operation==='close'?{ok:false,status:409,error:'financial_recovery_replay_required'}:{}),state:'pending',reason:payment?'provider_or_payment_identity_unresolved':inspected.frozen?'financial_acceptance_started':'legacy_claim_unresolved',replay_required:true};
    if(body.operation==='status')return {...base,state:claim?'pending':'unsubmitted',reason:claim?'reserved_before_execution':'no_server_claim',replay_required:!!claim};
    const closed=await store.closeUnusedIntent({quoteId:quote.id,scope,inputs:financialQuoteInputs(frozen),expectedRevision:body.expected_revision,ownerId:actor.customer_id,now});
    return {...base,revision:closed.revision,booking_id:closed.closed_booking_id,state:'closed',replay_required:false,safe_to_requote:true,
      closure_receipt:await verifyFinancialClosureV1(closed,quote,actor.customer_id)};
  }catch(e){
    const known=['financial_intent_closed','financial_recovery_revision_changed','financial_recovery_replay_required','evidence_scope_mismatch','evidence_inputs_changed',
      'financial_contract_upgrade_required','financial_transient_route_payload_not_allowed','financial_sale_price_consent_changed'];
    return failure(known.includes(e.message)?e.message:'financial_recovery_unavailable',known.includes(e.message)?409:503);
  }
}
