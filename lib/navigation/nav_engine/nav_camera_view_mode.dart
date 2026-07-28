import 'dart:math' as math;

import 'nav_camera_policy.dart';
import 'nav_complexity_guard.dart';
import 'nav_complexity_intelligence.dart';

/// NAV-R15A: selectable follow-camera presentation modes.
///
/// [northUp] keeps the map oriented north (bearing 0°).
/// [overview] preserves NAV-R12/R13/R14 camera behavior.
/// [streetView] strengthens bearing follow and shifts the viewport anchor
/// for a car-GPS driving feel. None of these modes change routing or snapping.
enum NavCameraViewMode {
  northUp,
  overview,
  streetView,
}

/// Resolved camera edge padding for follow mode.
class NavCameraViewPadding {
  final double top;
  final double bottom;
  final double left;
  final double right;

  const NavCameraViewPadding({
    required this.top,
    required this.bottom,
    this.left = 24,
    this.right = 24,
  });
}

/// Cycles north up -> overview -> street view -> north up.
NavCameraViewMode toggleNavCameraViewMode(NavCameraViewMode current) {
  switch (current) {
    case NavCameraViewMode.northUp:
      return NavCameraViewMode.overview;
    case NavCameraViewMode.overview:
      return NavCameraViewMode.streetView;
    case NavCameraViewMode.streetView:
      return NavCameraViewMode.northUp;
  }
}

/// NAV-PRESTART-FIELD-BLOCKER-3 (Problem B + C): the pre-start preview only
/// exposes two presentation options (overview and street view); north-up is a
/// live-only mode. This helper collapses any prior selection into a value the
/// preview surface can safely render.
NavCameraViewMode normaliseNavCameraViewModeForPreview(NavCameraViewMode mode) {
  if (mode == NavCameraViewMode.streetView) return NavCameraViewMode.streetView;
  return NavCameraViewMode.overview;
}

String navCameraViewModeLabel(NavCameraViewMode mode) {
  switch (mode) {
    case NavCameraViewMode.northUp:
      return 'north_up';
    case NavCameraViewMode.overview:
      return 'overview';
    case NavCameraViewMode.streetView:
      return 'street_view';
  }
}

/// Fixed map bearing for north-up mode (degrees).
double northUpCameraBearingTarget() => 0.0;

bool navCameraViewModeUsesFixedNorthBearing(NavCameraViewMode mode) =>
    mode == NavCameraViewMode.northUp;

/// Max bearing step when aligning the camera to north-up (not route follow).
double northUpBearingAlignMaxStep(double speedKmh) {
  if (speedKmh < 4.0) return 6.0;
  if (speedKmh < 20.0) return 12.0;
  return 18.0;
}

/// Bearing follow weight for street-view mode (overview uses policy default).
double streetViewBearingModeWeight(NavCameraPolicyInput input) {
  final speedKmh = math.max(0.0, input.speedKmh ?? 0.0);
  final confidence = input.routeConfidence ?? 0.0;

  if (input.offRouteLikely ||
      input.routeAdaptationActive ||
      confidence < 45.0) {
    return 0.22;
  }

  double base;
  if (speedKmh <= 5.0) {
    base = 0.14;
  } else if (speedKmh < 10.0) {
    final t = (speedKmh - 5.0) / 5.0;
    base = 0.14 + t * 0.36;
  } else if (speedKmh <= 30.0) {
    final t = (speedKmh - 10.0) / 20.0;
    base = 0.70 + t * 0.30;
  } else if (speedKmh < 50.0) {
    final t = (speedKmh - 30.0) / 20.0;
    base = 0.90 + t * 0.06;
  } else {
    base = 0.98;
  }

  if (confidence < 55.0 || !input.hasReliableSnap) {
    base *= 0.55;
  } else if (input.hasReliableSnap && confidence >= 55.0 && speedKmh > 5.0) {
    base = math.max(base, 0.88);
  }

  return base.clamp(0.1, 1.0);
}

/// Max bearing step per camera update (degrees), before bearingModeWeight.
double navCameraBearingMaxStepBase({
  required NavCameraViewMode viewMode,
  required double speedKmh,
}) {
  if (viewMode == NavCameraViewMode.overview) {
    if (speedKmh < 4.0) return 3.5;
    if (speedKmh < 20.0) return 14.0;
    return 28.0;
  }
  if (viewMode == NavCameraViewMode.northUp) {
    return northUpBearingAlignMaxStep(speedKmh);
  }
  if (speedKmh <= 5.0) return 1.2;
  if (speedKmh < 10.0) return 8.0;
  if (speedKmh <= 30.0) return 32.0;
  if (speedKmh < 50.0) return 32.0;
  return 36.0;
}

double navCameraBearingMaxStep({
  required NavCameraViewMode viewMode,
  required double speedKmh,
  required double bearingModeWeight,
}) {
  final weight = bearingModeWeight.clamp(0.0, 1.0);
  return navCameraBearingMaxStepBase(viewMode: viewMode, speedKmh: speedKmh) *
      weight;
}

/// Bounded bearing delta label for diagnostics (no coordinates).
String navCameraBearingDeltaBucket(double deltaDeg) {
  final abs = deltaDeg.abs();
  if (abs < 3.0) return '0-3';
  if (abs < 10.0) return '3-10';
  if (abs < 25.0) return '10-25';
  return '25+';
}

NavCameraViewPadding navCameraViewPadding({
  required NavCameraViewMode mode,
  required bool isLandscape,
  required double safeTop,
  required double safeBottom,
}) {
  if (mode == NavCameraViewMode.streetView) {
    return NavCameraViewPadding(
      top: safeTop + (isLandscape ? 36.0 : 110.0),
      bottom: safeBottom + (isLandscape ? 128.0 : 310.0),
    );
  }
  // northUp and overview share the standard follow padding.
  return NavCameraViewPadding(
    top: safeTop + (isLandscape ? 56.0 : 175.0),
    bottom: safeBottom + (isLandscape ? 96.0 : 240.0),
  );
}

/// Street-view zoom/tilt nudge for a closer forward-driving perspective.
({double zoom, double tilt}) streetViewCameraTuning({
  required double zoom,
  required double tilt,
  required bool routeAdaptationActive,
}) {
  if (routeAdaptationActive) {
    return (zoom: zoom, tilt: tilt);
  }
  return (
    zoom: (zoom + 0.35).clamp(DriverNavCameraPolicy.minZoom, 18.2),
    tilt: math.min(tilt + 2.0, DriverNavCameraPolicy.maxTiltDeg),
  );
}

String navCameraSpeedBucketForDiagnostics(double? speedKmh) {
  return NavComplexityIntelligenceBuilder.speedBucket(speedKmh);
}

String navCameraConfidenceBucketForDiagnostics(double? confidence) {
  return NavComplexityGuard.confidenceBucket(confidence);
}
