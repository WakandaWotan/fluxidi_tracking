import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_view_zoom.dart';

/// NAV-ZOOM-FIELD-REPAIR-1 — camera replay de-duplication.
///
/// Field defect: a superseded camera flight scheduled an extra replay in its
/// `finally` while the newest generation already had its own flight running,
/// so N rapid View +/- taps could issue roughly 2N platform-channel camera
/// calls and amplify the observed DartMessenger backlog.
///
/// [_CameraHarness] mirrors the production
/// `_applyDriverCockpitViewZoomCamera` control flow exactly. [_LegacyLifecycle]
/// reproduces the pre-repair lifecycle so the before/after call counts are
/// measured against the real defect and not against an assumption.
void main() {
  final t0 = DateTime(2026, 7, 27, 10);

  group('NAV-ZOOM-FIELD-REPAIR-1 camera call amplification', () {
    test('one tap produces exactly one newest-target camera request', () async {
      final h = _CameraHarness();
      h.tap(increase: true, now: t0);
      await h.settle();

      expect(h.flyToCalls, 1);
      expect(h.appliedTargets, <int>[8]);
      expect(h.lifecycle.appliedLevel, 8);
      expect(h.lifecycle.cameraInFlight, isFalse);
    });

    test('N rapid taps no longer produce ~2N camera calls', () async {
      for (final taps in <int>[2, 3, 5, 8]) {
        final legacy = _CameraHarness(lifecycle: _LegacyLifecycle());
        for (var i = 0; i < taps; i++) {
          legacy.tap(increase: true, now: t0);
        }
        await legacy.settle();

        final repaired = _CameraHarness();
        for (var i = 0; i < taps; i++) {
          repaired.tap(increase: true, now: t0);
        }
        await repaired.settle();

        // Before: one flight per tap plus a duplicate replay per superseded
        // flight.
        expect(
          legacy.flyToCalls,
          greaterThanOrEqualTo(2 * taps - 1),
          reason: 'legacy amplification for $taps taps',
        );

        // After: at most one active flight plus one coalesced replay.
        expect(
          repaired.flyToCalls,
          lessThanOrEqualTo(2),
          reason: 'repaired call count for $taps taps',
        );
        expect(
          repaired.flyToCalls,
          lessThan(legacy.flyToCalls),
          reason: 'repaired must be cheaper than legacy for $taps taps',
        );
      }
    });

    test('rapid taps still settle on the newest selected level', () async {
      final h = _CameraHarness();
      for (var i = 0; i < 5; i++) {
        h.tap(increase: true, now: t0);
      }
      expect(h.selectedLevel, 12, reason: 'level changes synchronously per tap');

      await h.settle();
      expect(h.lifecycle.requestedLevel, 12);
      expect(h.lifecycle.appliedLevel, 12);
      expect(h.appliedTargets.last, 12);
    });

    test('mixed rapid +/- taps settle on the newest level', () async {
      final h = _CameraHarness();
      h.tap(increase: true, now: t0);
      h.tap(increase: true, now: t0);
      h.tap(increase: false, now: t0);
      h.tap(increase: true, now: t0);
      expect(h.selectedLevel, 9);

      await h.settle();
      expect(h.lifecycle.appliedLevel, 9);
      expect(h.flyToCalls, lessThanOrEqualTo(2));
    });

    test('sequential taps that do not overlap each get their own flight', () async {
      final h = _CameraHarness();
      for (var i = 0; i < 3; i++) {
        h.tap(increase: true, now: t0);
        await h.settle();
      }
      expect(h.flyToCalls, 3);
      expect(h.appliedTargets, <int>[8, 9, 10]);
    });
  });

  group('NAV-ZOOM-FIELD-REPAIR-1 ownership contract', () {
    test('a second concurrent manual flight is refused, not queued twice', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(8, t0);
      expect(lifecycle.beginCamera(g1), isTrue);

      final g2 = lifecycle.requestManualLevel(9, t0);
      expect(
        lifecycle.beginCamera(g2),
        isFalse,
        reason: 'only one active manual camera request is allowed',
      );
      expect(lifecycle.inFlightGeneration, g1);
      expect(
        lifecycle.requestedLevel,
        9,
        reason: 'the newest level stays the single coalesced pending target',
      );
    });

    test('superseded finally does not replay when the newest gen owns it', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(8, t0);
      expect(lifecycle.beginCamera(g1), isTrue);

      // Older flight released ownership, newest generation took it over.
      lifecycle.cancelCamera(requestGeneration: g1);
      final g2 = lifecycle.requestManualLevel(10, t0);
      expect(lifecycle.beginCamera(g2), isTrue);

      expect(
        lifecycle.latestTargetAlreadyOwned(),
        isTrue,
        reason: 'the newest generation already owns a flight',
      );
    });

    test('superseded finally does not replay an already applied target', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(9, t0);
      expect(lifecycle.beginCamera(g1), isTrue);
      expect(
        lifecycle.finishCamera(requestGeneration: g1, appliedLevel: 9, now: t0),
        isFalse,
      );
      expect(lifecycle.latestTargetAlreadyOwned(), isTrue);
    });

    test('a genuinely unowned newest target is still replayed', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(8, t0);
      expect(lifecycle.beginCamera(g1), isTrue);
      lifecycle.requestManualLevel(11, t0);
      expect(
        lifecycle.finishCamera(requestGeneration: g1, appliedLevel: 8, now: t0),
        isTrue,
        reason: 'a newer generation exists, so a rerun is required',
      );
      expect(
        lifecycle.latestTargetAlreadyOwned(),
        isFalse,
        reason: 'nothing owns level 11 yet',
      );
    });

    test('only the latest generation may apply', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(6, t0);
      lifecycle.requestManualLevel(11, t0);
      expect(lifecycle.shouldIgnoreStaleCamera(g1), isTrue);
      expect(
        lifecycle.finishCamera(requestGeneration: g1, appliedLevel: 6, now: t0),
        isTrue,
      );
      expect(
        lifecycle.appliedLevel,
        isNull,
        reason: 'a stale generation must never overwrite the newest target',
      );
    });

    test('a stale cancel cannot clear the newest owner', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g1 = lifecycle.requestManualLevel(8, t0);
      expect(lifecycle.beginCamera(g1), isTrue);
      lifecycle.cancelCamera(requestGeneration: g1);

      final g2 = lifecycle.requestManualLevel(10, t0);
      expect(lifecycle.beginCamera(g2), isTrue);

      lifecycle.cancelCamera(requestGeneration: g1);
      expect(lifecycle.cameraInFlight, isTrue);
      expect(lifecycle.inFlightGeneration, g2);
    });

    test('normal completion clears ownership without a false stuck state', () async {
      final h = _CameraHarness();
      h.tap(increase: true, now: t0);
      await h.settle();

      expect(h.lifecycle.cameraInFlight, isFalse);
      expect(h.lifecycle.inFlightGeneration, isNull);
      expect(h.lifecycle.latestTargetAlreadyOwned(), isTrue);

      h.tap(increase: true, now: t0);
      await h.settle();
      expect(h.flyToCalls, 2);
      expect(h.lifecycle.appliedLevel, 9);
    });

    test('timeout or error self-heals and permits the next manual command', () async {
      final h = _CameraHarness();
      h.failNextFlight = true;
      h.tap(increase: true, now: t0);
      await h.settle();

      expect(h.lifecycle.cameraInFlight, isFalse);
      expect(h.lifecycle.inFlightGeneration, isNull);

      h.tap(increase: true, now: t0);
      await h.settle();
      expect(h.lifecycle.appliedLevel, 9);
      expect(h.lifecycle.cameraInFlight, isFalse);
    });

    test('an error while a newer level is pending still replays once', () async {
      final h = _CameraHarness(autoComplete: false);
      h.tap(increase: true, now: t0);
      h.tap(increase: true, now: t0);
      expect(h.flyToCalls, 1);

      h.failOpenFlight();
      await h.settle();

      expect(h.lifecycle.appliedLevel, 9, reason: 'newest press is not lost');
      expect(h.flyToCalls, 2);
      expect(h.lifecycle.cameraInFlight, isFalse);
    });

    test('no permanently stuck in-flight state after a long tap burst', () async {
      final h = _CameraHarness();
      for (var i = 0; i < 12; i++) {
        h.tap(increase: i.isEven, now: t0);
      }
      await h.settle();

      expect(h.lifecycle.cameraInFlight, isFalse);
      expect(h.lifecycle.inFlightGeneration, isNull);
      expect(h.lifecycle.appliedLevel, h.lifecycle.requestedLevel);
    });

    test('passive follow is suppressed only inside the manual window', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      lifecycle.requestManualLevel(9, t0);
      expect(lifecycle.blocksPassiveFollow(t0), isTrue);
      expect(
        lifecycle.blocksPassiveFollow(
          t0.add(
            const Duration(
              milliseconds: kDriverCockpitViewZoomManualOwnershipMs + 1,
            ),
          ),
        ),
        isFalse,
      );
    });

    test('passive follow keeps targeting the selected view level', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      lifecycle.requestManualLevel(11, t0);
      final selected = lifecycle.requestedLevel;

      final out = resolveDriverCockpitCameraProfile(
        const DriverCockpitCameraProfileInput(
          currentZoom: 19.1,
          currentPitch: 77.0,
          isTablet: false,
          isLandscape: false,
          safeTop: 24,
          safeBottom: 24,
          screenHeight: 2340,
        ),
        viewLevel: 11,
      );

      final target = driverCockpitViewLevelTargetZoom(
        isTablet: false,
        isLandscape: false,
        level: selected,
      );
      // Follow smoothing steps toward the selected level, never back to the
      // default level 7 target.
      expect(out.zoom, greaterThan(19.1));
      expect(out.zoom, lessThanOrEqualTo(target));
    });

    test('reset returns the lifecycle to a clean default state', () {
      final lifecycle = DriverCockpitViewZoomLifecycle();
      final g = lifecycle.requestManualLevel(12, t0);
      lifecycle.beginCamera(g);
      lifecycle.reset();

      expect(lifecycle.generation, 0);
      expect(lifecycle.requestedLevel, kDriverCockpitViewLevelDefault);
      expect(lifecycle.appliedLevel, isNull);
      expect(lifecycle.cameraInFlight, isFalse);
      expect(lifecycle.inFlightGeneration, isNull);
      expect(lifecycle.blocksPassiveFollow(t0), isFalse);
    });
  });
}

