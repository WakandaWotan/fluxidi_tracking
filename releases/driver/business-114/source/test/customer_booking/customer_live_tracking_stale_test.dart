import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';

void main() {
  const id = CustomerLiveTrackingIdentity(
    tenantId: 'T',
    companyId: 'C',
    bookingId: 'B',
  );
  test('non-live feed statuses never display a supplied position or ETA', () {
    for (final health in ['missing', 'stale', 'closed', 'unknown']) {
      final body = {
        ...live(DateTime.now()).body,
        'feed': {'health': health},
      };
      final snapshot = parseCustomerLiveSnapshot(body);
      expect(snapshot.showPosition, isFalse);
      expect(snapshot.showEta, isNull);
    }
  });
  testWidgets('retry backoff doubles to 30 seconds and resets after recovery', (
    tester,
  ) async {
    var failing = true;
    var polls = 0;
    final controller = CustomerLiveTrackingController(
      bookingBaseUrl: 'https://booking.test',
      trackingBaseUrl: 'https://tracking.test',
      customerToken: () async => 'customer',
      now: tester.binding.clock.now,
      send:
          ({required method, required uri, required headers, jsonBody}) async {
            if (method == 'POST') {
              if (jsonBody!.contains('renew'))
                return const CustomerLiveHttpResult(
                  statusCode: 200,
                  body: {
                    'ok': true,
                    'tracking_sync': {'confirmed': true, 'reason': 'renew'},
                  },
                );
              return boot;
            }
            polls++;
            return failing
                ? const CustomerLiveHttpResult(statusCode: 503)
                : live(tester.binding.clock.now());
          },
    );
    controller.bind(id);
    controller.setForeground(true);
    await tester.pump();
    for (final seconds in [2, 4, 8, 16, 30, 30]) {
      final before = polls;
      await tester.pump(Duration(seconds: seconds - 1));
      expect(polls, before);
      await tester.pump(const Duration(seconds: 1));
      expect(polls, before + 1);
    }
    failing = false;
    await tester.pump(const Duration(seconds: 30));
    expect(controller.view.showLivePosition, isTrue);
    failing = true;
    await tester.pump(const Duration(seconds: 10));
    final before = polls;
    await tester.pump(const Duration(seconds: 2));
    expect(polls, before + 1);
    controller.dispose();
  });
  for (final failure in ['timeout', 'network', '500', '503']) {
    testWidgets(
      'live then $failure hides old data and recovers automatically',
      (tester) async {
        var failing = false;
        var polls = 0;
        var inFlight = 0;
        var maximum = 0;
        final controller = CustomerLiveTrackingController(
          bookingBaseUrl: 'https://booking.test',
          trackingBaseUrl: 'https://tracking.test',
          customerToken: () async => 'customer',
          now: tester.binding.clock.now,
          send:
              ({
                required method,
                required uri,
                required headers,
                jsonBody,
              }) async {
                inFlight++;
                if (inFlight > maximum) maximum = inFlight;
                try {
                  if (method == 'POST') return boot;
                  polls++;
                  if (failing) {
                    if (failure == 'timeout') throw TimeoutException('offline');
                    if (failure == 'network') throw StateError('network');
                    return CustomerLiveHttpResult(
                      statusCode: int.parse(failure),
                    );
                  }
                  return live(tester.binding.clock.now());
                } finally {
                  inFlight--;
                }
              },
        );
        controller.bind(id);
        controller.setForeground(true);
        await tester.pump();
        expect(controller.view.showLivePosition, isTrue);
        expect(controller.view.showEta, isNotNull);
        failing = true;
        await tester.pump(const Duration(seconds: 10));
        expect(controller.view.showLivePosition, isFalse);
        expect(controller.view.showEta, isNull);
        expect(
          controller.view.availability,
          CustomerLiveTrackingAvailability.unavailable,
        );
        final count = polls;
        await tester.pump(const Duration(seconds: 1));
        expect(polls, count);
        failing = false;
        await tester.pump(const Duration(seconds: 1));
        expect(polls, count + 1);
        expect(controller.view.showLivePosition, isTrue);
        expect(controller.view.showEta, isNotNull);
        expect(maximum, 1);
        controller.dispose();
      },
    );
  }
  testWidgets(
    'ETA expires independently while a pending poll cannot freeze GPS',
    (tester) async {
      final gate = Completer<CustomerLiveHttpResult>();
      var polls = 0;
      final controller = CustomerLiveTrackingController(
        bookingBaseUrl: 'https://booking.test',
        trackingBaseUrl: 'https://tracking.test',
        customerToken: () async => 'customer',
        now: tester.binding.clock.now,
        send:
            ({
              required method,
              required uri,
              required headers,
              jsonBody,
            }) async {
              if (method == 'POST') return boot;
              if (++polls == 1)
                return live(tester.binding.clock.now(), etaSeconds: 5);
              return gate.future;
            },
      );
      controller.bind(id);
      controller.setForeground(true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(controller.view.showEta, isNull);
      expect(controller.view.showLivePosition, isTrue);
      await tester.pump(const Duration(seconds: 5));
      controller.bind(id);
      controller.bind(id);
      await tester.pump(const Duration(seconds: 20));
      expect(polls, 2);
      expect(controller.view.showLivePosition, isFalse);
      gate.complete(live(tester.binding.clock.now()));
      await tester.pump();
      expect(controller.view.showLivePosition, isTrue);
      controller.dispose();
    },
  );
  testWidgets('old captured_at expires even when backend says live', (
    tester,
  ) async {
    final now = tester.binding.clock.now();
    final controller = CustomerLiveTrackingController(
      bookingBaseUrl: 'https://booking.test',
      trackingBaseUrl: 'https://tracking.test',
      customerToken: () async => 'customer',
      now: tester.binding.clock.now,
      send:
          ({required method, required uri, required headers, jsonBody}) async =>
              method == 'POST'
              ? boot
              : live(now, captured: now.subtract(const Duration(seconds: 299))),
    );
    controller.bind(id);
    controller.setForeground(true);
    await tester.pump();
    expect(controller.view.showLivePosition, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.view.showLivePosition, isFalse);
    expect(controller.view.showEta, isNull);
    expect(controller.view.snapshot.feed, CustomerLiveFeedHealth.stale);
    controller.dispose();
  });
  testWidgets('real 404 ends permanently, including a queued poll', (
    tester,
  ) async {
    var polls = 0;
    final gate = Completer<CustomerLiveHttpResult>();
    final controller = CustomerLiveTrackingController(
      bookingBaseUrl: 'https://booking.test',
      trackingBaseUrl: 'https://tracking.test',
      customerToken: () async => 'customer',
      now: tester.binding.clock.now,
      send:
          ({required method, required uri, required headers, jsonBody}) async {
            if (method == 'POST') return boot;
            polls++;
            return gate.future;
          },
    );
    controller.bind(id);
    controller.setForeground(true);
    await tester.pump();
    controller.bind(id);
    gate.complete(const CustomerLiveHttpResult(statusCode: 404));
    await tester.pump();
    await tester.pump(const Duration(minutes: 2));
    controller.bind(id);
    await tester.pump();
    expect(polls, 1);
    expect(
      controller.view.availability,
      CustomerLiveTrackingAvailability.ended,
    );
    controller.dispose();
  });
  testWidgets('temporary bootstrap Room failure retries automatically', (
    tester,
  ) async {
    var starts = 0;
    final controller = CustomerLiveTrackingController(
      bookingBaseUrl: 'https://booking.test',
      trackingBaseUrl: 'https://tracking.test',
      customerToken: () async => 'customer',
      now: tester.binding.clock.now,
      send:
          ({required method, required uri, required headers, jsonBody}) async {
            if (method == 'POST')
              return ++starts == 1
                  ? const CustomerLiveHttpResult(statusCode: 503)
                  : boot;
            return live(tester.binding.clock.now());
          },
    );
    controller.bind(id);
    controller.setForeground(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(starts, 2);
    expect(controller.view.showLivePosition, isTrue);
    controller.dispose();
  });
}

const boot = CustomerLiveHttpResult(
  statusCode: 200,
  body: {
    'ok': true,
    'tracking_phase': 'en_route_pickup',
    'tracking_session': {'token': 'tracking'},
  },
);
CustomerLiveHttpResult live(
  DateTime now, {
  int etaSeconds = 45,
  DateTime? captured,
}) => CustomerLiveHttpResult(
  statusCode: 200,
  body: {
    'ok': true,
    'tracking_phase': 'en_route_pickup',
    'feed': {'health': 'live'},
    'position': {
      'latitude': 51.0,
      'longitude': 4.0,
      'captured_at': (captured ?? now).toIso8601String(),
    },
    'eta': {
      'target': 'pickup',
      'duration_seconds': 180,
      'valid_until': now.add(Duration(seconds: etaSeconds)).toIso8601String(),
    },
    'refresh': {
      'poll_after_seconds': 10,
      'access_until': now.add(const Duration(seconds: 90)).toIso8601String(),
    },
  },
);
