// BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 commit 2 / 2.
//
// Pure helpers for the KPI read paths in both the booking worker
// (`/admin/dashboard/bookings-kpis`) and the tracking worker
// (`/admin/dashboard/trip-kpis`).
//
// Design contract:
//
//   1. On a normal GET the endpoint reads the authoritative aggregate from
//      KV. If the aggregate is present and structurally valid, the endpoint
//      returns it directly — NO reconciliation scan, NO write-back.
//
//   2. If the aggregate is absent or malformed, the endpoint MAY invoke a
//      bounded reconciliation as a fallback. The reconciliation must be
//      bounded (`maxScannedContribs` upper cap) and must never grow with
//      complete tenant history. If it exceeds the read budget, the endpoint
//      returns a bounded `data_pending` response.
//
//   3. Expensive repair/materialization work belongs to write/finalization
//      paths or explicit `/rebuild` endpoints, not to the dashboard GET.
//
// The helpers here are Cloudflare-Workers-safe (no globals, no KV) and pure
// so the same rules can be unit-tested without a KV mock. The endpoint code
// keeps small inline copies wherever it doesn't already import from this
// module, so this file's tests act as the executable spec.

// Bounded read budget for the fallback reconciliation. 200 contributions is
// the observed safe worst-case for a fresh company (< 1 s KV time in
// practice); anything larger is out-of-scope for a normal dashboard GET and
// belongs on the /rebuild path.
export const KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS = 200;

// The read path emits at most one `[KPI_READ]` diagnostic line per request.
// Tokens are bounded so they never contain IDs, tokens, monetary values or
// customer data.
export const KPI_READ_SOURCE_AGGREGATE = 'aggregate';
export const KPI_READ_SOURCE_BOUNDED_FALLBACK = 'bounded_fallback';
export const KPI_READ_SOURCE_DATA_PENDING = 'data_pending';
export const KPI_READ_RECONCILE_SKIPPED = 'skipped';
export const KPI_READ_RECONCILE_BOUNDED = 'bounded';
export const KPI_READ_ENDPOINT_BOOKINGS = 'bookings';
export const KPI_READ_ENDPOINT_TRIP = 'trip';

/**
 * Returns true when the booking-finance month aggregate is present and
 * structurally valid enough to be returned directly without any
 * reconciliation scan.
 *
 * The aggregate is authoritative when EITHER
 *   * it carries an `updated_at` timestamp (i.e. it was persisted at least
 *     once by the reconciliation/materialization write path); OR
 *   * `monthly_paid_bookings_income_cents` is finite AND
 *     `monthly_paid_bookings_count` is finite (both fields are always
 *     written together by the persisted-aggregate path).
 *
 * Missing/invalid values (e.g. `NaN`, negative, non-object) fall back to
 * the bounded reconciliation path.
 */
export function bookingFinanceAggregateStructurallyValid(aggregate) {
  if (!aggregate || typeof aggregate !== 'object' || Array.isArray(aggregate)) {
    return false;
  }
  const hasTimestamp =
    typeof aggregate.updated_at === 'string' && aggregate.updated_at.length > 0;
  const incomeCents = Number(aggregate.monthly_paid_bookings_income_cents);
  const paidCount = Number(aggregate.monthly_paid_bookings_count);
  const bothCountersFinite =
    Number.isFinite(incomeCents) &&
    Number.isFinite(paidCount) &&
    incomeCents >= 0 &&
    paidCount >= 0;
  return hasTimestamp || bothCountersFinite;
}

/**
 * Returns true when the trip-KPI global + month aggregates are present and
 * structurally valid enough to compute the dashboard response without any
 * reconciliation scan.
 *
 * The trip endpoint reads three aggregates: `global` (completed/unpaid
 * counters), `month` (monthly paid rides + income), and `financeMonth`
 * (booking-finance-side amounts). The endpoint may respond directly when
 * BOTH `global` AND `month` are structurally valid; the finance aggregate
 * is optional (it has an independent absence path).
 */
export function tripKpiAggregatesStructurallyValid({
  global,
  month,
} = {}) {
  return (
    _tripKpiGlobalStructurallyValid(global) &&
    _tripKpiMonthStructurallyValid(month)
  );
}

