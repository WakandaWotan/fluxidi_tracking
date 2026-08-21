import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_event_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_event_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_transfer_endpoint.dart';
import 'package:fluxidi_tracking/limousine/limousine_wizard_vehicle.dart';

LimousinePublishedOffer _offer({
  String id = 'off_1',
  String vehicleId = 'veh_1',
  List<String> journeyTypes = const <String>['point_to_point'],
  List<Map<String, dynamic>>? vehicles,
  String presentation = 'quote_required',
}) {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': id,
    'target_type': 'vehicle',
    'vehicle_id': vehicleId,
    if (vehicles != null) 'vehicles': vehicles,
    if (vehicles != null)
      'vehicle_ids': vehicles
          .map((item) => item['vehicle_id'])
          .toList(growable: false),
    'service_class_id': 'executive_sedan',
    'title': {'nl': 'Executive', 'en': 'Executive'},
    'description': {'nl': 'Zwarte sedan met chauffeur', 'en': 'Black sedan'},
    'journey_types': journeyTypes,
    'price_presentation': presentation,
    'display_amount_cents': 45000,
    'currency': 'EUR',
    'photo_url': 'https://cdn.example/limo.jpg',
    'vehicle': {
      'passenger_capacity': 3,
      'luggage_capacity': 2,
      'photo_url': 'https://cdn.example/limo.jpg',
    },
  });
}

LimousineQuoteCreateDraft _validDraft({
  String journeyType = 'point_to_point',
  String vehicleId = 'veh_1',
}) {
  return LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    vehicleId: vehicleId,
    journeyType: journeyType,
    from: 'Korenmarkt 1, Gent',
    to: 'Graslei 10, Gent',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    fromEndpoint: const LimousineTransferEndpoint(
      kind: LimousineTransferEndpointKind.address,
      displayName: 'Korenmarkt 1, Gent',
      formattedAddress: 'Korenmarkt 1, Gent',
      latitude: 51.05,
      longitude: 3.72,
      providerPlaceId: 'address.1',
    ),
    toEndpoint: const LimousineTransferEndpoint(
      kind: LimousineTransferEndpointKind.address,
      displayName: 'Graslei 10, Gent',
      formattedAddress: 'Graslei 10, Gent',
      latitude: 51.05,
      longitude: 3.72,
      providerPlaceId: 'address.2',
    ),
  );
}

class _Gateway with LimousineCustomerQuoteGateway {
  _Gateway({this.fail = false, this.delay = Duration.zero});

  int createCalls = 0;
  LimousineQuoteCreateDraft? lastDraft;
  final bool fail;
  final Duration delay;

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
      offers: [_offer()],
    );
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    createCalls += 1;
    lastDraft = draft;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (fail) {
      throw const LimousineCustomerQuoteException(
        code: 'invalid_request',
        statusCode: 400,
        stage: 'validation',
        requestId: 'lsub_p3f_err',
      );
    }
    return LimousineQuoteCreateResult(
      request: LimousineQuoteRequest.fromJson(<String, dynamic>{
        'quote_request_id': 'limq_p3f_1',
        'state': 'requested',
        'revision': 1,
        'offer_id': draft.offerId,
        'journey_type': draft.journeyType,
        'from': draft.from,
        'to': draft.to,
        'scheduled_pickup_iso': draft.scheduledPickupIso,
      }),
      statusRef: 'limqs1.aaa.bbb',
    );
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

