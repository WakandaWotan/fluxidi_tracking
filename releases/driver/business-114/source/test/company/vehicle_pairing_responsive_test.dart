import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxidi_tracking/app_config.dart';
import 'package:fluxidi_tracking/app_strings.dart';
import 'package:fluxidi_tracking/company_session_store.dart';
import 'package:fluxidi_tracking/vehicle_management_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'dart:io';

void main() {
  for (final screen in [const Size(430, 900), const Size(1000, 1800), const Size(1800, 1000)]) {
  testWidgets('vehicle pairing visible on '+screen.toString(), (tester) async {
    final oldDrivers = driversNotifier.value;
    final oldVehicles = vehiclesNotifier.value;
    final oldSession = activeCompanySessionNotifier.value;
    final oldLanguage = appLanguageNotifier.value;
    addTearDown(() {
      driversNotifier.value = oldDrivers;
      vehiclesNotifier.value = oldVehicles;
      activeCompanySessionNotifier.value = oldSession;
      appLanguageNotifier.value = oldLanguage;
    });
    for (final name in [
      'plugins.flutter.io/shared_preferences',
      'plugins.it_nomads.com/flutter_secure_storage',
      'plugins.flutter.io/path_provider',
    ]) {
      final channel = MethodChannel(name);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async =>
              call.method == 'getAll' ? <String, Object>{} :
              call.method == 'getApplicationDocumentsDirectory' ? Directory.systemTemp.path : null);
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    }
    activeCompanySessionNotifier.value = const ActiveCompanySession(
      companyId: 'taxi-mario', role: 'companyAdmin',
      createdAt: '2026-10-01', lastUsedAt: '2026-10-01',
      companySessionToken: 'fixture-token',
    );
    appLanguageNotifier.value = AppLanguage.nl;
    driversNotifier.value = [
      for (final id in ['driver-a', 'driver-b', 'driver-c'])
        DriverProfile(id: id, fullName: id, employeeNumber: id,
          phone: '', isActive: true, companyId: 'taxi-mario',
          assignedVehicleId: 'fixture-car'),
      DriverProfile(id: 'other-driver', fullName: 'other-driver',
        employeeNumber: 'other-driver', phone: '', isActive: true,
        companyId: 'other-company', assignedVehicleId: 'fixture-car'),
    ];
    vehiclesNotifier.value = [const VehicleProfile(
      id: 'fixture-car', vehicleName: 'Fixture Corolla',
      brandModel: 'Toyota Corolla', licensePlate: '', color: '',
      passengerCapacity: 4, luggageCapacity: 3, tierId: 'comfort',
      isActive: true, driverId: 'driver-a', companyId: 'taxi-mario',
      primaryPhotoRef: '', galleryPhotoRefs: [],
    )];
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: VehicleManagementPage(
        limousineEntitlementLoader: _noLimousine,
      )));
      await tester.pumpAndSettle();
      final pairing=find.byKey(const ValueKey('vehicle_pairing_fixture-car'));
      await tester.scrollUntilVisible(pairing, 350, scrollable: find.byType(Scrollable).first);
      expect(pairing, findsOneWidget);
      await tester.ensureVisible(pairing);
      await tester.pumpAndSettle();
      expect(find.text('Toestel koppelen'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, () => MockClient((request) async => http.Response('{}', 200)));
  });
  }
}

Future<bool> _noLimousine(String _) async => false;

