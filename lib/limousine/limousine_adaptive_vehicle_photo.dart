// Adaptive public limousine photography. Classification uses intrinsic source
// pixels only — never the laid-out widget size after BoxFit.

import 'dart:ui';

import 'package:flutter/material.dart';

/// Inclusive near-square band around 1:1, from source width / height.
///
/// * portrait: aspect < 0.85
/// * square / near-square: 0.85 <= aspect <= 1.15
/// * landscape: aspect > 1.15
const double kLimousinePhotoNearSquareMinAspect = 0.85;
const double kLimousinePhotoNearSquareMaxAspect = 1.15;

const double kLimousineAdaptiveHeroPhoneMin = 200;
const double kLimousineAdaptiveHeroPhoneMax = 420;
const double kLimousineAdaptiveHeroTabletMin = 240;
const double kLimousineAdaptiveHeroTabletMax = 520;
const double kLimousineAdaptiveHeroPortraitPhoneMax = 460;
const double kLimousineAdaptiveHeroPortraitTabletMax = 560;

const double kLimousinePortraitBackdropSigma = 7;
const double kLimousinePortraitBackdropOverlay = 0.16;

const Key kLimousineAdaptivePhotoKey = ValueKey<String>(
  'limousine_adaptive_vehicle_photo',
);
const Key kLimousineAdaptivePhotoSharpKey = ValueKey<String>(
  'limousine_adaptive_vehicle_photo_sharp',
);
const Key kLimousineAdaptivePhotoBlurKey = ValueKey<String>(
  'limousine_adaptive_vehicle_photo_blur',
);
const Key kLimousineDetailFullscreenViewerKey = ValueKey<String>(
  'limousine_vehicle_detail_fullscreen_viewer',
);
const Key kLimousineDetailFullscreenCloseKey = ValueKey<String>(
  'limousine_vehicle_detail_fullscreen_close',
);
const Key kLimousineDetailFullscreenPageViewKey = ValueKey<String>(
  'limousine_vehicle_detail_fullscreen_pages',
);

Key limousineAdaptivePhotoOrientationKey(LimousinePhotoOrientation orientation) {
  return ValueKey<String>(
    'limousine_adaptive_vehicle_photo_${orientation.name}',
  );
}

Key limousineDetailGalleryThumbKey(int index) =>
    ValueKey<String>('limousine_vehicle_detail_gallery_thumb_$index');

enum LimousinePhotoOrientation { landscape, square, portrait }

/// Classify a photograph from its intrinsic pixel size.
LimousinePhotoOrientation limousinePhotoOrientationFromSize(Size size) {
  if (!size.isFinite || size.width <= 0 || size.height <= 0) {
    return LimousinePhotoOrientation.landscape;
  }
  final aspect = size.width / size.height;
  if (aspect < kLimousinePhotoNearSquareMinAspect) {
    return LimousinePhotoOrientation.portrait;
  }
  if (aspect <= kLimousinePhotoNearSquareMaxAspect) {
    return LimousinePhotoOrientation.square;
  }
  return LimousinePhotoOrientation.landscape;
}

bool limousineAdaptivePhotoUsesBlurredBackdrop(
  LimousinePhotoOrientation orientation,
) {
  return orientation == LimousinePhotoOrientation.portrait;
}

double limousineAdaptiveHeroHeight({
  required Size viewport,
  required Size sourceSize,
}) {
  final tablet = viewport.shortestSide >= 600;
  final minHeight = tablet
      ? kLimousineAdaptiveHeroTabletMin
      : kLimousineAdaptiveHeroPhoneMin;
  final landscapeMax = tablet
      ? kLimousineAdaptiveHeroTabletMax
      : kLimousineAdaptiveHeroPhoneMax;
  final portraitMax = tablet
      ? kLimousineAdaptiveHeroPortraitTabletMax
      : kLimousineAdaptiveHeroPortraitPhoneMax;
  final width = viewport.width <= 0 ? 1.0 : viewport.width;
  final orientation = limousinePhotoOrientationFromSize(sourceSize);
  final aspect = (sourceSize.width > 0 && sourceSize.height > 0)
      ? sourceSize.width / sourceSize.height
      : 16 / 9;
  switch (orientation) {
    case LimousinePhotoOrientation.landscape:
      return (width / aspect).clamp(minHeight, landscapeMax);
    case LimousinePhotoOrientation.square:
      return width.clamp(minHeight, landscapeMax);
    case LimousinePhotoOrientation.portrait:
      return (width / aspect).clamp(minHeight, portraitMax);
  }
}

