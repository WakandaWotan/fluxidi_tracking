import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'company and chauffeur lists use the shared booking-page repository',
    () {
      final company = File(
        'lib/main_parts/company_bookings_overview_page.dart',
      ).readAsStringSync();
      final driver = File(
        'lib/main_parts/driver_home_page_state.dart',
      ).readAsStringSync();
      expect(company.contains('bookingListPageRepository.fetch('), isTrue);
      expect(company.contains('kBookingListProjectedPageSize'), isFalse);
      expect(company.contains("'limit': '200'"), isFalse);
      expect(company.contains('_bookingLoadedExtraPages'), isTrue);
      expect(driver.contains('bookingListPageRepository.fetch('), isTrue);
      expect(driver.contains('_driverLoadedExtraPages'), isTrue);
      expect(driver.contains("'limit': '50'"), isFalse);
      expect(driver.contains('kDriverBookingsPath'), isTrue);
      expect(company.contains('kListBookingsPath'), isTrue);
    },
  );

  test('sign-out and company change invalidate booking-page cache', () {
    final companySession = File(
      'lib/company_session_store.dart',
    ).readAsStringSync();
    final driverSession = File(
      'lib/driver_session_store.dart',
    ).readAsStringSync();
    final businessHome = File(
      'lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    expect(
      companySession.contains('bookingListPageRepository.invalidateAll()'),
      isTrue,
    );
    expect(
      driverSession.contains('bookingListPageRepository.invalidateAll()'),
      isTrue,
    );
    expect(
      businessHome.contains('bookingListPageRepository.invalidate('),
      isTrue,
    );
  });

  test('QA logging defaults false and never logs identifiers', () {
    final repo = File(
      'lib/company/booking_list_page_repository.dart',
    ).readAsStringSync();
    expect(repo.contains("defaultValue: false"), isTrue);
    expect(repo.contains('FLUXIDI_QA_REQUEST_LOGGING'), isTrue);
    expect(repo.contains('booking_page_network_fetch'), isTrue);
    expect(repo.contains('booking_page_legacy_contract'), isTrue);
    expect(repo.contains('tenantId='), isFalse);
    expect(repo.contains('companyId='), isFalse);
    expect(repo.contains('driverId='), isFalse);
    expect(repo.contains('bookingId='), isFalse);
  });

  test('P0B KPI fallback remains disabled', () {
    final kpi = File(
      'lib/business/business_dashboard_kpi_loading.dart',
    ).readAsStringSync();
    expect(
      kpi.contains(
        'bool businessDashboardKpiAllowsAutomaticBookingsListFallback() => false;',
      ),
      isTrue,
    );
  });

  test('no automatic drain-all helper is false', () {
    final repo = File(
      'lib/company/booking_list_page_repository.dart',
    ).readAsStringSync();
    expect(
      repo.contains('bool bookingListAllowsAutomaticDrain() => false;'),
      isTrue,
    );
  });
}
