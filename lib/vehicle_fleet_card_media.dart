// Internal Voertuigen-list photography. The vehicle is the visual hero:
// show the full source photo with contain, never a low cover-cropped banner.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Previous stacked-card banner that center-cropped limousines on SM-X400.
const double kFleetCardOldPortraitBannerHeight = 176;

/// Previous tablet-landscape side-column banner height.
const double kFleetCardOldTabletLandscapeBannerHeight = 168;

/// Previous phone-landscape side-column banner height.
const double kFleetCardOldPhoneLandscapeBannerHeight = 130;

const double kFleetCardMediaAspect = 16 / 9;
const double kFleetCardTabletPortraitMinHeight = 300;
const double kFleetCardTabletPortraitMaxHeight = 420;
const double kFleetCardPhonePortraitMinHeight = 200;
const double kFleetCardPhonePortraitMaxHeight = 280;

const BoxFit kFleetVehicleCardSharpPhotoFit = BoxFit.contain;
const BoxFit kFleetVehicleCardFillPhotoFit = BoxFit.cover;

const Key kFleetVehicleCardMediaFrameKey = ValueKey<String>(
  'fleet_vehicle_card_media_frame',
);
const Key kFleetVehicleCardContainImageKey = ValueKey<String>(
  'fleet_vehicle_card_contain_image',
);
const Key kFleetVehicleCardFillImageKey = ValueKey<String>(
  'fleet_vehicle_card_fill_image',
);
const Key kFleetVehicleCardPlaceholderKey = ValueKey<String>(
  'fleet_vehicle_card_placeholder',
);
const Key kFleetVehicleCardExtraPhotosKey = ValueKey<String>(
  'fleet_vehicle_card_extra_photos',
);

enum FleetCardMediaLayout { stacked, sideColumn }

int fleetVehicleExtraPhotoCount({
  required String primaryPhotoRef,
  required Iterable<String> galleryPhotoRefs,
}) {
  final seen = <String>{};
  void add(String raw) {
    final value = raw.trim();
    if (value.isNotEmpty) seen.add(value);
  }

  add(primaryPhotoRef);
  for (final ref in galleryPhotoRefs) {
    add(ref);
  }
  if (seen.isEmpty) return 0;
  return seen.length - 1;
}

