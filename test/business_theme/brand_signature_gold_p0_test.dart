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
import 'package:fluxidi_tracking/widgets/brand_signature_color_rail.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_style_dock.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';
import 'package:fluxidi_tracking/widgets/business_theme_root_canvas.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_theme_data.dart';
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
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    businessAppearanceNotifier.value = BusinessThemeVariant.executiveGold;
    brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
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
        expect(brandSignatureRailTitle(), isNotEmpty);
        expect(brandSignatureResetDefaultLabel(), isNotEmpty);
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
      expect(brandSignatureRailTitle(), 'Kies je achtergrondkleur');
      expect(brandSignatureResetDefaultLabel(), 'Standaard herstellen');
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
      for (final color in <Color>[
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
        const Color(0xFFFF2D00),
        const Color(0xFF00E5FF),
        kBrandSignatureDefaultBase,
      ]) {
        final derived = BrandSignaturePalette.fromColor(color);
        expect(derived.accent, kBrandSignatureGoldAccent);
        expect(
          brandSignatureHasReadableText(
            brandSignatureReadableTextOn(derived.page),
            derived.page,
          ),
          isTrue,
        );
        expect(
          brandSignatureHasReadableText(
            brandSignatureReadableTextOn(derived.card),
            derived.card,
          ),
          isTrue,
        );
        expect(
          brandSignatureHasReadableText(
            brandSignatureReadableTextOn(derived.kpi),
            derived.kpi,
          ),
          isTrue,
        );
      }
      final gold = paletteForBusinessTheme(
        BusinessThemeVariant.brandSignatureGold,
      );
      expect(
        brandSignatureContrastRatio(gold.textPrimary, gold.surface),
        greaterThanOrEqualTo(4.5),
      );
    });
  });

  group('Brand Signature full-spectrum studio', () {
    test('27 old four color rows are gone', () {
      expect(
        File('lib/widgets/brand_signature_palette_sheet.dart').existsSync(),
        isFalse,
      );
      final dock = File(
        'lib/widgets/brand_signature_style_dock.dart',
      ).readAsStringSync();
      final rail = File(
        'lib/widgets/brand_signature_color_rail.dart',
      ).readAsStringSync();
      expect(dock.contains('_headerChoices'), isFalse);
      expect(dock.contains('_pageChoices'), isFalse);
      expect(dock.contains('_cardChoices'), isFalse);
      expect(dock.contains('_accentChoices'), isFalse);
      expect(dock.contains('showModalBottomSheet'), isFalse);
      expect(rail.contains('kBrandSignatureColorRailKey'), isTrue);
      expect(rail.contains('kBrandSignatureSvFieldKey'), isTrue);
      expect(dock.contains('kBrandSignatureHexFieldKey'), isTrue);
    });

    test('28 one exact color derives the full background family', () {
      final white = BrandSignaturePalette.fromColor(const Color(0xFFFFFFFF));
      final black = BrandSignaturePalette.fromColor(const Color(0xFF000000));
      final red = BrandSignaturePalette.fromColor(const Color(0xFFFF0000));
      expect(white.familyId, 'white');
      expect(black.familyId, 'black');
      expect(red.familyId, 'red');
      expect(white.page, isNot(black.page));
      expect(white.header, isNot(red.header));
      expect(white.card, isNot(black.card));
      expect(white.accent, kBrandSignatureGoldAccent);
      expect(black.accent, kBrandSignatureGoldAccent);
      expect(red.accent, kBrandSignatureGoldAccent);
      expect(white.border, kBrandSignatureGoldBronze);
      expect(black.border, kBrandSignatureGoldAccent);
      expect(BrandSignaturePalette.defaults.base, kBrandSignatureDefaultBase);
    });

    testWidgets('29 editor is a bright dock with hue rail and SV field', (
      tester,
    ) async {
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessThemeRootCanvas(
            child: BrandSignatureStyleEditor(),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(kBrandSignatureStyleDockKey), findsOneWidget);
      expect(find.byKey(kBrandSignatureColorRailKey), findsOneWidget);
      expect(find.byKey(kBrandSignatureSvFieldKey), findsOneWidget);
      expect(find.text('Kies je achtergrondkleur'), findsOneWidget);
      expect(find.text('Header'), findsNothing);
      expect(find.text('Pagina'), findsNothing);
      expect(find.text('Kaarten'), findsNothing);
      expect(find.text('Accent'), findsNothing);
      _expectNoDarkScrim(tester);
      final rail = tester.getSize(find.byKey(kBrandSignatureColorRailKey));
      expect(rail.height, greaterThanOrEqualTo(48));
      expect(rail.width, greaterThan(600));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('30 hue rail and neutrals reach white black and vivid hues', (
      tester,
    ) async {
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandSignatureStyleDock())),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('brand_signature_neutral_white')));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.base, const Color(0xFFFFFFFF));
      await tester.tap(find.byKey(const Key('brand_signature_neutral_black')));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.base, const Color(0xFF000000));
      previewBrandSignatureColor(const Color(0xFFFF0000));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.familyId, 'red');
      previewBrandSignatureColor(const Color(0xFFFFFF00));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.familyId, 'yellow');
      previewBrandSignatureColor(const Color(0xFF00FF00));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.familyId, 'green');
      previewBrandSignatureColor(const Color(0xFF00FFFF));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.familyId, 'cyan');
      previewBrandSignatureColor(const Color(0xFF0000FF));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.familyId, 'blue');
      previewBrandSignatureColor(const Color(0xFFFF00FF));
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.familyId, 'magenta');
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('31 live chrome follows the chosen color without tinting icons', (
      tester,
    ) async {
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      brandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
        const Color(0xFFFF2D00),
      );
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      await tester.pumpWidget(
        const MaterialApp(
          home: BusinessThemeRootCanvas(
            child: _GoldTabletPreview(includeDock: true),
          ),
        ),
      );
      await tester.pump();
      final headerBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(kBrandSignatureGoldHeaderKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        (headerBox.decoration as BoxDecoration).color,
        BrandSignaturePalette.fromColor(const Color(0xFFFF2D00)).header,
      );
      expect(find.byKey(kBrandSignatureGoldLogoFallbackKey), findsOneWidget);
      final settingsCard = tester.widget<Ink>(
        find.descendant(
          of: find.byKey(const Key('brand_signature_action_settings')),
          matching: find.byType(Ink),
        ),
      );
      expect(
        (settingsCard.decoration as BoxDecoration).color,
        BrandSignaturePalette.fromColor(const Color(0xFFFF2D00)).card,
      );
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(const Key('brand_signature_action_settings')),
          matching: find.byType(Image),
        ),
      );
      expect(image.color, isNull);
      expect(image.colorBlendMode, isNull);
      await tester.binding.setSurfaceSize(null);
    });

    test('32 cancel restores the previously applied color', () async {
      _setCompany('co_style_cancel');
      await applyBrandSignaturePalette(
        BrandSignaturePalette.fromColor(const Color(0xFF000000)),
      );
      previewBrandSignatureColor(const Color(0xFFFFFFFF));
      expect(brandSignaturePaletteNotifier.value.familyId, 'white');
      cancelBrandSignaturePalettePreview();
      expect(brandSignaturePaletteNotifier.value.base, const Color(0xFF000000));
    });

    test('33 apply persists one exact color per company', () async {
      _setCompany('co_style_a');
      await applyBrandSignaturePalette(
        BrandSignaturePalette.fromColor(const Color(0xFFFFFFFF)),
      );
      _setCompany('co_style_b');
      syncBusinessThemeForActiveCompany();
      await applyBrandSignaturePalette(
        BrandSignaturePalette.fromColor(const Color(0xFFFF2D00)),
      );
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}business_state'
        '${Platform.pathSeparator}business_theme_v1.json',
      );
      final decoded = jsonDecode(await file.readAsString()) as Map;
      final palettes = decoded['brandSignaturePalettes'] as Map;
      expect((palettes['co_style_a'] as Map)['argb'], 0xFFFFFFFF);
      expect((palettes['co_style_b'] as Map)['argb'], 0xFFFF2D00);
      expect((palettes['co_style_a'] as Map).containsKey('header'), isFalse);
      _setCompany('co_style_a');
      syncBusinessThemeForActiveCompany();
      expect(brandSignaturePaletteNotifier.value.familyId, 'white');
    });

    test('34 restart restores the applied exact color', () async {
      _setCompany('co_style_restart');
      await applyBrandSignaturePalette(
        BrandSignaturePalette.fromColor(const Color(0xFF00E5FF)),
      );
      brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
      await loadBusinessThemePreference();
      expect(
        brandSignaturePaletteNotifier.value.base,
        const Color(0xFF00E5FF),
      );
    });

    test('35 reset default only previews warm gold-brown', () async {
      previewBrandSignatureColor(const Color(0xFFFFFFFF));
      previewBrandSignatureColor(kBrandSignatureDefaultBase);
      expect(
        brandSignaturePaletteNotifier.value.base,
        kBrandSignatureDefaultBase,
      );
    });

    test('36 legacy four-color JSON falls back to the default color', () {
      final restored = BrandSignaturePalette.fromJson(<String, int>{
        'header': 0xFF1A1408,
        'page': 0xFF0C0A07,
        'card': 0xFF1C160C,
        'accent': 0xFFD4AF37,
      });
      expect(restored.base, kBrandSignatureDefaultBase);
    });

    test('36b legacy rail position migrates to matching RGB', () {
      final migrated = BrandSignaturePalette.fromJson(<String, double>{
        'position': kBrandSignatureMidnightPosition,
      });
      expect(
        migrated.base,
        BrandSignaturePalette.fromPosition(
          kBrandSignatureMidnightPosition,
        ).base,
      );
    });

    testWidgets('37 customize closes the selector then opens the dock', (
      tester,
    ) async {
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      await tester.binding.setSurfaceSize(const Size(800, 1280));
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
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byKey(kBusinessThemeSelectorSheetKey), findsOneWidget);
      await tester.tap(find.byKey(kBrandSignatureCustomizeStyleKey));
      await tester.pumpAndSettle();
      expect(find.byKey(kBusinessThemeSelectorSheetKey), findsNothing);
      expect(find.byKey(kBrandSignatureStyleDockKey), findsOneWidget);
      _expectNoDarkScrim(tester);
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.brandSignatureGold,
      );
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('38 dock fits narrow and tablet widths', (tester) async {
      for (final size in <Size>[const Size(360, 780), const Size(800, 1280)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: BrandSignatureStyleDock())),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byKey(kBrandSignatureColorRailKey), findsOneWidget);
        expect(find.byKey(kBrandSignatureSvFieldKey), findsOneWidget);
      }
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('38b valid HEX previews and invalid HEX does not crash', (
      tester,
    ) async {
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BrandSignatureStyleDock())),
      );
      await tester.pump();
      await tester.enterText(find.byKey(kBrandSignatureHexFieldKey), '#00FF80');
      await tester.pump();
      expect(brandSignaturePaletteNotifier.value.hex, '#00FF80');
      await tester.enterText(find.byKey(kBrandSignatureHexFieldKey), 'ZZZZZZ');
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(brandSignaturePaletteNotifier.value.hex, '#00FF80');
      await tester.binding.setSurfaceSize(null);
    });

    test('39 exact colors render distinct tablet pages', () {
      final out = Directory('test_reports/brand_signature_huisstijl')
        ..createSync(recursive: true);
      final pages = <String, BrandSignaturePalette>{
        'white': BrandSignaturePalette.fromColor(const Color(0xFFFFFFFF)),
        'black': BrandSignaturePalette.fromColor(const Color(0xFF000000)),
        'vivid': BrandSignaturePalette.fromColor(const Color(0xFFFF2D00)),
      };
      for (final entry in pages.entries) {
        File(
          '${out.path}${Platform.pathSeparator}rail_${entry.key}.bmp',
        ).writeAsBytesSync(_tabletFamilyBmp(entry.value));
      }
      expect(pages['white']!.page, isNot(pages['black']!.page));
      expect(pages['black']!.page, isNot(pages['vivid']!.page));
      expect(pages['white']!.header, isNot(pages['vivid']!.header));
      expect(pages['white']!.card, isNot(pages['black']!.card));
      expect(pages['white']!.accent, kBrandSignatureGoldAccent);
      expect(pages['black']!.accent, kBrandSignatureGoldAccent);
      expect(pages['vivid']!.accent, kBrandSignatureGoldAccent);
    });
  });

  group('Brand Signature business-wide inheritance', () {
    test('40 white black and vivid Gold pages share one derived palette', () {
      for (final color in <Color>[
        const Color(0xFFFFFFFF),
        const Color(0xFF000000),
        const Color(0xFFFF2D00),
      ]) {
        brandSignaturePaletteNotifier.value =
            BrandSignaturePalette.fromColor(color);
        final palette = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        expect(palette.background, BrandSignaturePalette.fromColor(color).page);
        expect(palette.accent, kBrandSignatureGoldAccent);
        expect(palette.success, const Color(0xFF49B889));
        expect(palette.danger, const Color(0xFFD07A82));
        final theme = themeDataForBrandSignatureGold(palette);
        expect(theme.scaffoldBackgroundColor, palette.background);
        expect(theme.appBarTheme.backgroundColor, palette.surfaceAlt);
        expect(theme.dialogTheme.backgroundColor, palette.surface);
        expect(theme.cardTheme.color, palette.surface);
        expect(theme.colorScheme.error, palette.danger);
      }
    });

    test('41 Gold overlay stays inside the business shell only', () {
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      brandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
        const Color(0xFFFFFFFF),
      );
      expect(
        brandSignatureBusinessOverlayTheme(
          businessShellActive: true,
          chauffeurShellTheme: null,
          variant: BusinessThemeVariant.brandSignatureGold,
        )?.scaffoldBackgroundColor,
        BrandSignaturePalette.fromColor(const Color(0xFFFFFFFF)).page,
      );
      expect(
        brandSignatureBusinessOverlayTheme(
          businessShellActive: true,
          chauffeurShellTheme: DriverThemeVariant.nightGold,
          variant: BusinessThemeVariant.brandSignatureGold,
        ),
        isNull,
      );
      expect(
        brandSignatureBusinessOverlayTheme(
          businessShellActive: false,
          chauffeurShellTheme: null,
          variant: BusinessThemeVariant.brandSignatureGold,
        ),
        isNull,
      );
      expect(
        brandSignatureBusinessOverlayTheme(
          businessShellActive: true,
          chauffeurShellTheme: null,
          variant: BusinessThemeVariant.executiveGold,
        ),
        isNull,
      );
    });

    testWidgets('42 business routes inherit Gold without a default flash', (
      tester,
    ) async {
      businessThemeNotifier.value = BusinessThemeVariant.brandSignatureGold;
      brandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
        const Color(0xFFFFFFFF),
      );
      final overlay = brandSignatureBusinessOverlayTheme(
        businessShellActive: true,
        chauffeurShellTheme: null,
        variant: BusinessThemeVariant.brandSignatureGold,
      )!;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => Theme(data: overlay, child: child!),
          home: const Scaffold(body: Text('billing')),
        ),
      );
      await tester.pump();
      expect(
        Theme.of(tester.element(find.text('billing'))).scaffoldBackgroundColor,
        BrandSignaturePalette.fromColor(const Color(0xFFFFFFFF)).page,
      );
      brandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
        const Color(0xFF000000),
      );
      final next = themeDataForBrandSignatureGold(
        paletteForBusinessTheme(BusinessThemeVariant.brandSignatureGold),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          builder: (context, child) => Theme(data: next, child: child!),
          home: const Scaffold(body: Text('vehicles')),
        ),
      );
      await tester.pump();
      expect(
        Theme.of(tester.element(find.text('vehicles'))).scaffoldBackgroundColor,
        BrandSignaturePalette.fromColor(const Color(0xFF000000)).page,
      );
    });

    test('43 switching to an existing theme does not leak Gold', () {
      brandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
        const Color(0xFFFF2D00),
      );
      final executive = paletteForBusinessTheme(
        BusinessThemeVariant.executiveGold,
      );
      expect(executive.background, isNot(const Color(0xFFFF2D00)));
      expect(
        brandSignatureBusinessOverlayTheme(
          businessShellActive: true,
          chauffeurShellTheme: null,
          variant: BusinessThemeVariant.corporateBlue,
        ),
        isNull,
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

Uint8List _tabletFamilyBmp(BrandSignaturePalette colors) {
  const width = 400;
  const height = 640;
  const rowSize = width * 3;
  final pixels = Uint8List(rowSize * height);
  void put(int x, int y, Color color) {
    final i = (y * width + x) * 3;
    pixels[i] = color.blue;
    pixels[i + 1] = color.green;
    pixels[i + 2] = color.red;
  }

  void fillRect(int left, int top, int right, int bottom, Color color) {
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        put(x, y, color);
      }
    }
  }

  fillRect(0, 0, width, height, colors.page);
  fillRect(12, 12, width - 12, 110, colors.header);
  fillRect(12, 122, 104, 166, colors.kpi);
  fillRect(110, 122, 202, 166, colors.kpi);
  fillRect(208, 122, 300, 166, colors.kpi);
  fillRect(306, 122, 388, 166, colors.kpi);
  fillRect(12, 178, 194, 280, colors.card);
  fillRect(206, 178, 388, 280, colors.card);
  fillRect(8, 520, width - 8, 632, colors.kpi);
  final anchors = kBrandSignatureRailAnchors;
  for (var x = 20; x < width - 20; x++) {
    final t = (x - 20) / (width - 40);
    final stop = t * (anchors.length - 1);
    final index = stop.floor().clamp(0, anchors.length - 1);
    final next = (index + 1).clamp(0, anchors.length - 1);
    final color = Color.lerp(anchors[index], anchors[next], stop - index)!;
    for (var y = 554; y < 582; y++) {
      put(x, y, color);
    }
  }
  final fileSize = 54 + pixels.length;
  final bytes = Uint8List(fileSize);
  bytes[0] = 0x42;
  bytes[1] = 0x4D;
  bytes[2] = fileSize & 0xFF;
  bytes[3] = (fileSize >> 8) & 0xFF;
  bytes[4] = (fileSize >> 16) & 0xFF;
  bytes[5] = (fileSize >> 24) & 0xFF;
  bytes[10] = 54;
  bytes[14] = 40;
  bytes[18] = width & 0xFF;
  bytes[19] = (width >> 8) & 0xFF;
  bytes[22] = height & 0xFF;
  bytes[23] = (height >> 8) & 0xFF;
  bytes[26] = 1;
  bytes[28] = 24;
  bytes[34] = pixels.length & 0xFF;
  bytes[35] = (pixels.length >> 8) & 0xFF;
  bytes[36] = (pixels.length >> 16) & 0xFF;
  bytes[37] = (pixels.length >> 24) & 0xFF;
  var offset = 54;
  for (var y = height - 1; y >= 0; y--) {
    bytes.setRange(offset, offset + rowSize, pixels, y * rowSize);
    offset += rowSize;
  }
  return bytes;
}

