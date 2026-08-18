import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_resume.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_dimensions.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_separation.dart';

const List<String> _kForbiddenLimousineWranglerKeys = <String>[
  'LIMOUSINE_QUOTE_ENABLED',
  'LIMOUSINE_BOOK_ENABLED',
  'LIMOUSINE_MANUAL_QUOTE_ENABLED',
  'LIMOUSINE_TEST_COMPANY_ALLOWLIST',
  'LIMOUSINE_ACCEPTANCE_SECRET',
];

const List<String> _kRatehawkFlutterFiles = <String>[
  'lib/hotels/ratehawk_search.dart',
  'lib/hotels/ratehawk_search_panel.dart',
  'lib/hotels/ratehawk_hotelpage.dart',
  'lib/hotels/ratehawk_hotelpage_panel.dart',
  'lib/hotels/ratehawk_prebook.dart',
  'lib/hotels/ratehawk_prebook_panel.dart',
  'lib/hotels/ratehawk_view_stay.dart',
];

LimousineAcceptedQuoteHandoff _handoff() {
  return const LimousineAcceptedQuoteHandoff(
    acceptanceReference: 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM',
    quoteRequestId: 'limq_1',
    quoteRevision: 3,
    termsRevision: 3,
    totalInclVatCents: 45000,
    currency: 'EUR',
    offerId: 'off_1',
    publicPartnerId: 'p1',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
  );
}

LimousineQuoteCreateDraft _draft() {
  return const LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
  );
}

const LimousineAcceptedBookingCustomer _customer =
    LimousineAcceptedBookingCustomer(
      sessionToken: 'sess_1',
      customerId: 'cust_1',
      name: 'Ada',
      phone: '+32470000000',
      email: 'ada@example.com',
    );

