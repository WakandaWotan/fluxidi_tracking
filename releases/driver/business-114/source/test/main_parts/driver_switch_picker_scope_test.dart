import '../support/driver_login_ui_fixture.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _own = 'fixture_switch_own';
const _foreign = 'fixture_switch_foreign';
const _scope = (tenantId: _own, companyId: _own, companyCode: 'FLX-90001');
const _otherScope = (tenantId: _foreign, companyId: _foreign, companyCode: 'FLX-90002');
const _pickerKey = ValueKey('vehicle_driver_choice');

ActiveCompanySession _admin(String company) => ActiveCompanySession(
  companyId: company, role: 'companyAdmin', createdAt: '', lastUsedAt: '',
  companySessionToken: 'fixture-company-$company',
  companyCode: company == _own ? 'FLX-90001' : 'FLX-90002',
);

Map<String, dynamic> _binding(String company, {String suffix = ''}) => {
  'tenant_id': company, 'company_id': company,
  'vehicle_id': '${company}_physical_vehicle$suffix',
  'device_id': '${company}_device$suffix', 'device_token': 'fixture-device$suffix',
  'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 600000,
};

http.Response _directory(String company) => http.Response(jsonEncode({
  'ok': true, 'tenant_id': company, 'company_id': company, 'drivers': [
    {'tenant_id': company, 'company_id': company, 'driver_id': '${company}_next',
      'display_name': 'Next own driver', 'is_active': true,
      'assigned_vehicle_id': '', 'weekly_roster': {}, 'working': false},
    {'tenant_id': company, 'company_id': company, 'driver_id': '${company}_other',
      'display_name': 'Other own driver', 'is_active': true},
  ],
}), 200);

http.Response _deviceDirectory(String company) => http.Response(jsonEncode({
  'ok': true, 'tenant_id': company, 'company_id': company,
  'vehicle_id': '${company}_physical_vehicle', 'company_code': 'FLX-90001',
  'drivers': [
    {'driver_id': '${company}_next', 'name': 'Next own driver'},
    {'driver_id': '${company}_other', 'name': 'Other own driver'},
  ],
}), 200);

Map<String, dynamic> _login({String? changedField}) => {
  'ok': true, 'role': 'driver', 'tenant_id': _own, 'company_id': _own,
  'driver_id': '${_own}_next', 'driver_name': 'Next own driver',
  // The next driver may have a different assigned vehicle; no previous actor lock.
  'assigned_vehicle_id': '${_own}_next_vehicle',
  'company_display_name': 'Own company', 'driver_session_token': 'fixture-personal',
  'expires_in': 3600,
  if (changedField != null) changedField: 'foreign_actor',
};

