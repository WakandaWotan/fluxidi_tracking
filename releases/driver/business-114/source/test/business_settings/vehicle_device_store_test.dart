import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/vehicle_device_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'name chooser is limited to stored vehicle scope and returns no device token',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': jsonEncode({
          'tenant_id': 't',
          'company_id': 'c',
          'vehicle_id': 'v',
          'device_id': 'dev',
          'device_token': 'fixture-device',
          'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 100000,
        }),
      });
      final client = MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['company_id'], 'c');
        expect(body['device_id'], 'dev');
        return http.Response(
          jsonEncode({
            'ok': true,
            'tenant_id': 't',
            'company_id': 'c',
            'vehicle_id': 'v',
            'drivers': [
              {'driver_id': 'd', 'name': 'Bart'},
            ],
          }),
          200,
        );
      });
      final choices = await VehicleDeviceStore().driverChoices(
        'https://fixture.invalid',
        client: client,
      );
      expect(choices?['drivers'], [
        {'driver_id': 'd', 'name': 'Bart'},
      ]);
      expect(choices?.containsKey('device_token'), false);
      client.close();
      final foreign = MockClient(
        (_) async => http.Response(
          '{"ok":true,"tenant_id":"t","company_id":"other","vehicle_id":"v","drivers":[]}',
          200,
        ),
      );
      await expectLater(
        VehicleDeviceStore().driverChoices(
          'https://fixture.invalid',
          client: foreign,
        ),
        throwsStateError,
      );
      foreign.close();
    },
  );
  test(
    'QR destination cannot override configured backend and binding persists securely',
    () async {
      final store = VehicleDeviceStore();
      expect(await store.loginIdentity(), isNull);
      final qr = {
        'kind': 'fluxidi_vehicle_device',
        'version': 1,
        'tenant_id': 't',
        'company_id': 'c',
        'challenge_id': 'one',
        'pairing_token': 'fixture-pairing',
        'url': 'https://untrusted.invalid',
      };
      final client = MockClient((request) async {
        expect(request.url.host, 'fixture.invalid');
        expect(jsonDecode(request.body).containsKey('url'), false);
        return http.Response(
          jsonEncode({
            'ok': true,
            'tenant_id': 't',
            'company_id': 'c',
            'device_id': 'dev',
            'vehicle_id': 'v',
            'device_token': 'fixture-device-secret',
            'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 100000,
          }),
          200,
        );
      });
      await store.pair(
        jsonEncode(qr),
        'https://fixture.invalid',
        client: client,
      );
      final login = await store.loginIdentity();
      expect(login?['device_id'], 'dev');
      expect(login?.containsKey('driver_id'), false);
      client.close();
    },
  );
  test(
    'failed or foreign pairing cannot replace an existing binding',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': jsonEncode({
          'device_id': 'old',
          'device_token': 'fixture-old',
          'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 100000,
        }),
      });
      final store = VehicleDeviceStore();
      final qr = {
        'kind': 'fluxidi_vehicle_device',
        'version': 1,
        'tenant_id': 't',
        'company_id': 'c',
        'challenge_id': 'one',
        'pairing_token': 'fixture-pairing',
      };
      final client = MockClient(
        (_) async => http.Response(
          '{"ok":true,"tenant_id":"other","company_id":"c"}',
          200,
        ),
      );
      await expectLater(
        store.pair(jsonEncode(qr), 'https://fixture.invalid', client: client),
        throwsStateError,
      );
      expect((await store.loginIdentity())?['device_id'], 'old');
      client.close();
    },
  );
}
