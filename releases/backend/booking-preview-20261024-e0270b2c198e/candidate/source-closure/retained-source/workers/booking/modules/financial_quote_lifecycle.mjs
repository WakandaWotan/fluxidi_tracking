import {createFinancialQuoteEvidence, verifyFinancialQuoteEvidence, FinancialRouteEvidenceStore} from './financial_route_evidence.mjs';
import {D1FinancialRouteEvidenceStorage} from './financial_route_evidence_d1.mjs';
import {projectFinancialSaleMoneyV2,assertFinancialSaleBookBodyV2} from './financial_sale_projection_v2.mjs';
import {reserveStagingTrialForEnvV1} from './staging_trial_budget_v1.mjs';
import {assertFinancialBatchWriteBudgetV1} from './financial_route_batch_v1.mjs';

// No KV emulation: accepting a quote needs an atomic durable insert.
export function financialEvidenceStore(env,scope) {
  if (scope && !String(env?.FINANCIAL_EVIDENCE_COMPANIES ?? "").split(",").map(v=>v.trim()).includes(`${scope.tenant_id}/${scope.company_id}`)) return null;
  return env?.FINANCIAL_EVIDENCE_DB
    ? new FinancialRouteEvidenceStore(new D1FinancialRouteEvidenceStorage(env.FINANCIAL_EVIDENCE_DB)) : null;
}
const text = v => String(v ?? '').trim();
export function financialQuoteInputs(body) {
  const first = (...keys) => keys.map(k=>body[k]).find(v=>v!=null);
  const point = prefix => {
    const names=prefix==='from' ? ['from','pickup'] : ['to','dropoff','destination'];
    const coordinate=axis=>{
      const values=names.flatMap(name=>[`${name}_${axis}`,`${name}${axis[0].toUpperCase()}${axis.slice(1)}`,
        ...(axis==='lng' ? [`${name}_lon`] : [])]).map(k=>body[k]).filter(v=>v!=null && v!=='').map(Number);
      if(values.some(v=>!Number.isFinite(v)) || values.some(v=>Math.abs(v-values[0])>1e-7)) throw new Error('financial_coordinate_alias_conflict');
      return values[0] ?? null;
    };
    return {lat:coordinate('lat'),lng:coordinate('lng')};
  };
  const ret = body.return_enabled === true || body.roundtrip === true;
  return {
    financial_inputs_version:2,
    ...(body.financial_context?.schema==='fluxidi-vehicle-financial-context-v1' ? {
      financial_context:structuredClone(body.financial_context),
      official_inputs:Object.fromEntries(['pickup_input','destination_input','return_pickup_input','return_destination_input']
        .filter(k=>body[k]!=null).map(k=>[k,structuredClone(body[k])])),
    } : {}),
    // Track optional legacy/commercial inputs as well as the canonical fields.
    // A caller adding an alternate price-determining input must requote.
    pricing_options:Object.fromEntries(Object.entries(body).filter(([key]) =>
      /^(booking_mode|stop_?\d+|return_(pickup_iso|pickup_mode|wait_min|wait_minutes|service|service_category)|pickup_(iso|mode)|service_category|extra_service|extra_service_key|requested_duration_minutes|duration_hours|hours|round_trip|returnEnabled|airport_(code|name|postal_code)|billing_customer)$/.test(key))),
    from:text(body.from),to:text(body.to),date:text(body.date),time:text(body.time),
    from_point:point('from'),to_point:point('to'),
    service:text(body.service || 'passenger'),tier:text(body.tier || 'comfort'),
    pax:Number(body.pax || 1),bags:Number(body.bags || 0),
    stops:first('stop_points','stops_addresses','stop_addresses','stops','waypoints') || [],
    // Known stop coordinates now determine the route. Changing their binding
    // must requote; absent/empty arrays have the same v2 input identity.
    ...(body.stop_coordinates?.length ? {stop_coordinates:body.stop_coordinates} : {}),
    wait_min:Number(first('wait_min','wait_minutes','waiting_min','wait') || 0),
    vehicle:text(first('required_vehicle_id','requiredVehicleId','preferred_vehicle_id','preferredVehicleId','vehicle_id','vehicleId')),
    driver:text(first('driver_id','driverId')),category:text(first('vehicle_category','vehicleCategory')),
    airport_iata:text(first('airport_iata','airportIata','airport_id','airportId')),
    airport_direction:text(first('airport_direction','airportDirection')),
    postcode:text(first('pickup_postcode','pickupPostcode','from_postcode','postcode')),
    return_enabled:ret,
    return:ret ? {from:text(first('return_from','returnFrom') || body.to),to:text(first('return_to','returnTo') || body.from),
      date:text(first('return_date','returnDate')),time:text(first('return_time','returnTime')),
      from_point:{lat:first('return_from_lat','returnFromLat','return_pickup_lat') ?? null,lng:first('return_from_lng','returnFromLng','return_pickup_lng') ?? null},
      to_point:{lat:first('return_to_lat','returnToLat','return_dropoff_lat') ?? null,lng:first('return_to_lng','returnToLng','return_dropoff_lng') ?? null},
      stops:first('return_stop_points','return_stops','returnStops') || [],kind:text(first('return_kind','returnKind')),
      ...(body.return_stop_coordinates?.length ? {stop_coordinates:body.return_stop_coordinates} : {}),
      vehicle:text(first('return_vehicle_id','preferred_return_vehicle_id','returnVehicleId'))} : null,
    billing_mode:['business_invoice','invoice','on_account','pay_later'].includes(text(body.business?.billing_mode ?? first('billing_mode','payment_mode')).toLowerCase()) ? 'business_invoice' : 'immediate',
    vat_number:text(body.business?.vat_number ?? body.vat_number),
    invoice_requested:body.business?.invoice_requested === true || body.invoice_requested === true,
  };
}
export async function persistFinancialQuote(env,{scope,body,tariff,route,quote,snapshot,now=Date.now(),routeRetention='full'}) {
  const store=financialEvidenceStore(env,scope);
  if (!store) return null; // Deployment gate: no binding has been activated.
  if (quote.request_quote_required || quote.booking_allowed === false || quote.total_price_incl_vat == null) return null;
  // In an explicitly isolated trial, consume a durable slot before creating
  // any new evidence. A failed write still consumes the slot, bounding retries.
  assertFinancialBatchWriteBudgetV1(env);
  await reserveStagingTrialForEnvV1(env,'financial_quote',now);
  const cents=v=>Math.round(Number(v)*100);
  const money={currency:'EUR',net_cents:cents(quote.total_price_ex_vat),vat_cents:cents(quote.total_price_vat),
      gross_cents:cents(quote.total_price_incl_vat),vat_mode:quote.breakdown?.vat_mode ?? quote.pricing_profile?.vat_mode ?? 'incl',
      components:JSON.parse(JSON.stringify({main:quote.breakdown,return:quote.return?.breakdown ?? null})),
      snapshot:JSON.parse(JSON.stringify(snapshot))};
  const record=await createFinancialQuoteEvidence({scope,inputs:financialQuoteInputs(body),tariff,route,
    money:routeRetention==='sale_only'?projectFinancialSaleMoneyV2(money):money,now,expiresAt:now+15*60_000,routeRetention});
  assertFinancialBatchWriteBudgetV1(env);
  await store.saveQuote(record);
  return record;
}
export async function acceptFinancialQuote(env,{scope,body,bookingId,tariff,now=Date.now()}) {
  const store=financialEvidenceStore(env,scope);
  const id=text(body.financial_quote_id);
  if (!id) return null;
  if (!store) throw new Error('financial_evidence_storage_unavailable');
  const inputs=financialQuoteInputs(body);
  const selected=await store.storage.get('quote:'+id);
  if(selected?.version===2)assertFinancialSaleBookBodyV2(body,selected.money);
  let existing;
  try { existing=await store.readAccepted({bookingId,scope,inputs}); }
  catch(e) { if (e.message !== 'booking_evidence_missing') throw e; }
  if (existing) {
    if (existing.evidence.id!==id) throw new Error('booking_evidence_already_frozen');
    return existing.evidence;
  }
  return (await store.accept({quoteId:id,bookingId,scope,inputs,tariff,now})).evidence;
}
export async function verifyBookingFinancialEvidence(record) {
  if(record?._canonical_financial_evidence_ref)throw new Error('booking_evidence_reference_unresolved');
  const copies=[record?.financial_evidence,record?.booking?.financial_evidence].filter(value=>value!=null);
  if (!copies.length) return null;
  const evidence=copies[0];
  const scope={tenant_id:record.tenant_id ?? record.booking?.tenant_id,company_id:record.company_id ?? record.booking?.company_id};
  // An identical claimed ID is not an integrity check. Verify every present
  // copy against its complete content, then require one financial identity.
  for(const copy of copies){
    await verifyFinancialQuoteEvidence(copy,{scope,inputs:copy?.inputs,accepted:true});
    if(copy.id!==evidence.id) throw new Error('booking_financial_evidence_mismatch');
  }
  for(const row of [record,record.booking]){
    if(!row)continue;
    for(const [key,aliases]of Object.entries({tenant_id:['tenant_id','tenantId'],company_id:['company_id','companyId']})){
      if(aliases.some(alias=>row[alias]!=null&&row[alias]!==scope[key])) throw new Error('booking_financial_evidence_mismatch');
    }
    if(['financial_quote_id','financialQuoteId'].some(key=>row[key]!=null&&row[key]!==evidence.id)) throw new Error('booking_financial_evidence_mismatch');
  }
  const expected=evidence.money;
  // These existing fields are euro presentations of the frozen sale, never
  // alternate price authorities. Leg-specific pricing is not a booking total.
  const fields={
    net_cents:['price_ex_vat','priceExVat','total_price_ex_vat','totalPriceExVat','subtotal_ex_vat','subtotalExVat'],
    vat_cents:['price_vat','priceVat','total_price_vat','totalPriceVat','vat_amount','vatAmount'],
    gross_cents:['price_incl_vat','priceInclVat','total_price_incl_vat','totalPriceInclVat','total_incl_vat','totalInclVat'],
  };
  for(const candidate of [record,record.booking,record.quote,record.quote?.pricing]) {
    if (!candidate) continue;
    if(['currency','booking_currency','bookingCurrency'].some(key=>candidate[key]!=null&&candidate[key]!==expected.currency)) throw new Error('booking_financial_evidence_mismatch');
    for(const [part,aliases] of Object.entries(fields))for(const key of aliases){
      if(candidate[key]!=null&&strictFinancialEuroCentsV1(candidate[key])!==expected[part]) throw new Error('booking_financial_evidence_mismatch');
    }
  }
  return evidence;
}

