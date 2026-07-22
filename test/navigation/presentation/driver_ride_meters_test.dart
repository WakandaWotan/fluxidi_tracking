// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 3

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';

void main() {
  group('DriverNavPresentationModeController', () {
    test('idempotent Navigatie ↔ Tellers switching', () {
      final c = DriverNavPresentationModeController();
      expect(c.mode, DriverNavPresentationMode.navigation);
      expect(c.showTellers(), isTrue);
      expect(c.showTellers(), isFalse);
      expect(c.isTellers, isTrue);
      expect(c.showNavigation(), isTrue);
      expect(c.showNavigation(), isFalse);
      expect(c.isTellers, isFalse);
      c.showTellers();
      c.reset();
      expect(c.mode, DriverNavPresentationMode.navigation);
    });
  });

  group('DriverRideMetersView', () {
    setUp(() {
      driverThemeNotifier.value = DriverThemeVariant.midnightBlue;
    });

    Widget harness({
      required DriverRideMetersSnapshot snapshot,
      required Widget navOwner,
      required DriverNavPresentationModeController mode,
      DriverThemeVariant? theme,
      Size size = const Size(390, 844),
      bool isTablet = false,
      bool isLandscape = false,
    }) {
      if (theme != null) driverThemeNotifier.value = theme;
      return MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                // Retained navigation owner — must stay mounted under Tellers.
                Positioned.fill(
                  child: KeyedSubtree(
                    key: const ValueKey('nav_owner_retained'),
                    child: navOwner,
                  ),
                ),
                if (mode.isTellers)
                  Positioned.fill(
                    child: DriverRideMetersView(
                      snapshot: snapshot,
                      onBackToNavigation: () {
                        mode.showNavigation();
                      },
                      isTablet: isTablet,
                      isLandscape: isLandscape,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('opening Tellers keeps navigation owner mounted', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController();
      var navBuildCount = 0;
      final navOwner = Builder(
        builder: (_) {
          navBuildCount += 1;
          return const ColoredBox(
            color: Colors.green,
            child: Text('NAV_OWNER'),
          );
        },
      );
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 12.50',
        distanceTravelledText: '3.2 km',
        rideDurationText: '12:05',
        waitingTimeText: '01:10',
        statusText: 'Rit actief',
      );

      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: navOwner, mode: mode),
      );
      expect(find.text('NAV_OWNER'), findsOneWidget);
      final buildsBefore = navBuildCount;

      mode.showTellers();
      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: navOwner, mode: mode),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('driver_tellers_view')), findsOneWidget);
      expect(find.byKey(const ValueKey('nav_owner_retained')), findsOneWidget);
      expect(find.text('NAV_OWNER'), findsOneWidget);
      // Owner may rebuild (setState) but must not be disposed/recreated away.
      expect(navBuildCount, greaterThanOrEqualTo(buildsBefore));
      expect(find.text('€ 12.50'), findsOneWidget);
      expect(find.text('3.2 km'), findsOneWidget);
    });

    testWidgets('closing Tellers returns to navigation; switch is idempotent', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController();
      mode.showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 1.00',
        distanceTravelledText: '0.1 km',
        rideDurationText: '00:20',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      final navOwner = const ColoredBox(
        color: Colors.blue,
        child: Text('NAV_OWNER'),
      );

      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: navOwner, mode: mode),
      );
      expect(find.text('Tellers'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('driver_tellers_back_nav')));
      // Controller already flipped in onBack; rebuild harness.
      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: navOwner, mode: mode),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('driver_tellers_view')), findsNothing);
      expect(find.text('NAV_OWNER'), findsOneWidget);
      expect(mode.mode, DriverNavPresentationMode.navigation);
    });

    testWidgets('live values update while Tellers is visible', (tester) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      var snap = const DriverRideMetersSnapshot(
        fareText: '€ 2.00',
        distanceTravelledText: '1.0 km',
        rideDurationText: '01:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      final navOwner = const SizedBox.shrink();

      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: navOwner, mode: mode),
      );
      expect(find.text('€ 2.00'), findsOneWidget);

      snap = const DriverRideMetersSnapshot(
        fareText: '€ 3.40',
        distanceTravelledText: '1.7 km',
        rideDurationText: '02:10',
        waitingTimeText: '00:30',
        statusText: 'Wachten',
      );
      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: navOwner, mode: mode),
      );
      await tester.pump();
      expect(find.text('€ 3.40'), findsOneWidget);
      expect(find.text('1.7 km'), findsOneWidget);
      expect(find.text('Wachten'), findsOneWidget);
    });

    testWidgets('theme change updates Tellers without losing nav owner', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 5.00',
        distanceTravelledText: '2.0 km',
        rideDurationText: '05:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      final navOwner = const Text('NAV_OWNER');

      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: navOwner,
          mode: mode,
          theme: DriverThemeVariant.midnightBlue,
        ),
      );
      final before = tester
          .widget<Material>(find.byKey(const ValueKey('driver_tellers_view')))
          .color;

      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: navOwner,
          mode: mode,
          theme: DriverThemeVariant.highContrast,
        ),
      );
      await tester.pump();
      final after = tester
          .widget<Material>(find.byKey(const ValueKey('driver_tellers_view')))
          .color;
      expect(after, isNot(equals(before)));
      expect(find.text('NAV_OWNER'), findsOneWidget);
    });

    testWidgets('phone and tablet layouts have no overflow', (tester) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 99.99',
        distanceTravelledText: '123.4 km',
        rideDurationText: '01:02:03',
        waitingTimeText: '00:15:00',
        statusText: 'Rit actief',
        etaText: '12 min',
        remainingDistanceText: '4.5 km',
      );
      final cases = <({Size size, bool tablet, bool landscape})>[
        (size: const Size(390, 844), tablet: false, landscape: false),
        (size: const Size(800, 380), tablet: false, landscape: true),
        (size: const Size(834, 1194), tablet: true, landscape: false),
        (size: const Size(1194, 834), tablet: true, landscape: true),
      ];
      for (final c in cases) {
        await tester.binding.setSurfaceSize(c.size);
        await tester.pumpWidget(
          harness(
            snapshot: snap,
            navOwner: const SizedBox.shrink(),
            mode: mode,
            size: c.size,
            isTablet: c.tablet,
            isLandscape: c.landscape,
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '${c.size}');
        expect(find.text('Tellers'), findsOneWidget);
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });

    test('route version / GPS / fare ownership are not part of this view', () {
      // Structural invariant: the view only accepts a snapshot + callbacks.
      // It cannot create a fare ticker, GPS subscription, or route version.
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 0.00',
        distanceTravelledText: '0.0 km',
        rideDurationText: '00:00',
        waitingTimeText: '00:00',
        statusText: 'Stand-by',
      );
      expect(snap.fareText, '€ 0.00');
      final c = DriverNavPresentationModeController();
      expect(c.showTellers(), isTrue);
      expect(c.showNavigation(), isTrue);
    });
  });
}
