// RELEASE-P0: post-reroute apply progress — forward segment selection,
// apply-time projection, and behind-geometry trim. Pure / unit-testable.
import 'dart:math' as math;

/// One route vertex (lat/lon degrees).
class NavRerouteApplyLatLon {
  const NavRerouteApplyLatLon({required this.lat, required this.lon});
  final double lat;
  final double lon;
}

/// Result of projecting the vehicle onto a candidate reroute package at
/// response-acceptance time.
class NavRerouteApplyProgressResult {
  const NavRerouteApplyProgressResult({
    required this.accepted,
    required this.reason,
    this.segmentIndex,
    this.segmentT,
    this.distanceAlongRouteM,
    this.snapDistanceM,
    this.segmentBearingDeg,
    this.courseDeltaDeg,
    this.trimIndex,
    this.snappedLat,
    this.snappedLon,
  });

  final bool accepted;
  final String reason;
  final int? segmentIndex;
  final double? segmentT;
  final double? distanceAlongRouteM;
  final double? snapDistanceM;
  final double? segmentBearingDeg;
  final double? courseDeltaDeg;

  /// First remaining vertex index in the original polyline (inclusive of the
  /// vertex after the snap segment start). Used with [navRerouteTrimCoordsAhead].
  final int? trimIndex;
  final double? snappedLat;
  final double? snappedLon;

  static const NavRerouteApplyProgressResult rejectedTooShort =
      NavRerouteApplyProgressResult(
        accepted: false,
        reason: 'route_too_short',
      );

  static const NavRerouteApplyProgressResult rejectedNoForward =
      NavRerouteApplyProgressResult(
        accepted: false,
        reason: 'no_forward_projection',
      );
}

class _SegCandidate {
  const _SegCandidate({
    required this.segmentIndex,
    required this.segmentT,
    required this.snapDistanceM,
    required this.distanceAlongRouteM,
    required this.segmentBearingDeg,
    required this.snappedLat,
    required this.snappedLon,
    required this.courseDeltaDeg,
  });

  final int segmentIndex;
  final double segmentT;
  final double snapDistanceM;
  final double distanceAlongRouteM;
  final double segmentBearingDeg;
  final double snappedLat;
  final double snappedLon;
  final double? courseDeltaDeg;
}

double navRerouteApplyHeadingDeltaDeg(double a, double b) {
  var d = (a - b).abs() % 360.0;
  if (d > 180.0) d = 360.0 - d;
  return d;
}

double navRerouteApplyBearingDeg({
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
}) {
  final lat1 = fromLat * math.pi / 180.0;
  final lat2 = toLat * math.pi / 180.0;
  final dLon = (toLon - fromLon) * math.pi / 180.0;
  final y = math.sin(dLon) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
}

double navRerouteApplyHaversineM({
  required double lat1,
  required double lon1,
  required double lat2,
  required double lon2,
}) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180.0;
  final p2 = lat2 * math.pi / 180.0;
  final dLat = (lat2 - lat1) * math.pi / 180.0;
  final dLon = (lon2 - lon1) * math.pi / 180.0;
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

List<_SegCandidate> _collectCandidates({
  required List<NavRerouteApplyLatLon> route,
  required double vehicleLat,
  required double vehicleLon,
  double? vehicleCourseDeg,
  required double maxCollectDistanceM,
}) {
  final out = <_SegCandidate>[];
  if (route.length < 2) return out;

  final refLatRad = vehicleLat * math.pi / 180.0;
  const metersPerDegLat = 111320.0;
  final metersPerDegLon =
      math.max(1.0, metersPerDegLat * math.cos(refLatRad));

  var cumulative = 0.0;
  for (var i = 0; i < route.length - 1; i++) {
    final a = route[i];
    final b = route[i + 1];
    final segmentM = navRerouteApplyHaversineM(
      lat1: a.lat,
      lon1: a.lon,
      lat2: b.lat,
      lon2: b.lon,
    );
    final ax = (a.lon - vehicleLon) * metersPerDegLon;
    final ay = (a.lat - vehicleLat) * metersPerDegLat;
    final bx = (b.lon - vehicleLon) * metersPerDegLon;
    final by = (b.lat - vehicleLat) * metersPerDegLat;
    final vx = bx - ax;
    final vy = by - ay;
    final len2 = vx * vx + vy * vy;
    final t =
        len2 <= 0 ? 0.0 : ((-ax * vx - ay * vy) / len2).clamp(0.0, 1.0);
    final px = ax + vx * t;
    final py = ay + vy * t;
    final dist = math.sqrt(px * px + py * py);
    if (dist <= maxCollectDistanceM) {
      final bearing = navRerouteApplyBearingDeg(
        fromLat: a.lat,
        fromLon: a.lon,
        toLat: b.lat,
        toLon: b.lon,
      );
      double? courseDelta;
      if (vehicleCourseDeg != null && vehicleCourseDeg.isFinite) {
        courseDelta =
            navRerouteApplyHeadingDeltaDeg(vehicleCourseDeg, bearing);
      }
      out.add(
        _SegCandidate(
          segmentIndex: i,
          segmentT: t,
          snapDistanceM: dist,
          distanceAlongRouteM: cumulative + segmentM * t,
          segmentBearingDeg: bearing,
          snappedLat: a.lat + (b.lat - a.lat) * t,
          snappedLon: a.lon + (b.lon - a.lon) * t,
          courseDeltaDeg: courseDelta,
        ),
      );
    }
    cumulative += segmentM;
  }
  return out;
}

