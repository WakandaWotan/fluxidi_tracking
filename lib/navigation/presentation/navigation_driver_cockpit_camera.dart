import '../nav_engine/nav_camera_view_mode.dart';

/// Input for NAV-PRES-3A driver cockpit camera tuning.
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

/// Resolved cockpit follow-camera parameters (zoom, pitch, padding).
class DriverCockpitCameraProfileOutput {
  final double zoom;
  final double pitch;
  final NavCameraViewPadding padding;
  final String reason;

  const DriverCockpitCameraProfileOutput({
    required this.zoom,
    required this.pitch,
    required this.padding,
    required this.reason,
  });
}

/// NAV-PRES-3A: bounded zoom/pitch step limits (aligned with NAV-R12-H policy).
const double kDriverCockpitCameraMaxZoomStep = 0.35;
const double kDriverCockpitCameraMaxPitchStep = 3.0;
const double kDriverCockpitCameraMinZoom = 13.0;
const double kDriverCockpitCameraMaxZoom = 18.8;
const double kDriverCockpitCameraMinPitch = 44.0;
const double kDriverCockpitCameraMaxPitch = 74.0;

double driverCockpitCameraTargetZoom({required bool isTablet}) {
  return isTablet ? 17.6 : 18.4;
}

double driverCockpitCameraTargetPitch({required bool isTablet}) {
  return isTablet ? 69.0 : 71.0;
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
      top: safeTop + (isTablet ? 28.0 : 32.0),
      bottom: safeBottom + (isTablet ? 148.0 : 156.0),
    );
  }
  if (isTablet) {
    return NavCameraViewPadding(
      top: safeTop + 72.0,
      bottom: safeBottom + 340.0,
    );
  }
  return NavCameraViewPadding(
    top: safeTop + 72.0,
    bottom: safeBottom + 368.0,
  );
}

/// NAV-PRES-3A: lower, more forward cockpit camera profile for driver mode.
DriverCockpitCameraProfileOutput resolveDriverCockpitCameraProfile(
  DriverCockpitCameraProfileInput input,
) {
  final targetZoom = driverCockpitCameraTargetZoom(isTablet: input.isTablet);
  final targetPitch = driverCockpitCameraTargetPitch(isTablet: input.isTablet);
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
  return DriverCockpitCameraProfileOutput(
    zoom: zoom,
    pitch: pitch,
    padding: driverCockpitCameraViewPadding(
      isTablet: input.isTablet,
      isLandscape: input.isLandscape,
      safeTop: input.safeTop,
      safeBottom: input.safeBottom,
    ),
    reason: 'driver_cockpit_profile',
  );
}
