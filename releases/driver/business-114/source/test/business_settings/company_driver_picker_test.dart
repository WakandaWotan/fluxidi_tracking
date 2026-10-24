import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/company/company_driver_picker.dart';
import 'package:fluxidi_tracking/driver/vehicle_device_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final company in ['fluxidi', 'mario', 'diva', 'empty']) {
    test(
      '$company: only authenticated active own members, no roster gate',
      () async {
        final client = MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/admin/company/drivers/index');
          expect(request.url.queryParameters, {
            'tenant_id': company,
            'company_id': company,
          });
          expect(request.headers['Authorization'], 'Bearer fixture-$company');
          return http.Response(
            jsonEncode({
              'ok': true,
              'tenant_id': company,
              'company_id': company,
              'drivers': [
                if (company != 'empty')
                  {
                    'driver_id': '$company-own',
                    'display_name': 'Own unassigned',
                    'is_active': true,
                    'tenant_id': company,
                    'company_id': company,
                  },
                {
                  'driver_id': 'foreign',
                  'display_name': 'Foreign',
                  'tenant_id': 'other',
                  'company_id': 'other',
                },
                {
                  'driver_id': 'aliases',
                  'display_name': 'Forged alias',
                  'tenant_id': company,
                  'company_id': company,
                  'companyId': 'other',
                },
                {
                  'driver_id': 'inactive',
                  'display_name': 'Inactive',
                  'is_active': false,
                  'tenant_id': company,
                  'company_id': company,
                },
              ],
            }),
            200,
          );
        });
        final rows =
            (await fetchCompanyDriverPicker(
                  bookingBaseUrl: 'https://fixture.invalid/',
                  tenantId: company,
                  companyId: company,
                  sessionToken: 'fixture-$company',
                  client: client,
                ))['drivers']
                as List;
        expect(
          rows.map((r) => r['driver_id']),
          company == 'empty' ? isEmpty : ['$company-own'],
        );
        client.close();
      },
    );
  }
  test(
    'forged scope, missing scope and HTTP errors never return a list',
    () async {
      for (final payload in [
        {
          'ok': true,
          'tenant_id': 'other',
          'company_id': 'fluxidi',
          'drivers': [],
        },
        {
          'ok': true,
          'tenant_id': 'fluxidi',
          'company_id': 'other',
          'drivers': [],
        },
        {'ok': true, 'drivers': []},
        {'ok': false, 'error': 'company_auth_required'},
      ]) {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode(payload),
            payload['ok'] == true ? 200 : 403,
          ),
        );
        await expectLater(
          fetchCompanyDriverPicker(
            bookingBaseUrl: 'https://fixture.invalid',
            tenantId: 'fluxidi',
            companyId: 'fluxidi',
            sessionToken: 'fixture',
            client: client,
          ),
          throwsStateError,
        );
        client.close();
      }
    },
  );
  test(
    'missing company session makes no request and uses no device fallback',
    () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      await expectLater(
        fetchCompanyDriverPicker(
          bookingBaseUrl: 'https://fixture.invalid',
          tenantId: 'fluxidi',
          companyId: 'fluxidi',
          sessionToken: '',
          client: client,
        ),
        throwsStateError,
      );
      expect(requests, 0);
      client.close();
    },
  );
  test(
    'foreign QR is rejected before redeeming or replacing device binding',
    () async {
      const storage = FlutterSecureStorage();
      const old =
          '{"tenant_id":"fluxidi","company_id":"fluxidi","vehicle_id":"tesla"}';
      FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': old,
      });
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      await expectLater(
        VehicleDeviceStore().pair(
          jsonEncode({
            'kind': 'fluxidi_vehicle_device',
            'version': 1,
            'tenant_id': 'mario',
            'company_id': 'mario',
            'challenge_id': 'fixture',
            'pairing_token': 'fixture',
          }),
          'https://fixture.invalid',
          client: client,
          expectedTenantId: 'fluxidi',
          expectedCompanyId: 'fluxidi',
        ),
        throwsStateError,
      );
      expect(requests, 0);
      expect(await storage.read(key: 'vehicle_device_binding_v1'), old);
      client.close();
    },
  );
  test(
    'same company wrong vehicle response cannot replace target binding',
    () async {
      const storage = FlutterSecureStorage();
      const old =
          '{"tenant_id":"fluxidi","company_id":"fluxidi","vehicle_id":"tesla"}';
      FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': old,
      });
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'ok': true,
            'tenant_id': 'fluxidi',
            'company_id': 'fluxidi',
            'vehicle_id': 'wrong',
            'device_id': 'fixture',
            'device_token': 'fixture',
            'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 60000,
          }),
          200,
        ),
      );
      await expectLater(
        VehicleDeviceStore().pair(
          jsonEncode({
            'kind': 'fluxidi_vehicle_device',
            'version': 1,
            'tenant_id': 'fluxidi',
            'company_id': 'fluxidi',
            'challenge_id': 'fixture',
            'pairing_token': 'fixture',
          }),
          'https://fixture.invalid',
          client: client,
          expectedTenantId: 'fluxidi',
          expectedCompanyId: 'fluxidi',
          expectedVehicleId: 'tesla',
        ),
        throwsStateError,
      );
      expect(await storage.read(key: 'vehicle_device_binding_v1'), old);
      client.close();
    },
  );
}
