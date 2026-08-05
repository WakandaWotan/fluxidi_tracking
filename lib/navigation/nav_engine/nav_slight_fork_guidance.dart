// NAV-GUIDANCE-SLIGHT-FORK-AND-PRESENTATION-SMOOTHNESS
//
// Pure, deterministic enrichment when Mapbox omits a usable directional
// modifier at a genuine gentle fork. Never invents guidance on a single
// winding road, roundabout, merge-without-choice, or when an official
// turn/fork/roundabout/U-turn instruction already exists.

import 'dart:math' as math;

import '../driver_navigation_formatters.dart';
import '../driver_navigation_models.dart';

/// Bearing delta (degrees) considered a slight left/right branch.
const double kSlightForkMinDeltaDeg = 12.0;
const double kSlightForkMaxDeltaDeg = 45.0;

/// Absolute delta below this is treated as geometry noise.
const double kSlightForkNoiseDeg = 8.0;

enum SlightForkSide { left, right }

class SlightForkGuidance {
  final SlightForkSide side;
  final double deltaDeg;
  final String source;

  const SlightForkGuidance({
    required this.side,
    required this.deltaDeg,
    required this.source,
  });

  String get modifier =>
      side == SlightForkSide.left ? 'slight left' : 'slight right';

  String primaryText(DriverNavTranslate tr) {
    if (side == SlightForkSide.left) {
      return tr(
        nl: 'Hou licht links',
        en: 'Keep slight left',
        fr: 'Serrez légèrement à gauche',
        es: 'Mantén ligeramente a la izquierda',
      );
    }
    return tr(
      nl: 'Hou licht rechts',
      en: 'Keep slight right',
      fr: 'Serrez légèrement à droite',
      es: 'Mantén ligeramente a la derecha',
    );
  }
}

/// True when Mapbox already provides an official directional maneuver that
/// must win over synthesis.
bool hasOfficialDirectionalManeuver({
  required String type,
  required String modifier,
}) {
  final t = type.trim().toLowerCase();
  final m = modifier.trim().toLowerCase();
  if (t.contains('roundabout') ||
      t.contains('rotary') ||
      t.contains('exit roundabout') ||
      t.contains('exit rotary')) {
    return true;
  }
  if (t.contains('uturn') || m.contains('uturn') || m.contains('u-turn')) {
    return true;
  }
  if (t.contains('arrive') || t.contains('depart')) return true;
  // Explicit turn / fork / ramp / end of road with a left/right/slight/sharp.
  if (m.contains('slight left') ||
      m.contains('slight right') ||
      m.contains('sharp left') ||
      m.contains('sharp right') ||
      m == 'left' ||
      m == 'right' ||
      (m.contains('left') && t.contains('turn')) ||
      (m.contains('right') && t.contains('turn'))) {
    return true;
  }
  if (t.contains('turn') && (m.contains('left') || m.contains('right'))) {
    return true;
  }
  if (t.contains('fork') && (m.contains('left') || m.contains('right'))) {
    return true;
  }
  if ((t.contains('on ramp') ||
          t.contains('off ramp') ||
          t.contains('ramp')) &&
      (m.contains('left') || m.contains('right'))) {
    return true;
  }
  if (t.contains('end of road') &&
      (m.contains('left') || m.contains('right'))) {
    return true;
  }
  return false;
}

double normalizeBearingDeltaDeg(double fromDeg, double toDeg) {
  var d = toDeg - fromDeg;
  while (d > 180.0) {
    d -= 360.0;
  }
  while (d < -180.0) {
    d += 360.0;
  }
  return d;
}

double bearingBetween(DriverLonLat a, DriverLonLat b) {
  final lat1 = a.lat * math.pi / 180.0;
  final lat2 = b.lat * math.pi / 180.0;
  final dLon = (b.lon - a.lon) * math.pi / 180.0;
  final y = math.sin(dLon) * math.cos(lat2);
  final x =
      math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
  final brng = math.atan2(y, x) * 180.0 / math.pi;
  return (brng + 360.0) % 360.0;
}

