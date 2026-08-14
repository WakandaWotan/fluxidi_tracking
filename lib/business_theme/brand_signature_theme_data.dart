import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/driver_theme_palette.dart';

/// Central ThemeData for Brand Signature Gold business routes only.
ThemeData themeDataForBrandSignatureGold(BusinessThemePalette palette) {
  final brightness = palette.isDark ? Brightness.dark : Brightness.light;
  final text = Typography.material2021(platform: TargetPlatform.android)
      .black
      .apply(
        bodyColor: palette.textPrimary,
        displayColor: palette.textPrimary,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: palette.background,
    canvasColor: palette.background,
    cardColor: palette.surface,
    dividerColor: palette.border,
    iconTheme: IconThemeData(color: palette.textPrimary),
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: palette.accent,
      onPrimary: palette.textOnAccent,
      secondary: palette.accent,
      onSecondary: palette.textOnAccent,
      error: palette.danger,
      onError: const Color(0xFFFFFFFF),
      surface: palette.surface,
      onSurface: palette.textPrimary,
    ),
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.surfaceAlt,
      foregroundColor: palette.textPrimary,
      elevation: 0,
      iconTheme: IconThemeData(color: palette.textPrimary),
      titleTextStyle: TextStyle(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.surface,
      shadowColor: palette.shadow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border.withOpacity(0.72)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      titleTextStyle: TextStyle(
        color: palette.textPrimary,
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
      contentTextStyle: TextStyle(color: palette.textSecondary, fontSize: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: palette.surface,
      modalBackgroundColor: palette.surface,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceAlt,
      hintStyle: TextStyle(color: palette.textMuted),
      labelStyle: TextStyle(color: palette.textSecondary),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: palette.accent, width: 1.4),
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.textOnAccent,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.textPrimary,
        side: BorderSide(color: palette.accent),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: palette.surfaceAlt,
      contentTextStyle: TextStyle(color: palette.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
  );
}

/// Gold overlay applies only inside an active business shell with no
/// chauffeur frame. Existing business themes and driver themes stay intact.
ThemeData? brandSignatureBusinessOverlayTheme({
  required bool businessShellActive,
  required DriverThemeVariant? chauffeurShellTheme,
  required BusinessThemeVariant variant,
}) {
  if (!businessShellActive || chauffeurShellTheme != null) return null;
  if (variant != BusinessThemeVariant.brandSignatureGold) return null;
  return themeDataForBrandSignatureGold(paletteForBusinessTheme(variant));
}
