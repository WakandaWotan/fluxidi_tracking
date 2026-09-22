import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_label_language.dart';
import 'package:fluxidi_tracking/limousine/limousine_address_lookup.dart';
import 'package:fluxidi_tracking/customer_profile/customer_stored_address.dart';

void main() {
  test('Ronse English label becomes Oost-Vlaanderen and België', () {
    expect(
      limousineLocalizeAddressLabel(
        'Ronse, East Flanders, Belgium',
        'nl',
      ),
      'Ronse, Oost-Vlaanderen, België',
    );
  });

  test('Koekamerstraat keeps house number and addition', () {
    expect(
      limousineLocalizeAddressLabel(
        'Koekamerstraat 48A, 9688 Schorisse, East Flanders, Belgium',
        'nl',
      ),
      'Koekamerstraat 48A, 9688 Schorisse, Oost-Vlaanderen, België',
    );
  });

  test('language switch does not invent a street translation', () {
    const street = 'Koekamerstraat 48A, 9688 Schorisse, Oost-Vlaanderen, België';
    expect(
      limousineLocalizeAddressLabel(street, 'en'),
      'Koekamerstraat 48A, 9688 Schorisse, East Flanders, Belgium',
    );
    expect(limousineLocalizeAddressLabel(street, 'en'), contains('Koekamerstraat'));
    expect(limousineLocalizeAddressLabel(street, 'fr'), contains('Koekamerstraat'));
  });

  test('Mapbox English place_name is displayed in the requested language', () {
    final suggestions = parseLimousineMapboxPlaceFeatures(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'place.ronse',
          'place_name': 'Ronse, East Flanders, Belgium',
          'place_name_nl': 'Ronse, Oost-Vlaanderen, België',
          'text': 'Ronse',
          'place_type': <String>['place'],
          'center': <double>[3.6003, 50.7452],
          'context': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'region.1',
              'text': 'East Flanders',
              'text_nl': 'Oost-Vlaanderen',
            },
            <String, dynamic>{
              'id': 'country.be',
              'text': 'Belgium',
              'text_nl': 'België',
              'short_code': 'be',
            },
          ],
        },
      ],
      language: 'nl',
    );

    expect(suggestions, hasLength(1));
    expect(suggestions.first.label, 'Ronse, Oost-Vlaanderen, België');
    expect(suggestions.first.lat, 50.7452);
    expect(suggestions.first.lon, 3.6003);
    expect(suggestions.first.placeId, 'place.ronse');
  });

  test('GPS reverse URI always sends the app language', () {
    final uri = limousineMapboxReverseGeocodeUri(
      lat: 50.745200,
      lon: 3.600300,
      token: 'test-token',
      language: 'nl',
    );
    expect(uri.queryParameters['language'], 'nl');
    expect(uri.path, contains('3.600300,50.745200'));
  });

  test('a stored English label is only rewritten for display', () {
    const stored = CustomerStoredAddress(
      label: 'Ronse, East Flanders, Belgium',
      lat: 50.7452,
      lon: 3.6003,
      placeId: 'place.ronse',
    );
    expect(
      composeCustomerStoredAddressLabel(stored, language: 'nl'),
      'Ronse, Oost-Vlaanderen, België',
    );
    expect(stored.label, 'Ronse, East Flanders, Belgium');
    expect(stored.lat, 50.7452);
    expect(stored.lon, 3.6003);
    expect(stored.placeId, 'place.ronse');
  });

  test('changing display language keeps coordinates and house number', () async {
    final lookup = LimousinePlaceLookup(
      searchOverride: (query, language) async {
        return const LimousinePlaceLookupResult(
          suggestions: <LimousinePlaceSuggestion>[
            LimousinePlaceSuggestion(
              label: 'Koekamerstraat 48A, 9688 Schorisse, East Flanders, Belgium',
              lat: 50.77205,
              lon: 3.66942,
              placeId: 'address.koekamer-48a',
              placeType: 'address',
            ),
          ],
        );
      },
    );
    final controller = LimousineAddressFieldController(
      lookup: lookup,
      fieldId: 'destination',
      language: 'en',
    );
    controller.selectSuggestion(
      const LimousinePlaceSuggestion(
        label: 'Koekamerstraat 48A, 9688 Schorisse, East Flanders, Belgium',
        lat: 50.77205,
        lon: 3.66942,
        placeId: 'address.koekamer-48a',
        placeType: 'address',
      ),
    );
    final searchesBefore = lookup.searchesStarted;
    controller.setDisplayLanguage('nl');
    expect(controller.value.displayText, contains('Oost-Vlaanderen'));
    expect(controller.value.displayText, contains('48A'));
    expect(controller.value.lat, 50.77205);
    expect(controller.value.lon, 3.66942);
    expect(controller.value.placeId, 'address.koekamer-48a');
    expect(
      controller.value.canonicalLabel,
      'Koekamerstraat 48A, 9688 Schorisse, East Flanders, Belgium',
    );
    expect(lookup.searchesStarted, searchesBefore);
    controller.setDisplayLanguage('nl');
    expect(lookup.searchesStarted, searchesBefore);
    controller.dispose();
  });
}
