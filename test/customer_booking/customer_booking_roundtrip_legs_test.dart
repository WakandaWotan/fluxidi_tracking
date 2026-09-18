import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_booking_metrics.dart';
import 'package:fluxidi_tracking/company/company_booking_route_coords.dart';
import 'package:fluxidi_tracking/company/company_crew_combo.dart';
import 'package:fluxidi_tracking/company/company_driver_schedule.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_plan_vehicle_type.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_assigned_driver.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_labels.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_vehicle_offers.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  const tesla = <String, dynamic>{
    'vehicle_id': 'vh_tesla',
    'name': 'Tesla',
    'vehicle_type': 'sedan',
    'passenger_capacity': 3,
    'assigned_driver_id': 'drv_chris',
    'is_active': true,
  };
  const cadillac = <String, dynamic>{
    'vehicle_id': 'vh_cadillac',
    'name': 'Cadillac',
    'vehicle_type': 'sedan',
    'passenger_capacity': 4,
    'assigned_driver_id': 'drv_wotan',
    'is_active': true,
  };
  const chris = <String, dynamic>{
    'driver_id': 'drv_chris',
    'first_name': 'Christophe',
    'display_name': 'Christophe',
    'is_active': true,
    'preferred_vehicle_id': 'vh_tesla',
    'linked_vehicle_ids': <String>['vh_tesla'],
    'weekly_roster': <String, dynamic>{
      'explicitly_set': true,
      'days': <String, dynamic>{
        'sun': <Map<String, dynamic>>[
          <String, dynamic>{'start': '08:00', 'end': '18:00'},
        ],
      },
    },
  };
  const wotan = <String, dynamic>{
    'driver_id': 'drv_wotan',
    'first_name': 'Wotan',
    'display_name': 'Wotan',
    'is_active': true,
    'preferred_vehicle_id': 'vh_cadillac',
    'linked_vehicle_ids': <String>['vh_cadillac'],
    'weekly_roster': <String, dynamic>{
      'explicitly_set': true,
      'days': <String, dynamic>{
        'wed': <Map<String, dynamic>>[
          <String, dynamic>{'start': '22:00', 'end': '06:00'},
        ],
      },
    },
  };

  test('daytime outbound Tesla is bookable while night Cadillac is not yet', () {
    final noon = DateTime.utc(2026, 9, 27, 10, 0); // Sunday 12:00 Brussels
    final offers = customerBookingVehicleOffers(
      vehicles: const <Map<String, dynamic>>[tesla, cadillac],
      drivers: const <Map<String, dynamic>>[chris, wotan],
      passengers: 1,
      pickupUtc: noon,
      durationMin: 40,
      durationKnown: true,
      rideReady: true,
      availableVehicleIds: const <String>{'vh_tesla'},
      unavailableVehicleIds: const <String>{'vh_cadillac'},
      unavailableReasons: const <String, String>{
        'vh_cadillac': 'assignment_driver_outside_hours',
      },
      availabilityResolved: true,
    );
    expect(
      customerBookingBookableOffers(offers).map((offer) => offer.vehicleId),
      <String>['vh_tesla'],
    );
  });

  test('night return proposes Cadillac when Tesla is outside hours', () {
    final night = DateTime.utc(2026, 9, 30, 21, 0); // Wednesday 23:00 Brussels
    final schedules = companyDriverSchedulesFromRecords(
      const <Map<String, dynamic>>[chris, wotan],
    );
    final outbound = companyPlanCrewCombos(
      drivers: const <Map<String, dynamic>>[chris, wotan],
      vehicles: const <Map<String, dynamic>>[tesla, cadillac],
      type: CompanyPlanVehicleType.sedan,
      passengers: 1,
      whenNow: false,
      rideStartUtc: DateTime.utc(2026, 9, 27, 10, 0),
      rideEndUtc: DateTime.utc(2026, 9, 27, 10, 40),
      schedules: schedules,
    );
    final inbound = companyPlanCrewCombos(
      drivers: const <Map<String, dynamic>>[chris, wotan],
      vehicles: const <Map<String, dynamic>>[tesla, cadillac],
      type: CompanyPlanVehicleType.sedan,
      passengers: 1,
      whenNow: false,
      rideStartUtc: night,
      rideEndUtc: night.add(const Duration(minutes: 40)),
      schedules: schedules,
    );
    expect(
      outbound.any((combo) => combo.vehicleId == 'vh_tesla' && combo.suitable),
      isTrue,
    );
    expect(
      inbound.any((combo) => combo.vehicleId == 'vh_tesla' && combo.suitable),
      isFalse,
    );
    final proposed = proposeCompanyPlanReturnCrew(
      combos: inbound,
      outboundDriverId: 'drv_chris',
      outboundVehicleId: 'vh_tesla',
      preferSame: true,
      outboundAvailableForReturn: false,
    );
    expect(proposed.driverId, 'drv_wotan');
    expect(proposed.vehicleId, 'vh_cadillac');
  });

  test('200 plus 200 from separate legs becomes 400, not a doubled blind copy', () {
    const outbound = CompanyPlanQuoteResult(
      fingerprint: 'out',
      distanceKm: 80,
      durationMin: 55,
      priceInclVat: 200,
      priceExVat: 165.29,
      priceVat: 34.71,
      currency: 'EUR',
      priceAvailable: true,
    );
    const inbound = CompanyPlanQuoteResult(
      fingerprint: 'in',
      distanceKm: 80,
      durationMin: 58,
      priceInclVat: 200,
      priceExVat: 165.29,
      priceVat: 34.71,
      currency: 'EUR',
      priceAvailable: true,
    );
    final merged = companyPlanMergeLegQuotes(
      outbound: outbound,
      inbound: inbound,
    );
    expect(merged.displayTotalPrice, 400);
    expect(merged.outboundPriceInclVat, 200);
    expect(merged.returnPriceInclVat, 200);
    expect(merged.priceExVat, closeTo(330.58, 0.01));
    expect(companyPlanQuoteNeedsInboundLeg(outbound), isTrue);
    expect(companyPlanQuoteNeedsInboundLeg(merged), isFalse);
  });

  test('parse keeps outbound 200 and listed return 200 as total 400', () {
    final parsed = parseCompanyPlanQuote(
      <String, dynamic>{
        'ok': true,
        'price_incl_vat': 200,
        'return_price_incl_vat': 200,
        'total_price_incl_vat': 400,
        'distance_km': 80,
        'duration_min': 55,
        'return_distance_km': 80,
        'return_duration_min': 58,
        'currency': 'EUR',
        'price_available': true,
      },
      fingerprint: 'roundtrip',
    );
    expect(parsed.outboundPriceInclVat, 200);
    expect(parsed.returnPriceInclVat, 200);
    expect(parsed.displayTotalPrice, 400);
    expect(companyPlanQuoteNeedsInboundLeg(parsed), isFalse);
  });

  test('outbound-only quote still needs a separate inbound leg', () {
    final parsed = parseCompanyPlanQuote(
      <String, dynamic>{
        'ok': true,
        'price_incl_vat': 200,
        'distance_km': 80,
        'duration_min': 55,
        'currency': 'EUR',
        'price_available': true,
      },
      fingerprint: 'one-way',
    );
    expect(parsed.displayTotalPrice, 200);
    expect(companyPlanQuoteNeedsInboundLeg(parsed), isTrue);
  });

  test('reopen keeps stored coords and 400 euro total', () {
    final row = <String, dynamic>{
      'record': <String, dynamic>{
        'booking': <String, dynamic>{
          'from': 'Brussels Airport',
          'to': 'Gent',
          'pickup_lat': 50.901,
          'pickup_lon': 4.484,
          'dropoff_lat': 51.054,
          'dropoff_lon': 3.717,
          'total_price_incl_vat': 400,
          'price_incl_vat': 200,
          'return_price_incl_vat': 200,
        },
        'quote': <String, dynamic>{
          'pickup_lat': 50.901,
          'pickup_lon': 4.484,
          'dropoff_lat': 51.054,
          'dropoff_lon': 3.717,
        },
      },
    };
    final route = resolveCompanyBookingRouteEndpoints(row: row);
    expect(route.hasCoordinates, isTrue);
    expect(route.pickup.acceptance, LimousineAddressAcceptance.selected);
    expect(resolveCompanyBookingPriceInclVat(row), 400);
    expect(
      companyPlanRouteStatus(
        from: route.pickup,
        to: route.dropoff,
        loading: false,
        quote: CompanyPlanQuoteResult(
          fingerprint: 'detail',
          distanceKm: 80,
          durationMin: 55,
          priceInclVat: 400,
          priceAvailable: true,
          pickupLat: route.pickup.lat,
          pickupLon: route.pickup.lon,
          dropoffLat: route.dropoff.lat,
          dropoffLon: route.dropoff.lon,
        ),
      ),
      CompanyPlanRouteStatus.ready,
    );
  });

  test('return date and time labels stay recognizable', () {
    expect(kCustomerBookingReturnDate.of(AppLanguage.nl), 'Datum terugrit');
    expect(kCustomerBookingReturnTime.of(AppLanguage.nl), 'Tijd terugrit');
    expect(
      kCustomerBookingNoVehicleAtTime.of(AppLanguage.nl),
      'Geen voertuig beschikbaar op dit tijdstip',
    );
  });

  test('proposed driver keeps a public photo url', () {
    final proposed = customerBookingProposedDriverFromRecord(<String, dynamic>{
      'driver_id': 'drv_chris',
      'first_name': 'Christophe',
      'public_photo_url': 'https://cdn.example/chris.jpg',
    });
    expect(proposed.photoUrl, 'https://cdn.example/chris.jpg');
    expect(proposed.assigned, isFalse);
  });
}
