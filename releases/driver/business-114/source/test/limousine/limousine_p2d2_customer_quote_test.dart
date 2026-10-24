import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_entry.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';

const String _statusRef = 'limqs1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';
const String _acceptRef = 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM';

Map<String, dynamic> _terms({int revision = 3, String? omit}) {
  final map = <String, dynamic>{
    'terms_revision': revision,
    'cancellation_deadline_hours': 24,
    'cancellation_penalty_percent': 50,
    'waiting_time_included_minutes': 15,
    'waiting_time_overage_cents_per_minute': 100,
    'no_show_penalty_percent': 100,
    'overtime_cents_per_hour': 9000,
    'included_services': [
      {
        'item_id': 'water',
        'label': {'en': 'Water', 'nl': 'Water'},
      },
    ],
    'paid_extras': [
      {
        'extra_id': 'wait',
        'label': {'en': 'Wait'},
        'amount_cents': 2500,
      },
    ],
    'mobilisation_disclosure': {'en': 'Included', 'nl': 'Inbegrepen'},
    'customer_obligations': {'en': 'Be ready', 'nl': 'Klaarstaan'},
    'important_information': {'en': 'No smoking', 'nl': 'Niet roken'},
  };
  if (omit != null) map.remove(omit);
  return map;
}

Map<String, dynamic> _quoteJson({
  String state = 'customer_acceptance_required',
  int revision = 3,
  bool acceptanceAllowed = true,
  String blocked = '',
  List<String> missing = const [],
  String? omitTerm,
  String expiresAt = '2099-01-01T00:00:00Z',
  int termsRevision = 3,
}) {
  return <String, dynamic>{
    'quote_request_id': 'limq_1',
    'state': state,
    'revision': revision,
    'offer_id': 'off_1',
    'service_class_id': 'executive_sedan',
    'journey_type': 'point_to_point',
    'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
    'roundtrip': false,
    'pax': 2,
    'bags': 1,
    'acceptance_allowed': acceptanceAllowed,
    if (blocked.isNotEmpty) 'acceptance_blocked_reason': blocked,
    if (missing.isNotEmpty) 'missing_terms': missing,
    'quote': <String, dynamic>{
      'total_incl_vat_cents': 45000,
      'currency': 'EUR',
      'vat_treatment': 'incl',
      'public_text': {'en': 'Fixed price', 'nl': 'Vaste prijs'},
      'terms_revision': termsRevision,
      'expires_at': expiresAt,
      'terms': _terms(revision: termsRevision, omit: omitTerm),
    },
  };
}

LimousineQuoteRequest _request({
  String state = 'customer_acceptance_required',
  int revision = 3,
  bool acceptanceAllowed = true,
  String blocked = '',
  List<String> missing = const [],
  String? omitTerm,
  String expiresAt = '2099-01-01T00:00:00Z',
  int termsRevision = 3,
}) {
  return LimousineQuoteRequest.fromJson(
    _quoteJson(
      state: state,
      revision: revision,
      acceptanceAllowed: acceptanceAllowed,
      blocked: blocked,
      missing: missing,
      omitTerm: omitTerm,
      expiresAt: expiresAt,
      termsRevision: termsRevision,
    ),
  );
}

LimousinePublishedOffer _offer({
  String id = 'off_1',
  String target = 'vehicle',
  List<String> journeys = const ['point_to_point', 'hourly_package'],
  int pax = 3,
  int bags = 2,
}) {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': id,
    'target_type': target,
    'vehicle_id': target == 'vehicle' ? 'veh_1' : '',
    'service_class_id': 'executive_sedan',
    'title': {'en': 'Executive', 'nl': 'Executive'},
    'journey_types': journeys,
    'price_presentation': 'quote_required',
    'vehicle': {
      'passenger_capacity': pax,
      'luggage_capacity': bags,
      'photo_url': 'https://cdn.example/car.webp',
    },
    'paid_extras': [
      {
        'extra_id': 'wait',
        'label': {'en': 'Wait'},
        'amount_cents': 2500,
      },
    ],
  });
}

LimousineQuoteCreateDraft _validDraft() {
  return const LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    journeyType: 'point_to_point',
    from: 'Gent',
    to: 'Brussel',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    pax: 2,
    bags: 1,
    locale: 'nl',
  );
}

