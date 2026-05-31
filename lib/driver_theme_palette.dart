import 'package:flutter/material.dart';

enum DriverThemeVariant { nightGold, midnightBlue, highContrast }

@immutable
class DriverThemePalette {
  const DriverThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.border,
    required this.danger,
    required this.success,
    required this.shadow,
    required this.isDark,
  });

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textMuted;
  final Color accent;
  final Color border;
  final Color danger;
  final Color success;
  final Color shadow;
  final bool isDark;
}

const DriverThemePalette _nightGoldPalette = DriverThemePalette(
  background: Color(0xFF07080C),
  surface: Color(0xFF101113),
  surfaceAlt: Color(0xFF16120A),
  textPrimary: Color(0xFFFFFFFF),
  textMuted: Color(0xFFB4B4B4),
  accent: Color(0xFFE5B641),
  border: Color(0xFF3B2C14),
  danger: Color(0xFFF97373),
  success: Color(0xFF34D29A),
  shadow: Color(0x66000000),
  isDark: true,
);

const DriverThemePalette _midnightBluePalette = DriverThemePalette(
  background: Color(0xFF08142D),
  surface: Color(0xFF101E3A),
  surfaceAlt: Color(0xFF0F1A2F),
  textPrimary: Color(0xFFF4F8FF),
  textMuted: Color(0xFFB6C4DA),
  accent: Color(0xFFFFD54F),
  border: Color(0xFF2D8CFF),
  danger: Color(0xFFFF6B5F),
  success: Color(0xFF4CD964),
  shadow: Color(0x70000000),
  isDark: true,
);

const DriverThemePalette _highContrastPalette = DriverThemePalette(
  background: Color(0xFF120F0B),
  surface: Color(0xFF1B1712),
  surfaceAlt: Color(0xFF261F15),
  textPrimary: Color(0xFFF7E9C8),
  textMuted: Color(0xFFDAC9A6),
  accent: Color(0xFFE8C57E),
  border: Color(0xFF8A7040),
  danger: Color(0xFFE27C7C),
  success: Color(0xFF69C89F),
  shadow: Color(0x68000000),
  isDark: true,
);

DriverThemePalette paletteForDriverTheme(DriverThemeVariant variant) {
  switch (variant) {
    case DriverThemeVariant.nightGold:
      return _nightGoldPalette;
    case DriverThemeVariant.midnightBlue:
      return _midnightBluePalette;
    case DriverThemeVariant.highContrast:
      return _highContrastPalette;
  }
}
