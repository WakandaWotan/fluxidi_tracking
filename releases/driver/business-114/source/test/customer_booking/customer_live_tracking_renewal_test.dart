import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'package:fluxidi_tracking/main.dart'
    show CustomerBookingDetailPage, CustomerBookingView;

const identity = CustomerLiveTrackingIdentity(
  tenantId: 'T1',
  companyId: 'C1',
  bookingId: 'B1',
);

void main() {
  testWidgets(
    'opening the real booking detail starts tracking without resume',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final server = _GrantServer(tester, phase: 'assigned');
      final controller = server.controller();
      await tester.pumpWidget(
        MaterialApp(
          home: CustomerBookingDetailPage(
            bookingId: 'B1',
            initialView: CustomerBookingView(
              bookingId: 'B1',
              lifecycleStatus: 'ASSIGNED',
              booking: const {},
              record: const {'tenant_id': 'T1', 'company_id': 'C1'},
              source: const {},
            ),
            trackingController: controller,
          ),
        ),
      );
      await tester.pump();
      expect(server.bootstraps, greaterThanOrEqualTo(1));
      expect(server.polls, greaterThanOrEqualTo(1));
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      // Drain the detail page's unrelated best-effort booking refresh.
      await tester.pump(const Duration(seconds: 15));
    },
  );

  testWidgets('a waiting renewal shares the polling request lock', (
    tester,
  ) async {
    final server = _GrantServer(tester)..renewalGate = Completer<void>();
    final controller = server.controller();
    controller.bind(identity);
    controller.setForeground(true);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(server.renewals, 1);
    final polls = server.polls;
    controller.bind(identity);
    controller.bind(identity);
    await tester.pump(const Duration(seconds: 5));
    expect(server.polls, polls);
    expect(server.renewals, 1);
    expect(server.maxInFlight, 1);
    server.renewalGate!.complete();
    await tester.pump();
    expect(server.renewals, 1);
    expect(server.polls, greaterThan(polls));
    expect(server.maxInFlight, 1);
    controller.dispose();
  });
  for (final phase in ['en_route_pickup', 'in_progress']) {
    testWidgets('$phase renews the same token across four minutes', (
      tester,
    ) async {
      final server = _GrantServer(tester, phase: phase);
      final controller = server.controller();
      controller.bind(identity);
      controller.setForeground(true);
      await tester.pump();
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(seconds: 10));
        expect(controller.view.showLivePosition, isTrue);
      }
      expect(server.bootstraps, 1);
      expect(server.renewals, 4);
      expect(server.expiredPolls, 0);
      expect(server.maxInFlight, 1);
      expect(
        server.renewTimes.first.difference(server.startedAt),
        const Duration(seconds: 60),
      );
      expect(server.liveTokens.toSet(), {'Bearer tracking-token'});
      expect(server.renewTokens.toSet(), {'Bearer customer-token'});
      controller.dispose();
    });
  }

  testWidgets('server access_until brings renewal forward', (tester) async {
    final server = _GrantServer(tester, ttl: const Duration(seconds: 50));
    final controller = server.controller();
    controller.bind(identity);
    controller.setForeground(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    expect(server.renewals, 0);
    await tester.pump(const Duration(seconds: 10));
    expect(server.renewals, 1);
    expect(server.expiredPolls, 0);
    controller.dispose();
  });

  testWidgets('temporary renewal failure retries without parallel polling', (
    tester,
  ) async {
    final server = _GrantServer(tester)..failNextRenewal = true;
    final controller = server.controller();
    controller.bind(identity);
    controller.setForeground(true);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(server.renewals, 1);
    expect(controller.view.showLivePosition, isFalse);
    final polls = server.polls;
    await tester.pump(const Duration(seconds: 1));
    expect(server.polls, polls);
    await tester.pump(const Duration(seconds: 1));
    expect(server.renewals, 2);
    expect(controller.view.showLivePosition, isTrue);
    expect(server.maxInFlight, 1);
    expect(server.expiredPolls, 0);
    controller.dispose();
  });

  testWidgets('renewal stops in background and resume bootstraps afresh', (
    tester,
  ) async {
    final server = _GrantServer(tester);
    final controller = server.controller();
    controller.bind(identity);
    controller.setForeground(true);
    await tester.pump();
    controller.setForeground(false);
    final polls = server.polls;
    await tester.pump(const Duration(minutes: 2));
    expect(server.polls, polls);
    expect(server.renewals, 0);
    controller.setForeground(true, rebootstrap: true);
    await tester.pump();
    expect(server.bootstraps, 2);
    expect(server.expiredPolls, 0);
    controller.dispose();
    final requests = server.polls + server.renewals;
    await tester.pump(const Duration(minutes: 2));
    expect(server.polls + server.renewals, requests);
  });

  testWidgets('rejected renewal clears position and does not continue', (
    tester,
  ) async {
    final server = _GrantServer(tester)..renewStatus = 401;
    final controller = server.controller();
    controller.bind(identity);
    controller.setForeground(true);
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(controller.view.showLivePosition, isFalse);
    expect(
      controller.view.availability,
      CustomerLiveTrackingAvailability.ended,
    );
    final polls = server.polls;
    await tester.pump(const Duration(minutes: 2));
    expect(server.polls, polls);
    expect(server.renewals, 1);
    controller.dispose();
  });
}

