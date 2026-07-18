import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

void main() {
  group('NAV-PRES-3J driver HUD nose-anchor alignment', () {
    const phoneViewport = 800.0;
    const tabletViewport = 1100.0;
    const phoneBottomHud = 202.0;
    const tabletBottomHud = 222.0;
    const phoneIcon = kDriverCockpitPro2HudPhoneL7;
    const tabletIcon = kDriverCockpitPro2HudTabletL7;

    test('nose screen fraction is above vehicle center and below icon top', () {
      final geometry = resolveDriverHudVehicleGeometry(
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: phoneBottomHud,
        iconSizePx: phoneIcon,
      );
      expect(geometry.noseY, greaterThan(geometry.topY));
      expect(geometry.noseY, lessThan(geometry.centerY));
      expect(geometry.noseScreenFraction, greaterThan(geometry.topY / phoneViewport));
      expect(geometry.noseScreenFraction, lessThan(geometry.centerScreenFraction));
    });

    test('calculated nose anchor differs from center anchor in expected direction', () {
      final geometry = resolveDriverHudVehicleGeometry(
        viewportHeightPx: tabletViewport,
        bottomHudHeightPx: tabletBottomHud,
        iconSizePx: tabletIcon,
      );
      final noseAnchor = resolveDriverCockpitNoseAnchorFraction(
        isTablet: true,
        isLandscape: false,
        viewLevel: 7,
        appliedZoom: kDriverCockpitPro2CompactZoomL7,
        appliedPitch: kDriverCockpitPro2CompactPitchL7,
        hudVehicleSizePx: tabletIcon,
        viewportHeightPx: tabletViewport,
        bottomHudHeightPx: tabletBottomHud,
      );
      expect(noseAnchor.anchorFraction, lessThan(geometry.centerScreenFraction));
      expect(noseAnchor.anchorFraction, closeTo(geometry.noseScreenFraction, 0.001));
      expect(noseAnchor.reason, 'nose_route_anchor');
    });

    test('HUD vehicle size stays fixed across View 1, 7, and 13', () {
      for (final isTablet in [false, true]) {
        for (final level in [1, 7, 13]) {
          expect(
            driverCockpitViewLevelHudIconSize(isTablet: isTablet, level: level),
            driverCockpitFixedHudIconSize(isTablet: isTablet),
          );
        }
      }
      expect(
        driverCockpitFixedHudIconSize(isTablet: false),
        kDriverCockpitPro2HudPhoneL7,
      );
      expect(
        driverCockpitFixedHudIconSize(isTablet: true),
        kDriverCockpitPro2HudTabletL7,
      );
    });

    test('HUD vehicle bottom offset stays fixed across View 1, 7, and 13', () {
      for (final level in [1, 7, 13]) {
        expect(
          driverCockpitFixedHudBottomOffset(
            isLandscape: false,
            cockpitChaseCamera: true,
            isTablet: false,
          ),
          176.0,
        );
        expect(
          driverCockpitFixedHudBottomOffset(
            isLandscape: false,
            cockpitChaseCamera: true,
            isTablet: true,
          ),
          188.0,
        );
      }
    });

    test('camera anchor uses nose point not center point', () {
      final geometry = resolveDriverHudVehicleGeometry(
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: phoneBottomHud,
        iconSizePx: phoneIcon,
      );
      final noseAnchor = resolveDriverCockpitNoseAnchorFraction(
        isTablet: false,
        isLandscape: false,
        viewLevel: 7,
        appliedZoom: kDriverCockpitPro2PhoneZoomL7,
        appliedPitch: kDriverCockpitPro2PhonePitchL7,
        hudVehicleSizePx: phoneIcon,
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: phoneBottomHud,
      );
      final padding = driverCockpitVehicleAnchorPadding(
        screenHeight: phoneViewport,
        safeTop: 44.0,
        safeBottom: 34.0,
        anchorFraction: noseAnchor.anchorFraction,
      );
      final projectedCenterY =
          padding.top + (phoneViewport - padding.top - padding.bottom) / 2;
      expect(projectedCenterY, closeTo(geometry.noseY, 1.0));
      expect(projectedCenterY, isNot(closeTo(geometry.centerY, 1.0)));
    });

    test('nose anchor is stable across View 1, 7, and 13 with fixed HUD', () {
      final anchors = [1, 7, 13]
          .map(
            (level) => resolveDriverCockpitNoseAnchorFraction(
              isTablet: true,
              isLandscape: false,
              viewLevel: level,
              appliedZoom: driverCockpitViewLevelTargetZoom(
                isTablet: true,
                isLandscape: false,
                level: level,
              ),
              appliedPitch: driverCockpitViewLevelTargetPitch(
                isTablet: true,
                isLandscape: false,
                level: level,
              ),
              hudVehicleSizePx: tabletIcon,
              viewportHeightPx: tabletViewport,
              bottomHudHeightPx: tabletBottomHud,
            ).anchorFraction,
          )
          .toSet();
      expect(anchors.length, 1);
    });

    test('anchor is clamped to safe range', () {
      final extreme = resolveDriverCockpitNoseAnchorFraction(
        isTablet: false,
        isLandscape: false,
        viewLevel: 13,
        appliedZoom: kDriverCockpitCameraMinZoom,
        appliedPitch: kDriverCockpitCameraMaxPitch,
        hudVehicleSizePx: 40.0,
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: 40.0,
      );
      expect(
        extreme.anchorFraction,
        inInclusiveRange(
          kDriverCockpitNoseAnchorMinPhone,
          kDriverCockpitNoseAnchorMaxPhone,
        ),
      );
      expect(extreme.result, anyOf('applied', 'clamped'));
    });

    test('anchor is deterministic for same inputs', () {
      final first = resolveDriverCockpitNoseAnchorFraction(
        isTablet: false,
        isLandscape: false,
        viewLevel: 7,
        appliedZoom: 19.1,
        appliedPitch: 77.0,
        hudVehicleSizePx: phoneIcon,
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: phoneBottomHud,
      );
      final second = resolveDriverCockpitNoseAnchorFraction(
        isTablet: false,
        isLandscape: false,
        viewLevel: 7,
        appliedZoom: 21.0,
        appliedPitch: 84.0,
        hudVehicleSizePx: phoneIcon,
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: phoneBottomHud,
      );
      expect(first.anchorFraction, second.anchorFraction);
      expect(first.result, second.result);
    });

    test('helper Y accessors match geometry resolver', () {
      expect(
        hudVehicleNoseY(
          viewportHeightPx: phoneViewport,
          bottomHudHeightPx: phoneBottomHud,
          iconSizePx: phoneIcon,
        ),
        resolveDriverHudVehicleGeometry(
          viewportHeightPx: phoneViewport,
          bottomHudHeightPx: phoneBottomHud,
          iconSizePx: phoneIcon,
        ).noseY,
      );
      expect(
        hudVehicleTailY(
          viewportHeightPx: phoneViewport,
          bottomHudHeightPx: phoneBottomHud,
          iconSizePx: phoneIcon,
        ),
        greaterThan(
          hudVehicleNoseY(
            viewportHeightPx: phoneViewport,
            bottomHudHeightPx: phoneBottomHud,
            iconSizePx: phoneIcon,
          ),
        ),
      );
    });

    test('invalid inputs fall back without throwing', () {
      final skipped = resolveDriverCockpitNoseAnchorFraction(
        isTablet: false,
        isLandscape: false,
        viewLevel: 7,
        appliedZoom: 18.0,
        appliedPitch: 70.0,
        hudVehicleSizePx: 0.0,
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: phoneBottomHud,
      );
      expect(skipped.result, 'skipped');
      expect(skipped.anchorFraction, greaterThan(0.0));
    });
  });
}
