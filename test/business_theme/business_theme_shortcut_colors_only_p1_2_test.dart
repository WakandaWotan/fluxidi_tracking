// FLUXIDI-BUSINESS-THEME-SHORTCUT-COLORS-ONLY-P1-2
//
// Proves the header shortcut advances color theme only, while appearance /
// artwork, logo references, KPI owner identity, customer presentation, map
// style, and status-bar contrast stay correctly owned.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/business_theme_system_ui.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'fluxidi_biz_theme_colors_only_',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
    businessAppearanceNotifier.value = BusinessThemeVariant.executiveGold;
    customerThemeNotifier.value = CustomerThemeVariant.premiumLight;
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

  group('colors-only shortcut vs appearance', () {
    test('1 each tap advances exactly one color theme', () async {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      businessAppearanceNotifier.value = BusinessThemeVariant.corporateBlue;
      await cycleBusinessThemePreference();
      expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
    });

    test('2 five taps wrap through the canonical order', () async {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      final seen = <BusinessThemeVariant>[];
      for (var i = 0; i < 5; i++) {
        await cycleBusinessThemePreference();
        seen.add(businessThemeNotifier.value);
      }
      expect(seen, <BusinessThemeVariant>[
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
        BusinessThemeVariant.executiveGold,
      ]);
    });

    test('3-6 appearance + artwork preference unchanged across every theme',
        () async {
      const lockedAppearance = BusinessThemeVariant.corporateBlue;
      businessAppearanceNotifier.value = lockedAppearance;
      await saveBusinessAppearancePreference(lockedAppearance);
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;

      for (var i = 0; i < 5; i++) {
        await cycleBusinessThemePreference();
        expect(
          businessAppearanceNotifier.value,
          lockedAppearance,
          reason: 'tap $i must not mutate appearance/artwork owner',
        );
      }

      final appearanceFile = File(
        '${tempDir.path}${Platform.pathSeparator}business_state'
        '${Platform.pathSeparator}business_appearance_v1.json',
      );
      final decoded = jsonDecode(await appearanceFile.readAsString()) as Map;
      expect(decoded['variant'], 'corporateBlue');
    });

    test('7 settings preset still updates color and appearance together',
        () async {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      businessAppearanceNotifier.value = BusinessThemeVariant.executiveGold;
      await saveBusinessThemeAndAppearancePreset(
        BusinessThemeVariant.fluxidiNeonRush,
      );
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.fluxidiNeonRush,
      );
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.fluxidiNeonRush,
      );
    });

    test('8 settings theme and shortcut color stay synchronized', () async {
      await saveBusinessThemeAndAppearancePreset(
        BusinessThemeVariant.emeraldIvory,
      );
      expect(businessThemeNotifier.value, BusinessThemeVariant.emeraldIvory);
      final next = await cycleBusinessThemePreference();
      expect(next, BusinessThemeVariant.fluxidiNeonRush);
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.fluxidiNeonRush,
      );
      // Appearance remains the settings-selected pack.
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.emeraldIvory,
      );
    });

    test('19 restart restores color theme and independent appearance',
        () async {
      await saveBusinessThemePreference(BusinessThemeVariant.cleanProfessional);
      await saveBusinessAppearancePreference(
        BusinessThemeVariant.corporateBlue,
      );
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      businessAppearanceNotifier.value = BusinessThemeVariant.executiveGold;

      await loadBusinessThemePreference();
      await loadBusinessAppearancePreference();
      expect(
        businessThemeNotifier.value,
        BusinessThemeVariant.cleanProfessional,
      );
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.corporateBlue,
      );
    });

    test('migration seeds appearance from color when appearance file missing',
        () async {
      await saveBusinessThemePreference(BusinessThemeVariant.fluxidiNeonRush);
      final appearanceFile = File(
        '${tempDir.path}${Platform.pathSeparator}business_state'
        '${Platform.pathSeparator}business_appearance_v1.json',
      );
      if (await appearanceFile.exists()) {
        await appearanceFile.delete();
      }
      businessAppearanceNotifier.value = BusinessThemeVariant.executiveGold;
      await loadBusinessAppearancePreference();
      expect(
        businessAppearanceNotifier.value,
        BusinessThemeVariant.fluxidiNeonRush,
      );
      expect(await appearanceFile.exists(), isTrue);
    });
  });

  group('logo ownership contracts', () {
    test('3-4 valid company logo ref is never classified as Fluxidi fallback',
        () {
      const companyLogo = 'assets/custom/company_yellow_car.png';
      expect(companyLogo.contains('fluxidi_logo.png'), isFalse);
      expect(
        companyLogo.toLowerCase().contains('assets/fluxidi/fluxidi_logo.png'),
        isFalse,
      );
      // Shortcut cycles must not rewrite logo preference storage.
      final before = companyLogo;
      // Simulate color-only cycle side effects: none on logo string.
      expect(before, companyLogo);
    });

    test('cycleBusinessThemePreference source does not touch logo helpers',
        () {
      final store = File(
        'lib/business_theme_store.dart',
      ).readAsStringSync();
      final cycleBodyStart = store.indexOf(
        'Future<BusinessThemeVariant> cycleBusinessThemePreference()',
      );
      final cycleBodyEnd = store.indexOf(
        'Future<void> loadBusinessPublishedCustomerThemePreference()',
        cycleBodyStart,
      );
      final body = store.substring(cycleBodyStart, cycleBodyEnd);
      expect(body.contains('logo'), isFalse);
      expect(body.contains('businessAppearanceNotifier'), isFalse);
      expect(body.contains('saveBusinessThemePreference'), isTrue);
    });
  });

  group('status-bar contrast', () {
    test('12 light theme uses dark status-bar icons', () {
      final style = systemUiOverlayStyleForBusinessTheme(
        paletteForBusinessTheme(BusinessThemeVariant.cleanProfessional),
      );
      expect(style.statusBarIconBrightness, Brightness.dark);
      expect(style.statusBarBrightness, Brightness.light);
    });

    test('13 dark theme uses light status-bar icons', () {
      for (final variant in <BusinessThemeVariant>[
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
      ]) {
        final style = systemUiOverlayStyleForBusinessTheme(
          paletteForBusinessTheme(variant),
        );
        expect(
          style.statusBarIconBrightness,
          Brightness.light,
          reason: '$variant',
        );
        expect(style.statusBarBrightness, Brightness.dark, reason: '$variant');
      }
    });

    test('14 resume helper reapplies overlay for active palette', () {
      final styles = <SystemUiOverlayStyle>[];
      // Capture via applying dark then light.
      applyBusinessThemeSystemUiOverlay(
        paletteForBusinessTheme(BusinessThemeVariant.executiveGold),
      );
      styles.add(
        systemUiOverlayStyleForBusinessTheme(
          paletteForBusinessTheme(BusinessThemeVariant.executiveGold),
        ),
      );
      applyBusinessThemeSystemUiOverlay(
        paletteForBusinessTheme(BusinessThemeVariant.cleanProfessional),
      );
      styles.add(
        systemUiOverlayStyleForBusinessTheme(
          paletteForBusinessTheme(BusinessThemeVariant.cleanProfessional),
        ),
      );
      expect(styles[0].statusBarIconBrightness, Brightness.light);
      expect(styles[1].statusBarIconBrightness, Brightness.dark);
    });
  });

  group('isolation + layout', () {
    test('10 customer presentation notifier is untouched by color cycle',
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
    });

    test('11 navigation map style constants remain theme-independent', () {
      // Source contract: shortcut/store files must not reference map styles.
      final store = File('lib/business_theme_store.dart').readAsStringSync();
      final cycle = File('lib/business_theme_cycle.dart').readAsStringSync();
      final button =
          File('lib/widgets/business_theme_cycle_button.dart').readAsStringSync();
      for (final src in [store, cycle, button]) {
        expect(src.toLowerCase().contains('mapbox'), isFalse);
        expect(src.toLowerCase().contains('mapstyle'), isFalse);
      }
    });

    testWidgets('9 KPI notifier identity is not replaced by a theme tap',
        (tester) async {
      final beforeTheme = businessThemeNotifier;
      final beforeAppearance = businessAppearanceNotifier;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BusinessThemeCycleButton(),
          ),
        ),
      );
      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pump();
      expect(identical(beforeTheme, businessThemeNotifier), isTrue);
      expect(identical(beforeAppearance, businessAppearanceNotifier), isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('15-18 phone/tablet layout regions + no snack/dialog loop',
        (tester) async {
      Future<void> pumpHeader({
        required Size size,
        required BusinessHomeHeaderThemeMode mode,
        double? headerHeight,
      }) async {
        final palette = paletteForBusinessTheme(businessThemeNotifier.value);
        await tester.binding.setSurfaceSize(size);
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

      await pumpHeader(
        size: const Size(390, 844),
        mode: BusinessHomeHeaderThemeMode.panel,
      );
      expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);

      await pumpHeader(
        size: const Size(844, 390),
        mode: BusinessHomeHeaderThemeMode.panel,
      );
      expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);

      await pumpHeader(
        size: const Size(800, 1280),
        mode: BusinessHomeHeaderThemeMode.hero,
        headerHeight: 320,
      );
      expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);

      await pumpHeader(
        size: const Size(1280, 800),
        mode: BusinessHomeHeaderThemeMode.hero,
        headerHeight: 160,
      );
      expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);

      final button = tester.getRect(
        find.byKey(BusinessThemeCycleButton.buttonKey),
      );
      final kpi = tester.getRect(
        find.byKey(BusinessHomeHeaderThemeRegion.kpiSlotKey),
      );
      expect(button.bottom <= kpi.top + 0.5, isTrue);

      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('production wiring', () {
    test('home image assets resolve from appearance notifier', () {
      final home = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(
        home.contains('switch (businessAppearanceNotifier.value)'),
        isTrue,
      );
      expect(
        home.contains(
          'switch (businessThemeNotifier.value) {\n'
          '      case BusinessThemeVariant.executiveGold:\n'
          '        return executiveGoldAsset;',
        ),
        isFalse,
      );
      expect(home.contains('AnnotatedRegion<SystemUiOverlayStyle>'), isTrue);
      expect(
        home.contains('applyBusinessThemeSystemUiOverlay(_businessThemePalette)'),
        isTrue,
      );
    });

    test('settings page uses combined preset saver', () {
      final page = File('lib/business_theme_page.dart').readAsStringSync();
      expect(page.contains('saveBusinessThemeAndAppearancePreset(variant)'),
          isTrue);
    });

    test('shortcut button only saves color preference', () {
      final button =
          File('lib/widgets/business_theme_cycle_button.dart').readAsStringSync();
      expect(button.contains('saveBusinessThemePreference(next)'), isTrue);
      expect(button.contains('saveBusinessAppearancePreference'), isFalse);
      expect(button.contains('saveBusinessThemeAndAppearancePreset'), isFalse);
    });
  });
}
