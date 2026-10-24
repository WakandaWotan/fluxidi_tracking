import {createFinancialRouteBatchV1} from './financial_route_batch_v1.mjs';
import {financialEvidenceStore,financialQuoteInputs} from './financial_quote_lifecycle.mjs';
import {verifyFinancialQuoteEvidence} from './financial_route_evidence.mjs';
import {assertFinancialSaleBookBodyV2} from './financial_sale_projection_v2.mjs';
import {parseCompanyMissionTariff} from './company_mission_tariff_config.mjs';
import {operationalOfficialAddressIndexV1} from './official_address_index_binding_v1.mjs';
import {createOfficialAddressAuthorityV1} from './official_address_routing_v1.mjs';
import {officialAddressReferenceV1,officialAddressPositionUsableV1} from './official_address_reference_v1.mjs';
export const VEHICLE_FINANCIAL_CONTEXT_V1='fluxidi-vehicle-financial-context-v1';
const fields=['required_vehicle_id','requiredVehicleId','preferred_vehicle_id','preferredVehicleId','vehicle_id','vehicleId'];
const id=v=>typeof v==='string'&&/^[A-Za-z0-9_-]{1,128}$/.test(v);
const finite=v=>typeof v==='number'&&Number.isFinite(v)&&v>=0;
const clone=v=>structuredClone(v);
const canonical=v=>JSON.stringify(v,(_,o)=>o&&typeof o==='object'&&!Array.isArray(o)?Object.fromEntries(Object.keys(o).sort().map(k=>[k,o[k]])):o);
const fail=(error,status=400)=>({status,out:{ok:false,error}});
const gates=new WeakMap();
// One HTTP batch only. Cache completed tariff reads, never sessions, fleet,
// presence, financial evidence or an in-flight Promise. The post-quote
// loadConfiguration below deliberately continues to use the original env.
export function vehicleQuoteTariffReadEnvironmentV1(env,scope){
  const kv=env.BOOKING_KV,prefix=`tenant:${scope.tenant_id}:company:${scope.company_id}:`;
  const keys=new Set(['business_profile:v1','pricing:v1','airport_fixed_fares:v1','fixed_prices:v1'].map(k=>prefix+k));
  const completed=new Map(),generation=new Map();let bytes=0;
  const invalidate=key=>{const old=completed.get(key);if(old){bytes-=old.bytes;completed.delete(key);}};
  const proxy=new Proxy(kv,{get(target,name){
    if(name==='get')return async(key,options)=>{
      const mode=typeof options==='string'?options:options?.type??'text';
      if(!keys.has(key)||!['text','json'].includes(mode))return target.get(key,options);
      const cacheKey=key+'|'+mode,hit=completed.get(cacheKey);
      if(hit)return clone(hit.value);
      const version=generation.get(key)??0;
      const value=await target.get(key,options),size=new TextEncoder().encode(JSON.stringify(value)).byteLength;
      if((generation.get(key)??0)===version&&bytes+size<=262144){invalidate(cacheKey);completed.set(cacheKey,{value:clone(value),bytes:size});bytes+=size;}
      return value;
    };
    if(name==='put'||name==='delete')return async(key,...args)=>{
      if(keys.has(key))generation.set(key,(generation.get(key)??0)+1);
      invalidate(key+'|text');invalidate(key+'|json');return target[name](key,...args);
    };
    const value=Reflect.get(target,name,target);return typeof value==='function'?value.bind(target):value;
  }});
  return {...env,BOOKING_KV:proxy};
}
export function assertVehicleFinancialCurrencyV1(body,currency='EUR'){
  // Mirror all caller-controlled currency seams of the existing quote/book
  // resolver, including nested presentation/payment objects. No FX is implied.
  const values=[body.currency,body.booking_currency,body.bookingCurrency,body.default_currency,body.defaultCurrency,
    body.pricing_profile?.currency,body.pricingProfile?.currency,body.quote?.currency,body.quote?.pricing?.currency,body.payment?.currency];
  if(values.some(v=>v!=null&&v!==''&&(typeof v!=='string'||v.trim().toUpperCase()!==currency)))throw Error('financial_currency_not_supported');
}
export async function readVehicleFinancialBodyV1(request){
  if(!/^application\/json(?:;|$)/i.test(request.headers.get('content-type')??''))throw Error('financial_body_content_type');
  const reader=request.body?.getReader();if(!reader)throw Error('financial_body_required');
  const chunks=[];let size=0;
  try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;
    if(size>32768){await reader.cancel();throw Error('financial_body_limit');}chunks.push(value);}}
  finally{reader.releaseLock();}
  const bytes=new Uint8Array(size);let offset=0;for(const c of chunks){bytes.set(c,offset);offset+=c.length;}
  return JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(bytes));
}
export async function assertVehicleFinancialConsentV1(body,env,scope){
  const consent=body.financial_price_consent;
  if(!consent||Object.keys(consent).some(k=>!['financial_quote_id','currency','gross_cents'].includes(k))||
    consent.financial_quote_id!==body.financial_quote_id||!Number.isSafeInteger(consent.gross_cents)||consent.gross_cents<0)throw Error('financial_price_consent_required');
  const stored=await financialEvidenceStore(env,scope)?.storage.get('quote:'+body.financial_quote_id);
  if(!stored||stored.scope.tenant_id!==scope.tenant_id||stored.scope.company_id!==scope.company_id||
    stored.inputs.financial_context?.customer_id!==body.financial_context?.customer_id)throw Error('financial_quote_owner_mismatch');
  if(consent.currency!==stored.money.currency||consent.gross_cents!==stored.money.gross_cents)throw Error('financial_price_consent_changed');
  // Optional on old bodies; newly issued bindings describe this exact stored
  // evidence. They never replace the existing server scope/owner/price checks.
  if(Object.hasOwn(body,'financial_scope_binding')){
    const b=body.financial_scope_binding;
    if(!b||b.schema!=='fluxidi-financial-scope-binding-v1'||
      b.tenant_id!==stored.scope.tenant_id||b.company_id!==stored.scope.company_id||
      b.financial_quote_id!==stored.id||b.customer_id!==stored.inputs.financial_context.customer_id||
      b.input_hash!==stored.input_hash||b.expires_at!==stored.expires_at||
      typeof b.public_partner_id!=='string'||!b.public_partner_id||b.public_partner_id!==body.public_partner_id||
      ['publicPartnerId','partner_id','partnerId'].some(k=>body[k]!=null&&body[k]!==b.public_partner_id))throw Error('financial_quote_owner_mismatch');
  }
  if(stored.version===2)assertFinancialSaleBookBodyV2(body,stored.money);
  assertVehicleFinancialCurrencyV1(body,stored.money.currency);
}
export async function verifyVehicleFinancialAddressesV1(body,env){
  const inputs=financialQuoteInputs(body);
  if(body.financial_context?.schema===VEHICLE_FINANCIAL_CONTEXT_V1){
    if(fields.some(f=>body[f]!=null&&body[f]!==inputs.vehicle))throw Error('financial_vehicle_alias_conflict');
    if(['return_vehicle_id','preferred_return_vehicle_id','returnVehicleId'].some(f=>body[f]!=null&&body[f]!==inputs.return?.vehicle)&&inputs.return_enabled)throw Error('financial_return_vehicle_alias_conflict');
  }
  if(![inputs.from_point,inputs.to_point].every(p=>Number.isFinite(p.lat)&&Math.abs(p.lat)<=90&&Number.isFinite(p.lng)&&Math.abs(p.lng)<=180))throw Error('financial_route_points_required');
  const checks=[['pickup_input',inputs.from_point],['destination_input',inputs.to_point],
    ['return_pickup_input',inputs.return?.from_point],['return_destination_input',inputs.return?.to_point]];
  const stops=inputs.stops;
  if(!Array.isArray(stops)||stops.length>12||inputs.return?.stops&&!Array.isArray(inputs.return.stops)||inputs.return?.stops?.length>12)throw Error('financial_stop_binding_required');
  if(Array.isArray(stops)&&stops.length){
    if(!Array.isArray(body.stop_coordinates)||body.stop_coordinates.length!==stops.length)throw Error('financial_stop_binding_required');
  }
  for(const field of ['stop_coordinates','return_stop_coordinates'])for(const [i,s]of (body[field]??[]).entries()){
    const labels=field==='stop_coordinates'?stops:inputs.return?.stops??[];
    if(typeof s.address!=='string'||s.address.trim()!==String(labels[i]??'').trim()||s.invalidated===true||s.confirmed===false||s.needs_confirmation===true||
      s.coordinates_valid===false||s.coordinate_valid===false||!Number.isFinite(s.lat)||Math.abs(s.lat)>90||!Number.isFinite(s.lng)||Math.abs(s.lng)>180)throw Error('financial_stop_binding_required');
    checks.push([null,{lat:s.lat,lng:s.lng},s.input]);
  }
  if(inputs.return?.stops?.length&&body.return_stop_coordinates?.length!==inputs.return.stops.length)throw Error('financial_stop_binding_required');
  let index,authority;const records=new Map();
  for(const [field,p,supplied] of checks){
    const ref=officialAddressReferenceV1(supplied??body[field]);if(!ref)continue;
    if(!index){index=await operationalOfficialAddressIndexV1(env);if(!index)throw Error('official_address_index_unavailable');authority=createOfficialAddressAuthorityV1({index,allowUnknownOfficialAssignment:true});}
    if(ref.index_revision!==index.revision)throw Error('official_address_index_changed');
    if(!records.has(ref.id))records.set(ref.id,await authority.resolve(ref.id));const a=records.get(ref.id);
    if(a.source!==ref.source||a.sourceVersion!==ref.source_version)throw Error('official_address_source_changed');
    if(!officialAddressPositionUsableV1(a))throw Error('official_address_position_unusable');
    if(!p||!Number.isFinite(Number(p.lat))||!Number.isFinite(Number(p.lng))||Math.abs(Number(p.lat)-a.point.latitude)>1e-7||Math.abs(Number(p.lng)-a.point.longitude)>1e-7)throw Error('official_address_position_changed');
  }
}
function reserve(kv,actor){
  let g=gates.get(kv);if(!g){g={active:0,actors:new Map()};gates.set(kv,g);}
  const now=Date.now();for(const [k,v] of g.actors)if(v.active===0&&v.probe!=='pending'&&v.until<=now)g.actors.delete(k);
  let a=g.actors.get(actor);if(!a){if(g.actors.size>=512)return null;a={active:0,count:0,until:now+60000,probeUntil:0,probe:'unknown'};g.actors.set(actor,a);}
  if(a.until<=now){a.until=now+60000;a.count=0;}
  if(g.active>=8||a.active>=2||a.count>=12)return null;
  g.active++;a.active++;a.count++;return {actor:a,release:()=>{g.active--;a.active--;}};
}
export function bindVehicleFinancialInputV1(body,vehicleId,customerId){
  const next=clone(body);delete next.vehicle_ids;delete next.financial_quote_id;delete next.financial_context;
  for(const f of fields)next[f]=vehicleId;
  next.financial_context={schema:VEHICLE_FINANCIAL_CONTEXT_V1,customer_id:customerId};
  return next;
}
export function configuredVehicleTariffV1({profile,pricing,body,vehicleId,missionEnabled}){
  if(!pricing||!finite(pricing.vat_rate)||pricing.vat_rate>1||!['incl','excl'].includes(pricing.vat_mode)||pricing.currency!=='EUR')return 'configured_money_policy_required';
  const mission=profile?.mission_tariff;
  if(mission?.enabled===true&&missionEnabled){
    if(!parseCompanyMissionTariff(mission).ok)return 'mission_tariff_invalid';
    if(!Object.values(mission.categories).some(c=>c.vehicle_ids?.includes(vehicleId)))return 'vehicle_tariff_missing';
    return null;
  }
  // This new contract cannot label legacy default values as company settings.
  const required=['base_fare','price_per_km','price_per_minute','minimum_fare','wait_per_minute',
    'bag_fee_each','stop_fee_each','tier_fee_comfort','tier_fee_private','tier_fee_premium',
    'night_surcharge_rate','weekend_surcharge_rate','surcharge_cap_rate','return_fee','fuel_surcharge'];
  if(required.some(k=>!finite(pricing[k]))||typeof pricing.return_enabled!=='boolean')return 'configured_tariff_required';
  return null;
}
export function vehicleFinancialRoutePolicyV1(vehicle){
  const restricted=Object.entries(vehicle).filter(([k,v])=>/route|restriction|height|width|weight|length|access|emission/i.test(k)
    &&v!=null&&v!==false&&v!==''&&(!Array.isArray(v)||v.length));
  return restricted.length ? 'vehicle_financial_route_policy_unproven' : null;
}
export async function vehicleFinancialQuotesV1({request,url,env,body,loadSession,resolvePartner,normalizeSchedule,authorizeCompany,loadConfiguration,quote,verifyAddresses,consumeRate,observePhase,outcomeCapture,handlerStartedMs=Date.now()}){
  const record=(method,...args)=>{try{outcomeCapture?.[method]?.(...args);}catch{}};
  const startedMs=Date.now();
  // Private numeric timing only. An observer must never affect the quote.
  const observe=(stage,values)=>{try{observePhase?.({stage,...values});}catch{}};
  observe('started',{ms_since_handler:Math.max(0,startedMs-handlerStartedMs)});
  const session=await loadSession(request,env);
  if(!session?.customer_id)return fail('unauthorized',401);
  if(!body||typeof body!=='object'||Array.isArray(body)||new TextEncoder().encode(JSON.stringify(body)).length>32768)return fail('invalid_body');
  if(Object.hasOwn(body,'route_presentation_mode'))return fail('route_presentation_mode_invalid');
  if(Object.keys(body).some(k=>k.startsWith('__')))return fail('invalid_body');
  try{assertVehicleFinancialCurrencyV1(body);}catch{return fail('financial_currency_not_supported',422);}
  const ids=body.vehicle_ids;
  if(!Array.isArray(ids)||ids.length<1||ids.length>10||ids.some(v=>!id(v))||new Set(ids).size!==ids.length)return fail('vehicle_quote_limit');
  for(const f of fields)if(body[f]!=null)return fail('batch_vehicle_selection_conflict');
  if(!['passenger','taxi','airport'].includes(body.service ?? 'passenger'))return fail('vehicle_quote_service_not_supported',422);
  if(!['from','to'].every(k=>typeof body[k]==='string'&&body[k].trim()))return fail('ride_input_required');
  const routed=await resolvePartner({url,body,env});
  if(!routed?.ok)return fail(routed?.error ?? 'public_partner_required',routed?.status??400);
  const scope={tenant_id:routed.tenant_id,company_id:routed.company_id,hasScope:true};
  for(const [name,expected] of [['tenant_id',scope.tenant_id],['tenantId',scope.tenant_id],['company_id',scope.company_id],['companyId',scope.company_id]])
    if(body[name]!=null&&body[name]!==expected)return fail('tenant_scope_conflict',403);
  if(!(session.tenant_id==='global'&&session.company_id==='global')&&(session.tenant_id!==scope.tenant_id||session.company_id!==scope.company_id))return fail('forbidden',403);
  record('resolvedScope',scope);record('stage','quote_scope');
  record('providerFlag',!Object.hasOwn(body,'customer_route_provider')?'absent':body.customer_route_provider==='mapbox_v1'?'mapbox_v1':'other_redacted');
  if(!(await authorizeCompany(env,scope))?.ok)return fail('company_unavailable',403);
  if(!financialEvidenceStore(env,scope))return fail('financial_evidence_storage_unavailable',503);
  const reservation=reserve(env.BOOKING_KV,session.customer_id);if(!reservation)return fail('rate_limited',429);
  try{
    // KV permits one write per key/second. Keep only completed probe data;
    // concurrent requests never await another request's KV Promise. A pending
    // or failed probe is a short conservative hold, not a permissive fallback.
    const actor=reservation.actor;
    if(actor.probe!=='pending'&&actor.probeUntil<=Date.now()){
      actor.probe='pending';actor.probeUntil=Date.now()+1100;
      const sequence=actor.probeSequence=(actor.probeSequence??0)+1;
      let result;try{result=await consumeRate(session,env);}
      catch(error){if(actor.probeSequence===sequence){actor.probe='failed';actor.probeUntil=Date.now()+1100;}throw error;}
      if(actor.probeSequence!==sequence)return fail('rate_limited',429);
      actor.probe=result?.limited?'limited':'allowed';actor.probeUntil=Date.now()+1100;
    }
    if(actor.probe!=='allowed')return fail('rate_limited',429);
    const scheduled=normalizeSchedule(body);if(!scheduled?.ok)return fail(scheduled?.error??'ride_schedule_required');
    record('mode',scheduled.schedule.pickup_mode==='asap'?'asap':scheduled.schedule.pickup_mode==='scheduled'?'later':'unknown');
    const input={...clone(body),...scheduled.schedule,tenant_id:scope.tenant_id,tenantId:scope.tenant_id,company_id:scope.company_id,companyId:scope.company_id,
      public_partner_id:routed.partner_id};
    delete input.financial_context;delete input.financial_quote_id;
    const addressStartedMs=Date.now();
    observe('addresses_started',{ms_before_addresses:Math.max(0,addressStartedMs-handlerStartedMs)});
    let addressMs=0,configMs=0;
    const addressCheck=Promise.resolve().then(async()=>{
      try{return await verifyAddresses(input,env);}
      finally{addressMs=Date.now()-addressStartedMs;}
    });
    const configStartedMs=Date.now();
    observe('configuration_started',{ms_before_configuration:Math.max(0,configStartedMs-handlerStartedMs)});
    const configuration=Promise.resolve().then(async()=>{
      try{return await loadConfiguration(env,scope);}
      finally{configMs=Date.now()-configStartedMs;}
    });
    // Both reads are independent after the same authorization and rate gate.
    // Wait for both to settle so no read outlives the reservation; preserve
    // address failure priority and never enter a financial quote on failure.
    const [addressResult,configResult]=await Promise.allSettled([addressCheck,configuration]);
    if(addressResult.status==='rejected')throw addressResult.reason;
    if(configResult.status==='rejected')throw configResult.reason;
    const config=configResult.value,rows=new Array(ids.length),start=Date.now();
    record('stage','quote_rows');record('pricePolicy',config.profile?.operating_policy?.scheduled_dispatch);
    observe('prepared',{ms_before_start:Math.max(0,start-handlerStartedMs),ms_verify_addresses:addressMs,
      ms_initial_configuration:configMs});
    const quoteEnv=vehicleQuoteTariffReadEnvironmentV1(env,scope);
    const batch=createFinancialRouteBatchV1({scope,inputs:financialQuoteInputs(input),deadlineMs:handlerStartedMs+20000});
    let firstQuoteObserved=false;
    const quoteOne=async(index,vehicleId)=>{
      const row={vehicle_id:vehicleId,status:'unavailable'},vehicle=config.vehicles.find(v=>(v.vehicle_id??v.vehicleId??v.id)===vehicleId&&v.is_active!==false);
      if(!vehicle)return {...row,reason:'vehicle_unavailable'};
      if(['tenant_id','tenantId'].some(k=>vehicle[k]!=null&&vehicle[k]!==scope.tenant_id)||
        ['company_id','companyId'].some(k=>vehicle[k]!=null&&vehicle[k]!==scope.company_id)){
        return {...row,reason:'vehicle_unavailable'};
      }
      // Admission budget includes authentication, address verification and the
      // first configuration read. Do not start another financial calculation
      // after that budget; an already-running quote is still awaited safely.
      if(Date.now()-handlerStartedMs>=20000)return {...row,reason:'calculation_budget_exceeded'};
      const tariffError=configuredVehicleTariffV1({profile:config.profile,pricing:config.pricing,body:input,vehicleId,missionEnabled:env.COMPANY_MISSION_PRICING_ENABLED==='1'});
      const policyError=vehicleFinancialRoutePolicyV1(vehicle);
      if(tariffError||policyError)return {...row,status:'quote_required',reason:tariffError??policyError};
      if(config.profile?.mission_tariff?.enabled===true&&env.COMPANY_MISSION_PRICING_ENABLED==='1'&&
        (input.service==='airport'||input.airport_iata||input.airport_id)){
        return {...row,status:'quote_required',reason:'airport_financial_floor_unproven'};
      }
      const payload=bindVehicleFinancialInputV1(input,vehicleId,session.customer_id);
      try{
        const quoteStartedMs=Date.now();
        const firstAttempt=!firstQuoteObserved;
        if(firstAttempt){
          firstQuoteObserved=true;
          observe('first_quote_started',{ms_before_first_quote:Math.max(0,quoteStartedMs-handlerStartedMs)});
        }
        let result;
        let quoteMs=0;
        try{result=await quote({body:payload,env:batch.environment(quoteEnv,vehicle),request,url});}
        finally{
          quoteMs=Date.now()-quoteStartedMs;
          if(firstAttempt)observe('first_quote',{ms_await_quote:quoteMs,...batch.metrics()});
        }
        const out=result?.out;
        record('quoteResult',vehicleId,{http_status:result?.status,request_quote_required:out?.request_quote_required,booking_allowed:out?.booking_allowed,financial_quote_present:typeof out?.financial_quote_id==='string'&&out.financial_quote_id.length>0});
        if(result?.status!==200||!out?.financial_quote_id||out.booking_allowed===false||out.request_quote_required){
          return {...row,status:out?.request_quote_required?'quote_required':'unavailable',reason:out?.error??out?.reason??'financial_quote_unavailable'};
        }
        const evidenceStartedMs=Date.now();
        const evidence=await financialEvidenceStore(env,scope).storage.get('quote:'+out.financial_quote_id);
        const evidenceReadMs=Date.now()-evidenceStartedMs;
        const verifyStartedMs=Date.now();
        await verifyFinancialQuoteEvidence(evidence,{scope,inputs:financialQuoteInputs(payload),tariff:evidence?.tariff,now:Date.now()});
        const evidenceVerifyMs=Date.now()-verifyStartedMs;
        const freshConfigStartedMs=Date.now();
        const current=await loadConfiguration(env,scope);
        observe('quote_subphases',{quote_index:index,ms_await_quote:quoteMs,ms_evidence_read:evidenceReadMs,
          ms_evidence_verify:evidenceVerifyMs,ms_fresh_configuration:Date.now()-freshConfigStartedMs});
        if(canonical(current.profile)!==canonical(config.profile)||canonical(current.pricing)!==canonical(config.pricing)||
          canonical(evidence.tariff.company_policy)!==canonical(config.profile)||
          Object.keys(evidence.tariff.pricing_profile).some(k=>Object.hasOwn(config.pricing,k)&&evidence.tariff.pricing_profile[k]!==config.pricing[k]))throw Error('evidence_tariff_changed');
        const currentVehicle=current.vehicles.find(v=>(v.vehicle_id??v.vehicleId??v.id)===vehicleId&&v.is_active!==false);
        if(!currentVehicle||vehicleFinancialRoutePolicyV1(currentVehicle))throw Error('evidence_tariff_changed');
        const vatRate=out.breakdown?.vat_rate??out.pricing_profile?.vat_rate??config.pricing.vat_rate;
        if(!finite(vatRate)||vatRate>1)throw Error('configured_money_policy_required');
        return {vehicle_id:vehicleId,status:'priced',financial_quote_id:evidence.id,...(evidence.version===2?{financial_evidence_version:2}:{}),
          financial_quote_expires_at:evidence.expires_at,tariff_hash:evidence.tariff_hash,input_hash:evidence.input_hash,
          financial_context:clone(payload.financial_context),
          money:{currency:evidence.money.currency,gross_cents:evidence.money.gross_cents,net_cents:evidence.money.net_cents,
            vat_cents:evidence.money.vat_cents,vat_mode:evidence.money.vat_mode,vat_rate:vatRate},
          conditions:{return_enabled:evidence.inputs.return_enabled,return_vehicle_id:evidence.inputs.return?.vehicle??null,
            scope:'complete_journey',components:clone(evidence.money.components)},
          confirmation:{vehicle_id:vehicleId,financial_quote_id:evidence.id,financial_context:clone(payload.financial_context),
            financial_scope_binding:{schema:'fluxidi-financial-scope-binding-v1',
              tenant_id:evidence.scope.tenant_id,company_id:evidence.scope.company_id,
              public_partner_id:routed.partner_id,customer_id:evidence.inputs.financial_context.customer_id,
              financial_quote_id:evidence.id,input_hash:evidence.input_hash,expires_at:evidence.expires_at},
            ...(evidence.version===2?{financial_evidence_version:2,quote:Object.fromEntries(['currency','gross_cents','net_cents','vat_cents'].map(k=>[k,evidence.money[k]]))}:{}),
            ...clone(scheduled.schedule),
            financial_price_consent:{financial_quote_id:evidence.id,currency:evidence.money.currency,gross_cents:evidence.money.gross_cents}}};
      }catch(error){record('quoteFailure',vehicleId,error);return {...row,reason:['calculation_budget_exceeded','evidence_expired','evidence_integrity_failed','evidence_inputs_changed','evidence_tariff_changed'].includes(error.message)?error.message:'financial_quote_failed'};}
    };
    // Seed a proven request-owned route before overlapping quote calculations.
    // This keeps identical vehicles on one provider route, and preserves a
    // serial fallback when no route can be reused. Each quote still receives
    // its own financial evidence and post-quote configuration check.
    let next=0;
    for(;next<ids.length;next++){
      rows[next]=await quoteOne(next,ids[next]);
      if(batch.metrics().distinct_routes>0){next++;break;}
    }
    for(;next<ids.length;next+=3){
      const group=await Promise.allSettled(ids.slice(next,next+3).map((vehicleId,offset)=>quoteOne(next+offset,vehicleId)));
      for(const [offset,result] of group.entries()){
        if(result.status==='rejected')throw result.reason;
        rows[next+offset]=result.value;
      }
    }
    observe('completed',{ms_server_total:Date.now()-startedMs,ms_after_start:Date.now()-start,
      priced_count:rows.filter(row=>row.status==='priced').length,...batch.metrics()});
    return {status:200,out:{ok:true,schema:'fluxidi-vehicle-financial-quotes-v1',public_partner_id:routed.partner_id,
      availability_claim:false,quotes:rows}};
  }finally{reservation.release();}
}
