import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_labels.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';
import 'package:fluxidi_tracking/partner_public_profile_page.dart';

Map<String, dynamic> _nearbyCard() {
  return <String, dynamic>{
    'partner_id': 'limo_1',
    'company_name': 'Maison Noire',
    'is_active': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'public_city': 'Gent',
    'distance_km': 12.4,
    'trust': <String, dynamic>{'verified_partner': true},
    'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
    'limousine_vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'service_category': 'limousine',
        'photo_url': 'https://cdn.example/limo.jpg',
        'service_class_id': 'executive_sedan',
        'passenger_capacity': 3,
        'luggage_capacity': 2,
      },
    ],
    'limousine_price_presentation': 'quote_required',
    'test_preview': true,
  };
}

Map<String, dynamic> _profile() {
  return <String, dynamic>{
    'partner_id': 'limo_1',
    'company_name': 'Maison Noire',
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'tagline': 'Chauffeured limousines',
    'about_short': 'Private limousine service.',
    'logo_url': 'https://cdn.example/logo.png',
    'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
    'rating_avg': 4.8,
    'rating_count': 12,
    'coverage': <String, dynamic>{'region_label': 'Oost-Vlaanderen'},
    'public_contact': <String, dynamic>{
      'website': 'https://maison.example',
      'public_phone': '+32 9 000 00 00',
      'booking_email': 'book@maison.example',
    },
    'trust': <String, dynamic>{'verified_partner': true},
    'services': <String>['limousine', 'taxi'],
    'payment_methods': <String>['visa'],
    'drivers': <Map<String, dynamic>>[
      <String, dynamic>{'display_name': 'Hidden Driver'},
    ],
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'name': 'S-Class',
        'brand_model': 'Mercedes',
        'category': 'Premium',
        'service_category': 'limousine',
        'service_class': 'executive_sedan',
        'pax': 3,
        'luggage': 2,
        'features': <String>['wifi'],
        'photo_url': 'https://cdn.example/limo.jpg',
        'vehicle_id': 'veh_1',
        'is_active': true,
      },
      <String, dynamic>{
        'name': 'Taxi Van',
        'category': 'Premium',
        'service_category': 'taxi',
        'pax': 4,
        'photo_url': 'https://cdn.example/taxi-van.jpg',
        'is_active': true,
      },
    ],
    'limousine_offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'off_1',
        'published': true,
        'enabled': true,
        'target_type': 'vehicle',
        'vehicle_id': 'veh_1',
        'service_class_id': 'executive_sedan',
        'title': <String, String>{
          'nl': 'Avondarrangement',
          'en': 'Evening',
          'fr': 'Soirée',
          'es': 'Noche',
        },
        'description': <String, String>{
          'nl': 'Zwarte sedan voor een avond.',
          'en': 'Black sedan for an evening.',
          'fr': 'Berline noire pour une soirée.',
          'es': 'Sedán negro para una noche.',
        },
        'price_presentation': 'quote_required',
        'vehicle': <String, dynamic>{
          'vehicle_id': 'veh_1',
          'service_class_id': 'executive_sedan',
          'passenger_capacity': 3,
          'luggage_capacity': 2,
          'photo_url': 'https://cdn.example/limo.jpg',
        },
      },
    ],
  };
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

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('discovery cover ignores vehicle photos and taxi hero', () {
    final card = tryParseLimousineDiscoveryCard(_nearbyCard());
    expect(card?.coverImageUrl, isEmpty);
    expect(card?.coverIsPlaceholder, isTrue);
    expect(card?.coverImageUrl.contains('taxi-cover'), isFalse);
    expect(card?.coverImageUrl.contains('limo.jpg'), isFalse);
    expect(limousineUrlLooksLikeTaxiCoverField('hero_photo_url'), isTrue);
    expect(limousineUrlLooksLikeTaxiCoverField('limousine_cover_url'), isFalse);
  });

  test('premium category alone never classifies a vehicle', () {
    expect(
      limousinePublicVehicleIsClassified(<String, dynamic>{
        'category': 'Premium',
        'name': 'Stretch',
        'is_active': true,
      }),
      isFalse,
    );
    expect(
      tryParseLimousineShowroomVehicle(<String, dynamic>{
        'category': 'Premium',
        'service_category': 'taxi',
        'name': 'Taxi Van',
        'is_active': true,
      }, index: 0),
      isNull,
    );
  });

  test('showroom keeps classified limousines and drops taxi-only vehicles', () {
    final data = buildLimousineProviderShowroomData(profile: _profile());
    expect(data.vehicles, hasLength(1));
    expect(data.vehicles.single.displayName, 'S-Class');
    expect(data.vehicles.single.serviceClassId, 'executive_sedan');
    expect(data.heroPhotoUrl, isEmpty);
    expect(data.heroPhotoUrl.contains('taxi-cover'), isFalse);
    expect(data.heroPhotoUrl.contains('limo.jpg'), isFalse);
    expect(
      data.vehicles.any((vehicle) => vehicle.displayName == 'Taxi Van'),
      isFalse,
    );
  });

  test('transaction gates stay fail-closed without dart-defines', () {
    expect(kLimousineCustomerQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerManualQuoteGateEnabled, isFalse);
    expect(kLimousineCustomerBookGateEnabled, isFalse);
    expect(limousineCustomerQuoteCtaEnabled(), isFalse);
    expect(limousineCustomerBookCtaEnabled(), isFalse);
    expect(limousineCustomerQuoteCtaEnabled(quoteGate: true), isTrue);
  });

  test('vehicle media contract keeps contain and a usable height', () {
    expect(
      limousineVehicleMediaUsesContainStrategy(
        minHeight: kLimousineVehiclePhotoMinHeight,
        photoFit: BoxFit.contain,
      ),
      isTrue,
    );
    expect(
      limousineVehicleMediaUsesContainStrategy(
        minHeight: 40,
        photoFit: BoxFit.cover,
      ),
      isFalse,
    );
    final media = File(
      'lib/limousine/limousine_vehicle_media.dart',
    ).readAsStringSync();
    expect(media.contains('BoxFit.contain'), isTrue);
    expect(media.contains('kLimousineVehiclePhotoMinHeight'), isTrue);
    final discovery = File(
      'lib/limousine/limousine_customer_discovery_page.dart',
    ).readAsStringSync();
    expect(discovery.contains('PartnerPublicProfilePage'), isFalse);
    expect(discovery.contains('PartnerProfilePage'), isFalse);
    expect(discovery.contains('height: 40'), isFalse);
    expect(discovery.contains('LimousineProviderShowroomPage'), isTrue);
    expect(discovery.contains('LimousinePublicProfilePage'), isTrue);
    final showroom = File(
      'lib/limousine/limousine_provider_showroom_page.dart',
    ).readAsStringSync();
    expect(showroom.contains('Taxi'), isFalse);
    expect(showroom.contains('Luchthaven'), isFalse);
    expect(showroom.contains('payment_methods'), isFalse);
    expect(showroom.contains('drivers'), isFalse);
    final profilePage = File(
      'lib/limousine/limousine_public_profile_page.dart',
    ).readAsStringSync();
    expect(profilePage.contains('PartnerPublicProfilePage'), isFalse);
    expect(profilePage.contains('Taxi'), isFalse);
    expect(profilePage.contains('Luchthaven'), isFalse);
    expect(profilePage.contains('payment_methods'), isFalse);
    expect(profilePage.contains('drivers'), isFalse);
  });

  test('limousine profile projection drops taxi chrome and taxi cover', () {
    final data = buildLimousinePublicProfileData(profile: _profile());
    expect(data.showroom.heroPhotoUrl, isEmpty);
    expect(data.showroom.heroPhotoUrl.contains('taxi-cover'), isFalse);
    expect(data.showroom.heroPhotoUrl.contains('limo.jpg'), isFalse);
    expect(
      data.showroom.vehicles.any(
        (vehicle) => vehicle.displayName == 'Taxi Van',
      ),
      isFalse,
    );
    expect(data.hasPublicRating, isTrue);
    expect(data.websiteUrl, 'https://maison.example');
    expect(data.serviceRegion, 'Oost-Vlaanderen');
  });

  testWidgets('discovery card has two distinct limousine CTAs', (tester) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _nearbyCard(),
        ]),
      ),
    );
    await tester.pumpWidget(
      _app(
        LimousineCustomerDiscoveryPage(
          gateway: gateway,
          customerHomeBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bekijk aanbod'), findsOneWidget);
    expect(find.text('Meer info'), findsOneWidget);
    expect(find.text('Bekijk profiel'), findsNothing);
    expect(find.text('Bekijk limousines'), findsNothing);
    expect(find.text('Vraag offerte aan'), findsNothing);
    expect(find.text('Boek nu'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(limousineDiscoveryCardKey('limo_1')),
        matching: find.byType(FilledButton),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(limousineDiscoveryCardKey('limo_1')),
        matching: find.byType(OutlinedButton),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Bekijk aanbod opens the showroom, not the taxi profile', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _nearbyCard(),
        ]),
      ),
      profileHandler: (_) async => _profile(),
    );
    await tester.pumpWidget(
      _app(
        LimousineCustomerDiscoveryPage(
          gateway: gateway,
          customerHomeBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ButtonStyleButton>(
          find.byKey(limousineDiscoveryOffersCtaKey('limo_1')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineProviderShowroomPageKey), findsOneWidget);
    expect(find.byType(LimousineProviderShowroomPage), findsOneWidget);
    expect(find.byType(LimousinePublicProfilePage), findsNothing);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
    expect(find.text('Onze limousines'), findsOneWidget);
    expect(find.text('S-Class'), findsOneWidget);
    expect(find.text('Taxi Van'), findsNothing);
    expect(find.text('Hidden Driver'), findsNothing);
    expect(find.text('Taxi'), findsNothing);
    expect(find.text('Luchthaven'), findsNothing);
    expect(find.text('Meer info'), findsOneWidget);
    expect(find.text('Vraag offerte aan'), findsNothing);
    expect(find.text('Boek nu'), findsNothing);
    expect(find.byKey(kLimousinePublicShowroomSectionKey), findsNothing);
    expect(find.text('Bekijk bedrijfsprofiel'), findsOneWidget);
  });

  testWidgets('Meer info opens the limousine profile, not the taxi page', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _nearbyCard(),
        ]),
      ),
      profileHandler: (_) async => _profile(),
    );
    await tester.pumpWidget(
      _app(
        LimousineCustomerDiscoveryPage(
          gateway: gateway,
          customerHomeBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ButtonStyleButton>(
          find.byKey(limousineDiscoveryProfileCtaKey('limo_1')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousinePublicProfilePageKey), findsOneWidget);
    expect(find.byType(LimousinePublicProfilePage), findsOneWidget);
    expect(find.byType(LimousineProviderShowroomPage), findsNothing);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
    expect(find.text('Taxi Van'), findsNothing);
    expect(find.text('Hidden Driver'), findsNothing);
    expect(find.text('Taxi'), findsNothing);
    expect(find.text('Luchthaven'), findsNothing);
    expect(find.text('visa'), findsNothing);
    expect(find.text('Chauffeured limousines'), findsWidgets);
    expect(find.textContaining('Oost-Vlaanderen'), findsOneWidget);
    expect(find.textContaining('4.8'), findsOneWidget);
    expect(find.text('Vraag offerte aan'), findsNothing);
    expect(find.text('Boek nu'), findsNothing);
    expect(find.text('Meer info'), findsNothing);
    expect(find.text('Bekijk aanbod'), findsWidgets);
  });

  testWidgets('limousine profile Bekijk aanbod opens the showroom', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousinePublicProfilePage(partnerId: 'limo_1', profile: _profile()),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ButtonStyleButton>(
          find.byKey(kLimousinePublicProfileOffersCtaKey),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(LimousineProviderShowroomPage), findsOneWidget);
    expect(find.byType(LimousinePublicProfilePage), findsNothing);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
    expect(find.text('Onze limousines'), findsOneWidget);
    expect(find.text('Vraag offerte aan'), findsNothing);
  });

  testWidgets('showroom company-profile link opens the limousine profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineProviderShowroomPage(partnerId: 'limo_1', profile: _profile()),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ButtonStyleButton>(
          find.byKey(kLimousineShowroomCompanyProfileCtaKey),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(LimousinePublicProfilePage), findsOneWidget);
    expect(find.byType(LimousineProviderShowroomPage), findsNothing);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
  });

  testWidgets('tablet discovery uses the available width', (tester) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _nearbyCard(),
        ]),
      ),
    );
    tester.view.physicalSize = kLimousineSmX400Portrait;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        LimousineCustomerDiscoveryPage(
          gateway: gateway,
          customerHomeBuilder: (_) => const SizedBox.shrink(),
        ),
        size: kLimousineSmX400Portrait,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(kLimousineDiscoveryTabletPortraitLayoutKey),
      findsOneWidget,
    );
    final card = tester.getSize(
      find.byKey(limousineDiscoveryCardKey('limo_1')),
    );
    expect(card.width, greaterThan(1000));
    expect(card.height, greaterThan(220));
  });

  testWidgets('phone discovery stays a vertical single-column card', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _nearbyCard(),
        ]),
      ),
    );
    await tester.pumpWidget(
      _app(
        LimousineCustomerDiscoveryPage(
          gateway: gateway,
          customerHomeBuilder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineDiscoveryPhoneLayoutKey), findsOneWidget);
    expect(find.text('Bekijk aanbod'), findsOneWidget);
    expect(find.text('Meer info'), findsOneWidget);
    expect(find.text('Bekijk profiel'), findsNothing);
  });

  testWidgets('showroom more info opens the vehicle detail page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        LimousineProviderShowroomPage(partnerId: 'limo_1', profile: _profile()),
      ),
    );
    await tester.pumpAndSettle();
    tester
        .widget<ButtonStyleButton>(
          find.byKey(limousineShowroomMoreInfoCtaKey('veh_1')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineVehicleDetailPageKey), findsOneWidget);
    expect(find.text('S-Class'), findsWidgets);
    expect(find.text(kLimousineDetailQuoteComingSoon.nl), findsOneWidget);
    expect(find.text('Vraag offerte aan'), findsNothing);
    expect(find.text('Boek nu'), findsNothing);
  });

  testWidgets('detail quote CTA stays local when gates are off', (
    tester,
  ) async {
    var quotes = 0;
    var books = 0;
    final data = buildLimousineProviderShowroomData(profile: _profile());
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: data.vehicles.single,
          companyName: data.companyName,
          partnerId: data.partnerId,
          quoteEnabled: false,
          manualQuoteEnabled: false,
          bookEnabled: false,
          onQuote: (_) => quotes += 1,
          onBook: (_) => books += 1,
        ),
      ),
    );
    await tester.pump();
    final quoteButton = tester.widget<ButtonStyleButton>(
      find.byKey(kLimousineDetailQuoteCtaKey),
    );
    expect(quoteButton.onPressed, isNull);
    expect(find.text(kLimousineDetailQuoteComingSoon.nl), findsOneWidget);
    expect(quotes, 0);
    expect(books, 0);
    expect(find.byKey(kLimousineDetailGateOffBannerKey), findsNothing);
  });

  testWidgets('bookable offer shows Book now and stays gated off', (
    tester,
  ) async {
    var books = 0;
    final profile = _profile();
    (profile['limousine_offers'] as List).first['price_presentation'] =
        'exact_fixed';
    (profile['limousine_offers'] as List).first['display_amount_cents'] = 45000;
    (profile['limousine_offers'] as List).first['currency'] = 'EUR';
    final data = buildLimousineProviderShowroomData(profile: profile);
    expect(
      limousineDetailCtaFor(data.vehicles.single.primaryOffer),
      LimousineShowroomCta.book,
    );
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: data.vehicles.single,
          companyName: data.companyName,
          partnerId: data.partnerId,
          bookEnabled: false,
          onBook: (_) => books += 1,
        ),
      ),
    );
    await tester.pump();
    expect(find.text(kLimousineDetailBookComingSoon.nl), findsOneWidget);
    expect(find.text('Boek nu'), findsNothing);
    final bookButton = tester.widget<ButtonStyleButton>(
      find.byKey(kLimousineDetailBookCtaKey),
    );
    expect(bookButton.onPressed, isNull);
    expect(books, 0);
  });

  testWidgets('missing photo and specs stay safe', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineProviderShowroomPage(
          partnerId: 'limo_empty',
          profile: <String, dynamic>{
            'partner_id': 'limo_empty',
            'company_name': 'Empty Coach',
            'limousine_available': true,
            'vehicles': <Map<String, dynamic>>[
              <String, dynamic>{
                'service_category': 'limousine',
                'service_class': 'executive_sedan',
                'is_active': true,
              },
            ],
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineVehiclePhotoPlaceholderKey), findsWidgets);
    expect(find.text('Empty Coach'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('general taxi partner page still renders taxi chrome', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        PartnerPublicProfilePage(
          partnerId: 'taxi_1',
          companyNameFallback: 'City Taxi',
          customerHomeBuilder: (_) => const SizedBox.shrink(),
          limousineShowroomEnabled: false,
          profileOverride: <String, dynamic>{
            'partner_id': 'taxi_1',
            'company_name': 'City Taxi',
            'profile_enabled': true,
            'services': <String>['taxi_vvb', 'airport_transfer'],
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(PartnerPublicProfilePage), findsOneWidget);
    expect(find.byKey(kLimousineProviderShowroomPageKey), findsNothing);
  });

  test('unscoped listing and distance ranking stay intact', () {
    expect(const LimousineDiscoveryQuery().isUnscoped, isTrue);
    final far = tryParseLimousineDiscoveryCard(
      _nearbyCard()
        ..['partner_id'] = 'far'
        ..['distance_km'] = 80,
    );
    final near = tryParseLimousineDiscoveryCard(_nearbyCard());
    expect(near?.distanceKm, 12.4);
    expect(far?.distanceKm, 80);
    expect(near?.publicPartnerId, isNot(far?.publicPartnerId));
  });
}
