import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_stabilization.dart';

void main() {
  group('NavRerouteStabilization', () {
    final t0 = DateTime.utc(2026, 1, 1, 12, 0, 0);

    test('idle state allows opposite-direction reroutes', () {
      final gate = NavRerouteStabilization();
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0,
          snapDistanceM: 12,
          oppositeStrong: true,
          speedKmh: 30,
          currentRouteGeneration: 3,
        ),
        isTrue,
      );
    });

    test('opens after >=2 fresh in-generation samples', () {
      final gate = NavRerouteStabilization();
      gate.noteRerouteApplied(newRouteGeneration: 2, now: t0);

      // Off-generation samples must not count.
      gate.observeSample(
        routeGeneration: 1,
        snapDistanceM: 5,
        hasReliableSnap: true,
      );
      expect(gate.freshSamplesCollected, 0);

      // Unreliable-snap samples must not count.
      gate.observeSample(
        routeGeneration: 2,
        snapDistanceM: 5,
        hasReliableSnap: false,
      );
      expect(gate.freshSamplesCollected, 0);

      // One reliable in-generation sample: gate still closed.
      gate.observeSample(
        routeGeneration: 2,
        snapDistanceM: 5,
        hasReliableSnap: true,
      );
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 1)),
          snapDistanceM: 15,
          oppositeStrong: true,
          speedKmh: 10,
          currentRouteGeneration: 2,
        ),
        isFalse,
      );

      // Second reliable in-generation sample: gate opens.
      gate.observeSample(
        routeGeneration: 2,
        snapDistanceM: 5,
        hasReliableSnap: true,
      );
      expect(gate.freshSamplesCollected, 2);
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 1)),
          snapDistanceM: 15,
          oppositeStrong: true,
          speedKmh: 10,
          currentRouteGeneration: 2,
        ),
        isTrue,
      );
    });

    test('cooldown opens the gate without fresh samples', () {
      final gate = NavRerouteStabilization();
      gate.noteRerouteApplied(newRouteGeneration: 2, now: t0);
      // Still under cooldown.
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 4)),
          snapDistanceM: 15,
          oppositeStrong: true,
          speedKmh: 10,
          currentRouteGeneration: 2,
        ),
        isFalse,
      );
      // Past cooldown.
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(NavRerouteStabilization.cooldown),
          snapDistanceM: 15,
          oppositeStrong: true,
          speedKmh: 10,
          currentRouteGeneration: 2,
        ),
        isTrue,
      );
    });

    test('severe snap distance bypasses the gate', () {
      final gate = NavRerouteStabilization();
      gate.noteRerouteApplied(newRouteGeneration: 2, now: t0);
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 1)),
          snapDistanceM: NavRerouteStabilization.severeSnapDistanceM + 1,
          oppositeStrong: false,
          speedKmh: 10,
          currentRouteGeneration: 2,
        ),
        isTrue,
      );
    });

    test('strong opposite direction at high speed bypasses the gate', () {
      final gate = NavRerouteStabilization();
      gate.noteRerouteApplied(newRouteGeneration: 2, now: t0);
      // Low speed: still blocked.
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 1)),
          snapDistanceM: 20,
          oppositeStrong: true,
          speedKmh: 5,
          currentRouteGeneration: 2,
        ),
        isFalse,
      );
      // High speed with strong opposite: bypass.
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 1)),
          snapDistanceM: 20,
          oppositeStrong: true,
          speedKmh: NavRerouteStabilization.severeOppositeSpeedKmh + 1,
          currentRouteGeneration: 2,
        ),
        isTrue,
      );
    });

    test('newer route generation opens the gate (post-reroute is stale)', () {
      final gate = NavRerouteStabilization();
      gate.noteRerouteApplied(newRouteGeneration: 2, now: t0);
      // A subsequent reroute (route 3) already ran through us; the gate has
      // no evidence on route 3 yet, but is not stabilising route 3 either.
      expect(
        gate.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 1)),
          snapDistanceM: 15,
          oppositeStrong: true,
          speedKmh: 10,
          currentRouteGeneration: 3,
        ),
        isTrue,
      );
    });

    test('reset clears state', () {
      final gate = NavRerouteStabilization();
      gate.noteRerouteApplied(newRouteGeneration: 2, now: t0);
      gate.observeSample(
        routeGeneration: 2,
        snapDistanceM: 5,
        hasReliableSnap: true,
      );
      gate.reset();
      expect(gate.stabilizationActive, isFalse);
      expect(gate.freshSamplesCollected, 0);
      expect(gate.rerouteAppliedAt, isNull);
    });
  });
}
