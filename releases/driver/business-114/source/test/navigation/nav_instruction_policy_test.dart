import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_instruction_policy.dart';

NavInstructionPolicyInput _input({
  String rawInstructionText = 'Turn left onto Elm Street',
  String maneuverType = 'turn',
  String maneuverModifier = 'left',
  double distanceToManeuverM = 250.0,
  double routeConfidence = 80.0,
  double instructionConfidenceScore = 80.0,
  bool trustInstruction = true,
  bool trustRouteSnap = true,
  bool offRouteLikely = false,
  bool routeDeviationLikely = false,
  bool oppositeDirectionLikely = false,
  bool backwardProgressLikely = false,
  bool reroutePending = false,
  bool forwardProgress = true,
  bool predictionActive = false,
}) {
  return NavInstructionPolicyInput(
    timestamp: DateTime(2026, 1, 1, 12),
    liveRideActive: true,
    rawInstructionText: rawInstructionText,
    maneuverType: maneuverType,
    maneuverModifier: maneuverModifier,
    distanceToManeuverM: distanceToManeuverM,
    routeConfidence: routeConfidence,
    instructionConfidenceScore: instructionConfidenceScore,
    trustInstruction: trustInstruction,
    trustRouteSnap: trustRouteSnap,
    offRouteLikely: offRouteLikely,
    routeDeviationLikely: routeDeviationLikely,
    oppositeDirectionLikely: oppositeDirectionLikely,
    backwardProgressLikely: backwardProgressLikely,
    reroutePending: reroutePending,
    forwardProgress: forwardProgress,
    predictionActive: predictionActive,
    speedKmh: 40.0,
  );
}

void main() {
  final policy = DriverNavInstructionPolicy();

  group('NAV-R12-E2 instruction policy: adaptation suppression', () {
    test('reliable route allows the real instruction', () {
      final out = policy.update(_input());
      expect(out.showOriginalInstruction, isTrue);
      expect(out.reason, 'maneuver_allowed');
      expect(out.isNeutralFallback, isFalse);
    });

    test('route deviation suppresses the stale instruction', () {
      final out = policy.update(_input(routeDeviationLikely: true));
      expect(out.showOriginalInstruction, isFalse);
      expect(out.isNeutralFallback, isTrue);
      expect(out.reason, 'route_adaptation_route_deviation');
    });

    test('opposite direction suppresses the stale instruction', () {
      final out = policy.update(_input(oppositeDirectionLikely: true));
      expect(out.showOriginalInstruction, isFalse);
      expect(out.reason, 'route_adaptation_opposite_direction');
    });

    test('backward progress suppresses the stale instruction', () {
      final out = policy.update(_input(backwardProgressLikely: true));
      expect(out.showOriginalInstruction, isFalse);
      expect(out.reason, 'route_adaptation_backward_progress');
    });

    test('off-route suppresses the stale instruction', () {
      final out = policy.update(_input(offRouteLikely: true));
      expect(out.showOriginalInstruction, isFalse);
      expect(out.reason, 'route_adaptation_off_route');
    });

    test('reroute pending suppresses even when snap still looks fine', () {
      final out = policy.update(_input(reroutePending: true));
      expect(out.showOriginalInstruction, isFalse);
      expect(out.reason, 'route_adaptation_reroute_pending');
    });

    test('adaptation reasons map to neutral non-blaming wording', () {
      final out = policy.update(_input(routeDeviationLikely: true));
      final text = navInstructionPolicyLocalizedText(
        policy: out,
        originalText: 'Turn left onto Elm Street',
        tr: ({required nl, required en, required fr, required es}) => en,
      );
      expect(text, 'Adapting route…');
      expect(text.toLowerCase(), isNot(contains('wrong')));
      expect(text.toLowerCase(), isNot(contains('off route')));
    });
  });

  group('NAV-R12-E2 instruction policy: 180°/U-turn handling', () {
    test('real reliable U-turn instruction remains allowed', () {
      final out = policy.update(
        _input(
          rawInstructionText: 'Make a U-turn at the roundabout',
          maneuverType: 'continue',
          maneuverModifier: 'uturn',
          distanceToManeuverM: 120.0,
        ),
      );
      expect(out.showOriginalInstruction, isTrue);
      expect(out.reason, 'uturn_allowed');
    });

    test('U-turn during route adaptation is suppressed', () {
      final out = policy.update(
        _input(
          rawInstructionText: 'Make a U-turn at the roundabout',
          maneuverType: 'continue',
          maneuverModifier: 'uturn',
          distanceToManeuverM: 120.0,
          routeDeviationLikely: true,
        ),
      );
      expect(out.showOriginalInstruction, isFalse);
      expect(out.reason, startsWith('route_adaptation'));
    });

    test('suspicious 180° wording without explicit maneuver type is gated '
        'like a U-turn', () {
      final out = policy.update(
        _input(
          rawInstructionText: 'Turn around when possible',
          maneuverType: 'turn',
          maneuverModifier: 'left',
          distanceToManeuverM: 900.0, // far away -> not plausible
        ),
      );
      expect(out.showOriginalInstruction, isFalse);
      expect(out.reason, 'uturn_distance');
    });

    test('U-turn without forward progress stays blocked', () {
      final out = policy.update(
        _input(
          rawInstructionText: 'Make a U-turn',
          maneuverModifier: 'uturn',
          distanceToManeuverM: 100.0,
          forwardProgress: false,
        ),
      );
      expect(out.showOriginalInstruction, isFalse);
      expect(out.reason, 'uturn_no_forward_progress');
    });
  });
}