// Only the private canonical envelope uses this compact representation. The
// original accepted evidence remains immutable in its existing D1 record.
export async function compactCanonicalFinancialEvidence(env,record,bookingId) {
  if(record?._canonical_financial_evidence_ref)throw new Error('booking_evidence_reference_unresolved');
  const evidence=await verifyBookingFinancialEvidence(record);
  if(!evidence)return record;
  const scope={tenant_id:record.tenant_id,company_id:record.company_id};
  const store=financialEvidenceStore(env,scope);
  if(!store)throw new Error('financial_evidence_store_required');
  const frozen=await store.readAcceptedReference({bookingId,scope,quoteId:evidence.id});
  if(frozen.id!==evidence.id)throw new Error('booking_financial_evidence_mismatch');
  const copy=structuredClone(record),paths=[];
  if(copy.financial_evidence!=null){delete copy.financial_evidence;paths.push('root');}
  if(copy.booking?.financial_evidence!=null){delete copy.booking.financial_evidence;paths.push('booking');}
  copy._canonical_financial_evidence_ref={schema:1,booking_id:bookingId,quote_id:evidence.id,paths};
  return copy;
}
export async function hydrateCanonicalFinancialEvidence(env,record,bookingId) {
  const ref=record?._canonical_financial_evidence_ref;
  if(!ref)return structuredClone(record);
  if(Object.keys(ref).sort().join(',')!=='booking_id,paths,quote_id,schema'||ref.schema!==1||ref.booking_id!==bookingId
    ||typeof ref.quote_id!=='string'||!Array.isArray(ref.paths)||!ref.paths.length||ref.paths.length>2
    ||new Set(ref.paths).size!==ref.paths.length||ref.paths.some(p=>!['root','booking'].includes(p))
    ||record.financial_evidence!=null||record.booking?.financial_evidence!=null
    ||ref.paths.includes('booking')&&(!record.booking||typeof record.booking!=='object'))throw new Error('booking_evidence_reference_invalid');
  const scope={tenant_id:record.tenant_id,company_id:record.company_id};
  const store=financialEvidenceStore(env,scope);
  if(!store)throw new Error('financial_evidence_store_required');
  const evidence=await store.readAcceptedReference({bookingId,scope,quoteId:ref.quote_id});
  const copy=structuredClone(record);delete copy._canonical_financial_evidence_ref;
  for(const path of ref.paths)(path==='root'?copy:copy.booking).financial_evidence=structuredClone(evidence);
  await verifyBookingFinancialEvidence(copy);
  return copy;
}
function strictFinancialEuroCentsV1(value){
  if(typeof value!=='string'&&(typeof value!=='number'||!Number.isFinite(value)||value<0)) throw new Error('booking_financial_evidence_mismatch');
  const raw=String(value);
  // No coercion, locale parsing, rounding, exponent strings or cent-as-euro
  // conversion. BigInt preserves exact safe cent integers at the upper bound.
  if(raw.length>32||!/^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(raw)) throw new Error('booking_financial_evidence_mismatch');
  const [major,minor='']=raw.split('.');const cents=BigInt(major)*100n+BigInt(minor.padEnd(2,'0'));
  if(cents>BigInt(Number.MAX_SAFE_INTEGER)) throw new Error('booking_financial_evidence_mismatch');
  return Number(cents);
}
export async function assertFinancialBookingInputs(record,body) {
  const evidence=await verifyBookingFinancialEvidence(record);
  if (!evidence) return;
  if (body.financial_quote_id!==evidence.id) throw new Error('booking_requote_required');
  await verifyFinancialQuoteEvidence(evidence,{scope:evidence.scope,inputs:financialQuoteInputs(body),accepted:true});
}

