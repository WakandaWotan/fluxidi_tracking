// LIMOUSINE-UNIFIED-BOOKING-P3A — customer-side classification of the five
// published price modes. Server authority still wins; this only chooses CTA
// and which existing Fluxidi route to call.

import 'limousine_customer_quote.dart';
import 'limousine_offer_binding.dart';
import 'limousine_offers.dart';

const String kLimousineServiceType = 'limousine';

enum LimousinePublishedPricingMode {
  quoteRequired,
  fromPrice,
  exactFixed,
  hourly,
  package,
}

enum LimousineCustomerIntentKind { quoteRequest, bookingRequest }

LimousinePublishedPricingMode limousinePublishedPricingModeOf(
  LimousinePublishedOffer offer,
) {
  final hourly = offer.raw['hourly'] is Map
      ? Map<String, dynamic>.from(offer.raw['hourly'] as Map)
      : const <String, dynamic>{};
  final hourlyOn = hourly['enabled'] == true;
  final packageAmount = limousineCentsOf(hourly['package_amount_cents']);
  final packageDuration = limousineMinutesOf(hourly['package_duration_minutes']);
  if (hourlyOn &&
      packageAmount != null &&
      packageAmount > 0 &&
      packageDuration != null &&
      packageDuration > 0) {
    return LimousinePublishedPricingMode.package;
  }
  if (hourlyOn) return LimousinePublishedPricingMode.hourly;
  switch (limousinePublishedDisplayKind(offer)) {
    case LimousineOfferDisplayKind.hourly:
      return LimousinePublishedPricingMode.hourly;
    case LimousineOfferDisplayKind.package:
      return LimousinePublishedPricingMode.package;
    case LimousineOfferDisplayKind.fixed:
      return LimousinePublishedPricingMode.exactFixed;
    case LimousineOfferDisplayKind.fromPrice:
      return LimousinePublishedPricingMode.fromPrice;
    case LimousineOfferDisplayKind.quote:
      break;
  }
  final presentation = limousineOfferToken(offer.pricePresentation);
  if (presentation == LimousinePricePresentation.exactFixed) {
    return LimousinePublishedPricingMode.exactFixed;
  }
  if (presentation == LimousinePricePresentation.fromPrice ||
      presentation == LimousinePricePresentation.indicative) {
    return LimousinePublishedPricingMode.fromPrice;
  }
  return LimousinePublishedPricingMode.quoteRequired;
}

LimousineCustomerIntentKind limousineCustomerIntentKindOf(
  LimousinePublishedOffer? offer,
) {
  if (offer == null) return LimousineCustomerIntentKind.quoteRequest;
  switch (limousinePublishedPricingModeOf(offer)) {
    case LimousinePublishedPricingMode.exactFixed:
    case LimousinePublishedPricingMode.hourly:
    case LimousinePublishedPricingMode.package:
      return LimousineCustomerIntentKind.bookingRequest;
    case LimousinePublishedPricingMode.quoteRequired:
    case LimousinePublishedPricingMode.fromPrice:
      return LimousineCustomerIntentKind.quoteRequest;
  }
}

