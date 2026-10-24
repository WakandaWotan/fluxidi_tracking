// RELEASE-P0 — Immediate detour recovery.
//
// Field failure: vehicle left the active route; Fluxidi stayed on the old
// polyline for ~1.5 km because nearby-route snapping + speed hard gates
// delayed detection. This suite encodes that failure as a deterministic
// replay against the production progress + decision modules.
//
// No coordinates are asserted as PII — only sample counts, distances,
// reason tokens, and trigger timing.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_decision.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';

/// ~111.32 m per 0.001° latitude (Brussels-ish synthetic corridor).
double _mToLat(double m) => m / 111320.0;
double _mToLon(double m, double atLat) =>
    m / (111320.0 * math.cos(atLat * math.pi / 180.0));

List<NavRoutePoint> _straightNorthRoute({double startLat = 50.8500, double startLon = 4.3500}) {
  final pts = <NavRoutePoint>[];
  for (var m = 0.0; m <= 2500.0; m += 25.0) {
    pts.add(NavRoutePoint(latitude: startLat + _mToLat(m), longitude: startLon));
  }
  return pts;
}

({double lat, double lon}) _offset({
  required double lat,
  required double lon,
  required double bearingDeg,
  required double distanceM,
}) {
  final br = bearingDeg * math.pi / 180.0;
  final dLat = (distanceM * math.cos(br)) / 111320.0;
  final dLon =
      (distanceM * math.sin(br)) / (111320.0 * math.cos(lat * math.pi / 180.0));
  return (lat: lat + dLat, lon: lon + dLon);
}

class _ReplayTick {
  final DateTime t;
  final double lat;
  final double lon;
  final double heading;
  final double speedKmh;
  final double accuracyM;

  const _ReplayTick({
    required this.t,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.speedKmh,
    this.accuracyM = 8.0,
  });
}

/// Drive north on corridor, then turn east onto a parallel/nearby road that
/// stays geographically close for the first samples (the field failure shape),
/// then continues away. [speedKmh] covers crawl / urban / arterial cases.
List<_ReplayTick> _clearTurnOntoOtherRoad({
  required double speedKmh,
  required DateTime t0,
  int onRouteSeconds = 6,
  int detourSeconds = 40,
}) {
  const startLat = 50.8500;
  const startLon = 4.3500;
  final stepM = speedKmh / 3.6;
  final ticks = <_ReplayTick>[];
  var lat = startLat;
  var lon = startLon;
  var t = t0;

  for (var i = 0; i < onRouteSeconds; i++) {
    if (i > 0) {
      final p = _offset(lat: lat, lon: lon, bearingDeg: 0, distanceM: stepM);
      lat = p.lat;
      lon = p.lon;
      t = t.add(const Duration(seconds: 1));
    }
    ticks.add(_ReplayTick(
      t: t,
      lat: lat,
      lon: lon,
      heading: 0,
      speedKmh: speedKmh,
    ));
  }

  // Clear turn: leave corridor due east. Old northbound route stays nearby
  // for the first ~20–40 m (snap remains moderate), then distance grows.
  for (var i = 0; i < detourSeconds; i++) {
    final p = _offset(lat: lat, lon: lon, bearingDeg: 90, distanceM: stepM);
    lat = p.lat;
    lon = p.lon;
    t = t.add(const Duration(seconds: 1));
    // Mild accuracy jitter like field GPS.
    final acc = 6.0 + (i % 3) * 2.0;
    ticks.add(_ReplayTick(
      t: t,
      lat: lat,
      lon: lon,
      heading: 90,
      speedKmh: speedKmh,
      accuracyM: acc,
    ));
  }
  return ticks;
}

class _DetourReplayOutcome {
  final int? firstTriggerSample;
  final double? travelMAtTrigger;
  final String? reasonAtTrigger;
  final int samples;

  const _DetourReplayOutcome({
    required this.firstTriggerSample,
    required this.travelMAtTrigger,
    required this.reasonAtTrigger,
    required this.samples,
  });
}

