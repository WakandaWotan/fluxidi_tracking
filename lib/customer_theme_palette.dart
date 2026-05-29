import 'package:flutter/material.dart';

enum CustomerThemeVariant { premiumLight, nightGold }

@immutable
class CustomerThemePalette {
  const CustomerThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textMuted,
    required this.gold,
    required this.bronze,
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
  final Color gold;
  final Color bronze;
  final Color border;
  final Color danger;
  final Color success;
  final Color shadow;
  final bool isDark;
}

const CustomerThemePalette _premiumLightPalette = CustomerThemePalette(
  background: Color(0xFFFFFBF4),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFFFF5E8),
  textPrimary: Color(0xFF182028),
  textMuted: Color(0xFF5F6670),
  gold: Color(0xFFC49A45),
  bronze: Color(0xFFB88735),
  border: Color(0xFFE7DECF),
  danger: Color(0xFFCD5C6C),
  success: Color(0xFF34D29A),
  shadow: Color(0x33000000),
  isDark: false,
);

const CustomerThemePalette _nightGoldPalette = CustomerThemePalette(
  background: Color(0xFF07080C),
  surface: Color(0xFF101010),
  surfaceAlt: Color(0xFF16120A),
  textPrimary: Color(0xFFFFFFFF),
  textMuted: Color(0xB3FFFFFF),
  gold: Color(0xFFE5B641),
  bronze: Color(0xFFC8943F),
  border: Color(0xFF3B2C14),
  danger: Color(0xFFCD5C6C),
  success: Color(0xFF34D29A),
  shadow: Color(0x66000000),
  isDark: true,
);

CustomerThemePalette paletteForCustomerTheme(CustomerThemeVariant variant) {
  switch (variant) {
    case CustomerThemeVariant.premiumLight:
      return _premiumLightPalette;
    case CustomerThemeVariant.nightGold:
      return _nightGoldPalette;
  }
}
