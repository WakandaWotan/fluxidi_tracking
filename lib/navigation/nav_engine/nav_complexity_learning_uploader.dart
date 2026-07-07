import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'nav_complexity_intelligence.dart';

/// NAV-AI-4A: optional Learning Worker dry-run upload (disabled unless caller
/// checks [kNavComplexityIntelligenceCloudUploadEnabled]).
const String kLearningBaseUrl = String.fromEnvironment(
  'LEARNING_BASE_URL',
  defaultValue: 'https://fluxidi-learning-api.fluxidi.workers.dev',
);

/// Dev/staging only — never hardcode; pass via `--dart-define=LEARNING_SERVICE_TOKEN=...`.
const String kLearningServiceToken = String.fromEnvironment(
  'LEARNING_SERVICE_TOKEN',
  defaultValue: '',
);

const Duration kNavComplexityLearningUploadTimeout = Duration(milliseconds: 1500);

const String _diagTag = 'NAV_AI_4_UPLOAD';
const String _ingestPath = '/admin/nav-complexity-events/ingest-dry-run';
const String _uploadSource = 'flutter_manual_test';

const Set<String> _forbiddenPayloadKeys = {
  'latitude',
  'longitude',
  'lat',
  'lng',
  'lon',
  'address',
  'bookingid',
  'booking_id',
  'customerid',
  'customer_id',
  'driverid',
  'driver_id',
  'phone',
  'email',
  'name',
  'street',
  'coordinate',
  'location',
  'passenger',
  'payment',
  'document',
  'free_text',
  'note',
  'comment',
};

String _safeReason(String value, {int maxLen = 48}) {
  final text = value.trim();
  if (text.isEmpty) return 'na';
  return text.length > maxLen ? text.substring(0, maxLen) : text;
}

void _logUpload({required String result, required String reason}) {
  assert(() {
    debugPrint(
      '[$_diagTag] result=${_safeReason(result, maxLen: 16)} '
      'reason=${_safeReason(reason)}',
    );
    return true;
  }());
}

Uri _ingestUri(String baseUrl) {
  final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) return Uri.parse('https://invalid.local$_ingestPath');
  return Uri.parse(trimmed).replace(path: _ingestPath);
}

bool _containsForbiddenKeys(Map<String, dynamic> payload) {
  for (final key in payload.keys) {
    final normalized = key.toLowerCase();
    for (final forbidden in _forbiddenPayloadKeys) {
      if (normalized == forbidden ||
          normalized.endsWith('_$forbidden') ||
          normalized.startsWith('${forbidden}_') ||
          normalized.contains('_${forbidden}_')) {
        return true;
      }
    }
  }
  return false;
}

/// Best-effort uploader for sanitized nav complexity events.
class NavComplexityLearningUploader {
  const NavComplexityLearningUploader({
    http.Client? client,
    String? baseUrlOverride,
    String? serviceTokenOverride,
  }) : _client = client,
       _baseUrlOverride = baseUrlOverride,
       _serviceTokenOverride = serviceTokenOverride;

  final http.Client? _client;
  final String? _baseUrlOverride;
  final String? _serviceTokenOverride;

  /// POST sanitized event to admin dry-run ingest. Never throws; bounded logs only.
  Future<void> uploadDryRunEvent(NavComplexityIntelligenceEvent event) async {
    try {
      final baseUrl = (_baseUrlOverride ?? kLearningBaseUrl).trim();
      final token = (_serviceTokenOverride ?? kLearningServiceToken).trim();
      if (baseUrl.isEmpty || token.isEmpty) {
        _logUpload(result: 'skipped', reason: 'missing_config');
        return;
      }

      final eventJson = event.toJson();
      if (_containsForbiddenKeys(eventJson)) {
        _logUpload(result: 'failed', reason: 'forbidden_keys');
        return;
      }

      final body = jsonEncode(<String, dynamic>{
        'dryRunStore': true,
        'source': _uploadSource,
        'event': eventJson,
      });

      _logUpload(result: 'attempted', reason: event.reasonCode);

      final ownsClient = _client == null;
      final client = _client ?? http.Client();
      try {
        final response = await client
            .post(
              _ingestUri(baseUrl),
              headers: <String, String>{
                'Content-Type': 'application/json; charset=utf-8',
                'Authorization': 'Bearer $token',
              },
              body: body,
            )
            .timeout(kNavComplexityLearningUploadTimeout);

        if (response.statusCode >= 200 && response.statusCode < 300) {
          _logUpload(result: 'success', reason: event.reasonCode);
          return;
        }
        _logUpload(
          result: 'failed',
          reason: 'http_${response.statusCode}',
        );
      } on Exception {
        _logUpload(result: 'failed', reason: 'request_failed');
      } finally {
        if (ownsClient) {
          client.close();
        }
      }
    } on Exception {
      _logUpload(result: 'failed', reason: 'unexpected');
    }
  }
}

/// @visibleForTesting
Map<String, dynamic> buildNavComplexityDryRunIngestBody(
  NavComplexityIntelligenceEvent event,
) {
  return <String, dynamic>{
    'dryRunStore': true,
    'source': _uploadSource,
    'event': event.toJson(),
  };
}

/// @visibleForTesting
bool navComplexityUploadPayloadContainsForbiddenKeys(
  Map<String, dynamic> payload,
) {
  return _containsForbiddenKeys(payload);
}

/// @visibleForTesting
Uri navComplexityLearningIngestUri(String baseUrl) => _ingestUri(baseUrl);
