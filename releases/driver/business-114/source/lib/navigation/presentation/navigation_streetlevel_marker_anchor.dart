import 'dart:math' as math;

/// NAV-VEHICLE-MODE-CAR-ARROW-1 (Phase 7): dynamic Street Level marker anchor.
///
/// In Street Level (driver cockpit) mode the visible marker (Car or Arrow)
/// sits just above the KPI meters panel. The vertical position is derived from
/// the real KPI panel geometry — never a single arbitrary global pixel value —
/// and is shared by both the on-screen marker widget and the camera nose
/// anchor so they move as one coherent unit. The same anchor is used for Car
/// and Arrow, so switching between them never shifts the position or camera.

/// Canonical cockpit KPI panel heights, measured as the real *outer* rendered
/// height of the panel (content plus the 1px decoration border on top and
/// bottom). Mirrored by [CockpitWidget] so the marker anchor and the panel
/// itself can never drift apart: the marker must clear the panel's true top
/// edge, which includes the border.
const double kCockpitPanelBorderWidth = 1.0;
const double kCockpitPanelBorderTotal = kCockpitPanelBorderWidth * 2;
const double kCockpitPortraitBasePanelHeight = 90.0;
const double kCockpitLandscapePanelHeight = 64.0;

/// Inner content heights (excluding the decoration border) used by
/// [CockpitWidget]'s [SizedBox] so the rendered outer panel equals the
/// canonical heights above.
const double kCockpitPortraitBaseContentHeight =
    kCockpitPortraitBasePanelHeight - kCockpitPanelBorderTotal;
const double kCockpitLandscapeContentHeight =
    kCockpitLandscapePanelHeight - kCockpitPanelBorderTotal;

/// Acceptance window: the marker bottom sits 12–20 logical px above the KPI
/// panel top. The default gap is centered in that window.
const double kStreetLevelMarkerGapAboveKpiMin = 12.0;
const double kStreetLevelMarkerGapAboveKpiMax = 20.0;
const double kStreetLevelMarkerGapAboveKpi = 16.0;

/// Height of the cockpit KPI panel for the current layout.
///
/// Mirrors [CockpitWidget]'s own layout math: landscape is a fixed strip;
/// portrait is a base panel plus an optional secondary action block.
double streetLevelKpiPanelHeight({
  required bool isLandscape,
  required bool hasSecondaryActions,
  required double secondaryActionRowHeight,
  required double primaryToSecondaryGap,
}) {
  if (isLandscape) {
    return kCockpitLandscapePanelHeight;
  }
  final secondaryBlock = hasSecondaryActions
      ? (secondaryActionRowHeight + primaryToSecondaryGap)
      : 0.0;
  return kCockpitPortraitBasePanelHeight + secondaryBlock;
}

/// Bottom offset (from the screen bottom, excluding the safe-area inset) for
/// the Street Level marker so its bottom edge sits [gapAboveKpi] logical px
/// above the KPI panel top. Callers add the safe-area bottom inset, matching
/// the existing HUD placement convention.
double streetLevelMarkerBottomOffset({
  required double kpiPanelHeight,
  double gapAboveKpi = kStreetLevelMarkerGapAboveKpi,
}) {
  final gap = gapAboveKpi.clamp(
    kStreetLevelMarkerGapAboveKpiMin,
    kStreetLevelMarkerGapAboveKpiMax,
  );
  final height = kpiPanelHeight.isFinite && kpiPanelHeight > 0
      ? kpiPanelHeight
      : kCockpitPortraitBasePanelHeight;
  return height + gap;
}

/// Convenience: resolves the Street Level marker bottom offset directly from
/// the KPI layout inputs (panel height + gap), excluding the safe-area inset.
///
/// NAV-CAMERA-FIELD-REGRESSION-1: [extraBottomChrome] covers optional chrome
/// stacked below the KPI secondary row (e.g. the direct-ride fare estimate
/// panel) so the marker/camera nose-anchor clear the same bottom strip as
/// the View-column `bottomStripReserve`.
double resolveStreetLevelMarkerBottomOffset({
  required bool isLandscape,
  required bool hasSecondaryActions,
  required double secondaryActionRowHeight,
  required double primaryToSecondaryGap,
  double gapAboveKpi = kStreetLevelMarkerGapAboveKpi,
  double extraBottomChrome = 0.0,
}) {
  final panelHeight = streetLevelKpiPanelHeight(
    isLandscape: isLandscape,
    hasSecondaryActions: hasSecondaryActions,
    secondaryActionRowHeight: math.max(0, secondaryActionRowHeight),
    primaryToSecondaryGap: math.max(0, primaryToSecondaryGap),
  );
  final extra =
      extraBottomChrome.isFinite && extraBottomChrome > 0 ? extraBottomChrome : 0.0;
  return streetLevelMarkerBottomOffset(
    kpiPanelHeight: panelHeight + extra,
    gapAboveKpi: gapAboveKpi,
  );
}
