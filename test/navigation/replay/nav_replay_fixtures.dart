// NAV-R12-F: synthetic replay fixtures for the driver navigation engine.
//
// All coordinates are synthetic (Brussels-area origin) — no real ride data.
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';

import 'nav_replay_sample.dart';

/// A named fixture: a route polyline plus a GPS sample trace.
class NavReplayFixture {
  final String name;
  final List<NavRoutePoint> routePoints;
  final List<NavReplaySample> samples;

  const NavReplayFixture({
    required this.name,
    required this.routePoints,
    required this.samples,
  });
}

class NavReplayFixtures {
  static const double _originLat = 50.8500;
  static const double _originLon = 4.3500;
  static final DateTime _t0 = DateTime.utc(2026, 7, 7, 10, 0, 0);

  /// Straight street heading due north from the origin, 2 km, 50 m spacing.
  static List<NavRoutePoint> straightNorthRoute() {
    final points = <NavRoutePoint>[];
    for (var m = 0.0; m <= 2000.0; m += 50.0) {
      final p = NavReplayDiagnosticsImport.offsetMeters(
        latitude: _originLat,
        longitude: _originLon,
        bearingDeg: 0.0,
        distanceM: m,
      );
      points.add(NavRoutePoint(latitude: p.latitude, longitude: p.longitude));
    }
    return points;
  }

  /// Generates 1 Hz samples driving along [bearingDeg] from a start point.
  static List<NavReplaySample> _drive({
    required double startLat,
    required double startLon,
    required double bearingDeg,
    required double speedKmh,
    required int count,
    required DateTime startTime,
    double? headingDeg,
    double accuracyM = 8.0,
    String? expectedRouteState,
  }) {
    final samples = <NavReplaySample>[];
    var lat = startLat;
    var lon = startLon;
    final stepM = speedKmh / 3.6;
    for (var i = 0; i < count; i++) {
      if (i > 0) {
        final moved = NavReplayDiagnosticsImport.offsetMeters(
          latitude: lat,
          longitude: lon,
          bearingDeg: bearingDeg,
          distanceM: stepM,
        );
        lat = moved.latitude;
        lon = moved.longitude;
      }
      samples.add(
        NavReplaySample(
          timestamp: startTime.add(Duration(seconds: i)),
          latitude: lat,
          longitude: lon,
          speedKmh: speedKmh,
          headingDeg: headingDeg ?? bearingDeg,
          accuracyM: accuracyM,
          expectedRouteState: expectedRouteState,
        ),
      );
    }
    return samples;
  }

  static ({double latitude, double longitude}) _alongRoute(double meters) {
    return NavReplayDiagnosticsImport.offsetMeters(
      latitude: _originLat,
      longitude: _originLon,
      bearingDeg: 0.0,
      distanceM: meters,
    );
  }

  /// A. Opposite-direction start on the same street: the planned route runs
  /// north; the driver is mid-route and departs due south along the exact
  /// same polyline, so snap distance stays near zero the whole time.
  static NavReplayFixture oppositeDirectionStart() {
    final start = _alongRoute(1000.0);
    final samples = _drive(
      startLat: start.latitude,
      startLon: start.longitude,
      bearingDeg: 180.0,
      speedKmh: 30.0,
      count: 12,
      startTime: _t0,
      expectedRouteState: 'route_deviation',
    );
    return NavReplayFixture(
      name: 'A_opposite_direction_start',
      routePoints: straightNorthRoute(),
      samples: samples,
    );
  }

  /// B. Normal on-route driving north with mild heading jitter.
  static NavReplayFixture normalOnRoute() {
    final base = _drive(
      startLat: _originLat,
      startLon: _originLon,
      bearingDeg: 0.0,
      speedKmh: 40.0,
      count: 30,
      startTime: _t0,
      expectedRouteState: 'on_route',
    );
    // Add deterministic +/-5 degree heading jitter without leaving the road.
    final jittered = <NavReplaySample>[];
    for (var i = 0; i < base.length; i++) {
      final s = base[i];
      final jitter = (i % 3 - 1) * 5.0; // -5, 0, +5 cycling
      jittered.add(
        NavReplaySample(
          timestamp: s.timestamp,
          latitude: s.latitude,
          longitude: s.longitude,
          speedKmh: s.speedKmh,
          headingDeg: (s.headingDeg! + jitter + 360.0) % 360.0,
          accuracyM: s.accuracyM,
          expectedRouteState: s.expectedRouteState,
        ),
      );
    }
    return NavReplayFixture(
      name: 'B_normal_on_route',
      routePoints: straightNorthRoute(),
      samples: jittered,
    );
  }

  /// C. U-turn/backtrack: north for 8 s, a 3-sample turnaround at moderate
  /// speed, then back south along the same street.
  static NavReplayFixture uTurnBacktrack() {
    final north = _drive(
      startLat: _originLat,
      startLon: _originLon,
      bearingDeg: 0.0,
      speedKmh: 30.0,
      count: 8,
      startTime: _t0,
      expectedRouteState: 'on_route',
    );
    final turnStart = north.last;
    // Turnaround: heading sweeps 60 -> 120 -> 180 while barely moving east.
    final turn = <NavReplaySample>[];
    var lat = turnStart.latitude;
    var lon = turnStart.longitude;
    final headings = <double>[60.0, 120.0, 180.0];
    for (var i = 0; i < headings.length; i++) {
      final moved = NavReplayDiagnosticsImport.offsetMeters(
        latitude: lat,
        longitude: lon,
        bearingDeg: headings[i],
        distanceM: 3.0,
      );
      lat = moved.latitude;
      lon = moved.longitude;
      turn.add(
        NavReplaySample(
          timestamp: turnStart.timestamp.add(Duration(seconds: i + 1)),
          latitude: lat,
          longitude: lon,
          speedKmh: 11.0,
          headingDeg: headings[i],
          accuracyM: 8.0,
          expectedRouteState: 'uturn',
        ),
      );
    }
    final south = _drive(
      startLat: lat,
      startLon: lon,
      bearingDeg: 180.0,
      speedKmh: 30.0,
      count: 10,
      startTime: turn.last.timestamp.add(const Duration(seconds: 1)),
      expectedRouteState: 'route_deviation',
    );
    return NavReplayFixture(
      name: 'C_uturn_backtrack',
      routePoints: straightNorthRoute(),
      samples: <NavReplaySample>[...north, ...turn, ...south],
    );
  }

  /// D. Route departure onto a side street: north for 8 s, then due east
  /// away from the planned route at speed. Heading delta stays ~90 degrees,
  /// so this must resolve via snap distance, not wrong-direction.
  static NavReplayFixture sideStreetDeparture() {
    final north = _drive(
      startLat: _originLat,
      startLon: _originLon,
      bearingDeg: 0.0,
      speedKmh: 30.0,
      count: 8,
      startTime: _t0,
      expectedRouteState: 'on_route',
    );
    final last = north.last;
    final east = _drive(
      startLat: last.latitude,
      startLon: last.longitude,
      bearingDeg: 90.0,
      speedKmh: 30.0,
      count: 14,
      startTime: last.timestamp.add(const Duration(seconds: 1)),
      expectedRouteState: 'off_route',
    );
    return NavReplayFixture(
      name: 'D_side_street_departure',
      routePoints: straightNorthRoute(),
      samples: <NavReplaySample>[...north, ...east],
    );
  }

  static List<NavReplayFixture> all() => <NavReplayFixture>[
    oppositeDirectionStart(),
    normalOnRoute(),
    uTurnBacktrack(),
    sideStreetDeparture(),
  ];
}
