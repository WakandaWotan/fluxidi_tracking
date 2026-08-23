import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/driver_theme/driver_custom_huis_stijl.dart';

enum DriverThemeVariant {
  nightGold,
  midnightBlue,
  highContrast,
  lightEmerald,
  customHuisstijl,
}

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
  accent: Color(0xFF4DA3FF),
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

const DriverThemePalette _lightEmeraldPalette = DriverThemePalette(
  background: Color(0xFFEEF5F2),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFE4F1EB),
  textPrimary: Color(0xFF143028),
  textMuted: Color(0xFF4A665C),
  accent: Color(0xFF1F8A65),
  border: Color(0xFFB7CEC4),
  danger: Color(0xFFC23B3B),
  success: Color(0xFF1F8A65),
  shadow: Color(0x1A143028),
  isDark: false,
);

/// Surface/foreground pairing used by chauffeur ride cards.
/// Light themes keep the light card surface; dark themes keep dark cards.
({Color surface, Color foreground, Color muted}) driverRideCardColors(
  DriverThemeVariant variant,
) {
  final palette = paletteForDriverTheme(variant);
  if (!palette.isDark) {
    return (
      surface: const Color(0xFFF7FAF8),
      foreground: palette.textPrimary,
      muted: palette.textMuted,
    );
  }
  return (
    surface: palette.surface,
    foreground: palette.textPrimary,
    muted: palette.textMuted,
  );
}

DriverThemePalette paletteForDriverTheme(DriverThemeVariant variant) {
  switch (variant) {
    case DriverThemeVariant.nightGold:
      return _nightGoldPalette;
    case DriverThemeVariant.midnightBlue:
      return _midnightBluePalette;
    case DriverThemeVariant.highContrast:
      return _highContrastPalette;
    case DriverThemeVariant.lightEmerald:
      return _lightEmeraldPalette;
    case DriverThemeVariant.customHuisstijl:
      return _paletteForCustomHuisstijl();
  }
}

bool isDriverCustomHuisstijl(DriverThemeVariant variant) =>
    variant == DriverThemeVariant.customHuisstijl;

DriverThemePalette _paletteForCustomHuisstijl() {
  final safe = sanitizeBrandSignaturePalette(
    driverBrandSignaturePaletteNotifier.value,
  );
  final textPrimary = brandSignatureReadableTextOn(safe.page);
  final isDark =
      brandSignatureContrastRatio(const Color(0xFFFFFFFF), safe.page) >=
      brandSignatureContrastRatio(const Color(0xFF000000), safe.page);
  return DriverThemePalette(
    background: safe.page,
    surface: safe.kpi,
    surfaceAlt: safe.header,
    textPrimary: textPrimary,
    textMuted: Color.lerp(textPrimary, safe.kpi, 0.28)!,
    accent: safe.accent,
    border: safe.border,
    danger: const Color(0xFFD07A82),
    success: const Color(0xFF49B889),
    shadow: const Color(0x99000000),
    isDark: isDark,
  );
}
