import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_session_credentials.dart';
import 'package:fluxidi_tracking/driver/driver_startup_preference.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

ActiveDriverSession _actor(String id, {String? bearer, String? company}) => ActiveDriverSession(
  driverId: id, employeeNumber: id, fullName: id, phone: '',
  loggedInAt: '2026-10-11T12:00:00Z', updatedAt: '2026-10-11T12:00:00Z',
  tenantId: company ?? 'switch_company', companyId: company ?? 'switch_company',
  companyCode: 'FLX-90001', assignedVehicleId: 'vehicle_$id',
  driverSessionToken: bearer ?? 'fixture-bearer-$id',
  driverSessionExpiresAtUtc: DateTime.now().toUtc().add(const Duration(days: 1)).toIso8601String(),
  linkMethod: 'public_driver_login',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final store = DriverSessionStore.instance;
  final credentials = DriverSessionCredentials();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory root;
  late Map<String, String> secure;
  late ActiveDriverSession? oldPersonal;
  late ActiveDriverSession? oldNative;
  late ActiveCompanySession? oldCompany;
  Future<String> Function(int call)? rootHook;
  Future<String?> Function(String key)? readHook;
  Future<void> Function(String key)? deleteHook;
  var rootCalls = 0;
  var secureDeletes = 0;

  Directory sessionRoot() => Directory('${root.path}/driver_session');
  File sessionFile(ActiveDriverSession actor) => File('${sessionRoot().path}/tenant_${actor.tenantId}/company_${actor.companyId}/active_driver_session_v1.json');
  File pointerFile() => File('${sessionRoot().path}/last_standalone_driver_scope_v1.json');
  File nativeFile() => File('${sessionRoot().path}/native_driver_duty_owner_v1.json');
  File hintFile() => File('${root.path}/preferred_standalone_driver_v1.json');

  void seed(ActiveDriverSession actor, {bool native = true}) {
    final file = sessionFile(actor);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(actor.toJson()));
    pointerFile().writeAsStringSync(jsonEncode({
      'tenantId': actor.tenantId, 'companyId': actor.companyId, 'driverId': actor.driverId,
      'linkMethod': actor.linkMethod, 'updatedAt': actor.updatedAt,
    }));
    secure[credentials.keyFor(actor.tenantId!, actor.companyId!, actor.driverId)] = actor.driverSessionToken!;
    activeDriverSessionNotifier.value = actor;
    if (native) {
      nativeFile().writeAsStringSync(jsonEncode(driverDutyIdentity(actor).toJson()));
      nativeDriverDutySessionNotifier.value = actor;
    }
  }

  void expectSaved(ActiveDriverSession actor) {
    expect(activeDriverSessionNotifier.value?.driverId, actor.driverId);
    expect(activeDriverSessionNotifier.value?.driverSessionToken, actor.driverSessionToken);
    expect(jsonDecode(sessionFile(actor).readAsStringSync())['driverId'], actor.driverId);
    expect(jsonDecode(pointerFile().readAsStringSync())['driverId'], actor.driverId);
    expect(secure[credentials.keyFor(actor.tenantId!, actor.companyId!, actor.driverId)], actor.driverSessionToken);
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('fluxidi-switch-clear-');
    secure = {'vehicle_device_binding_v1': 'fixture-physical-binding', 'company_session': 'fixture-company-credential'};
    oldPersonal = activeDriverSessionNotifier.value;
    oldNative = nativeDriverDutySessionNotifier.value;
    oldCompany = activeCompanySessionNotifier.value;
    activeDriverSessionNotifier.value = null;
    nativeDriverDutySessionNotifier.value = null;
    activeCompanySessionNotifier.value = null;
    rootHook = null; readHook = null; deleteHook = null; rootCalls = 0; secureDeletes = 0;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async {
      rootCalls++;
      return rootHook == null ? root.path : rootHook!(rootCalls);
    });
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (call) async {
      final arguments = Map<String, dynamic>.from(call.arguments as Map);
      final key = arguments['key']?.toString() ?? '';
      switch (call.method) {
        case 'read': return readHook == null ? secure[key] : readHook!(key);
        case 'write': secure[key] = arguments['value'].toString(); return null;
        case 'delete':
          secureDeletes++;
          if (deleteHook != null) await deleteHook!(key);
          secure.remove(key);
          return null;
        case 'containsKey': return secure.containsKey(key);
        case 'readAll': return secure;
        default: throw StateError('unexpected storage operation ${call.method}');
      }
    });
  });

  tearDown(() async {
    rootHook = null; readHook = null; deleteHook = null;
    await store.clear();
    activeDriverSessionNotifier.value = oldPersonal;
    nativeDriverDutySessionNotifier.value = oldNative;
    activeCompanySessionNotifier.value = oldCompany;
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    messenger.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), null);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('captured A clears only its personal metadata, bearer and native pointer', () async {
    final a = _actor('A'); seed(a);
    final ownCompany = ActiveCompanySession(companyId: 'switch_company', role: 'companyAdmin', createdAt: '', lastUsedAt: '', companySessionToken: 'fixture-admin');
    activeCompanySessionNotifier.value = ownCompany;
    expect(await store.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true), isTrue);
    expect(activeDriverSessionNotifier.value, isNull);
    expect(nativeDriverDutySessionNotifier.value, isNull);
    expect(sessionFile(a).existsSync(), isFalse);
    expect(pointerFile().existsSync(), isFalse);
    expect(nativeFile().existsSync(), isFalse);
    expect(secure.containsKey(credentials.keyFor(a.tenantId!, a.companyId!, a.driverId)), isFalse);
    expect(secure['vehicle_device_binding_v1'], 'fixture-physical-binding');
    expect(secure['company_session'], 'fixture-company-credential');
    expect(activeCompanySessionNotifier.value, same(ownCompany));
  });

  test('B already active refuses A clear before any storage await', () async {
    final a = _actor('A'); final b = _actor('B'); seed(b);
    expect(await store.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true), isFalse);
    expect(rootCalls, 0); expect(secureDeletes, 0); expectSaved(b);
    expect(nativeDriverDutySessionNotifier.value, same(b));
  });

  for (final phase in ['root', 'bearer', 'native-root']) {
    test('replacement B during $phase await preserves B personal/native storage', () async {
      final a = _actor('A'); final b = _actor('B'); seed(a);
      final entered = Completer<void>(); final release = Completer<void>();
      if (phase == 'bearer') {
        readHook = (key) async {
          if (!entered.isCompleted) { entered.complete(); await release.future; }
          return secure[key];
        };
      } else {
        rootHook = (call) async {
          if (call == (phase == 'root' ? 1 : 2)) { entered.complete(); await release.future; }
          return root.path;
        };
      }
      final clearing = store.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true);
      await entered.future;
      seed(b);
      release.complete();
      expect(await clearing, isFalse);
      expectSaved(b);
      expect(nativeDriverDutySessionNotifier.value, same(b));
      expect(jsonDecode(nativeFile().readAsStringSync())['driver_id'], 'B');
      expect(secureDeletes, 0);
    });
  }

  test('native B claimed mid-clear is not invalidated before its queued write publishes', () async {
    final a = _actor('A'); final b = _actor('B'); seed(a);
    final readEntered = Completer<void>(); final releaseRead = Completer<void>();
    readHook = (key) async { readEntered.complete(); await releaseRead.future; return secure[key]; };
    final nativeEntered = Completer<void>(); final releaseNative = Completer<void>();
    rootHook = (call) async { if (call == 2) { nativeEntered.complete(); await releaseNative.future; } return root.path; };
    final clearing = store.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true);
    await readEntered.future;
    final claiming = store.claimNativeDutyOwnership(b);
    await nativeEntered.future;
    releaseRead.complete();
    expect(await clearing, isFalse);
    releaseNative.complete();
    expect(await claiming, isTrue);
    expect(nativeDriverDutySessionNotifier.value, same(b));
    expect(jsonDecode(nativeFile().readAsStringSync())['driver_id'], 'B');
    expect(sessionFile(a).existsSync(), isTrue);
  });

  for (final sameDriver in [false, true]) {
    test('in-flight secure delete cannot erase ${sameDriver ? 'renewed same-driver' : 'different-driver'} B login', () async {
      final a = _actor('A');
      final b = _actor(sameDriver ? 'A' : 'B', bearer: 'fixture-replacement-bearer');
      seed(a);
      final entered = Completer<void>(); final release = Completer<void>();
      deleteHook = (key) async {
        if (key == credentials.keyFor(a.tenantId!, a.companyId!, a.driverId) && !entered.isCompleted) {
          entered.complete(); await release.future;
        }
      };
      final clearing = store.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true);
      await entered.future;
      // A replacement save is serialized behind A's in-flight secure mutation.
      final saving = store.saveBackendDriverLoginSession(
        tenantId: b.tenantId!, companyId: b.companyId!, companyCode: 'FLX-90001',
        driverId: b.driverId, driverName: b.fullName, companyDisplayName: 'Own',
        assignedVehicleId: b.assignedVehicleId, driverSessionToken: b.driverSessionToken,
        expiresInSeconds: 3600,
      );
      activeDriverSessionNotifier.value = b;
      release.complete();
      expect(await clearing, isFalse);
      await saving;
      expectSaved(b);
      expect(secure['vehicle_device_binding_v1'], 'fixture-physical-binding');
    });
  }

  test('foreign persisted session/pointer cannot be deleted by stale A notifier', () async {
    final a = _actor('A'); final b = _actor('B'); seed(b);
    activeDriverSessionNotifier.value = a;
    nativeDriverDutySessionNotifier.value = null;
    expect(await store.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true), isFalse);
    expect(jsonDecode(sessionFile(b).readAsStringSync())['driverId'], 'B');
    expect(jsonDecode(pointerFile().readAsStringSync())['driverId'], 'B');
    expect(secureDeletes, 0);
  });

  test('false lifecycle/current guard never clears current A', () async {
    final a = _actor('A'); seed(a);
    expect(await store.clearForDriverSwitch(expectedOwner: a, isCurrent: () => false), isFalse);
    expect(rootCalls, 0); expectSaved(a);
  });

  test('preview expected owner cannot use personal switch clear', () async {
    final preview = ActiveDriverSession(driverId: 'preview', employeeNumber: '', fullName: 'Preview', phone: '', loggedInAt: '', updatedAt: '', tenantId: 'switch_company', companyId: 'switch_company', driverSessionToken: 'fixture-preview', linkMethod: kCompanyAdminDriverViewLinkMethod);
    activeDriverSessionNotifier.value = preview;
    expect(await store.clearForDriverSwitch(expectedOwner: preview, isCurrent: () => true), isFalse);
    expect(rootCalls, 0); expect(activeDriverSessionNotifier.value, same(preview));
  });

  test('startup hint clear accepts only captured A and preserves company/device values', () async {
    final a = _actor('A'); seed(a);
    final startup = DriverStartupPreference(testRoot: root);
    await startup.markDriver(a);
    expect(await startup.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true), isTrue);
    expect(hintFile().existsSync(), isFalse);
    expectSaved(a);
    expect(secure['vehicle_device_binding_v1'], 'fixture-physical-binding');
  });

  for (final sameDriver in [false, true]) {
    test('startup A clear refuses ${sameDriver ? 'renewed same-driver' : 'different-driver'} B during root await', () async {
      final a = _actor('A'); final b = _actor(sameDriver ? 'A' : 'B', bearer: 'fixture-B'); seed(a);
      final startup = DriverStartupPreference.instance;
      await startup.markDriver(a);
      rootCalls = 0;
      final entered = Completer<void>(); final release = Completer<void>();
      rootHook = (call) async { entered.complete(); await release.future; return root.path; };
      final clearing = startup.clearForDriverSwitch(expectedOwner: a, isCurrent: () => true);
      await entered.future;
      seed(b);
      hintFile().writeAsStringSync(jsonEncode(PreferredStandaloneDriver.fromSession(b)!.toJson()));
      release.complete();
      expect(await clearing, isFalse);
      expect(jsonDecode(hintFile().readAsStringSync())['driver_id'], b.driverId);
      expectSaved(b);
      rootHook = null;
    });
  }

  test('startup foreign hint is kept even when notifier still contains A', () async {
    final a = _actor('A'); final b = _actor('B'); seed(a);
    hintFile().writeAsStringSync(jsonEncode(PreferredStandaloneDriver.fromSession(b)!.toJson()));
    expect(await DriverStartupPreference(testRoot: root).clearForDriverSwitch(expectedOwner: a, isCurrent: () => true), isFalse);
    expect(jsonDecode(hintFile().readAsStringSync())['driver_id'], 'B');
  });
}
