import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fluxidi_tracking/main.dart'
    show CustomerBookingDetailPage, CustomerBookingView;
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'customer_live_tracking_legs_test.dart' as legs;
import 'customer_live_tracking_reassignment_test.dart' as fixture;

class DetailServer {
  DetailServer(this.tester) : tracking = fixture.Server(tester);
  final WidgetTester tester;
  final fixture.Server tracking;
  Map<String, dynamic> booking = legs.record();
  String returnPhase = 'en_route_pickup';
  bool returnReady = true;
  bool outboundClosed = false;
  int reads = 0, inFlight = 0, maxInFlight = 0;
  Completer<void>? readGate;
  final bootLegs = <String>[];
  late final controller = CustomerLiveTrackingController(
    bookingBaseUrl: 'https://booking.test',
    trackingBaseUrl: 'https://tracking.test',
    customerToken: () async => 'owner',
    now: tester.binding.clock.now,
    send: ({required method, required uri, required headers, jsonBody}) {
      final leg = method == 'POST'
          ? jsonDecode(jsonBody!)['operational_leg']
          : uri.queryParameters['operational_leg'];
      if (method == 'POST' && jsonDecode(jsonBody!)['action'] != 'renew')
        bootLegs.add('$leg');
      tracking.phase = leg == 'B:RETURN'
          ? returnPhase
          : (outboundClosed ||
                    booking['operational_legs'] is List &&
                        (booking['operational_legs'] as List).first['status'] ==
                            'COMPLETED'
                ? 'completed'
                : 'en_route_pickup');
      tracking.ready = leg != 'B:RETURN' || returnReady;
      tracking.driver = leg == 'B:RETURN' ? 'Bob' : 'Alice';
      return tracking.send(
        method: method,
        uri: uri,
        headers: headers,
        jsonBody: jsonBody,
      );
    },
  );
  late final client = MockClient((req) async {
    if (!req.url.path.endsWith('/bookings/B')) return http.Response('{}', 404);
    reads++;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    final captured = jsonEncode({'ok': true, 'record': booking});
    try {
      if (readGate != null) await readGate!.future;
      return http.Response(captured, 200);
    } finally {
      inFlight--;
    }
  });
  Future<void> mount({String? focus}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerBookingDetailPage(
          bookingId: 'B',
          initialView: CustomerBookingView.fromResponse('B', {
            'ok': true,
            'record': booking,
          }),
          initialLegType: focus,
          trackingController: controller,
        ),
      ),
    );
    await flush();
  }

  Future<void> flush() async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }
  }

  Future<void> background() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await flush();
  }

  Future<void> resume() async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await flush();
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await flush();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fluxidi_resume_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => tempDir.path,
        );
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await tempDir.delete(recursive: true);
  });

  for (final phase in [
    'unassigned',
    'assigned',
    'en_route_pickup',
    'in_progress',
  ]) {
    testWidgets('real general detail discovers RETURN on resume: $phase', (
      tester,
    ) async {
      final s = DetailServer(tester);
      await http.runWithClient(() async {
        await s.mount();
        expect(s.bootLegs.last, 'B:OUTBOUND');
        await s.background();
        final before = s.reads;
        await tester.pump(const Duration(seconds: 30));
        expect(s.reads, before);
        s.booking = legs.record(outbound: 'COMPLETED');
        s.returnPhase = phase;
        s.returnReady = phase != 'unassigned';
        s.tracking.bootGate = Completer<void>();
        await s.resume();
        expect(s.reads, before + 1);
        expect(s.bootLegs.last, 'B:RETURN');
        expect(s.controller.view.showLivePosition, false);
        expect(s.controller.view.showEta, isNull);
        s.tracking.bootGate!.complete();
        s.tracking.bootGate = null;
        await s.flush();
        if (phase == 'unassigned') {
          s.returnReady = true;
          await tester.pump(const Duration(seconds: 10));
          await s.flush();
        }
        expect(s.tracking.maxInFlight, 1);
        expect(s.maxInFlight, 1);
        await s.close();
      }, () => s.client);
    });
  }
  testWidgets('explicit historical OUTBOUND stays selected after resume', (
    tester,
  ) async {
    final s = DetailServer(tester);
    await http.runWithClient(() async {
      await s.mount(focus: 'outbound');
      await s.background();
      s.booking = legs.record(outbound: 'COMPLETED');
      await s.resume();
      await tester.pump(const Duration(seconds: 30));
      expect(s.bootLegs.every((leg) => leg == 'B:OUTBOUND'), true);
      await s.close();
    }, () => s.client);
  });
  testWidgets(
    'unchanged leg and repeated resume cycles do not duplicate refreshes/polls',
    (tester) async {
      final s = DetailServer(tester);
      await http.runWithClient(() async {
        await s.mount();
        for (var i = 0; i < 3; i++) {
          await s.background();
          final before = s.reads;
          await s.resume();
          expect(s.reads, before + 1);
        }
        expect(s.bootLegs.toSet(), {'B:OUTBOUND'});
        expect(s.maxInFlight, 1);
        expect(s.tracking.maxInFlight, 1);
        await s.close();
      }, () => s.client);
    },
  );
  testWidgets(
    'resume queues one fresh booking read behind a request already in flight',
    (tester) async {
      final s = DetailServer(tester)..readGate = Completer<void>();
      await http.runWithClient(() async {
        await s.mount();
        expect(s.reads, 1);
        await s.background();
        s.booking = legs.record(outbound: 'COMPLETED');
        await s.resume();
        expect(s.reads, 1);
        final gate = s.readGate!;
        s.readGate = null;
        gate.complete();
        await s.flush();
        expect(s.reads, 2);
        expect(s.bootLegs.last, 'B:RETURN');
        expect(s.maxInFlight, 1);
        expect(s.tracking.maxInFlight, 1);
        await s.close();
      }, () => s.client);
    },
  );
  testWidgets('ended OUTBOUND restarts exactly one leg timer after resume', (
    tester,
  ) async {
    final s = DetailServer(tester);
    await http.runWithClient(() async {
      s.outboundClosed = true;
      await s.mount();
      expect(
        s.controller.view.availability,
        CustomerLiveTrackingAvailability.ended,
      );
      await s.background();
      await s.resume();
      final before = s.reads;
      await tester.pump(const Duration(seconds: 10));
      await s.flush();
      expect(s.reads, before + 1);
      await tester.pump(const Duration(seconds: 10));
      await s.flush();
      expect(s.reads, before + 2);
      await s.close();
    }, () => s.client);
  });
  testWidgets('resume switches leg while an old poll holds the request lock', (
    tester,
  ) async {
    final s = DetailServer(tester);
    await http.runWithClient(() async {
      await s.mount();
      s.tracking.pollGate = Completer<void>();
      await tester.pump(const Duration(seconds: 10));
      await s.flush();
      expect(s.tracking.inFlight, 1);
      await s.background();
      s.booking = legs.record(outbound: 'COMPLETED');
      await s.resume();
      expect(s.controller.view.showLivePosition, false);
      expect(s.controller.view.showEta, isNull);
      final gate = s.tracking.pollGate!;
      s.tracking.pollGate = null;
      gate.complete();
      await s.flush();
      expect(s.bootLegs.last, 'B:RETURN');
      expect(s.tracking.maxInFlight, 1);
      await s.close();
    }, () => s.client);
  });
  testWidgets('single detail retains existing resume flow without leg timer', (
    tester,
  ) async {
    final s = DetailServer(tester);
    s.booking = {
      'tenant_id': 'T',
      'company_id': 'C',
      'assigned_driver_id': 'D',
    };
    await http.runWithClient(() async {
      await s.mount();
      final before = s.reads;
      await s.background();
      await s.resume();
      await tester.pump(const Duration(seconds: 30));
      await s.flush();
      expect(s.reads, before);
      expect(s.tracking.maxInFlight, 1);
      await s.close();
    }, () => s.client);
  });
}
