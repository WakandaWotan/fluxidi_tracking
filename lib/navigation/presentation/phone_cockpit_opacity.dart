import 'package:flutter/material.dart';

// Phone-only translucent cockpit / Tellers surface alphas + readability.
// Colors come from the active driver theme where a tint is needed; Tellers
// prefers outlined glyphs over large opaque plates (no BackdropFilter).

/// Ordinary Navigatie phone glass shell (prior trial — unchanged this pass).
abstract final class PhoneCockpitOpacity {
  static const double outer = 0.79;
  static const double kpiTile = 0.885;
  static const double action = 0.93;
  static const double priceStrip = 0.88;
}

/// Phone Tellers overlay surface alphas — substantially more transparent than
/// ordinary Navigatie glass. Large panels stay at/near zero; only tap targets
/// may carry a restrained tint.
abstract final class PhoneTellersSurfaceOpacity {
  /// Outer meters/header panel fill (map must dominate).
  static const double panel = 0.0;

  /// KPI cell tint — extremely light glass, not a block.
  static const double kpiTile = 0.12;

  /// Individual control hit surfaces (Pauze / STOP / recenter).
  static const double actionHit = 0.40;

  /// Compact Navigatie action chip.
  static const double navButton = 0.36;

  /// Pre-START estimate pill only.
  static const double priceStrip = 0.26;

  /// Status chip tint.
  static const double statusChip = 0.18;
}

/// Phone Tellers readability tokens — outlined glyphs over the live map.
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
///
/// Tablet always keeps the strip (existing behavior). Phone shows it only for
/// a prepared route before START — never while active/paused/completed, and
/// never inferred from fare text or timers.
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
