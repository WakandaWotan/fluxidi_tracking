import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_map_visual_clarity.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_map_config.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_fixed_streetlevel.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_active_ride_controls.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_preview_controls.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';

// NAV-RELEASE-SIMPLE-STREETLEVEL-1
//
// Pins the release-simplified navigation surface: one fixed streetlevel
// camera owner, zoom-only +/-, sticky bottom reserve, and real 3D visualMode.

void main() {
  group('fixed streetlevel camera ownership', () {
    test('preview with route draft owns camera', () {
      expect(
        fixedStreetLevelOwnsCamera(
          hasPreviewDraft: true,
          liveRideActive: false,
        ),
        isTrue,
      );
    });

    test('live ride owns camera', () {
      expect(
        fixedStreetLevelOwnsCamera(
          hasPreviewDraft: false,
          liveRideActive: true,
        ),
        isTrue,
      );
    });

    test('idle map does not own camera', () {
      expect(
        fixedStreetLevelOwnsCamera(
          hasPreviewDraft: false,
          liveRideActive: false,
        ),
        isFalse,
      );
    });

    test('preview draft always decides streetlevel + cockpit apply', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          routePointCount: 12,
          liveRideActive: false,
        ),
      );
      expect(decision.mode, NavPreviewPresentationMode.streetLevel);
      expect(decision.applyCockpitCamera, isTrue);
      expect(decision.reason, 'preview_fixed_streetlevel');
    });

    test('fitBounds never permitted on release surface', () {
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isFalse,
      );
      expect(
        mayOverviewFitBoundsWithFixedStreetLevel(
          hasPreviewDraft: true,
          liveRideActive: false,
        ),
        isFalse,
      );
    });

    test('style switch restores streetlevel for any preview draft', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isTrue,
      );
      expect(
        mayRestoreFixedStreetLevelAfterStyleSwitch(
          hasPreviewDraft: true,
          liveRideActive: false,
        ),
        isTrue,
      );
    });

    test('live style switch keeps preview restore off', () {
      expect(
        mayRestoreFixedStreetLevelAfterStyleSwitch(
          hasPreviewDraft: true,
          liveRideActive: true,
        ),
        isFalse,
      );
    });
  });

  group('marker / sticky bottom reserve', () {
    test('phone portrait reserve clears estimate chrome', () {
      final offset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 48,
        primaryToSecondaryGap: 8,
        extraBottomChrome: 96,
      );
      expect(offset, greaterThan(168));
    });

    test('tablet portrait reserve clears estimate chrome', () {
      final offset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 56,
        primaryToSecondaryGap: 8,
        extraBottomChrome: 96,
      );
      expect(offset, greaterThan(180));
    });

    test('sticky reserve never shrinks on incomplete measurement', () {
      final grown = stickyBottomChromeReserve(measured: 220, lastReliable: 200);
      expect(grown, 220);
      final shrunken = stickyBottomChromeReserve(
        measured: 120,
        lastReliable: 220,
      );
      expect(shrunken, 220);
      final incomplete = stickyBottomChromeReserve(
        measured: 0,
        lastReliable: 220,
      );
      expect(incomplete, 220);
    });
  });

  group('zoom-only around fixed streetlevel L7', () {
    DriverCockpitCameraProfileOutput profileAt(int level, {required bool isTablet}) {
      final l7Pitch = driverCockpitViewLevelTargetPitch(
        isTablet: isTablet,
        isLandscape: false,
        level: kDriverCockpitViewLevelDefault,
      );
      final l7Zoom = driverCockpitViewLevelTargetZoom(
        isTablet: isTablet,
        isLandscape: false,
        level: kDriverCockpitViewLevelDefault,
      );
      return resolveDriverCockpitCameraProfile(
        DriverCockpitCameraProfileInput(
          currentZoom: l7Zoom,
          currentPitch: l7Pitch,
          isTablet: isTablet,
          isLandscape: false,
          safeTop: 24,
          safeBottom: 20,
          screenHeight: isTablet ? 1024 : 844,
          hudVehicleSizePx: driverCockpitFixedHudIconSize(isTablet: isTablet),
          bottomHudHeightPx: 220,
        ),
        viewLevel: level,
        directAdjust: true,
        fixedStreetLevelZoomOnly: true,
      );
    }

    test('plus increases zoom only; pitch stays at L7 (phone)', () {
      final base = profileAt(7, isTablet: false);
      final up = profileAt(8, isTablet: false);
      expect(up.zoom, greaterThan(base.zoom));
      expect(up.targetPitch, closeTo(base.targetPitch, 0.01));
      expect(
        up.targetPitch,
        closeTo(kDriverCockpitPro2PhonePitchL7, 0.01),
      );
    });

    test('minus decreases zoom only; pitch stays at L7 (tablet)', () {
      final base = profileAt(7, isTablet: true);
      final down = profileAt(6, isTablet: true);
      expect(down.zoom, lessThan(base.zoom));
      expect(down.targetPitch, closeTo(base.targetPitch, 0.01));
      expect(
        down.targetPitch,
        closeTo(kDriverCockpitPro2CompactPitchL7, 0.01),
      );
    });

    test('safe min/max zoom respected', () {
      final minP = profileAt(1, isTablet: false);
      final maxP = profileAt(13, isTablet: false);
      expect(minP.zoom, greaterThanOrEqualTo(kDriverCockpitCameraMinZoom));
      expect(maxP.zoom, lessThanOrEqualTo(kDriverCockpitCameraMaxZoom));
    });

    test('zoom label is compact value, never View N/13', () {
      expect(fixedStreetLevelZoomLabel(19.1), '19.1');
      expect(fixedStreetLevelZoomLabel(19.1).contains('View'), isFalse);
    });

    test('live zoom is allowed', () {
      expect(
        navActiveRideZoomAllowed(liveRideActive: true),
        NavActiveRideBlockReason.none,
      );
      expect(fixedStreetLevelZoomAllowed(liveRideActive: true), isTrue);
    });
  });

  group('real 3D visual mode', () {
    test('threeD visualMode resolves to Mapbox Standard', () {
      expect(
        driverMapStyleForTheme(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.threeD,
        ),
        kDriverMapStyleStandard,
      );
      expect(
        driverMapVisualModeLogLabel(DriverMapVisualMode.threeD),
        '3d',
      );
    });

    test('threeD visualMode baseline is Standard even when scene inactive', () {
      expect(
        resolveDriverMapStyleUri(
          isLightTheme: true,
          visualMode: DriverMapVisualMode.threeD,
          cockpit3dSceneActive: false,
        ),
        kDriverMapStyleStandard,
      );
    });

    test('Light/Dark/Satellite remain functional baselines', () {
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.light,
          isLightTheme: true,
        ),
        kDriverMapStyleNavStreetLight,
      );
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.dark,
          isLightTheme: false,
        ),
        kDriverMapStyleNavStreetDark,
      );
      expect(
        driverMapStyleForExplicitCockpitChoice(
          choice: DriverCockpitMapVisualStyle.satellite,
          isLightTheme: true,
        ),
        kDriverMapStyleStandardSatellite,
      );
    });
  });

  group('controls surface', () {
    test('active ride keeps zoom + style; no presentation modes', () {
      final live = resolveNavMapControlAvailability(
        liveRideActive: true,
        hasPreviewDestination: true,
        routePointCount: 24,
      );
      expect(live.zoomControls, isTrue);
      expect(live.styleSelector, isTrue);
      expect(live.markerSelector, isTrue);
    });

    test('preview keeps zoom + style + marker', () {
      final preview = resolveNavMapControlAvailability(
        liveRideActive: false,
        hasPreviewDestination: true,
        routePointCount: 24,
      );
      expect(preview.zoomControls, isTrue);
      expect(preview.styleSelector, isTrue);
      expect(preview.markerSelector, isTrue);
    });
  });
}
