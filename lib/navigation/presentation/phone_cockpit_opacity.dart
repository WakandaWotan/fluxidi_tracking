// Phone-only translucent cockpit / Tellers surface alphas.
// Colors always come from the active driver theme palette / cockpit tokens;
// these multipliers keep map readable underneath without BackdropFilter blur.

/// Centralized phone glass opacity tokens (starting field ranges).
abstract final class PhoneCockpitOpacity {
  /// Outer/header meters panel and ordinary-nav cockpit shell.
  static const double outer = 0.79;

  /// Individual KPI / metric tiles.
  static const double kpiTile = 0.885;

  /// Primary action controls (Pauze / STOP / nav buttons).
  static const double action = 0.93;

  /// Compact estimated-price strip.
  static const double priceStrip = 0.88;
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
