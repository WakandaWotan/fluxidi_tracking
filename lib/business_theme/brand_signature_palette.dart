import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Fixed Fluxidi gold line/accent. Never follows the chosen background.
const Color kBrandSignatureGoldAccent = Color(0xFFD4AF37);
const Color kBrandSignatureGoldBronze = Color(0xFF8A7018);
const Color kBrandSignatureDefaultBase = Color(0xFF5A3D18);

/// Legacy luxury-rail anchors, kept only to migrate stored 0.0–1.0 positions.
const List<Color> kBrandSignatureRailAnchors = <Color>[
  Color(0xFF8A5A2B),
  Color(0xFF6B1C2E),
  Color(0xFF4A1A4A),
  Color(0xFF152044),
  Color(0xFF0E3A3C),
  Color(0xFF0F4A2C),
  Color(0xFF2A2C2E),
  Color(0xFF5A3D18),
];

const double kBrandSignatureDefaultPosition = 1.0;
const double kBrandSignatureBordeauxPosition = 1 / 7;
const double kBrandSignatureMidnightPosition = 3 / 7;
const double kBrandSignatureEmeraldPosition = 5 / 7;

const Map<String, Color> kBrandSignatureNeutralShortcuts = <String, Color>{
  'white': Color(0xFFFFFFFF),
  'warmWhite': Color(0xFFF6EFE4),
  'lightGray': Color(0xFFD0D0D0),
  'midGray': Color(0xFF8A8A8A),
  'anthracite': Color(0xFF2A2C2E),
  'black': Color(0xFF000000),
};