Future<void> _drain(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> _mount(WidgetTester tester, {
  ({String tenantId, String companyId, String companyCode}) scope = _scope,
}) async {
  await tester.pumpWidget(MaterialApp(home: ChauffeurLoginPage(
    key: const ValueKey('switch_login'), retainedCompanyScope: scope,
    driverDashboardBuilder: (_) => const Scaffold(body: Text('verified next driver')),
  )));
  await _drain(tester);
  await openFixedDriverCode(tester);
}

Future<void> _selectNext(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(_pickerKey));
  await tester.tap(find.byKey(_pickerKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Next own driver').last);
  await tester.pumpAndSettle();
}

Future<void> _submit(WidgetTester tester, {bool declinePin = true}) async {
  // Company code is retained, so only the personal fixed-code field is shown.
  await tester.enterText(find.byType(TextFormField).first, '123456');
  final button = find.byKey(const ValueKey('driver_fixed_code_login'));
  await tester.ensureVisible(button);
  await tester.runAsync(() => tester.tap(button));
  await _drain(tester);
  // Non-PIN switch tests may decline the newly supported personal-phone setup.
  if (declinePin && find.text('Persoonlijke pincode instellen').evaluate().isNotEmpty) {
    await tester.tap(find.text('Annuleren'));
    await _drain(tester);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLanguage oldLanguage;
  late ActiveCompanySession? oldCompany;
  late CompanyOpsLocalSession? oldOps;
  late CompanyProfile? oldProfile;
  late ActiveDriverSession? oldDriver;
  late ActiveDriverSession? oldOwner;
  late AppRole oldRole;
  late Directory stateRoot;

  setUp(() {
    oldLanguage = appLanguageNotifier.value;
    oldCompany = activeCompanySessionNotifier.value;
    oldOps = companyOpsLocalSessionNotifier.value;
    oldProfile = companyProfileNotifier.value;
    oldDriver = activeDriverSessionNotifier.value;
    oldOwner = nativeDriverDutySessionNotifier.value;
    oldRole = appRoleNotifier.value;
    appLanguageNotifier.value = AppLanguage.nl;
    activeCompanySessionNotifier.value = _admin(_own);
    companyOpsLocalSessionNotifier.value = null;
    companyProfileNotifier.value = null;
    activeDriverSessionNotifier.value = null;
    nativeDriverDutySessionNotifier.value = null;
    FlutterSecureStorage.setMockInitialValues({});
    stateRoot = Directory.systemTemp.createTempSync('fluxidi-switch-picker-');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => stateRoot.path);
  });

  tearDown(() async {
    await DriverSessionStore.instance.clear();
    FlutterSecureStorage.setMockInitialValues({});
    appLanguageNotifier.value = oldLanguage;
    activeCompanySessionNotifier.value = oldCompany;
    companyOpsLocalSessionNotifier.value = oldOps;
    companyProfileNotifier.value = oldProfile;
    activeDriverSessionNotifier.value = oldDriver;
    nativeDriverDutySessionNotifier.value = oldOwner;
    appRoleNotifier.value = oldRole;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
    if (stateRoot.existsSync()) stateRoot.deleteSync(recursive: true);
  });

  void view(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('retained own company lists all names without a new company code or setup', (tester) async {
    view(tester);
    await http.runWithClient(() async {
      await _mount(tester);
      expect(find.byType(TextFormField), findsOneWidget);
      expect(find.text('Dit toestel aan een voertuig koppelen'), findsNothing);
      final picker = tester.widget<DropdownButtonFormField<String>>(find.byKey(_pickerKey));
      expect(picker.initialValue, isNull);
      await tester.ensureVisible(find.byKey(_pickerKey));
      await tester.tap(find.byKey(_pickerKey));
      await tester.pumpAndSettle();
      expect(find.text('Next own driver'), findsOneWidget);
      expect(find.text('Other own driver'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/admin/company/drivers/index');
      expect(request.url.queryParameters['company_id'], _own);
      expect(request.headers['authorization'], 'Bearer fixture-company-$_own');
      return _directory(_own);
    }));
  });

  testWidgets('foreign admin is ignored while the retained own physical binding lists own names', (tester) async {
    view(tester);
    activeCompanySessionNotifier.value = _admin(_foreign);
    final originalBinding = jsonEncode(_binding(_own));
    FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1': originalBinding});
    await http.runWithClient(() async {
      await _mount(tester);
      await _selectNext(tester);
      expect(find.text('Next own driver'), findsOneWidget);
      expect(activeCompanySessionNotifier.value?.companyId, _foreign);
      expect(await tester.runAsync(() => const FlutterSecureStorage().read(key: 'vehicle_device_binding_v1')), originalBinding);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/public/vehicle-device/drivers');
      final payload = jsonDecode(request.body) as Map;
      expect(payload['tenant_id'], _own);
      expect(payload['company_id'], _own);
      expect(payload['device_id'], '${_own}_device');
      return _deviceDirectory(_own);
    }));
  });

  for (final foreignBinding in [false, true]) {
    testWidgets('retained scope has no fallback with ${foreignBinding ? 'foreign' : 'missing'} binding and foreign admin', (tester) async {
      view(tester);
      activeCompanySessionNotifier.value = _admin(_foreign);
      if (foreignBinding) FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': jsonEncode(_binding(_foreign)),
      });
      var calls = 0;
      await http.runWithClient(() async {
        await _mount(tester);
        expect(find.byKey(_pickerKey), findsNothing);
        expect(find.textContaining('Chauffeurslijst niet beschikbaar'), findsOneWidget);
        expect(find.byType(TextFormField), findsOneWidget);
        await _submit(tester);
        expect(activeDriverSessionNotifier.value, isNull);
        expect(calls, 0);
        await tester.pumpWidget(const SizedBox());
      }, () => driverLoginFixtureClient((request) async {
        calls++;
        throw StateError('foreign directory/auth must never be requested');
      }));
    });
  }

  testWidgets('late directory response cannot restore the previous retained scope', (tester) async {
    view(tester);
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await _mount(tester);
      await _mount(tester, scope: _otherScope);
      pending.complete(_directory(_own));
      await _drain(tester);
      expect(find.byKey(_pickerKey), findsNothing);
      expect(activeDriverSessionNotifier.value, isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async => pending.future));
  });

  testWidgets('changed physical binding rejects a late directory response', (tester) async {
    view(tester);
    activeCompanySessionNotifier.value = null;
    FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1': jsonEncode(_binding(_own))});
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await _mount(tester);
      await const FlutterSecureStorage().write(key: 'vehicle_device_binding_v1', value: jsonEncode(_binding(_own, suffix: '_new')));
      pending.complete(_deviceDirectory(_own));
      await _drain(tester);
      expect(find.byKey(_pickerKey), findsNothing);
      expect(find.textContaining('Chauffeurslijst niet beschikbaar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async => pending.future));
  });

  for (final field in ['tenant_id', 'company_id', 'driver_id']) {
    testWidgets('retained scope rejects authenticated $field mismatch before session save', (tester) async {
      view(tester);
      await http.runWithClient(() async {
        await _mount(tester);
        await _selectNext(tester);
        await _submit(tester);
        expect(find.textContaining('Deze login hoort niet bij de gekozen chauffeur'), findsOneWidget);
        expect(activeDriverSessionNotifier.value, isNull);
        expect(find.text('verified next driver'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => driverLoginFixtureClient((request) async {
        if (request.url.path == '/admin/company/drivers/index') return _directory(_own);
        expect(request.url.path, '/public/driver/login');
        expect(jsonDecode(request.body)['company_code'], 'FLX-90001');
        return http.Response(jsonEncode(_login(changedField: field)), 200);
      }));
    });
  }

  testWidgets('late personal login cannot restore an actor after retained scope changes', (tester) async {
    view(tester);
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await _mount(tester);
      await _selectNext(tester);
      await _submit(tester);
      await _mount(tester, scope: _otherScope);
      pending.complete(http.Response(jsonEncode(_login()), 200));
      await _drain(tester);
      expect(activeDriverSessionNotifier.value, isNull);
      expect(find.text('verified next driver'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async {
      if (request.url.path == '/admin/company/drivers/index') return _directory(_own);
      return pending.future;
    }));
  });

  testWidgets('changed device capability rejects an in-flight personal login', (tester) async {
    view(tester);
    FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1': jsonEncode(_binding(_own))});
    final pending = Completer<http.Response>();
    await http.runWithClient(() async {
      await _mount(tester);
      await _selectNext(tester);
      await _submit(tester);
      await const FlutterSecureStorage().write(key: 'vehicle_device_binding_v1', value: jsonEncode(_binding(_own, suffix: '_changed')));
      pending.complete(http.Response(jsonEncode(_login()), 200));
      await _drain(tester);
      expect(activeDriverSessionNotifier.value, isNull);
      expect(find.text('verified next driver'), findsNothing);
      expect(find.byKey(_pickerKey), findsNothing);
      expect(find.textContaining('Voertuigkoppeling gewijzigd'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async {
      if (request.url.path == '/admin/company/drivers/index') return _directory(_own);
      expect(request.url.path, '/public/driver/login');
      return pending.future;
    }));
  });

  testWidgets('next own driver saves retained code without copying old assigned vehicle or personal actor', (tester) async {
    view(tester);
    final originalBinding = jsonEncode(_binding(_own));
    FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1': originalBinding});
    await http.runWithClient(() async {
      await _mount(tester);
      await _selectNext(tester);
      await _submit(tester);
      await _drain(tester, rounds: 100);
      expect(find.text('verified next driver'), findsOneWidget);
      expect(activeDriverSessionNotifier.value?.driverId, '${_own}_next');
      expect(activeDriverSessionNotifier.value?.assignedVehicleId, '${_own}_next_vehicle');
      expect(activeDriverSessionNotifier.value?.companyCode, 'FLX-90001');
      expect(activeCompanySessionNotifier.value?.companyId, _own);
      expect(await tester.runAsync(() => const FlutterSecureStorage().read(key: 'vehicle_device_binding_v1')), originalBinding);
      for (final file in stateRoot.listSync(recursive: true).whereType<File>()) {
        expect(file.readAsStringSync(), isNot(contains('fixture-personal')));
      }
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async {
      if (request.url.path == '/admin/company/drivers/index') return _directory(_own);
      // This historical fixture predates the explicit sign-in activation gate.
      // Model its existing non-vehicle-duty policy; do not bypass the real gate.
      if (request.url.path == '/public/driver/status') {
        final session = activeDriverSessionNotifier.value!;
        expect(request.headers['authorization'], 'Bearer ${session.driverSessionToken}');
        return http.Response(jsonEncode({'ok': true, 'tenant_id': session.tenantId,
          'company_id': session.companyId, 'driver_id': session.driverId,
          'driver': {'driver_id': session.driverId, 'is_active': true,
            'assigned_vehicle_id': session.assignedVehicleId, 'availability_status': 'available'}}), 200);
      }
      if (request.url.path == '/public/driver/vehicle-duty-state') {
        expect(request.method, 'POST');
        return http.Response('{"ok":false,"error":"vehicle_operations_disabled"}', 409);
      }
      expect(request.url.path, '/public/driver/login');
      final payload = jsonDecode(request.body) as Map;
      expect(payload['company_code'], 'FLX-90001');
      expect(payload['selected_driver_id'], '${_own}_next');
      expect(payload['vehicle_device']['device_id'], '${_own}_device');
      return http.Response(jsonEncode(_login()), 200);
    }));
  });

  for (final change in ['company', 'device']) {
  testWidgets('changed $change context during PIN dialog cannot save the previous personal login', (tester) async {
    view(tester);
    FlutterSecureStorage.setMockInitialValues({'vehicle_device_binding_v1': jsonEncode(_binding(_own))});
    await http.runWithClient(() async {
      await _mount(tester);
      await _selectNext(tester);
      await _submit(tester, declinePin: false);
      await tester.pump(const Duration(milliseconds: 400));
      await _drain(tester);
      expect(find.byKey(const ValueKey('vehicle_personal_pin')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('vehicle_personal_pin')), '654321');
      await tester.enterText(find.byKey(const ValueKey('vehicle_personal_pin_confirm')), '654321');
      if (change == 'company') activeCompanySessionNotifier.value = _admin(_foreign);
      else await const FlutterSecureStorage().write(key: 'vehicle_device_binding_v1', value: jsonEncode(_binding(_own, suffix: '_after_pin')));
      await _drain(tester);
      await tester.tap(find.text('Doorgaan'));
      await tester.pump(const Duration(milliseconds: 400));
      await _drain(tester);
      await tester.pumpAndSettle();
      expect(activeDriverSessionNotifier.value, isNull);
      expect(find.text('verified next driver'), findsNothing);
      final secure = await const FlutterSecureStorage().readAll();
      expect(secure.keys.where((key) => key.startsWith('vehicle_driver_pin')), isEmpty);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async {
      if (request.url.path == '/admin/company/drivers/index') return _directory(_own);
      if (request.url.path == '/public/vehicle-device/drivers') return _deviceDirectory(_own);
      expect(request.url.path, '/public/driver/login');
      final response = _login();
      response['assigned_vehicle_id'] = '${_own}_physical_vehicle';
      return http.Response(jsonEncode(response), 200);
    }));
  });

  }

  testWidgets('temporary personal pairing sheet retains company code without asking for setup', (tester) async {
    view(tester);
    await http.runWithClient(() async {
      await _mount(tester);
      await _selectNext(tester);
      final button = find.text('Tijdelijke koppelcode invoeren');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Bedrijfs-ID'), findsNothing);
      // One personal code field in the pairing sheet; no company code input.
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), findsOneWidget);
      await tester.tap(find.text('Annuleren').last);
      await tester.pumpAndSettle();
      expect(activeDriverSessionNotifier.value, isNull);
      await tester.pumpWidget(const SizedBox());
    }, () => driverLoginFixtureClient((request) async => _directory(_own)));
  });
}
