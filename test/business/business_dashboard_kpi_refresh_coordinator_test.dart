import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business/business_dashboard_kpi_loading.dart';

void main() {
  late BusinessDashboardKpiRefreshCoordinator coordinator;
  late DateTime now;
  var bookingsGets = 0;
  var tripGets = 0;

  Future<void> runCycle() async {
    bookingsGets += 1;
    tripGets += 1;
  }

  Future<void> trigger({
    required String reason,
    String tenant = 'tenant-a',
    String company = 'company-a',
  }) {
    return coordinator.runOrShare(
      reason: reason,
      tenantId: tenant,
      companyId: company,
      cycle: runCycle,
      now: now,
    );
  }

  setUp(() {
    now = DateTime.utc(2026, 8, 30, 12, 0, 0);
    coordinator = BusinessDashboardKpiRefreshCoordinator(clock: () => now);
    bookingsGets = 0;
    tripGets = 0;
  });

  test(
    '1. normal dashboard open → exactly 1 bookings GET + 1 trip GET',
    () async {
      await trigger(reason: BusinessKpiCycleReason.init);
      coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
      expect(bookingsGets, 1);
      expect(tripGets, 1);
    },
  );

  test(
    '2. init + profile/session listener triggers for same scope → still 1+1',
    () async {
      await trigger(reason: BusinessKpiCycleReason.init);
      coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
      await trigger(reason: BusinessKpiCycleReason.scopeReady);
      expect(bookingsGets, 1);
      expect(tripGets, 1);
    },
  );

  test('3. concurrent refresh calls → one shared cycle', () async {
    final first = trigger(reason: BusinessKpiCycleReason.init);
    final second = trigger(reason: BusinessKpiCycleReason.scopeReady);
    final third = trigger(reason: BusinessKpiCycleReason.resume);
    await Future.wait(<Future<void>>[first, second, third]);
    coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
    expect(bookingsGets, 1);
    expect(tripGets, 1);
  });

  test(
    '4. immediate resume/didPopNext inside freshness window → no duplicate',
    () async {
      await trigger(reason: BusinessKpiCycleReason.init);
      coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
      now = now.add(const Duration(seconds: 10));
      await trigger(reason: BusinessKpiCycleReason.resume);
      await trigger(reason: BusinessKpiCycleReason.routeReturn);
      expect(bookingsGets, 1);
      expect(tripGets, 1);
    },
  );

  test('5. stale data → one new cycle', () async {
    await trigger(reason: BusinessKpiCycleReason.init);
    coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
    now = now.add(const Duration(seconds: 31));
    await trigger(reason: BusinessKpiCycleReason.resume);
    coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
    expect(bookingsGets, 2);
    expect(tripGets, 2);
  });

  test('6. manual refresh → one new cycle', () async {
    await trigger(reason: BusinessKpiCycleReason.init);
    coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
    await trigger(reason: BusinessKpiCycleReason.manualRetry);
    coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
    expect(bookingsGets, 2);
    expect(tripGets, 2);
  });

  test('7. tenant/company change → one new cycle for the new scope', () async {
    await trigger(reason: BusinessKpiCycleReason.init);
    coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
    coordinator.invalidate(tenantId: 'tenant-a', companyId: 'company-a');
    await trigger(
      reason: BusinessKpiCycleReason.scopeChangedRerun,
      tenant: 'tenant-b',
      company: 'company-b',
    );
    coordinator.markSuccess(tenantId: 'tenant-b', companyId: 'company-b');
    expect(bookingsGets, 2);
    expect(tripGets, 2);
  });

  test('8. late old-company result cannot overwrite the new scope', () async {
    var applyTenant = '';
    var applyCompany = '';
    var applyGeneration = 0;
    var currentGeneration = 1;

    Future<void> cycleFor({
      required String tenant,
      required String company,
      required int requestGeneration,
      required Duration delay,
    }) async {
      bookingsGets += 1;
      tripGets += 1;
      await Future<void>.delayed(delay);
      if (!businessDashboardKpiMayApplyResponse(
        requestGeneration: requestGeneration,
        currentGeneration: currentGeneration,
        requestTenantId: tenant,
        requestCompanyId: company,
        activeTenantId: applyTenant.isEmpty ? tenant : applyTenant,
        activeCompanyId: applyCompany.isEmpty ? company : applyCompany,
      )) {
        return;
      }
      applyTenant = tenant;
      applyCompany = company;
      applyGeneration = requestGeneration;
    }

    applyTenant = 'company-old';
    applyCompany = 'company-old';
    final old = coordinator.runOrShare(
      reason: BusinessKpiCycleReason.init,
      tenantId: 'company-old',
      companyId: 'company-old',
      cycle: () => cycleFor(
        tenant: 'company-old',
        company: 'company-old',
        requestGeneration: 1,
        delay: const Duration(milliseconds: 30),
      ),
    );
    currentGeneration = 2;
    applyTenant = 'company-new';
    applyCompany = 'company-new';
    final fresh = coordinator.runOrShare(
      reason: BusinessKpiCycleReason.scopeChangedRerun,
      tenantId: 'company-new',
      companyId: 'company-new',
      cycle: () => cycleFor(
        tenant: 'company-new',
        company: 'company-new',
        requestGeneration: 2,
        delay: const Duration(milliseconds: 5),
      ),
    );
    await Future.wait(<Future<void>>[old, fresh]);
    expect(applyTenant, 'company-new');
    expect(applyCompany, 'company-new');
    expect(applyGeneration, 2);
    expect(bookingsGets, 2);
    expect(tripGets, 2);
  });

  test('9. failed/data-pending/non-authoritative payload is not applied', () {
    expect(
      businessDashboardKpiPayloadIsAuthoritative(<String, dynamic>{
        'ok': true,
        'open_bookings_count': 0,
        'data_pending': true,
      }),
      isFalse,
    );
    expect(
      businessDashboardKpiPayloadIsAuthoritative(<String, dynamic>{
        'ok': true,
        'completed_rides_count': 0,
        'counts_are_authoritative': false,
      }),
      isFalse,
    );
    expect(
      businessDashboardKpiPayloadIsAuthoritative(<String, dynamic>{
        'ok': true,
        'open_bookings_count': 4,
        'degraded': true,
        'stale': true,
        'projection_health': 'ok',
      }),
      isTrue,
    );
    final previous = BusinessDashboardKpiSnapshot(
      tenantId: 't1',
      companyId: 'c1',
      openBookingsCount: 7,
      completedRidesCount: 12,
      unpaidCompletedRidesCount: 3,
      monthlyIncomeCents: 4000,
      currency: 'EUR',
      responseGeneration: 2,
    );
    final view = resolveBusinessDashboardKpiView(
      lastSuccessfulForActiveScope: previous,
      requestInFlight: false,
      lastRequestFailed: true,
    );
    expect(view.snapshot, same(previous));
    expect(view.snapshot!.openBookingsCount, 7);
  });

  test('10. bounded retry cannot create an unbounded request loop', () async {
    var attempts = 0;
    Future<void> failingCycle() async {
      attempts += 1;
      bookingsGets += 1;
      tripGets += 1;
    }

    for (var attempt = 1; attempt <= 8; attempt++) {
      final decision = resolveBusinessKpiRetryDecision(
        bookingsOutcome: BusinessKpiLegOutcome.timeout,
        tripOutcome: BusinessKpiLegOutcome.timeout,
        attempt: attempt,
      );
      if (decision != BusinessKpiRetryDecision.autoRetryTransient) {
        break;
      }
      await coordinator.runOrShare(
        reason: BusinessKpiCycleReason.autoRetry,
        tenantId: 'tenant-a',
        companyId: 'company-a',
        cycle: failingCycle,
        now: now,
      );
    }
    expect(attempts, 1);
    expect(kBusinessKpiMaxAutomaticAttempts, 2);
    expect(
      resolveBusinessKpiRetryDecision(
        bookingsOutcome: BusinessKpiLegOutcome.timeout,
        tripOutcome: BusinessKpiLegOutcome.timeout,
        attempt: 2,
      ),
      BusinessKpiRetryDecision.noRetryAttemptsExhausted,
    );
  });

  test('freshness window is the documented 30s dashboard TTL', () {
    expect(kBusinessDashboardKpiFreshness, const Duration(seconds: 30));
  });

  test('never shares in-flight or freshness across another company', () async {
    await trigger(
      reason: BusinessKpiCycleReason.init,
      tenant: 'tenant-a',
      company: 'company-a',
    );
    coordinator.markSuccess(tenantId: 'tenant-a', companyId: 'company-a');
    await trigger(
      reason: BusinessKpiCycleReason.init,
      tenant: 'tenant-a',
      company: 'company-b',
    );
    expect(bookingsGets, 2);
    expect(tripGets, 2);
  });
}
