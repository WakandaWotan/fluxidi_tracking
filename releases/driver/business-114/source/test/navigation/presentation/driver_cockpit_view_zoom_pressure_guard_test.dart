import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_view_zoom.dart';

/// RAPID-ZOOM-INPUT-PRESSURE-GUARD-1 — deterministic pressure-guard coverage.
void main() {
  final t0 = DateTime(2026, 7, 27, 20, 28);

  setUp(debugResetViewZoomPressureLogSignature);

  group('RAPID-ZOOM-INPUT-PRESSURE-GUARD-1 input decisions', () {
    test('one isolated + tap starts exactly one camera operation', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final result = lifecycle.acceptDesiredLevel(8, t0);
      expect(result.decision, DriverCockpitViewZoomInputDecision.startCamera);
      expect(result.desiredLevel, 8);
      expect(result.inflight, isFalse);
      expect(lifecycle.beginCamera(result.generation), isTrue);
      expect(lifecycle.cameraInFlight, isTrue);
      expect(lifecycle.inFlightTargetLevel, 8);
    });

    test('one isolated − tap starts exactly one camera operation', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final result = lifecycle.acceptDesiredLevel(6, t0);
      expect(result.decision, DriverCockpitViewZoomInputDecision.startCamera);
      expect(result.desiredLevel, 6);
      expect(lifecycle.beginCamera(result.generation), isTrue);
    });

    test('clamp at level 1 does not enqueue camera work', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final first = lifecycle.acceptDesiredLevel(1, t0);
      expect(first.decision, DriverCockpitViewZoomInputDecision.startCamera);
      expect(lifecycle.beginCamera(first.generation), isTrue);
      expect(
        lifecycle.finishCamera(
          requestGeneration: first.generation,
          appliedLevel: 1,
          now: t0,
        ),
        isFalse,
      );

      final clamped = lifecycle.acceptDesiredLevel(1, t0);
      expect(clamped.decision, DriverCockpitViewZoomInputDecision.unchanged);
      expect(lifecycle.cameraInFlight, isFalse);
      expect(lifecycle.hasPendingLatest, isFalse);
      // Unchanged means the caller must not start camera work.
      expect(clamped.desiredLevel, 1);
      expect(lifecycle.appliedLevel, 1);
    });

    test('clamp at level 13 does not enqueue camera work', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final first = lifecycle.acceptDesiredLevel(13, t0);
      expect(lifecycle.beginCamera(first.generation), isTrue);
      lifecycle.finishCamera(
        requestGeneration: first.generation,
        appliedLevel: 13,
        now: t0,
      );

      final clamped = lifecycle.acceptDesiredLevel(13, t0);
      expect(clamped.decision, DriverCockpitViewZoomInputDecision.unchanged);
      expect(clamped.desiredLevel, kDriverCockpitViewLevelMax);
      expect(lifecycle.hasPendingLatest, isFalse);
    });

    test('input while camera in flight coalesces to capacity one', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final first = lifecycle.acceptDesiredLevel(8, t0);
      expect(lifecycle.beginCamera(first.generation), isTrue);

      final second = lifecycle.acceptDesiredLevel(9, t0);
      expect(second.decision, DriverCockpitViewZoomInputDecision.coalesced);
      expect(second.hasPendingLatest, isTrue);
      expect(lifecycle.pendingAtCapacity, isTrue);
      expect(lifecycle.beginCamera(second.generation), isFalse);
      expect(lifecycle.inFlightGeneration, first.generation);

      final third = lifecycle.acceptDesiredLevel(10, t0);
      expect(third.decision, DriverCockpitViewZoomInputDecision.coalesced);
      expect(lifecycle.requestedLevel, 10);
      // Still a single pending slot — not a growing queue.
      expect(lifecycle.hasPendingLatest, isTrue);
      expect(lifecycle.beginCamera(third.generation), isFalse);
    });

    test('latest desired level wins after in-flight completion', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.acceptDesiredLevel(8, t0).generation;
      expect(lifecycle.beginCamera(g1), isTrue);
      lifecycle.acceptDesiredLevel(11, t0);

      expect(
        lifecycle.finishCamera(
          requestGeneration: g1,
          appliedLevel: 8,
          now: t0,
        ),
        isTrue,
      );
      expect(lifecycle.latestTargetAlreadyOwned(), isFalse);
      expect(lifecycle.requestedLevel, 11);
      expect(lifecycle.beginCamera(lifecycle.generation), isTrue);
      expect(lifecycle.inFlightTargetLevel, 11);
    });

    test('maximum inflight count equals 1', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.acceptDesiredLevel(8, t0).generation;
      expect(lifecycle.beginCamera(g1), isTrue);
      for (var level = 9; level <= 12; level++) {
        final r = lifecycle.acceptDesiredLevel(level, t0);
        expect(r.decision, DriverCockpitViewZoomInputDecision.coalesced);
        expect(lifecycle.beginCamera(r.generation), isFalse);
      }
      expect(lifecycle.cameraInFlight, isTrue);
      expect(lifecycle.inFlightGeneration, g1);
    });

    test('camera failure releases ownership and allows pending latest', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.acceptDesiredLevel(8, t0).generation;
      expect(lifecycle.beginCamera(g1), isTrue);
      lifecycle.acceptDesiredLevel(10, t0);

      expect(
        lifecycle.releaseForFailure(requestGeneration: g1),
        isTrue,
      );
      expect(lifecycle.cameraInFlight, isFalse);
      expect(lifecycle.beginCamera(lifecycle.generation), isTrue);
      expect(lifecycle.inFlightTargetLevel, 10);
    });

    test('timeout release matches failure release contract', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.acceptDesiredLevel(8, t0).generation;
      expect(lifecycle.beginCamera(g1), isTrue);
      // No newer pending — timeout must clear without false rerun.
      expect(lifecycle.releaseForFailure(requestGeneration: g1), isFalse);
      expect(lifecycle.cameraInFlight, isFalse);

      final g2 = lifecycle.acceptDesiredLevel(9, t0).generation;
      expect(lifecycle.beginCamera(g2), isTrue);
      lifecycle.acceptDesiredLevel(12, t0);
      expect(lifecycle.releaseForFailure(requestGeneration: g2), isTrue);
    });

    test('widget disposal / reset drops pending ownership safely', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.acceptDesiredLevel(8, t0).generation;
      expect(lifecycle.beginCamera(g1), isTrue);
      lifecycle.acceptDesiredLevel(12, t0);
      lifecycle.reset();
      expect(lifecycle.generation, 0);
      expect(lifecycle.cameraInFlight, isFalse);
      expect(lifecycle.hasPendingLatest, isFalse);
      expect(lifecycle.requestedLevel, kDriverCockpitViewLevelDefault);
    });
  });

  group('RAPID-ZOOM-INPUT-PRESSURE-GUARD-1 burst harness', () {
    test('20 rapid taps in one direction: ≤2 camera, ≤2 restores, final level',
        () async {
      final h = _PressureHarness();
      for (var i = 0; i < 20; i++) {
        h.tap(increase: true, now: t0);
      }
      expect(h.selectedLevel, kDriverCockpitViewLevelMax);
      expect(h.maxInflightObserved, 1);
      expect(h.coalescedCount, greaterThan(0));

      await h.settle();

      expect(h.lifecycle.requestedLevel, kDriverCockpitViewLevelMax);
      expect(h.lifecycle.appliedLevel, kDriverCockpitViewLevelMax);
      expect(h.cameraStarts, lessThanOrEqualTo(2));
      expect(h.routeRestores, lessThanOrEqualTo(h.cameraStarts));
      expect(h.routeRestores, greaterThanOrEqualTo(1));
      expect(h.lifecycle.cameraInFlight, isFalse);
      expect(h.unhandledErrors, isEmpty);
    });

    test('alternating rapid +/− taps settle on latest desired level', () async {
      final h = _PressureHarness();
      // 7→8→7→8→7→8→9
      h.tap(increase: true, now: t0);
      h.tap(increase: false, now: t0);
      h.tap(increase: true, now: t0);
      h.tap(increase: false, now: t0);
      h.tap(increase: true, now: t0);
      h.tap(increase: true, now: t0);
      expect(h.selectedLevel, 9);

      await h.settle();
      expect(h.lifecycle.appliedLevel, 9);
      expect(h.maxInflightObserved, 1);
      expect(h.cameraStarts, lessThanOrEqualTo(2));
      expect(h.routeRestores, lessThanOrEqualTo(h.cameraStarts));
    });

    test('superseded intermediate levels launch no camera work', () async {
      final h = _PressureHarness(autoComplete: false);
      h.tap(increase: true, now: t0); // 8
      h.tap(increase: true, now: t0); // 9 coalesced
      h.tap(increase: true, now: t0); // 10 coalesced
      expect(h.cameraStarts, 1);
      expect(h.routeRestores, 0);

      h.completeOpenFlight();
      await h.settle();

      expect(h.lifecycle.appliedLevel, 10);
      expect(h.cameraStarts, 2);
      expect(h.routeRestores, 1);
      expect(h.appliedCameraLevels, isNot(contains(9)));
    });

    test('route restore occurs only for applied final states', () async {
      final h = _PressureHarness();
      for (var i = 0; i < 5; i++) {
        h.tap(increase: true, now: t0);
      }
      await h.settle();

      expect(h.routeRestores, h.successfulApplies);
      expect(h.routeRestores, lessThanOrEqualTo(2));
      expect(
        h.routeRestoreLevels,
        everyElement(isIn(h.appliedCameraLevels)),
        reason: 'restore only for camera states that were actually applied',
      );
      expect(h.routeRestoreLevels, isNot(contains(8)));
    });

    test('camera failure releases ownership and applies pending latest',
        () async {
      final h = _PressureHarness(autoComplete: false);
      h.tap(increase: true, now: t0);
      h.tap(increase: true, now: t0);
      expect(h.cameraStarts, 1);

      h.failOpenFlight();
      await h.settle();

      expect(h.lifecycle.appliedLevel, 9);
      expect(h.cameraStarts, 2);
      expect(h.lifecycle.cameraInFlight, isFalse);
      expect(h.unhandledErrors, isEmpty);
    });

    test('timeout releases ownership and applies pending latest', () async {
      final h = _PressureHarness(autoComplete: false);
      h.tap(increase: true, now: t0);
      h.tap(increase: true, now: t0);
      h.timeoutOpenFlight();
      await h.settle();

      expect(h.lifecycle.appliedLevel, 9);
      expect(h.cameraStarts, 2);
      expect(h.lifecycle.cameraInFlight, isFalse);
      expect(h.unhandledErrors, isEmpty);
    });

    test('teardown with pending input does not escape async errors', () async {
      final h = _PressureHarness(autoComplete: false);
      h.tap(increase: true, now: t0);
      h.tap(increase: true, now: t0);
      h.disposed = true;
      h.lifecycle.reset();
      h.completeOpenFlight();
      await h.settle();

      expect(h.lifecycle.cameraInFlight, isFalse);
      expect(h.unhandledErrors, isEmpty);
    });

    test('pressure log lines stay free of coordinates and booking ids', () {
      final lines = <String>[];
      logViewZoomPressure(
        event: 'zoom_input_received',
        currentLevel: 7,
        desiredLevel: 8,
        generation: 1,
        inflight: false,
        emit: lines.add,
      );
      expect(lines, hasLength(1));
      expect(lines.single, contains('event=zoom_input_received'));
      expect(lines.single, isNot(contains('lat')));
      expect(lines.single, isNot(contains('lon')));
      expect(lines.single, isNot(contains('booking')));
      expect(lines.single, isNot(contains('token')));
    });
  });
}

