import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_panel.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_presentation.dart';
import 'package:fluxidi_tracking/driver/planned_tracking_lifecycle.dart';

void main() {
  test(
    'human acceptance only posts its decision; NAV alone arms trip GPS',
    () async {
      final posts = <String>[];
      var clock = DateTime(2026, 10, 8, 10);
      final client = DriverRideOfferClient(
        baseUrl: 'https://fixture.invalid',
        token: 'fixture',
        vehicleId: 'V',
        client: MockClient((request) async {
          posts.add(request.url.path);
          return http.Response('{"ok":true}', 200);
        }),
      );
      final lifecycle = PlannedTrackingLifecycle(
        bookingBaseUrl: 'https://fixture.invalid',
        trackingBaseUrl: 'https://fixture.invalid',
        now: () => clock,
        post: (uri, body) async {
          posts.add(uri.path);
          return http.Response(
            jsonEncode({
              'ok': true,
              'tracking_sync': {
                'confirmed': true,
                'assignment_version': 1,
                'tracking_phase': 'en_route_pickup',
              },
            }),
            200,
          );
        },
      );
      final offer = DriverRideOffer(
        id: 'O',
        version: 1,
        vehicleId: 'V',
        deadlineMs: clock.millisecondsSinceEpoch + 30000,
        pickup: 'Pickup',
        destination: 'Destination',
      );
      await client.received(offer);
      await client.decide(offer, 'accept');
      expect(posts, [
        '/public/driver/dispatch/ack',
        '/public/driver/dispatch/decision',
      ]);
      expect(lifecycle.preStartActive, false);
      Future<void> sample() => lifecycle.uploadPreStart(
        latitude: 51,
        longitude: 4,
        speedMps: 0,
        heading: 0,
        accuracy: 8,
        capturedAt: clock,
      );
      await sample();
      expect(posts, hasLength(2));
      await lifecycle.enRoute(
        {
          'tenant_id': 'T',
          'company_id': 'C',
          'booking_id': 'B',
          'driver_id': 'D',
          'vehicle_id': 'V',
        },
        legId: 'primary',
        isOperationalLeg: false,
      );
      expect(lifecycle.preStartActive, true);
      await sample();
      expect(posts, [
        '/public/driver/dispatch/ack',
        '/public/driver/dispatch/decision',
        '/tracking/en-route',
        '/track/driver/location',
      ]);
      await lifecycle.stopPresence();
      clock = clock.add(const Duration(seconds: 9));
      await sample();
      expect(posts, hasLength(4));
      client.close();
    },
  );
  test('requested context is bounded and never changes offer identity', () {
    final row = {
      'human_acceptance_required': true,
      'vehicle_id': 'V',
      'offer_id': 'O',
      'version': 1,
      'ack_deadline_ms': 30000,
      'currency': 'EUR',
      'requested_vehicle_label': 'Mercedes Vito',
      'requested_choice_kind': 'exact',
    };
    final offer = DriverRideOffer.parse(row, 'V');
    expect(offer.requestedVehicleLabel, 'Mercedes Vito');
    expect(offer.vehicleId, 'V');
    expect(
      () => DriverRideOffer.parse({
        ...row,
        'requested_choice_kind': 'silent_substitution',
      }, 'V'),
      throwsFormatException,
    );
    expect(
      () => DriverRideOffer.parse({
        ...row,
        'requested_vehicle_label': 'x' * 101,
      }, 'V'),
      throwsFormatException,
    );
  });
  testWidgets(
    'existing driver request panel keeps accept/reject, timer and requested vehicle',
    (tester) async {
      String? decision;
      const now = 1000;
      const offer = DriverRideOffer(
        id: 'O',
        version: 1,
        vehicleId: 'V',
        deadlineMs: 31000,
        pickup: 'Synthetisch ophaalpunt',
        destination: 'Synthetische bestemming',
        requestedVehicleLabel: 'Mercedes Vito',
        requestedChoiceKind: 'exact',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: DriverRideOfferPanel(
            offer: offer,
            vehiclePresentation: const DriverRideOfferVehiclePresentation(
              name: 'Mercedes Vito',
            ),
            nowMs: now,
            onDecision: (v) => decision = v,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Mercedes Vito'), findsOneWidget);
      expect(find.text('Beslistijd · 30 s'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('accept_ride')));
      expect(decision, 'accept');
      expect(find.textContaining('onderweg'), findsNothing);
    },
  );
}
