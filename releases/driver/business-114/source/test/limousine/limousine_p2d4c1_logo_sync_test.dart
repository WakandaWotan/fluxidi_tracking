import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_brand_logo.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_discovery.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_local_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_pricing_overlay.dart';
import 'package:fluxidi_tracking/limousine/limousine_profile_identity.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_hero_overlay.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_vehicle_detail_page.dart';
import 'package:fluxidi_tracking/nearby/public_partner_identity.dart';

const String _kPartnerA = 'limo_company_a';
const String _kPartnerB = 'limo_company_b';
const String _kCompanyLogo =
    'https://cdn.example/public-media/t1/c1/company/logo.png';
const String _kLimoLogo =
    'https://cdn.example/public-media/t1/c1/limousine/profile-logo.png';
const String _kWorkingLogo =
    'https://cdn.example/public-media/t1/c1/limousine/draft-logo.png';
const String _kTenantBLogo =
    'https://cdn.example/public-media/t2/c9/limousine/profile-logo.png';
const String _kTaxiLater =
    'https://cdn.example/public-media/t1/c1/company/logo.png?v=2';

Map<String, dynamic> _logo(String url) {
  return <String, dynamic>{
    'photo_url': url,
    'explicit_override': url.startsWith('https://'),
    'source_revision': 3,
  };
}

Map<String, dynamic> _vehicle(String id, String name) {
  return <String, dynamic>{
    'vehicle_id': id,
    'name': name,
    'service_category': 'limousine',
    'is_active': true,
    'photo_url': 'https://cdn.example/$id.jpg',
    'passenger_capacity': 8,
  };
}

Map<String, dynamic> _offer() {
  return <String, dynamic>{
    'offer_id': 'off_quote',
    'enabled': true,
    'published': true,
    'price_presentation': 'quote_required',
    'target_type': 'service_class',
    'service_class_id': 'stretch_limousine',
  };
}

Map<String, dynamic> _profile({
  String partnerId = _kPartnerA,
  String companyLogo = _kCompanyLogo,
  String? publishedOverride,
  String? workingOverride,
  String? visitingPublished,
}) {
  final payload = limousinePublicDisplayPayload(
    publish: publishedOverride != null,
    title: const <String, String>{'nl': 'Fluxidi Limo'},
    description: const <String, String>{'nl': 'Voor elke gelegenheid'},
    hero: const <String, dynamic>{},
    publishedTitle: const <String, String>{'nl': 'Fluxidi Limo'},
    publishedDescription: const <String, String>{'nl': 'Voor elke gelegenheid'},
    publishedHero: const <String, dynamic>{},
    logo: _logo(workingOverride ?? publishedOverride ?? ''),
    publishedLogo: _logo(publishedOverride ?? ''),
  );
  return <String, dynamic>{
    'partner_id': partnerId,
    'company_name': 'Fluxidi BV',
    'is_active': true,
    'profile_enabled': true,
    'limousine_available': true,
    'limousine_service_enabled': true,
    'logo_url': companyLogo,
    'tenant_id': partnerId == _kPartnerB ? 'tenant_b' : 'tenant_a',
    'company_id': partnerId,
    'limousine_vehicles': <Map<String, dynamic>>[
      _vehicle('vh_party', 'Party Limo'),
      _vehicle('vh_hummer', 'Hummer white'),
    ],
    'limousine_offers': <Map<String, dynamic>>[_offer()],
    if (publishedOverride != null) ...payload,
    if (workingOverride != null && publishedOverride == null)
      kLimousineProfileLogoKey: _logo(workingOverride),
    if (visitingPublished != null)
      kLimousinePublishedVisitingCardKey: <String, dynamic>{
        'logo': _logo(visitingPublished),
      },
  };
}

Widget _app(Widget child) {
  return MaterialApp(
    home: MediaQuery(
      data: const MediaQueryData(size: kLimousineSmX400Portrait),
      child: child,
    ),
  );
}

