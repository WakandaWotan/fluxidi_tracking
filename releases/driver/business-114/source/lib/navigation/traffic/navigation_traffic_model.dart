import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../driver_navigation_models.dart';
import '../driver_navigation_map_config.dart' show kDriverRouteLineColor;

enum NavigationTrafficSourceState { available, stale, unavailable, unbound }

enum NavigationTrafficClass { normal, light, heavy, severe, closed }

enum NavigationTrafficEvent { congestion, incident, roadworks, closure }

// Presentation thresholds; never infer confidence or a traffic class from GPS.
const double navigationTrafficVisualConfidence = .8;
const double navigationTrafficAlertConfidence = .85;
const Duration navigationTrafficMaxAge = Duration(minutes: 3);
const int navigationTrafficMaxSegments = 256;

String navigationTrafficGeometryFingerprint(List<DriverLonLat> geometry) =>
    sha256
        .convert(
          utf8.encode(
            jsonEncode([
              for (final point in geometry)
                [point.lon.toDouble(), point.lat.toDouble()],
            ]),
          ),
        )
        .toString();

int navigationTrafficColor(NavigationTrafficClass traffic) => switch (traffic) {
  NavigationTrafficClass.normal => kDriverRouteLineColor,
  NavigationTrafficClass.light => 0xFFF59E0B,
  NavigationTrafficClass.heavy => 0xFFDC2626,
  NavigationTrafficClass.severe => 0xFF991B1B,
  NavigationTrafficClass.closed => 0xFF7C2D52,
};

class NavigationTrafficSegment {
  const NavigationTrafficSegment({
    required this.start,
    required this.end,
    required this.traffic,
    required this.event,
    required this.confidence,
    required this.observedAt,
    required this.validUntil,
    this.delaySeconds,
    this.speedKmh,
  });
  // Vertex indices in the exact, directed route geometry; end is inclusive.
  final int start, end;
  final NavigationTrafficClass traffic;
  final NavigationTrafficEvent event;
  final double confidence;
  final DateTime observedAt, validUntil;
  final double? delaySeconds, speedKmh;
  DateTime get expiresAt {
    final ageLimit = observedAt.add(navigationTrafficMaxAge);
    return validUntil.isBefore(ageLimit) ? validUntil : ageLimit;
  }

  bool isFresh(DateTime now) =>
      !observedAt.isAfter(now) && expiresAt.isAfter(now);
}

class NavigationTrafficSnapshot {
  const NavigationTrafficSnapshot({
    required this.state,
    this.geometryFingerprint,
    this.revision = '',
    this.segments = const [],
    this.expiresAt,
  });
  const NavigationTrafficSnapshot.unavailable()
    : state = NavigationTrafficSourceState.unavailable,
      geometryFingerprint = null,
      revision = '',
      segments = const [],
      expiresAt = null;
  final NavigationTrafficSourceState state;
  final String? geometryFingerprint;
  final String revision;
  final List<NavigationTrafficSegment> segments;
  final DateTime? expiresAt;
  NavigationTrafficSourceState stateAt(DateTime now) {
    if (state != NavigationTrafficSourceState.available) return state;
    if (expiresAt == null ||
        !expiresAt!.isAfter(now) ||
        !segments.any((segment) => segment.isFresh(now))) {
      return NavigationTrafficSourceState.stale;
    }
    return state;
  }
}