// Selection is company scoped; configuring a name never enables a provider.
// Google/internal adapters require a separate approval and are deliberately absent.
export function selectFinancialRouteProvider(companyPolicy,approvedAdapters) {
  const provider=companyPolicy?.financial_route_provider ?? 'mapbox';
  if (!['mapbox','google','internal'].includes(provider)) throw new Error('financial_route_provider_invalid');
  if (typeof approvedAdapters?.[provider] !== 'function') throw new Error('financial_route_provider_not_approved');
  return {provider,resolve:approvedAdapters[provider]};
}

// Provider status alone cannot settle a frozen sale with a different amount.
export async function assertFinancialProviderPayment(record,payment) {
  const evidence=await verifyBookingFinancialEvidence(record);
  if (!evidence) {
    if (record?.financial_quote_id || record?.payload?.financial_quote_id) throw new Error('booking_evidence_missing');
    return;
  }
  const raw=String(payment?.amount?.value ?? '');
  if (!/^\d+\.\d{2}$/.test(raw)) throw new Error('financial_payment_amount_invalid');
  const [major,minor]=raw.split('.');const cents=Number(major)*100+Number(minor);
  if (!Number.isSafeInteger(cents) || cents!==evidence.money.gross_cents || payment.amount.currency!==evidence.money.currency) {
    throw new Error('financial_payment_amount_mismatch');
  }
}
