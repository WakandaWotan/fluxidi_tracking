import 'package:flutter/material.dart';

/// Upper bound for a single decode edge so unbounded layout cannot request
/// pathological allocations. Source assets in this app stay well below this.
const int kFluxidiMaxDecodeEdgePixels = 4096;

/// Physical decode size for an image painted into [logicalWidth] ×
/// [logicalHeight] at [devicePixelRatio].
///
/// Both edges are returned so Flutter can fit the source within the box while
/// preserving aspect ratio (`Image.cacheWidth` / `cacheHeight` semantics).
/// Infinite or non-positive logical edges fall back to `null` on that axis so
/// callers can omit the corresponding cache argument.
({int? width, int? height}) fluxidiDecodePixelSize({
  required double logicalWidth,
  required double logicalHeight,
  required double devicePixelRatio,
  int maxEdgePixels = kFluxidiMaxDecodeEdgePixels,
}) {
  final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final maxEdge = maxEdgePixels < 1 ? 1 : maxEdgePixels;

  int? encode(double logical) {
    if (!logical.isFinite || logical <= 0) return null;
    final physical = logical * ratio;
    if (!physical.isFinite || physical <= 1) return 1;
    return physical.ceil().clamp(1, maxEdge);
  }

  return (width: encode(logicalWidth), height: encode(logicalHeight));
}

/// Resolves a finite paint size from layout constraints, falling back to the
/// viewport when a constraint axis is unbounded.
Size fluxidiResolvePaintSize({
  required BoxConstraints constraints,
  required Size fallback,
}) {
  final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
      ? constraints.maxWidth
      : fallback.width;
  final height = constraints.maxHeight.isFinite && constraints.maxHeight > 0
      ? constraints.maxHeight
      : fallback.height;
  return Size(
    width.isFinite && width > 0 ? width : fallback.width,
    height.isFinite && height > 0 ? height : fallback.height,
  );
}

/// [Image.asset] that decodes at the physical size of its layout box.
///
/// Drop-in for full-bleed / card-sized raster heroes where the source PNG is
/// much larger than the painted area. Does not change [fit], alignment, or
/// layout — only the decode target.
class FluxidiDecodeSizedAssetImage extends StatelessWidget {
  const FluxidiDecodeSizedAssetImage(
    this.assetName, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.filterQuality = FilterQuality.medium,
    this.gaplessPlayback = false,
    this.width,
    this.height,
    this.errorBuilder,
    this.semanticLabel,
  });

  final String assetName;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final FilterQuality filterQuality;
  final bool gaplessPlayback;
  final double? width;
  final double? height;
  final ImageErrorWidgetBuilder? errorBuilder;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.maybeOf(context);
        final fallback = media?.size ?? const Size(1, 1);
        final paintSize = fluxidiResolvePaintSize(
          constraints: constraints,
          fallback: fallback,
        );
        final decode = fluxidiDecodePixelSize(
          logicalWidth: paintSize.width,
          logicalHeight: paintSize.height,
          devicePixelRatio: media?.devicePixelRatio ?? 1.0,
        );
        return Image.asset(
          assetName,
          width: width ??
              (constraints.hasBoundedWidth ? constraints.maxWidth : null),
          height: height ??
              (constraints.hasBoundedHeight ? constraints.maxHeight : null),
          fit: fit,
          alignment: alignment,
          filterQuality: filterQuality,
          gaplessPlayback: gaplessPlayback,
          cacheWidth: decode.width,
          cacheHeight: decode.height,
          errorBuilder: errorBuilder,
          semanticLabel: semanticLabel,
        );
      },
    );
  }
}
