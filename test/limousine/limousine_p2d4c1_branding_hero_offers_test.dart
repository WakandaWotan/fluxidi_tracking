import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_brand_logo.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_offer_binding.dart';
import 'package:fluxidi_tracking/limousine/limousine_offers.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';

Map<String, dynamic> _vehicle({
  required String id,
  required String name,
  required String photo,
  String serviceClass = 'party_stretch',
}) {
  return <String, dynamic>{
    'vehicle_id': id,
    'name': name,
    'service_category': 'limousine',
    'service_class': serviceClass,
    'pax': 8,
    'luggage': 4,
    'photo_url': photo,
    'primary_photo_url': photo,
    'is_active': true,
  };
}

Map<String, dynamic> _offer({
  required String id,
  required String presentation,
  List<String> vehicleIds = const <String>[],
  bool appliesToAll = false,
  bool featured = false,
  int? amount,
  Map<String, dynamic>? hourly,
  String title = 'Aanbod',
}) {
  return <String, dynamic>{
    'offer_id': id,
    'enabled': true,
    'published': true,
    'target_type': appliesToAll
        ? LimousineOfferTarget.serviceClass
        : LimousineOfferTarget.vehicle,
    'service_class_id': 'party_stretch',
    'vehicle_id': vehicleIds.isEmpty ? '' : vehicleIds.first,
    'vehicle_ids': vehicleIds,
    'applies_to_all_selected_vehicles': appliesToAll,
    'featured': featured,
    'sort_order': 0,
    'price_presentation': presentation,
    'display_amount_cents': amount,
    'currency': 'EUR',
    'title': <String, String>{
      'nl': title,
      'en': title,
      'fr': title,
      'es': title,
    },
    'description': <String, String>{
      'nl': 'Beschrijving $title',
      'en': 'Description $title',
      'fr': 'Description $title',
      'es': 'Descripción $title',
    },
    if (hourly != null) 'hourly': hourly,
  };
}

