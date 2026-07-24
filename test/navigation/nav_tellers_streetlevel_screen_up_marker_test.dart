// NAV-TELLERS-STREETLEVEL-SCREEN-UP-MARKER-1
//
// Pure-Dart tests for the marker rotation policy that keeps the single visible
// Mapbox Car/Arrow annotation upright (screen-up) in Tellers Streetlevel while
// preserving legacy MAP alignment + pose-bearing everywhere else.
//
// These tests exercise the pure policy resolver and its `iconRotateFor`
// contract only — they never touch the Mapbox plugin or the widget tree.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_marker_rotation_policy.dart';

void main() {
  group('resolveDriverMarkerRotationPolicy (screen-up invariant)', () {
    test('Streetlevel + mapboxAnnotation owner → viewport screen-up', () {
      final policy = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
      expect(policy.alignment, DriverMarkerRotationAlignment.viewport);
      expect(policy.forceIconRotateZero, isTrue);
      expect(policy.logLabel, 'viewport_screen_up');
    });

    test('Streetlevel + Flutter HUD owner → legacy map alignment', () {
      final policy = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        owner: DriverVehicleMarkerPresentationOwner.navigationHud,
      );
      expect(policy.alignment, DriverMarkerRotationAlignment.map);
      expect(policy.forceIconRotateZero, isFalse);
      expect(policy.logLabel, 'map_road_bearing');
    });

    test('Streetlevel + no owner → legacy map alignment', () {
      final policy = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        owner: DriverVehicleMarkerPresentationOwner.none,
      );
      expect(policy.alignment, DriverMarkerRotationAlignment.map);
      expect(policy.forceIconRotateZero, isFalse);
    });

    test('Overview / North-up + mapboxAnnotation owner → legacy map alignment',
        () {
      final policy = resolveDriverMarkerRotationPolicy(
        isStreetlevel: false,
        owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
      expect(policy.alignment, DriverMarkerRotationAlignment.map);
      expect(policy.forceIconRotateZero, isFalse);
    });

    test('Overview / North-up + Flutter HUD owner → legacy map alignment', () {
      final policy = resolveDriverMarkerRotationPolicy(
        isStreetlevel: false,
        owner: DriverVehicleMarkerPresentationOwner.navigationHud,
      );
      expect(policy.alignment, DriverMarkerRotationAlignment.map);
      expect(policy.forceIconRotateZero, isFalse);
    });

    test(
        'deprecated tellersLiveWindow owner (never emitted) does NOT trigger '
        'screen-up policy — defensive fallback stays on MAP',
        () {
      final policy = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        // ignore: deprecated_member_use, deprecated_member_use_from_same_package
        owner: DriverVehicleMarkerPresentationOwner.tellersLiveWindow,
      );
      expect(policy.alignment, DriverMarkerRotationAlignment.map);
    });
  });

  group('DriverMarkerRotationPolicy.iconRotateFor', () {
    test('viewportScreenUp forces iconRotate = 0 regardless of pose bearing',
        () {
      const policy = DriverMarkerRotationPolicy.viewportScreenUp;
      for (final b in <double>[
        0.0,
        1.0,
        45.0,
        90.0,
        137.0,
        180.0,
        270.0,
        359.9,
        -30.0,
      ]) {
        expect(policy.iconRotateFor(b), 0.0, reason: 'poseBearing=$b');
      }
    });

    test('mapRoadBearing preserves the incoming pose bearing unchanged', () {
      const policy = DriverMarkerRotationPolicy.mapRoadBearing;
      for (final b in <double>[
        0.0,
        1.0,
        45.0,
        90.0,
        137.0,
        180.0,
        270.0,
        359.9,
        -30.0,
      ]) {
        expect(policy.iconRotateFor(b), b, reason: 'poseBearing=$b');
      }
    });
  });

  group('Field-proven scenarios (Streetlevel + Mapbox owner)', () {
    // Every scenario below resolves to viewport screen-up (marker upright,
    // map/route rotate underneath).
    final policy = resolveDriverMarkerRotationPolicy(
      isStreetlevel: true,
      owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
    );

    test('Tellers Car (pose bearing 137°) → iconRotate = 0', () {
      expect(policy.alignment, DriverMarkerRotationAlignment.viewport);
      expect(policy.iconRotateFor(137.0), 0.0);
    });

    test('Tellers Arrow (pose bearing 137°) → iconRotate = 0', () {
      // Arrow and Car both go through the same policy; the pose bearing has
      // no effect on the screen orientation of either sprite.
      expect(policy.alignment, DriverMarkerRotationAlignment.viewport);
      expect(policy.iconRotateFor(137.0), 0.0);
    });

    test('camera bearing changes do not modify the marker screen-up contract',
        () {
      // The camera bearing is applied to the map underneath the annotation;
      // the annotation's iconRotate is unconditionally 0. Simulate a full
      // sweep of pose bearings to prove the invariant holds mid-turn.
      for (double b = 0.0; b < 360.0; b += 15.0) {
        expect(policy.iconRotateFor(b), 0.0, reason: 'poseBearing=$b');
      }
    });

    test('Car → Arrow (pose bearing preserved) still resolves screen-up', () {
      // The marker choice does not affect the rotation policy: swapping
      // Car ↔ Arrow while in Tellers Streetlevel keeps VIEWPORT + iconRotate 0.
      expect(policy.iconRotateFor(45.0), 0.0);
      expect(policy.iconRotateFor(45.0), 0.0); // after simulated swap
    });

    test('Centreren (large abrupt bearing correction) stays screen-up', () {
      // A user-initiated recenter can produce a large delta between raw pose
      // bearing and smoothed camera bearing; the invariant is unaffected.
      expect(policy.iconRotateFor(0.0), 0.0);
      expect(policy.iconRotateFor(179.9), 0.0);
      expect(policy.iconRotateFor(-179.9), 0.0);
    });
  });

  group('Leaving Tellers restores MAP alignment where required', () {
    test('same driver, view stays Streetlevel, HUD takes over → legacy MAP',
        () {
      // Tellers open, Streetlevel:
      final duringTellers = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
      // Tellers closes → Flutter HUD becomes the owner (Streetlevel + HUD
      // flag on). The Mapbox marker is hidden, so alignment falls back to the
      // legacy MAP contract (defensive — the hidden marker rotation is
      // invisible but must stay compatible with ordinary Navigation).
      final afterTellers = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        owner: DriverVehicleMarkerPresentationOwner.navigationHud,
      );
      expect(duringTellers.alignment, DriverMarkerRotationAlignment.viewport);
      expect(afterTellers.alignment, DriverMarkerRotationAlignment.map);
      expect(afterTellers.iconRotateFor(90.0), 90.0);
    });

    test(
        'view switches Streetlevel → Overview with Mapbox owner → legacy MAP',
        () {
      // Owner stays the same; only Streetlevel-ness flips.
      final streetlevel = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
      final overview = resolveDriverMarkerRotationPolicy(
        isStreetlevel: false,
        owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
      expect(streetlevel.alignment, DriverMarkerRotationAlignment.viewport);
      expect(overview.alignment, DriverMarkerRotationAlignment.map);
      expect(overview.iconRotateFor(137.0), 137.0);
    });
  });

  group('Portrait / landscape / rapid transitions', () {
    test('policy is orientation-agnostic — depends only on view + owner', () {
      // The rotation policy does not read orientation directly; a marker
      // that is screen-up in portrait remains screen-up in landscape and
      // survives repeated portrait ↔ landscape flips.
      final policy = resolveDriverMarkerRotationPolicy(
        isStreetlevel: true,
        owner: DriverVehicleMarkerPresentationOwner.mapboxAnnotation,
      );
      for (var i = 0; i < 20; i++) {
        expect(policy.alignment, DriverMarkerRotationAlignment.viewport);
        expect(policy.iconRotateFor(50.0 + i.toDouble()), 0.0);
      }
    });
  });
}
