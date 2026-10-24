import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company/driver_management_native_repository.dart';
import 'driver_management_native_test_support.dart';

void main() {
  test(
    'Live nested DTO resolves only to authenticated own fleet by ID',
    () async {
      final f = NativeDriverFixture();
      expect(f.driver['vehicles'][0].containsKey('tenant_id'), isFalse);
      final repo = f.repository();
      await repo.connect();
      final detail = await repo.detail('driver-1');
      final vehicles = detail['vehicles'] as List;
      expect(vehicles, hasLength(2));
      expect(vehicles.map((v) => v['vehicle_id']).toSet(), hasLength(2));
      expect(vehicles.map((v) => v['license_plate']).toSet(), {'TEST'});
      expect(
        vehicles.every(
          (v) => v['tenant_id'] == f.tenant && v['company_id'] == f.company,
        ),
        isTrue,
      );
      await repo.connectPartners();
      expect(await repo.partners(), isEmpty);
    },
  );
  for (final mutation in [
    'unknown-id',
    'empty-id',
    'duplicate-id',
    'foreign-company',
    'foreign-tenant',
    'vehicle_name',
    'license_plate',
    'vehicle_type',
    'is_active',
  ]) {
    test('Nested vehicle $mutation cannot bypass own fleet binding', () async {
      final f = NativeDriverFixture();
      final repo = f.repository(
        get: (uri, headers) async {
          if (!uri.path.endsWith('/detail')) return f.get(uri, headers);
          final driver = f.driver;
          final linked = driver['vehicles'] as List;
          switch (mutation) {
            case 'unknown-id':
              linked[0]['vehicle_id'] = 'not-in-own-fleet';
            case 'empty-id':
              linked[0]['vehicle_id'] = '';
            case 'duplicate-id':
              linked[1] = linked[0];
            case 'foreign-company':
              linked[0]['company_id'] = 'foreign';
            case 'foreign-tenant':
              linked[0]['tenant_id'] = 'foreign';
            default:
              linked[0][mutation] = 'conflicting-value';
          }
          return (
            status: 200,
            body: jsonEncode({'ok': true, 'driver': driver}),
          );
        },
      );
      await repo.connect();
      await expectLater(
        repo.detail('driver-1'),
        throwsA(isA<DriverManagementReadFailure>()),
      );
    });
  }
  for (final mutation in [
    'missing-id',
    'duplicate-id',
    'foreign-company',
    'foreign-tenant',
  ]) {
    test('Readiness fleet $mutation is rejected before roster use', () async {
      final f = NativeDriverFixture();
      final ready = f.ready;
      final vehicles = ready['vehicles'] as List;
      switch (mutation) {
        case 'missing-id':
          vehicles[0].remove('vehicle_id');
        case 'duplicate-id':
          vehicles[1]['vehicle_id'] = vehicles[0]['vehicle_id'];
        case 'foreign-company':
          vehicles[0]['company_id'] = 'foreign';
        case 'foreign-tenant':
          vehicles[0]['tenant_id'] = 'foreign';
      }
      final repo = f.repository(
        get: (uri, headers) async => (status: 200, body: jsonEncode(ready)),
      );
      await expectLater(
        repo.connect(),
        throwsA(isA<DriverManagementReadFailure>()),
      );
    });
  }
  for (final scope in [
    ('tenant-a', 'mario'),
    ('tenant-a', 'diva'),
    ('tenant-b', 'mario'),
    ('tenant-future', 'new-company'),
  ]) {
    test(
      'Native own list/detail/export without company allowlist $scope',
      () async {
        final f = NativeDriverFixture(tenant: scope.$1, company: scope.$2);
        final repo = f.repository();
        await repo.connect();
        final page = await repo.list({
          'q': 'Tesla',
          'sort': 'name',
          'direction': 'desc',
          'limit': '25',
        });
        expect(page['items'].single['company_id'], scope.$2);
        expect((await repo.detail('driver-1'))['vehicles'], hasLength(2));
        expect(
          await repo.exportCsv({'q': 'Tesla', 'cursor': 'next-page'}),
          contains(scope.$2),
        );
        expect(f.requests.last.queryParameters, {'q': 'Tesla'});
        expect(
          f.requests.every(
            (r) =>
                r.scheme == 'https' &&
                !r.queryParameters.containsKey('company_id') &&
                !r.queryParameters.containsKey('tenant_id'),
          ),
          isTrue,
        );
      },
    );
  }
  test(
    'A newly registered company automatically has a real empty environment',
    () async {
      final f = NativeDriverFixture()..empty = true;
      final repo = f.repository();
      await repo.connect();
      final page = await repo.list({});
      expect(page['items'], isEmpty);
      expect(page['total'], 0);
      expect(repo.vehicleTypes, isEmpty);
    },
  );
  for (final target in ['driver', 'vehicle', 'detail']) {
    test('Foreign $target is rejected before native rendering', () async {
      final f = NativeDriverFixture();
      final repo = f.repository(
        get: (uri, headers) async {
          if (uri.path.endsWith('/readiness')) return f.get(uri, headers);
          final driver = f.driver;
          if (target == 'vehicle') {
            driver['vehicles'][0]['tenant_id'] = 'FOREIGN';
          } else {
            driver['company_id'] = 'FOREIGN';
          }
          return (
            status: 200,
            body: jsonEncode(
              target == 'detail'
                  ? {'ok': true, 'driver': driver}
                  : {
                      'ok': true,
                      'items': [driver],
                      'total': 1,
                      'offset': 0,
                      'next_cursor': null,
                    },
            ),
          );
        },
      );
      await repo.connect();
      expect(
        target == 'detail' ? repo.detail('driver-1') : repo.list({}),
        throwsA(isA<DriverManagementReadFailure>()),
      );
    });
  }
  test('A late HTTP response cannot cross a session change', () async {
    final f = NativeDriverFixture();
    final pending = Completer<DriverManagementResponse>();
    final repo = f.repository(
      get: (uri, headers) => uri.path.endsWith('/readiness')
          ? f.get(uri, headers)
          : pending.future,
    );
    await repo.connect();
    final response = repo.list({});
    final assertion = expectLater(
      response,
      throwsA(isA<DriverManagementReadFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    f.current = false;
    pending.complete((
      status: 200,
      body: jsonEncode({
        'ok': true,
        'items': [f.driver],
        'total': 1,
        'offset': 0,
        'next_cursor': null,
      }),
    ));
    await assertion;
  });
  for (final status in [401, 403, 404, 409, 500, 302]) {
    test('HTTP $status fails closed without leaking server response', () async {
      final f = NativeDriverFixture();
      final repo = f.repository();
      await repo.connect();
      f.denied = status;
      try {
        await repo.list({});
        fail('must reject');
      } on DriverManagementReadFailure catch (error) {
        expect(error.message, isNot(contains('PRIVATE')));
      }
    });
  }
  test(
    'Forged scope and financial filter keys never cause a request',
    () async {
      final f = NativeDriverFixture();
      final repo = f.repository();
      await repo.connect();
      final count = f.requests.length;
      for (final key in [
        'tenant_id',
        'company_id',
        'settlement_write',
        'partner_write',
        'authorization',
      ]) {
        await expectLater(
          repo.list({key: 'foreign'}),
          throwsA(isA<DriverManagementReadFailure>()),
        );
      }
      expect(f.requests.length, count);
    },
  );
  test('Scope, read contract and readonly rights must be proven', () async {
    for (final mutation in ['company', 'tenant', 'write', 'contract']) {
      final f = NativeDriverFixture();
      final ready = f.ready;
      switch (mutation) {
        case 'company':
          ready['operator']['company_id'] = 'foreign';
        case 'tenant':
          ready['operator']['tenant_id'] = '';
        case 'write':
          ready['capabilities']['import_write'] = true;
        case 'contract':
          ready['contract'] = 'unknown';
      }
      final repo = f.repository(
        get: (u, h) async => (status: 200, body: jsonEncode(ready)),
      );
      await expectLater(
        repo.connect(),
        throwsA(isA<DriverManagementReadFailure>()),
      );
    }
  });
  test('Revoked local session sends no request', () async {
    final f = NativeDriverFixture()..current = false;
    await expectLater(
      f.repository().connect(),
      throwsA(isA<DriverManagementReadFailure>()),
    );
    expect(f.requests, isEmpty);
  });
}