SlightForkSide? sideFromSignedDelta(double signedDeltaDeg) {
  final abs = signedDeltaDeg.abs();
  if (abs < kSlightForkMinDeltaDeg || abs > kSlightForkMaxDeltaDeg) {
    return null;
  }
  return signedDeltaDeg < 0 ? SlightForkSide.left : SlightForkSide.right;
}

/// Prefer intersection bearings/entry when present.
SlightForkGuidance? synthesizeSlightForkFromIntersection(
  DriverNavIntersection intersection,
) {
  final bearings = intersection.bearings;
  final entry = intersection.entry;
  final inIndex = intersection.inIndex;
  final outIndex = intersection.outIndex;
  if (bearings.length < 2 || inIndex == null || outIndex == null) return null;
  if (inIndex < 0 ||
      outIndex < 0 ||
      inIndex >= bearings.length ||
      outIndex >= bearings.length) {
    return null;
  }
  if (inIndex == outIndex) return null;

  // Count traversable outgoing choices excluding the inbound reverse.
  var traversableOut = 0;
  for (var i = 0; i < bearings.length; i++) {
    if (i == inIndex) continue;
    final allowed = i < entry.length ? entry[i] : true;
    if (allowed) traversableOut += 1;
  }
  if (traversableOut < 2) return null;

  final inBearing = bearings[inIndex];
  // Travel direction into the junction is opposite of the inbound bearing arm.
  final incomingTravel = (inBearing + 180.0) % 360.0;
  final outBearing = bearings[outIndex];
  final delta = normalizeBearingDeltaDeg(incomingTravel, outBearing);
  if (delta.abs() < kSlightForkNoiseDeg) return null;
  final side = sideFromSignedDelta(delta);
  if (side == null) return null;

  // Reject when another outbound choice is nearly collinear with selected
  // (not a distinguishable branch) — already covered by min/max band.
  return SlightForkGuidance(
    side: side,
    deltaDeg: delta.abs(),
    source: 'intersection_bearings',
  );
}

/// Bounded geometry fallback: compare route bearing into the step vs leaving it.
SlightForkGuidance? synthesizeSlightForkFromRouteGeometry({
  required List<DriverLonLat> routeCoords,
  required double maneuverDistanceAlongRouteM,
  double lookBackM = 28.0,
  double lookAheadM = 28.0,
}) {
  if (routeCoords.length < 3) return null;
  DriverLonLat? pointAt(double alongM) {
    var remaining = alongM.clamp(0.0, double.infinity);
    var traveled = 0.0;
    for (var i = 0; i < routeCoords.length - 1; i++) {
      final a = routeCoords[i];
      final b = routeCoords[i + 1];
      final seg = _meters(a, b);
      if (traveled + seg >= remaining) {
        final t = seg <= 0 ? 0.0 : (remaining - traveled) / seg;
        return DriverLonLat(
          a.lon + (b.lon - a.lon) * t,
          a.lat + (b.lat - a.lat) * t,
        );
      }
      traveled += seg;
    }
    return routeCoords.last;
  }

  final at = pointAt(maneuverDistanceAlongRouteM);
  final before = pointAt(maneuverDistanceAlongRouteM - lookBackM);
  final after = pointAt(maneuverDistanceAlongRouteM + lookAheadM);
  if (at == null || before == null || after == null) return null;
  final inBrng = bearingBetween(before, at);
  final outBrng = bearingBetween(at, after);
  final delta = normalizeBearingDeltaDeg(inBrng, outBrng);
  if (delta.abs() < kSlightForkNoiseDeg) return null;
  final side = sideFromSignedDelta(delta);
  if (side == null) return null;
  return SlightForkGuidance(
    side: side,
    deltaDeg: delta.abs(),
    source: 'route_geometry',
  );
}

