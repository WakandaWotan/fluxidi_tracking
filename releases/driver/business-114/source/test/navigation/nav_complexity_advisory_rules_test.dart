import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_advisory_rules.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('NAV-AI-5A NavComplexityAdvisoryRulesClient', () {
    test('flag off skips fetch', () async {
      var called = false;
      final client = NavComplexityAdvisoryRulesClient(
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
        store: NavComplexityAdvisoryRulesStore.instance,
      );
      final result = await client.fetchIfEnabled();
      expect(kNavComplexityFetchAdvisoryRules, isFalse);
      expect(result, isNull);
      expect(called, isFalse);
    });

    test('missing token/base url skips safely', () async {
      final client = NavComplexityAdvisoryRulesClient(
        client: MockClient((request) async {
          throw Exception('should not be called');
        }),
        baseUrlOverride: '',
        serviceTokenOverride: '',
      );
      await client.fetch();
    });

    test('successful fetch parses advisory rules', () async {
      final store = NavComplexityAdvisoryRulesStore.instance;
      store.clear();

      final body = jsonEncode(<String, dynamic>{
        'ok': true,
        'advisoryOnly': true,
        'version': 1,
        'generatedAt': '2026-07-08T08:00:00.000Z',
        'rules': [
          <String, dynamic>{
            'id': 'rule_repeated_prediction_city',
            'scope': 'global',
            'reasonCode': 'repeated_prediction',
            'speedBucket': 'city',
            'recommendation': 'consider_prediction_hold_tuning',
            'confidence': 0.72,
            'minSamples': 20,
            'sampleCount': 43,
            'enabledForRuntime': false,
          },
        ],
      });

      final client = NavComplexityAdvisoryRulesClient(
        client: MockClient((request) async {
          expect(request.url.path, '/admin/nav-complexity-rules/advisory');
          expect(request.headers['authorization'], 'Bearer test-token');
          return http.Response(body, 200);
        }),
        baseUrlOverride: 'https://fluxidi-learning-api.fluxidi.workers.dev',
        serviceTokenOverride: 'test-token',
        store: store,
      );

      final result = await client.fetch();
      expect(result, isNotNull);
      expect(result!.advisoryOnly, isTrue);
      expect(result.rules.length, 1);
      expect(result.rules.first.enabledForRuntime, isFalse);
      expect(result.rules.first.recommendation, 'consider_prediction_hold_tuning');
      expect(store.latest?.rules.length, 1);
    });

    test('fetched rules are advisoryOnly and enabledForRuntime false', () async {
      final json = NavComplexityAdvisoryRulesResponse.fromJson(<String, dynamic>{
        'ok': true,
        'advisoryOnly': true,
        'version': 1,
        'rules': [
          <String, dynamic>{
            'id': 'rule_threshold_sensitivity',
            'scope': 'global',
            'reasonCode': 'low_confidence',
            'recommendation': 'review_complexity_threshold_sensitivity',
            'confidence': 0.5,
            'minSamples': 20,
            'sampleCount': 25,
            'enabledForRuntime': false,
          },
        ],
      });
      expect(json.advisoryOnly, isTrue);
      expect(json.rules.every((r) => r.enabledForRuntime == false), isTrue);
    });

    test('HTTP failure does not throw', () async {
      final client = NavComplexityAdvisoryRulesClient(
        client: MockClient((request) async {
          return http.Response('{"ok":false}', 401);
        }),
        baseUrlOverride: 'https://fluxidi-learning-api.fluxidi.workers.dev',
        serviceTokenOverride: 'test-token',
      );
      await client.fetch();
    });

    test('payload rejects forbidden PII keys', () {
      expect(
        navComplexityAdvisoryRulesPayloadContainsForbiddenKeys(<String, dynamic>{
          'ok': true,
          'latitude': 51.2,
        }),
        isTrue,
      );
      expect(
        navComplexityAdvisoryRulesPayloadContainsForbiddenKeys(<String, dynamic>{
          'ok': true,
          'advisoryOnly': true,
          'rules': [],
        }),
        isFalse,
      );
    });

    test('ingest URI helper builds advisory path', () {
      final uri = navComplexityAdvisoryRulesUri(
        'https://fluxidi-learning-api.fluxidi.workers.dev/',
      );
      expect(
        uri.toString(),
        'https://fluxidi-learning-api.fluxidi.workers.dev/admin/nav-complexity-rules/advisory',
      );
    });
  });
}
