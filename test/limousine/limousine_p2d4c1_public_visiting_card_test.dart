import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';
import 'package:fluxidi_tracking/partner_public_profile_page.dart';

const String _kPartnerId = 'limo_fluxidi';
const String _kWhiteCover = 'https://cdn.example/white-stretch.jpg';
const String _kPinkHummer = 'https://cdn.example/pink-hummer.jpg';
const String _kStretchPhoto = 'https://cdn.example/stretch-8.jpg';
const String _kLogo = 'https://cdn.example/fluxidi-logo.png';
const String _kDraftCover = 'https://cdn.example/draft-cover.jpg';

Map<String, dynamic> _vehicle({
  required String id,
  required String name,
  required String photo,
  required int pax,
  required int luggage,
  String serviceClass = 'stretch_limousine',
}) {
  return <String, dynamic>{
    'vehicle_id': id,
    'name': name,
    'service_category': 'limousine',
    'service_class_id': serviceClass,
    'is_active': true,
    'photo_url': photo,
    'primary_photo_url': photo,
    'passenger_capacity': pax,
    'luggage_capacity': luggage,
  };
}

Map<String, dynamic> _offer({
  required String id,
  required String vehicleId,
  int amountCents = 25000,
}) {
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': true,
    'target_type': 'vehicle',
    'vehicle_id': vehicleId,
    'vehicle_ids': <String>[vehicleId],
    'price_presentation': 'from_price',
    'display_amount_cents': amountCents,
    'currency': 'EUR',
    'title': <String, String>{
      'nl': 'Avondrit',
      'en': 'Evening ride',
      'fr': 'Soirée',
      'es': 'Noche',
    },
  };
}

Map<String, dynamic> _fluxidiNearby({
  Map<String, String>? workingTitle,
  Map<String, String>? publishedTitle,
  Map<String, String>? workingDescription,
  Map<String, String>? publishedDescription,
  Map<String, dynamic>? workingHero,
  Map<String, dynamic>? publishedHero,
  bool includePublishedKeys = true,
}) {
  return <String, dynamic>{
    'partner_id': _kPartnerId,
    'company_name': 'Fluxidi BV',
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'public_city': 'Gent',
    'logo_url': _kLogo,
    'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
    'public_title':
        workingTitle ??
        const <String, String>{
          'nl': 'Fluxidi',
          'en': 'Fluxidi',
          'fr': 'Fluxidi',
          'es': 'Fluxidi',
        },
    'public_description':
        workingDescription ??
        const <String, String>{
          'nl': 'Voor elke gelegenheid',
          'en': 'For every occasion',
          'fr': 'Pour chaque occasion',
          'es': 'Para cada ocasión',
        },
    'limousine_hero':
        workingHero ??
        <String, dynamic>{'photo_url': _kWhiteCover, 'alignment': 'right'},
    if (includePublishedKeys) ...<String, dynamic>{
      'published_public_title':
          publishedTitle ??
          const <String, String>{
            'nl': 'Fluxidi',
            'en': 'Fluxidi',
            'fr': 'Fluxidi',
            'es': 'Fluxidi',
          },
      'published_public_description':
          publishedDescription ??
          const <String, String>{
            'nl': 'Voor elke gelegenheid',
            'en': 'For every occasion',
            'fr': 'Pour chaque occasion',
            'es': 'Para cada ocasión',
          },
      'published_limousine_hero':
          publishedHero ??
          <String, dynamic>{'photo_url': _kWhiteCover, 'alignment': 'right'},
    },
    'limousine_vehicles': <Map<String, dynamic>>[
      _vehicle(
        id: 'veh_hummer',
        name: 'Roze Hummer',
        photo: _kPinkHummer,
        pax: 16,
        luggage: 3,
        serviceClass: 'party_stretch',
      ),
      _vehicle(
        id: 'veh_stretch',
        name: 'Witte stretch',
        photo: _kStretchPhoto,
        pax: 8,
        luggage: 2,
      ),
    ],
    'limousine_offers': <Map<String, dynamic>>[
      _offer(id: 'off_hummer', vehicleId: 'veh_hummer'),
      _offer(id: 'off_stretch', vehicleId: 'veh_stretch', amountCents: 32000),
    ],
    'limousine_price_presentation': 'from_price',
    'display_amount_cents': 25000,
    'currency': 'EUR',
    'test_preview': true,
  };
}

