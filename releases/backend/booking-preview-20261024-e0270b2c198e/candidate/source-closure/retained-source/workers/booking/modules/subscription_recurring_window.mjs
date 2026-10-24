// Limit provider-generated payments to dates covered by reviewed fiscal proof.
// No scheduler/KV scan is needed for the provider-side finite payment limit.
const DAY = 86400000;
const fail = reason => ({ ok: false, error: `subscription_recurring_window_${reason}` });
const date = value => typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
  Number.isFinite(Date.parse(`${value}T00:00:00.000Z`)) && new Date(`${value}T00:00:00.000Z`).toISOString().slice(0, 10) === value
  ? Date.parse(`${value}T00:00:00.000Z`) : NaN;
const iso = value => typeof value === 'string' && Number.isFinite(Date.parse(value)) &&
  new Date(value).toISOString() === value ? Date.parse(value) : NaN;
function occurrence(start, index) {
  const anchor = new Date(start), year = anchor.getUTCFullYear(), month = anchor.getUTCMonth();
  const lastAnchor = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();
  const last = new Date(Date.UTC(year, month + index + 1, 0)).getUTCDate();
  return Date.UTC(year, month + index, anchor.getUTCDate() === lastAnchor ? last : Math.min(anchor.getUTCDate(), last));
}

export function recurringFiscalWindow(snapshot, { startDate, nextPaymentDate = startDate, nowMs = Date.now() } = {}) {
  const start = date(startDate), next = date(nextPaymentDate), until = iso(snapshot?.valid_until);
  const effective = iso(snapshot?.effective_from);
  if (![start, next, until, effective, nowMs].every(Number.isFinite)) return fail('date_invalid');
  // A payment day can be interpreted in a provider timezone. Require a full
  // 38-hour end margin and 14-hour start margin, and do not PATCH a
  // potentially in-flight debit (within 36 hours).
  if (next - nowMs < 36 * 3600000 || next - 14 * 3600000 < effective) return fail('date_not_safely_future');
  let index = -1;
  for (let i = 0; i < 1200; i++) {
    const value = occurrence(start, i);
    if (value === next) { index = i; break; }
    if (value > next) break;
  }
  if (index < 0) return fail('schedule_conflict');
  let count = 0;
  for (; count < 120; count++) if (occurrence(start, index + count) + DAY + 14 * 3600000 >= until) break;
  if (count === 0) return fail('proof_does_not_cover_payment');
  if (count === 120 && occurrence(start, index + count) + DAY + 14 * 3600000 < until) return fail('horizon_too_large');
  return { ok: true, future_payments: count, first_payment_date: nextPaymentDate,
    final_payment_date: new Date(occurrence(start, index + count - 1)).toISOString().slice(0, 10), valid_until: snapshot.valid_until };
}

export function recurringFiscalPatchWindow(snapshot, subscription, { customerId, subscriptionId, scope, nowMs = Date.now() } = {}) {
  if (subscription?.id !== subscriptionId || subscription?.customerId !== customerId || subscription?.status !== 'active' ||
      subscription?.interval !== '1 month' || subscription?.metadata?.purpose !== 'fluxidi_subscription_recurring' ||
      subscription?.metadata?.tenant_id !== scope?.tenant_id || subscription?.metadata?.company_id !== scope?.company_id)
    return fail('provider_identity_conflict');
  if (!Number.isSafeInteger(subscription.times) || subscription.times <= 0 ||
      !Number.isSafeInteger(subscription.timesRemaining) || subscription.timesRemaining <= 0 || subscription.timesRemaining > subscription.times)
    return fail('provider_count_unproven');
  const result = recurringFiscalWindow(snapshot, { startDate: subscription.startDate, nextPaymentDate: subscription.nextPaymentDate, nowMs });
  if (!result.ok) return result;
  return { ...result, times: subscription.times - subscription.timesRemaining + result.future_payments };
}

export function recurringFiscalProviderConfirmation(subscription, { customerId, subscriptionId, scope, times, amount, snapshotId } = {}) {
  if (subscription?.id !== subscriptionId || subscription?.customerId !== customerId || subscription?.status !== 'active' ||
      subscription?.interval !== '1 month' || subscription?.metadata?.purpose !== 'fluxidi_subscription_recurring' ||
      subscription?.metadata?.tenant_id !== scope?.tenant_id || subscription?.metadata?.company_id !== scope?.company_id ||
      subscription?.metadata?.fluxidi_tax_snapshot_id !== snapshotId) return fail('provider_confirmation_identity');
  if (!Number.isSafeInteger(times) || times <= 0 || subscription.times !== times ||
      !Number.isSafeInteger(subscription.timesRemaining) || subscription.timesRemaining <= 0 || subscription.timesRemaining > times)
    return fail('provider_confirmation_count');
  if (!/^[A-Z]{3}$/.test(amount?.currency || '') || !/^\d+\.\d{2}$/.test(amount?.value || '') ||
      subscription?.amount?.currency !== amount.currency || subscription?.amount?.value !== amount.value)
    return fail('provider_confirmation_amount');
  return { ok: true };
}
