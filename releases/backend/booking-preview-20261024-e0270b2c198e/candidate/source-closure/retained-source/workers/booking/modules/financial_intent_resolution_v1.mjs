import{financialEvidenceStore,verifyBookingFinancialEvidence,assertFinancialProviderPayment}from'./financial_quote_lifecycle.mjs';
import{canonicalBookingOperation,canonicalBookingAuthorityEnabled}from'./canonical_booking_authority.mjs';
// Release an owner fence only after the existing private canonical authority
// proves a completed booking and a determinate payment outcome. No provider
// queries, payment mutation, quote, dispatch or new booking is performed here.
export async function resolveCanonicalFinancialIntentV1({state,env,scope,bookingId}){
 const store=financialEvidenceStore(env,scope);
 if(!bookingId||!store||!await store.storage.hasCloseFence()||!canonicalBookingAuthorityEnabled(env))return{ok:false,reason:'resolution_unavailable'};
 const inspected=await canonicalBookingOperation(state,env,{operation:'inspect',scope,bookingId});
 if(!inspected.ok||!inspected.record||!['BOOKED','PENDING'].includes(inspected.record.stage))return{ok:false,reason:'canonical_booking_unresolved'};
 const record=inspected.record,evidence=await verifyBookingFinancialEvidence(record);
 if(!evidence)return{ok:false,reason:'financial_evidence_unproven'};
 const owner=evidence.inputs.financial_context?.schema==='fluxidi-vehicle-financial-context-v1'?evidence.inputs.financial_context.customer_id:null;
 const containers=[record,record.booking,record.payload].filter(x=>x&&typeof x==='object');
 const owners=containers.flatMap(x=>[x.customer_id,x.customerId]).filter(x=>x!==undefined);
 const bookings=containers.flatMap(x=>[x.booking_id,x.bookingId]).concat(record.id).filter(x=>x!==undefined);
 if(typeof owner!=='string'||!owner||!owners.length||owners.some(x=>x!==owner)||!bookings.length||bookings.some(x=>x!==bookingId)
  ||evidence.scope.tenant_id!==scope.tenant_id||evidence.scope.company_id!==scope.company_id)return{ok:false,reason:'financial_identity_conflict'};
 if(containers.some(x=>[x.tenant_id,x.tenantId].some(v=>v!==undefined&&v!==scope.tenant_id)
  ||[x.company_id,x.companyId].some(v=>v!==undefined&&v!==scope.company_id)
  ||[x.financial_quote_id,x.financialQuoteId].some(v=>v!==undefined&&v!==evidence.id)))return{ok:false,reason:'financial_identity_conflict'};
 const claim=await store.storage.get('acceptance:'+evidence.id);
 if(!claim||claim.booking_id!==bookingId||claim.state==='closed')return{ok:false,reason:'financial_identity_conflict'};
 const payment=await state.storage.get(`initial-booking-payment:${bookingId}`);
 const modes=containers.flatMap(x=>[x.payment_mode,x.paymentMode]).filter(x=>x!==undefined);
 const methods=containers.flatMap(x=>[x.payment_method,x.paymentMethod]).filter(x=>x!==undefined);
 if(!modes.length)modes.push(...methods);
 const statuses=containers.flatMap(x=>[x.payment_status,x.paymentStatus]).filter(x=>x!==undefined);
 const present=x=>x!==undefined&&x!==null&&x!=='';
 const providers=containers.flatMap(x=>[x.payment_provider,x.paymentProvider]).filter(present);
 const mode=modes[0],status=statuses[0];
 if(modes.some(x=>x!==mode)||statuses.some(x=>x!==status)||methods.some(x=>x!==methods[0])
  ||providers.some(x=>x!==providers[0]))return{ok:false,reason:'payment_unresolved'};
 const providerIds=containers.flatMap(x=>[x.mollie_payment_id,x.molliePaymentId,x.provider_payment_id,x.providerPaymentId,x.payment_id,x.paymentId,x.mollie?.id,x.mollie?.payment_id]).filter(present);
 if(providerIds.some(id=>typeof id!=='string'||!/^tr_[A-Za-z0-9_-]{1,125}$/.test(id)))return{ok:false,reason:'payment_unresolved'};
 // The writer uses manual + the selected method for cash, in-vehicle card and
 // invoice. Resolving this intent does not mark an unpaid booking as paid.
 // Preserve the older explicit cash/invoice modes, but never infer a manual
 // outcome from a mode alone when the selected method or provider disagrees.
 const manualMode=['manual','in_vehicle'].includes(mode)
  ?methods.length>0&&['cash','in_vehicle_card','invoice'].includes(methods[0])
  :mode==='cash'?(!methods.length||methods[0]==='cash')
  :['invoice','business_invoice','on_account','pay_later'].includes(mode)&&(!methods.length||methods[0]==='invoice'||methods[0]===mode);
 const checkoutMarkers=containers.flatMap(x=>[x.payment_booking_id,x.paymentBookingId,x.checkout_url,x.checkoutUrl,x.payment_url,x.paymentUrl,x.mollie?.checkout_url,x.mollie?.checkoutUrl,x.mollie?._links?.checkout?.href]).filter(present);
 const checkoutRequired=containers.some(x=>[x.requiresPayment,x.requires_payment,x.payment_required].some(v=>v!==undefined&&v!==false));
 const noProvider=!payment&&!providerIds.length&&!checkoutMarkers.length&&!checkoutRequired
  &&providers.every(x=>x==='manual')&&['unpaid','paid'].includes(status)&&manualMode;
 // A stale/contradictory paid presentation must not erase a request whose
 // provider result is still unknown. Use the existing recorded response and
 // canonical provider identity; never query or invent a payment outcome.
 const response=payment?.response;
 let paid=false;
 if(status==='paid'&&providerIds.length>0&&payment?.schema===1&&payment.tenant_id===scope.tenant_id&&payment.company_id===scope.company_id
  &&payment.bookingId===bookingId&&typeof payment.paymentId==='string'&&payment.paymentId
  &&Number.isFinite(payment.request?.at)&&Number.isInteger(response?.status)&&response.status>=200&&response.status<300
  &&/^tr_[A-Za-z0-9_-]{1,125}$/.test(response.body?.id??'')&&providerIds.every(id=>id===response.body.id)){
  const request=payment.request.body,metadata=request?.metadata;
  let url;try{url=new URL(payment.request.url);}catch{}
  const aliases=[metadata, response.body.metadata];
  const money=x=>x?.amount&&typeof x.amount.value==='string'&&/^(0|[1-9][0-9]*)\.[0-9]{2}$/.test(x.amount.value)&&x.amount.currency===evidence.money.currency;
  const bound=x=>x&&x.bookingId===payment.paymentId&&x.tenantId===scope.tenant_id&&x.companyId===scope.company_id
   &&(x.tenant_id===undefined||x.tenant_id===scope.tenant_id)&&(x.company_id===undefined||x.company_id===scope.company_id)
   &&x.initialBookingId===bookingId&&x.initialPaymentIntentId===payment.paymentId;
  if(url?.origin==='https://api.mollie.com'&&url.pathname==='/v2/payments'&&!url.username&&!url.password
   &&metadata&&aliases.every(bound)&&money(request)&&money(response.body)&&(!request.profileId||response.body.profileId===request.profileId)
   &&(!request.method||response.body.method===request.method)&&(!response.body.sequenceType||response.body.sequenceType==='oneoff')
   &&(!response.body.status||['open','pending','authorized','paid'].includes(response.body.status))){
   try{await assertFinancialProviderPayment(record,request);await assertFinancialProviderPayment(record,response.body);paid=true;}catch{/* Contradictory stored money never resolves an owner fence. */}
  }
 }
 if(!noProvider&&!paid)return{ok:false,reason:'payment_unresolved'};
 // Hosted checkout retains its existing operational PENDING stage after paid
 // finalization. Do not change dispatch/lifecycle: require the private, durable
 // confirmed payment projection as well as the bound provider proof above.
 if(record.stage==='PENDING'){
  const projections=containers.flatMap(x=>[x.payment_booking_id,x.paymentBookingId]).filter(x=>x!==undefined);
  if(!paid||!projections.length||projections.some(x=>x!==payment.paymentId))return{ok:false,reason:'canonical_booking_unresolved'};
  const projected=await canonicalBookingOperation(state,env,{operation:'inspect',scope,bookingId:payment.paymentId});
  const shadow=projected.ok&&projected.record;
  if(!shadow||typeof shadow.confirmed_at!=='string'||!Number.isFinite(Date.parse(shadow.confirmed_at))
   ||shadow.public_booking_id!==bookingId||shadow.payload?.__booking_id!==bookingId
   ||shadow.payment_status!=='paid'||shadow.paymentStatus!==undefined&&shadow.paymentStatus!=='paid'
   ||shadow.payload?.financial_quote_id!==evidence.id||shadow.mollie?.id!==response.body.id)return{ok:false,reason:'canonical_booking_unresolved'};
  const projectedContainers=[shadow,shadow.booking,shadow.payload].filter(x=>x&&typeof x==='object');
  if(projectedContainers.flatMap(x=>[x.customer_id,x.customerId]).filter(x=>x!==undefined).some(x=>x!==owner)
   ||projectedContainers.flatMap(x=>[x.payment_id,x.paymentId,x.mollie?.id,x.mollie?.payment_id]).filter(x=>x!==undefined&&x!==null).some(x=>x!==response.body.id))return{ok:false,reason:'financial_identity_conflict'};
  try{const projectedEvidence=await verifyBookingFinancialEvidence(shadow);if(projectedEvidence?.id!==evidence.id)return{ok:false,reason:'financial_identity_conflict'};}catch{return{ok:false,reason:'financial_identity_conflict'};}
 }
 const resolution={booking_id:bookingId,financial_quote_id:evidence.id,stage:'BOOKED',canonical_stage:record.stage,canonical_version:record._canonical_version??null,payment_resolved:true,payment_basis:noProvider?'no_provider':'canonical_paid'};
 const next={...claim,state:'resolved',revision:(claim.revision??0)+1,resolution};
 if(claim.state==='resolved')return{ok:true,already:true,booking_id:bookingId,payment_basis:resolution.payment_basis};
 const changed=await store.storage.compareAndSet('acceptance:'+evidence.id,claim,next);
 return changed?{ok:true,booking_id:bookingId,payment_basis:resolution.payment_basis}:{ok:false,reason:'financial_resolution_changed'};
}
export async function resolveCompletedFinancialResultV1(state,env,scope,result,input){
 if(!result?.ok)return;
 try{
  const store=financialEvidenceStore(env,scope);if(!store||!await store.storage.hasCloseFence())return;
  const id=input?.body?.financial_quote_id??input?.stored?.financial_quote_id??input?.stored?.payload?.financial_quote_id;
  const claim=id?await store.storage.get('acceptance:'+id):null;
  const bookingId=claim?.booking_id??result.canonicalBookingId??result.booking_id??result.bookingId;
  if(bookingId)await resolveCanonicalFinancialIntentV1({state,env,scope,bookingId});
 }catch{/* An uncertain resolution keeps the durable owner fence; never unlock. */}
}
