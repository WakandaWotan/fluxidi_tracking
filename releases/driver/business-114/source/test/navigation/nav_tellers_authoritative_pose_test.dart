// NAV-TELLERS-ROUTE-CENTERLINE-LOCK-1 — pure resolver + extended pose-lock
// diagnostic contract tests. These pin the single-source Tellers-only pose
// selection policy:
//
//   * reliable route-follow state -> snappedPoint;
//   * everything else             -> visualPoint (existing fallback).
//
// Ordinary Navigation is not touched by this resolver, so these tests
// intentionally verify the resolver in isolation from any camera/widget code.

import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
// driver_ride_meters re-exports every symbol from driver_tellers_layout_geometry.
import 'package:fluxidi_tracking/navigation/presentation/driver_ride_meters.dart';

void main() {
  TellersAuthoritativePoseInput input({
    double visualLat = 52.100005,
    double visualLon = 4.300005,
    double? snappedLat = 52.100000,
    double? snappedLon = 4.300000,
    bool hasReliableMatchedSnap = true,
    bool trustRouteSnap = true,
    bool offRouteLikely = false,
  }) {
    return TellersAuthoritativePoseInput(
      visualLat: visualLat,
      visualLon: visualLon,
      snappedLat: snappedLat,
      snappedLon: snappedLon,
      hasReliableMatchedSnap: hasReliableMatchedSnap,
      trustRouteSnap: trustRouteSnap,
      offRouteLikely: offRouteLikely,
    );
  }

  group('resolveTellersAuthoritativePose', () {
    test('1. reliable matched snap -> pose is snappedPoint', () {
      final pose = resolveTellersAuthoritativePose(input());
      expect(pose.usesSnappedRoute, isTrue);
      expect(pose.usesVisualFallback, isFalse);
      expect(pose.lat, 52.100000);
      expect(pose.lon, 4.300000);
      expect(pose.source, TellersAuthoritativePoseSource.snappedRoute);
      expect(pose.sourceTag, 'snap');
    });

    test('2. reliable snap wins even when prediction is active '
        '(prediction represented by a distinct visualPoint)', () {
      // A prediction-active state supplies a visualPoint that is not equal to
      // the snap (predicted a few metres ahead / off-line). Snap must still win.
      final pose = resolveTellersAuthoritativePose(input(
        visualLat: 52.100050, // ~5.5 m ahead
        visualLon: 4.300080,
      ));
      expect(pose.usesSnappedRoute, isTrue);
      expect(pose.lat, 52.100000);
      expect(pose.lon, 4.300000);
    });

    test('3. reliable snap wins over R3 interpolation (also a visualPoint)',
        () {
      // Interpolation between prior R3 visuals is just another visualPoint
      // that differs from the current snap. Snap must still win.
      final pose = resolveTellersAuthoritativePose(input(
        visualLat: 52.099950,
        visualLon: 4.299920,
      ));
      expect(pose.usesSnappedRoute, isTrue);
    });

    test('4. trustworthy snap prevents raw GPS from displacing the marker',
        () {
      // forceRawTarget path in the widget sets visualPoint = raw GPS. As long
      // as the confidence engine still trusts the route snap, Tellers must
      // pin to the snap so the marker stays on the polyline.
      final pose = resolveTellersAuthoritativePose(input(
        visualLat: 52.109999, // wildly off — raw GPS excursion
        visualLon: 4.310000,
      ));
      expect(pose.usesSnappedRoute, isTrue);
      expect(pose.lat, 52.100000);
      expect(pose.lon, 4.300000);
    });

    test('5a. offRouteLikely -> visual fallback (recovery UX unchanged)', () {
      final pose = resolveTellersAuthoritativePose(input(
        offRouteLikely: true,
      ));
      expect(pose.usesVisualFallback, isTrue);
      expect(pose.lat, 52.100005);
      expect(pose.lon, 4.300005);
      expect(pose.sourceTag, 'visual');
    });

    test('5b. !trustRouteSnap -> visual fallback', () {
      final pose = resolveTellersAuthoritativePose(input(
        trustRouteSnap: false,
      ));
      expect(pose.usesVisualFallback, isTrue);
    });

    test('5c. !hasReliableMatchedSnap -> visual fallback', () {
      final pose = resolveTellersAuthoritativePose(input(
        hasReliableMatchedSnap: false,
      ));
      expect(pose.usesVisualFallback, isTrue);
    });

    test('6. missing / invalid snap -> visual fallback', () {
      final missing = resolveTellersAuthoritativePose(input(
        snappedLat: null,
        snappedLon: null,
      ));
      expect(missing.usesVisualFallback, isTrue);

      final infLat = resolveTellersAuthoritativePose(input(
        snappedLat: double.infinity,
      ));
      expect(infLat.usesVisualFallback, isTrue);

      final nan = resolveTellersAuthoritativePose(input(
        snappedLon: double.nan,
      ));
      expect(nan.usesVisualFallback, isTrue);

      final zeroZero = resolveTellersAuthoritativePose(input(
        snappedLat: 0.0,
        snappedLon: 0.0,
      ));
      expect(zeroZero.usesVisualFallback, isTrue,
          reason: '(0,0) sentinel must not silently pull the camera');
    });

    test('11. Centreren uses the same resolver by construction', () {
      // Centreren re-runs the follow-camera path; there is no separate nudge.
      // Feed the same reliable input twice; pose must be identical.
      final a = resolveTellersAuthoritativePose(input());
      final b = resolveTellersAuthoritativePose(input());
      expect(a.lat, b.lat);
      expect(a.lon, b.lon);
      expect(a.source, b.source);
    });
  });

  // ==========================================================================
  // Extended [NAV_TELLERS_POSE_LOCK] diagnostic — pose-to-marker AND
  // snapped-route-to-marker deltas, coarse buckets only, PII-free.
  // ==========================================================================
  group('formatNavTellersPoseLockDiagnostic (route-centreline extension)', () {
    final geo = DriverTellersLayoutGeometry.resolve(
      viewportSize: const Size(390, 844),
      safeTop: 47,
      safeBottom: 34,
      safeLeft: 0,
      safeRight: 0,
      isLandscape: false,
      isTablet: false,
    );

    test('base line remains identical when optional snap projection absent',
        () {
      final legacy = formatNavTellersPoseLockDiagnostic(
        viewportGeneration: 3,
        isLandscape: geo.isLandscape,
        isTablet: geo.isTablet,
        viewLevel: 6,
        markerAnchor: geo.markerRoadContactAnchorGlobal,
        projectedPose: geo.markerRoadContactAnchorGlobal,
        viewportSize: geo.mapViewportSize,
      );
      final extended = formatNavTellersPoseLockDiagnostic(
        viewportGeneration: 3,
        isLandscape: geo.isLandscape,
        isTablet: geo.isTablet,
        viewLevel: 6,
        markerAnchor: geo.markerRoadContactAnchorGlobal,
        projectedPose: geo.markerRoadContactAnchorGlobal,
        viewportSize: geo.mapViewportSize,
        projectedSnappedRoute: null,
        poseSource: null,
      );
      expect(legacy, extended);
      expect(legacy, contains('aligned=true'));
    });

    test('pose aligned + snap aligned -> both alignment flags true', () {
      final line = formatNavTellersPoseLockDiagnostic(
        viewportGeneration: 7,
        isLandscape: geo.isLandscape,
        isTablet: geo.isTablet,
        viewLevel: 6,
        markerAnchor: geo.markerRoadContactAnchorGlobal,
        projectedPose: geo.markerRoadContactAnchorGlobal,
        viewportSize: geo.mapViewportSize,
        projectedSnappedRoute: geo.markerRoadContactAnchorGlobal,
        poseSource: TellersAuthoritativePoseSource.snappedRoute,
      );
      expect(line, contains('aligned=true'));
      expect(line, contains('routeAligned=true'));
      expect(line, contains('snapDx=le6'));
      expect(line, contains('snapDy=le6'));
      expect(line, contains('poseSource=snap'));
      // No decimals leak.
      expect(line, isNot(contains('.')));
    });

    test('pose aligned but snap offset -> routeAligned=false, coarse bucket',
        () {
      final line = formatNavTellersPoseLockDiagnostic(
        viewportGeneration: 2,
        isLandscape: geo.isLandscape,
        isTablet: geo.isTablet,
        viewLevel: 6,
        markerAnchor: geo.markerRoadContactAnchorGlobal,
        projectedPose: geo.markerRoadContactAnchorGlobal,
        viewportSize: geo.mapViewportSize,
        projectedSnappedRoute:
            geo.markerRoadContactAnchorGlobal + const Offset(20, 0),
        poseSource: TellersAuthoritativePoseSource.visualFallback,
      );
      expect(line, contains('aligned=true'));
      expect(line, contains('routeAligned=false'));
      expect(line, contains('snapDx=p17_40'));
      expect(line, contains('poseSource=visual'));
    });

    test('poseSource alone (no snap projection) still appends the tag', () {
      final line = formatNavTellersPoseLockDiagnostic(
        viewportGeneration: 1,
        isLandscape: geo.isLandscape,
        isTablet: geo.isTablet,
        viewLevel: 6,
        markerAnchor: geo.markerRoadContactAnchorGlobal,
        projectedPose: geo.markerRoadContactAnchorGlobal,
        viewportSize: geo.mapViewportSize,
        poseSource: TellersAuthoritativePoseSource.snappedRoute,
      );
      expect(line, contains('poseSource=snap'));
      expect(line, isNot(contains('snapDx=')));
      expect(line, isNot(contains('routeAligned=')));
    });
  });

  // ==========================================================================
  // Device-class regression: policy is orientation- and device-independent.
  // ==========================================================================
  group('resolveTellersAuthoritativePose — device-class invariance', () {
    final devices = <String, Size>{
      'phone portrait': const Size(390, 844),
      'phone landscape': const Size(844, 390),
      'tablet portrait': const Size(834, 1194),
      'tablet landscape': const Size(1194, 834),
    };

    devices.forEach((name, size) {
      test('$name: reliable snap wins; unreliable falls back', () {
        // The resolver is form-factor independent — the invariant must hold on
        // every device class. Geometry is asserted to exist for the same size
        // so a broken layout would surface here too.
        final reliable = resolveTellersAuthoritativePose(
          TellersAuthoritativePoseInput(
            visualLat: 52.10001,
            visualLon: 4.30001,
            snappedLat: 52.10000,
            snappedLon: 4.30000,
            hasReliableMatchedSnap: true,
            trustRouteSnap: true,
            offRouteLikely: false,
          ),
        );
        expect(reliable.usesSnappedRoute, isTrue, reason: name);

        final off = resolveTellersAuthoritativePose(
          TellersAuthoritativePoseInput(
            visualLat: 52.10001,
            visualLon: 4.30001,
            snappedLat: 52.10000,
            snappedLon: 4.30000,
            hasReliableMatchedSnap: true,
            trustRouteSnap: true,
            offRouteLikely: true,
          ),
        );
        expect(off.usesVisualFallback, isTrue, reason: name);

        // Sanity: authoritative geometry resolves for this device size.
        final g = DriverTellersLayoutGeometry.resolve(
          viewportSize: size,
          safeTop: 0,
          safeBottom: 0,
          safeLeft: 0,
          safeRight: 0,
          isLandscape: size.width > size.height,
          isTablet: size.shortestSide >= 600,
        );
        expect(g.markerAnchor.dx.isFinite, isTrue);
      });
    });
  });
}
