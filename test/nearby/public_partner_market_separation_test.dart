import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom_section.dart';
import 'package:fluxidi_tracking/nearby/public_partner_market.dart';
import 'package:fluxidi_tracking/partner_public_profile_page.dart';

Map<String, dynamic> _vehicle({
  required String id,
  required String name,
  required String category,
  required String photo,
  String serviceClass = 'first_class_sedan',
}) {
  return <String, dynamic>{
    'vehicle_id': id,
    'name': name,
    'brand_model': name,
    'category': category == 'limousine' ? 'Limousine' : 'Taxi',
    'service_category': category,
    'service_class': serviceClass,
    'is_active': true,
    'photo_url': photo,
    'pax': 4,
    'luggage': 2,
    'passenger_capacity': 4,
    'luggage_capacity': 2,
  };
}

Map<String, dynamic> _offer({
  String id = 'off_night',
  String vehicleId = 'limo_cadillac',
}) {
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': true,
    'target_type': 'vehicle',
    'vehicle_id': vehicleId,
    'vehicle_ids': <String>[vehicleId],
    'title': <String, String>{
      'nl': 'Nachtelijk arrangement',
      'en': 'Night package',
    },
    'price_presentation': 'from_price',
    'display_amount_cents': 18000,
    'currency': 'EUR',
  };
}

Map<String, dynamic> _mixedCompany() {
  return <String, dynamic>{
    'partner_id': 'mix_1',
    'company_name': 'Maison Noire',
    'about_short': 'Taxi en limousine onder dezelfde identiteit',
    'bookable': true,
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'airport_service_enabled': true,
    'services': <String>['taxi_vvb', 'airport_transfer', 'limousine'],
    'payment_methods': <String>['bancontact', 'cash'],
    'country': 'BE',
    'media': <String, dynamic>{
      'logo_url': 'https://cdn.example/logo.webp',
      'hero_photo_url': 'https://cdn.example/taxi-hero.webp',
      'limousine_cover_url': 'https://cdn.example/limo-cover.webp',
      'gallery': <String>[
        'https://cdn.example/taxi-gallery.webp',
        'https://cdn.example/limo-cover.webp',
        'https://cdn.example/cadillac.webp',
      ],
    },
    'public_contact': <String, dynamic>{
      'website': 'https://maison-noire.example',
      'public_phone': '+32 9 000 11 22',
      'booking_email': 'book@maison-noire.example',
    },
    'coverage': <String, dynamic>{
      'region_label': 'Gent',
      'postcodes': <String>['9000', '9050'],
    },
    'drivers': <Map<String, dynamic>>[
      <String, dynamic>{
        'display_name': 'Jan Peeters',
        'languages': <String>['nl'],
      },
    ],
    'vehicles': <Map<String, dynamic>>[
      _vehicle(
        id: 'taxi_sedan',
        name: 'City Sedan',
        category: 'taxi',
        photo: 'https://cdn.example/taxi-sedan.webp',
      ),
      _vehicle(
        id: 'taxi_shuttle',
        name: 'Limo Shuttle',
        category: '',
        photo: 'https://cdn.example/taxi-van.webp',
      ),
      _vehicle(
        id: 'limo_cadillac',
        name: 'Cadillac Stretch',
        category: 'limousine',
        photo: 'https://cdn.example/cadillac.webp',
      ),
      _vehicle(
        id: 'limo_hummer',
        name: 'Hummer H2',
        category: 'limousine',
        photo: 'https://cdn.example/hummer.webp',
      ),
    ],
    'limousine_vehicles': <Map<String, dynamic>>[
      _vehicle(
        id: 'limo_cadillac',
        name: 'Cadillac Stretch',
        category: 'limousine',
        photo: 'https://cdn.example/cadillac.webp',
      ),
      _vehicle(
        id: 'limo_hummer',
        name: 'Hummer H2',
        category: 'limousine',
        photo: 'https://cdn.example/hummer.webp',
      ),
    ],
    'limousine_offers': <Map<String, dynamic>>[_offer()],
  };
}

