import 'dart:convert';

import 'nav_complexity_guard.dart';

/// NAV-AI-1: local export enabled; cloud upload disabled until worker ingest
/// is approved and feature-flagged in production builds.
const bool kNavComplexityIntelligenceLocalExportEnabled = true;

/// NAV-AI-1: off by default — realtime safety never depends on this flag.
const bool kNavComplexityIntelligenceCloudUploadEnabled = false;

/// Sanitized navigation complexity event for future AI/learning ingestion.
///
/// No raw lat/lng, no addresses, no booking/customer identity.
class NavComplexityIntelligenceEvent {
  final String reasonCode;
  final String severity;
  final String confidenceBucket;
  final String snapDistBucket;
  final String speedBucket;
  final String maneuverType;
  final String maneuverModifier;
  final bool predictionRepeated;
  final bool trustBearing;
  final bool trustInstruction;
  final String occurredAtMinuteBucket;
  final String? sessionHash;

  const NavComplexityIntelligenceEvent({
    required this.reasonCode,
    required this.severity,
    required this.confidenceBucket,
    required this.snapDistBucket,
    required this.speedBucket,
    required this.maneuverType,
    required this.maneuverModifier,
    required this.predictionRepeated,
    required this.trustBearing,
    required this.trustInstruction,
    required this.occurredAtMinuteBucket,
    this.sessionHash,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': 'nav_complexity_event',
    'version': 1,
    'app': 'driver',
    'platform': 'flutter',
    'reasonCode': reasonCode,
    'severity': severity,
    'confidenceBucket': confidenceBucket,
    'snapDistBucket': snapDistBucket,
    'speedBucket': speedBucket,
    'maneuverType': maneuverType,
    'maneuverModifier': maneuverModifier,
    'predictionRepeated': predictionRepeated,
    'trustBearing': trustBearing,
    'trustInstruction': trustInstruction,
    'occurredAtMinuteBucket': occurredAtMinuteBucket,
    if (sessionHash != null) 'sessionHash': sessionHash,
  };

  String toJsonLine() => jsonEncode(toJson());
}

/// NAV-AI-1: builds sanitized events from guard inputs — pure/offline.
class NavComplexityIntelligenceBuilder {
  static NavComplexityIntelligenceEvent fromGuardContext({
    required NavComplexityGuardState state,
    required NavComplexityGuardInput input,
    String? diagnosticsSessionId,
    DateTime? now,
  }) {
    final ts = now ?? input.timestamp;
    return NavComplexityIntelligenceEvent(
      reasonCode: state.reasonCode,
      severity: state.severity.name,
      confidenceBucket: NavComplexityGuard.confidenceBucket(
        input.overallConfidence,
      ),
      snapDistBucket: NavComplexityGuard.snapDistanceBucket(
        input.snapDistanceM,
      ),
      speedBucket: speedBucket(input.speedKmh),
      maneuverType: normalizeManeuverType(input.maneuverType),
      maneuverModifier: normalizeManeuverModifier(input.maneuverModifier),
      predictionRepeated: state.predictionRepeated,
      trustBearing: input.trustBearing,
      trustInstruction: input.trustInstruction,
      occurredAtMinuteBucket: minuteBucket(ts),
      sessionHash: hashSessionId(diagnosticsSessionId),
    );
  }

  static String speedBucket(double? speedKmh) {
    final speed = speedKmh;
    if (speed == null || !speed.isFinite) return 'unknown';
    if (speed < 3.0) return 'stopped';
    if (speed < 15.0) return 'slow';
    if (speed < 35.0) return 'city';
    if (speed < 70.0) return 'urban';
    return 'fast';
  }

  static String normalizeManeuverType(String? raw) {
    final type = (raw ?? '').trim().toLowerCase();
    if (type.isEmpty) return 'unknown';
    if (type.contains('roundabout') || type.contains('rotary')) {
      return 'roundabout';
    }
    if (type.contains('arrive') || type.contains('destination')) {
      return 'arrive';
    }
    if (type.contains('depart') || type.contains('start')) return 'depart';
    if (type.contains('turn') ||
        type.contains('merge') ||
        type.contains('fork') ||
        type.contains('ramp')) {
      return 'turn';
    }
    return 'unknown';
  }

  static String normalizeManeuverModifier(String? raw) {
    final modifier = (raw ?? '').trim().toLowerCase();
    if (modifier.isEmpty) return 'unknown';
    if (modifier.contains('left') || modifier.contains('slight left')) {
      return 'left';
    }
    if (modifier.contains('right') || modifier.contains('slight right')) {
      return 'right';
    }
    if (modifier.contains('straight') || modifier.contains('continue')) {
      return 'straight';
    }
    if (modifier.contains('uturn') ||
        modifier.contains('u-turn') ||
        modifier == 'uturn') {
      return 'uturn';
    }
    return 'unknown';
  }

  /// Rounds [timestamp] to UTC minute for anonymous clustering.
  static String minuteBucket(DateTime timestamp) {
    final utc = timestamp.toUtc();
    final rounded = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
    );
    return rounded.toIso8601String();
  }

  /// Short opaque hash of an existing diagnostics session id — no PII.
  static String? hashSessionId(String? sessionId) {
    final id = sessionId?.trim();
    if (id == null || id.isEmpty) return null;
    return id.hashCode.toRadixString(16).padLeft(8, '0').substring(0, 8);
  }
}

/// NAV-AI-1: records sanitized events locally; cloud upload is stubbed/off.
class NavComplexityIntelligenceExporter {
  const NavComplexityIntelligenceExporter();

  /// Returns JSON line for local persistence. Cloud path is a no-op unless
  /// [kNavComplexityIntelligenceCloudUploadEnabled] is true (future worker).
  Future<void> exportEvent(
    NavComplexityIntelligenceEvent event, {
    required Future<void> Function(Map<String, dynamic> payload) recordLocally,
  }) async {
    if (!kNavComplexityIntelligenceLocalExportEnabled) return;
    await recordLocally(event.toJson());
    if (kNavComplexityIntelligenceCloudUploadEnabled) {
      await _uploadToWorkerStub(event);
    }
  }

  Future<void> _uploadToWorkerStub(NavComplexityIntelligenceEvent event) async {
    // NAV-AI-1 foundation: cloud ingest not wired yet — see
    // workers/learning/NAV_AI_1_NAV_COMPLEXITY.md for the planned endpoint.
    assert(() {
      // ignore: avoid_print
      print(
        '[NAV_AI_1] cloud_upload_stub reason=${event.reasonCode} '
        'severity=${event.severity}',
      );
      return true;
    }());
  }
}
