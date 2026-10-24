// COMPANY-CUSTOMER-OPS-P0 — shared dashboard layout tokens.
//
// Phone and tablet keep the existing Gold grid. Only a wide desktop / Windows
// browser window uses a compact header and a 4-column tile row.

import 'dart:math' as math;

import 'package:fluxidi_tracking/fluxidi_responsive.dart';

const double kCompanyDashboardFormMaxWidth = 720;
const double kCompanyDashboardDesktopHeaderHeight = 96;
const double kCompanyDashboardHeaderRadius = 18;
const int kCompanyDashboardDesktopGoldTileColumns = 4;
const double kCompanyDashboardDesktopGoldTileHeight = 148;

int companyDashboardGoldTileColumns({
  required FluxidiScreenClass screenClass,
  required bool isTabletLandscape,
}) {
  if (screenClass == FluxidiScreenClass.desktop) {
    return kCompanyDashboardDesktopGoldTileColumns;
  }
  return isTabletLandscape ? 3 : 2;
}

/// Keep every action row filled without making a tile too narrow to read.
int companyDashboardBalancedTileColumns({
  required int tileCount,
  required int preferredColumns,
  required double availableWidth,
  required double spacing,
  double minimumTileWidth = 148,
}) {
  if (tileCount <= 1) return 1;
  final maxReadableColumns = math.min(
    tileCount,
    math.max(
      1,
      ((availableWidth + spacing) / (minimumTileWidth + spacing)).floor(),
    ),
  );
  final preferred = math.min(math.max(1, preferredColumns), maxReadableColumns);
  if (tileCount % preferred == 0) return preferred;
  for (var columns = preferred + 1; columns <= maxReadableColumns; columns++) {
    if (tileCount % columns == 0) return columns;
  }
  for (var columns = preferred - 1; columns >= 1; columns--) {
    if (tileCount % columns == 0) return columns;
  }
  return 1;
}

bool companyDashboardIsDesktopWide(double width) =>
    FluxidiBreakpoints.classifyWidth(width) == FluxidiScreenClass.desktop;

double companyDashboardHeaderHeight({
  required bool isTabletLandscape,
  required bool useTabletVisualMode,
  bool isDesktopWide = false,
}) {
  if (isDesktopWide) return kCompanyDashboardDesktopHeaderHeight;
  if (isTabletLandscape) return 156;
  if (useTabletVisualMode) return 208;
  return 168;
}
