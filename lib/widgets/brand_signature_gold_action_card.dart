import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_assets.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';

const BoxFit kBrandSignatureGoldIllustrationFit = BoxFit.contain;
const EdgeInsets kBrandSignatureGoldActionCardPadding = EdgeInsets.fromLTRB(
  12,
  10,
  12,
  10,
);
const double kBrandSignatureGoldActionCardRadius = 16;
const double kBrandSignatureGoldActionIconGap = 6;
const double kBrandSignatureGoldActionCardHeightBoost = 28;

/// Company compact-phone leftover illustration space: card 132 + [kBrandSignatureGoldActionCardHeightBoost]
/// minus padding, title, subtitle. Chauffeur Gold phone tiles reuse this box.
const double kBrandSignatureGoldPhoneCompactCardHeight = 132;
const double kBrandSignatureGoldPhoneActionIconBox = 96;
const int kBrandSignatureGoldPhonePortraitColumns = 2;
const double kBrandSignatureGoldPhoneActionSpacing = 12;
const Key kBrandSignatureGoldPhoneActionGridKey = Key(
  'brand_signature_gold_phone_action_grid',
);

/// Company phone-portrait Gold tiles are always two columns. Chauffeur Gold
/// phone portrait reuses that token. Landscape keeps the existing 4-column
/// chauffeur host grid so Meer extras stay an even 4×2.
int brandSignatureGoldChauffeurPhoneActionColumns({
  required bool isPhoneLandscapeHost,
}) {
  if (isPhoneLandscapeHost) return 4;
  return kBrandSignatureGoldPhonePortraitColumns;
}

/// Gold WebPs carry 10–35% transparent margin. A uniform contain-scale
/// makes the visible metal match fuller company tiles in the same box.
const double kBrandSignatureGoldChauffeurActionIconFill = 1.18;
const Key kBrandSignatureGoldLightCardIconShadowKey = Key(
  'brand_signature_gold_light_card_icon_shadow',
);
const Key kBrandSignatureGoldPhoneActionIconBoxKey = Key(
  'brand_signature_gold_phone_action_icon_box',
);
Key brandSignatureGoldActionTitleKey(String actionKey) =>
    Key('brand_signature_gold_action_title_$actionKey');

double brandSignatureGoldPhoneActionIconExtent({
  required double maxWidth,
  required double maxHeight,
}) {
  final available = maxWidth < maxHeight ? maxWidth : maxHeight;
  if (available <= 0) return 0;
  return available < kBrandSignatureGoldPhoneActionIconBox
      ? available
      : kBrandSignatureGoldPhoneActionIconBox;
}

/// Contained Gold illustration used by company cards and chauffeur Gold icons.
class BrandSignatureGoldContainedIllustration extends StatelessWidget {
  const BrandSignatureGoldContainedIllustration({
    super.key,
    required this.assetKey,
    this.width,
    this.height,
    this.cacheSize,
    this.imageKey,
  });

  final String assetKey;
  final double? width;
  final double? height;
  final int? cacheSize;
  final Key? imageKey;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      brandSignatureGoldAssetPath(assetKey),
      key: imageKey ?? key,
      width: width,
      height: height,
      fit: kBrandSignatureGoldIllustrationFit,
      alignment: Alignment.center,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      cacheWidth: cacheSize,
      cacheHeight: cacheSize,
    );
  }
}

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
    this.paletteListenable,
    this.contrastTextAgainstCard = false,
    this.rectangularLightCardIconShadow = false,
    this.phoneGoldIconBox = false,
  });

  final String actionKey;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool isFuture;
  final String? futureBadge;
  final String? statusBadge;
  final ValueListenable<BrandSignaturePalette>? paletteListenable;

  /// Chauffeur Gold: title/subtitle contrast against [colors.card], not the
  /// company page token (which can be white on a cream card).
  final bool contrastTextAgainstCard;

  /// Legacy rectangular image-box shadow. Off by default: Gold WebPs already
  /// carry their own lighting, and a container BoxShadow paints a grey matte
  /// behind transparent pixels. Chauffeur Gold also passes false.
  final bool rectangularLightCardIconShadow;

  /// Chauffeur Gold phone tiles only. Company cards keep Expanded + intrinsic
  /// contain. Uses [kBrandSignatureGoldPhoneActionIconBox] and a contain-scale
  /// so transparent asset padding does not shrink the visible metal.
  final bool phoneGoldIconBox;

  @override
  Widget build(BuildContext context) {
    final assetKey = kBrandSignatureGoldActionAssetKeys[actionKey] ?? actionKey;
    final icon = BrandSignatureGoldContainedIllustration(assetKey: assetKey);
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: paletteListenable ?? brandSignaturePaletteNotifier,
      child: icon,
      builder: (context, colors, iconChild) {
        final palette = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        final active = onTap != null && !isFuture;
        final lightCard = brandSignatureRelativeLuminance(colors.card) >= 0.62;
        final titleColor = contrastTextAgainstCard
            ? brandSignatureReadableTextOn(colors.card)
            : palette.textPrimary;
        final muted = Color.lerp(titleColor, colors.card, 0.28)!;
        final subtitleColor = contrastTextAgainstCard
            ? (brandSignatureHasReadableText(muted, colors.card)
                  ? muted
                  : titleColor)
            : palette.textSecondary;
        final iconOnCard = lightCard && rectangularLightCardIconShadow
            ? DecoratedBox(
                key: kBrandSignatureGoldLightCardIconShadowKey,
                decoration: const BoxDecoration(
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: iconChild,
              )
            : iconChild;
        return Material(
          key: Key('brand_signature_action_$actionKey'),
          color: Colors.transparent,
          child: InkWell(
            onTap: active ? onTap : null,
            borderRadius: BorderRadius.circular(
              kBrandSignatureGoldActionCardRadius,
            ),
            child: Ink(
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(
                  kBrandSignatureGoldActionCardRadius,
                ),
                border: Border.all(color: colors.border.withOpacity(0.85)),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: colors.border.withOpacity(0.22),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Padding(
                padding: kBrandSignatureGoldActionCardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: phoneGoldIconBox
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                final box =
                                    brandSignatureGoldPhoneActionIconExtent(
                                      maxWidth: constraints.maxWidth,
                                      maxHeight: constraints.maxHeight,
                                    );
                                final dpr =
                                    MediaQuery.maybeDevicePixelRatioOf(
                                      context,
                                    ) ??
                                    2.0;
                                final decode = (box * dpr).round().clamp(
                                  48,
                                  256,
                                );
                                return Center(
                                  child: SizedBox(
                                    key:
                                        kBrandSignatureGoldPhoneActionIconBoxKey,
                                    width: box,
                                    height: box,
                                    child: ClipRect(
                                      child: Transform.scale(
                                        scale:
                                            kBrandSignatureGoldChauffeurActionIconFill,
                                        child:
                                            BrandSignatureGoldContainedIllustration(
                                              assetKey: assetKey,
                                              width: box,
                                              height: box,
                                              cacheSize: decode,
                                            ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : Center(child: iconOnCard),
                    ),
                    const SizedBox(height: kBrandSignatureGoldActionIconGap),
                    Text(
                      title,
                      key: brandSignatureGoldActionTitleKey(actionKey),
                      maxLines: phoneGoldIconBox ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: titleColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    if (!phoneGoldIconBox ||
                        (isFuture ? (futureBadge ?? subtitle) : subtitle)
                            .trim()
                            .isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        isFuture ? (futureBadge ?? subtitle) : subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 11.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
