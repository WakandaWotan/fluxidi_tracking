import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/ride/operational_route.dart';
import 'package:fluxidi_tracking/navigation/external/planned_booking_canonical_destination.dart';
import 'operational_route_editor_test.dart' show WidgetJournal;

void main() {
  final stop = OperationalStop(
    address: 'Gent',
    latitude: 51.05,
    longitude: 3.72,
    waitSeconds: 600,
    notBefore: DateTime.utc(2026, 10, 3, 12),
  );
  final route = OperationalRoute(
    address: 'Terug Sint-Niklaas',
    latitude: 51.165,
    longitude: 4.142,
    expectedEnd: DateTime.utc(2026, 10, 3, 13),
    remainingRouteComplete: true,
    remainingStops: [stop],
  );
  Map<String, dynamic> record() => {
    'revision': 7,
    'status': 'PLANNED',
    'roundtrip_dispatch_mode': 'continuous_wait',
    'return_enabled': true,
    'operational_legs': [
      {
        'leg_id': 'B:OUTBOUND',
        'leg_type': 'outbound',
        'customer_tracking_phase': 'in_progress',
        'operational_route': route.toMap(),
      },
      {'leg_id': 'B:RETURN', 'leg_type': 'return', 'status': 'PLANNED'},
    ],
  };
  test(
    'continuous mutation loads the selected active leg while shared capacity remains a root concern',
    () {
      final state = OperationalRideState.fromResponse(record(), 'B:OUTBOUND');
      expect(state.mutationLeg, 'B:OUTBOUND');
      expect(state.requiresItinerary, true);
      expect(state.route!.nextDestination.address, 'Gent');
      expect(
        OperationalRideState.fromResponse(record(), '').mutationLeg,
        'B:OUTBOUND',
      );
      expect(
        () => OperationalRideState.fromResponse(record(), 'B:RETURN'),
        throwsA(isA<OperationalRouteException>()),
      );
      expect(
        () => OperationalRideState.fromResponse({
          ...record(),
          'status': 'COMPLETED',
        }, 'B:OUTBOUND'),
        throwsA(isA<OperationalRouteException>()),
      );
    },
  );
  test(
    'stop order and departure are round-tripped, and navigation points at the next stop',
    () {
      final decoded = OperationalRoute.fromMap(route.toMap())!;
      expect(decoded.toMap(), route.toMap());
      expect(decoded.nextDestination.address, 'Gent');
      final target = {
        'status': 'IN_PROGRESS',
        'operational_route': decoded.toMap(),
      };
      final navigation = PlannedBookingCanonicalDestinationResolver.resolve(
        bookingId: 'B',
        details: target,
        toLabel: 'Offerte',
      );
      expect(navigation.dropoff.latitude, 51.05);
      expect(navigation.dropoff.address, 'Gent');
      expect(
        operationalHydratedDestination(target, 'Oud adres', 'Huidig'),
        'Gent',
      );
      expect(decoded.address, 'Terug Sint-Niklaas');
    },
  );
  for (final patch in [
    {'remaining_route_complete': false},
    {'remaining_stops': List.filled(9, stop.toMap())},
    {
      'remaining_stops': [
        {...stop.toMap(), 'wait_seconds': -1},
      ],
    },
    {
      'remaining_stops': [
        {...stop.toMap(), 'not_before_iso': 'bad'},
      ],
    },
    {
      'remaining_stops': [
        {...stop.toMap(), 'lat': '51.05'},
      ],
    },
    {
      'remaining_stops': [
        {...stop.toMap(), 'not_before_iso': '2026-10-04T12:00:00Z'},
      ],
    },
  ])
    test(
      'invalid itinerary never becomes a confirmed navigation route $patch',
      () => expect(
        OperationalRoute.fromMap({...route.toMap(), ...patch}),
        isNull,
      ),
    );
  test(
    'lost multi-stop response retains exact ordered body; a wrong stop confirmation cannot clear it',
    () async {
      final journal = WidgetJournal();
      var wrong = true;
      final api = OperationalRouteApi(
        baseUrl: 'https://booking.test',
        bookingId: 'B',
        tenantId: 'T',
        companyId: 'C',
        actorId: 'D',
        leg: 'B:OUTBOUND',
        headers: () => {'Authorization': 'Bearer session'},
        isCurrent: () => true,
        store: journal,
        client: MockClient((request) async {
          if (request.method == 'GET')
            return http.Response(jsonEncode(record()), 200);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'ok': true,
              'booking_id': 'B',
              'revision': 8,
              'operational_route': {
                ...body,
                if (wrong)
                  'remaining_stops': [
                    {...stop.toMap(), 'wait_seconds': 601},
                  ],
              },
            }),
            200,
          );
        }),
      );
      final state = await api.load(),
          body = api.prepare(route, await api.load());
      expect(state.mutationLeg, 'B:OUTBOUND');
      await expectLater(
        api.save(body),
        throwsA(
          isA<OperationalRouteException>().having(
            (error) => error.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      expect(await api.pending(), body);
      wrong = false;
      expect((await api.save(body)).toMap(), route.toMap());
      expect(await api.pending(), isNull);
      api.dispose();
    },
  );
}
