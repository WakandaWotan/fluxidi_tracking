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
}
