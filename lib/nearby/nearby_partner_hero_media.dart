import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/nearby/tablet_partner_branding_layout.dart';

/// Taxi Nearby company-card vehicle / hero banner sizing.
///
/// Old field behavior used a fixed 90px strip with [BoxFit.cover], which
/// aggressively cropped landscape company vehicle photos. The frame is now
/// taller and aspect-aware so [BoxFit.contain] can show the full vehicle.
const double kNearbyPartnerHeroMediaMinHeight = 128;
const double kNearbyPartnerHeroMediaMaxHeight = 176;
const double kNearbyPartnerHeroMediaLegacyHeight = 90;

/// Responsive media-frame height for a company card in [layoutWidth].
///
/// Uses a wide frame (~2.35:1) so typical landscape taxi photos fit under
/// [BoxFit.contain] without dominating the screen.
///
/// Phone-only contract: do not change these bounds when adding tablet splits.
double nearbyPartnerHeroMediaHeight(double layoutWidth) {
  final contentW = (layoutWidth - 36).clamp(280.0, 720.0);
  final ideal = contentW / 2.35;
  return ideal.clamp(
    kNearbyPartnerHeroMediaMinHeight,
    kNearbyPartnerHeroMediaMaxHeight,
  );
}

/// Shared hero / vehicle image strip for Taxi Nearby company cards.
///
/// Preserves source aspect ratio via [BoxFit.contain], centers the image, and
/// fills unused space with [backgroundColor] (theme card/surface — not black).
///
/// TABLET-PARTNER-BRANDING-LAYOUT-1 / TABLET-PARTNER-MEDIA-POLISH-1: when
/// [tabletSplit] is true the media zone is a single clipped photo | logo row.
/// Phone keeps the historic stacked strip with a small circular logo overlay.
class NearbyPartnerHeroMedia extends StatelessWidget {
  const NearbyPartnerHeroMedia({
    super.key,
    required this.height,
    required this.backgroundColor,
    this.heroUrl = '',
    this.logoUrl = '',
    this.heroImage,
    this.logoImage,
    this.fallback,
    this.borderRadius = 11,
    this.clipBorderRadius,
    this.tabletSplit = false,
    this.tabletSplitMetrics,
    this.logoPanelColor,
    this.logoBorderColor,
    this.logoFallbackIconColor,
  });

  final double height;
  final Color backgroundColor;
  final String heroUrl;
  final String logoUrl;
  /// Optional override for tests (avoids network). Production uses [heroUrl].
  final ImageProvider? heroImage;
  final ImageProvider? logoImage;
  final Widget? fallback;
  final double borderRadius;

  /// Optional full [BorderRadius] override for the outer tablet media clip.
  final BorderRadius? clipBorderRadius;

  /// TABLET-PARTNER-BRANDING-LAYOUT-1: enable horizontal photo | logo split.
  final bool tabletSplit;
  final TabletPartnerCardMediaSplit? tabletSplitMetrics;
  final Color? logoPanelColor;
  final Color? logoBorderColor;
  final Color? logoFallbackIconColor;

  bool get hasHero => heroImage != null || heroUrl.trim().isNotEmpty;
  bool get hasLogo => logoImage != null || logoUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final safeFallback =
        fallback ??
        ColoredBox(
          color: backgroundColor,
          child: SizedBox(height: height, width: double.infinity),
        );

    final ImageProvider? resolvedHero =
        heroImage ??
        (heroUrl.trim().isNotEmpty ? NetworkImage(heroUrl.trim()) : null);
    final ImageProvider? resolvedLogo =
        logoImage ??
        (logoUrl.trim().isNotEmpty ? NetworkImage(logoUrl.trim()) : null);

    if (tabletSplit) {
      return _buildTabletSplit(
        resolvedHero: resolvedHero,
        resolvedLogo: resolvedLogo,
        safeFallback: safeFallback,
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: ColoredBox(
        color: backgroundColor,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: resolvedHero != null
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image(
                      image: resolvedHero,
                      fit: BoxFit.contain,
                      alignment: Alignment.center,
                      width: double.infinity,
                      height: height,
                      errorBuilder: (_, __, ___) => safeFallback,
                    ),
                    if (resolvedLogo != null)
                      Positioned(
                        left: 10,
                        bottom: 8,
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black.withOpacity(0.82),
                          foregroundImage: resolvedLogo,
                        ),
                      ),
                  ],
                )
              : resolvedLogo != null
              ? Center(
                  child: Image(
                    image: resolvedLogo,
                    width: 56,
                    height: 56,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => safeFallback,
                  ),
                )
              : safeFallback,
        ),
      ),
    );
  }

  Widget _buildTabletSplit({
    required ImageProvider? resolvedHero,
    required ImageProvider? resolvedLogo,
    required Widget safeFallback,
  }) {
    final metrics =
        tabletSplitMetrics ??
        TabletPartnerCardMediaSplit.resolve(
          layoutWidth: 800,
          isLandscape: false,
        );
    final rowHeight = metrics.height;
    final clip =
        clipBorderRadius ?? BorderRadius.circular(borderRadius);
    final logoSurface = logoPanelColor ?? backgroundColor;
    return ClipRRect(
      key: const ValueKey<String>('nearby_partner_tablet_media_split'),
      borderRadius: clip,
      child: SizedBox(
        height: rowHeight,
        width: double.infinity,
        child: Row(
          key: const ValueKey<String>('nearby_partner_tablet_media_row'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: metrics.photoFlex,
              child: KeyedSubtree(
                key: const ValueKey<String>('nearby_partner_tablet_photo'),
                child: resolvedHero != null
                    ? PartnerTabletPhotoFill(
                        image: resolvedHero,
                        errorFallback: safeFallback,
                      )
                    : safeFallback,
              ),
            ),
            Expanded(
              flex: metrics.logoFlex,
              child: ColoredBox(
                key: const ValueKey<String>('nearby_partner_tablet_logo_cell'),
                color: logoSurface,
                child: Padding(
                  padding: metrics.logoPadding,
                  child: Center(
                    child: PartnerBrandingLogoPlate(
                      logoUrl: logoUrl,
                      logoImage: resolvedLogo,
                      maxWidth: rowHeight * 1.55,
                      maxHeight: rowHeight - metrics.logoPadding.vertical,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.transparent,
                      borderColor: Colors.transparent,
                      fallbackIconColor: logoFallbackIconColor,
                      borderRadius: 0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
