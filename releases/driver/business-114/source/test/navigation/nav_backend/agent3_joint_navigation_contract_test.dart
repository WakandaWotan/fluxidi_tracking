import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/navigation/driver_navigation_models.dart';
import 'package:fluxidi_tracking/navigation/nav_backend/driver_navigation_worker_client.dart';

void main() {
  final base = Platform.environment['AGENT3_NAV_TEST_URL'];
  if (base == null) {
    test(
      'joint contract requires the local Agent 3 Navigation fixture',
      () {},
      skip:
          'Start navigation-auth/joint-server.mjs with its overlay loader and set AGENT3_NAV_TEST_URL',
    );
    return;
  }
  DriverNavigationWorkerClient client([String token = 'SYNTHETIC_DRIVER']) =>
      DriverNavigationWorkerClient(
        baseUrl: base,
        loadHeaders: () => {'Authorization': 'Bearer $token'},
      );
  const start = DriverLonLat(4, 51), end = DriverLonLat(4.001, 51);
  setUpAll(() async {
    expect((await http.get(Uri.parse('$base/__refresh'))).statusCode, 200);
  });
  test(
    'B111 route and reroute accept real relay/HTTP/formatter contract',
    () async {
      final c = client();
      final preview = await c.route(
        origin: start,
        destination: end,
        country: 'BE',
        bookingId: 'B',
        operationalLeg: 'primary',
        originLabel: 'Teststraat 1, 9000 Gent',
        destinationLabel: 'Teststraat 2, 9000 Gent',
        language: 'nl',
      );
      expect(
        preview,
        isNotNull,
        reason: 'same B111 contract must work without weakening proof',
      );
      expect(preview!.distanceMeters, 100);
      expect(preview.durationSeconds, 10);
      expect(preview.coords.first.lon, 4);
      expect(preview.coords.first.lat, 51);
      expect(preview.legs.single['steps'], isNotEmpty);
      final reroute = await c.reroute(
        current: start,
        destination: end,
        country: 'BE',
        reason: 'wrong_exit',
        bookingId: 'B',
        operationalLeg: 'primary',
        originInput: {
          'kind': 'gps',
          'capturedAt': DateTime.now().millisecondsSinceEpoch,
          'accuracyMeters': 8,
          'speedMetersPerSecond': 3,
          'headingDegrees': 90,
        },
        destinationLabel: 'Teststraat 2, 9000 Gent',
      );
      expect(reroute, isNotNull);
      expect(reroute!.distanceMeters, 100);
      expect(reroute.toMapboxDirectionsShape()['routes'], isNotEmpty);
      expect((await http.get(Uri.parse('$base/__start'))).statusCode, 200);
      final started = await c.route(
        origin: start,
        destination: end,
        country: 'BE',
        bookingId: 'B',
        operationalLeg: 'primary',
        tripId: 'SESSION',
      );
      expect(started, isNotNull);
      expect(
        await c.route(
          origin: start,
          destination: end,
          country: 'BE',
          bookingId: 'B',
          operationalLeg: 'primary',
          tripId: 'WRONG',
        ),
        isNull,
      );
    },
  );
  test('stale GPS and rejected session remain blocked', () async {
    expect(
      await client().route(
        origin: start,
        destination: end,
        country: 'BE',
        originInput: {
          'kind': 'gps',
          'capturedAt': DateTime.now().millisecondsSinceEpoch - 31000,
          'accuracyMeters': 8,
        },
      ),
      isNull,
    );
    expect(
      await client(
        'FOREIGN',
      ).route(origin: start, destination: end, country: 'BE'),
      isNull,
    );
  });
}
