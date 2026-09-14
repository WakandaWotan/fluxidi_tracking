// DRIVER-WINDOWS-MAP-SLOT-P0 — flexible map height above the bottom nav.

const double kDriverWindowsMapMinHeight = 220;
const double kDriverWindowsWideWidth = 1524;
const double kDriverWindowsWideHeight = 869;
const double kDriverWindowsCompactWidth = 1100;
const double kDriverWindowsCompactHeight = 720;

double driverWindowsMapSlotHeight({
  required double viewportHeight,
  required double topChrome,
  required double bottomNav,
  double rideInfoHeight = 0,
  double actionsHeight = 0,
  double minHeight = kDriverWindowsMapMinHeight,
}) {
  final available =
      viewportHeight - topChrome - bottomNav - rideInfoHeight - actionsHeight;
  if (!available.isFinite) return minHeight;
  return available < minHeight ? minHeight : available;
}

bool driverWindowsMapOverflows({
  required double viewportHeight,
  required double topChrome,
  required double mapHeight,
  required double rideInfoHeight,
  required double actionsHeight,
  required double bottomNav,
}) {
  return topChrome + mapHeight + rideInfoHeight + actionsHeight + bottomNav >
      viewportHeight + 0.5;
}
