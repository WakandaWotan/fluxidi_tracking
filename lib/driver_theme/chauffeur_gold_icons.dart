import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/widgets/brand_signature_gold_action_card.dart';

const List<String> kChauffeurGoldQuickActionAssetKeys = <String>[
  'street_ride',
  'fare_calculator',
  'rides',
  'history',
  'receipts',
  'documents',
];

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

/// Bounded Gold WebP icon. Uses the company contained-illustration fit.
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
    return SizedBox(
      width: size,
      height: size,
      child: BrandSignatureGoldContainedIllustration(
        imageKey: chauffeurGoldIconKey(assetKey),
        assetKey: assetKey,
        width: size,
        height: size,
        cacheSize: decode,
      ),
    );
  }
}
