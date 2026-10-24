// Server-owned opt-in: airport areas and airport catalog fallbacks do not
// constrain an ordinary taxi priced over the complete depot mission.
import { parseCompanyMissionTariff } from './company_mission_tariff_config.mjs';
import { isTaxiWorkAreaRequest, isAirportWorkAreaRequest } from './taxi_work_area_policy.mjs';
export async function usesCompanyMissionTaxi(env, scope, payload) {
  if (env?.COMPANY_MISSION_PRICING_ENABLED !== '1' || !scope?.tenant_id || !scope?.company_id
    || isAirportWorkAreaRequest(payload) || !isTaxiWorkAreaRequest(payload)) return false;
  const raw = await env.BOOKING_KV.get(`tenant:${scope.tenant_id}:company:${scope.company_id}:business_profile:v1`, { type: 'json' });
  const tariff = (raw?.business_profile ?? raw)?.mission_tariff;
  return tariff?.enabled === true && parseCompanyMissionTariff(tariff).ok;
}
