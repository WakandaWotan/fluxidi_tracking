import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote.dart';
import 'package:fluxidi_tracking/limousine/limousine_customer_quote_api.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_field.dart';
import 'package:fluxidi_tracking/limousine/limousine_hotel_lookup.dart';
import 'package:fluxidi_tracking/limousine/limousine_p2d4c1a_ux.dart';
import 'package:fluxidi_tracking/limousine/limousine_transfer_endpoint.dart';

Map<String, dynamic> _oudenaardePlace() => <String, dynamic>{
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'Feature',
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': <double>[3.604, 50.843],
      },
      'properties': <String, dynamic>{
        'name': 'Oudenaarde',
        'feature_type': 'place',
        'mapbox_id': 'dXJuOm1ieHBsYzpvdWRlbmFhcmRl',
        'bbox': <double>[3.54, 50.80, 3.67, 50.88],
        'context': <String, dynamic>{
          'country': <String, dynamic>{
            'country_code': 'be',
            'name': 'België',
          },
        },
      },
    },
  ],
};

Map<String, dynamic> _oudenaardeHotels() => <String, dynamic>{
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'Feature',
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': <double>[3.6071, 50.8442],
      },
      'properties': <String, dynamic>{
        'name': 'Leopold Hotel Oudenaarde',
        'full_address': 'De Broeistraat 2, 9700 Oudenaarde, België',
        'mapbox_id': 'dXJuOm1ieHBvaTpsZW9wb2xk',
        'poi_category': <String>['hotel', 'lodging'],
        'context': <String, dynamic>{
          'place': <String, dynamic>{'name': 'Oudenaarde'},
          'postcode': <String, dynamic>{'name': '9700'},
          'country': <String, dynamic>{
            'country_code': 'be',
            'name': 'België',
          },
        },
      },
    },
    <String, dynamic>{
      'type': 'Feature',
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': <double>[3.6098, 50.8411],
      },
      'properties': <String, dynamic>{
        'name': 'Hotel de la Gare',
        'full_address': 'Stationstraat 10, 9700 Oudenaarde, België',
        'mapbox_id': 'dXJuOm1ieHBvaTpnYXJl',
        'poi_category': <String>['hotel'],
        'context': <String, dynamic>{
          'place': <String, dynamic>{'name': 'Oudenaarde'},
          'postcode': <String, dynamic>{'name': '9700'},
          'country': <String, dynamic>{
            'country_code': 'be',
            'name': 'België',
          },
        },
      },
    },
  ],
};

Map<String, dynamic> _leopoldSuggest() => <String, dynamic>{
  'suggestions': <Map<String, dynamic>>[
    <String, dynamic>{
      'name': 'Leopold Hotel Oudenaarde',
      'mapbox_id': 'dXJuOm1ieHBvaTpsZW9wb2xk',
      'feature_type': 'poi',
      'full_address': 'De Broeistraat 2, 9700 Oudenaarde, België',
      'poi_category': <String>['hotel'],
      'context': <String, dynamic>{
        'place': <String, dynamic>{'name': 'Oudenaarde'},
        'postcode': <String, dynamic>{'name': '9700'},
        'country': <String, dynamic>{
          'country_code': 'be',
          'name': 'België',
        },
      },
    },
  ],
};

Map<String, dynamic> _leopoldRetrieve() => <String, dynamic>{
  'type': 'FeatureCollection',
  'features': <Map<String, dynamic>>[
    <String, dynamic>{
      'type': 'Feature',
      'geometry': <String, dynamic>{
        'type': 'Point',
        'coordinates': <double>[3.6071, 50.8442],
      },
      'properties': <String, dynamic>{
        'name': 'Leopold Hotel Oudenaarde',
        'full_address': 'De Broeistraat 2, 9700 Oudenaarde, België',
        'mapbox_id': 'dXJuOm1ieHBvaTpsZW9wb2xk',
        'poi_category': <String>['hotel'],
        'context': <String, dynamic>{
          'place': <String, dynamic>{'name': 'Oudenaarde'},
          'postcode': <String, dynamic>{'name': '9700'},
          'country': <String, dynamic>{
            'country_code': 'be',
            'name': 'België',
          },
        },
      },
    },
  ],
};

http.Client _searchBoxClient({
  bool fail = false,
  List<Uri>? captured,
}) {
  return MockClient((request) async {
    captured?.add(request.url);
    if (fail) throw Exception('network');
    final path = request.url.path;
    if (path.endsWith('/forward')) {
      return http.Response(jsonEncode(_oudenaardePlace()), 200);
    }
    if (path.contains('/category/')) {
      return http.Response(jsonEncode(_oudenaardeHotels()), 200);
    }
    if (path.endsWith('/suggest')) {
      return http.Response(jsonEncode(_leopoldSuggest()), 200);
    }
    if (path.contains('/retrieve/')) {
      return http.Response(jsonEncode(_leopoldRetrieve()), 200);
    }
    return http.Response('{"message":"not_found"}', 404);
  });
}

