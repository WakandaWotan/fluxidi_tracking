import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_brand_logo.dart';
import 'package:fluxidi_tracking/limousine/limousine_current_location.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';

Map<String, dynamic> _publishedLimousinePartner({
  required String id,
  required String name,
  double? distanceKm,
  String presentation = 'from_price',
  int? amountCents = 45000,
  String city = 'Gent',
  bool verified = true,
  double? operatingBaseLat,
  double? operatingBaseLng,
  String? logoUrl,
}) {
  return <String, dynamic>{
    'partner_id': id,
    'company_name': name,
    'is_active': true,
    'limousine_available': true,
    'public_city': city,
    if (logoUrl != null) 'logo_url': logoUrl,
    if (distanceKm != null) 'distance_km': distanceKm,
    'trust': <String, dynamic>{'verified_partner': verified},
    'hero_photo_url': 'https://cdn.example/cover.jpg',
    if (operatingBaseLat != null)
      'operating_base': <String, dynamic>{
        'lat': operatingBaseLat,
        'lng': operatingBaseLng,
      },
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'service_category': 'limousine',
        'is_active': true,
        'photo_url': 'https://cdn.example/v1.jpg',
        'service_class_id': 'executive_sedan',
        'passenger_capacity': 3,
        'luggage_capacity': 2,
      },
    ],
    'limousine_offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'off_$id',
        'enabled': true,
        'published': true,
        'price_presentation': presentation,
        if (amountCents != null) 'display_amount_cents': amountCents,
        'currency': 'EUR',
      },
    ],
  };
}

Map<String, dynamic> _taxiOnlyPartner() {
  return <String, dynamic>{
    'partner_id': 'taxi_1',
    'company_name': 'City Taxi',
    'is_active': true,
    'services': <String>['taxi'],
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'Stretch Limousine',
        'brand': 'Mercedes',
        'category': 'limousine',
        'service_category': 'taxi',
      },
    ],
  };
}

Map<String, dynamic> _draftLimousinePartner() {
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
        'display_amount_cents': 12000,
        'currency': 'EUR',
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
  _LocationHarness({
    this.servicesEnabled = true,
    this.permission = LimousineLocationPermission.granted,
    Future<LimousineCurrentLocationFix> Function()? position,
  }) {
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
      isLocationServiceEnabled: () async => servicesEnabled,
      checkPermission: () async => permission,
      requestPermission: () async => permission,
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
  }

  late final LimousinePlaceLookup lookup;
  late final LimousineCurrentLocationPlatform platform;
  bool servicesEnabled;
  LimousineLocationPermission permission;
  int positionCalls = 0;
  int reverseCalls = 0;
  int settingsOpens = 0;
}

void _press(WidgetTester tester, Key key) {
  tester.widget<ButtonStyleButton>(find.byKey(key)).onPressed!();
}

Widget _app(
  Widget child, {
  Size size = kLimousinePhonePortrait,
  double textScale = 1,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child,
    ),
  );
}

