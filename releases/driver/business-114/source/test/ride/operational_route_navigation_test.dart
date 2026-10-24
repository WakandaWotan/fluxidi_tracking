import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/planned_booking_canonical_destination.dart';
import 'package:fluxidi_tracking/ride/operational_route.dart';

void main() {
  final details = <String, dynamic>{
    'status': 'IN_PROGRESS',
    'pickup_lat': 51.1,
    'pickup_lon': 4.1,
    'dropoff_lat': 51.2,
    'dropoff_lon': 4.2,
    'operational_route': {
      'destination': {'address': 'Nieuw adres', 'lat': 51.3, 'lng': 4.3},
      'expected_end_iso': '2026-10-03T12:00:00Z',
    },
  };
  test(
    'navigation follows the changed destination while pickup and quoted route stay intact',
    () {
      final result = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'B',
        details: details,
        fromLabel: 'Ophaal',
        toLabel: 'Offerte',
      );
      expect(result.pickup.latitude, 51.1);
      expect(result.pickup.longitude, 4.1);
      expect(result.dropoff.latitude, 51.3);
      expect(result.dropoff.longitude, 4.3);
      expect(result.dropoff.address, 'Nieuw adres');
      expect(details['dropoff_lat'], 51.2);
    },
  );
  test('a completed or separate leg cannot inherit a running destination', () {
    for (final patch in [
      {'status': 'COMPLETED', 'customer_tracking_phase': 'in_progress'},
      {'operational_route': null},
    ]) {
      final result = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'B:RETURN',
        details: {...details, ...patch},
        toLabel: 'Offerte',
      );
      expect(result.dropoff.latitude, 51.2);
      expect(result.dropoff.address, 'Offerte');
    }
  });
  test(
    'late original tracking address cannot rewind the running destination',
    () {
      expect(
        operationalHydratedDestination(details, 'Offerte', 'Nieuw adres'),
        'Nieuw adres',
      );
      expect(details['dropoff_lat'], 51.2);
    },
  );
  test(
    'hydration of completed or unchanged rides keeps the original behavior',
    () {
      expect(
        operationalHydratedDestination(
          {...details, 'status': 'COMPLETED'},
          'Offerte',
          'Nieuw adres',
        ),
        'Offerte',
      );
      expect(
        operationalHydratedDestination({}, null, 'Huidig adres'),
        'Huidig adres',
      );
    },
  );
}
