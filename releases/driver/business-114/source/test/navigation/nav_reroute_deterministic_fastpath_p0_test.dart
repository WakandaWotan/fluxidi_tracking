// FLUXIDI-REROUTE-DETERMINISTIC-FASTPATH-P0-1
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_route_apply.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_instruction_policy.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_reroute_decision.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_route_progress.dart';

double _mToLat(double m) => m / 111320.0;

List<NavRoutePoint> _straightNorthRoute({
  double startLat = 50.8500,
  double startLon = 4.3500,
}) {
  final pts = <NavRoutePoint>[];
  for (var m = 0.0; m <= 2000.0; m += 25.0) {
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

NavRerouteDecisionTickInput _tick({
  required NavRouteProgressOutput progress,
  required DateTime now,
  double speedKmh = 34.0,
  double? accuracyM = 25.0,
  bool isRerouting = false,
  DateTime? lastRerouteSuccessAt,
  DateTime? routeAcceptedAt,
}) {
  return NavRerouteDecisionTickInput(
    progress: progress,
    snapDistanceM: progress.snapDistanceM,
    speedKmh: speedKmh,
    offRouteThresholdM: 95.0,
    now: now,
    accuracyM: accuracyM,
    lastRerouteSuccessAt: lastRerouteSuccessAt,
    routeAcceptedAt: routeAcceptedAt,
    isRerouting: isRerouting,
    allowReroutePhase: true,
    liveRideActive: true,
    isWaiting: false,
    hasRoute: true,
    routeVersion: 3,
  );
}

void main() {
  group('FLUXIDI-REROUTE-DETERMINISTIC-FASTPATH-P0-1', () {
    test('1) urban deliberate 90° turn @20–35 m accuracy triggers ≤1.5 s', () {
      final route = _straightNorthRoute();
      final progress = DriverNavRouteProgress();
      final decision = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 3, 6, 0, 0);
      // Warm on-route samples.
      var lat = 50.8500;
      var lon = 4.3500;
      for (var i = 0; i < 4; i++) {
        final p = _offset(lat: lat, lon: lon, bearingDeg: 0, distanceM: 10);
        lat = p.lat;
        lon = p.lon;
        progress.update(
          NavRouteProgressInput(
            timestamp: t0.add(Duration(milliseconds: i * 500)),
            rawLatitude: lat,
            rawLongitude: lon,
            rawHeading: 0,
            speedKmh: 32,
            accuracyM: 25,
            routePoints: route,
          ),
        );
      }

      DateTime? triggerAt;
      for (var i = 0; i < 4; i++) {
        final t = t0.add(Duration(milliseconds: 2000 + i * 500));
        final p = _offset(
          lat: lat,
          lon: lon,
          bearingDeg: 90,
          distanceM: 12.0 + i * 6.0,
        );
        lat = p.lat;
        lon = p.lon;
        final out = progress.update(
          NavRouteProgressInput(
            timestamp: t,
            rawLatitude: lat,
            rawLongitude: lon,
            rawHeading: 90,
            speedKmh: 32,
            accuracyM: 28,
            routePoints: route,
          ),
        );
        // Deliberate turn must not wait for snap >58 m.
        expect(out.snapDistanceM, lessThan(58.0));
        final tick = decision.update(
          _tick(progress: out, now: t, speedKmh: 32, accuracyM: 28),
        );
        if (tick.shouldTrigger) {
          triggerAt = t;
          break;
        }
      }
      expect(triggerAt, isNotNull);
      expect(
        triggerAt!.difference(t0.add(const Duration(milliseconds: 2000))).inMilliseconds,
        lessThanOrEqualTo(1500),
      );
    });

    test('2) strong mismatch with good accuracy uses fast debounce ≤500 ms', () {
      final progress = NavRouteProgressOutput(
        hasReliableSnap: false,
        snapDistanceM: 18,
        confidence: 35,
        forwardProgress: false,
        offRouteLikely: true,
        routeDeviationLikely: true,
        routeDeviationReason: 'forced_detour',
        headingDeltaDeg: 80,
        strongMismatchSuspected: true,
        strongMismatchSampleCount: 2,
        reason: 'forced_detour',
      );
      final debounce = navRerouteDebounceFor(
        offRouteReason: 'forced_detour',
        progress: progress,
        wrongStreetConfirmed: false,
        strongGrowingMismatch: true,
      );
      expect(debounce.inMilliseconds, lessThanOrEqualTo(500));
      expect(
        debounce,
        anyOf(
          NavRerouteDecisionConfig.debounceWrongStreetConfirm,
          NavRerouteDecisionConfig.debounceStrongGrowingMismatch,
          NavRerouteDecisionConfig.debounceWrongStreetConfirmed,
        ),
      );
    });

    test('3) stationary / crawl GPS drift does not reroute', () {
      final route = _straightNorthRoute();
      final progress = DriverNavRouteProgress();
      final decision = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 3, 6, 0, 0);
      var triggered = false;
      for (var i = 0; i < 8; i++) {
        final t = t0.add(Duration(milliseconds: i * 500));
        // Tiny jitter near corridor, near-stationary.
        final out = progress.update(
          NavRouteProgressInput(
            timestamp: t,
            rawLatitude: 50.8500 + _mToLat(i * 0.3),
            rawLongitude: 4.3500 + (i.isEven ? 0.00001 : -0.00001),
            rawHeading: i.isEven ? 10 : 170,
            speedKmh: 0.4,
            accuracyM: 22,
            routePoints: route,
          ),
        );
        final tick = decision.update(
          _tick(progress: out, now: t, speedKmh: 0.4, accuracyM: 22),
        );
        if (tick.shouldTrigger) triggered = true;
      }
      expect(triggered, isFalse);
    });

    test('4) parallel-road ambiguity does not premature-reroute', () {
      final route = _straightNorthRoute();
      final progress = DriverNavRouteProgress();
      final decision = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 3, 6, 0, 0);
      var lat = 50.8500;
      var lon = 4.3500;
      var triggered = false;
      for (var i = 0; i < 6; i++) {
        final t = t0.add(Duration(milliseconds: i * 500));
        // Parallel lane: small lateral offset, route-aligned heading, no growth.
        final p = _offset(lat: lat, lon: lon, bearingDeg: 0, distanceM: 10);
        lat = p.lat;
        lon = p.lon;
        final lateral = _offset(lat: lat, lon: lon, bearingDeg: 90, distanceM: 4);
        final out = progress.update(
          NavRouteProgressInput(
            timestamp: t,
            rawLatitude: lateral.lat,
            rawLongitude: lateral.lon,
            rawHeading: 0,
            speedKmh: 30,
            accuracyM: 12,
            routePoints: route,
          ),
        );
        final tick = decision.update(
          _tick(progress: out, now: t, speedKmh: 30, accuracyM: 12),
        );
        if (tick.shouldTrigger) triggered = true;
      }
      expect(triggered, isFalse);
    });

    test('5) junction ambiguity suppression remains intact', () {
      final eval = navRerouteEvaluateWrongStreet(
        progress: const NavRouteProgressOutput(
          hasReliableSnap: true,
          snapDistanceM: 6,
          confidence: 70,
          forwardProgress: true,
          offRouteLikely: false,
          headingDeltaDeg: 40,
          reason: 'reliable_snap',
        ),
        snapDistanceM: 6,
        speedKmh: 28,
        accuracyM: 10,
        distanceToManeuverM: 20,
        snapGrowing: false,
        wrongStreetSampleCount: 0,
      );
      expect(eval.ambiguous, isTrue);
      expect(eval.observation, isFalse);
    });

    test('6) generic low-confidence snap jitter keeps conservative debounce', () {
      final progress = const NavRouteProgressOutput(
        hasReliableSnap: false,
        snapDistanceM: 62,
        confidence: 30,
        forwardProgress: true,
        offRouteLikely: true,
        reason: 'off_route_likely',
      );
      final debounce = navRerouteDebounceFor(
        offRouteReason: 'snap_distance',
        progress: progress,
      );
      expect(
        debounce.inMilliseconds,
        greaterThanOrEqualTo(
          NavRerouteDecisionConfig.debounceSnapLowConfidence.inMilliseconds,
        ),
      );
    });

    test('7) suspected mismatch clear returns banner to normal', () {
      final policy = DriverNavInstructionPolicy();
      final suspected = policy.update(
        NavInstructionPolicyInput(
          timestamp: DateTime.utc(2026, 8, 3),
          liveRideActive: true,
          rawInstructionText: 'Make a U-turn',
          maneuverType: 'turn',
          maneuverModifier: 'uturn',
          distanceToManeuverM: 80,
          routeConfidence: 80,
          instructionConfidenceScore: 80,
          trustInstruction: true,
          trustRouteSnap: true,
          strongMismatchSuspected: true,
        ),
      );
      expect(suspected.isNeutralFallback, isTrue);
      expect(suspected.reason, contains('strong_mismatch_suspected'));

      final cleared = policy.update(
        NavInstructionPolicyInput(
          timestamp: DateTime.utc(2026, 8, 3),
          liveRideActive: true,
          rawInstructionText: 'Turn right onto Main',
          maneuverType: 'turn',
          maneuverModifier: 'right',
          distanceToManeuverM: 80,
          routeConfidence: 80,
          instructionConfidenceScore: 80,
          trustInstruction: true,
          trustRouteSnap: true,
          strongMismatchSuspected: false,
          offRouteLikely: false,
          routeDeviationLikely: false,
        ),
      );
      expect(cleared.showOriginalInstruction, isTrue);
      expect(cleared.reason, 'maneuver_allowed');
    });

    test('8) strong suspected mismatch suppresses stale U-turn before HTTP', () {
      final policy = DriverNavInstructionPolicy();
      final out = policy.update(
        NavInstructionPolicyInput(
          timestamp: DateTime.utc(2026, 8, 3),
          liveRideActive: true,
          rawInstructionText: 'Make a U-turn',
          maneuverType: 'turn',
          maneuverModifier: 'uturn',
          distanceToManeuverM: 40,
          routeConfidence: 70,
          instructionConfidenceScore: 70,
          trustInstruction: true,
          trustRouteSnap: false,
          strongMismatchSuspected: true,
          reroutePending: false,
          offRouteLikely: false,
        ),
      );
      expect(out.showOriginalInstruction, isFalse);
      expect(out.isNeutralFallback, isTrue);
      expect(out.displayInstructionText.toLowerCase(), contains('adapting'));
    });

    test('9) confirmed deviation does not wait for snap >58 m', () {
      final route = _straightNorthRoute();
      final progress = DriverNavRouteProgress();
      final t0 = DateTime.utc(2026, 8, 3, 6, 0, 0);
      var lat = 50.8510;
      var lon = 4.3500;
      // Seed northbound.
      for (var i = 0; i < 3; i++) {
        final p = _offset(lat: lat, lon: lon, bearingDeg: 0, distanceM: 12);
        lat = p.lat;
        lon = p.lon;
        progress.update(
          NavRouteProgressInput(
            timestamp: t0.add(Duration(milliseconds: i * 500)),
            rawLatitude: lat,
            rawLongitude: lon,
            rawHeading: 0,
            speedKmh: 36,
            accuracyM: 22,
            routePoints: route,
          ),
        );
      }
      var confirmedBelow58 = false;
      for (var i = 0; i < 3; i++) {
        final p = _offset(
          lat: lat,
          lon: lon,
          bearingDeg: 90,
          distanceM: 14.0 + i * 7.0,
        );
        lat = p.lat;
        lon = p.lon;
        final out = progress.update(
          NavRouteProgressInput(
            timestamp: t0.add(Duration(milliseconds: 1500 + i * 500)),
            rawLatitude: lat,
            rawLongitude: lon,
            rawHeading: 90,
            speedKmh: 36,
            accuracyM: 22,
            routePoints: route,
          ),
        );
        if (out.routeDeviationLikely &&
            out.routeDeviationReason == 'forced_detour' &&
            out.snapDistanceM < 58.0) {
          confirmedBelow58 = true;
          break;
        }
      }
      expect(confirmedBelow58, isTrue);
    });

    test('10) startup grace still blocks non-fast-path', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 3, 6, 0, 0);
      final out = tracker.update(
        _tick(
          progress: const NavRouteProgressOutput(
            hasReliableSnap: false,
            snapDistanceM: 70,
            confidence: 25,
            forwardProgress: true,
            offRouteLikely: true,
            reason: 'off_route_likely',
          ),
          now: t0,
          speedKmh: 30,
          accuracyM: 40,
          routeAcceptedAt: t0.subtract(const Duration(milliseconds: 500)),
        ),
      );
      expect(out.cooldownActive || !out.eligible, isTrue);
      expect(
        out.blockedReason == 'cooldown' || out.blockedReason == 'not_off_route',
        isTrue,
      );
    });

    test('11) in-flight blocks concurrent duplicate owner', () {
      final tracker = NavRerouteDecisionTracker();
      final t0 = DateTime.utc(2026, 8, 3, 6, 0, 0);
      final out = tracker.update(
        _tick(
          progress: const NavRouteProgressOutput(
            hasReliableSnap: false,
            snapDistanceM: 25,
            confidence: 30,
            forwardProgress: false,
            offRouteLikely: true,
            routeDeviationLikely: true,
            routeDeviationReason: 'forced_detour',
            headingDeltaDeg: 90,
            strongMismatchSuspected: true,
            strongMismatchSampleCount: 2,
            reason: 'forced_detour',
          ),
          now: t0,
          isRerouting: true,
        ),
      );
      expect(out.shouldTrigger, isFalse);
      expect(out.requestInFlight, isTrue);
      expect(out.blockedReason, 'request_in_flight');
    });

    test('12) stale response generation cannot apply', () {
      final decision = evaluateDriverRouteAcceptance(
        context: const DriverRouteRequestContext(
          purpose: DriverRouteApplyPurpose.destination,
          requestGeneration: 3,
          cleanupEpoch: 1,
        ),
        package: DriverPreparedRoutePackage(
          coords: const [
            DriverLonLat(4.35, 50.85),
            DriverLonLat(4.36, 50.86),
          ],
          navSteps: const [],
          distanceMeters: 100,
          durationSeconds: 30,
          source: DriverRouteResponseSource.workerReroute,
          geometryFingerprint: 1,
        ),
        snapshot: const DriverRouteAcceptanceSnapshot(
          mounted: true,
          latestRequestGeneration: 5,
          cleanupEpoch: 1,
          activeBookingId: null,
          activeTripId: 'trip_1',
          directRideActive: false,
          liveRideActive: true,
        ),
      );
      expect(decision.accepted, isFalse);
      expect(
        shouldIgnoreStaleRouteDraw(
          drawAppliedRouteVersion: 3,
          currentAppliedRouteVersion: 5,
        ),
        isTrue,
      );

      final staleGen = evaluateDriverRouteAcceptance(
        context: const DriverRouteRequestContext(
          purpose: DriverRouteApplyPurpose.overview,
          requestGeneration: 3,
          cleanupEpoch: 1,
        ),
        package: const DriverPreparedRoutePackage(
          coords: [
            DriverLonLat(4.35, 50.85),
            DriverLonLat(4.36, 50.86),
          ],
          navSteps: [],
          distanceMeters: 100,
          durationSeconds: 30,
          source: DriverRouteResponseSource.workerReroute,
          geometryFingerprint: 1,
        ),
        snapshot: const DriverRouteAcceptanceSnapshot(
          mounted: true,
          latestRequestGeneration: 5,
          cleanupEpoch: 1,
          activeBookingId: null,
          activeTripId: null,
          directRideActive: false,
          liveRideActive: true,
        ),
      );
      expect(staleGen.accepted, isFalse);
      expect(staleGen.reason, DriverRouteRejectReason.staleGeneration);
    });

    test('13) phone/tablet share identical decision thresholds', () {
      // No form-factor inputs exist on the decision API — same config for both.
      expect(NavRerouteDecisionConfig.debounceStrongGrowingMismatch.inMilliseconds, 500);
      expect(NavRerouteDecisionConfig.strongMismatchRelaxedAccuracyMaxM, 35);
      expect(NavRerouteDecisionConfig.goodAccuracyMaxM, 15);
      expect(NavRerouteDecisionConfig.wrongStreetHeadingMinDeg, 55);
    });

    test('uncertainty-aware accuracy: mid-band needs strong evidence', () {
      expect(
        navRerouteAccuracyAllowsWrongStreetObservation(
          accuracyM: 28,
          speedKmh: 30,
          snapGrowing: true,
          headingDeltaDeg: 70,
          evidenceSamples: 1,
        ),
        isTrue,
      );
      expect(
        navRerouteAccuracyAllowsWrongStreetObservation(
          accuracyM: 28,
          speedKmh: 30,
          snapGrowing: false,
          headingDeltaDeg: 70,
          evidenceSamples: 0,
        ),
        isFalse,
      );
      expect(
        navRerouteAccuracyAllowsWrongStreetObservation(
          accuracyM: 45,
          speedKmh: 30,
          snapGrowing: true,
          headingDeltaDeg: 90,
          evidenceSamples: 3,
        ),
        isFalse,
      );
    });
  });
}
