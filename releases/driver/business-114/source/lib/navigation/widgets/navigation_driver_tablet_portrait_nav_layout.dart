import 'package:flutter/material.dart';

import '../../fluxidi_responsive.dart';
import 'navigation_driver_cockpit_camera_controls_layout.dart';
import 'navigation_driver_compact_nav_controls_layout.dart';

/// NAV-PRES-TABLET-PORTRAIT-POLISH-1: View +/- panel portrait polish metrics.
class DriverCockpitViewPanelPortraitLayout {
  const DriverCockpitViewPanelPortraitLayout({
    required this.panelWidthExtra,
    required this.panelHorizontalPadding,
    required this.levelLabelFontSize,
    required this.debugLabelFontSize,
    required this.debugLabelOpacity,
    required this.portraitBottomOffsetDelta,
    required this.portraitRightInsetExtra,
  });

  final double panelWidthExtra;
  final double panelHorizontalPadding;
  final double levelLabelFontSize;
  final double debugLabelFontSize;
  final double debugLabelOpacity;
  final double portraitBottomOffsetDelta;
  final double portraitRightInsetExtra;
}

/// NAV-PRES-TABLET-PORTRAIT-POLISH-1: route banner portrait tablet metrics.
class DriverNavBannerPortraitTabletLayout {
  const DriverNavBannerPortraitTabletLayout({
    required this.minHeight,
    required this.iconBoxSize,
    required this.iconSize,
    required this.verticalPadding,
    required this.horizontalPadding,
  });

  final double minHeight;
  final double iconBoxSize;
  final double iconSize;
  final double verticalPadding;
  final double horizontalPadding;
}

/// NAV-PRES-TABLET-PORTRAIT-POLISH-1: bundled tablet portrait navigation polish.
class DriverTabletPortraitNavLayout {
  const DriverTabletPortraitNavLayout({
    required this.compactControls,
    required this.metricsToPrimaryGap,
    required this.primaryToSecondaryGap,
    required this.viewPanel,
    required this.banner,
  });

  final DriverCompactNavControlsLayout compactControls;
  final double metricsToPrimaryGap;
  final double primaryToSecondaryGap;
  final DriverCockpitViewPanelPortraitLayout viewPanel;
  final DriverNavBannerPortraitTabletLayout banner;
}

const DriverCockpitViewPanelPortraitLayout
kDriverCockpitViewPanelPortraitTabletLayout =
    DriverCockpitViewPanelPortraitLayout(
      panelWidthExtra: 4,
      panelHorizontalPadding: 8,
      levelLabelFontSize: 11,
      debugLabelFontSize: 7,
      debugLabelOpacity: 0.55,
      portraitBottomOffsetDelta: 11,
      portraitRightInsetExtra: 12,
    );

// NAV-PRESENTATION-COMPACT-BANNER-LANES-TELLERS-1 / Commit 1:
// Content-adaptive floor — hug the icon + padding; do not reserve a tall
// empty black band for short instructions.
const DriverNavBannerPortraitTabletLayout kDriverNavBannerPortraitTabletLayout =
    DriverNavBannerPortraitTabletLayout(
      minHeight: 64,
      iconBoxSize: 52,
      iconSize: 30,
      verticalPadding: 6,
      horizontalPadding: 12,
    );

/// Returns polish layout only for tablet/desktop portrait; null otherwise.
DriverTabletPortraitNavLayout? resolveDriverTabletPortraitNavLayout({
  required FluxidiScreenClass screenClass,
  required Orientation orientation,
}) {
  final isTablet =
      screenClass == FluxidiScreenClass.tablet ||
      screenClass == FluxidiScreenClass.desktop;
  if (!isTablet || orientation != Orientation.portrait) {
    return null;
  }
  return const DriverTabletPortraitNavLayout(
    compactControls: DriverCompactNavControlsLayout(
      buttonVisualSize: 56,
      minTouchTarget: 64,
      iconSize: 28,
      horizontalGap: 10,
      rowPadding: 6,
      bottomSafePadding: 2,
      isTablet: true,
      isLandscape: false,
      metricsToPrimaryGap: 9,
      primaryToSecondaryGap: 9,
      secondaryRowHorizontalInset: 10,
      secondaryRowExtraHeight: 2,
      distributeSecondaryRowEvenly: true,
    ),
    metricsToPrimaryGap: 9,
    primaryToSecondaryGap: 9,
    viewPanel: kDriverCockpitViewPanelPortraitTabletLayout,
    banner: kDriverNavBannerPortraitTabletLayout,
  );
}

/// Applies tablet portrait polish when active; otherwise [resolveDriverCompactNavControlsLayout].
DriverCompactNavControlsLayout resolveDriverCompactNavControlsLayoutForNav({
  required FluxidiScreenClass screenClass,
  required Orientation orientation,
}) {
  final polish = resolveDriverTabletPortraitNavLayout(
    screenClass: screenClass,
    orientation: orientation,
  );
  return polish?.compactControls ??
      resolveDriverCompactNavControlsLayout(
        screenClass: screenClass,
        orientation: orientation,
      );
}

/// Placement hints for View +/- resolver (portrait tablet only).
DriverCockpitCameraControlsPlacementHints?
resolveDriverCockpitCameraControlsPlacementHints({
  required FluxidiScreenClass screenClass,
  required Orientation orientation,
}) {
  final polish = resolveDriverTabletPortraitNavLayout(
    screenClass: screenClass,
    orientation: orientation,
  );
  if (polish == null) return null;
  return DriverCockpitCameraControlsPlacementHints(
    portraitBottomOffset:
        kDriverCockpitControlsPortraitBottomOffset +
        polish.viewPanel.portraitBottomOffsetDelta,
    rightInsetExtra: polish.viewPanel.portraitRightInsetExtra,
  );
}

/// Ensures portrait tablet chrome fits within a typical tablet viewport.
bool driverTabletPortraitNavLayoutFitsViewport({
  required double screenWidth,
  required double screenHeight,
  required double safeTop,
  required double safeBottom,
  required double safeRight,
  required double panelWidth,
  required double panelHeight,
  required DriverTabletPortraitNavLayout layout,
  double bannerHeight = 100,
  double cockpitHeight = 170,
}) {
  final hints = DriverCockpitCameraControlsPlacementHints(
    portraitBottomOffset:
        kDriverCockpitControlsPortraitBottomOffset +
        layout.viewPanel.portraitBottomOffsetDelta,
    rightInsetExtra: layout.viewPanel.portraitRightInsetExtra,
  );
  final viewLayout = resolveDriverCockpitCameraControlsLayout(
    screenHeight: screenHeight,
    safeTop: safeTop,
    safeBottom: safeBottom,
    safeRight: safeRight,
    isLandscape: false,
    panelHeight: panelHeight,
    panelWidth: panelWidth,
    placementHints: hints,
  );
  final minTop = safeTop + kDriverCockpitControlsEdgeMargin;
  final maxBottom =
      screenHeight - safeBottom - kDriverCockpitControlsEdgeMargin;
  final panelBottom = viewLayout.panelTop + panelHeight;
  final bannerBottom = minTop + bannerHeight;
  final cockpitTop = screenHeight - safeBottom - cockpitHeight;
  return viewLayout.panelTop >= minTop &&
      panelBottom <= maxBottom &&
      bannerBottom < cockpitTop &&
      viewLayout.right + panelWidth <= screenWidth;
}