/// Select a course-compatible forward projection at reroute apply time.
///
/// Rejects nearest-but-backward segments and packages whose only nearby
/// geometry lies behind current travel.
NavRerouteApplyProgressResult navRerouteSelectApplyProgress({
  required List<NavRerouteApplyLatLon> routeCoords,
  required double vehicleLat,
  required double vehicleLon,
  double? vehicleCourseDeg,
  double maxSnapDistanceM = 55.0,
  double maxCourseDeltaDeg = 95.0,
  double rejectBackwardCourseDeg = 120.0,
}) {
  if (routeCoords.length < 2) {
    return NavRerouteApplyProgressResult.rejectedTooShort;
  }
  if (![vehicleLat, vehicleLon].every((v) => v.isFinite)) {
    return const NavRerouteApplyProgressResult(
      accepted: false,
      reason: 'invalid_vehicle',
    );
  }

  final candidates = _collectCandidates(
    route: routeCoords,
    vehicleLat: vehicleLat,
    vehicleLon: vehicleLon,
    vehicleCourseDeg: vehicleCourseDeg,
    maxCollectDistanceM: math.max(maxSnapDistanceM, 80.0),
  );
  if (candidates.isEmpty) {
    return NavRerouteApplyProgressResult.rejectedNoForward;
  }

  final hasCourse =
      vehicleCourseDeg != null && vehicleCourseDeg.isFinite;

  // Prefer course-compatible candidates within snap budget.
  final forward = candidates.where((c) {
    if (c.snapDistanceM > maxSnapDistanceM) return false;
    if (!hasCourse) return true;
    final d = c.courseDeltaDeg;
    if (d == null) return true;
    return d <= maxCourseDeltaDeg;
  }).toList();

  _SegCandidate? best;
  if (forward.isNotEmpty) {
    forward.sort((a, b) {
      final byDist = a.snapDistanceM.compareTo(b.snapDistanceM);
      if (byDist != 0) return byDist;
      // Prefer further-along when equally near (avoids the behind stub).
      return b.distanceAlongRouteM.compareTo(a.distanceAlongRouteM);
    });
    best = forward.first;
  } else if (!hasCourse) {
    // No course: nearest within snap only.
    candidates.sort((a, b) => a.snapDistanceM.compareTo(b.snapDistanceM));
    final nearest = candidates.first;
    if (nearest.snapDistanceM <= maxSnapDistanceM) best = nearest;
  } else {
    // Course known but only backward/nearby incompatible segments exist.
    final backwardOnly = candidates.any(
      (c) =>
          c.snapDistanceM <= maxSnapDistanceM &&
          (c.courseDeltaDeg ?? 0) >= rejectBackwardCourseDeg,
    );
    if (backwardOnly) {
      return const NavRerouteApplyProgressResult(
        accepted: false,
        reason: 'only_backward_nearby',
      );
    }
    return NavRerouteApplyProgressResult.rejectedNoForward;
  }

  if (best == null) {
    return NavRerouteApplyProgressResult.rejectedNoForward;
  }

  // Explicit reject: nearest course is strongly reverse of travel.
  if (hasCourse &&
      best.courseDeltaDeg != null &&
      best.courseDeltaDeg! >= rejectBackwardCourseDeg) {
    return NavRerouteApplyProgressResult(
      accepted: false,
      reason: 'backward_segment',
      segmentIndex: best.segmentIndex,
      snapDistanceM: best.snapDistanceM,
      segmentBearingDeg: best.segmentBearingDeg,
      courseDeltaDeg: best.courseDeltaDeg,
      distanceAlongRouteM: best.distanceAlongRouteM,
    );
  }

  return NavRerouteApplyProgressResult(
    accepted: true,
    reason: 'forward_projection',
    segmentIndex: best.segmentIndex,
    segmentT: best.segmentT,
    distanceAlongRouteM: best.distanceAlongRouteM,
    snapDistanceM: best.snapDistanceM,
    segmentBearingDeg: best.segmentBearingDeg,
    courseDeltaDeg: best.courseDeltaDeg,
    trimIndex: best.segmentIndex,
    snappedLat: best.snappedLat,
    snappedLon: best.snappedLon,
  );
}

