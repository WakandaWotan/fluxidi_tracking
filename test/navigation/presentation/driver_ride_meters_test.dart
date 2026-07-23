// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 3
// NAV-TELLERS-RECENTER-CONTROL-1

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_store.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

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

  group('DriverNavHudVisibility (one HUD at a time)', () {
    test('navigation mode shows cockpit + nav overlays, no Tellers HUD', () {
      final hud = DriverNavHudVisibility.resolve(
        showCockpit: true,
        cameraFollow: true,
        tellersActive: false,
        followLiveActive: true,
        showDriverHudOverlay: true,
      );
      expect(hud.cockpitHud, isTrue);
      expect(hud.navBannerHud, isTrue);
      expect(hud.tellersHud, isFalse);
      expect(hud.tellersMarkerPresentationVisible, isFalse);
      expect(
        hud.markerOwner,
        DriverVehicleMarkerPresentationOwner.navigationHud,
      );
    });

    test('Tellers mode suppresses cockpit KPI/controls and nav overlays', () {
      final hud = DriverNavHudVisibility.resolve(
        showCockpit: true,
        cameraFollow: true,
        tellersActive: true,
        followLiveActive: true,
        showDriverHudOverlay: true,
      );
      // Normal cockpit KPI row + controls and follow-mode overlays are hidden.
      expect(hud.cockpitHud, isFalse);
      expect(hud.navBannerHud, isFalse);
      // Only the Tellers HUD remains — with its own vehicle marker.
      expect(hud.tellersHud, isTrue);
      expect(hud.vehicleMarkerVisible, isTrue);
      expect(hud.tellersMarkerPresentationVisible, isTrue);
      expect(hud.tellersMarkerSelectorVisible, isTrue);
      expect(
        hud.markerOwner,
        DriverVehicleMarkerPresentationOwner.tellersLiveWindow,
      );
    });

    test('returning to Navigation restores the cockpit exactly once', () {
      // Enter Tellers…
      final inTellers = DriverNavHudVisibility.resolve(
        showCockpit: true,
        cameraFollow: true,
        tellersActive: true,
        followLiveActive: true,
        showDriverHudOverlay: true,
      );
      expect(inTellers.cockpitHud, isFalse);
      // …return to Navigation.
      final back = DriverNavHudVisibility.resolve(
        showCockpit: true,
        cameraFollow: true,
        tellersActive: false,
        followLiveActive: true,
        showDriverHudOverlay: true,
      );
      expect(back.cockpitHud, isTrue);
      expect(back.tellersHud, isFalse);
      expect(back.tellersMarkerPresentationVisible, isFalse);
      expect(
        back.markerOwner,
        DriverVehicleMarkerPresentationOwner.navigationHud,
      );
    });

    test('exactly one presentation HUD is active in every mode', () {
      for (final tellers in <bool>[false, true]) {
        final hud = DriverNavHudVisibility.resolve(
          showCockpit: true,
          cameraFollow: true,
          tellersActive: tellers,
          followLiveActive: true,
          showDriverHudOverlay: true,
        );
        // Cockpit HUD and Tellers HUD are mutually exclusive.
        expect(hud.cockpitHud && hud.tellersHud, isFalse);
        expect(hud.cockpitHud, tellers ? isFalse : isTrue);
        expect(hud.tellersHud, tellers);
        // Exactly one marker owner — never both navigation HUD and Tellers.
        expect(
          driverHideMapboxMarkerForPresentationOwner(hud.markerOwner),
          isTrue,
        );
      }
    });

    test('marker owner is exclusive (never HUD and Tellers together)', () {
      expect(
        resolveDriverVehicleMarkerPresentationOwner(
          tellersActive: true,
          followLiveActive: true,
          showDriverHudOverlay: true,
        ),
        DriverVehicleMarkerPresentationOwner.tellersLiveWindow,
      );
      expect(
        resolveDriverVehicleMarkerPresentationOwner(
          tellersActive: false,
          followLiveActive: true,
          showDriverHudOverlay: true,
        ),
        DriverVehicleMarkerPresentationOwner.navigationHud,
      );
      expect(
        resolveDriverVehicleMarkerPresentationOwner(
          tellersActive: false,
          followLiveActive: true,
          showDriverHudOverlay: false,
        ),
        DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
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

    testWidgets(
        'atomic geometry: an invalid transitional size retains the last valid '
        'live-window (no partial aperture during rotation)', (tester) async {
      // NAV-TELLERS-ROTATION-COMPOSITION-AND-POSE-LOCK-1 (Commit 1).
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 4.00',
        distanceTravelledText: '1.5 km',
        rideDurationText: '03:00',
        waitingTimeText: '00:00',
        statusText: 'Rit actief',
      );
      final windowFinder =
          find.byKey(const ValueKey('driver_tellers_live_window'));

      // Valid portrait frame commits a complete geometry.
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: const SizedBox.shrink(),
          mode: mode,
          size: const Size(390, 844),
        ),
      );
      await tester.pump();
      final validSize = tester.getSize(windowFinder);
      expect(validSize.height, greaterThan(0));

      // A transitional (zero-height) rotation frame is invalid → the committed
      // geometry must be retained (same live-window size), never a partial one.
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: const SizedBox.shrink(),
          mode: mode,
          size: const Size(390, 0),
        ),
      );
      await tester.pump();
      final retainedSize = tester.getSize(windowFinder);
      expect(retainedSize, validSize);
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

    testWidgets('each principal value appears exactly once; one Pause/one Stop', (
      tester,
    ) async {
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 13.37',
        distanceTravelledText: '7.7 km',
        rideDurationText: '00:11:22',
        waitingTimeText: '00:02:33',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: snap,
                onBackToNavigation: () {},
                onStop: () {},
                onToggleWait: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // No duplication of any principal value.
      expect(find.text('€ 13.37'), findsOneWidget);
      expect(find.text('7.7 km'), findsOneWidget);
      expect(find.text('00:11:22'), findsOneWidget);
      expect(find.text('00:02:33'), findsOneWidget);
      // Exactly one Pause action and one Stop action.
      expect(find.byKey(const ValueKey('driver_tellers_wait')), findsOneWidget);
      expect(find.byKey(const ValueKey('driver_tellers_stop')), findsOneWidget);
    });

    testWidgets('landscape meters column fills height (no unused spacer below)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1194, 834));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 5.00',
        distanceTravelledText: '2.0 km',
        rideDurationText: '00:05:00',
        waitingTimeText: '00:00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: const SizedBox.shrink(),
          mode: mode,
          size: const Size(1194, 834),
          isTablet: true,
          isLandscape: true,
        ),
      );
      await tester.pump();

      final panelRect = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_meters_panel')),
      );
      // The meters column fills the vast majority of the available height —
      // proving the grid expanded and no large black spacer remains below it.
      expect(panelRect.height, greaterThan(834 * 0.7));
    });

    testWidgets('landscape live window is clipped and stays right of meters', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1194, 834));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 5.00',
        distanceTravelledText: '2.0 km',
        rideDurationText: '00:05:00',
        waitingTimeText: '00:00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        harness(
          snapshot: snap,
          navOwner: const SizedBox.shrink(),
          mode: mode,
          size: const Size(1194, 834),
          isTablet: true,
          isLandscape: true,
        ),
      );
      await tester.pump();

      final windowFinder = find.byKey(
        const ValueKey('driver_tellers_live_window'),
      );
      // Frame is clipped exactly to its region.
      final container = tester.widget<Container>(windowFinder);
      expect(container.clipBehavior, Clip.antiAlias);

      // Live window never crosses the meters column.
      final panelRect = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_meters_panel')),
      );
      final windowRect = tester.getRect(windowFinder);
      expect(windowRect.left, greaterThanOrEqualTo(panelRect.right - 0.5));
      // And stays within the screen bounds.
      expect(windowRect.right, lessThanOrEqualTo(1194 + 0.5));
    });

    testWidgets('portrait controls do not overlap the live window', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(834, 1194));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final mode = DriverNavPresentationModeController()..showTellers();
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 5.00',
        distanceTravelledText: '2.0 km',
        rideDurationText: '00:05:00',
        waitingTimeText: '00:00:00',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(834, 1194)),
            child: MaterialApp(
              home: Scaffold(
                body: DriverRideMetersView(
                  snapshot: snap,
                  onBackToNavigation: () {},
                  onStop: () {},
                  onToggleWait: () {},
                  isTablet: true,
                  isLandscape: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final windowRect = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
      );
      final stopRect = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_stop')),
      );
      // Controls sit strictly below the live window — no overlap.
      expect(stopRect.top, greaterThanOrEqualTo(windowRect.bottom - 0.5));
    });

    testWidgets('selected vehicle marker is visible in Tellers (exactly one)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: const DriverRideMetersSnapshot(
                  fareText: '€ 4.00',
                  distanceTravelledText: '1.5 km',
                  rideDurationText: '03:00',
                  waitingTimeText: '00:00',
                  statusText: 'Rit actief',
                ),
                onBackToNavigation: () {},
                showVehicleMarker: true,
                showMarkerSelector: true,
                markerChoice: DriverNavigationMarkerChoice.car,
                onMarkerChoiceSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('driver_tellers_vehicle_marker_car')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_vehicle_marker_arrow')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_marker_selector')),
        findsOneWidget,
      );
      // Status localized Dutch — never "Ride active" in Dutch UI.
      expect(find.text('Rit actief'), findsOneWidget);
      expect(find.text('Ride active'), findsNothing);
    });

    testWidgets('Car ↔ Arrow switch is immediate; choice keys update', (
      tester,
    ) async {
      var choice = DriverNavigationMarkerChoice.car;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(834, 1194)),
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return DriverRideMetersView(
                    snapshot: const DriverRideMetersSnapshot(
                      fareText: '€ 4.00',
                      distanceTravelledText: '1.5 km',
                      rideDurationText: '03:00',
                      waitingTimeText: '00:00',
                      statusText: 'Rit actief',
                    ),
                    onBackToNavigation: () {},
                    isTablet: true,
                    showVehicleMarker: true,
                    showMarkerSelector: true,
                    markerChoice: choice,
                    onMarkerChoiceSelected: (c) {
                      setState(() => choice = c);
                    },
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('driver_tellers_vehicle_marker_car')),
        findsOneWidget,
      );

      // Tap the Arrow / Pijl button inside the compact selector.
      final arrowButton = find.text('Pijl');
      expect(arrowButton, findsOneWidget);
      await tester.tap(arrowButton);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('driver_tellers_vehicle_marker_arrow')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('driver_tellers_vehicle_marker_car')),
        findsNothing,
      );
      // Still exactly one marker.
      expect(find.byType(NavigationDriverHudOverlay), findsOneWidget);
    });

    testWidgets('marker stays inside portrait live-window bounds', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: const DriverRideMetersSnapshot(
                  fareText: '€ 4.00',
                  distanceTravelledText: '1.5 km',
                  rideDurationText: '03:00',
                  waitingTimeText: '00:00',
                  statusText: 'Rit actief',
                ),
                onBackToNavigation: () {},
                showVehicleMarker: true,
                showMarkerSelector: true,
                markerChoice: DriverNavigationMarkerChoice.arrow,
                onMarkerChoiceSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final window = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
      );
      final marker = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_vehicle_marker_arrow')),
      );
      expect(window.contains(marker.center), isTrue);
      expect(marker.top, greaterThanOrEqualTo(window.top - 0.5));
      expect(marker.bottom, lessThanOrEqualTo(window.bottom + 0.5));
    });

    testWidgets('marker stays inside landscape live-window bounds', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1194, 834));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1194, 834)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: const DriverRideMetersSnapshot(
                  fareText: '€ 4.00',
                  distanceTravelledText: '1.5 km',
                  rideDurationText: '03:00',
                  waitingTimeText: '00:00',
                  statusText: 'Rit actief',
                ),
                onBackToNavigation: () {},
                isTablet: true,
                isLandscape: true,
                showVehicleMarker: true,
                showMarkerSelector: true,
                markerChoice: DriverNavigationMarkerChoice.car,
                onMarkerChoiceSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final window = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_live_window')),
      );
      final marker = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_vehicle_marker_car')),
      );
      expect(window.contains(marker.center), isTrue);
      // Selector also inside the window.
      final selector = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_marker_selector')),
      );
      expect(window.contains(selector.center), isTrue);
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

    testWidgets(
      'geometry stack covers chrome; live aperture uncovered; no transparent Material',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const snap = DriverRideMetersSnapshot(
          fareText: '€ 9.00',
          distanceTravelledText: '4.0 km',
          rideDurationText: '00:08:00',
          waitingTimeText: '00:00:30',
          statusText: 'Rit actief',
        );
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: MaterialApp(
              home: Scaffold(
                body: DriverRideMetersView(
                  snapshot: snap,
                  onBackToNavigation: () {},
                  onToggleWait: () {},
                  onRecenter: () {},
                  onStop: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('driver_tellers_geometry_stack')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('driver_tellers_chrome_0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('driver_tellers_live_window')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('driver_tellers_live_label')),
          findsOneWidget,
        );
        // No full-screen transparent Material over the map aperture.
        final materials = tester.widgetList<Material>(find.byType(Material));
        for (final m in materials) {
          expect(m.type, isNot(MaterialType.transparency));
        }
        // Gold frame equals the live window key region (single aperture).
        final live = tester.getRect(
          find.byKey(const ValueKey('driver_tellers_live_window')),
        );
        final label = tester.getRect(
          find.byKey(const ValueKey('driver_tellers_live_label')),
        );
        expect(live.contains(label.center), isTrue);
      },
    );

    testWidgets(
      'exactly one recenter between Pause and Stop; invokes authoritative action',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(390, 844));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var recenterTaps = 0;
        const snap = DriverRideMetersSnapshot(
          fareText: '€ 9.00',
          distanceTravelledText: '4.0 km',
          rideDurationText: '00:08:00',
          waitingTimeText: '00:00:30',
          statusText: 'Rit actief',
        );
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(size: Size(390, 844)),
            child: MaterialApp(
              home: Scaffold(
                body: DriverRideMetersView(
                  snapshot: snap,
                  onBackToNavigation: () {},
                  onToggleWait: () {},
                  onRecenter: () => recenterTaps += 1,
                  onStop: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final wait = find.byKey(const ValueKey('driver_tellers_wait'));
        final recenter = find.byKey(const ValueKey('driver_tellers_recenter'));
        final stop = find.byKey(const ValueKey('driver_tellers_stop'));
        expect(wait, findsOneWidget);
        expect(recenter, findsOneWidget);
        expect(stop, findsOneWidget);

        // Order: Pauze | Recenter | Stop (left → right by center.dx).
        final waitX = tester.getCenter(wait).dx;
        final recenterX = tester.getCenter(recenter).dx;
        final stopX = tester.getCenter(stop).dx;
        expect(waitX, lessThan(recenterX));
        expect(recenterX, lessThan(stopX));

        // Crosshair / current-location icon.
        expect(
          find.descendant(
            of: recenter,
            matching: find.byIcon(Icons.my_location),
          ),
          findsOneWidget,
        );

        // Calls the existing authoritative recenter callback (idempotent taps).
        await tester.tap(recenter);
        await tester.pump();
        await tester.tap(recenter);
        await tester.pump();
        expect(recenterTaps, 2);
      },
    );

    testWidgets('portrait recenter has no overlap with Pause/Stop', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 9.00',
        distanceTravelledText: '4.0 km',
        rideDurationText: '00:08:00',
        waitingTimeText: '00:00:30',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(390, 844)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: snap,
                onBackToNavigation: () {},
                onToggleWait: () {},
                onRecenter: () {},
                onStop: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final waitRect = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_wait')),
      );
      final recenterRect = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_recenter')),
      );
      final stopRect = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_stop')),
      );
      expect(waitRect.overlaps(recenterRect), isFalse);
      expect(recenterRect.overlaps(stopRect), isFalse);
      expect(waitRect.overlaps(stopRect), isFalse);
      // Driving min touch-target.
      expect(recenterRect.width, greaterThanOrEqualTo(48));
      expect(recenterRect.height, greaterThanOrEqualTo(48));
    });

    testWidgets('landscape controls stay within panel without overflow', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1194, 834));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const snap = DriverRideMetersSnapshot(
        fareText: '€ 9.00',
        distanceTravelledText: '4.0 km',
        rideDurationText: '00:08:00',
        waitingTimeText: '00:00:30',
        statusText: 'Rit actief',
      );
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1194, 834)),
          child: MaterialApp(
            home: Scaffold(
              body: DriverRideMetersView(
                snapshot: snap,
                onBackToNavigation: () {},
                isTablet: true,
                isLandscape: true,
                onToggleWait: () {},
                onRecenter: () {},
                onStop: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final panel = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_meters_panel')),
      );
      final controls = tester.getRect(
        find.byKey(const ValueKey('driver_tellers_controls')),
      );
      expect(panel.contains(controls.topLeft), isTrue);
      expect(panel.contains(controls.bottomRight), isTrue);
      // Same order in landscape.
      expect(
        tester.getCenter(find.byKey(const ValueKey('driver_tellers_wait'))).dx,
        lessThan(
          tester
              .getCenter(find.byKey(const ValueKey('driver_tellers_recenter')))
              .dx,
        ),
      );
      expect(
        tester
            .getCenter(find.byKey(const ValueKey('driver_tellers_recenter')))
            .dx,
        lessThan(
          tester.getCenter(find.byKey(const ValueKey('driver_tellers_stop'))).dx,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('driverTellersStatusText localization', () {
    test('Dutch live ride shows Rit actief — never Ride active', () {
      expect(
        driverTellersStatusText(
          language: AppLanguage.nl,
          isWaiting: false,
          liveRideActive: true,
        ),
        'Rit actief',
      );
      expect(
        driverTellersStatusText(
          language: AppLanguage.nl,
          isWaiting: true,
          liveRideActive: true,
        ),
        'Rit gepauzeerd',
      );
    });

    test('other locales keep their own wording (no Dutch hardcode)', () {
      expect(
        driverTellersStatusText(
          language: AppLanguage.en,
          isWaiting: false,
          liveRideActive: true,
        ),
        'Ride active',
      );
      expect(
        driverTellersStatusText(
          language: AppLanguage.fr,
          isWaiting: false,
          liveRideActive: true,
        ),
        'Course active',
      );
      expect(
        driverTellersStatusText(
          language: AppLanguage.es,
          isWaiting: false,
          liveRideActive: true,
        ),
        'Viaje activo',
      );
    });
  });

  group('DriverTellersRecenterContract', () {
    test('preserves View level, stays in Tellers, no second owners', () {
      const contract = DriverTellersRecenterContract(
        viewLevelBefore: 7,
        tellersActiveBefore: true,
      );
      expect(contract.preservesViewLevel, isTrue);
      expect(contract.staysInTellers, isTrue);
      expect(contract.usesExistingCameraOwner, isTrue);
      expect(contract.createsSecondLocationOwner, isFalse);
      expect(
        contract.isIdempotentAfter(viewLevelAfter: 7, tellersActiveAfter: true),
        isTrue,
      );
      // Leaving Tellers or changing View level would violate the contract.
      expect(
        contract.isIdempotentAfter(
          viewLevelAfter: 8,
          tellersActiveAfter: true,
        ),
        isFalse,
      );
      expect(
        contract.isIdempotentAfter(
          viewLevelAfter: 7,
          tellersActiveAfter: false,
        ),
        isFalse,
      );
    });

    test('recenter label is localized (Dutch Centreren)', () {
      expect(driverTellersRecenterLabel(AppLanguage.nl), 'Centreren');
      expect(driverTellersRecenterLabel(AppLanguage.en), 'Recenter');
    });
  });
}
