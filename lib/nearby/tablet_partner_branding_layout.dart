import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/branding/company_logo_ref.dart';

/// TABLET-PARTNER-BRANDING-LAYOUT-1: tablet-only partner media / logo layouts.
///
/// Gate on logical [Size.shortestSide] only — never device model names.
const double kTabletPartnerBrandingShortestSide = 600;

bool isTabletPartnerBrandingLayout(Size size) =>
    size.shortestSide >= kTabletPartnerBrandingShortestSide;

/// Horizontal split for Taxi Nearby active partner cards.
class TabletPartnerCardMediaSplit {
  const TabletPartnerCardMediaSplit({
    required this.photoFlex,
    required this.logoFlex,
    required this.height,
    required this.logoPadding,
  });

  final int photoFlex;
  final int logoFlex;
  final double height;
  final EdgeInsets logoPadding;

  /// Photo ~52%, logo ~48% of the media row.
  static const int defaultPhotoFlex = 52;
  static const int defaultLogoFlex = 48;

  static TabletPartnerCardMediaSplit resolve({
    required double layoutWidth,
    required bool isLandscape,
  }) {
    final contentW = layoutWidth.clamp(320.0, 1200.0);
    // Shared row height: taller than the phone strip so both panes read clearly.
    final ideal = isLandscape
        ? (contentW * 0.18).clamp(148.0, 200.0)
        : (contentW * 0.22).clamp(156.0, 210.0);
    return TabletPartnerCardMediaSplit(
      photoFlex: defaultPhotoFlex,
      logoFlex: defaultLogoFlex,
      height: ideal,
      logoPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 18 : 16,
        vertical: isLandscape ? 14 : 16,
      ),
    );
  }
}

/// Horizontal split for the public partner profile hero.
class TabletPartnerProfileHeroSplit {
  const TabletPartnerProfileHeroSplit({
    required this.photoFlex,
    required this.brandingFlex,
    required this.height,
    required this.logoMaxWidth,
    required this.logoMaxHeight,
    required this.logoPadding,
  });

  final int photoFlex;
  final int brandingFlex;
  final double height;
  final double logoMaxWidth;
  final double logoMaxHeight;
  final EdgeInsets logoPadding;

  static const int defaultPhotoFlex = 55;
  static const int defaultBrandingFlex = 45;

  static TabletPartnerProfileHeroSplit resolve({
    required double layoutWidth,
    required bool isLandscape,
  }) {
    final contentW = layoutWidth.clamp(320.0, 1400.0);
    final height = isLandscape
        ? (contentW * 0.22).clamp(200.0, 280.0)
        : (contentW * 0.28).clamp(220.0, 300.0);
    final brandingW = contentW * defaultBrandingFlex / 100;
    return TabletPartnerProfileHeroSplit(
      photoFlex: defaultPhotoFlex,
      brandingFlex: defaultBrandingFlex,
      height: height,
      logoMaxWidth: (brandingW * 0.78).clamp(140.0, 260.0),
      logoMaxHeight: (height * 0.42).clamp(72.0, 120.0),
      logoPadding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
    );
  }
}

/// Rectangular logo metrics for "Mijn favoriete taxi's" on tablet.
class TabletFavoritePartnerLogoMetrics {
  const TabletFavoritePartnerLogoMetrics({
    required this.width,
    required this.height,
    required this.padding,
  });

  final double width;
  final double height;
  final EdgeInsets padding;

  static TabletFavoritePartnerLogoMetrics resolve({
    required double layoutWidth,
  }) {
    final w = (layoutWidth * 0.18).clamp(110.0, 150.0);
    final h = (w * 0.56).clamp(60.0, 84.0);
    return TabletFavoritePartnerLogoMetrics(
      width: w,
      height: h,
      padding: const EdgeInsets.all(8),
    );
  }
}

/// Canonical partner / Branding & support logo plate for tablet surfaces.
///
/// Uses [classifyCompanyLogoRef] so only asset/network/file refs render as
/// images. Missing or invalid refs use the safe taxi fallback — never a
/// cropped circle that clips wide marks such as “F Fluxidi”.
class PartnerBrandingLogoPlate extends StatelessWidget {
  const PartnerBrandingLogoPlate({
    super.key,
    required this.logoUrl,
    required this.maxWidth,
    required this.maxHeight,
    required this.padding,
    required this.backgroundColor,
    required this.borderColor,
    this.logoImage,
    this.fallbackIconColor,
    this.borderRadius = 12,
  });

  final String logoUrl;
  final double maxWidth;
  final double maxHeight;
  final EdgeInsets padding;
  final Color backgroundColor;
  final Color borderColor;
  final ImageProvider? logoImage;
  final Color? fallbackIconColor;
  final double borderRadius;

  static const Key plateKey = Key('partner_branding_logo_plate');
  static const Key imageKey = Key('partner_branding_logo_image');
  static const Key fallbackKey = Key('partner_branding_logo_fallback');

  bool get _hasRenderableRef {
    if (logoImage != null) return true;
    final kind = classifyCompanyLogoRef(logoUrl);
    return kind == CompanyLogoRefKind.network ||
        kind == CompanyLogoRefKind.asset ||
        kind == CompanyLogoRefKind.file;
  }

  ImageProvider? get _resolvedImage {
    if (logoImage != null) return logoImage;
    final kind = classifyCompanyLogoRef(logoUrl);
    final ref = logoUrl.trim();
    switch (kind) {
      case CompanyLogoRefKind.network:
        return NetworkImage(ref);
      case CompanyLogoRefKind.asset:
        return AssetImage(ref);
      case CompanyLogoRefKind.file:
        // Partner public media never ships file paths; keep safe fallback.
        return null;
      case CompanyLogoRefKind.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _hasRenderableRef ? _resolvedImage : null;
    return Container(
      key: plateKey,
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        minWidth: maxWidth * 0.55,
        minHeight: maxHeight * 0.55,
      ),
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: borderColor),
      ),
      alignment: Alignment.center,
      child: image == null
          ? Icon(
              key: fallbackKey,
              Icons.local_taxi_outlined,
              size: (maxHeight * 0.42).clamp(22.0, 40.0),
              color: fallbackIconColor ?? Colors.white70,
            )
          : Image(
              key: imageKey,
              image: image,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => Icon(
                key: fallbackKey,
                Icons.local_taxi_outlined,
                size: (maxHeight * 0.42).clamp(22.0, 40.0),
                color: fallbackIconColor ?? Colors.white70,
              ),
            ),
    );
  }
}