/// Trim route geometry so the active line begins at the snapped progress
/// point and continues to the destination.
List<NavRerouteApplyLatLon> navRerouteTrimCoordsAhead({
  required List<NavRerouteApplyLatLon> routeCoords,
  required NavRerouteApplyProgressResult progress,
}) {
  if (!progress.accepted ||
      progress.segmentIndex == null ||
      progress.snappedLat == null ||
      progress.snappedLon == null) {
    return List<NavRerouteApplyLatLon>.from(routeCoords);
  }
  if (routeCoords.length < 2) return List<NavRerouteApplyLatLon>.from(routeCoords);
  final i = progress.segmentIndex!.clamp(0, routeCoords.length - 2);
  final out = <NavRerouteApplyLatLon>[
    NavRerouteApplyLatLon(
      lat: progress.snappedLat!,
      lon: progress.snappedLon!,
    ),
    ...routeCoords.sublist(i + 1),
  ];
  if (out.length < 2) {
    out.add(routeCoords.last);
  }
  return out;
}

/// True when the candidate package can own the vehicle at apply time.
///
/// Replaces the old Euclidean-to-route-start check. When [vehicleCourseDeg]
/// is omitted, falls back to a near-start proximity gate for compatibility
/// with callers that only know the route start.
bool navRerouteApplyRouteIsAheadOfVehicle({
  required double vehicleLat,
  required double vehicleLon,
  required double routeStartLat,
  required double routeStartLon,
  double maxBehindM = 40.0,
  List<NavRerouteApplyLatLon>? routeCoords,
  double? vehicleCourseDeg,
}) {
  if (routeCoords != null && routeCoords.length >= 2) {
    final selected = navRerouteSelectApplyProgress(
      routeCoords: routeCoords,
      vehicleLat: vehicleLat,
      vehicleLon: vehicleLon,
      vehicleCourseDeg: vehicleCourseDeg,
    );
    return selected.accepted;
  }

  if (![vehicleLat, vehicleLon, routeStartLat, routeStartLon]
      .every((v) => v.isFinite)) {
    return false;
  }
  final distM = navRerouteApplyHaversineM(
    lat1: vehicleLat,
    lon1: vehicleLon,
    lat2: routeStartLat,
    lon2: routeStartLon,
  );
  return distM <= maxBehindM;
}

/// Bounded PII-safe diagnostic line for apply-time progress selection.
String formatNavRerouteApplyProgressDiag({
  required int generation,
  required NavRerouteApplyProgressResult progress,
  required double requestOriginDeltaM,
  String? writer,
}) {
  final seg = progress.segmentIndex?.toString() ?? '-';
  final along = progress.distanceAlongRouteM?.toStringAsFixed(0) ?? '-';
  final snap = progress.snapDistanceM?.toStringAsFixed(1) ?? '-';
  final course = progress.courseDeltaDeg?.toStringAsFixed(0) ?? '-';
  final bearing = progress.segmentBearingDeg?.toStringAsFixed(0) ?? '-';
  final trim = progress.trimIndex?.toString() ?? '-';
  final w = (writer ?? '-').trim();
  return 'gen=$generation accepted=${progress.accepted} '
      'reason=${progress.reason} seg=$seg alongM=$along snapM=$snap '
      'courseDelta=$course segBearing=$bearing trim=$trim '
      'originDeltaM=${requestOriginDeltaM.toStringAsFixed(0)} '
      'writer=${w.isEmpty ? '-' : w}';
}
