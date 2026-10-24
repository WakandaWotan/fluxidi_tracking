import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';

const identity = CustomerLiveTrackingIdentity(
  tenantId: 'T',
  companyId: 'C',
  bookingId: 'B',
);
void main() {
  for (final sameDriver in [false, true]) {
    testWidgets(
      'reassignment ${sameDriver ? "same driver" : "different driver"} uses new owner grant',
      (tester) async {
        final server = Server(tester);
        final controller = server.controller();
        controller.bind(identity);
        controller.setForeground(true);
        await tester.pump();
        expect(controller.view.driverName, 'Alice');
        server.version = 2;
        server.driver = sameDriver ? 'Alice' : 'Bob';
        await tester.pump(const Duration(seconds: 10));
        expect(controller.view.showLivePosition, isFalse);
        expect(controller.view.showEta, isNull);
        expect(controller.view.driverName, isEmpty);
        expect(controller.view.snapshot.driverName, isEmpty);
        expect(controller.view.snapshot.vehicleLabel, isEmpty);
        await tester.pump(const Duration(seconds: 10));
        expect(server.bootstraps, 2);
        expect(controller.view.showLivePosition, isTrue);
        expect(controller.view.driverName, server.driver);
        expect(server.tokens.last, 'Bearer token-2');
        expect(server.maxInFlight, 1);
        controller.dispose();
      },
    );
  }
  testWidgets('new assignment not ready retries owner bootstrap then resumes', (
    tester,
  ) async {
    final server = Server(tester);
    final controller = server.controller();
    controller.bind(identity);
    controller.setForeground(true);
    await tester.pump();
    server.version = 2;
    server.ready = false;
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(seconds: 10));
    expect(server.bootstraps, 2);
    expect(controller.view.showLivePosition, isFalse);
    await tester.pump(const Duration(seconds: 10));
    expect(server.bootstraps, 3);
    server.ready = true;
    server.phase = 'assigned';
    server.driver = 'Bob';
    await tester.pump(const Duration(seconds: 10));
    expect(controller.view.showLivePosition, isFalse);
    server.phase = 'en_route_pickup';
    await tester.pump(const Duration(seconds: 10));
    expect(controller.view.showLivePosition, isTrue);
    expect(controller.view.driverName, 'Bob');
    expect(server.maxInFlight, 1);
    controller.dispose();
  });
  testWidgets(
    'reassignment during pending poll clears before pending bootstrap completes',
    (tester) async {
      final server = Server(tester);
      final controller = server.controller();
      controller.bind(identity);
      controller.setForeground(true);
      await tester.pump();
      server.pollGate = Completer<void>();
      await tester.pump(const Duration(seconds: 10));
      controller.bind(identity);
      controller.bind(identity);
      server.version = 2;
      server.driver = 'Bob';
      server.bootGate = Completer<void>();
      server.pollGate!.complete();
      server.pollGate = null;
      await tester.pump();
      expect(controller.view.driverName, isEmpty);
      expect(controller.view.showLivePosition, isFalse);
      await tester.pump(const Duration(seconds: 10));
      expect(server.bootstraps, 2);
      expect(server.maxInFlight, 1);
      expect(controller.view.driverName, isEmpty);
      server.bootGate!.complete();
      server.bootGate = null;
      await tester.pump();
      expect(controller.view.driverName, 'Bob');
      expect(server.maxInFlight, 1);
      controller.dispose();
    },
  );
  testWidgets(
    'renewal version change reacquires access without polling old token',
    (tester) async {
      final server = Server(tester);
      final controller = server.controller();
      controller.bind(identity);
      controller.setForeground(true);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 10));
      }
      server.version = 2;
      server.driver = 'Bob';
      final polls = server.polls;
      await tester.pump(const Duration(seconds: 10));
      expect(server.renewals, 1);
      expect(server.polls, polls);
      expect(controller.view.driverName, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(server.bootstraps, 2);
      expect(server.tokens.last, 'Bearer token-2');
      expect(controller.view.driverName, 'Bob');
      expect(server.maxInFlight, 1);
      controller.dispose();
    },
  );
  testWidgets(
    'terminal owner bootstrap during recovery stops further bootstrap',
    (tester) async {
      final server = Server(tester);
      final controller = server.controller();
      controller.bind(identity);
      controller.setForeground(true);
      await tester.pump();
      server.version = 2;
      await tester.pump(const Duration(seconds: 10));
      server.phase = 'completed';
      await tester.pump(const Duration(seconds: 10));
      expect(server.bootstraps, 2);
      expect(
        controller.view.availability,
        CustomerLiveTrackingAvailability.ended,
      );
      await tester.pump(const Duration(minutes: 2));
      expect(server.bootstraps, 2);
      expect(controller.view.driverName, isEmpty);
      controller.dispose();
    },
  );
  testWidgets('terminal live status never starts reassignment recovery', (
    tester,
  ) async {
    final server = Server(tester);
    final controller = server.controller();
    controller.bind(identity);
    controller.setForeground(true);
    await tester.pump();
    server.phase = 'cancelled';
    await tester.pump(const Duration(seconds: 10));
    await tester.pump(const Duration(minutes: 2));
    expect(server.bootstraps, 1);
    expect(
      controller.view.availability,
      CustomerLiveTrackingAvailability.ended,
    );
    controller.dispose();
  });
}