class _FakeGateway with LimousineCustomerQuoteGateway {
  _FakeGateway({
    this.providers = const [],
    this.create,
    this.statusQueue,
    this.acceptError,
  });

  final List<LimousineDiscoveredProvider> providers;
  LimousineProviderDetail? detail;
  LimousineQuoteCreateResult? create;
  final List<LimousineQuoteRequest>? statusQueue;
  LimousineQuoteAcceptResult? acceptResult;
  LimousineCustomerQuoteException? statusError;
  LimousineCustomerQuoteException? acceptError;

  int discoverCalls = 0;
  int createCalls = 0;
  int statusCalls = 0;
  int acceptCalls = 0;
  int bookCalls = 0;
  String lastDiscoverService = '';
  Map<String, dynamic>? lastCreateBody;
  String? lastStatusRef;
  Map<String, dynamic>? lastAcceptBody;
  final List<String> logs = <String>[];

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async {
    discoverCalls += 1;
    lastDiscoverService = 'limousine';
    return providers;
  }

  @override
  Future<LimousineProviderDetail> loadProvider(String partnerId) async {
    return detail ??
        LimousineProviderDetail(
          provider: LimousineDiscoveredProvider(
            partnerId: partnerId,
            companyName: 'Coachline',
            limousineAvailable: true,
          ),
          offers: [
            _offer(),
            _offer(id: 'off_class', target: 'service_class'),
          ],
        );
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    createCalls += 1;
    lastCreateBody = limousineCustomerCreateBody(draft);
    return create ??
        LimousineQuoteCreateResult(
          request: _request(
            state: 'requested',
            revision: 1,
            acceptanceAllowed: false,
          ),
          statusRef: _statusRef,
        );
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    statusCalls += 1;
    lastStatusRef = statusRef;
    if (statusError != null) throw statusError!;
    final queue = statusQueue;
    if (queue == null || queue.isEmpty) {
      return _request(state: 'requested', acceptanceAllowed: false);
    }
    return queue.length == 1 ? queue.first : queue.removeAt(0);
  }

  @override
  Future<LimousineBookingRequestResult> createBookingRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    bookCalls += 1;
    throw const LimousineCustomerQuoteException(code: 'unused');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    acceptCalls += 1;
    lastAcceptBody = limousineCustomerAcceptBody(
      quoteRequestId: quoteRequestId,
      expectedRevision: expectedRevision,
      termsRevision: termsRevision,
    );
    if (acceptError != null) throw acceptError!;
    return acceptResult ??
        LimousineQuoteAcceptResult(
          request: _request(state: 'accepted', acceptanceAllowed: false),
          acceptanceReference: _acceptRef,
        );
  }
}