_DetourReplayOutcome _runDetourReplay({
  required List<_ReplayTick> ticks,
  required List<NavRoutePoint> route,
}) {
  final progress = DriverNavRouteProgress();
  final tracker = NavRerouteDecisionTracker();
  DateTime? firstTriggerAt;
  int? firstTriggerSample;
  double travelM = 0;
  double? travelAtTrigger;
  String? reasonAtTrigger;
  double? prevLat;
  double? prevLon;

  for (var i = 0; i < ticks.length; i++) {
    final s = ticks[i];
    if (prevLat != null && prevLon != null) {
      final dLat = (s.lat - prevLat) * 111320.0;
      final dLon = (s.lon - prevLon) *
          111320.0 *
          math.cos(s.lat * math.pi / 180.0);
      travelM += math.sqrt(dLat * dLat + dLon * dLon);
    }
    prevLat = s.lat;
    prevLon = s.lon;

    final out = progress.update(
      NavRouteProgressInput(
        timestamp: s.t,
        rawLatitude: s.lat,
        rawLongitude: s.lon,
        rawHeading: s.heading,
        speedKmh: s.speedKmh,
        accuracyM: s.accuracyM,
        routePoints: route,
      ),
    );

    final decision = tracker.update(
      NavRerouteDecisionTickInput(
        progress: out,
        snapDistanceM: out.snapDistanceM.isFinite ? out.snapDistanceM : 999,
        speedKmh: s.speedKmh,
        offRouteThresholdM: 70,
        now: s.t,
        accuracyM: s.accuracyM,
        allowReroutePhase: true,
        liveRideActive: true,
        isWaiting: false,
        isRerouting: false,
        hasRoute: true,
        routeVersion: 1,
      ),
    );

    if (decision.shouldTrigger && firstTriggerSample == null) {
      firstTriggerSample = i;
      firstTriggerAt = s.t;
      travelAtTrigger = travelM;
      reasonAtTrigger = decision.offRouteReason;
    }
  }

  // Silence unused in asserts via reason string only.
  assert(firstTriggerAt == null || firstTriggerAt != null);

  return _DetourReplayOutcome(
    firstTriggerSample: firstTriggerSample,
    travelMAtTrigger: travelAtTrigger,
    reasonAtTrigger: reasonAtTrigger,
    samples: ticks.length,
  );
}

