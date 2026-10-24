import { parseCompanyOperatingPolicy } from './company_operating_policy.mjs';

// The rollout flag permits the feature; the server-owned company profile opts in.
// Load only the authenticated scope, and reuse the result during one allocation.
export async function usesCompanyVehicleDuty(env, scope, context, loadProfile) {
  if (env.COMPANY_VEHICLE_OPERATIONS_ENABLED !== '1' || !scope?.hasScope) return false;
  const key = JSON.stringify([scope.tenant_id, scope.company_id]);
  if (!scope.tenant_id || !scope.company_id) return false;
  if (context.vehicleDutyProfileScope !== key) {
    context.vehicleDutyProfile = await loadProfile(env, scope, { allowTenantLegacyFallback: false });
    context.vehicleDutyProfileScope = key;
  }
  const parsed = parseCompanyOperatingPolicy(context.vehicleDutyProfile?.operating_policy);
  if (!parsed.ok) throw new Error(parsed.error);
  return parsed.policy?.device_binding === 'vehicle'
    && parsed.policy?.availability_source === 'manual_duty';
}
