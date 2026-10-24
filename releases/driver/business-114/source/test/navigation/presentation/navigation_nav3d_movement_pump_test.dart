import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_vehicle_model_layer.dart';

DriverVehicle3dMovementPose _pose({
  double lon = 4.9,
  double lat = 52.3,
  double bearingDeg = 90,
  String source = 'route_snap',
  DriverVehicle3dPreset preset = DriverVehicle3dPreset.fluxidiTaxi,
  int movementGeneration = 0,
}) {
  return DriverVehicle3dMovementPose(
    lon: lon,
    lat: lat,
    bearingDeg: bearingDeg,
    source: source,
    appliedZoom: 17.8,
    appliedPitch: 45,
    preset: preset,
    movementGeneration: movementGeneration,
  );
}

/// Test harness mirroring the host attempt logic in
/// `_attemptVehicleModelMovementWrite`: throttle wait inside the same
/// iteration, single in-flight write, stale drop/re-tag, latest-wins finish.
/// The attempt never calls `pump.request` (runner never calls scheduler).
class _PumpHarness {
  _PumpHarness() {
    pump = NavVehicleModelMovementPump(
      performAttempt: _attempt,
      onAbortLivelock: (_) => aborted = true,
    );
  }

  final NavVehicleModelSyncLifecycle lifecycle =
      NavVehicleModelSyncLifecycle();
  late final NavVehicleModelMovementPump pump;

  final List<DriverVehicle3dMovementPose> writes = [];
  Completer<void>? writeGate;
  bool aborted = false;
  bool nextWriteSkippedUnchanged = false;
  int throttleWaits = 0;
  int currentMovementGeneration = 0;

  void request(DriverVehicle3dMovementPose pose, {bool force = false}) {
    final event = lifecycle.queueMovement(pose);
    if (event == 'ignored') return;
    pump.request(force: force);
  }

