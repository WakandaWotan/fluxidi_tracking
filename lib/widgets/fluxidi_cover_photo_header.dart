import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/fluxidi_decode_sized_asset_image.dart';

/// Shared company-home photo header. Always paints with a uniform cover
/// scale and clips; never [BoxFit.fill] and never independent X/Y scaling.
const BoxFit kFluxidiCoverPhotoFit = BoxFit.cover;

const Key kFluxidiCoverPhotoHeaderKey = Key('fluxidi_cover_photo_header');
const Key kFluxidiCoverPhotoHeaderImageKey = Key(
  'fluxidi_cover_photo_header_image',
);

const String kBusinessHomeHeaderExecutiveGoldPortrait =
    'assets/fluxidi/zakelijke_tablet_header_foto.webp';
const String kBusinessHomeHeaderExecutiveGoldLandscape =
    'assets/fluxidi/zakelijke_tablet_header_foto_landscape.webp';
const String kBusinessHomeHeaderCorporateBlue =
    'assets/Corporate BLEU Compagny/company_header_fleet_corporate_blue.webp';
const String kBusinessHomeHeaderCleanProfessional =
    'assets/Clean & Professional Compagny/company_header_fleet_clean_professional.webp';
const String kBusinessHomeHeaderEmeraldIvory =
    'assets/Emerald_Ivory_Company/company_header_emerald_ivory.webp';
const String kBusinessHomeHeaderNeonRush =
    'assets/🥇 Fluxidi Neon Rush/company_header_fleet_neon_rush.webp';

/// Measured intrinsic pixel sizes of every company photo header.
const Map<String, Size> kBusinessHomeHeaderSourceSizes = <String, Size>{
  kBusinessHomeHeaderExecutiveGoldPortrait: Size(1086, 1448),
  kBusinessHomeHeaderExecutiveGoldLandscape: Size(1536, 1024),
  kBusinessHomeHeaderCorporateBlue: Size(1672, 941),
  kBusinessHomeHeaderCleanProfessional: Size(1536, 1024),
  kBusinessHomeHeaderEmeraldIvory: Size(1536, 1024),
  kBusinessHomeHeaderNeonRush: Size(1536, 1024),
};

const double kBusinessHomeHeaderContentInset = 16;
const double kBusinessHomeHeaderTitleHeight = 20;
const double kBusinessHomeHeaderBackHeight = 48;
const double kBusinessHomeHeaderListInnerBottom = 8;
const double kBusinessHomeHeaderKpiRowCompact = 52;
const double kBusinessHomeHeaderKpiRowComfort = 72;
const double kBusinessHomeHeaderKpiStackGap = 8;
const double kBusinessHomeHeaderTopBarHeight = 36;
const double kBusinessHomeHeaderGreetingBlockHeight = 36;
const double kBusinessHomeHeaderThemeButtonHeight = 40;
const double kBusinessHomeHeaderOverlayStackGap = 8;

String businessHomeHeaderPhotoAsset({
  required BusinessThemeVariant variant,
  required bool landscape,
}) {
  switch (variant) {
    case BusinessThemeVariant.executiveGold:
      return landscape
          ? kBusinessHomeHeaderExecutiveGoldLandscape
          : kBusinessHomeHeaderExecutiveGoldPortrait;
    case BusinessThemeVariant.corporateBlue:
      return kBusinessHomeHeaderCorporateBlue;
    case BusinessThemeVariant.cleanProfessional:
      return kBusinessHomeHeaderCleanProfessional;
    case BusinessThemeVariant.emeraldIvory:
      return kBusinessHomeHeaderEmeraldIvory;
    case BusinessThemeVariant.fluxidiNeonRush:
      return kBusinessHomeHeaderNeonRush;
    case BusinessThemeVariant.brandSignatureGold:
      return kBusinessHomeHeaderExecutiveGoldLandscape;
  }
}

Size businessHomeHeaderSourceSize(String assetName) {
  final size = kBusinessHomeHeaderSourceSizes[assetName];
  if (size != null) return size;
  return const Size(1536, 1024);
}

Alignment businessHomeHeaderFocalAlignment(String assetName) {
  if (assetName == kBusinessHomeHeaderExecutiveGoldPortrait) {
    return Alignment.center;
  }
  if (assetName == kBusinessHomeHeaderCorporateBlue) {
    return const Alignment(0, 0.08);
  }
  return const Alignment(0, 0.12);
}

double businessHomeHeaderOverlayMinHeight(EdgeInsets padding) {
  final overlayStack =
      kBusinessHomeHeaderTopBarHeight +
      kBusinessHomeHeaderOverlayStackGap +
      math.max(
        kBusinessHomeHeaderGreetingBlockHeight,
        kBusinessHomeHeaderThemeButtonHeight,
      );
  return padding.vertical + overlayStack;
}

double businessHomeKpiBlockHeight({
  required bool stacked,
  required bool compact,
}) {
  final row = compact
      ? kBusinessHomeHeaderKpiRowCompact
      : kBusinessHomeHeaderKpiRowComfort;
  if (stacked) return row * 2 + kBusinessHomeHeaderKpiStackGap;
  return row;
}

