import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_local_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_overlay.dart';
import 'package:fluxidi_tracking/limousine/limousine_profile_identity.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';

const String _kPartnerId = 'company:tenant_a:company_a';
const String _kForeignPartnerId = 'company:tenant_b:company_b';
const String _kLimoLogo =
    'https://cdn.example/public-media/tenant_a/company_a/limousine/profile-logo.png';
const String _kLimoCover =
    'https://cdn.example/public-media/tenant_a/company_a/limousine/profile-cover.jpg';
const String _kCompanyLogo =
    'https://cdn.example/public-media/tenant_a/company_a/company/logo.png';
const String _kTaxiLogo =
    'https://cdn.example/public-media/tenant_a/company_a/company/logo.png';
const String _kForeignLogo =
    'https://cdn.example/public-media/tenant_b/company_b/company/logo.png';

const String _kFullDescription = 'Party Ride voor elke gelegenheid.\nInclusief chauffeur.';

Map<String, dynamic> _cover(String url) {
  return <String, dynamic>{
    'photo_url': url,
    'alignment': 'right',
    'source_kind': 'upload',
    'media_id': 'media_cover_1',
    'source_revision': 2,
  };
}

Map<String, dynamic> _logo(String url) {
  return <String, dynamic>{
    'photo_url': url,
    'explicit_override': true,
    'media_id': 'media_logo_1',
    'source_revision': 2,
  };
}

/// In-memory worker: working stays private, published is the only public source.
class _PublishedIdentityBackend {
  Map<String, dynamic> working = <String, dynamic>{};
  Map<String, dynamic> published = <String, dynamic>{};
  String publishedAt = '';

  void writeWorking() {
    working = limousinePublicDisplayPayload(
      publish: false,
      title: const <String, String>{'nl': 'Party Ride'},
      description: const <String, String>{'nl': _kFullDescription},
      hero: _cover(_kLimoCover),
      publishedTitle: const <String, String>{},
      publishedDescription: const <String, String>{},
      publishedHero: const <String, dynamic>{},
      logo: _logo(_kLimoLogo),
      publishedLogo: const <String, dynamic>{},
    );
  }

  void publish() {
    published = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Party Ride'},
      description: const <String, String>{'nl': _kFullDescription},
      hero: _cover(_kLimoCover),
      publishedTitle: const <String, String>{},
      publishedDescription: const <String, String>{},
      publishedHero: const <String, dynamic>{},
      logo: _logo(_kLimoLogo),
      publishedLogo: const <String, dynamic>{},
    );
    publishedAt = '2026-08-20T09:45:00Z';
    published['published_at'] = publishedAt;
    published['tenant_id'] = 'tenant_a';
    published['company_id'] = 'company_a';
    published['partner_id'] = _kPartnerId;
  }

  Map<String, dynamic> nearbyCard() {
    return <String, dynamic>{
      'partner_id': _kPartnerId,
      'company_name': 'Fluxidi',
      'is_active': true,
      'profile_enabled': true,
      'limousine_available': true,
      'limousine_service_enabled': true,
      'logo_url': _kCompanyLogo,
      'about_short': 'Algemene Fluxidi-bedrijfstekst',
      'limousine_vehicles': <Map<String, dynamic>>[
        <String, dynamic>{
          'vehicle_id': 'vh_party',
          'name': 'Party Limo',
          'service_category': 'limousine',
          'service_class_id': 'stretch_limousine',
          'is_active': true,
          'photo_url': 'https://cdn.example/party.jpg',
        },
        <String, dynamic>{
          'vehicle_id': 'vh_hummer',
          'name': 'Hummer white',
          'service_category': 'limousine',
          'service_class_id': 'luxury_van',
          'is_active': true,
          'photo_url': 'https://cdn.example/hummer.jpg',
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
      ...published,
    };
  }

  Map<String, dynamic> taxiCard() {
    return <String, dynamic>{
      'partner_id': _kPartnerId,
      'company_name': 'Fluxidi',
      'logo_url': _kTaxiLogo,
      'services': <String>['taxi_vvb'],
    };
  }

  Map<String, dynamic> foreignCard() {
    return <String, dynamic>{
      'partner_id': _kForeignPartnerId,
      'company_name': 'Other Co',
      'is_active': true,
      'profile_enabled': true,
      'limousine_available': true,
      'limousine_service_enabled': true,
      'logo_url': _kForeignLogo,
      'published_public_title': const <String, String>{'nl': 'Other Ride'},
      'published_limousine_profile_logo': _logo(_kForeignLogo),
    };
  }
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: kLimousinePhonePortrait),
      child: child,
    ),
  );
}

