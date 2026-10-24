// NAV-REROUTE-CURRENT-POSITION-HEADING-P0
//
// Focused deterministic tests for the central reroute coordinator and
// current-position / current-heading request contract.
//
// Run:
//   flutter test test/navigation/nav_reroute_current_position_heading_p0_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_directions_request.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_coordinator.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_decision.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_complexity_guard.dart';

NavRerouteRequestOrigin _origin({
  double lat = 50.85,
  double lon = 4.35,
  double heading = 90,
}) {
  return NavRerouteRequestOrigin(
    latitude: lat,
    longitude: lon,
    headingDeg: heading,
  );
}

NavRerouteDestination _dest() =>
    const NavRerouteDestination(latitude: 50.86, longitude: 4.36);

String _tr({
  required String nl,
  required String en,
  required String fr,
  required String es,
}) =>
    nl;

void main() {
  group('NAV-REROUTE-CURRENT-POSITION-HEADING-P0 coordinator', () {
    test('1) confirmed deviation invalidates old route guidance', () {
      final c = NavRerouteCoordinator();
      c.noteSuspected(reason: 'wrong_street');
      c.confirmOffRoute(
        reason: 'wrong_street',
        origin: _origin(),
        dest: _dest(),
      );
      expect(c.oldGuidanceInvalidated, isTrue);
      expect(c.suppressOldManeuvers, isTrue);
      expect(c.freezeOldRouteProgress, isTrue);
      expect(c.showRecalculatingBanner, isTrue);
      expect(c.phase, NavReroutePhase.invalidated);
    });

    test('2) new request uses current position, same destination, heading', () {
      final c = NavRerouteCoordinator();
      final origin = _origin(lat: 50.851, lon: 4.352, heading: 175.5);
      final dest = _dest();
      final gen = c.confirmOffRoute(
        reason: 'off_route',
        origin: origin,
        dest: dest,
      );
      expect(c.beginRequest(expectedGeneration: gen, origin: origin), isTrue);
      expect(c.requestOrigin!.latitude, 50.851);
      expect(c.requestOrigin!.longitude, 4.352);
      expect(c.requestOrigin!.headingDeg, 175.5);
      expect(c.destination!.latitude, dest.latitude);
      expect(c.destination!.longitude, dest.longitude);
      final bearings = NavRerouteCoordinator.bearingsQueryValue(175.5);
      expect(bearings, contains('175.5'));
      expect(bearings.endsWith(';'), isTrue);
      final uri = buildDriverDirectionsUri(
        from: DriverLonLat(origin.longitude, origin.latitude),
        to: DriverLonLat(dest.longitude, dest.latitude),
        languageCode: 'nl',
        accessToken: 'test-token',
        originHeadingDeg: origin.headingDeg,
      );
      expect(uri.queryParameters.containsKey('bearings'), isTrue);
      expect(uri.queryParameters['bearings'], bearings);
    });

    test('3) stale reroute response is ignored', () {
      final c = NavRerouteCoordinator();
      final gen1 = c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(),
        dest: _dest(),
      );
      c.beginRequest(expectedGeneration: gen1);
      // Newer confirm supersedes.
      final gen2 = c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(heading: 10),
        dest: _dest(),
      );
      expect(gen2, greaterThan(gen1));
      expect(c.acceptResponseGeneration(gen1), isFalse);
      expect(c.activateAtomic(responseGeneration: gen1), isNull);
      expect(c.acceptResponseGeneration(gen2), isTrue);
    });

    test('4) newest generation wins', () {
      final c = NavRerouteCoordinator();
      c.confirmOffRoute(
        reason: 'a',
        origin: _origin(),
        dest: _dest(),
      );
      c.beginRequest(expectedGeneration: c.rerouteGeneration);
      // Simulate in-flight supersede.
      c.confirmOffRoute(
        reason: 'b',
        origin: _origin(heading: 200),
        dest: _dest(),
      );
      expect(c.pendingFollowUp, isTrue);
      expect(c.rerouteGeneration, 2);
      final v = c.activateAtomic(responseGeneration: 2);
      expect(v, 1);
      expect(c.phase, NavReroutePhase.active);
    });

    test('5) old maneuver is not visible during confirmed reroute', () {
      final c = NavRerouteCoordinator();
      c.confirmOffRoute(
        reason: 'wrong_street',
        origin: _origin(),
        dest: _dest(),
      );
      expect(c.suppressOldManeuvers, isTrue);
      expect(c.showRecalculatingBanner, isTrue);
    });

    test('6) geometry/maneuvers/progress/camera activate under one route_version',
        () {
      final c = NavRerouteCoordinator();
      final gen = c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(),
        dest: _dest(),
      );
      c.beginRequest(expectedGeneration: gen);
      c.noteResponseReceived(responseGeneration: gen);
      c.noteRouteParsed(responseGeneration: gen);
      final version = c.activateAtomic(responseGeneration: gen);
      expect(version, 1);
      expect(c.routeVersion, 1);
      expect(c.latency.geometryRenderedAt, isNotNull);
      expect(c.latency.maneuversActivatedAt, isNotNull);
      expect(c.latency.progressActivatedAt, isNotNull);
      expect(c.latency.cameraFollowAttachedAt, isNotNull);
      expect(c.oldGuidanceInvalidated, isFalse);
      expect(c.phase, NavReroutePhase.active);
    });

    test('7) one bad GPS fix does not reroute (decision still needs hits)', () {
      final progress = DriverNavRouteProgress();
      final decision = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 4, 6, 0, 0);
      // Warm on-route.
      for (var i = 0; i < 3; i++) {
        progress.update(
          NavRouteProgressInput(
            timestamp: t0.add(Duration(milliseconds: i * 400)),
            rawLatitude: 50.8500 + i * 0.00005,
            rawLongitude: 4.3500,
            rawHeading: 0,
            speedKmh: 30,
            accuracyM: 8,
            routePoints: [
              for (var m = 0; m <= 40; m++)
                NavRoutePoint(
                  latitude: 50.8500 + m * 0.0002,
                  longitude: 4.3500,
                ),
            ],
          ),
        );
      }
      // Single isolated GPS spike: still heading with the route, brief lateral
      // jump + poor accuracy — must not confirm a reroute alone.
      final spike = progress.update(
        NavRouteProgressInput(
          timestamp: t0.add(const Duration(seconds: 2)),
          rawLatitude: 50.8503,
          rawLongitude: 4.3504,
          rawHeading: 0,
          speedKmh: 28,
          accuracyM: 45,
          routePoints: [
            for (var m = 0; m <= 40; m++)
              NavRoutePoint(
                latitude: 50.8500 + m * 0.0002,
                longitude: 4.3500,
              ),
          ],
        ),
      );
      final out = decision.update(
        NavRerouteDecisionTickInput(
          progress: spike,
          snapDistanceM: spike.snapDistanceM,
          speedKmh: 28,
          offRouteThresholdM: 95,
          now: t0.add(const Duration(seconds: 2)),
          accuracyM: 45,
          allowReroutePhase: true,
          liveRideActive: true,
          isWaiting: false,
          isRerouting: false,
          hasRoute: true,
          routeVersion: 1,
        ),
      );
      expect(out.shouldTrigger, isFalse);
    });

    test('8) consecutive reliable off-route fixes trigger quickly', () {
      expect(
        NavRerouteDecisionConfig.debounceSnapMedium.inMilliseconds,
        lessThanOrEqualTo(1000),
      );
      expect(
        NavRerouteDecisionConfig.debounceDefault.inMilliseconds,
        lessThanOrEqualTo(1200),
      );
      expect(
        NavRerouteDecisionConfig.debounceWrongStreetConfirm.inMilliseconds,
        lessThanOrEqualTo(250),
      );
    });

    test('9) dead-end route produces stable U-turn guidance', () {
      final c = NavRerouteCoordinator();
      final gen = c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(heading: 0),
        dest: _dest(),
      );
      c.beginRequest(expectedGeneration: gen);
      c.activateAtomic(responseGeneration: gen, deadEndUturn: true);
      expect(c.deadEndUturnActive, isTrue);
      final text1 = c.deadEndUturnInstruction(
        currentHeadingDeg: 5,
        tr: _tr,
      );
      final text2 = c.deadEndUturnInstruction(
        currentHeadingDeg: 10,
        tr: _tr,
      );
      expect(text1, 'Keer om zodra dit veilig mogelijk is');
      expect(text2, text1);
      expect(
        NavRerouteCoordinator.looksLikeDeadEndUturn(
          maneuverType: 'turn',
          maneuverModifier: 'uturn',
          instructionText: null,
        ),
        isTrue,
      );
    });

    test('10) heading change after U-turn allows route continuation', () {
      final c = NavRerouteCoordinator();
      final gen = c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(heading: 0),
        dest: _dest(),
      );
      c.activateAtomic(responseGeneration: gen, deadEndUturn: true);
      expect(c.deadEndUturnActive, isTrue);
      final after = c.deadEndUturnInstruction(
        currentHeadingDeg: 180,
        tr: _tr,
      );
      expect(after, isNull);
      expect(c.deadEndUturnActive, isFalse);
    });

    test('11) reroute timeout does not permanently lock future reroutes', () {
      final c = NavRerouteCoordinator(
        requestTimeout: const Duration(milliseconds: 50),
      );
      final gen = c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(),
        dest: _dest(),
      );
      c.beginRequest(
        expectedGeneration: gen,
        at: DateTime.utc(2026, 8, 4, 6, 0, 0),
      );
      expect(
        c.isRequestTimedOut(at: DateTime.utc(2026, 8, 4, 6, 0, 1)),
        isTrue,
      );
      expect(
        c.noteTimeout(
          responseGeneration: gen,
          at: DateTime.utc(2026, 8, 4, 6, 0, 1),
        ),
        isTrue,
      );
      expect(c.timeoutLocked, isFalse);
      final next = c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(heading: 40),
        dest: _dest(),
      );
      expect(next, greaterThan(gen));
      expect(c.beginRequest(expectedGeneration: next), isTrue);
    });

    test('12) fare/tracking/compliance continue independently (coordinator isolation)',
        () {
      // Coordinator has no hooks into fare/tracking/Chiron — pure state only.
      final c = NavRerouteCoordinator();
      c.confirmOffRoute(
        reason: 'off_route',
        origin: _origin(),
        dest: _dest(),
      );
      expect(c.snapshot().inFlight || c.oldGuidanceInvalidated, isTrue);
      // No side effects beyond reroute generations / latency marks.
      expect(c.navigationSessionGeneration, 0);
      c.beginNavigationSession();
      expect(c.navigationSessionGeneration, 1);
    });
  });

  group('NAV-REROUTE-CURRENT-POSITION-HEADING-P0 complexity isolation', () {
    test('reroute pending does not activate Complexe via heading churn', () {
      final guard = NavComplexityGuard();
      // Feed sustained heading conflict + offroute while reroute pending.
      NavComplexityGuardState? last;
      for (var i = 0; i < 5; i++) {
        last = guard.update(
          NavComplexityGuardInput(
            timestamp: DateTime.utc(2026, 8, 4, 6, 0, i),
            liveRideActive: true,
            followMode: true,
            overallConfidence: 80,
            trustInstruction: true,
            trustBearing: true,
            snapDistanceM: 30,
            offRouteLikely: true,
            reroutePending: true,
            headingDeltaDeg: 90,
            predictionActive: false,
            gapBridgeMs: 0,
            speedKmh: 30,
            routeVersion: 3,
          ),
        );
      }
      expect(last, isNotNull);
      expect(last!.active, isFalse);
      expect(last.reasonCode == 'heading_route_conflict', isFalse);
    });
  });
}
