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
  testWidgets('vehicle editor lists all company shift drivers, not one reverse link', (tester) async {
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
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: VehicleManagementPage(
        openVehicleId: 'fixture-car',
        limousineEntitlementLoader: _noLimousine,
      )));
      await tester.pumpAndSettle();
      if (find.byKey(const ValueKey('vehicle_fallback_picker')).evaluate().isEmpty) {
        await tester.tap(find.text('Bewerken').first);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
      }
      expect(find.byKey(const ValueKey('vehicle_fallback_picker')), findsOneWidget);
      for (final id in ['driver-a', 'driver-b', 'driver-c']) {
        expect(find.textContaining(id), findsWidgets);
      }
      expect(find.textContaining('other-driver'), findsNothing);
      expect(find.text('Gekoppelde chauffeurs'), findsOneWidget);
    }, () => MockClient((request) async => http.Response('{}', 200)));
  });
}

Future<bool> _noLimousine(String _) async => false;
