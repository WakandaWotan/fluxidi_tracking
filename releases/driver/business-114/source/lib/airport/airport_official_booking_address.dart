// Versioned official postal addresses for existing airport catalogue entries.
// The aviation reference point remains in the catalogue. This binding is only
// an address identity; it never grants a road, taxi stand or terminal entrance.
// Backend select/reverify and the unchanged route-access checks remain required.
import 'airport_catalog_repository.dart';
import '../customer_booking/official_address_identity.dart';

class AirportOfficialBookingAddress {
  const AirportOfficialBookingAddress({required this.label, required this.latitude,
    required this.longitude, required this.identity});
  final String label;
  final double latitude, longitude;
  final OfficialAddressIdentity identity;
}

AirportOfficialBookingAddress? airportOfficialBookingAddress(AirportCatalogAirport airport) {
  final iata=airport.iata.trim().toUpperCase();
  final country=airport.countryCode.trim().toUpperCase();
  final icao=airport.icao.trim().toUpperCase();
  if(iata=='BRU' && country=='BE' && (icao.isEmpty || icao=='EBBR')) {
    return const AirportOfficialBookingAddress(
      label:'Luchthaven Brussel Nationaal 1, 1930 Zaventem BE',
      latitude:50.89881225, longitude:4.48511965,
      identity:OfficialAddressIdentity(
        id:'https://data.vlaanderen.be/id/adres/3668952',
        indexRevision:'official-be-nl-spatial-v2-c2369b3286ce357a669f3ef1',
        source:'Vlaanderen Adressenregister',
        sourceVersion:'2023-11-01T15:21:48+01:00'));
  }
  if(iata=='AMS' && country=='NL' && (icao.isEmpty || icao=='EHAM')) {
    return const AirportOfficialBookingAddress(
      label:'Vertrekpassage 1, 1118AP Schiphol NL',
      latitude:52.30865045, longitude:4.76407707,
      identity:OfficialAddressIdentity(
        id:'http://bag.basisregistraties.overheid.nl/bag/id/nummeraanduiding/0394200001005830',
        indexRevision:'official-be-nl-spatial-v2-c2369b3286ce357a669f3ef1',
        source:'Kadaster BAG / PDOK Adressen ATOM',
        sourceVersion:'2@2012-01-30@2012-01-31T09:23:29.000'));
  }
  return null;
}
