import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/hotel_geo_taxonomy.dart';
import 'package:fluxidi_tracking/hotels/stay22_europe_countries.dart';

void main() {
  final exposed = stay22CountryPickerOptions('en');
  final exposedCodes = exposed.map((option) => option.value).toSet();

  test('every exposed European ISO has catalogue coverage and a capital', () {
    expect(exposedCodes.contains('RU'), isFalse);
    expect(exposedCodes.contains('BY'), isFalse);
    for (final code in exposedCodes) {
      final country = stay22CatalogueCountryByCode(code);
      expect(country, isNotNull, reason: code);
      expect(stay22CountryHasMajorCities(country!), isTrue, reason: code);
      expect(country.capitalSettlement, isNotNull, reason: 'capital $code');
      expect(country.capitalSettlement!.isCapital, isTrue, reason: code);
    }
  });

  test('country and city IDs are unique and stay on the correct ISO', () {
    final countryIds = <String>{};
    for (final code in exposedCodes) {
      expect(countryIds.add(code), isTrue, reason: 'duplicate country $code');
      final country = stay22CatalogueCountryByCode(code)!;
      final cityIds = <String>{};
      for (final region in country.regions) {
        expect(region.settlements, isNotEmpty, reason: '${country.code}/${region.key}');
        for (final city in region.settlements) {
          expect(cityIds.add(city.key), isTrue, reason: '${country.code}/${city.key}');
          expect(stay22CatalogueCityByKey(countryCode: code, cityKey: city.key), city);
          expect(
            stay22RegionForCity(countryCode: code, cityKey: city.key)?.key,
            region.key,
          );
        }
      }
    }
  });

  test('city-state exceptions hide the region selector', () {
    for (final code in kStay22CityStateCountryCodes) {
      expect(exposedCodes, contains(code));
      final identity = stay22CountryIdentityFor(
        countryCode: code,
        languageCode: 'en',
      );
      expect(identity?.hideRegionSelector, isTrue, reason: code);
      expect(identity?.showCitySelector, isTrue, reason: code);
      expect(stay22RegionPickerOptions(countryCode: code, languageCode: 'en'), isEmpty);
      expect(
        stay22CityPickerOptions(countryCode: code, languageCode: 'en'),
        isNotEmpty,
      );
    }
    expect(
      stay22CountryIdentityFor(countryCode: 'PT', languageCode: 'nl')?.hideRegionSelector,
      isFalse,
    );
  });

  test('mandatory regression cities resolve on the correct ISO', () {
    const required = <String, List<String>>{
      'PT': <String>['lisbon', 'porto', 'faro', 'braga', 'coimbra', 'funchal'],
      'IT': <String>['rome', 'milan', 'venice', 'florence', 'naples', 'bologna', 'turin', 'verona', 'palermo', 'catania'],
      'DK': <String>['copenhagen', 'aarhus', 'odense', 'aalborg'],
      'AT': <String>['vienna', 'salzburg', 'innsbruck', 'graz', 'linz'],
      'GR': <String>['athens', 'thessaloniki', 'heraklion', 'rhodes', 'corfu'],
      'CH': <String>['zurich', 'geneva', 'basel', 'bern', 'lausanne', 'lucerne', 'lugano'],
      'IE': <String>['dublin', 'cork', 'galway', 'limerick', 'kilkenny'],
      'PL': <String>['warsaw', 'krakow', 'gdansk', 'wroclaw', 'poznan', 'lodz'],
      'HR': <String>['zagreb', 'split', 'dubrovnik', 'zadar', 'rijeka'],
      'NO': <String>['oslo', 'bergen', 'trondheim', 'stavanger', 'tromso'],
      'SE': <String>['stockholm', 'gothenburg', 'malmo', 'uppsala'],
      'FI': <String>['helsinki', 'turku', 'tampere', 'oulu', 'rovaniemi'],
      'CZ': <String>['prague', 'brno', 'ostrava', 'plzen', 'karlovy-vary'],
      'HU': <String>['budapest', 'debrecen', 'szeged', 'pecs', 'gyor'],
    };
    for (final entry in required.entries) {
      for (final cityKey in entry.value) {
        final city = stay22CatalogueCityByKey(
          countryCode: entry.key,
          cityKey: cityKey,
        );
        expect(city, isNotNull, reason: '${entry.key}/$cityKey');
      }
    }
  });

  test('aliases do not create duplicate city options', () {
    final portugal = stay22CityPickerOptions(
      countryCode: 'PT',
      languageCode: 'nl',
    );
    final labels = portugal.map((option) => option.value).toList();
    expect(labels.toSet().length, labels.length);
    expect(portugal.map((option) => option.label), contains('Lissabon'));
    expect(portugal.where((option) => option.value == 'lisbon'), hasLength(1));
    final lisbon = stay22CatalogueCityByKey(countryCode: 'PT', cityKey: 'lisbon')!;
    expect(lisbon.aliases, contains('Lisboa'));
    expect(lisbon.canonicalQueryName, 'Lisbon');
  });

  test('seeded taxonomy countries keep their existing selectors and capitals', () {
    for (final code in kStay22PriorityCountryCodes) {
      final identity = stay22CountryIdentityFor(
        countryCode: code,
        languageCode: 'nl',
      );
      expect(identity?.hasSeededTaxonomy, isTrue, reason: code);
      expect(identity?.showRegionSelector, isTrue, reason: code);
      expect(stay22RegionPickerOptions(countryCode: code, languageCode: 'nl'), isNotEmpty);
      expect(stay22CityPickerOptions(countryCode: code, languageCode: 'nl'), isNotEmpty);
    }
    expect(stay22CatalogueCountryByCode('BE')?.capitalKey, 'brussel');
    expect(stay22CatalogueCountryByCode('NL')?.capitalKey, 'amsterdam');
    expect(stay22CatalogueCountryByCode('ES')?.capitalKey, 'madrid');
  });

  test('coverage policy meets the minimum destination counts', () {
    int cityCount(String code) =>
        stay22CatalogueCountryByCode(code)!.allSettlements.length;
    expect(cityCount('AD'), inInclusiveRange(1, 5));
    expect(cityCount('MC'), inInclusiveRange(1, 5));
    expect(cityCount('PT'), greaterThanOrEqualTo(8));
    expect(cityCount('IT'), greaterThanOrEqualTo(12));
    expect(cityCount('GR'), greaterThanOrEqualTo(12));
    expect(cityCount('DK'), greaterThanOrEqualTo(5));
  });

  test('non-city-state cities keep a represented region', () {
    for (final code in exposedCodes) {
      if (kStay22CityStateCountryCodes.contains(code)) continue;
      final country = stay22CatalogueCountryByCode(code)!;
      expect(country.hideRegionSelector, isFalse, reason: code);
      for (final city in country.allSettlements) {
        expect(
          stay22RegionForCity(countryCode: code, cityKey: city.key),
          isNotNull,
          reason: '$code/${city.key}',
        );
      }
    }
  });
}
