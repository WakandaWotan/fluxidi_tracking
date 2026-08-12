// FLUXIDI-TELLERS-PRICE-SOT
//
// Presentation-only resolver for the Tellers bottom "Geschatte ritprijs" /
// fixed-price summary. Reuses ordinary Navigatie estimate / fixed-price
// inputs — never invents a second fare engine and never substitutes the
// live meter Tarief for a street route estimate.

/// Inputs for [resolveTellersEstimatedRidePriceText].
class TellersEstimatedRidePriceInput {
  const TellersEstimatedRidePriceInput({
    required this.usesFixedPrice,
    required this.fixedPriceText,
    required this.estimatedFare,
    required this.currency,
    required this.isLoading,
    required this.formatAmount,
    required this.loadingText,
    required this.unavailableText,
  });

  final bool usesFixedPrice;

  /// Authoritative fixed booking price text (same as Tellers Tarief when fixed).
  final String fixedPriceText;

  /// Latched `/quote` estimate (same field ordinary DirectRideEstimatePanel uses).
  final double? estimatedFare;
  final String currency;
  final bool isLoading;
  final String Function(double amount, String currency) formatAmount;
  final String loadingText;
  final String unavailableText;
}

/// Resolve the Tellers bottom-card amount text.
///
/// Precedence:
/// 1. Fixed-price rides → [TellersEstimatedRidePriceInput.fixedPriceText]
/// 2. Loading with no latched estimate → loading copy
/// 3. Valid latched calculator estimate → formatted estimate
/// 4. Otherwise → honest unavailable (never live meter / start fare)
String resolveTellersEstimatedRidePriceText(
  TellersEstimatedRidePriceInput input,
) {
  if (input.usesFixedPrice) {
    return input.fixedPriceText;
  }
  if (input.isLoading && input.estimatedFare == null) {
    return input.loadingText;
  }
  final estimate = input.estimatedFare;
  if (estimate != null && estimate.isFinite && estimate > 0) {
    return input.formatAmount(estimate, input.currency);
  }
  return input.unavailableText;
}
