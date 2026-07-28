import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';

// NAV-CAMERA-FIELD-REGRESSION-1
//
// Pins the field-observed camera ownership rules that af5199b broke:
// streetlevel must win over overview fitBounds, style switch must re-apply
// the cockpit profile, and the known Pro2 streetlevel pitch/zoom tables stay
// inside the existing safe bounds (no world/horizon presets).

void main() {
  group('mayOverviewFitBoundsInPreview', () {
    test('overview + allow: fitBounds permitted', () {
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isTrue,
      );
    });

    test('streetlevel selected: fitBounds blocked even when allow=true', () {
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          liveRideActive: false,
        ),
        isFalse,
      );
    });

    test('allowOverviewCamera=false: fitBounds blocked', () {
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: false,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isFalse,
      );
    });

    test('live ride: fitBounds blocked', () {
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: true,
        ),
        isFalse,
      );
    });
  });

  group('mayRestorePreviewCockpitCameraAfterStyleSwitch', () {
    test('preview streetlevel: restore required (keeps 3D style from horizon)', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          liveRideActive: false,
        ),
        isTrue,
      );
    });

    test('preview overview: no cockpit restore', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isFalse,
      );
    });

    test('live ride: preview restore stays off (live follow owns style_switch)', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          liveRideActive: true,
        ),
        isFalse,
      );
    });

    test('no draft: no restore', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: false,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          liveRideActive: false,
        ),
        isFalse,
      );
    });
  });

  group('known Pro2 streetlevel profile stays inside safe bounds', () {
    test('tablet L7 (default streetlevel) is the proven driving profile', () {
      final zoom = driverCockpitViewLevelTargetZoom(
        isTablet: true,
        isLandscape: false,
        level: kDriverCockpitViewLevelDefault,
      );
      final pitch = driverCockpitViewLevelTargetPitch(
        isTablet: true,
        isLandscape: false,
        level: kDriverCockpitViewLevelDefault,
      );
      expect(zoom, closeTo(kDriverCockpitPro2CompactZoomL7, 0.001));
      expect(pitch, closeTo(kDriverCockpitPro2CompactPitchL7, 0.001));
      // Field-proof bounds: never a regional/world zoom, never nearly-flat.
      expect(zoom, greaterThanOrEqualTo(17.0));
      expect(zoom, lessThanOrEqualTo(kDriverCockpitCameraMaxZoom));
      expect(pitch, greaterThanOrEqualTo(60.0));
      expect(pitch, lessThanOrEqualTo(kDriverCockpitCameraMaxPitch));
    });

    test('phone L7 stays inside the proven phone streetlevel profile', () {
      final zoom = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: kDriverCockpitViewLevelDefault,
      );
      final pitch = driverCockpitViewLevelTargetPitch(
        isTablet: false,
        isLandscape: false,
        level: kDriverCockpitViewLevelDefault,
      );
      expect(zoom, closeTo(kDriverCockpitPro2PhoneZoomL7, 0.001));
      expect(pitch, closeTo(kDriverCockpitPro2PhonePitchL7, 0.001));
      expect(zoom, greaterThanOrEqualTo(17.0));
      expect(pitch, greaterThanOrEqualTo(60.0));
    });

    test('View 1/13 and 13/13 stay within cockpit min/max (no world zoom)', () {
      for (final isTablet in [true, false]) {
        for (final level in [
          kDriverCockpitViewLevelMin,
          kDriverCockpitViewLevelMax,
        ]) {
          final zoom = driverCockpitViewLevelTargetZoom(
            isTablet: isTablet,
            isLandscape: false,
            level: level,
          );
          final pitch = driverCockpitViewLevelTargetPitch(
            isTablet: isTablet,
            isLandscape: false,
            level: level,
          );
          expect(zoom, greaterThanOrEqualTo(kDriverCockpitCameraMinZoom));
          expect(zoom, lessThanOrEqualTo(kDriverCockpitCameraMaxZoom));
          expect(pitch, greaterThanOrEqualTo(kDriverCockpitCameraMinPitch));
          expect(pitch, lessThanOrEqualTo(kDriverCockpitCameraMaxPitch));
          // Regional / world overview territory is well below 14.
          expect(zoom, greaterThanOrEqualTo(16.0));
        }
      }
    });

    test('directAdjust L7 profile keeps vehicle-anchor padding (not zero)', () {
      final profile = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: kDriverCockpitPro2CompactZoomL7,
          currentPitch: kDriverCockpitPro2CompactPitchL7,
          isTablet: true,
          isLandscape: false,
          safeTop: 24,
          safeBottom: 24,
          screenHeight: 1280,
          hudVehicleSizePx: 132,
          bottomHudHeightPx: 193 + 24,
        ),
        viewLevel: kDriverCockpitViewLevelDefault,
        directAdjust: true,
      );
      expect(profile.zoom, closeTo(kDriverCockpitPro2CompactZoomL7, 0.05));
      expect(profile.pitch, closeTo(kDriverCockpitPro2CompactPitchL7, 0.05));
      expect(profile.anchorFraction, greaterThan(0.50));
      expect(profile.anchorFraction, lessThan(0.85));
      // Top-heavy padding keeps the vehicle low above the KPI strip.
      expect(profile.padding.top, greaterThan(profile.padding.bottom));
    });
  });

  group('streetlevel marker clears KPI + estimate chrome', () {
    test('tablet portrait streetlevel offset clears KPI + secondary + estimate', () {
      // Matches the tablet compact-nav metrics used by af5199b layout:
      // rowHeight≈78, gap=9, estimate reserve=96, gapAboveKpi=16.
      final offset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 78,
        primaryToSecondaryGap: 9,
        extraBottomChrome: 96,
      );
      // 90 + 78 + 9 + 96 + 16 = 289
      expect(offset, closeTo(289.0, 0.01));
      expect(offset, greaterThan(kCockpitPortraitBasePanelHeight + 16));
    });

    test('phone portrait streetlevel offset clears KPI + secondary + estimate', () {
      final offset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 44,
        primaryToSecondaryGap: 4,
        extraBottomChrome: 96,
      );
      // 90 + 44 + 4 + 96 + 16 = 250
      expect(offset, closeTo(250.0, 0.01));
    });

    test('without estimate chrome the offset stays on KPI geometry only', () {
      final offset = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 78,
        primaryToSecondaryGap: 9,
      );
      expect(offset, closeTo(90 + 78 + 9 + 16.0, 0.01));
    });
  });

  group('presentation decision still separates style from camera', () {
    test('streetlevel decision still requests cockpit apply + route restore', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          routePointCount: 40,
          liveRideActive: false,
        ),
      );
      expect(decision.isStreetLevel, isTrue);
      expect(decision.applyCockpitCamera, isTrue);
      expect(decision.previewRouteRestoreEligible, isTrue);
    });

    test('overview decision keeps route restore without cockpit apply', () {
      final decision = decideNavPreviewPresentation(
        const NavPreviewPresentationInputs(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          routePointCount: 40,
          liveRideActive: false,
        ),
      );
      expect(decision.isStreetLevel, isFalse);
      expect(decision.applyCockpitCamera, isFalse);
      expect(decision.previewRouteRestoreEligible, isTrue);
    });
  });
}
