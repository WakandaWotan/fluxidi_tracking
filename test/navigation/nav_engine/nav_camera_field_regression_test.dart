import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_prestart_presentation.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_marker_anchor.dart';

// NAV-CAMERA-FIELD-REGRESSION-1 / NAV-RELEASE-SIMPLE-STREETLEVEL-1
//
// Pins camera ownership: fixed streetlevel wins; fitBounds never owns the
// release surface; style switch restores streetlevel; Pro2 L7 stays in bounds.

void main() {
  group('mayOverviewFitBoundsInPreview', () {
    test('release surface: fitBounds never permitted', () {
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isFalse,
      );
      expect(
        mayOverviewFitBoundsInPreview(
          allowOverviewCamera: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          liveRideActive: false,
        ),
        isFalse,
      );
    });
  });

  group('mayRestorePreviewCockpitCameraAfterStyleSwitch', () {
    test('any preview draft: restore required', () {
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.overview,
          liveRideActive: false,
        ),
        isTrue,
      );
      expect(
        mayRestorePreviewCockpitCameraAfterStyleSwitch(
          hasPreviewDraft: true,
          selectedViewMode: NavPreviewViewModeTokens.streetView,
          liveRideActive: false,
        ),
        isTrue,
      );
    });

    test('live ride: preview restore stays off', () {
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
      expect(zoom, greaterThan(15.0));
      expect(zoom, lessThan(22.5));
      expect(pitch, greaterThan(60.0));
      expect(pitch, lessThan(85.0));
    });

    test('phone L7 is the proven driving profile', () {
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
    });

    test('fare estimate chrome increases marker bottom offset', () {
      final without = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 48,
        primaryToSecondaryGap: 8,
      );
      final withFare = resolveStreetLevelMarkerBottomOffset(
        isLandscape: false,
        hasSecondaryActions: true,
        secondaryActionRowHeight: 48,
        primaryToSecondaryGap: 8,
        extraBottomChrome: 96,
      );
      expect(withFare, greaterThan(without));
    });
  });
}
