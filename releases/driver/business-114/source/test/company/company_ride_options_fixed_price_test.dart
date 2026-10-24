import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';

void main() {
  test('airport and return flight fields survive json', () {
    const options = CompanyRideOptions(
      service: 'airport',
      airportDirection: 'to_airport',
      airportIata: 'BRU',
      airportCountry: 'BE',
      flightNumber: 'SN1234',
      flightAt: '2026-09-16T07:40:00.000',
      pickupArrangement: 'scheduled',
      returnAirportIata: 'CDG',
      returnFlightNumber: 'AF1401',
      returnFlightAt: '2026-09-16T19:10:00.000',
    );
    final parsed = parseCompanyRideOptions(options.toJson());
    expect(parsed.airportIata, 'BRU');
    expect(parsed.flightAt, contains('2026-09-16'));
    expect(parsed.returnAirportIata, 'CDG');
    expect(parsed.returnFlightNumber, 'AF1401');
  });

  test('airport_ride stored as vehicle_type is recovered as service mode', () {
    final parsed = parseCompanyRideOptions(<String, dynamic>{
      'vehicle_type': 'airport_ride',
    });
    expect(parsed.service, 'airport');
    expect(parsed.vehicleType, isEmpty);
    expect(parsed.toJson()['vehicle_type'], isNull);
    expect(parsed.toJson()['service'], 'airport');
    expect(
      CompanyRideOptions(
        service: 'airport',
        vehicleType: 'sedan',
      ).copyWith(vehicleType: 'airport').vehicleType,
      isEmpty,
    );
  });

  test('inbound leg inverts airport direction and drops wait', () {
    const outbound = CompanyRideOptions(
      service: 'airport',
      waitMin: 20,
      airportDirection: 'to_airport',
      pickupAfterMin: 15,
      pickupArrangement: '',
    );
    final inbound = outbound.forInboundLeg();
    expect(inbound.airportDirection, 'from_airport');
    expect(inbound.waitMin, 0);
    expect(inbound.pickupAfterMin, 0);
    expect(inbound.pickupArrangement, 'scheduled');
    expect(
      inbound.forInboundLeg().airportDirection,
      'to_airport',
    );
  });
}
