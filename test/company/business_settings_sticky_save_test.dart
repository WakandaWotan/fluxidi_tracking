import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/business_settings_page.dart';
import 'package:fluxidi_tracking/business_settings_sticky_save.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/business_theme_store.dart';

Widget _pageHost({
  required Size size,
  required EdgeInsets viewPadding,
  EdgeInsets? padding,
  double textScale = 1.0,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: size,
        padding: padding ?? EdgeInsets.zero,
        viewPadding: viewPadding,
        textScaler: TextScaler.linear(textScale),
      ),
      // Outer Scaffold lets the page's missing-scope snackbar land during
      // the first build without aborting BusinessSettingsPage itself.
      child: const Scaffold(body: BusinessSettingsPage()),
    ),
  );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  required Size size,
  required EdgeInsets viewPadding,
  EdgeInsets? padding,
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _pageHost(
      size: size,
      viewPadding: viewPadding,
      padding: padding,
      textScale: textScale,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void _expectButtonAboveSystemInset({
  required WidgetTester tester,
  required Size size,
  required double systemBottom,
}) {
  final button = tester.getRect(
    find.byKey(kBusinessSettingsPublishEverythingButtonKey),
  );
  final bar = tester.getRect(find.byKey(kBusinessSettingsStickySaveBarKey));
  final label = tester.getRect(find.text('Alles opslaan en publiceren'));
  final icon = tester.getRect(find.byIcon(Icons.save));

  expect(button.bottom, lessThanOrEqualTo(size.height - systemBottom));
  expect(
    button.bottom + 12,
    lessThanOrEqualTo(size.height - systemBottom + 0.5),
  );
  expect(button.height, greaterThanOrEqualTo(52));
  expect(button.height, lessThanOrEqualTo(120));

  expect(label.left, greaterThanOrEqualTo(button.left - 0.5));
  expect(label.right, lessThanOrEqualTo(button.right + 0.5));
  expect(label.top, greaterThanOrEqualTo(button.top - 0.5));
  expect(label.bottom, lessThanOrEqualTo(button.bottom + 0.5));
  expect(icon.left, greaterThanOrEqualTo(button.left - 0.5));
  expect(icon.right, lessThanOrEqualTo(button.right + 0.5));
  expect(icon.top, greaterThanOrEqualTo(button.top - 0.5));
  expect(icon.bottom, lessThanOrEqualTo(button.bottom + 0.5));

  expect(bar.bottom, lessThanOrEqualTo(size.height + 0.5));
  expect(button.bottom, lessThanOrEqualTo(bar.bottom));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appLanguageNotifier.value = AppLanguage.nl;
    businessThemeNotifier.value = BusinessThemeVariant.executiveGold;
  });

  test('inset uses viewPadding plus 12, never a device constant', () {
    expect(
      businessSettingsListBottomReserve(
        viewPaddingBottom: 48,
        stickyBarHeight: 54,
      ),
      114,
    );
    expect(
      File('lib/business_settings_page.dart').readAsStringSync().contains(
        'bottomNavigationBar: BusinessSettingsStickySaveBar(',
      ),
      isTrue,
    );
    expect(
      File('lib/business_settings_page.dart').readAsStringSync().contains(
        '_isActiveStepMode ? _saveAndContinue : _save',
      ),
      isTrue,
    );
    expect(
      File(
        'lib/business_settings_sticky_save.dart',
      ).readAsStringSync().contains('MediaQuery.viewPaddingOf(context)'),
      isTrue,
    );
  });

  testWidgets(
    'real Bedrijfsinstellingen page keeps publish above tablet portrait nav',
    (tester) async {
      const size = Size(800, 1280);
      const nav = EdgeInsets.only(bottom: 48);
      await _pumpSettings(tester, size: size, viewPadding: nav);
      expect(find.byType(BusinessSettingsPage), findsOneWidget);
      expect(find.byType(BusinessSettingsStickySaveBar), findsOneWidget);
      expect(find.text('Alles opslaan en publiceren'), findsOneWidget);
      _expectButtonAboveSystemInset(
        tester: tester,
        size: size,
        systemBottom: nav.bottom,
      );
    },
  );

  testWidgets(
    'real Bedrijfsinstellingen page keeps publish above tablet landscape nav',
    (tester) async {
      const size = Size(1280, 800);
      const nav = EdgeInsets.only(bottom: 48);
      await _pumpSettings(tester, size: size, viewPadding: nav);
      _expectButtonAboveSystemInset(
        tester: tester,
        size: size,
        systemBottom: nav.bottom,
      );
    },
  );

  testWidgets(
    'phone gesture inset keeps the same sticky bar above the system nav',
    (tester) async {
      const size = Size(390, 844);
      const gesture = EdgeInsets.only(bottom: 24);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: size,
              padding: EdgeInsets.zero,
              viewPadding: gesture,
            ),
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: BusinessSettingsStickySaveBar(
                label: 'Alles opslaan en publiceren',
                busy: false,
                onPressed: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      _expectButtonAboveSystemInset(
        tester: tester,
        size: size,
        systemBottom: gesture.bottom,
      );
    },
  );

  testWidgets(
    'label, icon, tap target and last card stay clear of the sticky footer',
    (tester) async {
      const size = Size(800, 1280);
      const nav = EdgeInsets.only(bottom: 48);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await _pumpSettings(tester, size: size, viewPadding: nav);

      final buttonFinder = find.byKey(
        kBusinessSettingsPublishEverythingButtonKey,
      );
      final button = tester.widget<FilledButton>(buttonFinder);
      expect(button.onPressed, isNotNull);

      await tester.tap(buttonFinder);
      await tester.pump();
      expect(tester.takeException(), isNull);

      final lastTitle = find.text('Limousineaanbod en prijzen');
      await tester.scrollUntilVisible(lastTitle, 500);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final lastCard = tester.getRect(lastTitle);
      final bar = tester.getRect(find.byKey(kBusinessSettingsStickySaveBarKey));
      expect(lastCard.bottom, lessThanOrEqualTo(bar.top + 1));
    },
  );

  testWidgets('large text scale does not overflow the sticky publish button', (
    tester,
  ) async {
    const size = Size(390, 844);
    const nav = EdgeInsets.only(bottom: 48);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            padding: nav,
            viewPadding: nav,
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: BusinessSettingsStickySaveBar(
              label: 'Alles opslaan en publiceren',
              busy: false,
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    _expectButtonAboveSystemInset(
      tester: tester,
      size: size,
      systemBottom: nav.bottom,
    );
    expect(find.text('Alles opslaan en publiceren'), findsOneWidget);
  });

  testWidgets('isolated bar still forwards the same onPressed callback', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(800, 1280),
            padding: EdgeInsets.only(bottom: 48),
            viewPadding: EdgeInsets.only(bottom: 48),
          ),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: BusinessSettingsStickySaveBar(
              label: 'Alles opslaan en publiceren',
              busy: false,
              onPressed: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final button = tester.getRect(
      find.byKey(kBusinessSettingsPublishEverythingButtonKey),
    );
    await tester.tapAt(button.center);
    await tester.tapAt(Offset(button.left + 8, button.center.dy));
    await tester.tapAt(Offset(button.right - 8, button.center.dy));
    await tester.pump();
    expect(taps, 3);
    expect(tester.takeException(), isNull);
  });
}
