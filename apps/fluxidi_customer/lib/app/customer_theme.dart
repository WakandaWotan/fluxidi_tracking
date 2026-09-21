import 'package:flutter/material.dart';

import 'customer_app_config.dart';

ThemeData buildCustomerTheme(CustomerAppConfig config) {
  final brand = config.brand;
  final scheme = ColorScheme.fromSeed(
    seedColor: brand.primary,
    brightness: Brightness.dark,
  ).copyWith(
    primary: brand.primary,
    secondary: brand.accent,
    surface: brand.surface,
    onPrimary: Colors.black,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: brand.background,
    appBarTheme: AppBarTheme(
      backgroundColor: brand.background,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: brand.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
      ),
    ),
    textTheme: Typography.whiteMountainView.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: brand.primary,
        foregroundColor: Colors.black,
      ),
    ),
  );
}
