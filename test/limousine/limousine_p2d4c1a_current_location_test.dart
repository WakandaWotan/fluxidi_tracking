import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
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

class _SilentGateway with LimousineCustomerQuoteGateway {
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

class _LocationHarness {
  _LocationHarness({
    this.servicesEnabled = true,
    this.permission = LimousineLocationPermission.granted,
    LimousineLocationPermission? requestPermissionResult,
    Future<LimousineCurrentLocationFix> Function()? position,
    LimousinePlaceReverse? reverse,
  }) : requestResult = requestPermissionResult ?? permission {
    lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async =>
          LimousinePlaceLookupResult(suggestions: [_gent()]),
      reverseOverride:
          reverse ??
          (lat, lon, language) async {
            reverseCalls += 1;
            lastReverseLat = lat;
            lastReverseLon = lon;
            return LimousinePlaceLookupResult(suggestions: [_gent()]);
          },
    );
    platform = LimousineCurrentLocationPlatform(
      isLocationServiceEnabled: () async {
        serviceChecks += 1;
        return servicesEnabled;
      },
      checkPermission: () async {
        permissionChecks += 1;
        return permission;
      },
      requestPermission: () async {
        permissionRequests += 1;
        permission = requestResult;
        return requestResult;
      },
      getCurrentPosition: (timeLimit) async {
        positionCalls += 1;
        if (position != null) return position();
        return const LimousineCurrentLocationFix(
          latitude: 51.0543,
          longitude: 3.7174,
        );
      },
      openAppSettings: () async {
        settingsOpens += 1;
        return true;
      },
    );
    resolver = LimousineCurrentLocationResolver(
      lookup: lookup,
      platform: platform,
    );
  }

  late final LimousinePlaceLookup lookup;
  late final LimousineCurrentLocationPlatform platform;
  late final LimousineCurrentLocationResolver resolver;

  bool servicesEnabled;
  LimousineLocationPermission permission;
  LimousineLocationPermission requestResult;

  int serviceChecks = 0;
  int permissionChecks = 0;
  int permissionRequests = 0;
  int positionCalls = 0;
  int reverseCalls = 0;
  int settingsOpens = 0;
  double? lastReverseLat;
  double? lastReverseLon;

  LimousineAddressFieldController field() {
    return LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'pickup',
      debounce: Duration.zero,
      currentLocation: resolver,
    );
  }
}

Widget _fieldApp(LimousineAddressFieldController field) {
  return MaterialApp(
    home: Scaffold(
      body: LimousineAddressField(
        controller: field,
        label: 'Ophaallocatie',
        tokens: LimousineUxTokens.fromSurface(
          background: const Color(0xFFFFFBF4),
        ),
        language: AppLanguage.nl,
        showCurrentLocation: true,
      ),
    ),
  );
}

