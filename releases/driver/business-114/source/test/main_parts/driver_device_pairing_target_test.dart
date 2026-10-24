import '../support/driver_login_ui_fixture.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_duty_identity.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _fixtureCompanySession = ActiveCompanySession(
  companyId: 'company',
  role: 'companyAdmin',
  createdAt: '',
  lastUsedAt: '',
  companySessionToken: 'fixture-company-admin',
  companyCode: 'FLX-90001',
);

http.Response? _companyDirectoryFixture(http.Request request) {
  if (request.url.path != '/admin/company/drivers/index') return null;
  expect(request.method, 'GET');
  expect(request.url.queryParameters['tenant_id'], 'company');
  expect(request.url.queryParameters['company_id'], 'company');
  expect(request.headers['authorization'], 'Bearer fixture-company-admin');
  return http.Response(
    jsonEncode({
      'ok': true,
      'tenant_id': 'company',
      'company_id': 'company',
      'drivers': [
        {
          'driver_id': 'selected',
          'display_name': 'Selected',
          'is_active': true,
          'tenant_id': 'company',
          'company_id': 'company',
        },
      ],
    }),
    200,
  );
}

Future<void> _selectFixtureDriver(WidgetTester tester) async {
  await openFixedDriverCode(tester);
  if (!const bool.fromEnvironment('COMPANY_VEHICLE_OPERATIONS_UI')) return;
  final picker = find.byKey(const ValueKey('vehicle_driver_choice'));
  for (var attempt = 0; attempt < 40 && picker.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(picker, findsOneWidget);
  await tester.ensureVisible(picker);
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Selected').last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final field in [
    'tenant_id',
    'company_id',
    'driver_id',
    'assigned_vehicle_id',
  ]) {
    testWidgets('server $field mismatch cannot save or replace native owner', (
      tester,
    ) async {
      final oldLanguage = appLanguageNotifier.value;
      final oldSession = activeDriverSessionNotifier.value;
      final oldOwner = nativeDriverDutySessionNotifier.value;
      final oldCompanySession = activeCompanySessionNotifier.value;
      final oldOpsSession = companyOpsLocalSessionNotifier.value;
      activeCompanySessionNotifier.value = _fixtureCompanySession;
      companyOpsLocalSessionNotifier.value = null;
      addTearDown(() {
        activeCompanySessionNotifier.value = oldCompanySession;
        companyOpsLocalSessionNotifier.value = oldOpsSession;
      });
      addTearDown(() {
        appLanguageNotifier.value = oldLanguage;
        activeDriverSessionNotifier.value = oldSession;
        nativeDriverDutySessionNotifier.value = oldOwner;
      });
      appLanguageNotifier.value = AppLanguage.nl;
      final preview = ActiveDriverSession(
        driverId: 'selected',
        employeeNumber: '1',
        fullName: 'Selected',
        phone: '',
        loggedInAt: '',
        updatedAt: '',
        tenantId: 'company',
        companyId: 'company',
        assignedVehicleId: 'vehicle',
        driverSessionToken: 'fixture-preview',
        linkMethod: kOperatorMintDriverLinkMethod,
      );
      activeDriverSessionNotifier.value = preview;
      nativeDriverDutySessionNotifier.value = null;
      final writes = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
        (call) async {
          // Vehicle-device mode reads the existing encrypted binding before
          // login. A read must not be mistaken for a persisted assignment.
          if (!['read', 'containsKey', 'readAll'].contains(call.method))
            writes.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          null,
        ),
      );
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final response = {
        'ok': true,
        'role': 'driver',
        'tenant_id': 'company',
        'company_id': 'company',
        'driver_id': 'selected',
        'assigned_vehicle_id': 'vehicle',
        'driver_name': 'Selected',
        'driver_session_token': 'fixture-real',
        'expires_in': 3600,
        field: 'other',
      };
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            const MaterialApp(
              home: ChauffeurLoginPage(
                deviceDutyTarget: DriverDutyIdentity(
                  tenantId: 'company',
                  companyId: 'company',
                  driverId: 'selected',
                  vehicleId: 'vehicle',
                ),
                deviceDutyDriverName: 'Selected',
              ),
            ),
          );
          await _selectFixtureDriver(tester);
          await tester.enterText(find.byType(TextFormField).at(0), 'FLX-90001');
          await tester.enterText(find.byType(TextFormField).at(1), '123456');
          final button = find.byKey(const ValueKey('driver_fixed_code_login'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          // Drain native storage completion just as the successful-login case
          // below does. Keep HTTP in its fixture zone and the original timeout.
          for (
            var attempt = 0;
            attempt < 40 &&
                find
                    .textContaining(
                      'Deze login hoort niet bij de gekozen chauffeur',
                    )
                    .evaluate()
                    .isEmpty;
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 100));
            if (find.text('Persoonlijke pincode instellen').evaluate().isNotEmpty) {
              await tester.tap(find.text('Annuleren'));
              await tester.pump(const Duration(milliseconds: 400));
            }
          }
          await tester.pumpAndSettle();
          expect(find.byType(ChauffeurLoginPage), findsOneWidget);
          expect(
            find.textContaining(
              'Deze login hoort niet bij de gekozen chauffeur',
            ),
            findsOneWidget,
          );
          expect(activeDriverSessionNotifier.value, same(preview));
          expect(nativeDriverDutySessionNotifier.value, isNull);
          expect(writes, isEmpty);
          await tester.pumpWidget(const SizedBox());
        },
        () => driverLoginFixtureClient((request) async {
          final directory = _companyDirectoryFixture(request);
          if (directory != null) return directory;
          expect(request.url.path, '/public/driver/login');
          return http.Response(jsonEncode(response), 200);
        }),
      );
    });
  }
  testWidgets(
    'exact server actor saves real secure login and opens gated driver mode',
    (tester) async {
      final root = Directory.systemTemp.createTempSync(
        'fluxidi-pairing-success-test-',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => root.path,
      );
      FlutterSecureStorage.setMockInitialValues({});
      final oldSession = activeDriverSessionNotifier.value;
      final oldRole = appRoleNotifier.value;
      final oldLanguage = appLanguageNotifier.value;
      final oldOwner = nativeDriverDutySessionNotifier.value;
      final oldCompanySession = activeCompanySessionNotifier.value;
      final oldOpsSession = companyOpsLocalSessionNotifier.value;
      activeCompanySessionNotifier.value = _fixtureCompanySession;
      companyOpsLocalSessionNotifier.value = null;
      appLanguageNotifier.value = AppLanguage.nl;
      activeDriverSessionNotifier.value = null;
      nativeDriverDutySessionNotifier.value = null;
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        FlutterSecureStorage.setMockInitialValues({});
        activeDriverSessionNotifier.value = oldSession;
        appRoleNotifier.value = oldRole;
        appLanguageNotifier.value = oldLanguage;
        nativeDriverDutySessionNotifier.value = oldOwner;
        activeCompanySessionNotifier.value = oldCompanySession;
        companyOpsLocalSessionNotifier.value = oldOpsSession;
        messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
        tester.view.reset();
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      await http.runWithClient(
        () async {
          await tester.pumpWidget(
            MaterialApp(
              home: ChauffeurLoginPage(
                deviceDutyTarget: const DriverDutyIdentity(
                  tenantId: 'company',
                  companyId: 'company',
                  driverId: 'selected',
                  vehicleId: 'vehicle',
                ),
                driverDashboardBuilder: (_) =>
                    const Scaffold(body: Text('verified driver fixture')),
              ),
            ),
          );
          await _selectFixtureDriver(tester);
          await tester.enterText(find.byType(TextFormField).at(0), 'FLX-90001');
          await tester.enterText(find.byType(TextFormField).at(1), '123456');
          final button = find.byKey(const ValueKey('driver_fixed_code_login'));
          await tester.ensureVisible(button);
          await tester.tap(button);
          // Secure storage and filesystem completion use the real event loop.
          // pumpAndSettle alone only advances the widget test's fake clock.
          for (
            var attempt = 0;
            attempt < 40 &&
                find.text('verified driver fixture').evaluate().isEmpty;
            attempt++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 50)),
            );
            await tester.pump(const Duration(milliseconds: 100));
            if (find.text('Persoonlijke pincode instellen').evaluate().isNotEmpty) {
              await tester.tap(find.text('Annuleren'));
              await tester.pump(const Duration(milliseconds: 400));
            }
          }
          expect(find.text('verified driver fixture'), findsOneWidget);
          expect(
            isNativeDriverDutySession(activeDriverSessionNotifier.value),
            isTrue,
          );
          expect(activeDriverSessionNotifier.value?.driverId, 'selected');
          // Merely logging in does not pretend a native service has started.
          expect(nativeDriverDutySessionNotifier.value, isNull);
          for (final file in root.listSync(recursive: true).whereType<File>()) {
            expect(
              file.readAsStringSync(),
              isNot(contains('fixture-real-bearer')),
            );
          }
          await tester.pumpWidget(const SizedBox());
        },
        () => driverLoginFixtureClient((request) async {
          final directory = _companyDirectoryFixture(request);
          if (directory != null) return directory;
          // The real login is followed by the existing authenticated activation
          // gate. Model both the status and the explicit legacy-duty policy.
          if (request.url.path == '/public/driver/status') {
            expect(request.method, 'GET');
            expect(request.headers['authorization'], 'Bearer fixture-real-bearer');
            return http.Response(jsonEncode({
              'ok': true, 'tenant_id': 'company', 'company_id': 'company',
              'driver_id': 'selected', 'driver': {
                'driver_id': 'selected', 'is_active': true,
                'availability_status': 'available', 'assigned_vehicle_id': 'vehicle',
              },
            }), 200);
          }
          if (request.url.path == '/public/driver/vehicle-duty-state') {
            expect(request.method, 'POST');
            expect(request.headers['authorization'], 'Bearer fixture-real-bearer');
            return http.Response(jsonEncode({
              'ok': false, 'error': 'vehicle_duty_not_configured',
            }), 409);
          }
          expect(request.url.path, '/public/driver/login');
          return http.Response(
            jsonEncode({
              'ok': true,
              'role': 'driver',
              'tenant_id': 'company',
              'company_id': 'company',
              'driver_id': 'selected',
              'assigned_vehicle_id': 'vehicle',
              'driver_name': 'Selected',
              'driver_session_token': 'fixture-real-bearer',
              'expires_in': 3600,
            }),
            200,
          );
        }),
      );
    },
  );
}
