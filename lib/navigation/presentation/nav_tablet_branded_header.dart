import 'dart:math' as math;

import 'package:flutter/material.dart';

/// NAV-TABLET-TRANSPARENT-HEADER-P1: tablet-only top-row proportions for
/// `[ menu ] [ brand 50% ] [ maneuver 50% ]` over the live map.
///
/// Phone layouts never resolve these metrics. Width fractions are of the
/// content band after the menu button and inter-card gaps. Landscape keeps a
/// compact left cluster (`mainAxisSize.min`) instead of a full-width banner.
@immutable
class NavTabletBrandedHeaderMetrics {
  const NavTabletBrandedHeaderMetrics({
    required this.isLandscape,
    required this.menuSize,
    required this.gap,
    required this.brandWidth,
    required this.maneuverMaxWidth,
    required this.cardHeight,
    required this.radius,
  });

  final bool isLandscape;

  /// Compact square menu control edge length (vertically centered vs zones).
  final double menuSize;

  final double gap;

  /// Brand / white-label logo zone width (~50% of usable content).
  final double brandWidth;

  /// Maneuver / copy zone width (~50% of usable content).
  final double maneuverMaxWidth;

  /// Shared visual height for brand + maneuver zones.
  final double cardHeight;

  final double radius;

  static const double menuSizeDefault = 52;
  static const double gapDefault = 8;
  static const double radiusDefault = 16;

  /// Gold border language shared with recenter / prior chrome.
  static const Color goldBorder = Color(0x99FFD36A);

  /// Equal spatial importance after the menu button.
  static const double zoneFraction = 0.50;

  /// Landscape compact cluster usable width ceiling (map-first).
  static const double landscapeClusterMax = 640;

  /// Resolve width/height tokens for the available header band.
  ///
  /// FLUXIDI-HOST-FORM-FACTOR-P0: narrow multi-window panes keep tablet
  /// identity but clamp to the real content budget so brand+maneuver never
  /// invent width larger than the pane (overflow).
  factory NavTabletBrandedHeaderMetrics.resolve({
    required double availableWidth,
    required bool isLandscape,
    required double cardHeight,
    double menuSize = menuSizeDefault,
    double gap = gapDefault,
    bool includeMenu = true,
  }) {
    final narrowPane = availableWidth < 480;
    final safeMenu = includeMenu
        ? (narrowPane ? math.min(menuSize, 48.0) : menuSize).clamp(40.0, 56.0)
        : 0.0;
    final safeGap = gap.clamp(6.0, 12.0);
    final menuGaps = includeMenu ? (safeGap * 2) : safeGap;
    final contentBudget =
        math.max(0.0, availableWidth - safeMenu - menuGaps);
    // Prefer the real budget; only apply a soft floor when space allows.
    final usable = contentBudget >= 200
        ? contentBudget
        : math.max(120.0, contentBudget);

    final band = isLandscape ? math.min(usable, landscapeClusterMax) : usable;
    final brandW = band * zoneFraction;
    final manW = band * zoneFraction;
    final maxCard = narrowPane ? 152.0 : 220.0;
    final minCard = narrowPane ? 110.0 : 120.0;

    return NavTabletBrandedHeaderMetrics(
      isLandscape: isLandscape,
      menuSize: safeMenu,
      gap: safeGap,
      brandWidth: brandW,
      maneuverMaxWidth: manW,
      cardHeight: cardHeight.clamp(minCard, maxCard),
      radius: radiusDefault,
    );
  }

  /// True when brand and maneuver zones are equal-width (±1 px).
  bool get zonesAreEqualWidth =>
      (brandWidth - maneuverMaxWidth).abs() <= 1.0;

  /// Logo paint box — aggressive use of the 50% brand region.
  Size logoPaintBox({
    double horizontalPadding = 6,
    double verticalPadding = 4,
  }) {
    return Size(
      math.max(24, brandWidth - horizontalPadding * 2),
      math.max(24, cardHeight - verticalPadding * 2),
    );
  }
}

/// Transparent brand zone: no navy fill, optional gold hairline only when
/// [showBorder] is true (brand itself stays borderless by default).
BoxDecoration navTabletTransparentHeaderDecoration({
  required double radius,
  bool showBorder = false,
  bool showShadow = false,
}) {
  return BoxDecoration(
    color: Colors.transparent,
    borderRadius: BorderRadius.circular(radius),
    border: showBorder
        ? Border.all(
            color: NavTabletBrandedHeaderMetrics.goldBorder,
            width: 1.2,
          )
        : null,
    boxShadow: showShadow
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ]
        : const <BoxShadow>[],
  );
}

/// Gold-outline chrome for the compact tablet menu control only.
BoxDecoration navTabletHeaderMenuDecoration({required double radius}) {
  return BoxDecoration(
    color: const Color(0x9907142D),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: NavTabletBrandedHeaderMetrics.goldBorder,
      width: 1.2,
    ),
  );
}

/// Layout shell used by the driver home tablet follow header and widget tests.
class NavTabletBrandedHeader extends StatelessWidget {
  const NavTabletBrandedHeader({
    super.key,
    required this.metrics,
    required this.menu,
    required this.brand,
    this.maneuver,
  });

  final NavTabletBrandedHeaderMetrics metrics;
  final Widget menu;
  final Widget brand;
  final Widget? maneuver;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey<String>('nav_tablet_branded_header'),
      mainAxisSize: metrics.isLandscape ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        menu,
        SizedBox(width: metrics.gap),
        SizedBox(
          key: const ValueKey<String>('nav_tablet_header_brand_slot'),
          width: metrics.brandWidth,
          height: metrics.cardHeight,
          child: brand,
        ),
        if (maneuver != null) ...[
          SizedBox(width: metrics.gap),
          SizedBox(
            key: const ValueKey<String>('nav_tablet_header_maneuver_slot'),
            width: metrics.maneuverMaxWidth,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: maneuver,
            ),
          ),
        ],
      ],
    );
  }
}
