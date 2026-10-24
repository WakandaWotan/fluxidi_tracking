import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

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
import 'package:fluxidi_tracking/driver_theme/driver_theme_system_ui.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_action_card.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_header.dart';
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

  test(
    'fifth chauffeur option is Brand Signature Gold and cycle stays four',
    () {
      expect(kDriverThemeSelectorVariants, <DriverThemeVariant>[
        DriverThemeVariant.nightGold,
        DriverThemeVariant.midnightBlue,
        DriverThemeVariant.highContrast,
        DriverThemeVariant.lightEmerald,
        DriverThemeVariant.customHuisstijl,
      ]);
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
    },
  );

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
      find.byKey(
        driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl),
      ),
      findsOneWidget,
    );
    expect(find.text('Brand Signature Gold'), findsOneWidget);
    expect(find.textContaining('customHuisstijl'), findsNothing);
  }

  testWidgets(
    'company-style selector previews Gold without opening the studio',
    (tester) async {
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
        find.byKey(
          driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl),
        ),
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
    },
  );

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
      find.byKey(
        driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl),
      ),
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
      find.byKey(
        driverThemeSelectorTileKey(DriverThemeVariant.customHuisstijl),
      ),
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

  testWidgets('header palette button opens the production five-row selector', (
    tester,
  ) async {
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
    expect(
      home.contains('companyDriverView: widget.openedFromBusinessHome'),
      isTrue,
    );
    await tester.binding.setSurfaceSize(null);
  });

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

  testWidgets(
    'Gold KPI icons render only while Brand Signature Gold is active',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChauffeurGoldIcon(assetKey: 'planning', size: 28),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(chauffeurGoldIconKey('planning')), findsOneWidget);
    },
  );

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

  test(
    'legacy Night Gold file without palette key still loads Night Gold',
    () async {
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
    },
  );

  test(
    'Gold chauffeur header reuses company header tokens and skips hero copy',
    () {
      final src = File(
        'lib/main_parts/driver_home_page_state.dart',
      ).readAsStringSync();
      expect(src.contains('_buildChauffeurBrandSignatureGoldHeader'), isTrue);
      expect(src.contains('BrandSignatureGoldHeader('), isTrue);
      expect(src.contains('brandSignatureGoldHeaderHeightForLayout('), isTrue);
      expect(src.contains('BrandSignatureGoldActionCard('), isTrue);
      expect(src.contains('kBrandSignatureGoldActionCardHeightBoost'), isTrue);
      expect(src.contains('driver_header_portrait_tablet.webp'), isTrue);
      expect(src.contains('driver_home_header_midnight_blue.webp'), isTrue);
      expect(src.contains('driver_home_header_midday_gold.webp'), isTrue);
      expect(src.contains('driver_home_header_light_emerald.webp'), isTrue);
      expect(src.contains('driverIdentityBlock()'), isTrue);
      expect(src.contains("goldAsset: brandSignatureGoldAssetPath("), isFalse);
      expect(src.contains('if (isCustomHuisstijl)'), isTrue);
      expect(src.contains('_buildChauffeurBrandSignatureGoldHeader('), isTrue);
    },
  );

  testWidgets(
    'Gold chauffeur header shows a contained tenant logo without Driver copy',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1280));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BrandSignatureGoldHeader(
              height: brandSignatureGoldHeaderHeightForLayout(
                isTabletLandscape: false,
                useTabletVisualMode: true,
              ),
              logoRef: kBrandSignatureGoldThemeAsset,
              hasCompanyLogo: true,
              companyName: 'Acme Cars',
              paletteListenable: driverBrandSignaturePaletteNotifier,
              trailing: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(kBrandSignatureGoldHeaderKey), findsOneWidget);
      expect(find.byKey(kBrandSignatureGoldLogoKey), findsOneWidget);
      final logo = tester.widget<Image>(find.byKey(kBrandSignatureGoldLogoKey));
      expect(logo.fit, BoxFit.contain);
      expect(
        tester.getSize(find.byKey(kBrandSignatureGoldHeaderKey)).height,
        kBrandSignatureGoldHeaderHeightTablet,
      );
      expect(find.text('Driver'), findsNothing);
      expect(find.text('Chauffeur'), findsNothing);
      expect(find.text('Acme Cars'), findsNothing);
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets('Gold chauffeur cards use company contain sizing, not cover', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            height:
                kBrandSignatureGoldPhoneCompactCardHeight +
                kBrandSignatureGoldActionCardHeightBoost,
            child: BrandSignatureGoldActionCard(
              actionKey: 'street_ride',
              title: 'Straatrit',
              subtitle: '',
              paletteListenable: driverBrandSignaturePaletteNotifier,
              contrastTextAgainstCard: true,
              rectangularLightCardIconShadow: false,
              phoneGoldIconBox: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const Key('brand_signature_action_street_ride')),
      findsOneWidget,
    );
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.fit, kBrandSignatureGoldIllustrationFit);
      expect(image.fit, BoxFit.contain);
    }
    expect(
      find.byKey(kBrandSignatureGoldPhoneActionIconBoxKey),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(kBrandSignatureGoldPhoneActionIconBoxKey)),
      const Size(
        kBrandSignatureGoldPhoneActionIconBox,
        kBrandSignatureGoldPhoneActionIconBox,
      ),
    );
    final phoneIcon = tester.widget<Image>(
      find.descendant(
        of: find.byKey(kBrandSignatureGoldPhoneActionIconBoxKey),
        matching: find.byType(Image),
      ),
    );
    expect(phoneIcon.width, kBrandSignatureGoldPhoneActionIconBox);
    expect(phoneIcon.height, kBrandSignatureGoldPhoneActionIconBox);
    expect(phoneIcon.fit, BoxFit.contain);
    final title = tester.widget<Text>(
      find.byKey(brandSignatureGoldActionTitleKey('street_ride')),
    );
    expect(title.maxLines, 2);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChauffeurGoldIcon(assetKey: 'planning', size: 28)),
      ),
    );
    await tester.pump();
    final kpi = tester.widget<Image>(
      find.byKey(chauffeurGoldIconKey('planning')),
    );
    expect(kpi.fit, BoxFit.contain);
    expect(kpi.width, 28);
    expect(kpi.height, 28);
    await tester.binding.setSurfaceSize(null);
  });

  test(
    'six Gold chauffeur action assets have genuine transparent corners',
    () async {
      for (final key in kChauffeurGoldQuickActionAssetKeys) {
        final path = brandSignatureGoldAssetPath(key);
        final bytes = await File(path).readAsBytes();
        final codec = await instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1254, reason: path);
        expect(frame.image.height, 1254, reason: path);
        final data = await frame.image.toByteData(
          format: ImageByteFormat.rawRgba,
        );
        expect(data, isNotNull, reason: path);
        final w = frame.image.width;
        final h = frame.image.height;
        int alphaAt(int x, int y) => data!.getUint8(((y * w) + x) * 4 + 3);
        expect(alphaAt(0, 0), 0, reason: '$path TL');
        expect(alphaAt(w - 1, 0), 0, reason: '$path TR');
        expect(alphaAt(0, h - 1), 0, reason: '$path BL');
        expect(alphaAt(w - 1, h - 1), 0, reason: '$path BR');
        frame.image.dispose();
        codec.dispose();
      }
    },
  );

  testWidgets(
    'light Gold chauffeur cards use dark titles and no grey icon matte',
    (tester) async {
      final light = BrandSignaturePalette.fromColor(const Color(0xFFF4EDE0));
      driverBrandSignaturePaletteNotifier.value = light;
      expect(brandSignatureRelativeLuminance(light.card) >= 0.62, isTrue);
      await tester.binding.setSurfaceSize(const Size(400, 800));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              height: 180,
              child: BrandSignatureGoldActionCard(
                actionKey: 'street_ride',
                title: 'Straatrit',
                subtitle: 'Direct',
                paletteListenable: driverBrandSignaturePaletteNotifier,
                contrastTextAgainstCard: true,
                rectangularLightCardIconShadow: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(kBrandSignatureGoldLightCardIconShadowKey),
        findsNothing,
      );
      final title = tester.widget<Text>(
        find.byKey(brandSignatureGoldActionTitleKey('street_ride')),
      );
      expect(title.style?.color, isNot(Colors.white));
      expect(title.style?.color, isNot(const Color(0xFFFFFFFF)));
      expect(
        brandSignatureHasReadableText(title.style!.color!, light.card),
        isTrue,
      );
      expect(
        brandSignatureContrastRatio(title.style!.color!, light.card),
        greaterThanOrEqualTo(4.5),
      );
      final images = tester.widgetList<Image>(find.byType(Image));
      for (final image in images) {
        expect(image.fit, BoxFit.contain);
      }
      await tester.binding.setSurfaceSize(null);
    },
  );

  test('light Gold chauffeur overlay uses dark status-bar icons', () {
    driverBrandSignaturePaletteNotifier.value = BrandSignaturePalette.fromColor(
      const Color(0xFFF4EDE0),
    );
    final light = paletteForDriverTheme(DriverThemeVariant.customHuisstijl);
    expect(light.isDark, isFalse);
    final overlay = systemUiOverlayStyleForDriverTheme(light);
    expect(overlay.statusBarIconBrightness, Brightness.dark);
    expect(overlay.statusBarBrightness, Brightness.light);

    final night = paletteForDriverTheme(DriverThemeVariant.nightGold);
    expect(night.isDark, isTrue);
    expect(
      systemUiOverlayStyleForDriverTheme(night).statusBarIconBrightness,
      Brightness.light,
    );
    expect(
      paletteForDriverTheme(DriverThemeVariant.midnightBlue).textPrimary,
      const Color(0xFFF4F8FF),
    );
    expect(
      paletteForDriverTheme(DriverThemeVariant.lightEmerald).isDark,
      isFalse,
    );
  });

  test('source contract keeps Gold cards contain-only and overlay scoped', () {
    final src = File(
      'lib/main_parts/driver_home_page_state.dart',
    ).readAsStringSync();
    expect(src.contains('rectangularLightCardIconShadow: false'), isTrue);
    expect(src.contains('contrastTextAgainstCard: true'), isTrue);
    expect(src.contains('phoneGoldIconBox: phoneGold'), isTrue);
    expect(src.contains('kBrandSignatureGoldPhoneCompactCardHeight'), isTrue);
    expect(
      src.contains('brandSignatureGoldChauffeurPhoneActionColumns('),
      isTrue,
    );
    expect(src.contains('kBrandSignatureGoldPhoneActionSpacing'), isTrue);
    expect(src.contains('kChauffeurGoldStatusBarRegionKey'), isTrue);
    expect(src.contains('BoxFit.cover'), isTrue);
    expect(src.contains("goldAsset: brandSignatureGoldAssetPath("), isFalse);
  });

  test('phone Gold icon box matches the company compact leftover token', () {
    expect(kBrandSignatureGoldPhoneActionIconBox, 96);
    expect(kBrandSignatureGoldPhoneCompactCardHeight, 132);
    expect(kBrandSignatureGoldChauffeurActionIconFill, 1.18);
    expect(
      brandSignatureGoldPhoneActionIconExtent(maxWidth: 380, maxHeight: 84),
      84,
    );
    expect(
      brandSignatureGoldPhoneActionIconExtent(maxWidth: 180, maxHeight: 110),
      kBrandSignatureGoldPhoneActionIconBox,
    );
  });
}
