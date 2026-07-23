// NAV-TELLERS-COMPOSITION-CORRECTION-1
// NAV-TELLERS-EXACT-LIVE-VIEWPORT-1
//
// The Tellers live-navigation window camera padding must equal the padding
// derived from DriverTellersLayoutGeometry.liveWindowRect. Padding only —
// never View level / zoom / pitch, and never the normal follow path.

import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/driver_tellers_layout_geometry.dart';

void main() {
  group('driverTellersLiveWindowCameraPadding', () {
    test('landscape padding matches authoritative ~44% left geometry', () {
      const w = 1194.0;
      const h = 834.0;
      final pad = driverTellersLiveWindowCameraPadding(
        screenWidth: w,
        screenHeight: h,
        isLandscape: true,
        isTablet: true,
        safeTop: 0,
        safeBottom: 0,
      );
      final geo = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(w, h),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: true,
      );
      expect(pad.left, closeTo(geo.cameraPadding.left, 0.01));
      expect(pad.left, greaterThan(w * 0.4));
      expect(pad.right, lessThan(pad.left));
      expect(pad.left + pad.right, lessThan(w));
      expect(
        geo.landscapeLeftWidthFraction,
        closeTo(kTellersLandscapeLeftWidthFraction, 0.01),
      );
    });

    test('phone landscape uses the same 44% left share', () {
      const w = 800.0;
      final pad = driverTellersLiveWindowCameraPadding(
        screenWidth: w,
        screenHeight: 380,
        isLandscape: true,
        isTablet: false,
        safeTop: 0,
        safeBottom: 0,
      );
      final geo = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(w, 380),
        safeTop: 0,
        safeBottom: 0,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: true,
        isTablet: false,
      );
      expect(pad.left, closeTo(geo.cameraPadding.left, 0.01));
      expect(pad.left, greaterThan(pad.right));
    });

    test('portrait reserves top meters and bottom controls via geometry', () {
      final pad = driverTellersLiveWindowCameraPadding(
        screenWidth: 834,
        screenHeight: 1194,
        isLandscape: false,
        isTablet: true,
        safeTop: 24,
        safeBottom: 16,
      );
      final geo = DriverTellersLayoutGeometry.resolve(
        viewportSize: const Size(834, 1194),
        safeTop: 24,
        safeBottom: 16,
        safeLeft: 0,
        safeRight: 0,
        isLandscape: false,
        isTablet: true,
      );
      expect(pad.top, closeTo(geo.cameraPadding.top, 0.01));
      expect(pad.bottom, closeTo(geo.cameraPadding.bottom, 0.01));
      expect(pad.top, greaterThan(pad.bottom));
      expect(pad.top + pad.bottom, lessThan(1194));
    });

    test('padding is always non-negative and on-screen', () {
      for (final landscape in <bool>[false, true]) {
        for (final tablet in <bool>[false, true]) {
          final pad = driverTellersLiveWindowCameraPadding(
            screenWidth: landscape ? 900 : 400,
            screenHeight: landscape ? 420 : 900,
            isLandscape: landscape,
            isTablet: tablet,
            safeTop: 10,
            safeBottom: 10,
          );
          expect(pad.left, greaterThanOrEqualTo(0));
          expect(pad.right, greaterThanOrEqualTo(0));
          expect(pad.top, greaterThanOrEqualTo(0));
          expect(pad.bottom, greaterThanOrEqualTo(0));
        }
      }
    });
  });
}
