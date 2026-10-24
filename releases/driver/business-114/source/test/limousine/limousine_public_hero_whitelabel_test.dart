import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup.dart';
import 'package:fluxidi_tracking/limousine/limousine_business_setup_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_hero_overlay.dart';
import 'package:fluxidi_tracking/limousine/limousine_provider_showroom_page.dart';
import 'package:fluxidi_tracking/limousine/limousine_public_profile_page.dart';
import 'package:fluxidi_tracking/nearby/public_partner_identity.dart';

final Uint8List _kTinyPng = Uint8List.fromList(<int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

MemoryImage get _logo => MemoryImage(_kTinyPng);

LimousineUxTokens _tokens() {
  return LimousineUxTokens.fromSurface(background: const Color(0xFF1A1408));
}

Map<String, dynamic> _profile({
  String companyName = 'Maison Noire',
  String logoUrl = 'https://cdn.example/logo.png',
  String description = 'Avondritten met chauffeur in eigen stretchlimousine.',
}) {
  return <String, dynamic>{
    'partner_id': 'limo_1',
    'company_name': companyName,
    'logo_url': logoUrl,
    'tagline': '',
    'about_short': description,
    'limousine_available': true,
    'limousine_hero_url': 'https://cdn.example/limousine-hero.jpg',
    'vehicles': <Map<String, dynamic>>[
      <String, dynamic>{
        'vehicle_id': 'vh_1',
        'name': 'Party Limo',
        'service_category': 'limousine',
        'service_class': 'party_stretch',
        'photo_url': 'https://cdn.example/party.jpg',
        'is_active': true,
      },
    ],
  };
}

Widget _overlayHost({
  required Size size,
  required PublicPartnerHeroIdentity identity,
  bool compact = false,
  double height = 260,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: Scaffold(
        body: SizedBox(
          width: size.width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF8899AA)),
              LimousinePublicHeroOverlay(
                identity: identity,
                tokens: _tokens(),
                compact: compact,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _app(Widget child, {Size size = const Size(390, 844)}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(size: size),
      child: child,
    ),
  );
}

void _expectNoOverlap(Rect a, Rect b) {
  expect(a.overlaps(b), isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
  });

  test('shared identity never falls back to Fluxidi', () {
    final withLogo = resolvePublicPartnerHeroIdentity(
      logoUrl: 'https://cdn.example/logo.png',
      companyName: 'Maison Noire',
      description: 'Publieke beschrijving',
    );
    expect(withLogo.showsLogo, isTrue);
    expect(withLogo.showsName, isFalse);
    expect(withLogo.nameFallback, isEmpty);

    final nameOnly = resolvePublicPartnerHeroIdentity(
      companyName: 'Maison Noire',
      description: 'Publieke beschrijving',
    );
    expect(nameOnly.showsLogo, isFalse);
    expect(nameOnly.showsName, isTrue);
    expect(nameOnly.nameFallback, 'Maison Noire');

    final empty = resolvePublicPartnerHeroIdentity(
      companyName: 'Fluxidi',
      description: '',
    );
    expect(empty.showsLogo, isFalse);
    expect(empty.showsName, isFalse);
    expect(empty.nameFallback, isEmpty);
    expect(sanitizePublicPartnerBrandName('Fluxidi'), isEmpty);
    expect(sanitizePublicPartnerBrandName('fluxidi partner'), isEmpty);
  });

  test('preview and public pages share the same identity helper', () {
    final setup = File(
      'lib/limousine/limousine_business_setup_page.dart',
    ).readAsStringSync();
    final profile = File(
      'lib/limousine/limousine_public_profile_page.dart',
    ).readAsStringSync();
    final showroom = File(
      'lib/limousine/limousine_provider_showroom_page.dart',
    ).readAsStringSync();
    expect(setup.contains("'Fluxidi'"), isFalse);
    expect(setup.contains('"Fluxidi"'), isFalse);
    expect(setup.contains('LimousinePublicCompanyCard'), isTrue);
    expect(setup.contains('LimousinePublicHeroOverlay'), isFalse);
    expect(profile.contains('resolvePublicPartnerHeroIdentity'), isTrue);
    expect(profile.contains('LimousinePublicHeroOverlay'), isTrue);
    expect(showroom.contains('resolvePublicPartnerHeroIdentity'), isTrue);
    expect(showroom.contains('LimousinePublicHeroOverlay'), isTrue);
    expect(profile.contains('LimousineBrandLogoCorner'), isFalse);
    expect(showroom.contains('LimousineBrandLogoCorner'), isFalse);
    expect(setup.contains('LimousineBrandLogoPlaque'), isFalse);
  });

  testWidgets('hero with logo keeps it top-right and off the description', (
    tester,
  ) async {
    for (final size in const <Size>[Size(390, 844), Size(800, 1280)]) {
      final identity = resolvePublicPartnerHeroIdentity(
        logoUrl: 'https://cdn.example/logo.png',
        logoImage: _logo,
        companyName: 'Maison Noire',
        description: 'Avondritten met chauffeur in eigen stretchlimousine.',
      );
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _overlayHost(size: size, identity: identity, height: 260),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Fluxidi'), findsNothing);
      expect(find.byKey(kLimousinePublicHeroLogoKey), findsOneWidget);
      expect(find.byKey(kLimousinePublicHeroNameKey), findsNothing);
      expect(find.text('Maison Noire'), findsNothing);
      expect(find.byKey(kLimousinePublicHeroDescriptionKey), findsOneWidget);
      expect(
        find.text('Avondritten met chauffeur in eigen stretchlimousine.'),
        findsOneWidget,
      );
      final hero = tester.getRect(find.byKey(kLimousinePublicHeroOverlayKey));
      final logo = tester.getRect(find.byKey(kLimousinePublicHeroLogoKey));
      final description = tester.getRect(
        find.byKey(kLimousinePublicHeroDescriptionKey),
      );
      expect(logo.right, greaterThan(hero.right - 40));
      expect(logo.right, lessThanOrEqualTo(hero.right - 6));
      expect(logo.top, lessThan(hero.top + 32));
      expect(description.left, lessThan(hero.left + 24));
      expect(description.bottom, lessThanOrEqualTo(hero.bottom));
      _expectNoOverlap(logo, description);
      expect(
        tester.widget<Image>(find.byKey(kLimousinePublicHeroLogoKey)).fit,
        BoxFit.contain,
      );
    }
  });

  testWidgets('without logo the public company name is used', (tester) async {
    await tester.pumpWidget(
      _overlayHost(
        size: const Size(390, 844),
        identity: resolvePublicPartnerHeroIdentity(
          companyName: 'Maison Noire',
          description: 'Publieke beschrijving',
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousinePublicHeroLogoKey), findsNothing);
    expect(find.byKey(kLimousinePublicHeroNameKey), findsOneWidget);
    expect(find.text('Maison Noire'), findsOneWidget);
    expect(find.text('Fluxidi'), findsNothing);
  });

  testWidgets('without logo and name no platform fallback appears', (
    tester,
  ) async {
    await tester.pumpWidget(
      _overlayHost(
        size: const Size(390, 844),
        identity: resolvePublicPartnerHeroIdentity(
          companyName: 'Fluxidi',
          description: '',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Fluxidi'), findsNothing);
    expect(find.byKey(kLimousinePublicHeroNameKey), findsNothing);
    expect(find.byKey(kLimousinePublicHeroLogoKey), findsNothing);
  });

  testWidgets('preview and public pages use the same overlay rules', (
    tester,
  ) async {
    const description = 'Avondritten met chauffeur in eigen stretchlimousine.';
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{'offers': <dynamic>[]},
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[],
          knownClassIds: const <String>['executive_sedan'],
          language: AppLanguage.nl,
          companyName: 'Maison Noire',
          logoUrl: 'https://cdn.example/logo.png',
          logoImage: _logo,
        ),
        size: const Size(800, 1280),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(kLimousineBusinessSetupPreviewKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.text('Fluxidi'),
      ),
      findsNothing,
    );

    final profile = _profile(description: description);
    await tester.pumpWidget(
      _app(
        LimousinePublicProfilePage(
          partnerId: 'limo_1',
          profile: profile,
          logoImage: _logo,
        ),
        size: const Size(800, 1280),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousinePublicHeroOverlayKey), findsOneWidget);
    expect(find.byKey(kLimousinePublicHeroLogoKey), findsOneWidget);
    expect(find.byKey(kLimousinePublicHeroNameKey), findsNothing);
    expect(find.text('Fluxidi'), findsNothing);
    expect(find.text(description), findsWidgets);

    await tester.pumpWidget(
      _app(
        LimousineProviderShowroomPage(
          partnerId: 'limo_1',
          profile: profile,
          logoImage: _logo,
        ),
        size: const Size(390, 844),
      ),
    );
    await tester.pump();
    expect(find.byKey(kLimousinePublicHeroOverlayKey), findsOneWidget);
    expect(find.byKey(kLimousinePublicHeroLogoKey), findsOneWidget);
    expect(find.text('Fluxidi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty preview does not invent Fluxidi', (tester) async {
    await tester.pumpWidget(
      _app(
        LimousineBusinessSetupPage(
          loadPricing: () async => <String, dynamic>{
            'limousine': <String, dynamic>{'offers': <dynamic>[]},
          },
          savePricing: (_) async => <String, dynamic>{},
          vehicles: <VehicleProfile>[],
          knownClassIds: const <String>['executive_sedan'],
          language: AppLanguage.nl,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Fluxidi'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(kLimousineBusinessSetupPreviewKey),
        matching: find.byKey(kLimousinePublicHeroNameKey),
      ),
      findsNothing,
    );
  });
}