Map<String, dynamic> _fluxidiProfile() {
  return <String, dynamic>{
    ..._fluxidiNearby(),
    'tagline': 'Oude tagline',
    'about_short': 'Bedrijfsinformatie over Fluxidi.',
    'coverage': <String, dynamic>{'region_label': 'Oost-Vlaanderen'},
    'public_contact': <String, dynamic>{
      'website': 'https://fluxidi.example',
      'public_phone': '+32 9 000 00 00',
      'booking_email': 'book@fluxidi.example',
    },
    'vehicles': <Map<String, dynamic>>[
      _vehicle(
        id: 'veh_hummer',
        name: 'Roze Hummer',
        photo: _kPinkHummer,
        pax: 16,
        luggage: 3,
        serviceClass: 'party_stretch',
      ),
      _vehicle(
        id: 'veh_stretch',
        name: 'Witte stretch',
        photo: _kStretchPhoto,
        pax: 8,
        luggage: 2,
      ),
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

LimousineCustomerDiscoveryPage _discovery(
  MemoryLimousineDiscoveryGateway gateway,
) {
  return LimousineCustomerDiscoveryPage(
    gateway: gateway,
    customerHomeBuilder: (_) => const SizedBox.shrink(),
  );
}

MemoryLimousineDiscoveryGateway _gateway({
  Map<String, dynamic>? nearby,
  Map<String, dynamic>? profile,
}) {
  final card = nearby ?? _fluxidiNearby();
  return MemoryLimousineDiscoveryGateway(
    searchHandler: (_) async => LimousineDiscoveryPageData(
      listingMode: 'test_preview',
      cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[card]),
    ),
    profileHandler: (_) async => profile ?? _fluxidiProfile(),
  );
}

void _assertVisitingCardCopy(WidgetTester tester) {
  final card = find.byKey(limousineDiscoveryCardKey(_kPartnerId));
  expect(card, findsOneWidget);
  expect(
    find.descendant(of: card, matching: find.text('Fluxidi')),
    findsWidgets,
  );
  expect(find.text('Voor elke gelegenheid'), findsOneWidget);
  expect(find.text('Bekijk aanbod'), findsOneWidget);
  expect(find.text('Meer info'), findsOneWidget);
  expect(find.text('Roze Hummer'), findsNothing);
  expect(find.text('Witte stretch'), findsNothing);
  expect(find.text('stretch limousine'), findsNothing);
  expect(find.textContaining('16 personen'), findsNothing);
  expect(find.textContaining('8 personen'), findsNothing);
  expect(find.textContaining('3 bagage'), findsNothing);
  expect(find.textContaining('2 bagage'), findsNothing);
  expect(find.textContaining('Vanaf €250'), findsNothing);
  expect(find.textContaining('Vanaf €'), findsNothing);
  expect(find.text('Fluxidi BV'), findsNothing);
  expect(find.text('null'), findsNothing);
  final photo = tester.widget<LimousineContainPhoto>(
    find.byKey(limousineDiscoveryCardCoverKey(_kPartnerId)),
  );
  expect(photo.imageUrl, _kWhiteCover);
  expect(photo.imageUrl.contains('pink-hummer'), isFalse);
  expect(photo.alignment, Alignment.centerRight);
  expect(photo.fit, BoxFit.cover);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('fallback order is documented and never uses the first vehicle', () {
    final source = File(
      'lib/limousine/limousine_customer_discovery.dart',
    ).readAsStringSync();
    expect(source.contains('never taxi `hero_photo_url`'), isTrue);
    expect(source.contains('never the first'), isTrue);
    expect(source.contains('empty placeholder'), isTrue);
  });

  test('published public display wins over vehicles, taxi hero and drafts', () {
    final card = tryParseLimousineDiscoveryCard(
      _fluxidiNearby(
        workingTitle: const <String, String>{'nl': 'Draftnaam'},
        workingDescription: const <String, String>{'nl': 'Draft tekst'},
        workingHero: <String, dynamic>{
          'photo_url': _kDraftCover,
          'alignment': 'left',
        },
      ),
    );
    expect(card, isNotNull);
    expect(card!.publicPartnerId, _kPartnerId);
    expect(card.coverImageUrl, _kWhiteCover);
    expect(card.coverIsPlaceholder, isFalse);
    expect(card.coverAlignment, Alignment.centerRight);
    expect(card.coverSource, LimousineDiscoveryCoverSource.publishedHero);
    expect(limousineDiscoveryCardTitle(card, AppLanguage.nl), 'Fluxidi');
    expect(
      limousineDiscoveryCardDescription(card, AppLanguage.nl),
      'Voor elke gelegenheid',
    );
    expect(limousineDiscoveryCardTitle(card, AppLanguage.en), 'Fluxidi');
    expect(
      limousineDiscoveryCardDescription(card, AppLanguage.en),
      'For every occasion',
    );
    expect(card.coverImageUrl.contains('pink-hummer'), isFalse);
    expect(card.logoUrl, _kLogo);
    expect(card.vehicles, hasLength(2));
    expect(card.price.amountCents, 25000);
    expect(
      limousineDiscoveryPriceLabel(card.price, AppLanguage.nl),
      'Vanaf €250',
    );
  });

  test('explicit empty published snapshot does not leak draft copy', () {
    final card = tryParseLimousineDiscoveryCard(
      _fluxidiNearby(
        workingTitle: const <String, String>{'nl': 'Draftnaam'},
        workingDescription: const <String, String>{'nl': 'Draft tekst'},
        workingHero: <String, dynamic>{'photo_url': _kPinkHummer},
        publishedTitle: const <String, String>{},
        publishedDescription: const <String, String>{},
        publishedHero: <String, dynamic>{},
      ),
    );
    expect(card, isNotNull);
    expect(limousineDiscoveryCardTitle(card!, AppLanguage.nl), 'Fluxidi BV');
    expect(limousineDiscoveryCardDescription(card, AppLanguage.nl), isEmpty);
    expect(card.coverImageUrl, isEmpty);
    expect(card.coverIsPlaceholder, isTrue);
    expect(card.coverImageUrl.contains('pink-hummer'), isFalse);
  });

  test(
    'legacy companies without published_* still use live public display',
    () {
      final card = tryParseLimousineDiscoveryCard(
        _fluxidiNearby(includePublishedKeys: false),
      );
      expect(card?.coverImageUrl, _kWhiteCover);
      expect(limousineDiscoveryCardTitle(card!, AppLanguage.nl), 'Fluxidi');
      expect(
        limousineDiscoveryCardDescription(card, AppLanguage.nl),
        'Voor elke gelegenheid',
      );
    },
  );

  test('missing title or description never invents vehicle or price copy', () {
    final card = tryParseLimousineDiscoveryCard(
      _fluxidiNearby(
        publishedTitle: const <String, String>{},
        publishedDescription: const <String, String>{},
        workingTitle: const <String, String>{},
        workingDescription: const <String, String>{},
        includePublishedKeys: false,
      )..['company_name'] = 'Fluxidi BV',
    );
    expect(card, isNotNull);
    expect(limousineDiscoveryCardTitle(card!, AppLanguage.nl), 'Fluxidi BV');
    expect(limousineDiscoveryCardDescription(card, AppLanguage.nl), isEmpty);
    expect(
      limousineDiscoveryCardTitle(card, AppLanguage.nl).contains('16'),
      isFalse,
    );
    expect(
      limousineDiscoveryCardDescription(card, AppLanguage.nl),
      isNot('null'),
    );
  });

  test('draft save keeps published visiting-card fields unchanged', () {
    const liveTitle = <String, String>{'nl': 'Nieuw'};
    const liveDescription = <String, String>{'nl': 'Nieuwe tekst'};
    const publishedTitle = <String, String>{'nl': 'Fluxidi'};
    const publishedDescription = <String, String>{
      'nl': 'Voor elke gelegenheid',
    };
    final liveHero = <String, dynamic>{
      'photo_url': _kDraftCover,
      'alignment': 'left',
    };
    final publishedHero = <String, dynamic>{
      'photo_url': _kWhiteCover,
      'alignment': 'right',
    };
    final draft = limousinePublicDisplayPayload(
      publish: false,
      title: liveTitle,
      description: liveDescription,
      hero: liveHero,
      publishedTitle: publishedTitle,
      publishedDescription: publishedDescription,
      publishedHero: publishedHero,
    );
    expect(draft['public_title'], liveTitle);
    expect(draft['published_public_title'], publishedTitle);
    expect(draft['public_description'], liveDescription);
    expect(draft['published_public_description'], publishedDescription);
    expect(draft['limousine_hero'], liveHero);
    expect(draft['published_limousine_hero'], publishedHero);

    final published = limousinePublicDisplayPayload(
      publish: true,
      title: liveTitle,
      description: liveDescription,
      hero: liveHero,
      publishedTitle: publishedTitle,
      publishedDescription: publishedDescription,
      publishedHero: publishedHero,
    );
    expect(published['published_public_title'], liveTitle);
    expect(published['published_public_description'], liveDescription);
    expect(published['published_limousine_hero'], liveHero);
  });

  test('reload keeps the published cover, not a vehicle photo', () {
    final raw = _fluxidiNearby();
    final first = tryParseLimousineDiscoveryCard(raw)!;
    final second = tryParseLimousineDiscoveryCard(
      Map<String, dynamic>.from(raw),
    )!;
    expect(first.coverImageUrl, _kWhiteCover);
    expect(second.coverImageUrl, first.coverImageUrl);
    expect(second.coverAlignment, first.coverAlignment);
    expect(limousineDiscoveryCardTitle(second, AppLanguage.nl), 'Fluxidi');
    expect(second.coverImageUrl.contains('pink-hummer'), isFalse);
  });

  testWidgets('Limousines in uw buurt shows the published visiting card only', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_discovery(_gateway())));
    await tester.pumpAndSettle();
    _assertVisitingCardCopy(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('English app language uses the published translation', (
    tester,
  ) async {
    appLanguageNotifier.value = AppLanguage.en;
    await tester.pumpWidget(_app(_discovery(_gateway())));
    await tester.pumpAndSettle();
    expect(find.text('For every occasion'), findsOneWidget);
    expect(find.text('Voor elke gelegenheid'), findsNothing);
    expect(find.text('More info'), findsOneWidget);
    expect(find.text('View offers'), findsOneWidget);
    expect(find.textContaining('16 passengers'), findsNothing);
    expect(find.textContaining('From €250'), findsNothing);
  });

  testWidgets('Bekijk aanbod opens this company showroom with vehicle data', (
    tester,
  ) async {
    appLanguageNotifier.value = AppLanguage.nl;
    await tester.pumpWidget(_app(_discovery(_gateway())));
    await tester.pumpAndSettle();
    tester
        .widget<ButtonStyleButton>(
          find.byKey(limousineDiscoveryOffersCtaKey(_kPartnerId)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineProviderShowroomPageKey), findsOneWidget);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
    expect(find.text('Roze Hummer'), findsOneWidget);
    expect(find.text('Witte stretch'), findsOneWidget);
    expect(find.textContaining('16 personen'), findsOneWidget);
    expect(find.textContaining('8 personen'), findsOneWidget);
    expect(find.textContaining('3 bagage'), findsOneWidget);
    expect(find.textContaining('2 bagage'), findsOneWidget);
    expect(find.textContaining('Vanaf €250'), findsOneWidget);
    tester
        .widget<ButtonStyleButton>(
          find.byKey(limousineShowroomMoreInfoCtaKey('veh_hummer')),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineVehicleDetailPageKey), findsOneWidget);
    expect(find.text('Roze Hummer'), findsWidgets);
    expect(find.textContaining('16'), findsWidgets);
    expect(find.text('Vanafprijs'), findsOneWidget);
    expect(find.textContaining('€250'), findsWidgets);
  });

  testWidgets('Meer info opens the public limousine profile for this partner', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_discovery(_gateway())));
    await tester.pumpAndSettle();
    tester
        .widget<ButtonStyleButton>(
          find.byKey(limousineDiscoveryProfileCtaKey(_kPartnerId)),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousinePublicProfilePageKey), findsOneWidget);
    expect(find.byType(PartnerPublicProfilePage), findsNothing);
    expect(find.text('Voor elke gelegenheid'), findsWidgets);
    expect(find.textContaining('Oost-Vlaanderen'), findsOneWidget);
    expect(find.textContaining('https://fluxidi.example'), findsOneWidget);
    expect(find.text('Bekijk aanbod'), findsWidgets);
    tester
        .widget<ButtonStyleButton>(
          find.byKey(kLimousinePublicProfileOffersCtaKey),
        )
        .onPressed!();
    await tester.pumpAndSettle();
    expect(find.byKey(kLimousineProviderShowroomPageKey), findsOneWidget);
    expect(find.text('Roze Hummer'), findsOneWidget);
  });

  testWidgets(
    'concept edits stay off the live card until publish, then survive reload',
    (tester) async {
      var published = false;
      final gateway = MemoryLimousineDiscoveryGateway(
        searchHandler: (_) async {
          final raw = published
              ? _fluxidiNearby(
                  workingTitle: const <String, String>{'nl': 'Fluxidi Live'},
                  publishedTitle: const <String, String>{'nl': 'Fluxidi Live'},
                  workingDescription: const <String, String>{
                    'nl': 'Nieuwe beschrijving',
                  },
                  publishedDescription: const <String, String>{
                    'nl': 'Nieuwe beschrijving',
                  },
                  workingHero: <String, dynamic>{
                    'photo_url': 'https://cdn.example/new-white.jpg',
                    'alignment': 'top',
                  },
                  publishedHero: <String, dynamic>{
                    'photo_url': 'https://cdn.example/new-white.jpg',
                    'alignment': 'top',
                  },
                )
              : _fluxidiNearby(
                  workingTitle: const <String, String>{'nl': 'Draftnaam'},
                  workingDescription: const <String, String>{
                    'nl': 'Draft tekst',
                  },
                  workingHero: <String, dynamic>{
                    'photo_url': _kPinkHummer,
                    'alignment': 'left',
                  },
                );
          return LimousineDiscoveryPageData(
            listingMode: 'test_preview',
            cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[raw]),
          );
        },
      );
      final controller = LimousineDiscoveryController(gateway: gateway);
      await tester.pumpWidget(
        _app(
          LimousineCustomerDiscoveryPage(
            gateway: gateway,
            controller: controller,
            customerHomeBuilder: (_) => const SizedBox.shrink(),
            autoLoadRecommended: false,
          ),
        ),
      );
      await controller.search(const LimousineDiscoveryQuery());
      await tester.pumpAndSettle();
      expect(find.text('Fluxidi'), findsWidgets);
      expect(find.text('Draftnaam'), findsNothing);
      expect(find.text('Voor elke gelegenheid'), findsOneWidget);
      expect(find.text('Draft tekst'), findsNothing);
      expect(
        tester
            .widget<LimousineContainPhoto>(
              find.byKey(limousineDiscoveryCardCoverKey(_kPartnerId)),
            )
            .imageUrl,
        _kWhiteCover,
      );

      published = true;
      await controller.search(const LimousineDiscoveryQuery());
      await tester.pumpAndSettle();
      expect(find.text('Fluxidi Live'), findsWidgets);
      expect(find.text('Nieuwe beschrijving'), findsOneWidget);
      expect(find.text('Voor elke gelegenheid'), findsNothing);
      expect(
        tester
            .widget<LimousineContainPhoto>(
              find.byKey(limousineDiscoveryCardCoverKey(_kPartnerId)),
            )
            .imageUrl,
        'https://cdn.example/new-white.jpg',
      );

      await controller.search(const LimousineDiscoveryQuery());
      await tester.pumpAndSettle();
      expect(find.text('Fluxidi Live'), findsWidgets);
      expect(find.text('Nieuwe beschrijving'), findsOneWidget);
      expect(
        tester
            .widget<LimousineContainPhoto>(
              find.byKey(limousineDiscoveryCardCoverKey(_kPartnerId)),
            )
            .imageUrl
            .contains('pink-hummer'),
        isFalse,
      );
    },
  );

  testWidgets('phone and tablet visiting cards do not overflow', (
    tester,
  ) async {
    for (final size in <Size>[
      kLimousinePhonePortrait,
      kLimousineSmX400Portrait,
    ]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(_app(_discovery(_gateway()), size: size));
      await tester.pumpAndSettle();
      final cardSize = tester.getSize(
        find.byKey(limousineDiscoveryCardKey(_kPartnerId)),
      );
      expect(cardSize.width, lessThanOrEqualTo(size.width + 1));
      expect(find.text('Bekijk aanbod'), findsOneWidget);
      expect(find.text('Meer info'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  test(
    'public profile and showroom keep published copy and vehicle prices',
    () {
      final profile = buildLimousinePublicProfileData(
        profile: _fluxidiProfile(),
        partnerIdFallback: _kPartnerId,
        language: AppLanguage.nl,
      );
      expect(profile.showroom.partnerId, _kPartnerId);
      expect(profile.showroom.companyName, 'Fluxidi');
      expect(profile.showroom.tagline, 'Voor elke gelegenheid');
      expect(profile.serviceRegion, 'Oost-Vlaanderen');
      expect(profile.hasPublicContact, isTrue);
      expect(profile.showroom.vehicles, hasLength(2));
      expect(profile.showroom.vehicles.first.name, 'Roze Hummer');
      expect(profile.showroom.vehicles.first.passengerCapacity, 16);
      expect(profile.showroom.vehicles.first.luggageCapacity, 3);
      expect(profile.showroom.vehicles.last.passengerCapacity, 8);
      expect(
        limousineShowroomVehiclePriceLabel(
          profile.showroom.vehicles.first,
          AppLanguage.nl,
        ),
        contains('€250'),
      );
    },
  );
}
