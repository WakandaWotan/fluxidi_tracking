// Internal Voertuigen-list photography. The vehicle is the visual hero:
// show the full source photo with contain, never a low cover-cropped banner.
//
// Portrait here means the phone/tablet screen orientation, not a portrait
// crop of the vehicle photo. In that orientation every stacked fleet card
// uses the full available card width and derives height from the source
// aspect ratio so the whole car stays visible.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/vehicle_gallery_contract.dart';

/// Previous stacked-card banner that center-cropped limousines on SM-X400.
const double kFleetCardOldPortraitBannerHeight = 176;

/// Previous tablet-landscape side-column banner height.
const double kFleetCardOldTabletLandscapeBannerHeight = 168;

/// Previous phone-landscape side-column banner height.
const double kFleetCardOldPhoneLandscapeBannerHeight = 130;

const double kFleetCardMediaAspect = 16 / 9;

/// Historical clamped tablet-portrait banner. Portrait stacked cards no
/// longer use these; height follows the source photo instead.
const double kFleetCardTabletPortraitMinHeight = 280;
const double kFleetCardTabletPortraitMaxHeight = 360;
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
const Key kFleetVehicleCardPortraitFullWidthKey = ValueKey<String>(
  'fleet_vehicle_card_portrait_full_width',
);

enum FleetCardMediaLayout { stacked, sideColumn }

int fleetVehicleExtraPhotoCount({
  required String primaryPhotoRef,
  required Iterable<String> galleryPhotoRefs,
}) {
  final seen = <String>{};
  void add(String raw) {
    final identity = publicMediaObjectIdentity(raw);
    if (identity.isNotEmpty) seen.add(identity);
  }

  add(primaryPhotoRef);
  for (final ref in galleryPhotoRefs) {
    add(ref);
  }
  if (seen.isEmpty) return 0;
  return seen.length - 1;
}

bool fleetCardMediaIsPortraitScreen(Size viewport) {
  return viewport.height >= viewport.width;
}

bool fleetCardMediaIsTabletPortrait(Size viewport) {
  return viewport.shortestSide >= 600 &&
      fleetCardMediaIsPortraitScreen(viewport);
}

bool fleetCardMediaUsesFullWidthPortraitLayout({
  required FleetCardMediaLayout layout,
  required Size viewport,
}) {
  return layout == FleetCardMediaLayout.stacked &&
      fleetCardMediaIsPortraitScreen(viewport);
}

/// Height for a full-width portrait photo so the source aspect is kept.
///
/// [aspectRatio] is width / height of the source image. Different vehicles
/// may therefore get different heights; keeping the whole car visible is
/// more important than matching every card to the same banner height.
double fleetCardPortraitPhotoHeight({
  required double availableWidth,
  double aspectRatio = kFleetCardMediaAspect,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : 1.0;
  final aspect = aspectRatio > 0 ? aspectRatio : kFleetCardMediaAspect;
  return width / aspect;
}

/// Compact landscape / side-column height. Portrait stacked cards use
/// [fleetCardPortraitPhotoHeight] instead of this 16:9 clamp.
double fleetCardMediaHeight({
  required double availableWidth,
  required Size viewport,
  FleetCardMediaLayout layout = FleetCardMediaLayout.stacked,
  double? sourceAspectRatio,
}) {
  if (fleetCardMediaUsesFullWidthPortraitLayout(
    layout: layout,
    viewport: viewport,
  )) {
    return fleetCardPortraitPhotoHeight(
      availableWidth: availableWidth,
      aspectRatio: sourceAspectRatio ?? kFleetCardMediaAspect,
    );
  }

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
  final capFraction = landscape ? 0.46 : (tablet ? 0.30 : 0.38);
  final viewportCap = viewport.height * capFraction;
  if (viewportCap >= minHeight) {
    height = height.clamp(minHeight, math.min(maxHeight, viewportCap));
  } else {
    final relaxedMin = minHeight * 0.72;
    height = fromAspect.clamp(relaxedMin, math.max(relaxedMin, viewportCap));
  }
  return height;
}

Size fleetCardMediaBox({
  required double availableWidth,
  required Size viewport,
  FleetCardMediaLayout layout = FleetCardMediaLayout.stacked,
  double? sourceAspectRatio,
}) {
  final width = availableWidth.isFinite && availableWidth > 0
      ? availableWidth
      : viewport.width;
  final height = fleetCardMediaHeight(
    availableWidth: width,
    viewport: viewport,
    layout: layout,
    sourceAspectRatio: sourceAspectRatio,
  );
  return Size(width, height);
}

bool fleetCardMediaUsesContainStrategy({
  required BoxFit sharpFit,
  required double height,
  required Size viewport,
  FleetCardMediaLayout layout = FleetCardMediaLayout.stacked,
}) {
  if (sharpFit != BoxFit.contain || height <= 0) return false;
  if (fleetCardMediaUsesFullWidthPortraitLayout(
    layout: layout,
    viewport: viewport,
  )) {
    return true;
  }
  final minExpected = fleetCardMediaIsTabletPortrait(viewport)
      ? kFleetCardTabletPortraitMinHeight
      : kFleetCardPhonePortraitMinHeight;
  return height >= minExpected * 0.72;
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
    this.sourceAspectRatio,
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

  /// Optional known source width/height. Production leaves this null so
  /// the decoded photo supplies the ratio. Tests may pass it to pin layout
  /// without waiting on codec timing.
  final double? sourceAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = MediaQuery.sizeOf(context);
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : viewport.width;
        final image =
            imageOverride ??
            _providerFor(photoRef) ??
            _providerFor(fallbackPhotoRef);
        final extra = extraPhotoCount > 0
            ? <Widget>[
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
              ]
            : const <Widget>[];

        if (fleetCardMediaUsesFullWidthPortraitLayout(
          layout: layout,
          viewport: viewport,
        )) {
          return Column(
            key: kFleetVehicleCardPortraitFullWidthKey,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FleetPortraitAspectPhoto(
                availableWidth: width,
                background: background,
                gold: gold,
                placeholderText: placeholderText,
                image: image,
                onOpen: onOpen,
                sourceAspectRatio: sourceAspectRatio,
              ),
              ...extra,
            ],
          );
        }

        final box = fleetCardMediaBox(
          availableWidth: width,
          viewport: viewport,
          layout: layout,
        );
        final dpr = MediaQuery.devicePixelRatioOf(context);
        final cacheWidth = (box.width * dpr).round().clamp(240, 1400);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FleetVehicleCardPhotoFrame(
              height: box.height,
              width: box.width,
              background: background,
              gold: gold,
              placeholderText: placeholderText,
              image: image,
              cacheWidth: cacheWidth,
              onOpen: onOpen,
              letterboxFill: true,
            ),
            ...extra,
          ],
        );
      },
    );
  }
}

