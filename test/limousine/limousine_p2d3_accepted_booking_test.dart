import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_status_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_deactivation.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';

const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

LimousineAcceptedQuoteHandoff _handoff({
  String reference = _acceptRef,
  String partnerId = 'p1',
}) {
  return LimousineAcceptedQuoteHandoff(
    acceptanceReference: reference,
    quoteRequestId: 'limq_1',
    quoteRevision: 3,
    termsRevision: 3,
    totalInclVatCents: 45000,
    currency: 'EUR',
    offerId: 'off_1',
    publicPartnerId: partnerId,
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
  );
}

LimousineQuoteRequest _request({String vehicleId = 'veh_1'}) {
  return LimousineQuoteRequest.fromJson(<String, dynamic>{
    'quote_request_id': 'limq_1',
    'state': 'accepted',
    'revision': 3,
    'offer_id': 'off_1',
    'service_class_id': 'executive_sedan',
    'vehicle_id': vehicleId,
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'roundtrip': false,
    'pax': 2,
    'bags': 1,
    'selected_extra_ids': ['wait'],
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 45000,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'terms_revision': 3,
      'included_services': [
        {
          'item_id': 'water',
          'label': {'en': 'Water'},
        },
      ],
      'paid_extras': [
        {
          'extra_id': 'wait',
          'label': {'en': 'Wait'},
        },
      ],
      'mobilisation_disclosure': {'en': 'Included', 'nl': 'Inbegrepen'},
      'terms': {'terms_revision': 3, 'cancellation_deadline_hours': 24},
    },
  });
}

LimousineQuoteCreateDraft _draft() {
  return const LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    stops: ['Antwerpen'],
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    pax: 2,
    bags: 1,
  );
}

LimousineAcceptedBookingCustomer get _customer =>
    const LimousineAcceptedBookingCustomer(
      sessionToken: 'sess_1',
      customerId: 'cust_1',
      name: 'Ada',
      phone: '+32470000000',
      email: 'ada@example.com',
    );

LimousinePublishedOffer _offer() {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': 'off_1',
    'target_type': 'vehicle',
    'vehicle_id': 'veh_1',
    'service_class_id': 'executive_sedan',
    'title': {
      'nl': 'Executive',
      'en': 'Executive',
      'fr': 'Executive',
      'es': 'Executive',
    },
    'price_presentation': 'quote_required',
    'vehicle': {
      'vehicle_id': 'veh_1',
      'photo_url': 'https://cdn.example/c.webp',
    },
  });
}

class _BookGateway implements LimousineAcceptedBookingGateway {
  int calls = 0;
  Map<String, dynamic>? lastPayload;
  Duration delay = Duration.zero;
  Object? error;
  LimousineAcceptedBookResult result = const LimousineAcceptedBookResult(
    bookingId: 'B-100',
    publicReference: 'FLX-100',
    raw: <String, dynamic>{
      'ok': true,
      'booking_id': 'B-100',
      'public_reference': 'FLX-100',
    },
  );

  @override
  Future<LimousineAcceptedBookResult> book(Map<String, dynamic> payload) async {
    calls += 1;
    lastPayload = payload;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final thrown = error;
    if (thrown != null) {
      if (thrown is Exception) throw thrown;
      throw Exception('$thrown');
    }
    return result;
  }
}

class _QuoteGateway with LimousineCustomerQuoteGateway {
  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async => const [];

  @override
  Future<LimousineProviderDetail> loadProvider(String partnerId) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    throw const LimousineCustomerQuoteException(code: 'unused');
  }
}

class _HttpBookClient extends http.BaseClient {
  int posts = 0;
  String lastUrl = '';
  String lastBody = '';
  bool timeout = false;
  Map<String, dynamic> body = const <String, dynamic>{
    'ok': true,
    'booking_id': 'B-200',
    'public_reference': 'FLX-200',
  };
  int statusCode = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    posts += 1;
    lastUrl = request.url.toString();
    if (request is http.Request) lastBody = request.body;
    if (timeout) throw TimeoutException('book');
    final bytes = utf8.encode(jsonEncode(body));
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      statusCode,
      headers: const {'content-type': 'application/json'},
    );
  }
}