/// Mirrors the production `_applyDriverCockpitViewZoomCamera` control flow.
class _CameraHarness {
  _CameraHarness({DriverCockpitViewZoomLifecycle? lifecycle, this.autoComplete = true})
    : lifecycle = lifecycle ?? DriverCockpitViewZoomLifecycle();

  final DriverCockpitViewZoomLifecycle lifecycle;

  /// When false, flights stay open until [completeOpenFlight] / [failOpenFlight].
  final bool autoComplete;

  int selectedLevel = kDriverCockpitViewLevelDefault;
  int flyToCalls = 0;
  final List<int> appliedTargets = <int>[];
  bool failNextFlight = false;

  final List<Completer<void>> _openFlights = <Completer<void>>[];
  final List<Future<void>> _running = <Future<void>>[];

  /// The synchronous part of a View +/- press.
  void tap({required bool increase, required DateTime now}) {
    selectedLevel = stepDriverCockpitViewLevel(selectedLevel, increase: increase);
    final generation = lifecycle.requestManualLevel(selectedLevel, now);
    _running.add(_apply(generation, now));
  }

  Future<void> _apply(int generation, DateTime now) async {
    if (lifecycle.shouldIgnoreStaleCamera(generation)) return;
    if (!lifecycle.beginCamera(generation)) return;

    flyToCalls += 1;
    final levelAtStart = selectedLevel;
    var needsRerun = false;
    try {
      await _flight();
      appliedTargets.add(levelAtStart);
      needsRerun = lifecycle.finishCamera(
        requestGeneration: generation,
        appliedLevel: levelAtStart,
        now: now,
      );
    } catch (_) {
      needsRerun = lifecycle.shouldIgnoreStaleCamera(generation);
      lifecycle.cancelCamera(requestGeneration: generation);
    } finally {
      if (lifecycle.cameraInFlight &&
          lifecycle.inFlightGeneration == generation) {
        lifecycle.cancelCamera(requestGeneration: generation);
      }
      if (needsRerun && !lifecycle.latestTargetAlreadyOwned()) {
        _running.add(_apply(lifecycle.generation, now));
      }
    }
  }

