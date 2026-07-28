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

/// NAV-PRES-TABLET-PORTRAIT-POLISH-1: optional portrait placement overrides.
class DriverCockpitCameraControlsPlacementHints {
  const DriverCockpitCameraControlsPlacementHints({
    this.portraitBottomOffset,
    this.rightInsetExtra = 0,
  });

  final double? portraitBottomOffset;
  final double rightInsetExtra;
}

/// NAV-PRES-3E-FIX1: estimate panel size from control chrome (not map/HUD).
Size estimateDriverCockpitCameraControlsPanelSize({
  required double buttonSize,
  required bool hasLevelLabel,
  required bool hasDebugSubLabel,
  required bool compactLandscape,
  double panelWidthExtra = 0,
  double panelHorizontalPadding = 4,
  double? levelLabelFontSize,
  double? debugLabelFontSize,
}) {
  final verticalPad = 8.0;
  final levelFont = levelLabelFontSize ?? (compactLandscape ? 9.0 : 10.0);
  final debugFont = debugLabelFontSize ?? (compactLandscape ? 7.0 : 8.0);
  final labelBlock = !hasLevelLabel
      ? 4.0
      : (hasDebugSubLabel
            ? (compactLandscape ? 20.0 : (6 + levelFont + debugFont + 4))
            : (compactLandscape ? 14.0 : (6 + levelFont + 4)));
  final height =
      verticalPad + buttonSize + labelBlock + buttonSize + verticalPad;
  final width = buttonSize + (panelHorizontalPadding * 2) + panelWidthExtra;
  return Size(width, height);
}

/// NAV-PRES-3E-FIX1: clamp driver view controls inside the visible safe viewport.
///
/// Landscape uses mid-right vertical placement. Portrait anchors above the
/// cockpit bar with a fixed offset so high view levels / large HUD cars do
/// not push the panel off-screen.
///
/// NAV-PRESTART-FIELD-BLOCKER-3 (Problem D): [bottomStripReserve] is the
/// measured height of the actual bottom chrome (cockpit + secondary action
/// row + optional fare-estimate panel) so the portrait zoom column is placed
/// ABOVE the real bottom strip, not behind the fixed 168dp assumption. When
/// the reserve is smaller than the fixed anchor the original placement
/// wins, preserving the current behaviour for callers that do not measure
/// the chrome.
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
  double bottomStripReserve = 0.0,
  DriverCockpitCameraControlsPlacementHints? placementHints,
}) {
  final rightInsetExtra = placementHints?.rightInsetExtra ?? 0;
  final right = safeRight + margin + rightInsetExtra;
  final minTop = safeTop + margin + navBannerReserve;
  final maxPanelTop = screenHeight - safeBottom - margin - panelHeight;
  var clamped = false;
  late final String reason;
  var panelTop = 0.0;
  final safeReserve = bottomStripReserve.isFinite && bottomStripReserve > 0
      ? bottomStripReserve
      : 0.0;

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
    final portraitBottomOffset =
        placementHints?.portraitBottomOffset ??
        kDriverCockpitControlsPortraitBottomOffset;
    // NAV-PRESTART-FIELD-BLOCKER-3 (Problem D): grow the offset to clear the
    // measured chrome (cockpit + secondary + estimate) with an extra margin
    // so the minus button never lands behind the cockpit panel.
    final measuredBottomOffset = safeReserve > 0
        ? safeReserve + margin
        : portraitBottomOffset;
    final effectiveBottomOffset = measuredBottomOffset > portraitBottomOffset
        ? measuredBottomOffset
        : portraitBottomOffset;
    final desiredBottom = safeBottom + effectiveBottomOffset;
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
      reason = safeReserve > portraitBottomOffset
          ? 'portrait_above_measured_chrome'
          : 'portrait_above_cockpit';
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
