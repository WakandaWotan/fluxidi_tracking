// COMPANY-CUSTOMER-OPS-P0 — shared trip route kind for quote and plan ride.

import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

enum CompanyTripRouteKind { address, toAirport, fromAirport }

CompanyTripRouteKind companyTripRouteKindOf(CompanyRideOptions options) {
  switch (options.airportDirection.trim()) {
    case 'from_airport':
      return CompanyTripRouteKind.fromAirport;
    case 'to_airport':
      return CompanyTripRouteKind.toAirport;
    default:
      return options.isAirport
          ? CompanyTripRouteKind.toAirport
          : CompanyTripRouteKind.address;
  }
}

bool companyTripRouteKindIsAirport(CompanyTripRouteKind kind) {
  return kind == CompanyTripRouteKind.toAirport ||
      kind == CompanyTripRouteKind.fromAirport;
}

LimousineAddressValue companyAirportAddressValue(AirportCatalogAirport airport) {
  final label = airport.formattedAddress;
  return LimousineAddressValue(
    displayText: label,
    canonicalLabel: airport.displayLabel,
    lat: airport.latitude,
    lon: airport.longitude,
    placeId: 'airport:${airport.iata.trim().toUpperCase()}',
    acceptance: LimousineAddressAcceptance.selected,
  );
}

CompanyRideOptions companyTripRouteOptionsForKind({
  required CompanyRideOptions current,
  required CompanyTripRouteKind kind,
}) {
  switch (kind) {
    case CompanyTripRouteKind.address:
      return current.copyWith(
        service: current.service == 'airport' ? '' : current.service,
        airportDirection: '',
      );
    case CompanyTripRouteKind.toAirport:
      return current.copyWith(
        service: 'airport',
        airportDirection: 'to_airport',
        flightAt: '',
        pickupArrangement: '',
        pickupAfterMin: 0,
      );
    case CompanyTripRouteKind.fromAirport:
      return current.copyWith(
        service: 'airport',
        airportDirection: 'from_airport',
        flightAt: '',
      );
  }
}

CompanyRideOptions companyTripRouteOptionsAfterSwap({
  required CompanyRideOptions current,
}) {
  final kind = companyTripRouteKindOf(current);
  if (kind == CompanyTripRouteKind.address) return current;
  final next = kind == CompanyTripRouteKind.toAirport
      ? CompanyTripRouteKind.fromAirport
      : CompanyTripRouteKind.toAirport;
  return companyTripRouteOptionsForKind(current: current, kind: next).copyWith(
    airportIata: current.airportIata,
    airportCountry: current.airportCountry,
    flightNumber: current.flightNumber,
    flightAt: '',
    pickupArrangement: '',
    pickupAfterMin: 0,
    flightTimezone: current.flightTimezone,
    returnAirportIata: current.returnAirportIata,
    returnFlightNumber: current.returnFlightNumber,
    returnFlightAt: current.returnFlightAt,
    returnPickupArrangement: current.returnPickupArrangement,
  );
}

void companyTripApplyAirportEndpoint({
  required CompanyTripRouteKind kind,
  required AirportCatalogAirport airport,
  required void Function(LimousineAddressValue value) applyPickup,
  required void Function(LimousineAddressValue value) applyDropoff,
}) {
  final value = companyAirportAddressValue(airport);
  if (kind == CompanyTripRouteKind.fromAirport) {
    applyPickup(value);
    return;
  }
  if (kind == CompanyTripRouteKind.toAirport) {
    applyDropoff(value);
  }
}

bool companyTripAddressIsAirport(
  LimousineAddressValue value,
  AirportCatalogAirport airport,
) {
  final expected = 'airport:${airport.iata.trim().toUpperCase()}';
  return (value.placeId ?? '').trim().toUpperCase() == expected.toUpperCase();
}

void companyTripClearOppositeAirportEndpoint({
  required CompanyTripRouteKind kind,
  required AirportCatalogAirport airport,
  required LimousineAddressValue pickup,
  required LimousineAddressValue dropoff,
  required void Function() clearPickup,
  required void Function() clearDropoff,
}) {
  if (kind == CompanyTripRouteKind.fromAirport &&
      companyTripAddressIsAirport(dropoff, airport)) {
    clearDropoff();
    return;
  }
  if (kind == CompanyTripRouteKind.toAirport &&
      companyTripAddressIsAirport(pickup, airport)) {
    clearPickup();
  }
}
