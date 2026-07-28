import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_stationary_bearing_hold.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_streetlevel_bearing_lock.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_route_bearing.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_follow_pipeline.dart';

void main() {
  // A stationary fix: no speed, no displacement, good accuracy.
  NavStationaryBearingInput parked({
    double? routeTangentBearingDeg,
    int? routeSegmentIndex,
    double? gpsHeadingDeg,
  }) {
    return NavStationaryBearingInput(
      speedKmh: 0.0,
      routeTangentBearingDeg: routeTangentBearingDeg,
      routeSegmentIndex: routeSegmentIndex,
      gpsHeadingDeg: gpsHeadingDeg,
      displacementM: 0.4,
      accuracyM: 8.0,
    );
  }

  // A clearly moving fix.
  NavStationaryBearingInput driving({
    double speedKmh = 40.0,
    double? routeTangentBearingDeg,
    int? routeSegmentIndex,
    double? gpsHeadingDeg,
    double displacementM = 20.0,
  }) {
    return NavStationaryBearingInput(
      speedKmh: speedKmh,
      routeTangentBearingDeg: routeTangentBearingDeg,
      routeSegmentIndex: routeSegmentIndex,
      gpsHeadingDeg: gpsHeadingDeg,
      displacementM: displacementM,
      accuracyM: 8.0,
    );
  }

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 stationary START', () {
    test('stationary START holds route-segment bearing', () {
      final gate = NavStationaryBearingGate();
      final seeded = gate.seedInitialRouteBearing(
        routeTangentBearingDeg: 72.0,
        routeSegmentIndex: 0,
      );
      expect(seeded, closeTo(72.0, 1e-9));

      // Twenty parked fixes whose re-snapped tangent and GPS course wander.
      var bearing = seeded!;
      for (var i = 0; i < 20; i++) {
        final decision = gate.resolve(
          parked(
            routeTangentBearingDeg: 72.0 + (i.isEven ? 26.0 : -31.0),
            routeSegmentIndex: i.isEven ? 0 : 1,
            gpsHeadingDeg: (i * 47.0) % 360.0,
          ),
        );
        bearing = decision.bearingDeg;
        expect(decision.held, isTrue);
        expect(decision.source, NavBearingSource.held);
      }
      expect(bearing, closeTo(72.0, 1e-9));
    });

    test('the initial bearing comes from the first meaningful route segment', () {
      // A sub-metre opening stub followed by a clear northbound leg. The stub
      // azimuth must not become the opening camera orientation.
      const route = <DriverLonLat>[
        DriverLonLat(4.0, 52.0),
        DriverLonLat(4.0000012, 52.0000001),
        DriverLonLat(4.0, 52.0009),
      ];
      final bearing = navFirstMeaningfulRouteSegmentBearing(route);
      expect(bearing, isNotNull);
      expect(bearing!, closeTo(0.0, 5.0));
    });

    test('a route with only a stub still yields a usable direction', () {
      const route = <DriverLonLat>[
        DriverLonLat(4.0, 52.0),
        DriverLonLat(4.00001, 52.0),
      ];
      expect(navFirstMeaningfulRouteSegmentBearing(route), isNotNull);
      expect(
        navFirstMeaningfulRouteSegmentBearing(const <DriverLonLat>[]),
        isNull,
      );
    });

    test('no bearing is invented before route or movement exists', () {
      final gate = NavStationaryBearingGate();
      final decision = gate.resolve(parked());
      expect(decision.held, isTrue);
      expect(decision.reason, 'no_reliable_bearing_yet');
      expect(gate.acceptedBearing, isNull);
    });

    test('a first fix with a route seeds from the segment, not GPS course', () {
      final gate = NavStationaryBearingGate();
      final decision = gate.resolve(
        parked(routeTangentBearingDeg: 200.0, gpsHeadingDeg: 15.0),
      );
      expect(decision.source, NavBearingSource.initialRouteSegment);
      expect(decision.bearingDeg, closeTo(200.0, 1e-9));
    });
  });

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 bearing eligibility', () {
    test('invalid GPS heading is ignored', () {
      expect(navBearingGpsCourseUsable(-1.0), isFalse);
      expect(navBearingGpsCourseUsable(double.nan), isFalse);
      expect(navBearingGpsCourseUsable(null), isFalse);
      expect(navBearingGpsCourseUsable(0.0), isTrue);

      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 90.0);
      // Moving, but the platform reports no course and no tangent exists.
      final decision = gate.resolve(driving(gpsHeadingDeg: -1.0));
      expect(decision.source, isNot(NavBearingSource.gpsCourse));
      expect(decision.bearingDeg, closeTo(90.0, 1e-9));
    });

    test('a poor-accuracy fix cannot authorise rotation', () {
      expect(
        navBearingMovementTrustworthy(speedKmh: 50.0, accuracyM: 60.0),
        isFalse,
      );
      expect(
        navBearingMovementTrustworthy(speedKmh: 50.0, accuracyM: 10.0),
        isTrue,
      );
    });

    test('low-speed jitter holds last stable bearing', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 180.0);
      // 1.5 km/h creep with sub-threshold displacement: a traffic-light crawl.
      for (final course in const <double>[10.0, 350.0, 95.0, 265.0]) {
        final decision = gate.resolve(
          NavStationaryBearingInput(
            speedKmh: 1.5,
            gpsHeadingDeg: course,
            routeTangentBearingDeg: course,
            displacementM: 1.2,
            accuracyM: 6.0,
          ),
        );
        expect(decision.held, isTrue);
        expect(decision.bearingDeg, closeTo(180.0, 1e-9));
      }
    });

    test('moving bearing becomes eligible after confidence threshold', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 0.0);
      // First trustworthy fix alone must not unlock rotation.
      final first = gate.resolve(driving(gpsHeadingDeg: 90.0));
      expect(first.held, isTrue);
      expect(first.movingConfident, isFalse);
      expect(first.bearingDeg, closeTo(0.0, 1e-9));

      final second = gate.resolve(driving(gpsHeadingDeg: 90.0));
      expect(second.movingConfident, isTrue);
      expect(second.held, isFalse);
      expect(second.source, NavBearingSource.gpsCourse);
      expect(second.bearingDeg, greaterThan(0.0));
    });

    test('a single noisy fix cannot unlock rotation on its own', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 0.0);
      for (var i = 0; i < 6; i++) {
        // Alternating trustworthy / parked fixes never reach the streak.
        gate.resolve(driving(gpsHeadingDeg: 120.0));
        final parkedDecision = gate.resolve(parked(gpsHeadingDeg: 300.0));
        expect(parkedDecision.held, isTrue);
        expect(gate.eligibleStreak, 0);
      }
      expect(gate.acceptedBearing, closeTo(0.0, 1e-9));
    });

    test('the eligible streak is bounded, never an unbounded counter', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 0.0);
      for (var i = 0; i < 200; i++) {
        gate.resolve(driving(gpsHeadingDeg: 10.0));
      }
      expect(gate.eligibleStreak, kNavBearingMovingConfidenceFixes);
    });

    test('the last reliable moving bearing is held across a short stop', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 0.0);
      gate.resolve(driving(gpsHeadingDeg: 90.0));
      for (var i = 0; i < 8; i++) {
        gate.resolve(driving(gpsHeadingDeg: 90.0));
      }
      final moving = gate.acceptedBearing;
      expect(moving, closeTo(90.0, 1e-9));

      // Red light: 30 parked fixes with noisy course.
      for (var i = 0; i < 30; i++) {
        final decision = gate.resolve(parked(gpsHeadingDeg: (i * 37.0) % 360));
        expect(decision.held, isTrue);
        expect(decision.bearingDeg, closeTo(90.0, 1e-9));
      }
      expect(gate.lastReliableMovingBearing, closeTo(90.0, 1e-9));
    });
  });

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 rotation geometry', () {
    test('359-to-1-degree smoothing takes the short rotation path', () {
      expect(navBearingShortestDelta(359.0, 1.0), closeTo(2.0, 1e-9));
      expect(navBearingShortestDelta(1.0, 359.0), closeTo(-2.0, 1e-9));
      expect(navBearingShortestDelta(10.0, 350.0), closeTo(-20.0, 1e-9));

      final stepped = navBearingRateClampedStep(
        previousDeg: 359.0,
        targetDeg: 1.0,
      );
      expect(stepped, closeTo(1.0, 1e-9));
    });

    test('the rate clamp bounds a large re-target per tick', () {
      // 1 second at 45 deg/s must not sweep 170 degrees.
      final stepped = navBearingRateClampedStep(
        previousDeg: 0.0,
        targetDeg: 170.0,
        dtMs: 1000.0,
      );
      expect(
        navBearingShortestDelta(0.0, stepped).abs(),
        closeTo(kNavBearingMaxRotationRateDegPerSec, 1e-6),
      );
      // A short tick rotates proportionally less.
      final shortTick = navBearingRateClampedStep(
        previousDeg: 0.0,
        targetDeg: 170.0,
        dtMs: 100.0,
      );
      expect(
        navBearingShortestDelta(0.0, shortTick).abs(),
        closeTo(kNavBearingMaxRotationRateDegPerSec / 10.0, 1e-6),
      );
    });

    test('normalisation wraps negatives and multiples of 360', () {
      expect(navBearingNormalize(-10.0), closeTo(350.0, 1e-9));
      expect(navBearingNormalize(370.0), closeTo(10.0, 1e-9));
      expect(navBearingNormalize(double.nan), 0.0);
    });

    test('route-segment index oscillation does not rotate the map', () {
      // Origin oscillation 0 -> 1 -> 0 -> 1 while slow.
      expect(
        navRouteSegmentTangentRetargetAllowed(
          acceptedSegmentIndex: 1,
          candidateSegmentIndex: 0,
          speedKmh: 1.0,
        ),
        isFalse,
      );
      expect(
        navRouteSegmentTangentRetargetAllowed(
          acceptedSegmentIndex: 1,
          candidateSegmentIndex: 1,
          speedKmh: 1.0,
        ),
        isFalse,
      );
      // Genuine forward progress is allowed.
      expect(
        navRouteSegmentTangentRetargetAllowed(
          acceptedSegmentIndex: 1,
          candidateSegmentIndex: 2,
          speedKmh: 1.0,
        ),
        isTrue,
      );
      // At speed the resolver is free to re-target either way.
      expect(
        navRouteSegmentTangentRetargetAllowed(
          acceptedSegmentIndex: 5,
          candidateSegmentIndex: 4,
          speedKmh: 50.0,
        ),
        isTrue,
      );

      // End to end: an oscillating index at walking pace holds the bearing.
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(
        routeTangentBearingDeg: 45.0,
        routeSegmentIndex: 1,
      );
      for (var i = 0; i < 12; i++) {
        final decision = gate.resolve(
          NavStationaryBearingInput(
            speedKmh: 1.0,
            routeTangentBearingDeg: i.isEven ? 130.0 : 320.0,
            routeSegmentIndex: i.isEven ? 0 : 1,
            displacementM: 0.9,
            accuracyM: 7.0,
          ),
        );
        expect(decision.bearingDeg, closeTo(45.0, 1e-9));
      }
    });

    test('diagnostics stay PII-free and carry no coordinates', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 12.0);
      final decision = gate.resolve(parked());
      final line = formatNavStationaryBearingDiag(
        decision: decision,
        speedKmh: 0.0,
        segmentIndex: 3,
      );
      expect(line, startsWith('[NAV_BEARING_HOLD]'));
      expect(line, contains('held=true'));
      expect(line, contains('segmentIndex=3'));
      expect(line, isNot(contains('lat')));
      expect(line, isNot(contains('lon')));
      expect(navBearingSourceLabel(NavBearingSource.held), 'held');
    });
  });

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 lock integration', () {
    const routeTangent = DriverRouteBearingOutput(
      bearing: 12.0,
      source: 'route_tangent',
      confidence: 90.0,
      reason: 'route_snap_tangent',
      routeTangentBearing: 300.0,
    );

    test('compass jitter cannot rotate the active routed camera', () {
      // View 7+, parked, a route tangent available and a wildly noisy course.
      var previous = 45.0;
      for (final noise in const <double>[10.0, 200.0, 350.0, 95.0]) {
        final output = applyDriverCockpitStreetlevelBearingLock(
          DriverCockpitStreetlevelBearingLockInput(
            routeBearing: routeTangent,
            viewLevel: 9,
            speedKmh: 0.0,
            gpsHeadingDeg: noise,
            gpsAccuracyM: 6.0,
            previousAppliedBearingDeg: previous,
            displacementM: 0.3,
          ),
        );
        expect(output.mode, 'hold');
        expect(output.reason, 'stationary_hold');
        expect(output.appliedBearing, closeTo(45.0, 1e-9));
        previous = output.appliedBearing;
      }
    });

    test('a stationary route tangent no longer overrides the hold', () {
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangent,
          viewLevel: 11,
          speedKmh: 0.0,
          previousAppliedBearingDeg: 100.0,
          displacementM: 0.1,
          instantApply: true,
        ),
      );
      expect(output.mode, 'hold');
      expect(output.appliedBearing, closeTo(100.0, 1e-9));
    });

    test('the tangent still orients the first frame with no previous bearing', () {
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangent,
          viewLevel: 9,
          speedKmh: 0.0,
          instantApply: true,
        ),
      );
      expect(output.mode, 'route_tangent');
      expect(output.appliedBearing, closeTo(300.0, 1e-9));
    });

    test('a genuinely moving vehicle still follows the route tangent', () {
      final output = applyDriverCockpitStreetlevelBearingLock(
        const DriverCockpitStreetlevelBearingLockInput(
          routeBearing: routeTangent,
          viewLevel: 10,
          speedKmh: 42.0,
          previousAppliedBearingDeg: 300.0,
          instantApply: true,
        ),
      );
      expect(output.mode, 'route_tangent');
      expect(output.appliedBearing, closeTo(300.0, 1e-9));
    });

    test('a stationary GPS course is not a bearing source for the resolver', () {
      final parkedOutput = resolveDriverRouteBearing(
        const DriverRouteBearingInput(
          gpsHeadingDeg: 137.0,
          previousBearingDeg: 20.0,
          speedKmh: 0.0,
          displacementM: 0.2,
          accuracyM: 6.0,
        ),
      );
      expect(parkedOutput.source, 'fallback');
      expect(parkedOutput.reason, 'hold_previous');
      expect(parkedOutput.bearing, closeTo(20.0, 0.01));

      final movingOutput = resolveDriverRouteBearing(
        const DriverRouteBearingInput(
          gpsHeadingDeg: 137.0,
          previousBearingDeg: 137.0,
          speedKmh: 35.0,
          displacementM: 18.0,
          accuracyM: 6.0,
        ),
      );
      expect(movingOutput.source, 'gps_heading');
      expect(movingOutput.bearing, closeTo(137.0, 0.01));
    });
  });

  group('NAV-PRESTART-PREVIEW-AND-STABLE-BEARING-P0 camera ownership', () {
    NavStreetlevelPose pose(int generation, double bearing) {
      return NavStreetlevelPose(
        lat: 52.0,
        lon: 4.0,
        bearingDeg: bearing,
        headingDeg: bearing,
        timestampMs: generation * 100,
        routeGeneration: 1,
        poseGeneration: generation,
      );
    }

    test('camera command ownership remains bounded/latest-wins', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(1);

      // Ten bearing updates arrive before a single camera write completes.
      for (var i = 1; i <= 10; i++) {
        pump.submit(pose(i, i * 12.0));
      }
      final acquired = pump.acquire();
      expect(acquired, isNotNull);
      expect(
        acquired!.poseGeneration,
        10,
        reason: 'latest wins; intermediate targets are discarded',
      );
      expect(pump.inFlight, isTrue);

      // No second command may start while one is in flight.
      pump.submit(pose(11, 140.0));
      expect(pump.acquire(), isNull);
      expect(pump.droppedStaleTargets, greaterThan(0));

      pump.complete();
      final next = pump.acquire();
      expect(next!.poseGeneration, 11);
    });

    test('a superseded route generation cannot rotate the camera', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(5);
      pump.submit(
        const NavStreetlevelPose(
          lat: 52.0,
          lon: 4.0,
          bearingDeg: 270.0,
          headingDeg: 270.0,
          timestampMs: 10,
          routeGeneration: 4,
          poseGeneration: 1,
        ),
      );
      expect(pump.acquire(), isNull);
      expect(pump.inFlight, isFalse);
    });

    test('the bounded smoother still turns for a real low-speed turn', () {
      // The gate holds the target; the smoother must not additionally freeze,
      // otherwise genuine slow turns would never resolve.
      final controller = NavStreetlevelBearingController();
      controller.follow(targetBearingDeg: 0.0, speedKmh: 2.0);
      final applied = controller.follow(targetBearingDeg: 40.0, speedKmh: 2.0);
      expect(applied, greaterThan(0.0));
      expect(
        applied,
        closeTo(kNavStreetlevelBearingLowSpeedMaxStepDeg, 1e-9),
      );
    });
  });
}
