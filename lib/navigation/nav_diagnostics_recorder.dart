import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Local, PII-safe navigation diagnostics for Driver OS field tests.
class NavDiagnosticsRecorder {
  NavDiagnosticsRecorder._();

  static final NavDiagnosticsRecorder instance = NavDiagnosticsRecorder._();

  static const int maxSessions = 5;
  static const int maxSessionBytes = 1536 * 1024; // ~1.5 MB
  static const String _dirName = 'nav_diagnostics';
  static const String _indexFileName = 'sessions_index_v1.json';

  bool _initialized = false;
  Directory? _rootDir;
  String? _activeSessionId;
  DateTime? _sessionStartedAt;
  int _activeSessionBytes = 0;
  int _activeSessionEventCount = 0;
  bool _activeSessionCapped = false;
  Future<void> _writeChain = Future<void>.value();

  final Map<String, DateTime> _throttleAt = <String, DateTime>{};

  List<_NavDiagSessionMeta> _sessions = <_NavDiagSessionMeta>[];

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      final base = await getApplicationDocumentsDirectory();
      final root = Directory(
        '${base.path}${Platform.pathSeparator}$_dirName',
      );
      if (!await root.exists()) {
        await root.create(recursive: true);
      }
      _rootDir = root;
      await _loadIndex();
      _initialized = true;
    } catch (e) {
      debugPrint('[NAV_DIAG] init_failed error=$e');
    }
  }

  bool get hasActiveSession => _activeSessionId != null;

  Future<void> beginSessionIfNeeded({required String trigger}) async {
    await ensureInitialized();
    if (_activeSessionId != null) return;
    final id = 'nav_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    _activeSessionId = id;
    _sessionStartedAt = DateTime.now().toUtc();
    _activeSessionBytes = 0;
    _activeSessionEventCount = 0;
    _activeSessionCapped = false;
    await _pruneSessionsIfNeeded();
    await _appendEvent(
      type: 'session_started',
      data: <String, dynamic>{
        'trigger': _sanitizeToken(trigger),
        'sessionId': id,
      },
      force: true,
    );
    await _persistIndex();
    debugPrint('[NAV_DIAG] session_started id=$id trigger=$trigger');
  }

  Future<void> endSessionIfActive({required String reason}) async {
    if (_activeSessionId == null) return;
    await _appendEvent(
      type: 'session_ended',
      data: <String, dynamic>{
        'reason': _sanitizeToken(reason),
        'durationSec': _sessionStartedAt == null
            ? 0
            : DateTime.now()
                  .toUtc()
                  .difference(_sessionStartedAt!)
                  .inSeconds,
        'eventCount': _activeSessionEventCount,
      },
      force: true,
    );
    final endedId = _activeSessionId!;
    _activeSessionId = null;
    _sessionStartedAt = null;
    await _persistIndex(endedSessionId: endedId);
    debugPrint('[NAV_DIAG] session_ended id=$endedId reason=$reason');
  }

  Future<void> recordGpsUpdate({
    required int dtMs,
    required double speedKmh,
    required double accuracyM,
    double? heading,
    double? distanceFromLastM,
  }) async {
    if (!_shouldRecord(throttleKey: 'gps_update', minIntervalMs: 2000)) return;
    await _appendEvent(
      type: 'gps_update',
      data: <String, dynamic>{
        'dtMs': dtMs,
        'speedKmh': _round1(speedKmh),
        'accuracyM': _round1(accuracyM),
        if (heading != null && heading.isFinite) 'heading': _round1(heading),
        if (distanceFromLastM != null && distanceFromLastM.isFinite)
          'distanceFromLastM': _round1(distanceFromLastM),
      },
    );
  }

  Future<void> recordMarkerUpdate({
    required String source,
    double? snapDistM,
    double? bearing,
    int? markerLagMs,
    String? bearingSource,
    double? bearingDeltaDeg,
  }) async {
    if (!_shouldRecord(throttleKey: 'marker_update', minIntervalMs: 1200)) {
      return;
    }
    await _appendEvent(
      type: 'marker_update',
      data: <String, dynamic>{
        'source': _sanitizeToken(source),
        if (snapDistM != null && snapDistM.isFinite)
          'snapDistM': _round1(snapDistM),
        if (bearing != null && bearing.isFinite) 'bearing': _round1(bearing),
        if (markerLagMs != null) 'markerLagMs': markerLagMs,
        if (bearingSource != null)
          'bearingSource': _sanitizeToken(bearingSource),
        if (bearingDeltaDeg != null && bearingDeltaDeg.isFinite)
          'bearingDeltaDeg': _round1(bearingDeltaDeg),
      },
    );
  }

  Future<void> recordCameraUpdate({
    required bool follow,
    String? skippedReason,
    double? zoom,
    double? tilt,
    double? bearing,
  }) async {
    if (!_shouldRecord(throttleKey: 'camera_update', minIntervalMs: 1800)) {
      return;
    }
    await _appendEvent(
      type: 'camera_update',
      data: <String, dynamic>{
        'follow': follow,
        if (skippedReason != null)
          'skippedReason': _sanitizeToken(skippedReason),
        if (zoom != null) 'zoom': _round1(zoom),
        if (tilt != null) 'tilt': _round1(tilt),
        if (bearing != null && bearing.isFinite) 'bearing': _round1(bearing),
      },
    );
  }

  Future<void> recordManeuverProgress({
    double? distanceToNextM,
    String? instructionType,
    String? modifier,
  }) async {
    if (!_shouldRecord(
      throttleKey: 'maneuver_progress',
      minIntervalMs: 2500,
    )) {
      return;
    }
    await _appendEvent(
      type: 'maneuver_progress',
      data: <String, dynamic>{
        if (distanceToNextM != null && distanceToNextM.isFinite)
          'distanceToNextM': _round1(distanceToNextM),
        if (instructionType != null && instructionType.trim().isNotEmpty)
          'instructionType': _sanitizeToken(instructionType),
        if (modifier != null && modifier.trim().isNotEmpty)
          'modifier': _sanitizeToken(modifier),
      },
    );
  }

  Future<void> recordRerouteEvent({
    required bool offRoute,
    required String triggerReason,
    int? durationMs,
    bool? success,
    String? phase,
  }) async {
    await _appendEvent(
      type: 'reroute_event',
      data: <String, dynamic>{
        'offRoute': offRoute,
        'triggerReason': _sanitizeToken(triggerReason),
        if (durationMs != null) 'durationMs': durationMs,
        if (success != null) 'success': success,
        if (phase != null) 'phase': _sanitizeToken(phase),
      },
      force: true,
    );
  }

  Future<void> recordOfflineMode({
    required String transition,
    required String reason,
    int? durationMs,
    String? state,
  }) async {
    await _appendEvent(
      type: 'offline_mode',
      data: <String, dynamic>{
        'transition': _sanitizeToken(transition),
        'reason': _sanitizeToken(reason),
        if (durationMs != null) 'durationMs': durationMs,
        if (state != null) 'state': _sanitizeToken(state),
      },
      force: transition == 'entered' || transition == 'exited',
    );
  }

  Future<void> recordMapStyleChange({
    required String mode,
    required String phase,
    String? error,
  }) async {
    await _appendEvent(
      type: 'map_style_change',
      data: <String, dynamic>{
        'mode': _sanitizeToken(mode),
        'phase': _sanitizeToken(phase),
        if (error != null) 'error': _sanitizeError(error),
      },
      force: true,
    );
  }

  Future<void> recordException({
    required String context,
    required Object error,
    StackTrace? stack,
  }) async {
    await _appendEvent(
      type: 'exception',
      data: <String, dynamic>{
        'context': _sanitizeToken(context),
        'errorType': error.runtimeType.toString(),
        'message': _sanitizeError(error.toString()),
        if (stack != null) 'stack': _truncateStack(stack),
      },
      force: true,
    );
  }

  Future<void> recordNavEngineEvent({
    required String tag,
    required Map<String, dynamic> fields,
  }) async {
    final safeFields = <String, dynamic>{};
    for (final entry in fields.entries) {
      final key = _sanitizeToken(entry.key);
      final value = entry.value;
      if (value is num) {
        safeFields[key] = value is int ? value : _round1(value.toDouble());
      } else if (value is bool) {
        safeFields[key] = value;
      } else if (value != null) {
        safeFields[key] = _sanitizeToken(value.toString());
      }
    }
    await _appendEvent(
      type: 'nav_engine',
      data: <String, dynamic>{'tag': _sanitizeToken(tag), ...safeFields},
      throttleKey: 'nav_engine_$tag',
      minIntervalMs: _navEngineThrottleMs(tag),
    );
  }

  Future<void> recordValidationReport({
    required int durationSec,
    required int sampleCount,
    required double overallScore,
    required double gpsScore,
    required double routeConfidence,
    required double overallConfidence,
    required double snapAvgM,
    required int predictionEvents,
    required int offRouteEvents,
    required int cameraSkips,
    required String label,
    required String reason,
  }) async {
    await _appendEvent(
      type: 'nav_validation_report',
      data: <String, dynamic>{
        'tag': 'NAV_R10_REPORT',
        'durationSec': durationSec,
        'samples': sampleCount,
        'score': _round1(overallScore),
        'gps': _round1(gpsScore),
        'route': _round1(routeConfidence),
        'confidence': _round1(overallConfidence),
        'snapAvgM': _round1(snapAvgM),
        'predictionEvents': predictionEvents,
        'offRouteEvents': offRouteEvents,
        'cameraSkips': cameraSkips,
        'label': _sanitizeToken(label),
        'reason': _sanitizeToken(reason),
      },
      force: true,
    );
  }

  Future<File?> exportLatestSessions({
    int count = 1,
    bool asText = false,
  }) async {
    await ensureInitialized();
    await _writeChain;
    if (_activeSessionId != null) {
      await _persistIndex();
    }
    final root = _rootDir;
    if (root == null || _sessions.isEmpty) return null;

    final selected = _sessions.reversed.take(count.clamp(1, maxSessions)).toList();
    if (selected.isEmpty) return null;

    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final ext = asText ? 'txt' : 'json';
    final out = File(
      '${root.path}${Platform.pathSeparator}nav_diag_export_$stamp.$ext',
    );

    if (asText) {
      final buffer = StringBuffer();
      for (final session in selected) {
        buffer.writeln('=== session ${session.id} ===');
        buffer.writeln('startedAt=${session.startedAt}');
        buffer.writeln('endedAt=${session.endedAt ?? ''}');
        buffer.writeln('events=${session.eventCount} bytes=${session.bytes}');
        final file = File('${root.path}${Platform.pathSeparator}${session.fileName}');
        if (await file.exists()) {
          final lines = await file.readAsLines();
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final decoded = jsonDecode(line);
              buffer.writeln(const JsonEncoder.withIndent('  ').convert(decoded));
            } catch (_) {
              buffer.writeln(line);
            }
          }
        }
        buffer.writeln();
      }
      await out.writeAsString(buffer.toString(), flush: true);
    } else {
      final payload = <String, dynamic>{
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'sessionCount': selected.length,
        'sessions': <Map<String, dynamic>>[],
      };
      for (final session in selected) {
        final events = <Map<String, dynamic>>[];
        final file = File('${root.path}${Platform.pathSeparator}${session.fileName}');
        if (await file.exists()) {
          final lines = await file.readAsLines();
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final decoded = jsonDecode(line);
              if (decoded is Map) {
                events.add(Map<String, dynamic>.from(decoded));
              }
            } catch (_) {}
          }
        }
        payload['sessions']!.add(<String, dynamic>{
          'id': session.id,
          'startedAt': session.startedAt,
          'endedAt': session.endedAt,
          'eventCount': session.eventCount,
          'bytes': session.bytes,
          'events': events,
        });
      }
      await out.writeAsString(
        const JsonEncoder.withIndent(' ').convert(payload),
        flush: true,
      );
    }

    debugPrint(
      '[NAV_DIAG] session_exported format=$ext sessions=${selected.length} path=${out.path}',
    );
    return out;
  }

  int _navEngineThrottleMs(String tag) {
    switch (tag) {
      case 'NAV_R4_PROGRESS':
      case 'NAV_R6_CONFIDENCE':
        return 1500;
      case 'NAV_R5_CAMERA_POLICY':
        return 2000;
      case 'NAV_R7_PREDICTION':
        return 1200;
      case 'NAV_R9_OFFLINE':
        return 2500;
      default:
        return 1500;
    }
  }

  bool _shouldRecord({
    required String throttleKey,
    required int minIntervalMs,
  }) {
    if (_activeSessionId == null || _activeSessionCapped) return false;
    final now = DateTime.now();
    final last = _throttleAt[throttleKey];
    if (last != null && now.difference(last).inMilliseconds < minIntervalMs) {
      return false;
    }
    _throttleAt[throttleKey] = now;
    return true;
  }

  Future<void> _appendEvent({
    required String type,
    required Map<String, dynamic> data,
    bool force = false,
    String? throttleKey,
    int minIntervalMs = 0,
  }) async {
    if (_activeSessionId == null) return;
    if (!force && throttleKey != null && minIntervalMs > 0) {
      if (!_shouldRecord(throttleKey: throttleKey, minIntervalMs: minIntervalMs)) {
        return;
      }
    }
    if (_activeSessionCapped) return;

    final event = <String, dynamic>{
      'ts': DateTime.now().toUtc().toIso8601String(),
      'type': type,
      'data': data,
    };
    final line = '${jsonEncode(event)}\n';
    final bytes = utf8.encode(line).length;

    if (_activeSessionBytes + bytes > maxSessionBytes) {
      _activeSessionCapped = true;
      debugPrint('[NAV_DIAG] session_capped id=$_activeSessionId');
      return;
    }

    await _enqueueWrite(() async {
      final root = _rootDir;
      final sessionId = _activeSessionId;
      if (root == null || sessionId == null) return;
      final file = File(
        '${root.path}${Platform.pathSeparator}$sessionId.jsonl',
      );
      await file.writeAsString(line, mode: FileMode.append, flush: true);
      _activeSessionBytes += bytes;
      _activeSessionEventCount += 1;
      debugPrint('[NAV_DIAG] event_written type=$type');
    });
  }

  Future<void> _enqueueWrite(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) async {
      try {
        await op();
      } catch (e) {
        debugPrint('[NAV_DIAG] write_failed error=$e');
      }
    });
    return _writeChain;
  }

  Future<void> _loadIndex() async {
    final root = _rootDir;
    if (root == null) return;
    final indexFile = File('${root.path}${Platform.pathSeparator}$_indexFileName');
    if (!await indexFile.exists()) {
      _sessions = <_NavDiagSessionMeta>[];
      return;
    }
    try {
      final raw = await indexFile.readAsString();
      if (raw.trim().isEmpty) {
        _sessions = <_NavDiagSessionMeta>[];
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        _sessions = <_NavDiagSessionMeta>[];
        return;
      }
      final list = decoded['sessions'];
      if (list is! List) {
        _sessions = <_NavDiagSessionMeta>[];
        return;
      }
      _sessions = list
          .whereType<Map>()
          .map((m) => _NavDiagSessionMeta.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    } catch (_) {
      _sessions = <_NavDiagSessionMeta>[];
    }
  }

  Future<void> _persistIndex({String? endedSessionId}) async {
    final root = _rootDir;
    if (root == null) return;

    final activeId = _activeSessionId;
    if (activeId != null) {
      final existing = _sessions.indexWhere((s) => s.id == activeId);
      final meta = _NavDiagSessionMeta(
        id: activeId,
        startedAt: (_sessionStartedAt ?? DateTime.now().toUtc()).toIso8601String(),
        endedAt: null,
        fileName: '$activeId.jsonl',
        eventCount: _activeSessionEventCount,
        bytes: _activeSessionBytes,
      );
      if (existing >= 0) {
        _sessions[existing] = meta;
      } else {
        _sessions.add(meta);
      }
    }

    if (endedSessionId != null) {
      final idx = _sessions.indexWhere((s) => s.id == endedSessionId);
      if (idx >= 0) {
        final prev = _sessions[idx];
        _sessions[idx] = prev.copyWith(
          endedAt: DateTime.now().toUtc().toIso8601String(),
          eventCount: _activeSessionEventCount,
          bytes: _activeSessionBytes,
        );
      }
    }

    final indexFile = File('${root.path}${Platform.pathSeparator}$_indexFileName');
    final payload = <String, dynamic>{
      'version': 1,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'sessions': _sessions.map((s) => s.toJson()).toList(),
    };
    await indexFile.writeAsString(jsonEncode(payload), flush: true);
  }

  Future<void> _pruneSessionsIfNeeded() async {
    final root = _rootDir;
    if (root == null) return;
    while (_sessions.length >= maxSessions) {
      final oldest = _sessions.first;
      _sessions.removeAt(0);
      final file = File('${root.path}${Platform.pathSeparator}${oldest.fileName}');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  static double _round1(double value) => (value * 10).roundToDouble() / 10.0;

  static String _sanitizeToken(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'unknown';
    final cleaned = trimmed
        .replaceAll(RegExp(r'@[\w\.-]+\.\w+'), '[email]')
        .replaceAll(RegExp(r'\+?\d[\d\s\-]{7,}\d'), '[phone]')
        .replaceAll(RegExp(r'eyJ[\w\-]+\.[\w\-]+\.[\w\-]+'), '[token]')
        .replaceAll(RegExp(r'https?://\S+'), '[url]');
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  static String _sanitizeError(String raw) {
    var cleaned = raw
        .replaceAll(RegExp(r'-?\d+\.\d{4,}'), '[coord]')
        .replaceAll(RegExp(r'@[\w\.-]+\.\w+'), '[email]')
        .replaceAll(RegExp(r'\+?\d[\d\s\-]{7,}\d'), '[phone]')
        .replaceAll(RegExp(r'eyJ[\w\-]+\.[\w\-]+\.[\w\-]+'), '[token]')
        .replaceAll(RegExp(r'https?://\S+'), '[url]');
    if (cleaned.length > 240) {
      cleaned = cleaned.substring(0, 240);
    }
    return cleaned;
  }

  static String _truncateStack(StackTrace stack) {
    final lines = stack.toString().split('\n');
    final kept = lines.take(8).map((line) {
      var trimmed = line.trim();
      if (trimmed.length > 160) trimmed = trimmed.substring(0, 160);
      return trimmed;
    }).join('\n');
    return kept;
  }
}

class _NavDiagSessionMeta {
  final String id;
  final String startedAt;
  final String? endedAt;
  final String fileName;
  final int eventCount;
  final int bytes;

  const _NavDiagSessionMeta({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.fileName,
    required this.eventCount,
    required this.bytes,
  });

  factory _NavDiagSessionMeta.fromJson(Map<String, dynamic> json) {
    return _NavDiagSessionMeta(
      id: (json['id'] ?? '').toString(),
      startedAt: (json['startedAt'] ?? '').toString(),
      endedAt: (json['endedAt'] ?? '').toString().trim().isEmpty
          ? null
          : (json['endedAt'] ?? '').toString(),
      fileName: (json['fileName'] ?? '').toString(),
      eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'startedAt': startedAt,
    'endedAt': endedAt,
    'fileName': fileName,
    'eventCount': eventCount,
    'bytes': bytes,
  };

  _NavDiagSessionMeta copyWith({
    String? endedAt,
    int? eventCount,
    int? bytes,
  }) {
    return _NavDiagSessionMeta(
      id: id,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      fileName: fileName,
      eventCount: eventCount ?? this.eventCount,
      bytes: bytes ?? this.bytes,
    );
  }
}
