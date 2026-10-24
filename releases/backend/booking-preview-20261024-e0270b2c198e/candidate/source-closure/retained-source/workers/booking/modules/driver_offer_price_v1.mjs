import {verifyBookingFinancialEvidence} from './financial_quote_lifecycle.mjs';
import {resolveRoundtripDispatchMode} from './company_roundtrip.mjs';
import {missionDispatchPricingConstraint} from './company_mission_dispatch_pricing.mjs';
import {readFinancialDispatchPriceV2,financialDispatchPriceV2} from './financial_dispatch_price_v2.mjs';

// Read-only presentation of an already stored sale. V2 additionally checks the
// existing acceptance authority. No quote/provider calls, writes or repricing.
const own=(o,k)=>o!=null&&Object.hasOwn(o,k)&&o[k]!=null;
const fail=reason=>{throw Error(reason);};
function cents(value){
  if(typeof value==='string'){
    if(!/^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(value))fail('offer_price_invalid');
    const [major,minor='']=value.split('.');
    const result=Number(major)*100+Number(minor.padEnd(2,'0'));
    if(!Number.isSafeInteger(result))fail('offer_price_invalid');
    return result;
  }
  if(typeof value!=='number'||!Number.isFinite(value)||value<0)fail('offer_price_invalid');
  const result=Math.round(value*100);
  if(!Number.isSafeInteger(result)||Math.abs(result/100-value)>1e-9)fail('offer_price_invalid');
  return result;
}
const aliases={gross_cents:['price_incl_vat','priceInclVat'],net_cents:['price_ex_vat','priceExVat'],vat_cents:['price_vat','priceVat']};
function readMoney(rows,required=true){
  const result={};
  for(const [part,keys]of Object.entries(aliases)){
    const values=rows.flatMap(row=>keys.filter(k=>own(row,k)).map(k=>cents(row[k])));
    if(values.some(v=>v!==values[0]))fail('offer_price_conflict');
    result[part]=values[0]??null;
  }
  if(required&&result.gross_cents==null)fail('offer_price_missing');
  if(result.gross_cents!=null&&result.net_cents!=null&&result.vat_cents!=null&&result.net_cents+result.vat_cents!==result.gross_cents)fail('offer_price_vat_conflict');
  return result;
}
function agree(actual,expected){
  for(const part of Object.keys(aliases))if(actual[part]!=null&&expected[part]!=null&&actual[part]!==expected[part])fail('offer_price_conflict');
}
function rowHasMoney(row){return Object.values(aliases).flat().some(k=>own(row,k));}
function explicitCurrency(record,evidence){
  const rows=[record,record.booking,record.quote,record.quote?.pricing,record.quote?.pricing_main,record.quote?.pricing_return,evidence?.money];
  const values=rows.flatMap(row=>['currency','booking_currency','bookingCurrency'].filter(k=>own(row,k)).map(k=>row[k]));
  if(!values.length||values.some(v=>v!=='EUR'))fail('offer_price_currency_unproven');
  return 'EUR';
}
function inScope(record,scope){
  for(const row of [record,record.booking])for(const key of ['tenant_id','company_id']){
    if(own(row,key)&&row[key]!==scope[key])fail('offer_price_scope_mismatch');
  }
  if(!scope?.tenant_id||!scope.company_id||record.tenant_id!==scope.tenant_id||record.company_id!==scope.company_id)fail('offer_price_scope_mismatch');
}
function requirePricedVehicle(record,evidence,scope,vehicleId,legType,priceProof){
  const mission=missionDispatchPricingConstraint(record,scope,priceProof,legType);
  if(!mission.ok||mission.constrained&&!mission.vehicle_ids.includes(vehicleId))fail('offer_price_vehicle_mismatch');
  const inputs=evidence?.inputs;
  const bound=legType==='return'?(inputs?.return?.vehicle||inputs?.vehicle):inputs?.vehicle;
  if(inputs?.financial_context?.schema==='fluxidi-vehicle-financial-context-v1'&&(!bound||bound!==vehicleId))fail('offer_price_vehicle_mismatch');
}

