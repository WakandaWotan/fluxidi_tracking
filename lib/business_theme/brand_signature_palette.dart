import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Isolated Brand Signature Gold colors. Never written into existing
/// business-theme palettes.
@immutable
class BrandSignaturePalette {
  const BrandSignaturePalette({
    required this.header,
    required this.page,
    required this.card,
    required this.accent,
  });

  final Color header;
  final Color page;
  final Color card;
  final Color accent;

  static const BrandSignaturePalette defaults = BrandSignaturePalette(
    header: Color(0xFF1A1408),
    page: Color(0xFF0C0A07),
    card: Color(0xFF1C160C),
    accent: Color(0xFFD4AF37),
  );

  BrandSignaturePalette copyWith({
    Color? header,
    Color? page,
    Color? card,
    Color? accent,
  }) {
    return BrandSignaturePalette(
      header: header ?? this.header,
      page: page ?? this.page,
      card: card ?? this.card,
      accent: accent ?? this.accent,
    );
  }

  Map<String, int> toJson() => <String, int>{
    'header': header.value,
    'page': page.value,
    'card': card.value,
    'accent': accent.value,
  };

  static BrandSignaturePalette fromJson(Object? raw) {
    if (raw is! Map) return defaults;
    Color read(String key, Color fallback) {
      final value = raw[key];
      if (value is int) return Color(value);
      if (value is num) return Color(value.toInt());
      return fallback;
    }

    return sanitize(
      BrandSignaturePalette(
        header: read('header', defaults.header),
        page: read('page', defaults.page),
        card: read('card', defaults.card),
        accent: read('accent', defaults.accent),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BrandSignaturePalette &&
        other.header == header &&
        other.page == page &&
        other.card == card &&
        other.accent == accent;
  }

  @override
  int get hashCode => Object.hash(header, page, card, accent);
}

final ValueNotifier<BrandSignaturePalette> brandSignaturePaletteNotifier =
    ValueNotifier<BrandSignaturePalette>(BrandSignaturePalette.defaults);

/// WCAG relative-luminance contrast ratio for two sRGB colors.
double brandSignatureContrastRatio(Color a, Color b) {
  final l1 = _relativeLuminance(a);
  final l2 = _relativeLuminance(b);
  final light = l1 > l2 ? l1 : l2;
  final dark = l1 > l2 ? l2 : l1;
  return (light + 0.05) / (dark + 0.05);
}

bool brandSignatureHasReadableText(Color text, Color background) =>
    brandSignatureContrastRatio(text, background) >= 4.5;

Color brandSignatureReadableTextOn(Color background) {
  const light = Color(0xFFF8F0D8);
  const dark = Color(0xFF1A1408);
  final lightRatio = brandSignatureContrastRatio(light, background);
  final darkRatio = brandSignatureContrastRatio(dark, background);
  return lightRatio >= darkRatio ? light : dark;
}

/// Rejects inaccessible combinations by nudging colors toward the defaults
/// until body text and accent labels meet WCAG AA (4.5:1).
BrandSignaturePalette sanitizeBrandSignaturePalette(
  BrandSignaturePalette raw,
) => sanitize(raw);

BrandSignaturePalette sanitize(BrandSignaturePalette raw) {
  var page = raw.page;
  var header = raw.header;
  var card = raw.card;
  var accent = raw.accent;

  page = _ensureReadableSurface(page, BrandSignaturePalette.defaults.page);
  header = _ensureReadableSurface(
    header,
    BrandSignaturePalette.defaults.header,
  );
  card = _ensureReadableSurface(card, BrandSignaturePalette.defaults.card);

  final pageIsDark = _relativeLuminance(page) < 0.45;
  final cardIsDark = _relativeLuminance(card) < 0.45;
  if (pageIsDark != cardIsDark) {
    card = pageIsDark
        ? BrandSignaturePalette.defaults.card
        : const Color(0xFFF3E6C4);
  }

  accent = _ensureReadableAccent(accent, card);
  return BrandSignaturePalette(
    header: header,
    page: page,
    card: card,
    accent: accent,
  );
}

Color _ensureReadableSurface(Color candidate, Color fallback) {
  if (brandSignatureHasReadableText(
    brandSignatureReadableTextOn(candidate),
    candidate,
  )) {
    return candidate;
  }
  return fallback;
}

Color _ensureReadableAccent(Color accent, Color card) {
  final onAccent = brandSignatureReadableTextOn(accent);
  if (brandSignatureHasReadableText(onAccent, accent) &&
      brandSignatureContrastRatio(accent, card) >= 3.0) {
    return accent;
  }
  return BrandSignaturePalette.defaults.accent;
}

double _relativeLuminance(Color color) {
  double linear(int channel) {
    final value = channel / 255.0;
    return value <= 0.03928
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(color.red) +
      0.7152 * linear(color.green) +
      0.0722 * linear(color.blue);
}