Map<String, dynamic> _taxiOnlyCompany() {
  return <String, dynamic>{
    'partner_id': 'taxi_only',
    'company_name': 'City Taxi',
    'bookable': true,
    'is_active': true,
    'profile_enabled': true,
    'airport_service_enabled': true,
    'services': <String>['taxi_vvb', 'airport_transfer'],
    'payment_methods': <String>['cash'],
    'media': <String, dynamic>{
      'hero_photo_url': 'https://cdn.example/city-taxi-hero.webp',
    },
    'vehicles': <Map<String, dynamic>>[
      _vehicle(
        id: 'taxi_a',
        name: 'Skoda Octavia',
        category: 'taxi',
        photo: 'https://cdn.example/octavia.webp',
      ),
      _vehicle(
        id: 'taxi_b',
        name: 'Mercedes Vito',
        category: 'taxi',
        photo: 'https://cdn.example/vito.webp',
      ),
    ],
    'drivers': <Map<String, dynamic>>[
      <String, dynamic>{'display_name': 'Piet Taxi'},
    ],
    'coverage': <String, dynamic>{'region_label': 'Antwerpen'},
    'public_contact': <String, dynamic>{'public_phone': '+32 3 111 22 33'},
  };
}

Map<String, dynamic> _limousineOnlyCompany() {
  return <String, dynamic>{
    'partner_id': 'limo_only',
    'company_name': 'Only Limo',
    'bookable': true,
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'services': <String>['limousine'],
    'media': <String, dynamic>{
      'limousine_cover_url': 'https://cdn.example/only-limo-cover.webp',
    },
    'vehicles': <Map<String, dynamic>>[
      _vehicle(
        id: 'limo_only_1',
        name: 'Phantom',
        category: 'limousine',
        photo: 'https://cdn.example/phantom.webp',
      ),
    ],
    'limousine_vehicles': <Map<String, dynamic>>[
      _vehicle(
        id: 'limo_only_1',
        name: 'Phantom',
        category: 'limousine',
        photo: 'https://cdn.example/phantom.webp',
      ),
    ],
    'limousine_offers': <Map<String, dynamic>>[
      _offer(id: 'off_only', vehicleId: 'limo_only_1'),
    ],
  };
}

Widget _pageApp(Widget page) => MaterialApp(home: page);

Future<void> _pumpProfile(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(400, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_pageApp(page));
  await tester.pump();
}

