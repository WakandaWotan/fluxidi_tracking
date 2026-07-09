import 'dart:math' as math;

import '../driver_navigation_geometry.dart';
import '../driver_navigation_models.dart';
import '../nav_engine/nav_camera_view_mode.dart';

/// Input for NAV-PRES-3A/3B/3D driver cockpit camera tuning.
class DriverCockpitCameraProfileInput {
  final double currentZoom;
  final double currentPitch;
  final bool isTablet;
  final bool isLandscape;
  final double safeTop;
  final double safeBottom;

  /// NAV-PRES-3D-FIX: logical screen height used to anchor the vehicle
  /// coordinate low on screen via viewport padding.
  final double screenHeight;

  const DriverCockpitCameraProfileInput({
    required this.currentZoom,
    required this.currentPitch,
    required this.isTablet,
    required this.isLandscape,
    required this.safeTop,
    required this.safeBottom,
    this.screenHeight = 800.0,
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

  /// NAV-PRES-3D-FIX: how the camera center was resolved
  /// (`vehicle_anchor` | `vehicle_center` | `route_lookahead` |
  /// `zoom_pitch_only`).
  final String centerMode;

  /// NAV-PRES-3D-FIX: screen-height fraction where the vehicle coordinate is
  /// anchored (0 when no anchoring applies).
  final double anchorFraction;

  /// NAV-PRES-3G: view-level targets (for diagnostics).
  final double targetZoom;
  final double targetPitch;

  final String reason;

  const DriverCockpitCameraProfileOutput({
    required this.zoom,
    required this.pitch,
    required this.padding,
    this.centerLat,
    this.centerLon,
    this.lookaheadM = 0,
    this.centerMode = 'zoom_pitch_only',
    this.anchorFraction = 0,
    required this.targetZoom,
    required this.targetPitch,
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

/// NAV-PRES-3D-PRO2: bounded zoom/pitch step limits.
///
/// Larger per-update steps so discrete view-level taps feel responsive while
/// follow-camera motion stays smooth between GPS/camera ticks.
const double kDriverCockpitCameraMaxZoomStep = 0.75;
const double kDriverCockpitCameraMaxPitchStep = 6.5;
const double kDriverCockpitCameraMaxCenterStepM = 12.0;
const double kDriverCockpitCameraMinZoom = 13.0;
const double kDriverCockpitCameraMaxZoom = 21.8;
const double kDriverCockpitCameraMinPitch = 44.0;
const double kDriverCockpitCameraMaxPitch = 84.5;

/// NAV-PRES-3D-PRO: product-facing driver view levels (session-only).
///
/// Level 7 is normal cockpit. Level 13 is aggressive chase-cam; level 1 is
/// high overview. NAV-PRES-3D-PRO2 uses non-linear curves between these
/// anchor points so 1 / 7 / 13 are visually unmistakable.
const int kDriverCockpitViewLevelMin = 1;
const int kDriverCockpitViewLevelMax = 13;
const int kDriverCockpitViewLevelDefault = 7;

/// NAV-PRES-3D: normalized intensity bounds (diagnostics only).
const double kDriverCockpitPerspectiveIntensityMin = -1.0;
const double kDriverCockpitPerspectiveIntensityMax = 1.0;

/// NAV-PRES-3D-PRO2: phone-portrait anchor/zoom/pitch at levels 1 / 7 / 13.
const double kDriverCockpitPro2PhoneZoomL1 = 16.8;
const double kDriverCockpitPro2PhoneZoomL7 = 19.1;
const double kDriverCockpitPro2PhoneZoomL13 = 21.6;
const double kDriverCockpitPro2PhonePitchL1 = 51.5;
const double kDriverCockpitPro2PhonePitchL7 = 77.0;
const double kDriverCockpitPro2PhonePitchL13 = 84.25;
const double kDriverCockpitPro2PhoneAnchorL1 = 0.60;
const double kDriverCockpitPro2PhoneAnchorL7 = 0.70;
const double kDriverCockpitPro2PhoneAnchorL13 = 0.82;

/// NAV-PRES-3D-PRO2: tablet / landscape anchor/zoom/pitch at levels 1 / 7 / 13.
const double kDriverCockpitPro2CompactZoomL1 = 16.5;
const double kDriverCockpitPro2CompactZoomL7 = 18.4;
const double kDriverCockpitPro2CompactZoomL13 = 21.1;
const double kDriverCockpitPro2CompactPitchL1 = 51.5;
const double kDriverCockpitPro2CompactPitchL7 = 75.0;
const double kDriverCockpitPro2CompactPitchL13 = 84.25;
const double kDriverCockpitPro2CompactAnchorL1 = 0.55;
const double kDriverCockpitPro2CompactAnchorL7 = 0.62;
const double kDriverCockpitPro2CompactAnchorL13 = 0.73;

/// NAV-PRES-3D-PRO2: HUD icon size at levels 1 / 7 / 13 (phone baseline 94).
const double kDriverCockpitPro2HudPhoneL1 = 78.0;
const double kDriverCockpitPro2HudPhoneL7 = 94.0;
const double kDriverCockpitPro2HudPhoneL13 = 122.0;
const double kDriverCockpitPro2HudTabletL1 = 92.0;
const double kDriverCockpitPro2HudTabletL7 = 132.0;
const double kDriverCockpitPro2HudTabletL13 = 142.0;

/// NAV-PRES-3G: overview levels may shrink the HUD; close levels keep L7 size.
const int kDriverCockpitHudOverviewLevelMax = 3;
const int kDriverCockpitHudFixedLevelMin = 5;

/// NAV-PRES-3G: max step when ramping cockpit camera during GPS follow ticks.
const double kDriverCockpitCameraFollowMaxZoomStep = 0.75;
const double kDriverCockpitCameraFollowMaxPitchStep = 6.5;

/// NAV-PRES-3G: manual +/- applies targets directly (one visible map step).
const double kDriverCockpitCameraDirectAdjustMaxZoomStep = 99.0;
const double kDriverCockpitCameraDirectAdjustMaxPitchStep = 99.0;

/// NAV-PRES-3D-PRO2: ease exponents — high end much more aggressive.
const double kDriverCockpitPro2LowSegmentPower = 1.35;
const double kDriverCockpitPro2HighSegmentPower = 3.2;

/// Legacy level-7 anchor labels (tests / diagnostics).
const double kDriverCockpitVehicleAnchorFractionPortrait =
    kDriverCockpitPro2PhoneAnchorL7;
const double kDriverCockpitVehicleAnchorFractionLandscape =
    kDriverCockpitPro2CompactAnchorL7;

/// Legacy NAV-PRES-3B composition clamp (padding helper only).
const double kDriverCockpitPerspectiveMinBottomPadding = 96.0;

/// NAV-PRES-3A baseline targets (for tests comparing 3B increases).
const double kDriverCockpitCamera3aPhoneZoom = 18.4;
const double kDriverCockpitCamera3aPhonePitch = 71.0;
const double kDriverCockpitCamera3aTabletZoom = 17.6;
const double kDriverCockpitCamera3aTabletPitch = 69.0;

double driverCockpitCameraTargetZoom({required bool isTablet}) {
  return isTablet
      ? kDriverCockpitPro2CompactZoomL7
      : kDriverCockpitPro2PhoneZoomL7;
}

double driverCockpitCameraTargetPitch({required bool isTablet}) {
  return isTablet
      ? kDriverCockpitPro2CompactPitchL7
      : kDriverCockpitPro2PhonePitchL7;
}

bool driverCockpitUsesCompactChaseProfile({
  required bool isTablet,
  required bool isLandscape,
}) {
  return isTablet || isLandscape;
}

double _driverCockpitEaseInPower(double t, double power) {
  final c = t.clamp(0.0, 1.0);
  return math.pow(c, power).toDouble();
}

/// NAV-PRES-3D-PRO2: non-linear interpolation across levels 1 / 7 / 13.
///
/// Overview (1..4), normal driver (5..8), aggressive chase (9..13) are spread
/// by stronger easing on the high segment so 10..13 change quickly.
double driverCockpitViewLevelInterp({
  required int level,
  required double atLevel1,
  required double atLevel7,
  required double atLevel13,
  double lowSegmentPower = kDriverCockpitPro2LowSegmentPower,
  double highSegmentPower = kDriverCockpitPro2HighSegmentPower,
}) {
  final l = clampDriverCockpitViewLevel(level);
  if (l <= kDriverCockpitViewLevelDefault) {
    final span = kDriverCockpitViewLevelDefault - kDriverCockpitViewLevelMin;
    final t = _driverCockpitEaseInPower(
      (l - kDriverCockpitViewLevelMin) / span,
      lowSegmentPower,
    );
    return atLevel1 + (atLevel7 - atLevel1) * t;
  }
  final span = kDriverCockpitViewLevelMax - kDriverCockpitViewLevelDefault;
  final t = _driverCockpitEaseInPower(
    (l - kDriverCockpitViewLevelDefault) / span,
    highSegmentPower,
  );
  return atLevel7 + (atLevel13 - atLevel7) * t;
}

double clampDriverCockpitPerspectiveIntensity(double intensity) {
  return intensity.clamp(
    kDriverCockpitPerspectiveIntensityMin,
    kDriverCockpitPerspectiveIntensityMax,
  );
}

/// NAV-PRES-3D-PRO: clamp product view level.
int clampDriverCockpitViewLevel(int level) {
  return level.clamp(kDriverCockpitViewLevelMin, kDriverCockpitViewLevelMax);
}

/// NAV-PRES-3D-PRO: step view level on +/- tap.
int stepDriverCockpitViewLevel(int current, {required bool increase}) {
  return clampDriverCockpitViewLevel(current + (increase ? 1 : -1));
}

/// NAV-PRES-3D-PRO: map view level to normalized intensity.
///
/// Level 1 => -1.0, level 7 => 0.0, level 13 => +1.0.
double driverCockpitViewLevelToIntensity(int level) {
  final clamped = clampDriverCockpitViewLevel(level);
  return (clamped - kDriverCockpitViewLevelDefault) /
      ((kDriverCockpitViewLevelMax - kDriverCockpitViewLevelMin) / 2);
}

/// NAV-PRES-3D-PRO2: resolved zoom target for [level].
double driverCockpitViewLevelTargetZoom({
  required bool isTablet,
  required bool isLandscape,
  required int level,
}) {
  final compact = driverCockpitUsesCompactChaseProfile(
    isTablet: isTablet,
    isLandscape: isLandscape,
  );
  final raw = driverCockpitViewLevelInterp(
    level: level,
    atLevel1: compact
        ? kDriverCockpitPro2CompactZoomL1
        : kDriverCockpitPro2PhoneZoomL1,
    atLevel7: compact
        ? kDriverCockpitPro2CompactZoomL7
        : kDriverCockpitPro2PhoneZoomL7,
    atLevel13: compact
        ? kDriverCockpitPro2CompactZoomL13
        : kDriverCockpitPro2PhoneZoomL13,
  );
  return raw.clamp(kDriverCockpitCameraMinZoom, kDriverCockpitCameraMaxZoom);
}

/// NAV-PRES-3D-PRO2: resolved pitch target for [level].
double driverCockpitViewLevelTargetPitch({
  required bool isTablet,
  required bool isLandscape,
  required int level,
}) {
  final compact = driverCockpitUsesCompactChaseProfile(
    isTablet: isTablet,
    isLandscape: isLandscape,
  );
  final raw = driverCockpitViewLevelInterp(
    level: level,
    atLevel1: compact
        ? kDriverCockpitPro2CompactPitchL1
        : kDriverCockpitPro2PhonePitchL1,
    atLevel7: compact
        ? kDriverCockpitPro2CompactPitchL7
        : kDriverCockpitPro2PhonePitchL7,
    atLevel13: compact
        ? kDriverCockpitPro2CompactPitchL13
        : kDriverCockpitPro2PhonePitchL13,
  );
  return raw.clamp(kDriverCockpitCameraMinPitch, kDriverCockpitCameraMaxPitch);
}

/// NAV-PRES-3H: driver cockpit HUD is locked to View 7 baseline for all levels.
double driverCockpitFixedHudIconSize({required bool isTablet}) {
  return isTablet ? kDriverCockpitPro2HudTabletL7 : kDriverCockpitPro2HudPhoneL7;
}

/// NAV-PRES-3H/3K: fixed HUD bottom offset above safe inset (level-independent).
double driverCockpitFixedHudBottomOffset({
  required bool isLandscape,
  required bool cockpitChaseCamera,
  bool isTablet = false,
}) {
  final base = isLandscape
      ? (isTablet ? 116.0 : 112.0)
      : (isTablet ? 180.0 : 168.0);
  return base + (cockpitChaseCamera ? 8.0 : 0.0);
}

/// NAV-PRES-3H: stable L7 anchor for all driver view levels (1..13).
double driverCockpitFixedAnchorFraction({
  required bool isTablet,
  required bool isLandscape,
}) {
  final compact = driverCockpitUsesCompactChaseProfile(
    isTablet: isTablet,
    isLandscape: isLandscape,
  );
  return compact
      ? kDriverCockpitPro2CompactAnchorL7
      : kDriverCockpitPro2PhoneAnchorL7;
}

/// NAV-PRES-3G: stable anchor for close chase levels (5..13).
/// NAV-PRES-3H: all levels 1..13 use fixed L7 anchor in driver cockpit mode.
/// NAV-PRES-3L-A: tablet streetlevel gets a small anchor nudge at View 7+.
const int kDriverCockpitStreetLevelAnchorNudgeMinLevel = 7;
const double kDriverCockpitTabletStreetLevelAnchorNudge = 0.03;

/// NAV-PRES-3L-A: cockpit-only visual route lead-in behind snap (meters).
const double kDriverCockpitRouteLeadInMaxM = 35.0;

/// NAV-PRES-3L-A: meters of route geometry to render behind snap for cockpit HUD alignment.
double driverCockpitRouteVisualLeadInMeters(int viewLevel) {
  final level = clampDriverCockpitViewLevel(viewLevel);
  if (level <= 3) return 0.0;
  if (level <= 6) {
    return ((level - 3) / 3.0 * 8.0).clamp(0.0, 8.0);
  }
  if (level <= 10) {
    final t = (level - 7) / 3.0;
    return 12.0 + t * 8.0;
  }
  final t = (level - 11) / 2.0;
  return (20.0 + t * 15.0).clamp(20.0, kDriverCockpitRouteLeadInMaxM);
}

double driverCockpitViewLevelTargetAnchorFraction({
  required bool isTablet,
  required bool isLandscape,
  required int level,
}) {
  final base = driverCockpitFixedAnchorFraction(
    isTablet: isTablet,
    isLandscape: isLandscape,
  );
  if (!isTablet || level < kDriverCockpitStreetLevelAnchorNudgeMinLevel) {
    return base;
  }
  return (base + kDriverCockpitTabletStreetLevelAnchorNudge).clamp(base, 0.85);
}

/// NAV-PRES-3G/3H: driver cockpit HUD size — fixed at L7 baseline for all levels.
double driverCockpitViewLevelHudIconSize({
  required bool isTablet,
  required int level,
}) {
  return driverCockpitFixedHudIconSize(isTablet: isTablet);
}

/// Legacy intensity helpers (diagnostics / backward-compatible tests).
double driverCockpitPerspectiveTargetZoom({
  required bool isTablet,
  required double intensity,
}) {
  final level = kDriverCockpitViewLevelDefault +
      (clampDriverCockpitPerspectiveIntensity(intensity) *
              (kDriverCockpitViewLevelMax - kDriverCockpitViewLevelDefault))
          .round();
  return driverCockpitViewLevelTargetZoom(
    isTablet: isTablet,
    isLandscape: false,
    level: clampDriverCockpitViewLevel(level),
  );
}

double driverCockpitPerspectiveTargetPitch({
  required bool isTablet,
  required double intensity,
}) {
  final level = kDriverCockpitViewLevelDefault +
      (clampDriverCockpitPerspectiveIntensity(intensity) *
              (kDriverCockpitViewLevelMax - kDriverCockpitViewLevelDefault))
          .round();
  return driverCockpitViewLevelTargetPitch(
    isTablet: isTablet,
    isLandscape: false,
    level: clampDriverCockpitViewLevel(level),
  );
}

double driverCockpitPerspectiveTargetAnchorFraction({
  required bool isLandscape,
  required double intensity,
}) {
  final level = kDriverCockpitViewLevelDefault +
      (clampDriverCockpitPerspectiveIntensity(intensity) *
              (kDriverCockpitViewLevelMax - kDriverCockpitViewLevelDefault))
          .round();
  return driverCockpitViewLevelTargetAnchorFraction(
    isTablet: false,
    isLandscape: isLandscape,
    level: clampDriverCockpitViewLevel(level),
  );
}

/// NAV-PRES-3B: speed-scaled lookahead distance (bearing/forward context
/// only after NAV-PRES-3D-FIX; not used to shift the camera center).
double resolveDriverCockpitLookaheadMeters({required double speedKmh}) {
  final t = (speedKmh / 80.0).clamp(0.0, 1.0);
  return (35.0 + t * 25.0).clamp(35.0, 60.0);
}

/// NAV-PRES-3D-FIX: viewport padding that anchors the camera-centered
/// vehicle coordinate at [anchorFraction] of the screen height.
///
/// Mapbox places the camera center in the middle of the inset viewport, so
/// pinning the vehicle low on screen requires a top-heavy inset:
/// `top + (H - top - bottom) / 2 == anchorFraction * H`.
NavCameraViewPadding driverCockpitVehicleAnchorPadding({
  required double screenHeight,
  required double safeTop,
  required double safeBottom,
  required double anchorFraction,
}) {
  final h = screenHeight <= 0 ? 800.0 : screenHeight;
  final bottom = safeBottom + 16.0;
  final top = (2 * anchorFraction * h - h + bottom).clamp(safeTop, h * 0.9);
  return NavCameraViewPadding(top: top, bottom: bottom);
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
  double bottomPaddingDelta = 0.0,
}) {
  final double top;
  final double baseBottom;
  if (isLandscape) {
    top = safeTop + (isTablet ? 24.0 : 28.0);
    baseBottom = isTablet ? 172.0 : 188.0;
  } else if (isTablet) {
    top = safeTop + 56.0;
    baseBottom = 420.0;
  } else {
    top = safeTop + 56.0;
    baseBottom = 448.0;
  }
  final bottom = (baseBottom + bottomPaddingDelta)
      .clamp(kDriverCockpitPerspectiveMinBottomPadding, 640.0);
  return NavCameraViewPadding(
    top: top,
    bottom: safeBottom + bottom,
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
    centerMode: 'route_lookahead',
    targetZoom: 0,
    targetPitch: 0,
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

/// NAV-PRES-3D-PRO2: lower third-person chase camera profile for driver mode.
///
/// [viewLevel] (1..13, default 7) drives zoom, pitch, and anchor fraction
/// via non-linear curves. The camera centers on the snapped vehicle
/// coordinate and anchors it low on screen via top-heavy viewport padding.
DriverCockpitCameraProfileOutput resolveDriverCockpitCameraProfile(
  DriverCockpitCameraProfileInput input, {
  DriverCockpitCameraLookaheadInput? lookahead,
  int viewLevel = kDriverCockpitViewLevelDefault,
  bool directAdjust = false,
}) {
  final level = clampDriverCockpitViewLevel(viewLevel);
  final targetZoom = driverCockpitViewLevelTargetZoom(
    isTablet: input.isTablet,
    isLandscape: input.isLandscape,
    level: level,
  );
  final targetPitch = driverCockpitViewLevelTargetPitch(
    isTablet: input.isTablet,
    isLandscape: input.isLandscape,
    level: level,
  );
  final maxZoomStep = directAdjust
      ? kDriverCockpitCameraDirectAdjustMaxZoomStep
      : kDriverCockpitCameraFollowMaxZoomStep;
  final maxPitchStep = directAdjust
      ? kDriverCockpitCameraDirectAdjustMaxPitchStep
      : kDriverCockpitCameraFollowMaxPitchStep;
  final zoom = driverCockpitCameraSmoothToward(
    current: input.currentZoom,
    target: targetZoom,
    maxStep: maxZoomStep,
    min: kDriverCockpitCameraMinZoom,
    max: kDriverCockpitCameraMaxZoom,
  );
  final pitch = driverCockpitCameraSmoothToward(
    current: input.currentPitch,
    target: targetPitch,
    maxStep: maxPitchStep,
    min: kDriverCockpitCameraMinPitch,
    max: kDriverCockpitCameraMaxPitch,
  );
  final appliedReason =
      directAdjust ? 'direct_adjust' : 'cockpit_state';
  final anchorFraction = driverCockpitViewLevelTargetAnchorFraction(
    isTablet: input.isTablet,
    isLandscape: input.isLandscape,
    level: level,
  );
  final padding = driverCockpitVehicleAnchorPadding(
    screenHeight: input.screenHeight,
    safeTop: input.safeTop,
    safeBottom: input.safeBottom,
    anchorFraction: anchorFraction,
  );

  if (lookahead == null) {
    return DriverCockpitCameraProfileOutput(
      zoom: zoom,
      pitch: pitch,
      padding: padding,
      anchorFraction: anchorFraction,
      targetZoom: targetZoom,
      targetPitch: targetPitch,
      reason: appliedReason,
    );
  }

  // NAV-PRES-3D-FIX: the camera center IS the vehicle. Route lookahead is
  // intentionally not used for centering, so +/- can never move the car
  // away from the blue route line.
  final hasSnap = lookahead.hasReliableSnap &&
      lookahead.snappedLat != null &&
      lookahead.snappedLon != null;
  return DriverCockpitCameraProfileOutput(
    zoom: zoom,
    pitch: pitch,
    padding: padding,
    centerLat: hasSnap ? lookahead.snappedLat : lookahead.vehicleLat,
    centerLon: hasSnap ? lookahead.snappedLon : lookahead.vehicleLon,
    centerMode: hasSnap ? 'vehicle_anchor' : 'vehicle_center',
    anchorFraction: anchorFraction,
    targetZoom: targetZoom,
    targetPitch: targetPitch,
    reason: appliedReason,
  );
}