/// Full-bleed portrait photo: `width: double.infinity`, height from the
/// decoded source aspect so [BoxFit.contain] can paint the whole car.
class _FleetPortraitAspectPhoto extends StatefulWidget {
  const _FleetPortraitAspectPhoto({
    required this.availableWidth,
    required this.background,
    required this.gold,
    required this.placeholderText,
    required this.image,
    required this.onOpen,
    required this.sourceAspectRatio,
  });

  final double availableWidth;
  final Color background;
  final Color gold;
  final String placeholderText;
  final ImageProvider? image;
  final VoidCallback? onOpen;
  final double? sourceAspectRatio;

  @override
  State<_FleetPortraitAspectPhoto> createState() =>
      _FleetPortraitAspectPhotoState();
}

class _FleetPortraitAspectPhotoState extends State<_FleetPortraitAspectPhoto> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageProvider? _listeningImage;
  double? _sourceAspectRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_FleetPortraitAspectPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _sourceAspectRatio = null;
      _listeningImage = null;
      _resolve();
    }
  }

  void _resolve() {
    final image = widget.image;
    if (image == null) {
      _stop();
      _listeningImage = null;
      return;
    }
    if (identical(_listeningImage, image) && _listener != null) {
      return;
    }
    _stop();
    _listeningImage = image;
    final stream = image.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener((info, _) {
      final w = info.image.width.toDouble();
      final h = info.image.height.toDouble();
      if (!mounted || w <= 0 || h <= 0) return;
      final next = w / h;
      if (_sourceAspectRatio == next) return;
      setState(() => _sourceAspectRatio = next);
    }, onError: (_, __) {});
    _stream = stream..addListener(_listener!);
  }

  void _stop() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FleetVehicleCardPhotoFrame(
      width: double.infinity,
      height: fleetCardPortraitPhotoHeight(
        availableWidth: widget.availableWidth,
        aspectRatio:
            widget.sourceAspectRatio ??
            _sourceAspectRatio ??
            kFleetCardMediaAspect,
      ),
      background: widget.background,
      gold: widget.gold,
      placeholderText: widget.placeholderText,
      image: widget.image,
      onOpen: widget.onOpen,
      letterboxFill: false,
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
    this.letterboxFill = true,
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
  final bool letterboxFill;

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
                          if (letterboxFill)
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
              Icon(Icons.directions_car_filled_outlined, color: gold, size: 28),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  placeholderText,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: gold.withOpacity(0.86), fontSize: 12),
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
