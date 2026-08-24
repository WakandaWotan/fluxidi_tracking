import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_external_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_presentation.dart';

VehicleProfile _vehicle(String id, String name) {
  return VehicleProfile(
    id: id,
    vehicleName: name,
    brandModel: name,
    licensePlate: '1-TST-001',
    color: 'black',
    passengerCapacity: 8,
    luggageCapacity: 4,
    tierId: 'comfort',
    isActive: true,
    driverId: null,
    companyId: 'company_limo_p3q',
    primaryPhotoRef: '',
    galleryPhotoRefs: const <String>[],
    serviceCategory: 'limousine',
    serviceClassId: 'stretch_limousine',
  );
}

Map<String, dynamic> _offer({
  required String id,
  Map<String, String>? title,
  String? name,
  String presentation = LimousinePricePresentation.quoteRequired,
  String vehicleId = 'veh_limo',
}) {
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': true,
    'vehicle_id': vehicleId,
    'service_class_id': 'stretch_limousine',
    'target_type': LimousineOfferTarget.vehicle,
    'price_presentation': presentation,
    'currency': 'EUR',
    if (title != null) 'title': title,
    if (name != null) 'name': name,
  };
}

class _RecordingGateway implements LimousineExternalQuoteGateway {
  LimousineExternalJourneyDraft? lastJourney;
  int createCalls = 0;

  @override
  Future<LimousineExternalQuoteCreateResult> createExternal({
    required LimousineExternalContactSummary contact,
    required LimousineExternalJourneyDraft request,
    required Map<String, dynamic> quote,
    String? tenantId,
    String? companyId,
  }) async {
    createCalls += 1;
    lastJourney = request;
    return LimousineExternalQuoteCreateResult(
      record: LimousineQuoteRequest.fromJson(<String, dynamic>{
        'quote_request_id': 'limq_own',
        'state': 'customer_acceptance_required',
        'revision': 1,
        'origin_channel': kLimousineExternalOriginChannel,
        'offer_id': request.offerId,
      }),
      invitationUrl: 'https://booking.internal/l/i/token',
      contact: contact,
    );
  }

