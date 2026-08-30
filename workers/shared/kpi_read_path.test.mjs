// BUSINESS-KPI-FIRST-LOAD-P0-REPAIR-1 commit 2 / 2.
//
// Executable spec for the pure KPI read-path helpers shared by
// `handleDashboardTripKpis` (tracking worker) and
// `/admin/dashboard/bookings-kpis` (booking worker).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  KPI_READ_ENDPOINT_BOOKINGS,
  KPI_READ_ENDPOINT_TRIP,
  KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS,
  KPI_READ_RECONCILE_BOUNDED,
  KPI_READ_RECONCILE_SKIPPED,
  KPI_READ_SOURCE_AGGREGATE,
  KPI_READ_SOURCE_BOUNDED_FALLBACK,
  KPI_READ_SOURCE_DATA_PENDING,
  bookingFinanceAggregateStructurallyValid,
  chooseBookingsKpiReadStrategy,
  chooseTripKpiReadStrategy,
  formatKpiReadDiagnostic,
  tripKpiAggregatesStructurallyValid,
} from './kpi_read_path.mjs';

// Test 1 — valid bookings aggregate → reconciliation helper not called.
test('1. valid bookings aggregate → strategy skips reconciliation', () => {
  const aggregate = {
    monthly_paid_bookings_income_cents: 120239,
    monthly_paid_bookings_count: 5,
    updated_at: '2026-07-24T18:00:00Z',
  };
  assert.equal(bookingFinanceAggregateStructurallyValid(aggregate), true);
  const strategy = chooseBookingsKpiReadStrategy({
    aggregate,
    debugReconcileRequested: false,
  });
  assert.deepEqual(strategy, {
    shouldReconcile: false,
    source: KPI_READ_SOURCE_AGGREGATE,
    reconcile: KPI_READ_RECONCILE_SKIPPED,
  });
});

test('1b. aggregate with only counters (no timestamp) is still authoritative',
    () => {
  const aggregate = {
    monthly_paid_bookings_income_cents: 0,
    monthly_paid_bookings_count: 0,
  };
  assert.equal(bookingFinanceAggregateStructurallyValid(aggregate), true);
});

test('1c. aggregate with only updated_at (no counters) is still authoritative',
    () => {
  const aggregate = { updated_at: '2026-07-24T18:00:00Z' };
  assert.equal(bookingFinanceAggregateStructurallyValid(aggregate), true);
});

// Test 2 — valid trip aggregate → reconciliation helper not called.
test('2. valid trip aggregates → strategy skips reconciliation', () => {
  const global = { completed_rides_count: 137, unpaid_completed_rides_count: 14 };
  const month = { monthly_paid_rides_count: 42, monthly_income_cents: 120239 };
  assert.equal(
    tripKpiAggregatesStructurallyValid({ global, month }),
    true,
  );
  const strategy = chooseTripKpiReadStrategy({
    global,
    month,
    debugReconcileRequested: false,
  });
  assert.deepEqual(strategy, {
    shouldReconcile: false,
    source: KPI_READ_SOURCE_AGGREGATE,
    reconcile: KPI_READ_RECONCILE_SKIPPED,
  });
});

test('2b. trip month aggregate with zero paid rides is authoritative', () => {
  const global = { completed_rides_count: 0, unpaid_completed_rides_count: 0 };
  const month = { monthly_paid_rides_count: 0, monthly_income_cents: 0 };
  assert.equal(
    tripKpiAggregatesStructurallyValid({ global, month }),
    true,
  );
});

// Test 3 — missing aggregate uses bounded fallback only.
test('3. missing bookings aggregate → strategy returns data_pending, no reconcile', () => {
  assert.equal(bookingFinanceAggregateStructurallyValid({}), false);
  assert.equal(bookingFinanceAggregateStructurallyValid(null), false);
  assert.equal(bookingFinanceAggregateStructurallyValid(undefined), false);
  assert.equal(bookingFinanceAggregateStructurallyValid([]), false);
  const strategy = chooseBookingsKpiReadStrategy({
    aggregate: null,
    debugReconcileRequested: false,
  });
  assert.deepEqual(strategy, {
    shouldReconcile: false,
    source: KPI_READ_SOURCE_DATA_PENDING,
    reconcile: KPI_READ_RECONCILE_SKIPPED,
  });
});

test('3b. missing trip global → strategy returns data_pending, no reconcile', () => {
  const strategy = chooseTripKpiReadStrategy({
    global: null,
    month: { monthly_paid_rides_count: 0, monthly_income_cents: 0 },
    debugReconcileRequested: false,
  });
  assert.deepEqual(strategy, {
    shouldReconcile: false,
    source: KPI_READ_SOURCE_DATA_PENDING,
    reconcile: KPI_READ_RECONCILE_SKIPPED,
  });
});

test('3c. malformed trip month (NaN) → strategy returns data_pending, no reconcile',
    () => {
  const strategy = chooseTripKpiReadStrategy({
    global: { completed_rides_count: 5, unpaid_completed_rides_count: 0 },
    month: { monthly_paid_rides_count: NaN, monthly_income_cents: 0 },
    debugReconcileRequested: false,
  });
  assert.equal(strategy.shouldReconcile, false);
  assert.equal(strategy.source, KPI_READ_SOURCE_DATA_PENDING);
  assert.equal(strategy.reconcile, KPI_READ_RECONCILE_SKIPPED);
});

