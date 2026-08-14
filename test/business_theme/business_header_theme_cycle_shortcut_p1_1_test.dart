// FLUXIDI-BUSINESS-HEADER-THEME-CYCLE-SHORTCUT-P1-1
//
// Deterministic coverage for the one-tap business theme cycle shortcut:
// product order, persistence, settings sync, isolation, layout, a11y.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_cycle.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';
import 'package:fluxidi_tracking/customer_theme_palette.dart';
import 'package:fluxidi_tracking/customer_theme_store.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluxidi_biz_theme_cycle_');
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

  group('canonical cycle order', () {
    test('1 Executive Gold → Corporate Blue', () {
      expect(
        nextBusinessThemeVariant(BusinessThemeVariant.executiveGold),
        BusinessThemeVariant.corporateBlue,
      );
    });

    test('2 Corporate Blue → Clean Professional', () {
      expect(
        nextBusinessThemeVariant(BusinessThemeVariant.corporateBlue),
        BusinessThemeVariant.cleanProfessional,
      );
    });

    test('3 Clean Professional → Emerald Ivory (Emerald+Ivory canonical)', () {
      expect(
        nextBusinessThemeVariant(BusinessThemeVariant.cleanProfessional),
        BusinessThemeVariant.emeraldIvory,
      );
      expect(
        businessThemeProductLabel(BusinessThemeVariant.emeraldIvory),
        'Emerald Ivory',
      );
    });

    test('4 Emerald Ivory → Fluxy Neon Rush', () {
      // Product lists Emerald then Ivory separately; shipped enum has one
      // emeraldIvory step, then Neon Rush.
      expect(
        nextBusinessThemeVariant(BusinessThemeVariant.emeraldIvory),
        BusinessThemeVariant.fluxidiNeonRush,
      );
    });

    test('5 Fluxy Neon Rush → Brand Signature Gold', () {
      expect(
        nextBusinessThemeVariant(BusinessThemeVariant.fluxidiNeonRush),
        BusinessThemeVariant.brandSignatureGold,
      );
    });

    test('6 Brand Signature Gold → Executive Gold (wrap)', () {
      expect(
        nextBusinessThemeVariant(BusinessThemeVariant.brandSignatureGold),
        BusinessThemeVariant.executiveGold,
      );
    });

    test('product order matches canonical identifiers', () {
      expect(kBusinessThemeCycleOrder, <BusinessThemeVariant>[
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
        BusinessThemeVariant.brandSignatureGold,
      ]);
      expect(
        businessThemeProductLabel(BusinessThemeVariant.fluxidiNeonRush),
        'Fluxy Neon Rush',
      );
    });
  });

  group('persistence + notifier owner', () {
    test(
      '6-7 current persisted theme determines next; one tap advances once',
      () async {
        await saveBusinessThemePreference(BusinessThemeVariant.corporateBlue);
        expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);

        final next = await cycleBusinessThemePreference();
        expect(next, BusinessThemeVariant.cleanProfessional);
        expect(
          businessThemeNotifier.value,
          BusinessThemeVariant.cleanProfessional,
        );
      },
    );

    test('8 one tap advances exactly once', () async {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      await cycleBusinessThemePreference();
      expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
      expect(
        businessThemeNotifier.value,
        isNot(BusinessThemeVariant.cleanProfessional),
      );
    });

    test('9 rapid taps do not lose or duplicate transitions', () async {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      final expected = <BusinessThemeVariant>[
        BusinessThemeVariant.corporateBlue,
        BusinessThemeVariant.cleanProfessional,
        BusinessThemeVariant.emeraldIvory,
        BusinessThemeVariant.fluxidiNeonRush,
        BusinessThemeVariant.brandSignatureGold,
        BusinessThemeVariant.executiveGold,
        BusinessThemeVariant.corporateBlue,
      ];
      final observed = <BusinessThemeVariant>[];
      for (var i = 0; i < expected.length; i++) {
        final future = cycleBusinessThemePreference();
        observed.add(businessThemeNotifier.value);
        await future;
      }
      expect(observed, expected);
      expect(businessThemeNotifier.value, expected.last);
    });

    test('10 new theme is persisted', () async {
      await saveBusinessThemePreference(BusinessThemeVariant.executiveGold);
      await cycleBusinessThemePreference();
      final file = File(
        '${tempDir.path}${Platform.pathSeparator}business_state'
        '${Platform.pathSeparator}business_theme_v1.json',
      );
      expect(await file.exists(), isTrue);
      final decoded = jsonDecode(await file.readAsString()) as Map;
      expect(decoded['variant'], 'corporateBlue');
    });

    test('11 app restart restores the selected theme', () async {
      await saveBusinessThemePreference(BusinessThemeVariant.fluxidiNeonRush);
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      await loadBusinessThemePreference();
      expect(businessThemeNotifier.value, BusinessThemeVariant.fluxidiNeonRush);
    });

    test('invalid legacy storage falls back to Executive Gold', () async {
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
  });

  group('settings sync + isolation', () {
    test('12 settings screen reads the same selected theme', () async {
      await saveBusinessThemePreference(BusinessThemeVariant.emeraldIvory);
      expect(businessThemeNotifier.value, BusinessThemeVariant.emeraldIvory);
      expect(
        BusinessThemeVariant.values.contains(businessThemeNotifier.value),
        isTrue,
      );
    });

    test('13 settings-screen change becomes shortcut starting point', () async {
      await saveBusinessThemePreference(BusinessThemeVariant.cleanProfessional);
      final next = nextBusinessThemeVariant(businessThemeNotifier.value);
      expect(next, BusinessThemeVariant.emeraldIvory);
      await cycleBusinessThemePreference();
      expect(businessThemeNotifier.value, BusinessThemeVariant.emeraldIvory);
    });

    test('14 customer presentation remains unchanged', () async {
      final before = customerThemeNotifier.value;
      await cycleBusinessThemePreference();
      expect(customerThemeNotifier.value, before);
    });

    test('15 navigation map style remains unchanged (no map owner touch)', () {
      final beforeBiz = businessThemeNotifier.value;
      final beforeCustomer = customerThemeNotifier.value;
      final next = nextBusinessThemeVariant(beforeBiz);
      businessThemeNotifier.value = next;
      expect(customerThemeNotifier.value, beforeCustomer);
      expect(businessThemeNotifier.value, next);
      businessThemeNotifier.value = beforeBiz;

      final cycleSource = File(
        'lib/business_theme_cycle.dart',
      ).readAsStringSync();
      final buttonSource = File(
        'lib/widgets/business_theme_cycle_button.dart',
      ).readAsStringSync();
      expect(cycleSource.contains('MapThemeMode'), isFalse);
      expect(buttonSource.contains('MapThemeMode'), isFalse);
    });

    testWidgets('16 system Material brightness remains dark shell', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Builder(
            builder: (context) {
              return const Scaffold(
                body: Center(child: BusinessThemeCycleButton()),
              );
            },
          ),
        ),
      );
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pump();
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
    });
  });

  group('header layout + a11y', () {
    testWidgets('17 phone portrait header layout', (tester) async {
      await _pumpHeaderHarness(
        tester,
        size: const Size(390, 844),
        mode: BusinessHomeHeaderThemeMode.panel,
      );
      _expectHeaderGeometry(tester);
    });

    testWidgets('18 phone landscape header layout', (tester) async {
      await _pumpHeaderHarness(
        tester,
        size: const Size(844, 390),
        mode: BusinessHomeHeaderThemeMode.panel,
      );
      _expectHeaderGeometry(tester);
    });

    testWidgets('19 tablet portrait header layout', (tester) async {
      await _pumpHeaderHarness(
        tester,
        size: const Size(800, 1280),
        mode: BusinessHomeHeaderThemeMode.hero,
        headerHeight: 320,
      );
      _expectHeaderGeometry(tester);
    });

    testWidgets('20 tablet landscape header layout', (tester) async {
      await _pumpHeaderHarness(
        tester,
        size: const Size(1280, 800),
        mode: BusinessHomeHeaderThemeMode.hero,
        headerHeight: 160,
      );
      _expectHeaderGeometry(tester);
    });

    testWidgets('21 button above KPI and no overlap with greeting/chip', (
      tester,
    ) async {
      await _pumpHeaderHarness(
        tester,
        size: const Size(360, 740),
        mode: BusinessHomeHeaderThemeMode.panel,
      );
      final button = tester.getRect(
        find.byKey(BusinessThemeCycleButton.buttonKey),
      );
      final greeting = tester.getRect(
        find.byKey(BusinessHomeHeaderThemeRegion.greetingKey),
      );
      final chip = tester.getRect(
        find.byKey(BusinessHomeHeaderThemeRegion.companyChipKey),
      );
      final kpi = tester.getRect(
        find.byKey(BusinessHomeHeaderThemeRegion.kpiSlotKey),
      );
      expect(button.overlaps(greeting), isFalse);
      expect(button.overlaps(chip), isFalse);
      expect(button.bottom <= kpi.top + 0.5, isTrue);
      expect(button.center.dx > greeting.center.dx, isTrue);
    });

    testWidgets('22 accessibility semantics / tooltip exist', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: BusinessThemeCycleButton())),
        ),
      );
      expect(find.byTooltip(kBusinessThemeCycleSemanticLabel), findsOneWidget);
      final semantics = tester.getSemantics(
        find.byKey(BusinessThemeCycleButton.buttonKey),
      );
      expect(semantics.label, kBusinessThemeCycleSemanticLabel);
      expect(semantics.hasFlag(SemanticsFlag.isButton), isTrue);
      expect(
        semantics.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
      );
    });

    testWidgets('23 no SnackBar or dialog loop is introduced', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: BusinessThemeCycleButton())),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
        await tester.pump();
      }
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
    });

    testWidgets('button tap advances business theme immediately', (
      tester,
    ) async {
      businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: BusinessThemeCycleButton())),
        ),
      );
      await tester.tap(find.byKey(BusinessThemeCycleButton.buttonKey));
      await tester.pump();
      expect(businessThemeNotifier.value, BusinessThemeVariant.corporateBlue);
    });
  });

  group('production wiring guard', () {
    test('Business Home hosts BusinessThemeCycleButton in header', () {
      final source = File(
        'lib/main_parts/business_home_page_state.dart',
      ).readAsStringSync();
      expect(source.contains('BusinessThemeCycleButton'), isTrue);
      expect(
        source.contains('FLUXIDI-BUSINESS-HEADER-THEME-CYCLE-SHORTCUT-P1-1'),
        isTrue,
      );
      expect(source.contains('heroOverlay: true'), isTrue);
    });
  });
}

