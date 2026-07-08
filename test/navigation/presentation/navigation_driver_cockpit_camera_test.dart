import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_controller.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';

void main() {
  group('NAV-PRES-3B driver cockpit camera profile', () {
    test('phone target zoom/pitch increased compared to NAV-PRES-3A', () {
      expect(
        driverCockpitCameraTargetZoom(isTablet: false),
        greaterThan(kDriverCockpitCamera3aPhoneZoom),
      );
      expect(
        driverCockpitCameraTargetPitch(isTablet: false),
        greaterThan(kDriverCockpitCamera3aPhonePitch),
      );
      expect(driverCockpitCameraTargetZoom(isTablet: false), inInclusiveRange(18.9, 19.3));
      expect(driverCockpitCameraTargetPitch(isTablet: false), inInclusiveRange(76.0, 80.0));
    });

    test('tablet target zoom/pitch increased compared to NAV-PRES-3A', () {
      expect(
        driverCockpitCameraTargetZoom(isTablet: true),
        greaterThan(kDriverCockpitCamera3aTabletZoom),
      );
      expect(
        driverCockpitCameraTargetPitch(isTablet: true),
        greaterThan(kDriverCockpitCamera3aTabletPitch),
      );
      expect(driverCockpitCameraTargetZoom(isTablet: true), inInclusiveRange(18.2, 18.7));
      expect(driverCockpitCameraTargetPitch(isTablet: true), inInclusiveRange(74.0, 78.0));
    });

    test('zoom step remains bounded toward cockpit targets', () {
      final output = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 15.0,
          currentPitch: 50.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
      );
      expect(
        output.zoom - 15.0,
        lessThanOrEqualTo(kDriverCockpitCameraMaxZoomStep + 0.001),
      );
      expect(output.zoom, lessThanOrEqualTo(kDriverCockpitCameraMaxZoom));
    });

    test('pitch step remains bounded toward cockpit targets', () {
      final output = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 17.0,
          currentPitch: 50.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
      );
      expect(
        output.pitch - 50.0,
        lessThanOrEqualTo(kDriverCockpitCameraMaxPitchStep + 0.001),
      );
      expect(output.pitch, lessThanOrEqualTo(kDriverCockpitCameraMaxPitch));
    });

    test('3B padding is more aggressive than 3A street-view bottom padding', () {
      const safeTop = 44.0;
      const safeBottom = 34.0;
      final cockpit = driverCockpitCameraViewPadding(
        isTablet: false,
        isLandscape: false,
        safeTop: safeTop,
        safeBottom: safeBottom,
      );
      final streetView = NavCameraViewPadding(
        top: safeTop + 110.0,
        bottom: safeBottom + 310.0,
      );
      expect(cockpit.bottom, greaterThan(streetView.bottom));
      expect(cockpit.top, lessThan(streetView.top));
    });

    test('lookahead distance stays within 35-60m band', () {
      expect(resolveDriverCockpitLookaheadMeters(speedKmh: 0), 35.0);
      expect(resolveDriverCockpitLookaheadMeters(speedKmh: 40), 47.5);
      expect(resolveDriverCockpitLookaheadMeters(speedKmh: 80), 60.0);
      expect(resolveDriverCockpitLookaheadMeters(speedKmh: 120), 60.0);
    });

    test('route lookahead resolves center ahead on polyline', () {
      const route = <DriverLonLat>[
        DriverLonLat(4.0, 50.0),
        DriverLonLat(4.001, 50.0),
        DriverLonLat(4.002, 50.0),
      ];
      final output = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 18.0,
          currentPitch: 70.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 0,
          safeBottom: 0,
        ),
        lookahead: DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.0,
          vehicleLon: 4.0,
          bearingDeg: 90.0,
          speedKmh: 30.0,
          routeCoords: route,
          segmentIndex: 0,
          snappedLat: 50.0,
          snappedLon: 4.0,
          hasReliableSnap: true,
        ),
      );
      expect(output.lookaheadM, greaterThan(0));
      expect(output.centerLon, isNotNull);
      expect(output.centerLat, isNotNull);
      expect(output.centerLon!, greaterThan(4.0));
      expect(output.reason, 'route_lookahead');
    });

    test('bearing fallback lookahead when route snap unavailable', () {
      final output = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 18.0,
          currentPitch: 70.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 0,
          safeBottom: 0,
        ),
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.0,
          vehicleLon: 4.0,
          bearingDeg: 90.0,
          speedKmh: 20.0,
        ),
      );
      expect(output.centerLon, isNotNull);
      expect(output.centerLat, isNotNull);
      expect(output.centerLon!, greaterThan(4.0));
      expect(output.reason, 'bearing_lookahead');
    });

    test('center smoothing limits geodesic step per update', () {
      const route = <DriverLonLat>[
        DriverLonLat(4.0, 50.0),
        DriverLonLat(4.01, 50.0),
      ];
      final first = resolveDriverCockpitLookaheadCenter(
        const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.0,
          vehicleLon: 4.0,
          bearingDeg: 90.0,
          speedKmh: 50.0,
          routeCoords: route,
          segmentIndex: 0,
          snappedLat: 50.0,
          snappedLon: 4.0,
          hasReliableSnap: true,
        ),
        lookaheadM: 50.0,
      );
      final second = resolveDriverCockpitLookaheadCenter(
        DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.0,
          vehicleLon: 4.0,
          bearingDeg: 90.0,
          speedKmh: 50.0,
          routeCoords: route,
          segmentIndex: 0,
          snappedLat: 50.0,
          snappedLon: 4.0,
          hasReliableSnap: true,
          previousCenterLat: first.centerLat,
          previousCenterLon: first.centerLon,
        ),
        lookaheadM: 50.0,
      );
      expect(first.centerLat, isNotNull);
      expect(second.centerLat, isNotNull);
      expect(first.centerLon, isNotNull);
      expect(second.centerLon, isNotNull);
    });

    test('route align diagnostics expose marker-to-route-start distance', () {
      const route = <DriverLonLat>[
        DriverLonLat(4.0, 50.0),
        DriverLonLat(4.01, 50.01),
      ];
      final diag = resolveDriverCockpitRouteAlignDiagnostics(
        vehicleLat: 50.005,
        vehicleLon: 4.005,
        routeCoords: route,
        hasReliableSnap: true,
        snappedLat: 50.004,
        snappedLon: 4.004,
      );
      expect(diag.snapped, isTrue);
      expect(diag.markerToRouteStartM, isNotNull);
      expect(diag.markerToRouteStartM!, greaterThan(0));
      expect(diag.activeRouteStartDistM, isNotNull);
      expect(diag.activeRouteStartDistM!, greaterThan(0));
    });
  });

  group('NAV-PRES-3B presentation flag independence', () {
    test('cockpit camera flag remains independent from HUD and marker flags', () {
      const cockpitOnly = NavigationPresentationController(
        driverCockpitCameraEnabled: true,
      );
      const hudAndCockpit = NavigationPresentationController(
        driverHudOverlayEnabled: true,
        hideMapboxTaxiMarkerWithDriverHudEnabled: true,
        driverCockpitCameraEnabled: true,
      );
      const hudOnly = NavigationPresentationController(
        driverHudOverlayEnabled: true,
        hideMapboxTaxiMarkerWithDriverHudEnabled: true,
      );

      final driverCockpit = cockpitOnly.resolve(NavigationPresentationMode.driver);
      final driverHudCockpit = hudAndCockpit.resolve(NavigationPresentationMode.driver);
      final driverHudOnly = hudOnly.resolve(NavigationPresentationMode.driver);

      expect(driverCockpit.useDriverCockpitCamera, isTrue);
      expect(driverCockpit.showDriverHudOverlay, isFalse);
      expect(driverCockpit.hideMapboxTaxiMarker, isFalse);

      expect(driverHudCockpit.useDriverCockpitCamera, isTrue);
      expect(driverHudCockpit.showDriverHudOverlay, isTrue);
      expect(driverHudCockpit.hideMapboxTaxiMarker, isTrue);

      expect(driverHudOnly.useDriverCockpitCamera, isFalse);
      expect(driverHudOnly.showDriverHudOverlay, isTrue);
      expect(driverHudOnly.hideMapboxTaxiMarker, isTrue);
    });

    test('default controller keeps cockpit camera off in driver mode', () {
      final state = NavigationPresentationController.instance.resolve(
        NavigationPresentationMode.driver,
      );
      expect(state.useDriverCockpitCamera, isFalse);
    });
  });

  group('NAV-PRES-3C manual cockpit camera offsets', () {
    test('default offset 0 keeps NAV-PRES-3B target behavior', () {
      const input = DriverCockpitCameraProfileInput(
        currentZoom: 19.1,
        currentPitch: 78.0,
        isTablet: false,
        isLandscape: false,
        safeTop: 0,
        safeBottom: 0,
      );
      final baseline = resolveDriverCockpitCameraProfile(input);
      final withZeroOffsets = resolveDriverCockpitCameraProfile(
        input,
        manualZoomOffset: 0.0,
        manualPitchOffset: 0.0,
      );
      expect(withZeroOffsets.zoom, baseline.zoom);
      expect(withZeroOffsets.pitch, baseline.pitch);
    });

    test('plus offset increases target zoom within clamp', () {
      final base = driverCockpitCameraTargetZoom(isTablet: false);
      final plusTarget = applyDriverCockpitManualZoomTarget(
        baseTargetZoom: base,
        manualZoomOffset: 0.5,
      );
      expect(plusTarget, greaterThan(base));
      expect(plusTarget, lessThanOrEqualTo(kDriverCockpitCameraMaxZoom));

      final output = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 18.0,
          currentPitch: 70.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 0,
          safeBottom: 0,
        ),
        manualZoomOffset: 0.5,
      );
      expect(output.zoom, greaterThan(18.0));
    });

    test('minus offset decreases target zoom within clamp', () {
      final base = driverCockpitCameraTargetZoom(isTablet: false);
      final minusTarget = applyDriverCockpitManualZoomTarget(
        baseTargetZoom: base,
        manualZoomOffset: -0.5,
      );
      expect(minusTarget, lessThan(base));
      expect(minusTarget, greaterThanOrEqualTo(kDriverCockpitCameraMinZoom));
    });

    test('pitch offset stays bounded', () {
      expect(
        applyDriverCockpitManualPitchTarget(
          baseTargetPitch: 78.0,
          manualPitchOffset: 4.0,
        ),
        kDriverCockpitCameraMaxPitch,
      );
      expect(
        applyDriverCockpitManualPitchTarget(
          baseTargetPitch: 78.0,
          manualPitchOffset: -4.0,
        ),
        74.0,
      );
      expect(
        applyDriverCockpitManualPitchTarget(
          baseTargetPitch: 46.0,
          manualPitchOffset: -4.0,
        ),
        kDriverCockpitCameraMinPitch,
      );
      expect(
        stepDriverCockpitManualPitchOffset(3.5, increase: true),
        kDriverCockpitCameraManualPitchMaxOffset,
      );
      expect(
        stepDriverCockpitManualPitchOffset(-3.5, increase: false),
        kDriverCockpitCameraManualPitchMinOffset,
      );
    });

    test('manual zoom offset steps clamp at +/-1.0', () {
      expect(
        stepDriverCockpitManualZoomOffset(0.9, increase: true),
        kDriverCockpitCameraManualZoomMaxOffset,
      );
      expect(
        stepDriverCockpitManualZoomOffset(-0.9, increase: false),
        kDriverCockpitCameraManualZoomMinOffset,
      );
    });
  });
}
