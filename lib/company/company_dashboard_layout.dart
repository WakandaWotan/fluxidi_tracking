// COMPANY-CUSTOMER-OPS-P0 — shared dashboard layout tokens.
//
// Phone and tablet keep the existing Gold grid. Only a wide desktop / Windows
// browser window uses a compact header and a 4-column tile row.

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