/// Mirrors production pressure-guard wiring for View +/- bursts.
class _PressureHarness {
  _PressureHarness({this.autoComplete = true});

  final DriverCockpitViewZoomLifecycle lifecycle = DriverCockpitViewZoomLifecycle();
  final bool autoComplete;

  int selectedLevel = kDriverCockpitViewLevelDefault;
  int cameraStarts = 0;
  int successfulApplies = 0;
  int routeRestores = 0;
  int coalescedCount = 0;
  int maxInflightObserved = 0;
  bool disposed = false;
  bool failNextFlight = false;
  bool timeoutNextFlight = false;

  final List<int> appliedCameraLevels = <int>[];
  final List<int> routeRestoreLevels = <int>[];
  final List<Object> unhandledErrors = <Object>[];

  final List<Completer<void>> _openFlights = <Completer<void>>[];
  final List<Future<void>> _running = <Future<void>>[];

  void tap({required bool increase, required DateTime now}) {
    selectedLevel = stepDriverCockpitViewLevel(
      selectedLevel,
      increase: increase,
    );
    final input = lifecycle.acceptDesiredLevel(selectedLevel, now);
    if (input.decision == DriverCockpitViewZoomInputDecision.coalesced) {
      coalescedCount += 1;
      return;
    }
    if (input.decision == DriverCockpitViewZoomInputDecision.unchanged) {
      return;
    }
    _running.add(_apply(input.generation, now, pendingLatest: false));
  }

