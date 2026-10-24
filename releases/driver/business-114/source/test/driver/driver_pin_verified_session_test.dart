import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/driver/driver_pin_verified_session.dart';
import 'package:fluxidi_tracking/driver/vehicle_driver_pin_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

ActiveDriverSession actor({
  String driver = 'Christophe',
  String tenant = 'own',
  String token = 'issued-by-server',
  String method = 'driver_pairing_code',
  DateTime? expiry,
}) => ActiveDriverSession(
  driverId: driver,
  employeeNumber: 'one-time-qr-must-not-persist',
  fullName: driver,
  phone: '',
  loggedInAt: '',
  updatedAt: '',
  tenantId: tenant,
  companyId: 'company',
  companyCode: 'FLX-90001',
  assignedVehicleId: 'server-current-vehicle',
  driverSessionToken: token,
  linkMethod: method,
  driverSessionExpiresAtUtc:
      (expiry ?? DateTime.now().add(const Duration(hours: 1)))
          .toUtc()
          .toIso8601String(),
);
Map<String, dynamic> status({String driver = 'Christophe'}) => {
  'ok': true,
  'tenant_id': 'own',
  'company_id': 'company',
  'driver_id': driver,
  'driver': {
    'driver_id': driver,
    'is_active': true,
    'assigned_vehicle_id': 'server-current-vehicle',
  },
};
const scope = {'tenant_id': 'own', 'company_id': 'company'};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('setup is exact actor/token and expires at five minutes', () {
    var age = Duration.zero;
    final original = actor();
    final proof = FreshDriverPinSetup.withAge(original, () => age);
    expect(proof.matches(original), isTrue);
    expect(proof.matches(actor(driver: 'TestDriver')), isFalse);
    expect(proof.matches(actor(tenant: 'foreign')), isFalse);
    expect(proof.matches(actor(token: 'other-issued-token')), isFalse);
    age = const Duration(minutes: 5);
    expect(proof.matches(original), isFalse);
  });
  for (final method in [
    'company_admin_driver_view',
    kOperatorMintDriverLinkMethod,
  ]) {
    test('non-driver authority cannot create setup: $method', () {
      expect(
        () => FreshDriverPinSetup(actor(method: method)),
        throwsStateError,
      );
    });
  }
  test('expired bearer fails before network', () {
    expect(
      () => DriverPinServerSession.fromVerifiedSession(
        actor(expiry: DateTime.now().subtract(const Duration(seconds: 1))),
      ),
      throwsStateError,
    );
  });
  for (final invalid in [
    '401',
    '403',
    'tenant_id',
    'company_id',
    'driver_id',
    'nested_driver',
    'inactive',
    'vehicle_changed',
    'network',
  ]) {
    test('server session rejects $invalid', () async {
      await http.runWithClient(
        () async {
          await expectLater(
            DriverPinServerSession.fromVerifiedSession(actor()).verify(),
            throwsA(anything),
          );
        },
        () => MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/public/driver/status');
          expect(request.url.hasQuery, isFalse);
          expect(request.headers['Authorization'], 'Bearer issued-by-server');
          if (invalid == 'network') throw http.ClientException('unavailable');
          final data = status();
          if (['tenant_id', 'company_id', 'driver_id'].contains(invalid))
            data[invalid] = 'foreign';
          if (invalid == 'nested_driver')
            data['driver']['driver_id'] = 'TestDriver';
          if (invalid == 'inactive') data['driver']['is_active'] = false;
          if (invalid == 'vehicle_changed')
            data['driver']['assigned_vehicle_id'] = 'other-vehicle';
          return http.Response(jsonEncode(data), int.tryParse(invalid) ?? 200);
        }),
      );
    });
  }
  test(
    'encrypted credential restores bearer but never QR; server is still mandatory',
    () async {
      final store = DriverPersonalPinStore();
      await store.enrollServerSession(
        DriverPinServerSession.fromVerifiedSession(actor()),
        '837291',
        stillAuthorized: () async => true,
      );
      await store.rememberDriver(scope, 'Christophe', 'Christophe');
      final values = await const FlutterSecureStorage().readAll();
      expect(
        values.values.any(
          (v) =>
              v.contains('837291') ||
              v.contains('one-time-qr-must-not-persist'),
        ),
        isFalse,
      );
      final restored = await DriverPersonalPinStore().unlockForLogin(
        scope,
        'Christophe',
        '837291',
      );
      expect(restored?.driverCode, isEmpty);
      expect(
        restored?.serverSession?.session.driverSessionToken,
        'issued-by-server',
      );
      expect(
        await store.credentialsForReverification(scope, 'Christophe'),
        isNull,
      );
      expect(await store.unlockForLogin(scope, 'TestDriver', '837291'), isNull);
      await http.runWithClient(
        () async {
          final verified = await restored!.serverSession!.verify();
          expect(verified.assignedVehicleId, 'server-current-vehicle');
        },
        () => MockClient((_) async => http.Response(jsonEncode(status()), 200)),
      );
      await http.runWithClient(() async {
        await expectLater(restored!.serverSession!.verify(), throwsStateError);
      }, () => MockClient((_) async => http.Response('{}', 401)));
    },
  );
  test(
    'QR credential retains five-attempt lockout and recovery requires fresh authority',
    () async {
      final store = DriverPersonalPinStore();
      await store.enrollServerSession(
        DriverPinServerSession.fromVerifiedSession(actor()),
        '837291',
        stillAuthorized: () async => true,
      );
      for (var i = 0; i < 4; i++) {
        expect(
          await store.unlockForLogin(scope, 'Christophe', '000000'),
          isNull,
        );
      }
      await expectLater(
        store.unlockForLogin(scope, 'Christophe', '000000'),
        throwsStateError,
      );
      await expectLater(
        store.unlockForLogin(scope, 'Christophe', '837291'),
        throwsStateError,
      );
      await expectLater(
        store.enrollServerSession(
          DriverPinServerSession.fromVerifiedSession(actor()),
          '482716',
          stillAuthorized: () async => false,
        ),
        throwsStateError,
      );
      await expectLater(
        store.unlockForLogin(scope, 'Christophe', '482716'),
        throwsStateError,
      );
      await store.enrollServerSession(
        DriverPinServerSession.fromVerifiedSession(actor()),
        '482716',
        stillAuthorized: () async => true,
      );
      expect(await store.unlockForLogin(scope, 'Christophe', '837291'), isNull);
      expect(
        await store.unlockForLogin(scope, 'Christophe', '482716'),
        isNotNull,
      );
    },
  );
}
