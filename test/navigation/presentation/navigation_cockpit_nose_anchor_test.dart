import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

void main() {
  group('NAV-PRES-3N cockpit nose anchor calibration', () {
    const tabletViewport = 1100.0;
    const phoneViewport = 800.0;
    const tabletBottomHud = 222.0;
    const phoneBottomHud = 202.0;

    DriverCockpitNoseAnchorResult resolveTablet({
      required int level,
      required double zoom,
      required double pitch,
      required double hudSize,
    }) {
      return resolveDriverCockpitNoseAnchorFraction(
        isTablet: true,
        isLandscape: false,
        viewLevel: level,
        appliedZoom: zoom,
        appliedPitch: pitch,
        hudVehicleSizePx: hudSize,
        viewportHeightPx: tabletViewport,
        bottomHudHeightPx: tabletBottomHud,
      );
    }

    DriverCockpitNoseAnchorResult resolvePhone({
      required int level,
      required double zoom,
      required double pitch,
      required double hudSize,
    }) {
      return resolveDriverCockpitNoseAnchorFraction(
        isTablet: false,
        isLandscape: false,
        viewLevel: level,
        appliedZoom: zoom,
        appliedPitch: pitch,
        hudVehicleSizePx: hudSize,
        viewportHeightPx: phoneViewport,
        bottomHudHeightPx: phoneBottomHud,
      );
    }

    test('nose anchor changes when HUD vehicle size changes', () {
      final smallHud = resolveTablet(
        level: 7,
        zoom: 18.4,
        pitch: 75.0,
        hudSize: 132.0,
      );
      final largeHud = resolveTablet(
        level: 7,
        zoom: 18.4,
        pitch: 75.0,
        hudSize: 208.0,
      );
      expect(largeHud.anchorFraction, isNot(smallHud.anchorFraction));
      expect(largeHud.anchorFraction, lessThan(smallHud.anchorFraction));
    });

    test('nose anchor changes when pitch changes with same zoom', () {
      final lowPitch = resolveTablet(
        level: 7,
        zoom: 18.4,
        pitch: 55.0,
        hudSize: 166.0,
      );
      final highPitch = resolveTablet(
        level: 7,
        zoom: 18.4,
        pitch: 84.0,
        hudSize: 166.0,
      );
      expect(highPitch.anchorFraction, greaterThan(lowPitch.anchorFraction));
    });

    test('nose anchor changes when zoom changes with same pitch', () {
      final zoomedIn = resolveTablet(
        level: 7,
        zoom: 21.0,
        pitch: 75.0,
        hudSize: 166.0,
      );
      final zoomedOut = resolveTablet(
        level: 7,
        zoom: 16.8,
        pitch: 75.0,
        hudSize: 166.0,
      );
      expect(zoomedOut.anchorFraction, greaterThan(zoomedIn.anchorFraction));
    });

    test('tablet View 13 anchor differs from tablet View 1 in expected direction', () {
      final view1 = resolveDriverCockpitNoseAnchorFraction(
        isTablet: true,
        isLandscape: false,
        viewLevel: 1,
        appliedZoom: kDriverCockpitPro2CompactZoomL1,
        appliedPitch: kDriverCockpitPro2CompactPitchL1,
        hudVehicleSizePx: kDriverCockpitPro2HudTabletL1,
        viewportHeightPx: tabletViewport,
        bottomHudHeightPx: tabletBottomHud,
      );
      final view13 = resolveDriverCockpitNoseAnchorFraction(
        isTablet: true,
        isLandscape: false,
        viewLevel: 13,
        appliedZoom: kDriverCockpitPro2CompactZoomL13,
        appliedPitch: kDriverCockpitPro2CompactPitchL13,
        hudVehicleSizePx: kDriverCockpitPro2HudTabletL13,
        viewportHeightPx: tabletViewport,
        bottomHudHeightPx: tabletBottomHud,
      );
      expect(view1.anchorFraction, isNot(view13.anchorFraction));
      expect(view1.anchorFraction, greaterThan(view13.anchorFraction));
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
      final first = resolvePhone(
        level: 7,
        zoom: 19.1,
        pitch: 77.0,
        hudSize: 112.0,
      );
      final second = resolvePhone(
        level: 7,
        zoom: 19.1,
        pitch: 77.0,
        hudSize: 112.0,
      );
      expect(first.anchorFraction, second.anchorFraction);
      expect(first.result, second.result);
    });

    test('phone View 7 baseline stays near professional anchor', () {
      final phoneL7 = resolvePhone(
        level: 7,
        zoom: kDriverCockpitPro2PhoneZoomL7,
        pitch: kDriverCockpitPro2PhonePitchL7,
        hudSize: kDriverCockpitPro2HudPhoneL7,
      );
      expect(
        phoneL7.anchorFraction,
        closeTo(kDriverCockpitPro2PhoneAnchorL7, 0.08),
      );
    });

    test('overview zoom-out shifts anchor down more than streetlevel', () {
      final overview = resolveTablet(
        level: 1,
        zoom: kDriverCockpitPro2CompactZoomL1,
        pitch: kDriverCockpitPro2CompactPitchL1,
        hudSize: kDriverCockpitPro2HudTabletL1,
      );
      final street = resolveTablet(
        level: 13,
        zoom: kDriverCockpitPro2CompactZoomL13,
        pitch: kDriverCockpitPro2CompactPitchL13,
        hudSize: kDriverCockpitPro2HudTabletL13,
      );
      expect(overview.anchorFraction, greaterThan(street.anchorFraction));
    });

    test('invalid inputs fall back without throwing', () {
      final skipped = resolveDriverCockpitNoseAnchorFraction(
        isTablet: false,
        isLandscape: false,
        viewLevel: 7,
        appliedZoom: 18.0,
        appliedPitch: 70.0,
        hudVehicleSizePx: 0.0,
        viewportHeightPx: 800.0,
        bottomHudHeightPx: 200.0,
      );
      expect(skipped.result, 'skipped');
      expect(skipped.anchorFraction, greaterThan(0.0));
    });
  });
}
