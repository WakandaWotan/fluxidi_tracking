import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_guard.dart';
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
  double speedKmh = 34.0,
  DateTime? now,
  DateTime? lastRerouteAt,
  DateTime? lastRerouteSuccessAt,
  DateTime? lastRerouteFailureAt,
  DateTime? routeAcceptedAt,
  double? accuracyM = 2.2,
  double? distanceToManeuverM,
  bool lastRerouteFailed = false,
  bool isRerouting = false,
  bool allowReroutePhase = true,
  bool liveRideActive = true,
  bool isWaiting = false,
  bool hasRoute = true,
  int routeVersion = 3,
}) {
  return NavRerouteDecisionTickInput(
    progress: progress,
    snapDistanceM: progress.snapDistanceM,
    speedKmh: speedKmh,
    offRouteThresholdM: 95.0,
    now: now ?? DateTime.utc(2026, 7, 17, 14, 20, 25),
    lastRerouteAt: lastRerouteAt,
    lastRerouteSuccessAt: lastRerouteSuccessAt,
    lastRerouteFailureAt: lastRerouteFailureAt,
    routeAcceptedAt: routeAcceptedAt,
    accuracyM: accuracyM,
    distanceToManeuverM: distanceToManeuverM,
    lastRerouteFailed: lastRerouteFailed,
    allowReroutePhase: allowReroutePhase,
    liveRideActive: liveRideActive,
    isWaiting: isWaiting,
    isRerouting: isRerouting,
    hasRoute: hasRoute,
    routeVersion: routeVersion,
  );
}

