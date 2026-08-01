import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';
import 'package:http/http.dart' as http;

class _CapturingHttpClient extends http.BaseClient {
  String? lastBody;
  String? lastPath;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastPath = request.url.path;
    if (request is http.Request) {
      lastBody = request.body;
    }
    final payload = jsonEncode(<String, dynamic>{
      'ok': true,
      'cache': 'miss',
      'distance_m': 100,
      'duration_s': 20,
      'geometry': {
        'type': 'LineString',
        'coordinates': [
          [4.40, 50.85],
          [4.41, 50.86],
        ],
      },
      'maneuvers': <dynamic>[],
      'legs': <dynamic>[],
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(payload)),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

void main() {
  group('NAV-SIGNAL-P0A1-WORKER-LANGUAGE-PARITY', () {
    test('normalize allowlist and locale forms', () {
      expect(normalizeNavigationWorkerLanguage('en'), 'en');
      expect(normalizeNavigationWorkerLanguage('EN-BE'), 'en');
      expect(normalizeNavigationWorkerLanguage(' fr_FR '), 'fr');
      expect(normalizeNavigationWorkerLanguage('pt'), 'pt');
      expect(normalizeNavigationWorkerLanguage('BE'), isNull);
      expect(normalizeNavigationWorkerLanguage('de'), isNull);
      expect(normalizeNavigationWorkerLanguage(''), isNull);
      expect(normalizeNavigationWorkerLanguage(null), isNull);
    });

    test('A) UI=en + country=BE => body.language=en on /route', () async {
      final httpClient = _CapturingHttpClient();
      final client = DriverNavigationWorkerClient(
        baseUrl: 'https://nav.example.invalid',
        httpClient: httpClient,
      );
      await client.route(
        origin: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'BE',
        language: 'en',
      );
      expect(httpClient.lastPath, '/route');
      final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body['country'], 'BE');
      expect(body['language'], 'en');
    });

    test('B) UI=fr + country=BE => body.language=fr on /route', () async {
      final httpClient = _CapturingHttpClient();
      final client = DriverNavigationWorkerClient(
        baseUrl: 'https://nav.example.invalid',
        httpClient: httpClient,
      );
      await client.route(
        origin: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'BE',
        language: 'fr',
      );
      final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body['language'], 'fr');
    });

    test('C) UI=es + country=BE => body.language=es on /route', () async {
      final httpClient = _CapturingHttpClient();
      final client = DriverNavigationWorkerClient(
        baseUrl: 'https://nav.example.invalid',
        httpClient: httpClient,
      );
      await client.route(
        origin: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'BE',
        language: 'es',
      );
      final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body['language'], 'es');
    });

    test(
      'D) UI=nl + country=FR => body.language=nl (country not overwrite)',
      () async {
        final httpClient = _CapturingHttpClient();
        final client = DriverNavigationWorkerClient(
          baseUrl: 'https://nav.example.invalid',
          httpClient: httpClient,
        );
        await client.route(
          origin: const DriverLonLat(4.40, 50.85),
          destination: const DriverLonLat(4.41, 50.86),
          country: 'FR',
          language: 'nl',
        );
        final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
        expect(body['country'], 'FR');
        expect(body['language'], 'nl');
      },
    );

    test('G) /reroute also sends explicit language', () async {
      final httpClient = _CapturingHttpClient();
      final client = DriverNavigationWorkerClient(
        baseUrl: 'https://nav.example.invalid',
        httpClient: httpClient,
      );
      await client.reroute(
        current: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'BE',
        language: 'en',
        reason: 'off_route',
      );
      expect(httpClient.lastPath, '/reroute');
      final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body['language'], 'en');
      expect(body['country'], 'BE');
      expect(body['reason'], 'off_route');
    });

    test('G2) /reroute preserves opposite_direction and wrong_street', () async {
      final httpClient = _CapturingHttpClient();
      final client = DriverNavigationWorkerClient(
        baseUrl: 'https://nav.example.invalid',
        httpClient: httpClient,
      );
      await client.reroute(
        current: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'BE',
        reason: 'opposite_direction_strong',
      );
      var body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body['reason'], 'opposite_direction');

      await client.reroute(
        current: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'BE',
        reason: 'wrong_street',
      );
      body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body['reason'], 'wrong_street');
    });

    test('I) older request without language omits the field', () async {
      final httpClient = _CapturingHttpClient();
      final client = DriverNavigationWorkerClient(
        baseUrl: 'https://nav.example.invalid',
        httpClient: httpClient,
      );
      await client.route(
        origin: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'BE',
      );
      final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body.containsKey('language'), isFalse);
      expect(body['country'], 'BE');
    });

    test('unsupported language is not forwarded in the body', () async {
      final httpClient = _CapturingHttpClient();
      final client = DriverNavigationWorkerClient(
        baseUrl: 'https://nav.example.invalid',
        httpClient: httpClient,
      );
      await client.route(
        origin: const DriverLonLat(4.40, 50.85),
        destination: const DriverLonLat(4.41, 50.86),
        country: 'FR',
        language: 'de',
      );
      final body = jsonDecode(httpClient.lastBody!) as Map<String, dynamic>;
      expect(body.containsKey('language'), isFalse);
      expect(body['country'], 'FR');
    });
  });
}