  Future<void> settle() async {
    while (pump.running) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  Future<bool> _attempt({required bool force, required int iteration}) async {
    final bypassThrottle = resolveDriver3dVehicleFirstPoseBypassThrottle(
      force: force,
      firstPoseRequired: lifecycle.firstPoseRequired,
    );
    if (!bypassThrottle) {
      final delayMs = lifecycle.movementThrottleDelayMs(
        DateTime.now(),
        drainPending: lifecycle.pendingUpdate,
      );
      if (delayMs > 0) {
        throttleWaits += 1;
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }

    if (!lifecycle.beginMovementUpdate(DateTime.now())) return false;

    final pose = lifecycle.consumeLatestRequest();
    if (pose == null) {
      lifecycle.cancelMovementUpdate();
      return true;
    }

    if (lifecycle.shouldIgnoreStaleMovement(pose.movementGeneration)) {
      if (lifecycle.firstPoseRequired) {
        lifecycle.requeuePose(
          _pose(
            lon: pose.lon,
            lat: pose.lat,
            bearingDeg: pose.bearingDeg,
            source: pose.source,
            preset: pose.preset,
            movementGeneration: currentMovementGeneration,
          ),
        );
        pump.requestInternalFollowUp();
      }
      lifecycle.finishMovementUpdate(
        applied: false,
        now: DateTime.now(),
        countFailure: false,
      );
      return true;
    }

    final skippedUnchanged = nextWriteSkippedUnchanged;
    if (!skippedUnchanged) {
      writes.add(pose);
    }
    final gate = writeGate;
    if (gate != null) {
      await gate.future;
    }
    if (lifecycle.firstPoseRequired) {
      lifecycle.markFirstPoseSatisfied();
    }
    lifecycle.finishMovementUpdate(
      applied: !skippedUnchanged,
      now: DateTime.now(),
      countFailure: false,
    );
    return true;
  }
}

void main() {
  group('NAV-3D-MOVEMENT-SCHEDULER-LIVELOCK-FIX-1 finite movement pump', () {
    test('1. first activation: one first pose request, one write, pump exits',
        () async {
      final h = _PumpHarness();
      expect(h.lifecycle.firstPoseRequired, isTrue);

      h.request(_pose(source: 'first_pose_register_done'), force: true);
      await h.settle();

      expect(h.writes.length, 1);
      expect(h.writes.single.source, 'first_pose_register_done');
      expect(h.lifecycle.firstPoseRequired, isFalse);
      expect(h.pump.running, isFalse);
      expect(h.pump.rerunRequested, isFalse);
      expect(h.aborted, isFalse);
      expect(h.pump.lastRunIterations, lessThanOrEqualTo(2));
    });

    test(
        '2. new request while write in flight: one follow-up iteration, '
        'latest request wins, pump exits', () async {
      final h = _PumpHarness();
      h.lifecycle.markFirstPoseSatisfied();

      h.writeGate = Completer<void>();
      h.request(_pose(bearingDeg: 10, source: 'route_snap_a'), force: true);
      await Future<void>.delayed(Duration.zero);
      expect(h.lifecycle.updateInFlight, isTrue);

      // Three requests arrive while the write is in flight: latest wins.
      h.request(_pose(bearingDeg: 20, source: 'route_snap_b'), force: true);
      h.request(_pose(bearingDeg: 30, source: 'route_snap_c'), force: true);
      h.request(_pose(bearingDeg: 40, source: 'route_snap_d'), force: true);

      h.writeGate!.complete();
      h.writeGate = null;
      await h.settle();

      expect(h.writes.length, 2);
      expect(h.writes.first.source, 'route_snap_a');
      expect(h.writes.last.source, 'route_snap_d');
      expect(h.pump.running, isFalse);
      expect(h.pump.lastRunIterations, lessThanOrEqualTo(3));
      expect(h.aborted, isFalse);
    });

    test('3. 100 rapid route_snap requests: bounded writes, no livelock',
        () async {
      final h = _PumpHarness();
      h.lifecycle.markFirstPoseSatisfied();

      for (var i = 0; i < 100; i++) {
        h.request(_pose(bearingDeg: i.toDouble(), source: 'route_snap_$i'));
      }
      await h.settle();

      // 100 synchronous requests coalesce; the pump performs a handful of
      // writes at most (latest wins per iteration), never one per request.
      debugPrint(
        'stress: writes=${h.writes.length} '
        'maxIterations=${h.pump.maxObservedIterations}',
      );
      expect(h.writes.length, lessThanOrEqualTo(5));
      expect(h.writes.last.source, 'route_snap_99');
      expect(h.pump.running, isFalse);
      expect(h.aborted, isFalse);
      expect(
        h.pump.maxObservedIterations,
        lessThanOrEqualTo(kNavVehicleModelPumpMaxStagnantIterations),
      );
    });

    test('4. first pose bypasses throttle', () async {
      final h = _PumpHarness();

      // Establish a recent native write so the throttle window is active.
      h.request(_pose(source: 'first_pose_register_done'), force: true);
      await h.settle();
      expect(h.writes.length, 1);

      // Style restore re-arms the first pose; even a non-forced request must
      // not wait out the throttle window.
      h.lifecycle.markFirstPoseRequired();
      h.request(_pose(bearingDeg: 45, source: 'first_pose_style_restore'));
      await h.settle();

      expect(h.throttleWaits, 0);
      expect(h.writes.length, 2);
      expect(h.lifecycle.firstPoseRequired, isFalse);
      expect(h.pump.running, isFalse);
    });

    test('5. unchanged pose: no endless rerun', () async {
      final h = _PumpHarness();
      h.lifecycle.markFirstPoseSatisfied();
      h.nextWriteSkippedUnchanged = true;

      h.request(_pose(source: 'route_snap_same'), force: true);
      await h.settle();

      expect(h.writes, isEmpty);
      expect(h.pump.running, isFalse);
      expect(h.pump.rerunRequested, isFalse);
      expect(h.pump.lastRunIterations, lessThanOrEqualTo(2));
      expect(h.aborted, isFalse);
    });

    test(
        '6. preset swap during in-flight write: latest preset processed, '
        'pump exits', () async {
      final h = _PumpHarness();
      h.lifecycle.markFirstPoseSatisfied();

      h.writeGate = Completer<void>();
      h.request(
        _pose(source: 'route_snap', preset: DriverVehicle3dPreset.fluxidiTaxi),
        force: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(h.lifecycle.updateInFlight, isTrue);

      h.request(
        _pose(
          source: 'preset_swap',
          preset: DriverVehicle3dPreset.classicFlyingTaxi,
        ),
        force: true,
      );

      h.writeGate!.complete();
      h.writeGate = null;
      await h.settle();

      expect(h.writes.last.preset, DriverVehicle3dPreset.classicFlyingTaxi);
      expect(h.pump.running, isFalse);
      expect(h.aborted, isFalse);
    });

    test('7. style generation invalidation: stale request dropped, pump exits',
        () async {
      final h = _PumpHarness();
      h.lifecycle.markFirstPoseSatisfied();
      h.lifecycle.syncMovementGeneration(2);
      h.currentMovementGeneration = 2;

      h.request(_pose(source: 'stale_write', movementGeneration: 0),
          force: true);
      await h.settle();

      expect(h.writes, isEmpty);
      expect(h.pump.running, isFalse);
      expect(h.pump.rerunRequested, isFalse);
      expect(h.aborted, isFalse);
    });

    test(
        '7b. stale first pose is re-tagged once with the current generation '
        'and then written', () async {
      final h = _PumpHarness();
      expect(h.lifecycle.firstPoseRequired, isTrue);
      h.lifecycle.syncMovementGeneration(1);
      h.currentMovementGeneration = 1;

      h.request(
        _pose(source: 'first_pose_register_done', movementGeneration: 0),
        force: true,
      );
      await h.settle();

      expect(h.writes.length, 1);
      expect(h.writes.single.movementGeneration, 1);
      expect(h.lifecycle.firstPoseRequired, isFalse);
      expect(h.pump.running, isFalse);
      expect(h.aborted, isFalse);
    });

    test('8. livelock watchdog: safe abort, 2D fallback remains available',
        () async {
      var abortIteration = 0;
      late NavVehicleModelMovementPump pump;
      final lifecycle = NavVehicleModelSyncLifecycle();
      pump = NavVehicleModelMovementPump(
        performAttempt: ({required bool force, required int iteration}) async {
          // Pathological internal self-rerun without any external request.
          pump.requestInternalFollowUp();
          return true;
        },
        onAbortLivelock: (iteration) => abortIteration = iteration,
      );

      pump.request(force: true);
      while (pump.running) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      expect(pump.abortedLivelock, isTrue);
      expect(
        abortIteration,
        kNavVehicleModelPumpMaxStagnantIterations + 1,
      );
      expect(pump.running, isFalse);
      expect(pump.rerunRequested, isFalse);
      // 2D fallback path untouched: no session fallback was forced and a new
      // external request can still start a fresh pump.
      expect(lifecycle.sessionFallback2d, isFalse);
      pump.request(force: true);
      while (pump.running) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(pump.running, isFalse);
    });

    test('request while pump running never starts a second pump', () async {
      final h = _PumpHarness();
      h.lifecycle.markFirstPoseSatisfied();
      h.writeGate = Completer<void>();
      h.request(_pose(source: 'route_snap_a'), force: true);
      await Future<void>.delayed(Duration.zero);
      expect(h.pump.running, isTrue);
      expect(h.lifecycle.updateInFlight, isTrue);

      // A second request while running must not begin a concurrent update.
      h.request(_pose(source: 'route_snap_b'), force: true);
      await Future<void>.delayed(Duration.zero);
      expect(h.writes.length, 1);

      h.writeGate!.complete();
      h.writeGate = null;
      await h.settle();
      expect(h.writes.length, 2);
    });

    test('pump diagnostics stay within the per-activation budget', () {
      resetNav3dMovementPumpLogBudget();
      final printed = <String>[];
      final original = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };
      try {
        for (var i = 0; i < 50; i++) {
          logNav3dMovementPump(event: 'write_attempt', iteration: i);
        }
        logNav3dMovementPump(event: 'abort_livelock', iteration: 99);
      } finally {
        debugPrint = original;
      }
      final normal =
          printed.where((m) => m.contains('event=write_attempt')).length;
      final aborts =
          printed.where((m) => m.contains('event=abort_livelock')).length;
      expect(normal, kNav3dMovementPumpMaxLogsPerActivation);
      expect(aborts, 1);
    });
  });
}
