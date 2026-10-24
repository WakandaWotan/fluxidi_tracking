import '../support/driver_login_ui_fixture.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company/company_ops_identity.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_duty_identity.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _fluxidi = 'fixture_fluxidi';
const _mario = 'fixture_mario';
const _pickerKey = ValueKey('vehicle_driver_choice');

DriverDutyIdentity _target(String company, {String? tenant}) =>
    DriverDutyIdentity(
      tenantId: tenant ?? company,
      companyId: company,
      driverId: '${company}_driver',
      vehicleId: '${company}_vehicle',
    );

ActiveCompanySession _session(String company) => ActiveCompanySession(
  companyId: company,
  role: 'companyAdmin',
  createdAt: '2026-10-11T10:00:00Z',
  lastUsedAt: '2026-10-11T10:00:00Z',
  companySessionToken: 'fixture-company-token-$company',
  companyCode: company == _fluxidi ? 'FLX-90001' : 'FLX-90002',
  linkMethod: 'company_pairing',
);

Map<String, dynamic> _driver(
  String company,
  String id,
  String name, {
  bool active = true,
  String? tenant,
  String vehicleId = '',
}) => {
  'tenant_id': tenant ?? company,
  'company_id': company,
  'driver_id': id,
  'display_name': name,
  'is_active': active,
  'assigned_vehicle_id': vehicleId,
  // A company name picker is not the operational/ASAP roster gate.
  'weekly_roster': <String, dynamic>{},
  'working': false,
  'live_connected': false,
};

http.Response _directory(
  String company,
  List<Map<String, dynamic>> drivers, {
  String? tenant,
}) => http.Response(
  jsonEncode({
    'ok': true,
    'tenant_id': tenant ?? company,
    'company_id': company,
    'count': drivers.length,
    'drivers': drivers,
  }),
  200,
);

Map<String, dynamic> _binding(String company) => {
  'tenant_id': company,
  'company_id': company,
  'vehicle_id': '${company}_vehicle',
  'device_id': '${company}_device',
  'device_token': 'fixture-device-token-$company',
  'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 600000,
};

Future<void> _drain(WidgetTester tester, {int rounds = 5}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _mount(WidgetTester tester, DriverDutyIdentity? target) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChauffeurLoginPage(
        key: const ValueKey('company_driver_login'),
        deviceDutyTarget: target,
      ),
    ),
  );
  await _drain(tester);
  await openFixedDriverCode(tester);
}

Future<void> _openPicker(WidgetTester tester) async {
  expect(find.byKey(_pickerKey), findsOneWidget);
  await tester.ensureVisible(find.byKey(_pickerKey));
  await tester.tap(find.byKey(_pickerKey));
  await tester.pumpAndSettle();
}

