import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_decision.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';

NavRouteProgressOutput _progress({
  bool offRouteLikely = false,
  bool routeDeviationLikely = false,
  bool oppositeDirectionLikely = false,
  bool backwardProgressLikely = false,
  String routeDeviationReason = 'none',
  double snapDistanceM = 5.0,
  double confidence = 80.0,
  bool hasReliableSnap = true,
  double? headingDeltaDeg,
}) {
  return NavRouteProgressOutput(
    hasReliableSnap: hasReliableSnap,
    snapDistanceM: snapDistanceM,
    confidence: confidence,
    forwardProgress: !backwardProgressLikely,
    offRouteLikely: offRouteLikely,
    routeDeviationLikely: routeDeviationLikely,
    oppositeDirectionLikely: oppositeDirectionLikely,
    backwardProgressLikely: backwardProgressLikely,
    routeDeviationReason: routeDeviationReason,
    headingDeltaDeg: headingDeltaDeg,
    reason: offRouteLikely ? 'off_route_likely' : 'reliable_snap',
  );
}

NavRerouteDecisionTickInput _tick({
  required NavRouteProgressOutput progress,
  double speedKmh = 30.0,
  DateTime? now,
  DateTime? lastRerouteAt,
  bool lastRerouteFailed = false,
}) {
  return NavRerouteDecisionTickInput(
    progress: progress,
    snapDistanceM: progress.snapDistanceM,
    speedKmh: speedKmh,
    offRouteThresholdM: 95.0,
    now: now ?? DateTime.utc(2026, 1, 1, 12, 0, 0),
    lastRerouteAt: lastRerouteAt,
    lastRerouteFailed: lastRerouteFailed,
    allowReroutePhase: true,
    liveRideActive: true,
    hasRoute: true,
  );
}

void main() {
  group('NAV-R17A NavRerouteDecision', () {
    test('sustained opposite-direction movement becomes reroute eligible', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final strongOpposite = _progress(
        offRouteLikely: true,
        routeDeviationLikely: true,
        oppositeDirectionLikely: true,
        routeDeviationReason: 'opposite_heading_strong',
        headingDeltaDeg: 175.0,
        hasReliableSnap: false,
      );

      final first = tracker.update(
        _tick(progress: strongOpposite, speedKmh: 25.0, now: t0),
      );
      expect(first.offRouteLikely, isTrue);
      expect(first.offRouteReason, 'opposite_direction_strong');
      expect(first.movementOk, isTrue);

      final second = tracker.update(
        _tick(
          progress: strongOpposite,
          speedKmh: 25.0,
          now: t0.add(const Duration(milliseconds: 600)),
        ),
      );
      expect(second.eligible, isTrue);
      expect(second.shouldTrigger, isTrue);
    });

    test('stationary parking heading noise does not trigger reroute', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final parkedOffRoute = _progress(
        offRouteLikely: true,
        snapDistanceM: 72.0,
        confidence: 35.0,
        hasReliableSnap: false,
      );

      for (var i = 0; i < 5; i++) {
        final out = tracker.update(
          _tick(
            progress: parkedOffRoute,
            speedKmh: 0.5,
            now: t0.add(Duration(seconds: i)),
          ),
        );
        expect(out.movementOk, isFalse);
        expect(out.shouldTrigger, isFalse);
      }
    });

    test('cooldown prevents reroute spam', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final deviation = _progress(
        offRouteLikely: true,
        routeDeviationLikely: true,
        oppositeDirectionLikely: true,
        backwardProgressLikely: true,
        routeDeviationReason: 'backward_progress',
        hasReliableSnap: false,
      );

      tracker.update(_tick(progress: deviation, speedKmh: 20.0, now: t0));
      final trigger = tracker.update(
        _tick(
          progress: deviation,
          speedKmh: 20.0,
          now: t0.add(const Duration(seconds: 1)),
        ),
      );
      expect(trigger.shouldTrigger, isTrue);
      tracker.noteRerouteApplied(t0.add(const Duration(seconds: 1)));

      final blocked = tracker.update(
        _tick(
          progress: deviation,
          speedKmh: 20.0,
          now: t0.add(const Duration(seconds: 2)),
          lastRerouteAt: t0.add(const Duration(seconds: 1)),
        ),
      );
      expect(blocked.cooldownActive, isTrue);
      expect(blocked.eligible, isFalse);
      expect(blocked.shouldTrigger, isFalse);
    });

    test('route replacement only after eligibility and debounce', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);
      final deviation = _progress(
        offRouteLikely: true,
        routeDeviationLikely: true,
        oppositeDirectionLikely: true,
        routeDeviationReason: 'opposite_heading',
        hasReliableSnap: false,
      );

      final first = tracker.update(
        _tick(progress: deviation, speedKmh: 20.0, now: t0),
      );
      expect(first.offRouteLikely, isFalse);
      expect(first.shouldTrigger, isFalse);

      final second = tracker.update(
        _tick(
          progress: deviation,
          speedKmh: 20.0,
          now: t0.add(const Duration(milliseconds: 200)),
        ),
      );
      expect(second.offRouteLikely, isTrue);
      expect(second.eligible, isTrue);
      expect(second.shouldTrigger, isFalse);

      final third = tracker.update(
        _tick(
          progress: deviation,
          speedKmh: 20.0,
          now: t0.add(const Duration(milliseconds: 1000)),
        ),
      );
      expect(third.shouldTrigger, isTrue);
    });

    test('diagnostic buckets stay bounded without coordinates', () {
      expect(navRerouteHeadingDeltaBucket(128.0), '90-135');
      expect(navRerouteDistanceBucket(42.0), '30-60');
      expect(navRerouteMovementBucket(2.0), 'stopped');
    });
  });
}
