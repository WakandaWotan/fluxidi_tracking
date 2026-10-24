import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_decision.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';

/// RELEASE-P0: fuel-station / opposite-direction / small-snap reverse travel.
/// Deterministic unit coverage for the custom Fluxidi reroute path (no Mapbox
/// Navigation SDK). No coordinates are asserted as PII — only decision tokens.

List<NavRoutePoint> _northboundCorridor() {
  // ~111 m per 0.001 deg latitude.
  return const [
    NavRoutePoint(latitude: 50.85000, longitude: 4.35000),
    NavRoutePoint(latitude: 50.85100, longitude: 4.35000),
    NavRoutePoint(latitude: 50.85200, longitude: 4.35000),
    NavRoutePoint(latitude: 50.85300, longitude: 4.35000),
    NavRoutePoint(latitude: 50.85400, longitude: 4.35000),
  ];
}

NavRouteProgressInput _fix({
  required DateTime t,
  required double lat,
  required double lon,
  required double heading,
  required double speedKmh,
  double accuracyM = 8.0,
  List<NavRoutePoint>? route,
}) {
  return NavRouteProgressInput(
    timestamp: t,
    rawLatitude: lat,
    rawLongitude: lon,
    rawHeading: heading,
    speedKmh: speedKmh,
    accuracyM: accuracyM,
    routePoints: route ?? _northboundCorridor(),
  );
}

NavRouteProgressOutput _progress({
  bool offRouteLikely = false,
  bool routeDeviationLikely = false,
  bool oppositeDirectionLikely = false,
  bool backwardProgressLikely = false,
  String routeDeviationReason = 'none',
  double snapDistanceM = 5.0,
  double confidence = 80.0,
  bool hasReliableSnap = true,
  double? headingDeltaDeg,
}) {
  return NavRouteProgressOutput(
    hasReliableSnap: hasReliableSnap,
    snapDistanceM: snapDistanceM,
    confidence: confidence,
    forwardProgress: !backwardProgressLikely,
    offRouteLikely: offRouteLikely,
    routeDeviationLikely: routeDeviationLikely,
    oppositeDirectionLikely: oppositeDirectionLikely,
    backwardProgressLikely: backwardProgressLikely,
    routeDeviationReason: routeDeviationReason,
    headingDeltaDeg: headingDeltaDeg,
    reason: offRouteLikely ? 'off_route_likely' : 'reliable_snap',
  );
}

NavRerouteDecisionTickInput _tick({
  required NavRouteProgressOutput progress,
  double speedKmh = 30.0,
  DateTime? now,
  DateTime? lastRerouteAt,
  DateTime? lastRerouteFailureAt,
  bool lastRerouteFailed = false,
  bool isRerouting = false,
  bool allowReroutePhase = true,
  double? accuracyM,
  double? distanceToManeuverM,
}) {
  return NavRerouteDecisionTickInput(
    progress: progress,
    snapDistanceM: progress.snapDistanceM,
    speedKmh: speedKmh,
    offRouteThresholdM: 95.0,
    now: now ?? DateTime.utc(2026, 1, 1, 12, 0, 0),
    lastRerouteAt: lastRerouteAt,
    lastRerouteFailureAt: lastRerouteFailureAt,
    lastRerouteFailed: lastRerouteFailed,
    allowReroutePhase: allowReroutePhase,
    liveRideActive: true,
    hasRoute: true,
    isRerouting: isRerouting,
    accuracyM: accuracyM,
    distanceToManeuverM: distanceToManeuverM,
  );
}

