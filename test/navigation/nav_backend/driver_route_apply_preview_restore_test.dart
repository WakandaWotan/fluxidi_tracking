import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';

// NAV-PRESTART-FIELD-BLOCKER-3 (Problem A) unit tests.
//
// `mayRestoreRouteRender` used to short-circuit `navigationLive == false` as a
// hard reject. The widened contract now also accepts a valid preview draft:
// `previewRestoreEligible == true`. Every other owner clock (session, style,
// render-epoch, route-steps-version) must keep rejecting as before.

void main() {
  group('mayRestoreRouteRender - preview draft eligibility', () {
    test('legacy: pre-start without preview flag still rejects', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 12,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 1,
          navigationLive: false,
        ),
        isFalse,
      );
    });

    test('preview eligible + not live: allowed', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 12,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 1,
          navigationLive: false,
          previewRestoreEligible: true,
        ),
        isTrue,
      );
    });

    test('live ride: allowed regardless of preview flag', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 12,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 1,
          navigationLive: true,
        ),
        isTrue,
      );
    });

    test('preview eligible but routeCoordCount < 2: rejected', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 1,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 1,
          navigationLive: false,
          previewRestoreEligible: true,
        ),
        isFalse,
      );
    });

    test('preview eligible but render epoch bumped: rejected', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 12,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 2,
          navigationLive: false,
          previewRestoreEligible: true,
        ),
        isFalse,
      );
    });

    test('preview eligible but session generation mismatch: rejected', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 12,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 1,
          capturedSessionGeneration: 1,
          currentSessionGeneration: 2,
          navigationLive: false,
          previewRestoreEligible: true,
        ),
        isFalse,
      );
    });

    test('preview eligible but style generation mismatch: rejected', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 12,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 1,
          capturedStyleGeneration: 1,
          currentStyleGeneration: 2,
          navigationLive: false,
          previewRestoreEligible: true,
        ),
        isFalse,
      );
    });

    test('preview eligible but route steps version mismatch: rejected', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 12,
          capturedRenderEpoch: 1,
          currentRenderEpoch: 1,
          capturedRouteStepsVersion: 1,
          currentRouteStepsVersion: 2,
          navigationLive: false,
          previewRestoreEligible: true,
        ),
        isFalse,
      );
    });
  });
}
