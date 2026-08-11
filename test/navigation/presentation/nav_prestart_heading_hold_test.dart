// NAV-PRESTART-HEADING-HOLD-P0: prepared-route stationary hold before START.
// Post-START / moving / accecd8 gate behaviour must remain unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_stationary_bearing_hold.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

void main() {
  group('shouldSkipPassivePrestartFollowCamera', () {
    test('skips passive GPS follow in prepared draft before START', () {
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: false,
          preparedRouteDraft: true,
          force: false,
          cameraReason: 'normal_follow',
        ),
        isTrue,
      );
    });

    test('does not skip after START (live ride)', () {
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: true,
          preparedRouteDraft: false,
          force: false,
          cameraReason: 'normal_follow',
        ),
        isFalse,
      );
    });

    test('does not skip forced preview / style / recenter one-shots', () {
      for (final reason in const [
        'style_switch',
        'preview_route_ready',
        'booking_route_ready',
        'manual_recenter',
        'fixed_streetlevel',
        'cockpit_adjust',
      ]) {
        expect(
          shouldSkipPassivePrestartFollowCamera(
            liveRideActive: false,
            preparedRouteDraft: true,
            force: true,
            cameraReason: reason,
          ),
          isFalse,
          reason: reason,
        );
      }
    });

    test('does not skip when no prepared draft', () {
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: false,
          preparedRouteDraft: false,
          force: false,
          cameraReason: 'normal_follow',
        ),
        isFalse,
      );
    });
  });

  group('pre-START 15s stationary hold sequence', () {
    test('TEST1: latched preview bearing survives 15s of GPS/route jitter', () {
      const trusted = 72.0;
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(
        routeTangentBearingDeg: trusted,
        routeSegmentIndex: 0,
      );
      gate.latchHeldCameraBearing(trusted);

      // ~15s of 1 Hz ticks with pose heading + segment jitter.
      for (var i = 0; i < 15; i++) {
        final skip = shouldSkipPassivePrestartFollowCamera(
          liveRideActive: false,
          preparedRouteDraft: true,
          force: false,
          cameraReason: 'normal_follow',
        );
        expect(skip, isTrue);

        // Even if a pump-style resolve ran, gate must hold.
        final decision = gate.resolve(
          NavStationaryBearingInput(
            speedKmh: 0.0,
            routeTangentBearingDeg: trusted + (i.isEven ? 28.0 : -33.0),
            routeSegmentIndex: i.isEven ? 0 : 1,
            gpsHeadingDeg: (i * 41.0) % 360.0,
            displacementM: 0.3,
            accuracyM: 9.0,
          ),
        );
        expect(decision.held, isTrue);
        expect(decision.bearingDeg, closeTo(trusted, 1e-9));

        final held = resolvePrestartHeldCameraBearing(
          gate: gate,
          lastSmoothedCameraBearing: trusted + 5,
          previewRouteUpBearing: trusted,
        );
        expect(held, closeTo(trusted, 1e-9));
      }
    });

    test('TEST2: marker nose / camera forward-up share trusted heading', () {
      const trusted = 18.0;
      final gate = NavStationaryBearingGate();
      gate.latchHeldCameraBearing(trusted);
      final camera = resolvePrestartHeldCameraBearing(
        gate: gate,
        lastSmoothedCameraBearing: null,
        previewRouteUpBearing: trusted,
      );
      // Fixed HUD keeps the vehicle screen-up; camera must stay on the same
      // trusted heading so the road agrees with the nose.
      expect(camera, closeTo(trusted, 1e-9));
      expect(camera, closeTo(trusted, 1e-9));
    });

    test('TEST3: hold works with no map-style interaction', () {
      const trusted = 210.0;
      final gate = NavStationaryBearingGate();
      gate.latchHeldCameraBearing(trusted);
      for (var i = 0; i < 10; i++) {
        expect(
          shouldSkipPassivePrestartFollowCamera(
            liveRideActive: false,
            preparedRouteDraft: true,
            force: false,
            cameraReason: 'normal_follow',
          ),
          isTrue,
        );
        expect(
          resolvePrestartHeldCameraBearing(
            gate: gate,
            lastSmoothedCameraBearing: trusted,
            previewRouteUpBearing: trusted,
          ),
          closeTo(trusted, 1e-9),
        );
      }
    });

    test('TEST4: style switch force path is not blocked; bearing re-latches', () {
      const trusted = 95.0;
      final gate = NavStationaryBearingGate();
      gate.latchHeldCameraBearing(trusted);

      // Passive ticks still skip (no style required for hold).
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: false,
          preparedRouteDraft: true,
          force: false,
          cameraReason: 'normal_follow',
        ),
        isTrue,
      );

      // Forced style_switch one-shots remain allowed (geometry may change).
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: false,
          preparedRouteDraft: true,
          force: true,
          cameraReason: 'style_switch',
        ),
        isFalse,
      );

      // After style apply re-latches the same forward-up bearing.
      gate.latchHeldCameraBearing(trusted);
      expect(gate.acceptedBearing, closeTo(trusted, 1e-9));

      // Style-gated zoom/pitch profiles still differ; bearing ownership
      // stays independent of map style.
      final light = resolveDriverCockpitStreetlevelL7Targets(
        isTablet: true,
        isLandscape: false,
        mapVisualStyle: DriverCockpitMapVisualStyle.light,
      );
      final dark = resolveDriverCockpitStreetlevelL7Targets(
        isTablet: true,
        isLandscape: false,
        mapVisualStyle: DriverCockpitMapVisualStyle.dark,
      );
      final sat = resolveDriverCockpitStreetlevelL7Targets(
        isTablet: true,
        isLandscape: false,
        mapVisualStyle: DriverCockpitMapVisualStyle.satellite,
      );
      final standard3d = resolveDriverCockpitStreetlevelL7Targets(
        isTablet: true,
        isLandscape: false,
        mapVisualStyle: DriverCockpitMapVisualStyle.standard3d,
      );
      expect(light.zoom, isNot(equals(standard3d.zoom)));
      expect(dark.pitch, equals(light.pitch));
      expect(sat.zoom, equals(light.zoom));
      expect(
        resolvePrestartHeldCameraBearing(
          gate: gate,
          lastSmoothedCameraBearing: trusted,
          previewRouteUpBearing: trusted,
        ),
        closeTo(trusted, 1e-9),
      );
    });

    test('TEST5: START boundary — live ride disables prestart skip', () {
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: true,
          preparedRouteDraft: false,
          force: false,
          cameraReason: 'normal_follow',
        ),
        isFalse,
      );
      // Forced START follow also never skipped.
      expect(
        shouldSkipPassivePrestartFollowCamera(
          liveRideActive: true,
          preparedRouteDraft: false,
          force: true,
          cameraReason: 'normal_follow',
        ),
        isFalse,
      );
    });

    test('TEST6/7: post-START gate still holds when stationary after unlock', () {
      // Prove accecd8 semantics unchanged: seed → move unlock → park holds.
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(
        routeTangentBearingDeg: 40.0,
        routeSegmentIndex: 0,
      );
      // Build movement confidence.
      for (var i = 0; i < 3; i++) {
        gate.resolve(
          NavStationaryBearingInput(
            speedKmh: 35.0,
            routeTangentBearingDeg: 40.0 + i,
            routeSegmentIndex: 0,
            gpsHeadingDeg: 40.0,
            displacementM: 12.0,
            accuracyM: 6.0,
          ),
        );
      }
      final parked = gate.resolve(
        const NavStationaryBearingInput(
          speedKmh: 0.0,
          routeTangentBearingDeg: 95.0,
          routeSegmentIndex: 2,
          gpsHeadingDeg: 180.0,
          displacementM: 0.2,
          accuracyM: 8.0,
        ),
      );
      expect(parked.held, isTrue);
      expect(parked.bearingDeg, isNot(closeTo(95.0, 1.0)));
    });
  });
}
