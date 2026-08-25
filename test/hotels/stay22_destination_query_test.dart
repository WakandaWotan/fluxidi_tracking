import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/hotels/stay22_europe_countries.dart';

void main() {
  test('query priority is free text, then city+region, then country', () {
    final freeText = stay22ResolveDestinationQuery(
      countryCode: 'PT',
      regionKey: 'porto',
      cityKey: 'porto',
      freeText: 'Sintra',
    );
    expect(freeText.destination, 'Sintra');
    expect(freeText.city, 'Porto');
    expect(freeText.region, 'Porto District');
    expect(freeText.countryCode, 'PT');
    expect(freeText.countryEnglish, 'Portugal');

    final cityRegion = stay22ResolveDestinationQuery(
      countryCode: 'PT',
      regionKey: 'lisboa',
      cityKey: 'lisbon',
    );
    expect(cityRegion.destination, isNull);
    expect(cityRegion.city, 'Lisbon');
    expect(cityRegion.region, 'Lisbon District');

    final countryOnly = stay22ResolveDestinationQuery(countryCode: 'DK');
    expect(countryOnly.countryCode, 'DK');
    expect(countryOnly.countryEnglish, 'Denmark');
    expect(countryOnly.city, isNull);
    expect(countryOnly.region, isNull);
  });

  test('country change resets incompatible city and region', () {
    final next = stay22ApplyCountrySelection(
      const Stay22LocationSelection(
        countryCode: 'PT',
        regionKey: 'lisboa',
        cityKey: 'lisbon',
        freeText: 'Lisbon',
      ),
      'IT',
    );
    expect(next.countryCode, 'IT');
    expect(next.regionKey, isEmpty);
    expect(next.cityKey, isEmpty);
  });

  test('region change filters an incompatible city and city sets its region', () {
    final afterRegion = stay22ApplyRegionSelection(
      const Stay22LocationSelection(
        countryCode: 'PT',
        regionKey: 'lisboa',
        cityKey: 'lisbon',
      ),
      'porto',
    );
    expect(afterRegion.regionKey, 'porto');
    expect(afterRegion.cityKey, isEmpty);

    final afterCity = stay22ApplyCitySelection(
      const Stay22LocationSelection(countryCode: 'IT', regionKey: ''),
      'milan',
    );
    expect(afterCity.cityKey, 'milan');
    expect(afterCity.regionKey, 'lombardy');
  });

  test('free text overrides without destroying the catalogue selection', () {
    const selected = Stay22LocationSelection(
      countryCode: 'PT',
      regionKey: 'lisboa',
      cityKey: 'lisbon',
    );
    final withText = stay22ApplyFreeText(selected, 'Coimbra');
    expect(withText.cityKey, 'lisbon');
    expect(withText.regionKey, 'lisboa');
    expect(withText.freeText, 'Coimbra');
    final cleared = stay22ApplyFreeText(withText, '');
    expect(cleared.cityKey, 'lisbon');
    expect(cleared.freeText, isEmpty);
    final resolved = stay22ResolveDestinationQuery(
      countryCode: cleared.countryCode,
      regionKey: cleared.regionKey,
      cityKey: cleared.cityKey,
      freeText: cleared.freeText,
    );
    expect(resolved.city, 'Lisbon');
    expect(resolved.destination, isNull);
  });

  test('region and city dialogs are never empty for catalogue countries', () {
    for (final code in stay22CountryPickerOptions('en').map((o) => o.value)) {
      final cities = stay22CityPickerOptions(
        countryCode: code,
        languageCode: 'nl',
      );
      expect(cities, isNotEmpty, reason: code);
      if (!kStay22CityStateCountryCodes.contains(code)) {
        expect(
          stay22RegionPickerOptions(countryCode: code, languageCode: 'nl'),
          isNotEmpty,
          reason: code,
        );
      }
    }
  });

  test('Stay22 address uses canonical English names', () {
    final resolved = stay22ResolveDestinationQuery(
      countryCode: 'PT',
      cityKey: 'lisbon',
      regionKey: 'lisboa',
    );
    expect(
      stay22EffectiveStay22Address(resolved: resolved),
      'Lisbon, Lisbon District, Portugal',
    );
  });
}
