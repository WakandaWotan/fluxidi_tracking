import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/nav_ride_boundary_ownership.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_decision.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_stabilization.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';

void main() {
  group('NAV-RIDE-BOUNDARY-ROUTE-OWNERSHIP-1', () {
    test('1: stop clears all route geometries', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1', withCompleted: true);
      expect(sim.hasAnyPriorRouteResidue, isTrue);

      sim.stopSession(reason: 'stop');
      expect(sim.fullRouteGeometry, isEmpty);
      expect(sim.completedRouteGeometry, isEmpty);
      expect(sim.remainingRouteGeometry, isEmpty);
      expect(sim.alternativeRouteGeometry, isEmpty);
      expect(sim.hasDestinationMarker, isFalse);
      expect(sim.navigationLive, isFalse);
    });

    test('2: new ride starts with no previous route', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'old');
      sim.stopSession(reason: 'stop');

      sim.beginNewSession(reason: 'street');
      expect(sim.hasAnyPriorRouteResidue, isFalse);
      expect(sim.visibleRouteCount(), 0);
      expect(sim.hasManeuverBanner, isFalse);
      expect(sim.hasLaneState, isFalse);
    });

    test('3: old style completion after stop cannot restore a route', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1', withCompleted: true);
      final styleGen = sim.beginStyleRequest();
      final capture = sim.captureForStyleRestore(
        styleGeneration: styleGen,
        frozenRouteGeometry: <String>['r1', 'r1b'],
      );

      sim.stopSession(reason: 'stop');
      expect(sim.tryStyleRestore(capture), isFalse);
      expect(sim.fullRouteGeometry, isEmpty);
      expect(
        sim.events.any((e) => e.contains('style_restore_rejected')),
        isTrue,
      );
    });

    test('4: old style completion after new session cannot restore a route', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1');
      final styleGen = sim.beginStyleRequest();
      final capture = sim.captureForStyleRestore(
        styleGeneration: styleGen,
        frozenRouteGeometry: <String>['r1', 'r1b'],
      );

      sim.stopSession(reason: 'stop');
      sim.beginNewSession(reason: 'street');
      expect(sim.tryStyleRestore(capture), isFalse);
      expect(sim.fullRouteGeometry, isEmpty);
    });

    test('5: old reroute draw completion cannot add a second line', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      final first = sim.activateRoute(routeId: 'r1');
      final staleSession = first.sessionGeneration;
      final staleEpoch = first.renderEpoch;

      sim.activateRoute(routeId: 'r2');
      expect(sim.visibleRouteCount(), 1);
      expect(sim.fullRouteGeometry, <String>['r2']);

      expect(
        sim.tryCommitRerouteDraw(
          capturedSessionGeneration: staleSession,
          capturedRenderEpoch: staleEpoch,
          routeId: 'stale_r1',
        ),
        isFalse,
      );
      expect(sim.visibleRouteCount(), 1);
      expect(sim.fullRouteGeometry, <String>['r2']);
      expect(sim.fullRouteGeometry, isNot(contains('stale_r1')));
    });

    test('6: latest style request alone may restore visuals', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1');

      final styleN = sim.beginStyleRequest();
      final captureN = sim.captureForStyleRestore(
        styleGeneration: styleN,
        frozenRouteGeometry: <String>['r1', 'r1b'],
      );
      // N+1 begins → N is stale immediately.
      final styleN1 = sim.beginStyleRequest();
      expect(sim.tryStyleRestore(captureN), isFalse);

      final captureN1 = sim.captureForStyleRestore(
        styleGeneration: styleN1,
        frozenRouteGeometry: <String>['r1', 'r1b'],
      );
      expect(sim.tryStyleRestore(captureN1), isTrue);
      expect(
        sim.events.where((e) => e.contains('style_restore_allowed')).length,
        1,
      );
    });

    test('7: full/completed/remaining route always share one owner', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      final pkg = sim.activateRoute(routeId: 'r1', withCompleted: true);
      expect(pkg.hasFullRoute, isTrue);
      expect(pkg.hasCompletedRoute, isTrue);
      expect(pkg.hasRemainingRoute, isTrue);
      expect(sim.activePackage!.sessionGeneration, pkg.sessionGeneration);
      expect(sim.activePackage!.renderEpoch, pkg.renderEpoch);
      expect(sim.activePackage!.routeVersion, pkg.routeVersion);
    });

    test('8: new route atomically replaces all old route sources', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'old', withCompleted: true);
      sim.activateRoute(routeId: 'new', withCompleted: true);
      expect(sim.fullRouteGeometry, <String>['new']);
      expect(sim.completedRouteGeometry, <String>['new_completed']);
      expect(sim.remainingRouteGeometry, <String>['new_remaining']);
      expect(sim.fullRouteGeometry, isNot(contains('old')));
      expect(sim.visibleRouteCount(), 1);
    });

    test('9: repeated stop is idempotent', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1');
      sim.stopSession(reason: 'stop');
      final sessionAfterFirst = sim.sessionClock.current;
      final renderAfterFirst = sim.renderEpoch;
      sim.stopSession(reason: 'stop');
      expect(sim.fullRouteGeometry, isEmpty);
      expect(sim.hasDestinationMarker, isFalse);
      // Second stop still advances ownership clocks but leaves geometry clear.
      expect(sim.sessionClock.current, greaterThan(sessionAfterFirst));
      expect(sim.renderEpoch, greaterThan(renderAfterFirst));
      expect(sim.hasAnyPriorRouteResidue, isFalse);
    });

    test('10: start-stop-start has one visible route only', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'ride1');
      sim.stopSession(reason: 'stop');
      sim.beginNewSession(reason: 'street');
      expect(sim.visibleRouteCount(), 0);
      sim.activateRoute(routeId: 'ride2');
      expect(sim.visibleRouteCount(), 1);
      expect(sim.fullRouteGeometry, <String>['ride2']);
    });

    test('11: destination marker from prior ride cannot survive', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1', withDestination: true);
      expect(sim.hasDestinationMarker, isTrue);
      sim.stopSession(reason: 'stop');
      expect(sim.hasDestinationMarker, isFalse);
      sim.beginNewSession(reason: 'street');
      expect(sim.hasDestinationMarker, isFalse);
    });

    test('12: old maneuver/lane/banner state cannot survive', () {
      final sim = RideBoundaryOwnershipSimulator();
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1', withBanner: true, withLane: true);
      expect(sim.hasManeuverBanner, isTrue);
      expect(sim.hasLaneState, isTrue);
      sim.beginNewSession(reason: 'next');
      expect(sim.hasManeuverBanner, isFalse);
      expect(sim.hasLaneState, isFalse);
    });

    test('13: reroute tracker begins clean for the new session', () {
      final sim = RideBoundaryOwnershipSimulator();
      final stab = NavRerouteStabilization();
      final t0 = DateTime.utc(2026, 7, 22, 12);
      sim.beginNewSession(reason: 'street');
      sim.activateRoute(routeId: 'r1');
      sim.oppositeDirectionSamples = 3;
      sim.wrongStreetSamples = 2;
      sim.strongEvidenceAt = t0;
      sim.successfulRerouteCooldownOwnerSession = sim.sessionClock.current;
      stab.noteRerouteApplied(
        newRouteGeneration: sim.routeVersion,
        now: t0,
      );

      sim.beginNewSession(reason: 'street');
      stab.reset();
      expect(sim.oppositeDirectionSamples, 0);
      expect(sim.wrongStreetSamples, 0);
      expect(sim.strongEvidenceAt, isNull);
      expect(sim.successfulRerouteCooldownOwnerSession, 0);
      expect(stab.stabilizationActive, isFalse);
      expect(
        stab.allowOppositeDirectionReroute(
          now: t0.add(const Duration(seconds: 1)),
          snapDistanceM: 15,
          oppositeStrong: true,
          speedKmh: 10,
          currentRouteGeneration: sim.routeVersion,
        ),
        isTrue,
      );
    });

    test(
      '14: genuine wrong-street detection still works after fresh readiness',
      () {
        final sim = RideBoundaryOwnershipSimulator();
        final tracker = NavRerouteDecisionTracker();
        sim.beginNewSession(reason: 'street');
        sim.activateRoute(routeId: 'r1');
        // Contaminate then clear at the next ride boundary.
        tracker.strongSampleCount = 9;
        tracker.wrongStreetSampleCount = 9;
        sim.beginNewSession(reason: 'street');
        tracker.reset();
        sim.activateRoute(routeId: 'r2');

        final t0 = DateTime.utc(2026, 7, 22, 12, 0, 30);
        final routeAcceptedAt = t0.subtract(const Duration(seconds: 20));
        NavRouteProgressOutput progress() => NavRouteProgressOutput(
          hasReliableSnap: false,
          snapDistanceM: 84.0,
          confidence: 30.0,
          forwardProgress: true,
          offRouteLikely: true,
          routeDeviationLikely: true,
          oppositeDirectionLikely: false,
          backwardProgressLikely: false,
          routeDeviationReason: 'wrong_street',
          headingDeltaDeg: 95,
          reason: 'off_route_likely',
        );
        NavRerouteDecisionTickInput tick(DateTime now) =>
            NavRerouteDecisionTickInput(
              progress: progress(),
              snapDistanceM: 84.0,
              speedKmh: 34.0,
              offRouteThresholdM: 95.0,
              now: now,
              routeAcceptedAt: routeAcceptedAt,
              accuracyM: 2.2,
              liveRideActive: true,
              hasRoute: true,
              routeVersion: sim.routeVersion,
            );

        tracker.update(tick(t0));
        final second = tracker.update(
          tick(t0.add(const Duration(milliseconds: 1200))),
        );
        expect(tracker.strongSampleCount, greaterThan(0));
        expect(second.offRouteLikely || second.eligible || second.strongSampleCount >= 1, isTrue);
      },
    );

    test('15: style/session gates align with mayRestoreRouteRender', () {
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 4,
          capturedRenderEpoch: 2,
          currentRenderEpoch: 2,
          capturedRouteStepsVersion: 1,
          currentRouteStepsVersion: 1,
          capturedSessionGeneration: 3,
          currentSessionGeneration: 4,
          capturedStyleGeneration: 5,
          currentStyleGeneration: 5,
          navigationLive: true,
        ),
        isFalse,
      );
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 4,
          capturedRenderEpoch: 2,
          currentRenderEpoch: 2,
          capturedRouteStepsVersion: 1,
          currentRouteStepsVersion: 1,
          capturedSessionGeneration: 3,
          currentSessionGeneration: 3,
          capturedStyleGeneration: 5,
          currentStyleGeneration: 6,
          navigationLive: true,
        ),
        isFalse,
      );
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 4,
          capturedRenderEpoch: 2,
          currentRenderEpoch: 2,
          capturedRouteStepsVersion: 1,
          currentRouteStepsVersion: 1,
          capturedSessionGeneration: 3,
          currentSessionGeneration: 3,
          capturedStyleGeneration: 5,
          currentStyleGeneration: 5,
          navigationLive: false,
        ),
        isFalse,
      );
      expect(
        mayRestoreRouteRender(
          routeCoordCount: 4,
          capturedRenderEpoch: 2,
          currentRenderEpoch: 2,
          capturedRouteStepsVersion: 1,
          currentRouteStepsVersion: 1,
          capturedSessionGeneration: 3,
          currentSessionGeneration: 3,
          capturedStyleGeneration: 5,
          currentStyleGeneration: 5,
          navigationLive: true,
        ),
        isTrue,
      );
    });

    test('annotation commit rejects foreign session even if epoch matches', () {
      final decision = evaluateRouteAnnotationCommit(
        capturedRenderEpoch: 7,
        currentRenderEpoch: 7,
        capturedSessionGeneration: 1,
        currentSessionGeneration: 2,
      );
      expect(decision.shouldDeleteLocalOrphansOnly, isTrue);

      final owned = evaluateOwnedRouteAnnotationCommit(
        capturedSessionGeneration: 2,
        currentSessionGeneration: 2,
        capturedRenderEpoch: 7,
        currentRenderEpoch: 7,
      );
      expect(owned.shouldCommitShared, isTrue);
    });

    test('diagnostics are PII-free and include ownership fields', () {
      final boundary = formatNavRideBoundaryDiag(
        event: NavRideBoundaryEvent.sessionStarted,
        sessionGeneration: 2,
        styleGeneration: 3,
        routeVersion: 4,
        renderEpoch: 5,
      );
      expect(boundary, startsWith('[NAV_RIDE_BOUNDARY]'));
      expect(boundary, contains('sessionGeneration=2'));
      expect(boundary, contains('styleGeneration=3'));
      expect(boundary, contains('routeVersion=4'));
      expect(boundary, contains('renderEpoch=5'));
      expect(boundary.toLowerCase(), isNot(contains('booking')));
      expect(boundary.toLowerCase(), isNot(contains('address')));

      final owner = formatNavRouteRenderOwnerDiag(
        event: NavRouteRenderOwnerEvent.styleRestoreRejected,
        sessionGeneration: 2,
        styleGeneration: 3,
        routeVersion: 4,
        renderEpoch: 5,
        rejectionReason: 'session_mismatch',
      );
      expect(owner, startsWith('[NAV_ROUTE_RENDER_OWNER]'));
      expect(owner, contains('rejectionReason=session_mismatch'));
    });

    test('hard clear apply result is fully cleared and idempotent', () {
      final a = applyRideBoundaryHardClear(
        sessionGeneration: 1,
        styleGeneration: 1,
        routeVersion: 1,
        renderEpoch: 2,
        hadFullRoute: true,
        hadDestinationMarker: true,
      );
      final b = applyRideBoundaryHardClear(
        sessionGeneration: 1,
        styleGeneration: 1,
        routeVersion: 1,
        renderEpoch: 3,
      );
      expect(a.isFullyCleared, isTrue);
      expect(b.isFullyCleared, isTrue);
    });
  });
}
