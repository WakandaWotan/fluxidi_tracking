import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_selector.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking.dart';
import 'package:fluxidi_tracking/limousine/limousine_accepted_booking_resume.dart';
import 'package:fluxidi_tracking/limousine/limousine_airport_transfer_fields.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_journey_scope.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1c_journey.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_unified_intent.dart';

LimousinePublishedOffer _offer({
  required String id,
  required List<String> journeyTypes,
  String presentation = 'quote_required',
  int sourceRevision = 4,
  String vehicleId = 'veh_1',
}) {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': id,
    'target_type': 'vehicle',
    'vehicle_id': vehicleId,
    'service_class_id': 'executive_sedan',
    'title': {'nl': id, 'en': id},
    'description': {'nl': 'Incl. btw', 'en': 'Incl. VAT'},
    'journey_types': journeyTypes,
    'price_presentation': presentation,
    'display_amount_cents': 45000,
    'currency': 'EUR',
    'source_revision': sourceRevision,
    'vehicle': {'passenger_capacity': 3, 'luggage_capacity': 2},
  });
}

class _Gateway with LimousineCustomerQuoteGateway {
  _Gateway({this.rejectJourneyType = false});

  final bool rejectJourneyType;
  int createCalls = 0;
  int bookCalls = 0;

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async {
    return const [
      LimousineDiscoveredProvider(
        partnerId: 'p1',
        companyName: 'Coachline',
        limousineAvailable: true,
      ),
    ];
  }

  @override
  Future<LimousineProviderDetail> loadProvider(String publicPartnerId) async {
    return LimousineProviderDetail(
      provider: const LimousineDiscoveredProvider(
        partnerId: 'p1',
        companyName: 'Coachline',
        limousineAvailable: true,
      ),
      offers: [_offer(id: 'off_1', journeyTypes: const ['event_transfer'])],
    );
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    createCalls += 1;
    if (rejectJourneyType) {
      throw const LimousineCustomerQuoteException(
        code: 'journey_type_not_allowed',
        statusCode: 400,
      );
    }
    return LimousineQuoteCreateResult(
      request: LimousineQuoteRequest.fromJson(<String, dynamic>{
        'quote_request_id': 'limq_1',
        'state': 'requested',
        'revision': 1,
        'offer_id': draft.offerId,
        'journey_type': draft.journeyType,
        'from': draft.from,
        'to': draft.to,
        'scheduled_pickup_iso': draft.scheduledPickupIso,
      }),
    );
  }

  @override
  Future<LimousineBookingRequestResult> createBookingRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    bookCalls += 1;
    if (rejectJourneyType) {
      throw const LimousineCustomerQuoteException(
        code: 'journey_type_not_allowed',
        statusCode: 400,
      );
    }
    return const LimousineBookingRequestResult(bookingId: 'b1');
  }

  @override
  Future<LimousineQuoteRequest> pollStatus(String statusRef) async {
    throw const LimousineCustomerQuoteException(code: 'not_found');
  }

  @override
  Future<LimousineQuoteAcceptResult> accept({
    required String quoteRequestId,
    required int expectedRevision,
    required int termsRevision,
  }) async {
    throw const LimousineCustomerQuoteException(code: 'not_found');
  }
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: kLimousineSmX400Portrait),
      child: child,
    ),
  );
}

