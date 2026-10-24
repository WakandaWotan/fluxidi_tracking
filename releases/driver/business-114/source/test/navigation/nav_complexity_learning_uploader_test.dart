import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_guard.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_intelligence.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_learning_uploader.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

NavComplexityIntelligenceEvent _sampleEvent() {
  const state = NavComplexityGuardState(
    active: true,
    severity: NavComplexitySeverity.warning,
    reasonCode: 'heading_route_conflict',
    cooldownMs: 45000,
    predictionRepeated: true,
  );
  final input = NavComplexityGuardInput(
    timestamp: DateTime.utc(2026, 7, 7, 18, 0),
    overallConfidence: 48.0,
    trustInstruction: true,
    trustBearing: false,
    snapDistanceM: 22.0,
    speedKmh: 32.0,
    maneuverType: 'turn',
    maneuverModifier: 'right',
  );
  return NavComplexityIntelligenceBuilder.fromGuardContext(
    state: state,
    input: input,
    diagnosticsSessionId: 'nav_test_session',
  );
}

void main() {
  group('NAV-AI-4A NavComplexityLearningUploader', () {
    test('missing token/base url skips safely without throwing', () async {
      final uploader = NavComplexityLearningUploader(
        client: _FailingClient(),
      );
      await uploader.uploadDryRunEvent(_sampleEvent());
    });

    test('sends expected sanitized dry-run payload when configured', () async {
      Map<String, dynamic>? capturedBody;
      final client = MockClient((request) async {
        expect(
          request.url.path,
          '/admin/nav-complexity-events/ingest-dry-run',
        );
        expect(request.headers['authorization'], 'Bearer test-token');
        capturedBody =
            jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"ok":true,"stored":true}', 200);
      });

      final uploader = NavComplexityLearningUploader(
        client: client,
        baseUrlOverride: 'https://fluxidi-learning-api.fluxidi.workers.dev',
        serviceTokenOverride: 'test-token',
      );
      await uploader.uploadDryRunEvent(_sampleEvent());

      expect(capturedBody, isNotNull);
      expect(capturedBody!['dryRunStore'], isTrue);
      expect(capturedBody!['source'], 'flutter_manual_test');
      final event = capturedBody!['event'] as Map<String, dynamic>;
      expect(event['type'], 'nav_complexity_event');
      expect(event['reasonCode'], 'heading_route_conflict');
      expect(event.containsKey('latitude'), isFalse);
      expect(event.containsKey('longitude'), isFalse);
      expect(event.containsKey('bookingId'), isFalse);
    });

    test('HTTP failure does not throw', () async {
      final client = MockClient((request) async {
        return http.Response('{"ok":false,"error":"unauthorized"}', 401);
      });
      final uploader = NavComplexityLearningUploader(
        client: client,
        baseUrlOverride: 'https://fluxidi-learning-api.fluxidi.workers.dev',
        serviceTokenOverride: 'test-token',
      );
      await uploader.uploadDryRunEvent(_sampleEvent());
    });

    test('timeout/network failure does not throw', () async {
      final client = MockClient((request) async {
        throw Exception('network down');
      });
      final uploader = NavComplexityLearningUploader(
        client: client,
        baseUrlOverride: 'https://fluxidi-learning-api.fluxidi.workers.dev',
        serviceTokenOverride: 'test-token',
      );
      await uploader.uploadDryRunEvent(_sampleEvent());
    });

    test('payload builder excludes forbidden PII keys', () {
      final body = buildNavComplexityDryRunIngestBody(_sampleEvent());
      final event = body['event'] as Map<String, dynamic>;
      expect(navComplexityUploadPayloadContainsForbiddenKeys(event), isFalse);
      expect(event.containsKey('address'), isFalse);
      expect(event.containsKey('driver_id'), isFalse);
    });

    test('ingest URI is derived from learning base URL', () {
      final uri = navComplexityLearningIngestUri(
        'https://fluxidi-learning-api.fluxidi.workers.dev/',
      );
      expect(
        uri.toString(),
        'https://fluxidi-learning-api.fluxidi.workers.dev/admin/nav-complexity-events/ingest-dry-run',
      );
    });
  });

  group('NAV-AI-4A NavComplexityIntelligenceExporter', () {
    test('cloud upload flag off does not invoke uploader', () async {
      var uploadCalls = 0;
      final exporter = NavComplexityIntelligenceExporter(
        learningUploader: _TrackingUploader(() => uploadCalls++),
      );
      var localCalls = 0;

      await exporter.exportEvent(
        _sampleEvent(),
        recordLocally: (_) async {
          localCalls++;
        },
      );

      expect(kNavComplexityIntelligenceCloudUploadEnabled, isFalse);
      expect(localCalls, 1);
      expect(uploadCalls, 0);
    });

    test('local export still runs when cloud flag is off', () async {
      final exporter = NavComplexityIntelligenceExporter(
        learningUploader: _TrackingUploader(() {}),
      );
      Map<String, dynamic>? localPayload;

      await exporter.exportEvent(
        _sampleEvent(),
        recordLocally: (payload) async {
          localPayload = payload;
        },
      );

      expect(localPayload?['type'], 'nav_complexity_event');
    });
  });
}

class _FailingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    throw Exception('should not be called');
  }
}

class _TrackingUploader extends NavComplexityLearningUploader {
  _TrackingUploader(this._onUpload);

  final void Function() _onUpload;

  @override
  Future<void> uploadDryRunEvent(NavComplexityIntelligenceEvent event) async {
    _onUpload();
  }
}
