// Dossier 01 — a roundtrip total that disagrees with its legs is reported and
// blocks the booking. It is never repaired on the device.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

Map<String, dynamic> charleroiRoundTripWire({
  required num main,
  required num ret,
  required num total,
}) {
  return <String, dynamic>{
    'ok': true,
    'price_incl_vat': main,
    'price_incl_vat_main': main,
    'price_incl_vat_return': ret,
    'total_price_incl_vat': total,
    'distance_km': 118.4,
    'duration_min': 92,
    'return_distance_km': 118.4,
    'return_duration_min': 95,
    'currency': 'EUR',
    'price_available': true,
  };
}

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
  test('200 + 200 listed as 401 is inconsistent and drifts 100 cents', () {
    final quote = parseCompanyPlanQuote(
      charleroiRoundTripWire(main: 200, ret: 200, total: 401),
      fingerprint: 'charleroi-401',
    );
    final check = quote.totalCheck;
    expect(check.comparable, isTrue);
    expect(check.consistent, isFalse);
    expect(check.legSumCents, 40000);
    expect(check.listedCents, 40100);
    expect(check.driftCents, 100);
  });

  test('displayTotalPrice no longer masks the server total', () {
    final quote = parseCompanyPlanQuote(
      charleroiRoundTripWire(main: 200, ret: 200, total: 401),
      fingerprint: 'charleroi-401',
    );
    expect(
      quote.displayTotalPrice,
      401,
      reason: 'the wrong server total must stay visible, not be rewritten to 400',
    );
  });

  test('a correct 200 + 200 roundtrip totals 400 and is consistent', () {
    final quote = parseCompanyPlanQuote(
      charleroiRoundTripWire(main: 200, ret: 200, total: 400),
      fingerprint: 'charleroi-400',
    );
    expect(quote.totalCheck.consistent, isTrue);
    expect(quote.totalCheck.legSumCents, 40000);
    expect(quote.displayTotalPrice, 400);
  });

  test('an inconsistent total blocks Confirm with a visible reason', () {
    final quote = parseCompanyPlanQuote(
      charleroiRoundTripWire(main: 200, ret: 200, total: 401),
      fingerprint: 'charleroi-401',
    );
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
    expect(
      issues.map((issue) => issue.code),
      contains(kCustomerBookingIssuePriceInconsistent),
    );
  });

  test('a consistent total raises no price issue', () {
    final quote = parseCompanyPlanQuote(
      charleroiRoundTripWire(main: 200, ret: 200, total: 400),
      fingerprint: 'charleroi-400',
    );
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
    expect(
      issues.map((issue) => issue.code),
      isNot(contains(kCustomerBookingIssuePriceInconsistent)),
    );
  });

  test('a single leg quote is not comparable and stays bookable', () {
    final quote = parseCompanyPlanQuote(
      <String, dynamic>{
        'ok': true,
        'price_incl_vat': 200,
        'total_price_incl_vat': 200,
        'distance_km': 118.4,
        'duration_min': 92,
        'currency': 'EUR',
        'price_available': true,
      },
      fingerprint: 'single-200',
    );
    expect(quote.totalCheck.comparable, isFalse);
    expect(quote.totalCheck.consistent, isTrue);
    expect(quote.displayTotalPrice, 200);
  });

  test('the airport review page reads the same check from the wire map', () {
    final inconsistent = companyPlanQuoteTotalCheckFromWire(
      charleroiRoundTripWire(main: 200, ret: 200, total: 401),
    );
    expect(inconsistent.consistent, isFalse);
    expect(inconsistent.driftCents, 100);

    final nested = companyPlanQuoteTotalCheckFromWire(<String, dynamic>{
      'ok': true,
      'price_incl_vat_main': 200,
      'return': <String, dynamic>{'price_incl_vat': 200},
      'total_price_incl_vat': 401,
    });
    expect(nested.consistent, isFalse);
    expect(nested.legSumCents, 40000);
  });

  test('two separately quoted legs merge into a consistent 400 total', () {
    const outbound = CompanyPlanQuoteResult(
      fingerprint: 'out',
      priceInclVat: 200,
      outboundPriceInclVat: 200,
      totalPriceInclVat: 200,
      distanceKm: 118.4,
      durationMin: 92,
      priceAvailable: true,
    );
    const inbound = CompanyPlanQuoteResult(
      fingerprint: 'in',
      priceInclVat: 200,
      outboundPriceInclVat: 200,
      totalPriceInclVat: 200,
      distanceKm: 118.4,
      durationMin: 95,
      priceAvailable: true,
    );
    final merged = companyPlanMergeLegQuotes(
      outbound: outbound,
      inbound: inbound,
    );
    expect(merged.displayTotalPrice, 400);
    expect(merged.totalCheck.consistent, isTrue);
    expect(merged.totalCheck.legSumCents, 40000);
  });
}
