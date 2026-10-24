import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/driver/vehicle_driver_pin_store.dart';
import 'package:fluxidi_tracking/driver/vehicle_device_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final scope = <String, dynamic>{
    'tenant_id': 't',
    'company_id': 'c',
    'vehicle_id': 'v',
    'device_id': 'dev',
  };
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'verified QR identities without PIN survive restart but grant no credential',
    () async {
      final store = DriverPersonalPinStore();
      final personal = <String, dynamic>{'tenant_id': 't', 'company_id': 'c'};
      await store.rememberVerifiedDriver(
        personal,
        'christophe',
        'Christophe',
        'FLX-90001',
      );
      await store.rememberVerifiedDriver(
        personal,
        'testdriver',
        'TestDriver',
        'FLX-90001',
      );
      final restored = DriverPersonalPinStore();
      expect((await restored.preferredChoices())?['drivers'], hasLength(2));
      expect(await restored.hasPin(personal, 'christophe'), isFalse);
      expect(await restored.unlock(personal, 'christophe', '482716'), isNull);
      expect(
        await restored.credentialsForReverification(personal, 'christophe'),
        isNull,
      );
      expect(
        await restored.rememberedChoices({
          ...personal,
          'company_id': 'foreign',
        }),
        isNull,
      );
    },
  );

  test(
    'authorization change during PIN derivation preserves previous PIN',
    () async {
      final store = DriverPersonalPinStore();
      await store.enroll(
        scope,
        'bart',
        'fixture-company',
        'fixture-code',
        '482716',
      );
      await expectLater(
        store.enroll(
          scope,
          'bart',
          'fixture-company',
          'changed-code',
          '837291',
          stillAuthorized: () async => false,
        ),
        throwsStateError,
      );
      expect(
        (await store.unlock(scope, 'bart', '482716'))?.driverCode,
        'fixture-code',
      );
    },
  );

  test(
    'personal phone PIN survives restart without vehicle pairing and stays tenant/driver scoped',
    () async {
      final personalScope = <String, dynamic>{
        'tenant_id': 't',
        'company_id': 'c',
      };
      final store = DriverPersonalPinStore();
      await store.enroll(
        personalScope,
        'bart',
        'fixture-company',
        'fixture-code',
        '482716',
      );
      await store.rememberDriver(personalScope, 'bart', 'Bart');
      final restored = DriverPersonalPinStore();
      expect(await restored.hasPin(personalScope, 'bart'), true);
      expect(
        (await restored.unlock(personalScope, 'bart', '482716'))?.driverCode,
        'fixture-code',
      );
      expect(await restored.unlock(personalScope, 'tom', '482716'), isNull);
      expect(
        await restored.unlock(
          {...personalScope, 'company_id': 'foreign'},
          'bart',
          '482716',
        ),
        isNull,
      );
      expect(
        await restored.unlock(
          {...personalScope, 'tenant_id': 'foreign'},
          'bart',
          '482716',
        ),
        isNull,
      );
      expect(await VehicleDriverPinStore().hasPin(scope, 'bart'), false);
      expect((await restored.rememberedChoices(personalScope))?['drivers'], [
        {'driver_id': 'bart', 'name': 'Bart'},
      ]);
      expect(
        await restored.rememberedChoices({
          ...personalScope,
          'company_id': 'foreign',
        }),
        isNull,
      );
      expect((await restored.preferredChoices())?['company_id'], 'c');
      expect(
        (await const FlutterSecureStorage().readAll()).values.every(
          (value) => !value.contains('482716'),
        ),
        true,
      );
    },
  );

  test('personal phone PIN retains lockout and fixed-code reset', () async {
    final personalScope = <String, dynamic>{
      'tenant_id': 't',
      'company_id': 'c',
    };
    final store = DriverPersonalPinStore();
    await store.enroll(
      personalScope,
      'bart',
      'fixture-company',
      'fixture-code',
      '482716',
    );
    for (var i = 0; i < 4; i++) {
      expect(await store.unlock(personalScope, 'bart', '111111'), isNull);
    }
    await expectLater(
      store.unlock(personalScope, 'bart', '111111'),
      throwsStateError,
    );
    await expectLater(
      DriverPersonalPinStore().unlock(personalScope, 'bart', '482716'),
      throwsStateError,
    );
    await store.enroll(
      personalScope,
      'bart',
      'fixture-company',
      'new-code',
      '837291',
    );
    expect(
      (await store.unlock(personalScope, 'bart', '837291'))?.driverCode,
      'new-code',
    );
  });

  test(
    'personal PIN unlocks only its own driver on its own paired device',
    () async {
      final store = VehicleDriverPinStore();
      await store.enroll(
        scope,
        'bart',
        'fixture-company',
        'fixture-fixed-code',
        '482716',
      );
      expect(await store.unlock(scope, 'bart', '482716'), (
        companyCode: 'fixture-company',
        driverCode: 'fixture-fixed-code',
      ));
      expect(await store.unlock(scope, 'tom', '482716'), isNull);
      for (final key in scope.keys) {
        expect(
          await store.unlock({...scope, key: 'other'}, 'bart', '482716'),
          isNull,
        );
      }
      final values = await const FlutterSecureStorage().readAll();
      expect(values.values.single, isNot(contains('482716')));
      expect(await store.unlock(scope, 'bart', '000000'), isNull);
    },
  );

  test(
    'fifth wrong attempt locks across store recreation, then expires',
    () async {
      var now = DateTime.utc(2026, 10, 7);
      final store = VehicleDriverPinStore(now: () => now);
      await store.enroll(
        scope,
        'bart',
        'fixture-company',
        'fixture-code',
        '482716',
      );
      for (var i = 0; i < 4; i++) {
        expect(await store.unlock(scope, 'bart', '111111'), isNull);
      }
      await expectLater(
        store.unlock(scope, 'bart', '111111'),
        throwsStateError,
      );
      await expectLater(
        VehicleDriverPinStore(now: () => now).unlock(scope, 'bart', '482716'),
        throwsStateError,
      );
      now = now.add(const Duration(minutes: 15));
      expect(await store.unlock(scope, 'bart', '482716'), isNotNull);
    },
  );

  test(
    'fixed-code reenrollment resets forgotten PIN, removes old PIN',
    () async {
      final store = VehicleDriverPinStore();
      await store.enroll(
        scope,
        'bart',
        'fixture-company',
        'fixture-code',
        '482716',
      );
      await store.enroll(
        scope,
        'bart',
        'fixture-company',
        'new-fixture-code',
        '837291',
      );
      expect(await store.unlock(scope, 'bart', '482716'), isNull);
      expect(
        (await store.unlock(scope, 'bart', '837291'))?.driverCode,
        'new-fixture-code',
      );
      await store.forget(scope, 'bart');
      expect(await store.hasPin(scope, 'bart'), false);
    },
  );

  test('invalid scope and short PIN cannot enroll', () async {
    final store = VehicleDriverPinStore();
    await expectLater(
      store.enroll(scope, 'bart', 'c', 'd', '1234'),
      throwsArgumentError,
    );
    await expectLater(
      store.enroll({...scope, 'device_id': ''}, 'bart', 'c', 'd', '482716'),
      throwsStateError,
    );
  });

  test('expired vehicle binding cannot supply PIN scope', () async {
    FlutterSecureStorage.setMockInitialValues({
      'vehicle_device_binding_v1': jsonEncode({...scope, 'expires_at_ms': 1}),
    });
    await expectLater(VehicleDeviceStore().pinScope(), throwsStateError);
    FlutterSecureStorage.setMockInitialValues({});
    expect(await VehicleDeviceStore().pinScope(), isNull);
  });
}