double businessHomePhotoHeaderAvailableHeight({
  required double bodyHeight,
  required double listTop,
  required double sectionGap,
  required double kpiHeight,
  required double titleGap,
  required double gridTopGap,
  required double actionsHeight,
  required double backGap,
  required double listBottom,
  double titleHeight = kBusinessHomeHeaderTitleHeight,
  double backHeight = kBusinessHomeHeaderBackHeight,
  double listInnerBottom = kBusinessHomeHeaderListInnerBottom,
}) {
  final reserved =
      listTop +
      sectionGap +
      kpiHeight +
      titleGap +
      titleHeight +
      gridTopGap +
      actionsHeight +
      listInnerBottom +
      backGap +
      backHeight +
      listBottom;
  final leftover = bodyHeight - reserved;
  return leftover.isFinite && leftover > 0 ? leftover : 0;
}

/// One uniform cover scale. Horizontal and vertical factors are identical.
double fluxidiUniformCoverScale(Size source, Size zone) {
  if (source.width <= 0 || source.height <= 0) return 1;
  if (zone.width <= 0 || zone.height <= 0) return 1;
  return math.max(zone.width / source.width, zone.height / source.height);
}

int fluxidiCoverDecodeCacheWidth({
  required Size sourceSize,
  required Size zone,
  required double devicePixelRatio,
  int maxEdgePixels = kFluxidiMaxDecodeEdgePixels,
}) {
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final scale = fluxidiUniformCoverScale(sourceSize, zone) * dpr;
  final width = (sourceSize.width * scale).round();
  final maxEdge = maxEdgePixels < 1 ? 1 : maxEdgePixels;
  if (width < 1) return 1;
  return width > maxEdge ? maxEdge : width;
}

class FluxidiCoverPhotoHeaderLayout {
  const FluxidiCoverPhotoHeaderLayout({
    required this.sourceSize,
    required this.zone,
    required this.uniformScale,
  });

  final Size sourceSize;
  final Size zone;
  final double uniformScale;

  double get scaleX => uniformScale;
  double get scaleY => uniformScale;
  Size get paintedSize =>
      Size(sourceSize.width * uniformScale, sourceSize.height * uniformScale);
  BoxFit get fit => kFluxidiCoverPhotoFit;
}

FluxidiCoverPhotoHeaderLayout layoutFluxidiCoverPhotoHeader({
  required Size sourceSize,
  required double availableWidth,
  required double maxHeight,
  required double minHeight,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : 1.0;
  final aspectHeight = width * (sourceSize.height / sourceSize.width);
  final floor = minHeight.isFinite && minHeight > 0 ? minHeight : 0.0;
  double height = aspectHeight;
  if (maxHeight.isFinite && maxHeight > 0 && height > maxHeight) {
    height = maxHeight;
  }
  if (height < floor) {
    height = floor;
  }
  final zone = Size(width, height);
  return FluxidiCoverPhotoHeaderLayout(
    sourceSize: sourceSize,
    zone: zone,
    uniformScale: fluxidiUniformCoverScale(sourceSize, zone),
  );
}

class FluxidiCoverPhotoHeader extends StatelessWidget {
  const FluxidiCoverPhotoHeader({
    super.key,
    required this.assetName,
    required this.sourceSize,
    required this.maxHeight,
    this.minHeight = 0,
    this.focalAlignment = Alignment.center,
    this.borderRadius = 18,
    this.border,
    this.overlayGradient,
    this.overlay,
    this.errorBuilder,
  });

  final String assetName;
  final Size sourceSize;
  final double maxHeight;
  final double minHeight;
  final Alignment focalAlignment;
  final double borderRadius;
  final BoxBorder? border;
  final Gradient? overlayGradient;
  final Widget? overlay;
  final ImageErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final layout = layoutFluxidiCoverPhotoHeader(
          sourceSize: sourceSize,
          availableWidth: width,
          maxHeight: maxHeight,
          minHeight: minHeight,
        );
        final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
        final cacheWidth = fluxidiCoverDecodeCacheWidth(
          sourceSize: sourceSize,
          zone: layout.zone,
          devicePixelRatio: dpr,
        );
        return SizedBox(
          key: kFluxidiCoverPhotoHeaderKey,
          width: layout.zone.width,
          height: layout.zone.height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(borderRadius),
              border: border,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    assetName,
                    key: kFluxidiCoverPhotoHeaderImageKey,
                    fit: kFluxidiCoverPhotoFit,
                    alignment: focalAlignment,
                    filterQuality: FilterQuality.medium,
                    cacheWidth: cacheWidth,
                    errorBuilder:
                        errorBuilder ??
                        (_, __, ___) => const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xFF101010), Color(0xFF07080C)],
                            ),
                          ),
                        ),
                  ),
                  if (overlayGradient != null)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: overlayGradient),
                      ),
                    ),
                  if (overlay != null) Positioned.fill(child: overlay!),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
