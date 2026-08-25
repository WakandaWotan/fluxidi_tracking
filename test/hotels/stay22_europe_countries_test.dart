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
}
