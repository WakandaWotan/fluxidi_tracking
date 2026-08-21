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
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1c_journey.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_transfer_endpoint.dart';
import 'package:fluxidi_tracking/limousine/limousine_wizard_vehicle.dart';

LimousinePublishedOffer _dualOffer() {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': 'off_party_hummer',
    'target_type': 'vehicle',
    'vehicle_ids': <String>['veh_party', 'veh_hummer'],
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'veh_party',
        'name': 'Party Limo',
        'service_class_id': 'stretch_limousine',
        'photo_url': 'https://cdn.example/party.jpg',
        'passenger_capacity': 10,
        'luggage_capacity': 4,
      },
      <String, dynamic>{
        'vehicle_id': 'veh_hummer',
        'name': 'Hummer white',
        'service_class_id': 'stretch_limousine',
        'photo_url': 'https://cdn.example/hummer.jpg',
        'passenger_capacity': 8,
        'luggage_capacity': 3,
      },
    ],
    'service_class_id': 'stretch_limousine',
    'title': <String, String>{'nl': 'Party package', 'en': 'Party package'},
    'journey_types': <String>['point_to_point'],
    'price_presentation': 'quote_required',
    'display_amount_cents': 89000,
    'currency': 'EUR',
    'photo_url': 'https://cdn.example/party.jpg',
  });
}

LimousineWizardVehicleOption _hummer() {
  return const LimousineWizardVehicleOption(
    vehicleId: 'veh_hummer',
    name: 'Hummer white',
    serviceClassId: 'stretch_limousine',
    photoUrl: 'https://cdn.example/hummer.jpg',
    passengerCapacity: 8,
    luggageCapacity: 3,
    pricePresentation: 'quote_required',
  );
}

