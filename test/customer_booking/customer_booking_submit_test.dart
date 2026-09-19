import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_book_result.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_submit.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  const ready = LimousineAddressValue(
    displayText: 'A Straat 1, Brussel',
    canonicalLabel: 'A Straat 1, Brussel',
    lat: 50.85,
    lon: 4.35,
    acceptance: LimousineAddressAcceptance.selected,
  );

  test('confirm stays blocked until route, time, contact and company exist', () {
    final issues = customerBookingSubmitIssues(
      hasCompany: false,
      pickup: const LimousineAddressValue(),
      dropoff: const LimousineAddressValue(),
      whenNow: true,
      pickupLocal: null,
      name: '',
      phone: '',
      quoteLoading: false,
      quote: null,
      quoteError: null,
      successId: null,
    );
    expect(
      issues.map((issue) => issue.code),
      containsAll(<String>[
        kCustomerBookingIssueNeedCompany,
        kCustomerBookingIssueNeedPickup,
        kCustomerBookingIssueNeedDropoff,
        kCustomerBookingIssueNeedName,
        kCustomerBookingIssueNeedPhone,
      ]),
    );
  });

  test('failed price is not shown as on-request', () {
    const quote = CompanyPlanQuoteResult(
      fingerprint: 'q',
      distanceKm: 10,
      durationMin: 20,
      priceAvailable: false,
      calculatorOff: false,
      requestQuoteRequired: false,
    );
    expect(customerBookingQuoteIsOnRequest(quote), isFalse);
    expect(customerBookingQuotePriceFailed(quote), isTrue);
  });

  test('calculator-off remains a real on-request quote', () {
    const quote = CompanyPlanQuoteResult(
      fingerprint: 'q',
      distanceKm: 10,
      durationMin: 20,
      priceAvailable: false,
      calculatorOff: true,
      requestQuoteRequired: true,
    );
    expect(customerBookingQuoteIsOnRequest(quote), isTrue);
    expect(customerBookingQuotePriceFailed(quote), isFalse);
  });

  test('ready addresses still require a quote before book', () {
    final issues = customerBookingSubmitIssues(
      hasCompany: true,
      pickup: ready,
      dropoff: ready,
      whenNow: true,
      pickupLocal: null,
      name: 'Christophe',
      phone: '+32400000000',
      quoteLoading: false,
      quote: null,
      quoteError: null,
      successId: null,
    );
    expect(
      issues.map((issue) => issue.code),
      contains(kCustomerBookingIssueNeedQuote),
    );
  });

  test('success blocks a second confirm', () {
    const quote = CompanyPlanQuoteResult(
      fingerprint: 'q',
      distanceKm: 10,
      durationMin: 20,
      priceAvailable: true,
      priceInclVat: 48,
    );
    final issues = customerBookingSubmitIssues(
      hasCompany: true,
      pickup: ready,
      dropoff: ready,
      whenNow: true,
      pickupLocal: null,
      name: 'Christophe',
      phone: '+32400000000',
      quoteLoading: false,
      quote: quote,
      quoteError: null,
      successId: 'bk_1',
    );
    expect(issues.single.code, kCustomerBookingIssueAlreadyBooked);
  });

  test('a past Later pickup is refused', () {
    final issues = customerBookingSubmitIssues(
      hasCompany: true,
      pickup: ready,
      dropoff: ready,
      whenNow: false,
      pickupLocal: DateTime.now().subtract(const Duration(hours: 2)),
      name: 'Christophe',
      phone: '+32400000000',
      quoteLoading: false,
      quote: const CompanyPlanQuoteResult(
        fingerprint: 'q',
        distanceKm: 10,
        durationMin: 20,
        priceAvailable: true,
        priceInclVat: 48,
      ),
      quoteError: null,
      successId: null,
    );
    expect(
      issues.map((issue) => issue.code),
      contains(kCustomerBookingIssueLaterInvalid),
    );
  });

  test('book errors map to availability, payment and network — not fields', () {
    expect(
      customerBookingBookIssueFromRaw(
        'Niet beschikbaar: geen geschikt voertuig beschikbaar.',
      ),
      kCustomerBookingIssueUnavailable,
    );
    expect(
      customerBookingBookIssueFromRaw('required_vehicle_unavailable'),
      kCustomerBookingIssueUnavailable,
    );
    expect(
      customerBookingBookIssueFromRaw('payment_method_disabled_for_company'),
      kCustomerBookingIssuePayment,
    );
    expect(
      customerBookingBookIssueFromRaw('checkout_url_missing'),
      kCustomerBookingIssueCheckoutStart,
    );
    expect(
      customerBookingBookIssueFromRaw('TimeoutException after 0:00:20'),
      kCustomerBookingIssueNetwork,
    );
    expect(
      customerBookingBookIssueFromRaw('missing fields: from, to'),
      kCustomerBookingIssueNeedRoute,
    );
    expect(
      customerBookingBookIssueFromRaw('Geocode failed'),
      kCustomerBookingIssueFailed,
    );
  });

  test('uncertain network after send is not a field error', () {
    final mapped = customerBookingBookExceptionFromCaught(
      Exception('TimeoutException after 0:00:20'),
    );
    expect(mapped.uncertain, isTrue);
    expect(mapped.sent, isFalse);
    expect(
      customerBookingBookIssueFromException(mapped),
      kCustomerBookingIssueNetwork,
    );
    expect(
      customerBookingSubmitIssueText(
        kCustomerBookingIssueNetwork,
        AppLanguage.nl,
      ),
      isNot(contains('velden')),
    );
  });
}
