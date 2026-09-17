import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';

void main() {
  test('Ronse is treated as a place name so Mapbox can return the town', () {
    expect(limousineAddressLooksLikePlaceName('Ronse'), isTrue);
    expect(limousineAddressLooksLikeLocalityOnly('Ronse'), isTrue);
    expect(limousineAddressLooksLikePlaceName('Ronsevaaldreef 12'), isFalse);
    final uri = limousineMapboxPlacesUri(
      query: 'Ronse',
      token: 'test-token',
      types: limousineAddressLooksLikeLocalityOnly('Ronse')
          ? 'address,place,postcode'
          : 'address',
    );
    expect(uri.queryParameters['types'], 'address,place,postcode');
  });

  test('English UI keeps local Belgian place names in the search request', () {
    for (final place in const <String>['Gent', 'Kortrijk', 'Ronse']) {
      expect(limousineAddressLooksLikePlaceName(place), isTrue);
      expect(
        limousineMapboxForwardLanguage(query: place, uiLanguage: 'en'),
        isEmpty,
      );
      final uri = limousineMapboxPlacesUri(
        query: place,
        token: 'test-token',
        language: limousineMapboxForwardLanguage(
          query: place,
          uiLanguage: 'en',
        ),
        types: 'address,place,postcode',
      );
      expect(uri.queryParameters.containsKey('language'), isFalse);
      expect(uri.queryParameters['types'], 'address,place,postcode');
    }
  });

  test('street queries still send the UI language', () {
    final language = limousineMapboxForwardLanguage(
      query: 'Koekamerstraat 48A',
      uiLanguage: 'en',
    );
    expect(language, 'en');
    final uri = limousineMapboxPlacesUri(
      query: 'Koekamerstraat 48A',
      token: 'test-token',
      language: language,
    );
    expect(uri.queryParameters['language'], 'en');
  });

  test('ranking keeps Gent findable when Mapbox also returns Ghent', () {
    final ranked = limousineRankPlaceSuggestions(
      'Gent',
      const <LimousinePlaceSuggestion>[
        LimousinePlaceSuggestion(
          label: 'Ghent, Belgium',
          text: 'Ghent',
          matchingText: '',
          placeType: 'place',
        ),
        LimousinePlaceSuggestion(
          label: 'Gent, België',
          text: 'Gent',
          matchingText: 'Gent',
          placeType: 'place',
        ),
      ],
    );
    expect(limousinePlaceSuggestionMatchesQuery(ranked.first, 'Gent'), isTrue);
    expect(ranked.first.text, 'Gent');
  });
}
