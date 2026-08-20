// Shared public limousine cover pane. Settings preview and the discovery
// card use the same aspect, BoxFit and focus alignment.

import 'package:flutter/material.dart';

import 'limousine_hero_contract.dart';
import 'limousine_vehicle_media.dart';

const double kLimousinePublicCoverTabletAspect = 16 / 10;
const double kLimousinePublicCoverPhoneAspect = 16 / 9;
const double kLimousinePublicCoverTabletMinHeight = 240;
const double kLimousinePublicCoverTabletMaxHeight = 400;
const double kLimousinePublicCoverPhoneMaxHeight = 280;

const Key kLimousinePublicCoverFrameKey = ValueKey<String>(
  'limousine_public_cover_frame',
);

class LimousinePublicCoverSpec {
  const LimousinePublicCoverSpec({
    required this.aspectRatio,
    required this.minHeight,
    required this.maxHeight,
    required this.fit,
    required this.alignment,
    required this.tablet,
  });

  final double aspectRatio;
  final double minHeight;
  final double maxHeight;
  final BoxFit fit;
  final Alignment alignment;
  final bool tablet;
}

LimousinePublicCoverSpec limousinePublicCoverSpec({
  required Size viewport,
  required bool explicitCover,
  Alignment alignment = Alignment.center,
}) {
  final tablet = viewport.shortestSide >= 600;
  return LimousinePublicCoverSpec(
    aspectRatio: tablet
        ? kLimousinePublicCoverTabletAspect
        : kLimousinePublicCoverPhoneAspect,
    minHeight: tablet
        ? kLimousinePublicCoverTabletMinHeight
        : kLimousineVehiclePhotoMinHeight,
    maxHeight: tablet
        ? (viewport.height * 0.34).clamp(
            kLimousinePublicCoverTabletMinHeight,
            kLimousinePublicCoverTabletMaxHeight,
          )
        : (viewport.height * 0.30).clamp(
            kLimousineVehiclePhotoMinHeight,
            kLimousinePublicCoverPhoneMaxHeight,
          ),
    fit: explicitCover ? BoxFit.cover : BoxFit.contain,
    alignment: alignment,
    tablet: tablet,
  );
}

Size limousinePublicCoverPreviewSize({
  required double maxWidth,
  required LimousinePublicCoverSpec spec,
}) {
  final width = maxWidth <= 0 ? 1.0 : maxWidth;
  var height = width / spec.aspectRatio;
  if (height < spec.minHeight) height = spec.minHeight;
  if (height > spec.maxHeight) height = spec.maxHeight;
  var displayWidth = height * spec.aspectRatio;
  if (displayWidth > width) {
    displayWidth = width;
    height = displayWidth / spec.aspectRatio;
    if (height < spec.minHeight) height = spec.minHeight;
  }
  return Size(displayWidth, height);
}

class LimousinePublicCoverFrame extends StatelessWidget {
  const LimousinePublicCoverFrame({
    super.key,
    required this.imageUrl,
    required this.spec,
    required this.background,
    required this.gold,
    this.maxWidth,
    this.photoKey,
  });

  final String imageUrl;
  final LimousinePublicCoverSpec spec;
  final Color background;
  final Color gold;
  final double? maxWidth;
  final Key? photoKey;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = limousinePublicCoverPreviewSize(
          maxWidth: maxWidth ?? constraints.maxWidth,
          spec: spec,
        );
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            key: kLimousinePublicCoverFrameKey,
            width: size.width,
            height: size.height,
            child: LimousineContainPhoto(
              key: photoKey,
              imageUrl: imageUrl,
              background: background,
              gold: gold,
              minHeight: spec.minHeight,
              aspectRatio: spec.aspectRatio,
              fit: spec.fit,
              alignment: spec.alignment,
              borderRadius: 14,
              placeholderLabel: '',
            ),
          ),
        );
      },
    );
  }
}

LimousinePublicCoverSpec limousinePublicCoverSpecFromHero({
  required Size viewport,
  required LimousineHeroSelection hero,
}) {
  return limousinePublicCoverSpec(
    viewport: viewport,
    explicitCover: hero.explicit && hero.hasPhoto,
    alignment: hero.flutterAlignment,
  );
}
