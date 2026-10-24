// Server-owned company preferences. No company-specific defaults and no I/O.
// Not connected to runtime routes until persistence and authorization are wired.
export const COMPANY_OPERATING_POLICY_VERSION = 1;
const choices = Object.freeze({
  device_binding: ['existing', 'vehicle'],
  availability_source: ['existing', 'manual_duty'],
  scheduled_dispatch: ['existing', 'manager_first'],
  immediate_dispatch: ['existing', 'manager_first', 'driver_offer', 'primary_vehicle_first', 'manager_above_threshold'],
  unanswered_offer: ['central', 'next_vehicle'],
});

export function parseCompanyOperatingPolicy(value) {
  if (value == null) return { ok: true, policy: null };
  if (typeof value !== 'object' || Array.isArray(value)) return { ok: false, error: 'operating_policy_invalid' };
  const allowed = new Set(['version', ...Object.keys(choices), 'offer_response_seconds', 'primary_vehicle_id', 'primary_review_above_cents']);
  if (Object.keys(value).some(key => !allowed.has(key)) || value.version !== 1) {
    return { ok: false, error: 'operating_policy_invalid' };
  }
  const policy = { version: 1 };
  for (const [key, options] of Object.entries(choices)) {
    if (value[key] !== undefined && !(key === 'unanswered_offer' && value[key] === null) && !options.includes(value[key])) return { ok: false, error: 'operating_policy_invalid', field: key };
    policy[key] = value[key] ?? (key === 'unanswered_offer' ? null : 'existing');
  }
  const timeout = value.offer_response_seconds;
  if (timeout != null && (!Number.isSafeInteger(timeout) || timeout <= 0)) {
    return { ok: false, error: 'operating_policy_invalid', field: 'offer_response_seconds' };
  }
  policy.offer_response_seconds = timeout ?? null;
  if (['driver_offer', 'primary_vehicle_first', 'manager_above_threshold'].includes(policy.immediate_dispatch) && (!policy.unanswered_offer || !policy.offer_response_seconds)) {
    return { ok: false, error: 'offer_policy_incomplete' };
  }
  if (value.primary_vehicle_id != null && (typeof value.primary_vehicle_id !== 'string'
    || !/^[a-zA-Z0-9_.-]{1,96}$/.test(value.primary_vehicle_id))) return { ok: false, error: 'operating_policy_invalid', field: 'primary_vehicle_id' };
  if (value.primary_review_above_cents != null && (!Number.isSafeInteger(value.primary_review_above_cents)
    || value.primary_review_above_cents < 0)) return { ok: false, error: 'operating_policy_invalid', field: 'primary_review_above_cents' };
  if (policy.immediate_dispatch === 'primary_vehicle_first' && (!value.primary_vehicle_id || value.primary_review_above_cents == null)) return { ok: false, error: 'primary_offer_policy_incomplete' };
  if (policy.immediate_dispatch === 'manager_above_threshold' && value.primary_review_above_cents == null) return { ok: false, error: 'manager_review_policy_incomplete' };
  if (value.primary_vehicle_id != null) policy.primary_vehicle_id = value.primary_vehicle_id;
  if (value.primary_review_above_cents != null) policy.primary_review_above_cents = value.primary_review_above_cents;
  return { ok: true, policy: Object.freeze(policy) };
}

// Caller must supply an authenticated scope and a server-loaded profile.
// Client bodies must never be passed as the profile.
export function companyOperatingDecision(profile, scope, { scheduled } = {}) {
  if (!scope?.tenant_id || !scope?.company_id) return { ok: false, error: 'company_scope_required' };
  if (typeof scheduled !== 'boolean') return { ok: false, error: 'booking_timing_required' };
  const parsed = parseCompanyOperatingPolicy(profile?.operating_policy);
  if (!parsed.ok) return parsed;
  const policy = parsed.policy;
  return {
    ok: true,
    tenant_id: scope.tenant_id,
    company_id: scope.company_id,
    mode: policy?.[scheduled ? 'scheduled_dispatch' : 'immediate_dispatch'] ?? 'existing',
    device_binding: policy?.device_binding ?? 'existing',
    availability_source: policy?.availability_source ?? 'existing',
    offer_response_seconds: policy?.offer_response_seconds ?? null,
    unanswered_offer: policy?.unanswered_offer ?? null,
    ...(policy?.primary_vehicle_id ? { primary_vehicle_id: policy.primary_vehicle_id } : {}),
    ...(policy?.primary_review_above_cents != null ? { primary_review_above_cents: policy.primary_review_above_cents } : {}),
  };
}
