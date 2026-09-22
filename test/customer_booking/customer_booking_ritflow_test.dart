import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_layout.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

LimousineAddressValue _place(
  String text, {
  double lat = 50.85,
  double lon = 4.35,
}) {
  return LimousineAddressValue(
    displayText: text,
    canonicalLabel: text,
    lat: lat,
    lon: lon,
    placeId: 'place:$text',
    acceptance: LimousineAddressAcceptance.selected,
  );
}

bool _bodyHasWait(Map<String, dynamic> body) {
  for (final key in kCompanyRideWaitPayloadKeys) {
    if (body.containsKey(key)) return true;
  }
  final nested = body['ride_options'];
  if (nested is Map) {
    for (final key in kCompanyRideWaitPayloadKeys) {
      if (nested.containsKey(key)) return true;
    }
  }
  return false;
}

void main() {
  test('company banner logo grows on tablet and stays compact on phone', () {
    final tablet = customerBookingCompanyBannerLayout(innerWidth: 640);
    expect(tablet.equalSplit, isTrue);
    expect(tablet.stack, isFalse);
    expect(tablet.logoMaxHeight, kCustomerBookingCompanyLogoTabletMaxHeight);
    expect(tablet.logoMaxWidth, closeTo((640 - 12) / 2, 0.1));
    expect(
      tablet.logoMaxHeight,
      closeTo(kCustomerBookingCompanyLogoHeight * 2, 0.1),
    );

    final phone = customerBookingCompanyBannerLayout(innerWidth: 360);
    expect(phone.equalSplit, isFalse);
    expect(phone.stack, isFalse);
    expect(phone.logoMaxWidth, kCustomerBookingCompanyLogoPhoneWidth);
    expect(phone.logoMaxHeight, kCustomerBookingCompanyLogoPhoneHeight);

    final stacked = customerBookingCompanyBannerLayout(
      innerWidth: 260,
      textScale: 1.6,
    );
    expect(stacked.stack, isTrue);
  });

  test('listed 401 with two 200 legs is reported, not masked as 400', () {
    final parsed = parseCompanyPlanQuote(
      <String, dynamic>{
        'ok': true,
        'price_incl_vat': 200,
        'outbound_price_incl_vat': 200,
        'return_price_incl_vat': 200,
        'total_price_incl_vat': 401,
        'distance_km': 80,
        'duration_min': 55,
        'return_distance_km': 80,
        'return_duration_min': 58,
        'currency': 'EUR',
        'price_available': true,
      },
      fingerprint: 'listed-401',
    );
    expect(parsed.outboundPriceInclVat, 200);
    expect(parsed.returnPriceInclVat, 200);
    expect(parsed.totalPriceInclVat, 401);
    // The wrong server total stays visible; the app reports the drift instead
    // of quietly presenting an invented 400.
    expect(parsed.displayTotalPrice, 401);
    expect(parsed.totalCheck.consistent, isFalse);
    expect(parsed.totalCheck.driftCents, 100);
  });

  test('merged 200+200 stays 400 even if a combined listed total was 401', () {
    const outbound = CompanyPlanQuoteResult(
      fingerprint: 'out',
      priceInclVat: 200,
      outboundPriceInclVat: 200,
      totalPriceInclVat: 200,
      priceAvailable: true,
    );
    const inbound = CompanyPlanQuoteResult(
      fingerprint: 'in',
      priceInclVat: 200,
      outboundPriceInclVat: 200,
      totalPriceInclVat: 200,
      priceAvailable: true,
    );
    final merged = companyPlanMergeLegQuotes(
      outbound: outbound,
      inbound: inbound,
    );
    expect(merged.displayTotalPrice, 400);
    expect(merged.outboundPriceInclVat, 200);
    expect(merged.returnPriceInclVat, 200);
  });

  test('one-way airport quote stays 200', () {
    final parsed = parseCompanyPlanQuote(
      <String, dynamic>{
        'ok': true,
        'price_incl_vat': 200,
        'distance_km': 80,
        'duration_min': 94,
        'currency': 'EUR',
        'price_available': true,
      },
      fingerprint: 'one-way',
    );
    expect(parsed.displayTotalPrice, 200);
    expect(companyPlanQuoteNeedsInboundLeg(parsed), isTrue);
  });

  test('airport quote and stripped book payload omit every wait field', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _place('Koekamerstraat 48A'),
      to: _place('OST', lat: 51.20, lon: 2.86),
      pickupLocal: DateTime(2026, 9, 25, 20, 11),
      options: const CompanyRideOptions(
        service: 'airport',
        airportDirection: 'to_airport',
        waitMin: 90,
      ),
      passengers: 1,
      returnEnabled: true,
      returnPickupLocal: DateTime(2026, 9, 26, 18, 0),
    );
    expect(request, isNotNull);
    expect(_bodyHasWait(request!.body), isFalse);
    expect(request.body['ride_options'], isNot(contains('wait_min')));
    final book = companyRideOptionsStripWaitFields(
      <String, dynamic>{
        'service': 'airport',
        'wait_min': 90,
        'waitMinutes': 90,
        'waiting': true,
        'ride_options': <String, dynamic>{
          'service': 'airport',
          'wait_min': 90,
          'wait_minutes': 90,
        },
      },
    );
    expect(_bodyHasWait(book), isFalse);
  });

  test('ordinary taxi quote still sends wait minutes', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _place('A Straat 1'),
      to: _place('B Straat 2', lat: 50.90, lon: 4.48),
      pickupLocal: DateTime(2026, 9, 25, 12, 0),
      options: const CompanyRideOptions(waitMin: 90),
      passengers: 1,
      returnEnabled: true,
      returnPickupLocal: DateTime(2026, 9, 25, 12, 0),
    );
    expect(request, isNotNull);
    expect(request!.body['wait_min'], 90);
    expect(request.body['ride_options']['wait_min'], 90);
  });

  test('switching taxi wait options to airport clears wait', () {
    const waiting = CompanyRideOptions(service: 'passenger', waitMin: 90);
    final airport = companyRideOptionsWithoutWait(
      waiting.copyWith(service: 'airport'),
    );
    expect(airport.waitMin, 0);
    expect(airport.toJson().containsKey('wait_min'), isFalse);
    expect(waiting.toJson()['wait_min'], 90);
  });
}
