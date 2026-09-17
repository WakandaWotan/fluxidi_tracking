import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_repository.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_search.dart';
import 'package:fluxidi_tracking/airport/airport_catalog_supplement.dart';
import 'package:fluxidi_tracking/company/company_plan_airport_cards.dart';
import 'package:fluxidi_tracking/customer_booking/customer_booking_addresses.dart';

void main() {
  final baseline = jsonDecode(
    File('test/airport/airport_catalog_baseline.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('published catalog is not smaller than the locked baseline', () {
    final catalog = publishedAirportCatalog();
    final countries = publishedAirportCountryCodes(catalog);
    expect(catalog.length, greaterThanOrEqualTo(baseline['airports'] as int));
    expect(countries.length, greaterThanOrEqualTo(baseline['countries'] as int));
    expect(
      countries,
      containsAll(List<String>.from(baseline['country_codes'] as List)),
    );
  });

  test('search still covers name, city, IATA and ICAO', () {
    expect(searchPublishedAirports('Liège').any((a) => a.iata == 'LGG'), isTrue);
    expect(searchPublishedAirports('LGG').first.iata, 'LGG');
    expect(searchPublishedAirports('EBKT').first.iata, 'KJK');
    expect(searchPublishedAirports('Wevelgem').any((a) => a.iata == 'KJK'), isTrue);
    expect(searchPublishedAirports('Schiphol').any((a) => a.iata == 'AMS'), isTrue);
  });

  test('photo card, search and country list resolve the same KJK record', () {
    final fromCard = companyPlanAirportCatalogRecord('KJK');
    final fromIata = airportByIata('KJK');
    final fromIcao = searchPublishedAirports('EBKT').first;
    final fromName = searchPublishedAirports('Kortrijk-Wevelgem').first;
    expect(fromCard?.iata, 'KJK');
    expect(fromIata?.iata, fromCard?.iata);
    expect(fromIcao.iata, 'KJK');
    expect(fromName.iata, 'KJK');
    expect(fromCard?.icao, kAirportCatalogKortrijkWevelgem.icao);
    expect(fromCard?.latitude, 50.818611);
    expect(fromCard?.longitude, 3.209167);
    expect(
      fromCard?.preciseAddress,
      'Luchthavenstraat 1, 8560 Wevelgem, Belgium',
    );
    expect(
      customerBookingAddressFromAirport(fromCard!).lat,
      customerBookingAddressFromAirport(fromIata!).lat,
    );
  });

  test('six Belgian photo cards stay mapped to canonical records', () {
    for (final iata in List<String>.from(
      baseline['featured_belgian_iata'] as List,
    )) {
      expect(kCompanyPlanFeaturedAirportIata, contains(iata));
      expect(companyPlanAirportCatalogRecord(iata)?.iata, iata);
      expect(File(companyPlanAirportCardAsset(iata)).existsSync(), isTrue);
    }
  });
}
