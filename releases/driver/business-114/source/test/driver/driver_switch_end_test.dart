import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/driver_switch_end.dart';
import 'package:fluxidi_tracking/driver/vehicle_duty_client.dart';

const _tenant = 'tenant-fixture';
const _company = 'company-fixture';
const _driver = 'driver-fixture';
const _vehicle = 'vehicle-fixture';
const _bearer = 'personal-fixture-bearer';

Map<String, dynamic> _status(String availability) => {
  'ok': true,
  'tenant_id': _tenant,
  'company_id': _company,
  'driver_id': _driver,
  'driver': {
    'driver_id': _driver,
    'availability_status': availability,
    'assigned_vehicle_id': _vehicle,
    'live_connected': true,
  },
};

Map<String, dynamic> _offline() => {
  'ok': true,
  'tenant_id': _tenant,
  'company_id': _company,
  'driver_id': _driver,
  'availability_status': 'offline',
};

Map<String, dynamic> _dutyState({bool active = true, int version = 7}) => {
  'ok': true,
  'version': version,
  'duties': [
    if (active)
      {
        'duty_id': 'duty-fixture',
        'driver_id': _driver,
        'vehicle_id': _vehicle,
        'ended_at_ms': null,
      },
  ],
};

http.Response _json(Object? body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

Matcher _code(String expected) =>
    isA<VehicleDutyException>().having((error) => error.code, 'code', expected);

typedef _Step = FutureOr<http.Response> Function(http.Request request);

class _Transport {
  _Transport(List<_Step> steps) : _steps = [...steps] {
    client = MockClient((request) async {
      calls.add(request);
      expect(request.url.origin, 'https://booking.fixture.invalid');
      expect(request.headers['authorization'], 'Bearer $_bearer');
      expect(request.headers.values, isNot(contains('company-bearer')));
      if (_steps.isEmpty) {
        fail('Unexpected ${request.method} ${request.url.path}');
      }
      return await _steps.removeAt(0)(request);
    });
  }

  final List<_Step> _steps;
  final List<http.Request> calls = [];
  late final MockClient client;

  List<String> get paths =>
      calls.map((request) => '${request.method} ${request.url.path}').toList();
  void verifyConsumed() => expect(_steps, isEmpty);
}

Future<void> _run(
  _Transport transport, {
  String token = _bearer,
  String vehicle = _vehicle,
  bool Function()? isCurrent,
}) => confirmDriverOfflineForSwitch(
  bookingBaseUrl: 'https://booking.fixture.invalid',
  token: token,
  tenantId: _tenant,
  companyId: _company,
  driverId: _driver,
  vehicleId: vehicle,
  isCurrent: isCurrent ?? () => true,
  client: transport.client,
);

void main() {
  test(
    'manual duty end is confirmed by empty duty readback and own offline status',
    () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) => _json(_dutyState()),
        (request) {
          final body = jsonDecode(request.body) as Map;
          expect(body['action'], 'end');
          expect(body['vehicle_id'], _vehicle);
          expect(body['duty_id'], 'duty-fixture');
          expect(body['expected_version'], 7);
          expect(body['command_id'], startsWith('switch-end-'));
          expect(body.containsKey('device_token'), isFalse);
          return _json({
            'ok': true,
            'version': 8,
            'duty': {'ended_at_ms': 1234},
          });
        },
        (request) => _json(_dutyState(active: false, version: 8)),
        (request) => _json(_status('offline')),
      ]);
      await _run(transport);
      transport.verifyConsumed();
      expect(transport.paths, [
        'GET /public/driver/status',
        'POST /public/driver/vehicle-duty-state',
        'POST /public/driver/vehicle-duty',
        'POST /public/driver/vehicle-duty-state',
        'GET /public/driver/status',
      ]);
    },
  );

  for (final policy in [
    ('vehicle_duty_not_configured', 409),
    ('vehicle_operations_disabled', 503),
  ]) {
    test(
      'only explicit ${policy.$1} selects legacy offline authority',
      () async {
        final transport = _Transport([
          (request) => _json(_status('available')),
          (request) => _json({'ok': false, 'error': policy.$1}, policy.$2),
          (request) {
            expect(jsonDecode(request.body), {
              'availability_status': 'offline',
            });
            return _json(_offline());
          },
          (request) => _json(_status('offline')),
        ]);
        await _run(transport);
        transport.verifyConsumed();
        expect(transport.paths, [
          'GET /public/driver/status',
          'POST /public/driver/vehicle-duty-state',
          'POST /public/driver/availability',
          'GET /public/driver/status',
        ]);
      },
    );
  }

  test(
    'unassigned personal actor uses existing offline endpoint without duty command',
    () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) => _json(_offline()),
        (request) => _json(_status('offline')),
      ]);
      await _run(transport, vehicle: '');
      transport.verifyConsumed();
      expect(transport.paths, [
        'GET /public/driver/status',
        'POST /public/driver/availability',
        'GET /public/driver/status',
      ]);
    },
  );

  test(
    'empty configured duty is not a legacy policy and still needs offline status',
    () async {
      final transport = _Transport([
        (request) => _json(_status('offline')),
        (request) => _json(_dutyState(active: false)),
        (request) => _json(_status('offline')),
      ]);
      await _run(transport);
      transport.verifyConsumed();
      expect(
        transport.calls.where(
          (request) => request.url.path.endsWith('availability'),
        ),
        isEmpty,
      );
      expect(
        transport.calls.where(
          (request) => request.url.path.endsWith('/vehicle-duty'),
        ),
        isEmpty,
      );
    },
  );

  test('configured empty duty cannot confirm an available actor', () async {
    final transport = _Transport([
      (request) => _json(_status('available')),
      (request) => _json(_dutyState(active: false)),
      (request) => _json(_status('available')),
    ]);
    await expectLater(
      _run(transport),
      throwsA(_code('driver_offline_not_confirmed')),
    );
    transport.verifyConsumed();
  });

  for (final busy in ['busy', 'on_trip', 'in_progress']) {
    test(
      'server $busy state denies before any duty or availability write',
      () async {
        final transport = _Transport([(request) => _json(_status(busy))]);
        await expectLater(
          _run(transport),
          throwsA(_code('active_ride_blocks_duty_change')),
        );
        transport.verifyConsumed();
        expect(transport.calls.single.method, 'GET');
      },
    );
  }

  for (final failure in [
    ('unauthorized', 401),
    ('forbidden', 403),
    ('vehicle_device_auth_required', 403),
    ('duty_projection_pending', 503),
    ('tracking_unavailable', 503),
    ('vehicle_session_mismatch', 403),
    ('duty_version_conflict', 409),
  ]) {
    test('duty ${failure.$1} never falls back to another authority', () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) => _json({'ok': false, 'error': failure.$1}, failure.$2),
      ]);
      await expectLater(_run(transport), throwsA(_code(failure.$1)));
      transport.verifyConsumed();
      expect(
        transport.calls.where(
          (request) => request.url.path.endsWith('availability'),
        ),
        isEmpty,
      );
    });
  }

  test(
    'active ride race reported by duty end denies without offline fallback',
    () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) => _json(_dutyState()),
        (request) => _json({
          'ok': false,
          'error': 'active_ride_blocks_duty_change',
        }, 409),
      ]);
      await expectLater(
        _run(transport),
        throwsA(_code('active_ride_blocks_duty_change')),
      );
      transport.verifyConsumed();
      expect(transport.calls.last.url.path, '/public/driver/vehicle-duty');
    },
  );

  test(
    'duty timeout is not a policy response and never falls through',
    () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) => throw TimeoutException('fixture transport timed out'),
      ]);
      await expectLater(_run(transport), throwsA(isA<TimeoutException>()));
      transport.verifyConsumed();
      expect(transport.calls, hasLength(2));
    },
  );

  test('end success with retained active duty fails readback', () async {
    final transport = _Transport([
      (request) => _json(_status('available')),
      (request) => _json(_dutyState()),
      (request) => _json({'ok': true, 'version': 8}),
      (request) => _json(_dutyState(version: 8)),
    ]);
    await expectLater(
      _run(transport),
      throwsA(_code('driver_offline_not_confirmed')),
    );
    transport.verifyConsumed();
  });

  test(
    'manual end and empty duty do not confirm a still-online driver record',
    () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) => _json(_dutyState()),
        (request) => _json({'ok': true, 'version': 8}),
        (request) => _json(_dutyState(active: false, version: 8)),
        (request) => _json(_status('available')),
      ]);
      await expectLater(
        _run(transport),
        throwsA(_code('driver_offline_not_confirmed')),
      );
      transport.verifyConsumed();
    },
  );

  for (final field in ['tenant_id', 'company_id', 'driver_id']) {
    test(
      'initial status from wrong $field cannot select an authority',
      () async {
        final wrong = {..._status('available'), field: 'foreign-fixture'};
        final transport = _Transport([(request) => _json(wrong)]);
        await expectLater(
          _run(transport),
          throwsA(_code('driver_session_scope_mismatch')),
        );
        transport.verifyConsumed();
        expect(transport.calls.single.method, 'GET');
      },
    );
  }

  test(
    'legacy success body with another actor fails before status readback',
    () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) =>
            _json({'ok': false, 'error': 'vehicle_duty_not_configured'}, 409),
        (request) => _json({..._offline(), 'driver_id': 'foreign-fixture'}),
      ]);
      await expectLater(
        _run(transport),
        throwsA(_code('driver_session_scope_mismatch')),
      );
      transport.verifyConsumed();
    },
  );

  test(
    'legacy response available is not successful offline confirmation',
    () async {
      final transport = _Transport([
        (request) => _json(_status('available')),
        (request) =>
            _json({'ok': false, 'error': 'vehicle_duty_not_configured'}, 409),
        (request) => _json({..._offline(), 'availability_status': 'available'}),
      ]);
      await expectLater(
        _run(transport),
        throwsA(_code('driver_offline_not_confirmed')),
      );
      transport.verifyConsumed();
    },
  );

  test('legacy HTTP200 ok:false never confirms offline', () async {
    final transport = _Transport([
      (request) => _json(_status('available')),
      (request) =>
          _json({'ok': false, 'error': 'vehicle_duty_not_configured'}, 409),
      (request) => _json({
        ..._offline(),
        'ok': false,
        'error': 'driver_index_commit_failed',
      }),
    ]);
    await expectLater(
      _run(transport),
      throwsA(_code('driver_index_commit_failed')),
    );
    transport.verifyConsumed();
  });

  for (final failure in [
    (401, 'unauthorized'),
    (503, 'driver_index_commit_failed'),
  ]) {
    test(
      'legacy ${failure.$1} keeps failure despite requested offline status',
      () async {
        final transport = _Transport([
          (request) => _json(_status('available')),
          (request) =>
              _json({'ok': false, 'error': 'vehicle_duty_not_configured'}, 409),
          (request) => _json({'ok': false, 'error': failure.$2}, failure.$1),
        ]);
        await expectLater(_run(transport), throwsA(_code(failure.$2)));
        transport.verifyConsumed();
      },
    );
  }

  test('malformed duty response is not a legacy policy selection', () async {
    final transport = _Transport([
      (request) => _json(_status('available')),
      (request) => _json({'ok': true, 'version': 1, 'duties': 'invalid'}),
    ]);
    await expectLater(_run(transport), throwsA(_code('invalid_response')));
    transport.verifyConsumed();
  });

  test(
    'missing personal auth is rejected without a network or company fallback',
    () async {
      final transport = _Transport([]);
      await expectLater(
        _run(transport, token: ''),
        throwsA(_code('driver_auth_required')),
      );
      expect(transport.calls, isEmpty);
    },
  );

  test('already changed actor makes no requests', () async {
    final transport = _Transport([]);
    await expectLater(
      _run(transport, isCurrent: () => false),
      throwsA(_code('driver_session_changed')),
    );
    expect(transport.calls, isEmpty);
  });

  for (final stage in ['status', 'state', 'end', 'availability', 'readback']) {
    test(
      'late actor change at $stage cannot confirm or continue old-session requests',
      () async {
        var current = true;
        final delayed = Completer<http.Response>();
        final reached = Completer<void>();
        Future<http.Response> hold(http.Request request) {
          reached.complete();
          return delayed.future;
        }

        final steps = <_Step>[
          if (stage == 'status')
            hold
          else
            (request) => _json(_status('available')),
        ];
        if (stage != 'status') {
          if (stage == 'availability' || stage == 'readback') {
            steps.add(
              (request) => _json({
                'ok': false,
                'error': 'vehicle_duty_not_configured',
              }, 409),
            );
            steps.add(
              stage == 'availability' ? hold : (request) => _json(_offline()),
            );
            if (stage == 'readback') steps.add(hold);
          } else {
            steps.add(
              stage == 'state' ? hold : (request) => _json(_dutyState()),
            );
            if (stage == 'end') steps.add(hold);
          }
        }
        final transport = _Transport(steps);
        final future = _run(transport, isCurrent: () => current);
        final expectation = expectLater(
          future,
          throwsA(_code('driver_session_changed')),
        );
        await reached.future;
        current = false;
        delayed.complete(
          _json(switch (stage) {
            'state' => _dutyState(),
            'end' => {'ok': true, 'version': 8},
            'availability' => _offline(),
            'readback' => _status('offline'),
            _ => _status('available'),
          }),
        );
        await expectation;
        transport.verifyConsumed();
      },
    );
  }
}
