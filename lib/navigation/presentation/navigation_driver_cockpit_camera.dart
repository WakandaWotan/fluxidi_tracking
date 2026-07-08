import '../driver_navigation_geometry.dart';
import '../driver_navigation_models.dart';
import '../nav_engine/nav_camera_view_mode.dart';

/// Input for NAV-PRES-3A/3B driver cockpit camera tuning.
class DriverCockpitCameraProfileInput {
  final double currentZoom;
  final double currentPitch;
  final bool isTablet;
  final bool isLandscape;
  final double safeTop;
  final double safeBottom;

  const DriverCockpitCameraProfileInput({
    required this.currentZoom,
    required this.currentPitch,
    required this.isTablet,
    required this.isLandscape,
    required this.safeTop,
    required this.safeBottom,
  });
}

/// Input for NAV-PRES-3B chase-camera lookahead center resolution.
class DriverCockpitCameraLookaheadInput {
  final double vehicleLat;
  final double vehicleLon;
  final double bearingDeg;
  final double speedKmh;
  final List<DriverLonLat> routeCoords;
  final int? segmentIndex;
  final double? snappedLat;
  final double? snappedLon;
  final bool hasReliableSnap;
  final double? previousCenterLat;
  final double? previousCenterLon;

  const DriverCockpitCameraLookaheadInput({
    required this.vehicleLat,
    required this.vehicleLon,
    required this.bearingDeg,
    required this.speedKmh,
    this.routeCoords = const <DriverLonLat>[],
    this.segmentIndex,
    this.snappedLat,
    this.snappedLon,
    this.hasReliableSnap = false,
    this.previousCenterLat,
    this.previousCenterLon,
  });
}

/// Resolved cockpit follow-camera parameters (zoom, pitch, padding, center).
class DriverCockpitCameraProfileOutput {
  final double zoom;
  final double pitch;
  final NavCameraViewPadding padding;
  final double? centerLat;
  final double? centerLon;
  final double lookaheadM;
  final String reason;

  const DriverCockpitCameraProfileOutput({
    required this.zoom,
    required this.pitch,
    required this.padding,
    this.centerLat,
    this.centerLon,
    this.lookaheadM = 0,
    required this.reason,
  });
}

/// NAV-PRES-3B: bounded route-alignment diagnostics (no coordinates logged).
class DriverCockpitRouteAlignDiagnostics {
  final double? markerToRouteStartM;
  final double? activeRouteStartDistM;
  final bool snapped;

  const DriverCockpitRouteAlignDiagnostics({
    this.markerToRouteStartM,
    this.activeRouteStartDistM,
    required this.snapped,
  });
}

/// NAV-PRES-3A/3B: bounded zoom/pitch step limits (aligned with NAV-R12-H policy).
const double kDriverCockpitCameraMaxZoomStep = 0.35;
const double kDriverCockpitCameraMaxPitchStep = 3.0;
const double kDriverCockpitCameraMaxCenterStepM = 12.0;
const double kDriverCockpitCameraMinZoom = 13.0;
const double kDriverCockpitCameraMaxZoom = 19.3;
const double kDriverCockpitCameraMinPitch = 44.0;
const double kDriverCockpitCameraMaxPitch = 80.0;

/// NAV-PRES-3C: manual cockpit intensity adjustment bounds.
const double kDriverCockpitCameraManualZoomStep = 0.25;
const double kDriverCockpitCameraManualZoomMinOffset = -1.0;
const double kDriverCockpitCameraManualZoomMaxOffset = 1.0;
const double kDriverCockpitCameraManualPitchStep = 1.0;
const double kDriverCockpitCameraManualPitchMinOffset = -4.0;
const double kDriverCockpitCameraManualPitchMaxOffset = 4.0;

/// NAV-PRES-3A baseline targets (for tests comparing 3B increases).
const double kDriverCockpitCamera3aPhoneZoom = 18.4;
const double kDriverCockpitCamera3aPhonePitch = 71.0;
const double kDriverCockpitCamera3aTabletZoom = 17.6;
const double kDriverCockpitCamera3aTabletPitch = 69.0;

double driverCockpitCameraTargetZoom({required bool isTablet}) {
  return isTablet ? 18.4 : 19.1;
}

double driverCockpitCameraTargetPitch({required bool isTablet}) {
  return isTablet ? 76.0 : 78.0;
}

