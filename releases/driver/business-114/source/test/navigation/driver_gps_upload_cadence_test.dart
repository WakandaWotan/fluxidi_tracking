import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/driver/planned_tracking_lifecycle.dart';
import 'package:fluxidi_tracking/navigation/nav_engine/nav_background_dispatcher.dart';

void main() {
  late DateTime clock;
  late DriverGpsUploadCadence gate;
  setUp(() {
    clock = DateTime.utc(2026, 9, 26);
    gate = DriverGpsUploadCadence(now: () => clock);
  });
  test(
    '500ms samples: at most 8 attempts per minute, newest sample only',
    () async {
      final sent = <int>[];
      for (var i = 0; i < 120; i++) {
        await gate.send(
          capturedAt: clock,
          request: () async {
            sent.add(i);
            return http.Response('{}', 200);
          },
        );
        clock = clock.add(const Duration(milliseconds: 500));
      }
      expect(sent, [0, 16, 32, 48, 64, 80, 96, 112]);
    },
  );
  for (final retry in [8, 24, 60])
    test('429 $retry seconds is transient and bounded', () async {
      var calls = 0;
      await gate.send(
        capturedAt: clock,
        request: () async {
          calls++;
          return http.Response('{"retry_after_seconds":$retry}', 429);
        },
      );
      for (var i = 1; i < retry * 2; i++) {
        clock = clock.add(const Duration(milliseconds: 500));
        expect(
          await gate.send(
            capturedAt: clock,
            request: () async {
              calls++;
              return http.Response('{}', 200);
            },
          ),
          isNull,
        );
      }
      clock = clock.add(const Duration(milliseconds: 500));
      expect(
        (await gate.send(
          capturedAt: clock,
          request: () async {
            calls++;
            return http.Response('{}', 200);
          },
        ))!.statusCode,
        200,
      );
      expect(calls, 2);
    });
  test('429 header and missing retry hint: no aggressive retry', () async {
    await gate.send(
      capturedAt: clock,
      request: () async =>
          http.Response('{}', 429, headers: {'retry-after': '20'}),
    );
    clock = clock.add(const Duration(seconds: 19));
    expect(
      await gate.send(
        capturedAt: clock,
        request: () async => http.Response('{}', 200),
      ),
      isNull,
    );
    clock = clock.add(const Duration(seconds: 1));
    await gate.send(
      capturedAt: clock,
      request: () async => http.Response('invalid', 429),
    );
    clock = clock.add(const Duration(seconds: 59));
    expect(
      await gate.send(
        capturedAt: clock,
        request: () async => http.Response('{}', 200),
      ),
      isNull,
    );
  });
  test(
    'network failures back off 8/16/32 and recover using a fresh sample',
    () async {
      for (final seconds in [8, 16, 32, 32]) {
        await expectLater(
          gate.send(
            capturedAt: clock,
            request: () async => throw TimeoutException('offline'),
          ),
          throwsA(isA<TimeoutException>()),
        );
        clock = clock.add(Duration(seconds: seconds - 1));
        expect(
          await gate.send(
            capturedAt: clock,
            request: () async => http.Response('{}', 200),
          ),
          isNull,
        );
        clock = clock.add(const Duration(seconds: 1));
      }
      expect(
        (await gate.send(
          capturedAt: clock,
          request: () async => http.Response('{}', 200),
        ))!.statusCode,
        200,
      );
      clock = clock.add(const Duration(seconds: 8));
      expect(
        (await gate.send(
          capturedAt: clock,
          request: () async => http.Response('{}', 200),
        ))!.statusCode,
        200,
      );
    },
  );
  test(
    'dispatcher bounded pending sample cannot burst after slow request',
    () async {
      final first = Completer<http.Response>();
      final sent = <int>[];
      final dispatcher = NavBackgroundDispatcher<int>(
        runner: (sample) async {
          await gate.send(
            capturedAt: clock,
            request: () {
              sent.add(sample);
              return sample == 0
                  ? first.future
                  : Future.value(http.Response('{}', 200));
            },
          );
        },
      );
      dispatcher.enqueue(0);
      await Future<void>.delayed(Duration.zero);
      for (var i = 1; i <= 40; i++) {
        clock = clock.add(const Duration(milliseconds: 500));
        dispatcher.enqueue(i);
      }
      first.complete(http.Response('{}', 200));
      await Future<void>.delayed(Duration.zero);
      expect(sent, [0]);
      clock = clock.add(const Duration(seconds: 8));
      dispatcher.enqueue(41);
      await Future<void>.delayed(Duration.zero);
      expect(sent, [0, 41]);
      dispatcher.dispose();
    },
  );
  test('stale or future samples never uploaded', () async {
    for (final delta in [-31, 6])
      expect(
        await gate.send(
          capturedAt: clock.add(Duration(seconds: delta)),
          request: () async => throw StateError('must not send'),
        ),
        isNull,
      );
    expect(DriverGpsUploadCadence.validSample(91, 4, 5), false);
    expect(DriverGpsUploadCadence.validSample(51, 4, 151), false);
  });

  test(
    'START drains presence and preserves cooldown without a second upload',
    () async {
      final held = Completer<http.Response>();
      final paths = <String>[];
      final caller = PlannedTrackingLifecycle(
        bookingBaseUrl: 'https://booking',
        trackingBaseUrl: 'https://tracking',
        now: () => clock,
        post: (uri, body) async {
          paths.add(uri.path);
          if (uri.path == '/track/driver/location') return held.future;
          return http.Response(
            '{"ok":true,"session_id":"S1","tracking_sync":{"confirmed":true,"assignment_version":1,"tracking_phase":"en_route_pickup"}}',
            200,
          );
        },
      );
      final payload = {
        'booking_id': 'B1',
        'driver_id': 'D1',
        'tenant_id': 'T1',
        'company_id': 'C1',
      };
      await caller.enRoute(payload, legId: 'B1:RETURN', isOperationalLeg: true);
      final uploading = caller.uploadPreStart(
        latitude: 51,
        longitude: 4,
        speedMps: 4,
        heading: 0,
        accuracy: 5,
        capturedAt: clock,
      );
      final starting = caller.start(
        payload,
        legId: 'B1:RETURN',
        isOperationalLeg: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(paths.contains('/track/session/start'), false);
      clock = clock.add(const Duration(seconds: 20));
      held.complete(http.Response('{"ok":true}', 200));
      await uploading;
      await starting;
      expect(caller.preStartActive, false);
      var pings = 0;
      expect(
        await caller.gpsUploads.send(
          capturedAt: clock,
          request: () async {
            pings++;
            return http.Response('{}', 200);
          },
        ),
        isNull,
      );
      clock = clock.add(const Duration(seconds: 8));
      await caller.gpsUploads.send(
        capturedAt: clock,
        request: () async {
          pings++;
          return http.Response('{}', 200);
        },
      );
      expect(pings, 1);
    },
  );
}
