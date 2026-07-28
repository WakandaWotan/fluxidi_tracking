import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';

// NAV-PRESTART-FIELD-BLOCKER-3 (Problem B + C) unit tests.
//
// The pre-start preview only exposes two presentation options - overview and
// street view. North-up is a live-only mode. `normaliseNavCameraViewModeForPreview`
// makes sure a lingering north-up selection cannot leak into a preview session.

void main() {
  group('normaliseNavCameraViewModeForPreview', () {
    test('overview stays overview', () {
      expect(
        normaliseNavCameraViewModeForPreview(NavCameraViewMode.overview),
        NavCameraViewMode.overview,
      );
    });

    test('streetView stays streetView', () {
      expect(
        normaliseNavCameraViewModeForPreview(NavCameraViewMode.streetView),
        NavCameraViewMode.streetView,
      );
    });

    test('northUp collapses into overview', () {
      expect(
        normaliseNavCameraViewModeForPreview(NavCameraViewMode.northUp),
        NavCameraViewMode.overview,
      );
    });
  });
}