  Future<void> _apply(
    int generation,
    DateTime now, {
    required bool pendingLatest,
  }) async {
    if (disposed) return;
    if (lifecycle.shouldIgnoreStaleCamera(generation)) return;
    if (!lifecycle.beginCamera(generation)) return;

    cameraStarts += 1;
    if (lifecycle.cameraInFlight) {
      maxInflightObserved = 1;
    }
    final targetLevel =
        lifecycle.inFlightTargetLevel ?? lifecycle.requestedLevel;
    var needsRerun = false;
    var appliedThisFlight = false;
    try {
      await _flight();
      if (disposed) {
        lifecycle.cancelCamera(requestGeneration: generation);
        return;
      }
      needsRerun = lifecycle.finishCamera(
        requestGeneration: generation,
        appliedLevel: targetLevel,
        now: now,
      );
      if (!lifecycle.shouldIgnoreStaleCamera(generation)) {
        appliedThisFlight = true;
        successfulApplies += 1;
        appliedCameraLevels.add(targetLevel);
      }
    } catch (error) {
      needsRerun = lifecycle.releaseForFailure(requestGeneration: generation);
      // Captured locally — must not escape as an unhandled async error.
      if (error is! TimeoutException && error is! StateError) {
        unhandledErrors.add(error);
      }
    } finally {
      if (lifecycle.cameraInFlight &&
          lifecycle.inFlightGeneration == generation) {
        lifecycle.cancelCamera(requestGeneration: generation);
      }
      if (appliedThisFlight && !disposed) {
        routeRestores += 1;
        routeRestoreLevels.add(targetLevel);
      }
      if (needsRerun &&
          !disposed &&
          !lifecycle.latestTargetAlreadyOwned()) {
        _running.add(
          _apply(lifecycle.generation, now, pendingLatest: true),
        );
      }
    }
  }

