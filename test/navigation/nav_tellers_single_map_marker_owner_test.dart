// NAV-TELLERS-SINGLE-MAP-MARKER-OWNER-1
//
// Exactly one visible vehicle marker in Tellers: the same Mapbox annotation
// used by ordinary Navigation. No screen-fixed Flutter Car/Arrow child is
// painted inside the Tellers live window (field-proven duplicate). Selector
// keeps working — it drives the Mapbox annotation icon.
//
// These tests exercise ONLY:
//   * the pure marker-owner resolver;
//   * the Tellers live-window widget contract (no Flutter marker);
//   * the Car/Arrow selector callback contract.
// They do NOT touch the Mapbox annotation manager (state-side).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_choice.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

void main() {
  group('resolveDriverVehicleMarkerPresentationOwner (invariant)', () {
    test('Tellers -> mapboxAnnotation, regardless of the driver HUD flag', () {
      for (final hudFlag in <bool>[false, true]) {
        expect(
          resolveDriverVehicleMarkerPresentationOwner(
            tellersActive: true,
            followLiveActive: true,
            showDriverHudOverlay: hudFlag,
          ),
          DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
        );
      }
    });

    test('Mapbox marker must NOT be hidden when Tellers owns the display', () {
      final owner = resolveDriverVehicleMarkerPresentationOwner(
        tellersActive: true,
        followLiveActive: true,
        showDriverHudOverlay: true,
      );
      expect(driverHideMapboxMarkerForPresentationOwner(owner), isFalse);
    });

    test('deprecated tellersLiveWindow value is never emitted', () {
      for (final tellers in <bool>[false, true]) {
        for (final hud in <bool>[false, true]) {
          for (final live in <bool>[false, true]) {
            final owner = resolveDriverVehicleMarkerPresentationOwner(
              tellersActive: tellers,
              followLiveActive: live,
              showDriverHudOverlay: hud,
            );
            expect(
              owner,
              // ignore: deprecated_member_use_from_same_package
              isNot(DriverVehicleMarkerPresentationOwner.tellersLiveWindow),
              reason: 'tellers=$tellers hud=$hud live=$live',
            );
          }
        }
      }
    });

    test('ordinary Navigation is unchanged (no HUD -> Mapbox; HUD -> Flutter HUD)',
        () {
      expect(
        resolveDriverVehicleMarkerPresentationOwner(
          tellersActive: false,
          followLiveActive: true,
          showDriverHudOverlay: false,
        ),
        DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
      expect(
        resolveDriverVehicleMarkerPresentationOwner(
          tellersActive: false,
          followLiveActive: true,
          showDriverHudOverlay: true,
        ),
        DriverVehicleMarkerPresentationOwner.navigationHud,
      );
    });

    test('DriverNavHudVisibility.tellersMarkerPresentationVisible is always '
        'false with the single Mapbox owner in Tellers', () {
      for (final hud in <bool>[false, true]) {
        for (final cameraFollow in <bool>[false, true]) {
          for (final followLive in <bool>[false, true]) {
            final vis = DriverNavHudVisibility.resolve(
              showCockpit: true,
              cameraFollow: cameraFollow,
              tellersActive: true,
              followLiveActive: followLive,
              showDriverHudOverlay: hud,
            );
            expect(vis.tellersMarkerPresentationVisible, isFalse);
          }
        }
      }
    });
  });

  // ==========================================================================
  // Widget contract — Flutter Car/Arrow is NOT painted in Tellers.
  // Covers phone portrait, phone landscape, tablet portrait, tablet landscape.
  // ==========================================================================
  group('Tellers live window paints no Flutter vehicle marker', () {
    final devices = <String, Size>{
      'phone portrait': const Size(390, 844),
      'phone landscape': const Size(844, 390),
      'tablet portrait': const Size(834, 1194),
      'tablet landscape': const Size(1194, 834),
    };

    for (final entry in devices.entries) {
      final name = entry.key;
      final size = entry.value;
      final isLandscape = size.width > size.height;
      final isTablet = size.shortestSide >= 600;

      testWidgets('$name: no NavigationDriverHudOverlay in the live window',
          (tester) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size),
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
                  isTablet: isTablet,
                  isLandscape: isLandscape,
                  // Defense-in-depth: even when the API flag is still on, the
                  // widget must not paint a Flutter Car/Arrow.
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
        expect(find.byType(NavigationDriverHudOverlay), findsNothing,
            reason: name);
        expect(
          find.byKey(const ValueKey('driver_tellers_vehicle_marker_car')),
          findsNothing,
          reason: name,
        );
        expect(
          find.byKey(const ValueKey('driver_tellers_vehicle_marker_arrow')),
          findsNothing,
          reason: name,
        );
        // Selector is retained: it drives the single Mapbox marker icon.
        expect(
          find.byKey(const ValueKey('driver_tellers_marker_selector')),
          findsOneWidget,
          reason: name,
        );
      });
    }

    testWidgets('rotation phone <-> landscape never spawns a Flutter marker',
        (tester) async {
      // Portrait
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _WrappedTellersView(
          size: const Size(390, 844),
          isLandscape: false,
          isTablet: false,
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationDriverHudOverlay), findsNothing);

      // Landscape
      await tester.binding.setSurfaceSize(const Size(844, 390));
      await tester.pumpWidget(
        _WrappedTellersView(
          size: const Size(844, 390),
          isLandscape: true,
          isTablet: false,
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationDriverHudOverlay), findsNothing);

      // Back to portrait
      await tester.binding.setSurfaceSize(const Size(390, 844));
      await tester.pumpWidget(
        _WrappedTellersView(
          size: const Size(390, 844),
          isLandscape: false,
          isTablet: false,
        ),
      );
      await tester.pump();
      expect(find.byType(NavigationDriverHudOverlay), findsNothing);
    });
  });

  // ==========================================================================
  // Selector contract — Car/Arrow taps flow into onMarkerChoiceSelected. The
  // Mapbox annotation update is state-side; this only pins the callback.
  // ==========================================================================
  group('Car/Arrow selector remains functional (drives Mapbox marker)', () {
    testWidgets('tapping Arrow / Car fires the callback with the new choice',
        (tester) async {
      var choice = DriverNavigationMarkerChoice.car;
      final calls = <DriverNavigationMarkerChoice>[];
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(834, 1194)),
          child: MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) => DriverRideMetersView(
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
                    calls.add(c);
                    setState(() => choice = c);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      // No Flutter marker on the pre-tap state.
      expect(find.byType(NavigationDriverHudOverlay), findsNothing);

      final arrowButton = find.text('Pijl');
      final carButton = find.text('Auto');
      expect(arrowButton, findsOneWidget);
      expect(carButton, findsOneWidget);

      await tester.tap(arrowButton);
      await tester.pump();
      expect(choice, DriverNavigationMarkerChoice.arrow);

      await tester.tap(carButton);
      await tester.pump();
      expect(choice, DriverNavigationMarkerChoice.car);

      // No Flutter marker appears after taps either.
      expect(find.byType(NavigationDriverHudOverlay), findsNothing);
      expect(calls, [
        DriverNavigationMarkerChoice.arrow,
        DriverNavigationMarkerChoice.car,
      ]);
    });
  });
}

class _WrappedTellersView extends StatelessWidget {
  const _WrappedTellersView({
    required this.size,
    required this.isLandscape,
    required this.isTablet,
  });
  final Size size;
  final bool isLandscape;
  final bool isTablet;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: size),
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
            isTablet: isTablet,
            isLandscape: isLandscape,
            showVehicleMarker: true,
            showMarkerSelector: true,
            markerChoice: DriverNavigationMarkerChoice.car,
            onMarkerChoiceSelected: (_) {},
          ),
        ),
      ),
    );
  }
}
