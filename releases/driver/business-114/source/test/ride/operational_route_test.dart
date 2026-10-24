import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/ride/operational_route.dart';
import 'package:fluxidi_tracking/ride/operational_route_pending_io.dart';

final route = OperationalRoute(
  address: 'Nieuwe bestemming',
  latitude: 51.25,
  longitude: 4.25,
  expectedEnd: DateTime.utc(2026, 10, 3, 12),
);
Map<String, dynamic> record({int revision = 7}) => {
  'revision': revision,
  'status': 'IN_PROGRESS',
  'customer_tracking_phase': 'in_progress',
};
http.Response confirmation(Map<String, dynamic> body) => http.Response(
  jsonEncode({
    'ok': true,
    'booking_id': 'B',
    'revision': 8,
    'operational_route': {
      'destination': body['destination'],
      'expected_end_iso': body['expected_end_iso'],
    },
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  setUp(
    () async => directory = await Directory.systemTemp.createTemp(
      'fluxidi-operational-test-',
    ),
  );
  tearDown(() async => directory.delete(recursive: true));
  OperationalRouteApi api(
    http.Client client, {
    String company = 'C',
    String actor = 'D',
    String leg = '',
    bool Function()? current,
    Map<String, String> Function()? headers,
    OperationalPendingStore? store,
  }) => OperationalRouteApi(
    baseUrl: 'https://booking.test',
    bookingId: 'B',
    tenantId: 'T',
    companyId: company,
    actorId: actor,
    leg: leg,
    isCurrent: current ?? () => true,
    headers: headers ?? () => {'Authorization': 'Bearer driver-session'},
    client: client,
    store: store ?? OperationalPendingStore(directory: directory),
  );

  test(
    'unresolved journal has a shared total bound; new concurrent intents cannot evict older uncertain writes',
    () async {
      final store = OperationalPendingStore(directory: directory),
          other = OperationalPendingStore(directory: directory);
      for (var i = 0; i < 63; i++)
        await store.write(i.toRadixString(16).padLeft(64, '0'), {'intent': i});
      final outcomes = await Future.wait(
        [
          store.write('a' * 64, {'intent': 63}),
          other.write('b' * 64, {'intent': 64}),
        ].map((operation) async {
          try {
            await operation;
            return true;
          } catch (_) {
            return false;
          }
        }),
      );
      expect(outcomes.where((success) => success).length, 1);
      expect((await store.read('0' * 64))!['intent'], 0);
      await store.write('0' * 64, {'intent': 0, 'retry': true});
      expect((await store.read('0' * 64))!['retry'], true);
      await store.clear('0' * 64);
      await store.write('c' * 64, {'intent': 65});
      expect(await store.read('c' * 64), {'intent': 65});
    },
  );

  test(
    'authorized root read normalizes a synthesized single driver leg',
    () async {
      final requests = <http.Request>[];
      final service = api(
        MockClient((r) async {
          requests.add(r);
          return r.method == 'GET'
              ? http.Response(jsonEncode({'record': record()}), 200)
              : confirmation(jsonDecode(r.body));
        }),
        leg: 'B:OUTBOUND',
      );
      final state = await service.load();
      final body = service.prepare(route, state);
      expect(body.containsKey('operational_leg'), isFalse);
      expect(await service.save(body), isA<OperationalRoute>());
      expect(requests.first.url.queryParameters, {
        'tenant_id': 'T',
        'company_id': 'C',
      });
      expect(requests.last.url.path, '/bookings/B/operational-route');
      expect(requests.last.headers['Authorization'], 'Bearer driver-session');
      expect(await service.pending(), isNull);
    },
  );

  test(
    'split update uses only the exact active leg and cannot inherit a parent route',
    () async {
      final split = {
        ...record(),
        'roundtrip_dispatch_mode': 'split_no_wait',
        'operational_route': route.toMap(),
        'operational_legs': [
          {
            'leg_id': 'B:OUTBOUND',
            'leg_type': 'outbound',
            'status': 'COMPLETED',
          },
          {'leg_id': 'B:RETURN', 'leg_type': 'return', 'status': 'IN_PROGRESS'},
        ],
      };
      expect(
        () => OperationalRideState.fromResponse(split, ''),
        throwsA(isA<OperationalRouteException>()),
      );
      expect(
        () => OperationalRideState.fromResponse(split, 'B:OUTBOUND'),
        throwsA(isA<OperationalRouteException>()),
      );
      final service = api(
        MockClient((_) async => http.Response(jsonEncode(split), 200)),
        leg: 'B:RETURN',
      );
      final state = await service.load();
      expect(state.route, isNull);
      expect(service.prepare(route, state)['operational_leg'], 'B:RETURN');
      expect(
        () => OperationalRideState.fromResponse({
          ...split,
          'revision': null,
        }, 'B:RETURN'),
        throwsA(isA<OperationalRouteException>()),
      );
    },
  );

  for (final fault in [
    '503',
    'offline',
    'missing',
    'wrong-booking',
    'wrong-destination',
  ]) {
    test('$fault preserves exact durable intent across app restart', () async {
      final posted = <String>[];
      final first = api(
        MockClient((r) async {
          if (r.method == 'GET')
            return http.Response(jsonEncode(record()), 200);
          posted.add(r.body);
          if (fault == 'offline') throw http.ClientException('offline');
          if (fault == '503')
            return http.Response(
              '{"error":"operational_route_tracking_pending"}',
              503,
            );
          if (fault == 'missing') return http.Response('{}', 200);
          final value =
              jsonDecode(confirmation(jsonDecode(r.body)).body)
                  as Map<String, dynamic>;
          if (fault == 'wrong-booking') value['booking_id'] = 'OTHER';
          if (fault == 'wrong-destination')
            value['operational_route'] = route.toMap()
              ..['destination'] = {'address': 'OTHER', 'lat': 51.2, 'lng': 4.2};
          return http.Response(jsonEncode(value), 200);
        }),
      );
      final body = first.prepare(route, await first.load());
      await expectLater(
        first.save(body),
        throwsA(
          isA<OperationalRouteException>().having(
            (e) => e.uncertain,
            'uncertain',
            true,
          ),
        ),
      );
      final second = api(
        MockClient((r) async {
          if (r.method == 'GET')
            return http.Response(jsonEncode(record(revision: 8)), 200);
          posted.add(r.body);
          return confirmation(jsonDecode(r.body));
        }),
      );
      await second.load();
      final pending = await second.pending();
      expect(pending, body);
      await second.save(pending!);
      expect(posted[1], posted[0]);
      expect(await second.pending(), isNull);
      final serialized = jsonEncode(body);
      expect(serialized.contains('driver-session'), isFalse);
      expect(body.keys.toSet(), {
        'tenant_id',
        'company_id',
        'revision',
        'update_id',
        'destination',
        'expected_end_iso',
      });
    });
  }

  test(
    'definitive revision rejection clears the old intent before fresh submission',
    () async {
      final service = api(
        MockClient(
          (r) async => r.method == 'GET'
              ? http.Response(jsonEncode(record()), 200)
              : http.Response('{"error":"revision_conflict"}', 409),
        ),
      );
      final body = service.prepare(route, await service.load());
      await expectLater(
        service.save(body),
        throwsA(
          isA<OperationalRouteException>().having(
            (e) => e.uncertain,
            'uncertain',
            false,
          ),
        ),
      );
      expect(await service.pending(), isNull);
    },
  );

  test('session change and empty bearer reject before network', () async {
    var count = 0, current = true;
    final client = MockClient((_) async {
      count++;
      return http.Response(jsonEncode(record()), 200);
    });
    final service = api(client, current: () => current);
    final body = service.prepare(route, await service.load());
    current = false;
    await expectLater(
      service.save(body),
      throwsA(isA<OperationalRouteException>()),
    );
    await expectLater(
      api(client, headers: () => {'Authorization': 'Bearer '}).load(),
      throwsA(isA<OperationalRouteException>()),
    );
    expect(count, 1);
  });

  test('journals isolate company, actor, and operational leg', () async {
    final client = MockClient((_) async => http.Response('{}', 503));
    final keys = [
      api(client),
      api(client, company: 'OTHER'),
      api(client, actor: 'OTHER'),
      api(client, leg: 'B:RETURN'),
    ].map((s) => s.pendingKey).toSet();
    expect(keys.length, 4);
  });

  test(
    'a concurrent editor cannot overwrite a pending intent or post twice',
    () async {
      final release = Completer<http.Response>();
      var posts = 0;
      final client = MockClient((r) async {
        if (r.method == 'GET') return http.Response(jsonEncode(record()), 200);
        posts++;
        return release.future;
      });
      final first = api(client), second = api(client);
      final body = first.prepare(route, await first.load());
      await second.load();
      final sending = first.save(body);
      while (posts == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await expectLater(
        second.save(second.prepare(route, await second.load())),
        throwsA(isA<OperationalRouteException>()),
      );
      release.complete(confirmation(body));
      await sending;
      expect(posts, 1);
      expect(await first.pending(), isNull);
    },
  );

  test(
    'storage crash recovery reads durable next file; persistence failure never posts',
    () async {
      var posts = 0;
      final client = MockClient((r) async {
        if (r.method != 'GET') posts++;
        return http.Response(jsonEncode(record()), 200);
      });
      final service = api(client);
      final body = service.prepare(route, await service.load());
      final folder = Directory('${directory.path}/operational-route-pending');
      await folder.create();
      await File(
        '${folder.path}/${service.pendingKey}.json.next',
      ).writeAsString(jsonEncode(body), flush: true);
      expect(await service.pending(), body);
      final blocked = File('${directory.path}/blocked');
      await blocked.writeAsString('file');
      final refusal = api(
        client,
        store: OperationalPendingStore(directory: Directory(blocked.path)),
      );
      final rejected = refusal.prepare(route, await refusal.load());
      await expectLater(
        refusal.save(rejected),
        throwsA(isA<OperationalRouteException>()),
      );
      expect(posts, 0);
    },
  );

  for (final status in ['COMPLETED', 'CANCELLED', 'NO_SHOW', 'STOPPED']) {
    test('$status dominates an old in_progress phase', () {
      final value = {
        ...record(),
        'status': status,
        'operational_route': route.toMap(),
      };
      expect(runningOperationalRoute(value), isNull);
      expect(
        () => OperationalRideState.fromResponse(value, ''),
        throwsA(isA<OperationalRouteException>()),
      );
    });
  }
  test('invalid and textual coordinates are rejected', () {
    for (final lat in ['51.2', double.nan, 100]) {
      expect(
        OperationalRoute.fromMap({
          ...route.toMap(),
          'destination': {'address': 'a', 'lat': lat, 'lng': 4.2},
        }),
        isNull,
      );
    }
  });
}
