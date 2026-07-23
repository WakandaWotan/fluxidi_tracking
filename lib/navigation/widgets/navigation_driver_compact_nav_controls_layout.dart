import 'package:flutter/material.dart';

import '../../fluxidi_responsive.dart';

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: compact bottom nav icon row metrics.
class DriverCompactNavControlsLayout {
  const DriverCompactNavControlsLayout({
    required this.buttonVisualSize,
    required this.minTouchTarget,
    required this.iconSize,
    required this.horizontalGap,
    required this.rowPadding,
    required this.bottomSafePadding,
    required this.isTablet,
    required this.isLandscape,
    this.metricsToPrimaryGap = 4,
    this.primaryToSecondaryGap = 4,
    this.secondaryRowHorizontalInset = 0,
    this.secondaryRowExtraHeight = 0,
    this.distributeSecondaryRowEvenly = false,
  });

  final double buttonVisualSize;
  final double minTouchTarget;
  final double iconSize;
  final double horizontalGap;
  final double rowPadding;
  final double bottomSafePadding;
  final bool isTablet;
  final bool isLandscape;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: gap between metric tiles and primary row.
  final double metricsToPrimaryGap;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: gap between primary row and icon row.
  final double primaryToSecondaryGap;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: inset before first/after last icon chip.
  final double secondaryRowHorizontalInset;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: optional extra icon-row container height.
  final double secondaryRowExtraHeight;

  /// NAV-PRES-TABLET-PORTRAIT-POLISH-1: spread icon row across available width.
  final bool distributeSecondaryRowEvenly;

  double get rowHeight =>
      minTouchTarget + (rowPadding * 2) + secondaryRowExtraHeight;
}

/// NAV-MOBILE-3D-SELECTOR-SCALE-AND-BOTTOM-PRIORITY-1: bottom-strip action
/// priority. Phone diagnostics must never take a compact action slot needed
/// by Waze/external navigation or primary ride controls.
///
/// NAV-TELLERS-POSE-ANCHOR-AND-DIAGNOSTICS-UI-1: the visible diagnostics/log
/// button is now removed from every driver navigation toolbar on all form
/// factors, orientations and build modes. [showDiagnosticsInBottomStrip] is
/// therefore always `false`; internal diagnostics recording/export is kept
/// alive through non-UI paths only.
class DriverCockpitSecondaryActionPolicy {
  const DriverCockpitSecondaryActionPolicy({
    required this.showDiagnosticsInBottomStrip,
    required this.prioritizeExternalNavigation,
  });

  final bool showDiagnosticsInBottomStrip;
  final bool prioritizeExternalNavigation;
}

DriverCockpitSecondaryActionPolicy resolveDriverCockpitSecondaryActionPolicy({
  required bool isTablet,
  required bool diagnosticsEnabled,
}) {
  return const DriverCockpitSecondaryActionPolicy(
    showDiagnosticsInBottomStrip: false,
    prioritizeExternalNavigation: true,
  );
}

/// Phone defaults — unchanged production sizing.
const DriverCompactNavControlsLayout kDriverCompactNavControlsPhoneLayout =
    DriverCompactNavControlsLayout(
      buttonVisualSize: 44,
      minTouchTarget: 44,
      iconSize: 18,
      horizontalGap: 6,
      rowPadding: 0,
      bottomSafePadding: 0,
      isTablet: false,
      isLandscape: false,
      metricsToPrimaryGap: 4,
      primaryToSecondaryGap: 4,
      secondaryRowHorizontalInset: 0,
      secondaryRowExtraHeight: 0,
      distributeSecondaryRowEvenly: false,
    );

/// NAV-PRES-TABLET-CONTROLS-ZOOM-1: tablet-only enlarged touch targets.
DriverCompactNavControlsLayout resolveDriverCompactNavControlsLayout({
  required FluxidiScreenClass screenClass,
  required Orientation orientation,
}) {
  final isTablet =
      screenClass == FluxidiScreenClass.tablet ||
      screenClass == FluxidiScreenClass.desktop;
  if (!isTablet) {
    return kDriverCompactNavControlsPhoneLayout;
  }
  final isLandscape = orientation == Orientation.landscape;
  if (isLandscape) {
    return const DriverCompactNavControlsLayout(
      buttonVisualSize: 52,
      minTouchTarget: 62,
      iconSize: 27,
      horizontalGap: 11,
      rowPadding: 4,
      bottomSafePadding: 2,
      isTablet: true,
      isLandscape: true,
    );
  }
  return const DriverCompactNavControlsLayout(
    buttonVisualSize: 56,
    minTouchTarget: 64,
    iconSize: 28,
    horizontalGap: 9,
    rowPadding: 4,
    bottomSafePadding: 2,
    isTablet: true,
    isLandscape: false,
  );
}

/// Ensures [actionCount] compact chips fit within [availableWidth].
bool driverCompactNavControlsRowFits({
  required DriverCompactNavControlsLayout layout,
  required int actionCount,
  required double availableWidth,
}) {
  if (actionCount <= 0) return true;
  final total =
      (layout.minTouchTarget * actionCount) +
      (layout.horizontalGap * (actionCount - 1));
  return total <= availableWidth;
}
