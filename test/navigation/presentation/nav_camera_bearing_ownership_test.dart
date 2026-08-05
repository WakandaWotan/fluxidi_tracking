import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_camera_bearing_ownership.dart';
import 'package:fluxidi_tracking/navigation/presentation/nav_stationary_bearing_hold.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_follow_pipeline.dart';

void main() {
  group('NAV-CAMERA-ZERO-OLD-ROUTE-HOLD-P0 ownership', () {
    test('1) deviation suspected immediately releases route tangent ownership',
        () {
      final owner = resolveNavCameraBearingOwner(
        deviationSuspected: true,
        reroutePending: false,
        newRouteBlendActive: false,
        routeMatchReliable: true,
      );
      expect(owner, NavCameraBearingOwner.deviationSuspected);
      expect(navCameraRouteTangentAllowed(owner), isFalse);
      expect(navCameraTravelAuthority(owner), isTrue);

      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(
        routeTangentBearingDeg: 0.0,
        routeSegmentIndex: 0,
      );
      // Warm confidence with two moving fixes along the old tangent.
      for (var i = 0; i < 2; i++) {
        gate.resolve(
          NavStationaryBearingInput(
            speedKmh: 40,
            routeTangentBearingDeg: 0.0,
            routeSegmentIndex: i,
            gpsHeadingDeg: 0.0,
            displacementM: 20,
            accuracyM: 5,
            allowRouteTangent: true,
          ),
        );
      }
      // Deviation: travel is a hard left; old tangent must not win.
      final decision = gate.resolve(
        NavStationaryBearingInput(
          speedKmh: 40,
          routeTangentBearingDeg: 0.0,
          routeSegmentIndex: 2,
          gpsHeadingDeg: 90.0,
          travelBearingDeg: 90.0,
          displacementM: 20,
          accuracyM: 5,
          dtMs: 100,
          allowRouteTangent: false,
          travelAuthority: true,
          maxRotationRateDegPerSec: kNavCameraTravelMaxRotationRateDegPerSec,
        ),
      );
      expect(decision.source, isNot(NavBearingSource.routeTangent));
      expect(decision.reason, contains('travel'));
      expect(decision.held, isFalse);
      // Meaningful change begins within 100 ms (no hold on old 0°).
      expect(navBearingShortestDelta(0.0, decision.bearingDeg).abs(),
          greaterThan(10.0));
    });

    test('2) reroute pending follows travel bearing', () {
      final owner = resolveNavCameraBearingOwner(
        deviationSuspected: true,
        reroutePending: true,
        newRouteBlendActive: false,
        routeMatchReliable: false,
      );
      expect(owner, NavCameraBearingOwner.reroutePending);
      expect(navCameraRouteTangentAllowed(owner), isFalse);

      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 10.0);
      final d = gate.resolve(
        NavStationaryBearingInput(
          speedKmh: 35,
          routeTangentBearingDeg: 10.0,
          gpsHeadingDeg: 200.0,
          travelBearingDeg: 200.0,
          displacementM: 15,
          accuracyM: 6,
          dtMs: 100,
          allowRouteTangent: false,
          travelAuthority: true,
          maxRotationRateDegPerSec: kNavCameraTravelMaxRotationRateDegPerSec,
        ),
      );
      expect(d.source, isNot(NavBearingSource.routeTangent));
      expect(navBearingShortestDelta(10.0, d.bearingDeg).abs(), greaterThan(15));
    });

    test('3) old routeVersion completion is rejected', () {
      final decision = decideNavCameraCommandCommit(
        candidate: const NavCameraCommandToken(
          routeVersion: 3,
          ownerMode: NavCameraBearingOwner.reliableRoute,
          poseGeneration: 40,
          renderEpoch: 3,
          targetTimestampMs: 1000,
          targetBearingDeg: 90,
          bearingSource: 'route_tangent',
        ),
        activeRouteVersion: 4,
        activeRenderEpoch: 4,
        lastCommittedPoseGeneration: 39,
        activeOwner: NavCameraBearingOwner.newRouteAccepted,
      );
      expect(decision.accept, isFalse);
      expect(decision.staleCommandCancelled, isTrue);
      expect(decision.reason, 'stale_route_version');
    });

    test('4) new routeVersion supersedes all old targets', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(5);
      pump.setExpectedRenderEpoch(5);
      pump.submit(
        const NavStreetlevelPose(
          lat: 51,
          lon: 4,
          bearingDeg: 0,
          headingDeg: 0,
          timestampMs: 1,
          routeGeneration: 4,
          poseGeneration: 10,
          renderEpoch: 4,
          ownerMode: 'reroute_pending',
        ),
      );
      expect(pump.acquire(), isNull);
      expect(pump.staleCommandCancelled, greaterThan(0));

      pump.submit(
        const NavStreetlevelPose(
          lat: 51,
          lon: 4,
          bearingDeg: 40,
          headingDeg: 40,
          timestampMs: 2,
          routeGeneration: 5,
          poseGeneration: 11,
          renderEpoch: 5,
          ownerMode: 'new_route_accepted',
        ),
      );
      final next = pump.acquire();
      expect(next, isNotNull);
      expect(next!.routeGeneration, 5);
      expect(next.renderEpoch, 5);
    });
  });

  group('continuous bearing response', () {
    test('5) 30°, 90° and 180° changes start without hold', () {
      for (final delta in <double>[30, 90, 180]) {
        final controller = NavStreetlevelBearingController();
        controller.follow(targetBearingDeg: 0, speedKmh: 40, dtMs: 33);
        final stepped = controller.follow(
          targetBearingDeg: delta,
          speedKmh: 40,
          dtMs: 100,
          travelAuthority: true,
        );
        expect(
          navStreetlevelShortestBearingDelta(0, stepped).abs(),
          greaterThan(8.0),
          reason: '$delta° must start within 100 ms',
        );
      }
    });

    test('6) 359° → 1° takes shortest path', () {
      final step = navCameraTravelBearingStep(
        previousDeg: 359.0,
        targetDeg: 1.0,
        dtMs: 100,
      );
      // Shortest is +2°, so applied should move toward 1 via 0, not via 180.
      expect(navBearingShortestDelta(359.0, step), greaterThan(0));
      expect(navBearingShortestDelta(359.0, step).abs(), lessThan(30));
    });

    test('7) 1° → 359° takes shortest path', () {
      final step = navCameraTravelBearingStep(
        previousDeg: 1.0,
        targetDeg: 359.0,
        dtMs: 100,
      );
      expect(navBearingShortestDelta(1.0, step), lessThan(0));
      expect(navBearingShortestDelta(1.0, step).abs(), lessThan(30));
    });

    test('8) noise remains stable', () {
      final controller = NavStreetlevelBearingController();
      controller.follow(targetBearingDeg: 90, speedKmh: 30, dtMs: 33);
      final noisy = controller.follow(
        targetBearingDeg: 91.0,
        speedKmh: 30,
        dtMs: 33,
        travelAuthority: true,
      );
      expect(noisy, closeTo(90.0, 1e-9));
    });

    test('9) sustained direction changes are not over-smoothed', () {
      final controller = NavStreetlevelBearingController();
      controller.follow(targetBearingDeg: 0, speedKmh: 50, dtMs: 33);
      // Two 100 ms ticks toward a sustained 45° change must cover most of it.
      var applied = 0.0;
      for (var i = 0; i < 2; i++) {
        applied = controller.follow(
          targetBearingDeg: 45,
          speedKmh: 50,
          dtMs: 100,
          travelAuthority: true,
        );
      }
      expect(applied, greaterThan(30.0));
    });

    test('10) bearing retargets between GPS samples', () {
      final gate = NavStationaryBearingGate();
      gate.seedInitialRouteBearing(routeTangentBearingDeg: 0);
      // Simulate pose-pump / prediction ticks between 1 Hz GPS samples while
      // the GPS course stays stale at 0°. Travel pose advances each tick.
      double? last;
      for (final travel in <double>[15, 30, 45, 60, 80]) {
        final d = gate.resolve(
          NavStationaryBearingInput(
            speedKmh: 40,
            routeTangentBearingDeg: 0,
            travelBearingDeg: travel,
            gpsHeadingDeg: 0, // stale GPS sample
            displacementM: 12,
            accuracyM: 5,
            dtMs: 100, // camera apply cadence between GPS fixes
            allowRouteTangent: false,
            travelAuthority: true,
            maxRotationRateDegPerSec: kNavCameraTravelMaxRotationRateDegPerSec,
          ),
        );
        if (last != null) {
          expect(d.bearingDeg, greaterThan(last));
        }
        last = d.bearingDeg;
      }
      expect(last!, greaterThan(40));
      // Must not remain locked to the stale GPS/route 0° heading.
      expect(last, isNot(closeTo(0.0, 5.0)));
    });
  });

  group('route replacement camera response', () {
    test('11) camera remains responsive during route replacement', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(1);
      pump.setExpectedRenderEpoch(1);
      pump.submit(
        const NavStreetlevelPose(
          lat: 51,
          lon: 4,
          bearingDeg: 0,
          headingDeg: 0,
          timestampMs: 1,
          routeGeneration: 1,
          poseGeneration: 1,
          renderEpoch: 1,
          ownerMode: 'reroute_pending',
        ),
      );
      final a = pump.acquire();
      expect(a, isNotNull);
      // While in flight, a newer travel pose coalesces (latest-wins).
      pump.submit(
        const NavStreetlevelPose(
          lat: 51.001,
          lon: 4.001,
          bearingDeg: 120,
          headingDeg: 120,
          timestampMs: 2,
          routeGeneration: 1,
          poseGeneration: 2,
          renderEpoch: 1,
          ownerMode: 'reroute_pending',
        ),
      );
      expect(pump.acquire(), isNull);
      pump.complete();
      final b = pump.acquire();
      expect(b!.bearingDeg, 120);
      expect(b.poseGeneration, 2);
    });

    test('12) no old-route snap-back after accepting the new route', () {
      // Active owner is new route; an old pending token must not commit.
      final rejected = decideNavCameraCommandCommit(
        candidate: const NavCameraCommandToken(
          routeVersion: 7,
          ownerMode: NavCameraBearingOwner.deviationSuspected,
          poseGeneration: 99,
          renderEpoch: 7,
          targetTimestampMs: 50,
          targetBearingDeg: 180,
          bearingSource: 'route_tangent',
        ),
        activeRouteVersion: 8,
        activeRenderEpoch: 8,
        lastCommittedPoseGeneration: 98,
        activeOwner: NavCameraBearingOwner.newRouteAccepted,
      );
      expect(rejected.accept, isFalse);
      expect(rejected.staleCommandCancelled, isTrue);

      final accepted = decideNavCameraCommandCommit(
        candidate: const NavCameraCommandToken(
          routeVersion: 8,
          ownerMode: NavCameraBearingOwner.newRouteAccepted,
          poseGeneration: 100,
          renderEpoch: 8,
          targetTimestampMs: 60,
          targetBearingDeg: 40,
          bearingSource: 'route_tangent',
        ),
        activeRouteVersion: 8,
        activeRenderEpoch: 8,
        lastCommittedPoseGeneration: 98,
        activeOwner: NavCameraBearingOwner.newRouteAccepted,
      );
      expect(accepted.accept, isTrue);

      // Blend from travel (200°) toward new tangent (40°) uses shortest path
      // (+160° via 0? wait: 200→40 shortest is +200? 
      // 40-200 = -160, so clockwise -160 / left +200 → shortest is -160 via 180.
      final step = navCameraTravelBearingStep(
        previousDeg: 200.0,
        targetDeg: 40.0,
        dtMs: 100,
      );
      final delta = navBearingShortestDelta(200.0, step);
      // Must move toward 40 along short arc (negative from 200).
      expect(delta, lessThan(0));
      expect(step, isNot(closeTo(0.0, 1.0))); // no snap to old north
    });

    test('routeVersion N cannot commit after N+1 is active', () {
      var cancelled = 0;
      for (var poseGen = 1; poseGen <= 5; poseGen++) {
        final d = decideNavCameraCommandCommit(
          candidate: NavCameraCommandToken(
            routeVersion: 2,
            ownerMode: NavCameraBearingOwner.reliableRoute,
            poseGeneration: poseGen,
            renderEpoch: 2,
            targetTimestampMs: poseGen * 10,
            targetBearingDeg: 0,
            bearingSource: 'route_tangent',
          ),
          activeRouteVersion: 3,
          activeRenderEpoch: 3,
          lastCommittedPoseGeneration: 0,
          activeOwner: NavCameraBearingOwner.reliableRoute,
        );
        expect(d.accept, isFalse);
        if (d.staleCommandCancelled) cancelled += 1;
      }
      expect(cancelled, 5);

      final diag = formatNavCameraOwnerDiag(
        fromOwner: NavCameraBearingOwner.reroutePending,
        toOwner: NavCameraBearingOwner.newRouteAccepted,
        reason: 'new_route_accepted',
        routeVersion: 3,
        bearingSource: 'route_tangent',
        targetBearing: 40,
        appliedBearing: 38,
        angularDelta: 2,
        targetAgeMs: 12,
        staleCommandCancelled: true,
      );
      expect(diag, contains('[NAV_CAMERA_OWNER]'));
      expect(diag, contains('fromOwner=reroute_pending'));
      expect(diag, contains('toOwner=new_route_accepted'));
      expect(diag, contains('staleCommandCancelled=true'));
      expect(diag, contains('routeVersion=3'));
    });
  });
}
