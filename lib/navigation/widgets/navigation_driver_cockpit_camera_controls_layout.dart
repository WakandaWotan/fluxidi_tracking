import 'dart:ui';

/// NAV-PRES-3E-FIX1: resolved overlay position for driver view controls.
class DriverCockpitCameraControlsLayoutResult {
  final double bottom;
  final double right;
  final double panelTop;
  final bool clamped;
  final String reason;

  const DriverCockpitCameraControlsLayoutResult({
    required this.bottom,
    required this.right,
    required this.panelTop,
    required this.clamped,
    required this.reason,
  });
}

/// NAV-PRES-3E-FIX1: fixed portrait anchor above cockpit bar (HUD-independent).
const double kDriverCockpitControlsPortraitBottomOffset = 168.0;

/// NAV-PRES-3E-FIX1: landscape top reserve below maneuver/status banner area.
const double kDriverCockpitControlsLandscapeBannerReserve = 72.0;

/// NAV-PRES-3E-FIX1: edge margin for safe viewport clamping.
const double kDriverCockpitControlsEdgeMargin = 14.0;

/// NAV-PRES-3E-FIX1: estimate panel size from control chrome (not map/HUD).
Size estimateDriverCockpitCameraControlsPanelSize({
  required double buttonSize,
  required bool hasLevelLabel,
  required bool hasDebugSubLabel,
  required bool compactLandscape,
}) {
  final verticalPad = 8.0;
  final labelBlock = !hasLevelLabel
      ? 4.0
      : (hasDebugSubLabel ? (compactLandscape ? 20.0 : 28.0) : 16.0);
  final height = verticalPad + buttonSize + labelBlock + buttonSize + verticalPad;
  final width = buttonSize + 8.0;
  return Size(width, height);
}

/// NAV-PRES-3E-FIX1: clamp driver view controls inside the visible safe viewport.
///
/// Landscape uses mid-right vertical placement. Portrait anchors above the
/// cockpit bar with a fixed offset so high view levels / large HUD cars do
/// not push the panel off-screen.
DriverCockpitCameraControlsLayoutResult
resolveDriverCockpitCameraControlsLayout({
  required double screenHeight,
  required double safeTop,
  required double safeBottom,
  required double safeRight,
  required bool isLandscape,
  required double panelHeight,
  required double panelWidth,
  double margin = kDriverCockpitControlsEdgeMargin,
  double navBannerReserve = 0.0,
}) {
  final right = safeRight + margin;
  final minTop = safeTop + margin + navBannerReserve;
  final maxPanelTop = screenHeight - safeBottom - margin - panelHeight;
  var clamped = false;
  late final String reason;
  var panelTop = 0.0;

  if (isLandscape) {
    var top = (screenHeight - panelHeight) / 2.0;
    if (top < minTop) {
      top = minTop;
      clamped = true;
      reason = 'landscape_mid_clamped_top';
    } else if (top > maxPanelTop) {
      top = maxPanelTop;
      clamped = true;
      reason = 'landscape_mid_clamped_bottom';
    } else {
      reason = 'landscape_mid_right';
    }
    panelTop = top;
  } else {
    final desiredBottom = safeBottom + kDriverCockpitControlsPortraitBottomOffset;
    var top = screenHeight - desiredBottom - panelHeight;
    if (top < minTop) {
      top = minTop;
      clamped = true;
      reason = 'portrait_clamped_top';
    } else if (top > maxPanelTop) {
      top = maxPanelTop;
      clamped = true;
      reason = 'portrait_clamped_bottom';
    } else {
      reason = 'portrait_above_cockpit';
    }
    panelTop = top;
  }

  if (panelTop < minTop) {
    panelTop = minTop;
    clamped = true;
  } else if (panelTop > maxPanelTop) {
    panelTop = maxPanelTop;
    clamped = true;
  }

  final bottom = screenHeight - panelTop - panelHeight;
  return DriverCockpitCameraControlsLayoutResult(
    bottom: bottom,
    right: right,
    panelTop: panelTop,
    clamped: clamped,
    reason: reason,
  );
}
