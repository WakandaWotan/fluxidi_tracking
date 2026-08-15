import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_gold_assets.dart';
import 'package:fluxidi_tracking/business_theme/brand_signature_palette.dart';
import 'package:fluxidi_tracking/business_theme_palette.dart';
import 'package:fluxidi_tracking/widgets/business_theme_cycle_button.dart';
import 'package:fluxidi_tracking/widgets/business_theme_selector_sheet.dart';

const Key kBrandSignatureGoldHeaderKey = Key('brand_signature_gold_header');
const Key kBrandSignatureGoldLogoKey = Key('brand_signature_gold_logo');
const Key kBrandSignatureGoldLogoFallbackKey = Key(
  'brand_signature_gold_logo_fallback',
);

/// Production Brand Signature header heights from the company home.
const double kBrandSignatureGoldHeaderHeightTabletLandscape = 156;
const double kBrandSignatureGoldHeaderHeightTablet = 208;
const double kBrandSignatureGoldHeaderHeightPhone = 168;
const EdgeInsets kBrandSignatureGoldHeaderLogoPadding = EdgeInsets.fromLTRB(
  28,
  16,
  28,
  16,
);
const double kBrandSignatureGoldHeaderRadius = 18;
const double kBrandSignatureGoldHeaderActionInset = 10;

double brandSignatureGoldHeaderHeightForLayout({
  required bool isTabletLandscape,
  required bool useTabletVisualMode,
}) {
  if (isTabletLandscape) {
    return kBrandSignatureGoldHeaderHeightTabletLandscape;
  }
  if (useTabletVisualMode) {
    return kBrandSignatureGoldHeaderHeightTablet;
  }
  return kBrandSignatureGoldHeaderHeightPhone;
}

class BrandSignatureGoldHeader extends StatelessWidget {
  const BrandSignatureGoldHeader({
    super.key,
    required this.height,
    required this.logoRef,
    required this.hasCompanyLogo,
    required this.companyName,
    this.onOpenThemeSelector,
    this.paletteListenable,
    this.trailing,
  });

  final double height;
  final String logoRef;
  final bool hasCompanyLogo;
  final String companyName;
  final VoidCallback? onOpenThemeSelector;

  /// Defaults to the company Brand Signature store. Chauffeur Gold passes its
  /// isolated chauffeur palette listenable.
  final ValueListenable<BrandSignaturePalette>? paletteListenable;

  /// Defaults to the company theme chip. Chauffeur Gold may pass language /
  /// theme / profile controls in this same top-right inset.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final logo = hasCompanyLogo ? _CompanyLogo(ref: logoRef) : null;
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: paletteListenable ?? brandSignaturePaletteNotifier,
      child: logo,
      builder: (context, colors, logoChild) {
        final palette = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        return SizedBox(
          key: kBrandSignatureGoldHeaderKey,
          height: height,
          width: double.infinity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.header,
              borderRadius: BorderRadius.circular(
                kBrandSignatureGoldHeaderRadius,
              ),
              border: Border.all(color: colors.border.withOpacity(0.72)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: colors.border.withOpacity(0.22),
                  blurRadius: 18,
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: kBrandSignatureGoldHeaderLogoPadding,
                    child:
                        logoChild ??
                        _MonogramFallback(
                          name: companyName,
                          color: palette.textPrimary,
                        ),
                  ),
                ),
                Positioned(
                  top: kBrandSignatureGoldHeaderActionInset,
                  right: kBrandSignatureGoldHeaderActionInset,
                  child:
                      trailing ??
                      BusinessThemeCycleButton(
                        goldThemeAsset: kBrandSignatureGoldThemeAsset,
                        onPressed:
                            onOpenThemeSelector ??
                            () => showBusinessThemeSelectorSheet(context),
                      ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({required this.ref});

  final String ref;

  @override
  Widget build(BuildContext context) {
    Widget image({required ImageProvider provider}) {
      return Image(
        key: kBrandSignatureGoldLogoKey,
        image: provider,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) =>
            const _MonogramFallback(name: '', color: Color(0xFFF8F0D8)),
      );
    }

    if (ref.startsWith('assets/')) {
      return image(provider: AssetImage(ref));
    }
    if (ref.startsWith('http://') || ref.startsWith('https://')) {
      return image(provider: NetworkImage(ref));
    }
    if (!kIsWeb) {
      return image(provider: FileImage(File(ref)));
    }
    return const _MonogramFallback(name: '', color: Color(0xFFF8F0D8));
  }
}

class _MonogramFallback extends StatelessWidget {
  const _MonogramFallback({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final glyph = trimmed.isEmpty
        ? 'B'
        : String.fromCharCode(trimmed.runes.first).toUpperCase();
    return Center(
      child: Text(
        glyph,
        key: kBrandSignatureGoldLogoFallbackKey,
        style: TextStyle(
          color: color,
          fontSize: 72,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

bool brandSignatureHasTenantLogo({
  required String logoRef,
  required CompanyLogoSource source,
}) {
  if (source == CompanyLogoSource.fluxidiFallback ||
      source == CompanyLogoSource.none) {
    return false;
  }
  if (isDefaultFluxidiLogoRef(
    logoRef,
    configuredAsset: kPackagedFluxidiLogoAsset,
  )) {
    return false;
  }
  return logoRef.trim().isNotEmpty;
}