void _expectNoDarkScrim(WidgetTester tester) {
  for (final barrier in tester.widgetList<ModalBarrier>(
    find.byType(ModalBarrier),
  )) {
    final color = barrier.color;
    expect(
      color == null || color.opacity == 0,
      isTrue,
      reason: 'huisstijl editor must not dim the dashboard',
    );
  }
}

class _GoldTabletPreview extends StatelessWidget {
  const _GoldTabletPreview({this.includeDock = false});

  final bool includeDock;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: brandSignaturePaletteNotifier,
      builder: (context, colors, _) {
        return RepaintBoundary(
          key: const Key('brand_signature_tablet_preview'),
          child: Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 220),
                children: [
                  const BrandSignatureGoldHeader(
                    height: 168,
                    logoRef: '',
                    hasCompanyLogo: false,
                    companyName: 'FLX',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      for (final label in <String>[
                        'Open',
                        'Ritten',
                        'Te betalen',
                        'Omzet',
                      ])
                        Expanded(
                          child: Container(
                            key: Key('brand_signature_preview_kpi_$label'),
                            margin: const EdgeInsets.only(right: 6),
                            height: 64,
                            decoration: BoxDecoration(
                              color: colors.kpi,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.border),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              label,
                              style: TextStyle(
                                color: brandSignatureReadableTextOn(
                                  colors.kpi,
                                ),
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SizedBox(
                    height: 168,
                    child: Row(
                      children: [
                        Expanded(
                          child: BrandSignatureGoldActionCard(
                            actionKey: 'settings',
                            title: 'Instellingen',
                            subtitle: 'Bedrijf',
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: BrandSignatureGoldActionCard(
                            actionKey: 'payments',
                            title: 'Betalingen',
                            subtitle: 'Abonnement',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (includeDock)
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: BrandSignatureStyleDock(),
                ),
            ],
          ),
        );
      },
    );
  }
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
