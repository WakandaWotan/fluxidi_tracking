// NAV-PARKING-ARRIVAL-DEPARTURE-ROUTE-CLARITY-BANNER-TELLERS-2 / Commit 3
//
// Pure, unit-testable metrics for the driver navigation header brand logo.
// The company/Fluxidi logo must be recognisable from normal driving distance,
// so the reserved box and image height are enlarged while the aspect ratio is
// always preserved (BoxFit.contain at the call site). White-label and Fluxidi
// fallback logos share the same box, so branding stays consistent.

class DriverNavHeaderLogoMetrics {
  const DriverNavHeaderLogoMetrics({
    required this.boxWidth,
    required this.boxHeight,
    required this.logoHeight,
  });

  /// Reserved horizontal space for the logo (clipped).
  final double boxWidth;

  /// Reserved vertical space for the logo (clipped).
  final double boxHeight;

  /// Target rendered image height (BoxFit.contain preserves aspect ratio).
  final double logoHeight;
}

/// Larger, driving-readable header logo box. Bounded so it still fits inside the
/// nav header band (compact 118 / regular 140 logical px) after the header's
/// pulse scale.
DriverNavHeaderLogoMetrics driverNavHeaderLogoMetrics({
  required bool compact,
}) {
  if (compact) {
    return const DriverNavHeaderLogoMetrics(
      boxWidth: 150,
      boxHeight: 52,
      logoHeight: 46,
    );
  }
  return const DriverNavHeaderLogoMetrics(
    boxWidth: 196,
    boxHeight: 68,
    logoHeight: 62,
  );
}
