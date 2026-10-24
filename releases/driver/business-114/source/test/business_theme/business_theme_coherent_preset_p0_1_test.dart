// FLUXIDI-BUSINESS-THEME-COHERENT-PRESET-REPAIR-P0-1
//
// Field regression: the dashboard theme shortcut changed colors, cards and
// borders while Quick Actions artwork stayed on the previously selected pack, so
// Clean Professional could render Fluxy Neon Rush images. Cause: artwork was
// resolved from `businessAppearanceNotifier`, which the shortcut never advanced.
//
// These tests pin the repaired contract: one press applies one complete preset,
// colors and artwork always resolve from the same owner, and company-owned
// branding (uploaded logo, identity, KPI state) is untouched.
//
// Supersedes business_theme_shortcut_colors_only_p1_2_test.dart, whose
// colors-only expectation was the regression itself.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/business/business_dashboard_kpi_loading.dart';
import 'package:fluxidi_tracking/business_theme_cycle.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_preset.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/business_theme_system_ui.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';

/// Real Quick Actions artwork set (Settings card), one asset per preset.
String _settingsArtwork(
  BusinessThemeVariant preset,
) => businessThemePresetAsset(
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

/// Real Quick Actions artwork set (Bookings card), one asset per preset.
String _bookingsArtwork(
  BusinessThemeVariant preset,
) => businessThemePresetAsset(
  preset: preset,
  executiveGold: 'assets/fluxidi/bookings_background_company.webp',
  corporateBlue:
      'assets/Corporate BLEU Compagny/company_bookings_corporate_blue.webp',
  cleanProfessional:
      'assets/Clean & Professional Compagny/company_bookings_clean_professional.webp',
  emeraldIvory:
      'assets/Emerald_Ivory_Company/company_bookings_emerald_ivory.webp',
  fluxidiNeonRush:
      'assets/🥇 Fluxidi Neon Rush/company_bookings_neon_rush.webp',
);

/// Artwork for whatever preset is currently active, through the real owner.
String _activeSettingsArtwork() =>
    _settingsArtwork(activeBusinessThemePreset());

const BusinessDashboardKpiSnapshot _kpiSnapshot = BusinessDashboardKpiSnapshot(
  tenantId: 'fluxidi',
  companyId: 'fluxidi',
  openBookingsCount: 7,
  completedRidesCount: 42,
  unpaidCompletedRidesCount: 3,
  monthlyIncomeCents: 128450,
  currency: 'EUR',
  responseGeneration: 4,
);

({String logo, String company, String vat}) _brandingSnapshot() {
  final settings = businessSettingsNotifier.value;
  return (
    logo: settings.logoAssetPath,
    company: settings.companyName,
    vat: settings.vatCompanyNumber,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BusinessSettingsState settingsBefore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'fluxidi_biz_theme_preset_',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    resetBusinessThemePersistenceLatchForTest();
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    businessAppearanceNotifier.value = BusinessThemeVariant.executiveGold;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
    settingsBefore = businessSettingsNotifier.value;
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    businessSettingsNotifier.value = settingsBefore;
    resetBusinessThemePersistenceLatchForTest();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('each preset pairs its own colors with its own artwork', () {
    // Tests 1-5.
    final expectations =
        <BusinessThemeVariant, ({String label, String marker})>{
          BusinessThemeVariant.executiveGold: (
            label: 'Executive Gold',
            marker: 'assets/fluxidi/',
          ),
          BusinessThemeVariant.corporateBlue: (
            label: 'Corporate Blue',
            marker: 'corporate_blue',
          ),
          BusinessThemeVariant.cleanProfessional: (
            label: 'Clean Professional',
            marker: 'clean_professional',
          ),
          BusinessThemeVariant.emeraldIvory: (
            label: 'Emerald Ivory',
            marker: 'emerald_ivory',
          ),
          BusinessThemeVariant.fluxidiNeonRush: (
            label: 'Fluxy Neon Rush',
            marker: 'neon_rush',
          ),
        };

    expectations.forEach((preset, expected) {
      test('${expected.label} colors and artwork match', () async {
        await applyBusinessThemePreset(preset);

        expect(businessThemeProductLabel(preset), expected.label);
        expect(
          paletteForBusinessTheme(businessThemeNotifier.value),
          same(paletteForBusinessTheme(preset)),
        );

        for (final asset in <String>[
          _activeSettingsArtwork(),
          _bookingsArtwork(activeBusinessThemePreset()),
        ]) {
          expect(
            asset.toLowerCase(),
            contains(expected.marker.toLowerCase()),
            reason: '$preset artwork must come from its own pack',
          );
          expect(
            businessThemeAssetMatchesPreset(asset: asset, preset: preset),
            isTrue,
          );
        }
      });
    });

    // Test 7.
    test('no preset ever retains the previous preset artwork', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.fluxidiNeonRush);
      expect(_activeSettingsArtwork(), contains('neon_rush'));

      for (final preset in <BusinessThemeVariant>[
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
      ]) {
        await applyBusinessThemePreset(preset);
        final asset = _activeSettingsArtwork();
        expect(
          asset.toLowerCase(),
          isNot(contains('neon_rush')),
          reason: '$preset must not keep Neon Rush artwork',
        );
        expect(
          businessThemeAssetMatchesPreset(asset: asset, preset: preset),
          isTrue,
        );
      }
    });

    test('every preset resolves a distinct artwork asset', () {
      final assets = <String>{
        for (final preset in BusinessThemeVariant.values)
          _settingsArtwork(preset),
      };
      expect(assets.length, BusinessThemeVariant.values.length);
    });
  });

  group('cycle order and atomicity', () {
    // Test 6.
    test('five presses wrap back to Executive Gold', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.executiveGold);
      final seen = <BusinessThemeVariant>[];
      for (var i = 0; i < 6; i++) {
        seen.add(await cycleBusinessThemePreference());
      }
      expect(seen, <BusinessThemeVariant>[
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
        BusinessThemeVariant.brandSignatureGold,
        BusinessThemeVariant.executiveGold,
      ]);
      expect(seen.toSet().length, 6, reason: 'no duplicate or hidden state');
      expect(
        kBusinessThemeCycleOrder.toSet(),
        BusinessThemeVariant.values.toSet(),
      );
    });

    // Test 8.
    test('a switch is atomic: no await can observe a mixed preset', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.executiveGold);
      final pending = applyBusinessThemePreset(
        BusinessThemeVariant.cleanProfessional,
      );
      // Synchronously after the call, before the future completes.
      expect(businessThemeNotifier.value, businessAppearanceNotifier.value);
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );
      expect(
        _activeSettingsArtwork(),
        contains('clean_professional'),
        reason: 'artwork must already follow the new preset',
      );
      await pending;
      expect(businessThemeNotifier.value, businessAppearanceNotifier.value);
    });

    // Test 9.
    test('rapid presses cannot desynchronise colors and artwork', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.executiveGold);
      final futures = <Future<BusinessThemeVariant>>[];
      final observed = <bool>[];
      for (var i = 0; i < 6; i++) {
        futures.add(cycleBusinessThemePreference());
        observed.add(
          businessThemeNotifier.value == businessAppearanceNotifier.value,
        );
      }
      await Future.wait(futures);

      expect(observed, everyElement(isTrue));
      expect(businessThemeNotifier.value, businessAppearanceNotifier.value);
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.executiveGold,
        reason: 'six rapid presses complete one full cycle',
      );
      expect(
        businessThemeAssetMatchesPreset(
          asset: _activeSettingsArtwork(),
          preset: businessThemeNotifier.value,
        ),
        isTrue,
      );

      // Persistence converges on the preset the user ended on.
      for (final fileName in <String>[
        'business_theme_v1.json',
        'business_appearance_v1.json',
      ]) {
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}business_state'
          '${Platform.pathSeparator}$fileName',
        );
        final decoded = jsonDecode(await file.readAsString()) as Map;
        expect(decoded['variant'], 'executiveGold', reason: fileName);
      }
    });

    // Test 13.
    test('shortcut and settings selector share one preset owner', () async {
      await saveBusinessThemeAndAppearancePreset(
        BusinessThemeVariant.emeraldIvory,
      );
      expect(businessThemeNotifier.value, BusinessThemeVariant.emeraldIvory);
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.emeraldIvory,
      );
      expect(_activeSettingsArtwork(), contains('emerald_ivory'));

      // The shortcut continues from the settings selection.
      final next = await cycleBusinessThemePreference();
      expect(next, BusinessThemeVariant.fluxidiNeonRush);
      expect(businessAppearanceNotifier.value, next);
      expect(_activeSettingsArtwork(), contains('neon_rush'));
    });

    test('legacy single-owner savers now apply the complete preset', () async {
      await saveBusinessThemePreference(BusinessThemeVariant.corporateBlue);
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.corporateBlue,
      );
      expect(_activeSettingsArtwork(), contains('corporate_blue'));

      await saveBusinessAppearancePreference(
        BusinessThemeVariant.cleanProfessional,
      );
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
        reason: 'artwork is not separately selectable any more',
      );
    });
  });

  group('persistence and lifecycle', () {
    // Test 10.
    test('restart restores both colors and artwork', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.cleanProfessional);
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      businessAppearanceNotifier.value = BusinessThemeVariant.fluxidiNeonRush;

      await loadBusinessThemePreference();
      await loadBusinessAppearancePreference();

      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );
      expect(_activeSettingsArtwork(), contains('clean_professional'));
    });

    test('a legacy split artwork file cannot resurrect stale artwork', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.emeraldIvory);
      // Simulate the pre-repair state: appearance file left on another preset.
      final appearanceFile = File(
        '${tempDir.path}${Platform.pathSeparator}business_state'
        '${Platform.pathSeparator}business_appearance_v1.json',
      );
      await appearanceFile.writeAsString(
        jsonEncode(<String, dynamic>{'variant': 'fluxidiNeonRush'}),
        flush: true,
      );

      await loadBusinessThemePreference();
      await loadBusinessAppearancePreference();

      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.emeraldIvory,
      );
      expect(_activeSettingsArtwork(), contains('emerald_ivory'));
      // The legacy file is healed on disk, not just in memory.
      final healed = jsonDecode(await appearanceFile.readAsString()) as Map;
      expect(healed['variant'], 'emeraldIvory');
    });

    // Test 11.
    testWidgets('pause/resume preserves colors, artwork and overlay', (
      tester,
    ) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.cleanProfessional),
      );
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BusinessThemeCycleButton())),
      );

      for (final state in <AppLifecycleState>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
      }
      // Business Home re-applies the overlay for the active palette on resume.
      applyBusinessThemeSystemUiOverlay(
        paletteForBusinessTheme(businessThemeNotifier.value),
      );

      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );
      expect(businessAppearanceNotifier.value, businessThemeNotifier.value);
      expect(_activeSettingsArtwork(), contains('clean_professional'));
      expect(
        systemUiOverlayStyleForBusinessTheme(
          paletteForBusinessTheme(businessThemeNotifier.value),
        ).statusBarIconBrightness,
        Brightness.dark,
      );
    });

    // Test 12.
    testWidgets('navigating away and back preserves the complete preset', (
      tester,
    ) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.corporateBlue),
      );
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: BusinessThemeCycleButton()),
        ),
      );

      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pumpAndSettle();
      final afterPress = businessThemeNotifier.value;
      expect(afterPress, BusinessThemeVariant.cleanProfessional);

      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other page')),
        ),
      );
      await tester.pumpAndSettle();
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      expect(businessThemeNotifier.value, afterPress);
      expect(businessAppearanceNotifier.value, afterPress);
      expect(_activeSettingsArtwork(), contains('clean_professional'));
    });
  });

  group('company-owned branding and data stay untouched', () {
    // Tests 14 + 15.
    test('uploaded logo and company identity survive all five presets', () async {
      const uploadedLogo =
          '/data/user/0/com.fluxidi.tracking/app_flutter/tenant_state/company_logo/logo.png';
      businessSettingsNotifier.value = settingsBefore.copyWith(
        companyName: 'Wakanda Wotan BVBA',
        address: 'Kortrijksesteenweg 12, Deinze',
        vatCompanyNumber: 'BE0123456789',
        logoAssetPath: uploadedLogo,
      );
      final before = _brandingSnapshot();

      for (var i = 0; i < 5; i++) {
        await cycleBusinessThemePreference();
        expect(_brandingSnapshot(), before, reason: 'press ${i + 1}');
        expect(businessSettingsNotifier.value.logoAssetPath, uploadedLogo);
        expect(
          businessSettingsNotifier.value.logoAssetPath,
          isNot(contains('fluxidi_logo.png')),
          reason: 'the theme shortcut must not fall back to the Fluxidi logo',
        );
      }
      expect(
        businessSettingsNotifier.value.pricingVatRate,
        settingsBefore.pricingVatRate,
      );
    });

    // Test 16.
    test(
      'KPI values and loading state are unaffected by preset changes',
      () async {
        BusinessDashboardKpiView view() => resolveBusinessDashboardKpiView(
          lastSuccessfulForActiveScope: _kpiSnapshot,
          requestInFlight: true,
          lastRequestFailed: false,
        );
        final before = view();

        for (var i = 0; i < 5; i++) {
          await cycleBusinessThemePreference();
          final after = view();
          expect(after.phase, before.phase);
          expect(after.showRefreshIndicator, before.showRefreshIndicator);
          expect(after.showRetry, before.showRetry);
          expect(after.snapshot?.openBookingsCount, 7);
          expect(after.snapshot?.completedRidesCount, 42);
          expect(after.snapshot?.monthlyIncomeCents, 128450);
          expect(after.snapshot?.currency, 'EUR');
        }
      },
    );

    test('theme sources never reference company branding or KPI owners', () {
      for (final path in <String>[
        'lib/business_theme_store.dart',
        'lib/business_theme_cycle.dart',
        'lib/business_theme_preset.dart',
        'lib/widgets/business_theme_cycle_button.dart',
      ]) {
        final src = File(path).readAsStringSync().toLowerCase();
        // Symbol references, not prose: the doc comments legitimately name what
        // these files must never touch.
        for (final symbol in <String>[
          'logoassetpath',
          'businesssettingsnotifier',
          'kfluxidilogoasset',
          'businessdashboardkpi',
          'updatebusinesssettings',
          'mapbox',
          'mapstyle',
        ]) {
          expect(src.contains(symbol), isFalse, reason: '$path -> $symbol');
        }
      }
    });

    test(
      'customer presentation is untouched by a business preset change',
      () async {
        customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
        businessPublishedCustomerThemeNotifier.value =
            CustomerThemeVariant.premiumLight;
        await cycleBusinessThemePreference();
        expect(customerThemeNotifier.value, CustomerThemeVariant.premiumLight);
        expect(
          businessPublishedCustomerThemeNotifier.value,
          CustomerThemeVariant.premiumLight,
        );
      },
    );
  });

  group('system overlay follows the complete preset', () {
    // Test 17.
    test('Clean Professional uses dark status-bar icons', () {
      final style = systemUiOverlayStyleForBusinessTheme(
        paletteForBusinessTheme(BusinessThemeVariant.cleanProfessional),
      );
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
    });

    // Test 18.
    test('dark presets use light status-bar icons', () {
      for (final preset in <BusinessThemeVariant>[
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
      ]) {
        final style = systemUiOverlayStyleForBusinessTheme(
          paletteForBusinessTheme(preset),
        );
        expect(
          style.statusBarIconBrightness,
          Brightness.light,
          reason: '$preset',
        );
        expect(style.statusBarBrightness, Brightness.dark, reason: '$preset');
      }
    });

    test('the overlay style changes with every press of the cycle', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.executiveGold);
      final brightnesses = <Brightness?>[];
      for (var i = 0; i < 5; i++) {
        await cycleBusinessThemePreference();
        brightnesses.add(
          systemUiOverlayStyleForBusinessTheme(
            paletteForBusinessTheme(businessThemeNotifier.value),
          ).statusBarIconBrightness,
        );
      }
      // Clean Professional is the light preset; it is the third press.
      expect(brightnesses[1], Brightness.dark);
      expect(brightnesses.where((b) => b == Brightness.light).length, 4);
    });
  });

  group('layouts', () {
    Future<void> pumpHeader(
      WidgetTester tester, {
      required Size size,
      required BusinessHomeHeaderThemeMode mode,
      double? headerHeight,
    }) async {
      final palette = paletteForBusinessTheme(businessThemeNotifier.value);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  BusinessHomeHeaderThemeRegion(
                    mode: mode,
                    fixedHeight: headerHeight,
                    topBar: const SizedBox(
                      key: BusinessHomeHeaderThemeRegion.companyChipKey,
                      height: 28,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text('company'),
                      ),
                    ),
                    greeting: 'Goedemorgen',
                    subtitle: 'Bedrijfsoverzicht',
                    greetingStyle: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                    subtitleStyle: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12.5,
                    ),
                    heroBackground: mode == BusinessHomeHeaderThemeMode.hero
                        ? const ColoredBox(color: Color(0xFF101010))
                        : null,
                    heroDecoration: BoxDecoration(
                      color: palette.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  Container(
                    key: BusinessHomeHeaderThemeRegion.kpiSlotKey,
                    height: 72,
                    color: palette.surfaceAlt,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // Test 19.
    testWidgets('phone portrait and landscape cycle the complete preset', (
      tester,
    ) async {
      for (final size in <Size>[Size(390, 844), Size(844, 390)]) {
        await tester.runAsync(
          () => applyBusinessThemePreset(BusinessThemeVariant.executiveGold),
        );
        await pumpHeader(
          tester,
          size: size,
          mode: BusinessHomeHeaderThemeMode.panel,
        );
        expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);

        await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
        await tester.pumpAndSettle();

        expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
        expect(businessAppearanceNotifier.value, businessThemeNotifier.value);
        expect(_activeSettingsArtwork(), contains('corporate_blue'));
        expect(find.byType(SnackBar), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
      }
    });

    // Test 20.
    testWidgets('tablet portrait and landscape cycle the complete preset', (
      tester,
    ) async {
      for (final layout in <({Size size, double height})>[
        (size: Size(800, 1280), height: 320),
        (size: Size(1280, 800), height: 160),
      ]) {
        await tester.runAsync(
          () => applyBusinessThemePreset(BusinessThemeVariant.emeraldIvory),
        );
        await pumpHeader(
          tester,
          size: layout.size,
          mode: BusinessHomeHeaderThemeMode.hero,
          headerHeight: layout.height,
        );
        expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);

        // Control stays above the KPI slot.
        final button = tester.getRect(
          find.byKey(BusinessThemeCycleButton.buttonKey),
        );
        final kpi = tester.getRect(
          find.byKey(BusinessHomeHeaderThemeRegion.kpiSlotKey),
        );
        expect(button.bottom <= kpi.top + 0.5, isTrue);

        await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
        await tester.pumpAndSettle();

        expect(
          businessThemeNotifier.value,
          BusinessThemeVariant.fluxidiNeonRush,
        );
        expect(businessAppearanceNotifier.value, businessThemeNotifier.value);
        expect(_activeSettingsArtwork(), contains('neon_rush'));
      }
    });

    testWidgets('the notifier identity is never replaced by a press', (
      tester,
    ) async {
      final beforeTheme = businessThemeNotifier;
      final beforeAppearance = businessAppearanceNotifier;
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BusinessThemeCycleButton())),
      );
      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pumpAndSettle();
      expect(identical(beforeTheme, businessThemeNotifier), isTrue);
      expect(identical(beforeAppearance, businessAppearanceNotifier), isTrue);
    });
  });

  group('production wiring', () {
    test('home artwork resolves from the canonical preset owner', () {
      final home = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(home.contains('businessThemePresetAsset('), isTrue);
      expect(home.contains('preset: activeBusinessThemePreset()'), isTrue);
      expect(
        home.contains('switch (businessAppearanceNotifier.value)'),
        isFalse,
        reason: 'artwork must not read the legacy appearance owner',
      );
      // Root Scaffold / status-bar chrome live in BusinessThemeRootCanvas so the
      // navy page gradient rebuilds with the same preset as cards/artwork.
      expect(home.contains('BusinessThemeRootCanvas('), isTrue);
      expect(
        home.contains(
          'applyBusinessThemeSystemUiOverlay(_businessThemePalette)',
        ),
        isTrue,
      );
      final rootCanvas = File(
        'lib/widgets/business_theme_root_canvas.dart',
      ).readAsStringSync();
      expect(
        rootCanvas.contains('AnnotatedRegion<SystemUiOverlayStyle>'),
        isTrue,
      );
    });

    test('shortcut and settings both call the canonical preset apply', () {
      final button = File(
        'lib/widgets/business_theme_cycle_button.dart',
      ).readAsStringSync();
      expect(button.contains('applyBusinessThemePreset(next)'), isTrue);

      final page = File('lib/business_theme_page.dart').readAsStringSync();
      expect(
        page.contains('saveBusinessThemeAndAppearancePreset(variant)'),
        isTrue,
      );
      final store = File('lib/business_theme_store.dart').readAsStringSync();
      expect(
        store.contains(
          'Future<void> saveBusinessThemeAndAppearancePreset(\n'
          '  BusinessThemeVariant variant,\n'
          ') => applyBusinessThemePreset(variant);',
        ),
        isTrue,
        reason: 'settings must route through the one canonical apply',
      );
    });

    test('the appearance notifier is documented as a mirror, not an owner', () {
      final store = File('lib/business_theme_store.dart').readAsStringSync();
      final declIndex = store.indexOf(
        'final ValueNotifier<BusinessThemeVariant> businessAppearanceNotifier',
      );
      expect(declIndex, greaterThan(-1));
      final doc = store.substring(0, declIndex).toLowerCase();
      expect(doc.contains('compatibility mirror'), isTrue);
      expect(
        store.contains('BusinessThemeVariant activeBusinessThemePreset()'),
        isTrue,
      );
    });
  });
}