test('3d. negative counters are treated as invalid', () => {
  assert.equal(
    bookingFinanceAggregateStructurallyValid({
      monthly_paid_bookings_income_cents: -100,
      monthly_paid_bookings_count: 5,
    }),
    false,
  );
  assert.equal(
    tripKpiAggregatesStructurallyValid({
      global: {
        completed_rides_count: -1,
        unpaid_completed_rides_count: 0,
      },
      month: { monthly_paid_rides_count: 0, monthly_income_cents: 0 },
    }),
    false,
  );
});

// Test 4 — fallback cannot perform unbounded list/scan work.
test('4. bounded fallback cap is documented and small (≤ 500)', () => {
  assert.equal(typeof KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS, 'number');
  assert.ok(
    KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS > 0 &&
      KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS <= 500,
    `expected the fallback contribution cap in (0, 500], got ` +
      `${KPI_READ_MAX_FALLBACK_SCANNED_CONTRIBS}`,
  );
});

// Test 5 — valid zero totals return successfully (see test 1b above).
// A zero-valued aggregate is still an authoritative response; the read
// path returns it directly.
test('5. zero-totals aggregate is authoritative and never triggers reconcile',
    () => {
  const zero = {
    monthly_paid_bookings_income_cents: 0,
    monthly_paid_bookings_count: 0,
    updated_at: '2026-07-24T18:00:00Z',
  };
  const strategy = chooseBookingsKpiReadStrategy({
    aggregate: zero,
    debugReconcileRequested: false,
  });
  assert.equal(strategy.shouldReconcile, false);
});

// Test 10 — repeated GETs do not mutate aggregate state unnecessarily.
test('10. strategy is a pure function — repeated calls with the same aggregate '
    + 'produce the same decision (no hidden write-back)', () => {
  const aggregate = {
    monthly_paid_bookings_income_cents: 100,
    monthly_paid_bookings_count: 1,
    updated_at: '2026-07-24T00:00:00Z',
  };
  const first = chooseBookingsKpiReadStrategy({
    aggregate,
    debugReconcileRequested: false,
  });
  const second = chooseBookingsKpiReadStrategy({
    aggregate,
    debugReconcileRequested: false,
  });
  const third = chooseBookingsKpiReadStrategy({
    aggregate,
    debugReconcileRequested: false,
  });
  assert.deepEqual(first, second);
  assert.deepEqual(second, third);
  assert.equal(first.shouldReconcile, false);
});

// Test 11 — cold request does not require a full historical reconciliation
// (bounded fallback path).
test('11. cold aggregate (absent) is data_pending and never reconciles',
    () => {
  const strategy = chooseBookingsKpiReadStrategy({
    aggregate: null,
    debugReconcileRequested: false,
  });
  assert.equal(strategy.shouldReconcile, false);
  assert.equal(strategy.source, KPI_READ_SOURCE_DATA_PENDING);
  assert.equal(strategy.reconcile, KPI_READ_RECONCILE_SKIPPED);
});

// Test 12 — HTTP GET never honors debug reconcile (belongs on /rebuild).
test('12. explicit debug reconcile is ignored on the ordinary GET strategy', () => {
  const validAggregate = {
    monthly_paid_bookings_income_cents: 0,
    monthly_paid_bookings_count: 0,
    updated_at: '2026-07-24T00:00:00Z',
  };
  const strategy = chooseBookingsKpiReadStrategy({
    aggregate: validAggregate,
    debugReconcileRequested: true,
  });
  assert.equal(strategy.shouldReconcile, false);
  assert.equal(strategy.reconcile, KPI_READ_RECONCILE_SKIPPED);
});

test('12b. trip GET strategy never reconciles even when debug is requested',
    () => {
  const global = { completed_rides_count: 1, unpaid_completed_rides_count: 0 };
  const month = { monthly_paid_rides_count: 1, monthly_income_cents: 100 };
  const strategy = chooseTripKpiReadStrategy({
    global,
    month,
    debugReconcileRequested: true,
  });
  assert.equal(strategy.shouldReconcile, false);
  assert.equal(strategy.reconcile, KPI_READ_RECONCILE_SKIPPED);
});

test('diagnostic line is bounded and PII-free', () => {
  const line = formatKpiReadDiagnostic({
    endpoint: KPI_READ_ENDPOINT_BOOKINGS,
    source: KPI_READ_SOURCE_AGGREGATE,
    reconcile: KPI_READ_RECONCILE_SKIPPED,
    elapsedMs: 42,
    status: 200,
  });
  assert.equal(
    line,
    '[KPI_READ] endpoint=bookings source=aggregate reconcile=skipped '
      + 'elapsed_ms=42 status=200',
  );
});

test('diagnostic clamps out-of-range integers and rejects freeform tokens',
    () => {
  const line = formatKpiReadDiagnostic({
    endpoint: 'evil endpoint with spaces',
    source: 'source-with-dashes',
    reconcile: 'STATUS_UPPER',
    elapsedMs: -50,
    status: 12345,
  });
  // Bad tokens fall back to defaults, negative elapsed clamped to 0, status
  // clamped to <=599.
  assert.ok(line.startsWith('[KPI_READ]'));
  assert.match(line, /endpoint=trip/);
  assert.match(line, /source=aggregate/);
  assert.match(line, /reconcile=skipped/);
  assert.match(line, /elapsed_ms=0/);
  assert.match(line, /status=599/);
});

test('diagnostic accepts data_pending source label', () => {
  const line = formatKpiReadDiagnostic({
    endpoint: KPI_READ_ENDPOINT_TRIP,
    source: KPI_READ_SOURCE_DATA_PENDING,
    reconcile: KPI_READ_RECONCILE_SKIPPED,
    elapsedMs: 10,
    status: 202,
  });
  assert.match(line, /source=data_pending/);
  assert.match(line, /status=202/);
});
