// LIMOUSINE-MARKETPLACE-P2D2A — safe public showroom projection consumed from
// the already-loaded partner profile. No extra HTTP. No invented eligibility.

import 'package:flutter/foundation.dart';

import '../app_strings.dart';
import 'limousine_customer_quote.dart';
import 'limousine_customer_quote_labels.dart';
import 'limousine_offer_binding.dart';
import 'limousine_offers.dart';
import 'limousine_pricing_overlay.dart';
import 'limousine_public_showroom_labels.dart';
import 'limousine_quote_inbox.dart';

const Key kLimousinePublicShowroomSectionKey = ValueKey<String>(
  'limousine_public_showroom_section',
);

Key limousineShowroomCardKey(String offerId) =>
    ValueKey<String>('limousine_public_showroom_card_$offerId');

Key limousineShowroomViewKey(String offerId) =>
    ValueKey<String>('limousine_public_showroom_view_$offerId');

Key limousineShowroomQuoteCtaKey(String offerId) =>
    ValueKey<String>('limousine_public_showroom_quote_cta_$offerId');

Key limousineShowroomBookCtaKey(String offerId) =>
    ValueKey<String>('limousine_public_showroom_book_cta_$offerId');

/// Opening the public partner profile still performs exactly one HTTP GET
/// (`GET /partners/profile`). The showroom reads that in-memory payload.
const int kLimousinePublicShowroomProfileHttpGets = 1;

const Set<String> kLimousineShowroomPrivateKeys = <String>{
  'license_plate',
  'licenseplate',
  'vin',
  'vehicle_registration_number',
  'exploitation_license_number',
  'assigned_driver',
  'driver_id',
  'notes',
  'internal_notes',
  'base_address',
  'operating_base_address',
  'current_address',
  'internal_cost',
  'margin',
  'limousine_entitled',
};

enum LimousineShowroomCta { none, requestQuote, book }

bool limousinePublicProfileMarksAvailable(Map<String, dynamic>? profile) {
  if (profile == null || profile.isEmpty) return false;
  if (profile['limousine_available'] == true) return true;
  if (profile['limousine_service_enabled'] == true) return true;
  final projection = profile['limousine_projection'];
  if (projection is Map) {
    return projection['limousine_available'] == true ||
        projection['limousine_service_enabled'] == true;
  }
  return false;
}

bool limousinePublicShowroomShouldRender({
  required bool entryEnabled,
  required Map<String, dynamic>? profile,
}) {
  if (!entryEnabled) return false;
  if (!limousinePublicProfileMarksAvailable(profile)) return false;
  return collectLimousineShowroomOffers(profile).isNotEmpty;
}

LimousinePublishedOffer? tryParseLimousineShowroomOffer(Object? raw) {
  if (raw is! Map) return null;
  final map = raw.map((key, value) => MapEntry(key.toString(), value));
  if (map.containsKey('enabled') && map['enabled'] != true) return null;
  if (map.containsKey('published') && map['published'] != true) return null;
  final offer = LimousinePublishedOffer.fromJson(map);
  if (offer.offerId.isEmpty) return null;
  if (!LimousineOfferTarget.all.contains(offer.targetType)) return null;
  if (!LimousinePricePresentation.all.contains(offer.pricePresentation)) {
    return null;
  }
  if (offer.isVehicleTargeted) {
    final boundIds = limousineNormalizeBoundVehicleIds(
      map['vehicle_ids'] ?? map['vehicleIds'],
      single: offer.vehicleId,
    );
    if (boundIds.isEmpty) return null;
  }
  final showsAmount =
      offer.displayAmountCents != null && offer.displayAmountCents! > 0;
  if (showsAmount && offer.currency.isEmpty) return null;
  return offer;
}

List<LimousinePublishedOffer> collectLimousineShowroomOffers(
  Map<String, dynamic>? profile,
) {
  if (profile == null) return const <LimousinePublishedOffer>[];
  profile = limousineHydratePublicPartnerOverlay(profile);
  final raw = profile['limousine_offers'] ?? profile['limousineOffers'];
  if (raw is! List) return const <LimousinePublishedOffer>[];
  final parsed = <LimousinePublishedOffer>[];
  for (final item in raw) {
    final offer = tryParseLimousineShowroomOffer(item);
    if (offer != null) parsed.add(offer);
  }
  return limousineDeduplicatePublishedOffers(
    sortLimousineOffersVehicleFirst(parsed),
  );
}

LimousineShowroomCta limousineShowroomCtaFor(LimousinePublishedOffer offer) {
  switch (offer.pricePresentation) {
    case LimousinePricePresentation.unavailable:
      return LimousineShowroomCta.none;
    case LimousinePricePresentation.exactFixed:
      return LimousineShowroomCta.book;
    case LimousinePricePresentation.fromPrice:
    case LimousinePricePresentation.indicative:
    case LimousinePricePresentation.quoteRequired:
      return LimousineShowroomCta.requestQuote;
    default:
      return LimousineShowroomCta.none;
  }
}

String limousineShowroomPriceLabel(
  LimousinePublishedOffer offer,
  AppLanguage language,
) {
  if (offer.pricePresentation == LimousinePricePresentation.unavailable) {
    return kLimousineShowroomUnavailable.of(language);
  }
  if (offer.pricePresentation == LimousinePricePresentation.quoteRequired) {
    return kLimousineShowroomPriceOnRequest.of(language);
  }
  final cents = offer.displayAmountCents;
  final currency = offer.currency.trim();
  if (cents == null || cents <= 0 || currency.isEmpty) {
    return limousineCustomerPresentationLabel(
      offer.pricePresentation,
      language,
    );
  }
  final money = formatLimousineMoney(cents, currency);
  switch (offer.pricePresentation) {
    case LimousinePricePresentation.fromPrice:
      return '${kLimousineShowroomFrom.of(language)} $money';
    case LimousinePricePresentation.indicative:
      return '${kLimousineShowroomIndicative.of(language)} $money';
    default:
      return money;
  }
}

bool limousineShowroomTextLeaksPrivate(String text) {
  final lower = text.toLowerCase();
  for (final key in kLimousineShowroomPrivateKeys) {
    if (lower.contains(key)) return true;
  }
  return limousineTextLooksLikeSecret(text);
}
