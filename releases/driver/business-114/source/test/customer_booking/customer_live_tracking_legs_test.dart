import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/customer_booking/customer_live_tracking.dart';
import 'customer_live_tracking_reassignment_test.dart' as fixture;

Map<String, dynamic> record({
  String outbound = 'PENDING',
  String inbound = 'PENDING',
}) => {
  'tenant_id': 'T',
  'company_id': 'C',
  'assigned_driver_id': 'parent-summary',
  'operational_legs': [
    {'leg_id': 'B:OUTBOUND', 'leg_type': 'outbound', 'status': outbound},
    {'leg_id': 'B:RETURN', 'leg_type': 'return', 'status': inbound},
  ],
};
CustomerLiveTrackingIdentity selected(
  Map<String, dynamic> source, {
  String? focus,
}) => customerLiveTrackingIdentityFromSources(
  bookingId: 'B',
  maps: [source],
  preferredLegType: focus,
)!;

void main() {
  test('open/reopen detail selects canonical leg, never parent alias', () {
    expect(selected(record()).operationalLeg, 'B:OUTBOUND');
    expect(selected(record(), focus: 'return').operationalLeg, 'B:RETURN');
    expect(selected(record(outbound: 'COMPLETED')).operationalLeg, 'B:RETURN');
    expect(selected(record(outbound: 'CANCELLED')).operationalLeg, 'B:RETURN');
    expect(
      selected(record(outbound: 'COMPLETED'), focus: 'outbound').operationalLeg,
      'B:OUTBOUND',
    );
    expect(
      selected(
        record(outbound: 'COMPLETED', inbound: 'COMPLETED'),
      ).operationalLeg,
      'B:OUTBOUND',
    );
    final single = record();
    (single['operational_legs'] as List).removeLast();
    expect(selected(single).operationalLeg, 'primary');
  });
  testWidgets(
    'switching legs clears old driver and reauthorizes; reopen preserves return',
    (tester) async {
      final server = fixture.Server(tester);
      final controller = server.controller();
      controller.bind(selected(record()));
      controller.setForeground(true);
      await tester.pump();
      expect(controller.view.driverName, 'Alice');
      server.driver = 'Bob';
      server.version = 2;
      controller.bind(selected(record(outbound: 'COMPLETED')));
      expect(controller.view.showLivePosition, false);
      expect(controller.view.driverName, isEmpty);
      await tester.pump();
      expect(controller.view.driverName, 'Bob');
      expect(server.bootstraps, 2);
      controller.bind(selected(record(outbound: 'COMPLETED')));
      await tester.pump();
      expect(server.bootstraps, 2);
      expect(server.maxInFlight, 1);
      controller.dispose();
    },
  );
  testWidgets(
    'return awaiting assignment retries existing bootstrap automatically',
    (tester) async {
      final server = fixture.Server(tester)..ready = false;
      final controller = server.controller();
      controller.bind(selected(record(outbound: 'COMPLETED')));
      controller.setForeground(true);
      await tester.pump();
      expect(controller.view.showLivePosition, false);
      server.ready = true;
      server.driver = 'Bob';
      await tester.pump(const Duration(seconds: 10));
      expect(server.bootstraps, 2);
      expect(controller.view.driverName, 'Bob');
      controller.dispose();
    },
  );
  testWidgets(
    'leg switch during pending poll discards old response without concurrent requests',
    (tester) async {
      final server = fixture.Server(tester);
      final controller = server.controller();
      controller.bind(selected(record()));
      controller.setForeground(true);
      await tester.pump();
      final gate = Completer<void>();
      server.pollGate = gate;
      await tester.pump(const Duration(seconds: 10));
      controller.bind(selected(record(), focus: 'return'));
      expect(controller.view.driverName, isEmpty);
      server.driver = 'Bob';
      server.version = 2;
      server.pollGate = null;
      gate.complete();
      await tester.pump();
      expect(controller.view.driverName, 'Bob');
      expect(server.maxInFlight, 1);
      expect(server.bootstraps, 2);
      controller.dispose();
    },
  );
  testWidgets('explicit completed outbound does not retry or move to return', (
    tester,
  ) async {
    final server = fixture.Server(tester)..phase = 'completed';
    final controller = server.controller();
    controller.bind(selected(record(outbound: 'COMPLETED'), focus: 'outbound'));
    controller.setForeground(true);
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(
      controller.view.availability,
      CustomerLiveTrackingAvailability.ended,
    );
    expect(server.bootstraps, 1);
    controller.dispose();
  });
  testWidgets('bootstrap renewal and live GET all carry same concrete leg', (
    tester,
  ) async {
    final calls = <Map<String, dynamic>>[];
    final controller = CustomerLiveTrackingController(
      bookingBaseUrl: 'https://booking.invalid',
      trackingBaseUrl: 'https://tracking.invalid',
      customerToken: () async => 'customer-token',
      now: () => tester.binding.clock.now(),
      send:
          ({required method, required uri, required headers, jsonBody}) async {
            if (method == 'POST') {
              final body = jsonDecode(jsonBody!) as Map<String, dynamic>;
              calls.add(body);
              expectSync(body['operational_leg'], 'B:RETURN');
              return CustomerLiveHttpResult(
                statusCode: 200,
                body: {
                  'ok': true,
                  'assignment_version': 1,
                  'tracking_phase': 'en_route_pickup',
                  if (body['action'] != 'renew')
                    'tracking_session': {'token': 'return-token'},
                  'tracking_sync': {'confirmed': true, 'reason': 'renew'},
                },
              );
            }
            expectSync(uri.queryParameters['operational_leg'], 'B:RETURN');
            return const CustomerLiveHttpResult(
              statusCode: 200,
              body: {
                'ok': true,
                'tracking_phase': 'en_route_pickup',
                'assignment_version': 1,
                'refresh': {'poll_after_seconds': 10},
                'feed': {'health': 'missing'},
              },
            );
          },
    );
    controller.bind(selected(record(), focus: 'return'));
    controller.setForeground(true);
    await tester.pump();
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 10));
    }
    expect(calls.any((body) => body['action'] == 'renew'), true);
    controller.dispose();
  });
}
