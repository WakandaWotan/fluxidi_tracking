import 'dart:math' as math;

import 'package:geolocator/geolocator.dart' as geo;

import 'driver_navigation_models.dart';

double driverMetersBetween(DriverLonLat a, DriverLonLat b) {
  return geo.Geolocator.distanceBetween(a.lat, a.lon, b.lat, b.lon);
}

DriverRouteSnap? driverSnapToRouteOn(
  List<DriverLonLat> routeCoords,
  DriverLonLat raw,
) {
  if (routeCoords.length < 2) return null;
  final refLatRad = raw.lat * math.pi / 180.0;
  const metersPerDegLat = 111320.0;
  final metersPerDegLon = math.max(1.0, metersPerDegLat * math.cos(refLatRad));

  var bestDistance = double.infinity;
  var bestAlong = 0.0;
  var bestSegment = 0;
  var bestT = 0.0;
  DriverLonLat? bestPoint;
  var cumulative = 0.0;

  for (var i = 0; i < routeCoords.length - 1; i++) {
    final a = routeCoords[i];
    final b = routeCoords[i + 1];
    final ax = (a.lon - raw.lon) * metersPerDegLon;
    final ay = (a.lat - raw.lat) * metersPerDegLat;
    final bx = (b.lon - raw.lon) * metersPerDegLon;
    final by = (b.lat - raw.lat) * metersPerDegLat;
    final vx = bx - ax;
    final vy = by - ay;
    final len2 = vx * vx + vy * vy;
    final t = len2 <= 0 ? 0.0 : ((-ax * vx - ay * vy) / len2).clamp(0.0, 1.0);
    final px = ax + vx * t;
    final py = ay + vy * t;
    final approxDistance = math.sqrt(px * px + py * py);
    final segmentMeters = driverMetersBetween(a, b);
    if (approxDistance < bestDistance) {
      bestDistance = approxDistance;
      bestAlong = cumulative + segmentMeters * t;
      bestSegment = i;
      bestT = t;
      bestPoint = DriverLonLat(
        a.lon + (b.lon - a.lon) * t,
        a.lat + (b.lat - a.lat) * t,
      );
    }
    cumulative += segmentMeters;
  }

  final point = bestPoint;
  if (point == null || !bestDistance.isFinite) return null;
  return DriverRouteSnap(
    point: point,
    distanceFromRouteM: bestDistance,
    distanceAlongRouteM: bestAlong,
    segmentIndex: bestSegment,
    segmentT: bestT,
  );
}

double driverDistanceAlongRouteForCoords(
  List<DriverLonLat> routeCoords,
  DriverLonLat point,
) {
  return driverSnapToRouteOn(routeCoords, point)?.distanceAlongRouteM ?? 0.0;
}

List<DriverLonLat> driverRouteCoordsFromSnap(
  List<DriverLonLat> routeCoords,
  DriverRouteSnap snap,
) {
  if (routeCoords.length < 2) return routeCoords;
  final i = snap.segmentIndex.clamp(0, routeCoords.length - 2);
  final out = <DriverLonLat>[snap.point, ...routeCoords.sublist(i + 1)];
  if (out.length < 2) {
    out.add(routeCoords.last);
  }
  return out;
}

/// NAV-OS-R2: completed route geometry from route start up to the snap point.
List<DriverLonLat> driverRouteCoordsUpToSnap(
  List<DriverLonLat> routeCoords,
  DriverRouteSnap snap,
) {
  if (routeCoords.length < 2) return const <DriverLonLat>[];
  final i = snap.segmentIndex.clamp(0, routeCoords.length - 2);
  final out = <DriverLonLat>[...routeCoords.sublist(0, i + 1), snap.point];
  if (out.length < 2) return const <DriverLonLat>[];
  return out;
}

/// NAV-OS-R2: total polyline length in meters.
double driverRouteLengthMeters(List<DriverLonLat> routeCoords) {
  var total = 0.0;
  for (var i = 0; i < routeCoords.length - 1; i++) {
    total += driverMetersBetween(routeCoords[i], routeCoords[i + 1]);
  }
  return total;
}

/// NAV-OS-R2: forward-looking route bearing from the snapped position toward
/// a point [lookaheadM] meters ahead along the polyline. Walking strictly in
/// the direction of increasing distance-along-route guarantees the bearing can
/// never point down a previous/backward segment.
double? driverForwardRouteBearing(
  List<DriverLonLat> routeCoords, {
  required int segmentIndex,
  required double snappedLat,
  required double snappedLon,
  double lookaheadM = 12.0,
}) {
  if (routeCoords.length < 2) return null;
  final i = segmentIndex.clamp(0, routeCoords.length - 2);

  var curLat = snappedLat;
  var curLon = snappedLon;
  var need = lookaheadM;
  for (var k = i + 1; k < routeCoords.length; k++) {
    final next = routeCoords[k];
    final d = driverMetersBetween(
      DriverLonLat(curLon, curLat),
      DriverLonLat(next.lon, next.lat),
    );
    if (d >= need && d > 0.5) {
      final t = need / d;
      final targetLat = curLat + (next.lat - curLat) * t;
      final targetLon = curLon + (next.lon - curLon) * t;
      final fromTarget = driverBearingFromPoints(
        snappedLat,
        snappedLon,
        targetLat,
        targetLon,
      );
      if (fromTarget != null) return fromTarget;
      return driverBearingFromPoints(curLat, curLon, next.lat, next.lon);
    }
    need -= d;
    curLat = next.lat;
    curLon = next.lon;
  }
  // Near route end: bearing toward the final point if it is meaningful.
  final last = routeCoords.last;
  final distToEnd = driverMetersBetween(
    DriverLonLat(snappedLon, snappedLat),
    DriverLonLat(last.lon, last.lat),
  );
  if (distToEnd > 1.0) {
    return driverBearingFromPoints(snappedLat, snappedLon, last.lat, last.lon);
  }
  final a = routeCoords[routeCoords.length - 2];
  return driverBearingFromPoints(a.lat, a.lon, last.lat, last.lon);
}

