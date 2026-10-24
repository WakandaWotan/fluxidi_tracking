import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer.dart';
import 'package:fluxidi_tracking/driver/driver_ride_offer_panel.dart';

Map<String, dynamic> row() => {
  'offer_id': 'offer-one',
  'version': 1,
  'vehicle_id': 'v',
  'human_acceptance_required': true,
  'ack_deadline_ms': 30000,
  'pickup_address': 'Station',
  'dropoff_address': 'Luchthaven',
  'price_incl_vat': 125,
  'currency': 'EUR',
};
void main() {
  test(
    'display receipt uses server timer immediately without another inbox request',
    () async {
      final client = DriverRideOfferClient(
        baseUrl: 'https://fixture.invalid',
        token: 'personal',
        vehicleId: 'v',
        driverId: 'A',
        tenantId: 'T',
        companyId: 'C',
        client: MockClient((request) async {
          expect(request.url.path, '/public/driver/dispatch/ack');
          return http.Response(
            jsonEncode({
              'ok': true,
              'offer': {
                'offer_id': 'offer-one',
                'version': 1,
                'vehicle_id': 'v',
                'driver_id': 'A',
                'tenant_id': 'T',
                'company_id': 'C',
                'ack_deadline_ms': 75000,
                'receipts': {
                  'A': {'displayed_at_ms': 45000, 'accepted': false},
                },
              },
            }),
            200,
          );
        }),
      );
      final pending = DriverRideOffer.parse({
        ...row(),
        'ack_deadline_ms': 150000,
        'response_starts_on_display': true,
        'response_timeout_ms': 30000,
      }, 'v');
      final received = await client.received(pending);
      expect(received!.secondsRemaining(46000), 29);
      expect(received.pickup, pending.pickup);
      expect(received.price, pending.price);
      client.close();
    },
  );
  test(
    'driver and company isolation includes chauffeur switches on the same vehicle',
    () {
      final scoped = {
        ...row(),
        'driver_id': 'A',
        'tenant_id': 'T',
        'company_id': 'C',
        'pickup_iso': '2026-10-13T09:05:00Z',
      };
      final offer = DriverRideOffer.parse(
        scoped,
        'v',
        driverId: 'A',
        tenantId: 'T',
        companyId: 'C',
      );
      expect(offer.pickupTime, DateTime.utc(2026, 10, 13, 9, 5));
      for (final key in ['driver_id', 'tenant_id', 'company_id']) {
        expect(
          () => DriverRideOffer.parse(
            {...scoped, key: 'other'},
            'v',
            driverId: 'A',
            tenantId: 'T',
            companyId: 'C',
          ),
          throwsFormatException,
        );
      }
      expect(
        () => DriverRideOffer.parse({
          ...scoped,
          'pickup_iso': '2026-10-13T09:05:00',
        }, 'v'),
        throwsFormatException,
      );
      expect(
        () => DriverRideOffer.parse({...scoped, 'pickup_iso': 12}, 'v'),
        throwsFormatException,
      );
    },
  );
  test(
    'hidden cockpit withdraws only its own personal offer connection',
    () async {
      final client = DriverRideOfferClient(
        baseUrl: 'https://fixture.invalid',
        token: 'own-token',
        vehicleId: 'v',
        client: MockClient((request) async {
          expect(request.url.path, '/public/driver/dispatch/offers');
          expect(request.headers['authorization'], 'Bearer own-token');
          expect(jsonDecode(request.body), {'visible': false});
          return http.Response('{"ok":true,"vehicle_id":"v","offers":[]}', 200);
        }),
      );
      await client.stopOffers();
      client.close();
    },
  );
  test(
    'display timer shows configured response time and respects server delivery expiry',
    () {
      final waiting = DriverRideOffer.parse({
        ...row(),
        'ack_deadline_ms': 150000,
        'response_starts_on_display': true,
        'response_timeout_ms': 30000,
        'displayed_at_ms': null,
      }, 'v');
      expect(waiting.secondsRemaining(45000), 30);
      expect(waiting.secondsRemaining(150000), 0);
      final displayed = DriverRideOffer.parse({
        ...row(),
        'ack_deadline_ms': 75000,
        'response_starts_on_display': true,
        'response_timeout_ms': 30000,
        'displayed_at_ms': 45000,
      }, 'v');
      expect(displayed.secondsRemaining(46000), 29);
      expect(
        () => DriverRideOffer.parse({
          ...row(),
          'response_starts_on_display': true,
        }, 'v'),
        throwsFormatException,
      );
    },
  );
  test('only human offers for the authenticated vehicle are mapped', () {
    expect(DriverRideOffer.parse(row(), 'v').secondsRemaining(1000), 29);
    expect(() => DriverRideOffer.parse(row(), 'other'), throwsFormatException);
    expect(
      () => DriverRideOffer.parse({
        ...row(),
        'human_acceptance_required': false,
      }, 'v'),
      throwsFormatException,
    );
    expect(
      () =>
          DriverRideOffer.parse({...row(), 'price_incl_vat': double.nan}, 'v'),
      throwsFormatException,
    );
  });
  test(
    'receipt and deliberate decision use different endpoints with personal bearer',
    () async {
      final paths = <String>[];
      final transport = MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer personal-fixture');
        paths.add(request.url.path);
        if (request.url.path.endsWith('/offers'))
          return http.Response(
            jsonEncode({
              'ok': true,
              'vehicle_id': 'v',
              'offers': [row()],
            }),
            200,
          );
        final body = jsonDecode(request.body);
        expect(body['offer_id'], 'offer-one');
        if (request.url.path.endsWith('/ack'))
          expect(body.containsKey('action'), false);
        if (request.url.path.endsWith('/decision'))
          expect(body['action'], 'accept');
        return http.Response('{"ok":true}', 200);
      });
      final client = DriverRideOfferClient(
        baseUrl: 'https://fixture.invalid',
        token: 'personal-fixture',
        vehicleId: 'v',
        client: transport,
      );
      final offer = (await client.offers()).single;
      await client.received(offer);
      await client.decide(offer, 'accept');
      expect(paths.map((path) => path.split('/').last), [
        'offers',
        'ack',
        'decision',
      ]);
      await expectLater(client.decide(offer, 'automatic'), throwsArgumentError);
      client.close();
    },
  );
  testWidgets(
    'large distinct accept and decline buttons show addresses price and timer',
    (tester) async {
      final actions = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: DriverRideOfferPanel(
            offer: DriverRideOffer.parse(row(), 'v'),
            nowMs: 0,
            onDecision: actions.add,
          ),
        ),
      );
      expect(find.text('Nieuwe ritaanvraag'), findsOneWidget);
      expect(find.text('Station'), findsOneWidget);
      expect(find.text('€ 125,00'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('accept_ride')));
      await tester.tap(find.byKey(const ValueKey('accept_ride')));
      expect(actions, ['accept']);
    },
  );
  testWidgets('expired or uncertain opposite choice cannot be submitted', (
    tester,
  ) async {
    final offer = DriverRideOffer.parse(row(), 'v');
    await tester.pumpWidget(
      MaterialApp(
        home: DriverRideOfferPanel(
          offer: offer,
          nowMs: 30000,
          onDecision: (_) => fail('expired'),
        ),
      ),
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('accept_ride')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DriverRideOfferPanel(
          offer: offer,
          nowMs: 1000,
          pendingAction: 'accept',
          onDecision: (_) {},
        ),
      ),
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('decline_ride')))
          .onPressed,
      isNull,
    );
  });
}
