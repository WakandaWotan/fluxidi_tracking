import 'dart:math' as math;

import 'package:flutter/material.dart';

/// NAV-SIGNAGE-TABLET-READABILITY-1 / NAV-SIGNAGE-FIELD-QUALITY-P0-1:
/// tablet form-factor gate for navigation signage sizing and top-row placement.
///
/// FLUXIDI-HOST-FORM-FACTOR-P0: prefer [hostIsTablet] (physical display /
/// sticky latch). Falling back to [Size.shortestSide] alone mis-classifies a
/// tablet host when Android split-screen shrinks the current window below 600.
/// Phones (host shortestSide < 600) keep the existing banner metrics and
/// portrait-below-logo placement.
const double kNavSignageTabletShortestSide = 600;

bool isNavSignageTabletLayout(
  Size size, {
  bool? hostIsTablet,
}) {
  if (hostIsTablet != null) return hostIsTablet;
  return size.shortestSide >= kNavSignageTabletShortestSide;
}

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
    this.isSplitNav = false,
    this.isNarrowPane = false,
    this.useTransparentChrome = false,
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

  /// True when metrics target the Tellers + navigatie split column.
  final bool isSplitNav;

  /// True when the banner occupies a narrow Android split pane (vertical
  /// split / small maneuver column). Host may still be tablet (HUD 132).
  final bool isNarrowPane;

  /// Phone parity: paint maneuver chrome over the map (no navy fill).
  final bool useTransparentChrome;

  /// Available maneuver-column width below which tablet hosts use the compact
  /// narrow-pane banner (LayoutBuilder / real pane constraints — not host
  /// shortestSide alone).
  static const double narrowPaneAvailableWidthThreshold = 360;

  /// Full-navigation target ranges before available-width clamping.
  /// TABLET-LOCALIZED-NAV-SIGNAGE-1: taller band for captioned ~160–180 px plates.
  static const double portraitBannerHeightMin = 168;
  static const double portraitBannerHeightMax = 196;
  static const double portraitBannerWidthMin = 420;
  static const double portraitBannerWidthMax = 620;

  static const double landscapeBannerHeightMin = 160;
  static const double landscapeBannerHeightMax = 188;
  static const double landscapeBannerWidthMin = 460;
  static const double landscapeBannerWidthMax = 580;

  /// TABLET-LOCALIZED-NAV-SIGNAGE-1: full-nav captioned plate ~160–180 px.
  static const double signSizeMin = 160;
  static const double signSizeMax = 180;

  static const double distanceFontMin = 26;
  static const double distanceFontMax = 30;
  static const double primaryFontMin = 26;
  static const double primaryFontMax = 30;
  static const double secondaryFontMin = 24;
  static const double secondaryFontMax = 28;

  /// Tellers + navigatie split — captioned plate still readable while driving.
  static const double splitSignSizeMin = 120;
  static const double splitSignSizeMax = 140;
  static const double splitPrimaryFontMin = 22;
  static const double splitPrimaryFontMax = 26;
  static const double splitDistanceFontMin = 22;
  static const double splitDistanceFontMax = 26;
  static const double splitSecondaryFontMin = 20;
  static const double splitSecondaryFontMax = 24;
  static const double splitBannerHeightMin = 128;
  static const double splitBannerHeightMax = 156;
  static const double splitBannerWidthMin = 300;
  static const double splitBannerWidthMax = 420;

  /// Vertical-split / narrow maneuver column — keep arrow + distance + action
  /// readable without clipping into the Android divider.
  static const double narrowSignSizeMin = 52;
  static const double narrowSignSizeMax = 72;
  static const double narrowPrimaryFontMin = 15;
  static const double narrowPrimaryFontMax = 18;
  static const double narrowDistanceFontMin = 14;
  static const double narrowDistanceFontMax = 17;
  static const double narrowSecondaryFontMin = 13;
  static const double narrowSecondaryFontMax = 15;
  static const double narrowBannerHeightMin = 88;
  static const double narrowBannerHeightMax = 112;
  static const double narrowBannerWidthFloor = 140;

  static const double defaultCompassReserve = 96;

  /// Resolve metrics for the current orientation and the width the banner may
  /// actually occupy (viewport minus menu, logo, gaps and compass reserve).
  ///
  /// When [availableBannerWidth] is below [narrowPaneAvailableWidthThreshold]
  /// (typical vertical-split maneuver column), returns compact narrow-pane
  /// metrics so the wide tablet plate cannot crush "Rechtdoor" / road text.
  factory NavSignageTabletReadabilityMetrics.resolve({
    required bool isLandscape,
    required double availableBannerWidth,
  }) {
    final widthBudget = availableBannerWidth.isFinite && availableBannerWidth > 0
        ? availableBannerWidth
        : (isLandscape ? landscapeBannerWidthMax : portraitBannerWidthMax);

    // Vertical Android split only: a short portrait maneuver column cannot
    // host the 160–180 px tablet plate. Horizontal split / landscape keep
    // the existing tablet readability band (field-acceptable).
    if (!isLandscape && widthBudget < narrowPaneAvailableWidthThreshold) {
      return NavSignageTabletReadabilityMetrics.forNarrowPane(
        availableBannerWidth: widthBudget,
        isLandscape: isLandscape,
      );
    }

    final targetMax = isLandscape
        ? landscapeBannerWidthMax
        : portraitBannerWidthMax;
    final targetMin = isLandscape
        ? landscapeBannerWidthMin
        : portraitBannerWidthMin;

    // Narrower tablets: shrink the width ceiling before the min so we never
    // request minWidth > maxWidth. Floor at a still-glanceable 300.
    final maxWidth = math
        .min(targetMax, widthBudget)
        .clamp(300.0, targetMax)
        .toDouble();
    final minWidth = math.min(targetMin, maxWidth).toDouble();

    final widthT = ((maxWidth - 300) / (targetMax - 300)).clamp(0.0, 1.0);
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

  /// Compact banner metrics for a real narrow pane / maneuver column.
  factory NavSignageTabletReadabilityMetrics.forNarrowPane({
    required double availableBannerWidth,
    required bool isLandscape,
  }) {
    final widthBudget = availableBannerWidth.isFinite && availableBannerWidth > 0
        ? availableBannerWidth
        : narrowPaneAvailableWidthThreshold;
    final maxWidth = math
        .max(narrowBannerWidthFloor, widthBudget)
        .clamp(narrowBannerWidthFloor, narrowPaneAvailableWidthThreshold)
        .toDouble();
    final minWidth = math.min(narrowBannerWidthFloor, maxWidth).toDouble();
    final widthT = ((maxWidth - narrowBannerWidthFloor) /
            (narrowPaneAvailableWidthThreshold - narrowBannerWidthFloor))
        .clamp(0.0, 1.0);
    final signSize =
        (narrowSignSizeMin + (narrowSignSizeMax - narrowSignSizeMin) * widthT)
            .clamp(narrowSignSizeMin, narrowSignSizeMax);
    const inset = 2.0;
    final bannerMinHeight = (narrowBannerHeightMin +
            (narrowBannerHeightMax - narrowBannerHeightMin) * widthT)
        .clamp(narrowBannerHeightMin, narrowBannerHeightMax);
    return NavSignageTabletReadabilityMetrics(
      isLandscape: isLandscape,
      isNarrowPane: true,
      bannerMinHeight: bannerMinHeight,
      bannerMaxWidth: maxWidth,
      bannerMinWidth: minWidth,
      signSize: signSize,
      iconBoxSize: signSize + inset * 2,
      distanceFontSize: (narrowDistanceFontMin +
              (narrowDistanceFontMax - narrowDistanceFontMin) * widthT)
          .clamp(narrowDistanceFontMin, narrowDistanceFontMax),
      primaryFontSize: (narrowPrimaryFontMin +
              (narrowPrimaryFontMax - narrowPrimaryFontMin) * widthT)
          .clamp(narrowPrimaryFontMin, narrowPrimaryFontMax),
      secondaryFontSize: (narrowSecondaryFontMin +
              (narrowSecondaryFontMax - narrowSecondaryFontMin) * widthT)
          .clamp(narrowSecondaryFontMin, narrowSecondaryFontMax),
      horizontalPadding: 8,
      verticalPadding: 6,
      compassReserve: 0,
      signPlateInset: inset,
    );
  }

  /// Metrics for the Tellers + navigatie split guidance card.
  factory NavSignageTabletReadabilityMetrics.forSplitNav({
    required double availableBannerWidth,
  }) {
    final widthBudget = availableBannerWidth.isFinite && availableBannerWidth > 0
        ? availableBannerWidth
        : splitBannerWidthMax;
    final maxWidth = math
        .min(splitBannerWidthMax, widthBudget)
        .clamp(220.0, splitBannerWidthMax)
        .toDouble();
    final minWidth = math.min(splitBannerWidthMin, maxWidth).toDouble();
    final widthT =
        ((maxWidth - 220) / (splitBannerWidthMax - 220)).clamp(0.0, 1.0);
    final signSize =
        (splitSignSizeMin + (splitSignSizeMax - splitSignSizeMin) * widthT)
            .clamp(splitSignSizeMin, splitSignSizeMax);
    const inset = 3.0;
    final bannerMinHeight =
        (splitBannerHeightMin +
                (splitBannerHeightMax - splitBannerHeightMin) * widthT)
            .clamp(splitBannerHeightMin, splitBannerHeightMax);
    return NavSignageTabletReadabilityMetrics(
      isLandscape: false,
      isSplitNav: true,
      bannerMinHeight: bannerMinHeight,
      bannerMaxWidth: maxWidth,
      bannerMinWidth: minWidth,
      signSize: signSize,
      iconBoxSize: signSize + inset * 2,
      distanceFontSize:
          (splitDistanceFontMin +
                  (splitDistanceFontMax - splitDistanceFontMin) * widthT)
              .clamp(splitDistanceFontMin, splitDistanceFontMax),
      primaryFontSize:
          (splitPrimaryFontMin +
                  (splitPrimaryFontMax - splitPrimaryFontMin) * widthT)
              .clamp(splitPrimaryFontMin, splitPrimaryFontMax),
      secondaryFontSize:
          (splitSecondaryFontMin +
                  (splitSecondaryFontMax - splitSecondaryFontMin) * widthT)
              .clamp(splitSecondaryFontMin, splitSecondaryFontMax),
      horizontalPadding: 10,
      verticalPadding: 8,
      compassReserve: 0,
      signPlateInset: inset,
    );
  }

  /// Phone-only transparent maneuver metrics (tablet factories unchanged).
  factory NavSignageTabletReadabilityMetrics.forPhoneParity({
    required bool isLandscape,
    required double availableBannerWidth,
  }) {
    final widthBudget = availableBannerWidth.isFinite && availableBannerWidth > 0
        ? availableBannerWidth
        : (isLandscape ? 320.0 : 360.0);
    final signMin = isLandscape ? 64.0 : 72.0;
    final signMax = isLandscape ? 88.0 : 96.0;
    final heightMin = isLandscape ? 88.0 : 96.0;
    final heightMax = isLandscape ? 120.0 : 120.0;
    const fontMin = 18.0;
    const fontMax = 22.0;
    final widthT = ((widthBudget - 200) / (400 - 200)).clamp(0.0, 1.0);
    final signSize =
        (signMin + (signMax - signMin) * widthT).clamp(signMin, signMax);
    const inset = 3.0;
    final iconBox = signSize + inset * 2;
    final bannerMinHeight =
        (heightMin + (heightMax - heightMin) * widthT).clamp(
          heightMin,
          heightMax,
        );
    final maxWidth = math.min(widthBudget, isLandscape ? 480.0 : 700.0)
        .clamp(220.0, isLandscape ? 480.0 : 700.0)
        .toDouble();
    final minWidth = math.min(isLandscape ? 240.0 : 260.0, maxWidth).toDouble();
    final distanceFont =
        (fontMin + (fontMax - fontMin) * widthT).clamp(fontMin, fontMax);
    return NavSignageTabletReadabilityMetrics(
      isLandscape: isLandscape,
      bannerMinHeight: bannerMinHeight,
      bannerMaxWidth: maxWidth,
      bannerMinWidth: minWidth,
      signSize: signSize,
      iconBoxSize: iconBox,
      distanceFontSize: distanceFont,
      primaryFontSize: distanceFont,
      secondaryFontSize: (fontMin + (fontMax - fontMin) * widthT * 0.92)
          .clamp(fontMin - 1, fontMax - 1),
      horizontalPadding: isLandscape ? 8 : 10,
      verticalPadding: isLandscape ? 5 : 7,
      compassReserve: 0,
      signPlateInset: inset,
      useTransparentChrome: true,
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
    final available =
        viewport.width - sideInsets - menuWidth - logoWidth - gaps - reserve;
    return NavSignageTabletReadabilityMetrics.resolve(
      isLandscape: isLandscape,
      availableBannerWidth: available,
    );
  }
}