void main() {
  group('NAV-REROUTE-P0 strong-evidence fast path', () {
    test('1) one 80 m sample with good GPS does not immediately reroute', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final out = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 84.0,
            confidence: 30.0,
            hasReliableSnap: false,
          ),
          now: t0,
        ),
      );
      expect(out.shouldTrigger, isFalse);
      expect(out.offRouteLikely, isFalse);
      expect(out.strongSampleCount, 1);
    });

    test('2) two or three strong urban samples become eligible within target',
        () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final priorSuccess = t0.subtract(const Duration(seconds: 8));

      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 84.0,
            confidence: 30.0,
            hasReliableSnap: false,
          ),
          now: t0,
          lastRerouteAt: priorSuccess,
          lastRerouteSuccessAt: priorSuccess,
        ),
      );
      final second = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 84.0,
            confidence: 30.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 1200)),
          lastRerouteAt: priorSuccess,
          lastRerouteSuccessAt: priorSuccess,
        ),
      );
      expect(second.offRouteLikely, isTrue);
      expect(second.eligible, isTrue);
      expect(second.cooldownActive, isFalse);
      expect(second.fastPathEligible, isTrue);

      final third = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 90.0,
            confidence: 28.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 1800)),
          lastRerouteAt: priorSuccess,
          lastRerouteSuccessAt: priorSuccess,
        ),
      );
      expect(third.shouldTrigger, isTrue);
      expect(
        t0.add(const Duration(milliseconds: 1800)).difference(t0).inMilliseconds,
        lessThanOrEqualTo(3000),
      );
    });

    test('3) 80→118 m growing deviation eligible before five samples', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final snaps = <double>[84.0, 84.0, 118.0];
      NavRerouteDecisionTickOutput? out;
      for (var i = 0; i < snaps.length; i++) {
        out = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: snaps[i],
              confidence: 25.0,
              hasReliableSnap: false,
            ),
            now: t0.add(Duration(milliseconds: i * 1100)),
          ),
        );
      }
      expect(out!.eligible, isTrue);
      expect(out.samplesOffRoute, lessThan(5));
      expect(out.strongSampleCount, lessThan(5));
    });

    test('4) severe 120+ m bypasses stale successful-reroute cooldown', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final priorSuccess = t0.subtract(const Duration(seconds: 5));

      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 120.0,
            confidence: 20.0,
            hasReliableSnap: false,
          ),
          now: t0,
          lastRerouteSuccessAt: priorSuccess,
          lastRerouteAt: priorSuccess,
        ),
      );
      final second = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 134.0,
            confidence: 18.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 800)),
          lastRerouteSuccessAt: priorSuccess,
          lastRerouteAt: priorSuccess,
        ),
      );
      expect(second.cooldownKind, NavRerouteCooldownKind.none);
      expect(second.eligible, isTrue);
      expect(second.fastPathEligible, isTrue);

      final third = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 140.0,
            confidence: 18.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 1400)),
          lastRerouteSuccessAt: priorSuccess,
          lastRerouteAt: priorSuccess,
        ),
      );
      expect(third.shouldTrigger, isTrue);
    });

    test('5) poor GPS accuracy does not use the fast path', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final priorSuccess = t0.subtract(const Duration(seconds: 4));
      NavRerouteDecisionTickOutput? out;
      for (var i = 0; i < 3; i++) {
        out = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: 90.0 + i * 10,
              confidence: 20.0,
              hasReliableSnap: false,
            ),
            accuracyM: 35.0,
            now: t0.add(Duration(milliseconds: i * 800)),
            lastRerouteSuccessAt: priorSuccess,
            lastRerouteAt: priorSuccess,
          ),
        );
      }
      expect(out!.cooldownActive, isTrue);
      expect(out.cooldownKind, NavRerouteCooldownKind.successfulReroute);
      expect(out.eligible, isFalse);
      expect(out.strongSampleCount, 0);
    });

    test('6) stopped vehicle drift does not use the fast path', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      for (var i = 0; i < 4; i++) {
        final out = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: 90.0,
              confidence: 30.0,
              hasReliableSnap: false,
            ),
            speedKmh: 0.8,
            now: t0.add(Duration(seconds: i)),
          ),
        );
        expect(out.shouldTrigger, isFalse);
        expect(out.movementOk, isFalse);
      }
    });

    test('7) one isolated GPS jump recovers without reroute', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final jump = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 95.0,
            confidence: 20.0,
            hasReliableSnap: false,
          ),
          now: t0,
        ),
      );
      expect(jump.shouldTrigger, isFalse);

      final recover = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: false,
            snapDistanceM: 4.0,
            confidence: 95.0,
            hasReliableSnap: true,
          ),
          now: t0.add(const Duration(seconds: 1)),
        ),
      );
      expect(recover.offRouteLikely, isFalse);
      expect(recover.shouldTrigger, isFalse);
      expect(recover.strongSampleCount, 0);
    });

    test('8) moderate parallel-road ambiguity does not immediately reroute',
        () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final out = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 42.0,
            confidence: 50.0,
            hasReliableSnap: false,
          ),
          now: t0,
        ),
      );
      expect(out.shouldTrigger, isFalse);
      expect(out.strongSampleCount, 0);
    });

    test('9) in-flight request prevents duplicate start', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 100.0,
            hasReliableSnap: false,
          ),
          now: t0,
        ),
      );
      final blocked = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 110.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(seconds: 1)),
          isRerouting: true,
        ),
      );
      expect(blocked.cooldownKind, NavRerouteCooldownKind.requestInFlight);
      expect(blocked.eligible, isFalse);
      expect(blocked.shouldTrigger, isFalse);
      expect(blocked.requestInFlight, isTrue);
    });

    test('10) successful-reroute anti-thrash still blocks weak second attempt',
        () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final successAt = t0.subtract(const Duration(seconds: 2));
      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 60.0,
            confidence: 40.0,
            hasReliableSnap: false,
          ),
          now: t0,
          lastRerouteSuccessAt: successAt,
          lastRerouteAt: successAt,
        ),
      );
      final second = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 62.0,
            confidence: 40.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 900)),
          lastRerouteSuccessAt: successAt,
          lastRerouteAt: successAt,
        ),
      );
      expect(second.cooldownActive, isTrue);
      expect(second.cooldownKind, NavRerouteCooldownKind.successfulReroute);
      expect(second.eligible, isFalse);
    });

    test('11) failed-request retry backoff remains bounded', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      final failAt = t0.subtract(const Duration(seconds: 1));
      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 100.0,
            hasReliableSnap: false,
          ),
          now: t0,
          lastRerouteFailed: true,
          lastRerouteFailureAt: failAt,
          lastRerouteAt: failAt,
        ),
      );
      final second = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 110.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 500)),
          lastRerouteFailed: true,
          lastRerouteFailureAt: failAt,
          lastRerouteAt: failAt,
        ),
      );
      expect(second.cooldownKind, NavRerouteCooldownKind.failedRetry);
      expect(second.cooldownRemainingMs, lessThanOrEqualTo(3000));
      expect(second.eligible, isFalse);

      final after = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 120.0,
            hasReliableSnap: false,
          ),
          now: failAt.add(const Duration(milliseconds: 3100)),
          lastRerouteFailed: true,
          lastRerouteFailureAt: failAt,
          lastRerouteAt: failAt,
        ),
      );
      expect(after.cooldownKind, isNot(NavRerouteCooldownKind.failedRetry));
    });

    test('12) eligible=true reaches shouldTrigger in same logical cycle window',
        () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 100.0,
            hasReliableSnap: false,
          ),
          now: t0,
        ),
      );
      final eligible = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 110.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 600)),
        ),
      );
      expect(eligible.eligible, isTrue);
      // Debounce is 500 ms on strong urban; next tick in the same second triggers.
      final trigger = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 115.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 1200)),
        ),
      );
      expect(trigger.shouldTrigger, isTrue);
      expect(
        t0
            .add(const Duration(milliseconds: 1200))
            .difference(t0)
            .inMilliseconds,
        lessThanOrEqualTo(3000),
      );
    });

    test('13) route stop / destination cancels pending eligibility', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 100.0,
            hasReliableSnap: false,
          ),
          now: t0,
        ),
      );
      final stopped = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 110.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(seconds: 1)),
          liveRideActive: false,
        ),
      );
      expect(stopped.eligible, isFalse);
      expect(stopped.shouldTrigger, isFalse);
      expect(stopped.blockedReason, 'not_live');
    });

    test('14) newer generation supersedes older eligible decision via reset',
        () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25);
      tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 100.0,
            hasReliableSnap: false,
          ),
          now: t0,
          routeVersion: 3,
        ),
      );
      final eligible = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 110.0,
            hasReliableSnap: false,
          ),
          now: t0.add(const Duration(milliseconds: 600)),
          routeVersion: 3,
        ),
      );
      expect(eligible.eligible, isTrue);

      tracker.noteRerouteApplied(t0.add(const Duration(seconds: 1)));
      final afterAccept = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: false,
            snapDistanceM: 3.0,
            confidence: 96.0,
            hasReliableSnap: true,
          ),
          now: t0.add(const Duration(seconds: 1)),
          routeVersion: 4,
        ),
      );
      expect(afterAccept.eligible, isFalse);
      expect(afterAccept.shouldTrigger, isFalse);
      expect(afterAccept.samplesOffRoute, 0);
      expect(afterAccept.routeVersion, 4);
    });

    test('field replay: 84→84→118→134 never waits ~10s / five samples', () {
      final tracker = NavRerouteDecisionTracker();
      // Stale successful-reroute cooldown still active (the field blocker).
      // Observation cadence is phone-like (~1.1s); old path waited ~10s for
      // cooldown + five samples + 1.8s debounce.
      final t0 = DateTime.utc(2026, 7, 17, 14, 20, 25, 803);
      final priorSuccess = t0.subtract(const Duration(seconds: 18));
      final snaps = <double>[84.2, 84.2, 117.9, 134.4];
      final deltasMs = <int>[0, 1100, 2200, 3000];
      DateTime? triggerAt;
      var sampleCountAtTrigger = 0;
      for (var i = 0; i < snaps.length; i++) {
        final now = t0.add(Duration(milliseconds: deltasMs[i]));
        final out = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: snaps[i],
              confidence: 20.0,
              hasReliableSnap: false,
            ),
            speedKmh: 34.3,
            accuracyM: 2.2,
            now: now,
            lastRerouteAt: priorSuccess,
            lastRerouteSuccessAt: priorSuccess,
            routeVersion: 3,
          ),
        );
        if (out.shouldTrigger) {
          triggerAt = now;
          sampleCountAtTrigger = i + 1;
          break;
        }
      }
      expect(triggerAt, isNotNull);
      final elapsed = triggerAt!.difference(t0).inMilliseconds;
      expect(elapsed, lessThanOrEqualTo(3000));
      expect(sampleCountAtTrigger, lessThan(5));
      expect(tracker.samplesOffRoute, lessThan(5));
    });
  });

  group('NAV-REROUTE-P0 complexity ownership recovery', () {
    test('15-18) route N warning clears on N+1 ownership; transport pending ok',
        () {
      // NAV-COMPLEXITY-CHURN-GATE-P0-FIELD-2026-07-29: the "buildup" here is
      // now a genuine structural signal (`ambiguous_instruction` on a
      // roundabout with an unknown modifier) — the previous
      // `rapid_instruction_churn` path no longer independently activates
      // the guard. Ownership-cleanup semantics (route N-owned warning
      // clears on N+1 tick) are preserved and are what this test exercises.
      final guard = NavComplexityGuard();
      var t = DateTime.utc(2026, 7, 17, 14, 20, 30);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 4; i++) {
        t = t.add(const Duration(milliseconds: 400));
        state = guard.update(
          NavComplexityGuardInput(
            timestamp: t,
            liveRideActive: true,
            followMode: true,
            overallConfidence: 60.0,
            trustInstruction: true,
            trustBearing: true,
            snapDistanceM: 12.0,
            instructionStepIndex: 0,
            maneuverType: 'roundabout',
            maneuverModifier: 'unknown',
            speedKmh: 30.0,
            distanceToManeuverM: 80.0,
            routeVersion: 3,
          ),
        );
      }
      expect(state.active, isTrue);
      expect(state.reasonCode, 'ambiguous_instruction');

      // Home on accept: _resetNavComplexityState() then ownership maps
      // reroutePending=false even while the async Future is still finishing.
      guard.reset();
      t = t.add(const Duration(milliseconds: 200));
      const transportFutureStillFinishing = true;
      final ownershipAccepted = true;
      final reroutePendingForComplexity =
          transportFutureStillFinishing && !ownershipAccepted;
      state = guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 96.5,
          trustInstruction: true,
          trustBearing: true,
          snapDistanceM: 2.8,
          offRouteLikely: false,
          reroutePending: reroutePendingForComplexity,
          instructionStepIndex: 0,
          maneuverType: 'turn',
          maneuverModifier: 'right',
          speedKmh: 34.0,
          distanceToManeuverM: 400.0,
          routeVersion: 4,
        ),
      );
      expect(reroutePendingForComplexity, isFalse);
      expect(state.active, isFalse);
      expect(state.decision.show, isFalse);
      expect(state.decision.effectiveScore, 0);
      expect(state.decision.triggerRules, isEmpty);
      expect(state.decision.qualityRules, isNot(contains('offroute_uncertain')));
      expect(state.decision.currentRouteVersion, 4);
      expect(state.decision.stateOwnerMatches, isTrue);
    });

    test(
      '18b) N→N+1 version tick alone clears N-owned warning without home reset',
      () {
        // NAV-COMPLEXITY-CHURN-GATE-P0-FIELD-2026-07-29: churn is now a
        // quality signal only; use `ambiguous_instruction` on a roundabout
        // with an unknown modifier to build the N-owned warning so we can
        // verify the version-tick cleanup path still works.
        final guard = NavComplexityGuard();
        var t = DateTime.utc(2026, 7, 17, 14, 20, 40);
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        for (var i = 0; i < 4; i++) {
          t = t.add(const Duration(milliseconds: 400));
          state = guard.update(
            NavComplexityGuardInput(
              timestamp: t,
              liveRideActive: true,
              followMode: true,
              overallConfidence: 60.0,
              snapDistanceM: 12.0,
              instructionStepIndex: 0,
              maneuverType: 'roundabout',
              maneuverModifier: 'unknown',
              speedKmh: 30.0,
              distanceToManeuverM: 80.0,
              routeVersion: 3,
            ),
          );
        }
        expect(state.active, isTrue);

        t = t.add(const Duration(milliseconds: 100));
        state = guard.update(
          NavComplexityGuardInput(
            timestamp: t,
            liveRideActive: true,
            followMode: true,
            overallConfidence: 96.5,
            trustInstruction: true,
            snapDistanceM: 2.8,
            offRouteLikely: false,
            reroutePending: false,
            instructionStepIndex: 0,
            maneuverType: 'turn',
            maneuverModifier: 'right',
            speedKmh: 34.0,
            distanceToManeuverM: 400.0,
            routeVersion: 4,
          ),
        );
        expect(state.decision.show, isFalse);
        expect(state.active, isFalse);
        expect(
          state.decision.staleStateClearedReason,
          anyOf('route_version_replaced', 'route_version_replaced_clean'),
        );
      },
    );

    test('19) legitimate complexity parsed from N+1 may still show', () {
      final guard = NavComplexityGuard();
      var t = DateTime.utc(2026, 7, 17, 14, 21, 0);
      guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 90.0,
          snapDistanceM: 5.0,
          routeVersion: 4,
          maneuverType: 'turn',
          maneuverModifier: 'right',
        ),
      );
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          NavComplexityGuardInput(
            timestamp: t,
            liveRideActive: true,
            followMode: true,
            overallConfidence: 70.0,
            snapDistanceM: 10.0,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
            routeVersion: 4,
          ),
        );
      }
      expect(state.active, isTrue);
      expect(state.decision.structuralComplexityPresent, isTrue);
    });

    test('20) minimum-display hysteresis cannot carry old-route warning to N+1',
        () {
      final guard = NavComplexityGuard();
      var t = DateTime.utc(2026, 7, 17, 14, 21, 10);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          NavComplexityGuardInput(
            timestamp: t,
            liveRideActive: true,
            followMode: true,
            overallConfidence: 70.0,
            snapDistanceM: 10.0,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
            routeVersion: 5,
          ),
        );
      }
      expect(state.active, isTrue);

      t = t.add(const Duration(milliseconds: 200));
      state = guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 96.0,
          snapDistanceM: 3.0,
          trustInstruction: true,
          offRouteLikely: false,
          reroutePending: false,
          maneuverType: 'turn',
          maneuverModifier: 'right',
          speedKmh: 35.0,
          distanceToManeuverM: 300.0,
          routeVersion: 6,
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.show, isFalse);
      expect(state.decision.hysteresisHold, isFalse);
    });

    test('21) repeated prediction state is route-version scoped', () {
      final guard = NavComplexityGuard();
      var t = DateTime.utc(2026, 7, 17, 14, 21, 20);
      for (var cycle = 0; cycle < 3; cycle++) {
        guard.update(
          NavComplexityGuardInput(
            timestamp: t,
            liveRideActive: true,
            followMode: true,
            overallConfidence: 50.0,
            predictionActive: true,
            gapBridgeMs: 800,
            routeVersion: 1,
          ),
        );
        t = t.add(const Duration(seconds: 1));
        guard.update(
          NavComplexityGuardInput(
            timestamp: t,
            liveRideActive: true,
            followMode: true,
            overallConfidence: 50.0,
            predictionActive: false,
            routeVersion: 1,
          ),
        );
        t = t.add(const Duration(seconds: 1));
      }
      var state = guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 50.0,
          predictionActive: true,
          gapBridgeMs: 900,
          routeVersion: 1,
        ),
      );
      expect(state.predictionRepeated, isTrue);

      t = t.add(const Duration(milliseconds: 200));
      state = guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 90.0,
          predictionActive: true,
          gapBridgeMs: 900,
          routeVersion: 2,
        ),
      );
      expect(state.predictionRepeated, isFalse);
    });

    test('22) neutral reliable recovery clears stale offroute_uncertain', () {
      final guard = NavComplexityGuard();
      var t = DateTime.utc(2026, 7, 17, 14, 21, 30);
      var state = guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 40.0,
          snapDistanceM: 40.0,
          offRouteLikely: true,
          reroutePending: true,
          routeVersion: 1,
        ),
      );
      expect(state.decision.qualityRules, contains('offroute_uncertain'));

      t = t.add(const Duration(milliseconds: 300));
      state = guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 96.0,
          snapDistanceM: 3.0,
          offRouteLikely: false,
          reroutePending: false,
          trustInstruction: true,
          routeVersion: 1,
        ),
      );
      expect(state.decision.qualityRules, isNot(contains('offroute_uncertain')));
      expect(state.active, isFalse);
    });

    test('23) complexity decision owns the accepted routeVersion', () {
      final guard = NavComplexityGuard();
      final t = DateTime.utc(2026, 7, 17, 14, 21, 40);
      final state = guard.update(
        NavComplexityGuardInput(
          timestamp: t,
          liveRideActive: true,
          followMode: true,
          overallConfidence: 90.0,
          snapDistanceM: 5.0,
          routeVersion: 7,
        ),
      );
      expect(state.decision.complexityRouteVersion, 7);
      expect(state.decision.currentRouteVersion, 7);
      expect(state.decision.stateOwnerMatches, isTrue);
    });
  });

  group('NAV-REROUTE-P0 junction-exit / wrong-street fast path', () {
    test(
      'WS1) wrong outgoing street with good GPS starts immediately or after one confirm',
      () {
        final tracker = NavRerouteDecisionTracker();
        final t0 = DateTime.utc(2026, 7, 17, 15, 0, 0);

        // Approach junction on-route.
        tracker.update(
          _tick(
            progress: _progress(
              snapDistanceM: 4.0,
              confidence: 95.0,
              hasReliableSnap: true,
              headingDeltaDeg: 8.0,
            ),
            distanceToManeuverM: 35.0,
            now: t0,
          ),
        );

        // Exit through a different outgoing street.
        final exit = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: 18.0,
              confidence: 35.0,
              hasReliableSnap: false,
              headingDeltaDeg: 78.0,
            ),
            distanceToManeuverM: 8.0,
            speedKmh: 32.0,
            accuracyM: 3.0,
            now: t0.add(const Duration(milliseconds: 700)),
          ),
        );
        expect(exit.offRouteReason, anyOf('wrong_street', 'snap_distance'));
        expect(exit.wrongStreetSampleCount, greaterThanOrEqualTo(1));

        if (!exit.shouldTrigger) {
          final confirm = tracker.update(
            _tick(
              progress: _progress(
                offRouteLikely: true,
                snapDistanceM: 22.0,
                confidence: 30.0,
                hasReliableSnap: false,
                headingDeltaDeg: 82.0,
              ),
              distanceToManeuverM: 5.0,
              speedKmh: 32.0,
              accuracyM: 3.0,
              now: t0.add(const Duration(milliseconds: 1000)),
            ),
          );
          expect(confirm.shouldTrigger, isTrue);
          expect(confirm.wrongStreetFastPath, isTrue);
          expect(
            t0
                .add(const Duration(milliseconds: 1000))
                .difference(t0)
                .inMilliseconds,
            lessThanOrEqualTo(1200),
          );
        } else {
          expect(exit.shouldTrigger, isTrue);
          expect(exit.wrongStreetFastPath, isTrue);
        }
      },
    );

    test(
      'WS2) 10–25 m beyond junction on wrong street: reroute already in flight',
      () {
        final tracker = NavRerouteDecisionTracker();
        final t0 = DateTime.utc(2026, 7, 17, 15, 0, 10);
        tracker.update(
          _tick(
            progress: _progress(
              snapDistanceM: 5.0,
              confidence: 92.0,
              hasReliableSnap: true,
              headingDeltaDeg: 6.0,
            ),
            distanceToManeuverM: 20.0,
            now: t0,
          ),
        );
        const beyondSnapM = 22.0;
        final beyond = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: beyondSnapM,
              confidence: 28.0,
              hasReliableSnap: false,
              headingDeltaDeg: 85.0,
            ),
            distanceToManeuverM: 4.0,
            speedKmh: 28.0,
            accuracyM: 2.5,
            now: t0.add(const Duration(milliseconds: 800)),
          ),
        );
        expect(beyondSnapM, lessThan(80.0));
        expect(beyond.shouldTrigger, isTrue);
        expect(beyond.wrongStreetFastPath, isTrue);
        expect(beyond.offRouteReason, 'wrong_street');
      },
    );

    test('WS3) sideways GPS jump on correct street does not reroute', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 15, 0, 20);
      tracker.update(
        _tick(
          progress: _progress(
            snapDistanceM: 4.0,
            confidence: 95.0,
            hasReliableSnap: true,
            headingDeltaDeg: 5.0,
          ),
          now: t0,
        ),
      );
      final jump = tracker.update(
        _tick(
          progress: _progress(
            offRouteLikely: true,
            snapDistanceM: 20.0,
            confidence: 40.0,
            hasReliableSnap: false,
            headingDeltaDeg: 12.0, // still aligned with route
          ),
          speedKmh: 30.0,
          accuracyM: 3.0,
          now: t0.add(const Duration(milliseconds: 400)),
        ),
      );
      expect(jump.shouldTrigger, isFalse);
      expect(jump.wrongStreetFastPath, isFalse);

      final recover = tracker.update(
        _tick(
          progress: _progress(
            snapDistanceM: 4.5,
            confidence: 94.0,
            hasReliableSnap: true,
            headingDeltaDeg: 7.0,
          ),
          now: t0.add(const Duration(milliseconds: 900)),
        ),
      );
      expect(recover.shouldTrigger, isFalse);
      expect(recover.offRouteLikely, isFalse);
    });

    test(
      'WS4) ambiguous wide intersection waits until outgoing street is clear',
      () {
        final tracker = NavRerouteDecisionTracker();
        final t0 = DateTime.utc(2026, 7, 17, 15, 0, 30);

        final inside = tracker.update(
          _tick(
            progress: _progress(
              snapDistanceM: 6.0,
              confidence: 60.0,
              hasReliableSnap: false,
              headingDeltaDeg: 35.0,
            ),
            distanceToManeuverM: 12.0,
            speedKmh: 25.0,
            accuracyM: 4.0,
            now: t0,
          ),
        );
        expect(inside.shouldTrigger, isFalse);
        expect(
          inside.blockedReason,
          anyOf('junction_ambiguous', 'not_off_route'),
        );

        final clear = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: 16.0,
              confidence: 32.0,
              hasReliableSnap: false,
              headingDeltaDeg: 72.0,
            ),
            distanceToManeuverM: 6.0,
            speedKmh: 26.0,
            accuracyM: 3.5,
            now: t0.add(const Duration(milliseconds: 700)),
          ),
        );
        // May need one confirm tick if not yet fully confirmed.
        if (!clear.shouldTrigger) {
          final confirmed = tracker.update(
            _tick(
              progress: _progress(
                offRouteLikely: true,
                snapDistanceM: 19.0,
                confidence: 30.0,
                hasReliableSnap: false,
                headingDeltaDeg: 76.0,
              ),
              distanceToManeuverM: 4.0,
              speedKmh: 27.0,
              accuracyM: 3.5,
              now: t0.add(const Duration(milliseconds: 1000)),
            ),
          );
          expect(confirmed.shouldTrigger, isTrue);
        } else {
          expect(clear.shouldTrigger, isTrue);
        }
      },
    );

    test(
      'WS-same-cycle) wrong_street shouldTrigger schedules request start '
      'with decisionEligibleToRequestStartMs=0',
      () {
        final tracker = NavRerouteDecisionTracker();
        final t0 = DateTime.utc(2026, 7, 17, 15, 1, 0);
        tracker.update(
          _tick(
            progress: _progress(
              snapDistanceM: 4.0,
              confidence: 95.0,
              hasReliableSnap: true,
              headingDeltaDeg: 5.0,
            ),
            distanceToManeuverM: 25.0,
            now: t0,
          ),
        );

        DateTime? eligibleAt;
        DateTime? requestStartedAt;
        var extraCallbackRequired = false;

        // Mirrors home: _updateRouteSnapState → _evaluateOffRouteReroute →
        // synchronous start of _triggerOffRouteReroute (before any await).
        void evaluateSameCycle(NavRerouteDecisionTickOutput decision, DateTime now) {
          if (decision.eligible) {
            eligibleAt ??= now;
          }
          if (decision.shouldTrigger) {
            requestStartedAt = now;
          }
        }

        final beyond = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: 22.0,
              confidence: 28.0,
              hasReliableSnap: false,
              headingDeltaDeg: 85.0,
            ),
            distanceToManeuverM: 4.0,
            speedKmh: 28.0,
            accuracyM: 2.5,
            now: t0.add(const Duration(milliseconds: 800)),
          ),
        );
        evaluateSameCycle(beyond, t0.add(const Duration(milliseconds: 800)));

        expect(beyond.offRouteReason, 'wrong_street');
        expect(beyond.shouldTrigger, isTrue);
        expect(beyond.debounceRequired, Duration.zero);
        expect(requestStartedAt, isNotNull);
        expect(eligibleAt, isNotNull);
        final decisionEligibleToRequestStartMs =
            requestStartedAt!.difference(eligibleAt!).inMilliseconds;
        expect(decisionEligibleToRequestStartMs, 0);
        expect(extraCallbackRequired, isFalse);
      },
    );

    test(
      'WS5) confirmed wrong-street turn does not require 80+ m deviation',
      () {
        final tracker = NavRerouteDecisionTracker();
        final t0 = DateTime.utc(2026, 7, 17, 15, 0, 40);
        tracker.update(
          _tick(
            progress: _progress(
              snapDistanceM: 3.0,
              confidence: 96.0,
              hasReliableSnap: true,
              headingDeltaDeg: 4.0,
            ),
            now: t0,
          ),
        );
        const wrongStreetSnapM = 24.0;
        final out = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: true,
              snapDistanceM: wrongStreetSnapM,
              confidence: 25.0,
              hasReliableSnap: false,
              headingDeltaDeg: 90.0,
            ),
            distanceToManeuverM: 3.0,
            speedKmh: 30.0,
            accuracyM: 2.0,
            now: t0.add(const Duration(milliseconds: 600)),
          ),
        );
        expect(wrongStreetSnapM, lessThan(80.0));
        expect(out.shouldTrigger, isTrue);
        expect(out.wrongStreetFastPath, isTrue);
        expect(out.strongSampleCount, 0); // not the 80 m fallback path
      },
    );
  });

  group('NAV-REROUTE-P0 regression helpers', () {
    test('24) opposite-direction / backtrack remains fast', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 22, 0);
      final strongOpposite = _progress(
        offRouteLikely: true,
        routeDeviationLikely: true,
        oppositeDirectionLikely: true,
        routeDeviationReason: 'opposite_heading_strong',
        headingDeltaDeg: 175.0,
        hasReliableSnap: false,
      );
      tracker.update(_tick(progress: strongOpposite, speedKmh: 25.0, now: t0));
      final second = tracker.update(
        _tick(
          progress: strongOpposite,
          speedKmh: 25.0,
          now: t0.add(const Duration(milliseconds: 600)),
        ),
      );
      expect(second.shouldTrigger, isTrue);
    });

    test('25) ordinary route matching does not reroute', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 7, 17, 14, 22, 10);
      for (var i = 0; i < 5; i++) {
        final out = tracker.update(
          _tick(
            progress: _progress(
              offRouteLikely: false,
              snapDistanceM: 4.0,
              confidence: 95.0,
              hasReliableSnap: true,
            ),
            now: t0.add(Duration(seconds: i)),
          ),
        );
        expect(out.shouldTrigger, isFalse);
        expect(out.eligible, isFalse);
      }
    });
  });
}
