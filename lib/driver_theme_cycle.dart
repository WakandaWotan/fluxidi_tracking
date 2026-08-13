import 'package:fluxidi_tracking/driver_theme_palette.dart';

/// Product cycle order for the chauffeur/driver theme shortcut.
///
/// Authoritative order matches [DriverThemeVariant] declaration and the
/// settings selector — never inferred from asset folders on disk.
const List<DriverThemeVariant> kDriverThemeCycleOrder = <DriverThemeVariant>[
  DriverThemeVariant.nightGold,
  DriverThemeVariant.midnightBlue,
  DriverThemeVariant.highContrast, // Midday Gold
  DriverThemeVariant.lightEmerald,
];

/// Advances one step in [kDriverThemeCycleOrder], wrapping after the last.
///
/// Unknown/legacy values fall back to the first cycle entry.
DriverThemeVariant nextDriverThemeVariant(DriverThemeVariant current) {
  final index = kDriverThemeCycleOrder.indexOf(current);
  if (index < 0) {
    return kDriverThemeCycleOrder.first;
  }
  return kDriverThemeCycleOrder[(index + 1) % kDriverThemeCycleOrder.length];
}

/// Human-readable product name for the active driver theme.
String driverThemeProductLabel(DriverThemeVariant variant) {
  switch (variant) {
    case DriverThemeVariant.nightGold:
      return 'Night Gold';
    case DriverThemeVariant.midnightBlue:
      return 'Midnight Blue';
    case DriverThemeVariant.highContrast:
      return 'Midday Gold';
    case DriverThemeVariant.lightEmerald:
      return 'Light Emerald';
  }
}
