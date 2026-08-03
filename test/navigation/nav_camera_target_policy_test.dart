import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_target_policy.dart';

void main() {
  group('NAV-R12-E1 NavCameraTargetPolicy', () {
    test('reliable route uses the snapped/progress target', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          hasReliableSnap: true,
          cameraScore: 80.0,
        ),
      );
      expect(d.source, NavCameraTargetSource.routeSnap);
      expect(d.forceRawTarget, isFalse);
      expect(d.reason, 'reliable_route');
    });

    test('route deviation forces the raw live target', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          routeDeviationLikely: true,
          hasReliableSnap: true,
          cameraScore: 90.0,
        ),
      );
      expect(d.source, NavCameraTargetSource.rawLive);
      expect(d.forceRawTarget, isTrue);
      expect(d.reason, 'route_adaptation');
    });

    test('opposite direction and backward progress force raw live', () {
      for (final input in const <NavCameraTargetInput>[
        NavCameraTargetInput(
          followMode: true,
          oppositeDirectionLikely: true,
          hasReliableSnap: true,
        ),
        NavCameraTargetInput(
          followMode: true,
          backwardProgressLikely: true,
          hasReliableSnap: true,
        ),
      ]) {
        final d = NavCameraTargetPolicy.resolve(input);
        expect(d.source, NavCameraTargetSource.rawLive);
        expect(d.forceRawTarget, isTrue);
        expect(d.reason, startsWith('route_adaptation'));
      }
    });

    test('off-route uses raw live target', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          offRouteLikely: true,
          hasReliableSnap: true,
        ),
      );
      expect(d.source, NavCameraTargetSource.rawLive);
      expect(d.forceRawTarget, isTrue);
      expect(d.reason, 'off_route');
    });

    test('strong mismatch suspicion forces raw live before full off-route', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          strongMismatchSuspected: true,
          hasReliableSnap: true,
          cameraScore: 90,
        ),
      );
      expect(d.source, NavCameraTargetSource.rawLive);
      expect(d.forceRawTarget, isTrue);
      expect(d.reason, 'route_adaptation_mismatch');
    });

    test('prediction is never used during deviation, even when fresh', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          routeDeviationLikely: true,
          predictionActive: true,
          predictionAgeMs: 100,
          cameraScore: 95.0,
        ),
      );
      expect(d.source, NavCameraTargetSource.rawLive);
      expect(d.forceRawTarget, isTrue);
    });

    test('fresh confident prediction may drive the camera on-route', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          predictionActive: true,
          predictionAgeMs: 600,
          cameraScore: 70.0,
          hasReliableSnap: true,
        ),
      );
      expect(d.source, NavCameraTargetSource.prediction);
      expect(d.reason, 'prediction_fresh');
    });

    test('stale prediction is rejected and falls back to route snap', () {
      final d = NavCameraTargetPolicy.resolve(
        NavCameraTargetInput(
          followMode: true,
          predictionActive: true,
          predictionAgeMs: NavCameraTargetPolicy.maxPredictionAgeMs + 1,
          cameraScore: 70.0,
          hasReliableSnap: true,
        ),
      );
      expect(d.source, NavCameraTargetSource.routeSnap);
      expect(d.reason, 'prediction_stale');
    });

    test('stale prediction without reliable snap falls back to raw live', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          predictionActive: true,
          predictionAgeMs: null, // unknown age is treated as stale
          cameraScore: 70.0,
        ),
      );
      expect(d.source, NavCameraTargetSource.rawLive);
      expect(d.reason, 'prediction_stale');
    });

    test('low camera confidence rejects prediction', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: true,
          predictionActive: true,
          predictionAgeMs: 200,
          cameraScore: NavCameraTargetPolicy.minPredictionCameraScore - 1.0,
          hasReliableSnap: true,
        ),
      );
      expect(d.source, NavCameraTargetSource.routeSnap);
      expect(d.reason, 'prediction_low_confidence');
    });

    test('manual/follow gate prevents forced camera follow', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(followMode: false),
      );
      expect(d.source, NavCameraTargetSource.skipped);
      expect(d.reason, 'not_follow_mode');
    });

    test('manual recenter is allowed outside follow mode', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(
          followMode: false,
          manualRecenter: true,
          hasReliableSnap: true,
        ),
      );
      expect(d.source, NavCameraTargetSource.routeSnap);
    });

    test('no reliable snap on-route follows raw live position', () {
      final d = NavCameraTargetPolicy.resolve(
        const NavCameraTargetInput(followMode: true, cameraScore: 60.0),
      );
      expect(d.source, NavCameraTargetSource.rawLive);
      expect(d.reason, 'no_reliable_snap');
      expect(d.forceRawTarget, isFalse);
    });
  });
}
