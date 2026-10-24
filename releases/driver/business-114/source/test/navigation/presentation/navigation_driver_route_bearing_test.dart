import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_bearing_smoother.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_route_bearing.dart';

void main() {
  group('NAV-PRES-3E route-locked driver bearing', () {
    const northRoute = <DriverLonLat>[
      DriverLonLat(4.0, 50.0),
      DriverLonLat(4.0, 50.001),
      DriverLonLat(4.0, 50.002),
    ];

    const eastRoute = <DriverLonLat>[
      DriverLonLat(4.0, 50.0),
      DriverLonLat(4.001, 50.0),
      DriverLonLat(4.002, 50.0),
    ];

    DriverRouteBearingInput baseInput({
      List<DriverLonLat> route = northRoute,
      int segmentIndex = 0,
      double snappedLat = 50.0005,
      double snappedLon = 4.0,
      bool hasReliableSnap = true,
      double? gpsHeadingDeg = 270.0,
      double? previousBearingDeg,
      double speedKmh = 30.0,
      double tangentLookaheadM = kDriverRouteBearingTangentLookaheadM,
      double maxStepDeg = 90.0,
    }) {
      return DriverRouteBearingInput(
        routeCoords: route,
        segmentIndex: segmentIndex,
        snappedLat: snappedLat,
        snappedLon: snappedLon,
        hasReliableSnap: hasReliableSnap,
        gpsHeadingDeg: gpsHeadingDeg,
        previousBearingDeg: previousBearingDeg,
        routeConfidence: 90.0,
        forwardProgress: true,
        speedKmh: speedKmh,
        tangentLookaheadM: tangentLookaheadM,
        maxStepDeg: maxStepDeg,
      );
    }

    test('straight north route returns north/up bearing', () {
      final output = resolveDriverRouteBearing(baseInput(gpsHeadingDeg: 90.0));
      expect(output.source, 'route_tangent');
      expect(output.bearing, closeTo(0.0, 8.0));
    });

    test('east route returns east bearing', () {
      final output = resolveDriverRouteBearing(
        baseInput(
          route: eastRoute,
          snappedLat: 50.0,
          snappedLon: 4.0005,
          gpsHeadingDeg: 0.0,
        ),
      );
      expect(output.source, 'route_tangent');
      expect(output.bearing, closeTo(90.0, 8.0));
    });

    test('route tangent is preferred over GPS heading when snap is reliable', () {
      final output = resolveDriverRouteBearing(
        baseInput(gpsHeadingDeg: 270.0),
      );
      expect(output.source, 'route_tangent');
      expect(output.routeTangentBearing, isNotNull);
      expect(output.bearing, closeTo(output.routeTangentBearing!, 0.01));
      expect(output.gpsBearing, 270.0);
      expect(
        NavBearingSmoother.bearingDelta(output.bearing, output.gpsBearing!).abs(),
        greaterThanOrEqualTo(45.0),
      );
    });

    test('GPS heading fallback when route tangent unavailable', () {
      final output = resolveDriverRouteBearing(
        baseInput(
          route: const <DriverLonLat>[],
          hasReliableSnap: false,
          gpsHeadingDeg: 123.0,
        ),
      );
      expect(output.source, 'gps_heading');
      expect(output.bearing, closeTo(123.0, 0.01));
    });

    test('fallback bearing when neither route tangent nor GPS is reliable', () {
      final output = resolveDriverRouteBearing(
        baseInput(
          route: const <DriverLonLat>[],
          hasReliableSnap: false,
          gpsHeadingDeg: null,
          previousBearingDeg: 45.0,
        ),
      );
      expect(output.source, 'fallback');
      expect(output.bearing, closeTo(45.0, 0.01));
      expect(output.reason, 'hold_previous');
    });

    test('short lookahead on a curve returns local forward tangent', () {
      const curveRoute = <DriverLonLat>[
        DriverLonLat(4.0, 50.0),
        DriverLonLat(4.0003, 50.0),
        DriverLonLat(4.0003, 50.0005),
        DriverLonLat(4.0003, 50.001),
      ];
      final short = resolveDriverRouteTangentBearing(
        baseInput(
          route: curveRoute,
          segmentIndex: 0,
          snappedLat: 50.0,
          snappedLon: 4.00015,
          tangentLookaheadM: 12.0,
        ),
      );
      final long = resolveDriverRouteTangentBearing(
        baseInput(
          route: curveRoute,
          segmentIndex: 0,
          snappedLat: 50.0,
          snappedLon: 4.00015,
          tangentLookaheadM: 50.0,
        ),
      );
      expect(short, isNotNull);
      expect(long, isNotNull);
      expect(short!, closeTo(90.0, 10.0));
      expect(
        NavBearingSmoother.bearingDelta(long!, 90.0).abs(),
        greaterThan(15.0),
      );
    });

    test('bearing smoothing uses shortest-angle path across 0/360', () {
      final output = resolveDriverRouteBearing(
        baseInput(
          route: eastRoute,
          snappedLat: 50.0,
          snappedLon: 4.0005,
          gpsHeadingDeg: 10.0,
          previousBearingDeg: 350.0,
          maxStepDeg: 20.0,
        ),
      );
      expect(output.deltaDeg, isNotNull);
      expect(output.deltaDeg!.abs(), lessThanOrEqualTo(20.0));
      expect(output.deltaDeg!.abs(), lessThan(30.0));
    });

    test('avoids abrupt 180 flip when route geometry is ambiguous', () {
      const southRoute = <DriverLonLat>[
        DriverLonLat(4.0, 50.002),
        DriverLonLat(4.0, 50.001),
        DriverLonLat(4.0, 50.0),
      ];
      final ambiguous = resolveDriverRouteBearing(
        DriverRouteBearingInput(
          routeCoords: southRoute,
          segmentIndex: 0,
          snappedLat: 50.0018,
          snappedLon: 4.0,
          hasReliableSnap: true,
          gpsHeadingDeg: 0.0,
          previousBearingDeg: 0.0,
          routeConfidence: 90.0,
          forwardProgress: true,
          speedKmh: 30.0,
          tangentLookaheadM: 12.0,
          maxStepDeg: 90.0,
        ),
      );
      expect(ambiguous.source, 'gps_heading');
      expect(ambiguous.reason, contains('flip_guard'));
      expect(ambiguous.bearing, closeTo(0.0, 0.01));
    });

    test('driver view level does not change route-locked bearing', () {
      final input = baseInput(gpsHeadingDeg: 270.0);
      final level1 = resolveDriverRouteBearing(input);
      final level13 = resolveDriverRouteBearing(input);
      expect(level1.bearing, level13.bearing);
      expect(level1.source, level13.source);

      // View-level camera resolver is independent from bearing resolver.
      final camera7 = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.0,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
        viewLevel: 7,
      );
      final camera13 = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.0,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
        viewLevel: 13,
      );
      expect(camera13.zoom, greaterThan(camera7.zoom));
    });
  });
}
