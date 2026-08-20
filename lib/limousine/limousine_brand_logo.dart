// Company branding plaque for public limousine surfaces.
// Logo and vehicle photos stay separate: this widget never reads fleet media.

import 'package:flutter/material.dart';

import '../nearby/public_partner_identity.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom.dart';

enum LimousineCompanyIdentitySurface { discoveryCard, vehicleDetail }

double limousineDiscoveryCompanyLogoHeight(Size viewport) {
  return limousineCompanyIdentityLogoHeight(
    viewport,
    LimousineCompanyIdentitySurface.discoveryCard,
  );
}

double limousineDiscoveryCompanyLogoMaxWidth(Size viewport) {
  return limousineCompanyIdentityLogoMaxWidth(
    viewport,
    LimousineCompanyIdentitySurface.discoveryCard,
  );
}

double limousineCompanyIdentityLogoHeight(
  Size viewport,
  LimousineCompanyIdentitySurface surface,
) {
  final tablet = viewport.shortestSide >= 600;
  switch (surface) {
    case LimousineCompanyIdentitySurface.discoveryCard:
      return tablet ? 52 : 40;
    case LimousineCompanyIdentitySurface.vehicleDetail:
      return tablet ? 36 : 28;
  }
}

double limousineCompanyIdentityLogoMaxWidth(
  Size viewport,
  LimousineCompanyIdentitySurface surface,
) {
  final tablet = viewport.shortestSide >= 600;
  switch (surface) {
    case LimousineCompanyIdentitySurface.discoveryCard:
      return tablet ? 220 : 160;
    case LimousineCompanyIdentitySurface.vehicleDetail:
      return tablet ? 140 : 96;
  }
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
  return publicPartnerLogoIsRenderable(logoUrl);
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

/// Company mark for discovery cards and vehicle detail: logo only, no plate.
class LimousineCompanyIdentity extends StatelessWidget {
  const LimousineCompanyIdentity({
    super.key,
    required this.logoUrl,
    required this.companyName,
    required this.tokens,
    this.logoImage,
    this.surface = LimousineCompanyIdentitySurface.discoveryCard,
  });

  final String logoUrl;
  final String companyName;
  final LimousineUxTokens tokens;
  final ImageProvider? logoImage;
  final LimousineCompanyIdentitySurface surface;

  Key get _logoKey {
    return surface == LimousineCompanyIdentitySurface.vehicleDetail
        ? kLimousineDetailCompanyLogoKey
        : kLimousineDiscoveryCompanyLogoKey;
  }

  Key get _fallbackKey {
    return surface == LimousineCompanyIdentitySurface.vehicleDetail
        ? kLimousineDetailCompanyNameFallbackKey
        : kLimousineDiscoveryCompanyNameFallbackKey;
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final height = limousineCompanyIdentityLogoHeight(viewport, surface);
    final maxWidth = limousineCompanyIdentityLogoMaxWidth(viewport, surface);
    final name = sanitizePublicPartnerBrandName(companyName);
    final urlWins = limousinePublicLogoUrlIsRenderable(logoUrl);
    final staleNetworkImage =
        logoImage is NetworkImage &&
        (logoImage as NetworkImage).url.trim() != logoUrl.trim();
    final resolvedImage = staleNetworkImage ? null : logoImage;
    final showLogo = urlWins || resolvedImage != null;

    Widget nameFallback() {
      if (name.isEmpty) return const SizedBox.shrink();
      return Text(
        name,
        key: _fallbackKey,
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
        child: resolvedImage != null
            ? Image(
                key: _logoKey,
                image: resolvedImage,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.medium,
              )
            : Image.network(
                logoUrl.trim(),
                key: _logoKey,
                fit: BoxFit.contain,
                alignment: Alignment.centerLeft,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => nameFallback(),
              ),
      ),
    );
  }
}

/// Discovery-card company mark: logo only, no plate, never over the vehicle photo.
class LimousineDiscoveryCompanyIdentity extends LimousineCompanyIdentity {
  const LimousineDiscoveryCompanyIdentity({
    super.key,
    required super.logoUrl,
    required super.companyName,
    required super.tokens,
    super.logoImage,
  }) : super(surface: LimousineCompanyIdentitySurface.discoveryCard);
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

/// Settings-only logo preview: full mark, never cropped.
class LimousineSetupLogoPreview extends StatelessWidget {
  const LimousineSetupLogoPreview({
    super.key,
    required this.imageUrl,
    required this.background,
    this.tablet = false,
  });

  final String imageUrl;
  final Color background;
  final bool tablet;

  Size get box => tablet ? const Size(200, 104) : const Size(152, 84);

  @override
  Widget build(BuildContext context) {
    final size = box;
    final url = imageUrl.trim();
    return ColoredBox(
      color: background,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: url.startsWith('https://')
            ? Image.network(
                url,
                width: size.width,
                height: size.height,
                fit: BoxFit.contain,
                alignment: Alignment.center,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
