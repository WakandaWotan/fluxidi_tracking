import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/company/driver_management_native_page.dart';
import 'driver_management_native_test_support.dart';

void main() {
  setUpAll(() async {
    for (final f in [
      (
        'Roboto',
        'D:/Projecten/_flutter_work/fluxidi_diva_driver_management/features/diva-driver-management/web/partner-assets/roboto-regular.ttf',
      ),
      (
        'MaterialIcons',
        'C:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    ]) {
      await (FontLoader(f.$1)..addFont(
            Future.value(ByteData.sublistView(File(f.$2).readAsBytesSync())),
          ))
          .load();
    }
  });
  Future<void> setup(
    WidgetTester tester,
    NativeDriverFixture fixture, {
    ValueNotifier<Object?>? session,
    Object? Function()? sessionKey,
    ValueNotifier<BusinessThemeVariant>? theme,
    double width = 390,
    double height = 844,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifier = session ?? ValueNotifier<Object?>(Object());
    if (session == null) addTearDown(notifier.dispose);
    final variant =
        theme ?? ValueNotifier(BusinessThemeVariant.cleanProfessional);
    if (theme == null) addTearDown(variant.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('unified-capture'),
          child: ValueListenableBuilder(
            valueListenable: variant,
            builder: (_, v, __) => DriverManagementNativePage(
              connect: () async => fixture.repository(),
              session: notifier,
              sessionKey: sessionKey,
              palette: paletteForBusinessTheme(v),
              openLegacy: () {},
              manageDriver: (_) async {},
              addDriver: () async {},
              shareCsv: (_) async {},
              avatar: (id, size) => SizedBox(
                width: size,
                height: size,
                child: const Icon(Icons.person_outline),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tab(WidgetTester tester, String name) async {
    final finder = find.byKey(
      ValueKey(
        'management-tab-${{'Chauffeurs': 0, 'Partnerbedrijven': 1, 'Afrekeningen': 2}[name]}',
      ),
    );
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('unified-capture')),
    );
    await tester.runAsync(() async {
      final context = tester.element(
        find.byKey(const ValueKey('unified-capture')),
      );
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        await precacheImage(image.image, context);
      }
    });
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1),
          png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${Platform.environment['FLUXIDI_MANAGEMENT_CAPTURE_DIR'] ?? 'D:/Projecten/outputs/business98_final_management_20261013'}/$name.png',
      ).writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final v in [
    BusinessThemeVariant.cleanProfessional,
    BusinessThemeVariant.corporateBlue,
    BusinessThemeVariant.executiveGold,
  ]) {
    for (final size in [
      (320.0, 740.0),
      (390.0, 844.0),
      (844.0, 390.0),
      (800.0, 1280.0),
      (1280.0, 800.0),
    ]) {
      testWidgets('One responsive native environment ${v.name} $size', (
        tester,
      ) async {
        final fixture = NativeDriverFixture(), theme = ValueNotifier(v);
        addTearDown(theme.dispose);
        await setup(
          tester,
          fixture,
          theme: theme,
          width: size.$1,
          height: size.$2,
        );
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(
          fixture.requests.last.queryParameters.containsKey('status'),
          isFalse,
          reason: 'All includes offline drivers',
        );
        expect(find.byKey(const ValueKey('native-driver-add')), findsOneWidget);
        expect(find.text(fixture.company), findsNothing);
        final driverCalls = fixture.requests
            .where((u) => u.path == '/driver-management/api/drivers')
            .length;
        await capture(
          tester,
          'chauffeurs-${v.name}-${size.$1.toInt()}x${size.$2.toInt()}',
        );
        await tab(tester, 'Partnerbedrijven');
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(
          find.byKey(const ValueKey('native-partners-page')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('partner-add')), findsOneWidget);
        expect(find.text('Nog geen partnerbedrijven'), findsOneWidget);
        expect(find.byKey(const ValueKey('native-driver-add')), findsNothing);
        await capture(
          tester,
          'partners-${v.name}-${size.$1.toInt()}x${size.$2.toInt()}',
        );
        await tester.tap(find.byKey(const ValueKey('partner-add')));
        await tester.pumpAndSettle();
        expect(find.text('Zelfstandige chauffeur'), findsOneWidget);
        expect(find.text('Onderaannemersbedrijf'), findsOneWidget);
        expect(find.text('Werknemer'), findsNothing);
        expect(find.byKey(const ValueKey('partner-save')), findsOneWidget);
        await capture(
          tester,
          'partner-toevoegen-${v.name}-${size.$1.toInt()}x${size.$2.toInt()}',
        );
        await tester.enterText(
          find.byKey(const ValueKey('partner-business-name')),
          'Niet opgeslagen testinvoer',
        );
        await tester.tap(find.byTooltip('Vernieuwen'));
        await tester.pumpAndSettle();
        expect(
          find.text('Niet opgeslagen testinvoer'),
          findsOneWidget,
          reason: 'Header refresh must retain unsaved partner input',
        );
        theme.value = v == BusinessThemeVariant.cleanProfessional
            ? BusinessThemeVariant.corporateBlue
            : BusinessThemeVariant.cleanProfessional;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        theme.value = v;
        await tester.pumpAndSettle();
        await tab(tester, 'Afrekeningen');
        expect(
          find.byKey(const ValueKey('management-payments-title')),
          findsOneWidget,
        );
        expect(find.text('Nu betalen'), findsNothing);
        expect(find.textContaining('€'), findsNothing);
        expect(find.text('Nog niet beschikbaar'), findsWidgets);
        await capture(
          tester,
          'afrekeningen-${v.name}-${size.$1.toInt()}x${size.$2.toInt()}',
        );
        final financialReads = fixture.requests.length;
        final paymentManagement = find.byKey(
          const ValueKey('management-payments-manage'),
        );
        await tester.scrollUntilVisible(
          paymentManagement,
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('management-payments')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(paymentManagement);
        await tester.pumpAndSettle();
        expect(find.text('Betalingen beheren'), findsOneWidget);
        expect(find.textContaining('€'), findsNothing);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('management-payout-blocked')),
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('management-payment-selection')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('management-payout-blocked')),
              )
              .onPressed,
          isNull,
        );
        expect(
          fixture.requests.length,
          financialReads,
          reason:
              'Unproven financial UI must not request payouts, provider data or writes',
        );
        await capture(
          tester,
          'betalingen-${v.name}-${size.$1.toInt()}x${size.$2.toInt()}',
        );
        await tab(tester, 'Chauffeurs');
        expect(
          fixture.requests
              .where((u) => u.path == '/driver-management/api/drivers')
              .length,
          driverCalls,
          reason:
              'Tab changes keep the authenticated roster, no login or blank reload',
        );
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('native-driver-count')),
          200,
          scrollable: find
              .byWidgetPredicate(
                (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
              )
              .first,
        );
        expect(
          find.byKey(const ValueKey('native-driver-count')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        if (size.$1 >= 900) {
          final card = find.byKey(
            const ValueKey('native-driver-detail-driver-1'),
          );
          await tester.scrollUntilVisible(
            card,
            100,
            scrollable: find
                .byWidgetPredicate(
                  (w) =>
                      w is Scrollable && w.axisDirection == AxisDirection.down,
                )
                .first,
          );
          await tester.tap(card);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('management-list')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('native-driver-detail-title')),
            findsOneWidget,
          );
          await capture(tester, 'tablet-lijst-en-details-${v.name}');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      });
    }
  }
  for (final v in [
    BusinessThemeVariant.cleanProfessional,
    BusinessThemeVariant.corporateBlue,
  ]) {
    for (final scale in [1.4, 1.8]) {
      testWidgets('Small phone with enlarged text ${v.name} $scale', (
        tester,
      ) async {
        final theme = ValueNotifier(v);
        addTearDown(theme.dispose);
        await setup(
          tester,
          NativeDriverFixture(),
          theme: theme,
          width: 320,
          height: 740,
          textScale: scale,
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('management-action-codes')),
        );
        expect(
          find.byKey(const ValueKey('management-action-documents')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('management-action-vehicles')),
          findsOneWidget,
        );
        await capture(tester, 'large-text-${v.name}-$scale');
        for (final page in ['Partnerbedrijven', 'Afrekeningen']) {
          await tab(tester, page);
          if (page == 'Partnerbedrijven') {
            final title = tester.renderObject<RenderParagraph>(find.text('Partnerbedrijven'));
            expect(title.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: 'Partnerbedrijven'.length)), hasLength(1),
              reason: 'The title must not split the word Partnerbedrijven');
          }
          if (page == 'Afrekeningen') {
            final words = find.text('Nog niet beschikbaar');
            for (var i = 0; i < words.evaluate().length; i++) {
              final paragraph = tester.renderObject<RenderParagraph>(words.at(i));
              expect(paragraph.getBoxesForSelection(const TextSelection(baseOffset: 9, extentOffset: 20)), hasLength(1),
                reason: 'The word beschikbaar must remain intact');
            }
          }
          final first = find.byKey(ValueKey(page == 'Partnerbedrijven'
              ? 'partner-metric-Partners' : 'management-financial-metric-Open te betalen'));
          final second = find.byKey(ValueKey(page == 'Partnerbedrijven'
              ? 'partner-metric-Gekoppelde chauffeurs' : 'management-financial-metric-Klaar voor uitbetaling'));
          expect(tester.getTopLeft(first).dy, closeTo(tester.getTopLeft(second).dy, 1));
          expect(tester.getTopLeft(first).dx, lessThan(tester.getTopLeft(second).dx));
          await capture(tester, 'compact-${page == 'Partnerbedrijven' ? 'partners' : 'afrekeningen'}-${v.name}-$scale');
          expect(tester.takeException(), isNull);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'Same-scope bootstrap and backgrounding do not invalidate the session',
    (tester) async {
      final f = NativeDriverFixture(),
          notifier = ValueNotifier<Object?>(Object());
      addTearDown(notifier.dispose);
      await setup(
        tester,
        f,
        session: notifier,
        sessionKey: () =>
            ('own-company', 'companyAdmin', 'same-valid-credential'),
      );
      final requests = f.requests.length;
      notifier.value = Object();
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(f.requests, hasLength(requests));
      expect(find.byKey(const ValueKey('native-driver-error')), findsNothing);
      expect(find.byKey(const ValueKey('native-driver-count')), findsOneWidget);
      f.current = false;
      notifier.value = Object();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('native-driver-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('native-driver-count')), findsNothing);
    },
  );
  testWidgets('Late refresh failure cannot clear a renewed valid session', (
    tester,
  ) async {
    final f = NativeDriverFixture();
    final notifier = ValueNotifier<Object?>(Object());
    addTearDown(notifier.dispose);
    Object key = ('own-company', 'companyAdmin', 'old-credential');
    await setup(tester, f, session: notifier, sessionKey: () => key);
    final delayed = Completer<bool>();
    var first = true;
    f.sessionProbe = () {
      if (first) {
        first = false;
        return delayed.future;
      }
      return Future.value(true);
    };
    await tester.tap(find.byTooltip('Vernieuwen'));
    await tester.pump();
    key = ('own-company', 'companyAdmin', 'renewed-credential');
    notifier.value = Object();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('native-driver-count')), findsOneWidget);
    delayed.complete(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('native-driver-error')), findsNothing);
    expect(find.byKey(const ValueKey('native-driver-count')), findsOneWidget);
  });
  testWidgets(
    'Tenant change clears partners and drivers before new authentication',
    (tester) async {
      final f = NativeDriverFixture(),
          notifier = ValueNotifier<Object?>(Object());
      addTearDown(notifier.dispose);
      Object key = ('company-a', 'companyAdmin', 'credential-a');
      await setup(tester, f, session: notifier, sessionKey: () => key);
      await tab(tester, 'Partnerbedrijven');
      f.current = false;
      key = ('company-b', 'companyAdmin', 'credential-b');
      notifier.value = Object();
      await tester.pump();
      expect(find.byKey(const ValueKey('native-partners-page')), findsNothing);
      expect(find.byKey(const ValueKey('native-driver-count')), findsNothing);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('native-driver-error')), findsOneWidget);
    },
  );
  testWidgets(
    'Repeated main navigation preserves own roster and blocks financial selection',
    (tester) async {
      final f = NativeDriverFixture();
      await setup(tester, f);
      final driverReads = f.requests
          .where((u) => u.path == '/driver-management/api/drivers')
          .length;
      for (var cycle = 0; cycle < 4; cycle++) {
        await tab(tester, 'Partnerbedrijven');
        expect(
          find.byKey(const ValueKey('native-partners-page')),
          findsOneWidget,
        );
        expect(find.text(f.driver['display_name'] as String), findsNothing);
        await tab(tester, 'Afrekeningen');
        final manage = find.byKey(const ValueKey('management-payments-manage'));
        await tester.scrollUntilVisible(
          manage,
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('management-payments')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pumpAndSettle();
        await tester.tap(manage);
        await tester.pumpAndSettle();
        final selection = find.byKey(
          const ValueKey('management-payment-select-all-blocked'),
        );
        await tester.scrollUntilVisible(
          selection,
          150,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('management-payment-selection')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(tester.widget<CheckboxListTile>(selection).onChanged, isNull);
        expect(find.textContaining('€'), findsNothing);
        final back = find.byKey(const ValueKey('management-payments-back'));
        await tester.scrollUntilVisible(
          back,
          -200,
          scrollable: find
              .descendant(
                of: find.byKey(const ValueKey('management-payment-selection')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.tap(back);
        await tester.pumpAndSettle();
        await tab(tester, 'Chauffeurs');
        expect(
          find.byKey(const ValueKey('native-driver-count')),
          findsOneWidget,
        );
        expect(find.byType(AppBar), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byKey(const ValueKey('native-driver-error')), findsNothing);
      }
      expect(
        f.requests
            .where((u) => u.path == '/driver-management/api/drivers')
            .length,
        driverReads,
      );
      expect(
        f.requests.any(
          (u) => RegExp('settlement|payout|refund|payment').hasMatch(u.path),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
