import 'dart:math' as math;

import 'package:flutter/material.dart';

/// NAV-TABLET-BRANDED-HEADER-P1: tablet-only top-row proportions for
/// `[ menu ] [ brand card ] [ maneuver card ]`.
///
/// Phone layouts never resolve these metrics. Width fractions are of the
/// content band after the menu button and inter-card gaps — not the full
/// viewport — so the Mapbox compass reserve (parent [Positioned.right]) stays
/// free. Landscape keeps a compact left cluster (`mainAxisSize.min`) instead
/// of stretching a full-width banner.
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

  /// Compact square menu control edge length (vertically centered vs cards).
  final double menuSize;

  final double gap;

  /// Brand / white-label logo card width.
  final double brandWidth;

  /// Maneuver card width ceiling (dominant information element).
  final double maneuverMaxWidth;

  /// Shared visual height for brand + maneuver cards.
  final double cardHeight;

  final double radius;

  static const double menuSizeDefault = 52;
  static const double gapDefault = 8;
  static const double radiusDefault = 16;

  /// Gold border language shared with the existing logo capsule / recenter.
  static const Color goldBorder = Color(0x66FFD36A);

  /// Navy panel fill aligned with driver cockpit chrome.
  static const Color navyFill = Color(0xEB07142D);

  /// Portrait: brand ≈ 33%, maneuver ≈ 58% of content after menu + gaps.
  static const double portraitBrandFraction = 0.33;
  static const double portraitManeuverFraction = 0.58;

  /// Landscape compact cluster caps (map-first).
  static const double landscapeBrandMin = 168;
  static const double landscapeBrandMax = 228;
  static const double landscapeManeuverMin = 300;
  static const double landscapeManeuverMax = 480;

  /// Resolve width/height tokens for the available header band.
  ///
  /// [cardHeight] should match the resolved tablet maneuver
  /// [NavSignageTabletReadabilityMetrics.bannerMinHeight] so both cards share
  /// one baseline.
  factory NavTabletBrandedHeaderMetrics.resolve({
    required double availableWidth,
    required bool isLandscape,
    required double cardHeight,
    double menuSize = menuSizeDefault,
    double gap = gapDefault,
  }) {
    final safeMenu = menuSize.clamp(40.0, 56.0);
    final safeGap = gap.clamp(6.0, 12.0);
    final usable = math.max(
      200.0,
      availableWidth - safeMenu - (safeGap * 2),
    );

    double brandW;
    double manW;

    if (isLandscape) {
      brandW = (usable * 0.30).clamp(landscapeBrandMin, landscapeBrandMax);
      manW = (usable * 0.55).clamp(landscapeManeuverMin, landscapeManeuverMax);
      final total = brandW + manW;
      if (total > usable) {
        final scale = usable / total;
        brandW *= scale;
        manW *= scale;
      }
    } else {
      brandW = usable * portraitBrandFraction;
      manW = usable * portraitManeuverFraction;
    }

    return NavTabletBrandedHeaderMetrics(
      isLandscape: isLandscape,
      menuSize: safeMenu,
      gap: safeGap,
      brandWidth: brandW,
      maneuverMaxWidth: manW,
      cardHeight: cardHeight.clamp(120.0, 220.0),
      radius: radiusDefault,
    );
  }

  /// True when brand card is smaller than the maneuver card (hierarchy).
  bool get maneuverDominatesBrand => maneuverMaxWidth > brandWidth;

  /// Logo paint box inside the brand card (padding reserved).
  Size logoPaintBox({double horizontalPadding = 14, double verticalPadding = 12}) {
    return Size(
      math.max(24, brandWidth - horizontalPadding * 2),
      math.max(24, cardHeight - verticalPadding * 2),
    );
  }
}

/// Shared chrome for the tablet brand card (and matching menu outline).
BoxDecoration navTabletBrandedHeaderCardDecoration({
  required double radius,
  bool emphasizeGold = true,
}) {
  return BoxDecoration(
    color: NavTabletBrandedHeaderMetrics.navyFill,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: emphasizeGold
          ? NavTabletBrandedHeaderMetrics.goldBorder
          : Colors.white.withOpacity(0.14),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.34),
        blurRadius: 12,
        offset: const Offset(0, 5),
      ),
    ],
  );
}

/// Layout shell used by the driver home tablet follow header and widget tests.
///
/// Children are opaque; this widget only enforces proportions / alignment.
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
          // Maneuver keeps content-adaptive height (soft floor inside the
          // banner). Width is capped so the cluster stays map-first.
          ConstrainedBox(
            key: const ValueKey<String>('nav_tablet_header_maneuver_slot'),
            constraints: BoxConstraints(maxWidth: metrics.maneuverMaxWidth),
            child: maneuver,
          ),
        ],
      ],
    );
  }
}
