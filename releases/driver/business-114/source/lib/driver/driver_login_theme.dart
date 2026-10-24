import 'package:flutter/material.dart';
import '../business_theme_palette.dart';
import '../company/company_ops_theme.dart';

/// Login-local presentation of the existing company palette. Never persists
/// colors, changes the active company, or changes other app surfaces.
ThemeData driverLoginTheme(BusinessThemePalette palette) {
  final base = companyOpsMaterialTheme(palette);
  final text = companyOpsReadableOn(palette.background, palette);
  final onAccent = companyOpsReadableOn(palette.accent, palette);
  final outline = companyOpsEnsureContrast(
    color: palette.border,
    background: palette.background,
    minRatio: 3,
    toward: text,
  );
  final accentText = companyOpsEnsureContrast(
    color: palette.accent,
    background: palette.background,
    minRatio: 4.5,
    toward: text,
  );
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(18));
  final button = ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(0, 54)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    shape: WidgetStatePropertyAll(shape),
  );
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      onPrimary: onAccent,
      onSurface: text,
      onSurfaceVariant: text,
      outline: outline,
    ),
    textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: palette.background,
      foregroundColor: text,
      iconTheme: IconThemeData(color: text),
    ),
    iconTheme: IconThemeData(color: text),
    filledButtonTheme: FilledButtonThemeData(
      style: button.merge(
        FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: onAccent,
          disabledBackgroundColor: palette.surfaceAlt,
          disabledForegroundColor: companyOpsReadableOn(
            palette.surfaceAlt,
            palette,
          ),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button.merge(
        OutlinedButton.styleFrom(
          foregroundColor: accentText,
          side: BorderSide(color: outline, width: 1.5),
          disabledForegroundColor: text,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button.merge(TextButton.styleFrom(foregroundColor: accentText)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: text),
      hintStyle: TextStyle(color: text),
      prefixIconColor: text,
      suffixIconColor: text,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: accentText, width: 2.5),
      ),
    ),
  );
}
