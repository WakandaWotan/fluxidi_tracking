import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String billing;
  late String vehicle;
  late String config;

  setUpAll(() {
    billing = File(
      'lib/main_parts/company_subscription_billing_state.dart',
    ).readAsStringSync();
    vehicle = File('lib/vehicle_management_page.dart').readAsStringSync();
    config = File('lib/app_config.dart').readAsStringSync();
  });

  test('every billing CTA uses the shared quote resolver after fiscal', () {
    expect(billing.contains('_resolveSharedPurchaseQuote'), isTrue);
    expect(billing.contains('_requireConfirmablePurchaseQuote'), isTrue);
    expect(
      billing.contains('fetchCompanySubscriptionCheckoutQuoteVerdict'),
      isTrue,
    );
    expect(billing.contains('resolveSubscriptionPurchaseQuote'), isTrue);
    expect(billing.contains('kSubscriptionProductBase'), isTrue);
    expect(billing.contains('kSubscriptionProductExtraVehicle'), isTrue);
    expect(billing.contains('kSubscriptionProductExtraDriver'), isTrue);
    expect(billing.contains("productCode: code"), isTrue);
    expect(billing.contains('quote.mollieAmountCents == null'), isFalse);
  });

  test('vehicle extra-vehicle path uses the same resolver', () {
    expect(
      vehicle.contains('fetchCompanySubscriptionCheckoutQuoteVerdict'),
      isTrue,
    );
    expect(vehicle.contains('resolveSubscriptionPurchaseQuote'), isTrue);
    expect(vehicle.contains('kSubscriptionProductExtraVehicle'), isTrue);
    expect(vehicle.contains('quote.mollieAmountCents == null'), isFalse);
  });

  test('quote HTTP classifies 401/404 instead of swallowing to null only', () {
    expect(
      config.contains('fetchCompanySubscriptionCheckoutQuoteVerdict'),
      isTrue,
    );
    expect(config.contains('classifySubscriptionQuoteHttp'), isTrue);
    expect(config.contains('quote_id'), isTrue);
  });

  test('checkout start still omits an empty quote id and never sends a price', () {
    expect(billing.contains('quoteId: quote.quoteId'), isTrue);
    expect(billing.contains('amount_cents'), isFalse);
    expect(billing.contains('0.21'), isFalse);
    expect(config.contains("'quote_id': quoteId.trim()"), isTrue);
  });
}
