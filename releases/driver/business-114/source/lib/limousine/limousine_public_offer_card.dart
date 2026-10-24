// Shared public offer card used by customer detail and settings preview.
// Featured is a visible badge only. It does not change CTA, price or sort.

import 'package:flutter/material.dart';

import '../app_strings.dart';
import 'limousine_business_setup.dart';
import 'limousine_business_setup_labels.dart';
import 'limousine_customer_quote.dart';
import 'limousine_offer_binding.dart';
import 'limousine_p2d4c1a_ux.dart';
import 'limousine_provider_showroom.dart';
import 'limousine_provider_showroom_labels.dart';
import 'limousine_public_copy.dart';
import 'limousine_public_showroom.dart';
import 'limousine_quote_inbox.dart';

class LimousineRecommendedBadge extends StatelessWidget {
  const LimousineRecommendedBadge({
    super.key,
    required this.offerId,
    required this.language,
    required this.tokens,
  });

  final String offerId;
  final AppLanguage language;
  final LimousineUxTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: limousineRecommendedBadgeKey(offerId),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: tokens.gold.withOpacity(tokens.isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tokens.gold.withOpacity(0.55)),
      ),
      child: Text(
        kLimousineOfferRecommendedBadge.of(language),
        style: TextStyle(
          color: tokens.gold,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

Color limousinePublicOfferBorderColor({
  required LimousineUxTokens tokens,
  required bool featured,
}) {
  if (!featured) return tokens.border;
  return tokens.gold.withOpacity(tokens.isDark ? 0.55 : 0.48);
}

class LimousinePublicOfferCard extends StatelessWidget {
  const LimousinePublicOfferCard({
    super.key,
    required this.offer,
    required this.language,
    required this.tokens,
    this.showCta = false,
    this.quoteEnabled = false,
    this.bookEnabled = false,
    this.isSummary = false,
    this.onQuote,
    this.onBook,
    this.cardKey,
  });

  final LimousinePublishedOffer offer;
  final AppLanguage language;
  final LimousineUxTokens tokens;
  final bool showCta;
  final bool quoteEnabled;
  final bool bookEnabled;
  final bool isSummary;
  final VoidCallback? onQuote;
  final VoidCallback? onBook;
  final Key? cardKey;

  @override
  Widget build(BuildContext context) {
    final kind = limousinePublishedDisplayKind(offer);
    final title = localizedLimousineText(
      offer.title,
      languageCode: language.name,
    );
    final description = localizedLimousineText(
      offer.description,
      languageCode: language.name,
    );
    final included = limousineIncludedServicesLabel(offer, language);
    final generic =
        title.trim().toLowerCase() == 'limousine' ||
        description.trim().toLowerCase() ==
            'limousine / arrangementen / limousine';
    final kindLabel = limousineDetailOfferKindLabel(kind, language);
    final priceLabel = kind == LimousineOfferDisplayKind.fromPrice
        ? limousineFormatPublishedOfferAmount(offer, language)
        : limousineFormatPublishedOfferPrice(offer, language);
    final showKindEyebrow = limousineShouldShowOfferKindEyebrow(
      kindLabel,
      priceLabel,
    );
    final cta = showCta
        ? limousineDetailCtaFor(offer)
        : LimousineShowroomCta.none;
    final isBook = cta == LimousineShowroomCta.book;
    final featured = limousinePublishedOfferScope(offer).featured;
    String t(LocalizedText text) => text.of(language);
    return DecoratedBox(
      key: cardKey ?? limousineDetailOfferCardKey(offer.offerId),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: limousinePublicOfferBorderColor(
            tokens: tokens,
            featured: featured,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (featured) ...[
              LimousineRecommendedBadge(
                offerId: offer.offerId,
                language: language,
                tokens: tokens,
              ),
              const SizedBox(height: 8),
            ],
            if (showKindEyebrow) ...[
              Text(
                key: kLimousineDetailOfferKindEyebrowKey,
                kindLabel,
                style: TextStyle(
                  color: tokens.gold,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
            ],
            if (title.isNotEmpty &&
                !generic &&
                !limousinePublicLabelsMatch(title, priceLabel)) ...[
              Text(
                title,
                style: TextStyle(
                  color: tokens.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
            ],
            if (description.isNotEmpty && !generic) ...[
              Text(
                description,
                style: TextStyle(
                  color: tokens.muted,
                  height: 1.35,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 4),
            ],
            Text(
              key: kLimousineDetailOfferPriceKey,
              priceLabel,
              style: TextStyle(
                color: tokens.gold,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (kind == LimousineOfferDisplayKind.fromPrice) ...[
              const SizedBox(height: 4),
              Text(
                t(kLimousineOfferFromPriceDisclaimer),
                style: TextStyle(
                  color: tokens.muted,
                  fontSize: 11.5,
                  height: 1.3,
                ),
              ),
            ],
            if (included.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                included,
                style: TextStyle(
                  color: tokens.onSurface,
                  height: 1.3,
                  fontSize: 13,
                ),
              ),
            ],
            if (cta != LimousineShowroomCta.none) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  key: isSummary
                      ? (isBook
                            ? kLimousineDetailBookCtaKey
                            : kLimousineDetailQuoteCtaKey)
                      : ValueKey<String>(
                          'limousine_vehicle_detail_cta_${offer.offerId}',
                        ),
                  onPressed: (isBook ? bookEnabled : quoteEnabled)
                      ? (isBook ? onBook : onQuote)
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.gold,
                    foregroundColor: const Color(0xFF1A1408),
                    disabledBackgroundColor: tokens.gold.withOpacity(0.28),
                    disabledForegroundColor: tokens.muted,
                    minimumSize: const Size(88, 44),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                  ),
                  child: Text(
                    isBook
                        ? (bookEnabled
                              ? t(kLimousineDetailBookCta)
                              : t(kLimousineDetailBookComingSoon))
                        : (quoteEnabled
                              ? t(kLimousineDetailQuoteCta)
                              : t(kLimousineDetailQuoteComingSoon)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
