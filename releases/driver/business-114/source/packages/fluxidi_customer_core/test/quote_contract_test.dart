import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:test/test.dart';

FluxidiAddressValue _address(
  String label, {
  double? lat,
  double? lon,
  String display = '',
  FluxidiAddressAcceptance acceptance = FluxidiAddressAcceptance.selected,
}) {
  return FluxidiAddressValue(
    displayText: display.isEmpty ? label : display,
    canonicalLabel: label,
    lat: lat,
    lon: lon,
    acceptance: acceptance,
  );
}

final FluxidiAddressValue _from = _address(
  'Markt 1A bus 3, 9600 Ronse',
  lat: 50.7452,
  lon: 3.6003,
  display: 'Markt 1A',
);
final FluxidiAddressValue _to = _address(
  'Grote Markt 1, 9700 Oudenaarde',
  lat: 50.8492,
  lon: 3.6003,
);

void main() {
  group('address identity', () {
    test('the canonical label carries the house number and addition', () {
      expect(_from.routeText, 'Markt 1A bus 3, 9600 Ronse');
      expect(_from.displayText, 'Markt 1A');
    });

    test('an unconfirmed address has no route text and is not quote ready', () {
      final typed = _address(
        'Markt',
        acceptance: FluxidiAddressAcceptance.incomplete,
      );

      expect(typed.routeText, isEmpty);
      expect(fluxidiAddressIsQuoteReady(typed), isFalse);
    });

    test('a confirmed address without coordinates is not quote ready', () {
      final noCoords = _address('Markt 1, 9600 Ronse');

      expect(noCoords.isRouteReady, isTrue);
      expect(fluxidiAddressIsQuoteReady(noCoords), isFalse);
    });
  });

  group('quote request', () {
    test('sends route text, coordinates, passengers and options', () {
      final request = buildFluxidiQuoteRequest(
        from: _from,
        to: _to,
        pickupLocal: DateTime(2026, 9, 22, 9, 30),
        options: const FluxidiRideOptions(service: 'passenger', bags: 2),
        passengers: 3,
      );

      expect(request, isNotNull);
      final body = request!.body;
      expect(body['from'], 'Markt 1A bus 3, 9600 Ronse');
      expect(body['to'], 'Grote Markt 1, 9700 Oudenaarde');
      expect(body['passengers'], 3);
      expect(body['currency'], 'EUR');
      expect(body['bags'], 2);
      expect(body['service'], 'passenger');
      expect(body['pickup_lat'], 50.7452);
      expect(body['from_lng'], 3.6003);
      expect(body['dropoff_lat'], 50.8492);
      expect(body['return_enabled'], isFalse);
      expect(body['ride_options'], <String, dynamic>{
        'service': 'passenger',
        'bags': 2,
        'wait_min': 0,
      });
    });

    test('a later pickup is sent as Europe/Brussels wall clock in UTC', () {
      // Summer time: 09:30 Brussels is 07:30 UTC.
      final summer = buildFluxidiQuoteRequest(
        from: _from,
        to: _to,
        pickupLocal: DateTime(2026, 7, 1, 9, 30),
        options: const FluxidiRideOptions(service: 'passenger'),
        passengers: 1,
      );
      // Winter time: 09:30 Brussels is 08:30 UTC.
      final winter = buildFluxidiQuoteRequest(
        from: _from,
        to: _to,
        pickupLocal: DateTime(2026, 1, 15, 9, 30),
        options: const FluxidiRideOptions(service: 'passenger'),
        passengers: 1,
      );

      expect(summer!.body['pickup_iso'], '2026-07-01T07:30:00.000Z');
      expect(winter!.body['pickup_iso'], '2026-01-15T08:30:00.000Z');
    });

    test('now sends when_now and no client schedule fields', () {
      final request = buildFluxidiQuoteRequest(
        from: _from,
        to: _to,
        pickupLocal: DateTime(2026, 9, 22, 9, 30),
        options: const FluxidiRideOptions(service: 'passenger'),
        passengers: 1,
        whenNow: true,
      );

      final body = request!.body;
      expect(body['when'], 'now');
      expect(body['when_now'], isTrue);
      expect(body.containsKey('pickup_iso'), isFalse);
      expect(body.containsKey('date'), isFalse);
      expect(body.containsKey('time'), isFalse);
    });

    test('a return ride sends the return schedule and addresses', () {
      final request = buildFluxidiQuoteRequest(
        from: _from,
        to: _to,
        pickupLocal: DateTime(2026, 7, 1, 9, 30),
        options: const FluxidiRideOptions(service: 'passenger'),
        passengers: 2,
        returnEnabled: true,
        returnPickupLocal: DateTime(2026, 7, 1, 18, 0),
        returnFrom: _to,
        returnTo: _from,
      );

      final body = request!.body;
      expect(body['return_enabled'], isTrue);
      expect(body['return_pickup_iso'], '2026-07-01T16:00:00.000Z');
      expect(body['return_from'], 'Grote Markt 1, 9700 Oudenaarde');
      expect(body['return_to'], 'Markt 1A bus 3, 9600 Ronse');
      expect(body['return_from_lat'], 50.8492);
      expect(body['return_to_lng'], 3.6003);
    });

    test('an airport ride strips every wait field', () {
      final request = buildFluxidiQuoteRequest(
        from: _from,
        to: _to,
        pickupLocal: DateTime(2026, 7, 1, 9, 30),
        options: const FluxidiRideOptions(service: 'airport', waitMin: 30),
        passengers: 2,
      );

      final body = request!.body;
      expect(body.containsKey('wait_min'), isFalse);
      expect((body['ride_options'] as Map).containsKey('wait_min'), isFalse);
      expect(body['fixed_fare_zone_type'], 'postcode');
      expect(body['fixed_fare_zone_value'], '9600');
    });

    test('missing coordinates or a missing later time yields no request', () {
      expect(
        buildFluxidiQuoteRequest(
          from: _address('Markt 1, 9600 Ronse'),
          to: _to,
          pickupLocal: DateTime(2026, 9, 22, 9, 30),
          options: const FluxidiRideOptions(service: 'passenger'),
          passengers: 1,
        ),
        isNull,
      );
      expect(
        buildFluxidiQuoteRequest(
          from: _from,
          to: _to,
          pickupLocal: null,
          options: const FluxidiRideOptions(service: 'passenger'),
          passengers: 1,
        ),
        isNull,
      );
    });

    test('the text-only builder omits coordinates but keeps the contract', () {
      final typed = _address(
        'Grote Markt 12, 9600 Ronse',
        acceptance: FluxidiAddressAcceptance.manualFallback,
      );
      final request = buildFluxidiQuoteRequestFromText(
        from: typed,
        to: _address(
          'Markt 1, 9700 Oudenaarde',
          acceptance: FluxidiAddressAcceptance.manualFallback,
        ),
        pickupLocal: DateTime(2026, 7, 1, 9, 30),
        options: const FluxidiRideOptions(service: 'passenger'),
        passengers: 2,
      );

      expect(request, isNotNull);
      final body = request!.body;
      expect(body['from'], 'Grote Markt 12, 9600 Ronse');
      expect(body['to'], 'Markt 1, 9700 Oudenaarde');
      expect(body['pickup_iso'], '2026-07-01T07:30:00.000Z');
      expect(body.containsKey('pickup_lat'), isFalse);
      expect(body.containsKey('to_lng'), isFalse);
    });

    test('the text-only builder still refuses unconfirmed input', () {
      expect(
        buildFluxidiQuoteRequestFromText(
          from: _address(
            'Markt',
            acceptance: FluxidiAddressAcceptance.incomplete,
          ),
          to: _to,
          pickupLocal: DateTime(2026, 7, 1, 9, 30),
          options: const FluxidiRideOptions(service: 'passenger'),
          passengers: 1,
        ),
        isNull,
      );
    });

    test('the fingerprint changes when any priced input changes', () {
      FluxidiQuoteRequest build({
        int passengers = 2,
        int bags = 0,
        bool returnEnabled = false,
      }) {
        return buildFluxidiQuoteRequest(
          from: _from,
          to: _to,
          pickupLocal: DateTime(2026, 7, 1, 9, 30),
          options: FluxidiRideOptions(service: 'passenger', bags: bags),
          passengers: passengers,
          returnEnabled: returnEnabled,
          returnPickupLocal: DateTime(2026, 7, 1, 18, 0),
          returnFrom: _to,
          returnTo: _from,
        )!;
      }

      final base = build().fingerprint;
      expect(build(passengers: 3).fingerprint, isNot(base));
      expect(build(bags: 1).fingerprint, isNot(base));
      expect(build(returnEnabled: true).fingerprint, isNot(base));
      expect(build().fingerprint, base);
    });
  });

  group('public wire fields', () {
    test('date and time are derived from pickup_iso, not invented', () {
      final body = <String, dynamic>{'pickup_iso': '2026-07-01T07:30:00.000Z'};

      fluxidiEnsurePublicScheduleFields(body);

      final expected = DateTime.parse('2026-07-01T07:30:00.000Z').toLocal();
      expect(body['date'], fluxidiFormatDateYmd(expected));
      expect(body['time'], fluxidiFormatTimeHm(expected));
    });

    test('now uses the injected clock and fills pickup_iso', () {
      final body = <String, dynamic>{'when_now': true};

      fluxidiEnsurePublicScheduleFields(
        body,
        clock: () => DateTime(2026, 7, 1, 9, 30),
      );

      expect(body['date'], '2026-07-01');
      expect(body['time'], '09:30');
      expect((body['pickup_iso'] as String).isNotEmpty, isTrue);
    });

    test('without a schedule nothing is added', () {
      final body = <String, dynamic>{'from': 'a', 'to': 'b'};

      fluxidiEnsurePublicScheduleFields(body);

      expect(body.containsKey('date'), isFalse);
      expect(body.containsKey('time'), isFalse);
    });

    test('a return schedule gets its own date and time', () {
      final body = <String, dynamic>{
        'pickup_iso': '2026-07-01T07:30:00.000Z',
        'return_pickup_iso': '2026-07-01T16:00:00.000Z',
      };

      fluxidiEnsurePublicScheduleFields(body);

      expect(body['return_date'], isNotNull);
      expect(body['return_time'], isNotNull);
    });
  });

  group('partner scope', () {
    test('routing fields are added without touching the rest', () {
      const scope = FluxidiPartnerScope(
        partnerId: 'company:t1:c1',
        tenantId: 't1',
        companyId: 'c1',
        companyName: 'Taxi Schorisse',
        sourceLabel: 'customer_taxi_search',
      );

      final body = scope.decorate(<String, dynamic>{'from': 'a', 'to': 'b'});

      expect(body['public_partner_id'], 'company:t1:c1');
      expect(body['partner_id'], 'company:t1:c1');
      expect(body['tenant_id'], 't1');
      expect(body['company_id'], 'c1');
      expect(body['public_partner_name'], 'Taxi Schorisse');
      expect(body['source_label'], 'customer_taxi_search');
      expect(body['entry_kind'], 'taxi');
      expect(body['from'], 'a');
    });

    test('a company id alone still routes', () {
      const scope = FluxidiPartnerScope(companyId: 'c1');

      expect(scope.routingPartnerId, 'c1');
      expect(scope.decorate(const <String, dynamic>{})['partner_id'], 'c1');
    });
  });

  group('quote result', () {
    test('a one-way price, distance and duration are taken as sent', () {
      final result = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'price_incl_vat': 42.5,
        'price_ex_vat': 40.09,
        'price_vat': 2.41,
        'distance_km': 18.4,
        'duration_min': 24,
        'currency': 'EUR',
        'pricing_source': 'tariff',
        'price_available': true,
      }, fingerprint: 'fp');

      expect(result.displayTotalPrice, 42.5);
      expect(result.priceExVat, 40.09);
      expect(result.priceVat, 2.41);
      expect(result.distanceKm, 18.4);
      expect(result.durationMin, 24);
      expect(result.currency, 'EUR');
      expect(result.priceAvailable, isTrue);
      expect(result.hasRoute, isTrue);
      expect(result.isFixedPrice, isFalse);
    });

    test('a round trip keeps both legs and the server total', () {
      final result = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'outbound_price_incl_vat': 30,
        'return_price_incl_vat': 28,
        'total_price_incl_vat': 58,
        'distance_km': 12,
        'duration_min': 18,
        'return_distance_km': 12,
        'return_duration_min': 19,
      }, fingerprint: 'fp');

      expect(result.outboundPriceInclVat, 30);
      expect(result.returnPriceInclVat, 28);
      expect(result.displayTotalPrice, 58);
      expect(result.hasReturnRoute, isTrue);
      expect(result.totalCheck.consistent, isTrue);
    });

    test('a total that disagrees with its legs is reported, not repaired', () {
      final result = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'outbound_price_incl_vat': 200,
        'return_price_incl_vat': 200,
        'total_price_incl_vat': 401,
      }, fingerprint: 'fp');

      expect(result.displayTotalPrice, 401);
      expect(result.totalCheck.comparable, isTrue);
      expect(result.totalCheck.consistent, isFalse);
      expect(result.totalCheck.driftCents, 100);
    });

    test('calculator_off and request_quote_required block the price', () {
      final off = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'calculator_off': true,
        'price_incl_vat': 10,
      }, fingerprint: 'fp');
      final manual = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'request_quote_required': true,
        'price_incl_vat': 10,
      }, fingerprint: 'fp');

      expect(off.calculatorOff, isTrue);
      expect(off.priceAvailable, isFalse);
      expect(manual.requestQuoteRequired, isTrue);
      expect(manual.priceAvailable, isFalse);
    });

    test('price_available false wins over a sent amount', () {
      final result = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'price_available': false,
        'price_incl_vat': 25,
      }, fingerprint: 'fp');

      expect(result.priceAvailable, isFalse);
    });

    test('a fixed price snapshot is kept', () {
      final result = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'price_incl_vat': 75,
        'fixed_price_snapshot': <String, dynamic>{'zone': '9600'},
      }, fingerprint: 'fp');

      expect(result.isFixedPrice, isTrue);
      expect(result.fixedPriceSnapshot!['zone'], '9600');
    });

    test('ok:false throws the server error code', () {
      expect(
        () => parseFluxidiQuote(<String, dynamic>{
          'ok': false,
          'error': 'route_failed',
        }, fingerprint: 'fp'),
        throwsA(
          isA<FluxidiQuoteException>().having(
            (e) => e.code,
            'code',
            'route_failed',
          ),
        ),
      );
    });

    test('the public quote coordinates are read from from_/to_ fields', () {
      final result = parseFluxidiQuote(<String, dynamic>{
        'ok': true,
        'price_incl_vat': 35.1,
        'distance_km': 13.2,
        'duration_min': 17,
        'from_lat': 50.7452,
        'from_lng': 3.6003,
        'to_lat': 50.8492,
        'to_lng': 3.6089,
      }, fingerprint: 'fp');

      expect(result.pickupLat, 50.7452);
      expect(result.pickupLon, 3.6003);
      expect(result.dropoffLat, 50.8492);
      expect(result.dropoffLon, 3.6089);
    });

    test('money arrives as text with a comma', () {
      expect(fluxidiParseMoney('42,50'), 42.5);
      expect(fluxidiParseMoney(''), isNull);
      expect(fluxidiParseDurationMin('0'), isNull);
      expect(fluxidiParseDurationMin('23.6'), 24);
    });
  });

  group('availability and offers', () {
    Map<String, dynamic> row(
      String id, {
      bool available = true,
      String reason = '',
      String driverId = '',
      String driverName = '',
      int? seats,
    }) {
      return <String, dynamic>{
        'vehicle_id': id,
        'available': available,
        'reason': reason,
        if (driverId.isNotEmpty) 'driver_id': driverId,
        if (driverName.isNotEmpty) 'public_display_name': driverName,
        if (seats != null) 'passenger_seats': seats,
      };
    }

    test('rows are read exactly as the server states them', () {
      final snapshot = parseFluxidiAvailability(<String, dynamic>{
        'ok': true,
        'partner_id': 'company:t1:c1',
        'vehicles': <Map<String, dynamic>>[
          row('v1', driverId: 'd1', driverName: 'Jan', seats: 4),
          row('v2', available: false, reason: 'no_driver'),
        ],
      });

      expect(snapshot.fetched, isTrue);
      expect(snapshot.loadFailed, isFalse);
      expect(snapshot.availableIds, <String>{'v1'});
      expect(snapshot.unavailableIds, <String>{'v2'});
      expect(snapshot.rowFor('v2')!.reason, 'no_driver');
      expect(snapshot.rowFor('v1')!.passengerSeats, 4);
      expect(snapshot.hasAnyAvailable, isTrue);
    });

    test('a broken payload is a load failure, not an empty fleet', () {
      expect(parseFluxidiAvailability('nope').loadFailed, isTrue);
      expect(
        parseFluxidiAvailability(<String, dynamic>{'ok': false}).loadFailed,
        isTrue,
      );
      expect(
        parseFluxidiAvailability(<String, dynamic>{'ok': true}).loadFailed,
        isTrue,
      );
    });

    test('offers only exist for vehicles the server answered for', () {
      final snapshot = parseFluxidiAvailability(<String, dynamic>{
        'ok': true,
        'vehicles': <Map<String, dynamic>>[
          row('v1', driverId: 'd1', driverName: 'Jan', seats: 4),
          row('v2', available: false, reason: 'maintenance'),
        ],
      });

      final offers = buildFluxidiVehicleOffers(
        profileVehicles: <Map<String, dynamic>>[
          <String, dynamic>{
            'vehicle_id': 'v1',
            'name': 'Mercedes V-Klasse',
            'public_photo_url': 'https://cdn.example.invalid/v1.jpg',
          },
          <String, dynamic>{'vehicle_id': 'v2', 'name': 'Tesla Model Y'},
          <String, dynamic>{'vehicle_id': 'v3', 'name': 'Onbekend'},
          <String, dynamic>{
            'vehicle_id': 'v4',
            'name': 'Buiten dienst',
            'is_active': false,
          },
        ],
        availability: snapshot,
      );

      expect(offers.map((o) => o.vehicleId), <String>['v1', 'v2']);
      expect(offers.first.name, 'Mercedes V-Klasse');
      expect(offers.first.photoUrl, 'https://cdn.example.invalid/v1.jpg');
      expect(offers.first.driverDisplayName, 'Jan');
      expect(offers.first.passengerSeats, 4);
      expect(offers.last.available, isFalse);
      expect(offers.last.reason, 'maintenance');
      expect(offers.last.hasDriverDetails, isFalse);
    });

    test('no offers at all before availability was fetched', () {
      final offers = buildFluxidiVehicleOffers(
        profileVehicles: <Map<String, dynamic>>[
          <String, dynamic>{'vehicle_id': 'v1', 'name': 'Wagen'},
        ],
        availability: const FluxidiAvailabilitySnapshot(),
      );

      expect(offers, isEmpty);
    });

    test('capacity is only judged when the server stated it', () {
      const withSeats = FluxidiVehicleOffer(
        vehicleId: 'v1',
        name: 'Klein',
        available: true,
        passengerSeats: 3,
      );
      const withoutSeats = FluxidiVehicleOffer(
        vehicleId: 'v2',
        name: 'Onbekend',
        available: true,
      );

      expect(withSeats.tooSmallFor(4), isTrue);
      expect(withSeats.tooSmallFor(3), isFalse);
      expect(withoutSeats.tooSmallFor(8), isFalse);
    });
  });
}
