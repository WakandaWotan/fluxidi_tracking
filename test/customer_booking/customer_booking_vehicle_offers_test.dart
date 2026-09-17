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
