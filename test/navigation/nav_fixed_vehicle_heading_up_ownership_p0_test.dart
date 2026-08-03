// FLUXIDI-NAV-FIXED-VEHICLE-HEADING-UP-OWNERSHIP-P0-1
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_target_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_fixed_hud_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_route_bearing.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';

void main() {
  group('FLUXIDI-NAV-FIXED-VEHICLE-HEADING-UP-OWNERSHIP-P0-1', () {
    test('1) straight road: KPI-relative HUD gap + vehicle_anchor under nose', () {
      final bottom = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: false,
        secondaryActionRowHeight: 0,
        primaryToSecondaryGap: 0,
      );
      expect(bottom, greaterThan(90)); // base panel + gap
      final profile = resolveDriverCockpitCameraProfile(
        DriverCockpitCameraProfileInput(
          currentZoom: 19.1,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 40,
          safeBottom: 20,
          screenHeight: 800,
          hudVehicleSizePx: 94,
          bottomHudHeightPx: bottom,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.85,
          vehicleLon: 4.35,
          bearingDeg: 0,
          speedKmh: 40,
          snappedLat: 50.8501,
          snappedLon: 4.35,
          hasReliableSnap: true,
        ),
        fixedStreetLevelZoomOnly: true,
      );
      expect(profile.centerMode, 'vehicle_anchor');
      expect(profile.centerLat, 50.8501);
      expect(profile.anchorFraction, greaterThan(0.5));
    });

    test('2) curved / bearing change keeps forceVehicleCenter pixel-stable mode', () {
      final a = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.1,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 40,
          safeBottom: 20,
          screenHeight: 800,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.85,
          vehicleLon: 4.35,
          bearingDeg: 10,
          speedKmh: 35,
          snappedLat: 50.851,
          snappedLon: 4.351,
          hasReliableSnap: true,
          forceVehicleCenter: true,
        ),
        fixedStreetLevelZoomOnly: true,
      );
      final b = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.1,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 40,
          safeBottom: 20,
          screenHeight: 800,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.852,
          vehicleLon: 4.352,
          bearingDeg: 40,
          speedKmh: 35,
          snappedLat: 50.851,
          snappedLon: 4.351,
          hasReliableSnap: true,
          forceVehicleCenter: true,
        ),
        fixedStreetLevelZoomOnly: true,
      );
      // Overlay is screen-fixed; camera center follows vehicle, not stale snap.
      expect(a.centerMode, 'vehicle_center_raw');
      expect(b.centerMode, 'vehicle_center_raw');
      expect(a.centerLat, 50.85);
      expect(b.centerLat, 50.852);
      expect(a.anchorFraction, b.anchorFraction);
    });

    test('3) deliberate off-route: force raw; old snap cannot own center', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          strongMismatchSuspected: true,
          hasReliableSnap: true,
          cameraScore: 90,
        ),
      );
      expect(d.forceRawTarget, isTrue);
      expect(d.source, NavCameraTargetSource.rawLive);

      final profile = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.1,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 40,
          safeBottom: 20,
          screenHeight: 800,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.86,
          vehicleLon: 4.36,
          bearingDeg: 90,
          speedKmh: 32,
          snappedLat: 50.85,
          snappedLon: 4.35,
          hasReliableSnap: true,
          forceVehicleCenter: true,
        ),
        fixedStreetLevelZoomOnly: true,
      );
      expect(profile.centerLat, 50.86);
      expect(profile.centerLon, 4.36);
      expect(profile.centerMode, isNot('vehicle_anchor'));
    });

    test('4) reroute requesting: target policy stays raw/live, not skipped/overview', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          offRouteLikely: true,
          hasReliableSnap: true,
        ),
      );
      expect(d.source, isNot(NavCameraTargetSource.skipped));
      expect(d.forceRawTarget, isTrue);
    });

    test('5) reroute applied: stale generation cannot own draw; center uses new vehicle', () {
      expect(
        shouldIgnoreStaleRouteDraw(
          drawAppliedRouteVersion: 4,
          currentAppliedRouteVersion: 7,
        ),
        isTrue,
      );
      final profile = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.1,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 40,
          safeBottom: 20,
          screenHeight: 800,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.87,
          vehicleLon: 4.37,
          bearingDeg: 15,
          speedKmh: 30,
          snappedLat: 50.87,
          snappedLon: 4.37,
          hasReliableSnap: true,
        ),
        fixedStreetLevelZoomOnly: true,
      );
      expect(profile.centerMode, 'vehicle_anchor');
      expect(profile.centerLat, 50.87);
    });

    test('6) poor GPS / parallel: forceVehicleCenter ignores stale snap sideways pull', () {
      final profile = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.1,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 40,
          safeBottom: 20,
          screenHeight: 800,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.8502,
          vehicleLon: 4.3504,
          bearingDeg: 5,
          speedKmh: 28,
          snappedLat: 50.8502,
          snappedLon: 4.3490, // parallel corridor pull
          hasReliableSnap: true,
          forceVehicleCenter: true,
        ),
        fixedStreetLevelZoomOnly: true,
      );
      expect(profile.centerLon, 4.3504);
    });

    test('7) stationary: bearing holds previous; no tangent ownership off-route', () {
      final out = resolveDriverRouteBearing(
        const DriverRouteBearingInput(
          routeCoords: [
            DriverLonLat(4.35, 50.85),
            DriverLonLat(4.35, 50.851),
          ],
          segmentIndex: 0,
          snappedLat: 50.85,
          snappedLon: 4.35,
          hasReliableSnap: false,
          offRouteLikely: true,
          forwardProgress: true,
          speedKmh: 0.5,
          gpsHeadingDeg: 12,
          previousBearingDeg: 88,
        ),
      );
      // Stationary + off-route → hold previous travel bearing.
      expect(out.bearing, closeTo(88, 0.01));
    });

    test('8) HUD presentation active for prepared / toPickup / liveRide', () {
      for (final phase in const [
        NavFixedHudPhase.preparedRoute,
        NavFixedHudPhase.toPickup,
        NavFixedHudPhase.liveRide,
      ]) {
        expect(
          navFixedHudPresentationActive(phase: phase, cameraFollowMode: true),
          isTrue,
          reason: phase.name,
        );
      }
      expect(
        navFixedHudPresentationActive(
          phase: NavFixedHudPhase.idle,
          cameraFollowMode: true,
        ),
        isFalse,
      );
    });

    test('9) pause/resume ownership: follow mode + phase keeps HUD active', () {
      expect(
        navFixedHudPresentationActive(
          phase: NavFixedHudPhase.liveRide,
          cameraFollowMode: true,
        ),
        isTrue,
      );
    });

    test('10) phone/tablet portrait/landscape: marker stays above KPI with gap', () {
      for (final landscape in [false, true]) {
        final offset = resolveStreetLevelMarkerBottomOffset(
          isLandscape: landscape,
          hasSecondaryActions: false,
          secondaryActionRowHeight: 0,
          primaryToSecondaryGap: 0,
        );
        final panel = landscape
            ? kCockpitLandscapePanelHeight
            : kCockpitPortraitBasePanelHeight;
        expect(offset, greaterThanOrEqualTo(panel + 12));
        expect(offset - panel, lessThanOrEqualTo(20));
      }
      // Tablet uses the same KPI gap constants; HUD size differs separately.
      expect(kStreetLevelMarkerGapAboveKpi, inInclusiveRange(12, 20));
    });

    test('11) prepared / toPickup / live share force-raw on mismatch', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          strongMismatchSuspected: true,
          hasReliableSnap: true,
        ),
      );
      expect(d.forceRawTarget, isTrue);
      expect(d.reason, 'route_adaptation_mismatch');
    });

    test('12) geo snap cannot become center owner when forceVehicleCenter', () {
      final profile = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 18.4,
          currentPitch: 75.0,
          isTablet: true,
          isLandscape: false,
          safeTop: 24,
          safeBottom: 16,
          screenHeight: 1200,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 51.0,
          vehicleLon: 5.0,
          bearingDeg: 180,
          speedKmh: 40,
          snappedLat: 51.01,
          snappedLon: 5.01,
          hasReliableSnap: true,
          forceVehicleCenter: true,
        ),
        fixedStreetLevelZoomOnly: true,
      );
      expect(profile.centerMode, 'vehicle_center_raw');
      expect(profile.centerLat, 51.0);
      expect(profile.centerLon, 5.0);
    });

    test('bearing during mismatch rejects planned-route tangent', () {
      final onRoute = resolveDriverRouteBearing(
        const DriverRouteBearingInput(
          routeCoords: [
            DriverLonLat(4.35, 50.85),
            DriverLonLat(4.35, 50.852),
          ],
          segmentIndex: 0,
          snappedLat: 50.851,
          snappedLon: 4.35,
          hasReliableSnap: true,
          offRouteLikely: false,
          forwardProgress: true,
          speedKmh: 40,
          gpsHeadingDeg: 90,
          previousBearingDeg: 0,
        ),
      );
      final offRoute = resolveDriverRouteBearing(
        const DriverRouteBearingInput(
          routeCoords: [
            DriverLonLat(4.35, 50.85),
            DriverLonLat(4.35, 50.852),
          ],
          segmentIndex: 0,
          snappedLat: 50.851,
          snappedLon: 4.35,
          hasReliableSnap: false,
          offRouteLikely: true,
          forwardProgress: false,
          speedKmh: 40,
          gpsHeadingDeg: 90,
          previousBearingDeg: 80,
          displacementM: 12,
          accuracyM: 8,
          maxStepDeg: 40,
        ),
      );
      // On-route prefers northbound tangent; off-route must not keep tangent.
      expect(onRoute.source, 'route_tangent');
      expect(offRoute.source, isNot('route_tangent'));
      expect(offRoute.source, anyOf('gps_heading', 'fallback'));
      expect(offRoute.bearing, closeTo(90, 20));
    });
  });
}
