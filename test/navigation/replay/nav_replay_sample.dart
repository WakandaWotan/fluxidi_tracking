// NAV-R12-F: test-only replay input model for the driver navigation engine.
//
// This file is test tooling. It never runs in production and may hold raw
// lat/lng because fixtures are synthetic and diagnostics imports are
// dead-reckoned from the PII-safe export (which itself carries no positions).
import 'dart:convert';
import 'dart:math' as math;

/// One recorded/synthetic GPS fix to feed through the nav engine modules.
class NavReplaySample {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double speedKmh;

  /// GPS course over ground in degrees (0..360), null when unavailable.
  final double? headingDeg;
  final double? accuracyM;

  /// Optional expectation marker for fixtures, e.g. 'on_route',
  /// 'route_deviation', 'off_route'. Purely informational for asserts.
  final String? expectedRouteState;

  const NavReplaySample({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    this.headingDeg,
    this.accuracyM,
    this.expectedRouteState,
  });
}

/// Imports samples from a NavDiagnosticsRecorder JSON export.
///
/// The production diagnostics export is PII-safe: `gps_update` events carry
/// only dtMs / speedKmh / accuracyM / heading / distanceFromLastM and no
/// positions. Positions are therefore reconstructed by dead reckoning from a
/// caller-chosen synthetic origin, which preserves the motion *shape*
/// (speeds, headings, timing) that the engine modules react to.
class NavReplayDiagnosticsImport {
  static const double _metersPerDegLat = 111320.0;

  /// Parses an export JSON string (as written by NavDiagnosticsRecorder in
  /// JSON mode) and returns dead-reckoned samples for [sessionIndex].
  static List<NavReplaySample> samplesFromExportJson(
    String exportJson, {
    double originLatitude = 50.85,
    double originLongitude = 4.35,
    int sessionIndex = 0,
  }) {
    final decoded = jsonDecode(exportJson);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('export root must be a JSON object');
    }
    final sessions = decoded['sessions'];
    if (sessions is! List || sessionIndex >= sessions.length) {
      throw const FormatException('export has no session at requested index');
    }
    final session = sessions[sessionIndex];
    if (session is! Map<String, dynamic>) {
      throw const FormatException('session must be a JSON object');
    }
    final events = session['events'];
    if (events is! List) {
      throw const FormatException('session has no events list');
    }

    final samples = <NavReplaySample>[];
    var lat = originLatitude;
    var lon = originLongitude;
    DateTime? clock;

    for (final raw in events) {
      if (raw is! Map<String, dynamic>) continue;
      if (raw['type'] != 'gps_update') continue;
      final data = raw['data'];
      if (data is! Map<String, dynamic>) continue;

      final ts = DateTime.tryParse(raw['ts']?.toString() ?? '');
      final dtMs = _asDouble(data['dtMs'])?.round() ?? 1000;
      clock =
          ts ??
          (clock?.add(Duration(milliseconds: dtMs)) ?? DateTime.utc(2026));

      final heading = _asDouble(data['heading']);
      final distanceM = _asDouble(data['distanceFromLastM']) ?? 0.0;
      if (heading != null && heading.isFinite && distanceM > 0) {
        final moved = offsetMeters(
          latitude: lat,
          longitude: lon,
          bearingDeg: heading,
          distanceM: distanceM,
        );
        lat = moved.latitude;
        lon = moved.longitude;
      }

      samples.add(
        NavReplaySample(
          timestamp: clock,
          latitude: lat,
          longitude: lon,
          speedKmh: _asDouble(data['speedKmh']) ?? 0.0,
          headingDeg: heading,
          accuracyM: _asDouble(data['accuracyM']),
        ),
      );
    }
    return samples;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Flat-earth offset good enough for short replay hops.
  static ({double latitude, double longitude}) offsetMeters({
    required double latitude,
    required double longitude,
    required double bearingDeg,
    required double distanceM,
  }) {
    final rad = bearingDeg * math.pi / 180.0;
    final dLat = distanceM * math.cos(rad) / _metersPerDegLat;
    final metersPerDegLon =
        _metersPerDegLat * math.cos(latitude * math.pi / 180.0);
    final dLon = metersPerDegLon.abs() < 1.0
        ? 0.0
        : distanceM * math.sin(rad) / metersPerDegLon;
    return (latitude: latitude + dLat, longitude: longitude + dLon);
  }
}
