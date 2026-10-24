import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business/business_dashboard_kpi_loading.dart';

/// Xiaomi runtime body: structurally valid, dirty, non-authoritative.
Map<String, dynamic> dirtyBookingsProjection({int open = 3}) {
  return <String, dynamic>{
    'ok': true,
    'open_bookings_count': open,
    'projection_health': 'dirty',
    'counts_are_authoritative': false,
    'source': 'projection_degraded',
  };
}

Map<String, dynamic> cleanBookingsProjection({int open = 3}) {
  return <String, dynamic>{
    'ok': true,
    'open_bookings_count': open,
    'projection_health': 'ok',
    'counts_are_authoritative': true,
    'source': 'projection',
  };
}

Map<String, dynamic> cleanTripProjection({
  int completed = 10,
  int unpaid = 2,
  int income = 5000,
}) {
  return <String, dynamic>{
    'ok': true,
    'completed_rides_count': completed,
    'unpaid_completed_rides_count': unpaid,
    'monthly_income_cents': income,
    'currency': 'EUR',
    'projection_health': 'ok',
    'counts_are_authoritative': true,
  };
}

Map<String, dynamic> dirtyTripProjection({
  int completed = 10,
  int unpaid = 2,
  int income = 5000,
}) {
  return <String, dynamic>{
    'ok': true,
    'completed_rides_count': completed,
    'unpaid_completed_rides_count': unpaid,
    'monthly_income_cents': income,
    'currency': 'EUR',
    'projection_health': 'dirty',
    'counts_are_authoritative': false,
    'source': 'projection_degraded',
    'degraded': true,
  };
}

BusinessDashboardKpiSnapshot priorSnapshot() {
  return const BusinessDashboardKpiSnapshot(
    tenantId: 't1',
    companyId: 'c1',
    openBookingsCount: 7,
    completedRidesCount: 12,
    unpaidCompletedRidesCount: 3,
    monthlyIncomeCents: 4000,
    currency: 'EUR',
    responseGeneration: 2,
  );
}

