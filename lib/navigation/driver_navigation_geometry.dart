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
