import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_guard.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_intelligence.dart';

void main() {
  group('NAV-AI-1 NavComplexityIntelligenceBuilder', () {
    test('builds sanitized event JSON without coordinates', () {
      final input = NavComplexityGuardInput(
        timestamp: DateTime.utc(2026, 7, 7, 18, 12, 34),
        overallConfidence: 48.0,
        trustInstruction: false,
        trustBearing: true,
        snapDistanceM: 28.0,
        speedKmh: 32.0,
        maneuverType: 'turn',
        maneuverModifier: 'right',
      );
      const state = NavComplexityGuardState(
        active: true,
        severity: NavComplexitySeverity.warning,
        reasonCode: 'low_confidence',
        cooldownMs: 45000,
        predictionRepeated: true,
      );
      final event = NavComplexityIntelligenceBuilder.fromGuardContext(
        state: state,
        input: input,
        diagnosticsSessionId: 'nav_1234567890',
      );
      final json = event.toJson();
      expect(json['type'], 'nav_complexity_event');
      expect(json['version'], 1);
      expect(json['reasonCode'], 'low_confidence');
      expect(json['confidenceBucket'], '40-60');
      expect(json['snapDistBucket'], '15-30');
      expect(json['speedBucket'], 'city');
      expect(json['maneuverType'], 'turn');
      expect(json['maneuverModifier'], 'right');
      expect(json['predictionRepeated'], isTrue);
      expect(json.containsKey('latitude'), isFalse);
      expect(json.containsKey('longitude'), isFalse);
      expect(json['sessionHash'], isNotNull);
    });

    test('cloud upload flag is off by default', () {
      expect(kNavComplexityIntelligenceCloudUploadEnabled, isFalse);
      expect(kNavComplexityIntelligenceLocalExportEnabled, isTrue);
    });

    test('normalizes maneuver type and modifier buckets', () {
      expect(
        NavComplexityIntelligenceBuilder.normalizeManeuverType('rotary'),
        'roundabout',
      );
      expect(
        NavComplexityIntelligenceBuilder.normalizeManeuverModifier(
          'slight left',
        ),
        'left',
      );
      expect(NavComplexityIntelligenceBuilder.speedBucket(2.0), 'stopped');
      expect(NavComplexityIntelligenceBuilder.speedBucket(90.0), 'fast');
    });
  });
}
