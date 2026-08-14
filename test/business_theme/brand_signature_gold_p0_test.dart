import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_assets.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_l10n.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_cycle.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_preset.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_action_card.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_header.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';
import 'package:fluxidi_tracking/widgets/business_theme_selector_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  ActiveCompanySession? sessionBefore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluxidi_brand_sig_gold_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    resetBusinessThemePersistenceLatchForTest();
    sessionBefore = activeCompanySessionNotifier.value;
    activeCompanySessionNotifier.value = null;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    businessAppearanceNotifier.value = BusinessThemeVariant.executiveGold;
    brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
  });

  tearDown(() async {
    activeCompanySessionNotifier.value = sessionBefore;
    resetBusinessThemePersistenceLatchForTest();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('additive identity and compatibility', () {
    test('1 Brand Signature Gold is additive and selectable', () {
      expect(
        BusinessThemeVariant.values.contains(
          BusinessThemeVariant.brandSignatureGold,
        ),
        isTrue,
      );
      expect(
        kBusinessThemeCycleOrder.last,
        BusinessThemeVariant.brandSignatureGold,
      );
      expect(
        businessThemeProductLabel(BusinessThemeVariant.brandSignatureGold),
        'Brand Signature Gold',
      );
    });

    test('2 existing saved theme values remain compatible', () async {
      final root = Directory(
        '${tempDir.path}${Platform.pathSeparator}business_state',
      );
      await root.create(recursive: true);
      final file = File(
        '${root.path}${Platform.pathSeparator}business_theme_v1.json',
      );
      await file.writeAsString(
        jsonEncode(<String, dynamic>{'variant': 'corporateBlue'}),
        flush: true,
      );
      await loadBusinessThemePreference();
      expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
    });

    test('3 no existing company is automatically migrated', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.emeraldIvory);
      _setCompany('co_existing');
      await loadBusinessThemePreference();
      expect(businessThemeNotifier.value, BusinessThemeVariant.emeraldIvory);
      expect(
        resolveStoredBusinessThemeForCompany('co_existing'),
        BusinessThemeVariant.emeraldIvory,
      );
      expect(
        resolveStoredBusinessThemeForCompany('co_other'),
        BusinessThemeVariant.emeraldIvory,
      );
    });

    test('4 existing themes do not reference new gold assets', () {
      for (final preset in <BusinessThemeVariant>[
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
      ]) {
        final asset = businessThemePresetAsset(
          preset: preset,
          executiveGold: 'assets/fluxidi/settings_background_company.webp',
          corporateBlue:
              'assets/Corporate BLEU Compagny/company_settings_corporate_blue.webp',
          cleanProfessional:
              'assets/Clean & Professional Compagny/company_settings_clean_professional.webp',
          emeraldIvory:
              'assets/Emerald_Ivory_Company/company_settings_alt_emerald_ivory.webp',
          fluxidiNeonRush:
              'assets/🥇 Fluxidi Neon Rush/company_settings_neon_rush.webp',
        );
        expect(isBrandSignatureGoldAssetPath(asset), isFalse);
        expect(asset.contains('brand_signature_gold'), isFalse);
      }
    });

    test('5 existing render branches remain unchanged', () {
      final home = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(home.contains('zakelijke_tablet_header_foto.webp'), isTrue);
      expect(home.contains('else if (usesTabletHeader)'), isTrue);
      expect(home.contains('if (isBrandSignatureGold)'), isTrue);
      expect(home.contains('_brandSignatureGoldQuickActions'), isTrue);
    });

    test('6 chauffeur themes and storage are untouched', () {
      expect(
        DriverThemeVariant.values.map((v) => v.name).toList(),
        isNot(contains('brandSignatureGold')),
      );
      for (final path in <String>[
        'lib/driver_theme_palette.dart',
        'lib/driver_theme_store.dart',
        'lib/company_driver_view_theme_store.dart',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src.contains('brandSignatureGold'), isFalse, reason: path);
        expect(src.contains('brand_signature_gold'), isFalse, reason: path);
      }
    });
  });

  group('selector, preview and persistence', () {
    testWidgets('7 palette button remains directly accessible', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrandSignatureGoldHeader(
              height: 180,
              logoRef: '',
              hasCompanyLogo: false,
              companyName: 'FLX',
            ),
          ),
        ),
      );
      expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);
    });

    testWidgets('8 selector contains business themes only', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BusinessThemeSelectorSheet())),
      );
      await tester.pumpAndSettle();
      for (final variant in BusinessThemeVariant.values) {
        final tile = find.byKey(
          Key('business_theme_selector_tile_${variant.name}'),
        );
        await tester.scrollUntilVisible(tile, 80);
        expect(tile, findsOneWidget);
      }
      expect(find.text('Night Gold'), findsNothing);
      expect(find.text('Midnight Blue'), findsNothing);
      expect(find.text('Light Emerald'), findsNothing);
      expect(find.text('Midday Gold'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('9 active theme has a visible check', (tester) async {
      businessThemeNotifier.value = BusinessThemeVariant.corporateBlue;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BusinessThemeSelectorSheet())),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('business_theme_selector_check_corporateBlue')),
        findsOneWidget,
      );
    });

    test('10 selecting starts preview without persistence', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.executiveGold);
      previewBusinessTheme(BusinessThemeVariant.brandSignatureGold);
      expect(isBusinessThemePreviewActive, isTrue);
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.brandSignatureGold,
      );
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}business_state'
        '${Platform.pathSeparator}business_theme_v1.json',
      );
      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['variant'], 'executiveGold');
    });

    test('11 Toepassen persists for the current company', () async {
      _setCompany('co_apply');
      await applyBusinessThemePreset(BusinessThemeVariant.executiveGold);
      previewBusinessTheme(BusinessThemeVariant.brandSignatureGold);
      await applyBusinessThemePreset(BusinessThemeVariant.brandSignatureGold);
      expect(isBusinessThemePreviewActive, isFalse);
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}business_state'
        '${Platform.pathSeparator}business_theme_v1.json',
      );
      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['variant'], 'executiveGold');
      expect((decoded['byCompanyId'] as Map)['co_apply'], 'brandSignatureGold');
    });

    test('12 Annuleren restores the previous theme exactly', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.cleanProfessional);
      previewBusinessTheme(BusinessThemeVariant.brandSignatureGold);
      cancelBusinessThemePreview();
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );
      expect(isBusinessThemePreviewActive, isFalse);
    });

    testWidgets('13 dismissing restores the previous theme', (tester) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.emeraldIvory),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showBusinessThemeSelectorSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final goldTile = find.byKey(
        const Key('business_theme_selector_tile_brandSignatureGold'),
      );
      await tester.scrollUntilVisible(goldTile, 80);
      await tester.tap(goldTile);
      await tester.pumpAndSettle();
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.brandSignatureGold,
      );
      await tester.tap(find.byKey(kBusinessThemeSelectorCancelKey));
      await tester.pumpAndSettle();
      expect(businessThemeNotifier.value, BusinessThemeVariant.emeraldIvory);
      await tester.binding.setSurfaceSize(null);
    });

    test('14 company switching cannot leak theme or preview state', () async {
      _setCompany('co_a');
      await applyBusinessThemePreset(BusinessThemeVariant.brandSignatureGold);
      previewBusinessTheme(BusinessThemeVariant.corporateBlue);
      _setCompany('co_b');
      syncBusinessThemeForActiveCompany();
      expect(isBusinessThemePreviewActive, isFalse);
      expect(
        businessThemeNotifier.value,
        isNot(BusinessThemeVariant.corporateBlue),
      );
      expect(
        resolveStoredBusinessThemeForCompany('co_a'),
        BusinessThemeVariant.brandSignatureGold,
      );
      expect(
        resolveStoredBusinessThemeForCompany('co_b'),
        isNot(BusinessThemeVariant.brandSignatureGold),
      );
    });

    test('15 settings and dashboard use the same controller', () async {
      await saveBusinessThemeAndAppearancePreset(
        BusinessThemeVariant.brandSignatureGold,
      );
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.brandSignatureGold,
      );
      expect(
        activeBusinessThemePreset(),
        BusinessThemeVariant.brandSignatureGold,
      );
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.brandSignatureGold,
      );
    });
  });

  group('Brand Signature visuals and mapping', () {
    test('16 Brand Signature uses no photographic dashboard assets', () {
      for (final key in kBrandSignatureGoldAssetKeys) {
        final path = brandSignatureGoldAssetPath(key);
        expect(isPhotographicBusinessDashboardAsset(path), isFalse);
        expect(isBrandSignatureGoldAssetPath(path), isTrue);
      }
    });

    testWidgets('17 header uses tenant logo with contain', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrandSignatureGoldHeader(
              height: 200,
              logoRef: 'assets/fluxidi/fluxidi_logo.png',
              hasCompanyLogo: true,
              companyName: 'Tenant',
            ),
          ),
        ),
      );
      final image = tester.widget<Image>(
        find.byKey(kBrandSignatureGoldLogoKey),
      );
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('18 missing-logo fallback is safe and non-photographic', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrandSignatureGoldHeader(
              height: 200,
              logoRef: '',
              hasCompanyLogo: false,
              companyName: 'Wakanda',
            ),
          ),
        ),
      );
      expect(find.byKey(kBrandSignatureGoldLogoFallbackKey), findsOneWidget);
      expect(find.text('W'), findsOneWidget);
      expect(find.byKey(kBrandSignatureGoldLogoKey), findsNothing);
    });

    testWidgets('19 palette button does not cover the logo', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 220,
              child: BrandSignatureGoldHeader(
                height: 200,
                logoRef: '',
                hasCompanyLogo: false,
                companyName: 'FLX',
              ),
            ),
          ),
        ),
      );
      final header = tester.getRect(find.byKey(kBrandSignatureGoldHeaderKey));
      final button = tester.getRect(
        find.byKey(BusinessThemeCycleButton.buttonKey),
      );
      final fallback = tester.getRect(
        find.byKey(kBrandSignatureGoldLogoFallbackKey),
      );
      expect(header.contains(button.center), isTrue);
      expect(button.overlaps(fallback), isFalse);
    });

    test('20 all actions use the correct golden asset mapping', () {
      expect(kBrandSignatureGoldActionAssetKeys['settings'], 'settings');
      expect(kBrandSignatureGoldActionAssetKeys['payments'], 'payments');
      expect(kBrandSignatureGoldActionAssetKeys['vehicles'], 'vehicles');
      expect(kBrandSignatureGoldActionAssetKeys['documents'], 'documents');
      expect(kBrandSignatureGoldActionAssetKeys['customers'], 'customers');
      expect(kBrandSignatureGoldActionAssetKeys['drivers'], 'drivers');
      expect(
        kBrandSignatureGoldActionAssetKeys['demand_radar'],
        'demand_radar',
      );
      expect(
        kBrandSignatureGoldActionAssetKeys['booking_link'],
        'booking_link',
      );
      expect(kBrandSignatureGoldActionAssetKeys['planning'], 'planning');
      expect(kBrandSignatureGoldActionAssetKeys['ai_dispatch'], 'ai_dispatch');
      expect(kBrandSignatureGoldActionAssetKeys['theme'], 'theme');
    });

    test('21 existing action handlers and destinations are preserved', () {
      final home = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(home.contains('const BusinessSettingsPage()'), isTrue);
      expect(home.contains('const CompanySubscriptionBillingPage()'), isTrue);
      expect(home.contains('const VehicleManagementPage()'), isTrue);
      expect(home.contains('const ChironComplianceDashboardPage()'), isTrue);
      expect(home.contains('const CompanyDriverManagementPage()'), isTrue);
      expect(home.contains('_openDriverCockpitView'), isTrue);
      expect(home.contains('const BusinessRegionalDemandPage()'), isTrue);
      expect(home.contains('_showPublicBookingShareQuickAccess'), isTrue);
      expect(home.contains('_openBusinessBookingsOverview'), isTrue);
    });

    test('22 AI Dispatch remains disabled / coming soon', () {
      final home = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(home.contains("actionKey: 'ai_dispatch'"), isTrue);
      expect(home.contains('isFuture: true'), isTrue);
      expect(home.contains("nl: 'Binnenkort'"), isTrue);
    });

    testWidgets('23 tablet portrait and landscape do not overflow', (
      tester,
    ) async {
      for (final size in <Size>[const Size(800, 1280), const Size(1280, 800)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: size.width,
                height: size.height,
                child: GridView.count(
                  crossAxisCount: size.width > size.height ? 3 : 2,
                  children: [
                    for (final key in <String>[
                      'settings',
                      'payments',
                      'vehicles',
                      'documents',
                      'customers',
                      'drivers',
                      'demand_radar',
                      'booking_link',
                      'planning',
                      'ai_dispatch',
                    ])
                      BrandSignatureGoldActionCard(
                        actionKey: key,
                        title: 'Title $key',
                        subtitle: 'Subtitle',
                        isFuture: key == 'ai_dispatch',
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.binding.setSurfaceSize(null);
    });

    test('24 NL/EN/FR/ES labels exist', () {
      for (final language in AppLanguage.values) {
        if (language == AppLanguage.de) continue;
        appLanguageNotifier.value = language;
        expect(businessThemeSelectorTitle(), isNotEmpty);
        expect(businessThemeSelectorApplyLabel(), isNotEmpty);
        expect(businessThemeSelectorCancelLabel(), isNotEmpty);
        expect(brandSignatureCustomizeStyleLabel(), isNotEmpty);
      }
      appLanguageNotifier.value = AppLanguage.nl;
      expect(businessThemeSelectorTitle(), 'Kies je uitstraling');
      appLanguageNotifier.value = AppLanguage.en;
      expect(businessThemeSelectorTitle(), 'Choose your appearance');
      appLanguageNotifier.value = AppLanguage.fr;
      expect(businessThemeSelectorTitle(), 'Choisissez votre apparence');
      appLanguageNotifier.value = AppLanguage.es;
      expect(businessThemeSelectorTitle(), 'Elige tu estilo');
      appLanguageNotifier.value = AppLanguage.nl;
      expect(businessThemeSelectorApplyLabel(), 'Toepassen');
      expect(businessThemeSelectorCancelLabel(), 'Annuleren');
      expect(brandSignatureCustomizeStyleLabel(), 'Huisstijl aanpassen');
    });

    test('25 all 13 WebP assets exist, decode and preserve alpha', () async {
      expect(kBrandSignatureGoldAssetKeys, hasLength(13));
      for (final key in kBrandSignatureGoldAssetKeys) {
        final path = brandSignatureGoldAssetPath(key);
        final file = File(path);
        expect(await file.exists(), isTrue, reason: path);
        final bytes = await file.readAsBytes();
        final codec = await instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1254, reason: path);
        expect(frame.image.height, 1254, reason: path);
        final data = await frame.image.toByteData(
          format: ImageByteFormat.rawRgba,
        );
        expect(data, isNotNull);
        final alpha = data!.getUint8(3);
        expect(alpha, 0, reason: '$path corner alpha must be transparent');
        frame.image.dispose();
        codec.dispose();
      }
    });

    test('26 Brand color contrast safeguards work', () {
      final bad = sanitizeBrandSignaturePalette(
        const BrandSignaturePalette(
          header: Color(0xFF808080),
          page: Color(0xFF808080),
          card: Color(0xFF808080),
          accent: Color(0xFF808080),
        ),
      );
      final pageText = brandSignatureReadableTextOn(bad.page);
      final cardText = brandSignatureReadableTextOn(bad.card);
      expect(brandSignatureHasReadableText(pageText, bad.page), isTrue);
      expect(brandSignatureHasReadableText(cardText, bad.card), isTrue);
      expect(
        brandSignatureContrastRatio(
          brandSignatureReadableTextOn(bad.accent),
          bad.accent,
        ),
        greaterThanOrEqualTo(4.5),
      );
      final gold = paletteForBusinessTheme(
        BusinessThemeVariant.brandSignatureGold,
      );
      expect(
        brandSignatureContrastRatio(gold.textPrimary, gold.surface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  test('unknown legacy values keep the Executive Gold fallback', () async {
    final root = Directory(
      '${tempDir.path}${Platform.pathSeparator}business_state',
    );
    await root.create(recursive: true);
    final file = File(
      '${root.path}${Platform.pathSeparator}business_theme_v1.json',
    );
    await file.writeAsString(
      jsonEncode(<String, dynamic>{'variant': 'legacyIvoryOnly'}),
      flush: true,
    );
    await loadBusinessThemePreference();
    expect(businessThemeNotifier.value, BusinessThemeVariant.executiveGold);
  });

  test('restart does not restore an uncommitted preview', () async {
    await applyBusinessThemePreset(BusinessThemeVariant.corporateBlue);
    previewBusinessTheme(BusinessThemeVariant.brandSignatureGold);
    expect(isBusinessThemePreviewActive, isTrue);
    await loadBusinessThemePreference();
    expect(isBusinessThemePreviewActive, isFalse);
    expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
  });
}

void _setCompany(String companyId) {
  final now = DateTime.now().toUtc().toIso8601String();
  activeCompanySessionNotifier.value = ActiveCompanySession(
    companyId: companyId,
    role: 'companyAdmin',
    createdAt: now,
    lastUsedAt: now,
  );
}