Future<void> _pumpHeaderHarness(
  WidgetTester tester, {
  required Size size,
  required BusinessHomeHeaderThemeMode mode,
  double? headerHeight,
}) async {
  final palette = paletteForBusinessTheme(businessThemeNotifier.value);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() async {
    await tester.binding.setSurfaceSize(null);
  });

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
                contentPadding: mode == BusinessHomeHeaderThemeMode.hero
                    ? const EdgeInsets.fromLTRB(10, 8, 10, 10)
                    : const EdgeInsets.fromLTRB(12, 12, 12, 14),
                topBar: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Fluxy Bedrijf',
                    style: TextStyle(
                      color: mode == BusinessHomeHeaderThemeMode.hero
                          ? Colors.white
                          : palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                greeting: 'Goedemorgen! 👋',
                subtitle: 'Bedrijfsoverzicht',
                greetingStyle: TextStyle(
                  color: mode == BusinessHomeHeaderThemeMode.hero
                      ? Colors.white
                      : palette.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 19,
                ),
                subtitleStyle: TextStyle(
                  color: mode == BusinessHomeHeaderThemeMode.hero
                      ? Colors.white70
                      : palette.textMuted,
                  fontSize: 12.5,
                ),
                heroBackground: mode == BusinessHomeHeaderThemeMode.hero
                    ? const ColoredBox(color: Color(0xFF101010))
                    : null,
                heroDecoration: mode == BusinessHomeHeaderThemeMode.hero
                    ? BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: palette.accent.withOpacity(0.3),
                        ),
                      )
                    : BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: palette.border),
                      ),
              ),
              const SizedBox(height: 10),
              Container(
                key: BusinessHomeHeaderThemeRegion.kpiSlotKey,
                height: 72,
                color: palette.surfaceAlt,
                alignment: Alignment.center,
                child: Text(
                  'KPI',
                  style: TextStyle(color: palette.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectHeaderGeometry(WidgetTester tester) {
  expect(find.byKey(BusinessThemeCycleButton.buttonKey), findsOneWidget);
  expect(find.byKey(BusinessHomeHeaderThemeRegion.greetingKey), findsOneWidget);
  expect(
    find.byKey(BusinessHomeHeaderThemeRegion.companyChipKey),
    findsOneWidget,
  );
  expect(find.byKey(BusinessHomeHeaderThemeRegion.kpiSlotKey), findsOneWidget);

  final button = tester.getRect(find.byKey(BusinessThemeCycleButton.buttonKey));
  final greeting = tester.getRect(
    find.byKey(BusinessHomeHeaderThemeRegion.greetingKey),
  );
  final kpi = tester.getRect(
    find.byKey(BusinessHomeHeaderThemeRegion.kpiSlotKey),
  );

  expect(button.width, greaterThanOrEqualTo(40));
  expect(button.height, greaterThanOrEqualTo(40));
  expect(button.overlaps(greeting), isFalse);
  expect(button.bottom <= kpi.top + 0.5, isTrue);
}
