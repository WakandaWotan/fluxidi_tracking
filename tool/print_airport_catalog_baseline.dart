import 'dart:io';

import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';

void main() {
  final catalog = publishedAirportCatalog();
  final countries = publishedAirportCountryCodes(catalog);
  stdout.writeln('airports=${catalog.length}');
  stdout.writeln('countries=${countries.length}');
  stdout.writeln('country_codes=${countries.join(',')}');
  stdout.writeln(
    'iata_count=${catalog.map((airport) => airport.iata).toSet().length}',
  );
}
