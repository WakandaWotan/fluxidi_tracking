import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Fixed Fluxidi gold line/accent. Never follows the background rail.
const Color kBrandSignatureGoldAccent = Color(0xFFD4AF37);

/// Warm gold-brown end of the rail — the shipped Brand Signature default.
const double kBrandSignatureDefaultPosition = 1.0;
const double kBrandSignatureBordeauxPosition = 1 / 7;
const double kBrandSignatureMidnightPosition = 3 / 7;
const double kBrandSignatureEmeraldPosition = 5 / 7;

/// Visible rail anchors: warm bronze → burgundy → aubergine → midnight
/// blue → petroleum → emerald → anthracite → warm gold-brown.
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

const List<String> kBrandSignatureFamilyIds = <String>[
  'bronze',
  'bordeaux',
  'aubergine',
  'midnight',
  'petroleum',
  'emerald',
  'anthracite',
  'goldBrown',
];

double brandSignatureStopPosition(int index) {
  if (kBrandSignatureRailAnchors.length <= 1) return 0;
  return (index.clamp(0, kBrandSignatureRailAnchors.length - 1)) /
      (kBrandSignatureRailAnchors.length - 1);
}

/// Isolated Brand Signature Gold colors. Driven by one rail position.
@immutable
class BrandSignaturePalette {
  const BrandSignaturePalette._({
    required this.position,
    required this.header,
    required this.page,
    required this.card,
    required this.kpi,
    required this.border,
    required this.accent,
    required this.base,
  });

  factory BrandSignaturePalette.fromPosition(double position) {
    final t = position.clamp(0.0, 1.0);
    final base = lerpBrandSignatureRail(t);
    final page = _mix(const Color(0xFF050403), base, 0.20);
    final header = _mix(const Color(0xFF070605), base, 0.30);
    final kpi = _mix(const Color(0xFF080706), base, 0.34);
    final card = _mix(const Color(0xFF0A0806), base, 0.40);
    final border = _mix(kBrandSignatureGoldAccent, base, 0.42);
    return sanitize(
      BrandSignaturePalette._(
        position: t,
        header: header,
        page: page,
        card: card,
        kpi: kpi,
        border: border,
        accent: kBrandSignatureGoldAccent,
        base: base,
      ),
    );
  }

  final double position;
  final Color header;
  final Color page;
  final Color card;
  final Color kpi;
  final Color border;
  final Color accent;
  final Color base;

  static final BrandSignaturePalette defaults =
      BrandSignaturePalette.fromPosition(kBrandSignatureDefaultPosition);

  String get familyId => brandSignatureFamilyId(position);

  BrandSignaturePalette copyWithPosition(double next) =>
      BrandSignaturePalette.fromPosition(next);

  Map<String, Object> toJson() => <String, Object>{'position': position};

  static BrandSignaturePalette fromJson(Object? raw) {
    if (raw is Map) {
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
        other.position == position &&
        other.header == header &&
        other.page == page &&
        other.card == card &&
        other.kpi == kpi &&
        other.border == border &&
        other.accent == accent &&
        other.base == base;
  }

  @override
  int get hashCode =>
      Object.hash(position, header, page, card, kpi, border, accent, base);
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

String brandSignatureFamilyId(double position) {
  final last = kBrandSignatureFamilyIds.length - 1;
  final index = (position.clamp(0.0, 1.0) * last).round().clamp(0, last);
  return kBrandSignatureFamilyIds[index];
}

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

BrandSignaturePalette sanitizeBrandSignaturePalette(
  BrandSignaturePalette raw,
) => sanitize(raw);

BrandSignaturePalette sanitize(BrandSignaturePalette raw) {
  var page = _ensureReadableSurface(raw.page, raw.page);
  var header = _ensureReadableSurface(raw.header, raw.header);
  var card = _ensureReadableSurface(raw.card, raw.card);
  var kpi = _ensureReadableSurface(raw.kpi, raw.kpi);
  return BrandSignaturePalette._(
    position: raw.position.clamp(0.0, 1.0),
    header: header,
    page: page,
    card: card,
    kpi: kpi,
    border: raw.border,
    accent: kBrandSignatureGoldAccent,
    base: raw.base,
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

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

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