void main() {
  test('marketplace entry default remains OFF without a build define', () {
    expect(
      kLimousineMarketplaceCustomerEntryDefineKey,
      'FLUXIDI_LIMOUSINE_MARKETPLACE_ENTRY',
    );
    expect(kLimousineMarketplaceCustomerEntryEnabled, isFalse);
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
    final source = File(
      'lib/limousine/limousine_customer_entry.dart',
    ).readAsStringSync();
    expect(source.contains('defaultValue: false'), isTrue);
    expect(source.contains('defaultValue: true'), isFalse);
  });

  test('internal APK enablement does not change the source default', () {
    final source = File(
      'lib/limousine/limousine_customer_entry.dart',
    ).readAsStringSync();
    expect(
      source.contains(
        'const bool kLimousineMarketplaceCustomerEntryEnabled = bool.fromEnvironment(\n'
        '  kLimousineMarketplaceCustomerEntryDefineKey,\n'
        '  defaultValue: false,',
      ),
      isTrue,
    );
  });

  test('local wrangler keeps every limousine gate/allowlist/secret absent', () {
    final wrangler = File('workers/booking/wrangler.toml').readAsStringSync();
    for (final key in _kForbiddenLimousineWranglerKeys) {
      expect(wrangler.contains(key), isFalse, reason: key);
    }
    expect(wrangler.contains('RATEHAWK_TEST_PREBOOK_ENABLED = "0"'), isTrue);
  });

  test('committed RateHawk Flutter search/hotelpage/prebook files remain', () {
    for (final path in _kRatehawkFlutterFiles) {
      expect(File(path).existsSync(), isTrue, reason: path);
    }
    final search = File('lib/hotels/ratehawk_search.dart').readAsStringSync();
    expect(search.contains('ratehawk_invocation_blocked'), isTrue);
    final prebook = File('lib/hotels/ratehawk_prebook.dart').readAsStringSync();
    expect(prebook.contains('RatehawkPrebookLifecycleState.blocked'), isTrue);
    final config = File('lib/app_config.dart').readAsStringSync();
    expect(config.contains('fetchPublicRatehawkHotelpage'), isTrue);
    expect(config.contains('fetchPublicRatehawkPrebook'), isTrue);
    expect(config.contains('fetchPublicRatehawkPrebookAccept'), isTrue);
  });

  test('gates-off Flutter entry cannot create a booking', () async {
    final gateway = _NoBookGateway();
    final controller = LimousineAcceptedBookingController(
      gateway: gateway,
      handoff: _handoff(),
      draft: _draft(),
      entryEnabled: false,
      customerOverride: _customer,
    )..setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isFalse);
    expect(gateway.calls, 0);
    expect(controller.error, LimousineAcceptedBookingError.gateOff);
    expect(controller.result, isNull);
    controller.dispose();
  });

  test('gates-off HTTP 404 does not create a booking id', () async {
    final gateway = _StatusGateway(404);
    final controller = LimousineAcceptedBookingController(
      gateway: gateway,
      handoff: _handoff(),
      draft: _draft(),
      entryEnabled: true,
      customerOverride: _customer,
    )..setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isFalse);
    expect(controller.result, isNull);
    controller.dispose();
  });

  test('no taxi fallback and no client total becomes booking authority', () {
    expect(
      limousinePricingForbidsTaxiFallback(LimousineServiceCategory.limousine),
      isTrue,
    );
    expect(
      resolveLimousinePricingMode(const LimousinePricingInputs()).failedClosed,
      isTrue,
    );
    final payload = limousineAcceptedBookPayload(
      handoff: _handoff(),
      draft: _draft(),
      customer: _customer,
    );
    expect(payload.containsKey('total_incl_vat_cents'), isFalse);
    expect(payload.containsKey('total'), isFalse);
    expect(payload.containsKey('client_total'), isFalse);
    expect(
      kLimousineAcceptedBookForbiddenAuthorityKeys.contains(
        'total_incl_vat_cents',
      ),
      isTrue,
    );
    expect(
      kLimousineAcceptedBookForbiddenAuthorityKeys.contains('taxi_price'),
      isTrue,
    );
    expect(payload['limousine_acceptance_reference'], isNotEmpty);
    expect(limousineAcceptedBookPayloadIsSafe(payload), isTrue);
  });

  test('secure-resume isolation remains customer/company/partner scoped', () {
    final resume = File(
      'lib/limousine/limousine_accepted_booking_resume.dart',
    ).readAsStringSync();
    expect(
      resume.contains('class LimousineAcceptedBookingResumeScope'),
      isTrue,
    );
    expect(resume.contains('final String customerId'), isTrue);
    expect(resume.contains('final String? companyId'), isTrue);
    expect(resume.contains('final String? publicPartnerId'), isTrue);
    expect(resume.contains('bool matches('), isTrue);
    expect(
      resume.contains('limousineAcceptedBookingResumeJsonLooksSafe'),
      isTrue,
    );
    expect(
      resume.contains("'LIMOUSINE_ACCEPTANCE_SECRET'"),
      isTrue,
      reason: 'secret name appears only as a forbidden JSON key',
    );
    expect(
      resume.contains("'bearer'"),
      isTrue,
      reason: 'bearer appears only as a forbidden JSON key',
    );
    expect(resume.contains('Mollie'), isFalse);
    expect(
      limousineAcceptedBookingResumeJsonLooksSafe(<String, dynamic>{
        'bearer': 'x',
      }),
      isFalse,
    );
    expect(
      limousineAcceptedBookingResumeJsonLooksSafe(<String, dynamic>{
        'LIMOUSINE_ACCEPTANCE_SECRET': 'x',
      }),
      isFalse,
    );
    expect(
      limousineAcceptedBookingResumeJsonLooksSafe(<String, dynamic>{
        'customer_id': 'cust_1',
        'company_id': 'p1',
        'public_partner_id': 'p1',
      }),
      isTrue,
    );
  });
}

class _NoBookGateway implements LimousineAcceptedBookingGateway {
  int calls = 0;

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    calls += 1;
    throw StateError(
      'gateway must not be called while the Flutter gate is off',
    );
  }
}

class _StatusGateway implements LimousineAcceptedBookingGateway {
  _StatusGateway(this.statusCode);

  final int statusCode;

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    throw LimousineAcceptedBookException(
      code: 'not_found',
      statusCode: statusCode,
    );
  }
}
