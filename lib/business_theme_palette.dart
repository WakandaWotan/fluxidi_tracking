import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';

enum BusinessThemeVariant {
  executiveGold,
  corporateBlue,
  cleanProfessional,
  emeraldIvory,
  fluxidiNeonRush,
  brandSignatureGold,
}

@immutable
class BusinessThemePalette {
  const BusinessThemePalette({
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textOnAccent,
    required this.textOnWarning,
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
  final Color textSecondary;
  final Color textMuted;
  final Color textOnAccent;
  final Color textOnWarning;
  final Color accent;
  final Color border;
  final Color danger;
  final Color success;
  final Color shadow;
  final bool isDark;
}

const BusinessThemePalette _executiveGoldPalette = BusinessThemePalette(
  background: Color(0xFF07080C),
  surface: Color(0xFF101010),
  surfaceAlt: Color(0xFF16120A),
  textPrimary: Color(0xFFFFFFFF),
  textSecondary: Color(0xFFE9E9E9),
  textMuted: Color(0xFFB4B4B4),
  textOnAccent: Color(0xFF1B1B1B),
  textOnWarning: Color(0xFFFFF2CC),
  accent: Color(0xFFE5B641),
  border: Color(0xFF3B2C14),
  danger: Color(0xFFCD5C6C),
  success: Color(0xFF34D29A),
  shadow: Color(0x66000000),
  isDark: true,
);

const BusinessThemePalette _corporateBluePalette = BusinessThemePalette(
  background: Color(0xFF0B1020),
  surface: Color(0xFF111827),
  surfaceAlt: Color(0xFF1A2437),
  textPrimary: Color(0xFFF4F8FF),
  textSecondary: Color(0xFFDCE7F8),
  textMuted: Color(0xFFB8C4D6),
  textOnAccent: Color(0xFF0E1422),
  textOnWarning: Color(0xFFFFF0CC),
  accent: Color(0xFF60A5FA),
  border: Color(0xFF31445F),
  danger: Color(0xFFD46A7B),
  success: Color(0xFF34D29A),
  shadow: Color(0x70000000),
  isDark: true,
);

const BusinessThemePalette _cleanProfessionalPalette = BusinessThemePalette(
  background: Color(0xFFF4F6FA),
  surface: Color(0xFFFFFFFF),
  surfaceAlt: Color(0xFFEFF2F8),
  textPrimary: Color(0xFF1C2430),
  textSecondary: Color(0xFF2D3A4C),
  textMuted: Color(0xFF5F6B7A),
  textOnAccent: Color(0xFFFFFFFF),
  textOnWarning: Color(0xFF3C2900),
  // Darker than blue-500 so white label text meets WCAG AA (≥4.5:1).
  accent: Color(0xFF1D4ED8),
  border: Color(0xFFD7DEE9),
  danger: Color(0xFFC95D6D),
  success: Color(0xFF2FAE7B),
  shadow: Color(0x22000000),
  isDark: false,
);

const BusinessThemePalette _emeraldIvoryPalette = BusinessThemePalette(
  background: Color(0xFF081411),
  surface: Color(0xFF10201B),
  surfaceAlt: Color(0xFF1A2E27),
  textPrimary: Color(0xFFF3E8CF),
  textSecondary: Color(0xFFE5D7BA),
  textMuted: Color(0xFFC1B99E),
  textOnAccent: Color(0xFF1A1406),
  textOnWarning: Color(0xFFFFF2CC),
  accent: Color(0xFFC9A85F),
  border: Color(0xFF5E573F),
  danger: Color(0xFFD07A82),
  success: Color(0xFF49B889),
  shadow: Color(0x5C000000),
  isDark: true,
);

/// Dark premium palette with neon magenta-violet accents and electric-mint
/// success cues. Designed to feel like a high-end taxi/dispatch console: glowy
/// but not gamer-childish, with high contrast on tablet and phone.
const BusinessThemePalette _fluxidiNeonRushPalette = BusinessThemePalette(
  background: Color(0xFF0A0716),
  surface: Color(0xFF120D26),
  surfaceAlt: Color(0xFF1B1437),
  textPrimary: Color(0xFFF5F0FF),
  textSecondary: Color(0xFFD9CCFF),
  textMuted: Color(0xFF9D8FCC),
  textOnAccent: Color(0xFF0A0716),
  textOnWarning: Color(0xFFFFE9A8),
  accent: Color(0xFFB845FF),
  border: Color(0xFF3D2D63),
  danger: Color(0xFFFF4D86),
  success: Color(0xFF4CFFB0),
  shadow: Color(0x99000000),
  isDark: true,
);

BusinessThemePalette paletteForBusinessTheme(BusinessThemeVariant variant) {
  switch (variant) {
    case BusinessThemeVariant.executiveGold:
      return _executiveGoldPalette;
    case BusinessThemeVariant.corporateBlue:
      return _corporateBluePalette;
    case BusinessThemeVariant.cleanProfessional:
      return _cleanProfessionalPalette;
    case BusinessThemeVariant.emeraldIvory:
      return _emeraldIvoryPalette;
    case BusinessThemeVariant.fluxidiNeonRush:
      return _fluxidiNeonRushPalette;
    case BusinessThemeVariant.brandSignatureGold:
      return brandSignatureBusinessPalette(brandSignaturePaletteNotifier.value);
  }
}

/// Maps the isolated Brand Signature colors onto the shared palette shape
/// without mutating any existing preset constants.
BusinessThemePalette brandSignatureBusinessPalette(
  BrandSignaturePalette colors,
) {
  final safe = sanitizeBrandSignaturePalette(colors);
  final textPrimary = brandSignatureReadableTextOn(safe.card);
  final textOnAccent = brandSignatureReadableTextOn(safe.accent);
  final isDark =
      brandSignatureContrastRatio(const Color(0xFFFFFFFF), safe.page) >=
      brandSignatureContrastRatio(const Color(0xFF000000), safe.page);
  return BusinessThemePalette(
    background: safe.page,
    surface: safe.card,
    surfaceAlt: safe.header,
    textPrimary: textPrimary,
    textSecondary: _readableMuted(textPrimary, safe.card, 0.18),
    textMuted: _readableMuted(textPrimary, safe.card, 0.28),
    textOnAccent: textOnAccent,
    textOnWarning: const Color(0xFFFFF2CC),
    accent: safe.accent,
    border: Color.lerp(safe.accent, safe.card, 0.45)!,
    danger: const Color(0xFFD07A82),
    success: const Color(0xFF49B889),
    shadow: const Color(0x99000000),
    isDark: isDark,
  );
}

Color _readableMuted(Color text, Color background, double mix) {
  final candidate = Color.lerp(text, background, mix)!;
  if (brandSignatureContrastRatio(candidate, background) >= 4.5) {
    return candidate;
  }
  return text;
}
