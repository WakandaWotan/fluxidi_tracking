import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_assigned_driver.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_company_vehicles.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';

void main() {
  final tesla = <String, dynamic>{
    'vehicle_id': 'vh_tesla',
    'name': 'Tesla',
    'vehicle_type': 'sedan',
    'passenger_capacity': 3,
    'assigned_driver_id': 'drv_chris',
  };
  final cadillac = <String, dynamic>{
    'vehicle_id': 'vh_cadillac',
    'name': 'Cadillac',
    'vehicle_type': 'sedan',
    'passenger_capacity': 4,
    'assigned_driver_id': 'drv_wotan',
  };
  final chris = <String, dynamic>{
    'driver_id': 'drv_chris',
    'first_name': 'Christophe',
    'display_name': 'Christophe Vanroeghem',
    'preferred_vehicle_id': 'vh_tesla',
    'weekly_roster': <String, dynamic>{
      'explicitly_set': true,
      'days': <String, dynamic>{
        'mon': <Map<String, dynamic>>[
          <String, dynamic>{'start': '08:00', 'end': '16:00'},
        ],
      },
    },
  };
  final wotan = <String, dynamic>{
    'driver_id': 'drv_wotan',
    'first_name': 'Wotan',
    'display_name': 'Wotan',
    'preferred_vehicle_id': 'vh_cadillac',
    'weekly_roster': <String, dynamic>{
      'explicitly_set': true,
      'days': <String, dynamic>{
        'thu': <Map<String, dynamic>>[
          <String, dynamic>{'start': '22:00', 'end': '06:00'},
        ],
      },
    },
  };

  test('two sedans stay two cards', () {
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[tesla, cadillac],
      passengers: 1,
    );
    expect(offers.map((offer) => offer.vehicleId).toList(), <String>[
      'vh_tesla',
      'vh_cadillac',
    ]);
  });

  test('uses stored passenger seats and does not invent a default', () {
    expect(
      customerBookingVehicleOfferCapacityLabel(
        offer: CustomerBookingVehicleOffer(
          vehicle: tesla,
          passengerSeats: 3,
        ),
        language: AppLanguage.nl,
      ),
      '3 passagiers',
    );
    expect(
      customerBookingVehicleOfferCapacityLabel(
        offer: const CustomerBookingVehicleOffer(
          vehicle: <String, dynamic>{'vehicle_id': 'vh_x'},
        ),
        language: AppLanguage.nl,
      ),
      'Capaciteit onbekend',
    );
  });

  test('daytime Wotan night shift does not make Cadillac bookable', () {
    final thursdayAfternoon = DateTime.utc(2026, 9, 17, 11, 0);
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[cadillac],
      drivers: <Map<String, dynamic>>[wotan],
      passengers: 1,
      pickupUtc: thursdayAfternoon,
      availabilityResolved: true,
      availableVehicleIds: const <String>{},
      unavailableVehicleIds: const <String>{'vh_cadillac'},
      unavailableReasons: const <String, String>{
        'vh_cadillac': 'assignment_driver_outside_hours',
      },
    );
    expect(offers.single.vehicleId, 'vh_cadillac');
    expect(offers.single.available, isFalse);
  });

  test('availability load failure is not treated as available', () {
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[cadillac],
      drivers: <Map<String, dynamic>>[wotan],
      passengers: 1,
      pickupUtc: DateTime.utc(2026, 9, 17, 11, 0),
      availabilityFailed: true,
    );
    expect(offers.single.available, isFalse);
    expect(offers.single.reason, 'availability_load_failed');
  });

  test('empty linked drivers do not grant daytime availability', () {
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[cadillac],
      drivers: const <Map<String, dynamic>>[],
      passengers: 1,
      pickupUtc: DateTime.utc(2026, 9, 17, 11, 0),
    );
    expect(offers.single.available, isFalse);
  });

  test('server unavailable id hides Tesla while Cadillac stays bookable', () {
    final night = DateTime.utc(2026, 9, 17, 20, 0); // Thursday 22:00 Brussels
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[tesla, cadillac],
      drivers: <Map<String, dynamic>>[chris, wotan],
      passengers: 1,
      pickupUtc: night,
      availableVehicleIds: const <String>{'vh_cadillac'},
      unavailableVehicleIds: const <String>{'vh_tesla'},
    );
    expect(
      offers.firstWhere((offer) => offer.vehicleId == 'vh_cadillac').available,
      isTrue,
    );
    expect(
      offers.firstWhere((offer) => offer.vehicleId == 'vh_tesla').available,
      isFalse,
    );
  });

  test('three sequential drivers still produce one vehicle card', () {
    final vehicle = <String, dynamic>{
      'vehicle_id': 'vh_shared',
      'name': 'Gedeelde auto',
      'passenger_capacity': 3,
    };
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[vehicle, vehicle, vehicle],
      passengers: 1,
    );
    expect(offers, hasLength(1));
    expect(offers.single.vehicleId, 'vh_shared');
  });

  test('Party Limo seats stay on that vehicle_id', () {
    final party = <String, dynamic>{
      'vehicle_id': 'vh_party',
      'name': 'Party Limo',
      'passenger_capacity': 16,
    };
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[tesla, party],
      passengers: 1,
    );
    expect(
      offers.firstWhere((offer) => offer.vehicleId == 'vh_tesla').passengerSeats,
      3,
    );
    expect(
      offers.firstWhere((offer) => offer.vehicleId == 'vh_party').passengerSeats,
      16,
    );
    expect(
      customerBookingVehicleOfferCapacityLabel(
        offer: CustomerBookingVehicleOffer(vehicle: tesla, passengerSeats: 3),
        language: AppLanguage.en,
      ),
      '3 passengers',
    );
    expect(
      customerBookingVehicleOfferTitle(
        offer: CustomerBookingVehicleOffer(vehicle: tesla, passengerSeats: 3),
        language: AppLanguage.nl,
      ),
      'Tesla',
    );
  });

  test('incomplete ride keeps photos from looking like a roster block', () {
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[tesla],
      drivers: <Map<String, dynamic>>[chris],
      passengers: 1,
      pickupUtc: DateTime.utc(2026, 9, 17, 12, 0),
      rideReady: false,
      durationKnown: false,
    );
    expect(offers.single.available, isFalse);
    expect(offers.single.reason, 'need_ride');
    expect(
      customerBookingVehicleOfferState(
        hasCompany: true,
        rideReady: false,
        loading: false,
        loadFailed: false,
        offers: offers,
      ),
      CustomerBookingVehicleOfferState.incompleteRide,
    );
    expect(customerBookingVehicleReasonIsPending('need_ride'), isTrue);
  });

  test('missing duration is not a final unavailable mark', () {
    final mondayAfternoon = DateTime.utc(2026, 9, 14, 12, 0);
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[tesla],
      drivers: <Map<String, dynamic>>[chris],
      passengers: 1,
      pickupUtc: mondayAfternoon,
      durationKnown: false,
      rideReady: true,
    );
    expect(offers.single.reason, 'need_duration');
    expect(offers.single.available, isFalse);
    expect(customerBookingVehicleReasonIsPending('need_duration'), isTrue);
  });

  test('proven start-time roster block stays visible without duration', () {
    final thursdayAfternoon = DateTime.utc(2026, 9, 17, 11, 0);
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[cadillac],
      drivers: <Map<String, dynamic>>[wotan],
      passengers: 1,
      pickupUtc: thursdayAfternoon,
      durationKnown: false,
      rideReady: true,
    );
    expect(offers.single.reason, 'assignment_driver_outside_hours');
    expect(offers.single.available, isFalse);
    expect(customerBookingVehicleReasonIsPending(offers.single.reason), isFalse);
  });

  test('availability driver record is used when the profile omits that id', () {
    final snapshot = parseCustomerBookingAvailability(
      <String, dynamic>{
        'ok': true,
        'vehicles': <Map<String, dynamic>>[
          <String, dynamic>{
            'vehicle_id': 'vh_cadillac',
            'available': true,
            'driver_id': 'drv_night',
            'driver': <String, dynamic>{
              'driver_id': 'drv_night',
              'first_name': 'Night',
            },
          },
        ],
      },
    );
    expect(snapshot.driverIds['vh_cadillac'], 'drv_night');
    expect(snapshot.drivers, isNotEmpty);
    final offers = customerBookingVehicleOffers(
      vehicles: <Map<String, dynamic>>[cadillac],
      drivers: snapshot.drivers,
      passengers: 1,
      pickupUtc: DateTime.utc(2026, 9, 18, 0, 0),
      durationMin: 40,
      durationKnown: true,
      rideReady: true,
      availableVehicleIds: snapshot.availableIds,
      proposedDriverIds: snapshot.driverIds,
      availabilityResolved: true,
    );
    expect(offers.single.available, isTrue);
    expect(offers.single.driverId, 'drv_night');
    final proposed = customerBookingProposedDriverFromRecord(offers.single.driver);
    expect(proposed.firstName, 'Night');
    expect(proposed.assigned, isFalse);
  });

  test('availability response without vehicles is a load failure', () {
    final snapshot = parseCustomerBookingAvailability(
      <String, dynamic>{'ok': true, 'profile': <String, dynamic>{}},
    );
    expect(snapshot.loadFailed, isTrue);
    expect(snapshot.resolved, isFalse);
  });

  test('incomplete ride is not a final no-vehicles conclusion', () {
    expect(
      customerBookingVehicleOfferState(
        hasCompany: true,
        rideReady: false,
        loading: false,
        loadFailed: false,
        offers: const <CustomerBookingVehicleOffer>[],
      ),
      CustomerBookingVehicleOfferState.incompleteRide,
    );
    expect(
      customerBookingVehicleOfferState(
        hasCompany: true,
        rideReady: true,
        loading: false,
        loadFailed: false,
        offers: const <CustomerBookingVehicleOffer>[],
      ),
      CustomerBookingVehicleOfferState.noneSuitable,
    );
    expect(
      customerBookingRideDetailsReady(
        pickupFilled: true,
        dropoffFilled: false,
      ),
      isFalse,
    );
  });

  test('personal driver score is used, company aggregate is ignored', () {
    final assigned = customerBookingAssignedDriverFromMaps(
      booking: <String, dynamic>{
        'assigned_driver_id': 'drv_wotan',
        'assigned_driver': <String, dynamic>{
          'driver_id': 'drv_wotan',
          'first_name': 'Wotan',
          'rating_avg': 4.8,
          'rating_count': 12,
          'company_rating_avg': 2.1,
          'company_rating_count': 400,
        },
      },
    );
    expect(assigned.assigned, isTrue);
    expect(assigned.firstName, 'Wotan');
    expect(assigned.ratingAverage, 4.8);
    expect(assigned.ratingCount, 12);
    expect(
      customerBookingAssignedDriverFromMaps(
        booking: const <String, dynamic>{},
      ).assigned,
      isFalse,
    );
  });
}
