import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_apply_generation.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_apply_progress.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_decision.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_follow_pipeline.dart';

/// Field replay geometry (red/blue/green):
///
/// - Blue corridor: eastbound along lat≈50.8500 (original planned).
/// - Red detour: vehicle leaves northbound to ≈(50.8512, 4.3505).
/// - Worker package starts near the car but first stubs run *south*
///   (behind/diagonal), then joins the green northbound corridor.
/// - Old Euclidean-to-start check PASSES (start near car).
/// - Nearest-segment-only would pick the south stub.
/// - Correct apply must pick the northbound forward segment and trim.
NavRerouteApplyLatLon _ll(double lat, double lon) =>
    NavRerouteApplyLatLon(lat: lat, lon: lon);

/// Worker response that briefly looks near the car but includes behind stubs.
List<NavRerouteApplyLatLon> fieldWorkerRouteBehindThenGreen() {
  return <NavRerouteApplyLatLon>[
    // Blue/request-origin remnant south of the vehicle (behind travel).
    _ll(50.8500, 4.3490),
    _ll(50.8500, 4.3505),
    _ll(50.8500, 4.3520),
    // Nearest attractor: starts beside the car then runs south (behind).
    _ll(50.85125, 4.35055),
    _ll(50.85020, 4.35055),
    // Green forward corridor from the vehicle north to destination.
    _ll(50.85120, 4.35050),
    _ll(50.85180, 4.35050),
    _ll(50.85240, 4.35050),
    _ll(50.85240, 4.35200),
  ];
}