Future<LimousineCustomerQuoteController> _pumpScopedWizard(
  WidgetTester tester, {
  required LimousinePublishedOffer offer,
  _Gateway? gateway,
}) async {
  final controller = LimousineCustomerQuoteController(
    gateway: gateway ?? _Gateway(),
  );
  await tester.pumpWidget(
    _app(
      LimousineCustomerQuotePage(
        entryEnabled: true,
        controller: controller,
        initialPublicPartnerId: 'p1',
        initialOffer: offer,
        initialCompanyName: 'Coachline',
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('explicit published scope never silently expands to all types', () {
    final scoped = _offer(
      id: 'off_event',
      journeyTypes: const ['event_transfer'],
    );
    expect(
      limousinePublishedJourneyScopeOf(scoped.journeyTypes),
      ['event_transfer'],
    );
    expect(scoped.supportsJourney('event_transfer'), isTrue);
    expect(scoped.supportsJourney('airport_transfer'), isFalse);
    expect(scoped.supportsJourney('point_to_point'), isFalse);
    expect(
      limousineHasExplicitPublishedJourneyScope(const <String>[]),
      isFalse,
    );
    expect(
      limousinePublishedJourneyScopeOf(const <String>[]),
      LimousineJourneyTypeId.all,
    );
  });

  testWidgets('1) event-only offer auto-selects only Eventtransfer', (
    tester,
  ) async {
    final controller = await _pumpScopedWizard(
      tester,
      offer: _offer(id: 'off_event', journeyTypes: const ['event_transfer']),
    );
    expect(controller.draft.journeyType, 'event_transfer');
    expect(controller.draft.offerId, 'off_event');
    expect(find.byKey(kLimousineJourneyTypeScopeSingleKey), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_event_transfer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_airport_transfer')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_hotel_transfer')),
      findsNothing,
    );
    expect(find.byKey(kLimousineAirportToDirectionKey), findsNothing);
    expect(find.byKey(kLimousineHotelFieldKey), findsNothing);
  });

  testWidgets('2) airport-only offer shows the shared airport catalog', (
    tester,
  ) async {
    final controller = await _pumpScopedWizard(
      tester,
      offer: _offer(id: 'off_air', journeyTypes: const ['airport_transfer']),
    );
    expect(controller.draft.journeyType, 'airport_transfer');
    expect(find.byKey(kLimousineAirportToDirectionKey), findsOneWidget);
    expect(find.byKey(kSharedAirportCountryDropdownKey), findsOneWidget);
    expect(find.byKey(kLimousineHotelFieldKey), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_event_transfer')),
      findsNothing,
    );
  });

  testWidgets('3) hotel-only offer shows the hotel searcher', (tester) async {
    final controller = await _pumpScopedWizard(
      tester,
      offer: _offer(id: 'off_hotel', journeyTypes: const ['hotel_transfer']),
    );
    expect(controller.draft.journeyType, 'hotel_transfer');
    expect(find.byKey(kLimousineHotelFieldKey), findsOneWidget);
    expect(find.byKey(kLimousineAirportToDirectionKey), findsNothing);
  });

  testWidgets('4) point-to-point-only offer hides airport and hotel fields', (
    tester,
  ) async {
    final controller = await _pumpScopedWizard(
      tester,
      offer: _offer(id: 'off_p2p', journeyTypes: const ['point_to_point']),
    );
    expect(controller.draft.journeyType, 'point_to_point');
    expect(find.byKey(kLimousineAirportToDirectionKey), findsNothing);
    expect(find.byKey(kLimousineHotelFieldKey), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_hourly_package')),
      findsNothing,
    );
  });

  testWidgets('5) hourly-package-only offer shows duration, not airport/hotel', (
    tester,
  ) async {
    final controller = await _pumpScopedWizard(
      tester,
      offer: _offer(id: 'off_hour', journeyTypes: const ['hourly_package']),
    );
    expect(controller.draft.journeyType, 'hourly_package');
    expect(find.textContaining('Gevraagde duur'), findsWidgets);
    expect(find.byKey(kLimousineAirportToDirectionKey), findsNothing);
    expect(find.byKey(kLimousineHotelFieldKey), findsNothing);
  });

  testWidgets('6) multiple checked types show exactly that subset', (
    tester,
  ) async {
    await _pumpScopedWizard(
      tester,
      offer: _offer(
        id: 'off_multi',
        journeyTypes: const ['event_transfer', 'hotel_transfer'],
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_event_transfer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_hotel_transfer')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_airport_transfer')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('limousine_journey_type_point_to_point')),
      findsNothing,
    );
    expect(find.byKey(kLimousineJourneyTypeScopeSingleKey), findsNothing);
  });

  test('7) two offers on the same vehicle keep their own CTA scope', () {
    final event = _offer(
      id: 'off_event',
      journeyTypes: const ['event_transfer'],
      vehicleId: 'veh_shared',
    );
    final airport = _offer(
      id: 'off_air',
      journeyTypes: const ['airport_transfer'],
      vehicleId: 'veh_shared',
    );
    final first = LimousineCustomerQuoteController(gateway: _Gateway())
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: event,
        companyName: 'Coachline',
      );
    final second = LimousineCustomerQuoteController(gateway: _Gateway())
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: airport,
        companyName: 'Coachline',
      );
    expect(first.draft.offerId, 'off_event');
    expect(first.draft.journeyType, 'event_transfer');
    expect(first.publishedJourneyScopeForSelectedOffer(), ['event_transfer']);
    expect(second.draft.offerId, 'off_air');
    expect(second.draft.journeyType, 'airport_transfer');
    expect(second.publishedJourneyScopeForSelectedOffer(), [
      'airport_transfer',
    ]);
    first.dispose();
    second.dispose();
  });

  test('8/9) working edits stay private until publish', () {
    final vehicles = <VehicleProfile>[
      const VehicleProfile(
        id: 'vh_1',
        vehicleName: 'Fleet One',
        brandModel: 'Mercedes',
        licensePlate: '1-ABC-123',
        color: 'Black',
        passengerCapacity: 3,
        luggageCapacity: 2,
        tierId: 'premium',
        isActive: true,
        driverId: null,
        primaryPhotoRef: '',
        galleryPhotoRefs: <String>[],
        serviceCategory: 'limousine',
        serviceClassId: 'executive_sedan',
      ),
    ];
    final working = <String, dynamic>{
      'offer_id': 'off_draft',
      'enabled': true,
      'published': false,
      'target_type': LimousineOfferTarget.serviceClass,
      'service_class_id': 'executive_sedan',
      'price_presentation': LimousinePricePresentation.quoteRequired,
      'currency': 'EUR',
      'journey_types': <String>['airport_transfer'],
      'title': {'nl': 'Draft', 'en': 'Draft', 'fr': 'Draft', 'es': 'Draft'},
      'source_revision': 1,
    };
    final live = <String, dynamic>{
      ...working,
      'offer_id': 'off_live',
      'published': true,
      'journey_types': <String>['event_transfer'],
    };
    final before = buildSafePublicLimousineOffers(
      <Map<String, dynamic>>[working, live],
      eligible: true,
      readiness: true,
      vehicles: vehicles,
      knownClassIds: const <String>['executive_sedan'],
    );
    expect(before.map((o) => o['offer_id']), ['off_live']);
    expect(before.single['journey_types'], ['event_transfer']);

    final after = buildSafePublicLimousineOffers(
      <Map<String, dynamic>>[
        <String, dynamic>{...working, 'published': true},
        live,
      ],
      eligible: true,
      readiness: true,
      vehicles: vehicles,
      knownClassIds: const <String>['executive_sedan'],
    );
    expect(after.map((o) => o['offer_id']), containsAll(['off_draft', 'off_live']));
    expect(
      after.firstWhere((o) => o['offer_id'] == 'off_draft')['journey_types'],
      ['airport_transfer'],
    );
  });

  test('10) selected type survives back navigation, review and resume', () {
    final offer = _offer(
      id: 'off_event',
      journeyTypes: const ['event_transfer'],
    );
    final controller = LimousineCustomerQuoteController(gateway: _Gateway())
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: offer,
        companyName: 'Coachline',
      )
      ..updateDraft(
        const LimousineQuoteCreateDraft(
          publicPartnerId: 'p1',
          offerId: 'off_event',
          journeyType: 'event_transfer',
          from: 'Gent',
          to: 'Brussel',
          scheduledPickupIso: '2026-09-01T10:00:00Z',
        ),
      )
      ..goTo(LimousineCustomerQuoteStep.detailsExtras)
      ..goTo(LimousineCustomerQuoteStep.reviewRequest)
      ..goTo(LimousineCustomerQuoteStep.journey);
    expect(controller.draft.journeyType, 'event_transfer');
    final rows = buildLimousineRequestReviewRows(
      draft: controller.draft,
      language: AppLanguage.nl,
      providerName: 'Coachline',
      offer: offer,
    );
    expect(
      rows.firstWhere((row) => row.id == 'journey_type').value,
      kLimousineJourneyTypeLabels['event_transfer']!.nl,
    );

    final envelope = parseLimousineAcceptedBookingResumeEnvelope(<String, dynamic>{
      'schema_version': kLimousineAcceptedBookingResumeSchemaVersion,
      'acceptance_reference': 'limacc1.dGVzdGl2MTIz.dGVzdGNpcGhlcnRleHQxMjM',
      'quote_request_id': 'limq_1',
      'quote_revision': 3,
      'terms_revision': 3,
      'total_incl_vat_cents': 45000,
      'currency': 'EUR',
      'offer_id': 'off_event',
      'public_partner_id': 'p1',
      'tenant_id': 't1',
      'company_id': 'c1',
      'customer_id': 'cust_1',
      'from': 'Gent',
      'to': 'Brussel',
      'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
      'created_at': '2026-08-17T12:00:00Z',
      'expires_at': '2099-01-01T00:00:00Z',
      'draft': <String, dynamic>{
        'public_partner_id': 'p1',
        'offer_id': 'off_event',
        'journey_type': 'event_transfer',
        'from': 'Gent',
        'to': 'Brussel',
        'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
      },
      'review': <String, dynamic>{
        'provider_name': 'Coachline',
        'offer_title': 'Event',
        'journey_type': 'event_transfer',
        'from': 'Gent',
        'to': 'Brussel',
        'scheduled_pickup_iso': '2026-09-01T10:00:00Z',
        'total_incl_vat_cents': 45000,
        'currency': 'EUR',
        'terms_revision': 3,
      },
    });
    expect(envelope, isNotNull);
    expect(envelope!.draft.journeyType, 'event_transfer');
    expect(envelope.review.journeyType, 'event_transfer');
    controller.dispose();
  });

  test('11/12) forged or stale client types fail closed without switching', () {
    final offer = _offer(
      id: 'off_event',
      journeyTypes: const ['event_transfer'],
      sourceRevision: 4,
    );
    final errors = validateLimousineCustomerDraft(
      const LimousineQuoteCreateDraft(
        publicPartnerId: 'p1',
        offerId: 'off_event',
        journeyType: 'airport_transfer',
        from: 'Gent',
        to: 'Brussel',
        scheduledPickupIso: '2026-09-01T10:00:00Z',
      ),
      offer: offer,
    );
    expect(errors, contains(LimousineCustomerDraftError.unsupportedJourney));

    final controller = LimousineCustomerQuoteController(gateway: _Gateway())
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: offer,
        companyName: 'Coachline',
      );
    expect(controller.draft.journeyType, 'event_transfer');
    controller.applyLivePublishedOffer(
      _offer(
        id: 'off_event',
        journeyTypes: const ['hotel_transfer'],
        sourceRevision: 5,
      ),
    );
    expect(controller.offerScopeChanged, isTrue);
    expect(controller.draft.journeyType, 'event_transfer');
    expect(controller.draft.offerId, 'off_event');
    controller.dispose();
  });

  testWidgets('11b) server 4xx for a forged type does not create a quote', (
    tester,
  ) async {
    final gateway = _Gateway(rejectJourneyType: true);
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(
          id: 'off_event',
          journeyTypes: const ['event_transfer', 'airport_transfer'],
        ),
        companyName: 'Coachline',
      )
      ..updateDraft(
        const LimousineQuoteCreateDraft(
          publicPartnerId: 'p1',
          offerId: 'off_event',
          journeyType: 'airport_transfer',
          from: 'Gent',
          to: 'Brussel',
          scheduledPickupIso: '2026-09-01T10:00:00Z',
        ),
      );
    final submitted = await controller.submitRequest();
    expect(submitted, isFalse);
    expect(gateway.createCalls, 1);
    expect(gateway.bookCalls, 0);
    expect(controller.offerScopeChanged, isTrue);
    expect(controller.request, isNull);
    expect(controller.bookingRequestId, isEmpty);
    controller.dispose();
  });

  test('13) identical scoped drafts stay idempotent', () {
    const draft = LimousineQuoteCreateDraft(
      publicPartnerId: 'p1',
      offerId: 'off_event',
      journeyType: 'event_transfer',
      from: 'Gent',
      to: 'Brussel',
      scheduledPickupIso: '2026-09-01T10:00:00Z',
    );
    expect(limousineCustomerCreateBody(draft), limousineCustomerCreateBody(draft));
    expect(limousineCustomerBookBody(draft), limousineCustomerBookBody(draft));
  });

  test('14) tenant B scope cannot authorize tenant A journey types', () {
    final tenantA = _offer(
      id: 'off_a',
      journeyTypes: const ['event_transfer'],
    );
    final tenantB = _offer(
      id: 'off_b',
      journeyTypes: const ['airport_transfer'],
    );
    expect(tenantA.supportsJourney('airport_transfer'), isFalse);
    expect(tenantB.supportsJourney('event_transfer'), isFalse);
    expect(
      validateLimousineCustomerDraft(
        const LimousineQuoteCreateDraft(
          publicPartnerId: 'p_a',
          offerId: 'off_a',
          journeyType: 'airport_transfer',
          from: 'Gent',
          to: 'Brussel',
          scheduledPickupIso: '2026-09-01T10:00:00Z',
        ),
        offer: tenantA,
      ),
      contains(LimousineCustomerDraftError.unsupportedJourney),
    );
  });

  test('15-18) taxi, quote-only and planned-only invariants stay in place', () {
    final quote = File('lib/limousine/limousine_customer_quote.dart').readAsStringSync();
    final worker = File('workers/booking/fluxidi_booking_worker.js').readAsStringSync();
    expect(quote.contains("'service_category': 'limousine'"), isTrue);
    expect(quote.contains('street'), isFalse);
    expect(kLimousineCustomerForbiddenSubmitKeys.contains('total_incl_vat_cents'), isTrue);
    expect(worker.contains('isLimousineServiceToken'), isTrue);
    expect(worker.contains('journey_type_not_allowed'), isTrue);
    expect(
      File('lib/limousine/limousine_customer_quote_page.dart').readAsStringSync(),
      isNot(contains('MaterialPageRoute<void>(builder: (_) => Taxi')),
    );
    final offer = _offer(
      id: 'off_fixed',
      journeyTypes: const ['event_transfer'],
      presentation: 'exact_fixed',
    );
    expect(
      limousinePublishedPricingModeOf(offer),
      LimousinePublishedPricingMode.exactFixed,
    );
    expect(
      limousineCustomerIntentKindOf(offer),
      LimousineCustomerIntentKind.bookingRequest,
    );
  });

  test('new offer editors seed a default journey type; legacy empty stays valid', () {
    expect(
      limousineSeedEditorJourneyTypes(current: const <String>[]),
      <String>{LimousineJourneyTypeId.pointToPoint},
    );
    expect(
      limousineSeedEditorJourneyTypes(
        current: const <String>[],
        hourlyOrPackage: true,
      ),
      <String>{LimousineJourneyTypeId.hourlyPackage},
    );
    expect(
      limousineSeedEditorJourneyTypes(
        current: const <String>['event_transfer'],
      ),
      <String>{LimousineJourneyTypeId.eventTransfer},
    );
    final errors = validateLimousineOffer(
      <String, dynamic>{
        'offer_id': 'off_legacy',
        'enabled': true,
        'published': true,
        'target_type': LimousineOfferTarget.serviceClass,
        'service_class_id': 'executive_sedan',
        'price_presentation': LimousinePricePresentation.quoteRequired,
        'currency': 'EUR',
        'journey_types': <String>[],
        'title': {'nl': 'Legacy', 'en': 'Legacy', 'fr': 'Legacy', 'es': 'Legacy'},
      },
      knownClassIds: const <String>['executive_sedan'],
      readiness: true,
    ).errors;
    expect(errors, isNot(contains(LimousineOfferError.missingJourneyTypes)));
  });
}