void main() {
  group('A. Fuel-station opposite exit', () {
    test('slow station stop then low-speed reverse exit triggers once', () {
      final engine = DriverNavRouteProgress();
      final tracker = NavRerouteDecisionTracker();
      final route = _northboundCorridor();
      var t = DateTime.utc(2026, 8, 1, 12, 0, 0);

      // Follow route northbound.
      for (var i = 0; i < 3; i++) {
        final out = engine.update(
          _fix(
            t: t,
            lat: 50.8502 + i * 0.0002,
            lon: 4.35000,
            heading: 0.0,
            speedKmh: 30.0,
            route: route,
          ),
        );
        expect(out.oppositeDirectionLikely, isFalse);
        t = t.add(const Duration(milliseconds: 800));
      }

      // Slow into station (still near corridor).
      for (var i = 0; i < 2; i++) {
        engine.update(
          _fix(
            t: t,
            lat: 50.85085,
            lon: 4.35004 + i * 0.00001,
            heading: 90.0,
            speedKmh: 3.0,
            route: route,
          ),
        );
        t = t.add(const Duration(milliseconds: 700));
      }

      // Brief stop — must not arm opposite.
      final stopped = engine.update(
        _fix(
          t: t,
          lat: 50.85086,
          lon: 4.35005,
          heading: 170.0,
          speedKmh: 0.3,
          route: route,
        ),
      );
      expect(stopped.oppositeDirectionLikely, isFalse);
      t = t.add(const Duration(seconds: 1));

      // Low-speed opposite exit with sustained displacement southbound.
      NavRouteProgressOutput? last;
      for (var i = 0; i < 5; i++) {
        last = engine.update(
          _fix(
            t: t,
            lat: 50.85080 - i * 0.00004,
            lon: 4.35002,
            heading: 180.0,
            speedKmh: 4.0,
            route: route,
          ),
        );
        t = t.add(const Duration(milliseconds: 700));
      }
      expect(last, isNotNull);
      expect(last!.oppositeDirectionLikely, isTrue);
      expect(last.routeDeviationReason, 'opposite_heading_strong');

      var triggerCount = 0;
      var isRerouting = false;
      for (var i = 0; i < 4; i++) {
        final decision = tracker.update(
          _tick(
            progress: last,
            speedKmh: 4.0,
            now: t,
            accuracyM: 8.0,
            isRerouting: isRerouting,
          ),
        );
        if (decision.shouldTrigger) {
          triggerCount += 1;
          // Production locks in-flight after the first request start.
          isRerouting = true;
        }
        t = t.add(const Duration(milliseconds: 600));
      }
      expect(triggerCount, 1);
      expect(tracker.offRouteReason, 'opposite_direction_strong');
    });
  });

  group('B. Same-road U-turn', () {
    test('small snap + strong opposite + sustained movement triggers', () {
      final engine = DriverNavRouteProgress();
      final tracker = NavRerouteDecisionTracker();
      final route = _northboundCorridor();
      var t = DateTime.utc(2026, 8, 1, 12, 10, 0);

      for (var i = 0; i < 2; i++) {
        engine.update(
          _fix(
            t: t,
            lat: 50.8510 + i * 0.0001,
            lon: 4.35000,
            heading: 0.0,
            speedKmh: 25.0,
            route: route,
          ),
        );
        t = t.add(const Duration(milliseconds: 600));
      }

      NavRouteProgressOutput? last;
      for (var i = 0; i < 4; i++) {
        last = engine.update(
          _fix(
            t: t,
            lat: 50.8511 - i * 0.00005,
            lon: 4.35000,
            heading: 180.0,
            speedKmh: 18.0,
            route: route,
          ),
        );
        t = t.add(const Duration(milliseconds: 500));
      }
      expect(last!.oppositeDirectionLikely, isTrue);
      expect(last.snapDistanceM, lessThan(10.0));

      final first = tracker.update(
        _tick(progress: last, speedKmh: 18.0, now: t, accuracyM: 8.0),
      );
      expect(first.offRouteLikely, isTrue);
      final second = tracker.update(
        _tick(
          progress: last,
          speedKmh: 18.0,
          now: t.add(const Duration(milliseconds: 600)),
          accuracyM: 8.0,
        ),
      );
      expect(second.shouldTrigger, isTrue);
      expect(
        second.offRouteReason,
        anyOf('opposite_direction_strong', 'opposite_direction'),
      );
    });
  });

  group('C. Parking jitter', () {
    test('low speed noisy heading minimal displacement does not trigger', () {
      final engine = DriverNavRouteProgress();
      final tracker = NavRerouteDecisionTracker();
      final route = _northboundCorridor();
      var t = DateTime.utc(2026, 8, 1, 12, 20, 0);

      for (var i = 0; i < 8; i++) {
        final heading = i.isEven ? 10.0 : 170.0;
        final out = engine.update(
          _fix(
            t: t,
            lat: 50.85100 + (i.isEven ? 0.000001 : -0.000001),
            lon: 4.35000,
            heading: heading,
            speedKmh: 0.8,
            route: route,
          ),
        );
        final decision = tracker.update(
          _tick(
            progress: out,
            speedKmh: 0.8,
            now: t,
            accuracyM: 12.0,
          ),
        );
        expect(out.oppositeDirectionLikely, isFalse);
        expect(decision.shouldTrigger, isFalse);
        t = t.add(const Duration(milliseconds: 500));
      }
    });
  });

  group('D. Junction turn', () {
    test('temporary large heading mismatch does not false-trigger', () {
      final engine = DriverNavRouteProgress();
      final tracker = NavRerouteDecisionTracker();
      final route = _northboundCorridor();
      var t = DateTime.utc(2026, 8, 1, 12, 30, 0);

      engine.update(
        _fix(
          t: t,
          lat: 50.8510,
          lon: 4.35000,
          heading: 0.0,
          speedKmh: 20.0,
          route: route,
        ),
      );
      t = t.add(const Duration(milliseconds: 500));

      // Brief turn heading spike, then resume along route.
      final spike = engine.update(
        _fix(
          t: t,
          lat: 50.85115,
          lon: 4.35002,
          heading: 160.0,
          speedKmh: 15.0,
          route: route,
        ),
      );
      tracker.update(
        _tick(progress: spike, speedKmh: 15.0, now: t, accuracyM: 8.0),
      );
      t = t.add(const Duration(milliseconds: 500));

      var triggered = false;
      for (var i = 0; i < 4; i++) {
        final out = engine.update(
          _fix(
            t: t,
            lat: 50.8512 + i * 0.0001,
            lon: 4.35000,
            heading: 5.0,
            speedKmh: 22.0,
            route: route,
          ),
        );
        final decision = tracker.update(
          _tick(progress: out, speedKmh: 22.0, now: t, accuracyM: 8.0),
        );
        if (decision.shouldTrigger) triggered = true;
        t = t.add(const Duration(milliseconds: 500));
      }
      expect(triggered, isFalse);
    });
  });

  group('E. Roundabout', () {
    test('rotating heading through manoeuvre does not false opposite reroute', () {
      final engine = DriverNavRouteProgress();
      final tracker = NavRerouteDecisionTracker();
      // Compact ring-ish polyline (clockwise).
      final ring = <NavRoutePoint>[
        const NavRoutePoint(latitude: 50.8500, longitude: 4.3500),
        const NavRoutePoint(latitude: 50.8502, longitude: 4.3502),
        const NavRoutePoint(latitude: 50.8500, longitude: 4.3504),
        const NavRoutePoint(latitude: 50.8498, longitude: 4.3502),
        const NavRoutePoint(latitude: 50.8500, longitude: 4.3500),
      ];
      var t = DateTime.utc(2026, 8, 1, 12, 40, 0);
      final bearings = [45.0, 135.0, 225.0, 315.0];
      final lats = [50.8501, 50.8501, 50.8499, 50.8499];
      final lonFixes = [4.3501, 4.3503, 4.3503, 4.3501];

      var triggered = false;
      for (var i = 0; i < bearings.length; i++) {
        final out = engine.update(
          _fix(
            t: t,
            lat: lats[i],
            lon: lonFixes[i],
            heading: bearings[i],
            speedKmh: 18.0,
            route: ring,
          ),
        );
        final decision = tracker.update(
          _tick(
            progress: out,
            speedKmh: 18.0,
            now: t,
            accuracyM: 8.0,
            distanceToManeuverM: 15.0,
          ),
        );
        if (decision.shouldTrigger &&
            decision.offRouteReason.startsWith('opposite_direction')) {
          triggered = true;
        }
        t = t.add(const Duration(milliseconds: 600));
      }
      expect(triggered, isFalse);
    });
  });

  group('F. Parallel road', () {
    test('close snap with parallel heading does not immediate false reroute', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 1, 12, 50, 0);
      final parallel = _progress(
        snapDistanceM: 6.0,
        confidence: 70.0,
        hasReliableSnap: true,
        headingDeltaDeg: 12.0,
      );
      for (var i = 0; i < 5; i++) {
        final out = tracker.update(
          _tick(
            progress: parallel,
            speedKmh: 35.0,
            now: t0.add(Duration(milliseconds: 500 * i)),
            accuracyM: 8.0,
          ),
        );
        expect(out.shouldTrigger, isFalse);
        expect(out.offRouteLikely, isFalse);
      }
    });
  });

  group('G. Request lifecycle', () {
    test('in-flight blocks duplicate; failure clears and retries after backoff', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 1, 13, 0, 0);
      final strong = _progress(
        offRouteLikely: true,
        routeDeviationLikely: true,
        oppositeDirectionLikely: true,
        routeDeviationReason: 'opposite_heading_strong',
        headingDeltaDeg: 170.0,
        hasReliableSnap: false,
        snapDistanceM: 4.0,
      );

      final armed = tracker.update(
        _tick(progress: strong, speedKmh: 5.0, now: t0, accuracyM: 8.0),
      );
      expect(armed.offRouteLikely, isTrue);
      final trigger = tracker.update(
        _tick(
          progress: strong,
          speedKmh: 5.0,
          now: t0.add(const Duration(milliseconds: 700)),
          accuracyM: 8.0,
        ),
      );
      expect(trigger.shouldTrigger, isTrue);

      final inFlight = tracker.update(
        _tick(
          progress: strong,
          speedKmh: 5.0,
          now: t0.add(const Duration(milliseconds: 900)),
          isRerouting: true,
          accuracyM: 8.0,
        ),
      );
      expect(inFlight.shouldTrigger, isFalse);
      expect(inFlight.blockedReason, 'request_in_flight');

      final failedBackoff = tracker.update(
        _tick(
          progress: strong,
          speedKmh: 5.0,
          now: t0.add(const Duration(seconds: 1)),
          lastRerouteFailed: true,
          lastRerouteAt: t0.add(const Duration(milliseconds: 900)),
          lastRerouteFailureAt: t0.add(const Duration(milliseconds: 900)),
          accuracyM: 8.0,
        ),
      );
      expect(failedBackoff.shouldTrigger, isFalse);
      expect(failedBackoff.blockedReason, 'cooldown');

      final afterBackoffStart = tracker.update(
        _tick(
          progress: strong,
          speedKmh: 5.0,
          now: t0.add(const Duration(seconds: 5)),
          lastRerouteFailed: true,
          lastRerouteAt: t0.add(const Duration(milliseconds: 900)),
          lastRerouteFailureAt: t0.add(const Duration(milliseconds: 900)),
          accuracyM: 8.0,
        ),
      );
      expect(afterBackoffStart.eligible, isTrue);

      final afterBackoff = tracker.update(
        _tick(
          progress: strong,
          speedKmh: 5.0,
          now: t0.add(const Duration(seconds: 5, milliseconds: 600)),
          lastRerouteFailed: true,
          lastRerouteAt: t0.add(const Duration(milliseconds: 900)),
          lastRerouteFailureAt: t0.add(const Duration(milliseconds: 900)),
          accuracyM: 8.0,
        ),
      );
      expect(afterBackoff.shouldTrigger, isTrue);

      tracker.noteRerouteApplied(t0.add(const Duration(seconds: 6)));
      expect(tracker.offRouteLikely, isFalse);
      expect(tracker.offRouteReason, 'none');
    });
  });

  group('H. Reason / cache wire', () {
    test('opposite_direction and wrong_street are preserved', () {
      expect(
        normalizeNavigationWorkerRerouteReason('opposite_direction'),
        'opposite_direction',
      );
      expect(
        normalizeNavigationWorkerRerouteReason('opposite_direction_strong'),
        'opposite_direction',
      );
      expect(
        normalizeNavigationWorkerRerouteReason('wrong_street'),
        'wrong_street',
      );
      expect(
        normalizeNavigationWorkerRerouteReason('backward_progress'),
        'opposite_direction',
      );
      expect(normalizeNavigationWorkerRerouteReason('off_route'), 'off_route');
      expect(normalizeNavigationWorkerRerouteReason('manual'), 'manual');
      expect(normalizeNavigationWorkerRerouteReason('traffic'), 'traffic');
      expect(normalizeNavigationWorkerRerouteReason('junk'), 'unknown');
    });
  });

  group('I. Diagnostics buckets', () {
    test('blocked reasons distinguish stationary and samples', () {
      expect(
        navRerouteMovementBlockedReason(
          speedKmh: 0.4,
          offRouteReason: 'opposite_direction_strong',
          routeDeviationLikely: true,
          samplesOffRoute: 0,
          offRouteLikely: true,
        ),
        'stationary',
      );
      expect(
        navRerouteMovementBlockedReason(
          speedKmh: 3.0,
          offRouteReason: 'opposite_direction_strong',
          routeDeviationLikely: true,
          samplesOffRoute: 1,
          offRouteLikely: true,
          headingDeltaDeg: 170.0,
        ),
        'insufficient_samples',
      );
      expect(navRerouteDisplacementBucket(0.4), '0-1');
      expect(navRerouteDisplacementBucket(4.0), '3-8');
      expect(navRerouteHeadingDeltaBucket(150.0), '135-180');
    });
  });
}
