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

  bool beginCamera(int requestGeneration) {
    if (_cameraInFlight) return false;
    if (shouldIgnoreStaleCamera(requestGeneration)) return false;
    _cameraInFlight = true;
    _inFlightGeneration = requestGeneration;
    return true;
  }

  void cancelCamera() {
    _cameraInFlight = false;
    _inFlightGeneration = null;
  }

  /// Returns true when a newer manual request should run after this flight.
  bool finishCamera({
    required int requestGeneration,
    required int appliedLevel,
    required DateTime now,
  }) {
    _cameraInFlight = false;
    _inFlightGeneration = null;
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