Future<void> _pumpReview(
  WidgetTester tester, {
  required LimousineCustomerQuoteController controller,
  LimousineCustomerQuoteGateway? gateway,
  LimousineHotelLookup? hotelLookup,
  LimousineEventLookup? eventLookup,
}) async {
  await tester.pumpWidget(
    _app(
      LimousineCustomerQuotePage(
        controller: controller,
        gateway: gateway,
        hotelLookup: hotelLookup,
        eventLookup: eventLookup,
        entryEnabled: true,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('create body keeps partner, offer, vehicle and journey', () {
    final body = limousineCustomerCreateBody(_validDraft());
    expect(limousineCustomerCreateBodyIsBounded(body), isTrue);
    expect(body['public_partner_id'], 'p1');
    expect(body['offer_id'], 'off_1');
    expect(body['vehicle_id'], 'veh_1');
    expect(body['journey_type'], 'point_to_point');
    expect(kLimousineCustomerForbiddenSubmitKeys.contains('vehicle_id'), isFalse);
  });

  test('one published vehicle skips step 2', () {
    final offer = _offer();
    expect(limousineWizardVehicleOptions(offer), hasLength(1));
    expect(
      limousineWizardVehicleMode(providerOfferLocked: true, offer: offer),
      LimousineWizardVehicleMode.skip,
    );
    expect(
      limousineVisibleWizardSteps(LimousineWizardVehicleMode.skip),
      <LimousineRequestWizardStep>[
        LimousineRequestWizardStep.journey,
        LimousineRequestWizardStep.details,
        LimousineRequestWizardStep.review,
      ],
    );
  });

  test('multiple published vehicles stay on a limousine-only step', () {
    final offer = _offer(
      vehicles: const [
        {
          'vehicle_id': 'veh_a',
          'name': 'Zwarte stretch',
          'service_class_id': 'stretch_limousine',
          'photo_url': 'https://cdn.example/a.jpg',
          'passenger_capacity': 8,
          'luggage_capacity': 6,
          'public_description': {'nl': 'Voor bruiloften'},
        },
        {
          'vehicle_id': 'veh_b',
          'name': 'Witte sedan',
          'service_class_id': 'executive_sedan',
          'photo_url': 'https://cdn.example/b.jpg',
          'passenger_capacity': 3,
          'luggage_capacity': 2,
        },
      ],
    );
    expect(limousineWizardVehicleOptions(offer), hasLength(2));
    expect(
      limousineWizardVehicleMode(providerOfferLocked: true, offer: offer),
      LimousineWizardVehicleMode.choose,
    );
    expect(
      limousineVisibleWizardStepLabel(
        LimousineRequestWizardStep.provider,
        LimousineWizardVehicleMode.choose,
      ).nl,
      'Limousine',
    );
    expect(
      limousineWizardVehicleOptions(offer).first.name,
      isNot(contains('Exact voertuig')),
    );
    expect(
      limousineWizardVehicleOptions(offer).first.name,
      isNot(contains('stretch_limousine')),
    );
  });

  testWidgets('submit button fires exactly one gateway call', (tester) async {
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await _pumpReview(tester, controller: controller, gateway: gateway);
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    expect(controller.request?.quoteRequestId, 'limq_p3f_1');
    expect(find.byKey(kLimousineQuoteSubmitConfirmationKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteSubmitReferenceKey), findsOneWidget);
    expect(find.textContaining('limq_p3f_1'), findsOneWidget);
    expect(
      find.textContaining('Aanvraag verzonden'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Coachline heeft uw aanvraag ontvangen.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(kLimousineQuoteSubmittedHomeKey), findsOneWidget);
    controller.dispose();
  });

  testWidgets('loading blocks a second tap', (tester) async {
    final gateway = _Gateway(delay: const Duration(milliseconds: 80));
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await _pumpReview(tester, controller: controller, gateway: gateway);
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pump();
    expect(find.byKey(kLimousineQuoteSubmitLoadingKey), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(kLimousineCustomerSubmitKey))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    controller.dispose();
  });

  testWidgets('server error stays visible and keeps the draft', (tester) async {
    final gateway = _Gateway(fail: true);
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await _pumpReview(tester, controller: controller, gateway: gateway);
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pumpAndSettle();
    expect(controller.request, isNull);
    expect(controller.draft.from, 'Korenmarkt 1, Gent');
    expect(controller.draft.to, 'Graslei 10, Gent');
    expect(controller.safeError, 'invalid_request');
    expect(controller.lastHttpStatus, 400);
    expect(find.byKey(kLimousineQuoteSubmitErrorKey), findsOneWidget);
    expect(find.byKey(kLimousineCustomerSubmitKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteSubmitConfirmationKey), findsNothing);
    expect(controller.lastRequestId, 'lsub_p3f_err');
    expect(find.textContaining('lsub_p3f_err'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('confirmed success resets only the limousine wizard', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await _pumpReview(tester, controller: controller, gateway: gateway);
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pumpAndSettle();
    expect(controller.request?.quoteRequestId, 'limq_p3f_1');
    await tester.tap(find.byKey(kLimousineQuoteSubmittedHomeKey));
    await tester.pumpAndSettle();
    expect(controller.request, isNull);
    expect(controller.draft.offerId, isEmpty);
    expect(controller.step, LimousineCustomerQuoteStep.journey);
    expect(controller.phase, LimousineCustomerQuotePhase.draft);
    controller.dispose();
  });

  testWidgets('http gateway posts the real quote-requests route once', (
    tester,
  ) async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': false,
          'error': 'invalid_request',
        }),
        400,
        headers: const {'content-type': 'application/json'},
      );
    });
    final gateway = HttpLimousineCustomerQuoteGateway(
      client: client,
      bookingBaseUrl: 'https://booking.test',
      authHeaders: () async => const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    );
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft());
    final ok = await controller.submitRequest();
    expect(ok, isFalse);
    expect(requests, hasLength(1));
    expect(requests.single.method, 'POST');
    expect(
      requests.single.url.toString(),
      'https://booking.test/limousine/quote-requests',
    );
    final rawBody = requests.single is http.Request
        ? (requests.single as http.Request).body
        : '';
    final body = jsonDecode(rawBody) as Map<String, dynamic>;
    expect(body['public_partner_id'], 'p1');
    expect(body['offer_id'], 'off_1');
    expect(body['vehicle_id'], 'veh_1');
    expect(body['journey_type'], 'point_to_point');
    expect(body.containsKey('tenant_id'), isFalse);
    expect(controller.lastHttpStatus, 400);
    expect(controller.safeError, 'invalid_request');
    controller.dispose();
  });

  testWidgets('public offer entry reuses provider/offer and skips step 2', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _offer(),
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.detailsExtras);
    await _pumpReview(tester, controller: controller, gateway: gateway);
    expect(controller.providerOfferLocked, isTrue);
    expect(controller.draft.publicPartnerId, 'p1');
    expect(controller.draft.offerId, 'off_1');
    expect(controller.draft.vehicleId, 'veh_1');
    expect(
      find.byKey(limousineRequestWizardStepKey(LimousineRequestWizardStep.provider)),
      findsNothing,
    );
    expect(find.text('Aanbieder'), findsNothing);
    expect(find.text('Exact voertuig'), findsNothing);
    await tester.tap(find.byKey(kLimousineRequestWizardBackKey));
    await tester.pump();
    expect(controller.step, LimousineCustomerQuoteStep.journey);
    expect(controller.providerOfferLocked, isTrue);
    controller.dispose();
  });

  testWidgets('multiple vehicles show rich real cards', (tester) async {
    final offer = _offer(
      vehicles: const [
        {
          'vehicle_id': 'veh_a',
          'name': 'Zwarte stretch',
          'service_class_id': 'stretch_limousine',
          'photo_url': 'https://cdn.example/a.jpg',
          'passenger_capacity': 8,
          'luggage_capacity': 6,
          'public_description': {'nl': 'Voor bruiloften'},
        },
        {
          'vehicle_id': 'veh_b',
          'name': 'Witte sedan',
          'service_class_id': 'executive_sedan',
          'photo_url': 'https://cdn.example/b.jpg',
          'passenger_capacity': 3,
          'luggage_capacity': 2,
        },
      ],
    );
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: offer,
        companyName: 'Coachline',
      )
      ..updateDraft(_validDraft(vehicleId: ''))
      ..goTo(LimousineCustomerQuoteStep.providerOffer);
    await _pumpReview(tester, controller: controller, gateway: gateway);
    expect(find.byKey(kLimousineWizardVehicleListKey), findsOneWidget);
    expect(find.byKey(limousineWizardVehicleCardKey('veh_a')), findsOneWidget);
    expect(find.text('Zwarte stretch'), findsOneWidget);
    expect(find.text('Voor bruiloften'), findsOneWidget);
    expect(find.text('Exact voertuig'), findsNothing);
    expect(find.text('stretch_limousine'), findsNothing);
    expect(find.text('Aanbieder'), findsNothing);
    controller.dispose();
  });

  testWidgets('hotel searcher fills a typed endpoint', (tester) async {
    final lookup = LimousineHotelLookup(
      searchOverride: (query, language) async {
        return const LimousineHotelLookupResult(
          suggestions: [
            LimousineHotelSuggestion(
              name: 'Hotel de Ville',
              formattedAddress: 'Botermarkt 1, 9000 Gent, Belgium',
              latitude: 51.0543,
              longitude: 3.722,
              providerPlaceId: 'poi.hotel.1',
            ),
          ],
        );
      },
    );
    final field = LimousineHotelFieldController(lookup: lookup);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: LimousineHotelField(
            controller: field,
            label: 'Hotel',
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(kLimousineHotelInputKey), 'ho');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    expect(find.byKey(limousineHotelSuggestionKey(0)), findsOneWidget);
    await tester.tap(find.byKey(limousineHotelSuggestionKey(0)));
    await tester.pump();
    expect(field.selected?.kind, LimousineTransferEndpointKind.hotel);
    expect(field.selected?.hotelName, 'Hotel de Ville');
    expect(field.selected?.providerPlaceId, 'poi.hotel.1');
    expect(field.selected?.manual, isFalse);
    expect(find.byKey(kLimousineHotelSelectedCardKey), findsOneWidget);
    field.dispose();
    lookup.dispose();
  });

  testWidgets('event searcher fills a typed endpoint', (tester) async {
    final lookup = LimousineEventLookup(
      searchOverride: (query, language) async {
        return const LimousineEventLookupResult(
          suggestions: [
            LimousineEventVenueSuggestion(
              name: 'Flanders Expo',
              formattedAddress: 'Maaltekouter 1, 9051 Gent',
              latitude: 51.026,
              longitude: 3.69,
              providerPlaceId: 'poi.event.1',
            ),
          ],
        );
      },
    );
    final field = LimousineEventFieldController(lookup: lookup);
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: LimousineEventField(
            controller: field,
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(kLimousineEventInputKey), 'fl');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    expect(find.byKey(limousineEventSuggestionKey(0)), findsOneWidget);
    await tester.tap(find.byKey(limousineEventSuggestionKey(0)));
    await tester.pump();
    expect(field.selected?.kind, LimousineTransferEndpointKind.event);
    expect(field.selected?.venueName, 'Flanders Expo');
    expect(field.selected?.providerPlaceId, 'poi.event.1');
    expect(field.selected?.manual, isFalse);
    field.dispose();
    lookup.dispose();
  });

  test('manual hotel and event fallbacks keep manual true', () {
    final hotel = limousineManualHotelEndpoint('Korenmarkt 1, Gent');
    expect(hotel.manual, isTrue);
    expect(hotel.kind, LimousineTransferEndpointKind.hotel);
    final event = limousineManualEventEndpoint('Flanders Expo, Gent');
    expect(event.manual, isTrue);
    expect(LimousineTransferEndpointKind.isEvent(event.kind), isTrue);
  });

  test('published journey scope stays exact', () {
    final offer = _offer(journeyTypes: const ['event_transfer']);
    expect(offer.supportsJourney('event_transfer'), isTrue);
    expect(offer.supportsJourney('airport_transfer'), isFalse);
    expect(offer.supportsJourney('hotel_transfer'), isFalse);
    expect(offer.supportsJourney('point_to_point'), isFalse);
    expect(offer.supportsJourney('hourly_package'), isFalse);
  });

  test('airport catalog stays the shared published catalog', () {
    expect(kLimousineHotelMinQueryLength, 2);
    expect(kLimousineEventMinQueryLength, 2);
    expect(
      limousineMapboxSearchCategoryUri(
        category: 'hotel',
        token: 'tok',
        latitude: 51.05,
        longitude: 3.72,
      ).queryParameters['proximity'],
      '3.72,51.05',
    );
  });
}
