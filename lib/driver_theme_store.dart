import 'package:flutter/foundation.dart';

import 'driver_app_theme_store.dart';
import 'driver_theme_palette.dart';

/// Backward-compatible alias used by existing driver UI code.
///
/// Ownership now points to the real chauffeur app personal preference domain.
final ValueNotifier<DriverThemeVariant> driverThemeNotifier =
    driverAppThemeNotifier;

/// Active chauffeur shell theme while [DriverHomePage] is mounted; otherwise null.
final ValueNotifier<DriverThemeVariant?> chauffeurShellFrameThemeNotifier =
    ValueNotifier<DriverThemeVariant?>(null);

Future<void> loadDriverThemePreference() async {
  await loadDriverAppThemePreference();
}

Future<void> saveDriverThemePreference(DriverThemeVariant variant) async {
  await saveDriverAppThemePreference(variant);
}
