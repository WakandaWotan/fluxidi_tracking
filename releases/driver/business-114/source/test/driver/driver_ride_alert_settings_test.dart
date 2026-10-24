import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_settings_page.dart';
import 'package:fluxidi_tracking/driver/driver_ride_alert_preferences.dart';
import 'package:fluxidi_tracking/driver_session_store.dart';

void main() {
  testWidgets(
    'Flashlight is explicit opt-in, off initially, and cannot cross a driver switch',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final old = activeDriverSessionNotifier.value;
      ActiveDriverSession actor(String id) => ActiveDriverSession(
        driverId: id,
        employeeNumber: '',
        fullName: id,
        phone: '',
        loggedInAt: '',
        updatedAt: '',
        tenantId: 'T',
        companyId: 'C',
        driverSessionToken: 'fixture-$id',
        linkMethod: 'public_driver_login',
      );
      final a = actor('A'), b = actor('B');
      activeDriverSessionNotifier.value = a;
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('fluxidi/vehicle_ride_alert'),
        (call) async {
          calls.add(call.method);
          return call.method == 'torchAvailable' ? true : null;
        },
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/permissions/methods'),
        (call) async {
          calls.add(call.method);
          return call.method == 'requestPermissions' ? {1: 1} : null;
        },
      );
      addTearDown(() {
        activeDriverSessionNotifier.value = old;
        messenger.setMockMethodCallHandler(
          const MethodChannel('fluxidi/vehicle_ride_alert'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('flutter.baseflow.com/permissions/methods'),
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(home: DriverRideAlertSettingsPage(session: a)),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      final toggle = find.byKey(const ValueKey('driver-ride-flash-opt-in'));
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      expect(calls, ['torchAvailable']);
      await tester.tap(toggle);
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      expect(calls, contains('requestPermissions'));
      expect(await DriverRideAlertPreferences().flashlight(a), isTrue);
      expect(await DriverRideAlertPreferences().flashlight(b), isFalse);
      activeDriverSessionNotifier.value = b;
      await tester.pump();
      expect(tester.widget<SwitchListTile>(toggle).onChanged, isNull);
      expect(calls.where((v) => v == 'play'), isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
