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

  test('to/from airport fills only the matching catalog endpoint', () {
    final airport = airportByIata('BRU')!;
    LimousineAddressValue? pickup;
    LimousineAddressValue? dropoff;
    companyTripApplyAirportEndpoint(
      kind: CompanyTripRouteKind.toAirport,
      airport: airport,
      applyPickup: (value) => pickup = value,
      applyDropoff: (value) => dropoff = value,
    );
    expect(pickup, isNull);
    expect(dropoff?.placeId, 'airport:BRU');
    expect(dropoff?.lat, airport.latitude);
    expect(dropoff?.lon, airport.longitude);

    pickup = null;
    dropoff = null;
    companyTripApplyAirportEndpoint(
      kind: CompanyTripRouteKind.fromAirport,
      airport: airport,
      applyPickup: (value) => pickup = value,
      applyDropoff: (value) => dropoff = value,
    );
    expect(dropoff, isNull);
    expect(pickup?.placeId, 'airport:BRU');
  });

  test('direction change clears the opposite airport endpoint', () {
    final airport = airportByIata('ANR')!;
    final filled = companyAirportAddressValue(airport);
    var pickup = filled;
    var dropoff = filled;
    companyTripClearOppositeAirportEndpoint(
      kind: CompanyTripRouteKind.fromAirport,
      airport: airport,
      pickup: pickup,
      dropoff: dropoff,
      clearPickup: () => pickup = const LimousineAddressValue(),
      clearDropoff: () => dropoff = const LimousineAddressValue(),
    );
    expect(pickup.placeId, 'airport:ANR');
    expect(dropoff.placeId ?? '', isEmpty);
  });
}
