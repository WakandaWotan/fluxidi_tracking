import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/driver_management_native_page.dart';
import 'driver_management_native_test_support.dart';

void main() {
  setUpAll(() async {
    final icons = File(
      'C:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytesSync();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    for (final entry in [('Roboto', 'roboto-regular.ttf')]) {
      final bytes = File(
        'D:/Projecten/_flutter_work/fluxidi_diva_driver_management/features/diva-driver-management/web/partner-assets/${entry.$2}',
      ).readAsBytesSync();
      await (FontLoader(
        entry.$1,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  Future<void> pump(
    WidgetTester tester,
    NativeDriverFixture fixture, {
    double width = 390,
    double height = 844,
    double scale = 1,
    ValueNotifier<Object?>? session,
    VoidCallback? legacy,
    Future<void> Function(String)? manage,
    Future<void> Function(String)? csv,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notifier = session ?? ValueNotifier<Object?>(Object());
    if (session == null) addTearDown(notifier.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          fontFamily: 'Roboto',
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFFD4AF37),
            brightness: Brightness.dark,
            surface: const Color(0xFF1F1F1F),
          ),
          scaffoldBackgroundColor: Colors.black,
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: const ValueKey('native-preview'),
          child: DriverManagementNativePage(
            connect: () async => fixture.repository(),
            session: notifier,
            openLegacy: legacy ?? () {},
            manageDriver: manage ?? (_) async {},
            shareCsv: csv ?? (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final context = tester.element(
        find.byKey(const ValueKey('native-preview')),
      );
      for (final image in tester.widgetList<Image>(find.byType(Image))) {
        await precacheImage(image.image, context);
      }
    });
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final scroll = find
        .byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        )
        .first;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      finder,
      100,
      scrollable: scroll,
      maxScrolls: 40,
    );
    await tester.pumpAndSettle();
  }

  for (final size in [
    (320.0, 740.0, 1.0),
    (390.0, 844.0, 1.0),
    (844.0, 390.0, 1.0),
    (800.0, 1280.0, 1.0),
    (1280.0, 800.0, 1.0),
    (390.0, 844.0, 2.0),
    (800.0, 1280.0, 2.0),
  ]) {
    testWidgets(
      'Recovered native design no overflow ${size.$1}x${size.$2} scale${size.$3}',
      (tester) async {
        await pump(
          tester,
          NativeDriverFixture(),
          width: size.$1,
          height: size.$2,
          scale: size.$3,
        );
        expect(
          find.byKey(const ValueKey('native-driver-management-page')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        final scroll = find
            .byWidgetPredicate(
              (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
            )
            .first;
        for (var i = 0; i < 5; i++) {
          await tester.drag(scroll, const Offset(0, -450));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        final count = find.byKey(const ValueKey('native-driver-count'));
        await reveal(tester, count);
        expect(count, findsOneWidget);
        // Capture the actually rendered Flutter screen using the original fonts.
        await tester.drag(scroll, const Offset(0, 5000));
        await tester.pumpAndSettle();
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('native-preview')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = Directory(
            'D:/Projecten/outputs/business98_final_management_20261013/native-renders',
          )..createSync(recursive: true);
          File(
            '${out.path}/native-${size.$1.toInt()}x${size.$2.toInt()}-scale${size.$3}.png',
          ).writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      },
    );
  }

  testWidgets(
    'Search, combined filters, sorting, pagination and CSV stay on original host contract',
    (tester) async {
      final f = NativeDriverFixture();
      String? exported;
      await pump(tester, f, csv: (csv) async => exported = csv);
      await tester.enterText(
        find.byKey(const ValueKey('native-driver-search')),
        'Tesla',
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(f.requests.last.queryParameters['q'], 'Tesla');
      await reveal(tester, find.byKey(const ValueKey('native-driver-filters')));
      await tester.tap(find.text('Meer filters'));
      await tester.pumpAndSettle();
      await reveal(tester, find.byKey(const ValueKey('native-filter-status')));
      await tester.tap(find.byKey(const ValueKey('native-filter-status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Offline').last);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(f.requests.last.queryParameters['status'], 'offline');
      expect(f.requests.last.queryParameters['q'], 'Tesla');
      await reveal(tester, find.byKey(const ValueKey('native-filter-sort')));
      await tester.tap(find.byKey(const ValueKey('native-filter-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Laatst gezien').last);
      await tester.pumpAndSettle();
      expect(f.requests.last.queryParameters['sort'], 'last_seen');
      await reveal(tester, find.byKey(const ValueKey('native-driver-next')));
      await tester.tap(find.byKey(const ValueKey('native-driver-next')));
      await tester.pumpAndSettle();
      expect(f.requests.last.queryParameters['cursor'], 'next-page');
      await reveal(tester, find.text('Export CSV'));
      await tester.tap(find.text('Export CSV'));
      await tester.pumpAndSettle();
      expect(exported, contains(f.company));
      expect(f.requests.last.queryParameters.containsKey('cursor'), isFalse);
      expect(f.requests.last.queryParameters['q'], 'Tesla');
      expect(
        f.requests.any(
          (u) => RegExp('settlements|partners|import').hasMatch(u.path),
        ),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Details and existing docs/code/QR/vehicle actions stay within the app',
    (tester) async {
      final f = NativeDriverFixture();
      String? managed;
      var legacy = false;
      await pump(
        tester,
        f,
        manage: (id) async => managed = id,
        legacy: () => legacy = true,
      );
      await reveal(
        tester,
        find.byKey(const ValueKey('native-driver-detail-driver-1')),
      );
      await tester.tap(
        find.byKey(const ValueKey('native-driver-detail-driver-1')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('native-driver-detail-title')),
        findsOneWidget,
      );
      expect(find.text('Status en contact'), findsOneWidget);
      expect(find.text('Chauffeur-id'), findsNothing);
      await reveal(
        tester,
        find.byKey(const ValueKey('native-driver-existing-actions')),
      );
      await tester.tap(
        find.byKey(const ValueKey('native-driver-existing-actions')),
      );
      await tester.pumpAndSettle();
      expect(managed, 'driver-1');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Chauffeurs'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('native-driver-legacy')), findsNothing);
      expect(legacy, isFalse);
    },
  );

  testWidgets('Changing company clears visible chauffeur details immediately', (
    tester,
  ) async {
    final f = NativeDriverFixture();
    final session = ValueNotifier<Object?>(Object());
    addTearDown(session.dispose);
    await pump(tester, f, session: session);
    await reveal(
      tester,
      find.byKey(const ValueKey('native-driver-detail-driver-1')),
    );
    await tester.tap(
      find.byKey(const ValueKey('native-driver-detail-driver-1')),
    );
    await tester.pumpAndSettle();
    f.current = false;
    session.value = Object();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('native-driver-detail-title')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('native-driver-error')), findsOneWidget);
    expect(find.text(f.driver['display_name']), findsNothing);
  });

  testWidgets('New company empty state and unavailable finance are honest', (
    tester,
  ) async {
    await pump(tester, NativeDriverFixture()..empty = true);
    await reveal(tester, find.byKey(const ValueKey('native-driver-count')));
    expect(find.text('0 chauffeurs'), findsOneWidget);
    expect(
      find.text('Geen chauffeurs gevonden voor deze filters.'),
      findsOneWidget,
    );
    expect(find.textContaining('€'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