LimousineQuoteCreateDraft _validDraft({String vehicleId = 'veh_hummer'}) {
  return LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_party_hummer',
    vehicleId: vehicleId,
    journeyType: 'point_to_point',
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
  _Gateway();

  int createCalls = 0;
  LimousineQuoteCreateDraft? lastDraft;

  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async {
    return const <LimousineDiscoveredProvider>[];
  }

  @override
  Future<LimousineProviderDetail> loadProvider(String publicPartnerId) async {
    return LimousineProviderDetail(
      provider: const LimousineDiscoveredProvider(
        partnerId: 'p1',
        companyName: 'Coachline',
        limousineAvailable: true,
      ),
      offers: <LimousinePublishedOffer>[_dualOffer()],
    );
  }

  @override
  Future<LimousineQuoteCreateResult> createRequest(
    LimousineQuoteCreateDraft draft,
  ) async {
    createCalls += 1;
    lastDraft = draft;
    return LimousineQuoteCreateResult(
      request: LimousineQuoteRequest.fromJson(<String, dynamic>{
        'quote_request_id': 'limq_p3g_1',
        'state': 'requested',
        'revision': 1,
        'offer_id': draft.offerId,
        'vehicle_id': draft.vehicleId,
        'journey_type': draft.journeyType,
        'vehicle_snapshot': <String, dynamic>{
          'vehicle_id': draft.vehicleId,
          'public_name': 'Hummer white',
          'service_class_id': 'stretch_limousine',
          'photo_url': 'https://cdn.example/hummer.jpg',
          'passenger_capacity': 8,
          'luggage_capacity': 3,
        },
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
    throw const LimousineCustomerQuoteException(code: 'unavailable');
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

Future<void> _pump(
  WidgetTester tester,
  LimousineCustomerQuoteController controller,
  _Gateway gateway,
) async {
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    appLanguageNotifier.value = AppLanguage.nl;
  });

  test('preselected Hummer stays locked on a two-vehicle offer', () {
    expect(
      limousineWizardVehicleMode(
        providerOfferLocked: true,
        offer: _dualOffer(),
        lockedVehicleId: 'veh_hummer',
      ),
      LimousineWizardVehicleMode.locked,
    );
    expect(
      limousineVisibleWizardSteps(LimousineWizardVehicleMode.locked),
      <LimousineRequestWizardStep>[
        LimousineRequestWizardStep.journey,
        LimousineRequestWizardStep.details,
        LimousineRequestWizardStep.review,
      ],
    );
    expect(
      limousineWizardPrimaryAction(
        LimousineRequestWizardStep.journey,
        LimousineWizardVehicleMode.locked,
      ).nl,
      'Verder naar extra’s',
    );
    expect(
      limousineWizardPrimaryAction(
        LimousineRequestWizardStep.journey,
        LimousineWizardVehicleMode.discover,
      ).nl,
      kLimousineJourneyChooseProvider.nl,
    );
  });

  test('company offer without vehicle_id still offers both rich cars', () {
    expect(limousineWizardVehicleOptions(_dualOffer()).map((item) => item.name),
        <String>['Party Limo', 'Hummer white']);
    expect(
      limousineWizardVehicleMode(
        providerOfferLocked: true,
        offer: _dualOffer(),
      ),
      LimousineWizardVehicleMode.choose,
    );
  });

  testWidgets('vehicle-detail entry skips Limousine and keeps Hummer white', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _dualOffer(),
        companyName: 'Coachline',
        vehicleId: 'veh_hummer',
        vehicle: _hummer(),
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.journey);
    await _pump(tester, controller, gateway);
    expect(controller.vehicleLocked, isTrue);
    expect(controller.draft.vehicleId, 'veh_hummer');
    expect(find.text('Aanbieder'), findsNothing);
    expect(find.text('Limousine'), findsNothing);
    expect(find.text('Party Limo'), findsNothing);
    expect(find.text('Kies een aanbieder'), findsNothing);
    expect(find.text('Verder naar extra’s'), findsOneWidget);
    controller.goTo(LimousineCustomerQuoteStep.providerOffer);
    expect(controller.step, isNot(LimousineCustomerQuoteStep.providerOffer));
    controller.selectVehicle('veh_party');
    expect(controller.draft.vehicleId, 'veh_hummer');
    controller.dispose();
  });

  testWidgets('review shows locked Hummer and submits that vehicle_id', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _dualOffer(),
        companyName: 'Coachline',
        vehicleId: 'veh_hummer',
        vehicle: _hummer(),
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await _pump(tester, controller, gateway);
    expect(find.byKey(kLimousineReviewLockedVehicleKey), findsOneWidget);
    expect(find.text('Hummer white'), findsWidgets);
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    expect(gateway.lastDraft?.vehicleId, 'veh_hummer');
    expect(controller.request?.quoteRequestId, 'limq_p3g_1');
    expect(find.byKey(kLimousineQuoteSubmitConfirmationKey), findsOneWidget);
    expect(find.textContaining('limq_p3g_1'), findsOneWidget);
    expect(find.text('Offerteaanvraag verzonden'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('invalid review tap is visible and does not stay silent', (
    tester,
  ) async {
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _dualOffer(),
        companyName: 'Coachline',
        vehicleId: 'veh_hummer',
        vehicle: _hummer(),
      )
      ..updateDraft(_validDraft().copyWith(scheduledPickupIso: ''))
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    await _pump(tester, controller, gateway);
    await tester.tap(find.byKey(kLimousineCustomerSubmitKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 0);
    expect(controller.safeError, isNotEmpty);
    expect(find.byKey(kLimousineQuoteSubmitErrorKey), findsOneWidget);
    expect(find.byKey(kLimousineQuoteSubmitConfirmationKey), findsNothing);
    controller.dispose();
  });

  testWidgets('loading copy is Offerte wordt verzonden', (tester) async {
    final gateway = _Gateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _dualOffer(),
        companyName: 'Coachline',
        vehicleId: 'veh_hummer',
        vehicle: _hummer(),
      )
      ..updateDraft(_validDraft())
      ..goTo(LimousineCustomerQuoteStep.reviewRequest);
    controller.phase = LimousineCustomerQuotePhase.submitting;
    await _pump(tester, controller, gateway);
    expect(find.byKey(kLimousineQuoteSubmitLoadingKey), findsOneWidget);
    expect(find.text('Offerte wordt verzonden…'), findsOneWidget);
    controller.dispose();
  });

  test('http posts locked vehicle_id and treats empty quote_request_id as fail',
      () async {
    final requests = <http.BaseRequest>[];
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'quote_request': <String, dynamic>{
            'state': 'requested',
            'revision': 1,
          },
        }),
        200,
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
        offer: _dualOffer(),
        companyName: 'Coachline',
        vehicleId: 'veh_hummer',
        vehicle: _hummer(),
      )
      ..updateDraft(_validDraft());
    final ok = await controller.submitRequest();
    expect(ok, isFalse);
    expect(controller.safeError, isNotEmpty);
    expect(requests, hasLength(1));
    final body = jsonDecode((requests.single as http.Request).body)
        as Map<String, dynamic>;
    expect(body['vehicle_id'], 'veh_hummer');
    expect(body['offer_id'], 'off_party_hummer');
    expect(body.containsKey('tenant_id'), isFalse);
    controller.dispose();
  });

  test('inbox record keeps the public Hummer snapshot', () {
    final record = LimousineQuoteRequest.fromJson(<String, dynamic>{
      'quote_request_id': 'limq_p3g_1',
      'state': 'requested',
      'revision': 1,
      'vehicle_id': 'veh_hummer',
      'vehicle_snapshot': <String, dynamic>{
        'vehicle_id': 'veh_hummer',
        'public_name': 'Hummer white',
        'service_class_id': 'stretch_limousine',
        'photo_url': 'https://cdn.example/hummer.jpg',
        'passenger_capacity': 8,
        'luggage_capacity': 3,
      },
    });
    expect(record.vehicleId, 'veh_hummer');
    expect(record.publicVehicleName, 'Hummer white');
    expect(record.publicVehiclePhotoUrl, 'https://cdn.example/hummer.jpg');
  });

  test('missing customer session does not silently block a valid draft', () {
    final controller = LimousineCustomerQuoteController(gateway: _Gateway())
      ..applyShowroomSelection(
        publicPartnerId: 'p1',
        offer: _dualOffer(),
        companyName: 'Coachline',
        vehicleId: 'veh_hummer',
        vehicle: _hummer(),
      )
      ..updateDraft(_validDraft());
    expect(controller.validateCurrentDraft(), isTrue);
    controller.dispose();
  });
}