class _GrantServer {
  _GrantServer(
    this.tester, {
    this.phase = 'en_route_pickup',
    this.ttl = const Duration(seconds: 90),
  }) : startedAt = tester.binding.clock.now();

  final WidgetTester tester;
  final String phase;
  final Duration ttl;
  final DateTime startedAt;
  DateTime? accessUntil;
  int bootstraps = 0;
  int renewals = 0;
  int polls = 0;
  int expiredPolls = 0;
  int inFlight = 0;
  int maxInFlight = 0;
  bool failNextRenewal = false;
  int renewStatus = 200;
  Completer<void>? renewalGate;
  final renewTimes = <DateTime>[];
  final liveTokens = <String>[];
  final renewTokens = <String>[];

  CustomerLiveTrackingController controller() => CustomerLiveTrackingController(
    bookingBaseUrl: 'https://booking.test',
    trackingBaseUrl: 'https://tracking.test',
    customerToken: () async => 'customer-token',
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
      await Future<void>.value();
      final now = tester.binding.clock.now();
      if (method == 'POST') {
        expectSync(uri.path, '/bookings/B1/customer-tracking');
        final body = jsonDecode(jsonBody!);
        if (body['action'] == 'renew') {
          renewals++;
          renewTimes.add(now);
          if (renewalGate != null) await renewalGate!.future;
          renewTokens.add(headers['Authorization']!);
          if (failNextRenewal) {
            failNextRenewal = false;
            return const CustomerLiveHttpResult(statusCode: 503);
          }
          if (renewStatus != 200) {
            return CustomerLiveHttpResult(statusCode: renewStatus);
          }
          accessUntil = now.add(ttl);
          return CustomerLiveHttpResult(
            statusCode: 200,
            body: {
              'ok': true,
              'tracking_phase': phase,
              'tracking_session': null,
              'tracking_sync': {'confirmed': true, 'reason': 'renew'},
            },
          );
        }
        expectSync(body, isEmpty);
        bootstraps++;
        accessUntil = now.add(ttl);
        return CustomerLiveHttpResult(
          statusCode: 200,
          body: {
            'ok': true,
            'tracking_phase': phase,
            'tracking_session': {'token': 'tracking-token'},
          },
        );
      }
      expectSync(uri.path, '/track/customer/live');
      polls++;
      liveTokens.add(headers['Authorization']!);
      final expired = !now.isBefore(accessUntil!);
      if (expired) expiredPolls++;
      return CustomerLiveHttpResult(
        statusCode: 200,
        body: {
          'ok': true,
          'tracking_phase': expired ? 'expired' : phase,
          'feed': {'health': expired ? 'closed' : 'live'},
          'position': expired ? null : {'latitude': 51.05, 'longitude': 3.72},
          'refresh': {
            'access_until': accessUntil!.toIso8601String(),
            'poll_after_seconds': expired ? 0 : 10,
          },
        },
      );
    } finally {
      inFlight--;
    }
  }
}