Map<String, dynamic> _profile({
  String? hero,
  List<Map<String, dynamic>>? vehicles,
  List<Map<String, dynamic>>? offers,
}) {
  return <String, dynamic>{
    'partner_id': 'limo_1',
    'company_name': 'Maison Noire',
    'logo_url': 'https://cdn.example/logo.png',
    'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
    'limousine_available': true,
    if (hero != null) 'limousine_hero_url': hero,
    'vehicles': vehicles ??
        <Map<String, dynamic>>[
          _vehicle(
            id: 'vh_party',
            name: 'Party Limo',
            photo: 'https://cdn.example/party.jpg',
          ),
          _vehicle(
            id: 'vh_hummer',
            name: 'Hummer white',
            photo: 'https://cdn.example/hummer.jpg',
            serviceClass: 'suv_stretch',
          ),
        ],
    'limousine_offers': offers ??
        <Map<String, dynamic>>[
          _offer(
            id: 'off_party',
            presentation: LimousinePricePresentation.fromPrice,
            vehicleIds: const <String>['vh_party'],
            amount: 25000,
            title: 'Party vanaf',
          ),
          _offer(
            id: 'off_hummer',
            presentation: LimousinePricePresentation.exactFixed,
            vehicleIds: const <String>['vh_hummer'],
            amount: 65000,
            title: 'Hummer avondrit',
          ),
        ],
  };
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: Size(800, 1280)),
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

  test('1-4 explicit limousine hero persists and ignores fleet/taxi cover', () {
    const explicit = 'https://cdn.example/limousine-hero.jpg';
    final first = resolveLimousineHero(
      source: <String, dynamic>{
        'limousine_hero_url': explicit,
        'limousine_hero_source': 'upload',
        'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
      },
      fallbackVehiclePhotoUrls: const <String>[
        'https://cdn.example/party.jpg',
        'https://cdn.example/hummer.jpg',
      ],
    );
    expect(first.photoUrl, explicit);
    expect(first.explicit, isTrue);
    final reordered = resolveLimousineHero(
      source: <String, dynamic>{'limousine_hero_url': explicit},
      fallbackVehiclePhotoUrls: const <String>[
        'https://cdn.example/hummer.jpg',
        'https://cdn.example/party.jpg',
      ],
    );
    expect(reordered.photoUrl, explicit);
    final fallback = resolveLimousineHero(
      source: <String, dynamic>{
        'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
      },
      fallbackVehiclePhotoUrls: const <String>['https://cdn.example/party.jpg'],
    );
    expect(fallback.photoUrl, 'https://cdn.example/party.jpg');
    expect(fallback.explicit, isFalse);
    expect(fallback.photoUrl.contains('taxi-cover'), isFalse);
    final empty = resolveLimousineHero(
      source: <String, dynamic>{
        'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
      },
    );
    expect(empty.photoUrl, isEmpty);
    final showroom = buildLimousineProviderShowroomData(
      profile: _profile(hero: explicit),
    );
    expect(showroom.heroPhotoUrl, explicit);
    expect(showroom.heroIsExplicit, isTrue);
    expect(showroom.heroPhotoUrl.contains('taxi-cover'), isFalse);
    expect(
      buildLimousineProviderShowroomData(profile: _profile()).heroPhotoUrl,
      'https://cdn.example/party.jpg',
    );
  });

  test('discovery keeps vehicle primary photo, not company hero', () {
    final card = tryParseLimousineDiscoveryCard(<String, dynamic>{
      'partner_id': 'limo_1',
      'company_name': 'Maison Noire',
      'is_active': true,
      'profile_enabled': true,
      'limousine_available': true,
      'limousine_service_enabled': true,
      'logo_url': 'https://cdn.example/logo.png',
      'limousine_hero_url': 'https://cdn.example/limousine-hero.jpg',
      'hero_photo_url': 'https://cdn.example/taxi-cover.jpg',
      'limousine_vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'service_category': 'limousine',
          'service_class_id': 'party_stretch',
          'photo_url': 'https://cdn.example/party.jpg',
        },
      ],
      'limousine_offers': <Map<String, dynamic>>[
        _offer(
          id: 'off_party',
          presentation: LimousinePricePresentation.fromPrice,
          vehicleIds: const <String>['vh_party'],
          amount: 25000,
        ),
      ],
    });
    expect(card?.coverImageUrl, 'https://cdn.example/party.jpg');
    expect(card?.logoUrl, 'https://cdn.example/logo.png');
    expect(card?.price.kind, LimousineDiscoveryPriceKind.fromPrice);
    expect(card?.price.amountCents, 25000);
  });

  testWidgets('5-6 logo plaque is visible and keeps contain aspect ratio', (
    tester,
  ) async {
    final profile = _profile(hero: 'https://cdn.example/limousine-hero.jpg');
    await tester.pumpWidget(
      _app(LimousineProviderShowroomPage(partnerId: 'limo_1', profile: profile)),
    );
    await tester.pump();
    expect(find.byKey(kLimousineBrandLogoPlaqueKey), findsWidgets);
    expect(
      find.byKey(kLimousineBrandLogoImageKey).evaluate().isNotEmpty ||
          find.byKey(kLimousineBrandLogoInitialsKey).evaluate().isNotEmpty,
      isTrue,
    );
    if (find.byKey(kLimousineBrandLogoImageKey).evaluate().isNotEmpty) {
      expect(
        tester.widget<Image>(find.byKey(kLimousineBrandLogoImageKey).first).fit,
        BoxFit.contain,
      );
    }
    await tester.pumpWidget(
      _app(LimousinePublicProfilePage(partnerId: 'limo_1', profile: profile)),
    );
    await tester.pump();
    expect(find.byKey(kLimousineBrandLogoPlaqueKey), findsWidgets);
    final data = buildLimousineProviderShowroomData(profile: profile);
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: data.vehicles.first,
          companyName: 'Maison Noire',
          partnerId: 'limo_1',
          logoUrl: data.logoUrl,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineBrandLogoPlaqueKey), findsWidgets);
    final logo = File('lib/limousine/limousine_brand_logo.dart').readAsStringSync();
    expect(logo.contains('BoxFit.contain'), isTrue);
    expect(logo.contains('BoxFit.fill'), isFalse);
  });

  test('7-12 Party and Hummer keep distinct bindings, shared and all-selected work', () {
    final data = buildLimousineProviderShowroomData(profile: _profile());
    final party = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_party');
    final hummer = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_hummer');
    expect(party.offers.single.offerId, 'off_party');
    expect(hummer.offers.single.offerId, 'off_hummer');
    expect(party.offers.any((o) => o.offerId == 'off_hummer'), isFalse);
    expect(hummer.offers.any((o) => o.offerId == 'off_party'), isFalse);
    expect(
      limousineFormatPublishedOfferPrice(party.offers.single, AppLanguage.nl),
      contains('Vanaf'),
    );
    expect(
      limousineFormatPublishedOfferPrice(hummer.offers.single, AppLanguage.nl),
      isNot(contains('Vanaf')),
    );

    final shared = buildLimousineProviderShowroomData(
      profile: _profile(
        offers: <Map<String, dynamic>>[
          _offer(
            id: 'off_both',
            presentation: LimousinePricePresentation.quoteRequired,
            vehicleIds: const <String>['vh_party', 'vh_hummer'],
            title: 'Beide',
          ),
        ],
      ),
    );
    expect(shared.vehicles.every((v) => v.offers.single.offerId == 'off_both'), isTrue);

    final allSelected = buildLimousineProviderShowroomData(
      profile: _profile(
        offers: <Map<String, dynamic>>[
          _offer(
            id: 'off_all',
            presentation: LimousinePricePresentation.quoteRequired,
            appliesToAll: true,
            title: 'Alle',
          ),
        ],
      ),
    );
    expect(
      allSelected.vehicles.every((v) => v.offers.single.offerId == 'off_all'),
      isTrue,
    );
  });

  test('13 legacy unbound offers stay compatible as all selected', () {
    final legacy = <String, dynamic>{
      'offer_id': 'off_legacy',
      'enabled': true,
      'published': true,
      'target_type': LimousineOfferTarget.serviceClass,
      'service_class_id': 'party_stretch',
      'price_presentation': LimousinePricePresentation.quoteRequired,
      'currency': 'EUR',
      'title': <String, String>{'nl': 'Legacy', 'en': 'Legacy', 'fr': '', 'es': ''},
    };
    final scope = limousineOfferScopeOf(legacy);
    expect(scope.legacyUnbound, isTrue);
    expect(scope.appliesToAllSelected, isTrue);
    final data = buildLimousineProviderShowroomData(
      profile: _profile(offers: <Map<String, dynamic>>[legacy]),
    );
    expect(data.vehicles.every((v) => v.offers.single.offerId == 'off_legacy'), isTrue);
    final saved = limousineWriteOfferScope(
      legacy,
      appliesToAllSelected: true,
      vehicleIds: const <String>[],
    );
    expect(saved['applies_to_all_selected_vehicles'], isTrue);
    expect(limousineOfferScopeOf(saved).legacyUnbound, isFalse);
  });

  test('14-16 detail models stay correctly labelled', () {
    final hourly = _offer(
      id: 'off_hour',
      presentation: LimousinePricePresentation.fromPrice,
      vehicleIds: const <String>['vh_party'],
      amount: 12500,
      hourly: <String, dynamic>{
        'enabled': true,
        'first_hour_cents': 12500,
        'minimum_duration_minutes': 180,
      },
      title: 'Uurhuur',
    );
    final package = _offer(
      id: 'off_pkg',
      presentation: LimousinePricePresentation.exactFixed,
      vehicleIds: const <String>['vh_party'],
      amount: 65000,
      hourly: <String, dynamic>{
        'enabled': true,
        'package_amount_cents': 65000,
        'package_duration_minutes': 240,
      },
      title: 'Trouwarrangement',
    );
    final fixed = _offer(
      id: 'off_fixed',
      presentation: LimousinePricePresentation.exactFixed,
      vehicleIds: const <String>['vh_party'],
      amount: 30000,
      title: 'Avondrit van 3 uur',
    );
    final from = _offer(
      id: 'off_from',
      presentation: LimousinePricePresentation.fromPrice,
      vehicleIds: const <String>['vh_party'],
      amount: 25000,
      title: 'Standaard',
    );
    expect(limousineOfferDisplayKindOf(from), LimousineOfferDisplayKind.fromPrice);
    expect(limousineOfferDisplayKindOf(fixed), LimousineOfferDisplayKind.fixed);
    expect(limousineOfferDisplayKindOf(hourly), LimousineOfferDisplayKind.hourly);
    expect(limousineOfferDisplayKindOf(package), LimousineOfferDisplayKind.package);
    final data = buildLimousineProviderShowroomData(
      profile: _profile(offers: <Map<String, dynamic>>[from, fixed, hourly, package]),
    );
    final party = data.vehicles.firstWhere((v) => v.vehicleId == 'vh_party');
    expect(party.offers, hasLength(4));
    expect(
      limousineFormatPublishedOfferPrice(party.offers.firstWhere((o) => o.offerId == 'off_from'), AppLanguage.nl),
      contains('Vanaf'),
    );
    expect(
      limousineFormatPublishedOfferPrice(party.offers.firstWhere((o) => o.offerId == 'off_fixed'), AppLanguage.nl),
      isNot(contains('Vanaf')),
    );
    expect(
      limousineFormatPublishedOfferPrice(party.offers.firstWhere((o) => o.offerId == 'off_pkg'), AppLanguage.nl),
      allOf(contains('Trouwarrangement'), isNot(contains('Vanaf'))),
    );
    expect(
      limousineFormatPublishedOfferPrice(party.offers.firstWhere((o) => o.offerId == 'off_hour'), AppLanguage.nl),
      contains('per uur'),
    );
  });

  test('17-18 discovery summary and unpublished vehicle do not leak', () {
    final summary = limousineDiscoveryPriceFromOffers(<Map<String, dynamic>>[
      _offer(
        id: 'off_from',
        presentation: LimousinePricePresentation.fromPrice,
        vehicleIds: const <String>['vh_party'],
        amount: 25000,
      ),
      _offer(
        id: 'off_fixed',
        presentation: LimousinePricePresentation.exactFixed,
        vehicleIds: const <String>['vh_hummer'],
        amount: 9000,
      ),
    ]);
    expect(summary.kind, LimousineDiscoveryPriceKind.fromPrice);
    expect(summary.amountCents, 25000);
    final data = buildLimousineProviderShowroomData(
      profile: _profile(
        vehicles: <Map<String, dynamic>>[
          _vehicle(
            id: 'vh_party',
            name: 'Party Limo',
            photo: 'https://cdn.example/party.jpg',
          ),
        ],
        offers: <Map<String, dynamic>>[
          _offer(
            id: 'off_hummer',
            presentation: LimousinePricePresentation.exactFixed,
            vehicleIds: const <String>['vh_hummer'],
            amount: 65000,
            title: 'Hummer only',
          ),
        ],
      ),
    );
    expect(data.vehicles.single.offers, isEmpty);
    expect(
      limousineShowroomVehiclePriceLabel(data.vehicles.single, AppLanguage.nl),
      'Prijs op aanvraag',
    );
  });

  testWidgets('19 gates off create no request or booking', (tester) async {
    var quotes = 0;
    var books = 0;
    final data = buildLimousineProviderShowroomData(profile: _profile());
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: data.vehicles.first,
          companyName: 'Maison Noire',
          partnerId: 'limo_1',
          logoUrl: data.logoUrl,
          onQuote: (_) => quotes++,
          onBook: (_) => books++,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousineDetailPricesSectionKey), findsOneWidget);
    expect(find.text('Prijzen en arrangementen'), findsOneWidget);
    await tester.ensureVisible(find.byKey(kLimousineDetailQuoteCtaKey));
    await tester.tap(find.byKey(kLimousineDetailQuoteCtaKey));
    await tester.pump();
    expect(quotes, 0);
    expect(books, 0);
    expect(find.byKey(kLimousineDetailGateOffBannerKey), findsOneWidget);
  });

  test('20 save/reopen keeps hero, vehicles and offer bindings', () {
    final section = <String, dynamic>{
      'selected_vehicle_ids': <String>['vh_party', 'vh_hummer'],
      'limousine_hero': <String, dynamic>{
        'photo_url': 'https://cdn.example/limousine-hero.jpg',
        'source_kind': 'upload',
        'alignment': 'top',
        'source_revision': 4,
      },
      'offers': <Map<String, dynamic>>[
        limousineWriteOfferScope(
          _offer(
            id: 'off_party',
            presentation: LimousinePricePresentation.fromPrice,
            vehicleIds: const <String>['vh_party'],
            amount: 25000,
          ),
          appliesToAllSelected: false,
          vehicleIds: const <String>['vh_party'],
          featured: true,
          sortOrder: 2,
        ),
      ],
    };
    final hero = limousineHeroFromSection(section);
    expect(hero.photoUrl, 'https://cdn.example/limousine-hero.jpg');
    expect(hero.alignment, 'top');
    expect(hero.sourceRevision, 4);
    expect(hero.explicit, isTrue);
    final again = limousineHeroFromSection(<String, dynamic>{
      'limousine_hero': hero.toSectionJson(),
    });
    expect(again.photoUrl, hero.photoUrl);
    expect(again.alignment, hero.alignment);
    final scope = limousineOfferScopeOf(
      (section['offers'] as List).first as Map<String, dynamic>,
    );
    expect(scope.vehicleIds, <String>['vh_party']);
    expect(scope.featured, isTrue);
    expect(scope.sortOrder, 2);
    expect(scope.appliesToAllSelected, isFalse);
  });

  test('vehicle media stay contain while explicit hero may cover', () {
    expect(
      limousineVehicleMediaUsesContainStrategy(
        minHeight: kLimousineVehiclePhotoMinHeight,
        photoFit: BoxFit.contain,
      ),
      isTrue,
    );
    expect(limousineCompanyInitials('Maison Noire'), 'MN');
    expect(limousineCompanyInitials(''), 'L');
  });
}
