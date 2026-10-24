import {financialDispatchPriceV2, hasDispatchFinancialEvidenceV2} from './financial_dispatch_price_v2.mjs';
// Inputs come from server-calculated pricing and server-loaded configuration.
// Never recover these facts from the customer's payload.
// Booking's server-owned monetary helpers serialize exact two-decimal euros.
// Accept that canonical representation; reject coercive/ambiguous inputs.
const cents = value => {
  const numeric = typeof value === 'number' ? value
    : typeof value === 'string' && /^(0|[1-9][0-9]*)(\.[0-9]{1,2})?$/.test(value) ? Number(value) : NaN;
  return Number.isFinite(numeric) && numeric >= 0 && Number.isSafeInteger(Math.round(numeric * 100))
    && Math.abs(Math.round(numeric * 100) / 100 - numeric) < 1e-7 ? Math.round(numeric * 100) : null;
};
const idsValid = ids => Array.isArray(ids) && ids.length > 0 && ids.length <= 1000
  && ids.every(id => typeof id === 'string' && /^[a-zA-Z0-9_.-]{1,128}$/.test(id))
  && new Set(ids).size === ids.length;

export function freezeMissionDispatchPricing(scope, missionQuote, totalPricing) {
  const facts = missionQuote?.vehicle_pricing;
  const amount = cents(totalPricing?.price_incl_vat);
  if (!missionQuote?.ok || !scope?.tenant_id || !scope?.company_id || amount == null
    || !['car', 'minibus'].includes(facts?.category) || !idsValid(facts?.vehicle_ids)) return null;
  return { version: 1, tenant_id: scope.tenant_id, company_id: scope.company_id,
    category: facts.category, vehicle_ids: [...facts.vehicle_ids], price_incl_vat_cents: amount, currency: 'EUR' };
}

export function missionDispatchPricingConstraint(record, scope = record, priceProof = null, leg) {
  if (hasDispatchFinancialEvidenceV2(record)) {
    const verified = financialDispatchPriceV2(record, scope, priceProof, leg);
    if (!verified) return {ok:false,constrained:true,reason:'verified_dispatch_price_required'};
    if (verified.version === 1) return previewMissionDispatchPricingConstraint(record,scope);
    const snapshot = verified.evidence.money.snapshot;
    const mission = verified.leg === 'return' ? snapshot.returnPackage?.vehicle_pricing ? snapshot.returnPackage : null
      : verified.source === 'company_mission' ? snapshot.mission
      : ['airport_fixed_fare','company_fixed_price'].includes(verified.source) && snapshot.fixedFare?.vehicle_pricing ? snapshot.fixedFare : null;
    if (verified.source === 'company_mission' && !mission?.vehicle_pricing) return {ok:false,constrained:true,reason:'mission_vehicle_price_review_required'};
    if (mission && (!idsValid(mission.vehicle_pricing?.vehicle_ids)
      || !mission.vehicle_pricing.vehicle_ids.includes(verified.vehicleId)
      || !['car','minibus'].includes(mission.vehicle_pricing.category))) {
      return {ok:false,constrained:true,reason:'mission_vehicle_price_review_required'};
    }
    return {ok:true,constrained:true,vehicle_ids:[verified.vehicleId],
      ...(mission ? {category:mission.vehicle_pricing.category} : {})};
  }
  return previewMissionDispatchPricingConstraint(record,scope);
}

// Existing prebooking constraint; it never establishes financial acceptance.
export function previewMissionDispatchPricingConstraint(record, scope = record) {
  if (record?.pricing_source !== 'company_mission'
    && !(record?.pricing_source === 'airport_fixed_fare' && record.mission_vehicle_pricing_snapshot)) return { ok: true, constrained: false };
  const snapshot = record.mission_vehicle_pricing_snapshot;
  if (!snapshot || snapshot.version !== 1 || snapshot.tenant_id !== scope?.tenant_id
    || snapshot.company_id !== scope?.company_id || !snapshot.tenant_id || !snapshot.company_id
    || !['car', 'minibus'].includes(snapshot.category) || !idsValid(snapshot.vehicle_ids)
    || snapshot.currency !== 'EUR' || record.currency != null && record.currency !== 'EUR'
    || !Number.isSafeInteger(snapshot.price_incl_vat_cents)
    || cents(record.price_incl_vat) !== snapshot.price_incl_vat_cents) {
    return { ok: false, constrained: true, reason: 'mission_vehicle_price_review_required' };
  }
  return { ok: true, constrained: true, category: snapshot.category, vehicle_ids: [...snapshot.vehicle_ids] };
}

export function vehicleMatchesMissionPricing(vehicle, request) {
  if (request?.allowed_vehicle_ids === undefined) return true;
  return idsValid(request.allowed_vehicle_ids)
    && request.allowed_vehicle_ids.includes(vehicle?.vehicle_id ?? vehicle?.vehicleId);
}