/// Optional presentation DTO inside an already received route or preserved leg.
/// This consumer has no producer/network/fabric/routing authority. A schema and
/// exact geometry digest are mandatory; raw graph edge IDs are never indices.
/// No timestamps, classes, confidence or delay are synthesized on receipt.
NavigationTrafficSnapshot decodeNavigationTraffic({
  required Map<String, dynamic> response,
  required List<DriverLonLat> geometry,
  required DateTime now,
}) {
  const unbound = NavigationTrafficSnapshot(
    state: NavigationTrafficSourceState.unbound,
  );
  try {
    final routes = response['routes'];
    if (routes is! List || routes.isEmpty || routes.first is! Map) {
      return const NavigationTrafficSnapshot.unavailable();
    }
    final route = routes.first as Map;
    final candidates = <Map>[];
    if (route['traffic_visuals'] is Map)
      candidates.add(route['traffic_visuals'] as Map);
    final legs = route['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is Map && leg['traffic_visuals'] is Map) {
          candidates.add(leg['traffic_visuals'] as Map);
        }
      }
    }
    if (candidates.isEmpty)
      return const NavigationTrafficSnapshot.unavailable();
    // Multiple authorities/leg-local geometries need an upstream adapter.
    if (candidates.length != 1) return unbound;
    final value = candidates.single;
    final state = switch (value['sourceState']) {
      'AVAILABLE' => NavigationTrafficSourceState.available,
      'STALE' => NavigationTrafficSourceState.stale,
      'UNBOUND' => NavigationTrafficSourceState.unbound,
      _ => NavigationTrafficSourceState.unavailable,
    };
    if (state != NavigationTrafficSourceState.available) {
      return NavigationTrafficSnapshot(state: state);
    }
    if (value['schema'] != 'fluxidi-navigation-traffic-visuals-v1' ||
        value['binding'] != 'exact-directed-route-geometry' ||
        value['rights'] != 'usable' ||
        value['scope'] != 'public-road' ||
        geometry.length < 2 ||
        value['routeGeometrySha256'] !=
            navigationTrafficGeometryFingerprint(geometry)) {
      return unbound;
    }
    DateTime? timestamp(dynamic input) =>
        input is int && input >= 0 && input <= 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(input, isUtc: true)
        : null;
    final observedAt = timestamp(value['observedAt']);
    final validUntil = timestamp(value['validUntil']);
    if (observedAt == null ||
        validUntil == null ||
        observedAt.isAfter(now) ||
        !validUntil.isAfter(observedAt))
      return unbound;
    final expiry = validUntil.isBefore(observedAt.add(navigationTrafficMaxAge))
        ? validUntil
        : observedAt.add(navigationTrafficMaxAge);
    if (!expiry.isAfter(now))
      return const NavigationTrafficSnapshot(
        state: NavigationTrafficSourceState.stale,
      );
    final rows = value['segments'];
    if (rows is! List || rows.isEmpty)
      return const NavigationTrafficSnapshot.unavailable();
    if (rows.length > navigationTrafficMaxSegments) return unbound;
    final segments = <NavigationTrafficSegment>[];
    for (final row in rows) {
      if (row is! Map) return unbound;
      final start = row['startGeometryIndex'], end = row['endGeometryIndex'];
      final confidence = row['confidence'];
      final traffic = switch (row['trafficClass']) {
        'normal' => NavigationTrafficClass.normal,
        'light' => NavigationTrafficClass.light,
        'heavy' => NavigationTrafficClass.heavy,
        'severe' => NavigationTrafficClass.severe,
        'closed' => NavigationTrafficClass.closed,
        _ => null,
      };
      final event = switch (row['eventType']) {
        'congestion' => NavigationTrafficEvent.congestion,
        'incident' => NavigationTrafficEvent.incident,
        'roadworks' => NavigationTrafficEvent.roadworks,
        'closure' => NavigationTrafficEvent.closure,
        _ => null,
      };
      if (start is! int ||
          end is! int ||
          start < 0 ||
          end <= start ||
          end >= geometry.length ||
          confidence is! num ||
          !confidence.isFinite ||
          confidence < 0 ||
          confidence > 1 ||
          traffic == null ||
          event == null ||
          (traffic == NavigationTrafficClass.closed) !=
              (event == NavigationTrafficEvent.closure))
        return unbound;
      double? number(dynamic input) =>
          input is num && input.isFinite && input >= 0
          ? input.toDouble()
          : null;
      if (row['delaySeconds'] != null && number(row['delaySeconds']) == null ||
          row['speedKmh'] != null && number(row['speedKmh']) == null)
        return unbound;
      final segmentObserved = row.containsKey('observedAt')
          ? timestamp(row['observedAt'])
          : observedAt;
      final segmentUntil = row.containsKey('validUntil')
          ? timestamp(row['validUntil'])
          : validUntil;
      if (segmentObserved == null ||
          segmentUntil == null ||
          segmentObserved.isAfter(now) ||
          !segmentUntil.isAfter(segmentObserved))
        return unbound;
      segments.add(
        NavigationTrafficSegment(
          start: start,
          end: end,
          traffic: traffic,
          event: event,
          confidence: confidence.toDouble(),
          observedAt: segmentObserved,
          validUntil: segmentUntil.isBefore(expiry) ? segmentUntil : expiry,
          delaySeconds: number(row['delaySeconds']),
          speedKmh: number(row['speedKmh']),
        ),
      );
    }
    segments.sort((a, b) => a.start.compareTo(b.start));
    for (var i = 1; i < segments.length; i++) {
      if (segments[i].start < segments[i - 1].end) return unbound;
    }
    final snapshot = NavigationTrafficSnapshot(
      state: state,
      geometryFingerprint: value['routeGeometrySha256'] as String,
      revision: value['revision'] is String
          ? (value['revision'] as String).substring(
              0,
              math.min(128, (value['revision'] as String).length),
            )
          : '',
      segments: List.unmodifiable(segments),
      expiresAt: expiry,
    );
    return snapshot.stateAt(now) == NavigationTrafficSourceState.stale
        ? const NavigationTrafficSnapshot(
            state: NavigationTrafficSourceState.stale,
          )
        : snapshot;
  } catch (_) {
    // Malformed optional evidence must never turn a valid route into an error.
    return unbound;
  }
}
