import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/driver/driver_duty_identity.dart';
import 'package:fluxidi_tracking/driver/driver_duty_bridge.dart';
import 'package:fluxidi_tracking/driver/driver_session_credentials.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() {
    root = Directory.systemTemp.createTempSync('fluxidi-duty-owner-test-');
    FlutterSecureStorage.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => root.path,
    );
    activeDriverSessionNotifier.value = null;
    nativeDriverDutySessionNotifier.value = null;
  });
  tearDown(() async {
    await DriverSessionStore.instance.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), null,
    );
    if (await root.exists()) await root.delete(recursive: true);
  });
  Future<ActiveDriverSession> login(String driver, {String vehicle = 'vehicle', String? token}) async {
    await DriverSessionStore.instance.saveBackendDriverLoginSession(
      tenantId: 'tenant', companyId: 'company', driverId: driver, driverName: 'Fixture',
      companyDisplayName: 'Fixture', assignedVehicleId: vehicle,
      driverSessionToken: token ?? 'fixture-bearer-$driver', expiresInSeconds: 3600,
    );
    return activeDriverSessionNotifier.value!;
  }
  test('durable identity pointer restores secure real session independent of preview', () async {
    final real = await login('a');
    expect(await DriverSessionStore.instance.claimNativeDutyOwnership(real), isTrue);
    final ownerFiles = root.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('native_driver_duty_owner_v1.json'));
    final pointer = await ownerFiles.single.readAsString();
    expect(pointer, contains('vehicle'));
    expect(pointer, isNot(contains('fixture-bearer')));
    DriverSessionStore.instance.prepareBusinessDriverCockpitEntry();
    nativeDriverDutySessionNotifier.value = null;
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value?.driverId, 'a');
    expect(nativeDriverDutySessionNotifier.value?.driverSessionToken, 'fixture-bearer-a');
    expect(activeDriverSessionNotifier.value, isNull);
  });
  test('real actor or vehicle replacement invalidates old native ownership', () async {
    var real = await login('a');
    await DriverSessionStore.instance.claimNativeDutyOwnership(real);
    await login('b');
    expect(nativeDriverDutySessionNotifier.value, isNull);
    real = activeDriverSessionNotifier.value!;
    await DriverSessionStore.instance.claimNativeDutyOwnership(real);
    await login('b', vehicle: 'different-vehicle');
    expect(nativeDriverDutySessionNotifier.value, isNull);
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value, isNull);
  });
  test('genuine same-driver bearer replacement invalidates its old native pairing', () async {
    final first = await login('a', token: 'fixture-bearer-A');
    expect(await DriverSessionStore.instance.claimNativeDutyOwnership(first), isTrue);
    final replacement = await login('a', token: 'fixture-bearer-B');
    expect(replacement.driverId, first.driverId);
    expect(replacement.assignedVehicleId, first.assignedVehicleId);
    expect(nativeDriverDutySessionNotifier.value, isNull);
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value, isNull);
    expect(activeDriverSessionNotifier.value?.driverSessionToken, 'fixture-bearer-B');
  });
  test('same-actor login B while A claim persistence waits cannot publish A owner', () async {
    final first = await login('a', token: 'fixture-bearer-A');
    final pendingPath = Completer<String>();
    final requestedPath = Completer<void>();
    var blockFirstPath = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async {
        if (blockFirstPath) {
          blockFirstPath = false;
          requestedPath.complete();
          return pendingPath.future;
        }
        return root.path;
      },
    );
    final claimA = DriverSessionStore.instance.claimNativeDutyOwnership(first,
      isCurrent: () => DriverDutyBridge.activationOwnerIsCurrent(first, businessPreview: false));
    await requestedPath.future;
    final replacement = await login('a', token: 'fixture-bearer-B');
    expect(nativeDriverDutySessionNotifier.value, isNull);
    pendingPath.complete(root.path);
    expect(await claimA, isFalse);
    expect(nativeDriverDutySessionNotifier.value, isNull);
    expect(activeDriverSessionNotifier.value?.driverSessionToken, 'fixture-bearer-B');
    expect(await DriverSessionStore.instance.claimNativeDutyOwnership(replacement,
      isCurrent: () => DriverDutyBridge.activationOwnerIsCurrent(replacement, businessPreview: false)), isTrue);
    nativeDriverDutySessionNotifier.value = null;
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value?.driverSessionToken, 'fixture-bearer-B');
  });
  test('logout clears pointer and cannot revive duty', () async {
    final real = await login('a');
    await DriverSessionStore.instance.claimNativeDutyOwnership(real);
    await DriverSessionStore.instance.clearNativeDutyOwnership();
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value, isNull);
    await DriverSessionStore.instance.claimNativeDutyOwnership(real);
    await DriverSessionStore.instance.clear();
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value, isNull);
  });
  test('clear racing a queued claim wins; no late persisted resurrection', () async {
    final real = await login('a');
    final claim = DriverSessionStore.instance.claimNativeDutyOwnership(real);
    await DriverSessionStore.instance.clearNativeDutyOwnership();
    expect(await claim, isFalse);
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value, isNull);
  });
  test('operator preview and expired bearer cannot become native owner', () async {
    final real = await login('a');
    for (final edits in [
      {'linkMethod': kOperatorMintDriverLinkMethod},
      {'driverSessionExpiresAtUtc': DateTime.now().toUtc().subtract(const Duration(seconds: 1)).toIso8601String()},
    ]) {
      final invalid = ActiveDriverSession.fromJson({...real.toJson(includeToken: true), ...edits});
      expect(await DriverSessionStore.instance.claimNativeDutyOwnership(invalid), isFalse);
    }
    expect(nativeDriverDutySessionNotifier.value, isNull);
  });
  test('a revoked or missing secure bearer cannot restore the native owner', () async {
    final real = await login('a');
    await DriverSessionStore.instance.claimNativeDutyOwnership(real);
    await DriverSessionCredentials().delete('tenant', 'company', 'a');
    nativeDriverDutySessionNotifier.value = null;
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value, isNull);
  });
  test('owner storage failure refuses activation and does not crash restoration', () async {
    final real = await login('a');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'), (_) async => throw PlatformException(code: 'unavailable'),
    );
    expect(await DriverSessionStore.instance.claimNativeDutyOwnership(real), isFalse);
    expect(nativeDriverDutySessionNotifier.value, isNull);
    await DriverSessionStore.instance.restoreNativeDutyOwnership();
    expect(nativeDriverDutySessionNotifier.value, isNull);
    await DriverSessionStore.instance.clearNativeDutyOwnership();
  });
  test('every server actor coordinate must match the selected device driver', () {
    const selected = DriverDutyIdentity(tenantId: 't', companyId: 'c', driverId: 'd', vehicleId: 'v');
    expect(selected.matches(tenantId: 't', companyId: 'c', driverId: 'd', vehicleId: 'v'), isTrue);
    for (final wrong in ['tenant', 'company', 'driver', 'vehicle']) {
      expect(selected.matches(tenantId: wrong == 'tenant' ? 'other' : 't',
        companyId: wrong == 'company' ? 'other' : 'c', driverId: wrong == 'driver' ? 'other' : 'd',
        vehicleId: wrong == 'vehicle' ? 'other' : 'v'), isFalse);
    }
  });
}