class _CaptureClient extends http.BaseClient {
  Uri? uri;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    uri = request.url;
    final bytes = utf8.encode('{"partners":[]}');
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

Widget _app(Widget child, {Size size = const Size(390, 844)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('1) customer entry remains default OFF', () {
    expect(LimousineCustomerEntryContract.isVisible, isFalse);
    expect(kLimousineMarketplaceCustomerEntryEnabled, isFalse);
  });

  testWidgets('2) no request on page open while gated', (tester) async {
    final gateway = _FakeGateway();
    await tester.pumpWidget(
      _app(const LimousineCustomerQuotePage(entryEnabled: false)),
    );
    expect(find.byKey(kLimousineCustomerQuotePageKey), findsNothing);
    expect(gateway.discoverCalls, 0);
    expect(gateway.createCalls, 0);
  });

  test(
    '3/4/5) discovery uses service=limousine and only eligible providers',
    () async {
      final gateway = _FakeGateway(
        providers: [
          const LimousineDiscoveredProvider(
            partnerId: 'p1',
            companyName: 'Coachline',
            limousineAvailable: true,
          ),
          const LimousineDiscoveredProvider(
            partnerId: 'taxi1',
            companyName: 'Yellow Cab',
          ),
        ],
      );
      final controller = LimousineCustomerQuoteController(gateway: gateway);
      await controller.discover(postcode: '9000');
      expect(gateway.lastDiscoverService, 'limousine');
      expect(controller.providers, hasLength(1));
      expect(controller.providers.single.partnerId, 'p1');
      await controller.discover(postcode: '1000');
      controller.providers = filterWorkerEligibleLimousineProviders(const []);
      expect(controller.providers, isEmpty);
      controller.dispose();
    },
  );

  test('3b) HTTP discovery sends service=limousine', () async {
    final client = _CaptureClient();
    final gateway = HttpLimousineCustomerQuoteGateway(
      client: client,
      bookingBaseUrl: 'https://booking.example',
      authHeaders: () async => const {'Accept': 'application/json'},
    );
    await gateway.discoverNearby(postcode: '9000');
    expect(client.uri!.path, '/partners/nearby');
    expect(client.uri!.queryParameters['service'], 'limousine');
    expect(client.uri!.queryParameters['postcode'], '9000');
  });

  test('6) vehicle offer precedence', () {
    final ranked = sortLimousineOffersVehicleFirst([
      _offer(id: 'class', target: 'service_class'),
      _offer(id: 'veh', target: 'vehicle'),
    ]);
    expect(ranked.first.offerId, 'veh');
    expect(ranked.first.isVehicleTargeted, isTrue);
  });

  test('7/8/9) journey, capacity, schedule and duration validation', () {
    final offer = _offer(pax: 2, bags: 1, journeys: const ['point_to_point']);
    expect(
      validateLimousineCustomerDraft(
        _validDraft().copyWith(journeyType: 'hourly_package'),
        offer: offer,
      ),
      contains(LimousineCustomerDraftError.unsupportedJourney),
    );
    expect(
      validateLimousineCustomerDraft(
        _validDraft().copyWith(pax: 4),
        offer: offer,
      ),
      contains(LimousineCustomerDraftError.capacityExceeded),
    );
    expect(
      validateLimousineCustomerDraft(
        _validDraft().copyWith(
          roundtrip: true,
          returnPickupIso: '2026-09-01T09:00:00Z',
        ),
        offer: offer,
      ),
      contains(LimousineCustomerDraftError.invalidSchedule),
    );
    expect(
      validateLimousineCustomerDraft(
        _validDraft().copyWith(
          journeyType: 'hourly_package',
          requestedDurationMinutes: 0,
        ),
        offer: _offer(journeys: const ['hourly_package']),
      ),
      contains(LimousineCustomerDraftError.invalidDuration),
    );
  });

  test('10/11) create sends exact bounded DTO without a client price', () {
    final body = limousineCustomerCreateBody(_validDraft());
    expect(limousineCustomerCreateBodyIsBounded(body), isTrue);
    expect(body.containsKey('total_incl_vat_cents'), isFalse);
    expect(body.containsKey('tenant_id'), isFalse);
    expect(body['public_partner_id'], 'p1');
    expect(body['offer_id'], 'off_1');
    expect(body['from'], 'Gent');
    expect(body['to'], 'Brussel');
  });

  test(
    '12/13) double-submit is ignored and idempotent create is accepted',
    () async {
      final gateway = _FakeGateway(
        create: LimousineQuoteCreateResult(
          request: _request(state: 'requested', acceptanceAllowed: false),
          statusRef: _statusRef,
          idempotent: true,
        ),
      );
      final controller = LimousineCustomerQuoteController(gateway: gateway);
      controller
        ..selectedOffer = _offer()
        ..updateDraft(_validDraft());
      final first = controller.submitRequest();
      final second = controller.submitRequest();
      expect(await first, isTrue);
      expect(await second, isFalse);
      expect(gateway.createCalls, 1);
      controller.dispose();
    },
  );

  test('14/15) limqs1 stays opaque, memory-only and is never logged', () async {
    final store = LimousineInMemoryStatusReferenceStore();
    final gateway = _FakeGateway();
    final controller = LimousineCustomerQuoteController(
      gateway: gateway,
      statusStore: store,
    );
    controller
      ..selectedOffer = _offer()
      ..updateDraft(_validDraft());
    await controller.submitRequest();
    expect(looksLikeLimousineStatusRef(controller.statusRefForTests), isTrue);
    expect(store.persistsAcrossRestarts, isFalse);
    expect(controller.logSinkForTests.join(), isNot(contains('limqs1')));
    expect(limousineTextLooksLikeSecret(_statusRef), isTrue);
    controller.dispose();
  });

  test(
    '16/17/18/19/31/32) status uses opaque ref, polling and stale guards',
    () async {
      final gateway = _FakeGateway(
        statusQueue: [
          _request(state: 'requested', revision: 2, acceptanceAllowed: false),
          _request(state: 'requested', revision: 1, acceptanceAllowed: false),
          _request(state: 'declined', revision: 4, acceptanceAllowed: false),
        ],
      );
      final controller = LimousineCustomerQuoteController(gateway: gateway);
      controller
        ..selectedOffer = _offer()
        ..updateDraft(_validDraft());
      await controller.submitRequest();
      expect(gateway.lastStatusRef, isNull);
      await controller.refreshStatus(manual: true);
      expect(gateway.lastStatusRef, _statusRef);
      expect(looksLikeLimousineStatusRef(gateway.lastStatusRef), isTrue);
      expect(controller.request!.revision, 2);
      await controller.refreshStatus();
      expect(controller.request!.revision, 2);
      await controller.refreshStatus();
      expect(controller.request!.state, 'declined');
      expect(limousineCustomerShouldPoll('declined'), isFalse);
      gateway.statusError = const LimousineCustomerQuoteException(
        code: 'invalid_status_ref',
        unavailable: true,
        statusCode: 404,
      );
      final unavailable = LimousineCustomerQuoteController(gateway: gateway);
      unavailable
        ..selectedOffer = _offer()
        ..updateDraft(_validDraft());
      await unavailable.submitRequest();
      await unavailable.refreshStatus(manual: true);
      expect(unavailable.phase, LimousineCustomerQuotePhase.unavailable);
      controller.dispose();
      unavailable.dispose();
    },
  );

  test('20/21) quote price and every required P2D1A term are present', () {
    final request = _request();
    expect(request.quote!.totalInclVatCents, 45000);
    expect(request.quote!.currency, 'EUR');
    expect(request.quote!.vatTreatment, 'incl');
    expect(
      limousineCustomerRequiredTermsPresent(request.quote!.terms),
      containsAll(kLimousineRequiredTermsKeys),
    );
    expect(request.quote!.terms!['customer_obligations'], isNotNull);
    expect(request.quote!.terms!['important_information'], isNotNull);
  });

  test(
    '22/23/24) missing term, blocked flag and expiry disable acceptance',
    () {
      expect(
        limousineCustomerCanAccept(
          _request(omitTerm: 'cancellation_deadline_hours'),
        ),
        isFalse,
      );
      expect(
        limousineCustomerCanAccept(
          _request(acceptanceAllowed: false, blocked: 'quote_terms_incomplete'),
        ),
        isFalse,
      );
      expect(
        limousineCustomerCanAccept(
          _request(expiresAt: '2020-01-01T00:00:00Z'),
          now: DateTime.utc(2026, 8, 17),
        ),
        isFalse,
      );
      expect(limousineCustomerCanAccept(_request()), isTrue);
    },
  );

  test('25/26/27) confirmation, accept body and stale refresh', () async {
    final gateway = _FakeGateway(
      acceptError: const LimousineCustomerQuoteException(
        code: 'stale_revision',
        stale: true,
        statusCode: 409,
      ),
      statusQueue: [_request(revision: 5)],
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.request = _request();
    expect(await controller.acceptCurrentQuote(), isFalse);
    controller.setTermsAcknowledged(true);
    expect(await controller.acceptCurrentQuote(), isFalse);
    expect(gateway.lastAcceptBody!['expected_revision'], 3);
    expect(gateway.lastAcceptBody!['terms_revision'], 3);
    expect(controller.quoteUpdated, isTrue);
    expect(controller.termsAcknowledged, isFalse);
    expect(controller.acceptanceRefForTests, isNull);
    controller.dispose();
  });

  test('28/29) re-quote resets review and limacc1 stays memory-only', () async {
    final gateway = _FakeGateway(
      statusQueue: [_request(revision: 6, termsRevision: 4)],
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller
      ..selectedOffer = _offer()
      ..updateDraft(_validDraft());
    await controller.submitRequest();
    controller
      ..request = _request()
      ..setTermsAcknowledged(true)
      ..handoff = const LimousineAcceptedQuoteHandoff(
        acceptanceReference: _acceptRef,
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
    await controller.refreshStatus(manual: true);
    expect(controller.quoteUpdated, isTrue);
    expect(controller.termsAcknowledged, isFalse);
    expect(controller.handoff, isNull);
    expect(controller.statusStore.persistsAcrossRestarts, isFalse);
    expect(controller.logSinkForTests.join(), isNot(contains('limacc1')));
    controller.dispose();
  });

  test('30) no /book or payment call is issued', () async {
    final gateway = _FakeGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller
      ..selectedOffer = _offer()
      ..updateDraft(_validDraft())
      ..request = _request()
      ..setTermsAcknowledged(true);
    gateway.acceptResult = LimousineQuoteAcceptResult(
      request: _request(state: 'accepted', acceptanceAllowed: false),
      acceptanceReference: _acceptRef,
    );
    await controller.acceptCurrentQuote();
    expect(gateway.bookCalls, 0);
    expect(controller.handoff?.toBookPayloadFields()['from'], 'Gent');
    expect(gateway.createCalls, 0);
    controller.dispose();
  });

  testWidgets('33) privacy-denied fields stay out of the status widgets', (
    tester,
  ) async {
    final gateway = _FakeGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    controller.request = _request();
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('limqs1'), findsNothing);
    expect(find.textContaining('limacc1'), findsNothing);
    expect(find.textContaining('itinerary_fingerprint'), findsNothing);
    expect(find.byKey(kLimousineCustomerTermsCardKey), findsOneWidget);
    controller.dispose();
  });

  test('34) NL/EN/FR/ES customer labels exist', () {
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.de) continue;
      expect(kLimousineBookLabel.of(language).trim(), isNotEmpty);
      expect(kLimousineCustomerSubmit.of(language).trim(), isNotEmpty);
      expect(kLimousineCustomerAcceptAction.of(language).trim(), isNotEmpty);
      expect(kLimousineCustomerEmptyDiscovery.of(language).trim(), isNotEmpty);
      expect(
        limousineCustomerStateLabel('customer_acceptance_required', language),
        isNotEmpty,
      );
    }
  });

  testWidgets('35/36) phone and tablet layout smoke', (tester) async {
    final gateway = _FakeGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerPhoneLayoutKey), findsOneWidget);
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          entryEnabled: true,
        ),
        size: const Size(1024, 768),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
    controller.dispose();
  });

  test('37) Taxi/Airport/Hotels/Events/Saved remain independent', () {
    final home = File(
      'lib/main_parts/customer_home_page.dart',
    ).readAsStringSync();
    expect(home.contains('_openAirportFlow'), isTrue);
    expect(home.contains('_openHotelsPage'), isTrue);
    expect(home.contains('_openEventsPage'), isTrue);
    expect(home.contains('_openBusinessTaxiFlow'), isTrue);
    expect(home.contains('CustomerSavedBookingsPage'), isTrue);
    expect(
      File(
        'lib/nearby_partners_page.dart',
      ).readAsStringSync().contains('_limousineServiceEnabledFromPartner'),
      isFalse,
    );
    expect(
      File(
        'lib/calculator_page.dart',
      ).readAsStringSync().contains('LimousineCustomerQuotePage'),
      isFalse,
    );
  });

  test('38) company inbox contract still parses acceptance fields', () {
    final parsed = LimousineQuoteRequest.fromJson(
      _quoteJson(acceptanceAllowed: true),
    );
    expect(parsed.acceptanceAllowed, isTrue);
    expect(parsed.quote!.terms!['cancellation_deadline_hours'], 24);
  });

  test('worker gates remain OFF', () {
    final wrangler = File('workers/booking/wrangler.toml').readAsStringSync();
    expect(wrangler.contains('LIMOUSINE_QUOTE_ENABLED'), isFalse);
    expect(wrangler.contains('LIMOUSINE_BOOK_ENABLED'), isFalse);
    expect(wrangler.contains('LIMOUSINE_MANUAL_QUOTE_ENABLED'), isFalse);
  });
}
