// NAV-ROUNDABOUT-LANE-CLARITY-P0-2026-07-31
//
// Pure geometry helpers for forward-direction chevron placement along a
// route polyline around a roundabout. Emits a bounded number of small
// V-shaped polylines (2 short segments meeting at a "chevron tip") that
// follow the underlying route geometry:
//   * one chevron BEFORE the roundabout (approach)
//   * a small number of chevrons ON the curved roundabout segment (only
//     where the segment is long enough for a chevron to fit without
//     overlapping)
//   * one chevron AT the chosen exit (after the roundabout maneuver)
//
// Never touches the vehicle marker, never mutates camera / zoom, never
// creates chevrons outside the immediate roundabout maneuver. Empty return
// on missing / uncertain input.
//
// All units: meters (great-circle) for spacing, degrees (lon/lat) for
// coordinates. The equirectangular projection used for spacing is a fine
// approximation over the ~100 m envelope of a roundabout — chevrons are a
// visual guide, not a survey grade artefact.

import 'dart:math' as math;

/// A single chevron rendered as a 3-point polyline: [left, tip, right].
/// Forward direction is from the mid-point of `left`–`right` toward `tip`.
class RoundaboutChevron {
  const RoundaboutChevron({
    required this.left,
    required this.tip,
    required this.right,
    required this.bearingDegrees,
    required this.role,
  });

  /// One of the two flanks (screen-left of the tip w.r.t. `bearingDegrees`).
  final RoundaboutChevronPoint left;

  /// The tip of the chevron; points in `bearingDegrees` direction.
  final RoundaboutChevronPoint tip;

  /// Other flank.
  final RoundaboutChevronPoint right;

  /// Great-circle-ish bearing at the tip (degrees, 0=north, clockwise).
  final double bearingDegrees;

  final RoundaboutChevronRole role;

  List<RoundaboutChevronPoint> get points => [left, tip, right];
}

enum RoundaboutChevronRole { approach, insideRing, exit }

/// A single (lon, lat) coordinate pair used by chevron polylines.
class RoundaboutChevronPoint {
  const RoundaboutChevronPoint(this.lon, this.lat);
  final double lon;
  final double lat;
}

/// Computes chevrons for a roundabout maneuver window on a route.
///
/// Inputs:
///   * [routeCoordinates] — full route geometry in lon/lat order.
///   * [roundaboutStepStartIndex] / [roundaboutStepEndIndex] — inclusive
///     indices into [routeCoordinates] bracketing the roundabout step's
///     polyline vertices. Both must be inside `[0, routeCoordinates.length)`
///     and start < end. When missing / inconsistent the function returns an
///     empty list.
///   * [chevronSizeMeters] — width of the "V" between the two flanks along
///     the polyline (chevron feels this size at map scale). Default: 6 m.
///   * [maxChevronsOnRing] — safety cap for chevrons drawn ON the curved
///     ring segment. Default: 4.
///   * [minSpacingMeters] — minimum along-track spacing between adjacent
///     chevrons. Prevents overlap on very short roundabouts. Default: 8 m.
///
/// Returns an empty list when the roundabout step is too short (< 2×
/// [chevronSizeMeters]) or when the input geometry is malformed. This is
/// the safe default the caller relies on to know "no chevrons should be
/// rendered right now".
List<RoundaboutChevron> computeRoundaboutChevrons({
  required List<RoundaboutChevronPoint> routeCoordinates,
  required int roundaboutStepStartIndex,
  required int roundaboutStepEndIndex,
  double chevronSizeMeters = 6.0,
  int maxChevronsOnRing = 4,
  double minSpacingMeters = 8.0,
}) {
  if (routeCoordinates.length < 2) return const [];
  if (roundaboutStepStartIndex < 0 ||
      roundaboutStepEndIndex >= routeCoordinates.length ||
      roundaboutStepStartIndex >= roundaboutStepEndIndex) {
    return const [];
  }
  if (chevronSizeMeters <= 0.5 || maxChevronsOnRing < 1) return const [];

  // Cumulative distance along the whole route + per-segment bearings.
  final cum = _cumulativeMeters(routeCoordinates);
  if (cum.isEmpty) return const [];

  final startCum = cum[roundaboutStepStartIndex];
  final endCum = cum[roundaboutStepEndIndex];
  final ringLength = endCum - startCum;
  if (ringLength < chevronSizeMeters * 2) return const [];

  final chevrons = <RoundaboutChevron>[];

  // 1) Approach chevron — one chevron-size before ring entry, but only when
  //    there is enough approach length available.
  final approachOffset = chevronSizeMeters * 1.2;
  final approachCum = startCum - approachOffset;
  if (approachCum >= chevronSizeMeters * 0.5) {
    final built = _buildChevronAt(
      routeCoordinates: routeCoordinates,
      cum: cum,
      targetMeters: approachCum,
      widthMeters: chevronSizeMeters,
      role: RoundaboutChevronRole.approach,
    );
    if (built != null) chevrons.add(built);
  }

  // 2) Chevrons on the ring — sample up to `maxChevronsOnRing`, spaced
  //    evenly, but never closer than `minSpacingMeters`.
  final safeRing = ringLength - chevronSizeMeters * 2.0;
  int ringChevronCount = safeRing <= 0
      ? 0
      : math
          .max(
            1,
            math.min(
              maxChevronsOnRing,
              (safeRing / math.max(minSpacingMeters, chevronSizeMeters))
                  .floor(),
            ),
          )
          .toInt();
  if (ringChevronCount > 0) {
    for (int i = 1; i <= ringChevronCount; i++) {
      final t = i / (ringChevronCount + 1);
      final targetCum = startCum + chevronSizeMeters + safeRing * t;
      final built = _buildChevronAt(
        routeCoordinates: routeCoordinates,
        cum: cum,
        targetMeters: targetCum,
        widthMeters: chevronSizeMeters,
        role: RoundaboutChevronRole.insideRing,
      );
      if (built != null) chevrons.add(built);
    }
  }

  // 3) Exit chevron — one chevron-size past the end of the ring, i.e. on
  //    the chosen exit road.
  final exitOffset = chevronSizeMeters * 1.2;
  final exitCum = endCum + exitOffset;
  if (exitCum <= cum.last - chevronSizeMeters * 0.5) {
    final built = _buildChevronAt(
      routeCoordinates: routeCoordinates,
      cum: cum,
      targetMeters: exitCum,
      widthMeters: chevronSizeMeters,
      role: RoundaboutChevronRole.exit,
    );
    if (built != null) chevrons.add(built);
  }

  return chevrons;
}

