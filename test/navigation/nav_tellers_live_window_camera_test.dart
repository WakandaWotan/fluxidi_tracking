// NAV-TELLERS-COMPOSITION-CORRECTION-1
//
// The Tellers live-navigation window camera padding must fit the follow camera
// into the dedicated live region: the right-hand column in landscape and the
// band between the top meters panel and bottom controls in portrait. Padding
// only — never View level / zoom / pitch, and never the normal follow path.

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';

void main() {
  group('driverTellersLiveWindowCameraPadding', () {
    test('landscape reserves the left meters column (focus on right window)', () {
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

      // Left inset equals horizontal padding + meters flex share + gap.
      const hPad = 20.0;
      const gap = 12.0;
      final avail = w - 2 * hPad - gap;
      final metersWidth = avail * 5.0 / (5.0 + 6.0);
      final expectedLeft = hPad + metersWidth + gap;
      expect(pad.left, closeTo(expectedLeft, 0.5));

      // The focus is biased to the right window: left inset dominates.
      expect(pad.left, greaterThan(w * 0.4));
      expect(pad.right, lessThan(pad.left));
      // Bounds stay on-screen.
      expect(pad.left + pad.right, lessThan(w));
    });

    test('phone landscape uses larger meters flex share', () {
      const w = 800.0;
      final pad = driverTellersLiveWindowCameraPadding(
        screenWidth: w,
        screenHeight: 380,
        isLandscape: true,
        isTablet: false,
        safeTop: 0,
        safeBottom: 0,
      );
      const hPad = 12.0;
      const gap = 12.0;
      final avail = w - 2 * hPad - gap;
      final metersWidth = avail * 6.0 / (6.0 + 5.0);
      expect(pad.left, closeTo(hPad + metersWidth + gap, 0.5));
      expect(pad.left, greaterThan(pad.right));
    });

    test('portrait reserves the top meters panel and bottom controls', () {
      final pad = driverTellersLiveWindowCameraPadding(
        screenWidth: 834,
        screenHeight: 1194,
        isLandscape: false,
        isTablet: true,
        safeTop: 24,
        safeBottom: 16,
      );
      // Top reserves safe area + vertical pad + meters panel; bottom reserves
      // safe area + vertical pad + controls. Both leave a live band between.
      expect(pad.top, greaterThan(pad.bottom));
      expect(pad.top, greaterThan(200));
      expect(pad.bottom, greaterThan(0));
      // The live band is genuinely present (insets do not consume all height).
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
