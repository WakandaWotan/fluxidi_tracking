import 'dart:convert';

import 'package:fluxidi_customer_core/fluxidi_customer_core.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

Map<String, dynamic> _ronseFeature() => <String, dynamic>{
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
};

Map<String, dynamic> _koekamerFeature() => <String, dynamic>{
  'id': 'address.koekamer-48a',
  'place_name': 'Koekamerstraat 48A, 9688 Schorisse, East Flanders, Belgium',
  'place_type': <String>['address'],
  'center': <double>[3.66942, 50.77205],
};

void main() {
  test('Ronse Dutch display keeps English identity and coordinates', () {
    final parsed = parseFluxidiAddressFeatures(
      <Map<String, dynamic>>[_ronseFeature()],
      language: 'nl',
    );
    expect(parsed, hasLength(1));
    expect(parsed.first.label, 'Ronse, Oost-Vlaanderen, België');
    expect(parsed.first.identityLabel, 'Ronse, East Flanders, Belgium');
    expect(parsed.first.lat, 50.7452);
    expect(parsed.first.lon, 3.6003);
    final value = parsed.first.toAddressValue();
    expect(value.displayText, 'Ronse, Oost-Vlaanderen, België');
    expect(value.canonicalLabel, 'Ronse, East Flanders, Belgium');
    expect(value.lat, 50.7452);
    expect(value.lon, 3.6003);
  });

  test('Koekamerstraat keeps house number and addition after localize', () {
    final parsed = parseFluxidiAddressFeatures(
      <Map<String, dynamic>>[_koekamerFeature()],
      language: 'nl',
    );
    expect(parsed.first.label, contains('Koekamerstraat 48A'));
    expect(parsed.first.label, contains('Oost-Vlaanderen'));
    expect(parsed.first.label, contains('België'));
    expect(parsed.first.lat, 50.77205);
    expect(parsed.first.lon, 3.66942);
  });

  test('language switch only rewrites the display label', () {
    final value = parseFluxidiAddressFeatures(
      <Map<String, dynamic>>[_koekamerFeature()],
      language: 'en',
    ).first.toAddressValue();
    final dutch = value.copyWith(
      displayText: fluxidiLocalizeAddressLabel(value.canonicalLabel, 'nl'),
    );
    expect(dutch.displayText, contains('Oost-Vlaanderen'));
    expect(dutch.canonicalLabel, value.canonicalLabel);
    expect(dutch.lat, value.lat);
    expect(dutch.lon, value.lon);
    expect(dutch.placeId, value.placeId);
    final back = dutch.copyWith(
      displayText: fluxidiLocalizeAddressLabel(dutch.canonicalLabel, 'en'),
    );
    expect(back.lat, value.lat);
    expect(back.lon, value.lon);
    expect(back.canonicalLabel, value.canonicalLabel);
  });

  test('search cache and request language stay separate', () async {
    final uris = <Uri>[];
    final client = FluxidiAddressSearchClient(
      token: 'pk.test',
      httpGet: (uri) async {
        uris.add(uri);
        return http.Response(jsonEncode(<String, dynamic>{
          'features': <Map<String, dynamic>>[_ronseFeature()],
        }), 200);
      },
    );

    await client.search('Ronse', language: 'en');
    await client.search('Ronse', language: 'nl');
    await client.search('Ronse', language: 'en');

    expect(uris, hasLength(2));
    expect(uris[0].queryParameters['language'], 'en');
    expect(uris[1].queryParameters['language'], 'nl');
  });

  test('a late previous-language answer does not win the current search', () async {
    var releaseEnglish = false;
    final client = FluxidiAddressSearchClient(
      token: 'pk.test',
      httpGet: (uri) async {
        if (uri.queryParameters['language'] == 'en') {
          while (!releaseEnglish) {
            await Future<void>.delayed(const Duration(milliseconds: 5));
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'features': <Map<String, dynamic>>[
                <String, dynamic>{
                  'id': 'place.en',
                  'place_name': 'Ronse, East Flanders, Belgium',
                  'place_type': <String>['place'],
                  'center': <double>[3.6, 50.7],
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'features': <Map<String, dynamic>>[_ronseFeature()],
          }),
          200,
        );
      },
    );

    final english = client.search('Ronse', language: 'en');
    final dutch = client.search('Ronse', language: 'nl');
    final dutchResult = await dutch;
    expect(dutchResult.first.label, contains('Oost-Vlaanderen'));
    releaseEnglish = true;
    final englishResult = await english;
    expect(englishResult, isEmpty);
    final cachedEnglish = await client.search('Ronse', language: 'en');
    expect(cachedEnglish.first.identityLabel, contains('East Flanders'));
  });

  test('GPS reverse sends language and localizes the label', () async {
    late Uri seen;
    final client = FluxidiAddressSearchClient(
      token: 'pk.test',
      httpGet: (uri) async {
        seen = uri;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'features': <Map<String, dynamic>>[_koekamerFeature()],
          }),
          200,
        );
      },
    );
    final result = await client.reverse(
      lat: 50.77205,
      lon: 3.66942,
      language: 'nl',
    );
    expect(seen.queryParameters['language'], 'nl');
    expect(seen.path, contains('3.669420,50.772050'));
    expect(result, isNotNull);
    expect(result!.label, contains('Koekamerstraat 48A'));
    expect(result.label, contains('België'));
    expect(result.lat, 50.77205);
    expect(result.lon, 3.66942);
  });

  test('a previously stored English label localizes without a new search', () {
    expect(
      fluxidiLocalizeAddressLabel('Ronse, East Flanders, Belgium', 'nl'),
      'Ronse, Oost-Vlaanderen, België',
    );
  });

  test('bare Belgian postcode is not rewritten into English Belgium', () {
    expect(fluxidiNormalizeAddressQuery('9688'), '9688');
  });
}
