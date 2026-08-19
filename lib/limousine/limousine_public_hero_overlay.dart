// Shared public limousine hero chrome: partner logo top-right, description
// bottom-left. Never paints a platform name.

import 'package:flutter/material.dart';

import '../nearby/public_partner_identity.dart';
import 'limousine_p2d4c1a_ux.dart';

const Key kLimousinePublicHeroOverlayKey = ValueKey<String>(
  'limousine_public_hero_overlay',
);
const Key kLimousinePublicHeroLogoKey = ValueKey<String>(
  'limousine_public_hero_logo',
);
const Key kLimousinePublicHeroNameKey = ValueKey<String>(
  'limousine_public_hero_name',
);
const Key kLimousinePublicHeroDescriptionKey = ValueKey<String>(
  'limousine_public_hero_description',
);

const Color kLimousinePublicHeroOnImage = Color(0xFFF6F1E8);

class LimousinePublicHeroOverlay extends StatelessWidget {
  const LimousinePublicHeroOverlay({
    super.key,
    required this.identity,
    required this.tokens,
    this.compact = false,
    this.includeTopSafeArea = false,
    this.verified = false,
    this.distanceLabel = '',
  });

  final PublicPartnerHeroIdentity identity;
  final LimousineUxTokens tokens;
  final bool compact;
  final bool includeTopSafeArea;
  final bool verified;
  final String distanceLabel;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = MediaQuery.sizeOf(context);
        final tablet = viewport.shortestSide >= 600;
        final inset = tablet ? 20.0 : 14.0;
        final topSafe = includeTopSafeArea
            ? MediaQuery.paddingOf(context).top
            : 0.0;
        final logoMaxHeight = (constraints.maxHeight * (compact ? 0.36 : 0.28))
            .clamp(40.0, compact ? 64.0 : (tablet ? 88.0 : 72.0));
        final logoMaxWidth = (constraints.maxWidth * 0.34).clamp(
          72.0,
          tablet ? 200.0 : 148.0,
        );
        return Stack(
          key: kLimousinePublicHeroOverlayKey,
          fit: StackFit.expand,
          children: [
            if (identity.description.isNotEmpty ||
                distanceLabel.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Color(0x00000000),
                        Color(0x99000000),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(inset, 36, inset, inset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (distanceLabel.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              distanceLabel.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: kLimousinePublicHeroOnImage.withOpacity(
                                  0.86,
                                ),
                                fontSize: compact ? 11.5 : 13.5,
                              ),
                            ),
                          ),
                        if (identity.description.isNotEmpty)
                          Text(
                            identity.description,
                            key: kLimousinePublicHeroDescriptionKey,
                            maxLines: compact ? 2 : 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: kLimousinePublicHeroOnImage,
                              fontSize: compact ? 12.5 : 14.5,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (identity.showsLogo || identity.showsName || verified)
              Positioned(
                top: topSafe + inset,
                right: inset,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: logoMaxWidth,
                    maxHeight: logoMaxHeight + (verified ? 22 : 0),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (identity.showsLogo)
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: logoMaxWidth,
                            maxHeight: logoMaxHeight,
                          ),
                          child: _logo(),
                        )
                      else if (identity.showsName)
                        Text(
                          identity.nameFallback,
                          key: kLimousinePublicHeroNameKey,
                          maxLines: 2,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: kLimousinePublicHeroOnImage,
                            fontWeight: FontWeight.w800,
                            fontSize: compact ? 14 : 18,
                            height: 1.2,
                          ),
                        ),
                      if (verified)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.verified,
                            color: tokens.gold,
                            size: compact ? 16 : 20,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _logo() {
    final image = identity.logoImage;
    final child = image != null
        ? Image(
            key: kLimousinePublicHeroLogoKey,
            image: image,
            fit: BoxFit.contain,
            alignment: Alignment.centerRight,
            filterQuality: FilterQuality.medium,
          )
        : Image.network(
            identity.logoUrl,
            key: kLimousinePublicHeroLogoKey,
            fit: BoxFit.contain,
            alignment: Alignment.centerRight,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.22),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(padding: const EdgeInsets.all(6), child: child),
    );
  }
}
