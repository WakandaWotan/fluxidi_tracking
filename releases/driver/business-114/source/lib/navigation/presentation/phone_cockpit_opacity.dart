import 'package:flutter/material.dart';

// Phone-only translucent cockpit / Tellers surface alphas + readability.
// Colors come from the active driver theme where a tint is needed; phone
// chrome prefers outlined glyphs over large opaque plates (no BackdropFilter).

/// Ordinary Navigatie + Tellers phone glass — same transparent family.
abstract final class PhoneCockpitOpacity {
  /// Outer shell / meters panel (map must dominate).
  static const double outer = 0.16;

  /// KPI / metric tile tint.
  static const double kpiTile = 0.12;

  /// Primary control hit surfaces.
  static const double action = 0.40;

  /// Compact estimate strip.
  static const double priceStrip = 0.26;
}

/// Phone Tellers overlay surface alphas (aligned with [PhoneCockpitOpacity]).
abstract final class PhoneTellersSurfaceOpacity {
  static const double panel = 0.0;
  static const double kpiTile = PhoneCockpitOpacity.kpiTile;
  static const double actionHit = PhoneCockpitOpacity.action;
  static const double navButton = 0.36;
  static const double priceStrip = PhoneCockpitOpacity.priceStrip;
  static const double statusChip = 0.18;
}

/// Phone Tellers / Navigatie readability tokens — outlined glyphs over the map.
abstract final class PhoneTellersReadability {
  static const Color primaryFill = Color(0xFFFFFFFF);
  static const Color primaryStroke = Color(0xFF0A0A0A);
  static const double primaryStrokeWidth = 3.0;

  static const Color labelFill = Color(0xFFF2F5F8);
  static const Color labelStroke = Color(0xCC000000);
  static const double labelStrokeWidth = 2.2;

  static const Color iconStroke = Color(0xFF0A0A0A);
  static const Color focusBorder = Color(0xE6FFD54F);

  static const List<Shadow> softShadow = <Shadow>[
    Shadow(
      color: Color(0x99000000),
      blurRadius: 4,
      offset: Offset(0, 1),
    ),
  ];
}

/// Phone Tellers estimate-strip visibility from authoritative ride phase.
bool resolveTellersEstimatedPriceStripVisible({
  required bool isTablet,
  required bool liveRideActive,
  required bool ridePrepared,
  required bool rideCompleted,
}) {
  if (isTablet) return true;
  if (liveRideActive) return false;
  if (rideCompleted) return false;
  return ridePrepared;
}

/// Phone phase pill: only meaningful runtime states (active / paused / waiting).
/// Tablet always keeps its status chrome. Never show generic Navigation/Stand-by.
bool resolveTellersPhasePillVisible({
  required bool isTablet,
  required bool liveRideActive,
  required bool isWaiting,
}) {
  if (isTablet) return true;
  return liveRideActive || isWaiting;
}
