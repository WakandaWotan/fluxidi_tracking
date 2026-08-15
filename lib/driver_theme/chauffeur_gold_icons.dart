import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_assets.dart';

const List<String> kChauffeurGoldIconKeys = <String>[
  'home',
  'planning',
  'completed',
  'next_ride',
  'street_ride',
  'fare_calculator',
  'rides',
  'history',
  'receipts',
  'documents',
  'navigation',
  'more',
];

Key chauffeurGoldIconKey(String assetKey) =>
    Key('chauffeur_gold_icon_$assetKey');

/// Bounded Gold WebP icon. Used only while chauffeur Brand Signature Gold is active.
class ChauffeurGoldIcon extends StatelessWidget {
  const ChauffeurGoldIcon({
    super.key,
    required this.assetKey,
    required this.size,
  });

  final String assetKey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
    final decode = (size * dpr).round().clamp(48, 256);
    return Image.asset(
      brandSignatureGoldAssetPath(assetKey),
      key: chauffeurGoldIconKey(assetKey),
      width: size,
      height: size,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      cacheWidth: decode,
      cacheHeight: decode,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}