LimousineCustomerDiscoveryPage _page({
  required MemoryLimousineDiscoveryGateway gateway,
  LimousineDiscoveryController? controller,
  _LocationHarness? location,
  LimousineDiscoveryOpenPartner? onOpenPartner,
}) {
  final harness = location ?? _LocationHarness();
  return LimousineCustomerDiscoveryPage(
    gateway: gateway,
    controller: controller,
    placeLookup: harness.lookup,
    currentLocationPlatform: harness.platform,
    onOpenPartner: onOpenPartner,
    customerHomeBuilder: (_) => const SizedBox.shrink(),
    autoLoadRecommended: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('customer entry opens discovery instead of the request wizard', () {
    final home = File(
      'lib/main_parts/customer_home_page.dart',
    ).readAsStringSync();
    expect(home.contains('openLimousineCustomerDiscovery('), isTrue);
    expect(home.contains('openLimousineCustomerQuoteFlow(context)'), isFalse);
    expect(home.contains('kLimousineRequestWizardKey'), isFalse);
    final discovery = File(
      'lib/limousine/limousine_customer_discovery_page.dart',
    ).readAsStringSync();
    expect(discovery.contains('openLimousineCustomerQuoteFlow'), isFalse);
    expect(discovery.contains("'/book'"), isFalse);
    expect(discovery.contains('createRequest'), isFalse);
  });

  test('committed nearby contract is documented and fail-closed', () {
    expect(kLimousineDiscoveryNearbyPath, '/partners/nearby');
    expect(kLimousineDiscoveryProfilePath, '/partners/profile');
    expect(
      kLimousineDiscoveryMissingWorkerContract.contains('limousine_available'),
      isTrue,
    );
    expect(
      kLimousineDiscoveryMissingWorkerContract.contains('service_category'),
      isTrue,
    );
    expect(
      kLimousineDiscoveryMissingWorkerContract.contains('operating-base'),
      isTrue,
    );
    final nearbyOnly = <String, dynamic>{
      'partner_id': 'p_near',
      'company_name': 'Taxi Nearby',
      'is_active': true,
      'services': <String>['taxi'],
      'distance_km': 2.4,
      'hero_photo_url': 'https://cdn.example/taxi.jpg',
    };
    expect(limousineDiscoveryPartnerIsIncludable(nearbyOnly), isFalse);
    expect(tryParseLimousineDiscoveryCard(nearbyOnly), isNull);
  });

  test('server-authoritative eligibility include and exclude rules', () {
    final valid = _publishedLimousinePartner(
      id: 'limo_1',
      name: 'Maison Noire',
    );
    expect(limousineDiscoveryPartnerIsIncludable(valid), isTrue);
    expect(tryParseLimousineDiscoveryCard(valid)?.companyName, 'Maison Noire');

    expect(limousineDiscoveryPartnerIsIncludable(_taxiOnlyPartner()), isFalse);
    expect(
      limousineDiscoveryPartnerIsIncludable(_draftLimousinePartner()),
      isFalse,
    );

    final nameOnly = <String, dynamic>{
      'partner_id': 'name_1',
      'company_name': 'Looks Like Limo',
      'is_active': true,
      'vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'Mercedes Limousine',
          'brand': 'Mercedes',
          'category': 'limousine',
        },
      ],
    };
    expect(limousineDiscoveryPartnerIsIncludable(nameOnly), isFalse);

    final preview = Map<String, dynamic>.from(valid)
      ..['limousine_available'] = false
      ..['client_preview'] = true;
    expect(limousineDiscoveryPartnerIsIncludable(preview), isFalse);

    final unpublishedVehicle = _publishedLimousinePartner(
      id: 'limo_2',
      name: 'Hidden Fleet',
    );
    unpublishedVehicle['vehicles'] = <Map<String, dynamic>>[
      <String, dynamic>{
        'service_category': 'limousine',
        'is_active': false,
        'draft': true,
      },
    ];
    expect(limousineDiscoveryPartnerIsIncludable(unpublishedVehicle), isFalse);
  });

  test('nearest ordering uses the server list, not private coordinates', () {
    final far = _publishedLimousinePartner(
      id: 'far',
      name: 'Far Coach',
      distanceKm: 40,
      operatingBaseLat: 51.05,
      operatingBaseLng: 3.72,
    );
    final near = _publishedLimousinePartner(
      id: 'near',
      name: 'Near Coach',
      distanceKm: 5,
      operatingBaseLat: 50.0,
      operatingBaseLng: 4.0,
    );
    final cards = limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
      far,
      near,
    ]);
    expect(cards.map((card) => card.publicPartnerId).toList(), <String>[
      'far',
      'near',
    ]);
    expect(cards.first.distanceKm, 40);
    expect(cards.last.distanceKm, 5);
  });

  test('price-on-request and starting-price cards stay factual', () {
    final quote = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(
        id: 'q1',
        name: 'Quote House',
        presentation: 'quote_required',
        amountCents: 99999,
      ),
    )!;
    expect(
      limousineDiscoveryPriceLabel(quote.price, AppLanguage.nl),
      kLimousineDiscoveryQuoteOnRequest.nl,
    );
    expect(quote.price.kind, LimousineDiscoveryPriceKind.quoteRequired);

    final from = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(
        id: 'f1',
        name: 'From House',
        presentation: 'from_price',
        amountCents: 45000,
      ),
    )!;
    expect(
      limousineDiscoveryPriceLabel(from.price, AppLanguage.nl),
      'Vanaf €450',
    );

    final fixed = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(
        id: 'x1',
        name: 'Fixed House',
        presentation: 'exact_fixed',
        amountCents: 18000,
      ),
    )!;
    expect(
      limousineDiscoveryPriceLabel(fixed.price, AppLanguage.nl),
      'Vaste prijs · €180',
    );

    final noAmount = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(
        id: 'n1',
        name: 'No Amount',
        presentation: 'from_price',
        amountCents: null,
      ),
    )!;
    expect(limousineDiscoveryPriceLabel(noAmount.price, AppLanguage.nl), '');
  });

  test('cards never fabricate rating, price or distance', () {
    final partner = _publishedLimousinePartner(
      id: 'limo_1',
      name: 'Maison Noire',
    );
    partner.remove('distance_km');
    final card = tryParseLimousineDiscoveryCard(partner)!;
    expect(card.distanceKm, isNull);
    expect(card.price.kind, isNot(LimousineDiscoveryPriceKind.none));
    expect(
      limousineDiscoveryCardShowsFabricatedSocialProof(card.companyName),
      isFalse,
    );
    expect(card.publicCity, 'Gent');
    expect(card.verifiedPartner, isTrue);
  });

  testWidgets('entry route shows discovery, not the four-step wizard', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () => openLimousineCustomerDiscovery(
                  context,
                  gateway: gateway,
                  placeLookup: _LocationHarness().lookup,
                  currentLocationPlatform: _LocationHarness().platform,
                  customerHomeBuilder: (_) => const SizedBox.shrink(),
                ),
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineCustomerDiscoveryPageKey), findsOneWidget);
    expect(find.byKey(kLimousineRequestWizardKey), findsNothing);
    expect(find.byKey(kLimousineCustomerQuotePageKey), findsNothing);
  });

  testWidgets('automatic NL/EN/FR/ES chrome without language tabs', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway();
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.pump();

    for (final language in <AppLanguage>[
      AppLanguage.nl,
      AppLanguage.en,
      AppLanguage.fr,
      AppLanguage.es,
    ]) {
      appLanguageNotifier.value = language;
      await tester.pump();
      expect(find.byKey(kLimousineDiscoveryTitleKey), findsOneWidget);
      expect(find.text(kLimousineDiscoveryTitle.of(language)), findsOneWidget);
      expect(
        find.text(kLimousineDiscoverySubtitle.of(language)),
        findsOneWidget,
      );
      expect(
        find.text(kLimousineDiscoverySearchAction.of(language)),
        findsOneWidget,
      );
      expect(find.byKey(kLimousineDiscoveryLanguageTabsKey), findsNothing);
      expect(find.byType(TabBar), findsNothing);
      expect(find.text('NL'), findsNothing);
      expect(find.text('EN'), findsNothing);
      expect(find.text('FR'), findsNothing);
      expect(find.text('ES'), findsNothing);
    }
  });

  testWidgets('structured postcode and place search uses nearby, not /book', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        expect(query.postcode, '9000');
        expect(query.lat, isNull);
        return LimousineDiscoveryPageData(
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _publishedLimousinePartner(id: 'limo_1', name: 'Maison Noire'),
          ]),
        );
      },
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.enterText(
      find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
      '9000 Gent',
    );
    await tester.pump();
    await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
    await tester.pumpAndSettle();
    expect(gateway.searchCalls, 1);
    expect(gateway.requestedPaths, <String>[kLimousineDiscoveryNearbyPath]);
    expect(gateway.bookCalls, 0);
    expect(gateway.createQuoteCalls, 0);
    expect(find.text('Maison Noire'), findsOneWidget);
    expect(find.text('City Taxi'), findsNothing);
  });

  testWidgets(
    'place suggestion search keeps server coordinates, not a private base',
    (tester) async {
      final gateway = MemoryLimousineDiscoveryGateway(
        searchHandler: (query) async {
          expect(query.lat, closeTo(51.0543, 0.0001));
          expect(query.lng, closeTo(3.7174, 0.0001));
          return const LimousineDiscoveryPageData();
        },
      );
      final location = _LocationHarness();
      await tester.pumpWidget(
        _app(_page(gateway: gateway, location: location)),
      );
      await tester.enterText(
        find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
        'Gent',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 230));
      tester
          .widget<ListTile>(
            find.byKey(
              limousineAddressSuggestionKey(kLimousineDiscoveryFieldId, 0),
            ),
          )
          .onTap!();
      await tester.pumpAndSettle();
      expect(gateway.searchCalls, 1);
      expect(gateway.lastQuery?.postcode, isNull);
    },
  );

  testWidgets('explicit current location success starts one nearby search', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        expect(query.lat, 51.0543);
        expect(query.lng, 3.7174);
        return const LimousineDiscoveryPageData();
      },
    );
    final location = _LocationHarness();
    await tester.pumpWidget(_app(_page(gateway: gateway, location: location)));
    await tester.tap(
      find.byKey(
        limousineAddressCurrentLocationKey(kLimousineDiscoveryFieldId),
      ),
    );
    await tester.pumpAndSettle();
    expect(location.positionCalls, 1);
    expect(location.reverseCalls, 1);
    expect(gateway.searchCalls, 1);
    expect(find.byKey(kLimousineDiscoveryEmptyKey), findsOneWidget);
    expect(find.text('City Taxi'), findsNothing);
    expect(find.textContaining('Vanaf €'), findsNothing);
  });

  testWidgets(
    'disabled location services stay on discovery without searching',
    (tester) async {
      final gateway = MemoryLimousineDiscoveryGateway();
      final location = _LocationHarness(servicesEnabled: false);
      await tester.pumpWidget(
        _app(_page(gateway: gateway, location: location)),
      );
      await tester.tap(
        find.byKey(
          limousineAddressCurrentLocationKey(kLimousineDiscoveryFieldId),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.searchCalls, 0);
      expect(
        find.byKey(
          limousineAddressCurrentLocationErrorKey(kLimousineDiscoveryFieldId),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'current location failure keeps search controls and offers settings',
    (tester) async {
      final gateway = MemoryLimousineDiscoveryGateway();
      final location = _LocationHarness(
        permission: LimousineLocationPermission.deniedForever,
      );
      await tester.pumpWidget(
        _app(_page(gateway: gateway, location: location)),
      );
      await tester.tap(
        find.byKey(
          limousineAddressCurrentLocationKey(kLimousineDiscoveryFieldId),
        ),
      );
      await tester.pumpAndSettle();
      expect(gateway.searchCalls, 0);
      expect(
        find.byKey(
          limousineAddressCurrentLocationErrorKey(kLimousineDiscoveryFieldId),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(limousineAddressOpenSettingsKey(kLimousineDiscoveryFieldId)),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(limousineAddressOpenSettingsKey(kLimousineDiscoveryFieldId)),
      );
      await tester.pump();
      expect(location.settingsOpens, 1);
      expect(
        find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
        findsOneWidget,
      );
    },
  );

  testWidgets('double-tap suppression while resolving location and search', (
    tester,
  ) async {
    final location = _LocationHarness(
      position: () async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        return const LimousineCurrentLocationFix(
          latitude: 51.0543,
          longitude: 3.7174,
        );
      },
    );
    await tester.pumpWidget(
      _app(
        _page(gateway: MemoryLimousineDiscoveryGateway(), location: location),
      ),
    );
    final locationKey = limousineAddressCurrentLocationKey(
      kLimousineDiscoveryFieldId,
    );
    await tester.tap(find.byKey(locationKey));
    await tester.tap(find.byKey(locationKey));
    await tester.pump();
    expect(location.positionCalls, 1);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpAndSettle();

    final started = Completer<void>();
    final release = Completer<void>();
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (query) async {
        if (!started.isCompleted) started.complete();
        await release.future;
        return const LimousineDiscoveryPageData();
      },
    );
    final controller = LimousineDiscoveryController(gateway: gateway);
    unawaited(
      controller.search(const LimousineDiscoveryQuery(postcode: '9000')),
    );
    await started.future;
    await controller.search(const LimousineDiscoveryQuery(postcode: '2000'));
    expect(controller.suppressedSearchTaps, greaterThanOrEqualTo(1));
    expect(gateway.searchCalls, 1);
    release.complete();
  });

  testWidgets('gates-off shows a polished empty state without taxi fallback', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async =>
          const LimousineDiscoveryPageData(gatesOff: true),
    );
    await tester.pumpWidget(_app(_page(gateway: gateway)));
    await tester.enterText(
      find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
      '9000',
    );
    await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineDiscoveryGatesOffKey), findsOneWidget);
    expect(find.text(kLimousineDiscoveryGatesOffTitle.nl), findsOneWidget);
    expect(find.text('Maison Noire'), findsNothing);
    expect(find.text('City Taxi'), findsNothing);
    expect(find.byKey(kLimousineDiscoverySearchOtherRegionKey), findsOneWidget);
    expect(
      find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
      findsOneWidget,
    );
    _press(tester, kLimousineDiscoverySearchOtherRegionKey);
    await tester.pumpAndSettle();
    expect(gateway.searchCalls, 2);
    expect(gateway.lastQuery?.isUnscoped, isTrue);
  });

  testWidgets(
    'Bekijk aanbod opens a server-confirmed profile and never /book',
    (tester) async {
      final opened = <String>[];
      final gateway = MemoryLimousineDiscoveryGateway(
        searchHandler: (_) async => LimousineDiscoveryPageData(
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _publishedLimousinePartner(id: 'limo_1', name: 'Maison Noire'),
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
              opened.add(
                profile['limousine_available'] == true
                    ? card.publicPartnerId
                    : 'unconfirmed',
              );
            },
          ),
        ),
      );
      await tester.enterText(
        find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
        '9000',
      );
      await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
      await tester.pumpAndSettle();
      expect(find.text('Maison Noire'), findsOneWidget);
      expect(find.text('Vanaf €450'), findsNothing);
      expect(find.textContaining('★'), findsNothing);
      _press(tester, limousineDiscoveryViewLimousinesCtaKey('limo_1'));
      await tester.pumpAndSettle();
      expect(opened, <String>['limo_1']);
      expect(gateway.profileCalls, 1);
      expect(gateway.bookCalls, 0);
      expect(gateway.createQuoteCalls, 0);
      expect(
        gateway.requestedPaths.contains(kLimousineDiscoveryBookPath),
        isFalse,
      );
      expect(find.byKey(kLimousineRequestWizardKey), findsNothing);
    },
  );

  testWidgets(
    'profile without a Limousine surface does not open or create a quote',
    (tester) async {
      var opened = 0;
      final gateway = MemoryLimousineDiscoveryGateway(
        searchHandler: (_) async => LimousineDiscoveryPageData(
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _publishedLimousinePartner(id: 'limo_1', name: 'Maison Noire'),
          ]),
        ),
        profileHandler: (_) async => <String, dynamic>{
          'partner_id': 'limo_1',
          'services': <String>['taxi'],
        },
      );
      await tester.pumpWidget(
        _app(
          _page(
            gateway: gateway,
            onOpenPartner: (context, card, profile) async => opened += 1,
          ),
        ),
      );
      await tester.enterText(
        find.byKey(limousineAddressInputKey(kLimousineDiscoveryFieldId)),
        '9000',
      );
      await tester.tap(find.byKey(kLimousineDiscoverySearchActionKey));
      await tester.pumpAndSettle();
      _press(tester, limousineDiscoveryViewLimousinesCtaKey('limo_1'));
      await tester.pumpAndSettle();
      expect(opened, 0);
      expect(
        find.byKey(kLimousineDiscoveryProfileUnavailableKey),
        findsOneWidget,
      );
      expect(gateway.createQuoteCalls, 0);
    },
  );

  testWidgets('phone, tablet portrait and tablet landscape layouts', (
    tester,
  ) async {
    final card = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(id: 'limo_1', name: 'Maison Noire'),
    )!;
    final gateway = MemoryLimousineDiscoveryGateway();
    final controller = LimousineDiscoveryController(gateway: gateway);
    controller.phase = LimousineDiscoveryPhase.ready;
    controller.cards = <LimousineDiscoveryCard>[card];

    Future<void> pump(Size size, Key layout) async {
      await tester.pumpWidget(
        _app(
          _page(gateway: gateway, controller: controller),
          size: size,
        ),
      );
      await tester.pump();
      expect(find.byKey(layout), findsOneWidget);
      expect(find.byKey(limousineDiscoveryCardKey('limo_1')), findsOneWidget);
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
  });

  testWidgets('light, dark, blue and gold themes plus larger text', (
    tester,
  ) async {
    final card = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(id: 'limo_1', name: 'Maison Noire'),
    )!;
    final gateway = MemoryLimousineDiscoveryGateway();
    final controller = LimousineDiscoveryController(gateway: gateway);
    controller.phase = LimousineDiscoveryPhase.ready;
    controller.cards = <LimousineDiscoveryCard>[card];

    final themes = <CustomerThemeVariant>[
      CustomerThemeVariant.premiumLight,
      CustomerThemeVariant.nightGold,
      CustomerThemeVariant.royalBlueGold,
      CustomerThemeVariant.ivoryGold,
    ];
    for (final theme in themes) {
      customerThemeNotifier.value = theme;
      await tester.pumpWidget(
        _app(_page(gateway: gateway, controller: controller), textScale: 1.6),
      );
      await tester.pump();
      final scaffold = tester.widget<Scaffold>(
        find.byKey(kLimousineCustomerDiscoveryPageKey),
      );
      expect(
        scaffold.backgroundColor,
        paletteForCustomerTheme(theme).background,
      );
      expect(find.text('Maison Noire'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  test('discovery cards keep partner logos off the vehicle photo', () {
    final page = File(
      'lib/limousine/limousine_customer_discovery_page.dart',
    ).readAsStringSync();
    final card = File(
      'lib/limousine/limousine_public_company_card.dart',
    ).readAsStringSync();
    final identity = File(
      'lib/limousine/limousine_brand_logo.dart',
    ).readAsStringSync();
    expect(page.contains('LimousineBrandLogoCorner'), isFalse);
    expect(page.contains('LimousineBrandLogoPlaque'), isFalse);
    expect(card.contains('LimousineDiscoveryCompanyIdentity'), isTrue);
    expect(page.contains("'Fluxidi'"), isFalse);
    expect(page.contains('"Fluxidi"'), isFalse);
    expect(identity.contains("companyName: 'Fluxidi'"), isFalse);
    expect(identity.contains("return 'Fluxidi'"), isFalse);
  });

  test('discovery cards parse the public partner logo URL', () {
    final withLogo = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(
        id: 'limo_1',
        name: 'Maison Noire',
        logoUrl: 'https://cdn.example/logo.png',
      ),
    )!;
    expect(withLogo.logoUrl, 'https://cdn.example/logo.png');
    expect(withLogo.companyName, 'Maison Noire');

    final withoutLogo = tryParseLimousineDiscoveryCard(
      _publishedLimousinePartner(id: 'limo_2', name: 'Atelier Or'),
    )!;
    expect(withoutLogo.logoUrl, isEmpty);
    expect(withoutLogo.companyName, 'Atelier Or');
  });

  testWidgets(
    'ready cards show company-name fallback and never overlay the photo',
    (tester) async {
      final card = tryParseLimousineDiscoveryCard(
        _publishedLimousinePartner(id: 'limo_1', name: 'Maison Noire'),
      )!;
      final gateway = MemoryLimousineDiscoveryGateway();
      final controller = LimousineDiscoveryController(gateway: gateway);
      controller.phase = LimousineDiscoveryPhase.ready;
      controller.cards = <LimousineDiscoveryCard>[card];

      Future<void> pump(Size size) async {
        await tester.pumpWidget(
          _app(
            _page(gateway: gateway, controller: controller),
            size: size,
          ),
        );
        await tester.pump();
        expect(find.byType(LimousineBrandLogoCorner), findsNothing);
        expect(find.byType(LimousineBrandLogoPlaque), findsNothing);
        expect(
          find.byKey(limousineDiscoveryCardTitleKey('limo_1')),
          findsOneWidget,
        );
        expect(find.text('Maison Noire'), findsOneWidget);
        expect(find.text('Fluxidi'), findsNothing);
        expect(find.byType(LimousineContainPhoto), findsOneWidget);

        final photo = tester.getRect(find.byType(LimousineContainPhoto));
        final title = tester.getRect(
          find.byKey(limousineDiscoveryCardTitleKey('limo_1')),
        );
        expect(photo.overlaps(title), isFalse);
        expect(
          find.byKey(limousineDiscoveryOffersCtaKey('limo_1')),
          findsOneWidget,
        );
        expect(
          find.byKey(limousineDiscoveryProfileCtaKey('limo_1')),
          findsOneWidget,
        );
      }

      await pump(kLimousinePhonePortrait);
      await pump(kLimousineSmX400Portrait);
      await pump(kLimousineTabletLandscape);
    },
  );
}
