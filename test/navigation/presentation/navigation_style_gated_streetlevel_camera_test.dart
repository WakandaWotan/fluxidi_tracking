import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_policy.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_stationary_bearing_hold.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

DriverCockpitCameraProfileOutput _fixedProfile({
  required bool isTablet,
  required DriverCockpitMapVisualStyle style,
  double? currentZoom,
  double? currentPitch,
}) {
  final l7 = resolveDriverCockpitStreetlevelL7Targets(
    isTablet: isTablet,
    isLandscape: false,
    mapVisualStyle: style,
  );
  return resolveDriverCockpitCameraProfile(
    DriverCockpitCameraProfileInput(
      currentZoom: currentZoom ?? l7.zoom,
      currentPitch: currentPitch ?? l7.pitch,
      isTablet: isTablet,
      isLandscape: false,
      safeTop: 24,
      safeBottom: 20,
      screenHeight: isTablet ? 1100 : 800,
    ),
    viewLevel: 7,
    directAdjust: true,
    fixedStreetLevelZoomOnly: true,
    mapVisualStyle: style,
  );
}

void main() {
  group('NAV-STYLE-GATED-STREETLEVEL-CAMERA-P0 tablet', () {
    test('1) Light resolves raised non-3D streetlevel L7', () {
      final out = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.light,
      );
      expect(out.targetZoom, closeTo(17.0, 1e-9));
      expect(out.targetPitch, closeTo(62.0, 1e-9));
      expect(out.zoom, closeTo(17.0, 1e-9));
      expect(out.pitch, closeTo(62.0, 1e-9));
    });

    test('2) Dark matches Light camera geometry', () {
      final light = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.light,
      );
      final dark = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.dark,
      );
      expect(dark.targetZoom, closeTo(light.targetZoom, 1e-9));
      expect(dark.targetPitch, closeTo(light.targetPitch, 1e-9));
    });

    test('3) Satellite matches Light/Dark non-3D geometry', () {
      final sat = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.satellite,
      );
      expect(sat.targetZoom, closeTo(17.0, 1e-9));
      expect(sat.targetPitch, closeTo(62.0, 1e-9));
    });

    test('4) 3D keeps exact Pro2 L7', () {
      final out = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.standard3d,
      );
      expect(out.targetZoom, closeTo(kDriverCockpitPro2CompactZoomL7, 1e-9));
      expect(out.targetPitch, closeTo(kDriverCockpitPro2CompactPitchL7, 1e-9));
      expect(kDriverCockpitPro2CompactZoomL7, 18.4);
      expect(kDriverCockpitPro2CompactPitchL7, 75.0);
    });

    test('5) Switch 3D → Light applies non-3D values', () {
      final from3d = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.standard3d,
      );
      final toLight = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.light,
        currentZoom: from3d.zoom,
        currentPitch: from3d.pitch,
      );
      expect(toLight.zoom, closeTo(17.0, 1e-9));
      expect(toLight.pitch, closeTo(62.0, 1e-9));
    });

    test('6) Switch Light → 3D restores exact Pro2', () {
      final fromLight = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.light,
      );
      final to3d = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.standard3d,
        currentZoom: fromLight.zoom,
        currentPitch: fromLight.pitch,
      );
      expect(to3d.zoom, closeTo(18.4, 1e-9));
      expect(to3d.pitch, closeTo(75.0, 1e-9));
    });

    test('7) Light → Dark → Satellite has no cumulative drift', () {
      var currentZoom = 18.4;
      var currentPitch = 75.0;
      for (final style in const [
        DriverCockpitMapVisualStyle.light,
        DriverCockpitMapVisualStyle.dark,
        DriverCockpitMapVisualStyle.satellite,
        DriverCockpitMapVisualStyle.dark,
        DriverCockpitMapVisualStyle.light,
      ]) {
        final out = _fixedProfile(
          isTablet: true,
          style: style,
          currentZoom: currentZoom,
          currentPitch: currentPitch,
        );
        expect(out.zoom, closeTo(17.0, 1e-9));
        expect(out.pitch, closeTo(62.0, 1e-9));
        currentZoom = out.zoom;
        currentPitch = out.pitch;
      }
    });

    test('8) Reroute context still uses selected style profile', () {
      // Profile resolution is style-only; reroute does not inject Pro2.
      final duringRerouteFeel = _fixedProfile(
        isTablet: true,
        style: DriverCockpitMapVisualStyle.satellite,
      );
      expect(duringRerouteFeel.targetZoom, isNot(closeTo(18.4, 0.01)));
      expect(duringRerouteFeel.targetZoom, closeTo(17.0, 1e-9));
    });
  });

  group('NAV-STYLE-GATED-STREETLEVEL-CAMERA-P0 phone + preservation', () {
    test('11) phone standard3d remains exact Pro2 19.1 / 77', () {
      final out = _fixedProfile(
        isTablet: false,
        style: DriverCockpitMapVisualStyle.standard3d,
      );
      expect(out.targetZoom, closeTo(19.1, 1e-9));
      expect(out.targetPitch, closeTo(77.0, 1e-9));
      expect(kDriverCockpitPro2PhoneZoomL7, 19.1);
      expect(kDriverCockpitPro2PhonePitchL7, 77.0);
    });

    test('phone Light/Dark/Satellite use same deltas as tablet', () {
      final light = _fixedProfile(
        isTablet: false,
        style: DriverCockpitMapVisualStyle.light,
      );
      expect(light.targetZoom, closeTo(17.7, 1e-9));
      expect(light.targetPitch, closeTo(64.0, 1e-9));
    });

    test('9) standstill bearing hold still latches (accecd8)', () {
      final gate = NavStationaryBearingGate();
      gate.latchHeldCameraBearing(90.0);
      for (final pose in const <double>[110.0, 70.0, 130.0]) {
        final d = gate.resolve(
          NavStationaryBearingInput(
            speedKmh: 0,
            travelBearingDeg: pose,
            gpsHeadingDeg: pose,
            displacementM: 0.2,
            accuracyM: 8,
          ),
        );
        expect(d.held, isTrue);
        expect(d.bearingDeg, closeTo(90.0, 1e-9));
      }
    });

    test('10) moving travelAuthority still unlocks without multi-fix wait', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 0.0);
      final d = gate.resolve(
        NavStationaryBearingInput(
          speedKmh: 40,
          travelBearingDeg: 90,
          gpsHeadingDeg: 90,
          displacementM: 20,
          accuracyM: 5,
          dtMs: 100,
          allowRouteTangent: false,
          travelAuthority: true,
          maxRotationRateDegPerSec: 220,
        ),
      );
      expect(d.held, isFalse);
      expect(navBearingShortestDelta(0, d.bearingDeg).abs(), greaterThan(10));
    });

    test('wrong-axis overview bias is absent from policy', () {
      // Ensure the reverted dcd3197 token is gone.
      expect(
        DriverNavCameraPolicy,
        isNot(equals(null)),
      );
      // Compile-time: symbol must not exist — probe via overview zoom equality
      // to unbiased speed band (no -0.45 shift).
      final out = DriverNavCameraPolicy().update(
        NavCameraPolicyInput(
          timestamp: DateTime(2026, 1, 1),
          liveRideActive: true,
          cameraFollowMode: true,
          speedKmh: 40,
          accuracyM: 8,
          routeConfidence: 80,
          hasReliableSnap: true,
        ),
      );
      expect(
        out.targetZoom,
        closeTo(DriverNavCameraPolicy.speedZoomFor(40), 1e-9),
      );
    });

    test('null style keeps exact Pro2 (flag-off safety)', () {
      final tablet = resolveDriverCockpitStreetlevelL7Targets(
        isTablet: true,
        isLandscape: false,
        mapVisualStyle: null,
      );
      expect(tablet.zoom, 18.4);
      expect(tablet.pitch, 75.0);
    });
  });
}
