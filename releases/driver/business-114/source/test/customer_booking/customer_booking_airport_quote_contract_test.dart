import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/company/company_plan_quote.dart';
import 'package:fluxidi_tracking/company/company_ride_options.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_quote_wire.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

LimousineAddressValue _addr(
  String text, {
  double? lat,
  double? lon,
}) {
  return LimousineAddressValue(
    displayText: text,
    canonicalLabel: text,
    lat: lat,
    lon: lon,
    acceptance: lat != null && lon != null
        ? LimousineAddressAcceptance.selected
        : LimousineAddressAcceptance.manualFallback,
  );
}

void main() {
  const crl = AirportCatalogAirport(
    countryCode: 'BE',
    countryName: 'Belgium',
    city: 'Charleroi',
    name: 'Brussels South Charleroi Airport',
    iata: 'CRL',
    latitude: 50.461963,
    longitude: 4.459562,
  );

  test('CRL survives a split return and keeps IATA plus comfort tier', () {
    const outbound = CompanyRideOptions(
      service: 'airport',
      airportDirection: 'to_airport',
      airportIata: 'CRL',
      returnAirportIata: 'CRL',
      tier: 'comfort',
    );
    final inbound = outbound.forInboundLeg();
    expect(inbound.airportDirection, 'from_airport');
    expect(inbound.airportIata, 'CRL');
    expect(inbound.returnAirportIata, 'CRL');
    expect(inbound.tier, 'comfort');
  });

  test('airport /quote body has CRL, direction, return IATA and home coords', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _addr('Koekamerstraat 48A, 9688 Schorisse', lat: 50.77205, lon: 3.66959),
      to: _addr(
        'Brussels South Charleroi Airport',
        lat: 50.461963,
        lon: 4.459562,
      ),
      pickupLocal: DateTime(2026, 9, 20, 14, 34),
      options: const CompanyRideOptions(
        service: 'airport',
        airportDirection: 'to_airport',
        airportIata: 'CRL',
        returnAirportIata: 'CRL',
        tier: 'comfort',
      ),
      passengers: 1,
    );
    expect(request, isNotNull);
    expect(request!.body['airport_iata'], 'CRL');
    expect(request.body['airport_id'], 'crl');
    expect(request.body['airport_direction'], 'to_airport');
    expect(request.body['return_airport_iata'], 'CRL');
    expect(request.body['tier'], 'comfort');
    expect(request.body['service'], 'airport');
    expect(request.body['from_lat'], 50.77205);
    expect(request.body['to_lat'], 50.461963);
    expect(request.body['postcode'], '9688');
  });

  test('split inbound quote keeps CRL and return home coordinates', () {
    const outbound = CompanyRideOptions(
      service: 'airport',
      airportDirection: 'to_airport',
      airportIata: 'CRL',
      returnAirportIata: 'CRL',
      tier: 'comfort',
    );
    final request = companyPlanQuoteRequestFromAddresses(
      from: _addr(
        'Brussels South Charleroi Airport',
        lat: 50.461963,
        lon: 4.459562,
      ),
      to: _addr('Koekamerstraat 48A, 9688 Schorisse', lat: 50.77205, lon: 3.66959),
      pickupLocal: DateTime(2026, 9, 23, 21),
      options: outbound.forInboundLeg(),
      passengers: 1,
    );
    expect(request, isNotNull);
    expect(request!.body['airport_iata'], 'CRL');
    expect(request.body['airport_direction'], 'from_airport');
    expect(request.body['return_airport_iata'], 'CRL');
    expect(request.body['from_lat'], 50.461963);
    expect(request.body['to_lat'], 50.77205);
    expect(request.body['to_lng'], 3.66959);
  });

  test('missing airport metadata blocks the quote', () {
    expect(customerBookingAirportMetadataReady(null), isFalse);
    expect(
      customerBookingAirportMetadataReady(
        const AirportCatalogAirport(
          countryCode: 'BE',
          countryName: 'Belgium',
          city: 'X',
          name: 'X',
          iata: '',
        ),
      ),
      isFalse,
    );
    expect(customerBookingAirportMetadataReady(crl), isTrue);
    expect(
      customerBookingQuoteIssueFromRaw('need_airport'),
      kCustomerBookingIssueNeedAirport,
    );
    expect(
      customerBookingQuoteIssueFromRaw('Selecteer de luchthaven opnieuw'),
      kCustomerBookingIssueNeedAirport,
    );
  });

  test('airport return uses one payload with return coords, not a split inbound', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _addr('Koekamerstraat 48A, 9688 Schorisse', lat: 50.77205, lon: 3.66959),
      to: _addr(
        'Brussels South Charleroi Airport',
        lat: 50.461963,
        lon: 4.459562,
      ),
      pickupLocal: DateTime(2026, 9, 20, 14, 34),
      returnPickupLocal: DateTime(2026, 9, 23, 21),
      returnFrom: _addr(
        'Brussels South Charleroi Airport',
        lat: 50.461963,
        lon: 4.459562,
      ),
      returnTo: _addr('Koekamerstraat 48A, 9688 Schorisse', lat: 50.77205, lon: 3.66959),
      returnEnabled: true,
      options: const CompanyRideOptions(
        service: 'airport',
        airportDirection: 'to_airport',
        airportIata: 'CRL',
        returnAirportIata: 'CRL',
        tier: 'comfort',
      ),
      passengers: 1,
    );
    expect(request, isNotNull);
    expect(request!.body['return_enabled'], isTrue);
    expect(request.body['return_airport_iata'], 'CRL');
    expect(request.body['return_direction'], 'from_airport');
    expect(request.body['return_from_lat'], 50.461963);
    expect(request.body['return_to_lat'], 50.77205);
    expect(request.body['return_to_lng'], 3.66959);
    expect(request.body['tier'], 'comfort');
  });

  test('ordinary taxi stays route_calc without airport metadata', () {
    final request = companyPlanQuoteRequestFromAddresses(
      from: _addr('Heuntjesstraat 61, 8570 Anzegem', lat: 50.83, lon: 3.56),
      to: _addr('Amerstraat 48, 9688 Maarkedal', lat: 50.79, lon: 3.64),
      pickupLocal: DateTime(2026, 9, 20, 18),
      options: const CompanyRideOptions(service: 'passenger'),
      passengers: 4,
    );
    expect(request, isNotNull);
    expect(request!.body.containsKey('airport_iata'), isFalse);
    expect(request.body.containsKey('airport_direction'), isFalse);
    expect(request.body['service'], 'passenger');
    expect(request.body['tier'], isNull);
  });

  test('switching Taxi to Airport without IATA is a new incomplete quote', () {
    final taxi = companyPlanQuoteRequestFromAddresses(
      from: _addr('Koekamerstraat 48A, 9688', lat: 50.77, lon: 3.67),
      to: _addr('Gent', lat: 51.05, lon: 3.72),
      pickupLocal: DateTime(2026, 9, 20, 10),
      options: const CompanyRideOptions(service: 'passenger'),
      passengers: 1,
    )!;
    final airport = companyPlanQuoteRequestFromAddresses(
      from: _addr('Koekamerstraat 48A, 9688', lat: 50.77, lon: 3.67),
      to: _addr('Charleroi', lat: 50.46, lon: 4.46),
      pickupLocal: DateTime(2026, 9, 20, 10),
      options: const CompanyRideOptions(
        service: 'airport',
        airportDirection: 'to_airport',
      ),
      passengers: 1,
    )!;
    expect(taxi.fingerprint, isNot(airport.fingerprint));
    expect(airport.body.containsKey('airport_iata'), isFalse);
    expect(customerBookingAirportMetadataReady(null), isFalse);
  });
}
