import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('public fetchCompanySubscriptionProfile uses the shared repository', () {
    final source = File('lib/app_config.dart').readAsStringSync();
    expect(source.contains('loadCompanySubscriptionProfileUncached'), isTrue);
    expect(
      source.contains('return companySubscriptionProfileRepository.fetch('),
      isTrue,
    );
    expect(source.contains('_commitCompanySubscriptionMutation'), isTrue);
    expect(
      source.contains('invalidateCompanySubscriptionProfileCache'),
      isTrue,
    );
  });

  test('vehicle, driver and bootstrap still use the shared fetch API', () {
    final vehicle = File('lib/vehicle_management_page.dart').readAsStringSync();
    final driver = File(
      'lib/main_parts/company_driver_management_page_body.dart',
    ).readAsStringSync();
    final bootstrap = File(
      'lib/company/business_first_run_fleet_bootstrap_page.dart',
    ).readAsStringSync();
    expect(vehicle.contains('fetchCompanySubscriptionProfile('), isTrue);
    expect(driver.contains('fetchCompanySubscriptionProfile('), isTrue);
    expect(bootstrap.contains('fetchCompanySubscriptionProfile('), isTrue);
  });

  test('sign-out clears subscription and dashboard KPI caches', () {
    final source = File('lib/company_session_store.dart').readAsStringSync();
    expect(source.contains('businessDashboardKpiCache.clearAll()'), isTrue);
    expect(
      source.contains('businessDashboardKpiRefreshCoordinator.invalidateAll()'),
      isTrue,
    );
    expect(
      source.contains('companySubscriptionProfileRepository.invalidateAll()'),
      isTrue,
    );
  });
}