export async function projectDriverOfferPriceV1(record,{env,bookingId,scope,vehicleId,legs}={}){
  try{
    inScope(record,scope);
    if(typeof vehicleId!=='string'||!vehicleId||!Array.isArray(legs)||!legs.length||legs.length>2||new Set(legs).size!==legs.length||legs.some(l=>!['outbound','return'].includes(l)))fail('offer_price_context_invalid');
    const priceProof=await readFinancialDispatchPriceV2(env,scope,record,bookingId);
    const verified=financialDispatchPriceV2(record,scope,priceProof);
    const evidence=verified?.evidence??await verifyBookingFinancialEvidence(record);
    if(record.financial_evidence&&record.booking?.financial_evidence&&record.financial_evidence.id!==record.booking.financial_evidence.id)fail('offer_price_evidence_mismatch');
    if((record.financial_quote_id||record.booking?.financial_quote_id)&&!evidence)fail('offer_price_evidence_missing');
    if(evidence&&[record.financial_quote_id,record.booking?.financial_quote_id].some(id=>id!=null&&id!==evidence.id))fail('offer_price_evidence_mismatch');
    const currency=explicitCurrency(record,evidence);
    const mode=resolveRoundtripDispatchMode(record),split=mode==='split_no_wait';
    const returning=mode!=='single'||record.return_enabled===true||record.booking?.return_enabled===true;
    const legType=split&&legs.length===1?legs[0]:null;
    for(const type of legs)requirePricedVehicle(record,evidence,scope,vehicleId,type,priceProof);
    const canonicalLegs=record.operational_legs??record.booking?.operational_legs??[];
    const pricing=record.quote?.pricing;
    let money,source;
    if(evidence){
      // The shared verifier checks snake_case totals. Presentation must also
      // refuse conflicting camelCase aliases, including partial VAT fields.
      agree(readMoney([record,record.booking,pricing],false),evidence.money);
      for(const [stored,frozen]of [[record.quote?.pricing_main,evidence.money.snapshot?.mainPricing],[record.quote?.pricing_return,evidence.money.snapshot?.returnPricing]]){
        if(stored&&rowHasMoney(stored)){
          if(!frozen)fail('offer_price_leg_unproven');
          agree(readMoney([stored],false),readMoney([frozen]));
        }
      }
      if(legType){
        const frozen=legType==='return'?evidence.money.snapshot?.returnPricing:evidence.money.snapshot?.mainPricing;
        money=readMoney([frozen]);source='immutable_financial_leg';
      }else{money={gross_cents:evidence.money.gross_cents,net_cents:evidence.money.net_cents,vat_cents:evidence.money.vat_cents};source='immutable_financial_booking';}
    }else if(legType){
      const rows=canonicalLegs.filter(l=>l.leg_type===legType);
      if(rows.length!==1)fail('offer_price_leg_unproven');
      money=readMoney([rows[0],legType==='return'?record.quote?.pricing_return:record.quote?.pricing_main]);source='stored_server_leg';
    }else{
      const rows=[record,record.booking,pricing];
      // A single canonical leg can be the stored price authority in older
      // sales. A multi-leg sale needs its stored total; never infer a quote.
      if(!returning&&!rows.some(rowHasMoney)&&canonicalLegs.length===1&&canonicalLegs[0].leg_type==='outbound')rows.push(canonicalLegs[0]);
      money=readMoney(rows);source='stored_server_booking';
    }
    const relevant=legType?canonicalLegs.filter(l=>l.leg_type===legType):canonicalLegs;
    if(relevant.length){
      if(relevant.length>2||new Set(relevant.map(l=>l.leg_type)).size!==relevant.length||relevant.some(l=>!['outbound','return'].includes(l.leg_type)))fail('offer_price_leg_unproven');
      const priced=relevant.filter(rowHasMoney);
      const parts=priced.map(l=>readMoney([l]));
      // Operational legs can carry route/assignment facts without monetary
      // facts. A continuous roundtrip may have only an outbound operational
      // leg. Neither absence makes that leg the complete sale price.
      const complete=legType?priced.length===1:returning?priced.length===2&&priced.some(l=>l.leg_type==='outbound')&&priced.some(l=>l.leg_type==='return'):priced.length===1&&priced[0].leg_type==='outbound';
      if(complete){
        const sum=Object.fromEntries(Object.keys(aliases).map(k=>[k,parts.every(p=>p[k]!=null)?parts.reduce((n,p)=>n+p[k],0):null]));
        agree(sum,money);
      }
    }
    // Preserve the gross/inclusive display contract. VAT input mode is a
    // separate tariff fact, copied only when the server stored it explicitly.
    const tariffVatMode=evidence?.money.vat_mode??record.quote?.inputs?.vat_mode??null;
    return {ok:true,price_incl_vat:money.gross_cents/100,currency,price_money:{schema:'fluxidi-driver-offer-price-v1',...money,currency,presentation:'incl_vat',basis:legType??'booking',source,
      ...(evidence?{financial_quote_id:evidence.id}:{}),...(tariffVatMode?{tariff_vat_mode:tariffVatMode}:{})}};
  }catch(error){return {ok:false,price_incl_vat:null,reason:error.message};}
}
