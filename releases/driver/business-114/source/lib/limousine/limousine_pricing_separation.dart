// LIMOUSINE-MARKETPLACE-P0 (addendum) — pricing separation contract.
//
// Pure, testable rules that keep Limousine pricing authoritative and separate
// from taxi/airport pricing. No route calculation happens here; the shared
// engine seam (worker `routeFromTextsWithStopsDetailed` / `POST /quote` /
// `calcPrice` / `resolveAirportFixedFare`) remains the single calculator.
//
// Hard requirements enforced:
//   * never fall back from missing Limousine pricing to ordinary taxi pricing;
//   * never infer a customer price;
//   * never use the street-ride meter to finalize a scheduled Limousine ride;
//   * never let a taxi fixed fare overwrite a Limousine fixed fare (or vice
//     versa) — fixed fares are keyed by service category;
//   * missing/stale/contradictory/incomplete pricing fails closed;
//   * no eligible price => manual quote or unavailable.

import 'limousine_dimensions.dart';

/// What authoritative Limousine pricing inputs are available for a request.
/// Every field defaults to the fail-closed value (nothing available).
class LimousinePricingInputs {
  const LimousinePricingInputs({
    this.hasMatchingLimousineFixedFare = false,
    this.hasConfiguredHourlyOrPackagePrice = false,
    this.hasLimousineDistanceTimeProfile = false,
    this.manualQuoteAllowed = false,
    this.pricingIsStale = false,
    this.pricingIsContradictory = false,
  });

  /// Step 1: a Limousine fixed route/airport fare matched for this exact
  /// company + category + class + journey + direction + zone/radius (+ dates).
  final bool hasMatchingLimousineFixedFare;

  /// Step 2: a configured Limousine hourly/package price for this request.
  final bool hasConfiguredHourlyOrPackagePrice;

  /// Step 3: an authoritative Limousine distance/time pricing profile for the
  /// SELECTED company (never the taxi profile, never another company).
  final bool hasLimousineDistanceTimeProfile;

  /// Step 4: manual human quote is permitted for this company/journey.
  final bool manualQuoteAllowed;

  /// Any resolved input is stale (fails closed).
  final bool pricingIsStale;

  /// Inputs contradict each other (fails closed).
  final bool pricingIsContradictory;
}

class LimousinePricingResolution {
  const LimousinePricingResolution({
    required this.mode,
    required this.category,
    this.failedClosed = false,
  });

  final LimousinePricingMode mode;
  final LimousineServiceCategory category;

  /// True when incomplete/stale/contradictory inputs forced `unavailable`.
  final bool failedClosed;

  bool get requiresManualQuote => mode == LimousinePricingMode.manualQuote;
  bool get isUnavailable => mode == LimousinePricingMode.unavailable;
  bool get hasResolvedPrice =>
      mode == LimousinePricingMode.fixedRouteOrAirportFare ||
      mode == LimousinePricingMode.hourlyOrPackage ||
      mode == LimousinePricingMode.limousineDistanceTime;
}

/// Authoritative future resolution order for a Limousine request:
///   1. Limousine fixed route/airport fare match
///   2. Configured Limousine hourly/package price
///   3. Limousine-specific distance/time calc (selected company profile only)
///   4. Manual quote, else unavailable
///
/// Never returns a taxi pricing outcome. Stale/contradictory inputs fail
/// closed to `unavailable`.
LimousinePricingResolution resolveLimousinePricingMode(
  LimousinePricingInputs inputs, {
  LimousineServiceCategory category = LimousineServiceCategory.limousine,
}) {
  // Fail closed on stale or contradictory pricing before selecting any mode.
  if (inputs.pricingIsStale || inputs.pricingIsContradictory) {
    return LimousinePricingResolution(
      mode: LimousinePricingMode.unavailable,
      category: category,
      failedClosed: true,
    );
  }
  if (inputs.hasMatchingLimousineFixedFare) {
    return LimousinePricingResolution(
      mode: LimousinePricingMode.fixedRouteOrAirportFare,
      category: category,
    );
  }
  if (inputs.hasConfiguredHourlyOrPackagePrice) {
    return LimousinePricingResolution(
      mode: LimousinePricingMode.hourlyOrPackage,
      category: category,
    );
  }
  if (inputs.hasLimousineDistanceTimeProfile) {
    return LimousinePricingResolution(
      mode: LimousinePricingMode.limousineDistanceTime,
      category: category,
    );
  }
  if (inputs.manualQuoteAllowed) {
    return LimousinePricingResolution(
      mode: LimousinePricingMode.manualQuote,
      category: category,
    );
  }
  return LimousinePricingResolution(
    mode: LimousinePricingMode.unavailable,
    category: category,
    failedClosed: true,
  );
}

/// A Limousine request must NEVER fall back to taxi pricing. This is always
/// true for the limousine category and encodes the hard prohibition so callers
/// and tests can assert it explicitly.
bool limousinePricingForbidsTaxiFallback(LimousineServiceCategory category) {
  return category == LimousineServiceCategory.limousine;
}

/// A fixed-fare rule may only apply to a request of the SAME service category.
/// A taxi fixed fare can never match/overwrite a limousine request and a
/// limousine fixed fare can never alter taxi/airport pricing.
bool fixedFareRuleAppliesToRequest({
  required LimousineServiceCategory ruleCategory,
  required LimousineServiceCategory requestCategory,
}) {
  return ruleCategory == requestCategory;
}

/// True when two fixed-fare rules are kept distinct because their service
/// categories differ (e.g. taxi airport fare vs executive limousine airport
/// fare for the same journey). Neither may overwrite the other.
bool fixedFaresAreDistinctByCategory({
  required LimousineServiceCategory a,
  required LimousineServiceCategory b,
}) {
  return a != b;
}

/// The street-ride meter is only for taxi street rides. Finalizing a SCHEDULED
/// limousine booking from the street meter is forbidden.
bool isStreetMeterFinalizationForbidden({
  required LimousineServiceCategory category,
  required bool isScheduled,
}) {
  if (category == LimousineServiceCategory.limousine && isScheduled) {
    return true;
  }
  return false;
}

/// Convenience guard for the scheduled-limousine finalization path.
bool canFinalizeWithStreetMeter({
  required LimousineServiceCategory category,
  required bool isScheduled,
}) {
  return !isStreetMeterFinalizationForbidden(
    category: category,
    isScheduled: isScheduled,
  );
}
