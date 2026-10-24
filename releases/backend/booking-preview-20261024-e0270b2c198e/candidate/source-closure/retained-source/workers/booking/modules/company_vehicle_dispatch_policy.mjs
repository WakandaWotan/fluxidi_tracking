import { parseCompanyOperatingPolicy } from './company_operating_policy.mjs';
import { asapSearchState } from './asap_dispatch_timing.mjs';
import { resolveRoundtripDispatchMode } from './company_roundtrip.mjs';
import { missionDispatchPricingConstraint, previewMissionDispatchPricingConstraint } from './company_mission_dispatch_pricing.mjs';
import {readFinancialDispatchPriceV2, financialDispatchPriceV2, hasDispatchFinancialEvidenceV2} from './financial_dispatch_price_v2.mjs';

export function vehicleDispatchPreparation(profile, record, priceProof = null) {
  const verified = financialDispatchPriceV2(record, record, priceProof);
  if (hasDispatchFinancialEvidenceV2(record) && !verified) return {ok:false,error:'verified_dispatch_price_required'};
  return prepare(profile, record, verified?.version === 2 ? verified : null,
    () => missionDispatchPricingConstraint(record,record,priceProof));
}

// Called only by the server's prebooking snapshot closure. Its result cannot
// serve as accepted-sale evidence at any operational consumer.
export function previewVehicleDispatchPreparation(profile,record) {
  return prepare(profile,record,null,()=>previewMissionDispatchPricingConstraint(record));
}

function prepare(profile,record,verified,constraint) {
  const parsed = parseCompanyOperatingPolicy(record.vehicle_operating_policy_snapshot ?? profile?.operating_policy);
  if (!parsed.ok) return parsed;
  const policy = parsed.policy;
  if (record.vehicle_dispatch_review && record.do_not_dispatch === true) return { ok: true,
    mode: 'manager_first', reason: record.vehicle_dispatch_review.reason, policy };
  if (!policy || policy.device_binding !== 'vehicle' || policy.availability_source !== 'manual_duty') return { ok: true, mode: 'existing' };
  const airport = [record, record.booking].some(row => row && (row.service === 'airport'
    || row.service_type === 'airport' || row.booking_type === 'airport_transfer' || row.booking_source === 'airport_module'));
  if (airport || !asapSearchState(record).asap) return policy.scheduled_dispatch === 'manager_first' || airport
    ? { ok: true, mode: 'manager_first', reason: 'scheduled_company_review', policy } : { ok: true, mode: 'existing' };
  if (policy.immediate_dispatch === 'manager_first') return { ok: true, mode: 'manager_first', reason: 'company_manual_dispatch', policy };
  if (!['driver_offer', 'primary_vehicle_first', 'manager_above_threshold'].includes(policy.immediate_dispatch)) return { ok: true, mode: 'existing' };
  if (resolveRoundtripDispatchMode(record) === 'split_no_wait') return { ok: true, mode: 'manager_first', reason: 'split_vehicle_dispatch_review', policy };
  const result = { ok: true, mode: 'human_offer', policy,
    ack_timeout_ms: policy.offer_response_seconds * 1000, response_starts_on_display: true };
  if (!constraint().ok) return { ok: true, mode: 'manager_first',
    reason: 'mission_vehicle_price_review_required', policy };
  if (!['primary_vehicle_first', 'manager_above_threshold'].includes(policy.immediate_dispatch)) return result;
  // Only canonical server pricing sources qualify. A client hint, missing
  // quote or unsupported currency must not silently bypass primary review.
  const price = verified ? verified.cents / 100 : record.price_incl_vat;
  const cents = typeof price === 'number' ? Math.round(price * 100) : NaN;
  if (!(verified || ['route_calc', 'fixed_fare', 'airport_fixed_fare', 'company_mission'].includes(record.pricing_source))
    || record.currency != null && record.currency !== 'EUR' || !Number.isFinite(price) || price < 0
    || !Number.isSafeInteger(cents) || Math.abs(cents / 100 - price) > 1e-7) {
    return { ok: true, mode: 'manager_first', reason: 'verified_dispatch_price_required', policy };
  }
  // Manager review is a company queue decision, never a request for the manager's car.
  if (policy.immediate_dispatch === 'manager_above_threshold') return cents > policy.primary_review_above_cents
    ? { ok: true, mode: 'manager_first', reason: 'company_price_threshold_review', policy }
    : result;
  const attempts = record.vehicle_dispatch_attempts ?? [];
  return { ...result, primary_vehicle_id: attempts.length === 0 && cents > policy.primary_review_above_cents
    ? policy.primary_vehicle_id : null };
}

export async function readVehicleDispatchPreparation(env, scope, record, {bookingId, priceProof} = {}) {
  try {
    priceProof ??= await readFinancialDispatchPriceV2(env, scope, record, bookingId);
  } catch (error) { return {ok:false,error:error.message}; }
  if (env.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1') return { ok: true, mode: 'existing' };
  const raw = record.vehicle_operating_policy_snapshot ? null
    : await env.BOOKING_KV.get(`tenant:${scope.tenant_id}:company:${scope.company_id}:business_profile:v1`, { type: 'json' });
  return vehicleDispatchPreparation(raw?.business_profile ?? raw, record, priceProof);
}
