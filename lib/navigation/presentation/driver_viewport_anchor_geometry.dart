// FLUXIDI-VEHICLE-CAMERA-VIEWPORT-ANCHOR-P0
//
// One pure geometry model for the screen-fixed HUD vehicle and the Mapbox
// nose/focal padding. Host tablet identity owns icon size; current window
// owns H/W and bottom chrome. Paint and camera consume the SAME result.

import 'dart:ui' show Offset;

import 'package:fluxidi_tracking/navigation/nav_engine/nav_camera_view_mode.dart';
import 'package:fluxidi_tracking/navigation/presentation/navigation_driver_cockpit_camera.dart';

/// Shared HUD ↔ camera viewport anchor for Street Level native navigation.
class DriverViewportAnchorGeometry {
  const DriverViewportAnchorGeometry({
    required this.hostIsTablet,
    required this.vehicleIconSize,
    required this.viewportWidth,
    required this.viewportHeight,
    required this.safeTop,
    required this.safeBottom,
    required this.layoutBottomHudHeightPx,
    required this.bottomHudHeightPx,
    required this.vehicleGeometry,
    required this.rawNoseScreenFraction,
    required this.anchorFraction,
    required this.anchorClamped,
    required this.cameraPadding,
    required this.vehicleNoseScreenPoint,
    required this.cameraFocalScreenPoint,
  });

  /// Physical host tablet identity (sticky latch / display), not pane size.
  final bool hostIsTablet;

  /// Fixed HUD vehicle size (tablet 132 / phone 94 when cockpit-boosted).
  final double vehicleIconSize;

  final double viewportWidth;
  final double viewportHeight;
  final double safeTop;
  final double safeBottom;

  /// KPI/chrome-derived bottom reserve before clamp reconciliation.
  final double layoutBottomHudHeightPx;

  /// Bottom reserve actually used for paint + nose geometry (may be adjusted
  /// when the safety clamp binds so paint nose == camera focal).
  final double bottomHudHeightPx;

  final DriverHudVehicleGeometry vehicleGeometry;

  /// Unclamped nose Y / H from [layoutBottomHudHeightPx].
  final double rawNoseScreenFraction;

  /// Final shared anchor fraction (clamped) used by padding AND paint.
  final double anchorFraction;

  final bool anchorClamped;

  final NavCameraViewPadding cameraPadding;

  /// Screen point of the vehicle nose (layout centre X, nose Y).
  final Offset vehicleNoseScreenPoint;

  /// Screen point Mapbox places the tracked geo target at (padding midpoint).
  final Offset cameraFocalScreenPoint;

  double get deltaX =>
      vehicleNoseScreenPoint.dx - cameraFocalScreenPoint.dx;

  double get deltaY =>
      vehicleNoseScreenPoint.dy - cameraFocalScreenPoint.dy;

  /// True when paint nose and camera focal agree within [tolerancePx].
  bool isAligned({double tolerancePx = 1.0}) =>
      deltaX.abs() <= tolerancePx && deltaY.abs() <= tolerancePx;
}

/// Bottom HUD height that places the vehicle nose at [noseScreenFraction].
///
/// Inverts [resolveDriverHudVehicleGeometry]:
/// `noseY = (H - bottom) - icon*(1 - noseFromTop)`.
double driverViewportBottomHudForNoseFraction({
  required double viewportHeightPx,
  required double iconSizePx,
  required double noseScreenFraction,
  double noseFractionFromTop = kDriverHudVehicleNoseFractionFromTop,
}) {
  final h = viewportHeightPx <= 0 ? 800.0 : viewportHeightPx;
  final icon = iconSizePx <= 0 ? 1.0 : iconSizePx;
  final f = noseScreenFraction.clamp(0.0, 1.0);
  final noseFromTop = noseFractionFromTop.clamp(0.0, 1.0);
  return h * (1.0 - f) - icon * (1.0 - noseFromTop);
}

/// Mapbox focal point implied by [padding] on a [viewportWidth]×[viewportHeight]
/// canvas (logical px).
Offset driverViewportCameraFocalScreenPoint({
  required double viewportWidth,
  required double viewportHeight,
  required NavCameraViewPadding padding,
}) {
  final w = viewportWidth <= 0 ? 1.0 : viewportWidth;
  final h = viewportHeight <= 0 ? 1.0 : viewportHeight;
  return Offset(
    (padding.left + (w - padding.right)) / 2.0,
    (padding.top + (h - padding.bottom)) / 2.0,
  );
}

