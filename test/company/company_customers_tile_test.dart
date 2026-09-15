import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home tile is Klantenbeheer and opens the customers page', () {
    final home = File(
      'lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    expect(home.contains("nl: 'Klantenbeheer'"), isTrue);
    expect(home.contains('_openCompanyCustomers'), isTrue);
    expect(home.contains('_openCompanyPlanRide'), isTrue);
    expect(home.contains('CompanyCustomersPage('), isTrue);
    expect(home.contains('CompanyOpsWorkspacePage('), isTrue);
    expect(home.contains('issuerName:'), isTrue);
    expect(home.contains('onOpenBooking:'), isTrue);
    expect(home.contains('openCompanyBookingDetail('), isTrue);
    expect(home.contains('CompanyBookingOpenedFrom.bookingsList'), isTrue);
    expect(home.contains('const BusinessSettingsPage()'), isTrue);
    expect(home.contains('const VehicleManagementPage()'), isTrue);
    expect(home.contains('const CompanyDriverManagementPage()'), isTrue);
    expect(home.contains('const CompanyBookingsOverviewPage()'), isTrue);
    expect(home.contains("nl: 'AI Dispatch'"), isFalse);
    expect(
      home.contains("onTap: () => _openCompanyCustomers(context)"),
      isTrue,
    );
    expect(home.contains("'company_home_customers'"), isTrue);
  });

  test('old AI Dispatch placeholder is no longer reachable via that tile', () {
    final home = File(
      'lib/main_parts/business_home_page_state.dart',
    ).readAsStringSync();
    final tileStart = home.indexOf("actionKey: 'ai_dispatch'");
    expect(tileStart, greaterThan(0));
    final tile = home.substring(tileStart, tileStart + 700);
    expect(tile.contains('isFuture: true'), isFalse);
    expect(tile.contains("nl: 'Binnenkort'"), isFalse);
    expect(tile.contains('_openCompanyCustomers'), isTrue);
  });
}