double clampDriverCockpitManualZoomOffset(double offset) {
  return offset.clamp(
    kDriverCockpitCameraManualZoomMinOffset,
    kDriverCockpitCameraManualZoomMaxOffset,
  );
}

double clampDriverCockpitManualPitchOffset(double offset) {
  return offset.clamp(
    kDriverCockpitCameraManualPitchMinOffset,
    kDriverCockpitCameraManualPitchMaxOffset,
  );
}

/// NAV-PRES-3C: apply manual zoom offset after base target, before smoothing.
double applyDriverCockpitManualZoomTarget({
  required double baseTargetZoom,
  required double manualZoomOffset,
}) {
  final clamped = clampDriverCockpitManualZoomOffset(manualZoomOffset);
  return (baseTargetZoom + clamped).clamp(
    kDriverCockpitCameraMinZoom,
    kDriverCockpitCameraMaxZoom,
  );
}

/// NAV-PRES-3C: apply manual pitch offset after base target, before smoothing.
double applyDriverCockpitManualPitchTarget({
  required double baseTargetPitch,
  required double manualPitchOffset,
}) {
  final clamped = clampDriverCockpitManualPitchOffset(manualPitchOffset);
  return (baseTargetPitch + clamped).clamp(
    kDriverCockpitCameraMinPitch,
    kDriverCockpitCameraMaxPitch,
  );
}

/// NAV-PRES-3C: step session manual zoom offset on +/- tap.
double stepDriverCockpitManualZoomOffset(
  double current, {
  required bool increase,
}) {
  final delta = increase
      ? kDriverCockpitCameraManualZoomStep
      : -kDriverCockpitCameraManualZoomStep;
  return clampDriverCockpitManualZoomOffset(current + delta);
}

/// NAV-PRES-3C: step session manual pitch offset on +/- tap.
double stepDriverCockpitManualPitchOffset(
  double current, {
  required bool increase,
}) {
  final delta = increase
      ? kDriverCockpitCameraManualPitchStep
      : -kDriverCockpitCameraManualPitchStep;
  return clampDriverCockpitManualPitchOffset(current + delta);
}

/// NAV-PRES-3B: speed-scaled lookahead distance for chase-camera framing.
double resolveDriverCockpitLookaheadMeters({required double speedKmh}) {
  final t = (speedKmh / 80.0).clamp(0.0, 1.0);
  return (35.0 + t * 25.0).clamp(35.0, 60.0);
}

/// Ramps [current] toward [target] by at most [maxStep].
double driverCockpitCameraSmoothToward({
  required double current,
  required double target,
  required double maxStep,
  required double min,
  required double max,
}) {
  if (!current.isFinite) {
    return target.clamp(min, max);
  }
  final delta = (target - current).clamp(-maxStep, maxStep);
  return (current + delta).clamp(min, max);
}

NavCameraViewPadding driverCockpitCameraViewPadding({
  required bool isTablet,
  required bool isLandscape,
  required double safeTop,
  required double safeBottom,
}) {
  if (isLandscape) {
    return NavCameraViewPadding(
      top: safeTop + (isTablet ? 24.0 : 28.0),
      bottom: safeBottom + (isTablet ? 172.0 : 188.0),
    );
  }
  if (isTablet) {
    return NavCameraViewPadding(
      top: safeTop + 56.0,
      bottom: safeBottom + 420.0,
    );
  }
  return NavCameraViewPadding(
    top: safeTop + 56.0,
    bottom: safeBottom + 448.0,
  );
}

/// NAV-PRES-3B: chase-camera center on route lookahead or bearing fallback.
DriverCockpitCameraProfileOutput resolveDriverCockpitLookaheadCenter(
  DriverCockpitCameraLookaheadInput input, {
  required double lookaheadM,
}) {
  DriverLonLat? target;
  var reason = 'bearing_lookahead';

  if (input.hasReliableSnap &&
      input.segmentIndex != null &&
      input.snappedLat != null &&
      input.snappedLon != null &&
      input.routeCoords.length >= 2) {
    final i = input.segmentIndex!.clamp(0, input.routeCoords.length - 2);
    target = driverForwardRouteLookaheadPoint(
      input.routeCoords,
      segmentIndex: i,
      snappedLat: input.snappedLat!,
      snappedLon: input.snappedLon!,
      lookaheadM: lookaheadM,
    );
    if (target != null) {
      reason = 'route_lookahead';
    }
  }

  target ??= driverPointAheadOnBearing(
    lat: input.vehicleLat,
    lon: input.vehicleLon,
    bearingDeg: input.bearingDeg,
    distanceM: lookaheadM,
  );

  var center = target;
  if (input.previousCenterLat != null &&
      input.previousCenterLon != null &&
      input.previousCenterLat!.isFinite &&
      input.previousCenterLon!.isFinite) {
    center = driverSmoothGeodesicToward(
      current: DriverLonLat(
        input.previousCenterLon!,
        input.previousCenterLat!,
      ),
      target: target,
      maxStepM: kDriverCockpitCameraMaxCenterStepM,
    );
  }

  return DriverCockpitCameraProfileOutput(
    zoom: 0,
    pitch: 0,
    padding: const NavCameraViewPadding(top: 0, bottom: 0),
    centerLat: center.lat,
    centerLon: center.lon,
    lookaheadM: lookaheadM,
    reason: reason,
  );
}

