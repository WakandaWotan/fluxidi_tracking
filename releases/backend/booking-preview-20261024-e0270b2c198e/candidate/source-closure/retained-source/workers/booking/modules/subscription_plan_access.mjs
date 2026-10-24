// Commercial access is calculated against the server clock. Receiving an
// enquiry is separate from accepting or operating it; existing trips may end.
const PAID = new Set(['standard', 'smart']);
const VIEW = new Set(['receive_request', 'view_requests', 'view_history', 'view_profile']);
const FINISH = new Set(['finish_existing_trip', 'cancel_existing_trip']);
const SMART = new Set(['automatic_dispatch', 'customer_live_tracking', 'traffic_eta']);
const HANDLING = new Set(['accept_request', 'start_street_hail',
  'create_company_booking', 'start_booked_trip', 'assign_driver',
  'respond_quote', 'edit_booking', 'manage_fleet']);
const MAX_TRIAL_MS = 14 * 86400000;

export function subscriptionPlanAccess(profile = {}, { now = Date.now(), operation = 'view_requests', trialOverrideEndsAt = null } = {}) {
  const plan = String(profile.plan_code ?? profile.plan ?? 'free').trim().toLowerCase();
  const status = String(profile.subscription_status ?? profile.status ?? '').trim().toLowerCase();
  const end = Date.parse(profile.trial_ends_at ?? '');
  const start = Date.parse(profile.trial_started_at ?? '');
  const overrideEnd = Date.parse(trialOverrideEndsAt ?? '');
  const effectiveEnd = Number.isFinite(overrideEnd) && overrideEnd > end ? overrideEnd : end;
  const clockValid = Number.isFinite(now);
  const trial = clockValid && plan === 'smart' && status === 'trialing'
    && Number.isFinite(start) && Number.isFinite(end)
    && start <= now && now < effectiveEnd && end > start && end - start <= MAX_TRIAL_MS;
  const created = Date.parse(profile.created_at ?? '');
  const operationalFrom = Date.parse(profile.trial_operational_from_at ?? '');
  const usageReady = profile.trial_usage_mode === 'controlled_test'
    || profile.trial_usage_mode === 'operational' && Number.isFinite(operationalFrom)
      && operationalFrom >= created && operationalFrom <= now;
  const pending = clockValid && plan === 'smart' && status === 'trial_pending'
    && profile.trial_activation === 'first_use'
    && usageReady && Number.isFinite(created) && created <= now
    && !profile.trial_started_at && !profile.trial_ends_at;
  const periodEndRaw = profile.current_period_end;
  const periodEnd = Date.parse(periodEndRaw ?? '');
  const periodValid = periodEndRaw == null || periodEndRaw === ''
    || (Number.isFinite(periodEnd) && now < periodEnd);
  const paid = clockValid && periodValid && status === 'active' && PAID.has(plan);
  const effectivePlan = trial || pending ? 'smart' : paid ? plan : 'free';
  if (!VIEW.has(operation) && !FINISH.has(operation)
    && !SMART.has(operation) && !HANDLING.has(operation))
    return { ok: false, error: 'subscription_operation_not_supported',
      effective_plan: effectivePlan, trial };
  if (VIEW.has(operation) || FINISH.has(operation)) return { ok: true, effective_plan: effectivePlan, trial };
  if (effectivePlan === 'free') return { ok: false, error: 'paid_subscription_required', effective_plan: 'free', trial: false };
  if (SMART.has(operation) && effectivePlan !== 'smart') return {
    ok: false, error: 'smart_subscription_required', effective_plan: effectivePlan, trial,
  };
  return { ok: true, effective_plan: effectivePlan, trial };
}