function _tripKpiGlobalStructurallyValid(global) {
  if (!global || typeof global !== 'object' || Array.isArray(global)) {
    return false;
  }
  const completed = Number(global.completed_rides_count);
  const unpaid = Number(global.unpaid_completed_rides_count);
  return (
    Number.isFinite(completed) &&
    completed >= 0 &&
    Number.isFinite(unpaid) &&
    unpaid >= 0
  );
}

function _tripKpiMonthStructurallyValid(month) {
  if (!month || typeof month !== 'object' || Array.isArray(month)) {
    return false;
  }
  const paid = Number(month.monthly_paid_rides_count);
  const income = Number(month.monthly_income_cents);
  // A month aggregate is present when the paid-rides counter is finite; the
  // income counter is allowed to be zero (a valid successful response for
  // months without paid rides).
  return (
    Number.isFinite(paid) &&
    paid >= 0 &&
    Number.isFinite(income) &&
    income >= 0
  );
}

/**
 * Renders one bounded PII-free `[KPI_READ]` diagnostic line for the read
 * path. Never contains IDs, tokens, URLs or monetary values.
 */
export function formatKpiReadDiagnostic({
  endpoint,
  source,
  reconcile,
  elapsedMs,
  status,
} = {}) {
  const safeEndpoint = _sanitizeToken(endpoint, 16, 'trip');
  const safeSource = _sanitizeToken(source, 32, KPI_READ_SOURCE_AGGREGATE);
  const safeReconcile = _sanitizeToken(reconcile, 16, KPI_READ_RECONCILE_SKIPPED);
  const safeElapsed = _clampInt(elapsedMs, 0, 60_000);
  const safeStatus = _clampInt(status, 100, 599);
  return (
    `[KPI_READ] endpoint=${safeEndpoint} source=${safeSource} ` +
    `reconcile=${safeReconcile} elapsed_ms=${safeElapsed} status=${safeStatus}`
  );
}

/**
 * Decides which read path to take for a bookings-KPI GET, given the current
 * aggregate value and whether the caller has explicitly requested a debug
 * reconciliation.
 */
export function chooseBookingsKpiReadStrategy({
  aggregate,
  debugReconcileRequested,
} = {}) {
  if (debugReconcileRequested === true) {
    return {
      shouldReconcile: true,
      source: KPI_READ_SOURCE_BOUNDED_FALLBACK,
      reconcile: KPI_READ_RECONCILE_BOUNDED,
    };
  }
  if (bookingFinanceAggregateStructurallyValid(aggregate)) {
    return {
      shouldReconcile: false,
      source: KPI_READ_SOURCE_AGGREGATE,
      reconcile: KPI_READ_RECONCILE_SKIPPED,
    };
  }
  return {
    shouldReconcile: true,
    source: KPI_READ_SOURCE_BOUNDED_FALLBACK,
    reconcile: KPI_READ_RECONCILE_BOUNDED,
  };
}

/**
 * Decides which read path to take for a trip-KPI GET.
 */
export function chooseTripKpiReadStrategy({
  global,
  month,
  debugReconcileRequested,
} = {}) {
  if (debugReconcileRequested === true) {
    return {
      shouldReconcile: true,
      source: KPI_READ_SOURCE_BOUNDED_FALLBACK,
      reconcile: KPI_READ_RECONCILE_BOUNDED,
    };
  }
  if (tripKpiAggregatesStructurallyValid({ global, month })) {
    return {
      shouldReconcile: false,
      source: KPI_READ_SOURCE_AGGREGATE,
      reconcile: KPI_READ_RECONCILE_SKIPPED,
    };
  }
  return {
    shouldReconcile: true,
    source: KPI_READ_SOURCE_BOUNDED_FALLBACK,
    reconcile: KPI_READ_RECONCILE_BOUNDED,
  };
}

function _sanitizeToken(raw, maxLen, fallback) {
  const asString = raw == null ? '' : String(raw);
  if (!asString) return fallback;
  const bounded = asString.length > maxLen ? asString.slice(0, maxLen) : asString;
  return /^[a-z0-9_]+$/.test(bounded) ? bounded : fallback;
}

function _clampInt(raw, min, max) {
  const asNumber = Number(raw);
  if (!Number.isFinite(asNumber)) return min;
  const rounded = Math.round(asNumber);
  if (rounded < min) return min;
  if (rounded > max) return max;
  return rounded;
}
