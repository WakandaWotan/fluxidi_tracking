import 'package:flutter/material.dart';

import 'nav_sign_resolver.dart';

/// NAV-SIGNAGE-VISUAL-RELEASE-GATE: renders one Fluxidi navigation sign.
///
/// The only widget allowed to turn a [NavSignManeuver] into pixels. It never
/// composes a path itself — [navSignAssetPath] does that — and it never draws
/// a maneuver at runtime.
class NavManeuverSign extends StatelessWidget {
  const NavManeuverSign({
    super.key,
    required this.maneuver,
    required this.languageCode,
    required this.size,
    this.semanticLabel,
  });

  final NavSignManeuver maneuver;

  /// Active customer language. Unsupported values fall back to Dutch inside
  /// [navSignAssetPath], so exactly one language variant is ever loaded.
  final String? languageCode;

  /// Edge length of the square sign plate in logical pixels.
  final double size;

  final String? semanticLabel;

  /// The resolved bundle path this widget will load.
  String get assetPath =>
      navSignAssetPath(languageCode: languageCode, maneuver: maneuver);

  /// Language directory actually used after fallback.
  String get resolvedLanguageCode => resolveNavSignLanguageCode(languageCode);

  @override
  Widget build(BuildContext context) {
    final path = assetPath;
    // Source plates are 1024x1024. Decoding them at full size would cost ~4 MB
    // of RGBA per sign for a glyph drawn at well under 100 logical pixels, so
    // the decode is capped at the physical size actually painted.
    final devicePixelRatio =
        MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0;
    final decodeEdge = navSignDecodeEdge(
      size: size,
      devicePixelRatio: devicePixelRatio,
    );
    return Image.asset(
      path,
      // Rebuilding with a different sign or language must not leave the
      // previous plate on screen for a frame. A path-derived key forces a new
      // element, and gaplessPlayback stays off so no stale frame is retained.
      key: ValueKey<String>('nav_sign:$path'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      cacheWidth: decodeEdge,
      cacheHeight: decodeEdge,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) {
        // Safety net only: the asset-integrity tests prove all 136 plates
        // resolve. If the bundle is ever broken mid-drive the banner must keep
        // rendering rather than throw at the driver.
        assert(() {
          debugPrint(
            '[NAV_SIGN_ASSET_MISSING] path=$path maneuver=${maneuver.id}',
          );
          return true;
        }());
        return SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.straight_rounded,
            size: size * 0.72,
            color: const Color(0xFF1F2937),
          ),
        );
      },
    );
  }
}

/// Physical edge length a sign should be decoded at.
///
/// Clamped to the 1024 px source so upscaling never allocates more than the
/// original, and floored at 1 so a zero-sized layout cannot produce an invalid
/// decode request.
int navSignDecodeEdge({
  required double size,
  required double devicePixelRatio,
}) {
  final ratio = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final edge = (size.isFinite ? size : 0) * ratio;
  if (!edge.isFinite || edge <= 1) return 1;
  return edge.ceil().clamp(1, kNavSignSourceEdgePixels);
}

/// Native edge length of every plate in `assets/fluxidi_navigation_signs_v3`.
const int kNavSignSourceEdgePixels = 1024;
