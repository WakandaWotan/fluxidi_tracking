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
import 'package:fluxidi_tracking/limousine/limousine_hero_contract.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_profile_identity.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_media.dart';
import 'package:fluxidi_tracking/nearby/public_partner_market.dart';

const String _kPartnerId = 'limo_fluxidi';
const String _kCover =
    'https://cdn.example/public-media/t1/c1/limousine/profile-cover.jpg';
const String _kDraftCover =
    'https://cdn.example/public-media/t1/c1/limousine/draft-cover.jpg';
const String _kTaxiHero =
    'https://cdn.example/public-media/t1/c1/company/hero.jpg';
const String _kCompanyLogo =
    'https://cdn.example/public-media/t1/c1/company/logo.png';
const String _kLimoLogo =
    'https://cdn.example/public-media/t1/c1/limousine/profile-logo.png';
const String _kTaxiLogoLater =
    'https://cdn.example/public-media/t1/c1/company/logo.png?v=2';

Map<String, dynamic> _cover(String url, {String alignment = 'center'}) {
  return <String, dynamic>{
    'photo_url': url,
    'alignment': alignment,
    'source_kind': 'upload',
    'source_revision': 1,
  };
}

Map<String, dynamic> _logo(String url) {
  return <String, dynamic>{
    'photo_url': url,
    'explicit_override': url.startsWith('https://'),
    'source_revision': 1,
  };
}

Map<String, dynamic> _concept({
  bool publish = false,
  Map<String, dynamic>? publishedHero,
  Map<String, dynamic>? publishedLogo,
}) {
  return limousinePublicDisplayPayload(
    publish: publish,
    title: const <String, String>{'nl': 'Fluxidi'},
    description: const <String, String>{'nl': 'Voor elke gelegenheid'},
    hero: _cover(_kCover, alignment: 'right'),
    publishedTitle: const <String, String>{'nl': 'Oud'},
    publishedDescription: const <String, String>{'nl': 'Oude tekst'},
    publishedHero: publishedHero ?? _cover(_kDraftCover),
    logo: _logo(_kLimoLogo),
    publishedLogo: publishedLogo ?? const <String, dynamic>{},
    taxiHeroUrls: <String>[_kTaxiHero],
  );
}

