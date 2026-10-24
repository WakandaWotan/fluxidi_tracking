import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/driver_sign_in_activation.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

const actor = ActiveDriverSession(
  driverId: 'driver',
  employeeNumber: 'unused',
  fullName: 'Fixture',
  phone: '',
  loggedInAt: '',
  updatedAt: '',
  tenantId: 'tenant',
  companyId: 'company',
  assignedVehicleId: 'vehicle',
  driverSessionToken: 'real-server-fixture',
  linkMethod: 'public_driver_login',
);
Map<String, dynamic> scope() => {
  'ok': true,
  'tenant_id': 'tenant',
  'company_id': 'company',
  'driver_id': 'driver',
  'is_active': true,
  'availability_status': 'available',
};
Map<String, dynamic> status(String state) => {
  ...scope(),
  'driver': {
    'driver_id': 'driver',
    'is_active': true,
    'availability_status': state,
    'assigned_vehicle_id': 'vehicle',
  },
};
http.Response reply(Map data, [int code = 200]) =>
    http.Response(jsonEncode(data), code);
void main() {
  test('already available still starts its required missing vehicle duty', () async {
    final calls = <String>[];
    Map? command;
    final result = await DriverSignInActivation(actor).activate(
      baseUrl: 'https://fixture.invalid',
      isCurrent: () => true,
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/status')) return reply(status('available'));
        if (request.url.path.endsWith('/vehicle-duty-state')) {
          return reply({'ok': true, 'version': 7, 'duties': []});
        }
        expect(request.url.path, '/public/driver/vehicle-duty');
        command = jsonDecode(request.body);
        return reply({'ok': true});
      }),
    );
    expect(result, 'available');
    expect(command, isNotNull);
    expect(command!['action'], 'start');
    expect(command!['vehicle_id'], 'vehicle');
    expect(command!['expected_version'], 7);
    expect(calls, [
      '/public/driver/status', '/public/driver/vehicle-duty-state',
      '/public/driver/vehicle-duty', '/public/driver/status',
    ]);
  });
  test('actor switch during available-duty read cannot start the previous vehicle', () async {
    var current = true;
    final calls = <String>[];
    await expectLater(DriverSignInActivation(actor).activate(
      baseUrl: 'https://fixture.invalid', isCurrent: () => current,
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/status')) return reply(status('available'));
        expect(request.url.path, '/public/driver/vehicle-duty-state');
        current = false;
        return reply({'ok': true, 'version': 7, 'duties': []});
      }),
    ), throwsStateError);
    expect(calls, ['/public/driver/status', '/public/driver/vehicle-duty-state']);
  });
  test('available-duty failure retries the same versioned command identity', () async {
    final commands = <Map>[];
    final activation = DriverSignInActivation(actor);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/status')) return reply(status('available'));
      if (request.url.path.endsWith('/vehicle-duty-state')) return reply({'ok': true, 'version': 7, 'duties': []});
      expect(request.url.path, '/public/driver/vehicle-duty');
      commands.add(jsonDecode(request.body) as Map);
      return commands.length == 1
          ? reply({'ok': false, 'error': 'duty_projection_pending'}, 503)
          : reply({'ok': true});
    });
    await expectLater(activation.activate(baseUrl: 'https://fixture.invalid', isCurrent: () => true, client: client), throwsA(isA<Exception>()));
    expect(commands, hasLength(1));
    expect(await activation.activate(baseUrl: 'https://fixture.invalid', isCurrent: () => true, client: client), 'available');
    expect(commands, hasLength(2));
    expect(commands[1], commands[0]);
  });
  for (final initial in ['offline', 'paused']) {
    test(
      'explicit sign-in from $initial verifies, activates once, and confirms server state',
      () async {
        var state = initial;
        final calls = <String>[];
        final client = MockClient((request) async {
          expect(
            request.headers['Authorization'],
            'Bearer real-server-fixture',
          );
          expect(request.url.hasQuery, isFalse);
          calls.add('${request.method} ${request.url.path}');
          if (request.method == 'GET') return reply(status(state));
          expect(jsonDecode(request.body), {
            'availability_status': 'available',
          });
          state = 'available';
          return reply(scope());
        });
        final intent = DriverSignInActivation(actor);
        final results = await Future.wait(
          List.generate(
            2,
            (_) => intent.activate(
              baseUrl: 'https://fixture.invalid',
              isCurrent: () => true,
              client: client,
            ),
          ),
        );
        expect(results, ['available', 'available']);
        expect(
          await intent.activate(
            baseUrl: 'https://fixture.invalid',
            isCurrent: () => true,
            client: client,
          ),
          'available',
        );
        expect(calls, [
          'GET /public/driver/status',
          'POST /public/driver/availability',
          'GET /public/driver/status',
        ]);
      },
    );
  }
  for (final current in ['busy', 'on_trip']) {
    test(
      '$current stays unchanged and sends no availability mutation',
      () async {
        var calls = 0;
        final result = await DriverSignInActivation(actor).activate(
          baseUrl: 'https://fixture.invalid',
          isCurrent: () => true,
          client: MockClient((request) async {
            calls++;
            expect(request.method, 'GET');
            return reply(status(current));
          }),
        );
        expect(result, current);
        expect(calls, 1);
      },
    );
  }
  for (final error in ['vehicle_duty_not_configured', 'vehicle_operations_disabled']) {
    test('available retains legacy authority only for explicit $error', () async {
      final calls = <String>[];
      final result = await DriverSignInActivation(actor).activate(
        baseUrl: 'https://fixture.invalid', isCurrent: () => true,
        client: MockClient((request) async {
          calls.add(request.url.path);
          if (request.url.path.endsWith('/status')) return reply(status('available'));
          expect(request.url.path, '/public/driver/vehicle-duty-state');
          return reply({'ok': false, 'error': error}, error.endsWith('disabled') ? 503 : 409);
        }),
      );
      expect(result, 'available');
      expect(calls, ['/public/driver/status', '/public/driver/vehicle-duty-state']);
    });
  }
  for (final error in ['vehicle_device_auth_required', 'duty_projection_pending', 'forbidden']) {
    test('available does not hide $error or issue a duty command', () async {
      final calls = <String>[];
      await expectLater(DriverSignInActivation(actor).activate(
        baseUrl: 'https://fixture.invalid', isCurrent: () => true,
        client: MockClient((request) async {
          calls.add(request.url.path);
          if (request.url.path.endsWith('/status')) return reply(status('available'));
          expect(request.url.path, '/public/driver/vehicle-duty-state');
          return reply({'ok': false, 'error': error}, error.endsWith('pending') ? 503 : 403);
        }),
      ), throwsA(isA<Exception>()));
      expect(calls, ['/public/driver/status', '/public/driver/vehicle-duty-state']);
    });
  }
  for (final paused in [false, true]) {
    test('available preserves ${paused ? 'paused duty identity on resume' : 'an already active duty without command'}', () async {
      Map? command;
      final result = await DriverSignInActivation(actor).activate(
        baseUrl: 'https://fixture.invalid', isCurrent: () => true,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/status')) return reply(status('available'));
          if (request.url.path.endsWith('/vehicle-duty-state')) return reply({
            'ok': true, 'version': 8, 'duties': [{
              'driver_id': 'driver', 'vehicle_id': 'vehicle', 'duty_id': 'existing-duty',
              'paused_at_ms': paused ? 123 : null,
            }],
          });
          expect(request.url.path, '/public/driver/vehicle-duty');
          command = jsonDecode(request.body);
          return reply({'ok': true});
        }),
      );
      expect(result, 'available');
      if (paused) {
        expect(command!['action'], 'resume');
        expect(command!['duty_id'], 'existing-duty');
        expect(command!['expected_version'], 8);
      } else {
        expect(command, isNull);
      }
    });
  }
  for (final invalid in [
    'tenant_id',
    'company_id',
    'driver_id',
    'nested_driver',
    'vehicle',
    'inactive',
    'unknown',
    '401',
  ]) {
    test('rejects $invalid before a write', () async {
      final data = status('offline');
      if (['tenant_id', 'company_id', 'driver_id'].contains(invalid))
        data[invalid] = 'foreign';
      if (invalid == 'nested_driver') data['driver']['driver_id'] = 'foreign';
      if (invalid == 'vehicle')
        data['driver']['assigned_vehicle_id'] = 'foreign';
      if (invalid == 'inactive') data['driver']['is_active'] = false;
      if (invalid == 'unknown')
        data['driver']['availability_status'] = 'unknown';
      await expectLater(
        DriverSignInActivation(actor).activate(
          baseUrl: 'https://fixture.invalid',
          isCurrent: () => true,
          client: MockClient((request) async {
            expect(request.method, 'GET');
            return reply(data, invalid == '401' ? 401 : 200);
          }),
        ),
        throwsStateError,
      );
    });
  }
  for (final error in [
    'forbidden',
    'duty_version_conflict',
    'active_ride_blocks_duty_change',
  ]) {
    test('does not bypass server $error rejection', () async {
      final calls = <String>[];
      await expectLater(
        DriverSignInActivation(actor).activate(
          baseUrl: 'https://fixture.invalid',
          isCurrent: () => true,
          client: MockClient((request) async {
            calls.add(request.url.path);
            return request.method == 'GET'
                ? reply(status('offline'))
                : reply({'ok': false, 'error': error}, 409);
          }),
        ),
        throwsStateError,
      );
      expect(calls, ['/public/driver/status', '/public/driver/availability']);
    });
  }
  for (final paused in [false, true]) {
    test(
      'manual duty uses existing exact-driver ${paused ? 'resume' : 'start'} command',
      () async {
        var state = 'offline';
        Map? command;
        final result = await DriverSignInActivation(actor).activate(
          baseUrl: 'https://fixture.invalid',
          isCurrent: () => true,
          client: MockClient((request) async {
            if (request.url.path.endsWith('/status'))
              return reply(status(state));
            if (request.url.path.endsWith('/availability'))
              return reply({
                'ok': false,
                'error': 'availability_managed_by_duty',
              }, 409);
            if (request.url.path.endsWith('/vehicle-duty-state'))
              return reply({
                'ok': true,
                'version': 7,
                'duties': paused
                    ? [
                        {
                          'driver_id': 'driver',
                          'vehicle_id': 'vehicle',
                          'duty_id': 'own-duty',
                          'paused_at_ms': 123,
                        },
                      ]
                    : [],
              });
            expect(request.url.path, '/public/driver/vehicle-duty');
            command = jsonDecode(request.body);
            expect(command!['vehicle_id'], 'vehicle');
            expect(command!['expected_version'], 7);
            expect(command!['action'], paused ? 'resume' : 'start');
            if (paused) expect(command!['duty_id'], 'own-duty');
            state = 'available';
            return reply({'ok': true});
          }),
        );
        expect(result, 'available');
        expect(command, isNotNull);
      },
    );
  }
  test('late actor switch stops before any availability write', () async {
    final pending = Completer<http.Response>();
    var current = true;
    var calls = 0;
    final result = DriverSignInActivation(actor).activate(
      baseUrl: 'https://fixture.invalid',
      isCurrent: () => current,
      client: MockClient((request) async {
        calls++;
        return pending.future;
      }),
    );
    current = false;
    pending.complete(reply(status('offline')));
    await expectLater(result, throwsStateError);
    expect(calls, 1);
  });
  test('successful POST with wrong actor never reports available', () async {
    await expectLater(
      DriverSignInActivation(actor).activate(
        baseUrl: 'https://fixture.invalid',
        isCurrent: () => true,
        client: MockClient(
          (request) async => request.method == 'GET'
              ? reply(status('offline'))
              : reply({...scope(), 'driver_id': 'foreign'}),
        ),
      ),
      throwsStateError,
    );
  });
  test('POST accepted but unchanged status never reports available', () async {
    await expectLater(
      DriverSignInActivation(actor).activate(
        baseUrl: 'https://fixture.invalid',
        isCurrent: () => true,
        client: MockClient(
          (request) async =>
              reply(request.method == 'GET' ? status('offline') : scope()),
        ),
      ),
      throwsStateError,
    );
  });
}
