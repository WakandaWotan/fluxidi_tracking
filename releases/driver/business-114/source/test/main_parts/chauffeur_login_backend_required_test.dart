import '../support/driver_login_ui_fixture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fluxidi_tracking/main.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final mode in ['rejected', 'offline', 'missing_token']) {
    testWidgets('$mode login cannot use matching cached driver as authentication', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      for (final channel in ['plugins.flutter.io/shared_preferences', 'plugins.flutter.io/flutter_secure_storage']) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async => call.method == 'getAll' ? <String,Object>{} : call.method == 'readAll' ? <String,String>{} : null);
        addTearDown(() => messenger.setMockMethodCallHandler(MethodChannel(channel), null));
      }
      final oldDrivers = driversNotifier.value;
      final oldLanguage = appLanguageNotifier.value;
      final oldSession = activeDriverSessionNotifier.value;
      addTearDown(() { driversNotifier.value = oldDrivers; appLanguageNotifier.value = oldLanguage; activeDriverSessionNotifier.value = oldSession; });
      appLanguageNotifier.value = AppLanguage.nl;
      activeDriverSessionNotifier.value = null;
      driversNotifier.value = const [DriverProfile(id: 'driver_fixture', companyId: 'FLX-90001', fullName: 'Fixture', employeeNumber: '123456', phone: '', isActive: true)];
      tester.view.physicalSize = const Size(1000, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var calls = 0;
      final client = driverLoginFixtureClient((request) async {
        calls++;
        expect(request.url.path, '/public/driver/login');
        if (mode == 'offline') throw http.ClientException('connection refused');
        return mode == 'missing_token'
          ? http.Response('{"ok":true,"role":"driver","tenant_id":"FLX-90001","company_id":"FLX-90001","driver_id":"driver_fixture"}', 200)
          : http.Response('{"ok":false,"error":"verification_failed"}', 403);
      });
      await http.runWithClient(() async {
        await tester.pumpWidget(const MaterialApp(home: ChauffeurLoginPage()));
        await openFixedDriverCode(tester);
        await tester.enterText(find.byType(TextFormField).at(0), 'FLX-90001');
        await tester.enterText(find.byType(TextFormField).at(1), '123456');
        final button = find.byKey(const ValueKey('driver_fixed_code_login'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.byType(ChauffeurLoginPage), findsOneWidget);
        expect(activeDriverSessionNotifier.value, isNull);
        expect(find.text(mode == 'offline' ? 'Geen verbinding met de aanmeldserver. Controleer het netwerk.' : mode == 'rejected' ? 'Chauffeurcode ongeldig of verlopen' : 'Chauffeurlogin mislukt. Controleer bedrijfscode en chauffeurcode.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, () => client);
    });
  }
}