void _assertSamePublishedIdentity({
  required String logoUrl,
  required String coverUrl,
  required String title,
  required String description,
}) {
  expect(logoUrl, _kLimoLogo);
  expect(coverUrl, _kLimoCover);
  expect(title, 'Party Ride');
  expect(description, _kFullDescription);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLimousinePricingLocalStore emptyOverlay;
  late _PublishedIdentityBackend backend;

  setUp(() {
    emptyOverlay = MemoryLimousinePricingLocalStore();
    limousinePricingLocalStore = emptyOverlay;
    backend = _PublishedIdentityBackend();
    appLanguageNotifier.value = AppLanguage.nl;
  });

  tearDown(() {
    limousinePricingLocalStore = FileLimousinePricingLocalStore();
  });

  test('fresh customer chain reads backend published identity without overlay', () async {
    backend.writeWorking();
    expect(backend.working[kLimousineProfileLogoKey], isNotNull);
    backend.publish();
    expect(emptyOverlay.peekSection(_kPartnerId), isEmpty);

    final nearby = backend.nearbyCard();
    expect(limousineBackendPublishedIdentityIsPresent(nearby), isTrue);
    expect(
      limousineHydratePublishedPartnerOverlay(nearby, store: emptyOverlay),
      nearby,
    );

    final card = tryParseLimousineDiscoveryCard(nearby)!;
    final showroom = buildLimousineProviderShowroomData(
      profile: nearby,
      language: AppLanguage.nl,
    );
    final profile = buildLimousinePublicProfileData(
      profile: nearby,
      language: AppLanguage.nl,
    );
    final party = showroom.vehicles.firstWhere((v) => v.vehicleId == 'vh_party');
    final hummer = showroom.vehicles.firstWhere(
      (v) => v.vehicleId == 'vh_hummer',
    );

    _assertSamePublishedIdentity(
      logoUrl: card.logoUrl,
      coverUrl: card.coverImageUrl,
      title: limousineDiscoveryCardTitle(card, AppLanguage.nl),
      description: limousineDiscoveryCardDescription(card, AppLanguage.nl),
    );
    _assertSamePublishedIdentity(
      logoUrl: showroom.logoUrl,
      coverUrl: showroom.heroPhotoUrl,
      title: showroom.companyName,
      description: showroom.tagline,
    );
    _assertSamePublishedIdentity(
      logoUrl: profile.showroom.logoUrl,
      coverUrl: profile.showroom.heroPhotoUrl,
      title: profile.showroom.companyName,
      description: profile.showroom.tagline,
    );
    expect(showroom.description, isEmpty);
    expect(party.name, 'Party Limo');
    expect(hummer.name, 'Hummer white');
    expect(showroom.logoUrl, party.offers.isEmpty ? _kLimoLogo : _kLimoLogo);

    final gateway = MemoryLimousineDiscoveryGateway(
      searchHandler: (_) async {
        return LimousineDiscoveryPageData(cards: <LimousineDiscoveryCard>[card]);
      },
      profileHandler: (_) async => nearby,
    );
    final controller = LimousineDiscoveryController(gateway: gateway);
    await controller.search(const LimousineDiscoveryQuery(postcode: '2000'));
    expect(controller.cards.single.logoUrl, _kLimoLogo);

    await controller.search(const LimousineDiscoveryQuery(postcode: '2000'));
    expect(controller.cards.single.logoUrl, _kLimoLogo);
  });

  testWidgets('fresh customer pages render the same published logo without overlay', (
    tester,
  ) async {
    backend.publish();
    final nearby = backend.nearbyCard();
    final card = tryParseLimousineDiscoveryCard(nearby)!;
    final showroom = buildLimousineProviderShowroomData(
      profile: nearby,
      language: AppLanguage.nl,
    );

    await tester.pumpWidget(
      _app(
        LimousineProviderShowroomPage(
          partnerId: _kPartnerId,
          profile: nearby,
          discoveryCard: card,
        ),
      ),
    );
    await tester.pump();
    expect(showroom.companyName, 'Party Ride');
    expect(showroom.logoUrl, _kLimoLogo);
    expect(find.text('Party Limo'), findsWidgets);
    expect(find.text('Hummer white'), findsWidgets);

    await tester.pumpWidget(
      _app(
        LimousinePublicProfilePage(
          partnerId: _kPartnerId,
          profile: nearby,
          discoveryCard: card,
        ),
      ),
    );
    await tester.pump();
    final profile = buildLimousinePublicProfileData(
      profile: nearby,
      language: AppLanguage.nl,
    );
    expect(profile.showroom.companyName, 'Party Ride');
    expect(profile.showroom.logoUrl, _kLimoLogo);
    expect(profile.showroom.heroPhotoUrl, _kLimoCover);
    expect(profile.showroom.tagline, _kFullDescription);
    expect(find.textContaining('Party Ride voor elke gelegenheid'), findsWidgets);
    expect(find.text('Algemene Fluxidi-bedrijfstekst'), findsNothing);

    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: showroom.vehicles.first,
          companyName: showroom.companyName,
          partnerId: _kPartnerId,
          logoUrl: showroom.logoUrl,
        ),
      ),
    );
    await tester.pump();
    expect(showroom.logoUrl, _kLimoLogo);
  });

  test('app reinit with empty overlay still reads backend identity', () {
    backend.publish();
    final first = tryParseLimousineDiscoveryCard(backend.nearbyCard())!;
    limousinePricingLocalStore = MemoryLimousinePricingLocalStore();
    final second = tryParseLimousineDiscoveryCard(backend.nearbyCard())!;
    expect(first.logoUrl, second.logoUrl);
    expect(first.coverImageUrl, second.coverImageUrl);
    expect(first.publicTitle, second.publicTitle);
  });

  test('tenant isolation and taxi branding stay unchanged', () {
    backend.publish();
    final own = tryParseLimousineDiscoveryCard(backend.nearbyCard())!;
    expect(own.logoUrl, _kLimoLogo);
    expect(
      limousineResolvePublishedLogoUrl(source: backend.foreignCard()),
      isNot(_kLimoLogo),
    );
    expect(backend.foreignCard()['partner_id'], _kForeignPartnerId);
    expect(limousineCompanyLogoUrl(backend.taxiCard()), _kTaxiLogo);
    expect(limousinePublishedLogoOverrideUrl(backend.taxiCard()), isEmpty);
    expect(
      limousineResolvePublishedLogoUrl(source: backend.taxiCard()),
      _kTaxiLogo,
    );
  });

  test('local overlay is ignored once backend published identity is present', () {
    backend.publish();
    final nearby = backend.nearbyCard();
    final overlayStore = MemoryLimousinePricingLocalStore();
    overlayStore.writeOverlay(
      scopeKeys: <String>[_kPartnerId],
      fields: <String, dynamic>{
        'published_public_title': const <String, String>{'nl': 'Stale overlay'},
        kLimousinePublishedProfileLogoKey: _logo(
          'https://cdn.example/stale-overlay.png',
        ),
        'source_revision': 99,
      },
    );
    final hydrated = limousineHydratePublishedPartnerOverlay(
      nearby,
      store: overlayStore,
    );
    expect(hydrated['published_public_title'], nearby['published_public_title']);
    expect(
      limousineResolvePublishedLogoUrl(source: hydrated),
      _kLimoLogo,
    );
  });
}
