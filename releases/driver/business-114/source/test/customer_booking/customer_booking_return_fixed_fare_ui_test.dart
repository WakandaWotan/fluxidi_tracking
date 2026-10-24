// Dossier 01 UI — a 422 return_fixed_fare_unresolved is shown clearly and
// Confirm stays blocked. No price is invented on the device.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

LimousineAddressValue address(String label) {
  return LimousineAddressValue(
    displayText: label,
    canonicalLabel: label,
    lat: 50.7452,
    lon: 3.5981,
    acceptance: LimousineAddressAcceptance.selected,
  );
}

void main() {
  test('the server code maps to a clear reason in every language', () {
    for (final language in AppLanguage.values) {
      final text = customerBookingSubmitIssueText(
        kCustomerBookingIssueReturnFixedFare,
        language,
      );
      expect(text, kCustomerBookingReturnFixedFareUnresolved.of(language));
      expect(text.trim(), isNotEmpty);
      expect(text, isNot(contains('return_fixed_fare_unresolved')));
    }
  });

  test('a 422 quote error blocks Confirm with that reason', () {
    final issues = customerBookingSubmitIssues(
      hasCompany: true,
      pickup: address('Koekamerstraat 48A, 9688 Louise-Marie'),
      dropoff: address('Brussels South Charleroi Airport, Belgium'),
      whenNow: true,
      pickupLocal: null,
      name: 'Christophe',
      phone: '+32470000000',
      quoteLoading: false,
      quote: null,
      quoteError: kCustomerBookingIssueReturnFixedFare,
      successId: null,
    );
    expect(
      issues.map((issue) => issue.code),
      contains(kCustomerBookingIssueReturnFixedFare),
    );
    expect(
      customerBookingSubmitIssueText(issues.first.code, AppLanguage.nl),
      contains('terugrit'),
    );
  });

  test('no quote means no price, so nothing can be shown as a total', () {
    final issues = customerBookingSubmitIssues(
      hasCompany: true,
      pickup: address('Koekamerstraat 48A, 9688 Louise-Marie'),
      dropoff: address('Brussels South Charleroi Airport, Belgium'),
      whenNow: true,
      pickupLocal: null,
      name: 'Christophe',
      phone: '+32470000000',
      quoteLoading: false,
      quote: null,
      quoteError: kCustomerBookingIssueReturnFixedFare,
      successId: null,
    );
    expect(issues, isNotEmpty, reason: 'Confirm must stay blocked');
  });

  test('a consistent 200 + 200 roundtrip still confirms at 400', () {
    final quote = parseCompanyPlanQuote(
      <String, dynamic>{
        'ok': true,
        'price_incl_vat': 200,
        'price_incl_vat_main': 200,
        'price_incl_vat_return': 200,
        'total_price_incl_vat': 400,
        'distance_km': 118.4,
        'duration_min': 92,
        'return_distance_km': 118.4,
        'return_duration_min': 95,
        'currency': 'EUR',
        'price_available': true,
      },
      fingerprint: 'charleroi-400',
    );
    expect(quote.displayTotalPrice, 400);
    expect(quote.totalCheck.consistent, isTrue);
    final issues = customerBookingSubmitIssues(
      hasCompany: true,
      pickup: address('Koekamerstraat 48A, 9688 Louise-Marie'),
      dropoff: address('Brussels South Charleroi Airport, Belgium'),
      whenNow: true,
      pickupLocal: null,
      name: 'Christophe',
      phone: '+32470000000',
      quoteLoading: false,
      quote: quote,
      quoteError: null,
      successId: null,
    );
    expect(issues, isEmpty);
  });
}
