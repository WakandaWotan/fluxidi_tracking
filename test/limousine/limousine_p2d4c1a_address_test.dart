import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_quote_inbox.dart';

LimousinePublishedOffer _offer() {
  return LimousinePublishedOffer.fromJson(<String, dynamic>{
    'offer_id': 'off_1',
    'target_type': 'vehicle',
    'vehicle_id': 'veh_1',
    'service_class_id': 'executive_sedan',
    'title': {'nl': 'Executive', 'en': 'Executive'},
    'price_presentation': 'quote_required',
    'display_amount_cents': 45000,
    'currency': 'EUR',
    'vehicle': {'passenger_capacity': 3, 'luggage_capacity': 2},
  });
}

LimousinePlaceSuggestion _gent() => const LimousinePlaceSuggestion(
  label: 'Korenmarkt 1, 9000 Gent, Belgium',
  lat: 51.0543,
  lon: 3.7174,
  placeId: 'address.1',
);

LimousinePlaceSuggestion _brussels() => const LimousinePlaceSuggestion(
  label: 'Grote Markt, 1000 Brussel, Belgium',
  lat: 50.8467,
  lon: 4.3525,
  placeId: 'address.2',
);

class _RecordingLookup extends LimousinePlaceLookup {
  _RecordingLookup({
    LimousinePlaceSearch? search,
  }) : super(
         searchOverride:
             search ??
             (query, language) async {
               if (query.toLowerCase().contains('brussel') ||
                   query.toLowerCase().contains('brussels')) {
                 return LimousinePlaceLookupResult(
                   suggestions: [_brussels()],
                 );
               }
               return LimousinePlaceLookupResult(suggestions: [_gent()]);
             },
       );
}

