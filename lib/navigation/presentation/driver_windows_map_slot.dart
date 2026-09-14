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

String formatDriverDashboardMoney(num amount, [String currency = 'EUR']) {
  final value = amount.toDouble().toStringAsFixed(2).replaceAll('.', ',');
  final cur = currency.toUpperCase();
  if (cur == 'EUR' || cur == 'EURO' || cur == '€') return '€ $value';
  if (cur.length <= 3) return '$cur $value';
  return value;
}

/// Remaining map height inside the landscape "Volgende rit" card.
double driverWindowsNextRideMapHeight({
  required double paneHeight,
  required double summaryHeight,
  required double rideInfoHeight,
  required double actionsHeight,
  double gap = 10,
  double cardPadding = 32,
  double minHeight = 136,
}) {
  final available =
      paneHeight -
      summaryHeight -
      gap -
      rideInfoHeight -
      actionsHeight -
      cardPadding;
  if (!available.isFinite) return minHeight;
  return available < minHeight ? minHeight : available;
}