String? _networkUrl(WidgetTester tester, Key key) {
  final image = tester.widget<Image>(find.byKey(key));
  final provider = image.image;
  return provider is NetworkImage ? provider.url : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryLimousinePricingLocalStore store;

  setUp(() {
    store = MemoryLimousinePricingLocalStore();
    limousinePricingLocalStore = store;
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  tearDown(() {
    limousinePricingLocalStore = FileLimousinePricingLocalStore();
  });

  test('1 working resolver shows the new override immediately', () {
    expect(
      limousineResolveWorkingLogoUrl(
        workingOverrideUrl: _kLimoLogo,
        companyLogoUrl: _kCompanyLogo,
      ),
      _kLimoLogo,
    );
  });

  test('2 publish snapshot stores the logo override, not the taxi logo', () {
    final published = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Fluxidi'},
      description: const <String, String>{'nl': 'Tekst'},
      hero: const <String, dynamic>{},
      publishedTitle: const <String, String>{},
      publishedDescription: const <String, String>{},
      publishedHero: const <String, dynamic>{},
      logo: _logo(_kLimoLogo),
      publishedLogo: const <String, dynamic>{},
    );
    expect(
      (published[kLimousinePublishedProfileLogoKey] as Map)['photo_url'],
      _kLimoLogo,
    );
    expect(published.toString(), isNot(contains(_kCompanyLogo)));
  });

  test('3-7 discovery, showroom, profile and both vehicle details share override', () {
    final partner = _profile(publishedOverride: _kLimoLogo);
    final card = tryParseLimousineDiscoveryCard(partner)!;
    expect(card.logoUrl, _kLimoLogo);

    final showroom = buildLimousineProviderShowroomData(profile: partner);
    expect(showroom.logoUrl, _kLimoLogo);
    expect(
      buildLimousinePublicProfileData(profile: partner).showroom.logoUrl,
      _kLimoLogo,
    );

    final names = showroom.vehicles.map((item) => item.name).toList();
    expect(names, containsAll(<String>['Party Limo', 'Hummer white']));
    for (final vehicle in showroom.vehicles) {
      expect(showroom.logoUrl, _kLimoLogo, reason: vehicle.name);
    }
  });

  test('8 quote and booking provider payloads use the same published resolver', () {
    final partner = _profile(publishedOverride: _kLimoLogo);
    final provider = LimousineDiscoveredProvider.fromJson(partner);
    expect(provider.logoUrl, _kLimoLogo);
    expect(
      limousineResolvePublishedLogoUrl(source: partner),
      provider.logoUrl,
    );
  });

  test('9-10 reopen and restart keep the published override from overlay', () {
    final staleProfile = _profile();
    expect(limousineResolvePublishedLogoUrl(source: staleProfile), _kCompanyLogo);

    store.writeSection(
      _kPartnerA,
      <String, dynamic>{
        'source_revision': 9,
        kLimousinePublishedProfileLogoKey: _logo(_kLimoLogo),
      },
    );
    final hydrated = limousineHydratePublishedPartnerOverlay(
      staleProfile,
      store: store,
    );
    expect(limousineResolvePublishedLogoUrl(source: hydrated), _kLimoLogo);
    expect(
      buildLimousineProviderShowroomData(profile: hydrated).logoUrl,
      _kLimoLogo,
    );
  });

  test('11 clearing the override restores only the general company logo', () {
    expect(
      limousineResolveWorkingLogoUrl(
        workingOverrideUrl: '',
        companyLogoUrl: _kCompanyLogo,
      ),
      _kCompanyLogo,
    );
    final cleared = limousinePublicDisplayPayload(
      publish: true,
      title: const <String, String>{'nl': 'Fluxidi'},
      description: const <String, String>{'nl': 'Tekst'},
      hero: const <String, dynamic>{},
      publishedTitle: const <String, String>{'nl': 'Fluxidi'},
      publishedDescription: const <String, String>{'nl': 'Tekst'},
      publishedHero: const <String, dynamic>{},
      logo: const <String, dynamic>{},
      publishedLogo: _logo(_kLimoLogo),
    );
    expect(
      limousineResolvePublishedLogoUrl(
        source: <String, dynamic>{
          'logo_url': _kCompanyLogo,
          ...cleared,
        },
      ),
      _kCompanyLogo,
    );
  });

  test('12-13 taxi profile and general company branding stay on company/logo', () {
    final taxi = taxiReplaceBusinessLogo(
      businessProfile: <String, dynamic>{
        'publicLogoUrl': _kCompanyLogo,
        kLimousineProfileLogoKey: _logo(_kLimoLogo),
      },
      logoUrl: _kTaxiLater,
    );
    expect(taxi['publicLogoUrl'], _kTaxiLater);
    expect(taxi.containsKey(kLimousineProfileLogoKey), isFalse);
    expect(taxi.containsKey(kLimousinePublishedProfileLogoKey), isFalse);
    final taxiPage = File('lib/partner_public_profile_page.dart').readAsStringSync();
    expect(taxiPage.contains('limousineResolvePublishedLogoUrl'), isFalse);
    expect(taxiPage.contains('kLimousineProfileLogoKey'), isFalse);
    expect(taxiPage.contains("['logo_url', 'logoUrl']"), isTrue);
  });

  test('14-15 tenant A / company A never see tenant B or company B logos', () {
    final a = _profile(publishedOverride: _kLimoLogo);
    final b = _profile(
      partnerId: _kPartnerB,
      publishedOverride: _kTenantBLogo,
      companyLogo: 'https://cdn.example/public-media/t2/c9/company/logo.png',
    );
    expect(limousineResolvePublishedLogoUrl(source: a), _kLimoLogo);
    expect(limousineResolvePublishedLogoUrl(source: b), _kTenantBLogo);
    expect(limousineResolvePublishedLogoUrl(source: a), isNot(_kTenantBLogo));

    store.writeSection(
      _kPartnerB,
      <String, dynamic>{
        'source_revision': 4,
        kLimousinePublishedProfileLogoKey: _logo(_kTenantBLogo),
      },
    );
    final hydratedA = limousineHydratePublishedPartnerOverlay(a, store: store);
    expect(limousineResolvePublishedLogoUrl(source: hydratedA), _kLimoLogo);

    store.writeSection(
      kLimousinePricingLocalDefaultScope,
      <String, dynamic>{
        'source_revision': 5,
        'tenant_id': 'tenant_b',
        'company_id': _kPartnerB,
        'partner_id': _kPartnerB,
        kLimousinePublishedProfileLogoKey: _logo(_kTenantBLogo),
      },
    );
    final isolated = limousineHydratePublishedPartnerOverlay(a, store: store);
    expect(limousineResolvePublishedLogoUrl(source: isolated), _kLimoLogo);
    expect(limousineResolvePublishedLogoUrl(source: isolated), isNot(_kTenantBLogo));
  });

  test('17 customer pages never read an unpublished working override', () {
    final draftOnly = _profile(workingOverride: _kWorkingLogo);
    expect(
      limousineResolvePublishedLogoUrl(source: draftOnly),
      _kCompanyLogo,
    );
    expect(
      limousineDiscoveryEffectiveLogoUrl(draftOnly),
      _kCompanyLogo,
    );
    expect(
      buildLimousineProviderShowroomData(profile: draftOnly).logoUrl,
      _kCompanyLogo,
    );
    expect(
      LimousineDiscoveredProvider.fromJson(draftOnly).logoUrl,
      _kCompanyLogo,
    );
  });

  test('profile API company logo does not hide a discovery-card override', () {
    final staleProfile = _profile();
    final card = tryParseLimousineDiscoveryCard(
      _profile(publishedOverride: _kLimoLogo),
    )!;
    expect(
      buildLimousineProviderShowroomData(
        profile: staleProfile,
        discoveryCard: card,
      ).logoUrl,
      _kLimoLogo,
    );
  });

  testWidgets('16 logos render with BoxFit.contain on card, hero and detail', (
    tester,
  ) async {
    final partner = _profile(publishedOverride: _kLimoLogo);
    final showroom = buildLimousineProviderShowroomData(profile: partner);
    final party = showroom.vehicles.firstWhere((item) => item.name == 'Party Limo');
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: ListView(
            children: [
              LimousineCompanyIdentity(
                logoUrl: showroom.logoUrl,
                companyName: showroom.companyName,
                tokens: LimousineUxTokens.fromCustomer(
                  paletteForCustomerTheme(customerThemeNotifier.value),
                ),
              ),
              SizedBox(
                height: 220,
                child: LimousinePublicHeroOverlay(
                  identity: resolvePublicPartnerHeroIdentity(
                    logoUrl: showroom.logoUrl,
                    companyName: showroom.companyName,
                  ),
                  tokens: LimousineUxTokens.fromCustomer(
                    paletteForCustomerTheme(customerThemeNotifier.value),
                  ),
                ),
              ),
              SizedBox(
                height: 640,
                child: LimousineVehicleDetailPage(
                  vehicle: party,
                  companyName: showroom.companyName,
                  partnerId: showroom.partnerId,
                  logoUrl: showroom.logoUrl,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    for (final key in <Key>[
      kLimousineDiscoveryCompanyLogoKey,
      kLimousinePublicHeroLogoKey,
      kLimousineDetailCompanyLogoKey,
    ]) {
      expect(find.byKey(key), findsOneWidget, reason: '$key');
      final image = tester.widget<Image>(find.byKey(key));
      expect(image.fit, BoxFit.contain, reason: '$key');
      final provider = image.image;
      expect(provider, isA<NetworkImage>());
      expect((provider as NetworkImage).url, _kLimoLogo, reason: '$key');
    }
  });

  testWidgets('showroom and profile heroes use the published override URL', (
    tester,
  ) async {
    final partner = _profile(publishedOverride: _kLimoLogo);
    await tester.pumpWidget(
      _app(
        LimousineProviderShowroomPage(
          partnerId: _kPartnerA,
          profile: partner,
        ),
      ),
    );
    await tester.pump();
    expect(_networkUrl(tester, kLimousinePublicHeroLogoKey), _kLimoLogo);

    await tester.pumpWidget(
      _app(
        LimousinePublicProfilePage(
          partnerId: _kPartnerA,
          profile: partner,
        ),
      ),
    );
    await tester.pump();
    expect(_networkUrl(tester, kLimousinePublicHeroLogoKey), _kLimoLogo);
  });

  testWidgets('stale logoImage cannot keep an old general logo on detail', (
    tester,
  ) async {
    final showroom = buildLimousineProviderShowroomData(
      profile: _profile(publishedOverride: _kLimoLogo),
    );
    final hummer = showroom.vehicles.firstWhere(
      (item) => item.name == 'Hummer white',
    );
    await tester.pumpWidget(
      _app(
        LimousineVehicleDetailPage(
          vehicle: hummer,
          companyName: showroom.companyName,
          partnerId: showroom.partnerId,
          logoUrl: showroom.logoUrl,
          logoImage: const NetworkImage(_kCompanyLogo),
        ),
      ),
    );
    await tester.pump();
    expect(_networkUrl(tester, kLimousineDetailCompanyLogoKey), _kLimoLogo);
  });
}