  Future<void> _flight() {
    if (failNextFlight) {
      failNextFlight = false;
      return Future<void>.error(StateError('camera platform failure'));
    }
    if (timeoutNextFlight) {
      timeoutNextFlight = false;
      return Future<void>.error(
        TimeoutException('camera timeout'),
      );
    }
    final completer = Completer<void>();
    _openFlights.add(completer);
    if (autoComplete) {
      scheduleMicrotask(() {
        if (!completer.isCompleted) completer.complete();
      });
    }
    return completer.future;
  }

  void completeOpenFlight() {
    for (final c in List<Completer<void>>.of(_openFlights)) {
      if (!c.isCompleted) c.complete();
    }
  }

  void failOpenFlight() {
    for (final c in List<Completer<void>>.of(_openFlights)) {
      if (!c.isCompleted) c.completeError(StateError('camera platform failure'));
    }
  }

  void timeoutOpenFlight() {
    for (final c in List<Completer<void>>.of(_openFlights)) {
      if (!c.isCompleted) {
        c.completeError(TimeoutException('camera timeout'));
      }
    }
  }

  Future<void> settle() async {
    for (var i = 0; i < 80; i++) {
      // Settling always drains follow-up flights. Callers that need a paused
      // in-flight op use fail/timeout/complete before invoking settle.
      completeOpenFlight();
      final pending = List<Future<void>>.of(_running);
      if (pending.isEmpty && _openFlights.every((c) => c.isCompleted)) {
        break;
      }
      _running.clear();
      await Future.wait(
        pending.map(
          (f) => f.catchError((Object e) {
            // Expected camera failures are handled inside _apply.
            if (e is! TimeoutException && e is! StateError) {
              unhandledErrors.add(e);
            }
          }),
        ),
      );
    }
  }
}
