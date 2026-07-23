import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business/business_dashboard_kpi_loading.dart';

BusinessDashboardKpiSnapshot snap({
  String tenant = 't1',
  String company = 'c1',
  int open = 0,
  int completed = 137,
  int unpaid = 14,
  int income = 120239,
  int generation = 1,
}) {
  return BusinessDashboardKpiSnapshot(
    tenantId: tenant,
    companyId: company,
    openBookingsCount: open,
    completedRidesCount: completed,
    unpaidCompletedRidesCount: unpaid,
    monthlyIncomeCents: income,
    currency: 'EUR',
    responseGeneration: generation,
  );
}

void main() {
  group('BUSINESS-DASHBOARD-KPI-LOADING-UX-1 presentation', () {
    test('1. initial loading does not display authoritative zeros', () {
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: null,
        requestInFlight: true,
        lastRequestFailed: false,
      );
      expect(view.phase, BusinessDashboardKpiPhase.initialLoading);
      expect(view.snapshot, isNull);
      expect(view.hasAuthoritativeValues, isFalse);
      expect(
        businessDashboardKpiCountText(
          snapshot: view.snapshot,
          select: (s) => s.completedRidesCount,
        ),
        '—',
      );
      expect(businessDashboardKpiIncomeCents(view.snapshot), isNull);
    });

    test('2. first successful response updates all cards atomically', () {
      final s = snap(generation: 3);
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: s,
        requestInFlight: false,
        lastRequestFailed: false,
      );
      expect(view.phase, BusinessDashboardKpiPhase.ready);
      expect(view.snapshot!.openBookingsCount, 0);
      expect(view.snapshot!.completedRidesCount, 137);
      expect(view.snapshot!.unpaidCompletedRidesCount, 14);
      expect(view.snapshot!.monthlyIncomeCents, 120239);
      expect(view.snapshot!.responseGeneration, 3);
      // All four values share one generation (atomic apply).
      expect(view.snapshot!.responseGeneration, s.responseGeneration);
    });

    test('3. refresh preserves previous values', () {
      final previous = snap();
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: previous,
        requestInFlight: true,
        lastRequestFailed: false,
      );
      expect(view.phase, BusinessDashboardKpiPhase.refreshing);
      expect(view.snapshot, same(previous));
      expect(view.showRefreshIndicator, isTrue);
      expect(
        businessDashboardKpiCountText(
          snapshot: view.snapshot,
          select: (s) => s.completedRidesCount,
        ),
        '137',
      );
    });

    test('4. failed refresh preserves previous values', () {
      final previous = snap();
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: previous,
        requestInFlight: false,
        lastRequestFailed: true,
      );
      expect(view.phase, BusinessDashboardKpiPhase.ready);
      expect(view.snapshot, same(previous));
      expect(view.showRetry, isTrue);
      expect(view.snapshot!.monthlyIncomeCents, 120239);
    });

    test('5. first-load failure shows unavailable/retry state', () {
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: null,
        requestInFlight: false,
        lastRequestFailed: true,
      );
      expect(view.phase, BusinessDashboardKpiPhase.unavailable);
      expect(view.snapshot, isNull);
      expect(view.showRetry, isTrue);
      expect(
        businessDashboardKpiCountText(
          snapshot: view.snapshot,
          select: (s) => s.openBookingsCount,
        ),
        '—',
      );
    });

    test('8. open/completed/unpaid/income remain from one response generation', () {
      expect(
        businessDashboardKpiResponseIsComplete(
          bookingsOk: true,
          tripKpisOk: true,
        ),
        isTrue,
      );
      expect(
        businessDashboardKpiResponseIsComplete(
          bookingsOk: true,
          tripKpisOk: false,
        ),
        isFalse,
      );
      expect(
        businessDashboardKpiResponseIsComplete(
          bookingsOk: false,
          tripKpisOk: true,
        ),
        isFalse,
      );
    });
  });

  group('BUSINESS-DASHBOARD-KPI-LOADING-UX-1 cache and scope', () {
    test('6. company scope change clears the old snapshot from display path', () {
      final cache = BusinessDashboardKpiCache();
      cache.put(snap(tenant: 't1', company: 'c1'));
      cache.put(snap(tenant: 't1', company: 'c2', completed: 5, generation: 2));
      cache.clearScope(tenantId: 't1', companyId: 'c1');
      expect(cache.get(tenantId: 't1', companyId: 'c1'), isNull);
      // Other company untouched.
      expect(cache.get(tenantId: 't1', companyId: 'c2')!.completedRidesCount, 5);
    });

    test('never returns another company snapshot', () {
      final cache = BusinessDashboardKpiCache();
      cache.put(snap(tenant: 't1', company: 'c1', completed: 99));
      expect(cache.get(tenantId: 't1', companyId: 'c2'), isNull);
      expect(cache.get(tenantId: 't9', companyId: 'c1'), isNull);
    });

    test('7. stale response from old scope is rejected', () {
      expect(
        businessDashboardKpiMayApplyResponse(
          requestGeneration: 1,
          currentGeneration: 2,
          requestTenantId: 't1',
          requestCompanyId: 'c1',
          activeTenantId: 't1',
          activeCompanyId: 'c1',
        ),
        isFalse,
      );
      expect(
        businessDashboardKpiMayApplyResponse(
          requestGeneration: 2,
          currentGeneration: 2,
          requestTenantId: 't1',
          requestCompanyId: 'c1',
          activeTenantId: 't1',
          activeCompanyId: 'c2',
        ),
        isFalse,
      );
      expect(
        businessDashboardKpiMayApplyResponse(
          requestGeneration: 2,
          currentGeneration: 2,
          requestTenantId: 't1',
          requestCompanyId: 'c1',
          activeTenantId: 't1',
          activeCompanyId: 'c1',
        ),
        isTrue,
      );
    });

    test('dashboard entry may use scoped last successful snapshot immediately', () {
      final cache = BusinessDashboardKpiCache();
      final stored = snap(generation: 4);
      cache.put(stored);
      final hit = cache.get(tenantId: 't1', companyId: 'c1');
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: hit,
        requestInFlight: true,
        lastRequestFailed: false,
      );
      expect(view.phase, BusinessDashboardKpiPhase.refreshing);
      expect(view.snapshot!.responseGeneration, 4);
      expect(view.snapshot!.completedRidesCount, 137);
    });
  });

  group('BUSINESS-DASHBOARD-KPI-LOADING-UX-1 diagnostics', () {
    test('duration buckets are bounded and PII-free', () {
      expect(businessKpiDurationBucket(0), 'lt_250');
      expect(businessKpiDurationBucket(400), '250_499');
      expect(businessKpiDurationBucket(800), '500_999');
      expect(businessKpiDurationBucket(1500), '1000_1999');
      expect(businessKpiDurationBucket(3000), '2000_4999');
      expect(businessKpiDurationBucket(9000), 'gte_5000');
      expect(BusinessKpiLoadEvent.cacheHit, 'cache_hit');
      expect(BusinessKpiLoadEvent.snapshotApplied, 'snapshot_applied');
    });
  });
}
