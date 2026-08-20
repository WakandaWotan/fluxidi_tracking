// Commercial first-impression card for nearby discovery and the settings
// preview. Shows only logo, title, the full public description and the two
// CTAs. Price, fleet counts and offer scopes belong behind "Bekijk aanbod".

import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_brand_logo.dart';
import 'limousine_customer_discovery.dart';
import 'limousine_customer_discovery_labels.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_public_cover_view.dart';

const Key kLimousinePublicCompanyCardBodyKey = ValueKey<String>(
  'limousine_public_company_card_body',
);

class LimousinePublicCompanyCard extends StatelessWidget {
  const LimousinePublicCompanyCard({
    super.key,
    required this.card,
    required this.tokens,
    required this.language,
    this.horizontal = false,
    this.onOpenOffers,
    this.onOpenProfile,
    this.showActions = true,
  });

  final LimousineDiscoveryCard card;
  final LimousineUxTokens tokens;
  final AppLanguage language;
  final bool horizontal;
  final VoidCallback? onOpenOffers;
  final VoidCallback? onOpenProfile;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final split = horizontal && viewport.width > viewport.height;
    final spec = limousinePublicCoverSpec(
      viewport: viewport,
      explicitCover: card.coverIsExplicit,
      alignment: card.coverAlignment,
    );
    final photo = LimousinePublicCoverFrame(
      imageUrl: card.coverImageUrl,
      spec: spec,
      background: tokens.surfaceAlt,
      gold: tokens.gold,
      photoKey: limousineDiscoveryCardCoverKey(card.publicPartnerId),
    );
    final info = _info();
    final body = split
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 11, child: photo),
              const SizedBox(width: 16),
              Expanded(flex: 9, child: info),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [photo, const SizedBox(height: 12), info],
          );
    return Material(
      key: limousineDiscoveryCardKey(card.publicPartnerId),
      color: tokens.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: tokens.border),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [tokens.surface, tokens.surfaceAlt.withOpacity(0.5)],
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(12), child: body),
      ),
    );
  }

  Widget _info() {
    final title = limousineDiscoveryCardTitle(card, language);
    final description = limousineDiscoveryCardDescription(card, language);
    return Padding(
      key: kLimousinePublicCompanyCardBodyKey,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LimousineDiscoveryCompanyIdentity(
            logoUrl: card.logoUrl,
            companyName: '',
            tokens: tokens,
            logoImage: card.logoImage,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            key: limousineDiscoveryCardTitleKey(card.publicPartnerId),
            softWrap: true,
            style: TextStyle(
              color: tokens.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              description,
              key: limousineDiscoveryCardDescriptionKey(card.publicPartnerId),
              softWrap: true,
              style: TextStyle(
                color: tokens.muted,
                fontSize: 13.5,
                height: 1.35,
              ),
            ),
          ],
          if (showActions) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: limousineDiscoveryOffersCtaKey(card.publicPartnerId),
                onPressed: onOpenOffers,
                style: FilledButton.styleFrom(
                  backgroundColor: tokens.gold,
                  foregroundColor: const Color(0xFF1A1408),
                  minimumSize: const Size.fromHeight(46),
                ),
                child: Text(kLimousineDiscoveryViewOffers.of(language)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: limousineDiscoveryProfileCtaKey(card.publicPartnerId),
                onPressed: onOpenProfile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.onSurface,
                  side: BorderSide(color: tokens.gold.withOpacity(0.55)),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(kLimousineDiscoveryViewProfile.of(language)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
