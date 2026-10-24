import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/driver_personal_pin_page.dart';
import 'package:fluxidi_tracking/driver/driver_pin_verified_session.dart';
import 'package:fluxidi_tracking/driver/vehicle_driver_pin_store.dart';

const scope = <String, dynamic>{
  'tenant_id': 'own-tenant',
  'company_id': 'own-company',
};
ActiveDriverSession session(
  String driver, {
  String method = 'public_driver_login',
}) => ActiveDriverSession(
  driverId: driver,
  employeeNumber: 'not-used-as-a-credential',
  fullName: driver,
  phone: '',
  loggedInAt: '',
  updatedAt: '',
  tenantId: 'own-tenant',
  companyId: 'own-company',
  companyCode: 'FLX-90001',
  driverSessionToken: 'current-$driver',
  driverSessionExpiresAtUtc: DateTime.now()
      .add(const Duration(hours: 1))
      .toUtc()
      .toIso8601String(),
  linkMethod: method,
);
Map<String, dynamic> reply(String driver) => {
  'ok': true,
  'role': 'driver',
  ...scope,
  'driver_id': driver,
  'driver_session_token': 'new-verified-$driver',
};
Future<void> drain(WidgetTester tester, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

Future<void> mount(
  WidgetTester tester, {
  bool freshQr = false,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final captured = activeDriverSessionNotifier.value!;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DriverPersonalPinPage(
                  session: captured,
                  freshVerification: freshQr
                      ? FreshDriverPinSetup(captured)
                      : null,
                ),
              ),
            ),
            child: const Text('open-settings'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open-settings'));
  await drain(tester);
}

Future<void> fill(
  WidgetTester tester,
  String action, {
  bool code = true,
}) async {
  await tester.tap(find.byKey(ValueKey(action)));
  await tester.pump();
  if (code)
    await tester.enterText(
      find.byKey(const ValueKey('personal-pin-driver-code')),
      'fixed-christophe',
    );
  await tester.enterText(
    find.byKey(const ValueKey('personal-pin-new')),
    '837291',
  );
  await tester.enterText(
    find.byKey(const ValueKey('personal-pin-confirm')),
    '837291',
  );
  await tester.ensureVisible(find.byKey(const ValueKey('personal-pin-save')));
  await tester.tap(find.byKey(const ValueKey('personal-pin-save')));
}

void main() {
  late ActiveDriverSession? previous;
  late AppLanguage language;
  setUp(() {
    previous = activeDriverSessionNotifier.value;
    language = appLanguageNotifier.value;
    appLanguageNotifier.value = AppLanguage.nl;
    activeDriverSessionNotifier.value = session('Christophe');
    FlutterSecureStorage.setMockInitialValues({});
  });
  tearDown(() {
    activeDriverSessionNotifier.value = previous;
    appLanguageNotifier.value = language;
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final action in ['set', 'change', 'reset', 'qr-reset']) {
    testWidgets(
      '$action reauthenticates exact driver, preserves session and other driver PIN',
      (tester) async {
        final store = DriverPersonalPinStore();
        await tester.runAsync(() async {
          await store.enroll(
            scope,
            'TestDriver',
            'FLX-90001',
            'fixed-test',
            '482716',
          );
          await store.rememberDriver(scope, 'TestDriver', 'TestDriver');
          if (action != 'set') {
            await store.enroll(
              scope,
              'Christophe',
              'FLX-90001',
              'fixed-christophe',
              '726184',
            );
            await store.rememberDriver(scope, 'Christophe', 'Christophe');
          }
        });
        final original = activeDriverSessionNotifier.value;
        var requests = 0;
        await http.runWithClient(
          () async {
            await mount(
              tester,
              freshQr: action == 'qr-reset',
              width: action == 'set' ? 320 : 800,
            );
            await fill(
              tester,
              'personal-pin-${action == 'qr-reset' ? 'reset' : action}',
              code: action != 'qr-reset',
            );
            await drain(tester, 100);
            expect(requests, 1);
            expect(find.byType(DriverPersonalPinPage), findsNothing);
            expect(
              identical(activeDriverSessionNotifier.value, original),
              isTrue,
            );
            await tester.runAsync(() async {
              final restored = DriverPersonalPinStore();
              expect(
                (await restored.unlock(
                  scope,
                  'Christophe',
                  '837291',
                ))?.driverCode,
                'fixed-christophe',
              );
              expect(
                await restored.unlock(scope, 'Christophe', '482716'),
                isNull,
              );
              expect(
                (await restored.unlock(
                  scope,
                  'TestDriver',
                  '482716',
                ))?.driverCode,
                'fixed-test',
              );
              if (action != 'set')
                expect(
                  await restored.unlock(scope, 'Christophe', '726184'),
                  isNull,
                );
              final values = await const FlutterSecureStorage().readAll();
              expect(values.values.any((v) => v.contains('837291')), isFalse);
            });
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((request) async {
            requests++;
            expect(request.url.path, '/public/driver/login');
            expect(jsonDecode(request.body), {
              'company_code': 'FLX-90001',
              'driver_code': 'fixed-christophe',
              'selected_driver_id': 'Christophe',
            });
            return http.Response(jsonEncode(reply('Christophe')), 200);
          }),
        );
      },
    );
  }

  for (final invalid in [
    'driver_id',
    'tenant_id',
    'company_id',
    'role',
    'driver_session_token',
    '403',
    'network',
  ]) {
    testWidgets('PIN cannot be saved after $invalid failure', (tester) async {
      await http.runWithClient(
        () async {
          await mount(tester);
          await fill(tester, 'personal-pin-set');
          await drain(tester);
          expect(
            await DriverPersonalPinStore().hasPin(scope, 'Christophe'),
            isFalse,
          );
          expect(
            find.byKey(const ValueKey('personal-pin-error')),
            findsOneWidget,
          );
          expect(
            activeDriverSessionNotifier.value?.driverSessionToken,
            'current-Christophe',
          );
          await tester.pumpWidget(const SizedBox());
        },
        () => MockClient((request) async {
          if (invalid == 'network')
            throw http.ClientException('private details must not leak');
          final data = reply('Christophe');
          if (invalid != '403')
            data[invalid] = invalid == 'driver_session_token' ? '' : 'foreign';
          return http.Response(jsonEncode(data), invalid == '403' ? 403 : 200);
        }),
      );
    });
  }

  for (final driver in ['Christophe', 'TestDriver', 'NewDriver']) {
    testWidgets(
      'first verified QR for $driver saves PIN without asking long code',
      (tester) async {
        activeDriverSessionNotifier.value = session(
          driver,
          method: 'driver_pairing_code',
        );
        final before = activeDriverSessionNotifier.value;
        await http.runWithClient(
          () async {
            await mount(tester, freshQr: true);
            await fill(tester, 'personal-pin-set', code: false);
            await drain(tester, 30);
            expect(
              await DriverPersonalPinStore().hasPin(scope, driver),
              isTrue,
            );
            expect(activeDriverSessionNotifier.value, same(before));
            expect(
              find.byKey(const ValueKey('personal-pin-driver-code')),
              findsNothing,
            );
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
          },
          () => MockClient((request) async {
            expect(request.url.path, '/public/driver/status');
            expect(request.url.hasQuery, isFalse);
            return http.Response(
              jsonEncode({
                'ok': true,
                ...scope,
                'driver_id': driver,
                'driver': {'driver_id': driver, 'is_active': true},
              }),
              200,
            );
          }),
        );
      },
    );
  }

  testWidgets(
    'late QR authority reply after switch cannot enroll another driver',
    (tester) async {
      final pending = Completer<http.Response>();
      await http.runWithClient(() async {
        await mount(tester, freshQr: true);
        await fill(tester, 'personal-pin-set', code: false);
        activeDriverSessionNotifier.value = session('TestDriver');
        pending.complete(
          http.Response(
            jsonEncode({
              'ok': true,
              ...scope,
              'driver_id': 'Christophe',
              'driver': {'driver_id': 'Christophe', 'is_active': true},
            }),
            200,
          ),
        );
        await drain(tester);
        expect(
          await DriverPersonalPinStore().hasPin(scope, 'Christophe'),
          isFalse,
        );
        expect(
          await DriverPersonalPinStore().hasPin(scope, 'TestDriver'),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((_) => pending.future));
    },
  );

  testWidgets(
    'late server reply after driver switch cannot change either PIN',
    (tester) async {
      final pending = Completer<http.Response>();
      await http.runWithClient(() async {
        await mount(tester);
        await fill(tester, 'personal-pin-set');
        await tester.pump();
        activeDriverSessionNotifier.value = session('TestDriver');
        pending.complete(http.Response(jsonEncode(reply('Christophe')), 200));
        await drain(tester);
        expect(
          await DriverPersonalPinStore().hasPin(scope, 'Christophe'),
          isFalse,
        );
        expect(
          await DriverPersonalPinStore().hasPin(scope, 'TestDriver'),
          isFalse,
        );
        expect(find.byKey(const ValueKey('personal-pin-save')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, () => MockClient((_) => pending.future));
    },
  );

  testWidgets('company preview has no driver PIN writer', (tester) async {
    activeDriverSessionNotifier.value = session(
      'Christophe',
      method: kCompanyAdminDriverViewLinkMethod,
    );
    await mount(tester);
    expect(find.byKey(const ValueKey('personal-pin-set')), findsNothing);
    expect(find.byKey(const ValueKey('personal-pin-error')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
