import 'package:flutter/foundation.dart';

import 'navigation_driver_cockpit_camera.dart';

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: manual View +/- ownership window.
const int kDriverCockpitViewZoomManualOwnershipMs = 400;

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: responsive manual camera transition targets.
const int kDriverCockpitViewZoomAnimationMsTablet = 240;
const int kDriverCockpitViewZoomAnimationMsPhone = 220;

/// RAPID-ZOOM-INPUT-PRESSURE-GUARD-1: decision for one View +/- press.
enum DriverCockpitViewZoomInputDecision {
  /// Level did not change (clamp) and no camera work is required.
  unchanged,

  /// Desired level updated; caller must start the single camera operation now.
  startCamera,

  /// Desired level updated while a camera op is in flight — capacity-one pending.
  coalesced,
}

/// RAPID-ZOOM-INPUT-PRESSURE-GUARD-1: result of accepting one desired level.
class DriverCockpitViewZoomInputResult {
  const DriverCockpitViewZoomInputResult({
    required this.decision,
    required this.generation,
    required this.currentLevel,
    required this.desiredLevel,
    required this.inflight,
    required this.hasPendingLatest,
  });

  final DriverCockpitViewZoomInputDecision decision;
  final int generation;
  final int currentLevel;
  final int desiredLevel;
  final bool inflight;
  final bool hasPendingLatest;
}

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1 / RAPID-ZOOM-INPUT-PRESSURE-GUARD-1:
/// latest-desired-wins manual view zoom owner with capacity-one pending.
///
/// At most one camera operation may be in flight. Additional taps only update
/// [requestedLevel] (pending capacity = 1). They must not enqueue one camera
/// operation or route restore per tap.
class DriverCockpitViewZoomLifecycle {
  int _generation = 0;
  int _requestedLevel = kDriverCockpitViewLevelDefault;
  int? _appliedLevel;
  bool _cameraInFlight = false;
  int? _inFlightGeneration;
  int? _inFlightTargetLevel;
  DateTime? _manualOwnershipUntil;

  int get generation => _generation;

  int get requestedLevel => _requestedLevel;

  int? get appliedLevel => _appliedLevel;

  bool get cameraInFlight => _cameraInFlight;

  int? get inFlightGeneration => _inFlightGeneration;

  /// Level the active camera operation was started for (null when idle).
  int? get inFlightTargetLevel => _inFlightTargetLevel;

  /// Pending capacity is structurally one: a single [requestedLevel] slot.
  bool get hasPendingLatest =>
      _cameraInFlight &&
      _inFlightGeneration != null &&
      _generation != _inFlightGeneration;

  /// True when pending capacity is already occupied (never grows beyond one).
  bool get pendingAtCapacity => hasPendingLatest;

  /// Records a manual +/- tap and extends passive-follow suppression.
  int requestManualLevel(int level, DateTime now) {
    _generation += 1;
    _requestedLevel = clampDriverCockpitViewLevel(level);
    _manualOwnershipUntil = now.add(
      const Duration(milliseconds: kDriverCockpitViewZoomManualOwnershipMs),
    );
    return _generation;
  }

  /// RAPID-ZOOM-INPUT-PRESSURE-GUARD-1: accept a stepped/clamped desired level.
  ///
  /// Returns whether the caller should start a camera operation. While one
  /// operation is active, further level changes coalesce onto the single
  /// pending desired level and must not start additional work.
  DriverCockpitViewZoomInputResult acceptDesiredLevel(int level, DateTime now) {
    final desired = clampDriverCockpitViewLevel(level);
    final current = _appliedLevel ?? _requestedLevel;

    if (desired == _requestedLevel) {
      if (!_cameraInFlight &&
          (_appliedLevel == null || _appliedLevel != desired)) {
        final generation = requestManualLevel(desired, now);
        return DriverCockpitViewZoomInputResult(
          decision: DriverCockpitViewZoomInputDecision.startCamera,
          generation: generation,
          currentLevel: current,
          desiredLevel: desired,
          inflight: false,
          hasPendingLatest: false,
        );
      }
      return DriverCockpitViewZoomInputResult(
        decision: DriverCockpitViewZoomInputDecision.unchanged,
        generation: _generation,
        currentLevel: current,
        desiredLevel: desired,
        inflight: _cameraInFlight,
        hasPendingLatest: hasPendingLatest,
      );
    }

    final generation = requestManualLevel(desired, now);
    if (_cameraInFlight) {
      return DriverCockpitViewZoomInputResult(
        decision: DriverCockpitViewZoomInputDecision.coalesced,
        generation: generation,
        currentLevel: current,
        desiredLevel: desired,
        inflight: true,
        hasPendingLatest: true,
      );
    }
    return DriverCockpitViewZoomInputResult(
      decision: DriverCockpitViewZoomInputDecision.startCamera,
      generation: generation,
      currentLevel: current,
      desiredLevel: desired,
      inflight: false,
      hasPendingLatest: false,
    );
  }

  bool blocksPassiveFollow(DateTime now) {
    final until = _manualOwnershipUntil;
    if (until == null) return false;
    return now.isBefore(until);
  }

  bool shouldIgnoreStaleCamera(int requestGeneration) {
    return requestGeneration != _generation;
  }

