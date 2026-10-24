import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fluxidi_tracking/branding/company_logo_ref.dart';
import 'package:fluxidi_tracking/fluxidi_responsive.dart';
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
const double kBrandSignatureGoldHeaderHeightDesktopWide = 96;
const EdgeInsets kBrandSignatureGoldHeaderLogoPadding = EdgeInsets.fromLTRB(
  28,
  16,
  28,
  16,
);
const double kBrandSignatureGoldHeaderRadius = 18;
const double kBrandSignatureGoldHeaderActionInset = 10;
const double kBrandSignatureGoldHeaderActionGap = 8;

double brandSignatureGoldHeaderHeightForLayout({
  required bool isTabletLandscape,
  required bool useTabletVisualMode,
  bool isDesktopWide = false,
}) {
  if (isDesktopWide) {
    return kBrandSignatureGoldHeaderHeightDesktopWide;
  }
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
    this.accountMenu,
    this.extraAction,
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

  /// GOLD-THEME-ACCOUNT-MENU-RESTORE-P0: optional shared business account /
  /// company menu trigger. When set (company Gold), it is rendered as a
  /// separate button to the left of the retained palette (theme) control in
  /// the same top-right inset. When null (chauffeur Gold, previews, default),
  /// only the palette control shows — unchanged behaviour. This slot never
  /// replaces the palette button; [trailing] (chauffeur) still fully overrides
  /// the inset when provided.
  final Widget? accountMenu;

  /// Optional company action beside the account and theme controls.
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    final logo = hasCompanyLogo
        ? _CompanyLogo(ref: logoRef, companyName: companyName)
        : null;
    return ValueListenableBuilder<BrandSignaturePalette>(
      valueListenable: paletteListenable ?? brandSignaturePaletteNotifier,
      child: logo,
      builder: (context, colors, logoChild) {
        final palette = paletteForBusinessTheme(
          BusinessThemeVariant.brandSignatureGold,
        );
        // Palette (theme) control — retained exactly as before, its own hit
        // target and key ([BusinessThemeCycleButton.buttonKey]).
        final themeControl = BusinessThemeCycleButton(
          goldThemeAsset: kBrandSignatureGoldThemeAsset,
          onPressed:
              onOpenThemeSelector ??
              () => showBusinessThemeSelectorSheet(context),
        );
        // Two separate buttons when the account menu slot is provided; palette
        // only otherwise. Both sit in the same top-right inset.
        final Widget actions = accountMenu == null
            ? themeControl
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  accountMenu!,
                  const SizedBox(width: kBrandSignatureGoldHeaderActionGap),
                  if (extraAction != null) ...[
                    extraAction!,
                    const SizedBox(width: kBrandSignatureGoldHeaderActionGap),
                  ],
                  themeControl,
                ],
              );
        final decoration = BoxDecoration(
          color: colors.header,
          borderRadius: BorderRadius.circular(kBrandSignatureGoldHeaderRadius),
          border: Border.all(color: colors.border.withOpacity(0.72)),
          boxShadow: <BoxShadow>[
            BoxShadow(color: colors.border.withOpacity(0.22), blurRadius: 18),
          ],
        );
        final mark =
            logoChild ??
            _GoldHeaderFallbackMark(
              name: companyName,
              color: brandSignatureReadableTextOn(colors.header),
            );
        return LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth.isFinite
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
            final screen = MediaQuery.sizeOf(context);
            final stacked = brandSignatureGoldUsesStackedMobilePortrait(
              width: width,
              height: screen.height,
            );
            if (!stacked) {
              return SizedBox(
                key: kBrandSignatureGoldHeaderKey,
                height: height,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: decoration,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: kBrandSignatureGoldHeaderLogoPadding,
                          child: mark,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: kBrandSignatureGoldHeaderActionInset,
                          right: kBrandSignatureGoldHeaderActionInset,
                          bottom: kBrandSignatureGoldHeaderActionInset,
                        ),
                        child: Align(
                          alignment: Alignment.topRight,
                          child: trailing ?? actions,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            final logoBox = brandSignatureGoldMobilePortraitLogoBox(width);
            final innerWidth = math.max(0.0, width - 32);
            final logoWidth = math.min(logoBox.width, innerWidth);
            final logoHeight = logoBox.width <= 0
                ? logoBox.height
                : logoBox.height * (logoWidth / logoBox.width);
            return DecoratedBox(
              key: kBrandSignatureGoldHeaderKey,
              decoration: decoration,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing ?? actions,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: SizedBox(
                        width: logoWidth,
                        height: logoHeight,
                        child: mark,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CompanyLogo extends StatelessWidget {
  const _CompanyLogo({required this.ref, required this.companyName});

  final String ref;
  final String companyName;

  @override
  Widget build(BuildContext context) {
    Widget image({required ImageProvider provider}) {
      return Image(
        key: kBrandSignatureGoldLogoKey,
        image: provider,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => _GoldHeaderFallbackMark(
          name: companyName,
          color: const Color(0xFFF8F0D8),
        ),
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
    return const _GoldHeaderFallbackMark(name: '', color: Color(0xFFF8F0D8));
  }
}

class _GoldHeaderFallbackMark extends StatelessWidget {
  const _GoldHeaderFallbackMark({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      return Center(
        child: Text(
          trimmed,
          key: kBrandSignatureGoldLogoFallbackKey,
          textAlign: TextAlign.center,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Center(
      child: Image.asset(
        'assets/fluxidi/fluxidi_logo_horizontal_gold.png',
        key: kBrandSignatureGoldLogoFallbackKey,
        fit: BoxFit.contain,
        alignment: Alignment.center,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Text(
          'B',
          style: TextStyle(
            color: color,
            fontSize: 48,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Phone portrait only. Tablet, desktop and landscape keep the side-by-side row.
bool brandSignatureGoldUsesStackedMobilePortrait({
  required double width,
  required double height,
}) {
  return height > width && width <= FluxidiBreakpoints.largePhoneMax;
}

/// Maximum logo frame for the stacked phone-portrait header.
Size brandSignatureGoldMobilePortraitLogoBox(double width) {
  if (width <= FluxidiBreakpoints.compactPhoneMax) return const Size(240, 84);
  if (width <= FluxidiBreakpoints.phoneMax) return const Size(280, 94);
  return const Size(320, 104);
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
