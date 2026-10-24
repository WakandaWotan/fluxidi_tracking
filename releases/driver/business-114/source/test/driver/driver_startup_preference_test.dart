import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_startup_preference.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues(<String, String>{});
    root = Directory.systemTemp.createTempSync('driver-startup-role-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => root.path,
        );
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = null;
    activeDriverSessionNotifier.value = null;
  });

  tearDown(() async {
    await DriverStartupPreference.instance.clear();
    await DriverSessionStore.instance.clear();
    companyProfileNotifier.value = null;
    activeCompanySessionNotifier.value = null;
    activeDriverSessionNotifier.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'last standalone driver wins over a different admin company only by exact pointer',
    () async {
      await DriverSessionStore.instance.saveBackendDriverLoginSession(
        tenantId: 'tenant-a',
        companyId: 'company-a',
        driverId: 'driver-a',
        driverName: 'A',
        companyDisplayName: 'A',
        driverSessionToken: 'bearer-a',
        expiresInSeconds: 3600,
      );
      await DriverSessionStore.instance.saveBackendDriverLoginSession(
        tenantId: 'tenant-b',
        companyId: 'company-b',
        driverId: 'driver-b',
        driverName: 'B',
        companyDisplayName: 'B',
        driverSessionToken: 'bearer-b',
        expiresInSeconds: 3600,
      );
      await DriverStartupPreference.instance.markDriver(
        activeDriverSessionNotifier.value,
      );
      final preference = await DriverStartupPreference.instance.load();
      expect(preference?.companyId, 'company-b');
      expect(preference?.driverId, 'driver-b');
      final hint = File('${root.path}/preferred_standalone_driver_v1.json');
      expect(await hint.readAsString(), isNot(contains('bearer-b')));

      await CompanySessionStore.instance.saveVerifiedCompanyPairingSession(
        tenantId: 'tenant-a',
        companyId: 'company-a',
        companyName: 'A',
        countryCode: 'BE',
        companySessionToken: 'admin-a',
      );
      activeDriverSessionNotifier.value = null;
      await DriverSessionStore.instance.bootstrap(
        const <DriverProfile>[],
        useStandaloneScopePointer: true,
        preferStandaloneScopePointer: true,
      );
      expect(activeDriverSessionNotifier.value?.companyId, 'company-b');
      expect(activeDriverSessionNotifier.value?.driverId, 'driver-b');
      expect(preference?.matches(activeDriverSessionNotifier.value), isTrue);

      await DriverStartupPreference.instance.clear();
      expect(await DriverStartupPreference.instance.load(), isNull);
    },
  );

  test('preferred identity cannot authorize another company or driver', () {
    const preferred = PreferredStandaloneDriver(
      tenantId: 'tenant-a',
      companyId: 'company-a',
      driverId: 'driver-a',
    );
    expect(
      preferred.matches(
        ActiveDriverSession(
          driverId: 'driver-b',
          employeeNumber: 'B',
          fullName: 'B',
          phone: '',
          loggedInAt: DateTime.now().toUtc().toIso8601String(),
          updatedAt: DateTime.now().toUtc().toIso8601String(),
          tenantId: 'tenant-a',
          companyId: 'company-a',
          driverSessionToken: 'bearer',
          linkMethod: 'public_driver_login',
        ),
      ),
      isFalse,
    );
    expect(
      PreferredStandaloneDriver.fromJson(<String, dynamic>{
        'tenant_id': 'tenant-a',
        'company_id': '',
        'driver_id': 'driver-a',
      }),
      isNull,
    );
  });
}