class LimousineAdaptiveVehiclePhoto extends StatefulWidget {
  const LimousineAdaptiveVehiclePhoto({
    super.key,
    required this.imageUrl,
    required this.background,
    this.gold = const Color(0xFFC9A227),
    this.placeholderLabel = '',
    this.sourceSize,
    this.image,
    this.borderRadius = 0,
    this.fillParent = false,
    this.onTap,
    this.semanticLabel,
  });

  final String imageUrl;
  final Color background;
  final Color gold;
  final String placeholderLabel;
  final Size? sourceSize;
  final ImageProvider? image;
  final double borderRadius;
  final bool fillParent;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<LimousineAdaptiveVehiclePhoto> createState() =>
      _LimousineAdaptiveVehiclePhotoState();
}

class _LimousineAdaptiveVehiclePhotoState
    extends State<LimousineAdaptiveVehiclePhoto> {
  Size? _resolved;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  ImageProvider? get _provider {
    if (widget.image != null) return widget.image;
    if (widget.imageUrl.startsWith('https://')) {
      return NetworkImage(widget.imageUrl);
    }
    return null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listen();
  }

  @override
  void didUpdateWidget(covariant LimousineAdaptiveVehiclePhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.image != widget.image ||
        oldWidget.sourceSize != widget.sourceSize) {
      _resolved = null;
      _listen();
    }
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  void _listen() {
    _unlisten();
    if (widget.sourceSize != null) return;
    final provider = _provider;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        final next = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
        if (_resolved == next) return;
        setState(() => _resolved = next);
      },
      onError: (Object _, StackTrace? __) {},
    );
    stream.addListener(_listener!);
    _stream = stream;
  }

  void _unlisten() {
    final listener = _listener;
    if (_stream != null && listener != null) {
      _stream!.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  Size get _source {
    return widget.sourceSize ??
        _resolved ??
        const Size(16, 9);
  }

  @override
  Widget build(BuildContext context) {
    final source = _source;
    final orientation = limousinePhotoOrientationFromSize(source);
    final height = limousineAdaptiveHeroHeight(
      viewport: MediaQuery.sizeOf(context),
      sourceSize: source,
    );
    final usesBlur = limousineAdaptivePhotoUsesBlurredBackdrop(orientation);
    final photo = widget.imageUrl.isEmpty && widget.image == null
        ? _placeholder()
        : _photo(orientation: orientation, usesBlur: usesBlur);
    final framed = ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: ColoredBox(
        color: Colors.black,
        child: SizedBox(
          key: kLimousineAdaptivePhotoKey,
          width: double.infinity,
          height: widget.fillParent ? double.infinity : height,
          child: KeyedSubtree(
            key: limousineAdaptivePhotoOrientationKey(orientation),
            child: photo,
          ),
        ),
      ),
    );
    final labeled = Semantics(
      image: true,
      button: widget.onTap != null,
      label: widget.semanticLabel ?? widget.placeholderLabel,
      child: framed,
    );
    if (widget.onTap == null) return labeled;
    return GestureDetector(onTap: widget.onTap, child: labeled);
  }

  Widget _photo({
    required LimousinePhotoOrientation orientation,
    required bool usesBlur,
  }) {
    final sharp = _image(
      key: kLimousineAdaptivePhotoSharpKey,
      fit: BoxFit.contain,
    );
    if (!usesBlur) {
      return ColoredBox(color: Colors.black, child: sharp);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          key: kLimousineAdaptivePhotoBlurKey,
          imageFilter: ImageFilter.blur(
            sigmaX: kLimousinePortraitBackdropSigma,
            sigmaY: kLimousinePortraitBackdropSigma,
          ),
          child: _image(fit: BoxFit.cover),
        ),
        ColoredBox(color: Colors.black.withOpacity(kLimousinePortraitBackdropOverlay)),
        sharp,
      ],
    );
  }

  Widget _image({Key? key, required BoxFit fit}) {
    if (widget.image != null) {
      return Image(
        key: key,
        image: widget.image!,
        fit: fit,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return Image.network(
      widget.imageUrl,
      key: key,
      fit: fit,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: CircularProgressIndicator(color: widget.gold, strokeWidth: 2),
        );
      },
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _placeholder() {
    final letter = widget.placeholderLabel.trim().isEmpty
        ? ''
        : widget.placeholderLabel.trim().substring(0, 1).toUpperCase();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [widget.background, widget.gold.withOpacity(0.16)],
        ),
      ),
      child: Center(
        child: letter.isEmpty
            ? Icon(
                Icons.directions_car_filled_outlined,
                color: widget.gold,
                size: 42,
              )
            : Text(
                letter,
                style: TextStyle(
                  color: widget.gold,
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

Future<void> openLimousineVehiclePhotoViewer({
  required BuildContext context,
  required List<String> photos,
  required int initialIndex,
  required String semanticLabel,
  List<ImageProvider>? images,
}) {
  if (photos.isEmpty && (images == null || images.isEmpty)) {
    return Future<void>.value();
  }
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      barrierColor: Colors.black,
      pageBuilder: (context, _, __) {
        return LimousineVehiclePhotoViewerPage(
          photos: photos,
          initialIndex: initialIndex,
          semanticLabel: semanticLabel,
          images: images,
        );
      },
    ),
  );
}

class LimousineVehiclePhotoViewerPage extends StatefulWidget {
  const LimousineVehiclePhotoViewerPage({
    super.key,
    required this.photos,
    required this.initialIndex,
    required this.semanticLabel,
    this.images,
  });

  final List<String> photos;
  final int initialIndex;
  final String semanticLabel;
  final List<ImageProvider>? images;

  @override
  State<LimousineVehiclePhotoViewerPage> createState() =>
      _LimousineVehiclePhotoViewerPageState();
}

class _LimousineVehiclePhotoViewerPageState
    extends State<LimousineVehiclePhotoViewerPage> {
  late final PageController _pages;
  late int _index;
  final Map<int, TransformationController> _transforms =
      <int, TransformationController>{};

  int get _count {
    if (widget.images != null && widget.images!.isNotEmpty) {
      return widget.images!.length;
    }
    return widget.photos.length;
  }

  TransformationController _transformFor(int index) {
    return _transforms.putIfAbsent(index, TransformationController.new);
  }

  bool _zoomed(int index) =>
      _transformFor(index).value.getMaxScaleOnAxis() > 1.01;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, _count == 0 ? 0 : _count - 1);
    _pages = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pages.dispose();
    for (final controller in _transforms.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: kLimousineDetailFullscreenViewerKey,
      backgroundColor: Colors.black,
      body: Semantics(
        label: widget.semanticLabel,
        child: Stack(
          children: [
            PageView.builder(
              key: kLimousineDetailFullscreenPageViewKey,
              controller: _pages,
              itemCount: _count,
              onPageChanged: (index) {
                _transformFor(index).value = Matrix4.identity();
                setState(() => _index = index);
              },
              itemBuilder: (_, index) {
                return InteractiveViewer(
                  transformationController: _transformFor(index),
                  minScale: 1,
                  maxScale: 4,
                  panEnabled: _zoomed(index),
                  onInteractionEnd: (_) => setState(() {}),
                  child: Center(
                    child: widget.images != null && index < widget.images!.length
                        ? Image(
                            image: widget.images![index],
                            fit: BoxFit.contain,
                          )
                        : Image.network(
                            widget.photos[index],
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                  ),
                );
              },
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  key: kLimousineDetailFullscreenCloseKey,
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
