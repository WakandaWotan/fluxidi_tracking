import 'fluxidi_fare_rounding.dart';

/// Street-ride estimate from an already calculated route and the company tariff.
///
/// Returns null when the route distance or duration is missing. Never uses the
/// live meter, and never invents a route.
double? streetRideEstimateFromKnownRoute({
  required double? routeKm,
  required int? routeDurationSec,
  required double baseFare,
  required double pricePerKm,
  required double pricePerMinute,
  required double minimumFare,
  required double vatRate,
  required String vatMode,
}) {
  if (routeKm == null || !routeKm.isFinite || routeKm <= 0) return null;
  if (routeDurationSec == null || routeDurationSec <= 0) return null;
  if (!baseFare.isFinite ||
      !pricePerKm.isFinite ||
      !pricePerMinute.isFinite ||
      !minimumFare.isFinite ||
      !vatRate.isFinite) {
    return null;
  }
  final minutes = routeDurationSec / 60.0;
  var raw = baseFare + (routeKm * pricePerKm) + (minutes * pricePerMinute);
  if (minimumFare > raw) raw = minimumFare;
  final mode = vatMode.trim().toLowerCase();
  if (mode == 'excl') {
    raw = raw * (1.0 + vatRate.clamp(0.0, 1.0));
  }
  if (!raw.isFinite || raw < 0) return null;
  return roundFareEuroToNearestTenCents(raw) ?? raw;
}
