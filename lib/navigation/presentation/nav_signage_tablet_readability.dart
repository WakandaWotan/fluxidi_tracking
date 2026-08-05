import 'dart:math' as math;

import 'package:flutter/material.dart';

/// NAV-SIGNAGE-TABLET-READABILITY-1: tablet form-factor gate for navigation
/// signage sizing and top-row placement.
///
/// Logical [Size.shortestSide] only — never device model names or physical
/// pixels. Phones (shortestSide < 600) keep the existing banner metrics and
/// portrait-below-logo placement.
const double kNavSignageTabletShortestSide = 600;

bool isNavSignageTabletLayout(Size size) =>
    size.shortestSide >= kNavSignageTabletShortestSide;

/// Resolved tablet banner metrics after clamping to the available width.
@immutable
class NavSignageTabletReadabilityMetrics {
  const NavSignageTabletReadabilityMetrics({
    required this.isLandscape,
    required this.bannerMinHeight,
    required this.bannerMaxWidth,
    required this.bannerMinWidth,
    required this.signSize,
    required this.iconBoxSize,
    required this.distanceFontSize,
    required this.primaryFontSize,
    required this.secondaryFontSize,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.compassReserve,
    required this.signPlateInset,
  });

  final bool isLandscape;

  /// Soft floor for the maneuver card height (content may grow with lanes).
  final double bannerMinHeight;

  /// Content-adaptive width ceiling for the maneuver card.
  final double bannerMaxWidth;
  final double bannerMinWidth;

  /// Edge length passed to [NavManeuverSign] (the painted plate itself).
  final double signSize;

  /// Outer light plate container around the sign.
  final double iconBoxSize;

  final double distanceFontSize;
  final double primaryFontSize;
  final double secondaryFontSize;
  final double horizontalPadding;
  final double verticalPadding;

  /// Right inset reserved so the top-row banner never overlaps the Mapbox
  /// compass control.
  final double compassReserve;

  final double signPlateInset;

  /// Target ranges before available-width clamping.
  static const double portraitBannerHeightMin = 100;
  static const double portraitBannerHeightMax = 112;
  static const double portraitBannerWidthMin = 330;
  static const double portraitBannerWidthMax = 390;

  static const double landscapeBannerHeightMin = 96;
  static const double landscapeBannerHeightMax = 108;
  static const double landscapeBannerWidthMin = 390;
  static const double landscapeBannerWidthMax = 470;

  static const double signSizeMin = 88;
  static const double signSizeMax = 100;

  static const double distanceFontMin = 21;
  static const double distanceFontMax = 23;
  static const double primaryFontMin = 24;
  static const double primaryFontMax = 27;
  static const double secondaryFontMin = 20;
  static const double secondaryFontMax = 22;

  static const double defaultCompassReserve = 96;

  /// Resolve metrics for the current orientation and the width the banner may
  /// actually occupy (viewport minus menu, logo, gaps and compass reserve).
  factory NavSignageTabletReadabilityMetrics.resolve({
    required bool isLandscape,
    required double availableBannerWidth,
  }) {
    final widthBudget = availableBannerWidth.isFinite && availableBannerWidth > 0
        ? availableBannerWidth
        : (isLandscape ? landscapeBannerWidthMax : portraitBannerWidthMax);

    final targetMax = isLandscape
        ? landscapeBannerWidthMax
        : portraitBannerWidthMax;
    final targetMin = isLandscape
        ? landscapeBannerWidthMin
        : portraitBannerWidthMin;

    // Narrower tablets: shrink the width ceiling before the min so we never
    // request minWidth > maxWidth. Floor at a still-glanceable 280.
    final maxWidth = math
        .min(targetMax, widthBudget)
        .clamp(280.0, targetMax)
        .toDouble();
    final minWidth = math.min(targetMin, maxWidth).toDouble();

    // Scale the sign with available width; stay inside 88–100.
    final widthT = ((maxWidth - 280) / (targetMax - 280)).clamp(0.0, 1.0);
    final signSize =
        (signSizeMin + (signSizeMax - signSizeMin) * widthT).clamp(
          signSizeMin,
          signSizeMax,
        );
    const inset = 4.0;
    final iconBox = signSize + inset * 2;

    final heightMin = isLandscape
        ? landscapeBannerHeightMin
        : portraitBannerHeightMin;
    final heightMax = isLandscape
        ? landscapeBannerHeightMax
        : portraitBannerHeightMax;
    final bannerMinHeight =
        (heightMin + (heightMax - heightMin) * widthT).clamp(
          heightMin,
          heightMax,
        );

    final distanceFont =
        (distanceFontMin + (distanceFontMax - distanceFontMin) * widthT)
            .clamp(distanceFontMin, distanceFontMax);
    final primaryFont =
        (primaryFontMin + (primaryFontMax - primaryFontMin) * widthT)
            .clamp(primaryFontMin, primaryFontMax);
    final secondaryFont =
        (secondaryFontMin + (secondaryFontMax - secondaryFontMin) * widthT)
            .clamp(secondaryFontMin, secondaryFontMax);

    return NavSignageTabletReadabilityMetrics(
      isLandscape: isLandscape,
      bannerMinHeight: bannerMinHeight,
      bannerMaxWidth: maxWidth,
      bannerMinWidth: minWidth,
      signSize: signSize,
      iconBoxSize: iconBox,
      distanceFontSize: distanceFont,
      primaryFontSize: primaryFont,
      secondaryFontSize: secondaryFont,
      horizontalPadding: isLandscape ? 12 : 14,
      verticalPadding: isLandscape ? 8 : 10,
      compassReserve: defaultCompassReserve,
      signPlateInset: inset,
    );
  }

  /// Convenience for widget tests that already know the viewport size.
  factory NavSignageTabletReadabilityMetrics.forViewport({
    required Size viewport,
    required bool isLandscape,
    double menuWidth = 44,
    double logoWidth = 118,
    double gaps = 8 + 8,
  }) {
    final reserve = defaultCompassReserve;
    final sideInsets = isLandscape ? 20.0 : 20.0;
    final available = viewport.width - sideInsets - menuWidth - logoWidth - gaps - reserve;
    return NavSignageTabletReadabilityMetrics.resolve(
      isLandscape: isLandscape,
      availableBannerWidth: available,
    );
  }
}