  Future<void> _flight() {
    if (failNextFlight) {
      failNextFlight = false;
      return Future<void>.error(StateError('camera timeout'));
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

  void failOpenFlight() {
    for (final c in _openFlights) {
      if (!c.isCompleted) c.completeError(StateError('camera timeout'));
    }
  }

  Future<void> settle() async {
    for (var i = 0; i < 50; i++) {
      for (final c in List<Completer<void>>.of(_openFlights)) {
        if (!c.isCompleted) c.complete();
      }
      final pending = List<Future<void>>.of(_running);
      if (pending.isEmpty) break;
      _running.clear();
      await Future.wait(pending);
      if (_running.isEmpty) break;
    }
  }
}

/// Pre-repair lifecycle: allowed a concurrent flight per generation and had no
/// duplicate-replay guard. Retained here only to measure the amplification the
/// repair removes.
class _LegacyLifecycle implements DriverCockpitViewZoomLifecycle {
  int _generation = 0;
  int _requestedLevel = kDriverCockpitViewLevelDefault;
  int? _appliedLevel;
  bool _cameraInFlight = false;
  int? _inFlightGeneration;
  DateTime? _manualOwnershipUntil;

  @override
  int get generation => _generation;

  @override
  int get requestedLevel => _requestedLevel;

  @override
  int? get appliedLevel => _appliedLevel;

  @override
  bool get cameraInFlight => _cameraInFlight;

  @override
  int? get inFlightGeneration => _inFlightGeneration;

  @override
  int requestManualLevel(int level, DateTime now) {
    _generation += 1;
    _requestedLevel = clampDriverCockpitViewLevel(level);
    _manualOwnershipUntil = now.add(
      const Duration(milliseconds: kDriverCockpitViewZoomManualOwnershipMs),
    );
    return _generation;
  }

  @override
  bool blocksPassiveFollow(DateTime now) {
    final until = _manualOwnershipUntil;
    if (until == null) return false;
    return now.isBefore(until);
  }

  @override
  bool shouldIgnoreStaleCamera(int requestGeneration) =>
      requestGeneration != _generation;

  @override
  bool beginCamera(int requestGeneration) {
    if (shouldIgnoreStaleCamera(requestGeneration)) return false;
    _cameraInFlight = true;
    _inFlightGeneration = requestGeneration;
    return true;
  }

  @override
  bool latestTargetAlreadyOwned() => false;

  @override
  void cancelCamera({int? requestGeneration}) {
    if (requestGeneration != null &&
        _inFlightGeneration != null &&
        _inFlightGeneration != requestGeneration) {
      return;
    }
    _cameraInFlight = false;
    _inFlightGeneration = null;
  }

  @override
  bool finishCamera({
    required int requestGeneration,
    required int appliedLevel,
    required DateTime now,
  }) {
    if (_inFlightGeneration == null ||
        _inFlightGeneration == requestGeneration) {
      _cameraInFlight = false;
      _inFlightGeneration = null;
    }
    if (!shouldIgnoreStaleCamera(requestGeneration)) {
      _appliedLevel = clampDriverCockpitViewLevel(appliedLevel);
    }
    return shouldIgnoreStaleCamera(requestGeneration);
  }

  @override
  void reset() {
    _generation = 0;
    _requestedLevel = kDriverCockpitViewLevelDefault;
    _appliedLevel = null;
    _cameraInFlight = false;
    _inFlightGeneration = null;
    _manualOwnershipUntil = null;
  }
}
