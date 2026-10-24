import '../support/driver_login_ui_fixture.dart';
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
import 'package:fluxidi_tracking/driver/vehicle_driver_pin_store.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _own = 'fixture_switch_own';
const _foreign = 'fixture_switch_foreign';
const _scope = (tenantId: _own, companyId: _own, companyCode: 'FLX-90001');
const _otherScope = (
  tenantId: _foreign,
  companyId: _foreign,
  companyCode: 'FLX-90002',
);
const _pickerKey = ValueKey('vehicle_driver_choice');

ActiveCompanySession _admin(String company) => ActiveCompanySession(
  companyId: company,
  role: 'companyAdmin',
  createdAt: '',
  lastUsedAt: '',
  companySessionToken: 'fixture-company-$company',
  companyCode: company == _own ? 'FLX-90001' : 'FLX-90002',
);

Map<String, dynamic> _binding(String company, {String suffix = ''}) => {
  'tenant_id': company,
  'company_id': company,
  'vehicle_id': '${company}_physical_vehicle$suffix',
  'device_id': '${company}_device$suffix',
  'device_token': 'fixture-device$suffix',
  'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 600000,
};

http.Response _directory(String company) => http.Response(
  jsonEncode({
    'ok': true,
    'tenant_id': company,
    'company_id': company,
    'drivers': [
      {
        'tenant_id': company,
        'company_id': company,
        'driver_id': '${company}_next',
        'display_name': 'Next own driver',
        'is_active': true,
        'assigned_vehicle_id': '',
        'weekly_roster': {},
        'working': false,
      },
      {
        'tenant_id': company,
        'company_id': company,
        'driver_id': '${company}_other',
        'display_name': 'Other own driver',
        'is_active': true,
      },
    ],
  }),
  200,
);

http.Response _deviceDirectory(String company) => http.Response(
  jsonEncode({
    'ok': true,
    'tenant_id': company,
    'company_id': company,
    'vehicle_id': '${company}_physical_vehicle',
    'company_code': 'FLX-90001',
    'drivers': [
      {'driver_id': '${company}_next', 'name': 'Next own driver'},
      {'driver_id': '${company}_other', 'name': 'Other own driver'},
    ],
  }),
  200,
);

Map<String, dynamic> _login({String? changedField}) => {
  'ok': true, 'role': 'driver', 'tenant_id': _own, 'company_id': _own,
  'driver_id': '${_own}_next', 'driver_name': 'Next own driver',
  // The next driver may have a different assigned vehicle; no previous actor lock.
  'assigned_vehicle_id': '${_own}_next_vehicle',
  'company_display_name': 'Own company',
  'driver_session_token': 'fixture-personal',
  'expires_in': 3600,
  if (changedField != null) changedField: 'foreign_actor',
};

Future<void> _drain(WidgetTester tester, {int rounds = 8}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

int _authenticatedStatusChecks = 0;
MockClient _loginClient(Future<http.Response> Function(http.Request) handler) => driverLoginFixtureClient((request) async {
  final session = activeDriverSessionNotifier.value;
  if (request.url.path == '/public/driver/vehicle-duty-state') return http.Response('{"ok":false,"error":"vehicle_operations_disabled"}', 409);
  if (request.method == 'GET' && request.url.path == '/public/driver/status' && session != null &&
      request.headers['Authorization'] == 'Bearer ${session.driverSessionToken}') {
    expect(request.url.hasQuery, isFalse);
    _authenticatedStatusChecks++;
    return http.Response(jsonEncode({'ok':true,'tenant_id':session.tenantId,'company_id':session.companyId,
      'driver_id':session.driverId,'driver':{'driver_id':session.driverId,'is_active':true,
        'assigned_vehicle_id':session.assignedVehicleId,'availability_status':'available'}}),200);
  }
  return handler(request);
});

Future<void> _until(WidgetTester tester, bool Function() complete) async {
  for (var i = 0; i < 500 && !complete(); i++) {
    await _drain(tester, rounds: 1);
  }
  expect(
    complete(),
    isTrue,
    reason: 'Asynchronous login or PIN operation must complete',
  );
}

Future<void> _mount(
  WidgetTester tester, {
  ({String tenantId, String companyId, String companyCode})? scope = _scope,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChauffeurLoginPage(
        key: const ValueKey('switch_login'),
        retainedCompanyScope: scope,
        driverDashboardBuilder: (_) =>
            const Scaffold(body: Text('verified next driver')),
      ),
    ),
  );
  await _drain(tester);
  await openFixedDriverCode(tester);
}