class Server {
  Server(this.tester);
  final WidgetTester tester;
  int version = 1,
      bootstraps = 0,
      polls = 0,
      renewals = 0,
      inFlight = 0,
      maxInFlight = 0;
  String driver = 'Alice', phase = 'en_route_pickup';
  bool ready = true;
  Completer<void>? pollGate, bootGate;
  final tokens = <String>[];
  CustomerLiveTrackingController controller() => CustomerLiveTrackingController(
    bookingBaseUrl: 'https://booking.test',
    trackingBaseUrl: 'https://tracking.test',
    customerToken: () async => 'owner',
    now: tester.binding.clock.now,
    send: send,
  );
  Future<CustomerLiveHttpResult> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? jsonBody,
  }) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      if (method == 'POST') {
        expectSync(headers['Authorization'], 'Bearer owner');
        if (jsonDecode(jsonBody!)['action'] == 'renew') {
          renewals++;
          return CustomerLiveHttpResult(
            statusCode: 200,
            body: {
              'ok': true,
              'assignment_version': version,
              'tracking_phase': phase,
              'tracking_sync': {'confirmed': true, 'reason': 'renew'},
            },
          );
        }
        bootstraps++;
        if (bootGate != null) await bootGate!.future;
        if (phase == 'completed')
          return const CustomerLiveHttpResult(
            statusCode: 404,
            body: {
              'ok': false,
              'error': 'tracking_closed',
              'booking_status': 'COMPLETED',
            },
          );
        if (!ready)
          return const CustomerLiveHttpResult(
            statusCode: 404,
            body: {'ok': false, 'error': 'not_assigned'},
          );
        return CustomerLiveHttpResult(
          statusCode: 200,
          body: {
            'ok': true,
            'assignment_version': version,
            'tracking_phase': phase,
            'tracking_session': {'token': 'token-$version'},
          },
        );
      }
      polls++;
      tokens.add(headers['Authorization']!);
      if (pollGate != null) await pollGate!.future;
      if (headers['Authorization'] != 'Bearer token-$version')
        return const CustomerLiveHttpResult(
          statusCode: 409,
          body: {'error': 'assignment_changed'},
        );
      expectSync(uri.queryParameters['assignment_version'], '$version');
      final now = tester.binding.clock.now();
      return CustomerLiveHttpResult(
        statusCode: 200,
        body: {
          'ok': true,
          'assignment_version': version,
          'tracking_phase': phase,
          'driver': {'display_name': driver},
          'vehicle': {'label': 'Taxi $version'},
          'feed': {'health': 'live'},
          'position': {
            'latitude': 51.0 + version / 100,
            'longitude': 4.0,
            'captured_at': now.toIso8601String(),
          },
          'eta': {
            'target': 'pickup',
            'duration_seconds': 180,
            'valid_until': now
                .add(const Duration(seconds: 45))
                .toIso8601String(),
          },
          'refresh': {'poll_after_seconds': 10},
        },
      );
    } finally {
      inFlight--;
    }
  }
}
