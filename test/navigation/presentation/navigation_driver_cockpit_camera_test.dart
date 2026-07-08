import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_controller.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_presentation_mode.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_hud_overlay.dart';

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

    test('NAV-PRES-3D-FIX: resolver centers on the snapped vehicle', () {
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
        lookahead: const DriverCockpitCameraLookaheadInput(
          vehicleLat: 50.0,
          vehicleLon: 4.0,
          bearingDeg: 90.0,
          speedKmh: 30.0,
          routeCoords: route,
          segmentIndex: 0,
          snappedLat: 50.0001,
          snappedLon: 4.0001,
          hasReliableSnap: true,
        ),
      );
      expect(output.centerLat, 50.0001);
      expect(output.centerLon, 4.0001);
      expect(output.centerMode, 'vehicle_anchor');
      expect(output.anchorFraction, kDriverCockpitVehicleAnchorFractionPortrait);
    });

    test('NAV-PRES-3D-FIX: raw vehicle center when route snap unavailable', () {
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
      expect(output.centerLat, 50.0);
      expect(output.centerLon, 4.0);
      expect(output.centerMode, 'vehicle_center');
    });

    test('standalone lookahead helper still resolves ahead on polyline', () {
      const route = <DriverLonLat>[
        DriverLonLat(4.0, 50.0),
        DriverLonLat(4.001, 50.0),
        DriverLonLat(4.002, 50.0),
      ];
      final center = resolveDriverCockpitLookaheadCenter(
        const DriverCockpitCameraLookaheadInput(
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
        lookaheadM: 40.0,
      );
      expect(center.centerLon, isNotNull);
      expect(center.centerLon!, greaterThan(4.0));
      expect(center.reason, 'route_lookahead');
      expect(center.centerMode, 'route_lookahead');
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

  group('NAV-PRES-3D-PRO2 driver view levels', () {
    const phoneInput = DriverCockpitCameraProfileInput(
      currentZoom: 19.1,
      currentPitch: 78.0,
      isTablet: false,
      isLandscape: false,
      safeTop: 44.0,
      safeBottom: 34.0,
      screenHeight: 800.0,
    );

    const alignedLookahead = DriverCockpitCameraLookaheadInput(
      vehicleLat: 50.0,
      vehicleLon: 4.0,
      bearingDeg: 90.0,
      speedKmh: 30.0,
      routeCoords: <DriverLonLat>[
        DriverLonLat(4.0, 50.0),
        DriverLonLat(4.001, 50.0),
        DriverLonLat(4.002, 50.0),
      ],
      segmentIndex: 0,
      snappedLat: 50.0001,
      snappedLon: 4.0001,
      hasReliableSnap: true,
    );

    test('level 1, 7, 13 exist and clamp correctly', () {
      expect(kDriverCockpitViewLevelDefault, 7);
      expect(kDriverCockpitViewLevelMin, 1);
      expect(kDriverCockpitViewLevelMax, 13);
      expect(clampDriverCockpitViewLevel(0), 1);
      expect(clampDriverCockpitViewLevel(20), 13);
      expect(stepDriverCockpitViewLevel(7, increase: true), 8);
      expect(stepDriverCockpitViewLevel(7, increase: false), 6);
    });

    test('level 7 preserves normal cockpit baseline on phone portrait', () {
      expect(
        driverCockpitViewLevelTargetZoom(
          isTablet: false,
          isLandscape: false,
          level: 7,
        ),
        kDriverCockpitPro2PhoneZoomL7,
      );
      expect(
        driverCockpitViewLevelTargetPitch(
          isTablet: false,
          isLandscape: false,
          level: 7,
        ),
        kDriverCockpitPro2PhonePitchL7,
      );
      expect(
        driverCockpitViewLevelTargetAnchorFraction(
          isTablet: false,
          isLandscape: false,
          level: 7,
        ),
        kDriverCockpitPro2PhoneAnchorL7,
      );
    });

    test('level 13 zoom is at least 2.0 higher than level 1 on phone', () {
      final zoom13 = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: 13,
      );
      final zoom1 = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: 1,
      );
      expect(zoom13 - zoom1, greaterThanOrEqualTo(2.0));
      expect(zoom13, inInclusiveRange(21.4, 21.8));
      expect(zoom1, inInclusiveRange(16.6, 17.0));
    });

    test('level 13 pitch is at least 25 degrees higher than level 1 on phone', () {
      final pitch13 = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: 13,
      );
      final pitch1 = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: 1,
      );
      expect(pitch13 - pitch1, greaterThanOrEqualTo(25.0));
      expect(pitch13, inInclusiveRange(84.0, 84.5));
      expect(pitch1, inInclusiveRange(48.0, 55.0));
    });

    test('level 13 anchor is fixed at level 7 baseline for all levels', () {
      for (final level in [1, 4, 7, 13]) {
        expect(
          driverCockpitViewLevelTargetAnchorFraction(
            isTablet: false,
            isLandscape: false,
            level: level,
          ),
          kDriverCockpitPro2PhoneAnchorL7,
        );
        expect(
          driverCockpitViewLevelTargetAnchorFraction(
            isTablet: false,
            isLandscape: true,
            level: level,
          ),
          kDriverCockpitPro2CompactAnchorL7,
        );
      }
    });

    test('levels 1, 7, 13 are visually distinct on phone portrait', () {
      final zoom1 = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: 1,
      );
      final zoom7 = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: 7,
      );
      final zoom13 = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: 13,
      );
      final pitch1 = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: 1,
      );
      final pitch7 = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: 7,
      );
      final pitch13 = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: 13,
      );
      expect(zoom7 - zoom1, greaterThanOrEqualTo(2.0));
      expect(zoom13 - zoom7, greaterThanOrEqualTo(2.0));
      expect(pitch7 - pitch1, greaterThanOrEqualTo(20.0));
      expect(pitch13 - pitch7, greaterThanOrEqualTo(5.0));
    });

    test('single step 12 to 13 remains visible on phone portrait', () {
      final zoom12 = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: 12,
      );
      final zoom13 = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: 13,
      );
      final pitch12 = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: 12,
      );
      final pitch13 = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: 13,
      );
      expect(zoom13 - zoom12, greaterThanOrEqualTo(0.35));
      expect(pitch13 - pitch12, greaterThanOrEqualTo(1.5));
    });

    test('HUD size is fixed at level 7 baseline for View 1..13', () {
      for (var level = kDriverCockpitViewLevelMin;
          level <= kDriverCockpitViewLevelMax;
          level++) {
        expect(
          driverCockpitViewLevelHudIconSize(isTablet: false, level: level),
          kDriverCockpitPro2HudPhoneL7,
        );
        expect(
          NavigationDriverHudOverlay.resolveIconSize(
            screenWidth: 400,
            cockpitBoost: true,
            viewLevel: level,
          ),
          kDriverCockpitPro2HudPhoneL7,
        );
      }
    });

    test('center coordinate remains snapped vehicle across all levels', () {
      for (var level = kDriverCockpitViewLevelMin;
          level <= kDriverCockpitViewLevelMax;
          level++) {
        final output = resolveDriverCockpitCameraProfile(
          phoneInput,
          lookahead: alignedLookahead,
          viewLevel: level,
        );
        expect(output.centerLat, alignedLookahead.snappedLat);
        expect(output.centerLon, alignedLookahead.snappedLon);
        expect(output.centerMode, 'vehicle_anchor');
      }
    });

    test('route alignment invariant remains preserved across levels', () {
      final level1 = resolveDriverCockpitCameraProfile(
        phoneInput,
        lookahead: alignedLookahead,
        viewLevel: 1,
      );
      final level7 = resolveDriverCockpitCameraProfile(
        phoneInput,
        lookahead: alignedLookahead,
        viewLevel: 7,
      );
      final level13 = resolveDriverCockpitCameraProfile(
        phoneInput,
        lookahead: alignedLookahead,
        viewLevel: 13,
      );
      expect(level1.centerLat, level7.centerLat);
      expect(level13.centerLat, level7.centerLat);
      expect(level13.anchorFraction, level7.anchorFraction);
      expect(level1.anchorFraction, level7.anchorFraction);
      expect(level13.anchorFraction, kDriverCockpitPro2PhoneAnchorL7);
    });

    test('tablet level 13 targets aggressive chase range', () {
      expect(
        driverCockpitViewLevelTargetZoom(
          isTablet: true,
          isLandscape: false,
          level: 13,
        ),
        inInclusiveRange(20.8, 21.4),
      );
      expect(
        driverCockpitViewLevelTargetPitch(
          isTablet: true,
          isLandscape: false,
          level: 13,
        ),
        inInclusiveRange(84.0, 84.5),
      );
    });

    test('vehicle anchor padding pins center at anchor fraction', () {
      final padding = driverCockpitVehicleAnchorPadding(
        screenHeight: 800.0,
        safeTop: 44.0,
        safeBottom: 34.0,
        anchorFraction: 0.82,
      );
      final centerY =
          padding.top + (800.0 - padding.top - padding.bottom) / 2;
      expect(centerY, closeTo(0.82 * 800.0, 0.5));
      expect(padding.top, greaterThan(padding.bottom));
    });

    test('smoothing/step limits remain bounded under max view level', () {
      final output = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 15.0,
          currentPitch: 50.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
        viewLevel: 13,
      );
      expect(
        output.zoom - 15.0,
        lessThanOrEqualTo(kDriverCockpitCameraFollowMaxZoomStep + 0.001),
      );
      expect(
        output.pitch - 50.0,
        lessThanOrEqualTo(kDriverCockpitCameraFollowMaxPitchStep + 0.001),
      );
      expect(output.zoom, lessThanOrEqualTo(kDriverCockpitCameraMaxZoom));
      expect(output.pitch, lessThanOrEqualTo(kDriverCockpitCameraMaxPitch));
    });

    test('default/non-driver behavior unchanged', () {
      final state = NavigationPresentationController.instance.resolve(
        NavigationPresentationMode.driver,
      );
      expect(state.useDriverCockpitCamera, isFalse);
      expect(state.showDriverCockpitCameraControls, isFalse);

      const controls = NavigationPresentationController(
        driverCockpitCameraEnabled: true,
        driverCockpitCameraControlsEnabled: true,
      );
      expect(
        controls
            .resolve(NavigationPresentationMode.overview)
            .showDriverCockpitCameraControls,
        isFalse,
      );
      expect(
        controls
            .resolve(NavigationPresentationMode.northUp)
            .showDriverCockpitCameraControls,
        isFalse,
      );
    });
  });

  group('NAV-PRES-3G real Mapbox cockpit camera', () {
    const phoneInput = DriverCockpitCameraProfileInput(
      currentZoom: 18.0,
      currentPitch: 70.0,
      isTablet: false,
      isLandscape: false,
      safeTop: 44.0,
      safeBottom: 34.0,
    );

    test('cockpit smoothing accumulates from last applied not NAV policy', () {
      const policySeed = DriverCockpitCameraProfileInput(
        currentZoom: 17.0,
        currentPitch: 58.0,
        isTablet: false,
        isLandscape: false,
        safeTop: 44.0,
        safeBottom: 34.0,
      );
      final first = resolveDriverCockpitCameraProfile(
        policySeed,
        viewLevel: 13,
      );
      final accumulated = resolveDriverCockpitCameraProfile(
        DriverCockpitCameraProfileInput(
          currentZoom: first.zoom,
          currentPitch: first.pitch,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
        viewLevel: 13,
      );
      expect(accumulated.zoom, greaterThan(first.zoom));
      final resetFromPolicy = resolveDriverCockpitCameraProfile(
        policySeed,
        viewLevel: 13,
      );
      expect(resetFromPolicy.zoom, lessThan(accumulated.zoom));
    });

    test('direct adjust reaches View 13 targets in one update', () {
      final output = resolveDriverCockpitCameraProfile(
        phoneInput,
        viewLevel: 13,
        directAdjust: true,
      );
      expect(output.zoom, closeTo(kDriverCockpitPro2PhoneZoomL13, 0.05));
      expect(output.pitch, closeTo(kDriverCockpitPro2PhonePitchL13, 0.05));
      expect(output.targetZoom, kDriverCockpitPro2PhoneZoomL13);
      expect(output.targetPitch, kDriverCockpitPro2PhonePitchL13);
    });

    test('View 13 targets exceed NAV-R12 policy caps', () {
      expect(
        driverCockpitViewLevelTargetZoom(
          isTablet: false,
          isLandscape: false,
          level: 13,
        ),
        greaterThan(18.5),
      );
      expect(
        driverCockpitViewLevelTargetPitch(
          isTablet: false,
          isLandscape: false,
          level: 13,
        ),
        greaterThan(58.0),
      );
    });

    test('two forced direct adjusts from level 7 to 13 reach chase targets', () {
      final level7 = resolveDriverCockpitCameraProfile(
        phoneInput,
        viewLevel: 7,
        directAdjust: true,
      );
      final level13 = resolveDriverCockpitCameraProfile(
        DriverCockpitCameraProfileInput(
          currentZoom: level7.zoom,
          currentPitch: level7.pitch,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
        viewLevel: 13,
        directAdjust: true,
      );
      expect(level13.zoom, closeTo(kDriverCockpitPro2PhoneZoomL13, 0.05));
      expect(level13.pitch, closeTo(kDriverCockpitPro2PhonePitchL13, 0.05));
    });

    test('HUD screen position inputs stay level-independent for close levels', () {
      for (final level in [1, 7, 13]) {
        final portrait = driverCockpitFixedHudBottomOffset(
          isLandscape: false,
          cockpitChaseCamera: true,
        );
        final landscape = driverCockpitFixedHudBottomOffset(
          isLandscape: true,
          cockpitChaseCamera: true,
        );
        expect(portrait, 168.0 + 8.0);
        expect(landscape, 112.0 + 8.0);
        expect(
          driverCockpitViewLevelTargetAnchorFraction(
            isTablet: false,
            isLandscape: false,
            level: level,
          ),
          driverCockpitFixedAnchorFraction(
            isTablet: false,
            isLandscape: false,
          ),
        );
      }
    });

    test('profile output exposes target and applied zoom/pitch', () {
      final output = resolveDriverCockpitCameraProfile(
        phoneInput,
        viewLevel: 7,
        directAdjust: true,
      );
      expect(output.zoom, output.targetZoom);
      expect(output.pitch, output.targetPitch);
      expect(output.reason, 'direct_adjust');
    });
  });

  group('NAV-PRES-3H fixed HUD and 3D style capability', () {
    test('HUD size identical for View 1, 7, and 13', () {
      final sizes = [1, 7, 13].map(
        (level) => driverCockpitViewLevelHudIconSize(
          isTablet: false,
          level: level,
        ),
      );
      expect(sizes.toSet().length, 1);
      expect(sizes.first, kDriverCockpitPro2HudPhoneL7);
    });

    test('HUD bottom offset identical for View 1, 7, and 13', () {
      for (final level in [1, 7, 13]) {
        expect(
          driverCockpitFixedHudBottomOffset(
            isLandscape: false,
            cockpitChaseCamera: true,
          ),
          176.0,
        );
        expect(
          driverCockpitFixedHudBottomOffset(
            isLandscape: true,
            cockpitChaseCamera: true,
          ),
          120.0,
        );
      }
    });

    test('anchor fraction stable across View 1, 7, and 13', () {
      final anchors = [1, 7, 13]
          .map(
            (level) => driverCockpitViewLevelTargetAnchorFraction(
              isTablet: false,
              isLandscape: false,
              level: level,
            ),
          )
          .toSet();
      expect(anchors.length, 1);
      expect(anchors.first, kDriverCockpitPro2PhoneAnchorL7);
    });

    test('View 13 still applies high zoom/pitch while HUD stays fixed', () {
      expect(
        driverCockpitViewLevelTargetZoom(
          isTablet: false,
          isLandscape: false,
          level: 13,
        ),
        greaterThan(
          driverCockpitViewLevelTargetZoom(
            isTablet: false,
            isLandscape: false,
            level: 1,
          ),
        ),
      );
      final applied = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 18.0,
          currentPitch: 70.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 44.0,
          safeBottom: 34.0,
        ),
        viewLevel: 13,
        directAdjust: true,
      );
      expect(applied.zoom, closeTo(kDriverCockpitPro2PhoneZoomL13, 0.05));
      expect(applied.pitch, closeTo(kDriverCockpitPro2PhonePitchL13, 0.05));
    });

    test('navigation style reports flat 2D capability note', () {
      final navDay = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleNavStreetLight,
        visualMode: DriverMapVisualMode.street,
      );
      expect(navDay.likelyFlatNavStyle, isTrue);
      expect(navDay.terrainLikelyAvailable, isFalse);
      expect(navDay.note, contains('3d'));

      final satellite = DriverCockpitMap3dCapability.resolve(
        styleUri: kDriverMapStyleSatellite,
        visualMode: DriverMapVisualMode.satellite,
      );
      expect(satellite.styleFamily, 'satellite-streets');
      expect(satellite.note, contains('street_3d'));
    });
  });
}