  /// Begin camera ownership for [requestGeneration].
  ///
  /// NAV-CAMERA-INFLIGHT-SELF-HEAL-1: stale generations are rejected.
  ///
  /// NAV-ZOOM-FIELD-REPAIR-1 / RAPID-ZOOM-INPUT-PRESSURE-GUARD-1: at most one
  /// active camera request. A newer generation arriving mid-flight only bumps
  /// [generation] / [requestedLevel] (capacity-one pending). The in-flight
  /// owner replays to that newest target when it completes.
  bool beginCamera(int requestGeneration) {
    if (shouldIgnoreStaleCamera(requestGeneration)) return false;
    if (_cameraInFlight) return false;
    _cameraInFlight = true;
    _inFlightGeneration = requestGeneration;
    _inFlightTargetLevel = _requestedLevel;
    return true;
  }

  /// True when the newest target is already owned, so a superseded flight
  /// must not schedule a duplicate replay.
  bool latestTargetAlreadyOwned() {
    if (_cameraInFlight && _inFlightGeneration == _generation) return true;
    if (_appliedLevel != null && _appliedLevel == _requestedLevel) return true;
    return false;
  }

  void cancelCamera({int? requestGeneration}) {
    if (requestGeneration != null &&
        _inFlightGeneration != null &&
        _inFlightGeneration != requestGeneration) {
      return;
    }
    _cameraInFlight = false;
    _inFlightGeneration = null;
    _inFlightTargetLevel = null;
  }

  /// Failure / timeout release for [requestGeneration].
  ///
  /// Returns true when a newer desired level should be started after release.
  bool releaseForFailure({required int requestGeneration}) {
    final needsRerun = shouldIgnoreStaleCamera(requestGeneration);
    cancelCamera(requestGeneration: requestGeneration);
    return needsRerun && !latestTargetAlreadyOwned();
  }

  /// Returns true when a newer manual request should run after this flight.
  ///
  /// Only the matching in-flight generation may clear ownership — an older
  /// finish must not wipe a superseding View +/- owner.
  bool finishCamera({
    required int requestGeneration,
    required int appliedLevel,
    required DateTime now,
  }) {
    if (_inFlightGeneration == null ||
        _inFlightGeneration == requestGeneration) {
      _cameraInFlight = false;
      _inFlightGeneration = null;
      _inFlightTargetLevel = null;
    }
    if (!shouldIgnoreStaleCamera(requestGeneration)) {
      _appliedLevel = clampDriverCockpitViewLevel(appliedLevel);
    }
    return shouldIgnoreStaleCamera(requestGeneration);
  }

  void reset() {
    _generation = 0;
    _requestedLevel = kDriverCockpitViewLevelDefault;
    _appliedLevel = null;
    _cameraInFlight = false;
    _inFlightGeneration = null;
    _inFlightTargetLevel = null;
    _manualOwnershipUntil = null;
  }
}

int resolveDriverCockpitViewZoomAnimationMs({
  required bool isTablet,
  required bool manualViewAdjust,
  int defaultFollowAnimationMs = 300,
}) {
  if (!manualViewAdjust) return defaultFollowAnimationMs;
  return isTablet
      ? kDriverCockpitViewZoomAnimationMsTablet
      : kDriverCockpitViewZoomAnimationMsPhone;
}

String driverCockpitViewZoomFormFactorLabel({required bool isTablet}) {
  return isTablet ? 'tablet' : 'phone';
}

String? _lastNavPresViewZoomLogSignature;

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: bounded diagnostics (no coordinates / PII).
void logNavPresViewZoom({
  required int requestedLevel,
  required int? appliedLevel,
  required int generation,
  required String phase,
  int? durationMs,
  required String formFactor,
}) {
  final signature =
      '$requestedLevel|${appliedLevel ?? 'na'}|$generation|$phase|'
      '${durationMs ?? 'na'}|$formFactor';
  if (signature == _lastNavPresViewZoomLogSignature) return;
  _lastNavPresViewZoomLogSignature = signature;
  final buffer = StringBuffer(
    '[NAV_PRES_VIEW_ZOOM] requestedLevel=$requestedLevel '
    'appliedLevel=${appliedLevel ?? 'na'} generation=$generation '
    'phase=$phase formFactor=$formFactor',
  );
  if (durationMs != null) {
    buffer.write(' durationMs=$durationMs');
  }
  debugPrint(buffer.toString());
}

String? _lastViewZoomPressureLogSignature;

/// RAPID-ZOOM-INPUT-PRESSURE-GUARD-1: sanitized pressure-guard diagnostic line.
void logViewZoomPressure({
  required String event,
  required int currentLevel,
  required int desiredLevel,
  required int generation,
  required bool inflight,
  int? durationMs,
  void Function(String line)? emit,
}) {
  final signature =
      '$event|$currentLevel|$desiredLevel|$generation|$inflight|'
      '${durationMs ?? 'na'}';
  if (signature == _lastViewZoomPressureLogSignature &&
      event != 'zoom_input_received') {
    return;
  }
  _lastViewZoomPressureLogSignature = signature;
  final buffer = StringBuffer(
    '[VIEW_ZOOM_PRESSURE] event=$event '
    'currentLevel=$currentLevel desiredLevel=$desiredLevel '
    'generation=$generation inflight=${inflight ? 'yes' : 'no'}',
  );
  if (durationMs != null) {
    buffer.write(' durationMs=$durationMs');
  }
  final line = buffer.toString();
  if (emit != null) {
    emit(line);
  } else {
    debugPrint(line);
  }
}

@visibleForTesting
void debugResetViewZoomPressureLogSignature() {
  _lastViewZoomPressureLogSignature = null;
  _lastNavPresViewZoomLogSignature = null;
}
