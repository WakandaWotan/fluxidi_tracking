// COMPANY-AGENDA-P0 — one plan flow; layout follows measured leftover space.

import 'package:flutter/material.dart';

const double kCompanyPlanRideSplitMinWidth = 720;
const double kCompanyPlanRideSplitMinHeight = 480;
const double kCompanyPlanRideWideWindowsWidth = 1280;
const double kCompanyPlanRideCompactWindowsHeight = 720;
const double kCompanyPlanRidePlannerMinWidth = 360;
const double kCompanyPlanRidePlannerMaxWidth = 520;
const double kCompanyPlanRideAgendaMinWidth = 420;

enum CompanyPlanRideLayout { stacked, split }

bool companyOpsShowAgendaBesidePlanner(
  Size size, {
  double desktopWidth = 1100,
}) {
  if (size.width >= kCompanyPlanRideWideWindowsWidth) return true;
  if (size.width >= desktopWidth &&
      size.height <= kCompanyPlanRideCompactWindowsHeight) {
    return true;
  }
  return false;
}

CompanyPlanRideLayout companyPlanRideLayoutFor(BoxConstraints constraints) {
  if (constraints.maxWidth >= kCompanyPlanRideSplitMinWidth &&
      constraints.maxHeight >= kCompanyPlanRideSplitMinHeight) {
    return CompanyPlanRideLayout.split;
  }
  return CompanyPlanRideLayout.stacked;
}

double companyOpsPlannerPaneWidth({
  required double totalWidth,
  required bool customersCollapsed,
  required bool planning,
  required bool dossierOpen,
  double customerPaneWidth = 280,
  double dossierPaneWidth = 360,
  double collapsedRailWidth = 44,
}) {
  final rail = customersCollapsed ? collapsedRailWidth : customerPaneWidth;
  final leftover = (totalWidth - rail - 2).clamp(0.0, totalWidth);
  if (!planning) {
    return dossierOpen ? dossierPaneWidth : collapsedRailWidth;
  }
  final maxPlanner = leftover - kCompanyPlanRideAgendaMinWidth;
  if (maxPlanner < kCompanyPlanRidePlannerMinWidth) {
    return (leftover * 0.38).clamp(
      kCompanyPlanRidePlannerMinWidth * 0.85,
      leftover,
    );
  }
  return maxPlanner.clamp(
    kCompanyPlanRidePlannerMinWidth,
    kCompanyPlanRidePlannerMaxWidth,
  );
}

double companyPlanStackedMapHeight(BoxConstraints constraints) {
  final phoneLike = constraints.maxWidth < 520;
  if (!phoneLike || constraints.maxHeight < 560) return 0;
  return (constraints.maxHeight * 0.28).clamp(140, 220);
}