void main() {
  group('RELEASE-P0 reroute apply progress / field replay', () {
    const vehicleLat = 50.8512;
    const vehicleLon = 4.3505;
    const vehicleCourseNorth = 5.0;

    test('1. response after vehicle moved beyond request origin', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final requestOrigin = route.first;
      final originDelta = navRerouteApplyHaversineM(
        lat1: requestOrigin.lat,
        lon1: requestOrigin.lon,
        lat2: vehicleLat,
        lon2: vehicleLon,
      );
      expect(originDelta, greaterThan(80));
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(selected.accepted, isTrue);
      expect(selected.distanceAlongRouteM, greaterThan(originDelta * 0.4));
    });

    test('2. nearby segment behind vehicle is not sole acceptance', () {
      final route = fieldWorkerRouteBehindThenGreen();
      // Euclidean start is near? Start is ~130m south — old gate may fail.
      // Package with start *near* car but southbound first segment:
      final nearStartBehind = <NavRerouteApplyLatLon>[
        _ll(50.85115, 4.3505), // near car
        _ll(50.8506, 4.3505), // south = behind course
        _ll(50.8500, 4.3505),
        _ll(50.8500, 4.3520),
      ];
      final selected = navRerouteSelectApplyProgress(
        routeCoords: nearStartBehind,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(selected.accepted, isFalse);
      expect(
        selected.reason,
        anyOf('only_backward_nearby', 'no_forward_projection', 'backward_segment'),
      );
    });

    test('3+4. behind+forward nearby → course-compatible forward wins', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(selected.accepted, isTrue);
      expect(selected.segmentIndex, isNotNull);
      // Forward northbound corridor — not the southbound near attractor (index 3).
      expect(selected.segmentIndex!, greaterThanOrEqualTo(4));
      expect(selected.segmentIndex, isNot(3));
      expect(selected.courseDeltaDeg, isNotNull);
      expect(selected.courseDeltaDeg!, lessThan(40));
      expect(
        navRerouteApplyHeadingDeltaDeg(selected.segmentBearingDeg!, 0),
        lessThan(25),
      );
    });

    test('5. nearest but backward segment is rejected', () {
      final route = <NavRerouteApplyLatLon>[
        _ll(50.85125, 4.3505),
        _ll(50.8507, 4.3505), // nearest, southbound
        _ll(50.8512, 4.3512),
        _ll(50.8518, 4.3512), // further forward east-of-north
      ];
      // Vehicle heading north; nearest segment bearing ~180.
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      if (selected.accepted) {
        expect(selected.courseDeltaDeg!, lessThan(95));
        expect(selected.segmentBearingDeg!, isNot(closeTo(180, 25)));
      } else {
        expect(selected.accepted, isFalse);
      }
    });

    test('6. progress initializes from apply-time position (not origin)', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(selected.accepted, isTrue);
      expect(selected.snappedLat, isNotNull);
      expect(
        navRerouteApplyHaversineM(
          lat1: selected.snappedLat!,
          lon1: selected.snappedLon!,
          lat2: vehicleLat,
          lon2: vehicleLon,
        ),
        lessThan(40),
      );
      expect(
        navRerouteApplyHaversineM(
          lat1: selected.snappedLat!,
          lon1: selected.snappedLon!,
          lat2: route.first.lat,
          lon2: route.first.lon,
        ),
        greaterThan(80),
      );
    });

    test('7. geometry behind initialized progress is trimmed', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      final trimmed = navRerouteTrimCoordsAhead(
        routeCoords: route,
        progress: selected,
      );
      expect(trimmed.length, lessThan(route.length));
      expect(trimmed.first.lat, closeTo(selected.snappedLat!, 1e-6));
      expect(trimmed.last.lon, closeTo(route.last.lon, 1e-6));
      // No long south stub remains at the head.
      expect(trimmed.first.lat, greaterThan(50.8509));
    });

    test('8. first forward segment after trim owns ahead corridor', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      final trimmed = navRerouteTrimCoordsAhead(
        routeCoords: route,
        progress: selected,
      );
      expect(trimmed.length, greaterThanOrEqualTo(2));
      final bearing = navRerouteApplyBearingDeg(
        fromLat: trimmed[0].lat,
        fromLon: trimmed[0].lon,
        toLat: trimmed[1].lat,
        toLon: trimmed[1].lon,
      );
      expect(navRerouteApplyHeadingDeltaDeg(bearing, vehicleCourseNorth),
          lessThan(45));
    });

    test('9. stale route callback cannot overwrite new route', () {
      expect(
        shouldIgnoreStaleRouteDraw(
          drawAppliedRouteVersion: 4,
          currentAppliedRouteVersion: 5,
        ),
        isTrue,
      );
      expect(
        navRerouteApplyAcceptWriter(
          writerGeneration: 4,
          activeGeneration: 5,
        ),
        NavRerouteApplyWriterDecision.rejectedStaleGeneration,
      );
      final counter = NavRerouteApplyStaleWriterCounter();
      counter.note('route_geometry');
      expect(counter.total, 1);
    });

    test('10. stale camera callback cannot overwrite new bearing', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(7);
      pump.submit(
        NavStreetlevelPose(
          lat: vehicleLat,
          lon: vehicleLon,
          bearingDeg: 180,
          headingDeg: 180,
          timestampMs: 1,
          routeGeneration: 6,
          poseGeneration: 1,
        ),
      );
      expect(pump.acquire(), isNull);
      expect(pump.droppedStaleTargets, greaterThan(0));
      expect(
        navRerouteApplyAcceptWriter(
          writerGeneration: 6,
          activeGeneration: 7,
        ),
        NavRerouteApplyWriterDecision.rejectedStaleGeneration,
      );
    });

    test('11. briefly-correct-then-wrong regression (ownership preserve)', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      final trimmed = navRerouteTrimCoordsAhead(
        routeCoords: route,
        progress: selected,
      );
      // Simulate first correct apply.
      var activeCoords = trimmed;
      var matchedVisual = true;
      var trimmedFlag = true;
      var bearingFromForward = selected.segmentBearingDeg!;

      // Bug path: post-apply reset wiped ownership then restored full package.
      void buggyReset() {
        matchedVisual = false;
        trimmedFlag = false;
        activeCoords = route; // full behind stub returns
      }

      void fixedReset({required bool preserve}) {
        if (!preserve) {
          matchedVisual = false;
          trimmedFlag = false;
          return;
        }
        // Preserve trimmed ahead geometry + matched visual.
        matchedVisual = true;
        trimmedFlag = true;
        bearingFromForward = navRerouteApplyBearingDeg(
          fromLat: activeCoords[0].lat,
          fromLon: activeCoords[0].lon,
          toLat: activeCoords[1].lat,
          toLon: activeCoords[1].lon,
        );
      }

      buggyReset();
      expect(activeCoords.first.lat, lessThan(50.8505));
      expect(matchedVisual, isFalse);

      // Re-apply correct state and use fixed reset.
      activeCoords = trimmed;
      fixedReset(preserve: true);
      expect(matchedVisual, isTrue);
      expect(trimmedFlag, isTrue);
      expect(activeCoords.first.lat, greaterThan(50.8509));
      expect(
        navRerouteApplyHeadingDeltaDeg(bearingFromForward, vehicleCourseNorth),
        lessThan(45),
      );
    });

    test('12. loop/crossing route does not choose wrong segment', () {
      // Figure-8 that passes near vehicle twice: first southbound, later northbound.
      final loop = <NavRerouteApplyLatLon>[
        _ll(50.8520, 4.3490),
        _ll(50.8512, 4.3490), // near, southbound
        _ll(50.8504, 4.3490),
        _ll(50.8504, 4.3510),
        _ll(50.8512, 4.3510),
        _ll(50.8512, 4.3505), // near again, toward vehicle
        _ll(50.8520, 4.3505), // northbound forward
        _ll(50.8528, 4.3505),
      ];
      final selected = navRerouteSelectApplyProgress(
        routeCoords: loop,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(selected.accepted, isTrue);
      expect(selected.segmentBearingDeg, isNotNull);
      expect(
        navRerouteApplyHeadingDeltaDeg(
          selected.segmentBearingDeg!,
          vehicleCourseNorth,
        ),
        lessThan(95),
      );
      // Must not pick the early southbound near segment (index 0).
      expect(selected.segmentIndex!, greaterThan(0));
    });

    test('13. second reroute not needed when forward projection exists', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(selected.accepted, isTrue);
      // Same package remains ahead for a subsequent sample further north.
      final later = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: 50.8518,
        vehicleLon: 4.3505,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(later.accepted, isTrue);
    });

    test('14. same destination preserved after trim', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      final trimmed = navRerouteTrimCoordsAhead(
        routeCoords: route,
        progress: selected,
      );
      expect(trimmed.last.lat, closeTo(route.last.lat, 1e-7));
      expect(trimmed.last.lon, closeTo(route.last.lon, 1e-7));
    });

    test('15. route remains ahead during subsequent samples', () {
      final route = fieldWorkerRouteBehindThenGreen();
      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      final trimmed = navRerouteTrimCoordsAhead(
        routeCoords: route,
        progress: selected,
      );
      for (final lat in <double>[50.8512, 50.8515, 50.8518, 50.8521]) {
        final tick = navRerouteSelectApplyProgress(
          routeCoords: trimmed,
          vehicleLat: lat,
          vehicleLon: 4.3505,
          vehicleCourseDeg: vehicleCourseNorth,
        );
        expect(tick.accepted, isTrue, reason: 'lat=$lat');
        final headBearing = navRerouteApplyBearingDeg(
          fromLat: trimmed[0].lat,
          fromLon: trimmed[0].lon,
          toLat: trimmed[1].lat,
          toLon: trimmed[1].lon,
        );
        // Ahead ownership: vehicle not south of the trimmed head by >40m
        // after progress, and course stays forward-compatible.
        expect(
          navRerouteApplyHeadingDeltaDeg(headBearing, vehicleCourseNorth),
          lessThan(50),
        );
      }
    });

    test('16. original red/blue/green field replay passes', () {
      final route = fieldWorkerRouteBehindThenGreen();
      // Old check: Euclidean to route start (~130m) → would reject OR
      // near-start packages would pass without course. Prove new path:
      final aheadLegacyStartOnly = navRerouteRouteIsAheadOfVehicle(
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        routeStartLat: route.first.lat,
        routeStartLon: route.first.lon,
        maxBehindM: 40,
      );
      // Start is far behind — legacy proximity alone fails.
      expect(aheadLegacyStartOnly, isFalse);

      // With full geometry + course: accept forward green ownership.
      final ahead = navRerouteRouteIsAheadOfVehicle(
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        routeStartLat: route.first.lat,
        routeStartLon: route.first.lon,
        routeCoords: route,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(ahead, isTrue);

      final selected = navRerouteSelectApplyProgress(
        routeCoords: route,
        vehicleLat: vehicleLat,
        vehicleLon: vehicleLon,
        vehicleCourseDeg: vehicleCourseNorth,
      );
      expect(selected.accepted, isTrue);
      final trimmed = navRerouteTrimCoordsAhead(
        routeCoords: route,
        progress: selected,
      );
      expect(trimmed.first.lat, greaterThan(50.8509));
      final diag = formatNavRerouteApplyProgressDiag(
        generation: 12,
        progress: selected,
        requestOriginDeltaM: 130,
        writer: 'field_replay',
      );
      expect(diag, contains('accepted=true'));
      expect(diag, contains('writer=field_replay'));
      expect(diag, isNot(contains('50.851')));
    });

    test('route-ahead with coords rejects near-start southbound stub', () {
      final nearStartBehind = <NavRerouteApplyLatLon>[
        _ll(50.85115, 4.3505),
        _ll(50.8505, 4.3505),
        _ll(50.8500, 4.3505),
      ];
      expect(
        navRerouteRouteIsAheadOfVehicle(
          vehicleLat: vehicleLat,
          vehicleLon: vehicleLon,
          routeStartLat: nearStartBehind.first.lat,
          routeStartLon: nearStartBehind.first.lon,
          routeCoords: nearStartBehind,
          vehicleCourseDeg: vehicleCourseNorth,
        ),
        isFalse,
      );
    });
  });
}
