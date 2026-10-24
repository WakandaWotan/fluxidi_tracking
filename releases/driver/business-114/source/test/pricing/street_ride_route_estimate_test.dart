import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_remaining_distance_truth.dart';
import 'package:fluxidi_tracking/pricing/street_ride_route_estimate.dart';

void main() {
  group('street ride route estimate', () {
    test('A valid destination route uses tariff, not the live meter', () {
      final estimate = streetRideEstimateFromKnownRoute(
        routeKm: 10,
        routeDurationSec: 1200,
        baseFare: 3.5,
        pricePerKm: 2.0,
        pricePerMinute: 0.5,
        minimumFare: 6,
        vatRate: 0.06,
        vatMode: 'incl',
      );
      // 3.50 + 20.00 + 10.00 = 33.50, not a live meter of 5.30.
      expect(estimate, 33.5);
      expect(estimate, isNot(5.3));
    });

    test('B no route metrics means no estimate', () {
      expect(
        streetRideEstimateFromKnownRoute(
          routeKm: null,
          routeDurationSec: null,
          baseFare: 3.5,
          pricePerKm: 2,
          pricePerMinute: 0.5,
          minimumFare: 6,
          vatRate: 0.06,
          vatMode: 'incl',
        ),
        isNull,
      );
    });

    test('C route failure without distance stays null', () {
      expect(
        streetRideEstimateFromKnownRoute(
          routeKm: 0,
          routeDurationSec: 0,
          baseFare: 3.5,
          pricePerKm: 2,
          pricePerMinute: 0.5,
          minimumFare: 6,
          vatRate: 0.06,
          vatMode: 'incl',
        ),
        isNull,
      );
    });

    test('D a recovered route replaces the previous amount', () {
      final first = streetRideEstimateFromKnownRoute(
        routeKm: 4,
        routeDurationSec: 600,
        baseFare: 3,
        pricePerKm: 2,
        pricePerMinute: 0,
        minimumFare: 0,
        vatRate: 0.21,
        vatMode: 'incl',
      );
      final recovered = streetRideEstimateFromKnownRoute(
        routeKm: 8,
        routeDurationSec: 900,
        baseFare: 3,
        pricePerKm: 2,
        pricePerMinute: 0,
        minimumFare: 0,
        vatRate: 0.21,
        vatMode: 'incl',
      );
      expect(first, 11.0);
      expect(recovered, 19.0);
      expect(recovered, isNot(first));
    });

    test('F the draft estimate is not the stop price', () {
      final draft = streetRideEstimateFromKnownRoute(
        routeKm: 10,
        routeDurationSec: 1200,
        baseFare: 3.5,
        pricePerKm: 2.0,
        pricePerMinute: 0.5,
        minimumFare: 6,
        vatRate: 0.06,
        vatMode: 'incl',
      );
      const liveMeterAtStop = 5.30;
      expect(draft, isNot(liveMeterAtStop));
      expect(liveMeterAtStop, 5.30);
    });

    test('excl VAT is added once on the route tariff', () {
      final estimate = streetRideEstimateFromKnownRoute(
        routeKm: 10,
        routeDurationSec: 600,
        baseFare: 10,
        pricePerKm: 1,
        pricePerMinute: 0,
        minimumFare: 0,
        vatRate: 0.21,
        vatMode: 'excl',
      );
      expect(estimate, 24.2);
    });
  });

  group('ETA and KM from the same route', () {
    test('known route shows ETA and KM before a nav target is bound', () {
      final truth = resolveNavRemainingDistanceTruth(
        activeTargetValid: false,
        activeRouteId: null,
        progressRouteId: null,
        routeLengthMeters: 12500,
        distanceAlongRouteMeters: null,
        fallbackRemainingKmFromOdometer: 12.5,
        routeDurationSec: 900,
        kmDriven: 0,
        trackingCountdownStarted: false,
      );
      expect(truth.routeReady, isTrue);
      expect(formatNavRemainingKmText(truth), '12.5');
      expect(formatNavEtaText(truth), '15 min');
    });

    test('missing route still leaves ETA and KM empty', () {
      final truth = resolveNavRemainingDistanceTruth(
        activeTargetValid: false,
        activeRouteId: null,
        progressRouteId: null,
        routeLengthMeters: null,
        distanceAlongRouteMeters: null,
        fallbackRemainingKmFromOdometer: null,
        routeDurationSec: null,
        kmDriven: 0,
        trackingCountdownStarted: false,
      );
      expect(truth.routeReady, isFalse);
      expect(formatNavRemainingKmText(truth), isEmpty);
      expect(formatNavEtaText(truth), isEmpty);
    });
  });
}
