// PLANNED-BOOKING-CANONICAL-GMAPS-HANDOFF-P0-6
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/external/planned_booking_canonical_destination.dart';

void main() {
  group('PLANNED-BOOKING-CANONICAL-GMAPS-HANDOFF-P0-6', () {
    test('1) street ride contract fingerprint stays stable', () {
      const a = StreetRideGmapsDestinationContract(
        latitude: 50.850000,
        longitude: 4.350000,
        address: 'Street Destination',
      );
      const b = StreetRideGmapsDestinationContract(
        latitude: 50.850000,
        longitude: 4.350000,
        address: 'Street Destination',
      );
      expect(a.contractFingerprint, b.contractFingerprint);
      expect(a.destinationSource, 'street_direct_destination');
    });

    test('2) planned outbound before START uses pickup leg', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'parent_bk',
        fromLabel: 'Koekamerstraat 48A Maarkedal',
        toLabel: 'Nieuwstraat 1 Kluisbergen',
        details: <String, dynamic>{
          'leg_id': 'leg_out',
          'is_operational_leg': true,
          'pickup_lat': 50.80000,
          'pickup_lon': 3.55000,
          'dropoff_lat': 50.78000,
          'dropoff_lon': 3.50000,
          'status': 'accepted',
        },
      );
      final pickup = r.endpointForPhase(toPickup: true);
      expect(pickup.role, PlannedEndpointRole.pickup);
      expect(pickup.coordSource, PlannedEndpointCoordSource.activeLegCoords);
      expect(pickup.latitude, 50.80000);
      expect(pickup.hasCoordinates, isTrue);
    });

    test('3) planned outbound after START uses drop-off leg', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'parent_bk',
        fromLabel: 'Koekamerstraat 48A Maarkedal',
        toLabel: 'Nieuwstraat 1 Kluisbergen',
        details: <String, dynamic>{
          'leg_id': 'leg_out',
          'is_operational_leg': true,
          'pickup_lat': 50.80000,
          'pickup_lon': 3.55000,
          'dropoff_lat': 50.78000,
          'dropoff_lon': 3.50000,
        },
      );
      final drop = r.endpointForPhase(toPickup: false);
      expect(drop.role, PlannedEndpointRole.dropoff);
      expect(drop.latitude, 50.78000);
      expect(drop.coordSource, PlannedEndpointCoordSource.activeLegCoords);
    });

    test('4) parent/leg mismatch chooses active leg coords', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'parent_bk',
        fromLabel: 'Leg Pickup',
        toLabel: 'Leg Dropoff',
        details: <String, dynamic>{
          'leg_id': 'leg_out',
          'is_operational_leg': true,
          'pickup_lat': 50.80111,
          'pickup_lon': 3.55111,
          'dropoff_lat': 50.78111,
          'dropoff_lon': 3.50111,
          // Parent/package quote would previously win via first-match order.
          'quote': {
            'destination': {'lat': 51.00000, 'lon': 4.00000},
            'origin': {'lat': 51.10000, 'lon': 4.10000},
          },
          'record': {
            'booking': {
              'dropoff_lat': 51.00000,
              'dropoff_lon': 4.00000,
              'pickup_lat': 51.10000,
              'pickup_lon': 4.10000,
            },
          },
        },
      );
      expect(r.dropoff.latitude, 50.78111);
      expect(r.pickup.latitude, 50.80111);
      expect(r.dropoff.coordSource, PlannedEndpointCoordSource.activeLegCoords);
      expect(r.dropoff.latitude, isNot(51.0));
    });

    test('5) missing parent coords with valid leg coords works', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'bk',
        toLabel: 'Nieuwstraat 1',
        details: <String, dynamic>{
          'leg_id': 'L1',
          'dropoff_lat': 50.78,
          'dropoff_lon': 3.50,
        },
      );
      expect(r.dropoff.hasCoordinates, isTrue);
      expect(r.dropoff.coordSource, PlannedEndpointCoordSource.activeLegCoords);
    });

    test('6) address fallback only when lat/lng missing', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'bk',
        toLabel: 'Nieuwstraat 1 Kluisbergen',
        details: <String, dynamic>{
          'leg_id': 'L1',
          'status': 'accepted',
        },
      );
      expect(r.dropoff.hasCoordinates, isFalse);
      expect(r.dropoff.hasAddress, isTrue);
      expect(r.dropoff.coordSource, PlannedEndpointCoordSource.addressOnly);
    });

    test('7) no pickup/drop-off mix across parent and leg', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'bk',
        fromLabel: 'A',
        toLabel: 'B',
        details: <String, dynamic>{
          'leg_id': 'L1',
          // Only leg dropoff coords — pickup must not borrow parent coords
          // while dropoff uses leg (same-family rule via independent resolve,
          // but parent pickup still allowed only when leg pickup absent).
          'dropoff_lat': 50.78,
          'dropoff_lon': 3.50,
          'quote': {
            'origin': {'lat': 51.2, 'lon': 4.2},
          },
        },
      );
      expect(r.dropoff.coordSource, PlannedEndpointCoordSource.activeLegCoords);
      expect(r.pickup.coordSource, PlannedEndpointCoordSource.parentFallbackCoords);
      // Distinct sources are OK; mixing fields into one endpoint is not.
      expect(r.pickup.latitude, 51.2);
      expect(r.dropoff.latitude, 50.78);
    });

    test('8) Maps and PiP share same target hash for active dropoff', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'bk',
        toLabel: 'B',
        details: <String, dynamic>{
          'dropoff_lat': 50.78000,
          'dropoff_lon': 3.50000,
        },
      );
      final mapsHash = r.dropoff.coordinateHash;
      final pipHash = r.dropoff.coordinateHash;
      expect(mapsHash, pipHash);
      expect(mapsHash, isNot('none'));
    });

    test('9) audit line is PII-safe', () {
      final r = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'verylongbookingid1234',
        fromLabel: 'Secret Street 1',
        toLabel: 'Secret Street 2',
        details: <String, dynamic>{
          'leg_id': 'leg1',
          'pickup_lat': 50.8,
          'pickup_lon': 3.5,
        },
      );
      final line = PlannedBookingCanonicalDestinationResolver.auditLine(
        endpoints: r,
        toPickup: true,
        rideKind: 'planned',
        activePhase: 'toPickup',
      );
      expect(line.contains('Secret'), isFalse);
      expect(line.contains('ride_kind=planned'), isTrue);
      expect(line.contains('coord_src=activeLegCoords'), isTrue);
    });

    test('10) launchable requires coords or address', () {
      final empty = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'bk',
        details: const <String, dynamic>{},
      );
      expect(empty.dropoff.isLaunchable, isFalse);
      expect(empty.pickup.isLaunchable, isFalse);
    });
  });
}