Widget _app(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}

CustomerThemePalette get _palette =>
    paletteForCustomerTheme(CustomerThemeVariant.premiumLight);

LimousineAcceptedBookingController _controller({
  required _BookGateway gateway,
  LimousineAcceptedQuoteHandoff? handoff,
  LimousineCustomerQuoteController? quoteController,
  bool entryEnabled = true,
  LimousineAcceptedBookingCustomer? customer,
}) {
  return LimousineAcceptedBookingController(
    handoff: handoff ?? _handoff(),
    draft: _draft(),
    request: _request(),
    offer: _offer(),
    providerName: 'Coachline',
    entryEnabled: entryEnabled,
    quoteController: quoteController,
    gateway: gateway,
    customerOverride: customer ?? _customer,
    customerLoader: () async => customer ?? _customer,
    persister:
        ({
          required response,
          required requestPayload,
          required customer,
        }) async {},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('1) accepted quote opens the final booking review', (
    tester,
  ) async {
    final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
      ..request = _request()
      ..handoff = _handoff();
    var opened = false;
    await tester.pumpWidget(
      _app(
        LimousineCustomerStatusView(
          controller: quote,
          language: AppLanguage.en,
          palette: _palette,
          onOpenBookingReview: () => opened = true,
        ),
      ),
    );
    expect(find.byKey(kLimousineAcceptedBookingOpenReviewKey), findsOneWidget);
    await tester.tap(find.byKey(kLimousineAcceptedBookingOpenReviewKey));
    await tester.pump();
    expect(opened, isTrue);
    quote.dispose();
  });

  test('2) missing acceptance reference never calls /book', () async {
    final gateway = _BookGateway();
    final controller = _controller(
      gateway: gateway,
      handoff: _handoff(reference: ''),
    );
    controller.setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isFalse);
    expect(gateway.calls, 0);
    expect(
      controller.error,
      LimousineAcceptedBookingError.missingAcceptanceReference,
    );
    controller.dispose();
  });

  testWidgets('3) explicit confirmation is required before submit', (
    tester,
  ) async {
    final gateway = _BookGateway();
    final controller = _controller(gateway: gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineAcceptedBookingPage(
          controller: controller,
          entryEnabled: true,
        ),
      ),
    );
    expect(find.byKey(kLimousineAcceptedBookingReviewKey), findsOneWidget);
    expect(find.text('Coachline'), findsOneWidget);
    expect(find.text('Executive'), findsWidgets);
    expect(find.textContaining('EUR'), findsOneWidget);
    final submit = tester.widget<FilledButton>(
      find.byKey(kLimousineAcceptedBookingSubmitKey),
    );
    expect(submit.onPressed, isNull);
    await tester.tap(find.byKey(kLimousineAcceptedBookingConfirmKey));
    await tester.pump();
    expect(controller.confirmationAcknowledged, isTrue);
    controller.dispose();
  });

  test(
    '4/5) confirm submits exactly one /book and blocks double submit',
    () async {
      final gateway = _BookGateway()..delay = const Duration(milliseconds: 40);
      final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
        ..handoff = _handoff();
      final controller = _controller(gateway: gateway, quoteController: quote);
      controller.setConfirmationAcknowledged(true);
      final first = controller.confirmBooking();
      final second = controller.confirmBooking();
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(gateway.calls, 1);
      expect(controller.bookCalls, 1);
      expect(
        gateway.lastPayload!['limousine_acceptance_reference'],
        _acceptRef,
      );
      expect(gateway.lastPayload!['public_partner_id'], 'p1');
      expect(gateway.lastPayload!['from'], 'Gent');
      expect(gateway.lastPayload!['pickup_iso'], '2026-09-01T10:00:00Z');
      expect(gateway.lastPayload!.containsKey('total_incl_vat_cents'), isFalse);
      expect(gateway.lastPayload!.containsKey('vehicle_id'), isFalse);
      expect(gateway.lastPayload!['payment_mode'], 'manual');
      controller.dispose();
      quote.dispose();
    },
  );

  testWidgets('6) server reference is displayed after success', (tester) async {
    final gateway = _BookGateway();
    final controller = _controller(gateway: gateway);
    controller.setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isTrue);
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineAcceptedBookingPage(
          controller: controller,
          entryEnabled: true,
        ),
      ),
    );
    expect(find.byKey(kLimousineAcceptedBookingSuccessKey), findsOneWidget);
    expect(find.textContaining('FLX-100'), findsOneWidget);
    expect(find.textContaining('limacc1'), findsNothing);
    controller.dispose();
  });

  test('7) handoff clears only after confirmed creation', () async {
    final gateway = _BookGateway();
    final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
      ..handoff = _handoff();
    final controller = _controller(gateway: gateway, quoteController: quote);
    expect(quote.handoff, isNotNull);
    expect(controller.handoffCleared, isFalse);
    controller.setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isTrue);
    expect(quote.handoff, isNull);
    expect(controller.handoffCleared, isTrue);
    controller.dispose();
    quote.dispose();
  });

  test('8) retryable failure retains the safe handoff', () async {
    final gateway = _BookGateway()
      ..error = const LimousineAcceptedBookException(code: 'network');
    final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
      ..handoff = _handoff();
    final controller = _controller(gateway: gateway, quoteController: quote);
    controller.setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isFalse);
    expect(quote.handoff, isNotNull);
    expect(controller.handoffCleared, isFalse);
    expect(
      looksLikeLimousineAcceptanceRef(quote.handoff!.acceptanceReference),
      isTrue,
    );
    controller.dispose();
    quote.dispose();
  });

  test('9) stale/expired/malformed references fail closed', () async {
    final gateway = _BookGateway();
    final malformed = _controller(
      gateway: gateway,
      handoff: _handoff(reference: 'limacc1.onlytwo'),
    )..setConfirmationAcknowledged(true);
    expect(await malformed.confirmBooking(), isFalse);
    expect(gateway.calls, 0);
    malformed.dispose();

    gateway.error = const LimousineAcceptedBookException(
      code: 'acceptance_reference_expired',
    );
    final expired = _controller(gateway: gateway)
      ..setConfirmationAcknowledged(true);
    expect(await expired.confirmBooking(), isFalse);
    expect(
      expired.error,
      LimousineAcceptedBookingError.expiredAcceptanceReference,
    );
    expired.dispose();

    gateway.error = const LimousineAcceptedBookException(
      code: 'limousine_quote_refresh_required',
    );
    final stale = _controller(gateway: gateway)
      ..setConfirmationAcknowledged(true);
    expect(await stale.confirmBooking(), isFalse);
    expect(stale.error, LimousineAcceptedBookingError.staleRevision);
    stale.dispose();
  });

  test('10) client amount is ignored as authority', () {
    final payload = limousineAcceptedBookPayload(
      handoff: _handoff(),
      draft: _draft(),
      customer: _customer,
      request: _request(),
    );
    expect(payload.containsKey('total_incl_vat_cents'), isFalse);
    expect(payload.containsKey('price_incl_vat'), isFalse);
    expect(payload.containsKey('display_amount_cents'), isFalse);
    expect(payload.containsKey('taxi_price'), isFalse);
    expect(payload.containsKey('airport_fixed_fare'), isFalse);
    expect(limousineAcceptedBookPayloadIsSafe(payload), isTrue);
  });

  testWidgets('11) token is never rendered, logged or persisted', (
    tester,
  ) async {
    final gateway = _BookGateway();
    final controller = _controller(gateway: gateway);
    await tester.pumpWidget(
      MaterialApp(
        home: LimousineAcceptedBookingPage(
          controller: controller,
          entryEnabled: true,
        ),
      ),
    );
    expect(find.textContaining('limacc1'), findsNothing);
    controller.setConfirmationAcknowledged(true);
    await controller.confirmBooking();
    expect(controller.logSinkForTests.join(), isNot(contains('limacc1')));
    controller.dispose();
  });

  test('12) logout clears the acceptance handoff', () async {
    final quote = LimousineCustomerQuoteController(gateway: _QuoteGateway())
      ..handoff = _handoff();
    final controller = _controller(
      gateway: _BookGateway(),
      quoteController: quote,
    );
    controller.handleSessionClearedForTests();
    expect(quote.handoff, isNull);
    expect(
      controller.error,
      LimousineAcceptedBookingError.missingCustomerScope,
    );
    expect(
      File(
        'lib/limousine/limousine_accepted_booking_api.dart',
      ).readAsStringSync().contains('addClearedListener(_onSessionCleared)'),
      isTrue,
    );
    controller.dispose();
    quote.dispose();
  });

  test('13) unknown Worker response does not show success', () async {
    final client = _HttpBookClient()
      ..body = <String, dynamic>{'ok': true, 'status': 'maybe'};
    final gateway = HttpLimousineAcceptedBookingGateway(
      client: client,
      authHeaders: () async => const {
        'Authorization': 'Bearer sess_1',
        'Content-Type': 'application/json',
      },
      bookingBaseUrl: 'https://booking.test',
    );
    expect(
      () => gateway.book(
        limousineAcceptedBookPayload(
          handoff: _handoff(),
          draft: _draft(),
          customer: _customer,
        ),
      ),
      throwsA(
        isA<LimousineAcceptedBookException>().having(
          (error) => error.code,
          'code',
          'unknown_response',
        ),
      ),
    );
  });

  test('14) ambiguous timeout does not blindly resubmit', () async {
    final client = _HttpBookClient()..timeout = true;
    final httpGateway = HttpLimousineAcceptedBookingGateway(
      client: client,
      authHeaders: () async => const {
        'Authorization': 'Bearer sess_1',
        'Content-Type': 'application/json',
      },
      bookingBaseUrl: 'https://booking.test',
    );
    final controller = LimousineAcceptedBookingController(
      handoff: _handoff(),
      draft: _draft(),
      request: _request(),
      entryEnabled: true,
      gateway: httpGateway,
      customerOverride: _customer,
      customerLoader: () async => _customer,
      persister:
          ({
            required response,
            required requestPayload,
            required customer,
          }) async {},
    )..setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isFalse);
    expect(controller.phase, LimousineAcceptedBookingPhase.ambiguous);
    expect(client.posts, 1);
    expect(controller.bookCalls, 1);
    controller.dispose();
  });

  test(
    '15) provider deactivation blocks new bookings and preserves existing',
    () async {
      expect(kLimousineDeactivationDecision.stopNewBookings, isTrue);
      expect(kLimousineDeactivationDecision.preserveExistingBookings, isTrue);
      expect(kLimousineDeactivationDecision.preserveHistory, isTrue);
      expect(
        kLimousineDeactivationDecision.disablesUnrelatedTaxiOrAirport,
        isFalse,
      );
      final gateway = _BookGateway()
        ..error = const LimousineAcceptedBookException(code: 'not_eligible');
      final controller = _controller(gateway: gateway)
        ..setConfirmationAcknowledged(true);
      expect(await controller.confirmBooking(), isFalse);
      expect(
        controller.error,
        LimousineAcceptedBookingError.providerUnavailable,
      );
      expect(controller.succeeded, isFalse);
      controller.dispose();
    },
  );

  test('16) taxi and airport booking files stay isolated', () {
    final calculator = File('lib/calculator_page.dart').readAsStringSync();
    final airport = File(
      'lib/airport/airport_booking_review_page.dart',
    ).readAsStringSync();
    expect(calculator.contains('_postBookAndDecode'), isTrue);
    expect(airport.contains('_buildBookPayload'), isTrue);
    expect(calculator.contains('limousine_acceptance_reference'), isFalse);
    expect(airport.contains('limousine_acceptance_reference'), isFalse);
  });

  test('17) NL/EN/FR/ES booking labels exist', () {
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.de) continue;
      expect(kLimousineAcceptedBookingTitle.of(language).trim(), isNotEmpty);
      expect(kLimousineAcceptedBookingConfirm.of(language).trim(), isNotEmpty);
      expect(kLimousineAcceptedBookingSubmit.of(language).trim(), isNotEmpty);
      expect(kLimousineAcceptedBookingCreating.of(language).trim(), isNotEmpty);
      expect(kLimousineAcceptedBookingSuccess.of(language).trim(), isNotEmpty);
      expect(
        kLimousineAcceptedBookingOpenReview.of(language).trim(),
        isNotEmpty,
      );
      expect(
        kLimousineAcceptedBookingErrors[LimousineAcceptedBookingError
                .expiredAcceptanceReference]!
            .of(language)
            .trim(),
        isNotEmpty,
      );
    }
  });

  test('18) showroom stays off /book; quote API reuses existing /book only for booking requests', () {
    final quoteApi = File(
      'lib/limousine/limousine_customer_quote_api.dart',
    ).readAsStringSync();
    expect(quoteApi.contains('/limousine/quote-requests'), isTrue);
    expect(quoteApi.contains("Uri.parse('\$_base/book')"), isTrue);
    expect(
      File(
        'lib/limousine/limousine_public_showroom.dart',
      ).readAsStringSync().contains('/book'),
      isFalse,
    );
    expect(
      File(
        'lib/limousine/limousine_accepted_booking_api.dart',
      ).readAsStringSync().contains('/book'),
      isTrue,
    );
  });

  test('19) marketplace entry remains default OFF', () {
    expect(kLimousineMarketplaceCustomerEntryEnabled, isFalse);
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
    final wrangler = File('workers/booking/wrangler.toml').readAsStringSync();
    expect(wrangler.contains('LIMOUSINE_QUOTE_ENABLED'), isFalse);
    expect(wrangler.contains('LIMOUSINE_BOOK_ENABLED'), isFalse);
    expect(wrangler.contains('LIMOUSINE_MANUAL_QUOTE_ENABLED'), isFalse);
  });

  test('20) HTTP /book uses existing endpoint and auth', () async {
    final client = _HttpBookClient();
    final gateway = HttpLimousineAcceptedBookingGateway(
      client: client,
      authHeaders: () async => const {
        'Authorization': 'Bearer sess_1',
        'Content-Type': 'application/json',
      },
      bookingBaseUrl: 'https://booking.test',
    );
    final result = await gateway.book(
      limousineAcceptedBookPayload(
        handoff: _handoff(),
        draft: _draft(),
        customer: _customer,
      ),
    );
    expect(client.posts, 1);
    expect(client.lastUrl, 'https://booking.test/book');
    expect(result.bookingId, 'B-200');
    expect(result.publicReference, 'FLX-200');
    final decoded = jsonDecode(client.lastBody) as Map;
    expect(decoded['limousine_acceptance_reference'], _acceptRef);
    expect(decoded.containsKey('total_incl_vat_cents'), isFalse);
  });

  test('gate off creates zero booking', () async {
    final gateway = _BookGateway();
    final controller = _controller(gateway: gateway, entryEnabled: false)
      ..setConfirmationAcknowledged(true);
    expect(await controller.confirmBooking(), isFalse);
    expect(gateway.calls, 0);
    expect(controller.error, LimousineAcceptedBookingError.gateOff);
    controller.dispose();
  });
}