/// NAV-PRES-3B: route-line alignment diagnostics (diagnosis only).
DriverCockpitRouteAlignDiagnostics resolveDriverCockpitRouteAlignDiagnostics({
  required double vehicleLat,
  required double vehicleLon,
  required List<DriverLonLat> routeCoords,
  required bool hasReliableSnap,
  double? snappedLat,
  double? snappedLon,
}) {
  if (routeCoords.isEmpty) {
    return const DriverCockpitRouteAlignDiagnostics(snapped: false);
  }
  final vehicle = DriverLonLat(vehicleLon, vehicleLat);
  final markerToRouteStartM = driverMetersBetween(vehicle, routeCoords.first);
  double? activeRouteStartDistM;
  if (hasReliableSnap && snappedLat != null && snappedLon != null) {
    activeRouteStartDistM = driverMetersBetween(
      vehicle,
      DriverLonLat(snappedLon, snappedLat),
    );
  }
  return DriverCockpitRouteAlignDiagnostics(
    markerToRouteStartM: markerToRouteStartM,
    activeRouteStartDistM: activeRouteStartDistM,
    snapped: hasReliableSnap,
  );
}

/// NAV-PRES-3B: lower third-person chase camera profile for driver mode.
DriverCockpitCameraProfileOutput resolveDriverCockpitCameraProfile(
  DriverCockpitCameraProfileInput input, {
  DriverCockpitCameraLookaheadInput? lookahead,
  double manualZoomOffset = 0.0,
  double manualPitchOffset = 0.0,
}) {
  final baseTargetZoom = driverCockpitCameraTargetZoom(isTablet: input.isTablet);
  final baseTargetPitch = driverCockpitCameraTargetPitch(isTablet: input.isTablet);
  final targetZoom = applyDriverCockpitManualZoomTarget(
    baseTargetZoom: baseTargetZoom,
    manualZoomOffset: manualZoomOffset,
  );
  final targetPitch = applyDriverCockpitManualPitchTarget(
    baseTargetPitch: baseTargetPitch,
    manualPitchOffset: manualPitchOffset,
  );
  final zoom = driverCockpitCameraSmoothToward(
    current: input.currentZoom,
    target: targetZoom,
    maxStep: kDriverCockpitCameraMaxZoomStep,
    min: kDriverCockpitCameraMinZoom,
    max: kDriverCockpitCameraMaxZoom,
  );
  final pitch = driverCockpitCameraSmoothToward(
    current: input.currentPitch,
    target: targetPitch,
    maxStep: kDriverCockpitCameraMaxPitchStep,
    min: kDriverCockpitCameraMinPitch,
    max: kDriverCockpitCameraMaxPitch,
  );
  final padding = driverCockpitCameraViewPadding(
    isTablet: input.isTablet,
    isLandscape: input.isLandscape,
    safeTop: input.safeTop,
    safeBottom: input.safeBottom,
  );

  if (lookahead == null) {
    return DriverCockpitCameraProfileOutput(
      zoom: zoom,
      pitch: pitch,
      padding: padding,
      reason: 'driver_cockpit_profile',
    );
  }

  final lookaheadM = resolveDriverCockpitLookaheadMeters(
    speedKmh: lookahead.speedKmh,
  );
  final center = resolveDriverCockpitLookaheadCenter(
    lookahead,
    lookaheadM: lookaheadM,
  );
  return DriverCockpitCameraProfileOutput(
    zoom: zoom,
    pitch: pitch,
    padding: padding,
    centerLat: center.centerLat,
    centerLon: center.centerLon,
    lookaheadM: center.lookaheadM,
    reason: center.reason,
  );
}