Future<void> _selectNext(WidgetTester tester) async {
  await tester.ensureVisible(driverProfilePicker);
  await tester.tap(driverProfilePicker);
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
  if (declinePin &&
      find.text('Persoonlijke pincode instellen').evaluate().isNotEmpty) {
    await tester.tap(find.text('Annuleren'));
    await _drain(tester);
  }
}

void main() => registerPersonalPinScenario('original');

// Each scenario has its own isolate: DriverSessionStore owns asynchronous
// persistence queues that must not cross separate widget fake clocks.
void registerPersonalPinScenario(String scenario) {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Initialize the persistence queue outside the widget fake clock.
  final sessionStore = DriverSessionStore.instance;
  late AppLanguage oldLanguage;
  late ActiveCompanySession? oldCompany;
  late CompanyOpsLocalSession? oldOps;
  late CompanyProfile? oldProfile;
  late ActiveDriverSession? oldDriver;
  late ActiveDriverSession? oldOwner;
  late AppRole oldRole;
  late Directory stateRoot;

  setUp(() {
    _authenticatedStatusChecks = 0;
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
    if (scenario == 'qr-pairing') {
      for (final channel in ['event', 'deviceOrientation']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel('dev.steenbakker.mobile_scanner/scanner/$channel'), (_) async => null);
      }
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'), (call) async {
          if (call.method == 'state') return 1;
          if (call.method == 'request') return false;
          return null;
        });
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => stateRoot.path,
        );
  });

  tearDown(() async {
    for (final channel in ['event', 'deviceOrientation']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel('dev.steenbakker.mobile_scanner/scanner/$channel'), null);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('dev.steenbakker.mobile_scanner/scanner/method'), null);
    await sessionStore.clear();
    FlutterSecureStorage.setMockInitialValues({});
    appLanguageNotifier.value = oldLanguage;
    activeCompanySessionNotifier.value = oldCompany;
    companyOpsLocalSessionNotifier.value = oldOps;
    companyProfileNotifier.value = oldProfile;
    activeDriverSessionNotifier.value = oldDriver;
    nativeDriverDutySessionNotifier.value = oldOwner;
    appRoleNotifier.value = oldRole;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (stateRoot.existsSync()) stateRoot.deleteSync(recursive: true);
  });

  void view(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  if (scenario == 'first')
    testWidgets(
      'first verified login without picker offers PIN for a new driver',
      (tester) async {
        view(tester);
        activeCompanySessionNotifier.value = null;
        await http.runWithClient(
          () async {
            await _mount(tester, scope: null);
            expect(driverProfilePicker, findsNothing);
            final fields = find.byType(TextFormField);
            await tester.enterText(fields.at(0), 'FLX-90001');
            await tester.enterText(fields.at(1), '123456');
            await tester.ensureVisible(find.byKey(const ValueKey('driver_fixed_code_login')));
            await tester.tap(find.byKey(const ValueKey('driver_fixed_code_login')));
            await _drain(tester);
            expect(find.text('Persoonlijke pincode instellen'), findsOneWidget);
            await tester.tap(find.text('Annuleren'));
            await _drain(tester, rounds: 40);
            expect(find.text('verified next driver'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          () => _loginClient((request) async {
            expect(request.url.path, '/public/driver/login');
            return http.Response(jsonEncode(_login()), 200);
          }),
        );
      },
    );

  if (scenario == 'switch')
    testWidgets(
      'two remembered drivers enroll independently and return after restart with their own PIN',
      (tester) async {
        view(tester);
        activeCompanySessionNotifier.value = null;
        const personal = <String, dynamic>{
          'tenant_id': _own,
          'company_id': _own,
        };
        await tester.runAsync(() async {
          final store = DriverPersonalPinStore();
          await store.enroll(
            personal,
            '${_own}_next',
            'FLX-90001',
            '123456',
            '482716',
          );
          await store.rememberDriver(
            personal,
            '${_own}_next',
            'Next own driver',
          );
          // Presentation-only identity from a previously verified QR login.
          await store.rememberVerifiedDriver(
            personal,
            '${_own}_other',
            'Other own driver',
            'FLX-90001',
          );
        });
        var calls = 0;
        await http.runWithClient(
          () async {
            Future<void> selectOther() async {
              await tester.ensureVisible(driverProfilePicker);
              await tester.tap(driverProfilePicker);
              await tester.pumpAndSettle();
              await tester.tap(find.text('Other own driver').last);
              await tester.pumpAndSettle();
            }

            await _mount(tester);
            await selectOther();
            await tester.enterText(find.byType(TextFormField).first, '654321');
            await tester.ensureVisible(find.byKey(const ValueKey('driver_fixed_code_login')));
            await tester.tap(find.byKey(const ValueKey('driver_fixed_code_login')));
            await _drain(tester);
            expect(find.text('Persoonlijke pincode instellen'), findsOneWidget);
            await tester.enterText(
              find.byKey(const ValueKey('vehicle_personal_pin')),
              '837291',
            );
            await tester.enterText(
              find.byKey(const ValueKey('vehicle_personal_pin_confirm')),
              '837291',
            );
            await tester.tap(find.text('Doorgaan'));
            await _until(
              tester,
              () => find.text('verified next driver').evaluate().isNotEmpty,
            );
            expect(
              activeDriverSessionNotifier.value?.driverId,
              '${_own}_other',
            );
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(() => DriverSessionStore.instance.clear());
            await _mount(tester);
            await selectOther();
            Future<void> unlock(String pin) async {
              await enterInlineDriverPin(tester, pin);
              await _until(
                tester,
                () =>
                    find.text('verified next driver').evaluate().isNotEmpty ||
                    find
                        .text(
                          'Pincode onjuist of niet beschikbaar. Je kunt je vaste chauffeurscode gebruiken.',
                        )
                        .evaluate()
                        .isNotEmpty,
              );
            }

            await unlock('482716');
            expect(
              calls,
              1,
            ); // Other driver's PIN cannot even send a server login.
            expect(activeDriverSessionNotifier.value, isNull);
            await unlock('837291');
            expect(calls, 2);
            expect(
              activeDriverSessionNotifier.value?.driverId,
              '${_own}_other',
            );
            expect(find.text('Persoonlijke pincode instellen'), findsNothing);
            await tester.runAsync(() async {
              expect(
                (await DriverPersonalPinStore().unlock(
                  personal,
                  '${_own}_next',
                  '482716',
                ))?.driverCode,
                '123456',
              );
            });
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          () => _loginClient((request) async {
            expect(request.url.path, '/public/driver/login');
            expect(jsonDecode(request.body)['driver_code'], '654321');
            calls++;
            return http.Response(
              jsonEncode({
                ..._login(),
                'driver_id': '${_own}_other',
                'driver_name': 'Other own driver',
              }),
              200,
            );
          }),
        );
      },
    );

  if (scenario == 'pairing' || scenario == 'qr-pairing')
    testWidgets(
      '$scenario enrolls PIN without long code and returns via server-checked PIN',
      (tester) async {
        view(tester);
        activeCompanySessionNotifier.value = null;
        var verifications = 0;
        await http.runWithClient(
          () async {
            await _mount(tester, scope: null);
            if (scenario == 'qr-pairing') {
              await tester.ensureVisible(find.text('Scan chauffeur-QR'));
              await tester.tap(find.text('Scan chauffeur-QR'));
              await tester.pumpAndSettle();
              await _drain(tester);
              tester.widget<MobileScanner>(find.byType(MobileScanner)).onDetect!(
                BarcodeCapture(barcodes: [Barcode(rawValue: 'fluxidi://driver-link?company_code=FLX-90001&pairing_code=temporary-pairing-token&challenge_id=one-time-challenge')]),
              );
              await tester.pumpAndSettle();
              await tester.tap(find.text('Doorgaan'));
            } else {
            final button = find.text('Tijdelijke koppelcode invoeren');
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
            final sheet = find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(TextField),
            );
            await tester.enterText(sheet.at(0), 'FLX-90001');
            await tester.enterText(sheet.at(1), 'temporary-pairing-token');
            await tester.tap(find.text('Code koppelen'));
            }
            await _drain(tester, rounds: 40);
            expect(find.text('Persoonlijke pincode instellen'), findsOneWidget);
            expect(
              await DriverPersonalPinStore().hasPin({
                'tenant_id': _own,
                'company_id': _own,
              }, '${_own}_next'),
              isFalse,
            );
            expect(
              (await const FlutterSecureStorage().readAll()).values.any(
                (v) => v.contains('temporary-pairing-token'),
              ),
              isFalse,
            );
            await tester.tap(find.text('PIN instellen'));
            await _drain(tester);
            await tester.tap(find.byKey(const ValueKey('personal-pin-set')));
            await tester.pump();
            expect(find.byKey(const ValueKey('personal-pin-driver-code')), findsNothing);
            await tester.enterText(
              find.byKey(const ValueKey('personal-pin-new')),
              '837291',
            );
            await tester.enterText(
              find.byKey(const ValueKey('personal-pin-confirm')),
              '837291',
            );
            await tester.ensureVisible(
              find.byKey(const ValueKey('personal-pin-save')),
            );
            await tester.tap(find.byKey(const ValueKey('personal-pin-save')));
            await _until(
              tester,
              () => find.text('verified next driver').evaluate().isNotEmpty,
            );
            expect(verifications + _authenticatedStatusChecks, 2);
            expect(find.text('verified next driver'), findsOneWidget);
            await tester.runAsync(() async {
              final credential = await DriverPersonalPinStore().unlockForLogin(
                {'tenant_id': _own, 'company_id': _own},
                '${_own}_next',
                '837291',
              );
              expect(credential?.driverCode, '');
              expect(credential?.serverSession?.session.driverId, '${_own}_next');
              expect((await const FlutterSecureStorage().readAll()).values.any(
                (v) => v.contains('temporary-pairing-token') || v.contains('837291')), isFalse);
            });
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(() => DriverSessionStore.instance.clear());
            await _mount(tester);
            await _selectNext(tester);
            await enterInlineDriverPin(tester, '837291');
            await _until(tester, () => find.text('verified next driver').evaluate().isNotEmpty);
            expect(verifications + _authenticatedStatusChecks, 4);
            expect(activeDriverSessionNotifier.value?.driverId, '${_own}_next');
            await tester.pumpWidget(const SizedBox());
          },
          () => _loginClient((request) async {
            if (request.url.path == '/public/company/driver-link/verify') {
              final verificationRequest = jsonDecode(request.body);
              expect(verificationRequest['pairing_code'], 'temporary-pairing-token');
              if (scenario == 'qr-pairing') expect(verificationRequest['challenge_id'], 'one-time-challenge');
              return http.Response(
                jsonEncode({
                  'ok': true,
                  'role': 'driver',
                  'tenant_id': _own,
                  'company_id': _own,
                  'company_code': 'FLX-90001',
                  'driver_session_token': 'fresh-pairing-session',
                  'expires_in': 3600,
                  'driver': {
                    'driver_id': '${_own}_next',
                    'driver_name': 'Next own driver',
                    'employee_number': 'temporary-pairing-token',
                    'assigned_vehicle_id': '${_own}_next_vehicle',
                  },
                }),
                200,
              );
            }
            if (request.url.path == '/public/company/drivers') return _directory(_own);
            expect(request.url.path, '/public/driver/status');
            expect(request.method, 'GET');
            expect(request.headers['Authorization'], 'Bearer fresh-pairing-session');
            expect(request.url.queryParameters.containsKey('driver_id'), isFalse);
            verifications++;
            return http.Response(jsonEncode({'ok': true, 'tenant_id': _own, 'company_id': _own,
              'driver_id': '${_own}_next', 'driver': {'driver_id': '${_own}_next',
                'is_active': true, 'assigned_vehicle_id': '${_own}_next_vehicle'}}), 200);
          }),
        );
      },
    );

  if (scenario == 'original')
    testWidgets(
      'ordinary phone enrolls PIN after fixed code and returns via PIN without company session or vehicle binding',
      (tester) async {
        view(tester);
        var calls = 0;
        await http.runWithClient(
          () async {
            await _mount(tester);
            await _selectNext(tester);
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('vehicle_pin_login')),
                  )
                  .onPressed,
              isNull,
            );
            await tester.enterText(find.byType(TextFormField).first, '123456');
            await tester.ensureVisible(find.byKey(const ValueKey('driver_fixed_code_login')));
            await tester.tap(find.byKey(const ValueKey('driver_fixed_code_login')));
            await _drain(tester);
            expect(find.text('Persoonlijke pincode instellen'), findsOneWidget);
            await tester.enterText(
              find.byKey(const ValueKey('vehicle_personal_pin')),
              '482716',
            );
            await tester.enterText(
              find.byKey(const ValueKey('vehicle_personal_pin_confirm')),
              '482716',
            );
            await tester.tap(find.text('Doorgaan'));
            await _until(
              tester,
              () => find.text('verified next driver').evaluate().isNotEmpty,
            );
            expect(find.text('verified next driver'), findsOneWidget);
            final pinStore = DriverPersonalPinStore();
            expect(
              await pinStore.hasPin({
                'tenant_id': _own,
                'company_id': _own,
              }, '${_own}_next'),
              true,
            );
            expect(
              await const FlutterSecureStorage().read(
                key: 'vehicle_device_binding_v1',
              ),
              isNull,
            );

            await tester.pumpWidget(const SizedBox());
            await tester.runAsync(() => DriverSessionStore.instance.clear());
            activeCompanySessionNotifier.value = null;
            await _mount(tester);
            await _selectNext(tester);
            await enterInlineDriverPin(tester, '482716');
            await _until(
              tester,
              () => find
                  .text('Chauffeurcode ongeldig of verlopen')
                  .evaluate()
                  .isNotEmpty,
            );
            expect(calls, 2);
            // Even a correct local PIN cannot bypass server revocation.
            expect(activeDriverSessionNotifier.value, isNull);
            expect(
              find.text('Chauffeurcode ongeldig of verlopen'),
              findsOneWidget,
            );
            expect(
              find.byKey(const ValueKey('vehicle_personal_pin_confirm')),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          () => _loginClient((request) async {
            if (request.url.path == '/admin/company/drivers/index')
              return _directory(_own);
            expect(request.url.path, '/public/driver/login');
            final body = jsonDecode(request.body) as Map;
            expect(body['company_code'], 'FLX-90001');
            expect(body['driver_code'], '123456');
            expect(body.containsKey('vehicle_device'), false);
            expect(body.containsKey('pin'), false);
            calls++;
            return calls == 1
                ? http.Response(jsonEncode(_login()), 200)
                : http.Response(
                    '{"ok":false,"error":"verification_failed"}',
                    403,
                  );
          }),
        );
      },
    );
}