void main() {
  final route = _straightNorthRoute();
  final t0 = DateTime.utc(2026, 8, 1, 16, 0, 0);

  group('RELEASE-P0 immediate detour field replay', () {
    test('1. clear turn at 5–10 km/h triggers early (not after ~1.5 km)', () {
      final ticks = _clearTurnOntoOtherRoad(speedKmh: 8.0, t0: t0);
      final out = _runDetourReplay(ticks: ticks, route: route);
      expect(out.firstTriggerSample, isNotNull,
          reason: 'must request a reroute after a genuine low-speed turn');
      expect(out.travelMAtTrigger, isNotNull);
      // Product bar: definitely not hundreds of metres / 1.5 km.
      expect(out.travelMAtTrigger!, lessThan(120.0),
          reason:
              'travel at trigger was ${out.travelMAtTrigger!.toStringAsFixed(1)} m');
      expect(
        out.reasonAtTrigger,
        anyOf(
          'wrong_street',
          'forced_detour',
          'off_route',
          'snap_distance',
          'opposite_direction',
          'opposite_direction_strong',
        ),
      );
    });

    test('2. clear turn at 25–35 km/h triggers early', () {
      final ticks = _clearTurnOntoOtherRoad(speedKmh: 30.0, t0: t0);
      final out = _runDetourReplay(ticks: ticks, route: route);
      expect(out.firstTriggerSample, isNotNull);
      expect(out.travelMAtTrigger!, lessThan(120.0));
    });

    test('3. clear turn at 50 km/h triggers early', () {
      final ticks = _clearTurnOntoOtherRoad(speedKmh: 50.0, t0: t0);
      final out = _runDetourReplay(ticks: ticks, route: route);
      expect(out.firstTriggerSample, isNotNull);
      expect(out.travelMAtTrigger!, lessThan(150.0));
    });

    test('10. stationary GPS jitter does not trigger', () {
      final ticks = <_ReplayTick>[];
      var t = t0;
      // Park on corridor with noisy ±3 m jitter, near-zero speed.
      for (var i = 0; i < 20; i++) {
        final jitterE = (i.isEven ? 1.0 : -1.0) * 2.5;
        final jitterN = (i % 3 == 0 ? 1.0 : -1.0) * 1.5;
        ticks.add(_ReplayTick(
          t: t,
          lat: 50.8510 + _mToLat(jitterN),
          lon: 4.3500 + _mToLon(jitterE, 50.8510),
          heading: 0,
          speedKmh: 0.4,
          accuracyM: 12,
        ));
        t = t.add(const Duration(seconds: 1));
      }
      final out = _runDetourReplay(ticks: ticks, route: route);
      expect(out.firstTriggerSample, isNull);
    });

    test('11. poor-accuracy sample ignored for early departure', () {
      final progress = DriverNavRouteProgress();
      final tracker = NavRerouteDecisionTracker();
      var lat = 50.8510;
      var lon = 4.3500;
      var t = t0;
      // Warm up on route.
      for (var i = 0; i < 4; i++) {
        final p = _offset(lat: lat, lon: lon, bearingDeg: 0, distanceM: 8);
        lat = p.lat;
        lon = p.lon;
        t = t.add(const Duration(seconds: 1));
        progress.update(NavRouteProgressInput(
          timestamp: t,
          rawLatitude: lat,
          rawLongitude: lon,
          rawHeading: 0,
          speedKmh: 25,
          accuracyM: 8,
          routePoints: route,
        ));
      }
      // One poor-accuracy east jump — must not alone trigger.
      final jump = _offset(lat: lat, lon: lon, bearingDeg: 90, distanceM: 40);
      t = t.add(const Duration(seconds: 1));
      final out = progress.update(NavRouteProgressInput(
        timestamp: t,
        rawLatitude: jump.lat,
        rawLongitude: jump.lon,
        rawHeading: 90,
        speedKmh: 25,
        accuracyM: 45,
        routePoints: route,
      ));
      final decision = tracker.update(
        NavRerouteDecisionTickInput(
          progress: out,
          snapDistanceM: out.snapDistanceM,
          speedKmh: 25,
          offRouteThresholdM: 70,
          now: t,
          accuracyM: 45,
          allowReroutePhase: true,
          liveRideActive: true,
          isWaiting: false,
          isRerouting: false,
          hasRoute: true,
          routeVersion: 1,
        ),
      );
      expect(decision.shouldTrigger, isFalse);
    });

    test('14. snapping cannot hide genuine eastbound departure', () {
      final ticks = _clearTurnOntoOtherRoad(speedKmh: 10.0, t0: t0);
      final progress = DriverNavRouteProgress();
      var sawDeviationBeforeLargeSnap = false;
      for (final s in ticks) {
        final out = progress.update(NavRouteProgressInput(
          timestamp: s.t,
          rawLatitude: s.lat,
          rawLongitude: s.lon,
          rawHeading: s.heading,
          speedKmh: s.speedKmh,
          accuracyM: s.accuracyM,
          routePoints: route,
        ));
        if (s.heading == 90 &&
            out.snapDistanceM < 50 &&
            (out.routeDeviationLikely || out.offRouteLikely)) {
          sawDeviationBeforeLargeSnap = true;
          break;
        }
      }
      expect(sawDeviationBeforeLargeSnap, isTrue,
          reason: 'raw heading/displacement must expose departure before 58 m snap');
    });

    test('20. forced_detour / wrong_street reason normalizes for worker cache bypass', () {
      expect(
        normalizeNavigationWorkerRerouteReason('forced_detour'),
        anyOf('forced_detour', 'off_route', 'wrong_street'),
      );
      expect(
        normalizeNavigationWorkerRerouteReason('wrong_street'),
        'wrong_street',
      );
    });

    test('25. route-ahead invariant rejects material behind start', () {
      expect(
        navRerouteRouteIsAheadOfVehicle(
          vehicleLat: 50.8520,
          vehicleLon: 4.3500,
          routeStartLat: 50.8500,
          routeStartLon: 4.3500,
          maxBehindM: 40,
        ),
        isFalse,
      );
      expect(
        navRerouteRouteIsAheadOfVehicle(
          vehicleLat: 50.8520,
          vehicleLon: 4.3500,
          routeStartLat: 50.85205,
          routeStartLon: 4.3500,
          maxBehindM: 40,
        ),
        isTrue,
      );
    });
  });
}
