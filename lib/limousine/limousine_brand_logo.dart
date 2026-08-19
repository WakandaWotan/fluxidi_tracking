// Company branding plaque for public limousine surfaces.
// Logo and vehicle photos stay separate: this widget never reads fleet media.

import 'package:flutter/material.dart';

import '../branding/company_logo_ref.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_p2d4c1a_ux.dart';

double limousineDiscoveryCompanyLogoHeight(Size viewport) {
  return viewport.shortestSide >= 600 ? 52 : 40;
}

double limousineDiscoveryCompanyLogoMaxWidth(Size viewport) {
  return viewport.shortestSide >= 600 ? 220 : 160;
}

const Key kLimousineBrandLogoPlaqueKey = ValueKey<String>(
  'limousine_brand_logo_plaque',
);
const Key kLimousineBrandLogoImageKey = ValueKey<String>(
  'limousine_brand_logo_image',
);
const Key kLimousineBrandLogoInitialsKey = ValueKey<String>(
  'limousine_brand_logo_initials',
);

const double kLimousineLogoDiscoveryMin = 72;
const double kLimousineLogoDiscoveryMax = 96;
const double kLimousineLogoHeroMin = 120;
const double kLimousineLogoHeroMax = 160;
const double kLimousineLogoDetailMin = 88;
const double kLimousineLogoDetailMax = 120;

String limousineCompanyInitials(String companyName) {
  final parts = companyName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  if (parts.isEmpty) return 'L';
  if (parts.length == 1) {
    final word = parts.first;
    return word.substring(0, word.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

bool limousinePublicLogoUrlIsRenderable(String logoUrl) {
  return classifyCompanyLogoRef(logoUrl) == CompanyLogoRefKind.network &&
      logoUrl.trim().startsWith('https://');
}

class LimousineBrandLogoPlaque extends StatelessWidget {
  const LimousineBrandLogoPlaque({
    super.key,
    required this.logoUrl,
    required this.companyName,
    required this.minExtent,
    required this.maxExtent,
    required this.tokens,
    this.semanticLabel,
  });

  final String logoUrl;
  final String companyName;
  final double minExtent;
  final double maxExtent;
  final LimousineUxTokens tokens;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final shortest = MediaQuery.sizeOf(context).shortestSide;
    final scale = (shortest / 800).clamp(0.82, 1.12);
    final minSize = (minExtent * scale).clamp(minExtent * 0.85, minExtent);
    final maxSize = (maxExtent * scale).clamp(maxExtent * 0.85, maxExtent);
    final initials = limousineCompanyInitials(companyName);
    final plate = ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: minSize,
        minHeight: minSize * 0.72,
        maxWidth: maxSize,
        maxHeight: maxSize,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.isDark
              ? const Color(0xF2F4EFE6)
              : const Color(0xF2FFFDF8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.gold.withOpacity(0.45), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: limousinePublicLogoUrlIsRenderable(logoUrl)
              ? Image.network(
                  logoUrl.trim(),
                  key: kLimousineBrandLogoImageKey,
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, __, ___) => _initials(initials),
                )
              : _initials(initials),
        ),
      ),
    );
    return Semantics(
      key: kLimousineBrandLogoPlaqueKey,
      image: limousinePublicLogoUrlIsRenderable(logoUrl),
      label: semanticLabel ?? companyName,
      child: plate,
    );
  }

  Widget _initials(String initials) {
    return FittedBox(
      key: kLimousineBrandLogoInitialsKey,
      fit: BoxFit.scaleDown,
      child: Text(
        initials,
        style: TextStyle(
          color: tokens.gold,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          fontSize: 28,
        ),
      ),
    );
  }
}

/// Discovery-card company mark: logo only, no plate, never over the vehicle photo.
class LimousineDiscoveryCompanyIdentity extends StatelessWidget {
  const LimousineDiscoveryCompanyIdentity({
    super.key,
    required this.logoUrl,
    required this.companyName,
    required this.tokens,
    this.logoImage,
  });

  final String logoUrl;
  final String companyName;
  final LimousineUxTokens tokens;
  final ImageProvider? logoImage;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final height = limousineDiscoveryCompanyLogoHeight(viewport);
    final maxWidth = limousineDiscoveryCompanyLogoMaxWidth(viewport);
    final name = companyName.trim();
    final showLogo =
        logoImage != null || limousinePublicLogoUrlIsRenderable(logoUrl);

    Widget nameFallback() {
      return Text(
        name,
        key: kLimousineDiscoveryCompanyNameFallbackKey,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tokens.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    if (!showLogo) return nameFallback();

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: height,
          maxHeight: height,
          maxWidth: maxWidth,
        ),
        child: logoImage != null
            ? Image(
                key: kLimousineDiscoveryCompanyLogoKey,
                image: logoImage!,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.medium,
              )
            : Image.network(
                logoUrl.trim(),
                key: kLimousineDiscoveryCompanyLogoKey,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => nameFallback(),
              ),
      ),
    );
  }
}

/// Anchors the plaque in a hero/card corner without covering the visual center.
class LimousineBrandLogoCorner extends StatelessWidget {
  const LimousineBrandLogoCorner({
    super.key,
    required this.child,
    this.alignment = Alignment.bottomLeft,
  });

  final Widget child;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.sizeOf(context).shortestSide >= 600 ? 20.0 : 14.0;
    return SafeArea(
      child: Align(
        alignment: alignment,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            alignment.x <= 0 ? inset : inset * 2.4,
            inset,
            alignment.x >= 0 ? inset : inset * 2.4,
            inset,
          ),
          child: child,
        ),
      ),
    );
  }
}
