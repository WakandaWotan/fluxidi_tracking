import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_streetlevel_follow_pipeline.dart';

NavStreetlevelPose _pose({
  required int gen,
  double lat = 51.0,
  double lon = 4.0,
  double bearing = 90.0,
  int routeGen = 1,
  int ts = 0,
}) {
  return NavStreetlevelPose(
    lat: lat,
    lon: lon,
    bearingDeg: bearing,
    headingDeg: bearing,
    timestampMs: ts,
    routeGeneration: routeGen,
    poseGeneration: gen,
  );
}

void main() {
  group('NAV-STREETLEVEL pump: latest-state-wins consumer', () {
    test('1. camera and vehicle consume the same pose generation', () {
      final pump = NavStreetlevelFollowPump();
      // Producer publishes one authoritative pose (shared by vehicle + camera).
      final produced = _pose(gen: 7, routeGen: 3);
      pump.submit(produced);

      final consumed = pump.acquire();
      expect(consumed, isNotNull);
      // Camera consumes exactly the pose the producer published for the
      // vehicle — same generation + route generation (PART A / PART G).
      expect(consumed!.poseGeneration, produced.poseGeneration);
      expect(consumed.routeGeneration, produced.routeGeneration);
      expect(pump.lastConsumedGeneration, 7);
    });

    test('2. stale camera targets are discarded (latest wins)', () {
      final pump = NavStreetlevelFollowPump();
      pump.submit(_pose(gen: 1));
      pump.submit(_pose(gen: 2)); // overwrites unapplied gen 1 -> dropped
      pump.submit(_pose(gen: 3)); // overwrites unapplied gen 2 -> dropped

      expect(pump.droppedStaleTargets, 2);
      final consumed = pump.acquire();
      expect(consumed!.poseGeneration, 3, reason: 'newest target wins');
    });

    test(
      '7 + 8. one update in flight max; latest target wins on next acquire',
      () {
        final pump = NavStreetlevelFollowPump();
        pump.submit(_pose(gen: 1));
        final first = pump.acquire();
        expect(first!.poseGeneration, 1);
        expect(pump.inFlight, isTrue);

        // While in flight, new poses arrive but no second update starts.
        pump.submit(_pose(gen: 2));
        pump.submit(_pose(gen: 3));
        expect(pump.acquire(), isNull, reason: 'no overlapping camera update');

        // After the single in-flight update completes, the newest wins.
        pump.complete();
        final next = pump.acquire();
        expect(next!.poseGeneration, 3);
      },
    );

    test('acquire returns null when nothing newer than last consumed', () {
      final pump = NavStreetlevelFollowPump();
      pump.submit(_pose(gen: 5));
      expect(pump.acquire()!.poseGeneration, 5);
      pump.complete();
      // No new submit -> nothing to apply, no re-applying the same pose.
      expect(pump.acquire(), isNull);
    });

    test('reset clears pending, in-flight and counters', () {
      final pump = NavStreetlevelFollowPump();
      pump.submit(_pose(gen: 1));
      pump.submit(_pose(gen: 2));
      pump.acquire();
      pump.reset();
      expect(pump.inFlight, isFalse);
      expect(pump.latest, isNull);
      expect(pump.droppedStaleTargets, 0);
      expect(pump.coalescedCount, 0);
      expect(pump.expectedRouteGeneration, -1);
      expect(pump.lastConsumedGeneration, -1);
    });

    test(
      'coalescedCount counts poses arriving while a camera is in flight',
      () {
        final pump = NavStreetlevelFollowPump();
        pump.submit(_pose(gen: 1));
        pump.acquire(); // in flight now
        pump.submit(_pose(gen: 2));
        pump.submit(_pose(gen: 3));
        expect(pump.coalescedCount, 2);
      },
    );
  });

  group('NAV-LATENCY atomic reroute handoff (PART E)', () {
    test('old-route pose is rejected after route generation bump', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(2);
      // A stale pose still tagged with the old route generation must not be
      // applied — it would compete with the freshly applied route.
      pump.submit(_pose(gen: 10, routeGen: 1));
      expect(pump.acquire(), isNull, reason: 'stale old-route pose rejected');
      expect(pump.droppedStaleTargets, 1);
    });

    test('new-route pose is applied after route generation bump', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(2);
      pump.submit(_pose(gen: 11, routeGen: 2));
      final consumed = pump.acquire();
      expect(consumed, isNotNull);
      expect(consumed!.routeGeneration, 2);
    });

    test('expected route generation is monotonic', () {
      final pump = NavStreetlevelFollowPump();
      pump.setExpectedRouteGeneration(5);
      pump.setExpectedRouteGeneration(3); // ignored (older)
      expect(pump.expectedRouteGeneration, 5);
      // A pose from the current generation still applies.
      pump.submit(_pose(gen: 1, routeGen: 5));
      expect(pump.acquire(), isNotNull);
    });

    test(
      'reroute handoff: old-route pose in flight, new-route pose wins next',
      () {
        final pump = NavStreetlevelFollowPump();
        pump.submit(_pose(gen: 1, routeGen: 1));
        final first = pump.acquire();
        expect(first!.routeGeneration, 1);
        // Reroute lands mid-flight: route generation bumps, new poses arrive.
        pump.setExpectedRouteGeneration(2);
        pump.submit(_pose(gen: 2, routeGen: 1)); // trailing old-route pose
        pump.submit(_pose(gen: 3, routeGen: 2)); // fresh new-route pose
        pump.complete();
        final next = pump.acquire();
        expect(next!.routeGeneration, 2, reason: 'new route wins the handoff');
        expect(next.poseGeneration, 3);
      },
    );
  });

  group('NAV-STREETLEVEL bearing: single authoritative smoothing stage', () {
    test(
      '3. no second smoothing stage adds extra lag (single step applied)',
      () {
        // One controller = one stepToward. A small delta within the max step is
        // applied fully in a single call (no residual double-lag).
        final c = NavStreetlevelBearingController();
        c.follow(targetBearingDeg: 90.0, speedKmh: 40.0); // seed
        final applied = c.follow(targetBearingDeg: 95.0, speedKmh: 40.0);
        expect(
          applied,
          closeTo(95.0, 1e-9),
          reason: 'within max step -> reaches target in one stage',
        );
      },
    );

    test('4. 0/360 wraparound remains correct', () {
      expect(
        navStreetlevelShortestBearingDelta(350.0, 10.0),
        closeTo(20.0, 1e-9),
      );
      expect(
        navStreetlevelShortestBearingDelta(10.0, 350.0),
        closeTo(-20.0, 1e-9),
      );

      final c = NavStreetlevelBearingController();
      c.follow(targetBearingDeg: 359.0, speedKmh: 40.0);
      final applied = c.follow(targetBearingDeg: 1.0, speedKmh: 40.0);
      // 359 -> 1 is +2 degrees, not -358.
      expect(applied, closeTo(1.0, 1e-9));
    });

    test(
      '5. small heading changes remain smooth (applied, not suppressed)',
      () {
        final c = NavStreetlevelBearingController();
        c.follow(targetBearingDeg: 100.0, speedKmh: 30.0);
        final applied = c.follow(targetBearingDeg: 104.0, speedKmh: 30.0);
        expect(
          applied,
          closeTo(104.0, 1e-9),
          reason: '4 deg is above deadband and within small max step',
        );
      },
    );

    test('6. large turn catches up faster than small jitter', () {
      final small = NavStreetlevelBearingController();
      small.follow(targetBearingDeg: 0.0, speedKmh: 30.0);
      final smallStep = small.lastAppliedDeltaDeg.abs();
      small.follow(targetBearingDeg: 5.0, speedKmh: 30.0);
      final smallApplied = small.lastAppliedDeltaDeg.abs();

      final big = NavStreetlevelBearingController();
      big.follow(targetBearingDeg: 0.0, speedKmh: 30.0);
      big.follow(targetBearingDeg: 120.0, speedKmh: 30.0); // sharp/roundabout
      final bigApplied = big.lastAppliedDeltaDeg.abs();

      expect(smallStep, 0.0);
      expect(
        bigApplied,
        greaterThan(smallApplied),
        reason: 'large delta uses a larger bounded catch-up step',
      );
      expect(bigApplied, closeTo(kNavStreetlevelBearingMaxStepLargeDeg, 1e-9));
    });

    test('9. low-speed jitter does not spin the camera', () {
      final c = NavStreetlevelBearingController();
      c.follow(targetBearingDeg: 90.0, speedKmh: 0.5);
      // Sub-deadband wobble at a standstill is held.
      final a1 = c.follow(targetBearingDeg: 90.8, speedKmh: 0.5);
      final a2 = c.follow(targetBearingDeg: 89.3, speedKmh: 0.5);
      expect(a1, closeTo(90.0, 1e-9));
      expect(a2, closeTo(90.0, 1e-9));
    });

    test('F. low speed still rotates for a genuine route-tangent turn', () {
      final c = NavStreetlevelBearingController();
      c.follow(targetBearingDeg: 0.0, speedKmh: 2.0);
      final applied = c.follow(targetBearingDeg: 40.0, speedKmh: 2.0);
      // Not frozen: rotates by the bounded low-speed step toward the turn.
      expect(applied, greaterThan(0.0));
      expect(applied, closeTo(kNavStreetlevelBearingLowSpeedMaxStepDeg, 1e-9));
    });

    test('10. progressive roundabout heading change stays responsive', () {
      final c = NavStreetlevelBearingController();
      var applied = c.follow(targetBearingDeg: 0.0, speedKmh: 18.0);
      // Simulate continuous 15 deg/step course change around a roundabout.
      for (var target = 15.0; target <= 180.0; target += 15.0) {
        applied = c.follow(targetBearingDeg: target, speedKmh: 18.0);
      }
      // Camera should have progressed well past the entry heading, not stuck
      // facing the old road.
      expect(applied, greaterThan(120.0));
    });
  });

  group('NAV-STREETLEVEL-FLUID-MOTION bearing: turn scenarios', () {
    // Helper: run a controller to steady state against a fixed target and
    // return the number of ticks + final applied bearing.
    ({int ticks, double applied}) settle(
      NavStreetlevelBearingController c,
      double target,
      double speedKmh, {
      double dtMs = kNavStreetlevelBearingReferenceTickMs,
      int maxTicks = 400,
    }) {
      var applied = c.appliedBearing ?? double.nan;
      var ticks = 0;
      for (; ticks < maxTicks; ticks++) {
        applied = c.follow(
          targetBearingDeg: target,
          speedKmh: speedKmh,
          dtMs: dtMs,
        );
        if (navStreetlevelShortestBearingDelta(applied, target).abs() < 0.5) {
          break;
        }
      }
      return (ticks: ticks, applied: applied);
    }

    test('straight road with noisy headings stays within a tight band', () {
      final c = NavStreetlevelBearingController();
      c.follow(targetBearingDeg: 90.0, speedKmh: 50.0);
      final noisy = <double>[91.2, 88.9, 90.7, 89.4, 90.9, 88.8, 91.1];
      var maxDev = 0.0;
      for (final t in noisy) {
        final a = c.follow(targetBearingDeg: t, speedKmh: 50.0);
        maxDev = math.max(maxDev, (a - 90.0).abs());
      }
      expect(maxDev, lessThan(2.0), reason: 'noisy heading does not swing');
    });

    test('gradual curve is tracked smoothly and monotonically', () {
      final c = NavStreetlevelBearingController();
      var prev = c.follow(targetBearingDeg: 0.0, speedKmh: 40.0);
      for (var target = 3.0; target <= 60.0; target += 3.0) {
        final a = c.follow(targetBearingDeg: target, speedKmh: 40.0);
        expect(a, greaterThanOrEqualTo(prev - 1e-6), reason: 'monotonic curve');
        prev = a;
      }
      expect(prev, closeTo(60.0, 1.0));
    });

    test('90-degree turn catches up over several bounded ticks', () {
      final c = NavStreetlevelBearingController();
      c.follow(targetBearingDeg: 0.0, speedKmh: 30.0);
      final r = settle(c, 90.0, 30.0);
      expect(r.ticks, greaterThan(2), reason: 'not an instant snap');
      expect(r.applied, closeTo(90.0, 0.5));
    });

    test('roundabout: continuous rotation follows without unwrap glitch', () {
      final c = NavStreetlevelBearingController();
      var applied = c.follow(targetBearingDeg: 0.0, speedKmh: 18.0);
      for (var target = 20.0; target <= 340.0; target += 20.0) {
        final a = c.follow(targetBearingDeg: target, speedKmh: 18.0);
        // No step should exceed the large bounded cap (no 300deg unwrap jump).
        expect(
          c.lastAppliedDeltaDeg.abs(),
          lessThanOrEqualTo(kNavStreetlevelBearingMaxStepLargeDeg + 1e-6),
        );
        applied = a;
      }
      expect(applied, greaterThan(180.0), reason: 'progressed around circle');
    });

    test('359 -> 1 transition wraps the short way (+2, not -358)', () {
      final c = NavStreetlevelBearingController();
      c.follow(targetBearingDeg: 359.0, speedKmh: 40.0);
      final a = c.follow(targetBearingDeg: 1.0, speedKmh: 40.0);
      expect(a, closeTo(1.0, 1e-9));
    });

    test('stationary heading noise is held (no left/right jitter)', () {
      final c = NavStreetlevelBearingController();
      c.follow(targetBearingDeg: 200.0, speedKmh: 0.2);
      for (final t in const [201.0, 199.2, 200.8, 198.9]) {
        final a = c.follow(targetBearingDeg: t, speedKmh: 0.2);
        expect(a, closeTo(200.0, 1e-9));
      }
    });

    test('fresh GPS correction during a turn is bounded, not a snap', () {
      final c = NavStreetlevelBearingController();
      // Mid 90deg turn, applied has reached ~40deg.
      c.follow(targetBearingDeg: 0.0, speedKmh: 35.0);
      var applied = 0.0;
      for (var i = 0; i < 4; i++) {
        applied = c.follow(targetBearingDeg: 90.0, speedKmh: 35.0);
      }
      final before = applied;
      // A fresh GPS course correction arrives (target shifts to 70deg).
      final a = c.follow(targetBearingDeg: 70.0, speedKmh: 35.0);
      expect(
        navStreetlevelShortestBearingDelta(before, a).abs(),
        lessThanOrEqualTo(kNavStreetlevelBearingMaxStepLargeDeg + 1e-6),
        reason: 'correction is bounded per tick, not an instant jump',
      );
    });

    test('angular velocity is frame-rate independent (16ms vs 33ms)', () {
      // Same wall-clock elapsed (about 330 ms) should reach a similar applied
      // bearing whether ticked at 16 ms or 33 ms.
      final fast = NavStreetlevelBearingController();
      fast.follow(targetBearingDeg: 0.0, speedKmh: 40.0);
      for (var t = 0.0; t < 330.0; t += 16.0) {
        fast.follow(targetBearingDeg: 90.0, speedKmh: 40.0, dtMs: 16.0);
      }

      final slow = NavStreetlevelBearingController();
      slow.follow(targetBearingDeg: 0.0, speedKmh: 40.0);
      for (var t = 0.0; t < 330.0; t += 33.0) {
        slow.follow(targetBearingDeg: 90.0, speedKmh: 40.0, dtMs: 33.0);
      }

      expect(
        (fast.appliedBearing! - slow.appliedBearing!).abs(),
        lessThan(12.0),
        reason: 'similar turn progress regardless of frame rate',
      );
    });
  });

  group('NAV-STREETLEVEL-FLUID-MOTION correction blend policy', () {
    test('1 m correction blends smoothly over the minimum window', () {
      expect(NavStreetlevelCorrectionPolicy.blendDurationMs(1.0), 250);
      expect(NavStreetlevelCorrectionPolicy.requiresHardReset(1.0), isFalse);
    });

    test('3 m correction completes within ~250-500 ms', () {
      final d = NavStreetlevelCorrectionPolicy.blendDurationMs(3.0);
      expect(d, greaterThanOrEqualTo(250));
      expect(d, lessThan(350));
    });

    test('8 m correction completes within ~250-500 ms', () {
      final d = NavStreetlevelCorrectionPolicy.blendDurationMs(8.0);
      expect(d, greaterThan(350));
      expect(d, lessThanOrEqualTo(500));
    });

    test('large off-route correction uses a bounded recovery window', () {
      final d = NavStreetlevelCorrectionPolicy.blendDurationMs(60.0);
      expect(d, NavStreetlevelCorrectionPolicy.boundedRecoveryMs);
      expect(NavStreetlevelCorrectionPolicy.requiresHardReset(60.0), isFalse);
    });

    test('irreconcilable jump hard-resets instead of smearing', () {
      expect(NavStreetlevelCorrectionPolicy.requiresHardReset(120.0), isTrue);
      expect(NavStreetlevelCorrectionPolicy.blendDurationMs(500.0), 0);
      expect(
        NavStreetlevelCorrectionPolicy.requiresHardReset(double.nan),
        isTrue,
      );
    });

    test('maxBlendMsFor caps large corrections but not normal following', () {
      // Normal (<=15m): high cap so interval-based following is unchanged.
      expect(
        NavStreetlevelCorrectionPolicy.maxBlendMsFor(10.0),
        NavStreetlevelCorrectionPolicy.normalBlendMs,
      );
      // Large: bounded recovery cap.
      expect(
        NavStreetlevelCorrectionPolicy.maxBlendMsFor(60.0),
        NavStreetlevelCorrectionPolicy.boundedRecoveryMs,
      );
    });

    test('ease-out fraction is monotonic and never overshoots', () {
      var prev = 0.0;
      for (var e = 0; e <= 500; e += 25) {
        final f = NavStreetlevelCorrectionPolicy.easeFraction(e, 500);
        expect(f, greaterThanOrEqualTo(prev - 1e-9), reason: 'monotonic');
        expect(f, inInclusiveRange(0.0, 1.0), reason: 'no overshoot');
        prev = f;
      }
      expect(NavStreetlevelCorrectionPolicy.easeFraction(500, 500), 1.0);
      expect(NavStreetlevelCorrectionPolicy.easeFraction(1000, 500), 1.0);
    });

    test(
      'GPS recovery after a gap: drift within normal blends, not hard reset',
      () {
        // After a 5-10s gap the vehicle has dead-reckoned; the real fix lands a
        // few metres off -> a normal bounded correction, never a teleport.
        final d = NavStreetlevelCorrectionPolicy.blendDurationMs(6.0);
        expect(NavStreetlevelCorrectionPolicy.requiresHardReset(6.0), isFalse);
        expect(d, inInclusiveRange(250, 500));
      },
    );
  });

  group('NAV-STREETLEVEL-FLUID-MOTION look-ahead', () {
    test('collapses to minimum at/below low speed', () {
      expect(
        navStreetlevelLookAheadMeters(0.0),
        kNavStreetlevelLookAheadMinMeters,
      );
      expect(
        navStreetlevelLookAheadMeters(kNavStreetlevelBearingLowSpeedKmh),
        kNavStreetlevelLookAheadMinMeters,
      );
    });

    test('grows with speed within bounded clamps', () {
      final low = navStreetlevelLookAheadMeters(40.0);
      final high = navStreetlevelLookAheadMeters(90.0);
      expect(low, greaterThan(kNavStreetlevelLookAheadMinMeters));
      expect(high, greaterThan(low));
      expect(high, lessThanOrEqualTo(kNavStreetlevelLookAheadMaxMeters));
    });

    test('never exceeds the maximum even at very high speed', () {
      expect(
        navStreetlevelLookAheadMeters(300.0),
        kNavStreetlevelLookAheadMaxMeters,
      );
    });
  });

  group('NAV-STREETLEVEL-FLUID-MOTION cadence stats + diag', () {
    test('median / p95 / freezes over a rolling window', () {
      final s = NavFrameCadenceStats(capacity: 100);
      for (var i = 0; i < 50; i++) {
        s.add(16.0);
      }
      s.add(120.0); // a freeze
      s.add(130.0); // a freeze
      expect(s.medianMs, closeTo(16.0, 1e-9));
      expect(s.p95Ms, greaterThanOrEqualTo(16.0));
      expect(s.freezesOver(100.0), 2);
      expect(s.maxMs, 130.0);
    });

    test('window is bounded to capacity', () {
      final s = NavFrameCadenceStats(capacity: 10);
      for (var i = 0; i < 100; i++) {
        s.add(i.toDouble());
      }
      expect(s.count, 10);
    });

    test('ignores negative / non-finite intervals', () {
      final s = NavFrameCadenceStats();
      s.add(-5.0);
      s.add(double.nan);
      s.add(double.infinity);
      expect(s.count, 0);
    });

    test('cadence diag line contains all five cadences', () {
      final line = formatNavCadenceDiag(
        gpsMedianMs: 1000,
        anchorMedianMs: 1000,
        poseMedianMs: 16,
        cameraApplyMedianMs: 16,
        frameMedianMs: 16.7,
        frameP95Ms: 33.0,
        frameFreezesOver100: 0,
        uiBuildMedianMs: 6.2,
        rasterMedianMs: 7.1,
      );
      expect(line, contains('[NAV_LATENCY_CADENCE]'));
      for (final key in const [
        'gpsMedianMs=1000',
        'anchorMedianMs=1000',
        'poseMedianMs=16',
        'cameraApplyMedianMs=16',
        'frameMedianMs=16.7',
        'frameP95Ms=33.0',
        'frameFreezesOver100=0',
        'uiBuildMedianMs=6.2',
        'rasterMedianMs=7.1',
      ]) {
        expect(line, contains(key));
      }
    });
  });

  group('NAV-STREETLEVEL diagnostics (PART H)', () {
    test('bounded diagnostics line contains all required fields', () {
      final line = formatNavStreetlevelFollowDiag(
        poseGeneration: 12,
        cameraGeneration: 11,
        vehicleGeneration: 12,
        poseAgeMs: 34,
        cameraUpdateIntervalMs: 80,
        bearingTarget: 91.4,
        bearingApplied: 90.2,
        bearingDelta: 1.2,
        cameraInFlight: true,
        droppedStaleTargets: 3,
        reason: 'pump_apply',
      );
      expect(line, contains('[NAV_STREETLEVEL_FOLLOW]'));
      for (final key in const [
        'poseGeneration=12',
        'cameraGeneration=11',
        'vehicleGeneration=12',
        'poseAgeMs=34',
        'cameraUpdateIntervalMs=80',
        'bearingTarget=91.4',
        'bearingApplied=90.2',
        'bearingDelta=1.2',
        'cameraInFlight=true',
        'droppedStaleTargets=3',
        'reason=pump_apply',
      ]) {
        expect(line, contains(key));
      }
    });

    test(
      'NAV_LATENCY_CAMERA diagnostics line contains all required fields',
      () {
        final line = formatNavLatencyCameraDiag(
          owner: 'streetlevel_pump',
          targetGeneration: 58,
          appliedGeneration: 57,
          targetAgeMs: 34,
          requestToApplyMs: 12,
          applyIntervalMs: 80,
          animationInFlight: true,
          coalescedCount: 2,
          droppedCount: 31,
          skipReason: '',
        );
        expect(line, contains('[NAV_LATENCY_CAMERA]'));
        for (final key in const [
          'owner=streetlevel_pump',
          'targetGeneration=58',
          'appliedGeneration=57',
          'targetAgeMs=34',
          'requestToApplyMs=12',
          'applyIntervalMs=80',
          'animationInFlight=true',
          'coalescedCount=2',
          'droppedCount=31',
          'skipReason=-',
        ]) {
          expect(line, contains(key));
        }
      },
    );
  });
}
