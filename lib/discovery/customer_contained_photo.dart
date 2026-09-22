import 'package:flutter/material.dart';

const int kCustomerDetailPhotoTargetPx = 1600;

bool isCustomerTechnicalDiscoveryCopy(String? raw) {
  final text = (raw ?? '').trim().toLowerCase();
  if (text.isEmpty) return false;
  const markers = <String>[
    'live place discovery',
    'real place discovery',
    'echte plaatsvermelding',
    'découverte de lieu réel',
    'descubrimiento de lugar real',
    'uitgelichte inspiratie',
    'featured inspiration',
    'inspiration mise en avant',
    'inspiración destacada',
    'stay22-partners',
    'stay22 partners',
    'partenaires stay22',
    'socios stay22',
    'geen prijsinventaris',
    'no price inventory',
  ];
  return markers.any(text.contains);
}

String preferredCustomerDetailPhotoUrl({
  String? hero,
  String? image,
  String? thumbnail,
}) {
  for (final candidate in <String?>[hero, image, thumbnail]) {
    final text = (candidate ?? '').trim();
    if (text.isNotEmpty) return customerPreferredDetailPhotoUrl(text);
  }
  return '';
}

/// Prefers a larger existing variant. Does not invent a new image or add crop.
String customerPreferredDetailPhotoUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return trimmed;

  var next = uri;
  next = _upgradeQueryPhotoSize(next);
  next = _upgradeGoogleUserContentSize(next);
  return next.toString();
}

Uri _upgradeQueryPhotoSize(Uri uri) {
  if (uri.queryParameters.isEmpty) return uri;
  final params = Map<String, String>.from(uri.queryParameters);
  var changed = false;
  const sizeKeys = <String>{
    'maxwidth',
    'maxWidth',
    'maxwidthpx',
    'maxWidthPx',
    'w',
    'width',
  };
  const heightKeys = <String>{
    'maxheight',
    'maxHeight',
    'maxheightpx',
    'maxHeightPx',
    'h',
    'height',
  };
  for (final key in sizeKeys) {
    final current = int.tryParse((params[key] ?? '').trim());
    if (current == null) continue;
    if (current < kCustomerDetailPhotoTargetPx) {
      params[key] = '$kCustomerDetailPhotoTargetPx';
      changed = true;
    }
  }
  for (final key in heightKeys) {
    if (!params.containsKey(key)) continue;
    params.remove(key);
    changed = true;
  }
  if (params.remove('crop') != null) changed = true;
  if (!changed) return uri;
  return uri.replace(queryParameters: params.isEmpty ? null : params);
}

Uri _upgradeGoogleUserContentSize(Uri uri) {
  final host = uri.host.toLowerCase();
  if (!host.contains('googleusercontent.com')) return uri;
  final path = uri.path;
  final match = RegExp(
    r'=(?:s|w)\d+(?:-h\d+)?(?:-[a-z0-9-]+)*$',
    caseSensitive: false,
  ).firstMatch(path);
  if (match == null) return uri;
  final upgraded = '${path.substring(0, match.start)}=s$kCustomerDetailPhotoTargetPx';
  return uri.replace(path: upgraded);
}

class CustomerContainedPhoto extends StatefulWidget {
  const CustomerContainedPhoto({
    required this.backgroundColor,
    required this.borderColor,
    required this.placeholder,
    this.imageUrl = '',
    this.assetFallback = '',
    this.borderRadius = 18,
    this.maxHeight,
    super.key,
  });

  final String imageUrl;
  final String assetFallback;
  final Color backgroundColor;
  final Color borderColor;
  final Widget placeholder;
  final double borderRadius;
  final double? maxHeight;

  @override
  State<CustomerContainedPhoto> createState() => _CustomerContainedPhotoState();
}

class _CustomerContainedPhotoState extends State<CustomerContainedPhoto> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  Size? _imageSize;
  Object? _error;
  ImageProvider? _provider;

  String get _resolvedUrl => customerPreferredDetailPhotoUrl(widget.imageUrl);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _listenToImage();
  }

  @override
  void didUpdateWidget(covariant CustomerContainedPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.assetFallback != widget.assetFallback) {
      _imageSize = null;
      _error = null;
      _listenToImage();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  ImageProvider? get _imageProvider {
    final url = _resolvedUrl;
    if (url.isNotEmpty) return NetworkImage(url);
    final asset = widget.assetFallback.trim();
    if (asset.isNotEmpty) return AssetImage(asset);
    return null;
  }

  void _listenToImage() {
    _detach();
    final provider = _imageProvider;
    _provider = provider;
    if (provider == null) return;
    final stream = provider.resolve(createLocalImageConfiguration(context));
    _listener = ImageStreamListener(
      (image, _) {
        if (!mounted) return;
        final size = Size(
          image.image.width.toDouble(),
          image.image.height.toDouble(),
        );
        if (size.width <= 0 || size.height <= 0) return;
        setState(() {
          _imageSize = size;
          _error = null;
        });
      },
      onError: (error, _) {
        if (!mounted) return;
        setState(() {
          _error = error;
          _imageSize = null;
        });
      },
    );
    stream.addListener(_listener!);
    _stream = stream;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screen.width;
        final maxHeight =
            widget.maxHeight ?? (screen.height * 0.85).clamp(240.0, 900.0);
        final hasImage = _provider != null && _error == null;
        var height = 168.0;
        if (hasImage && _imageSize != null && _imageSize!.height > 0) {
          final aspect = _imageSize!.width / _imageSize!.height;
          height = maxWidth / aspect;
          if (height > maxHeight) height = maxHeight;
        } else if (hasImage) {
          height = (maxWidth * 9 / 16).clamp(160.0, maxHeight);
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            border: Border.all(color: widget.borderColor),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: ColoredBox(
              color: widget.backgroundColor,
              child: SizedBox(
                width: maxWidth,
                height: height,
                child: hasImage
                    ? Image(
                        image: _provider!,
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => widget.placeholder,
                      )
                    : widget.placeholder,
              ),
            ),
          ),
        );
      },
    );
  }
}
