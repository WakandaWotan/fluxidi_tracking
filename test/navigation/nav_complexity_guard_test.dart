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
  );
}

void main() {
  group('NAV-R14A NavComplexityGuard', () {
    test('no popup during high-confidence normal route', () {
      final guard = NavComplexityGuard();
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var i = 0; i < 10; i++) {
        state = guard.update(
          _input(
            timestamp: DateTime(2026, 1, 1, 12, 0, i),
            overallConfidence: 82.0,
            snapDistanceM: 6.0,
          ),
        );
      }
      expect(state.active, isFalse);
      expect(state.complexCandidate, isFalse);
    });

    test('popup after sustained low confidence + high snap distance', () {
      final guard = NavComplexityGuard();
      NavComplexityGuardState state = NavComplexityGuardState.inactive;
      for (var ms = 0; ms <= 3000; ms += 500) {
        state = guard.update(
          _input(
            timestamp: DateTime(2026, 1, 1, 12, 0, 0, ms),
            overallConfidence: 48.0,
            trustInstruction: false,
            snapDistanceM: 38.0,
          ),
        );
      }
      expect(state.active, isTrue);
      expect(state.reasonCode, 'low_confidence');
    });

    test('popup after repeated prediction / gap bridge', () {
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
      expect(state.active, isTrue);
      expect(state.reasonCode, 'repeated_prediction');
      expect(state.predictionRepeated, isTrue);
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
            offRouteLikely: true,
          ),
        );
      }
      expect(state.active, isTrue);

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
}
