import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_guard.dart';

NavComplexityGuardInput _input({
  DateTime? timestamp,
  bool liveRideActive = true,
  bool followMode = true,
  double? overallConfidence = 80.0,
  bool trustInstruction = true,
  bool trustBearing = true,
  double? snapDistanceM = 8.0,
  bool offRouteLikely = false,
  bool reroutePending = false,
  double? headingDeltaDeg,
  bool predictionActive = false,
  int gapBridgeMs = 0,
  String? maneuverModifier = 'right',
  int? instructionStepIndex = 0,
  double? speedKmh = 40.0,
  double? distanceToManeuverM = 500.0,
  String? maneuverType = 'turn',
  int routeVersion = 1,
}) {
  return NavComplexityGuardInput(
    timestamp: timestamp ?? DateTime(2026, 1, 1, 12),
    liveRideActive: liveRideActive,
    followMode: followMode,
    overallConfidence: overallConfidence,
    trustInstruction: trustInstruction,
    trustBearing: trustBearing,
    snapDistanceM: snapDistanceM,
    offRouteLikely: offRouteLikely,
    reroutePending: reroutePending,
    headingDeltaDeg: headingDeltaDeg,
    predictionActive: predictionActive,
    gapBridgeMs: gapBridgeMs,
    maneuverModifier: maneuverModifier,
    instructionStepIndex: instructionStepIndex,
    speedKmh: speedKmh,
    distanceToManeuverM: distanceToManeuverM,
    maneuverType: maneuverType,
    routeVersion: routeVersion,
  );
}

NavComplexityGuardState _runUntil(
  NavComplexityGuard guard,
  NavComplexityGuardInput Function(DateTime t) buildInput, {
  required Duration total,
  Duration step = const Duration(milliseconds: 500),
}) {
  var t = DateTime(2026, 1, 1, 12);
  NavComplexityGuardState state = NavComplexityGuardState.inactive;
  for (var elapsed = Duration.zero; elapsed <= total; elapsed += step) {
    state = guard.update(buildInput(t));
    t = t.add(step);
  }
  return state;
}

