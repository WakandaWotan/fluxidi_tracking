// Canonical airports omitted by the generated OurAirports slice.
// KJK/EBKT is a medium airport without scheduled airline service, so the
// generator skips it. Coordinates and address come from the Belgian AIP
// (EBKT AD 2.2, ARP 504907N 0031233E; operator address Luchthavenstraat 1).

import 'airport_catalog_repository.dart';

const AirportCatalogAirport kAirportCatalogKortrijkWevelgem =
    AirportCatalogAirport(
  countryCode: 'BE',
  countryName: 'Belgium',
  city: 'Wevelgem',
  name: 'Kortrijk-Wevelgem International Airport',
  iata: 'KJK',
  icao: 'EBKT',
  latitude: 50.818611,
  longitude: 3.209167,
  preciseAddress: 'Luchthavenstraat 1, 8560 Wevelgem, Belgium',
);

const List<AirportCatalogAirport> kAirportCatalogSupplements =
    <AirportCatalogAirport>[
  kAirportCatalogKortrijkWevelgem,
];

List<AirportCatalogAirport> mergeAirportCatalogSupplements(
  List<AirportCatalogAirport> published, {
  List<AirportCatalogAirport> supplements = kAirportCatalogSupplements,
}) {
  if (supplements.isEmpty) {
    return List<AirportCatalogAirport>.unmodifiable(published);
  }
  final seen = <String>{
    for (final airport in published) airport.iata.trim().toUpperCase(),
  };
  final merged = <AirportCatalogAirport>[...published];
  for (final extra in supplements) {
    final iata = extra.iata.trim().toUpperCase();
    if (iata.length != 3 || !seen.add(iata)) continue;
    merged.add(extra);
  }
  return List<AirportCatalogAirport>.unmodifiable(merged);
}
