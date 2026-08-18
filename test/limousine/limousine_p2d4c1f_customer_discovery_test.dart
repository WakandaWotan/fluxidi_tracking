import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_marketplace_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_state_composition.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _workerCard({
  required String id,
  required String name,
  double? distanceKm,
  bool testPreview = true,
  String city = 'Gent',
  bool verified = true,
}) {
  return <String, dynamic>{
    'partner_id': id,
    'company_name': name,
    'is_active': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'public_city': city,
    'service_region': city,
    if (distanceKm != null) 'distance_km': distanceKm,
    'trust': <String, dynamic>{'verified_partner': verified},
    'hero_photo_url': 'https://cdn.example/cover.jpg',
    'limousine_vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'service_category': 'limousine',
        'photo_url': 'https://cdn.example/v1.jpg',
        'service_class_id': 'executive_sedan',
        'passenger_capacity': 3,
        'luggage_capacity': 2,
      },
    ],
    'limousine_price_presentation': 'from_price',
    'display_amount_cents': 45000,
    'currency': 'EUR',
    if (testPreview) 'test_preview': true,
  };
}

Map<String, dynamic> _taxiOnly() {
  return <String, dynamic>{
    'partner_id': 'taxi_1',
    'company_name': 'City Taxi',
    'is_active': true,
    'services': <String>['taxi'],
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Stretch Limousine',
        'service_category': 'taxi',
      },
    ],
  };
}

Map<String, dynamic> _airportOnly() {
  return <String, dynamic>{
    'partner_id': 'air_1',
    'company_name': 'Airport Shuttle',
    'is_active': true,
    'services': <String>['airport'],
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{'name': 'Van', 'service_category': 'airport'},
    ],
  };
}

Map<String, dynamic> _draftOnly() {
  return <String, dynamic>{
    'partner_id': 'draft_1',
    'company_name': 'Draft Coach',
    'is_active': true,
    'limousine_available': true,
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{'service_category': 'limousine', 'is_active': true},
    ],
    'limousine_offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'off_draft',
        'enabled': false,
        'published': false,
        'draft': true,
        'price_presentation': 'quote_required',
      },
    ],
  };
}

LimousinePlaceSuggestion _gent() => const LimousinePlaceSuggestion(
  label: 'Korenmarkt 1, 9000 Gent, Belgium',
  lat: 51.0543,
  lon: 3.7174,
  placeId: 'address.1',
);

class _LocationHarness {
  _LocationHarness() {
    lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        if (query.contains('9000') || query.toLowerCase().contains('gent')) {
          return LimousinePlaceLookupResult(suggestions: [_gent()]);
        }
        return const LimousinePlaceLookupResult();
      },
      reverseOverride: (lat, lon, language) async {
        reverseCalls += 1;
        return LimousinePlaceLookupResult(suggestions: [_gent()]);
      },
    );
    platform = LimousineCurrentLocationPlatform(
      isLocationServiceEnabled: () async => true,
      checkPermission: () async => LimousineLocationPermission.granted,
      requestPermission: () async => LimousineLocationPermission.granted,
      getCurrentPosition: (timeLimit) async {
        positionCalls += 1;
        return const LimousineCurrentLocationFix(
          latitude: 51.0543,
          longitude: 3.7174,
        );
      },
      openAppSettings: () async => true,
    );
  }

  late final LimousinePlaceLookup lookup;
  late final LimousineCurrentLocationPlatform platform;
  int positionCalls = 0;
  int reverseCalls = 0;
}

void _press(WidgetTester tester, Key key) {
  tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed!();
}

