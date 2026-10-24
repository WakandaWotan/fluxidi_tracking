import { subscriptionPlanAccess } from './subscription_plan_access.mjs';
import { normalizeAccountState } from './company_account_lifecycle.mjs';
import { isScopedInternalDevSubscriptionExempt } from './internal_dev_subscription_exemption.mjs';

const PLANS = new Set(['free', 'standard', 'smart']);
export const COMPANY_SUBSCRIPTION_OPERATIONS = Object.freeze([
  'receive_request', 'view_requests', 'view_history', 'view_profile',
  'accept_request', 'start_street_hail', 'create_company_booking',
  'start_booked_trip', 'assign_driver', 'respond_quote', 'edit_booking',
  'manage_fleet', 'automatic_dispatch', 'customer_live_tracking', 'traffic_eta',
  'finish_existing_trip', 'cancel_existing_trip',
]);
const FINISH = new Set(['finish_existing_trip', 'cancel_existing_trip']);
const text = value => typeof value === 'string' ? value.trim() : '';
const date = value => Number.isFinite(Date.parse(value)) ? new Date(value).toISOString() : null;

// Called with canonical server records, never browser-supplied entitlements.
// Legacy plans remain distinguishable and are not silently repriced/migrated.
export function companySubscriptionFacts({ profile = {}, account = {}, override = null, internalDevExemption = null, scope = {}, now = Date.now() } = {}) {
  if (!Number.isFinite(now)) throw new Error('subscription_clock_invalid');
  const state = normalizeAccountState(account.state ?? account.account_state);
  const plan = text(profile.plan_code ?? profile.plan).toLowerCase();
  const knownPlan = PLANS.has(plan);
  const internalDev = isScopedInternalDevSubscriptionExempt(internalDevExemption, scope);
  const voluntary = profile.trial_activation === 'voluntary';
  const firstUse = profile.trial_activation === 'first_use';
  const originalEnd = date(profile.trial_ends_at);
  const sameScope = !!scope.tenant_id && !!scope.company_id
    && override?.tenant_id === scope.tenant_id && override?.company_id === scope.company_id;
  const overrideEnd = sameScope && text(override.actor_id) && text(override.reason)
    ? date(override.trial_ends_at) : null;
  const extendsTrial = !!originalEnd && !!overrideEnd && Date.parse(overrideEnd) > Date.parse(originalEnd);
  const trialProfile = internalDev ? { plan_code: 'smart', subscription_status: 'active' } : !voluntary && !firstUse && ['trialing', 'trial', 'trial_active'].includes(text(profile.subscription_status ?? profile.status).toLowerCase())
    ? { ...profile, subscription_status: 'payment_required' } : profile;
  const decisions = Object.fromEntries(COMPANY_SUBSCRIPTION_OPERATIONS.map(operation => {
    const commercial = subscriptionPlanAccess(trialProfile, {
      now, operation, trialOverrideEndsAt: extendsTrial ? overrideEnd : null,
    });
    if (!FINISH.has(operation) && state !== 'active') return [operation, {
      allowed: false, reason: state === 'unknown' ? 'company_status_unknown' : `company_${state}`,
    }];
    if (!knownPlan && !internalDev && !FINISH.has(operation)) return [operation, { allowed: null, reason: 'legacy_plan_requires_migration' }];
    return [operation, { allowed: commercial.ok, reason: commercial.ok ? null : commercial.error }];
  }));
  const access = subscriptionPlanAccess(trialProfile, {now, trialOverrideEndsAt: extendsTrial ? overrideEnd : null});
  return {
    schema_version: 'company_subscription_facts_v1', evaluated_at: new Date(now).toISOString(),
    stored_plan: plan || null, legacy_plan: knownPlan ? null : plan || null,
    effective_plan: internalDev ? 'smart' : knownPlan ? access.effective_plan : null,
    ...(internalDev ? {internal_dev_account: true, entitlement_no_expiry: true, unlimited_vehicles: true, unlimited_drivers: true} : {}),
    account_state: state, subscription_status: text(profile.subscription_status ?? profile.status) || null,
    trial_activation: profile.trial_activation === 'first_use' ? 'first_use' : voluntary ? 'voluntary' : null,
    trial_usage_mode: ['controlled_test','operational'].includes(profile.trial_usage_mode) ? profile.trial_usage_mode : null,
    trial_operational_from_at: date(profile.trial_operational_from_at),
    trial_started_at: date(profile.trial_started_at), trial_ends_at: originalEnd,
    effective_trial_ends_at: extendsTrial ? overrideEnd : originalEnd,
    trial_active: !internalDev && knownPlan && access.trial,
    trial_pending: !internalDev && knownPlan && plan === 'smart' && firstUse
      && access.effective_plan === 'smart' && !access.trial && !date(profile.trial_started_at),
    trial_override: { applicable: extendsTrial, updated_at: sameScope ? date(override?.updated_at) : null },
    white_label: typeof profile.white_label === 'boolean' ? profile.white_label : null,
    source_revision: profile.source_revision ?? null, operations: decisions,
  };
}