/// Resolve the single HUD ↔ camera anchor for the current host + window.
///
/// [layoutBottomHudHeightPx] is the KPI/chrome reserve (includes safe bottom),
/// matching today's `_streetLevelHudBottomOffset + safeBottom` input to camera
/// overrides. Icon size follows [hostIsTablet], never the pane shortest-side.
DriverViewportAnchorGeometry resolveDriverViewportAnchorGeometry({
  required bool hostIsTablet,
  required double viewportWidth,
  required double viewportHeight,
  required double layoutBottomHudHeightPx,
  required double safeTop,
  required double safeBottom,
  bool cockpitBoost = true,
}) {
  final w = viewportWidth <= 0 ? 800.0 : viewportWidth;
  final h = viewportHeight <= 0 ? 800.0 : viewportHeight;
  final iconSize = cockpitBoost
      ? driverCockpitFixedHudIconSize(isTablet: hostIsTablet)
      : (hostIsTablet ? 80.0 : 72.0);

  final layoutBottom = layoutBottomHudHeightPx.isFinite &&
          layoutBottomHudHeightPx > 0
      ? layoutBottomHudHeightPx
      : driverCockpitFixedHudBottomOffset(
              isLandscape: w > h,
              cockpitChaseCamera: true,
              isTablet: hostIsTablet,
            ) +
            safeBottom;

  final provisional = resolveDriverHudVehicleGeometry(
    viewportHeightPx: h,
    bottomHudHeightPx: layoutBottom,
    iconSizePx: iconSize,
  );
  final minAnchor = hostIsTablet
      ? kDriverCockpitNoseAnchorMinTablet
      : kDriverCockpitNoseAnchorMinPhone;
  final maxAnchor = hostIsTablet
      ? kDriverCockpitNoseAnchorMaxTablet
      : kDriverCockpitNoseAnchorMaxPhone;
  final raw = provisional.noseScreenFraction;
  final clamped = raw.clamp(minAnchor, maxAnchor).toDouble();
  final fractionClampBound = (clamped - raw).abs() > 1e-9;

  // Camera padding may clamp `top` to safeTop, so the realized Mapbox focal
  // can differ from the requested fraction. Paint always tracks that focal.
  final padding = driverCockpitVehicleAnchorPadding(
    screenHeight: h,
    safeTop: safeTop,
    safeBottom: safeBottom,
    anchorFraction: clamped,
  );
  final focal = driverViewportCameraFocalScreenPoint(
    viewportWidth: w,
    viewportHeight: h,
    padding: padding,
  );
  final realizedAnchor = (focal.dy / h).clamp(0.0, 1.0);
  final needsPaintReconcile =
      fractionClampBound || (provisional.noseY - focal.dy).abs() > 0.5;

  final bottomHud = needsPaintReconcile
      ? driverViewportBottomHudForNoseFraction(
          viewportHeightPx: h,
          iconSizePx: iconSize,
          noseScreenFraction: realizedAnchor,
        )
      : layoutBottom;
  final geometry = needsPaintReconcile
      ? resolveDriverHudVehicleGeometry(
          viewportHeightPx: h,
          bottomHudHeightPx: bottomHud,
          iconSizePx: iconSize,
        )
      : provisional;
  final nose = Offset(w / 2.0, geometry.noseY);

  return DriverViewportAnchorGeometry(
    hostIsTablet: hostIsTablet,
    vehicleIconSize: iconSize,
    viewportWidth: w,
    viewportHeight: h,
    safeTop: safeTop,
    safeBottom: safeBottom,
    layoutBottomHudHeightPx: layoutBottom,
    bottomHudHeightPx: bottomHud,
    vehicleGeometry: geometry,
    rawNoseScreenFraction: raw,
    anchorFraction: realizedAnchor,
    anchorClamped: fractionClampBound || needsPaintReconcile,
    cameraPadding: padding,
    vehicleNoseScreenPoint: nose,
    cameraFocalScreenPoint: focal,
  );
}