Finder _networkImage(String url) {
  return find.byWidgetPredicate((widget) {
    if (widget is Image && widget.image is NetworkImage) {
      return (widget.image! as NetworkImage).url == url;
    }
    return false;
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mixed = _mixedCompany();
  final taxiCatalog = selectPublicPartnerMarketCatalog(
    profile: mixed,
    market: PublicPartnerMarket.taxi,
  );
  final limoCatalog = selectPublicPartnerMarketCatalog(
    profile: mixed,
    market: PublicPartnerMarket.limousine,
  );

  test('authoritative classification ignores Hummer and Limo names', () {
    expect(taxiCatalog.vehicles.map(publicPartnerVehicleId), <String>[
      'taxi_sedan',
      'taxi_shuttle',
    ]);
    expect(limoCatalog.vehicles.map(publicPartnerVehicleId), <String>[
      'limo_cadillac',
      'limo_hummer',
    ]);
    expect(taxiCatalog.services, isNot(contains('limousine')));
    expect(
      taxiCatalog.services,
      containsAll(<String>['taxi_vvb', 'airport_transfer']),
    );
    expect(taxiCatalog.heroPhotoUrl, 'https://cdn.example/taxi-hero.webp');
    expect(taxiCatalog.gallery, <String>[
      'https://cdn.example/taxi-gallery.webp',
    ]);
    expect(taxiCatalog.showLimousineOffers, isFalse);
    expect(limoCatalog.heroPhotoUrl, 'https://cdn.example/limo-cover.webp');
    expect(limoCatalog.showLimousineOffers, isTrue);
  });

  test('taxi hero never falls back to the limousine cover or gallery', () {
    final leaked = Map<String, dynamic>.from(mixed);
    leaked['media'] = <String, dynamic>{
      'hero_photo_url': 'https://cdn.example/limo-cover.webp',
      'limousine_cover_url': 'https://cdn.example/limo-cover.webp',
      'gallery': <String>['https://cdn.example/cadillac.webp'],
    };
    final catalog = selectPublicPartnerMarketCatalog(
      profile: leaked,
      market: PublicPartnerMarket.taxi,
    );
    expect(catalog.heroPhotoUrl, isEmpty);
    expect(catalog.gallery, isEmpty);
  });

  test('mixed company appears in both search markets with split catalogs', () {
    expect(publicPartnerAppearsInTaxiSearch(mixed), isTrue);
    expect(limousineDiscoveryPartnerIsIncludable(mixed), isTrue);
    expect(publicPartnerAppearsInTaxiSearch(_taxiOnlyCompany()), isTrue);
    expect(limousineDiscoveryPartnerIsIncludable(_taxiOnlyCompany()), isFalse);
    expect(publicPartnerAppearsInTaxiSearch(_limousineOnlyCompany()), isFalse);
    expect(
      limousineDiscoveryPartnerIsIncludable(_limousineOnlyCompany()),
      isTrue,
    );
  });

  test('deep links keep the explicit market context', () {
    final taxiRoute = publicPartnerMarketRouteName(
      partnerId: 'mix_1',
      market: PublicPartnerMarket.taxi,
    );
    final limoRoute = publicPartnerMarketRouteName(
      partnerId: 'mix_1',
      market: PublicPartnerMarket.limousine,
    );
    final airportRoute = publicPartnerMarketRouteName(
      partnerId: 'mix_1',
      market: PublicPartnerMarket.airport,
    );
    expect(
      publicPartnerMarketFromUri(Uri.parse(taxiRoute)),
      PublicPartnerMarket.taxi,
    );
    expect(
      publicPartnerMarketFromUri(Uri.parse(limoRoute)),
      PublicPartnerMarket.limousine,
    );
    expect(
      publicPartnerMarketFromUri(Uri.parse(airportRoute)),
      PublicPartnerMarket.airport,
    );
    expect(taxiRoute, contains('market=taxi'));
    expect(limoRoute, contains('market=limousine'));
  });

  test('nearby taxi entry stores taxi market, not a visual tab', () {
    final nearby = File('lib/nearby_partners_page.dart').readAsStringSync();
    expect(nearby.contains('PublicPartnerMarket.taxi'), isTrue);
    expect(nearby.contains('publicPartnerMarketRouteSettings'), isTrue);
    expect(nearby.contains('publicPartnerAppearsInTaxiSearch'), isTrue);
  });

  testWidgets('taxi profile hides limousine catalog and keeps taxi chrome', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      PartnerPublicProfilePage(
        partnerId: 'mix_1',
        companyNameFallback: 'Maison Noire',
        customerHomeBuilder: (_) => const SizedBox.shrink(),
        limousineShowroomEnabled: true,
        market: PublicPartnerMarket.taxi,
        profileOverride: mixed,
      ),
    );
    expect(
      find.byKey(publicPartnerProfilePageKey(PublicPartnerMarket.taxi)),
      findsOneWidget,
    );
    expect(find.text('City Sedan'), findsOneWidget);
    expect(find.text('Limo Shuttle'), findsOneWidget);
    expect(find.text('Cadillac Stretch'), findsNothing);
    expect(find.text('Hummer H2'), findsNothing);
    expect(
      find.byKey(publicPartnerProfileVehicleKey('taxi_sedan')),
      findsOneWidget,
    );
    expect(
      find.byKey(publicPartnerProfileVehicleKey('limo_cadillac')),
      findsNothing,
    );
    expect(find.text('Limousines en arrangementen'), findsNothing);
    expect(find.text('Nachtelijk arrangement'), findsNothing);
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsNothing);
    expect(find.text('Limousine'), findsNothing);
    expect(find.text('Bekijk limousine'), findsNothing);
    expect(_networkImage('https://cdn.example/limo-cover.webp'), findsNothing);
    expect(_networkImage('https://cdn.example/cadillac.webp'), findsNothing);
    expect(find.text('Jan Peeters'), findsOneWidget);
    expect(find.textContaining('Gent'), findsWidgets);
    expect(find.textContaining('+32 9 000 11 22'), findsOneWidget);
    expect(find.byKey(kPublicPartnerProfilePaymentsSectionKey), findsOneWidget);
    expect(find.byIcon(Icons.local_taxi_outlined), findsWidgets);
    expect(find.byIcon(Icons.flight_takeoff_rounded), findsWidgets);
    expect(find.byKey(kPublicPartnerProfileServicesSectionKey), findsOneWidget);
    expect(find.text('Taxi & VVB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('airport market on the taxi page still hides limousines', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      PartnerPublicProfilePage(
        partnerId: 'mix_1',
        companyNameFallback: 'Maison Noire',
        customerHomeBuilder: (_) => const SizedBox.shrink(),
        market: PublicPartnerMarket.airport,
        profileOverride: mixed,
      ),
    );
    expect(
      find.byKey(publicPartnerProfilePageKey(PublicPartnerMarket.airport)),
      findsOneWidget,
    );
    expect(find.text('City Sedan'), findsOneWidget);
    expect(find.text('Cadillac Stretch'), findsNothing);
    expect(find.text('Limousines en arrangementen'), findsNothing);
    expect(find.byIcon(Icons.flight_takeoff_rounded), findsWidgets);
  });

  testWidgets('limousine profile keeps limousine catalog and drops taxi cars', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      LimousinePublicProfilePage(
        partnerId: 'mix_1',
        companyNameFallback: 'Maison Noire',
        profile: mixed,
        market: PublicPartnerMarket.limousine,
      ),
    );
    expect(find.byKey(kLimousinePublicProfilePageKey), findsOneWidget);
    expect(find.text('Cadillac Stretch'), findsWidgets);
    expect(find.text('Hummer H2'), findsWidgets);
    expect(find.text('City Sedan'), findsNothing);
    expect(find.text('Limo Shuttle'), findsNothing);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
    final profile = buildLimousinePublicProfileData(profile: mixed);
    expect(
      profile.showroom.heroPhotoUrl,
      'https://cdn.example/limo-cover.webp',
    );
    expect(
      profile.showroom.vehicles.map((vehicle) => vehicle.vehicleId),
      <String>['limo_cadillac', 'limo_hummer'],
    );
    expect(
      collectLimousineShowroomOffers(mixed).map((offer) => offer.offerId),
      <String>['off_night'],
    );
  });

  testWidgets('pure taxi company stays unchanged', (tester) async {
    await _pumpProfile(
      tester,
      PartnerPublicProfilePage(
        partnerId: 'taxi_only',
        companyNameFallback: 'City Taxi',
        customerHomeBuilder: (_) => const SizedBox.shrink(),
        profileOverride: _taxiOnlyCompany(),
      ),
    );
    expect(find.text('Skoda Octavia'), findsOneWidget);
    expect(find.text('Mercedes Vito'), findsOneWidget);
    expect(find.byKey(kPublicPartnerProfileVehiclesSectionKey), findsOneWidget);
    expect(find.text('Limousines en arrangementen'), findsNothing);
    expect(find.byIcon(Icons.local_taxi_outlined), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('filtered-empty vehicle section does not leave a title', (
    tester,
  ) async {
    await _pumpProfile(
      tester,
      PartnerPublicProfilePage(
        partnerId: 'limo_only',
        companyNameFallback: 'Only Limo',
        customerHomeBuilder: (_) => const SizedBox.shrink(),
        market: PublicPartnerMarket.taxi,
        profileOverride: _limousineOnlyCompany(),
      ),
    );
    expect(find.text('Voertuigen'), findsNothing);
    expect(find.text('Phantom'), findsNothing);
    expect(find.text('Limousines en arrangementen'), findsNothing);
    expect(find.byKey(kPublicPartnerProfileVehiclesSectionKey), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy limousine payload cannot leak through the taxi UI filter',
    (tester) async {
      final leaked = Map<String, dynamic>.from(mixed);
      leaked['vehicles'] = <Map<String, dynamic>>[
        ...((mixed['vehicles'] as List).whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        )),
      ];
      await _pumpProfile(
        tester,
        PartnerPublicProfilePage(
          partnerId: 'mix_1',
          companyNameFallback: 'Maison Noire',
          customerHomeBuilder: (_) => const SizedBox.shrink(),
          limousineShowroomEnabled: true,
          profileOverride: leaked,
        ),
      );
      expect(find.byType(LimousinePublicShowroomSection), findsNothing);
      expect(find.text('Limousine'), findsNothing);
      expect(find.text('Cadillac Stretch'), findsNothing);
    },
  );
}
