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

  test('English UI still matches Dutch place names but asks for English labels', () {
    for (final place in const <String>['Gent', 'Kortrijk', 'Ronse']) {
      expect(limousineAddressLooksLikePlaceName(place), isTrue);
      expect(
        limousineMapboxForwardLanguage(query: place, uiLanguage: 'en'),
        'en,nl',
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
      expect(uri.queryParameters['language'], 'en,nl');
      expect(uri.queryParameters['types'], 'address,place,postcode');
    }
  });

  test('Dutch UI sends language=nl for Ronse so labels stay Dutch', () {
    expect(
      limousineMapboxForwardLanguage(query: 'Ronse', uiLanguage: 'nl'),
      'nl',
    );
    final uri = limousineMapboxPlacesUri(
      query: 'Ronse',
      token: 'test-token',
      language: limousineMapboxForwardLanguage(
        query: 'Ronse',
        uiLanguage: 'nl',
      ),
      types: 'address,place,postcode',
    );
    expect(uri.queryParameters['language'], 'nl');
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

  test('Gent ranks above Genthin, Genthod and Gentilly', () {
    final ranked = limousineRankPlaceSuggestions(
      'gent',
      const <LimousinePlaceSuggestion>[
        LimousinePlaceSuggestion(
          label: 'Genthin, Germany',
          text: 'Genthin',
          placeType: 'place',
          locality: 'Genthin',
          country: 'de',
        ),
        LimousinePlaceSuggestion(
          label: 'Genthod, Switzerland',
          text: 'Genthod',
          placeType: 'place',
          locality: 'Genthod',
          country: 'ch',
        ),
        LimousinePlaceSuggestion(
          label: 'Gentilly, France',
          text: 'Gentilly',
          placeType: 'place',
          locality: 'Gentilly',
          country: 'fr',
        ),
        LimousinePlaceSuggestion(
          label: 'Gent, België',
          text: 'Gent',
          matchingText: 'Gent',
          placeType: 'place',
          locality: 'Gent',
          country: 'be',
        ),
      ],
      contextCountry: 'be',
    );
    expect(ranked.first.text, 'Gent');
    expect(ranked.first.country, 'be');
  });

  test('Mapbox URI sends sibling proximity without locking the country', () {
    final uri = limousineMapboxPlacesUri(
      query: 'gent',
      token: 'test-token',
      country: '',
      types: 'address,place,postcode',
      proximityLat: 50.77205,
      proximityLon: 3.66942,
    );
    expect(uri.queryParameters.containsKey('country'), isFalse);
    expect(uri.queryParameters['proximity'], '3.669420,50.772050');
  });
}