LimousineQuoteCreateDraft _draft() {
  return const LimousineQuoteCreateDraft(
    publicPartnerId: 'p1',
    offerId: 'off_1',
    vehicleId: 'veh_hummer',
    journeyType: 'point_to_point',
    from: 'Korenmarkt 1, Gent',
    to: 'Graslei 10, Gent',
    scheduledPickupIso: '2026-09-01T10:00:00Z',
    fromEndpoint: LimousineTransferEndpoint(
      kind: LimousineTransferEndpointKind.address,
      displayName: 'Korenmarkt 1, Gent',
      formattedAddress: 'Korenmarkt 1, Gent',
      latitude: 51.05,
      longitude: 3.72,
    ),
    toEndpoint: LimousineTransferEndpoint(
      kind: LimousineTransferEndpointKind.address,
      displayName: 'Graslei 10, Gent',
      formattedAddress: 'Graslei 10, Gent',
      latitude: 51.05,
      longitude: 3.73,
    ),
  );
}

void main() {
  test('token missing fails closed and is not a silent empty list', () async {
    final lookup = LimousineHotelLookup(token: '');
    final result = await lookup.search('Oudenaarde');
    expect(result.hadError, isTrue);
    expect(result.errorCode, 'token_missing');
    expect(result.suggestions, isEmpty);
  });

  test('Oudenaarde place search returns concrete nearby hotels', () async {
    final lookup = LimousineHotelLookup(
      token: 'pk.test',
      client: _searchBoxClient(),
    );
    final result = await lookup.search('Oudenaarde');
    expect(result.hadError, isFalse);
    expect(result.suggestions.length, greaterThanOrEqualTo(2));
    expect(
      result.suggestions.map((item) => item.name),
      containsAll(<String>['Leopold Hotel Oudenaarde', 'Hotel de la Gare']),
    );
    expect(
      result.suggestions.every((item) => item.city == 'Oudenaarde'),
      isTrue,
    );
    final endpoint = result.suggestions.first.toEndpoint();
    expect(endpoint.kind, LimousineTransferEndpointKind.hotel);
    expect(endpoint.hotelName, 'Leopold Hotel Oudenaarde');
    expect(endpoint.formattedAddress, contains('Oudenaarde'));
    expect(endpoint.city, 'Oudenaarde');
    expect(endpoint.postcode, '9700');
    expect(endpoint.countryCode, 'BE');
    expect(endpoint.providerPlaceId, isNotEmpty);
    expect(endpoint.manual, isFalse);
    expect(endpoint.ratehawkHotelId, isNull);
    expect(lookup.debugEvents.any((e) => e.phase == 'place'), isTrue);
    expect(
      lookup.debugEvents.any((e) => e.phase.startsWith('category_')),
      isTrue,
    );
    expect(
      lookup.debugEvents.any((e) => e.toString().contains('pk.test')),
      isFalse,
    );
  });

  test('hotel name uses the same session_token for suggest and retrieve', () async {
    final captured = <Uri>[];
    final lookup = LimousineHotelLookup(
      token: 'pk.test',
      client: _searchBoxClient(captured: captured),
    );
    final result = await lookup.search('Leopold Hotel Oudenaarde');
    expect(result.suggestions, isNotEmpty);
    await lookup.resolveSuggestion(
      LimousineHotelSuggestion(
        name: 'Leopold Hotel Oudenaarde',
        formattedAddress: 'De Broeistraat 2, 9700 Oudenaarde, België',
        providerPlaceId: 'dXJuOm1ieHBvaTpsZW9wb2xk',
        sessionToken: result.sessionToken,
        needsRetrieve: true,
      ),
    );
    final suggest = captured.firstWhere((uri) => uri.path.endsWith('/suggest'));
    final retrieve = captured.firstWhere((uri) => uri.path.contains('/retrieve/'));
    expect(suggest.queryParameters['session_token'], result.sessionToken);
    expect(retrieve.queryParameters['session_token'], result.sessionToken);
    expect(suggest.queryParameters['session_token'], isNotEmpty);
    expect(suggest.toString().contains('access_token'), isTrue);
  });

  test('selected hotel fills the existing transfer endpoint', () {
    final suggestion = parseLimousineSearchBoxFeature(
      _oudenaardeHotels()['features'][0],
    )!;
    final endpoint = suggestion.toEndpoint();
    expect(limousineHotelEndpointIsUsable(endpoint), isTrue);
    expect(endpoint.manual, isFalse);
    expect(endpoint.ratehawkHotelId, isNull);
    expect(endpoint.latitude, closeTo(50.8442, 0.0001));
    expect(endpoint.longitude, closeTo(3.6071, 0.0001));
  });

  testWidgets('stale hotel results do not overwrite a newer query', (tester) async {
    var searches = 0;
    final lookup = LimousineHotelLookup(
      searchOverride: (query, language) async {
        searches += 1;
        if (query.toLowerCase().contains('oudenaarde')) {
          await Future<void>.delayed(const Duration(milliseconds: 40));
          return LimousineHotelLookupResult(
            suggestions: parseLimousineSearchBoxFeatures(
              _oudenaardeHotels()['features'],
            ),
          );
        }
        return const LimousineHotelLookupResult();
      },
    );
    final controller = LimousineHotelFieldController(
      lookup: lookup,
      debounce: const Duration(milliseconds: 10),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousineHotelField(
            controller: controller,
            label: 'Hotel',
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    controller.onTextChanged('Oudenaarde');
    await tester.pump(const Duration(milliseconds: 15));
    controller.onTextChanged('Xx');
    await tester.pump(const Duration(milliseconds: 80));
    expect(searches, 2);
    expect(controller.suggestions, isEmpty);
    expect(find.byKey(kLimousineHotelEmptyKey), findsOneWidget);
    controller.dispose();
  });

  testWidgets('network error keeps the current hotel draft and shows retry', (
    tester,
  ) async {
    final lookup = LimousineHotelLookup(
      token: 'pk.test',
      client: _searchBoxClient(fail: true),
    );
    final controller = LimousineHotelFieldController(
      lookup: lookup,
      debounce: Duration.zero,
    );
    controller.selected = limousineManualHotelEndpoint('Korenmarkt 1, Gent');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LimousineHotelField(
            controller: controller,
            label: 'Hotel',
            tokens: LimousineUxTokens.fromSurface(background: Colors.white),
            language: AppLanguage.nl,
          ),
        ),
      ),
    );
    controller.textController.text = 'Oudenaarde';
    controller.onTextChanged('Oudenaarde');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.byKey(kLimousineHotelErrorKey), findsOneWidget);
    expect(controller.selected, isNull);
    expect(controller.textController.text, 'Oudenaarde');
    controller.dispose();
  });

  test('manual hotel fallback stays manual true', () {
    final manual = limousineManualHotelEndpoint('Markt 1, 9700 Oudenaarde');
    expect(manual.manual, isTrue);
    expect(manual.kind, LimousineTransferEndpointKind.hotel);
    expect(limousineHotelEndpointIsUsable(manual), isTrue);
  });

  test('Worker HTTP statuses stay visible and are not collapsed to network', () async {
    Future<void> expectStatus(int status, String error, String stage) async {
      final gateway = HttpLimousineCustomerQuoteGateway(
        bookingBaseUrl: 'https://booking.test',
        authHeaders: () async => const <String, String>{},
        client: MockClient((request) async {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'ok': false,
              'error': error,
              'stage': stage,
              'request_id': 'lsub_$status',
            }),
            status,
          );
        }),
      );
      try {
        await gateway.createRequest(_draft());
        fail('expected $status');
      } on LimousineCustomerQuoteException catch (err) {
        expect(err.code, error);
        expect(err.statusCode, status);
        expect(err.stage, stage);
        expect(err.requestId, 'lsub_$status');
        expect(err.code, isNot('network'));
      }
    }

    await expectStatus(400, 'invalid_request', 'validation');
    await expectStatus(403, 'not_found', 'allowlist');
    await expectStatus(404, 'manual_quote_gate_off', 'gate');
    await expectStatus(409, 'stale_revision', 'validation');
    await expectStatus(422, 'invalid_endpoint', 'endpoint');
    await expectStatus(500, 'internal_error', 'persist_primary');
  });

  test('success requires quote_request_id even on HTTP 200', () async {
    final gateway = HttpLimousineCustomerQuoteGateway(
      bookingBaseUrl: 'https://booking.test',
      authHeaders: () async => const <String, String>{},
      client: MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'request_id': 'lsub_empty',
            'quote_request': <String, dynamic>{'state': 'requested'},
          }),
          200,
        );
      }),
    );
    try {
      await gateway.createRequest(_draft());
      fail('expected invalid_response');
    } on LimousineCustomerQuoteException catch (err) {
      expect(err.code, 'invalid_response');
      expect(err.stage, 'parse_response');
      expect(err.requestId, 'lsub_empty');
    }
  });

  test('top-level quote_request_id is accepted as success', () async {
    final gateway = HttpLimousineCustomerQuoteGateway(
      bookingBaseUrl: 'https://booking.test',
      authHeaders: () async => const <String, String>{},
      client: MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'quote_request_id': 'limq_top',
            'request_id': 'lsub_ok',
            'quote_request': <String, dynamic>{
              'quote_request_id': 'limq_top',
              'state': 'requested',
              'revision': 1,
              'offer_id': 'off_1',
              'journey_type': 'point_to_point',
              'scheduled_pickup_iso': '2026-09-01T10:00:00.000Z',
            },
          }),
          200,
        );
      }),
    );
    final created = await gateway.createRequest(_draft());
    expect(created.request.quoteRequestId, 'limq_top');
  });
}
