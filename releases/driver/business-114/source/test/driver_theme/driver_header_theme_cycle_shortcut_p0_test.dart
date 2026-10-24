// FLUXIDI — DRIVER HEADER ONE-TAP THEME SWITCH
//
// Source/widget contracts for the chauffeur dashboard theme-cycle shortcut.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/company_driver_view_theme_store.dart';
import 'package:fluxidi_tracking/driver_app_theme_store.dart';
import 'package:fluxidi_tracking/driver_theme_cycle.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/driver_theme_cycle_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'fluxidi_driver_theme_cycle_',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    resetDriverAppThemePersistenceLatchForTest();
    resetCompanyDriverViewThemePersistenceLatchForTest();
    driverAppThemeNotifier.value = DriverThemeVariant.nightGold;
    companyDriverViewThemeNotifier.value = DriverThemeVariant.nightGold;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  tearDown(() async {
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

  group('canonical cycle order', () {
    test('Night Gold → Midnight Blue → Midday Gold → Light Emerald → wrap', () {
      expect(kDriverThemeCycleOrder, <DriverThemeVariant>[
        DriverThemeVariant.nightGold,
        DriverThemeVariant.midnightBlue,
        DriverThemeVariant.highContrast,
        DriverThemeVariant.lightEmerald,
      ]);
      expect(
        nextDriverThemeVariant(DriverThemeVariant.nightGold),
        DriverThemeVariant.midnightBlue,
      );
      expect(
        nextDriverThemeVariant(DriverThemeVariant.midnightBlue),
        DriverThemeVariant.highContrast,
      );
      expect(
        nextDriverThemeVariant(DriverThemeVariant.highContrast),
        DriverThemeVariant.lightEmerald,
      );
      expect(
        nextDriverThemeVariant(DriverThemeVariant.lightEmerald),
        DriverThemeVariant.nightGold,
      );
    });

    test('Light Emerald appears exactly once', () {
      final count = kDriverThemeCycleOrder
          .where((v) => v == DriverThemeVariant.lightEmerald)
          .length;
      expect(count, 1);
    });

    test('product labels cover all four themes', () {
      expect(
        driverThemeProductLabel(DriverThemeVariant.nightGold),
        'Night Gold',
      );
      expect(
        driverThemeProductLabel(DriverThemeVariant.midnightBlue),
        'Midnight Blue',
      );
      expect(
        driverThemeProductLabel(DriverThemeVariant.highContrast),
        'Midday Gold',
      );
      expect(
        driverThemeProductLabel(DriverThemeVariant.lightEmerald),
        'Light Emerald',
      );
    });
  });

  group('persistence + rapid taps', () {
    test('cycleDriverAppThemePreference persists next theme', () async {
      driverAppThemeNotifier.value = DriverThemeVariant.nightGold;
      final next = await cycleDriverAppThemePreference();
      expect(next, DriverThemeVariant.midnightBlue);
      expect(driverAppThemeNotifier.value, DriverThemeVariant.midnightBlue);

      final file = File(
        '${tempDir.path}${Platform.pathSeparator}driver_app_state'
        '${Platform.pathSeparator}driver_app_theme_v1.json',
      );
      expect(await file.exists(), isTrue);
      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['variant'], 'midnightBlue');
    });

    test('rapid cycles coalesce to final live theme (no stale LWW)', () async {
      driverAppThemeNotifier.value = DriverThemeVariant.nightGold;
      // Fire overlapping persists; latch must converge on the last live value.
      final f1 = applyDriverAppThemePreference(DriverThemeVariant.midnightBlue);
      final f2 = applyDriverAppThemePreference(DriverThemeVariant.highContrast);
      final f3 = applyDriverAppThemePreference(DriverThemeVariant.lightEmerald);
      await Future.wait<void>([f1, f2, f3]);
      expect(driverAppThemeNotifier.value, DriverThemeVariant.lightEmerald);

      final file = File(
        '${tempDir.path}${Platform.pathSeparator}driver_app_state'
        '${Platform.pathSeparator}driver_app_theme_v1.json',
      );
      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['variant'], 'lightEmerald');
    });

    test(
      'company chauffeur-view cycle does not touch business theme',
      () async {
        businessThemeNotifier.value = BusinessThemeVariant.corporateBlue;
        companyDriverViewThemeNotifier.value = DriverThemeVariant.nightGold;
        await cycleCompanyDriverViewThemePreference();
        expect(
          companyDriverViewThemeNotifier.value,
          DriverThemeVariant.midnightBlue,
        );
        expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
        expect(driverAppThemeNotifier.value, DriverThemeVariant.nightGold);
      },
    );
  });

  group('button widget', () {
    testWidgets('exists, cycles once, uses palette colors, 48px target', (
      tester,
    ) async {
      final listenable = ValueNotifier(DriverThemeVariant.nightGold);
      DriverThemeVariant? cycled;
      final applied = <DriverThemeVariant>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DriverThemeCycleButton(
                themeListenable: listenable,
                semanticLabel: 'Next theme',
                onApply: (next) async {
                  applied.add(next);
                  listenable.value = next;
                },
                onCycled: (v) => cycled = v,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(DriverThemeCycleButton.buttonKey), findsOneWidget);
      final size = tester.getSize(find.byKey(DriverThemeCycleButton.buttonKey));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));

      await tester.tap(find.byKey(DriverThemeCycleButton.buttonKey));
      await tester.pump();
      for (var i = 0; i < 20 && cycled == null; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(applied, <DriverThemeVariant>[DriverThemeVariant.midnightBlue]);
      expect(cycled, DriverThemeVariant.midnightBlue);
      expect(listenable.value, DriverThemeVariant.midnightBlue);
    });

    testWidgets('light and dark themes keep accent icon contrast', (
      tester,
    ) async {
      for (final variant in kDriverThemeCycleOrder) {
        final listenable = ValueNotifier(variant);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: DriverThemeCycleButton(
                themeListenable: listenable,
                semanticLabel: 'Volgend thema',
                onApply: (_) async {},
              ),
            ),
          ),
        );
        await tester.pump();
        final icon = tester.widget<Icon>(find.byIcon(Icons.palette_outlined));
        final expected = paletteForDriverTheme(variant).accent;
        expect(icon.color, expected, reason: 'accent for $variant');
      }
    });

    testWidgets('phone/tablet widths do not overflow the control', (
      tester,
    ) async {
      for (final size in const [
        Size(360, 780),
        Size(780, 360),
        Size(800, 1280),
        Size(1280, 800),
      ]) {
        await tester.binding.setSurfaceSize(size);
        final listenable = ValueNotifier(DriverThemeVariant.lightEmerald);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: size),
              child: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 72, height: 30),
                      const SizedBox(width: 8),
                      DriverThemeCycleButton(
                        themeListenable: listenable,
                        semanticLabel: 'Next theme',
                        heroOverlay: true,
                        onApply: (_) async {},
                      ),
                      const SizedBox(width: 8),
                      const SizedBox(width: 50, height: 50),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'size $size');
      }
      await tester.binding.setSurfaceSize(null);
    });
  });

  group('source contracts in driver home header', () {
    late String homeSource;

    setUpAll(() {
      homeSource = File(
        'lib/main_parts/driver_home_page_state.dart',
      ).readAsStringSync();
    });

    test('header wires DriverThemeCycleButton between language and avatar', () {
      expect(homeSource.contains('DriverThemeCycleButton('), isTrue);
      expect(homeSource.contains("nl: 'Kies je uitstraling'"), isTrue);
      expect(homeSource.contains("en: 'Choose your appearance'"), isTrue);
      expect(homeSource.contains('showDriverThemeSelectorSheet('), isTrue);
      expect(homeSource.contains('onPressed: ()'), isTrue);
      expect(homeSource.contains('_applyDriverThemeFromHeaderCycle'), isTrue);

      final clusterStart = homeSource.indexOf(
        'Widget _buildDriverHeaderActionCluster(',
      );
      expect(clusterStart, greaterThan(0));
      final clusterSlice = homeSource.substring(
        clusterStart,
        clusterStart + 4000,
      );
      final langIdx = clusterSlice.indexOf('_driverLanguagePill()');
      final cycleIdx = clusterSlice.indexOf('DriverThemeCycleButton(');
      final avatarIdx = clusterSlice.indexOf('width: 50');
      expect(langIdx, greaterThan(0));
      expect(cycleIdx, greaterThan(langIdx));
      expect(avatarIdx, greaterThan(cycleIdx));
      expect(
        homeSource.contains('_buildDriverHeaderActionCluster('),
        isTrue,
      );
    });
  });
}
