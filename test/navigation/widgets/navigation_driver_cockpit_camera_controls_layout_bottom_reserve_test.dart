import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/widgets/navigation_driver_cockpit_camera_controls_layout.dart';

// NAV-PRESTART-FIELD-BLOCKER-3 (Problem D) unit tests.
//
// Phone portrait phones (360 / 390 / 412 dp) had the zoom column anchored at
// a fixed 168 dp above the safe-area bottom. That anchor was smaller than the
// real bottom chrome (cockpit + secondary row + optional fare-estimate panel),
// so the minus button sat behind the cockpit and the plus button behind the
// secondary row. `bottomStripReserve` now lifts the column above the measured
// chrome without changing the layout when the chrome fits under the fixed
// anchor (backwards compatible for tablet and landscape callers).

void main() {
  const double kPortraitZoomStackHeight = 106.0;
  const double kPortraitZoomStackWidth = 48.0;

  double runPortraitBottom({
    required double bottomStripReserve,
    double screenHeight = 800.0,
    double safeBottom = 24.0,
  }) {
    final layout = resolveDriverCockpitCameraControlsLayout(
      screenHeight: screenHeight,
      safeTop: 30.0,
      safeBottom: safeBottom,
      safeRight: 0.0,
      isLandscape: false,
      panelHeight: kPortraitZoomStackHeight,
      panelWidth: kPortraitZoomStackWidth,
      bottomStripReserve: bottomStripReserve,
    );
    return layout.bottom;
  }

  group('portrait bottomStripReserve', () {
    test('no reserve: keeps legacy 168dp anchor', () {
      final layout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: 800.0,
        safeTop: 30.0,
        safeBottom: 24.0,
        safeRight: 0.0,
        isLandscape: false,
        panelHeight: kPortraitZoomStackHeight,
        panelWidth: kPortraitZoomStackWidth,
      );
      expect(layout.bottom, closeTo(24.0 + 168.0, 0.01));
      expect(layout.reason, 'portrait_above_cockpit');
    });

    test('small reserve (< 168dp): still legacy anchor', () {
      expect(
        runPortraitBottom(bottomStripReserve: 90.0),
        closeTo(24.0 + 168.0, 0.01),
      );
    });

    test('measured chrome larger than legacy anchor lifts the panel', () {
      final measured = 90.0 + 48.0 + 96.0;
      final expectedBottom = 24.0 + measured + 14.0;
      expect(
        runPortraitBottom(bottomStripReserve: measured),
        closeTo(expectedBottom, 0.01),
      );
    });

    test('bottom reserve applies on 360x800 dp phone', () {
      final layout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: 800.0,
        safeTop: 30.0,
        safeBottom: 24.0,
        safeRight: 0.0,
        isLandscape: false,
        panelHeight: kPortraitZoomStackHeight,
        panelWidth: kPortraitZoomStackWidth,
        bottomStripReserve: 234.0,
      );
      expect(layout.bottom, greaterThan(24.0 + 168.0));
      expect(layout.reason, 'portrait_above_measured_chrome');
      expect(
        layout.panelTop,
        greaterThanOrEqualTo(30.0 + 14.0),
      );
    });

    test('bottom reserve does not extend into the top safe area', () {
      final layout = resolveDriverCockpitCameraControlsLayout(
        screenHeight: 640.0,
        safeTop: 30.0,
        safeBottom: 24.0,
        safeRight: 0.0,
        isLandscape: false,
        panelHeight: kPortraitZoomStackHeight,
        panelWidth: kPortraitZoomStackWidth,
        bottomStripReserve: 900.0,
      );
      expect(layout.clamped, isTrue);
      expect(layout.panelTop, greaterThanOrEqualTo(30.0 + 14.0));
    });

    test('landscape ignores bottomStripReserve', () {
      final legacy = resolveDriverCockpitCameraControlsLayout(
        screenHeight: 400.0,
        safeTop: 20.0,
        safeBottom: 20.0,
        safeRight: 0.0,
        isLandscape: true,
        panelHeight: kPortraitZoomStackHeight,
        panelWidth: kPortraitZoomStackWidth,
      );
      final measured = resolveDriverCockpitCameraControlsLayout(
        screenHeight: 400.0,
        safeTop: 20.0,
        safeBottom: 20.0,
        safeRight: 0.0,
        isLandscape: true,
        panelHeight: kPortraitZoomStackHeight,
        panelWidth: kPortraitZoomStackWidth,
        bottomStripReserve: 500.0,
      );
      expect(measured.bottom, closeTo(legacy.bottom, 0.01));
      expect(measured.panelTop, closeTo(legacy.panelTop, 0.01));
    });
  });
}
