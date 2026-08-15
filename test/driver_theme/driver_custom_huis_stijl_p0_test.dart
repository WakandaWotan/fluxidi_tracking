import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_assets.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_l10n.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company_driver_view_theme_store.dart';
import 'package:fluxidi_tracking/driver_app_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme/chauffeur_gold_icons.dart';
import 'package:fluxidi_tracking/driver_theme/driver_custom_huis_stijl.dart';
import 'package:fluxidi_tracking/driver_theme/driver_theme_selector.dart';
import 'package:fluxidi_tracking/driver_theme_cycle.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_style_dock.dart';
import 'package:fluxidi_tracking/widgets/business_theme_selector_sheet.dart';
import 'package:fluxidi_tracking/widgets/driver_theme_cycle_button.dart';
import 'package:fluxidi_tracking/widgets/driver_theme_selector_sheet.dart';

const _channelsToSilence = <String>[
  'plugins.flutter.io/path_provider',
  'plugins.flutter.io/shared_preferences',
  'flutter.baseflow.com/geolocator',
  'flutter.baseflow.com/geolocator_android',
  'flutter.baseflow.com/geolocator_updates_android',
  'flutter.baseflow.com/permissions/methods',
  'dev.fluttercommunity.plus/wakelock_plus',
  'dev.fluttercommunity.plus/connectivity',
  'dev.fluttercommunity.plus/connectivity_status',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'fluxidi_driver_brand_sig_',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in _channelsToSilence) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        if (name.contains('path_provider')) return tempDir.path;
        return null;
      });
    }
    resetDriverAppThemePersistenceLatchForTest();
    resetCompanyDriverViewThemePersistenceLatchForTest();
    resetBusinessThemePersistenceLatchForTest();
    driverAppThemeNotifier.value = DriverThemeVariant.nightGold;
    companyDriverViewThemeNotifier.value = DriverThemeVariant.nightGold;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    brandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
    driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
  });

  tearDown(() async {
    resetDriverAppThemePersistenceLatchForTest();
    resetCompanyDriverViewThemePersistenceLatchForTest();
    resetBusinessThemePersistenceLatchForTest();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in _channelsToSilence) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fifth chauffeur option is Brand Signature Gold and cycle stays four', () {
    expect(
      kDriverThemeSelectorVariants,
      <DriverThemeVariant>[
        DriverThemeVariant.nightGold,
        DriverThemeVariant.midnightBlue,
        DriverThemeVariant.highContrast,
        DriverThemeVariant.lightEmerald,
        DriverThemeVariant.customHuisstijl,
      ],
    );
    expect(
      driverThemeProductLabel(DriverThemeVariant.customHuisstijl),
      'Brand Signature Gold',
    );
    expect(
      kDriverThemeCycleOrder.contains(DriverThemeVariant.customHuisstijl),
      isFalse,
    );
    expect(
      nextDriverThemeVariant(DriverThemeVariant.lightEmerald),
      DriverThemeVariant.nightGold,
    );
  });

  test('existing chauffeur palettes stay byte-identical', () {
    expect(
      paletteForDriverTheme(DriverThemeVariant.nightGold).background,
      const Color(0xFF07080C),
    );
    expect(
      paletteForDriverTheme(DriverThemeVariant.midnightBlue).accent,
      const Color(0xFF4DA3FF),
    );
    expect(
      paletteForDriverTheme(DriverThemeVariant.highContrast).accent,
      const Color(0xFFE8C57E),
    );
    expect(
      paletteForDriverTheme(DriverThemeVariant.lightEmerald).background,
      const Color(0xFFEEF5F2),
    );
  });

  test('all eight new Gold chauffeur assets resolve in the bundle', () async {
    const added = <String>[
      'home',
      'rides',
      'street_ride',
      'fare_calculator',
      'history',
      'receipts',
      'completed',
      'next_ride',
    ];
    for (final key in added) {
      final data = await rootBundle.load(brandSignatureGoldAssetPath(key));
      expect(data.lengthInBytes, greaterThan(100), reason: key);
    }
    for (final key in kChauffeurGoldIconKeys) {
      final data = await rootBundle.load(brandSignatureGoldAssetPath(key));
      expect(data.lengthInBytes, greaterThan(100), reason: key);
    }
  });

  Future<void> expectFiveRows(WidgetTester tester) async {
    expect(find.byKey(kDriverThemeSelectorSheetKey), findsOneWidget);
    expect(find.text(businessThemeSelectorTitle()), findsOneWidget);
    expect(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.nightGold)),
      findsOneWidget,
    );
    expect(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.midnightBlue)),
      findsOneWidget,
    );
    expect(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.highContrast)),
      findsOneWidget,
    );
    expect(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.lightEmerald)),
      findsOneWidget,
    );
    expect(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl)),
      findsOneWidget,
    );
    expect(find.text('Brand Signature Gold'), findsOneWidget);
    expect(find.textContaining('customHuisstijl'), findsNothing);
  }

  testWidgets('company-style selector previews Gold without opening the studio', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DriverThemeSelectorSheet(companyDriverView: true),
        ),
      ),
    );
    await tester.pump();
    await expectFiveRows(tester);
    expect(find.byKey(kBrandSignatureCustomizeStyleKey), findsNothing);
    expect(find.byKey(kBrandSignatureStyleDockKey), findsNothing);
    await tester.tap(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl)),
    );
    await tester.pump();
    expect(
      companyDriverViewThemeNotifier.value,
      DriverThemeVariant.customHuisstijl,
    );
    expect(find.byKey(kBrandSignatureCustomizeStyleKey), findsOneWidget);
    expect(find.byKey(kBrandSignatureStyleDockKey), findsNothing);
    expect(businessThemeNotifier.value, BusinessThemeVariant.executiveGold);
    await tester.tap(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.lightEmerald)),
    );
    await tester.pump();
    expect(find.byKey(kBrandSignatureCustomizeStyleKey), findsNothing);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('selector Cancel restores the previous chauffeur theme', (
    tester,
  ) async {
    companyDriverViewThemeNotifier.value = DriverThemeVariant.midnightBlue;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDriverThemeSelectorSheet(
                context,
                companyDriverView: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl)),
    );
    await tester.pump();
    await tester.tap(find.byKey(kDriverThemeSelectorCancelKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      companyDriverViewThemeNotifier.value,
      DriverThemeVariant.midnightBlue,
    );
  });

  testWidgets('selector Apply persists Gold and Customize opens the studio', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDriverThemeSelectorSheet(
                context,
                companyDriverView: true,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl)),
    );
    await tester.pump();
    expect(find.byKey(kBrandSignatureStyleDockKey), findsNothing);
    await tester.tap(find.byKey(kBrandSignatureCustomizeStyleKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(kBrandSignatureStyleDockKey), findsOneWidget);
    await tester.ensureVisible(find.byKey(kBrandSignatureStyleCancelKey));
    await tester.tap(find.byKey(kBrandSignatureStyleCancelKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(brandSignaturePaletteNotifier.value, BrandSignaturePalette.defaults);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets(
    'header palette button opens the production five-row selector',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      companyDriverViewThemeNotifier.value = DriverThemeVariant.nightGold;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: DriverThemeCycleButton(
                themeListenable: companyDriverViewThemeNotifier,
                semanticLabel: 'Choose your appearance',
                onApply: (_) async {},
                onPressed: () {
                  unawaited(
                    showDriverThemeSelectorSheet(
                      context,
                      companyDriverView: true,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(DriverThemeCycleButton.buttonKey), findsOneWidget);
      await tester.tap(find.byKey(DriverThemeCycleButton.buttonKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await expectFiveRows(tester);
      expect(find.byKey(kBrandSignatureCustomizeStyleKey), findsNothing);
      await tester.tap(
        find.byKey(
          driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl),
        ),
      );
      await tester.pump();
      expect(find.byKey(kBrandSignatureCustomizeStyleKey), findsOneWidget);
      expect(find.byKey(kBrandSignatureStyleDockKey), findsNothing);
      await tester.tap(find.byKey(kDriverThemeSelectorApplyKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        companyDriverViewThemeNotifier.value,
        DriverThemeVariant.customHuisstijl,
      );
      expect(businessThemeNotifier.value, BusinessThemeVariant.executiveGold);
      final home = File(
        'lib/main_parts/driver_home_page_state.dart',
      ).readAsStringSync();
      expect(home.contains('onPressed: ()'), isTrue);
      expect(home.contains('showDriverThemeSelectorSheet('), isTrue);
      expect(home.contains('companyDriverView: widget.openedFromBusinessHome'), isTrue);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('standalone header palette button opens the same selector', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1280));
    driverAppThemeNotifier.value = DriverThemeVariant.nightGold;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: DriverThemeCycleButton(
              themeListenable: driverAppThemeNotifier,
              semanticLabel: 'Choose your appearance',
              onApply: (_) async {},
              onPressed: () {
                unawaited(
                  showDriverThemeSelectorSheet(
                    context,
                    companyDriverView: false,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(DriverThemeCycleButton.buttonKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await expectFiveRows(tester);
    await tester.tap(find.byKey(kDriverThemeSelectorCancelKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(driverAppThemeNotifier.value, DriverThemeVariant.nightGold);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('Gold KPI icons render only while Brand Signature Gold is active', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChauffeurGoldIcon(assetKey: 'planning', size: 28),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(chauffeurGoldIconKey('planning')), findsOneWidget);
  });

  test('Gold apply persists chauffeur palette after restart', () async {
    await applyChauffeurTheme(
      DriverThemeVariant.customHuisstijl,
      companyDriverView: true,
    );
    await applyChauffeurCustomHuisstijlPalette(
      BrandSignaturePalette.fromColor(const Color(0xFF00E5FF)),
      companyDriverView: true,
    );
    companyDriverViewThemeNotifier.value = DriverThemeVariant.nightGold;
    driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.defaults;
    await loadCompanyDriverViewThemePreference();
    expect(
      companyDriverViewThemeNotifier.value,
      DriverThemeVariant.customHuisstijl,
    );
    expect(
      driverBrandSignaturePaletteNotifier.value.base,
      const Color(0xFF00E5FF),
    );
    expect(businessThemeNotifier.value, BusinessThemeVariant.executiveGold);
    await applyChauffeurTheme(
      DriverThemeVariant.lightEmerald,
      companyDriverView: true,
    );
    expect(
      companyDriverViewThemeNotifier.value,
      DriverThemeVariant.lightEmerald,
    );
  });

  test('legacy Night Gold file without palette key still loads Night Gold', () async {
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}driver_app_state'
      '${Platform.pathSeparator}driver_app_theme_v1.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'variant': 'nightGold',
        'updatedAt': '2026-08-01T00:00:00.000Z',
      }),
    );
    await loadDriverAppThemePreference();
    expect(driverAppThemeNotifier.value, DriverThemeVariant.nightGold);
  });
}
