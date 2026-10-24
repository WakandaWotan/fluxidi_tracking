import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_preference.dart';

void main() {
  Map<String, dynamic> car(String id, {bool active = true}) => {
    'vehicle_id': id,
    'name': id,
    'is_active': active,
    'passenger_capacity': 4,
    'luggage_capacity': 3,
    'service_capacity': {
      'airport': {'passengers': 3, 'baggage': 3},
      'taxi': {'passengers': 4, 'baggage': 3},
    },
  };
  test(
    'quote preference accepts offline fleet without driver and keeps airport capacities',
    () {
      final offers = customerQuoteVehiclePreferences(
        [
          car('car'),
          car('car'),
          car('inactive', active: false),
          {...car('taxi_only'), 'airport_enabled': false},
        ],
        passengers: 3,
        baggage: 3,
        service: 'airport',
      );
      expect(offers.map((x) => x.vehicleId), ['car']);
      expect(offers.single.available, isTrue);
      expect(offers.single.driver, isNull);
      expect(offers.single.passengerSeats, 3);
      expect(offers.single.baggageCapacity, 3);
    },
  );
  test('too many passengers or bags cannot select a preference', () {
    for (final counts in [(4, 0), (1, 4)]) {
      final offer = customerQuoteVehiclePreferences(
        [car('car')],
        passengers: counts.$1,
        baggage: counts.$2,
        service: 'airport',
      ).single;
      expect(offer.available, isFalse);
      expect(offer.reason, isNotEmpty);
    }
    expect(
      customerQuoteVehiclePreferences(
        [car('car')],
        passengers: 4,
        baggage: 3,
        service: 'taxi',
      ).single.available,
      isTrue,
    );
  });
  test(
    'offerte email preserves full summary and Unicode without accidental query parameters',
    () {
      const summary =
          'Ophalen: A & B\nVoertuig: Tesla\nPassagiers: 3\nBagage: 2\nNaam: André + Tom';
      final uri = customerQuoteEmailUri('booking@example.com', summary);
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'booking@example.com');
      expect(uri.queryParameters['body'], summary);
      expect(uri.queryParameters['subject'], 'Offerteaanvraag taxi');
      expect(uri.queryParameters.length, 2);
    },
  );
}
