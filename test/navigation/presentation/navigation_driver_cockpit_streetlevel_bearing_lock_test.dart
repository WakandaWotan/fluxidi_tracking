import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_bearing_smoother.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_streetlevel_bearing_lock.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_route_bearing.dart';

void main() {
  group('NAV-PRES-3L-A streetlevel bearing lock', () {
    const routeTangentOutput = DriverRouteBearingOutput(
      bearing: 12.0,
      source: 'route_tangent',
      confidence: 90.0,
      reason: 'route_snap_tangent',
      gpsBearing: 45.0,
      routeTangentBearing: 0.0,
    );

    test('inactive below View 7 passes resolver bearing through', () {
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangentOutput,
          viewLevel: 6,
          speedKmh: 30.0,
        ),
      );
      expect(output.result, 'skipped');
      expect(output.appliedBearing, 12.0);
      expect(output.mode, 'hold');
    });

    test('View 7+ uses route tangent as primary target', () {
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangentOutput,
          viewLevel: 10,
          speedKmh: 40.0,
          instantApply: true,
        ),
      );
      expect(output.result, 'applied');
      expect(output.mode, 'route_tangent');
      expect(output.appliedBearing, closeTo(0.0, 0.01));
    });

    test('reliable GPS blends lightly with route tangent at speed', () {
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangentOutput,
          viewLevel: 13,
          speedKmh: 35.0,
          gpsHeadingDeg: 45.0,
          gpsAccuracyM: 12.0,
          instantApply: true,
        ),
      );
      expect(output.mode, 'speed_blend');
      expect(output.appliedBearing, greaterThan(0.0));
      expect(output.appliedBearing, lessThan(45.0));
    });

    test('low speed holds previous bearing when tangent unavailable', () {
      const noTangent = DriverRouteBearingOutput(
        bearing: 90.0,
        source: 'gps_heading',
        confidence: 55.0,
        reason: 'no_route_tangent',
        gpsBearing: 100.0,
      );
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: noTangent,
          viewLevel: 9,
          speedKmh: 1.5,
          previousAppliedBearingDeg: 15.0,
          instantApply: true,
        ),
      );
      expect(output.mode, 'hold');
      expect(output.appliedBearing, closeTo(15.0, 0.01));
    });

    test('instant apply removes step lag on view changes', () {
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangentOutput,
          viewLevel: 12,
          speedKmh: 50.0,
          previousAppliedBearingDeg: 120.0,
          instantApply: true,
        ),
      );
      expect(output.appliedBearing, closeTo(0.0, 0.01));
      expect(
        NavBearingSmoother.bearingDelta(120.0, output.appliedBearing).abs(),
        greaterThan(90.0),
      );
    });

    test('normal speed allows faster rotation than low speed', () {
      const start = 100.0;
      final fast = applyDriverCockpitStreetlevelBearingLock(
        DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangentOutput,
          viewLevel: 11,
          speedKmh: 45.0,
          previousAppliedBearingDeg: start,
        ),
      );
      final slow = applyDriverCockpitStreetlevelBearingLock(
        DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangentOutput,
          viewLevel: 11,
          speedKmh: 1.0,
          previousAppliedBearingDeg: start,
        ),
      );
      expect(
        NavBearingSmoother.bearingDelta(start, fast.appliedBearing).abs(),
        greaterThan(
          NavBearingSmoother.bearingDelta(start, slow.appliedBearing).abs(),
        ),
      );
    });
  });
}
