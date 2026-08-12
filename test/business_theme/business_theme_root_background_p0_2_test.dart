// FLUXIDI-BUSINESS-THEME-ROOT-BACKGROUND-OWNER-P0-2
//
// Field regression after e6c5941: cards, borders, accents, typography and Quick
// Actions artwork switched with the complete preset, but the Business Home
// Scaffold / page gradient stayed on hardcoded Corporate Blue navy because those
// layers were built outside the businessThemeNotifier listenable.
//
// These tests pin the repaired contract: the same canonical preset that owns
// cards and artwork also owns the root canvas on every press, settings change,
// restart, pause/resume and navigate-away/back — without touching company logo
// or KPI state.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/business/business_dashboard_kpi_loading.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_preset.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/business_theme_system_ui.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';
import 'package:fluxidi_tracking/widgets/business_theme_root_canvas.dart';

String _settingsArtwork(BusinessThemeVariant preset) => businessThemePresetAsset(
  preset: preset,
  executiveGold: 'assets/fluxidi/settings_background_company.webp',
  corporateBlue:
      'assets/Corporate BLEU Compagny/company_settings_corporate_blue.webp',
  cleanProfessional:
      'assets/Clean & Professional Compagny/company_settings_clean_professional.webp',
  emeraldIvory:
      'assets/Emerald_Ivory_Company/company_settings_alt_emerald_ivory.webp',
  fluxidiNeonRush: 'assets/🥇 Fluxidi Neon Rush/company_settings_neon_rush.webp',
);

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

({Color scaffold, List<Color> gradient, Color accent, String artwork})
_rootSnapshot(BusinessThemeVariant preset) {
  return (
    scaffold: businessThemeRootBackground(preset),
    gradient: businessThemeRootGradientColors(preset),
    accent: paletteForBusinessTheme(preset).accent,
    artwork: _settingsArtwork(preset),
  );
}

