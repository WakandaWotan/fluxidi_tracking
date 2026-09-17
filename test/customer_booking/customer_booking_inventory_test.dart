import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_entry.dart';

void main() {
  test('customer taxi CTAs share one flow opener and leave no CalculatorPage', () {
    const files = <String>[
      'lib/main_parts/customer_home_page.dart',
      'lib/partner_public_profile_page.dart',
      'lib/nearby_partners_page.dart',
      'lib/hotels/hotels_page.dart',
    ];
    for (final path in files) {
      final source = File(path).readAsStringSync();
      expect(source.contains('openCustomerBookingFlow'), isTrue, reason: path);
      expect(source.contains('CalculatorPage('), isFalse, reason: path);
      expect(source.contains('AirportPage('), isFalse, reason: path);
    }
    expect(kCustomerBookingTaxiCtaInventory, isNotEmpty);
    expect(
      File('lib/main_parts/driver_home_page_state.dart').readAsStringSync(),
      contains('CalculatorPage('),
    );
  });

  test('limousine discovery stays off the taxi booking flow', () {
    final home = File('lib/main_parts/customer_home_page.dart').readAsStringSync();
    expect(home.contains('openLimousineCustomerDiscovery'), isTrue);
    expect(
      home.contains('CustomerBookingKind'),
      isTrue,
    );
  });
}