void main() {
  test(
    '1. valid clean projection is applied and never loads the bookings list',
    () {
      expect(
        classifyBusinessDashboardKpiBookingsPayload(cleanBookingsProjection()),
        BusinessDashboardKpiPayloadKind.clean,
      );
      expect(
        classifyBusinessDashboardKpiTripPayload(cleanTripProjection()),
        BusinessDashboardKpiPayloadKind.clean,
      );
      expect(
        resolveBusinessDashboardKpiApplyAction(
          bookingsKind: BusinessDashboardKpiPayloadKind.clean,
          tripKind: BusinessDashboardKpiPayloadKind.clean,
          hasPreviousSnapshot: false,
        ),
        BusinessDashboardKpiApplyAction.apply,
      );
      expect(businessDashboardKpiAllowsAutomaticBookingsListFallback(), isFalse);
    },
  );

  test(
    '2. valid dirty/non-authoritative projection is degraded last-known, zero fallback',
    () {
      final kind = classifyBusinessDashboardKpiBookingsPayload(
        dirtyBookingsProjection(open: 6),
      );
      expect(kind, BusinessDashboardKpiPayloadKind.degraded);
      expect(
        classifyBusinessKpiLegHttpOutcome(
          statusCode: 200,
          decodedOk: kind != BusinessDashboardKpiPayloadKind.malformed,
        ),
        BusinessKpiLegOutcome.success,
      );
      expect(
        businessDashboardKpiPayloadIsAuthoritative(dirtyBookingsProjection()),
        isFalse,
      );
      final health = combineBusinessDashboardKpiWorkerHealth(
        bookings: parseBusinessDashboardKpiWorkerHealth(
          dirtyBookingsProjection(open: 6),
        ),
        trip: parseBusinessDashboardKpiWorkerHealth(dirtyTripProjection()),
        bookingsKind: BusinessDashboardKpiPayloadKind.degraded,
        tripKind: BusinessDashboardKpiPayloadKind.degraded,
      );
      final snap = BusinessDashboardKpiSnapshot(
        tenantId: 't1',
        companyId: 'c1',
        openBookingsCount: 6,
        completedRidesCount: 10,
        unpaidCompletedRidesCount: 2,
        monthlyIncomeCents: 5000,
        currency: 'EUR',
        responseGeneration: 3,
        health: health,
      );
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: snap,
        requestInFlight: false,
        lastRequestFailed: false,
      );
      expect(view.snapshot!.openBookingsCount, 6);
      expect(view.hasAuthoritativeValues, isFalse);
      expect(view.showDegradedNotice, isTrue);
      expect(view.showUpdatingNotice, isTrue);
      expect(businessDashboardKpiAllowsAutomaticBookingsListFallback(), isFalse);
    },
  );

  test('3. degraded zero is never marked authoritative/healthy', () {
    final snap = BusinessDashboardKpiSnapshot(
      tenantId: 't1',
      companyId: 'c1',
      openBookingsCount: 0,
      completedRidesCount: 0,
      unpaidCompletedRidesCount: 0,
      monthlyIncomeCents: 0,
      currency: 'EUR',
      responseGeneration: 1,
      health: const BusinessDashboardKpiWorkerHealth(
        dataPending: false,
        degraded: true,
        stale: true,
        projectionHealth: 'dirty',
        countsAreAuthoritative: false,
      ),
    );
    final view = resolveBusinessDashboardKpiView(
      lastSuccessfulForActiveScope: snap,
      requestInFlight: false,
      lastRequestFailed: false,
    );
    expect(view.hasAuthoritativeValues, isFalse);
    expect(view.snapshot!.isAuthoritative, isFalse);
    expect(view.showDegradedNotice, isTrue);
    expect(
      businessDashboardKpiCountText(
        snapshot: view.snapshot,
        select: (s) => s.openBookingsCount,
      ),
      '0',
    );
  });

  test('4. data_pending with prior snapshot retains prior, zero fallback', () {
    expect(
      classifyBusinessDashboardKpiBookingsPayload(<String, dynamic>{
        'ok': true,
        'open_bookings_count': 0,
        'data_pending': true,
      }),
      BusinessDashboardKpiPayloadKind.pending,
    );
    expect(
      resolveBusinessDashboardKpiApplyAction(
        bookingsKind: BusinessDashboardKpiPayloadKind.pending,
        tripKind: BusinessDashboardKpiPayloadKind.clean,
        hasPreviousSnapshot: true,
      ),
      BusinessDashboardKpiApplyAction.keepPrevious,
    );
    final view = resolveBusinessDashboardKpiView(
      lastSuccessfulForActiveScope: priorSnapshot(),
      requestInFlight: false,
      lastRequestFailed: false,
      projectionPending: true,
    );
    expect(view.snapshot!.openBookingsCount, 7);
    expect(view.showUpdatingNotice, isTrue);
    expect(businessDashboardKpiAllowsAutomaticBookingsListFallback(), isFalse);
  });

  test(
    '5. data_pending without prior snapshot is pending/unavailable, zero fallback',
    () {
      expect(
        resolveBusinessDashboardKpiApplyAction(
          bookingsKind: BusinessDashboardKpiPayloadKind.pending,
          tripKind: BusinessDashboardKpiPayloadKind.pending,
          hasPreviousSnapshot: false,
        ),
        BusinessDashboardKpiApplyAction.unavailable,
      );
      final view = resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: null,
        requestInFlight: false,
        lastRequestFailed: false,
        projectionPending: true,
      );
      expect(view.phase, BusinessDashboardKpiPhase.unavailable);
      expect(view.snapshot, isNull);
      expect(view.hasAuthoritativeValues, isFalse);
      expect(view.showUpdatingNotice, isTrue);
      expect(businessDashboardKpiAllowsAutomaticBookingsListFallback(), isFalse);
    },
  );

  test('6. malformed/HTTP failure never starts an automatic list fallback', () {
    expect(
      classifyBusinessDashboardKpiBookingsPayload(<String, dynamic>{
        'ok': false,
        'open_bookings_count': 3,
      }),
      BusinessDashboardKpiPayloadKind.malformed,
    );
    expect(
      classifyBusinessKpiLegHttpOutcome(statusCode: 500, decodedOk: false),
      BusinessKpiLegOutcome.http5xx,
    );
    expect(
      resolveBusinessDashboardKpiApplyAction(
        bookingsKind: BusinessDashboardKpiPayloadKind.malformed,
        tripKind: BusinessDashboardKpiPayloadKind.clean,
        hasPreviousSnapshot: true,
      ),
      BusinessDashboardKpiApplyAction.keepPrevious,
    );
    expect(businessDashboardKpiAllowsAutomaticBookingsListFallback(), isFalse);
  });

  test(
    '7. dashboard KPI source never reconstructs counts from bookings-list',
    () {
      final source = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(source.contains('_loadOpenBookingsFallbackCount'), isFalse);
      expect(source.contains('include_history'), isFalse);
      expect(source.contains('/admin/dashboard/bookings-kpis'), isTrue);
      expect(source.contains('/admin/dashboard/trip-kpis'), isTrue);
      expect(
        source.contains('BusinessKpiLoadEvent.manualRefresh'),
        isTrue,
      );
      expect(businessDashboardKpiAllowsAutomaticBookingsListFallback(), isFalse);
    },
  );

  test(
    'Xiaomi dirty Worker contract is structurally valid, not invalid_payload',
    () {
      final decoded = dirtyBookingsProjection();
      final kind = classifyBusinessDashboardKpiBookingsPayload(decoded);
      expect(kind, isNot(BusinessDashboardKpiPayloadKind.malformed));
      expect(kind, BusinessDashboardKpiPayloadKind.degraded);
      expect(
        classifyBusinessKpiLegHttpOutcome(
          statusCode: 200,
          decodedOk: kind != BusinessDashboardKpiPayloadKind.malformed,
        ),
        isNot(BusinessKpiLegOutcome.invalidPayload),
      );
    },
  );
}