/// Card/artwork probes that rebuild with the same notifier as the root canvas.
class _LiveThemeProbes extends StatelessWidget {
  const _LiveThemeProbes();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessThemeVariant>(
      valueListenable: businessThemeNotifier,
      builder: (context, _, __) {
        final preset = activeBusinessThemePreset();
        return Column(
          children: [
            const BusinessThemeCycleButton(),
            ColoredBox(
              key: const ValueKey<String>('card_surface_probe'),
              color: paletteForBusinessTheme(preset).surface,
              child: const SizedBox(height: 48, width: double.infinity),
            ),
            Text(
              key: const ValueKey<String>('artwork_probe'),
              _settingsArtwork(preset),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _pumpRootCanvas(
  WidgetTester tester, {
  required Size size,
  Widget? child,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: BusinessThemeRootCanvas(
          child: child ?? const _LiveThemeProbes(),
        ),
      ),
    ),
  );
  await tester.pump();
}

Scaffold _scaffoldUnderTest(WidgetTester tester) {
  return tester.widget<Scaffold>(
    find.byKey(BusinessThemeRootCanvas.scaffoldKey),
  );
}

DecoratedBox _gradientUnderTest(WidgetTester tester) {
  return tester.widget<DecoratedBox>(
    find.byKey(BusinessThemeRootCanvas.gradientKey),
  );
}

List<Color> _gradientColors(DecoratedBox box) {
  final decoration = box.decoration as BoxDecoration;
  final gradient = decoration.gradient! as LinearGradient;
  return gradient.colors;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late BusinessSettingsState settingsBefore;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'fluxidi_biz_theme_root_bg_',
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
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('canonical root mapping for all five presets', () {
    final expectations = <BusinessThemeVariant, ({
      String label,
      Color background,
      Color surfaceAlt,
      String artworkMarker,
    })>{
      BusinessThemeVariant.executiveGold: (
        label: 'Executive Gold',
        background: const Color(0xFF07080C),
        surfaceAlt: const Color(0xFF16120A),
        artworkMarker: 'assets/fluxidi/',
      ),
      BusinessThemeVariant.corporateBlue: (
        label: 'Corporate Blue',
        background: const Color(0xFF0B1020),
        surfaceAlt: const Color(0xFF1A2437),
        artworkMarker: 'corporate_blue',
      ),
      BusinessThemeVariant.cleanProfessional: (
        label: 'Clean Professional',
        background: const Color(0xFFF4F6FA),
        surfaceAlt: const Color(0xFFEFF2F8),
        artworkMarker: 'clean_professional',
      ),
      BusinessThemeVariant.emeraldIvory: (
        label: 'Emerald Ivory',
        background: const Color(0xFF081411),
        surfaceAlt: const Color(0xFF1A2E27),
        artworkMarker: 'emerald_ivory',
      ),
      BusinessThemeVariant.fluxidiNeonRush: (
        label: 'Fluxy Neon Rush',
        background: const Color(0xFF0A0716),
        surfaceAlt: const Color(0xFF1B1437),
        artworkMarker: 'neon_rush',
      ),
    };

    // Tests 1-5.
    expectations.forEach((preset, expected) {
      testWidgets(
        '${expected.label} root background matches ${expected.label}',
        (tester) async {
          await tester.runAsync(() => applyBusinessThemePreset(preset));
          await _pumpRootCanvas(tester, size: const Size(390, 844));

          final scaffold = _scaffoldUnderTest(tester);
          final gradient = _gradientColors(_gradientUnderTest(tester));
          final palette = paletteForBusinessTheme(preset);

          expect(scaffold.backgroundColor, expected.background);
          expect(scaffold.backgroundColor, palette.background);
          expect(gradient, <Color>[
            expected.background,
            expected.background,
            expected.surfaceAlt,
          ]);
          expect(
            _settingsArtwork(activeBusinessThemePreset()).toLowerCase(),
            contains(expected.artworkMarker.toLowerCase()),
          );
        },
      );
    });

    // Test 6.
    testWidgets(
      'no non-blue preset contains the Corporate Blue root gradient/color',
      (tester) async {
        final corporate = _rootSnapshot(BusinessThemeVariant.corporateBlue);
        for (final preset in <BusinessThemeVariant>[
          BusinessThemeVariant.executiveGold,
          BusinessThemeVariant.cleanProfessional,
          BusinessThemeVariant.emeraldIvory,
          BusinessThemeVariant.fluxidiNeonRush,
        ]) {
          await tester.runAsync(() => applyBusinessThemePreset(preset));
          await _pumpRootCanvas(tester, size: const Size(390, 844));

          final scaffold = _scaffoldUnderTest(tester).backgroundColor!;
          final gradient = _gradientColors(_gradientUnderTest(tester));

          expect(scaffold, isNot(corporate.scaffold), reason: '$preset');
          expect(scaffold, isNot(const Color(0xFF0A1324)), reason: '$preset');
          expect(scaffold, isNot(const Color(0xFF13213A)), reason: '$preset');
          for (final color in gradient) {
            expect(isForbiddenCorporateBlueRootColor(color), isFalse,
                reason: '$preset gradient $color');
            expect(color, isNot(corporate.scaffold), reason: '$preset');
          }
          expect(
            gradient,
            isNot(corporate.gradient),
            reason: '$preset must not keep the Corporate Blue gradient',
          );
        }
      },
    );
  });

  group('same-frame ownership with cards and artwork', () {
    // Test 7.
    testWidgets('root background changes in the same frame as cards and artwork',
        (tester) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.corporateBlue),
      );
      await _pumpRootCanvas(tester, size: const Size(390, 844));

      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.fluxidiNeonRush),
      );
      // One pump — not pumpAndSettle — proves same-frame ownership.
      await tester.pump();

      final neon = paletteForBusinessTheme(BusinessThemeVariant.fluxidiNeonRush);
      expect(
        _scaffoldUnderTest(tester).backgroundColor,
        neon.background,
      );
      expect(
        _gradientColors(_gradientUnderTest(tester)).first,
        neon.background,
      );
      expect(
        tester.widget<ColoredBox>(
          find.byKey(const ValueKey<String>('card_surface_probe')),
        ).color,
        neon.surface,
      );
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('artwork_probe')),
        ).data,
        contains('neon_rush'),
      );
    });

    // Test 8.
    testWidgets('rapid presses cannot leave root background behind', (
      tester,
    ) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.executiveGold),
      );
      await _pumpRootCanvas(tester, size: const Size(390, 844));

      // Start and await all cycles inside runAsync so path_provider I/O is not
      // stranded on the test zone (plain Future.wait outside can hang).
      await tester.runAsync(() async {
        final futures = <Future<BusinessThemeVariant>>[
          for (var i = 0; i < 5; i++) cycleBusinessThemePreference(),
        ];
        await Future.wait(futures);
      });
      await tester.pump();

      final preset = activeBusinessThemePreset();
      expect(preset, BusinessThemeVariant.executiveGold);
      final expected = _rootSnapshot(preset);
      expect(_scaffoldUnderTest(tester).backgroundColor, expected.scaffold);
      expect(_gradientColors(_gradientUnderTest(tester)), expected.gradient);
      expect(
        tester.widget<ColoredBox>(
          find.byKey(const ValueKey<String>('card_surface_probe')),
        ).color,
        paletteForBusinessTheme(preset).surface,
      );
      expect(
        businessThemeAssetMatchesPreset(
          asset: tester
              .widget<Text>(
                find.byKey(const ValueKey<String>('artwork_probe')),
              )
              .data!,
          preset: preset,
        ),
        isTrue,
      );
    });

    // Test 9.
    testWidgets('settings theme selection changes root background too', (
      tester,
    ) async {
      await _pumpRootCanvas(tester, size: const Size(390, 844));
      await tester.runAsync(
        () => saveBusinessThemeAndAppearancePreset(
          BusinessThemeVariant.emeraldIvory,
        ),
      );
      await tester.pump();

      final emerald =
          paletteForBusinessTheme(BusinessThemeVariant.emeraldIvory);
      expect(_scaffoldUnderTest(tester).backgroundColor, emerald.background);
      expect(
        _gradientColors(_gradientUnderTest(tester)).last,
        emerald.surfaceAlt,
      );
      expect(businessAppearanceNotifier.value, businessThemeNotifier.value);
    });
  });

  group('persistence and lifecycle restore the complete root canvas', () {
    // Test 10.
    testWidgets('restart restores the complete root/card/artwork preset', (
      tester,
    ) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.cleanProfessional),
      );
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      businessAppearanceNotifier.value = BusinessThemeVariant.fluxidiNeonRush;

      await tester.runAsync(() async {
        await loadBusinessThemePreference();
        await loadBusinessAppearancePreference();
      });
      await _pumpRootCanvas(tester, size: const Size(390, 844));

      final clean =
          paletteForBusinessTheme(BusinessThemeVariant.cleanProfessional);
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );
      expect(_scaffoldUnderTest(tester).backgroundColor, clean.background);
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('artwork_probe')),
        ).data,
        contains('clean_professional'),
      );
    });

    // Test 11.
    testWidgets('pause/resume restores the complete root canvas', (tester) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.fluxidiNeonRush),
      );
      await _pumpRootCanvas(tester, size: const Size(390, 844));

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
      applyBusinessThemeSystemUiOverlay(
        paletteForBusinessTheme(businessThemeNotifier.value),
      );

      final neon =
          paletteForBusinessTheme(BusinessThemeVariant.fluxidiNeonRush);
      expect(_scaffoldUnderTest(tester).backgroundColor, neon.background);
      expect(
        _gradientColors(_gradientUnderTest(tester)),
        businessThemeRootGradientColors(BusinessThemeVariant.fluxidiNeonRush),
      );
    });

    // Test 12.
    testWidgets('navigate away/back restores the complete root canvas', (
      tester,
    ) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.corporateBlue),
      );
      final navKey = GlobalKey<NavigatorState>();
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const BusinessThemeRootCanvas(
            child: _LiveThemeProbes(),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pumpAndSettle();
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );

      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other page')),
        ),
      );
      await tester.pumpAndSettle();
      navKey.currentState!.pop();
      await tester.pumpAndSettle();

      final clean =
          paletteForBusinessTheme(BusinessThemeVariant.cleanProfessional);
      expect(_scaffoldUnderTest(tester).backgroundColor, clean.background);
      expect(
        tester.widget<Text>(
          find.byKey(const ValueKey<String>('artwork_probe')),
        ).data,
        contains('clean_professional'),
      );
    });
  });

  group('company-owned branding and KPI state stay untouched', () {
    // Test 13.
    test('company logo remains unchanged across root-canvas switches', () async {
      const uploadedLogo =
          '/data/user/0/com.fluxidi.tracking/app_flutter/tenant_state/company_logo/logo.png';
      businessSettingsNotifier.value = settingsBefore.copyWith(
        companyName: 'Wakanda Wotan BVBA',
        vatCompanyNumber: 'BE0123456789',
        logoAssetPath: uploadedLogo,
      );

      for (final preset in BusinessThemeVariant.values) {
        await applyBusinessThemePreset(preset);
        expect(businessSettingsNotifier.value.logoAssetPath, uploadedLogo);
        expect(businessSettingsNotifier.value.companyName, 'Wakanda Wotan BVBA');
      }
    });

    // Test 14.
    test('KPI state remains unchanged across root-canvas switches', () async {
      BusinessDashboardKpiView view() => resolveBusinessDashboardKpiView(
        lastSuccessfulForActiveScope: _kpiSnapshot,
        requestInFlight: true,
        lastRequestFailed: false,
      );
      final before = view();
      for (final preset in BusinessThemeVariant.values) {
        await applyBusinessThemePreset(preset);
        final after = view();
        expect(after.phase, before.phase);
        expect(after.snapshot?.openBookingsCount, 7);
        expect(after.snapshot?.monthlyIncomeCents, 128450);
      }
    });
  });

  group('layouts and system overlay', () {
    // Tests 15-16.
    testWidgets('phone portrait and landscape update the root canvas', (
      tester,
    ) async {
      for (final size in <Size>[const Size(390, 844), const Size(844, 390)]) {
        await tester.runAsync(
          () => applyBusinessThemePreset(BusinessThemeVariant.executiveGold),
        );
        await _pumpRootCanvas(tester, size: size);
        await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
        await tester.pumpAndSettle();

        final corporate =
            paletteForBusinessTheme(BusinessThemeVariant.corporateBlue);
        expect(
          _scaffoldUnderTest(tester).backgroundColor,
          corporate.background,
        );
        expect(
          _gradientColors(_gradientUnderTest(tester)).first,
          corporate.background,
        );
      }
    });

    testWidgets('tablet portrait and landscape update the root canvas', (
      tester,
    ) async {
      for (final size in <Size>[
        const Size(800, 1280),
        const Size(1280, 800),
      ]) {
        await tester.runAsync(
          () => applyBusinessThemePreset(BusinessThemeVariant.emeraldIvory),
        );
        await _pumpRootCanvas(tester, size: size);
        await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
        await tester.pumpAndSettle();

        final neon =
            paletteForBusinessTheme(BusinessThemeVariant.fluxidiNeonRush);
        expect(_scaffoldUnderTest(tester).backgroundColor, neon.background);
      }
    });

    // Test 17.
    testWidgets('Clean Professional system overlay remains correct', (
      tester,
    ) async {
      await tester.runAsync(
        () => applyBusinessThemePreset(BusinessThemeVariant.cleanProfessional),
      );
      await _pumpRootCanvas(tester, size: const Size(390, 844));

      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      );
      expect(region.value.statusBarIconBrightness, Brightness.dark);
      expect(region.value.statusBarBrightness, Brightness.light);
      expect(
        _scaffoldUnderTest(tester).backgroundColor,
        const Color(0xFFF4F6FA),
      );
    });
  });

  group('production wiring — no leftover hardcoded Corporate Blue owner', () {
    // Test 18.
    test('no hardcoded Corporate Blue root owner remains outside the preset',
        () {
      final home = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      final canvas = File(
        'lib/widgets/business_theme_root_canvas.dart',
      ).readAsStringSync();
      final mainSrc = File('lib/main.dart').readAsStringSync();

      expect(home.contains('BusinessThemeRootCanvas('), isTrue);
      expect(home.contains('0xFF0A1324'), isFalse);
      expect(home.contains('0xFF13213A'), isFalse);
      expect(
        home.contains('isCorporateBlue\n            ? const Color'),
        isFalse,
      );

      expect(canvas.contains('activeBusinessThemePreset()'), isTrue);
      expect(canvas.contains('paletteForBusinessTheme(preset)'), isTrue);
      expect(canvas.contains('businessThemeNotifier'), isTrue);
      // Forbidden values may be listed only as a denylist for tests.
      expect(
        canvas.contains('kForbiddenCorporateBlueRootColorValues'),
        isTrue,
      );
      expect(
        canvas.contains('backgroundColor: businessThemeRootBackground(preset)'),
        isTrue,
      );

      expect(
        mainSrc.contains(
          "import 'package:fluxidi_tracking/widgets/business_theme_root_canvas.dart';",
        ),
        isTrue,
      );

      // Canonical mapping must not invent a second theme truth source.
      expect(canvas.contains('businessAppearanceNotifier'), isFalse);
    });

    test('root helpers are pure projections of paletteForBusinessTheme', () {
      for (final preset in BusinessThemeVariant.values) {
        final palette = paletteForBusinessTheme(preset);
        expect(businessThemeRootBackground(preset), palette.background);
        expect(businessThemeRootGradientColors(preset), <Color>[
          palette.background,
          palette.background,
          palette.surfaceAlt,
        ]);
        final decoration = businessThemeRootBoxDecoration(preset);
        expect(decoration.gradient, isA<LinearGradient>());
      }
    });

    test('persisted theme file still stores one complete preset', () async {
      await applyBusinessThemePreset(BusinessThemeVariant.fluxidiNeonRush);
      for (final fileName in <String>[
        'business_theme_v1.json',
        'business_appearance_v1.json',
      ]) {
        final file = File(
          '${tempDir.path}${Platform.pathSeparator}business_state'
          '${Platform.pathSeparator}$fileName',
        );
        final decoded = jsonDecode(await file.readAsString()) as Map;
        expect(decoded['variant'], 'fluxidiNeonRush', reason: fileName);
      }
    });
  });
}
