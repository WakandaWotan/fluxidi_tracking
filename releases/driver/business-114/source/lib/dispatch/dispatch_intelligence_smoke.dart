// CLOUD-AI-3: internal smoke helper for the Dispatch Intelligence client.
//
// Not wired to any UI and never called automatically. To use it, invoke
// [runDispatchIntelligenceSmoke] manually from a debug/profile build started
// with:
//   --dart-define=USE_DISPATCH_INTELLIGENCE_WORKER=true
//
// Uses fixed sample values only — no booking IDs, addresses, names, emails,
// phone numbers, or coordinates.

import 'package:flutter/foundation.dart';

import 'dispatch_intelligence_client.dart';

const String _diagTag = 'CLOUD_AI_3';

void _logSmoke(String result, String reason) {
  debugPrint('[$_diagTag] result=$result reason=$reason');
}

/// Debug/profile-only smoke check: verifies the Dispatch Intelligence Worker
/// is reachable via [DispatchIntelligenceClient]. No-op in release builds and
/// when kUseDispatchIntelligenceWorker is false (client returns `disabled`).
Future<void> runDispatchIntelligenceSmoke() async {
  if (kReleaseMode) {
    _logSmoke('disabled', 'release_build');
    return;
  }

  final client = DispatchIntelligenceClient();
  if (!client.isEnabled) {
    _logSmoke('disabled', 'flag_off');
    return;
  }

  final health = await client.health();
  if (!health.ok) {
    _logSmoke('error', 'health_${health.failureReason}');
    return;
  }
  _logSmoke('ok', 'health_${health.service}_${health.version}');

  final suggestions = await client.offlineMapSuggestions(
    country: 'BE',
    pickupArea: 'Maarkedal',
    dropoffArea: 'Brussels Airport',
    airportCode: 'BRU',
  );
  if (!suggestions.ok) {
    _logSmoke('error', 'offline_maps_${suggestions.failureReason}');
    return;
  }
  final regionIds = suggestions.suggestions
      .map((s) => s.regionId)
      .take(6)
      .join(',');
  _logSmoke(
    'ok',
    'offline_maps_count_${suggestions.suggestions.length}'
    '${regionIds.isEmpty ? '' : '_regions_$regionIds'}',
  );
}