Map<String, dynamic> _nearby({
  Map<String, dynamic>? extra,
  bool includePublished = true,
  String? coverUrl,
  String? logoOverride,
}) {
  return <String, dynamic>{
    'partner_id': _kPartnerId,
    'company_name': 'Fluxidi BV',
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'logo_url': _kCompanyLogo,
    'hero_photo_url': _kTaxiHero,
    'public_title': const <String, String>{'nl': 'Draftnaam'},
    'public_description': const <String, String>{'nl': 'Draft tekst'},
    'limousine_hero': _cover(_kDraftCover),
    if (includePublished) ...<String, dynamic>{
      'published_public_title': const <String, String>{'nl': 'Fluxidi'},
      'published_public_description': const <String, String>{
        'nl': 'Voor elke gelegenheid',
      },
      'published_limousine_profile_cover': _cover(
        coverUrl ?? _kCover,
        alignment: 'right',
      ),
      'published_limousine_hero': _cover(coverUrl ?? _kCover, alignment: 'right'),
      if (logoOverride != null)
        'published_limousine_profile_logo': _logo(logoOverride),
    },
    'limousine_vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'veh_1',
        'service_category': 'limousine',
        'service_class_id': 'stretch_limousine',
        'is_active': true,
        'photo_url': 'https://cdn.example/stretch.jpg',
        'passenger_capacity': 16,
      },
    ],
    'limousine_offers': <Map<String, dynamic>>[
      <String, dynamic>{
        'offer_id': 'off_1',
        'enabled': true,
        'published': true,
        'price_presentation': 'from_price',
        'display_amount_cents': 25000,
        'currency': 'EUR',
      },
    ],
    'limousine_price_presentation': 'from_price',
    'display_amount_cents': 25000,
    'currency': 'EUR',
    ...?extra,
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

  test('1 concept keeps title, description and hero in the working copy', () {
    final draft = _concept();
    expect(draft['public_title'], const <String, String>{'nl': 'Fluxidi'});
    expect(draft['public_description'], const <String, String>{
      'nl': 'Voor elke gelegenheid',
    });
    expect((draft[kLimousineProfileCoverKey] as Map)['photo_url'], _kCover);
    expect(
      (draft['published_public_title'] as Map)['nl'],
      isNot('Fluxidi'),
    );
  });

  test('2 publish snapshots title, description, hero, focus and logo atomically', () {
    final published = _concept(publish: true);
    final card = published[kLimousinePublishedVisitingCardKey] as Map;
    expect(card['public_title'], const <String, String>{'nl': 'Fluxidi'});
    expect(card['public_description'], const <String, String>{
      'nl': 'Voor elke gelegenheid',
    });
    expect((card['cover'] as Map)['photo_url'], _kCover);
    expect((card['cover'] as Map)['alignment'], 'right');
    expect((card['logo'] as Map)['photo_url'], _kLimoLogo);
    expect(published['published_public_title'], card['public_title']);
    expect(published[kLimousinePublishedProfileCoverKey], card['cover']);
    expect(published[kLimousinePublishedProfileLogoKey], card['logo']);
  });

  test('3 discovery card shows the published limousine hero only', () {
    final card = tryParseLimousineDiscoveryCard(_nearby())!;
    expect(card.coverImageUrl, _kCover);
    expect(card.coverAlignment, Alignment.centerRight);
    expect(card.coverSource, LimousineDiscoveryCoverSource.publishedHero);
    expect(card.coverImageUrl.contains('company/hero'), isFalse);
  });

  test('4 discovery card shows Fluxidi from the published title', () {
    final card = tryParseLimousineDiscoveryCard(_nearby())!;
    expect(limousineDiscoveryCardTitle(card, AppLanguage.nl), 'Fluxidi');
    expect(card.companyName, 'Fluxidi BV');
  });

  test('5 description sits directly under Fluxidi', () {
    final card = tryParseLimousineDiscoveryCard(_nearby())!;
    expect(
      limousineDiscoveryCardDescription(card, AppLanguage.nl),
      'Voor elke gelegenheid',
    );
  });

  test('6 own limousine logo wins on the discovery card', () {
    final card = tryParseLimousineDiscoveryCard(
      _nearby(logoOverride: _kLimoLogo),
    )!;
    expect(card.logoUrl, _kLimoLogo);
    expect(card.logoUrl, isNot(_kCompanyLogo));
  });

  test('7 own limousine logo wins on the partner profile', () {
    final showroom = buildLimousineProviderShowroomData(
      profile: _nearby(logoOverride: _kLimoLogo),
      language: AppLanguage.nl,
    );
    expect(showroom.logoUrl, _kLimoLogo);
    expect(showroom.heroPhotoUrl, _kCover);
    expect(showroom.companyName, 'Fluxidi');
    expect(showroom.tagline, 'Voor elke gelegenheid');
  });

  test('8 without override only the general company logo is shown', () {
    final card = tryParseLimousineDiscoveryCard(_nearby())!;
    expect(card.logoUrl, _kCompanyLogo);
    expect(limousineDiscoveryPublishedLogoOverride(_nearby()), isEmpty);
  });

  test('9 logo fallback never copies or mutates override fields', () {
    final draft = limousinePublicDisplayPayload(
      publish: false,
      title: const <String, String>{'nl': 'Fluxidi'},
      description: const <String, String>{'nl': 'Voor elke gelegenheid'},
      hero: _cover(_kCover),
      publishedTitle: const <String, String>{'nl': 'Fluxidi'},
      publishedDescription: const <String, String>{
        'nl': 'Voor elke gelegenheid',
      },
      publishedHero: _cover(_kCover),
      logo: const <String, dynamic>{},
      publishedLogo: const <String, dynamic>{},
    );
    expect((draft[kLimousineProfileLogoKey] as Map)['photo_url'], isEmpty);
    expect(
      (draft[kLimousinePublishedProfileLogoKey] as Map)['photo_url'],
      isEmpty,
    );
    expect(
      limousineLogoFallbackMutatesOverride(
        workingLogo: draft[kLimousineProfileLogoKey] as Map<String, dynamic>,
        companyLogoUrl: _kCompanyLogo,
      ),
      isFalse,
    );
    expect(
      limousineEffectiveLogoUrl(
        overrideUrl: '',
        companyLogoUrl: _kCompanyLogo,
      ),
      _kCompanyLogo,
    );
  });

  test('10 limousine hero never falls back to the taxi hero', () {
    final card = tryParseLimousineDiscoveryCard(
      _nearby(
        includePublished: true,
        extra: <String, dynamic>{
          'published_limousine_profile_cover': _cover(_kTaxiHero),
          'published_limousine_hero': _cover(_kTaxiHero),
        },
      ),
    )!;
    expect(card.coverImageUrl, isEmpty);
    expect(card.coverIsPlaceholder, isTrue);
    expect(publicPartnerTaxiHeroUrl(_nearby()), _kTaxiHero);
  });

  test('11 taxi hero stays unchanged after a limousine publish', () {
    final taxi = taxiReplaceBusinessHero(
      businessProfile: <String, dynamic>{
        'publicHeroPhotoUrl': _kTaxiHero,
        'tagline': 'Taxi',
      },
      heroUrl: _kTaxiHero,
    );
    final published = _concept(publish: true);
    expect(taxi['publicHeroPhotoUrl'], _kTaxiHero);
    expect(published.containsKey('publicHeroPhotoUrl'), isFalse);
    expect(published.containsKey('hero_photo_url'), isFalse);
  });

  test('12 limousine logo stays unchanged after a taxi logo change', () {
    final limousine = _concept(publish: true);
    final taxi = taxiReplaceBusinessLogo(
      businessProfile: <String, dynamic>{
        'publicLogoUrl': _kCompanyLogo,
        kLimousineProfileLogoKey: _logo(_kLimoLogo),
      },
      logoUrl: _kTaxiLogoLater,
    );
    expect(taxi['publicLogoUrl'], _kTaxiLogoLater);
    expect(taxi.containsKey(kLimousineProfileLogoKey), isFalse);
    expect(
      (limousine[kLimousinePublishedProfileLogoKey] as Map)['photo_url'],
      _kLimoLogo,
    );
  });

  test('13 clearing the override restores the company logo fallback', () {
    final withOverride = tryParseLimousineDiscoveryCard(
      _nearby(logoOverride: _kLimoLogo),
    )!;
    expect(withOverride.logoUrl, _kLimoLogo);
    final cleared = tryParseLimousineDiscoveryCard(
      _nearby(logoOverride: ''),
    )!;
    expect(cleared.logoUrl, _kCompanyLogo);
  });

  test('14 draft edits stay off the public card until publish', () {
    final live = tryParseLimousineDiscoveryCard(_nearby())!;
    expect(limousineDiscoveryCardTitle(live, AppLanguage.nl), 'Fluxidi');
    expect(
      limousineDiscoveryCardDescription(live, AppLanguage.nl),
      'Voor elke gelegenheid',
    );
    expect(live.coverImageUrl, _kCover);
    final draftOnly = tryParseLimousineDiscoveryCard(
      _nearby(includePublished: true),
    )!;
    expect(limousineDiscoveryCardTitle(draftOnly, AppLanguage.nl), isNot('Draftnaam'));
    expect(
      limousineDiscoveryCardDescription(draftOnly, AppLanguage.nl),
      isNot('Draft tekst'),
    );
  });

  test('15 failed publish keeps the previous full published snapshot', () {
    final previous = _concept(publish: true);
    final failed = limousinePublishedSnapshotOrPrevious(
      publishSucceeded: false,
      incomingPublished: _concept(
        publish: true,
        publishedHero: _cover('https://cdn.example/partial.jpg'),
      ),
      previousPublished: previous,
    );
    expect(
      (failed[kLimousinePublishedVisitingCardKey] as Map)['public_title'],
      (previous[kLimousinePublishedVisitingCardKey] as Map)['public_title'],
    );
    expect(failed[kLimousinePublishedProfileCoverKey], previous[kLimousinePublishedProfileCoverKey]);
    expect(failed[kLimousinePublishedProfileLogoKey], previous[kLimousinePublishedProfileLogoKey]);
  });

  test('16 reopen keeps both the working concept and published snapshot', () {
    final stored = _concept(publish: false);
    expect((stored['public_title'] as Map)['nl'], 'Fluxidi');
    expect((stored['published_public_title'] as Map)['nl'], 'Oud');
    expect((stored[kLimousineProfileCoverKey] as Map)['photo_url'], _kCover);
    expect(
      (stored[kLimousinePublishedProfileCoverKey] as Map)['photo_url'],
      _kDraftCover,
    );
    expect((stored[kLimousineProfileLogoKey] as Map)['photo_url'], _kLimoLogo);
    expect(
      (stored[kLimousinePublishedProfileLogoKey] as Map)['photo_url'],
      isEmpty,
    );
  });

  testWidgets('17 phone and tablet discovery cards stay overflow-free', (
    tester,
  ) async {
    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async => LimousineDiscoveryPageData(
        listingMode: 'test_preview',
        cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
          _nearby(logoOverride: _kLimoLogo),
        ]),
      ),
    );
    for (final size in <Size>[
      kLimousinePhonePortrait,
      kLimousineSmX400Portrait,
      kLimousineTabletLandscape,
    ]) {
      tester.view.physicalSize = Size(size.width * 2, size.height * 2);
      tester.view.devicePixelRatio = 2;
      await tester.pumpWidget(
        _app(
          LimousineCustomerDiscoveryPage(
            gateway: gateway,
            customerHomeBuilder: (_) => const SizedBox.shrink(),
          ),
          size: size,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Fluxidi'), findsWidgets);
      expect(find.text('Voor elke gelegenheid'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets(
    '18 neutral placeholder appears only without a published limousine hero',
    (tester) async {
      final gateway = MemoryLimousineDiscoveryGateway(
        searchHandler: (_) async => LimousineDiscoveryPageData(
          cards: limousineDiscoveryCardsFromNearbyPartners(<dynamic>[
            _nearby(
              extra: <String, dynamic>{
                'published_limousine_profile_cover': const <String, dynamic>{},
                'published_limousine_hero': const <String, dynamic>{},
              },
            ),
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
      expect(find.byKey(kLimousineVehiclePhotoPlaceholderKey), findsOneWidget);
      expect(find.text('F'), findsNothing);
      final photo = tester.widget<LimousineContainPhoto>(
        find.byKey(limousineDiscoveryCardCoverKey(_kPartnerId)),
      );
      expect(photo.imageUrl, isEmpty);
      expect(photo.placeholderLabel, isEmpty);
    },
  );
}