void main() {
  group('NAV-R14A NavComplexityGuard', () {
    test('no popup during high-confidence normal route', () {
      final guard = NavComplexityGuard();
      final state = _runUntil(
        guard,
        (t) =>
            _input(timestamp: t, overallConfidence: 82.0, snapDistanceM: 6.0),
        total: const Duration(seconds: 5),
      );
      expect(state.active, isFalse);
      expect(state.complexCandidate, isFalse);
      expect(state.decision.triggerRules, isEmpty);
    });

    test('quality-only low confidence + high snap does not warn', () {
      final guard = NavComplexityGuard();
      final state = _runUntil(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 48.0,
          trustInstruction: false,
          snapDistanceM: 38.0,
          maneuverType: 'turn',
          maneuverModifier: 'right',
        ),
        total: const Duration(seconds: 4),
      );
      expect(state.active, isFalse);
      expect(state.complexCandidate, isFalse);
      expect(state.decision.qualityRules, contains('low_confidence'));
      expect(state.decision.qualityRules, contains('high_snap_distance'));
      expect(state.decision.triggerRules, isEmpty);
    });

    test('repeated prediction alone never shows Complex road situation', () {
      final guard = NavComplexityGuard();
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      var t = DateTime(2026, 1, 1, 12);
      for (var cycle = 0; cycle < 3; cycle++) {
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 50.0,
            trustBearing: false,
            snapDistanceM: 30.0,
            predictionActive: true,
            gapBridgeMs: 800,
          ),
        );
        t = t.add(const Duration(seconds: 1));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 50.0,
            trustBearing: false,
            snapDistanceM: 30.0,
            predictionActive: false,
          ),
        );
        t = t.add(const Duration(seconds: 1));
      }
      for (var i = 0; i <= 6; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 50.0,
            trustBearing: false,
            snapDistanceM: 30.0,
            predictionActive: true,
            gapBridgeMs: 900,
          ),
        );
      }
      expect(state.active, isFalse);
      expect(state.predictionRepeated, isTrue);
      expect(state.decision.qualityRules, contains('repeated_prediction'));
      expect(
        state.decision.triggerRules,
        isNot(contains('repeated_prediction')),
      );
      expect(state.decision.predictionSupportingOnly, isTrue);
      expect(state.decision.structuralComplexityPresent, isFalse);
      expect(state.decision.effectiveScore, 0);
    });

    test('cooldown prevents spam after recovery', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;

      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 42.0,
            trustInstruction: false,
            snapDistanceM: 35.0,
            headingDeltaDeg: 85.0,
            speedKmh: 20.0,
          ),
        );
      }
      expect(state.active, isTrue);

      for (var i = 0; i < 12; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 85.0,
            trustInstruction: true,
            trustBearing: true,
            snapDistanceM: 6.0,
          ),
        );
      }
      expect(state.active, isFalse);

      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 40.0,
            trustInstruction: false,
            snapDistanceM: 40.0,
            headingDeltaDeg: 90.0,
            speedKmh: 25.0,
          ),
        );
      }
      expect(state.active, isFalse);
      expect(state.complexCandidate, isTrue);
    });

    test('recovery hides after stable confidence returns', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;

      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 44.0,
            trustBearing: false,
            snapDistanceM: 32.0,
            headingDeltaDeg: 75.0,
            speedKmh: 30.0,
          ),
        );
      }
      expect(state.active, isTrue);
      expect(state.reasonCode, 'heading_route_conflict');

      for (var i = 0; i < 12; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 88.0,
            trustInstruction: true,
            trustBearing: true,
            snapDistanceM: 5.0,
            offRouteLikely: false,
          ),
        );
      }
      expect(state.active, isFalse);
    });

    test('diagnostics buckets match NAV-AI-1 spec', () {
      expect(NavComplexityGuard.confidenceBucket(48.0), '40-60');
      expect(NavComplexityGuard.confidenceBucket(12.0), '0-20');
      expect(NavComplexityGuard.snapDistanceBucket(4.0), '0-5');
      expect(NavComplexityGuard.snapDistanceBucket(22.0), '15-30');
      expect(NavComplexityGuard.snapDistanceBucket(55.0), '30+');
    });
  });

  group('NAV-COMPLEXITY-FALSE-POSITIVE-AUDIT-1', () {
    test('simple straight/curved road => no warning', () {
      final guard = NavComplexityGuard();
      final state = _runUntil(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 78.0,
          snapDistanceM: 9.0,
          maneuverType: 'continue',
          maneuverModifier: 'straight',
          speedKmh: 55.0,
          distanceToManeuverM: 800.0,
        ),
        total: const Duration(seconds: 4),
      );
      expect(state.active, isFalse);
      expect(state.decision.triggerRules, isEmpty);
    });

    test('normal T-junction step advance => no warning', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var step = 0; step <= 1; step++) {
        for (var i = 0; i < 4; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 72.0,
              snapDistanceM: 11.0,
              instructionStepIndex: step,
              maneuverType: 'turn',
              maneuverModifier: 'right',
              speedKmh: 30.0,
              distanceToManeuverM: 120.0,
            ),
          );
        }
      }
      expect(state.active, isFalse);
      expect(
        state.decision.triggerRules,
        isNot(contains('ambiguous_instruction')),
      );
      expect(state.decision.maneuverCount, lessThan(2));
    });

    test('ordinary route continuation => no warning', () {
      final guard = NavComplexityGuard();
      final state = _runUntil(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 76.0,
          snapDistanceM: 7.0,
          maneuverType: 'continue',
          maneuverModifier: 'straight',
          instructionStepIndex: 2,
          speedKmh: 45.0,
          distanceToManeuverM: 650.0,
        ),
        total: const Duration(seconds: 3),
      );
      expect(state.active, isFalse);
    });

    test('true complex multi-branch junction => warning', () {
      final guard = NavComplexityGuard();
      final state = _runUntil(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 70.0,
          snapDistanceM: 10.0,
          maneuverType: 'fork',
          maneuverModifier: '',
          speedKmh: 12.0,
          distanceToManeuverM: 80.0,
        ),
        total: const Duration(seconds: 3),
      );
      expect(state.complexCandidate, isTrue);
      expect(state.active, isTrue);
      expect(state.decision.triggerRules, contains('ambiguous_instruction'));
      expect(state.decision.triggerRules, contains('dense_maneuver_area'));
      expect(state.decision.branchCount, 2);
    });

    test('low GPS confidence alone => not Complex road situation', () {
      final guard = NavComplexityGuard();
      final state = _runUntil(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 42.0,
          trustInstruction: false,
          trustBearing: false,
          snapDistanceM: 12.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
        ),
        total: const Duration(seconds: 4),
      );
      expect(state.active, isFalse);
      expect(state.decision.qualityRules, contains('low_confidence'));
      expect(state.decision.triggerRules, isEmpty);
    });

    test('off-route uncertainty alone => not Complex road situation', () {
      final guard = NavComplexityGuard();
      final state = _runUntil(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 68.0,
          snapDistanceM: 18.0,
          offRouteLikely: true,
          reroutePending: true,
          maneuverType: 'turn',
          maneuverModifier: 'right',
        ),
        total: const Duration(seconds: 4),
      );
      expect(state.active, isFalse);
      expect(state.decision.qualityRules, contains('offroute_uncertain'));
      expect(state.decision.triggerRules, isEmpty);
    });

    test('rapid instruction churn at complex area => warning', () {
      // NAV-COMPLEXITY-CHURN-GATE-P0-FIELD-2026-07-29: churn is a QUALITY
      // signal so the warning here is now owned by `ambiguous_instruction`
      // (roundabout with an empty modifier). Churn appears in `qualityRules`
      // rather than `triggerRules` — it supports the structural warning, it
      // does not create one.
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var step = 0; step <= 2; step++) {
        t = t.add(const Duration(seconds: 2));
        for (var i = 0; i < 2; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 74.0,
              snapDistanceM: 9.0,
              instructionStepIndex: step,
              maneuverType: 'roundabout',
              maneuverModifier: '',
              speedKmh: 18.0,
              distanceToManeuverM: 60.0,
            ),
          );
        }
      }
      expect(state.active, isTrue);
      expect(state.decision.triggerRules, contains('ambiguous_instruction'));
      expect(state.decision.qualityRules, contains('rapid_instruction_churn'));
      expect(
        state.decision.triggerRules,
        isNot(contains('rapid_instruction_churn')),
      );
    });

    test('decision snapshot exposes audit fields', () {
      final guard = NavComplexityGuard();
      // NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1: heading conflict is only
      // structural after the sustained-sample gate is reached AND supporting
      // quality is present on the same tick. Iterate to reach the gate.
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 4; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 48.0,
            snapDistanceM: 40.0,
            headingDeltaDeg: 80.0,
            speedKmh: 25.0,
          ),
        );
      }
      expect(state.decision.score, 1);
      expect(state.decision.rawScore, 1);
      expect(state.decision.effectiveScore, 1);
      expect(state.decision.threshold, 1);
      expect(state.decision.routeConfidence, 48.0);
      expect(state.decision.mapMatchConfidence, isNotNull);
      expect(state.decision.bearingAmbiguity, 80.0);
      expect(state.decision.structuralComplexityPresent, isTrue);
    });
  });

  group('NAV-R14-COMPLEXITY-GATE-2', () {
    test(
      '1) high-confidence ordinary nav with predictionRepeated stays hidden',
      () {
        final guard = NavComplexityGuard();
        // Establish repeated prediction via continuous bridge.
        var t = DateTime(2026, 1, 1, 12);
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        for (var i = 0; i < 12; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 96.5,
              trustBearing: true,
              trustInstruction: true,
              snapDistanceM: 3.0,
              offRouteLikely: false,
              reroutePending: false,
              predictionActive: true,
              gapBridgeMs: 400,
              instructionStepIndex: 0,
              maneuverType: 'turn',
              maneuverModifier: 'right',
              speedKmh: 40.0,
              distanceToManeuverM: 400.0,
            ),
          );
        }
        expect(state.predictionRepeated, isTrue);
        expect(state.active, isFalse);
        expect(state.decision.visible, isFalse);
        expect(state.decision.effectiveScore, 0);
        expect(state.decision.branchCount, 0);
        expect(state.decision.maneuverCount, lessThan(2));
        expect(state.decision.structuralComplexityPresent, isFalse);
      },
    );

    test('2) repeated prediction alone across many evals stays hidden', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 30; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 90.0,
            snapDistanceM: 4.0,
            predictionActive: true,
            gapBridgeMs: 500,
          ),
        );
      }
      expect(state.predictionRepeated, isTrue);
      expect(state.active, isFalse);
      expect(state.decision.predictionSupportingOnly, isTrue);
      expect(state.complexCandidate, isFalse);
    });

    test('3) real complexity appears only after positive streak', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      var state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 70.0,
          snapDistanceM: 10.0,
          maneuverType: 'fork',
          maneuverModifier: '',
          speedKmh: 12.0,
          distanceToManeuverM: 80.0,
        ),
      );
      expect(state.complexCandidate, isTrue);
      expect(state.active, isFalse);
      expect(state.decision.transition, 'pending_show');
      expect(state.decision.positiveStreak, 1);

      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 70.0,
          snapDistanceM: 10.0,
          maneuverType: 'fork',
          maneuverModifier: '',
          speedKmh: 12.0,
          distanceToManeuverM: 80.0,
        ),
      );
      expect(state.active, isTrue);
      expect(state.decision.transition, 'shown');
      expect(state.decision.positiveStreak, 2);
      expect(state.decision.visible, isTrue);
    });

    test(
      '4) score=0 reason=none clears immediately on strong reliable recovery',
      () {
        final guard = NavComplexityGuard();
        var t = DateTime(2026, 1, 1, 12);
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        for (var i = 0; i < 3; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 70.0,
              snapDistanceM: 10.0,
              maneuverType: 'fork',
              maneuverModifier: '',
              speedKmh: 12.0,
              distanceToManeuverM: 80.0,
            ),
          );
        }
        expect(state.active, isTrue);

        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 96.5,
            snapDistanceM: 3.0,
            maneuverType: 'turn',
            maneuverModifier: 'right',
            speedKmh: 40.0,
            distanceToManeuverM: 400.0,
          ),
        );
        expect(state.decision.effectiveScore, 0);
        expect(state.decision.reason, 'none');
        expect(state.active, isFalse);
        expect(state.decision.transition, 'reliable_recovery_clear');
        expect(state.decision.visible, isFalse);
        expect(state.decision.staleStateClearedReason, 'reliable_recovery');
      },
    );

    test('4b) noisy recovery still uses negative hysteresis', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 70.0,
            snapDistanceM: 10.0,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
      }
      expect(state.active, isTrue);

      // Confidence recovered but snap still mediocre — not strong recovery.
      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 72.0,
          snapDistanceM: 18.0,
          maneuverType: 'turn',
          maneuverModifier: 'right',
          speedKmh: 40.0,
          distanceToManeuverM: 400.0,
        ),
      );
      expect(state.decision.effectiveScore, 0);
      expect(state.active, isTrue);
      expect(state.decision.transition, 'pending_clear');
      expect(state.decision.hysteresisHold, isTrue);

      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 72.0,
          snapDistanceM: 18.0,
          maneuverType: 'turn',
          maneuverModifier: 'right',
          speedKmh: 40.0,
          distanceToManeuverM: 400.0,
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.transition, 'cleared');
    });

    test('5) visible warning clears immediately on arrive', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 70.0,
            snapDistanceM: 10.0,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
      }
      expect(state.active, isTrue);

      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 90.0,
          snapDistanceM: 5.0,
          maneuverType: 'arrive',
          maneuverModifier: '',
          speedKmh: 5.0,
          distanceToManeuverM: 10.0,
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.transition, 'terminal_clear');
      expect(state.decision.suppressionReason, 'arrive');
      expect(state.decision.positiveStreak, 0);
      expect(state.decision.negativeStreak, 0);
    });

    test('6) visible warning clears immediately on destination reached', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 70.0,
            snapDistanceM: 10.0,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
      }
      expect(state.active, isTrue);

      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 90.0,
          snapDistanceM: 5.0,
          maneuverType: 'destination',
          maneuverModifier: '',
          speedKmh: 3.0,
          distanceToManeuverM: 5.0,
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.transition, 'terminal_clear');
      expect(state.decision.suppressionReason, 'destination_reached');
    });

    test(
      '7) stale positive evidence does not transfer across route version',
      () {
        final guard = NavComplexityGuard();
        var t = DateTime(2026, 1, 1, 12);
        var state = guard.update(
          _input(
            timestamp: t,
            routeVersion: 1,
            overallConfidence: 70.0,
            snapDistanceM: 10.0,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
        expect(state.decision.positiveStreak, 1);
        expect(state.active, isFalse);

        // Replacement route version must drop streak / candidate evidence.
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            routeVersion: 2,
            overallConfidence: 96.0,
            snapDistanceM: 4.0,
            maneuverType: 'turn',
            maneuverModifier: 'right',
            speedKmh: 40.0,
            distanceToManeuverM: 300.0,
          ),
        );
        expect(state.active, isFalse);
        expect(state.complexCandidate, isFalse);
        expect(state.decision.positiveStreak, 0);
        expect(state.decision.effectiveScore, 0);
        expect(state.decision.transition, anyOf('terminal_clear', 'none'));
      },
    );

    test('8) prediction plus structural ambiguity can still show', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      // Warm prediction bridges first.
      for (var cycle = 0; cycle < 3; cycle++) {
        guard.update(
          _input(
            timestamp: t,
            overallConfidence: 72.0,
            snapDistanceM: 10.0,
            predictionActive: true,
            gapBridgeMs: 800,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
        t = t.add(const Duration(seconds: 1));
        guard.update(
          _input(
            timestamp: t,
            overallConfidence: 72.0,
            snapDistanceM: 10.0,
            predictionActive: false,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
        t = t.add(const Duration(seconds: 1));
      }

      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 4; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 72.0,
            snapDistanceM: 10.0,
            predictionActive: true,
            gapBridgeMs: 900,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
      }
      expect(state.predictionRepeated, isTrue);
      expect(state.active, isTrue);
      expect(state.decision.structuralComplexityPresent, isTrue);
      expect(state.decision.triggerRules, contains('ambiguous_instruction'));
      expect(state.decision.qualityRules, contains('repeated_prediction'));
      expect(state.decision.predictionSupportingOnly, isFalse);
    });

    test('9) navigation start/stop resets streak and visible state', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 3; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 70.0,
            snapDistanceM: 10.0,
            maneuverType: 'fork',
            maneuverModifier: '',
            speedKmh: 12.0,
            distanceToManeuverM: 80.0,
          ),
        );
      }
      expect(state.active, isTrue);
      expect(state.decision.positiveStreak, greaterThan(0));

      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(timestamp: t, liveRideActive: false, followMode: true),
      );
      expect(state.active, isFalse);
      expect(state.decision.suppressionReason, 'no_active_session');

      // Fresh start must not inherit prior streaks.
      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 70.0,
          snapDistanceM: 10.0,
          maneuverType: 'fork',
          maneuverModifier: '',
          speedKmh: 12.0,
          distanceToManeuverM: 80.0,
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.positiveStreak, 1);
      expect(state.decision.transition, 'pending_show');
    });

    test('startup prediction-only activity is suppressed', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 10; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 95.0,
            snapDistanceM: 3.0,
            predictionActive: true,
            gapBridgeMs: 500,
          ),
        );
      }
      expect(state.active, isFalse);
      expect(state.predictionRepeated, isTrue);
      expect(
        state.decision.transition,
        anyOf('startup_prediction_suppressed', 'none'),
      );
      expect(
        state.decision.suppressionReason,
        anyOf('startup_prediction_only', 'prediction_supporting_only'),
      );
    });
  });

  group('NAV-COMPLEXITY-HEADING-CONFLICT-GATE-P0-1', () {
    NavComplexityGuardState drive(
      NavComplexityGuard guard,
      NavComplexityGuardInput Function(DateTime t) build, {
      int samples = 6,
      Duration step = const Duration(milliseconds: 500),
      DateTime? start,
    }) {
      var t = start ?? DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < samples; i++) {
        t = t.add(step);
        state = guard.update(build(t));
      }
      return state;
    }

    test('1) simple one-lane left turn at 641m => no warning', () {
      final guard = NavComplexityGuard();
      final state = drive(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 78.0,
          trustInstruction: true,
          trustBearing: true,
          snapDistanceM: 8.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
          instructionStepIndex: 2,
          speedKmh: 40.0,
          distanceToManeuverM: 641.0,
          headingDeltaDeg: null,
        ),
        samples: 20,
      );
      expect(state.active, isFalse);
      expect(state.decision.triggerRules, isEmpty);
      expect(state.decision.structuralComplexityPresent, isFalse);
    });

    test('2) simple one-lane right turn => no warning', () {
      final guard = NavComplexityGuard();
      final state = drive(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 78.0,
          snapDistanceM: 8.0,
          maneuverType: 'turn',
          maneuverModifier: 'right',
          instructionStepIndex: 2,
          speedKmh: 40.0,
          distanceToManeuverM: 500.0,
          headingDeltaDeg: null,
        ),
        samples: 20,
      );
      expect(state.active, isFalse);
      expect(state.decision.triggerRules, isEmpty);
    });

    test('3) straight local road => no warning', () {
      final guard = NavComplexityGuard();
      final state = drive(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 82.0,
          snapDistanceM: 6.0,
          maneuverType: 'continue',
          maneuverModifier: 'straight',
          instructionStepIndex: 1,
          speedKmh: 55.0,
          distanceToManeuverM: 900.0,
          headingDeltaDeg: null,
        ),
        samples: 20,
      );
      expect(state.active, isFalse);
      expect(state.decision.triggerRules, isEmpty);
    });

    test('4) one heading spike at 75 deg => no warning', () {
      final guard = NavComplexityGuard();
      final state = guard.update(
        _input(
          timestamp: DateTime(2026, 1, 1, 12, 0, 1),
          overallConfidence: 78.0,
          snapDistanceM: 8.0,
          headingDeltaDeg: 75.0,
          speedKmh: 20.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
          distanceToManeuverM: 641.0,
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.triggerRules, isEmpty);
      expect(state.decision.structuralComplexityPresent, isFalse);
    });

    test('5) two consecutive heading spikes => no warning', () {
      final guard = NavComplexityGuard();
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      var t = DateTime(2026, 1, 1, 12);
      for (var i = 0; i < 2; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 78.0,
            snapDistanceM: 8.0,
            headingDeltaDeg: 80.0,
            speedKmh: 20.0,
            maneuverType: 'turn',
            maneuverModifier: 'left',
            distanceToManeuverM: 641.0,
          ),
        );
      }
      expect(state.active, isFalse);
      expect(state.decision.triggerRules, isEmpty);
      expect(state.decision.structuralComplexityPresent, isFalse);
    });

    test(
      '6) sustained heading conflict without supporting quality => no warning',
      () {
        final guard = NavComplexityGuard();
        final state = drive(
          guard,
          (t) => _input(
            timestamp: t,
            // Healthy trust flags, good snap, healthy overall — no supporting
            // quality signal, so a heading conflict must never activate.
            overallConfidence: 90.0,
            trustInstruction: true,
            trustBearing: true,
            snapDistanceM: 6.0,
            headingDeltaDeg: 85.0,
            speedKmh: 30.0,
            maneuverType: 'turn',
            maneuverModifier: 'left',
            distanceToManeuverM: 641.0,
          ),
          samples: 12,
        );
        expect(state.active, isFalse);
        expect(state.decision.triggerRules, isEmpty);
        expect(state.decision.structuralComplexityPresent, isFalse);
      },
    );

    test(
      '7) alternating 75/60 curvature noise resets streak => no warning',
      () {
        final guard = NavComplexityGuard();
        var t = DateTime(2026, 1, 1, 12);
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        for (var i = 0; i < 20; i++) {
          t = t.add(const Duration(milliseconds: 500));
          final delta = i.isEven ? 75.0 : 60.0;
          state = guard.update(
            _input(
              timestamp: t,
              // Even with low confidence + high snap present as corroboration,
              // an alternating pattern must never reach the sustained streak
              // because the counter resets on each below-threshold sample.
              overallConfidence: 45.0,
              trustInstruction: false,
              snapDistanceM: 32.0,
              headingDeltaDeg: delta,
              speedKmh: 25.0,
              maneuverType: 'turn',
              maneuverModifier: 'left',
              distanceToManeuverM: 641.0,
            ),
          );
        }
        expect(state.active, isFalse);
        expect(
          state.decision.triggerRules,
          isNot(contains('heading_route_conflict')),
        );
      },
    );

    test('8) heading conflict below 8 km/h => no warning', () {
      final guard = NavComplexityGuard();
      final state = drive(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 45.0,
          trustInstruction: false,
          snapDistanceM: 32.0,
          headingDeltaDeg: 90.0,
          speedKmh: 6.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
          distanceToManeuverM: 641.0,
        ),
        samples: 12,
      );
      expect(state.active, isFalse);
      expect(
        state.decision.triggerRules,
        isNot(contains('heading_route_conflict')),
      );
    });

    test(
      '9) heading conflict for >=3 samples + low confidence => warning allowed',
      () {
        final guard = NavComplexityGuard();
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        var t = DateTime(2026, 1, 1, 12);
        for (var i = 0; i < 8; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 42.0,
              trustInstruction: false,
              snapDistanceM: 10.0,
              headingDeltaDeg: 85.0,
              speedKmh: 20.0,
              maneuverType: 'turn',
              maneuverModifier: 'left',
              distanceToManeuverM: 300.0,
            ),
          );
        }
        expect(state.active, isTrue);
        expect(state.decision.triggerRules, contains('heading_route_conflict'));
        expect(state.decision.qualityRules, contains('low_confidence'));
      },
    );

    test(
      '10) heading conflict for >=3 samples + high snap distance => warning allowed',
      () {
        final guard = NavComplexityGuard();
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        var t = DateTime(2026, 1, 1, 12);
        for (var i = 0; i < 8; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 75.0,
              trustInstruction: true,
              trustBearing: true,
              snapDistanceM: 40.0,
              headingDeltaDeg: 85.0,
              speedKmh: 22.0,
              maneuverType: 'turn',
              maneuverModifier: 'left',
              distanceToManeuverM: 300.0,
            ),
          );
        }
        expect(state.active, isTrue);
        expect(state.decision.triggerRules, contains('heading_route_conflict'));
        expect(state.decision.qualityRules, contains('high_snap_distance'));
      },
    );

    test(
      '11) heading conflict for >=3 samples + off-route uncertainty => warning allowed',
      () {
        final guard = NavComplexityGuard();
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        var t = DateTime(2026, 1, 1, 12);
        for (var i = 0; i < 8; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 75.0,
              trustInstruction: true,
              trustBearing: true,
              snapDistanceM: 8.0,
              offRouteLikely: true,
              reroutePending: true,
              headingDeltaDeg: 85.0,
              speedKmh: 22.0,
              maneuverType: 'turn',
              maneuverModifier: 'left',
              distanceToManeuverM: 300.0,
            ),
          );
        }
        expect(state.active, isTrue);
        expect(state.decision.triggerRules, contains('heading_route_conflict'));
        expect(state.decision.qualityRules, contains('offroute_uncertain'));
      },
    );

    test('12) repeated_prediction alone remains insufficient', () {
      final guard = NavComplexityGuard();
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      var t = DateTime(2026, 1, 1, 12);
      for (var i = 0; i < 30; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 90.0,
            snapDistanceM: 4.0,
            headingDeltaDeg: 85.0,
            speedKmh: 20.0,
            predictionActive: true,
            gapBridgeMs: 500,
            maneuverType: 'turn',
            maneuverModifier: 'left',
          ),
        );
      }
      // repeated_prediction is not a permitted corroboration for a heading
      // conflict — must remain hidden even when both are sustained.
      expect(state.active, isFalse);
      expect(
        state.decision.triggerRules,
        isNot(contains('heading_route_conflict')),
      );
    });

    test('13) missing lane metadata remains irrelevant', () {
      final guard = NavComplexityGuard();
      final state = drive(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 82.0,
          snapDistanceM: 6.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
          instructionStepIndex: 3,
          speedKmh: 40.0,
          distanceToManeuverM: 500.0,
          // No lane fields exist on the guard input; verify the guard cannot
          // activate on a normal one-lane turn regardless of upstream lanes.
          headingDeltaDeg: null,
        ),
        samples: 20,
      );
      expect(state.active, isFalse);
      expect(state.decision.triggerRules, isEmpty);
    });

    test('14) genuine fork/merge complexity remains allowed', () {
      final guard = NavComplexityGuard();
      final state = drive(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 70.0,
          snapDistanceM: 10.0,
          maneuverType: 'fork',
          maneuverModifier: '',
          speedKmh: 12.0,
          distanceToManeuverM: 80.0,
          headingDeltaDeg: null,
        ),
        samples: 4,
      );
      expect(state.active, isTrue);
      expect(state.decision.triggerRules, contains('ambiguous_instruction'));
      expect(state.decision.triggerRules, contains('dense_maneuver_area'));
    });

    test('15) genuine ambiguous roundabout remains allowed', () {
      final guard = NavComplexityGuard();
      final state = drive(
        guard,
        (t) => _input(
          timestamp: t,
          overallConfidence: 72.0,
          snapDistanceM: 9.0,
          maneuverType: 'roundabout',
          maneuverModifier: '',
          speedKmh: 14.0,
          distanceToManeuverM: 70.0,
        ),
        samples: 4,
      );
      expect(state.active, isTrue);
      expect(state.decision.triggerRules, contains('ambiguous_instruction'));
    });

    test('16) route replacement resets the conflict streak', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      // Build a saturated conflict streak on route version 1 (no warning
      // shown because there is no supporting quality signal).
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 5; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 90.0,
            snapDistanceM: 6.0,
            headingDeltaDeg: 85.0,
            speedKmh: 25.0,
            maneuverType: 'turn',
            maneuverModifier: 'left',
            routeVersion: 1,
          ),
        );
      }
      expect(state.active, isFalse);

      // Route replacement to version 2: internal reset must drop the streak.
      // Present low-quality + one conflict spike — must NOT be sufficient
      // because the sustained gate now requires >=3 fresh samples.
      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 42.0,
          trustInstruction: false,
          snapDistanceM: 32.0,
          headingDeltaDeg: 85.0,
          speedKmh: 25.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
          routeVersion: 2,
        ),
      );
      expect(state.active, isFalse);
      expect(
        state.decision.triggerRules,
        isNot(contains('heading_route_conflict')),
      );
    });

    test('17) arrival resets the conflict streak and clears warning', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      // Reach `shown` via sustained conflict + low_confidence corroboration.
      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 42.0,
            trustInstruction: false,
            snapDistanceM: 12.0,
            headingDeltaDeg: 85.0,
            speedKmh: 22.0,
            maneuverType: 'turn',
            maneuverModifier: 'left',
            distanceToManeuverM: 300.0,
          ),
        );
      }
      expect(state.active, isTrue);

      // Arrival — must terminate the warning and drop the streak.
      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 90.0,
          snapDistanceM: 5.0,
          maneuverType: 'arrive',
          maneuverModifier: '',
          speedKmh: 4.0,
          distanceToManeuverM: 5.0,
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.transition, 'terminal_clear');

      // After arrival, a single fresh heading spike + poor quality must not
      // reactivate — the streak must have been reset.
      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 42.0,
          trustInstruction: false,
          snapDistanceM: 30.0,
          headingDeltaDeg: 85.0,
          speedKmh: 20.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
        ),
      );
      expect(state.active, isFalse);
      expect(
        state.decision.triggerRules,
        isNot(contains('heading_route_conflict')),
      );
    });

    test('18) one-frame warning remains impossible', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      // A single tick with worst-case supporting-quality corroboration and
      // a huge raw delta cannot produce shown=true on the first tick, since
      // the sustained gate demands >=3 conflict samples AND
      // requiredPositiveStreak=2 additional guard ticks.
      final state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 20.0,
          trustInstruction: false,
          trustBearing: false,
          snapDistanceM: 60.0,
          offRouteLikely: true,
          reroutePending: true,
          headingDeltaDeg: 100.0,
          speedKmh: 40.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
        ),
      );
      expect(state.active, isFalse);
      expect(state.decision.visible, isFalse);
      expect(state.decision.transition, isNot('shown'));
    });

    test('19) existing hysteresis/cooldown suppression still applies', () {
      // First reach `shown` via sustained conflict + low_confidence, then
      // recover strongly on the very next tick — reliable_recovery clears
      // immediately AND cooldown blocks re-activation on the following
      // (still-poor) samples.
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 42.0,
            trustInstruction: false,
            snapDistanceM: 12.0,
            headingDeltaDeg: 85.0,
            speedKmh: 22.0,
            maneuverType: 'turn',
            maneuverModifier: 'left',
            distanceToManeuverM: 300.0,
          ),
        );
      }
      expect(state.active, isTrue);

      // Strong reliable recovery (no structural, no offroute, good snap +
      // overall) must clear immediately.
      t = t.add(const Duration(milliseconds: 500));
      state = guard.update(
        _input(
          timestamp: t,
          overallConfidence: 96.0,
          trustInstruction: true,
          trustBearing: true,
          snapDistanceM: 4.0,
          headingDeltaDeg: 5.0,
          speedKmh: 40.0,
          maneuverType: 'turn',
          maneuverModifier: 'left',
          distanceToManeuverM: 400.0,
        ),
      );
      expect(state.active, isFalse);

      // Cooldown must prevent immediate re-activation despite renewed poor
      // quality + sustained conflict.
      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 42.0,
            trustInstruction: false,
            snapDistanceM: 30.0,
            headingDeltaDeg: 85.0,
            speedKmh: 25.0,
            maneuverType: 'turn',
            maneuverModifier: 'left',
          ),
        );
      }
      expect(state.active, isFalse);
    });

    test(
      '20) heading conflict streak resets when session becomes inactive',
      () {
        final guard = NavComplexityGuard();
        var t = DateTime(2026, 1, 1, 12);
        // Saturate the counter under corroborating quality — warning may show.
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        for (var i = 0; i < 8; i++) {
          t = t.add(const Duration(milliseconds: 500));
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 42.0,
              trustInstruction: false,
              snapDistanceM: 12.0,
              headingDeltaDeg: 85.0,
              speedKmh: 22.0,
              maneuverType: 'turn',
              maneuverModifier: 'left',
            ),
          );
        }
        expect(state.active, isTrue);

        // Session becomes inactive — reset should clear counter.
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(timestamp: t, liveRideActive: false, followMode: true),
        );
        expect(state.active, isFalse);

        // Resume with a single conflict spike + poor quality — must NOT
        // reactivate because the counter was reset.
        t = t.add(const Duration(milliseconds: 500));
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 42.0,
            trustInstruction: false,
            snapDistanceM: 32.0,
            headingDeltaDeg: 85.0,
            speedKmh: 22.0,
            maneuverType: 'turn',
            maneuverModifier: 'left',
          ),
        );
        expect(state.active, isFalse);
        expect(
          state.decision.triggerRules,
          isNot(contains('heading_route_conflict')),
        );
      },
    );
  });

  group('NAV-COMPLEXITY-CHURN-GATE-P0-FIELD-2026-07-29', () {
    // Field evidence (tablet test rides 2026-07-29):
    //   overall=97 route=100 heading=100 map-match=100 branchCount=0
    //   maneuverCount=2 offRoute=false rerouteState=false
    //   triggerRules=rapid_instruction_churn qualityRules=repeated_prediction
    //   predictionSupportingOnly=false structuralComplexityPresent=true
    //   show=true positiveStreak growing into the hundreds
    // On an ordinary, non-complex route WARN is a false positive. Churn alone
    // (with or without repeated prediction) must never activate WARN.
    test('field repro: churn + repeated prediction on ordinary high-confidence '
        'route with branchCount=0 keeps WARN hidden', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      var step = 0;
      for (var tick = 0; tick < 20; tick++) {
        t = t.add(const Duration(milliseconds: 700));
        if (tick == 2 || tick == 6) step += 1;
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 97.0,
            trustBearing: true,
            trustInstruction: true,
            snapDistanceM: 3.0,
            offRouteLikely: false,
            reroutePending: false,
            headingDeltaDeg: 6.0,
            predictionActive: true,
            gapBridgeMs: 500,
            instructionStepIndex: step,
            maneuverType: 'turn',
            maneuverModifier: 'right',
            speedKmh: 46.0,
            distanceToManeuverM: 320.0,
          ),
        );
      }
      expect(
        state.active,
        isFalse,
        reason: 'WARN must not appear on an ordinary route',
      );
      expect(state.decision.visible, isFalse);
      expect(state.decision.branchCount, 0);
      expect(state.decision.offRoute, isFalse);
      expect(state.decision.rerouteState, isFalse);
      expect(state.decision.structuralComplexityPresent, isFalse);
      expect(state.decision.effectiveScore, 0);
      expect(state.decision.rawScore, 0);
      expect(
        state.decision.triggerRules,
        isNot(contains('rapid_instruction_churn')),
        reason: 'churn is now a QUALITY signal, never structural',
      );
      expect(
        state.decision.qualityRules,
        contains('rapid_instruction_churn'),
        reason: 'churn stays observable in qualityRules',
      );
    });

    test(
      'churn plus one genuine structural signal (ambiguous roundabout) still '
      'warns after the required positive streak',
      () {
        final guard = NavComplexityGuard();
        var t = DateTime(2026, 1, 1, 12);
        NavComplexityGuardState state = NavComplexityGuardState.inactive;
        var step = 0;
        for (var tick = 0; tick < 6; tick++) {
          t = t.add(const Duration(milliseconds: 500));
          if (tick == 1 || tick == 3) step += 1;
          state = guard.update(
            _input(
              timestamp: t,
              overallConfidence: 74.0,
              snapDistanceM: 9.0,
              instructionStepIndex: step,
              maneuverType: 'roundabout',
              maneuverModifier: '',
              speedKmh: 18.0,
              distanceToManeuverM: 60.0,
            ),
          );
        }
        expect(state.active, isTrue);
        expect(state.decision.triggerRules, contains('ambiguous_instruction'));
        expect(
          state.decision.qualityRules,
          contains('rapid_instruction_churn'),
        );
        expect(state.decision.structuralComplexityPresent, isTrue);
      },
    );

    test('churn severity may only be `warning` when a real structural risk is '
        'present (heading_route_conflict) — never for churn alone', () {
      final guard = NavComplexityGuard();
      var t = DateTime(2026, 1, 1, 12);
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      var step = 0;
      for (var tick = 0; tick < 20; tick++) {
        t = t.add(const Duration(milliseconds: 500));
        if (tick == 2 || tick == 5 || tick == 8) step += 1;
        state = guard.update(
          _input(
            timestamp: t,
            overallConfidence: 88.0,
            trustBearing: true,
            trustInstruction: true,
            snapDistanceM: 5.0,
            headingDeltaDeg: 12.0,
            instructionStepIndex: step,
            maneuverType: 'turn',
            maneuverModifier: 'right',
            speedKmh: 40.0,
            distanceToManeuverM: 260.0,
          ),
        );
      }
      expect(state.severity, NavComplexitySeverity.info);
      expect(state.active, isFalse);
    });
  });
}
