import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'customer_live_tracking_reassignment_test.dart' as fixture;
import 'customer_live_tracking_legs_test.dart' as legs;

class Harness {
  Harness(this.tester) : server = fixture.Server(tester);
  final WidgetTester tester;
  final fixture.Server server;
  Completer<void>? gate;
  String hold = 'GET';
  CustomerLiveHttpResult? oldResult;
  CustomerLiveHttpResult? currentResult;
  bool throwOld = false;
  int active = 0, maxActive = 0;
  final seen = <CustomerLiveTrackingView>[];
  late final controller = CustomerLiveTrackingController(
    bookingBaseUrl: 'https://booking.test',
    trackingBaseUrl: 'https://tracking.test',
    customerToken: () async => 'owner',
    now: tester.binding.clock.now,
    send: ({required method, required uri, required headers, jsonBody}) async {
      active++;
      if (active > maxActive) maxActive = active;
      final kind = method == 'GET'
          ? 'GET'
          : jsonDecode(jsonBody!)['action'] == 'renew'
          ? 'renew'
          : 'boot';
      final wait = kind == hold ? gate : null;
      try {
        final result = await server.send(
          method: method,
          uri: uri,
          headers: headers,
          jsonBody: jsonBody,
        );
        if (wait != null) {
          await wait.future;
          if (throwOld) throw StateError('old network exception');
          return oldResult ?? result;
        }
        return currentResult ?? result;
      } finally {
        active--;
      }
    },
  );
  Future<void> start() async {
    controller.addListener(() => seen.add(controller.view));
    controller.bind(legs.selected(legs.record()));
    controller.setForeground(true);
    await tester.pump();
  }

  Future<void> pendingPoll() async {
    gate = Completer<void>();
    await tester.pump(const Duration(seconds: 10));
    expect(active, 1);
  }

  Future<void> release() async {
    final g = gate!;
    gate = null;
    g.complete();
    await tester.pump();
  }

  void close() {
    expect(maxActive, 1);
    controller.dispose();
  }
}

void main() {
  testWidgets('normal current response still updates tracking', (tester) async {
    final h = Harness(tester);
    await h.start();
    expect(h.controller.view.driverName, 'Alice');
    h.server.driver = 'Bob';
    await tester.pump(const Duration(seconds: 10));
    expect(h.controller.view.driverName, 'Bob');
    expect(h.controller.view.showLivePosition, true);
    h.close();
  });
  for (final error in [false, true]) {
    testWidgets(
      'background discards pending ${error ? "exception" : "success"}',
      (tester) async {
        final h = Harness(tester);
        await h.start();
        await h.pendingPoll();
        h.throwOld = error;
        h.controller.setForeground(false);
        final before = h.controller.view;
        final count = h.seen.length;
        await h.release();
        expect(identical(h.controller.view, before), true);
        expect(h.seen.length, count);
        h.close();
      },
    );
  }
  for (final outcome in [
    'success',
    'terminal',
    'assignment',
    'transient',
    'exception',
  ]) {
    testWidgets(
      'resume rejects old $outcome and reboots once after request lock',
      (tester) async {
        final h = Harness(tester);
        await h.start();
        await h.pendingPoll();
        if (outcome == 'terminal')
          h.oldResult = const CustomerLiveHttpResult(statusCode: 404);
        if (outcome == 'assignment')
          h.oldResult = const CustomerLiveHttpResult(
            statusCode: 409,
            body: {'error': 'assignment_changed'},
          );
        if (outcome == 'transient')
          h.oldResult = const CustomerLiveHttpResult(statusCode: 503);
        h.throwOld = outcome == 'exception';
        for (var i = 0; i < 3; i++) {
          h.controller.setForeground(false);
          h.controller.setForeground(true, rebootstrap: true);
        }
        h.server.version = 2;
        h.server.driver = 'Bob';
        h.seen.clear();
        expect(h.server.bootstraps, 1);
        expect(h.active, 1);
        await h.release();
        expect(h.server.bootstraps, 2);
        expect(h.controller.view.driverName, 'Bob');
        expect(h.seen.every((v) => v.driverName == 'Bob'), true);
        expect(h.server.tokens.last, 'Bearer token-2');
        h.close();
      },
    );
  }
  for (final change in ['leg', 'identity ABA', 'token']) {
    testWidgets('old poll ignored across $change context change', (
      tester,
    ) async {
      final h = Harness(tester);
      await h.start();
      await h.pendingPoll();
      if (change == 'token') {
        h.controller.setForeground(true, rebootstrap: true);
      } else {
        h.controller.bind(legs.selected(legs.record(outbound: 'COMPLETED')));
        if (change == 'identity ABA')
          h.controller.bind(legs.selected(legs.record()));
      }
      h.server.driver = 'Bob';
      h.server.version = 2;
      h.seen.clear();
      await h.release();
      expect(h.seen.every((v) => v.driverName == 'Bob'), true);
      expect(h.controller.view.driverName, 'Bob');
      h.close();
    });
  }
  testWidgets(
    'obsolete success cannot replace transient state of resumed generation',
    (tester) async {
      final h = Harness(tester);
      await h.start();
      await h.pendingPoll();
      h.controller.setForeground(false);
      h.controller.setForeground(true);
      h.server.driver = 'Bob';
      h.currentResult = const CustomerLiveHttpResult(statusCode: 503);
      h.seen.clear();
      await h.release();
      expect(h.controller.view.showLivePosition, false);
      expect(h.seen.every((v) => !v.showLivePosition), true);
      h.currentResult = null;
      await tester.pump(const Duration(seconds: 2));
      expect(h.controller.view.driverName, 'Bob');
      expect(h.controller.view.showLivePosition, true);
      h.close();
    },
  );
  for (final kind in ['boot', 'renew']) {
    testWidgets(
      'late $kind result is ignored after foreground generation changes',
      (tester) async {
        final h = Harness(tester);
        h.hold = kind;
        if (kind == 'boot') {
          h.gate = Completer<void>();
          await h.start();
        } else {
          await h.start();
          h.gate = Completer<void>();
          await tester.pump(const Duration(seconds: 60));
        }
        expect(h.active, 1);
        h.controller.setForeground(false);
        h.controller.setForeground(true);
        h.server.version = 2;
        h.server.driver = 'Bob';
        h.seen.clear();
        await h.release();
        expect(h.controller.view.driverName, 'Bob');
        expect(h.seen.every((v) => v.driverName == 'Bob'), true);
        h.close();
      },
    );
  }
  testWidgets('disposed controller ignores late terminal result', (
    tester,
  ) async {
    final h = Harness(tester);
    await h.start();
    await h.pendingPoll();
    h.oldResult = const CustomerLiveHttpResult(statusCode: 404);
    final before = h.controller.view;
    h.close();
    await h.release();
    expect(identical(h.controller.view, before), true);
  });
}
