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
      expect(state.decision.triggerRules, contains('rapid_instruction_churn'));
    });

    test('decision snapshot exposes audit fields', () {
      final guard = NavComplexityGuard();
      final state = guard.update(
        _input(
          overallConfidence: 48.0,
          snapDistanceM: 40.0,
          headingDeltaDeg: 80.0,
          speedKmh: 25.0,
        ),
      );
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

    test('4) score=0 reason=none clears after negative hysteresis', () {
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
      expect(state.active, isTrue);
      expect(state.decision.transition, 'pending_clear');
      expect(state.decision.negativeStreak, 1);

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
      expect(state.active, isFalse);
      expect(state.decision.transition, 'cleared');
      expect(state.decision.visible, isFalse);
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
}
