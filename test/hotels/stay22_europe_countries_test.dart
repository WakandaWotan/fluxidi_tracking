import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/stay22_europe_countries.dart';

void main() {
  test('priority markets remain available and are not an allowlist', () {
    final options = stay22CountryPickerOptions('nl');
    final codes = options.map((option) => option.value).toList();
    expect(codes.toSet().length, codes.length);
    for (final code in kStay22PriorityCountryCodes) {
      expect(codes, contains(code));
    }
    expect(codes, contains('AT'));
    expect(codes, contains('IT'));
    expect(codes, contains('PT'));
    expect(codes, contains('CH'));
    expect(codes, isNot(contains('JP')));
  });

  test(
    'localized country labels resolve deterministically without duplicates',
    () {
      for (final language in <String>['nl', 'fr', 'en', 'es']) {
        final options = stay22CountryPickerOptions(language);
        final labels = options.map((option) => option.label).toList();
        expect(labels.toSet().length, labels.length);
        expect(
          options.map((option) => option.value).toSet().length,
          options.length,
        );
        final priorityLabels = options
            .where(
              (option) => kStay22PriorityCountryCodes.contains(option.value),
            )
            .map((option) => option.label)
            .toList();
        final sortedPriority = List<String>.from(priorityLabels)..sort();
        expect(priorityLabels, sortedPriority);
      }
      expect(
        stay22CountryPickerOptions('nl').map((option) => option.label),
        containsAll(<String>[
          'België',
          'Nederland',
          'Luxemburg',
          'Frankrijk',
          'Duitsland',
          'Spanje',
          'Verenigd Koninkrijk',
          'Oostenrijk',
        ]),
      );
      expect(stay22EnglishCountryName('AT'), 'Austria');
      expect(stay22EnglishCountryName('BE'), 'Belgium');
    },
  );

  test('structured ISO identity uses taxonomy without a second country table', () {
    final spain = stay22CountryIdentityFor(countryCode: 'ES', languageCode: 'nl');
    expect(spain?.isoCode, 'ES');
    expect(spain?.englishName, 'Spain');
    expect(spain?.localizedLabel, 'Spanje');
    expect(spain?.hasSeededTaxonomy, isTrue);

    final portugal = stay22CountryIdentityFor(
      countryCode: 'PT',
      languageCode: 'nl',
    );
    expect(portugal?.isoCode, 'PT');
    expect(portugal?.englishName, 'Portugal');
    expect(portugal?.hasSeededTaxonomy, isFalse);
  });

  test('localized names resolve to ISO and never slice two letters', () {
    expect(stay22ResolveIsoCountryCode('Denmark'), 'DK');
    expect(stay22ResolveIsoCountryCode('Denemarken'), 'DK');
    expect(stay22ResolveIsoCountryCode('Spain'), 'ES');
    expect(stay22ResolveIsoCountryCode('Spanje'), 'ES');
    expect(stay22ResolveIsoCountryCode('Germany'), 'DE');
    expect(stay22ResolveIsoCountryCode('Duitsland'), 'DE');
    expect(stay22ResolveIsoCountryCode('Netherlands'), 'NL');
    expect(stay22ResolveIsoCountryCode('Nederland'), 'NL');
    expect(stay22ResolveIsoCountryCode('Verenigd Koninkrijk'), 'GB');
    expect(stay22ResolveIsoCountryCode('Portugal'), 'PT');
    expect(stay22ResolveIsoCountryCode('SP'), isNull);
    expect(stay22ResolveIsoCountryCode('PO'), isNull);
    expect(stay22ResolveIsoCountryCode('NE'), isNull);
  });

  test('featured cards stay visible for ISO country codes', () {
    for (final iso in <String>['ES', 'DE', 'NL', 'GB', 'PT', 'DK']) {
      expect(
        stay22StayMatchesCountry(stayCountry: iso, selectedCountryCode: iso),
        isTrue,
      );
    }
    expect(
      stay22StayMatchesCountry(stayCountry: 'Spain', selectedCountryCode: 'ES'),
      isTrue,
    );
    expect(
      stay22StayMatchesCountry(stayCountry: 'SP', selectedCountryCode: 'ES'),
      isFalse,
    );
  });
}