/// Full decision for a step. Returns null when synthesis must not run.
SlightForkGuidance? resolveSlightForkGuidance({
  required DriverNavStep step,
  List<DriverLonLat> routeCoords = const <DriverLonLat>[],
  bool allowGeometryFallback = true,
}) {
  final type = step.type.trim().toLowerCase();
  final modifier = step.modifier.trim().toLowerCase();

  if (hasOfficialDirectionalManeuver(type: type, modifier: modifier)) {
    return null;
  }
  if (type.contains('roundabout') || type.contains('rotary')) return null;
  if (type.contains('merge') && !type.contains('fork')) {
    // Merge with no driver choice — do not invent a fork.
    return null;
  }
  if (type.contains('arrive') || type.contains('depart')) return null;
  if (type.contains('notification') && modifier.isEmpty) {
    // Continue; may still be a fork without modifier — intersection decides.
  }

  // Prefer first intersection with usable out/in.
  for (final ix in step.intersections) {
    final fromIx = synthesizeSlightForkFromIntersection(ix);
    if (fromIx != null) return fromIx;
  }

  if (!allowGeometryFallback) return null;
  // Geometry fallback only when step type hints at a choice (fork/turn/new
  // name) OR intersections existed but lacked usable indices — never for
  // plain "continue" on a single road with zero intersections.
  final hintsChoice =
      type.contains('fork') ||
      type.contains('turn') ||
      type.contains('new name') ||
      type.contains('continue') && step.intersections.isNotEmpty;
  if (!hintsChoice && step.intersections.isEmpty) return null;

  return synthesizeSlightForkFromRouteGeometry(
    routeCoords: routeCoords,
    maneuverDistanceAlongRouteM: step.distanceAlongRouteM,
  );
}

double _meters(DriverLonLat a, DriverLonLat b) {
  const r = 6371000.0;
  final dLat = (b.lat - a.lat) * math.pi / 180.0;
  final dLon = (b.lon - a.lon) * math.pi / 180.0;
  final lat1 = a.lat * math.pi / 180.0;
  final lat2 = b.lat * math.pi / 180.0;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
}

/// Presentation coalesce decision for progress polyline updates.
enum NavRouteLineProgressWriteKind {
  /// Skip — stale ownership or no material progress.
  skip,

  /// Update existing annotation geometries in place.
  updateInPlace,

  /// Full create+replace (first draw, missing handles, or forced replace).
  recreate,
}

class NavRouteLineProgressWriteDecision {
  final NavRouteLineProgressWriteKind kind;
  final String reason;

  const NavRouteLineProgressWriteDecision({
    required this.kind,
    required this.reason,
  });
}

/// Latest-wins / coalesce gate for progress-trim route presentation.
NavRouteLineProgressWriteDecision decideNavRouteLineProgressWrite({
  required int capturedRenderEpoch,
  required int currentRenderEpoch,
  required bool hasActiveLineAnnotations,
  required bool forceRecreate,
  required bool sameRouteVersion,
  required double progressDeltaM,
  required int msSinceLastWrite,
  double minProgressDeltaM = 12.0,
  int minIntervalMs = 320,
}) {
  if (capturedRenderEpoch != currentRenderEpoch) {
    return const NavRouteLineProgressWriteDecision(
      kind: NavRouteLineProgressWriteKind.skip,
      reason: 'stale_render_epoch',
    );
  }
  if (forceRecreate || !sameRouteVersion) {
    return const NavRouteLineProgressWriteDecision(
      kind: NavRouteLineProgressWriteKind.recreate,
      reason: 'force_or_route_version_change',
    );
  }
  if (!hasActiveLineAnnotations) {
    return const NavRouteLineProgressWriteDecision(
      kind: NavRouteLineProgressWriteKind.recreate,
      reason: 'missing_annotations',
    );
  }
  if (progressDeltaM < minProgressDeltaM && msSinceLastWrite < minIntervalMs) {
    return const NavRouteLineProgressWriteDecision(
      kind: NavRouteLineProgressWriteKind.skip,
      reason: 'coalesced',
    );
  }
  return const NavRouteLineProgressWriteDecision(
    kind: NavRouteLineProgressWriteKind.updateInPlace,
    reason: 'progress_trim',
  );
}
