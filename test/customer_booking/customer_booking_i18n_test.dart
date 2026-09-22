import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_price_block.dart';
import 'package:fluxidi_tracking/customer_booking/customer_payment_display.dart';

void main() {
  final labels = <LocalizedText>[
    kCustomerBookingTaxiTitle,
    kCustomerBookingAirportTitle,
    kCustomerBookingEventTitle,
    kCustomerBookingStayTitle,
    kCustomerBookingBusinessTitle,
    kCustomerBookingChooseCountry,
    kCustomerBookingChooseAirport,
    kCustomerBookingBrowseAllAirports,
    kCustomerBookingPickupAsk,
    kCustomerBookingDropoffAsk,
    kCustomerBookingConfirm,
    kCustomerBookingMyAddress,
    kCustomerBookingPaymentTitle,
    kCustomerBookingTotalInclVat,
    kCustomerBookingPriceOnRequest,
  ];

  test('booking chrome has a non-empty value in every offered language', () {
    for (final language in AppLanguage.values) {
      for (final label in labels) {
        expect(
          label.of(language).trim(),
          isNotEmpty,
          reason: '${label.en} missing $language',
        );
      }
    }
  });

  test('payment status labels exist in German and the other offered languages', () {
    for (final token in <String>[
      CustomerPaymentDisplayTokens.paid,
      CustomerPaymentDisplayTokens.payInCar,
      CustomerPaymentDisplayTokens.onlinePending,
      CustomerPaymentDisplayTokens.unknown,
    ]) {
      final copy = customerPaymentStatusLabel(token);
      for (final value in <String>[copy.nl, copy.en, copy.fr, copy.es, copy.de]) {
        expect(value.trim(), isNotEmpty, reason: token);
      }
    }
  });

  test('inherited booking screens no longer omit German on _t/_tr/LocalizedText', () {
    final files = <String>[
      'lib/customer_booking/customer_booking_labels.dart',
      'lib/customer_booking/customer_booking_price_block.dart',
      'lib/main_parts/customer_saved_bookings_page.dart',
      'lib/main_parts/customer_booking_detail_page.dart',
      'lib/main_parts/customer_onboarding_page.dart',
      'lib/main_parts/customer_profile_edit_page_state.dart',
      'lib/main_parts/customer_booking_lookup_page.dart',
      'lib/main_parts/customer_bookings_page.dart',
      'lib/main_parts/customer_home_page.dart',
      'lib/main_parts/customer_region_registration_page_state.dart',
    ];
    final block = RegExp(
      r"nl:\s*'((?:\\'|[^'])*)'\s*,\s*en:\s*'((?:\\'|[^'])*)'\s*,\s*fr:\s*'((?:\\'|[^'])*)'\s*,\s*es:\s*'((?:\\'|[^'])*)'(\s*)(?!,?\s*de:)",
    );
    for (final path in files) {
      final source = File(path).readAsStringSync();
      final match = block.firstMatch(source);
      expect(match, isNull, reason: 'missing de in $path near ${match?.group(2)}');
    }
  });
}
