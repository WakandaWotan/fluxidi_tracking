import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';

enum RouteWarningState { available, stale, unavailable, unbound }

class RouteWarning {
  const RouteWarning({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    required this.validUntil,
    required this.observedAt,
    required this.confirmedAt,
    required this.point,
    required this.sourceRevision,
  });
  final String id, kind;
  final double start, end;
  final DateTime validUntil, observedAt, confirmedAt;
  final bool point;
  final int sourceRevision;
  String get label => switch (kind) {
    'accident' => 'Ongeval',
    'roadworks' => 'Wegwerkzaamheden',
    'closure' => 'Weg afgesloten',
    'lane-closure' => 'Rijstrookbeperking',
    _ => 'Incident',
  };
}

class RouteWarnings {
  const RouteWarnings(
    this.state,
    this.items,
    this.geometryHash,
    this.validUntil,
  );
  final RouteWarningState state;
  final List<RouteWarning> items;
  final String? geometryHash;
  final DateTime? validUntil;

  /// Consume the existing navigation's trusted along-route progress. No new
  /// GPS matcher, timers, network polling, traffic colors or ETA computation.
  RouteWarning? ahead({
    required double progressMeters,
    required bool trusted,
    required DateTime now,
    double withinMeters = 1500,
  }) {
    if (!trusted ||
        !progressMeters.isFinite ||
        progressMeters < 0 ||
        !withinMeters.isFinite ||
        withinMeters < 0 ||
        state != RouteWarningState.available ||
        validUntil == null ||
        !validUntil!.isAfter(now))
      return null;
    for (final w in items) {
      if (!w.validUntil.isAfter(now) ||
          now.difference(w.confirmedAt).inMilliseconds >= 180000 ||
          w.end < progressMeters ||
          math.max(0, w.start - progressMeters) > withinMeters)
        continue;
      return w;
    }
    return null;
  }
}

String warningGeometryHash(List<List<num>> vertices) => sha256
    .convert(
      utf8.encode(
        jsonEncode(
          vertices.map((p) => [p[0].toDouble(), p[1].toDouble()]).toList(),
        ),
      ),
    )
    .toString();

RouteWarnings decodeRouteWarnings({
  required Map<String, dynamic> dto,
  required List<List<num>> geometry,
  required String tenantId,
  required String companyId,
  required String graphVersion,
  required String manifestSha256,
  required String evidenceRevision,
  required String routeEvidenceId,
  required DateTime now,
}) {
  const unavailable = RouteWarnings(RouteWarningState.unbound, [], null, null);
  try {
    if (geometry.length < 2 ||
        geometry.any((p) => p.length != 2 || p.any((n) => !n.isFinite)) ||
        dto['schema'] != 'fluxidi-navigation-traffic-warnings-v1' ||
        dto['mode'] != 'warnings-only' ||
        dto['binding'] != 'exact-directed-route-geometry' ||
        dto['tenant_id'] != tenantId ||
        dto['company_id'] != companyId ||
        dto['graphVersion'] != graphVersion ||
        dto['manifestSha256'] != manifestSha256 ||
        dto['evidenceRevision'] != evidenceRevision ||
        dto['routeEvidenceId'] != routeEvidenceId ||
        dto['routeGeometrySha256'] != warningGeometryHash(geometry) ||
        dto['routeCostChanges'] != false ||
        dto['etaAdjustmentSeconds'] != null ||
        dto['trafficColors'] is! List ||
        (dto['trafficColors'] as List).isNotEmpty)
      return unavailable;
    DateTime date(dynamic n) {
      if (n is! int || n < 0 || n > 8640000000000000)
        throw const FormatException();
      return DateTime.fromMillisecondsSinceEpoch(n, isUtc: true);
    }

    final generated = date(dto['generatedAt']), until = date(dto['validUntil']);
    if (generated.isAfter(now) || !until.isAfter(generated)) return unavailable;
    if (!until.isAfter(now) ||
        now.difference(generated).inMilliseconds >= 180000)
      return RouteWarnings(
        RouteWarningState.stale,
        const [],
        dto['routeGeometrySha256'],
        until,
      );
    final rows = dto['warnings'];
    if (rows is! List || rows.length > 1024) return unavailable;
    final warnings = <RouteWarning>[];
    for (final row in rows) {
      if (row is! Map ||
          ![
            'accident',
            'incident',
            'roadworks',
            'closure',
            'lane-closure',
          ].contains(row['kind']) ||
          row['id'] is! String ||
          row['sourceRevision'] is! int ||
          row['sourceRevision'] < 0 ||
          row['point'] is! bool ||
          row['startGeometryIndex'] is! int ||
          row['endGeometryIndex'] is! int ||
          row['startGeometryIndex'] < 0 ||
          row['endGeometryIndex'] != row['startGeometryIndex'] + 1 ||
          row['endGeometryIndex'] >= geometry.length)
        return unavailable;
      double number(dynamic n) {
        if (n is! num || !n.isFinite || n < 0) throw const FormatException();
        return n.toDouble();
      }

      final from = number(row['startFraction']),
          to = number(row['endFraction']),
          start = number(row['startAlongMeters']),
          end = number(row['endAlongMeters']);
      if (from > 1 ||
          to > 1 ||
          to < from ||
          end < start ||
          row['point'] == true && (from != to || start != end))
        return unavailable;
      final observed = date(row['observedAt']),
          confirmed = date(row['confirmedAt']),
          expires = date(row['validUntil']);
      if (observed.isAfter(confirmed) ||
          confirmed.isAfter(now) ||
          !expires.isAfter(confirmed))
        return unavailable;
      if (!expires.isAfter(now) ||
          now.difference(confirmed).inMilliseconds >= 180000)
        continue;
      warnings.add(
        RouteWarning(
          id: row['id'],
          kind: row['kind'],
          start: start,
          end: end,
          validUntil: expires.isBefore(until) ? expires : until,
          observedAt: observed,
          confirmedAt: confirmed,
          point: row['point'],
          sourceRevision: row['sourceRevision'],
        ),
      );
    }
    warnings.sort((a, b) => a.start.compareTo(b.start));
    return RouteWarnings(
      warnings.isEmpty
          ? RouteWarningState.unavailable
          : RouteWarningState.available,
      List.unmodifiable(warnings),
      dto['routeGeometrySha256'],
      until,
    );
  } catch (_) {
    return unavailable;
  }
}
