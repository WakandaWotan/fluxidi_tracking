import '../support/driver_login_ui_fixture.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';
import 'package:fluxidi_tracking/driver/vehicle_driver_pin_store.dart';

void main() {
  testWidgets(
    'correct remembered PIN still requires server authorization on paired vehicle',
    (tester) async {
      final scope = <String, dynamic>{
        'tenant_id': 't',
        'company_id': 'c',
        'vehicle_id': 'v',
        'device_id': 'dev',
      };
      FlutterSecureStorage.setMockInitialValues({
        'vehicle_device_binding_v1': jsonEncode({
          ...scope,
          'device_token': 'fixture-device',
          'expires_at_ms': DateTime.now().millisecondsSinceEpoch + 100000,
        }),
      });
      await tester.runAsync(
        () => VehicleDriverPinStore().enroll(
          scope,
          'bart',
          'FLX-90001',
          'fixture-fixed-code',
          '482716',
        ),
      );
      final oldLanguage = appLanguageNotifier.value;
      final oldSession = activeDriverSessionNotifier.value;
      appLanguageNotifier.value = AppLanguage.nl;
      activeDriverSessionNotifier.value = null;
      addTearDown(() {
        appLanguageNotifier.value = oldLanguage;
        activeDriverSessionNotifier.value = oldSession;
      });
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var loginCalls = 0;
      final client = driverLoginFixtureClient((request) async {
        if (request.url.path == '/public/vehicle-device/drivers')
          return http.Response(
            jsonEncode({
              'ok': true,
              ...scope,
              'company_code': 'FLX-90001',
              'drivers': [
                {'driver_id': 'bart', 'name': 'Bart'},
              ],
            }),
            200,
          );
        expect(request.url.path, '/public/driver/login');
        final body = jsonDecode(request.body);
        expect(body['driver_code'], 'fixture-fixed-code');
        expect(body['selected_driver_id'], 'bart');
        expect(body['vehicle_device']['device_id'], 'dev');
        expect(body.containsKey('pin'), false);
        loginCalls++;
        return http.Response('{"ok":false,"error":"verification_failed"}', 403);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ChauffeurLoginPage()));
        await tester.pumpAndSettle();
        final choice = find.byKey(const ValueKey('vehicle_driver_choice'));
        await tester.ensureVisible(choice);
        await tester.tap(choice);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Bart').last);
        await tester.pumpAndSettle();
        await enterInlineDriverPin(tester, '482716');
        await tester.runAsync(() async {
          for (var i = 0; i < 200 && loginCalls == 0; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
        });
        await tester.pumpAndSettle();
        expect(loginCalls, 1);
        expect(activeDriverSessionNotifier.value, isNull);
        expect(find.text('Chauffeurcode ongeldig of verlopen'), findsOneWidget);
        expect(find.byType(ChauffeurLoginPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    },
  );
}
