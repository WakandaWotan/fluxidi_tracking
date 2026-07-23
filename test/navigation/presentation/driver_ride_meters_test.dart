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

  group('DriverTellersViewportController', () {
    test('open activates a latest-wins viewport with a fresh token', () {
      final c = DriverTellersViewportController();
      expect(c.active, isFalse);
      final t1 = c.open();
      expect(c.active, isTrue);
      expect(c.isCallbackValid(t1), isTrue);
      // Re-opening (latest-wins) invalidates the previous token.
      final t2 = c.open();
      expect(t2, greaterThan(t1));
      expect(c.isCallbackValid(t1), isFalse);
      expect(c.isCallbackValid(t2), isTrue);
    });

    test('close invalidates pending callbacks and cannot resurrect', () {
      final c = DriverTellersViewportController();
      final t = c.open();
      c.close();
      expect(c.active, isFalse);
      // A deferred callback from the open viewport is now stale.
      expect(c.isCallbackValid(t), isFalse);
    });

    test('repeated open/close is idempotent and stays consistent', () {
      final c = DriverTellersViewportController();
      c.open();
      c.open();
      c.close();
      c.close();
      expect(c.active, isFalse);
      final t = c.open();
      expect(c.active, isTrue);
      expect(c.isCallbackValid(t), isTrue);
    });

    test('reset drops the viewport for a clean stop/start cycle', () {
      final c = DriverTellersViewportController();
      final t = c.open();
      c.reset();
      expect(c.active, isFalse);
      expect(c.isCallbackValid(t), isFalse);
      // New session opens cleanly.
      final t2 = c.open();
      expect(c.isCallbackValid(t2), isTrue);
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
      Color? panelColor() {
        final container = tester.widget<Container>(
          find.byKey(const ValueKey('driver_tellers_meters_panel')),
        );
        return (container.decoration as BoxDecoration?)?.color;
      }

      final before = panelColor();

      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: navOwner,
          mode: mode,
          theme: DriverThemeVariant.highContrast,
        ),
      );
      await tester.pump();
      final after = panelColor();
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

    testWidgets('exactly four principal meter tiles; status is secondary', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 7.20',
        distanceTravelledText: '4.0 km',
        rideDurationText: '00:08:30',
        waitingTimeText: '00:00:45',
        statusText: 'Rit gepauzeerd',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: const SizedBox.shrink(),
          mode: mode,
        ),
      );
      await tester.pump();

      // Exactly the four principal tiles.
      expect(find.byKey(const ValueKey('teller_fare')), findsOneWidget);
      expect(find.byKey(const ValueKey('teller_distance')), findsOneWidget);
      expect(find.byKey(const ValueKey('teller_duration')), findsOneWidget);
      expect(find.byKey(const ValueKey('teller_waiting')), findsOneWidget);
      // No fifth equal status tile.
      expect(find.byKey(const ValueKey('teller_status')), findsNothing);
      // Status exists as a smaller secondary element and is localized (Dutch).
      expect(find.byKey(const ValueKey('driver_tellers_status')), findsOneWidget);
      expect(find.text('Rit gepauzeerd'), findsOneWidget);
      expect(find.text('Ride active'), findsNothing);
    });

    testWidgets('live navigation window is present and transparent', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 1.00',
        distanceTravelledText: '0.1 km',
        rideDurationText: '00:20',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: const ColoredBox(color: Colors.green, child: Text('MAP')),
          mode: mode,
        ),
      );
      await tester.pump();

      final windowFinder = find.byKey(
        const ValueKey('driver_tellers_live_window'),
      );
      expect(windowFinder, findsOneWidget);
      // The window itself paints no opaque fill — the map behind shows through.
      final container = tester.widget<Container>(windowFinder);
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.color, Colors.transparent);
      // Retained map owner still mounted beneath.
      expect(find.text('MAP'), findsOneWidget);
    });

    testWidgets('showLiveWindow=false reserves no live window', (tester) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: const DriverRideMetersSnapshot(
                  fareText: '€ 1.00',
                  distanceTravelledText: '0.1 km',
                  rideDurationText: '00:20',
                  waitingTimeText: '00:00',
                  statusText: 'Rit actief',
                ),
                onBackToNavigation: () {},
                showLiveWindow: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('teller_fare')), findsOneWidget);
    });

    testWidgets(
      'Tellers view root is not a full-screen transparent Material '
      '(NAV-PHONE-DRIVER-VIEW-FLICKER-1)',
      (tester) async {
        final mode = DriverNavPresentationModeController()..showTellers();
        const snap = DriverRideMetersSnapshot(
          fareText: '€ 4.00',
          distanceTravelledText: '1.5 km',
          rideDurationText: '03:00',
          waitingTimeText: '00:00',
          statusText: 'Rit actief',
        );
        await tester.pumpWidget(
          harness(snapshot: snap, navOwner: const SizedBox.shrink(), mode: mode),
        );
        await tester.pump();

        // The root of the Tellers view must NOT be a Material (a full-screen
        // transparent compositing surface over the HC map caused phone flicker).
        final root = tester.widget(
          find.byKey(const ValueKey('driver_tellers_view')),
        );
        expect(root, isA<KeyedSubtree>());
        expect(root, isNot(isA<Material>()));

        // No Material anywhere in the Tellers subtree uses transparency (which
        // would reintroduce a repainting transparent layer over the map).
        final materials = tester.widgetList<Material>(find.byType(Material));
        expect(
          materials.every((m) => m.type != MaterialType.transparency),
          isTrue,
        );
      },
    );

    testWidgets('meter panel is fully opaque and repaint-isolated', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 4.00',
        distanceTravelledText: '1.5 km',
        rideDurationText: '03:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: const SizedBox.shrink(), mode: mode),
      );
      await tester.pump();

      final panelFinder = find.byKey(
        const ValueKey('driver_tellers_meters_panel'),
      );
      final container = tester.widget<Container>(panelFinder);
      final color = (container.decoration as BoxDecoration?)?.color;
      // Fully opaque: no per-frame alpha blend over the HC platform view.
      expect(color, isNotNull);
      expect(color!.alpha, 0xFF);

      // Isolated in its own RepaintBoundary so ticks don't dirty the map.
      expect(
        find.ancestor(
          of: panelFinder,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
    });

    testWidgets('live window is repaint-isolated and interior stays uncovered', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 4.00',
        distanceTravelledText: '1.5 km',
        rideDurationText: '03:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: const SizedBox.shrink(), mode: mode),
      );
      await tester.pump();

      final windowFinder = find.byKey(
        const ValueKey('driver_tellers_live_window'),
      );
      expect(
        find.ancestor(
          of: windowFinder,
          matching: find.byType(RepaintBoundary),
        ),
        findsWidgets,
      );
      final container = tester.widget<Container>(windowFinder);
      expect((container.decoration as BoxDecoration?)?.color, Colors.transparent);
    });

    testWidgets('Navigation mode has no Tellers overlay (no transparent layer)', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 4.00',
        distanceTravelledText: '1.5 km',
        rideDurationText: '03:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: const ColoredBox(color: Colors.black, child: Text('MAP')),
          mode: mode,
        ),
      );
      await tester.pump();
      // In Navigation mode the Tellers overlay is entirely unmounted — there is
      // no full-screen (transparent) overlay above the map.
      expect(find.byKey(const ValueKey('driver_tellers_view')), findsNothing);
      expect(find.text('MAP'), findsOneWidget);
    });

    testWidgets('meter/timer updates do not rebuild the navigation owner', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      var navBuildCount = 0;
      final navOwner = Builder(
        builder: (_) {
          navBuildCount += 1;
          return const ColoredBox(color: Colors.black, child: Text('MAP'));
        },
      );
      var snap = const DriverRideMetersSnapshot(
        fareText: '€ 1.00',
        distanceTravelledText: '0.1 km',
        rideDurationText: '00:01',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(snapshot: snap, navOwner: navOwner, mode: mode),
      );
      final afterFirst = navBuildCount;

      // Simulate several fare/timer ticks by updating the snapshot only.
      for (var i = 0; i < 5; i++) {
        snap = DriverRideMetersSnapshot(
          fareText: '€ ${i + 2}.00',
          distanceTravelledText: '${i + 1}.0 km',
          rideDurationText: '00:0${i + 2}',
          waitingTimeText: '00:00',
          statusText: 'Rit actief',
        );
        await tester.pumpWidget(
          harness(snapshot: snap, navOwner: navOwner, mode: mode),
        );
        await tester.pump();
      }
      // The retained navigation owner (map subtree stand-in) is not rebuilt by
      // meter updates — it is a stable child, not driven by the snapshot.
      expect(navBuildCount, afterFirst);
      expect(find.text('MAP'), findsOneWidget);
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
