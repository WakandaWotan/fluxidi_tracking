import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/company/company_trip_route.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  test('kind follows airport direction and service', () {
    expect(
      companyTripRouteKindOf(const CompanyRideOptions()),
      CompanyTripRouteKind.address,
    );
    expect(
      companyTripRouteKindOf(const CompanyRideOptions(service: 'airport')),
      CompanyTripRouteKind.toAirport,
    );
    expect(
      companyTripRouteKindOf(
        const CompanyRideOptions(
          service: 'airport',
          airportDirection: 'from_airport',
        ),
      ),
      CompanyTripRouteKind.fromAirport,
    );
  });

  test('swap keeps airport identity and does not reuse flight time', () {
    const current = CompanyRideOptions(
      service: 'airport',
      airportDirection: 'to_airport',
      airportIata: 'BRU',
      airportCountry: 'BE',
      flightNumber: 'SN1234',
      flightAt: '2026-09-20T14:00:00.000Z',
      pickupArrangement: 'scheduled',
    );
    final swapped = companyTripRouteOptionsAfterSwap(current: current);
    expect(swapped.airportDirection, 'from_airport');
    expect(swapped.airportIata, 'BRU');
    expect(swapped.flightNumber, 'SN1234');
    expect(swapped.flightAt, isEmpty);
    expect(swapped.pickupArrangement, isEmpty);
  });

  test('airport address value keeps IATA and coordinates', () {
    final airport = airportByIata('AMS');
    expect(airport, isNotNull);
    final value = companyAirportAddressValue(airport!);
    expect(value.placeId, 'airport:AMS');
    expect(value.acceptance, LimousineAddressAcceptance.selected);
    expect(value.displayText, isNotEmpty);
  });
}