  @override
  Future<LimousineExternalInvitationResult> invitation({
    required String quoteRequestId,
    required String action,
    String? tenantId,
    String? companyId,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<LimousineExternalContactSummary> contact({
    required String quoteRequestId,
    String? tenantId,
    String? companyId,
  }) async {
    throw UnimplementedError();
  }
}

const LimousinePlaceSuggestion _pickupHit = LimousinePlaceSuggestion(
  label: 'Korenmarkt 1, 9000 Gent, Belgium',
  lat: 51.0543,
  lon: 3.7174,
  placeId: 'poi.pickup',
);

const LimousinePlaceSuggestion _destinationHit = LimousinePlaceSuggestion(
  label: 'Graslei, 9000 Gent, Belgium',
  lat: 51.0549,
  lon: 3.7210,
  placeId: 'poi.destination',
);

const LimousinePlaceSuggestion _stopHit = LimousinePlaceSuggestion(
  label: 'Kouter, 9000 Gent, Belgium',
  lat: 51.0518,
  lon: 3.7226,
  placeId: 'poi.stop',
);

const LimousinePlaceSuggestion _castleHit = LimousinePlaceSuggestion(
  label: 'Kasteel van Laarne, Belgium',
  lat: 51.0290,
  lon: 3.8340,
  placeId: 'poi.castle',
);

class _Lookup extends LimousinePlaceLookup {
  _Lookup({this.error = false})
    : super(
        searchOverride: (query, language) async {
          return const LimousinePlaceLookupResult();
        },
      );

  final bool error;
  final List<String> queries = <String>[];

  @override
  Future<LimousinePlaceLookupResult> search(
    String rawQuery, {
    String language = 'nl',
  }) async {
    queries.add(rawQuery);
    searchesStarted += 1;
    if (error) {
      return const LimousinePlaceLookupResult(hadError: true);
    }
    final query = rawQuery.toLowerCase();
    if (query.contains('gras')) {
      return const LimousinePlaceLookupResult(suggestions: [_destinationHit]);
    }
    if (query.contains('kouter')) {
      return const LimousinePlaceLookupResult(suggestions: [_stopHit]);
    }
    if (query.contains('kasteel') || query.contains('laarne')) {
      return const LimousinePlaceLookupResult(suggestions: [_castleHit]);
    }
    return const LimousinePlaceLookupResult(suggestions: [_pickupHit]);
  }
}

Widget _app(Widget child, {Size size = const Size(390, 1800)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

Future<void> _pumpForm(
  WidgetTester tester, {
  required List<Map<String, dynamic>> offers,
  LimousinePlaceLookup? lookup,
  Size size = const Size(430, 1800),
  LimousineExternalQuoteGateway? gateway,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _app(
      LimousineExternalQuoteCreatePage(
        gateway: gateway ?? _RecordingGateway(),
        offers: offers,
        vehicles: <VehicleProfile>[_vehicle('veh_limo', 'Party Limo')],
        quoteDraft: const LimousineCompanyQuoteDraft(
          totalInclVatCents: 100000,
          currency: 'EUR',
          vatTreatment: 'excl',
          vatRate: 0.06,
          expiresAt: '2099-01-01T00:00:00Z',
        ),
        placeLookup: lookup ?? _Lookup(),
      ),
      size: size,
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
  });

  test('offer catalog labels never expose internal IDs', () {
    final preview = _offer(id: 'limo_test_preview_por_1');
    expect(
      limousineLooksLikeRawVehicleOrOfferId('limo_test_preview_por_1'),
      isTrue,
    );
    expect(
      limousineOfferCatalogDisplayLabel(preview, AppLanguage.nl),
      kLimousineOwnCustomerPriceOnRequest.nl,
    );
    expect(
      limousineOfferCatalogDisplayLabel(preview, AppLanguage.en),
      kLimousineOwnCustomerPriceOnRequest.en,
    );
    expect(
      limousineOfferCatalogDisplayLabel(preview, AppLanguage.fr),
      kLimousineOwnCustomerPriceOnRequest.fr,
    );
    expect(
      limousineOfferCatalogDisplayLabel(preview, AppLanguage.es),
      kLimousineOwnCustomerPriceOnRequest.es,
    );
    expect(
      limousineOfferCatalogDisplayLabel(preview, AppLanguage.nl),
      isNot(contains('limo_test')),
    );
    expect(
      limousineOfferCatalogDisplayLabel(
        _offer(
          id: 'limo_test_preview_por_1',
          title: <String, String>{'nl': 'Avondarrangement'},
        ),
        AppLanguage.nl,
      ),
      'Avondarrangement',
    );
    expect(
      limousineOfferCatalogDisplayLabel(
        _offer(id: 'off_quote', name: 'Wedding package'),
        AppLanguage.en,
      ),
      'Wedding package',
    );
    expect(
      limousineOfferCatalogDisplayLabel(
        _offer(
          id: 'off_from',
          presentation: LimousinePricePresentation.fromPrice,
        ),
        AppLanguage.nl,
      ),
      isNot(contains('off_from')),
    );
    expect(
      limousineOfferSafeDisplayLabel(language: AppLanguage.nl),
      kLimousineOwnCustomerStandardOffer.nl,
    );
    final record = LimousineQuoteRequest.fromJson(<String, dynamic>{
      'quote_request_id': 'limq_1',
      'state': 'requested',
      'revision': 1,
      'offer_id': 'limo_test_preview_por_1',
    });
    expect(
      limousineQuoteOfferDisplay(record, AppLanguage.nl),
      isNot('limo_test_preview_por_1'),
    );
    expect(
      limousineQuoteOfferDisplay(record, AppLanguage.nl).contains('limo_test'),
      isFalse,
    );
    final payload = const LimousineExternalJourneyDraft(
      offerId: 'limo_test_preview_por_1',
      from: 'Korenmarkt 1, Gent, Belgium',
      to: 'Graslei, Gent, Belgium',
    ).toWorkerRequest();
    expect(payload['offer_id'], 'limo_test_preview_por_1');
    expect(payload['from'], isNot(contains('limo_test')));
  });

  test('duplicate offer labels are distinguished without IDs', () {
    final labels = limousineOfferCatalogDisplayLabels(<Map<String, dynamic>>[
      _offer(id: 'limo_test_preview_por_1'),
      _offer(id: 'limo_test_preview_por_2', vehicleId: 'veh_other'),
    ], AppLanguage.nl);
    expect(labels, everyElement(isNot(contains('limo_test'))));
    expect(labels.toSet().length, 2);
  });

  testWidgets('single preview offer auto-selects a human label', (
    tester,
  ) async {
    final gateway = _RecordingGateway();
    await _pumpForm(
      tester,
      gateway: gateway,
      offers: <Map<String, dynamic>>[_offer(id: 'limo_test_preview_por_1')],
    );
    expect(find.text('limo_test_preview_por_1'), findsNothing);
    expect(find.text('Prijs op aanvraag'), findsWidgets);
    expect(find.byKey(kLimousineExternalOfferLabelKey), findsOneWidget);
    await tester.enterText(find.byKey(kLimousineExternalContactNameKey), 'Ada');
    await tester.enterText(
      find.byKey(kLimousineExternalContactEmailKey),
      'ada@example.test',
    );
    await tester.enterText(
      find.byKey(kLimousineExternalPickupKey),
      'Korenmarkt 1, Gent',
    );
    await tester.enterText(
      find.byKey(kLimousineExternalDestinationKey),
      'Graslei, Gent',
    );
    await tester.enterText(find.byKey(kLimousineExternalPaxKey), '8');
    await tester.enterText(find.byKey(kLimousineExternalBagsKey), '2');
    await tester.scrollUntilVisible(
      find.byKey(kLimousineExternalSubmitKey),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(kLimousineExternalSubmitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kLimousineExternalPreviewSendKey));
    await tester.pumpAndSettle();
    expect(gateway.createCalls, 1);
    expect(gateway.lastJourney?.offerId, 'limo_test_preview_por_1');
    expect(gateway.lastJourney?.from, 'Korenmarkt 1, Gent');
    expect(find.text('limo_test_preview_por_1'), findsNothing);
  });

  testWidgets('multiple offers keep IDs off the labels and survive rebuild', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      offers: <Map<String, dynamic>>[
        _offer(
          id: 'limo_test_preview_por_1',
          title: <String, String>{'nl': 'Avond', 'en': 'Evening'},
        ),
        _offer(
          id: 'off_day',
          title: <String, String>{'nl': 'Dag', 'en': 'Day'},
        ),
      ],
    );
    expect(find.text('limo_test_preview_por_1'), findsNothing);
    expect(find.text('Avond'), findsWidgets);
    await tester.tap(find.byKey(kLimousineExternalOfferKey));
    await tester.pumpAndSettle();
    expect(find.text('Dag'), findsWidgets);
    await tester.tap(find.text('Dag').last);
    await tester.pumpAndSettle();
    expect(find.text('Dag'), findsWidgets);
    appLanguageNotifier.value = AppLanguage.en;
    await tester.pumpAndSettle();
    expect(find.text('limo_test_preview_por_1'), findsNothing);
    expect(find.text('off_day'), findsNothing);
    expect(find.text('Day'), findsWidgets);
    expect(find.text('Evening'), findsNothing);
  });

  test(
    'debounce, min query length and edit clear structured metadata',
    () async {
      final lookup = _Lookup();
      final pickup = LimousineAddressFieldController(
        lookup: lookup,
        fieldId: 'unit_pickup',
      );
      final destination = LimousineAddressFieldController(
        lookup: lookup,
        fieldId: 'unit_destination',
      );
      addTearDown(pickup.dispose);
      addTearDown(destination.dispose);

      pickup.onTextChanged('Ko');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(lookup.queries, isEmpty);
      expect(lookup.searchesStarted, 0);

      pickup.onTextChanged('Koren');
      expect(lookup.queries, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(lookup.queries, isNotEmpty);

      pickup.selectSuggestion(_pickupHit);
      destination.selectSuggestion(_destinationHit);
      expect(pickup.value.placeId, 'poi.pickup');
      expect(pickup.value.lat, 51.0543);
      expect(destination.value.placeId, 'poi.destination');

      pickup.onTextChanged('Korenmarkt 9');
      expect(pickup.value.placeId, isNull);
      expect(pickup.value.lat, isNull);
      expect(pickup.value.lon, isNull);
      expect(pickup.value.acceptance, LimousineAddressAcceptance.incomplete);
      expect(destination.value.placeId, 'poi.destination');
      expect(destination.value.lat, 51.0549);
      expect(destination.value.routeText, _destinationHit.label);
    },
  );

  testWidgets('address suggestions fill structured pickup and destination', (
    tester,
  ) async {
    final lookup = _Lookup();
    final gateway = _RecordingGateway();
    await _pumpForm(
      tester,
      gateway: gateway,
      lookup: lookup,
      offers: <Map<String, dynamic>>[_offer(id: 'off_quote')],
    );
    await tester.enterText(find.byKey(kLimousineExternalPickupKey), 'Kor');
    await tester.pump();
    expect(lookup.queries, isEmpty);
    await tester.enterText(find.byKey(kLimousineExternalPickupKey), 'Koren');
    await tester.pump(const Duration(milliseconds: 250));
    expect(lookup.searchesStarted, greaterThan(0));
    expect(
      find.byKey(limousineAddressSuggestionsKey('own_pickup')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('own_pickup', 0)),
    );
    await tester.pump();
    expect(find.text(_pickupHit.label), findsWidgets);

    await tester.enterText(
      find.byKey(kLimousineExternalDestinationKey),
      'Gras',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(limousineAddressSuggestionsKey('own_destination')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('own_destination', 0)),
    );
    await tester.pump();
    expect(find.text(_destinationHit.label), findsWidgets);
    expect(find.text(_pickupHit.label), findsWidgets);

    await tester.enterText(
      find.byKey(kLimousineExternalDestinationKey),
      'Graslei 12, Gent',
    );
    await tester.pump();
    expect(find.text(_destinationHit.label), findsNothing);
    expect(find.text(_pickupHit.label), findsWidgets);

    await tester.enterText(find.byKey(kLimousineExternalContactNameKey), 'Ada');
    await tester.enterText(
      find.byKey(kLimousineExternalContactEmailKey),
      'ada@example.test',
    );
    await tester.enterText(find.byKey(kLimousineExternalPaxKey), '2');
    await tester.scrollUntilVisible(
      find.byKey(kLimousineExternalAddStopKey),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(kLimousineExternalAddStopKey));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('limousine_external_stop_0')),
      'Kouter',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(limousineAddressSuggestionsKey('own_stop_0')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('own_stop_0', 0)),
    );
    await tester.pump();
    expect(find.text(_stopHit.label), findsWidgets);

    appLanguageNotifier.value = AppLanguage.en;
    await tester.pumpAndSettle();
    expect(find.text(_pickupHit.label), findsWidgets);
    expect(find.text(_stopHit.label), findsWidgets);

    await tester.scrollUntilVisible(
      find.byKey(kLimousineExternalSubmitKey),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(kLimousineExternalSubmitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kLimousineExternalPreviewSendKey));
    await tester.pumpAndSettle();
    expect(gateway.lastJourney?.from, _pickupHit.label);
    expect(gateway.lastJourney?.to, 'Graslei 12, Gent');
    expect(gateway.lastJourney?.stops, <String>[_stopHit.label]);
    expect(gateway.lastJourney?.offerId, 'off_quote');
    final payload = gateway.lastJourney!.toWorkerRequest();
    expect(payload['from'], _pickupHit.label);
    expect(payload['to'], 'Graslei 12, Gent');
    expect(payload['stops'], <String>[_stopHit.label]);
    expect(payload.containsKey('place_id'), isFalse);
    expect(payload.containsKey('lat'), isFalse);
    expect(payload.containsKey('lon'), isFalse);
    expect(jsonEncode(payload), isNot(contains('poi.pickup')));
    expect(jsonEncode(payload), isNot(contains('own_pickup')));
  });

  testWidgets('multiple stops keep route order after reorder', (tester) async {
    final gateway = _RecordingGateway();
    await _pumpForm(
      tester,
      gateway: gateway,
      lookup: _Lookup(),
      offers: <Map<String, dynamic>>[_offer(id: 'off_quote')],
    );
    await tester.enterText(find.byKey(kLimousineExternalContactNameKey), 'Ada');
    await tester.enterText(
      find.byKey(kLimousineExternalContactEmailKey),
      'ada@example.test',
    );
    await tester.enterText(
      find.byKey(kLimousineExternalPickupKey),
      'Korenmarkt',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('own_pickup', 0)),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(kLimousineExternalDestinationKey),
      'Graslei',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('own_destination', 0)),
    );
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(kLimousineExternalAddStopKey),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(kLimousineExternalAddStopKey));
    await tester.pump();
    await tester.tap(find.byKey(kLimousineExternalAddStopKey));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('limousine_external_stop_0')),
      'Kouter',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('own_stop_0', 0)),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey<String>('limousine_external_stop_1')),
      'Laarne',
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(
      find.byKey(limousineAddressSuggestionKey('own_stop_1', 0)),
    );
    await tester.pump();
    await tester.tap(find.byKey(limousineExternalStopMoveUpKey(1)));
    await tester.pump();
    await tester.enterText(find.byKey(kLimousineExternalPaxKey), '2');
    await tester.scrollUntilVisible(
      find.byKey(kLimousineExternalSubmitKey),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(kLimousineExternalSubmitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(kLimousineExternalPreviewSendKey));
    await tester.pumpAndSettle();
    expect(gateway.lastJourney?.stops, <String>[
      _castleHit.label,
      _stopHit.label,
    ]);
  });

  testWidgets('lookup failure does not wipe unrelated fields or crash', (
    tester,
  ) async {
    await _pumpForm(
      tester,
      lookup: _Lookup(error: true),
      offers: <Map<String, dynamic>>[_offer(id: 'off_quote')],
      size: const Size(360, 1800),
    );
    await tester.enterText(find.byKey(kLimousineExternalContactNameKey), 'Ada');
    await tester.enterText(
      find.byKey(kLimousineExternalPickupKey),
      'Korenmarkt',
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
    expect(find.text('Ada'), findsOneWidget);
    expect(find.byKey(limousineAddressRetryKey('own_pickup')), findsOneWidget);
  });

  testWidgets('phone and tablet widths keep offer and address fields', (
    tester,
  ) async {
    for (final size in <Size>[
      const Size(360, 1800),
      const Size(390, 1800),
      const Size(430, 1800),
      const Size(800, 1800),
    ]) {
      await _pumpForm(
        tester,
        offers: <Map<String, dynamic>>[_offer(id: 'limo_test_preview_por_1')],
        size: size,
      );
      expect(find.text('limo_test_preview_por_1'), findsNothing);
      expect(find.byKey(kLimousineExternalPickupKey), findsOneWidget);
      expect(find.byKey(kLimousineExternalDestinationKey), findsOneWidget);
      expect(find.byKey(kLimousineExternalOfferKey), findsOneWidget);
      expect(tester.takeException(), isNull);
      final pickup = tester.getRect(find.byKey(kLimousineExternalPickupKey));
      final destination = tester.getRect(
        find.byKey(kLimousineExternalDestinationKey),
      );
      expect(pickup.left, greaterThanOrEqualTo(0));
      expect(pickup.right, lessThanOrEqualTo(size.width + 0.5));
      expect(destination.left, greaterThanOrEqualTo(0));
      expect(destination.right, lessThanOrEqualTo(size.width + 0.5));
      expect(destination.top, greaterThanOrEqualTo(pickup.bottom));
    }
  });
}