const List<Color> kBrandSignatureHueSpectrum = <Color>[
  Color(0xFFFF0000),
  Color(0xFFFF8000),
  Color(0xFFFFFF00),
  Color(0xFF80FF00),
  Color(0xFF00FF00),
  Color(0xFF00FF80),
  Color(0xFF00FFFF),
  Color(0xFF0080FF),
  Color(0xFF0000FF),
  Color(0xFF4B0082),
  Color(0xFF8B00FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

/// Isolated Brand Signature Gold colors. Driven by one exact base color.
@immutable
class BrandSignaturePalette {
  const BrandSignaturePalette._({
    required this.base,
    required this.header,
    required this.page,
    required this.card,
    required this.kpi,
    required this.border,
    required this.accent,
  });

  factory BrandSignaturePalette.fromColor(Color base) {
    final chosen = Color(base.value | 0xFF000000);
    final lum = brandSignatureRelativeLuminance(chosen);
    late final Color page;
    late final Color header;
    late final Color kpi;
    Color card;
    late final Color border;
    if (lum >= 0.88) {
      page = chosen;
      header = _mix(chosen, const Color(0xFFE4E0D8), 0.42);
      kpi = _mix(chosen, const Color(0xFFD8D4CC), 0.34);
      card = _mix(chosen, const Color(0xFFD0CCC4), 0.28);
      border = kBrandSignatureGoldBronze;
    } else if (lum <= 0.025) {
      page = chosen;
      header = _mix(chosen, const Color(0xFFFFFFFF), 0.07);
      kpi = _mix(chosen, const Color(0xFFFFFFFF), 0.09);
      card = _mix(chosen, const Color(0xFFFFFFFF), 0.12);
      border = kBrandSignatureGoldAccent;
    } else if (lum < 0.38) {
      page = lum < 0.10 ? chosen : _mix(const Color(0xFF000000), chosen, 0.78);
      header = _mix(page, chosen, 0.62);
      kpi = _mix(page, const Color(0xFFFFFFFF), 0.08);
      card = _mix(page, const Color(0xFFFFFFFF), 0.13);
      border = _mix(kBrandSignatureGoldAccent, chosen, 0.22);
    } else {
      page = chosen;
      header = _mix(chosen, const Color(0xFF000000), 0.10);
      kpi = _mix(chosen, const Color(0xFF000000), 0.07);
      card = _mix(chosen, const Color(0xFFFFFFFF), 0.16);
      if ((brandSignatureRelativeLuminance(card) -
              brandSignatureRelativeLuminance(page))
          .abs() <
          0.04) {
        card = _mix(chosen, const Color(0xFF000000), 0.10);
      }
      border = kBrandSignatureGoldBronze;
    }
    return sanitize(
      BrandSignaturePalette._(
        base: chosen,
        header: header,
        page: page,
        card: card,
        kpi: kpi,
        border: border,
        accent: kBrandSignatureGoldAccent,
      ),
    );
  }

  /// Migrates a stored 0.0–1.0 luxury-rail position to one exact RGB color.
  factory BrandSignaturePalette.fromPosition(double position) =>
      BrandSignaturePalette.fromColor(lerpBrandSignatureRail(position));

  final Color base;
  final Color header;
  final Color page;
  final Color card;
  final Color kpi;
  final Color border;
  final Color accent;

  static final BrandSignaturePalette defaults =
      BrandSignaturePalette.fromColor(kBrandSignatureDefaultBase);

  HSVColor get hsv => HSVColor.fromColor(base);

  String get hex => brandSignatureHex(base);

  String get familyId => brandSignatureColorNameId(base);

  BrandSignaturePalette copyWithColor(Color next) =>
      BrandSignaturePalette.fromColor(next);

  Map<String, Object> toJson() => <String, Object>{'argb': base.value};

  static BrandSignaturePalette fromJson(Object? raw) {
    if (raw is Map) {
      final argb = raw['argb'];
      if (argb is num) {
        return BrandSignaturePalette.fromColor(Color(argb.toInt()));
      }
      final hex = raw['hex'];
      if (hex is String) {
        final parsed = parseBrandSignatureHex(hex);
        if (parsed != null) return BrandSignaturePalette.fromColor(parsed);
      }
      final value = raw['position'];
      if (value is num) {
        return BrandSignaturePalette.fromPosition(value.toDouble());
      }
    }
    return defaults;
  }

  @override
  bool operator ==(Object other) {
    return other is BrandSignaturePalette &&
        other.base == base &&
        other.header == header &&
        other.page == page &&
        other.card == card &&
        other.kpi == kpi &&
        other.border == border &&
        other.accent == accent;
  }

  @override
  int get hashCode =>
      Object.hash(base, header, page, card, kpi, border, accent);
}

final ValueNotifier<BrandSignaturePalette> brandSignaturePaletteNotifier =
    ValueNotifier<BrandSignaturePalette>(BrandSignaturePalette.defaults);

Color lerpBrandSignatureRail(double t) {
  final clamped = t.clamp(0.0, 1.0);
  final last = kBrandSignatureRailAnchors.length - 1;
  final scaled = clamped * last;
  final index = scaled.floor().clamp(0, last);
  final next = (index + 1).clamp(0, last);
  final local = scaled - index;
  return Color.lerp(
    kBrandSignatureRailAnchors[index],
    kBrandSignatureRailAnchors[next],
    local,
  )!;
}

Color? parseBrandSignatureHex(String raw) {
  var text = raw.trim();
  if (text.startsWith('#')) text = text.substring(1);
  if (text.length != 6) return null;
  final value = int.tryParse(text, radix: 16);
  if (value == null) return null;
  return Color(0xFF000000 | value);
}

String brandSignatureHex(Color color) {
  final rgb = color.value & 0x00FFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

String brandSignatureColorNameId(Color color) {
  final hsv = HSVColor.fromColor(color);
  if (hsv.saturation < 0.08) {
    if (hsv.value >= 0.96) return 'white';
    if (hsv.value >= 0.86) return 'warmWhite';
    if (hsv.value >= 0.62) return 'lightGray';
    if (hsv.value >= 0.32) return 'midGray';
    if (hsv.value >= 0.08) return 'anthracite';
    return 'black';
  }
  final hue = hsv.hue % 360;
  if (hue < 18 || hue >= 345) return 'red';
  if (hue < 45) return 'orange';
  if (hue < 68) return 'yellow';
  if (hue < 90) return 'lime';
  if (hue < 150) return 'green';
  if (hue < 175) return 'turquoise';
  if (hue < 195) return 'cyan';
  if (hue < 255) return 'blue';
  if (hue < 275) return 'indigo';
  if (hue < 292) return 'violet';
  if (hue < 308) return 'magenta';
  if (hue < 330) return 'purple';
  return 'magenta';
}

/// WCAG relative-luminance contrast ratio for two sRGB colors.
double brandSignatureContrastRatio(Color a, Color b) {
  final l1 = brandSignatureRelativeLuminance(a);
  final l2 = brandSignatureRelativeLuminance(b);
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

BrandSignaturePalette sanitizeBrandSignaturePalette(
  BrandSignaturePalette raw,
) => sanitize(raw);

BrandSignaturePalette sanitize(BrandSignaturePalette raw) {
  return BrandSignaturePalette._(
    base: raw.base,
    header: _ensureReadableSurface(raw.header, raw.header),
    page: _ensureReadableSurface(raw.page, raw.page),
    card: _ensureReadableSurface(raw.card, raw.card),
    kpi: _ensureReadableSurface(raw.kpi, raw.kpi),
    border: raw.border,
    accent: kBrandSignatureGoldAccent,
  );
}

Color _ensureReadableSurface(Color candidate, Color fallback) {
  var current = candidate;
  for (var i = 0; i < 10; i++) {
    if (brandSignatureHasReadableText(
      brandSignatureReadableTextOn(current),
      current,
    )) {
      return current;
    }
    final towardDark = brandSignatureContrastRatio(
      const Color(0xFF1A1408),
      current,
    );
    final towardLight = brandSignatureContrastRatio(
      const Color(0xFFF8F0D8),
      current,
    );
    current = towardDark >= towardLight
        ? _mix(current, const Color(0xFF000000), 0.12)
        : _mix(current, const Color(0xFFFFFFFF), 0.12);
  }
  return fallback;
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

double brandSignatureRelativeLuminance(Color color) {
  double linear(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(color.r) +
      0.7152 * linear(color.g) +
      0.0722 * linear(color.b);
}
