// LIMOUSINE-MARKETPLACE-P0 (addendum) — typed transport dimensions.
//
// These four dimensions are kept SEPARATE and are never collapsed into one
// boolean or one generic service string. They describe the shared ride engine
// (CalculatorPage + POST /quote), not a second booking engine.
//
//   1. service category  — taxi vs limousine
//   2. journey type      — point-to-point / airport / hotel / event / hourly
//   3. vehicle class     — authoritative configurable class id (never brand)
//   4. pricing mode      — fixed / hourly / distance-time / manual / unavailable

import 'limousine_service_capability.dart';

/// Dimension 1: transport/service category.
enum LimousineServiceCategory { taxi, limousine }

/// Dimension 2: journey type. Limousine and airport transfer are NOT mutually
/// exclusive; a limousine may run an airport/hotel/event/hourly journey.
enum LimousineJourneyType {
  pointToPoint,
  airportTransfer,
  hotelTransfer,
  eventTransfer,
  hourlyPackage,
}

/// Dimension 4: pricing mode. `unavailable` is a terminal fail-closed outcome
/// (distinct from `manualQuote`, which is a permitted human-priced path).
enum LimousinePricingMode {
  fixedRouteOrAirportFare,
  hourlyOrPackage,
  limousineDistanceTime,
  manualQuote,
  unavailable,
}

LimousineServiceCategory? normalizeServiceCategory(String? raw) {
  final token = normalizePublicServiceToken(raw);
  if (token.isEmpty) return null;
  if (token == 'taxi' || token == 'taxi_vvb')
    return LimousineServiceCategory.taxi;
  if (isLimousineServiceToken(token)) return LimousineServiceCategory.limousine;
  return null;
}

LimousineJourneyType? normalizeJourneyType(String? raw) {
  final token = normalizePublicServiceToken(raw);
  if (token.isEmpty) return null;
  switch (token) {
    case 'point_to_point':
    case 'pointtopoint':
    case 'p2p':
    case 'direct':
      return LimousineJourneyType.pointToPoint;
    case 'airport':
    case 'airport_transfer':
    case 'airport_service':
      return LimousineJourneyType.airportTransfer;
    case 'hotel':
    case 'hotel_transfer':
    case 'hotel_bnb_pickup':
      return LimousineJourneyType.hotelTransfer;
    case 'event':
    case 'event_transfer':
    case 'event_mobility':
      return LimousineJourneyType.eventTransfer;
    case 'hourly':
    case 'hourly_package':
    case 'package':
      return LimousineJourneyType.hourlyPackage;
    default:
      return null;
  }
}

LimousinePricingMode? normalizePricingMode(String? raw) {
  final token = normalizePublicServiceToken(raw);
  if (token.isEmpty) return null;
  switch (token) {
    case 'fixed':
    case 'fixed_fare':
    case 'fixed_route':
    case 'fixed_route_or_airport_fare':
    case 'airport_fixed_fare':
      return LimousinePricingMode.fixedRouteOrAirportFare;
    case 'hourly':
    case 'package':
    case 'hourly_or_package':
      return LimousinePricingMode.hourlyOrPackage;
    case 'distance_time':
    case 'limousine_distance_time':
    case 'route_calc':
      return LimousinePricingMode.limousineDistanceTime;
    case 'manual':
    case 'manual_quote':
      return LimousinePricingMode.manualQuote;
    case 'unavailable':
      return LimousinePricingMode.unavailable;
    default:
      return null;
  }
}

/// Dimension 3: authoritative, configurable vehicle/service class reference.
///
/// The class id must come from an authoritative configuration (the company's
/// service-class catalog). It is NEVER inferred from a vehicle brand, model,
/// or a display name such as "Mercedes", "executive", or "premium".
class LimousineServiceClassRef {
  const LimousineServiceClassRef._(this.id);

  final String id;

  bool get isValid => id.isNotEmpty;

  static const LimousineServiceClassRef none = LimousineServiceClassRef._('');

  /// Builds a class ref from an AUTHORITATIVE configured id only.
  static LimousineServiceClassRef fromAuthoritativeId(String? configuredId) {
    return LimousineServiceClassRef._(
      normalizePublicServiceToken(configuredId),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LimousineServiceClassRef && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LimousineServiceClassRef($id)';
}

/// Words that must never, on their own, resolve a vehicle/service class.
/// Class assignment is authoritative configuration, not string inference.
const Set<String> kForbiddenClassInferenceTokens = <String>{
  'executive',
  'premium',
  'luxury',
  'vip',
  'business',
  'mercedes',
  'bmw',
  'audi',
  'tesla',
  'sclass',
  's_class',
  'limo',
  'limousine',
};

/// Guard: brand/name-derived class inference is forbidden. Always returns
/// [LimousineServiceClassRef.none] so callers cannot accidentally derive a
/// class from marketing words or a vehicle brand.
LimousineServiceClassRef serviceClassFromBrandOrName(String? _) {
  return LimousineServiceClassRef.none;
}

/// True when [token] is only a marketing/brand word and must not resolve a
/// service class by itself.
bool isForbiddenClassInferenceToken(String? token) {
  return kForbiddenClassInferenceTokens.contains(
    normalizePublicServiceToken(token),
  );
}
