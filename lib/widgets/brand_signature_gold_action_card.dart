import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_assets.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';

class BrandSignatureGoldActionCard extends StatelessWidget {
  const BrandSignatureGoldActionCard({
    super.key,
    required this.actionKey,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.isFuture = false,
    this.futureBadge,
    this.statusBadge,
  });

  final String actionKey;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isFuture;
  final String? futureBadge;
  final String? statusBadge;

  @override
  Widget build(BuildContext context) {
    final assetKey = kBrandSignatureGoldActionAssetKeys[actionKey] ?? actionKey;
    final icon = Image.asset(
      brandSignatureGoldAssetPath(assetKey),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
    );
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: brandSignaturePaletteNotifier,
      child: icon,
      builder: (context, colors, iconChild) {
        final palette = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        final active = onTap != null && !isFuture;
        return Material(
          key: Key('brand_signature_action_$actionKey'),
          color: Colors.transparent,
          child: InkWell(
            onTap: active ? onTap : null,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border.withOpacity(0.85)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.border.withOpacity(0.22),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Center(child: iconChild)),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isFuture ? (futureBadge ?? subtitle) : subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textSecondary,
                        fontSize: 11.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (statusBadge != null && statusBadge!.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          statusBadge!,
                          style: TextStyle(
                            color: palette.accent,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
