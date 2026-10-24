import {financialEvidenceStore, hydrateCanonicalFinancialEvidence, verifyBookingFinancialEvidence} from './financial_quote_lifecycle.mjs';
import {resolveRoundtripDispatchMode} from './company_roundtrip.mjs';

// Request-local authority, never serialized into a booking or supplied by a client.
const proofs = new WeakMap();
const fail = reason => { throw Error(reason); };
const identity = record => JSON.stringify([record?.tenant_id,record?.company_id,record?.booking_id,record?.bookingId,
  record?.customer_requested_vehicle_id,record?.customer_requested_return_vehicle_id,record?._reliable_leg_type,
  record?.financial_quote_id,record?.financial_evidence,record?._canonical_financial_evidence_ref,
  record?.booking,record?.quote,record?.price_incl_vat,record?.currency,record?.pricing_source,record?.mission_vehicle_pricing_snapshot]);
export const hasDispatchFinancialEvidenceV2 = record => {
  if (record?._canonical_financial_evidence_ref != null) return true;
  const copies = [record?.financial_evidence,record?.booking?.financial_evidence].filter(v=>v!=null);
  if (copies.length && copies.every(v=>v.version===1)) return false;
  return copies.length>0 || !!(record?.financial_quote_id || record?.booking?.financial_quote_id);
};
const sources = ['route_calc','fixed_fare','airport_fixed_fare','company_fixed_price','company_mission'];
function cents(value) {
  if (typeof value !== 'number' && !(typeof value === 'string' && /^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(value))) fail('dispatch_financial_money_invalid');
  const n = Number(value), c = Math.round(n * 100);
  if (!Number.isFinite(n) || n < 0 || !Number.isSafeInteger(c) || Math.abs(c / 100 - n) > 1e-9) fail('dispatch_financial_money_invalid');
  return c;
}
function money(row) {
  const result = Object.fromEntries([['gross_cents','price_incl_vat'],['net_cents','price_ex_vat'],['vat_cents','price_vat']].map(([part,key]) => [part,cents(row?.[key])]));
  if (result.net_cents + result.vat_cents !== result.gross_cents) fail('dispatch_financial_vat_conflict');
  return result;
}
function project(evidence, leg) {
  if (!['outbound','return'].includes(leg)) fail('dispatch_financial_leg_unproven');
  const snapshot = evidence.money.snapshot, returning = evidence.inputs.return_enabled === true;
  const vehicleId = leg === 'return' ? evidence.inputs.return?.vehicle || evidence.inputs.vehicle : evidence.inputs.vehicle;
  if (typeof vehicleId !== 'string' || !vehicleId || leg === 'return' && !returning) fail('dispatch_financial_vehicle_required');
  const frozen = leg === 'return' ? snapshot.returnPricing : snapshot.mainPricing;
  const amount = frozen ? money(frozen) : !returning && leg === 'outbound' ? evidence.money : fail('dispatch_financial_leg_unproven');
  const fixed = leg === 'outbound' && snapshot.fixedFare?.matched === true ? snapshot.fixedFare : null;
  if (fixed?.pricing) {
    const fixedMoney = money(fixed.pricing);
    for (const part of ['gross_cents','net_cents','vat_cents']) if (fixedMoney[part] !== amount[part]) fail('dispatch_financial_leg_conflict');
  }
  const source = frozen?.pricing_source ?? (leg === 'return' ? snapshot.quote?.return?.pricing_source : fixed?.pricing_source) ?? snapshot.quote?.pricing_source;
  if (!sources.includes(source)) fail('verified_dispatch_price_required');
  if (returning) {
    const main = money(snapshot.mainPricing), ret = money(snapshot.returnPricing);
    for (const part of ['gross_cents','net_cents','vat_cents']) if (main[part] + ret[part] !== evidence.money[part]) fail('dispatch_financial_leg_conflict');
  }
  return {vehicleId, source, cents:amount.gross_cents, currency:evidence.money.currency, money:{...amount}, leg};
}

