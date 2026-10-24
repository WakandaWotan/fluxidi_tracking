// Minimal projection inside the existing evidence/store contract. No pricing,
// hashing, payment, routing, table or new ledger. V1 records are never projected.
const clone=v=>structuredClone(v);
const pick=(v,keys)=>Object.fromEntries(keys.filter(k=>v?.[k]!=null).map(k=>[k,clone(v[k])]));
const moneyFields=['price_ex_vat','price_vat','price_incl_vat','total_price_ex_vat','total_price_vat','total_price_incl_vat'];
const breakdownFields=['kind','vat_rate','vat_mode','vehicle_category','local_meter','price_rounding',
  'tariff_amount_cents','minimum_applied','minimum_amount_cents','distance_amount_cents','total_ex','vat_amount','total_incl'];
function price(value){if(value==null)return null;return {...pick(value,[...moneyFields,'pricing_source','fixed_fare_applied','fixed_fare_rule_id','currency']),
  ...(value.breakdown?{breakdown:pick(value.breakdown,breakdownFields)}:{})};}
function fare(value){if(!value)return {matched:false};return {...pick(value,['matched','pricing_source','fixed_fare_applied','fixed_fare_rule_id']),
  ...(value.pricing?{pricing:price(value.pricing)}:{}),
  ...(value.snapshot?{snapshot:pick(value.snapshot,['rule_id','rule_version','fixed_fare_rule_id','currency','total_incl_vat','total_ex_vat','vat_amount','price_incl_vat'])}:{}),
  ...(value.vehicle_pricing?{vehicle_pricing:pick(value.vehicle_pricing,['category','vehicle_ids'])}:{})};}
function mission(value){return value?{...pick(value,['handled','ok','request_quote','reason']),
  ...(value.pricing?{pricing:price(value.pricing)}:{}),
  ...(value.vehicle_pricing?{vehicle_pricing:pick(value.vehicle_pricing,['category','vehicle_ids'])}:{})}:{handled:false};}
export function projectFinancialSaleMoneyV2(money){
  const s=money?.snapshot??{},q=s.quote??{};
  return {...pick(money,['currency','net_cents','vat_cents','gross_cents','vat_mode']),
    components:{main:pick(money?.components?.main,breakdownFields),return:money?.components?.return?pick(money.components.return,breakdownFields):null},
    snapshot:{quote:{...price(q),...pick(q,['ok','pricing_source','pricing_model','fixed_fare_applied','fixed_fare_rule_id']),
      inputs:pick(q.inputs,['vat_rate','vat_mode']),pricing_profile:pick(q.pricing_profile,['return_enabled']),
      ...(q.return?{return:price(q.return)}:{})},
      mainPricing:price(s.mainPricing),returnPricing:price(s.returnPricing),
      mission:mission(s.mission),fixedFare:fare(s.fixedFare),returnPackage:fare(s.returnPackage)}};
}
export const canonicalSaleV2=v=>JSON.stringify(v,(_,x)=>x&&typeof x==='object'&&!Array.isArray(x)?Object.fromEntries(Object.keys(x).sort().map(k=>[k,x[k]])):x);
const fail=r=>{throw Error(r);};
export function assertFinancialSaleMoneyV2(money){
  if(canonicalSaleV2(money)!==canonicalSaleV2(projectFinancialSaleMoneyV2(money)))fail('financial_sale_projection_invalid');
  const q=money.snapshot.quote;
  for(const [key,part]of [['total_price_ex_vat','net_cents'],['total_price_vat','vat_cents'],['total_price_incl_vat','gross_cents']]){
    const v=q[key],n=typeof v==='number'?v:typeof v==='string'&&/^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(v)?Number(v):NaN;
    if(!Number.isFinite(n)||n<0||!Number.isSafeInteger(Math.round(n*100))||Math.abs(n*100-Math.round(n*100))>1e-7||Math.round(n*100)!==money[part])fail('financial_sale_money_conflict');
  }
}

// Optional client route presentations are not quote inputs. Reject these for a
// new V2 /book BEFORE journaling/claiming; never rewrite an existing V1 request.
export const TRANSIENT_PROVIDER_BOOK_FIELDS_V2=Object.freeze(['route_preview','return_route_preview','distance_km','duration_min',
  'route_distance_km','route_duration_min','road_distance_km','route','route_geometry','financial_snapshot','legs','routeOut','returnRoute',
  'mission_distance_km','mission_duration_min','occupied_distance_km','return_distance_km','return_duration_min']);
export function assertFinancialSaleBookBodyV2(body,expectedMoney){
  if(body?.financial_evidence_version!==2)fail('financial_contract_upgrade_required');
  if(TRANSIENT_PROVIDER_BOOK_FIELDS_V2.some(k=>Object.hasOwn(body,k)))fail('financial_transient_route_payload_not_allowed');
  const q=body.quote,keys=['currency','gross_cents','net_cents','vat_cents'];
  if(!q||Object.keys(q).length!==4||Object.keys(q).some(k=>!keys.includes(k))||keys.some(k=>q[k]!==expectedMoney?.[k]))fail('financial_sale_price_consent_changed');
}

// Apply only to NEW sale-only bookings, before their first canonical write.
// Preserve our reservation policy and own addresses/money. This function is
// deliberately not a general update sanitizer: actual GPS/meter trip data and
// historical V1 records must not be removed or rewritten.
export function projectNewSaleBookingV2(record,{serviceMinutes,legServiceMinutes}={}){
  if(record?.financial_evidence?.version!==2)return record;
  if(!Number.isSafeInteger(serviceMinutes)||serviceMinutes<1)fail('booking_reservation_policy_required');
  const routeFields=[...TRANSIENT_PROVIDER_BOOK_FIELDS_V2,'distanceKm','durationMin','duration_route_min','duration_route_seconds','route_duration_seconds',
    'return_distanceKm','return_durationMin','routeOut','returnRoute','waypointNames','financial_route'];
  function strip(value){if(!value||typeof value!=='object')return;for(const key of routeFields)delete value[key];}
  for(const object of [record,record.booking,record.payload,record.quote]){strip(object);strip(object?.return);}
  record.booking??={};record.booking.service_min=serviceMinutes;
  for(const container of [record,record.booking])for(const alias of ['operational_legs','operationalLegs']){
    for(const leg of container[alias]??[]){
      const duration=legServiceMinutes?.get(leg.leg_id??leg.legId);
      if(!Number.isSafeInteger(duration)||duration<1)fail('booking_reservation_policy_required');
      strip(leg);leg.service_min=duration;
    }
  }
  return record;
}