Widget _app(Widget child, {Size size = kLimousinePhonePortrait}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

LimousineCustomerDiscoveryPage _page({
  required MemoryLimousineDiscoveryGateway gateway,
  LimousineDiscoveryController? controller,
  _LocationHarness? location,
  LimousineDiscoveryOpenPartner? onOpenPartner,
  bool autoLoadRecommended = true,
}) {
  final harness = location ?? _LocationHarness();
  return LimousineCustomerDiscoveryPage(
    gateway: gateway,
    controller: controller,
    placeLookup: harness.lookup,
    currentLocationPlatform: harness.platform,
    onOpenPartner: onOpenPartner,
    customerHomeBuilder: (_) => const SizedBox.shrink(),
    autoLoadRecommended: autoLoadRecommended,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('selected postcode labels use the postcode filter, not GPS', () {
    final query = limousineDiscoveryQueryFromAddress(
      displayText: '9688, Maarkedal',
      lat: 50.796,
      lon: 3.621,
    );
    expect(query?.postcode, '9688');
    expect(query?.lat, isNull);
    expect(query?.lng, isNull);
  });

  test('street-level selected labels keep server coordinates', () {
    final query = limousineDiscoveryQueryFromAddress(
      displayText: 'Korenmarkt 1, 9000 Gent, Belgium',
      lat: 51.0543,
      lon: 3.7174,
    );
    expect(query?.lat, 51.0543);
    expect(query?.lng, 3.7174);
    expect(query?.postcode, isNull);
  });

  test(
    'explicit current location keeps GPS even when the label has a postcode',
    () {
      final query = limousineDiscoveryQueryFromAddress(
        displayText: 'Koekamerstraat 48, 9688 Maarkedal',
        lat: 50.796,
        lon: 3.621,
        explicitCurrentLocation: true,
      );
      expect(query?.lat, 50.796);
      expect(query?.lng, 3.621);
      expect(query?.postcode, isNull);
    },
  );

  test('worker-shaped test-preview cards parse; excluded classes stay out', () {
    final allowlisted = tryParseLimousineDiscoveryCard(
      _workerCard(id: 'limo_1', name: 'Maison Noire'),
    );
    expect(allowlisted?.companyName, 'Maison Noire');
    expect(allowlisted?.testPreview, isTrue);
    expect(allowlisted?.publicCity, 'Gent');
    expect(allowlisted?.vehicles.first.serviceClassId, 'executive_sedan');

    expect(tryParseLimousineDiscoveryCard(_taxiOnly()), isNull);
    expect(tryParseLimousineDiscoveryCard(_airportOnly()), isNull);
    expect(tryParseLimousineDiscoveryCard(_draftOnly()), isNull);

    final unmarked =
        Map<String, dynamic>.from(
            _workerCard(id: 'other_1', name: 'Not Allowlisted'),
          )
          ..['limousine_available'] = false
          ..['limousine_service_enabled'] = false;
    expect(tryParseLimousineDiscoveryCard(unmarked), isNull);
  });

  test('private operating-base fields never become distance or card data', () {
    final raw = _workerCard(id: 'limo_1', name: 'Maison Noire')
      ..['operating_base'] = <String, dynamic>{'lat': 51.05, 'lng': 3.72}
      ..['tenant_id'] = 'ten_secret'
      ..['company_id'] = 'cmp_secret'
      ..['license_plate'] = '1-ABC-234'
      ..['driver_id'] = 'drv_1';
    raw.remove('distance_km');
    final card = tryParseLimousineDiscoveryCard(raw)!;
    expect(card.distanceKm, isNull);
    expect(card.publicCity, 'Gent');
    expect(card.companyName, 'Maison Noire');
  });

  test('unscoped HTTP nearby sends only service=limousine', () async {
    final requested = <Uri>[];
    final client = MockClient((request) async {
      requested.add(request.url);
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'limousine_listing_mode': 'test_preview',
          'partners': <dynamic>[
            _workerCard(id: 'limo_1', name: 'Maison Noire'),
            _taxiOnly(),
            _airportOnly(),
            _draftOnly(),
          ],
        }),
        200,
      );
    });
    final gateway = HttpLimousineDiscoveryGateway(
      client: client,
      bookingBaseUrl: 'https://booking.example',
    );
    final result = await gateway.search(const LimousineDiscoveryQuery());
    expect(requested.single.path, '/partners/nearby');
    expect(requested.single.queryParameters, <String, String>{
      'service': 'limousine',
    });
    expect(result.listingMode, 'test_preview');
    expect(result.isTestPreview, isTrue);
    expect(result.cards.map((card) => card.publicPartnerId), <String>[
      'limo_1',
    ]);
    expect(result.cards.first.distanceKm, isNull);
  });

  testWidgets('initial load shows recommended test companies without GPS', (
    tester,
  ) async {
    final location = _LocationHarness();
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        expect(query.isUnscoped, isTrue);
        return LimousineDiscoveryPageData(
          listingMode: 'test_preview',
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _workerCard(id: 'limo_1', name: 'Maison Noire'),
            _taxiOnly(),
          ]),
        );
      },
    );
    await tester.pumpWidget(_app(_page(gateway: gateway, location: location)));
    await tester.pumpAndSettle();
    expect(gateway.searchCalls, 1);
    expect(gateway.lastQuery?.isUnscoped, isTrue);
    expect(location.positionCalls, 0);
    expect(location.reverseCalls, 0);
    expect(gateway.requestedPaths, <String>[kLimousineDiscoveryNearbyPath]);
    expect(gateway.bookCalls, 0);
    expect(find.byKey(kLimousineDiscoveryRecommendedKey), findsOneWidget);
    expect(find.text(kLimousineDiscoveryRecommended.nl), findsOneWidget);
    expect(find.byKey(kLimousineDiscoveryTestEnvironmentKey), findsOneWidget);
    expect(find.text(kLimousineDiscoveryGatesOffTitle.nl), findsOneWidget);
    expect(find.text('Maison Noire'), findsOneWidget);
    expect(find.text('City Taxi'), findsNothing);
    expect(find.textContaining('km van'), findsNothing);
    expect(find.textContaining('nearest'), findsNothing);
  });

  testWidgets('unscoped listing hides server distance if it was sent', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _workerCard(id: 'limo_1', name: 'Maison Noire', distanceKm: 12.4),
        ]),
      ),
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pumpAndSettle();
    expect(find.text('Maison Noire'), findsOneWidget);
    expect(find.textContaining('km van uw zoekgebied'), findsNothing);
  });

  testWidgets('region search keeps server order and authoritative distance', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        if (query.isUnscoped) {
          return LimousineDiscoveryPageData(
            listingMode: 'test_preview',
            cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
              _workerCard(id: 'far', name: 'Far Coach'),
              _workerCard(id: 'near', name: 'Near Coach'),
            ]),
          );
        }
        expect(query.postcode, '9000');
        return LimousineDiscoveryPageData(
          listingMode: 'test_preview',
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _workerCard(id: 'near', name: 'Near Coach', distanceKm: 4),
            _workerCard(id: 'far', name: 'Far Coach', distanceKm: 31),
          ]),
        );
      },
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pumpAndSettle();
    expect(find.text('Far Coach'), findsOneWidget);
    await tester.enterText(
      find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
      '9000',
    );
    await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
    await tester.pumpAndSettle();
    expect(gateway.searchCalls, 2);
    expect(find.byKey(kLimousineDiscoveryRecommendedKey), findsNothing);
    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(names.indexOf('Near Coach'), lessThan(names.indexOf('Far Coach')));
    expect(find.textContaining('4 km van uw zoekgebied'), findsOneWidget);
    expect(find.textContaining('31 km van uw zoekgebied'), findsOneWidget);
  });

  testWidgets('explicit Huidige locatie refines by server distance', (
    tester,
  ) async {
    final location = _LocationHarness();
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        if (query.isUnscoped) {
          return LimousineDiscoveryPageData(
            listingMode: 'test_preview',
            cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
              _workerCard(id: 'limo_1', name: 'Maison Noire'),
            ]),
          );
        }
        expect(query.lat, 51.0543);
        expect(query.lng, 3.7174);
        return LimousineDiscoveryPageData(
          listingMode: 'test_preview',
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _workerCard(id: 'limo_1', name: 'Maison Noire', distanceKm: 6),
          ]),
        );
      },
    );
    await tester.pumpWidget(_app(_page(gateway: gateway, location: location)));
    await tester.pumpAndSettle();
    expect(location.positionCalls, 0);
    await tester.tap(
      find.byKey(
        limousineAddressCurrentLocationKey(kLimousineDiscoveryFieldId),
      ),
    );
    await tester.pumpAndSettle();
    expect(location.positionCalls, 1);
    expect(gateway.searchCalls, 2);
    expect(find.textContaining('6 km van uw zoekgebied'), findsOneWidget);
    expect(find.byKey(kLimousineDiscoveryRecommendedKey), findsNothing);
  });

  testWidgets('Andere regio zoeken reloads the unscoped recommended list', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        if (!query.isUnscoped) {
          return const LimousineDiscoveryPageData(listingMode: 'test_preview');
        }
        return LimousineDiscoveryPageData(
          listingMode: 'test_preview',
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _workerCard(id: 'limo_1', name: 'Maison Noire'),
          ]),
        );
      },
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
      '9000',
    );
    await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineDiscoveryEmptyKey), findsOneWidget);
    _press(tester, kLimousineDiscoverySearchOtherRegionKey);
    await tester.pumpAndSettle();
    expect(gateway.lastQuery?.isUnscoped, isTrue);
    expect(find.text('Maison Noire'), findsOneWidget);
    expect(find.byKey(kLimousineDiscoveryRecommendedKey), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
            find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
          )
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('confirmed profile opens; taxi surface does not', (tester) async {
    var opened = 0;
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _workerCard(id: 'limo_1', name: 'Maison Noire'),
        ]),
      ),
      profileHandler: (id) async => <String, dynamic>{
        'partner_id': id,
        'limousine_available': true,
        'company_name': 'Maison Noire',
      },
    );
    await tester.pumpWidget(
      _app(
        _page(
          gateway: gateway,
          onOpenPartner: (context, card, profile) async {
            if (profile['limousine_available'] == true) opened += 1;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    _press(tester, limousineDiscoveryOffersCtaKey('limo_1'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(gateway.profileCalls, 1);
    expect(gateway.bookCalls, 0);
    expect(
      gateway.requestedPaths.contains(kLimousineDiscoveryBookPath),
      isFalse,
    );

    gateway.profileHandler = (_) async => <String, dynamic>{
      'partner_id': 'limo_1',
      'services': <String>['taxi'],
    };
    opened = 0;
    _press(tester, limousineDiscoveryProfileCtaKey('limo_1'));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(
      find.byKey(kLimousineDiscoveryProfileUnavailableKey),
      findsOneWidget,
    );
  });

  testWidgets('recommended and Testomgeving chrome follow NL/EN/FR/ES', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _workerCard(id: 'limo_1', name: 'Maison Noire'),
        ]),
      ),
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pumpAndSettle();
    for (final language in AppLanguage.values) {
      if (language == AppLanguage.de) continue;
      appLanguageNotifier.value = language;
      await tester.pump();
      expect(
        find.text(kLimousineDiscoveryRecommended.of(language)),
        findsOneWidget,
      );
      expect(
        find.text(kLimousineDiscoveryGatesOffTitle.of(language)),
        findsOneWidget,
      );
      expect(find.byKey(kLimousineDiscoveryLanguageTabsKey), findsNothing);
    }
  });

  testWidgets('phone and tablet layouts plus existing customer themes', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _workerCard(id: 'limo_1', name: 'Maison Noire'),
        ]),
      ),
    );

    Future<void> pump(Size size, Key layout) async {
      await tester.pumpWidget(_app(_page(gateway: gateway), size: size));
      await tester.pumpAndSettle();
      expect(find.byKey(layout), findsOneWidget);
      expect(find.text('Maison Noire'), findsOneWidget);
    }

    await pump(kLimousinePhonePortrait, kLimousineDiscoveryPhoneLayoutKey);
    await pump(
      kLimousineSmX400Portrait,
      kLimousineDiscoveryTabletPortraitLayoutKey,
    );
    await pump(
      kLimousineTabletLandscape,
      kLimousineDiscoveryTabletLandscapeLayoutKey,
    );

    for (final theme in <CustomerThemeVariant>[
      CustomerThemeVariant.premiumLight,
      CustomerThemeVariant.nightGold,
      CustomerThemeVariant.royalBlueGold,
      CustomerThemeVariant.ivoryGold,
    ]) {
      customerThemeNotifier.value = theme;
      await tester.pumpWidget(_app(_page(gateway: gateway)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Scaffold>(find.byKey(kLimousineCustomerDiscoveryPageKey))
            .backgroundColor,
        paletteForCustomerTheme(theme).background,
      );
      expect(tester.takeException(), isNull);
    }
  });

  test('postcode and coordinates only rank; they do not filter', () {
    expect(
      limousineDiscoveryQueryFromAddress(
        displayText: '9688, Maarkedal, Oost-Vlaanderen, België',
        lat: 50.796,
        lon: 3.621,
      )?.postcode,
      '9688',
    );
    expect(
      limousineDiscoveryQueryFromAddress(
        displayText: 'Korenmarkt 1, 9000 Gent, Belgium',
        lat: 51.0543,
        lon: 3.7174,
      )?.lat,
      51.0543,
    );
  });

  test('server-eligible published profile is visible even with gates off', () {
    final composition = composeLimousinePublicAvailability(<String, dynamic>{
      'subscription_status': 'active',
      'features': <String, dynamic>{'limousine': true},
      'is_active': true,
      'services': <String>['limousine'],
      'profile_enabled': true,
      'published_at': '2026-08-17T10:00:00Z',
      'bookable': false,
      'limousine_available': true,
      'vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'service_category': 'limousine',
          'service_class': 'executive_sedan',
          'is_active': true,
        },
      ],
    });
    expect(
      composition.state,
      LimousinePublicAvailabilityState.publiclyAvailable,
    );
    expect(
      limousineAvailabilityStateLabelFor(composition.state, AppLanguage.nl),
      'Gepubliceerd en zichtbaar',
    );
  });

  testWidgets('postcode keeps every company and only changes distance order', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        if (query.isUnscoped) {
          return LimousineDiscoveryPageData(
            listingMode: 'test_preview',
            cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
              _workerCard(id: 'far', name: 'Far Coach'),
              _workerCard(id: 'near', name: 'Near Coach'),
            ]),
          );
        }
        expect(query.postcode, '9688');
        return LimousineDiscoveryPageData(
          listingMode: 'test_preview',
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _workerCard(id: 'near', name: 'Near Coach', distanceKm: 2),
            _workerCard(id: 'far', name: 'Far Coach', distanceKm: 88),
          ]),
        );
      },
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pumpAndSettle();
    expect(find.text('Far Coach'), findsOneWidget);
    expect(find.text('Near Coach'), findsOneWidget);
    await tester.enterText(
      find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
      '9688, Maarkedal',
    );
    await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
    await tester.pumpAndSettle();
    expect(find.text('Far Coach'), findsOneWidget);
    expect(find.text('Near Coach'), findsOneWidget);
    final names = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data)
        .whereType<String>()
        .toList();
    expect(names.indexOf('Near Coach'), lessThan(names.indexOf('Far Coach')));
    expect(find.text(kLimousineDiscoveryEmptyTitle.nl), findsNothing);
  });

  testWidgets('empty state appears only when the public set is truly empty', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async =>
          const LimousineDiscoveryPageData(listingMode: 'test_preview'),
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pumpAndSettle();
    expect(find.text(kLimousineDiscoveryEmptyTitle.nl), findsOneWidget);
    expect(find.textContaining('in deze regio'), findsNothing);
    expect(find.text(kLimousineDiscoveryGatesOffTitle.nl), findsNothing);
  });

  testWidgets('new search keeps previous cards visible while loading', (
    tester,
  ) async {
    final next = Completer<LimousineDiscoveryPageData>();
    var calls = 0;
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        calls += 1;
        if (calls == 1) {
          return LimousineDiscoveryPageData(
            listingMode: 'test_preview',
            cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
              _workerCard(id: 'limo_1', name: 'Maison Noire'),
            ]),
          );
        }
        return next.future;
      },
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pumpAndSettle();
    expect(find.text('Maison Noire'), findsOneWidget);
    await tester.enterText(
      find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
      '9688',
    );
    await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
    await tester.pump();
    expect(find.text('Maison Noire'), findsOneWidget);
    expect(find.byKey(kLimousineDiscoveryLoadingKey), findsOneWidget);
    next.complete(
      LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _workerCard(id: 'limo_1', name: 'Maison Noire', distanceKm: 1.2),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Maison Noire'), findsOneWidget);
  });
}
