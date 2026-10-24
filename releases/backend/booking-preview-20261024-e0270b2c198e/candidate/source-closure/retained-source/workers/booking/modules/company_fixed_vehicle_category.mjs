import { usesCompanyMissionTaxi } from './company_mission_scope.mjs';
// Resolve tariff ownership from the company's server configuration, never a
// customer-supplied category, price, or allowlist.
export async function resolveFixedVehicleCategory(env, scope, payload, document) {
  if (!document.rules.some(rule => rule.vehicle_category)) return { ok: true };
  const denied = () => ({ ok: false, reason: 'vehicle_tariff_missing' });
  if (!scope?.tenant_id || !scope.company_id) return denied();
  const prefix = `tenant:${scope.tenant_id}:company:${scope.company_id}:`;
  const raw = await env.BOOKING_KV.get(prefix + 'business_profile:v1', { type: 'json' });
  const tariff = (raw?.business_profile ?? raw)?.mission_tariff;
  if (!tariff?.categories) return denied();
  const dates=[payload.date ?? payload.pickup_date ?? payload.pickup_at];
  if (payload.return_enabled === true) dates.push(payload.return_date ?? payload.return_pickup_at);
  if (dates.some(date=>typeof date==='string' && /^\d{4}-\d{2}-\d{2}/.test(date) &&
      tariff.quote_only_month_days?.includes(date.slice(5,10)))) {
    return {ok:false,reason:'company_tariff_exception_day'};
  }

  const vehicleId = payload.required_vehicle_id ?? payload.requiredVehicleId
    ?? payload.preferred_vehicle_id ?? payload.preferredVehicleId ?? payload.vehicle_id ?? payload.vehicleId;
  const carCapacity=await usesCompanyMissionTaxi(env,scope,payload) ? 4
    : Math.max(0,...document.rules.filter(rule=>rule.vehicle_category==='car').map(rule=>rule.pax_max));
  let category = tariff.default_vehicle_category;
  if (vehicleId) {
    const matches = Object.entries(tariff.categories).filter(([, value]) => value.vehicle_ids?.includes(vehicleId));
    if (matches.length !== 1) return denied();
    category = matches[0][0];
  } else if (Number(payload.pax ?? payload.passengers ?? 1) > carCapacity) {
    category = 'minibus';
  }
  if (!['car', 'minibus'].includes(category) || !tariff.categories[category]?.vehicle_ids?.length) return denied();
  // Capacity comes from the company's categorized airport rules.
  if (category === 'car' && Number(payload.pax ?? 1) > carCapacity) return denied();
  const rawFleet = await env.BOOKING_KV.get(prefix + 'fleet:vehicles:v1', { type: 'json' });
  const values = rawFleet?.vehicles ?? rawFleet?.items ?? rawFleet?.fleet ?? rawFleet;
  const fleet = Array.isArray(values) ? values : Object.values(values ?? {});
  const active = new Set(fleet.filter(row => row?.is_active !== false && row?.isActive !== false)
    .map(row => row.vehicle_id ?? row.vehicleId ?? row.id));
  const ids = tariff.categories[category].vehicle_ids.filter(id => active.has(id));
  if (!ids.length || vehicleId && !ids.includes(vehicleId)) return denied();
  return { ok: true, category, vehicle_ids: ids };
}