export async function readFinancialDispatchPriceV2(env, scope, record, bookingId) {
  if (!hasDispatchFinancialEvidenceV2(record)) return null;
  if (typeof bookingId !== 'string' || !bookingId || bookingId.startsWith('RC-')) fail('dispatch_canonical_booking_id_required');
  if (!scope?.tenant_id || !scope.company_id || record?.tenant_id !== scope.tenant_id || record?.company_id !== scope.company_id) fail('dispatch_financial_scope_mismatch');
  for (const row of [record,record.booking]) for (const key of ['booking_id','bookingId']) if (row?.[key] != null && row[key] !== bookingId) fail('dispatch_financial_booking_mismatch');
  const hydrated = await hydrateCanonicalFinancialEvidence(env,record,bookingId);
  const evidence = await verifyBookingFinancialEvidence(hydrated);
  if (!evidence) fail('booking_financial_evidence_missing');
  if (evidence.version === 1) {
    const token = Object.freeze({}); proofs.set(token,{identity:identity(record),scope:{...scope},bookingId,evidence}); return token;
  }
  const store = financialEvidenceStore(env,scope);
  if (!store) fail('financial_evidence_store_required');
  const accepted = await store.readAcceptedReference({bookingId,scope,quoteId:evidence.id,enforceHold:true});
  // Both complete contents were verified against their canonical digest. Key
  // order in a JSON projection must not change a frozen sale's identity.
  if (accepted.id !== evidence.id) fail('booking_financial_evidence_mismatch');
  if (accepted.money.currency !== 'EUR') fail('dispatch_financial_currency_invalid');
  const leg = record._reliable_leg_type === 'return' ? 'return' : 'outbound';
  const selected = project(accepted,leg);
  if (record.customer_requested_vehicle_id && record.customer_requested_vehicle_id !== selected.vehicleId) fail('dispatch_financial_vehicle_mismatch');
  if (!record._reliable_leg_type && record.customer_requested_return_vehicle_id
    && record.customer_requested_return_vehicle_id !== project(accepted,'return').vehicleId) fail('dispatch_financial_vehicle_mismatch');
  for (const row of [record,record.booking]) if (row?.pricing_source != null && row.pricing_source !== accepted.money.snapshot.quote?.pricing_source) fail('dispatch_financial_source_mismatch');
  const token = Object.freeze({});
  proofs.set(token,{identity:identity(record),scope:{tenant_id:scope.tenant_id,company_id:scope.company_id},bookingId,evidence:accepted,leg});
  return token;
}

export function financialDispatchPriceV2(record, scope, token, leg) {
  const proof = token && proofs.get(token);
  if (!proof || proof.identity !== identity(record) || proof.scope.tenant_id !== scope?.tenant_id || proof.scope.company_id !== scope?.company_id) return null;
  if (proof.evidence.version === 1) return {version:1,evidence:structuredClone(proof.evidence)};
  try {
  const projected = project(proof.evidence,leg ?? proof.leg);
  // A continuous roundtrip is one resource/offer and keeps the complete sale.
  // Split legs use their own frozen component, never the other leg's price.
  if (leg == null && !record._reliable_leg_type && proof.evidence.inputs.return_enabled === true
    && resolveRoundtripDispatchMode(record) !== 'split_no_wait') {
    if (project(proof.evidence,'return').vehicleId !== projected.vehicleId) fail('dispatch_financial_vehicle_mismatch');
    projected.cents = proof.evidence.money.gross_cents;
    projected.money = {gross_cents:proof.evidence.money.gross_cents,net_cents:proof.evidence.money.net_cents,vat_cents:proof.evidence.money.vat_cents};
    const source = proof.evidence.money.snapshot.quote.pricing_source;
    if (![...sources,'mixed_fixed_price'].includes(source)) fail('verified_dispatch_price_required');
    projected.source = source;
  }
  return {version:2,bookingId:proof.bookingId,evidence:structuredClone(proof.evidence),...projected};
  } catch { return null; }
}
