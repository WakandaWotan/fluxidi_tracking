import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:fluxidi_tracking/navigation/driver_location_stream_owner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fluxidi_tracking/driver/planned_tracking_lifecycle.dart';

void main() {
  late Process server;
  late String base;
  late PlannedTrackingLifecycle caller;
  var driver = 'D1';
  var clock = DateTime.now();
  final payload = <String, dynamic>{
    'tenant_id': 'T1',
    'company_id': 'C1',
    'booking_id': 'B1',
  };
  Future<Map<String, dynamic>> control(
    Map<String, dynamic> body, {
    int status = 200,
  }) async {
    final r = await http.post(
      Uri.parse('$base/control'),
      body: jsonEncode(body),
    );
    expect(r.statusCode, status, reason: r.body);
    return Map<String, dynamic>.from(jsonDecode(r.body));
  }

  Future<void> reset({
    bool split = false,
    bool sameDriver = false,
    bool projectedSingleLeg = false,
  }) async {
    driver = 'D1';
    await control({
      'action': 'reset',
      'split': split,
      'sameDriver': sameDriver,
      'projectedSingleLeg': projectedSingleLeg,
    });
    clock = DateTime.now();
    caller = PlannedTrackingLifecycle(
      now: () => clock,
      bookingBaseUrl: '$base/booking',
      trackingBaseUrl: '$base/tracking',
      post: (uri, body) => http
          .post(
            uri,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $driver',
            },
            body: jsonEncode({...body, 'driver_id': driver}),
          )
          .timeout(const Duration(seconds: 5)),
    );
  }

  setUpAll(() async {
    server = await Process.start(
      'node',
      ['test/support/driver_tracking_handlers.mjs'],
      environment: {
        'FLUXIDI_BACKEND_ROOT':
            Platform.environment['FLUXIDI_BACKEND_ROOT'] ??
            'D:/Projecten/_flutter_work/fluxidi_booking_live_9af4c215_rc',
      },
    );
    final port = Completer<String>();
    server.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('PORT=') && !port.isCompleted)
            port.complete(line.substring(5));
        });
    server.stderr.transform(utf8.decoder).listen(stderr.write);
    base =
        'http://127.0.0.1:${await port.future.timeout(const Duration(seconds: 15))}';
  });
  tearDownAll(() {
    server.kill();
  });

  test('explicit pickup arrival retains presence and START creates the physical trip', () async {
    await reset(projectedSingleLeg: true);
    await expectLater(caller.confirmPickupArrival(), throwsStateError);
    await caller.enRoute({...payload, 'driver_id': 'D1'},
        legId: 'B1:OUTBOUND', isOperationalLeg: true);
    await caller.confirmPickupArrival();
    final waiting = await control({'action': 'state'});
    expect(waiting['record']['customer_tracking_phase'], 'arrived_pickup');
    expect(waiting['record']['trip'], isNull);
    expect(caller.preStartActive, isTrue);
    expect((waiting['calls'] as List).where((x) => x['path'] == '/track/session/start'), isEmpty);
    await caller.start({...payload, 'driver_id': 'D1'},
        legId: 'B1:OUTBOUND', isOperationalLeg: true);
    expect(caller.preStartActive, isFalse);
    expect((await control({'action': 'state'}))['record']['customer_tracking_phase'], 'in_progress');
  });

  for (final navigateFirst in [true, false]) {
    test(
      'projected single OUTBOUND resolves primary from confirmed ownership, NAV=$navigateFirst',
      () async {
        await reset(projectedSingleLeg: true);
        final actorPayload = {...payload, 'driver_id': 'D1'};
        if (navigateFirst) {
          await caller.enRoute(
            actorPayload,
            legId: 'B1:OUTBOUND',
            isOperationalLeg: true,
          );
          expect(
            caller.presenceMatches(bookingId: 'B1', legId: 'B1:OUTBOUND'),
            isTrue,
          );
          await caller.uploadPreStart(
            latitude: 51.1,
            longitude: 4.1,
            speedMps: 0,
            heading: 0,
            accuracy: 5,
            capturedAt: DateTime.now(),
          );
          expect(
            (await control({'action': 'snapshot'}))['eta']['target'],
            'pickup',
          );
        }
        final started = await caller.start(
          actorPayload,
          legId: 'B1:OUTBOUND',
          isOperationalLeg: true,
        );
        final again = await caller.start(
          actorPayload,
          legId: 'B1:OUTBOUND',
          isOperationalLeg: true,
        );
        expect(again['session_id'], started['session_id']);
        final state = await control({'action': 'state'});
        final calls = state['calls'] as List;
        expect(
          calls
              .where((c) => c['path'] == '/track/session/start')
              .every((c) => c['body']['operational_leg'] == 'primary'),
          isTrue,
        );
        expect(state['record']['customer_tracking_phase'], 'in_progress');
      },
    );
  }

  for (final leg in ['primary', 'B1:OUTBOUND', 'B1:RETURN']) {
    test(
      'real Driver caller -> handlers: $leg pickup, start, retry and STOP',
      () async {
        await reset(split: leg != 'primary', sameDriver: true);
        await control({'action': 'position'});
        expect(
          (await control({'action': 'snapshot', 'leg': leg}))['position'],
          isNull,
        );
        await caller.enRoute(
          payload,
          legId: leg,
          isOperationalLeg: leg != 'primary',
        );
        await caller.enRoute(
          payload,
          legId: leg,
          isOperationalLeg: leg != 'primary',
        );
        await caller.uploadPreStart(
          latitude: 51.1,
          longitude: 4.1,
          speedMps: 4,
          heading: 0,
          accuracy: 5,
          capturedAt: DateTime.now().add(const Duration(milliseconds: 1)),
        );
        final pickup = await control({'action': 'snapshot', 'leg': leg});
        expect(pickup['eta']['target'], 'pickup');
        final results = await Future.wait([
          caller.start(payload, legId: leg, isOperationalLeg: leg != 'primary'),
          caller.start(payload, legId: leg, isOperationalLeg: leg != 'primary'),
        ]);
        expect(results[0]['session_id'], results[1]['session_id']);
        final state = await control({'action': 'state'});
        final again = await caller.start(
          payload,
          legId: leg,
          isOperationalLeg: leg != 'primary',
        );
        expect(again['session_id'], results[0]['session_id']);
        expect((await control({'action': 'state'}))['record'], state['record']);
        final ping = await caller.post(Uri.parse('$base/tracking/track/ping'), {
          ...payload,
          'session_id': again['session_id'],
          'lat': 51.2,
          'lon': 4.2,
          'accuracy_m': 5,
          'ts': DateTime.now()
              .add(const Duration(milliseconds: 2))
              .toIso8601String(),
        });
        expect(ping.statusCode, 200, reason: ping.body);
        expect(
          (await control({'action': 'snapshot', 'leg': leg}))['eta']['target'],
          'destination',
        );
        final stop = await http.post(
          Uri.parse('$base/tracking/track/session/stop'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer D1',
          },
          body: jsonEncode({...payload, 'session_id': again['session_id']}),
        );
        expect(stop.statusCode, 200, reason: stop.body);
        expect(
          (await control({
            'action': 'snapshot',
            'leg': leg,
          }, status: 404))['position'],
          isNull,
        );
      },
    );
  }
  test(
    'different drivers and two active legs keep explicit assignment',
    () async {
      await reset(split: true);
      final capacity = await control({'action': 'initialize-capacity'});
      expect(capacity['ok'], isTrue);
      for (final leg in ['B1:OUTBOUND', 'B1:RETURN']) {
        driver = leg.endsWith('RETURN') ? 'D2' : 'D1';
        await caller.enRoute(payload, legId: leg, isOperationalLeg: true);
        await caller.start(payload, legId: leg, isOperationalLeg: true);
      }
      final record = (await control({'action': 'state'}))['record'];
      expect(
        record['operational_legs'].map(
          (dynamic l) => l['customer_tracking_phase'],
        ),
        ['in_progress', 'in_progress'],
      );
      expect(
        record['operational_legs'][0]['trip']['session_id'],
        isNot(record['operational_legs'][1]['trip']['session_id']),
      );
    },
  );
  test('two active legs for same driver: explicit RETURN wins', () async {
    await reset(split: true, sameDriver: true);
    for (final leg in ['B1:OUTBOUND', 'B1:RETURN']) {
      await caller.enRoute(payload, legId: leg, isOperationalLeg: true);
    }
    await caller.start(payload, legId: 'B1:RETURN', isOperationalLeg: true);
    final legs = (await control({
      'action': 'state',
    }))['record']['operational_legs'];
    expect(legs[0]['customer_tracking_phase'], 'en_route_pickup');
    expect(legs[1]['customer_tracking_phase'], 'in_progress');
  });
  test('wrong driver cannot start another concrete leg', () async {
    await reset(split: true);
    await expectLater(
      caller.start(payload, legId: 'B1:RETURN', isOperationalLeg: true),
      throwsStateError,
    );
    final legs = (await control({
      'action': 'state',
    }))['record']['operational_legs'];
    expect(legs[1]['customer_tracking_phase'], 'assigned');
    expect(legs[1]['trip'], isNull);
  });
  test('missing and invalid concrete leg never falls back', () async {
    await reset(split: true);
    expect(
      () => caller.start(payload, legId: '', isOperationalLeg: true),
      throwsStateError,
    );
    await expectLater(
      caller.start(payload, legId: 'invalid', isOperationalLeg: true),
      throwsStateError,
    );
    expect(
      (await control({
        'action': 'state',
      }))['record']['operational_legs'][0]['customer_tracking_phase'],
      'assigned',
    );
  });
  for (final fault in [
    '/tracking/start',
    '/track/session/start',
    'room',
    'lost-session',
  ]) {
    test(
      'real caller recovers $fault without repeated lifecycle or session',
      () async {
        await reset();
        await caller.enRoute(payload, legId: '', isOperationalLeg: false);
        await control({'action': 'fail', 'kind': fault});
        await expectLater(
          caller.start(payload, legId: '', isOperationalLeg: false),
          throwsStateError,
        );
        final failed = await control({'action': 'snapshot'});
        expect(failed['tracking_phase'], 'en_route_pickup');
        final recovered = await caller.start(
          payload,
          legId: '',
          isOperationalLeg: false,
        );
        final state = await control({'action': 'state'});
        expect(state['record']['trip']['session_id'], recovered['session_id']);
        expect(state['record']['customer_tracking_seq'], 3);
        expect(
          (await control({'action': 'snapshot'}))['tracking_phase'],
          'in_progress',
        );
      },
    );
  }
  test('departure failure publishes no phase; retry succeeds', () async {
    await reset();
    await control({'action': 'fail', 'kind': '/tracking/en-route'});
    await expectLater(
      caller.enRoute(payload, legId: '', isOperationalLeg: false),
      throwsStateError,
    );
    expect(
      (await control({'action': 'snapshot'}))['tracking_phase'],
      'assigned',
    );
    await caller.enRoute(payload, legId: '', isOperationalLeg: false);
    expect(
      (await control({'action': 'snapshot'}))['tracking_phase'],
      'en_route_pickup',
    );
  });
  Future<void> advance(int seconds) async {
    clock = clock.add(Duration(seconds: seconds));
    await control({'action': 'clock', 'now': clock.millisecondsSinceEpoch});
  }

  Future<void> gps({double lat = 51.1, DateTime? capturedAt}) =>
      caller.uploadPreStart(
        latitude: lat,
        longitude: 4.1,
        speedMps: 10,
        heading: 45,
        accuracy: 5,
        capturedAt: capturedAt ?? clock,
      );
  Future<void> nav([String leg = 'primary']) =>
      caller.enRoute(payload, legId: leg, isOperationalLeg: leg != 'primary');
  Future<List<dynamic>> presenceCalls() async =>
      ((await control({'action': 'state'}))['calls'] as List)
          .where((dynamic call) => call['path'] == '/track/driver/location')
          .toList();
  Future<http.Response> rawPresence(Map<String, dynamic> overrides) =>
      http.post(
        Uri.parse('$base/tracking/track/driver/location'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $driver',
        },
        body: jsonEncode({
          ...payload,
          'pre_start': true,
          'operational_leg': 'primary',
          'assignment_version': 1,
          'lat': 51.2,
          'lon': 4.2,
          'accuracy_m': 5,
          'captured_at': clock.toUtc().toIso8601String(),
          ...overrides,
        }),
      );

  for (final navigateFirst in [true, false]) {
    test(
      'projected single OUTBOUND resolves primary from confirmed ownership, NAV=$navigateFirst',
      () async {
        await reset(projectedSingleLeg: true);
        final actorPayload = {...payload, 'driver_id': 'D1'};
        if (navigateFirst) {
          await caller.enRoute(
            actorPayload,
            legId: 'B1:OUTBOUND',
            isOperationalLeg: true,
          );
          expect(
            caller.presenceMatches(bookingId: 'B1', legId: 'B1:OUTBOUND'),
            isTrue,
          );
          await caller.uploadPreStart(
            latitude: 51.1,
            longitude: 4.1,
            speedMps: 0,
            heading: 0,
            accuracy: 5,
            capturedAt: DateTime.now(),
          );
          expect(
            (await control({'action': 'snapshot'}))['eta']['target'],
            'pickup',
          );
        }
        final started = await caller.start(
          actorPayload,
          legId: 'B1:OUTBOUND',
          isOperationalLeg: true,
        );
        final again = await caller.start(
          actorPayload,
          legId: 'B1:OUTBOUND',
          isOperationalLeg: true,
        );
        expect(again['session_id'], started['session_id']);
        final state = await control({'action': 'state'});
        final calls = state['calls'] as List;
        expect(
          calls
              .where((c) => c['path'] == '/track/session/start')
              .every((c) => c['body']['operational_leg'] == 'primary'),
          isTrue,
        );
        expect(state['record']['customer_tracking_phase'], 'in_progress');
      },
    );
  }

  for (final leg in ['primary', 'B1:OUTBOUND', 'B1:RETURN']) {
    test(
      'pre-START real GPS caller $leg: assigned hidden, moving pickup, trip handover and STOP',
      () async {
        await reset(split: leg != 'primary');
        if (leg == 'B1:RETURN') driver = 'D2';
        await gps();
        expect(await presenceCalls(), isEmpty);
        expect((await rawPresence({'operational_leg': leg})).statusCode, 409);
        expect(
          (await control({'action': 'snapshot', 'leg': leg}))['position'],
          isNull,
        );
        await nav(leg);
        expect(caller.preStartActive, isTrue);
        await gps();
        final first = await control({'action': 'snapshot', 'leg': leg});
        expect(first['position']['latitude'], 51.1);
        expect(first['eta']['target'], 'pickup');
        expect(first['ops']['gps_kv_writes'], 0);
        await advance(26);
        await gps(lat: 51.2);
        final moving = await control({'action': 'snapshot', 'leg': leg});
        expect(moving['position']['latitude'], 51.2);
        final calls = await presenceCalls();
        expect(calls.last['body']['operational_leg'], leg);
        expect(calls.last['body']['assignment_version'], 1);
        final started = await caller.start(
          payload,
          legId: leg,
          isOperationalLeg: leg != 'primary',
        );
        expect(caller.preStartActive, isFalse);
        await advance(26);
        await gps(lat: 51.3);
        expect((await presenceCalls()).length, calls.length);
        // Old pickup presence is not relabelled as a passenger-trip sample.
        expect(
          (await control({'action': 'snapshot', 'leg': leg}))['position'],
          isNull,
        );
        final ping = await http.post(
          Uri.parse('$base/tracking/track/ping'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $driver',
          },
          body: jsonEncode({
            ...payload,
            'session_id': started['session_id'],
            'lat': 51.3,
            'lon': 4.3,
            'captured_at': clock.toUtc().toIso8601String(),
          }),
        );
        expect(ping.statusCode, 200, reason: ping.body);
        final trip = await control({'action': 'snapshot', 'leg': leg});
        expect(trip['position']['latitude'], 51.3);
        expect(trip['eta']['target'], 'destination');
        final stop = await http.post(
          Uri.parse('$base/tracking/track/session/stop'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $driver',
          },
          body: jsonEncode({...payload, 'session_id': started['session_id']}),
        );
        expect(stop.statusCode, 200, reason: stop.body);
        expect((await rawPresence({'operational_leg': leg})).statusCode, 409);
      },
    );
  }

  test(
    'pre-START sample never bleeds into sibling leg for the same driver',
    () async {
      await reset(split: true, sameDriver: true);
      await nav('B1:OUTBOUND');
      await gps();
      await nav('B1:RETURN');
      expect(
        (await control({'action': 'snapshot', 'leg': 'B1:RETURN'}))['position'],
        isNull,
      );
      await advance(8);
      await gps(lat: 51.2);
      expect(
        (await control({
          'action': 'snapshot',
          'leg': 'B1:RETURN',
        }))['position']['latitude'],
        51.2,
      );
      expect(
        (await control({
          'action': 'snapshot',
          'leg': 'B1:OUTBOUND',
        }))['position'],
        isNull,
      );
    },
  );

  test(
    'stale GPS disappears; resumed delivery needs fresh sample and retains no extra timer',
    () async {
      await reset();
      await nav();
      await gps();
      final old = clock;
      await advance(301);
      await control({'action': 'bootstrap'});
      final stale = await control({'action': 'snapshot'});
      expect(stale['position'], isNull);
      expect(stale['eta'], isNull);
      expect(stale['feed']['health'], 'stale');
      expect((await presenceCalls()).length, 1);
      await gps(capturedAt: old);
      expect((await presenceCalls()).length, 1);
      await gps(lat: 51.3);
      expect(
        (await control({'action': 'snapshot'}))['position']['latitude'],
        51.3,
      );
    },
  );

  for (final change in ['D2', 'D1', 'unassign', 'CANCELLED', 'COMPLETED']) {
    test(
      'pre-START stops after real $change mutation; old version cannot upload',
      () async {
        await reset();
        await nav();
        await gps();
        await control({
          'action': 'mutate',
          'path': change == 'unassign'
              ? '/company/agenda/rides/B1/unassign'
              : (change.startsWith('D')
                    ? '/bookings/B1/assign'
                    : '/bookings/B1/status'),
          'body': change.startsWith('D')
              ? {'driver_id': change, 'vehicle_id': 'V2'}
              : change == 'unassign'
              ? <String, dynamic>{}
              : {'status': change},
        });
        await advance(26);
        await gps(lat: 51.2);
        expect(caller.preStartActive, isFalse);
        expect((await rawPresence({})).statusCode, 409);
        final count = (await presenceCalls()).length;
        await advance(26);
        await gps();
        expect((await presenceCalls()).length, count);
        if (change.startsWith('D')) {
          await control({'action': 'bootstrap'});
          driver = change;
          await nav();
          expect((await control({'action': 'snapshot'}))['position'], isNull);
          await gps(lat: 51.4);
          expect(
            (await control({'action': 'snapshot'}))['position']['latitude'],
            51.4,
          );
          expect((await presenceCalls()).last['body']['assignment_version'], 2);
        }
      },
    );
  }

  for (final failure in ['presence-room', '/track/driver/location']) {
    test(
      'pre-START transient $failure backs off then automatically retries fresh GPS',
      () async {
        await reset();
        await nav();
        await control({'action': 'fail', 'kind': failure});
        await gps();
        expect(caller.preStartActive, isTrue);
        expect((await control({'action': 'snapshot'}))['position'], isNull);
        await gps();
        expect((await presenceCalls()).length, 1);
        await advance(8);
        await gps(lat: 51.3);
        expect(
          (await control({'action': 'snapshot'}))['position']['latitude'],
          51.3,
        );
      },
    );
  }

  test(
    'START drains in-flight presence; concurrent GPS does not duplicate and cannot rearm',
    () async {
      await reset();
      await nav();
      await control({'action': 'fail', 'kind': 'hold-presence'});
      final pending = gps();
      while ((await presenceCalls()).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await gps(lat: 51.3);
      final starting = caller.start(
        payload,
        legId: 'primary',
        isOperationalLeg: false,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final calls = (await control({'action': 'state'}))['calls'] as List;
      expect(
        calls.where((dynamic c) => c['path'] == '/track/session/start'),
        isEmpty,
      );
      expect(caller.preStartActive, isFalse);
      await control({'action': 'release-presence'});
      await pending;
      await starting;
      expect((await presenceCalls()).length, 1);
      expect((await rawPresence({})).statusCode, 409);
    },
  );

  test(
    'late NAV confirmation after leaving ride context cannot activate uploader',
    () async {
      await reset();
      final posted = Completer<void>(), release = Completer<void>();
      final basePost = caller.post;
      final delayed = PlannedTrackingLifecycle(
        bookingBaseUrl: caller.bookingBaseUrl,
        trackingBaseUrl: caller.trackingBaseUrl,
        post: (uri, body) async {
          final response = await basePost(uri, body);
          posted.complete();
          await release.future;
          return response;
        },
      );
      final pending = delayed.enRoute(
        payload,
        legId: 'primary',
        isOperationalLeg: false,
      );
      await posted.future;
      await delayed.stopPresence();
      release.complete();
      await pending;
      expect(delayed.preStartActive, isFalse);
    },
  );

  test(
    'network timeout keeps bounded retry; stop while response pending stays stopped',
    () async {
      await reset();
      final basePost = caller.post;
      var timeout = true;
      caller = PlannedTrackingLifecycle(
        bookingBaseUrl: caller.bookingBaseUrl,
        trackingBaseUrl: caller.trackingBaseUrl,
        now: () => clock,
        post: (uri, body) async {
          if (uri.path.endsWith('/track/driver/location') && timeout) {
            timeout = false;
            throw TimeoutException('temporary network timeout');
          }
          return basePost(uri, body);
        },
      );
      await nav();
      await gps();
      expect(caller.preStartActive, isTrue);
      await advance(8);
      await gps();
      expect((await control({'action': 'snapshot'}))['position'], isNotNull);
      await caller.stopPresence();
      await advance(26);
      await gps();
      expect((await presenceCalls()).length, 1);
    },
  );

  test(
    'wrong or ambiguous leg, version, booking and identity fail closed',
    () async {
      await reset(split: true);
      await nav('B1:OUTBOUND');
      for (final override in [
        <String, dynamic>{'operational_leg': ''},
        {'operational_leg': 'primary'},
        {'operational_leg': 'B1:RETURN'},
        {'operational_leg': 'bad'},
        {'operational_leg': 'B1:OUTBOUND', 'assignment_version': 2},
        {'operational_leg': 'B1:OUTBOUND', 'booking_id': 'other'},
      ]) {
        expect((await rawPresence(override)).statusCode, 409);
      }
      for (final field in ['tenant_id', 'company_id', 'driver_id']) {
        expect(
          (await rawPresence({
            'operational_leg': 'B1:OUTBOUND',
            field: 'wrong',
          })).statusCode,
          403,
        );
      }
      final unowned = await http.get(
        Uri.parse(
          '$base/tracking/track/customer/live?tenant_id=T1&company_id=C1&booking_id=B1&operational_leg=B1%3AOUTBOUND',
        ),
        headers: {'authorization': 'Bearer unknown'},
      );
      expect(unowned.statusCode, 404);
    },
  );
  for (final duty in ['offDuty', 'paused']) {
    test('confirmed pickup GPS survives $duty through real HTTP handlers', () async {
      await reset();
      await control({'action': 'duty', duty: true});
      await nav();
      final before = await control({'action': 'state'});
      await gps();
      final live = await control({'action': 'snapshot'});
      expect(live['position']['latitude'], 51.1);
      expect(live['eta']['target'], 'pickup');
      expect(live['ops']['gps_kv_writes'], 0);
      final after = await control({'action': 'state'});
      expect(after['bookingWrites'], before['bookingWrites']);
      expect(after['trackingWrites'], before['trackingWrites']);
      expect(after['record']['trip'], isNull);
      expect(caller.preStartActive, isTrue);
    });
  }

  test(
    'duplicate NAV preserves throttle; presence has no booking/GPS KV writes',
    () async {
      await reset();
      await nav();
      final before = await control({'action': 'state'});
      await gps();
      await nav();
      await gps();
      final after = await control({'action': 'state'});
      expect((await presenceCalls()).length, 1);
      expect(after['bookingWrites'], before['bookingWrites']);
      expect(after['trackingWrites'], before['trackingWrites']);
    },
  );

  test(
    'simultaneous OUTBOUND and RETURN with different drivers keep separate GPS',
    () async {
      await reset(split: true);
      await nav('B1:OUTBOUND');
      await gps(lat: 51.1);
      driver = 'D2';
      await nav('B1:RETURN');
      await advance(8);
      await gps(lat: 51.4);
      expect(
        (await control({
          'action': 'snapshot',
          'leg': 'B1:OUTBOUND',
        }))['position']['latitude'],
        51.1,
      );
      expect(
        (await control({
          'action': 'snapshot',
          'leg': 'B1:RETURN',
        }))['position']['latitude'],
        51.4,
      );
    },
  );

  test(
    'same driver executing another leg cannot keep uploading pre-START presence',
    () async {
      await reset(split: true, sameDriver: true);
      await nav('B1:OUTBOUND');
      await gps();
      await caller.start(payload, legId: 'B1:RETURN', isOperationalLeg: true);
      expect(
        (await rawPresence({'operational_leg': 'B1:OUTBOUND'})).statusCode,
        409,
      );
    },
  );

  test(
    'reassignment while GPS request is delayed is rejected before hot-state write',
    () async {
      await reset();
      await nav();
      await control({'action': 'fail', 'kind': 'hold-presence'});
      final pending = gps();
      while ((await presenceCalls()).isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await control({
        'action': 'mutate',
        'path': '/bookings/B1/assign',
        'body': {'driver_id': 'D1', 'vehicle_id': 'V2'},
      });
      await control({'action': 'release-presence'});
      await pending;
      expect(caller.preStartActive, isFalse);
      await nav();
      await control({'action': 'bootstrap'});
      expect((await control({'action': 'snapshot'}))['position'], isNull);
    },
  );

  test(
    'foreground resume after cancellation cannot reactivate pre-START GPS',
    () async {
      await reset();
      await nav();
      await gps();
      // Existing driver lifecycle retains the stream. Simulate OS suspension of
      // callbacks, then actual cancellation and a fresh callback on resume.
      await advance(45);
      await control({
        'action': 'mutate',
        'path': '/bookings/B1/status',
        'body': {'status': 'CANCELLED'},
      });
      await gps(lat: 51.5);
      expect(caller.preStartActive, isFalse);
      final before = (await presenceCalls()).length;
      await advance(30);
      await gps();
      expect((await presenceCalls()).length, before);
    },
  );

  for (final navigateFirst in [true, false]) {
    test(
      'projected single OUTBOUND resolves primary from confirmed ownership, NAV=$navigateFirst',
      () async {
        await reset(projectedSingleLeg: true);
        final actorPayload = {...payload, 'driver_id': 'D1'};
        if (navigateFirst) {
          await caller.enRoute(
            actorPayload,
            legId: 'B1:OUTBOUND',
            isOperationalLeg: true,
          );
          expect(
            caller.presenceMatches(bookingId: 'B1', legId: 'B1:OUTBOUND'),
            isTrue,
          );
          await caller.uploadPreStart(
            latitude: 51.1,
            longitude: 4.1,
            speedMps: 0,
            heading: 0,
            accuracy: 5,
            capturedAt: DateTime.now(),
          );
          expect(
            (await control({'action': 'snapshot'}))['eta']['target'],
            'pickup',
          );
        }
        final started = await caller.start(
          actorPayload,
          legId: 'B1:OUTBOUND',
          isOperationalLeg: true,
        );
        final again = await caller.start(
          actorPayload,
          legId: 'B1:OUTBOUND',
          isOperationalLeg: true,
        );
        expect(again['session_id'], started['session_id']);
        final state = await control({'action': 'state'});
        final calls = state['calls'] as List;
        expect(
          calls
              .where((c) => c['path'] == '/track/session/start')
              .every((c) => c['body']['operational_leg'] == 'primary'),
          isTrue,
        );
        expect(state['record']['customer_tracking_phase'], 'in_progress');
      },
    );
  }

  for (final leg in ['primary', 'B1:OUTBOUND', 'B1:RETURN']) {
    test(
      'FGS owner -> actual presence/session/START/STOP handlers: $leg',
      () async {
        await reset(split: leg != 'primary');
        if (leg == 'B1:RETURN') driver = 'D2';
        var opens = 0, closes = 0;
        String? session;
        var valid = true;
        Future<void> upload = Future.value();
        final stream = StreamController<geo.Position>(
          onCancel: () {
            closes++;
          },
        );
        final owner = DriverLocationStreamOwner(
          observeLifecycle: false,
          now: () => clock,
          permissionReady: () async => true,
          foregroundConfirmed: () async => true,
          operationValid: () =>
              valid && (caller.preStartActive || session != null),
          openStream: (fgs) {
            expect(fgs, isTrue);
            opens++;
            return stream.stream;
          },
          onPosition: (pos) {
            upload = () async {
              if (session == null) {
                await gps(lat: pos.latitude);
              } else {
                final r = await caller.gpsUploads.send(
                  capturedAt: pos.timestamp,
                  request: () =>
                      caller.post(Uri.parse('$base/tracking/track/ping'), {
                        ...payload,
                        'session_id': session,
                        'lat': pos.latitude,
                        'lon': pos.longitude,
                        'captured_at': pos.timestamp.toUtc().toIso8601String(),
                      }),
                );
                if (r != null) expect(r.statusCode, 200, reason: r.body);
              }
            }();
          },
        );
        Future<void> sample(double lat) async {
          stream.add(
            geo.Position(
              latitude: lat,
              longitude: 4.1,
              timestamp: clock,
              accuracy: 5,
              altitude: 0,
              altitudeAccuracy: 0,
              heading: 45,
              headingAccuracy: 0,
              speed: 10,
              speedAccuracy: 0,
            ),
          );
          await Future<void>.delayed(Duration.zero);
          await upload;
        }

        try {
          expect(await owner.ensure(foreground: true), isFalse);
          expect(opens, 0); // assigned alone
          await nav(leg);
          expect(await owner.ensure(foreground: true), isTrue);
          final subscription = owner.subscription;
          owner.didChangeAppLifecycleState(AppLifecycleState.paused); // Maps
          await sample(51.1);
          expect(
            (await control({
              'action': 'snapshot',
              'leg': leg,
            }))['eta']['target'],
            'pickup',
          );
          final started = await caller.start(
            payload,
            legId: leg,
            isOperationalLeg: leg != 'primary',
          );
          session = started['session_id'] as String;
          expect(await owner.ensure(foreground: true), isTrue);
          expect(identical(subscription, owner.subscription), isTrue);
          await advance(1);
          await sample(51.2); // START must not reset the presence cooldown.
          final during = await control({'action': 'state'});
          expect(
            (during['calls'] as List).where(
              (dynamic c) => c['path'] == '/track/ping',
            ),
            isEmpty,
          );
          await advance(7);
          await sample(51.3);
          final snapshot = await control({'action': 'snapshot', 'leg': leg});
          expect(snapshot['position']['latitude'], 51.3);
          expect(snapshot['eta']['target'], 'destination');
          expect((await presenceCalls()).length, 1);
          final stopped = await caller.post(
            Uri.parse('$base/tracking/track/session/stop'),
            {...payload, 'session_id': session},
          );
          expect(stopped.statusCode, 200, reason: stopped.body);
          valid = false;
          await owner.stop();
          expect(opens, 1);
          expect(closes, 1);
          expect(owner.uploadingAllowed, isFalse);
        } finally {
          await owner.dispose();
          await stream.close();
        }
      },
    );
  }
  for (final change in ['D2', 'D1', 'unassign', 'CANCELLED', 'COMPLETED']) {
    test(
      'active trip $change mutation preserves assignment or revokes GPS after positive closure',
      () async {
        await reset();
        await nav();
        final started = await caller.start(
          payload,
          legId: 'primary',
          isOperationalLeg: false,
        );
        final rejected = change.startsWith('D') || change == 'unassign';
        final original = await control({'action': 'state'});
        final mutation = await control({
          'action': 'mutate',
          'path': change == 'unassign'
              ? '/company/agenda/rides/B1/unassign'
              : change.startsWith('D')
              ? '/bookings/B1/assign'
              : '/bookings/B1/status',
          'body': change.startsWith('D')
              ? {'driver_id': change, 'vehicle_id': 'V2'}
              : change == 'unassign'
              ? <String, dynamic>{}
              : {'status': change},
        }, status: rejected ? 409 : 200);
        if (rejected) {
          expect(
            mutation['error'],
            'active_assignment_change_requires_completion',
          );
          expect(
            (await control({'action': 'state'}))['record'],
            original['record'],
          );
        }
        final before = await control({'action': 'state'});
        final ping = await caller.post(Uri.parse('$base/tracking/track/ping'), {
          ...payload,
          'session_id': started['session_id'],
          'lat': 51.5,
          'lon': 4.5,
          'captured_at': clock.toUtc().toIso8601String(),
        });
        expect(ping.statusCode, rejected ? 200 : 409, reason: ping.body);
        if (!rejected) {
          expect(
            (await control({'action': 'state'}))['trackingWrites'],
            before['trackingWrites'],
          );
        } else {
          expect(
            (await control({'action': 'snapshot'}))['position']['latitude'],
            51.5,
          );
        }
      },
    );
  }

  for (final leg in ['primary', 'B1:OUTBOUND', 'B1:RETURN'])
    test('M5 500ms GPS for one minute per phase: $leg', () async {
      await reset(split: leg != 'primary');
      if (leg == 'B1:RETURN') driver = 'D2';
      await nav(leg);
      for (var i = 0; i < 120; i++) {
        clock = clock.add(const Duration(milliseconds: 500));
        await control({'action': 'clock', 'now': clock.millisecondsSinceEpoch});
        await gps(lat: 51.1 + i / 10000);
      }
      expect((await presenceCalls()).length, 8);
      final pre = await control({'action': 'snapshot', 'leg': leg});
      expect(pre['position']['latitude'], closeTo(51.1112, 0.000001));
      expect(pre['eta']['target'], 'pickup');
      final session = await caller.start(
        payload,
        legId: leg,
        isOperationalLeg: leg != 'primary',
      );
      var sent = 0;
      for (var i = 0; i < 120; i++) {
        clock = clock.add(const Duration(milliseconds: 500));
        await control({'action': 'clock', 'now': clock.millisecondsSinceEpoch});
        final response = await caller.gpsUploads.send(
          capturedAt: clock,
          request: () => caller.post(Uri.parse('$base/tracking/track/ping'), {
            ...payload,
            'session_id': session['session_id'],
            'lat': 51.2 + i / 10000,
            'lon': 4.2,
            'accuracy_m': 5,
            'captured_at': clock.toUtc().toIso8601String(),
          }),
        );
        if (response != null) {
          sent++;
          expect(response.statusCode, 200, reason: response.body);
        }
      }
      expect(sent, inInclusiveRange(7, 8));
      // Grants retain their existing 90s lease; refresh through the real handler.
      await control({'action': 'bootstrap', 'leg': leg});
      final active = await control({'action': 'snapshot', 'leg': leg});
      expect(active['position'], isNotNull);
      expect(active['eta']['target'], 'destination');
    });

  test(
    'M5 actual Room 429 remains transient and resumes with newest fresh GPS',
    () async {
      await reset();
      await nav();
      for (var i = 0; i < 12; i++)
        expect((await rawPresence({'lat': 51.1 + i / 10000})).statusCode, 200);
      expect((await rawPresence({})).statusCode, 429);
      await gps(); // Gate receives the actual Room retry_after_seconds.
      expect(caller.preStartActive, isTrue);
      final before = (await presenceCalls()).length;
      await advance(59);
      await gps(lat: 51.5);
      expect((await presenceCalls()).length, before);
      await advance(2);
      await gps(lat: 51.6); // allow the bridge wall-clock boundary
      expect((await presenceCalls()).length, before + 1);
      expect(caller.preStartActive, isTrue);
      final snapshot = await control({'action': 'snapshot'});
      expect(snapshot['position']['latitude'], 51.6);
      expect(snapshot['eta']['target'], 'pickup');
    },
  );
}