/// Responsive media height from the available card/column width.
///
/// Replaces the old universal 176/168/130 cover banners. Landscape and
/// split-screen are capped by the viewport so the card can grow without
/// overflowing the visible window.
double fleetCardMediaHeight({
  required double availableWidth,
  required Size viewport,
  FleetCardMediaLayout layout = FleetCardMediaLayout.stacked,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : viewport.width;
  final shortest = math.min(viewport.width, viewport.height);
  final tablet = shortest >= 600;
  final landscape = viewport.width > viewport.height;
  final fromAspect = width / kFleetCardMediaAspect;

  late final double minHeight;
  late final double maxHeight;
  if (layout == FleetCardMediaLayout.sideColumn) {
    minHeight = tablet ? 188 : 148;
    maxHeight = tablet ? 280 : 200;
  } else if (tablet) {
    minHeight = kFleetCardTabletPortraitMinHeight;
    maxHeight = kFleetCardTabletPortraitMaxHeight;
  } else {
    minHeight = kFleetCardPhonePortraitMinHeight;
    maxHeight = kFleetCardPhonePortraitMaxHeight;
  }

  var height = fromAspect.clamp(minHeight, maxHeight);
  final capFraction = landscape ? 0.46 : 0.38;
  final viewportCap = viewport.height * capFraction;
  if (viewportCap >= minHeight) {
    height = height.clamp(minHeight, math.min(maxHeight, viewportCap));
  } else {
    final relaxedMin = minHeight * 0.72;
    height = fromAspect.clamp(
      relaxedMin,
      math.max(relaxedMin, viewportCap),
    );
  }
  return height;
}

bool fleetCardMediaUsesContainStrategy({
  required BoxFit sharpFit,
  required double height,
  required Size viewport,
}) {
  final tabletPortrait =
      viewport.shortestSide >= 600 && viewport.height >= viewport.width;
  final minExpected = tabletPortrait
      ? kFleetCardTabletPortraitMinHeight
      : kFleetCardPhonePortraitMinHeight;
  return sharpFit == BoxFit.contain && height >= minExpected;
}

class FleetVehicleCardMedia extends StatelessWidget {
  const FleetVehicleCardMedia({
    super.key,
    required this.photoRef,
    required this.placeholderText,
    required this.background,
    required this.gold,
    this.fallbackPhotoRef = '',
    this.extraPhotoCount = 0,
    this.extraPhotosLabel = '',
    this.onOpen,
    this.layout = FleetCardMediaLayout.stacked,
    this.imageOverride,
  });

  final String photoRef;
  final String fallbackPhotoRef;
  final String placeholderText;
  final Color background;
  final Color gold;
  final int extraPhotoCount;
  final String extraPhotosLabel;
  final VoidCallback? onOpen;
  final FleetCardMediaLayout layout;
  final ImageProvider? imageOverride;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : viewport.width;
        final height = fleetCardMediaHeight(
          availableWidth: width,
          viewport: viewport,
          layout: layout,
        );
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (width * dpr).round().clamp(240, 1400);
        final image =
            imageOverride ??
            _providerFor(photoRef) ??
            _providerFor(fallbackPhotoRef);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FleetVehicleCardPhotoFrame(
              height: height,
              width: width,
              background: background,
              gold: gold,
              placeholderText: placeholderText,
              image: image,
              cacheWidth: cacheWidth,
              onOpen: onOpen,
            ),
            if (extraPhotoCount > 0) ...[
              const SizedBox(height: 6),
              Text(
                key: kFleetVehicleCardExtraPhotosKey,
                extraPhotosLabel.trim().isEmpty
                    ? '+$extraPhotoCount extra foto\'s'
                    : extraPhotosLabel,
                style: TextStyle(
                  color: gold.withOpacity(0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class FleetVehicleCardPhotoFrame extends StatelessWidget {
  const FleetVehicleCardPhotoFrame({
    super.key,
    required this.height,
    required this.background,
    required this.gold,
    required this.placeholderText,
    this.width,
    this.image,
    this.cacheWidth,
    this.onOpen,
    this.borderRadius = 10,
  });

  final double height;
  final double? width;
  final Color background;
  final Color gold;
  final String placeholderText;
  final ImageProvider? image;
  final int? cacheWidth;
  final VoidCallback? onOpen;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        key: kFleetVehicleCardMediaFrameKey,
        width: width ?? double.infinity,
        height: height,
        child: Material(
          color: background,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(borderRadius),
          child: InkWell(
            onTap: onOpen,
            child: image == null
                ? _placeholder()
                : Builder(
                    builder: (context) {
                      final decoded = cacheWidth == null
                          ? image!
                          : ResizeImage(
                              image!,
                              width: cacheWidth,
                              policy: ResizeImagePolicy.fit,
                            );
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ColorFiltered(
                            colorFilter: ColorFilter.mode(
                              Colors.black.withOpacity(0.46),
                              BlendMode.darken,
                            ),
                            child: Image(
                              key: kFleetVehicleCardFillImageKey,
                              image: decoded,
                              fit: kFleetVehicleCardFillPhotoFit,
                              alignment: Alignment.center,
                              filterQuality: FilterQuality.low,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                          Image(
                            key: kFleetVehicleCardContainImageKey,
                            image: decoded,
                            fit: kFleetVehicleCardSharpPhotoFit,
                            alignment: Alignment.center,
                            filterQuality: FilterQuality.medium,
                            gaplessPlayback: true,
                            errorBuilder: (_, __, ___) => _placeholder(),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return KeyedSubtree(
      key: kFleetVehicleCardPlaceholderKey,
      child: ColoredBox(
        color: background,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.directions_car_filled_outlined,
                color: gold,
                size: 28,
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  placeholderText,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: gold.withOpacity(0.86),
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

ImageProvider? _providerFor(String raw) {
  final ref = raw.trim();
  if (ref.isEmpty) return null;
  final lower = ref.toLowerCase();
  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    return NetworkImage(ref);
  }
  if (lower.startsWith('assets/')) {
    return AssetImage(ref);
  }
  return FileImage(File(ref));
}