Widget _pageApp({
  required _LocationHarness harness,
  required LimousineCustomerQuoteController controller,
  Size size = kLimousinePhonePortrait,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: LimousineCustomerQuotePage(
        controller: controller,
        gateway: _SilentGateway(),
        placeLookup: harness.lookup,
        currentLocationPlatform: harness.platform,
        entryEnabled: true,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('current location reuses Geolocator and Mapbox reverse, never last-known', () {
    final source = File(
      'lib/limousine/limousine_current_location.dart',
    ).readAsStringSync();
    expect(source.contains('package:geolocator/geolocator.dart'), isTrue);
    expect(source.contains('getCurrentPosition'), isTrue);
    expect(source.contains('reverseGeocode'), isTrue);
    expect(source.contains('getLastKnownPosition'), isFalse);
    expect(source.contains('getPositionStream'), isFalse);
    expect(source.contains('debugPrint'), isFalse);
    expect(source.contains('kMapboxToken'), isFalse);
    final lookup = File(
      'lib/limousine/limousine_address_lookup.dart',
    ).readAsStringSync();
    expect(lookup.contains('limousineMapboxReverseGeocodeUri'), isTrue);
    expect(lookup.contains('debugPrint'), isFalse);
    final page = File(
      'lib/limousine/limousine_customer_quote_page.dart',
    ).readAsStringSync();
    expect('showCurrentLocation: true'.allMatches(page).length, 3);
    expect(page.contains('controller: _destination'), isTrue);
    expect(RegExp(r'controller: _destination,[\s\S]{0,180}showCurrentLocation: true').hasMatch(page), isFalse);
  });

  testWidgets('success fills the same selected address model as autocomplete', (
    tester,
  ) async {
    final harness = _LocationHarness();
    final field = harness.field();
    await tester.pumpWidget(_fieldApp(field));
    expect(find.byKey(limousineAddressCurrentLocationKey('pickup')), findsOneWidget);
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(field.isRouteReady, isTrue);
    expect(field.value.acceptance, LimousineAddressAcceptance.selected);
    expect(field.value.canonicalLabel, _gent().label);
    expect(field.value.lat, _gent().lat);
    expect(field.value.lon, _gent().lon);
    expect(field.value.placeId, 'address.1');
    expect(harness.positionCalls, 1);
    expect(harness.reverseCalls, 1);
    expect(harness.lastReverseLat, 51.0543);
    expect(harness.lastReverseLon, 3.7174);
    expect(harness.resolver.reverseGeocodesStarted, 1);
    expect(harness.lookup.reverseGeocodesStarted, 1);
    expect(find.text(_gent().label), findsWidgets);

    await tester.enterText(
      find.byKey(limousineAddressInputKey('pickup')),
      'Nieuw adres 12, Gent',
    );
    await tester.pump();
    expect(field.isRouteReady, isFalse);
    expect(field.value.acceptance, LimousineAddressAcceptance.incomplete);
    field.dispose();
    harness.lookup.dispose();
  });

  testWidgets('permission denied stays empty and can retry', (tester) async {
    final harness = _LocationHarness(
      permission: LimousineLocationPermission.denied,
      requestPermissionResult: LimousineLocationPermission.denied,
    );
    final field = harness.field();
    await tester.pumpWidget(_fieldApp(field));
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(field.isRouteReady, isFalse);
    expect(field.value.lat, isNull);
    expect(harness.positionCalls, 0);
    expect(harness.reverseCalls, 0);
    expect(
      find.byKey(limousineAddressCurrentLocationErrorKey('pickup')),
      findsOneWidget,
    );
    expect(
      find.text(kLimousineCurrentLocationDenied.of(AppLanguage.nl)),
      findsOneWidget,
    );

    harness.requestResult = LimousineLocationPermission.granted;
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(field.isRouteReady, isTrue);
    expect(field.value.canonicalLabel, _gent().label);
    expect(harness.permissionRequests, 2);
    expect(harness.positionCalls, 1);
    expect(harness.reverseCalls, 1);
    field.dispose();
    harness.lookup.dispose();
  });

  testWidgets('permanently denied explains Android app settings', (tester) async {
    final harness = _LocationHarness(
      permission: LimousineLocationPermission.deniedForever,
    );
    final field = harness.field();
    await tester.pumpWidget(_fieldApp(field));
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(field.isRouteReady, isFalse);
    expect(harness.permissionRequests, 0);
    expect(harness.positionCalls, 0);
    expect(harness.reverseCalls, 0);
    expect(
      find.text(kLimousineCurrentLocationDeniedForever.of(AppLanguage.nl)),
      findsOneWidget,
    );
    expect(find.byKey(limousineAddressOpenSettingsKey('pickup')), findsOneWidget);
    await tester.tap(find.byKey(limousineAddressOpenSettingsKey('pickup')));
    await tester.pump();
    expect(harness.settingsOpens, 1);
    field.dispose();
    harness.lookup.dispose();
  });

  testWidgets('disabled location services do not request a fix', (tester) async {
    final harness = _LocationHarness(servicesEnabled: false);
    final field = harness.field();
    await tester.pumpWidget(_fieldApp(field));
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(field.value.lat, isNull);
    expect(harness.permissionChecks, 0);
    expect(harness.positionCalls, 0);
    expect(harness.reverseCalls, 0);
    expect(
      find.text(kLimousineCurrentLocationServicesOff.of(AppLanguage.nl)),
      findsOneWidget,
    );
    field.dispose();
    harness.lookup.dispose();
  });

  testWidgets('timeout after a fix does not persist raw coordinates', (
    tester,
  ) async {
    final harness = _LocationHarness(
      reverse: (lat, lon, language) async {
        throw TimeoutException('reverse');
      },
    );
    final field = harness.field();
    await tester.pumpWidget(_fieldApp(field));
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(field.isRouteReady, isFalse);
    expect(field.value.lat, isNull);
    expect(field.value.lon, isNull);
    expect(field.textController.text, isEmpty);
    expect(harness.positionCalls, 1);
    expect(harness.lookup.reverseGeocodesStarted, 1);
    expect(
      find.text(kLimousineCurrentLocationTimeoutMessage.of(AppLanguage.nl)),
      findsOneWidget,
    );
    field.dispose();
    harness.lookup.dispose();
  });

  testWidgets('GPS timeout never reverse-geocodes or uses a cached fix', (
    tester,
  ) async {
    final harness = _LocationHarness(
      position: () async {
        throw TimeoutException('gps');
      },
    );
    final field = harness.field();
    await tester.pumpWidget(_fieldApp(field));
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(field.value.lat, isNull);
    expect(harness.reverseCalls, 0);
    expect(harness.lookup.reverseGeocodesStarted, 0);
    expect(harness.resolver.positionsStarted, 1);
    expect(
      find.text(kLimousineCurrentLocationTimeoutMessage.of(AppLanguage.nl)),
      findsOneWidget,
    );
    field.dispose();
    harness.lookup.dispose();
  });

  testWidgets('double tap starts only one fix and one reverse-geocode', (
    tester,
  ) async {
    final hold = Completer<LimousineCurrentLocationFix>();
    final harness = _LocationHarness(position: () => hold.future);
    final field = harness.field();
    await tester.pumpWidget(_fieldApp(field));
    final button = find.byKey(limousineAddressCurrentLocationKey('pickup'));
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(field.resolvingCurrentLocation, isTrue);
    expect(
      find.byKey(limousineAddressCurrentLocationLoadingKey('pickup')),
      findsOneWidget,
    );
    expect(harness.positionCalls, 1);
    expect(harness.lookup.reverseGeocodesStarted, 0);
    hold.complete(
      const LimousineCurrentLocationFix(latitude: 51.0543, longitude: 3.7174),
    );
    await tester.pump();
    expect(field.isRouteReady, isTrue);
    expect(harness.positionCalls, 1);
    expect(harness.reverseCalls, 1);
    expect(harness.resolver.suppressedTaps, 0);
    field.dispose();
    harness.lookup.dispose();
  });

  testWidgets('resolver suppresses a second in-flight resolve', (tester) async {
    final hold = Completer<LimousineCurrentLocationFix>();
    final harness = _LocationHarness(position: () => hold.future);
    final first = harness.resolver.resolve();
    final second = harness.resolver.resolve();
    expect(harness.resolver.isResolving, isTrue);
    expect(await second, isNull);
    expect(harness.resolver.suppressedTaps, 1);
    hold.complete(
      const LimousineCurrentLocationFix(latitude: 51.0543, longitude: 3.7174),
    );
    final suggestion = await first;
    expect(suggestion?.label, _gent().label);
    expect(harness.positionCalls, 1);
    expect(harness.lookup.reverseGeocodesStarted, 1);
    harness.lookup.dispose();
  });

  testWidgets('pickup current location never fills destination', (tester) async {
    final harness = _LocationHarness();
    final controller = LimousineCustomerQuoteController(gateway: _SilentGateway());
    await tester.pumpWidget(_pageApp(harness: harness, controller: controller));
    await tester.pump();
    expect(find.byKey(limousineAddressCurrentLocationKey('pickup')), findsOneWidget);
    expect(
      find.byKey(limousineAddressCurrentLocationKey('destination')),
      findsNothing,
    );
    await tester.tap(find.byKey(limousineAddressCurrentLocationKey('pickup')));
    await tester.pump();
    expect(controller.draft.from, _gent().label);
    expect(controller.draft.to, isEmpty);
    final body = limousineCustomerCreateBody(
      controller.draft.copyWith(
        publicPartnerId: 'p1',
        offerId: 'off_1',
        to: _gent().label,
        scheduledPickupIso: '2026-09-01T10:00:00Z',
      ),
    );
    expect(body['from'], _gent().label);
    expect(body.containsKey('from_lat'), isFalse);
    expect(body.containsKey('from_lng'), isFalse);
    expect(limousineCustomerCreateBodyIsBounded(body), isTrue);
    controller.dispose();
  });

  testWidgets('tablet and phone layouts keep the pickup location action', (
    tester,
  ) async {
    final harness = _LocationHarness();
    final controller = LimousineCustomerQuoteController(gateway: _SilentGateway());
    await tester.pumpWidget(
      _pageApp(
        harness: harness,
        controller: controller,
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
    expect(find.byKey(limousineAddressCurrentLocationKey('pickup')), findsOneWidget);
    expect(
      find.byKey(limousineAddressCurrentLocationKey('destination')),
      findsNothing,
    );

    await tester.pumpWidget(
      _pageApp(
        harness: harness,
        controller: controller,
        size: kLimousinePhonePortrait,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerPhoneLayoutKey), findsOneWidget);
    expect(find.byKey(limousineAddressCurrentLocationKey('pickup')), findsOneWidget);
    expect(
      find.byKey(limousineAddressCurrentLocationKey('destination')),
      findsNothing,
    );

    await tester.pumpWidget(
      _pageApp(
        harness: harness,
        controller: controller,
        size: kLimousineTabletLandscape,
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineCustomerTabletLayoutKey), findsOneWidget);
    expect(find.byKey(limousineAddressCurrentLocationKey('pickup')), findsOneWidget);
    controller.dispose();
  });
}
