import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_search.dart';

void main() {
  test('search finds airports by IATA, city and partial name', () {
    final byCode = searchPublishedAirports('bru');
    expect(byCode.any((airport) => airport.iata == 'BRU'), isTrue);

    final byCity = searchPublishedAirports('Charleroi');
    expect(byCity.any((airport) => airport.iata == 'CRL'), isTrue);

    final byName = searchPublishedAirports('Schiphol');
    expect(byName.any((airport) => airport.iata == 'AMS'), isTrue);

    expect(searchPublishedAirports('z'), isNotEmpty);
    expect(searchPublishedAirports(''), isEmpty);

    final byIcao = searchPublishedAirports('EBKT');
    expect(byIcao.any((airport) => airport.iata == 'KJK'), isTrue);
  });

  test('exact IATA outranks a weaker name match', () {
    final matches = searchPublishedAirports('BER');
    expect(matches, isNotEmpty);
    expect(matches.first.iata, 'BER');
    expect(
      airportByIata(matches.first.iata),
      isNotNull,
    );
  });
}