void _expectDirectoryRequest(http.Request request, String company) {
  expect(request.method, 'GET');
  expect(request.url.path, '/admin/company/drivers/index');
  expect(request.url.queryParameters['tenant_id'], company);
  expect(request.url.queryParameters['company_id'], company);
  expect(
    request.headers['authorization'],
    'Bearer fixture-company-token-$company',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppLanguage oldLanguage;
  late ActiveCompanySession? oldCompanySession;
  late CompanyProfile? oldProfile;
  late CompanyOpsLocalSession? oldOpsSession;
  late List<DriverProfile> oldDrivers;

  setUp(() {
    oldLanguage = appLanguageNotifier.value;
    oldCompanySession = activeCompanySessionNotifier.value;
    oldProfile = companyProfileNotifier.value;
    oldOpsSession = companyOpsLocalSessionNotifier.value;
    oldDrivers = driversNotifier.value;
    appLanguageNotifier.value = AppLanguage.nl;
    companyProfileNotifier.value = null;
    companyOpsLocalSessionNotifier.value = null;
    activeCompanySessionNotifier.value = _session(_fluxidi);
    driversNotifier.value = const [];
    FlutterSecureStorage.setMockInitialValues({});
  });

  tearDown(() {
    FlutterSecureStorage.setMockInitialValues({});
    appLanguageNotifier.value = oldLanguage;
    companyProfileNotifier.value = oldProfile;
    companyOpsLocalSessionNotifier.value = oldOpsSession;
    activeCompanySessionNotifier.value = oldCompanySession;
    driversNotifier.value = oldDrivers;
  });

  void prepareView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1100, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('A: old Mario binding cannot supply a Fluxidi company picker', (
    tester,
  ) async {
    prepareView(tester);
    FlutterSecureStorage.setMockInitialValues({
      'vehicle_device_binding_v1': jsonEncode(_binding(_mario)),
    });
    final requests = <http.Request>[];
    await http.runWithClient(
      () async {
        await _mount(tester, _target(_fluxidi));
        await _openPicker(tester);
        expect(find.text('Christophe'), findsOneWidget);
        expect(find.text('Eigen ongebonden'), findsOneWidget);
        expect(find.text('Mario chauffeur'), findsNothing);
        expect(find.text('Inactieve chauffeur'), findsNothing);
        expect(requests, hasLength(1));
        await tester.pumpWidget(const SizedBox());
      },
      () => driverLoginFixtureClient((request) async {
        requests.add(request);
        _expectDirectoryRequest(request, _fluxidi);
        return _directory(_fluxidi, [
          _driver(_fluxidi, '${_fluxidi}_driver', 'Christophe'),
          _driver(_fluxidi, 'own_unassigned', 'Eigen ongebonden'),
          _driver(
            _fluxidi,
            'own_inactive',
            'Inactieve chauffeur',
            active: false,
          ),
        ]);
      }),
    );
  });

  testWidgets('B: Mario company scope lists only its own active directory', (
    tester,
  ) async {
    prepareView(tester);
    activeCompanySessionNotifier.value = _session(_mario);
    await http.runWithClient(
      () async {
        await _mount(tester, _target(_mario));
        await _openPicker(tester);
        expect(find.text('Mario chauffeur'), findsOneWidget);
        expect(find.text('Christophe'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
      () => driverLoginFixtureClient((request) async {
        _expectDirectoryRequest(request, _mario);
        return _directory(_mario, [
          _driver(_mario, '${_mario}_driver', 'Mario chauffeur'),
        ]);
      }),
    );
  });

  testWidgets('foreign vehicle binding is omitted from own fixed-code login', (
    tester,
  ) async {
    prepareView(tester);
    FlutterSecureStorage.setMockInitialValues({
      'vehicle_device_binding_v1': jsonEncode(_binding(_mario)),
    });
    final oldDriverSession = activeDriverSessionNotifier.value;
    activeDriverSessionNotifier.value = null;
    addTearDown(() => activeDriverSessionNotifier.value = oldDriverSession);
    var personalLoginCalls = 0;
    await http.runWithClient(
      () async {
        await _mount(tester, _target(_fluxidi));
        await _openPicker(tester);
        await tester.tap(find.text('Christophe').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('vehicle_pin_login')),
              )
              .onPressed,
          isNull, // Inline PIN login additionally requires six entered digits.
        );
        await tester.enterText(
          find.byType(TextFormField).at(1),
          'fixture-fixed-code',
        );
        final login = find.byKey(const ValueKey('driver_fixed_code_login'));
        await tester.ensureVisible(login);
        await tester.tap(login);
        await _drain(tester, rounds: 10);
        expect(personalLoginCalls, 1);
        expect(activeDriverSessionNotifier.value, isNull);
        expect(find.text('Chauffeurcode ongeldig of verlopen'), findsOneWidget);
        expect(find.byType(ChauffeurLoginPage), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
      () => driverLoginFixtureClient((request) async {
        if (request.url.path == '/admin/company/drivers/index') {
          _expectDirectoryRequest(request, _fluxidi);
          return _directory(_fluxidi, [
            _driver(_fluxidi, '${_fluxidi}_driver', 'Christophe'),
          ]);
        }
        expect(request.url.path, '/public/driver/login');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['company_code'], 'FLX-90001');
        expect(body['driver_code'], 'fixture-fixed-code');
        expect(body.containsKey('vehicle_device'), false);
        personalLoginCalls++;
        return http.Response('{"ok":false,"error":"verification_failed"}', 403);
      }),
    );
  });

  for (final mismatch in ['company', 'tenant']) {
    testWidgets('C/D: mismatched $mismatch target cannot query another scope', (
      tester,
    ) async {
      prepareView(tester);
      var requests = 0;
      final target = mismatch == 'company'
          ? _target(_mario)
          : _target(_fluxidi, tenant: 'foreign_tenant');
      await http.runWithClient(
        () async {
          await _mount(tester, target);
          expect(find.byKey(_pickerKey), findsNothing);
          expect(find.text('Foreign chauffeur'), findsNothing);
          expect(requests, 0);
          await tester.pumpWidget(const SizedBox());
        },
        () => driverLoginFixtureClient((request) async {
          requests++;
          return _directory(_mario, [
            _driver(_mario, 'foreign', 'Foreign chauffeur'),
          ]);
        }),
      );
    });
  }

  testWidgets(
    'missing company token never falls back to an old vehicle binding',
    (tester) async {
      prepareView(tester);
      activeCompanySessionNotifier.value = const ActiveCompanySession(
        companyId: _fluxidi,
        role: 'companyAdmin',
        createdAt: '2026-10-11T10:00:00Z',
        lastUsedAt: '2026-10-11T10:00:00Z',
      );
      FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': jsonEncode(_binding(_mario)),
      });
      var requests = 0;
      await http.runWithClient(
        () async {
          await _mount(tester, null);
          expect(find.byKey(_pickerKey), findsNothing);
          expect(find.text('Old Mario chauffeur'), findsNothing);
          expect(requests, 0);
          await tester.pumpWidget(const SizedBox());
        },
        () => driverLoginFixtureClient((request) async {
          requests++;
          return http.Response(
            jsonEncode({
              'ok': true,
              ..._binding(_mario),
              'drivers': [
                {'driver_id': 'old_mario', 'name': 'Old Mario chauffeur'},
              ],
            }),
            200,
          );
        }),
      );
    },
  );

  testWidgets('E: late Mario response is ignored after switching to Fluxidi', (
    tester,
  ) async {
    prepareView(tester);
    activeCompanySessionNotifier.value = _session(_mario);
    final pendingMario = Completer<http.Response>();
    var marioCalls = 0;
    await http.runWithClient(
      () async {
        await _mount(tester, _target(_mario));
        expect(marioCalls, 1);
        activeCompanySessionNotifier.value = _session(_fluxidi);
        await _mount(tester, _target(_fluxidi));
        pendingMario.complete(
          _directory(_mario, [
            _driver(_mario, 'old_mario', 'Late Mario chauffeur'),
          ]),
        );
        await _drain(tester);
        await _openPicker(tester);
        expect(find.text('Christophe'), findsOneWidget);
        expect(find.text('Late Mario chauffeur'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
      () => driverLoginFixtureClient((request) async {
        if (request.url.queryParameters['company_id'] == _mario) {
          _expectDirectoryRequest(request, _mario);
          marioCalls++;
          return pendingMario.future;
        }
        _expectDirectoryRequest(request, _fluxidi);
        return _directory(_fluxidi, [
          _driver(_fluxidi, '${_fluxidi}_driver', 'Christophe'),
        ]);
      }),
    );
  });

  testWidgets('F: company switch clears the old list and driver selection', (
    tester,
  ) async {
    prepareView(tester);
    await http.runWithClient(
      () async {
        await _mount(tester, _target(_fluxidi));
        await _openPicker(tester);
        await tester.tap(find.text('Christophe').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(find.byKey(_pickerKey))
              .initialValue,
          '${_fluxidi}_driver',
        );
        activeCompanySessionNotifier.value = _session(_mario);
        await _drain(tester);
        expect(find.byKey(_pickerKey), findsNothing);
        expect(find.text('Christophe'), findsNothing);
        await _mount(tester, _target(_mario));
        expect(
          tester
              .widget<DropdownButtonFormField<String>>(find.byKey(_pickerKey))
              .initialValue,
          isNull,
        );
        await _openPicker(tester);
        expect(find.text('Mario chauffeur'), findsOneWidget);
        expect(find.text('Christophe'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
      () => driverLoginFixtureClient((request) async {
        final company = request.url.queryParameters['company_id']!;
        _expectDirectoryRequest(request, company);
        return _directory(company, [
          _driver(
            company,
            '${company}_driver',
            company == _fluxidi ? 'Christophe' : 'Mario chauffeur',
          ),
        ]);
      }),
    );
  });

  testWidgets(
    'G: empty own directory never falls back to global cached drivers',
    (tester) async {
      prepareView(tester);
      driversNotifier.value = const [
        DriverProfile(
          id: 'cached_foreign',
          fullName: 'Cached Mario chauffeur',
          employeeNumber: 'cached',
          phone: '',
          isActive: true,
          companyId: _mario,
        ),
      ];
      await http.runWithClient(
        () async {
          await _mount(tester, _target(_fluxidi));
          expect(find.text('Cached Mario chauffeur'), findsNothing);
          final picker = find.byKey(_pickerKey);
          if (picker.evaluate().isNotEmpty) {
            expect(
              tester
                  .widget<DropdownButtonFormField<String>>(picker)
                  .initialValue,
              isNull,
            );
          }
          await tester.pumpWidget(const SizedBox());
        },
        () => driverLoginFixtureClient((request) async {
          _expectDirectoryRequest(request, _fluxidi);
          return _directory(_fluxidi, []);
        }),
      );
    },
  );

  testWidgets('H: a wrong-scope directory cannot populate the company picker', (
    tester,
  ) async {
    prepareView(tester);
    await http.runWithClient(
      () async {
        await _mount(tester, _target(_fluxidi));
        expect(find.byKey(_pickerKey), findsNothing);
        expect(find.text('Foreign chauffeur'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
      () => driverLoginFixtureClient((request) async {
        _expectDirectoryRequest(request, _fluxidi);
        return _directory(_mario, [
          _driver(_mario, 'foreign', 'Foreign chauffeur'),
        ]);
      }),
    );
  });

  for (final failure in ['mixed_scope', 'http_error', 'malformed']) {
    testWidgets('I: $failure does not display foreign or malformed names', (
      tester,
    ) async {
      prepareView(tester);
      await http.runWithClient(
        () async {
          await _mount(tester, _target(_fluxidi));
          if (find.byKey(_pickerKey).evaluate().isNotEmpty) {
            await _openPicker(tester);
          }
          expect(find.text('Foreign chauffeur'), findsNothing);
          expect(find.text('Malformed chauffeur'), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        () => driverLoginFixtureClient((request) async {
          _expectDirectoryRequest(request, _fluxidi);
          if (failure == 'http_error') {
            return http.Response('{"ok":false,"error":"unauthorized"}', 403);
          }
          return _directory(_fluxidi, [
            if (failure == 'mixed_scope') ...[
              _driver(_fluxidi, 'own', 'Christophe'),
              _driver(_mario, 'foreign', 'Foreign chauffeur'),
            ] else
              {
                'tenant_id': _fluxidi,
                'company_id': _fluxidi,
                'display_name': 'Malformed chauffeur',
                'is_active': true,
              },
          ]);
        }),
      );
    });
  }

  testWidgets(
    'J: standalone vehicle-device flow keeps its bound company list',
    (tester) async {
      prepareView(tester);
      activeCompanySessionNotifier.value = null;
      final binding = _binding(_mario);
      FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': jsonEncode(binding),
      });
      await http.runWithClient(
        () async {
          await _mount(tester, null);
          await _openPicker(tester);
          expect(find.text('Mario voertuigchauffeur'), findsOneWidget);
          expect(find.text('Christophe'), findsNothing);
          await tester.pumpWidget(const SizedBox());
        },
        () => driverLoginFixtureClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/public/vehicle-device/drivers');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['tenant_id'], _mario);
          expect(body['company_id'], _mario);
          return http.Response(
            jsonEncode({
              'ok': true,
              ...binding,
              'company_code': 'FLX-90002',
              'drivers': [
                {'driver_id': 'bound_mario', 'name': 'Mario voertuigchauffeur'},
              ],
            }),
            200,
          );
        }),
      );
    },
  );
}
