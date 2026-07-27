import 'package:flutter/foundation.dart';

import 'navigation_driver_cockpit_camera.dart';

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: manual View +/- ownership window.
const int kDriverCockpitViewZoomManualOwnershipMs = 400;

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: responsive manual camera transition targets.
const int kDriverCockpitViewZoomAnimationMsTablet = 240;
const int kDriverCockpitViewZoomAnimationMsPhone = 220;

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: latest-request-wins manual view zoom state.
class DriverCockpitViewZoomLifecycle {
  int _generation = 0;
  int _requestedLevel = kDriverCockpitViewLevelDefault;
  int? _appliedLevel;
  bool _cameraInFlight = false;
  int? _inFlightGeneration;
  DateTime? _manualOwnershipUntil;

  int get generation => _generation;

  int get requestedLevel => _requestedLevel;

  int? get appliedLevel => _appliedLevel;

  bool get cameraInFlight => _cameraInFlight;

  int? get inFlightGeneration => _inFlightGeneration;

  /// Records a manual +/- tap and extends passive-follow suppression.
  int requestManualLevel(int level, DateTime now) {
    _generation += 1;
    _requestedLevel = clampDriverCockpitViewLevel(level);
    _manualOwnershipUntil = now.add(
      const Duration(milliseconds: kDriverCockpitViewZoomManualOwnershipMs),
    );
    return _generation;
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
  /// NAV-ZOOM-FIELD-REPAIR-1: the manual adjustment path owns at most one
  /// active camera request. A newer generation arriving mid-flight no longer
  /// starts a second concurrent flight — it only bumps [generation], which is
  /// the single coalesced latest pending target. The in-flight owner replays
  /// to that newest target when it completes. Starting a concurrent flight
  /// per tap is what produced roughly 2N platform-channel camera calls for N
  /// rapid taps and amplified the DartMessenger backlog.
  bool beginCamera(int requestGeneration) {
    if (shouldIgnoreStaleCamera(requestGeneration)) return false;
    if (_cameraInFlight) return false;
    _cameraInFlight = true;
    _inFlightGeneration = requestGeneration;
    return true;
  }

  /// True when the newest target is already owned, so a superseded flight
  /// must not schedule a duplicate replay.
  ///
  /// NAV-ZOOM-FIELD-REPAIR-1: covers both the case where the newest
  /// generation already has a flight running and the case where a completed
  /// flight already applied the newest requested level.
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
