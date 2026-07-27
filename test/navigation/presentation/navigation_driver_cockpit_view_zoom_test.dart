import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_view_zoom.dart';

void main() {
  group('NAV-PRES-TABLET-CONTROLS-ZOOM-1 view zoom lifecycle', () {
    final t0 = DateTime(2026, 7, 12, 10);

    test('rapid View + taps apply only latest level', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(8, t0);
      expect(g1, 1);
      expect(lifecycle.requestedLevel, 8);
      expect(lifecycle.beginCamera(g1), isTrue);

      // NAV-ZOOM-FIELD-REPAIR-1: the newest View + no longer starts a second
      // concurrent flight. It becomes the single coalesced pending target and
      // the in-flight owner replays to it on completion.
      final g2 = lifecycle.requestManualLevel(9, t0);
      expect(g2, 2);
      expect(lifecycle.beginCamera(g2), isFalse);
      expect(lifecycle.inFlightGeneration, g1);
      expect(lifecycle.requestedLevel, 9);

      // The superseded finish releases ownership and asks for a rerun.
      expect(
        lifecycle.finishCamera(requestGeneration: g1, appliedLevel: 8, now: t0),
        isTrue,
      );
      expect(lifecycle.cameraInFlight, isFalse);
      expect(lifecycle.appliedLevel, isNull);

      // The rerun runs for the newest generation only.
      expect(lifecycle.latestTargetAlreadyOwned(), isFalse);
      expect(lifecycle.beginCamera(g2), isTrue);
      expect(
        lifecycle.finishCamera(requestGeneration: g2, appliedLevel: 9, now: t0),
        isFalse,
      );
      expect(lifecycle.appliedLevel, 9);
      expect(lifecycle.cameraInFlight, isFalse);
    });

    test('stale cancelCamera cannot clear newer View +/- owner', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(8, t0);
      expect(lifecycle.beginCamera(g1), isTrue);
      lifecycle.cancelCamera(requestGeneration: g1);

      final g2 = lifecycle.requestManualLevel(10, t0);
      expect(lifecycle.beginCamera(g2), isTrue);
      lifecycle.cancelCamera(requestGeneration: g1);
      expect(lifecycle.cameraInFlight, isTrue);
      expect(lifecycle.inFlightGeneration, g2);
      lifecycle.cancelCamera(requestGeneration: g2);
      expect(lifecycle.cameraInFlight, isFalse);
    });

    test('rapid View +/- mixed taps apply latest request', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      lifecycle.requestManualLevel(8, t0);
      lifecycle.requestManualLevel(7, t0);
      final g3 = lifecycle.requestManualLevel(10, t0);
      expect(lifecycle.requestedLevel, 10);
      expect(lifecycle.beginCamera(g3), isTrue);
      expect(
        lifecycle.finishCamera(
          requestGeneration: g3,
          appliedLevel: 10,
          now: t0,
        ),
        isFalse,
      );
      expect(lifecycle.appliedLevel, 10);
    });

    test('stale camera completion ignored', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(6, t0);
      lifecycle.requestManualLevel(11, t0);
      expect(lifecycle.shouldIgnoreStaleCamera(g1), isTrue);
      expect(
        lifecycle.finishCamera(requestGeneration: g1, appliedLevel: 6, now: t0),
        isTrue,
      );
      expect(lifecycle.appliedLevel, isNull);
    });

    test('passive follow blocked during manual ownership window', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      lifecycle.requestManualLevel(7, t0);
      expect(lifecycle.blocksPassiveFollow(t0), isTrue);
      expect(
        lifecycle.blocksPassiveFollow(
          t0.add(
            const Duration(
              milliseconds: kDriverCockpitViewZoomManualOwnershipMs,
            ),
          ),
        ),
        isFalse,
      );
    });

    test('passive follow resumes after ownership window', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      lifecycle.requestManualLevel(7, t0);
      final afterWindow = t0.add(
        const Duration(
          milliseconds: kDriverCockpitViewZoomManualOwnershipMs + 1,
        ),
      );
      expect(lifecycle.blocksPassiveFollow(afterWindow), isFalse);
    });

    test('tablet manual animation target stays within 180-280 ms', () {
      expect(
        resolveDriverCockpitViewZoomAnimationMs(
          isTablet: true,
          manualViewAdjust: true,
        ),
        inInclusiveRange(180, 280),
      );
      expect(
        resolveDriverCockpitViewZoomAnimationMs(
          isTablet: false,
          manualViewAdjust: true,
        ),
        kDriverCockpitViewZoomAnimationMsPhone,
      );
    });
  });
}