/// Cumulative distance in meters at each vertex; length == coords.length.
List<double> _cumulativeMeters(List<RoundaboutChevronPoint> coords) {
  final out = List<double>.filled(coords.length, 0.0);
  for (int i = 1; i < coords.length; i++) {
    out[i] = out[i - 1] +
        _haversineMeters(
          coords[i - 1].lat,
          coords[i - 1].lon,
          coords[i].lat,
          coords[i].lon,
        );
  }
  return out;
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const earthRadius = 6371000.0;
  final dLat = _deg2rad(lat2 - lat1);
  final dLon = _deg2rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_deg2rad(lat1)) *
          math.cos(_deg2rad(lat2)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadius * c;
}

double _deg2rad(double d) => d * math.pi / 180.0;
double _rad2deg(double r) => r * 180.0 / math.pi;

RoundaboutChevron? _buildChevronAt({
  required List<RoundaboutChevronPoint> routeCoordinates,
  required List<double> cum,
  required double targetMeters,
  required double widthMeters,
  required RoundaboutChevronRole role,
}) {
  if (targetMeters <= 0 || targetMeters >= cum.last) return null;
  int seg = 0;
  for (int i = 1; i < cum.length; i++) {
    if (cum[i] >= targetMeters) {
      seg = i - 1;
      break;
    }
  }
  final segLen = cum[seg + 1] - cum[seg];
  if (segLen <= 0) return null;
  final t = (targetMeters - cum[seg]) / segLen;
  final a = routeCoordinates[seg];
  final b = routeCoordinates[seg + 1];
  final tipLon = a.lon + (b.lon - a.lon) * t;
  final tipLat = a.lat + (b.lat - a.lat) * t;
  final bearing = _bearingDegrees(a.lat, a.lon, b.lat, b.lon);

  // Chevron flanks: step BACKWARDS along the route from the tip by
  // widthMeters/2 in each direction (± bearing perpendicular), so the "V"
  // faces forward.
  //
  // Practical: place flanks along the SAME direction the polyline is going
  // but a few meters *before* the tip, offset laterally. The offset is
  // small enough (widthMeters/2 ≈ 3 m at default) that chevrons are visible
  // at driving zoom without ever bleeding outside the roundabout lane.
  final backDistance = widthMeters * 0.55;
  final lateralDistance = widthMeters * 0.55;
  final backOffset = _offsetByBearingMeters(
    tipLat: tipLat,
    tipLon: tipLon,
    distanceMeters: -backDistance,
    bearingDegrees: bearing,
  );
  final leftFlank = _offsetByBearingMeters(
    tipLat: backOffset.lat,
    tipLon: backOffset.lon,
    distanceMeters: lateralDistance,
    bearingDegrees: bearing - 90,
  );
  final rightFlank = _offsetByBearingMeters(
    tipLat: backOffset.lat,
    tipLon: backOffset.lon,
    distanceMeters: lateralDistance,
    bearingDegrees: bearing + 90,
  );

  return RoundaboutChevron(
    left: leftFlank,
    tip: RoundaboutChevronPoint(tipLon, tipLat),
    right: rightFlank,
    bearingDegrees: bearing,
    role: role,
  );
}

double _bearingDegrees(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _deg2rad(lat1);
  final phi2 = _deg2rad(lat2);
  final dLon = _deg2rad(lon2 - lon1);
  final y = math.sin(dLon) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
  final theta = math.atan2(y, x);
  return (_rad2deg(theta) + 360) % 360;
}

RoundaboutChevronPoint _offsetByBearingMeters({
  required double tipLat,
  required double tipLon,
  required double distanceMeters,
  required double bearingDegrees,
}) {
  const earthRadius = 6371000.0;
  final bearingRad = _deg2rad(bearingDegrees);
  final phi1 = _deg2rad(tipLat);
  final lambda1 = _deg2rad(tipLon);
  final angDist = distanceMeters / earthRadius;
  final phi2 = math.asin(
    math.sin(phi1) * math.cos(angDist) +
        math.cos(phi1) * math.sin(angDist) * math.cos(bearingRad),
  );
  final lambda2 = lambda1 +
      math.atan2(
        math.sin(bearingRad) * math.sin(angDist) * math.cos(phi1),
        math.cos(angDist) - math.sin(phi1) * math.sin(phi2),
      );
  return RoundaboutChevronPoint(_rad2deg(lambda2), _rad2deg(phi2));
}