/// NAV-PRES-3B: geographic point [lookaheadM] meters ahead along the route
/// polyline from the snapped position (same walk as [driverForwardRouteBearing]).
DriverLonLat? driverForwardRouteLookaheadPoint(
  List<DriverLonLat> routeCoords, {
  required int segmentIndex,
  required double snappedLat,
  required double snappedLon,
  double lookaheadM = 45.0,
}) {
  if (routeCoords.length < 2 || lookaheadM <= 0) return null;
  final i = segmentIndex.clamp(0, routeCoords.length - 2);

  var curLat = snappedLat;
  var curLon = snappedLon;
  var need = lookaheadM;
  for (var k = i + 1; k < routeCoords.length; k++) {
    final next = routeCoords[k];
    final d = driverMetersBetween(
      DriverLonLat(curLon, curLat),
      DriverLonLat(next.lon, next.lat),
    );
    if (d >= need && d > 0.5) {
      final t = need / d;
      return DriverLonLat(
        curLon + (next.lon - curLon) * t,
        curLat + (next.lat - curLat) * t,
      );
    }
    need -= d;
    curLat = next.lat;
    curLon = next.lon;
  }
  final last = routeCoords.last;
  final distToEnd = driverMetersBetween(
    DriverLonLat(snappedLon, snappedLat),
    DriverLonLat(last.lon, last.lat),
  );
  if (distToEnd > 1.0) {
    return last;
  }
  return DriverLonLat(snappedLon, snappedLat);
}

/// NAV-PRES-3B: offset a point [distanceM] along [bearingDeg] (0 = north).
DriverLonLat driverPointAheadOnBearing({
  required double lat,
  required double lon,
  required double bearingDeg,
  required double distanceM,
}) {
  if (distanceM <= 0) {
    return DriverLonLat(lon, lat);
  }
  const earthRadiusM = 6378137.0;
  final bearingRad = bearingDeg * math.pi / 180.0;
  final latRad = lat * math.pi / 180.0;
  final lonRad = lon * math.pi / 180.0;
  final angularDist = distanceM / earthRadiusM;
  final lat2Rad = math.asin(
    math.sin(latRad) * math.cos(angularDist) +
        math.cos(latRad) * math.sin(angularDist) * math.cos(bearingRad),
  );
  final lon2Rad =
      lonRad +
      math.atan2(
        math.sin(bearingRad) * math.sin(angularDist) * math.cos(latRad),
        math.cos(angularDist) - math.sin(latRad) * math.sin(lat2Rad),
      );
  return DriverLonLat(
    lon2Rad * 180.0 / math.pi,
    lat2Rad * 180.0 / math.pi,
  );
}

/// NAV-PRES-3B: move [current] toward [target] by at most [maxStepM] meters.
DriverLonLat driverSmoothGeodesicToward({
  required DriverLonLat current,
  required DriverLonLat target,
  required double maxStepM,
}) {
  if (maxStepM <= 0) return current;
  final distanceM = driverMetersBetween(current, target);
  if (!distanceM.isFinite || distanceM <= maxStepM) {
    return target;
  }
  final bearing = driverBearingFromPoints(
    current.lat,
    current.lon,
    target.lat,
    target.lon,
  );
  if (bearing == null) return target;
  return driverPointAheadOnBearing(
    lat: current.lat,
    lon: current.lon,
    bearingDeg: bearing,
    distanceM: maxStepM,
  );
}

double? driverBearingFromPoints(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const degToRad = math.pi / 180.0;
  const radToDeg = 180.0 / math.pi;
  final dLon = (lon2 - lon1) * degToRad;
  final y = math.sin(dLon) * math.cos(lat2 * degToRad);
  final x =
      math.cos(lat1 * degToRad) * math.sin(lat2 * degToRad) -
      math.sin(lat1 * degToRad) * math.cos(lat2 * degToRad) * math.cos(dLon);
  if (!x.isFinite || !y.isFinite) return null;
  final brng = math.atan2(y, x) * radToDeg;
  return (brng + 360.0) % 360.0;
}

double? driverRouteBearingAtSnap(
  List<DriverLonLat> routeCoords,
  DriverRouteSnap? snap,
) {
  if (snap == null || routeCoords.length < 2) return null;
  final i = snap.segmentIndex.clamp(0, routeCoords.length - 2);
  final a = routeCoords[i];
  final b = routeCoords[i + 1];
  return driverBearingFromPoints(a.lat, a.lon, b.lat, b.lon);
}
