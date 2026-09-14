// Search the published European airport catalog by name, city, country or IATA.

import 'airport_catalog_repository.dart';

int airportCatalogSearchScore(AirportCatalogAirport airport, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 0;
  final iata = airport.iata.trim().toLowerCase();
  final name = airport.name.trim().toLowerCase();
  final city = airport.city.trim().toLowerCase();
  final country = airport.countryName.trim().toLowerCase();
  final address = airport.formattedAddress.toLowerCase();
  if (iata == q) return 100;
  if (iata.startsWith(q)) return 90;
  if (city == q) return 85;
  if (city.startsWith(q)) return 80;
  if (name.startsWith(q)) return 70;
  if (name.contains(q)) return 55;
  if (city.contains(q)) return 50;
  if (country.startsWith(q)) return 40;
  if (address.contains(q) || country.contains(q)) return 30;
  return 0;
}

List<AirportCatalogAirport> searchPublishedAirports(
  String query, {
  int limit = 12,
  List<AirportCatalogAirport>? airports,
}) {
  final scored = <({int score, AirportCatalogAirport airport})>[];
  for (final airport in airports ?? publishedAirportCatalog()) {
    final score = airportCatalogSearchScore(airport, query);
    if (score > 0) {
      scored.add((score: score, airport: airport));
    }
  }
  scored.sort((a, b) {
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.airport.displayLabel.compareTo(b.airport.displayLabel);
  });
  return scored.take(limit).map((item) => item.airport).toList(growable: false);
}
