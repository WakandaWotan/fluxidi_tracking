import 'package:flutter/material.dart';

import 'package:fluxidi_tracking/nearby/tablet_partner_branding_layout.dart';

/// Upper bound for a partner-card cover.
///
/// Wide covers use their own aspect ratio and stay shorter than this.
/// Square and portrait covers stop here and letterbox with [BoxFit.contain].
const double kNearbyPartnerHeroMediaMinHeight = 96;
const double kNearbyPartnerHeroMediaMaxHeight = 460;
const double kNearbyPartnerHeroMediaLegacyHeight = 90;

/// Maximum cover height for a card laid out at [layoutWidth].
///
/// The frame itself follows the image. This cap only applies when the
/// natural height would be taller than the card should grow.
double nearbyPartnerHeroMediaHeight(double layoutWidth) {
  final contentW = layoutWidth.clamp(280.0, 1100.0);
  final cap = contentW * 0.72;
  return cap.clamp(
    kNearbyPartnerHeroMediaMinHeight,
    kNearbyPartnerHeroMediaMaxHeight,
  );
}

/// Full-width company cover for Taxi Nearby partner cards.
///
/// The height follows the source aspect ratio. [height] is only a maximum:
/// taller images stay inside it with [BoxFit.contain] and [backgroundColor]
/// in the unused space. Nothing is cropped or stretched.
///
/// The separate company logo is not drawn here. Cards place it under the cover.
class NearbyPartnerHeroMedia extends StatefulWidget {
  const NearbyPartnerHeroMedia({
    super.key,
    required this.height,
    required this.backgroundColor,
    this.heroUrl = '',
    this.heroImage,
    this.fallback,
    this.borderRadius = 11,
    this.clipBorderRadius,
    this.aspectRatio,
  });

  /// Maximum frame height. The painted height may be smaller.
  final double height;
  final Color backgroundColor;
  final String heroUrl;

  /// Optional override for tests (avoids network). Production uses [heroUrl].
  final ImageProvider? heroImage;
  final Widget? fallback;
  final double borderRadius;

  /// Optional full [BorderRadius] override for the outer cover clip.
  final BorderRadius? clipBorderRadius;

  /// Width divided by height. Tests pass this so the frame is stable before
  /// the image codec finishes. Production reads the decoded image instead.
  final double? aspectRatio;

  bool get hasHero => heroImage != null || heroUrl.trim().isNotEmpty;

  @override
  State<NearbyPartnerHeroMedia> createState() => _NearbyPartnerHeroMediaState();
}

class _NearbyPartnerHeroMediaState extends State<NearbyPartnerHeroMedia> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _info;
  bool _failed = false;

  ImageProvider? get _provider {
    if (widget.heroImage != null) return widget.heroImage;
    final url = widget.heroUrl.trim();
    if (url.isEmpty) return null;
    return NetworkImage(url);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(NearbyPartnerHeroMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.heroImage != widget.heroImage ||
        oldWidget.heroUrl != widget.heroUrl) {
      _subscribe();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    final listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  void _subscribe() {
    _detach();
    final provider = _provider;
    if (provider == null) {
      _info = null;
      _failed = false;
      return;
    }
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _stream = stream;
    final listener = ImageStreamListener(
      (info, _) {
        if (!mounted) return;
        setState(() {
          _info = info;
          _failed = false;
        });
      },
      onError: (_, __) {
        if (!mounted) return;
        setState(() {
          _info = null;
          _failed = true;
        });
      },
    );
    _listener = listener;
    stream.addListener(listener);
  }

  double _frameHeight(double width) {
    final maxHeight = widget.height;
    final image = _info?.image;
    final decoded = (image != null && image.width > 0 && image.height > 0)
        ? image.width / image.height
        : null;
    final ratio = (widget.aspectRatio != null && widget.aspectRatio! > 0)
        ? widget.aspectRatio
        : decoded;
    if (ratio == null || ratio <= 0) {
      return (width / 2.35).clamp(kNearbyPartnerHeroMediaMinHeight, maxHeight);
    }
    final natural = width / ratio;
    if (natural > maxHeight) return maxHeight;
    return natural;
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider == null || _failed) {
      final fallback = widget.fallback;
      if (fallback != null) return fallback;
      return const SizedBox.shrink();
    }

    final clip = widget.clipBorderRadius ??
        BorderRadius.circular(widget.borderRadius);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 360.0;
        final frameHeight = _frameHeight(width);
        return ClipRRect(
          key: const ValueKey<String>('nearby_partner_cover_frame'),
          borderRadius: clip,
          child: ColoredBox(
            color: widget.backgroundColor,
            child: SizedBox(
              key: const ValueKey<String>('nearby_partner_cover_box'),
              width: double.infinity,
              height: frameHeight,
              child: Image(
                key: const ValueKey<String>('nearby_partner_cover_image'),
                image: provider,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                width: double.infinity,
                height: frameHeight,
                errorBuilder: (_, __, ___) =>
                    widget.fallback ??
                    SizedBox(height: frameHeight, width: double.infinity),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Company mark placed under the cover, beside the name and status.
///
/// Light themes put transparent yellow marks on a dark plate so the mark
/// stays readable. Dark themes keep a dark plate as well, because those
/// marks are drawn for a dark ground.
class NearbyPartnerLogoMark extends StatelessWidget {
  const NearbyPartnerLogoMark({
    super.key,
    required this.logoUrl,
    required this.maxWidth,
    required this.maxHeight,
    required this.lightTheme,
    this.logoImage,
    this.fallbackIconColor,
  });

  final String logoUrl;
  final double maxWidth;
  final double maxHeight;
  final bool lightTheme;
  final ImageProvider? logoImage;
  final Color? fallbackIconColor;

  static const Key markKey = Key('nearby_partner_logo_mark');

  @override
  Widget build(BuildContext context) {
    return PartnerBrandingLogoPlate(
      key: markKey,
      logoUrl: logoUrl,
      logoImage: logoImage,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      backgroundColor: const Color(0xFF161616),
      borderColor: lightTheme
          ? const Color(0xFF2A2A2A)
          : const Color(0xFFFFD36A).withOpacity(0.45),
      fallbackIconColor: fallbackIconColor ?? const Color(0xFFFFD36A),
      borderRadius: 10,
    );
  }
}
