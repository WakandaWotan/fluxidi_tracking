import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_monitor.dart';

NavComplexityMonitorInput _input({
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
  return NavComplexityMonitorInput(
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
  group('NAV-R14 NavComplexityMonitor', () {
    test('no popup during high-confidence normal route', () {
      final monitor = NavComplexityMonitor();
      NavCautionState state = NavCautionState.inactive;
      for (var i = 0; i < 10; i++) {
        state = monitor.update(
          _input(
            timestamp: DateTime(2026, 1, 1, 12, 0, i),
            overallConfidence: 82.0,
            snapDistanceM: 6.0,
          ),
        );
      }
      expect(state.shouldShowCaution, isFalse);
      expect(state.complexCandidate, isFalse);
    });

    test('popup after sustained low confidence + high snap distance', () {
      final monitor = NavComplexityMonitor();
      NavCautionState state = NavCautionState.inactive;
      for (var ms = 0; ms <= 3000; ms += 500) {
        state = monitor.update(
          _input(
            timestamp: DateTime(2026, 1, 1, 12, 0, 0, ms),
            overallConfidence: 48.0,
            trustInstruction: false,
            snapDistanceM: 38.0,
          ),
        );
      }
      expect(state.shouldShowCaution, isTrue);
      expect(state.reasonCode, 'low_confidence');
    });

    test('popup for repeated prediction / gap bridge', () {
      final monitor = NavComplexityMonitor();
      NavCautionState state = NavCautionState.inactive;
      var t = DateTime(2026, 1, 1, 12);
      for (var cycle = 0; cycle < 3; cycle++) {
        state = monitor.update(
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
        state = monitor.update(
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
        state = monitor.update(
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
      expect(state.shouldShowCaution, isTrue);
      expect(state.reasonCode, 'repeated_prediction');
    });

    test('cooldown prevents spam after recovery', () {
      final monitor = NavComplexityMonitor();
      var t = DateTime(2026, 1, 1, 12);

      // Trigger caution.
      NavCautionState state = NavCautionState.inactive;
      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = monitor.update(
          _input(
            timestamp: t,
            overallConfidence: 42.0,
            trustInstruction: false,
            snapDistanceM: 35.0,
          ),
        );
      }
      expect(state.shouldShowCaution, isTrue);

      // Recover and hide.
      for (var i = 0; i < 12; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = monitor.update(
          _input(
            timestamp: t,
            overallConfidence: 85.0,
            trustInstruction: true,
            trustBearing: true,
            snapDistanceM: 6.0,
          ),
        );
      }
      expect(state.shouldShowCaution, isFalse);

      // Complex again within cooldown — should stay hidden.
      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = monitor.update(
          _input(
            timestamp: t,
            overallConfidence: 40.0,
            trustInstruction: false,
            snapDistanceM: 40.0,
          ),
        );
      }
      expect(state.shouldShowCaution, isFalse);
      expect(state.complexCandidate, isTrue);
    });

    test('recovery hides after stable confidence returns', () {
      final monitor = NavComplexityMonitor();
      var t = DateTime(2026, 1, 1, 12);
      NavCautionState state = NavCautionState.inactive;

      for (var i = 0; i < 8; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = monitor.update(
          _input(
            timestamp: t,
            overallConfidence: 44.0,
            trustBearing: false,
            snapDistanceM: 32.0,
            offRouteLikely: true,
          ),
        );
      }
      expect(state.shouldShowCaution, isTrue);

      for (var i = 0; i < 12; i++) {
        t = t.add(const Duration(milliseconds: 500));
        state = monitor.update(
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
      expect(state.shouldShowCaution, isFalse);
    });
  });
}