class _SilentGateway implements LimousineCustomerQuoteGateway {
  @override
  Future<List<LimousineDiscoveredProvider>> discoverNearby({
    String? postcode,
    double? lat,
    double? lng,
    int radiusKm = 20,
  }) async => const [];

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
    throw const LimousineCustomerQuoteException(code: 'not_found');
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

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reuses the proven Mapbox Geocoding v5 seam', () {
    final uri = limousineMapboxPlacesUri(
      query: 'Korenmarkt Gent',
      token: 'token',
      language: 'nl',
    );
    expect(uri.host, kLimousineMapboxGeocodingV5Host);
    expect(uri.path, contains('geocoding/v5/mapbox.places/'));
    expect(uri.queryParameters['autocomplete'], 'true');
    expect(uri.queryParameters['country'], 'be');
    expect(uri.queryParameters['limit'], '6');
    expect(uri.queryParameters.containsKey('access_token'), isTrue);
    final source = File(
      'lib/limousine/limousine_address_lookup.dart',
    ).readAsStringSync();
    expect(source.contains('kMapboxToken'), isTrue);
    expect(source.contains('CalculatorPage._searchPlaces'), isTrue);
    expect(source.contains('debugPrint'), isFalse);
  });

  test('incomplete fragments cannot be accepted silently', () {
    expect(limousineAddressLooksLikeIncompleteFragment('90'), isTrue);
    expect(limousineAddressLooksLikeIncompleteFragment('9000'), isTrue);
    expect(limousineAddressLooksLikeIncompleteFragment('Gent'), isTrue);
    expect(limousineAddressAllowsManualFallback('9000'), isFalse);
    expect(limousineAddressAllowsManualFallback('Gent'), isFalse);
    expect(
      limousineAddressAllowsManualFallback('Korenmarkt 1, Gent'),
      isTrue,
    );
  });

  test('required addresses stay blocked until selected or confirmed', () {
    final draft = const LimousineQuoteCreateDraft(
      from: '9000',
      to: '1000',
      scheduledPickupIso: '2026-09-01T10:00:00Z',
    );
    expect(
      limousineRequestWizardCanAdvance(
        step: LimousineRequestWizardStep.journey,
        draft: draft,
        pickupAddress: const LimousineAddressValue(
          displayText: '9000',
          acceptance: LimousineAddressAcceptance.incomplete,
        ),
        destinationAddress: const LimousineAddressValue(
          displayText: 'Grote Markt, 1000 Brussel, Belgium',
          canonicalLabel: 'Grote Markt, 1000 Brussel, Belgium',
          acceptance: LimousineAddressAcceptance.selected,
        ),
      ),
      isFalse,
    );
    expect(
      limousineRequestWizardCanAdvance(
        step: LimousineRequestWizardStep.journey,
        draft: draft.copyWith(from: _gent().label, to: _brussels().label),
        pickupAddress: LimousineAddressValue(
          displayText: _gent().label,
          canonicalLabel: _gent().label,
          lat: _gent().lat,
          lon: _gent().lon,
          placeId: _gent().placeId,
          acceptance: LimousineAddressAcceptance.selected,
        ),
        destinationAddress: LimousineAddressValue(
          displayText: _brussels().label,
          canonicalLabel: _brussels().label,
          lat: _brussels().lat,
          lon: _brussels().lon,
          placeId: _brussels().placeId,
          acceptance: LimousineAddressAcceptance.selected,
        ),
      ),
      isTrue,
    );
  });

  test('stops and return addresses are required once started', () {
    final draft = const LimousineQuoteCreateDraft(
      from: 'Gent',
      to: 'Brussel',
      scheduledPickupIso: '2026-09-01T10:00:00Z',
      roundtrip: true,
      returnPickupIso: '2026-09-01T18:00:00Z',
    );
    expect(
      limousineRequestWizardGaps(
        step: LimousineRequestWizardStep.journey,
        draft: draft,
        pickupAddress: LimousineAddressValue(
          displayText: _gent().label,
          canonicalLabel: _gent().label,
          acceptance: LimousineAddressAcceptance.selected,
        ),
        destinationAddress: LimousineAddressValue(
          displayText: _brussels().label,
          canonicalLabel: _brussels().label,
          acceptance: LimousineAddressAcceptance.selected,
        ),
        stopAddresses: const [
          LimousineAddressValue(
            displayText: 'Ant',
            acceptance: LimousineAddressAcceptance.incomplete,
          ),
        ],
        returnPickupAddress: const LimousineAddressValue(
          displayText: '1000',
          acceptance: LimousineAddressAcceptance.incomplete,
        ),
        returnDestinationAddress: LimousineAddressValue(
          displayText: _gent().label,
          canonicalLabel: _gent().label,
          acceptance: LimousineAddressAcceptance.selected,
        ),
      ).map((gap) => gap.code),
      containsAll(<String>[
        'stop_address_required',
        'return_pickup_required',
      ]),
    );
  });

  test('create body keeps server as route/price authority', () {
    final body = limousineCustomerCreateBody(
      LimousineQuoteCreateDraft(
        publicPartnerId: 'p1',
        offerId: 'off_1',
        from: _gent().label,
        to: _brussels().label,
        scheduledPickupIso: '2026-09-01T10:00:00Z',
      ),
    );
    expect(body.containsKey('from_lat'), isFalse);
    expect(body.containsKey('to_lng'), isFalse);
    expect(body.containsKey('total_incl_vat_cents'), isFalse);
    expect(body.containsKey('taxi_price'), isFalse);
    expect(limousineCustomerCreateBodyIsBounded(body), isTrue);
  });

  test('session cache avoids a second lookup for the same query', () async {
    var remoteCalls = 0;
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        remoteCalls += 1;
        return LimousinePlaceLookupResult(suggestions: [_gent()]);
      },
    );
    await lookup.search('Korenmarkt Gent');
    await lookup.search('Korenmarkt Gent');
    expect(remoteCalls, 1);
    expect(lookup.searchesStarted, 1);
    lookup.dispose();
  });

  test('stale lookup results are dropped', () async {
    final firstStarted = Completer<void>();
    final releaseStale = Completer<void>();
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        if (query.contains('one')) {
          if (!firstStarted.isCompleted) firstStarted.complete();
          await releaseStale.future;
          return LimousinePlaceLookupResult(
            suggestions: const [
              LimousinePlaceSuggestion(label: 'STALE ADDRESS'),
            ],
          );
        }
        return LimousinePlaceLookupResult(suggestions: [_brussels()]);
      },
    );
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'pickup',
      debounce: Duration.zero,
    );
    controller.textController.text = 'one street name';
    controller.onTextChanged('one street name');
    await Future<void>.delayed(Duration.zero);
    await firstStarted.future;
    controller.textController.text = 'two street names';
    controller.onTextChanged('two street names');
    await Future<void>.delayed(Duration.zero);
    expect(controller.suggestions.single.label, _brussels().label);
    releaseStale.complete();
    await Future<void>.delayed(Duration.zero);
    expect(controller.suggestions, hasLength(1));
    expect(controller.suggestions.single.label, _brussels().label);
    expect(controller.suggestions.single.label.contains('STALE'), isFalse);
    controller.dispose();
    lookup.dispose();
  });

  testWidgets('suggestion selection writes a canonical address', (tester) async {
    final lookup = _RecordingLookup();
    final field = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'pickup',
      debounce: Duration.zero,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousineAddressField(
            controller: field,
            label: 'Ophaallocatie',
            tokens: LimousineUxTokens.fromSurface(
              background: const Color(0xFFFFFBF4),
            ),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(limousineAddressInputKey('pickup')),
      'Korenmarkt',
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(find.byKey(limousineAddressSuggestionsKey('pickup')), findsOneWidget);
    await tester.tap(find.byKey(limousineAddressSuggestionKey('pickup', 0)));
    await tester.pump();
    expect(field.isRouteReady, isTrue);
    expect(field.value.canonicalLabel, _gent().label);
    expect(field.value.lat, _gent().lat);
    expect(field.value.placeId, 'address.1');
    expect(find.text(_gent().label), findsWidgets);
    field.dispose();
    lookup.dispose();
  });

  testWidgets('manual fallback works only for a complete typed address', (
    tester,
  ) async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          const LimousinePlaceLookupResult(),
    );
    final field = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'destination',
      debounce: Duration.zero,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousineAddressField(
            controller: field,
            label: 'Bestemming',
            tokens: LimousineUxTokens.fromSurface(
              background: const Color(0xFFFFFBF4),
            ),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(limousineAddressInputKey('destination')),
      '9000',
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(find.byKey(limousineAddressManualKey('destination')), findsNothing);
    expect(field.confirmManualFallback(), isFalse);

    await tester.enterText(
      find.byKey(limousineAddressInputKey('destination')),
      'Korenmarkt 1, Gent',
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    expect(find.byKey(limousineAddressNoResultKey('destination')), findsOneWidget);
    expect(find.byKey(limousineAddressRetryKey('destination')), findsOneWidget);
    await tester.tap(find.byKey(limousineAddressManualKey('destination')));
    await tester.pump();
    expect(field.isRouteReady, isTrue);
    expect(
      field.value.acceptance,
      LimousineAddressAcceptance.manualFallback,
    );
    field.dispose();
    lookup.dispose();
  });

  testWidgets('wizard keeps Next disabled for a postcode fragment', (
    tester,
  ) async {
    final lookup = _RecordingLookup();
    final gateway = _SilentGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          placeLookup: lookup,
          entryEnabled: true,
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(limousineAddressInputKey('pickup')),
      '9000',
    );
    await tester.pump(const Duration(milliseconds: 230));
    final next = tester.widget<FilledButton>(
      find.byKey(kLimousineRequestWizardNextKey),
    );
    expect(next.onPressed, isNull);
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
    expect(controller.draft.from, isEmpty);
    controller.dispose();
  });

  testWidgets('phone and tablet layouts host the address fields', (
    tester,
  ) async {
    final lookup = _RecordingLookup();
    final gateway = _SilentGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway)
      ..updateDraft(const LimousineQuoteCreateDraft(stops: ['Antwerpen']));
    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          placeLookup: lookup,
          entryEnabled: true,
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
    expect(find.byKey(limousineAddressFieldKey('pickup')), findsOneWidget);
    expect(find.byKey(limousineAddressFieldKey('destination')), findsOneWidget);
    controller.updateDraft(controller.draft.copyWith(roundtrip: true));
    await tester.pump();
    expect(find.byKey(limousineAddressFieldKey('return_pickup')), findsOneWidget);
    expect(
      find.byKey(limousineAddressFieldKey('return_destination')),
      findsOneWidget,
    );
    expect(find.byKey(kLimousineRequestAddStopKey), findsOneWidget);
    expect(find.byKey(limousineAddressFieldKey('stop_0')), findsOneWidget);

    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          placeLookup: lookup,
          entryEnabled: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerPhoneLayoutKey), findsOneWidget);
    expect(find.byKey(limousineAddressFieldKey('pickup')), findsOneWidget);

    await tester.pumpWidget(
      _app(
        LimousineCustomerQuotePage(
          controller: controller,
          gateway: gateway,
          placeLookup: lookup,
          entryEnabled: true,
        ),
        size: kLimousineTabletLandscape,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
    expect(find.byKey(limousineAddressFieldKey('pickup')), findsOneWidget);
    controller.dispose();
  });

  testWidgets('rebuild does not start another geocoding call', (tester) async {
    final lookup = _RecordingLookup();
    final gateway = _SilentGateway();
    final controller = LimousineCustomerQuoteController(gateway: gateway);
    final page = LimousineCustomerQuotePage(
      controller: controller,
      gateway: gateway,
      placeLookup: lookup,
      entryEnabled: true,
    );
    await tester.pumpWidget(_app(page));
    await tester.enterText(
      find.byKey(limousineAddressInputKey('pickup')),
      'Korenmarkt',
    );
    await tester.pump(const Duration(milliseconds: 230));
    expect(lookup.searchesStarted, 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    expect(lookup.searchesStarted, 1);
    controller.dispose();
  });
}
