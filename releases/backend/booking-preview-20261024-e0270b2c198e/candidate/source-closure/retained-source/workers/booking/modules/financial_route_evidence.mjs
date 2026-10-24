// Server-owned evidence contract. No provider selection, HTTP or traffic lookup.
// Storage must be private, durable and implement atomic insert-if-absent.
import {assertFinancialSaleMoneyV2} from './financial_sale_projection_v2.mjs';
const clone = value => structuredClone(value);
const fail = reason => { throw new Error(reason); };
function canonical(value) {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number' && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${canonical(value[k])}`).join(',')}}`;
  return fail('evidence_value_invalid');
}
async function digest(value) {
  const bytes = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonical(value)));
  return [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2, '0')).join('');
}
function scopeOf(scope) {
  if (!scope || !['tenant_id','company_id'].every(k => typeof scope[k] === 'string' && scope[k].trim())) fail('evidence_scope_required');
  return {tenant_id:scope.tenant_id,company_id:scope.company_id};
}
function checkRoute(route) {
  const approvedLegacy = route?.source === 'mapbox' && route.source_version === 'directions/v5'
    && route.profile === 'mapbox/driving' && route.duration_basis === 'provider_driving';
  const certifiedInternal = route?.duration_basis === 'static_normalized'
    && route.source && route.source_version && route.graph_checksum;
  if (!route || route.access_cost !== 'included' || (!approvedLegacy && !certifiedInternal)) fail('financial_route_not_certified');
  if (!Array.isArray(route.points) || route.points.length < 2 || !route.points.every(p => Number.isFinite(p.lat) && Math.abs(p.lat)<=90 && Number.isFinite(p.lng) && Math.abs(p.lng)<=180)) fail('evidence_points_invalid');
  if (!Array.isArray(route.legs) || route.legs.length !== route.points.length-1
    || !route.legs.every(l => ['distance_m','duration_s'].every(k => Number.isFinite(l[k]) && l[k]>=0))) fail('evidence_legs_invalid');
  if (route.additional_routes != null) {
    if (!Array.isArray(route.additional_routes)) fail('evidence_legs_invalid');
    route.additional_routes.forEach(checkRoute);
  }
  return clone(route);
}
function moneyOf(money) {
  if (!money || money.currency !== 'EUR' || !['net_cents','vat_cents','gross_cents'].every(k => Number.isSafeInteger(money[k]) && money[k]>=0)
    || money.net_cents+money.vat_cents !== money.gross_cents) fail('evidence_money_invalid');
  return clone(money);
}
export async function createFinancialQuoteEvidence({scope,inputs,tariff,route,money,now,expiresAt,routeRetention='full'}) {
  if (!Number.isSafeInteger(now) || !Number.isSafeInteger(expiresAt) || expiresAt<=now) fail('evidence_expiry_invalid');
  const checked=checkRoute(route);
  if(!['full','sale_only'].includes(routeRetention))fail('financial_route_retention_invalid');
  const routes=[checked,...(checked.additional_routes ?? [])];
  checked.total_distance_m=routes.reduce((sum,r)=>sum+r.legs.reduce((n,l)=>n+l.distance_m,0),0);
  checked.total_duration_s=routes.reduce((sum,r)=>sum+r.legs.reduce((n,l)=>n+l.duration_s,0),0);
  if(routeRetention==='sale_only'){if(checked.source!=='mapbox')fail('financial_route_retention_invalid');assertFinancialSaleMoneyV2(money);}
  const content={version:routeRetention==='sale_only'?2:1,scope:scopeOf(scope),input_hash:await digest(inputs),inputs:clone(inputs),tariff_hash:await digest(tariff),tariff:clone(tariff),
    ...(routeRetention==='full'?{route:checked}:{}),money:moneyOf(money),created_at:now,expires_at:expiresAt};
  return {...content,id:await digest(content)};
}
export async function verifyFinancialQuoteEvidence(record,{scope,inputs,tariff,now,accepted=false}) {
  const {id,...content}=record ?? {};
  if (![1,2].includes(content.version) || id!==await digest(content)) fail('evidence_integrity_failed');
  if(content.version===2){
    if(Object.keys(content).some(k=>!['version','scope','input_hash','inputs','tariff_hash','tariff','money','created_at','expires_at'].includes(k)))fail('financial_sale_projection_invalid');
    assertFinancialSaleMoneyV2(content.money);
  }
  if (canonical(content.scope)!==canonical(scopeOf(scope))) fail('evidence_scope_mismatch');
  let checkedInputs=inputs;
  // Already accepted v1 sales keep the financial input definition signed at
  // acceptance. New/pending quotes and v2 sales remain strict, including stops.
  if (accepted && content.inputs?.financial_inputs_version == null
      && Object.hasOwn(content.inputs ?? {},'pricing_options')
      && inputs?.financial_inputs_version===2) {
    checkedInputs={...inputs};delete checkedInputs.financial_inputs_version;
    if (!Object.hasOwn(content.inputs,'stop_coordinates')) delete checkedInputs.stop_coordinates;
    if (checkedInputs.return && typeof checkedInputs.return==='object') {
      checkedInputs.return={...checkedInputs.return};
      if (!Object.hasOwn(content.inputs.return ?? {},'stop_coordinates')) delete checkedInputs.return.stop_coordinates;
    }
  }
  if (content.input_hash!==await digest(checkedInputs)) fail('evidence_inputs_changed');
  if (!accepted && content.tariff_hash!==await digest(tariff)) fail('evidence_tariff_changed');
  if (!accepted && (!Number.isSafeInteger(now) || now>=content.expires_at)) fail('evidence_expired');
  if(content.version===1)checkRoute(content.route); moneyOf(content.money);
  return clone(record);
}
export class FinancialRouteEvidenceStore {
  constructor(storage) {
    if (typeof storage?.get!=='function' || typeof storage?.insertIfAbsent!=='function') fail('atomic_evidence_storage_required');
    this.storage=storage;
  }
  async saveQuote(record) {
    const {id,...content}=record;
    if (id!==await digest(content)) fail('evidence_integrity_failed');
    if((await this.storage.get(`acceptance:${id}`))?.state==='closed')fail('financial_intent_closed');
    await this.storage.insertIfAbsent(`quote:${id}`,clone(record));
    return id;
  }
  // Reserve one durable canonical identity before any operational side effect.
  // A restart can recover it even when the KV booking projection was not written.
  async reserveAcceptance({quoteId,allocateBookingId,...validation}) {
    const record=await this.storage.get(`quote:${quoteId}`);
    const key=`acceptance:${quoteId}`;
    const existing=await this.storage.get(key);
    await verifyFinancialQuoteEvidence(record,{...validation,accepted:!!existing});
    if(await this.storage.get(`historical-hold:${quoteId}`))fail('financial_historical_execution_held');
    if(existing?.state==='closed')fail('financial_intent_closed');
    if (existing) return clone(existing);
    const candidate={booking_id:await allocateBookingId(),...(typeof this.storage.compareAndSet==='function'?{state:'reserved',revision:1}: {})};
    await this.storage.insertIfAbsent(key,candidate);
    const winner=await this.storage.get(key);
    if(winner?.state==='closed')fail('financial_intent_closed');
    if (!winner?.booking_id) fail('acceptance_identity_missing');
    return clone(winner);
  }
  async accept({quoteId,bookingId,...validation}) {
    if (typeof bookingId!=='string' || !bookingId) fail('booking_id_required');
    const record=await this.storage.get(`quote:${quoteId}`);
    const priorClaim=await this.storage.get(`acceptance:${quoteId}`);
    if(priorClaim?.state==='closed')fail('financial_intent_closed');
    if (priorClaim && priorClaim.booking_id!==bookingId) fail('quote_already_accepted');
    await verifyFinancialQuoteEvidence(record,{...validation,accepted:!!priorClaim});
    if(await this.storage.get(`historical-hold:${quoteId}`))fail('financial_historical_execution_held');
    // A quote can be accepted by one canonical booking only. A failed attempt
    // retains its claim for the same booking's retry; it cannot become a second sale.
    const claimKey=`acceptance:${record.id}`;
    const claim={booking_id:bookingId};
    const claimed=await this.storage.insertIfAbsent(claimKey,claim);
    if (!claimed && (await this.storage.get(claimKey))?.booking_id!==bookingId) fail('quote_already_accepted');
    // Fence the first irreversible financial/operational work against close.
    // Legacy insert-only claims remain replayable but cannot be safely closed.
    const live=await this.storage.get(claimKey);
    if(live?.state==='closed')fail('financial_intent_closed');
    if(live?.state==='reserved'){
      if(!await this.storage.compareAndSet(claimKey,live,{...live,state:'executing',revision:live.revision+1})){
        const changed=await this.storage.get(claimKey);
        if(changed?.state==='closed')fail('financial_intent_closed');
        if(changed?.booking_id!==bookingId||changed?.state!=='executing')fail('financial_intent_transition_conflict');
      }
    }
    const key=`booking:${await digest({scope:scopeOf(validation.scope),bookingId})}`;
    const frozen={booking_id:bookingId,evidence:record};
    const inserted=await this.storage.insertIfAbsent(key,clone(frozen));
    const stored=inserted ? frozen : await this.storage.get(key);
    if (stored?.evidence?.id!==record.id) fail('booking_evidence_already_frozen');
    return clone(stored);
  }
  async readAccepted({bookingId,scope,inputs}) {
    const key=`booking:${await digest({scope:scopeOf(scope),bookingId})}`;
    const stored=await this.storage.get(key);
    if (!stored) fail('booking_evidence_missing');
    await verifyFinancialQuoteEvidence(stored.evidence,{scope,inputs,accepted:true});
    // readAccepted is also the execution replay path in acceptFinancialQuote
    // and payment finalization. Frozen evidence must not bypass a later hold.
    if(await this.storage.get(`historical-hold:${stored.evidence.id}`))fail('financial_historical_execution_held');
    return clone(stored);
  }
  // The accepted sale is already frozen in this D1 table. Canonical booking
  // storage may hold a scoped reference instead of copying a large tariff
  // snapshot into every booking revision. Read-only consumers may inspect a
  // historical hold; execution callers must still honour it.
  async readAcceptedReference({bookingId,scope,quoteId,enforceHold=false}) {
    const key=`booking:${await digest({scope:scopeOf(scope),bookingId})}`;
    const stored=await this.storage.get(key);
    if(stored?.booking_id!==bookingId||stored?.evidence?.id!==quoteId)fail('booking_evidence_reference_missing');
    await verifyFinancialQuoteEvidence(stored.evidence,{scope,inputs:stored.evidence.inputs,accepted:true});
    const claim=await this.storage.get(`acceptance:${quoteId}`);
    if(claim?.booking_id!==bookingId||claim?.state==='closed')fail('booking_evidence_reference_conflict');
    if(enforceHold&&await this.storage.get(`historical-hold:${quoteId}`))fail('financial_historical_execution_held');
    return clone(stored.evidence);
  }
  async inspectIntent({quoteId,scope,inputs}) {
    const quote=await this.storage.get(`quote:${quoteId}`);
    await verifyFinancialQuoteEvidence(quote,{scope,inputs,accepted:true});
    const claim=await this.storage.get(`acceptance:${quoteId}`);
    const bookingId=claim?.booking_id??claim?.closed_booking_id;
    const frozen=bookingId ? await this.storage.get(`booking:${await digest({scope:scopeOf(scope),bookingId})}`) : null;
    return {quote,claim:claim??null,frozen:frozen??null};
  }
  async closeUnusedIntent({quoteId,scope,inputs,expectedRevision,ownerId,now}) {
    if(typeof this.storage.compareAndSet!=='function')fail('financial_recovery_atomic_storage_required');
    if(typeof this.storage.assertCloseFence!=='function')fail('financial_recovery_storage_fence_required');
    await this.storage.assertCloseFence();
    const {quote,claim,frozen}=await this.inspectIntent({quoteId,scope,inputs});
    if(claim?.state==='closed'){if(frozen)fail('financial_recovery_replay_required');return clone(claim);}
    if(frozen||claim&&claim.state!=='reserved')fail('financial_recovery_replay_required');
    const revision=claim?.revision??0;
    if(expectedRevision!==revision)fail('financial_recovery_revision_changed');
    const receipt={schema:'fluxidi-financial-intent-closure-v1',financial_quote_id:quoteId,scope:scopeOf(scope),owner_id:ownerId,
      financial_input_hash:quote.input_hash,booking_id:claim?.booking_id??null,previous_revision:revision,revision:revision+1,
      closed_at:now,reason:'no_execution_started',active_booking:false,provider_payment_started:false,active_financial_claim:false};
    const closed={...claim,booking_id:claim?.booking_id??null,closed_booking_id:claim?.booking_id??null,state:'closed',revision:revision+1,storage_fence_version:1,
      _scope_key:JSON.stringify([quote.scope.tenant_id,quote.scope.company_id]),
      _owner_key:JSON.stringify([quote.scope.tenant_id,quote.scope.company_id,ownerId]),receipt:{...receipt,id:await digest(receipt)}};
    const key=`acceptance:${quoteId}`;
    const won=claim?await this.storage.compareAndSet(key,claim,closed):await this.storage.insertIfAbsent(key,closed);
    if(!won){const current=await this.storage.get(key);if(current?.state==='closed')return clone(current);fail('financial_recovery_revision_changed');}
    return clone(closed);
  }
}
export async function verifyFinancialClosureV1(claim, quote, ownerId) {
  const {id,...receipt}=claim?.receipt??{};
  if(claim?.state!=='closed'||receipt.schema!=='fluxidi-financial-intent-closure-v1'||id!==await digest(receipt)
    ||receipt.financial_quote_id!==quote.id||receipt.financial_input_hash!==quote.input_hash
    ||canonical(receipt.scope)!==canonical(quote.scope)||receipt.owner_id!==ownerId
    ||claim.storage_fence_version!==1||receipt.booking_id!==claim.booking_id||receipt.booking_id!==claim.closed_booking_id||receipt.revision!==claim.revision
    ||!Number.isSafeInteger(receipt.revision)||receipt.revision!==receipt.previous_revision+1
    ||receipt.reason!=='no_execution_started'||receipt.active_booking!==false
    ||receipt.provider_payment_started!==false||receipt.active_financial_claim!==false)fail('financial_closure_integrity_failed');
  return clone(claim.receipt);
}
